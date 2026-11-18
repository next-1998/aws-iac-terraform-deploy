# shared-common

`02-resource` 단계에서 **여러 유형이 같이 쓰거나, 모든 리소스가 대상인 것**만 만듭니다.

| 리소스 | 기본 | 설명 |
|---|---|---|
| 사이트 ACM 인증서 | 생성 | `<site>.<root_domain>`, `*.<site>.<root_domain>`. 용도별 ALB가 같이 씀. DNS 검증 레코드는 사이트 public 존(있을 때) 또는 상위 존 |
| SNS 알림 토픽 | 이메일을 주면 생성 | 리소스별 알람이 같은 곳으로 보냄 |

KMS 키는 기본적으로 각 리소스의 `<유형>-common`이 만듭니다. 고객사가 공용 키를 요구할 때만 여기에 추가합니다.

주말 중지 Lambda는 대상 서비스의 `-common`에 둡니다(EC2: `ec2-common`, RDS: `rds-common`). Lambda는 필요한 서비스의 `-common`에 두는 것이 원칙입니다.
