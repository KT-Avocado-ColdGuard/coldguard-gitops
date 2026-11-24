# monitoring (모니터링 담당)

Prometheus Agent, kube-state-metrics, Fluent Bit 매니페스트를 이 폴더에 둔다. Argo CD Application `monitoring`이 이 폴더를 그대로 배포한다.

- 네임스페이스 `monitoring`은 `infra/aws/base/namespaces.yaml`에 있다(Pod Security privileged). 여기에는 넣지 않는다.
- KT 허브 주소는 egress Service를 쓴다.
  - remote_write: `http://kt-hub.monitoring.svc.cluster.local:9090/api/v1/write`
  - Loki push: `http://kt-hub.monitoring.svc.cluster.local:3100/loki/api/v1/push`
- ClusterRole·ClusterRoleBinding·ServiceAccount는 함께 넣는다.
- 노드당 Pod 17개 제한이 있으니 DaemonSet 외에는 replicas 1로 둔다.
