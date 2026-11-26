############################################################
# 03-database 입력
############################################################

variable "kms_key_administrators" {
  description = "RDS 키 관리자 (IAM role/user ARN). 비우면 계정 root 정책으로만 관리"
  type        = list(string)
  default     = []
}

# ── RDS (엔진별 DB 목록). 키 = DB 키 (이름 <접두어>-rds-<엔진 코드>-<DB 키>-01) ─────────────
variable "rds_postgres" {
  description = "PostgreSQL DB 목록 (DB 키 → 설정, deployment/rds-postgres). 비우면 만들지 않음. DB 이름 <접두어>-rds-<엔진 코드>-<DB 키>-01"
  type = map(object({
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
    monitoring_interval        = optional(number, 60)
    auto_minor_version_upgrade = optional(bool, false)
    backup_plans               = optional(list(string), [])
    log_exports                = optional(list(string))
    log_retention_days         = optional(number, 14)
    allowed_cidrs              = optional(list(string))
    snapshot_identifier        = optional(string)
    nlb = optional(object({                     # 이 DB를 NLB에 연결 (기본 없음). 개별/통합은 사이트의 rds_nlb.mode. 쓰기 리스너 = DB port
      allowed_cidrs = list(string)              # NLB로 접속할 고객 접근제어 대역 (필수)
      private_ips   = optional(map(string), {}) # AZ → 고정 IP (개별 NLB일 때만, 비우면 자동)
    }))
    replicas = optional(map(object({
      instance_class       = optional(string)
      multi_az             = optional(bool, false)
      performance_insights = optional(bool)
    })), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.rds_postgres : can(regex("^[a-z][a-z0-9]{0,11}$", k))])
    error_message = "rds_postgres의 키(DB 키)는 소문자로 시작하는 소문자·숫자 12자 이하여야 합니다 (하이픈 불가: 이름을 하이픈으로 나누기 때문)."
  }
  validation {
    # 읽기 복제본은 원본 자동 백업이 켜져 있어야 만들 수 있음
    condition     = alltrue([for k, v in var.rds_postgres : length(v.replicas) == 0 || v.backup_retention_days >= 1])
    error_message = "읽기 복제본(replicas)을 쓰는 DB는 backup_retention_days가 1 이상이어야 합니다 (원본 자동 백업 필요)."
  }
}

variable "rds_mysql" {
  description = "MySQL DB 목록 (DB 키 → 설정, deployment/rds-mysql). 비우면 만들지 않음. DB 이름 <접두어>-rds-<엔진 코드>-<DB 키>-01"
  type = map(object({
    engine_version        = optional(string, "8.0")
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
    monitoring_interval        = optional(number, 60)
    auto_minor_version_upgrade = optional(bool, false)
    backup_plans               = optional(list(string), [])
    log_exports                = optional(list(string))
    log_retention_days         = optional(number, 14)
    allowed_cidrs              = optional(list(string))
    snapshot_identifier        = optional(string)
    nlb = optional(object({                     # 이 DB를 NLB에 연결 (기본 없음). 개별/통합은 사이트의 rds_nlb.mode. 쓰기 리스너 = DB port
      allowed_cidrs = list(string)              # NLB로 접속할 고객 접근제어 대역 (필수)
      private_ips   = optional(map(string), {}) # AZ → 고정 IP (개별 NLB일 때만, 비우면 자동)
    }))
    replicas = optional(map(object({
      instance_class       = optional(string)
      multi_az             = optional(bool, false)
      performance_insights = optional(bool)
    })), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.rds_mysql : can(regex("^[a-z][a-z0-9]{0,11}$", k))])
    error_message = "rds_mysql의 키(DB 키)는 소문자로 시작하는 소문자·숫자 12자 이하여야 합니다 (하이픈 불가: 이름을 하이픈으로 나누기 때문)."
  }
  validation {
    # 읽기 복제본은 원본 자동 백업이 켜져 있어야 만들 수 있음
    condition     = alltrue([for k, v in var.rds_mysql : length(v.replicas) == 0 || v.backup_retention_days >= 1])
    error_message = "읽기 복제본(replicas)을 쓰는 DB는 backup_retention_days가 1 이상이어야 합니다 (원본 자동 백업 필요)."
  }
}

variable "rds_mariadb" {
  description = "MariaDB DB 목록 (DB 키 → 설정, deployment/rds-mariadb). 비우면 만들지 않음. DB 이름 <접두어>-rds-<엔진 코드>-<DB 키>-01"
  type = map(object({
    engine_version        = optional(string, "10.11")
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
    monitoring_interval        = optional(number, 60)
    auto_minor_version_upgrade = optional(bool, false)
    backup_plans               = optional(list(string), [])
    log_exports                = optional(list(string))
    log_retention_days         = optional(number, 14)
    allowed_cidrs              = optional(list(string))
    snapshot_identifier        = optional(string)
    nlb = optional(object({                     # 이 DB를 NLB에 연결 (기본 없음). 개별/통합은 사이트의 rds_nlb.mode. 쓰기 리스너 = DB port
      allowed_cidrs = list(string)              # NLB로 접속할 고객 접근제어 대역 (필수)
      private_ips   = optional(map(string), {}) # AZ → 고정 IP (개별 NLB일 때만, 비우면 자동)
    }))
    replicas = optional(map(object({
      instance_class       = optional(string)
      multi_az             = optional(bool, false)
      performance_insights = optional(bool)
    })), {})
  }))
  default = {}

  validation {
    # 엔진이 달라도 DB 키는 겹치면 안 됨 (다음 단계로 넘기는 값이 DB 키 하나로 묶임)
    condition     = length(setintersection(keys(var.rds_mariadb), concat(keys(var.rds_postgres), keys(var.rds_mysql)))) == 0 && length(setintersection(keys(var.rds_postgres), keys(var.rds_mysql))) == 0
    error_message = "rds_postgres, rds_mysql, rds_mariadb 사이에 같은 DB 키가 있습니다. DB 키는 엔진이 달라도 겹치면 안 됩니다."
  }

  validation {
    condition     = alltrue([for k, v in var.rds_mariadb : can(regex("^[a-z][a-z0-9]{0,11}$", k))])
    error_message = "rds_mariadb의 키(DB 키)는 소문자로 시작하는 소문자·숫자 12자 이하여야 합니다 (하이픈 불가: 이름을 하이픈으로 나누기 때문)."
  }
  validation {
    # 읽기 복제본은 원본 자동 백업이 켜져 있어야 만들 수 있음
    condition     = alltrue([for k, v in var.rds_mariadb : length(v.replicas) == 0 || v.backup_retention_days >= 1])
    error_message = "읽기 복제본(replicas)을 쓰는 DB는 backup_retention_days가 1 이상이어야 합니다 (원본 자동 백업 필요)."
  }
}

variable "rds_master_passwords" {
  description = <<-EOT
    마스터 비밀번호 평문 (DB 키 → 비밀번호). 넣은 DB는 RDS 비밀번호 관리(Secrets Manager)를 끄고 이 값을 씀
      읽기 복제본은 RDS 비밀번호 관리와 같이 쓸 수 없어서 복제본이 있는 DB는 필수 (엔진 무관)
      비밀번호가 tfvars·state에 평문으로 남습니다. test.tfvars(커밋 안 함)에만 넣고, 커밋하는 terraform.tfvars에는 넣지 않습니다
  EOT
  type        = map(string)
  default     = {}
  sensitive   = true

  validation {
    condition     = alltrue([for k in keys(var.rds_master_passwords) : contains(concat(keys(var.rds_postgres), keys(var.rds_mysql), keys(var.rds_mariadb)), k)])
    error_message = "rds_master_passwords의 키는 rds_postgres, rds_mysql, rds_mariadb에 있는 DB 키여야 합니다."
  }
  validation {
    # RDS 규칙: 8~128자, / " @ 공백 불가
    condition     = alltrue([for k, p in var.rds_master_passwords : length(p) >= 8 && length(p) <= 128 && !can(regex("[/\"@ ]", p))])
    error_message = "마스터 비밀번호는 8~128자이고 / \" @ 공백을 쓸 수 없습니다."
  }
  validation {
    condition     = alltrue([for k, v in merge(var.rds_postgres, var.rds_mysql, var.rds_mariadb) : length(v.replicas) == 0 || contains(keys(var.rds_master_passwords), k)])
    error_message = "RDS 읽기 복제본은 RDS 비밀번호 관리(Secrets Manager)와 같이 쓸 수 없습니다 (PostgreSQL·MariaDB 실계정 확인). 복제본이 있는 DB는 rds_master_passwords에 비밀번호를 넣으세요."
  }
}

variable "rds_nlb" {
  description = <<-EOT
    RDS 앞 NLB (고정 IP 용도, 특수 상황에만). null(기본)이면 NLB를 만들지 않음
      mode        : dedicated (nlb를 적은 DB마다 개별 NLB) | shared (사이트 통합 NLB 하나에 DB마다 리스너). 한 사이트에서 섞지 않음
      private_ips : 통합 NLB의 AZ → 고정 IP (shared만. 비우면 AWS가 정하고 NLB를 지울 때까지 유지)
    연결할 DB는 DB 설정에 nlb = { allowed_cidrs } 를 적음 (원본·대기만 연결, 읽기 복제본은 연결하지 않음)
  EOT
  type = object({
    mode        = string
    private_ips = optional(map(string), {})
  })
  default = null

  validation {
    condition     = var.rds_nlb == null || contains(["dedicated", "shared"], try(var.rds_nlb.mode, ""))
    error_message = "rds_nlb.mode는 dedicated(개별 NLB) 또는 shared(통합 NLB)여야 합니다."
  }
  validation {
    # DB에 nlb를 적었으면 사이트 방식이 있어야 함
    condition     = var.rds_nlb != null || !anytrue([for k, v in merge(var.rds_postgres, var.rds_mysql, var.rds_mariadb) : v.nlb != null])
    error_message = "DB 설정에 nlb가 있는데 rds_nlb(개별/통합 방식)가 없습니다. rds_nlb = { mode = \"dedicated\" } 또는 { mode = \"shared\" }를 넣으세요."
  }
  validation {
    # 개별 고정 IP는 개별 NLB에만
    condition     = try(var.rds_nlb.mode, "") != "shared" || !anytrue([for k, v in merge(var.rds_postgres, var.rds_mysql, var.rds_mariadb) : length(try(v.nlb.private_ips, {})) > 0])
    error_message = "통합 NLB(shared)는 DB별 nlb.private_ips를 쓸 수 없습니다. 고정 IP는 rds_nlb.private_ips에 넣으세요."
  }
  validation {
    # 통합 NLB 리스너 포트 = 각 DB의 port(없으면 엔진 기본). 겹치면 리스너를 만들 수 없음
    condition = try(var.rds_nlb.mode, "") != "shared" || length(flatten([
      for k, v in merge(
        { for k, v in var.rds_postgres : k => merge(v, { default_port = 5432 }) },
        { for k, v in var.rds_mysql : k => merge(v, { default_port = 3306 }) },
        { for k, v in var.rds_mariadb : k => merge(v, { default_port = 3306 }) },
      ) : [tostring(coalesce(v.port, v.default_port))] if v.nlb != null
      ])) == length(distinct(flatten([
        for k, v in merge(
          { for k, v in var.rds_postgres : k => merge(v, { default_port = 5432 }) },
          { for k, v in var.rds_mysql : k => merge(v, { default_port = 3306 }) },
          { for k, v in var.rds_mariadb : k => merge(v, { default_port = 3306 }) },
        ) : [tostring(coalesce(v.port, v.default_port))] if v.nlb != null
    ])))
    error_message = "통합 NLB(shared)에 연결한 DB끼리 리스너 포트(port)가 겹칩니다. DB마다 port를 다르게 지정하세요 (예: app 5432, orders 3306, shop 3307)."
  }
}
