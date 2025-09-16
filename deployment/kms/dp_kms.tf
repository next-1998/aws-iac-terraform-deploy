module "kms" {
  source = "${var.module_repo_url}//module/security/aws-kms-workload"
  
  key_name = "${var.resource_prefix}-ec2-kms"
  region = var.region
  resource_tags = {}
  common_tags = var.common_tags
  bypass_policy_lockout_safety_check = true
  customer_master_key_spec = "SYMMETRIC_DEFAULT"
  deletion_window_in_days = 30
  description = "ec2 cms key"
  enable_key_rotation = true
  is_enabled = true
  key_usage = "ENCRYPT_DECRYPT"
  multi_region = false
  policy = null
  rotation_period_in_days = 365
  source_policy_documents = null
  override_policy_documents = null
  enable_default_policy = true

  tags = merge(
    var.common_tags,
    var.resource_tags,
    {
      Name = "${var.resource_prefix}-ec2-kms"
    }
  )
}



