############################################################
# 00-bootstrap — 계정·리전마다 한 번 실행
#
# 이 단계의 state는 로컬(terraform.tfstate)에 둡니다.
# 다른 단계의 state를 저장할 버킷을 이 단계가 만들기 때문입니다.
# 만든 뒤 이 state도 버킷으로 옮기려면 README의 "state 옮기기"를 참고하세요.
############################################################
terraform {
  required_version = ">= 1.10" # S3 자체 잠금(use_lockfile) 지원 버전

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.100.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = var.common_tags
  }
}
