locals {
  base    = var.network.base
  subnets = var.network.subnets
  routing = var.network.routing

  site   = local.base.site
  prefix = "${local.site}-${var.name}"
  np     = local.base.name_prefix # 이름 접두어 (00-bootstrap naming)

  # ResourceKey 대상 (stack 이름의 '-'를 '_'로)
  key = replace(var.name, "-", "_")

  resource_tags = local.base.resource_tags
  azs           = local.base.azs

  ############################################################
  # DB 서브넷
  #   표준: 01-network가 계산한 db CIDR (AZ마다 하나, 키 = AZ)
  #   수동: 01-network manual_subnets 중 purpose = "db" (키 = 이름)
  ############################################################
  standard_subnets = {
    for az in local.azs : az => { az = az, cidr = local.subnets.cidrs.db[az], key = "${local.key}_${local.base.az_short[az]}" }
  }
  manual_subnets = {
    for name, s in local.subnets.manual : name => { az = s.az, cidr = s.cidr, key = "${local.key}_${replace(name, "-", "_")}" }
    if s.purpose == "db"
  }
  all_subnets = merge(local.standard_subnets, local.manual_subnets)

  # 사내망 경로: DB 관리 도구 등 사내망에서 접속할 때 돌아가는 경로 (TGW)
  corp_routes = local.routing.has_tgw && length(local.routing.corp_cidrs) > 0
}
