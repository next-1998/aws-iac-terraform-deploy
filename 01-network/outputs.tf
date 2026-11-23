output "sizing" {
  description = "설계서용 대역 배치 (AZ별 서브넷, 사용 가능 IP, 예비 공간)"
  value       = module.network_base.sizing
}

output "nat_public_ips" {
  description = "NAT 공인 IP (협력사 화이트리스트 등록용)"
  value       = module.network_base.contract.routing.nat_public_ips
}

output "parameters" {
  description = "다음 단계가 읽는 Parameter Store 경로"
  value       = values(module.contract.names)
}
