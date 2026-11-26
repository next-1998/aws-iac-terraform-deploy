# 03-database

DB 유형 전체를 하나의 state로 만듭니다. 03-compute와 같은 번호라 **서로 의존하지 않고 병렬로 apply할 수 있습니다** (01-network, 02-shared를 읽고 03-compute 값은 읽지 않음).

| 모듈 | 조합 코드 | 만드는 것 |
|---|---|---|
| `rds_common` | `deployment/rds-common` (1차 조합) | DB 서브넷(AZ별, 01-network가 계산한 db CIDR), 라우트(사내망 TGW 응답 경로), DB 서브넷 그룹, RDS 키 |
| `rds_postgres["<DB 키>"]` / `rds_mysql[…]` / `rds_mariadb[…]` | `deployment/rds-postgres`, `rds-mysql`, `rds-mariadb` (엔진 조합: 엔진 고정값·엔진 전용 검사·CSV) | → `deployment/rds-core` (공통 코어): 파라미터 그룹, DB 인스턴스, 복제본, SG, DB 로그 그룹 |
| `aurora_postgres["<DB 키>"]` / `aurora_mysql[…]` | `deployment/aurora-postgres`, `aurora-mysql` (엔진 조합) | → `deployment/aurora-core`: 클러스터, 인스턴스(쓰기 1 + 읽기 N), 파라미터 그룹 2개(클러스터·인스턴스), SG, 로그 그룹, 백업 태그(클러스터), NLB(쓰기 주소 DNS 기준) |

```bash
cp backend.hcl.example backend.hcl   # 값 입력
terraform init -backend-config=backend.hcl
terraform apply
```

- 입력: `/iac/<site>/01-network/{base,subnets,routing,endpoints}`, `/iac/<site>/02-shared/shared` (백업 플랜 목록), `/iac/_account/00-bootstrap/kms` (logs 키)
- 출력: `/iac/<site>/03-database/rds` (용도별 접속 주소, 포트, 비밀 ARN, SG ID. **비밀번호 자체는 없음**)
- RDS는 AZ 2개 이상 필요 (01-network `az_count` ≥ 2, plan에서 검사)

## 설계

| 항목 | 내용 |
|---|---|
| 엔진 | 엔진별 목록 `rds_postgres`, `rds_mysql`, `rds_mariadb`. 쓰는 엔진 목록만 채움. Aurora(`aurora-core`), Oracle·SQL Server는 같은 틀로 추후 |
| 이름 | DB `<접두어>-rds-<엔진 코드>-<DB 키>-01` (pg / my / mdb), 복제본 `…-<DB 키>-ro-01`, 파라미터 그룹 `<접두어>-rds-pagrp-<엔진·주버전>-<DB 키>-01` (pg16 / my80 / mdb1011), 서브넷 그룹 `<접두어>-rds-sng-main-01`. DB 키는 엔진이 달라도 겹치면 안 됨 |
| 읽기 복제본 | `<엔진 목록>.<DB 키>.replicas = { r1 = {}, … }` → `<접두어>-rds-<엔진>-<DB 키>-ro-01`, `-02` (키 이름순). 원본과 같은 SG·파라미터 그룹·RDS 키, 복제본마다 로그 그룹. 원본 자동 백업 필요(plan에서 검사). 출력 `readers`에 읽기 주소 |
| 스냅샷으로 배포 | `<엔진 목록>.<DB 키>.snapshot_identifier` (DB "이미지"). **처음 만들 때만 적용**, 이후 바꿔도 다시 만들지 않음 (바꾸려면 `-replace`). 복원 뒤 비밀번호는 Secrets Manager 관리로 바뀜. 다른 키로 암호화된 스냅샷은 RDS 키로 복사해서 지정 |
| 파라미터 | DBA에게 받은 값만 `deployment/rds-<엔진>/src/rds-<DB 키>.parameters.csv` (`no,name,value,apply_method,memo`). 나머지는 엔진 기본값 |
| 관리자 비밀번호 | **RDS가 Secrets Manager에 만들고 관리** (`manage_master_user_password`). tfvars·state에 비밀번호 없음. 애플리케이션은 `secret_arn`으로 읽음 (폐쇄망이면 01-network에 `secretsmanager` endpoint 필요) |
| 암호화 | 저장소·비밀·Performance Insights 모두 RDS 키 (`alias/<접두어>-kms-rds-01`, 중앙 키면 `central_kms_key_arns.rds`) |
| 접근 | DB 포트 ← **EC2 서브넷 대역** (03-compute와 병렬이라 SG 대신 대역). 추가는 `deployment/rds-<엔진>/src/rds-<DB 키>.sg_rules.csv` (`sg` = `db`) |
| 이중화 | `operation_mode = "enable"`이면 Multi-AZ (DB별 `multi_az`로 바꿀 수 있음) |
| 고정 IP (NLB) | 특수 상황에만 (기본 없음). 사이트에서 `rds_nlb = { mode = "dedicated" }`(개별) 또는 `{ mode = "shared" }`(통합) 하나로 정하고(섞지 않음), 연결할 DB에 `nlb = { allowed_cidrs }`. 리스너 = DB port, 대상은 원본·대기 IP(상태 확인이 활성만 사용). 읽기 복제본은 NLB에 연결하지 않음(용도가 달라 분리, 복제본 SG도 별도). 대상 IP는 rds-common 동기화 Lambda가 DB SG의 ENI로 1분마다 맞춤. 고정 IP는 출력 `nlb.private_ips` |
| 삭제 보호 | `operation_mode` / `deletion_protection.rds`: 삭제 방지 + 삭제 시 최종 스냅샷. 테스트(기본)는 바로 삭제 |
| 로그 | DB 로그를 CloudWatch로 보냄 (보관 기간·logs 키). **로그 그룹 이름은 AWS가 `/aws/rds/instance/<identifier>/<로그>`로 고정** → "로그 그룹은 `/<VPC 이름>/…`" 규칙의 예외. 미리 만들어 두어 보관 기간·암호화를 Terraform이 정함 |
