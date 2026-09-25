-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0232 — the cancel-money sweep stops sending a false 「delayed」 notice · the recurring generator
--        honours a suspended/retired course · a debt pause's episode is recorded, not inferred
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 263_sweep_honesty_route_gate_suite.sql (tag `shr`) — 0232-A1 · A2 · A3 · B1 · B2 · B3 · B4 ·
--        D1 · D2 · D3 · H1 · S1
-- Deploy: `supabase db push` only. No edge function, no cron change, no flag. One NEW owner-facing
--        title (§B) has no client route yet — see §0d.
-- ⚠ Numbers 0229–0231 (and suites 260–262) were SKIPPED: they are held by unpushed worktrees on
--   Sean's Mac (REGISTRY.md, the 0228 row). This file is 0232 / suite 263 on the coordinator's word,
--   re-checked against every local and remote-tracking ref at commit time.
--
-- ═══ §0a WHAT IS WRONG ═════════════════════════════════════════════════════════════════════════
--   (1) gap sweep 2 P9 — `sweep_cancel_money_gaps` (0117 §9e, its only declaration). The candidate
--       predicate admitted a row missing EITHER half — the runner's comp or the owner's charge
--       intent. While `payments_live_since` is NULL the mint writes nothing by design (0080 §E and
--       the sweep's own second bound), so every protocol-era fee cancel whose comp was written on
--       time stayed a candidate FOREVER; and inside the loop `n := n + 1` and the runner notice
--       「시간을 비워둔 보상이 기록됐어요 / 취소 보상 기록이 지연됐다가 방금 반영됐어요」 ran whether or
--       not anything had been repaired. For an EN-ROUTE cancel the on-time notice's title is
--       「예약 취소됨」 (transition-booking/cancel_owner.ts), so the title dedupe missed and the runner
--       was told their comp had been DELAYED when it was written on time. (For a late cancel the
--       on-time notice carries this same title, so the dedupe hid the lie there — the count still
--       ran.) REPRODUCED: 263 `0232-A1` on 0117's body — n = 1 and one notice for a row nothing
--       was done to.
--   (2) gap sweep 2 P9 — `generate_recurring_bookings` (latest: 0227 §B) inserts `s.route_id`
--       without reading `routes.status`, while `create-booking-hold/handler.ts:236-243` refuses a
--       `suspended` or `retired` course. An operator's suspension (a flooded path, a closed park)
--       stopped new holds and NOT the weekly copy. REPRODUCED: 263 `0232-B1` on 0227's body — a
--       booking minted on a suspended course.
--   (3) Codex s2 (medium, docs/reviews/2026-09-25-wave4-codex-verdicts.md) — 0226 §C's debt-episode
--       witness `_unsettled_charge_through(owner, notice.created_at)` asks 「did a charge EXIST before
--       the notice and is it debt NOW」, not 「was it debt THEN」. A is failed and B a freshly
--       dispatched pending when the notice goes out; A is paid (the debt the owner was told about is
--       over); B crosses the one-hour threshold — and because B was minted before the notice, the
--       genuinely new pause is suppressed for up to 24 h. 0226 §0c named exactly this as its
--       「NAMED RESIDUE」. REPRODUCED: 263 `0232-D1` on 0227's body.
--
-- ═══ §0b WHAT THIS FILE DOES ═════════════════════════════════════════════════════════════════
--   §A `sweep_cancel_money_gaps` — 0117's body, built BY SCRIPT, byte-faithful except two changes:
--        ① the payments arm of the candidate predicate carries the mint gate's own two conjuncts
--          (flag set, row updated at or after it) — a row is a candidate only if a writer below can
--          act on it;
--        ② `n` counts a row only when the comp branch or the mint ran (`v_did`), and the runner
--          notice fires only when the COMP branch ran (`r.comp_missing`).
--        No LIMIT (unchanged). ACL restated.
--   §B `recurring_pause_notices` — NEW server-only table: one row per recurring pause notice the
--        generator writes, keyed by the notification's id (on delete cascade), carrying the series,
--        the reason (`debt` · `no_card` · `route`) and — for debt — the ids of the charges that were
--        debt when it went out. Why a table and not the notification: `notifications` is the owner's
--        own row (read by the client, deleted with the account) and has one untyped `ref_id`, which
--        this title family deliberately leaves NULL (the client routes it by title alone).
--   §C `_unsettled_charge_ids(owner)` — 0226 §B's body with its one added conjunct REMOVED and
--        `exists` turned into `array_agg(p.id)`: 0080 §F's debt predicate, returning WHICH charges.
--        263 `0232-H1` holds it equal to `owner_has_unsettled_charge` over the whole population.
--   §D `generate_recurring_bookings` — 0227 §B's body, built BY SCRIPT; every other line asserted
--        identical. The edits:
--        ① two declare lines (`v_nid`, `v_debt`);
--        ② `v_debt := _unsettled_charge_ids(owner)` at the top of the money-block branch;
--        ③ the pause dedupe's debt conjunct: an earlier notice counts only while one of the charges
--          on ITS episode row is still debt (`&&`); a notice with no row predates 0232 and keeps
--          0226's witness;
--        ④ the pause insert returns its id and writes its episode row; a tick that finds the debt
--          continuing adds today's debt charges to every live episode row that still overlaps it;
--        ⑤ the route gate, immediately before the booking insert: a `suspended` or `retired` course
--          mints nothing and tells the owner once per series per 24 h per episode.
--        The per-series subtransaction and its nested failure record (0227), the money gates, the
--        dog lock, `lock_timeout`, the loop order, the ownership belt, every other insert and string:
--        UNCHANGED. ACL restated (0227's, verbatim).
--
-- ═══ §0c WHY THESE KEYS ════════════════════════════════════════════════════════════════════════
--   · §A ① is not a new rule: it is the mint gate's own condition moved up into the row filter, so
--     「candidate」 and 「something below will run」 are the same sentence. With ① in place ② can never
--     see a candidate where neither writer runs, so ②'s counter guard is belt-and-braces — 263's
--     header records that this is a disjunction the pins can observe only as a pair (the `0232-A1`
--     plant battery), not arm by arm. ②'s NOTICE guard is separately observable: a post-flip row with
--     its comp written and its intent missing IS a candidate (the mint runs) and must not tell the
--     runner their comp was delayed (`0232-A3`).
--   · §D ③ — the episode is identified by the charges that were debt WHEN THE NOTICE WENT OUT, the
--     thing codex s2 says 0226 inferred. 0226-C2/C3 (257) still hold: paying everything the notice
--     was about ends the episode (C2); a second charge failing while the first is unpaid does not
--     (C3 — and ④ writes that second charge into the episode, so paying the FIRST one later does not
--     read as a new episode either: `0232-D2`).
--   · §D ④ observes continuity only at tick granularity. NAMED RESIDUE (prose — a pin could only
--     restate it): if the original debt is paid and a pre-existing pending becomes debt within ONE
--     hourly interval with no tick in between, the owner is told again although, minute by minute,
--     they were never out of debt. That errs toward telling — the opposite direction from 0226's
--     residue, which erred toward silence.
--   · §D ⑤ is keyed PER SERIES (the brief), with the series' own booking as the episode witness —
--     0226's shape one level down. It does not read `v_notified` (an owner-level, money-only guard).
--
-- ═══ §0d WHAT THIS FILE DELIBERATELY DOES NOT DO ════════════════════════════════════════════════
--   · Codex s1 (high) — an OPS escalation for a series that fails every tick — is NOT here. It needs
--     a new `kind='system'` writer, and 245 `0214-T1`/`T4` pin the ledger and the writer set by value
--     (a new writer or title reddens both until 245 is edited in the same slice, as 0224 did). 245 was
--     outside this slice's file allowlist, so the escalation is left for a slice that owns 245 — see
--     the REGISTRY row. `recurring_generation_failures` (0227) is unchanged and still the durable trace.
--   · The route notice's title 「반복 예약 코스 점검 중」 is NEW. `app/src/lib/notification-route.ts`
--     has no entry for it, so the inbox draws it as a line of text without a tap (the no-dead-button
--     law) until a client slice gives it a destination. It deliberately does NOT reuse
--     「반복 예약 일시 중지」: that title routes to `/payments` (REFLESS_BOOKING_DESTINATIONS) — the
--     wrong screen for a course problem — and the money dedupe matches it by title, so a route
--     notice would have suppressed a debt pause. The same body goes to a `retired` course (permanent)
--     as to a `suspended` one (temporary), as the brief wrote it.
--   · `marketplace_cancel_fee`, `record_enroute_cancel_comp`, `cancel_owner.ts`, the recurring
--     clash/billing checks: untouched.
--   · No backfill of episode rows for pre-0232 notices (they fall back to 0226's witness and age out
--     of the 24 h window on their own).
--
-- ═══ §0d-bis SHIPPED PINS THAT MOVE, AND WHY ═════════════════════════════════════════════════════
--   · `161 P4` — the generator's prosrc/comment digests, re-read from the catalog after this file
--     applied, as P4's own note asks.
--
-- ═══ §0e WHOSE OBJECTS THIS BUILDS ON (REGISTRY's silent-collision table) ════════════════════════
--   RE-DECLARES `sweep_cancel_money_gaps()` ←0117 §9e and `generate_recurring_bookings()` ←0227 §B
--   (both built by script, every other line asserted identical). CREATES `recurring_pause_notices`
--   and `_unsettled_charge_ids(uuid)`. Every ACL restated in THIS file.
--   ⚠ A later slice re-declaring `generate_recurring_bookings` must keep 0227's per-series block and
--   nested record write, AND this file's route gate (263 `0232-B1…B4`) and episode rows (`0232-D1…D3`).
--   ⚠ A later slice re-declaring `sweep_cancel_money_gaps` must keep the payments-arm conjuncts and the
--   `r.comp_missing` notice guard (263 `0232-A1…A3`).

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A sweep_cancel_money_gaps — a candidate is a row a writer below can act on
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0117 §9e's body, built BY SCRIPT: two changes (§0b), every other line 0117's byte for byte.
create or replace function sweep_cancel_money_gaps() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; n int := 0;
  v_did boolean;   -- [0232 §A] did the comp branch or the mint run for THIS row?
begin
  -- [blind r5 NOTE-10] gated by the SAME flag as the rest of the protocol. Ungated, this cron
  -- would start writing runner ledger rows for HISTORICAL cancellations the moment the file
  -- landed — money appearing in people's ledgers because a migration was pushed, which is the
  -- deploy-day surprise the flag exists to prevent. It repairs what the protocol era produced.
  if (select f.late_protocol_live_since from ops_flags f) is null then return 0; end if;
  if not pg_try_advisory_lock(hashtextextended('cancel_money_gaps', 0)) then return 0; end if;
  for r in
    select b.id, b.cancel_reason, b.updated_at,
           not exists (select 1 from ledger_items li where li.booking_id = b.id) as comp_missing,
           not exists (select 1 from payments pm where pm.booking_id = b.id)     as intent_missing
    from bookings b
    where b.status = 'cancelled_owner'
      and b.club_session_id is null
      and coalesce(b.cancel_fee, 0) > 0
      and b.cancel_reason in ('owner_cancel_enroute', 'owner_cancel_late')
      and b.runner_id is not null
      -- [blind r5 F5] A LEDGER ROW IS NOT EVIDENCE THE FEE WAS COLLECTED. Round 4 excluded any
      -- booking that had one, so the commonest tear — comp written, then the worker dies before
      -- `collectCancelFee` — was invisible to the repair that existed for it, and deleting the
      -- collection call outright left the pin green. The two halves are independent facts and
      -- each is checked for itself.
      and (not exists (select 1 from ledger_items li where li.booking_id = b.id)
           -- [0232 §A] THE PAYMENTS ARM ADMITS ONLY A ROW THE MINT BELOW COULD ACT ON. It read
           -- `or not exists (payments)` alone, and while `payments_live_since` is null the mint
           -- writes nothing — so every protocol-era fee cancel whose comp was written ON TIME was a
           -- candidate forever, and each tick counted it and sent its runner 「취소 보상 기록이
           -- 지연됐다가 방금 반영됐어요」 (the title dedupe misses: the on-time en-route notice is
           -- 「예약 취소됨」). The two added conjuncts are the mint gate's own, below, verbatim.
           or (not exists (select 1 from payments pm where pm.booking_id = b.id)
               and (select f.payments_live_since from ops_flags f) is not null
               and b.updated_at >= (select f.payments_live_since from ops_flags f)))
      -- give the request that owns this cancel time to finish its own writes; only rows that
      -- are STILL bare after the window are torn.
      and b.updated_at < now() - cancel_gap_grace()
      -- ⚠ [R3, 2026-08-24] THE LOWER BOUND. Every temporal clause above it is an UPPER bound, and
      -- without this line the sweep is precisely the retroactive-billing machine that
      -- `sweep_settled_without_payments` names in its own header. The comment at the top of this
      -- function claims the flag confines it to "what the protocol era produced" — IT DOES NOT.
      -- The flag gates WHEN the sweep starts, not WHICH rows it selects, so the first tick after
      -- the flip reaches back over all of history.
      -- Reproduced: a 90-day-old `cancelled_owner` row (fee 2490, `owner_cancel_late`, no payments
      -- row) acquired a pending ₩2,490 charge intent marked due for dispatch AND a retroactive
      -- ₩1,245 runner ledger row on the first tick — and `cron.schedule('cancel-money-gaps',
      -- '6-56/10 * * * *')` makes that unattended and inside ten minutes of the flip.
      -- `mint_cancel_fee_intent` cannot save us here: 0080 says its anchor is `now()` "because a
      -- cancel has no run to date it by", which is true only when it is called AT cancel time.
      and b.updated_at >= (select f.late_protocol_live_since from ops_flags f)
    order by b.id
  loop
    begin
      v_did := false;
      if r.comp_missing then
        if r.cancel_reason = 'owner_cancel_enroute' then
          perform record_enroute_cancel_comp(r.id);
        else
          perform record_late_cancel_share(r.id);
        end if;
        v_did := true;
      end if;
      -- the owner's side of the same tear. `mint_cancel_fee_intent` is idempotent and returns
      -- ZERO ROWS while charging is off (0080 §E), so this is inert pre-cutover and cannot
      -- double-mint after it. Dispatch stays with the edge/ladder — this only restores the
      -- intent the dying request never wrote.
      -- [R3] THE SECOND BOUND, and it is a different line in time from the one in the row filter.
      -- The protocol flip says which tears this sweep OWNS; the payments cutover says which of
      -- them may be CHARGED. A cancel made after the protocol flip but before charging went live
      -- was told it cost nothing, so minting an intent for it later is the same deploy-day
      -- surprise one flag narrower. This mirrors `mint_settle_charge_intent`'s own
      -- `pilot-era run: free, forever` guard rather than inventing a second rule.
      -- Belt and braces on purpose: 0080 §E already makes the mint return zero rows while
      -- charging is off, but that is a property of another file that this sweep must not depend
      -- on to avoid billing someone retroactively.
      if r.intent_missing
         and (select f.payments_live_since from ops_flags f) is not null
         and r.updated_at >= (select f.payments_live_since from ops_flags f) then
        perform mint_cancel_fee_intent(r.id);
        v_did := true;
      end if;
      -- [0232 §A] counted only when a writer ran for this row, and the runner is told only when
      -- the COMP branch ran — a repaired charge intent is the owner's side, not the runner's.
      if v_did then n := n + 1; end if;
      insert into notifications (profile_id, kind, title, body, ref_id)
      select b.runner_id, 'booking', '시간을 비워둔 보상이 기록됐어요',
             '취소 보상 기록이 지연됐다가 방금 반영됐어요', b.id
      from bookings b
      where b.id = r.id and b.runner_id is not null
        and r.comp_missing                           -- [0232 §A] the comp branch ran
        and not exists (select 1 from notifications nt
                        where nt.ref_id = b.id and nt.profile_id = b.runner_id
                          and nt.title = '시간을 비워둔 보상이 기록됐어요');
    exception when others then
      raise warning 'sweep_cancel_money_gaps % : %', r.id, sqlerrm;
    end;
  end loop;
  perform pg_advisory_unlock(hashtextextended('cancel_money_gaps', 0));
  return n;
exception when others then
  perform pg_advisory_unlock(hashtextextended('cancel_money_gaps', 0));
  raise;
end $$;

-- 0117's ACL, restated — never rely on grant preservation (0116:636; check-definer-acl).
revoke execute on function sweep_cancel_money_gaps() from public, anon, authenticated;
grant  execute on function sweep_cancel_money_gaps() to service_role;

comment on function sweep_cancel_money_gaps is
  '0117 §9e (blind review BLOCKER-5): 취소는 한 문장으로 커밋되고 그 돈의 결과는 이어지는
요청들이 쓴다 — 그 사이에 워커가 죽으면 수수료만 적힌 채 러너 보상도 청구 인텐트도 없는
영구 부분 커밋이 남고, 재시도는 이미-취소됨으로 빠져나가 복구하지 못한다. 이 스윕이 그
행들을 찾아 멱등한 보상 기록을 다시 몬다 (0080의 sweep_settled_without_payments 와 같은
형상). 타이머가 돈을 결정하지 않는다 — 사람이 이미 결정한 것을 마저 쓸 뿐이다 (0068 구분).
+ [0232 §A] the payments arm admits a row only when charging is live and the row was updated at or
after payments_live_since (the mint gate''s own conditions), n counts a row only when the comp branch
or the mint ran, and the runner''s 「시간을 비워둔 보상이 기록됐어요」 fires only when the comp branch
ran. 263 0232-A1/A2/A3 pin it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B recurring_pause_notices — the episode each recurring pause notice announced
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
create table if not exists recurring_pause_notices (
  notice_id        uuid primary key references notifications(id) on delete cascade,
  series_id        uuid references recurring_series(id) on delete set null,   -- the series that tripped it
  reason           text not null check (reason in ('debt', 'no_card', 'route')),
  debt_payment_ids uuid[] not null default '{}'   -- debt: the charges that were debt when it went out
);
alter table recurring_pause_notices enable row level security;
revoke all on table recurring_pause_notices from public, anon, authenticated;
grant select, insert, update, delete on table recurring_pause_notices to service_role;

comment on table recurring_pause_notices is
  '0232 §B: one row per recurring pause notice generate_recurring_bookings writes (반복 예약 일시 중지 /
반복 예약 코스 점검 중), keyed by the notification id (cascade). reason = debt | no_card | route. For
debt, debt_payment_ids = the charges that were debt when the notice went out, extended by every tick
that finds the debt continuing; the pause dedupe counts the notice only while one of them is still
debt. For route, the dedupe is per series. Server-only: RLS on, no policies, no client privilege.
Written and read only by the generator. 263 0232-B*/D*/S1 pin it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C _unsettled_charge_ids — WHICH charges make an owner a debtor now
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0226 §B's body (itself 0080 §F's predicate + one conjunct) with that conjunct removed and `exists`
-- turned into the ids. ⚠ A NEW definer, server-only like the gate it copies.
create or replace function _unsettled_charge_ids(p_owner uuid) returns uuid[]
language sql stable security definer
set search_path = public, pg_temp
as $$
  select coalesce(array_agg(p.id order by p.id), '{}'::uuid[])
    from payments p
    join bookings b on b.id = p.booking_id
    where b.owner_id = p_owner
      and (
        exists (select 1 from runs r where r.booking_id = b.id and r.ended_at is not null)
        or exists (select 1 from ledger_items li where li.booking_id = b.id)
        or coalesce(b.cancel_fee, 0) > 0
      )
      and (p.raw->>'kind') is not null      -- server-minted only (round-2 R1 P1-2)
      and (
        p.status = 'failed'
        or (p.status = 'pending'
            and (p.raw->>'dispatched_at') is not null
            and (p.raw->>'dispatched_at')::timestamptz < now() - interval '1 hour')
      )
$$;

revoke execute on function _unsettled_charge_ids(uuid) from public, anon, authenticated;
grant  execute on function _unsettled_charge_ids(uuid) to service_role;

comment on function _unsettled_charge_ids is
  '0232 §C: the ids of the charges that make owner_has_unsettled_charge (0080 §F) true for this owner
NOW — the same predicate (scope arms, server-minted, failed or dispatched-pending past an hour),
returning which rows instead of whether. Empty ⇔ no debt. Read by generate_recurring_bookings to
record and test a debt pause''s episode. Server-only. 263 0232-H1 pins it against the gate over the
whole population.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §D generate_recurring_bookings — the route gate, and a debt pause's episode on the record
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0227 §B's body, built BY SCRIPT: the edits in §0b, every other line 0227's byte for byte.
create or replace function generate_recurring_bookings() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s record;
  n int := 0;
  v_dow int; v_time text;
  v_kst_now timestamp;
  v_next_date date;
  v_sched timestamptz;
  v_start timestamptz; v_end timestamptz;
  v_runner uuid; v_avail boolean; v_clash boolean;
  v_bid uuid;
  v_live boolean;              -- [0080] cutover switch, read once per sweep
  v_block text;                -- [0080] null | 'debt' | 'no_card'
  v_notified uuid[] := '{}';   -- [0080] owners already told this sweep (ⓓ)
  v_fail_state text;          -- [0227] the SQLSTATE a failed series raised …
  v_fail_msg text;            -- [0227] … and its message
  v_nid uuid;                 -- [0232] the notice just written (its episode row keys on it)
  v_debt uuid[];              -- [0232] the owner's debt charges NOW (a pause's episode)
begin
  select (select f.payments_live_since from ops_flags f where f.id) is not null into v_live;

  -- [0180] the bounded wait (0117 MINOR-14's other half, late_booking_sweep's value): the dog
  -- locks below can WAIT, and a sweep stalled on one holds every lock it already took. Past 2 s
  -- the statement raises, this transaction and its locks release, and the next tick retries.
  perform set_config('lock_timeout', '2000', true);

  -- [0180] deterministic candidate order: two overlapping ticks take the dog locks below in the
  -- same sequence, so they queue instead of deadlocking (0117 MINOR-14's lesson, applied here).
  for s in select * from recurring_series where not paused and dog_id is not null
           order by dog_id, id loop
    -- [0227] EACH SERIES IN ITS OWN SUBTRANSACTION — the Codex s1 shape (0226 §0d ③ named it here).
    -- Until 0227 one series whose write raised — a row held past the 2 s lock_timeout above, or any
    -- other fault — raised out of the WHOLE function: every other owner's booking in the tick went
    -- unminted, every notice already written rolled back, and the next tick met the same series
    -- again, so nothing resolved it (258 `0227-R1`/`R2`, reproduced on 0226's body). Everything one
    -- series writes — its booking, 「반복 러닝 예약 생성」, 「지명 러닝 요청」, the pause notice —
    -- commits or rolls back TOGETHER, so a booking never outlives the notice that announces it
    -- (`0227-R3`). Inside this block the body is 0226's byte for byte, one indent deeper.
    begin
      v_dow := (s.rule->'weekdays'->>0)::int;
      v_time := s.rule->>'time';
      if v_dow is null or v_time is null then continue; end if;

      -- 다음 발생 시각 (KST) — 오늘 포함, 최소 통보 2h 미달이면 다음 주
      v_kst_now := now() at time zone 'Asia/Seoul';
      v_next_date := v_kst_now::date + ((v_dow - extract(dow from v_kst_now)::int + 7) % 7);
      v_sched := (v_next_date::text || ' ' || v_time)::timestamp at time zone 'Asia/Seoul';
      if v_sched < now() + interval '2 hours' then
        v_sched := v_sched + interval '7 days';
      end if;
      if v_sched > now() + interval '72 hours' then continue; end if;

      -- [0180] THE DOG LOCK — the same key text `create_booking_hold_tx` (0179) takes, so this sweep
      -- and an edge hold for the same dog SERIALIZE: whichever runs second sees the first's committed
      -- row in the clash guard below. Transaction-scoped and held to COMMIT on purpose — releasing it
      -- early (a session lock unlocked in an exception arm, 0117's job-lock shape) would let an edge
      -- hold take the lock, read a snapshot with this sweep's row still uncommitted, and pass: the
      -- exact race this lock exists to close. Taken only for a series with something due (after the
      -- 72h gate), before any read of this dog's bookings. The edge takes key-lock then dog-lock; this
      -- sweep takes only dog locks, in `order by dog_id` sequence, so no lock cycle is possible.
      perform pg_advisory_xact_lock(hashtextextended('booking_hold_dog:' || s.dog_id::text, 0));

      -- dedup: 같은 시리즈, 같은 KST 날짜에 이미 예약 존재 (첫 예약 포함 — series_id 링크가 가드)
      if exists (
        select 1 from bookings
        where series_id = s.id
          and (scheduled_at at time zone 'Asia/Seoul')::date = (v_sched at time zone 'Asia/Seoul')::date
      ) then continue; end if;

      v_start := v_sched;
      v_end := v_sched + make_interval(mins => (s.km * 8 + 25)::int); -- 실소요 공식 (hold와 동일)

      -- 같은 강아지 라이브 예약 겹침 가드 (create-booking-hold와 동일 로직의 SQL판)
      select exists (
        select 1 from bookings c
        where c.dog_id = s.dog_id
          and c.status in ('matching','runner_pending','confirmed','runner_enroute','picked_up','active')
          and c.scheduled_at < v_end
          and c.scheduled_at + make_interval(mins => (c.km * 8 + 25)::int) > v_start
      ) into v_clash;
      if v_clash then continue; end if;

      -- 같은 러너 우선 — 시리즈 최근 확정+ 러너, 가용성 재검증 (감사 ① 교훈: 지명은 검증 후)
      v_runner := null;
      select b2.runner_id into v_runner from bookings b2
      where b2.series_id = s.id and b2.runner_id is not null
        and b2.status in ('confirmed','runner_enroute','picked_up','active','completed')
      order by b2.scheduled_at desc limit 1;
      if v_runner is not null then
        begin
          select is_slot_available(v_runner, v_start, v_end) into v_avail;
        exception when others then
          v_avail := false;
        end;
        if not coalesce(v_avail, false) then v_runner := null; end if;
      end if;

      -- ⓑ/ⓒ [0080 §0-ter #3] money gates — the last thing before the insert.
      v_block := null;
      if owner_has_unsettled_charge(s.owner_id) then
        v_block := 'debt';
      elsif v_live and not exists (select 1 from billing_keys bk where bk.profile_id = s.owner_id) then
        v_block := 'no_card';
      end if;
      if v_block is not null then
        -- [0232 §C] the charges that make this owner a debtor NOW. Written onto the notice's
        -- episode row below, and compared against every earlier notice's row in the guard.
        v_debt := _unsettled_charge_ids(s.owner_id);
        -- ⓓ once per owner per sweep (v_notified) — [0224 §H] AND at most once per 24 h per owner
        -- per EPISODE: an earlier pause notice counts only while no booking of this owner's series
        -- has been created since it (the owner fixed it, it resumed, it broke again ⇒ tell them).
        -- [0226 §C] …AND, for a DEBT block, only while a charge that already existed when that notice
        -- was written is STILL unsettled. A generated booking proves an unblocked tick; it is not the
        -- only way an episode ends — paid and re-incurred between two hourly ticks leaves no booking
        -- (codex s3, measured by 257 `0226-C2`). A `failed` charge stays `failed` through every retry
        -- until it is paid, so an old charge still unpaid means the debt never ended. A card-less
        -- block has no debt to witness and keeps 0224's rule (`0226-C4`).
        if not (s.owner_id = any(v_notified))
           and not exists (
             select 1 from notifications nt
              where nt.profile_id = s.owner_id
                and nt.title = '반복 예약 일시 중지'
                and nt.created_at > now() - interval '24 hours'
                and not exists (select 1 from bookings gb
                                  join recurring_series gs on gs.id = gb.series_id
                                 where gs.owner_id = s.owner_id
                                   and gb.created_at > nt.created_at)
                -- [0232 §C] …for a DEBT block, only while a charge that WAS DEBT when that notice
                -- went out (its episode row, extended by every tick that saw the debt continue) is
                -- STILL debt. 0226 asked 「existed then, debt now」 — so a charge that was a fresh
                -- pending at the notice and became debt after the old debt was paid suppressed the
                -- new pause (codex s2). A notice with no episode row predates 0232 and keeps
                -- 0226's witness (it ages out of the 24 h window by itself).
                and (v_block is distinct from 'debt'
                     or case when exists (select 1 from recurring_pause_notices pn
                                           where pn.notice_id = nt.id)
                             then exists (select 1 from recurring_pause_notices pn
                                           where pn.notice_id = nt.id
                                             and pn.debt_payment_ids && v_debt)
                             else _unsettled_charge_through(s.owner_id, nt.created_at) end)) then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (s.owner_id, 'booking', '반복 예약 일시 중지',
                  '반복 예약이 결제 문제로 쉬어가요 — 결제 문제를 해결하면 다시 시작돼요', null)
          returning id into v_nid;
          -- [0232 §C] the episode this notice announced: which block, and — for debt — exactly
          -- which charges were debt when it went out.
          insert into recurring_pause_notices (notice_id, series_id, reason, debt_payment_ids)
          values (v_nid, s.id, v_block, coalesce(v_debt, '{}'));
          v_notified := v_notified || s.owner_id;
        end if;
        -- [0232 §C] CONTINUITY, observed. A tick that finds the owner still in debt adds today's
        -- debt charges to every live notice whose charges are still debt — the episode did not
        -- end, it gained a charge. Without this, paying the ORIGINAL charge while a later one is
        -- still unpaid would read as a new episode and re-tell a pause that never lifted.
        if v_block = 'debt' and cardinality(v_debt) > 0 then
          update recurring_pause_notices pn
             set debt_payment_ids = array(select distinct x from unnest(pn.debt_payment_ids || v_debt) x order by x)
           where pn.debt_payment_ids && v_debt
             and not (pn.debt_payment_ids @> v_debt)
             and pn.notice_id in (select nt.id from notifications nt
                                   where nt.profile_id = s.owner_id
                                     and nt.title = '반복 예약 일시 중지'
                                     and nt.created_at > now() - interval '24 hours');
        end if;
        continue;
      end if;

      -- ⓔ [0111] the series row is a snapshot, and a snapshot can go stale or (before this
      -- migration) be FORGED. Ownership is re-asked at copy time, not trusted from write time.
      -- A silent `continue` would make a skipped series indistinguishable from a series with
      -- nothing due, so say so in the log first — this warning is the ONLY signal that the second
      -- belt fired at all. `continue`, never `raise`: see this file's §3 header.
      if not exists (select 1 from dogs d where d.id = s.dog_id and d.owner_id = s.owner_id)
         or (s.address_id is not null
             and not exists (select 1 from addresses a where a.id = s.address_id and a.owner_id = s.owner_id))
      then
        raise warning 'recurring_series % skipped: dog/address not owned by series owner', s.id;
        continue;
      end if;

      -- [0232 §B] THE ROUTE GATE — create-booking-hold/handler.ts refuses a suspended or retired
      -- course (「이 코스는 지금 예약할 수 없어요」), and this generator copied `s.route_id` without
      -- ever reading it, so an operator's suspension stopped new holds and not the weekly copy.
      -- Nothing is minted; the owner is told once per series per 24 h per episode (0226's
      -- recurring-pause shape: an earlier notice stops counting once this series produced a
      -- booking after it — the course came back and went away again ⇒ tell them again).
      if s.route_id is not null
         and exists (select 1 from routes rt
                      where rt.id = s.route_id and rt.status in ('suspended', 'retired')) then
        if not exists (
             select 1 from recurring_pause_notices pn
               join notifications nt on nt.id = pn.notice_id
              where pn.series_id = s.id
                and pn.reason = 'route'
                and nt.created_at > now() - interval '24 hours'
                and not exists (select 1 from bookings gb
                                 where gb.series_id = s.id
                                   and gb.created_at > nt.created_at)) then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (s.owner_id, 'booking', '반복 예약 코스 점검 중',
                  '반복 예약 코스가 점검 중이라 이번 주 러닝을 만들지 않았어요 — 다른 코스로 바꿔 예약해주세요', null)
          returning id into v_nid;
          insert into recurring_pause_notices (notice_id, series_id, reason)
          values (v_nid, s.id, 'route');
        end if;
        continue;
      end if;

      insert into bookings
        (owner_id, dog_id, runner_id, route_id, address_id, series_id, status, scheduled_at,
         km, pace_label, addons, base_fare, distance_fare, addon_fare, total_price, min_fare)
      values
        (s.owner_id, s.dog_id, v_runner, s.route_id, s.address_id, s.id,
         (case when v_runner is null then 'matching' else 'runner_pending' end)::booking_status,
         v_sched, s.km, s.pace_label, s.addons,
         s.base_fare, s.distance_fare, s.addon_fare, s.total_price, s.min_fare)
      returning id into v_bid;

      insert into notifications (profile_id, kind, title, body, ref_id)
      values (s.owner_id, 'booking', '반복 러닝 예약 생성',
              to_char(v_sched at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI')
              || ' 러닝이 자동 예약됐어요'
              || case when v_runner is null then ' — 러너를 찾는 중이에요' else '' end,
              v_bid);
      if v_runner is not null then
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (v_runner, 'booking', '지명 러닝 요청',
                '반복 예약 보호자가 회원님을 지명했어요 — 요청 탭에서 응답해주세요', v_bid);
      end if;

      n := n + 1;
    exception when others then
      -- [0227] this series' writes are already rolled back; say so, record it, move to the next.
      -- Its dog lock, if it was taken inside this block, is released with the block — safe, because
      -- nothing it guarded was written (0180's race needs this sweep's row to EXIST). A lock an
      -- earlier series of the same dog took belongs to the enclosing transaction and stays to commit.
      v_fail_state := sqlstate;
      v_fail_msg := sqlerrm;
      raise warning 'generate_recurring_bookings: recurring_series % failed (% %) — nothing of it was written this tick; retried next tick',
        s.id, v_fail_state, v_fail_msg;
      -- The record is its OWN subtransaction: a raise inside a handler is not caught by that handler,
      -- so a failing record write would abort the very tick this block exists to save (`0227-V2`).
      begin
        insert into recurring_generation_failures as f (series_id, error_code, error_message)
        values (s.id, v_fail_state, left(coalesce(v_fail_msg, ''), 500))
        on conflict (series_id) do update
          set error_code     = excluded.error_code,
              error_message  = excluded.error_message,
              attempts       = f.attempts + 1,
              last_failed_at = now();
      exception when others then
        raise warning 'generate_recurring_bookings: recurring_series % — its failure record could not be written (% %); the warning above is the only trace',
          s.id, sqlstate, sqlerrm;
      end;
    end;
  end loop;
  return n;
end $$;

-- 0227's ACL, restated verbatim — never rely on grant preservation (0116:636; check-definer-acl).
revoke execute on function generate_recurring_bookings() from public, anon, authenticated;

comment on function generate_recurring_bookings is
  '0080 §H (was 0026): 반복 예약 자동 생성 크론 — 72h 창, 같은 러너 우선(가용성 재검증), 겹침 가드
+ [0080 §0-ter #3] 결제 게이트 둘 + [0111] 복사 시점 소유권 재확인 + [0180] 강아지별 xact 락 —
+ [0224 §H] the pause notice (「반복 예약 일시 중지」) is sent at most once per 24 h per owner per episode
+ [0226 §C] and an episode ends when the series produces a booking again OR — for a debt block — when
every charge that existed at the last notice has been paid (the witness is _unsettled_charge_through).
Title, body and NULL ref unchanged. 255 0224-C1 and 257 0226-C2/C3/C4 pin it.
+ [0227] each series runs in its own subtransaction: a series whose write raises writes nothing that
tick, raises a WARNING naming it and is recorded in recurring_generation_failures, is retried next
tick, and touches no other series. 258 0227-R1/R2/R3/V1/V2/G1 pin it.
+ [0232] a debt pause''s episode is RECORDED (recurring_pause_notices: the charges that were debt when
the notice went out, extended while the debt continues) and a notice counts only while one of them
is still debt — 0226''s witness remains for notices older than 0232. And a series on a suspended or
retired course mints nothing and tells its owner 「반복 예약 코스 점검 중」 once per series per 24 h per
episode. 263 0232-B1…B4/D1…D3 pin it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — apply-time SHAPE only (behaviour is suite 263's — 0131-G4's lesson). Source arms read
-- COMMENT-STRIPPED prosrc: this file explains every predicate at length inside the bodies.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_bad text := '';
  fn text;
  v_src text;
  v_role text;
  v_priv text;
begin
  foreach fn in array array['sweep_cancel_money_gaps()', 'generate_recurring_bookings()',
                            '_unsettled_charge_ids(uuid)'] loop
    if to_regprocedure('public.' || fn) is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure('public.' || fn)
                    and p.prosecdef and 'search_path=public, pg_temp' = any(coalesce(p.proconfig, '{}')))
      then v_bad := v_bad || ' ' || fn || ': not a definer with the in-body search_path;'; end if;
    if has_function_privilege('anon', to_regprocedure('public.' || fn), 'execute')
       or has_function_privilege('authenticated', to_regprocedure('public.' || fn), 'execute')
      then v_bad := v_bad || ' ' || fn || ': a client role can execute (server-only);'; end if;
  end loop;

  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.oid = to_regprocedure('public.sweep_cancel_money_gaps()');
  if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(sweep_cancel_money_gaps);';
  else
    if (v_src like '%and b.updated_at >= (select f.payments_live_since from ops_flags f)))%') is not true
      then v_bad := v_bad || ' sweep: the payments arm lost its mint-gate conjuncts;'; end if;
    if (v_src like '%if v_did then n := n + 1; end if;%') is not true
      then v_bad := v_bad || ' sweep: n is counted unconditionally;'; end if;
    if (v_src like '%and r.comp_missing%') is not true
      then v_bad := v_bad || ' sweep: the runner notice is not guarded by the comp branch;'; end if;
  end if;

  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.oid = to_regprocedure('public.generate_recurring_bookings()');
  if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(generate_recurring_bookings);';
  else
    if (v_src like '%rt.status in (''suspended'', ''retired'')%') is not true
      then v_bad := v_bad || ' generator: no route-status gate;'; end if;
    if (position('rt.status in' in v_src) < position('insert into bookings' in v_src)) is not true
      then v_bad := v_bad || ' generator: the route gate is not before the booking insert;'; end if;
    -- the DEDUPE's conjunct, closing paren included: the continuity UPDATE's `where` carries the same
    -- operator and a bare match would be satisfied by it alone (measured: battery M10)
    if (v_src like '%and pn.debt_payment_ids && v_debt)%') is not true
      then v_bad := v_bad || ' generator: the debt dedupe does not read the episode row;'; end if;
    if (v_src like '%insert into recurring_generation_failures%') is not true
      then v_bad := v_bad || ' generator: 0227''s failure record is gone;'; end if;
  end if;

  if to_regclass('public.recurring_pause_notices') is null then
    v_bad := v_bad || ' NO-TABLE(recurring_pause_notices);';
  else
    if (select c.relrowsecurity from pg_class c where c.oid = 'public.recurring_pause_notices'::regclass) is not true
      then v_bad := v_bad || ' recurring_pause_notices: RLS off;'; end if;
    foreach v_role in array array['anon', 'authenticated'] loop
      foreach v_priv in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
        if has_table_privilege(v_role, 'public.recurring_pause_notices', v_priv)
          then v_bad := v_bad || ' recurring_pause_notices: ' || v_role || ' holds ' || v_priv || ';'; end if;
      end loop;
    end loop;
  end if;
  if v_bad <> '' then raise exception '0232 VERIFY failed:%', v_bad; end if;
  raise notice '0232 VERIFY ok — three server-only definers with the new predicates in place; the episode table is sealed';
end $$;
