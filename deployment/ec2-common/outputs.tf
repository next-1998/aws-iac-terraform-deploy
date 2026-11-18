# ec2-<용도> stack들이 받는 표준 입력 묶음
output "contract" {
  description = "ec2-common → ec2-<용도> 표준 연결 값"
  value = {
    # network-base 정보 (ec2-<용도>가 VPC, ALB 서브넷, DNS 등에 사용)
    base = var.base

    # EC2 공통 네트워크
    subnet_ids      = { for az in local.azs : az => module.subnet[az].vpc_subnet[0].id }
    subnet_cidrs    = local.subnets
    cidr_block      = local.block
    route_table_ids = { for az in local.azs : az => module.rt[az].vpc_rt.id }

    # 공통 SG (서버 접근용)
    common_sg_id = module.common_sg.securitygroup_id

    # 인스턴스가 만들어지기 전에 준비돼야 하는 리소스 (endpoint, 라우팅)
    # ec2-<용도>는 이 값을 참조해서 생성 순서를 맞춥니다.
    ready = {
      endpoints = length(local.endpoint_services) > 0 ? module.vpce[0].vpce_ids : {}
      internet  = flatten([for k, m in module.rt_internet : m.route_ids])
      corp      = flatten([for k, m in module.rt_corp : m.route_ids])
    }
  }
}

output "endpoints_created" {
  description = "이 stack이 만든 endpoint (키: 서비스 이름)"
  value       = length(local.endpoint_services) > 0 ? module.vpce[0].vpce_ids : {}
}

output "endpoints_skipped" {
  description = "다른 stack이 이미 만들어서 skip한 endpoint"
  value       = length(local.endpoint_services) > 0 ? module.vpce[0].skipped : []
}

output "subnet_cidrs" {
  value = local.subnets
}

output "route_table_ids" {
  value = { for az in local.azs : az => module.rt[az].vpc_rt.id }
}

output "common_sg_id" {
  value = module.common_sg.securitygroup_id
}

output "common_sg_ingress_rules" {
  description = "공통 SG에 들어간 인바운드 규칙 (기본값: 없음)"
  value       = module.common_sg.securitygroup.ingress
}
