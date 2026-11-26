############################################################
# 보안 그룹 (보안 기본값 → 필요한 것만 추가)
#   SG는 규칙 없이 만들고, 규칙은 두 곳에서 붙입니다.
#   1) 기본 규칙 (이 파일): 서비스 동작에 꼭 필요한 최소 규칙
#      app 인바운드 : ALB → app_port (ALB를 켠 경우)
#      app 아웃바운드: VPC 대역 전체, S3/DynamoDB gateway endpoint(443)
#      alb 인바운드 : 80/443 ← alb_ingress_cidrs 또는 alb_ingress_prefix_lists
#      alb 아웃바운드: app_port → EC2 서브넷
#   2) 사이트 규칙 (src/sg_rules.csv): 고객사와 협의한 추가 규칙
#      CSV의 sg 열: app (서버 SG), alb (ALB SG). 대상 sg:common 은 ec2-common 공통 SG
#   서버 접근(SSH 등)은 ec2-common의 공통 SG가 담당합니다.
############################################################

data "aws_region" "current" {}

# gateway endpoint(S3, DynamoDB)의 AWS 관리형 prefix list
data "aws_prefix_list" "gateway" {
  for_each = toset(keys(var.common.network.endpoints.gateway))
  name     = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
}

module "sg" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/security-group"

  name        = "${local.np}-sg-${local.purpose}-01"
  description = "${local.prefix} service (rules from ${var.name}/src/sg_rules.csv)"
  vpc_id      = local.base.vpc_id

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}

locals {
  # CSV의 sg 열에 쓸 수 있는 이름 (이 폴더에서 만드는 SG)
  sg_ids = merge(
    { app = module.sg.securitygroup_id },
    var.enable_alb ? { alb = module.alb_sg[0].securitygroup_id } : {},
  )

  # 테스트 등에서 내용을 직접 넘기면(var.sg_rules_csv) 그 값을, 아니면 src/sg_rules.csv를 읽음
  sg_rules_csv_file = "${path.module}/src/sg_rules.csv"
  sg_rules_csv      = var.sg_rules_csv != null ? var.sg_rules_csv : (fileexists(local.sg_rules_csv_file) ? file(local.sg_rules_csv_file) : "")

  # ALB 인바운드 출발지: prefix list를 주고 CIDR을 따로 주지 않았으면 prefix list만
  alb_src_cidrs = length(var.alb_ingress_prefix_lists) > 0 && var.alb_ingress_cidrs == null ? [] : local.alb_ingress_cidrs

  base_ingress = merge(
    var.enable_alb ? {
      "base|app|alb" = {
        security_group_id            = module.sg.securitygroup_id
        ip_protocol                  = "tcp"
        from_port                    = var.app_port
        to_port                      = var.app_port
        referenced_security_group_id = module.alb_sg[0].securitygroup_id
        description                  = "from ${local.prefix} ALB"
      }
    } : {},
    { for pair in setproduct(var.enable_alb ? local.alb_ports : [], local.alb_src_cidrs) : "base|alb|${pair[0]}|${pair[1]}" => {
      security_group_id = module.alb_sg[0].securitygroup_id
      ip_protocol       = "tcp"
      from_port         = pair[0]
      to_port           = pair[0]
      cidr_ipv4         = pair[1]
      description       = "HTTP(S) to ALB"
    } },
    { for pair in setproduct(var.enable_alb ? local.alb_ports : [], var.alb_ingress_prefix_lists) : "base|alb|${pair[0]}|pl:${pair[1]}" => {
      security_group_id = module.alb_sg[0].securitygroup_id
      ip_protocol       = "tcp"
      from_port         = pair[0]
      to_port           = pair[0]
      prefix_list_id    = local.routing.prefix_list_ids[pair[1]]
      description       = "HTTP(S) to ALB"
    } },
  )

  base_egress = merge(
    { for c in local.base.vpc_cidrs : "base|app|vpc|${c}" => {
      security_group_id = module.sg.securitygroup_id
      ip_protocol       = "-1"
      cidr_ipv4         = c
      description       = "to VPC"
    } },
    { for k, p in data.aws_prefix_list.gateway : "base|app|gateway|${k}" => {
      security_group_id = module.sg.securitygroup_id
      ip_protocol       = "tcp"
      from_port         = 443
      to_port           = 443
      prefix_list_id    = p.id
      description       = "to ${k} gateway endpoint"
    } },
    { for c in var.enable_alb ? values(var.common.subnet_cidrs) : [] : "base|alb|ec2|${c}" => {
      security_group_id = module.alb_sg[0].securitygroup_id
      ip_protocol       = "tcp"
      from_port         = var.app_port
      to_port           = var.app_port
      cidr_ipv4         = c
      description       = "to ${local.prefix} EC2"
    } },
  )
}

locals {
  # 기본 규칙의 서명(<sg>|<방향>|<프로토콜>|<from>|<to>|<대상>)과 한도 가중치
  #   CSV에 같은 규칙이 있거나 SG 규칙 한도를 넘으면 plan에서 막기 위해 helper에 넘김
  pl_weights = try(local.routing.prefix_list_max_entries, {})
  base_meta = concat(
    var.enable_alb ? [{ sig = "app|ingress|tcp|${var.app_port}|${var.app_port}|sg:alb", w = 1 }] : [],
    [for pair in setproduct(var.enable_alb ? local.alb_ports : [], local.alb_src_cidrs) : { sig = "alb|ingress|tcp|${pair[0]}|${pair[0]}|cidr:${lower(pair[1])}", w = 1 }],
    [for pair in setproduct(var.enable_alb ? local.alb_ports : [], var.alb_ingress_prefix_lists) : { sig = "alb|ingress|tcp|${pair[0]}|${pair[0]}|pl:${lower(pair[1])}", w = lookup(local.pl_weights, pair[1], 1) }],
    [for c in local.base.vpc_cidrs : { sig = "app|egress|-1|||cidr:${lower(c)}", w = 1 }],
    # AWS 관리형 S3/DynamoDB prefix list는 규칙 1개로 계산
    [for k, p in data.aws_prefix_list.gateway : { sig = "app|egress|tcp|443|443|pl:${lower(p.id)}", w = 1 }],
    [for c in var.enable_alb ? values(var.common.subnet_cidrs) : [] : { sig = "alb|egress|tcp|${var.app_port}|${var.app_port}|cidr:${lower(c)}", w = 1 }],
  )
  base_signatures = [for m in local.base_meta : m.sig]
  base_weights = {
    for k, ws in { for m in local.base_meta : join("|", slice(split("|", m.sig), 0, 2)) => m.w... } : k => sum(ws)
  }
}

module "sg_rules_csv" {
  source              = "../../../aws-iac-terraform-module/module/_sg_rules_csv"
  base_signatures     = local.base_signatures
  base_weights        = local.base_weights
  prefix_list_weights = local.pl_weights
  rule_limit          = var.sg_rule_limit
  source_name         = "${var.name}/src/sg_rules.csv"

  csv    = local.sg_rules_csv
  sg_ids = local.sg_ids
  # sg:<이름>으로 참조할 수 있는 다른 SG: 공통 SG + 같은 단계 다른 용도 SG(<용도>.<sg>, 03-compute가 넘김)
  source_sg_ids   = merge(var.peer_sg_ids, { common = var.common.common_sg_id })
  prefix_list_ids = local.routing.prefix_list_ids
}

module "sg_ingress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/ingress-rule"
  rules  = merge(local.base_ingress, module.sg_rules_csv.ingress)
}

module "sg_egress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/egress-rule"
  rules  = merge(local.base_egress, module.sg_rules_csv.egress)
}
