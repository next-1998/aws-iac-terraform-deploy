# aws-iac-terraform-deploy (사이트 repo)

서비스(워크로드) 계정에 사이트 하나를 배포하는 repo입니다. 공통 생성 모듈은 `aws-iac-terraform-module` repo를 같은 상위 폴더에 두고 상대경로로 씁니다.

```text
workspace/
├── aws-iac-terraform-module/   ← 생성 모듈 (태그 표준: TAGGING.md)
└── aws-iac-terraform-deploy/   ← 이 repo
```

## 단계 구성

| 단계 | 범위 | 하는 일 | 상태 |
|---|---|---|---|
| `00-bootstrap` | **계정·리전당 1회** | state 버킷, 로그 버킷, (선택) DynamoDB 잠금, **보안 기본값**(EBS CMK 기본 암호화, S3 계정 퍼블릭 차단, IMDSv2) | 구현 |
| `01-network` | 사이트 | VPC, 공통 서브넷(edge/vpce/transit/public), NAT, VPC endpoint, DNS, prefix list, Flow Logs, 기존 TGW/peering 연결 | 구현 |
| `02-shared` | 사이트 | 여러 유형이 같이 쓰는 것: 사이트 인증서, 알림 토픽 (`shared-common`) | 구현 |
| `02-compute` | 사이트 | EC2 유형: `ec2-common` + 용도별 (`ec2-was`, `ec2-webide` …) | 구현 |
| `02-database` | 사이트 | DB 유형: `rds-common` + 용도별 | 예정 (README에 설계) |
| `03-eks` | 사이트 | EKS | 예정 (README에 설계) |
| `04-pod` | 사이트 | 애드온, Helm, 워크로드 | 예정 |

- 단계마다 state가 따로 있고(`<site>/<단계>/terraform.tfstate`), 값은 **Parameter Store**로 넘깁니다.
- 02 단계는 **유형별로 나눕니다** (`02-compute`, `02-database` …). 유형마다 state가 하나이고, 유형끼리는 서로 영향을 주지 않습니다.
- 조합 코드는 `deployment/`에 있고 단계 폴더가 호출합니다.
  - 1차 조합 `<유형>-common`: 리소스를 만들 때 필요한 것 (서브넷, 공통 SG, IAM, Lambda …)
  - 2차 조합 `<유형>-<용도>`: 만들려는 목적 리소스 (서버, 개별 SG, ALB …)
- ALB/NLB는 네트워크 단계에서 만들지 않습니다. 필요한 리소스(예: `ec2-was`)를 만들 때 같이 만듭니다.

```text
Parameter Store
/iac/_account/00-bootstrap/state | logs | ebs
/iac/<site>/01-network/base | subnets | routing | endpoints | dns
/iac/<site>/02-shared/shared
/iac/<site>/02-compute/ec2
```

## 배포 순서

```bash
# 0. 계정당 한 번
cd 00-bootstrap && terraform init && terraform apply

# 1~2. 사이트마다 (backend.hcl.example을 backend.hcl로 복사해 값 입력)
cd 01-network  && terraform init -backend-config=backend.hcl && terraform apply
cd 02-shared   && terraform init -backend-config=backend.hcl && terraform apply
cd 02-compute  && terraform init -backend-config=backend.hcl && terraform apply   # 02-database도 같은 방식
```

**삭제는 반대 순서**(04 → 03 → 02-compute·02-database → 02-shared → 01)입니다. 01을 먼저 지우면 Parameter Store 값이 사라져 다음 단계를 정리할 수 없습니다.

## 사전 요청 사항 (이 코드 밖의 작업)

| # | 대상 | 내용 | 언제 |
|---|---|---|---|
| 1 | 네트워크팀 | **routable 대역 할당** (AZ 2개 /23, 3~4개 /22, EKS를 routable에 두면 더 큼) | 01 전 |
| 2 | 중앙 네트워크 계정 | TGW RAM 공유 **자동 수락**, attachment **자동 승인** | TGW 연결 시 |
| 3 | 중앙 네트워크 계정 | 우리 attachment의 TGW 라우트 테이블 연결·전파, 사이트 대역 경로 | TGW 연결 시 |
| 4 | 중앙 네트워크 계정 | 사내망에서 private 존을 조회하려면 Resolver inbound 설정 | 내부 도메인 사용 시 |
| 5 | 중앙 로그 계정 | 버킷 정책에 이 계정의 Flow Logs, ELB 로그 전달 허용 (SSE-S3) | 중앙 로그 사용 시 |
| 6 | 네트워크팀 | 새 routable 대역을 추가하면 TGW 라우트 추가 | 확장 시 |
| 7 | 중앙 보안(KMS) 계정 | 중앙 CMK를 쓸 때: 용도별 키 ARN 전달, 키 정책에 이 계정 사용 권한 + 서비스 권한(CloudWatch Logs: `logs.<리전>.amazonaws.com`, 알림: `cloudwatch.amazonaws.com`, EBS ASG: AutoScaling 서비스 연결 역할) | `central_kms_key_arns` 사용 시 |

## 테스트 (mock provider, AWS 접속 없음)

```bash
terraform -chdir=tests       init && terraform -chdir=tests       test   # 조합 코드 통합 (대역 배치, 규칙)
terraform -chdir=00-bootstrap init && terraform -chdir=00-bootstrap test
terraform -chdir=01-network  init -backend=false && terraform -chdir=01-network  test
terraform -chdir=02-shared   init -backend=false && terraform -chdir=02-shared   test
terraform -chdir=02-compute  init -backend=false && terraform -chdir=02-compute  test
```

mock 테스트는 AWS 쪽 제한(권한, 한도, AZ별 지원 인스턴스)을 확인하지 못합니다. 고객사에 적용하기 전에 테스트 계정에서 실제 plan/apply를 권장합니다.

## 참고
- `legacy/`: 이전 구조 코드 (참고용, 실행하지 않음)
- 리소스별 CSV 입력은 나중에 추가 예정입니다. 입력은 이름을 키로 하는 목록 형태로 유지합니다.
