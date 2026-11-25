# 03-database

DB 유형 전체를 하나의 state로 만듭니다. 03-compute와 같은 번호라 **서로 의존하지 않고 병렬로 apply할 수 있습니다** (01-network만 읽음).

| 모듈 | 조합 코드 | 만드는 것 |
|---|---|---|
| `rds_common` | `deployment/rds-common` (1차 조합) | DB 서브넷(AZ별, 01-network가 계산한 db CIDR), 라우트(사내망 TGW 응답 경로), DB 서브넷 그룹, RDS 키 |
| `rds_db["<용도>"]` | `deployment/rds-db` (2차 조합, DB마다 한 번) | 파라미터 그룹, DB 인스턴스, SG, DB 로그 그룹 |

```bash
cp backend.hcl.example backend.hcl   # 값 입력
terraform init -backend-config=backend.hcl
terraform apply
```

- 입력: `/iac/<site>/01-network/{base,subnets,routing}`, `/iac/_account/00-bootstrap/kms` (logs 키)
- 출력: `/iac/<site>/03-database/rds` (용도별 접속 주소, 포트, 비밀 ARN, SG ID. **비밀번호 자체는 없음**)
- RDS는 AZ 2개 이상 필요 (01-network `az_count` ≥ 2, plan에서 검사)

## 설계

| 항목 | 내용 |
|---|---|
| 엔진 | PostgreSQL, MySQL (`rds.<용도>.engine`). Aurora, Oracle, SQL Server, 주말 중지는 추후 |
| 읽기 복제본 | `rds.<용도>.replicas = { r1 = {}, … }` → `<site>-rds-<용도>-<키>`. 원본과 같은 SG·파라미터 그룹·RDS 키, 복제본마다 로그 그룹. 원본 자동 백업 필요(plan에서 검사). 출력 `readers`에 읽기 주소 |
| 스냅샷으로 배포 | `rds.<용도>.snapshot_identifier` (DB "이미지"). **처음 만들 때만 적용**, 이후 바꿔도 다시 만들지 않음 (바꾸려면 `-replace`). 복원 뒤 비밀번호는 Secrets Manager 관리로 바뀜. 다른 키로 암호화된 스냅샷은 RDS 키로 복사해서 지정 |
| 파라미터 | DBA에게 받은 값만 `deployment/rds-db/src/rds-<용도>.parameters.csv` (`no,name,value,apply_method,memo`). 나머지는 엔진 기본값 |
| 관리자 비밀번호 | **RDS가 Secrets Manager에 만들고 관리** (`manage_master_user_password`). tfvars·state에 비밀번호 없음. 애플리케이션은 `secret_arn`으로 읽음 (폐쇄망이면 01-network에 `secretsmanager` endpoint 필요) |
| 암호화 | 저장소·비밀·Performance Insights 모두 RDS 키 (`alias/iac/<site>/rds`, 중앙 키면 `central_kms_key_arns.rds`) |
| 접근 | DB 포트 ← **EC2 서브넷 대역** (03-compute와 병렬이라 SG 대신 대역). 추가는 `deployment/rds-db/src/rds-<용도>.sg_rules.csv` (`sg` = `db`) |
| 이중화 | `operation_mode = "enable"`이면 Multi-AZ (DB별 `multi_az`로 바꿀 수 있음) |
| 삭제 보호 | `operation_mode` / `deletion_protection.rds`: 삭제 방지 + 삭제 시 최종 스냅샷. 테스트(기본)는 바로 삭제 |
| 로그 | DB 로그를 CloudWatch로 보냄 (보관 기간·logs 키). **로그 그룹 이름은 AWS가 `/aws/rds/instance/<identifier>/<로그>`로 고정** → "로그 그룹은 `/<VPC 이름>/…`" 규칙의 예외. 미리 만들어 두어 보관 기간·암호화를 Terraform이 정함 |
