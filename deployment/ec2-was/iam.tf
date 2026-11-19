############################################################
# EC2 role, 정책 연결, instance profile (1차 조합: EC2를 만들 때 필요한 IAM)
############################################################

data "aws_partition" "current" {}

module "role" {
  source = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role"

  name        = "${local.prefix}-role"
  description = "EC2 role for ${local.prefix}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}

module "role_policy" {
  source = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy-attachment"

  role_name = module.role.name
  policy_arns = merge(
    { ssm = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore" },
    var.policy_arns,
  )
}

module "instance_profile" {
  source = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/instance-profile"

  name      = "${local.prefix}-profile"
  role_name = module.role.name

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}
