# ec2-webide

Web IDE 서버를 만듭니다. 서브넷과 공통 SG는 `ec2-common`의 것을 쓰고, 이 폴더는 **Web IDE에만 필요한 것**만 만듭니다.

다른 EC2 용도가 필요하면 이 폴더를 복사해서 `ec2-<용도>`로 이름을 바꾸고, `variables.tf`의 `name` 기본값을 폴더 이름으로 바꾸면 됩니다.

## 파일 구성

| 파일 | 만드는 리소스 |
|---|---|
| `sg.tf` | **개별 SG** (서비스 포트). ALB를 켜면 ALB → `app_port` 규칙 자동 추가 |
| `iam.tf` | 이 서버 전용 IAM role (SSM 접속 정책 기본 포함) |
| `ec2.tf` | instance profile, EC2, EBS. SG는 `[공통 SG, 개별 SG]` 두 개 연결 |
| `alb.tf` | ALB, ALB SG, target group, listener, DNS 레코드 (`enable_alb = true`일 때만) |

## SG

| SG | 위치 | 용도 |
|---|---|---|
| 공통 SG | `ec2-common` | SSH, 서버 접근제어 |
| 개별 SG | 이 폴더 | 서비스 포트 (`ingress_rules`, ALB → `app_port`) |

`ingress_rules`의 `description`에는 한글을 쓸 수 없습니다(AWS 제한).

## ALB

- `enable_alb = true`일 때만 만듭니다. 용도마다 따로 둡니다.
- ALB는 `network-base`의 edge 서브넷(routable 대역)에 만듭니다. internal 대역의 서버는 ALB를 거쳐서만 외부 요청을 받습니다.
- 인증서(`alb_certificate_arn`)가 있으면 80 → 443 리다이렉트를 만들고, 443을 서버로 보냅니다. 없으면 80을 그대로 서버로 보냅니다.
- `alb_record_name`을 주면 `<이름>.<site>.<root_domain>` 레코드를 만듭니다.

## 주말 중지

`weekend_stop_enable = true`면 EC2, EBS, instance profile에 `WEEKEND_STOP_ENABLE = true` 태그가 붙습니다(리소스 생성 시 태그). 주말 중지 Lambda가 이 태그를 읽습니다.

## 사용 예

```hcl
module "ec2_webide" {
  source              = "./deployment/ec2-webide"
  common              = module.ec2_common.contract
  ami                 = var.web_ide_instance_ami
  instance_type       = var.web_ide_instance_type
  ebs_volumes         = [{ device_name = "/dev/xvdb", volume_size = 20 }]
  user_data           = templatefile("${path.root}/files/run_web_ide.tpl", { ... })
  weekend_stop_enable = true

  ingress_rules = []   # 서비스 포트 (ALB 경유만 쓰면 비워 둠)

  enable_alb          = true
  alb_certificate_arn = module.acm_site.acm_certificate_arn
  alb_record_name     = "ide"

  common_tags = var.common_tags
}
```

## 태그

| 태그 | 값 (예: 개별 SG) |
|---|---|
| `Stack` | `simple/ec2-webide` |
| `ResourceType` | `ec2:security-group` |
| `ResourceKey` | `ec2_webide_sg` |
| `Scope` | `stack` |
| `VpcName` | `simple-vpc` |
| `WEEKEND_STOP_ENABLE` (EC2, EBS, instance profile) | `weekend_stop_enable` 값 |

## 아직 지원하지 않는 것

- EC2 key pair (instance 모듈에 `key_name` 입력이 없음. SSM 또는 서버 접근제어로 접속)
- EC2 여러 대, ASG
