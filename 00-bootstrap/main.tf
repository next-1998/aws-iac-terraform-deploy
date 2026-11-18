data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_elb_service_account" "this" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name

  state_bucket = coalesce(var.state_bucket_name, "iac-tfstate-${local.account_id}-${local.region}")
  log_bucket   = coalesce(var.log_bucket_name, "iac-logs-${local.account_id}-${local.region}")

  tags = { ManagedBy = "terraform", Stack = "account/00-bootstrap" }
}

############################################################
# state 버킷
#   버전 관리: state를 잘못 덮어써도 이전 버전으로 복구
#   삭제 보호: 실수로 지우면 모든 단계의 state를 잃으므로 prevent_destroy
############################################################
resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket
  tags   = merge(local.tags, { Name = local.state_bucket, ResourceType = "s3:bucket", ResourceKey = "tfstate_s3" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.state_kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.state_kms_key_arn
    }
    bucket_key_enabled = var.state_kms_key_arn != null
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# 오래된 state 버전 정리 (최근 버전은 유지)
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    id     = "noncurrent-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days           = 90
      newer_noncurrent_versions = 10
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.state]
}

############################################################
# DynamoDB 잠금 테이블 (선택)
############################################################
resource "aws_dynamodb_table" "lock" {
  count        = var.create_lock_table ? 1 : 0
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = merge(local.tags, { Name = var.lock_table_name, ResourceType = "dynamodb:table", ResourceKey = "tfstate_lock" })
}

############################################################
# 로그 버킷 (선택, 기본값 생성)
#   경로: <site>/vpc-flow-logs/…, <site>/alb/<ALB 이름>/…
#   암호화: SSE-S3 (ALB 접근 로그는 SSE-KMS를 지원하지 않음)
############################################################
resource "aws_s3_bucket" "logs" {
  count  = var.create_log_bucket ? 1 : 0
  bucket = local.log_bucket
  tags   = merge(local.tags, { Name = local.log_bucket, ResourceType = "s3:bucket", ResourceKey = "logs_s3" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = var.create_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count                   = var.create_log_bucket ? 1 : 0
  bucket                  = aws_s3_bucket.logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  count  = var.create_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count  = var.create_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  rule {
    id     = "log-retention"
    status = "Enabled"
    filter {}
    transition {
      days          = var.log_transition_ia_days
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = var.log_transition_glacier_days
      storage_class = "GLACIER"
    }
    expiration {
      days = var.log_retention_days
    }
  }
}

# 로그 전달 서비스만 쓰기 허용 (VPC Flow Logs, ELB 접근 로그)
resource "aws_s3_bucket_policy" "logs" {
  count  = var.create_log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.logs[0].arn, "${aws_s3_bucket.logs[0].arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        Sid       = "FlowLogsWrite"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs[0].arn}/*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id, "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Sid       = "FlowLogsAclCheck"
        Effect    = "Allow"
        Principal = { Service = "delivery.logs.amazonaws.com" }
        Action    = ["s3:GetBucketAcl", "s3:ListBucket"]
        Resource  = aws_s3_bucket.logs[0].arn
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
      {
        # 2022-08 이전 리전(서울 포함)은 리전별 ELB 계정이 로그를 씀
        Sid       = "ElbLogsWriteLegacy"
        Effect    = "Allow"
        Principal = { AWS = data.aws_elb_service_account.this.arn }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs[0].arn}/*/AWSLogs/${local.account_id}/*"
      },
      {
        Sid       = "ElbLogsWrite"
        Effect    = "Allow"
        Principal = { Service = "logdelivery.elasticloadbalancing.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs[0].arn}/*/AWSLogs/${local.account_id}/*"
      },
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.logs]
}

############################################################
# 다음 단계가 읽는 값 (계정 단위 경로)
############################################################
resource "aws_ssm_parameter" "state" {
  name        = "/iac/_account/00-bootstrap/state"
  description = "00-bootstrap: state 버킷 정보"
  type        = "String"
  tier        = "Intelligent-Tiering"
  value = jsonencode({
    bucket     = aws_s3_bucket.state.id
    region     = local.region
    lock_table = var.create_lock_table ? aws_dynamodb_table.lock[0].name : null
  })
  tags = merge(local.tags, { Name = "/iac/_account/00-bootstrap/state" })
}

resource "aws_ssm_parameter" "logs" {
  count       = var.create_log_bucket ? 1 : 0
  name        = "/iac/_account/00-bootstrap/logs"
  description = "00-bootstrap: 로그 버킷 정보"
  type        = "String"
  tier        = "Intelligent-Tiering"
  value = jsonencode({
    bucket     = aws_s3_bucket.logs[0].id
    bucket_arn = aws_s3_bucket.logs[0].arn
  })
  tags = merge(local.tags, { Name = "/iac/_account/00-bootstrap/logs" })
}
