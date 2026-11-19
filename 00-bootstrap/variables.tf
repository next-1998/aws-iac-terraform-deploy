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

############################################################
# 계정·리전 보안 기본값 (account_defaults.tf) — 필수 적용, 끄는 옵션 없음
############################################################
variable "ebs_kms_key_administrators" {
  description = "EBS 기본 CMK 관리자 (IAM role/user ARN). 비우면 계정 root 정책으로만 관리"
  type        = list(string)
  default     = []
}

variable "ebs_kms_allow_autoscaling" {
  description = "Auto Scaling 서비스 연결 역할에 EBS CMK 사용 허용 (ASG를 쓸 때 true. 역할이 계정에 먼저 있어야 함)"
  type        = bool
  default     = false
}

variable "manage_s3_account_public_access_block" {
  description = "계정 단위 S3 퍼블릭 차단을 이 state에서 관리. 계정 전체 설정이라 여러 리전에서 이 단계를 실행하면 한 리전만 true"
  type        = bool
  default     = true
}
