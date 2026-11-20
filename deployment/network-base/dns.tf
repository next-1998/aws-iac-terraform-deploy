############################################################
# DNS
#   private 존 (항상, root_domain이 있을 때)
#     - VPC에 연결. VPC 안과 사내망(Resolver inbound를 통해)에서만 조회
#     - 내부용 LB와 내부 서비스 레코드
#   public 존 (enable_public일 때만)
#     - 상위 존에 NS 위임. 외부용 LB 레코드
#     - 같은 이름이라도 VPC 안에서는 private 존만 조회되므로, 외부용 레코드는 두 존에 모두 넣습니다.
#   레코드는 LB를 만드는 리소스가 LB 종류에 따라 자동으로 존을 골라 등록합니다 (내부 IP의 public 노출 방지).
#   ACM 인증서 검증 레코드: public 존이 있으면 public 존, 없으면 상위 존 (parent_zone_id)
############################################################

locals {
  zone_name     = var.root_domain != "" ? "${var.site}.${var.root_domain}" : null
  create_public = var.enable_public && local.zone_name != null
}

data "aws_route53_zone" "parent" {
  count        = local.zone_name != null ? 1 : 0
  name         = var.root_domain
  private_zone = false
}

module "private_zone" {
  source = "../../../aws-iac-terraform-module/module/network/aws-route53-workload/zones"
  count  = local.zone_name != null ? 1 : 0

  zones = {
    (local.zone_name) = {
      comment = "${local.zone_name} (private, ${var.vpc_name})"
      vpc     = [{ vpc_id = module.vpc.vpc.id }]
    }
  }

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "private"
}

module "public_zone" {
  source = "../../../aws-iac-terraform-module/module/network/aws-route53-workload/zones"
  count  = local.create_public ? 1 : 0

  zones = {
    (local.zone_name) = { comment = "${local.zone_name} (public)" }
  }

  common_tags   = var.common_tags
  resource_tags = local.resource_tags
  site          = var.site
  stack         = local.stack
  key_target    = "public"
}

module "public_zone_delegation" {
  source = "../../../aws-iac-terraform-module/module/network/aws-route53-workload/records"
  count  = local.create_public ? 1 : 0

  zone_id   = data.aws_route53_zone.parent[0].zone_id
  zone_name = var.root_domain
  records = {
    ns = {
      name    = var.site
      type    = "NS"
      ttl     = 300
      records = module.public_zone[0].route53_zone_name_servers[local.zone_name]
    }
  }
}
