# network-base

`01-network` 단계에서 쓰는 조합 코드입니다. **모든 리소스가 공유하는 네트워크만** 만들고, 리소스별 서브넷은 CIDR만 계산해서 넘깁니다.

## 만드는 것

| 리소스 | 조건 |
|---|---|
| VPC (DNS support/hostnames 켬), 기본 SG 잠금(규칙 없음) | 항상 |
| 공통 서브넷: **edge**(내부용 LB), **vpce**(endpoint), **transit**(TGW, private NAT) | 항상 |
| **public** 서브넷 + IGW + public NAT(EIP 삭제 보호) | `enable_public = true` |
| private NAT | internal 대역(100.64)을 쓰고 TGW나 peering이 있을 때 |
| 기존 TGW attachment, 사내망·peering 라우트 | `tgw_id`, `peerings` |
| VPC endpoint (인터페이스·gateway, 다른 state가 만든 것은 skip) | `interface_endpoints`, `gateway_endpoints` |
| private 존(항상), public 존(public일 때) | `root_domain` |
| prefix list | `prefix_lists` (필요한 것만) |
| VPC Flow Logs (S3, Parquet) | `enable_flow_logs` (기본 켬) |

ec2, db, eks 서브넷은 **만들지 않습니다.** CIDR만 계산해서 contract로 넘기고, 각 `<유형>-common`이 만듭니다. ALB/NLB도 여기서 만들지 않습니다.

## 대역 배치 v1 (`layout.tf`)

받은 첫 routable 대역을 **AZ별로 균등 분배**합니다(AZ 3개면 4등분하고 4번째는 예비). AZ 블록 안의 표준 /24는 다음과 같습니다.

```text
.0   /26  edge     (59)  내부용 ALB/NLB          private
.64  /27  vpce     (27)  인터페이스 endpoint     private
.96  /28  transit  (11)  TGW, private NAT        private
.112 /28  예비 (수동 서브넷용)
.128 /26  ec2      (59)  ec2-common              private
.192 /27  db       (27)  rds-common 등           private
.224 /27  public   (27)  외부용 LB, public NAT   IGW 경로 (enable_public일 때만)
```

| 받은 대역 (AZ 2개) | AZ 블록 | 배치 |
|---|---|---|
| /23 | /24 | 표준 /24만 |
| /22 | /23 | 표준 /24 + 예비 /24 |
| /21 (EKS routable) | /22 | 표준 /24 + 예비 /24 + **EKS /23**(뒤쪽 절반) |

- 필요한 최소 크기: AZ 1개 /24, 2개 /23, 3~4개 /22. 작으면 plan에서 막힙니다.
- **배치 규칙은 버전으로 관리합니다** (`layout_version`). 기존 버전은 수정하지 않습니다. 자세한 규칙은 `layout.tf` 상단 주석을 보세요.
- `sizing` 출력에 AZ별 서브넷, 사용 가능 IP, 예비 공간이 나옵니다(설계서용).

## 라우팅

| 서브넷 | 0.0.0.0/0 | 사내망 대역 | peering 대역 |
|---|---|---|---|
| public | → IGW | — | — |
| edge, transit | 없음 | → TGW | → peering |
| vpce | 없음 | 없음 | 없음 |
| ec2, db (각 common) | → 같은 AZ public NAT (public일 때) | → TGW | → peering |

`enable_public = false`면 VPC 어디에도 인터넷 경로가 없습니다. 필요한 AWS 서비스는 VPC endpoint로 접근하므로 `interface_endpoints`를 빠뜨리지 마세요.

## EKS

CIDR만 계산합니다(서브넷은 04-eks).
- `routable`: AZ 블록 뒤쪽 절반 앞에 `eks_subnet`(기본 /23) 크기. AZ 블록이 /22 이상이어야 함
- `internal`: 100.64.0.0/16을 AZ별 균등 분배 (AZ 2개 /17). 100.64 대역을 자동으로 VPC에 연결

## 수동 서브넷과 확장

1. `sizing` 출력의 `spare`에 `manual_subnets`로 직접 넣습니다(범위와 겹침을 plan에서 검사).
2. 부족하면 routable 대역을 추가(`vpc_cidrs`)하고, 그 대역에 수동 서브넷을 넣습니다. 대역 추가는 중앙 네트워크 쪽 TGW 라우트 추가가 필요합니다.

## 출력: `contract` (Parameter Store 묶음)

| 묶음 | 내용 |
|---|---|
| `base` | VPC ID, AZ, 대역, `resource_tags` |
| `subnets` | 공통 서브넷 ID, 모든 용도의 CIDR, EKS CIDR, 수동 서브넷 |
| `routing` | public/private NAT ID(AZ별), NAT 공인 IP, TGW, 사내망 대역, peering, prefix list ID |
| `endpoints` | endpoint ID(서비스별), gateway endpoint, endpoint SG |
| `dns` | 존 이름, private/public 존 ID, 상위 존 ID(인증서 검증용) |

기존 키는 이름을 바꾸거나 지우지 않고 추가만 합니다.
