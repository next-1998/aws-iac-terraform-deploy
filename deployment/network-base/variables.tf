############################################################
# 사이트 / 태그
############################################################
variable "site" {
  description = "사이트 이름 (tfvars). Stack 태그, 리소스 이름 접두어"
  type        = string
}

variable "common_tags" {
  description = "tfvars에서 정의하는 사이트 공통 태그"
  type        = map(string)
  default     = {}
}

############################################################
# VPC 대역
#
# role
#   routable : 사내망과 통신할 수 있는 대역 (네트워크팀 할당). 반드시 첫 번째
#   internal : VPC 안에서만 쓰는 대역. 100.64.0.0/16 만 허용
#
# 네트워크 유형은 대역 구성으로 자동 판단합니다.
#   routable 단독        : [routable]            → 워크로드도 routable 대역에 배치
#   routable + internal  : [routable, internal]  → 워크로드는 internal 대역에 배치
############################################################
variable "vpc_name" {
  description = "VPC 이름 (VpcName 태그 값)"
  type        = string
}

variable "vpc_cidrs" {
  description = "VPC 대역 목록. 첫 번째는 routable (VPC primary)"
  type = list(object({
    cidr = string
    role = string
  }))

  validation {
    condition     = length(var.vpc_cidrs) >= 1 && length(var.vpc_cidrs) <= 2
    error_message = "vpc_cidrs는 routable 1개, 또는 routable 1개 + internal 1개여야 합니다."
  }
  validation {
    condition     = alltrue([for c in var.vpc_cidrs : contains(["routable", "internal"], c.role)])
    error_message = "role은 routable 또는 internal이어야 합니다."
  }
  validation {
    condition     = var.vpc_cidrs[0].role == "routable" && length([for c in var.vpc_cidrs : c if c.role == "routable"]) == 1
    error_message = "첫 번째 대역은 routable이어야 하고, routable은 1개만 둘 수 있습니다."
  }
  validation {
    condition     = alltrue([for c in var.vpc_cidrs : c.cidr == "100.64.0.0/16" if c.role == "internal"])
    error_message = "internal 대역은 100.64.0.0/16만 사용할 수 있습니다."
  }
  validation {
    condition     = alltrue([for c in var.vpc_cidrs : can(cidrhost(c.cidr, 0))])
    error_message = "cidr 형식이 올바르지 않습니다."
  }
  validation {
    # base 영역(/24, AZ 4개분)이 들어가야 함. routable 단독이면 stack 영역(나머지 절반)까지 필요해서 /23 이상
    condition = (
      length(var.vpc_cidrs) == 2
      ? tonumber(split("/", var.vpc_cidrs[0].cidr)[1]) <= 24
      : tonumber(split("/", var.vpc_cidrs[0].cidr)[1]) <= 23
    )
    error_message = "routable 대역 크기가 부족합니다. routable + internal은 /24 이상, routable 단독은 /23 이상이어야 합니다."
  }
}

variable "az_count" {
  description = "사용할 AZ 개수 (2~4). a, b, c, d 순서로 늘어남. 늘려도 기존 서브넷은 바뀌지 않음"
  type        = number
  default     = 2

  validation {
    condition     = contains([2, 3, 4], var.az_count)
    error_message = "az_count는 2, 3, 4 중 하나여야 합니다."
  }
}

############################################################
# 인터넷 출구 / TGW
############################################################
variable "enable_internet" {
  description = "인터넷 출구(IGW, public NAT) 생성 여부"
  type        = bool
  default     = true
}

variable "nat_per_az" {
  description = "NAT GW를 AZ마다 만들지 여부. true(기본값): AZ마다 public/private NAT, 각 AZ는 자기 AZ의 NAT 사용 / false: 첫 번째 AZ(a)에 1개, 모든 AZ가 공유 (비용 절감, a AZ 장애 시 외부 통신 중단)"
  type        = bool
  default     = true
}

variable "tgw_id" {
  description = "연결할 Transit Gateway ID. null이면 TGW 관련 리소스를 만들지 않음"
  type        = string
  default     = null
}

variable "tgw_route_cidrs" {
  description = "TGW로 보낼 사내망 목적지 CIDR 목록"
  type        = list(string)
  default     = []
}

############################################################
# DNS
############################################################
variable "root_domain" {
  description = "상위 도메인. 값이 있으면 <site>.<root_domain> 존을 만들고 상위 존에 NS 위임 레코드를 추가"
  type        = string
  default     = ""
}

variable "resolver_rule_id" {
  description = "VPC에 연결할 Route53 Resolver Rule ID. null이면 연결하지 않음"
  type        = string
  default     = null
}
