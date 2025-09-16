region = "ap-northeast-2"

azs = [
  "ap-northeast-2a",
  "ap-northeast-2c"
]

cluster_name = "simple"
resource_prefix = "simple"

vpc_name           = "simple-vpc"
vpc_primary_cidr   = "10.227.0.0/27"
vpc_secondary_cidr = "100.0.0.0/16"

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

# module_repo_url = 