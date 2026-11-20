variable "vpc_id" {
  description = "VPC ID"
  type = string
}

variable "vpc_primary_cidr" {
  description = "VPC Primary CIDR"
  type = string
}

variable "vpc_secondary_cidr" {
  description = "VPC Secondary CIDR"
  type = string
}

variable "db_engine" {
  description = "DB Engine"
  type = string
}

variable "common_tags" {
  description = "Common Tags"
  type = map(string)
}

variable "resource_tags" {
  description = "Resource Tags"
  type = map(string)
}

variable "replica_mode" {
  description = "Replica Mode"
  type = string
  default = false
}