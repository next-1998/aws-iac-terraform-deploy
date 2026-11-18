variable "region" {
  description = "리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "common_tags" {
  description = "tfvars에서 정의하는 공통 태그"
  type        = map(string)
  default     = {}
}

############################################################
# state 버킷 (계정당 하나, 사이트는 경로로 구분: <site>/<단계>/terraform.tfstate)
############################################################
variable "state_bucket_name" {
  description = "state 버킷 이름. null이면 iac-tfstate-<계정ID>-<리전>"
  type        = string
  default     = null
}

variable "state_kms_key_arn" {
  description = "state 버킷 암호화 KMS 키. null이면 SSE-S3"
  type        = string
  default     = null
}

############################################################
# 잠금
#   Terraform 1.10 이상은 S3 자체 잠금(backend의 use_lockfile = true)을 씁니다.
#   1.10 미만을 쓰는 실행 환경이 있을 때만 DynamoDB 잠금 테이블을 만듭니다.
############################################################
variable "create_lock_table" {
  description = "DynamoDB 잠금 테이블 생성 여부 (Terraform 1.10 미만 환경이 있을 때만)"
  type        = bool
  default     = false
}

variable "lock_table_name" {
  description = "DynamoDB 잠금 테이블 이름"
  type        = string
  default     = "iac-tfstate-lock"
}

############################################################
# 로그 버킷 (VPC Flow Logs, ALB 접근 로그)
#   중앙 로그 계정을 쓰는 경우 create_log_bucket = false로 두고,
#   각 사이트 tfvars에 central_log_bucket_arn을 적습니다.
############################################################
variable "create_log_bucket" {
  description = "이 계정에 로그 버킷을 만들지 여부"
  type        = bool
  default     = true
}

variable "log_bucket_name" {
  description = "로그 버킷 이름. null이면 iac-logs-<계정ID>-<리전>"
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "로그 보관 기간 (일). 지나면 삭제"
  type        = number
  default     = 365
}

variable "log_transition_ia_days" {
  description = "Standard-IA로 옮기는 시점 (일)"
  type        = number
  default     = 30
}

variable "log_transition_glacier_days" {
  description = "Glacier로 옮기는 시점 (일)"
  type        = number
  default     = 90
}
