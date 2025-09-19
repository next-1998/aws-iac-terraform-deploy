locals {
  db_name = local.db_name
  root_domain = local.root_domain
}

module "security_group_rds" {
  source = "${var.module_repo_url}/module/security/aws-security-group-workload"

  name = "${local.db_name}-sg"
  vpc_id = var.vpc_id
  common_tags = var.common_tags
  resource_tags = {}
  default_security_group_rules = {
    ingress = [
      {
        from_port = var.db_engine == "mysql" ? 3306 : 6379
        to_port = var.db_engine == "mysql" ? 3306 : 6379
        protocol = "tcp"
        cidr_blocks = [
          var.vpc_primary_cidr,
          var.vpc_secondary_cidr,
          "10.227.20.0/24",
          "10.227.10.0/24",
          "100.0.0.0/8"
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

module "security_group_rds_ro" {
  source = "${var.module_repo_url}/module/security/aws-security-group-workload"
  count = var.replica_mode != false ? 1 : 0

  name = "${local.db_name}-sg-ro"
  vpc_id = var.vpc_id
  common_tags = var.common_tags
  resource_tags = {}
  default_security_group_rules = {
    ingress = [
      {
        from_port = var.db_engine == "mysql" ? 3306 : 6379
        to_port = var.db_engine == "mysql" ? 3306 : 6379
        protocol = "tcp"
        cidr_blocks = [
          var.vpc_primary_cidr,
          var.vpc_secondary_cidr,
          "10.227.20.0/24",
          "10.227.10.0/24",
          "100.0.0.0/8"
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
