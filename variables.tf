variable "region" {
  description = "AWS Region"
  type = string
  default = "ap-northeast-2"
}

variable "azs" {
  description = "A list of availability zones names or ids in the region"
  type = list(string)
  default = []
}

variable "cluster_name" { 
  description = "Cluster Name"
  type = string
  default = "simple"
}

variable "resource_prefix" {
  description = "Resource Prefix"
  type = string
  default = "simple"
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID"
  type = string
  default = null
}

variable "common_tags" {
  description = "Common Tags"
  type = map(string)
  default = {}
}

variable "resource_tags" {
  description = "Resource Tags"
  type = map(string)
  default = {}
}

variable "vpc_name" {
  description = "VPC Name"
  type = string
  default = "simple-vpc"
}

variable "vpc_primary_cidr" {
  description = "VPC CIDR Range"
  type = string
  default = "10.0.0.0/16"
}

variable "vpc_secondary_cidr" {
  description = "VPC CIDR Range"
  type = string
  default = "100.0.0.0/16"
}

variable "KEYCLOAK_REALM" {
  description = "KEYCLOAK Realm"
  type = string
  default = "DevOS"
}

variable "KEYCLOAK_ENDPOINT" {
  description = "KEYCLOAK Endpoint"
  type = string
  default = ""
}

variable "KEYCLOAK_CLIENT_ID" {
  description = "KEYCLOAK Client ID"
  type = string
  default = ""
}

variable "KEYCLOAK_CLIENT_UUID" {
  description = "KEYCLOAK Client UUID"
  type = string
  default = ""
}

variable "KEYCLOAK_CLIENT_SECRET" {
  description = "KEYCLOAK Client Secret"
  type = string
  default = ""
}

variable "KEYCLOAK_USER_UUID" {
  description = "KEYCLOAK User UUID"
  type = string
  default = ""
}

variable "attachment_tgw" {
  description = "Attachment Transit Gateway (Root Account)"
  type        = string
  default     = null
}

variable "attachment_name" {
  description = "Attachment Name"
  type = string
  default = null
}

variable "tgw_route_target_ips" {
  description = "Transit Gateway Target Ips"
  type        = list(string)
  default     = null
}

variable "vpc_resolver_rule_id" {
  description = "VPC Resolver Rule ID"
  type = string
  default = null
}

variable "root_domain" {
  description = "Root Domain"
  type = string
  default = ""
}

variable "root_account" {
  description = "Root Account"
  type = string
  default = ""
}

variable "daytona_url" {
  description = "Daytona URL"
  type = string
  default = ""
}

## RDS
variable "create_db" {
  description = "RDS DB 생성여부"
  type = all
}

variable "db_name" {
  description = "RDS DB 이름"
  type = string
  default = ""
}

variable "db_allocated_storage" {
  description = "RDS DB 저장소 크기"
  type = number
  default = 20
}

variable "db_max_allocated_storage" {
  description = "RDS DB 최대 저장소 크기"
  type = number
  default = 100
}

variable "db_user_name" {
  description = "RDS DB 사용자 이름"
  type = string
  default = "user"
}

variable "db_user_pass" {
  description = "RDS DB 사용자 비밀번호"
  type = string
  default = "1234"
}

variable "db_port" {
  description = "RDS DB 포트"
  type = number
  default = 3306
} 

variable "db_engine" {
  description = "RDS DB 엔진"
  type = string
  default = "mysql"
}

variable "db_engine_version" {
  description = "RDS DB 엔진 버전"
  type = string
  default = "8.0"
}

variable "db_instance_class" {
  description = "RDS DB 인스턴스 클래스"
  type = string
  default = "db.t3.medium"
}

variable "multi_az" {
  description = "RDS DB 다중 가용영역 여부"
  type = bool
  default = false
}

variable "db_parameter_group" {
  description = "RDS DB 파라미터 그룹"
  type = map(any)
  default = null
}

variable "db_subnet_group" {
  description = "RDS DB 서브넷 그룹"
  type = string
  default = null
}

variable "db_sg" {
  description = "RDS DB 보안 그룹"
  type = map(any)
  default = null
}

variable "db_sg_rules" {
  description = "RDS DB 보안 그룹 규칙"
  type = map(any)
  default = null
}

variable "db_sg_ro" {
  description = "RDS DB 읽기 전용 보안 그룹"
  type = map(any)
  default = null
}

variable "db_sg_ro_rules" {
  description = "RDS DB 읽기 전용 보안 그룹 규칙"
  type = map(any)
  default = null
}

variable "DAYTONA_SECRET_KEY" {
  default     = null
}

variable "DAYTONA_ACCESS_KEY" {
  default     = null
}

variable "KEYCLOAK_REALM" {
  default     = null
}

variable "KEYCLOAK_ENDPOINT" {
  default     = null
}

variable "KEYCLOAK_CLIENT_ID" {
  default     = null
}

variable "KEYCLOAK_CLIENT_UUID" {
  default     = null
}

variable "KEYCLOAK_CLIENT_SECRET" {
  default     = null
}

variable "KEYCLOAK_USER_UUID" {
  default = null
}

variable "daytona_url" {
  default = ""
}



## 기존


variable "tgw_route_target_ips" {
  description = "Transit Gateway Target Ips"
  type        = list(string)
  default     = null
}

variable "network_interface_id" {
  description = "Network Interface ID"
  type = string
  default = null
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID"
  type = string
  default = null
}

variable "vpc_peering_connection_id" {
  description = "VPC Peering Connection ID"
  type = string
  default = null
}

variable "vpc_endpoint_id" {
  description = "VPC Endpoint ID"
  type = string
  default = null
}

## VPC_tgw_attach
variable "attachment_tgw" {
  description = "Attachment Transit Gateway (Root Account)"
  type        = string
  default     = null
}

variable "attachment_name" {
  description = "Attachment Name"
  type = string
  default = null
}

variable "create_elasticache" {
  description = "elasticache 생성 여부"
  type = all
}

variable "create_db" {
  description = "RDS DB 생성여부"
  type = all
}

##route
variable "tgw_route_target_ips" {
  description = "Transit Gateway Target Ips"
  type        = list(string)
  default     = null
}

variable "attachment_tgw" {
  description = "Attachment Transit Gateway (Root Account)"
  type        = string
  default     = null
}

## tgw
variable "attachment_name" {
  description = "TGW attachment 이름"
  type = all
}

## alb
variable "was_name" {
  description = "was EC2 이름"
  type = all
}

variable "was_alb" {
  description = "was에서 사용하는 alb"
  type = all
}

variable "web_ide_name" {
  description = "web_ide EC2 이름"
  type = all
}

variable "web_ide_alb" {
  description = "web_ide에서 사용하는 alb"
  type = all
}

variable "cluster_name" {
  description = "cluster EC2 이름"
  type = all
}

variable "root_domain" {
  description = "root_domain 이름"
  type = all
}

variable "vpc_resolver_rule_id" {
  description = "VPC Resolver Rule Id"
  type        = string
  default     = null
}


## 기존



variable "region" {
  default = "ap-northeast-2"
}

variable "cluster_name" {
  description = "All Resource Prefix Name"
  type = string
  default = ""
}



variable "root_domain" {
  description = "Root Domain"
  default = ""
}

variable "root_account" {
  description = "Root Account"
  default = ""
}

# VPC
variable "vpc_id" {
  description = "The VPC ID."
  default = ""
}





variable "vpc_name" {
  description = "VPC Name"
  type        = string
  default     = ""
}



# Bastion
#variable "bastion_ami" {
#  description = "EC2 Bastion Instance Ami Id"
#  type = string
#  default = "ami-01711d925a1e4cc3a" // amazon linux
#}
#
#variable "bastion_instance_name" {
#  description = "EC2 Bastion Instance Name"
#  type = string
#  default = "ntier-bastion"
#}
#
#variable "bastion_instance_type" {
#  description = "EC2 Bastion Instance Type"
#  type = string
#  default = "t2.micro"
#}
#
#variable "bastion_key_pair_name" {
#  description = "EC2 Bastion Key Pair Name"
#  type = string
#  default = "bastion-key-pair"
#}
#
#variable "bastion_instance_role_policy" {
#  description = "EC2 Bastion Assum Role Policy"
#  type = string
#  default = <<EOF
#{
#    "Version": "2012-10-17",
#    "Statement": [
#        {
#            "Action": "sts:AssumeRole",
#            "Principal": {
#               "Service": ["ec2.amazonaws.com"]
#            },
#            "Effect": "Allow",
#            "Sid": ""
#        }
#    ]
#}
#EOF
#}

# WAS
variable "was_name" {
  description = "EC2 Web Server Instance Type"
  default = "bg-was"
}

variable "was_instance_type" {
  description = "EC2 Web Server Instance Type"
  default = "t2.micro"
}

variable "was_instance_ami" {
  description = "EC2 Web Server Instance Ami Type"
  default = "ami-04599ab1182cd7961"
}

variable "was_instance_root_volume" {
  description = "EC2 Web Server Instance Root Device Volume"
  default = 30
}

variable "was_instance_log_volume_mount_path" {
  description = "EC2 WAS Server Instance Log Volume Mount Path"
  default = "/logs001"
}

variable "was_instance_log_volume_device_name" {
  description = "EC2 Web Server Instance Log Volume Device Name"
  default = "/dev/xvdc"
}

variable "was_instance_log_volume" {
  description = "EC2 Web Server Instance Log Volume"
  default = 30
}

variable "was_instance_engine_volume_mount_path" {
  description = "EC2 WAS Server Instance Engine Volume Mount Path"
  default = "/engn001"
}

variable "was_instance_engine_volume_device_name" {
  description = "EC2 Web Server Instance Engine Volume Device Name"
  default = "/dev/xvdb"
}


variable "was_instance_engine_volume" {
  description = "EC2 Web Server Instance Engine Volume"
  default = 20
}

variable "common_key_pair_name" {
  description = "Common Resources Used Key Pair Name"
  type        = string
  default     = "ec2-key-pair"
}

variable "was_desired_capacity" {
  description = "WAS Auto Scaling Group Desired Capacity"
  default = 2
}

variable "was_min_size" {
  description = "WAS Auto Scaling Group Min Size"
  default = 2
}

variable "was_max_size" {
  description = "WAS Auto Scaling Group Max Size"
  default = 4
}

variable "was_alb_name" {
  description = "WAS ALB Name"
  default = ""
}

# WEB IDE Server
variable "web_ide_name" {
  description = "WEB IDE Server Instance Name"
  default = "bg-web-ide"
}

variable "web_ide_instance_type" {
  description = "WEB IDE Server Instance Type"
  default = "t2.medium"
}

variable "web_ide_instance_ami" {
  description = "WEB IDE Server Instance Ami Type"
  default = "ami-0aac0f781c0507f05" # shared custom image
}

variable "web_ide_alb_name" {
  description = "WEB IDE Service ALB Name"
  default = ""
}

# RDS
variable "create_db" {
  description = "Generated RDS or not"
  type = bool
  default = false
}

variable "db_name" {
  description = "RDS Name"
  default = ""
}

variable "db_user_name" {
  description = "RDS User Password"
  default = "user"
}

variable "db_user_pass" {
  description = "RDS User Password"
  default = "1234"
}

variable "db_engine" {
  description = "RDS DB Engine"
  default = "mysql"
}

variable "db_engine_version" {
  description = "RDS DB Engine Version"
  default = "8.0"
}

variable "db_engine_instance_class" {
  description = "RDS DB Engine Instance Class"
  default = "db.t3.micro"
}

#S3
variable "create_bucket" {
  description = "Generated S3 Bucket or not"
  type = bool
  default = false
}

variable "bucket_name" {
  description = "S3 Bucket Name"
  type = string
  default = "simple-bucket"
}

variable "bucket_versioning" {
  description = "S3 Bucket Versioning"
  type        = bool
  default     = true
}

variable "bucket_private_acl" {
  description = "S3 Bucket Private ACL"
  type        = bool
  default     = true
}

variable "bucket_object_expiration_days" {
  description = "Bucket Object Expiration Days"
  type        = number
  default     = 30
}

# elastiCache
variable "create_elasticache" {
  description = "Generated ElastiCache or not"
  type = bool
  default = false
}

variable "elasticache_name" {
  description = "ElastiCache Cluster Name"
  type = string
  default = "simple-cache-cluster"
}

variable "elasticache_engine" {
  description = "ElastiCache Engine"
  type = string
  default = "redis"
}

variable "elasticache_engine_version" {
  description = "ElastiCache Engine Version"
  type = string
  default = "6.2"
}

variable "elasticache_node_type" {
  description = "ElastiCache Node Type"
  type = string
  default = "cache.t2.micro"
}

variable "elasticache_cache_node_number" {
  description = "ElastiCache number of Cache Nodes"
  type = number
  default = 1
}

variable "elasticache_parameter_group_name" {
  description = "ElastiCache Parameter Group Name"
  type = string
  default = "default.redis6.x"
}

variable "elasticache_port" {
  description = "ElastiCache Port Number"
  type = number
  default = 6379
}

variable "attachment_tgw" {
  description = "Attachment Transit Gateway (Root Account)"
  type        = string
  default     = null
}

variable "vpc_resolver_rule_id" {
  description = "VPC Resolver Rule Id"
  type        = string
  default     = null
}

variable "tgw_route_target_ips" {
  description = "Transit Gateway Target Ips"
  type        = list(string)
  default     = null
}

variable "DAYTONA_SECRET_KEY" {
  default     = null
}

variable "DAYTONA_ACCESS_KEY" {
  default     = null
}

variable "KEYCLOAK_REALM" {
  default     = null
}

variable "KEYCLOAK_ENDPOINT" {
  default     = null
}

variable "KEYCLOAK_CLIENT_ID" {
  default     = null
}

variable "KEYCLOAK_CLIENT_UUID" {
  default     = null
}

variable "KEYCLOAK_CLIENT_SECRET" {
  default     = null
}

variable "KEYCLOAK_USER_UUID" {
  default = null
}

variable "daytona_url" {
  default = ""
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

variable "weekend_stop_enable" {
  description = "Stop Ec2, RDS over the weekend or not"
  type = bool
  default = true # 운영 배포 시 false 처리
}

variable "module_repo_url" {
  description = "Module Repository URL"
  type = string
  default = "https://github.com/bsp-daytona/bsp-daytona-module.git"
}

variable "common_tags" {
  description = "Common Tags"
  type = map(string)
  default = {}
}