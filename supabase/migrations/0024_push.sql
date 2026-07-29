-- 0024: APNs 푸시 (Expo Push 경유) — 러너 응답 속도가 '앱 열림'에 의존하던 마켓플레이스 병목 해소.
-- 구조: notifications INSERT 트리거 → pg_net으로 Expo Push API 호출.
--   기존 notify() 호출 지점(transition-booking · settle_run_tx · 크론들) 전부가 코드 수정 0으로 푸시가 된다.
--
-- 토큰은 별도 테이블 — profiles에 두면 'profiles public runner read' 정책으로
-- 러너 토큰이 공개 노출된다 (타인이 내 기기로 푸시를 쏠 수 있는 구멍). 자기만 읽고 쓴다.

create extension if not exists pg_net;

create table push_tokens (
  profile_id uuid primary key references profiles(id) on delete cascade,
  token text not null,
  updated_at timestamptz not null default now()
);
alter table push_tokens enable row level security;
create policy "push self all" on push_tokens for all
  using (profile_id = auth.uid()) with check (profile_id = auth.uid());

-- 알림 → 푸시 브릿지. 실패해도 알림 저장은 막지 않는다 (푸시는 부가 채널).
create or replace function notify_push() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_token text;
begin
  select token into v_token from push_tokens where profile_id = new.profile_id;
  if v_token is not null and v_token like 'ExponentPushToken%' then
    perform net.http_post(
      url := 'https://exp.host/--/api/v2/push/send',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object(
        'to', v_token,
        'title', new.title,
        'body', coalesce(new.body, ''),
        'sound', 'default',
        'data', jsonb_build_object('kind', new.kind, 'ref_id', new.ref_id)
      )
    );
  end if;
  return new;
exception when others then
  return new;
end $$;

drop trigger if exists notifications_push on notifications;
create trigger notifications_push after insert on notifications
  for each row execute function notify_push();

comment on table push_tokens is 'Expo 푸시 토큰 — 본인만 읽기/쓰기 (프로필 공개 정책과 분리)';
