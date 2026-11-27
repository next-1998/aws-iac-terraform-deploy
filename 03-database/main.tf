############################################################
# 03-database
#   DB 유형 전체를 만듭니다 (state 하나).
#   - rds-common : DB 서브넷, 라우트, DB 서브넷 그룹, RDS 키 (1차 조합)
#   - rds-postgres / rds-mysql / rds-mariadb : 엔진 조합 (엔진 고정값·검사·CSV) → rds-core (파라미터 그룹, DB, 복제본, SG, 로그 그룹)
#   읽는 값: /iac/<site>/01-network/*, /iac/<site>/02-shared/shared (백업 플랜 목록), /iac/_account/00-bootstrap/kms (logs 키)
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

# 02-shared 값 (백업 플랜 목록: backup_plans 입력 검사)
data "aws_ssm_parameter" "shared" {
  name = "/iac/${var.site}/02-shared/shared"
}

data "aws_ssm_parameter" "bootstrap_kms" {
  name = "/iac/_account/00-bootstrap/kms"
}

locals {
  network = { for k, p in data.aws_ssm_parameter.network : k => jsondecode(p.insecure_value) }

  # 엔진과 관계없이 모든 DB (RDS + Aurora, DB 키 → 설정)
  all_dbs = merge(local.rds_postgres, local.rds_mysql, local.rds_mariadb, local.aurora_postgres, local.aurora_mysql) # tfvars + src/databases.csv
  any_db  = length(local.all_dbs) > 0

  # RDS는 서브넷 그룹에 2개 AZ 이상 필요
  az_ok = length(local.network.base.azs) >= 2

  logs_kms_key_arn = try(jsondecode(data.aws_ssm_parameter.bootstrap_kms.insecure_value).key_arns.logs, null)

  # 02-shared에 실제로 있는 백업 플랜 (backup_plans 입력 검사용). 백업을 끈 사이트는 빈 목록
  backup_plans_known   = keys(try(jsondecode(data.aws_ssm_parameter.shared.insecure_value).backup_tag_keys, {}))
  backup_plans_unknown = distinct([for p in flatten([for k, v in local.all_dbs : v.backup_plans]) : p if !contains(local.backup_plans_known, p)])
}

module "rds_common" {
  source = "../deployment/rds-common"
  count  = local.any_db ? 1 : 0

  network                = local.network
  subnet_cidrs           = var.db_subnet_cidrs # 비우면 01-network 배치 규칙. 01-network 공용 서브넷(use = db)이 있으면 그 서브넷
  central_kms_key_arns   = var.central_kms_key_arns
  kms_key_administrators = var.kms_key_administrators
  # 향상된 모니터링을 쓰는 DB가 있으면 역할 생성
  enable_enhanced_monitoring = anytrue([for k, v in local.all_dbs : v.monitoring_interval > 0])
  # NLB (rds_nlb가 있을 때만): 통합(shared)이면 공유 NLB. 대상 동기화 Lambda는 target_sync = "lambda"일 때만
  enable_nlb_sync  = try(var.rds_nlb.target_sync, "") == "lambda" && anytrue([for k, v in local.all_dbs : v.nlb != null])
  shared_nlb       = try(var.rds_nlb.mode, "") == "shared" && anytrue([for k, v in local.all_dbs : v.nlb != null]) ? { private_ips = var.rds_nlb.private_ips } : null
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
  for_each = local.rds_postgres

  common           = module.rds_common[0].contract
  name             = "rds-${each.key}"
  db               = merge(each.value, { nlb = var.rds_nlb == null || try(each.value.nlb.allowed_cidrs, null) == null ? null : merge(each.value.nlb, { mode = var.rds_nlb.mode, target_sync = var.rds_nlb.target_sync }) })
  multi_az         = coalesce(each.value.multi_az, var.operation_mode == "enable")
  protect          = local.protect.rds
  master_password  = lookup(var.rds_master_passwords, each.key, null)
  logs_kms_key_arn = local.logs_kms_key_arn
  common_tags      = var.common_tags
}

module "rds_mysql" {
  source   = "../deployment/rds-mysql"
  for_each = local.rds_mysql

  common           = module.rds_common[0].contract
  name             = "rds-${each.key}"
  db               = merge(each.value, { nlb = var.rds_nlb == null || try(each.value.nlb.allowed_cidrs, null) == null ? null : merge(each.value.nlb, { mode = var.rds_nlb.mode, target_sync = var.rds_nlb.target_sync }) })
  multi_az         = coalesce(each.value.multi_az, var.operation_mode == "enable")
  protect          = local.protect.rds
  master_password  = lookup(var.rds_master_passwords, each.key, null)
  logs_kms_key_arn = local.logs_kms_key_arn
  common_tags      = var.common_tags
}

module "rds_mariadb" {
  source   = "../deployment/rds-mariadb"
  for_each = local.rds_mariadb

  common           = module.rds_common[0].contract
  name             = "rds-${each.key}"
  db               = merge(each.value, { nlb = var.rds_nlb == null || try(each.value.nlb.allowed_cidrs, null) == null ? null : merge(each.value.nlb, { mode = var.rds_nlb.mode, target_sync = var.rds_nlb.target_sync }) })
  multi_az         = coalesce(each.value.multi_az, var.operation_mode == "enable")
  protect          = local.protect.rds
  master_password  = lookup(var.rds_master_passwords, each.key, null)
  logs_kms_key_arn = local.logs_kms_key_arn
  common_tags      = var.common_tags
}

############################################################
# Aurora 클러스터 (엔진 조합 → aurora-core). 항목은 RDS와 같은 이름
#   비밀번호는 RDS가 Secrets Manager로 관리 (읽기 인스턴스가 클러스터 안이라 rds_master_passwords 불필요)
############################################################
module "aurora_postgres" {
  source   = "../deployment/aurora-postgres"
  for_each = local.aurora_postgres

  common           = module.rds_common[0].contract
  name             = "rds-${each.key}"
  db               = merge(each.value, { nlb = var.rds_nlb == null || try(each.value.nlb.allowed_cidrs, null) == null ? null : merge(each.value.nlb, { mode = var.rds_nlb.mode, target_sync = var.rds_nlb.target_sync }) })
  multi_az         = coalesce(each.value.multi_az, var.operation_mode == "enable")
  protect          = local.protect.rds
  logs_kms_key_arn = local.logs_kms_key_arn
  common_tags      = var.common_tags
}

module "aurora_mysql" {
  source   = "../deployment/aurora-mysql"
  for_each = local.aurora_mysql

  common           = module.rds_common[0].contract
  name             = "rds-${each.key}"
  db               = merge(each.value, { nlb = var.rds_nlb == null || try(each.value.nlb.allowed_cidrs, null) == null ? null : merge(each.value.nlb, { mode = var.rds_nlb.mode, target_sync = var.rds_nlb.target_sync }) })
  multi_az         = coalesce(each.value.multi_az, var.operation_mode == "enable")
  protect          = local.protect.rds
  logs_kms_key_arn = local.logs_kms_key_arn
  common_tags      = var.common_tags
}

locals {
  # 엔진과 관계없이 DB 키 → 접속 정보 (다음 단계로 넘기는 값)
  rds_dbs = merge(
    { for k, m in module.rds_postgres : k => m.db },
    { for k, m in module.rds_mysql : k => m.db },
    { for k, m in module.rds_mariadb : k => m.db },
    { for k, m in module.aurora_postgres : k => m.db },
    { for k, m in module.aurora_mysql : k => m.db },
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
