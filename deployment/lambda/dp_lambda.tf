module "start_stop_ec2_rds_policy" {
  source = "${var.module_repo_url}/module/security/aws-iam-workload/policy"
  name = "${var.resource_prefix}-Lambda-default-Policy"
  description = "Lambda default Policy"
  policy = jsondecode(file("${path.module}/json/lambda_default_policy.json"))
}


module "lambda_role" {
  source = "${var.module_repo_url}/module/devtools/aws-lambda-workload/lambda"

  name = "${var.resource_prefix}-Lambda-default-Role"
  description = "Lambda default Role"
  assume_role_policy = jsondecode(templatefile("${path.module}/json/Role-template.json.tftpl",{
    SID = ""
    EFFECT = "Allow"
    SERVICE = "lambda.amazonaws.com"
    ACTION = "sts:AssumeRole"
    })
  )

  policies = {
    LambdaDefaultPolicy = module.start_stop_ec2_rds_policy.arn
  }
}

data "archive_file" "start_stop_ec2_rds_lambda_py" {
  type             = "zip"
  source_file      = "${path.module}/lambda/weekend-stop/index.py"
  output_file_mode = "0666"
  output_path      = "${path.module}/files/weekend-stop-py.zip"
}

module "start_stop_ec2_rds_lambda" {
  source = "${var.module_repo_url}/module/devtools/aws-lambda-workload/lambda"

  filename = data.archive_file.start_stop_ec2_rds_lambda_py.output_path
  function_name = "start-stop-ec2-rds-lambda-py"
  name = "${var.resource_prefix}-Lambda-default-Function"
  description = "Lambda default Function"
  role_arn = module.lambda_role.arn
  handler = "index.lambda_handler"
  timeout = "600"
  source_code_hash = data.archive_file.start_stop_ec2_rds_lambda_py.output_base64sha256
  runtime = "python3.10"
  environment_variables = {
    TZ = "Asia/Seoul"
  }
}
