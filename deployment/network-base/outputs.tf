############################################################
# contract: 다음 단계(02-shared, 03-*, 04-eks)가 받는 값
#   01-network 단계 루트가 묶음(bundle)별로 Parameter Store에 씁니다.
#     /iac/<site>/01-network/base, subnets, routing, endpoints, dns
#   규칙: 기존 키의 이름을 바꾸거나 지우지 않습니다 (다음 단계가 깨짐). 추가만 합니다.
############################################################
locals {
  contract = {
    base = {
      contract_version = 1
      site             = var.site
      layout_version   = var.layout_version
      vpc_id           = module.vpc.vpc.id
      vpc_name         = var.vpc_name
      azs              = local.azs
      az_short         = local.az_short
      vpc_cidrs        = local.vpc_cidrs
      primary_cidr     = local.primary_cidr
      extra_routable   = local.extra_routable
      internal_cidr    = local.internal_cidr
      enable_public    = var.enable_public
      resource_tags    = local.resource_tags
    }

    subnets = {
      # network-base가 만든 서브넷 ID (용도 → AZ → ID)
      ids = local.subnet_ids
      # 모든 용도의 CIDR (용도 → AZ → CIDR). ec2, db는 <유형>-common이 이 값으로 서브넷을 만듦
      cidrs         = local.subnet_cidrs
      eks_placement = var.eks_placement
      eks_cidrs     = local.eks_cidrs
      # 수동 서브넷 (purpose별). 해당 <유형>-common이 생성
      manual = { for s in var.manual_subnets : s.name => s }
    }

    routing = {
      has_public      = var.enable_public
      has_tgw         = local.use_tgw
      has_private_nat = local.create_private_nat
      igw_id          = var.enable_public ? module.igw[0].vpc_igw.id : null
      public_nat_ids  = local.public_nat_ids  # AZ → 그 AZ가 쓸 public NAT
      private_nat_ids = local.private_nat_ids # AZ → 그 AZ가 쓸 private NAT
      nat_public_ips  = [for k, e in module.nat_eip : e.vpc_eip.public_ip]
      tgw_id          = var.tgw_id
      corp_cidrs      = var.corp_cidrs
      peerings        = var.peerings
      prefix_list_ids = module.prefix_list.ids
      # SG 규칙 한도 계산용 (prefix list를 참조하는 규칙 하나가 max_entries만큼 한도를 씀)
      prefix_list_max_entries = { for k, v in var.prefix_lists : k => v.max_entries }
    }

    endpoints = {
      ids        = local.endpoint_ids                                                            # 서비스 → endpoint ID
      gateway    = { for s in var.gateway_endpoints : s => lookup(local.endpoint_ids, s, null) } # 라우트 테이블 연결 대상
      interface  = var.interface_endpoints
      vpce_sg_id = length(var.interface_endpoints) > 0 ? module.vpce_sg[0].securitygroup_id : null
    }

    dns = {
      zone_name       = local.zone_name
      private_zone_id = local.zone_name != null ? module.private_zone[0].route53_zone_zone_id[local.zone_name] : null
      public_zone_id  = local.create_public ? module.public_zone[0].route53_zone_zone_id[local.zone_name] : null
      parent_zone_id  = local.zone_name != null ? data.aws_route53_zone.parent[0].zone_id : null
    }
  }
}

output "contract" {
  description = "다음 단계로 넘길 값 (묶음별)"
  value       = local.contract
}

############################################################
# sizing: 설계서용 대역 정보 (리소스를 만들기 전에 plan으로 확인 가능)
############################################################
output "sizing" {
  description = "AZ별 대역 배치, 사용 가능 IP, 예비 공간"
  value = {
    layout_version    = var.layout_version
    primary_cidr      = local.primary_cidr
    azs               = local.azs
    az_block_prefix   = "/${local.az_block_prefix}"
    az_growth_reserve = local.az_growth_reserve
    per_az = {
      for az, b in local.az_block : az => {
        az_block = b
        subnets = merge(
          {
            for name, m in local.subnet_cidrs : name => {
              cidr   = m[az]
              usable = local.usable[split("/", m[az])[1]]
              owner  = local.layout.subnets[name].owner
              active = name != "public" || var.enable_public
            }
          },
          contains(keys(local.eks_cidrs), az) ? {
            eks = { cidr = local.eks_cidrs[az], usable = local.usable[split("/", local.eks_cidrs[az])[1]], owner = "eks-common", active = true }
          } : {},
        )
        spare = local.spare_cidrs[az]
      }
    }
  }
}

output "default_security_group" {
  description = "잠근 기본 SG (규칙 없음)"
  value       = module.default_sg.default_security_group
}
