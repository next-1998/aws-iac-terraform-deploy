############################################################
# 입력 검사 (리전 정보나 계산 결과가 필요해서 variable validation 대신 precondition 사용)
############################################################
locals {
  # cidr a가 cidr b 안에 들어가는지 (a의 prefix가 b 이상이고, a를 b 크기로 잘랐을 때 b와 같음)
  manual_allowed = {
    for s in var.manual_subnets : s.name => concat(
      lookup(local.spare_cidrs, s.az, []),
      local.extra_routable,
    )
  }
  manual_inside = {
    for s in var.manual_subnets : s.name => anytrue([
      for b in local.manual_allowed[s.name] :
      tonumber(split("/", s.cidr)[1]) >= tonumber(split("/", b)[1]) &&
      cidrsubnet(format("%s/%s", cidrhost(s.cidr, 0), split("/", b)[1]), 0, 0) == b
    ])
  }
  # 직접 입력(subnet_cidrs)·공용 서브넷(shared_subnets) 검사: VPC 대역 안, 서로 겹침, 모든 AZ, 필수 용도, 크기
  #   규칙 배치(layout)를 쓰면 계산한 서브넷(ec2·db 포함)과 공용 서브넷이 겹치는지도 봄
  check_list = concat(
    local.manual_mode ? local.manual_list : flatten([for p, m in local.layout_subnet_cidrs : [for az, c in m : { name = "${p}-${local.az_short[az]}", purpose = p, short = local.az_short[az], cidr = c }]]),
    [for k, s in local.shared_map : { name = "${s.name}-${s.short}", purpose = s.name, short = s.short, cidr = s.cidr }],
  )
  sub_inside = {
    for s in local.check_list : s.name => anytrue([
      for b in local.vpc_cidrs :
      tonumber(split("/", s.cidr)[1]) >= tonumber(split("/", b)[1]) &&
      cidrsubnet(format("%s/%s", cidrhost(s.cidr, 0), split("/", b)[1]), 0, 0) == b
    ])
  }
  sub_overlaps = flatten([
    for i, a in local.check_list : [
      for j, b in local.check_list : "${a.name}(${a.cidr}) <> ${b.name}(${b.cidr})"
      if i < j && cidrsubnet(format("%s/%d", cidrhost(a.cidr, 0), min(tonumber(split("/", a.cidr)[1]), tonumber(split("/", b.cidr)[1]))), 0, 0) == cidrsubnet(format("%s/%d", cidrhost(b.cidr, 0), min(tonumber(split("/", a.cidr)[1]), tonumber(split("/", b.cidr)[1]))), 0, 0)
    ]
  ])
  az_letters      = sort(values(local.az_short))
  sub_az_mismatch = !local.manual_mode ? [] : [for p, m in var.subnet_cidrs : p if sort(keys(m)) != local.az_letters]
  sub_required    = concat(["edge", "vpce", "transit"], var.enable_public ? ["public"] : [])
  sub_missing     = !local.manual_mode ? [] : [for p in local.sub_required : p if !contains(keys(var.subnet_cidrs), p)]
  sub_size_errors = [
    for s in local.manual_list : "${s.name}(${s.cidr})"
    if(s.purpose == "edge" && tonumber(split("/", s.cidr)[1]) > 27) || (s.purpose == "eks" && tonumber(split("/", s.cidr)[1]) > 23)
  ]

  manual_overlaps = flatten([
    for i, a in var.manual_subnets : [
      for j, b in var.manual_subnets : "${a.name} <> ${b.name}"
      if i < j && cidrsubnet(format("%s/%d", cidrhost(a.cidr, 0), min(tonumber(split("/", a.cidr)[1]), tonumber(split("/", b.cidr)[1]))), 0, 0) == cidrsubnet(format("%s/%d", cidrhost(b.cidr, 0), min(tonumber(split("/", a.cidr)[1]), tonumber(split("/", b.cidr)[1]))), 0, 0)
    ]
  ])
}

# 검사 결과는 출력 precondition으로 보여 줍니다 (리소스를 만들지 않음).
output "input_checks" {
  value = "ok"

  precondition {
    condition     = local.manual_mode || local.layout != null
    error_message = "layout_version '${var.layout_version}'이 없습니다. 사용 가능: ${join(", ", keys(local.layouts))}"
  }
  precondition {
    condition     = var.az_count <= length(local.region_azs)
    error_message = "az_count(${var.az_count})가 이 리전의 사용 가능한 AZ 수(${length(local.region_azs)})보다 큽니다. 사용 가능 AZ: ${join(", ", local.region_azs)}"
  }
  precondition {
    condition     = local.manual_mode || local.layout_fits
    error_message = "첫 번째 routable 대역(${local.primary_cidr})이 작습니다. AZ ${var.az_count}개면 AZ 블록이 /${local.az_block_prefix}가 되는데, 표준 배치에는 /24 이상이 필요합니다. 필요한 크기: AZ 1개 /24, 2개 /23, 3~4개 /22"
  }
  precondition {
    condition     = local.manual_mode || var.eks_placement != "routable" || local.eks_routable_fits
    error_message = "EKS를 routable에 두려면 AZ 블록이 /${var.eks_subnet - 1} 이상이어야 합니다 (지금 /${local.az_block_prefix}). 대역을 더 받거나 eks_placement = \"internal\"을 쓰세요."
  }
  precondition {
    condition     = !var.enable_flow_logs || var.flow_log_bucket_arn != null
    error_message = "enable_flow_logs = true인데 로그 버킷이 없습니다. 00-bootstrap 로그 버킷을 만들거나 central_log_bucket_arn을 지정하세요."
  }
  precondition {
    condition     = alltrue([for s in var.manual_subnets : contains(local.azs, s.az)])
    error_message = "manual_subnets의 az가 사용 중인 AZ(${join(", ", local.azs)})가 아닙니다."
  }
  precondition {
    condition     = alltrue(values(local.manual_inside))
    error_message = "manual_subnets가 예비 공간이나 추가 routable 대역 밖에 있습니다: ${join(", ", [for k, v in local.manual_inside : k if !v])}. 넣을 수 있는 곳은 sizing 출력의 spare를 확인하세요."
  }
  precondition {
    condition     = length(local.manual_overlaps) == 0
    error_message = "manual_subnets끼리 겹칩니다: ${join(", ", local.manual_overlaps)}"
  }

  # ── 서브넷 직접 입력 (subnet_cidrs) ──
  precondition {
    condition     = !local.manual_mode || length(var.manual_subnets) == 0
    error_message = "subnet_cidrs(직접 입력)를 쓰면 manual_subnets 대신 subnet_cidrs에 넣으세요."
  }
  precondition {
    condition     = length(local.sub_missing) == 0
    error_message = "subnet_cidrs에 필수 용도가 없습니다: ${join(", ", local.sub_missing)} (필수: edge, vpce, transit, enable_public이면 public)"
  }
  precondition {
    condition     = length(local.sub_az_mismatch) == 0
    error_message = "subnet_cidrs·shared_subnets는 용도마다 사용 중인 AZ(${join(", ", local.az_letters)})에 하나씩 있어야 합니다. 맞지 않는 용도: ${join(", ", local.sub_az_mismatch)}"
  }
  precondition {
    condition     = alltrue(values(local.sub_inside))
    error_message = "subnet_cidrs·shared_subnets가 VPC 대역(${join(", ", local.vpc_cidrs)}) 밖에 있습니다: ${join(", ", [for k, v in local.sub_inside : k if !v])}"
  }
  precondition {
    condition     = length(local.sub_overlaps) == 0
    error_message = "서브넷끼리 겹칩니다 (subnet_cidrs·shared_subnets·배치 규칙 계산값): ${join(", ", local.sub_overlaps)}"
  }
  precondition {
    condition     = length(local.sub_size_errors) == 0
    error_message = "subnet_cidrs 크기가 작습니다 (edge는 ALB 때문에 /27 이상, eks는 /23 이상): ${join(", ", local.sub_size_errors)}"
  }
}
