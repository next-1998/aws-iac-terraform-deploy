############################################################
# VPC endpoint
# enable_ssm = true 이면 ssm, ssmmessages, ec2messages + endpoints(추가)
# 같은 VPC에 다른 stack이 만든 endpoint가 있으면 skip (vpce 모듈 skip_if_exists)
# 같은 apply 안의 stack 간 중복은 main.tf에서 endpoints 목록을 나눠서 막습니다.
############################################################

locals {
  gateway_services = ["s3", "dynamodb"]
  ssm_services     = ["ssm", "ssmmessages", "ec2messages"]

  # SSM 사용 시 SSM endpoint + 추가 endpoint
  endpoint_services = distinct(concat(var.enable_ssm ? local.ssm_services : [], var.endpoints))

  # Gateway / Interface 모두 같은 속성을 갖게 하고, 해당 없는 값은 null
  endpoints = {
    for svc in local.endpoint_services : svc => {
      service             = svc
      service_type        = contains(local.gateway_services, svc) ? "Gateway" : "Interface"
      route_table_ids     = contains(local.gateway_services, svc) ? [for az in local.azs : module.rt[az].vpc_rt.id] : null
      private_dns_enabled = contains(local.gateway_services, svc) ? null : true
    }
  }

  has_interface = length([for s in local.endpoint_services : s if !contains(local.gateway_services, s)]) > 0
}

module "vpce_sg" {
  source = "../../../aws-iac-terraform-module/module/security/aws-securitygroup-workload"
  count  = local.has_interface ? 1 : 0

  name   = "${local.prefix}-vpce-sg"
  vpc_id = var.base.vpc_id
  default_security_group_rules = {
    ingress = [{
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = var.base.vpc_cidrs
      description = "HTTPS from VPC"
    }]
    egress = []
  }

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_vpce"
}

module "vpce" {
  source = "../../../aws-iac-terraform-module/module/network/aws-vpce-workload"
  count  = length(local.endpoint_services) > 0 ? 1 : 0

  name               = "${local.site}-vpce"
  vpc_id             = var.base.vpc_id
  endpoints          = local.endpoints
  subnet_ids         = [for az in local.azs : module.subnet[az].vpc_subnet[0].id]
  security_group_ids = local.has_interface ? [module.vpce_sg[0].securitygroup_id] : []
  skip_if_exists     = true

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
}

# 다른 stack이 만든 Gateway endpoint(s3 등)에 이 stack의 AZ별 라우트 테이블을 모두 연결
resource "aws_vpc_endpoint_route_table_association" "shared_gateway" {
  for_each = length(local.endpoint_services) > 0 ? merge([
    for svc, id in module.vpce[0].existing_ids : {
      for az in local.azs : "${svc}-${az}" => { endpoint_id = id, az = az }
    } if contains(local.gateway_services, svc)
  ]...) : {}

  vpc_endpoint_id = each.value.endpoint_id
  route_table_id  = module.rt[each.value.az].vpc_rt.id
}
