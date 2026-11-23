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
  default     = "ec2-was"

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
  description = "루트 볼륨 크기 (GiB)"
  type        = number
  default     = 30
}

variable "ebs_volumes" {
  description = "추가 EBS 볼륨. 예: [{ device_name = \"/dev/xvdb\", volume_size = 20 }]"
  type = list(object({
    device_name = string
    volume_size = number
    volume_type = optional(string, "gp3")
  }))
  default = []
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
