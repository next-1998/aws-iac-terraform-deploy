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

output "kms_keys" {
  description = "CMK (ebs: 이 리전 EBS 기본 키, s3: S3 버킷, tfstate: state 버킷·잠금 테이블이 쓰는 키. source: central / local / same-as-s3)"
  value = {
    key_arns = local.kms_key_arns
    source   = local.kms_key_source
  }
}

output "cloudwatch_logs_to_s3" {
  description = "CloudWatch Logs 내보내기 (mode: local = 이 계정 Firehose, central = 중앙 destination. null이면 꺼짐)"
  value = !local.cwlogs_enabled ? null : (local.cwlogs_central ? {
    mode         = "central"
    destination  = var.cloudwatch_logs_destination_arn
    subscription = var.enable_log_subscription
    } : {
    mode         = "local"
    firehose     = module.cwlogs_firehose["this"].name
    subscription = var.enable_log_subscription
    destination  = "${local.cwlogs_bucket_arn}/<로그 그룹 이름>/YYYY/MM/DD/"
  })
}
