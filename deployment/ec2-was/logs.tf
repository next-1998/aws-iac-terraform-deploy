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
#   로그 그룹 이름을 로그 그룹 모듈 출력에서 받으므로 로그 그룹이 생긴 뒤에 실행됨 (depends_on 없이 값 참조로 순서 결정)
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
      # 자동 확장을 켜면 태그(ServiceGroup)로 지정 → 고정 서버와 나중에 뜨는 확장 서버 모두 자동 적용
      instance_ids = local.autoscale ? [] : [module.ec2.ec2_instance.id]
      target_tag   = local.autoscale ? { key = "ServiceGroup", values = [local.service_group] } : null
      parameters = {
        commands = join("\n", [
          "MSG_GROUP='${module.agent_log["messages"].name}'",
          "SEC_GROUP='${module.agent_log["secure"].name}'",
          # 자동 확장 기준 지표 (CPU·메모리). 켜지 않으면 비움 = 지표를 보내지 않음
          "METRIC_GROUP='${local.autoscale ? local.service_group : ""}'",
          # EBS 자동 증설 기준 지표 (고정 서버의 대상 마운트 경로만). 켜지 않으면 비움
          "DISK_INSTANCE='${module.ec2.ec2_instance.id}'",
          "DISK_PATHS='${join(" ", sort(distinct([for t in values(local.grow_targets) : t.path])))}'",
          file("${path.module}/src/cwagent_setup.sh"),
        ])
      }
      schedule_expression = var.cloudwatch_agent_schedule
      # 최초 이미지를 만들 때는 Agent 설치가 끝난 뒤 찍히도록 성공까지 대기
      wait_for_success_seconds = local.make_image ? 1800 : null
    }
  } : {}
}
