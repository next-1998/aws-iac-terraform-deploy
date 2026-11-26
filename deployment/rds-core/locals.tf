locals {
  network = var.common.network
  base    = local.network.base
  subnets = local.network.subnets
  routing = local.network.routing

  site = local.base.site
  # 이름: <np>-rds-<엔진 코드>-<DB 키>-01 (np = 00-bootstrap naming 접두어, DB 키 = name에서 rds- 를 뺀 것)
  np         = local.base.name_prefix
  db_key     = trimprefix(var.name, "rds-")
  identifier = "${local.np}-rds-${local.engine_defaults[var.engine].code}-${local.db_key}-01"
  key        = replace(var.name, "-", "_")

  resource_tags = local.base.resource_tags

  # 버전: 주 (16) / 주.부 (8.0, 10.11)
  ver_parts       = split(".", var.engine_version)
  ver_major       = local.ver_parts[0]
  ver_major_minor = join(".", slice(local.ver_parts, 0, min(2, length(local.ver_parts))))

  # 엔진별 기본값 (code: 이름의 엔진 코드, ver_code: 파라미터 그룹 이름의 엔진·버전 코드)
  engine_defaults = {
    postgres = { code = "pg", port = 5432, logs = ["postgresql", "upgrade"], family = "postgres${local.ver_major}", ver_code = "pg${local.ver_major}" }
    mysql    = { code = "my", port = 3306, logs = ["error", "slowquery"], family = "mysql${local.ver_major_minor}", ver_code = "my${replace(local.ver_major_minor, ".", "")}" }
    mariadb  = { code = "mdb", port = 3306, logs = ["error", "slowquery"], family = "mariadb${local.ver_major_minor}", ver_code = "mdb${replace(local.ver_major_minor, ".", "")}" }
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
