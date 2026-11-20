# ColdGuard 온프렘 MQTT·DB 규격 v1 (2026-11-18)

클라우드 MQTT 메시지 규격 제안(11/17)을 기준으로, 온프렘 내부 동작에 필요한 부분을 보완함. 개발 담당 위임으로 온프렘이 확정.

## 1. ID 규칙
- 시설 ID: `site01` (시설 1곳)
- 장비(냉동고) ID: `fz01`, `fz02`, ... (영문 소문자+숫자)
- 시뮬레이터 1개 = 냉동고 1대. MQTT 계정 이름 = 장비 ID

## 2. 토픽 (`coldguard/site01/<장비ID>/...`)
| 토픽 | 흐름 | AWS 브릿지 |
|---|---|---|
| telemetry | 냉동고 → collector, web, AWS (1초) | 올림 |
| cmd | AWS 제어 API → controller 전용 | 내림 |
| ack | controller → AWS, web | 올림 |
| event | collector(경보), controller(차단) → AWS, web | 올림 |
| apply (내부) | controller → 냉동고 (검증 통과 명령만) | 넘기지 않음 |
| applied (내부) | 냉동고 → controller (적용 완료) | 넘기지 않음 |
| door (내부) | web → 냉동고 (문 열기/닫기) | 넘기지 않음 |
| lock (내부) | web → controller (장비별 현장 잠금 설정/해제) | 넘기지 않음 |

- 모든 토픽 QoS 1. `lock`만 `retain=true`, 나머지는 `retain=false`
- lock은 장비별 마지막 잠금 상태를 보관하여 controller 재접속 시 전달한다.
- 시각은 모두 UTC + `Z` (예: `2026-11-17T09:12:03Z`), 화면 표시만 KST 변환

## 3. 메시지 형식
telemetry
```json
{"site_id":"site01","device_id":"fz01","seq":10421,"measured_at":"2026-11-17T09:12:03Z",
 "temp_c":-29.8,"setpoint_c":-30.0,"door_open":false,"cooling":true,"status":"normal"}
```
- seq: 장비별 1씩 증가, 재시작 시 이어서(파일 저장), 재전송 시 같은 값. 중복 키 `(site_id, device_id, seq)`
- status: `normal`(≤ -25°C) / `high_temp`(> -25°C). 조기 경보는 collector가 판단해 event로 발행

cmd (클라우드 규격 그대로)
```json
{"site_id":"site01","device_id":"fz01","cmd_id":"site01-77","action":"set_temp","value":-20.0,
 "issued_at":"...Z","expires_at":"...Z","issued_by":"operator01"}
```
- 허용 action: `set_temp` 1개. 허용 범위 `-50 <= value < -10`
- controller 검사 순서: `unknown_device` → `duplicate` → `expired` → `locked` → `out_of_range`
- `issued_at`이 현재보다 미래라는 이유로 거부하지 않는다. 미래 시각 오차 제한은 제거했다(2026-11-20).
- 명령 유효시간은 `0 < expires_at - issued_at <= 300초`여야 한다.
- `expires_at`이 현재 시각 이하이면 만료다. 유효시간 위반도 ack의 `reason=expired`로 거부한다.
- 명령 발행자와 controller의 시스템 시각을 동기화한다.

apply
```json
{"site_id":"site01","device_id":"fz01","cmd_id":"site01-77","action":"set_temp","value":-20.0,"approved_at":"...Z","expires_at":"...Z"}
```
- `expires_at`은 원래 cmd의 값을 그대로 전달하며 승인 시 유효시간을 연장하지 않는다.
- 시뮬레이터는 신규 명령 적용 전에 만료 시각을 검사한다. 만료된 명령은 적용하지 않고, 이미 적용된 동일 명령의 재전송은 재적용하지 않는다.

applied
```json
{"site_id":"site01","device_id":"fz01","cmd_id":"site01-77","setpoint_c":-20.0,"at":"...Z"}
```
ack (클라우드 규격 그대로)
```json
{"cmd_id":"site01-77","result":"rejected","reason":"out_of_range","at":"...Z"}
```
- result: `accepted` / `rejected`
- reason: `locked`, `expired`, `out_of_range`, `duplicate`, `unknown_device`, `apply_timeout`(추가 제안: apply 후 5초 내 applied 없음)

door
```json
{"site_id":"site01","device_id":"fz01","action":"open","requested_by":"web","at":"...Z"}
```
lock (내부 / 이 토픽만 retain=true)
```json
{"site_id":"site01","device_id":"fz01","locked":true,"by":"web","at":"2026-11-18T07:30:00Z"}
```
- 토픽 예: `coldguard/site01/fz01/lock`
- 현장 웹에서 냉동고별 잠금 토글로 설정한다. `locked=true`는 잠금, `false`는 해제다.
- controller가 장비별 잠금 상태를 보관하고 원격 명령을 검사한다. 시뮬레이터에서 잠금을 판단하지 않는다.
- 잠금 상태가 없는 장비는 기본 해제다. 저장된 잠금 상태가 있으면 재시작만으로 해제하지 않는다.
- 잠금 중 AWS 원격 명령은 `ack: rejected / locked`로 거부한다. 앞선 검증에서 거부된 명령은 위 검사 순서의 사유를 따른다.
- 현장 웹의 문 열기/닫기는 잠금과 무관하게 허용한다. 잠금 설정과 해제는 현장 웹만 가능하며 AWS에는 권한을 주지 않는다.
- 잠금 변경 시 controller가 `lock_on / lock_off` 이벤트를 발행하고 event_log에 기록한다.

event
```json
{"site_id":"site01","device_id":"fz01","event_type":"early_warning","severity":"warning",
 "temp_c":-26.1,"predicted_sec":95,"detail":"...","at":"...Z"}
```
- event_type: `early_warning`, `high_temp`, `data_lost`, `cmd_rejected`, `lock_on`, `lock_off`
- lock_on은 잠금, lock_off는 해제 이벤트다. severity는 info이며 temp_c와 predicted_sec는 null로 전달할 수 있다.

## 4. MQTT 계정·ACL (온프렘 Mosquitto)
| 계정 | 쓰기 | 읽기 |
|---|---|---|
| fz01, fz02… (자기 장비만, %u 패턴) | telemetry, applied | apply, door |
| collector | event | telemetry |
| controller | apply, ack, event | cmd, applied, lock |
| web | door, lock | telemetry, ack, event |
| aws-bridge | cmd | telemetry, ack, event |
| exporter | – | $SYS/# |

- 온프렘에서는 aws-bridge에 `#` 전체 권한을 주지 않음 (apply 직접 쓰기로 controller 우회 방지)

- web의 시설 내 장비별 lock 발행 / controller의 lock 구독 권한을 허용한다. 예: `coldguard/site01/+/lock`
- 장비 계정과 aws-bridge에는 lock 발행 권한을 주지 않는다.

## 5. MySQL (coldguard DB, UTC 저장)
- telemetry: UNIQUE(site_id, device_id, seq)
- command_log: 명령별 결정 기록(중복 시도도 기록하므로 cmd_id는 UNIQUE 아님), setpoint_before/after
- event_log: 경보·차단·잠금 설정/해제 이벤트 (lock_on / lock_off 포함)
- 계정: collector(SELECT, INSERT) / controller(SELECT, INSERT) / web(SELECT)

## 6. 앱 환경변수·포트
- MQTT_HOST=mosquitto, MQTT_PORT=8883, MQTT_CA=/etc/coldguard/ca.crt, MQTT_USER, MQTT_PASS
- MYSQL_HOST=mysql, MYSQL_PORT=3306, MYSQL_DB=coldguard, MYSQL_USER, MYSQL_PASSWORD
- /metrics: collector :9201, controller :9202 / web :8080
- 외부 냉동고 시뮬레이터 접속: <MQTT_HOST>:8883 (Tailscale, IP로 접속)

## 7. 클라우드 쪽 확인 필요
1. 중복 키 `(site_id, seq)` → `(site_id, device_id, seq)` 변경
2. 내부 토픽(apply·applied·door·lock)은 브릿지 대상 아님
3. telemetry에 door_open, cooling 추가
4. reason에 apply_timeout 추가

5. cmd 발급 시 최대 유효시간 300초 준수 (미래 시각 오차 제한 없음)
6. AWS는 현장 잠금 설정/해제 불가. 잠금 결과는 ack의 locked 및 event의 lock_on / lock_off로 확인

## 8. 추가 합의 반영 및 배포 확인 (2026-11-18)
- apply의 expires_at / lock 토픽·ACL·이벤트 / 명령 시각 검증 기준을 추가 합의에 따라 본 문서에 반영했다.
- 문서 수정은 실제 Mosquitto ACL 변경이나 배포 완료를 의미하지 않는다.
- 온프렘 배포 시 web의 lock 발행 / controller의 lock 구독 ACL을 적용하고 내부 토픽의 AWS 브릿지 제외를 확인한다.
- lock만 retain=true이며 재접속한 controller에 마지막 잠금 상태가 전달되는지 확인한다.
- apply가 원래 expires_at을 전달하고 만료된 신규 명령이 적용되지 않는지 확인한다.
- 잠금 중 원격 명령 거부 / 문 조작 허용 / 현장 웹에서 해제 후 정상 제어를 확인한다.
- lock_on / lock_off 이벤트 발행 및 MySQL 기록을 확인한다.
- 계정 발급 / 비밀번호 전달 / 인증서 및 실제 송수신 검증은 별도로 수행한다.
