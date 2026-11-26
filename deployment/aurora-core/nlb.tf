############################################################
# NLB (선택, 고정 IP 용도) — 클러스터와 함께 만듦. 방식(개별/통합)은 03-database rds_nlb.mode
#   RDS와 다른 점: Aurora 읽기 인스턴스도 접속을 받아 상태 확인을 통과하므로 SG의 ENI 전체를 넣으면 안 됨
#   → 대상 그룹 태그 RdsNlbSyncDns = <클러스터 쓰기 주소>. 동기화 Lambda가 DNS를 조회해 지금 쓰기 인스턴스 IP 하나만 등록
#     장애 조치 뒤에는 쓰기 주소가 새 인스턴스를 가리키고, Lambda가 1분 안에 대상을 바꿈
############################################################
locals {
  nlb_on  = try(var.nlb.allowed_cidrs, null) != null
  nlb_ded = local.nlb_on && try(var.nlb.mode, "") == "dedicated"

  nlb_shared = try(var.common.nlb.shared, null)
  nlb_arn    = !local.nlb_on ? null : (local.nlb_ded ? module.nlb[0].elb.arn : try(local.nlb_shared.arn, null))
  nlb_dns    = !local.nlb_on ? null : (local.nlb_ded ? module.nlb[0].elb.dns_name : try(local.nlb_shared.dns_name, null))
  nlb_sg_id  = !local.nlb_on ? null : (local.nlb_ded ? module.nlb_sg[0].securitygroup_id : try(local.nlb_shared.sg_id, null))
  nlb_ips    = !local.nlb_on ? [] : (local.nlb_ded ? module.nlb[0].nlb_private_ips : try(local.nlb_shared.private_ips, []))
}

module "nlb_sg" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/security-group"
  count  = local.nlb_ded ? 1 : 0

  name        = "${local.np}-sg-rds${local.db_key}nlb-01"
  description = "NLB for ${local.cluster_id}"
  vpc_id      = local.base.vpc_id

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_nlb"
}

module "nlb" {
  source = "../../../aws-iac-terraform-module/module/network/aws-elb-workload/lb"
  count  = local.nlb_ded ? 1 : 0

  name               = "${local.np}-nlb-rds${local.db_key}-01"
  load_balancer_type = "network"
  internal           = true
  lb_sg_id_list      = [module.nlb_sg[0].securitygroup_id]
  subnet_mapping = [
    for az, id in var.common.nlb.db_subnet_by_az : merge(
      { subnet_id = id },
      contains(keys(try(var.nlb.private_ips, {})), az) ? { private_ipv4_address = var.nlb.private_ips[az] } : {},
    )
  ]
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = var.protect

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_nlb"
}

module "nlb_tg" {
  source = "../../../aws-iac-terraform-module/module/network/aws-elb-workload/target-group"
  count  = local.nlb_on ? 1 : 0

  vpc_id             = local.base.vpc_id
  load_balancer_type = "network"
  target_groups = {
    w = {
      name                   = "${local.np}-tg-rds${local.db_key}-01"
      port                   = local.port
      protocol               = "TCP"
      target_type            = "ip"
      deregistration_delay   = 30
      connection_termination = true
      health_check           = { protocol = "TCP", interval = 10, healthy_threshold = 2, unhealthy_threshold = 2 }
    }
  }

  common_tags = var.common_tags
  # 동기화 Lambda가 이 주소(DNS)를 조회해 쓰기 인스턴스 IP만 등록
  resource_tags = merge(local.resource_tags, { (var.common.nlb.sync_dns_tag_key) = module.cluster.endpoint })
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_nlb"
}

module "nlb_listener" {
  source = "../../../aws-iac-terraform-module/module/network/aws-elb-workload/listener"
  count  = local.nlb_on ? 1 : 0

  load_balancer_arn = local.nlb_arn
  listeners = {
    w = { port = local.port, protocol = "TCP", forward = { arn = module.nlb_tg[0].target_group_arn["w"] } }
  }

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_nlb"
}

module "nlb_sg_ingress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/ingress-rule"
  rules = merge(
    {
      for c in local.nlb_on ? var.nlb.allowed_cidrs : [] : "nlb|${local.db_key}|${c}" => {
        security_group_id = local.nlb_sg_id
        ip_protocol       = "tcp"
        from_port         = local.port
        to_port           = local.port
        cidr_ipv4         = c
        description       = "${local.db_key} from ${c}"
      }
    },
    local.nlb_on ? {
      "db|nlb" = {
        security_group_id            = module.sg.securitygroup_id
        ip_protocol                  = "tcp"
        from_port                    = local.port
        to_port                      = local.port
        referenced_security_group_id = local.nlb_sg_id
        description                  = "from NLB"
      }
    } : {},
  )
}

module "nlb_sg_egress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/egress-rule"
  rules = local.nlb_on ? {
    "nlb|${local.db_key}|db" = {
      security_group_id            = local.nlb_sg_id
      ip_protocol                  = "tcp"
      from_port                    = local.port
      to_port                      = local.port
      referenced_security_group_id = module.sg.securitygroup_id
      description                  = "to ${local.db_key} cluster"
    }
  } : {}
}
