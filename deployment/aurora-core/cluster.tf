############################################################
# 로그 그룹 (클러스터보다 먼저: 보관 기간·암호화를 Terraform이 정함)
#   Aurora 로그 그룹 이름은 AWS가 /aws/rds/cluster/<클러스터>/<로그>로 고정 (로그 경로 규칙의 예외)
############################################################
module "db_log" {
  source   = "../../../aws-iac-terraform-module/module/monitor_log/aws-cloudwatch-workload/loggroup"
  for_each = toset(local.log_exports)

  name              = "/aws/rds/cluster/${local.cluster_id}/${each.key}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_${each.key}"
}

############################################################
# 파라미터 그룹 2개 (클러스터 / 인스턴스). 엔진·주버전 포함 (주버전을 바꾸면 새 파라미터 그룹)
############################################################
module "cluster_parameter_group" {
  source = "../../../aws-iac-terraform-module/module/database/aws-rds-workload/cluster-parameter-group"

  name       = "${local.np}-rds-cpar-${local.ed.ver_code}-${local.db_key}-01"
  family     = local.ed.family
  parameters = local.cluster_parameters

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}

module "parameter_group" {
  source = "../../../aws-iac-terraform-module/module/database/aws-rds-workload/parameter-group"

  name       = "${local.np}-rds-pagrp-${local.ed.ver_code}-${local.db_key}-01"
  family     = local.ed.family
  parameters = local.parameters

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}

############################################################
# 클러스터
############################################################
module "cluster" {
  source = "../../../aws-iac-terraform-module/module/database/aws-rds-workload/cluster"

  cluster_identifier  = local.cluster_id
  snapshot_identifier = var.snapshot_identifier
  engine              = var.engine
  engine_version      = var.engine_version
  database_name       = var.db_name
  master_username     = var.username
  port                = local.port

  # 비밀번호: RDS가 Secrets Manager에 만들고 관리 (읽기 인스턴스는 클러스터 안이라 RDS 복제본 제약이 없음)
  manage_master_user_password   = true
  master_user_secret_kms_key_id = var.common.kms_key_arn

  storage_type  = var.storage_type
  kms_key_id    = var.common.kms_key_arn
  serverless_v2 = var.serverless_v2

  db_subnet_group_name         = var.common.subnet_group_name
  security_group_ids           = [module.sg.securitygroup_id]
  cluster_parameter_group_name = module.cluster_parameter_group.name

  # 로그 그룹을 먼저 만든 뒤 내보내기 (값 참조로 순서 보장)
  enabled_cloudwatch_logs_exports = [for k, lg in module.db_log : k if lg.name != ""]

  backup_retention_period = var.backup_retention_days
  deletion_protection     = var.protect
  skip_final_snapshot     = !var.protect
  # AWS Backup 대상이면 자동 백업을 남김 (실시간 백업이 걸린 DB는 true면 삭제가 거부됨. 남은 자동 백업은 보관 기간이 지나면 사라짐)
  delete_automated_backups = length(var.backup_plans) == 0
  apply_immediately        = var.apply_immediately

  common_tags = var.common_tags
  # 백업 태그는 클러스터에 (AWS Backup이 Aurora는 클러스터 단위로 백업)
  resource_tags = merge(local.resource_tags, { for p in var.backup_plans : "Backup-${p}" => "true" })
  site          = local.site
  stack         = var.name
  key_target    = local.key
}

############################################################
# 인스턴스 (쓰기 1 + 읽기 N). 쓰기·읽기 역할은 장애 조치 때 바뀔 수 있음
############################################################
module "instance" {
  source   = "../../../aws-iac-terraform-module/module/database/aws-rds-workload/cluster-instance"
  for_each = local.instances

  identifier              = each.value.identifier
  cluster_identifier      = module.cluster.cluster_identifier
  engine                  = var.engine
  instance_class          = each.value.instance_class
  availability_zone       = each.value.az
  promotion_tier          = each.value.tier
  db_parameter_group_name = module.parameter_group.name
  db_subnet_group_name    = var.common.subnet_group_name

  performance_insights_enabled    = each.value.performance_insights
  performance_insights_kms_key_id = each.value.performance_insights ? var.common.kms_key_arn : null

  monitoring_interval        = var.monitoring_interval
  monitoring_role_arn        = var.common.monitoring_role_arn
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_${replace(each.key, "_", "")}"
}
