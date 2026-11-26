output "contract" {
  description = "다음 단계가 쓰는 값 (리소스에 붙일 태그, 플랜별 연속 백업 보관 일수)"
  value = {
    vault_name = module.vault.name
    vault_arn  = module.vault.arn
    tag_key    = var.tag_key
    plans = {
      for k, p in var.plans : k => {
        rules = { for r, v in p : r => { schedule = v.schedule, retention_days = v.retention_days, continuous_backup = v.continuous_backup } }
        # 연속 백업(시점 복구) 보관 일수. 없으면 null. RDS는 자동 백업 보관 기간을 이 값으로 맞춤 (AWS Backup이 관리)
        pitr_days = one([for v in values(p) : v.retention_days if v.continuous_backup])
      }
    }
    kms_key_arn = local.kms_key_arn
  }
}

output "settings" {
  description = "적용된 설정 (검사·확인용)"
  value = {
    local_kms_key  = length(module.kms_key) > 0
    vault_lock     = length(module.vault_lock) > 0
    force_destroy  = !var.protect
    tag_conditions = { for k, p in var.plans : k => { (var.tag_key) = k, Site = var.site } }
  }
}
