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
