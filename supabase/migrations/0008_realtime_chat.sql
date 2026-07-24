-- 0008: 실시간 — 채팅 스레드 생성 정책 + Realtime 구독 대상 등록
-- chat_threads엔 select 정책만 있어 스레드를 만들 수 없었음 (읽기 전용 채팅의 역설)

drop policy if exists "threads party insert" on chat_threads;
create policy "threads party insert" on chat_threads
  for insert with check (is_booking_party(booking_id));

-- Realtime 발행 등록 (idempotent) — RLS는 구독에도 그대로 적용됨
do $$ begin
  alter publication supabase_realtime add table chat_messages;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table bookings;
exception when duplicate_object then null; end $$;

do $$ begin
  alter publication supabase_realtime add table notifications;
exception when duplicate_object then null; end $$;
