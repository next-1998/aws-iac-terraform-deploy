#!/bin/bash
# 데이터 볼륨 마운트: Terraform이 붙인 데이터 볼륨을 포맷(처음만)하고 마운트
#   SSM 연결(AWS-RunShellScript, root)이 실행. 여러 번 실행해도 결과가 같음
#   VOLUMES는 Terraform이 이 스크립트 앞에 넣음. 한 줄에 볼륨 하나:
#     <볼륨 ID>|<장치 이름>|<마운트 경로>|<파일시스템>|<fstab 옵션>|<크기 GiB>
#     예) vol-0123456789abcdef0|/dev/sdf|/data|xfs|defaults,nofail|100
#   볼륨마다
#     1) 볼륨 ID로 장치 찾기 (붙을 때까지 최대 5분 대기)
#     2) 파일시스템이 없으면 포맷. 파일시스템·파티션이 이미 있으면 포맷하지 않음 (기존 데이터 보호)
#     3) 마운트 경로: 없으면 만들고, 있으면 그대로 씀
#        비어 있지 않은 디렉터리, 다른 장치가 마운트된 경로, fstab에 다른 항목이 있는 경로는 건너뜀 (오류)
#     4) fstab에 UUID로 등록 (재부팅 후에도 마운트) → 마운트
#     5) 볼륨을 늘렸으면 파일시스템도 확장
#   한 볼륨이 실패해도 나머지는 계속 처리하고, 마지막에 실패로 끝냄 (SSM 연결 상태 Failed)
set -uo pipefail
: "${VOLUMES:?VOLUMES가 없습니다}"

. /etc/os-release
case " ${ID} ${ID_LIKE:-} " in
  *" debian "*|*" ubuntu "*) PKG_INSTALL="apt-get install -y" ;;
  *" rhel "*|*" fedora "*|*" centos "*|*" amzn "*)
    if command -v dnf >/dev/null 2>&1; then PKG_INSTALL="dnf install -y"; else PKG_INSTALL="yum install -y"; fi ;;
  *) echo "지원하지 않는 OS: ${ID}"; exit 1 ;;
esac
echo "OS=${ID} ${VERSION_ID:-}"

FAILED=0
fail() { echo "[오류] $*"; FAILED=1; }

# 파일시스템 도구 (AL·RHEL은 xfsprogs 기본 포함, 없으면 설치)
ensure_tool() {
  local cmd=$1 pkg=$2
  command -v "$cmd" >/dev/null 2>&1 && return 0
  echo "$cmd 없음 → $pkg 설치"
  [ "${PKG_INSTALL%% *}" = "apt-get" ] && apt-get update -y >/dev/null 2>&1
  $PKG_INSTALL "$pkg" >/dev/null 2>&1 && command -v "$cmd" >/dev/null 2>&1
}

# 볼륨 ID → 장치 경로
#   Nitro(NVMe): 장치 일련번호가 볼륨 ID(하이픈 없음) / Xen: /dev/sdf → /dev/xvdf
find_device() {
  local vol=$1 name=$2 serial=${1/-/} dev=""
  for _ in $(seq 1 60); do
    dev=$(lsblk -dpno NAME,SERIAL 2>/dev/null | awk -v s="$serial" '$2==s {print $1; exit}')
    [ -z "$dev" ] && dev=$(ls /dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_"${serial}" 2>/dev/null | head -1)
    [ -z "$dev" ] && [ -b "${name/\/dev\/sd//dev/xvd}" ] && dev=${name/\/dev\/sd//dev/xvd}
    [ -z "$dev" ] && [ -b "$name" ] && dev=$name
    if [ -n "$dev" ]; then readlink -f "$dev"; return 0; fi
    sleep 5
  done
  return 1
}

while IFS='|' read -r VOL NAME MNT FS OPTS SIZE; do
  [ -z "${VOL}" ] && continue
  echo "── ${VOL} (${NAME}) → ${MNT} [${FS}] ${SIZE}GiB"

  # 1) 장치
  DEV=$(find_device "$VOL" "$NAME") || { fail "${VOL}: 장치를 찾지 못함 (붙지 않았거나 5분 초과)"; continue; }
  echo "장치: ${DEV}"

  # 2) 파일시스템 (없을 때만 포맷)
  CUR_FS=$(blkid -p -o value -s TYPE "$DEV" 2>/dev/null || true)
  PT=$(blkid -p -o value -s PTTYPE "$DEV" 2>/dev/null || true)
  if [ -z "$CUR_FS" ]; then
    if [ -n "$PT" ] || [ "$(lsblk -no TYPE "$DEV" | grep -c part)" -gt 0 ]; then
      fail "${VOL}: 파티션이 있는 디스크 - 포맷하지 않음 (수동 확인 필요)"; continue
    fi
    case "$FS" in
      xfs)  ensure_tool mkfs.xfs xfsprogs  || { fail "${VOL}: mkfs.xfs 설치 실패"; continue; } ;;
      ext4) ensure_tool mkfs.ext4 e2fsprogs || { fail "${VOL}: mkfs.ext4 설치 실패"; continue; } ;;
    esac
    echo "파일시스템 없음 → ${FS}로 포맷"
    mkfs -t "$FS" "$DEV" >/dev/null || { fail "${VOL}: 포맷 실패"; continue; }
    CUR_FS=$FS
  elif [ "$CUR_FS" != "$FS" ]; then
    echo "[주의] 기존 파일시스템(${CUR_FS})이 설정(${FS})과 다름 - 기존 것을 그대로 씀 (포맷하지 않음)"
  fi
  UUID=$(blkid -o value -s UUID "$DEV")

  # 3) 마운트 경로
  if mountpoint -q "$MNT"; then
    SRC=$(readlink -f "$(findmnt -n -o SOURCE "$MNT")")
    if [ "$SRC" != "$DEV" ]; then fail "${MNT}: 다른 장치(${SRC})가 마운트되어 있음"; continue; fi
    echo "이미 마운트됨"
  else
    if [ -e "$MNT" ] && [ ! -d "$MNT" ]; then fail "${MNT}: 디렉터리가 아님"; continue; fi
    if [ -d "$MNT" ]; then
      [ -n "$(ls -A "$MNT")" ] && { fail "${MNT}: 비어 있지 않음 (마운트하면 기존 파일이 가려짐)"; continue; }
      echo "디렉터리 있음 → 그대로 사용"
    else
      mkdir -p "$MNT" && echo "디렉터리 없음 → 생성"
    fi
    OTHER=$(findmnt -n -o TARGET -S "$DEV" 2>/dev/null | head -1)
    [ -n "$OTHER" ] && { fail "${VOL}: 이미 다른 경로(${OTHER})에 마운트되어 있음"; continue; }
  fi

  # 4) fstab (UUID) → 마운트
  if ! grep -qE "^UUID=${UUID}[[:space:]]" /etc/fstab; then
    if awk -v m="$MNT" '$1 !~ /^#/ && $2 == m {found=1} END {exit !found}' /etc/fstab; then
      fail "${MNT}: fstab에 다른 항목이 있음"; continue
    fi
    cp -p /etc/fstab "/etc/fstab.bak.$(date +%Y%m%d%H%M%S)"
    echo "UUID=${UUID} ${MNT} ${CUR_FS} ${OPTS} 0 2" >> /etc/fstab
    echo "fstab 등록"
    command -v systemctl >/dev/null 2>&1 && systemctl daemon-reload
  fi
  if ! mountpoint -q "$MNT"; then
    mount "$MNT" || { fail "${MNT}: 마운트 실패"; continue; }
    echo "마운트 완료"
  fi

  # 5) 파일시스템 확장 (볼륨을 늘린 경우. 이미 같으면 변화 없음)
  case "$CUR_FS" in
    xfs)  xfs_growfs "$MNT" >/dev/null 2>&1 || fail "${MNT}: xfs_growfs 실패" ;;
    ext4) resize2fs "$DEV" >/dev/null 2>&1 || fail "${MNT}: resize2fs 실패" ;;
  esac
  df -h "$MNT" | tail -1
done <<< "$VOLUMES"

[ "$FAILED" -eq 0 ] && echo "완료" || { echo "일부 볼륨 실패 (위 [오류] 확인)"; exit 1; }
