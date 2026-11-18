############################################################
# EC2 서브넷 + AZ별 라우트 테이블
#   CIDR은 01-network가 계산한 값을 그대로 씁니다 (배치 규칙은 network-base/layout.tf).
#
#   0.0.0.0/0   → 같은 AZ의 public NAT   (01-network enable_public일 때. 아니면 인터넷 경로 없음)
#   사내망 대역 → TGW                    (01-network tgw_id가 있을 때)
#   peering 대역 → peering               (01-network peerings)
############################################################

module "subnet" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-sbn-workload"
  for_each = local.all_subnets

  name                    = "${local.prefix}-${each.key}-subnet"
  vpc_id                  = local.base.vpc_id
  azs                     = each.value.az
  subnet_cidr_block       = [each.value.cidr]
  tier                    = "private"
  map_public_ip_on_launch = false

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = each.value.key
}

module "rt" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/routetable"
  for_each = toset(local.azs)

  name          = "${local.prefix}-${local.base.az_short[each.key]}-rt"
  vpc_id        = local.base.vpc_id
  vpc_subnet_id = [for k, s in local.all_subnets : module.subnet[k].vpc_subnet[0].id if s.az == each.key]

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_${local.base.az_short[each.key]}"
}

module "rt_internet" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/route"
  for_each = local.routing.has_public ? toset(local.azs) : toset([])

  vpc_rt_id        = module.rt[each.key].vpc_rt.id
  route_cidr_block = ["0.0.0.0/0"]
  route_type       = "nat_gateway"
  route            = { nat_gateway_id = local.routing.public_nat_ids[each.key] }
}

module "rt_corp" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/route"
  for_each = local.corp_routes ? toset(local.azs) : toset([])

  vpc_rt_id        = module.rt[each.key].vpc_rt.id
  route_cidr_block = local.routing.corp_cidrs
  route_type       = "transit_gateway"
  route            = { transit_gateway_id = local.routing.tgw_id }
}

module "rt_peering" {
  source = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/route"
  for_each = {
    for pair in setproduct(local.azs, keys(local.routing.peerings)) : "${pair[0]}_${pair[1]}" => { az = pair[0], peering = pair[1] }
  }

  vpc_rt_id        = module.rt[each.value.az].vpc_rt.id
  route_cidr_block = local.routing.peerings[each.value.peering].cidrs
  route_type       = "vpc_peering_connection"
  route            = { vpc_peering_connection_id = local.routing.peerings[each.value.peering].peering_connection_id }
}

############################################################
# Gateway endpoint (S3, DynamoDB) 연결
#   endpoint는 01-network가 만들었고, 여기서는 이 stack의 라우트 테이블만 연결합니다.
############################################################
resource "aws_vpc_endpoint_route_table_association" "gateway" {
  for_each = {
    for pair in setproduct(keys(var.network.endpoints.gateway), local.azs) : "${pair[0]}_${pair[1]}" => {
      endpoint_id = var.network.endpoints.gateway[pair[0]]
      az          = pair[1]
    }
  }

  vpc_endpoint_id = each.value.endpoint_id
  route_table_id  = module.rt[each.value.az].vpc_rt.id
}
