############################################################
# EBS 자동 증설 (사이트에 하나, ec2-<용도>의 auto_grow 볼륨이 있을 때)
#   - ec2-<용도>가 볼륨마다 디스크 사용률 알람을 만들고, 알람이 이 Lambda를 호출
#   - Lambda: 볼륨 크기 늘림 → SSM으로 파일시스템 확장 → 알람 OK로 되돌림 → SNS 알림
#   - 6시간 제한(AWS) 등으로 못 늘린 알람은 스케줄(retry_schedule)로 다시 확인
#   - 권한: 태그 EBS_AUTO_GROW = "true"인 볼륨·서버만 변경 (IAM 조건)
#   코드: ./src/ebs_grow.py
#
#   조합: log group → role(+정책) → SG → Lambda → 알람 호출 권한 → scheduler role(+정책) → 스케줄
############################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "archive_file" "ebs_grow" {
  count       = var.enable_ebs_auto_grow ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/src/ebs_grow.py"
  output_path = "${path.module}/.build/ebs_grow.zip"
}

locals {
  eg_name = "${local.prefix}-ebs-grow"
  eg_key  = "${local.key}_ebs_grow"
  eg      = var.enable_ebs_auto_grow ? { this = true } : {}

  # ec2-<용도>가 쓰는 이름 규칙 (알람: <site>-<용도>-ebs-grow-<볼륨>)
  eg_tag        = "EBS_AUTO_GROW"
  eg_alarm_mark = "-ebs-grow-"
  eg_alarm_arn  = "arn:${data.aws_partition.current.partition}:cloudwatch:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:alarm:${local.site}-*${local.eg_alarm_mark}*"

  # AWS API는 VPC endpoint로만 (public을 켜도 워크로드는 private 기본, public subnet은 제한적 용도)
  eg_endpoints         = concat(["ec2", "ssm", "monitoring"], var.ebs_auto_grow.alarm_topic_arn == null ? [] : ["sns"])
  eg_missing_endpoints = setsubtract(local.eg_endpoints, var.network.endpoints.interface)
  eg_egress_cidrs      = local.base.vpc_cidrs
}

module "eg_log" {
  source   = "../../../aws-iac-terraform-module/module/monitor_log/aws-cloudwatch-workload/loggroup"
  for_each = local.eg

  name              = "/${local.base.vpc_name}/lambda/${local.eg_name}/function"
  retention_in_days = var.ebs_auto_grow.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.eg_key
}

module "eg_role" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role"
  for_each = local.eg

  name               = "${local.eg_name}-role"
  description        = "EBS auto grow lambda"
  assume_role_policy = templatefile("${path.module}/policies/weekend-stop-lambda-trust.json.tftpl", {})

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.eg_key
}

module "eg_role_vpc" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy-attachment"
  for_each = local.eg

  role_name   = module.eg_role[each.key].name
  policy_arns = { vpc = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole" }
}

module "eg_role_target" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy"
  for_each = local.eg

  role_name = module.eg_role[each.key].name
  policies = {
    "${local.eg_name}-target" = templatefile("${path.module}/policies/ebs-grow-target.json.tftpl", {
      partition     = data.aws_partition.current.partition
      region        = data.aws_region.current.region
      account_id    = data.aws_caller_identity.current.account_id
      tag_key       = local.eg_tag
      alarm_pattern = "${local.site}-*${local.eg_alarm_mark}*"
      topic_arn     = var.ebs_auto_grow.alarm_topic_arn == null ? "" : var.ebs_auto_grow.alarm_topic_arn
    })
  }
}

module "eg_sg" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/security-group"
  for_each = local.eg

  name        = "${local.eg_name}-sg"
  description = "EBS auto grow lambda (egress 443 to VPC endpoints only)"
  vpc_id      = local.base.vpc_id

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.eg_key
}

module "eg_sg_egress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/egress-rule"
  rules = {
    for pair in setproduct(keys(local.eg), local.eg_egress_cidrs) : "${pair[0]}|aws|${pair[1]}" => {
      security_group_id = module.eg_sg[pair[0]].securitygroup_id
      ip_protocol       = "tcp"
      from_port         = 443
      to_port           = 443
      cidr_ipv4         = pair[1]
      description       = "to VPC endpoints"
    }
  }
}

module "eg_lambda" {
  source   = "../../../aws-iac-terraform-module/module/devtools/aws-lambda-workload"
  for_each = local.eg

  function_name    = local.eg_name
  description      = "EBS auto grow by disk usage alarm (tag ${local.eg_tag})"
  role_arn         = module.eg_role[each.key].arn
  filename         = data.archive_file.ebs_grow[0].output_path
  source_code_hash = data.archive_file.ebs_grow[0].output_base64sha256
  timeout          = 600 # 볼륨 변경 대기(최대 5분) + 파일시스템 확장(최대 3분)

  environment_variables = {
    TAG_KEY           = local.eg_tag
    ALARM_NAME_PREFIX = "${local.site}-"
    ALARM_NAME_MARK   = local.eg_alarm_mark
    SNS_TOPIC_ARN     = var.ebs_auto_grow.alarm_topic_arn == null ? "" : var.ebs_auto_grow.alarm_topic_arn
    DRY_RUN           = "false"
  }

  subnet_ids         = [for az in local.azs : module.subnet[az].vpc_subnet[0].id]
  security_group_ids = [module.eg_sg[each.key].securitygroup_id]
  log_group_name     = module.eg_log[each.key].name

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.eg_key

  # VPC 권한이 붙은 뒤에 만들어야 ENI 생성이 실패하지 않음 (주말 중지와 같은 예외)
  depends_on = [module.eg_role_vpc]
}

# CloudWatch 알람이 이 Lambda를 호출 (이 계정, 이 사이트의 증설 알람만)
module "eg_alarm_invoke" {
  source   = "../../../aws-iac-terraform-module/module/devtools/aws-lambda-workload/permission"
  for_each = local.eg

  function_name = module.eg_lambda[each.key].function_name
  permissions = {
    AllowEbsGrowAlarms = {
      principal      = "lambda.alarms.cloudwatch.amazonaws.com"
      source_arn     = local.eg_alarm_arn
      source_account = data.aws_caller_identity.current.account_id
    }
  }
}

module "eg_scheduler_role" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role"
  for_each = local.eg

  name               = "${local.eg_name}-scheduler-role"
  description        = "EBS auto grow retry scheduler"
  assume_role_policy = templatefile("${path.module}/policies/weekend-stop-scheduler-trust.json.tftpl", {})

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.eg_key}_scheduler"
}

module "eg_scheduler_invoke" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy"
  for_each = local.eg

  role_name = module.eg_scheduler_role[each.key].name
  policies = {
    "${local.eg_name}-invoke" = templatefile("${path.module}/policies/weekend-stop-invoke.json.tftpl", { lambda_arn = module.eg_lambda[each.key].arn })
  }
}

module "eg_schedule" {
  source   = "../../../aws-iac-terraform-module/module/devtools/aws-scheduler-workload"
  for_each = local.eg

  schedules = {
    retry = {
      name       = "${local.eg_name}-retry"
      expression = var.ebs_auto_grow.retry_schedule
      timezone   = "Asia/Seoul"
      enabled    = true
      target_arn = module.eg_lambda[each.key].arn
      role_arn   = module.eg_scheduler_role[each.key].arn
      input      = jsonencode({ action = "retry" })
    }
  }
}
