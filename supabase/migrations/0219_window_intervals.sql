-- ═══ 0219 — `is_slot_available` §1: 「제공된 시간 안」이 글자 그대로의 뜻이 된다              ═══
-- ═══        (codex 2026-09-25 server review, finding #5 — READ-based, REPRODUCED here first)  ═══
--
-- ═══ §0 THE DEFECT, AND IT WAS REPRODUCED BEFORE A LINE OF THIS FILE WAS WRITTEN ══════════════
-- 0203 §D's §1 asked containment with two INDEPENDENT scalar comparisons on minutes-of-day:
--
--     r.start_min <= v_start_min  and  r.end_min >= v_end_min      -- 주간 규칙
--     x.start_min <= v_start_min  and  x.end_min >= v_end_min      -- 추가 근무 (extra)
--
-- `v_end_min` is a minute OF DAY, so it carries no date. For a 23:30–00:19 KST request
-- `v_start_min = 1410` and `v_end_min = 19`, and a lone 09:00–10:00 추가 근무 gives
-- `540 <= 1410` (true) and `600 >= 19` (true) — **§1 admits a slot fourteen hours outside the only
-- window the runner ever opened.** The same shape is in the weekly-rule arm, so any window that
-- starts before the slot's start and ends after the slot's minute-of-day end admits it, which for
-- a cross-midnight slot is very nearly every window there is.
--
-- A second defect rides the same expression and is not about midnight at all: `extract(minute
-- from …)` **discards seconds**, so a slot ending 10:00:30 and a slot ending 10:00:00 were the
-- same value to §1, and a window ending at 10:00 admitted the first.
--
-- 🔴 **MEASURED, NOT INFERRED.** Suite `250_window_intervals_suite.sql` was written FIRST and run
-- against trunk's body with this migration absent: harness **1486 → 1490 pass / 7 fail, exit 1**,
-- total 1497 = the 1486 baseline plus exactly the 11 pins that file adds — so the suite is known
-- to have RUN, not to have been skipped. Seven pins RED: `0219-W1 · W2 · W5 · W7 · W8 · W9 · S1`.
-- `0219-W1` is the finding verbatim — a runner with ZERO weekly rules and one 09:00–10:00 추가 근무
-- returned **true** for 23:30–00:19 — and its two controls stood at the same time (the in-window
-- slot true, a 19-minute overhang false), so the number was not produced by an empty fixture.
-- `0219-W8` measured the divergence 246 carves out as **8 candidate cells**. ⚠ `0219-W9` is red
-- before the fix for the OPPOSITE reason — it pins a family this file CREATES (§0b) — and it is
-- listed rather than filtered out, because that is what tells you the pin is tied to the new
-- behaviour instead of to the defect.
--
-- ⚠ **0203's own header asserts the OPPOSITE** (「A slot that crosses KST midnight fails §1 on
-- BOTH arms, because `v_end_min` wraps below `v_start_min` and no containment can hold」). That
-- sentence describes a RANGE containment; the code was two scalars that never interact. 0215 §0c
-- caught the prose/code split and recorded it rather than repairing it, because repairing it
-- changes what `create-booking-hold`, `transition-booking`'s reschedule-accept and the recurring
-- cron will accept. This file is that repair, with the blast radius measured below.
--
-- ═══ §0a WHAT §1 MEANS NOW ═══════════════════════════════════════════════════════════════════
-- For each KST date `d` the slot TOUCHES, every weekly rule on `dow(d)` and every 추가 근무 row
-- with `starts_on = d` becomes a CONCRETE instant interval `[d + start_min, d + end_min)`. Those
-- intervals are merged where they touch or overlap, and the slot is admitted only when ONE merged
-- interval covers `[p_start, p_end)` entirely. `end_min = 1440` is the following midnight, which
-- is what lets two adjacent windows span midnight — and the upper bound stays EXCLUSIVE, so a
-- slot ending exactly at 24:00 is inside a window ending at 1440 and does not reach the next day.
--
-- **There is no minute-of-day arithmetic left in the body.** `v_wd`, `v_start_min` and `v_end_min`
-- are gone rather than corrected; `250 0219-S1` reads the deployed body back and fails if any of
-- them returns.
--
-- ═══ §0b WHAT THIS DELIBERATELY DOES **NOT** DECIDE ══════════════════════════════════════════
-- 🔴 **Whether a runner may be booked across midnight AT ALL is a product ruling and it is not
-- taken here.** This file makes 「제공된 시간 안」 mean what it says: an overnight slot is admitted
-- **only** when the runner genuinely opened both sides of midnight (a window ending at 24:00 on
-- day D and one starting at 00:00 on D+1, from either source), and refused when there is a gap of
-- even one minute. Forbidding a genuinely-offered overnight slot is a different sentence with
-- different consequences for supply, and it belongs to Sean's letter (d). `250 0219-W3`/`W4` are
-- the pins that would flip if he rules that way.
--
-- ⚠ **THE FIX WIDENS §1 IN ONE DIRECTION NOBODY ASKED FOR, AND IT IS SAID OUT LOUD RATHER THAN
-- LEFT TO BE DISCOVERED.** Merging is what lets the two sides of midnight join — and merging does
-- not know about midnight, so it also joins two ADJACENT windows on the SAME day. A runner with a
-- 09:00–12:00 grid rule and a 12:00–14:00 추가 근무 now has 11:30–12:35 admitted, where 0203
-- required ONE row to contain the slot. That is the same sentence applied consistently (the union
-- of what the runner offered covers it), and it moves in the runner's favour, but it is a
-- behaviour change beyond the reported finding. `250 0219-W9` MEASURES it rather than asserting it
-- is absent.
--
-- ═══ §0c `runner_offered_slots` (0215) IS **NOT** RE-DECLARED — MEASURED, NOT ASSUMED ═════════
-- 0215's list already builds concrete per-day windows and never wraps, so nothing in it is wrong.
-- The question is whether its candidate SET must change to stay ≡ with the fixed judge. Measured,
-- in `250 0219-W8` and `0219-W9`:
--
--   · On 246's own mixed fixture the two are now **equal in both directions with no carve-out** —
--     14 days × 48 candidates, ⊆ violations 0 and ⊇ violations 0, midnight candidates included.
--     That is the whole point of the fix: 246's exemption existed because the judge was wrong.
--   · Two ⊇-divergence families survive, both created by the merge and both **structurally
--     unrepresentable in the list**: ① a cross-midnight slot covered by adjacent windows — the
--     list's rows are per-day with `end_min <= 1440`, so it cannot emit one; ② a same-day slot
--     spanning two adjacent windows — the list deliberately does not merge, because a merged row
--     cannot say whether its `source` is `grid` or `extra` and the 추가 근무 chip would lie
--     (0215's CLIENT section).
--
-- 🔴 **⊆ stays 0, which is the direction that protects a person**: the screen never offers a slot
-- the server will refuse. The surviving divergence costs a runner an offer for a time they did
-- open — visible only from the calendar screen, still bookable by nobody — and closing it means
-- either merging the list (and losing `source`) or forbidding the overnight case outright. Both
-- are Sean's letter (d). Re-declaring 0215 to chase equality would ALSO break `246 0215-P1`'s
-- `source='extra'` row and `0215-P3`'s grid-3/extra-2 shape, so it is not a free change.
--
-- ═══ §0d WHAT ELSE THIS FILE DOES NOT DO ═════════════════════════════════════════════════════
-- - **It edits no landed migration.** 0003, 0203 and 0215 are untouched on disk; `is_slot_available`
--   is re-declared FORWARD from here and **restates its own ACL** — a `create or replace` on an
--   apply where the function is absent is a plain CREATE and a SECURITY DEFINER born
--   PUBLIC-executable is the worst shape this repo makes (0116:636, `check-definer-acl.mjs`).
-- - **§2 · §3 · §4 · §5 are carried byte-for-byte**, comments included. §2 never wrapped: it has
--   compared whole KST DATES since 0203 §A③ and already uses the exclusive-bound `v_end_date`, so
--   it needs nothing from this file. §5's daily cap counts against the slot's START date, exactly
--   as 0003 wrote it — a cross-midnight slot is one session on the day it begins, and changing
--   that is a product question this file has no answer for.
-- - **No client change.** The signature is identical (`uuid, timestamptz, timestamptz → boolean`),
--   so `api.ts:2778 checkSlot` and `transition-booking/index.ts:568` are untouched.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A  THE PREDICATE
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
create or replace function is_slot_available(
  p_runner uuid,
  p_start timestamptz,
  p_end timestamptz
) returns boolean
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_start_date date;
  v_end_date date;
  v_covered boolean;
  v_rest int;
  v_max_daily int;
  v_daily_count int;
begin
  -- KST 기준 날짜. 상한은 배타 — 자정 정각에 끝나는 슬롯이 다음 날까지 차지한 것으로 세지 않는다
  v_start_date := (p_start at time zone 'Asia/Seoul')::date;
  v_end_date := greatest(v_start_date,
                         ((p_end - interval '1 microsecond') at time zone 'Asia/Seoul')::date);

  -- ⚠ 열거 상한 [0219]. 아래의 §1은 슬롯이 **건드리는 날**을 펴므로, 인자가 임의로 긴 구간이면
  -- 열거도 임의로 길어진다. 90일은 0203의 `rae_range_capped`·0215의 범위 상한과 같은 수이고,
  -- 90일짜리 「슬롯」은 산책이 아니다. NULL 인자에서 조용히 통과하지 않도록 boolean을 명시한다.
  if (v_end_date - v_start_date > 89) is true then return false; end if;

  -- 1. 주간 규칙과 그 날짜의 추가 근무(extra)를 **구체적인 KST 구간**으로 펴서, 겹치거나 맞닿는
  --    것을 합친 뒤, 그 합집합 하나가 슬롯을 통째로 덮을 때만 받는다 [0219]
  --    · `end_min = 1440` 은 그 다음 날 자정이다 — 그래서 24:00에 끝나는 창과 00:00에 시작하는
  --      창이 맞닿아 합쳐지고, 1분이라도 벌어지면 합쳐지지 않는다.
  --    · 상한 비교가 `u.e >= p_end` 인 것이 배타 상한이다: 창이 1440에서 끝나면 24:00 정각에
  --      끝나는 슬롯은 안에 있고, 1 마이크로초 더 긴 슬롯은 밖에 있다.
  --    · 분-of-day 산술은 이 본문 어디에도 없다 (0203의 결함이 거기 있었다).
  select exists (
    with touched as (
      select (v_start_date + g.i)::date as d
        from generate_series(0, v_end_date - v_start_date) as g(i)
    ),
    win as (
      select (t.d::timestamp + make_interval(mins => r.start_min)) at time zone 'Asia/Seoul' as s,
             (t.d::timestamp + make_interval(mins => r.end_min))   at time zone 'Asia/Seoul' as e
        from touched t
        join runner_availability_rules r
          on r.runner_id = p_runner
         and r.weekday   = extract(dow from t.d)::int
      union all
      select (t.d::timestamp + make_interval(mins => x.start_min)) at time zone 'Asia/Seoul',
             (t.d::timestamp + make_interval(mins => x.end_min))   at time zone 'Asia/Seoul'
        from touched t
        join runner_availability_exceptions x
          on x.runner_id = p_runner
         and x.kind      = 'extra'
         and x.starts_on = t.d
    ),
    ranked as (
      select w.s, w.e,
             max(w.e) over (order by w.s, w.e rows between unbounded preceding and 1 preceding) as prev_e
        from win w
    ),
    grouped as (
      select k.s, k.e,
             count(*) filter (where k.prev_e is null or k.prev_e < k.s)
               over (order by k.s, k.e rows between unbounded preceding and current row) as grp
        from ranked k
    ),
    merged as (
      select min(m.s) as s, max(m.e) as e from grouped m group by m.grp
    )
    select 1 from merged u where u.s <= p_start and u.e >= p_end
  ) into v_covered;
  if v_covered is not true then return false; end if;

  -- 2. 휴가(blackout)와 무겹침 — KST 일 단위, extra 행은 읽지 않는다 [0203]
  if exists (
    select 1 from runner_availability_exceptions e
    where e.runner_id = p_runner and e.kind = 'blackout'
      and daterange(e.starts_on, e.ends_on, '[]') && daterange(v_start_date, v_end_date, '[]')
  ) then return false; end if;

  -- 러너 규칙 로드
  select coalesce(b.rest_after_min, 30), coalesce(b.max_sessions_per_day, 4)
    into v_rest, v_max_daily
  from runner_booking_rules b where b.runner_id = p_runner;
  v_rest := coalesce(v_rest, 30);
  v_max_daily := coalesce(v_max_daily, 4);

  -- 3. 확정 예약(+휴식 버퍼)과 무겹침
  if exists (
    select 1 from bookings bk
    where bk.runner_id = p_runner
      and bk.status in ('confirmed','runner_enroute','picked_up','active','runner_pending')
      and tstzrange(
            bk.scheduled_at - (v_rest || ' minutes')::interval,
            bk.scheduled_at + ((bk.km * 8 + 25 + v_rest) || ' minutes')::interval
          ) && tstzrange(p_start, p_end)
  ) then return false; end if;

  -- 4. 유효한 슬롯 홀드와 무겹침
  if exists (
    select 1 from slot_holds h
    where h.runner_id = p_runner
      and h.expires_at > now()
      and tstzrange(h.starts_at, h.ends_at) && tstzrange(p_start, p_end)
  ) then return false; end if;

  -- 5. 하루 최대 세션
  select count(*) into v_daily_count from bookings bk
  where bk.runner_id = p_runner
    and bk.status in ('confirmed','runner_enroute','picked_up','active','completed')
    and (bk.scheduled_at at time zone 'Asia/Seoul')::date
        = (p_start at time zone 'Asia/Seoul')::date;
  if v_daily_count >= v_max_daily then return false; end if;

  return true;
end $$;

-- 🔴 THE ACL IS RESTATED BY THIS FILE BECAUSE THIS FILE RE-DECLARES THE FUNCTION. 0203 §D's own
-- comment carries the correction worth repeating: the function is NOT public-executable today
-- (0057 §1 swept every `public` SECURITY DEFINER once), and that sweep is exactly why these two
-- lines matter — 0057 has already gone by and will not run again. If this `create or replace`
-- lands where the function is ABSENT (a partial prior apply, a branch that never ran 0003, a
-- rebuilt environment) it is a plain CREATE and the new function is born PUBLIC-executable.
-- Both real callers are named rather than inferred: `app/src/lib/api.ts:2778` (`checkSlot`, as
-- `authenticated`) and `supabase/functions/transition-booking/index.ts:568` (as `service_role`).
-- `250 0219-S1` pins the `service_role` arm every run, because that is the one way this slice
-- could silently kill the edge's reschedule-accept while looking green.
revoke execute on function is_slot_available(uuid, timestamptz, timestamptz) from public, anon;
grant  execute on function is_slot_available(uuid, timestamptz, timestamptz) to authenticated, service_role;

comment on function is_slot_available(uuid, timestamptz, timestamptz) is
'0003→0203→0219: 슬롯 판정. §1 주간 규칙 ∪ 그날의 추가 근무를 **구체적인 KST 구간**으로 펴서 합친
합집합이 슬롯을 통째로 덮어야 한다 (분-of-day 비교 없음, 상한 배타) · §2 휴가(KST 일 단위) · §3 확정
예약 + 휴식 버퍼 · §4 홀드 · §5 일일 상한. 자정을 넘는 슬롯은 러너가 양쪽을 다 연 경우에만 열린다 —
「자정을 아예 금지할 것인가」는 제품 결정이고 여기서 내리지 않는다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B  VERIFY — the apply refuses rather than landing a half of this
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_bad text := '';
  v_oid oid;
  v_raw text;
  v_src text;
begin
  v_oid := to_regprocedure('is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid;
  if v_oid is null then raise exception '0219 VERIFY failed: NO-FUNCTION(is_slot_available)'; end if;

  if (select prosecdef from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' definer가 아니다'; end if;
  if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' 본문 search_path가 없다'; end if;
  if (select proacl from pg_proc where oid = v_oid) is null
    then v_bad := v_bad || ' ACL이 NULL이다 (기본 PUBLIC)'; end if;
  if has_function_privilege('anon', v_oid, 'execute') is not false
    then v_bad := v_bad || ' anon이 실행할 수 있다'; end if;
  if has_function_privilege('authenticated', v_oid, 'execute') is not true
    then v_bad := v_bad || ' authenticated가 실행할 수 없다'; end if;
  if has_function_privilege('service_role', v_oid, 'execute') is not true
    then v_bad := v_bad || ' service_role이 실행할 수 없다 (엣지의 일정 변경 수락이 죽는다)'; end if;

  -- 본문은 주석을 벗기고 읽는다. `prosrc`는 소스 + 우리 산문이고 이 파일은 고침을 길게 설명한다 —
  -- 안 벗기면 **설명이 구현을 대신해 통과한다** (0148의 W6가 정확히 그렇게 붉어졌다).
  select prosrc into v_raw from pg_proc where oid = v_oid;
  if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(is_slot_available)';
  else
    v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
    -- 주석 제거기의 대조를 먼저 세운다: `[0219]`는 이 본문의 주석에만 있다.
    if (v_raw ~ '\[0219\]') is not true
      then v_bad := v_bad || ' 대조: 원본 본문에 [0219] 주석이 없다 (주석 제거 팔이 무의미)'; end if;
    if (v_src ~ '\[0219\]') is not false
      then v_bad := v_bad || ' 대조: 주석 제거가 동작하지 않았다'; end if;
    -- 결함 자체: 분-of-day 산술이 한 조각도 남아 있으면 안 된다
    if (v_src ~ '\mv_end_min\M') is not false
      then v_bad := v_bad || ' 🔴 본문에 v_end_min이 살아 있다 (분-of-day 비교가 돌아왔다)'; end if;
    if (v_src ~ '\mv_start_min\M') is not false
      then v_bad := v_bad || ' 🔴 본문에 v_start_min이 살아 있다'; end if;
    if (v_src ~ 'extract\s*\(\s*hour\s+from') is not false
      then v_bad := v_bad || ' 🔴 본문이 시각을 시/분으로 쪼갠다'; end if;
    -- 고침이 실제로 거기 있다 (부재 팔만 있으면 빈 함수도 통과한다)
    if (v_src ~ '\mmerged\M') is not true
      then v_bad := v_bad || ' 🔴 창 합치기(merged)가 없다'; end if;
    if (v_src ~ 'make_interval') is not true
      then v_bad := v_bad || ' 🔴 창을 instant 구간으로 만들지 않는다'; end if;
    -- 0203이 세운 모양은 그대로여야 한다 — 예외 테이블을 정확히 두 번 읽고, 두 번 다 kind로 가른다
    if (v_src ~ 'kind\s*=\s*''extra''') is not true
      then v_bad := v_bad || ' §1에 extra 팔이 없다'; end if;
    if (v_src ~ 'kind\s*=\s*''blackout''') is not true
      then v_bad := v_bad || ' §2가 blackout으로 가르지 않는다'; end if;
    if (select count(*) from regexp_matches(v_src, 'runner_availability_exceptions', 'g')) is distinct from 2
      then v_bad := v_bad || ' 🔴 판정이 예외 테이블을 정확히 두 번 읽지 않는다'; end if;
    if (select count(*) from regexp_matches(v_src, 'kind\s*=\s*''', 'g')) is distinct from 2
      then v_bad := v_bad || ' 🔴 예외 읽기 중 kind로 가르지 않는 것이 있다'; end if;
    if (v_src ~ '\mdaterange\M') is not true
      then v_bad := v_bad || ' 휴가 비교가 날짜 범위가 아니다'; end if;
    if (v_src ~ 'runner_availability_rules') is not true
      then v_bad := v_bad || ' 🔴 주간 그리드 팔이 사라졌다'; end if;
    -- 0203의 주석 제거기 대조는 234 0203-S1이 매 런마다 본다 — 그 팔이 요구하는 `[0203]`이
    -- 이 본문에도 남아 있는지 여기서 먼저 확인한다 (§2 주석이 그것을 들고 있다).
    if (v_raw ~ '\[0203\]') is not true
      then v_bad := v_bad || ' 🔴 본문에서 [0203] 주석이 사라졌다 (234 0203-S1의 주석 제거기 대조가 죽는다)'; end if;
  end if;

  if v_bad <> '' then raise exception '0219 VERIFY failed:%', v_bad; end if;
end $$;
