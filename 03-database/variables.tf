############################################################
# 03-database 입력
############################################################

variable "kms_key_administrators" {
  description = "RDS 키 관리자 (IAM role/user ARN). 비우면 계정 root 정책으로만 관리"
  type        = list(string)
  default     = []
}

# ── RDS (DB 이름 → 설정). 키가 용도 이름: rds-<키> ─────────────
variable "rds" {
  description = "RDS 인스턴스 목록 (deployment/rds-db/variables.tf 항목). 비우면 DB를 만들지 않음"
  type = map(object({
    engine                = optional(string, "postgres")
    engine_version        = optional(string, "16")
    instance_class        = optional(string, "db.t4g.micro")
    allocated_storage     = optional(number, 20)
    max_allocated_storage = optional(number, 100)
    db_name               = optional(string)
    username              = optional(string, "dbadmin")
    port                  = optional(number)
    parameters = optional(list(object({
      name         = string
      value        = string
      apply_method = optional(string, "pending-reboot")
    })), [])
    multi_az                   = optional(bool) # null이면 operation_mode = "enable"일 때만 켬
    backup_retention_days      = optional(number, 7)
    performance_insights       = optional(bool, false)
    monitoring_interval        = optional(number, 60)  # 향상된 모니터링 간격(초), 0이면 끔
    auto_minor_version_upgrade = optional(bool, false) # 마이너 버전 자동 업그레이드 (기본 끔)
    backup_plan                = optional(string)      # AWS Backup 플랜 (02-shared, 예: pitr). 넣으면 태그 Backup = <플랜>
    log_exports                = optional(list(string))
    log_retention_days         = optional(number, 14)
    allowed_cidrs              = optional(list(string)) # null이면 EC2 서브넷 대역
    snapshot_identifier        = optional(string)       # 이 스냅샷으로 만듦 (처음 한 번만)
    replicas = optional(map(object({                    # 읽기 복제본 (키 → 설정)
      instance_class       = optional(string)
      multi_az             = optional(bool, false)
      performance_insights = optional(bool)
    })), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.rds : can(regex("^[a-z0-9-]{1,30}$", k))])
    error_message = "rds의 키(용도 이름)는 소문자, 숫자, '-'로 30자 이하여야 합니다."
  }
  validation {
    # 읽기 복제본은 원본 자동 백업이 켜져 있어야 만들 수 있음
    condition     = alltrue([for k, v in var.rds : length(v.replicas) == 0 || v.backup_retention_days >= 1])
    error_message = "읽기 복제본(replicas)을 쓰는 DB는 backup_retention_days가 1 이상이어야 합니다 (원본 자동 백업 필요)."
  }
}

variable "rds_master_passwords" {
  description = <<-EOT
    마스터 비밀번호 평문 (DB 키 → 비밀번호). 넣은 DB는 RDS 비밀번호 관리(Secrets Manager)를 끄고 이 값을 씀
      PostgreSQL 읽기 복제본은 RDS 비밀번호 관리와 같이 쓸 수 없어서 복제본이 있는 postgres DB는 필수
      비밀번호가 tfvars·state에 평문으로 남습니다. test.tfvars(커밋 안 함)에만 넣고, 커밋하는 terraform.tfvars에는 넣지 않습니다
  EOT
  type        = map(string)
  default     = {}
  sensitive   = true

  validation {
    condition     = alltrue([for k in keys(var.rds_master_passwords) : contains(keys(var.rds), k)])
    error_message = "rds_master_passwords의 키는 rds에 있는 DB 키여야 합니다."
  }
  validation {
    # RDS 규칙: 8~128자, / " @ 공백 불가
    condition     = alltrue([for k, p in var.rds_master_passwords : length(p) >= 8 && length(p) <= 128 && !can(regex("[/\"@ ]", p))])
    error_message = "마스터 비밀번호는 8~128자이고 / \" @ 공백을 쓸 수 없습니다."
  }
  validation {
    condition     = alltrue([for k, v in var.rds : !(v.engine == "postgres" && length(v.replicas) > 0) || contains(keys(var.rds_master_passwords), k)])
    error_message = "PostgreSQL 읽기 복제본은 RDS 비밀번호 관리(Secrets Manager)와 같이 쓸 수 없습니다. 복제본이 있는 postgres DB는 rds_master_passwords에 비밀번호를 넣으세요."
  }
}
