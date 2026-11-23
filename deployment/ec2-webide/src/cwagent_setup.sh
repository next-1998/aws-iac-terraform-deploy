#!/bin/bash
# CloudWatch Agent: OS 로그(messages, secure) -> 미리 만든 로그 그룹
#   SSM 연결(AWS-RunShellScript, root)이 실행. 여러 번 실행해도 결과가 같음
#   LOG_PREFIX(예: /simple/ec2-was)는 Terraform이 이 스크립트 앞에 넣음
#   OS 계열   messages            secure
#   RHEL계열  /var/log/messages   /var/log/secure     (RHEL, Rocky, Alma, CentOS, Amazon Linux)
#   Debian계열 /var/log/syslog    /var/log/auth.log   (Ubuntu, Debian)
#   1) rsyslog가 없으면 설치 (Amazon Linux 2023은 기본 미설치)
#   2) Agent가 없으면 설치 (OS 저장소 -> 없으면 AWS 리전 S3 배포본, S3 게이트웨이 endpoint 경유)
#   3) 설정을 쓰고 적용
set -euo pipefail
: "${LOG_PREFIX:?LOG_PREFIX가 없습니다}"

. /etc/os-release
case " ${ID} ${ID_LIKE:-} " in
  *" debian "*|*" ubuntu "*)
    FAMILY=debian; MSG=/var/log/syslog; SEC=/var/log/auth.log; PKG=deb ;;
  *" rhel "*|*" fedora "*|*" centos "*|*" amzn "*)
    FAMILY=rhel; MSG=/var/log/messages; SEC=/var/log/secure; PKG=rpm ;;
  *) echo "지원하지 않는 OS: ${ID}"; exit 1 ;;
esac
[ "$ID" = "amzn" ] && DIST=amazon_linux || { [ "$FAMILY" = debian ] && DIST=ubuntu || DIST=redhat; }
case "$(uname -m)" in aarch64) ARCH=arm64 ;; *) ARCH=amd64 ;; esac
echo "OS=${ID} ${VERSION_ID:-} family=${FAMILY} arch=${ARCH}"

installed() { if [ "$PKG" = rpm ]; then rpm -q "$1" >/dev/null 2>&1; else dpkg -s "$1" >/dev/null 2>&1; fi; }
pkg_install() {
  if [ "$FAMILY" = debian ]; then DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
  elif command -v dnf >/dev/null; then dnf install -y "$@"
  else yum install -y "$@"; fi
}

# 1) rsyslog
if installed rsyslog; then echo "rsyslog: 이미 설치됨"
else echo "rsyslog: 설치"; pkg_install rsyslog; fi
systemctl enable --now rsyslog

# 2) CloudWatch Agent
if installed amazon-cloudwatch-agent; then echo "agent: 이미 설치됨"
elif pkg_install amazon-cloudwatch-agent; then echo "agent: OS 저장소에서 설치"
else
  T=$(curl -sS -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
  REGION=$(curl -sS -H "X-aws-ec2-metadata-token: $T" http://169.254.169.254/latest/meta-data/placement/region)
  URL="https://amazoncloudwatch-agent-${REGION}.s3.${REGION}.amazonaws.com/${DIST}/${ARCH}/latest/amazon-cloudwatch-agent.${PKG}"
  echo "agent: AWS 배포본 설치 ${URL}"
  curl -sSfo "/tmp/cwagent.${PKG}" "$URL"
  if [ "$PKG" = rpm ]; then rpm -U --replacepkgs /tmp/cwagent.rpm; else dpkg -i -E /tmp/cwagent.deb; fi
  rm -f "/tmp/cwagent.${PKG}"
fi

# 3) 설정 (로그 그룹은 Terraform이 만든 것을 씀. 보관 기간은 Terraform 값 유지)
CTL=/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl
CFG=/opt/aws/amazon-cloudwatch-agent/etc/iac-os-logs.json
cat > "$CFG" <<EOF
{
  "agent": { "run_as_user": "root" },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          { "file_path": "${MSG}", "log_group_name": "${LOG_PREFIX}/messages", "log_stream_name": "{instance_id}" },
          { "file_path": "${SEC}", "log_group_name": "${LOG_PREFIX}/secure", "log_stream_name": "{instance_id}" }
        ]
      }
    }
  }
}
EOF
"$CTL" -a fetch-config -m ec2 -s -c "file:${CFG}"
"$CTL" -a status
