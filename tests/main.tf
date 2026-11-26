############################################################
# 조합 코드 통합 테스트용 구성 (실제 배포용이 아님)
#   단계(01, 02)를 Parameter Store 없이 직접 이어서 대역 배치와 규칙을 검사합니다.
# 실행: terraform -chdir=tests init && terraform -chdir=tests test
# mock provider를 쓰므로 AWS에 접속하지 않습니다.
############################################################

terraform {
  required_version = ">= 1.17"
  required_providers {
    aws = { source = "hashicorp/aws", version = "6.74.0" }
  }
}

provider "aws" {
  region = "ap-northeast-2"
}

variable "vpc_cidrs" {
  type    = list(object({ cidr = string, role = string }))
  default = [{ cidr = "10.227.0.0/23", role = "routable" }]
}

variable "az_count" {
  type    = number
  default = 2
}

variable "enable_public" {
  type    = bool
  default = false
}

variable "nat_per_az" {
  type    = bool
  default = true
}

variable "eks_placement" {
  type    = string
  default = null
}

variable "manual_subnets" {
  type    = any
  default = []
}

variable "interface_endpoints" {
  type    = list(string)
  default = ["ssm", "ssmmessages", "ec2messages", "logs", "monitoring"]
}

variable "common_sg_rules_csv" {
  description = "ec2-common SG 규칙 CSV 내용 (기본: 헤더만 = 규칙 없음)"
  type        = string
  default     = "sg,no,direction,protocol,from_port,to_port,source,description,memo\n"
}

variable "enable_certificate" {
  type    = bool
  default = false
}

variable "enable_weekend_stop" {
  type    = bool
  default = false
}

variable "was_enable_alb" {
  type    = bool
  default = true
}

variable "was_sg_rules_csv" {
  type    = string
  default = null
}

variable "was_alb_internal" {
  type    = bool
  default = true
}

module "network_base" {
  source = "../deployment/network-base"

  site          = "simple"
  vpc_name      = "simple-vpc"
  name_prefix   = "hw-iac-dev-an2"
  vpc_cidrs     = var.vpc_cidrs
  az_count      = var.az_count
  enable_public = var.enable_public
  nat_per_az    = var.nat_per_az
  tgw_id        = "tgw-0123456789abcdef0"
  corp_cidrs    = ["10.0.0.0/8"]
  prefix_lists = {
    access_ctl = { max_entries = 5, entries = { "10.185.66.10/32" = "server-access-control" } }
    admin      = { max_entries = 5, entries = { "10.185.66.0/24" = "admin-pc" } }
    corp       = { max_entries = 5, entries = { "10.0.0.0/8" = "corp" } }
    corp_proxy = { max_entries = 2, entries = { "10.185.1.10/32" = "proxy" } }
  }
  eks_placement       = var.eks_placement
  manual_subnets      = var.manual_subnets
  interface_endpoints = var.interface_endpoints
  gateway_endpoints   = ["s3"]
  root_domain         = "example.com"
  resolver_rule_id    = "rslvr-rr-0123456789"
  flow_log_bucket_arn = "arn:aws:s3:::iac-logs-111111111111-ap-northeast-2"
  common_tags         = { Owner = "platform-team" }
}

module "shared_common" {
  source             = "../deployment/shared-common"
  network            = module.network_base.contract
  enable_certificate = var.enable_certificate
}

module "ec2_common" {
  source              = "../deployment/ec2-common"
  network             = module.network_base.contract
  sg_rules_csv        = var.common_sg_rules_csv
  enable_weekend_stop = var.enable_weekend_stop
}

module "ec2_was" {
  source              = "../deployment/ec2-was"
  common              = module.ec2_common.contract
  ami                 = "ami-0123456789abcdef0"
  enable_alb          = var.was_enable_alb
  alb_internal        = var.was_alb_internal
  alb_certificate_arn = "arn:aws:acm:ap-northeast-2:111111111111:certificate/x"
  alb_record_name     = "web"
  access_log_bucket   = "iac-logs-111111111111-ap-northeast-2"
  weekend_stop_enable = true
  ebs_volumes         = [{ device_name = "/dev/xvdb", volume_size = 20 }]
  sg_rules_csv        = var.was_sg_rules_csv
  peer_sg_ids         = { for k, v in local.purpose_sg_ids : k => v if !startswith(k, "was.") }
}

module "ec2_webide" {
  source       = "../deployment/ec2-webide"
  common       = module.ec2_common.contract
  ami          = "ami-0123456789abcdef0"
  sg_rules_csv = "sg,no,direction,protocol,from_port,to_port,source,description,memo\napp,1,ingress,tcp,80,80,pl:access_ctl,web ide,웹 IDE 접속\n"
  peer_sg_ids  = { for k, v in local.purpose_sg_ids : k => v if !startswith(k, "webide.") }
}

# 같은 단계 SG 이름표 (03-compute와 같은 방식)
locals {
  purpose_sg_ids = merge(
    { for k, v in module.ec2_was.sg_ids : "was.${k}" => v },
    { for k, v in module.ec2_webide.sg_ids : "webide.${k}" => v },
  )
}

locals {
  c = module.network_base.contract

  all_cidrs = concat(
    flatten([for p, m in local.c.subnets.cidrs : values(m)]),
    values(local.c.subnets.eks_cidrs),
    [for s in var.manual_subnets : s.cidr],
  )
  # 두 CIDR을 더 큰 쪽 prefix로 잘랐을 때 같은 네트워크면 겹침
  overlaps = flatten([
    for i, a in local.all_cidrs : [
      for j, b in local.all_cidrs : "${a} <> ${b}"
      if i < j && cidrsubnet(format("%s/%d", cidrhost(a, 0), min(tonumber(split("/", a)[1]), tonumber(split("/", b)[1]))), 0, 0) == cidrsubnet(format("%s/%d", cidrhost(b, 0), min(tonumber(split("/", a)[1]), tonumber(split("/", b)[1]))), 0, 0)
    ]
  ])
}

output "azs" { value = local.c.base.azs }
output "vpc_cidrs" { value = local.c.base.vpc_cidrs }
output "cidrs" { value = local.c.subnets.cidrs }
output "eks_cidrs" { value = local.c.subnets.eks_cidrs }
output "base_subnet_ids" { value = { for p, m in local.c.subnets.ids : p => keys(m) } }
output "public_nat_ids" { value = local.c.routing.public_nat_ids }
output "private_nat_ids" { value = local.c.routing.private_nat_ids }
output "prefix_list_ids" { value = local.c.routing.prefix_list_ids }
output "endpoint_ids" { value = keys(local.c.endpoints.ids) }
output "gateway_endpoints" { value = keys(local.c.endpoints.gateway) }
output "zone" { value = local.c.dns }
output "sizing" { value = module.network_base.sizing }
output "overlaps" { value = local.overlaps }
output "ec2_subnets" { value = module.ec2_common.subnet_cidrs }
output "ec2_rts" { value = module.ec2_common.route_table_ids }
output "common_sg_id" { value = module.ec2_common.common_sg_id }
output "common_sg_rules" { value = module.ec2_common.sg_rules }
output "webide_sg_rules" { value = module.ec2_webide.sg_rules }
output "was_sg_rules" { value = module.ec2_was.sg_rules }
output "purpose_sg_ids" { value = local.purpose_sg_ids }
output "was_sgs" { value = module.ec2_was.security_group_ids }
output "was_alb" { value = module.ec2_was.alb_arn != null }
output "webide_alb" { value = module.ec2_webide.alb_arn == null }
output "network_contract" { value = module.network_base.contract }
output "ec2_common_contract" { value = module.ec2_common.contract }
output "certificate_validation_records" { value = module.shared_common.validation_records }
output "weekend_stop" { value = module.ec2_common.weekend_stop }
