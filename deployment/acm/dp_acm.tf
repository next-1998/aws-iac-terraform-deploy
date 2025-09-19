locals {
  root_domain = var.root_domain
}

module "acm" {
  source = "../../../bsp-daytona-module/module/security/aws-acm-workload/acm"

  domain_name               = "${var.cluster_name}.${local.root_domain}"
  subject_alternative_names = ["*.${var.cluster_name}.${local.root_domain}"]
  resource_tags             = {}
}

module "acm_validation" {
  source = "../../../bsp-daytona-module/module/security/aws-acm-workload/acm_validation"

  acm_validation = {
    certificate_arn = module.acm.acm_certificate_arn
  }
}



//메인 VPC 구성에 적용
  # r53_record = {
  #   zone_id = var.route53_zone_zone_id
  #   acm_certificate_domain_validation_options = module.acm.acm_certificate_domain_validation_options
  #   allow_overwrite = true
  #   ttl = 60
  # }


