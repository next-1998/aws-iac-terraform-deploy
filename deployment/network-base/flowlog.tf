############################################################
# VPC Flow Logs → S3
#   경로: <bucket>/<site>/vpc-flow-logs/AWSLogs/<계정ID>/vpcflowlogs/<리전>/YYYY/MM/DD/HH/
#   형식: Parquet, Hive 호환 시간 단위 파티션 (Athena 조회 비용과 속도에 유리)
#   버킷: 00-bootstrap 버킷 또는 중앙 로그 버킷 (01-network 단계 루트에서 결정해서 넘김)
############################################################
resource "aws_flow_log" "this" {
  count = var.enable_flow_logs && var.flow_log_bucket_arn != null ? 1 : 0

  vpc_id                   = module.vpc.vpc.id
  traffic_type             = "ALL"
  log_destination_type     = "s3"
  log_destination          = "${var.flow_log_bucket_arn}/${var.site}/vpc-flow-logs/"
  max_aggregation_interval = 600

  destination_options {
    file_format                = "parquet"
    hive_compatible_partitions = true
    per_hour_partition         = true
  }

  tags = module.tags.tags["flow_log"]
}
