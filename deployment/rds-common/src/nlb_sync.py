"""
RDS NLB 대상 동기화 Lambda (1분마다)

대상 그룹 태그로 방식을 고릅니다.
  <TAG_KEY> = <SG ID>        (RDS)    그 SG에 붙은 ENI의 IP 전체 = 원본 + Multi-AZ 대기 인스턴스
                                       NLB 상태 확인(TCP)이 지금 원본만 healthy로 보고 그쪽으로만 보냄 (대기는 접속을 받지 않음)
                                       장애 조치는 상태 확인이 따라가고, ENI가 바뀔 때(유지 관리·사양 변경)만 IP를 교체
  <DNS_TAG_KEY> = <쓰기 주소> (Aurora) 클러스터 쓰기 주소(DNS)를 조회한 IP 하나 = 지금 쓰기 인스턴스
                                       (Aurora 읽기 인스턴스도 접속을 받아 상태 확인을 통과하므로 SG 방식을 쓸 수 없음)
                                       장애 조치 뒤 쓰기 주소가 새 인스턴스를 가리키면 1분 안에 대상을 바꿈
  찾은 IP가 없으면(DB 재생성 중, DNS 조회 실패 등) 기존 대상을 지우지 않습니다 (연결 유지).

실행
  1분마다 (EventBridge Scheduler) + DB 클러스터 장애 조치 이벤트 때 바로 (EventBridge 규칙, event = {"trigger": "failover"})
  장애 조치 실행은 쓰기 주소(DNS)가 늦게 바뀔 수 있어, DNS 방식 대상이 바뀔 때까지 5초 간격으로 최대 45초 다시 확인

환경 변수
  TAG_KEY     : SG 방식 태그 키
  DNS_TAG_KEY : DNS 방식 태그 키
  VPC_ID      : 이 VPC의 대상 그룹·ENI만
  DRY_RUN     : "true"면 바꾸지 않고 로그만
"""
import logging
import os
import socket
import time

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TAG_KEY = os.environ.get("TAG_KEY", "RdsNlbSyncSg")
DNS_TAG_KEY = os.environ.get("DNS_TAG_KEY", "RdsNlbSyncDns")
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
            tags = {t["Key"]: t["Value"] for t in d["Tags"]}
            g = next(x for x in batch if x["TargetGroupArn"] == d["ResourceArn"])
            if tags.get(TAG_KEY):
                result[g["TargetGroupArn"]] = {"sg": tags[TAG_KEY], "port": g["Port"], "name": g["TargetGroupName"]}
            elif tags.get(DNS_TAG_KEY):
                result[g["TargetGroupArn"]] = {"dns": tags[DNS_TAG_KEY], "port": g["Port"], "name": g["TargetGroupName"]}
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


def _dns_ips(name):
    try:
        return {a[4][0] for a in socket.getaddrinfo(name, None, socket.AF_INET)}
    except socket.gaierror as e:
        logger.warning("DNS 조회 실패 %s: %s", name, e)
        return set()


def lambda_handler(event, context):
    if (event or {}).get("trigger") != "failover":
        return _sync(_tagged_target_groups())
    # 장애 조치: DNS 방식(Aurora) 대상이 바뀔 때까지 다시 확인 (쓰기 주소가 몇 초 늦게 바뀜)
    groups = _tagged_target_groups()
    dns_names = {g["name"] for g in groups.values() if "dns" in g}
    result = _sync(groups)
    # 7번 x (확인 + 5초) ≈ 45초. Lambda 제한 시간 60초 안
    for _ in range(6):
        if not dns_names or any(isinstance(result.get(n), dict) and result[n]["added"] for n in dns_names):
            break
        time.sleep(5)
        result = _sync(groups)
    return result


def _sync(groups):
    result = {}
    for arn, tg in groups.items():
        source = tg.get("sg") or tg.get("dns")
        want = _sg_ips(tg["sg"]) if "sg" in tg else _dns_ips(tg["dns"])
        have = {t["Target"]["Id"] for t in elb.describe_target_health(TargetGroupArn=arn)["TargetHealthDescriptions"]}
        if not want:
            logger.warning("%s: %s에서 찾은 IP 없음 - 기존 대상 유지 %s", tg["name"], source, sorted(have))
            result[tg["name"]] = "no-ip"
            continue
        add, remove = sorted(want - have), sorted(have - want)
        if add or remove:
            logger.info("%s: 추가 %s, 제거 %s (%s)", tg["name"], add, remove, source)
            if not DRY_RUN:
                if add:
                    elb.register_targets(TargetGroupArn=arn, Targets=[{"Id": ip, "Port": tg["port"]} for ip in add])
                if remove:
                    elb.deregister_targets(TargetGroupArn=arn, Targets=[{"Id": ip, "Port": tg["port"]} for ip in remove])
        result[tg["name"]] = {"targets": sorted(want), "added": add, "removed": remove}
    logger.info("result: %s", result)
    return result
