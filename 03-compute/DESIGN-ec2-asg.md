# 설계: 고정 EC2 + 자동 확장(ASG) 옵션

> 상태: **설계 확정, 구현 전** (2026-11-25). 브랜치 `tf1.17-aws6_mgkim`

## 1. 결정 사항

| # | 항목 | 결정 |
|---|---|---|
| 1 | 구조 | 용도 폴더(`ec2-was` 등) 하나에 **고정 EC2 1대 + 자동 확장 옵션**. 고정 서버와 확장 서버가 같은 SG·IAM·ALB 대상 그룹을 씀 |
| 2 | 옵션 | `autoscale.enabled` (기본 **false**). 켠 용도만 최초 이미지·Launch Template·ASG·스케일링을 만듦. 끄면 지금과 같음 |
| 3 | 고정 서버 | 지금 그대로: 항상 1대, AMI 변경 무시, 루트 + 데이터 볼륨 + 마운트, 고정 IP |
| 4 | 확장 서버 | ASG **최소 0 ~ 최대 `max_extra`** (기본 0). 2번째 서버부터 부하에 따라 늘고 줄어듦 |
| 5 | 최초 이미지 | `autoscale.ami`가 없으면 **Terraform이 고정 EC2로 한 번만 생성** (1차 apply). 데이터 볼륨까지 포함 (빼지 않음). 마운트·Agent 설치가 끝난 뒤 생성 |
| 6 | 이후 이미지 | Terraform 밖에서 만들어 **`autoscale.ami`에 고정 ID**로 넣음 → 확장 서버만 순차 교체. 최초 이미지는 다시 만들지 않음 |
| 7 | Launch Template 볼륨 | 이미지에 들어간 데이터 볼륨은 **종료 시 삭제**로 덮어씀 (축소 때 볼륨이 남지 않게) |
| 8 | 스케일링 | **CPU·메모리** 그룹 평균(고정 + 확장 서버). 늘리기: 둘 중 하나라도 **80%** 초과, 줄이기: 둘 다 **50%** 미만. 값 수정 가능 |
| 9 | 주말 중지 | 선택형, **기본 꺼짐**. 고정 서버는 Lambda(태그), 확장 서버는 예약 스케일링으로 0대 |
| 10 | DB | RDS가 기본 (서버 데이터 볼륨에 DB를 두지 않음) |

## 2. 구조

```text
deployment/ec2-was (용도 폴더)
 ├ iam.tf, sg.tf          그대로 (고정·확장 서버 공용)
 ├ ec2.tf, volumes.tf      그대로 (고정 서버)
 ├ logs.tf                 + Agent가 CPU·메모리 지표를 ServiceGroup(<site>-ec2-<용도>) 기준으로 전송
 │                           + 마운트 SSM 연결은 성공까지 대기 (최초 이미지가 마운트 후 찍히도록)
 ├ alb.tf                  그대로 (대상 그룹 공용)
 ├ image.tf   (새로)       최초 이미지 (autoscale.enabled && ami 없음, 한 번만)
 ├ lt.tf      (새로)       Launch Template: 이미지(autoscale.ami → 최초 이미지), 사양, SG, 프로파일, IMDSv2, 데이터 볼륨 종료 시 삭제
 ├ asg.tf     (새로)       ASG 0 ~ max_extra, 모든 AZ, 대상 그룹 연결, ELB 헬스체크, 줄일 때 최신 서버부터, 순차 교체
 └ scaling.tf (새로)       CPU·메모리 알람(높음/낮음) → 단계 정책(+1/-1), 주말 예약(선택)
```

## 3. 순서 (값 참조로, depends_on 없음)

```text
고정 EC2 → 데이터 볼륨 연결 → 마운트 SSM(성공 대기) ┐
                              Agent SSM               ├→ 최초 이미지 → Launch Template → ASG → 알람·정책
```

## 4. 입력 (03-compute tfvars, 용도별)

```hcl
was = {
  ami = "ami-…"                       # 고정 서버 (골든 AMI, 애플리케이션 포함 가능)
  autoscale = {
    enabled       = false             # 기본 꺼짐
    ami           = null              # 없으면 최초 1회 고정 EC2로 이미지 생성. 이후 변경은 여기에 고정 ID
    max_extra     = 0                 # 확장 서버 최대 대수 (0이면 대기만)
    scale_out     = 80                # CPU 또는 메모리 평균 % 초과 시 +1
    scale_in      = 50                # CPU와 메모리 평균 % 모두 미만 시 -1
    image_reboot  = false             # 최초 이미지 생성 시 고정 서버 재부팅 (일관성 ↑, 잠시 중단)
    instance_type = null              # null이면 고정 서버와 같음
    weekend_stop  = { enabled = false, stop_schedule = "0 21 * * FRI", start_schedule = "0 7 * * MON" }
  }
}
```

### 켜기 전 확인 (협의 항목, 고객 서비스 담당)
- 이미지(AMI)만으로 애플리케이션이 뜨는가 (수동 설치·설정 없음)
- 세션·업로드 파일을 서버 밖(DB·Redis·S3·EFS)에 두는가. 데이터 볼륨은 **이미지 시점의 복사본**이 확장 서버에 들어가고, 확장 서버에서 쓴 데이터는 축소 시 사라짐
- 라이선스가 서버 대수·IP에 묶여 있지 않은가
- 외부 방화벽이 서버 IP가 아니라 대역·SG로 허용되어 있는가

## 5. 동작

| 상황 | 고정 서버 | 확장 서버 |
|---|---|---|
| 1차 apply (enabled, ami 없음) | 생성 → 볼륨·마운트·Agent | 최초 이미지 생성, Launch Template·ASG(0대) |
| 부하 80% 초과 | 그대로 | +1 (최대 `max_extra`) |
| 부하 50% 미만 | 그대로 | -1 (최신 서버부터, 최소 0) |
| `autoscale.ami` 변경 | 그대로 | Launch Template 새 버전 → 순차 교체 |
| 고정 서버 `ami` 변경 | 무시 | 영향 없음 |
| destroy | 기존과 같음 | 테스트: 최초 이미지까지 삭제 / 운영 모드: 최초 이미지 삭제 보호 |

## 6. 비용 (확장 서버 0대일 때, 용도당)

| 항목 | 월 |
|---|---|
| ASG, Launch Template, 정책 | 무료 |
| 최초 이미지 스냅샷 (루트 + 데이터) | 약 $0.05/GB (예: 50GB ≈ $2.5) |
| 알람 2개 (지표 2개씩) | 약 $0.4 |
| Agent 지표 (CPU·메모리) | 약 $1.2 + 전송 약 $0.4 |
| 확장 서버가 뜨면 | 뜬 시간만큼 EC2·EBS |

## 7. 새로 필요한 모듈 (module repo, 리소스 유형당 하나)

| 모듈 | 리소스 |
|---|---|
| `computing/aws-ami-workload/from-instance` | `aws_ami_from_instance` (삭제 보호 옵션, 원본 서버 변경 무시) |
| `computing/aws-asg-workload/policy` | `aws_autoscaling_policy` (단계 스케일링) |
| `computing/aws-asg-workload/schedule` | `aws_autoscaling_schedule` |
| `monitor_log/aws-cloudwatch-workload/metric-alarm` | `aws_cloudwatch_metric_alarm` (지표 계산식: max(CPU, 메모리)) |

기존 모듈 수정: Launch Template(블록 디바이스 덮어쓰기), ASG(종료 정책 NewestInstance, 대상 그룹), SSM 연결(성공 대기 옵션).

## 8. 테스트 계획
1. 로컬: 옵션 끔 = 변화 없음, 옵션 켬 = 리소스 생성, 입력 검사
2. 테스트 계정: 옵션 켬(max_extra 2) → 최초 이미지에 데이터 볼륨 포함·마운트 상태 확인 → 부하(stress)로 +1, 해제 후 -1 → 축소 시 볼륨 삭제 확인 → `autoscale.ami` 변경 시 확장 서버만 교체
