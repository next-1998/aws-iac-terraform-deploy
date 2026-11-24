############################################################
# CloudWatch Logs → S3 (계정 단위)
#   CloudWatch에는 짧게(기본 14일) 두고, 모든 로그 그룹을 S3 로그 버킷으로 계속 내보내 오래 보관합니다.
#   S3 보관 기간은 로그 버킷 수명 주기(log_retention_days, 기본 365일)를 따릅니다. 최종 보관일은 고객 협의 후 결정.
#
#   방식 (cloudwatch_logs_destination_arn으로 결정)
#   A. 이 계정 Firehose (기본)
#      모든 로그 그룹 ─(계정 단위 구독 필터)→ Firehose ─→ S3 <로그 버킷>/<로그 그룹 이름>/YYYY/MM/DD/
#      로그 그룹 이름 규칙이 /<VPC 이름>/<리소스 유형>/<리소스 이름>/<로그 이름> 이므로
#      S3도 <VPC 이름>/<리소스 유형>/<리소스 이름>/<로그 이름>/YYYY/MM/DD/ (Flow Logs, ELB 접근 로그와 같은 구조)
#      Firehose가 CloudWatch Logs 데이터를 풀어(Decompression) 로그 그룹 이름을 뽑고(MetadataExtraction) 경로로 씀(동적 파티셔닝)
#   B. 중앙 로그 계정 (destination ARN을 넣으면)
#      모든 로그 그룹 ─(계정 단위 구독 필터)→ 중앙 계정 CloudWatch Logs destination ─→ (중앙이 운영) Firehose ─→ 중앙 버킷
#      이 계정에는 Firehose를 만들지 않음. 서비스 계정이 보관 경로를 바꾸거나 지울 수 없음
#      중앙 destination 정책에 이 계정(또는 조직)의 구독 허용이 필요 (중앙 계정 사전 요청)
#   - 구독(실제 전송)은 enable_log_subscription = true일 때만. 쓰지 않는 환경은 false(기본)
#     정책을 만들 때 AWS가 역할로 테스트 메시지를 보내 검증하므로, 역할·권한을 만든 직후 켜면 IAM 반영 전이라 실패할 수 있음
#     → 새 계정은 첫 apply 후 다음 apply에서 켬
#   - 계정 단위 필터라 로그 그룹을 하나씩 등록하지 않아도 되고, 나중에 생기는 로그 그룹도 포함
#   - 로그는 모두 VPC 이름으로 시작하므로 계정 단위(VPC 없음) Firehose 오류 로그 그룹은 만들지 않음
#     전송·처리에 실패한 데이터는 S3 firehose-errors/ 에 남음 (Firehose 지표로도 확인)
#   - S3에 저장되는 파일은 CloudWatch Logs 형식 JSON(레코드마다 한 줄)을 gzip으로 묶은 것
############################################################

locals {
  cwlogs_central    = var.cloudwatch_logs_destination_arn != null
  cwlogs_enabled    = var.cloudwatch_logs_to_s3 && (local.cwlogs_central || var.create_log_bucket || var.cloudwatch_logs_bucket_arn != null)
  cwlogs_bucket_arn = var.cloudwatch_logs_bucket_arn != null ? var.cloudwatch_logs_bucket_arn : try(module.log_bucket["this"].arn, null)

  # A(이 계정 Firehose)일 때만 만드는 것들
  cwlogs = local.cwlogs_enabled && !local.cwlogs_central ? { this = true } : {}
  # 계정 구독 정책(A, B 모두)은 enable_log_subscription을 켰을 때만 (선택)
  #   새 계정: 첫 apply는 끈 채로(역할·권한·Firehose만 준비) → 다음 apply에서 켬 (IAM 권한 반영 시간 확보)
  cwlogs_subscription = local.cwlogs_enabled && var.enable_log_subscription ? { this = true } : {}

  cwlogs_name = "iac-cwlogs-to-s3"

  # policies/*.json.tftpl 에 넣는 값
  cwlogs_policy_vars = {
    partition     = data.aws_partition.current.partition
    region        = local.region
    account_id    = local.account_id
    firehose_name = local.cwlogs_name
  }
}

# Firehose → S3 쓰기 role
module "cwlogs_firehose_role" {
  source   = "../../aws-iac-terraform-module/module/security/aws-iam-workload/role"
  for_each = local.cwlogs

  name               = "${local.cwlogs_name}-firehose-role"
  description        = "Firehose writes CloudWatch Logs to S3"
  assume_role_policy = templatefile("${path.module}/policies/cwlogs-firehose-trust.json.tftpl", local.cwlogs_policy_vars)

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
  key_target  = "cwlogs_firehose"
}

module "cwlogs_firehose_policy" {
  source   = "../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy"
  for_each = local.cwlogs

  role_name = module.cwlogs_firehose_role[each.key].name
  # 경로가 로그 그룹 이름(<VPC 이름>/…)으로 정해지므로 버킷 전체. 로그 버킷 외에는 쓰지 못함
  policies = {
    "${local.cwlogs_name}-s3" = templatefile("${path.module}/policies/cwlogs-firehose-s3.json.tftpl", { bucket_arn = local.cwlogs_bucket_arn })
  }
}

module "cwlogs_firehose" {
  source   = "../../aws-iac-terraform-module/module/monitor_log/aws-firehose-workload/delivery-stream"
  for_each = local.cwlogs

  name       = local.cwlogs_name
  role_arn   = module.cwlogs_firehose_role[each.key].arn
  bucket_arn = local.cwlogs_bucket_arn
  # <로그 그룹 이름(앞의 / 제외)>/YYYY/MM/DD/  예) iactest-vpc/ec2/iactest-ec2-was/messages/2026/11/23/
  prefix               = "!{partitionKeyFromQuery:log_group}/!{timestamp:yyyy/MM/dd}/"
  error_output_prefix  = "firehose-errors/${local.cwlogs_name}/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd}/"
  dynamic_partitioning = true
  processors = [
    # CloudWatch Logs가 보낸 gzip 데이터를 풂
    { type = "Decompression", parameters = { CompressionFormat = "GZIP" } },
    # 로그 그룹 이름 → 경로 (앞의 / 제거)
    { type = "MetadataExtraction", parameters = {
      MetadataExtractionQuery = "{log_group: (.logGroup | ltrimstr(\"/\"))}"
      JsonParsingEngine       = "JQ-1.6"
    } },
    # 레코드마다 줄바꿈 (한 파일에 여러 JSON)
    { type = "AppendDelimiterToRecord" },
  ]
  # 풀어서 처리했으므로 S3에는 다시 gzip으로 저장
  compression_format = "GZIP"
  # S3는 보관 전용(조회는 CloudWatch)이라 크게 묶어 객체 수를 줄임 → PUT·수명 주기 전환 요청 비용 절감 (동적 파티셔닝은 64MB 이상)
  buffering_size     = 128
  buffering_interval = 900

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
  key_target  = "cwlogs"

  # S3 쓰기 권한이 붙은 뒤에 만들어야 생성 시 S3 쓰기 검사가 실패하지 않음
  # 로그 전달 역할도 먼저 만들어 둠 (구독 정책 생성 전 IAM 반영 시간 확보)
  depends_on = [module.cwlogs_firehose_policy, module.cwlogs_subscription_role]
}

# CloudWatch Logs → Firehose 전달 role
module "cwlogs_subscription_role" {
  source   = "../../aws-iac-terraform-module/module/security/aws-iam-workload/role"
  for_each = local.cwlogs

  name               = "${local.cwlogs_name}-logs-role"
  description        = "CloudWatch Logs sends all log groups to Firehose"
  assume_role_policy = templatefile("${path.module}/policies/cwlogs-subscription-trust.json.tftpl", local.cwlogs_policy_vars)

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
  key_target  = "cwlogs_subscription"
}

module "cwlogs_subscription_policy" {
  source   = "../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy"
  for_each = local.cwlogs

  role_name = module.cwlogs_subscription_role[each.key].name
  # Firehose ARN을 이름으로 조립 (Firehose 모듈을 참조하지 않음)
  #   → 권한이 역할과 함께 먼저 붙고, Firehose를 만드는 동안 IAM 반영 시간을 벎
  policies = {
    "${local.cwlogs_name}-firehose" = templatefile("${path.module}/policies/cwlogs-subscription-firehose.json.tftpl", local.cwlogs_policy_vars)
  }
}

# 계정의 모든 로그 그룹 → A: 이 계정 Firehose / B: 중앙 destination
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
  selection_criteria = null

  depends_on = [module.cwlogs_subscription_policy]
}
