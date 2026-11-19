############################################################
# 02-shared — 사이트: simple (예시 값. 실제 값으로 바꿔서 사용)
# 01-network를 먼저 apply해야 합니다 (Parameter Store 값을 읽음).
#
# [구축 전 협의 항목]
#   항목                     협의 대상            값
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
