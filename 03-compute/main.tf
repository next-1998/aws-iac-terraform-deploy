############################################################
# 03-compute
#   EC2 유형 전체를 만듭니다 (state 하나).
#   - ec2-common : EC2 서브넷, 라우트, 공통 SG, 주말 중지 (1차 조합)
#   - ec2-was, ec2-webide : 서버, 개별 SG, IAM, ALB (2차 조합, 용도별)
#   읽는 값: /iac/<site>/01-network/*, /iac/<site>/02-shared/shared (인증서)
#   결과는 /iac/<site>/03-compute/ec2 에 남깁니다 (04-eks가 읽음).
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

# 00-bootstrap 계정 CMK (logs 키: 로그 그룹 암호화)
data "aws_ssm_parameter" "bootstrap_kms" {
  name = "/iac/_account/00-bootstrap/kms"
}

# String 파라미터라 insecure_value로 읽습니다 (value는 항상 sensitive)
data "aws_ssm_parameter" "bootstrap_logs" {
  count = var.enable_alb_access_logs && var.central_log_bucket_arn == null ? 1 : 0
  name  = "/iac/_account/00-bootstrap/logs"
}

locals {
  network = { for k, p in data.aws_ssm_parameter.network : k => jsondecode(p.insecure_value) }
  shared  = jsondecode(data.aws_ssm_parameter.shared.insecure_value)

  # EBS 자동 증설 대상이 하나라도 있는지 (켜진 용도만)
  ebs_auto_grow = anytrue([
    for p in [var.was, var.webide] : p.enabled && (p.root_auto_grow != null || anytrue([for v in p.ebs_volumes : v.auto_grow != null]))
  ])

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

  # 암호화: 로그 그룹은 00-bootstrap의 logs 키(또는 중앙 키). EC2 볼륨은 계정 EBS 기본 키(00-bootstrap ebs)
  logs_kms_key_arn = try(jsondecode(data.aws_ssm_parameter.bootstrap_kms.insecure_value).key_arns.logs, null)

  # EBS 자동 증설: 어느 서버든 auto_grow 볼륨이 있으면 Lambda 생성. 결과는 02-shared 알림 토픽으로
  enable_ebs_auto_grow = local.ebs_auto_grow
  ebs_auto_grow        = { alarm_topic_arn = local.shared.alarm_topic_arn }

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

############################################################
# 같은 단계 SG 이름표: <용도>.<sg> → ID (sg_rules.csv의 sg:<용도>.<sg>)
#   SG는 규칙과 따로 먼저 만들어지므로 용도끼리 서로 참조해도 순환이 생기지 않음
#   켜지지 않은 용도는 이름표에 없음 → 참조하면 plan에서 막힘
############################################################
locals {
  purpose_sg_ids = merge(
    var.was.enabled ? { for k, v in module.ec2_was[0].sg_ids : "was.${k}" => v } : {},
    var.webide.enabled ? { for k, v in module.ec2_webide[0].sg_ids : "webide.${k}" => v } : {},
  )
}

module "ec2_was" {
  source = "../deployment/ec2-was"
  count  = var.was.enabled ? 1 : 0

  protect_volumes         = local.protect.ec2_volumes
  alb_deletion_protection = local.protect.alb

  common              = module.ec2_common.contract
  ami                 = var.was.ami
  instance_type       = var.was.instance_type
  root_volume_size    = var.was.root_volume_size
  root_auto_grow      = var.was.root_auto_grow
  backup_plans        = var.was.backup_plans
  key_pair_name       = var.was.key_pair_name
  ebs_volumes         = var.was.ebs_volumes
  weekend_stop_enable = var.was.weekend_stop_enable

  enable_alb          = var.was.enable_alb
  alb_internal        = var.was.alb_internal
  alb_certificate_arn = local.shared.certificate_arn
  alb_record_name     = var.was.alb_record_name
  access_log_bucket   = local.access_log_bucket
  app_port            = var.was.app_port
  health_check_path   = var.was.health_check_path
  autoscale           = var.was.autoscale

  # 같은 단계 다른 용도 SG (sg_rules.csv에서 sg:webide.app 등으로 참조)
  peer_sg_ids = { for k, v in local.purpose_sg_ids : k => v if !startswith(k, "was.") }

  common_tags = var.common_tags
}

module "ec2_webide" {
  source = "../deployment/ec2-webide"
  count  = var.webide.enabled ? 1 : 0

  protect_volumes         = local.protect.ec2_volumes
  alb_deletion_protection = local.protect.alb

  common              = module.ec2_common.contract
  ami                 = var.webide.ami
  instance_type       = var.webide.instance_type
  root_volume_size    = var.webide.root_volume_size
  root_auto_grow      = var.webide.root_auto_grow
  backup_plans        = var.webide.backup_plans
  key_pair_name       = var.webide.key_pair_name
  ebs_volumes         = var.webide.ebs_volumes
  weekend_stop_enable = var.webide.weekend_stop_enable

  enable_alb          = var.webide.enable_alb
  alb_internal        = var.webide.alb_internal
  alb_certificate_arn = local.shared.certificate_arn
  alb_record_name     = var.webide.alb_record_name
  access_log_bucket   = local.access_log_bucket
  app_port            = var.webide.app_port
  health_check_path   = var.webide.health_check_path
  autoscale           = var.webide.autoscale

  # 같은 단계 다른 용도 SG (sg_rules.csv에서 sg:was.app 등으로 참조)
  peer_sg_ids = { for k, v in local.purpose_sg_ids : k => v if !startswith(k, "webide.") }

  common_tags = var.common_tags
}

############################################################
# 다음 단계(04-eks)로 넘길 값 (/iac/<site>/03-compute/ec2)
#   EKS API는 EC2에서만 접근을 허용하므로 EC2 SG 목록을 남깁니다.
############################################################
module "contract" {
  source = "../../aws-iac-terraform-module/module/management/aws-ssm-parameter-workload"

  path_prefix = "/iac/${var.site}/03-compute"
  description = "03-compute 묶음 (04-eks가 읽음)"
  parameters = {
    ec2 = {
      common_sg_id = module.ec2_common.common_sg_id
      # 이 단계에서 만든 SG 전체 (<용도>.<sg> → ID, 다음 단계가 참조할 때 사용)
      sg_ids = local.purpose_sg_ids
      app_sg_ids = merge(
        var.was.enabled ? { ec2_was = module.ec2_was[0].sg_id } : {},
        var.webide.enabled ? { ec2_webide = module.ec2_webide[0].sg_id } : {},
      )
    }
  }

  common_tags = var.common_tags
  site        = var.site
  stack       = "03-compute"
  key_target  = "contract"
}
