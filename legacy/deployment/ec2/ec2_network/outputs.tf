output "pri_subnet_ids" { 
  value = module.private_subnet[*].id
}