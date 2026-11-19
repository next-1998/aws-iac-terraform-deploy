# 00-bootstrap

**계정·리전마다 한 번** 실행합니다. 다른 단계(01~04)의 state를 저장할 버킷과 로그 버킷을 만듭니다.

| 리소스 | 기본 | 설명 |
|---|---|---|
| state 버킷 `iac-tfstate-<계정ID>-<리전>` | 생성 | 버전 관리, 암호화, 퍼블릭 차단, HTTPS만 허용, **삭제 보호** |
| DynamoDB 잠금 테이블 | 만들지 않음 | Terraform 1.10 미만 환경이 있을 때만 `create_lock_table = true` |
| 로그 버킷 `iac-logs-<계정ID>-<리전>` | 생성 | Flow Logs, ALB 접근 로그. SSE-S3, 30일 후 IA, 90일 후 Glacier, **365일 후 삭제** |
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

## 중앙 로그 계정을 쓰는 경우
`create_log_bucket = false`로 두고, 각 사이트 `01-network` tfvars에 `central_log_bucket_arn`을 적습니다. 중앙 계정에 다음을 요청합니다.
1. 버킷 정책에 이 계정의 VPC Flow Logs 전달 허용 (`delivery.logs.amazonaws.com`, `aws:SourceAccount`)
2. 버킷 정책에 이 리전의 ELB 로그 전달 허용 (ALB 접근 로그를 보낼 때)
3. 버킷 암호화가 SSE-S3인지 확인 (ALB 접근 로그는 SSE-KMS 불가)

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
| `s3` | `alias/iac/account/s3` | S3 버킷. 기본은 state 버킷·DynamoDB 잠금 테이블도 이 키 |
| (분리 옵션) `tfstate` | `alias/iac/account/tfstate` | `separate_tfstate_key = true`일 때 state 버킷·잠금 테이블 전용. 중앙 `tfstate` 키를 넣으면 옵션과 관계없이 그 키 사용 |

- 키는 자동 교체, 삭제 대기 30일, **삭제 보호**(prevent_destroy).
- 로그 버킷은 **SSE-S3 고정**입니다. ALB 접근 로그가 SSE-KMS를 지원하지 않기 때문입니다.
- 중앙 키를 쓰면 키 ARN이어야 하고(alias 불가), 중앙 키 정책에 이 계정의 사용 권한이 있어야 합니다. 중앙 키를 비활성화·삭제하면 이 계정의 데이터도 읽을 수 없게 됩니다.
