############################################################
# ALB (선택) - main.tf에서 enable_alb = true 일 때만 생성
#   인증서가 있으면: 80 → 443 리다이렉트, 443 → EC2
#   인증서가 없으면: 80 → EC2
############################################################

locals {
  alb_subnet_ids    = var.alb_subnet_ids != null ? var.alb_subnet_ids : values(local.base.edge_subnet_ids)
  alb_ingress_cidrs = var.alb_ingress_cidrs != null ? var.alb_ingress_cidrs : distinct(concat(local.base.vpc_cidrs, local.base.tgw_route_cidrs))
  use_https         = var.alb_certificate_arn != null
  alb_ports         = local.use_https ? tolist([80, 443]) : tolist([80])
  tg_arn            = try(module.alb_tg[0].target_group_arn["app"], null)

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
}

module "alb_sg" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload"
  count  = var.enable_alb ? 1 : 0

  name   = "${local.prefix}-alb-sg"
  vpc_id = local.base.vpc_id
  default_security_group_rules = {
    ingress = [for p in local.alb_ports : {
      from_port   = p
      to_port     = p
      protocol    = "tcp"
      cidr_blocks = local.alb_ingress_cidrs
      description = "HTTP(S) to ALB"
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

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
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
  source = "../../../aws-iac-terraform-module/module/network/aws-route53-workload/records"
  # zone_id는 apply 전까지 알 수 없으므로 plan 시점에 정해지는 zone_name으로 판단
  count = var.enable_alb && var.alb_record_name != null && local.base.has_zone ? 1 : 0

  zone_id   = local.base.zone_id
  zone_name = local.base.zone_name
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
