############################################################
# VPC Flow Logs → S3
#   경로: <bucket>/<site>/vpc-flow-logs/AWSLogs/<계정ID>/vpcflowlogs/<리전>/YYYY/MM/DD/HH/
#   버킷: 00-bootstrap 버킷 또는 중앙 로그 버킷 (01-network 단계 루트에서 결정해서 넘김)
############################################################
module "flow_log" {
  source = "../../../aws-iac-terraform-module/module/monitor_log/aws-flowlog-workload"
  count  = var.enable_flow_logs && var.flow_log_bucket_arn != null ? 1 : 0

  name       = "${var.site}-vpc-flow-log"
  vpc_id     = module.vpc.vpc.id
  bucket_arn = var.flow_log_bucket_arn
  prefix     = "${var.site}/vpc-flow-logs"

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "base"
}
