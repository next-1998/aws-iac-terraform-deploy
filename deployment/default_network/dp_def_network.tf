locals { 
  root_domain = var.root_domain
  vpc_name = var.vpc_name
}

module "vpc" {
  source = "${var.module_repo_url}//module/network/aws-vpc-workload"

  name = local.vpc_name
  vpc_primary_cidr = var.vpc_primary_cidr
  vpc_secondary_cidr = var.vpc_secondary_cidr
}

module "public_subnet" {
  source = "${var.module_repo_url}//module/network/aws-subnet-workload"
  count =  length(var.azs)

  name = "${var.cluster_name}-subnet"
  vpc_id = module.vpc.vpc.id
  cidr_block = [
    cidrsubnet(var.vpc_primary_cidr, 1, 0),
    cidrsubnet(var.vpc_primary_cidr, 1, 1)
  ]
  azs = var.azs[count.index]
  common_tags = var.common_tags
  resource_tags = {
    Type = "public"
  }
}

module "tgw_attachment" {
  source = "${var.module_repo_url}//module/network/aws-tgwattch-workload"

  name = "${var.resource_prefix}-${var.attachment_tgw}"
  vpc_id = module.vpc.vpc.id
  subnet_ids = module.public_subnet.vpc_subnet[*].id
  attachment_tgw = var.attachment_tgw
  common_tags = var.common_tags
  resource_tags = {}
}

module "pub_rt_1" {
  source = "${var.module_repo_url}//module/network/aws-rtb-workload/routetable"
  name = "${var.cluster_name}-PUB-RT"
  vpc_id = module.vpc.vpc.id
  vpc_subnet_id = module.public_subnet.vpc_subnet[0].id
  common_tags = var.common_tags
  resource_tags = {}
}

module "pub_rt_1_route_1" {
  source = "${var.module_repo_url}//module/network/aws-rtb-workload/route"

  vpc_rt_id = module.pub_rt_1.vpc_rt.id
  route_cidr_block = ["0.0.0.0/0"]
  gateway_id = module.igw.igw.id
  common_tags = var.common_tags
  resource_tags = {}
}

module "pub_rt_1_route_2" {
  source = "${var.module_repo_url}//module/network/aws-rtb-workload/route"

  vpc_rt_id = module.pub_rt_1.vpc_rt.id
  route_cidr_block = var.tgw_route_target_ips
  transit_gateway_id = var.attachment_tgw
  common_tags = var.common_tags
  resource_tags = {}
}

module "pub_rt_2" {
  source = "${var.module_repo_url}//module/network/aws-rtb-workload"
  name = "${var.cluster_name}-PUB-RT"
  vpc_id = module.vpc.vpc.id
  vpc_subnet_id = module.public_subnet.vpc_subnet[1].id
  common_tags = var.common_tags
  resource_tags = {}
}

module "pub_rt_2_route_1" {
  source = "${var.module_repo_url}//module/network/aws-rtb-workload/route"
  vpc_rt_id = module.pub_rt_2.vpc_rt.id
  route_cidr_block = ["0.0.0.0/0"]
  nat_gateway_id = module.pub_nat.nat_gw.id
  common_tags = var.common_tags
  resource_tags = {}
}

module "pub_rt_2_route_2" {
  source = "${var.module_repo_url}//module/network/aws-rtb-workload/route"
  vpc_rt_id = module.pub_rt_2.vpc_rt.id
  route_cidr_block = var.tgw_route_target_ips
  transit_gateway_id = var.attachment_tgw
  common_tags = var.common_tags
  resource_tags = {}
}

module "igw" {
  source = "${var.module_repo_url}//module/network/aws-igw-workload"

  name = "${var.cluster_name}-igw"
  vpc_id = module.vpc.vpc.id
  common_tags = var.common_tags
  resource_tags = {}
}

module "eip" {
  source = "${var.module_repo_url}//module/network/aws-eip-workload"

  name = "${var.cluster_name}-eip"
  common_tags = var.common_tags
  resource_tags = {}
}

module "pub_nat" {
  source = "${var.module_repo_url}//module/network/aws-natgw-workload"

  name = "${var.cluster_name}-Nat-Gateway"
  vpc_subnet_id = module.public_subnet.vpc_subnet[0].id
  eip_id = module.eip.eip.id
  connectivity_type = "public"
  common_tags = var.common_tags
  resource_tags = {}
}

module "pri_nat" {
  source = "${var.module_repo_url}//module/network/aws-natgw-workload"

  name = "${var.cluster_name}-Private-Nat-Gateway"
  vpc_subnet_id = module.private_subnet.vpc_subnet[0].id
  connectivity_type = "private"
  common_tags = var.common_tags
  resource_tags = {}
}

module "r53_zones" {
  source  = "${var.module_repo_url}//module/network/aws-route53-workload(확인필요)/zones"

  zones = {
    "${var.cluster_name}.${local.root_domain}" = {
      comment = "${var.cluster_name}.${local.root_domain}"
    }
  }
}

module "r53_records" {
  source  = "${var.module_repo_url}//module/network/aws-route53-workload(확인필요)/records"

  zone_name = keys(module.r53_zones.route53_zone_zone_id)[0]
  records = [
    {
      name = "web"
      type = "A"
      alias = {
        name = var.was_alb.dns_name
        zone_id = var.was_alb.zone_id
        evaluate_target_health = true
      }
    },
    {
      name = "ide"
      type = "A"
      alias = {
        name = var.web_ide_alb.dns_name
        zone_id = var.web_ide_alb.zone_id
        evaluate_target_health = true
      }
    },
    {
      name = "ide-preview"
      type = "A"
      alias = {
        name = var.web_ide_alb.dns_name
        zone_id = var.web_ide_alb.zone_id
        evaluate_target_health = true
      }
    }
  ]

}



# variable "domain_name" {
#   description = "Domain Name"
#   type = string
#   default = "${var.cluster_name}.${local.root_domain}"
# }