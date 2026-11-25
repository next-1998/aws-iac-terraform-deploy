locals {
  network = var.common.network
  base    = local.network.base
  subnets = local.network.subnets
  routing = local.network.routing

  site       = local.base.site
  identifier = "${local.site}-${var.name}"
  key        = replace(var.name, "-", "_")

  resource_tags = local.base.resource_tags

  # 엔진별 기본값
  engine_defaults = {
    postgres = { port = 5432, logs = ["postgresql", "upgrade"], family = "postgres${split(".", var.engine_version)[0]}" }
    mysql    = { port = 3306, logs = ["error", "slowquery"], family = "mysql${join(".", slice(split(".", var.engine_version), 0, min(2, length(split(".", var.engine_version)))))}" }
  }
  port        = coalesce(var.port, local.engine_defaults[var.engine].port)
  log_exports = var.log_exports != null ? var.log_exports : local.engine_defaults[var.engine].logs
  family      = local.engine_defaults[var.engine].family

  # 접근 허용: 지정하지 않으면 EC2 서브넷 대역 (표준 + 수동 ec2 서브넷)
  ec2_cidrs = concat(
    values(local.subnets.cidrs.ec2),
    [for n, s in local.subnets.manual : s.cidr if s.purpose == "ec2"],
  )
  allowed_cidrs = var.allowed_cidrs != null ? var.allowed_cidrs : local.ec2_cidrs
}

locals {
  # 비밀번호 여부만 판단 (값은 노출하지 않음)
  managed_password = nonsensitive(var.master_password == null)
}
