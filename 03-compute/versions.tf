terraform {
  required_version = ">= 1.17" # 최신 버전 기준 (tf1.17-aws6 브랜치)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.74.0"
    }
  }

  # state 저장 위치: 00-bootstrap 버킷의 <site>/<단계>/terraform.tfstate
  # terraform init -backend-config=backend.hcl  (backend.hcl.example 참고)
  backend "s3" {}
}

provider "aws" {
  region = var.region

  # 사이트 공통 태그 (변경 태그). 고정 태그는 각 모듈이 붙입니다.
  default_tags {
    tags = merge(var.common_tags, {
      Site        = var.site
      Environment = var.environment
    })
  }
}
