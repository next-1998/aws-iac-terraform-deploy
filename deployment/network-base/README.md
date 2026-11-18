# network-base

모든 stack이 공유하는 네트워크만 만듭니다. stack 전용 리소스(서브넷, SG, role 등)는 각 stack이 만듭니다.

## 네트워크 유형

`vpc_cidrs`에 넣은 대역 구성으로 유형이 자동으로 정해집니다.

| 유형 | `vpc_cidrs` | 워크로드 위치 | 사내망 통신 |
|---|---|---|---|
| **routable 단독** | `[{ cidr = "10.227.0.0/23", role = "routable" }]` | routable 대역 | TGW 직접 |
| **routable + internal** | `[{ cidr = "10.227.0.0/24", role = "routable" }, { cidr = "100.64.0.0/16", role = "internal" }]` | internal 대역 | private NAT → TGW |

| role | 의미 |
|---|---|
| `routable` | 사내망과 통신할 수 있는 대역 (네트워크팀 할당). 반드시 첫 번째(VPC primary) |
| `internal` | VPC 안에서만 쓰는 대역. **`100.64.0.0/16`만 허용** |

internal 대역의 워크로드는 TGW로 직접 나가지 않습니다. VPC 안은 local 라우트로 통신하고, 밖으로 나갈 때는 NAT GW를, 들어올 때는 edge 서브넷의 LB를 거칩니다.

## AZ

- `az_count`로 AZ 개수를 고릅니다. **기본값 2개**이고, 최대 4개입니다.
- 순서는 a → b → c → d로 늘어납니다.

| `az_count` | AZ |
|---|---|
| 2 (기본값) | a, b |
| 3 | a, b, c |
| 4 | a, b, c, d |

배치는 처음부터 **AZ 4개분 자리를 잡아 두고**, 서브넷 번호를 AZ 글자로 고정합니다(a=0, b=1, c=2, d=3). 그래서 `az_count`를 늘려도 **기존 서브넷 CIDR은 바뀌지 않습니다**(테스트로 확인).

ap-northeast-2b는 일부 인스턴스 타입을 지원하지 않을 수 있습니다. 사용할 인스턴스 타입이 2b에서 지원되는지 먼저 확인하세요.

## 대역 배치 (`layout.tf`, 모든 사이트 공통)

routable 대역의 **앞쪽 /24는 항상 base 영역**입니다.

```text
routable 앞쪽 /24 (예: 10.227.0.0/24)
├── 10.227.0.0/27     edge-a     ALB, public NAT
├── 10.227.0.32/27    edge-b     ALB
├── 10.227.0.64/27    edge-c     (az_count >= 3)
├── 10.227.0.96/27    edge-d     (az_count = 4)
├── 10.227.0.128/28   transit-a  TGW attachment, private NAT
├── 10.227.0.144/28   transit-b  TGW attachment
├── 10.227.0.160/28   transit-c  (az_count >= 3)
├── 10.227.0.176/28   transit-d  (az_count = 4)
└── 10.227.0.192/26   예비
```

stack 영역은 유형에 따라 다릅니다. stack은 `zone`과 `slot` 번호로 블록을 받고, 블록을 AZ 4개 자리로 나눠 씁니다.

| 유형 | zone | 영역 | stack 블록 | AZ별 서브넷 |
|---|---|---|---|---|
| routable + internal | `ec2` | 100.64.0.0/18 | /23 (최대 32개) | /25 |
| | `eks` | 100.64.64.0/18 | /18 (1개) | /20 |
| | `db` | 100.64.128.0/20 | /24 (최대 16개) | /26 |
| routable 단독 (/23 기준) | `ec2` | 10.227.1.0/25 | /26 (2개) | /28 |
| | `db` | 10.227.1.128/25 | /26 (2개) | /28 |

routable 단독에서는 eks 영역이 없습니다(Pod IP 부족). routable 대역이 크면 영역과 블록 수가 그만큼 늘어납니다(/21이면 ec2 블록 8개).

**`netnum`과 `slot`은 고정 번호입니다.** 순서를 바꾸거나 재사용하면 서브넷이 삭제됐다가 다시 만들어집니다.

## 만드는 리소스

| 리소스 | 조건 |
|---|---|
| VPC (+ internal 대역 연결) | 항상 |
| edge 서브넷 + 라우트 테이블 (0.0.0.0/0 → IGW, 사내망 → TGW) | 항상 |
| transit 서브넷 + AZ별 라우트 테이블 (0.0.0.0/0 → 같은 AZ의 public NAT, 사내망 → TGW) | 항상 |
| IGW, public NAT (+EIP) | `enable_internet = true` (기본값). NAT 개수는 `nat_per_az`에 따름 |
| private NAT | routable + internal 이고 `tgw_id`가 있을 때 |
| TGW attachment (transit 서브넷) | `tgw_id`가 있을 때 |
| Route53 존 `<site>.<root_domain>` + 상위 존 NS 위임 | `root_domain`이 있을 때 |
| Resolver Rule 연결 | `resolver_rule_id`가 있을 때 |

### NAT 배치 (`nat_per_az`)

| `nat_per_az` | NAT | 라우팅 | 특징 |
|---|---|---|---|
| `true` (기본값) | AZ마다 public NAT, private NAT | 각 AZ의 서브넷은 같은 AZ의 NAT로 나감 | AZ 하나에 장애가 나도 다른 AZ는 정상. AZ 간 전송 비용 없음 |
| `false` | 첫 번째 AZ(a)에 1개씩 | 모든 AZ가 a의 NAT를 씀 | NAT 비용 절감. a AZ에 장애가 나면 전체 외부 통신 중단 |

이를 위해 transit 서브넷과 stack 서브넷의 라우트 테이블은 AZ마다 따로 만듭니다.

모든 리소스의 `Stack` 태그는 `<site>/network-base`입니다.

## 입력 검증 (plan에서 막힘)

| 잘못된 입력 | 이유 |
|---|---|
| internal 대역이 `100.64.0.0/16`이 아님 | internal 대역 고정 규칙 |
| 첫 번째 대역이 routable이 아님, routable이 2개 | VPC primary는 routable |
| routable + internal 인데 routable이 /24보다 작음 | base 영역(/24)이 안 들어감 |
| routable 단독인데 routable이 /23보다 작음 | stack 영역이 없음 |
| `az_count`가 2~4가 아님 | 최대 AZ 4개 기준 배치 |

## 출력: `contract`

`<유형>-common`은 `base = module.network_base.contract` 하나로 필요한 값을 모두 받습니다.

| 키 | 내용 |
|---|---|
| `site`, `vpc_id`, `vpc_name` | 기본 정보 |
| `azs`, `az_index`, `max_azs` | 사용 중인 AZ, AZ별 고정 번호(a=0 ~ d=3), 최대 AZ 수(4) |
| `network_type` | `routable` / `hybrid` |
| `vpc_cidrs`, `routable_cidr`, `internal_cidr`, `stack_zones` | 대역 |
| `edge_subnet_ids`, `edge_subnet_cidrs`, `edge_route_table_id`, `transit_subnet_cidrs` | base 서브넷 |
| `igw_id`, `public_nat_ids`, `private_nat_ids` (AZ → NAT ID), `nat_per_az`, `tgw_id`, `tgw_route_cidrs` | 라우팅 대상 |
| `zone_id`, `zone_name` | DNS |
| `has_public_nat`, `has_private_nat`, `has_tgw`, `has_zone` | plan 시점에 정해지는 플래그. stack의 `count` 조건은 ID 대신 이 값을 씁니다 |
| `resource_tags` | stack이 리소스 생성 시 붙일 태그 (`VpcName`) |

## 사용 예

```hcl
module "network_base" {
  source   = "./deployment/network-base"
  site     = var.site
  vpc_name = "${var.site}-vpc"
  vpc_cidrs = [
    { cidr = "10.227.0.0/24", role = "routable" },
    { cidr = "100.64.0.0/16", role = "internal" },
  ]
  az_count         = 2
  nat_per_az       = true
  enable_internet  = true
  tgw_id           = var.attachment_tgw
  tgw_route_cidrs  = var.tgw_route_target_ips
  root_domain      = "example.com"
  resolver_rule_id = var.vpc_resolver_rule_id
  common_tags      = var.common_tags
}
```
