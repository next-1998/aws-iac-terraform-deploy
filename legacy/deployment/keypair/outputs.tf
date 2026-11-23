output "local_private_key" {
  description = "The private key"
  value       = module.keypair_local.private_key
}

output "local_public_key" {
  description = "The public key"
  value       = module.keypair_local.public_key
}

output "service_private_key" {
  description = "The private key"
  value       = module.keypair_service.private_key
}

output "service_public_key" {
  description = "The public key"
  value       = module.keypair_service.public_key
}