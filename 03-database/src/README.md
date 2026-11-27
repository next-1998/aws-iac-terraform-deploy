# 03-database/src

| 파일 | 내용 |
|---|---|
| `databases.csv` | DB 목록 (선택). 없으면 tfvars(`rds_postgres` 등)만 씀. 예: `databases.example.csv` |

## databases.csv

DB마다 한 줄. 자주 정하는 값만 받고 나머지는 tfvars 기본값과 같습니다. 엑셀에서 "CSV UTF-8"로 저장해도 됩니다.

| 열 | 값 | 비우면 |
|---|---|---|
| `no` | 순번 (1 이상, 중복 불가) | 필수 |
| `name` | DB 키 (소문자로 시작, 소문자·숫자 12자 이하). 이름 `<접두어>-rds-<엔진 코드>-<name>-01` | 필수 |
| `engine` | `postgres` `mysql` `mariadb` `aurora_postgres` `aurora_mysql` | 필수 |
| `engine_version` | 주 버전 (`16`, `8.0`, `10.11`) | 엔진 기본 |
| `instance_class` | `db.t4g.medium` 등. Aurora Serverless v2는 `serverless:<최소 ACU>-<최대 ACU>` | RDS `db.t4g.micro`, Aurora `db.t4g.medium` |
| `storage` / `max_storage` | GB (RDS만, Aurora는 비움) | 20 / 100 |
| `multi_az` | `true` / `false` | `operation_mode`를 따름 (운영이면 켬) |
| `db_name`, `port` | 처음 만들 DB 이름, 포트 | 없음 / 엔진 기본 |
| `backup` | `true`면 AWS Backup daily + pitr | `false` |
| `snapshot_identifier` | 복원할 스냅샷 이름 또는 ARN (처음 만들 때만) | 새로 만듦 |
| `replica` | `true`면 원본과 같은 사양의 읽기 복제본 하나 (Aurora는 클러스터 인스턴스 하나 추가). 나중에 켜도 됨 | `false` |
| `nlb_allowed_cidrs` | NLB로 접속할 대역, `;`로 여러 개 | NLB 없음 |
| `nlb_private_ips` | NLB 고정 IP (개별 NLB만): `<AZ 끝 글자>=<IP>`, `;`로 여러 개 (예 `a=10.227.0.200;c=10.227.1.200`). 재배포 때 같은 IP가 필요하면 넣음 | 자동 (NLB를 지울 때까지 유지) |
| `memo` | 메모 (Terraform은 쓰지 않음) | |

- 한 DB는 tfvars나 CSV 한 곳에만 적습니다 (같은 키면 plan에서 막힘).
- 사이트 단위 값은 tfvars: `rds_nlb`(개별/통합, 대상 등록 방법), `rds_master_passwords`(RDS 복제본은 필수, 커밋하지 않는 파일에만), `operation_mode`.
- CSV에 없는 설정(로그 종류, 모니터링 주기, 복제본별 사양 등)이 필요하면 그 DB는 tfvars로 적습니다.
- 파라미터 그룹 값·추가 SG 규칙은 DB별 CSV: `deployment/<엔진>/src/rds-<DB 키>.parameters.csv`, `rds-<DB 키>.sg_rules.csv`.
