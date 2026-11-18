locals { 
  root_domain = var.root_domain
  vpc_name = var.vpc_name
}

module "vpc" {
  # source = "${var.module_repo_url}/module/network/aws-vpc-workload"
  source = "../../../bsp-daytona-module/module/network/aws-vpc-workload"

  name = local.vpc_name
  vpc_primary_cidr = var.vpc_primary_cidr
  vpc_secondary_cidr = var.vpc_secondary_cidr
}

module "public_subnet" {
  # source = "${var.module_repo_url}/module/network/aws-subnet-workload"
  source = "../../../bsp-daytona-module/module/network/aws-sbn-workload"
  count =  length(var.azs)

  name = "${var.cluster_name}-subnet"
  vpc_id = module.vpc.vpc.id
  subnet_cidr_block = [
    cidrsubnet(var.vpc_primary_cidr, 1, 0),
    cidrsubnet(var.vpc_primary_cidr, 1, 1)
  ]
  azs = var.azs[count.index]
  common_tags = var.common_tags
  resource_tags = {
    Type = "public"
  }
}

module "private_subnet" {
  # source = "${var.module_repo_url}/module/network/aws-subnet-workload"
  source = "../../../bsp-daytona-module/module/network/aws-sbn-workload"
  count =  length(var.azs)

  name = "${var.cluster_name}-private-subnet"
  vpc_id = module.vpc.vpc.id
  subnet_cidr_block = [
    cidrsubnet(var.vpc_primary_cidr, 2, 2),
    cidrsubnet(var.vpc_primary_cidr, 2, 3)
  ]
  azs = var.azs[count.index]
  common_tags = var.common_tags
  resource_tags = {
    Type = "private"
  }
}

module "tgw_attachment" {
  # source = "${var.module_repo_url}/module/network/aws-tgwattch-workload"
  source = "../../../bsp-daytona-module/module/network/aws-tgwattch-workload"

  name = "${var.resource_prefix}-${var.attachment_tgw}"
  vpc_id = module.vpc.vpc.id
  subnet_ids = module.public_subnet[*].vpc_subnet.id
  attachment_tgw = var.attachment_tgw
  common_tags = var.common_tags
  resource_tags = {}
}

module "pub_rt_1" {
  # source = "${var.module_repo_url}/module/network/aws-rt-workload/routetable"
  source = "../../../bsp-daytona-module/module/network/aws-rt-workload/routetable"

  name = "${var.cluster_name}-PUB-RT"
  vpc_id = module.vpc.vpc.id
  vpc_subnet_id = module.public_subnet[0].vpc_subnet.id
  common_tags = var.common_tags
  resource_tags = {}
}

module "pub_rt_1_route_1" {
  # source = "${var.module_repo_url}/module/network/aws-rt-workload/route"
  source = "../../../bsp-daytona-module/module/network/aws-rt-workload/route"

  vpc_rt_id = module.pub_rt_1.vpc_rt.id
  route_cidr_block = ["0.0.0.0/0"]
  route = {
    gateway_id = module.igw.vpc_igw
  }
}

module "pub_rt_1_route_2" {
  # source = "${var.module_repo_url}/module/network/aws-rt-workload/route"
  source = "../../../bsp-daytona-module/module/network/aws-rt-workload/route"


  vpc_rt_id = module.pub_rt_1.vpc_rt.id
  route_cidr_block = var.tgw_route_target_ips
  route = {
    transit_gateway_id = var.attachment_tgw
  }
}

module "pub_rt_2" {
  # source = "${var.module_repo_url}/module/network/aws-rt-workload"
  source = "../../../bsp-daytona-module/module/network/aws-rt-workload/routetable"
  name = "${var.cluster_name}-PUB-RT"
  vpc_id = module.vpc.vpc.id
  vpc_subnet_id = module.public_subnet[1].vpc_subnet.id
}

module "pub_rt_2_route_1" {
  # source = "${var.module_repo_url}/module/network/aws-rt-workload/route"
  source = "../../../bsp-daytona-module/module/network/aws-rt-workload/route"

  vpc_rt_id = module.pub_rt_2.vpc_rt.id
  route_cidr_block = ["0.0.0.0/0"]
  route = {
    nat_gateway_id = module.pub_nat.vpc_nat.id
  }
}

module "pub_rt_2_route_2" {
  # source = "${var.module_repo_url}/module/network/aws-rt-workload/route"
  source = "../../../bsp-daytona-module/module/network/aws-rt-workload/route"

  vpc_rt_id = module.pub_rt_2.vpc_rt.id
  route_cidr_block = var.tgw_route_target_ips
  route = {
    transit_gateway_id = var.attachment_tgw
  }
}

module "igw" {
  # source = "${var.module_repo_url}/module/network/aws-igw-workload"
  source = "../../../bsp-daytona-module/module/network/aws-igw-workload"

  name = "${var.cluster_name}-igw"
  vpc_id = module.vpc.vpc.id
  common_tags = var.common_tags
  resource_tags = {}
}

module "eip" {
  # source = "${var.module_repo_url}/module/network/aws-eip-workload"
  source = "../../../bsp-daytona-module/module/network/aws-eip-workload"

  name = "${var.cluster_name}-eip"
  vpc_id = module.vpc.vpc.id
  common_tags = var.common_tags
  resource_tags = {}
}

module "pub_nat" {
  # source = "${var.module_repo_url}/module/network/aws-natgw-workload"
  source = "../../../bsp-daytona-module/module/network/aws-natgw-workload"

  name = "${var.cluster_name}-Nat-Gateway"
  vpc_subnet_id = module.public_subnet[0].vpc_subnet.id
  eip_id = module.eip.vpc_eip.id
  connectivity_type = "public"
  common_tags = var.common_tags
  resource_tags = {}
}

module "pri_nat" {
  # source = "${var.module_repo_url}/module/network/aws-natgw-workload"
  source = "../../../bsp-daytona-module/module/network/aws-natgw-workload"

  name = "${var.cluster_name}-Private-Nat-Gateway"
  vpc_subnet_id = module.private_subnet[0].vpc_subnet.id
  connectivity_type = "private"
  common_tags = var.common_tags
  resource_tags = {}
}

module "r53_zones" {
  # source  = "${var.module_repo_url}/module/network/aws-route53-workload/zones"
  source  = "../../../bsp-daytona-module/module/network/aws-route53-workload/zones"

  zones = {
    "${var.cluster_name}.${local.root_domain}" = {
      comment = "${var.cluster_name}.${local.root_domain}"
    }
  }
  common_tags = var.common_tags
  resource_tags = {}
}

module "resolver_rule" {
  source = "../../../bsp-daytona-module/module/network/aws-route53-workload/resolver_rule_associate"
  name = "${var.cluster_name}-Resolver-Rule"
  vpc_id = module.vpc.vpc.id
  vpc_resolver_rule_id = var.vpc_resolver_rule_id
}

data "aws_route53_zone" "daytona" {
  # provider     = aws.daytona
  name         = local.root_domain
}

module "r53_record_daytona_ns" {
  source = "../../../bsp-daytona-module/module/network/aws-route53-workload/records"

  zone_id = data.aws_route53_zone.daytona.id
  records = [
    {
      name = keys(module.r53_zones.route53_zone_zone_id)[0]
      type = "NS"
      ttl = "30"
      records = lookup(module.r53_zones.route53_zone_name_servers, keys(module.r53_zones.route53_zone_zone_id)[0])
    }
  ]
}



# variable "domain_name" {
#   description = "Domain Name"
#   type = string
#   default = "${var.cluster_name}.${local.root_domain}"
# }