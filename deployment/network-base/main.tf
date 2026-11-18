############################################################
# network-base (01-network 단계)
#   모든 리소스가 공유하는 네트워크만 만듭니다.
#   - VPC, 기본 SG 잠금
#   - 공통 서브넷: edge, vpce, transit, public(선택)
#   - IGW, public NAT (enable_public), private NAT (internal 대역을 쓸 때)
#   - 기존 TGW에 attach, 사내망·peering 라우트 (공통 서브넷 라우트 테이블)
#   - VPC endpoint (endpoint.tf), DNS (dns.tf), prefix list (prefix_list.tf), Flow Logs (flowlog.tf)
#
#   ec2, db, eks 서브넷은 CIDR만 계산해서 넘기고, 각 <유형>-common이 만듭니다.
#   ALB/NLB는 여기서 만들지 않습니다. 필요한 리소스가 만들어질 때 그 리소스가 만듭니다.
############################################################

locals {
  stack  = "network-base"
  module = "../../../aws-iac-terraform-module/module"

  # 리소스 생성 시 붙이는 변경 태그
  resource_tags = { VpcName = var.vpc_name }

  use_tgw     = var.tgw_id != null
  has_peering = length(var.peerings) > 0

  # NAT 배치: nat_per_az = true(기본값)면 AZ마다, false면 첫 번째 AZ에 1개
  nat_azs    = var.nat_per_az ? local.layout_azs : slice(local.layout_azs, 0, min(1, length(local.layout_azs)))
  nat_for_az = { for az in local.layout_azs : az => var.nat_per_az ? az : local.layout_azs[0] }

  # private NAT: internal 대역(100.64)을 쓰고 사내망 연결이 있을 때만
  create_private_nat = local.use_internal && (local.use_tgw || local.has_peering)

  public_nat_ids  = var.enable_public ? { for az in local.layout_azs : az => aws_nat_gateway.public[local.nat_for_az[az]].id } : {}
  private_nat_ids = local.create_private_nat ? { for az in local.layout_azs : az => module.private_nat[local.nat_for_az[az]].vpc_nat.id } : {}

  # peering 라우트 (라우트 테이블 키 × peering)
  peering_routes = { for k, p in var.peerings : k => p }
}

############################################################
# VPC
############################################################
module "vpc" {
  source = "../../../aws-iac-terraform-module/module/network/aws-vpc-workload"

  name               = var.vpc_name
  vpc_primary_cidr   = local.primary_cidr
  vpc_secondary_cidr = local.secondary_cidrs

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "base"
}

# 기본 SG 잠금: AWS가 VPC마다 자동으로 만드는 default SG의 규칙을 모두 비웁니다.
# SG를 지정하지 않고 만든 리소스가 의도치 않게 통신되는 것을 막습니다 (CIS 권고).
# 코드에 규칙을 넣고 apply하면 다시 바꿀 수 있습니다. 콘솔에서 바꾸면 다음 apply 때 되돌아갑니다.
resource "aws_default_security_group" "this" {
  vpc_id = module.vpc.vpc.id
  tags   = module.tags.tags["default_sg"]
}

module "tags" {
  source = "../../../aws-iac-terraform-module/module/_tags"

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "base"

  resources = merge(
    { default_sg = { type = "ec2:security-group", abbr = "sg", name = "${var.site}-default-sg-locked", target = "default" } },
    { for az in local.nat_azs : "nat_eip_${az}" => {
      type = "ec2:elastic-ip", abbr = "eip", name = "${var.site}-nat-${local.az_short[az]}-eip", target = "public_nat_${local.az_short[az]}"
    } if var.enable_public },
    { for az in local.nat_azs : "nat_${az}" => {
      type = "ec2:natgateway", abbr = "nat", name = "${var.site}-public-${local.az_short[az]}-nat", target = "public_${local.az_short[az]}"
    } if var.enable_public },
    { for k, v in var.prefix_lists : "pl_${k}" => {
      type = "ec2:prefix-list", abbr = "pl", name = "${var.site}-${replace(k, "_", "-")}-pl", target = k
    } },
    var.enable_flow_logs ? { flow_log = { type = "ec2:vpc-flow-log", abbr = "flowlog", name = "${var.site}-vpc-flow-log" } } : {},
  )
}

############################################################
# 공통 서브넷 (edge, vpce, transit, public)
############################################################
locals {
  # 배치가 맞지 않으면(대역이 작음 등) 서브넷을 만들지 않고 checks.tf의 에러 메시지를 보여 줌
  base_subnets = !local.layout_fits ? {} : merge(
    { for az in local.layout_azs : "edge_${az}" => { purpose = "edge", az = az, tier = "private" } },
    { for az in local.layout_azs : "vpce_${az}" => { purpose = "vpce", az = az, tier = "private" } },
    { for az in local.layout_azs : "transit_${az}" => { purpose = "transit", az = az, tier = "private" } },
    var.enable_public ? { for az in local.layout_azs : "public_${az}" => { purpose = "public", az = az, tier = "public" } } : {},
  )

  # EKS Load Balancer Controller가 LB 위치를 찾는 태그
  lb_role_tags = {
    edge   = { "kubernetes.io/role/internal-elb" = "1" }
    public = { "kubernetes.io/role/elb" = "1" }
  }
}

module "subnet" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-sbn-workload"
  for_each = local.base_subnets

  name                    = "${var.site}-${each.value.purpose}-${local.az_short[each.value.az]}-subnet"
  vpc_id                  = module.vpc.vpc.id
  azs                     = each.value.az
  subnet_cidr_block       = [local.subnet_cidrs[each.value.purpose][each.value.az]]
  tier                    = each.value.tier
  map_public_ip_on_launch = false # EC2는 어디에서도 공인 IP를 받지 않음

  common_tags   = var.common_tags
  resource_tags = merge(local.resource_tags, lookup(local.lb_role_tags, each.value.purpose, {}))
  site          = var.site
  stack         = local.stack
  key_target    = "${each.value.purpose}_${local.az_short[each.value.az]}"

  depends_on = [module.vpc]
}

locals {
  subnet_ids = {
    for p in ["edge", "vpce", "transit", "public"] : p => {
      for az in local.layout_azs : az => module.subnet["${p}_${az}"].vpc_subnet[0].id if contains(keys(local.base_subnets), "${p}_${az}")
    }
  }
}

############################################################
# 인터넷 (enable_public)
############################################################
module "igw" {
  source = "../../../aws-iac-terraform-module/module/network/aws-igw-workload"
  count  = var.enable_public ? 1 : 0

  name   = "${var.site}-igw"
  vpc_id = module.vpc.vpc.id

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "base"
}

# NAT EIP: 외부에 알려준 출발지 IP라 바뀌면 협력사 화이트리스트가 깨집니다 → 삭제 보호.
# 정말 지워야 하면 이 prevent_destroy를 해제한 뒤 진행합니다.
resource "aws_eip" "nat" {
  for_each = var.enable_public ? toset(local.nat_azs) : toset([])
  domain   = "vpc"
  tags     = module.tags.tags["nat_eip_${each.key}"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_nat_gateway" "public" {
  for_each          = var.enable_public ? toset(local.nat_azs) : toset([])
  allocation_id     = aws_eip.nat[each.key].id
  subnet_id         = local.subnet_ids.public[each.key]
  connectivity_type = "public"
  tags              = module.tags.tags["nat_${each.key}"]

  depends_on = [module.igw]
}

# internal 대역(100.64) 워크로드가 사내망과 통신할 때 출발지를 routable 주소로 바꿔 줌
module "private_nat" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-natgw-workload"
  for_each = local.create_private_nat ? toset(local.nat_azs) : toset([])

  name              = "${var.site}-private-${local.az_short[each.key]}-nat"
  vpc_subnet_id     = local.subnet_ids.transit[each.key]
  connectivity_type = "private"

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "private_${local.az_short[each.key]}"
}

############################################################
# 기존 TGW에 attach (transit 서브넷)
#   승인, TGW 라우트 테이블 연결·전파는 중앙 네트워크 계정 담당 (README 사전 요청 사항)
############################################################
module "tgw_attachment" {
  source = "../../../aws-iac-terraform-module/module/network/aws-tgwattch-workload"
  count  = local.use_tgw ? 1 : 0

  name           = "${var.site}-tgwa"
  vpc_id         = module.vpc.vpc.id
  attachment_tgw = var.tgw_id
  subnet_ids     = [for az in local.layout_azs : local.subnet_ids.transit[az]]

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "base"
}

############################################################
# 라우트 테이블 (공통 서브넷)
#   public  : 0.0.0.0/0 → IGW                (enable_public)
#   edge    : 사내망 → TGW, peering 대역 → peering   (내부용 LB가 사내망 요청에 응답)
#   transit : 사내망 → TGW, peering 대역 → peering   (private NAT가 사내망으로 내보냄. 인터넷 경로 없음)
#   vpce    : 경로 없음 (local만)
#   ec2, db, eks 서브넷의 라우트는 각 <유형>-common이 만듭니다.
############################################################
locals {
  route_tables = merge(
    { for az in local.layout_azs : "edge_${az}" => { purpose = "edge", az = az } },
    { for az in local.layout_azs : "transit_${az}" => { purpose = "transit", az = az } },
  )
}

module "rt" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/routetable"
  for_each = local.route_tables

  name          = "${var.site}-${each.value.purpose}-${local.az_short[each.value.az]}-rt"
  vpc_id        = module.vpc.vpc.id
  vpc_subnet_id = [local.subnet_ids[each.value.purpose][each.value.az]]

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "${each.value.purpose}_${local.az_short[each.value.az]}"
}

module "rt_public" {
  source = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/routetable"
  count  = var.enable_public ? 1 : 0

  name          = "${var.site}-public-rt"
  vpc_id        = module.vpc.vpc.id
  vpc_subnet_id = [for az in local.layout_azs : local.subnet_ids.public[az]]

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "public"
}

module "rt_vpce" {
  source = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/routetable"

  name          = "${var.site}-vpce-rt"
  vpc_id        = module.vpc.vpc.id
  vpc_subnet_id = [for az in local.layout_azs : local.subnet_ids.vpce[az]]

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "vpce"
}

module "route_public_internet" {
  source = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/route"
  count  = var.enable_public ? 1 : 0

  vpc_rt_id        = module.rt_public[0].vpc_rt.id
  route_cidr_block = ["0.0.0.0/0"]
  route_type       = "gateway"
  route            = { gateway_id = module.igw[0].vpc_igw.id }
}

module "route_corp" {
  source   = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/route"
  for_each = local.use_tgw && length(var.corp_cidrs) > 0 ? local.route_tables : {}

  vpc_rt_id        = module.rt[each.key].vpc_rt.id
  route_cidr_block = var.corp_cidrs
  route_type       = "transit_gateway"
  route            = { transit_gateway_id = var.tgw_id }

  depends_on = [module.tgw_attachment]
}

module "route_peering" {
  source = "../../../aws-iac-terraform-module/module/network/aws-rt-workload/route"
  for_each = {
    for pair in setproduct(keys(local.route_tables), keys(var.peerings)) : "${pair[0]}_${pair[1]}" => { rt = pair[0], peering = pair[1] }
  }

  vpc_rt_id        = module.rt[each.value.rt].vpc_rt.id
  route_cidr_block = var.peerings[each.value.peering].cidrs
  route_type       = "vpc_peering_connection"
  route            = { vpc_peering_connection_id = var.peerings[each.value.peering].peering_connection_id }
}

############################################################
# Resolver rule (사내 도메인 질의를 사내 DNS로)
############################################################
module "resolver_rule" {
  source = "../../../aws-iac-terraform-module/module/network/aws-route53-workload/resolver_rule_associate"
  count  = var.resolver_rule_id != null ? 1 : 0

  name                 = "${var.site}-resolver-rule"
  vpc_id               = module.vpc.vpc.id
  vpc_resolver_rule_id = var.resolver_rule_id
}
