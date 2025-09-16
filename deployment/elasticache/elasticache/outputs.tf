output "elasticache_id" {
  value = module.elasticache[0].elasticache_id
}

output "elasticache_endpoint" {
  value = module.elasticache[0].elasticache_endpoint
}

output "elasticache_port" {
  value = module.elasticache[0].elasticache_port
}

output "elasticache_subnet_group_name" {
  value = module.elasticache[0].elasticache_subnet_group_name
}

output "elasticache_security_group_id" {
  value = module.elasticache[0].elasticache_security_group_id
}