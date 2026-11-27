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

  # ALB 서브넷: alb_subnet_ids(직접) > 태그 Use-alb = true 서브넷 (Tier: 내부용 private, 외부용 public. 배포 때 조회)
  #             > 01-network edge / public (태그 서브넷이 없을 때)
  alb_subnet_ids = var.alb_subnet_ids != null ? var.alb_subnet_ids : (
    [for az in local.network.base.azs : try(module.alb_subnet_use[0].found, false) ? module.alb_subnet_use[0].subnet_ids[az] : lookup(var.alb_internal ? local.network.subnets.ids.edge : local.network.subnets.ids.public, az, null)] # 개수(AZ)는 plan 전에 정해짐 (없으면 null → 검사에서 막힘)
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
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/security-group"
  count  = var.enable_alb ? 1 : 0

  name        = "${local.np}-sg-${local.purpose}alb-01"
  description = "ALB for ${local.prefix}"
  vpc_id      = local.base.vpc_id

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_alb"
}

module "alb" {
  source = "../../../aws-iac-terraform-module/module/network/aws-elb-workload/lb"
  count  = var.enable_alb ? 1 : 0

  name                             = "${local.np}-alb-${local.purpose}-01"
  load_balancer_type               = "application"
  internal                         = var.alb_internal
  subnet_id_list                   = local.alb_subnet_ids
  lb_sg_id_list                    = [module.alb_sg[0].securitygroup_id]
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = var.alb_deletion_protection
  drop_invalid_header_fields       = true

  # 접근 로그: <버킷>/<VPC 이름>/elb/<ALB 이름>/access-logs/AWSLogs/... (로그 경로 규칙)
  access_logs = var.access_log_bucket != null ? {
    bucket  = var.access_log_bucket
    prefix  = "${local.base.vpc_name}/elb/${local.np}-alb-${local.purpose}-01/access-logs"
    enabled = "true"
  } : {}

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}

# WAF (선택, 기본값 끔)
module "alb_waf" {
  source = "../../../aws-iac-terraform-module/module/network/aws-elb-workload/waf-association"
  count  = var.enable_alb && var.waf_acl_arn != null ? 1 : 0

  resource_arn = module.alb[0].elb.arn
  web_acl_arn  = var.waf_acl_arn
}

module "alb_tg" {
  source = "../../../aws-iac-terraform-module/module/network/aws-elb-workload/target-group"
  count  = var.enable_alb ? 1 : 0

  vpc_id = local.base.vpc_id
  target_groups = {
    app = {
      name     = "${local.np}-tg-${local.purpose}-01"
      port     = var.app_port
      protocol = "HTTP"
      health_check = {
        path = var.health_check_path
      }
    }
  }

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}

module "alb_tg_attachment" {
  source = "../../../aws-iac-terraform-module/module/network/aws-elb-workload/target-attachment"
  count  = var.enable_alb ? 1 : 0

  attachments = {
    app = {
      target_group_arn = local.tg_arn
      target_id        = module.ec2.ec2_instance.id
      port             = var.app_port
    }
  }
}

module "alb_listener" {
  source = "../../../aws-iac-terraform-module/module/network/aws-elb-workload/listener"
  count  = var.enable_alb ? 1 : 0

  load_balancer_arn = module.alb[0].elb.arn
  listeners         = local.alb_listeners

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
  records = {
    app = {
      name = var.alb_record_name
      type = "A"
      alias = {
        name                   = module.alb[0].elb.dns_name
        zone_id                = module.alb[0].elb.zone_id
        evaluate_target_health = true
      }
    }
  }
}

# ALB를 둘 서브넷: 태그 Use-alb = true + Tier (내부용 private, 외부용 public). AZ마다 하나
module "alb_subnet_use" {
  source = "../../../aws-iac-terraform-module/module/_subnet_use_lookup"
  count  = var.enable_alb && var.alb_subnet_ids == null ? 1 : 0

  label  = "ALB 서브넷 (${local.purpose})"
  vpc_id = local.network.base.vpc_id
  azs    = local.network.base.azs
  use    = "alb"
  tier   = var.alb_internal ? "private" : "public"
}
