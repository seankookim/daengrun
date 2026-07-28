-- 0019: 러너 장비 (loadout) — 러너가 러닝에 들고 오는 장비를 슬롯제로 등록하는 스토어프런트 요소.
-- RPG 로드아웃 콘셉트: kind당 1슬롯 (리드줄·러닝 장비·급수·간식·바디캠).
--
-- 인증 원칙 (정직 도그마): '사진이 곧 인증' — verified_at은 photo_url이 있을 때만 존재할 수 있다.
-- 체크 제약이 이를 DB에서 강제한다. 클라이언트가 사진 없이 인증을 주장할 방법이 없음.
--
-- 매칭 가드레일: 인증 장비는 매칭 점수에 최대 +2만 기여 (클라이언트 Math.min(2, n)).
-- 핵심 점수(응답률·경험·페이스)는 불변 — 장비는 신뢰 신호이지 pay-to-win 축이 아니다.

create table runner_gear (
  id uuid primary key default gen_random_uuid(),
  runner_id uuid not null references runners(profile_id) on delete cascade,
  kind text not null check (kind in ('leash', 'apparel', 'water', 'treats', 'bodycam')),
  label text not null,
  photo_url text,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  unique (runner_id, kind),                        -- 슬롯제 — kind당 1개 (부스트 파밍 차단)
  check (verified_at is null or photo_url is not null)  -- 사진 없는 인증 금지
);

alter table runner_gear enable row level security;

-- 공개 읽기 — 스토어프런트/매칭 카드에서 누구나 조회 (runners public read와 동일 성격)
create policy "gear public read" on runner_gear for select using (true);
-- 본인만 쓰기
create policy "gear self insert" on runner_gear for insert with check (runner_id = auth.uid());
create policy "gear self update" on runner_gear for update using (runner_id = auth.uid());
create policy "gear self delete" on runner_gear for delete using (runner_id = auth.uid());

create index runner_gear_runner_idx on runner_gear (runner_id);

comment on table runner_gear is '러너 로드아웃 — kind당 1슬롯, 사진이 곧 인증(verified_at ⇒ photo_url)';
