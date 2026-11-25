# 02-shared

여러 유형(03-compute, 03-database …)이 같이 쓰는 리소스를 만듭니다. 조합 코드는 `deployment/shared-common`입니다.

| 리소스 | 내용 |
|---|---|
| ACM 인증서 | `<site>.<root_domain>`, `*.<site>.<root_domain>` (DNS 검증) |
| SNS 알림 토픽 | `alarm_emails`가 있을 때만 |
| AWS Backup 볼트·플랜·IAM 역할·백업 키 | `enable_backup` (기본 켬). 대상은 리소스 태그 `Backup = <플랜 이름>` + `Site = <site>`. 기본 플랜 daily(7일)·monthly(12개월), 볼트 잠금 기본 끔 |

- 입력: `/iac/<site>/01-network/base`, `dns`
- 출력: `/iac/<site>/02-shared/shared` (`certificate_arn`, `alarm_topic_arn`, `backup_tag_key`, `backup_plans`, `backup_vault`)
- 순서: 01-network → **02-shared** → 03-compute, 03-database
