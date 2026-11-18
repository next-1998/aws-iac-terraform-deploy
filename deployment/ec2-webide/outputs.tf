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
  value = var.enable_alb ? module.alb[0].elb.arn : null
}

output "target_group_arn" {
  value = var.enable_alb ? module.alb_tg[0].target_group_arn["app"] : null
}
