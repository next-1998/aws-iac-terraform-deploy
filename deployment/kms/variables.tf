variable "region" {
  description = "Region where the resource(s) will be managed. Defaults to the Region set in the provider configuration"
  type        = string
  default     = null
}

variable "common_tags" {
  description = "Common Tags"
  type        = map(string)
  default     = {}
}

variable "resource_prefix" {
  description = "Resource Prefix"
  type        = string
  default     = null
}

variable "resource_tags" {
  description = "Resource Tags"
  type = map(string)
  default = {}
}
