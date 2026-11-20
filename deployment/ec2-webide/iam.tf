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
  # 필수 정책은 마지막에 합쳐서 var.policy_arns로 덮어쓰거나 뺄 수 없게 함
  #   ssm              : Session Manager 접속, 패치
  #   cloudwatch_agent : CloudWatch Agent 지표·로그 전송 (필수)
  policy_arns = merge(
    var.policy_arns,
    {
      ssm              = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
      cloudwatch_agent = "arn:${data.aws_partition.current.partition}:iam::aws:policy/CloudWatchAgentServerPolicy"
    },
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
