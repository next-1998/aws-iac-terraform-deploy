############################################################
# CloudWatch Agent 로그 그룹 (껍데기를 미리 만듦)
#   보관 14일, logs CMK(00-bootstrap 계정 키 또는 중앙 키)로 암호화.
#   Agent가 직접 로그 그룹을 만들게 두지 않습니다 (만들면 보관 기간이 무기한이 됨).
#   장기 보관은 00-bootstrap이 S3로 내보냄 (기본 365일).
#   이름: /<VPC 이름>/ec2/<서버 이름>/<로그 이름>   예) /simple-vpc/ec2/simple-ec2-was/messages
#         (로그 경로 규칙. S3에도 같은 경로로 쌓임: <VPC 이름>/ec2/<서버 이름>/<로그 이름>/YYYY/MM/DD/)
#   기본: messages(OS 로그), secure(인증 로그). 그 밖의 로그 그룹은 agent_log_groups에 추가 (Agent 설정은 별도)
############################################################
module "agent_log" {
  source   = "../../../aws-iac-terraform-module/module/monitor_log/aws-cloudwatch-workload/loggroup"
  for_each = var.agent_log_groups

  name              = "${local.log_prefix}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = try(var.common.logs_kms_key_arn, null)

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_${replace(each.key, "-", "_")}"
}

############################################################
# CloudWatch Agent 설치·설정 (SSM 연결로 src/cwagent_setup.sh 실행)
#   스크립트가 OS 계열(RHEL / Debian)을 확인하고, rsyslog·Agent가 없으면 설치한 뒤
#   OS 로그 -> <prefix>/messages, 인증 로그 -> <prefix>/secure 로 보내도록 설정합니다.
#   서버가 교체되거나 스크립트가 바뀌면 다시 실행됩니다 (서버 재생성 불필요).
#   로그 그룹을 먼저 만든 뒤 실행 (Agent가 무기한 보관 로그 그룹을 만들지 않도록)
############################################################
locals {
  # 로그 그룹 이름 앞부분 (/<VPC 이름>/ec2/<서버 이름>)
  log_prefix = "/${local.base.vpc_name}/ec2/${local.prefix}"

  cwagent_enabled = var.enable_cloudwatch_agent && alltrue([for k in ["messages", "secure"] : contains(keys(var.agent_log_groups), k)])
}

module "cwagent" {
  source = "../../../aws-iac-terraform-module/module/management/aws-ssm-association-workload"

  associations = local.cwagent_enabled ? {
    "${local.prefix}-cwagent" = {
      instance_ids = [module.ec2.ec2_instance.id]
      parameters = {
        commands = join("\n", [
          "LOG_PREFIX='${local.log_prefix}'",
          file("${path.module}/src/cwagent_setup.sh"),
        ])
      }
      schedule_expression = var.cloudwatch_agent_schedule
    }
  } : {}

  depends_on = [module.agent_log]
}
