############################################################
# backup 입력 (02-shared가 넘김)
############################################################
variable "site" {
  description = "사이트 이름 (리소스 이름, 대상 선택의 Site 태그 조건)"
  type        = string
}

variable "name_prefix" {
  description = "이름 앞부분 <회사>-<서비스>-<환경>-<리전 코드> (00-bootstrap naming). 볼트 <name_prefix>-bku-vault-main-01"
  type        = string
}

variable "name" {
  description = "stack 이름"
  type        = string
  default     = "backup"
}

variable "common_tags" {
  description = "사이트 공통 선택 태그"
  type        = map(string)
  default     = {}
}

variable "resource_tags" {
  description = "리소스 생성 시 붙이는 변경 태그 (예: VpcName)"
  type        = map(string)
  default     = {}
}

variable "plans" {
  description = <<-EOT
    백업 플랜 (플랜 이름 → 규칙 하나). 백업 종류마다 플랜 하나 (예: daily, monthly, pitr)
    대상: 태그 Backup-<플랜> = true 이고 Site = <site>인 리소스 (여러 플랜이면 태그도 여러 개, 예: Backup-daily = true, Backup-pitr = true)
      schedule                : cron(분 시 일 월 요일 년), timezone 기준 (기본 Asia/Seoul)
      retention_days          : 보관 일수
      cold_storage_after_days : 콜드 스토리지로 옮길 일수 (null이면 안 옮김)
      continuous_backup       : 시점 복구(PITR)용 연속 백업 (RDS·S3 등, 최대 35일)
  EOT
  type = map(object({
    schedule                = string
    timezone                = optional(string, "Asia/Seoul")
    retention_days          = number
    cold_storage_after_days = optional(number)
    continuous_backup       = optional(bool, false)
  }))

  validation {
    condition     = alltrue([for k, p in var.plans : can(regex("^[a-z0-9-]{1,20}$", k))])
    error_message = "플랜 이름(태그 값)은 소문자, 숫자, '-'로 20자 이하여야 합니다."
  }
}

variable "tag_key" {
  description = "백업 대상 태그 키 앞부분 (리소스에 <tag_key>-<플랜> = true, 예: Backup-daily = true)"
  type        = string
  default     = "Backup"
}

variable "vault_lock" {
  description = "볼트 잠금 (null이면 안 함). 보관 기간이 끝나기 전에는 누구도 백업을 지울 수 없음. changeable_for_days가 지나면 영구 (Compliance)"
  type = object({
    min_retention_days  = number
    max_retention_days  = optional(number)
    changeable_for_days = optional(number)
  })
  default = null
}

variable "central_kms_key_arns" {
  description = "조직 중앙 계정 CMK (용도 → 키 ARN). backup이 있으면 이 계정에 백업 키를 만들지 않음"
  type        = map(string)
  default     = {}
}

variable "kms_key_administrators" {
  description = "백업 키 관리자 (IAM role/user ARN)"
  type        = list(string)
  default     = []
}

variable "protect" {
  description = "삭제 보호 (단계 루트 operation_mode / deletion_protection.backups). true: 볼트 삭제 불가, 백업 보존 / false: destroy 때 백업까지 삭제"
  type        = bool
  default     = false
}

variable "protect_kms_keys" {
  description = "백업 키 삭제 보호 (operation_mode / deletion_protection.kms_keys)"
  type        = bool
  default     = false
}
