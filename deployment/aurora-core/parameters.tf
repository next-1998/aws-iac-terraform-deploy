############################################################
# 파라미터 그룹 값 (CSV 두 개, 열: no,name,value,apply_method,memo)
#   src/<name>.cluster-parameters.csv : 클러스터 파라미터 그룹 (예: 문자셋, 시간대, 로그 설정 대부분)
#   src/<name>.parameters.csv         : 인스턴스 파라미터 그룹 (tfvars parameters로 넣어도 됨, 둘 다 넣으면 막힘)
############################################################
locals {
  parameters_csv_file         = "${var.src_dir}/${var.name}.parameters.csv"
  parameters_csv              = var.parameters_csv != null ? var.parameters_csv : (fileexists(local.parameters_csv_file) ? file(local.parameters_csv_file) : "")
  cluster_parameters_csv_file = "${var.src_dir}/${var.name}.cluster-parameters.csv"
  cluster_parameters_csv      = var.cluster_parameters_csv != null ? var.cluster_parameters_csv : (fileexists(local.cluster_parameters_csv_file) ? file(local.cluster_parameters_csv_file) : "")
}

module "parameters_csv" {
  source = "../../../aws-iac-terraform-module/module/_rds_parameters_csv"

  csv                = local.parameters_csv
  source_name        = "${var.src_label}/${var.name}.parameters.csv"
  other_source_count = length(var.parameters)
}

module "cluster_parameters_csv" {
  source = "../../../aws-iac-terraform-module/module/_rds_parameters_csv"

  csv                = local.cluster_parameters_csv
  source_name        = "${var.src_label}/${var.name}.cluster-parameters.csv"
  other_source_count = 0
}

locals {
  parameters         = length(var.parameters) > 0 ? var.parameters : module.parameters_csv.parameters
  cluster_parameters = module.cluster_parameters_csv.parameters
}
