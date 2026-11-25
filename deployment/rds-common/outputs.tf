output "contract" {
  description = "rds-<용도>가 받는 값"
  value = {
    network           = var.network
    subnet_group_name = module.subnet_group.name
    subnet_cidrs      = { for k, s in local.all_subnets : k => s.cidr }
    kms_key_arn       = local.rds_kms_key_arn
    kms_key_source    = local.local_rds_key ? "local" : "central"
    # 향상된 모니터링 역할 (켜지 않으면 null). 정책 연결 결과를 거쳐 넘겨 정책이 붙은 뒤에 DB가 씀
    monitoring_role_arn = var.enable_enhanced_monitoring ? (length(module.monitoring_role_policy[0].ids) > 0 ? module.monitoring_role[0].arn : null) : null
  }
}
