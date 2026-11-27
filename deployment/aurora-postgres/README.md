# aurora-postgres

Aurora PostgreSQL 클러스터 엔진 조합입니다. 엔진 고정값(engine = "aurora-postgresql"), 고를 수 있는 로그 이름 검사, CSV 예제만 두고 실제 구성은 `deployment/aurora-core`가 합니다.

- 호출: 03-database의 `aurora_postgres` 목록 (DB 키마다 한 번)
- 이름: 클러스터 `<접두어>-rds-cl-<엔진 코드>-<DB 키>-01`, 인스턴스 `<접두어>-rds-<엔진 코드>-<DB 키>-NN` (순번만: 01 처음 쓰기, 02 multi_az, 그다음 replicas. 장애 조치로 역할이 바뀌어 ro를 붙이지 않음)
- 파라미터 그룹: 클러스터 `<접두어>-rds-cpar-<엔진·주버전>-<DB 키>-01`, 인스턴스 `<접두어>-rds-pagrp-<엔진·주버전>-<DB 키>-01`
- CSV (DB마다, 없으면 생략): `src/rds-<DB 키>.cluster-parameters.csv`, `src/rds-<DB 키>.parameters.csv`, `src/rds-<DB 키>.sg_rules.csv`
- 비밀번호: RDS가 Secrets Manager로 관리 (읽기 인스턴스가 있어도 평문 비밀번호가 필요 없음)
