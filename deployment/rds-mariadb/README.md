# rds-mariadb

mariadb 엔진 조합입니다. 엔진 고정값(engine = "mariadb"), 엔진 전용 검사(고를 수 있는 로그 이름), CSV 예제만 두고 실제 구성은 `deployment/rds-core`가 합니다.

- 호출: 03-database의 `rds_mariadb` 목록 (DB 키마다 한 번)
- 이름: DB `<접두어>-rds-<엔진 코드>-<DB 키>-01`, 복제본 `…-ro-01`, 파라미터 그룹 `<접두어>-rds-pagrp-<엔진·주버전>-<DB 키>-01`
- CSV (DB마다, 없으면 생략): `src/rds-<DB 키>.parameters.csv` (파라미터 그룹), `src/rds-<DB 키>.sg_rules.csv` (추가 SG 규칙). 형식·예제는 `src/README.md`
