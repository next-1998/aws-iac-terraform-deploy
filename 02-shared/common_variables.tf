############################################################
# 모든 단계 공통 입력 (단계마다 같은 파일)
############################################################
variable "site" {
  description = "사이트 이름. 태그(Site, Stack), 리소스 이름 접두어, Parameter Store 경로에 사용. 소문자, 숫자, '-'만, 10자 안팎 권장"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,19}$", var.site))
    error_message = "site는 소문자, 숫자, '-'만 사용하고 20자 이하여야 합니다."
  }
}

variable "environment" {
  description = "환경 (Environment 태그)"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod"], var.environment)
    error_message = "environment는 dev, stg, prod 중 하나여야 합니다."
  }
}

variable "region" {
  description = "리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "common_tags" {
  description = "tfvars에서 정의하는 사이트 공통 태그 (선택 태그: Owner, CostCenter 등). 고정 태그 키는 넣을 수 없음"
  type        = map(string)
  default     = {}
}

variable "central_log_bucket_arn" {
  description = "중앙 로그 계정 버킷 ARN. null(기본값)이면 이 계정의 00-bootstrap 로그 버킷 사용"
  type        = string
  default     = null
}

variable "central_kms_key_arns" {
  description = <<-EOT
    조직 중앙 계정의 CMK (용도 → 키 ARN). 넣은 용도는 키를 만들지 않고 중앙 키를 씀. 없는 용도는 이 계정에 CMK를 만듦
      리소스별 키: ebs, s3 (00-bootstrap) / logs, sns (02-shared) / rds (추가 예정)
      분리 옵션 키: tfstate (00-bootstrap separate_tfstate_key) / secrets, backup (추가 예정). 중앙 키를 넣으면 옵션과 관계없이 그 키를 씀
    중앙 키 정책에 이 계정(과 서비스: logs, cloudwatch 등)의 사용 권한이 있어야 함 (중앙 계정 사전 요청)
  EOT
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.central_kms_key_arns : contains(["ebs", "s3", "logs", "sns", "rds", "tfstate", "secrets", "backup"], k)])
    error_message = "central_kms_key_arns의 키는 ebs, s3, logs, sns, rds, tfstate, secrets, backup 중 하나여야 합니다."
  }
  validation {
    # 다른 계정 키는 alias로 쓸 수 없어서 키 ARN만 받음
    condition     = alltrue([for k, v in var.central_kms_key_arns : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]+$", v))])
    error_message = "central_kms_key_arns 값은 키 ARN(arn:aws:kms:<리전>:<계정>:key/<ID>)이어야 합니다. alias는 다른 계정에서 쓸 수 없습니다."
  }
  validation {
    # KMS 키는 쓰는 리소스와 같은 리전이어야 함 (다중 리전 키도 이 리전의 복제본 ARN을 넣음)
    condition     = alltrue([for k, v in var.central_kms_key_arns : try(split(":", v)[3] == var.region, false)])
    error_message = "central_kms_key_arns에 이 단계 리전(${var.region})이 아닌 키가 있습니다: ${join(", ", [for k, v in var.central_kms_key_arns : k if try(split(":", v)[3] != var.region, true)])}"
  }
}
