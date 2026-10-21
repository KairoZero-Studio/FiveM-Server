-- #N-3: 관리 시간(duty_minute) 분리 누적 — total_minute(접속) 옆에 신설
ALTER TABLE cookie_admin
  ADD COLUMN IF NOT EXISTS duty_minute INT(11) NOT NULL DEFAULT 0 AFTER total_minute;
