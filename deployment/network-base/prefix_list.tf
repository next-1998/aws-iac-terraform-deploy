############################################################
# prefix list (종류 고정 없음, 사이트 tfvars에서 필요한 것만 추가)
#   SG 규칙에서 IP 대신 이름으로 참조합니다 (02-compute 등의 SG 입력에서 prefix_lists = ["access_ctl"]).
#   항목을 바꾸면 prefix list만 바뀌고, 참조하는 모든 SG에 자동으로 반영됩니다.
############################################################
module "prefix_list" {
  source = "../../../aws-iac-terraform-module/module/network/aws-prefixlist-workload"

  name_prefix  = var.site
  prefix_lists = var.prefix_lists

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = null
}
