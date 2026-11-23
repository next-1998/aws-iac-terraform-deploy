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