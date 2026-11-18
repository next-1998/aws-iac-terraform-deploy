# 02-resource

01-network 값을 Parameter Store에서 읽어 리소스를 만듭니다. 사이트마다 구성이 다르므로 `main.tf`의 모듈 호출과 `terraform.tfvars`를 사이트에 맞게 고칩니다.

| 모듈 | 조합 코드 |
|---|---|
| `shared_common` | `deployment/shared-common` (인증서, 알림) |
| `ec2_common` | `deployment/ec2-common` |
| `ec2_was`, `ec2_webide` | `deployment/ec2-was`, `deployment/ec2-webide` |

새 유형(예: RDS)을 추가할 때는 `deployment/rds-common`, `deployment/rds-<용도>`를 만들고 여기서 호출합니다.

결과는 `/iac/<site>/02-resource/ec2`, `shared`에 남깁니다(03-eks가 EKS API 접근 허용 SG로 사용).
