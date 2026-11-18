output "subnet_ids" { 
  value = module.rds_subnet[*].id
}

output "rds_subnet_group_name" {
  value = module.rds_subnet_group.name
}
