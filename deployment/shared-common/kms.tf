############################################################
# 공용 CMK (용도별)
#   central_kms_key_arns에 용도가 있으면 중앙 키를 쓰고, 없으면 이 계정에 만듭니다.
#     (logs 키는 계정 기본이라 00-bootstrap이 만듦: alias/<접두어>-kms-logs-01)
#     sns  : 알림 토픽. 키 정책에 CloudWatch 알람(cloudwatch.amazonaws.com) 허용
#   서비스마다 키 정책이 달라 키를 나눕니다. 중앙 키를 쓰면 같은 권한이 중앙 키 정책에 있어야 합니다.
############################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition

  kms_statements = {
    sns = [{
      sid     = "CloudWatchAlarmsPublish"
      actions = ["kms:Decrypt", "kms:GenerateDataKey*"]
      principals = [{
        type        = "Service"
        identifiers = ["cloudwatch.amazonaws.com"]
      }]
      resources = ["*"]
      condition = [{
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }]
    }]
  }

  # 이 계정에 만들 키 (중앙 키가 없는 용도만). sns는 알림 토픽을 쓸 때만
  kms_purposes = var.enable_alarm_topic ? ["sns"] : []
  local_keys   = toset([for k in local.kms_purposes : k if !contains(keys(var.central_kms_key_arns), k)])
}

module "kms_key" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-kms-workload/key"
  for_each = local.local_keys

  key_name                = "${local.base.name_prefix}-kms-${each.key}-01"
  description             = "${local.site} ${each.key} encryption"
  enable_key_rotation     = true
  deletion_window_in_days = var.protect_kms_keys ? 30 : 7
  prevent_destroy         = var.protect_kms_keys

  key_administrators = var.kms_key_administrators
  key_statements     = local.kms_statements[each.key]

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = local.stack
  key_target    = each.key
  scope         = "shared"
}

module "kms_alias" {
  source   = "../../../aws-iac-terraform-module/module/security/aws-kms-workload/alias"
  for_each = local.local_keys

  name          = "${local.base.name_prefix}-kms-${each.key}-01"
  target_key_id = module.kms_key[each.key].key_id
}

locals {
  # 용도 → 실제로 쓰는 키 ARN (중앙 키 또는 이 계정 키)
  kms_key_arns = {
    for k in local.kms_purposes : k => (
      contains(keys(var.central_kms_key_arns), k) ? var.central_kms_key_arns[k] : module.kms_key[k].key_arn
    )
  }
  kms_key_source = { for k in local.kms_purposes : k => contains(keys(var.central_kms_key_arns), k) ? "central" : "local" }
}
