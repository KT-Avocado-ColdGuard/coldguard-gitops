# monitoring (모니터링 담당)

Prometheus Agent, kube-state-metrics, Fluent Bit 매니페스트를 이 폴더에 둔다. Argo CD Application `monitoring`이 이 폴더를 그대로 배포한다.

- 네임스페이스 `monitoring`은 `infra/aws/base/namespaces.yaml`에 있다(Pod Security privileged). 여기에는 넣지 않는다.
- KT 허브 주소는 egress Service를 쓴다.
  - remote_write: `http://kt-hub.monitoring.svc.cluster.local:9090/api/v1/write`
  - Loki push: `http://kt-hub.monitoring.svc.cluster.local:3100/loki/api/v1/push`
- ClusterRole·ClusterRoleBinding·ServiceAccount는 함께 넣는다.
- 노드당 Pod 17개 제한이 있으니 DaemonSet 외에는 replicas 1로 둔다.

## 구성

| 파일 | 리소스 | 하는 일 |
|---|---|---|
| `rbac.yaml` | ServiceAccount 3개, ClusterRole·Binding 2쌍 | Agent는 노드·Pod 찾기와 cAdvisor 읽기, kube-state-metrics는 오브젝트 list/watch (읽기 전용) |
| `prometheus-agent.yaml` | ConfigMap, Deployment (1개) | kube-state-metrics · cAdvisor(컨테이너 CPU·메모리·네트워크) · `prometheus.io/scrape: "true"` 붙은 coldguard Pod 수집 → 허브 remote_write |
| `kube-state-metrics.yaml` | Deployment (1개), Service | Deployment·Pod·PVC 상태 지표 |
| `fluent-bit.yaml` | ConfigMap, DaemonSet | `coldguard` 네임스페이스 컨테이너 로그 → 허브 Loki |

- 모든 지표·로그에 `site=central, env=demo`가 붙는다(지표는 `cluster=coldguard-eks`도). 시설은 `site01`·`site02`.
- Loki `app` 라벨 = 컨테이너 이름. 시설과 같은 방식.
- 앱 지표를 수집하려면 Pod 템플릿에 `prometheus.io/scrape: "true"`, `prometheus.io/port: "<포트>"`(경로가 `/metrics`가 아니면 `prometheus.io/path`)를 붙인다.

## 확인

```bash
kubectl -n monitoring get pods                      # agent 1, ksm 1, fluent-bit 노드 수만큼
kubectl -n monitoring logs deploy/prometheus-agent | grep -i "remote\|error" | tail
kubectl -n monitoring logs ds/fluent-bit | grep -i "error\|loki" | tail
```

허브에서: Prometheus `up{site="central"}`, Loki `{site="central"}`.
