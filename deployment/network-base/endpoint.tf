############################################################
# VPC endpoint (모든 유형이 같이 씀)
#   인터페이스 endpoint: vpce 서브넷, private DNS 사용 (VPC DNS 설정은 vpc 모듈에서 켜 둠)
#   Gateway endpoint  : 여기서 endpoint만 만들고, 라우트 테이블 연결은 각 <유형>-common이 합니다.
#   skip_if_exists    : 다른 state(수동 생성 등)가 같은 endpoint를 이미 만들었으면 생성하지 않음
############################################################

locals {
  endpoint_map = merge(
    { for s in var.interface_endpoints : s => { service = s, service_type = "Interface", route_table_ids = null, private_dns_enabled = true } },
    { for s in var.gateway_endpoints : s => { service = s, service_type = "Gateway", route_table_ids = null, private_dns_enabled = null } },
  )
}

module "vpce_sg" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/security-group"
  count  = length(var.interface_endpoints) > 0 ? 1 : 0

  name        = "${var.name_prefix}-sg-vpce-01"
  description = "interface endpoints (HTTPS from VPC)"
  vpc_id      = module.vpc.vpc.id

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "vpce"
}

module "vpce_sg_ingress" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload/ingress-rule"
  rules = length(var.interface_endpoints) == 0 ? {} : {
    for c in local.vpc_cidrs : "vpc|${c}" => {
      security_group_id = module.vpce_sg[0].securitygroup_id
      ip_protocol       = "tcp"
      from_port         = 443
      to_port           = 443
      cidr_ipv4         = c
      description       = "HTTPS from VPC"
    }
  }
}

module "vpce" {
  source = "../../../aws-iac-terraform-module/module/network/aws-vpce-workload"
  count  = length(local.endpoint_map) > 0 ? 1 : 0

  name               = "${var.name_prefix}-vpce"
  name_suffix        = "-01"
  vpc_id             = module.vpc.vpc.id
  endpoints          = local.endpoint_map
  subnet_ids         = [for az in local.layout_azs : local.subnet_ids.vpce[az]]
  security_group_ids = length(var.interface_endpoints) > 0 ? [module.vpce_sg[0].securitygroup_id] : []
  skip_if_exists     = var.endpoint_skip_if_exists

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
}

locals {
  # 서비스 이름 → endpoint ID (이 state가 만든 것 + skip된 기존 것)
  endpoint_ids = length(local.endpoint_map) > 0 ? merge(module.vpce[0].existing_ids, module.vpce[0].vpce_ids) : {}
}
