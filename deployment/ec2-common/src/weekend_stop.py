"""
주말 중지 Lambda

대상은 태그로만 판단합니다. 리소스마다 자기 태그를 확인합니다.
  WEEKEND_STOP_ENABLE = "true"  → 대상
  그 외 / 태그 없음             → 대상 아님

환경 변수
  TARGET   : "ec2" 또는 "rds"
  TAG_KEY  : 대상 태그 키 (기본값 WEEKEND_STOP_ENABLE)
  DRY_RUN  : "true"면 실제로 중지·시작하지 않고 대상만 로그로 남김

이벤트
  {"action": "stop"} 또는 {"action": "start"}

VPC 안에서 실행되므로 VPC endpoint(ec2 또는 rds)로 AWS API를 호출합니다.
"""
import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TARGET = os.environ.get("TARGET", "ec2")
TAG_KEY = os.environ.get("TAG_KEY", "WEEKEND_STOP_ENABLE")
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"


def _enabled(tags):
    """리소스 자기 태그로만 판단"""
    for t in tags or []:
        if t.get("Key") == TAG_KEY and str(t.get("Value", "")).lower() == "true":
            return True
    return False


def handle_ec2(action):
    ec2 = boto3.client("ec2")
    want_state = "running" if action == "stop" else "stopped"
    targets = []

    paginator = ec2.get_paginator("describe_instances")
    for page in paginator.paginate(
        Filters=[
            {"Name": f"tag:{TAG_KEY}", "Values": ["true", "True", "TRUE"]},
            {"Name": "instance-state-name", "Values": [want_state]},
        ]
    ):
        for r in page["Reservations"]:
            for i in r["Instances"]:
                if _enabled(i.get("Tags")):
                    targets.append(i["InstanceId"])

    logger.info(json.dumps({"target": "ec2", "action": action, "instances": targets, "dry_run": DRY_RUN}))
    if targets and not DRY_RUN:
        if action == "stop":
            ec2.stop_instances(InstanceIds=targets)
        else:
            ec2.start_instances(InstanceIds=targets)
    return targets


def handle_rds(action):
    rds = boto3.client("rds")
    want_status = "available" if action == "stop" else "stopped"
    targets, skipped = [], []

    paginator = rds.get_paginator("describe_db_instances")
    for page in paginator.paginate():
        for db in page["DBInstances"]:
            if not _enabled(db.get("TagList")):
                continue
            if db.get("DBClusterIdentifier"):
                # Aurora는 인스턴스가 아니라 클러스터 단위로 중지해야 함 (지원 예정)
                skipped.append(db["DBInstanceIdentifier"])
                continue
            if db.get("DBInstanceStatus") != want_status:
                continue
            targets.append(db["DBInstanceIdentifier"])

    logger.info(json.dumps({"target": "rds", "action": action, "instances": targets, "skipped_aurora": skipped, "dry_run": DRY_RUN}))
    if not DRY_RUN:
        for db_id in targets:
            try:
                if action == "stop":
                    rds.stop_db_instance(DBInstanceIdentifier=db_id)
                else:
                    rds.start_db_instance(DBInstanceIdentifier=db_id)
            except Exception as ex:  # 한 대가 실패해도 나머지는 계속
                logger.error(json.dumps({"db": db_id, "error": str(ex)}))
    return targets


def lambda_handler(event, context):
    action = (event or {}).get("action")
    if action not in ("stop", "start"):
        raise ValueError(f"action은 stop 또는 start여야 합니다: {action}")

    if TARGET == "ec2":
        result = handle_ec2(action)
    elif TARGET == "rds":
        result = handle_rds(action)
    else:
        raise ValueError(f"TARGET은 ec2 또는 rds여야 합니다: {TARGET}")

    return {"target": TARGET, "action": action, "count": len(result)}
