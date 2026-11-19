output "state_bucket" {
  value = module.state_bucket.id
}

output "lock_table" {
  value = var.create_lock_table ? module.lock_table[0].name : null
}

output "log_bucket_arn" {
  value = var.create_log_bucket ? module.log_bucket["this"].arn : null
}

output "backend_hcl_example" {
  description = "각 단계의 backend.hcl에 넣을 값 예시 (<site>, <단계>는 바꿔서 사용)"
  value       = <<-EOT
    bucket       = "${module.state_bucket.id}"
    key          = "<site>/<단계>/terraform.tfstate"
    region       = "${local.region}"
    encrypt      = true
    use_lockfile = true%{if var.create_lock_table}
    dynamodb_table = "${module.lock_table[0].name}"%{endif}
  EOT
}

output "ebs_kms_key_arn" {
  description = "EBS 기본 CMK (이 리전의 새 EBS 볼륨 기본 키)"
  value       = module.ebs_kms_key.key_arn
}
