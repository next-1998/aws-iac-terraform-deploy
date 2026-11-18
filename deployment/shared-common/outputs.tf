output "certificate_arn" {
  description = "검증이 끝난 사이트 인증서 ARN. ALB의 alb_certificate_arn에 사용"
  value       = local.create_cert ? module.acm[0].acm_certificate_arn : null
  # 검증이 끝난 뒤에 ALB가 인증서를 쓰도록
  depends_on = [module.acm_validation]
}

output "alarm_topic_arn" {
  value = var.enable_alarm_topic ? aws_sns_topic.alarm[0].arn : null
}

output "validation_records" {
  description = "인증서 검증 레코드 (키: 도메인)"
  value       = aws_route53_record.acm_validation
}
