# tests

`deployment/` 조합 코드를 단계 구분 없이 직접 이어서(network-base → shared-common → ec2-common → ec2-was, ec2-webide) 검사하는 통합 테스트입니다. mock provider를 쓰므로 **AWS에 접속하지 않습니다.**

```bash
terraform -chdir=tests init
terraform -chdir=tests test
```

검사 항목 (`site.tftest.hcl`)
- v1 배치 CIDR (AZ 2개, 3개 증설, 1개, 리전 AZ 목록), 서브넷 겹침, 예비 공간
- public 기본 꺼짐 / 켬(plan만: NAT EIP 삭제 보호 때문)
- EKS routable(뒤쪽 절반) / internal(100.64 자동 추가, AZ별 private NAT), NAT 1개 옵션
- 수동 서브넷 (예비 공간 안 / 밖이면 에러)
- 공통 SG 기본 규칙 없음, prefix list 참조, 기본 SG 잠금
- VPC endpoint 생성, 다른 state가 만든 endpoint skip
- ALB 용도별, 외부용은 public 필요, AZ 1개 에러, ACM 검증 레코드 위치
- 잘못된 입력 차단 (대역 크기, internal 대역, AZ 수, 배치 버전, SG 설명 한글)

단계 루트(00, 01, 02)의 연결(Parameter Store, 로그 버킷 선택)은 각 단계 폴더의 `tests/`에서 검사합니다.
