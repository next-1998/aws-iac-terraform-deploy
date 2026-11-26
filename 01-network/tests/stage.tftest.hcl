# 01-network 단계 루트 검사 (plan만, mock provider). terraform.tfvars 값을 사용합니다.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c", "ap-northeast-2d"] }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "{\"bucket\":\"iac-logs-111111111111-ap-northeast-2\",\"bucket_arn\":\"arn:aws:s3:::iac-logs-111111111111-ap-northeast-2\"}" }
  }
}

override_data {
  target = data.aws_ssm_parameter.bootstrap_naming
  values = { insecure_value = "{\"prefix\":\"hw-iac-dev-an2\"}" }
}

run "writes_contract_bundles" {
  command = plan
  assert {
    condition     = toset(keys(module.contract.names)) == toset(["base", "subnets", "routing", "endpoints", "dns"])
    error_message = "묶음: ${jsonencode(keys(module.contract.names))}"
  }
  assert {
    condition     = module.contract.names["base"] == "/iac/simple/01-network/base" && module.contract.tiers["base"] == "Intelligent-Tiering"
    error_message = "경로: ${module.contract.names["base"]}"
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

run "names_follow_central_prefix" {
  # 이름: <접두어>-<유형>-<이름>-<순번>[-<AZ>] (접두어는 00-bootstrap naming)
  command = plan
  assert {
    condition     = module.network_base.contract.base.vpc_name == "hw-iac-dev-an2-vpc-simple-01" && module.network_base.contract.base.name_prefix == "hw-iac-dev-an2"
    error_message = "VPC 이름: ${module.network_base.contract.base.vpc_name}"
  }
}
