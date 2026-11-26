############################################################
# aurora-mysql 입력 (03-database가 DB마다 한 번씩 호출)
############################################################
variable "common" {
  description = "rds-common contract (network, subnet_group_name, kms_key_arn …)"
  type        = any
}

variable "name" {
  description = "stack 이름 = rds-<DB 키> (예: rds-app). 클러스터 이름은 <접두어>-rds-cl-<엔진 코드>-<DB 키>-01"
  type        = string
}

variable "db" {
  description = "DB 설정 (03-database의 aurora_mysql 항목 하나). 항목 설명은 03-database/variables.tf"
  type        = any

  validation {
    condition     = var.db.log_exports == null || alltrue([for l in coalesce(var.db.log_exports, []) : contains(["audit", "error", "general", "slowquery", "iam-db-auth-error"], l)])
    error_message = "Aurora MySQL log_exports는 [audit, error, general, slowquery, iam-db-auth-error] 중에서 고릅니다."
  }
}

variable "multi_az" {
  description = "Multi-AZ (03-database가 operation_mode에 따라 정해 넘김)"
  type        = bool
  default     = false
}

variable "protect" {
  description = "삭제 보호 + 삭제 시 최종 스냅샷 (operation_mode / deletion_protection.rds)"
  type        = bool
  default     = false
}

variable "logs_kms_key_arn" {
  description = "로그 그룹 암호화 키 (00-bootstrap logs 키)"
  type        = string
  default     = null
}

variable "common_tags" {
  description = "사이트 공통 선택 태그"
  type        = map(string)
  default     = {}
}
