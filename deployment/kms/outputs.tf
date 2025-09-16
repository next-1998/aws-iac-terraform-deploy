output "key_arn" {
  description = "The Amazon Resource Name (ARN) of the key" 
  value       =  module.kms.this.arn
}

output "key_id" {
  description = "The globally unique identifier for the key"
  value       = module.kms.this.key_id
}

output "key_region" {
  description = "The region for the key"
  value       = module.kms.this.region
}

output "aliases" {
  description = "A map of aliases created and their attributes"
  value       = module.kms.this.aliases
}