############################################################
# 개별 보안 그룹 (서비스 포트)
# 서버 접근(SSH 등)은 ec2-common의 공통 SG가 담당합니다.
# 출발지는 IP(cidr_blocks)보다 prefix list 이름(prefix_lists)을 권장합니다.
############################################################

locals {
  alb_to_app = var.enable_alb ? [{
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    cidr_blocks     = null
    security_groups = [module.alb_sg[0].securitygroup_id]
    prefix_list_ids = null
    description     = "from ${local.prefix} ALB"
  }] : []

  ec2_ingress = concat(
    [for r in var.ingress_rules : {
      from_port       = r.from_port
      to_port         = r.to_port
      protocol        = r.protocol
      cidr_blocks     = r.cidr_blocks
      security_groups = null
      prefix_list_ids = r.prefix_lists == null ? null : [for n in r.prefix_lists : local.routing.prefix_list_ids[n]]
      description     = coalesce(r.description, "managed by terraform")
    }],
    local.alb_to_app,
  )
}

module "sg" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload"

  name   = "${local.prefix}-sg"
  vpc_id = local.base.vpc_id
  default_security_group_rules = {
    ingress = local.ec2_ingress
    egress = [{
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
      description = "all outbound"
    }]
  }

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}
