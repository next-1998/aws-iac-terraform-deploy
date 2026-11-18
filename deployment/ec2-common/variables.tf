############################################################
# 공통
############################################################
variable "network" {
  description = "01-network contract (Parameter Store /iac/<site>/01-network/* 묶음을 합친 값)"
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
# 공통 보안 그룹 (sg.tf)
# SSH / 서버 접근제어 용도. 기본값은 규칙 없음 (고객사마다 다르므로 사이트에서 추가)
# 출발지는 IP(cidr_blocks)보다 prefix list 이름(prefix_lists)을 권장합니다.
############################################################
variable "common_sg_ingress" {
  description = "공통 SG 인바운드 규칙. 서버 접근 경로만. 서비스 포트는 각 용도의 개별 SG에 둡니다"
  type = list(object({
    from_port       = number
    to_port         = number
    protocol        = string
    prefix_lists    = optional(list(string)) # 01-network의 prefix list 이름 (예: ["access_ctl"])
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
# 주말 중지 (weekend_stop.tf) — 협의 후 적용
#   enable_weekend_stop = true면 Lambda와 스케줄을 만듭니다.
#   스케줄은 schedule_enabled = true가 되기 전까지 실행되지 않습니다 (임시 값).
#   대상은 EC2 태그 WEEKEND_STOP_ENABLE = "true" (ec2-<용도>의 weekend_stop_enable)
#   VPC 안에서 실행하므로 01-network interface_endpoints에 "ec2"가 있어야 합니다.
############################################################
variable "enable_weekend_stop" {
  description = "EC2 주말 중지 Lambda 생성 여부"
  type        = bool
  default     = false
}

variable "weekend_stop" {
  description = "주말 중지 설정 (스케줄은 임시 값, 협의 후 변경)"
  type = object({
    schedule_enabled = optional(bool, false)
    stop_schedule    = optional(string, "cron(0 21 ? * FRI *)")
    start_schedule   = optional(string, "cron(0 7 ? * MON *)")
    timezone         = optional(string, "Asia/Seoul")
    dry_run          = optional(bool, false)
  })
  default = {}
}
