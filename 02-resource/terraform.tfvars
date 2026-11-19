############################################################
# 02-resource — 사이트: simple (예시 값. 실제 값으로 바꿔서 사용)
# 01-network를 먼저 apply해야 합니다 (Parameter Store 값을 읽음).
#
# [구축 전 협의 항목]
#   항목                     협의 대상            값
#     서버 접근 경로         고객 보안팀          ec2_common_sg_ingress (포트, 출발지 prefix list)
#     서버 사양·AMI          고객 (서비스 담당)   was/webide.ami, instance_type, ebs_volumes
#     서비스 포트·헬스체크   고객 (서비스 담당)   app_port, health_check_path
#     LB 공개 범위           고객 보안팀          enable_alb, alb_internal (외부용은 enable_public 필요)
#     서비스 도메인 이름     고객 DNS 담당        alb_record_name
#     WAF                    고객 보안팀          외부용 LB에 붙일 Web ACL (필요 시 main.tf에서 ec2-<용도>의 waf_acl_arn으로 넘김)
#     알림 받는 사람         고객 운영팀          alarm_emails
#     주말 중지 대상·시간    고객 운영팀          ec2_weekend_stop, was/webide.weekend_stop_enable
#     접근 로그              고객 보안팀          enable_alb_access_logs
############################################################
site        = "simple"
environment = "dev"
region      = "ap-northeast-2"

common_tags = {}

# ALB 접근 로그 (central_log_bucket_arn = null이면 00-bootstrap 로그 버킷)
enable_alb_access_logs = true

# 알림 이메일 (넣으면 SNS 토픽 생성)
alarm_emails = []

# ── EC2 공통 SG (서버 접근용, 고객사마다 다름) ─────────────────
# 출발지는 01-network의 prefix list 이름을 권장합니다. description은 영문만.
ec2_common_sg_ingress = [
  # { from_port = 22, to_port = 22, protocol = "tcp", prefix_lists = ["access_ctl"], description = "server access control" },
]

# ── WAS ───────────────────────────────────────────────────────
was = {
  ami             = "ami-05377cf8cfef186c2" # ← 사용할 AMI로 변경
  instance_type   = "t3.micro"
  ebs_volumes     = [{ device_name = "/dev/xvdb", volume_size = 20 }]
  enable_alb      = true
  alb_internal    = true # 외부용(false)은 01-network enable_public = true 필요
  alb_record_name = "web"
  app_port        = 8080
}

# ── Web IDE ───────────────────────────────────────────────────
webide = {
  ami           = "ami-0eff555c11692fc96" # ← 사용할 AMI로 변경
  instance_type = "t3.medium"
  enable_alb    = false
}

# ── EC2 주말 중지 (협의 후 적용) ───────────────────────────────
# enabled = true      : Lambda와 스케줄 생성 (01-network interface_endpoints에 "ec2" 필요)
# schedule_enabled    : 협의가 끝나기 전에는 false (스케줄이 실행되지 않음). 아래 시간은 임시 값
# 대상 서버는 태그로 켜고 끔: was/webide의 weekend_stop_enable = true → WEEKEND_STOP_ENABLE = "true"
# dry_run = true      : 실제로 중지하지 않고 대상만 로그로 확인
ec2_weekend_stop = {
  enabled          = false
  schedule_enabled = false
  # stop_schedule  = "cron(0 21 ? * FRI *)"
  # start_schedule = "cron(0 7 ? * MON *)"
}
