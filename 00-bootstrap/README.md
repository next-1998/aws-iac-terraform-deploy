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
