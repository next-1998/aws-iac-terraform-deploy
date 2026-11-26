############################################################
# 01-network
#   VPC와 기본 네트워크(공통 서브넷, NAT, VPC endpoint, DNS, TGW/peering 연결)를 만들고,
#   결과를 Parameter Store에 묶음별로 남깁니다. 02-shared, 03-compute, 03-database, 04-eks가 읽습니다.
#     /iac/<site>/01-network/base | subnets | routing | endpoints | dns
############################################################

# 로그 버킷: 중앙 로그 버킷이 지정되지 않으면 00-bootstrap 로그 버킷 사용
# String 파라미터라 insecure_value로 읽습니다 (value는 항상 sensitive)
data "aws_ssm_parameter" "bootstrap_logs" {
  count = var.enable_flow_logs && var.central_log_bucket_arn == null ? 1 : 0
  name  = "/iac/_account/00-bootstrap/logs"
}

# 이름 규칙 앞부분 (00-bootstrap이 남긴 값: <회사>-<서비스>-<환경>-<리전 코드>)
data "aws_ssm_parameter" "bootstrap_naming" {
  name = "/iac/_account/00-bootstrap/naming"
}

locals {
  naming      = jsondecode(data.aws_ssm_parameter.bootstrap_naming.insecure_value)
  name_prefix = local.naming.prefix
  # VPC 이름도 00-bootstrap이 정함 (naming.vpc). 로그 S3 경로(<VPC 이름>/…)와 같은 이름이어야 하므로 여기서 만들지 않음
  vpc_name = local.naming.vpc_name

  log_bucket_arn = var.central_log_bucket_arn != null ? var.central_log_bucket_arn : (
    length(data.aws_ssm_parameter.bootstrap_logs) > 0 ? jsondecode(data.aws_ssm_parameter.bootstrap_logs[0].insecure_value).bucket_arn : null
  )
}

module "network_base" {
  source = "../deployment/network-base"

  site           = var.site
  name_prefix    = local.name_prefix
  vpc_name       = local.vpc_name # 00-bootstrap naming.vpc → <접두어>-vpc-<vpc>-01
  common_tags    = var.common_tags
  layout_version = var.layout_version

  vpc_cidrs  = var.vpc_cidrs
  az_count   = var.az_count
  nat_per_az = var.nat_per_az

  enable_public = var.enable_public
  tgw_id        = var.tgw_id
  corp_cidrs    = var.corp_cidrs
  peerings      = var.peerings
  prefix_lists  = var.prefix_lists

  eks_placement  = var.eks_placement
  eks_subnet     = var.eks_subnet
  manual_subnets = var.manual_subnets

  interface_endpoints     = var.interface_endpoints
  gateway_endpoints       = var.gateway_endpoints
  endpoint_skip_if_exists = var.endpoint_skip_if_exists

  root_domain      = var.root_domain
  resolver_rule_id = var.resolver_rule_id

  enable_flow_logs    = var.enable_flow_logs
  flow_log_bucket_arn = local.log_bucket_arn
  protect_nat_eip     = local.protect.nat_eip
}

############################################################
# 다음 단계로 넘길 값 (묶음별, Intelligent-Tiering: 4KB 이하는 Standard)
#   규칙: 기존 키는 바꾸거나 지우지 않고 추가만 합니다.
############################################################
module "contract" {
  source = "../../aws-iac-terraform-module/module/management/aws-ssm-parameter-workload"

  path_prefix = "/iac/${var.site}/01-network"
  description = "01-network 묶음 (02-shared, 03-*, 04-eks가 읽음)"
  parameters  = module.network_base.contract

  common_tags = var.common_tags
  site        = var.site
  stack       = "01-network"
  key_target  = "contract"
}
