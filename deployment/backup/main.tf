############################################################
# AWS Backup (사이트)
#   볼트(전용 KMS) + 플랜(이름마다 하나) + 대상 선택(태그) + IAM 역할
#   대상: AWS Backup이 지원하는 모든 리소스 유형 중 태그 <tag_key> = <플랜 이름> 이고 Site = <site>
#         (같은 계정에 사이트가 여러 개여도 서로의 리소스를 백업하지 않음)
#   리소스 유형 사용 설정(리전 설정)은 계정·리전 단위라 00-bootstrap이 합니다.
#   비용: 볼트·플랜은 무료, 백업 데이터 저장량만큼 + 키 월 $1
#   참고: EBS·RDS 등은 원본 리소스의 키로 암호화된 스냅샷이 그대로 보관됨 (볼트 키는 EFS, DynamoDB, S3 등 완전 관리형 유형에 적용)
############################################################
data "aws_partition" "current" {}

locals {
  prefix = "${var.site}-${var.name}"
  key    = replace(var.name, "-", "_")
}

# ── 백업 키 (중앙 키 backup이 있으면 만들지 않음) ──────────────
module "kms_key" {
  source = "../../../aws-iac-terraform-module/module/security/aws-kms-workload/key"
  count  = contains(keys(var.central_kms_key_arns), "backup") ? 0 : 1

  key_name                = "${var.site}-backup"
  description             = "${var.site} AWS Backup vault"
  enable_key_rotation     = true
  deletion_window_in_days = var.protect_kms_keys ? 30 : 7
  prevent_destroy         = var.protect_kms_keys

  key_administrators = var.kms_key_administrators

  common_tags   = var.common_tags
  resource_tags = var.resource_tags
  site          = var.site
  stack         = var.name
  key_target    = "backup"
  scope         = "shared"
}

module "kms_alias" {
  source = "../../../aws-iac-terraform-module/module/security/aws-kms-workload/alias"
  count  = length(module.kms_key)

  name          = "iac/${var.site}/backup"
  target_key_id = module.kms_key[0].key_id
}

locals {
  kms_key_arn = length(module.kms_key) > 0 ? module.kms_key[0].key_arn : var.central_kms_key_arns["backup"]
}

# ── 볼트 ───────────────────────────────────────────────────────
module "vault" {
  source = "../../../aws-iac-terraform-module/module/management/aws-backup-workload/vault"

  name            = "${local.prefix}-vault"
  kms_key_arn     = local.kms_key_arn
  prevent_destroy = var.protect
  force_destroy   = !var.protect # 테스트: destroy 때 남은 백업까지 삭제

  common_tags   = var.common_tags
  resource_tags = var.resource_tags
  site          = var.site
  stack         = var.name
  key_target    = local.key
  scope         = "shared"
}

module "vault_lock" {
  source = "../../../aws-iac-terraform-module/module/management/aws-backup-workload/vault-lock"
  count  = var.vault_lock == null ? 0 : 1

  vault_name          = module.vault.name
  min_retention_days  = var.vault_lock.min_retention_days
  max_retention_days  = var.vault_lock.max_retention_days
  changeable_for_days = var.vault_lock.changeable_for_days
}

# ── IAM 역할 (AWS Backup이 백업·복원에 사용) ───────────────────
module "role" {
  source = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role"

  name               = "${local.prefix}-role"
  description        = "AWS Backup service role for ${var.site}"
  assume_role_policy = templatefile("${path.module}/policies/backup-trust.json.tftpl", {})

  common_tags   = var.common_tags
  resource_tags = var.resource_tags
  site          = var.site
  stack         = var.name
  key_target    = local.key
}

module "role_policy" {
  source = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy-attachment"

  role_name = module.role.name
  policy_arns = {
    backup     = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
    restore    = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
    s3_backup  = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup"
    s3_restore = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore"
  }
}

# ── 플랜 + 대상 선택 (플랜 이름 = 태그 값) ──────────────────────
module "plan" {
  source   = "../../../aws-iac-terraform-module/module/management/aws-backup-workload/plan"
  for_each = var.plans

  name       = "${local.prefix}-${each.key}"
  vault_name = module.vault.name
  rules = {
    (each.key) = {
      schedule                = each.value.schedule
      timezone                = each.value.timezone
      retention_days          = each.value.retention_days
      cold_storage_after_days = each.value.cold_storage_after_days
      continuous_backup       = each.value.continuous_backup
    }
  }

  common_tags   = var.common_tags
  resource_tags = var.resource_tags
  site          = var.site
  stack         = var.name
  key_target    = "${local.key}_${replace(each.key, "-", "_")}"
  scope         = "shared"
}

module "selection" {
  source   = "../../../aws-iac-terraform-module/module/management/aws-backup-workload/selection"
  for_each = var.plans

  # 역할 권한은 백업이 실행될 때(다음 스케줄) 필요하므로 정책 연결과 순서를 맞출 필요 없음
  name           = "${local.prefix}-${each.key}"
  plan_id        = module.plan[each.key].id
  iam_role_arn   = module.role.arn
  resources      = ["*"]
  tag_conditions = { (var.tag_key) = each.key, Site = var.site }
}
