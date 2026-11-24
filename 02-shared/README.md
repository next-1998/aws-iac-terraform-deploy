# 02-shared

여러 유형(03-compute, 03-database …)이 같이 쓰는 리소스를 만듭니다. 조합 코드는 `deployment/shared-common`입니다.

| 리소스 | 내용 |
|---|---|
| ACM 인증서 | `<site>.<root_domain>`, `*.<site>.<root_domain>` (DNS 검증) |
| SNS 알림 토픽 | `alarm_emails`가 있을 때만 |

- 입력: `/iac/<site>/01-network/base`, `dns`
- 출력: `/iac/<site>/02-shared/shared` (`certificate_arn`, `alarm_topic_arn`)
- 순서: 01-network → **02-shared** → 03-compute, 03-database
