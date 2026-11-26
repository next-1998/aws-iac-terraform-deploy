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

variable "enable_backup" {
  description = "AWS Backup 구성 여부 (볼트·플랜·IAM 역할. 볼트·플랜은 무료, 백업 데이터 저장량만큼 과금)"
  type        = bool
  default     = true
}

variable "backup_plans" {
  description = <<-EOT
    백업 플랜 (플랜 이름 → 규칙 이름 → 규칙). 리소스에 태그 Backup = <플랜 이름> 이 있고 Site = <site>인 리소스를 백업
    (AWS Backup이 지원하는 모든 유형: EC2·EBS·RDS·EFS·S3·DynamoDB 등). 원칙: AWS Backup이 지원하는 리소스는 AWS Backup만 사용
    한 리소스는 플랜 하나에만 들어가므로, 같이 받아야 하는 규칙은 한 플랜에 묶음 (예: pitr = 시점 복구 + 일간 스냅샷)
      schedule                : cron(분 시 일 월 요일 년), timezone 기준 (기본 Asia/Seoul)
      retention_days          : 보관 일수
      cold_storage_after_days : 콜드 스토리지로 옮길 일수 (EBS·EFS·DynamoDB 등 지원 유형만, 보관 일수 ≥ 이 값 + 90)
      continuous_backup       : 시점 복구(PITR)용 연속 백업 (RDS·S3, 보관 최대 35일, 플랜당 하나)
  EOT
  type = map(map(object({
    schedule                = string
    timezone                = optional(string, "Asia/Seoul")
    retention_days          = number
    cold_storage_after_days = optional(number)
    continuous_backup       = optional(bool, false)
  })))
  default = {
    daily   = { daily = { schedule = "cron(0 3 * * ? *)", retention_days = 7 } }     # 매일 03:00, 7일 보관
    monthly = { monthly = { schedule = "cron(0 3 1 * ? *)", retention_days = 365 } } # 매월 1일 03:00, 12개월 보관
    # 시점 복구(연속 백업 7일) + 일간 스냅샷(7일). RDS·S3 등 연속 백업 지원 리소스 (태그 Backup = pitr)
    pitr = {
      pitr  = { schedule = "cron(0 3 * * ? *)", retention_days = 7, continuous_backup = true }
      daily = { schedule = "cron(0 3 * * ? *)", retention_days = 7 }
    }
  }
  validation {
    condition     = alltrue(flatten([for k, p in var.backup_plans : [for r in values(p) : r.cold_storage_after_days == null || r.retention_days >= coalesce(r.cold_storage_after_days, 0) + 90]]))
    error_message = "콜드 스토리지를 쓰면 보관 일수(retention_days)가 이동 일수(cold_storage_after_days) + 90 이상이어야 합니다."
  }
  validation {
    condition     = alltrue(flatten([for k, p in var.backup_plans : [for r in values(p) : !r.continuous_backup || r.retention_days <= 35]]))
    error_message = "연속 백업(continuous_backup)은 보관 일수가 35일 이하여야 합니다."
  }
  validation {
    condition     = alltrue([for k, p in var.backup_plans : can(regex("^[a-z0-9-]{1,20}$", k)) && length(p) > 0 && length([for r in values(p) : r if r.continuous_backup]) <= 1])
    error_message = "플랜 이름(태그 값)은 소문자, 숫자, '-'로 20자 이하이고, 규칙이 하나 이상, 연속 백업 규칙은 플랜당 하나까지입니다."
  }
}

variable "backup_vault_lock" {
  description = "백업 볼트 잠금 (null이면 안 함, 기본). 켜면 보관 기간 전에는 누구도 백업을 지울 수 없고, changeable_for_days가 지나면 해제 불가 (Compliance)"
  type = object({
    min_retention_days  = number
    max_retention_days  = optional(number)
    changeable_for_days = optional(number)
  })
  default = null
}
