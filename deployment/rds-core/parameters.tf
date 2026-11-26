############################################################
# 파라미터 그룹 값 (src/<name>.parameters.csv 또는 tfvars parameters, 둘 중 하나)
#   CSV 열: no,name,value,apply_method,memo  (형식: module repo module/_rds_parameters_csv, 예제: src/parameters.example.csv)
############################################################
locals {
  parameters_csv_file = "${var.src_dir}/${var.name}.parameters.csv"
  parameters_csv      = var.parameters_csv != null ? var.parameters_csv : (fileexists(local.parameters_csv_file) ? file(local.parameters_csv_file) : "")
}

module "parameters_csv" {
  source = "../../../aws-iac-terraform-module/module/_rds_parameters_csv"

  csv                = local.parameters_csv
  source_name        = "${var.src_label}/${var.name}.parameters.csv"
  other_source_count = length(var.parameters)
}

locals {
  parameters = length(var.parameters) > 0 ? var.parameters : module.parameters_csv.parameters
}
