############################################################
# 자동 확장 (선택, 기본 꺼짐: autoscale.enabled)
#   고정 서버(ec2.tf) 1대는 그대로 두고, 2번째 서버부터 ASG로 늘리고 줄입니다 (0 ~ max_extra).
#   고정 서버와 확장 서버는 같은 SG·IAM 역할·ALB 대상 그룹을 씁니다.
#
#   이미지: autoscale.ami(고정 ID)가 있으면 그것, 없으면 고정 서버로 최초 이미지를 한 번만 만듦
#           (데이터 볼륨 포함, 마운트·Agent 설치가 성공한 뒤. 이후 이미지는 Terraform 밖에서 만들어 autoscale.ami로)
#   확장 기준: CPU·메모리 그룹 평균 (고정 + 확장 서버, Agent가 ServiceGroup 차원으로 보냄)
#              둘 중 하나라도 scale_out(%) 초과 5분 → +1 / 둘 다 scale_in(%) 미만 15분 → -1
#   줄일 때: 가장 최근에 뜬 서버부터 / 이미지가 바뀌면: 확장 서버만 순차 교체 (고정 서버는 그대로)
############################################################
locals {
  autoscale     = var.autoscale.enabled
  make_image    = local.autoscale && var.autoscale.ami == null
  service_group = local.prefix
}

# ── 최초 이미지 (고정 서버로 한 번만) ──────────────────────────
module "initial_image" {
  source = "../../../aws-iac-terraform-module/module/computing/aws-ami-workload/from-instance"
  count  = local.make_image ? 1 : 0

  name        = "${local.prefix}-initial"
  description = "initial image of ${local.prefix} for autoscaling (created once by Terraform)"
  # 마운트·Agent 설치 SSM 연결이 성공한 뒤에 찍히도록 그 결과를 참조 (값은 서버 ID)
  source_instance_id = length(merge(module.volume_mount.association_ids, module.cwagent.association_ids)) >= 0 ? module.ec2.ec2_instance.id : null
  reboot             = var.autoscale.image_reboot
  prevent_destroy    = var.protect_volumes

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_initial"
}

locals {
  asg_ami = local.autoscale ? coalesce(var.autoscale.ami, one(module.initial_image[*].id)) : null
}

# 이미지의 디스크 구성 (루트 + 포함된 데이터 볼륨). Launch Template에서 "종료 시 삭제"로 덮어쓰기 위해 읽음
data "aws_ami" "asg" {
  count = local.autoscale ? 1 : 0

  filter {
    name   = "image-id"
    values = [local.asg_ami]
  }
}

# ── Launch Template ────────────────────────────────────────
module "asg_lt" {
  source = "../../../aws-iac-terraform-module/module/computing/aws-lt-workload/launch-template"
  count  = local.autoscale ? 1 : 0

  name                      = "${local.prefix}-lt"
  description               = "${local.prefix} autoscale servers"
  image_id                  = local.asg_ami
  instance_type             = coalesce(var.autoscale.instance_type, var.instance_type)
  iam_instance_profile_name = module.instance_profile.name
  vpc_security_group_ids    = [var.common.common_sg_id, module.sg.securitygroup_id]
  user_data                 = var.user_data == null ? null : base64encode(var.user_data)
  instance_name             = "${local.prefix}-asg"

  # 이미지에 들어 있는 EBS 볼륨(루트, 데이터)을 모두 "종료 시 삭제" + 암호화로 덮어씀 (줄일 때 볼륨이 남지 않게)
  block_device_mappings = [
    for b in data.aws_ami.asg[0].block_device_mappings : {
      device_name           = b.device_name
      encrypted             = true
      kms_key_id            = var.kms_key_id
      delete_on_termination = true
    } if length(b.ebs) > 0
  ]

  common_tags = var.common_tags
  # 확장 서버: Agent 설치 대상(ServiceGroup), Lambda 주말 중지 대상 아님 (ASG가 교체해 버리므로)
  resource_tags = merge(local.resource_tags, {
    ServiceGroup        = local.service_group
    WEEKEND_STOP_ENABLE = "false"
  })
  site       = local.site
  stack      = var.name
  key_target = "${local.key}_asg"
}

# ── Auto Scaling Group (0 ~ max_extra) ─────────────────────
module "asg" {
  source = "../../../aws-iac-terraform-module/module/computing/aws-asg-workload/asg"
  count  = local.autoscale ? 1 : 0

  name                = "${local.prefix}-asg"
  min_size            = 0
  max_size            = var.autoscale.max_extra
  desired_capacity    = 0
  vpc_zone_identifier = values(var.common.subnet_ids) # 모든 AZ
  health_check_type   = var.enable_alb ? "ELB" : "EC2"

  launch_template_id      = module.asg_lt[0].id
  launch_template_version = module.asg_lt[0].latest_version # 버전이 바뀌면 순차 교체

  # 줄일 때 최근에 뜬 서버부터, AZ 균형을 맞추려고 임의로 종료하지 않음
  termination_policies = ["NewestInstance"]
  suspended_processes  = ["AZRebalance"]

  instance_refresh_min_healthy_percentage = var.autoscale.refresh_min_healthy_percentage
  instance_refresh_triggers               = []

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_asg"
}

# 고정 서버와 같은 ALB 대상 그룹에 연결 (확장 서버는 자동 등록·해제)
module "asg_tg" {
  source = "../../../aws-iac-terraform-module/module/computing/aws-asg-workload/attachment"
  count  = local.autoscale && var.enable_alb ? 1 : 0

  autoscaling_group_name = module.asg[0].name
  lb_target_group_arn    = local.tg_arn
}

# ── 스케일링: CPU·메모리 알람 → 1대씩 ─────────────────────
module "asg_policy" {
  source = "../../../aws-iac-terraform-module/module/computing/aws-asg-workload/policy"
  count  = local.autoscale ? 1 : 0

  autoscaling_group_name = module.asg[0].name
  policies = {
    "${local.prefix}-scale-out" = { adjustment = 1 }
    "${local.prefix}-scale-in"  = { adjustment = -1 }
  }
}

locals {
  # 고정 + 확장 서버의 그룹 평균 (Agent가 ServiceGroup 차원 하나로 보냄)
  scale_metrics = {
    cpu = { namespace = "CWAgent", metric_name = "cpu_usage_active", dimensions = { ServiceGroup = local.service_group, cpu = "cpu-total" } }
    mem = { namespace = "CWAgent", metric_name = "mem_used_percent", dimensions = { ServiceGroup = local.service_group } }
  }
}

module "asg_alarm" {
  source = "../../../aws-iac-terraform-module/module/monitor_log/aws-cloudwatch-workload/metric-alarm"
  count  = local.autoscale ? 1 : 0

  name = "${local.prefix}-scaling"
  alarms = {
    "${local.prefix}-high" = {
      description         = "CPU or memory above ${var.autoscale.scale_out}% for 5 minutes -> add 1 server"
      metrics             = local.scale_metrics
      expression          = "MAX([cpu, mem])"
      label               = "max(cpu, mem) %"
      comparison_operator = "GreaterThanThreshold"
      threshold           = var.autoscale.scale_out
      evaluation_periods  = 5
      treat_missing_data  = "notBreaching"
      alarm_actions       = [module.asg_policy[0].arns["${local.prefix}-scale-out"]]
    }
    "${local.prefix}-low" = {
      description         = "CPU and memory below ${var.autoscale.scale_in}% for 15 minutes -> remove 1 server"
      metrics             = local.scale_metrics
      expression          = "MAX([cpu, mem])"
      label               = "max(cpu, mem) %"
      comparison_operator = "LessThanThreshold"
      threshold           = var.autoscale.scale_in
      evaluation_periods  = 15
      treat_missing_data  = "notBreaching"
      alarm_actions       = [module.asg_policy[0].arns["${local.prefix}-scale-in"]]
    }
  }

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_scaling"
}

# ── 주말 중지 (선택, 기본 꺼짐): 확장 서버만 0대 ↔ 원복 ────────
module "asg_schedule" {
  source = "../../../aws-iac-terraform-module/module/computing/aws-asg-workload/schedule"
  count  = local.autoscale && var.autoscale.weekend_stop.enabled ? 1 : 0

  autoscaling_group_name = module.asg[0].name
  schedules = {
    "${local.prefix}-weekend-stop" = {
      recurrence = var.autoscale.weekend_stop.stop_schedule
      time_zone  = var.autoscale.weekend_stop.time_zone
      min_size   = 0, max_size = 0, desired_capacity = 0
    }
    "${local.prefix}-weekend-start" = {
      recurrence = var.autoscale.weekend_stop.start_schedule
      time_zone  = var.autoscale.weekend_stop.time_zone
      min_size   = 0, max_size = var.autoscale.max_extra, desired_capacity = 0
    }
  }
}
