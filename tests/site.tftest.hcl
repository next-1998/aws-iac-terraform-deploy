# 조합 코드 통합 테스트 (mock provider, AWS 접속 없음)
# 실행: terraform -chdir=tests init && terraform -chdir=tests test
#
# public NAT EIP에는 prevent_destroy가 있어 apply 후 정리를 할 수 없으므로,
# enable_public = true 검사는 plan으로만 합니다.

mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-northeast-2:111111111111:loadbalancer/app/mock/0123456789abcdef" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-northeast-2:111111111111:targetgroup/mock/0123456789abcdef" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111111111111:role/mock" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:ap-northeast-2:111111111111:function:mock" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["ap-northeast-2a", "ap-northeast-2b", "ap-northeast-2c", "ap-northeast-2d"] }
  }
}


############################################################
# v1 배치: 받은 대역 /23, AZ 2개 → AZ 블록 /24
############################################################
run "layout_v1_2az" {
  command = apply
  assert {
    condition = jsonencode(output.cidrs) == jsonencode({
      edge    = { "ap-northeast-2a" = "10.227.0.0/26", "ap-northeast-2b" = "10.227.1.0/26" }
      vpce    = { "ap-northeast-2a" = "10.227.0.64/27", "ap-northeast-2b" = "10.227.1.64/27" }
      transit = { "ap-northeast-2a" = "10.227.0.96/28", "ap-northeast-2b" = "10.227.1.96/28" }
      ec2     = { "ap-northeast-2a" = "10.227.0.128/26", "ap-northeast-2b" = "10.227.1.128/26" }
      db      = { "ap-northeast-2a" = "10.227.0.192/27", "ap-northeast-2b" = "10.227.1.192/27" }
      public  = { "ap-northeast-2a" = "10.227.0.224/27", "ap-northeast-2b" = "10.227.1.224/27" }
    })
    error_message = "cidrs: ${jsonencode(output.cidrs)}"
  }
  assert {
    condition     = length(output.overlaps) == 0
    error_message = "overlap: ${jsonencode(output.overlaps)}"
  }
  assert {
    condition     = jsonencode(output.ec2_subnets) == jsonencode(output.cidrs.ec2)
    error_message = "ec2-common 서브넷이 01-network 계산값과 다름: ${jsonencode(output.ec2_subnets)}"
  }
  assert {
    condition     = jsonencode(output.sizing.per_az["ap-northeast-2a"].spare) == jsonencode(["10.227.0.112/28"])
    error_message = "spare: ${jsonencode(output.sizing.per_az["ap-northeast-2a"].spare)}"
  }
}

run "public_off_by_default" {
  command = apply
  assert {
    condition     = length(output.base_subnet_ids.public) == 0 && length(output.public_nat_ids) == 0
    error_message = "public 기본값 꺼짐이어야 함: subnets=${jsonencode(output.base_subnet_ids)} nat=${jsonencode(output.public_nat_ids)}"
  }
  assert {
    condition     = output.zone.public_zone_id == null && output.zone.private_zone_id != null
    error_message = "public을 끄면 private 존만: ${jsonencode(output.zone)}"
  }
}

run "public_on_plan" {
  command = plan
  variables {
    enable_public = true
  }
  assert {
    condition     = length(output.base_subnet_ids.public) == 2 && length(keys(output.public_nat_ids)) == 2
    error_message = "public 서브넷과 NAT가 AZ마다 있어야 함"
  }
}

############################################################
# AZ 증설 (2 → 3 → 4), 1개
############################################################
run "grow_to_3_azs" {
  command = apply
  variables {
    vpc_cidrs = [{ cidr = "10.227.0.0/22", role = "routable" }]
    az_count  = 3
  }
  assert {
    condition     = output.cidrs.ec2["ap-northeast-2c"] == "10.227.2.128/26" && output.sizing.az_growth_reserve == "10.227.3.0/24"
    error_message = "c=${output.cidrs.ec2["ap-northeast-2c"]} reserve=${output.sizing.az_growth_reserve}"
  }
  assert {
    condition     = length(output.overlaps) == 0
    error_message = "overlap: ${jsonencode(output.overlaps)}"
  }
}

run "az_from_region_list" {
  command = apply
  override_data {
    target = module.network_base.data.aws_availability_zones.this
    values = { names = ["ap-northeast-1d", "ap-northeast-1a", "ap-northeast-1c"] } # 도쿄처럼 b가 없는 리전
  }
  assert {
    condition     = jsonencode(output.azs) == jsonencode(["ap-northeast-1a", "ap-northeast-1c"])
    error_message = "azs: ${jsonencode(output.azs)}"
  }
}

run "az_count_1" {
  command = apply
  variables {
    vpc_cidrs      = [{ cidr = "10.227.0.0/24", role = "routable" }]
    az_count       = 1
    was_enable_alb = false
  }
  assert {
    condition     = length(output.azs) == 1 && output.cidrs.ec2["ap-northeast-2a"] == "10.227.0.128/26"
    error_message = "azs=${jsonencode(output.azs)} ec2=${jsonencode(output.cidrs.ec2)}"
  }
}

############################################################
# EKS 배치
############################################################
run "eks_routable" {
  command = apply
  variables {
    vpc_cidrs     = [{ cidr = "10.227.0.0/21", role = "routable" }]
    eks_placement = "routable"
  }
  assert {
    condition     = jsonencode(output.eks_cidrs) == jsonencode({ "ap-northeast-2a" = "10.227.2.0/23", "ap-northeast-2b" = "10.227.6.0/23" })
    error_message = "eks: ${jsonencode(output.eks_cidrs)}"
  }
  assert {
    condition     = jsonencode(output.sizing.per_az["ap-northeast-2a"].spare) == jsonencode(["10.227.0.112/28", "10.227.1.0/24"])
    error_message = "spare: ${jsonencode(output.sizing.per_az["ap-northeast-2a"].spare)}"
  }
  assert {
    condition     = length(output.overlaps) == 0
    error_message = "overlap: ${jsonencode(output.overlaps)}"
  }
}

run "eks_internal" {
  command = apply
  variables {
    eks_placement = "internal"
  }
  assert {
    condition     = jsonencode(output.eks_cidrs) == jsonencode({ "ap-northeast-2a" = "100.64.0.0/17", "ap-northeast-2b" = "100.64.128.0/17" })
    error_message = "eks: ${jsonencode(output.eks_cidrs)}"
  }
  assert {
    condition     = contains(output.vpc_cidrs, "100.64.0.0/16") && length(distinct(values(output.private_nat_ids))) == 2
    error_message = "internal 대역 자동 추가, AZ별 private NAT: cidrs=${jsonencode(output.vpc_cidrs)} nat=${jsonencode(output.private_nat_ids)}"
  }
}

run "nat_single" {
  command = apply
  variables {
    eks_placement = "internal"
    nat_per_az    = false
  }
  assert {
    condition     = length(distinct(values(output.private_nat_ids))) == 1 && length(keys(output.private_nat_ids)) == 2
    error_message = "private NAT 1개를 두 AZ가 같이 써야 함: ${jsonencode(output.private_nat_ids)}"
  }
}

############################################################
# 수동 서브넷
############################################################
run "manual_subnet_in_spare" {
  command = apply
  variables {
    manual_subnets = [{ name = "batch", az = "ap-northeast-2a", cidr = "10.227.0.112/28", purpose = "ec2" }]
  }
  assert {
    condition     = output.ec2_subnets["batch"] == "10.227.0.112/28" && length(output.overlaps) == 0
    error_message = "ec2 subnets: ${jsonencode(output.ec2_subnets)}"
  }
}

############################################################
# 보안: 공통 SG, prefix list, 기본 SG 잠금
############################################################
run "common_sg_and_prefix_list" {
  command = apply
  variables {
    common_sg_ingress = [{ from_port = 22, to_port = 22, protocol = "tcp", prefix_lists = ["access_ctl"], description = "server access control" }]
  }
  assert {
    condition     = length(output.common_sg_rules) == 1 && contains(one(output.common_sg_rules).prefix_list_ids, output.prefix_list_ids["access_ctl"])
    error_message = "공통 SG 규칙: ${jsonencode(output.common_sg_rules)}"
  }
  assert {
    condition     = length(output.was_sgs) == 2 && contains(output.was_sgs, output.common_sg_id)
    error_message = "WAS SG: ${jsonencode(output.was_sgs)}"
  }
}

run "default_sg_locked" {
  command = apply
  assert {
    condition     = length(module.network_base.default_security_group.ingress) == 0 && length(module.network_base.default_security_group.egress) == 0
    error_message = "기본 SG에 규칙이 남아 있음"
  }
}

############################################################
# VPC endpoint
############################################################
run "endpoints_created" {
  command = apply
  assert {
    condition     = toset(output.endpoint_ids) == toset(["ssm", "ssmmessages", "ec2messages", "s3"])
    error_message = "endpoints: ${jsonencode(output.endpoint_ids)}"
  }
}

run "endpoint_skip_existing" {
  command = apply
  override_data {
    target = module.network_base.module.vpce[0].data.aws_resourcegroupstaggingapi_resources.existing["ssm"]
    values = {
      resource_tag_mapping_list = [{
        resource_arn       = "arn:aws:ec2:ap-northeast-2:111111111111:vpc-endpoint/vpce-0abc"
        tags               = { Stack = "simple/other", ResourceKey = "ssm_vpce" }
        compliance_details = []
      }]
    }
  }
  assert {
    condition     = contains(output.endpoint_ids, "ssm") && output.network_contract.endpoints.ids["ssm"] == "vpce-0abc"
    error_message = "skip된 endpoint의 기존 ID가 contract에 있어야 함: ${jsonencode(output.network_contract.endpoints.ids)}"
  }
}

############################################################
# ALB: 용도별 선택, 외부용은 public 필요
############################################################
run "alb_per_purpose" {
  command = apply
  assert {
    condition     = output.was_alb && output.webide_alb
    error_message = "WAS에는 ALB가 있고 Web IDE에는 없어야 함"
  }
}

run "reject_internet_alb_without_public" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common       = run.layout_v1_2az.ec2_common_contract
    ami          = "ami-0123456789abcdef0"
    enable_alb   = true
    alb_internal = false
  }
  expect_failures = [terraform_data.alb_checks]
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

run "reject_korean_sg_description" {
  command = plan
  module { source = "../deployment/ec2-common" }
  variables {
    network           = run.layout_v1_2az.network_contract
    common_sg_ingress = [{ from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["10.185.66.0/24"], description = "서버 접근제어" }]
  }
  expect_failures = [var.common_sg_ingress]
}

############################################################
# 잘못된 입력은 plan에서 막힘 (network-base 단독 실행)
############################################################
run "reject_small_routable" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site      = "simple"
    vpc_name  = "simple-vpc"
    vpc_cidrs = [{ cidr = "10.227.0.0/24", role = "routable" }] # AZ 2개면 /23 필요
  }
  expect_failures = [terraform_data.checks]
}

run "reject_eks_routable_too_small" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site          = "simple"
    vpc_name      = "simple-vpc"
    vpc_cidrs     = [{ cidr = "10.227.0.0/23", role = "routable" }]
    eks_placement = "routable"
  }
  expect_failures = [terraform_data.checks]
}

run "reject_manual_outside_spare" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site           = "simple"
    vpc_name       = "simple-vpc"
    vpc_cidrs      = [{ cidr = "10.227.0.0/23", role = "routable" }]
    manual_subnets = [{ name = "bad", az = "ap-northeast-2a", cidr = "10.227.0.128/28", purpose = "ec2" }] # ec2 서브넷과 겹침
  }
  expect_failures = [terraform_data.checks]
}

run "reject_unknown_layout_version" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site           = "simple"
    vpc_name       = "simple-vpc"
    vpc_cidrs      = [{ cidr = "10.227.0.0/23", role = "routable" }]
    layout_version = "v9"
  }
  expect_failures = [terraform_data.checks]
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
    vpc_cidrs = [{ cidr = "10.227.0.0/22", role = "routable" }]
    az_count  = 3
  }
  expect_failures = [terraform_data.checks]
}

run "reject_wrong_internal_cidr" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site     = "simple"
    vpc_name = "simple-vpc"
    vpc_cidrs = [
      { cidr = "10.227.0.0/23", role = "routable" },
      { cidr = "100.0.0.0/16", role = "internal" },
    ]
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
      { cidr = "10.227.0.0/23", role = "routable" },
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
    vpc_cidrs = [{ cidr = "10.227.0.0/22", role = "routable" }]
    az_count  = 5
  }
  expect_failures = [var.az_count]
}

############################################################
# ACM 인증서 (plan만: mock은 검증 정보를 plan 시점에 모르므로 테스트에서만 값을 지정)
############################################################
run "acm_validation_in_parent_zone_when_no_public" {
  command = plan
  variables {
    enable_certificate = true
  }
  override_resource {
    target          = module.shared_common.module.acm[0].aws_acm_certificate.this
    override_during = plan
    values = {
      domain_validation_options = [
        { domain_name = "simple.example.com", resource_record_name = "_x.simple.example.com.", resource_record_type = "CNAME", resource_record_value = "_y.acm-validations.aws." },
        { domain_name = "*.simple.example.com", resource_record_name = "_x.simple.example.com.", resource_record_type = "CNAME", resource_record_value = "_y.acm-validations.aws." },
      ]
    }
  }
  override_data {
    target          = module.network_base.data.aws_route53_zone.parent[0]
    override_during = plan
    values          = { zone_id = "ZPARENT123" }
  }
  assert {
    condition     = toset(keys(output.certificate_validation_records)) == toset(["simple.example.com", "*.simple.example.com"]) && alltrue([for k, z in output.certificate_validation_records : z == "ZPARENT123"])
    error_message = "검증 레코드는 public 존이 없으면 상위 존에: ${jsonencode(output.certificate_validation_records)}"
  }
}

############################################################
# 주말 중지: 스케줄은 기본 꺼짐, ec2 endpoint 필요
############################################################
run "weekend_stop_prepared_but_disabled" {
  command = apply
  variables {
    enable_weekend_stop = true
    interface_endpoints = ["ssm", "ssmmessages", "ec2messages", "ec2"]
  }
  assert {
    condition     = alltrue([for k, s in output.weekend_stop.schedules : s.state == "DISABLED"]) && toset(keys(output.weekend_stop.schedules)) == toset(["stop", "start"])
    error_message = "스케줄은 협의 전 DISABLED여야 함: ${jsonencode(output.weekend_stop)}"
  }
}

run "reject_weekend_stop_without_ec2_endpoint" {
  command = plan
  module { source = "../deployment/ec2-common" }
  variables {
    network             = run.layout_v1_2az.network_contract
    enable_weekend_stop = true
  }
  expect_failures = [terraform_data.weekend_stop_checks]
}
