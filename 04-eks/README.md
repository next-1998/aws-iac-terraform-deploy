# 04-eks (예정)

EKS 클러스터를 만드는 단계입니다. 아직 구현하지 않았고, 정해진 설계만 적어 둡니다.

| 항목 | 설계 |
|---|---|
| 서브넷 | `eks-common`이 만듦. CIDR은 01-network의 `subnets.eks_cidrs` (eks_placement가 정해져 있어야 함) |
| 크기 | AZ마다 /23 이상 (routable 배치 시 `eks_subnet`) |
| 배치 | `eks_placement = "routable"` 또는 `"internal"`(100.64.0.0/16 균등 분배). 01-network tfvars에서 직접 지정 |
| 라우팅 | routable: 0.0.0.0/0 → public NAT(있을 때), 사내망 → TGW<br>internal: 0.0.0.0/0 → public NAT(있을 때), 사내망 → private NAT |
| API 접근 | private endpoint만. EKS SG는 03-compute의 EC2 SG(`/iac/<site>/03-compute/ec2`)에서만 443 허용 |
| LB 위치 | 서브넷 태그로 찾음: edge = `kubernetes.io/role/internal-elb`, public = `kubernetes.io/role/elb` (01-network가 붙여 둠) |
| AZ 검사 | AZ 2개 이상이 아니면 plan에서 에러 |
| endpoint | public을 끈 사이트는 01-network `interface_endpoints`에 ecr.api, ecr.dkr, sts, ec2, logs, elasticloadbalancing, autoscaling (+ gateway s3) 필요 |
| 서비스 대역 | 사내망 대역과 겹치지 않게 `service_ipv4_cidr`를 명시 |

입력: `/iac/<site>/01-network/*`, `/iac/<site>/03-compute/ec2`
출력: `/iac/<site>/04-eks/cluster` (05-pod가 읽음)
