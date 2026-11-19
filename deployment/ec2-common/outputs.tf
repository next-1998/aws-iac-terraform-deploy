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
    function_name = module.ws_lambda["this"].function_name
    schedules     = module.ws_schedule["this"].schedules
  } : null

  precondition {
    condition     = !var.enable_weekend_stop || contains(var.network.endpoints.interface, "ec2")
    error_message = "주말 중지 Lambda는 VPC 안에서 실행되므로 01-network의 interface_endpoints에 \"ec2\"가 필요합니다."
  }
}
