#!/usr/bin/env bash
############################################################
# 참조하지 않는 자식 모듈 검사 회귀 테스트
#
# 확인하는 것
#   deployment 폴더의 output precondition(network-base input_checks, ec2-<용도> alb_arn,
#   SG CSV helper ingress/egress)이 "루트에서 그 출력을 참조하지 않아도" plan을 막는지.
#   운영 루트(01-network, 02-compute)는 이 출력을 참조하지 않으므로, 같은 조건에서 확인합니다.
#
# 왜 스크립트인지
#   terraform test의 expect_failures는 루트 모듈의 객체만 가리킬 수 있어
#   자식 모듈 안의 실패를 "예상된 실패"로 적을 수 없습니다. 그래서 plan을 돌리고 결과를 직접 확인합니다.
#
# 방법
#   tests/main.tf에서 output을 모두 지운 임시 루트를 만들고(실행할 때마다 새로 생성),
#   경우마다 run 하나짜리 테스트 파일로 plan → 실패 여부와 메시지를 확인합니다.
#
# 실행: bash tests/nested_checks.sh   (deploy repo 루트 또는 tests 폴더 어디서든)
############################################################
set -u

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$TESTS_DIR/.nested_tmp"
cleanup() { cd "$TESTS_DIR" && rm -rf "$WORK"; }
trap cleanup EXIT

rm -rf "$WORK" && mkdir -p "$WORK/tests"

# 1) 출력이 없는 루트: tests/main.tf에서 output 블록 제거, 모듈 경로를 한 단계 더 위로
awk '/^output "/{skip=1} skip&&/^}/{skip=0;next} skip{next} {print}' "$TESTS_DIR/main.tf" \
  | sed 's|source *= *"\.\./deployment/|source = "../../deployment/|' > "$WORK/main.tf"
if grep -q '^output ' "$WORK/main.tf"; then echo "FAIL: 임시 루트에 output이 남아 있음"; exit 1; fi

# 2) mock 설정은 site.tftest.hcl 앞부분(첫 run 전까지)을 그대로 씀
HEADER="$(sed -n '1,/^run "/p' "$TESTS_DIR/site.tftest.hcl" | sed '$d')"

# 경우: 이름|기대 결과(fail/pass)|기대 메시지(fail일 때)|variables 블록 내용
CASES=(
  'valid_defaults|pass||'
  'small_routable_cidr|fail|첫 번째 routable 대역|vpc_cidrs = [{ cidr = "10.227.0.0/24", role = "routable" }]'
  'internet_alb_without_public|fail|외부용 ALB|was_alb_internal = false'
  'bad_common_sg_csv|fail|ec2-common/src/sg_rules.csv 오류|common_sg_rules_csv = "sg,no,direction,protocol,from_port,to_port,source,description,memo\ndb,1,ingress,tcp,22,22,pl:nope,ssh,\n"'
)

for c in "${CASES[@]}"; do
  IFS='|' read -r name expect message vars <<< "$c"
  { echo "$HEADER"; echo "run \"$name\" {"; echo "  command = plan"; echo "  variables {"; [ -n "$vars" ] && echo "    $vars"; echo "  }"; echo "}"; } > "$WORK/tests/$name.tftest.hcl"
done

cd "$WORK" || exit 1
terraform init -backend=false -input=false -no-color > init.log 2>&1 || { echo "FAIL: terraform init"; cat init.log; exit 1; }

failed=0
for c in "${CASES[@]}"; do
  IFS='|' read -r name expect message vars <<< "$c"
  # 경우마다 그 파일만 남기고 실행 (-filter 경로 표기가 OS마다 달라 파일을 옮겨서 격리)
  mkdir -p ../.nested_hold && mv tests/*.tftest.hcl ../.nested_hold/ && mv "../.nested_hold/$name.tftest.hcl" tests/
  terraform test -no-color > "$name.log" 2>&1
  rc=$?
  mv ../.nested_hold/*.tftest.hcl tests/ 2>/dev/null; rmdir ../.nested_hold 2>/dev/null

  if [ "$expect" = "pass" ]; then
    if [ $rc -eq 0 ]; then echo "PASS: $name (정상 입력은 통과)"; else echo "FAIL: $name (정상 입력인데 실패)"; failed=1; tail -20 "$name.log"; fi
  else
    if [ $rc -ne 0 ] && grep -q "precondition failed" "$name.log" && grep -q "$message" "$name.log"; then
      echo "PASS: $name (참조하지 않은 자식 모듈 검사로 plan 실패: '$message')"
    else
      echo "FAIL: $name (plan이 막히지 않았거나 메시지가 다름. 기대: '$message')"; failed=1; grep -E 'Error:|on \.\.' "$name.log" | head -6
    fi
  fi
done

cd "$TESTS_DIR"
exit $failed
