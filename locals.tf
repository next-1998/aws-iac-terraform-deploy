locals {
  # set resource name
#  bastion_name = var.bastion_instance_name != "" ? var.bastion_instance_name : lower("${var.resource_prefix}-bastion")
  vpc_name     = var.vpc_name != "" ? var.vpc_name : lower("${var.resource_prefix}-vpc")
  was_name     = var.was_name != "" ? var.was_name : lower("${var.resource_prefix}-was")
  was_alb      = var.was_alb_name != "" ? var.was_alb_name : lower("${var.resource_prefix}-was-alb")
  web_ide_name = var.web_ide_name != "" ? var.web_ide_name : lower("${var.resource_prefix}-web-ide")
  web_ide_alb  = var.web_ide_alb_name != "" ? var.web_ide_alb_name : lower("${var.resource_prefix}-web-ide-alb")

  create_db    = var.create_db ? 1 : 0
  db_name      = var.db_name != "" ? var.db_name : lower("${var.resource_prefix}-rds")

  create_bucket       = var.create_bucket ? 1 : 0
  bucket_name         = var.bucket_name != "" ? var.bucket_name : lower("${var.resource_prefix}-bucket")
  bucket_private_acl  = var.bucket_private_acl ? "private" : "public-read"
  bucket_versioning   = var.bucket_versioning ? "Enabled" : "Suspended"

  create_elasticache               = var.create_elasticache ? 1 : 0
  elasticache_name                 = var.elasticache_name != "" ? var.elasticache_name : lower("${var.resource_prefix}-cache-cluster")
  elasticache_port                 = var.elasticache_engine == "redis" ? 6379 : 11211
  # version fix
  elasticache_engine_version       = var.elasticache_engine == "redis" ? "6.2" : "1.6.12"
  elasticache_parameter_group_name = var.elasticache_engine == "redis" ? "default.redis6.x" : "default.memcached1.6"
  elasticache_cache_node_number    = 1

  weekend_stop_enable = var.weekend_stop_enable ? 1 : 0

  attachment_name =  format("%s-%s", var.resource_prefix, var.attachment_tgw)

  /* default: prod setting */
  KEYCLOAK_ENDPOINT = var.KEYCLOAK_ENDPOINT != "" ? var.KEYCLOAK_ENDPOINT : local.prod_keycloak_endpoint
  root_domain       = var.root_domain != "" ? var.root_domain : local.prod_root_domain
  daytona_url       = var.daytona_url != "" ? var.daytona_url : local.prod_daytona_url


/*prod config*/
  prod_keycloak_endpoint = "https://sso.daytona.lge.com"
  prod_root_domain       = "daytona-platform.com"
  prod_daytona_url       = "https://daytona.lge.com/"
}