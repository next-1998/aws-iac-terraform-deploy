############################################################
# DB 목록 CSV (선택): src/databases.csv
#   형식: src/databases.example.csv, module repo module/_rds_databases_csv
#   DB마다 자주 정하는 값만 CSV로 받고, 나머지는 tfvars 항목과 같은 기본값을 씁니다.
#   한 DB는 tfvars(rds_postgres 등)나 CSV 한 곳에만 적습니다 (같은 키면 plan에서 막힘)
#   사이트 단위 값은 tfvars: rds_nlb(개별/통합, 대상 등록 방법), rds_master_passwords(RDS 복제본), operation_mode
#   CSV에 없는 설정(파라미터 그룹 값·SG 규칙)은 DB별 CSV(deployment/<엔진>/src/rds-<DB 키>.*.csv)로
############################################################
locals {
  databases_csv_file = "${path.module}/src/databases.csv"
}

module "databases_csv" {
  source = "../../aws-iac-terraform-module/module/_rds_databases_csv"

  csv           = var.databases_csv != null ? var.databases_csv : (fileexists(local.databases_csv_file) ? file(local.databases_csv_file) : "")
  source_name   = "03-database/src/databases.csv"
  region        = var.region
  existing_keys = keys(merge(var.rds_postgres, var.rds_mysql, var.rds_mariadb, var.aurora_postgres, var.aurora_mysql))
}

locals {
  csv_db = module.databases_csv.databases

  # 기본값: variables.tf의 rds_postgres 등 optional 기본값과 같아야 함 (tests: csv_matches_tfvars_defaults)
  csv_version_default = { postgres = "16", mysql = "8.0", mariadb = "10.11", aurora_postgres = "16", aurora_mysql = "8.0" }
  csv_common = {
    for k, v in local.csv_db : k => {
      engine_version             = coalesce(v.engine_version, local.csv_version_default[v.engine])
      db_name                    = v.db_name
      username                   = "dbadmin"
      port                       = v.port
      parameters                 = []
      multi_az                   = v.multi_az
      backup_retention_days      = 7
      performance_insights       = false
      monitoring_interval        = 60
      auto_minor_version_upgrade = false
      apply_immediately          = false
      backup_plans               = v.backup ? ["daily", "pitr"] : [] # RDS 백업 표준: daily + pitr
      log_exports                = null
      log_retention_days         = 14
      allowed_cidrs              = null
      snapshot_identifier        = v.snapshot_identifier
      nlb                        = v.nlb
    }
  }

  # RDS: 복제본은 원본과 같은 사양 하나
  csv_rds = {
    for k, v in local.csv_db : k => merge(local.csv_common[k], {
      instance_class        = coalesce(v.instance_class, "db.t4g.micro")
      allocated_storage     = coalesce(v.allocated_storage, 20)
      max_allocated_storage = coalesce(v.max_allocated_storage, 100)
      replicas              = v.replica ? { r1 = { instance_class = null, multi_az = false, performance_insights = null } } : {}
    }) if !v.aurora
  }
  # Aurora: 복제본 = 클러스터 인스턴스 하나 추가 (같은 사양)
  csv_aurora = {
    for k, v in local.csv_db : k => merge(local.csv_common[k], {
      instance_class = coalesce(v.instance_class, "db.t4g.medium")
      serverless_v2  = v.serverless_v2
      storage_type   = "aurora"
      replicas       = v.replica ? { r1 = { instance_class = null, performance_insights = null } } : {}
    }) if v.aurora
  }

  # tfvars + CSV (엔진별). 이후 코드는 var.rds_postgres 대신 이 값을 씀
  rds_postgres    = merge(var.rds_postgres, { for k, v in local.csv_rds : k => v if local.csv_db[k].engine == "postgres" })
  rds_mysql       = merge(var.rds_mysql, { for k, v in local.csv_rds : k => v if local.csv_db[k].engine == "mysql" })
  rds_mariadb     = merge(var.rds_mariadb, { for k, v in local.csv_rds : k => v if local.csv_db[k].engine == "mariadb" })
  aurora_postgres = merge(var.aurora_postgres, { for k, v in local.csv_aurora : k => v if local.csv_db[k].engine == "aurora_postgres" })
  aurora_mysql    = merge(var.aurora_mysql, { for k, v in local.csv_aurora : k => v if local.csv_db[k].engine == "aurora_mysql" })

  rds_keys = concat(keys(local.rds_postgres), keys(local.rds_mysql), keys(local.rds_mariadb))
}

# CSV로 넣은 DB 검사 (tfvars DB는 variables.tf validation이 검사)
output "databases_csv_check" {
  description = "CSV로 넣은 DB 키 (없으면 빈 목록)"
  value       = keys(local.csv_db)

  precondition {
    # NLB를 쓰는 DB가 있으면 사이트 방식(rds_nlb)이 있어야 함
    condition     = var.rds_nlb != null || !anytrue([for k, v in local.csv_db : v.nlb != null])
    error_message = "databases.csv에 nlb_allowed_cidrs가 있는데 rds_nlb(개별/통합 방식)가 없습니다. tfvars에 rds_nlb = { mode = \"dedicated\" } 또는 { mode = \"shared\" }를 넣으세요."
  }
  precondition {
    # DB별 고정 IP는 개별 NLB만
    condition     = try(var.rds_nlb.mode, "") != "shared" || !anytrue([for k, v in local.csv_db : length(try(v.nlb.private_ips, {})) > 0])
    error_message = "통합 NLB(shared)는 DB별 nlb_private_ips를 쓸 수 없습니다. 고정 IP는 tfvars rds_nlb.private_ips에 넣으세요."
  }
  precondition {
    # RDS 읽기 복제본은 RDS 비밀번호 관리와 같이 쓸 수 없음
    condition     = alltrue([for k, v in local.csv_rds : length(v.replicas) == 0 || contains(keys(var.rds_master_passwords), k)])
    error_message = "databases.csv에서 replica = true인 RDS DB는 rds_master_passwords(test.tfvars 등 커밋하지 않는 파일)에 비밀번호가 필요합니다: ${join(", ", [for k, v in local.csv_rds : k if length(v.replicas) > 0 && !contains(nonsensitive(keys(var.rds_master_passwords)), k)])}"
  }
  precondition {
    # 통합 NLB 리스너 포트 겹침 (tfvars + CSV 전체)
    condition     = try(var.rds_nlb.mode, "") != "shared" || length(local.shared_nlb_ports) == length(distinct(local.shared_nlb_ports))
    error_message = "통합 NLB(shared)에 연결한 DB끼리 port가 겹칩니다: ${jsonencode(local.shared_nlb_ports)}. DB별 port를 다르게 하세요."
  }
}

locals {
  # NLB를 쓰는 DB의 리스너 포트 (tfvars + CSV, 비우면 엔진 기본)
  shared_nlb_ports = concat(
    [for k, v in local.rds_postgres : coalesce(v.port, 5432) if v.nlb != null],
    [for k, v in local.rds_mysql : coalesce(v.port, 3306) if v.nlb != null],
    [for k, v in local.rds_mariadb : coalesce(v.port, 3306) if v.nlb != null],
    [for k, v in local.aurora_postgres : coalesce(v.port, 5432) if v.nlb != null],
    [for k, v in local.aurora_mysql : coalesce(v.port, 3306) if v.nlb != null],
  )
}
