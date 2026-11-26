############################################################
# 02-shared — 사이트: simple (예시 값. 실제 값으로 바꿔서 사용)
# 01-network를 먼저 apply해야 합니다 (Parameter Store 값을 읽음).
#
# [구축 전 협의 항목]
#   항목                     협의 대상            값
#     암호화 키 (CMK)        고객 보안팀          central_kms_key_arns (조직 중앙 CMK를 쓸지, 쓰면 용도별 키 ARN)
#     사이트 인증서          고객 DNS 담당        enable_certificate (01-network root_domain 필요)
#     알림 받는 사람         고객 운영팀          alarm_emails
#     백업 정책              고객 운영팀          backup_plans (주기·보관 기간), backup_vault_lock (보관 기간 전 삭제 금지 여부)
#     백업 대상              고객 운영팀·개발팀   리소스 태그 Backup = <플랜 이름> (구성 후 대상 리소스에 태그를 붙임)
############################################################
site        = "simple"
environment = "dev"
region      = "ap-northeast-2"

common_tags = {}

enable_certificate = true

# 알림 이메일 (넣으면 SNS 토픽 생성)
alarm_emails = []

# ── AWS Backup ────────────────────────────────────────────────
# 볼트·플랜·IAM 역할을 만들고, 태그가 붙은 리소스만 백업합니다 (AWS Backup이 지원하는 모든 유형: EC2·EBS·RDS·EFS·S3·DynamoDB 등).
#   대상 지정: 리소스에 태그 Backup = <플랜 이름> (예: Backup = daily). 03-database·03-compute는 backup_plan 값으로 태그를 붙임
#   원칙: AWS Backup이 지원하는 리소스는 AWS Backup만 사용 (지원하지 않을 때만 자체 백업). Site 태그가 이 사이트여야 함 (모든 모듈이 자동으로 붙임)
#   비용: 볼트·플랜은 무료. 백업 데이터 저장량만큼 과금 + 백업 키 월 $1 (중앙 backup 키를 쓰면 없음)
#   리소스 유형 사용 설정은 00-bootstrap이 합니다
enable_backup = true

# 플랜 이름 → 규칙 이름 → 규칙. 플랜 이름이 태그 값이 됩니다 (리소스는 플랜 하나에만 들어가므로 같이 받을 규칙은 한 플랜에). 시간은 Asia/Seoul 기준 (timezone으로 변경)
#   schedule                : cron(분 시 일 월 요일 년)
#   retention_days          : 보관 일수
#   cold_storage_after_days : 콜드 스토리지로 옮길 일수 (선택. 보관 일수 ≥ 이 값 + 90)
#   continuous_backup       : 시점 복구 (선택. RDS·S3, 보관 35일 이하)
backup_plans = {
  daily   = { daily = { schedule = "cron(0 3 * * ? *)", retention_days = 7 } }     # 매일 03:00, 7일 보관
  monthly = { monthly = { schedule = "cron(0 3 1 * ? *)", retention_days = 365 } } # 매월 1일 03:00, 12개월 보관
  # 시점 복구(연속 백업) + 일간 스냅샷. RDS·S3 등 연속 백업 지원 리소스에 태그 Backup = "pitr" (03-database rds.<용도>.backup_plan)
  #   시점 복구 보관 일수는 03-database backup_retention_days와 같게 둡니다 (AWS Backup이 RDS 자동 백업 보관 기간을 이 값으로 바꿈)
  pitr = {
    pitr  = { schedule = "cron(0 3 * * ? *)", retention_days = 7, continuous_backup = true }
    daily = { schedule = "cron(0 3 * * ? *)", retention_days = 7 }
  }
  # weekly = { weekly = { schedule = "cron(0 3 ? * SUN *)", retention_days = 35 } }
}

# 볼트 잠금 (기본 끔). 켜면 보관 기간 전에는 관리자도 백업을 지울 수 없습니다.
#   changeable_for_days(최소 3일)가 지나면 잠금 해제·볼트 삭제가 영구히 불가 (Compliance). 비우면 Governance (권한 있는 사용자는 해제 가능)
backup_vault_lock = null
# backup_vault_lock = { min_retention_days = 7, max_retention_days = 365, changeable_for_days = 3 }

# ── 암호화 키 (CMK) ───────────────────────────────────────────
# 기본: 리소스별로 이 계정에 CMK를 하나씩 만듭니다. 이 단계: sns (알림 토픽, alarm_emails가 있을 때), backup (백업 볼트)
#   logs (CloudWatch 로그 그룹) 키는 계정 기본이라 00-bootstrap이 만들고, 중앙 키도 00-bootstrap에 넣습니다
# 조직 중앙 계정의 CMK를 쓰면 용도별로 키 ARN을 넣습니다 (넣은 용도는 키를 만들지 않음).
#   - alias가 아니라 키 ARN이어야 합니다 (다른 계정 alias는 쓸 수 없음)
#   - 중앙 키 정책에 이 계정과 서비스 사용 권한이 있어야 합니다 (중앙 계정 사전 요청)
#   - 중앙 키 하나로 모든 용도를 쓰지 말고 용도별로 분리하세요
central_kms_key_arns = {
  # sns = "arn:aws:kms:ap-northeast-2:<중앙 계정>:key/<키 ID>"
  # backup = "arn:aws:kms:ap-northeast-2:<중앙 계정>:key/<키 ID>" # 백업 볼트
}

# ── 운영 모드 (삭제 보호) ─────────────────────────────────────
# operation_mode = "enable" : 운영. 버킷·KMS 키·NAT EIP 삭제 불가, KMS 삭제 대기 30일, ALB 삭제 보호, EC2 볼륨은 서버 삭제 후에도 남김, RDS 삭제 보호(최종 스냅샷)·Multi-AZ, 백업 볼트 보존
# 그 외(null, 기본)         : 모두 삭제 가능 (테스트처럼 만들고 지우는 환경)
# 처음 배포할 때 정하고 바꾸지 않습니다 (바꾸면 버킷·KMS 키·EIP가 새로 만들어짐). 모든 단계에 같은 값을 넣습니다
operation_mode = null

# 항목별 선택 (비우면 operation_mode를 따름. true = 삭제 불가, false = 삭제 가능)
deletion_protection = {
  # buckets     = true # state·로그 버킷 (00-bootstrap)
  # kms_keys    = true # KMS 키 (00-bootstrap, 02-shared)
  # nat_eip     = true # NAT EIP (01-network)
  # alb         = true # ALB 삭제 보호 (03-compute)
  # ec2_volumes = true # 서버 삭제 후 EBS 볼륨 유지 (03-compute)
  # rds         = true # RDS 삭제 보호 + 삭제 시 최종 스냅샷 (03-database)
  # backups     = true # 백업 볼트 삭제 불가·남은 백업 보존 (02-shared)
}
