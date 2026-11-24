# 00-bootstrap

**계정·리전마다 한 번** 실행합니다. 다른 단계(01~04)의 state를 저장할 버킷과 로그 버킷을 만듭니다.

| 리소스 | 기본 | 설명 |
|---|---|---|
| state 버킷 `iac-tfstate-<계정ID>-<리전>` | 생성 | 버전 관리, 암호화, 퍼블릭 차단, HTTPS만 허용, **삭제 보호** |
| 로그 버킷 `iac-logs-<계정ID>-<리전>` | 생성 | Flow Logs, ALB 접근 로그, CloudWatch Logs(내보낸 것). SSE-S3, **30일 후 Glacier, 365일 후 삭제** (기본값, 최종 보관일은 고객 협의) |
| Parameter Store | 생성 | `/iac/_account/00-bootstrap/state`, `/iac/_account/00-bootstrap/logs` |

## 실행

```bash
cd 00-bootstrap
terraform init
terraform apply          # 필요하면 -var-file=terraform.tfvars
terraform output backend_hcl_example
```

이 단계의 state는 로컬(`terraform.tfstate`)에 남습니다. 잃어버려도 버킷은 그대로 있지만, Terraform으로 다시 관리하려면 import가 필요하니 안전한 곳에 보관하세요.

### state 옮기기 (선택)
버킷이 만들어진 뒤 이 단계의 state도 버킷에 두려면, `versions.tf`에 `backend "s3" {}`를 추가하고 `terraform init -migrate-state -backend-config=backend.hcl`을 실행합니다. 경로는 `_account/00-bootstrap/terraform.tfstate`를 권장합니다.

### 운영 체크리스트 (이 단계 state)
이 단계는 state 버킷을 만드는 단계라 처음에는 state가 **로컬 파일**에 남습니다. 잃어버리면 리소스는 남아도 Terraform으로 다시 관리하려면 import가 필요합니다.

- [ ] apply 직후 `terraform.tfstate`를 안전한 곳(접근 제한된 저장소)에 백업
- [ ] 위 "state 옮기기"로 버킷(`_account/00-bootstrap/terraform.tfstate`)으로 이관
- [ ] 이관 후 `terraform plan`이 "변경 없음"인지 확인
- [ ] 확인 후 로컬 `terraform.tfstate`, `terraform.tfstate.backup` 삭제 (state에 민감 정보가 있을 수 있음)
- [ ] 이관 여부를 사이트 구축 기록에 남김

## 중앙 로그 계정을 쓰는 경우
`create_log_bucket = false`로 두고, 각 사이트 `01-network` tfvars에 `central_log_bucket_arn`을 적습니다. 중앙 계정에 다음을 요청합니다.
1. 버킷 정책에 이 계정의 VPC Flow Logs 전달 허용 (`delivery.logs.amazonaws.com`, `aws:SourceAccount`)
2. 버킷 정책에 이 리전의 ELB 로그 전달 허용 (ALB 접근 로그를 보낼 때)
3. 버킷 암호화가 SSE-S3인지 확인 (ALB 접근 로그는 SSE-KMS 불가)

### ELB 접근 로그 버킷 정책
AWS 권장 방식(서비스 주체 `logdelivery.elasticloadbalancing.amazonaws.com` + `aws:SourceArn`으로 이 계정·리전 로드밸런서만 허용)만 씁니다. 리전별 ELB 계정을 주체로 쓰는 예전 방식(legacy)은 출처 조건을 걸 수 없어 넣지 않습니다 (다른 계정 ALB가 로그 prefix를 조작해 이 버킷에 쓸 수 있음). 처음 구축할 때 테스트 계정에서 ALB 접근 로그가 실제로 들어오는지 확인하세요.

## 삭제
버킷에 `prevent_destroy`가 걸려 있어 `terraform destroy`가 막힙니다. 정말 지워야 할 때만 코드에서 해제합니다. 버킷을 지우면 **모든 사이트의 state**가 사라집니다.

## 테스트
```bash
terraform -chdir=00-bootstrap init && terraform -chdir=00-bootstrap test
```

## 계정·리전 보안 기본값 (필수, `account_defaults.tf`)

이 단계에서 보안 기본값을 먼저 적용하고, 이후 단계는 그 위에 필요한 것만 추가합니다.

| 항목 | 내용 | 범위 |
|---|---|---|
| EBS 기본 암호화 | 켜짐. 새 EBS 볼륨·스냅샷 복사본은 항상 암호화 | 리전 |
| EBS 기본 키 | CMK `alias/iac/account/ebs` (또는 중앙 키), 자동 교체, **삭제 보호** | 리전 |
| S3 퍼블릭 차단 | 계정 단위 4개 항목 모두 차단 (버킷 설정보다 우선) | 계정 전체 |
| IMDSv2 | 인스턴스 메타데이터 기본값 `http_tokens = required`, hop limit 2 | 리전 |

- 이미 있는 볼륨·인스턴스는 바뀌지 않습니다. 새로 만드는 것부터 적용됩니다.
- 여러 리전에서 이 단계를 실행하면 S3 계정 차단은 한 리전에서만 관리합니다 (`manage_s3_account_public_access_block`).
- Auto Scaling을 쓰면 `ebs_kms_allow_autoscaling = true` (서비스 연결 역할이 계정에 먼저 있어야 함).
- CMK ARN은 `/iac/_account/00-bootstrap/kms`에 남깁니다 (`key_arns`, `source`: central / local / same-as-s3).

## 암호화 키 (CMK, `kms.tf`)

기본은 **리소스별로 CMK 하나**를 이 계정에 만듭니다. 조직 중앙 계정의 CMK를 쓰면 `central_kms_key_arns`에 키 ARN을 넣습니다 (넣은 키는 만들지 않음).

| 키 | 이 계정에 만들 때 | 쓰는 곳 |
|---|---|---|
| `ebs` | `alias/iac/account/ebs` | 계정·리전 EBS 기본 키. EC2 볼륨은 따로 지정하지 않으면 이 키 |
| `s3` | `alias/iac/account/s3` | S3 버킷. 기본은 state 버킷도 이 키 |
| `logs` | `alias/iac/account/logs` | CloudWatch 로그 그룹 (계정 전체: 서버 Agent 로그, Lambda 로그, Firehose 오류 로그). 키 정책에 CloudWatch Logs 서비스(이 계정 로그 그룹만) 허용. 다음 단계는 `/iac/_account/00-bootstrap/kms`의 `key_arns.logs`를 읽음 |
| (분리 옵션) `tfstate` | `alias/iac/account/tfstate` | `separate_tfstate_key = true`일 때 state 버킷 전용. 중앙 `tfstate` 키를 넣으면 옵션과 관계없이 그 키 사용 |

- 키는 자동 교체, 삭제 대기 30일, **삭제 보호**(prevent_destroy). 삭제 보호는 `operation_mode = "enable"`(운영)일 때만 켜집니다. 그 외(기본 null)는 삭제 가능(버킷은 파일까지, KMS 대기 7일)이고, 항목별로는 `deletion_protection`에서 고릅니다. **처음 배포할 때 정하고 바꾸지 않습니다** (바꾸면 버킷·키가 새로 만들어짐). 모든 단계에 같은 값을 넣습니다.
- 지우는 순서: 02-compute → 02-shared → 01-network → 00-bootstrap (02-* 단계가 01-network 값을 읽으므로 01-network를 먼저 지우면 02-shared 삭제가 실패함)
- 로그 버킷은 **SSE-S3 고정**입니다. ALB 접근 로그가 SSE-KMS를 지원하지 않기 때문입니다.
- 로그 버킷은 **버전 관리**를 켭니다. 덮어쓰거나 지운 로그는 이전 버전으로 남고, `log_noncurrent_version_days`(기본 30일) 뒤 지웁니다.
- 중앙 키를 쓰면 키 ARN이어야 하고(alias 불가), 중앙 키 정책에 이 계정의 사용 권한이 있어야 합니다. 중앙 키를 비활성화·삭제하면 이 계정의 데이터도 읽을 수 없게 됩니다.
- 로그는 계정 기본 설정이라 logs 키도 이 단계가 만듭니다. 중앙 로그 계정 키를 쓸 때도 이 단계의 `central_kms_key_arns.logs`에 넣습니다 (중앙 키 정책에 이 계정 로그 그룹용 CloudWatch Logs 서비스 허용 필요).

## CloudWatch Logs 보관 (`cloudwatch_logs.tf`)

| 위치 | 보관 | 설정 |
|---|---|---|
| CloudWatch Logs | **14일** | 로그 그룹 모듈 기본값 (각 단계 `log_retention_days`) |
| S3 로그 버킷 `<버킷>/<로그 그룹 이름>/YYYY/MM/DD/` | **365일** (30일 후 Glacier로 바로. IA 단계는 `log_transition_ia_days`를 지정할 때만) | `log_retention_days`. **최종 보관일은 고객 협의 후 결정** |

```text
모든 로그 그룹 ─(계정 단위 구독 필터)→ Firehose (iac-cwlogs-to-s3) ─→ S3 로그 버킷
```

### 로그 경로 규칙 (모든 로그는 VPC 이름으로 시작)

| 로그 | CloudWatch 로그 그룹 | S3 경로 |
|---|---|---|
| EC2 OS·인증 로그 | `/<VPC>/ec2/<서버 이름>/messages`, `/secure` | `<VPC>/ec2/<서버 이름>/messages/YYYY/MM/DD/` |
| Lambda (주말 중지 등) | `/<VPC>/lambda/<함수 이름>/function` | `<VPC>/lambda/<함수 이름>/function/YYYY/MM/DD/` |
| VPC Flow Logs | 없음 (S3로 바로) | `<VPC>/vpc/<VPC>/flow-logs/AWSLogs/…` |
| ALB 접근 로그 | 없음 (S3로 바로) | `<VPC>/elb/<ALB 이름>/access-logs/AWSLogs/…` |

- 규칙: `/<VPC 이름>/<리소스 유형>/<리소스 이름>/<로그 이름>`. 새 로그 그룹도 이 규칙으로 만듭니다.
- CloudWatch → S3 경로는 Firehose가 로그 그룹 이름을 읽어 정합니다 (동적 파티셔닝). 규칙을 지키면 S3도 자동으로 같은 구조가 됩니다.
- Firehose 처리에 실패한 데이터만 `firehose-errors/`에 남습니다 (계정 단위라 VPC가 없음).

- 계정 단위 구독 필터라 로그 그룹을 하나씩 등록하지 않아도 되고, 나중에 생기는 로그 그룹도 자동으로 포함됩니다.
- **구독(실제 전송)은 선택**입니다: `enable_log_subscription = true`일 때만 계정 구독 정책을 만듭니다(기본 false = 준비만). 새 계정은 첫 apply를 false로 하고 다음 apply에서 true로 켭니다. 정책을 만들 때 AWS가 테스트 메시지로 권한을 검증하는데, 방금 만든 IAM 권한은 반영에 시간이 걸려 바로 켜면 실패할 수 있기 때문입니다.
- VPC가 없는 계정 단위 로그 그룹은 만들지 않습니다. Firehose 전송 오류용 로그 그룹도 두지 않고, 실패 데이터는 S3 `firehose-errors/`와 Firehose 지표로 확인합니다.
- S3 파일은 CloudWatch Logs 형식 JSON(레코드마다 한 줄)을 gzip으로 묶은 것입니다. Athena로 조회할 때 이 형식으로 테이블을 만듭니다.
- 중앙 로그 계정을 쓰는 방법은 두 가지입니다.
  - **B. 중앙 destination (추천)**: `cloudwatch_logs_destination_arn`에 중앙 계정 CloudWatch Logs destination ARN을 넣으면 이 계정에 Firehose를 만들지 않고 중앙으로 보냅니다. 중앙이 Firehose와 버킷을 운영하므로 서비스 계정이 보관 경로를 바꾸거나 지울 수 없습니다. 중앙 destination 정책에 이 계정(또는 조직) 구독 허용이 필요합니다.
  - **A. 중앙 버킷만**: `create_log_bucket = false`, `cloudwatch_logs_bucket_arn` 지정. 이 계정 Firehose가 중앙 버킷에 씁니다. 중앙 버킷 정책에 이 계정 Firehose role 쓰기 허용이 필요합니다.
- 로그 그룹은 Terraform이 미리 만듭니다 (14일, logs 키). CloudWatch Agent가 로그 그룹을 직접 만들지 않게 합니다 (만들면 무기한 보관). EC2 Agent 설정은 `deployment/ec2-<용도>/src/cwagent_setup.sh` 참고.
- 새 계정에서 처음 apply할 때 계정 단위 구독 정책이 `firehose:PutRecord` 권한 오류로 실패할 수 있습니다 (방금 붙인 IAM 권한이 퍼지기 전에 AWS가 테스트 메시지를 보냄). 잠시 뒤 다시 apply하면 됩니다.
