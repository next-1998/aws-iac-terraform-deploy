# 03-compute 단계 루트 검사 (plan만, mock provider). terraform.tfvars 값을 사용합니다.
# 01-network, 02-shared가 남긴 Parameter Store 값은 아래 override_data로 대신합니다.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-northeast-2:111111111111:loadbalancer/app/mock/0123456789abcdef" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-northeast-2:111111111111:targetgroup/mock/0123456789abcdef" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "ap-northeast-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

override_data {
  target = data.aws_ssm_parameter.network["base"]
  values = { insecure_value = "{\"contract_version\":1,\"site\":\"simple\",\"layout_version\":\"v1\",\"vpc_id\":\"vpc-1\",\"vpc_name\":\"hw-iac-dev-an2-vpc-simple-01\",\"name_prefix\":\"hw-iac-dev-an2\",\"azs\":[\"ap-northeast-2a\",\"ap-northeast-2b\"],\"az_short\":{\"ap-northeast-2a\":\"a\",\"ap-northeast-2b\":\"b\"},\"vpc_cidrs\":[\"10.227.0.0/23\"],\"primary_cidr\":\"10.227.0.0/23\",\"extra_routable\":[],\"internal_cidr\":null,\"enable_public\":false,\"resource_tags\":{\"VpcName\":\"simple-vpc\"}}" }
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
  values = { insecure_value = "{\"ids\":{\"ssm\":\"vpce-1\",\"s3\":\"vpce-2\"},\"gateway\":{\"s3\":\"vpce-2\"},\"interface\":[\"ssm\",\"logs\",\"monitoring\"],\"vpce_sg_id\":\"sg-1\"}" }
}
override_data {
  target = data.aws_ssm_parameter.network["dns"]
  values = { insecure_value = "{\"zone_name\":\"simple.example.com\",\"private_zone_id\":\"ZPRIV\",\"public_zone_id\":null,\"parent_zone_id\":\"ZPARENT\"}" }
}
override_data {
  target = data.aws_ssm_parameter.bootstrap_logs[0]
  values = { insecure_value = "{\"bucket\":\"iac-logs-111111111111-ap-northeast-2\",\"bucket_arn\":\"arn:aws:s3:::iac-logs-111111111111-ap-northeast-2\"}" }
}
override_data {
  target = data.aws_ssm_parameter.shared
  values = { insecure_value = "{\"certificate_arn\":\"arn:aws:acm:ap-northeast-2:111111111111:certificate/mock\",\"alarm_topic_arn\":null,\"backup_tag_keys\":{\"daily\":\"Backup-daily\",\"monthly\":\"Backup-monthly\",\"pitr\":\"Backup-pitr\"}}" }
}
override_data {
  target = data.aws_ssm_parameter.bootstrap_kms
  values = { insecure_value = "{\"key_arns\":{\"ebs\":\"arn:aws:kms:ap-northeast-2:111111111111:key/ebs-mock\",\"logs\":\"arn:aws:kms:ap-northeast-2:111111111111:key/logs-mock\",\"s3\":\"arn:aws:kms:ap-northeast-2:111111111111:key/s3-mock\"},\"source\":{}}" }
}

run "reads_network_and_builds_resources" {
  command = plan
  assert {
    # 로그 그룹 암호화 키는 00-bootstrap logs 키
    condition     = module.ec2_common.contract.logs_kms_key_arn == "arn:aws:kms:ap-northeast-2:111111111111:key/logs-mock"
    error_message = "logs 키: ${module.ec2_common.contract.logs_kms_key_arn}"
  }
  assert {
    condition     = local.network.base.vpc_id == "vpc-1" && local.access_log_bucket == "iac-logs-111111111111-ap-northeast-2"
    error_message = "network=${jsonencode(local.network.base)} log=${local.access_log_bucket}"
  }
  assert {
    condition     = keys(module.contract.names) == ["ec2"] && module.contract.names["ec2"] == "/iac/simple/03-compute/ec2"
    error_message = "03-compute 출력 경로가 다름: ${jsonencode(module.contract.names)}"
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

run "reject_placeholder_ami" {
  command = plan
  variables {
    was = { ami = "__AMI__" }
  }
  expect_failures = [var.was]
}

run "ebs_auto_grow" {
  # 루트·데이터 볼륨 자동 증설: 증설 Lambda 생성, 볼륨마다 알람, 늘어난 실제 크기는 유지 (줄이지 않음)
  command = plan
  variables {
    was = {
      ami            = "ami-0123456789abcdef0"
      root_auto_grow = { max_size = 100 }
      ebs_volumes    = [{ device_name = "/dev/sdf", volume_size = 50, mount_point = "/data", auto_grow = { max_size = 200 } }]
    }
  }
  override_data {
    target = data.aws_ssm_parameter.network["endpoints"]
    values = { insecure_value = "{\"ids\":{},\"gateway\":{\"s3\":\"vpce-2\"},\"interface\":[\"ssm\",\"logs\",\"monitoring\",\"ec2\"],\"vpce_sg_id\":\"sg-1\"}" }
  }
  # 데이터 볼륨이 자동으로 60 GiB로 늘어난 상태
  override_data {
    target = module.ec2_was[0].data.aws_ebs_volumes.grow[0]
    values = { ids = ["vol-1"] }
  }
  override_data {
    target = module.ec2_was[0].data.aws_ebs_volume.grow["vol-1"]
    values = { size = 60, tags = { ResourceKey = "ec2_was_data_sdf_vol" } }
  }
  assert {
    condition     = module.ec2_common.ebs_grow == "hw-iac-dev-an2-lbd-ebsgrow-01"
    error_message = "증설 Lambda: ${jsonencode(module.ec2_common.ebs_grow)}"
  }
  assert {
    condition     = toset(module.ec2_was[0].auto_grow.alarms) == toset(["hw-iac-dev-an2-alm-was-ebsgrow-root-01", "hw-iac-dev-an2-alm-was-ebsgrow-sdf-01"])
    error_message = "알람: ${jsonencode(module.ec2_was[0].auto_grow.alarms)}"
  }
  assert {
    condition     = module.ec2_was[0].auto_grow.data_volume_size["/dev/sdf"] == 60 && module.ec2_was[0].auto_grow.root_volume_size == 30
    error_message = "크기: ${jsonencode(module.ec2_was[0].auto_grow)}"
  }
}

run "ebs_auto_grow_off_by_default" {
  command = plan
  assert {
    condition     = module.ec2_common.ebs_grow == null && length(module.ec2_was[0].auto_grow.alarms) == 0
    error_message = "기본은 자동 증설 꺼짐이어야 합니다."
  }
}


run "key_pair_by_name" {
  # 미리 만든 key pair를 이름으로 지정 (WAS만), webide는 key pair 없음
  command = plan
  variables {
    was = { ami = "ami-0123456789abcdef0", key_pair_name = "hw-iac-dev-an2-kp-was-01", autoscale = { enabled = true } }
  }
  override_data {
    target = module.ec2_was[0].data.aws_key_pair.this[0]
    values = { key_name = "hw-iac-dev-an2-kp-was-01" }
  }
  assert {
    condition     = module.ec2_was[0].key_pair == "hw-iac-dev-an2-kp-was-01" && module.ec2_webide[0].key_pair == null
    error_message = "key pair: ${jsonencode([module.ec2_was[0].key_pair, module.ec2_webide[0].key_pair])}"
  }
}

run "reject_unknown_backup_plan" {
  command = plan
  variables {
    was = { ami = "ami-0123456789abcdef0", backup_plans = ["dayly"] }
  }
  expect_failures = [output.backup_plan_check]
}
