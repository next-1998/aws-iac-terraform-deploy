# tests

`deployment/` 조합 코드를 검증하는 테스트입니다. mock provider를 쓰므로 **AWS에 접속하지 않고**, 실제 리소스도 만들지 않습니다.

```bash
terraform -chdir=tests init
terraform -chdir=tests test
```

- `main.tf`: 테스트용 사이트 구성 (network-base → ec2-common → ec2-was, ec2-webide). 실제 배포용이 아닙니다.
- `site.tftest.hcl`: 검사 항목
  - 네트워크 유형 2가지(routable 단독, routable + internal)의 대역 배치와 서브넷 겹침
  - AZ 2 → 3 → 4 증설 시 기존 서브넷 CIDR 유지
  - NAT AZ별(기본값) / 1개
  - 공통 SG 기본 규칙 없음, 인스턴스에 공통 SG + 개별 SG 연결
  - SSM endpoint 옵션, 다른 stack이 만든 endpoint skip, 자기 자신은 skip하지 않음
  - ALB 용도별 선택
  - 잘못된 입력 차단 (internal 대역, routable 크기, AZ 수, SG description 한글)

조합 코드나 module repo를 바꾼 뒤에는 이 테스트를 돌려서 확인합니다.
