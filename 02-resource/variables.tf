############################################################
# 02-resource 입력 (사이트마다 구성이 다르므로 사이트에 맞게 추가·삭제합니다)
############################################################

# ── 공통 ──────────────────────────────────────────────────────
variable "enable_alb_access_logs" {
  description = "ALB 접근 로그 저장 여부 (00-bootstrap 로그 버킷 또는 central_log_bucket_arn)"
  type        = bool
  default     = true
}

variable "alarm_emails" {
  type    = list(string)
  default = []
}

# ── ec2-common ────────────────────────────────────────────────
variable "ec2_common_sg_ingress" {
  description = "EC2 공통 SG 인바운드 (서버 접근용). 고객사마다 다름. 출발지는 prefix list 이름 권장"
  type        = any
  default     = []
}

# ── ec2-was ───────────────────────────────────────────────────
variable "was" {
  description = "WAS 서버 설정"
  type = object({
    enabled             = optional(bool, true)
    ami                 = string
    instance_type       = optional(string, "t3.micro")
    root_volume_size    = optional(number, 30)
    ebs_volumes         = optional(list(object({ device_name = string, volume_size = number, volume_type = optional(string, "gp3") })), [])
    weekend_stop_enable = optional(bool, false)
    ingress_rules       = optional(any, [])
    enable_alb          = optional(bool, true)
    alb_internal        = optional(bool, true)
    alb_record_name     = optional(string, "web")
    app_port            = optional(number, 8080)
    health_check_path   = optional(string, "/")
  })
}

# ── ec2-webide ────────────────────────────────────────────────
variable "webide" {
  description = "Web IDE 서버 설정"
  type = object({
    enabled             = optional(bool, true)
    ami                 = string
    instance_type       = optional(string, "t3.medium")
    root_volume_size    = optional(number, 30)
    ebs_volumes         = optional(list(object({ device_name = string, volume_size = number, volume_type = optional(string, "gp3") })), [])
    weekend_stop_enable = optional(bool, false)
    ingress_rules       = optional(any, [])
    enable_alb          = optional(bool, false)
    alb_internal        = optional(bool, true)
    alb_record_name     = optional(string, "ide")
    app_port            = optional(number, 80)
    health_check_path   = optional(string, "/")
  })
}

# ── EC2 주말 중지 (협의 후 적용) ───────────────────────────────
variable "ec2_weekend_stop" {
  description = "EC2 주말 중지. enabled면 Lambda와 스케줄 생성, schedule_enabled가 true가 되기 전까지는 실행되지 않음"
  type = object({
    enabled          = optional(bool, false)
    schedule_enabled = optional(bool, false)
    stop_schedule    = optional(string, "cron(0 21 ? * FRI *)")
    start_schedule   = optional(string, "cron(0 7 ? * MON *)")
    timezone         = optional(string, "Asia/Seoul")
    dry_run          = optional(bool, false)
  })
  default = {}
}
