############################################################
# 공통 보안 그룹
# SSH / 서버 접근제어 같은 "서버 접근" 용도만 둡니다.
# 기본값은 규칙 없음. 고객사마다 다르므로 사이트 main.tf에서 common_sg_ingress로 추가합니다.
# 출발지는 prefix list 이름(prefix_lists)을 권장합니다. 01-network에서 만든 이름을 씁니다.
# 아웃바운드는 두지 않습니다. 인스턴스에 같이 붙는 개별 SG의 아웃바운드가 적용됩니다.
# 서비스 포트는 각 용도(ec2-was 등)의 개별 SG에 둡니다.
############################################################

module "common_sg" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload"

  name   = "${local.prefix}-sg"
  vpc_id = local.base.vpc_id
  default_security_group_rules = {
    ingress = [for r in var.common_sg_ingress : {
      from_port       = r.from_port
      to_port         = r.to_port
      protocol        = r.protocol
      cidr_blocks     = r.cidr_blocks
      security_groups = r.security_groups
      prefix_list_ids = r.prefix_lists == null ? null : [for n in r.prefix_lists : local.routing.prefix_list_ids[n]]
      description     = coalesce(r.description, "server access")
    }]
    egress = []
  }

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = local.key
}
