# ec2-was SG 규칙 가이드

이 폴더(`ec2-was`)의 **서버 SG**와 **ALB SG** 규칙을 `sg_rules.csv`로 관리합니다.

| 파일 | 내용 |
|---|---|
| `sg_rules.csv` | **실제 적용되는 규칙.** 고객사와 협의한 추가 규칙만 넣습니다 (기본: 헤더만 = 추가 규칙 없음) |
| `sg_rules.example.csv` | 예제. 적용되지 않습니다. 필요한 행만 `sg_rules.csv`로 옮겨 씁니다 |

## 1. 규칙을 붙일 수 있는 SG

| `sg` 열 값 | 실제 SG | 용도 | 조건 |
|---|---|---|---|
| `app` | `<site>-ec2-was-sg` | WAS 서버의 서비스 포트, 서버에서 나가는 경로 | 항상 |
| `alb` | `<site>-ec2-was-alb-sg` | WAS 앞단 ALB로 들어오는 경로 | `enable_alb = true`일 때만 |

- 이 폴더의 CSV에는 `app`, `alb`만 쓸 수 있습니다. ALB를 끈 상태에서 `alb`를 쓰면 plan에서 막힙니다.
- SSH 같은 **서버 접근 경로는 여기에 넣지 않습니다.** `ec2-common/src/sg_rules.csv`의 공통 SG(`common`)에 넣습니다.
- 서버에는 공통 SG와 `app` SG가 같이 붙습니다.
- CSV로 SG를 새로 만들 수는 없습니다. SG를 추가하려면 `../sg.tf`에 SG 모듈을 추가하고 `locals.sg_ids`에 이름을 넣어야 합니다.
- `sg` 값은 역할 이름이라, 이 폴더를 복사해 새 용도(예: ec2-batch)를 만들어도 CSV를 고칠 필요가 없습니다.

## 2. 코드에 이미 있는 기본 규칙 (CSV에 넣지 않음)

서비스 동작에 꼭 필요한 최소 규칙은 `../sg.tf`에 있습니다. CSV는 여기에 **추가만** 합니다.

| SG | 방향 | 내용 |
|---|---|---|
| `app` | 인바운드 | ALB SG → `app_port` (ALB를 켠 경우) |
| `app` | 아웃바운드 | VPC 대역 전체 (VPC endpoint, 내부 LB, DB) |
| `app` | 아웃바운드 | S3/DynamoDB gateway endpoint 443 (AWS 관리형 prefix list) |
| `alb` | 인바운드 | 80/443 ← `alb_ingress_cidrs` 또는 `alb_ingress_prefix_lists` (기본: 내부용은 VPC + 사내망) |
| `alb` | 아웃바운드 | `app_port` → EC2 서브넷 |

- **사내망·인터넷으로 나가는 경로는 기본에 없습니다.** 필요하면 CSV에 `app,egress,...`로 추가합니다 (보안 기본값 → 필요한 것만 추가).

## 3. CSV 형식

```csv
sg,no,direction,protocol,from_port,to_port,source,description,memo
app,1,egress,tcp,1521,1521,cidr:10.185.10.0/24,to legacy oracle db,기존 사내 Oracle DB
alb,1,ingress,tcp,443,443,pl:corp,https from corp users,사내망 사용자
```

| 열 | 필수 | 값 |
|---|---|---|
| `sg` | ○ | `app` / `alb` |
| `no` | ○ | **SG별** 규칙 순번 (SG마다 1부터, 같은 SG 안에서 중복 불가). `sg` + `no`가 규칙의 식별자 (아래 "순번 쓰는 법") |
| `direction` | ○ | `ingress` / `egress` |
| `protocol` | ○ | `tcp` / `udp` / `icmp` / `all` |
| `from_port`, `to_port` | ○ | 포트. `all`이면 비움. `icmp`는 `-1,-1`(전체) |
| `source` | ○ | 인바운드면 **출발지**, 아웃바운드면 **목적지** (아래 표) |
| `description` | ○ | AWS에 들어가는 설명. **영문, 숫자, 일부 기호만** |
| `memo` 등 | | 자유 (한글 가능, Terraform은 읽지 않음). 요청자·승인일·티켓 등 열을 더 붙여도 됨 |

| `source` | 의미 | 예 |
|---|---|---|
| `pl:<이름>` | 01-network prefix list (**권장**) | `pl:corp_proxy` |
| `pl:pl-xxxx` | prefix list ID 직접 | `pl:pl-0a1b2c3d` |
| `cidr:<CIDR>` | IP 대역 | `cidr:10.185.10.0/24` |
| `sg:app`, `sg:alb` | 이 폴더의 SG | `sg:alb` |
| `sg:common` | ec2-common의 공통 SG | `sg:common` |
| `sg:<용도>.<sg>` | **같은 단계(03-compute)의 다른 용도 SG**. ID를 몰라도 이름으로 참조 (처음 배포에도 한 번에 적용). 켜지지 않은 용도를 참조하면 plan에서 막힘 | `sg:webide.app`, `sg:was.alb` |
| `sg:sg-xxxx` | 우리 코드 밖의 SG ID (기존 레거시 DB, 다른 계정 등). 다른 단계의 SG는 아직 이름 참조 없음 → ID | `sg:sg-0123abcd` |
| `self` | 같은 SG끼리 (예: WAS끼리 세션 복제) | `self` |

- 열 순서는 바꿔도 되지만 **필수 열 이름은 정확히** 같아야 합니다 (대소문자, 공백 주의).
- 모든 행의 열 개수는 같아야 합니다. 값이 없으면 빈 칸.

### 순번(`no`) 쓰는 법
- `no`는 **SG별 순번**입니다. SG마다 1부터 매기고 같은 SG 안에서 중복될 수 없습니다 (중복이면 plan에서 `app no 3 중복: 2행, 5행`처럼 표시). SG가 다르면 같은 번호를 써도 됩니다.
- `sg` + `no`(예: `app-3`)가 **규칙의 식별자**입니다. SG마다 번호를 따로 매기므로 SG별로 규칙이 추가돼도 번호가 흩어지지 않습니다.
- **번호가 같으면 내용(포트, 대상, 설명)을 고쳐도 그 규칙만 그 자리에서 수정**됩니다. 규칙이 지워졌다 다시 생기지 않아 통신이 끊기지 않습니다.
- 번호를 바꾸면 다른 규칙으로 봅니다 (기존 규칙 삭제 + 새 규칙 생성).
- 행 순서는 바꿔도 됩니다. 지운 규칙의 번호는 다시 쓰지 않고, 새 규칙은 그 SG의 마지막 번호 다음부터 붙이는 것을 권장합니다 (협의 이력과 맞추기 쉬움).
- 규칙을 다른 SG로 옮기면(`sg` 열 변경) 번호가 같아도 다시 만들어집니다 (AWS 규칙은 SG를 바꿀 수 없음).

## 4. plan에서 막히는 경우 (행 번호와 이유가 표시됨)
- `sg`가 `app`, `alb`가 아님 (또는 ALB를 껐는데 `alb`)
- direction, protocol, 포트 형식 오류
- `source`를 해석할 수 없음 (없는 prefix list 이름, 없는 SG 이름 등)
- 같은 규칙이 두 행에 있음 (표기만 달라도 같은 규칙: `TCP`/`tcp`, `22`/`022`. description은 비교하지 않음)
- **코드 기본 규칙과 같은 규칙** (AWS가 중복 규칙을 거부해 apply에서 실패하므로 미리 막음)
- **SG 규칙 한도 초과**: SG마다 인바운드·아웃바운드 각각 60개 (기본 규칙 포함). prefix list를 참조하는 규칙은 그 prefix list의 `max_entries`만큼 계산. 한도를 올렸으면(Service Quotas) `sg_rule_limit` 조정
- `0.0.0.0/0` 인바운드 (외부 공개는 `alb_internal = false` + `alb_ingress_cidrs`로만)
- `description`에 한글

## 5. 협의할 것 (고객 서비스 담당, 보안팀)
- 서비스 사용자 대역 → `alb` 인바운드 (또는 ALB 없이 직접 접속이면 `app` 인바운드)
- 서버가 호출하는 대상: 기존 DB, 사내 API, 프록시, 외부 연동 → `app` 아웃바운드
- 서버끼리 통신 (클러스터, 세션 복제) → `self`
- 출발지·목적지는 01-network `prefix_lists`에 먼저 등록하고 `pl:<이름>`으로 참조

## 6. Excel로 편집할 때
- 저장 형식은 **"CSV UTF-8 (쉼표로 분리)"** (일반 "CSV"는 한글 memo가 깨질 수 있음)
- 포트 칸은 텍스트 서식 권장
- BOM, Windows 줄바꿈은 자동 처리

형식 상세: module repo `module/_sg_rules_csv/README.md`
