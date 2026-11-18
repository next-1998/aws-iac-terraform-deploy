# ec2-<용도> stack들이 받는 표준 입력 묶음
output "contract" {
  description = "ec2-common → ec2-<용도> 표준 연결 값"
  value = {
    # 01-network contract (VPC, edge/public 서브넷, DNS, prefix list 등)
    network = var.network

    # EC2 공통 네트워크
    subnet_ids      = { for az in local.azs : az => module.subnet[az].vpc_subnet[0].id }            # 표준 (AZ → ID)
    manual_subnets  = { for k, s in local.manual_subnets : k => module.subnet[k].vpc_subnet[0].id } # 수동 (이름 → ID)
    subnet_cidrs    = { for k, s in local.all_subnets : k => s.cidr }
    route_table_ids = { for az in local.azs : az => module.rt[az].vpc_rt.id }

    # 공통 SG (서버 접근용)
    common_sg_id = module.common_sg.securitygroup_id

    # 인스턴스가 만들어지기 전에 준비돼야 하는 라우팅 (생성 순서 고정용)
    ready = {
      internet = flatten([for k, m in module.rt_internet : m.route_ids])
      corp     = flatten([for k, m in module.rt_corp : m.route_ids])
      gateway  = [for k, a in aws_vpc_endpoint_route_table_association.gateway : a.id]
    }
  }
}

output "subnet_cidrs" {
  value = { for k, s in local.all_subnets : k => s.cidr }
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

output "weekend_stop" {
  description = "주말 중지 Lambda와 스케줄 상태 (켜지 않았으면 null)"
  value = var.enable_weekend_stop ? {
    function_name = module.weekend_stop[0].function_name
    schedules     = module.weekend_stop[0].schedules
  } : null
}
