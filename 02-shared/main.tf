############################################################
# 02-shared
#   여러 유형(02-compute, 02-database …)이 같이 쓰는 리소스만 만듭니다.
#   - 사이트 ACM 인증서 (<site>.<root_domain>, *.<site>.<root_domain>)
#   - SNS 알림 토픽 (alarm_emails가 있을 때)
#   결과는 /iac/<site>/02-shared/shared 에 남깁니다. 02-compute 등이 읽으므로 먼저 apply합니다.
############################################################

locals {
  network_bundles = ["base", "dns"]
}

# 민감 정보가 아닌 String 파라미터라 insecure_value로 읽습니다 (value는 항상 sensitive)
data "aws_ssm_parameter" "network" {
  for_each = toset(local.network_bundles)
  name     = "/iac/${var.site}/01-network/${each.key}"
}

locals {
  network = { for k, p in data.aws_ssm_parameter.network : k => jsondecode(p.insecure_value) }
}

module "shared_common" {
  source = "../deployment/shared-common"

  network            = local.network
  enable_certificate = var.enable_certificate
  enable_alarm_topic = length(var.alarm_emails) > 0
  alarm_emails       = var.alarm_emails
  common_tags        = var.common_tags
}

############################################################
# 다음 단계로 넘길 값 (/iac/<site>/02-shared/<묶음>)
############################################################
module "contract" {
  source = "../../aws-iac-terraform-module/module/management/aws-ssm-parameter-workload"

  path_prefix = "/iac/${var.site}/02-shared"
  description = "02-shared 묶음 (02-compute, 02-database가 읽음)"
  parameters = {
    shared = {
      certificate_arn = module.shared_common.certificate_arn
      alarm_topic_arn = module.shared_common.alarm_topic_arn
    }
  }

  common_tags = var.common_tags
  site        = var.site
  stack       = "02-shared"
  key_target  = "contract"
}
