# 01-network 단계 루트 검사 (plan만, mock provider). terraform.tfvars 값을 사용합니다.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c", "ap-northeast-2d"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "{\"bucket\":\"iac-logs-111111111111-ap-northeast-2\",\"bucket_arn\":\"arn:aws:s3:::iac-logs-111111111111-ap-northeast-2\"}" }
  }
}

run "writes_contract_bundles" {
  command = plan
  assert {
    condition     = toset(keys(aws_ssm_parameter.contract)) == toset(["base", "subnets", "routing", "endpoints", "dns"])
    error_message = "묶음: ${jsonencode(keys(aws_ssm_parameter.contract))}"
  }
  assert {
    condition     = aws_ssm_parameter.contract["base"].name == "/iac/simple/01-network/base" && aws_ssm_parameter.contract["base"].tier == "Intelligent-Tiering"
    error_message = "경로: ${aws_ssm_parameter.contract["base"].name}"
  }
}

run "uses_bootstrap_log_bucket_by_default" {
  command = plan
  assert {
    condition     = local.log_bucket_arn == "arn:aws:s3:::iac-logs-111111111111-ap-northeast-2"
    error_message = "log bucket: ${local.log_bucket_arn}"
  }
}

run "uses_central_log_bucket_when_set" {
  command = plan
  variables {
    central_log_bucket_arn = "arn:aws:s3:::central-logs"
  }
  assert {
    condition     = local.log_bucket_arn == "arn:aws:s3:::central-logs" && length(data.aws_ssm_parameter.bootstrap_logs) == 0
    error_message = "central log bucket not used: ${local.log_bucket_arn}"
  }
}
