############################################################
# 입력 검사 (리전 정보가 필요해서 variable validation 대신 precondition 사용)
############################################################
resource "terraform_data" "checks" {
  lifecycle {
    precondition {
      condition     = var.az_count <= length(local.region_azs)
      error_message = "az_count(${var.az_count})가 이 리전의 사용 가능한 AZ 수(${length(local.region_azs)})보다 큽니다. 사용 가능 AZ: ${join(", ", local.region_azs)}"
    }
  }
}
