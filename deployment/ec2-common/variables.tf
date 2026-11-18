############################################################
# 공통
############################################################
variable "base" {
  description = "network-base의 contract 출력"
  type        = any
}

variable "name" {
  description = "stack 이름. 폴더 이름과 같게 둡니다 (Stack 태그, 리소스 이름 접두어)"
  type        = string
  default     = "ec2-common"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.name))
    error_message = "name은 소문자, 숫자, '-'만 사용할 수 있습니다."
  }
}

variable "common_tags" {
  description = "tfvars에서 정의하는 사이트 공통 태그"
  type        = map(string)
  default     = {}
}

############################################################
# 대역 (subnet.tf)
############################################################
variable "zone" {
  description = "network-base contract의 stack_zones 중 사용할 영역"
  type        = string
  default     = "ec2"
}

variable "slot" {
  description = "zone 안의 블록 번호. 사이트 main.tf에서 고유하게 지정하고, 한 번 쓴 번호는 재사용하지 않음"
  type        = number
  default     = 0

  validation {
    condition     = var.slot >= 0 && floor(var.slot) == var.slot
    error_message = "slot은 0 이상의 정수여야 합니다."
  }
}

############################################################
# 공통 보안 그룹 (sg.tf)
# SSH / 서버 접근제어 용도. 기본값은 규칙 없음 (고객사마다 다르므로 사이트에서 추가)
############################################################
variable "common_sg_ingress" {
  description = "공통 SG 인바운드 규칙. 서버 접근 경로만 넣습니다. 서비스 포트는 각 용도의 개별 SG에 둡니다"
  type = list(object({
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string))
    security_groups = optional(list(string))
    description     = optional(string)
  }))
  default = []

  validation {
    # AWS SG 규칙 설명은 영문, 숫자, 일부 기호만 허용 (한글 불가)
    condition     = alltrue([for r in var.common_sg_ingress : r.description == null || can(regex("^[0-9A-Za-z_ .:/()#,@\\[\\]+=&;{}!$*-]*$", r.description))])
    error_message = "SG 규칙 description은 영문, 숫자, 공백과 일부 기호(_ . : / ( ) # , @ [ ] + = & ; { } ! $ * -)만 쓸 수 있습니다. 한글은 쓸 수 없습니다."
  }
}

############################################################
# VPC endpoint (endpoint.tf)
############################################################
variable "enable_ssm" {
  description = "SSM Session Manager 사용 여부. true면 ssm, ssmmessages, ec2messages endpoint를 만듭니다 (다른 stack이 이미 만들었으면 skip)"
  type        = bool
  default     = true
}

variable "endpoints" {
  description = "추가로 필요한 endpoint 서비스 이름 (예: s3, logs). 이미 다른 stack이 만들었으면 skip됩니다"
  type        = list(string)
  default     = []
}
