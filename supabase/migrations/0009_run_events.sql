-- 0009: 러닝 이벤트 — 응가 도장·간식·물·사진 순간 기록 (러너 원탭 → 보호자 알림 + 리포트 스탬프)
-- [{ kind: 'poop'|'snack'|'water'|'photo', at: iso }]
alter table runs add column if not exists events jsonb not null default '[]';

-- 예약 당사자가 상대에게 booking 알림을 보낼 수 있게 (러닝 이벤트 실시간 알림용)
drop policy if exists "noti party insert" on notifications;
create policy "noti party insert" on notifications
  for insert with check (
    kind = 'booking' and ref_id is not null and exists (
      select 1 from bookings b
      where b.id = ref_id
        and (b.owner_id = auth.uid() or b.runner_id = auth.uid())
        and (notifications.profile_id = b.owner_id or notifications.profile_id = b.runner_id)
    )
  );
