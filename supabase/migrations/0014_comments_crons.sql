-- 0014: 피드 댓글 + 주간 TOP3 보상 크론 + 채팅 30일 보관 크론

-- ---------- 댓글 ----------
create table if not exists feed_comments (
  id bigint generated always as identity primary key,
  post_id uuid not null references feed_posts on delete cascade,
  author_id uuid not null references profiles on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);
alter table feed_comments enable row level security;

drop policy if exists "comments read" on feed_comments;
create policy "comments read" on feed_comments for select using (true);
drop policy if exists "comments insert own" on feed_comments;
create policy "comments insert own" on feed_comments for insert with check (author_id = auth.uid());
drop policy if exists "comments delete own" on feed_comments;
create policy "comments delete own" on feed_comments for delete using (author_id = auth.uid());

-- ---------- 주간 TOP3 댕마일 보상 (지난주 집계 — 매주 월요일 KST 자정 직후) ----------
create or replace function grant_weekly_rewards() returns void
language plpgsql security definer set search_path = public as $$
declare
  r record;
  amounts int[] := array[200, 100, 50];
  i int;
  week_start timestamptz := date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
begin
  -- 강아지(보호자) 부문: 지난주 km TOP3
  i := 1;
  for r in (
    select b.owner_id as pid
    from runs rr
    join bookings b on b.id = rr.booking_id and b.status = 'completed'
    where rr.ended_at >= week_start - interval '7 days' and rr.ended_at < week_start
    group by b.owner_id
    order by sum(rr.actual_km) desc
    limit 3
  ) loop
    insert into miles_ledger (profile_id, delta, reason) values (r.pid, amounts[i], 'weekly_top_dog');
    i := i + 1;
  end loop;

  -- 러너 부문: 지난주 러닝 수 TOP3
  i := 1;
  for r in (
    select b.runner_id as pid
    from runs rr
    join bookings b on b.id = rr.booking_id and b.status = 'completed' and b.runner_id is not null
    where rr.ended_at >= week_start - interval '7 days' and rr.ended_at < week_start
    group by b.runner_id
    order by count(*) desc
    limit 3
  ) loop
    insert into miles_ledger (profile_id, delta, reason) values (r.pid, amounts[i], 'weekly_top_runner');
    i := i + 1;
  end loop;
end $$;

-- ---------- 채팅 30일 보관 (안내 문구와 일치) ----------
create or replace function purge_old_chat() returns void
language sql security definer set search_path = public as $$
  delete from chat_messages where created_at < now() - interval '30 days';
$$;

-- ---------- pg_cron 스케줄 (미지원 환경에서도 마이그레이션이 죽지 않게) ----------
do $$ begin
  create extension if not exists pg_cron;
  -- KST 월 00:10 = UTC 일 15:10
  perform cron.schedule('weekly-rewards', '10 15 * * 0', 'select grant_weekly_rewards()');
  -- 매일 KST 04:00 = UTC 19:00
  perform cron.schedule('purge-chat', '0 19 * * *', 'select purge_old_chat()');
exception when others then
  raise notice 'pg_cron unavailable — schedule manually: %', sqlerrm;
end $$;
