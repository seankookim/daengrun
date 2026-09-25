-- ═══ 0221 — 후보 목록이 **판정과 같은 합집합**을 쓴다: 러너가 이어서 연 시간을 보호자가 고를 수 ═══
-- ═══        있다 (codex 2026-09-25 서버 평결 #1, READ 기반 — 여기서 먼저 재현했다)               ═══
--
-- DEPLOY: `supabase db push` + a client build. No edge deploy, no cron, no data migration, and
-- nothing in this file writes a row. ⚠ The RETURN SHAPE changes (a fifth column), so this is a
-- `drop function` + bare `create function`, not a `create or replace` — Postgres refuses a
-- returns-table change on `or replace`. The ACL is therefore not merely restated for safety, it is
-- MANDATORY: the drop takes the grants with it.
--
-- ═══ §0 THE DEFECT — REPRODUCED BEFORE A LINE OF THIS FILE WAS WRITTEN ════════════════════════
-- `docs/reviews/2026-09-25-0216-0220-codex-verdict.md` finding #1 (medium, READ):
--
--   0219 §1 made the judge accept a slot covered by the UNION of a runner's adjacent windows.
--   `runner_offered_slots` (0215 §A) still returned those windows SEPARATELY, and
--   `app/src/lib/offered-slots.ts:115` required the whole duration inside ONE window — so an
--   owner could never be OFFERED a slot the server would have accepted.
--
-- 🔴 **MEASURED, NOT INFERRED.** `252_offered_slots_merge_suite.sql` was written FIRST and run
-- against trunk with this migration held aside: harness **1527 pass / 9 fail, exit 1**, total
-- 1536 = the 1527 baseline plus exactly the 9 pins that file adds — so the suite is known to have
-- RUN rather than to have been skipped (§three-ways-a-green-means-nothing ①). All nine RED, and
-- `0221-E1` is the finding verbatim: with a 09:00–12:00 weekly rule and a 12:00–14:00 추가 근무 on
-- the same day the judge returned **true** for 11:00–12:05 while the list held **0** windows
-- containing it and returned the day as TWO unmerged rows. `0221-E2` measured the same thing
-- across midnight.
-- ⚠ **All nine red is not the reassuring number it looks like**, so the reds were read one at a
-- time rather than counted. `0221-E3` — the pin that must NOT move, because a merge that swallowed
-- a one-minute hole would paint 가능 on a booking the server rejects — was red on its **CONTROL**
-- arm only: its 「gap not swallowed」 arms were green on trunk (nothing merges there), and what
-- failed was 「close the hole and the two DO merge」, which is the arm that proves the fixture sits
-- where the two rules diverge instead of in their agreement zone. `0221-E4` and `0221-V1` were red
-- because `segments` did not exist yet. Counting nine and calling it nine reproductions would have
-- been the number that flatters the finding.
--
-- 🔴 **THE CLIENT HALF WAS REPRODUCED SEPARATELY**, against trunk's `offered-slots.ts` with the new
-- pins in place and the run GATED on the plant actually landing: **31 pass / 6 fail** across all
-- three zones. And the two worst reds were not the seam at all — handed a merged span, the old
-- module emitted `startMin = 1440` (there is no hour 24 for `kstInstant`) and, on the second day of
-- a pair, `startMin = -120`. The seam-acceptance pin itself PASSED on the old module, because it
-- reads the row's `endMin` verbatim: that half of the repair is this file's, not the client's, and
-- saying so is the difference between a battery and a list of things that went red.
--
-- ═══ §0a WHAT THE FUNCTION RETURNS NOW, STATED AS A PROPOSITION ═══════════════════════════════
-- Take every window the runner has open on a day that is not under a 휴가 — the weekly grid rows
-- for that weekday and the `extra` rows dated to it — as a CONCRETE KST interval
-- `[day + start_min, day + end_min)`; `end_min = 1440` is the following midnight. Merge the ones
-- that overlap OR TOUCH. Each merged interval is a **SPAN**. For every KST day `d` in
-- `[p_from, p_to]` that a span intersects, one row:
--
--     day        = d
--     start_min  = the span's start, in minutes from d's KST midnight   (MAY BE NEGATIVE)
--     end_min    = the span's end,   in minutes from d's KST midnight   (MAY EXCEED 1440)
--     source     = 'grid' | 'extra' | 'mixed' — a SUMMARY of the span's constituents
--     segments   = every constituent, in the same units, ascending, covering [start_min, end_min)
--                  exactly: [{"start_min":…,"end_min":…,"source":"grid"|"extra"}, …]
--
-- so `∃ row: row.day = d ∧ row.start_min <= m ∧ m + dur <= row.end_min` is now **exactly**
-- `is_slot_available` §1 for the slot starting at minute `m` of day `d`. That is the whole slice.
--
-- 🔴 **WHY A SPAN IS EMITTED ON EVERY DAY IT TOUCHES AND NOT ONLY ON THE DAY IT STARTS.** The
-- client's vocabulary is a DAY — `windowsForDay(windows, dayKey)` — and both slot sheets draw one
-- day at a time. A span anchored only at its first day would leave the *second* day of a
-- cross-midnight pair with no row at all, and the screen would show 「열린 시간 없음」 for a day the
-- runner had opened. So the span is re-anchored per day, and the price is that its bounds leave
-- `[0, 1440]` — which is the honest shape, because the span genuinely does.
--
-- 🔴 **WHY `segments` AND NOT JUST A `sources text[]`.** The 추가 근무 chip's rule (0215 CLIENT,
-- `offered-slots.ts`) is 「no GRID window contains the whole slot」 — it means 「this time exists
-- ONLY because the runner opened it for this one day」, and that is why a slot sitting inside an
-- ordinary 09:00–21:00 grid window does NOT get a chip even when an `extra` row overlaps it
-- (pinned: `offered-slots.test.cjs` ⑤). A merged span cannot answer that question with one word,
-- and a set of words (`{grid,extra}`) cannot either: the client has to know WHERE the grid part
-- is. `segments` is the smallest thing that answers it, and it answers it across the midnight seam
-- too — which a per-day `source` column could not, because the grid half of a cross-midnight span
-- sits on the other day. The alternative the review left open — 「show nothing rather than a lie」 —
-- was NOT taken: it would have silently dropped a true 추가 근무 badge on the exact windows this
-- slice exists to surface.
--
-- ⚠ `source` survives as a SUMMARY so that 246's `0215-P1` (a lone extra window comes back as
-- `source='extra'`) and `0215-P3` (grid 3 rows / extra 2 rows) keep measuring what they measured —
-- on a fixture with no adjacency a span IS its one window, so those two pins are untouched by this
-- file. The third value `'mixed'` is NEW and it widens what the column can mean, which is a caller
-- obligation and not a free change (§④ WIDENING A SQL RETURN'S MEANING): `api.ts` maps all three by
-- hand and `252 0221-V1` pins that a `'mixed'` row exists in the fixture and that every row's
-- summary agrees with its own segments.
--
-- ═══ §0b ONE DAY OF MARGIN ON EACH SIDE, AND WHY IT IS NOT DECORATION ═════════════════════════
-- The judge builds its union from the days the SLOT touches, so for a 23:30 slot on `p_to` it
-- reads `p_to + 1` — a day outside the caller's range. A list that merged only within
-- `[p_from, p_to]` would end that span at `p_to` 24:00 and refuse to offer a slot the judge
-- accepts: a ⊇ gap created by the range boundary rather than by the calendar. So the merge reads
-- `[p_from - 1, p_to + 1]` and rows are emitted only for `[p_from, p_to]`. `252 0221-E6` is the
-- delta: the same query, with and without the next day's rule.
--
-- ═══ §0c PURE INTEGER MINUTES — THERE IS NO `at time zone` IN THIS BODY, DELIBERATELY ═════════
-- The judge converts `(day + minutes)` to an instant and merges instants. This function merges
-- `(day - p_from) * 1440 + minutes`, an integer. The two agree because the map
-- `(KST day, minute) → instant` is affine and strictly increasing over the supported range: two
-- windows touch in minute space exactly when they touch in instant space, and `end_min = 1440` on
-- day D is the same local timestamp as `start_min = 0` on day D+1, hence the same instant.
-- ⚠ **NAMED LIMITATION — prose, and deliberately not a pin.** That equality is a property of
-- Asia/Seoul having no DST; Korea's last transition was in 1988 and every range this function can
-- be asked about is `now()`-relative. The harness cannot manufacture a DST jump in Asia/Seoul, so
-- a pin asserting it would be green by construction and would be read as coverage it does not buy
-- (§DO NOT WRITE A PIN TO DOCUMENT A LIMITATION). Keeping the body free of `at time zone` is also
-- what lets `246 0215-A2`'s body arms — which run every harness run — keep meaning what they say.
--
-- ═══ §0d WHAT THIS FILE DOES NOT DO ══════════════════════════════════════════════════════════
-- - **It edits no landed migration.** 0003, 0203, 0215 and 0219 are untouched on disk.
-- - **The judge is NOT re-declared.** 0219 §1 is already the union; this file makes the LIST agree
--   with it. `252 0221-S1` asserts the judge is still a definer that `authenticated` and
--   `service_role` can execute, so a future edit here cannot quietly take it with it.
-- - **§3 (confirmed bookings + rest buffer), §4 (holds) and §5 (daily cap) are still NOT applied.**
--   0215 §0b's division is unchanged and `246 0215-P4` still pins it as a delta: this function
--   proposes, `checkSlot` disposes, and the per-slot check stays the final gate on both screens.
-- - **Whether a runner may be booked across midnight at all is still Sean's letter (d).** 0219 §0b
--   made the judge admit it only when the runner genuinely opened both sides; this file makes the
--   screen able to OFFER exactly that set. Narrowing it is a product ruling, not a repair.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A  THE READER — merged spans, per day, with their provenance
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
drop function if exists runner_offered_slots(uuid, date, date);

create function runner_offered_slots(
  p_runner uuid,
  p_from   date,
  p_to     date
) returns table (
  day       date,
  start_min int,
  end_min   int,
  source    text,
  segments  jsonb
)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  -- party gate FIRST [0215]. There is no owner/runner split to make: the grid is already readable
  -- by every signed-in account (0215 §0d), so the only thing to refuse is an account-less caller.
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_runner is null then raise exception 'bad_runner'; end if;
  if p_from is null or p_to is null or p_to < p_from then raise exception 'bad_range'; end if;
  -- inclusive span = p_to - p_from + 1, so 89 is 「at most 90 days」 — the same arithmetic and the
  -- same number as 0203's `rae_range_capped`, so a runner cannot write a range this cannot read.
  if p_to - p_from > 89 then raise exception 'range_too_long'; end if;

  return query
  -- ⚠ the day enumeration is INTEGER arithmetic on dates, never `generate_series(date, date,
  -- interval)`. The latter returns TIMESTAMPS, and a timestamp in a function about KST calendar
  -- days is a timezone waiting to be read by whoever edits this next. [0215]
  -- [0221] ONE DAY OF MARGIN EACH SIDE — §0b. The extra days feed the MERGE; they never reach the
  -- output, because `emit` below re-joins against `p_from .. p_to`.
  with days as (
    select (p_from - 1 + g.i)::date as day
      from generate_series(0, (p_to - p_from) + 2) as g(i)
  ),
  -- §2 [0215] 휴가(blackout)는 그날을 통째로 닫는다 — extra 행도 함께 사라진다.
  -- 0203 §D의 「BLACKOUT BEATS EXTRA」와 같은 구조다: 그쪽은 두 개의 독립된 return false 게이트로,
  -- 여기서는 날짜 자체를 빼는 것으로 같은 결과를 낸다. 두 팔 모두 kind로 갈라 읽는다 — 가르지
  -- 않으면 extra가 자기 자신을 막는다(0203의 테이블 주석).
  -- ⚠ [0221] 휴가는 **합치기 전에** 뺀다. 그래서 휴가 낀 날을 사이에 두고 두 창이 이어지는 일이
  -- 없고, 자정을 사이에 둔 쌍도 한쪽 날이 휴가면 합쳐지지 않는다 — 판정 §2와 같은 결과다.
  open_days as (
    select d.day from days d
     where not exists (
       select 1 from runner_availability_exceptions e
       where e.runner_id = p_runner
         and e.kind = 'blackout'
         and daterange(e.starts_on, e.ends_on, '[]') @> d.day
     )
  ),
  -- §1 [0215] 주간 그리드 — KST 요일. `extract(dow from <date>)`는 달력 연산이라 시간대가 없고,
  -- 판정이 쓰는 요일과 같은 날을 준다 (246 0215-K1이 경계에서 잰다).
  -- §1b [0215] 추가 근무(extra) — 그날 하루의 한 구간. 그리드를 대체하지 않고 더한다.
  -- [0221] 두 팔 모두 **p_from 자정으로부터의 절대 분**으로 편다 (§0c). 이 정수 하나가 「같은 날
  -- 인접」과 「자정 너머 인접」을 같은 비교 하나로 만든다.
  win as (
    select od.day                                        as d,
           (od.day - p_from) * 1440 + r.start_min        as s,
           (od.day - p_from) * 1440 + r.end_min          as e,
           'grid'::text                                  as src
      from open_days od
      join runner_availability_rules r
        on r.runner_id = p_runner
       and r.weekday   = extract(dow from od.day)::int
    union all
    select od.day,
           (od.day - p_from) * 1440 + x.start_min,
           (od.day - p_from) * 1440 + x.end_min,
           'extra'::text
      from open_days od
      join runner_availability_exceptions x
        on x.runner_id = p_runner
       and x.kind      = 'extra'
       and x.starts_on = od.day
  ),
  -- [0221] gaps-and-islands, the SAME shape 0219 §1 uses on instants. `prev_e < s` is a genuine
  -- gap and opens a new island; `prev_e >= s` touches or overlaps and stays in the current one —
  -- so a one-minute hole does not merge and an exact abutment does.
  ranked as (
    select w.s, w.e, w.src,
           max(w.e) over (order by w.s, w.e rows between unbounded preceding and 1 preceding) as prev_e
      from win w
  ),
  grouped as (
    select k.s, k.e, k.src,
           count(*) filter (where k.prev_e is null or k.prev_e < k.s)
             over (order by k.s, k.e rows between unbounded preceding and current row) as grp
      from ranked k
  ),
  spans as (
    select g.grp, min(g.s) as s, max(g.e) as e from grouped g group by g.grp
  ),
  -- [0221] one row per (span × KST day inside the REQUESTED range that the span's interior
  -- touches). Both comparisons are strict, so a span ending exactly at a day's midnight does not
  -- emit on that day — which is what keeps a 휴가 day empty and keeps the ⊆ direction honest.
  emit as (
    select sp.grp, sp.s, sp.e, od.day
      from spans sp
      join open_days od
        on od.day between p_from and p_to
       and (od.day - p_from) * 1440        <  sp.e
       and (od.day - p_from) * 1440 + 1440 >  sp.s
  )
  select em.day,
         (em.s - (em.day - p_from) * 1440)::int,
         (em.e - (em.day - p_from) * 1440)::int,
         case when bool_and(g.src = 'grid')  then 'grid'
              when bool_and(g.src = 'extra') then 'extra'
              else 'mixed' end::text,
         jsonb_agg(jsonb_build_object(
             'start_min', (g.s - (em.day - p_from) * 1440)::int,
             'end_min',   (g.e - (em.day - p_from) * 1440)::int,
             'source',    g.src)
           order by g.s, g.e)
    from emit em
    join grouped g on g.grp = em.grp
   group by em.day, em.grp, em.s, em.e
   order by 1, 2, 3;
end $$;

-- 🔴 THE ACL IS SET BY THIS FILE AND IT IS NOT OPTIONAL HERE. The `drop function` above removes
-- the grants 0215 wrote, so without these two lines the new function is born PUBLIC-executable
-- (0116:636) — the worst shape this repo makes for a SECURITY DEFINER. Measured, not reasoned:
-- deleting the `revoke` alone makes the APPLY ABORT at §B (`anon이 실행할 수 있다`), and deleting it
-- together with §B's anon arm lands the hole and reddens FOUR standing pins — `98 H9` · `99 S1` ·
-- `246 0215-A2` · `252 0221-S1`. That is the hole reproducing and the fix closing it, which are
-- two different claims.
--
-- ⚠ **AND `scripts/check-definer-acl.mjs` IS GREEN ON THAT MUTATION — measured, against a COPY of
-- the migrations dir, never the live one.** Its sentence is 「no `create or replace` of a definer
-- first defined elsewhere relies on grant preservation」, and this file is a `drop` + a bare
-- `create`, which is a different shape: preservation is not relied on, it is impossible. So the
-- gate is right and its green licenses nothing about this function's ACL. What covers it is §B at
-- apply time and the four runtime pins every harness run — named here because reading that green
-- as 「the ACL is checked」 is exactly the substitution this repo keeps paying for. (Whether the
-- gate should also learn the `drop`+`create` shape is a real question with its own baseline and
-- its own false-positive budget; it is not a ride-along on this slice.)
--
-- `service_role` is NOT named: no edge function and no cron calls this (grepped, 2026-09-25:
-- `supabase/functions` has zero references), and it holds EXECUTE through Supabase's function
-- default privileges anyway (`00_shim.sql:135`, `0057:59`).
revoke execute on function runner_offered_slots(uuid, date, date) from public, anon;
grant  execute on function runner_offered_slots(uuid, date, date) to authenticated;

comment on function runner_offered_slots(uuid, date, date) is
'0215→0221: 보호자 화면이 후보 슬롯을 만드는 달력. 주간 그리드 ∪ 추가 근무(extra) − 휴가(blackout)
날을 **구체적인 KST 구간으로 펴서 맞닿거나 겹치는 것을 합친다** — 판정(is_slot_available §1, 0219)이
쓰는 바로 그 합집합이다. 합쳐진 구간(span)은 그것이 건드리는 날마다 한 행으로 나오고, start_min은
음수가, end_min은 1440 초과가 될 수 있다(자정을 넘는 span). segments가 그 span을 이루는 창들을
그대로 들고 있어서 추가 근무 칩이 거짓말을 하지 않는다. §3~§5(확정 예약·홀드·일일 상한)는 일부러
안 본다 — 그건 슬롯별 checkSlot이 마지막 문으로 계속 본다. note는 반환하지 않는다.';

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
    raise exception '0221 VERIFY failed: NO-FUNCTION(runner_offered_slots(uuid, date, date))';
  end if;

  if (select prosecdef from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' definer가 아니다'; end if;
  if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
    then v_bad := v_bad || ' 본문 search_path가 없다'; end if;
  if (select provolatile from pg_proc where oid = v_oid) is distinct from 's'
    then v_bad := v_bad || ' stable이 아니다'; end if;
  -- 🔴 the drop took 0215's grants with it — a NULL ACL here means the two lines above never ran
  if (select proacl from pg_proc where oid = v_oid) is null
    then v_bad := v_bad || ' 🔴 ACL이 NULL이다 (drop 뒤 기본 PUBLIC로 태어났다)'; end if;
  if has_function_privilege('anon', v_oid, 'execute') is not false
    then v_bad := v_bad || ' anon이 실행할 수 있다'; end if;
  if has_function_privilege('authenticated', v_oid, 'execute') is not true
    then v_bad := v_bad || ' authenticated가 실행할 수 없다'; end if;

  -- the OUT list is the privacy contract. A sixth column is how `note` would arrive. Read by
  -- argument MODE ('t' = a table column), never by a naming convention.
  select string_agg(t.n, ',' order by t.ord) into v_cols
    from pg_proc p,
         lateral unnest(p.proargnames, p.proargmodes) with ordinality as t(n, m, ord)
   where p.oid = v_oid and t.m = 't'::"char";
  if v_cols is distinct from 'day,start_min,end_min,source,segments'
    then v_bad := v_bad || ' 🔴 반환 칸이 day,start_min,end_min,source,segments가 아니다 [' || coalesce(v_cols, 'NULL') || ']'; end if;

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
    if (select count(*) from regexp_matches(v_src, 'runner_availability_exceptions', 'g')) is distinct from 2
      then v_bad := v_bad || ' 🔴 예외 테이블을 정확히 두 번 읽지 않는다'; end if;
    if (select count(*) from regexp_matches(v_src, 'kind\s*=\s*''', 'g')) is distinct from 2
      then v_bad := v_bad || ' 🔴 kind로 안 가르는 예외 읽기가 있다'; end if;
    if (v_src ~ 'runner_availability_rules') is not true
      then v_bad := v_bad || ' 🔴 주간 그리드 팔이 없다 (extra가 그리드를 대체했다)'; end if;
    if (v_src ~ '\mdaterange\M') is not true
      then v_bad := v_bad || ' 휴가 비교가 날짜 범위가 아니다 (비권위 instant 칸으로 되돌아갔다)'; end if;
    if (v_src ~ '\mstarts_at\M') is not false or (v_src ~ '\mends_at\M') is not false
      then v_bad := v_bad || ' 🔴 비권위 instant 칸(starts_at/ends_at)을 읽는다'; end if;
    if (v_src ~ '\mnote\M') is not false
      then v_bad := v_bad || ' 🔴 본문이 note를 읽는다'; end if;
    if (v_src ~ 'at time zone') is not false
      then v_bad := v_bad || ' 🔴 순수 날짜·분 산술이 아니다 (at time zone이 들어왔다, §0c)'; end if;
    if (v_src ~ '\mnow\s*\(') is not false
      then v_bad := v_bad || ' 🔴 본문이 now()를 읽는다 (범위는 호출자가 정한다)'; end if;
    -- the stripper's own CONTROL, both ways: `[0221]` occurs ONLY in this body's comments, so a
    -- stripper that silently did nothing would leave it behind and every arm above would be
    -- measuring prose.
    if (v_raw ~ '\[0221\]') is not true
      then v_bad := v_bad || ' 대조: 원본 본문에 [0221] 주석이 없다 (주석 제거 팔이 무의미)'; end if;
    if (v_src ~ '\[0221\]') is not false
      then v_bad := v_bad || ' 대조: 주석 제거가 동작하지 않았다'; end if;
  end if;

  -- the judge is UNTOUCHED by this file, and that is a property worth aborting on: if a future
  -- edit re-declares it here, 0219 §A's own ACL has already gone by and will not re-run.
  if to_regprocedure('is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid is null
    then v_bad := v_bad || ' 🔴 대조: is_slot_available이 없다'; end if;
  if (select prosecdef from pg_proc where oid = to_regprocedure(
        'is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid) is not true
    then v_bad := v_bad || ' 🔴 대조: is_slot_available이 definer가 아니다'; end if;
  if has_function_privilege('service_role', to_regprocedure(
        'is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid, 'execute') is not true
    then v_bad := v_bad || ' 🔴 대조: service_role이 판정을 못 부른다 (transition-booking이 죽는다)'; end if;

  if v_bad <> '' then raise exception '0221 VERIFY failed:%', v_bad; end if;
end $$;
