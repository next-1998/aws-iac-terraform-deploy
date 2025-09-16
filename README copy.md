1. module 리스트 및 경로

| division | module Name | path |  description  | not used | 
|----------|-------------|------|---------------|----------|
| cache | aws-cachesng-workload | module/cache/aws-cachesng-workload | elasticache subnet group | X |
| cache | aws-elasticache-workload | module/cache/aws-elasticache-workload | elasticache | X |
| computing | aws-asg-workload | module/computing/aws-asg-workload | autoscale group | O |
| computing | aws-ebs-workload | module/computing/aws-ebs-workload | added ebs volume | X |
| computing | aws-instance-workload | module/computing/aws-instance-workload | EC2 instance | X |
| computing | aws-lt-workload | module/computing/aws-lt-workload | launch template | X |
| database | aws-dynamo-workload | module/database/aws-dynamo-workload | dynamo DB  | X |
| database | aws-rds-workload | module/database/aws-rds-workload | RDS instance / parameter | X |
| database | aws-rdssng-workload | module/database/aws-rdssng-workload | RDS's subnet group | X |
| devtools | aws-codedeploy-workload | module/devtools/aws-codedeploy-workload | code deploy | X |
| devtools | aws-lambda-workload | module/devtools/aws-lambda-workload | lambda (start/stop schedule) | X |
| monitor_log | aws-cloudtrail-workload | module/monitor_log/aws-cloudtrail-workload | cloudtaril setting  | X |
| monitor_log | aws-cloudwatch-workload | module/monitor_log/aws-cloudwatch-workload | eventbridge & loggroup | X |
| network | aws-eip-workload | module/network/aws-eip-workload | VPC EIP setting | X |
| network | aws-elb-workload(lb) | module/network/aws-elb-workload/lb | loadbalancer setting | X |
| network | aws-elb-workload(listener) | module/network/aws-elb-workload/lb-listener | loadbalancer listener & listener rule setting | X |
| network | aws-elb-workload(target) | module/network/aws-elb-workload /lb-target | loadbalancer targetgroup setting | X |
| network | aws-igw-workload | module/network/aws-igw-workload/ | internet gateway setting | X |
| network | aws-natgw-workload | module/network/aws-natgw-workload | nat gateway setting | X |
| network | aws-route53-workload(record) | module/network/aws-route53-workload/record/ | route53 record setting | X |
| network | aws-route53-workload(zones) | module/network/aws-route53-workload/zones/ | route53 zone setting | X |
| network | aws-rt-workload(route) | module/network/aws-rt-workload/route/ | route settinf | X |
| network | aws-rt-workload(route table) | module/network/aws-rt-workload/route table/ | routetable setting | X |
| network | aws-sbn-workload | module/network/aws-sbn-workload/ | VPC subnet setting | X |
| network | aws-tgwattch-workload | module/network/aws-tgwattch-workload/ | transit gateway attach setting | X |
| network | aws-vpc-workload | module/network/aws-vpc-workload/ | VPC setting | X |
| network | aws-vpce-workload | module/network/aws-vpce-workload/ | VPC Endpoint setting | O |
| security | aws-acm-workload | module/security/aws-acm-workload/ | aws certimanager setting | X |
| security | aws-acm-workload(vadidation) | module/security/aws-acm-workload/vadidation/ | acm validation setting | X |
| security | aws-iam-workload(role) | module/security/aws-iam-workload/role/ | iam role add | X |
| security | aws-iam-workload(policy) | module/security/aws-iam-workload/policy/ | iam policy add | X |
| security | aws-kms-workload | module/security/aws-kms-workload/ | kms setting | O |
| security | aws-securitygroup-workload | module/security/aws-securitygroup-workload/ | security group & sg rule setting | X |


2. deploy repo 구성
- terraform.auto.tfvars
- main.tf
- deployment (각 카탈로그 배포 모듈)