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

variable "central_kms_key_arns" {
  description = <<-EOT
    조직 중앙 계정의 CMK (용도 → 키 ARN). 넣은 용도는 키를 만들지 않고 중앙 키를 씀. 없으면 이 계정에 CMK를 만듦
      이 단계의 용도: ebs (계정 EBS 기본 키), s3 (S3 버킷), tfstate (state 버킷·잠금 테이블 전용 키, 분리 옵션)
    다른 단계와 같은 변수 이름이라 tfvars 값을 같이 써도 됨 (이 단계는 위 두 용도만 읽음)
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.central_kms_key_arns : contains(["ebs", "s3", "logs", "sns", "rds", "tfstate", "secrets", "backup"], k)])
    error_message = "central_kms_key_arns의 키는 ebs, s3, logs, sns, rds, tfstate, secrets, backup 중 하나여야 합니다."
  }
  validation {
    condition     = alltrue([for k, v in var.central_kms_key_arns : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", v))])
    error_message = "central_kms_key_arns 값은 키 ARN(arn:aws:kms:<리전>:<계정>:key/<ID>)이어야 합니다. alias는 다른 계정에서 쓸 수 없습니다."
  }
}

variable "tfstate_kms_key_administrators" {
  description = "tfstate 전용 CMK 관리자 (separate_tfstate_key = true일 때) (IAM role/user ARN). 비우면 계정 root 정책으로만 관리. state에는 민감 정보가 있을 수 있어 최소 인원만"
  type        = list(string)
  default     = []
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
variable "kms_key_administrators" {
  description = "이 단계에서 만드는 CMK(ebs, s3)의 관리자 (IAM role/user ARN). 비우면 계정 root 정책으로만 관리"
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

variable "separate_tfstate_key" {
  description = "state 버킷·잠금 테이블 전용 CMK를 따로 만듦 (분리 옵션). false면 s3 키를 같이 씀. 생성 후 바꾸면 state 버킷 암호화 키가 바뀜 (기존 객체는 재암호화되지 않음)"
  type        = bool
  default     = false
}
