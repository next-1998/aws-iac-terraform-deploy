locals {
  network = var.common.network
  base    = local.network.base
  subnets = local.network.subnets
  routing = local.network.routing

  site   = local.base.site
  np     = local.base.name_prefix
  db_key = trimprefix(var.name, "rds-")
  key    = replace(var.name, "-", "_")

  resource_tags = local.base.resource_tags

  # 버전: 주 (16) / 주.부 (8.0)
  ver_parts       = split(".", var.engine_version)
  ver_major       = local.ver_parts[0]
  ver_major_minor = join(".", slice(local.ver_parts, 0, min(2, length(local.ver_parts))))

  # 엔진별 기본값 (code: 이름의 엔진 코드, ver_code: 파라미터 그룹 이름의 엔진·버전 코드)
  engine_defaults = {
    aurora-postgresql = { code = "apg", port = 5432, logs = ["postgresql"], family = "aurora-postgresql${local.ver_major}", ver_code = "apg${local.ver_major}" }
    aurora-mysql      = { code = "amy", port = 3306, logs = ["error", "slowquery"], family = "aurora-mysql${local.ver_major_minor}", ver_code = "amy${replace(local.ver_major_minor, ".", "")}" }
  }
  ed          = local.engine_defaults[var.engine]
  port        = coalesce(var.port, local.ed.port)
  log_exports = var.log_exports != null ? var.log_exports : local.ed.logs

  # 이름: 클러스터 <np>-rds-cl-<엔진>-<키>-01, 인스턴스 <np>-rds-<엔진>-<키>-NN (순번만. 01 = 처음 쓰기, 그다음 multi_az, replicas 키 이름순)
  #   Aurora는 장애 조치 때 쓰기·읽기 역할이 바뀌므로 이름에 역할(ro)을 넣지 않음 (RDS 읽기 복제본은 역할 고정이라 -ro-NN)
  cluster_id  = "${local.np}-rds-cl-${local.ed.code}-${local.db_key}-01"
  instance_id = "${local.np}-rds-${local.ed.code}-${local.db_key}"

  serverless     = var.serverless_v2 != null
  instance_class = local.serverless ? "db.serverless" : var.instance_class

  # 인스턴스: 쓰기 1 + (multi_az면 다른 AZ에 장애 조치용 읽기 1, 우선순위 0) + replicas (키 이름순, 우선순위 1)
  azs     = local.base.azs
  ro_keys = concat(var.multi_az ? ["__multi_az"] : [], sort(keys(var.replicas)))
  instances = merge(
    { w = { identifier = "${local.instance_id}-01", az = local.azs[0], tier = 0, instance_class = local.instance_class, performance_insights = var.performance_insights } },
    {
      for i, k in local.ro_keys : k => {
        identifier           = format("%s-%02d", local.instance_id, i + 2)
        az                   = local.azs[(i + 1) % length(local.azs)]
        tier                 = k == "__multi_az" ? 0 : 1
        instance_class       = local.serverless ? "db.serverless" : coalesce(try(var.replicas[k].instance_class, null), var.instance_class)
        performance_insights = coalesce(try(var.replicas[k].performance_insights, null), var.performance_insights)
      }
    },
  )

  # 접근 허용: 지정하지 않으면 EC2 서브넷 대역
  ec2_cidrs = concat(
    values(local.subnets.cidrs.ec2),
    [for n, s in local.subnets.manual : s.cidr if s.purpose == "ec2"],
  )
  allowed_cidrs = var.allowed_cidrs != null ? var.allowed_cidrs : local.ec2_cidrs
}
