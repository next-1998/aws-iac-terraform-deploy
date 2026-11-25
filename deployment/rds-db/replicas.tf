############################################################
# 읽기 복제본 (replicas)
#   원본과 같은 SG·파라미터 그룹·RDS 키를 씁니다. 같은 리전 복제 (원본 identifier 참조)
#   로그 그룹도 복제본마다 미리 만듭니다 (/aws/rds/instance/<복제본 identifier>/<로그>)
############################################################
locals {
  replicas = { for k, r in var.replicas : k => merge(r, { identifier = "${local.identifier}-${k}" }) }
  replica_logs = {
    for pair in setproduct(keys(local.replicas), local.log_exports) : "${pair[0]}|${pair[1]}" => { replica = pair[0], log = pair[1] }
  }
}

module "replica_log" {
  source   = "../../../aws-iac-terraform-module/module/monitor_log/aws-cloudwatch-workload/loggroup"
  for_each = local.replica_logs

  name              = "/aws/rds/instance/${local.replicas[each.value.replica].identifier}/${each.value.log}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.logs_kms_key_arn

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_${replace(each.value.replica, "-", "_")}_${each.value.log}"
}

module "replica" {
  source   = "../../../aws-iac-terraform-module/module/database/aws-rds-workload/instance"
  for_each = local.replicas

  identifier          = each.value.identifier
  replicate_source_db = module.db.identifier
  instance_class      = coalesce(each.value.instance_class, var.instance_class)
  port                = local.port

  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.common.kms_key_arn
  max_allocated_storage = var.max_allocated_storage > var.allocated_storage ? var.max_allocated_storage : null

  performance_insights_enabled    = coalesce(each.value.performance_insights, var.performance_insights)
  performance_insights_kms_key_id = coalesce(each.value.performance_insights, var.performance_insights) ? var.common.kms_key_arn : null

  multi_az                   = each.value.multi_az
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  # 향상된 모니터링 (rds-common 역할)
  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.common.monitoring_role_arn

  # 이 복제본의 로그 그룹을 먼저 만든 뒤 내보내기
  enabled_cloudwatch_logs_exports = [for k, lg in module.replica_log : lg.name == "" ? "" : split("|", k)[1] if split("|", k)[0] == each.key]

  parameter_group_name = module.parameter_group.name
  security_group_ids   = [module.sg.securitygroup_id]

  # 복제본: 삭제 보호는 원본과 같게, 최종 스냅샷·자동 백업은 없음 (원본이 백업)
  deletion_protection     = var.protect
  skip_final_snapshot     = true
  backup_retention_period = 0

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_${replace(each.key, "-", "_")}"
}
