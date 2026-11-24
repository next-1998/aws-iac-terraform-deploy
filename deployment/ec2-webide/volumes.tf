############################################################
# 데이터 볼륨 (2차 조합)
#   EC2는 루트 볼륨만으로 만들고, 데이터 볼륨은 따로 만들어 붙입니다.
#   - 크기는 tfvars(ebs_volumes)로만 바꿉니다: 서버 교체 없이 늘어남 (줄일 수 없음)
#     AWS 콘솔에서 바꾸면 다음 apply가 tfvars 값으로 되돌리려다 실패하므로 tfvars도 같이 맞춤
#   - 서버를 다시 만들어도 볼륨은 남아 다시 붙음
#   - 붙인 볼륨은 포맷·마운트되지 않은 상태 (마운트는 별도)
#   - AMI에 포함된 볼륨은 이미지대로 만들어지고 여기서 관리하지 않음 (인스턴스 모듈 ignore_changes)
############################################################
locals {
  # 장치 이름이 키: 바꾸면 그 볼륨이 다시 만들어짐 (데이터 없음)
  data_volumes = { for v in var.ebs_volumes : v.device_name => v }
}

module "data_volume" {
  source   = "../../../aws-iac-terraform-module/module/computing/aws-ebs-workload/volume"
  for_each = local.data_volumes

  name              = "${local.prefix}-data-${basename(each.key)}"
  availability_zone = local.instance_az
  volume_size       = each.value.volume_size
  volume_type       = each.value.volume_type
  encrypted         = true
  kms_key_id        = var.kms_key_id
  # 보호(운영): terraform destroy로 지울 수 없음 / 테스트(보호 끔): 같이 삭제
  prevent_destroy = var.protect_volumes

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_data_${lower(replace(basename(each.key), "/[^a-zA-Z0-9]/", "_"))}"
}

module "data_volume_attachment" {
  source   = "../../../aws-iac-terraform-module/module/computing/aws-ebs-workload/attachment"
  for_each = local.data_volumes

  device_name = each.key
  volume_id   = module.data_volume[each.key].id
  instance_id = module.ec2.ec2_instance.id
}

############################################################
# 데이터 볼륨 마운트 (SSM 연결로 src/mount_volumes.sh 실행)
#   mount_point가 있는 볼륨만. 볼륨 연결 결과를 값으로 참조하므로 붙은 뒤에 실행됨 (depends_on 없음)
#   볼륨을 추가하거나 크기를 바꾸면 입력(VOLUMES)이 바뀌어 다시 실행됨
#   (새 볼륨은 포맷·마운트, 늘린 볼륨은 파일시스템 확장, 이미 마운트된 볼륨은 건너뜀)
############################################################
locals {
  mount_volumes = {
    for k, v in local.data_volumes : k => v if v.mount_point != null
  }
  # <볼륨 ID>|<장치 이름>|<마운트 경로>|<파일시스템>|<fstab 옵션>|<크기>
  mount_lines = [
    for k, v in local.mount_volumes :
    join("|", [module.data_volume_attachment[k].attachment.volume_id, k, trimsuffix(v.mount_point, "/"), v.fs_type, v.mount_options, tostring(v.volume_size)])
  ]
}

module "volume_mount" {
  source = "../../../aws-iac-terraform-module/module/management/aws-ssm-association-workload"

  associations = length(local.mount_volumes) > 0 ? {
    "${local.prefix}-mount" = {
      instance_ids = [module.ec2.ec2_instance.id]
      parameters = {
        commands = join("\n", [
          "VOLUMES='${join("\n", local.mount_lines)}'",
          file("${path.module}/src/mount_volumes.sh"),
        ])
      }
    }
  } : {}
}
