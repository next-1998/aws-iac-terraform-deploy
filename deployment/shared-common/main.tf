############################################################
# shared-common (02-resource 단계)
#   여러 유형이 같이 쓰거나, 모든 리소스가 대상인 것만 둡니다.
#   - ACM 인증서: <site>.<root_domain>, *.<site>.<root_domain> (용도별 ALB가 같이 씀)
#   - SNS 알림 토픽 (선택): 리소스별 알람이 같은 곳으로 보냄
#   - (예정) 주말 중지 Lambda: legacy/deployment/lambda를 옮기면서 인스턴스별 태그 확인 버그 수정
#   KMS 키는 기본적으로 각 리소스 <유형>-common이 만듭니다. 공용 키가 필요할 때만 여기에 추가합니다.
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
resource "aws_route53_record" "acm_validation" {
  for_each = local.create_cert ? {
    for o in module.acm[0].acm_certificate_domain_validation_options : o.domain_name => o
  } : {}

  zone_id         = local.validation_zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  ttl             = 300
  records         = [each.value.resource_record_value]
  allow_overwrite = true
}

module "acm_validation" {
  source = "../../../aws-iac-terraform-module/module/security/aws-acm-workload/acm_validation"
  count  = local.create_cert ? 1 : 0

  acm_validation          = { certificate_arn = module.acm[0].acm_certificate_arn }
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}

############################################################
# SNS 알림 토픽 (선택)
############################################################
module "tags" {
  source = "../../../aws-iac-terraform-module/module/_tags"

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = local.stack
  key_target    = "site"
  scope         = "shared"

  resources = var.enable_alarm_topic ? {
    alarm_topic = { type = "sns:topic", abbr = "sns", name = "${local.site}-alarm", target = "alarm" }
  } : {}
}

resource "aws_sns_topic" "alarm" {
  count             = var.enable_alarm_topic ? 1 : 0
  name              = "${local.site}-alarm"
  kms_master_key_id = "alias/aws/sns"
  tags              = module.tags.tags["alarm_topic"]
}

resource "aws_sns_topic_subscription" "alarm_email" {
  for_each  = var.enable_alarm_topic ? toset(var.alarm_emails) : toset([])
  topic_arn = aws_sns_topic.alarm[0].arn
  protocol  = "email"
  endpoint  = each.value
}
