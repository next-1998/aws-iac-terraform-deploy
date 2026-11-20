############################################################
# CloudWatch Agent 로그 그룹 (껍데기를 미리 만듦)
#   보관 14일, logs CMK(02-shared)로 암호화. Agent 설정에서 아래 이름(output agent_log_groups)으로 보냅니다.
#   Agent가 직접 로그 그룹을 만들게 두지 않습니다 (만들면 보관 기간이 무기한이 됨).
#   장기 보관은 00-bootstrap이 S3로 내보냄 (기본 365일).
#   이름: /<site>/<stack>/<로그 이름>   예) /simple/ec2-was/system
############################################################
module "agent_log" {
  source   = "../../../aws-iac-terraform-module/module/monitor_log/aws-cloudwatch-workload/loggroup"
  for_each = var.agent_log_groups

  name              = "/${local.site}/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = try(var.common.logs_kms_key_arn, null)

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_${replace(each.key, "-", "_")}"
}
