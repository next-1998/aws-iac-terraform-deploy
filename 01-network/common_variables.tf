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
