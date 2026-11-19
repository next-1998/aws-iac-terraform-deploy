############################################################
# 공통 보안 그룹 (서버 접근 전용: SSH, 서버 접근제어 솔루션 등)
#   SG는 규칙 없이 만들고, 규칙은 src/sg_rules.csv에서 읽어 추가합니다 (보안 기본값 → 필요한 것만 추가).
#   CSV의 sg 열: common
#   아웃바운드는 두지 않습니다. 인스턴스에 같이 붙는 개별 SG(ec2-<용도>)의 아웃바운드가 적용됩니다.
#   서비스 포트는 각 용도(ec2-was 등)의 개별 SG에 둡니다.
############################################################

module "common_sg" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/security-group"

  name        = "${local.prefix}-sg"
  description = "server access (rules from ec2-common/src/sg_rules.csv)"
  vpc_id      = local.base.vpc_id

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}

locals {
  # 테스트 등에서 내용을 직접 넘기면(var.sg_rules_csv) 그 값을, 아니면 src/sg_rules.csv를 읽음
  sg_rules_csv_file = "${path.module}/src/sg_rules.csv"
  sg_rules_csv      = var.sg_rules_csv != null ? var.sg_rules_csv : (fileexists(local.sg_rules_csv_file) ? file(local.sg_rules_csv_file) : "")

  # CSV의 sg 열에 쓸 수 있는 이름 (이 폴더에서 만드는 SG)
  sg_ids = { common = module.common_sg.securitygroup_id }
}

module "sg_rules_csv" {
  source = "../../../aws-iac-terraform-module/module/_sg_rules_csv"

  csv             = local.sg_rules_csv
  sg_ids          = local.sg_ids
  prefix_list_ids = local.routing.prefix_list_ids

  # 공통 SG는 기본 규칙이 없으므로 한도만 검사
  prefix_list_weights = try(local.routing.prefix_list_max_entries, {})
  rule_limit          = var.sg_rule_limit
}

module "sg_ingress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/ingress-rule"
  rules  = module.sg_rules_csv.ingress
}

module "sg_egress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/egress-rule"
  rules  = module.sg_rules_csv.egress
}
