############################################################
# EC2 (2차 조합: 목적 리소스)
############################################################

module "ec2" {
  source = "../../../aws-iac-terraform-module/module/computing/aws-instance-workload"

  name                 = local.prefix
  iam_instance_profile = module.instance_profile.name
  key_name             = one(data.aws_key_pair.this[*].key_name)

  ami                    = var.ami
  instance_type          = var.instance_type
  subnet                 = var.common.subnet_ids[local.instance_az]
  vpc_security_group_ids = [var.common.common_sg_id, module.sg.securitygroup_id] # 공통 SG(서버 접근) + 개별 SG(서비스)

  volume_size = local.root_volume_size # 이미지 루트 크기 이상. 자동 증설로 늘어난 실제 크기가 더 크면 그 값 (autogrow.tf)
  encrypted   = true
  kms_key_id  = var.kms_key_id
  # 루트 볼륨만 (데이터 볼륨은 volumes.tf)
  # 보호(운영): 서버를 지워도 루트 볼륨은 남김 / 테스트(보호 끔): 서버와 같이 삭제
  root_delete_on_termination = !var.protect_volumes

  user_data = var.user_data

  common_tags = var.common_tags
  # 리소스 생성 시 태그: 주말 중지 대상 여부, 서비스 그룹(자동 확장 시 Agent 설치 대상·지표 묶음), EBS 자동 증설 허용(루트 볼륨에도 붙음)
  resource_tags = merge(local.resource_tags, {
    WEEKEND_STOP_ENABLE = tostring(var.weekend_stop_enable)
    ServiceGroup        = local.prefix
  }, local.grow_any ? { (local.grow_tag) = "true" } : {}, { for p in var.backup_plans : "Backup-${p}" => "true" })
  site       = local.site
  stack      = var.name
  key_target = local.key
}

# key pair (선택): 담당자가 콘솔에서 만든 key pair를 이름으로 지정 (Terraform은 키를 만들지 않음 → state·Git에 개인 키 없음)
#   이 계정·리전에 없는 이름이면 plan에서 실패
data "aws_key_pair" "this" {
  count    = var.key_pair_name == null ? 0 : 1
  key_name = var.key_pair_name
}
