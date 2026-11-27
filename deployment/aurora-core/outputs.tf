output "db" {
  description = "접속 정보 (RDS 출력과 같은 모양 + reader_address. 비밀번호는 secret_arn의 Secrets Manager 비밀에서 읽음)"
  value = {
    identifier     = module.cluster.cluster_identifier
    engine         = var.engine
    address        = module.cluster.endpoint        # 쓰기 주소 (장애 조치 때 새 쓰기 인스턴스를 가리킴)
    reader_address = module.cluster.reader_endpoint # 읽기 주소 (읽기 인스턴스 부하 분산)
    port           = local.port
    db_name        = var.db_name
    username       = var.username
    secret_arn     = module.cluster.master_user_secret_arn
    readers        = { for k, i in module.instance : k => i.address if k != "w" }
    sg_id          = module.sg.securitygroup_id
    nlb            = local.nlb_on ? { mode = var.nlb.mode, dns_name = local.nlb_dns, private_ips = local.nlb_ips, port = local.port } : null
  }
}

output "allowed_cidrs" {
  value = local.allowed_cidrs
}

output "log_groups" {
  description = "로그 그룹 이름"
  value       = { for k, lg in module.db_log : k => lg.name }
}

output "settings" {
  description = "주요 설정 (확인·테스트용)"
  value = {
    cluster_identifier           = local.cluster_id
    instances                    = { for k, v in local.instances : k => { identifier = v.identifier, az = v.az, tier = v.tier, instance_class = v.instance_class } }
    serverless_v2                = var.serverless_v2
    parameter_group_name         = module.parameter_group.name
    cluster_parameter_group_name = module.cluster_parameter_group.name
    parameter_group_family       = local.ed.family
    deletion_protection          = var.protect
    monitoring_interval          = var.monitoring_interval
    auto_minor_version_upgrade   = var.auto_minor_version_upgrade
    apply_immediately            = var.apply_immediately
    backup_tags                  = { for p in var.backup_plans : "Backup-${p}" => "true" }
    log_exports                  = local.log_exports
    from_snapshot                = var.snapshot_identifier != null
    nlb_mode                     = try(var.nlb.mode, null)
    nlb_target_sync              = local.nlb_on ? (local.nlb_lambda ? "lambda" : "apply") : null
  }
}

output "nlb_check" {
  description = "통합 NLB를 쓰는데 rds-common에 공유 NLB가 없으면 plan에서 막음"
  value       = local.nlb_on ? var.nlb.mode : null

  precondition {
    condition     = !local.nlb_on || local.nlb_ded || local.nlb_shared != null
    error_message = "통합 NLB(shared)인데 공유 NLB가 없습니다 (03-database가 rds-common에 shared_nlb를 넘겨야 함)."
  }
}
