variable "was_alb" {
  description = "The name of the WAS ALB"
  type        = string
  default     = null
}

variable "web_ide_alb" {
  description = "The name of the WEB IDE ALB"
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
  default     = null
}

variable "pub_subnet_ids" {
  description = "The IDs of the public subnets"
  type        = list(string)
  default     = null
}

variable "pri_subnet_ids" {
  description = "The IDs of the private subnets"
  type        = list(string)
  default     = null
}

variable "certificate_arn" {
  description = "The ARN of the certificate"
  type        = string
  default     = null
}

variable "ec2_was_id" {
  description = "The ID of the EC2 WAS"
  type        = string
  default     = null
}

variable "ec2_web_ide_id" {
  description = "The ID of the EC2 WEB IDE"
  type        = string
  default     = null
}

variable "was_name" {
  description = "The name of the WAS"
  type        = string
  default     = null
}

variable "web_ide_name" {
  description = "The name of the EC2 WEB IDE"
  type        = string
  default     = null
}

variable "resource_prefix" {
  description = "The prefix of the resource"
  type        = string
  default     = null
}

variable "common_tags" {
  description = "The tags of the resource"
  type        = map(string)
  default     = {}
}

variable "resource_tags" {
  description = "The tags of the resource"
  type        = map(string)
  default     = {}
}

variable "module_repo_url" {
  description = "Module Repository URL"
  type = string
}

variable "root_domain" {
  description = "Root Domain"
  type = string
}

variable "cluster_name" {
  description = "Cluster Name"
  type = string
}

variable "route53_zone_zone_id" {
  description = "Route53 Zone Zone ID"
  type = any
  default = {}
}
