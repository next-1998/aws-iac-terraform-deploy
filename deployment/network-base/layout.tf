############################################################
# 대역 배치 (모든 사이트 공통 고정 규칙)
#
# AZ
#   리전의 AZ 목록(일반 AZ만, 이름순)에서 앞에서부터 az_count개를 순서대로 사용합니다.
#   예) 서울 2개 → a, b / 도쿄 2개 → a, c (도쿄는 b가 없음)
#   AZ는 최대 4개 자리를 미리 잡고, 서브넷 번호(netnum)는 목록 순서로 정합니다 (첫 번째=0 ~ 네 번째=3).
#   AZ가 1개여도 동작하지만 ALB, RDS, EKS는 AWS 규칙상 AZ 2개 이상이 필요합니다.
#   번호를 바꾸거나 재사용하면 서브넷이 다시 만들어집니다.
#
# routable 대역의 앞쪽 /24 = base 영역
#   x.x.x.0/27   ~ x.x.x.96/27    edge-a ~ edge-d       (ALB, public NAT)
#   x.x.x.128/28 ~ x.x.x.176/28   transit-a ~ transit-d (TGW attachment, private NAT)
#   x.x.x.192/26                  예비
#
# stack 영역
#   routable + internal : internal 대역 전체 (100.64.0.0/16)
#   routable 단독        : routable 대역의 뒤쪽 절반
############################################################

data "aws_availability_zones" "this" {
  state = "available"

  # 일반 AZ만 (Local Zone, Wavelength Zone 제외)
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  max_azs = 4

  region_azs = sort(data.aws_availability_zones.this.names)
  azs        = slice(local.region_azs, 0, min(var.az_count, length(local.region_azs)))
  az_index   = { for i, az in local.azs : az => i } # 목록 순서 = 고정 번호

  routable     = var.vpc_cidrs[0].cidr
  internal     = try([for c in var.vpc_cidrs : c.cidr if c.role == "internal"][0], null)
  network_type = local.internal != null ? "hybrid" : "routable"

  routable_prefix = tonumber(split("/", local.routable)[1])

  # base 영역 (/24)
  base_area     = cidrsubnet(local.routable, 24 - local.routable_prefix, 0)
  edge_cidrs    = { for az, i in local.az_index : az => cidrsubnet(local.base_area, 3, i) }     # /27, netnum 0~3
  transit_cidrs = { for az, i in local.az_index : az => cidrsubnet(local.base_area, 4, 8 + i) } # /28, netnum 8~11

  # stack 영역
  stack_area = (
    local.network_type == "hybrid"
    ? local.internal
    : try(cidrsubnet(local.routable, 1, 1), null)
  )

  # stack 종류별 영역(zone)과 stack 하나당 블록 크기(block_prefix)
  # stack은 zone 안에서 slot 번호로 블록을 받고, 블록을 AZ 4개 자리로 나눠 씁니다 (+2 bit).
  stack_zones = local.network_type == "hybrid" ? {
    ec2 = { cidr = cidrsubnet(local.stack_area, 2, 0), block_prefix = 23 } # 100.64.0.0/18   → /23 블록 32개 (AZ별 /25)
    eks = { cidr = cidrsubnet(local.stack_area, 2, 1), block_prefix = 18 } # 100.64.64.0/18  → /18 블록 1개  (AZ별 /20)
    db  = { cidr = cidrsubnet(local.stack_area, 4, 8), block_prefix = 24 } # 100.64.128.0/20 → /24 블록 16개 (AZ별 /26)
    # 100.64.144.0 ~ 예비
    } : {
    # routable /23 기준: stack 영역 /24 → zone /25 → /26 블록 2개 (AZ별 /28 = AWS 최소 서브넷)
    # routable이 더 크면 zone도 커져서 블록 수가 늘어납니다. (/21 → zone /23 → 블록 8개)
    ec2 = { cidr = cidrsubnet(local.stack_area, 1, 0), block_prefix = 26 }
    db  = { cidr = cidrsubnet(local.stack_area, 1, 1), block_prefix = 26 }
    # routable 단독에서는 eks 영역을 두지 않습니다 (Pod IP 부족)
  }
}
