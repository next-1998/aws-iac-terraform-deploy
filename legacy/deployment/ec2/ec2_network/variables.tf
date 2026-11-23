variable "module_repo_url" {
  description = "Module Repository URL"
  type        = string
  default     = ""
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

variable "pri_nat_gw" {
  description = "Private NAT Gateway"
  type        = string
  default     = ""
}

variable "pub_nat_gw" {
  description = "Public NAT Gateway"
  type        = string
  default     = ""
}

variable "pri_subnet_ids" {
  description = "Private Subnet IDs"
  type        = list(string)
  default     = []
}

variable "tgw_route_target_ips" {
  description = "TGW Route Target IPs"
  type        = list(string)
  default     = []
}

variable "common_tags" {
  description = "Common Tags"
  type        = map(string)
  default     = {}
}

variable "azs" {
  description = "AZs"
  type        = list(string)
  default     = []
}

variable "vpc_secondary_cidr" {
  description = "VPC Secondary CIDR"
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "Cluster Name"
  type        = string
  default     = ""
}
