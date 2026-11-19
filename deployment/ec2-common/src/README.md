# ec2-common SG 규칙 가이드

이 폴더(`ec2-common`)의 **공통 SG** 규칙을 `sg_rules.csv`로 관리합니다.

| 파일 | 내용 |
|---|---|
| `sg_rules.csv` | **실제 적용되는 규칙.** 고객사와 협의한 규칙만 넣습니다 (기본: 헤더만 = 규칙 없음) |
| `sg_rules.example.csv` | 예제. 적용되지 않습니다. 필요한 행만 `sg_rules.csv`로 옮겨 씁니다 |
| `weekend_stop.py` | 주말 중지 Lambda 코드 (SG와 무관) |

## 1. 규칙을 붙일 수 있는 SG

| `sg` 열 값 | 실제 SG | 용도 |
|---|---|---|
| `common` | `<site>-ec2-common-sg` | **서버 접근 전용** (SSH, RDP, 서버 접근제어 솔루션, 관리자 점검) |

- 이 폴더의 CSV에는 `common`만 쓸 수 있습니다. 다른 값은 plan에서 막힙니다.
- 공통 SG는 모든 EC2(ec2-was, ec2-webide …)에 같이 붙습니다. 여기 넣은 규칙은 **모든 서버**에 적용됩니다.
- 서비스 포트(8080, 443 등)는 여기에 넣지 않습니다. 각 용도 폴더(`ec2-<용도>/src/sg_rules.csv`)의 `app` SG에 넣습니다.
- CSV로 SG를 새로 만들 수는 없습니다. SG를 추가하려면 `../sg.tf`에 SG 모듈을 추가하고 `locals.sg_ids`에 이름을 넣어야 합니다.

## 2. 코드에 이미 있는 기본 규칙

**없습니다.** 공통 SG는 규칙 없이 만들어집니다 (보안 기본값).

- 인바운드: CSV에 넣은 것만 열립니다.
- 아웃바운드: 두지 않습니다. 서버의 아웃바운드는 같이 붙는 용도별 SG(`app`)가 담당합니다.

## 3. CSV 형식

```csv
sg,no,direction,protocol,from_port,to_port,source,description,memo
common,1,ingress,tcp,22,22,pl:access_ctl,ssh from server access control,서버 접근제어 솔루션에서 SSH
```

| 열 | 필수 | 값 |
|---|---|---|
| `sg` | ○ | `common` |
| `no` | ○ | **SG별** 규칙 순번 (SG마다 1부터, 같은 SG 안에서 중복 불가). `sg` + `no`가 규칙의 식별자 (아래 "순번 쓰는 법") |
| `direction` | ○ | `ingress` / `egress` (이 SG는 보통 `ingress`만) |
| `protocol` | ○ | `tcp` / `udp` / `icmp` / `all` |
| `from_port`, `to_port` | ○ | 포트. `all`이면 비움. `icmp`는 `-1,-1`(전체) |
| `source` | ○ | 아래 표 |
| `description` | ○ | AWS에 들어가는 설명. **영문, 숫자, 일부 기호만** |
| `memo` 등 | | 자유 (한글 가능, Terraform은 읽지 않음). 요청자·승인일·티켓 등 열을 더 붙여도 됨 |

| `source` | 의미 | 예 |
|---|---|---|
| `pl:<이름>` | 01-network prefix list (**권장**. IP가 바뀌면 prefix list만 고치면 됨) | `pl:access_ctl` |
| `pl:pl-xxxx` | prefix list ID 직접 | `pl:pl-0a1b2c3d` |
| `cidr:<CIDR>` | IP 대역 | `cidr:10.185.66.0/24` |
| `sg:sg-xxxx` | 다른 SG ID (다른 계정·VPC 연결 등) | `sg:sg-0123abcd` |
| `self` | 같은 SG끼리 | `self` |

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
- `sg`가 `common`이 아님
- direction, protocol, 포트 형식 오류
- `source`를 해석할 수 없음 (없는 prefix list 이름 등)
- 같은 규칙이 두 행에 있음 (표기만 달라도 같은 규칙: `TCP`/`tcp`, `22`/`022`. description은 비교하지 않음)
- **코드 기본 규칙과 같은 규칙** (AWS가 중복 규칙을 거부해 apply에서 실패하므로 미리 막음)
- **SG 규칙 한도 초과**: SG마다 인바운드·아웃바운드 각각 60개 (기본 규칙 포함). prefix list를 참조하는 규칙은 그 prefix list의 `max_entries`만큼 계산. 한도를 올렸으면(Service Quotas) `sg_rule_limit` 조정
- `0.0.0.0/0` 인바운드
- `description`에 한글

## 5. 협의할 것 (고객 보안팀)
- 서버 접근 경로: 서버 접근제어 솔루션 IP, 관리자 PC 대역
- 프로토콜: SSH(22), RDP(3389), 기타 관리 포트
- 출발지는 01-network `prefix_lists`에 먼저 등록하고 `pl:<이름>`으로 참조

## 6. Excel로 편집할 때
- 저장 형식은 **"CSV UTF-8 (쉼표로 분리)"** (일반 "CSV"는 한글 memo가 깨질 수 있음)
- 포트 칸은 텍스트 서식 권장 (`-1` 등이 바뀌지 않게)
- BOM, Windows 줄바꿈은 자동 처리

형식 상세: module repo `module/_sg_rules_csv/README.md`
