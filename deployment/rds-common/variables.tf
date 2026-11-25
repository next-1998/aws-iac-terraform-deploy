############################################################
# rds-common 입력 (03-database가 넘김)
############################################################
variable "network" {
  description = "01-network contract (Parameter Store /iac/<site>/01-network/* 묶음을 합친 값)"
  type        = any
}

variable "name" {
  description = "stack 이름 (리소스 이름·태그에 사용)"
  type        = string
  default     = "rds-common"
}

variable "common_tags" {
  description = "사이트 공통 선택 태그"
  type        = map(string)
  default     = {}
}

variable "central_kms_key_arns" {
  description = "조직 중앙 계정 CMK (용도 → 키 ARN). rds가 있으면 이 계정에 RDS 키를 만들지 않고 그 키를 씀"
  type        = map(string)
  default     = {}
}

variable "kms_key_administrators" {
  description = "RDS 키 관리자 (IAM role/user ARN). 비우면 계정 root 정책으로만 관리"
  type        = list(string)
  default     = []
}

variable "protect_kms_keys" {
  description = "RDS 키 삭제 보호 (단계 루트 operation_mode / deletion_protection.kms_keys). true면 삭제 불가, 대기 30일"
  type        = bool
  default     = false
}

variable "enable_enhanced_monitoring" {
  description = "향상된 모니터링 역할 생성 (DB 중 monitoring_interval > 0이 하나라도 있으면 03-database가 켬)"
  type        = bool
  default     = false
}
