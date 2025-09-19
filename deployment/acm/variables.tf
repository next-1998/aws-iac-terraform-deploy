variable "root_domain" {
  description = "Root Domain"
  type = string
}

variable "cluster_name" {
  description = "Cluster Name"
  type = string
}

variable "module_repo_url" {
  description = "Module Repository URL"
  type = string
}

variable "route53_zone_zone_id" {
  description = "Route53 Zone ID"
  type = any
  default = {}
}

variable "common_tags" {
  description = "Common Tags"
  type = map(string)
}