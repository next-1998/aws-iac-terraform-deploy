############################################################
# prefix list (종류 고정 없음, 사이트 tfvars에서 필요한 것만 추가)
#   SG 규칙에서 IP 대신 이름으로 참조합니다 (02-resource의 SG 입력에서 prefix_lists = ["access_ctl"]).
#   항목을 바꾸면 prefix list만 바뀌고, 참조하는 모든 SG에 자동으로 반영됩니다.
#   주의: 참조하는 SG 규칙 하나가 max_entries만큼 SG 규칙 한도(기본 60)를 씁니다.
############################################################
resource "aws_ec2_managed_prefix_list" "this" {
  for_each = var.prefix_lists

  name           = "${var.site}-${replace(each.key, "_", "-")}"
  address_family = "IPv4"
  max_entries    = each.value.max_entries

  dynamic "entry" {
    for_each = each.value.entries
    content {
      cidr        = entry.key
      description = entry.value
    }
  }

  tags = module.tags.tags["pl_${each.key}"]
}
