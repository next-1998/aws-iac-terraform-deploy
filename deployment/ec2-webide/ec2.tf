############################################################
# EC2 (instance profile 포함)
############################################################

module "ec2" {
  source = "../../../aws-iac-terraform-module/module/computing/aws-instance-workload"

  name         = local.prefix
  profile_name = "${local.prefix}-profile"
  role         = module.role.role

  ami                    = var.ami
  instance_type          = var.instance_type
  subnet                 = var.common.subnet_ids[local.instance_az]
  vpc_security_group_ids = [var.common.common_sg_id, module.sg.securitygroup_id] # 공통 SG(서버 접근) + 개별 SG(서비스)

  volume_size = var.root_volume_size
  encrypted   = true
  kms_key_id  = var.kms_key_id
  ebs_block_device = {
    ebs_block_device = [for v in var.ebs_volumes : {
      device_name           = v.device_name
      volume_size           = v.volume_size
      volume_type           = v.volume_type
      encrypted             = true
      kms_key_id            = var.kms_key_id
      delete_on_termination = false
    }]
  }

  user_data = var.user_data

  common_tags = var.common_tags
  # 리소스 생성 시 태그: 주말 중지 대상 여부
  resource_tags = merge(local.resource_tags, {
    WEEKEND_STOP_ENABLE = tostring(var.weekend_stop_enable)
  })
  site       = local.site
  stack      = var.name
  key_target = local.key

  # ec2-common의 endpoint와 라우팅이 먼저 준비되도록
  depends_on = [terraform_data.common_ready]
}

# ec2-common의 endpoint, 라우트가 만들어진 뒤에 인스턴스를 만들기 위한 순서 고정용
resource "terraform_data" "common_ready" {
  input = var.common.ready
}
