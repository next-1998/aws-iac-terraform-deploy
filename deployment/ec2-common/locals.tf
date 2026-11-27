locals {
  base    = var.network.base
  subnets = var.network.subnets
  routing = var.network.routing

  site   = local.base.site
  prefix = "${local.site}-${var.name}"

  # 이름 규칙: <np>-<유형>-<이름>-<순번>[-<AZ>] (np = 00-bootstrap naming 접두어)
  np = local.base.name_prefix

  # ResourceKey 대상 (stack 이름의 '-'를 '_'로)
  key = replace(var.name, "-", "_")

  # 리소스 생성 시 붙이는 변경 태그
  resource_tags = local.base.resource_tags

  azs = local.base.azs

  ############################################################
  # 서브넷
  #   표준: subnet_cidrs(03-compute tfvars, AZ 끝 글자 → CIDR). 비우면 01-network 배치 규칙 계산값 (AZ마다 하나, 키 = AZ)
  #   수동: 01-network manual_subnets 중 purpose = "ec2" (키 = 이름)
  ############################################################
  standard_subnets = {
    for az in local.azs : az => {
      az   = az
      cidr = var.subnet_cidrs != null ? lookup(var.subnet_cidrs, local.base.az_short[az], null) : try(local.subnets.cidrs.ec2[az], null)
      key  = "${local.key}_${local.base.az_short[az]}"
    } if(var.subnet_cidrs != null ? lookup(var.subnet_cidrs, local.base.az_short[az], null) : try(local.subnets.cidrs.ec2[az], null)) != null
  }
  manual_subnets = {
    for name, s in local.subnets.manual : name => { az = s.az, cidr = s.cidr, key = "${local.key}_${replace(name, "-", "_")}" }
    if s.purpose == "ec2"
  }
  all_subnets = merge(local.standard_subnets, local.manual_subnets)

  # 사내망 경로 (EC2는 routable 대역 → TGW / peering 직접)
  corp_routes = local.routing.has_tgw && length(local.routing.corp_cidrs) > 0
}
