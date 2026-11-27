############################################################
# NLB (선택, 고정 IP 용도) — 클러스터와 함께 만듦. 방식(개별/통합)은 03-database rds_nlb.mode
#   Aurora 읽기 인스턴스도 접속을 받아 상태 확인을 통과하므로 SG의 ENI 전체를 넣으면 안 됨 → 지금 쓰기 인스턴스 IP 하나만
#   대상 등록 (rds_nlb.target_sync)
#     apply (기본) : 배포 때 지금 쓰기 인스턴스 주소(DNS) IP를 Terraform이 등록
#                    장애 조치 뒤에는 다시 apply (그 전까지 NLB는 이전 쓰기 인스턴스 = 이제 읽기로 보내 쓰기가 실패함)
#     lambda       : 대상 그룹 태그 RdsNlbSyncDns = <클러스터 쓰기 주소>. 동기화 Lambda가 1분마다 + 장애 조치 이벤트 때 바로 맞춤
############################################################
locals {
  nlb_on  = try(var.nlb.allowed_cidrs, null) != null
  nlb_ded = local.nlb_on && try(var.nlb.mode, "") == "dedicated"
  # 대상 등록 방법 (03-database rds_nlb.target_sync): apply(기본) | lambda
  nlb_lambda = local.nlb_on && try(var.nlb.target_sync, "apply") == "lambda"

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
    for az in local.base.azs : merge( # 개수(AZ)는 plan 전에 정해짐
      { subnet_id = try(var.common.nlb.nlb_subnet_by_az, var.common.nlb.db_subnet_by_az)[az] },
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
  # lambda 방식만: 동기화 Lambda가 이 주소(DNS)를 조회해 쓰기 인스턴스 IP만 등록
  resource_tags = local.nlb_lambda ? merge(local.resource_tags, { (var.common.nlb.sync_dns_tag_key) = module.cluster.endpoint }) : local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_nlb"
}

# ── 대상 등록: apply 방식 (기본) ───────────────────────────────
#   클러스터 쓰기 주소(DNS, 늘 지금 쓰기 인스턴스를 가리킴)를 조회. 장애 조치 뒤 다시 apply하면 새 쓰기 인스턴스 IP로 바뀜
#   처음 인스턴스(01)를 만들 때만 apply 중에 조회 (쓰기 인스턴스가 생기기 전에는 주소가 풀리지 않음)
#   그 밖에는 plan 때 조회 → 읽기 인스턴스를 바꿔도 IP가 같으면 대상을 건드리지 않음
#   (인스턴스별 writer 값으로 고르면 바뀌는 인스턴스가 하나라도 있을 때 값을 몰라 대상이 교체됨)
data "dns_a_record_set" "nlb_target" {
  count = local.nlb_on && !local.nlb_lambda ? 1 : 0
  host  = module.instance["w"].identifier != "" ? module.cluster.endpoint : module.cluster.endpoint
}

module "nlb_target" {
  source = "../../../aws-iac-terraform-module/module/network/aws-elb-workload/target-attachment"
  attachments = local.nlb_on && !local.nlb_lambda ? {
    w = {
      target_group_arn = module.nlb_tg[0].target_group_arn["w"]
      target_id        = sort(data.dns_a_record_set.nlb_target[0].addrs)[0]
      port             = local.port
    }
  } : {}
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
