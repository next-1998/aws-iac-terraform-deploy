data "aws_caller_identity" "current" {}

module "default_network" {
  source = "./deployment/default_network"
  module_repo_url = var.module_repo_url
  vpc_name = var.vpc_name
  cluster_name = var.cluster_name
  root_domain = local.root_domain
  resource_prefix = var.resource_prefix
  common_tags = var.common_tags
  vpc_primary_cidr = var.vpc_primary_cidr
  vpc_secondary_cidr = var.vpc_secondary_cidr
  azs = var.azs
  tgw_route_target_ips = var.tgw_route_target_ips
  resource_tags = {}
}

module "elb" {
  source = "./deployment/elb"
  module_repo_url = var.module_repo_url
  was_alb = local.was_alb
  web_ide_alb = local.web_ide_alb
  vpc_id = module.default_network.vpc_id
  pub_subnet_ids = module.default_network.pub_subnet_ids
  pri_subnet_ids = module.ec2_network.pri_subnet_ids
  certificate_arn = module.acm.acm_certificate_arn
  ec2_was_id = module.ec2_was.id
  ec2_web_ide_id = module.ec2_web_ide.id
  was_name = local.was_name
  web_ide_name = local.web_ide_name
  resource_prefix = var.resource_prefix
  cluster_name = var.cluster_name
  root_domain = local.root_domain
  common_tags = var.common_tags
  resource_tags = {}
}

module "keypair" {
  source = "./deployment/keypair"
  module_repo_url = var.module_repo_url
  local_keypair_name = var.local_keypair_name
  service_keypair_name =var.service_keypair_name
  resource_tags = {}
  common_tags = var.common_tags
}

module "acm" {
  source = "./deployment/acm"
  module_repo_url = var.module_repo_url
  cluster_name = var.cluster_name
  root_domain = local.root_domain
}

module "codedeploy" {
  source = "./deployment/codedeploy"
  module_repo_url = var.module_repo_url
  resource_prefix = var.resource_prefix
  common_tags = var.common_tags
  resource_tags = {}
}

module "lambda" {
  source = "./deployment/lambda"
  module_repo_url = var.module_repo_url
  resource_prefix = var.resource_prefix
  common_tags = var.common_tags
  resource_tags = {}
}

module "ec2_network" {
  source = "./deployment/ec2/ec2_network"
  module_repo_url = var.module_repo_url
  resource_prefix = var.resource_prefix
  vpc_id = module.default_network.vpc_id
  pri_nat_gw = module.default_network.pri_nat_gw
  pub_nat_gw = module.default_network.pub_nat_gw
  pri_subnet_ids = module.default_network.pri_subnet_ids
  tgw_route_target_ips = var.tgw_route_target_ips
  common_tags = var.common_tags
}

module "ec2_was" {
  source = "./deployment/ec2/ec2_was"
  module_repo_url = var.module_repo_url
  local_public_key = module.keypair.local_public_key
  service_public_key = module.keypair.service_public_key
  was_name = local.was_name
  vpc_id = module.default_network.vpc_id
  common_tags = var.common_tags
  pub_subnet_ids = module.default_network.pub_subnet_ids
  pri_subnet_ids = module.ec2_network.pri_subnet_ids
  vpc_secondary_cidr = var.vpc_secondary_cidr
  resource_prefix = var.resource_prefix
  was_instance_ami = var.was_instance_ami
  was_instance_type = var.was_instance_type
  instance_root_volume = var.was_instance_root_volume
  was_instance_log_volume = var.was_instance_log_volume
  was_instance_engine_volume = var.was_instance_engine_volume
  was_instance_engine_volume_device_name = var.was_instance_engine_volume_device_name
  was_instance_log_volume_device_name = var.was_instance_log_volume_device_name
  was_instance_engine_volume_mount_path = var.was_instance_engine_volume_mount_path
  was_instance_log_volume_mount_path = var.was_instance_log_volume_mount_path
  availability_zone = var.azs[0]
  resource_tags = {}
}

module "ec2_web_ide" {
  source = "./deployment/ec2/ec2_web_ide"
  module_repo_url = var.module_repo_url
  web_ide_name = local.web_ide_name
  service_private_key = module.keypair.service_private_key
  root_domain = local.root_domain
  daytona_url = local.daytona_url
  KEYCLOAK_ENDPOINT = local.KEYCLOAK_ENDPOINT
  resource_prefix = var.resource_prefix
  vpc_id = module.default_network.vpc_id
  common_tags = var.common_tags
  pub_subnet_ids = module.default_network.pub_subnet_ids
  pri_subnet_ids = module.ec2_network.pri_subnet_ids
  vpc_secondary_cidr = var.vpc_secondary_cidr
  golden_image = ""
  ami_owner_account = data.aws_caller_identity.current.account_id
  web_ide_instance_ami = var.web_ide_instance_ami
  web_ide_instance_type = var.web_ide_instance_type
  common_key_pair_name = var.common_key_pair_name
  cluster_name = var.cluster_name
  KEYCLOAK_REALM = var.KEYCLOAK_REALM
  KEYCLOAK_CLIENT_ID = var.KEYCLOAK_CLIENT_ID
  KEYCLOAK_CLIENT_SECRET = var.KEYCLOAK_CLIENT_SECRET
  KEYCLOAK_CLIENT_UUID = var.KEYCLOAK_CLIENT_UUID
  resource_tags = {}
}

module "cache_network" {
  source = "./deployment/elasticache/elc_network"
  count = local.create_elasticache ? 1 : 0

  module_repo_url = var.module_repo_url
  resource_prefix = var.resource_prefix
  vpc_id = module.default_network.vpc_id
  pri_nat_gw = module.default_network.pri_nat_gw
  pub_nat_gw = module.default_network.pub_nat_gw
  cache_subnet_ids = module.default_network.pri_subnet_ids
  tgw_route_target_ips = var.tgw_route_target_ips
  common_tags = var.common_tags
  azs = var.azs
  vpc_secondary_cidr = var.vpc_secondary_cidr
  cluster_name = var.cluster_name
  attachment_tgw = var.attachment_tgw
}

module "elasticache" {
  source = "./deployment/elasticache/elasticache"
  count = local.create_elasticache ? 1 : 0

  module_repo_url      = var.module_repo_url
  elasticache_name     = local.elasticache_name
  elasticache_engine   = var.elasticache_engine
  elasticache_engine_version  = local.elasticache_engine_version
  elasticache_node_type = var.elasticache_node_type
  elasticache_cache_node_number = local.elasticache_cache_node_number
  elasticache_parameter_group_name = local.elasticache_parameter_group_name
  elasticache_port = local.elasticache_port
  common_tags          = var.common_tags
  resource_tags        = {}
}


