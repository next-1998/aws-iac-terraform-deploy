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

  precondition {
    condition     = length(module.sg_rules_csv.errors) == 0
    error_message = "${var.name}/src/sg_rules.csv 오류: ${join(" / ", module.sg_rules_csv.errors)}"
  }
}
