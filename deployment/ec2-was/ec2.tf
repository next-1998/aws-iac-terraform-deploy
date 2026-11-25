############################################################
# EC2 (2차 조합: 목적 리소스)
############################################################

module "ec2" {
  source = "../../../aws-iac-terraform-module/module/computing/aws-instance-workload"

  name                 = local.prefix
  iam_instance_profile = module.instance_profile.name

  ami                    = var.ami
  instance_type          = var.instance_type
  subnet                 = var.common.subnet_ids[local.instance_az]
  vpc_security_group_ids = [var.common.common_sg_id, module.sg.securitygroup_id] # 공통 SG(서버 접근) + 개별 SG(서비스)

  volume_size = var.root_volume_size # 이미지 루트 크기 이상
  encrypted   = true
  kms_key_id  = var.kms_key_id
  # 루트 볼륨만 (데이터 볼륨은 volumes.tf)
  # 보호(운영): 서버를 지워도 루트 볼륨은 남김 / 테스트(보호 끔): 서버와 같이 삭제
  root_delete_on_termination = !var.protect_volumes

  user_data = var.user_data

  common_tags = var.common_tags
  # 리소스 생성 시 태그: 주말 중지 대상 여부, 서비스 그룹(자동 확장 시 Agent 설치 대상·지표 묶음)
  resource_tags = merge(local.resource_tags, {
    WEEKEND_STOP_ENABLE = tostring(var.weekend_stop_enable)
    ServiceGroup        = local.prefix
  })
  site       = local.site
  stack      = var.name
  key_target = local.key
}
