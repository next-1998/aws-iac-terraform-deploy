############################################################
# RDS 키 (저장소 암호화, 마스터 비밀번호 비밀, Performance Insights)
#   central_kms_key_arns.rds가 있으면 중앙 키를 쓰고, 없으면 이 계정에 만듭니다.
#   RDS·Secrets Manager는 호출한 주체의 권한으로 키를 쓰므로 키 정책은 기본(계정 root + 관리자)으로 충분합니다.
############################################################
locals {
  local_rds_key = !contains(keys(var.central_kms_key_arns), "rds")
}

module "kms_key" {
  source = "../../../aws-iac-terraform-module/module/security/aws-kms-workload/key"
  count  = local.local_rds_key ? 1 : 0

  key_name                = "${local.np}-kms-rds-01"
  description             = "${local.site} RDS encryption (storage, master user secret, performance insights)"
  enable_key_rotation     = true
  deletion_window_in_days = var.protect_kms_keys ? 30 : 7
  prevent_destroy         = var.protect_kms_keys

  key_administrators = var.kms_key_administrators

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "rds"
}

module "kms_alias" {
  source = "../../../aws-iac-terraform-module/module/security/aws-kms-workload/alias"
  count  = local.local_rds_key ? 1 : 0

  name          = "${local.np}-kms-rds-01"
  target_key_id = module.kms_key[0].key_id
}

locals {
  rds_kms_key_arn = local.local_rds_key ? module.kms_key[0].key_arn : var.central_kms_key_arns["rds"]
}
