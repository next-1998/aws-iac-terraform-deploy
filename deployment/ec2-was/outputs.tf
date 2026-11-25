output "instance_id" {
  value = module.ec2.ec2_instance.id
}

output "private_ip" {
  value = module.ec2.ec2_instance.private_ip
}

output "sg_id" {
  description = "개별 SG ID (다른 stack에서 이 서버로의 접근을 허용할 때 main.tf가 넘겨줌)"
  value       = module.sg.securitygroup_id
}

output "security_group_ids" {
  description = "인스턴스에 붙은 SG (공통 SG, 개별 SG)"
  value       = module.ec2.ec2_instance.vpc_security_group_ids
}

output "role_arn" {
  value = module.role.arn
}

output "alb_dns_name" {
  value = var.enable_alb ? module.alb[0].elb.dns_name : null
}

output "alb_zone_id" {
  value = var.enable_alb ? module.alb[0].elb.zone_id : null
}

output "alb_arn" {
  # 검증: ALB는 AZ 2개 이상, 외부용 ALB는 01-network enable_public = true
  precondition {
    condition     = !var.enable_alb || length(local.alb_subnet_ids) >= 2
    error_message = "ALB는 AZ 2개 이상이 필요합니다. 현재 사용 가능한 서브넷 ${length(local.alb_subnet_ids)}개 (01-network의 az_count를 2 이상으로 하거나 enable_alb = false)."
  }
  precondition {
    condition     = !var.enable_alb || var.alb_internal || local.network.routing.has_public
    error_message = "외부용 ALB(alb_internal = false)는 01-network의 enable_public = true가 필요합니다. public을 끈 사이트는 인터넷을 쓰지 않습니다."
  }

  value = var.enable_alb ? module.alb[0].elb.arn : null
}

output "target_group_arn" {
  value = var.enable_alb ? module.alb_tg[0].target_group_arn["app"] : null
}

output "sg_rules" {
  description = "적용한 SG 규칙 (기본 규칙 + src/sg_rules.csv)"
  value = {
    ingress = module.sg_ingress.rules
    egress  = module.sg_egress.rules
  }
}

output "agent_log_groups" {
  description = "CloudWatch Agent 설정에 쓸 로그 그룹 이름 (이름 → 로그 그룹)"
  value       = { for k, m in module.agent_log : k => m.name }
}

output "sg_base_rules" {
  description = "코드에 있는 기본 SG 규칙 (<sg>|<방향>|<프로토콜>|<from>|<to>|<대상>). CSV에 같은 규칙을 넣으면 plan에서 막힘"
  value       = local.base_signatures
}

output "cloudwatch_agent" {
  description = "CloudWatch Agent 설정 (SSM 연결 이름 → ID). 비어 있으면 Agent 설정을 하지 않음"
  value       = module.cwagent.association_ids
}

output "data_volumes" {
  description = "데이터 볼륨 (장치 이름 → 볼륨 ID, 마운트 경로)"
  value       = { for k, v in local.data_volumes : k => { volume_id = module.data_volume[k].id, mount_point = v.mount_point } }
}

output "volume_mount" {
  description = "데이터 볼륨 마운트 (SSM 연결 이름 → ID). 비어 있으면 마운트할 볼륨 없음"
  value       = module.volume_mount.association_ids
}

output "sg_ids" {
  description = "이 용도에서 만든 SG (sg_rules.csv의 sg 이름 → ID: app, alb). 03-compute가 다른 용도에 <용도>.<이름>으로 넘김"
  value       = local.sg_ids
}
