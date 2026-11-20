# legacy (기존 구조, 참고용)

새 단계 구조(`00-bootstrap` ~ `04-pod`)로 옮기기 전의 코드입니다. **실행하지 않습니다.**

- `main.tf`, `variables.tf`, `terraform.auto.tfvars` 등: 기존 루트 구성
- `deployment/*`: 기존 조합 코드 (acm, elb, ec2, rds, lambda …)

새 구조로 옮길 때 참고할 자료(예: `deployment/lambda/lambda/weekend-stop/index.py`, `deployment/ec2/*/tpl/*.tpl`)를 위해 남겨 둡니다.
`terraform.auto.tfvars`에는 비밀번호, 계정 ID 같은 값이 들어 있으므로 새 구조에서는 그대로 옮기지 않습니다.
