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
  value = module.shared_common.certificate_arn
}
