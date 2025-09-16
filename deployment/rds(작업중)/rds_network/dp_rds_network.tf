

module "rds_subnet" {
  source = "${var.module_repo_url}//module/network/aws-sbn-workload"
  count =  length(var.azs)

  name = "${var.resource_prefix}-ElasticCache-${count.index+1}"
  vpc_id = var.vpc_id
  cidr_block = [
    cidrsubnet(var.vpc_secondary_cidr, 3, 1),
    cidrsubnet(var.vpc_secondary_cidr, 3, 2)
  ]
  azs = var.azs[count.index]
  common_tags = var.common_tags
  resource_tags = {
    Type = "private"
    name =  "${var.resource_prefix}-ElasticCache-${count.index+1}"
  }
}

module "cache_rt_1" {
  source = "${var.module_repo_url}//module/network/aws-rtb-workload/routetable"
  name = "${var.resource_prefix}-ElastiCache-RT"
  vpc_id = var.vpc_id
  vpc_subnet_id = module.cache_subnet[0].id
  common_tags = var.common_tags
  resource_tags = {}
}

module "cache_rt_1_route_1" {
  source = "${var.module_repo_url}//module/network/aws-rtb-workload/route"

  vpc_rt_id = module.pub_rt_1.vpc_rt.id
  route_cidr_block = ["0.0.0.0/0"]
  nat_gateway_id = var.pri_nat_gw.id
  common_tags = var.common_tags
  resource_tags = {}
}

module "cache_rt_1_route_2" {
  source = "${var.module_repo_url}//module/network/aws-rtb-workload/route"

  vpc_rt_id = module.pub_rt_1.vpc_rt.id
  route_cidr_block = var.tgw_route_target_ips
  attachment_tgw = var.attachment_tgw
  common_tags = var.common_tags
  resource_tags = {}
}

module "rds_subnet_group" {
  source = "${var.module_repo_url}//module/network/aws-sbn-workload/subnetgroup"
  name = "${var.resource_prefix}-RDS-SubnetGroup"
  vpc_id = var.vpc_id
  subnet_ids = module.rds_subnet[*].id
  common_tags = var.common_tags
  resource_tags = {}
}