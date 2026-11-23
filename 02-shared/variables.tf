############################################################
# 02-shared 입력
############################################################
variable "enable_certificate" {
  description = "사이트 ACM 인증서 생성 여부. 01-network에 root_domain이 있어야 함"
  type        = bool
  default     = true
}

variable "alarm_emails" {
  description = "알림을 받을 이메일 (넣으면 SNS 토픽 생성, 구독 확인 메일을 수락해야 동작)"
  type        = list(string)
  default     = []
}
