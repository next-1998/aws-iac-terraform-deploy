############################################################
# CloudWatch Logs → S3 (계정 단위)
#   CloudWatch에는 짧게(기본 14일) 두고, 모든 로그 그룹을 S3 로그 버킷으로 계속 내보내 오래 보관합니다.
#   S3 보관 기간은 로그 버킷 수명 주기(log_retention_days, 기본 365일)를 따릅니다. 최종 보관일은 고객 협의 후 결정.
#
#   방식 (cloudwatch_logs_destination_arn으로 결정)
#   A. 이 계정 Firehose (기본)
#      모든 로그 그룹 ─(계정 단위 구독 필터)→ Firehose ─→ S3 <로그 버킷>/cloudwatch-logs/YYYY/MM/DD/
#   B. 중앙 로그 계정 (destination ARN을 넣으면)
#      모든 로그 그룹 ─(계정 단위 구독 필터)→ 중앙 계정 CloudWatch Logs destination ─→ (중앙이 운영) Firehose ─→ 중앙 버킷
#      이 계정에는 Firehose를 만들지 않음. 서비스 계정이 보관 경로를 바꾸거나 지울 수 없음
#      중앙 destination 정책에 이 계정(또는 조직)의 구독 허용이 필요 (중앙 계정 사전 요청)
#   - 계정 단위 필터라 로그 그룹을 하나씩 등록하지 않아도 되고, 나중에 생기는 로그 그룹도 포함
#   - A의 Firehose 오류 로그 그룹은 대상에서 뺌 (순환 방지)
#   - S3에 저장되는 파일은 CloudWatch Logs 형식(gzip JSON)
############################################################

locals {
  cwlogs_central    = var.cloudwatch_logs_destination_arn != null
  cwlogs_enabled    = var.cloudwatch_logs_to_s3 && (local.cwlogs_central || var.create_log_bucket || var.cloudwatch_logs_bucket_arn != null)
  cwlogs_bucket_arn = var.cloudwatch_logs_bucket_arn != null ? var.cloudwatch_logs_bucket_arn : try(module.log_bucket["this"].arn, null)

  # A(이 계정 Firehose)일 때만 만드는 것들
  cwlogs = local.cwlogs_enabled && !local.cwlogs_central ? { this = true } : {}
  # 구독 필터는 A, B 모두
  cwlogs_subscription = local.cwlogs_enabled ? { this = true } : {}

  cwlogs_name      = "iac-cwlogs-to-s3"
  cwlogs_error_log = "/aws/kinesisfirehose/${local.cwlogs_name}"
}

# Firehose 전송 오류 기록용 (구독 대상에서 제외)
module "cwlogs_error_log" {
  source   = "../../aws-iac-terraform-module/module/monitor_log/aws-cloudwatch-workload/loggroup"
  for_each = local.cwlogs

  name              = local.cwlogs_error_log
  retention_in_days = var.cloudwatch_logs_retention_days

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
  key_target  = "cwlogs_error"
}

# Firehose → S3 쓰기 role
module "cwlogs_firehose_role" {
  source   = "../../aws-iac-terraform-module/module/security/aws-iam-workload/role"
  for_each = local.cwlogs

  name        = "${local.cwlogs_name}-firehose-role"
  description = "Firehose writes CloudWatch Logs to S3"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "firehose.amazonaws.com" }
      Condition = { StringEquals = { "sts:ExternalId" = local.account_id } }
    }]
  })

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
  key_target  = "cwlogs_firehose"
}

module "cwlogs_firehose_policy" {
  source   = "../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy"
  for_each = local.cwlogs

  role_name = module.cwlogs_firehose_role[each.key].name
  policies = {
    "${local.cwlogs_name}-s3" = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect   = "Allow"
          Action   = ["s3:AbortMultipartUpload", "s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:PutObject"]
          Resource = [local.cwlogs_bucket_arn, "${local.cwlogs_bucket_arn}/cloudwatch-logs/*", "${local.cwlogs_bucket_arn}/cloudwatch-logs-errors/*"]
        },
        {
          Effect   = "Allow"
          Action   = ["logs:PutLogEvents"]
          Resource = "arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:log-group:${local.cwlogs_error_log}:*"
        },
      ]
    })
  }
}

module "cwlogs_firehose" {
  source   = "../../aws-iac-terraform-module/module/monitor_log/aws-firehose-workload/delivery-stream"
  for_each = local.cwlogs

  name                = local.cwlogs_name
  role_arn            = module.cwlogs_firehose_role[each.key].arn
  bucket_arn          = local.cwlogs_bucket_arn
  prefix              = "cloudwatch-logs/!{timestamp:yyyy/MM/dd}/"
  error_output_prefix = "cloudwatch-logs-errors/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd}/"
  # S3는 보관 전용(조회는 CloudWatch)이라 크게 묶어 객체 수를 줄임 → PUT·수명 주기 전환 요청 비용 절감
  buffering_size       = 128
  buffering_interval   = 900
  error_log_group_name = local.cwlogs_error_log

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
  key_target  = "cwlogs"

  # 권한이 붙은 뒤에 만들어야 생성 시 S3 쓰기 검사가 실패하지 않음
  depends_on = [module.cwlogs_firehose_policy]
}

# CloudWatch Logs → Firehose 전달 role
module "cwlogs_subscription_role" {
  source   = "../../aws-iac-terraform-module/module/security/aws-iam-workload/role"
  for_each = local.cwlogs

  name        = "${local.cwlogs_name}-logs-role"
  description = "CloudWatch Logs sends all log groups to Firehose"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "logs.amazonaws.com" }
      Condition = { StringLike = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:*" } }
    }]
  })

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
  key_target  = "cwlogs_subscription"
}

module "cwlogs_subscription_policy" {
  source   = "../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy"
  for_each = local.cwlogs

  role_name = module.cwlogs_subscription_role[each.key].name
  policies = {
    "${local.cwlogs_name}-firehose" = jsonencode({
      Version   = "2012-10-17"
      Statement = [{ Effect = "Allow", Action = ["firehose:PutRecord", "firehose:PutRecordBatch"], Resource = module.cwlogs_firehose[each.key].arn }]
    })
  }
}

# 계정의 모든 로그 그룹 → A: 이 계정 Firehose (오류 로그 그룹 제외) / B: 중앙 destination
#   B(다른 계정 destination)는 destination 정책으로 허용되므로 RoleArn을 쓰지 않음
module "cwlogs_account_subscription" {
  source   = "../../aws-iac-terraform-module/module/monitor_log/aws-cloudwatch-workload/log-account-policy"
  for_each = local.cwlogs_subscription

  policy_name = "${local.cwlogs_name}-all"
  policy_type = "SUBSCRIPTION_FILTER_POLICY"
  policy_document = jsonencode(local.cwlogs_central ? {
    DestinationArn = var.cloudwatch_logs_destination_arn
    FilterPattern  = ""
    Distribution   = "Random"
    } : {
    DestinationArn = module.cwlogs_firehose[each.key].arn
    RoleArn        = module.cwlogs_subscription_role[each.key].arn
    FilterPattern  = ""
    Distribution   = "Random"
  })
  selection_criteria = local.cwlogs_central ? null : "LogGroupName NOT IN [\"${local.cwlogs_error_log}\"]"

  depends_on = [module.cwlogs_subscription_policy]
}
