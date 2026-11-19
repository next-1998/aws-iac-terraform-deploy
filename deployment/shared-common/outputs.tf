output "certificate_arn" {
  description = "검증이 끝난 사이트 인증서 ARN. ALB의 alb_certificate_arn에 사용"
  value       = local.create_cert ? module.acm_validation[0].certificate_arn : null
}

output "alarm_topic_arn" {
  value = var.enable_alarm_topic ? module.alarm_topic[0].arn : null
}

output "validation_records" {
  description = "인증서 검증 레코드가 들어간 존 (키: 도메인 → zone ID)"
  value       = local.create_cert ? module.acm_validation_record[0].route53_record_zone_id : {}
}

output "kms_keys" {
  description = "용도별 CMK (logs: CloudWatch 로그 그룹, sns: 알림 토픽). source: central = 중앙 키, local = 이 계정 키"
  value = {
    key_arns = local.kms_key_arns
    source   = local.kms_key_source
  }
}
