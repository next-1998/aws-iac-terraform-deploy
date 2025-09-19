module "private_subnet" {
  source = "${var.module_repo_url}/module/network/aws-sbn-workload"

  name = "${var.resource_prefix}-PRV-1"
  vpc_id = var.vpc_id
  cidr_block = [
    cidrsubnet(var.vpc_secondary_cidr, 3, 0)
  ]
  azs = var.azs[0]
  common_tags = var.common_tags
  resource_tags = {
    name = "${var.resource_prefix}-PRV-1"
    Type = "private"
  }
}

module "pri_rt_1" {
  source = "${var.module_repo_url}/module/network/aws-rtb-workload/routetable"
  name = "${var.resource_prefix}-WEB-PRV-RT"
  vpc_id = var.vpc_id
  vpc_subnet_id = module.private_subnet[0].id
  common_tags = var.common_tags
  resource_tags = {}
}

module "pri_rt_1_route_1" {
  source = "${var.module_repo_url}/module/network/aws-rtb-workload/route"

  vpc_rt_id = module.pub_rt_1.vpc_rt.id
  route_cidr_block = ["0.0.0.0/0"]
  nat_gateway_id = var.pri_nat_gw.id
  common_tags = var.common_tags
  resource_tags = {}
}

module "pri_rt_1_route_2" {
  source = "${var.module_repo_url}/module/network/aws-rtb-workload/route"

  vpc_rt_id = module.pub_rt_1.vpc_rt.id
  route_cidr_block = var.tgw_route_target_ips
  nat_gateway_id = var.pub_nat_gw.id
  common_tags = var.common_tags
  resource_tags = {}
}
