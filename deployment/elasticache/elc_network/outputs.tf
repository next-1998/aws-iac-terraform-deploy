output "cache_subnet_ids" { 
  value = module.cache_subnet[*].id
}

output "cache_subnet_group_name" {
  value = module.cache_subnet_group.name
}
