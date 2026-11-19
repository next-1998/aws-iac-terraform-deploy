############################################################
# 계정·리전 보안 기본값 (필수)
#   - EBS: 기본 암호화 켜기 + 기본 키를 고객 관리형 키(CMK)로 지정
#          kms_key_id를 주지 않은 모든 새 EBS 볼륨이 이 CMK로 암호화됩니다.
#   - S3 : 계정 단위 퍼블릭 접근 차단 (계정 전체, 버킷 설정보다 우선)
#   - EC2: 인스턴스 메타데이터 기본값 IMDSv2 필수
#   EBS, IMDS 설정은 리전 단위라 이 단계를 실행하는 리전마다 적용됩니다.
#   이미 만들어진 볼륨·인스턴스는 바뀌지 않습니다 (새로 만드는 것부터 적용).
############################################################

locals {
  # Auto Scaling이 CMK로 암호화된 볼륨을 붙이려면 서비스 연결 역할에 키 사용 권한이 필요합니다.
  # 이 역할이 계정에 먼저 있어야 키 정책을 만들 수 있으므로 ASG를 쓸 때만 켭니다.
  asg_service_role = "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
}

data "aws_partition" "current" {}

# EBS 기본 CMK. 지우면 이 키로 암호화한 모든 볼륨을 읽을 수 없으므로 삭제 보호.
module "ebs_kms_key" {
  source = "../../aws-iac-terraform-module/module/security/aws-kms-workload/key"

  key_name                = "iac-ebs-default"
  description             = "EBS default encryption key (account/region default)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  prevent_destroy         = true

  key_administrators                = var.ebs_kms_key_administrators
  key_service_roles_for_autoscaling = var.ebs_kms_allow_autoscaling ? [local.asg_service_role] : []

  common_tags = var.common_tags
  site        = local.tag.site
  stack       = local.tag.stack
  key_target  = "ebs"
}

module "ebs_kms_alias" {
  source = "../../aws-iac-terraform-module/module/security/aws-kms-workload/alias"

  name          = "iac/ebs-default"
  target_key_id = module.ebs_kms_key.key_id
}

module "ebs_encryption_by_default" {
  source = "../../aws-iac-terraform-module/module/computing/aws-ebs-workload/encryption-by-default"
}

module "ebs_default_kms_key" {
  source  = "../../aws-iac-terraform-module/module/computing/aws-ebs-workload/default-kms-key"
  key_arn = module.ebs_kms_key.key_arn
}

# 계정 전체 설정이라 리전마다 이 단계를 실행하면 한 리전에서만 관리합니다.
module "s3_account_public_access_block" {
  source = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/account-public-access-block"
  count  = var.manage_s3_account_public_access_block ? 1 : 0
}

module "imds_defaults" {
  source = "../../aws-iac-terraform-module/module/computing/aws-instance-metadata-defaults-workload"
}
