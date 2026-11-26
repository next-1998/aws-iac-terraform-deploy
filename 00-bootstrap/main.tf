data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  state_bucket = coalesce(var.state_bucket_name, local.n.state_bucket)
  log_bucket   = coalesce(var.log_bucket_name, local.n.log_bucket)

  # 계정 단위 리소스라 사이트 대신 account를 씀 (Stack 태그 = account/00-bootstrap)
  tag = {
    site  = "account"
    stack = "00-bootstrap"
  }

  logs = var.create_log_bucket ? { this = true } : {}
}

############################################################
# state 버킷
#   버전 관리: state를 잘못 덮어써도 이전 버전으로 복구
#   삭제 보호: 실수로 지우면 모든 단계의 state를 잃으므로 prevent_destroy
############################################################
module "state_bucket" {
  source = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/bucket"

  name            = local.state_bucket
  prevent_destroy = local.protect.buckets
  force_destroy   = !local.protect.buckets # 보호하지 않을 때만 파일까지 지움

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
  key_target  = "tfstate"
}

module "state_versioning" {
  source = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/versioning"
  bucket = module.state_bucket.id
}

module "state_encryption" {
  source      = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/encryption"
  bucket      = module.state_bucket.id
  kms_key_arn = local.kms_key_arns.tfstate
}

module "state_public_access_block" {
  source = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/public-access-block"
  bucket = module.state_bucket.id
}

module "state_ownership" {
  source = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/ownership"
  bucket = module.state_bucket.id
}

# 오래된 state 버전 정리 (최근 버전은 유지)
module "state_lifecycle" {
  source = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/lifecycle"
  bucket = module.state_bucket.id
  lifecycle_rules = [{
    id                        = "noncurrent-versions"
    noncurrent_days           = 90
    newer_noncurrent_versions = 10
  }]
}

module "state_policy" {
  source     = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/policy"
  bucket     = module.state_bucket.id
  bucket_arn = module.state_bucket.arn

  depends_on = [module.state_public_access_block]
}

############################################################
# 로그 버킷 (선택, 기본값 생성)
#   경로: 모두 <VPC 이름>으로 시작 (<VPC 이름>/<리소스 유형>/<리소스 이름>/<로그 이름>/…)
#     Flow Logs <VPC>/vpc/<VPC>/flow-logs/, ALB <VPC>/elb/<ALB 이름>/access-logs/, CloudWatch 로그 <로그 그룹 이름>/YYYY/MM/DD/
#   암호화: SSE-S3 (ALB 접근 로그는 SSE-KMS를 지원하지 않음)
#   버전 관리: 로그를 덮어쓰거나 지워도 이전 버전이 남음 (이전 버전은 log_noncurrent_version_days 뒤 삭제)
############################################################
module "log_bucket" {
  source   = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/bucket"
  for_each = local.logs

  name            = local.log_bucket
  prevent_destroy = local.protect.buckets
  force_destroy   = !local.protect.buckets # 보호하지 않을 때만 파일까지 지움

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
  key_target  = "logs"
}

module "log_versioning" {
  source   = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/versioning"
  for_each = local.logs
  bucket   = module.log_bucket[each.key].id
}

module "log_encryption" {
  source   = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/encryption"
  for_each = local.logs
  bucket   = module.log_bucket[each.key].id
}

module "log_public_access_block" {
  source   = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/public-access-block"
  for_each = local.logs
  bucket   = module.log_bucket[each.key].id
}

module "log_ownership" {
  source   = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/ownership"
  for_each = local.logs
  bucket   = module.log_bucket[each.key].id
}

module "log_lifecycle" {
  source   = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/lifecycle"
  for_each = local.logs
  bucket   = module.log_bucket[each.key].id
  lifecycle_rules = [{
    id = "log-retention"
    # 로그는 쌓아 두는 용도(조회는 CloudWatch)라 기본은 30일 후 Glacier로 바로. IA 단계는 지정할 때만
    transitions = concat(
      var.log_transition_ia_days == null ? [] : [{ days = var.log_transition_ia_days, storage_class = "STANDARD_IA" }],
      [{ days = var.log_transition_glacier_days, storage_class = "GLACIER" }],
    )
    expiration_days = var.log_retention_days
    # 버전 관리로 남는 이전 버전(덮어쓰기·삭제된 로그) 정리
    noncurrent_days = var.log_noncurrent_version_days
  }]
}

# 로그 전달 서비스만 쓰기 허용 (VPC Flow Logs, ELB 접근 로그)
module "log_policy" {
  source     = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/policy"
  for_each   = local.logs
  bucket     = module.log_bucket[each.key].id
  bucket_arn = module.log_bucket[each.key].arn

  policy_statements = [
    {
      Sid       = "FlowLogsWrite"
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "{bucket_arn}/*"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id, "s3:x-amz-acl" = "bucket-owner-full-control" }
      }
    },
    {
      Sid       = "FlowLogsAclCheck"
      Effect    = "Allow"
      Principal = { Service = "delivery.logs.amazonaws.com" }
      Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
      Resource  = "{bucket_arn}"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    },
    {
      # ELB 접근 로그 (AWS 권장 방식: 서비스 주체 + 출처 조건)
      #   리전별 ELB 계정을 주체로 쓰는 예전 방식(legacy)은 출처 조건을 걸 수 없어 쓰지 않습니다.
      #   (다른 계정 ALB가 로그 prefix를 "x/AWSLogs/<이 계정>"으로 잡으면 이 경로에 쓸 수 있음 → 혼동된 대리자)
      #   aws:SourceArn으로 이 계정·리전의 로드밸런서만 쓸 수 있게 제한합니다.
      Sid       = "ElbLogsWrite"
      Effect    = "Allow"
      Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "{bucket_arn}/*/AWSLogs/${local.account_id}/*"
      Condition = {
        ArnLike = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:elasticloadbalancing:${local.region}:${local.account_id}:loadbalancer/*" }
      }
    },
  ]

  depends_on = [module.log_public_access_block]
}

############################################################
# 다음 단계가 읽는 값 (계정 단위 경로 /iac/_account/00-bootstrap/<이름>)
############################################################
module "parameters" {
  source = "../../aws-iac-terraform-module/module/management/aws-ssm-parameter-workload"

  path_prefix = "/iac/_account/00-bootstrap"
  description = "00-bootstrap (계정 단위 값)"
  parameters = merge(
    {
      state = {
        bucket = module.state_bucket.id
        region = local.region
      }
      # 용도별 CMK (source: central = 중앙 계정 키, local = 이 계정 키)
      kms = {
        key_arns = local.kms_key_arns
        source   = local.kms_key_source
      }
      # 이름 규칙 앞부분 (다른 단계가 읽어 <접두어>-<유형>-<이름>-<순번>[-<AZ>]로 씀)
      naming = {
        prefix      = local.name_prefix
        company     = var.naming.company
        service     = var.naming.service
        env         = var.naming.env
        region_code = local.region_code
        vpc_name    = local.vpc_name
      }
    },
    var.create_log_bucket ? {
      logs = {
        bucket     = module.log_bucket["this"].id
        bucket_arn = module.log_bucket["this"].arn
      }
    } : {},
  )

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
}
