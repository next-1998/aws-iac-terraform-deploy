variable "module_repo_url" {
  description = "Module Repository URL"
  type        = string
  default     = ""
}

##locals

variable "web_ide_name" {
  description = "Web IDE Instance Name"
  type        = string
  default     = "bg-web-ide"
}

variable "service_private_key" {
  description = "Service Private Key"
  type        = string
  default     = ""
}

variable "root_domain" {
  description = "Root Domain"
  type        = string
  default     = ""
}

variable "daytona_url" {
  description = "Daytona URL"
  type        = string
  default     = ""
}

variable "KEYCLOAK_ENDPOINT" {
  description = "Keycloak Endpoint"
  type        = string
  default     = ""
}

## role
variable "resource_prefix" {
  description = "Resource Prefix"
  type        = string
  default     = "bg"
}

## securitygroup
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

variable "resource_tags" {
  description = "Resource Tags"
  type        = map(string)
  default     = {}
}

variable "pub_subnet_ids" {
  description = "Public Subnet IDs"
  type        = list(string)
  default     = []
}

variable "pri_subnet_ids" {
  description = "Private Subnet IDs"
  type        = list(string)
  default     = []
}

variable "vpc_secondary_cidr" {
  description = "VPC Secondary CIDR"
  type        = string
  default     = ""
}

## data
variable "golden_image" {
  description = "Golden Image"
  type        = string
  default     = ""
}

variable "ami_owner_account" {
  description = "AMI Owner Account"
  type        = string
  default     = ""
}

## ec2 instance
variable "web_ide_instance_ami" {
  description = "Web IDE Instance AMI"
  type        = string
  default     = ""
}

variable "web_ide_instance_type" {
  description = "Web IDE Instance Type"
  type        = string
  default     = ""
}

variable "common_key_pair_name" {
  description = "Common Key Pair Name"
  type        = string
  default     = ""
}

## ec2
variable "cluster_name" {
  description = "Cluster Name"
  type        = string
  default     = ""
}

variable "KEYCLOAK_REALM" {
  description = "Keycloak Realm"
  type        = string
  default     = ""
}

variable "KEYCLOAK_CLIENT_ID" {
  description = "Keycloak Client ID"
  type        = string
  default     = ""
}

variable "KEYCLOAK_CLIENT_SECRET" {
  description = "Keycloak Client Secret"
  type        = string
  default     = ""
}

variable "KEYCLOAK_CLIENT_UUID" {
  description = "Keycloak Client UUID"
  type        = string
  default     = ""
}
