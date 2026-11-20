output "lambda_policy_arn" {
  value = module.start_stop_ec2_rds_policy.arn
}

output "lambda_role_arn" {
  value = module.lambda_role.arn
}

output "lambda_function" {
  value = module.start_stop_ec2_rds_lambda
}
