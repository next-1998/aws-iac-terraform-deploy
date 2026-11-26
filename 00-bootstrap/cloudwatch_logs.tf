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
#     정책을 만들 때 AWS가 역할로 테스트 메시지를 보내 검증하므로 PutRecord 권한이 먼저 퍼져 있어야 함
#     → 권한을 역할과 함께 맨 먼저 붙이고(Firehose ARN은 이름으로 조립), Firehose를 만드는 동안 반영 시간을 벎. apply 한 번이면 됨
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
  cwlogs_subscription = local.cwlogs_enabled && var.enable_log_subscription ? { this = true } : {}

  cwlogs_name = "${local.name_prefix}-fh-cwlogs-01"

  # S3 경로 = 로그 그룹 이름 (앞의 / 제거)
  #   예외: RDS 로그 그룹은 AWS가 /aws/rds/instance/<DB>/<로그>로 고정 → 다른 리소스처럼 <VPC 이름>/rds/<DB>/<로그>
  #         DB 이름 <site>-rds-<용도>[-<복제본>]에서 site를 뽑고, VPC 이름 규칙 <site>-vpc (01-network)를 씀
  #   예) /iactest-vpc/ec2/iactest-ec2-was/messages      → iactest-vpc/ec2/iactest-ec2-was/messages/
  #       /aws/rds/instance/iactest-rds-app/postgresql   → iactest-vpc/rds/iactest-rds-app/postgresql/
  #   계정 단위 로그 그룹(VPC 없음): RDSOSMetrics → _account/rds/RDSOSMetrics/
  #   로그 그룹 이름이 빈 레코드(구독을 만들 때 CloudWatch Logs가 보내는 연결 확인 메시지) → _control/
  cwlogs_path_query = join("", [
    "{log_group: (.logGroup as $g",
    " | if (($g // \"\") == \"\") then \"_control\"",
    " elif $g == \"RDSOSMetrics\" then \"_account/rds/RDSOSMetrics\"",
    " else ((($g | capture(\"^/aws/rds/instance/(?<id>(?<site>[a-z0-9-]+?)-rds-[^/]+)/(?<log>[^/]+)$\")) // null) as $m",
    " | if $m then \"\\($m.site)-vpc/rds/\\($m.id)/\\($m.log)\" else ($g | ltrimstr(\"/\")) end) end)}",
  ])

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

  name               = "${local.name_prefix}-role-cwlogsfh-01"
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
  error_output_prefix  = "firehose-errors/cwlogs/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd}/"
  dynamic_partitioning = true
  processors = [
    # CloudWatch Logs가 보낸 gzip 데이터를 풂
    { type = "Decompression", parameters = { CompressionFormat = "GZIP" } },
    # 로그 그룹 이름 → 경로 (local.cwlogs_path_query)
    { type = "MetadataExtraction", parameters = {
      MetadataExtractionQuery = local.cwlogs_path_query
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

  name               = "${local.name_prefix}-role-cwlogssub-01"
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

  policy_name = "${local.name_prefix}-lpol-cwlogs-01"
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

############################################################
# RDS 향상된 모니터링 로그 그룹 (계정·리전에 하나, 이름은 AWS가 RDSOSMetrics로 고정)
#   미리 만들지 않으면 RDS가 보관 30일·기본 암호화로 만듦 → 다른 로그와 같게 보관 기간·logs CMK를 정함
#   S3로 보내는 방식은 다른 로그와 같음 (경로 _account/rds/RDSOSMetrics/, local.cwlogs_path_query)
############################################################
module "rds_os_metrics_log" {
  source = "../../aws-iac-terraform-module/module/monitor_log/aws-cloudwatch-workload/loggroup"
  count  = var.manage_rds_os_metrics_log_group ? 1 : 0

  name              = "RDSOSMetrics"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = local.kms_key_arns.logs

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
  key_target  = "rds_os_metrics"
}
