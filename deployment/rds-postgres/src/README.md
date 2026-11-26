# rds-postgres SG 규칙

DB마다 `src/<name>.sg_rules.csv` 파일로 추가 규칙을 넣습니다 (예: `rds-app.sg_rules.csv`). 파일이 없으면 추가 규칙이 없습니다.

- 기본 규칙(코드): DB 포트 ← EC2 서브넷 대역 (`allowed_cidrs`로 바꿀 수 있음). 아웃바운드 없음
- CSV의 `sg` 열은 `db`만 씁니다. 형식은 module repo `module/_sg_rules_csv/README.md` (EC2 SG 규칙 CSV와 같음)
- 예제: `sg_rules.example.csv` (적용되지 않음)

# rds-postgres 파라미터

DB마다 `src/<name>.parameters.csv` 파일로 파라미터 그룹 값을 넣습니다 (예: `rds-app.parameters.csv`). 파일이 없으면 엔진 기본값입니다.

- 열: `no,name,value,apply_method,memo` (no = 순번, apply_method = immediate | pending-reboot, 비우면 pending-reboot)
- 정적(static) 파라미터는 pending-reboot만 가능합니다. 값을 바꾸면 DB 재부팅 후 적용됩니다
- 03-database tfvars의 `parameters`로 넣어도 됩니다. 둘 다 넣으면 plan에서 막힙니다
- 예제: `parameters.example.csv` (적용되지 않음)
