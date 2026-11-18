output "ec2_web_ide_lt_id" {
  description = "The ID of the AWS Launch Template."
  value       = aws_launch_template.ec2_web_ide.id
}

output "ec2_web_ide_lt_arn" {
  description = "The ARN of the AWS Launch Template."
  value       = aws_launch_template.ec2_web_ide.arn
}

output "ec2_web_ide_lt_latest_version" {
  description = "The latest version of the AWS Launch Template."
  value       = aws_launch_template.ec2_web_ide.latest_version
}