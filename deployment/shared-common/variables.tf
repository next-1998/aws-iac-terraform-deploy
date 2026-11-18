variable "network" {
  description = "01-network contract (Parameter Store /iac/<site>/01-network/* 묶음을 합친 값)"
  type        = any
}

variable "name" {
  description = "stack 이름. 폴더 이름과 같게 둡니다"
  type        = string
  default     = "shared-common"
}

variable "common_tags" {
  description = "tfvars에서 정의하는 사이트 공통 태그"
  type        = map(string)
  default     = {}
}

variable "enable_certificate" {
  description = "사이트 ACM 인증서(<site>.<root_domain>, *.<site>.<root_domain>) 생성 여부. 01-network에 root_domain이 있어야 함"
  type        = bool
  default     = true
}

variable "enable_alarm_topic" {
  description = "SNS 알림 토픽 생성 여부"
  type        = bool
  default     = false
}

variable "alarm_emails" {
  description = "알림을 받을 이메일 (구독 확인 메일을 수락해야 동작)"
  type        = list(string)
  default     = []
}
