############################################################
# prefix list (종류 고정 없음, 사이트에 필요한 것만 추가)
#   SG 규칙에서 IP 대신 이름으로 참조합니다 (sg_rules.csv의 source = pl:<이름>).
#   항목을 바꾸면 prefix list만 바뀌고, 참조하는 모든 SG에 자동으로 반영됩니다.
#
#   입력은 둘 중 하나 (둘 다 넣으면 plan에서 막힘)
#     - src/prefix_lists.csv (권장, 엑셀로 관리)  형식: src/prefix_lists.example.csv, module repo module/_prefix_lists_csv
#     - 01-network tfvars의 prefix_lists
############################################################
locals {
  prefix_lists_csv_file = "${path.module}/src/prefix_lists.csv"
  prefix_lists_csv      = var.prefix_lists_csv != null ? var.prefix_lists_csv : (fileexists(local.prefix_lists_csv_file) ? file(local.prefix_lists_csv_file) : "")
}

module "prefix_lists_csv" {
  source = "../../../aws-iac-terraform-module/module/_prefix_lists_csv"

  csv                = local.prefix_lists_csv
  source_name        = "deployment/network-base/src/prefix_lists.csv"
  other_source_count = length(var.prefix_lists)
}

locals {
  prefix_lists = length(var.prefix_lists) > 0 ? var.prefix_lists : module.prefix_lists_csv.prefix_lists
}

module "prefix_list" {
  source = "../../../aws-iac-terraform-module/module/network/aws-prefixlist-workload"

  name_prefix  = var.site
  prefix_lists = local.prefix_lists

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = null
}
