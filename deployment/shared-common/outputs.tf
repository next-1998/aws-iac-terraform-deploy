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
