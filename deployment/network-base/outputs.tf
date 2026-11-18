# stack들이 받는 표준 입력 묶음. 모든 사이트에서 같은 형태를 유지합니다.
output "contract" {
  description = "base-network → stack 표준 연결 값"
  value = {
    site     = var.site
    vpc_id   = module.vpc.vpc.id
    vpc_name = var.vpc_name
    azs      = local.azs
    az_index = local.az_index # AZ → 고정 번호 (a=0, b=1, c=2, d=3)
    max_azs  = local.max_azs

    # 대역
    network_type  = local.network_type # routable / hybrid(routable + internal)
    vpc_cidrs     = [for c in var.vpc_cidrs : c.cidr]
    routable_cidr = local.routable
    internal_cidr = local.internal
    stack_zones   = local.stack_zones # stack은 zone + slot으로 블록을 받음

    # edge (ALB 위치)
    edge_subnet_ids      = { for az in local.azs : az => module.edge_subnet[az].vpc_subnet[0].id }
    edge_subnet_cidrs    = local.edge_cidrs
    edge_route_table_id  = module.edge_rt.vpc_rt.id
    transit_subnet_cidrs = local.transit_cidrs

    # 라우팅 대상
    igw_id          = var.enable_internet ? module.igw[0].vpc_igw.id : null
    public_nat_ids  = local.public_nat_ids  # AZ → 그 AZ가 쓸 public NAT
    private_nat_ids = local.private_nat_ids # AZ → 그 AZ가 쓸 private NAT
    nat_per_az      = var.nat_per_az
    tgw_id          = var.tgw_id
    tgw_route_cidrs = var.tgw_route_cidrs

    # DNS
    zone_id   = local.zone_name != null ? module.zone[0].route53_zone_zone_id[local.zone_name] : null
    zone_name = local.zone_name

    # plan 시점에 정해지는 플래그 (stack의 count 조건은 ID 대신 이 값을 사용)
    has_public_nat  = var.enable_internet
    has_private_nat = local.create_private_nat
    has_tgw         = local.use_tgw
    has_zone        = local.zone_name != null

    # stack이 리소스를 만들 때 resource_tags로 넘길 값
    resource_tags = local.resource_tags
  }
}
