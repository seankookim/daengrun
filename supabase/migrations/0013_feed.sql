-- 0013: 동네 피드 — 완료 러닝 자랑 포스트 (옵트인: 보호자가 리포트에서 공유해야만 공개)
-- + 좋아요. 커뮤니티 탭의 실콘텐츠.

create table if not exists feed_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references profiles on delete cascade,
  booking_id uuid references bookings unique,   -- 러닝당 포스트 1개
  body text,
  photo_url text,
  meta jsonb not null default '{}',             -- {dogName, km, durationSec, badges[]}
  created_at timestamptz not null default now()
);
alter table feed_posts enable row level security;

drop policy if exists "feed read" on feed_posts;
create policy "feed read" on feed_posts for select using (true);
drop policy if exists "feed insert own" on feed_posts;
create policy "feed insert own" on feed_posts for insert with check (author_id = auth.uid());
drop policy if exists "feed delete own" on feed_posts;
create policy "feed delete own" on feed_posts for delete using (author_id = auth.uid());

create table if not exists feed_likes (
  post_id uuid not null references feed_posts on delete cascade,
  profile_id uuid not null references profiles on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, profile_id)
);
alter table feed_likes enable row level security;

drop policy if exists "likes read" on feed_likes;
create policy "likes read" on feed_likes for select using (true);
drop policy if exists "likes insert own" on feed_likes;
create policy "likes insert own" on feed_likes for insert with check (profile_id = auth.uid());
drop policy if exists "likes delete own" on feed_likes;
create policy "likes delete own" on feed_likes for delete using (profile_id = auth.uid());
