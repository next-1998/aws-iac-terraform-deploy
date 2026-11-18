############################################################
# 조합 코드 테스트용 사이트 구성 (실제 배포용이 아님)
# 실행: terraform -chdir=tests init && terraform -chdir=tests test
# mock provider를 쓰므로 AWS에 접속하지 않습니다.
############################################################

terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = { source = "hashicorp/aws", version = "5.100.0" }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

variable "vpc_cidrs" {
  type = list(object({ cidr = string, role = string }))
  default = [
    { cidr = "10.227.0.0/24", role = "routable" },
    { cidr = "100.64.0.0/16", role = "internal" },
  ]
}

variable "az_count" {
  type    = number
  default = 2
}

variable "was_enable_alb" {
  type    = bool
  default = true
}

variable "nat_per_az" {
  type    = bool
  default = true
}

variable "enable_internet" {
  type    = bool
  default = true
}

variable "enable_ssm" {
  type    = bool
  default = true
}

variable "extra_endpoints" {
  type    = list(string)
  default = ["s3"]
}

variable "common_sg_ingress" {
  type    = any
  default = []
}

module "network_base" {
  source           = "../deployment/network-base"
  site             = "simple"
  vpc_name         = "simple-vpc"
  vpc_cidrs        = var.vpc_cidrs
  az_count         = var.az_count
  nat_per_az       = var.nat_per_az
  enable_internet  = var.enable_internet
  tgw_id           = "tgw-0123456789abcdef0"
  tgw_route_cidrs  = ["10.0.0.0/8"]
  root_domain      = "example.com"
  resolver_rule_id = "rslvr-rr-0123456789"
  common_tags      = { Owner = "platform-team" }
}

module "ec2_common" {
  source            = "../deployment/ec2-common"
  base              = module.network_base.contract
  slot              = 0
  enable_ssm        = var.enable_ssm
  endpoints         = var.extra_endpoints
  common_sg_ingress = var.common_sg_ingress
  common_tags       = { Owner = "platform-team" }
}

module "ec2_was" {
  source              = "../deployment/ec2-was"
  common              = module.ec2_common.contract
  ami                 = "ami-0123456789abcdef0"
  enable_alb          = var.was_enable_alb
  alb_certificate_arn = "arn:aws:acm:ap-northeast-2:111111111111:certificate/x"
  alb_record_name     = "web"
  weekend_stop_enable = true
  ebs_volumes         = [{ device_name = "/dev/xvdb", volume_size = 20 }]
  common_tags         = { Owner = "platform-team" }
}

module "ec2_webide" {
  source        = "../deployment/ec2-webide"
  common        = module.ec2_common.contract
  ami           = "ami-0123456789abcdef0"
  ingress_rules = [{ from_port = 8080, to_port = 8080, protocol = "tcp", cidr_blocks = ["10.0.0.0/8"] }]
}

locals {
  all_cidrs = concat(
    values(module.network_base.contract.edge_subnet_cidrs),
    values(module.network_base.contract.transit_subnet_cidrs),
    values(module.ec2_common.subnet_cidrs),
  )
  # 두 CIDR을 더 큰 쪽 prefix로 잘랐을 때 같은 네트워크면 겹침
  overlaps = flatten([
    for i, a in local.all_cidrs : [
      for j, b in local.all_cidrs : "${a} <> ${b}"
      if i < j && cidrsubnet(format("%s/%d", cidrhost(a, 0), min(tonumber(split("/", a)[1]), tonumber(split("/", b)[1]))), 0, 0) == cidrsubnet(format("%s/%d", cidrhost(b, 0), min(tonumber(split("/", a)[1]), tonumber(split("/", b)[1]))), 0, 0)
    ]
  ])
}

output "network_type" { value = module.network_base.contract.network_type }
output "has_private_nat" { value = module.network_base.contract.has_private_nat }
output "edge" { value = module.network_base.contract.edge_subnet_cidrs }
output "transit" { value = module.network_base.contract.transit_subnet_cidrs }
output "public_nat_ids" { value = module.network_base.contract.public_nat_ids }
output "private_nat_ids" { value = module.network_base.contract.private_nat_ids }
output "ec2_subnets" { value = module.ec2_common.subnet_cidrs }
output "ec2_rts" { value = module.ec2_common.route_table_ids }
output "overlaps" { value = local.overlaps }
output "endpoints" { value = keys(module.ec2_common.endpoints_created) }
output "endpoints_skipped" { value = module.ec2_common.endpoints_skipped }
output "common_sg_id" { value = module.ec2_common.common_sg_id }
output "common_sg_rules" { value = module.ec2_common.common_sg_ingress_rules }
output "was_sgs" { value = module.ec2_was.security_group_ids }
output "webide_sgs" { value = module.ec2_webide.security_group_ids }
output "was_alb" { value = module.ec2_was.alb_arn != null }
output "webide_alb" { value = module.ec2_webide.alb_arn == null }
output "base_contract" { value = module.network_base.contract }
output "ec2_common_contract" { value = module.ec2_common.contract }
output "azs" { value = module.network_base.contract.azs }
