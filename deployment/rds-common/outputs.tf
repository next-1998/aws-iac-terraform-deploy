output "contract" {
  description = "rds-<용도>가 받는 값"
  value = {
    network           = var.network
    subnet_group_name = module.subnet_group.name
    subnet_cidrs      = merge({ for k, s in local.all_subnets : k => s.cidr }, local.use_shared ? try(local.subnets.shared_cidrs_for.db, {}) : {})
    shared_subnet     = local.use_shared # 01-network 공용 서브넷(use = db)을 쓰는지
    # 접근 허용 대역: 태그 Access-db = true 서브넷 (EC2 등). rds-core·aurora-core가 기본 허용에 더함
    access_cidrs   = sort(distinct([for id, s in data.aws_subnet.access_db : s.cidr_block]))
    kms_key_arn    = local.rds_kms_key_arn
    kms_key_source = local.local_rds_key ? "local" : "central"
    # 향상된 모니터링 역할 (켜지 않으면 null). 정책 연결 결과를 거쳐 넘겨 정책이 붙은 뒤에 DB가 씀
    monitoring_role_arn = var.enable_enhanced_monitoring ? (length(module.monitoring_role_policy[0].ids) > 0 ? module.monitoring_role[0].arn : null) : null

    # NLB (고정 IP 용도). DB(rds-core)가 리스너·대상 그룹을 붙일 때 씀
    nlb = {
      sync_tag_key     = local.nlb_sync_tag
      sync_dns_tag_key = local.nlb_sync_dns_tag
      db_subnet_by_az  = local.db_subnet_by_az
      shared = var.shared_nlb == null ? null : {
        arn         = module.shared_nlb[0].elb.arn
        dns_name    = module.shared_nlb[0].elb.dns_name
        sg_id       = module.shared_nlb_sg[0].securitygroup_id
        private_ips = module.shared_nlb[0].nlb_private_ips
      }
    }
  }
}

output "nlb_sync" {
  description = "NLB 대상 동기화 Lambda 이름 (켜지 않으면 null)"
  value       = try(module.ns_lambda["this"].function_name, null)

  precondition {
    condition     = !var.enable_nlb_sync || length(local.nlb_sync_endpoints) == 0
    error_message = "RDS NLB 동기화 Lambda용 VPC endpoint가 없습니다: ${join(", ", local.nlb_sync_endpoints)}. 01-network의 interface_endpoints에 추가하세요."
  }
}
