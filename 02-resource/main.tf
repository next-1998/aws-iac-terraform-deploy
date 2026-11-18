############################################################
# 02-resource
#   01-network가 Parameter Store에 남긴 값을 읽어 리소스를 만듭니다.
#   - shared-common : 사이트 인증서, 알림 토픽
#   - ec2-common    : EC2 서브넷, 라우트, 공통 SG
#   - ec2-was, ec2-webide : 서버, 개별 SG, IAM, ALB
#   rds-common 등 다른 유형은 필요할 때 같은 방식으로 추가합니다.
#   결과는 /iac/<site>/02-resource/* 에 남깁니다 (03-eks가 읽음).
############################################################

locals {
  network_bundles = ["base", "subnets", "routing", "endpoints", "dns"]
}

# 민감 정보가 아닌 String 파라미터라 insecure_value로 읽습니다.
# (value는 항상 sensitive로 표시되어 for_each 등에 쓸 수 없음)
data "aws_ssm_parameter" "network" {
  for_each = toset(local.network_bundles)
  name     = "/iac/${var.site}/01-network/${each.key}"
}

# String 파라미터라 insecure_value로 읽습니다 (value는 항상 sensitive)
data "aws_ssm_parameter" "bootstrap_logs" {
  count = var.enable_alb_access_logs && var.central_log_bucket_arn == null ? 1 : 0
  name  = "/iac/_account/00-bootstrap/logs"
}

locals {
  network = { for k, p in data.aws_ssm_parameter.network : k => jsondecode(p.insecure_value) }

  # ALB 접근 로그 버킷 이름
  access_log_bucket = !var.enable_alb_access_logs ? null : (
    var.central_log_bucket_arn != null ? element(split(":::", var.central_log_bucket_arn), 1) :
    jsondecode(data.aws_ssm_parameter.bootstrap_logs[0].insecure_value).bucket
  )
}

############################################################
# 공용
############################################################
module "shared_common" {
  source = "../deployment/shared-common"

  network            = local.network
  enable_alarm_topic = length(var.alarm_emails) > 0
  alarm_emails       = var.alarm_emails
  common_tags        = var.common_tags
}

############################################################
# EC2
############################################################
module "ec2_common" {
  source = "../deployment/ec2-common"

  network           = local.network
  common_sg_ingress = var.ec2_common_sg_ingress

  enable_weekend_stop = var.ec2_weekend_stop.enabled
  weekend_stop = {
    schedule_enabled = var.ec2_weekend_stop.schedule_enabled
    stop_schedule    = var.ec2_weekend_stop.stop_schedule
    start_schedule   = var.ec2_weekend_stop.start_schedule
    timezone         = var.ec2_weekend_stop.timezone
    dry_run          = var.ec2_weekend_stop.dry_run
  }
  common_tags = var.common_tags
}

module "ec2_was" {
  source = "../deployment/ec2-was"
  count  = var.was.enabled ? 1 : 0

  common              = module.ec2_common.contract
  ami                 = var.was.ami
  instance_type       = var.was.instance_type
  root_volume_size    = var.was.root_volume_size
  ebs_volumes         = var.was.ebs_volumes
  weekend_stop_enable = var.was.weekend_stop_enable
  ingress_rules       = var.was.ingress_rules

  enable_alb          = var.was.enable_alb
  alb_internal        = var.was.alb_internal
  alb_certificate_arn = module.shared_common.certificate_arn
  alb_record_name     = var.was.alb_record_name
  access_log_bucket   = local.access_log_bucket
  app_port            = var.was.app_port
  health_check_path   = var.was.health_check_path

  common_tags = var.common_tags
}

module "ec2_webide" {
  source = "../deployment/ec2-webide"
  count  = var.webide.enabled ? 1 : 0

  common              = module.ec2_common.contract
  ami                 = var.webide.ami
  instance_type       = var.webide.instance_type
  root_volume_size    = var.webide.root_volume_size
  ebs_volumes         = var.webide.ebs_volumes
  weekend_stop_enable = var.webide.weekend_stop_enable
  ingress_rules       = var.webide.ingress_rules

  enable_alb          = var.webide.enable_alb
  alb_internal        = var.webide.alb_internal
  alb_certificate_arn = module.shared_common.certificate_arn
  alb_record_name     = var.webide.alb_record_name
  access_log_bucket   = local.access_log_bucket
  app_port            = var.webide.app_port
  health_check_path   = var.webide.health_check_path

  common_tags = var.common_tags
}

############################################################
# 다음 단계(03-eks)로 넘길 값
#   EKS API는 이 단계의 EC2에서만 접근을 허용하므로 EC2 SG 목록을 남깁니다.
############################################################
resource "aws_ssm_parameter" "contract" {
  for_each = {
    ec2 = {
      common_sg_id = module.ec2_common.common_sg_id
      app_sg_ids = merge(
        var.was.enabled ? { ec2_was = module.ec2_was[0].sg_id } : {},
        var.webide.enabled ? { ec2_webide = module.ec2_webide[0].sg_id } : {},
      )
    }
    shared = {
      certificate_arn = module.shared_common.certificate_arn
      alarm_topic_arn = module.shared_common.alarm_topic_arn
    }
  }

  name        = "/iac/${var.site}/02-resource/${each.key}"
  description = "02-resource ${each.key} (03-eks가 읽음)"
  type        = "String"
  tier        = "Intelligent-Tiering"
  value       = jsonencode(each.value)
}
