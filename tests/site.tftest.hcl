# 조합 코드 테스트 (mock provider, AWS 접속 없음)
# 실행: terraform -chdir=tests init && terraform -chdir=tests test

mock_provider "aws" {
  # 형식 검사를 하는 ARN 값은 실제 형식으로 지정
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-northeast-2:111111111111:loadbalancer/app/mock/0123456789abcdef" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-northeast-2:111111111111:targetgroup/mock/0123456789abcdef" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/mock" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c", "ap-northeast-2d"] }
  }
}

############################################################
# 네트워크 유형 1: routable(/24) + internal, AZ 기본값 2개
############################################################
run "hybrid_layout" {
  command = apply
  assert {
    condition     = output.network_type == "hybrid" && output.has_private_nat
    error_message = "type=${output.network_type} private_nat=${output.has_private_nat}"
  }
  assert {
    condition     = output.edge == { "ap-northeast-2a" = "10.227.0.0/27", "ap-northeast-2b" = "10.227.0.32/27" }
    error_message = "edge: ${jsonencode(output.edge)}"
  }
  assert {
    condition     = output.transit == { "ap-northeast-2a" = "10.227.0.128/28", "ap-northeast-2b" = "10.227.0.144/28" }
    error_message = "transit: ${jsonencode(output.transit)}"
  }
  assert {
    condition     = output.ec2_subnets == { "ap-northeast-2a" = "100.64.0.0/25", "ap-northeast-2b" = "100.64.0.128/25" }
    error_message = "ec2: ${jsonencode(output.ec2_subnets)}"
  }
  assert {
    condition     = length(output.overlaps) == 0
    error_message = "overlap: ${jsonencode(output.overlaps)}"
  }
}

############################################################
# AZ 2 → 3, 4: 기존 a, b 서브넷은 그대로
############################################################
run "grow_to_3_azs" {
  command = apply
  variables {
    az_count = 3
  }
  assert {
    condition = alltrue([for az, c in run.hybrid_layout.edge : output.edge[az] == c]) && alltrue([
      for az, c in run.hybrid_layout.ec2_subnets : output.ec2_subnets[az] == c
    ])
    error_message = "a, b 서브넷이 바뀜: edge=${jsonencode(output.edge)} ec2=${jsonencode(output.ec2_subnets)}"
  }
  assert {
    condition     = output.edge["ap-northeast-2c"] == "10.227.0.64/27" && output.transit["ap-northeast-2c"] == "10.227.0.160/28" && output.ec2_subnets["ap-northeast-2c"] == "100.64.1.0/25"
    error_message = "c: ${jsonencode([output.edge, output.transit, output.ec2_subnets])}"
  }
  assert {
    condition     = length(output.overlaps) == 0
    error_message = "overlap: ${jsonencode(output.overlaps)}"
  }
}

run "grow_to_4_azs" {
  command = apply
  variables {
    az_count = 4
  }
  assert {
    condition     = output.edge["ap-northeast-2d"] == "10.227.0.96/27" && output.transit["ap-northeast-2d"] == "10.227.0.176/28" && output.ec2_subnets["ap-northeast-2d"] == "100.64.1.128/25"
    error_message = "d: ${jsonencode([output.edge, output.transit, output.ec2_subnets])}"
  }
  assert {
    condition     = length(output.overlaps) == 0
    error_message = "overlap: ${jsonencode(output.overlaps)}"
  }
}

############################################################
# 네트워크 유형 2: routable 단독 (/23)
############################################################
run "routable_only_layout" {
  command = apply
  variables {
    vpc_cidrs = [{ cidr = "10.227.0.0/23", role = "routable" }]
  }
  assert {
    condition     = output.network_type == "routable" && !output.has_private_nat && length(output.private_nat_ids) == 0
    error_message = "type=${output.network_type} private_nat=${jsonencode(output.private_nat_ids)}"
  }
  assert {
    condition     = output.ec2_subnets == { "ap-northeast-2a" = "10.227.1.0/28", "ap-northeast-2b" = "10.227.1.16/28" }
    error_message = "ec2: ${jsonencode(output.ec2_subnets)}"
  }
  assert {
    condition     = length(output.overlaps) == 0
    error_message = "overlap: ${jsonencode(output.overlaps)}"
  }
}

run "no_internet" {
  command = apply
  variables {
    enable_internet = false
  }
  assert {
    condition     = length(output.public_nat_ids) == 0
    error_message = "public NAT가 생성됨: ${jsonencode(output.public_nat_ids)}"
  }
}

############################################################
# NAT: 기본값 AZ별, 옵션으로 1개
############################################################
run "nat_per_az_default" {
  command = apply
  variables {
    az_count = 3
  }
  assert {
    condition     = length(distinct(values(output.public_nat_ids))) == 3 && length(distinct(values(output.private_nat_ids))) == 3
    error_message = "public=${jsonencode(output.public_nat_ids)} private=${jsonencode(output.private_nat_ids)}"
  }
  assert {
    condition     = length(distinct(values(output.ec2_rts))) == 3
    error_message = "ec2 라우트 테이블이 AZ별이 아님: ${jsonencode(output.ec2_rts)}"
  }
}

run "nat_single" {
  command = apply
  variables {
    az_count   = 3
    nat_per_az = false
  }
  assert {
    condition     = length(distinct(values(output.public_nat_ids))) == 1 && length(distinct(values(output.private_nat_ids))) == 1
    error_message = "public=${jsonencode(output.public_nat_ids)} private=${jsonencode(output.private_nat_ids)}"
  }
}

############################################################
# 공통 SG / 개별 SG
############################################################
run "common_sg_has_no_rules_by_default" {
  command = apply
  assert {
    condition     = length(output.common_sg_rules) == 0
    error_message = "공통 SG에 기본 규칙이 있음: ${jsonencode(output.common_sg_rules)}"
  }
  assert {
    condition     = length(output.was_sgs) == 2 && contains(output.was_sgs, output.common_sg_id)
    error_message = "WAS SG: ${jsonencode(output.was_sgs)} (공통 ${output.common_sg_id} + 개별)"
  }
  assert {
    condition     = length(output.webide_sgs) == 2 && contains(output.webide_sgs, output.common_sg_id)
    error_message = "Web IDE SG: ${jsonencode(output.webide_sgs)}"
  }
}

run "common_sg_rules_added_per_site" {
  command = apply
  variables {
    common_sg_ingress = [{ from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["10.185.66.0/24"], description = "server access control" }]
  }
  assert {
    condition     = length(output.common_sg_rules) == 1
    error_message = "공통 SG 규칙: ${jsonencode(output.common_sg_rules)}"
  }
}

############################################################
# endpoint: SSM 옵션, skip
############################################################
run "ssm_on" {
  command = apply
  assert {
    condition     = toset(output.endpoints) == toset(["ssm", "ssmmessages", "ec2messages", "s3"])
    error_message = "endpoints: ${jsonencode(output.endpoints)}"
  }
}

run "ssm_off" {
  command = apply
  variables {
    enable_ssm      = false
    extra_endpoints = []
  }
  assert {
    condition     = length(output.endpoints) == 0
    error_message = "SSM을 껐는데 endpoint가 생성됨: ${jsonencode(output.endpoints)}"
  }
}

run "skip_when_other_stack_owns" {
  command = apply
  override_data {
    target = module.ec2_common.module.vpce[0].data.aws_resourcegroupstaggingapi_resources.existing["ssm"]
    values = {
      resource_tag_mapping_list = [{
        resource_arn       = "arn:aws:ec2:ap-northeast-2:111111111111:vpc-endpoint/vpce-0abc"
        tags               = { Stack = "simple/eks-common", ResourceKey = "ssm_vpce" }
        compliance_details = []
      }]
    }
  }
  assert {
    condition     = toset(output.endpoints_skipped) == toset(["ssm"]) && !contains(output.endpoints, "ssm")
    error_message = "skip failed: skipped=${jsonencode(output.endpoints_skipped)} created=${jsonencode(output.endpoints)}"
  }
}

run "no_skip_for_own_resource" {
  command = apply
  override_data {
    target = module.ec2_common.module.vpce[0].data.aws_resourcegroupstaggingapi_resources.existing["ssm"]
    values = {
      resource_tag_mapping_list = [{
        resource_arn       = "arn:aws:ec2:ap-northeast-2:111111111111:vpc-endpoint/vpce-0abc"
        tags               = { Stack = "simple/ec2-common", ResourceKey = "ssm_vpce" }
        compliance_details = []
      }]
    }
  }
  assert {
    condition     = length(output.endpoints_skipped) == 0 && contains(output.endpoints, "ssm")
    error_message = "own resource caused skip"
  }
}

############################################################
# ALB: 용도별 선택
############################################################
run "alb_per_purpose" {
  command = apply
  assert {
    condition     = output.was_alb && output.webide_alb
    error_message = "WAS에는 ALB가 있고 Web IDE에는 없어야 함"
  }
}

############################################################
# 잘못된 입력은 plan에서 막힘 (network-base 단독 실행)
############################################################
run "reject_wrong_internal_cidr" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site     = "simple"
    vpc_name = "simple-vpc"
    vpc_cidrs = [
      { cidr = "10.227.0.0/24", role = "routable" },
      { cidr = "100.0.0.0/16", role = "internal" },
    ]
  }
  expect_failures = [var.vpc_cidrs]
}

run "reject_small_routable_hybrid" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site     = "simple"
    vpc_name = "simple-vpc"
    vpc_cidrs = [
      { cidr = "10.227.0.0/25", role = "routable" },
      { cidr = "100.64.0.0/16", role = "internal" },
    ]
  }
  expect_failures = [var.vpc_cidrs]
}

run "reject_small_routable_only" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site      = "simple"
    vpc_name  = "simple-vpc"
    vpc_cidrs = [{ cidr = "10.227.0.0/24", role = "routable" }]
  }
  expect_failures = [var.vpc_cidrs]
}

run "reject_internal_first" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site     = "simple"
    vpc_name = "simple-vpc"
    vpc_cidrs = [
      { cidr = "100.64.0.0/16", role = "internal" },
      { cidr = "10.227.0.0/24", role = "routable" },
    ]
  }
  expect_failures = [var.vpc_cidrs]
}

run "reject_5_azs" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site      = "simple"
    vpc_name  = "simple-vpc"
    vpc_cidrs = [{ cidr = "10.227.0.0/23", role = "routable" }]
    az_count  = 5
  }
  expect_failures = [var.az_count]
}

run "reject_korean_sg_description" {
  command = plan
  module { source = "../deployment/ec2-common" }
  variables {
    base              = run.hybrid_layout.base_contract
    common_sg_ingress = [{ from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["10.185.66.0/24"], description = "서버 접근제어" }]
  }
  expect_failures = [var.common_sg_ingress]
}

############################################################
# AZ: 리전 AZ 목록에서 앞에서부터, 1개 허용
############################################################
run "az_from_region_list" {
  command = apply
  override_data {
    target = module.network_base.data.aws_availability_zones.this
    values = { names = ["ap-northeast-1d", "ap-northeast-1a", "ap-northeast-1c"] } # 도쿄처럼 b가 없는 리전
  }
  assert {
    condition     = jsonencode(output.azs) == jsonencode(["ap-northeast-1a", "ap-northeast-1c"])
    error_message = "azs: ${jsonencode(output.azs)} (이름순 앞에서부터 2개여야 함)"
  }
}

run "az_count_1" {
  command = apply
  variables {
    az_count       = 1
    was_enable_alb = false
  }
  assert {
    condition     = length(output.azs) == 1 && length(output.edge) == 1 && length(output.ec2_subnets) == 1
    error_message = "azs=${jsonencode(output.azs)} edge=${jsonencode(output.edge)}"
  }
  assert {
    condition     = length(output.overlaps) == 0
    error_message = "overlap: ${jsonencode(output.overlaps)}"
  }
}

run "reject_az_count_over_region" {
  command = plan
  module { source = "../deployment/network-base" }
  override_data {
    target = data.aws_availability_zones.this
    values = { names = ["ap-northeast-2a", "ap-northeast-2c"] }
  }
  variables {
    site      = "simple"
    vpc_name  = "simple-vpc"
    vpc_cidrs = [{ cidr = "10.227.0.0/23", role = "routable" }]
    az_count  = 3
  }
  expect_failures = [terraform_data.checks]
}

run "reject_alb_with_1_az" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common     = run.az_count_1.ec2_common_contract
    ami        = "ami-0123456789abcdef0"
    enable_alb = true
  }
  expect_failures = [terraform_data.alb_checks]
}
