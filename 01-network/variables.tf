############################################################
# 01-network 입력 (설명과 제약 사항은 terraform.tfvars 주석과 deployment/network-base/variables.tf 참고)
############################################################
variable "layout_version" {
  type    = string
  default = "v1"
}

variable "vpc_cidrs" {
  type = list(object({ cidr = string, role = string }))
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

variable "tgw_id" {
  type    = string
  default = null
}

variable "corp_cidrs" {
  type    = list(string)
  default = []
}

variable "peerings" {
  type = map(object({
    peering_connection_id = string
    cidrs                 = list(string)
  }))
  default = {}
}

variable "prefix_lists" {
  type = map(object({
    max_entries = number
    entries     = map(string)
  }))
  default = {}
}

variable "eks_placement" {
  type    = string
  default = null
}

variable "eks_subnet" {
  type    = number
  default = 23
}

variable "manual_subnets" {
  type = list(object({
    name    = string
    az      = string
    cidr    = string
    purpose = string
  }))
  default = []
}

variable "interface_endpoints" {
  type    = list(string)
  default = []
}

variable "gateway_endpoints" {
  type    = list(string)
  default = []
}

variable "endpoint_skip_if_exists" {
  type    = bool
  default = true
}

variable "root_domain" {
  type    = string
  default = ""
}

variable "resolver_rule_id" {
  type    = string
  default = null
}

variable "enable_flow_logs" {
  type    = bool
  default = true
}
