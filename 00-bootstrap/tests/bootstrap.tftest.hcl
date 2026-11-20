# 버킷에 prevent_destroy가 있어서 apply 후 정리(destroy)를 할 수 없으므로 plan으로만 검사합니다.
mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_region" {
    defaults = { name = "ap-northeast-2" }
  }
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
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
    # 중앙 로그 계정을 쓰므로 CloudWatch 로그도 중앙 destination으로
    cloudwatch_logs_destination_arn = "arn:aws:logs:ap-northeast-2:333333333333:destination:central-cwlogs"
  }
  assert {
    condition     = length(module.lock_table) == 1 && length(module.log_bucket) == 0
    error_message = "lock=${length(module.lock_table)} logs=${length(module.log_bucket)}"
  }
}

run "account_security_defaults" {
  command = plan
  assert {
    condition     = module.ebs_encryption_by_default.enabled == true
    error_message = "EBS 기본 암호화가 켜져야 함"
  }
  assert {
    condition     = module.imds_defaults.http_tokens == "required"
    error_message = "IMDSv2 필수여야 함"
  }
  assert {
    condition     = alltrue(values(module.s3_account_public_access_block[0].settings))
    error_message = "계정 S3 퍼블릭 차단 4개 모두 true여야 함: ${jsonencode(module.s3_account_public_access_block[0].settings)}"
  }
  assert {
    condition     = toset(keys(module.parameters.names)) == toset(["state", "logs", "kms"])
    error_message = "파라미터: ${jsonencode(keys(module.parameters.names))}"
  }
}

run "one_cmk_per_resource_by_default" {
  command = plan
  assert {
    # 리소스별 키(ebs, s3)만 만들고, state 버킷·잠금 테이블은 s3 키를 같이 씀
    condition     = jsonencode(local.kms_key_source) == jsonencode({ ebs = "local", s3 = "local", tfstate = "same-as-s3" }) && toset(keys(module.kms_key)) == toset(["ebs", "s3"])
    error_message = "키: ${jsonencode(local.kms_key_source)}"
  }
}

run "separate_tfstate_key_option" {
  command = plan
  variables {
    separate_tfstate_key = true
  }
  assert {
    condition     = toset(keys(module.kms_key)) == toset(["ebs", "s3", "tfstate"]) && local.kms_key_source.tfstate == "local"
    error_message = "tfstate 분리: ${jsonencode(local.kms_key_source)}"
  }
}

run "central_cmk_when_given" {
  command = plan
  variables {
    central_kms_key_arns = {
      s3      = "arn:aws:kms:ap-northeast-2:222222222222:key/11111111-2222-3333-4444-555555555555"
      tfstate = "arn:aws:kms:ap-northeast-2:222222222222:key/66666666-2222-3333-4444-555555555555"
    }
  }
  assert {
    # s3, tfstate는 중앙 키 (옵션을 켜지 않아도 중앙 tfstate 키가 있으면 분리), ebs는 이 계정 키
    condition     = toset(keys(module.kms_key)) == toset(["ebs"]) && local.kms_key_arns.tfstate == "arn:aws:kms:ap-northeast-2:222222222222:key/66666666-2222-3333-4444-555555555555" && local.kms_key_source.tfstate == "central"
    error_message = "중앙 키 사용: ${jsonencode(local.kms_key_source)}"
  }
}

run "reject_alias_as_central_key" {
  command = plan
  variables {
    central_kms_key_arns = { s3 = "arn:aws:kms:ap-northeast-2:222222222222:alias/central-s3" }
  }
  expect_failures = [var.central_kms_key_arns]
}

run "cloudwatch_logs_exported_to_s3" {
  command = plan
  assert {
    condition     = length(module.cwlogs_firehose) == 1 && length(module.cwlogs_account_subscription) == 1 && module.cwlogs_error_log["this"].name == "/aws/kinesisfirehose/iac-cwlogs-to-s3"
    error_message = "CloudWatch Logs → S3 구성이 없음"
  }
}

run "cloudwatch_logs_export_explicitly_off" {
  command = plan
  variables {
    create_log_bucket     = false
    cloudwatch_logs_to_s3 = false
  }
  assert {
    # 내보내지 않으려면 cloudwatch_logs_to_s3 = false로 명시
    condition     = length(module.cwlogs_firehose) == 0 && output.cloudwatch_logs_to_s3 == null
    error_message = "명시적으로 끈 경우 Firehose를 만들면 안 됨"
  }
}

run "reject_cloudwatch_export_without_destination" {
  command = plan
  variables {
    # 켜져 있는데(기본값) 보낼 곳이 없음 → 조용히 꺼지지 않고 plan에서 막힘
    create_log_bucket = false
  }
  expect_failures = [var.cloudwatch_logs_to_s3]
}

run "reject_lifecycle_ia_too_early" {
  command = plan
  variables {
    log_transition_ia_days = 10
  }
  expect_failures = [var.log_transition_ia_days]
}

run "reject_lifecycle_glacier_too_close_to_ia" {
  command = plan
  variables {
    log_transition_ia_days      = 30
    log_transition_glacier_days = 45
  }
  expect_failures = [var.log_transition_glacier_days]
}

run "reject_retention_not_after_glacier" {
  command = plan
  variables {
    log_retention_days = 30
  }
  expect_failures = [var.log_retention_days]
}

run "lifecycle_with_ia_ok" {
  command = plan
  variables {
    log_transition_ia_days      = 30
    log_transition_glacier_days = 90
  }
  assert {
    condition     = length(module.log_lifecycle["this"].rules[0].transitions) == 2
    error_message = "IA + Glacier: ${jsonencode(module.log_lifecycle["this"].rules[0].transitions)}"
  }
}

run "reject_central_key_other_region" {
  command = plan
  variables {
    central_kms_key_arns = { s3 = "arn:aws:kms:us-east-1:222222222222:key/11111111-2222-3333-4444-555555555555" }
  }
  expect_failures = [var.central_kms_key_arns]
}

run "reject_destination_other_region" {
  command = plan
  variables {
    cloudwatch_logs_destination_arn = "arn:aws:logs:us-east-1:333333333333:destination:central-cwlogs"
  }
  expect_failures = [var.cloudwatch_logs_destination_arn]
}

run "cloudwatch_logs_to_central_destination" {
  command = plan
  variables {
    cloudwatch_logs_destination_arn = "arn:aws:logs:ap-northeast-2:333333333333:destination:central-cwlogs"
  }
  assert {
    # 중앙 destination이면 이 계정 Firehose 없이 구독 필터만
    condition     = length(module.cwlogs_firehose) == 0 && length(module.cwlogs_account_subscription) == 1 && output.cloudwatch_logs_to_s3.mode == "central"
    error_message = "중앙 destination: ${jsonencode(output.cloudwatch_logs_to_s3)}"
  }
}

run "log_bucket_lifecycle_default" {
  command = plan
  assert {
    # 기본: 30일 후 Glacier로 바로 (IA 단계 없음), 365일 후 삭제
    condition     = jsonencode(module.log_lifecycle["this"].rules[0].transitions) == jsonencode([{ days = 30, storage_class = "GLACIER" }]) && module.log_lifecycle["this"].rules[0].expiration_days == 365
    error_message = "수명 주기: ${jsonencode(module.log_lifecycle["this"].rules)}"
  }
}

run "elb_log_policy_restricted_to_own_load_balancers" {
  command = plan
  # 정책 JSON에 버킷 ARN이 들어가 plan 시점에 모르므로, 이 테스트에서만 버킷 ARN을 정해 둠
  override_resource {
    target          = module.log_bucket["this"].aws_s3_bucket.protected[0]
    override_during = plan
    values          = { arn = "arn:aws:s3:::iac-logs-111111111111-ap-northeast-2", id = "iac-logs-111111111111-ap-northeast-2", bucket = "iac-logs-111111111111-ap-northeast-2" }
  }
  assert {
    # 예전 방식(리전 ELB 계정 주체)은 없고, 새 방식은 이 계정 로드밸런서로 출처 제한
    condition = (
      !strcontains(module.log_policy["this"].policy, "600734575887") &&
      strcontains(module.log_policy["this"].policy, "arn:aws:elasticloadbalancing:ap-northeast-2:111111111111:loadbalancer/*")
    )
    error_message = "ELB 로그 정책: ${module.log_policy["this"].policy}"
  }
}
