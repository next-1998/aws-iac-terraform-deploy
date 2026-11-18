############################################################
# ALB (선택) — 이 리소스가 필요할 때 여기서 만듭니다 (network-base에서 만들지 않음)
#
#   alb_internal = true  (기본값): 내부용. edge 서브넷, private 존에 레코드
#   alb_internal = false          : 외부용. public 서브넷, public 존 + private 존에 레코드
#                                   01-network enable_public = true여야 함
#   인증서가 있으면: 80 → 443 리다이렉트, 443 → EC2 / 없으면: 80 → EC2
############################################################

locals {
  internet_facing = var.enable_alb && !var.alb_internal

  alb_subnet_ids = var.alb_subnet_ids != null ? var.alb_subnet_ids : values(
    var.alb_internal ? local.network.subnets.ids.edge : local.network.subnets.ids.public
  )

  # ALB 접근 허용 출발지: 지정하지 않으면 내부용은 VPC + 사내망, 외부용은 인터넷 전체
  alb_ingress_cidrs = var.alb_ingress_cidrs != null ? var.alb_ingress_cidrs : (
    var.alb_internal ? distinct(concat(local.base.vpc_cidrs, local.routing.corp_cidrs)) : ["0.0.0.0/0"]
  )
  alb_ingress_pl_ids = [for n in var.alb_ingress_prefix_lists : local.routing.prefix_list_ids[n]]

  use_https = var.alb_certificate_arn != null
  alb_ports = local.use_https ? tolist([80, 443]) : tolist([80])
  tg_arn    = try(module.alb_tg[0].target_group_arn["app"], null)

  # 후보 listener를 모두 정의하고, 조건에 맞는 것만 골라 씀
  listener_candidates = {
    http_redirect = {
      port     = 80
      protocol = "HTTP"
      redirect = { port = "443", protocol = "HTTPS", status_code = "HTTP_301" }
    }
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = var.alb_certificate_arn
      forward         = { arn = local.tg_arn }
    }
    http_forward = {
      port     = 80
      protocol = "HTTP"
      forward  = { arn = local.tg_arn }
    }
  }
  listener_keys = local.use_https ? ["http_redirect", "https"] : ["http_forward"]
  alb_listeners = {
    for k, v in local.listener_candidates : k => v
    if var.enable_alb && contains(local.listener_keys, k)
  }

  # 레코드를 넣을 존: 내부용 → private, 외부용 → public + private (VPC 안에서는 private 존만 조회되므로)
  record_zones = var.enable_alb && var.alb_record_name != null && local.dns.zone_name != null ? merge(
    { private = local.dns.private_zone_id },
    local.internet_facing ? { public = local.dns.public_zone_id } : {},
  ) : {}
}

module "alb_sg" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload"
  count  = var.enable_alb ? 1 : 0

  name   = "${local.prefix}-alb-sg"
  vpc_id = local.base.vpc_id
  default_security_group_rules = {
    ingress = [for p in local.alb_ports : {
      from_port       = p
      to_port         = p
      protocol        = "tcp"
      cidr_blocks     = length(var.alb_ingress_prefix_lists) > 0 && var.alb_ingress_cidrs == null ? null : local.alb_ingress_cidrs
      prefix_list_ids = length(local.alb_ingress_pl_ids) > 0 ? local.alb_ingress_pl_ids : null
      description     = "HTTP(S) to ALB"
    }]
    egress = [{
      from_port   = var.app_port
      to_port     = var.app_port
      protocol    = "tcp"
      cidr_blocks = values(var.common.subnet_cidrs)
      description = "to ${local.prefix} EC2"
    }]
  }

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_alb"
}

module "alb" {
  source = "../../../aws-iac-terraform-module/module/network/aws-elb-workload/lb"
  count  = var.enable_alb ? 1 : 0

  name                             = "${local.prefix}-alb"
  load_balancer_type               = "application"
  internal                         = var.alb_internal
  subnet_id_list                   = local.alb_subnet_ids
  lb_sg_id_list                    = [module.alb_sg[0].securitygroup_id]
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = var.alb_deletion_protection
  drop_invalid_header_fields       = true

  # 접근 로그: <버킷>/<site>/alb/<ALB 이름>/AWSLogs/...
  access_logs = var.access_log_bucket != null ? {
    bucket  = var.access_log_bucket
    prefix  = "${local.site}/alb/${local.prefix}-alb"
    enabled = "true"
  } : {}

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}

# WAF (선택, 기본값 끔)
resource "aws_wafv2_web_acl_association" "alb" {
  count        = var.enable_alb && var.waf_acl_arn != null ? 1 : 0
  resource_arn = module.alb[0].elb.arn
  web_acl_arn  = var.waf_acl_arn
}

module "alb_tg" {
  source = "../../../aws-iac-terraform-module/module/network/aws-elb-workload/lb-target"
  count  = var.enable_alb ? 1 : 0

  vpc_id = local.base.vpc_id
  target_groups = {
    app = {
      name     = "${local.prefix}-tg"
      port     = var.app_port
      protocol = "HTTP"
      health_check = {
        path = var.health_check_path
      }
    }
  }
  target_id   = module.ec2.ec2_instance.id
  target_port = var.app_port

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}

module "alb_listener" {
  source = "../../../aws-iac-terraform-module/module/network/aws-elb-workload/lb-listeners"
  count  = var.enable_alb ? 1 : 0

  elb            = module.alb[0].elb
  listeners      = local.alb_listeners
  listener_rules = {}

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}

module "alb_record" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-route53-workload/records"
  for_each = local.record_zones

  zone_id   = each.value
  zone_name = local.dns.zone_name
  records = [{
    name = var.alb_record_name
    type = "A"
    alias = {
      name                   = module.alb[0].elb.dns_name
      zone_id                = module.alb[0].elb.zone_id
      evaluate_target_health = true
    }
  }]
}

resource "terraform_data" "alb_checks" {
  count = var.enable_alb ? 1 : 0

  lifecycle {
    # ALB는 AWS 규칙상 서로 다른 AZ의 서브넷이 2개 이상 필요합니다.
    precondition {
      condition     = length(local.alb_subnet_ids) >= 2
      error_message = "ALB는 AZ 2개 이상이 필요합니다. 현재 사용 가능한 서브넷 ${length(local.alb_subnet_ids)}개 (01-network의 az_count를 2 이상으로 하거나 enable_alb = false)."
    }
    # 외부용 ALB는 public 서브넷(IGW)이 있어야 합니다.
    precondition {
      condition     = var.alb_internal || local.network.routing.has_public
      error_message = "외부용 ALB(alb_internal = false)는 01-network의 enable_public = true가 필요합니다. public을 끈 사이트는 인터넷을 쓰지 않습니다."
    }
  }
}
