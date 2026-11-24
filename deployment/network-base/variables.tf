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

variable "vpc_name" {
  description = "VPC 이름 (VpcName 태그 값)"
  type        = string
}

############################################################
# 배치 규칙 버전 (layout.tf 상단 설명 참고)
############################################################
variable "layout_version" {
  description = "대역 배치 규칙 버전. 사이트를 처음 만들 때 정하고 이후 변경 금지"
  type        = string
  default     = "v1"
}

############################################################
# VPC 대역
#
# role
#   routable : 사내망과 통신할 수 있는 대역 (네트워크팀 할당).
#              첫 번째 항목은 반드시 routable이고 VPC primary가 됩니다.
#              표준 배치(AZ 분할, 서브넷)는 첫 번째 routable 대역으로만 계산합니다.
#              두 번째 이후 routable 대역은 확장용입니다 (수동 서브넷).
#   internal : VPC 안에서만 쓰는 대역. 100.64.0.0/16만 허용.
#              eks_placement = "internal"이면 자동으로 추가되므로 직접 넣지 않아도 됩니다.
#
# 주의
#   - 첫 번째 대역은 바꿀 수 없습니다 (AWS VPC primary).
#   - 대역은 CIDR 값으로 구분하므로 목록 순서를 바꿔도 기존 연결은 유지됩니다.
#   - 추가 routable 대역은 첫 대역과 같은 사설 범위여야 합니다 (예: 10.x에 172.16.x 추가 불가, AWS 제한).
#   - VPC 하나에 붙일 수 있는 대역은 기본 5개입니다 (AWS 한도, 증가 요청 가능).
#   - 새 대역을 추가하면 중앙 네트워크 쪽에 TGW 라우트 추가를 요청해야 사내망과 통신됩니다.
############################################################
variable "vpc_cidrs" {
  description = "VPC 대역 목록. 첫 번째는 routable (VPC primary)"
  type = list(object({
    cidr = string
    role = string
  }))

  validation {
    condition     = length(var.vpc_cidrs) >= 1
    error_message = "vpc_cidrs에 routable 대역이 최소 1개 있어야 합니다."
  }
  validation {
    condition     = alltrue([for c in var.vpc_cidrs : contains(["routable", "internal"], c.role)])
    error_message = "role은 routable 또는 internal이어야 합니다."
  }
  validation {
    condition     = var.vpc_cidrs[0].role == "routable"
    error_message = "첫 번째 대역은 routable이어야 합니다 (VPC primary)."
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
    condition     = length(distinct([for c in var.vpc_cidrs : c.cidr])) == length(var.vpc_cidrs)
    error_message = "같은 대역이 중복으로 들어 있습니다."
  }
}

############################################################
# AZ (제약 사항은 사이트 tfvars 주석 참고)
############################################################
variable "az_count" {
  description = "사용할 AZ 개수 (1~4). 리전의 AZ 목록에서 앞에서부터 순서대로 사용. 1개면 ALB, RDS, EKS를 만들 수 없음"
  type        = number
  default     = 2

  validation {
    condition     = contains([1, 2, 3, 4], var.az_count)
    error_message = "az_count는 1, 2, 3, 4 중 하나여야 합니다."
  }
}

############################################################
# public (선택, 기본값 끔)
#   켜면: public 서브넷 + IGW + public NAT, 외부용 ALB 허용
#   끄면: 인터넷을 쓰지 않음. VPC 어디에도 0.0.0.0/0 경로가 없음 (사내망 경로만)
#         AWS 서비스는 VPC endpoint로만 접근하므로 필요한 endpoint를 빠뜨리지 마세요.
############################################################
variable "enable_public" {
  description = "public 서브넷, IGW, public NAT 생성 여부"
  type        = bool
  default     = false
}

variable "nat_per_az" {
  description = "NAT GW를 AZ마다 만들지 여부. true(기본값): AZ마다, false: 첫 번째 AZ에 1개 (비용 절감, 그 AZ 장애 시 외부 통신 중단)"
  type        = bool
  default     = true
}

############################################################
# 사내망 연결 (서비스 계정: 이미 있는 TGW에 연결만 함)
#   TGW 생성, RAM 공유 수락, attachment 승인, TGW 라우트 테이블은 중앙 네트워크 계정 담당 (README 사전 요청 사항)
############################################################
variable "tgw_id" {
  description = "연결할 기존 Transit Gateway ID. null이면 TGW 연결 안 함"
  type        = string
  default     = null
}

variable "corp_cidrs" {
  description = "TGW로 보낼 사내망 목적지 CIDR 목록"
  type        = list(string)
  default     = []
}

variable "peerings" {
  description = "이미 만들어진 VPC peering 연결. 키: 이름, 값: peering ID와 상대 대역"
  type = map(object({
    peering_connection_id = string
    cidrs                 = list(string)
  }))
  default = {}
}

############################################################
# prefix list (종류 고정 없음. 필요한 것만 추가)
#   SG 규칙에서 IP를 직접 넣지 않고 prefix list 이름으로 참조합니다.
#   주의: 참조하는 SG 규칙 하나가 max_entries 개수만큼 SG 규칙 한도(기본 60)를 씁니다.
#   description은 영문만 (AWS 제한)
############################################################
variable "prefix_lists" {
  description = "prefix list. 예: { access_ctl = { max_entries = 5, entries = { \"10.0.0.10/32\" = \"server-access-control\" } } }"
  type = map(object({
    max_entries = number
    entries     = map(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.prefix_lists : length(v.entries) <= v.max_entries])
    error_message = "prefix list 항목 수가 max_entries보다 많습니다."
  }
  validation {
    condition     = alltrue([for k, v in var.prefix_lists : can(regex("^[a-z0-9_]+$", k))])
    error_message = "prefix list 이름은 소문자, 숫자, '_'만 쓸 수 있습니다."
  }
}

############################################################
# EKS 배치 (서브넷은 04-eks의 eks-common이 만듭니다. 여기서는 CIDR만 계산)
############################################################
variable "eks_placement" {
  description = "EKS 서브넷 위치. null(EKS 없음) / routable / internal"
  type        = string
  default     = null

  validation {
    condition     = var.eks_placement == null || contains(["routable", "internal"], coalesce(var.eks_placement, "routable"))
    error_message = "eks_placement는 null, routable, internal 중 하나여야 합니다."
  }
}

variable "eks_subnet" {
  description = "eks_placement = routable일 때 AZ별 EKS 서브넷 크기 (prefix 길이). 23 이하(= /23 이상)"
  type        = number
  default     = 23

  validation {
    condition     = var.eks_subnet >= 16 && var.eks_subnet <= 23
    error_message = "eks_subnet은 16~23이어야 합니다 (EKS는 AZ마다 /23 이상 필요)."
  }
}

############################################################
# 수동 서브넷 (예비 공간 또는 추가 routable 대역에만)
#   서브넷 생성은 purpose에 해당하는 <유형>-common이 담당합니다.
############################################################
variable "manual_subnets" {
  description = "sizing 출력의 spare 또는 추가 routable 대역에 직접 넣는 서브넷"
  type = list(object({
    name    = string
    az      = string
    cidr    = string
    purpose = string
  }))
  default = []

  validation {
    condition     = alltrue([for s in var.manual_subnets : can(cidrhost(s.cidr, 0)) && tonumber(split("/", s.cidr)[1]) <= 28])
    error_message = "manual_subnets의 cidr 형식이 올바르지 않거나 /28보다 작습니다 (AWS 최소 /28)."
  }
  validation {
    condition     = length(distinct([for s in var.manual_subnets : s.name])) == length(var.manual_subnets)
    error_message = "manual_subnets의 name이 중복됩니다."
  }
}

############################################################
# VPC endpoint (모든 유형이 같이 쓰는 endpoint를 여기서 만듭니다)
############################################################
variable "interface_endpoints" {
  description = "인터페이스 endpoint 서비스 이름 (예: ssm, ssmmessages, ec2messages, ecr.api, ecr.dkr, sts, logs)"
  type        = list(string)
  default     = []
}

variable "gateway_endpoints" {
  description = "Gateway endpoint (s3, dynamodb). 라우트 테이블 연결은 각 <유형>-common이 합니다"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.gateway_endpoints : contains(["s3", "dynamodb"], s)])
    error_message = "gateway_endpoints는 s3, dynamodb만 가능합니다."
  }
}

variable "endpoint_skip_if_exists" {
  description = "같은 VPC에 다른 state(수동 생성 등)가 만든 같은 endpoint가 있으면 생성하지 않음"
  type        = bool
  default     = true
}

############################################################
# DNS
#   private 존: 항상 생성 (root_domain이 있을 때). 내부 레코드용, VPC에만 연결
#   public 존 : enable_public = true일 때만. 외부용 ALB 레코드
############################################################
variable "root_domain" {
  description = "상위 도메인. 값이 있으면 <site>.<root_domain> 존을 만듦 (public 존은 상위 존에 NS 위임)"
  type        = string
  default     = ""
}

variable "resolver_rule_id" {
  description = "VPC에 연결할 Route53 Resolver Rule ID. null이면 연결하지 않음"
  type        = string
  default     = null
}

############################################################
# VPC Flow Logs
############################################################
variable "enable_flow_logs" {
  description = "VPC Flow Logs 생성 여부"
  type        = bool
  default     = true
}

variable "flow_log_bucket_arn" {
  description = "Flow Logs를 보낼 S3 버킷 ARN (00-bootstrap 버킷 또는 중앙 로그 버킷). enable_flow_logs = true면 필수"
  type        = string
  default     = null
}

variable "protect_nat_eip" {
  description = "NAT EIP 삭제 보호 (단계 루트 operation_mode / deletion_protection.nat_eip)"
  type        = bool
  default     = false
}
