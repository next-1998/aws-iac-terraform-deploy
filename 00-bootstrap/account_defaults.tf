############################################################
# 계정·리전 보안 기본값 (필수)
#   - EBS: 기본 암호화 켜기 + 기본 키를 CMK로 지정 (kms.tf의 ebs: 중앙 키 또는 이 계정 키)
#          kms_key_id를 주지 않은 모든 새 EBS 볼륨이 이 CMK로 암호화됩니다.
#   - S3 : 계정 단위 퍼블릭 접근 차단 (계정 전체, 버킷 설정보다 우선)
#   - EC2: 인스턴스 메타데이터 기본값 IMDSv2 필수
#   - AWS Backup: 백업할 리소스 유형 사용 설정 (지원하는 모든 유형 켜기. 볼트·플랜·대상은 02-shared)
#   EBS, IMDS, AWS Backup 설정은 리전 단위라 이 단계를 실행하는 리전마다 적용됩니다.
#   이미 만들어진 볼륨·인스턴스는 바뀌지 않습니다 (새로 만드는 것부터 적용).
############################################################

module "ebs_encryption_by_default" {
  source = "../../aws-iac-terraform-module/module/computing/aws-ebs-workload/encryption-by-default"
}

module "ebs_default_kms_key" {
  source  = "../../aws-iac-terraform-module/module/computing/aws-ebs-workload/default-kms-key"
  key_arn = local.kms_key_arns.ebs
}

# 계정 전체 설정이라 리전마다 이 단계를 실행하면 한 리전에서만 관리합니다.
module "s3_account_public_access_block" {
  source = "../../aws-iac-terraform-module/module/storage/aws-s3-workload/account-public-access-block"
  count  = var.manage_s3_account_public_access_block ? 1 : 0
}

module "imds_defaults" {
  source = "../../aws-iac-terraform-module/module/computing/aws-instance-metadata-defaults-workload"
}

# 리소스 유형 사용 설정 (리전 단위). destroy해도 설정은 그대로 남습니다 (Terraform 관리만 해제)
module "backup_region_settings" {
  source = "../../aws-iac-terraform-module/module/management/aws-backup-workload/region-settings"

  resource_types = var.backup_resource_types
}
