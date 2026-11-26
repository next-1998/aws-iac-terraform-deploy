"""
RDS NLB 대상 동기화 Lambda

태그 <TAG_KEY> = <SG ID> 가 붙은 대상 그룹마다, 그 SG에 붙은 ENI의 IP 전체를 대상으로 맞춥니다.
  - 대상 그룹: 원본 DB SG → 원본 + Multi-AZ 대기 인스턴스 IP. NLB 상태 확인(TCP)이 지금 원본만 healthy로 보고 그쪽으로만 보냄
  장애 조치는 상태 확인이 따라가므로 갱신이 필요 없고, 유지 관리·사양 변경 등으로 ENI가 바뀔 때만 IP를 교체합니다.
  SG에 ENI가 하나도 없으면(DB 재생성 중 등) 기존 대상을 지우지 않습니다 (연결 유지).

환경 변수
  TAG_KEY : 대상 그룹 태그 키 (값 = 대상 SG ID)
  VPC_ID  : 이 VPC의 대상 그룹·ENI만
  DRY_RUN : "true"면 바꾸지 않고 로그만
"""
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TAG_KEY = os.environ.get("TAG_KEY", "RdsNlbSyncSg")
VPC_ID = os.environ.get("VPC_ID", "")
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"

elb = boto3.client("elbv2")
ec2 = boto3.client("ec2")


def _tagged_target_groups():
    groups = []
    for page in elb.get_paginator("describe_target_groups").paginate():
        groups += [g for g in page["TargetGroups"] if g.get("VpcId") == VPC_ID and g.get("TargetType") == "ip"]
    result = {}
    for i in range(0, len(groups), 20):
        batch = groups[i:i + 20]
        for d in elb.describe_tags(ResourceArns=[g["TargetGroupArn"] for g in batch])["TagDescriptions"]:
            sg = {t["Key"]: t["Value"] for t in d["Tags"]}.get(TAG_KEY)
            if sg:
                g = next(x for x in batch if x["TargetGroupArn"] == d["ResourceArn"])
                result[g["TargetGroupArn"]] = {"sg": sg, "port": g["Port"], "name": g["TargetGroupName"]}
    return result


def _sg_ips(sg):
    ips = set()
    for page in ec2.get_paginator("describe_network_interfaces").paginate(
        Filters=[{"Name": "group-id", "Values": [sg]}, {"Name": "vpc-id", "Values": [VPC_ID]}]
    ):
        for eni in page["NetworkInterfaces"]:
            if eni.get("Status") == "in-use":
                ips.add(eni["PrivateIpAddress"])
    return ips


def lambda_handler(event, context):
    result = {}
    for arn, tg in _tagged_target_groups().items():
        want = _sg_ips(tg["sg"])
        have = {t["Target"]["Id"] for t in elb.describe_target_health(TargetGroupArn=arn)["TargetHealthDescriptions"]}
        if not want:
            logger.warning("%s: SG %s에 ENI 없음 - 기존 대상 유지 %s", tg["name"], tg["sg"], sorted(have))
            result[tg["name"]] = "no-eni"
            continue
        add, remove = sorted(want - have), sorted(have - want)
        if add or remove:
            logger.info("%s: 추가 %s, 제거 %s (SG %s)", tg["name"], add, remove, tg["sg"])
            if not DRY_RUN:
                if add:
                    elb.register_targets(TargetGroupArn=arn, Targets=[{"Id": ip, "Port": tg["port"]} for ip in add])
                if remove:
                    elb.deregister_targets(TargetGroupArn=arn, Targets=[{"Id": ip, "Port": tg["port"]} for ip in remove])
        result[tg["name"]] = {"targets": sorted(want), "added": add, "removed": remove}
    logger.info("result: %s", result)
    return result
