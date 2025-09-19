
locals {
  elasticache_name = var.elasticache_name
  elasticache_port = var.elasticache_port
  elasticache_engine_version = var.elasticache_engine_version
  elasticache_node_type = var.elasticache_node_type
  elasticache_cache_node_number = var.elasticache_cache_node_number
  root_domain = var.root_domain
}

module "security_group_elasticache" {
  source = "${var.module_repo_url}/module/security/aws-security-group-workload"

  name = "${local.elasticache_name}-sg"
  vpc_id = var.vpc_id
  common_tags = var.common_tags
  resource_tags = {}
  default_security_group_rules = {
    ingress = [
      {
        from_port = local.elasticache_engine == "memcached" ? 11211 : 6379
        to_port = local.elasticache_engine == "memcached" ? 11211 : 6379
        protocol = "tcp"
        cidr_blocks = [
          var.vpc_secondary_cidr
        ]
        description = "Security Group managed by Terraform"
      }
    ]
    egress = [
      {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        description = "Security Group managed by Terraform"
      }
    ]
  }
}


module "elasticache" {
  source = "../../module/cache/aws-elasticache-workload"

  name = var.elasticache_name
  description = "${var.elasticache_name} Elasticache Cluster managed by Terraform"
  cluster_id           = var.elasticache_name
  engine               = var.elasticache_engine
  engine_version       = var.elasticache_engine_version
  node_type            = var.elasticache_node_type
  num_cache_nodes      = var.elasticache_cache_node_number
  parameter_group_name = var.elasticache_parameter_group_name
  port                 = var.elasticache_port
  apply_immediately = true
  subnet_group_name = var.elasticache_subnet_group_name
  security_group_ids = module.security_group_elasticache.security_group_id
  common_tags = var.common_tags
  resource_tags = {}
}