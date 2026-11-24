# ec2-was

WAS 서버를 만듭니다. 서브넷과 공통 SG는 `ec2-common`의 것을 쓰고, 이 폴더는 **WAS에만 필요한 것**을 만듭니다.

다른 EC2 용도가 필요하면 이 폴더를 복사해서 `ec2-<용도>`로 이름을 바꾸고, `variables.tf`의 `name` 기본값을 폴더 이름으로 바꿉니다.

## 만드는 것

| 파일 | 리소스 |
|---|---|
| `sg.tf` | **개별 SG**(`app`)와 ALB SG(`alb`)의 규칙. 기본 규칙(ALB → app_port, VPC·gateway endpoint 아웃바운드, ALB 80/443)은 코드에, 사이트 추가 규칙은 `src/sg_rules.csv` |
| `src/sg_rules.csv` | 협의한 SG 추가 규칙 (`sg` 열: `app`, `alb` / 대상 `sg:common`은 ec2-common 공통 SG). 형식: module repo `module/_sg_rules_csv/README.md` |
| `src/sg_rules.example.csv` | 예제 (적용되지 않음). 복사해서 `sg_rules.csv`에 필요한 행만 옮겨 씁니다 |
| `src/README.md` | **SG 규칙 가이드**: 규칙을 붙일 수 있는 SG, 코드 기본 규칙, CSV 형식, 협의 항목 |
| `iam.tf` | 이 서버 전용 IAM role, instance profile. **필수 정책**(뺄 수 없음): SSM 접속(`AmazonSSMManagedInstanceCore`), CloudWatch Agent 지표·로그(`CloudWatchAgentServerPolicy`). 로그 그룹 생성·보관 기간 변경은 **거부**(Terraform이 미리 만든 로그 그룹만 씀). 폐쇄망이면 01-network에 `logs`, `monitoring` endpoint 필요 |
| `ec2.tf` | EC2(공인 IP 없음, **루트 볼륨만**). SG는 `[공통 SG, 개별 SG]`. AMI·이미지에 포함된 볼륨은 배포 후 바뀌어도 Terraform이 손대지 않음(서버 교체 없음) |
| `volumes.tf` | **데이터 볼륨**(`ebs_volumes`): 서버를 만든 뒤 따로 만들어 붙임. 크기는 tfvars로만 늘림(서버 교체 없음). `mount_point`가 있으면 SSM 연결로 `src/mount_volumes.sh` 실행(디렉터리 확인·생성, 처음만 포맷, 마운트, fstab, 증설 시 확장) |
| `alb.tf` | ALB, ALB SG, target group, listener, DNS 레코드, WAF 연결 (`enable_alb = true`일 때) |

## ALB

ALB는 네트워크 단계에서 만들지 않고, **이 리소스를 만들 때** 만듭니다.

| `alb_internal` | 서브넷 | 접근 허용 기본값 | DNS 레코드 |
|---|---|---|---|
| `true` (기본값) | edge | VPC + 사내망 대역 | private 존 |
| `false` (외부용) | public (**01-network `enable_public = true` 필요**, 아니면 plan에서 막힘) | 0.0.0.0/0 | public 존 + private 존 |

- 인증서(`alb_certificate_arn`, 보통 `shared-common`의 사이트 인증서)가 있으면 80 → 443 리다이렉트, 443 → 서버
- 접근 출발지는 `alb_ingress_prefix_lists`(prefix list 이름)를 권장합니다.
- 접근 로그: `access_log_bucket`을 주면 `<버킷>/<VPC 이름>/elb/<ALB 이름>/access-logs/…`에 저장
- WAF: `waf_acl_arn`을 주면 연결 (기본값 없음)
- AZ 2개 이상이 아니면 plan에서 막힙니다.

## 주말 중지

`weekend_stop_enable = true`면 EC2, EBS, instance profile에 `WEEKEND_STOP_ENABLE = true` 태그가 붙습니다(리소스 생성 시 태그).

## 아직 지원하지 않는 것

- EC2 key pair (SSM 또는 서버 접근제어로 접속)
- EC2 여러 대, ASG
