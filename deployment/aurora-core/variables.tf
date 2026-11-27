############################################################
# aurora-core 입력 (엔진 조합 aurora-postgres, aurora-mysql이 클러스터마다 한 번씩 호출)
#   항목 이름은 rds-core와 같게 둠. Aurora라서 다른 것: 용량 항목 없음, serverless_v2·storage_type 추가,
#   multi_az·replicas = 클러스터 안 읽기 인스턴스, 파라미터 CSV 두 개(클러스터·인스턴스)
############################################################
variable "common" {
  description = "rds-common contract (network, subnet_group_name, kms_key_arn, monitoring_role_arn, nlb …)"
  type        = any
}

variable "name" {
  description = "stack 이름 = rds-<DB 키> (예: rds-app). 클러스터 이름 <접두어>-rds-cl-<엔진 코드>-<DB 키>-01"
  type        = string
}

variable "common_tags" {
  type    = map(string)
  default = {}
}

variable "logs_kms_key_arn" {
  description = "로그 그룹 암호화 키 (00-bootstrap logs 키)"
  type        = string
  default     = null
}

variable "src_dir" {
  description = "CSV(<name>.parameters.csv, <name>.cluster-parameters.csv, <name>.sg_rules.csv)를 읽을 폴더 (엔진 조합의 src)"
  type        = string
}

variable "src_label" {
  description = "오류 메시지에 보일 CSV 위치 (예: aurora-postgres/src)"
  type        = string
}

# ── 엔진·용량 ─────────────────────────────────────────────────
variable "engine" {
  description = "aurora-postgresql | aurora-mysql"
  type        = string

  validation {
    condition     = contains(["aurora-postgresql", "aurora-mysql"], var.engine)
    error_message = "engine은 aurora-postgresql 또는 aurora-mysql이어야 합니다."
  }
}

variable "engine_version" {
  description = "엔진 버전 (예: aurora-postgresql 16 또는 16.4, aurora-mysql 8.0 또는 8.0.mysql_aurora.3.08.0)"
  type        = string
}

variable "instance_class" {
  description = "인스턴스 클래스 (Aurora 최소 db.t4g.medium). serverless_v2를 쓰면 무시하고 db.serverless"
  type        = string
  default     = "db.t4g.medium"
}

variable "serverless_v2" {
  description = "Serverless v2 용량 범위 { min_acu, max_acu } (null이면 프로비저닝)"
  type = object({
    min_acu = number
    max_acu = number
  })
  default = null
}

variable "storage_type" {
  description = "aurora (기본) | aurora-iopt1 (I/O 포함 요금)"
  type        = string
  default     = "aurora"
}

variable "db_name" {
  description = "처음 만들 데이터베이스 이름 (null이면 만들지 않음)"
  type        = string
  default     = null
}

variable "username" {
  description = "마스터 사용자 이름 (비밀번호는 RDS가 Secrets Manager로 관리)"
  type        = string
  default     = "dbadmin"
}

variable "port" {
  description = "포트. null이면 엔진 기본 (5432 / 3306)"
  type        = number
  default     = null
}

variable "parameters" {
  description = "DB(인스턴스) 파라미터 그룹 값. 보통은 src/<name>.parameters.csv"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default = []
}

variable "parameters_csv" {
  description = "인스턴스 파라미터 CSV 내용 (null이면 src/<name>.parameters.csv)"
  type        = string
  default     = null
}

variable "cluster_parameters_csv" {
  description = "클러스터 파라미터 CSV 내용 (null이면 src/<name>.cluster-parameters.csv)"
  type        = string
  default     = null
}

# ── 가용성 (클러스터 안 읽기 인스턴스) ─────────────────────────
variable "multi_az" {
  description = "true면 다른 AZ에 장애 조치용 읽기 인스턴스 1대 추가 (승격 우선순위 0)"
  type        = bool
  default     = false
}

variable "replicas" {
  description = "읽기 인스턴스 (키 → 설정). 이름 <인스턴스 이름>-NN (01 처음 쓰기, multi_az 다음 순번, 키 이름순)"
  type = map(object({
    instance_class       = optional(string)
    performance_insights = optional(bool)
  }))
  default = {}
}

# ── 보호·백업·운영 ─────────────────────────────────────────────
variable "protect" {
  description = "삭제 보호 + 삭제 시 최종 스냅샷"
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "클러스터 자동 백업 보관 일수 (1~35, 시점 복구)"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "Aurora backup_retention_days는 1~35여야 합니다 (Aurora는 자동 백업을 끌 수 없음)."
  }
}

variable "performance_insights" {
  type    = bool
  default = false
}

variable "monitoring_interval" {
  description = "향상된 모니터링 간격(초): 0(끔), 1, 5, 10, 15, 30, 60"
  type        = number
  default     = 60
}

variable "auto_minor_version_upgrade" {
  type    = bool
  default = false
}

variable "apply_immediately" {
  description = "변경을 바로 적용 (기본 false: 다음 유지 관리 시간)"
  type        = bool
  default     = false
}

variable "backup_plans" {
  description = "AWS Backup 플랜 목록 → 클러스터에 태그 Backup-<플랜> = true"
  type        = list(string)
  default     = []
}

variable "snapshot_identifier" {
  description = "이 클러스터 스냅샷으로 만듦 (처음 한 번만)"
  type        = string
  default     = null
}

# ── 로그·접근 ──────────────────────────────────────────────────
variable "log_exports" {
  description = "CloudWatch로 보낼 로그. null이면 엔진 기본 (aurora-postgresql: postgresql / aurora-mysql: error, slowquery)"
  type        = list(string)
  default     = null
}

variable "log_retention_days" {
  type    = number
  default = 14
}

variable "allowed_cidrs" {
  description = "DB 포트 허용 대역. null이면 EC2 서브넷 대역"
  type        = list(string)
  default     = null
}

variable "sg_rules_csv" {
  description = "SG 규칙 CSV 내용 (null이면 src/<name>.sg_rules.csv)"
  type        = string
  default     = null
}

variable "sg_rule_limit" {
  type    = number
  default = 60
}

variable "nlb" {
  description = "NLB 연결 { mode, allowed_cidrs, private_ips } (null이면 없음). 쓰기 인스턴스만 연결: 클러스터 쓰기 주소(DNS)를 동기화 Lambda가 조회"
  type        = any
  default     = null
}
