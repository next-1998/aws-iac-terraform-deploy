module "sts_endpoints" {
  source = "${var.module_repo_url}//module/network/aws-vpce-workload/vpc-endpoints"

  name = "${var.resource_prefix}-sts-vpce"
  vpc_id             = var.vpc_id
  security_group_ids = module.vpce_securitygroup.securitygroup.id[*]

  endpoints = {
    # s3_gw = {
    #   # gateway endpoint
    #   service         = "s3"
    #   route_table_ids = [var.pub_subnet_ids[*]]
    # },
    sts = {
      service             = "sts"
      private_dns_enabled = true
      security_group_ids  = [module.vpce_sts_securitygroup.securitygroup.id[*]]
      subnet_ids          = [var.pri_subnet_ids[*]] //생성하거나 기존것 가져 오기
    }
  }

  common_tags = var.common_tags
  resource_tags = var.resource_tags
}

module "vpce_sts_securitygroup" {
  source = "${var.module_repo_url}//module/network/aws-elb-workload/securitygroup"

  name = "${local.was_alb}-vpce-sts-sg"
  vpc_id = var.vpc_id
  common_tags = var.common_tags
  resource_tags = var.resource_tags
  default_security_group_rules = {
    ingress = [
      {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = [ var.vpc_primary_cidr, var.vpc_secondary_cidr ]
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