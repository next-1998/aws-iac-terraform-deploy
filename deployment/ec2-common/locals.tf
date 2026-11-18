locals {
  site   = var.base.site
  prefix = "${local.site}-${var.name}"

  # ResourceKey 대상 (stack 이름의 '-'를 '_'로)
  key = replace(var.name, "-", "_")

  # 리소스 생성 시 붙이는 변경 태그
  resource_tags = var.base.resource_tags

  azs      = var.base.azs
  az_short = { for az in local.azs : az => substr(az, -1, 1) }

  ############################################################
  # 대역: zone 안에서 slot 번호로 블록을 받고, 블록을 AZ별로 나눔
  #   블록은 AZ 4개 자리로 나누고(+2 bit), AZ 글자 번호(a=0 ~ d=3)로 자리를 고정
  #   → az_count를 늘려도 기존 서브넷 CIDR은 바뀌지 않음
  #   hybrid   ec2: slot 0 = 100.64.0.0/23 → a 100.64.0.0/25, b 100.64.0.128/25, c 100.64.1.0/25, d 100.64.1.128/25
  #   routable ec2: 블록 /26 → AZ별 /28
  ############################################################
  zone        = var.base.stack_zones[var.zone]
  zone_prefix = tonumber(split("/", local.zone.cidr)[1])
  block       = cidrsubnet(local.zone.cidr, local.zone.block_prefix - local.zone_prefix, var.slot)
  subnets     = { for az in local.azs : az => cidrsubnet(local.block, 2, var.base.az_index[az]) }

  # routable + internal 이면 워크로드는 internal 대역 → 사내망은 private NAT 경유
  # routable 단독이면 워크로드는 routable 대역 → 사내망은 TGW 직접
  in_internal = var.base.network_type == "hybrid"
}
