output "was" {
  value = var.was.enabled ? {
    instance_id  = module.ec2_was[0].instance_id
    private_ip   = module.ec2_was[0].private_ip
    alb_dns_name = module.ec2_was[0].alb_dns_name
  } : null
}

output "webide" {
  value = var.webide.enabled ? {
    instance_id  = module.ec2_webide[0].instance_id
    private_ip   = module.ec2_webide[0].private_ip
    alb_dns_name = module.ec2_webide[0].alb_dns_name
  } : null
}

output "certificate_arn" {
  value = local.shared.certificate_arn
}

output "backup_plan_check" {
  description = "backup_plans 입력이 02-shared에 실제로 있는 플랜인지 (없는 이름이면 태그만 붙고 백업되지 않으므로 plan에서 막음)"
  value       = local.backup_plans_unknown

  precondition {
    condition     = length(local.backup_plans_unknown) == 0
    error_message = "02-shared에 없는 백업 플랜입니다: ${join(", ", local.backup_plans_unknown)}. 사용할 수 있는 플랜: ${length(local.backup_plans_known) == 0 ? "(없음: 02-shared enable_backup = false)" : join(", ", local.backup_plans_known)}"
  }
}
