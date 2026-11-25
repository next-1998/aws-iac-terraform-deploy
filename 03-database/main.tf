############################################################
# 03-database
#   DB 유형 전체를 만듭니다 (state 하나).
#   - rds-common : DB 서브넷, 라우트, DB 서브넷 그룹, RDS 키 (1차 조합)
#   - rds-db     : 파라미터 그룹, DB 인스턴스, SG, 로그 그룹 (2차 조합, DB마다 한 번)
#   읽는 값: /iac/<site>/01-network/*, /iac/_account/00-bootstrap/kms (logs 키)
#   결과는 /iac/<site>/03-database/rds 에 남깁니다 (접속 주소, 비밀 ARN).
#   03-compute와 같은 번호(병렬)라 서로의 값을 읽지 않습니다. DB 접근은 EC2 서브넷 대역으로 허용.
############################################################

locals {
  network_bundles = ["base", "subnets", "routing"]
}

# 민감 정보가 아닌 String 파라미터라 insecure_value로 읽습니다.
data "aws_ssm_parameter" "network" {
  for_each = toset(local.network_bundles)
  name     = "/iac/${var.site}/01-network/${each.key}"
}

data "aws_ssm_parameter" "bootstrap_kms" {
  name = "/iac/_account/00-bootstrap/kms"
}

locals {
  network = { for k, p in data.aws_ssm_parameter.network : k => jsondecode(p.insecure_value) }

  # RDS는 서브넷 그룹에 2개 AZ 이상 필요
  az_ok = length(local.network.base.azs) >= 2
}

module "rds_common" {
  source = "../deployment/rds-common"
  count  = length(var.rds) > 0 ? 1 : 0

  network                = local.network
  central_kms_key_arns   = var.central_kms_key_arns
  kms_key_administrators = var.kms_key_administrators
  protect_kms_keys       = local.protect.kms_keys
  common_tags            = var.common_tags
}

module "rds_db" {
  source   = "../deployment/rds-db"
  for_each = var.rds

  common           = module.rds_common[0].contract
  name             = "rds-${each.key}"
  logs_kms_key_arn = try(jsondecode(data.aws_ssm_parameter.bootstrap_kms.insecure_value).key_arns.logs, null)

  engine                = each.value.engine
  engine_version        = each.value.engine_version
  instance_class        = each.value.instance_class
  allocated_storage     = each.value.allocated_storage
  max_allocated_storage = each.value.max_allocated_storage
  db_name               = each.value.db_name
  username              = each.value.username
  port                  = each.value.port
  parameters            = each.value.parameters

  # 운영 모드면 Multi-AZ·삭제 보호 (DB별로 multi_az를 정하면 그 값)
  multi_az              = coalesce(each.value.multi_az, var.operation_mode == "enable")
  protect               = local.protect.rds
  backup_retention_days = each.value.backup_retention_days
  performance_insights  = each.value.performance_insights

  log_exports        = each.value.log_exports
  log_retention_days = each.value.log_retention_days
  allowed_cidrs      = each.value.allowed_cidrs

  snapshot_identifier = each.value.snapshot_identifier
  replicas            = each.value.replicas

  common_tags = var.common_tags
}

############################################################
# 다음 단계로 넘길 값 (/iac/<site>/03-database/rds)
############################################################
module "contract" {
  source = "../../aws-iac-terraform-module/module/management/aws-ssm-parameter-workload"
  count  = length(var.rds) > 0 ? 1 : 0

  path_prefix = "/iac/${var.site}/03-database"
  description = "03-database 묶음 (접속 주소, 비밀 ARN. 비밀번호 자체는 없음)"
  parameters = {
    rds = { for k, m in module.rds_db : k => m.db }
  }

  common_tags = var.common_tags
  site        = var.site
  stack       = "03-database"
  key_target  = "contract"
}

check "rds_needs_two_azs" {
  assert {
    condition     = length(var.rds) == 0 || local.az_ok
    error_message = "RDS는 2개 AZ 이상이 필요합니다 (01-network az_count >= 2)."
  }
}
