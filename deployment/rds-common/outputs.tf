output "contract" {
  description = "rds-<용도>가 받는 값"
  value = {
    network           = var.network
    subnet_group_name = module.subnet_group.name
    subnet_cidrs      = { for k, s in local.all_subnets : k => s.cidr }
    kms_key_arn       = local.rds_kms_key_arn
    kms_key_source    = local.local_rds_key ? "local" : "central"
  }
}
