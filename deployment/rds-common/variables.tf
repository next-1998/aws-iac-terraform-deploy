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

variable "enable_nlb_sync" {
  description = "NLB 대상 동기화 Lambda 생성 (NLB를 쓰는 DB가 하나라도 있으면 03-database가 켬)"
  type        = bool
  default     = false
}

variable "shared_nlb" {
  description = "공유 NLB (null이면 만들지 않음). nlb.mode = shared인 DB가 리스너(DB port)를 붙임. private_ips: AZ → 고정 IP (비우면 AWS가 정하고 NLB를 지울 때까지 유지)"
  type = object({
    private_ips = optional(map(string), {})
  })
  default = null
}

variable "logs_kms_key_arn" {
  description = "동기화 Lambda 로그 그룹 암호화 키 (00-bootstrap logs 키)"
  type        = string
  default     = null
}

variable "protect_nlb" {
  description = "NLB 삭제 보호 (operation_mode / deletion_protection.rds)"
  type        = bool
  default     = false
}
