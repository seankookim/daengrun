-- ═══ 0215 — 추가 근무가 실제로 보이는 문: 보호자 화면이 후보 슬롯을 **판정과 같은 달력**에서   ═══
-- ═══        만든다 (0203 §1의 extra 팔에 독자가 생긴다)                                          ═══
--
-- DEPLOY: `supabase db push` + a client build. No edge deploy, no cron, no data migration, and
-- nothing in this file writes a row.
--
-- ═══ §0 THE DEFECT, AS MEASURED BY THE 0203–0213 EXECUTING REVIEW (F2) ════════════════════════
-- `docs/reviews/2026-09-23-executing-review-0203-0213.md` §F2. On a runner with ONE weekly rule:
--
--     ① 10:00 inside the weekly rule                      -> t   (control)
--     ② 18:00 outside the grid, no extra                  -> f   (control)
--     ③ 18:00 WITH an extra 18:00-20:00 on that date      -> t
--     ④ extra on a weekday with NO rule row at all        -> t
--     ⑤ a grid slot under a blackout                      -> f
--
-- The SERVER is right in all five. The PRODUCT is wrong in ③ and ④, because **no owner-facing
-- screen can ever offer those slots**: both slot sheets enumerate candidates from
-- `runner_availability_rules` ALONE and only then verify each candidate with `checkSlot`
-- (`is_slot_available`).
--
--   · `app/app/runner-profile/[id].tsx:174` — `p.availability.filter(r => r.weekday === wd)`
--   · `app/app/owner/reschedule.tsx:131`    — `(rules).filter(r => r.weekday === wd).forEach(...)`
--
-- So for an `extra` window `daySlots` is EMPTY and `checkSlot` is **never called** — the server's
-- `true` is never asked for. Blackouts survive this shape only by accident: they are honoured
-- because `checkSlot` refuses each grid candidate one by one, not because anything removed the
-- day. Meanwhile `app/app/runner/availability.tsx:494` tells the runner, in as many words:
--
--     「휴가는 그 기간의 예약을 막고, **추가 근무는 그날 그 시간만 엽니다**」
--
-- That sentence is a promise made on one screen about what a different screen will do, and it was
-- false. This file gives the promise a reader.
--
-- ⚠ 0203 §0's own diagnosis, one feature over: 「the product shipped a blackout mechanism with no
-- door」 became 「the slice shipped an `extra` mechanism with a writer, a server honourer and no
-- reader」. 0203 §0a argues carefully about which of the three availability predicates changes; it
-- never asks which SCREEN enumerates slots, and that is where the feature died.
--
-- ═══ §0a WHAT THIS FILE DOES **NOT** TOUCH, AND WHY ═══════════════════════════════════════════
-- `DO-NOT-REFACTOR`: 「Availability definitions are deliberately 3 distinct predicates — do not
-- unify」. Nothing here unifies them, and nothing here re-declares one.
--
--   · **0003/0203 `is_slot_available` is NOT re-declared.** It is already correct on every one of
--     the five rows above. The defect is that nobody could reach ③/④, so the repair is a READER,
--     not a change to the judge. The per-slot check stays exactly where it is and stays the FINAL
--     gate — this function proposes, `checkSlot` disposes.
--   · **0054 `runners_available_for` (the 지명 display predicate) is LEFT ALONE, deliberately.**
--     0203 §0a's argument is unchanged and it is 0054's own: ③ mirrors `transition-booking`'s
--     accept gate, and that gate refuses to read availability RULES on purpose
--     (`transition-booking/index.ts:174-176`). Teaching the 지명 screen about a 휴가 while the
--     accept gate still ignores it would make the DISPLAY stricter than the SERVER — a runner the
--     screen had hidden would still be accepted, and supply would evaporate with nobody able to
--     see why. That is precisely the failure 0054 exists to prevent. The review's own note stands:
--     a 휴가 removes the SCHEDULED offer and leaves the 지명 and 즉시 요청 offers standing, and
--     that is a decision, not a gap.
--   · **0015 `available_runners` is LEFT ALONE**, same jurisdiction argument (「right now」 is
--     governed by `runners.online`, which is strictly more current than a calendar).
--
-- This function therefore serves exactly ONE predicate — ②, the slot RULES engine — and it is the
-- LIST form of that predicate's calendar layer. It is not a fourth definition of availability; it
-- is the same one, enumerated instead of interrogated.
--
-- ═══ §0b WHAT THE FUNCTION RETURNS, STATED AS A PROPOSITION ═══════════════════════════════════
-- For each KST date `d` in `[p_from, p_to]`, one row per OPEN WINDOW on that day:
--
--     offered(d) = ( weekly grid rows for dow(d)  ∪  `extra` rows with starts_on = d )
--                  if NO `blackout` covers d, else ∅
--
-- which is `is_slot_available` §1 ∪ §1b − §2 — the **CALENDAR** layer, and only that.
--
-- 🔴 §3 (confirmed bookings + rest buffer), §4 (slot holds) and §5 (daily cap) are DELIBERATELY
-- NOT applied here, and that division is the whole design rather than an omission:
--
--   · §1/§2 answer 「does this runner OFFER this time at all」 — a calendar fact, stable for the
--     whole range, and the only thing a list of candidate windows can honestly assert.
--   · §3/§4/§5 answer 「is this particular slot still free RIGHT NOW」 — a race, and a list
--     computed once and rendered for minutes cannot be right about it. `checkSlot` per candidate
--     is, and it already runs on both screens.
--
-- So the two disagree by construction on a runner with a confirmed booking — the window is still
-- OFFERED and the slot inside it is refused — and `246 0215-P3` pins that disagreement rather
-- than pretending it away. A pin asserting set EQUALITY without that carve-out would be measuring
-- a fixture with no bookings in it.
--
-- ═══ §0c THE ONE MEASURED DIVERGENCE INSIDE THE CALENDAR LAYER — NAMED, NOT SMOOTHED ══════════
-- On a clean fixture (no bookings, no holds, cap not reached) the offered list and
-- `is_slot_available` agree in BOTH directions over the range — with exactly one family of
-- exceptions, and it runs in the SAFE direction:
--
-- 🔴 **`is_slot_available` §1 admits a slot that CROSSES OR TOUCHES KST MIDNIGHT even when the
-- weekly rule ends long before it.** §1's containment is two independent comparisons,
-- `r.start_min <= v_start_min and r.end_min >= v_end_min`, and `v_end_min` is a minute-OF-DAY. A
-- 23:00–00:30 slot against a 09:00–21:00 rule gives `540 <= 1380` (true) and `1260 >= 30` (true),
-- so §1 passes. Measured; `246 0215-P3` counts the family and asserts every disagreement
-- between the list and the judge lies inside it.
--
-- ⚠ 0203's own header says the opposite — 「A slot that crosses KST midnight fails §1 on BOTH
-- arms, because `v_end_min` wraps below `v_start_min` and no containment can hold」. That sentence
-- describes a RANGE containment; the code is two scalar comparisons, and they do not interact.
-- The prose is wrong about the code it sits above. **Recorded here rather than fixed**: repairing
-- `is_slot_available` changes what `create-booking-hold`, `transition-booking`'s reschedule-accept
-- and the recurring cron will accept, which is a different slice with a different blast radius and
-- a product question attached (may a runner be booked across midnight at all?). It is reported
-- upward with this slice.
--
-- **This function never emits such a window** — it cannot, because a window is bounded by
-- `end_min <= 1440` and a candidate must fit inside one. So the offered set stays a SUBSET of the
-- judge's true set, the client never offers a slot the server would refuse, and the divergence
-- costs a runner an overnight offer nobody was showing them anyway.
--
-- ═══ §0d VISIBILITY — MATCHED TO WHAT THE EXISTING SLOT BUILDERS ALREADY READ, NO WIDER ═══════
-- MEASURED, not assumed:
--   · `runner_availability_rules` — RLS policy 「avail rules public read」 `for select using (true)`
--     (0002:77), `grant select … to authenticated`, `revoke … from anon` (0093:70-75). So **any
--     signed-in user already reads ANY runner's whole weekly grid**, and both slot sheets do
--     exactly that today through `fetchRunnerAvailability` (`api.ts:2569`).
--   · `runner_availability_exceptions` — self-scoped SELECT policy only (0203 §B). An owner
--     CANNOT read these rows directly, which is why this must be a definer.
--
-- So this function is granted to `authenticated` and revoked from `public, anon` — the grid half
-- is no wider than today, and the exception half is new disclosure, deliberately:
--
-- 🔴 **AN OWNER MUST SEE A 추가 근무 IN ORDER TO BOOK IT, AND MUST NOT BE OFFERED A 휴가 DAY.**
-- That is the feature. What leaks is the SHAPE of the calendar (which windows are open), which is
-- exactly what the product intends to advertise, and it is already obtainable one slot at a time
-- from `is_slot_available` — itself granted to `authenticated` (0203 §D). `246 0215-A2` pins that
-- a stranger gets the SAME rows the booking owner does, as a decision recorded rather than a hole
-- discovered.
--
-- 🔴 **WHAT DOES NOT LEAK IS THE `note`.** It is free text the runner typed for themselves
-- (「가족 여행」), it is capped at 40 characters and it is displayed on the runner's own screen.
-- It is not in the OUT list, it is not read by the body, and `246 0215-A2` asserts both — the
-- column list by name and the comment-stripped body by absence.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A  THE READER
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ Flat, whitelisted, four columns. No id, no runner_id, no note, no timestamps — a caller that
-- needs an instant builds it from `day` + `start_min` in KST, which is the one arithmetic
-- `app/src/lib/kst.ts` owns.
create or replace function runner_offered_slots(
  p_runner uuid,
  p_from   date,
  p_to     date
) returns table (
  day       date,
  start_min int,
  end_min   int,
  source    text
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  -- party gate FIRST. There is no owner/runner split to make: the grid is already readable by
  -- every signed-in account (§0d), so the only thing to refuse is an account-less caller.
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_runner is null then raise exception 'bad_runner'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_range'; end if;
  -- inclusive span = p_to - p_from + 1, so 89 is 「at most 90 days」 — the same arithmetic and the
  -- same number as 0203's `rae_range_capped`, so a runner cannot write a range this cannot read.
  if p_to - p_from > 89 then raise exception 'range_too_long'; end if;

  return query
  -- ⚠ the day enumeration is INTEGER arithmetic on dates, never `generate_series(date, date,
  -- interval)`. The latter returns TIMESTAMPS, and a timestamp in a function about KST calendar
  -- days is a timezone waiting to be read by whoever edits this next. `p_from + i` is a date.
  with days as (
    select (p_from + g.i)::date as day
      from generate_series(0, p_to - p_from) as g(i)
  ),
  -- §2 [0215] 휴가(blackout)는 그날을 통째로 닫는다 — extra 행도 함께 사라진다.
  -- 0203 §D의 「BLACKOUT BEATS EXTRA」와 같은 구조다: 그쪽은 두 개의 독립된 return false 게이트로,
  -- 여기서는 날짜 자체를 빼는 것으로 같은 결과를 낸다. 두 팔 모두 kind로 갈라 읽는다 — 가르지
  -- 않으면 extra가 자기 자신을 막는다(0203의 테이블 주석).
  open_days as (
    select d.day from days d
     where not exists (
       select 1 from runner_availability_exceptions e
       where e.runner_id = p_runner
         and e.kind = 'blackout'
         and daterange(e.starts_on, e.ends_on, '[]') @> d.day
     )
  )
  -- §1 [0215] 주간 그리드 — KST 요일. `extract(dow from <date>)`는 달력 연산이라 시간대가 없고,
  -- 판정이 쓰는 `extract(dow from p_start at time zone 'Asia/Seoul')`와 같은 요일을 준다: 호출자가
  -- instant를 KST 날짜로 바꿔 넘기면 두 함수는 같은 날을 말한다 (246 0215-K1이 경계에서 잰다).
  select od.day, r.start_min, r.end_min, 'grid'::text
    from open_days od
    join runner_availability_rules r
      on r.runner_id = p_runner
     and r.weekday   = extract(dow from od.day)::int
  union all
  -- §1b [0215] 추가 근무(extra) — 그날 하루의 한 구간. 그리드를 대체하지 않고 더한다.
  select od.day, x.start_min, x.end_min, 'extra'::text
    from open_days od
    join runner_availability_exceptions x
      on x.runner_id = p_runner
     and x.kind      = 'extra'
     and x.starts_on = od.day
   order by 1, 2, 3, 4;
end $$;

-- 🔴 THE ACL IS SET BY THIS FILE, WHICH IS THE FILE THAT FIRST DEFINES THE FUNCTION. On an apply
-- where it is absent the statement above is a plain CREATE and a SECURITY DEFINER is born
-- PUBLIC-executable (0116:636) — `scripts/check-definer-acl.mjs` exists for exactly this.
-- `service_role` is NOT named: no edge function and no cron calls this, and it holds EXECUTE
-- through Supabase's function default privileges anyway (`00_shim.sql:135`, `0057:59`). Naming a
-- role that nothing uses would widen the written contract past the measurement.
revoke execute on function runner_offered_slots(uuid, date, date) from public, anon;
grant  execute on function runner_offered_slots(uuid, date, date) to authenticated;

comment on function runner_offered_slots(uuid, date, date) is
'0215: 보호자 화면이 후보 슬롯을 만드는 달력. 주간 그리드 ∪ 추가 근무(extra) − 휴가(blackout) 날,
KST 날짜 범위 최대 90일. 판정(is_slot_available)의 §1∪§1b−§2와 같은 층이고 §3~§5(확정 예약·홀드·
일일 상한)는 일부러 안 본다 — 그건 슬롯별 checkSlot이 마지막 문으로 계속 본다. note는 반환하지
않는다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B  VERIFY — the apply refuses rather than landing a half of this
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_bad  text := '';
  v_oid  oid;
  v_raw  text;
  v_src  text;
  v_cols text;
begin
  v_oid := to_regprocedure('runner_offered_slots(uuid, date, date)')::oid;
  if v_oid is null then
    raise exception '0215 VERIFY failed: NO-FUNCTION(runner_offered_slots(uuid, date, date))';
  end if;

  if (select prosecdef from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' definer가 아니다'; end if;
  if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' 본문 search_path가 없다'; end if;
  if (select provolatile from pg_proc where oid = v_oid) is distinct from 's'
    then v_bad := v_bad || ' stable이 아니다'; end if;
  if (select proacl from pg_proc where oid = v_oid) is null
    then v_bad := v_bad || ' ACL이 NULL이다 (기본 PUBLIC)'; end if;
  if has_function_privilege('anon', v_oid, 'execute') is not false
    then v_bad := v_bad || ' anon이 실행할 수 있다'; end if;
  if has_function_privilege('authenticated', v_oid, 'execute') is not true
    then v_bad := v_bad || ' authenticated가 실행할 수 없다'; end if;

  -- the OUT list is the privacy contract. A fifth column is how `note` would arrive.
  -- read by argument MODE ('t' = a table column), never by a naming convention: a convention is a
  -- habit and a mode is what the catalog actually says.
  select string_agg(t.n, ',' order by t.ord) into v_cols
    from pg_proc p,
         lateral unnest(p.proargnames, p.proargmodes) with ordinality as t(n, m, ord)
   where p.oid = v_oid and t.m = 't'::"char";
  if v_cols is distinct from 'day,start_min,end_min,source'
    then v_bad := v_bad || ' 🔴 반환 칸이 day,start_min,end_min,source가 아니다 [' || coalesce(v_cols, 'NULL') || ']'; end if;

  -- the body, read with comments stripped. `prosrc` is source plus our own prose and this file
  -- documents every arm at length — an un-stripped match is satisfied by the writing that
  -- EXPLAINS the fix rather than by the fix.
  select prosrc into v_raw from pg_proc where oid = v_oid;
  if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(runner_offered_slots)';
  else
    v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
    if (v_src ~ 'kind\s*=\s*''blackout''') is not true
      then v_bad := v_bad || ' 휴가 팔이 kind로 갈라지지 않는다'; end if;
    if (v_src ~ 'kind\s*=\s*''extra''') is not true
      then v_bad := v_bad || ' 추가 근무 팔이 kind로 갈라지지 않는다'; end if;
    -- EXACTLY two reads, EXACTLY two kind filters — the same shape 0203 §E demands of the judge.
    -- A third read, or a read without a kind filter, is the defect that table's comment warns of.
    if (select count(*) from regexp_matches(v_src, 'runner_availability_exceptions', 'g')) is distinct from 2
      then v_bad := v_bad || ' 🔴 예외 테이블을 정확히 두 번 읽지 않는다'; end if;
    if (select count(*) from regexp_matches(v_src, 'kind\s*=\s*''', 'g')) is distinct from 2
      then v_bad := v_bad || ' 🔴 kind로 안 가르는 예외 읽기가 있다'; end if;
    if (v_src ~ 'runner_availability_rules') is not true
      then v_bad := v_bad || ' 🔴 주간 그리드 팔이 없다 (extra가 그리드를 대체했다)'; end if;
    -- the blackout comparison must stay on the AUTHORITATIVE date columns (0203 §A④ demoted
    -- starts_at/ends_at to derived). Shared shape with the judge, which uses daterange too.
    if (v_src ~ '\mdaterange\M') is not true
      then v_bad := v_bad || ' 휴가 비교가 날짜 범위가 아니다 (비권위 instant 칸으로 되돌아갔다)'; end if;
    if (v_src ~ '\mstarts_at\M') is not false or (v_src ~ '\mends_at\M') is not false
      then v_bad := v_bad || ' 🔴 비권위 instant 칸(starts_at/ends_at)을 읽는다'; end if;
    -- `note`는 반환도 읽기도 하지 않는다. 낱말 경계로 잡는다 — `note`는 다른 이름의 부분문자열이
    -- 될 수 있고, 그 grep은 묻지 않은 질문에 답한다 (CLAUDE.md의 컬럼명-부분문자열 법).
    if (v_src ~ '\mnote\M') is not false
      then v_bad := v_bad || ' 🔴 본문이 note를 읽는다'; end if;
    -- 시간대: 이 함수는 순수 날짜 산술이어야 한다. `at time zone`이 생겼다면 누군가 instant를
    -- 끌어들인 것이고, 그 순간 KST 경계가 다시 열린다.
    if (v_src ~ 'at time zone') is not false
      then v_bad := v_bad || ' 🔴 순수 날짜 산술이 아니다 (at time zone이 들어왔다)'; end if;
    if (v_src ~ '\mnow\s*\(') is not false
      then v_bad := v_bad || ' 🔴 본문이 now()를 읽는다 (범위는 호출자가 정한다)'; end if;
    -- the stripper's own CONTROL, both ways: `[0215]` occurs ONLY in this body's comments, so a
    -- stripper that silently did nothing would leave it behind and every arm above would be
    -- measuring prose.
    if (v_raw ~ '\[0215\]') is not true
      then v_bad := v_bad || ' 대조: 원본 본문에 [0215] 주석이 없다 (주석 제거 팔이 무의미)'; end if;
    if (v_src ~ '\[0215\]') is not false
      then v_bad := v_bad || ' 대조: 주석 제거가 동작하지 않았다'; end if;
  end if;

  -- the judge is UNTOUCHED by this file, and that is a property worth aborting on: if a future
  -- edit re-declares it here, 0203 §E's own VERIFY has already gone by and will not re-run.
  if to_regprocedure('is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid is null
    then v_bad := v_bad || ' 🔴 대조: is_slot_available이 없다'; end if;
  if (select prosecdef from pg_proc where oid = to_regprocedure(
        'is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid) is not true
    then v_bad := v_bad || ' 🔴 대조: is_slot_available이 definer가 아니다'; end if;

  if v_bad <> '' then raise exception '0215 VERIFY failed:%', v_bad; end if;
end $$;
