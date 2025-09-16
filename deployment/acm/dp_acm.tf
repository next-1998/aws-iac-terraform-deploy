locals {
  root_domain = var.root_domain
}

module "acm" {
  source = "${var.module_repo_url}//module/security/aws-acm-workload/acm"

  domain_name               = "${var.cluster_name}.${local.root_domain}"
  subject_alternative_names = ["*.${var.cluster_name}.${local.root_domain}"]
  zone_id                   =  lookup(module.zones.route53_zone_zone_id, keys(module.zones.route53_zone_zone_id)[0])
}

module "acm_validation" {
  source = "${var.module_repo_url}//module/security/aws-acm-workload/acm_validation"

  r53_record = {
    zone_id = module.r53_zones.route53_zone_zone_id
    acm_certificate_domain_validation_options = module.acm.acm_certificate_domain_validation_options
    allow_overwrite = true
    ttl = 60
  }
  acm_validation = {
    certificate_arn = module.acm.acm_certificate_arn
  }
}



//메인 VPC 구성에 적용
