# ec2-<용도> stack들이 받는 표준 입력 묶음
output "contract" {
  description = "ec2-common → ec2-<용도> 표준 연결 값"

  # EC2는 CloudWatch Agent(지표·로그)가 필수입니다. 워크로드는 private 기본이라 logs, monitoring endpoint가 있어야 전송됩니다 (public 사용 여부와 무관).
  precondition {
    condition     = length(setsubtract(["logs", "monitoring"], var.network.endpoints.interface)) == 0
    error_message = "EC2 CloudWatch Agent용 VPC endpoint가 없습니다: ${join(", ", setsubtract(["logs", "monitoring"], var.network.endpoints.interface))}. 01-network의 interface_endpoints에 추가하세요."
  }
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

    # 로그 그룹 암호화 CMK (00-bootstrap의 logs 키). ec2-<용도>가 Agent 로그 그룹에 씀
    logs_kms_key_arn = var.logs_kms_key_arn

    # EBS 자동 증설 (켜지 않으면 lambda_arn = null). ec2-<용도>가 알람 이름·태그에 씀
    ebs_grow = {
      enabled    = var.enable_ebs_auto_grow
      lambda_arn = try(module.eg_lambda["this"].arn, null)
      tag_key    = local.eg_tag
      alarm_mark = local.eg_alarm_mark
    }
  }
}

output "ebs_grow" {
  description = "EBS 자동 증설 Lambda (켜지 않으면 null)"
  value       = try(module.eg_lambda["this"].function_name, null)

  # Lambda는 VPC endpoint로만 AWS API를 호출 (public 사용 여부와 무관)
  precondition {
    condition     = !var.enable_ebs_auto_grow || length(local.eg_missing_endpoints) == 0
    error_message = "EBS 자동 증설 Lambda용 VPC endpoint가 없습니다: ${join(", ", local.eg_missing_endpoints)}. 01-network의 interface_endpoints에 추가하세요."
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

output "sg_rules" {
  description = "CSV에서 읽어 적용한 SG 규칙 (src/sg_rules.csv)"
  value = {
    ingress = module.sg_ingress.rules
    egress  = module.sg_egress.rules
  }
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
