# 03-database (예정)

DB 유형(RDS, ElastiCache …) 전체를 하나의 state로 만듭니다. 03-compute와 같은 구조입니다.

| 모듈 | 조합 코드 | 단계 |
|---|---|---|
| `rds_common` | `deployment/rds-common` (db 서브넷, DB subnet group, 공통 SG, KMS, 주말 중지) | 1차 조합 |
| `rds_<용도>` | `deployment/rds-<용도>` (parameter group, instance, 개별 SG) | 2차 조합 (용도별) |

- 입력: `/iac/<site>/01-network/*` (db 서브넷 CIDR은 network-base가 계산), `/iac/<site>/02-shared/shared`
- 출력: `/iac/<site>/03-database/<묶음>`
- RDS는 AZ 2개 이상이 필요합니다 (01-network `az_count` ≥ 2, plan에서 검사 예정).
- 주말 중지는 rds-common에 EC2와 같은 방식(Lambda는 VPC 안, rds endpoint 필요)으로 둡니다.
