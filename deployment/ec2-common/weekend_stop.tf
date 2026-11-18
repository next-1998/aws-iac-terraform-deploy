############################################################
# EC2 주말 중지 (선택, 기본값 끔)
#   Lambda 코드와 권한은 module repo의 ops/aws-weekendstop-workload
#   EC2 서브넷에서 실행하고, AWS API는 01-network의 ec2 endpoint로 호출합니다.
############################################################
module "weekend_stop" {
  source = "../../../aws-iac-terraform-module/module/ops/aws-weekendstop-workload"
  count  = var.enable_weekend_stop ? 1 : 0

  name           = "${local.prefix}-weekend-stop"
  target         = "ec2"
  vpc_id         = local.base.vpc_id
  subnet_ids     = [for az in local.azs : module.subnet[az].vpc_subnet[0].id]
  endpoint_cidrs = local.base.vpc_cidrs

  schedule_enabled  = var.weekend_stop.schedule_enabled
  stop_schedule     = var.weekend_stop.stop_schedule
  start_schedule    = var.weekend_stop.start_schedule
  schedule_timezone = var.weekend_stop.timezone
  dry_run           = var.weekend_stop.dry_run

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = local.site
  stack         = var.name
  key_target    = "${local.key}_weekend_stop"
}

resource "terraform_data" "weekend_stop_checks" {
  count = var.enable_weekend_stop ? 1 : 0

  lifecycle {
    precondition {
      condition     = contains(var.network.endpoints.interface, "ec2")
      error_message = "주말 중지 Lambda는 VPC 안에서 실행되므로 01-network의 interface_endpoints에 \"ec2\"가 필요합니다."
    }
  }
}
