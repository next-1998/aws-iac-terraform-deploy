############################################################
# 03-compute — 사이트: simple (예시 값. 실제 값으로 바꿔서 사용)
# 01-network, 02-shared를 먼저 apply해야 합니다 (Parameter Store 값을 읽음).
# 구성할 수 있는 항목을 모두 적어 두었습니다. 값이 기본값과 같은 항목은 지워도 동작은 같습니다.
#
# [구축 전 협의 항목]
#   항목                     협의 대상            값
#     암호화 키 (CMK)        고객 보안팀          central_kms_key_arns (조직 중앙 CMK를 쓸지, 쓰면 용도별 키 ARN)
#     SG 규칙 (접근 경로)    고객 보안팀          deployment/ec2-*/src/sg_rules.csv (포트, 출발지 prefix list)
#     서버 이미지 (AMI)      고객 보안/플랫폼     was/webide.ami (커스텀 이미지, 공유·암호화 키, 루트 볼륨 크기)
#     서버 사양              고객 (서비스 담당)   was/webide.instance_type, root_volume_size, ebs_volumes
#     서비스 포트·헬스체크   고객 (서비스 담당)   app_port, health_check_path
#     LB 공개 범위           고객 보안팀          enable_alb, alb_internal (외부용은 01-network enable_public 필요)
#     서비스 도메인 이름     고객 DNS 담당        alb_record_name
#     WAF                    고객 보안팀          외부용 LB에 붙일 Web ACL (필요 시 main.tf에서 ec2-<용도>의 waf_acl_arn으로 넘김)
#     주말 중지 대상·시간    고객 운영팀          ec2_weekend_stop, was/webide.weekend_stop_enable
#     접근 로그              고객 보안팀          enable_alb_access_logs, central_log_bucket_arn
#     로그 최종 보관 기간    고객 보안팀          00-bootstrap log_retention_days (S3, 기본 365일. CloudWatch는 14일)
#     삭제 보호 (운영 모드)  고객 운영팀          operation_mode, deletion_protection
############################################################

# ── 사이트 (모든 단계 같은 값) ────────────────────────────────
site        = "simple"         # 소문자·숫자·'-', 20자 이하. 리소스 이름 접두어, 태그, Parameter Store 경로
environment = "dev"            # dev | stg | prod
region      = "ap-northeast-2" # 기본 ap-northeast-2

# 사이트 공통 선택 태그 (Owner, CostCenter 등). 고정 태그 키는 넣을 수 없음
common_tags = {}

# ── 로그 ──────────────────────────────────────────────────────
# ALB 접근 로그 저장 여부 (기본 true)
enable_alb_access_logs = true

# 중앙 로그 계정 버킷 ARN. null(기본)이면 이 계정의 00-bootstrap 로그 버킷
central_log_bucket_arn = null
# central_log_bucket_arn = "arn:aws:s3:::<중앙 로그 버킷>"

# ── 보안 그룹 규칙 (CSV) ──────────────────────────────────────
# SG 규칙은 tfvars가 아니라 그 SG를 만드는 폴더의 src/sg_rules.csv에 넣습니다.
#   공통 SG(서버 접근)  : deployment/ec2-common/src/sg_rules.csv   (sg 열: common)
#   용도별 SG, ALB SG   : deployment/ec2-<용도>/src/sg_rules.csv   (sg 열: app, alb)
# 서비스에 꼭 필요한 기본 규칙은 코드에 이미 있고, CSV에는 협의한 추가 규칙만 넣습니다.

# ── 서버 이미지 (AMI) ────────────────────────────────────────
# 보안 기준상 보통 공개 이미지가 아니라 고객사 커스텀 이미지(골든 AMI)를 씁니다. 서버마다 다른 이미지를 넣을 수 있습니다.
# 협의 항목 (고객 보안/플랫폼 담당)
#   - 서버별 AMI ID (이 계정·리전 기준. 다른 계정 이미지는 이 계정에 공유되어 있어야 함)
#   - 이미지가 고객 CMK로 암호화되어 있으면: 그 키를 이 계정이 쓸 수 있게 키 정책 공유 (없으면 서버 생성 실패)
#   - 이미지 루트 볼륨 크기 (root_volume_size는 이미지 크기 이상이어야 함)
#   - 이미지에 포함된 데이터 볼륨: 이미지대로 만들어지고 Terraform은 관리하지 않음 (증설 등은 AWS에서 직접)
#     권장: 이미지에는 OS(루트)만 넣고 데이터 볼륨은 아래 ebs_volumes로 추가
#   - OS (Agent 설치 스크립트는 Amazon Linux/RHEL 계열, Ubuntu/Debian 계열 지원. 이미지에 Agent가 있으면 설치는 건너뜀)
# 이미지를 바꿔도 이미 떠 있는 서버는 교체되지 않습니다 (새로 만드는 서버에만 적용).
# 새 이미지로 바꾸려면 의도적으로: terraform apply -replace='module.ec2_was[0].module.ec2.aws_instance.vm'

# ── WAS ───────────────────────────────────────────────────────
was = {
  enabled          = true                    # false면 WAS 서버와 관련 리소스(SG, ALB 등)를 만들지 않음
  ami              = "ami-05377cf8cfef186c2" # (필수) 이 서버의 AMI ID (커스텀 이미지)
  instance_type    = "t3.micro"              # 기본 t3.micro
  root_volume_size = 30                      # 루트 볼륨 GB (기본 30, 이미지 크기 이상)
  # 데이터 볼륨 (기본 없음). 서버를 만든 뒤 따로 만들어 붙임. volume_type 기본 gp3
  #   크기는 여기서만 바꿈 (서버 교체 없이 늘어남, 줄일 수 없음). 장치 이름을 바꾸면 볼륨이 다시 만들어짐
  #   마운트 (mount_point가 있는 볼륨만. 붙인 뒤 SSM이 서버 안에서 deployment/ec2-<용도>/src/mount_volumes.sh 실행)
  #     mount_point   : 마운트 경로. 비우면 붙이기만 함 (마운트는 고객이 직접)
  #                     디렉터리가 없으면 만들고, 있으면 그대로 씀 (비어 있지 않거나 다른 장치가 마운트돼 있으면 그 볼륨은 실패 처리)
  #                     /, /etc, /usr, /var, /tmp, /home 같은 시스템 경로는 불가 (하위 경로는 가능, 예: /var/app)
  #     fs_type       : xfs(기본) | ext4. 파일시스템이 없을 때만 포맷 (기존 데이터·파티션이 있으면 포맷하지 않음)
  #     mount_options : fstab 옵션 (기본 defaults,nofail. nofail = 볼륨이 없어도 부팅은 계속)
  #     볼륨을 추가하거나 크기를 늘리면 다시 실행됨 (새 볼륨은 마운트, 늘린 볼륨은 파일시스템 확장)
  #     결과 확인: SSM 연결 <site>-ec2-<용도>-mount 상태 (Success / Failed)
  ebs_volumes = [
    { device_name = "/dev/xvdb", volume_size = 20, mount_point = "/data" }, # xfs, 기본 옵션
    # { device_name = "/dev/sdg", volume_size = 50, mount_point = "/app/logs", fs_type = "ext4" }, # ext4
    # { device_name = "/dev/sdh", volume_size = 200, volume_type = "gp3", mount_point = "/backup",
    #   fs_type = "xfs", mount_options = "defaults,nofail,noatime" },                             # 옵션 지정
    # { device_name = "/dev/sdi", volume_size = 30 },                                             # 붙이기만 (마운트 안 함)
  ]
  weekend_stop_enable = false # 주말 중지 대상 (ec2_weekend_stop.enabled일 때 동작. 태그 WEEKEND_STOP_ENABLE)
  enable_alb          = true  # ALB 생성 (기본 true)
  alb_internal        = true  # 내부용(기본). 외부용(false)은 01-network enable_public = true 필요
  alb_record_name     = "web" # 서비스 도메인 <이름>.<site>.<root_domain> (기본 web)
  app_port            = 8080  # 서버 서비스 포트 = ALB 대상 포트 (기본 8080)
  health_check_path   = "/"   # ALB 헬스체크 경로 (기본 /)

  # 자동 확장 (선택, 기본 꺼짐): 고정 서버(위) 1대 + 확장 서버 ASG 0 ~ max_extra대, 같은 ALB 대상 그룹
  #   켜기 전 확인 (협의 항목, 고객 서비스 담당)
  #     - 이미지만으로 애플리케이션이 뜨는가 (수동 설치·설정 없음)
  #     - 세션·업로드 파일이 서버 밖(DB·Redis·S3·EFS)에 있는가. 데이터 볼륨은 이미지 시점 복사본이 들어가고,
  #       확장 서버에서 쓴 데이터는 줄어들 때 사라짐
  #     - 라이선스가 서버 대수·IP에 묶여 있지 않은가 / 외부 방화벽이 서버 IP가 아니라 대역·SG로 허용되는가
  #   이미지: ami가 없으면 처음 한 번 고정 서버로 이미지를 만들어 씀 (데이터 볼륨 포함, 마운트·Agent 설치 후)
  #           이후 바꿀 때는 Terraform 밖에서 만든 이미지 ID를 ami에 → 확장 서버만 순차 교체
  #   확장 기준: CPU·메모리 그룹 평균 (고정 + 확장). 하나라도 scale_out% 초과 5분 → +1, 둘 다 scale_in% 미만 15분 → -1
  autoscale = {
    enabled = false # true로 켜야 동작
    # ami           = "ami-…"  # 확장 서버 이미지 (고정 ID). 비우면 최초 1회 고정 서버로 생성
    # max_extra     = 0        # 확장 서버 최대 대수 (0이면 대기만)
    # scale_out     = 80       # %
    # scale_in      = 50       # %
    # image_reboot  = false    # 최초 이미지 생성 시 고정 서버 재부팅 (true = 파일 일관성, 잠시 중단)
    # instance_type = null     # 확장 서버 사양 (null = 고정 서버와 같음)
    # refresh_min_healthy_percentage = 90  # 이미지 변경 시 순차 교체 중 유지할 정상 비율
    # weekend_stop  = { enabled = false, stop_schedule = "0 21 * * FRI", start_schedule = "0 7 * * MON" }  # 확장 서버만 0대 ↔ 원복
  }
}

# ── Web IDE ───────────────────────────────────────────────────
webide = {
  enabled             = true                    # false면 Web IDE 서버와 관련 리소스를 만들지 않음
  ami                 = "ami-0eff555c11692fc96" # (필수) 이 서버의 AMI ID (커스텀 이미지)
  instance_type       = "t3.medium"             # 기본 t3.medium
  root_volume_size    = 30                      # 루트 볼륨 GB (기본 30, 이미지 크기 이상)
  ebs_volumes         = []                      # 추가 데이터 볼륨 (형식은 was와 같음)
  weekend_stop_enable = false                   # 주말 중지 대상
  enable_alb          = false                   # ALB 생성 (기본 false)
  alb_internal        = true                    # 내부용(기본). 외부용(false)은 01-network enable_public = true 필요
  alb_record_name     = "ide"                   # 서비스 도메인 이름 (기본 ide)
  app_port            = 80                      # 서버 서비스 포트 (기본 80)
  health_check_path   = "/"                     # ALB 헬스체크 경로 (기본 /)
  autoscale           = { enabled = false }     # 자동 확장 (형식은 was와 같음, 기본 꺼짐)
}

# ── EC2 주말 중지 (협의 후 적용) ───────────────────────────────
# enabled = true      : Lambda와 스케줄 생성 (01-network interface_endpoints에 "ec2" 필요)
# schedule_enabled    : 협의가 끝나기 전에는 false (스케줄이 실행되지 않음). 아래 시간은 임시 값
# 대상 서버는 태그로 켜고 끔: was/webide의 weekend_stop_enable = true → WEEKEND_STOP_ENABLE = "true"
# dry_run = true      : 실제로 중지하지 않고 대상만 로그로 확인
ec2_weekend_stop = {
  enabled          = false
  schedule_enabled = false
  stop_schedule    = "cron(0 21 ? * FRI *)" # 중지 시각 (기본 금요일 21:00)
  start_schedule   = "cron(0 7 ? * MON *)"  # 시작 시각 (기본 월요일 07:00)
  timezone         = "Asia/Seoul"           # 스케줄 시간대 (기본 Asia/Seoul)
  dry_run          = false                  # true면 중지하지 않고 대상만 로그로 확인
}

# ── 암호화 키 (CMK) ───────────────────────────────────────────
# EC2 볼륨은 계정 EBS 기본 키(00-bootstrap의 ebs)로 암호화되므로 이 단계에서 만드는 키는 없습니다.
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
}

# ── 운영 모드 (삭제 보호) ─────────────────────────────────────
# operation_mode = "enable" : 운영. 버킷·KMS 키·NAT EIP 삭제 불가, KMS 삭제 대기 30일, ALB 삭제 보호, EC2 볼륨은 서버 삭제 후에도 남김
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
}
