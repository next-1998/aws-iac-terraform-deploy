output "was_alb_arn" {
  value = module.was_alb.elb.arn
}

output "web_ide_alb_arn" {
  value = module.web_ide_alb.elb.arn
}

output "was_alb_dns_name" {
  value = module.was_alb.elb.dns_name
}

output "web_ide_alb_dns_name" {
  value = module.web_ide_alb.elb.dns_name
}