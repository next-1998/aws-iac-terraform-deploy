# 02-shared 단계 루트 검사 (plan만, mock provider). terraform.tfvars 값을 사용합니다.
mock_provider "aws" {}

override_data {
  target = data.aws_ssm_parameter.network["base"]
  values = { insecure_value = "{\"contract_version\":1,\"site\":\"simple\",\"layout_version\":\"v1\",\"vpc_id\":\"vpc-1\",\"vpc_name\":\"simple-vpc\",\"azs\":[\"ap-northeast-2a\",\"ap-northeast-2b\"],\"az_short\":{\"ap-northeast-2a\":\"a\",\"ap-northeast-2b\":\"b\"},\"vpc_cidrs\":[\"10.227.0.0/23\"],\"primary_cidr\":\"10.227.0.0/23\",\"extra_routable\":[],\"internal_cidr\":null,\"enable_public\":false,\"resource_tags\":{\"VpcName\":\"simple-vpc\"}}" }
}

override_data {
  target = data.aws_ssm_parameter.network["dns"]
  values = { insecure_value = "{\"zone_name\":\"simple.example.com\",\"private_zone_id\":\"ZPRIV\",\"public_zone_id\":null,\"parent_zone_id\":\"ZPARENT\"}" }
}

override_resource {
  target          = module.shared_common.module.acm[0].aws_acm_certificate.this
  override_during = plan
  values = {
    arn = "arn:aws:acm:ap-northeast-2:111111111111:certificate/mock"
    domain_validation_options = [
      { domain_name = "simple.example.com", resource_record_name = "_x.simple.example.com.", resource_record_type = "CNAME", resource_record_value = "_y.acm-validations.aws." },
      { domain_name = "*.simple.example.com", resource_record_name = "_x.simple.example.com.", resource_record_type = "CNAME", resource_record_value = "_y.acm-validations.aws." },
    ]
  }
}

run "writes_shared_bundle" {
  # public 존이 없으면 인증서 검증 레코드는 상위 존(parent)에 들어감
  command = plan
  assert {
    condition     = module.contract.names["shared"] == "/iac/simple/02-shared/shared"
    error_message = "경로: ${jsonencode(module.contract.names)}"
  }
  assert {
    condition     = alltrue([for k, z in module.shared_common.validation_records : z == "ZPARENT"])
    error_message = "검증 레코드 존: ${jsonencode(module.shared_common.validation_records)}"
  }
}
