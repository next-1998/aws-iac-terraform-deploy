#############################################
# web-ide instance
#############################################

locals {
  web_ide_name = var.web_ide_name
  service_private_key = var.service_private_key
  root_domain = var.root_domain
  daytona_url = var.daytona_url
  KEYCLOAK_ENDPOINT = var.KEYCLOAK_ENDPOINT
}

module "role_ec2_web_ide" {
  source = "${var.module_repo_url}/module/security/aws-iam-workload/role"

  name = "${var.resource_prefix}-WEB-IDE-Instance-Profile-Role"
  path = "/"
  description = "web-ide instance role"

  assume_role_policy = jsondecode(file("${path.module}/json/web-ide-instance-profile-role.json"))
# <<EOF
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Sid": "",
#       "Effect": "Allow",
#       "Principal": {
#         "Service": [
#           "ec2.amazonaws.com"
#         ]
#       },
#       "Action": "sts:AssumeRole"
#     }
#   ]
# }
# EOF

  policies = {
    PowerUserAccess = "arn:aws:iam::aws:policy/PowerUserAccess"
  }
}

module "security_group_web_ide" {
  source = "${var.module_repo_url}/module/security/aws-security-group-workload"

  name = "${local.web_ide_name}-sg"
  vpc_id = var.vpc_id
  common_tags = var.common_tags
  resource_tags = {}
  default_security_group_rules = {
    ingress = [
      {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [
          var.pub_subnet_ids[0].cidr_block,
          var.pub_subnet_ids[1].cidr_block
        ]
        description = "Security Group managed by Terraform"
      },
      {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = [
          var.pub_subnet_ids[0].cidr_block,
          var.pub_subnet_ids[1].cidr_block
        ]
        description = "Security Group managed by Terraform"
      },
      {
        from_port = 8080
        to_port = 8080
        protocol = "tcp"
        cidr_blocks = [
          var.pub_subnet_ids[0].cidr_block,
          var.pub_subnet_ids[1].cidr_block
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


data "aws_ami" "ec2_golden_ami" {
  count = var.web_ide_instance_ami == null ? 1 : 0
	most_recent = true
	filter {
		name = "name"
		values = [ var.golden_image ]
	}
	
	owners = ["${var.ami_owner_account}"]
}


module "ec2_lt_web_ide" {
  source  = "${var.module_repo_url}/module/computing(작업중)/aws-instance-workload"

  ##w profile
  profile_name           = "${var.resource_prefix}-web-ide-instance-profile"
  role                   = module.role_ec2_web_ide.name

  ## launch template
  name                   = local.web_ide_name
  image_id               = try(var.web_ide_instance_ami, data.aws_ami.ec2_golden_ami[0].id)
  instance_type          = var.web_ide_instance_type
  key_name               = var.common_key_pair_name
 
  monitoring {
    enabled = true
  }

  network_interfaces {
    associate_public_ip_address = false
    subnet_id                   = var.pri_subnet_ids[0]
    security_groups             = [module.security_group_web_ide.security_group_id]
  }
  
  tag_type                = ["instance", "volume"]
  common_tags = var.common_tags
  resource_tags = {}

  user_data = base64encode(templatefile("${path.module}/tpl/run_web_ide.tpl",
    {
      service_private_key=local.service_private_key
      web_ide_server_name="${var.cluster_name}.${local.root_domain}"
      web_ide_port="3000"
      client_id=var.KEYCLOAK_CLIENT_ID
      client_secret=var.KEYCLOAK_CLIENT_SECRET
      keycloak_endpoint=local.KEYCLOAK_ENDPOINT
      user_uuid=var.KEYCLOAK_USER_UUID
      oidc_auth_url="${local.KEYCLOAK_ENDPOINT}/auth/realms/${var.KEYCLOAK_REALM}"
      redirect_uri="https:/ide.${var.cluster_name}.${local.root_domain}/callback"
      daytona_url=local.daytona_url
      get_access_token_url="${local.KEYCLOAK_ENDPOINT}/auth/realms/${var.KEYCLOAK_REALM}/protocol/openid-connect/token"
      get_client_info_url="${local.KEYCLOAK_ENDPOINT}/auth/admin/realms/${var.KEYCLOAK_REALM}/clients/${var.KEYCLOAK_CLIENT_UUID}"
      update_client_info_url="${local.KEYCLOAK_ENDPOINT}/auth/admin/realms/${var.KEYCLOAK_REALM}/clients/${var.KEYCLOAK_CLIENT_UUID}"
      valid_uri="\"https:/ide.${var.cluster_name}.${local.root_domain}/*\""
    }))
}