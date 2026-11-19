data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_elb_service_account" "this" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  state_bucket = coalesce(var.state_bucket_name, "iac-tfstate-${local.account_id}-${local.region}")
  log_bucket   = coalesce(var.log_bucket_name, "iac-logs-${local.account_id}-${local.region}")

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
  prevent_destroy = true

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
# DynamoDB 잠금 테이블 (선택)
############################################################
module "lock_table" {
  source = "../../aws-iac-terraform-module/module/database/aws-dynamodb-workload"
  count  = var.create_lock_table ? 1 : 0

  name        = var.lock_table_name
  hash_key    = "LockID"
  attributes  = { LockID = "S" }
  kms_key_arn = local.kms_key_arns.tfstate

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
  key_target  = "tfstate"
}

############################################################
# 로그 버킷 (선택, 기본값 생성)
#   경로: <site>/vpc-flow-logs/…, <site>/alb/<ALB 이름>/…
#   암호화: SSE-S3 (ALB 접근 로그는 SSE-KMS를 지원하지 않음)
############################################################
module "log_bucket" {
  source   = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/bucket"
  for_each = local.logs

  name            = local.log_bucket
  prevent_destroy = true

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
  key_target  = "logs"
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
    transitions = [
      { days = var.log_transition_ia_days, storage_class = "STANDARD_IA" },
      { days = var.log_transition_glacier_days, storage_class = "GLACIER" },
    ]
    expiration_days = var.log_retention_days
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
      # 2022-08 이전 리전(서울 포함)은 리전별 ELB 계정이 로그를 씀
      Sid       = "ElbLogsWriteLegacy"
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.this.arn }
      Action    = "s3:PutObject"
      Resource  = "{bucket_arn}/*/AWSLogs/${local.account_id}/*"
    },
    {
      Sid       = "ElbLogsWrite"
      Effect    = "Allow"
      Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
      Action    = "s3:PutObject"
      Resource  = "{bucket_arn}/*/AWSLogs/${local.account_id}/*"
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
        bucket     = module.state_bucket.id
        region     = local.region
        lock_table = var.create_lock_table ? module.lock_table[0].name : null
      }
      # 용도별 CMK (source: central = 중앙 계정 키, local = 이 계정 키)
      kms = {
        key_arns = local.kms_key_arns
        source   = local.kms_key_source
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
