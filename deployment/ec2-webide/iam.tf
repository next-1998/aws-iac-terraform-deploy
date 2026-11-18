############################################################
# EC2 role (instance profile은 ec2.tf의 instance 모듈이 만듦)
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

  policies = merge(
    { ssm = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore" },
    var.policy_arns,
  )

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}
