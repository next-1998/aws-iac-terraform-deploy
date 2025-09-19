
module keypair_local {
  source = "${var.module_repo_url}/module/security/aws-keypair-workload"
  
  private_key_algorithm = "RSA"
  key_name = var.local_keypair_name
  resource_tags = var.resource_tags
  common_tags = var.common_tags
}

module keypair_service {
  source = "${var.module_repo_url}/module/security/aws-keypair-workload"
  
  private_key_algorithm = "RSA"
  key_name = var.service_keypair_name
  resource_tags = var.resource_tags
  common_tags = var.common_tags
}