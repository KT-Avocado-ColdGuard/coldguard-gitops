# control-api (중앙 통제 API)

Deployment·Service 매니페스트를 이 폴더에 둔다. Argo CD Application `control-api`가 coldguard 네임스페이스로 배포한다.

- Service: 이름 `control-api`, 포트 80, ClusterIP (targetPort는 앱 포트)
- tailnet 노출은 `infra/aws/ingress/control-api.yaml`(Tailscale Ingress)이 맡는다.
- MySQL: `mysql.coldguard.svc.cluster.local:3306`, DB `coldguard_central`, 계정 `coldguard_api` (비밀번호는 Secret `mysql-auth`의 `api-password`)
- MQTT: `mosquitto.coldguard.svc.cluster.local:1883`, 계정 `control-api` (비밀번호는 별도 전달)
