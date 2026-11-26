output "db" {
  description = "접속 정보 (aurora-core db: 쓰기 주소 address, 읽기 주소 reader_address)"
  value       = module.core.db
}

output "log_groups" {
  value = module.core.log_groups
}

output "allowed_cidrs" {
  value = module.core.allowed_cidrs
}

output "settings" {
  description = "주요 설정 (확인·테스트용)"
  value       = module.core.settings
}
