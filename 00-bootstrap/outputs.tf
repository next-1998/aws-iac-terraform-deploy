output "state_bucket" {
  value = aws_s3_bucket.state.id
}

output "lock_table" {
  value = var.create_lock_table ? aws_dynamodb_table.lock[0].name : null
}

output "log_bucket_arn" {
  value = var.create_log_bucket ? aws_s3_bucket.logs[0].arn : null
}

output "backend_hcl_example" {
  description = "각 단계의 backend.hcl에 넣을 값 예시 (<site>, <단계>는 바꿔서 사용)"
  value       = <<-EOT
    bucket       = "${aws_s3_bucket.state.id}"
    key          = "<site>/<단계>/terraform.tfstate"
    region       = "${local.region}"
    encrypt      = true
    use_lockfile = true%{if var.create_lock_table}
    dynamodb_table = "${aws_dynamodb_table.lock[0].name}"%{endif}
  EOT
}
