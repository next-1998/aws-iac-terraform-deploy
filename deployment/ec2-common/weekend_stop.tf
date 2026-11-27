############################################################
# EC2 주말 중지 (선택, 기본값 끔) — 협의 후 적용
#   - 대상: EC2 태그 WEEKEND_STOP_ENABLE = "true" (인스턴스마다 자기 태그로 판단)
#   - EC2 서브넷(VPC 안)에서 실행. AWS API는 01-network의 ec2 endpoint로 호출
#   - 스케줄: EventBridge Scheduler. 협의 전에는 schedule_enabled = false (만들어지지만 실행 안 됨)
#   - 권한: 태그가 true인 인스턴스만 중지·시작 (IAM 조건)
#   코드: ./src/weekend_stop.py
#
#   조합: log group → role(+정책) → SG → Lambda → scheduler role(+정책) → 스케줄
############################################################

data "aws_partition" "current" {}

data "archive_file" "weekend_stop" {
  count       = var.enable_weekend_stop ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/src/weekend_stop.py"
  output_path = "${path.module}/.build/weekend_stop.zip"
}

locals {
  ws_name = "${local.np}-lbd-wkstop-01"
  ws_key  = "${local.key}_weekend_stop"
  ws_tag  = "WEEKEND_STOP_ENABLE"
  ws      = var.enable_weekend_stop ? { this = true } : {}

  ws_tags = {
    common_tags   = var.common_tags
    resource_tags = local.resource_tags
    site          = local.site
    stack         = var.name
  }
}

module "ws_log" {
  source   = "../../../aws-iac-terraform-module/module/monitor_log/aws-cloudwatch-workload/loggroup"
  for_each = local.ws

  # 로그 경로 규칙: /<VPC 이름>/lambda/<함수 이름>/function (Lambda logging_config로 이 로그 그룹을 씀)
  name              = "/${local.base.vpc_name}/lambda/${local.ws_name}/function"
  retention_in_days = var.weekend_stop.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  common_tags   = local.ws_tags.common_tags
  resource_tags = local.ws_tags.resource_tags
  site          = local.ws_tags.site
  stack         = local.ws_tags.stack
  key_target    = local.ws_key
}

# Lambda 실행 role
module "ws_role" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role"
  for_each = local.ws

  name               = "${local.np}-role-wkstop-01"
  description        = "weekend stop lambda"
  assume_role_policy = templatefile("${path.module}/policies/weekend-stop-lambda-trust.json.tftpl", {})

  common_tags   = local.ws_tags.common_tags
  resource_tags = local.ws_tags.resource_tags
  site          = local.ws_tags.site
  stack         = local.ws_tags.stack
  key_target    = local.ws_key
}

module "ws_role_vpc" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy-attachment"
  for_each = local.ws

  role_name   = module.ws_role[each.key].name
  policy_arns = { vpc = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole" }
}

module "ws_role_target" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy"
  for_each = local.ws

  role_name = module.ws_role[each.key].name
  policies = {
    "${local.ws_name}-target" = templatefile("${path.module}/policies/weekend-stop-target.json.tftpl", { tag_key = local.ws_tag })
  }
}

# 아웃바운드는 VPC endpoint(443)로만
module "ws_sg" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/security-group"
  for_each = local.ws

  name        = "${local.np}-sg-wkstop-01"
  description = "weekend stop lambda (egress to VPC endpoints only)"
  vpc_id      = local.base.vpc_id

  common_tags   = local.ws_tags.common_tags
  resource_tags = local.ws_tags.resource_tags
  site          = local.ws_tags.site
  stack         = local.ws_tags.stack
  key_target    = local.ws_key
}

# 아웃바운드는 VPC endpoint(443)로만
module "ws_sg_egress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/egress-rule"
  rules = {
    for pair in setproduct(keys(local.ws), local.base.vpc_cidrs) : "${pair[0]}|vpce|${pair[1]}" => {
      security_group_id = module.ws_sg[pair[0]].securitygroup_id
      ip_protocol       = "tcp"
      from_port         = 443
      to_port           = 443
      cidr_ipv4         = pair[1]
      description       = "to VPC endpoints"
    }
  }
}

module "ws_lambda" {
  source   = "../../../aws-iac-terraform-module/module/devtools/aws-lambda-workload"
  for_each = local.ws

  function_name    = local.ws_name
  description      = "EC2 weekend stop/start by tag ${local.ws_tag}"
  role_arn         = module.ws_role[each.key].arn
  handler          = "weekend_stop.lambda_handler"
  filename         = data.archive_file.weekend_stop[0].output_path
  source_code_hash = data.archive_file.weekend_stop[0].output_base64sha256
  timeout          = 300

  environment_variables = {
    TARGET  = "ec2"
    TAG_KEY = local.ws_tag
    DRY_RUN = tostring(var.weekend_stop.dry_run)
  }

  subnet_ids         = [for az, s in local.standard_subnets : module.subnet[az].vpc_subnet[0].id]
  security_group_ids = [module.ws_sg[each.key].securitygroup_id]
  log_group_name     = module.ws_log[each.key].name

  common_tags   = local.ws_tags.common_tags
  resource_tags = local.ws_tags.resource_tags
  site          = local.ws_tags.site
  stack         = local.ws_tags.stack
  key_target    = local.ws_key

  # VPC 권한이 붙은 뒤에 만들어야 ENI 생성이 실패하지 않음
  depends_on = [module.ws_role_vpc]
}

# 스케줄러가 Lambda를 호출할 role
module "ws_scheduler_role" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role"
  for_each = local.ws

  name               = "${local.np}-role-wkstopsch-01"
  description        = "weekend stop scheduler"
  assume_role_policy = templatefile("${path.module}/policies/weekend-stop-scheduler-trust.json.tftpl", {})

  common_tags   = local.ws_tags.common_tags
  resource_tags = local.ws_tags.resource_tags
  site          = local.ws_tags.site
  stack         = local.ws_tags.stack
  key_target    = "${local.ws_key}_scheduler"
}

module "ws_scheduler_invoke" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy"
  for_each = local.ws

  role_name = module.ws_scheduler_role[each.key].name
  policies = {
    "${local.ws_name}-invoke" = templatefile("${path.module}/policies/weekend-stop-invoke.json.tftpl", { lambda_arn = module.ws_lambda[each.key].arn })
  }
}

module "ws_schedule" {
  source   = "../../../aws-iac-terraform-module/module/devtools/aws-scheduler-workload"
  for_each = local.ws

  schedules = {
    for action, expr in { stop = var.weekend_stop.stop_schedule, start = var.weekend_stop.start_schedule } : action => {
      name                     = "${local.np}-sch-wkstop${action}-01"
      expression               = expr
      timezone                 = var.weekend_stop.timezone
      enabled                  = var.weekend_stop.schedule_enabled
      target_arn               = module.ws_lambda[each.key].arn
      role_arn                 = module.ws_scheduler_role[each.key].arn
      input                    = jsonencode({ action = action })
    }
  }
}
