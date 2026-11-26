############################################################
# NLB (선택, 고정 IP 용도: 고객 DB 접근제어가 IP로만 허용할 때) — DB와 함께 만듦
#   nlb = null        : 없음 (기본)
#   mode = dedicated  : 이 DB 전용 NLB <np>-nlb-rds<DB 키>-01
#   mode = shared     : rds-common의 공유 NLB <np>-nlb-rds-01에 이 DB의 리스너만 붙임 (DB끼리 port가 달라야 함)
#   리스너: DB port → 대상 그룹 (원본 SG의 ENI = 원본 + Multi-AZ 대기, 상태 확인이 활성만 사용)
#   읽기 복제본은 NLB에 연결하지 않음 (용도가 다를 수 있어 분리. 복제본은 자기 SG·접속 주소로)
#   대상 IP는 rds-common 동기화 Lambda가 태그 RdsNlbSyncSg = <SG>를 보고 1분마다 맞춤 (Terraform은 대상을 직접 등록하지 않음)
#   접근: NLB SG ← nlb.allowed_cidrs (DB port), DB SG ← NLB SG
############################################################
locals {
  nlb_on  = try(var.nlb.allowed_cidrs, null) != null
  nlb_ded = local.nlb_on && try(var.nlb.mode, "") == "dedicated"

  nlb_shared = try(var.common.nlb.shared, null)
  nlb_arn    = !local.nlb_on ? null : (local.nlb_ded ? module.nlb[0].elb.arn : try(local.nlb_shared.arn, null))
  nlb_dns    = !local.nlb_on ? null : (local.nlb_ded ? module.nlb[0].elb.dns_name : try(local.nlb_shared.dns_name, null))
  nlb_sg_id  = !local.nlb_on ? null : (local.nlb_ded ? module.nlb_sg[0].securitygroup_id : try(local.nlb_shared.sg_id, null))
  # 고정 IP (고객 접근제어 등록용). 전용은 이 NLB, 공유는 rds-common이 조회한 값
  nlb_ips = !local.nlb_on ? [] : (local.nlb_ded ? module.nlb[0].nlb_private_ips : try(local.nlb_shared.private_ips, []))

  # NLB 쪽 허용 포트 = DB port (원본·대기만. 복제본은 NLB에 연결하지 않음)
  nlb_ports = local.nlb_on ? { w = local.port } : {}
}

# ── 전용 NLB ───────────────────────────────────────────────────
module "nlb_sg" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/security-group"
  count  = local.nlb_ded ? 1 : 0

  name        = "${local.np}-sg-rds${local.db_key}nlb-01"
  description = "NLB for ${local.identifier}"
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

# ── 대상 그룹 (IP, TCP). 대상은 동기화 Lambda가 SG의 ENI IP로 맞춤 ──
module "nlb_tg_w" {
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

  common_tags   = var.common_tags
  resource_tags = merge(local.resource_tags, { (var.common.nlb.sync_tag_key) = module.sg.securitygroup_id })
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_nlb"
}

module "nlb_listener" {
  source = "../../../aws-iac-terraform-module/module/network/aws-elb-workload/listener"
  count  = local.nlb_on ? 1 : 0

  load_balancer_arn = local.nlb_arn
  listeners = {
    w = { port = local.port, protocol = "TCP", forward = { arn = module.nlb_tg_w[0].target_group_arn["w"] } }
  }

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_nlb"
}

# ── 접근 규칙 ──────────────────────────────────────────────────
module "nlb_sg_ingress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/ingress-rule"
  rules = merge(
    # NLB ← 고객 접근 대역 (쓰기·읽기 포트)
    {
      for pair in setproduct(keys(local.nlb_ports), local.nlb_on ? var.nlb.allowed_cidrs : []) : "nlb|${local.db_key}|${pair[0]}|${pair[1]}" => {
        security_group_id = local.nlb_sg_id
        ip_protocol       = "tcp"
        from_port         = local.nlb_ports[pair[0]]
        to_port           = local.nlb_ports[pair[0]]
        cidr_ipv4         = pair[1]
        description       = "${local.db_key} from ${pair[1]}"
      }
    },
    # DB(원본·대기) ← NLB
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

# NLB → DB·복제본 (대상 포트 = DB port)
module "nlb_sg_egress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/egress-rule"
  rules = merge(
    local.nlb_on ? {
      "nlb|${local.db_key}|db" = {
        security_group_id            = local.nlb_sg_id
        ip_protocol                  = "tcp"
        from_port                    = local.port
        to_port                      = local.port
        referenced_security_group_id = module.sg.securitygroup_id
        description                  = "to ${local.db_key} database"
      }
    } : {},
  )
}
