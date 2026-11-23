variable "module_repo_url" {
  description = "Module Repository URL"
  type        = string
  default     = ""
}

##locals
variable "local_public_key" {
  description = "Local Public Key"
  type        = string
  default     = ""
}

variable "service_public_key" {
  description = "Service Public Key"
  type        = string
  default     = ""
}

variable "was_name" {
  description = "WAS Name"
  type        = string
  default     = ""
}

##securitygroup
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

##ec2 instance

variable "resource_prefix" {
  description = "Resource Prefix"
  type        = string
  default     = "bg"
}

variable "was_instance_ami" {
  description = "Instance AMI"
  type        = string
  default     = "ami-04599ab1182cd7961"
}

variable "was_instance_type" {
  description = "Instance Type"
  type        = string
  default     = "t2.micro"
}

variable "instance_root_volume" {
  description = "Instance Root Volume"
  type        = number
  default     = 30
}

variable "availability_zone" {
  description = "Availability Zone"
  type        = string
  default     = "ap-northeast-2a"
}

variable "was_instance_log_volume" {
  description = "WAS Instance Log Volume"
  type        = number
  default     = 30
}

# variable "ebs_add_volume" {
#   description = "EBS Add Volume"
#   type        = map(any)
# #   ebs_add_volume = {
# #   log-volume = {
# #     name = "bg-was-log-volume"
# #     volume_size = 30
# #     device_name = "/dev/xvdc"
# #   }
# #   app-volume = {
# #     volume_size = 20
# #     device_name = "/dev/xvdb"
# #   }
# # }
#   default     = {}
# }

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

variable "was_instance_engine_volume_device_name" {
  description = "WAS Instance Engine Volume Device Name"
  type        = string
  default     = "/dev/xvdb"
}

variable "was_instance_log_volume_device_name" {
  description = "WAS Instance Log Volume Device Name"
  type        = string
  default     = "/dev/xvdc"
}

variable "was_instance_engine_volume_mount_path" {
  description = "WAS Instance Engine Volume Mount Path"
  type        = string
  default     = "/engn001"
}

variable "was_instance_log_volume_mount_path" {
  description = "WAS Instance Log Volume Mount Path"
  type        = string
  default     = "/logs001"
}

variable "was_instance_engine_volume" {
  description = "WAS Instance Engine Volume"
  type        = number
  default     = 20
}

variable "was_instance_log_volume" {
  description = "WAS Instance Log Volume"
  type        = number
  default     = 30
}

variable "resource_tags" {
  description = "Resource Tags"
  type        = map(string)
  default     = {}
}