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
  #   용도 지정: 이 VPC에서 태그 Use-db = true 서브넷 (plan 때 조회, subnet_use 모듈). 사용 AZ마다 있으면 자기 서브넷을 만들지 않고 그 서브넷을 씀
  #         이미 자기 DB 서브넷을 만들었으면 계속 그것을 씀 (위치가 나중에 바뀌지 않게)
  #   표준: subnet_cidrs(03-database tfvars db_subnet_cidrs, AZ 끝 글자 → CIDR). 비우면 01-network 배치 규칙 계산값
  #   수동: 01-network manual_subnets 중 purpose = "db" (키 = 이름)
  ############################################################
  shared_db  = module.subnet_use.subnet_ids
  use_shared = module.subnet_use.mode == "tagged"

  standard_subnets = local.use_shared ? {} : {
    for az in local.azs : az => {
      az   = az
      cidr = var.subnet_cidrs != null ? lookup(var.subnet_cidrs, local.base.az_short[az], null) : try(local.subnets.cidrs.db[az], null)
      key  = "${local.key}_${local.base.az_short[az]}"
    } if(var.subnet_cidrs != null ? lookup(var.subnet_cidrs, local.base.az_short[az], null) : try(local.subnets.cidrs.db[az], null)) != null
  }
  manual_subnets = {
    for name, s in local.subnets.manual : name => { az = s.az, cidr = s.cidr, key = "${local.key}_${replace(name, "-", "_")}" }
    if s.purpose == "db"
  }
  all_subnets = merge(local.standard_subnets, local.manual_subnets)
  # 이 단계가 만든 서브넷이 있는 AZ (라우트 테이블은 여기만. 용도 지정 서브넷 라우팅은 01-network가 함)
  rt_azs = distinct([for k, s in local.all_subnets : s.az])
  # DB가 쓸 서브넷 (AZ → ID): 용도 태그(Use-db) 서브넷 또는 자기 서브넷
  db_subnet_ids = local.use_shared ? local.shared_db : { for az, s in local.standard_subnets : az => module.subnet[az].vpc_subnet[0].id }

  # 사내망 경로: DB 관리 도구 등 사내망에서 접속할 때 돌아가는 경로 (TGW)
  corp_routes = local.routing.has_tgw && length(local.routing.corp_cidrs) > 0
}
