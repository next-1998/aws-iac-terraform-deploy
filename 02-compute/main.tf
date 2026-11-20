############################################################
# 02-compute
#   EC2 유형 전체를 만듭니다 (state 하나).
#   - ec2-common : EC2 서브넷, 라우트, 공통 SG, 주말 중지 (1차 조합)
#   - ec2-was, ec2-webide : 서버, 개별 SG, IAM, ALB (2차 조합, 용도별)
#   읽는 값: /iac/<site>/01-network/*, /iac/<site>/02-shared/shared (인증서)
#   결과는 /iac/<site>/02-compute/ec2 에 남깁니다 (03-eks가 읽음).
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

# 02-shared 값 (사이트 인증서, 알림 토픽)
data "aws_ssm_parameter" "shared" {
  name = "/iac/${var.site}/02-shared/shared"
}

# String 파라미터라 insecure_value로 읽습니다 (value는 항상 sensitive)
data "aws_ssm_parameter" "bootstrap_logs" {
  count = var.enable_alb_access_logs && var.central_log_bucket_arn == null ? 1 : 0
  name  = "/iac/_account/00-bootstrap/logs"
}

locals {
  network = { for k, p in data.aws_ssm_parameter.network : k => jsondecode(p.insecure_value) }
  shared  = jsondecode(data.aws_ssm_parameter.shared.insecure_value)

  # ALB 접근 로그 버킷 이름
  access_log_bucket = !var.enable_alb_access_logs ? null : (
    var.central_log_bucket_arn != null ? element(split(":::", var.central_log_bucket_arn), 1) :
    jsondecode(data.aws_ssm_parameter.bootstrap_logs[0].insecure_value).bucket
  )
}

############################################################
# EC2
############################################################
module "ec2_common" {
  source = "../deployment/ec2-common"

  network = local.network

  # 암호화: 로그 그룹은 02-shared의 logs 키. EC2 볼륨은 계정 EBS 기본 키(00-bootstrap ebs)
  logs_kms_key_arn = try(local.shared.logs_kms_key_arn, null)

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

  enable_alb          = var.was.enable_alb
  alb_internal        = var.was.alb_internal
  alb_certificate_arn = local.shared.certificate_arn
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

  enable_alb          = var.webide.enable_alb
  alb_internal        = var.webide.alb_internal
  alb_certificate_arn = local.shared.certificate_arn
  alb_record_name     = var.webide.alb_record_name
  access_log_bucket   = local.access_log_bucket
  app_port            = var.webide.app_port
  health_check_path   = var.webide.health_check_path

  common_tags = var.common_tags
}

############################################################
# 다음 단계(03-eks)로 넘길 값 (/iac/<site>/02-compute/ec2)
#   EKS API는 EC2에서만 접근을 허용하므로 EC2 SG 목록을 남깁니다.
############################################################
module "contract" {
  source = "../../aws-iac-terraform-module/module/management/aws-ssm-parameter-workload"

  path_prefix = "/iac/${var.site}/02-compute"
  description = "02-compute 묶음 (03-eks가 읽음)"
  parameters = {
    ec2 = {
      common_sg_id = module.ec2_common.common_sg_id
      app_sg_ids = merge(
        var.was.enabled ? { ec2_was = module.ec2_was[0].sg_id } : {},
        var.webide.enabled ? { ec2_webide = module.ec2_webide[0].sg_id } : {},
      )
    }
  }

  common_tags = var.common_tags
  site        = var.site
  stack       = "02-compute"
  key_target  = "contract"
}
