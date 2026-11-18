# ec2-common

EC2 용도(`ec2-was`, `ec2-webide` 등)가 **같이 쓰는 리소스**를 만듭니다. `network-base`의 `contract`를 받고, `ec2-<용도>`에게 자기 `contract`를 넘깁니다.

```text
network-base ──contract──▶ ec2-common ──contract──▶ ec2-was
                                       └──contract──▶ ec2-webide
```

## 파일 구성

| 파일 | 만드는 리소스 |
|---|---|
| `subnet.tf` | EC2 서브넷(AZ별), AZ별 라우트 테이블. 0.0.0.0/0 → 같은 AZ의 public NAT, 사내망 → private NAT(internal 대역) 또는 TGW(routable 대역) |
| `sg.tf` | **공통 SG** (서버 접근용, 기본값 규칙 없음) |
| `endpoint.tf` | VPC endpoint (SSM 옵션 + 추가 endpoint), endpoint SG |

## 대역: zone + slot

`network-base`의 `stack_zones` 중 `zone`(기본값 `ec2`)에서 `slot` 번호의 블록을 받아 AZ별로 나눕니다.

| 유형 | `slot = 0`일 때 서브넷 |
|---|---|
| routable + internal | a 100.64.0.0/25, b 100.64.0.128/25 (c 100.64.1.0/25, d 100.64.1.128/25) |
| routable 단독 (10.227.0.0/23) | a 10.227.1.0/28, b 10.227.1.16/28 |

`slot`은 사이트에서 고유하게 정하고 **한 번 쓴 번호는 재사용하지 않습니다.**

## 공통 SG (서버 접근용)

- SSH나 서버 접근제어처럼 **서버에 들어가는 경로만** 둡니다. 서비스 포트는 각 용도의 개별 SG에 둡니다.
- 고객사마다 다르기 때문에 **기본값은 규칙 없음**입니다. 사이트 `main.tf`에서 `common_sg_ingress`로 추가합니다.
- 아웃바운드 규칙은 두지 않습니다. 인스턴스에 같이 붙는 개별 SG의 아웃바운드가 적용됩니다.
- `description`에는 **한글을 쓸 수 없습니다**(AWS 제한). 넣으면 plan에서 막힙니다.

```hcl
common_sg_ingress = [
  { from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["10.185.66.0/24"], description = "server access control" },
]
```

## VPC endpoint

| 입력 | 만드는 endpoint |
|---|---|
| `enable_ssm = true` (기본값) | `ssm`, `ssmmessages`, `ec2messages` |
| `endpoints = ["s3", "logs"]` | 추가 endpoint |

- 같은 VPC에 **다른 stack**(예: `eks-common`)이 이미 만든 같은 endpoint가 있으면 만들지 않습니다(skip).
- 자기 자신이 만든 endpoint는 `Stack` 태그로 구분하므로, 두 번째 plan에서 삭제되지 않습니다.
- **같은 apply 안의 stack끼리는 확인이 동작하지 않습니다.** 사이트 `main.tf`에서 endpoint 목록이 겹치지 않게 나눠 줍니다.
- 이 stack이 만든 endpoint는 다른 stack도 같이 씁니다. 삭제 전에 `endpoints_created` 출력을 확인하세요.

## 출력: `contract`

| 키 | 내용 |
|---|---|
| `base` | network-base contract (VPC, edge 서브넷, DNS 등) |
| `subnet_ids`, `subnet_cidrs`, `cidr_block`, `route_table_ids` | EC2 공통 네트워크 |
| `common_sg_id` | 공통 SG |
| `ready` | 인스턴스보다 먼저 준비돼야 하는 endpoint와 라우트 (생성 순서 고정용) |

## 사용 예

```hcl
module "ec2_common" {
  source            = "./deployment/ec2-common"
  base              = module.network_base.contract
  slot              = 0
  enable_ssm        = true
  endpoints         = ["s3"]
  common_sg_ingress = var.ec2_common_sg_ingress   # 고객사별
  common_tags       = var.common_tags
}
```

**주의:** `ec2-<용도>`가 남아 있는 상태에서 이 stack을 지우지 마세요. 서브넷과 공통 SG를 모든 EC2가 같이 씁니다.
