output "ec2_was_instance" {
  value = module.ec2_was.ec2_was_instance
}

output "ec2_was_private_ip" {
  value = module.ec2_was.ec2_was_private_ip
}

output "ec2_was_public_ip" {
  value = module.ec2_was.ec2_was_public_ip
} 

output "ec2_was_security_group_id" {
  value = module.ec2_was.ec2_was_security_group_id
}