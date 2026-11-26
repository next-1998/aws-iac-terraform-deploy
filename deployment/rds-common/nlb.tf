############################################################
# RDS 앞 NLB (고정 IP 용도: 고객 DB 접근제어가 IP로만 허용할 때)
#   - 공유 NLB: 사이트에 하나(여기). 리스너(DB port)·대상 그룹은 각 DB(rds-core)가 만듦 → DB끼리 참조 없음
#   - 전용 NLB: DB마다 rds-core가 만듦
#   - 대상 동기화 Lambda: 태그 RdsNlbSyncSg = <SG>인 대상 그룹에 그 SG의 ENI IP를 1분마다 맞춤
#       원본 + 대기(Multi-AZ) IP, NLB 상태 확인이 활성 쪽만 사용 (읽기 복제본은 연결하지 않음)
#   NLB는 DB 서브넷에 둠 (AZ별 IP는 NLB를 지울 때까지 고정. private_ips로 지정 가능)
############################################################
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  nlb_sync_tag    = "RdsNlbSyncSg"
  db_subnet_by_az = { for az in local.azs : az => module.subnet[az].vpc_subnet[0].id }

  # Lambda가 쓰는 AWS API는 VPC endpoint로만 (워크로드는 private 기본)
  nlb_sync_endpoints = setsubtract(["ec2", "elasticloadbalancing"], try(var.network.endpoints.interface, []))
}

# ── 공유 NLB ───────────────────────────────────────────────────
module "shared_nlb_sg" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/security-group"
  count  = var.shared_nlb == null ? 0 : 1

  name        = "${local.np}-sg-rdsnlb-01"
  description = "shared NLB for RDS (rules added per DB)"
  vpc_id      = local.base.vpc_id

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_nlb"
}

module "shared_nlb" {
  source = "../../../aws-iac-terraform-module/module/network/aws-elb-workload/lb"
  count  = var.shared_nlb == null ? 0 : 1

  name               = "${local.np}-nlb-rds-01"
  load_balancer_type = "network"
  internal           = true
  lb_sg_id_list      = [module.shared_nlb_sg[0].securitygroup_id]
  subnet_mapping = [
    for az, id in local.db_subnet_by_az : merge(
      { subnet_id = id },
      contains(keys(var.shared_nlb.private_ips), az) ? { private_ipv4_address = var.shared_nlb.private_ips[az] } : {},
    )
  ]
  enable_cross_zone_load_balancing = true
  enable_deletion_protection       = var.protect_nlb

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_nlb"
}

# ── 대상 동기화 Lambda ─────────────────────────────────────────
locals {
  ns      = var.enable_nlb_sync ? { this = true } : {}
  ns_name = "${local.np}-lbd-rdsnlbsync-01"
}

data "archive_file" "nlb_sync" {
  count       = var.enable_nlb_sync ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/src/nlb_sync.py"
  output_path = "${path.module}/.build/nlb_sync.zip"
}

module "ns_log" {
  source   = "../../../aws-iac-terraform-module/module/monitor_log/aws-cloudwatch-workload/loggroup"
  for_each = local.ns

  name              = "/${local.base.vpc_name}/lambda/${local.ns_name}/function"
  retention_in_days = 14
  kms_key_id        = var.logs_kms_key_arn

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_nlbsync"
}

module "ns_role" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role"
  for_each = local.ns

  name               = "${local.np}-role-rdsnlbsync-01"
  description        = "RDS NLB target sync lambda"
  assume_role_policy = templatefile("${path.module}/policies/lambda-trust.json.tftpl", {})

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_nlbsync"
}

module "ns_role_vpc" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy-attachment"
  for_each = local.ns

  role_name   = module.ns_role[each.key].name
  policy_arns = { vpc = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole" }
}

module "ns_role_sync" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy"
  for_each = local.ns

  role_name = module.ns_role[each.key].name
  policies = {
    "${local.ns_name}-sync" = templatefile("${path.module}/policies/nlb-sync.json.tftpl", {
      partition  = data.aws_partition.current.partition
      region     = data.aws_region.current.region
      account_id = data.aws_caller_identity.current.account_id
      tag_key    = local.nlb_sync_tag
    })
  }
}

module "ns_sg" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/security-group"
  for_each = local.ns

  name        = "${local.np}-sg-rdsnlbsync-01"
  description = "RDS NLB sync lambda (egress 443 to VPC endpoints only)"
  vpc_id      = local.base.vpc_id

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_nlbsync"
}

module "ns_sg_egress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/egress-rule"
  rules = {
    for pair in setproduct(keys(local.ns), local.base.vpc_cidrs) : "${pair[0]}|vpce|${pair[1]}" => {
      security_group_id = module.ns_sg[pair[0]].securitygroup_id
      ip_protocol       = "tcp"
      from_port         = 443
      to_port           = 443
      cidr_ipv4         = pair[1]
      description       = "to VPC endpoints"
    }
  }
}

module "ns_lambda" {
  source   = "../../../aws-iac-terraform-module/module/devtools/aws-lambda-workload"
  for_each = local.ns

  function_name    = local.ns_name
  description      = "sync RDS NLB targets with ENI IPs of tagged security groups"
  role_arn         = module.ns_role[each.key].arn
  handler          = "nlb_sync.lambda_handler"
  filename         = data.archive_file.nlb_sync[0].output_path
  source_code_hash = data.archive_file.nlb_sync[0].output_base64sha256
  timeout          = 60

  environment_variables = {
    TAG_KEY = local.nlb_sync_tag
    VPC_ID  = local.base.vpc_id
    DRY_RUN = "false"
  }

  subnet_ids         = values(local.db_subnet_by_az)
  security_group_ids = [module.ns_sg[each.key].securitygroup_id]
  log_group_name     = module.ns_log[each.key].name

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_nlbsync"

  # VPC 권한이 붙은 뒤에 만들어야 ENI 생성이 실패하지 않음 (ec2-common Lambda와 같은 예외)
  depends_on = [module.ns_role_vpc]
}

module "ns_scheduler_role" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role"
  for_each = local.ns

  name               = "${local.np}-role-rdsnlbsyncsch-01"
  description        = "RDS NLB target sync scheduler"
  assume_role_policy = templatefile("${path.module}/policies/scheduler-trust.json.tftpl", {})

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_nlbsync_scheduler"
}

module "ns_scheduler_invoke" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-iam-workload/role-policy"
  for_each = local.ns

  role_name = module.ns_scheduler_role[each.key].name
  policies = {
    "${local.ns_name}-invoke" = templatefile("${path.module}/policies/lambda-invoke.json.tftpl", { lambda_arn = module.ns_lambda[each.key].arn })
  }
}

module "ns_schedule" {
  source   = "../../../aws-iac-terraform-module/module/devtools/aws-scheduler-workload"
  for_each = local.ns

  schedules = {
    sync = {
      name       = "${local.np}-sch-rdsnlbsync-01"
      expression = "rate(1 minute)"
      enabled    = true
      target_arn = module.ns_lambda[each.key].arn
      role_arn   = module.ns_scheduler_role[each.key].arn
    }
  }
}
