-- ═══ 0183: handoff cycle IDENTITY · a pending ops escalation · verdicts only for named errors ═══
--
-- Codex's re-review of 0182 (docs/reviews/2026-09-18-migration-0182-codex-verdict.md, REJECT/3,
-- static; #3 lock-then-look and #5 club routing closed there) — three findings, fixed forward
-- without editing 0182:
--   #1 HIGH  a TIMESTAMP cannot tell handoff cycles apart: the edge stamps and asks in two calls
--            (index.ts:349-365), so a re-match committing between them dates the OLD cycle's ask
--            inside the NEW cycle's window; and rows re-matched before 0182 kept 0181's skew-only
--            rule. → an explicit cycle identity, on the booking AND on the ask.
--   #2 HIGH  arm ⓓ stamped `handoff_escalated_at` even when `ops_recipients_for` returned nothing,
--            so an empty roster consumed the ops escalation forever (213 pinned that). → party
--            delivery and ops delivery recorded separately; an empty roster leaves a durable
--            PENDING ops escalation that later ticks retry, and the parties are never told twice.
--   #3 MED   the reconciler's transient allow-list (40 · 55 · 57 · 08) missed 53 out_of_memory and
--            58 io_error. → inverted: a tick becomes `failed` ONLY on a named deterministic
--            response error (22 · 23 · P0); everything else re-raises and retries.
--
-- ═══ §A the identity (#1) ═══
-- `bookings.handoff_cycle_id uuid` — MINTED BY THE DATABASE (trigger `_handoff_cycle`, before
-- insert and before update) whenever a cycle starts: a row born with a stamp, a first stamp on a
-- row that has no cycle, a runner change, a stamp reset. Derived, never taken from the statement.
-- `notifications.handoff_cycle_id uuid` — the cycle an ask belongs to. `transition-booking` reads
-- the booking's id in the same request that stamped it and writes it onto the ask; this sweep
-- writes its own; `_notification_cycle_guard` (before insert on notifications) REFUSES an ask
-- whose id is not the booking's current one (`stale_handoff_cycle`) — the delayed old-cycle ask
-- of #1 is thereby never inserted, and the sweep re-sends the current cycle's. Arm ⓒ matches an
-- ask by `handoff_cycle_id` alone; 0182's timestamp window (`ASK_SKEW`) is retired.
-- ⚠ THE LEGACY RULE, stated: every one-sided row is given an identity at apply (the backfill
--   below) and any stamped row without one is given one on its next update; an ask carrying NULL
--   (pre-0183, or written by the old edge in the deploy window) cannot prove it belongs to the
--   current cycle, so such a row is asked ONCE MORE — a duplicate push, bounded to rows one-sided
--   across the deploy, over a silent stall. Conservative in the direction the attack-INACTION law
--   prefers. ⚠ DEPLOY ORDER: `db push` FIRST (the old edge keeps working — it writes asks without
--   an id, which the sweep treats as legacy), then `functions deploy transition-booking` promptly
--   (the new edge writes the id); the client build is unchanged by this slice. INVERTED, it fails
--   SILENTLY (cold review 0183 #12): the new edge's ask insert dies on `undefined_column`, `notify`
--   logs it non-fatally, nobody is asked until the migration lands and arm ⓒ catches up — the
--   order belongs in the deploy letter.
-- ⚠ The id authenticates the CYCLE, not the writer: a booking's parties can read it (`bookings
--   party read`) and `noti party insert` lets a party hand-write an ask carrying it, which would
--   suppress the counterparty's re-send — the same suppression a party could already do with the
--   title alone before 0183. Not a regression; named (cold review 0183 #10).
-- `handoff_cycle_at` (0182) stays as the informational timestamp of the cycle's start; nothing
-- matches on it any more.
--
-- ═══ §B `sweep_run_end_recovery` — 0182's body + three marked changes ═══
--   · ⓒ's candidate and re-check match the ask by `handoff_cycle_id` (#1); the re-check mints an
--     identity for a legacy row and the ask it writes carries it.
--   · ⓓ records `handoff_escalated_at` (the parties were told) always and `handoff_ops_alerted_at`
--     (ops were told) ONLY when a roster row was written (#2).
--   · ⓔ the pending ops escalation: rows escalated while the roster was empty are retried every
--     tick — ops rows written, the record stamped on delivery, the parties untouched (#2).
--   Both records reset with the cycle (the trigger). Row locks: ⓒ, ⓓ and ⓔ (three) — each locks
--   its row and looks again before it writes. Handlers: four. `c_dead` at five sites.
--
-- ═══ §C `reconcile_billing_key_dispatch_ticks` — 0182's body + three marked changes (#3) ═══
--   `failed` only for SQLSTATE classes 22 · 23 · P0. Everything else is neither a verdict nor an
--   abort: the tick is left `sent` with a notice and the loop continues — the siblings' verdicts,
--   the stale sweep and the prune all still happen (a re-raise would have killed them every tick
--   for a deterministic unnamed fault such as 42883, cold review 0183 #3). Inside the TTL the tick
--   is read again (a transient fault heals); past it the row stays `sent` beside its answer, and
--   the `no_response` arm skips ticks that HAVE an answer so it is never mislabelled. The inner
--   parse handler classifies the same way (#2: it used to swallow every class into `accepted`).
--   214 E5 injects 53200 · 58030 · 40P01 (the tick stays `sent`, the sibling reconciles in the
--   same call, `accepted/3` once the cause is gone), 42883 (the same, plus the stale sweep and the
--   prune still ran), 22003 · P0001 (verdicts).
--
-- ⚠ `create or replace` of definers FIRST DEFINED IN 0083 and 0150 — both ACLs restated below.
--   Suite-update law, with the reason in each file: 212 C3/C4/C9's edge-ask fixtures now carry the
--   booking's cycle id (an ask without it is legacy and no longer counts — 214 E2 owns that); 213
--   D1's control fixture likewise; 213 D3/D7's 「cycle bound」 source arms move from the timestamp
--   to the id; 213 D7's handler and `c_dead` counts move from `= 3` to `≥ 3` (ⓔ adds one each;
--   214 E6 pins 4); 161 P6's bookings trigger set gains `_handoff_cycle_ins`; the deno `[0181]`
--   drift pin's regex admits the ask's fourth argument.
--
-- ═══ MUTATION TABLE — measured, plants `&&`-chained against a COPY, control observed clean ═══
--   In suite 214's header and the REGISTRY row.

-- ═══ §A ═══
alter table bookings      add column if not exists handoff_cycle_id       uuid;
alter table bookings      add column if not exists handoff_ops_alerted_at timestamptz;
alter table notifications add column if not exists handoff_cycle_id       uuid;
comment on column bookings.handoff_cycle_id is
  '0183: the identity of the CURRENT handoff cycle — minted by trigger _handoff_cycle when a cycle starts (a row born with a stamp, a first stamp, a runner change, a stamp reset); derived, never taken from a statement. 「인계 확인 요청」 rows carry it (notifications.handoff_cycle_id) and sweep_run_end_recovery arm ⓒ counts an ask as this cycle''s only when the ids match. NULL until the row''s first cycle event (a stamp, or a runner change on a stampless row also mints). Readable by the booking''s parties (bookings party read), so it authenticates the CYCLE, not the writer.';
comment on column bookings.handoff_ops_alerted_at is
  '0183: when the ops roster (handoff_unanswered) actually received arm ⓓ''s escalation for this cycle — set only when a recipient row was written; NULL with handoff_escalated_at set = the parties were told while the roster was empty and the ops escalation is PENDING (arm ⓔ retries it every tick). Reset by trigger _handoff_cycle on a new cycle. Server-owned (0058 _guard_booking_cols refuses direct client writes to bookings).';
comment on column notifications.handoff_cycle_id is
  '0183: for a 「인계 확인 요청」 row, the handoff cycle it belongs to (bookings.handoff_cycle_id at the moment the ask was made — the edge reads it in the request that stamped, the sweep writes its own). _notification_cycle_guard refuses an ask whose id is not the booking''s current cycle (stale_handoff_cycle). NULL on every other notification, and on asks that predate 0183 or came from the old edge in the deploy window (legacy: they do not count as the current cycle''s ask).';

create or replace function _handoff_cycle_tg() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    -- a row born mid-handoff (fixtures; a production booking is born at `draft` with no stamp)
    -- needs the cycle's identity from the first moment the sweep could meet it; the records are
    -- the server's and an insert cannot pre-set them
    new.handoff_cycle_id := case when new.owner_confirmed_handoff_at is not null or new.runner_confirmed_handoff_at is not null
                                 then gen_random_uuid() end;
    new.handoff_cycle_at       := case when new.handoff_cycle_id is not null then now() end;   -- derived here too, never the statement's
    new.handoff_escalated_at   := null;
    new.handoff_ops_alerted_at := null;
    return new;
  end if;
  if new.runner_id is distinct from old.runner_id
     or (old.owner_confirmed_handoff_at  is not null and new.owner_confirmed_handoff_at  is null)
     or (old.runner_confirmed_handoff_at is not null and new.runner_confirmed_handoff_at is null) then
    -- a new pairing, or the same pairing starting over: a NEW cycle — new identity, records cleared
    new.handoff_cycle_at       := now();
    new.handoff_cycle_id       := gen_random_uuid();
    new.handoff_escalated_at   := null;
    new.handoff_ops_alerted_at := null;
  else
    -- derived, never taken from the statement: no statement moves the boundary or the identity.
    -- A stamped row that has no identity yet — a first stamp, or a row that predates 0183 being
    -- touched — is given one now. (0058's `_guard_booking_cols` fires first and refuses every
    -- direct client write to `bookings`, so no refusal arm is needed here — measured in 0182.)
    new.handoff_cycle_at := old.handoff_cycle_at;
    new.handoff_cycle_id := coalesce(old.handoff_cycle_id,
                                     case when new.owner_confirmed_handoff_at is not null or new.runner_confirmed_handoff_at is not null
                                          then gen_random_uuid() end);
  end if;
  return new;
end $$;
revoke execute on function _handoff_cycle_tg() from public, anon, authenticated;

drop trigger if exists _handoff_cycle on bookings;
create trigger _handoff_cycle before update on bookings
  for each row execute function _handoff_cycle_tg();
drop trigger if exists _handoff_cycle_ins on bookings;
create trigger _handoff_cycle_ins before insert on bookings
  for each row execute function _handoff_cycle_tg();
comment on function _handoff_cycle_tg is
  '0183 (0182): keeps bookings.handoff_cycle_at and MINTS bookings.handoff_cycle_id when a handoff cycle starts (a row born with a stamp · a first stamp · a runner change · a stamp reset), clearing handoff_escalated_at and handoff_ops_alerted_at on a new cycle; a stamped row without an identity is given one on its next update. Derived — no statement moves them. Before insert and before update; after _guard_booking_cols by name, which is what refuses direct client writes.';

-- the backfill: every row one-sided at apply AND STILL IN A HANDOFF gets its identity now (the
-- trigger mints; the value in the statement is only the touch). A row with no stamp has no cycle.
-- ⚠ SCOPED TO THE TWO LIVE STATUSES ON PURPOSE (cold review 0183 #1, CRITICAL, measured): this
--   UPDATE fires `t_bookings_touch`, which rewrites `updated_at`, and `sweep_cancel_money_gaps`
--   (0117:1579-1592, cron'd every 10 min) uses `bookings.updated_at` as the lower bound that keeps
--   it from being 「the retroactive-billing machine」 — an unscoped backfill re-armed it on a 90-day-
--   old `cancelled_owner` row in the lab (a ₩1,245 runner ledger row on the first tick). Terminal
--   rows are never met by the sweep; a live row the backfill somehow misses is minted by arm ⓒ's
--   touch on first contact. An allow-list here is the SAFER direction: touching fewer rows.
update bookings
   set handoff_cycle_id = gen_random_uuid()
 where handoff_cycle_id is null
   and (owner_confirmed_handoff_at is not null or runner_confirmed_handoff_at is not null)
   and status in ('confirmed', 'runner_enroute');

create or replace function _notification_cycle_guard() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  -- only an ask that CLAIMS a cycle is checked; every other notification carries NULL and passes.
  -- The claim must be the booking's CURRENT cycle: a request overtaken by a re-match (the edge
  -- stamps, then asks, in two calls) arrives here with the old id and is refused — the edge logs
  -- the lost insert (M2's shape) and the sweep re-sends the current cycle's ask.
  if new.handoff_cycle_id is not null then
    if not exists (select 1 from bookings b where b.id = new.ref_id and b.handoff_cycle_id = new.handoff_cycle_id) then
      raise exception 'stale_handoff_cycle'
        using detail = '이 인계 확인 요청은 예약이 더 이상 속하지 않는 인계 사이클의 것이에요 — 재배정에 추월된 요청';
    end if;
  end if;
  return new;
end $$;
revoke execute on function _notification_cycle_guard() from public, anon, authenticated;
drop trigger if exists _notification_cycle_guard on notifications;
create trigger _notification_cycle_guard before insert on notifications
  for each row execute function _notification_cycle_guard();
comment on function _notification_cycle_guard is
  '0183: refuses a notification whose handoff_cycle_id is not the referenced booking''s current handoff_cycle_id (stale_handoff_cycle) — an ask overtaken by a re-match never lands as the new cycle''s. NULL passes.';

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
  v_cid uuid;   -- [0183] the cycle the locked row is in, minted on the spot if it has none (legacy)
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
          -- [0183] …and CARRYING THIS CYCLE'S IDENTITY. `handoff_cycle_id` is minted by the
          -- database (trigger _handoff_cycle) when a cycle starts — a first stamp, a runner change,
          -- a stamp reset — the edge writes it onto the ask it inserts, and `_notification_cycle_guard`
          -- refuses an ask whose id is not the booking's current one. A timestamp could not tell
          -- cycles apart (codex 0182 #1: a delayed old-cycle ask lands inside the new window); an
          -- id can. A row with no id (legacy) matches nothing here and is given one in the loop.
          and nt.handoff_cycle_id = b.handoff_cycle_id)
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
      select b.id, b.owner_id, b.runner_id, b.status, b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at, b.handoff_cycle_id
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
      -- [0183] THE LEGACY RULE, stated: a one-sided row with no cycle identity (it predates 0183 and
      -- the apply-time backfill somehow missed it, or a fixture) is given one by this touch — the
      -- trigger mints on any update of a stamped, id-less row — and every ask it already has
      -- (NULL id) cannot prove it belongs to this cycle, so the row is asked ONCE MORE: a
      -- duplicate push over a silent stall. The ask written below carries the id, so the next
      -- tick matches it.
      v_cid := v_b.handoff_cycle_id;
      if v_cid is null then
        update bookings set handoff_cycle_at = handoff_cycle_at where id = v_b.id returning handoff_cycle_id into v_cid;
        raise notice 'sweep_run_end_recovery: booking % had no handoff cycle identity — minted % (legacy row)', v_b.id, v_cid;
      end if;
      if exists (select 1 from notifications nt
                 where nt.ref_id = v_b.id and nt.title = c_ask_title and nt.profile_id = v_cp
                   and nt.handoff_cycle_id = v_cid) then
        continue;
      end if;
      insert into notifications (profile_id, kind, title, body, ref_id, handoff_cycle_id)
      values (v_cp, 'booking', c_ask_title, c_ask_body, v_b.id, v_cid);
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
      -- [0183] TWO RECORDS, not one (codex 0182 #2): the parties' delivery is done here and once;
      -- the OPS delivery is recorded ONLY when a recipient actually got a row. An empty roster
      -- leaves `handoff_ops_alerted_at` NULL — a durable PENDING ops escalation that arm ⓔ retries
      -- every tick until somebody is provisioned, without telling the parties twice (0166's
      -- 「the stamp is conditioned on a delivery」 rule, applied to the half it fits).
      update bookings
         set handoff_escalated_at = now(),
             handoff_ops_alerted_at = case when v_ops > 0 then now() end
       where id = v_b.id;
      raise notice 'sweep_run_end_recovery: booking % — handoff one-sided since %, past %: both parties told, % ops recipient(s) for %',
        v_b.id, v_st, ESCALATE_AFTER, v_ops,
        c_ops_class || case when v_ops = 0 then ' — ops escalation PENDING until the roster is provisioned' else '' end;
      n := n + 1;
    exception when others then
      raise notice 'sweep_run_end_recovery: escalate % — %', r.id, sqlerrm;
    end;
  end loop;

  -- ⓔ [0183] THE PENDING OPS ESCALATION (codex 0182 #2). Rows whose parties were told (ⓓ) while
  -- the ops roster was empty keep `handoff_ops_alerted_at` NULL; every tick tries the roster again
  -- for rows still one-sided and live, records the delivery only when a row was written, and never
  -- touches the parties. Locked and re-checked like ⓒ/ⓓ (cold review 0183 #6, measured: without
  -- the lock a confirm committing inside the loop still got ops paged about a handoff that had
  -- just finished — the row WAS escalated, but the page's whole content is 「still stuck」). The job
  -- lock serializes ticks. Bounded by `c_batch`; resets with the cycle (the trigger).
  for r in
    select b.id
    from bookings b
    where b.handoff_escalated_at is not null
      and b.handoff_ops_alerted_at is null
      and (b.owner_confirmed_handoff_at is null) <> (b.runner_confirmed_handoff_at is null)
      and b.runner_id is not null
      and not (b.status = any(c_dead))
    order by b.id
    limit c_batch
  loop
    begin
      select b.id, b.runner_id, b.status, b.owner_confirmed_handoff_at, b.runner_confirmed_handoff_at, b.handoff_escalated_at, b.handoff_ops_alerted_at
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then continue; end if;
      if (v_b.owner_confirmed_handoff_at is null) = (v_b.runner_confirmed_handoff_at is null) then continue; end if;
      if v_b.runner_id is null or v_b.status = any(c_dead) then continue; end if;
      if v_b.handoff_escalated_at is null or v_b.handoff_ops_alerted_at is not null then continue; end if;
      insert into notifications (profile_id, kind, title, body, ref_id)
      select rc.profile_id, 'system'::noti_kind, '인계 확인 멈춤 — 확인 필요',
             '한쪽만 확인한 인계가 30분 넘게 멈춰 있어요. 예약을 확인해 주세요.', v_b.id
        from ops_recipients_for(c_ops_class) as rc(profile_id);
      get diagnostics v_ops = row_count;
      if v_ops > 0 then
        update bookings set handoff_ops_alerted_at = now() where id = v_b.id and handoff_ops_alerted_at is null;
        raise notice 'sweep_run_end_recovery: booking % — pending ops escalation delivered to % recipient(s)', v_b.id, v_ops;
        n := n + 1;
      end if;
    exception when others then
      raise notice 'sweep_run_end_recovery: pending ops % — %', r.id, sqlerrm;
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
+ [0182] ⓒ는 행을 잠그고 다시 본 뒤에만 보내며(잠긴 행은 다음 틱), 이전 짝의 알림은 handoff_cycle_at(재배정·스탬프 리셋 때 DB가 찍음) 앞이면 이 짝의 요청이 아니다; ⓓ 한쪽만 확인한 채 30분이 지나면 양측과 ops 로스터(handoff_unanswered)에 사이클당 1회 알린다 — 상태는 옮기지 않는다, 클럽 포함, 플래그와 무관
+ [0183] 요청 행은 handoff_cycle_id(사이클 정체성, 트리거가 발급·notifications 삽입 가드가 검증)로 맞춘다 — 시각으로는 사이클을 못 가른다; ⓔ ops 로스터가 비어 있던 승격은 handoff_ops_alerted_at이 NULL인 채 남아 틱마다 다시 시도한다(양측은 두 번 듣지 않는다)';

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
        -- [0183] the same classification as the per-tick handler below (cold review 0183 #2: this
        -- inner arm swallowed EVERY class, so an out-of-memory during the parse became `accepted`
        -- with 「no claim count」 — and prunable). A malformed body (22P02) is the answer's own
        -- fault → NULL body; anything else is not a verdict and goes to the per-tick handler.
        if left(sqlstate, 2) in ('22', '23', 'P0') then v_body := null; else raise; end if;
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
      -- [0183] ONLY an identified DETERMINISTIC response error becomes a verdict (codex 0182 #3 —
      -- 0182's allow-list of four transient classes missed 53 out_of_memory and 58 io_error, which
      -- would have become permanent `failed`s): class 22 = a data exception (the body's own
      -- numbers), class 23 = an integrity violation (a verdict the table refuses), class P0 = a
      -- raise from our own plpgsql path. EVERYTHING ELSE — deadlocks (40), resources (53), locks
      -- (55), cancels/shutdowns (57), I/O (58), connections (08), internal (XX), and any class
      -- nobody has named yet — is NOT a verdict and NOT an abort either (cold review 0183 #3: a
      -- re-raise killed the siblings' verdicts, the stale sweep and the prune every tick for a
      -- deterministic unnamed fault such as 42883): the tick is left exactly as it is, `sent`, the
      -- notice names it, the loop goes on. Inside the TTL the next tick reads it again (a transient
      -- fault heals); past it the row stays `sent` beside its answer — visible, and the
      -- `no_response` arm below will not mislabel it (it skips ticks that HAVE an answer).
      if left(sqlstate, 2) not in ('22', '23', 'P0') then
        raise notice 'reconcile_billing_key_dispatch_ticks: tick % — not a verdict (%), left as it is: %', r.tick_id, sqlstate, sqlerrm;
        continue;
      end if;
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
     and sent_at <= now() - c_bound
     -- [0183] a tick that HAS an answer is not 「no response」, whatever kept the loop from reading it
     and not exists (select 1 from net._http_response h where h.id = request_id);
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

-- ═══ VERIFY — apply-time, and NOT a substitute for suite 214 ═══
do $$
declare
  v_oid oid; v_src text; v_bad text := ''; v_n int; v_lit text; v_arr text;
begin
  -- §A
  select count(*) into v_n from pg_attribute where attrelid = 'public.bookings'::regclass and not attisdropped
     and attname in ('handoff_cycle_id', 'handoff_ops_alerted_at');
  if v_n is distinct from 2 then v_bad := v_bad || ' A:BOOKING-COLUMNS(' || v_n || '/2)'; end if;
  select count(*) into v_n from pg_attribute where attrelid = 'public.notifications'::regclass and not attisdropped and attname = 'handoff_cycle_id';
  if v_n is distinct from 1 then v_bad := v_bad || ' A:NOTIFICATION-COLUMN(' || v_n || '/1)'; end if;
  select count(*) into v_n from pg_trigger where tgrelid = 'public.bookings'::regclass and tgname in ('_handoff_cycle', '_handoff_cycle_ins') and not tgisinternal and tgenabled = 'O';
  if v_n is distinct from 2 then v_bad := v_bad || ' A:CYCLE-TRIGGERS-NOT-ENABLED(' || v_n || '/2)'; end if;
  select count(*) into v_n from pg_trigger where tgrelid = 'public.notifications'::regclass and tgname = '_notification_cycle_guard' and not tgisinternal and tgenabled = 'O';
  if v_n is distinct from 1 then v_bad := v_bad || ' A:GUARD-NOT-ENABLED(' || v_n || ')'; end if;
  -- the guard must check WHICH booking the ask names (cold review 0183 #4: without `b.id = new.ref_id` it
  -- became 「is this uuid any live booking's current cycle」 and the suite stayed green until 214 E3 grew an arm)
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where proname = '_notification_cycle_guard';
  if v_src is null then v_bad := v_bad || ' A:NO-SOURCE(guard)';
  elsif (v_src ~ 'b\.id = new\.ref_id and b\.handoff_cycle_id = new\.handoff_cycle_id') is distinct from true then v_bad := v_bad || ' A:GUARD-DOES-NOT-CHECK-WHICH-BOOKING'; end if;
  -- ⚠ vacuous in the harness (migrations apply on an empty table — cold review 0183 #11); real on a
  --   production apply. Scoped like the backfill: a terminal row may keep NULL.
  select count(*) into v_n from bookings where handoff_cycle_id is null and (owner_confirmed_handoff_at is not null or runner_confirmed_handoff_at is not null) and status in ('confirmed', 'runner_enroute');
  if v_n is distinct from 0 then v_bad := v_bad || ' A:BACKFILL-LEFT-LIVE-ONE-SIDED-ROWS-WITHOUT-AN-IDENTITY(' || v_n || ')'; end if;
  -- §B
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'sweep_run_end_recovery';
  if v_oid is null then raise exception '0183 VERIFY FAILED: NO-FUNCTION(sweep_run_end_recovery)'; end if;
  if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' B:NOT-DEFINER'; end if;
  if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' B:NO-IN-BODY-SEARCH-PATH'; end if;
  if (select proacl is null from pg_proc where oid = v_oid) is distinct from false then v_bad := v_bad || ' B:PUBLIC-EXECUTE'; end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' B:anon-EXECUTE'; end if;
  if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' B:authenticated-EXECUTE'; end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
  if v_src is null then v_bad := v_bad || ' B:NO-SOURCE';
  else
    if (v_src ~ 'nt\.handoff_cycle_id = b\.handoff_cycle_id\)') is distinct from true then v_bad := v_bad || ' B:ID-MATCH-MISSING-IN-CANDIDATE'; end if;
    if (v_src ~ 'nt\.handoff_cycle_id = v_cid\)') is distinct from true then v_bad := v_bad || ' B:ID-MATCH-MISSING-IN-RECHECK'; end if;
    if (v_src ~ 'ASK_SKEW|handoff_cycle_at, ''-infinity''') is distinct from false then v_bad := v_bad || ' B:TIMESTAMP-MATCH-STILL-PRESENT'; end if;
    if (v_src ~ 'returning handoff_cycle_id into v_cid') is distinct from true then v_bad := v_bad || ' B:LEGACY-ROW-NOT-GIVEN-AN-IDENTITY'; end if;
    if (v_src ~ 'values \(v_cp, ''booking'', c_ask_title, c_ask_body, v_b\.id, v_cid\)') is distinct from true then v_bad := v_bad || ' B:RESEND-CARRIES-NO-IDENTITY'; end if;
    if (v_src ~ 'handoff_ops_alerted_at = case when v_ops > 0 then now\(\) end') is distinct from true then v_bad := v_bad || ' B:OPS-RECORD-NOT-CONDITIONED-ON-DELIVERY'; end if;
    if (v_src ~ 'and b\.handoff_ops_alerted_at is null') is distinct from true then v_bad := v_bad || ' B:NO-PENDING-OPS-ARM'; end if;
    if (v_src ~ 'set handoff_ops_alerted_at = now\(\) where id = v_b\.id and handoff_ops_alerted_at is null') is distinct from true then v_bad := v_bad || ' B:PENDING-OPS-NOT-RECORDED-ON-DELIVERY'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'for update skip locked', 'g');
    if v_n is distinct from 3 then v_bad := v_bad || ' B:ROW-LOCKS(' || v_n || '/3 — ⓒ, ⓓ and ⓔ each lock before they write)'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'exception when others', 'g');
    if v_n is distinct from 4 then v_bad := v_bad || ' B:PER-ROW-HANDLERS(' || v_n || '/4)'; end if;
    select count(*) into v_n from regexp_matches(v_src, '= any\(c_dead\)', 'g');
    if v_n is distinct from 5 then v_bad := v_bad || ' B:C_DEAD-USES(' || v_n || '/5)'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'limit c_batch', 'g');
    if v_n is distinct from 3 then v_bad := v_bad || ' B:BATCH-BOUND(' || v_n || '/3)'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'club_session_id is null', 'g');
    if v_n is distinct from 2 then v_bad := v_bad || ' B:CLUB-SCOPE-COUNT(' || v_n || '/2)'; end if;
    if (v_src ~ 'late_protocol_live_since') is distinct from false then v_bad := v_bad || ' B:FLAG-GATED'; end if;
    v_lit := regexp_replace((regexp_match(v_src, 'b\.status not in \(([^)]*)\)'))[1], '\s+', '', 'g');
    v_arr := regexp_replace((regexp_match(v_src, 'array\[([^\]]*)\]::booking_status\[\]'))[1], '\s+', '', 'g');
    if v_lit is null or v_arr is null or v_lit is distinct from v_arr then v_bad := v_bad || ' B:DENY-LIST-DRIFT'; end if;
    if (v_src ~ '정산을 확인하고 있어요' and v_src ~ '귀가 확인이 필요해요' and v_src ~ 'c_ask_title constant text := ''인계 확인 요청''' and v_src ~ 'c_esc_title constant text := ''인계 확인이 멈춰 있어요''') is distinct from true then v_bad := v_bad || ' B:EARLIER-ARMS-MISSING'; end if;
  end if;
  -- §C
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'reconcile_billing_key_dispatch_ticks';
  if v_oid is null then raise exception '0183 VERIFY FAILED: NO-FUNCTION(reconcile_billing_key_dispatch_ticks)'; end if;
  if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' C:NOT-DEFINER'; end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' C:anon-EXECUTE'; end if;
  if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' C:authenticated-EXECUTE'; end if;
  if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' C:service_role-CANNOT-EXECUTE'; end if;
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
  if v_src is null then v_bad := v_bad || ' C:NO-SOURCE';
  else
    if (v_src ~ 'left\(sqlstate, 2\) not in \(''22'', ''23'', ''P0''\) then') is distinct from true then v_bad := v_bad || ' C:VERDICT-NOT-LIMITED-TO-NAMED-CLASSES'; end if;
    if (v_src ~ 'left\(sqlstate, 2\) in \(''22'', ''23'', ''P0''\) then v_body := null; else raise; end if;') is distinct from true then v_bad := v_bad || ' C:PARSE-HANDLER-SWALLOWS-EVERY-CLASS'; end if;
    if (v_src ~ 'not in \(''22'', ''23'', ''P0''\) then raise;') is distinct from false then v_bad := v_bad || ' C:UNNAMED-FAULT-ABORTS-THE-CALL'; end if;
    if (v_src ~ 'and not exists \(select 1 from net\._http_response h where h\.id = request_id\)') is distinct from true then v_bad := v_bad || ' C:NO_RESPONSE-MISLABELS-AN-ANSWERED-TICK'; end if;
    if (v_src ~ 'left\(sqlstate, 2\) in \(''40''') is distinct from false then v_bad := v_bad || ' C:TRANSIENT-ALLOW-LIST-STILL-PRESENT'; end if;
    if (v_src ~ 'v_claimed::bigint <> v_revoked::bigint \+') is distinct from true then v_bad := v_bad || ' C:BALANCE-SUM-NOT-BIGINT'; end if;
    select count(*) into v_n from regexp_matches(v_src, 'exception when others', 'g');
    if v_n is distinct from 2 then v_bad := v_bad || ' C:PER-TICK-BOUNDARY(' || v_n || '/2)'; end if;
  end if;
  if v_bad <> '' then raise exception '0183 VERIFY FAILED:%', v_bad; end if;
end $$;
