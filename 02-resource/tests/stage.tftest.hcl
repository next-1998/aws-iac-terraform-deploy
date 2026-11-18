# 02-resource 단계 루트 검사 (plan만, mock provider). terraform.tfvars 값을 사용합니다.
# 01-network가 남긴 Parameter Store 값은 아래 override_data로 대신합니다.
mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-northeast-2:111111111111:loadbalancer/app/mock/0123456789abcdef" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-northeast-2:111111111111:targetgroup/mock/0123456789abcdef" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

override_data {
  target = data.aws_ssm_parameter.network["base"]
  values = { insecure_value = "{\"contract_version\":1,\"site\":\"simple\",\"layout_version\":\"v1\",\"vpc_id\":\"vpc-1\",\"vpc_name\":\"simple-vpc\",\"azs\":[\"ap-northeast-2a\",\"ap-northeast-2b\"],\"az_short\":{\"ap-northeast-2a\":\"a\",\"ap-northeast-2b\":\"b\"},\"vpc_cidrs\":[\"10.227.0.0/23\"],\"primary_cidr\":\"10.227.0.0/23\",\"extra_routable\":[],\"internal_cidr\":null,\"enable_public\":false,\"resource_tags\":{\"VpcName\":\"simple-vpc\"}}" }
}
override_data {
  target = data.aws_ssm_parameter.network["subnets"]
  values = { insecure_value = "{\"ids\":{\"edge\":{\"ap-northeast-2a\":\"subnet-ea\",\"ap-northeast-2b\":\"subnet-eb\"},\"vpce\":{\"ap-northeast-2a\":\"subnet-va\",\"ap-northeast-2b\":\"subnet-vb\"},\"transit\":{\"ap-northeast-2a\":\"subnet-ta\",\"ap-northeast-2b\":\"subnet-tb\"},\"public\":{}},\"cidrs\":{\"edge\":{\"ap-northeast-2a\":\"10.227.0.0/26\",\"ap-northeast-2b\":\"10.227.1.0/26\"},\"vpce\":{\"ap-northeast-2a\":\"10.227.0.64/27\",\"ap-northeast-2b\":\"10.227.1.64/27\"},\"transit\":{\"ap-northeast-2a\":\"10.227.0.96/28\",\"ap-northeast-2b\":\"10.227.1.96/28\"},\"ec2\":{\"ap-northeast-2a\":\"10.227.0.128/26\",\"ap-northeast-2b\":\"10.227.1.128/26\"},\"db\":{\"ap-northeast-2a\":\"10.227.0.192/27\",\"ap-northeast-2b\":\"10.227.1.192/27\"},\"public\":{\"ap-northeast-2a\":\"10.227.0.224/27\",\"ap-northeast-2b\":\"10.227.1.224/27\"}},\"eks_placement\":null,\"eks_cidrs\":{},\"manual\":{}}" }
}
override_data {
  target = data.aws_ssm_parameter.network["routing"]
  values = { insecure_value = "{\"has_public\":false,\"has_tgw\":true,\"has_private_nat\":false,\"igw_id\":null,\"public_nat_ids\":{},\"private_nat_ids\":{},\"nat_public_ips\":[],\"tgw_id\":\"tgw-1\",\"corp_cidrs\":[\"10.0.0.0/8\"],\"peerings\":{},\"prefix_list_ids\":{\"access_ctl\":\"pl-1\"}}" }
}
override_data {
  target = data.aws_ssm_parameter.network["endpoints"]
  values = { insecure_value = "{\"ids\":{\"ssm\":\"vpce-1\",\"s3\":\"vpce-2\"},\"gateway\":{\"s3\":\"vpce-2\"},\"interface\":[\"ssm\"],\"vpce_sg_id\":\"sg-1\"}" }
}
override_data {
  target = data.aws_ssm_parameter.network["dns"]
  values = { insecure_value = "{\"zone_name\":\"simple.example.com\",\"private_zone_id\":\"ZPRIV\",\"public_zone_id\":null,\"parent_zone_id\":\"ZPARENT\"}" }
}
override_data {
  target = data.aws_ssm_parameter.bootstrap_logs[0]
  values = { insecure_value = "{\"bucket\":\"iac-logs-111111111111-ap-northeast-2\",\"bucket_arn\":\"arn:aws:s3:::iac-logs-111111111111-ap-northeast-2\"}" }
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

run "reads_network_and_builds_resources" {
  command = plan
  assert {
    condition     = local.network.base.vpc_id == "vpc-1" && local.access_log_bucket == "iac-logs-111111111111-ap-northeast-2"
    error_message = "network=${jsonencode(local.network.base)} log=${local.access_log_bucket}"
  }
  assert {
    condition     = toset(keys(aws_ssm_parameter.contract)) == toset(["ec2", "shared"]) && aws_ssm_parameter.contract["ec2"].name == "/iac/simple/02-resource/ec2"
    error_message = "02-resource 출력 경로가 다름"
  }
}

run "central_log_bucket_for_alb" {
  command = plan
  variables {
    central_log_bucket_arn = "arn:aws:s3:::central-logs"
  }
  assert {
    condition     = local.access_log_bucket == "central-logs"
    error_message = "log=${local.access_log_bucket}"
  }
}
