# ColdGuard GitOps

배포 설정 / DB 초기화 / MQTT 규격을 관리합니다.

- database/: 관리자용 DB 초기화 SQL
- docs/: 연동 규격과 배포 안내
- k8s/: 배포 파일 작성 예정. 현재 .gitkeep만 있으며 배포 리소스는 미작성입니다.
- argocd/: Argo CD AppProject와 Application (루트 Application이 이 폴더를 배포합니다. Cloud 담당과 협의)
- infra/aws/: AWS EKS 공용 인프라 (Cloud 담당). [안내](infra/aws/README.md)
- infra/aws/monitoring/: EKS 모니터링 에이전트 (모니터링 담당)
- 중앙 수집 워커·통제 API 매니페스트는 비공개 저장소 coldguard-deploy에 있습니다(이미지 주소에 AWS 계정 ID가 들어가기 때문).
- 비밀번호/Secret 실제 값/인증서는 커밋하지 않습니다.
