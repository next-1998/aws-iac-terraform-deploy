output "db" {
  description = "접속 정보 (rds-core db)"
  value       = module.core.db
}

output "replicas" {
  description = "읽기 복제본 접속 주소"
  value       = module.core.replicas
}

output "log_groups" {
  description = "DB 로그 그룹"
  value       = module.core.log_groups
}

output "allowed_cidrs" {
  value = module.core.allowed_cidrs
}

output "sg_rules" {
  value = module.core.sg_rules
}

output "settings" {
  description = "주요 설정 (확인·테스트용)"
  value       = module.core.settings
}
