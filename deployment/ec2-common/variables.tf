############################################################
# 공통
############################################################
variable "network" {
  description = "01-network contract (Parameter Store /iac/<site>/01-network/* 묶음을 합친 값)"
  type        = any
}

variable "name" {
  description = "stack 이름. 폴더 이름과 같게 둡니다 (Stack 태그, 리소스 이름 접두어)"
  type        = string
  default     = "ec2-common"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.name))
    error_message = "name은 소문자, 숫자, '-'만 사용할 수 있습니다."
  }
}

variable "common_tags" {
  description = "tfvars에서 정의하는 사이트 공통 태그"
  type        = map(string)
  default     = {}
}


############################################################
# 주말 중지 (weekend_stop.tf) — 협의 후 적용
#   enable_weekend_stop = true면 Lambda와 스케줄을 만듭니다.
#   스케줄은 schedule_enabled = true가 되기 전까지 실행되지 않습니다 (임시 값).
#   대상은 EC2 태그 WEEKEND_STOP_ENABLE = "true" (ec2-<용도>의 weekend_stop_enable)
#   VPC 안에서 실행하므로 01-network interface_endpoints에 "ec2"가 있어야 합니다.
############################################################
variable "enable_weekend_stop" {
  description = "EC2 주말 중지 Lambda 생성 여부"
  type        = bool
  default     = false
}

variable "weekend_stop" {
  description = "주말 중지 설정 (스케줄은 임시 값, 협의 후 변경)"
  type = object({
    schedule_enabled   = optional(bool, false)
    stop_schedule      = optional(string, "cron(0 21 ? * FRI *)")
    start_schedule     = optional(string, "cron(0 7 ? * MON *)")
    timezone           = optional(string, "Asia/Seoul")
    dry_run            = optional(bool, false)
    log_retention_days = optional(number, 14) # CloudWatch 보관 (장기 보관은 S3로 내보냄: 00-bootstrap)
  })
  default = {}
}

############################################################
# 공통 SG 규칙 (sg.tf) — src/sg_rules.csv에서 읽음
############################################################
variable "sg_rules_csv" {
  description = "SG 규칙 CSV 내용. null(기본값)이면 src/sg_rules.csv를 읽음 (테스트나 다른 파일을 쓸 때만 지정)"
  type        = string
  default     = null
}

variable "sg_rule_limit" {
  description = "SG 하나의 방향별 규칙 한도 (AWS 기본 60). Service Quotas로 올렸으면 그 값으로"
  type        = number
  default     = 60
}

############################################################
# 암호화
############################################################
variable "logs_kms_key_arn" {
  description = "로그 그룹 암호화 CMK (02-shared의 logs 키). null이면 CloudWatch Logs 기본 암호화"
  type        = string
  default     = null
}
