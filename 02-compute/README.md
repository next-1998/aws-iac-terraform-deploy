# 02-compute

EC2 유형 전체를 하나의 state로 만듭니다. 사이트마다 구성이 다르므로 `main.tf`의 모듈 호출과 `terraform.tfvars`를 사이트에 맞게 고칩니다.

| 모듈 | 조합 코드 | 단계 |
|---|---|---|
| `ec2_common` | `deployment/ec2-common` (서브넷, 라우트, 공통 SG, 주말 중지) | 1차 조합 |
| `ec2_was`, `ec2_webide` | `deployment/ec2-was`, `deployment/ec2-webide` | 2차 조합 (용도별) |

- 입력: `/iac/<site>/01-network/*`, `/iac/<site>/02-shared/shared` (인증서)
- 출력: `/iac/<site>/02-compute/ec2` (공통 SG, 용도별 SG — 03-eks가 EKS API 접근 허용에 사용)
- 순서: 01-network → 02-shared → **02-compute**
- 용도를 추가할 때는 `deployment/ec2-<용도>`를 비슷한 것에서 복사해 만들고 `main.tf`에서 호출합니다.
