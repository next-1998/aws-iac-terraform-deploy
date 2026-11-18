# ec2-common

`02-resource` 단계에서 EC2 용도(`ec2-was`, `ec2-webide` 등)가 **같이 쓰는 리소스**를 만듭니다.

```text
01-network (Parameter Store) ──network──▶ ec2-common ──contract──▶ ec2-was
                                                     └──contract──▶ ec2-webide
```

## 만드는 것

| 파일 | 리소스 |
|---|---|
| `subnet.tf` | EC2 서브넷(01-network가 계산한 CIDR, + `purpose = "ec2"` 수동 서브넷), AZ별 라우트 테이블, gateway endpoint(S3 등) 연결 |
| `sg.tf` | **공통 SG** (서버 접근용, 기본값 규칙 없음) |

라우팅: 0.0.0.0/0 → 같은 AZ의 public NAT(01-network에서 public을 켰을 때), 사내망 → TGW, peering 대역 → peering

## 공통 SG

- SSH, 서버 접근제어처럼 **서버에 들어가는 경로만** 둡니다. 서비스 포트는 각 용도의 개별 SG에 둡니다.
- 고객사마다 다르므로 **기본값은 규칙 없음**입니다. 사이트 tfvars의 `ec2_common_sg_ingress`로 추가합니다.
- 출발지는 IP보다 **prefix list 이름**(`prefix_lists = ["access_ctl"]`)을 권장합니다. 01-network에서 만든 이름을 씁니다.
- `description`에는 한글을 쓸 수 없습니다(AWS 제한, plan에서 막힘).

```hcl
ec2_common_sg_ingress = [
  { from_port = 22, to_port = 22, protocol = "tcp", prefix_lists = ["access_ctl"], description = "server access control" },
]
```

## 출력: `contract`

| 키 | 내용 |
|---|---|
| `network` | 01-network contract (그대로 전달) |
| `subnet_ids`, `manual_subnets`, `subnet_cidrs`, `route_table_ids` | EC2 네트워크 |
| `common_sg_id` | 공통 SG |
| `ready` | 인스턴스보다 먼저 준비돼야 하는 라우트, endpoint 연결 (생성 순서 고정용) |

**주의:** `ec2-<용도>`가 남아 있는 상태에서 이 stack을 지우지 마세요. 서브넷과 공통 SG를 모든 EC2가 같이 씁니다.
