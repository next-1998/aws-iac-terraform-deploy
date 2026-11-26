output "contract" {
  description = "다음 단계가 쓰는 값 (리소스에 붙일 태그 안내)"
  value = {
    vault_name  = module.vault.name
    vault_arn   = module.vault.arn
    tag_keys    = { for k, p in var.plans : k => "${var.tag_key}-${k}" }
    plans       = { for k, p in var.plans : k => { schedule = p.schedule, retention_days = p.retention_days, continuous_backup = p.continuous_backup } }
    kms_key_arn = local.kms_key_arn
  }
}

output "settings" {
  description = "적용된 설정 (검사·확인용)"
  value = {
    local_kms_key = length(module.kms_key) > 0
    vault_lock    = length(module.vault_lock) > 0
    force_destroy = !var.protect
    selection     = { for k, p in var.plans : k => { "${var.tag_key}-${k}" = "true", Site = var.site } }
  }
}
