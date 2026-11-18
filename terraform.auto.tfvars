region = "ap-northeast-2"

azs = [
  "ap-northeast-2a",
  "ap-northeast-2c"
]

# ── AZ 개수 (새 구조 network-base용) ─────────────────────────────
# 리전의 AZ 목록(일반 AZ만, 이름순)에서 앞에서부터 az_count개를 순서대로 사용합니다.
#   예) 서울 2 → a, b / 3 → a, b, c     도쿄 2 → a, c (도쿄는 b가 없음)
# 제약 사항
#   - 1 ~ 4만 가능하고, 리전의 사용 가능한 AZ 수보다 클 수 없습니다.
#   - 1이면 ALB, RDS, EKS를 만들 수 없습니다 (AWS 규칙상 AZ 2개 이상 필요). 개발·테스트용.
#   - 사이트를 처음 만들 때 정하고 이후에는 바꾸지 않습니다.
#     바꾸면 대역 분할이 달라져 서브넷과 그 안의 서버가 다시 만들어질 수 있습니다.
#   - 서울의 b(ap-northeast-2b)는 일부 인스턴스 타입을 지원하지 않을 수 있습니다.
#     사용할 인스턴스 타입이 해당 AZ에서 지원되는지 먼저 확인하세요.
# (위 azs는 기존 구조용이며, 사이트를 새 구조로 전환할 때 정리합니다)
az_count = 2

cluster_name = "simple"
resource_prefix = "simple"
site            = "simple"

vpc_name           = "simple-vpc"
vpc_primary_cidr   = "10.227.0.0/27"
vpc_secondary_cidr = ["100.0.0.0/16"]

#bastion_ami           = "ami-01711d925a1e4cc3a"
#bastion_instance_name = "simple-bastion"

# was_name          = "simple-was"
# was_instance_type = "t2.micro"
# was_instance_ami  = "ami-05377cf8cfef186c2" # al2023
# was_alb_name      = "simple-was-alb"

# web_ide_name          = "simple-web-ide"
# web_ide_instance_type = "t2.medium"
# web_ide_instance_ami  = "ami-0eff555c11692fc96" # shared custom image
# web_ide_alb_name      = "simple-web-ide-alb"

create_db         = true
db_name           = "rds"
db_allocated_storage = 20
db_max_allocated_storage = 100
db_user_name      = "user"
db_user_pass      = "12345678" //min length 8
db_engine         = "mysql"
db_engine_version = "5.7"
db_port = 3306
db_instance_class = "db.t3.medium"
multi_az = false



# create_bucket = false
# bucket_name = "simple-bucket"
# bucket_versioning = true
# bucket_private_acl = true

# create_elasticache = false
# elasticache_name = "simple-cache-cluster"
# elasticache_engine = "redis"
# elasticache_node_type = "cache.t2.micro"

KEYCLOAK_REALM = "DevOS"
KEYCLOAK_ENDPOINT = ""
KEYCLOAK_CLIENT_ID = ""
KEYCLOAK_CLIENT_UUID = ""
KEYCLOAK_CLIENT_SECRET = ""
KEYCLOAK_USER_UUID = ""

attachment_tgw       = "tgw-036be97ccc70d1499"
tgw_route_target_ips = ["10.177.160.0/19", "10.222.0.0/15", "165.186.175.0/24", "10.227.0.0/17", "156.147.0.0/16", "100.0.0.0/8", "10.185.66.0/24", "10.233.0.0/17"]
vpc_resolver_rule_id = "rslvr-rr-bde3158ecb3342eba"

root_domain  = ""
root_account = "059055520861"
daytona_url  = ""

common_tags = {}

module_repo_url = "../../bsp-daytona-module"