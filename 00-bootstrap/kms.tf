############################################################
# 계정 단위 CMK (리소스별로 하나)
#   central_kms_key_arns에 있으면 중앙 키를 쓰고, 없으면 이 계정에 만듭니다.
#     ebs     : 계정·리전 EBS 기본 키. EC2 볼륨은 따로 지정하지 않으면 이 키로 암호화됨
#     s3      : S3 버킷. 기본은 state 버킷도 이 키 (로그 버킷은 ALB 때문에 SSE-S3 고정)
#     logs    : CloudWatch 로그 그룹 (계정 전체: 서버·Lambda 로그, Firehose 오류 로그 등). 키 정책에 CloudWatch Logs 서비스 허용
#               로그는 계정 기본 설정이라 이 단계가 만듦. 중앙 로그 계정 키를 쓸 때도 여기(central_kms_key_arns.logs)에 넣음
#   분리 옵션
#     tfstate : separate_tfstate_key = true면 state 버킷 전용 키를 따로 만듦
#               (state에 민감 정보가 있을 수 있어 S3 데이터 키와 권한을 나눌 때)
#               central_kms_key_arns.tfstate가 있으면 옵션과 관계없이 그 키를 씀
#   여기서 만든 키는 지우면 그 키로 암호화한 데이터를 읽을 수 없으므로 삭제 보호합니다.
############################################################

locals {
  central = var.central_kms_key_arns

  # tfstate 전용 키를 쓰는지 (중앙 키가 있거나 분리 옵션을 켰을 때)
  tfstate_separate = contains(keys(local.central), "tfstate") || var.separate_tfstate_key

  key_specs = {
    ebs = {
      description = "EBS default encryption key (account/region default)"
      admins      = var.kms_key_administrators
    }
    s3 = {
      description = "S3 buckets"
      admins      = var.kms_key_administrators
    }
    logs = {
      description = "CloudWatch Logs log groups (account)"
      admins      = var.kms_key_administrators
    }
    tfstate = {
      description = "Terraform state bucket and lock table (separated)"
      admins      = var.tfstate_kms_key_administrators
    }
  }

  # 이 계정에 만들 키: 중앙 키가 없는 리소스별 키 + (분리 옵션을 켰고 중앙 키가 없으면) tfstate
  purposes   = concat(["ebs", "s3", "logs"], local.tfstate_separate ? ["tfstate"] : [])
  local_keys = { for k in local.purposes : k => local.key_specs[k] if !contains(keys(local.central), k) }
}

data "aws_partition" "current" {}

locals {
  # EBS 기본 키: 이 계정 안에서 EC2 서비스를 통해 쓰는 경우만 허용 (AWS 기본 키 aws/ebs와 같은 방식)
  #   Auto Scaling이 확장 서버의 암호화 볼륨을 만들 때 쓰는 서비스 연결 역할(AWSServiceRoleForAutoScaling)도 포함됩니다.
  #   특정 역할 이름을 적지 않으므로 그 역할이 계정에 아직 없어도 키를 만들 수 있습니다 (bootstrap이 ASG보다 먼저 실행됨).
  #   EC2를 거치지 않는 직접 사용(Decrypt API 등)은 키 관리자 외에는 허용되지 않습니다.
  ebs_key_statements = [
    {
      sid        = "EbsViaEc2InThisAccount"
      actions    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey", "kms:CreateGrant"]
      principals = [{ type = "AWS", identifiers = ["*"] }]
      resources  = ["*"]
      condition = [
        { test = "StringEquals", variable = "kms:CallerAccount", values = [local.account_id] },
        { test = "StringEquals", variable = "kms:ViaService", values = ["ec2.${local.region}.amazonaws.com"] },
      ]
    },
  ]

  logs_key_statements = [{
    sid     = "CloudWatchLogs"
    actions = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    principals = [{
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }]
    resources = ["*"]
    # 이 계정의 로그 그룹만
    condition = [{
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${local.region}:${local.account_id}:log-group:*"]
    }]
  }]
}

module "kms_key" {
  source   = "../../aws-iac-terraform-module/module/security/aws-kms-workload/key"
  for_each = local.local_keys

  key_name                = "iac-account-${each.key}"
  description             = each.value.description
  enable_key_rotation     = true
  deletion_window_in_days = local.protect.kms_keys ? 30 : 7
  prevent_destroy         = local.protect.kms_keys

  key_administrators = each.value.admins
  # ebs 키: 이 계정 안에서 EC2를 통해 쓰는 경우만 허용 (Auto Scaling 서비스 역할 포함)
  # logs 키: CloudWatch Logs 서비스가 이 계정 로그 그룹을 암호화하도록 허용
  key_statements = each.key == "ebs" ? local.ebs_key_statements : each.key == "logs" ? local.logs_key_statements : []

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
  key_target  = each.key
}

module "kms_alias" {
  source   = "../../aws-iac-terraform-module/module/security/aws-kms-workload/alias"
  for_each = local.local_keys

  name          = "iac/account/${each.key}"
  target_key_id = module.kms_key[each.key].key_id
}

locals {
  # 키 → 실제로 쓰는 키 ARN (중앙 키 또는 이 계정 키)
  key_arn = { for k in local.purposes : k => contains(keys(local.central), k) ? local.central[k] : module.kms_key[k].key_arn }

  kms_key_arns = {
    ebs = local.key_arn.ebs
    s3  = local.key_arn.s3
    # CloudWatch 로그 그룹 (계정 전체, 다음 단계도 이 값을 씀)
    logs = local.key_arn.logs
    # state 버킷이 실제로 쓰는 키 (분리하지 않으면 s3 키)
    tfstate = local.tfstate_separate ? local.key_arn.tfstate : local.key_arn.s3
  }
  kms_key_source = {
    ebs     = contains(keys(local.central), "ebs") ? "central" : "local"
    s3      = contains(keys(local.central), "s3") ? "central" : "local"
    logs    = contains(keys(local.central), "logs") ? "central" : "local"
    tfstate = !local.tfstate_separate ? "same-as-s3" : (contains(keys(local.central), "tfstate") ? "central" : "local")
  }
}
