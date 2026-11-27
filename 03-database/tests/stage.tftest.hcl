# 03-database 단계 루트 검사 (plan만, mock provider). terraform.tfvars 값을 사용합니다.
# 01-network, 00-bootstrap이 남긴 Parameter Store 값은 아래 override_data로 대신합니다.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-northeast-2:111111111111:loadbalancer/app/mock/0123456789abcdef" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:ap-northeast-2:111111111111:targetgroup/mock/0123456789abcdef" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "ap-northeast-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
}

# NLB 대상 등록(apply 방식)의 DB 주소 → IP 조회
mock_provider "dns" {
  mock_data "dns_a_record_set" {
    defaults = { addrs = ["10.227.0.10"] }
  }
}

override_data {
  target = data.aws_ssm_parameter.network["base"]
  values = { insecure_value = "{\"contract_version\":1,\"site\":\"simple\",\"layout_version\":\"v1\",\"vpc_id\":\"vpc-1\",\"vpc_name\":\"hw-iac-dev-an2-vpc-simple-01\",\"name_prefix\":\"hw-iac-dev-an2\",\"azs\":[\"ap-northeast-2a\",\"ap-northeast-2b\"],\"az_short\":{\"ap-northeast-2a\":\"a\",\"ap-northeast-2b\":\"b\"},\"vpc_cidrs\":[\"10.227.0.0/23\"],\"primary_cidr\":\"10.227.0.0/23\",\"extra_routable\":[],\"internal_cidr\":null,\"enable_public\":false,\"resource_tags\":{\"VpcName\":\"simple-vpc\"}}" }
}
override_data {
  target = data.aws_ssm_parameter.network["subnets"]
  values = { insecure_value = "{\"ids\":{\"edge\":{\"ap-northeast-2a\":\"subnet-ea\",\"ap-northeast-2b\":\"subnet-eb\"},\"vpce\":{\"ap-northeast-2a\":\"subnet-va\",\"ap-northeast-2b\":\"subnet-vb\"},\"transit\":{\"ap-northeast-2a\":\"subnet-ta\",\"ap-northeast-2b\":\"subnet-tb\"},\"public\":{}},\"cidrs\":{\"edge\":{\"ap-northeast-2a\":\"10.227.0.0/26\",\"ap-northeast-2b\":\"10.227.1.0/26\"},\"vpce\":{\"ap-northeast-2a\":\"10.227.0.64/27\",\"ap-northeast-2b\":\"10.227.1.64/27\"},\"transit\":{\"ap-northeast-2a\":\"10.227.0.96/28\",\"ap-northeast-2b\":\"10.227.1.96/28\"},\"ec2\":{\"ap-northeast-2a\":\"10.227.0.128/26\",\"ap-northeast-2b\":\"10.227.1.128/26\"},\"db\":{\"ap-northeast-2a\":\"10.227.0.192/27\",\"ap-northeast-2b\":\"10.227.1.192/27\"},\"public\":{\"ap-northeast-2a\":\"10.227.0.224/27\",\"ap-northeast-2b\":\"10.227.1.224/27\"}},\"eks_placement\":null,\"eks_cidrs\":{},\"manual\":{}}" }
}
override_data {
  target = data.aws_ssm_parameter.network["routing"]
  values = { insecure_value = "{\"has_public\":false,\"has_tgw\":true,\"has_private_nat\":false,\"igw_id\":null,\"public_nat_ids\":{},\"private_nat_ids\":{},\"nat_public_ips\":[],\"tgw_id\":\"tgw-1\",\"corp_cidrs\":[\"10.0.0.0/8\"],\"peerings\":{},\"prefix_list_ids\":{\"access_ctl\":\"pl-1\"}}" }
}
override_data {
  target = data.aws_ssm_parameter.network["endpoints"]
  values = { insecure_value = "{\"ids\":{},\"gateway\":{\"s3\":\"vpce-2\"},\"interface\":[\"ssm\",\"logs\",\"monitoring\",\"ec2\",\"elasticloadbalancing\"],\"vpce_sg_id\":\"sg-1\"}" }
}
override_data {
  target = data.aws_ssm_parameter.shared
  values = { insecure_value = "{\"backup_tag_keys\":{\"daily\":\"Backup-daily\",\"monthly\":\"Backup-monthly\",\"pitr\":\"Backup-pitr\"}}" }
}
override_data {
  target = data.aws_ssm_parameter.bootstrap_kms
  values = { insecure_value = "{\"key_arns\":{\"ebs\":\"arn:aws:kms:ap-northeast-2:111111111111:key/ebs-mock\",\"logs\":\"arn:aws:kms:ap-northeast-2:111111111111:key/logs-mock\",\"s3\":\"arn:aws:kms:ap-northeast-2:111111111111:key/s3-mock\"},\"source\":{}}" }
}


run "defaults_postgres" {
  command = plan
  assert {
    # tfvars 예시: app = postgres 16, 단일 AZ(운영 모드 아님), 삭제 보호 끔, 비밀번호는 Secrets Manager
    condition = (
      module.rds_postgres["app"].db.identifier == "hw-iac-dev-an2-rds-pg-app-01" && module.rds_postgres["app"].db.port == 5432 &&
      module.rds_postgres["app"].db.engine == "postgres" &&
      !module.rds_postgres["app"].settings.multi_az && !module.rds_postgres["app"].settings.deletion_protection &&
      module.rds_postgres["app"].settings.manage_master_user_password
    )
    error_message = "기본 DB: ${jsonencode(module.rds_postgres["app"].db)}"
  }
  assert {
    # DB 로그 그룹은 AWS 고정 이름, 접근은 EC2 서브넷 대역에서 DB 포트만
    condition = (
      toset(values(module.rds_postgres["app"].log_groups)) == toset(["/aws/rds/instance/hw-iac-dev-an2-rds-pg-app-01/postgresql", "/aws/rds/instance/hw-iac-dev-an2-rds-pg-app-01/upgrade"]) &&
      toset(module.rds_postgres["app"].allowed_cidrs) == toset(["10.227.0.128/26", "10.227.1.128/26"])
    )
    error_message = "로그·접근: ${jsonencode(module.rds_postgres["app"].log_groups)} / ${jsonencode(module.rds_postgres["app"].allowed_cidrs)}"
  }
  assert {
    # DB 서브넷은 01-network db CIDR(AZ 2개), RDS 키는 이 계정에 생성, 계약 경로
    condition = (
      length(module.rds_common[0].contract.subnet_cidrs) == 2 && module.rds_common[0].contract.kms_key_source == "local" &&
      module.contract[0].names["rds"] == "/iac/simple/03-database/rds"
    )
    error_message = "공통: ${jsonencode(module.rds_common[0].contract.subnet_cidrs)}"
  }
}

run "operation_mode_enable_multi_az_and_protection" {
  command = plan
  variables {
    operation_mode = "enable"
  }
  assert {
    condition     = module.rds_postgres["app"].settings.multi_az && module.rds_postgres["app"].settings.deletion_protection && module.rds_postgres["app"].settings.final_snapshot
    error_message = "운영 모드면 Multi-AZ + 삭제 보호 + 최종 스냅샷"
  }
}

run "mysql_engine_defaults" {
  command = plan
  variables {
    rds_postgres = {}
    rds_mysql    = { orders = { engine_version = "8.0" } }
  }
  assert {
    condition = (
      module.rds_mysql["orders"].db.port == 3306 &&
      module.rds_mysql["orders"].settings.parameter_group_family == "mysql8.0" &&
      toset(keys(module.rds_mysql["orders"].log_groups)) == toset(["error", "slowquery"])
    )
    error_message = "mysql 기본값: ${jsonencode(module.rds_mysql["orders"].db)}"
  }
}

run "no_rds_no_resources" {
  command = plan
  variables {
    rds_postgres = {}
  }
  assert {
    condition     = length(module.rds_common) == 0 && length(module.rds_postgres) == 0 && length(module.contract) == 0
    error_message = "rds가 비면 아무것도 만들지 않음"
  }
}

run "central_rds_key" {
  command = plan
  variables {
    central_kms_key_arns = { rds = "arn:aws:kms:ap-northeast-2:222222222222:key/11111111-2222-3333-4444-555555555555" }
  }
  assert {
    condition     = module.rds_common[0].contract.kms_key_source == "central"
    error_message = "중앙 rds 키: ${module.rds_common[0].contract.kms_key_source}"
  }
}

run "read_replicas" {
  command = plan
  variables {
    rds_postgres         = { app = { replicas = { r1 = {}, r2 = { instance_class = "db.t4g.small" } } } }
    rds_master_passwords = { app = "Test-Passw0rd-123" }
  }
  assert {
    # 복제본 2개, 이름 <site>-rds-app-<키>, 복제본마다 로그 그룹
    condition = (
      toset(module.rds_postgres["app"].settings.replicas) == toset(["r1", "r2"]) &&
      length(module.rds_postgres["app"].replicas) == 2
    )
    error_message = "복제본: ${jsonencode(module.rds_postgres["app"].settings.replicas)}"
  }
}

run "reject_replicas_without_backup" {
  command = plan
  variables {
    rds_postgres = { app = { backup_retention_days = 0, replicas = { r1 = {} } } }
  }
  expect_failures = [var.rds_postgres]
}

run "restore_from_snapshot" {
  command = plan
  variables {
    rds_postgres = { app = { snapshot_identifier = "app-golden-2026-11" } }
  }
  assert {
    condition     = module.rds_postgres["app"].settings.from_snapshot && module.rds_postgres["app"].settings.manage_master_user_password
    error_message = "스냅샷 복원 + 관리형 비밀번호"
  }
}

run "reject_postgres_replicas_with_managed_password" {
  # PostgreSQL 복제본은 RDS 비밀번호 관리와 같이 쓸 수 없음 → 비밀번호를 넣어야 함
  command = plan
  variables {
    rds_postgres = { app = { replicas = { r1 = {} } } }
  }
  expect_failures = [var.rds_master_passwords]
}

run "plaintext_password_turns_off_managed" {
  command = plan
  variables {
    rds_postgres         = { app = {}, etc = {} }
    rds_master_passwords = { app = "Test-Passw0rd-123" }
  }
  assert {
    condition     = !module.rds_postgres["app"].settings.manage_master_user_password && module.rds_postgres["etc"].settings.manage_master_user_password
    error_message = "비밀번호를 넣은 DB만 RDS 비밀번호 관리를 꺼야 합니다."
  }
}

run "reject_password_for_unknown_db" {
  command = plan
  variables {
    rds_postgres         = { app = {} }
    rds_master_passwords = { other = "Test-Passw0rd-123" }
  }
  expect_failures = [var.rds_master_passwords]
}

run "monitoring_and_minor_upgrade_defaults" {
  # 기본: 향상된 모니터링 60초(역할 생성), 마이너 버전 자동 업그레이드 끔
  command = plan
  variables {
    rds_postgres = { app = {}, nomon = { monitoring_interval = 0, auto_minor_version_upgrade = true } }
  }
  assert {
    condition     = module.rds_postgres["app"].settings.monitoring_interval == 60 && !module.rds_postgres["app"].settings.auto_minor_version_upgrade
    error_message = "기본값: ${jsonencode(module.rds_postgres["app"].settings)}"
  }
  assert {
    condition     = module.rds_postgres["nomon"].settings.monitoring_interval == 0 && module.rds_postgres["nomon"].settings.auto_minor_version_upgrade
    error_message = "DB별 값: ${jsonencode(module.rds_postgres["nomon"].settings)}"
  }
}

run "no_monitoring_role_when_all_off" {
  command = plan
  variables {
    rds_postgres = { app = { monitoring_interval = 0 } }
  }
  assert {
    condition     = length(module.rds_common[0].contract.monitoring_role_arn == null ? [] : ["x"]) == 0
    error_message = "모니터링을 모두 끄면 역할을 만들지 않아야 합니다."
  }
}

run "backup_tag_from_plan" {
  # backup_plans를 넣은 DB만 플랜마다 태그 Backup-<플랜> = true (02-shared AWS Backup이 태그로 선택)
  command = plan
  variables {
    rds_postgres = { app = { backup_plans = ["daily", "pitr"] }, etc = {} }
  }
  assert {
    condition     = jsonencode(module.rds_postgres["app"].settings.backup_tags) == jsonencode({ Backup-daily = "true", Backup-pitr = "true" }) && length(module.rds_postgres["etc"].settings.backup_tags) == 0
    error_message = "백업 플랜: ${jsonencode([module.rds_postgres["app"].settings.backup_tags, module.rds_postgres["etc"].settings.backup_tags])}"
  }
}

run "mariadb_engine_defaults" {
  # MariaDB: 포트 3306, 파라미터 그룹 family mariadb<주.부>, 로그 error·slowquery
  command = plan
  variables {
    rds_postgres         = {}
    rds_mariadb          = { shop = { engine_version = "10.11", replicas = { r1 = {} } } }
    rds_master_passwords = { shop = "Test-Passw0rd-123" }
  }
  assert {
    condition = (
      module.rds_mariadb["shop"].db.port == 3306 &&
      module.rds_mariadb["shop"].settings.parameter_group_family == "mariadb10.11" &&
      toset(keys(module.rds_mariadb["shop"].log_groups)) == toset(["error", "slowquery"]) &&
      !module.rds_mariadb["shop"].settings.manage_master_user_password
    )
    error_message = "mariadb 기본값: ${jsonencode(module.rds_mariadb["shop"].settings)}"
  }
}

run "names_follow_rule" {
  # DB <접두어>-rds-<엔진 코드>-<DB 키>-01, 복제본 …-ro-01, 파라미터 그룹 <접두어>-rds-pagrp-<엔진·주버전>-<DB 키>-01
  command = plan
  variables {
    rds_postgres         = { app = { replicas = { r1 = {}, r2 = {} } } }
    rds_mysql            = { orders = {} }
    rds_mariadb          = { shop = {} }
    rds_master_passwords = { app = "Test-Passw0rd-123" }
  }
  assert {
    condition = (
      module.rds_postgres["app"].settings.parameter_group_name == "hw-iac-dev-an2-rds-pagrp-pg16-app-01" &&
      jsonencode({ for k, r in module.rds_postgres["app"].replicas : k => r.identifier }) == jsonencode({ r1 = "hw-iac-dev-an2-rds-pg-app-ro-01", r2 = "hw-iac-dev-an2-rds-pg-app-ro-02" }) &&
      module.rds_mysql["orders"].settings.identifier == "hw-iac-dev-an2-rds-my-orders-01" &&
      module.rds_mysql["orders"].settings.parameter_group_name == "hw-iac-dev-an2-rds-pagrp-my80-orders-01" &&
      module.rds_mariadb["shop"].settings.identifier == "hw-iac-dev-an2-rds-mdb-shop-01" &&
      module.rds_mariadb["shop"].settings.parameter_group_name == "hw-iac-dev-an2-rds-pagrp-mdb1011-shop-01"
    )
    error_message = "이름: ${jsonencode([module.rds_postgres["app"].settings, module.rds_mysql["orders"].settings.identifier, module.rds_mariadb["shop"].settings.parameter_group_name])}"
  }
}

run "reject_same_db_key_across_engines" {
  command = plan
  variables {
    rds_postgres = { app = {} }
    rds_mariadb  = { app = {} }
  }
  expect_failures = [var.rds_mariadb]
}

run "reject_mariadb_replicas_with_managed_password" {
  # MariaDB도 복제본 + RDS 비밀번호 관리 불가 (실계정 확인)
  command = plan
  variables {
    rds_postgres = {}
    rds_mariadb  = { shop = { replicas = { r1 = {} } } }
  }
  expect_failures = [var.rds_master_passwords]
}

run "nlb_dedicated" {
  # 개별 NLB: nlb를 적은 DB(app)만, 리스너 = DB port (원본·대기만, 복제본은 연결 안 함)
  # 대상 등록 기본 = apply (배포 때 Terraform이 등록, 동기화 Lambda 없음)
  command = plan
  variables {
    rds_nlb              = { mode = "dedicated" }
    rds_postgres         = { app = { replicas = { r1 = {} }, nlb = { allowed_cidrs = ["10.10.0.0/16"] } }, etc = {} }
    rds_master_passwords = { app = "Test-Passw0rd-123" }
  }
  assert {
    condition = (
      module.rds_postgres["app"].db.nlb.mode == "dedicated" && module.rds_postgres["app"].db.nlb.port == 5432 &&
      toset(module.rds_postgres["app"].settings.nlb_listener_ports) == toset([5432]) &&
      module.rds_postgres["app"].settings.nlb_target_sync == "apply" &&
      module.rds_postgres["etc"].db.nlb == null &&
      module.rds_common[0].nlb_sync == null && module.rds_common[0].contract.nlb.shared == null
    )
    error_message = "개별 NLB: ${jsonencode([module.rds_postgres["app"].db.nlb, module.rds_postgres["etc"].db.nlb])}"
  }
}

run "nlb_target_sync_lambda_option" {
  # 선택: 동기화 Lambda로 대상 맞춤 (고객 요청 시). Terraform은 대상을 등록하지 않음
  command = plan
  variables {
    rds_nlb      = { mode = "dedicated", target_sync = "lambda" }
    rds_postgres = { app = { nlb = { allowed_cidrs = ["10.10.0.0/16"] } } }
  }
  assert {
    condition     = module.rds_postgres["app"].settings.nlb_target_sync == "lambda" && module.rds_common[0].nlb_sync == "hw-iac-dev-an2-lbd-rdsnlbsync-01"
    error_message = "lambda 방식: ${jsonencode(module.rds_postgres["app"].settings)}"
  }
}

run "reject_unknown_target_sync" {
  command = plan
  variables {
    rds_nlb      = { mode = "dedicated", target_sync = "cron" }
    rds_postgres = { app = { nlb = { allowed_cidrs = ["10.10.0.0/16"] } } }
  }
  expect_failures = [var.rds_nlb]
}

run "nlb_shared" {
  # 통합 NLB: DB마다 리스너 포트(DB port)를 다르게 (orders 3306, shop 3307)
  command = plan
  variables {
    rds_nlb      = { mode = "shared" }
    rds_postgres = {}
    rds_mysql    = { orders = { nlb = { allowed_cidrs = ["10.10.0.0/16"] } } }
    rds_mariadb  = { shop = { port = 3307, nlb = { allowed_cidrs = ["10.10.0.0/16"] } } }
  }
  assert {
    condition     = module.rds_mysql["orders"].db.nlb.mode == "shared" && module.rds_mariadb["shop"].db.nlb.port == 3307
    error_message = "통합 NLB: ${jsonencode([module.rds_mysql["orders"].db.nlb, module.rds_mariadb["shop"].db.nlb])}"
  }
}

run "reject_shared_nlb_port_overlap" {
  # 통합 NLB에 MySQL·MariaDB가 둘 다 3306 → 리스너 포트 충돌
  command = plan
  variables {
    rds_nlb      = { mode = "shared" }
    rds_postgres = {}
    rds_mysql    = { orders = { nlb = { allowed_cidrs = ["10.10.0.0/16"] } } }
    rds_mariadb  = { shop = { nlb = { allowed_cidrs = ["10.10.0.0/16"] } } }
  }
  expect_failures = [var.rds_nlb]
}

run "reject_db_nlb_without_site_mode" {
  # DB에 nlb를 적었는데 사이트 방식(rds_nlb)이 없음
  command = plan
  variables {
    rds_postgres = { app = { nlb = { allowed_cidrs = ["10.10.0.0/16"] } } }
  }
  expect_failures = [var.rds_nlb]
}

run "no_nlb_by_default" {
  command = plan
  assert {
    condition     = module.rds_postgres["app"].db.nlb == null && module.rds_common[0].nlb_sync == null
    error_message = "기본은 NLB 없음이어야 합니다."
  }
}

run "apply_immediately_default_off" {
  # 기본은 유지 관리 시간에 적용, DB별로 바로 적용 가능
  command = plan
  variables {
    rds_postgres = { app = {}, now = { apply_immediately = true } }
  }
  assert {
    condition     = !module.rds_postgres["app"].settings.apply_immediately && module.rds_postgres["now"].settings.apply_immediately
    error_message = "apply_immediately: ${jsonencode([module.rds_postgres["app"].settings.apply_immediately, module.rds_postgres["now"].settings.apply_immediately])}"
  }
}

run "reject_unknown_backup_plan" {
  # 02-shared에 없는 플랜 이름 → 태그만 붙고 백업되지 않으므로 plan에서 막음
  command = plan
  variables {
    rds_postgres = { app = { backup_plans = ["daily", "weekly"] } }
  }
  expect_failures = [output.backup_plan_check]
}

run "aurora_postgres_cluster" {
  # 클러스터 + 쓰기 1 + multi_az 읽기 1(다른 AZ, 우선순위 0) + 읽기 r1, 이름·파라미터 그룹 2개, 비밀번호는 RDS 관리(평문 불필요)
  command = plan
  variables {
    rds_postgres    = {}
    aurora_postgres = { app2 = { multi_az = true, replicas = { r1 = {} }, backup_plans = ["daily", "pitr"] } }
  }
  assert {
    condition = (
      module.aurora_postgres["app2"].settings.cluster_identifier == "hw-iac-dev-an2-rds-cl-apg-app2-01" &&
      module.aurora_postgres["app2"].settings.instances["w"].identifier == "hw-iac-dev-an2-rds-apg-app2-01" &&
      module.aurora_postgres["app2"].settings.instances["__multi_az"].identifier == "hw-iac-dev-an2-rds-apg-app2-02" &&
      module.aurora_postgres["app2"].settings.instances["__multi_az"].tier == 0 &&
      module.aurora_postgres["app2"].settings.instances["__multi_az"].az != module.aurora_postgres["app2"].settings.instances["w"].az &&
      module.aurora_postgres["app2"].settings.instances["r1"].identifier == "hw-iac-dev-an2-rds-apg-app2-03" &&
      module.aurora_postgres["app2"].settings.parameter_group_name == "hw-iac-dev-an2-rds-pagrp-apg16-app2-01" &&
      module.aurora_postgres["app2"].settings.cluster_parameter_group_name == "hw-iac-dev-an2-rds-cpar-apg16-app2-01" &&
      module.aurora_postgres["app2"].settings.parameter_group_family == "aurora-postgresql16" &&
      jsonencode(module.aurora_postgres["app2"].settings.backup_tags) == jsonencode({ Backup-daily = "true", Backup-pitr = "true" }) &&
      toset(values(module.aurora_postgres["app2"].log_groups)) == toset(["/aws/rds/cluster/hw-iac-dev-an2-rds-cl-apg-app2-01/postgresql"])
    )
    error_message = "Aurora: ${jsonencode(module.aurora_postgres["app2"].settings)}"
  }
}

run "aurora_mysql_serverless" {
  # Serverless v2: 인스턴스는 db.serverless, family aurora-mysql8.0
  command = plan
  variables {
    rds_postgres = {}
    aurora_mysql = { orders2 = { serverless_v2 = { min_acu = 0.5, max_acu = 4 } } }
  }
  assert {
    condition = (
      module.aurora_mysql["orders2"].settings.instances["w"].instance_class == "db.serverless" &&
      module.aurora_mysql["orders2"].settings.parameter_group_family == "aurora-mysql8.0" &&
      module.aurora_mysql["orders2"].settings.cluster_identifier == "hw-iac-dev-an2-rds-cl-amy-orders2-01" &&
      module.aurora_mysql["orders2"].db.port == 3306
    )
    error_message = "Aurora MySQL: ${jsonencode(module.aurora_mysql["orders2"].settings)}"
  }
}

run "aurora_nlb_writer_only" {
  # Aurora NLB: 쓰기 인스턴스 하나만. 기본 apply = 배포 때 쓰기 인스턴스 주소 IP 등록, lambda = 쓰기 주소(DNS) 태그로 동기화
  command = plan
  variables {
    rds_nlb         = { mode = "dedicated" }
    rds_postgres    = {}
    aurora_postgres = { app2 = { replicas = { r1 = {} }, nlb = { allowed_cidrs = ["10.10.0.0/16"] } } }
  }
  assert {
    condition     = module.aurora_postgres["app2"].db.nlb.mode == "dedicated" && module.aurora_postgres["app2"].settings.nlb_target_sync == "apply" && module.rds_common[0].nlb_sync == null
    error_message = "Aurora NLB: ${jsonencode(module.aurora_postgres["app2"].db.nlb)}"
  }
}

run "aurora_nlb_lambda_option" {
  command = plan
  variables {
    rds_nlb         = { mode = "dedicated", target_sync = "lambda" }
    rds_postgres    = {}
    aurora_postgres = { app2 = { nlb = { allowed_cidrs = ["10.10.0.0/16"] } } }
  }
  assert {
    condition     = module.aurora_postgres["app2"].settings.nlb_target_sync == "lambda" && module.rds_common[0].nlb_sync == "hw-iac-dev-an2-lbd-rdsnlbsync-01"
    error_message = "Aurora NLB lambda: ${jsonencode(module.aurora_postgres["app2"].settings)}"
  }
}

run "reject_same_key_rds_and_aurora" {
  command = plan
  variables {
    rds_postgres    = { app = {} }
    aurora_postgres = { app = {} }
  }
  expect_failures = [var.aurora_mysql]
}

############################################################
# DB 목록 CSV (src/databases.csv)
############################################################
run "csv_creates_dbs" {
  # CSV만으로 RDS·Aurora 생성. backup = true → daily + pitr, replica = true → 같은 사양 복제본 하나
  command = plan
  variables {
    rds_postgres         = {}
    rds_nlb              = { mode = "dedicated" }
    rds_master_passwords = { app = "Test-Passw0rd-123" }
    databases_csv        = "﻿no,name,engine,engine_version,instance_class,storage,max_storage,multi_az,db_name,port,backup,snapshot_identifier,replica,nlb_allowed_cidrs,nlb_private_ips,memo\r\n1,app,postgres,16,db.t4g.medium,50,200,true,app,,true,,true,,,업무\r\n2,core,aurora_postgres,,serverless:0.5-2,,,,core,,TRUE,,,10.10.0.0/16;10.20.0.0/16,a=10.227.0.200,고정 IP\r\n"
  }
  assert {
    condition = (
      module.rds_postgres["app"].settings.multi_az == true &&
      module.rds_postgres["app"].settings.backup_tags == { "Backup-daily" = "true", "Backup-pitr" = "true" } &&
      length(module.rds_postgres["app"].replicas) == 1 &&
      module.aurora_postgres["core"].settings.instances["w"].instance_class == "db.serverless" &&
      module.aurora_postgres["core"].settings.nlb_target_sync == "apply" &&
      module.aurora_postgres["core"].db.nlb != null &&
      output.databases_csv_check == ["app", "core"]
    )
    error_message = "CSV DB: ${jsonencode(module.rds_postgres["app"].settings)} / ${jsonencode(module.aurora_postgres["core"].settings)}"
  }
}

run "csv_matches_tfvars_defaults" {
  # CSV 기본값이 tfvars(optional 기본값)와 같아야 함 (빈칸만 있는 행 = tfvars {} )
  command = plan
  variables {
    rds_postgres    = { t = {} }
    aurora_postgres = { ta = {} }
    databases_csv   = "no,name,engine\n1,u,postgres\n2,ua,aurora_postgres\n"
  }
  assert {
    condition     = jsonencode(local.rds_postgres["t"]) == jsonencode(local.rds_postgres["u"])
    error_message = "RDS 기본값 차이: tfvars ${jsonencode(local.rds_postgres["t"])} / CSV ${jsonencode(local.rds_postgres["u"])}"
  }
  assert {
    condition     = jsonencode(local.aurora_postgres["ta"]) == jsonencode(local.aurora_postgres["ua"])
    error_message = "Aurora 기본값 차이: tfvars ${jsonencode(local.aurora_postgres["ta"])} / CSV ${jsonencode(local.aurora_postgres["ua"])}"
  }
}

run "reject_csv_replica_without_password" {
  command = plan
  variables {
    rds_postgres  = {}
    databases_csv = "no,name,engine,replica\n1,app,postgres,true\n"
  }
  expect_failures = [output.databases_csv_check]
}

run "reject_csv_nlb_without_site_mode" {
  command = plan
  variables {
    rds_postgres  = {}
    databases_csv = "no,name,engine,nlb_allowed_cidrs\n1,app,postgres,10.10.0.0/16\n"
  }
  expect_failures = [output.databases_csv_check]
}

run "reject_bad_csv_rows" {
  # 행 검사 (helper 모듈 직접): 엔진, 키 중복, Aurora 저장소, 버전, Serverless 범위, 고정 IP 형식, tfvars와 같은 키
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_rds_databases_csv" }
  variables {
    region        = "ap-northeast-2"
    existing_keys = ["dup"]
    csv           = "no,name,engine,engine_version,instance_class,storage,nlb_allowed_cidrs,nlb_private_ips\n1,a,oracle,,,,,\n1,b,aurora_mysql,,,50,,\n3,c,postgres,v16,,,,\n4,d,aurora_postgres,,serverless:4-1,,,\n5,e,postgres,,,,10.0.0.0/16,a:10.0.0.1\n6,dup,postgres,,,,,\n"
  }
  expect_failures = [output.databases]
}

run "csv_bad_rows_listed" {
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_rds_databases_csv" }
  variables {
    region = "ap-northeast-2"
    csv    = "no,name,engine,storage\n1,a,oracle,\n1,b,aurora_mysql,50\n"
  }
  expect_failures = [output.databases]
  assert {
    condition     = length(output.errors) == 2 && strcontains(join(" ", output.errors), "2행(a): engine") && strcontains(join(" ", output.errors), "3행(b): Aurora는 storage")
    error_message = "오류 목록: ${jsonencode(output.errors)}"
  }
}

run "csv_example_file_valid" {
  # src/databases.example.csv 예제가 형식에 맞는지 (복사해서 쓰는 예제라 항상 통과해야 함)
  command = plan
  module { source = "../../aws-iac-terraform-module/module/_rds_databases_csv" }
  variables {
    region = "ap-northeast-2"
    csv    = file("src/databases.example.csv")
  }
  assert {
    condition     = length(output.errors) == 0 && output.databases["core"].nlb.private_ips == { "ap-northeast-2a" = "10.227.0.200", "ap-northeast-2c" = "10.227.1.200" } && output.databases["orders"].serverless_v2 == { min_acu = 0.5, max_acu = 2 }
    error_message = "예제 CSV: ${jsonencode(output.errors)}"
  }
}
