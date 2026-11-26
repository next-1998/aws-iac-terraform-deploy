############################################################
# 00-bootstrap — 계정 단위 (예시 값. 실제 값으로 바꿔서 사용)
# 계정·리전마다 한 번, 다른 단계보다 먼저 apply합니다 (state는 로컬 → 이후 S3 백업).
# 적지 않은 항목은 기본값을 씁니다 (variables.tf 참고).
#
# [구축 전 협의 항목]
#   항목                     협의 대상            값
#     이름 규칙              고객 (표준 담당)     naming (회사·서비스·환경 코드). 모든 리소스 이름의 앞부분 → NAMING.md
#     암호화 키 (CMK)        고객 보안팀          central_kms_key_arns (조직 중앙 CMK를 쓸지, 쓰면 용도별 키 ARN)
#     로그 보관 위치·기간    고객 보안팀          create_log_bucket, cloudwatch_logs_bucket_arn / cloudwatch_logs_destination_arn (중앙 로그 계정),
#                                                 log_retention_days (S3, 기본 365일), cloudwatch_log_retention_days (CloudWatch, 기본 14일)
#     로그 S3 전송           고객 보안팀          enable_log_subscription (계정 전체 CloudWatch Logs → S3)
#     백업                   고객 운영팀          manage_backup_region_settings (서드파티 백업이면 false), backup_resource_types
#     삭제 보호 (운영 모드)  고객 운영팀          operation_mode, deletion_protection
############################################################
region = "ap-northeast-2"

# ── 이름 규칙 앞부분 (필수) ───────────────────────────────────
# 결과: <company>-<service>-<env>-<리전 코드>  예) hw-iac-dev-an2
#   각 값은 소문자·숫자 1~8자 (하이픈 불가). 리전 코드는 region에서 자동 (ap-northeast-2 → an2)
#   여기서 정한 값을 Parameter Store에 남기고, 모든 단계가 읽어 리소스 이름 앞에 붙입니다 (NAMING.md)
#   처음 배포할 때 정하고 바꾸지 않습니다 (바꾸면 대부분의 리소스가 다시 만들어짐)
naming = {
  company = "hw"  # 회사 코드
  service = "iac" # 서비스 코드
  env     = "dev" # 환경 코드 (dev, stg, prd …)
  # region_code = "an2" # 리전 코드 표에 없는 리전만
}

common_tags = {}

# ── 로그 ──────────────────────────────────────────────────────
# 모든 CloudWatch 로그 그룹을 S3 로그 버킷으로 보냄 (계정 단위 구독). 쓰지 않는 환경은 false
enable_log_subscription = false

# ── 운영 모드 (삭제 보호) ─────────────────────────────────────
# operation_mode = "enable" : 운영. 버킷·KMS 키 삭제 불가, KMS 삭제 대기 30일 등
# 그 외(null, 기본)         : 모두 삭제 가능 (테스트처럼 만들고 지우는 환경)
operation_mode = null
