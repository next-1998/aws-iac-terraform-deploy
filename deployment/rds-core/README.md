# rds-core

RDS 공통 코어입니다. 엔진 조합(`rds-postgres`, `rds-mysql`, `rds-mariadb`)이 엔진 값과 CSV 폴더(`src_dir`)를 넘겨 호출합니다. 직접 호출하지 않습니다.

만드는 것: 파라미터 그룹, DB 인스턴스, 읽기 복제본, SG(기본 규칙 + CSV), DB 로그 그룹(복제본 포함), 백업 태그(`Backup-<플랜>`)
엔진별 차이(포트, 파라미터 그룹 family, 기본 로그, 이름의 엔진 코드·엔진·버전 코드)는 `locals.tf`의 `engine_defaults` 표 한 곳에 있습니다.
