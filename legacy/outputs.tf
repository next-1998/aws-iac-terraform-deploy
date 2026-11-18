# output "vpc_igw_id" {
#   value = module.vpc_igw.vpc_igw.id
# }

# output "vpc_nat_id" {
#   value = {for k, v in module.vpc_natgw.vpc_nat : k => v.id}
# }