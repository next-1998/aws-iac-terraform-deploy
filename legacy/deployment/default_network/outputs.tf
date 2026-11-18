output "vpc_id" {
  value = module.vpc.vpc.id
}

output "public_subnet_ids" {
  value = module.public_subnet[*].vpc_subnet.id
}

output "private_subnet_ids" {
  value = module.private_subnet[*].vpc_subnet.id
}

output "igw_id" {
  value = module.igw.vpc_igw.id
}

output "eip_id" {
  value = module.eip.vpc_eip.id
}

output "pub_nat_id" {
  value = module.pub_nat.vpc_nat.id
}

output "pri_nat_id" {
  value = module.pri_nat.vpc_nat.id
}

output "route53_zone_zone_id"{
  value = module.r53_zones.route53_zone_zone_id
}

