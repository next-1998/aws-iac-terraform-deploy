locals {
  # 01-network contract는 ec2-common contract 안에 들어 있음
  network = var.common.network
  base    = local.network.base
  routing = local.network.routing
  dns     = local.network.dns

  site   = local.base.site
  prefix = "${local.site}-${var.name}"

  # 이름 규칙: <np>-<유형>-<용도>-<순번>[-<AZ>] (np = 00-bootstrap naming 접두어, 용도 = stack 이름에서 ec2- 를 뺀 것)
  np      = local.base.name_prefix
  purpose = trimprefix(var.name, "ec2-")
  # 서버 묶음 (자동 확장 시 Agent 설치 대상·지표 차원, 로그 그룹 경로)
  service_group = "${local.np}-ec2-${local.purpose}"

  # ResourceKey 대상 (stack 이름의 '-'를 '_'로)
  key = replace(var.name, "-", "_")

  # 리소스 생성 시 붙이는 변경 태그
  resource_tags = local.base.resource_tags

  azs         = local.base.azs
  instance_az = coalesce(var.instance_az, local.azs[0])
}
