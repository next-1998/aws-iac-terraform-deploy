############################################################
# DB 로그 그룹 (DB보다 먼저: 보관 기간·암호화를 Terraform이 정함)
#   RDS가 쓰는 로그 그룹 이름은 AWS가 /aws/rds/instance/<identifier>/<로그>로 고정합니다.
#   → "로그 그룹은 /<VPC 이름>/…" 규칙의 예외. 미리 만들어 두지 않으면 RDS가 보관 기간 무기한·암호화 없이 만듦
############################################################
module "db_log" {
  source   = "../../../aws-iac-terraform-module/module/monitor_log/aws-cloudwatch-workload/loggroup"
  for_each = toset(local.log_exports)

  name              = "/aws/rds/instance/${local.identifier}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_${each.key}"
}

############################################################
# 파라미터 그룹 + DB 인스턴스
############################################################
module "parameter_group" {
  source = "../../../aws-iac-terraform-module/module/database/aws-rds-workload/parameter-group"

  name       = "${local.np}-rds-pagrp-${local.engine_defaults[var.engine].ver_code}-${local.db_key}-01" # 엔진·주버전 포함 (주버전을 바꾸면 새 파라미터 그룹)
  family     = local.family
  parameters = local.parameters

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}

module "db" {
  source = "../../../aws-iac-terraform-module/module/database/aws-rds-workload/instance"

  apply_immediately = var.apply_immediately

  identifier = local.identifier
  # 스냅샷으로 만들 때 (처음 한 번만. 이후 값 변경은 무시)
  snapshot_identifier = var.snapshot_identifier
  engine              = var.engine
  engine_version      = var.engine_version
  instance_class      = var.instance_class
  db_name             = var.db_name
  username            = var.username
  port                = local.port

  # 비밀번호: 기본은 RDS가 Secrets Manager에 만들고 관리 (tfvars·state에 비밀값 없음, 비밀은 RDS 키로 암호화)
  #           master_password를 넣으면 그 값 사용 (PostgreSQL 읽기 복제본은 이 방식만 가능)
  manage_master_user_password   = local.managed_password
  password                      = var.master_password
  master_user_secret_kms_key_id = var.common.kms_key_arn

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage > var.allocated_storage ? var.max_allocated_storage : null
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.common.kms_key_arn

  performance_insights_enabled    = var.performance_insights
  performance_insights_kms_key_id = var.performance_insights ? var.common.kms_key_arn : null

  multi_az                   = var.multi_az
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # 향상된 모니터링 (rds-common 역할)
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.common.monitoring_role_arn

  # 로그 그룹을 먼저 만든 뒤 내보내기 (로그 그룹 모듈 결과를 참조 → 순서 보장)
  enabled_cloudwatch_logs_exports = [for k, lg in module.db_log : k if lg.name != ""]

  parameter_group_name = module.parameter_group.name
  db_subnet_group_name = var.common.subnet_group_name
  security_group_ids   = [module.sg.securitygroup_id]

  # 보호(운영): 삭제 보호 + 삭제 시 최종 스냅샷 / 테스트: 바로 삭제
  deletion_protection     = var.protect
  skip_final_snapshot     = !var.protect
  backup_retention_period = var.backup_retention_days

  common_tags = var.common_tags
  # 백업 태그는 DB(원본)에만. 복제본은 원본이 백업되므로 제외
  resource_tags = merge(local.resource_tags, { for p in var.backup_plans : "Backup-${p}" => "true" })
  site          = local.site
  stack         = var.name
  key_target    = local.key
}
