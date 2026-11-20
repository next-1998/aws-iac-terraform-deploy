variable "elasticache_name" {
  description = "Elasticache Name"
  type        = string
  default     = ""
}

variable "elasticache_port" {
  description = "Elasticache Port"
  type        = number
  default     = 6379
}

variable "elasticache_engine" {
  description = "Elasticache Engine"
  type        = string
  default     = ""
}

variable "elasticache_engine_version" {
  description = "Elasticache Engine Version"
  type        = string
  default     = ""
}

variable "elasticache_node_type" {
  description = "Elasticache Node Type"
  type        = string
  default     = ""
}

variable "elasticache_cache_node_number" {
  description = "Elasticache Cache Node Number"
  type        = number
  default     = 1
}

variable "root_domain" {
  description = "Root Domain"
  type        = string
  default     = ""
}

variable "module_repo_url" {
  description = "Module Repository URL"
  type        = string
  default     = ""
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common Tags"
  type        = map(string)
  default     = {}
}

variable "vpc_secondary_cidr" {
  description = "VPC Secondary CIDR"
  type        = string
  default     = ""
}

variable "elasticache_parameter_group_name" {
  description = "Elasticache Parameter Group Name"
  type        = string
  default     = ""
}

variable "elasticache_subnet_group_name" {
  description = "Cache Subnet IDs"
  type        = list(string)
  default     = []
}

variable "resource_tags" {
  description = "Resource Tags"
  type        = map(string)
  default     = {}
}