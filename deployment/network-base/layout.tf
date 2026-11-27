############################################################
# 대역 배치 규칙 (layout) — 버전 관리
#
# ■ 버전이 왜 필요한가
#   서브넷 CIDR은 "받은 대역 + 이 파일의 배치 규칙"으로 계산됩니다.
#   규칙(크기, 위치)을 바꾸면 같은 입력이라도 CIDR이 달라지고,
#   Terraform은 기존 서브넷과 그 안의 서버를 삭제한 뒤 다시 만듭니다.
#   그래서 이미 배포된 사이트는 처음에 쓴 규칙을 계속 써야 합니다.
#
# ■ 사이트는 어떻게 쓰나
#   사이트 tfvars에 layout_version을 적습니다. (예: layout_version = "v1")
#   사이트를 처음 만들 때 최신 버전을 고르고, 이후에는 바꾸지 않습니다.
#
# ■ 언제 새 버전을 만드나
#   - 기존 용도의 크기나 위치를 바꿔야 할 때 (예: vpce /27 → /26)
#   → 기존 버전은 그대로 두고, layouts 안에 새 버전(v2)을 추가합니다.
#
# ■ 새 버전 없이 고쳐도 되는 경우
#   - 예비(spare) 위치에 새 용도를 "추가"만 할 때 (기존 항목은 그대로)
#   → 같은 버전 안에 항목을 추가하고 spare에서 그 위치를 뺍니다. 기존 서브넷은 바뀌지 않습니다.
#
# ■ 절대 하면 안 되는 것
#   - 이미 있는 버전의 기존 항목(size, netnum)을 수정하거나 삭제
#   - 사이트의 layout_version을 다른 버전으로 변경
#   tests/가 버전별 결과 CIDR을 검사하므로, 실수하면 테스트가 실패합니다.
#
# ■ 용어
#   size   : 서브넷 크기 (prefix 길이. 26 = /26 = 64개)
#   netnum : 표준 /24 안에서 그 크기로 몇 번째 칸인지 (cidrsubnet의 netnum)
#            예) size 27, netnum 2 → /27 칸 중 3번째 = .64 ~ .95
#   owner  : 그 서브넷을 만드는 곳 (network-base가 아니면 CIDR만 계산해서 넘김)
############################################################

locals {
  layouts = {
    ##########################################################
    # v1 (2026-11) — 표준 AZ 블록 /24
    #
    #   .0   /26  edge     network-base  내부용 ALB/NLB (LB는 각 리소스가 생성)
    #   .64  /27  vpce     network-base  인터페이스 endpoint
    #   .96  /28  transit  network-base  TGW attachment, private NAT
    #   .112 /28  예비      (EFS 등은 manual_subnets 또는 subnet_cidrs 직접 입력으로)
    #   .128 /26  ec2      ec2-common
    #   .192 /27  db       rds-common 등 (RDS, Aurora, ElastiCache)
    #   .224 /27  public   network-base  외부용 ALB/NLB, public NAT (enable_public일 때만)
    #
    # AZ 블록이 /24보다 크면 (받은 대역이 큼, EKS routable 등)
    #   - 앞쪽 절반의 첫 /24 = 위 표준 배치
    #   - 뒤쪽 절반의 앞 = EKS (eks_placement = routable일 때, eks_subnet 크기)
    #   - 나머지 = 예비
    ##########################################################
    v1 = {
      standard_prefix = 24
      subnets = {
        edge    = { size = 26, netnum = 0, owner = "network-base" }
        vpce    = { size = 27, netnum = 2, owner = "network-base" }
        transit = { size = 28, netnum = 6, owner = "network-base" }
        ec2     = { size = 26, netnum = 2, owner = "ec2-common" }
        db      = { size = 27, netnum = 6, owner = "rds-common" }
        public  = { size = 27, netnum = 7, owner = "network-base" }
      }
      spare = [
        { size = 28, netnum = 7 }, # .112/28
      ]
    }
    # v2를 추가할 때는 이 아래에 작성합니다 (v1은 수정하지 않음).
  }

  layout = lookup(local.layouts, var.layout_version, null)

  ############################################################
  # AZ
  #   리전의 AZ 목록(일반 AZ만, 이름순)에서 앞에서부터 az_count개를 순서대로 사용합니다.
  #   예) 서울 2개 → a, b / 도쿄 2개 → a, c (도쿄는 b가 없음)
  #
  # AZ 분할 (받은 첫 routable 대역을 균등 분배)
  #   az_count 1 → 1등분 (대역 = AZ 블록)
  #   az_count 2 → 2등분
  #   az_count 3 → 4등분, 4번째 칸은 예비 (AZ 4개째 증설용으로 남김. 수동 서브넷 금지)
  #   az_count 4 → 4등분
  #   CIDR은 2의 거듭제곱으로만 나뉘므로 3등분은 할 수 없습니다.
  ############################################################
  region_azs = sort(data.aws_availability_zones.this.names)
  azs        = slice(local.region_azs, 0, min(var.az_count, length(local.region_azs)))
  az_index   = { for i, az in local.azs : az => i }
  az_short   = { for az in local.azs : az => substr(az, -1, 1) }
  # 서브넷 CIDR이 정해졌을 때만 서브넷을 만드는 AZ 목록 (직접 입력, 또는 배치가 맞을 때. 아니면 checks.tf가 에러 메시지를 보여 줌)
  layout_azs = local.subnets_ready ? local.azs : []
  az_slots   = var.az_count == 1 ? 1 : (var.az_count == 2 ? 2 : 4)
  slot_bits  = { 1 = 0, 2 = 1, 4 = 2 }[local.az_slots]

  ############################################################
  # 대역
  ############################################################
  routable_cidrs = [for c in var.vpc_cidrs : c.cidr if c.role == "routable"]
  primary_cidr   = local.routable_cidrs[0]
  extra_routable = slice(local.routable_cidrs, 1, length(local.routable_cidrs)) # 확장용 routable 대역

  use_internal  = var.eks_placement == "internal" || length([for c in var.vpc_cidrs : c if c.role == "internal"]) > 0
  internal_cidr = local.use_internal ? "100.64.0.0/16" : null

  # VPC에 연결할 secondary 대역 (확장 routable + internal)
  secondary_cidrs = distinct(concat(local.extra_routable, local.use_internal ? [local.internal_cidr] : []))
  vpc_cidrs       = concat([local.primary_cidr], local.secondary_cidrs)

  primary_prefix  = tonumber(split("/", local.primary_cidr)[1])
  az_block_prefix = local.primary_prefix + local.slot_bits
  layout_fits     = local.layout != null ? local.az_block_prefix <= local.layout.standard_prefix : false

  ############################################################
  # AZ 블록 → 표준 /24 → 용도별 서브넷
  #   (layout_fits가 false면 checks.tf가 plan에서 막습니다. 아래 계산은 그 전에 에러가 나지 않도록 보호)
  ############################################################
  az_block = local.layout_fits ? { for az, i in local.az_index : az => cidrsubnet(local.primary_cidr, local.slot_bits, i) } : {}

  # AZ 블록이 /24면 블록 자체가 표준 /24, 더 크면 앞쪽 절반의 첫 /24
  standard_block = {
    for az, b in local.az_block : az => cidrsubnet(b, local.layout.standard_prefix - local.az_block_prefix, 0)
  }

  # 용도 → AZ → CIDR (배치 규칙으로 계산한 값. subnet_cidrs를 직접 넣으면 그 값을 씀: 아래 "직접 입력")
  layout_subnet_cidrs = local.layout_fits ? {
    for name, s in local.layout.subnets : name => {
      for az, b in local.standard_block : az => cidrsubnet(b, s.size - local.layout.standard_prefix, s.netnum)
    }
  } : {}

  ############################################################
  # EKS (CIDR만 계산, 서브넷은 04-eks가 생성)
  #   routable : AZ 블록의 뒤쪽 절반 앞에 eks_subnet 크기로. AZ 블록이 /(eks_subnet - 1) 이상이어야 함
  #              예) eks_subnet 23 → AZ 블록 /22 이상 (받은 대역: AZ 2개면 /21)
  #   internal : 100.64.0.0/16을 AZ별로 균등 분배한 칸 전체 (AZ 2개면 /17)
  ############################################################
  eks_routable_fits = local.az_block_prefix <= var.eks_subnet - 1

  layout_eks_cidrs = (
    var.eks_placement == "routable" && local.eks_routable_fits ? {
      for az, b in local.az_block : az => cidrsubnet(cidrsubnet(b, 1, 1), var.eks_subnet - (local.az_block_prefix + 1), 0)
    } :
    var.eks_placement == "internal" ? {
      for az, i in local.az_index : az => cidrsubnet(local.internal_cidr, local.slot_bits, i)
    } : {}
  )

  ############################################################
  # 예비 공간 (수동 서브넷을 넣을 수 있는 곳)
  #   - 표준 /24 안의 spare
  #   - AZ 블록이 /24보다 크면: 앞쪽 절반에서 표준 /24를 뺀 나머지 + 뒤쪽 절반에서 EKS를 뺀 나머지
  ############################################################
  half_prefix = local.az_block_prefix + 1
  has_halves  = local.layout_fits ? local.az_block_prefix < local.layout.standard_prefix : false

  spare_cidrs = {
    for az, b in local.az_block : az => concat(
      [for s in local.layout.spare : cidrsubnet(local.standard_block[az], s.size - local.layout.standard_prefix, s.netnum)],
      local.has_halves ? [
        for q in range(local.half_prefix + 1, local.layout.standard_prefix + 1) : cidrsubnet(cidrsubnet(b, 1, 0), q - local.half_prefix, 1)
      ] : [],
      local.has_halves ? (
        var.eks_placement == "routable" && local.eks_routable_fits ? [
          for q in range(local.half_prefix + 1, var.eks_subnet + 1) : cidrsubnet(cidrsubnet(b, 1, 1), q - local.half_prefix, 1)
        ] : [cidrsubnet(b, 1, 1)]
      ) : [],
    )
  }

  ############################################################
  # 직접 입력 (subnet_cidrs): 고객 네트워크 설계서의 서브넷 CIDR을 그대로 씀
  #   넣으면 위 배치 규칙(layout_version)을 쓰지 않음. 비우면(null) 배치 규칙으로 계산
  #   용도 → { AZ 끝 글자 → CIDR }. 서브넷은 지금처럼 각 용도의 단계가 만듦 (ec2 → 03-compute, db → 03-database …)
  #   eks는 eks_cidrs로 넘김 (04-eks가 만듦)
  ############################################################
  manual_mode = var.subnet_cidrs != null
  # 직접 입력은 필수 용도·AZ가 맞을 때만 (아니면 서브넷을 만들지 않고 checks.tf가 에러 메시지를 보여 줌)
  subnets_ready = (local.manual_mode ? length(local.sub_missing) == 0 : local.layout_fits) && length(local.sub_az_mismatch) == 0
  az_by_short   = { for az in local.azs : local.az_short[az] => az }

  manual_cidrs = !local.manual_mode ? {} : {
    for p, m in var.subnet_cidrs : p => { for s, c in m : local.az_by_short[s] => c if contains(keys(local.az_by_short), s) }
  }
  subnet_cidrs = local.manual_mode ? { for p, m in local.manual_cidrs : p => m if p != "eks" } : local.layout_subnet_cidrs
  eks_cidrs    = local.manual_mode ? try(local.manual_cidrs["eks"], {}) : local.layout_eks_cidrs

  # 검사용: 모든 직접 입력 서브넷 (이름 = 용도-AZ)
  manual_list = !local.manual_mode ? [] : flatten([
    for p, m in var.subnet_cidrs : [for s, c in m : { name = "${p}-${s}", purpose = p, short = s, cidr = c }]
  ])

  # az_count 3일 때 4번째 칸: AZ 증설용 예비 (수동 서브넷 금지)
  az_growth_reserve = var.az_count == 3 && local.layout_fits ? cidrsubnet(local.primary_cidr, 2, 3) : null

  ############################################################
  # 크기 정보 (설계서용 sizing 출력)
  #   사용 가능 IP = 서브넷 크기 - 5 (AWS가 서브넷마다 5개 예약)
  ############################################################
  usable = { for p in range(16, 29) : tostring(p) => pow(2, 32 - p) - 5 }
}

data "aws_availability_zones" "this" {
  state = "available"

  # 일반 AZ만 (Local Zone, Wavelength Zone 제외)
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # 용도 → 서브넷을 만드는 곳 (sizing 출력용)
  purpose_owner = {
    edge = "network-base", vpce = "network-base", transit = "network-base", public = "network-base",
    ec2  = "ec2-common", db = "rds-common", efs = "efs-common", cache = "cache-common", eks = "eks-common",
  }
}

############################################################
# 용도 지정 서브넷 (purpose_subnets): 여러 종류의 리소스가 함께 쓰는 서브넷 (01-network가 미리 만듦)
#   use에 적은 종류의 리소스가 자기 서브넷 대신 이 서브넷을 씀 (예: db·efs·cache를 한 서브넷에)
#   그 종류를 받는 용도 지정 서브넷이 없으면 각 단계가 자기 서브넷을 만듦
############################################################
locals {
  purpose_map = merge([
    for name, s in var.purpose_subnets : {
      for short, c in s.cidrs : "${name}_${local.az_by_short[short]}" => { name = name, az = local.az_by_short[short], short = short, cidr = c, use = s.use }
      if contains(keys(local.az_by_short), short)
    }
  ]...)

  # 종류 → AZ → 서브넷 ID (그 종류를 받는 용도 지정 서브넷. 같은 종류를 받는 용도 지정 서브넷이 여러 개면 이름순 첫 번째)
  purpose_for = {
    for u in distinct(flatten([for n, s in var.purpose_subnets : s.use])) : u => {
      for az in local.layout_azs : az => [for n in sort(keys(var.purpose_subnets)) : module.subnet["${n}_${az}"].vpc_subnet[0].id if contains(var.purpose_subnets[n].use, u) && contains(keys(local.purpose_map), "${n}_${az}")][0]
    }
  }
  purpose_cidrs_for = {
    for u in distinct(flatten([for n, s in var.purpose_subnets : s.use])) : u => {
      for az in local.azs : az => [for n in sort(keys(var.purpose_subnets)) : local.purpose_map["${n}_${az}"].cidr if contains(var.purpose_subnets[n].use, u) && contains(keys(local.purpose_map), "${n}_${az}")][0]
    }
  }
}
