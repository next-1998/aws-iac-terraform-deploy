output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_id" {
  value = module.public_subnet[*].vpc_subnet.id
}

output "igw_id" {
  value = module.igw.igw_id
}

output "eip_id" {
  value = module.eip.eip_id
}

output "pub_nat_id" {
  value = module.pub_nat.nat_gw.id
}

output "pri_nat_id" {
  value = module.pri_nat.nat_gw.id
}

output "r53_record_zone_name" {
  value = module.r53_zones.route53_zone_name
}

output "r53_record_fqdn" {
  value = module.r53_records.route53_record_fqdn
} 

