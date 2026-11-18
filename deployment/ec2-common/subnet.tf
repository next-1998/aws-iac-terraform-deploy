############################################################
# stack 전용 서브넷 + AZ별 라우트 테이블
#
# 각 AZ 서브넷은 base contract의 <AZ → NAT> 매핑을 따라 NAT로 나갑니다.
#   nat_per_az = true  : 같은 AZ의 NAT
#   nat_per_az = false : 첫 번째 AZ(a)의 NAT
#
# internal 대역 (routable + internal)
#   VPC 안은 local 라우트, 밖으로는 NAT GW로만 나감 (TGW 직접 경로 없음)
#     0.0.0.0/0 → public NAT (인터넷 출구가 있을 때)
#     사내망    → private NAT → (transit) TGW
#   들어오는 트래픽은 edge 서브넷의 LB를 거침
#
# routable 대역 (routable 단독)
#     0.0.0.0/0 → public NAT (인터넷 출구가 있을 때)
#     사내망    → TGW 직접
############################################################

module "subnet" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-sbn-workload"
  for_each = local.subnets

  name              = "${local.prefix}-${local.az_short[each.key]}-subnet"
  vpc_id            = var.base.vpc_id
  azs               = each.key
  subnet_cidr_block = [each.value]
  tier              = "private"

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_${local.az_short[each.key]}"
}

module "rt" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/routetable"
  for_each = toset(local.azs)

  name          = "${local.prefix}-${local.az_short[each.key]}-rt"
  vpc_id        = var.base.vpc_id
  vpc_subnet_id = [module.subnet[each.key].vpc_subnet[0].id]

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_${local.az_short[each.key]}"
}

module "rt_internet" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/route"
  for_each = var.base.has_public_nat ? toset(local.azs) : toset([])

  vpc_rt_id        = module.rt[each.key].vpc_rt.id
  route_cidr_block = ["0.0.0.0/0"]
  route_type       = "nat_gateway"
  route            = { nat_gateway_id = var.base.public_nat_ids[each.key] }
}

module "rt_corp" {
  source = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/route"
  for_each = (
    length(var.base.tgw_route_cidrs) > 0 &&
    (local.in_internal ? var.base.has_private_nat : var.base.has_tgw)
  ) ? toset(local.azs) : toset([])

  vpc_rt_id        = module.rt[each.key].vpc_rt.id
  route_cidr_block = var.base.tgw_route_cidrs
  route_type       = local.in_internal ? "nat_gateway" : "transit_gateway"
  # 두 키를 모두 넘기고, 쓰지 않는 쪽은 ""
  route = {
    nat_gateway_id     = local.in_internal ? var.base.private_nat_ids[each.key] : ""
    transit_gateway_id = local.in_internal ? "" : var.base.tgw_id
  }
}
