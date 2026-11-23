############################################################
# 02-shared — 사이트: simple (예시 값. 실제 값으로 바꿔서 사용)
# 01-network를 먼저 apply해야 합니다 (Parameter Store 값을 읽음).
#
# [구축 전 협의 항목]
#   항목                     협의 대상            값
#     암호화 키 (CMK)        고객 보안팀          central_kms_key_arns (조직 중앙 CMK를 쓸지, 쓰면 용도별 키 ARN)
#     사이트 인증서          고객 DNS 담당        enable_certificate (01-network root_domain 필요)
#     알림 받는 사람         고객 운영팀          alarm_emails
############################################################
site        = "simple"
environment = "dev"
region      = "ap-northeast-2"

common_tags = {}

enable_certificate = true

# 알림 이메일 (넣으면 SNS 토픽 생성)
alarm_emails = []

# ── 암호화 키 (CMK) ───────────────────────────────────────────
# 기본: 리소스별로 이 계정에 CMK를 하나씩 만듭니다. 이 단계: sns (알림 토픽, alarm_emails가 있을 때)
#   logs (CloudWatch 로그 그룹) 키는 계정 기본이라 00-bootstrap이 만들고, 중앙 키도 00-bootstrap에 넣습니다
# 조직 중앙 계정의 CMK를 쓰면 용도별로 키 ARN을 넣습니다 (넣은 용도는 키를 만들지 않음).
#   - alias가 아니라 키 ARN이어야 합니다 (다른 계정 alias는 쓸 수 없음)
#   - 중앙 키 정책에 이 계정과 서비스 사용 권한이 있어야 합니다 (중앙 계정 사전 요청)
#   - 중앙 키 하나로 모든 용도를 쓰지 말고 용도별로 분리하세요
central_kms_key_arns = {
  # sns = "arn:aws:kms:ap-northeast-2:<중앙 계정>:key/<키 ID>"
}
