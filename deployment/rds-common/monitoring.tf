############################################################
# 향상된 모니터링 (Enhanced Monitoring) 역할
#   RDS가 OS 지표(CPU·메모리·프로세스 등, 1~60초)를 CloudWatch Logs RDSOSMetrics 로그 그룹에 보낼 때 쓰는 역할
#   사이트에 하나. DB마다 monitoring_interval로 켜고 끔 (rds-core)
#   참고: RDSOSMetrics 로그 그룹은 계정·리전에 하나라 RDS가 만듭니다 (보관 30일 기본)
############################################################
data "aws_partition" "current" {}

module "monitoring_role" {
  source = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role"
  count  = var.enable_enhanced_monitoring ? 1 : 0

  name               = "${local.np}-role-rdsmon-01"
  description        = "RDS enhanced monitoring for ${local.site}"
  assume_role_policy = templatefile("${path.module}/policies/rds-monitoring-trust.json.tftpl", {})

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_monitoring"
}

module "monitoring_role_policy" {
  source = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy-attachment"
  count  = var.enable_enhanced_monitoring ? 1 : 0

  role_name   = module.monitoring_role[0].name
  policy_arns = { monitoring = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole" }
}
