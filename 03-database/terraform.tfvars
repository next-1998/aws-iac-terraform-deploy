############################################################
# 03-database — 사이트: simple (예시 값. 실제 값으로 바꿔서 사용)
# 01-network를 먼저 apply해야 합니다 (Parameter Store 값을 읽음). 03-compute와는 순서 상관없음 (병렬 가능).
# 구성할 수 있는 항목을 모두 적어 두었습니다. 값이 기본값과 같은 항목은 지워도 동작은 같습니다.
#
# [구축 전 협의 항목]
#   항목                     협의 대상            값
#     DB 엔진·버전           고객 (서비스 담당)   rds.<용도>.engine, engine_version (postgres | mysql)
#     사양·저장소            고객 (서비스 담당)   instance_class, allocated_storage, max_allocated_storage
#     이중화 (Multi-AZ)      고객 운영팀          multi_az (기본: operation_mode = "enable"이면 켬. 비용 약 2배)
#     백업 보관              고객 운영팀          backup_retention_days (기본 7일)
#     접근 허용              고객 보안팀          allowed_cidrs (기본 EC2 서브넷 대역), 추가는 deployment/rds-db/src/rds-<용도>.sg_rules.csv
#     DB 로그·보관           고객 보안팀          log_exports, log_retention_days (CloudWatch. S3에는 계정 로그 정책으로 더 오래)
#     DB 파라미터            고객 (서비스·DBA)    deployment/rds-db/src/rds-<용도>.parameters.csv (엔진 기본값에서 바꿀 값만)
#     관리자 비밀번호        고객 보안팀          RDS가 Secrets Manager에 만들고 관리 (비밀번호를 tfvars에 넣지 않음)
#                                                 PostgreSQL 읽기 복제본을 쓰면 rds_master_passwords 평문 (test.tfvars에만)
#                                                  애플리케이션은 출력의 secret_arn으로 읽음. 폐쇄망이면 01-network에 secretsmanager endpoint 필요
#     암호화 키 (CMK)        고객 보안팀          central_kms_key_arns.rds (없으면 이 계정에 RDS 키 생성)
#     스냅샷 복원·복제본     고객 (서비스·DBA)    rds.<용도>.snapshot_identifier (기존 DB 이전·골든 이미지), replicas (읽기 부하 분산)
#     삭제 보호              고객 운영팀          operation_mode, deletion_protection.rds (보호 시 삭제 방지 + 최종 스냅샷)
############################################################

# ── 사이트 (모든 단계 같은 값) ────────────────────────────────
site        = "simple"
environment = "dev"
region      = "ap-northeast-2"
common_tags = {}

# ── RDS (용도 이름 → 설정). DB identifier는 <site>-rds-<용도> ───
# 비우면({}) DB를 만들지 않습니다. 용도 이름은 바꾸지 않는 값 (바꾸면 DB가 새로 만들어짐)
rds = {
  app = {
    engine                = "postgres"     # postgres | mysql
    engine_version        = "16"           # 주 버전 (postgres 16, mysql 8.0). 부 버전은 만들 때 기본값, 이후 자동으로 안 바뀜
    instance_class        = "db.t4g.micro" # 기본 db.t4g.micro
    allocated_storage     = 20             # GiB (gp3)
    max_allocated_storage = 100            # 저장소 자동 확장 상한 (allocated_storage와 같으면 자동 확장 끔)
    db_name               = "app"          # 처음 만들 DB 이름 (null이면 만들지 않음)
    username              = "dbadmin"      # 마스터 사용자 (비밀번호는 Secrets Manager)
    # port                = 5432           # null이면 엔진 기본 (postgres 5432, mysql 3306)
    # multi_az            = true           # null이면 operation_mode = "enable"일 때만 켬 (DB별로 true/false 지정 가능)
    backup_retention_days      = 7      # 자동 백업 보관 일수
    performance_insights       = false  # 일부 작은 클래스는 지원 안 함
    monitoring_interval        = 60     # 향상된 모니터링 간격(초): 0(끔), 1, 5, 10, 15, 30, 60. 복제본도 같음
    auto_minor_version_upgrade = false  # 마이너 버전 자동 업그레이드 (기본 끔. 올릴 때는 engine_version을 바꿔 apply)
    backup_plan                = "pitr" # AWS Backup 플랜 (02-shared backup_plans). 태그 Backup = pitr → 시점 복구 + 일간 스냅샷. null이면 RDS 자동 백업만
    # log_exports         = ["postgresql", "upgrade"]  # null이면 엔진 기본 (mysql: error, slowquery)
    log_retention_days = 14 # DB 로그 CloudWatch 보관 일수
    # allowed_cidrs      = ["10.227.0.128/26"]          # null이면 EC2 서브넷 대역 전체

    # 스냅샷(DB "이미지")으로 만들기: 처음 한 번만 적용 (이후 바꿔도 DB를 다시 만들지 않음, 바꾸려면 -replace)
    #   엔진·버전·db_name·username은 스냅샷 값을 따르고, 비밀번호는 복원 뒤 Secrets Manager 관리로 바뀜
    #   다른 키로 암호화된 스냅샷은 RDS 키로 복사한 스냅샷을 지정 (다른 계정이면 스냅샷·키 공유 필요)
    # snapshot_identifier = "app-golden-2026-11"   # 또는 arn:aws:rds:<리전>:<계정>:snapshot:<이름>

    # 읽기 복제본 (키 → 설정). 이름은 <site>-rds-app-<키>, 원본과 같은 SG·파라미터·키. 원본 자동 백업이 켜져 있어야 함
    #   PostgreSQL 복제본은 RDS 비밀번호 관리와 같이 쓸 수 없어 rds_master_passwords가 필요 (아래)
    replicas = {
      # r1 = {}                                   # 원본과 같은 사양
      # r2 = { instance_class = "db.t4g.small" }  # 사양만 다르게
    }
    # 파라미터 그룹 값: 보통은 CSV로 넣음 → deployment/rds-db/src/rds-app.parameters.csv (열: no,name,value,apply_method,memo)
    #   예제: deployment/rds-db/src/parameters.example.csv. 여기(parameters)에 넣어도 되지만 CSV와 둘 다 넣으면 plan에서 막힘
    # parameters = [{ name = "log_min_duration_statement", value = "1000", apply_method = "immediate" }]
  }
}

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
# 넣은 DB는 RDS 비밀번호 관리(Secrets Manager)를 끄고 이 값을 씁니다. PostgreSQL 읽기 복제본을 쓰는 DB는 필수
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
