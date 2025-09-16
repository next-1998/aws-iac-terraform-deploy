variable "module_repo_url" {
  description = "Module Repository URL"
  type = string
}

variable "vpc_name" {
  description = "VPC Name"
  type = string
}

variable "cluster_name" {
  description = "Cluster Name"
  type = string
}

variable "resource_prefix" {
  description = "Resource Prefix"
  type = string
}

variable "common_tags" {
  description = "Common Tags"
  type = map(string)
}

variable "vpc_primary_cidr" {
  description = "VPC Primary CIDR"
  type = string
}

variable "vpc_secondary_cidr" {
  description = "VPC Secondary CIDR"
  type = string
}

variable "azs" {
  description = "A list of availability zones names or ids in the region"
  type = list(string)
}

variable "root_domain" {
  description = "Root Domain"
  type = string
}

variable "resource_tags" {
  description = "Resource Tags"
  type = map(string)
  default = {}
}

variable "tgw_route_target_ips" {
  description = "TGW Route Target IPs"
  type = list(string)
  default = []
}
