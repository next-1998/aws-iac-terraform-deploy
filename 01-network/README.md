# 01-network

사이트의 VPC와 기본 네트워크를 만들고, 결과를 Parameter Store(`/iac/<site>/01-network/*`)에 남깁니다. 조합 코드는 `deployment/network-base`입니다.

```bash
cp backend.hcl.example backend.hcl   # 값 입력
terraform init -backend-config=backend.hcl
terraform plan                       # sizing 출력으로 대역 배치 확인
terraform apply
```

- 입력과 제약 사항은 `terraform.tfvars` 주석을 보세요.
- 실행 전: 00-bootstrap 완료, routable 대역 할당, (TGW 연결 시) 중앙 네트워크 계정의 자동 수락·승인 설정
- 출력: `sizing`(설계서용), `nat_public_ips`(화이트리스트용), `parameters`
