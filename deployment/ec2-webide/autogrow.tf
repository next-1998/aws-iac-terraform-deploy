############################################################
# EBS 자동 증설 (고정 서버의 root_auto_grow, ebs_volumes[].auto_grow)
#   CloudWatch Agent: 대상 마운트 경로의 디스크 사용률 (disk_used_percent, 차원 InstanceId·path)
#   알람(사용률 > threshold) → ec2-common 증설 Lambda: 볼륨 크기 늘림 → 파일시스템 확장 → SNS 알림
#   켠 볼륨은 태그 EBS_AUTO_GROW = "true" (Lambda IAM 조건). 서버에도 붙임 (SSM 명령 허용 조건)
#
#   Terraform과 크기 맞추기: 자동으로 늘어난 볼륨은 tfvars보다 큼 → 실제 크기를 읽어 큰 값을 씀
#   (그대로 두면 다음 apply가 tfvars 크기로 줄이려다 실패). tfvars를 실제보다 크게 하면 그 값으로 늘어남
############################################################
locals {
  grow_root = var.root_auto_grow != null
  grow_data = { for k, v in local.data_volumes : k => v if v.auto_grow != null }
  grow_any  = local.grow_root || length(local.grow_data) > 0

  # 볼륨 ResourceKey (인스턴스 모듈 루트 = <key>_vol, 데이터 볼륨 = <key>_data_<장치>_vol)
  data_volume_keys = { for k, v in local.data_volumes : k => "${local.key}_data_${lower(replace(basename(k), "/[^a-zA-Z0-9]/", "_"))}" }
  grow_lookup_keys = concat(
    local.grow_root ? ["${local.key}_vol"] : [],
    [for k, v in local.grow_data : "${local.data_volume_keys[k]}_vol"],
  )
}

# 실제 크기 (자동 증설로 늘어났을 수 있음). 처음 배포 때는 볼륨이 없어 빈 결과
data "aws_ebs_volumes" "grow" {
  count = local.grow_any ? 1 : 0

  filter {
    name   = "tag:Stack"
    values = ["${local.site}/${var.name}"]
  }
  filter {
    name   = "tag:ResourceKey"
    values = local.grow_lookup_keys
  }
  filter {
    # 서버를 다시 만들 때 남은 이전 루트 볼륨(available)은 제외
    name   = "status"
    values = ["in-use"]
  }
}

data "aws_ebs_volume" "grow" {
  for_each = toset(try(data.aws_ebs_volumes.grow[0].ids, []))

  filter {
    name   = "volume-id"
    values = [each.key]
  }
}

locals {
  # ResourceKey → 실제 크기 (같은 키가 여럿이면 가장 큰 값)
  grow_actual = { for k in distinct([for v in data.aws_ebs_volume.grow : v.tags["ResourceKey"]]) : k => max([for v in data.aws_ebs_volume.grow : v.size if v.tags["ResourceKey"] == k]...) }

  root_volume_size = local.grow_root ? max(var.root_volume_size, lookup(local.grow_actual, "${local.key}_vol", 0)) : var.root_volume_size
  data_volume_size = {
    for k, v in local.data_volumes : k => v.auto_grow == null ? v.volume_size : max(v.volume_size, lookup(local.grow_actual, "${local.data_volume_keys[k]}_vol", 0))
  }

  # 증설 대상 (알람 키 → 볼륨, 경로, 설정)
  grow_targets = merge(
    local.grow_root ? {
      root = { volume_id = module.ec2.root_volume_id, path = "/", conf = var.root_auto_grow }
    } : {},
    { for k, v in local.grow_data : basename(k) => { volume_id = module.data_volume[k].id, path = trimsuffix(v.mount_point, "/"), conf = v.auto_grow } },
  )

  grow_tag = var.common.ebs_grow.tag_key
}

module "grow_alarm" {
  source = "../../../aws-iac-terraform-module/module/monitor_log/aws-cloudwatch-workload/metric-alarm"

  name = "${local.prefix}-ebs-grow"
  alarms = {
    for k, t in local.grow_targets : "${local.prefix}${var.common.ebs_grow.alarm_mark}${k}" => {
      # Lambda가 읽는 대상 정보 (key=value). 사람이 봐도 알 수 있게 그대로 둠
      description = "EBS auto grow volume=${t.volume_id} instance=${module.ec2.ec2_instance.id} path=${t.path} max=${t.conf.max_size} percent=${t.conf.increase_percent} min=${t.conf.min_increase}"
      # Metrics Insights: Agent가 붙이는 fstype 등 다른 차원과 관계없이 InstanceId·path로 조회
      expression          = "SELECT MAX(disk_used_percent) FROM CWAgent WHERE InstanceId = '${module.ec2.ec2_instance.id}' AND path = '${t.path}'"
      label               = "disk_used_percent ${t.path}"
      comparison_operator = "GreaterThanThreshold"
      threshold           = t.conf.threshold
      period              = 300
      evaluation_periods  = 1
      treat_missing_data  = "notBreaching"
      alarm_actions       = compact([var.common.ebs_grow.lambda_arn])
    }
  }

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_ebs_grow"
}

# 확인: 증설 Lambda가 있어야 하고, Agent가 사용률을 보내야 함
check "auto_grow_requirements" {
  assert {
    condition     = !local.grow_any || (var.common.ebs_grow.enabled && local.cwagent_enabled)
    error_message = "EBS 자동 증설은 ec2-common 증설 Lambda(enable_ebs_auto_grow)와 CloudWatch Agent(enable_cloudwatch_agent, agent_log_groups의 messages·secure)가 필요합니다."
  }
}
