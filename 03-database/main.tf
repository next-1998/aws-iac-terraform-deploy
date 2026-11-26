############################################################
# 03-database
#   DB 유형 전체를 만듭니다 (state 하나).
#   - rds-common : DB 서브넷, 라우트, DB 서브넷 그룹, RDS 키 (1차 조합)
#   - rds-postgres / rds-mysql / rds-mariadb : 엔진 조합 (엔진 고정값·검사·CSV) → rds-core (파라미터 그룹, DB, 복제본, SG, 로그 그룹)
#   읽는 값: /iac/<site>/01-network/*, /iac/_account/00-bootstrap/kms (logs 키)
#   결과는 /iac/<site>/03-database/rds 에 남깁니다 (접속 주소, 비밀 ARN).
#   03-compute와 같은 번호(병렬)라 서로의 값을 읽지 않습니다. DB 접근은 EC2 서브넷 대역으로 허용.
############################################################

locals {
  network_bundles = ["base", "subnets", "routing", "endpoints"]
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

  # 엔진과 관계없이 모든 DB (DB 키 → 설정)
  all_dbs = merge(var.rds_postgres, var.rds_mysql, var.rds_mariadb)
  any_db  = length(local.all_dbs) > 0

  # RDS는 서브넷 그룹에 2개 AZ 이상 필요
  az_ok = length(local.network.base.azs) >= 2

  logs_kms_key_arn = try(jsondecode(data.aws_ssm_parameter.bootstrap_kms.insecure_value).key_arns.logs, null)
}

module "rds_common" {
  source = "../deployment/rds-common"
  count  = local.any_db ? 1 : 0

  network                = local.network
  central_kms_key_arns   = var.central_kms_key_arns
  kms_key_administrators = var.kms_key_administrators
  # 향상된 모니터링을 쓰는 DB가 있으면 역할 생성
  enable_enhanced_monitoring = anytrue([for k, v in local.all_dbs : v.monitoring_interval > 0])
  # NLB: 쓰는 DB가 있으면 대상 동기화 Lambda, shared를 쓰는 DB가 있으면 공유 NLB
  enable_nlb_sync  = anytrue([for k, v in local.all_dbs : v.nlb != null])
  shared_nlb       = anytrue([for k, v in local.all_dbs : try(v.nlb.mode, "") == "shared"]) ? var.rds_shared_nlb : null
  protect_nlb      = local.protect.rds
  logs_kms_key_arn = local.logs_kms_key_arn
  protect_kms_keys = local.protect.kms_keys
  common_tags      = var.common_tags
}

############################################################
# 엔진별 DB (엔진 조합 → rds-core)
#   운영 모드면 Multi-AZ·삭제 보호 (DB별로 multi_az를 정하면 그 값)
#   비밀번호: rds_master_passwords에 있으면 평문, 없으면 RDS가 Secrets Manager로 관리
############################################################
module "rds_postgres" {
  source   = "../deployment/rds-postgres"
  for_each = var.rds_postgres

  common           = module.rds_common[0].contract
  name             = "rds-${each.key}"
  db               = each.value
  multi_az         = coalesce(each.value.multi_az, var.operation_mode == "enable")
  protect          = local.protect.rds
  master_password  = lookup(var.rds_master_passwords, each.key, null)
  logs_kms_key_arn = local.logs_kms_key_arn
  common_tags      = var.common_tags
}

module "rds_mysql" {
  source   = "../deployment/rds-mysql"
  for_each = var.rds_mysql

  common           = module.rds_common[0].contract
  name             = "rds-${each.key}"
  db               = each.value
  multi_az         = coalesce(each.value.multi_az, var.operation_mode == "enable")
  protect          = local.protect.rds
  master_password  = lookup(var.rds_master_passwords, each.key, null)
  logs_kms_key_arn = local.logs_kms_key_arn
  common_tags      = var.common_tags
}

module "rds_mariadb" {
  source   = "../deployment/rds-mariadb"
  for_each = var.rds_mariadb

  common           = module.rds_common[0].contract
  name             = "rds-${each.key}"
  db               = each.value
  multi_az         = coalesce(each.value.multi_az, var.operation_mode == "enable")
  protect          = local.protect.rds
  master_password  = lookup(var.rds_master_passwords, each.key, null)
  logs_kms_key_arn = local.logs_kms_key_arn
  common_tags      = var.common_tags
}

locals {
  # 엔진과 관계없이 DB 키 → 접속 정보 (다음 단계로 넘기는 값)
  rds_dbs = merge(
    { for k, m in module.rds_postgres : k => m.db },
    { for k, m in module.rds_mysql : k => m.db },
    { for k, m in module.rds_mariadb : k => m.db },
  )
}

############################################################
# 다음 단계로 넘길 값 (/iac/<site>/03-database/rds)
############################################################
module "contract" {
  source = "../../aws-iac-terraform-module/module/management/aws-ssm-parameter-workload"
  count  = local.any_db ? 1 : 0

  path_prefix = "/iac/${var.site}/03-database"
  description = "03-database 묶음 (접속 주소, 비밀 ARN. 비밀번호 자체는 없음)"
  parameters = {
    rds = local.rds_dbs
  }

  common_tags = var.common_tags
  site        = var.site
  stack       = "03-database"
  key_target  = "contract"
}

check "rds_needs_two_azs" {
  assert {
    condition     = !local.any_db || local.az_ok
    error_message = "RDS는 2개 AZ 이상이 필요합니다 (01-network az_count >= 2)."
  }
}
