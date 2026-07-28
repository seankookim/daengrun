-- 0016: 일정 변경 제안 (reschedule-as-proposal)
-- 확정 예약은 계약 — 시간 변경은 조용한 UPDATE가 아니라 러너 동의 절차다.
-- 보호자가 새 시간을 제안 → 러너 수락 시에만 scheduled_at 변경 (수락 시점에 슬롯 재검증).
-- 만료는 레이지: 원래 시작 시간 2시간 전을 지나면 서버가 수락을 거부하고, 클라이언트는 목록에서 제외.

alter table bookings
  add column if not exists reschedule_new_time timestamptz,
  add column if not exists reschedule_proposed_at timestamptz;

comment on column bookings.reschedule_new_time is
  '보호자 제안 새 시간 — 러너 수락 전까지 scheduled_at 불변. 원 시간 2h 전 자동 만료(레이지 검증)';
comment on column bookings.reschedule_proposed_at is '제안 시각 (재제안 시 갱신)';
