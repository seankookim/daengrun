-- ═══ 0203 — 예외 일정: a runner's 휴가 and 다구간 become real rows that the booking         ═══
-- ═══        predicate already reads, instead of a 「준비 중」 sentence                        ═══
--
-- ═══ §0 WHAT WAS ACTUALLY THERE ══════════════════════════════════════════════════════════════
-- `app/app/runner/availability.tsx:346` printed 「30분 단위 · 요일당 1구간 (다구간·휴가 등 예외
-- 일정은 준비 중)」. Measured on trunk `fde88a1`, that sentence was accurate about the CLIENT and
-- misleading about the SERVER, in two different directions:
--
--   · **The table has existed since 0001.** `runner_availability_exceptions` (0001:99-106) is a
--     real table with RLS since 0002:30, a self-scoped policy at 0002:78, a purge arm in
--     `delete_my_account_tx` (0115:597) — and **`is_slot_available` §2 has been honouring it as a
--     blackout since 0003:35-40**. What never existed is a WRITER: `grep -rn
--     runner_availability_exceptions app/` returns 0. So the product shipped a blackout mechanism
--     with no door, and the screen described the whole feature as unbuilt.
--   · **`extra` (다구간) genuinely did not exist in any form.** §1 requires a weekly-rule row to
--     CONTAIN the slot, and no row anywhere could add a one-off window.
--
-- ═══ §0a WHICH PREDICATE THIS EXTENDS, AND WHY THE OTHER TWO ARE NOT TOUCHED ══════════════════
-- `DO-NOT-REFACTOR`: 「Availability definitions are deliberately 3 distinct predicates — do not
-- unify」, and 0054's header (lines 33-43) is where the three are written down. They are:
--
--   ① **0015 `available_runners` (view)** — find-now 히어로 카운트/레이더. Has NO time argument
--      (「지금」, minus anything confirmed within 2 h). Screen: 즉시 요청.
--   ② **0003 `is_slot_available` (function)** — the slot RULES engine: weekly grid · rest buffer ·
--      daily cap · holds · **and the exceptions table**. Screen: picking a slot in the booking
--      calendar; also `create-booking-hold`, `transition-booking`'s reschedule-accept, and the
--      recurring cron's re-check (0026:118 → 0111:332 → 0180:160).
--   ③ **0054 `runners_available_for`** — a SPECIFIC booking's 지명 screen, built as an exact
--      MIRROR of `transition-booking`'s accept gate.
--
-- 🔴 **ONLY ② CHANGES, and that is not a compromise — it is where the feature's own jurisdiction
-- already is.** ② is the predicate the weekly grid feeds (`availability.tsx:38` says so in as many
-- words), it is the predicate that already reads this exact table, and it is the one the booking
-- path evaluates. The 예외 일정 section sits directly under the weekly grid on one screen; putting
-- its rows anywhere else would be two facts with one home.
--
-- **③ MUST NOT CHANGE, and the argument is 0054's own, not a preference.** ③ mirrors the accept
-- gate, and the accept gate deliberately refuses to read availability RULES
-- (`transition-booking/index.ts:174-176`: 「find-now 오픈 브로드캐스트는 규칙 밖 시간에도 '지금
-- 온라인'이면 받을 수 있어야 한다 — 충돌만 검사」). Adding a blackout to ③ alone makes the DISPLAY
-- stricter than the SERVER, which is precisely the failure 0054 exists to prevent: the server would
-- still accept a runner the 지명 screen had hidden, and supply evaporates with nobody able to see
-- why. Changing the accept gate to match is a different slice with a different blast radius (an
-- edge deploy, and a product decision about whether a 휴가 should block an ASAP broadcast).
--
-- **① MUST NOT CHANGE, same jurisdiction argument.** ① is 「right now」, and 「right now」 already
-- has a runner-owned switch that is strictly more current than a calendar: `runners.online`. A
-- 휴가 row for TODAY would be redundant with the toggle; a 휴가 row for next week is not a fact
-- about now. The screen says which of the two governs which surface rather than implying one rule
-- (see the client half of this slice).
--
-- ⚠ So the honest sentence, and it is the one the screen prints: **예외 일정 governs the
-- SCHEDULED path (예약 슬롯), and the 온라인 toggle governs the NOW path (즉시 요청).** Neither
-- predicate learned about the other.
--
-- ═══ §0b WHAT THIS FILE DOES **NOT** DO ══════════════════════════════════════════════════════
-- - **It edits NO landed migration.** 0001, 0002, 0003, 0055, 0093 and 0115 are untouched on disk.
--   `is_slot_available` is re-declared FORWARD from this file, and it **restates its own ACL
--   here** — a `create or replace` on an apply where the function is absent is a plain CREATE and
--   a SECURITY DEFINER born PUBLIC-executable is the worst shape this repo makes (0116:636).
-- - **It does not drop `starts_at` / `ends_at`.** They are legacy NOT NULL columns that this file
--   demotes to DERIVED (§A④) rather than deleting, because a DROP COLUMN cannot be verified safe
--   against production from a builder worktree and the columns cost nothing kept.
-- - **It adds no cron, no enum, no notification.** A 휴가 does not cancel anything already
--   confirmed — it removes FUTURE offers. Cancelling live bookings from a calendar row is a
--   product decision with money attached and it is not smuggled in here.
--
-- ═══ §0c THE ONE BEHAVIOUR CHANGE ON EXISTING ROWS, STATED RATHER THAN DISCOVERED ═════════════
-- 0003 §2 blocked on `tstzrange(e.starts_at, e.ends_at) && tstzrange(p_start, p_end)` — an
-- arbitrary-precision instant range. This file makes a blackout a **whole-KST-day** concept
-- (§A③), backfills `starts_on`/`ends_on` from the instants, and has §2 read the DATE columns. For
-- any legacy row that was NOT day-aligned the blackout therefore gets **wider**, never narrower.
-- That is the safe direction (a runner who declared they are out stays out), and the population it
-- can affect is bounded by the measured fact above: **the table has never had a writer**, so every
-- row it could touch would have been hand-written in psql.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A  THE TABLE — one shape, two kinds
-- ═══════════════════════════════════════════════════════════════════════════════════════════════

-- ① the new authoritative columns. `starts_on`/`ends_on` are an INCLUSIVE KST date range on both
--    kinds; `start_min`/`end_min` are minutes-from-KST-midnight and belong to `extra` alone.
alter table runner_availability_exceptions add column if not exists starts_on  date;
alter table runner_availability_exceptions add column if not exists ends_on    date;
alter table runner_availability_exceptions add column if not exists start_min  int;
alter table runner_availability_exceptions add column if not exists end_min    int;
alter table runner_availability_exceptions add column if not exists created_at timestamptz not null default now();

-- ② the kind domain. 0001 shipped `kind text not null default 'blocked'` with a comment naming
--    three values nothing enforced (`vacation | personal | extended`). Every one of them meant
--    「this time is removed」, so they all normalise to `blackout`; `extra` is new and no row can
--    already hold it. The UPDATE is written to be idempotent and to survive a value nobody
--    anticipated.
update runner_availability_exceptions set kind = 'blackout' where kind is null or kind not in ('blackout', 'extra');
alter table runner_availability_exceptions alter column kind set default 'blackout';

-- ③ backfill the date range from the instants, for legacy rows only. `ends_at` is EXCLUSIVE in
--    the old shape (a `tstzrange` upper bound), so the last covered KST day is one microsecond
--    before it — subtracting first is what stops a blackout ending at midnight from eating the
--    following day.
update runner_availability_exceptions
   set starts_on = (starts_at at time zone 'Asia/Seoul')::date,
       ends_on   = greatest(
                     (starts_at at time zone 'Asia/Seoul')::date,
                     ((ends_at - interval '1 microsecond') at time zone 'Asia/Seoul')::date)
 where starts_on is null or ends_on is null;

alter table runner_availability_exceptions alter column starts_on set not null;
alter table runner_availability_exceptions alter column ends_on   set not null;

-- ④ `starts_at` / `ends_at` are now DERIVED and NON-AUTHORITATIVE. They stay NOT NULL and the two
--    RPCs below keep writing them from the date columns, so nothing that reads them breaks — but
--    the predicate no longer does, and neither should anything new.
comment on column runner_availability_exceptions.starts_at is
  '0203: DERIVED, 비권위 — starts_on/start_min에서 RPC가 계산해 넣는다. 판정은 이 칸을 읽지 않는다.';
comment on column runner_availability_exceptions.ends_at is
  '0203: DERIVED, 비권위 — ends_on/end_min에서 RPC가 계산해 넣는다 (배타 상한). 판정은 이 칸을 읽지 않는다.';
comment on table runner_availability_exceptions is
  '0203: 러너 예외 일정. kind=blackout(휴가·통일 KST 일 단위, start_min/end_min은 NULL) ·
kind=extra(다구간·하루 한 구간, starts_on = ends_on). 🔴 이 테이블을 읽는 코드는 **반드시 kind로
갈라야 한다** — kind를 안 보고 겹침만 보면 extra가 자기 자신을 막는다 (0003 is_slot_available §2가
blackout만 읽는 이유). 쓰기는 set_availability_exception / delete_availability_exception 둘뿐이다;
authenticated의 직접 INSERT/UPDATE/DELETE는 §B에서 회수됐다.';

-- ⑤ the CHECK belt. Every one is `not valid`: the RPCs below are the only writers and they refuse
--    by NAME before they reach a constraint, so these bind future writes without risking an apply
--    abort on remote rows this worktree cannot see (the 0054:52 `bookings_km_positive` precedent).
do $$ begin
  alter table runner_availability_exceptions
    add constraint rae_kind_domain check (kind in ('blackout', 'extra')) not valid;
exception when duplicate_object then null; end $$;

do $$ begin
  alter table runner_availability_exceptions
    add constraint rae_range_ordered check (ends_on >= starts_on) not valid;
exception when duplicate_object then null; end $$;

-- inclusive span = ends_on - starts_on + 1, so 89 is 「at most 90 days」.
do $$ begin
  alter table runner_availability_exceptions
    add constraint rae_range_capped check (ends_on - starts_on <= 89) not valid;
exception when duplicate_object then null; end $$;

-- the per-kind shape, as ONE constraint so the two kinds cannot drift apart:
--   blackout → whole days, no window · extra → exactly one day, a real window inside it
do $$ begin
  alter table runner_availability_exceptions
    add constraint rae_kind_shape check (
      (kind = 'blackout' and start_min is null and end_min is null)
      or
      (kind = 'extra' and starts_on = ends_on
        and start_min is not null and end_min is not null
        and start_min >= 0 and end_min <= 1440 and start_min < end_min)
    ) not valid;
exception when duplicate_object then null; end $$;

create index if not exists rae_runner_dates_idx
  on runner_availability_exceptions (runner_id, kind, starts_on, ends_on);

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B  WHO MAY WRITE — the validation becomes a constraint instead of a request
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0002:78 gave the runner `for all using (runner_id = auth.uid())`, which (with no `with check`)
-- also governs INSERT. That was correct when nothing else existed and it is wrong now: a policy
-- can say WHOSE row it is and cannot say 「90 days」, 「a window inside one day」 or 「at most 20」.
-- Leaving the door open beside the RPCs would mean the RPC's refusals are advice a client can walk
-- around with one PostgREST call — the same 「a check that REPORTS vs a constraint that PREVENTS」
-- distinction as deleting `main` instead of asking people not to branch from it.
--
-- ⚠ Blast radius measured before writing this, not assumed: `grep -rn
-- runner_availability_exceptions app/` → **0 hits**. No client path writes or reads this table
-- today, so the revoke breaks nothing that exists.
drop policy if exists "avail exc self all" on runner_availability_exceptions;
do $$ begin
  create policy "avail exc self read" on runner_availability_exceptions
    for select using (runner_id = auth.uid());
exception when duplicate_object then null; end $$;

revoke insert, update, delete on runner_availability_exceptions from anon, authenticated;
-- 0093's argument, on the table next door: a stranger with no account should not be able to learn
-- when a named runner is away. RLS already answers that (the only policy is self-scoped) — the
-- revoke converts 「protected by a policy」 into 「protected by not being granted」, and the
-- `authenticated` grant is restated EXPLICITLY so a future blanket revoke reddens a pin instead of
-- silently turning the screen off.
revoke select on runner_availability_exceptions from anon;
grant  select on runner_availability_exceptions to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C  THE WRITERS
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 🔴 NEITHER FUNCTION TAKES A RUNNER ARGUMENT. The party gate is not a conjunct that could be
-- dropped — the row's owner is `auth.uid()` and there is no other value it could be, so 「write
-- someone else's calendar」 is not a refusal, it is unsayable. `0203-E4` pins the signature for
-- exactly that reason: the guard is the ABSENCE of an argument, and an absence is invisible from
-- both directions unless something asserts it.

create or replace function set_availability_exception(
  p_kind      text,
  p_starts_on date,
  p_ends_on   date,
  p_start_min int  default null,
  p_end_min   int  default null,
  p_note      text default null
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid   uuid := auth.uid();
  v_note  text := nullif(btrim(coalesce(p_note, '')), '');
  v_today date;
  v_live  int;
  v_id    uuid;
  v_s     timestamptz;
  v_e     timestamptz;
begin
  -- party gate FIRST, before anything reads a row or validates a value
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if not exists (select 1 from runners r where r.profile_id = v_uid) then
    raise exception 'not_runner';
  end if;

  if p_kind is null or p_kind not in ('blackout', 'extra') then raise exception 'bad_kind'; end if;
  if p_starts_on is null or p_ends_on is null or p_ends_on < p_starts_on then
    raise exception 'bad_range';
  end if;
  if p_ends_on - p_starts_on > 89 then raise exception 'range_too_long'; end if;

  -- the window is the kind's definition, so both directions are one refusal: an `extra` without a
  -- real window inside ONE day, and a `blackout` carrying a window it would never apply.
  if p_kind = 'extra' then
    if p_starts_on <> p_ends_on
       or p_start_min is null or p_end_min is null
       or p_start_min < 0 or p_end_min > 1440 or p_start_min >= p_end_min then
      raise exception 'bad_window';
    end if;
  else
    if p_start_min is not null or p_end_min is not null then raise exception 'bad_window'; end if;
  end if;

  if v_note is not null and char_length(v_note) > 40 then raise exception 'note_too_long'; end if;

  -- The cap counts rows that can still change an answer. A past 휴가 is history and must not use
  -- up the runner's allowance — counting every row ever written would turn the cap into a slow
  -- lockout nobody could explain.
  v_today := (now() at time zone 'Asia/Seoul')::date;
  select count(*) into v_live
    from runner_availability_exceptions e
   where e.runner_id = v_uid and e.ends_on >= v_today;
  if v_live >= 20 then raise exception 'too_many'; end if;

  -- the DERIVED instants (§A④). Upper bound is EXCLUSIVE, matching the `tstzrange` shape 0001's
  -- columns were born for.
  if p_kind = 'blackout' then
    v_s := (p_starts_on::timestamp) at time zone 'Asia/Seoul';
    v_e := ((p_ends_on + 1)::timestamp) at time zone 'Asia/Seoul';
  else
    v_s := (p_starts_on::timestamp + make_interval(mins => p_start_min)) at time zone 'Asia/Seoul';
    v_e := (p_starts_on::timestamp + make_interval(mins => p_end_min))   at time zone 'Asia/Seoul';
  end if;

  insert into runner_availability_exceptions
    (runner_id, kind, starts_on, ends_on, start_min, end_min, note, starts_at, ends_at)
  values
    (v_uid, p_kind, p_starts_on, p_ends_on,
     case when p_kind = 'extra' then p_start_min end,
     case when p_kind = 'extra' then p_end_min   end,
     v_note, v_s, v_e)
  returning id into v_id;

  return v_id;
end $$;

revoke execute on function set_availability_exception(text, date, date, int, int, text) from public, anon;
grant  execute on function set_availability_exception(text, date, date, int, int, text) to authenticated;

-- `not_found` covers 「no such row」 and 「not yours」 with ONE word, deliberately: a separate
-- `not_owner` would make any uuid an existence oracle for another runner's calendar.
create or replace function delete_availability_exception(p_id uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_n   int;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;
  if p_id is null then raise exception 'not_found'; end if;

  delete from runner_availability_exceptions e
   where e.id = p_id and e.runner_id = v_uid;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'not_found'; end if;
  return true;
end $$;

revoke execute on function delete_availability_exception(uuid) from public, anon;
grant  execute on function delete_availability_exception(uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §D  THE PREDICATE — 0003 `is_slot_available`, re-declared forward
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Two arms move and nothing else does. §3, §4 and §5 are 0003's text, carried over unchanged.
--
--   · **§1 gains a DISJUNCT.** The weekly grid still admits, and now an `extra` row on that KST
--     date admits too. It is an OR and never a replacement — a runner who adds one Saturday
--     morning does not lose their weekday grid.
--   · **§2 gains a KIND FILTER and moves to the DATE columns.** The filter is not tidying: without
--     it an `extra` row overlaps its own slot and a 다구간 window would block the very time it was
--     created to open.
--
-- 🔴 **BLACKOUT BEATS EXTRA, and it is structural rather than an ordering.** §1 and §2 are two
-- independent `return false` gates, so an `extra` can only satisfy §1 — it can never reach past
-- §2. A runner who marks a 휴가 week and then adds a 추가 근무 inside it stays out. `0203-E3` pins
-- that with its own control.
--
-- ⚠ A slot that crosses KST midnight fails §1 on BOTH arms, because `v_end_min` wraps below
-- `v_start_min` and no containment can hold. That is 0003's existing behaviour for the weekly
-- grid and the `extra` arm inherits it deliberately — one rule for one screen. The blackout arm
-- does NOT inherit it: it compares whole dates and uses the last KST day the slot actually
-- touches, so an overnight slot is blocked by a blackout on either of its days.
create or replace function is_slot_available(
  p_runner uuid,
  p_start timestamptz,
  p_end timestamptz
) returns boolean
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_wd int;
  v_start_min int;
  v_end_min int;
  v_start_date date;
  v_end_date date;
  v_rest int;
  v_max_daily int;
  v_daily_count int;
begin
  -- KST 기준 요일/분/날짜
  v_wd := extract(dow from p_start at time zone 'Asia/Seoul');
  v_start_min := extract(hour from p_start at time zone 'Asia/Seoul') * 60
               + extract(minute from p_start at time zone 'Asia/Seoul');
  v_end_min := extract(hour from p_end at time zone 'Asia/Seoul') * 60
             + extract(minute from p_end at time zone 'Asia/Seoul');
  v_start_date := (p_start at time zone 'Asia/Seoul')::date;
  -- 상한은 배타 — 자정 정각에 끝나는 슬롯이 다음 날까지 차지한 것으로 세지 않는다
  v_end_date := greatest(v_start_date,
                         ((p_end - interval '1 microsecond') at time zone 'Asia/Seoul')::date);

  -- 1. 주간 규칙 내 **또는** 그 날짜의 추가 근무(extra) 구간 내 [0203]
  if not exists (
    select 1 from runner_availability_rules r
    where r.runner_id = p_runner and r.weekday = v_wd
      and r.start_min <= v_start_min and r.end_min >= v_end_min
  ) and not exists (
    select 1 from runner_availability_exceptions x
    where x.runner_id = p_runner and x.kind = 'extra'
      and x.starts_on = v_start_date
      and x.start_min <= v_start_min and x.end_min >= v_end_min
  ) then return false; end if;

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

-- 🔴 THE ACL IS RESTATED HERE AND THAT IS NOT DECORATION — but the reason is NOT the one a first
-- draft of this comment gave, and the correction is kept rather than tidied away because it is the
-- more useful half.
--
-- ⚠ **THE FIRST DRAFT SAID 「before this file `is_slot_available` ran on the default PUBLIC
-- EXECUTE, so a key with no account could probe a named runner's calendar」. THAT IS FALSE.** It
-- came from `grep -iE 'grant|revoke'` over the migrations finding no line naming this function —
-- an absence read as 「nobody closed it」 when the real answer is that it was closed by something a
-- per-function grep structurally cannot see: **`0057_security_hardening.sql` §1 sweeps EVERY
-- `public` SECURITY DEFINER function and runs `revoke execute … from public, anon`**, restoring
-- `authenticated` where it had it. Measured on the harness with both revoke lines below DELETED
-- (battery M9): `proacl = {postgres=X/postgres, service_role=X/postgres, authenticated=X/postgres}`
-- — no PUBLIC entry — and `has_function_privilege('anon', …, 'execute') = false`. The oracle was
-- already shut.
--
-- **What the two lines below really buy, and it is one path rather than a class:** 0057 §1 is a
-- SWEEP that ran once, at 0057. If this file's `create or replace` lands where the function is
-- ABSENT — a partial prior apply, a branch that never ran 0003, a rebuilt environment — the
-- statement above is a plain CREATE, the new function is born PUBLIC-executable (0116:636), and
-- 0057 has already gone by and will not re-run. That is exactly the class `check-definer-acl.mjs`
-- exists for, and it is why the re-declaring FILE must set the ACL rather than inherit one.
--
-- Both real callers are named rather than inferred, so the `grant` line is a measurement and not a
-- guess: `app/src/lib/api.ts:2491` (`checkSlot`, as `authenticated`) and
-- `supabase/functions/transition-booking/index.ts:525` (as `service_role`). Every other caller is
-- inside a definer body and runs as the owner.
-- ⚠ `service_role` additionally holds EXECUTE through Supabase's function default privileges
-- (`00_shim.sql:135` models it; `0057:59` says so), so naming it here cannot be observed by
-- deleting it — battery M9/M7 measured exactly that. It is named anyway because the default
-- privilege is a property of the PROJECT and this grant is a property of the FILE.
revoke execute on function is_slot_available(uuid, timestamptz, timestamptz) from public, anon;
grant  execute on function is_slot_available(uuid, timestamptz, timestamptz) to authenticated, service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §E  VERIFY — the apply refuses rather than landing a half of this
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_bad text := '';
  v_oid oid;
  v_src text;
  v_raw text;
  r record;
begin
  -- the three functions' shape
  for r in select unnest(array[
             'is_slot_available(uuid, timestamp with time zone, timestamp with time zone)',
             'set_availability_exception(text, date, date, integer, integer, text)',
             'delete_availability_exception(uuid)']) as sig
  loop
    v_oid := to_regprocedure(r.sig)::oid;
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || r.sig || ')'; continue; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || r.sig || ': definer가 아니다'; end if;
    if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || r.sig || ': 본문 search_path가 없다'; end if;
    if (select proacl from pg_proc where oid = v_oid) is null
      then v_bad := v_bad || ' ' || r.sig || ': ACL이 NULL이다 (기본 PUBLIC)'; end if;
    if has_function_privilege('anon', v_oid, 'execute') is not false
      then v_bad := v_bad || ' ' || r.sig || ': anon이 실행할 수 있다'; end if;
    if has_function_privilege('authenticated', v_oid, 'execute') is not true
      then v_bad := v_bad || ' ' || r.sig || ': authenticated가 실행할 수 없다'; end if;
  end loop;

  -- the predicate's two moved arms, read from the DEPLOYED body with comments stripped. `prosrc`
  -- is source plus our own prose and this file documents both arms at length — an un-stripped
  -- match would be satisfied by the writing that EXPLAINS the fix.
  select prosrc into v_raw from pg_proc where oid = to_regprocedure(
    'is_slot_available(uuid, timestamp with time zone, timestamp with time zone)')::oid;
  if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(is_slot_available)';
  else
    v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
    if (v_src ~ 'kind\s*=\s*''extra''') is not true
      then v_bad := v_bad || ' 판정 §1에 extra 팔이 없다'; end if;
    if (v_src ~ 'kind\s*=\s*''blackout''') is not true
      then v_bad := v_bad || ' 판정 §2가 blackout으로 가르지 않는다 (extra가 자기 자신을 막는다)'; end if;
    -- EXACTLY two reads, EXACTLY two kind filters. A third read of this table, or a read without a
    -- kind filter, is the defect the table comment warns about — and it would be invisible to an
    -- arm that only checked the two words are present somewhere.
    if (select count(*) from regexp_matches(v_src, 'runner_availability_exceptions', 'g')) is distinct from 2
      then v_bad := v_bad || ' 🔴 판정이 예외 테이블을 정확히 두 번 읽지 않는다'; end if;
    if (select count(*) from regexp_matches(v_src, 'kind\s*=\s*''', 'g')) is distinct from 2
      then v_bad := v_bad || ' 🔴 예외 읽기 중 kind로 가르지 않는 것이 있다'; end if;
    if (v_src ~ '\mdaterange\M') is not true
      then v_bad := v_bad || ' 휴가 비교가 날짜 범위가 아니다 (비권위 instant 칸으로 되돌아갔다)'; end if;
    -- the stripper's own CONTROL: `[0203]` occurs ONLY in this body's comments, so a stripper that
    -- silently did nothing would leave it behind and every arm above would be measuring prose.
    if (v_raw ~ '\[0203\]') is not true
      then v_bad := v_bad || ' 대조: 원본 본문에 [0203] 주석이 없다 (주석 제거 팔이 무의미)'; end if;
    if (v_src ~ '\[0203\]') is not false
      then v_bad := v_bad || ' 대조: 주석 제거가 동작하지 않았다'; end if;
  end if;

  -- the write door is closed and the read door is open
  if has_table_privilege('authenticated', 'public.runner_availability_exceptions', 'insert') is not false
    then v_bad := v_bad || ' 🔴 authenticated가 예외 행을 직접 INSERT할 수 있다'; end if;
  if has_table_privilege('authenticated', 'public.runner_availability_exceptions', 'update') is not false
    then v_bad := v_bad || ' 🔴 authenticated가 예외 행을 직접 UPDATE할 수 있다'; end if;
  if has_table_privilege('authenticated', 'public.runner_availability_exceptions', 'delete') is not false
    then v_bad := v_bad || ' 🔴 authenticated가 예외 행을 직접 DELETE할 수 있다'; end if;
  if has_table_privilege('authenticated', 'public.runner_availability_exceptions', 'select') is not true
    then v_bad := v_bad || ' 대조: authenticated가 자기 예외 행도 못 읽는다'; end if;
  if has_table_privilege('anon', 'public.runner_availability_exceptions', 'select') is not false
    then v_bad := v_bad || ' anon이 예외 행을 읽을 수 있다'; end if;

  if v_bad <> '' then raise exception '0203 VERIFY failed:%', v_bad; end if;
end $$;
