############################################################
# 02-resource — 사이트: simple (예시 값. 실제 값으로 바꿔서 사용)
# 01-network를 먼저 apply해야 합니다 (Parameter Store 값을 읽음).
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
