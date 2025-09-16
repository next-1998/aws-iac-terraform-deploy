#############################################
# was instance
#############################################

locals {
  local_public_key = var.local_public_key
  service_public_key = var.service_public_key
  was_name = var.was_name
}

module "role_ec2_was" {
  source = "${var.module_repo_url}//module/security/aws-iam-workload/role"

  name = "${var.resource_prefix}-CodeDeploy-Instance-Profile-Rol"
  path = "/"
  description = "codedeploy instance role"

  assume_role_policy = jsondecode(file("${path.module}/json/codedeploy-instance-role.json"))
#   <<EOF
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
    AmazonEC2RoleforAWSCodeDeploy = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforAWSCodeDeploy"
  }
}

module "security_group_was" {
  source = "${var.module_repo_url}//module/security/aws-security-group-workload"

  name = "${local.was_name}-sg"
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
          var.pub_subnet_ids[1].cidr_block,
          var.vpc_secondary_cidr
        ]
        description = "Security Group managed by Terraform"
      },
      {
        from_port = 8080
        to_port = 8080
        protocol = "tcp"
        cidr_blocks = [
          var.pub_subnet_ids[0].cidr_block,
          var.pub_subnet_ids[1].cidr_block,
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

module "ec2_was" {
  source  = "${var.module_repo_url}//module/computing/aws-ec2-instance-workload"

  profile_name           = "${var.resource_prefix}-CodeDeploy-Instance-Profile"
  role                   = module.role_ec2_was.name
  name                   = local.was_name
  ami                    = var.was_instance_ami
  instance_type          = var.was_instance_type
  key_name               = "ec2-key-pair"
  monitoring             = true
  vpc_security_group_ids = [module.security_group_was.security_group_id]
  subnet_id              = var.pri_subnet_ids[0]
  # remove public ip
  associate_public_ip_address = false

  root_block_device = [
    {
      volume_size = var.instance_root_volume
    }
  ]

  common_tags = var.common_tags
  resource_tags = {
    codeDeployTarget = "true"
  }

  user_data = base64encode(templatefile("${path.module}/tpl/run_was.tpl",
    {
      local_public_key=format("%s %s",chomp(local.local_public_key), var.local_keypair_name)
      service_public_key=format("%s %s",chomp(local.service_public_key), var.service_keypair_name)
      was_engine_volume_path=var.was_instance_engine_volume_device_name
      was_log_volume_path=var.was_instance_log_volume_device_name
      was_engine_volume_mount_path=var.was_instance_engine_volume_mount_path
      was_log_volume_mount_path=var.was_instance_log_volume_mount_path
    }))
//volume dependency
  # depends_on = [aws_nat_gateway.tier_nat]
}

module "ebs_was_log_volume" {
  source = "${var.module_repo_url}//module/computing/aws-ebs-workload"
  availability_zone = var.subnet_id == var.pri_subnet_ids[0] ? "ap-northeast-2a" : "ap-northeast-2c"
  name = "${local.was_name}-log-volume"
  volume_size = var.was_instance_log_volume
  device_name = var.was_instance_log_volume_device_name
  instance_id = module.ec2_was.id
  force_detach = true
}

module "ebs_was_app_volume" {
  source = "${var.module_repo_url}//module/computing(작업중)/aws-ebs-workload"
  availability_zone = var.subnet_id == var.pri_subnet_ids[0] ? "ap-northeast-2a" : "ap-northeast-2c"
  name = "${local.was_name}-app-volume"
  volume_size = var.was_instance_engine_volume
  device_name = var.was_instance_engine_volume_device_name
  instance_id = module.ec2_was.id
  force_detach = true
}

# module "ebs_add_volume" {
#   source = "./module/computing(작업중)/aws-ebs-workload"
#   for_each = try(var.ebs_add_volume, {})
  
#   availability_zone = try(var.ebs_add_volume[each.key].availability_zone, null)
#   name = try(var.ebs_add_volume[each.key].name, null)
#   volume_size = try(var.was_instance_log_volume, null)
#   device_name = try(var.ebs_add_volume[each.key].device_name, null)
#   instance_id = module.ec2_was.id
#   force_detach = true
# }




#############################################
# web-ide instance
#############################################