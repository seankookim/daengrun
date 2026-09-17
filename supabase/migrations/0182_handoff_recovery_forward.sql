-- ═══ 0182: handoff recovery, correct-forward — cycle identity · lock-then-look · the deadline · bigint ═══
--
-- Codex's adversarial pass on 0180+0181 (docs/reviews/2026-09-18-migrations-0180-0181-codex-verdict.md,
-- REJECT/5, static) — four findings re-measured here and fixed forward, never by editing 0180/0181:
--   #1 HIGH  a previous pairing's ask suppresses this pairing's re-send · #2 HIGH no deadline after
--   the one re-send · #3 MED send-after-action (no row lock, no re-check) · #4 MED an int4 overflow
--   in 0180's balance check aborts the whole reconciliation. #5 (club recipients routed to the 1:1
--   meetup) is the client's: `hig/club-handoff-route` (1081a33) resolves `bookings.club_session_id`
--   from the booking ref and lands both club parties on `club/session/[sid]`. ⚠ That is exactly why
--   the sweep's club re-send keeps the EDGE'S SHAPE — `ref_id` = the booking, title in the family —
--   and is NOT re-shaped with a session ref: the client resolver keys on the booking id, so a
--   session-ref'd row would break the route just landed and diverge from the edge's own club ask.
--   213 D6 pins that shape.
--
-- ═══ §A the cycle boundary (#1) ═══
-- `bookings.handoff_cycle_at` — stamped by the DATABASE (trigger `_handoff_cycle`, before update)
-- whenever `runner_id` changes or a handoff stamp is reset, i.e. whenever the pair that must both
-- confirm is not the pair that was confirming. Arm ⓒ's ask match now requires the ask row to be at
-- or after `greatest(handoff_cycle_at, stamp - ASK_SKEW)`: the skew rule keeps tolerating edge-vs-
-- database clock drift, and the cycle rule stops an EARLIER pairing's ask to the same recipient
-- (owner asked, re-match, new runner confirms, that ask lost) from answering this one. Both
-- bounds are database time or within the skew; neither trusts the edge's clock for the boundary.
-- ⚠ TWO RESIDUES SURVIVE THE BOUND, named here with their rescue (cold review 0182 #5, measured):
--   (a) a DELAYED old-pairing ask — the edge stamps and notifies in two PostgREST calls
--       (index.ts:350,363); a re-match committing between them dates the old ask after the
--       boundary, addressed to the same owner, and it suppresses the new pairing's re-send;
--   (b) a row re-matched BEFORE 0182 (no backfill: `handoff_cycle_at` NULL) keeps 0181's skew-only
--       rule, so an earlier ask inside the skew still masks — until that row's next cycle.
--   In both, arm ⓓ tells both parties at 30 minutes. That bound is why no backfill is warranted:
--   the residual set is 「re-matched before apply and still one-sided」, and it is rescued.
-- `handoff_escalated_at` — arm ⓓ's one-shot record, reset by the same trigger. Both columns are
-- SERVER-OWNED: the trigger DERIVES the boundary (no statement can move it), and 0058's
-- `_guard_booking_cols` — which fires first and refuses every direct client write to `bookings`
-- (measured: `booking_protected_columns`, 「클라이언트 직접 쓰기 전면 차단」) — keeps a client off the
-- record; no client path writes either. NULL on rows that never re-matched since 0182 = 「no
-- boundary known」 → the skew rule alone, 0181's behaviour.
--
-- ═══ §B `sweep_run_end_recovery` — 0181's body (arms ⓐ/ⓑ, the job lock, ⓒ's candidate query byte-identical) + three marked changes ═══
--   · ⓒ's not-exists gains the cycle bound (#1).
--   · ⓒ's loop body is rewritten: it locks each candidate (`for update skip locked`) and re-evaluates stamps · runner · status ·
--     age · the ask on the LOCKED row before inserting, with the lock held through the insert (#3).
--     A row a transition-booking write holds is skipped, never waited on: its outcome decides the
--     next tick. `90_race_check.sh` RL2 measures it with two processes.
--   · ⓓ the deadline (#2): ESCALATE_AFTER = 30 min one-sided ⇒ both parties told once, the ops
--     roster told once (event class `handoff_unanswered`, redacted body, 0155's shape), the column
--     stamped. Club and marketplace alike; reads no flag; moves no status — a stuck pickup handoff's
--     fate is a product decision. Bounded and one-shot BY THE COLUMN, per cycle.
--     ⚠ The parties' title `인계 확인이 멈춰 있어요` is written by this sweep ALONE, so the client
--     must know it: `app/src/lib/notification-route.ts` carries it as ESCALATION_TITLE in
--     CLUB_PROBE_TITLES — a club party taps it into `club/session/[sid]`, a 1:1 party into the
--     report / calendar (never a CTA: it is deliberately NOT in HANDOFF_TITLES, which would route
--     the owner to /owner/meetup). `app/test/notification-route.test.cjs` reads THIS file for the
--     constant, so the two cannot drift (cold review 0182 #4; carried in this slice).
--     ⚠ After ⓓ, nothing further reaches a still-one-sided row: `late_booking_sweep` is flag-gated
--     and marketplace-only, so a stuck CLUB handoff stays `confirmed` with the record set until a
--     human acts. Named as the product decision it is (cold review 0182 #11).
--     ⚠ The ops half is a no-op until someone subscribes to `handoff_unanswered` — 0155 noted an
--     empty roster in production; the obligation is the ops roster owner's, and the zero is in
--     the sweep's notice. Until then the escalation's real effect is the two party rows.
--   · ⓒ and ⓓ each serve at most `c_batch` (50) rows a tick and the sweep sets `lock_timeout` 2 s:
--     every row lock is held to commit and a counterparty's confirm waits behind it, so the number
--     held is bounded and a wait in arm ⓑ cannot stall the tick (#6).
--   The deny-list (the fourteen statuses in which no pickup handoff is underway) is spelled twice:
--   literally in ⓒ's candidate query (212 C8 anchors on that literal) and as the constant `c_dead`
--   everything else uses; VERIFY and 213 D7 assert the two are identical, so neither can drift.
--
-- ═══ §C `reconcile_billing_key_dispatch_ticks` — 0180's body verbatim + two marked changes ═══
--   · the balance sum's first operand is bigint (#4): claimed=0, revoked=2147483647, failed=1 passes
--     every per-counter guard and overflowed the int4 sum, aborting the whole call (measured).
--   · a per-tick exception boundary: an answer the block cannot read is marked `failed` with the
--     reason and the siblings, the stale sweep and the prune still run (the same class as arm ⓒ's
--     handler; no reachable raise is known today after the cast — the arm is for the next one).
--     A TRANSIENT cause (SQLSTATE classes 40 · 55 · 57 · 08) is re-raised instead — the tick
--     stays `sent` and the next tick retries, 0180's self-healing kept (cold review 0182 #3).
--     ④-law: `failed` gains the member 「unreadable by the reconciler」; its readers (`failed_24h`
--     in 0150/0155/0166's health views, 181, the prune keep-list) count it, none break.
--
-- ⚠ `create or replace` of definers FIRST DEFINED IN 0083 and 0150 — both ACLs restated below.
--   Suites 119 · 132 · 133 · 163 · 208 (the sweep's other arms, the cron row), 181 · 211 (the
--   reconciler's verdicts and the split) and 212 (arm ⓒ) stay green — 212 C8's handler count moves
--   from 「= 2」 to 「≥ 2」 because ⓓ adds a third (the suite-update law; 213 D7 pins the exact 3).
-- ⚠ The ops class `handoff_unanswered` is appended to `ops_recipients`' vocabulary comment (0084's
--   rule: the vocabulary lives in the comment, no check constraint; 0155's append idiom). Nobody
--   is subscribed in the harness or, as of 0155's note, in production — a zero is the honest count
--   and it is in the notice; provisioning belongs to whoever owns the ops roster.
--
-- ═══ MUTATION TABLE — measured, plants `&&`-chained against a COPY, control observed clean ═══
--   In suite 213's header and the REGISTRY row.

-- ═══ §A ═══
alter table bookings add column if not exists handoff_cycle_at     timestamptz;
alter table bookings add column if not exists handoff_escalated_at timestamptz;
comment on column bookings.handoff_cycle_at is
  '0182: when the CURRENT handoff cycle began — stamped by trigger _handoff_cycle (database time) whenever runner_id changes or a handoff confirmation stamp is reset. sweep_run_end_recovery arm ⓒ counts only 「인계 확인 요청」 rows created at or after this as this cycle''s ask. NULL = no re-match/reset since 0182 (the skew rule alone applies). Server-owned: the trigger derives it; a client value never lands.';
comment on column bookings.handoff_escalated_at is
  '0182: when sweep_run_end_recovery arm ⓓ told both parties and the ops roster (handoff_unanswered) that this cycle''s pickup handoff stayed one-sided past 30 minutes. The one-shot record and dedupe key; reset by trigger _handoff_cycle on a new cycle. Server-owned: 0058''s _guard_booking_cols refuses every direct client write to bookings (booking_protected_columns).';

create or replace function _handoff_cycle_tg() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  if new.runner_id is distinct from old.runner_id
     or (old.owner_confirmed_handoff_at  is not null and new.owner_confirmed_handoff_at  is null)
     or (old.runner_confirmed_handoff_at is not null and new.runner_confirmed_handoff_at is null) then
    -- a new pairing, or the same pairing starting over: everything confirmed so far is void
    new.handoff_cycle_at     := now();
    new.handoff_escalated_at := null;
  else
    -- derived, never taken from the statement: NO statement — client or server — moves the
    -- boundary; only the two events above do. (The escalation record needs no arm of its own
    -- here: 0058's `_guard_booking_cols` refuses EVERY direct client write to `bookings`
    -- 「클라이언트 직접 쓰기 전면 차단」 and fires before this trigger by name order — measured; a
    -- refusal arm here would be unreachable code that reads as protection. 213 D2 measures the
    -- refusal as it actually happens, and names its source.)
    new.handoff_cycle_at := old.handoff_cycle_at;
  end if;
  return new;
end $$;
revoke execute on function _handoff_cycle_tg() from public, anon, authenticated;

drop trigger if exists _handoff_cycle on bookings;
create trigger _handoff_cycle before update on bookings
  for each row execute function _handoff_cycle_tg();
comment on function _handoff_cycle_tg is
  '0182: keeps bookings.handoff_cycle_at (database time of the latest runner change or stamp reset — derived, no statement can move it) and clears handoff_escalated_at on a new cycle. Fires before update, after _guard_booking_cols (name order), which is what refuses direct client writes.';

-- ═══ §B ═══
create or replace function sweep_run_end_recovery() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; n int := 0;
  STRAND_AFTER constant interval := interval '2 hours';
  -- A sealed row is RECOVERABLE — the money can still move the moment the pricing path re-drives
  -- it — so its alarm is longer than the stranding deadline and, crucially, moves no state.
  SEAL_ALARM_AFTER constant interval := interval '6 hours';
  -- [0181] arm ⓒ: how long a one-sided handoff may sit with no ask row before the sweep re-sends
  -- the ask, and how far an ask row may PRECEDE the stamp it answers (the edge stamps with its
  -- own clock, the row is stamped by the database's) and still count as that stamp's ask.
  ASK_AFTER constant interval := interval '5 minutes';
  ASK_SKEW  constant interval := interval '10 minutes';
  -- the edge's exact strings (`transition-booking/index.ts`, case confirm_handoff): `push.ts`
  -- routes the runner by EXACT title, and the inbox must show one ask, not two spellings of it.
  c_ask_title constant text := '인계 확인 요청';
  c_ask_body  constant text := '상대방이 인계를 확인했어요 — 확인해주세요';
  -- [0182] arm ⓓ: how long a handoff may stay one-sided — ask delivered or not — before both
  -- parties and the ops roster are told ONCE for this cycle. 30 min: the re-send (arm ⓒ) lands
  -- 5–15 min after the stamp, so the re-sent ask has had at least 15 min to be answered.
  ESCALATE_AFTER constant interval := interval '30 minutes';
  c_esc_title constant text := '인계 확인이 멈춰 있어요';
  c_esc_body  constant text := '인계 확인이 한쪽만 된 채 30분이 지났어요 — 담당자가 확인하고 있어요';
  c_ops_class constant text := 'handoff_unanswered';
  -- [0182] the statuses in which a pickup handoff is NOT underway — the same fourteen arm ⓒ's
  -- candidate query names literally (212 C8 anchors on that literal); this constant is what the
  -- re-checks and arm ⓓ use, and VERIFY / 213 D7 assert the two spellings are identical.
  c_dead constant booking_status[] := array['draft','quoted','payment_hold','matching','runner_pending',
                                            'picked_up','active','completed',
                                            'cancelled_owner','cancelled_runner','expired','no_show',
                                            'incident_review','refund_pending']::booking_status[];
  -- [0182] rows served per tick per arm (ⓒ, ⓓ): every row lock these arms take is held to
  -- commit, and a counterparty's confirm (a plain UPDATE, no NOWAIT) waits behind it — so the
  -- number held is bounded, the arms are idempotent, and the rest wait for the next tick, ten
  -- minutes away (cold review 0182 #6; late_booking_sweep's `limit 5` is the precedent, 0126:61).
  c_batch constant int := 50;
  v_b record; v_cp uuid; v_st timestamptz; v_ops int;
begin
  -- [0181] ONE tick at a time (0117's job-lock idiom; 0177 gave owner-la the same): arm ⓐ's
  -- one-shot alarm and arm ⓒ's re-send are both read-then-write on `notifications`, and two
  -- overlapping ticks would each see no row and each insert (audit M10's class). A TRY-lock, so
  -- a slow predecessor is skipped and never queued; transaction-scoped, so any raise below
  -- releases it with no unlock to forget. `90_race_check.sh` RL measures the skip with two
  -- processes; 212 C8 sees the lock held after the call.
  if not pg_try_advisory_xact_lock(hashtextextended('sweep_run_end_recovery', 0)) then
    raise notice 'sweep_run_end_recovery: another tick holds the job lock — skipped';
    return 0;
  end if;
  -- [0182] the bounded wait (0117 MINOR-14, 0180 §A's value): ⓒ/ⓓ never wait (skip locked), but
  -- arm ⓑ's UPDATE can, and a sweep stalled there holds every row lock ⓒ already took.
  perform set_config('lock_timeout', '2000', true);
  -- ⓐ report every sealed-but-unsettled row. The runner is owed money on a booking whose
  -- settlement died; SQL cannot price it (see the header), so the honest output is a visible
  -- notice per row and a count, not a silent zero.
  for r in
    select b.id, b.owner_id, b.runner_id, b.settlement_ready_at
    from bookings b
    where b.status = 'active'
      and b.club_session_id is null
      and b.settlement_ready_at is not null
  loop
    raise notice 'sweep_run_end_recovery: booking % is sealed but unsettled since % — settlement needs the pricing path (0083 §0f)',
      r.id, r.settlement_ready_at;
    n := n + 1;
    -- …and after SEAL_ALARM_AFTER, a notice in a cron log is not enough: tell both parties, once.
    -- This alarm deliberately does NOT move the status. The row stays `active`, which is the only
    -- state from which `_settle_sealed_run` can still pay the runner — escalating it to
    -- `incident_review` would trade a slow settlement for an impossible one (see the header).
    -- One-shot by construction: a title that exists for this booking is an alarm already raised.
    if r.settlement_ready_at < now() - SEAL_ALARM_AFTER
       and not exists (select 1 from notifications nt
                       where nt.ref_id = r.id and nt.title = '정산을 확인하고 있어요') then
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (r.owner_id, 'booking', '정산을 확인하고 있어요',
              '인계는 확인됐는데 정산이 마무리되지 않았어요 — 담당자가 확인하고 있어요', r.id);
      if r.runner_id is not null then
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (r.runner_id, 'booking', '정산을 확인하고 있어요',
                '인계는 확인됐는데 정산이 마무리되지 않았어요 — 지급은 취소되지 않아요, 담당자가 확인하고 있어요', r.id);
      end if;
    end if;
  end loop;

  -- ⓑ escalate a stranded 귀가 — the booking must never be able to stay active forever. NOTE the
  -- `settlement_ready_at is null` predicate: this arm is for the return NOBODY CONFIRMED, and
  -- only for it. A sealed row is money that can still move and is handled by ⓐ (see the header).
  for r in
    select b.id, b.owner_id, b.runner_id
    from bookings b
    where b.status = 'active'
      and b.club_session_id is null
      and b.run_ended_at is not null
      and b.run_ended_at < now() - STRAND_AFTER
      and b.settlement_ready_at is null
  loop
    begin
      update bookings set status = 'incident_review' where id = r.id and status = 'active';
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (r.owner_id, 'booking', '귀가 확인이 필요해요',
              '러닝은 끝났는데 인계 확인이 없어요 — 담당자가 확인을 도와드릴게요', r.id);
      if r.runner_id is not null then
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (r.runner_id, 'booking', '귀가 확인이 필요해요',
                '인계 확인이 되지 않아 담당자 확인으로 넘어갔어요 — 정산은 확인 뒤에 진행돼요', r.id);
      end if;
      n := n + 1;
    exception when others then
      raise notice 'sweep_run_end_recovery: strand % — %', r.id, sqlerrm;
    end;
  end loop;

  -- ⓒ [0181] THE ASK THAT NEVER ARRIVED — backend audit M2's second half (the attack-INACTION one).
  -- `transition-booking`'s confirm_handoff stamps one side and then asks the OTHER side with a
  -- 「인계 확인 요청」 notification — the only thing in the product that asks. Since M2 a lost
  -- insert is a log line; nothing retried it, and no sweep looked for a handoff that was asked
  -- for and never answered because the ask never existed. This arm does: exactly one stamp set,
  -- the booking still able to reach `picked_up`, a runner to hand to, older than ASK_AFTER, and
  -- NO ask row for the counterparty created at or after that stamp (an earlier cycle's ask —
  -- stamps are reset on re-match, 0047:112 / index.ts:163 — does not count) ⇒ the ask is written
  -- ONCE, counted in the return, and named in a notice. The counterparty is the side that has
  -- NOT stamped: the party who stamped is never asked to confirm their own handoff.
  -- ⚠ STATUS IS A DENY-LIST, NOT AN ALLOW-LIST (the attack-INACTION law). A handoff is underway
  --   in exactly two statuses of 0066's map — `confirmed` and `runner_enroute`, the two from
  --   which `picked_up` is one edge away — and this arm names the OTHER fourteen rather than
  --   those two: before assignment there is no agreed handoff to confirm (a stamp there is a
  --   leftover; re-match resets it), after the pickup or in any end state there is nothing left
  --   to ask. So a status added to the enum lands in the sweep by default — re-sent, the failure
  --   this arm exists to close, and one spurious ask if it was in fact an end state (a wrong
  --   line in an inbox, visible) — and 212 C6 walks the enum so that new status reddens a pin
  --   until someone places it, instead of being decided by omission.
  -- ⚠ NO `club_session_id is null` here, unlike arms ⓐ/ⓑ. 0144:94 scoped THOSE for run-END
  --   reasons (a club run ends by the host's stop, not by `end_run_tx`). The PICKUP ask is the
  --   same edge action for both worlds — `club/session/[sid].tsx:665,708` call confirm_handoff
  --   exactly as `owner/meetup.tsx:252` does — so a club booking's lost ask is the same defect
  --   and is swept here; `runner_id is not null` already excludes an owner-handled club dog,
  --   which has no handoff to confirm.
  for r in
    select b.id, x.counterparty, x.stamped_at
    from bookings b
    -- the counterparty and the stamp are computed ONCE (lateral) and used by both the insert and
    -- the not-exists below — two copies of that `case` would be two places to drift (cold review)
    cross join lateral (
      select case when b.owner_confirmed_handoff_at is not null then b.runner_id else b.owner_id end as counterparty,
             coalesce(b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at) as stamped_at
    ) x
    where (b.owner_confirmed_handoff_at is null) <> (b.runner_confirmed_handoff_at is null)
      and b.runner_id is not null
      and b.status not in ('draft', 'quoted', 'payment_hold', 'matching', 'runner_pending',        -- before assignment: no agreed handoff to confirm
                           'picked_up', 'active', 'completed',                                    -- past the pickup: nothing left to ask
                           'cancelled_owner', 'cancelled_runner', 'expired', 'no_show',          -- ended
                           'incident_review', 'refund_pending')
      and x.stamped_at < now() - ASK_AFTER
      -- ⚠ `nt.profile_id = x.counterparty` is load-bearing and easy to read as redundant: an ask
      --   row addressed to the OTHER party (the previous cycle's, inside the skew — re-match
      --   resets the stamps and leaves the row) must not silence this party's re-send. Measured
      --   by the cold review: without it the owner is NEVER asked in that shape. 212 C9 pins it.
      and not exists (
        select 1 from notifications nt
        where nt.ref_id = b.id
          and nt.title = c_ask_title
          and nt.profile_id = x.counterparty
          -- [0182] …and at or after THIS CYCLE's boundary: `handoff_cycle_at` is stamped by the
          -- database (trigger _handoff_cycle) whenever the runner changes or a stamp is reset, so
          -- an earlier pairing's ask to the same recipient cannot answer this pairing's stamp
          -- (codex 0181 #1). NULL (a row that never re-matched since 0182) falls to the skew rule.
          and nt.created_at >= greatest(coalesce(b.handoff_cycle_at, '-infinity'::timestamptz), x.stamped_at - ASK_SKEW))
    order by b.id
    limit c_batch
  loop
    -- arm ⓑ's shape, for arm ⓑ's reason (0117:1222): one surprising row must not stop the sweep
    -- for every other. Measured — without this sub-block a single failing insert here rolled
    -- arm ⓑ's escalations back with it. Latent today (the runner conjunct and owner_id NOT NULL
    -- make the insert unable to fail), and that is one conjunct away from not latent.
    begin
      -- [0182] LOCK, THEN LOOK AGAIN (codex 0181 #3). The candidate query read a snapshot; a
      -- transition-booking write (the counterparty's confirm, a cancel, a re-match) can commit
      -- between that read and this insert, and the ask would then be obsolete — or addressed to
      -- the former runner. `for update skip locked`: a row a writer holds right now is left for
      -- the next tick (its outcome decides), never waited on (a sweep holding every dog lock it
      -- took must not stall — 0180's lesson). The row we DO get is re-evaluated on its locked,
      -- current version, and the insert happens while the lock is held, so no write can slip in.
      select b.id, b.owner_id, b.runner_id, b.status, b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at, b.handoff_cycle_at
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then
        raise notice 'sweep_run_end_recovery: ask % — row locked by a writer, left for the next tick', r.id;
        continue;
      end if;
      if (v_b.owner_confirmed_handoff_at is null) = (v_b.runner_confirmed_handoff_at is null) then continue; end if;
      if v_b.runner_id is null or v_b.status = any(c_dead) then continue; end if;
      v_cp := case when v_b.owner_confirmed_handoff_at is not null then v_b.runner_id else v_b.owner_id end;
      v_st := coalesce(v_b.owner_confirmed_handoff_at, v_b.runner_confirmed_handoff_at);
      if v_st >= now() - ASK_AFTER then continue; end if;
      if exists (select 1 from notifications nt
                 where nt.ref_id = v_b.id and nt.title = c_ask_title and nt.profile_id = v_cp
                   and nt.created_at >= greatest(coalesce(v_b.handoff_cycle_at, '-infinity'::timestamptz), v_st - ASK_SKEW)) then
        continue;
      end if;
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (v_cp, 'booking', c_ask_title, c_ask_body, v_b.id);
      raise notice 'sweep_run_end_recovery: booking % — 인계 확인 요청 re-sent to % (one-sided since %, no ask row this cycle)',
        v_b.id, v_cp, v_st;
      n := n + 1;
    exception when others then
      raise notice 'sweep_run_end_recovery: ask % — %', r.id, sqlerrm;
    end;
  end loop;

  -- ⓓ [0182] THE DEADLINE (codex 0181 #2 — the attack-INACTION shape, again). After arm ⓒ's one
  -- re-send an unanswered handoff was excluded forever: arms ⓐ/ⓑ need run-end states, and
  -- `late_booking_sweep` is gated on `ops_flags.late_protocol_live_since` AND marketplace-only
  -- (0126:43,78-80). This arm is a bounded ONE-SHOT per cycle, for club and marketplace alike,
  -- reading no flag: ESCALATE_AFTER after the stamp, still one-sided, the parties are told (a
  -- `booking` row each — no '요청' in the title, so it routes to the report / calendar, never to
  -- a CTA that was already declined twice) and the ops roster is told (a redacted `system` row,
  -- 0155's shape; zero subscribers is the honest answer and is in the notice). NO status move —
  -- what a stuck pickup handoff should become is a product decision (Sean's), not a clock's.
  -- ONCE by a column, not by prose: `handoff_escalated_at` is the record and the dedupe key,
  -- reset by the cycle trigger so a NEW pairing can escalate again.
  for r in
    select b.id
    from bookings b
    where (b.owner_confirmed_handoff_at is null) <> (b.runner_confirmed_handoff_at is null)
      and b.runner_id is not null
      and not (b.status = any(c_dead))
      and coalesce(b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at) < now() - ESCALATE_AFTER
      and b.handoff_escalated_at is null
    order by b.id
    limit c_batch
  loop
    begin
      select b.id, b.owner_id, b.runner_id, b.status, b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at, b.handoff_escalated_at
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then continue; end if;
      if (v_b.owner_confirmed_handoff_at is null) = (v_b.runner_confirmed_handoff_at is null) then continue; end if;
      if v_b.runner_id is null or v_b.status = any(c_dead) or v_b.handoff_escalated_at is not null then continue; end if;
      v_st := coalesce(v_b.owner_confirmed_handoff_at, v_b.runner_confirmed_handoff_at);
      if v_st >= now() - ESCALATE_AFTER then continue; end if;
      update bookings set handoff_escalated_at = now() where id = v_b.id;
      insert into notifications (profile_id, kind, title, body, ref_id)
      values (v_b.owner_id,  'booking', c_esc_title, c_esc_body, v_b.id),
             (v_b.runner_id, 'booking', c_esc_title, c_esc_body, v_b.id);
      -- the ops row carries NO identifier in its body (0084 §E: a wrong recipient id pushes a body
      -- verbatim to a stranger's lock screen); the booking id rides in ref_id, as 0155/0166 do.
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, '인계 확인 멈춤 — 확인 필요',
             '한쪽만 확인한 인계가 30분 넘게 멈춰 있어요. 예약을 확인해 주세요.', v_b.id
        from ops_recipients_for(c_ops_class) as rc(profile_id);
      get diagnostics v_ops = row_count;
      raise notice 'sweep_run_end_recovery: booking % — handoff one-sided since %, past %: both parties told, % ops recipient(s) for %',
        v_b.id, v_st, ESCALATE_AFTER, v_ops, c_ops_class;
      n := n + 1;
    exception when others then
      raise notice 'sweep_run_end_recovery: escalate % — %', r.id, sqlerrm;
    end;
  end loop;

  return n;
end $$;
revoke execute on function sweep_run_end_recovery() from public, anon, authenticated;
grant execute on function sweep_run_end_recovery() to service_role;

comment on function sweep_run_end_recovery is
  '0083 §9: 귀가 청소부 두 팔 — ⓐ settlement_ready_at은 찍혔는데 정산이 안 된 행을 NOTICE로
드러내고, 6시간이 지나면 양측에 1회 알린다(상태는 절대 옮기지 않는다: active여야 아직 지급할 수
있다. 러너 지급 기준이 end_reason에 따라 달라져 가격 계산이 TS에 있으므로 크론이 정산할 수는 없다
— 재구동은 0080 §K의 pg_net 디스패처 형태로 후속, §0f). ⓑ 아무도 인계를 확인하지 않은
채(settlement_ready_at is null) 종료 2시간이 지난 예약만 incident_review로 승격(0047:40의 합법
간선) — 부킹이 영원히 active면 러너의 다음 예약이 막힌다. 씰이 찍힌 행은 절대 승격하지 않는다:
incident_review는 돈의 막다른 길(→refund_pending만 허용, 상업적 출구인 club_incident_settle은
클럽 전용)이라 승격하면 러너가 영구 미지급이 된다 — §0h. 승격은 정산이 아니다. 양측에 통지
+ [0181] ⓒ 한쪽만 인계 확인을 찍었고 5분이 지나도록 상대에게 「인계 확인 요청」 알림 행이 없으면(엣지의 insert가 유실된 경우) 스윕이 같은 제목·본문으로 1회 다시 보낸다 — 아직 picked_up에 닿을 수 있는 상태만, 클럽 포함, 찍은 쪽이 아니라 상대에게. 틱은 한 번에 하나(try 잡 락, 겹치면 건너뜀)
+ [0182] ⓒ는 행을 잠그고 다시 본 뒤에만 보내며(잠긴 행은 다음 틱), 이전 짝의 알림은 handoff_cycle_at(재배정·스탬프 리셋 때 DB가 찍음) 앞이면 이 짝의 요청이 아니다; ⓓ 한쪽만 확인한 채 30분이 지나면 양측과 ops 로스터(handoff_unanswered)에 사이클당 1회 알린다 — 상태는 옮기지 않는다, 클럽 포함, 플래그와 무관';

-- ═══ §C ═══
create or replace function reconcile_billing_key_dispatch_ticks()
returns int
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  -- A response written seconds after dispatch, against a cron that ticks every 10 minutes. Two
  -- minutes is generous for the first, far inside the second, and well clear of pg_net's own
  -- default request timeout.
  c_bound constant interval := interval '2 minutes';
  -- pg_net's measured retention (`pg_net.ttl = 6 hours`). Past this the answer is gone and cannot
  -- improve, so a tick stops being re-read and keeps whatever verdict it has.
  c_ttl   constant interval := interval '6 hours';
  -- History is kept, but not forever, and NOT symmetrically — see the delete below.
  c_keep  constant interval := interval '30 days';
  r record;
  v_changed int := 0; v_n int;
  v_outcome text; v_claimed int; v_detail text; v_body jsonb;
  -- [0180] the worker's per-cause counters (0178 split them in the response; the table kept only
  -- `claimed`). NULL = 「the body did not carry this number」, never 0.
  v_revoked int; v_failed int; v_stale int; v_not_processing int; v_absent int; v_unreported int;
  -- [0180] the seven counters are read through ONE guarded path: a JSON number is taken only when
  -- it is an integer in int4 range; anything else is NAMED, never cast — a cast that raises here
  -- aborts the whole call, and every tick behind it stays `sent` for the 6-hour TTL (cold review).
  c_fields constant text[] := array['claimed','revoked','failed','stale','not_processing','absent','unreported'];
  v_f text; v_num numeric; v_vals jsonb; v_missing text[];
begin
  for r in
    select distinct on (t.id)
           t.id as tick_id, h.status_code, h.timed_out, h.error_msg, h.content
      from billing_key_dispatch_ticks t
      join net._http_response h on h.id = t.request_id
     where t.outcome in ('sent','no_response')
       and t.request_id is not null
       and t.sent_at > now() - c_ttl
     order by t.id, h.id desc
  loop
    -- [0182] a per-tick boundary (codex 0180 #4): one answer this block cannot read must not roll
    -- back every sibling's verdict, the stale sweep and the prune with it (measured: an int4 sum
    -- overflow did exactly that; the sum is bigint now, and this arm is for the next such class).
    -- The tick is marked `failed` with the reason — the honest verdict for an answer that arrived
    -- and could not be interpreted — and stops being re-read.
    begin
    v_claimed := null; v_detail := null; v_body := null;
    v_revoked := null; v_failed := null; v_stale := null; v_not_processing := null; v_absent := null; v_unreported := null;

    -- ⚠ `coalesce(…, false)`: `timed_out` is a nullable boolean and a bare `if r.timed_out` is
    --   NOT TAKEN on NULL, which would silently drop the row into a later arm. The NULL-collapse
    --   law (CLAUDE.md) is about pins; it is the same statement about a branch.
    if coalesce(r.timed_out, false) then
      v_outcome := 'failed';
      v_detail  := 'pg_net timed out — the endpoint did not answer in time';
    elsif r.error_msg is not null then
      v_outcome := 'failed';
      v_detail  := left('transport: ' || r.error_msg, 300);
    elsif r.status_code between 200 and 299 then
      v_outcome := 'accepted';
      begin
        v_body := r.content::jsonb;
      exception when others then
        v_body := null;
      end;
      -- `handle()` returns the handler's object un-wrapped (`_shared/ctx.ts:46`), so the claim
      -- count is top level. A different envelope leaves `claimed_count` NULL and says so in
      -- `detail` — visible, rather than a zero that reads like a measurement.
      if v_body is not null and jsonb_typeof(v_body) = 'object' then
        -- [0180] one guarded read for all seven. `jsonb_typeof = 'number'` guards the READ; the
        -- integer test guards the CAST (1.5, 4.0 and 3000000000 are all JSON numbers, and each
        -- would have raised `invalid input syntax` / `out of range` from a bare `::int`). What is
        -- not taken is listed in `v_missing` with its raw value, so `detail` names what it saw.
        v_vals := '{}'::jsonb; v_missing := '{}';
        foreach v_f in array c_fields loop
          if jsonb_typeof(v_body->v_f) is not distinct from 'number' then
            v_num := (v_body->>v_f)::numeric;
            if v_num = trunc(v_num) and v_num between -2147483648 and 2147483647 then
              v_vals := v_vals || jsonb_build_object(v_f, v_num::int);
            else
              v_missing := array_append(v_missing, v_f || '=' || v_num::text || ' (not an integer)');
            end if;
          elsif v_body ? v_f then
            v_missing := array_append(v_missing, v_f || '=' || coalesce(left(v_body->>v_f, 40), 'null') || ' (not a number)');
          elsif v_f <> 'claimed' then
            v_missing := array_append(v_missing, v_f || ' (absent)');
          end if;
        end loop;
        v_claimed        := (v_vals->>'claimed')::int;
        v_revoked        := (v_vals->>'revoked')::int;
        v_failed         := (v_vals->>'failed')::int;
        v_stale          := (v_vals->>'stale')::int;
        v_not_processing := (v_vals->>'not_processing')::int;
        v_absent         := (v_vals->>'absent')::int;
        v_unreported     := (v_vals->>'unreported')::int;
        if v_revoked is null or v_failed is null or v_stale is null or v_not_processing is null
           or v_absent is null or v_unreported is null then
          -- ALL or NOTHING: a body that carries some of the six is an OLDER worker's shape, and in
          -- that shape `stale` still merges three causes (pre-0178). Storing the three it happens
          -- to name beside three NULLs would put a differently-defined number in the same column.
          -- The detail names each field that was absent or unreadable — a diagnosis the code made,
          -- not a guess about which worker sent it.
          v_revoked := null; v_failed := null; v_stale := null;
          v_not_processing := null; v_absent := null; v_unreported := null;
          v_detail := case when v_claimed is null then '2xx with no claim count in the body; ' else '' end
                      || 'per-cause split incomplete — ' || array_to_string(v_missing, ', ') || ' — counters left NULL';
        elsif v_claimed is null then
          -- the six are measurements the worker sent; kept, and the detail says the arithmetic
          -- could not be checked against a claim count that is not there (or not an integer)
          v_detail := '2xx with no claim count in the body'
                      || case when v_body ? 'claimed' then ' (claimed=' || coalesce(left(v_body->>'claimed', 40), 'null') || ')' else '' end
                      || ' — split kept, unchecked';
        elsif least(v_claimed, v_revoked, v_failed, v_stale, v_not_processing, v_absent, v_unreported) < 0 then
          -- 「minus one key was revoked」 is a contradiction whether or not it happens to balance
          v_detail := 'a counter is negative: claimed ' || v_claimed || ', revoked ' || v_revoked || ', failed ' || v_failed
                      || ', stale ' || v_stale || ', not_processing ' || v_not_processing || ', absent ' || v_absent
                      || ', unreported ' || v_unreported;
        elsif v_claimed::bigint <> v_revoked::bigint + v_failed + v_stale + v_not_processing + v_absent + v_unreported then
          -- the tick row must never carry a set of numbers that contradict each other in silence:
          -- every claimed row ends in exactly one bucket (handler.ts), so a body where they do not
          -- sum is a worker bug, and the detail names it while the numbers are kept as sent.
          v_detail := 'counters do not balance: claimed ' || v_claimed || ' <> revoked ' || v_revoked
                      || ' + failed ' || v_failed || ' + stale ' || v_stale || ' + not_processing '
                      || v_not_processing || ' + absent ' || v_absent || ' + unreported ' || v_unreported;
        end if;
      else
        v_detail := '2xx with no claim count in the body';
      end if;
    elsif r.status_code in (401, 403, 503) then
      -- 🔴 THE FINDING. 401 = the cron key is wrong, 503 = it is unset (handler.ts:26-27). Either
      --    way the endpoint answered without claiming a single row, and every tick from here on
      --    will do the same until somebody changes a secret.
      v_outcome := 'rejected';
      v_detail  := left('the endpoint refused this caller (' || r.status_code || '): '
                        || coalesce(left(r.content, 200), ''), 300);
    else
      v_outcome := 'failed';
      v_detail  := left('unexpected answer (' || coalesce(r.status_code::text, 'no status') || '): '
                        || coalesce(left(r.content, 200), ''), 300);
    end if;

    update billing_key_dispatch_ticks
       set outcome              = v_outcome,
           status_code          = r.status_code,
           claimed_count        = v_claimed,
           revoked_count        = v_revoked,
           failed_count         = v_failed,
           stale_count          = v_stale,
           not_processing_count = v_not_processing,
           absent_count         = v_absent,
           unreported_count     = v_unreported,
           detail               = v_detail,
           resolved_at          = now()
     where id = r.tick_id;
    v_changed := v_changed + 1;
    exception when others then
      -- a TRANSIENT cause — a deadlock or serialization failure (class 40), a lock that was not
      -- available (55), a cancelled statement or a shutdown (57), a dropped connection (08) — must
      -- not become a permanent verdict: 0180's whole-call raise self-healed those on the next tick
      -- and so does this: re-raise, the tick stays `sent`, the next tick reads the answer again
      -- (cold review 0182 #3). Everything else is the answer's own fault and is marked, once.
      if left(sqlstate, 2) in ('40', '55', '57', '08') then raise; end if;
      update billing_key_dispatch_ticks
         set outcome = 'failed', status_code = r.status_code,
             detail = left('reconciler could not read this answer: ' || sqlerrm, 300),
             resolved_at = now()
       where id = r.tick_id;
      v_changed := v_changed + 1;
      raise notice 'reconcile_billing_key_dispatch_ticks: tick % — %', r.tick_id, sqlerrm;
    end;
  end loop;

  -- ⚠ THE THIRD STATE. A tick that sent and was never answered is NOT the same as one that was
  --   refused, and it is not silence either — it says the pg_net worker is not running, or the
  --   request never left. Declared only AFTER the bound, so an in-flight tick is never libelled.
  update billing_key_dispatch_ticks
     set outcome     = 'no_response',
         detail      = 'no pg_net response within ' || c_bound::text
                       || ' — the worker may be down, or the request never left',
         resolved_at = now()
   where outcome = 'sent'
     and sent_at <= now() - c_bound;
  get diagnostics v_n = row_count;
  v_changed := v_changed + v_n;

  -- ⚠ THE PRUNE IS DELIBERATELY ASYMMETRIC AND MUST STAY THAT WAY. Only the two outcomes that
  --   mean 「this tick was fine」 are ever deleted. `rejected`, `failed`, `no_response` and
  --   `deferred` are the evidence — the whole reason this table exists — and a retention rule
  --   that swept them on a timer would re-create the defect on a 30-day delay. A permanently
  --   broken system accumulating 144 rows a day is not this table's problem; it is the finding.
  delete from billing_key_dispatch_ticks
   where outcome in ('idle', 'accepted')
     and sent_at < now() - c_keep;

  return v_changed;
end $$;
revoke execute on function reconcile_billing_key_dispatch_ticks() from public, anon, authenticated;
grant  execute on function reconcile_billing_key_dispatch_ticks() to service_role;

-- ═══ the ops vocabulary — 0084's rule: it lives in the table comment, no check constraint; 0155's idiom ═══
do $$
declare v_c text;
begin
  select obj_description('ops_recipients'::regclass, 'pg_class') into v_c;
  if v_c is null or length(v_c) = 0 then
    raise exception '0182: ops_recipients carries no comment — refusing to invent the contract';
  end if;
  if position('handoff_unanswered' in v_c) = 0 then
    execute format('comment on table ops_recipients is %L', v_c || chr(10)
      || '  handoff_unanswered      — [0182] a pickup handoff one side confirmed and the other never did, '
      || '30 minutes on (sweep_run_end_recovery arm ⓓ; both parties are told too, the ops row carries '
      || 'only the booking id in ref_id)');
  end if;
end $$;

-- ═══ VERIFY — apply-time, and NOT a substitute for suite 213 ═══
do $$
declare
  v_oid oid; v_src text; v_bad text := ''; v_n int; v_lit text; v_arr text;
begin
  -- §A
  select count(*) into v_n from pg_attribute where attrelid = 'public.bookings'::regclass and not attisdropped
     and attname in ('handoff_cycle_at', 'handoff_escalated_at');
  if v_n is distinct from 2 then v_bad := v_bad || ' A:COLUMNS(' || v_n || '/2)'; end if;
  select count(*) into v_n from pg_trigger where tgrelid = 'public.bookings'::regclass and tgname = '_handoff_cycle' and not tgisinternal and tgenabled = 'O';
  if v_n is distinct from 1 then v_bad := v_bad || ' A:TRIGGER-NOT-ENABLED(' || v_n || ')'; end if;
  -- §B
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'sweep_run_end_recovery';
  if v_oid is null then raise exception '0182 VERIFY FAILED: NO-FUNCTION(sweep_run_end_recovery)'; end if;
  if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' B:NOT-DEFINER'; end if;
  if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' B:NO-IN-BODY-SEARCH-PATH'; end if;
  if (select proacl is null from pg_proc where oid = v_oid) is distinct from false then v_bad := v_bad || ' B:PUBLIC-EXECUTE'; end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' B:anon-EXECUTE'; end if;
  if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' B:authenticated-EXECUTE'; end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
  if v_src is null then v_bad := v_bad || ' B:NO-SOURCE';
  else
    if (v_src ~ 'nt\.created_at >= greatest\(coalesce\(b\.handoff_cycle_at') is distinct from true then v_bad := v_bad || ' B:CYCLE-BOUND-MISSING-IN-CANDIDATE'; end if;
    if (v_src ~ 'nt\.created_at >= greatest\(coalesce\(v_b\.handoff_cycle_at') is distinct from true then v_bad := v_bad || ' B:CYCLE-BOUND-MISSING-IN-RECHECK'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'for update skip locked', 'g');
    if v_n is distinct from 2 then v_bad := v_bad || ' B:ROW-LOCKS(' || v_n || '/2 — ⓒ and ⓓ each lock before they write)'; end if;
    if (v_src ~ 'handoff_escalated_at = now\(\)') is distinct from true then v_bad := v_bad || ' B:ESCALATION-NOT-RECORDED'; end if;
    if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is distinct from true then v_bad := v_bad || ' B:OPS-NOT-TOLD'; end if;
    if (v_src ~ 'late_protocol_live_since') is distinct from false then v_bad := v_bad || ' B:FLAG-GATED'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'club_session_id is null', 'g');
    if v_n is distinct from 2 then v_bad := v_bad || ' B:CLUB-SCOPE-COUNT(' || v_n || '/2 — ⓐ/ⓑ only)'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'exception when others', 'g');
    if v_n is distinct from 3 then v_bad := v_bad || ' B:PER-ROW-HANDLERS(' || v_n || '/3)'; end if;
    -- the deny-list and the runner conjunct guard ⓓ as well as ⓒ, candidate and re-check alike
    select count(*) into v_n from regexp_matches(v_src, '= any\(c_dead\)', 'g');
    if v_n is distinct from 3 then v_bad := v_bad || ' B:C_DEAD-USES(' || v_n || '/3 — ⓒ re-check, ⓓ candidate, ⓓ re-check)'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'b\.runner_id is not null', 'g');
    if v_n is distinct from 2 then v_bad := v_bad || ' B:RUNNER-CONJUNCT(' || v_n || '/2 — ⓒ and ⓓ candidates)'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'v_b\.runner_id is null', 'g');
    if v_n is distinct from 2 then v_bad := v_bad || ' B:RUNNER-RECHECK(' || v_n || '/2)'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'limit c_batch', 'g');
    if v_n is distinct from 2 then v_bad := v_bad || ' B:BATCH-BOUND(' || v_n || '/2)'; end if;
    if (v_src ~ 'set_config\(''lock_timeout'', ''2000'', true\)') is distinct from true then v_bad := v_bad || ' B:NO-LOCK-TIMEOUT'; end if;
    -- the deny-list spelled twice must be ONE list: the literal in ⓒ's candidate query vs c_dead
    v_lit := regexp_replace((regexp_match(v_src, 'b\.status not in \(([^)]*)\)'))[1], '\s+', '', 'g');
    v_arr := regexp_replace((regexp_match(v_src, 'array\[([^\]]*)\]::booking_status\[\]'))[1], '\s+', '', 'g');
    if v_lit is null or v_arr is null or v_lit is distinct from v_arr then v_bad := v_bad || ' B:DENY-LIST-DRIFT(' || coalesce(v_lit,'∅') || ' vs ' || coalesce(v_arr,'∅') || ')'; end if;
    if (v_src ~ '정산을 확인하고 있어요' and v_src ~ '귀가 확인이 필요해요' and v_src ~ 'c_ask_title constant text := ''인계 확인 요청''') is distinct from true then v_bad := v_bad || ' B:0083/0181-ARMS-MISSING'; end if;
  end if;
  -- §C
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'reconcile_billing_key_dispatch_ticks';
  if v_oid is null then raise exception '0182 VERIFY FAILED: NO-FUNCTION(reconcile_billing_key_dispatch_ticks)'; end if;
  if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' C:NOT-DEFINER'; end if;
  if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' C:NO-IN-BODY-SEARCH-PATH'; end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' C:anon-EXECUTE'; end if;
  if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' C:authenticated-EXECUTE'; end if;
  if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' C:service_role-CANNOT-EXECUTE'; end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
  if v_src is null then v_bad := v_bad || ' C:NO-SOURCE';
  else
    if (v_src ~ 'v_claimed::bigint <> v_revoked::bigint \+') is distinct from true then v_bad := v_bad || ' C:BALANCE-SUM-NOT-BIGINT'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'exception when others', 'g');
    if v_n is distinct from 2 then v_bad := v_bad || ' C:PER-TICK-BOUNDARY(' || v_n || '/2)'; end if;
    if (v_src ~ 'reconciler could not read this answer') is distinct from true then v_bad := v_bad || ' C:UNREADABLE-ANSWER-NOT-NAMED'; end if;
    if (v_src ~ 'left\(sqlstate, 2\) in \(''40'', ''55'', ''57'', ''08''\) then raise;') is distinct from true then v_bad := v_bad || ' C:TRANSIENT-NOT-RERAISED(a deadlock would become a permanent verdict)'; end if;
    if (v_src ~ '\(v_body->>''[a-z_]+''\)::int') is distinct from false then v_bad := v_bad || ' C:UNGUARDED-BODY-CAST'; end if;
  end if;
  if v_bad <> '' then raise exception '0182 VERIFY FAILED:%', v_bad; end if;
end $$;
