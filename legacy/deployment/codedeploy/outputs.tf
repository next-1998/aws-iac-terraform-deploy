output "module_codedeploy_service_role" {
  value = module.codedeploy_service_role.arn
}

output "codedeploy_arn" {
  value = module.codedeploy.arn
}