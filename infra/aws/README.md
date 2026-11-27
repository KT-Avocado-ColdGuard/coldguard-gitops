# infra/aws (Cloud 담당)

AWS EKS에 올라가는 공용 인프라입니다. Argo CD Application `infra-aws`가 이 폴더(kustomize)를 배포합니다.

| 폴더 | 리소스 | 내용 |
|---|---|---|
| base | Namespace `coldguard`, `monitoring` | coldguard는 Pod Security baseline, monitoring은 privileged(Fluent Bit hostPath) |
| base | ResourceQuota, LimitRange | coldguard 네임스페이스 상한과 requests·limits 기본값 |
| base | ServiceAccount `s3-backup` | Terraform이 Pod Identity로 S3 백업 role을 연결해 둔 이름 |
| base | Service `kt-hub` (monitoring) | KT 관제 허브(tailnet)로 나가는 Tailscale operator egress. 9090(remote_write), 3100(Loki) |
| mysql | StatefulSet `mysql` (8.4, 1개) | gp3 10Gi, DB `coldguard_central`, 통제 API 계정 `coldguard_api`, 수집 워커 계정 `coldguard_worker` |
| mysql | ConfigMap `mysql-initdb` | 첫 기동 때만 실행. 중앙 스키마(telemetry, event_log, command_ack, command_request)와 계정(수집 워커, 통제 API, 감시) |
| backup | CronJob `mysql-backup` | 매일 03:00 KST, mysqldump → S3 `mysql/` (7일 보관) |
| mosquitto | Deployment `mosquitto` (2.1.2) | 1883 클러스터 내부용, 8883 TLS 시설 브리지용. 계정별 토픽 ACL |
| mosquitto | Service `mosquitto-tailnet` | 8883을 tailnet에 `coldguard-mqtt`로 노출 (`tag:eks-mqtt`) |
| ingress | Ingress `control-api-tailnet` | 통제 API를 tailnet에 `control-api`로 HTTPS 노출 (`tag:eks-api`) |
| ingress | Ingress `argocd-tailnet` (argocd) | Argo CD 화면을 tailnet에 `argocd`로 HTTPS 노출 (`tag:eks-argocd`) |

모니터링 에이전트는 `monitoring/`(모니터링 담당), 중앙 수집 워커와 통제 API는 비공개 저장소 coldguard-deploy(`central-worker/`, `control-api/`)에 있고 각각 별도 Application으로 배포합니다.

## 사전 조건

- Terraform(인프라)과 bootstrap(gp3 StorageClass, Argo CD, Tailscale operator) apply 완료
- Tailscale 관리 콘솔에서 MagicDNS와 HTTPS Certificates 켜짐 (Tailscale Ingress가 인증서를 받는 데 필요)
- Tailscale ACL에 `tag:k8s-operator`, `tag:k8s`, `tag:eks-api`, `tag:eks-mqtt`, `tag:eks-argocd`, `tag:eks-egress` 등록

## 비밀값 준비 (Argo CD 동기화 전)

Git에 넣지 않는 값은 클러스터에서 직접 만듭니다. Secret이 없으면 해당 Pod가 뜨지 않습니다.

```bash
kubectl create namespace coldguard

# 1. MySQL 비밀번호
kubectl -n coldguard create secret generic mysql-auth \
  --from-literal=root-password="$(openssl rand -base64 24)" \
  --from-literal=api-password="$(openssl rand -base64 24)" \
  --from-literal=worker-password="$(openssl rand -base64 24)"

# 2. 백업 버킷 이름
kubectl -n coldguard create configmap backup-params \
  --from-literal=BACKUP_BUCKET="$(terraform -chdir=<coldguard-iac 경로>/terraform output -raw backup_bucket_name)"

# 3. Mosquitto 계정 (평문은 표준입력으로만 넘기고 해시된 파일만 받는다)
#    계정: site01-bridge, site02-bridge, control-api, central-worker
cat > /tmp/mq-plain <<'EOP'
site01-bridge:<비밀번호>
site02-bridge:<비밀번호>
control-api:<비밀번호>
central-worker:<비밀번호>
EOP
kubectl -n coldguard run mqpasswd --rm -i --quiet --restart=Never --image=eclipse-mosquitto:2.1.2-alpine \
  --command -- sh -c 'cat > /tmp/p && mosquitto_passwd -U /tmp/p 2>/dev/null && cat /tmp/p' < /tmp/mq-plain > passwd
rm -f /tmp/mq-plain
cat passwd   # 네 줄, 각각 "이름:$7$..." 형태인지 확인
kubectl -n coldguard create secret generic mosquitto-auth --from-file=passwd=passwd
rm -f passwd

# 3-1. 계정 추가 (예: 부하 시험용 kt-load). 기존 해시는 그대로 두고 한 줄만 붙인다.
#      브로커는 시작할 때만 파일을 읽으므로, configmap.yaml의 ACL 변경과 함께 브로커가 재시작돼야 적용된다.
kubectl -n coldguard get secret mosquitto-auth -o jsonpath='{.data.passwd}' | base64 -d > passwd
printf 'kt-load:%s\n' '<비밀번호>' | kubectl -n coldguard run mqpasswd --rm -i --quiet --restart=Never \
  --image=eclipse-mosquitto:2.1.2-alpine --command -- sh -c 'cat > /tmp/p && mosquitto_passwd -U /tmp/p 2>/dev/null && cat /tmp/p' >> passwd
cut -d: -f1 passwd   # 계정 이름만 확인 (kt-load가 한 번만 있어야 함)
kubectl -n coldguard create secret generic mosquitto-auth --from-file=passwd=passwd --dry-run=client -o yaml | kubectl apply -f -
rm -f passwd

# 4. Mosquitto TLS (보안 담당이 서명한 인증서, CA 인증서, 직접 만든 개인키)
kubectl -n coldguard create secret generic mosquitto-tls \
  --from-file=ca.crt=ca.crt \
  --from-file=tls.crt=coldguard-mqtt.crt \
  --from-file=tls.key=coldguard-mqtt.key
```

브리지 비밀번호는 온프렘 담당에게, `control-api`·`central-worker` 비밀번호와 MySQL 계정은 각 앱 담당에게 따로 전달합니다.

## 확인

```bash
kubectl -n coldguard get pods,pvc,svc,ingress
kubectl get svc -n monitoring kt-hub   # EXTERNAL-IP 자리에 operator가 만든 이름이 보여야 함

# MySQL: 스키마와 계정
kubectl -n coldguard exec mysql-0 -- sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -e "SHOW TABLES FROM coldguard_central; SELECT user,host FROM mysql.user;"'

# Mosquitto: 내부 리스너로 발행 (계정이 맞으면 성공)
kubectl -n coldguard run mqtest --rm -it --restart=Never --image=eclipse-mosquitto:2.1.2-alpine -- \
  mosquitto_pub -h mosquitto -p 1883 -u control-api -P '<비밀번호>' -t coldguard/site01/fz01/cmd -m test

# tailnet 노출: 관리 콘솔 Machines에 coldguard-mqtt, control-api, argocd와 egress 프록시가 보여야 함
# 시설 VM에서 TLS 확인
openssl s_client -connect coldguard-mqtt.<tailnet>.ts.net:8883 -CAfile ca.crt </dev/null | grep -E "Verify return code|subject="

# KT 허브 egress (monitoring 네임스페이스에서)
kubectl -n monitoring run nettest --rm -it --restart=Never --image=curlimages/curl -- \
  curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://kt-hub:9090/-/healthy

# 백업 수동 실행
kubectl -n coldguard create job --from=cronjob/mysql-backup mysql-backup-manual-1
kubectl -n coldguard logs job/mysql-backup-manual-1 -c upload
```

## 주의

- gp3 StorageClass의 reclaimPolicy가 Delete라서 PVC를 지우면 EBS 볼륨과 데이터도 지워집니다. Application `infra-aws`를 지우면 네임스페이스까지 지워지므로 MySQL·Mosquitto 데이터가 모두 사라집니다.
- `mysql-initdb`는 데이터 디렉터리가 비어 있을 때만 실행됩니다. 스키마를 바꾸면 기존 DB에는 직접 ALTER를 실행해야 합니다.
- 노드를 밤에 0으로 내려 두면 03:00 백업은 실행되지 않습니다(1시간 뒤 건너뜀). 필요하면 수동 실행을 씁니다.
- 시설 브리지 설정에서 `notifications false`로 두는 것을 권합니다. 켜 두면 브리지가 `$SYS/broker/connection/...`에 상태를 발행하려다 ACL에 막혀 로그가 남습니다.
- 수집 워커는 `$share/central-worker/coldguard/+/+/{telemetry,ack,event}`로 공유 구독합니다(그룹 이름 고정). ACL 통과는 배포 후 아래처럼 확인합니다.

  ```bash
  # 터미널 1: 워커 계정으로 공유 구독
  kubectl -n coldguard run mqsub --rm -it --restart=Never --image=eclipse-mosquitto:2.1.2-alpine -- \
    mosquitto_sub -h mosquitto -p 1883 -u central-worker -P '<비밀번호>' -t '$share/central-worker/coldguard/+/+/telemetry' -v
  # 터미널 2: 브리지 계정으로 발행 → 터미널 1에 찍히면 통과
  kubectl -n coldguard run mqpub --rm -it --restart=Never --image=eclipse-mosquitto:2.1.2-alpine -- \
    mosquitto_pub -h mosquitto -p 1883 -u site01-bridge -P '<비밀번호>' -t coldguard/site01/fz01/telemetry -m test
  ```
- 중앙 스키마는 초안입니다. 수집 워커와 통제 API 구현이 정해지면 함께 맞춥니다.
