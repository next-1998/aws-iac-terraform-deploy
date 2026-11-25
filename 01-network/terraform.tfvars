############################################################
# 01-network — 사이트: simple (예시 값. 실제 값으로 바꿔서 사용)
#
# [구축 전 협의 항목]  (★ = 처음에 정하면 이후 변경 어려움)
#   항목                     협의 대상            값
#   ★ VPC routable 대역      고객 네트워크팀      vpc_cidrs (AZ 수에 맞는 크기)
#   ★ AZ 개수                고객 (가용성/비용)   az_count
#   ★ 인터넷 사용 여부       고객 보안팀          enable_public (기본 폐쇄망)
#     NAT 이중화             고객 (비용)          nat_per_az (enable_public일 때만)
#     사내망 연결            중앙 네트워크 계정   tgw_id, corp_cidrs (+ RAM 수락·attachment 승인 사전 요청)
#     VPC peering            상대 VPC 담당        peerings
#     접근 허용 대역         고객 보안팀          prefix_lists (서버 접근제어, 관리자 PC 등)
#   ★ EKS 사용·배치          고객 (서비스 계획)   eks_placement, eks_subnet
#     사용할 AWS 서비스      고객 (폐쇄망 필수)   interface_endpoints, gateway_endpoints
#     도메인                 고객 DNS 담당        root_domain, resolver_rule_id (+ Resolver inbound 사전 요청)
#     로그 보관 위치         고객 보안팀          enable_flow_logs, central_log_bucket_arn
#     비용·관리 태그         고객 (회계/운영)     common_tags
############################################################
site        = "simple"
environment = "dev"
region      = "ap-northeast-2"

common_tags = {
  # Owner      = "platform-team"
  # CostCenter = "cc-1234"
}

# ── 배치 규칙 버전 ─────────────────────────────────────────────
# 사이트를 처음 만들 때 정하고 이후 변경 금지 (바꾸면 서브넷이 다시 만들어짐)
layout_version = "v1"

# ── VPC 대역 ──────────────────────────────────────────────────
# 첫 번째는 routable(네트워크팀 할당, VPC primary). AZ별로 균등 분배됩니다.
# 필요한 크기 (AZ 블록 /24 기준): AZ 1개 /24, 2개 /23, 3~4개 /22
# EKS를 routable에 두면 AZ 블록 /22 이상 필요 (AZ 2개 /21)
# internal(100.64.0.0/16)은 eks_placement = "internal"이면 자동 추가
vpc_cidrs = [
  { cidr = "10.227.0.0/23", role = "routable" }, # ← 네트워크팀 할당 값으로 변경
]

# ── AZ 개수 ───────────────────────────────────────────────────
# 리전의 AZ 목록(일반 AZ만, 이름순)에서 앞에서부터 az_count개를 순서대로 사용합니다.
#   예) 서울 2 → a, b / 3 → a, b, c     도쿄 2 → a, c (도쿄는 b가 없음)
# 제약 사항
#   - 1 ~ 4만 가능하고, 리전의 사용 가능한 AZ 수보다 클 수 없습니다.
#   - 1이면 ALB, RDS, EKS를 만들 수 없습니다 (AWS 규칙상 AZ 2개 이상 필요). 개발·테스트용.
#   - 사이트를 처음 만들 때 정하고 이후에는 바꾸지 않습니다.
#     바꾸면 대역 분할이 달라져 서브넷과 그 안의 서버가 다시 만들어집니다.
#   - 3이면 대역을 4등분해서 4번째 칸은 예비로 남깁니다.
#   - 서울의 b(ap-northeast-2b)는 일부 인스턴스 타입을 지원하지 않을 수 있습니다.
az_count = 2

# ── 인터넷 (public) ───────────────────────────────────────────
# false(기본값): 인터넷을 쓰지 않음. 0.0.0.0/0 경로 없음. AWS 서비스는 VPC endpoint로만 접근
# true         : public 서브넷 + IGW + public NAT 생성, 외부용 ALB 허용
enable_public = false
nat_per_az    = true # true: AZ마다 NAT / false: 첫 번째 AZ에 1개 (비용 절감)

# ── 사내망 연결 (기존 TGW에 attach만 함) ───────────────────────
# 사전 요청: TGW RAM 공유 자동 수락, attachment 자동 승인, TGW 라우트 테이블 연결·전파 (중앙 네트워크 계정)
tgw_id = "tgw-036be97ccc70d1499"
corp_cidrs = [
  "10.177.160.0/19",
  "10.222.0.0/15",
  "165.186.175.0/24",
  "10.227.0.0/17",
  "156.147.0.0/16",
  "10.185.66.0/24",
  "10.233.0.0/17",
  # "100.0.0.0/8" 는 제외: internal(100.64)은 VPC 안에서만 사용 (네트워크팀 확인 필요)
]
peerings = {}

# ── prefix list (필요한 것만 추가, description은 영문) ────────
# SG 규칙에서 IP 대신 이름으로 참조합니다 (sg_rules.csv의 source = pl:<이름>). max_entries만큼 SG 규칙 한도를 씁니다.
# 기본은 CSV로 넣습니다: deployment/network-base/src/prefix_lists.csv (예제: src/prefix_lists.example.csv)
#   열: list,no,cidr,description,max_entries,memo  (no = 목록별 순번, max_entries는 목록의 한 행에만 넣어도 됨, 비우면 10)
# CSV 대신 여기(tfvars)에 넣어도 됩니다. 둘 다 넣으면 plan에서 막힙니다 (둘 중 하나만).
prefix_lists = {
  # access_ctl = { max_entries = 5, entries = { "10.185.66.10/32" = "server-access-control" } }
  # admin      = { max_entries = 10, entries = { "10.185.66.0/24" = "admin-pc" } }
  # corp       = { max_entries = 10, entries = { "10.0.0.0/8" = "corp-network" } }
  # corp_proxy = { max_entries = 2, entries = { "10.185.1.10/32" = "corp-proxy" } }
  # (deployment/ec2-*/src/sg_rules.example.csv 예제가 이 이름들을 씁니다)
}

# ── EKS 배치 (EKS를 쓸 때만) ──────────────────────────────────
# null: EKS 없음 / "routable": AZ 블록 뒤쪽 절반 (eks_subnet 크기, /23 이상) / "internal": 100.64.0.0/16 균등 분배
eks_placement = null
eks_subnet    = 23

# ── 수동 서브넷 (sizing 출력의 spare 또는 추가 routable 대역에만) ──
manual_subnets = []

# ── VPC endpoint ──────────────────────────────────────────────
# enable_public = false면 서버가 쓰는 AWS 서비스 endpoint를 반드시 넣어야 합니다.
#   EC2 (필수) : ssm, ssmmessages, ec2messages (접속), logs, monitoring (CloudWatch Agent 로그·지표) (+ s3, kms 필요 시)
#   EKS       : ecr.api, ecr.dkr, sts, ec2, logs, elasticloadbalancing, autoscaling (+ s3)
interface_endpoints = ["ssm", "ssmmessages", "ec2messages", "logs", "monitoring"]
gateway_endpoints   = ["s3"]

# ── DNS ───────────────────────────────────────────────────────
# private 존 <site>.<root_domain>은 항상 생성. public 존은 enable_public일 때만
# 사내망에서 private 존을 조회하려면 중앙 쪽 Resolver inbound 설정이 필요합니다.
root_domain      = "daytona-platform.com"
resolver_rule_id = "rslvr-rr-bde3158ecb3342eba"

# ── 로그 ──────────────────────────────────────────────────────
# central_log_bucket_arn = null(기본값)이면 00-bootstrap 로그 버킷 사용
enable_flow_logs = true
# central_log_bucket_arn = "arn:aws:s3:::central-logs-bucket"

# ── 운영 모드 (삭제 보호) ─────────────────────────────────────
# operation_mode = "enable" : 운영. 버킷·KMS 키·NAT EIP 삭제 불가, KMS 삭제 대기 30일, ALB 삭제 보호, EC2 볼륨은 서버 삭제 후에도 남김, RDS 삭제 보호(최종 스냅샷)·Multi-AZ, 백업 볼트 보존
# 그 외(null, 기본)         : 모두 삭제 가능 (테스트처럼 만들고 지우는 환경)
# 처음 배포할 때 정하고 바꾸지 않습니다 (바꾸면 버킷·KMS 키·EIP가 새로 만들어짐). 모든 단계에 같은 값을 넣습니다
operation_mode = null

# 항목별 선택 (비우면 operation_mode를 따름. true = 삭제 불가, false = 삭제 가능)
deletion_protection = {
  # buckets     = true # state·로그 버킷 (00-bootstrap)
  # kms_keys    = true # KMS 키 (00-bootstrap, 02-shared)
  # nat_eip     = true # NAT EIP (01-network)
  # alb         = true # ALB 삭제 보호 (03-compute)
  # ec2_volumes = true # 서버 삭제 후 EBS 볼륨 유지 (03-compute)
  # rds         = true # RDS 삭제 보호 + 삭제 시 최종 스냅샷 (03-database)
  # backups     = true # 백업 볼트 삭제 불가·남은 백업 보존 (02-shared)
}
