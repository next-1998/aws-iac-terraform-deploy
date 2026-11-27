############################################################
# 03-database — 사이트: simple (예시 값. 실제 값으로 바꿔서 사용)
# 01-network를 먼저 apply해야 합니다 (Parameter Store 값을 읽음). 03-compute와는 순서 상관없음 (병렬 가능).
# 구성할 수 있는 항목을 모두 적어 두었습니다. 값이 기본값과 같은 항목은 지워도 동작은 같습니다.
#
# [구축 전 협의 항목]
#   항목                     협의 대상            값
#   ★ DB 서브넷 CIDR         고객 네트워크팀      db_subnet_cidrs (설계서 값. 비우면 01-network 배치 규칙, 01-network 공용 서브넷 use = db가 있으면 그것)
#     DB 엔진·버전           고객 (서비스 담당)   엔진별 목록 rds_postgres | rds_mysql | rds_mariadb | aurora_postgres | aurora_mysql, engine_version (RDS·Aurora 선택)
#     사양·저장소            고객 (서비스 담당)   instance_class, allocated_storage, max_allocated_storage
#     이중화 (Multi-AZ)      고객 운영팀          multi_az (기본: operation_mode = "enable"이면 켬. 비용 약 2배)
#     백업 보관              고객 운영팀          backup_retention_days (기본 7일)
#     접근 허용              고객 보안팀          allowed_cidrs (기본 EC2 서브넷 대역), 추가는 deployment/rds-<엔진>/src/rds-<DB 키>.sg_rules.csv
#     DB 로그·보관           고객 보안팀          log_exports, log_retention_days (CloudWatch. S3에는 계정 로그 정책으로 더 오래)
#     DB 파라미터            고객 (서비스·DBA)    deployment/rds-<엔진>/src/rds-<DB 키>.parameters.csv (엔진 기본값에서 바꿀 값만)
#     관리자 비밀번호        고객 보안팀          RDS가 Secrets Manager에 만들고 관리 (비밀번호를 tfvars에 넣지 않음)
#                                                 읽기 복제본을 쓰면 rds_master_passwords 평문 (엔진 무관, test.tfvars에만)
#                                                  애플리케이션은 출력의 secret_arn으로 읽음. 폐쇄망이면 01-network에 secretsmanager endpoint 필요
#     암호화 키 (CMK)        고객 보안팀          central_kms_key_arns.rds (없으면 이 계정에 RDS 키 생성)
#     스냅샷 복원·복제본     고객 (서비스·DBA)    <엔진 목록>.<DB 키>.snapshot_identifier (기존 DB 이전·골든 이미지), replicas (읽기 부하 분산)
#     삭제 보호              고객 운영팀          operation_mode, deletion_protection.rds (보호 시 삭제 방지 + 최종 스냅샷)
#     DB 고정 IP (NLB)       고객 보안팀·DBA      rds_nlb (개별/통합 방식, 고정 IP), <엔진 목록>.<DB 키>.nlb (연결할 DB, 허용 대역. 원본·대기만)
############################################################

# ── 사이트 (모든 단계 같은 값) ────────────────────────────────
site        = "simple"
environment = "dev"
region      = "ap-northeast-2"
common_tags = {}

# ── DB 서브넷 ─────────────────────────────────────────────────
# null(기본): 01-network 배치 규칙 계산값. 01-network shared_subnets에 use = ["db", …] 서브넷이 있으면 그 서브넷을 씀
# 설계서가 있으면 AZ 끝 글자 → CIDR. vpc_cidrs 안, 기존 서브넷과 겹치면 plan에서 막힘
# DB 접근 기본 허용: 배치 규칙의 EC2 대역 + 태그 Access-db = true 서브넷 (03-compute ec2_subnet_access). 03-compute를 먼저 배포
db_subnet_cidrs = null

# ── RDS: 엔진별 목록 (DB 키 → 설정) ───────────────────────────
# DB 목록은 CSV로도 넣을 수 있습니다: 03-database/src/databases.csv (열 설명: src/README.md, 예: src/databases.example.csv)
#   CSV는 자주 정하는 값만 (엔진·버전·사양·저장소·Multi-AZ·백업 여부·스냅샷·복제본 여부·NLB). 그 밖의 설정이 필요한 DB는 여기 tfvars로
#   한 DB는 tfvars나 CSV 한 곳에만 (같은 키면 plan에서 막힘)
# 이름: DB <접두어>-rds-<엔진 코드>-<DB 키>-01 (엔진 코드 pg | my | mdb), 복제본 …-<DB 키>-ro-01, 파라미터 그룹 <접두어>-rds-pagrp-<엔진·주버전>-<DB 키>-01
# 비우면({}) 그 엔진 DB를 만들지 않습니다. DB 키는 소문자·숫자 12자 이하, 엔진이 달라도 겹치면 안 됨. 바꾸면 DB가 새로 만들어짐
# 엔진별 설정 항목은 모두 같습니다 (아래 rds_postgres 예시 참고). 엔진 전용 예제·CSV: deployment/rds-<엔진>/src/
rds_postgres = {
  app = {
    engine_version        = "16"           # 주 버전 (예: 16). 부 버전은 만들 때 기본값, 이후 자동으로 안 바뀜
    instance_class        = "db.t4g.micro" # 기본 db.t4g.micro
    allocated_storage     = 20             # GiB (gp3)
    max_allocated_storage = 100            # 저장소 자동 확장 상한 (allocated_storage와 같으면 자동 확장 끔)
    db_name               = "app"          # 처음 만들 DB 이름 (null이면 만들지 않음)
    username              = "dbadmin"      # 마스터 사용자 (비밀번호는 Secrets Manager)
    # port                = 5432           # null이면 엔진 기본 (postgres 5432)
    # multi_az            = true           # null이면 operation_mode = "enable"일 때만 켬 (DB별로 true/false 지정 가능)
    backup_retention_days      = 7                 # 자동 백업 보관 일수
    performance_insights       = false             # 일부 작은 클래스는 지원 안 함
    monitoring_interval        = 60                # 향상된 모니터링 간격(초): 0(끔), 1, 5, 10, 15, 30, 60. 복제본도 같음
    auto_minor_version_upgrade = false             # 마이너 버전 자동 업그레이드 (기본 끔. 올릴 때는 engine_version을 바꿔 apply)
    apply_immediately          = false             # 변경을 바로 적용. 기본 false: Multi-AZ·인스턴스 클래스·파라미터 그룹 변경은 다음 유지 관리 시간에 적용 (운영 권장)
    backup_plans               = ["daily", "pitr"] # AWS Backup 플랜 (02-shared backup_plans). 02-shared에 없는 이름이면 plan에서 막힘. 태그 Backup-daily, Backup-pitr = true (일간 스냅샷 + 시점 복구). 빈 목록이면 RDS 자동 백업만
    # log_exports         = ["postgresql", "upgrade"]  # null이면 엔진 기본 (postgresql, upgrade)
    log_retention_days = 14 # DB 로그 CloudWatch 보관 일수
    # allowed_cidrs      = ["10.227.0.128/26"]          # null이면 EC2 서브넷 대역 전체

    # 스냅샷(DB "이미지")으로 만들기: 처음 한 번만 적용 (이후 바꿔도 DB를 다시 만들지 않음, 바꾸려면 -replace)
    #   엔진·버전·db_name·username은 스냅샷 값을 따르고, 비밀번호는 복원 뒤 Secrets Manager 관리로 바뀜
    #   다른 키로 암호화된 스냅샷은 RDS 키로 복사한 스냅샷을 지정 (다른 계정이면 스냅샷·키 공유 필요)
    # snapshot_identifier = "app-golden-2026-11"   # 또는 arn:aws:rds:<리전>:<계정>:snapshot:<이름>

    # 읽기 복제본 (키 → 설정). 이름은 <접두어>-rds-pg-app-ro-01, -02 … (키 이름순), 원본과 같은 SG·파라미터·키. 원본 자동 백업이 켜져 있어야 함
    #   읽기 복제본은 RDS 비밀번호 관리와 같이 쓸 수 없어 rds_master_passwords가 필요 (엔진 무관, 아래)
    replicas = {
      # r1 = {}                                   # 원본과 같은 사양
      # r2 = { instance_class = "db.t4g.small" }  # 사양만 다르게
    }
    # NLB 연결 (선택, 기본 없음): 고객 DB 접근제어가 IP로만 허용할 때 고정 IP 용도. 쓰기 리스너 포트 = DB port
    #   개별/통합 방식은 아래 rds_nlb.mode (사이트에서 하나). 통합이면 연결한 DB끼리 port가 겹치면 plan에서 막힘
    #   원본·대기(Multi-AZ)만 연결하고 읽기 복제본은 연결하지 않음
    #   고정 IP는 출력 rds.<DB 키>.nlb.private_ips (고객 접근제어에 등록). 대상 등록 방법은 아래 rds_nlb.target_sync
    # nlb = { allowed_cidrs = ["10.10.0.0/16"] } # private_ips = { "ap-northeast-2a" = "…" } (개별 NLB만)
    # 파라미터 그룹 값: 보통은 CSV로 넣음 → deployment/rds-postgres/src/rds-app.parameters.csv (열: no,name,value,apply_method,memo)
    #   예제: deployment/rds-postgres/src/parameters.example.csv. 여기(parameters)에 넣어도 되지만 CSV와 둘 다 넣으면 plan에서 막힘
    # parameters = [{ name = "log_min_duration_statement", value = "1000", apply_method = "immediate" }]
  }
}

# MySQL (기본 버전 8.0, 포트 3306, 기본 로그 error·slowquery). 항목은 rds_postgres와 같음. CSV: deployment/rds-mysql/src/
rds_mysql = {
  # orders = { engine_version = "8.0", db_name = "orders", backup_plans = ["daily", "pitr"] }
}

# MariaDB (기본 버전 10.11, 포트 3306, 기본 로그 error·slowquery, general·audit 선택). 항목은 rds_postgres와 같음. CSV: deployment/rds-mariadb/src/
rds_mariadb = {
  # shop = { engine_version = "10.11", db_name = "shop", backup_plans = ["daily", "pitr"] }
}

# ── Aurora (클러스터) ─────────────────────────────────────────
# 항목은 RDS(rds_postgres 등)와 같은 이름입니다. Aurora라서 다른 것:
#   - 용량 항목(allocated_storage 등) 없음 (저장소 자동 확장). instance_class 최소 db.t4g.medium
#   - serverless_v2 = { min_acu, max_acu } 를 넣으면 Serverless v2 (instance_class 무시)
#   - storage_type = "aurora"(기본) | "aurora-iopt1"(I/O 포함 요금)
#   - multi_az = true → 다른 AZ에 장애 조치용 읽기 인스턴스, replicas → 읽기 인스턴스 추가 (모두 클러스터 안)
#   - 비밀번호는 RDS가 Secrets Manager로 관리 (읽기 인스턴스가 있어도 rds_master_passwords 불필요)
#   - 파라미터 CSV 두 개: deployment/aurora-<엔진>/src/rds-<DB 키>.cluster-parameters.csv, rds-<DB 키>.parameters.csv
#   - nlb = { allowed_cidrs } → 쓰기 인스턴스만 연결 (쓰기 주소 DNS 기준, 장애 조치 뒤 1분 안에 대상 교체)
# 이름: 클러스터 <접두어>-rds-cl-<apg|amy>-<DB 키>-01, 인스턴스 …-rds-<apg|amy>-<DB 키>-01, -02 … (순번만. 장애 조치로 쓰기·읽기가 바뀌어 ro를 붙이지 않음)
# 출력: rds.<DB 키>.address = 쓰기 주소, reader_address = 읽기 주소. DB 키는 RDS·Aurora 전체에서 겹치면 안 됨
aurora_postgres = {
  # app2 = {
  #   engine_version = "16"
  #   instance_class = "db.t4g.medium"
  #   # serverless_v2 = { min_acu = 0.5, max_acu = 4 }
  #   db_name        = "app2"
  #   multi_az       = true
  #   backup_plans   = ["daily", "pitr"]
  #   replicas       = { r1 = {} }
  # }
}

aurora_mysql = {
  # orders2 = { engine_version = "8.0", db_name = "orders" }
}

# ── RDS NLB (고정 IP 용도, 특수 상황에만) ─────────────────────
# null(기본)이면 NLB를 만들지 않습니다. 켜면 DB 설정에 nlb = { allowed_cidrs }를 적은 DB만 연결 (원본·대기만, 읽기 복제본은 연결 안 함)
#   mode = "dedicated" : DB마다 개별 NLB (<접두어>-nlb-rds<DB 키>-01). DB별 고정 IP는 nlb.private_ips
#   mode = "shared"    : 사이트 통합 NLB 하나 (<접두어>-nlb-rds-01)에 DB마다 리스너(DB port). 고정 IP는 private_ips
#   한 사이트에서 섞어 쓰지 않습니다. 고정 IP는 출력 rds.<DB 키>.nlb.private_ips (고객 접근제어에 등록)
#   target_sync = NLB 대상(DB IP)을 맞추는 방법 (고객과 협의)
#     "apply" (기본) : 배포 때 Terraform이 지금 원본(쓰기) 인스턴스 IP 하나를 등록. Lambda 없음
#                      장애 조치·유지 관리로 IP가 바뀌면 03-database를 다시 apply (그 전까지 NLB는 이전 IP로 보냄)
#     "lambda"       : 동기화 Lambda가 1분마다 + 클러스터 장애 조치 때 바로 맞춤 (자동, 운영 관리 대상 늘어남)
#                      RDS는 원본 + 대기 IP를 모두 넣어 장애 조치도 상태 확인이 자동 처리
#                      폐쇄망이면 01-network에 ec2, elasticloadbalancing endpoint 필요
rds_nlb = null
# rds_nlb = { mode = "dedicated", target_sync = "lambda" }
# rds_nlb = { mode = "shared", private_ips = { "ap-northeast-2a" = "10.227.0.200", "ap-northeast-2c" = "10.227.1.200" } }

# RDS 키 관리자 (비우면 계정 root 정책으로만 관리)
kms_key_administrators = []

# ── 암호화 키 (CMK) ───────────────────────────────────────────
# RDS 키: central_kms_key_arns.rds가 있으면 그 키, 없으면 이 단계가 RDS 전용 키를 만듭니다.
# 같은 tfvars 값을 여러 단계가 같이 쓸 수 있도록 변수만 받습니다.
# 조직 중앙 계정의 CMK를 쓰면 용도별로 키 ARN을 넣습니다 (넣은 용도는 키를 만들지 않음).
#   - 용도: ebs, s3, logs (00-bootstrap) / sns (02-shared) / tfstate (00-bootstrap 분리 옵션) / rds, secrets, backup (추가 예정)
#   - alias가 아니라 키 ARN이어야 합니다 (다른 계정 alias는 쓸 수 없음). 이 단계와 같은 리전의 키여야 합니다
#   - 중앙 키 정책에 이 계정과 서비스 사용 권한이 있어야 합니다 (중앙 계정 사전 요청)
#   - 중앙 키 하나로 모든 용도를 쓰지 말고 용도별로 분리하세요
central_kms_key_arns = {
  # ebs  = "arn:aws:kms:ap-northeast-2:<중앙 계정>:key/<키 ID>"
  # s3   = "arn:aws:kms:ap-northeast-2:<중앙 계정>:key/<키 ID>"
  # logs = "arn:aws:kms:ap-northeast-2:<중앙 계정>:key/<키 ID>"
  # sns  = "arn:aws:kms:ap-northeast-2:<중앙 계정>:key/<키 ID>"
  # rds  = "arn:aws:kms:ap-northeast-2:<중앙 계정>:key/<키 ID>"  # 이 단계에서 사용
}

# ── 마스터 비밀번호 평문 (선택) ────────────────────────────────
# 넣은 DB는 RDS 비밀번호 관리(Secrets Manager)를 끄고 이 값을 씁니다. 읽기 복제본을 쓰는 DB는 필수 (엔진 무관)
# 비밀번호가 평문으로 tfvars·state에 남습니다. 이 파일(커밋됨)에는 넣지 말고 test.tfvars(커밋 안 함)에만 넣으세요
# rds_master_passwords = { app = "<8~128자, 슬래시·큰따옴표·@·공백 제외>" }

# ── 운영 모드 (삭제 보호) ─────────────────────────────────────
# operation_mode = "enable" : 운영. 버킷·KMS 키·NAT EIP 삭제 불가, KMS 삭제 대기 30일, ALB 삭제 보호, EC2 볼륨은 서버 삭제 후에도 남김, RDS 삭제 보호(최종 스냅샷)·Multi-AZ, 백업 볼트 보존
# 그 외(null, 기본)         : 모두 삭제 가능 (테스트처럼 만들고 지우는 환경)
# 처음 배포할 때 정하고 바꾸지 않습니다 (바꾸면 버킷·KMS 키·EIP가 새로 만들어짐). 모든 단계에 같은 값을 넣습니다
operation_mode = null

# 항목별 선택 (비우면 operation_mode를 따름. true = 삭제 불가, false = 삭제 가능)
deletion_protection = {
  # buckets     = true # state·로그 버킷 (00-bootstrap)
  # kms_keys    = true # KMS 키 (00-bootstrap, 02-shared)
  # nat_eip     = true # NAT EIP (01-network)
  # alb         = true # ALB 삭제 보호 (03-compute)
  # ec2_volumes = true # 서버 삭제 후 EBS 볼륨 유지 (03-compute)
  # rds         = true # RDS 삭제 보호 + 삭제 시 최종 스냅샷 (03-database)
  # backups     = true # 백업 볼트 삭제 불가·남은 백업 보존 (02-shared)
}
