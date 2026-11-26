############################################################
# rds-core 입력 (엔진 조합 rds-postgres, rds-mysql, rds-mariadb가 DB마다 한 번씩 호출)
############################################################
variable "common" {
  description = "rds-common contract (network, subnet_group_name, kms_key_arn …)"
  type        = any
}

variable "name" {
  description = "stack 이름 = rds-<용도> (예: rds-app). DB identifier는 <site>-<name>"
  type        = string

  validation {
    condition     = can(regex("^rds-[a-z0-9-]{1,30}$", var.name))
    error_message = "name은 rds-<용도> 형식 (소문자, 숫자, '-')이어야 합니다."
  }
}

variable "common_tags" {
  description = "사이트 공통 선택 태그"
  type        = map(string)
  default     = {}
}

variable "logs_kms_key_arn" {
  description = "로그 그룹 암호화 키 (00-bootstrap logs 키). null이면 암호화 안 함"
  type        = string
  default     = null
}

# ── 엔진 ──────────────────────────────────────────────────────
variable "engine" {
  description = "postgres | mysql | mariadb"
  type        = string
  default     = "postgres"

  validation {
    condition     = contains(["postgres", "mysql", "mariadb"], var.engine)
    error_message = "engine은 postgres, mysql, mariadb 중 하나여야 합니다."
  }
}

variable "engine_version" {
  description = "엔진 버전. 주 버전만 쓰면 만들 때 그 안의 기본 부 버전 (예: postgres 16, mysql 8.0, mariadb 10.11). 부 버전 자동 업그레이드는 auto_minor_version_upgrade (기본 끔)"
  type        = string
  default     = "16"
}

variable "instance_class" {
  description = "인스턴스 클래스"
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "저장소 GiB (gp3)"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "저장소 자동 확장 상한 GiB (allocated_storage보다 크면 자동 확장 켜짐, 같으면 끔)"
  type        = number
  default     = 100
}

variable "db_name" {
  description = "처음 만들 데이터베이스 이름 (null이면 만들지 않음)"
  type        = string
  default     = null
}

variable "username" {
  description = "마스터 사용자 이름 (비밀번호는 RDS가 Secrets Manager에 만들고 관리)"
  type        = string
  default     = "dbadmin"
}

variable "port" {
  description = "포트. null이면 엔진 기본 (postgres 5432, mysql·mariadb 3306)"
  type        = number
  default     = null
}

variable "parameters" {
  description = "파라미터 그룹 값 [{ name, value, apply_method = immediate | pending-reboot }]. 보통은 src/<name>.parameters.csv 사용 (둘 다 넣으면 plan에서 막힘)"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default = []
}

# ── 가용성·보호 ────────────────────────────────────────────────
variable "multi_az" {
  description = "Multi-AZ (대기 인스턴스를 다른 AZ에). 단계 루트에서 operation_mode에 따라 기본값을 정해 넘김"
  type        = bool
  default     = false
}

variable "protect" {
  description = "삭제 보호 + 삭제 시 최종 스냅샷 (단계 루트 operation_mode / deletion_protection.rds)"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "자동 백업 보관 일수 (0이면 백업 끔. 운영은 7 이상 권장)"
  type        = number
  default     = 7
}

variable "performance_insights" {
  description = "Performance Insights (7일 무료 보관. 일부 작은 인스턴스 클래스는 지원 안 함)"
  type        = bool
  default     = false
}

# ── 로그 ──────────────────────────────────────────────────────
variable "log_exports" {
  description = "CloudWatch로 보낼 DB 로그. null이면 엔진 기본 (postgres: postgresql, upgrade / mysql·mariadb: error, slowquery)"
  type        = list(string)
  default     = null
}

variable "log_retention_days" {
  description = "DB 로그 CloudWatch 보관 일수 (S3에는 계정 로그 정책으로 더 오래)"
  type        = number
  default     = 14
}

# ── 접근 ──────────────────────────────────────────────────────
variable "allowed_cidrs" {
  description = "DB 포트 접근 허용 대역. null이면 EC2 서브넷 대역 전체 (03-compute와 같은 번호라 SG 대신 대역으로 허용)"
  type        = list(string)
  default     = null
}

variable "sg_rules_csv" {
  description = "SG 규칙 CSV 내용 (테스트용). null이면 src/<name>.sg_rules.csv를 읽음 (없으면 추가 규칙 없음)"
  type        = string
  default     = null
}

variable "sg_rule_limit" {
  description = "SG 규칙 한도 (AWS 기본 60)"
  type        = number
  default     = 60
}

variable "parameters_csv" {
  description = "파라미터 CSV 내용 (테스트용). null이면 src/<name>.parameters.csv를 읽음 (없으면 CSV 파라미터 없음)"
  type        = string
  default     = null
}

# ── 스냅샷 복원 · 읽기 복제본 ──────────────────────────────────
variable "snapshot_identifier" {
  description = <<-EOT
    이 스냅샷(DB "이미지")으로 DB를 만듦. 스냅샷 이름(같은 계정) 또는 ARN(다른 계정에서 공유받은 것)
    처음 만들 때만 적용: 나중에 바꾸거나 지워도 DB를 다시 만들지 않음 (새 스냅샷으로 바꾸려면 -replace)
    엔진·버전·db_name·username은 스냅샷 값을 따름. 비밀번호는 복원 뒤 Secrets Manager 관리로 바뀜
    스냅샷이 다른 KMS 키로 암호화돼 있으면 RDS 키로 복사한 스냅샷을 써야 함 (다른 계정이면 스냅샷·키 공유 필요)
  EOT
  type        = string
  default     = null
}

variable "replicas" {
  description = <<-EOT
    읽기 복제본 (키 → 설정). 키는 이름 끝 <site>-<name>-<키> (예: r1). 키를 바꾸면 복제본이 새로 만들어짐
      instance_class       : null이면 원본과 같음
      multi_az             : 복제본도 Multi-AZ로 (기본 false)
      performance_insights : null이면 원본과 같음
    원본 자동 백업(backup_retention_days ≥ 1)이 켜져 있어야 함. 복제본은 최종 스냅샷을 남기지 않음
  EOT
  type = map(object({
    instance_class       = optional(string)
    multi_az             = optional(bool, false)
    performance_insights = optional(bool)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, r in var.replicas : can(regex("^[a-z0-9-]{1,10}$", k))])
    error_message = "replicas의 키는 소문자, 숫자, '-'로 10자 이하여야 합니다."
  }
}

variable "master_password" {
  description = "마스터 비밀번호 평문. null(기본)이면 RDS가 만들어 Secrets Manager에 보관. 넣으면 tfvars·state에 평문으로 남음 (PostgreSQL 읽기 복제본은 이 방식만 가능)"
  type        = string
  default     = null
  sensitive   = true
}

variable "monitoring_interval" {
  description = "향상된 모니터링 간격(초): 0(끔), 1, 5, 10, 15, 30, 60. 복제본도 같은 값. 비용은 CloudWatch Logs(RDSOSMetrics) 수집량만큼"
  type        = number
  default     = 60

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "monitoring_interval은 0, 1, 5, 10, 15, 30, 60 중 하나여야 합니다."
  }
}

variable "auto_minor_version_upgrade" {
  description = "마이너 버전 자동 업그레이드 (기본 끔: 유지 관리 기간에 자동으로 버전이 바뀌지 않음. 올릴 때는 engine_version을 바꿔 apply)"
  type        = bool
  default     = false
}

variable "backup_plans" {
  description = "AWS Backup 플랜 이름 목록 (02-shared backup_plans). DB(원본)에 태그 Backup-<플랜> = true를 플랜마다 붙여 백업 대상이 됨. 빈 목록이면 태그 없음 (RDS 자동 백업만). 예: [daily, pitr]"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.backup_plans : can(regex("^[a-z0-9-]{1,20}$", p))])
    error_message = "backup_plans는 02-shared 플랜 이름(소문자, 숫자, '-')이어야 합니다."
  }
}

variable "src_dir" {
  description = "CSV(<name>.parameters.csv, <name>.sg_rules.csv)를 읽을 폴더. 엔진 조합(rds-postgres 등)이 자기 src 폴더를 넘김"
  type        = string
}

variable "src_label" {
  description = "오류 메시지에 보일 CSV 위치 (예: rds-postgres/src)"
  type        = string
}

variable "nlb" {
  description = <<-EOT
    RDS 앞 NLB (null이면 없음). 고객 DB 접근제어가 IP로만 허용할 때 고정 IP 용도 (nlb.tf)
      mode          : dedicated (이 DB 전용 NLB) | shared (rds-common 공유 NLB에 리스너만)
      allowed_cidrs : NLB로 접속할 수 있는 대역 (고객 접근제어 대역, 필수)
      read_port     : 읽기(복제본) 리스너 포트. 복제본이 있으면 필수, DB port와 달라야 함
      private_ips   : AZ → 고정 IP (dedicated만. 비우면 AWS가 정하고 NLB를 지울 때까지 유지)
    쓰기 리스너 포트 = DB port
  EOT
  type = object({
    mode          = string
    allowed_cidrs = list(string)
    read_port     = optional(number)
    private_ips   = optional(map(string), {})
  })
  default = null

  validation {
    condition     = var.nlb == null || contains(["dedicated", "shared"], try(var.nlb.mode, ""))
    error_message = "nlb.mode는 dedicated 또는 shared여야 합니다."
  }
  validation {
    condition     = var.nlb == null || length(try(var.nlb.allowed_cidrs, [])) > 0
    error_message = "nlb.allowed_cidrs(NLB로 접속할 고객 접근제어 대역)를 하나 이상 넣어야 합니다."
  }
  validation {
    condition     = var.nlb == null || length(var.replicas) == 0 || try(var.nlb.read_port != null, false)
    error_message = "복제본이 있는 DB에 NLB를 쓰면 nlb.read_port(읽기 리스너 포트)가 필요합니다."
  }
}
