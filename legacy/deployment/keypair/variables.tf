variable "module_repo_url" {
  description = "Repository Path 변수"
  type        = string
  default     = "../.."
}

variable "resource_tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
  default     = {}
}

variable "common_tags" {
  description = "A map of tags to add to all resources."
  type        = map(string)
  default     = {}
}

variable "local_keypair_name" {
  description = "Local Keypair Name"
  type        = string
  default     = "local-key"
}

variable "service_keypair_name" {
  description = "Service Keypair Name"
  type        = string
  default     = "service-key"
}