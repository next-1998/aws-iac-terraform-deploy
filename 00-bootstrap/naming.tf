############################################################
# 이름 규칙 (중앙 관리)
#   <회사>-<서비스>-<환경>-<리전 코드>-<리소스 유형>-<리소스 이름>-<순번 2자리>[-<AZ>]
#   예) hw-iac-dev-an2-ec2-squid-01-a, hw-iac-dev-an2-sg-squid-01
#   앞부분(접두어)은 여기서 정하고 Parameter Store /iac/_account/00-bootstrap/naming 에 남깁니다.
#   다른 단계는 이 값을 읽어 뒤에 <유형>-<이름>-<순번>[-<AZ>]만 붙입니다.
############################################################
locals {
  # 리전 코드: 대륙 첫 글자 + 방향 첫 글자(들) + 번호. 겹치는 리전이 있어 표로 고정 (없는 리전은 region_code로 지정)
  region_codes = {
    "ap-northeast-1" = "an1", "ap-northeast-2" = "an2", "ap-northeast-3" = "an3",
    "ap-southeast-1" = "as1", "ap-southeast-2" = "as2", "ap-south-1" = "ap1",
    "us-east-1"      = "ue1", "us-east-2" = "ue2", "us-west-1" = "uw1", "us-west-2" = "uw2",
    "eu-west-1"      = "ew1", "eu-central-1" = "ec1", "ca-central-1" = "cc1", "sa-east-1" = "se1",
  }
  region_code = coalesce(var.naming.region_code, lookup(local.region_codes, local.region, "unknown"))

  # 이름 앞부분 (모든 단계 공통)
  name_prefix = join("-", [var.naming.company, var.naming.service, var.naming.env, local.region_code])

  # 이 단계 리소스 이름: <접두어>-<유형>-<이름>-01
  n = {
    state_bucket = "${local.name_prefix}-s3-tfstate-01"
    log_bucket   = "${local.name_prefix}-s3-logs-01"
  }
}
