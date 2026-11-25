############################################################
# 공통
############################################################
variable "common" {
  description = "ec2-common의 contract 출력 (서브넷, 공통 SG, network-base 정보 포함)"
  type        = any
}

variable "name" {
  description = "stack 이름. 폴더 이름과 같게 둡니다 (Stack 태그, 리소스 이름 접두어)"
  type        = string
  default     = "ec2-webide"

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
# 보안 그룹 (sg.tf)
############################################################

############################################################
# IAM (iam.tf)
############################################################
variable "policy_arns" {
  description = "role에 추가로 연결할 관리형 정책. 키: 식별 이름, 값: 정책 ARN (SSM 접속, CloudWatch Agent 정책은 항상 포함되어 뺄 수 없음)"
  type        = map(string)
  default     = {}
}

############################################################
# EC2 (ec2.tf)
############################################################
variable "ami" {
  description = "EC2 AMI ID"
  type        = string
}

variable "instance_type" {
  description = "EC2 인스턴스 타입"
  type        = string
  default     = "t3.micro"
}

variable "instance_az" {
  description = "EC2를 둘 AZ. null이면 subnets의 첫 번째 AZ"
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "루트 볼륨 크기 (GiB). root_auto_grow를 켜면 처음 크기 (실제 크기가 더 크면 실제 크기 유지)"
  type        = number
  default     = 30
}

variable "ebs_volumes" {
  description = <<-EOT
    데이터 볼륨 (서버 생성 후 따로 만들어 붙임, volumes.tf). 크기는 늘리기만 가능
      device_name   : 장치 이름 (예: /dev/sdf). 바꾸면 볼륨이 다시 만들어짐
      mount_point   : 마운트 경로. null이면 붙이기만 함. 있으면 SSM으로 포맷(처음만)·마운트·fstab 등록 (src/mount_volumes.sh)
      fs_type       : xfs(기본) | ext4
      mount_options : fstab 옵션 (기본 defaults,nofail)
      auto_grow     : 자동 증설 (null이면 끔, autogrow.tf). mount_point가 있어야 함. { max_size = 상한 GiB, threshold = 80, increase_percent = 20, min_increase = 10 }
    예: [{ device_name = "/dev/sdf", volume_size = 100, mount_point = "/data" }]
  EOT
  type = list(object({
    device_name   = string
    volume_size   = number
    volume_type   = optional(string, "gp3")
    mount_point   = optional(string)
    fs_type       = optional(string, "xfs")
    mount_options = optional(string, "defaults,nofail")
    auto_grow     = optional(object({ max_size = number, threshold = optional(number, 80), increase_percent = optional(number, 20), min_increase = optional(number, 10) }))
  }))
  default = []

  validation {
    condition     = length(distinct([for v in var.ebs_volumes : v.device_name])) == length(var.ebs_volumes)
    error_message = "ebs_volumes에 같은 device_name이 두 번 있습니다."
  }
  validation {
    # 마운트 경로: 절대 경로, 허용 문자만 (스크립트 입력 구분자 '|'·따옴표 방지), 시스템 경로 금지
    condition = alltrue([for v in var.ebs_volumes : v.mount_point == null || (
      can(regex("^/[A-Za-z0-9._/-]+$", v.mount_point)) &&
      !contains(["/", "/bin", "/boot", "/dev", "/etc", "/lib", "/lib64", "/proc", "/root", "/run", "/sbin", "/sys", "/usr", "/var", "/tmp", "/home"], trimsuffix(v.mount_point, "/"))
    )])
    error_message = "mount_point는 /로 시작하는 경로(영문, 숫자, . _ - /)여야 하고 /, /boot, /etc, /usr, /var, /tmp, /home 같은 시스템 경로는 쓸 수 없습니다 (그 아래 하위 경로는 가능, 예: /var/app)."
  }
  validation {
    condition     = length(distinct(compact([for v in var.ebs_volumes : v.mount_point == null ? null : trimsuffix(v.mount_point, "/")]))) == length(compact([for v in var.ebs_volumes : v.mount_point == null ? null : trimsuffix(v.mount_point, "/")]))
    error_message = "ebs_volumes에 같은 mount_point가 두 번 있습니다."
  }
  validation {
    condition     = alltrue([for v in var.ebs_volumes : v.auto_grow == null || v.mount_point != null])
    error_message = "auto_grow를 켠 볼륨은 mount_point가 있어야 합니다 (마운트 경로의 사용률로 판단)."
  }
  validation {
    condition     = alltrue([for v in var.ebs_volumes : v.auto_grow == null || try(v.auto_grow.max_size > v.volume_size && v.auto_grow.max_size <= 16384 && v.auto_grow.threshold > 0 && v.auto_grow.threshold < 100 && v.auto_grow.increase_percent > 0 && v.auto_grow.min_increase >= 1, false)])
    error_message = "auto_grow: max_size는 volume_size보다 크고 16384 GiB 이하, threshold는 1~99, increase_percent는 1 이상, min_increase는 1 GiB 이상이어야 합니다."
  }
  validation {
    condition     = alltrue([for v in var.ebs_volumes : contains(["xfs", "ext4"], v.fs_type)])
    error_message = "fs_type은 xfs 또는 ext4여야 합니다."
  }
  validation {
    condition     = alltrue([for v in var.ebs_volumes : can(regex("^[a-z0-9_,=.-]+$", v.mount_options))])
    error_message = "mount_options는 fstab 옵션 형식(예: defaults,nofail,noatime)이어야 합니다."
  }
}

variable "kms_key_id" {
  description = "EBS 암호화 CMK. null이면 계정 EBS 기본 CMK (00-bootstrap의 ebs 키: 중앙 키 또는 이 계정 키). 서버별로 키를 따로 둘 때만 지정"
  type        = string
  default     = null
}

variable "user_data" {
  description = "user_data 스크립트 (렌더링된 문자열)"
  type        = string
  default     = null
}

variable "weekend_stop_enable" {
  description = "주말 자동 중지 대상 여부. EC2와 EBS에 WEEKEND_STOP_ENABLE 태그로 붙습니다 (주말 중지 Lambda가 읽음)"
  type        = bool
  default     = false
}

############################################################
# ALB (alb.tf) - main.tf에서 enable_alb로 선택
############################################################
variable "enable_alb" {
  description = "ALB 생성 여부"
  type        = bool
  default     = false
}

variable "alb_internal" {
  description = "내부 ALB 여부"
  type        = bool
  default     = true
}

variable "alb_subnet_ids" {
  description = "ALB 서브넷. null이면 내부용은 edge, 외부용은 public 서브넷"
  type        = list(string)
  default     = null
}

variable "alb_ingress_cidrs" {
  description = "ALB 접근 허용 CIDR. null이면 내부용은 VPC + 사내망, 외부용은 0.0.0.0/0"
  type        = list(string)
  default     = null
}

variable "alb_ingress_prefix_lists" {
  description = "ALB 접근 허용 prefix list 이름 (01-network). 지정하면 alb_ingress_cidrs 대신 사용 (권장)"
  type        = list(string)
  default     = []
}

variable "waf_acl_arn" {
  description = "ALB에 연결할 WAF Web ACL ARN. null이면 연결하지 않음 (기본값)"
  type        = string
  default     = null
}

variable "access_log_bucket" {
  description = "ALB 접근 로그 버킷 이름 (00-bootstrap 버킷 또는 중앙 로그 버킷). null이면 끔"
  type        = string
  default     = null
}

variable "alb_certificate_arn" {
  description = "HTTPS 인증서 ARN. null이면 HTTP(80)만 사용"
  type        = string
  default     = null
}

variable "alb_record_name" {
  description = "base 존에 만들 ALB 레코드 이름 (예: web → web.<site>.<domain>). null이면 만들지 않음"
  type        = string
  default     = null
}

variable "alb_deletion_protection" {
  description = "ALB 삭제 보호 (단계 루트 operation_mode / deletion_protection.alb)"
  type        = bool
  default     = false
}

variable "app_port" {
  description = "EC2 애플리케이션 포트 (ALB target 포트)"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "target group 헬스 체크 경로"
  type        = string
  default     = "/"
}


variable "sg_rules_csv" {
  description = "SG 규칙 CSV 내용. null(기본값)이면 src/sg_rules.csv를 읽음 (테스트나 다른 파일을 쓸 때만 지정)"
  type        = string
  default     = null
}

variable "sg_rule_limit" {
  description = "SG 하나의 방향별 규칙 한도 (AWS 기본 60). Service Quotas로 올렸으면 그 값으로"
  type        = number
  default     = 60
}

############################################################
# CloudWatch Agent 로그 그룹 (logs.tf)
############################################################
variable "agent_log_groups" {
  description = "미리 만들 Agent 로그 그룹 (이름 → 설명). 이름은 /<VPC 이름>/ec2/<서버 이름>/<이름>. messages, secure는 Agent 기본 설정이 씀. 그 밖의 이름은 껍데기만 만듦"
  type        = map(string)
  default = {
    messages = "OS 로그 (RHEL계열 /var/log/messages, Debian계열 /var/log/syslog)"
    secure   = "인증 로그 (RHEL계열 /var/log/secure, Debian계열 /var/log/auth.log)"
  }

  validation {
    condition     = alltrue([for k, v in var.agent_log_groups : can(regex("^[a-z0-9][a-z0-9-]*$", k))])
    error_message = "agent_log_groups 이름은 소문자, 숫자, '-'만 쓸 수 있습니다."
  }
}

variable "log_retention_days" {
  description = "CloudWatch 로그 보관 기간 (일). 기본 14 (장기 보관은 S3)"
  type        = number
  default     = 14
}

variable "enable_cloudwatch_agent" {
  description = "CloudWatch Agent 설치·설정 (SSM 연결로 src/cwagent_setup.sh 실행). agent_log_groups에 messages, secure가 있어야 동작"
  type        = bool
  default     = true
}

variable "cloudwatch_agent_schedule" {
  description = "Agent 설정을 다시 적용할 주기 (예: rate(7 days)). null이면 만들 때와 서버·스크립트가 바뀔 때만 실행"
  type        = string
  default     = null
}

variable "protect_volumes" {
  description = "서버 삭제 후 EBS 볼륨 유지 (단계 루트 operation_mode / deletion_protection.ec2_volumes). false면 서버와 같이 삭제"
  type        = bool
  default     = false
}

variable "peer_sg_ids" {
  description = <<-EOF2
    같은 단계(03-compute)의 다른 용도 SG (이름 → ID). sg_rules.csv에서 sg:<용도>.<sg>로 참조 (예: sg:webide.app, sg:was.alb)
    03-compute가 넘겨 줌. ID는 apply 전까지 몰라도 됨 (이름으로 참조하므로 처음 배포에도 한 번에 적용)
  EOF2
  type        = map(string)
  default     = {}
}

############################################################
# 자동 확장 (autoscale.tf, 선택 · 기본 꺼짐)
############################################################
variable "autoscale" {
  description = <<-EOT
    고정 서버 1대 + 확장 서버(ASG, 0 ~ max_extra)
      enabled       : 켜기 (기본 false = 고정 서버 1대만, 지금과 같음)
      ami           : 확장 서버 이미지 (고정 AMI ID). null이면 고정 서버로 최초 이미지를 한 번만 만들어 씀
      max_extra     : 확장 서버 최대 대수 (0이면 대기만)
      scale_out     : CPU 또는 메모리 그룹 평균이 이 값(%)을 5분 넘으면 +1
      scale_in      : CPU와 메모리 그룹 평균이 모두 이 값(%) 미만 15분이면 -1
      image_reboot  : 최초 이미지를 만들 때 고정 서버 재부팅 (true = 파일 일관성, 잠시 중단)
      instance_type : 확장 서버 사양 (null이면 고정 서버와 같음)
      refresh_min_healthy_percentage : 이미지가 바뀌어 순차 교체할 때 유지할 정상 비율 (%)
      weekend_stop  : 주말 중지 (선택, 기본 꺼짐). 확장 서버만 0대 ↔ 원복
  EOT
  type = object({
    enabled                        = optional(bool, false)
    ami                            = optional(string)
    max_extra                      = optional(number, 0)
    scale_out                      = optional(number, 80)
    scale_in                       = optional(number, 50)
    image_reboot                   = optional(bool, false)
    instance_type                  = optional(string)
    refresh_min_healthy_percentage = optional(number, 90)
    weekend_stop = optional(object({
      enabled        = optional(bool, false)
      stop_schedule  = optional(string, "0 21 * * FRI")
      start_schedule = optional(string, "0 7 * * MON")
      time_zone      = optional(string, "Asia/Seoul")
    }), {})
  })
  default = {}

  validation {
    condition     = var.autoscale.ami == null || can(regex("^ami-[0-9a-f]{8,17}$", var.autoscale.ami))
    error_message = "autoscale.ami는 AMI ID(ami-로 시작) 형식이어야 합니다."
  }
  validation {
    condition     = var.autoscale.max_extra >= 0 && floor(var.autoscale.max_extra) == var.autoscale.max_extra
    error_message = "autoscale.max_extra는 0 이상의 정수여야 합니다."
  }
  validation {
    condition     = var.autoscale.scale_in > 0 && var.autoscale.scale_in < var.autoscale.scale_out && var.autoscale.scale_out < 100
    error_message = "autoscale은 0 < scale_in < scale_out < 100 이어야 합니다 (늘었다 줄었다 반복하지 않게 간격 필요)."
  }
}

############################################################
# EBS 자동 증설 (autogrow.tf) — 고정 서버만 (확장 서버는 교체되므로 제외)
#   디스크 사용률(CloudWatch Agent) > threshold% → 크기 + max(increase_percent%, min_increase GiB), max_size까지
#   ec2-common의 증설 Lambda가 늘리고 파일시스템까지 확장. 같은 볼륨은 6시간에 한 번만 (AWS 제한)
#   켠 볼륨은 실제 크기가 tfvars보다 크면 실제 크기를 유지 (줄이려다 실패하지 않음). tfvars를 더 크게 하면 그 값으로 늘어남
############################################################
variable "root_auto_grow" {
  description = "루트 볼륨 자동 증설 (null이면 끔). { max_size = 상한 GiB, threshold = 80, increase_percent = 20, min_increase = 10 }"
  type = object({
    max_size         = number
    threshold        = optional(number, 80)
    increase_percent = optional(number, 20)
    min_increase     = optional(number, 10)
  })
  default = null

  validation {
    condition     = var.root_auto_grow == null || try(var.root_auto_grow.threshold > 0 && var.root_auto_grow.threshold < 100 && var.root_auto_grow.increase_percent > 0 && var.root_auto_grow.min_increase >= 1, false)
    error_message = "root_auto_grow: threshold는 1~99, increase_percent는 1 이상, min_increase는 1 GiB 이상이어야 합니다."
  }
  validation {
    condition     = var.root_auto_grow == null || try(var.root_auto_grow.max_size > var.root_volume_size && var.root_auto_grow.max_size <= 16384, false)
    error_message = "root_auto_grow.max_size는 root_volume_size보다 크고 16384 GiB 이하여야 합니다."
  }
}
