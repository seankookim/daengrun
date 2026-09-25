-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0227 — one recurring series' fault costs that series, not the hourly tick
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 258_recurring_row_isolation_suite.sql (tag `rri`) — 0227-R1 · R2 · R3 · V1 · G1 · S1
-- Deploy: `supabase db push` only. No edge function, no cron change, no client change, no flag.
--
-- ═══ §0a WHAT IS WRONG — the Codex s1 shape, in the recurring generator ═══════════════════════
-- Codex s1 (docs/reviews/2026-09-25-wave3-codex-verdicts.md) found a sweep whose per-row writes had
-- no handler under its own 2 s `lock_timeout`; 0226 fixed that sweep and named the SAME shape here
-- (0226 §0d ③, and its REGISTRY row 「NAMED, NOT FIXED ③」). `generate_recurring_bookings` did every
-- series' work — the booking insert, 「반복 러닝 예약 생성」, 「지명 러닝 요청」, the pause notice — in ONE
-- `for` loop with no per-series handler. So one series whose write raised raised out of the whole
-- function. REPRODUCED on 0226's body (258, run before this file existed; harness DB, the tick
-- inside a sub-block): three due series A < B < C in the loop's own order, a 55P03 planted on B's
-- booking insert →
--   · the call RAISED `55P03`;
--   · A — minted BEFORE the fault in the same tick — had its booking and notice ROLLED BACK;
--   · C — after it — was never reached;
--   · the debt-blocked and card-less owners beside them lost their pause notices (0 of 1 each);
--   · a second call with the fault still there RAISED again.
-- ⚠ ATTACK INACTION: what resolves it? Nothing. The loop runs `order by dog_id, id`, so the next
-- tick meets the same series at the same place and dies the same way; a row held past 2 s by a stuck
-- session, or any row-shaped fault that does not go away on its own, starves EVERY owner's recurring
-- bookings for as long as it lasts, and the cron's only trace was a failed run in
-- `cron.job_run_details` that nobody is paged for.
-- ⚠ This is not a new idea in this file's history — it is an UNRULED one being ruled. 0127 restored
-- the loop without isolation and said so out loud: 「Generic per-row isolation for OTHER error classes
-- is a real question and an UNRULED one — it belongs to its own slice with its own pin」. This is
-- that slice; 258 is that pin. The house shape it follows: 0080 §G / 0116 §C (「one poisoned row fails
-- ITS OWN ROW, never the batch」), 0117's late_booking_sweep, 0210 §E's nested leg, 0226 §A.
--
-- ═══ §0b WHAT THIS FILE DOES ═════════════════════════════════════════════════════════════════
--   §A `recurring_generation_failures` — a NEW, server-only table: one row per series that has ever
--      failed a tick, carrying the last SQLSTATE and message, the attempt count and first/last
--      failure times. (§0c says why a new table and not an existing one.)
--   §B `generate_recurring_bookings` — 0226 §C's body (== the harness catalog's prosrc, md5
--      `da4bb3cd…`/8231, measured), built BY SCRIPT with exactly three insertions and nothing else:
--        ① two `declare` lines (`v_fail_state`, `v_fail_msg`);
--        ② `begin` (and its comment) as the first statement of the loop body;
--        ③ the handler before `end loop`: a WARNING naming the series, SQLSTATE and message, then an
--           upsert into §A inside its OWN nested block (a raise inside a handler is not caught by that
--           handler — without the nesting a failing record write would abort the tick this exists to
--           save; 0210 §E's reason; 258 `0227-V2`).
--      Every line in between is 0226's, byte for byte, one indent deeper — the build script removes
--      the three insertions, dedents the rest by two spaces and asserts equality with 0226's body.
--      The money gates (`owner_has_unsettled_charge`, the card switch), 0226's debt-episode dedupe,
--      the dog lock, `lock_timeout`, `order by dog_id, id`, the ownership belt, every insert and every
--      string are therefore UNCHANGED. WHAT it mints and whom it charges is not touched; only how far
--      one series' failure reaches.
--   What a failed series now costs: ITS OWN writes for that tick (all of them — the booking, its
--   「반복 러닝 예약 생성」 and 「지명 러닝 요청」, or its pause notice — roll back together, so a booking can
--   never exist without the notice that announces it: 258 `0227-R3`), a WARNING in the Postgres log, a
--   row in §A, and a retry next tick. No other series is touched (`0227-R1`), a second failing tick
--   is contained the same way (`0227-R2`), and the money gates on a neighbour are unmoved
--   (`0227-G1`).
--
-- ═══ §0c WHY A NEW TABLE — and why the WARNING alone is not enough ═══════════════════════════
--   Containment REMOVES the only durable signal this failure used to have: the tick itself failed, so
--   pg_cron kept a failed run in `cron.job_run_details` (0180 §A says so). After this file the tick
--   succeeds, and a series that fails every hour forever would be visible only as a WARNING line in
--   the Postgres log — the 「silent catch → happy UI」 shape the honesty laws forbid, one layer down.
--   So a failed series must land somewhere durable. What was checked, and why each did not fit:
--     · `recurring_series` has NO per-series failure column; adding one would put an internal error
--       string on a row its OWNER can read (0111's 「series owner read」 policy) and would need a
--       success-path write to clear it — a new statement on the minting path, which this slice
--       refuses to add.
--     · `club_fee_mint_failures` (0118) is the closest shape — a durable queue for a failed MINT —
--       but it is keyed by `booking_id` with a `fee_kind` CHECK; a recurring failure has no booking.
--     · `booking_faults` (0117) is an immutable record of a party's fault for a booking — wrong
--       subject entirely.
--     · the ops bell (`ops_recipients_for` + `notifications`) is how sweeps PAGE people; paging for
--       this means a new event class, a new ops title and client routing for it — a product decision
--       about who is told, not a containment. Named in §0d, not made.
--     · no generic ops journal exists that sweeps write to (checked: 0186/0198/0213's journals are
--       money-read and payout journals).
--   So §A is new, and deliberately minimal: server-only (RLS on, zero policies, every client
--   privilege revoked — the harness shim mirrors Supabase's default grants, so 258 `0227-S1` sees a
--   revoke go missing), written ONLY on the failure path, never read by the generator, bounded (one
--   row per series, upserted), and cascaded away with its series.
--   ⚠ HOW TO READ IT. The row is the series' LAST failure and a lifetime count, not a current state:
--   nothing clears it when the series recovers (clearing would be a write on the minting path). A
--   series is failing NOW when `last_failed_at` is from the latest tick (the cron runs at :07 hourly);
--   an older `last_failed_at` beside a newer booking of that series means it recovered.
--   ⚠ `error_message` is `SQLERRM` capped at 500 characters — the primary message only, never DETAIL
--   (where Postgres puts row values). Server-only, so no party ever reads it.
--   ⚠ The WARNING is a WARNING and not a NOTICE on purpose (0111's belt and 0117's sweep do the same):
--   with Postgres's default `log_min_messages = warning`, a NOTICE raised in a pg_cron tick reaches
--   no log at all. (Production's setting was NOT read from here — no supabase CLI in this slice.)
--
-- ═══ §0d WHAT THIS FILE DELIBERATELY DOES NOT DO ═════════════════════════════════════════════
--   · It pages nobody and tells the OWNER nothing. A series that fails every tick now costs its owner
--     their recurring bookings silently (today it costs EVERY owner theirs, just as silently). Whether
--     an operator is paged (a new ops class) or the owner is told (new in-app copy) is a product
--     decision — named in the REGISTRY row for Sean, not made here.
--   · No reader ships: §A is read by an operator with SQL. An ops-desk read is a later slice's.
--   · The `lock_timeout` is unchanged, and so is its meaning for ONE series (a wait past 2 s raises).
--     What changed is its reach. Two costs of that, stated rather than discovered later:
--       ① a tick that meets k contended dogs now runs up to ~2 s × k longer instead of dying at the
--         first — and every dog lock it already took is held to commit for that long (0180's
--         「held to commit」 law, unchanged). An edge hold for such a dog waits the rest of the tick.
--       ② two OVERLAPPING ticks (pg_cron itself never overlaps a job with itself; a manual call beside
--         the cron can) no longer make the follower die at the leader's first dog: each dog is
--         serialized by its lock exactly as before (no double booking — the follower's dedupe reads
--         the leader's committed row), and each dog the follower cannot lock within 2 s is recorded in
--         §A as a 55P03 failure and retried next tick. §A can therefore carry a 55P03 row that means
--         「another tick had this dog」, not 「this series is broken」.
--   · Dog locks under a rolled-back series (measured by hand in the lab, not pinned — 258's header
--     says why): a lock taken INSIDE a failed series' block is released with the block; a lock the
--     enclosing transaction already held (an earlier series of the same dog) stays held to commit.
--     Both are PostgreSQL resource-owner semantics. The first is safe because nothing of that series
--     was written, so there is no uncommitted row for 0180's race to slip beside.
--   · No `pg_advisory_unlock` anywhere (211 `0180-A1` pins its absence).
--
-- ═══ §0d-bis SHIPPED PINS THAT MOVE, AND WHY ═════════════════════════════════════════════════
--   · `161 P4` — the generator's prosrc/comment digests, re-read from the catalog after this file
--     applied, as P4's own note asks (the body moved by the three insertions above and one indent;
--     the comment gained one `[0227]` stanza).
--
-- ═══ §0e WHOSE OBJECTS THIS BUILDS ON (REGISTRY's silent-collision table) ═════════════════════
--   RE-DECLARES `generate_recurring_bookings()` ←0226 §C (built by script, every other line asserted
--   identical after a two-space dedent). CREATES table `recurring_generation_failures`. ACL restated.
--   ⚠ A later slice re-declaring `generate_recurring_bookings` must keep the per-series block and its
--   nested record write (258 `0227-R1`/`R2`/`R3`/`V1`/`V2`) — a loop-wide handler is NOT equivalent (it
--   rolls back every series before the fault and skips every series after it; battery M2), and neither
--   is a handler narrowed to one SQLSTATE (the fault that is not a lock wait escapes it; battery M4).

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A recurring_generation_failures — the durable trace of a series that failed a tick
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
create table if not exists recurring_generation_failures (
  series_id       uuid primary key references recurring_series(id) on delete cascade,
  error_code      text not null,                                  -- SQLSTATE of the LAST failure
  error_message   text not null,                                  -- its SQLERRM, capped at 500
  attempts        int  not null default 1 check (attempts > 0),   -- failed ticks, lifetime
  first_failed_at timestamptz not null default now(),
  last_failed_at  timestamptz not null default now()
);
alter table recurring_generation_failures enable row level security;
revoke all on table recurring_generation_failures from public, anon, authenticated;
grant select, insert, update, delete on table recurring_generation_failures to service_role;

comment on table recurring_generation_failures is
  '0227: one row per recurring series that has failed a generate_recurring_bookings tick — the last
SQLSTATE and message (SQLERRM, 500 chars, never DETAIL), a lifetime attempt count, first and last
failure time. Written ONLY by the generator''s per-series handler; never read by it; never cleared on
recovery (that would be a write on the minting path). Failing NOW = last_failed_at from the latest
hourly tick. A 55P03 row can also mean an overlapping tick held that dog (0227 §0d ②). Server-only:
RLS on, no policies, no client privilege. 258 0227-V1/V2/S1 pin it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B generate_recurring_bookings — each series in its own subtransaction
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0226 §C's body, built BY SCRIPT (§0b): three insertions, everything else 0226's one indent deeper.
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
                and (v_block is distinct from 'debt'
                     or _unsettled_charge_through(s.owner_id, nt.created_at))) then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (s.owner_id, 'booking', '반복 예약 일시 중지',
                  '반복 예약이 결제 문제로 쉬어가요 — 결제 문제를 해결하면 다시 시작돼요', null);
          v_notified := v_notified || s.owner_id;
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

-- 0226:928 verbatim — never rely on grant preservation (0116:636; check-definer-acl).
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
tick, and touches no other series. 258 0227-R1/R2/R3/V1/V2/G1 pin it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — apply-time SHAPE only (behaviour is suite 258's — 0131-G4's lesson)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_bad text := '';
  v_src text;
  v_role text;
  v_priv text;
begin
  if to_regprocedure('public.generate_recurring_bookings()') is null then
    v_bad := v_bad || ' NO-FUNCTION(generate_recurring_bookings)';
  else
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure('public.generate_recurring_bookings()')
                    and p.prosecdef and 'search_path=public, pg_temp' = any(coalesce(p.proconfig, '{}')))
      then v_bad := v_bad || ' generate_recurring_bookings: not a definer with the in-body search_path;'; end if;
    if has_function_privilege('anon', 'public.generate_recurring_bookings()', 'execute')
       or has_function_privilege('authenticated', 'public.generate_recurring_bookings()', 'execute')
      then v_bad := v_bad || ' generate_recurring_bookings: a client role can execute (server-only);'; end if;
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.oid = to_regprocedure('public.generate_recurring_bookings()');
    if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(generate_recurring_bookings);'; end if;
  end if;
  if to_regclass('public.recurring_generation_failures') is null then
    v_bad := v_bad || ' NO-TABLE(recurring_generation_failures);';
  else
    if (select c.relrowsecurity from pg_class c where c.oid = 'public.recurring_generation_failures'::regclass) is not true
      then v_bad := v_bad || ' recurring_generation_failures: RLS off;'; end if;
    foreach v_role in array array['anon', 'authenticated'] loop
      foreach v_priv in array array['select', 'insert', 'update', 'delete', 'truncate', 'references', 'trigger'] loop
        if has_table_privilege(v_role, 'public.recurring_generation_failures', v_priv)
          then v_bad := v_bad || ' recurring_generation_failures: ' || v_role || ' holds ' || v_priv || ';'; end if;
      end loop;
    end loop;
  end if;
  if v_bad <> '' then raise exception '0227 VERIFY failed:%', v_bad; end if;
  raise notice '0227 VERIFY ok — the generator is a server-only definer with its in-body search_path; the failure record is sealed';
end $$;
