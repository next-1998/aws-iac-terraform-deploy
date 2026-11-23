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
# 로그 그룹은 Terraform이 미리 만든 것만 씀 (보안 기본값)
#   CloudWatchAgentServerPolicy에는 로그 그룹 생성·보관 기간 변경 권한이 있어,
#   설정이 어긋나면 Agent가 보관 기간 무기한·CMK 없는 로그 그룹을 만들 수 있음 → 명시적으로 거부
module "role_policy_logs_guard" {
  source = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy"

  role_name = module.role.name
  policies = {
    "${local.prefix}-logs-guard" = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid      = "DenyLogGroupCreateAndRetentionChange"
        Effect   = "Deny"
        Action   = ["logs:CreateLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy"]
        Resource = "*"
      }]
    })
  }
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
