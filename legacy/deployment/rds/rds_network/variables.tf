variable "module_repo_url" {
  description = "Module Repository URL"
  type        = string
  default     = ""
}

variable "azs" {
  description = "rds availability zones"
  type        = list(string)
  default     = []
}

variable "resource_prefix" {
  description = "Resource Prefix"
  type        = string
  default     = "bg"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = ""
}

variable "vpc_secondary_cidr" {
  description = "VPC Secondary CIDR"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common Tags"
  type        = map(string)
  default     = {}
}

variable "nat_gateway_id" {
  description = "NAT Gateway ID"
  type        = list(string)
  default     = []
}

variable "tgw_route_target_ips" {
  description = "TGW Route Target IPs"
  type        = list(string)
  default     = []
}

variable "attachment_tgw" {
  description = "Attachment TGW"
  type        = string
  default     = ""
}