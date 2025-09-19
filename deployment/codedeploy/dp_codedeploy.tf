# module "sample_policy" {
#   source = "./module/security/aws-iam-workload/policy"

#   name = "example"
#   path        = "/"
#   description = "My example policy"

#   policy = jsondecode(file("${path.module}/json/sample_policy.json"))
#   # <<-EOF
#   #   {
#   #     "Version": "2012-10-17",
#   #     "Statement": [
#   #       {
#   #         "Action": [
#   #           "ec2:Describe*"
#   #         ],
#   #         "Effect": "Allow",
#   #         "Resource": "*"
#   #       }
#   #     ]
#   #   }
#   # EOF

#   common_tags = var.common_tags
#   resource_tags = {}
# }

module "codedeploy_service_role" {
  source = "${var.module_repo_url}/module/security/aws-iam-workload/role"

  name = "${var.resource_prefix}-CodeDeploy-Service-Role"
  path = "/"
  description = "codedeploy service role"

  assume_role_policy = jsondecode(file("${path.module}/json/CodeDeploy-Service-Role.json"))
#   <<EOF
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Sid": "",
#       "Effect": "Allow",
#       "Principal": {
#         "Service": [
#           "codedeploy.amazonaws.com"
#         ]
#       },
#       "Action": "sts:AssumeRole"
#     }
#   ]
# }
# EOF

  policies = {
    AWSCodeDeployRole = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
  }
}


module "codedeploy" {
  source = "./module/devops/aws-codedeploy-workload/code-deploy"

  name = "${var.resource_prefix}-CodeDeploy-Application"
  deployment_group_name = "${var.resource_prefix}-Deployment-Group"
  service_role_arn = module.codedeploy_service_role.arn
  ec2_tag_filter = {
    key = "codeDeployTarget"
    type = "KEY_AND_VALUE"
    value = "true"
  }
  
  auto_rollback_configuration = {
    enabled = true
    events = ["DEPLOYMENT_FAILURE"]
  }

  common_tags = var.common_tags
  resource_tags = var.resource_tags
    
  }