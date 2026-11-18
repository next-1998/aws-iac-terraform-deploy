locals {
  # 01-network contract는 ec2-common contract 안에 들어 있음
  network = var.common.network
  base    = local.network.base
  routing = local.network.routing
  dns     = local.network.dns

  site   = local.base.site
  prefix = "${local.site}-${var.name}"

  # ResourceKey 대상 (stack 이름의 '-'를 '_'로)
  key = replace(var.name, "-", "_")

  # 리소스 생성 시 붙이는 변경 태그
  resource_tags = local.base.resource_tags

  azs         = local.base.azs
  instance_az = coalesce(var.instance_az, local.azs[0])
}
