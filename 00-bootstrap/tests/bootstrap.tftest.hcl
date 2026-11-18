# 버킷에 prevent_destroy가 있어서 apply 후 정리(destroy)를 할 수 없으므로 plan으로만 검사합니다.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_region" {
    defaults = { name = "ap-northeast-2" }
  }
  mock_data "aws_elb_service_account" {
    defaults = { arn = "arn:aws:iam::600734575887:root" }
  }
}

run "defaults" {
  command = plan
  assert {
    condition     = aws_s3_bucket.state.bucket == "iac-tfstate-111111111111-ap-northeast-2"
    error_message = "state bucket: ${aws_s3_bucket.state.bucket}"
  }
  assert {
    condition     = aws_s3_bucket.logs[0].bucket == "iac-logs-111111111111-ap-northeast-2"
    error_message = "log bucket: ${aws_s3_bucket.logs[0].bucket}"
  }
  assert {
    condition     = length(aws_dynamodb_table.lock) == 0
    error_message = "DynamoDB는 기본값에서 만들지 않아야 함"
  }
  assert {
    condition     = one([for r in aws_s3_bucket_lifecycle_configuration.logs[0].rule : r.expiration[0].days]) == 365
    error_message = "로그 보관 기간 기본값은 365일"
  }
}

run "with_lock_table_and_central_logs" {
  command = plan
  variables {
    create_lock_table = true
    create_log_bucket = false
  }
  assert {
    condition     = length(aws_dynamodb_table.lock) == 1 && length(aws_s3_bucket.logs) == 0
    error_message = "lock=${length(aws_dynamodb_table.lock)} logs=${length(aws_s3_bucket.logs)}"
  }
}
