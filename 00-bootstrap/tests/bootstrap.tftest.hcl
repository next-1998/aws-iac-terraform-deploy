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
    condition     = module.state_bucket.bucket == "iac-tfstate-111111111111-ap-northeast-2"
    error_message = "state bucket: ${module.state_bucket.bucket}"
  }
  assert {
    condition     = module.log_bucket["this"].bucket == "iac-logs-111111111111-ap-northeast-2"
    error_message = "log bucket: ${module.log_bucket["this"].bucket}"
  }
  assert {
    condition     = length(module.lock_table) == 0
    error_message = "DynamoDB는 기본값에서 만들지 않아야 함"
  }
  assert {
    condition     = one([for r in module.log_lifecycle["this"].rules : r.expiration_days]) == 365
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
    condition     = length(module.lock_table) == 1 && length(module.log_bucket) == 0
    error_message = "lock=${length(module.lock_table)} logs=${length(module.log_bucket)}"
  }
}
