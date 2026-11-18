############################################################
# network-base
# 모든 stack이 공유하는 네트워크만 만듭니다.
#   VPC, edge/transit 서브넷, IGW·public NAT(선택), private NAT(routable + internal),
#   TGW attachment, Route53 존, Resolver 연결
# stack 전용 서브넷, SG, role 등은 각 stack이 만듭니다.
# 대역 배치 규칙은 layout.tf
############################################################

locals {
  stack = "network-base" # 폴더 이름 = stack 이름 (Stack 태그: <site>/network-base)

  # 리소스 생성 시 붙이는 변경 태그
  resource_tags = { VpcName = var.vpc_name }

  az_short = { for az in local.azs : az => substr(az, -1, 1) }

  use_tgw            = var.tgw_id != null
  create_private_nat = local.network_type == "hybrid" && local.use_tgw
  zone_name          = var.root_domain != "" ? "${var.site}.${var.root_domain}" : null

  # NAT 배치: nat_per_az = true(기본값)면 AZ마다, false면 첫 번째 AZ(a)에 1개
  nat_azs    = var.nat_per_az ? local.azs : [local.azs[0]]
  nat_for_az = { for az in local.azs : az => var.nat_per_az ? az : local.azs[0] }

  # AZ → 그 AZ가 사용할 NAT ID
  public_nat_ids  = var.enable_internet ? { for az in local.azs : az => module.public_nat[local.nat_for_az[az]].vpc_nat.id } : {}
  private_nat_ids = local.create_private_nat ? { for az in local.azs : az => module.private_nat[local.nat_for_az[az]].vpc_nat.id } : {}
}

############################################################
# VPC
############################################################
module "vpc" {
  source = "../../../aws-iac-terraform-module/module/network/aws-vpc-workload"

  name               = var.vpc_name
  vpc_primary_cidr   = local.routable
  vpc_secondary_cidr = [for c in slice(var.vpc_cidrs, 1, length(var.vpc_cidrs)) : c.cidr]

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "base"
}

############################################################
# edge 서브넷 (ALB, public NAT)
#   0.0.0.0/0 → IGW (enable_internet), 사내망 → TGW
############################################################
module "edge_subnet" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-sbn-workload"
  for_each = local.edge_cidrs

  name                    = "${var.site}-edge-${local.az_short[each.key]}-subnet"
  vpc_id                  = module.vpc.vpc.id
  azs                     = each.key
  subnet_cidr_block       = [each.value]
  tier                    = var.enable_internet ? "public" : "private"
  map_public_ip_on_launch = false

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "edge_${local.az_short[each.key]}"

  depends_on = [module.vpc]
}

module "edge_rt" {
  source = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/routetable"

  name          = "${var.site}-edge-rt"
  vpc_id        = module.vpc.vpc.id
  vpc_subnet_id = [for az in local.azs : module.edge_subnet[az].vpc_subnet[0].id]

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "edge"
}

module "edge_rt_internet" {
  source = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/route"
  count  = var.enable_internet ? 1 : 0

  vpc_rt_id        = module.edge_rt.vpc_rt.id
  route_cidr_block = ["0.0.0.0/0"]
  route_type       = "gateway"
  route            = { gateway_id = module.igw[0].vpc_igw.id }
}

module "edge_rt_tgw" {
  source = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/route"
  count  = local.use_tgw && length(var.tgw_route_cidrs) > 0 ? 1 : 0

  vpc_rt_id        = module.edge_rt.vpc_rt.id
  route_cidr_block = var.tgw_route_cidrs
  route_type       = "transit_gateway"
  route            = { transit_gateway_id = var.tgw_id }

  depends_on = [module.tgw_attachment]
}

############################################################
# 인터넷 출구 (선택, 기본값 생성)
############################################################
module "igw" {
  source = "../../../aws-iac-terraform-module/module/network/aws-igw-workload"
  count  = var.enable_internet ? 1 : 0

  name   = "${var.site}-igw"
  vpc_id = module.vpc.vpc.id

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "base"
}

module "public_nat_eip" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-eip-workload"
  for_each = var.enable_internet ? toset(local.nat_azs) : toset([])

  name   = "${var.site}-nat-${local.az_short[each.key]}-eip"
  vpc_id = module.vpc.vpc.id

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "public_nat_${local.az_short[each.key]}"
}

module "public_nat" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-natgw-workload"
  for_each = var.enable_internet ? toset(local.nat_azs) : toset([])

  name              = "${var.site}-public-${local.az_short[each.key]}-nat"
  vpc_subnet_id     = module.edge_subnet[each.key].vpc_subnet[0].id
  eip_id            = module.public_nat_eip[each.key].vpc_eip.id
  connectivity_type = "public"

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "public_${local.az_short[each.key]}"

  depends_on = [module.igw]
}

############################################################
# transit 서브넷 (TGW attachment, private NAT)
#   사내망 → TGW, 0.0.0.0/0 → public NAT (enable_internet)
############################################################
module "transit_subnet" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-sbn-workload"
  for_each = local.transit_cidrs

  name              = "${var.site}-transit-${local.az_short[each.key]}-subnet"
  vpc_id            = module.vpc.vpc.id
  azs               = each.key
  subnet_cidr_block = [each.value]
  tier              = "private"

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "transit_${local.az_short[each.key]}"

  depends_on = [module.vpc]
}

# AZ마다 라우트 테이블 (같은 AZ의 public NAT로 나가도록)
module "transit_rt" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/routetable"
  for_each = toset(local.azs)

  name          = "${var.site}-transit-${local.az_short[each.key]}-rt"
  vpc_id        = module.vpc.vpc.id
  vpc_subnet_id = [module.transit_subnet[each.key].vpc_subnet[0].id]

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "transit_${local.az_short[each.key]}"
}

module "transit_rt_internet" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/route"
  for_each = var.enable_internet ? toset(local.azs) : toset([])

  vpc_rt_id        = module.transit_rt[each.key].vpc_rt.id
  route_cidr_block = ["0.0.0.0/0"]
  route_type       = "nat_gateway"
  route            = { nat_gateway_id = local.public_nat_ids[each.key] }
}

module "transit_rt_tgw" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/route"
  for_each = local.use_tgw && length(var.tgw_route_cidrs) > 0 ? toset(local.azs) : toset([])

  vpc_rt_id        = module.transit_rt[each.key].vpc_rt.id
  route_cidr_block = var.tgw_route_cidrs
  route_type       = "transit_gateway"
  route            = { transit_gateway_id = var.tgw_id }

  depends_on = [module.tgw_attachment]
}

# internal 대역 워크로드가 사내망과 통신할 때 출발지를 routable 주소로 바꿔 줌
module "private_nat" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-natgw-workload"
  for_each = local.create_private_nat ? toset(local.nat_azs) : toset([])

  name              = "${var.site}-private-${local.az_short[each.key]}-nat"
  vpc_subnet_id     = module.transit_subnet[each.key].vpc_subnet[0].id
  connectivity_type = "private"

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "private_${local.az_short[each.key]}"
}

############################################################
# TGW attachment (transit 서브넷)
############################################################
module "tgw_attachment" {
  source = "../../../aws-iac-terraform-module/module/network/aws-tgwattch-workload"
  count  = local.use_tgw ? 1 : 0

  name           = "${var.site}-tgwa"
  vpc_id         = module.vpc.vpc.id
  attachment_tgw = var.tgw_id
  subnet_ids     = [for az in local.azs : module.transit_subnet[az].vpc_subnet[0].id]

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "base"
}

############################################################
# DNS (선택)
############################################################
module "zone" {
  source = "../../../aws-iac-terraform-module/module/network/aws-route53-workload/zones"
  count  = local.zone_name != null ? 1 : 0

  zones = {
    (local.zone_name) = { comment = local.zone_name }
  }

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "base"
}

data "aws_route53_zone" "parent" {
  count = local.zone_name != null ? 1 : 0
  name  = var.root_domain
}

module "zone_delegation" {
  source = "../../../aws-iac-terraform-module/module/network/aws-route53-workload/records"
  count  = local.zone_name != null ? 1 : 0

  zone_id   = data.aws_route53_zone.parent[0].zone_id
  zone_name = var.root_domain
  records = [
    {
      name    = var.site
      type    = "NS"
      ttl     = 300
      records = jsonencode(module.zone[0].route53_zone_name_servers[local.zone_name])
    }
  ]
}

module "resolver_rule" {
  source = "../../../aws-iac-terraform-module/module/network/aws-route53-workload/resolver_rule_associate"
  count  = var.resolver_rule_id != null ? 1 : 0

  name                 = "${var.site}-resolver-rule"
  vpc_id               = module.vpc.vpc.id
  vpc_resolver_rule_id = var.resolver_rule_id
}
