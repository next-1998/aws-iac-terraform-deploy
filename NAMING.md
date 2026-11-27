# 리소스 이름 규칙

모든 리소스 이름은 코드가 만듭니다. 사이트에서 정하는 것은 **접두어 값(00-bootstrap `naming`)** 과 **용도·DB 키 같은 짧은 이름**뿐입니다.

```text
<회사>-<서비스>-<환경>-<리전 코드>-<리소스 유형>-<이름>-<순번>[-<AZ>]
 hw   - iac    - dev  - an2        - ec2         - was  - 01    - a
└──────────── 접두어 (중앙 관리) ───────────┘ └──────── 리소스마다 (코드가 붙임) ────────┘
```

| 부분 | 규칙 | 정하는 곳 |
|---|---|---|
| 접두어 | `<회사>-<서비스>-<환경>-<리전 코드>`. 각 칸 소문자·숫자 1~8자, 하이픈 불가 | 00-bootstrap `naming = { company, service, env }`. Parameter Store `/iac/_account/00-bootstrap/naming`에 남기고 모든 단계가 읽음 |
| 리전 코드 | 리전에서 자동 (`ap-northeast-2` → `an2`, `us-east-1` → `ue1`). 표에 없는 리전만 `naming.region_code` | 00-bootstrap `naming.tf` |
| 리소스 유형 | 아래 표. 서비스에 딸린 부속 리소스만 `<서비스>-<하위 유형>` (예: `rds-pagrp`, `bku-plan`) | 코드 |
| 이름 | 용도·DB 키 등 짧은 이름 (예: `was`, `app`). 하이픈 없이 붙여 씀 (`wasdata`) | tfvars 키 |
| 순번 | **항상** 두 자리 (`01`, `02`) | 코드 |
| AZ | AZ에 묶인 리소스만, 순번 **뒤**에 (`01-a`) | 코드 |

## 리소스 유형 코드

| 영역 | 코드 |
|---|---|
| 네트워크 | `vpc` VPC, `sbn` 서브넷, `rtb` 라우트 테이블, `igw` 인터넷 게이트웨이, `natgw` NAT 게이트웨이, `eip` Elastic IP, `vpce` VPC 엔드포인트, `tga` TGW 연결, `eni` 네트워크 인터페이스, `fl` Flow Logs, `pl` prefix list, `rsv` Resolver 규칙 연결, `sg` 보안 그룹 |
| 컴퓨팅 | `ec2` 인스턴스, `vol` EBS 볼륨, `kp` key pair(수동 생성 안내), `ami` 이미지, `lt` launch template, `asg` Auto Scaling 그룹, `asg-pol` 스케일링 정책, `asg-sch` 예약 작업, `alb` ALB, `tg` 대상 그룹 |
| DB | `rds` DB 인스턴스, `rds-pagrp` 파라미터 그룹, `rds-og` 옵션 그룹, `rds-sng` 서브넷 그룹, `rds-cl` Aurora 클러스터, `rds-cpar` 클러스터 파라미터 그룹 |
| 보안·관리 | `kms` KMS 키(별칭), `role` IAM 역할, `ipf` 인스턴스 프로파일, `pol` IAM 정책, `ssa` SSM 연결 |
| 모니터링·로그 | `alm` CloudWatch 알람, `fh` Firehose, `lpol` 로그 계정 정책 |
| 기타 | `s3` 버킷, `sns` 토픽, `lbd` Lambda, `sch` EventBridge 스케줄, `evb-rule` EventBridge 규칙, `bku-vault` / `bku-plan` / `bku-sel` 백업 볼트·플랜·대상 선택 |

`ResourceKey` 태그(`<대상>_<약어>`)도 같은 코드를 씁니다.

## RDS
| 엔진 | 엔진 코드 | 엔진·버전 코드 (파라미터 그룹) |
|---|---|---|
| PostgreSQL | `pg` | `pg16` |
| MySQL | `my` | `my80` |
| MariaDB | `mdb` | `mdb1011` |
| Aurora PostgreSQL / MySQL | `apg` / `amy` | `apg16` / `amy80` |

- DB: `<접두어>-rds-pg-app-01`, 읽기 복제본: `<접두어>-rds-pg-app-ro-01`, `-ro-02` (복제본 키 이름순)
- 파라미터 그룹: `<접두어>-rds-pagrp-pg16-app-01`. 주 버전을 올리면 family가 바뀌어 새 파라미터 그룹이 됨
- DB 이름에는 버전을 넣지 않음 (버전을 올려도 접속 주소가 바뀌지 않게)
- Aurora: 클러스터 `<접두어>-rds-cl-apg-app-01`, 인스턴스 `<접두어>-rds-apg-app-01`, `-02` …(순번만. 장애 조치로 쓰기·읽기가 바뀌므로 ro를 붙이지 않음. RDS 읽기 복제본은 역할 고정이라 `-ro-NN`), 파라미터 그룹 클러스터 `<접두어>-rds-cpar-apg16-app-01` + 인스턴스 `<접두어>-rds-pagrp-apg16-app-01`

## 예시 (접두어 `hw-iac-dev-an2`)

| 리소스 | 이름 |
|---|---|
| VPC | `hw-iac-dev-an2-vpc-<naming.vpc>-01` |
| 서브넷 (EC2, AZ a) | `hw-iac-dev-an2-sbn-ec2-01-a` |
| EC2 (WAS) | `hw-iac-dev-an2-ec2-was-01-a` |
| EBS (WAS 데이터) | `hw-iac-dev-an2-vol-wasxvdb-01-a` |
| ALB / 대상 그룹 | `hw-iac-dev-an2-alb-was-01` / `hw-iac-dev-an2-tg-was-01` |
| IAM 역할 | `hw-iac-dev-an2-role-was-01` |
| Lambda | `hw-iac-dev-an2-lbd-ebsgrow-01` |
| 백업 플랜 | `hw-iac-dev-an2-bku-plan-daily-01` |
| state 버킷 | `hw-iac-dev-an2-s3-tfstate-01` |

## 예외
- **AWS가 정하는 이름:** RDS 로그 그룹 `/aws/rds/instance/<DB 이름>/<로그>`, `/aws/rds/cluster/<클러스터>/<로그>`, `RDSOSMetrics`, Route53 존·레코드(도메인)
- **로그 그룹 경로:** `/<VPC 이름>/<유형>/<리소스 이름>/<로그>` (이름 규칙 값을 경로에 씀)
- **VPC 이름:** `<접두어>-vpc-<naming.vpc>-01`. 00-bootstrap `naming.vpc`로 정해 Parameter Store에 남기고 01-network가 읽음

## S3 로그 경로 (모든 로그 같은 규칙: `<VPC 이름>/<리소스 유형>/…`)
| 로그 | S3 폴더 (로그 버킷 `<접두어>-s3-logs-01`) |
|---|---|
| EC2 에이전트 | `<VPC>/ec2/<접두어>-ec2-<용도>/messages/YYYY/MM/DD/` (`secure`도 같음) |
| Lambda | `<VPC>/lambda/<접두어>-lbd-<이름>-01/function/YYYY/MM/DD/` |
| RDS | `<VPC>/rds/instance/<DB 이름>/<로그>/YYYY/MM/DD/` |
| Aurora | `<VPC>/rds/cluster/<클러스터 이름>/<로그>/YYYY/MM/DD/` |
| RDS 확장 모니터링 | `<VPC>/rds/RDSOSMetrics/YYYY/MM/DD/` |
| VPC Flow Logs | `<VPC>/vpc/<VPC>/flow-logs/AWSLogs/<계정>/vpcflowlogs/<리전>/YYYY/MM/DD/HH/` |
| ALB 접근 로그 | `<VPC>/elb/<ALB 이름>/access-logs/AWSLogs/<계정>/elasticloadbalancing/<리전>/YYYY/MM/DD/` |
| Firehose 처리 실패 | `firehose-errors/cwlogs/<오류 유형>/YYYY/MM/DD/` |
| 로그 그룹 없는 레코드 (구독 연결 확인) | `_control/` |

AWS가 이름을 정하는 로그 그룹(`/aws/…`, `RDSOSMetrics`)은 이름에 VPC가 없어 Firehose가 00-bootstrap의 VPC 이름을 앞에 붙입니다 (계정당 VPC 하나 기준).
- **AWS가 자동으로 만드는 ENI:** 이름을 정할 수 없어 `Name` 태그만 붙임
- **길이 한도:** ALB·대상 그룹 32자, RDS 식별자 63자. 접두어 14자 + 이름 8자 이내면 ALB·대상 그룹도 들어감
