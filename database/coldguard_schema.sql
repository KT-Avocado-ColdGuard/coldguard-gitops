-- 온프렘 제공 확정 DDL (2026-11-18). 관리자만 실행한다.
-- 기존 테이블을 DROP/ALTER하거나 데이터를 이전하지 않는다.
CREATE TABLE IF NOT EXISTS telemetry (
 id BIGINT AUTO_INCREMENT PRIMARY KEY,
 site_id VARCHAR(20) NOT NULL,
 device_id VARCHAR(20) NOT NULL,
 seq BIGINT NOT NULL,
 measured_at DATETIME(3) NOT NULL,
 temp_c DECIMAL(5,2) NOT NULL,
 setpoint_c DECIMAL(5,2) NOT NULL,
 door_open BOOLEAN NOT NULL,
 cooling BOOLEAN NOT NULL,
 status VARCHAR(20) NOT NULL,
 received_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
 UNIQUE KEY uk_site_device_seq (site_id,device_id,seq),
 KEY idx_device_time (site_id,device_id,measured_at)
);
CREATE TABLE IF NOT EXISTS command_log (
 id BIGINT AUTO_INCREMENT PRIMARY KEY,
 cmd_id VARCHAR(50) NOT NULL,
 site_id VARCHAR(20) NOT NULL,
 device_id VARCHAR(20) NOT NULL,
 action VARCHAR(20) NOT NULL,
 value DECIMAL(6,2) NULL,
 issued_at DATETIME(3) NOT NULL,
 expires_at DATETIME(3) NOT NULL,
 issued_by VARCHAR(50) NOT NULL,
 result ENUM('accepted','rejected') NOT NULL,
 reason ENUM('locked','expired','out_of_range','duplicate','unknown_device','apply_timeout') NULL,
 setpoint_before DECIMAL(5,2) NULL,
 setpoint_after DECIMAL(5,2) NULL,
 decided_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
 KEY idx_cmd_id (cmd_id),
 KEY idx_device_time (site_id,device_id,decided_at)
);
CREATE TABLE IF NOT EXISTS event_log (
 id BIGINT AUTO_INCREMENT PRIMARY KEY,
 site_id VARCHAR(20) NOT NULL,
 device_id VARCHAR(20) NOT NULL,
 event_type VARCHAR(30) NOT NULL,
 severity ENUM('info','warning','critical') NOT NULL,
 temp_c DECIMAL(5,2) NULL,
 predicted_sec INT NULL,
 detail VARCHAR(255) NULL,
 occurred_at DATETIME(3) NOT NULL,
 KEY idx_device_time (site_id,device_id,occurred_at)
);
