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

variable "subnet_cidrs" {
  description = "서브넷 CIDR 직접 입력 (용도 → { AZ 끝 글자 → CIDR }). null이면 layout_version 배치 규칙으로 계산. 설명: deployment/network-base/variables.tf"
  type        = map(map(string))
  default     = null
}

variable "purpose_subnets" {
  description = "용도 지정 서브넷 (이름 → { cidrs = { AZ 끝 글자 → CIDR }, use = [종류] }). 여러 종류의 리소스가 함께 씀. 설명: deployment/network-base/variables.tf"
  type = map(object({
    cidrs = map(string)
    use   = list(string)
  }))
  default = {}
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
