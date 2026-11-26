output "rds" {
  description = "DB 접속 정보 (DB 키 → 접속 정보. 비밀번호는 secret_arn의 Secrets Manager 비밀에서 읽음)"
  value       = local.rds_dbs
}

output "rds_kms_key" {
  value = local.any_db ? {
    arn    = module.rds_common[0].contract.kms_key_arn
    source = module.rds_common[0].contract.kms_key_source
  } : null
}

output "backup_plan_check" {
  description = "backup_plans 입력이 02-shared에 실제로 있는 플랜인지 (없는 이름이면 태그만 붙고 백업되지 않으므로 plan에서 막음)"
  value       = local.backup_plans_unknown

  precondition {
    condition     = length(local.backup_plans_unknown) == 0
    error_message = "02-shared에 없는 백업 플랜입니다: ${join(", ", local.backup_plans_unknown)}. 사용할 수 있는 플랜: ${length(local.backup_plans_known) == 0 ? "(없음: 02-shared enable_backup = false)" : join(", ", local.backup_plans_known)}"
  }
}
