"""
EBS 자동 증설 Lambda

호출
  1) CloudWatch 알람 (디스크 사용률 초과) → 그 알람의 볼륨 하나를 늘림
  2) 스케줄 {"action": "retry"} → ALARM 상태로 남은 증설 알람을 다시 확인
     (6시간 대기 중이라 못 늘렸거나, 늘린 뒤에도 사용률이 높은 경우)

대상 정보는 알람 설명(description)에 Terraform이 넣습니다 (key=value, 공백 구분)
  volume=vol-... instance=i-... path=/data max=200 percent=20 min=10

처리
  1) 볼륨이 그 서버에 붙어 있는지, 상한(max)에 닿았는지, 6시간 대기 중인지 확인
  2) 크기 늘림: 현재 + max(현재 × percent%, min) GiB, 상한까지
  3) 볼륨 변경이 optimizing 이상이 되면 SSM으로 서버 안 파일시스템 확장 (파티션 growpart → xfs_growfs / resize2fs)
  4) 알람을 OK로 되돌림 (사용률이 여전히 높으면 다시 ALARM → 다음 증설)
  5) 결과를 SNS로 알림 (SNS_TOPIC_ARN이 있을 때)
  대기 중이면 알람을 ALARM 그대로 두고, 스케줄(retry)이 다시 확인합니다.

환경 변수
  TAG_KEY            : 증설 허용 태그 키 (볼륨·서버에 "true", IAM 조건과 같은 키)
  ALARM_NAME_PREFIX  : 다시 확인할 알람 이름 앞부분 (<접두어>-alm-)
  ALARM_NAME_MARK    : 증설 알람 이름에 들어 있는 표시 (-ebsgrow-)
  SNS_TOPIC_ARN      : 결과 알림 토픽 (비우면 알림 없음)
  DRY_RUN            : "true"면 크기를 바꾸지 않고 로그만
"""
import datetime
import logging
import math
import os
import re
import shlex
import time

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TAG_KEY = os.environ.get("TAG_KEY", "EBS_AUTO_GROW")
ALARM_NAME_PREFIX = os.environ.get("ALARM_NAME_PREFIX", "")
ALARM_NAME_MARK = os.environ.get("ALARM_NAME_MARK", "-ebsgrow-")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"

COOLDOWN = datetime.timedelta(hours=6)  # AWS 제한: 같은 볼륨은 변경 후 6시간 동안 다시 바꿀 수 없음
WAIT_MODIFY_SECONDS = 300
WAIT_COMMAND_SECONDS = 180

ec2 = boto3.client("ec2")
ssm = boto3.client("ssm")
cw = boto3.client("cloudwatch")
sns = boto3.client("sns") if SNS_TOPIC_ARN else None

# 서버 안 파일시스템 확장 (root로 실행). 파티션이면 growpart 후 파일시스템 확장. LVM은 지원하지 않음
GROW_SCRIPT = r"""
set -eu
P=__PATH__
SRC=$(findmnt -no SOURCE --mountpoint "$P")
FS=$(findmnt -no FSTYPE --mountpoint "$P")
[ -n "$SRC" ] || { echo "마운트 없음: $P"; exit 1; }
DEV=$(readlink -f "$SRC")
NAME=$(basename "$DEV")
if [ -f "/sys/class/block/$NAME/partition" ]; then
  PK=$(lsblk -no PKNAME "$DEV" | head -1)
  N=$(cat "/sys/class/block/$NAME/partition")
  command -v growpart >/dev/null || { echo "growpart가 없습니다 (cloud-utils-growpart / cloud-guest-utils)"; exit 1; }
  growpart "/dev/$PK" "$N" || [ $? -eq 1 ]   # 1 = 늘릴 공간 없음 (이미 늘어남)
fi
case "$FS" in
  xfs) xfs_growfs "$P" ;;
  ext4|ext3) resize2fs "$DEV" ;;
  *) echo "지원하지 않는 파일시스템: $FS"; exit 1 ;;
esac
df -h "$P"
"""


def _parse(description):
    info = dict(re.findall(r"(\w+)=(\S+)", description or ""))
    for k in ("volume", "instance", "path", "max"):
        if k not in info:
            raise ValueError(f"알람 설명에 {k}가 없습니다: {description}")
    info["max"] = int(info["max"])
    info["percent"] = int(info.get("percent", 20))
    info["min"] = int(info.get("min", 10))
    return info


def _notify(subject, message):
    logger.info("%s | %s", subject, message)
    if sns:
        try:
            sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject[:100], Message=message)
        except ClientError as e:
            logger.error("알림 실패: %s", e)


def _latest_modification(volume_id):
    try:
        mods = ec2.describe_volumes_modifications(VolumeIds=[volume_id])["VolumesModifications"]
    except ClientError as e:
        if "NotFound" in e.response["Error"]["Code"]:
            return None
        raise
    return max(mods, key=lambda m: m["StartTime"]) if mods else None


def _wait_modification(volume_id):
    """크기가 OS에 보이는 단계(optimizing / completed)까지 대기"""
    deadline = time.time() + WAIT_MODIFY_SECONDS
    while time.time() < deadline:
        m = _latest_modification(volume_id)
        state = m and m["ModificationState"]
        if state in ("optimizing", "completed"):
            return state
        if state == "failed":
            raise RuntimeError(f"볼륨 변경 실패: {m.get('StatusMessage')}")
        time.sleep(10)
    raise TimeoutError("볼륨 변경이 optimizing 단계에 들어가지 않았습니다")


def _grow_filesystem(instance_id, path):
    script = GROW_SCRIPT.replace("__PATH__", shlex.quote(path))
    cmd = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName="AWS-RunShellScript",
        Comment=f"EBS auto grow {path}",
        Parameters={"commands": [script]},
    )["Command"]["CommandId"]
    deadline = time.time() + WAIT_COMMAND_SECONDS
    while time.time() < deadline:
        time.sleep(5)
        try:
            r = ssm.get_command_invocation(CommandId=cmd, InstanceId=instance_id)
        except ClientError as e:
            if e.response["Error"]["Code"] == "InvocationDoesNotExist":
                continue
            raise
        if r["Status"] not in ("Pending", "InProgress", "Delayed"):
            return r["Status"], (r.get("StandardOutputContent") or "") + (r.get("StandardErrorContent") or "")
    return "Timeout", f"명령 {cmd} 결과를 {WAIT_COMMAND_SECONDS}초 안에 받지 못함"


def grow(alarm_name, description):
    t = _parse(description)
    vol = ec2.describe_volumes(VolumeIds=[t["volume"]])["Volumes"][0]
    size = vol["Size"]
    attached = [a["InstanceId"] for a in vol.get("Attachments", []) if a["State"] == "attached"]
    tags = {x["Key"]: x["Value"] for x in vol.get("Tags", [])}
    where = f"{t['volume']} ({t['instance']} {t['path']})"

    if t["instance"] not in attached:
        return _notify(f"[EBS 자동 증설] 대상 불일치 {alarm_name}", f"{where}: 볼륨이 이 서버에 붙어 있지 않습니다 ({attached}).")
    if tags.get(TAG_KEY, "").lower() != "true":
        return _notify(f"[EBS 자동 증설] 허용 태그 없음 {alarm_name}", f"{where}: 볼륨에 {TAG_KEY}=true 태그가 없습니다.")
    if size >= t["max"]:
        # 알람은 ALARM 그대로 (같은 알림 반복 없음). 상한을 올리면 다음 retry에서 늘어남
        return _notify(f"[EBS 자동 증설] 상한 도달 {alarm_name}", f"{where}: 현재 {size} GiB = 상한 {t['max']} GiB. 디스크를 정리하거나 상한(max_size)을 올리세요.")

    m = _latest_modification(t["volume"])
    if m and m["ModificationState"] in ("modifying", "optimizing") and m.get("TargetSize", size) > size:
        logger.info("%s: 변경 진행 중 (%s) - 다음 확인 때 처리", where, m["ModificationState"])
        return "in_progress"
    if m and datetime.datetime.now(datetime.timezone.utc) - m["StartTime"] < COOLDOWN:
        logger.info("%s: 6시간 대기 중 (마지막 변경 %s) - 다음 확인 때 처리", where, m["StartTime"])
        return "cooldown"

    new_size = min(t["max"], size + max(t["min"], math.ceil(size * t["percent"] / 100)))
    if DRY_RUN:
        logger.info("DRY_RUN %s: %s → %s GiB", where, size, new_size)
        return "dry_run"

    ec2.modify_volume(VolumeId=t["volume"], Size=new_size)
    _wait_modification(t["volume"])
    status, output = _grow_filesystem(t["instance"], t["path"])

    # OK로 되돌려 두면 사용률이 여전히 높을 때 다시 ALARM → 다음 증설 (6시간 뒤 retry)
    cw.set_alarm_state(AlarmName=alarm_name, StateValue="OK", StateReason=f"EBS grown {size} -> {new_size} GiB")
    _notify(
        f"[EBS 자동 증설] {size} → {new_size} GiB {alarm_name}",
        f"{where}: {size} GiB → {new_size} GiB (상한 {t['max']} GiB)\n파일시스템 확장: {status}\n\n{output[-2000:]}\n\n"
        "Terraform은 실제 크기가 tfvars보다 크면 실제 크기를 유지합니다 (줄이지 않음).",
    )
    return "grown"


def _retry():
    results = {}
    paginator = cw.get_paginator("describe_alarms")
    for page in paginator.paginate(AlarmNamePrefix=ALARM_NAME_PREFIX, StateValue="ALARM", AlarmTypes=["MetricAlarm"]):
        for a in page["MetricAlarms"]:
            if ALARM_NAME_MARK in a["AlarmName"]:
                results[a["AlarmName"]] = _safe(a["AlarmName"], a.get("AlarmDescription"))
    return results


def _safe(name, description):
    try:
        return grow(name, description)
    except Exception as e:  # 실패는 알리고 다음 대상으로
        logger.exception("증설 실패 %s", name)
        _notify(f"[EBS 자동 증설] 실패 {name}", f"{type(e).__name__}: {e}")
        return "error"


def lambda_handler(event, context):
    if event.get("action") == "retry":
        result = _retry()
    else:
        # CloudWatch 알람 직접 호출
        data = event.get("alarmData", {})
        if data.get("state", {}).get("value") != "ALARM":
            return {"skipped": "not ALARM"}
        name = data["alarmName"]
        result = {name: _safe(name, data.get("configuration", {}).get("description"))}
    logger.info("result: %s", result)
    return result
