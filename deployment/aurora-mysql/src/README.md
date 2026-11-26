# aurora-mysql 파라미터·SG 규칙

DB 키마다 아래 파일을 두면 적용됩니다. 파일이 없으면 엔진 기본값 / 추가 규칙 없음입니다.

| 파일 | 적용 대상 | 예제 |
|---|---|---|
| `rds-<DB 키>.cluster-parameters.csv` | 클러스터 파라미터 그룹 (문자셋, 시간대, SSL 등 클러스터 전체) | `cluster-parameters.example.csv` |
| `rds-<DB 키>.parameters.csv` | 인스턴스 파라미터 그룹 (로그, 메모리 등 인스턴스별) | `parameters.example.csv` |
| `rds-<DB 키>.sg_rules.csv` | 클러스터 SG 추가 규칙 (`sg` 열 = `db`) | `sg_rules.example.csv` |

- 파라미터 열: `no,name,value,apply_method,memo` (apply_method = immediate | pending-reboot, 비우면 pending-reboot)
- 어떤 파라미터가 클러스터용인지 인스턴스용인지는 엔진 문서를 따릅니다 (잘못 넣으면 apply에서 AWS가 거부)
- SG CSV 형식은 module repo `module/_sg_rules_csv/README.md`
