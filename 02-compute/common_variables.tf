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
      리소스별 키: ebs, s3, logs (00-bootstrap) / sns (02-shared) / rds (추가 예정)
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

variable "operation_mode" {
  description = <<-EOT
    운영 모드 (삭제 보호)
      "enable" : 운영. 버킷·KMS 키·NAT EIP 삭제 불가, KMS 삭제 대기 30일, ALB 삭제 보호, EC2 볼륨은 서버 삭제 후에도 남김
      그 외(null 등, 기본) : 위 항목 모두 삭제 가능 (destroy로 정리. 버킷은 파일까지, KMS 대기 7일, EC2 볼륨도 같이 삭제)
    항목별로 다르게 하려면 deletion_protection에서 선택
    처음 배포할 때 정하고 바꾸지 않습니다 (바꾸면 버킷·KMS 키·EIP가 새로 만들어짐). 모든 단계에 같은 값을 넣습니다
  EOT
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "항목별 삭제 보호 선택 (true = 삭제 불가, false = 삭제 가능, 비우면 operation_mode를 따름)"
  type = object({
    buckets     = optional(bool) # state·로그 버킷 (00-bootstrap)
    kms_keys    = optional(bool) # KMS 키 (00-bootstrap, 02-shared)
    nat_eip     = optional(bool) # NAT EIP (01-network)
    alb         = optional(bool) # ALB 삭제 보호 (02-compute)
    ec2_volumes = optional(bool) # 서버 삭제 후 EBS 볼륨 유지 (02-compute)
  })
  default = {}
}

locals {
  # 항목별 삭제 보호: 항목 값이 있으면 그 값, 없으면 operation_mode = "enable"일 때만 보호 (그 외 값은 모두 기본 = 삭제 가능)
  protect = {
    for k in ["buckets", "kms_keys", "nat_eip", "alb", "ec2_volumes"] :
    k => lookup(var.deletion_protection, k, null) != null ? lookup(var.deletion_protection, k, null) : var.operation_mode == "enable"
  }
}
