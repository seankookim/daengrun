-- 0074 — 인스타식 계정 아이디(@handle) + 피드가 주장할 수 있는 것의 경계
--
-- Sean 2026-08-12: "let's not restrict what the users will be uploading" · "the users themselves
-- should make account ids like instagram and those ids should be shown like insta".
--
-- 두 반쪽이 사실은 한 질문이라 한 파일에 있다: **누가 올리는가**(handle)와
-- **그 글이 무엇을 주장해도 되는가**(claim gate).
--
-- ═══ §A 왜 자유 업로드에도 게이트가 하나 필요한가 (이 마이그레이션의 핵심 판단) ═══
-- Sean의 지시는 "업로드를 제한하지 말라"이고 그건 그대로 따른다. 그런데 어제 감사에서 나온 사실이
-- 하나 있다: `feed_posts.meta`는 **클라가 주는 대로** 들어가고, INSERT 정책은
-- `with check (author_id = auth.uid())` — 작성자만 본다. 즉 오늘 이미 누구나
-- `meta:{km:42.2, badges:['★ 역대 최장 거리']}`를 실제로 달리지 않고 올릴 수 있다.
--
-- "제한하지 말라"를 "아무 주장이나 해도 된다"로 읽으면 정직법이 무너진다. 그래서 선을
-- **업로드의 자유**가 아니라 **주장의 종류**에 긋는다:
--   · 사진·글만 있는 포스트 → **완전 자유**. booking_id 없이 올라간다. (F1이 이걸 핀으로 박는다 —
--     다음 세션이 "완료된 러닝만"으로 되돌리지 못하게. 이건 Sean의 결정이다.)
--   · **러닝을 주장하는 포스트**(meta에 km/durationSec/trace 중 하나라도 = 측정된 수행) → 그 러닝이
--     실재해야 한다. 내 예약이어야 하고, runs 행이 있어야 한다.
--     (`badges`가 왜 이 목록에 없는지는 §D 주석에 — 하네스가 가르쳐준 것이다.)
-- 자랑은 누구나, 기록은 달린 사람만. 업로드는 하나도 안 막힌다.
--
-- ⚠ CHECK 제약이 아니라 **트리거**인 이유: CHECK는 기존 행을 검증하므로, 프로덕션에 이미 있는
-- 포스트 중 하나라도 어긋나면 마이그레이션이 실패한다. 트리거는 새 쓰기에만 건다.
--
-- ═══ §B handle 형식 ═══
-- 소문자 저장(정규화), 3~20자, [a-z0-9_.], 점으로 시작/끝 금지, 점 연속 금지 — 인스타 규칙 그대로.
-- `citext` 확장에 의존하지 않는다: `text` + `lower(handle)` 유니크 인덱스가 확장 없이 같은 일을 한다.
-- nullable로 둔다 — 기존 사용자에겐 아직 없고, 화면이 만들라고 권한다 (없는 값을 지어내지 않는다).
--
-- 독트린: definer 본문에 `set search_path = public, pg_temp` (98 H1) · 파티 게이트 우선 ·
-- `_fail` 인자는 변수로 선계산(110 헤더법). 핀: 112_handles_feed_claims_suite.sql, 뮤테이션 증명.

-- ---------- §A profiles.handle ----------
alter table profiles add column if not exists handle text;

-- 대소문자 무시 유니크. 부분 인덱스라 handle이 null인 기존 행은 서로 충돌하지 않는다.
create unique index if not exists profiles_handle_lower_uniq
  on profiles (lower(handle)) where handle is not null;

comment on column profiles.handle is
  '0074: 인스타식 계정 아이디. 소문자 정규화 저장, 3~20자 [a-z0-9_.], 대소문자 무시 유니크.
NULL = 아직 안 만듦 (기존 사용자). 설정은 set_my_handle()만 — 클라 직접 UPDATE는 컬럼 화이트리스트가
없으므로 신뢰하지 않는다.';

-- ---------- §B 예약어 ----------
-- 브랜드·시스템 사칭 차단. 테이블이 아니라 함수 안의 배열인 이유: 운영 UI가 없어 편집 주체가 없고,
-- 목록이 바뀌는 빈도가 마이그레이션보다 낮다. 늘어나면 그때 테이블로 승격한다.
create or replace function _handle_reserved(p text)
returns boolean
language sql immutable
set search_path = public, pg_temp
as $$
  select p = any (array[
    'admin','administrator','root','system','support','help','official','staff','team',
    'dogshigh','dogs_high','도그스하이','하이클럽','highclub','runner','owner','me','you',
    'null','undefined','anonymous','everyone','all','api','www','app'
  ])
$$;

-- ---------- §C set_my_handle — 한 사람이 자기 아이디 하나를 정한다 ----------
create or replace function set_my_handle(p_handle text)
returns text
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v text;
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;

  -- 정규화 먼저 — 대문자로 낸 아이디를 거절하지 않고 소문자로 받아준다 (인스타와 같은 관용).
  v := lower(btrim(coalesce(p_handle, '')));

  if v = '' then
    raise exception 'handle_required';
  end if;
  if char_length(v) < 3 or char_length(v) > 20 then
    raise exception 'handle_length';
  end if;
  if v !~ '^[a-z0-9_.]+$' then
    raise exception 'handle_charset';
  end if;
  -- 점 규칙: 시작/끝 금지, 연속 금지. 'a..b'나 '.a'는 사람이 읽기도 어렵고 사칭에 쓰인다.
  if v like '.%' or v like '%.' or position('..' in v) > 0 then
    raise exception 'handle_dots';
  end if;
  if _handle_reserved(v) then
    raise exception 'handle_reserved';
  end if;
  -- 이미 내 것이면 조용히 성공 (멱등) — 같은 값을 다시 저장하는 걸 '중복'이라 부르지 않는다.
  if exists (select 1 from profiles where id = auth.uid() and lower(handle) = v) then
    return v;
  end if;
  if exists (select 1 from profiles where lower(handle) = v) then
    raise exception 'handle_taken';
  end if;

  update profiles set handle = v, updated_at = now() where id = auth.uid();
  return v;
end $$;

revoke execute on function set_my_handle(text) from public, anon;
grant  execute on function set_my_handle(text) to authenticated;

comment on function set_my_handle is
  '0074: 로그인한 본인의 @handle을 정한다. 소문자 정규화 · 3~20자 · [a-z0-9_.] · 점 시작/끝/연속 금지 ·
예약어 차단 · 대소문자 무시 유니크. 같은 값 재설정은 멱등 성공. 실패 문자열은 화면이 사람 말로 옮긴다
(handle_length/charset/dots/reserved/taken).';

-- ---------- §D 피드 주장 게이트 ----------
-- 러닝을 주장하는 meta 키 = **측정된 수행**을 말하는 키. km · durationSec · trace.
-- 🔴 `badges`는 일부러 빠져 있다 — 첫 초안에 넣었다가 하네스가 15건 red로 잡았다.
--    서버가 만드는 **클럽 리캡 자동 포스트**가 booking_id 없이
--    `badges:['🏁 하이클럽']`를 싣는다 (0031:123 · 0037 · 0038 · 0045 · 0048 — 다섯 곳 전부).
--    리캡은 예약이 아니라 세션의 사실이므로 그 자체로 정당하다.
--    안전한 이유: 위험한 배지(`★ 역대 최장 거리`, `★ 역대 최고 페이스`)는 shareRunToFeed가
--    **항상 km과 함께** 쓴다(api.ts:2921-2925). 그래서 km 게이트가 이미 그것들을 덮는다.
--    측정치 없이 배지만 있는 포스트는 주장이 아니라 라벨이다.
create or replace function _feed_claims_run(p_meta jsonb)
returns boolean
language sql immutable
set search_path = public, pg_temp
as $$
  select coalesce(
    (p_meta ? 'km') or (p_meta ? 'durationSec') or (p_meta ? 'trace'),
    false)
$$;

create or replace function enforce_feed_claim() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  -- 자유 포스트 — 사진·글만. 아무것도 요구하지 않는다 (Sean 2026-08-12).
  if not _feed_claims_run(new.meta) then
    return new;
  end if;

  -- 여기부터는 '러닝을 주장하는' 포스트다.
  if new.booking_id is null then
    raise exception 'claim_needs_booking';
  end if;

  -- 그 예약이 작성자의 것이어야 한다 — 보호자든 배정된 러너든 (compose는 양쪽을 허용한다).
  -- 그리고 실제로 달린 기록(runs 행)이 있어야 한다. 없는 러닝의 기록은 기록이 아니다.
  if not exists (
    select 1 from bookings b
    join runs r on r.booking_id = b.id
    where b.id = new.booking_id
      and (b.owner_id = new.author_id or b.runner_id = new.author_id)
  ) then
    raise exception 'claim_not_yours';
  end if;

  return new;
end $$;

-- definer 함수는 anon 실행 봉인 대상이다 (0057 §1 · 99 S1이 스키마 전체를 훑는다).
-- 트리거 함수라 직접 호출할 일이 없어도, 스윕은 '실행 가능한 definer'를 센다.
revoke execute on function enforce_feed_claim() from public, anon;

drop trigger if exists feed_claim_gate on feed_posts;
create trigger feed_claim_gate
  before insert or update on feed_posts
  for each row execute function enforce_feed_claim();

comment on function enforce_feed_claim is
  '0074: 업로드는 제한하지 않는다 (Sean) — 사진·글만 있는 포스트는 booking_id 없이 자유롭게 올라간다.
제한하는 것은 **주장**뿐: meta가 km/durationSec/trace 중 하나라도 실으면 그 러닝이 실재해야 하고
(runs 행), 작성자가 그 예약의 보호자 또는 배정 러너여야 한다. 자랑은 누구나, 기록은 달린 사람만.
트리거인 이유는 CHECK가 기존 행을 검증해 마이그레이션을 깨뜨리기 때문 (헤더 §A).';
