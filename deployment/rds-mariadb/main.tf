############################################################
# rds-mariadb: MariaDB DB (엔진 조합)
#   엔진 고정값(engine = "mariadb")과 엔진 전용 검사·예제만 두고, 실제 구성은 rds-core가 합니다.
#   CSV: src/<name>.parameters.csv (파라미터 그룹), src/<name>.sg_rules.csv (추가 SG 규칙)
############################################################
module "core" {
  source = "../rds-core"

  common           = var.common
  name             = var.name
  logs_kms_key_arn = var.logs_kms_key_arn
  src_dir          = "${path.module}/src"
  src_label        = "rds-mariadb/src"

  engine                = "mariadb"
  engine_version        = var.db.engine_version
  instance_class        = var.db.instance_class
  allocated_storage     = var.db.allocated_storage
  max_allocated_storage = var.db.max_allocated_storage
  db_name               = var.db.db_name
  username              = var.db.username
  port                  = var.db.port
  parameters            = var.db.parameters

  multi_az                   = var.multi_az
  protect                    = var.protect
  backup_retention_days      = var.db.backup_retention_days
  performance_insights       = var.db.performance_insights
  monitoring_interval        = var.db.monitoring_interval
  auto_minor_version_upgrade = var.db.auto_minor_version_upgrade
  backup_plans               = var.db.backup_plans

  log_exports        = var.db.log_exports
  log_retention_days = var.db.log_retention_days
  allowed_cidrs      = var.db.allowed_cidrs

  snapshot_identifier = var.db.snapshot_identifier
  replicas            = var.db.replicas
  nlb                 = var.db.nlb
  master_password     = var.master_password

  common_tags = var.common_tags
}
