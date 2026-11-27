# 조합 코드 통합 테스트 (mock provider, AWS 접속 없음)
# 실행: terraform -chdir=tests init && terraform -chdir=tests test
#
# public NAT EIP에는 prevent_destroy가 있어 apply 후 정리를 할 수 없으므로,
# enable_public = true 검사는 plan으로만 합니다.

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
    common_sg_rules_csv = "sg,no,direction,protocol,from_port,to_port,source,description,memo\ncommon,1,ingress,tcp,22,22,pl:access_ctl,server access control,서버 접근제어\n"
  }
  assert {
    condition     = length(output.common_sg_rules.ingress) == 1 && one(values(output.common_sg_rules.ingress)).prefix_list_id == output.prefix_list_ids["access_ctl"]
    error_message = "공통 SG 규칙: ${jsonencode(output.common_sg_rules)}"
  }
  assert {
    condition     = length(output.common_sg_rules.egress) == 0
    error_message = "공통 SG는 아웃바운드 없음: ${jsonencode(output.common_sg_rules.egress)}"
  }
  assert {
    # webide CSV: app 인바운드 80 ← pl:access_ctl (memo의 한글은 무시)
    condition     = length([for k, r in output.webide_sg_rules.ingress : r if r.prefix_list_id == output.prefix_list_ids["access_ctl"] && r.from_port == 80]) == 1
    error_message = "webide 규칙: ${jsonencode(output.webide_sg_rules.ingress)}"
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
    condition     = toset(output.endpoint_ids) == toset(["ssm", "ssmmessages", "ec2messages", "logs", "monitoring", "s3"])
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
  expect_failures = [output.alb_arn]
}

run "reject_alb_with_1_az" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common     = run.az_count_1.ec2_common_contract
    ami        = "ami-0123456789abcdef0"
    enable_alb = true
  }
  expect_failures = [output.alb_arn]
}

run "reject_korean_sg_description" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_sg_rules_csv" }
  variables {
    sg_ids              = { common = "sg-common" }
    prefix_list_ids     = { access_ctl = "pl-access", admin = "pl-admin" }
    prefix_list_weights = { access_ctl = 5, admin = 5 }
    csv                 = "sg,no,direction,protocol,from_port,to_port,source,description,memo\ncommon,1,ingress,tcp,22,22,cidr:10.185.66.0/24,서버 접근제어,\n"
  }
  expect_failures = [output.ingress, output.egress]
}

run "reject_bad_sg_csv_rows" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_sg_rules_csv" }
  variables {
    sg_ids          = { app = "sg-app", alb = "sg-alb" }
    source_sg_ids   = { common = "sg-common" }
    prefix_list_ids = { access_ctl = "pl-access", admin = "pl-admin" }
    csv             = "sg,no,direction,protocol,from_port,to_port,source,description,memo\ndb,1,ingress,tcp,1521,1521,cidr:10.0.0.0/24,x,\napp,1,ingress,tcp,80,80,pl:nope,x,\napp,2,ingress,tcp,443,443,cidr:0.0.0.0/0,x,\napp,3,egress,tcp,1521,1521,cidr:10.1.0.0/24,x,\napp,4,egress,tcp,1521,1521,cidr:10.1.0.0/24,x,\n"
  }
  expect_failures = [output.ingress, output.egress]
}

run "sg_csv_rules_applied" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common = run.layout_v1_2az.ec2_common_contract
    ami    = "ami-0123456789abcdef0"
    # BOM + Windows 줄바꿈 (Excel "CSV UTF-8" 저장 형식)
    sg_rules_csv = "\ufeffsg,no,direction,protocol,from_port,to_port,source,description,memo\r\napp,1,egress,tcp,1521,1521,cidr:10.185.10.0/24,to legacy db,기존 DB\r\napp,2,ingress,tcp,8443,8443,sg:common,from common,\r\napp,3,egress,all,,,self,self,\r\n"
  }
  assert {
    condition     = length([for k, r in output.sg_rules.egress : r if r.cidr_ipv4 == "10.185.10.0/24" && r.from_port == 1521]) == 1
    error_message = "CSV egress 규칙: ${jsonencode(output.sg_rules.egress)}"
  }
  assert {
    condition     = length([for k, r in output.sg_rules.ingress : r if r.from_port == 8443 && r.referenced_security_group_id == run.layout_v1_2az.ec2_common_contract.common_sg_id]) == 1
    error_message = "CSV sg:common 규칙: ${jsonencode(output.sg_rules.ingress)}"
  }
  assert {
    condition     = length([for k, r in output.sg_rules.egress : r if r.ip_protocol == "-1" && r.from_port == null && r.cidr_ipv4 == null && r.prefix_list_id == null]) == 1
    error_message = "CSV self 규칙: ${jsonencode(output.sg_rules.egress)}"
  }
}

############################################################
# 잘못된 입력은 plan에서 막힘 (network-base 단독 실행)
############################################################
run "reject_small_routable" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site        = "simple"
    vpc_name    = "simple-vpc"
    name_prefix = "hw-iac-dev-an2"
    vpc_cidrs   = [{ cidr = "10.227.0.0/24", role = "routable" }] # AZ 2개면 /23 필요
  }
  expect_failures = [output.input_checks]
}

run "reject_eks_routable_too_small" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site          = "simple"
    vpc_name      = "simple-vpc"
    name_prefix   = "hw-iac-dev-an2"
    vpc_cidrs     = [{ cidr = "10.227.0.0/23", role = "routable" }]
    eks_placement = "routable"
  }
  expect_failures = [output.input_checks]
}

run "reject_manual_outside_spare" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site           = "simple"
    vpc_name       = "simple-vpc"
    name_prefix    = "hw-iac-dev-an2"
    vpc_cidrs      = [{ cidr = "10.227.0.0/23", role = "routable" }]
    manual_subnets = [{ name = "bad", az = "ap-northeast-2a", cidr = "10.227.0.128/28", purpose = "ec2" }] # ec2 서브넷과 겹침
  }
  expect_failures = [output.input_checks]
}

run "reject_unknown_layout_version" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site           = "simple"
    vpc_name       = "simple-vpc"
    name_prefix    = "hw-iac-dev-an2"
    vpc_cidrs      = [{ cidr = "10.227.0.0/23", role = "routable" }]
    layout_version = "v9"
  }
  expect_failures = [output.input_checks]
}

run "reject_az_count_over_region" {
  command = plan
  module { source = "../deployment/network-base" }
  override_data {
    target = data.aws_availability_zones.this
    values = { names = ["ap-northeast-2a", "ap-northeast-2c"] }
  }
  variables {
    site        = "simple"
    vpc_name    = "simple-vpc"
    name_prefix = "hw-iac-dev-an2"
    vpc_cidrs   = [{ cidr = "10.227.0.0/22", role = "routable" }]
    az_count    = 3
  }
  expect_failures = [output.input_checks]
}

run "reject_wrong_internal_cidr" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site        = "simple"
    vpc_name    = "simple-vpc"
    name_prefix = "hw-iac-dev-an2"
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
    site        = "simple"
    vpc_name    = "simple-vpc"
    name_prefix = "hw-iac-dev-an2"
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
    site        = "simple"
    vpc_name    = "simple-vpc"
    name_prefix = "hw-iac-dev-an2"
    vpc_cidrs   = [{ cidr = "10.227.0.0/22", role = "routable" }]
    az_count    = 5
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
    interface_endpoints = ["ssm", "ssmmessages", "ec2messages", "logs", "monitoring", "ec2"]
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
  expect_failures = [output.weekend_stop]
}

############################################################
# EC2 CloudWatch Agent: 정책은 항상 포함, 폐쇄망이면 logs/monitoring endpoint 필요
############################################################
run "ec2_role_has_cloudwatch_agent_policy" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common      = run.layout_v1_2az.ec2_common_contract
    ami         = "ami-0123456789abcdef0"
    policy_arns = { cloudwatch_agent = "arn:aws:iam::111111111111:policy/other" } # 덮어쓰기 시도
  }
  assert {
    condition     = module.role_policy.policy_arns["cloudwatch_agent"] == "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" && module.role_policy.policy_arns["ssm"] == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "필수 정책이 빠지거나 덮어써짐: ${jsonencode(module.role_policy.policy_arns)}"
  }
}

run "reject_closed_network_without_cloudwatch_endpoints" {
  command = plan
  module { source = "../deployment/ec2-common" }
  variables {
    network = merge(run.layout_v1_2az.network_contract, {
      endpoints = merge(run.layout_v1_2az.network_contract.endpoints, { interface = ["ssm", "ssmmessages", "ec2messages"] })
    })
  }
  expect_failures = [output.contract]
}

############################################################
# 보안 기본값: EC2 아웃바운드는 VPC + gateway endpoint만 (인터넷 전체 허용 없음)
############################################################
run "ec2_egress_closed_by_default" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common = run.layout_v1_2az.ec2_common_contract
    ami    = "ami-0123456789abcdef0"
  }
  assert {
    condition     = !anytrue([for k, r in output.sg_rules.egress : r.cidr_ipv4 == "0.0.0.0/0"]) && length(output.sg_rules.egress) > 0
    error_message = "EC2 SG 아웃바운드에 0.0.0.0/0이 있으면 안 됨"
  }
}

############################################################
# src/sg_rules.example.csv 예제가 형식에 맞는지 (복사해서 쓰는 예제라 항상 통과해야 함)
############################################################
run "sg_example_csv_common" {
  command = plan
  module { source = "../deployment/ec2-common" }
  variables {
    network      = run.layout_v1_2az.network_contract
    sg_rules_csv = file("../deployment/ec2-common/src/sg_rules.example.csv")
  }
  assert {
    condition     = length(output.sg_rules.ingress) == 3
    error_message = "ec2-common 예제: ${jsonencode(keys(output.sg_rules.ingress))}"
  }
}

run "sg_example_csv_was" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common       = run.layout_v1_2az.ec2_common_contract
    ami          = "ami-0123456789abcdef0"
    enable_alb   = true # 예제에 alb 행이 있음
    sg_rules_csv = file("../deployment/ec2-was/src/sg_rules.example.csv")
  }
  assert {
    condition     = length([for k, r in output.sg_rules.ingress : k if !startswith(k, "base|")]) == 2 && length([for k, r in output.sg_rules.egress : k if !startswith(k, "base|")]) == 3
    error_message = "ec2-was 예제: ${jsonencode(keys(output.sg_rules.ingress))} ${jsonencode(keys(output.sg_rules.egress))}"
  }
}

run "sg_example_csv_webide" {
  command = plan
  module { source = "../deployment/ec2-webide" }
  variables {
    common       = run.layout_v1_2az.ec2_common_contract
    ami          = "ami-0123456789abcdef0"
    sg_rules_csv = file("../deployment/ec2-webide/src/sg_rules.example.csv")
  }
  assert {
    condition     = length([for k, r in output.sg_rules.ingress : k if !startswith(k, "base|")]) == 1 && length([for k, r in output.sg_rules.egress : k if !startswith(k, "base|")]) == 2
    error_message = "ec2-webide 예제: ${jsonencode(keys(output.sg_rules.ingress))} ${jsonencode(keys(output.sg_rules.egress))}"
  }
}

############################################################
# SG CSV: 코드 기본 규칙과 같은 규칙, 표기만 다른 중복, 규칙 한도 (모두 apply 실패 원인 → plan에서 막음)
############################################################
run "reject_csv_rule_same_as_base" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_sg_rules_csv" }
  variables {
    sg_ids          = { app = "sg-app", alb = "sg-alb" }
    source_sg_ids   = { common = "sg-common" }
    prefix_list_ids = { access_ctl = "pl-access", admin = "pl-admin" }
    # 폴더가 넘기는 기본 규칙 서명 (app 아웃바운드 VPC 전체)과 같은 행
    base_signatures = ["app|egress|-1|||cidr:10.227.0.0/23"]
    csv             = "sg,no,direction,protocol,from_port,to_port,source,description,memo\napp,1,egress,all,,,cidr:10.227.0.0/23,again,\n"
  }
  expect_failures = [output.ingress, output.egress]
}

run "reject_csv_duplicate_with_different_notation" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_sg_rules_csv" }
  variables {
    sg_ids              = { common = "sg-common" }
    prefix_list_ids     = { access_ctl = "pl-access", admin = "pl-admin" }
    prefix_list_weights = { access_ctl = 5, admin = 5 }
    csv                 = "sg,no,direction,protocol,from_port,to_port,source,description,memo\ncommon,1,ingress,tcp,22,22,pl:access_ctl,ssh,\ncommon,2,ingress,TCP,022,22,pl:access_ctl,ssh again,\n"
  }
  expect_failures = [output.ingress, output.egress]
}

run "reject_sg_rule_limit" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_sg_rules_csv" }
  variables {
    sg_ids              = { common = "sg-common" }
    prefix_list_ids     = { access_ctl = "pl-access", admin = "pl-admin" }
    prefix_list_weights = { access_ctl = 5, admin = 5 }
    # access_ctl(max 5) + admin(max 5) = 10 > 한도 8
    rule_limit = 8
    csv        = "sg,no,direction,protocol,from_port,to_port,source,description,memo\ncommon,1,ingress,tcp,22,22,pl:access_ctl,ssh,\ncommon,2,ingress,tcp,22,22,pl:admin,ssh admin,\n"
  }
  expect_failures = [output.ingress, output.egress]
}

run "sg_rule_limit_counts_prefix_list_entries" {
  command = plan
  module { source = "../deployment/ec2-common" }
  variables {
    network       = run.layout_v1_2az.network_contract
    sg_rule_limit = 10 # 정확히 10이면 통과
    sg_rules_csv  = "sg,no,direction,protocol,from_port,to_port,source,description,memo\ncommon,1,ingress,tcp,22,22,pl:access_ctl,ssh,\ncommon,2,ingress,tcp,22,22,pl:admin,ssh admin,\n"
  }
  assert {
    condition     = length(output.sg_rules.ingress) == 2
    error_message = "규칙: ${jsonencode(keys(output.sg_rules.ingress))}"
  }
}

############################################################
# SG CSV 순번(no): 규칙의 키. 내용을 고쳐도 번호가 같으면 같은 규칙 (그 자리에서 수정)
############################################################
run "sg_csv_key_is_no" {
  command = plan
  module { source = "../deployment/ec2-common" }
  variables {
    network = run.layout_v1_2az.network_contract
    # common 7번 규칙의 포트를 22 → 2222로 바꾼 상태. 키는 그대로 common-7
    sg_rules_csv = "sg,no,direction,protocol,from_port,to_port,source,description,memo\ncommon,7,ingress,tcp,2222,2222,pl:access_ctl,ssh,\n"
  }
  assert {
    condition     = jsonencode(keys(output.sg_rules.ingress)) == jsonencode(["common-7"]) && output.sg_rules.ingress["common-7"].from_port == 2222
    error_message = "키: ${jsonencode(keys(output.sg_rules.ingress))}"
  }
}

run "reject_duplicate_no" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_sg_rules_csv" }
  variables {
    sg_ids              = { common = "sg-common" }
    prefix_list_ids     = { access_ctl = "pl-access", admin = "pl-admin" }
    prefix_list_weights = { access_ctl = 5, admin = 5 }
    csv                 = "sg,no,direction,protocol,from_port,to_port,source,description,memo\ncommon,3,ingress,tcp,22,22,pl:access_ctl,ssh,\ncommon,3,ingress,tcp,3389,3389,pl:access_ctl,rdp,\n"
  }
  expect_failures = [output.ingress, output.egress]
}

run "reject_invalid_no" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_sg_rules_csv" }
  variables {
    sg_ids              = { common = "sg-common" }
    prefix_list_ids     = { access_ctl = "pl-access", admin = "pl-admin" }
    prefix_list_weights = { access_ctl = 5, admin = 5 }
    csv                 = "sg,no,direction,protocol,from_port,to_port,source,description,memo\ncommon,,ingress,tcp,22,22,pl:access_ctl,ssh,\ncommon,1.5,ingress,tcp,3389,3389,pl:access_ctl,rdp,\n"
  }
  expect_failures = [output.ingress, output.egress]
}

############################################################
# CloudWatch Agent 로그 그룹: 미리 만들고 보관 14일
############################################################
run "agent_log_groups_precreated_14_days" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common = run.layout_v1_2az.ec2_common_contract
    ami    = "ami-0123456789abcdef0"
  }
  assert {
    # 기본은 OS 로그(messages), 인증 로그(secure). 이름 규칙: /<VPC 이름>/<리소스 유형>/<리소스 이름>/<로그 이름>
    condition     = jsonencode(output.agent_log_groups) == jsonencode({ messages = "/simple-vpc/ec2/hw-iac-dev-an2-ec2-was/messages", secure = "/simple-vpc/ec2/hw-iac-dev-an2-ec2-was/secure" })
    error_message = "Agent 로그 그룹: ${jsonencode(output.agent_log_groups)}"
  }
  assert {
    # Agent 설치·설정 SSM 연결이 서버마다 하나
    condition     = keys(output.cloudwatch_agent) == ["hw-iac-dev-an2-ssa-wascwagent-01"]
    error_message = "Agent SSM 연결: ${jsonencode(keys(output.cloudwatch_agent))}"
  }
}

run "cloudwatch_agent_off_without_os_log_groups" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common           = run.layout_v1_2az.ec2_common_contract
    ami              = "ami-0123456789abcdef0"
    agent_log_groups = { app = "애플리케이션 로그" }
  }
  assert {
    # messages, secure 로그 그룹이 없으면 Agent 기본 설정을 걸지 않음 (Agent가 로그 그룹을 만들지 않도록)
    condition     = length(output.cloudwatch_agent) == 0 && keys(output.agent_log_groups) == ["app"]
    error_message = "Agent SSM 연결: ${jsonencode(keys(output.cloudwatch_agent))}"
  }
}

run "sg_base_rule_signature_format" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common = run.layout_v1_2az.ec2_common_contract
    ami    = "ami-0123456789abcdef0"
  }
  assert {
    # 폴더의 기본 규칙 서명이 helper의 CSV 서명 형식과 같아야 중복 검사가 동작함
    condition     = contains(output.sg_base_rules, "app|egress|-1|||cidr:${lower(run.layout_v1_2az.vpc_cidrs[0])}")
    error_message = "기본 규칙 서명: ${jsonencode(output.sg_base_rules)}"
  }
}

run "volumes_kept_when_protected" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common          = run.layout_v1_2az.ec2_common_contract
    ami             = "ami-0123456789abcdef0"
    protect_volumes = true
    ebs_volumes     = [{ device_name = "/dev/sdf", volume_size = 50, mount_point = "/data" }, { device_name = "/dev/sdg", volume_size = 100 }]
  }
  assert {
    # EC2는 루트만, 데이터 볼륨은 따로 만들어 붙임 (볼륨마다 볼륨 + 연결)
    condition     = length(module.data_volume) == 2 && length(module.data_volume_attachment) == 2 && length(output.agent_log_groups) == 2
    error_message = "데이터 볼륨: ${length(module.data_volume)}개, 연결 ${length(module.data_volume_attachment)}개"
  }
  assert {
    # mount_point가 있는 볼륨만 마운트 대상 → 마운트용 SSM 연결 1개, 붙이기만 하는 볼륨은 대상 아님
    condition     = length(output.volume_mount) == 1 && keys(local.mount_volumes) == ["/dev/sdf"]
    error_message = "마운트 대상: ${jsonencode(keys(local.mount_volumes))}"
  }
}

run "no_mount_without_mount_point" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common      = run.layout_v1_2az.ec2_common_contract
    ami         = "ami-0123456789abcdef0"
    ebs_volumes = [{ device_name = "/dev/sdf", volume_size = 50 }]
  }
  assert {
    condition     = length(output.volume_mount) == 0 && length(module.data_volume) == 1
    error_message = "mount_point가 없으면 마운트 SSM 연결을 만들지 않아야 함"
  }
}

run "reject_system_mount_point" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common      = run.layout_v1_2az.ec2_common_contract
    ami         = "ami-0123456789abcdef0"
    ebs_volumes = [{ device_name = "/dev/sdf", volume_size = 50, mount_point = "/var" }]
  }
  expect_failures = [var.ebs_volumes]
}

run "reject_duplicate_mount_point" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common = run.layout_v1_2az.ec2_common_contract
    ami    = "ami-0123456789abcdef0"
    ebs_volumes = [
      { device_name = "/dev/sdf", volume_size = 50, mount_point = "/data" },
      { device_name = "/dev/sdg", volume_size = 50, mount_point = "/data/" },
    ]
  }
  expect_failures = [var.ebs_volumes]
}

############################################################
# prefix list CSV (deployment/network-base/src/prefix_lists.csv → module/_prefix_lists_csv)
############################################################
run "prefix_lists_csv_parse" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_prefix_lists_csv" }
  variables {
    # BOM + Windows 줄바꿈, max_entries는 한 행에만 / 비우면 기본 10, 빈 행 무시
    csv = "﻿list,no,cidr,description,max_entries,memo\r\naccess_ctl,1,10.185.66.10/32,server-access-control,5,접근제어\r\nadmin,1,10.185.66.0/24,admin-pc,,관리자\r\nadmin,2,10.185.67.0/24,admin-pc-2,,\r\n,,,,,\r\n"
  }
  assert {
    condition = (
      output.prefix_lists.access_ctl.max_entries == 5 &&
      output.prefix_lists.admin.max_entries == 10 &&
      output.prefix_lists.admin.entries["10.185.67.0/24"] == "admin-pc-2" &&
      length(output.prefix_lists.admin.entries) == 2 && output.row_count == 3
    )
    error_message = "prefix list CSV 해석: ${jsonencode(output.prefix_lists)}"
  }
}

run "reject_prefix_lists_csv_errors" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_prefix_lists_csv" }
  variables {
    # 잘못된 cidr, 순번 중복, 한글 description, max_entries 불일치
    csv = "list,no,cidr,description,max_entries,memo\nadmin,1,10.185.66.0/33,admin-pc,5,\nadmin,1,10.185.67.0/24,관리자,4,\n"
  }
  expect_failures = [output.prefix_lists]
}

run "reject_prefix_lists_tfvars_and_csv" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_prefix_lists_csv" }
  variables {
    csv                = "list,no,cidr,description,max_entries,memo\nadmin,1,10.185.66.0/24,admin-pc,5,\n"
    other_source_count = 1
  }
  expect_failures = [output.prefix_lists]
}

run "network_base_reads_prefix_lists_csv" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site             = "simple"
    vpc_name         = "simple-vpc"
    name_prefix      = "hw-iac-dev-an2"
    vpc_cidrs        = [{ cidr = "10.227.0.0/23", role = "routable" }]
    enable_flow_logs = false
    prefix_lists_csv = "list,no,cidr,description,max_entries,memo\ncorp,1,10.0.0.0/8,corp-network,10,사내망\n"
  }
  assert {
    condition     = jsonencode(keys(local.prefix_lists)) == jsonencode(["corp"]) && local.prefix_lists.corp.max_entries == 10
    error_message = "network-base prefix list: ${jsonencode(local.prefix_lists)}"
  }
}

############################################################
# 같은 단계 다른 용도 SG 참조 (sg:<용도>.<sg>)
############################################################
run "same_stage_sg_reference_by_name" {
  command = apply
  variables {
    was_enable_alb   = true
    was_sg_rules_csv = "sg,no,direction,protocol,from_port,to_port,source,description,memo\napp,1,ingress,tcp,8080,8080,sg:webide.app,from webide,웹 IDE 서버 → WAS\n"
  }
  assert {
    # was 규칙의 출발지 = webide의 app SG (ID를 몰라도 이름으로 한 번에 적용)
    condition     = length([for k, r in output.was_sg_rules.ingress : r if r.referenced_security_group_id == output.purpose_sg_ids["webide.app"] && r.from_port == 8080]) == 1
    error_message = "was 규칙: ${jsonencode(output.was_sg_rules.ingress)} / 이름표: ${jsonencode(output.purpose_sg_ids)}"
  }
  assert {
    # 이름표: was(app, alb), webide(app, ALB 없음)
    condition     = toset(keys(output.purpose_sg_ids)) == toset(["was.app", "was.alb", "webide.app"])
    error_message = "이름표: ${jsonencode(keys(output.purpose_sg_ids))}"
  }
}

############################################################
# 자동 확장 (고정 서버 1대 + ASG 0 ~ max_extra)
############################################################
run "autoscale_off_by_default" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common = run.layout_v1_2az.ec2_common_contract
    ami    = "ami-0123456789abcdef0"
  }
  assert {
    condition     = output.autoscale == null && length(module.asg) == 0 && length(module.initial_image) == 0 && length(module.asg_alarm) == 0
    error_message = "기본은 자동 확장 꺼짐 (고정 서버만)"
  }
}

run "autoscale_with_initial_image" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common      = run.layout_v1_2az.ec2_common_contract
    ami         = "ami-0123456789abcdef0"
    enable_alb  = true
    ebs_volumes = [{ device_name = "/dev/sdf", volume_size = 20, mount_point = "/data" }]
    autoscale   = { enabled = true, max_extra = 2 }
  }
  assert {
    # autoscale.ami가 없으면 고정 서버로 최초 이미지, ALB 대상 그룹에 연결, 알람 2개·정책 2개, 주말 중지는 기본 꺼짐
    condition = (
      length(module.initial_image) == 1 && length(module.asg) == 1 && length(module.asg_tg) == 1 &&
      length(module.asg_policy) == 1 && length(module.asg_alarm) == 1 && length(module.asg_schedule) == 0 &&
      output.autoscale.initial_image
    )
    error_message = "자동 확장 구성: ${jsonencode(output.autoscale)}"
  }
}

run "autoscale_with_fixed_ami_and_weekend_stop" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common    = run.layout_v1_2az.ec2_common_contract
    ami       = "ami-0123456789abcdef0"
    autoscale = { enabled = true, ami = "ami-0fedcba9876543210", max_extra = 3, weekend_stop = { enabled = true } }
  }
  assert {
    # 고정 AMI ID가 있으면 최초 이미지를 만들지 않음, ALB를 끄면 대상 그룹 연결 없음, 주말 중지 켜면 예약 2개
    condition     = length(module.initial_image) == 0 && output.autoscale.image_id == "ami-0fedcba9876543210" && length(module.asg_tg) == 0 && length(module.asg_schedule) == 1
    error_message = "고정 AMI: ${jsonencode(output.autoscale)}"
  }
}

run "reject_autoscale_thresholds" {
  command = plan
  module { source = "../deployment/ec2-was" }
  variables {
    common    = run.layout_v1_2az.ec2_common_contract
    ami       = "ami-0123456789abcdef0"
    autoscale = { enabled = true, max_extra = 2, scale_out = 60, scale_in = 70 }
  }
  expect_failures = [var.autoscale]
}

############################################################
# SG 규칙 CSV 검사 보강 (QA)
############################################################
run "reject_all_protocol_with_ports" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_sg_rules_csv" }
  variables {
    sg_ids = { app = "sg-app" }
    # all에 22를 적어도 모든 포트가 열림 → 막아야 함
    csv = "sg,no,direction,protocol,from_port,to_port,source,description,memo\napp,1,ingress,all,22,22,cidr:10.0.0.0/24,ssh only,의도와 다름\n"
  }
  expect_failures = [output.ingress, output.egress]
}

run "all_protocol_without_ports_ok" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_sg_rules_csv" }
  variables {
    sg_ids = { app = "sg-app" }
    csv    = "sg,no,direction,protocol,from_port,to_port,source,description,memo\napp,1,egress,all,,,cidr:10.0.0.0/24,all to subnet,\n"
  }
  assert {
    condition     = length(output.egress) == 1 && length(output.errors) == 0
    error_message = "all + 빈 포트는 허용: ${jsonencode(output.errors)}"
  }
}

run "prefix_list_id_uses_real_max_entries" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_sg_rules_csv" }
  override_data {
    target = data.aws_ec2_managed_prefix_list.direct["pl-0abc1234def567890"]
    values = { max_entries = 50 }
  }
  variables {
    sg_ids     = { app = "sg-app" }
    rule_limit = 30
    # ID로 쓴 prefix list의 max_entries(50)가 한도(30)를 넘음 → 막아야 함 (예전에는 1로 계산되어 통과)
    csv = "sg,no,direction,protocol,from_port,to_port,source,description,memo\napp,1,ingress,tcp,443,443,pl:pl-0abc1234def567890,https from partner,\n"
  }
  expect_failures = [output.ingress, output.egress]
}

############################################################
# RDS 파라미터 CSV (deployment/rds-<엔진>/src/<name>.parameters.csv → module/_rds_parameters_csv)
############################################################
run "rds_parameters_csv_parse" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_rds_parameters_csv" }
  variables {
    # BOM + Windows 줄바꿈, apply_method 비우면 pending-reboot, 빈 행 무시
    csv = "﻿no,name,value,apply_method,memo\r\n1,log_min_duration_statement,1000,immediate,느린 쿼리\r\n2,rds.force_ssl,1,,SSL 강제\r\n,,,,\r\n"
  }
  assert {
    condition = (
      length(output.parameters) == 2 &&
      output.parameters[0].name == "log_min_duration_statement" && output.parameters[0].apply_method == "immediate" &&
      output.parameters[1].apply_method == "pending-reboot"
    )
    error_message = "파라미터 CSV 해석: ${jsonencode(output.parameters)}"
  }
}

run "reject_rds_parameters_csv_errors" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_rds_parameters_csv" }
  variables {
    # 순번 중복, 이름 중복, 잘못된 apply_method
    csv = "no,name,value,apply_method,memo\n1,max_connections,200,immediate,\n1,max_connections,300,later,\n"
  }
  expect_failures = [output.parameters]
}

run "reject_rds_parameters_tfvars_and_csv" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_rds_parameters_csv" }
  variables {
    csv                = "no,name,value,apply_method,memo\n1,max_connections,200,,\n"
    other_source_count = 1
  }
  expect_failures = [output.parameters]
}

############################################################
# 서브넷 CIDR 직접 입력 (subnet_cidrs): 고객 대역 모양과 관계없이 설계서 값 그대로
############################################################
run "manual_cidrs_single_24_with_shared" {
  # /24 하나 (AZ 2개, 규칙 배치로는 안 되는 크기): 01-network는 자기 서브넷만 직접 입력 + 공용 서브넷(db·efs)은 내부 대역
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site             = "simple"
    vpc_name         = "simple-vpc"
    name_prefix      = "hw-iac-dev-an2"
    enable_flow_logs = false
    vpc_cidrs        = [{ cidr = "10.30.0.0/24", role = "routable" }, { cidr = "100.64.0.0/16", role = "internal" }]
    subnet_cidrs = {
      edge    = { a = "10.30.0.0/27", b = "10.30.0.32/27" }
      vpce    = { a = "10.30.0.64/28", b = "10.30.0.80/28" }
      transit = { a = "10.30.0.96/28", b = "10.30.0.112/28" }
    }
    shared_subnets = {
      data = { cidrs = { a = "100.64.255.0/27", b = "100.64.255.32/27" }, use = ["db", "efs"] }
    }
  }
  assert {
    condition = (
      output.contract.base.subnet_mode == "manual" && output.contract.subnets.cidrs.edge["ap-northeast-2a"] == "10.30.0.0/27" &&
      !contains(keys(output.contract.subnets.cidrs), "ec2") &&
      jsonencode(output.contract.subnets.shared_cidrs_for.db) == jsonencode({ "ap-northeast-2a" = "100.64.255.0/27", "ap-northeast-2b" = "100.64.255.32/27" }) &&
      output.contract.subnets.shared_cidrs_for.efs["ap-northeast-2b"] == "100.64.255.32/27" &&
      jsonencode(output.contract.subnets.shared["data"].use) == jsonencode(["db", "efs"])
    )
    error_message = "직접 입력 /24 + 공용: ${jsonencode(output.contract.subnets.cidrs)} / ${jsonencode(output.contract.subnets.shared_cidrs_for)}"
  }
}

run "reject_shared_subnet_overlap_with_layout" {
  # 규칙 배치(v1)를 쓰면서 공용 서브넷이 계산된 db 칸과 겹침
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site           = "simple"
    vpc_name       = "simple-vpc"
    name_prefix    = "hw-iac-dev-an2"
    vpc_cidrs      = [{ cidr = "10.227.0.0/23", role = "routable" }]
    shared_subnets = { data = { cidrs = { a = "10.227.0.192/28", b = "10.227.0.112/28" }, use = ["db"] } }
  }
  expect_failures = [output.input_checks]
}

run "reject_shared_subnet_bad_use" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site           = "simple"
    vpc_name       = "simple-vpc"
    name_prefix    = "hw-iac-dev-an2"
    vpc_cidrs      = [{ cidr = "10.227.0.0/23", role = "routable" }]
    shared_subnets = { db = { cidrs = { a = "10.227.0.112/28", b = "10.227.1.112/28" }, use = ["ec2"] } }
  }
  expect_failures = [var.shared_subnets]
}

run "ec2_subnet_cidrs_direct" {
  # 03-compute가 EC2 서브넷 CIDR을 직접 받음 (규칙 계산값 대신). 태그 Access-db·efs
  command = plan
  module { source = "../deployment/ec2-common" }
  variables {
    network      = run.layout_v1_2az.network_contract
    name         = "ec2-common"
    subnet_cidrs = { a = "10.227.0.112/28", b = "10.227.1.112/28" }
  }
  assert {
    condition     = jsonencode(output.subnet_cidrs) == jsonencode({ "ap-northeast-2a" = "10.227.0.112/28", "ap-northeast-2b" = "10.227.1.112/28" })
    error_message = "EC2 직접 입력: ${jsonencode(output.subnet_cidrs)}"
  }
}

run "reject_subnet_cidr_outside_vpc_or_missing_az" {
  # 검사 도우미 직접: AZ b 없음, VPC 대역 밖
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_subnet_cidr_check" }
  variables {
    label           = "EC2 서브넷"
    vpc_id          = "vpc-1"
    vpc_cidrs       = ["10.227.0.0/23"]
    azs             = ["ap-northeast-2a", "ap-northeast-2b"]
    cidrs           = { "ap-northeast-2a" = "10.99.0.0/28" }
    own_name_prefix = "hw-iac-dev-an2-sbn-ec2-"
  }
  expect_failures = [output.ok]
}

run "subnet_cidr_check_passes" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_subnet_cidr_check" }
  variables {
    label           = "EC2 서브넷"
    vpc_id          = "vpc-1"
    vpc_cidrs       = ["10.227.0.0/23", "100.64.0.0/16"]
    azs             = ["ap-northeast-2a", "ap-northeast-2b"]
    cidrs           = { "ap-northeast-2a" = "10.227.0.112/28", "ap-northeast-2b" = "100.64.1.0/24" }
    own_name_prefix = "hw-iac-dev-an2-sbn-ec2-"
  }
  assert {
    condition     = output.ok
    error_message = "검사 통과해야 함"
  }
}

run "reject_manual_cidr_outside_vpc" {
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site         = "simple"
    vpc_name     = "simple-vpc"
    name_prefix  = "hw-iac-dev-an2"
    vpc_cidrs    = [{ cidr = "10.30.0.0/24", role = "routable" }]
    subnet_cidrs = { edge = { a = "10.30.0.0/27", b = "10.30.0.32/27" }, vpce = { a = "10.30.0.64/28", b = "10.30.0.80/28" }, transit = { a = "10.30.0.96/28", b = "10.99.0.0/28" } }
  }
  expect_failures = [output.input_checks]
}

run "reject_manual_cidr_overlap_and_missing_az" {
  # 겹침(vpce b와 edge a), AZ 빠짐(transit에 b 없음)
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site         = "simple"
    vpc_name     = "simple-vpc"
    name_prefix  = "hw-iac-dev-an2"
    vpc_cidrs    = [{ cidr = "10.30.0.0/24", role = "routable" }]
    subnet_cidrs = { edge = { a = "10.30.0.0/27", b = "10.30.0.32/27" }, vpce = { a = "10.30.0.64/28", b = "10.30.0.16/28" }, transit = { a = "10.30.0.96/28" } }
  }
  expect_failures = [output.input_checks]
}

run "reject_manual_missing_required_and_small_edge" {
  # transit 없음, edge /28 (ALB는 /27 이상)
  command = plan
  module { source = "../deployment/network-base" }
  variables {
    site         = "simple"
    vpc_name     = "simple-vpc"
    name_prefix  = "hw-iac-dev-an2"
    vpc_cidrs    = [{ cidr = "10.30.0.0/24", role = "routable" }]
    subnet_cidrs = { edge = { a = "10.30.0.0/28", b = "10.30.0.16/28" }, vpce = { a = "10.30.0.64/28", b = "10.30.0.80/28" } }
  }
  expect_failures = [output.input_checks]
}
