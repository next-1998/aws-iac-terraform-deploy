############################################################
# DB 서브넷 + AZ별 라우트 테이블 + DB 서브넷 그룹
#   CIDR은 01-network가 계산한 값을 그대로 씁니다 (배치 규칙은 network-base/layout.tf, db /27).
#   DB는 인터넷 경로가 없습니다 (NAT 연결 안 함).
#   사내망 대역 → TGW   (01-network tgw_id가 있을 때. 사내망에서 DB에 접속하는 응답 경로)
#   peering 대역 → peering
############################################################

module "subnet" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-sbn-workload"
  for_each = local.all_subnets

  name                    = contains(keys(local.standard_subnets), each.key) ? "${local.np}-sbn-db-01-${local.base.az_short[each.value.az]}" : "${local.np}-sbn-${each.key}-01"
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
  for_each = toset(local.rt_azs)

  name   = "${local.np}-rtb-db-01-${local.base.az_short[each.key]}"
  vpc_id = local.base.vpc_id

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_${local.base.az_short[each.key]}"
}

module "rt_corp" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/route"
  for_each = local.corp_routes ? toset(local.rt_azs) : toset([])

  vpc_rt_id        = module.rt[each.key].vpc_rt.id
  route_cidr_block = local.routing.corp_cidrs
  route_type       = "transit_gateway"
  route            = { transit_gateway_id = local.routing.tgw_id }
}

module "rt_peering" {
  source = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/route"
  for_each = {
    for pair in setproduct(local.rt_azs, keys(local.routing.peerings)) : "${pair[0]}_${pair[1]}" => { az = pair[0], peering = pair[1] }
  }

  vpc_rt_id        = module.rt[each.value.az].vpc_rt.id
  route_cidr_block = local.routing.peerings[each.value.peering].cidrs
  route_type       = "vpc_peering_connection"
  route            = { vpc_peering_connection_id = local.routing.peerings[each.value.peering].peering_connection_id }
}

module "rt_association" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/association"
  for_each = toset(local.rt_azs)

  route_table_id = module.rt[each.key].vpc_rt.id
  subnet_ids     = { for k, s in local.all_subnets : k => module.subnet[k].vpc_subnet[0].id if s.az == each.key }
}

# RDS가 쓸 서브넷 묶음 (2개 AZ 이상 필요)
module "subnet_group" {
  source = "../../../aws-iac-terraform-module/module/database/aws-rds-workload/subnet-group"

  name       = "${local.np}-rds-sng-main-01"
  subnet_ids = concat(values(local.db_subnet_ids), [for k, s in local.manual_subnets : module.subnet[k].vpc_subnet[0].id])

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}

# DB를 둘 서브넷 판단: 태그 Use-db = true 서브넷(01-network 용도 지정 서브넷 등)이 있으면 그것, 없으면 자기 서브넷
module "subnet_use" {
  source = "../../../aws-iac-terraform-module/module/_subnet_use_lookup"

  label           = "DB 서브넷"
  vpc_id          = local.base.vpc_id
  azs             = local.azs
  use             = "db"
  tier            = "private" # DB는 private 서브넷에만
  need_cidrs      = true      # DB 서브넷 대역을 contract로 넘김
  own_name_prefix = "${local.np}-sbn-db-"
}

# 서브넷 CIDR 검사 (이 단계가 서브넷을 만들고 subnet_cidrs를 직접 넣었을 때만): 모든 AZ, VPC 대역 안, 기존 서브넷과 겹침
module "subnet_check" {
  source = "../../../aws-iac-terraform-module/module/_subnet_cidr_check"
  count  = !local.use_shared && var.subnet_cidrs != null ? 1 : 0

  label           = "DB 서브넷 (03-database db_subnet_cidrs)"
  vpc_id          = local.base.vpc_id
  vpc_cidrs       = local.base.vpc_cidrs
  azs             = local.azs
  cidrs           = { for az, s in local.standard_subnets : az => s.cidr }
  own_name_prefix = "${local.np}-sbn-db-"
}

# 접근 허용 대역: 이 VPC에서 태그 Access-db = true 인 서브넷 (ec2-common 등이 붙임). plan 때 조회
#   그 서브넷이 나중에 생기면 03-database를 다시 apply해야 SG 규칙에 들어감
data "aws_subnets" "access_db" {
  filter {
    name   = "vpc-id"
    values = [local.base.vpc_id]
  }
  filter {
    name   = "tag:Access-db"
    values = ["true"]
  }
}

data "aws_subnet" "access_db" {
  for_each = toset(data.aws_subnets.access_db.ids)
  id       = each.value
}
