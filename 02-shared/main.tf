############################################################
# 02-shared
#   여러 유형(03-compute, 03-database …)이 같이 쓰는 리소스만 만듭니다.
#   - 사이트 ACM 인증서 (<site>.<root_domain>, *.<site>.<root_domain>)
#   - SNS 알림 토픽 (alarm_emails가 있을 때)
#   - AWS Backup 볼트·플랜 (enable_backup, 대상은 리소스 태그 Backup = <플랜 이름>)
#   결과는 /iac/<site>/02-shared/shared 에 남깁니다. 03-compute 등이 읽으므로 먼저 apply합니다.
############################################################

locals {
  network_bundles = ["base", "dns"]
}

# 민감 정보가 아닌 String 파라미터라 insecure_value로 읽습니다 (value는 항상 sensitive)
data "aws_ssm_parameter" "network" {
  for_each = toset(local.network_bundles)
  name     = "/iac/${var.site}/01-network/${each.key}"
}

locals {
  network = { for k, p in data.aws_ssm_parameter.network : k => jsondecode(p.insecure_value) }
}

module "shared_common" {
  source = "../deployment/shared-common"

  network              = local.network
  enable_certificate   = var.enable_certificate
  enable_alarm_topic   = length(var.alarm_emails) > 0
  central_kms_key_arns = var.central_kms_key_arns
  alarm_emails         = var.alarm_emails
  protect_kms_keys     = local.protect.kms_keys
  common_tags          = var.common_tags
}

module "backup" {
  source = "../deployment/backup"
  count  = var.enable_backup ? 1 : 0

  site                 = var.site
  vpc_name             = local.network.base.vpc_name
  resource_tags        = local.network.base.resource_tags
  plans                = var.backup_plans
  vault_lock           = var.backup_vault_lock
  central_kms_key_arns = var.central_kms_key_arns
  protect              = local.protect.backups
  protect_kms_keys     = local.protect.kms_keys
  common_tags          = var.common_tags
}

############################################################
# 다음 단계로 넘길 값 (/iac/<site>/02-shared/<묶음>)
############################################################
module "contract" {
  source = "../../aws-iac-terraform-module/module/management/aws-ssm-parameter-workload"

  path_prefix = "/iac/${var.site}/02-shared"
  description = "02-shared 묶음 (03-compute, 03-database가 읽음)"
  parameters = {
    shared = {
      certificate_arn = module.shared_common.certificate_arn
      alarm_topic_arn = module.shared_common.alarm_topic_arn
      # 리소스에 붙일 백업 태그 (플랜 → 태그 키, 값은 "true". 예: daily → Backup-daily). 백업을 안 쓰면 {}
      backup_tag_keys = try(module.backup[0].contract.tag_keys, {})
      backup_plans    = try(keys(module.backup[0].contract.plans), [])
      backup_vault    = try(module.backup[0].contract.vault_name, null)
    }
  }

  common_tags = var.common_tags
  site        = var.site
  stack       = "02-shared"
  key_target  = "contract"
}
