variable "resource_prefix" {
  description = "Resource Prefix"
  type = string
}

variable "common_tags" {
  description = "Common Tags"
  type = map(string)
}

variable "module_repo_url" {
  description = "Module Repository URL"
  type = string
}

variable "resource_tags" {
  description = "Resource Tags"
  type = map(string)
  default = {}
}

variable "vpc_id" {
  description = "VPC ID"
  type = string
}

variable "pub_subnet_ids" {
  description = "Public Subnet IDs"
  type = list(string)
}

variable "pri_subnet_ids" {
  description = "Private Subnet IDs"
  type = list(string)
}

variable "vpc_primary_cidr" {
  description = "VPC Primary CIDR"
  type = string
}

variable "vpc_secondary_cidr" {
  description = "VPC Secondary CIDR"
  type = string
}

