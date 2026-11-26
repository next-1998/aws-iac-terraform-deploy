# ec2-common

`03-compute` 단계에서 EC2 용도(`ec2-was`, `ec2-webide` 등)가 **같이 쓰는 리소스**를 만듭니다.

```text
01-network (Parameter Store) ──network──▶ ec2-common ──contract──▶ ec2-was
                                                     └──contract──▶ ec2-webide
```

## 만드는 것

| 파일 | 리소스 |
|---|---|
| `subnet.tf` | EC2 서브넷(01-network가 계산한 CIDR, + `purpose = "ec2"` 수동 서브넷), AZ별 라우트 테이블, gateway endpoint(S3 등) 연결 |
| `sg.tf` | **공통 SG** (서버 접근용). 규칙은 `src/sg_rules.csv` |

라우팅: 0.0.0.0/0 → 같은 AZ의 public NAT(01-network에서 public을 켰을 때), 사내망 → TGW, peering 대역 → peering

## 공통 SG

- SSH, 서버 접근제어처럼 **서버에 들어가는 경로만** 둡니다. 서비스 포트는 각 용도의 개별 SG에 둡니다.
- SG는 **규칙 없이** 만들고, 규칙은 **`src/sg_rules.csv`**에 넣습니다 (`sg` 열: `common`).
- 출발지는 IP보다 **prefix list 이름**(`pl:access_ctl`)을 권장합니다. 01-network에서 만든 이름을 씁니다.
- 형식과 검사 규칙: module repo `module/_sg_rules_csv/README.md`
- 예제: `src/sg_rules.example.csv` (적용되지 않음. 필요한 행만 `sg_rules.csv`로 옮겨 씀)
- **가이드: [src/README.md](src/README.md)** (규칙을 붙일 수 있는 SG, CSV 형식, 협의 항목)

```csv
sg,no,direction,protocol,from_port,to_port,source,description,memo
common,1,ingress,tcp,22,22,pl:access_ctl,server access control,서버 접근제어 솔루션
```

## 출력: `contract`

| 키 | 내용 |
|---|---|
| `network` | 01-network contract (그대로 전달) |
| `subnet_ids`, `manual_subnets`, `subnet_cidrs`, `route_table_ids` | EC2 네트워크 |
| `common_sg_id` | 공통 SG |

**주의:** `ec2-<용도>`가 남아 있는 상태에서 이 stack을 지우지 마세요. 서브넷과 공통 SG를 모든 EC2가 같이 씁니다.

## 주말 중지 (선택, 협의 후 적용)

| 입력 | 기본값 | 설명 |
|---|---|---|
| `enable_weekend_stop` | `false` | `true`면 Lambda(VPC 안, EC2 서브넷)와 스케줄 2개(중지·시작) 생성 |
| `weekend_stop.schedule_enabled` | `false` | **협의 전에는 꺼 둠.** 스케줄이 만들어져도 실행되지 않음 |
| `weekend_stop.stop_schedule` / `start_schedule` | 금 21:00 / 월 07:00 | **임시 값** (EventBridge Scheduler cron, `Asia/Seoul`) |
| `weekend_stop.dry_run` | `false` | `true`면 중지하지 않고 대상만 로그로 확인 |

- **대상은 태그로 켜고 끕니다.** 서버마다 자기 태그 `WEEKEND_STOP_ENABLE = "true"`일 때만 대상입니다(`ec2-<용도>`의 `weekend_stop_enable`). 태그 하나 때문에 다른 서버까지 중지되던 기존 버그는 고쳤습니다.
- IAM 권한도 태그가 `true`인 인스턴스만 중지·시작할 수 있게 제한합니다.
- VPC 안에서 실행하므로 01-network `interface_endpoints`에 **`ec2`**가 있어야 합니다(없으면 plan에서 막힘).
- Lambda 코드: 이 폴더의 `src/weekend_stop.py` (RDS용은 `rds-common`을 만들 때 그 폴더에 둠). 조합은 `weekend_stop.tf` (log group → role → SG → Lambda → scheduler)

## EBS 자동 증설 (선택, 기본 꺼짐)

ec2-<용도>에서 `root_auto_grow` 또는 `ebs_volumes[].auto_grow`를 켜면 03-compute가 `enable_ebs_auto_grow = true`로 넘깁니다. 사이트에 Lambda 하나를 만듭니다 (`ebs_grow.tf`, 코드 `src/ebs_grow.py`).

```text
CloudWatch Agent (disk_used_percent, InstanceId·path) → 알람 <접두어>-alm-<용도>-ebsgrow-<root|장치>-01
  → Lambda: 볼륨 크기 늘림 → SSM: 파일시스템 확장 → 알람 OK로 되돌림 → SNS 알림 (02-shared 알림 토픽)
스케줄 (1시간마다) → ALARM 상태로 남은 증설 알람 다시 확인 (6시간 제한 대기, 늘린 뒤에도 높은 경우)
```

| 항목 | 내용 |
|---|---|
| 권한 | 태그 `EBS_AUTO_GROW = true`인 볼륨만 크기 변경, 같은 태그의 서버에만 SSM 명령 |
| 대상 정보 | 알람 설명에 `volume=… instance=… path=… max=… percent=… min=…` (Terraform이 넣음) |
| 제한 | 같은 볼륨은 6시간에 한 번 (AWS). LVM은 지원하지 않음 (파티션 + xfs / ext4) |
| 네트워크 | interface endpoint `ec2`, `ssm`, `monitoring` (+ 알림 시 `sns`)가 필요 (public 여부와 무관, 없으면 plan에서 막힘) |
| Terraform 크기 | 자동으로 늘어난 볼륨은 실제 크기가 tfvars보다 크면 실제 크기를 씀 (줄이려다 실패하지 않음) |
