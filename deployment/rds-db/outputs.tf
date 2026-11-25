output "db" {
  description = "접속 정보 (비밀번호는 secret_arn의 Secrets Manager 비밀에서 읽음)"
  value = {
    identifier = module.db.identifier
    engine     = var.engine
    address    = module.db.address
    port       = local.port
    db_name    = var.db_name
    username   = var.username
    secret_arn = module.db.master_user_secret_arn
    readers    = { for k, r in module.replica : k => r.address }
    sg_id      = module.sg.securitygroup_id
  }
}

output "allowed_cidrs" {
  description = "DB 포트 기본 허용 대역"
  value       = local.allowed_cidrs
}

output "log_groups" {
  description = "DB 로그 그룹 이름"
  value       = { for k, lg in module.db_log : k => lg.name }
}

output "sg_rules" {
  description = "적용한 SG 규칙 (기본 + CSV)"
  value = {
    ingress = merge(local.base_ingress, module.sg_rules_csv.ingress)
    egress  = module.sg_rules_csv.egress
  }
}

output "settings" {
  description = "주요 설정 (확인·테스트용)"
  value = {
    multi_az                    = var.multi_az
    deletion_protection         = var.protect
    final_snapshot              = var.protect
    manage_master_user_password = true
    parameter_group_family      = local.family
    parameters                  = local.parameters
    log_exports                 = local.log_exports
    from_snapshot               = var.snapshot_identifier != null
    replicas                    = keys(local.replicas)
  }
}

output "replicas" {
  description = "읽기 복제본 접속 주소 (키 → identifier, address). 읽기 전용"
  value       = { for k, r in module.replica : k => { identifier = r.identifier, address = r.address } }
}
