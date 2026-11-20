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
  validation {
    # KMS 키는 쓰는 리소스와 같은 리전이어야 함 (다중 리전 키도 이 리전의 복제본 ARN을 넣음)
    condition     = alltrue([for k, v in var.central_kms_key_arns : try(split(":", v)[3] == var.region, false)])
    error_message = "central_kms_key_arns에 이 단계 리전(${var.region})이 아닌 키가 있습니다: ${join(", ", [for k, v in var.central_kms_key_arns : k if try(split(":", v)[3] != var.region, true)])}"
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
  description = "S3 로그 버킷 보관 기간 (일). 지나면 삭제. Flow Logs, ALB 접근 로그, CloudWatch Logs(내보낸 것) 공통. 기본 365일, 최종 보관일은 고객 협의 후 결정"
  type        = number
  default     = 365

  validation {
    condition     = var.log_retention_days > var.log_transition_glacier_days
    error_message = "log_retention_days(${var.log_retention_days})는 Glacier 전환 시점(log_transition_glacier_days = ${var.log_transition_glacier_days})보다 커야 합니다."
  }
}

variable "log_transition_ia_days" {
  description = "Standard-IA로 옮기는 시점 (일). null(기본값)이면 IA 단계 없이 Glacier로 바로. 지정하면 30 이상, Glacier 시점보다 30일 이상 앞이어야 함"
  type        = number
  default     = null

  validation {
    condition     = var.log_transition_ia_days == null || try(var.log_transition_ia_days >= 30, false)
    error_message = "log_transition_ia_days는 null(IA 단계 없음)이거나 30 이상이어야 합니다 (S3 규칙: 생성 후 30일이 지나야 IA로 전환 가능)."
  }
}

variable "log_transition_glacier_days" {
  description = "Glacier(Flexible Retrieval)로 옮기는 시점 (일). 기본 30. Glacier는 최소 보관 90일, 꺼낼 때 시간·비용이 듦"
  type        = number
  default     = 30

  validation {
    condition     = var.log_transition_glacier_days >= 0 && (var.log_transition_ia_days == null || try(var.log_transition_glacier_days >= var.log_transition_ia_days + 30, false))
    error_message = "log_transition_glacier_days는 0 이상이어야 하고, IA 단계를 쓰면 IA 전환 시점보다 30일 이상 뒤여야 합니다 (S3 규칙: IA에 30일 이상 머문 뒤 Glacier로 전환)."
  }
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

############################################################
# CloudWatch Logs → S3 (cloudwatch_logs.tf)
############################################################
variable "cloudwatch_logs_to_s3" {
  description = "계정의 모든 CloudWatch 로그 그룹을 S3 로그 버킷으로 내보냄 (장기 보관은 S3에서)"
  type        = bool
  default     = true

  validation {
    # 켰는데 보낼 곳(이 계정 로그 버킷, 버킷 ARN, 중앙 destination)이 하나도 없으면 조용히 꺼지지 않도록 막음
    condition     = !var.cloudwatch_logs_to_s3 || var.create_log_bucket || var.cloudwatch_logs_bucket_arn != null || var.cloudwatch_logs_destination_arn != null
    error_message = "cloudwatch_logs_to_s3 = true인데 보낼 곳이 없습니다. create_log_bucket = true, cloudwatch_logs_bucket_arn, cloudwatch_logs_destination_arn 중 하나를 지정하거나, 내보내지 않으려면 cloudwatch_logs_to_s3 = false로 명시하세요."
  }
}

variable "cloudwatch_logs_bucket_arn" {
  description = "CloudWatch 로그를 보낼 버킷 ARN. null이면 이 계정의 로그 버킷. create_log_bucket = false(중앙 로그 버킷)면 지정해야 내보냄"
  type        = string
  default     = null
}

variable "cloudwatch_logs_retention_days" {
  description = "이 단계에서 만드는 로그 그룹의 CloudWatch 보관 기간 (일). 장기 보관은 S3(log_retention_days)"
  type        = number
  default     = 14
}

variable "cloudwatch_logs_destination_arn" {
  description = "중앙 로그 계정의 CloudWatch Logs destination ARN (B 방식). 넣으면 이 계정에 Firehose를 만들지 않고 중앙으로 보냄. null이면 이 계정 Firehose → S3 (A 방식)"
  type        = string
  default     = null

  validation {
    condition     = var.cloudwatch_logs_destination_arn == null || can(regex("^arn:aws[a-z-]*:logs:[a-z0-9-]+:[0-9]{12}:destination:.+$", var.cloudwatch_logs_destination_arn))
    error_message = "cloudwatch_logs_destination_arn은 arn:aws:logs:<리전>:<계정>:destination:<이름> 형식이어야 합니다."
  }
  validation {
    # CloudWatch Logs destination은 구독하는 로그 그룹과 같은 리전이어야 함 (AWS 규칙)
    condition     = var.cloudwatch_logs_destination_arn == null || try(split(":", var.cloudwatch_logs_destination_arn)[3] == var.region, false)
    error_message = "cloudwatch_logs_destination_arn의 리전이 이 단계의 리전(${var.region})과 다릅니다. destination은 로그 그룹과 같은 리전이어야 합니다."
  }
}
