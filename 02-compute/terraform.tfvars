############################################################
# 02-compute — 사이트: simple (예시 값. 실제 값으로 바꿔서 사용)
# 01-network, 02-shared를 먼저 apply해야 합니다 (Parameter Store 값을 읽음).
#
# [구축 전 협의 항목]
#   항목                     협의 대상            값
#     암호화 키 (CMK)        고객 보안팀          central_kms_key_arns (조직 중앙 CMK를 쓸지, 쓰면 용도별 키 ARN)
#     SG 규칙 (접근 경로)    고객 보안팀          deployment/ec2-*/src/sg_rules.csv (포트, 출발지 prefix list)
#     서버 사양·AMI          고객 (서비스 담당)   was/webide.ami, instance_type, ebs_volumes
#     서비스 포트·헬스체크   고객 (서비스 담당)   app_port, health_check_path
#     LB 공개 범위           고객 보안팀          enable_alb, alb_internal (외부용은 enable_public 필요)
#     서비스 도메인 이름     고객 DNS 담당        alb_record_name
#     WAF                    고객 보안팀          외부용 LB에 붙일 Web ACL (필요 시 main.tf에서 ec2-<용도>의 waf_acl_arn으로 넘김)
#     주말 중지 대상·시간    고객 운영팀          ec2_weekend_stop, was/webide.weekend_stop_enable
#     접근 로그              고객 보안팀          enable_alb_access_logs
#     로그 최종 보관 기간    고객 보안팀          00-bootstrap log_retention_days (S3, 기본 365일. CloudWatch는 14일)
############################################################
site        = "simple"
environment = "dev"
region      = "ap-northeast-2"

common_tags = {}

# ALB 접근 로그 (central_log_bucket_arn = null이면 00-bootstrap 로그 버킷)
enable_alb_access_logs = true

# ── 보안 그룹 규칙 (CSV) ──────────────────────────────────────
# SG 규칙은 tfvars가 아니라 그 SG를 만드는 폴더의 src/sg_rules.csv에 넣습니다.
#   공통 SG(서버 접근)  : deployment/ec2-common/src/sg_rules.csv   (sg 열: common)
#   용도별 SG, ALB SG   : deployment/ec2-<용도>/src/sg_rules.csv   (sg 열: app, alb)
# 서비스에 꼭 필요한 기본 규칙은 코드에 이미 있고, CSV에는 협의한 추가 규칙만 넣습니다.

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

# ── 암호화 키 (CMK) ───────────────────────────────────────────
# EC2 볼륨은 계정 EBS 기본 키(00-bootstrap의 ebs)로 암호화되므로 이 단계에서 만드는 키는 없습니다.
# 같은 tfvars 값을 여러 단계가 같이 쓸 수 있도록 변수만 받습니다.
# 조직 중앙 계정의 CMK를 쓰면 용도별로 키 ARN을 넣습니다 (넣은 용도는 키를 만들지 않음).
#   - alias가 아니라 키 ARN이어야 합니다 (다른 계정 alias는 쓸 수 없음)
#   - 중앙 키 정책에 이 계정과 서비스 사용 권한이 있어야 합니다 (중앙 계정 사전 요청)
#   - 중앙 키 하나로 모든 용도를 쓰지 말고 용도별로 분리하세요
central_kms_key_arns = {
  # ebs = "arn:aws:kms:ap-northeast-2:<중앙 계정>:key/<키 ID>"   # 00-bootstrap에서 사용
}

# ── 운영 모드 (삭제 보호) ─────────────────────────────────────
# operation_mode = "enable" : 운영. 버킷·KMS 키·NAT EIP 삭제 불가, KMS 삭제 대기 30일, ALB 삭제 보호, EC2 볼륨은 서버 삭제 후에도 남김
# 그 외(null, 기본)         : 모두 삭제 가능 (테스트처럼 만들고 지우는 환경)
# 처음 배포할 때 정하고 바꾸지 않습니다 (바꾸면 버킷·KMS 키·EIP가 새로 만들어짐). 모든 단계에 같은 값을 넣습니다
operation_mode = null

# 항목별 선택 (비우면 operation_mode를 따름. true = 삭제 불가, false = 삭제 가능)
deletion_protection = {
  # buckets     = true # state·로그 버킷 (00-bootstrap)
  # kms_keys    = true # KMS 키 (00-bootstrap, 02-shared)
  # nat_eip     = true # NAT EIP (01-network)
  # alb         = true # ALB 삭제 보호 (02-compute)
  # ec2_volumes = true # 서버 삭제 후 EBS 볼륨 유지 (02-compute)
}
