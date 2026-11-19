############################################################
# shared-common (02-shared 단계)
#   여러 유형이 같이 쓰거나, 모든 리소스가 대상인 것만 둡니다.
#   - ACM 인증서: <site>.<root_domain>, *.<site>.<root_domain> (용도별 ALB가 같이 씀)
#   - SNS 알림 토픽 (선택): 리소스별 알람이 같은 곳으로 보냄
#   주말 중지 Lambda는 대상 서비스의 -common에 둡니다 (ec2-common, rds-common).
#   KMS 키는 용도별로 분리합니다 (kms.tf). 여기에는 공용 서비스 키(logs, sns)만 두고, 리소스 데이터 키는 각 <유형>-common이 만듭니다 (예: ec2-common의 ec2).
############################################################

locals {
  base = var.network.base
  dns  = var.network.dns

  site          = local.base.site
  stack         = var.name
  resource_tags = local.base.resource_tags

  create_cert = var.enable_certificate && local.dns.zone_name != null

  # 인증서 검증 레코드를 넣을 존: 사이트 public 존이 있으면 거기, 없으면 상위 존
  # (검증 레코드는 무작위 값이라 정보가 노출되지 않음)
  validation_zone_id = local.dns.public_zone_id != null ? local.dns.public_zone_id : local.dns.parent_zone_id
}

############################################################
# ACM 인증서 (DNS 검증)
############################################################
module "acm" {
  source = "../../../aws-iac-terraform-module/module/security/aws-acm-workload/acm"
  count  = local.create_cert ? 1 : 0

  domain_name               = local.dns.zone_name
  subject_alternative_names = ["*.${local.dns.zone_name}"]

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = local.stack
  key_target    = "site"
}

# 키는 plan 시점에 정해지는 도메인 이름 (검증 값은 apply 후에 정해짐).
# 와일드카드와 apex는 같은 검증 레코드를 쓰므로 allow_overwrite로 중복을 허용합니다.
module "acm_validation_record" {
  source = "../../../aws-iac-terraform-module/module/network/aws-route53-workload/records"
  count  = local.create_cert ? 1 : 0

  zone_id = local.validation_zone_id
  records = {
    for o in module.acm[0].acm_certificate_domain_validation_options : o.domain_name => {
      full_name       = o.resource_record_name
      type            = o.resource_record_type
      ttl             = 300
      records         = [o.resource_record_value]
      allow_overwrite = true
    }
  }
}

module "acm_validation" {
  source = "../../../aws-iac-terraform-module/module/security/aws-acm-workload/acm_validation"
  count  = local.create_cert ? 1 : 0

  certificate_arn         = module.acm[0].acm_certificate_arn
  validation_record_fqdns = values(module.acm_validation_record[0].route53_record_fqdn)
}

############################################################
# SNS 알림 토픽 (선택)
############################################################
module "alarm_topic" {
  source = "../../../aws-iac-terraform-module/module/monitor_log/aws-sns-workload/topic"
  count  = var.enable_alarm_topic ? 1 : 0

  name = "${local.site}-alarm"
  # 알림 토픽 CMK (kms.tf: 중앙 키 또는 이 계정 키)
  kms_master_key_id = local.kms_key_arns.sns

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = local.stack
  key_target    = "alarm"
  scope         = "shared"
}

module "alarm_subscription" {
  source = "../../../aws-iac-terraform-module/module/monitor_log/aws-sns-workload/subscription"
  count  = var.enable_alarm_topic ? 1 : 0

  topic_arn     = module.alarm_topic[0].arn
  subscriptions = { for e in var.alarm_emails : e => { protocol = "email", endpoint = e } }
}
