output "certificate_arn" {
  value = module.shared_common.certificate_arn
}

output "alarm_topic_arn" {
  value = module.shared_common.alarm_topic_arn
}

output "parameters" {
  description = "다음 단계가 읽는 Parameter Store 경로"
  value       = values(module.contract.names)
}

output "backup" {
  description = "AWS Backup (볼트, 태그 키, 플랜). 대상 리소스에 태그 Backup-<플랜> = true"
  value       = try(module.backup[0].contract, null)
}
