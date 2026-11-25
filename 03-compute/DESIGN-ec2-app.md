# 설계: EC2 구성을 CSV로 (ec2-app 통합)

> 상태: **보류** (2026-11-24). CSV로 나누면 파일이 많이 쪼개지거나 구조가 복잡해짐 (특히 ELB 구성 유형). 지금은 ec2-was/ec2-webide + tfvars 유지.
> 보류 시점의 미결: ELB를 서버에서 분리할지(로드밸런서·대상 그룹·연결을 따로 정의), purpose 개념 유지 여부, D4.
> 브랜치: `tf1.17-aws6_mgkim`

## 1. 목표

- 서버를 **CSV 한 줄로 추가**합니다. 같은 용도의 서버를 여러 대 둘 수 있습니다.
- 새 용도(was, webide 외)도 **CSV 한 줄로 추가**합니다. 폴더를 복사하지 않습니다.
- 고객에게 엑셀(시트별)로 받은 협의 결과를 CSV로 저장해 그대로 넣습니다.
- 지금처럼 tfvars로 넣는 방식도 계속 씁니다.

## 2. 결정한 것

| # | 항목 | 결정 |
|---|---|---|
| 1 | 구조 | `ec2-was`, `ec2-webide`를 **공통 틀 `ec2-app` 하나로 합침**. 용도마다 한 번씩 호출 |
| 2 | 입력 | **tfvars 변수가 기준**(형식·검사), CSV는 선택 입력. 데이터마다 둘 중 하나만 (둘 다 있으면 plan에서 막음) |
| 3 | CSV 읽기 | **Terraform `csvdecode`로 직접** (변환 스크립트 없음). CSV 종류별 읽기·검사 모듈 (`module/_sg_rules_csv`와 같은 방식, 행 번호가 있는 오류) |
| 4 | 서버와 볼륨 | **파일 분리** (`servers.csv`, `volumes.csv`). 볼륨 수 제한 없음 |
| 5 | 순번 | **모든 CSV에 `no` 열, 순번이 Terraform 키**. 1 이상 정수, 범위 안에서 중복 불가, 한번 쓴 번호는 바꾸거나 다시 쓰지 않음. CSV는 매번 전체를 읽지만 **내용이 바뀐 행의 리소스만 변경**됨 (SG 규칙 CSV와 같음). 행 순서를 바꾸거나 중간에 행을 넣어도 다른 행은 영향 없음 |
| 8 | 볼륨 → 서버 | volumes.csv의 `server`는 **서버 이름**으로 매핑 (키는 내부적으로 서버 순번 기준) |
| 9 | 공통 SG 규칙 | sg_rules.csv 한 파일, 공통 SG(ec2-common)는 `purpose = common` |
| 10 | 사이트 전체 값 | 용도마다 다를 이유가 없는 값은 **03-compute tfvars에 한 번만**: `log_retention_days`(14), `enable_cloudwatch_agent`(true), `cloudwatch_agent_schedule`(없음), `sg_rule_limit`(60) |
| 6 | EC2 디스크 | EC2는 **루트 볼륨만**, 데이터 볼륨은 따로 만들어 붙임, `mount_point`가 있으면 SSM으로 마운트 (구현·검증 완료) |
| 7 | AMI | 서버마다 AMI ID 직접 (커스텀 이미지). 바뀌어도 서버 교체 없음 (구현 완료) |

## 3. 구조

```text
03-compute
 ├ csv/                      purposes.csv, servers.csv, volumes.csv, sg_rules.csv (+ *.example.csv, README.md)
 ├ main.tf                   CSV 또는 tfvars → 읽기·검사 모듈 → ec2-common, ec2-app × 용도
 └ variables.tf              purposes, servers, volumes (tfvars로 넣을 때)

deployment/ec2-common        그대로 (서브넷, 공통 SG, 주말 중지)
deployment/ec2-app           (새로) ec2-was + ec2-webide 통합
   ├ 용도 단위   : 개별 SG + 규칙, IAM 역할·정책·프로파일, ALB·대상 그룹·리스너·DNS·WAF
   └ 서버 단위   : EC2(루트), Agent 로그 그룹, Agent 설치 SSM 연결
      └ 볼륨 단위: 데이터 볼륨, 연결, (마운트 SSM 연결은 서버 단위)

module repo
   _servers_csv, _volumes_csv, _purposes_csv   CSV 읽기·검사 (리소스 없음)
   (_sg_rules_csv는 있음. prefix list CSV는 보류)
```

- 같은 용도의 서버는 같은 SG·IAM 역할·ALB를 씁니다 (ALB 대상 그룹에 모두 붙음).
- 용도 고유 기능은 `ec2-app` 옵션으로 넣습니다. 정말 다른 용도만 별도 폴더로 둡니다 (예외).

## 4. CSV 파일과 열

공통: UTF-8(BOM 허용), 첫 행은 열 이름, **빈 칸 = 기본값**, `memo` 열은 설명용(Terraform은 무시). 예제는 `*.example.csv`.

### 4.1 purposes.csv — 용도 (행 하나 = 용도 하나)

| 열 | 필수 | 기본 | 설명 |
|---|---|---|---|
| `no` | ✅ | | 순번 |
| `purpose` | ✅ | | 용도 이름 (소문자·숫자·`-`). 리소스 이름 `<site>-ec2-<purpose>`에 들어감 |
| `app_port` | | 8080 | 서비스 포트 = ALB 대상 포트 |
| `enable_alb` | | false | ALB 생성 |
| `alb_internal` | | true | 내부용. 외부용(false)은 01-network `enable_public` 필요 |
| `alb_record_name` | | purpose | 도메인 `<이름>.<site>.<root_domain>` |
| `health_check_path` | | `/` | ALB 헬스체크 경로 |
| `memo` | | | |

- 추가 IAM 정책(`policy_arns`), WAF, ALB 허용 대역 같은 목록 값은 CSV에 넣기 어려워 **tfvars의 용도별 추가 설정**으로 둡니다 (결정 필요 D4).

### 4.2 servers.csv — 서버 (행 하나 = 서버 하나)

| 열 | 필수 | 기본 | 설명 |
|---|---|---|---|
| `no` | ✅ | | 순번 (파일 전체에서 중복 불가) |
| `name` | ✅ | | 서버 이름 (소문자·숫자·`-`). 리소스 이름 `<site>-<name>` |
| `purpose` | ✅ | | purposes.csv의 `purpose` |
| `ami` | ✅ | | AMI ID (`ami-…`, 커스텀 이미지) |
| `instance_type` | | t3.micro | |
| `root_volume_size` | | 30 | 루트 GiB (이미지 크기 이상) |
| `az` | | 첫 AZ | 서버 AZ (01-network의 AZ 중 하나) |
| `weekend_stop` | | false | 주말 중지 대상 |
| `memo` | | | |

### 4.3 volumes.csv — 데이터 볼륨 (행 하나 = 볼륨 하나)

| 열 | 필수 | 기본 | 설명 |
|---|---|---|---|
| `server` | ✅ | | servers.csv의 `name` (서버 이름으로 매핑) |
| `no` | ✅ | | 순번 (**서버별**로 1부터, 같은 서버 안에서 중복 불가) |
| `device_name` | ✅ | | 예: `/dev/sdf` |
| `volume_size` | ✅ | | GiB (늘리기만 가능) |
| `volume_type` | | gp3 | |
| `mount_point` | | (마운트 안 함) | 마운트 경로. 시스템 경로 불가 |
| `fs_type` | | xfs | xfs / ext4 |
| `mount_options` | | defaults,nofail | fstab 옵션 |
| `memo` | | | |

- AZ는 넣지 않습니다. 서버 AZ를 따릅니다.

### 4.4 sg_rules.csv — SG 추가 규칙

- 지금 형식(`sg,no,direction,protocol,from_port,to_port,source,description,memo`)에 **`purpose` 열을 추가**해 한 파일로 모읍니다 (지금은 용도 폴더마다 파일).
- 공통 SG(ec2-common) 규칙도 같은 파일에 `purpose = common`으로 넣습니다. 키는 `<purpose>-<sg>-<no>` (sg/no 규칙은 지금과 같음).

### 4.5 prefix list — **보류**

- prefix list는 만드는 곳(01-network `terraform.tfvars`의 `prefix_lists`)에서 지금처럼 수정합니다. CSV로 옮기지 않습니다 (보류).

## 5. 키(식별자)와 바꿨을 때의 영향

| 데이터 | Terraform 키 | 이름·값을 바꾸면 |
|---|---|---|
| 용도 | `no` | `purpose` 이름 변경: 리소스 이름에 들어가므로 그 용도의 SG·역할·ALB가 다시 만들어짐 → **바꾸지 않는 값** |
| 서버 | `no` | `name` 변경: EC2는 유지(Name 태그만). 단 로그 그룹 이름(`/<vpc>/ec2/<name>/…`)·SSM 연결 이름은 다시 만들어짐 (CloudWatch 로그는 새 그룹으로, 예전 로그는 S3에 남음) |
| 볼륨 | `<서버 no>-<볼륨 no>` | `device_name` 변경: 볼륨·데이터 유지, 연결만 다시 / 서버 `name` 변경: 볼륨 유지 (키가 서버 순번 기준) |
| 순번(`no`) | 키 자체 | **다시 만들어짐** → 바꾸지 않음 |

## 6. tfvars와 CSV

```hcl
# 데이터마다 (purposes, servers, volumes, sg_rules)
#   tfvars 값이 있으면 그것, 없으면 csv/<이름>.csv, 둘 다 있으면 plan에서 막음
```
- 서버가 적은 사이트: tfvars만
- 서버가 많거나 엑셀로 받는 사이트: CSV만
- tfvars 형식도 CSV와 같은 키 구조 (`servers = { 1 = { name = "was-01", … } }`)

## 7. 검사 (plan에서 막음, 행 번호 포함)

| 검사 | 예 |
|---|---|
| 필수 열 없음 / 필수 값 빈 칸 | `servers.csv 3행: ami가 비어 있음` |
| 순번 형식·중복 | `volumes.csv was-01 no 2 중복: 3행, 5행` |
| 이름 형식·중복 | `servers.csv name was-01 중복: 2행, 4행` |
| 참조 | `volumes.csv 4행: 서버 was-1이 servers.csv에 없음` / `servers.csv 2행: 용도 api가 purposes.csv에 없음` |
| 값 형식 | AMI ID, 숫자, true/false, AZ, 마운트 경로(시스템 경로 금지), 파일시스템 |
| 입력 중복 | `servers가 tfvars와 csv/servers.csv 양쪽에 있음 (하나만 사용)` |

## 8. 바꿀 것 (구현 범위)

| repo | 작업 |
|---|---|
| module | `_servers_csv`, `_volumes_csv`, `_purposes_csv` 읽기·검사 모듈 (리소스 없음) |
| deploy | `deployment/ec2-app` 작성 (ec2-was 기반, 서버·볼륨 for_each) / `ec2-was`, `ec2-webide` 삭제 |
| deploy | `03-compute`: 변수(purposes, servers, volumes), CSV 읽기, 입력 선택, `ec2-app` 호출, 출력 |
| deploy | `03-compute/csv/`: 예제 CSV, README(열 정의·협의 항목·순번 규칙) / tfvars 안내 정리 |
| deploy | 테스트: 읽기·검사, 서버 여러 대·용도 추가, 이름 변경 시 볼륨 유지 |
| 이동 | state 주소 변경 `module.ec2_was[0]` → `module.ec2_app["was"]` …: 테스트 계정은 다시 배포, 운영 사이트는 `moved` 블록 (지금은 운영 배포 없음) |

## 9. 결정 필요

| # | 항목 | 선택지 | 제안 |
|---|---|---|---|
| ~~D1~~ | 서버 키 | → **`no`** (모든 CSV 순번 키) | 결정 |
| ~~D2~~ | 볼륨의 서버 참조 | → **서버 이름** | 결정 |
| ~~D3~~ | 공통 SG 규칙 위치 | → **sg_rules.csv, `purpose = common`** | 결정 |
| D4 | 용도별 목록 값 (추가 IAM 정책, WAF, ALB 허용 대역) | tfvars 용도별 추가 설정 / CSV 열(공백 구분) | tfvars |
| ~~D5~~ | prefix list 한도 | → **prefix list는 01-network tfvars에서 관리 (CSV 보류)** | 결정 |
| ~~D6~~ | prefix_lists.csv | → **보류** | 결정 |
