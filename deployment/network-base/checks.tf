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
    condition     = local.layout != null
    error_message = "layout_version '${var.layout_version}'이 없습니다. 사용 가능: ${join(", ", keys(local.layouts))}"
  }
  precondition {
    condition     = var.az_count <= length(local.region_azs)
    error_message = "az_count(${var.az_count})가 이 리전의 사용 가능한 AZ 수(${length(local.region_azs)})보다 큽니다. 사용 가능 AZ: ${join(", ", local.region_azs)}"
  }
  precondition {
    condition     = local.layout_fits
    error_message = "첫 번째 routable 대역(${local.primary_cidr})이 작습니다. AZ ${var.az_count}개면 AZ 블록이 /${local.az_block_prefix}가 되는데, 표준 배치에는 /24 이상이 필요합니다. 필요한 크기: AZ 1개 /24, 2개 /23, 3~4개 /22"
  }
  precondition {
    condition     = var.eks_placement != "routable" || local.eks_routable_fits
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
}
