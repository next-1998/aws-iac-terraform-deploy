############################################################
# aurora-postgres: Aurora PostgreSQL 클러스터 (엔진 조합)
#   엔진 고정값(engine = "aurora-postgresql")과 엔진 전용 검사·예제만 두고, 실제 구성은 aurora-core가 합니다.
#   CSV: src/<name>.cluster-parameters.csv (클러스터), src/<name>.parameters.csv (인스턴스), src/<name>.sg_rules.csv (SG)
############################################################
module "core" {
  source = "../aurora-core"

  common           = var.common
  name             = var.name
  logs_kms_key_arn = var.logs_kms_key_arn
  src_dir          = "${path.module}/src"
  src_label        = "aurora-postgres/src"

  engine         = "aurora-postgresql"
  engine_version = var.db.engine_version
  instance_class = var.db.instance_class
  serverless_v2  = var.db.serverless_v2
  storage_type   = var.db.storage_type
  db_name        = var.db.db_name
  username       = var.db.username
  port           = var.db.port
  parameters     = var.db.parameters

  multi_az                   = var.multi_az
  replicas                   = var.db.replicas
  protect                    = var.protect
  backup_retention_days      = var.db.backup_retention_days
  performance_insights       = var.db.performance_insights
  monitoring_interval        = var.db.monitoring_interval
  auto_minor_version_upgrade = var.db.auto_minor_version_upgrade
  apply_immediately          = var.db.apply_immediately
  backup_plans               = var.db.backup_plans
  snapshot_identifier        = var.db.snapshot_identifier

  log_exports        = var.db.log_exports
  log_retention_days = var.db.log_retention_days
  allowed_cidrs      = var.db.allowed_cidrs
  nlb                = var.db.nlb

  common_tags = var.common_tags
}
