############################################################
# DB 보안 그룹 (보안 기본값 → 필요한 것만 추가)
#   1) 기본 규칙: DB 포트 ← allowed_cidrs (기본 EC2 서브넷 대역). 아웃바운드 없음 (DB가 먼저 연결하지 않음)
#   2) 사이트 규칙: src/<name>.sg_rules.csv (sg 열: db). 예: 사내망 DB 관리 도구 → pl:<이름>
############################################################
module "sg" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/security-group"

  name        = "${local.np}-sg-rds${local.db_key}-01"
  description = "${local.identifier} database (rules from ${var.src_label}/${var.name}.sg_rules.csv)"
  vpc_id      = local.base.vpc_id

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}

locals {
  sg_ids = { db = module.sg.securitygroup_id }

  sg_rules_csv_file = "${var.src_dir}/${var.name}.sg_rules.csv"
  sg_rules_csv      = var.sg_rules_csv != null ? var.sg_rules_csv : (fileexists(local.sg_rules_csv_file) ? file(local.sg_rules_csv_file) : "")

  base_ingress = {
    for c in local.allowed_cidrs : "base|db|${c}" => {
      security_group_id = module.sg.securitygroup_id
      ip_protocol       = "tcp"
      from_port         = local.port
      to_port           = local.port
      cidr_ipv4         = c
      description       = "database port from ${c}"
    }
  }
  # CSV에 같은 규칙이 있거나 한도를 넘으면 plan에서 막기 위해 서명·개수를 넘김
  base_signatures = [for c in local.allowed_cidrs : "db|ingress|tcp|${local.port}|${local.port}|cidr:${lower(c)}"]
  base_weights    = { "db|ingress" = length(local.allowed_cidrs) }
}

module "sg_rules_csv" {
  source              = "../../../aws-iac-terraform-module/module/_sg_rules_csv"
  base_signatures     = local.base_signatures
  base_weights        = local.base_weights
  prefix_list_weights = try(local.routing.prefix_list_max_entries, {})
  rule_limit          = var.sg_rule_limit
  source_name         = "${var.src_label}/${var.name}.sg_rules.csv"

  csv             = local.sg_rules_csv
  sg_ids          = local.sg_ids
  prefix_list_ids = local.routing.prefix_list_ids
}

module "sg_ingress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/ingress-rule"
  rules  = merge(local.base_ingress, module.sg_rules_csv.ingress)
}

module "sg_egress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/egress-rule"
  rules  = module.sg_rules_csv.egress
}

############################################################
# 복제본 SG (원본과 분리: NLB 쓰기 대상 그룹에 복제본 IP가 섞이지 않도록)
#   기본 규칙: DB 포트 ← allowed_cidrs (원본과 같음). CSV 규칙은 원본 SG(db)에만 적용
############################################################
module "sg_ro" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/security-group"
  count  = length(var.replicas) > 0 ? 1 : 0

  name        = "${local.np}-sg-rds${local.db_key}ro-01"
  description = "${local.identifier} read replicas"
  vpc_id      = local.base.vpc_id

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_ro"
}

module "sg_ro_ingress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/ingress-rule"
  rules = length(var.replicas) == 0 ? {} : {
    for c in local.allowed_cidrs : "base|ro|${c}" => {
      security_group_id = module.sg_ro[0].securitygroup_id
      ip_protocol       = "tcp"
      from_port         = local.port
      to_port           = local.port
      cidr_ipv4         = c
      description       = "database port from ${c}"
    }
  }
}
