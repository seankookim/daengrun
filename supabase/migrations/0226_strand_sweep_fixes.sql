-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0226 — the sealed-unsettled bell can no longer abort the sweep · the recurring pause dedupe keys
--        on the DEBT it was about, not on generated bookings
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 257_strand_sweep_fixes_suite.sql (tag `ssf`) — 0226-F1 · F2 · C2 · C3 · C4 · H1 · S1
-- Edge (same slice, no migration object): `transition-booking/index.ts`'s accept refusal maps the two
--   work-gate words 0224 added (`start_run` / `end_run`) — see §0c.
--
-- ═══ §0a WHAT IS WRONG — Codex REJECT/3 on 0224 (docs/reviews/2026-09-25-wave3-codex-verdicts.md) ══
-- Both SQL findings were READ-based, so 257 was written first and RUN AGAINST 0224 before a line of
-- this file existed. Measured there (harness DB, rolled-back transaction):
--   s1 (high) — 0224:580-606. Arm ⓐ's two per-row writes — the parties' 「정산을 확인하고 있어요」
--     alarm (0083's) and 0224's new `payout_due` bell — sit in the loop with NO handler. One row's
--     insert that raises (codex's case: a recipient `profiles` row held FOR UPDATE, so the FK's KEY
--     SHARE check waits past the 2 s `lock_timeout` this function sets for itself) raises out of the
--     whole function. MEASURED with a planted 55P03 on one row's bell: the tick RAISED; the healthy
--     row beside it got neither its alarm nor its bell; arm ⓑ-①'s zero-stamp escalation and arm
--     ⓖ's custody notice — both in the same tick, both AFTER ⓐ — never happened. And arm ⓐ runs
--     FIRST and unconditionally: this is live with both custody thresholds NULL.
--   s3 (medium) — 0224:1553-1561. The recurring pause dedupe resets only when a series booking was
--     created after the last notice. MEASURED: debt → notice → both failed charges PAID → a new
--     charge fails, no tick in between (so no booking) → the next tick wrote NOTHING although the
--     first notice was two hours old. The owner who paid is not told the series paused again until
--     the 24 h window lapses.
--   s2 (medium) — its EDGE half: `transition-booking/index.ts:209-214` answered `start_run` /
--     `end_run` with the both-parties-return sentence (「인계가 양측 확인으로 끝나지 않았어요 — 인계를
--     마치면…」) — telling a runner whose run never started, or never stopped, to finish a return that
--     does not exist yet. The client half is another builder's (fix/custody-strand-client).
--
-- ═══ §0b WHAT THIS FILE DOES ═════════════════════════════════════════════════════════════════
--   §A `sweep_run_end_recovery` — 0224 §D's body, copied BY SCRIPT, one edit region: arm ⓐ's two
--      writes each run in their OWN subtransaction (0210 §E's nested-leg shape, siblings here because
--      neither leg is the other's parent). A failure is a NOTICE naming the row, the leg and SQLERRM,
--      writes nothing for that leg, and is retried next tick — neither leg's one-shot title exists
--      until its insert commits. The legs are SIBLINGS on purpose: a failing bell must not roll back
--      the parties' alarm (0210's reason), and a failing alarm must not skip the bell (the reverse,
--      which a single block around both would do). `0226-F1`/`F2` pin both directions.
--      Arms ⓑ–ⓖ are 0224's byte for byte (asserted by the build script).
--   §B `_unsettled_charge_through(owner, through)` — 0080 §F's `owner_has_unsettled_charge` predicate
--      VERBATIM plus one conjunct, `p.created_at <= p_through`: 「is this owner in debt NOW, counting
--      only charges minted at or before `through`」. `0226-H1` pins that its comment-stripped source is
--      0080's plus exactly that conjunct, and that at `'infinity'` it equals the original over the
--      whole harness population — so the two cannot drift silently.
--   §C `generate_recurring_bookings` — 0224 §H's body, copied BY SCRIPT, ONE edit: the pause dedupe's
--      subquery gains one conjunct. An earlier notice now counts only while
--        (i)  no booking of this owner's series has been created since it — 0224's witness, KEPT: a
--             generated booking proves the owner was unblocked at some tick, which is a real episode
--             boundary; it is just not the only one, and
--        (ii) for a DEBT block, a charge that already existed when it was written is STILL unsettled
--             (`_unsettled_charge_through(s.owner_id, nt.created_at)`). Every charge the notice was
--             about has been paid ⇒ whatever debt blocks the owner now is a new episode ⇒ tell them.
--      Title, body and NULL ref are 0180's, byte for byte (the brief; notification-route pins 0180).
--
-- ═══ §0c WHY THIS KEY, AND WHAT IT DOES NOT CATCH ══════════════════════════════════════════════
--   Debt is DERIVED (0080 §F — 「there is no collection_status column and there never will be」), so no
--   row records when an episode began or ended. What the rows DO carry: a `failed` charge stays
--   `failed` through every retry of the ladder (the dispatch CLAIM rewrites `raw` and `updated_at`,
--   never `status` — `_shared/charge.ts` §dispatch) until it leaves for good (`confirmed`/`waived`).
--   So a charge that was unpaid when the notice was written and is unpaid now has been debt the whole
--   time: the debt the owner was told about has not ended. That is a CONTINUITY witness, and it is
--   the smallest key the rows support. Two other keys were weighed and rejected:
--     · 「a failed charge NEWER than the notice」 — MEASURED (planted in the lab battery): it re-tells a
--       blocked owner once per failed charge while the first is still unpaid (the pause they were
--       told about has not changed); `0226-C3` is the control that reddens under it.
--     · `payments.updated_at` — READ, not measured: the dispatch claim rewrites it on every ladder
--       retry (`_shared/charge.ts`, rungs +1 h and +24 h), so one unpaid charge would re-send the
--       notice at each automatic retry.
--   ⚠ NAMED RESIDUE (prose — `257`'s header says why no pin): a charge minted BEFORE a notice that
--     only becomes debt AFTER the owner paid everything the notice was about counts as a witness and
--     suppresses the new episode's notice. Its window is about an hour — a never-dispatched pending
--     is failed by `sweep_stale_payment_intents` at +1 h, a dispatched pending is debt at dispatch
--     +1 h — and (i) still catches it whenever a tick in that hour generated a booking.
--   ⚠ A CARD-LESS block (`no_card`) has no debt to witness, so (ii) is not asked of it and 0224's rule
--     stands (`0226-C4`). A debt block that clears and becomes a card-less block with no booking in
--     between is suppressed as before; nothing durable records a card's removal.
--
-- ═══ §0d WHAT THIS FILE DELIBERATELY DOES NOT DO ═════════════════════════════════════════════
--   · `generate_recurring_bookings`'s own per-series inserts (the booking, 「반복 러닝 예약 생성」, the
--     pause notice) still have no per-series handler, and it sets the same 2 s `lock_timeout` — the
--     s1 shape in a different function. It is a MONEY PATH and this slice's brief for it is 「change
--     only the dedupe predicate」; it is named here and in the REGISTRY row, not fixed.
--   · `owner_has_unsettled_charge` is NOT re-declared on top of §B (it is 0080's money gate, read by the
--     edge's create-booking-hold and by `my_unsettled_charge`). The drift is held by `0226-H1` instead.
--   · No client change. No threshold is set.
--
-- ═══ §0d-bis SHIPPED PINS THAT MOVE, AND WHY ═════════════════════════════════════════════════
--   · `214 0183-E6` — 「exception when others」 in the sweep's comment-stripped body: 5 → 7. Arm ⓐ's two
--     legs are the sixth and seventh; the property that line owns — every arm that writes catches its
--     own row — is now true of ⓐ as well. `0226-F1`/`F2` own the behaviour.
--   · `161 P4` — the generator's prosrc/comment digests, re-read from the catalog after this file
--     applied, as P4's own note asks.
--
-- ═══ §0e WHOSE OBJECTS THIS BUILDS ON (REGISTRY's silent-collision table) ═════════════════════
--   RE-DECLARES `sweep_run_end_recovery()` ←0224 §D and `generate_recurring_bookings()` ←0224 §H
--   (both copied by script from 0224's text, every other line asserted identical). CREATES
--   `_unsettled_charge_through(uuid,timestamptz)`. Every ACL restated in THIS file.
--   ⚠ A later slice re-declaring `sweep_run_end_recovery` must keep arm ⓐ's two handlers (257
--   `0226-F1`/`F2`, 214 `0183-E6`) and the call to `_sweep_custody_strands()` (255 `0224-S1`).
--
-- ═══ §0f DEPLOY ══════════════════════════════════════════════════════════════════════════════
--   `supabase db push` (this file) and `supabase functions deploy transition-booking`, either order —
--   the edge change only adds refusal sentences for two `waiting_on` values the server already sends
--   once a custody threshold is set, and the thresholds ship NULL. No cron change, no flag.

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A sweep_run_end_recovery — arm ⓐ's two writes, each in its own subtransaction
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0224 §D's body, copied BY SCRIPT (0201 §0c's discipline). ONE edit region, arm ⓐ's per-row tail;
-- the build script asserts every other line identical to 0224's and the handler count +2 exactly.
create or replace function sweep_run_end_recovery() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; n int := 0;
  STRAND_AFTER constant interval := interval '2 hours';
  -- A sealed row is RECOVERABLE — the money can still move the moment the pricing path re-drives
  -- it — so its alarm is longer than the stranding deadline and, crucially, moves no state.
  SEAL_ALARM_AFTER constant interval := interval '6 hours';
  -- [0188] arm ⓑ-②'s one-shot alarm: a return ONE side has confirmed and the other has not.
  -- A DISTINCT title from the escalation's 「귀가 확인이 필요해요」 so neither dedupe key can
  -- silence the other, and so the client can route them apart. `notification-route.ts` routes it
  -- (runner → /runner/return-seal · owner → the bid-scoped report) and
  -- `app/test/notification-route.test.cjs` reads THIS constant out of THIS file, so the two
  -- spellings cannot drift (the c_esc_title idiom, 0182).
  c_ret_title     constant text := '반환 확인이 멈춰 있어요';
  -- to the side that has NOT stamped …
  c_ret_body_ask  constant text := '러닝이 끝났는데 반환 확인이 아직이에요 — 앱에서 인계를 확인해주세요';
  -- … and to the side that HAS. Never the first sentence: telling someone to confirm what they
  -- already confirmed is a lie about their own action (0092 §6).
  c_ret_body_wait constant text := '내 반환 확인은 끝났고 상대방 확인을 기다리고 있어요 — 확인되면 정산이 마무리돼요';
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
  -- [0193 §D] arm ⓕ. A DURATION read from `ops_flags` at the top of the arm, not a constant: the
  -- number is Sean's ruling (queue item 23) and NULL — the shipped value — means the arm does
  -- nothing at all. The ops class is its own, not `payout_due`'s: the people who can END a strand
  -- (`ops_resolve_return_tx` gates on exactly this roster) are the people who should be told.
  c_strand_ops_class constant text := 'return_strand';
  c_strand_title constant text := '반환 좌초 — 확인 필요';
  -- NO id and NO amount in the body (0084 §E: a wrong recipient id pushes the body verbatim to a
  -- stranger's lock screen). The booking id rides in `ref_id`, as 0155/0166/0182 do.
  c_strand_body  constant text := '러닝이 끝났는데 반환 확인이 끝나지 않은 예약이 있어요. 예약을 확인해 주세요.';
  v_strand_min int;
  -- [0224 §D ①] arm ⓐ's OPERATOR bell. `payout_due` — a sealed-but-unsettled run is a runner owed
  -- money, the class 0084 §E pages for money. Its own one-shot title (NOT the parties'), so a row
  -- whose parties were told before 0224 still rings once. NO id and NO amount in the body (0084 §E).
  c_seal_ops_class constant text := 'payout_due';
  c_seal_ops_title constant text := '정산 미완료 — 확인 필요';
  c_seal_ops_body  constant text := '인계는 확인됐는데 정산이 마무리되지 않은 예약이 있어요. 예약을 확인해 주세요.';
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
    -- [0226 §A] ITS OWN SUBTRANSACTION (codex s1). Without it one row whose insert raises — a
    -- recipient row held past this function's own 2 s lock_timeout, or anything else — raised out
    -- of the whole sweep: every earlier row's notice rolled back and arms ⓑ–ⓖ never ran (measured,
    -- 257 `0226-F1` against 0224). A failure is a NOTICE, the one-shot title is not written, and the
    -- next tick tries again. The owner row and the runner row stay in ONE block: the one-shot key is
    -- the title on this booking, so a half-written pair would silence the other half forever.
    begin
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
    exception when others then
      raise notice 'sweep_run_end_recovery: seal-alarm % — the parties'' alarm failed (% %); nothing written, retried next tick',
        r.id, sqlstate, sqlerrm;
    end;
    -- [0224 §D ①] …and the OPERATORS, once, by their own title, at the same age. Until this file
    -- the sentence above — 「담당자가 확인하고 있어요」 — had nobody behind it: no operator was told
    -- and no list showed the row (backend-logic-2). An EMPTY roster writes nothing and is retried
    -- next tick (0193 ⓕ's durable PENDING), and the notice says so rather than reading as sent.
    -- [0226 §A] A SIBLING subtransaction, not nested in the one above and not sharing it: a failing
    -- bell must not roll back the parties' alarm (0210 §E's reason), and a failing alarm must not
    -- skip the bell (which one block around both would do). 257 `0226-F2` pins both directions.
    begin
      if r.settlement_ready_at < now() - SEAL_ALARM_AFTER
         and not exists (select 1 from notifications nt
                         where nt.ref_id = r.id and nt.title = c_seal_ops_title) then
        insert into notifications (profile_id, kind, title, body, ref_id)
        select rc.profile_id, 'system'::noti_kind, c_seal_ops_title, c_seal_ops_body, r.id
          from ops_recipients_for(c_seal_ops_class) as rc(profile_id);
        get diagnostics v_ops = row_count;
        raise notice 'sweep_run_end_recovery: booking % — sealed but unsettled past %: % ops recipient(s) for %',
          r.id, SEAL_ALARM_AFTER, v_ops,
          c_seal_ops_class || case when v_ops = 0 then ' — the roster is empty; nobody was told, retried next tick' else '' end;
      end if;
    exception when others then
      raise notice 'sweep_run_end_recovery: seal-ops % — the payout_due bell failed (% %); nothing written, retried next tick',
        r.id, sqlstate, sqlerrm;
    end;
  end loop;

  -- ⓑ [0188] THE RUN-END STRAND — narrowed, because what this arm does to a row is a MONEY DEAD
  -- END and this slice is the first thing in the product that can put a row in front of it.
  --
  -- 0083 wrote this arm while `end_run_tx` had ZERO callers, so it has never escalated a real
  -- marketplace 귀가. The run-end ceremony (⑪/⑫) gives it rows for the first time, and the
  -- composition is a defect measured before it shipped:
  --   ① the runner stops (`end_run_tx`) and stamps their own return on R6a seconds later;
  --   ② the owner is slower than STRAND_AFTER — at work, phone silent; two hours is not long;
  --   ③ this arm moves the booking `active → incident_review`;
  --   ④ the owner stamps that evening. 0096 lets the stamp LAND and deliberately does not seal;
  --   ⑤ `_settle_sealed_run` requires `active` (0083 §6) and `enforce_booking_transition` gives
  --      `incident_review` exactly one edge — `refund_pending` (0066:56) — so the run can NEVER
  --      settle. The runner walked the dog, brought it home, BOTH parties said so, and the only
  --      state the money could have moved from is gone.
  -- 0083's own header already refused this shape for SEALED rows ("an owner who simply did not
  -- tap confirm within 2 hours able to render the runner permanently unpayable"). The UNSEALED
  -- row acquires the identical property the moment 0096 makes a late stamp possible — and 0096
  -- landed after 0083, so neither file could see it alone.
  --
  -- ⚠ AND THE ESCALATION BUYS NOTHING IT WAS BOUGHT FOR. Its stated purpose is that `active` is
  -- LIVE to the runner-accept conflict guard, "so the runner's future bookings are blocked by a
  -- dog they returned two days ago". Both halves are false today:
  --   · the block is ⑫'s WORK GATE (0092), which reads the two stamp columns and ALSO catches
  --     `incident_review` (`0092:112-117`) — escalating frees no runner. Pinned: 219 0188-B3.
  --   · the accept-time conflict guard (`transition-booking/index.ts`) compares SCHEDULED
  --     WINDOWS within ±6h, so a two-day-old booking overlaps nothing it could block. READ from
  --     that source, NOT pinned here — it is TypeScript and this is SQL, and per the house law
  --     neither is evidence for the other.
  --
  -- SO: this arm escalates only a return NOBODY has confirmed — zero stamps, which is the state
  -- `incident_review` actually names (the dog is unaccounted for). A row where at least one party
  -- has said the dog is home keeps `active`, and therefore keeps its money path, and is ALARMED
  -- instead: both parties told once, no status move. That is arm ⓓ's own principle, three arms
  -- down and written by a later author for the same class of stuck two-sided confirmation —
  -- "what a stuck pickup handoff should become is a product decision (Sean's), not a clock's".
  --
  -- ⚠ NAMED RESIDUE, deliberately NOT closed here, and stated in FULL because the first draft of
  -- this paragraph named only half of it (cold review #7):
  --   ① a return NOBODY confirms still escalates at STRAND_AFTER, and is still a dead end if both
  --      parties stamp afterwards;
  --   ② AND THE ONE-STAMP ROW THIS ARM NOW PRESERVES HAS ITS OWN NEW TERMINAL. Runner stamps,
  --      owner never does: one notification at 2h, then permanent silence, `active` forever, the
  --      runner work-gated (0092) and unpaid. That is strictly better than the escalation it
  --      replaces — the money path SURVIVES, so a stamp on any later day still settles — but it
  --      is not bounded, and the honest word for the detection is HALF: `ops_gated_runners()`
  --      (0096 §7) lists the row, and the remedy it names, `force_return_tx`, **HAS NO CALLER
  --      ANYWHERE** — measured: `grep -rn force_return_tx` over `supabase/functions/`, `app/` and
  --      `scripts/` returns only two comment mentions in a deno test. No edge action, no ops
  --      console, no client. The only exit is a human typing SQL.
  -- Both need the same decision, and it is Sean's rather than a clock's (awaiting-sean §4): what,
  -- if anything, may a timer do with money. What this arm guarantees is smaller and checkable:
  -- **a run where at least one party has said the dog is home is never made unpayable by a
  -- clock.** An escalating alarm (rather than the one-shot) and an ops door for
  -- `force_return_tx` are the two follow-ups this creates.
  --
  -- ⚠ LOCK, THEN LOOK AGAIN — arm ⓒ's idiom (codex 0181 #3), applied here because the branch is
  -- now destructive and the race lands exactly on the defect being closed: a stamp committing
  -- between the candidate read and the UPDATE would escalate a row that had just become
  -- settleable. `skip locked` leaves a row a writer holds for the next tick rather than stalling
  -- a sweep that holds every lock arm ⓒ took (0180's lesson).
  -- ⚠ [cold review #3] THE CANDIDATE SET MUST DRAIN, and this arm is the first in the function
  -- whose rows do NOT leave it. 0183's arm ⓑ had neither `order by` nor `limit`, and that was safe
  -- there because every candidate was escalated and left the set by changing status. A ⓑ-② row
  -- never leaves: status stays `active`, `run_ended_at` stays set, `settlement_ready_at` stays
  -- null, and the one-shot check makes it silent on every later tick. Adding `limit c_batch` to a
  -- non-draining set with `order by b.id` — a v4 uuid, so an ARBITRARY but STABLE order — would
  -- select the same fifty lowest-uuid corpses every tick forever, and a new zero-stamp row sorting
  -- above them would never be escalated at all. Two changes, and they are independent:
  --   · `order by b.run_ended_at` — OLDEST FIRST, a meaningful order, so nothing can be
  --     permanently shadowed by rows that merely have smaller ids;
  --   · the alarmed rows are excluded from the CANDIDATE, not just skipped in the loop, which
  --     restores the drain: a row that has had its one-shot alarm is done with this arm.
  -- The same `not exists` still guards the insert under the lock (a candidate read is a snapshot).
  for r in
    select b.id
    from bookings b
    where b.status = 'active'
      and b.club_session_id is null
      and b.run_ended_at is not null
      and b.run_ended_at < now() - STRAND_AFTER
      and b.settlement_ready_at is null
      and not exists (select 1 from notifications nt
                      where nt.ref_id = b.id and nt.title = c_ret_title)
    order by b.run_ended_at
    limit c_batch
  loop
    begin
      select b.id, b.owner_id, b.runner_id, b.status, b.run_ended_at, b.settlement_ready_at,
             b.runner_confirmed_return_at, b.owner_confirmed_return_at, b.club_session_id
        into v_b from bookings b where b.id = r.id for update skip locked;
      if not found then
        raise notice 'sweep_run_end_recovery: strand % — row locked by a writer, left for the next tick', r.id;
        continue;
      end if;
      -- Every predicate of the candidate query, re-asserted on the LOCKED row.
      -- ⚠ [cold review #8] `club_session_id` is in this list because the comment SAID "every"
      -- and the first version omitted it — and 219's `0188-B4` pins this re-check by matching
      -- this exact string, so the pin would have inherited the gap. No live path re-parents a
      -- booking into a club session, so this is a comment made true rather than a hole closed;
      -- that distinction is the finding, and it is worth the one conjunct.
      if v_b.status <> 'active' or v_b.run_ended_at is null or v_b.settlement_ready_at is not null
         or v_b.club_session_id is not null then continue; end if;
      if v_b.run_ended_at >= now() - STRAND_AFTER then continue; end if;

      if v_b.runner_confirmed_return_at is not null or v_b.owner_confirmed_return_at is not null then
        -- ⓑ-② ONE SIDE HAS SAID THE DOG IS HOME. No status move, ever. Both parties told ONCE —
        -- one-shot by construction (arm ⓐ's idiom): a row with this title for this booking is an
        -- alarm already raised. The two bodies are NOT interchangeable: telling a party who has
        -- already stamped to "확인해주세요" is a lie about their own action (0092 §6's rule for
        -- `waiting_on`, which exists for exactly this sentence).
        if not exists (select 1 from notifications nt
                       where nt.ref_id = v_b.id and nt.title = c_ret_title) then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (v_b.owner_id, 'booking', c_ret_title,
                  case when v_b.owner_confirmed_return_at is null then c_ret_body_ask else c_ret_body_wait end,
                  v_b.id);
          if v_b.runner_id is not null then
            insert into notifications (profile_id, kind, title, body, ref_id)
            values (v_b.runner_id, 'booking', c_ret_title,
                    case when v_b.runner_confirmed_return_at is null then c_ret_body_ask else c_ret_body_wait end,
                    v_b.id);
          end if;
          raise notice 'sweep_run_end_recovery: booking % — 반환 확인이 한쪽만 된 채 % 경과: 양측 1회 통지, 상태 무이동 (0188 ⓑ-②)',
            v_b.id, STRAND_AFTER;
          n := n + 1;
        end if;
      else
        -- ⓑ-① NOBODY has confirmed the return. This is the state `incident_review` names, and
        -- 0083's escalation is reproduced here verbatim — same UPDATE, same two titles, same
        -- two bodies. A human has to look, and `ops_gated_runners` (0096 §7) is where they look.
        update bookings set status = 'incident_review' where id = v_b.id and status = 'active';
        -- [0193 §D, codex B5] `safety`, NOT `booking`. 0187's classifier files a booking row as
        -- disableable, so with 예약 알림 off this push — 「the dog is unaccounted for」 — was
        -- silenced. Classified at the WRITER, which is what codex asked for; §E's title entry is
        -- the belt that covers rows a pre-0193 tick already wrote as `booking`.
        -- ⚠ 0114:273-281 admits only kind='booking' from a booking PARTY. This is a definer owned
        -- by postgres, so no policy applies and `safety` is writable here — which is exactly why
        -- the client writers (api.ts) were left alone in 0189 and are still left alone.
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (v_b.owner_id, 'safety'::noti_kind, '귀가 확인이 필요해요',
                '러닝은 끝났는데 인계 확인이 없어요 — 담당자가 확인을 도와드릴게요', v_b.id);
        if v_b.runner_id is not null then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (v_b.runner_id, 'safety'::noti_kind, '귀가 확인이 필요해요',
                  '인계 확인이 되지 않아 담당자 확인으로 넘어갔어요 — 정산은 확인 뒤에 진행돼요', v_b.id);
        end if;
        n := n + 1;
      end if;
    exception when others then
      raise notice 'sweep_run_end_recovery: strand % — %', r.id, sqlerrm;
    end;
  end loop;
  -- ⓕ [0193] THE STRAND IS FINALLY TOLD TO SOMEBODY WHO CAN END IT (codex A1's detection half).
  --
  -- 0188 arm ⓑ-② is correct and it is not enough: it tells the two PARTIES once and then goes
  -- silent forever, and the parties are precisely the people who are already not acting. 0188's own
  -- header names the residue in full — 「one notification at 2h, then permanent silence, `active`
  -- forever, the runner work-gated (0092) and unpaid」 — and calls an ops door the follow-up it
  -- creates. This is that door's bell; `ops_resolve_return_tx` (§C-b) is the door.
  --
  -- 🔴 **NULL MEANS THE ARM DOES NOTHING, AND THAT IS THE SHIPPED STATE.** `return_strand_minutes`
  -- is Sean's ruling (queue item 23) and a deadline nobody chose is worse than no deadline: it
  -- would page an operator on a cadence invented by whoever typed the migration. Read fresh each
  -- tick so the flip needs no redeploy, and `is null` short-circuits before a single booking is
  -- read.
  --
  -- ⚠ TWO STATES, because a strand has two shapes and only one of them is `active`: a row nobody
  -- confirmed has already been escalated to `incident_review` by arm ⓑ-①, and that row is the
  -- WORSE one (0096 lets late stamps land and refuses to seal, so it cannot settle at all until an
  -- operator acts). It is identified by the FACTS it carries — a run that ended, no seal — never by
  -- a free-text reason, because a reason string is prose and this is the input to a money door.
  --
  -- ⚠ ONCE PER BOOKING, by arm ⓐ/ⓑ's idiom: a row with this title for this booking is a bell
  -- already rung, and the candidate query excludes it so the set DRAINS (cold review 0188 #3's
  -- lesson: a `limit` over a non-draining set shadows new rows forever). An EMPTY ROSTER writes
  -- nothing, so the arm retries every tick until somebody is provisioned — the same durable-PENDING
  -- shape as ⓓ/ⓔ, and the honest one: an escalation recorded as delivered when nobody received it
  -- is worse than an unmonitored state (0096 §4).
  select f.return_strand_minutes into v_strand_min from ops_flags f where f.id;
  if v_strand_min is not null then
    for r in
      select b.id
      from bookings b
      where b.club_session_id is null
        and b.status in ('active', 'incident_review')
        and b.run_ended_at is not null
        and b.settlement_ready_at is null
        and (b.status = 'incident_review'
             or not (b.runner_confirmed_return_at is not null and b.owner_confirmed_return_at is not null))
        and b.run_ended_at < now() - make_interval(mins => v_strand_min)
        and not exists (select 1 from notifications nt
                        where nt.ref_id = b.id and nt.title = c_strand_title)
      order by b.run_ended_at
      limit c_batch
    loop
      begin
        select b.id, b.owner_id, b.runner_id, b.status, b.run_ended_at, b.settlement_ready_at,
               b.runner_confirmed_return_at, b.owner_confirmed_return_at, b.club_session_id
          into v_b from bookings b where b.id = r.id for update skip locked;
        if not found then
          raise notice 'sweep_run_end_recovery: strand-ops % — row locked by a writer, left for the next tick', r.id;
          continue;
        end if;
        -- every predicate of the candidate query, re-asserted on the LOCKED row (arm ⓑ's law)
        if v_b.club_session_id is not null or v_b.run_ended_at is null
           or v_b.settlement_ready_at is not null then continue; end if;
        if v_b.status not in ('active', 'incident_review') then continue; end if;
        if (v_b.status is distinct from 'incident_review')
           and v_b.runner_confirmed_return_at is not null
           and v_b.owner_confirmed_return_at is not null then continue; end if;
        if v_b.run_ended_at >= now() - make_interval(mins => v_strand_min) then continue; end if;
        -- the candidate read was a snapshot; the one-shot guard is re-taken under the lock
        if exists (select 1 from notifications nt
                   where nt.ref_id = v_b.id and nt.title = c_strand_title) then continue; end if;
        insert into notifications (profile_id, kind, title, body, ref_id)
        select rc.profile_id, 'system'::noti_kind, c_strand_title, c_strand_body, v_b.id
          from ops_recipients_for(c_strand_ops_class) as rc(profile_id);
        get diagnostics v_ops = row_count;
        raise notice 'sweep_run_end_recovery: booking % — 반환이 %분 넘게 끝나지 않았다 (status=%, stamps=%/%): ops 수신자 %명 (%)',
          v_b.id, v_strand_min, v_b.status,
          (v_b.runner_confirmed_return_at is not null), (v_b.owner_confirmed_return_at is not null),
          v_ops,
          c_strand_ops_class || case when v_ops = 0 then ' — 명부가 비어 있어 아무에게도 가지 않았다 (다음 틱에 다시 시도)' else '' end;
        if v_ops > 0 then n := n + 1; end if;
      exception when others then
        raise notice 'sweep_run_end_recovery: strand-ops % — %', r.id, sqlerrm;
      end;
    end loop;
  end if;

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

  -- ⓖ [0224 §C] A CUSTODY THAT NEVER MOVED — `picked_up` with no start, `active` with no stop, past
  -- the thresholds Sean sets (NULL ⇒ it reads no booking). Its own function, locked and bounded
  -- there, with its own handler so a surprise in it cannot roll back arms ⓐ–ⓕ's work.
  n := n + _sweep_custody_strands();

  return n;
end $$;

-- THE ACL IS SET IN THIS FILE, not inherited (0116:636; `check-definer-acl.mjs`'s class).
revoke execute on function sweep_run_end_recovery() from public, anon, authenticated;
grant  execute on function sweep_run_end_recovery() to service_role;

comment on function sweep_run_end_recovery is
  '0083 §9 · 0181 ⓒ · 0182 ⓓ · 0183 ⓔ · 0188 ⓑ · 0193 ⓕ · 0201 §D · 0224 §D, and 0226 §A: arm ⓐ''s two
per-row writes — the parties'' 「정산을 확인하고 있어요」 alarm and the payout_due 「정산 미완료 — 확인 필요」
bell — each run in their own subtransaction, so one faulting row (a recipient held past the 2 s
lock_timeout, or anything else) is a NOTICE and a retry next tick instead of an abort that rolled back
every earlier notice and skipped arms ⓑ–ⓖ. The legs are siblings: either can fail without costing the
other. Everything else is 0224''s byte for byte (arm ⓐ still bells payout_due once per sealed row past
SEAL_ALARM_AFTER; arm ⓖ _sweep_custody_strands() still runs last). 257 0226-F1/F2 pin the isolation;
255/232/224/219/214/213/212 keep pinning the rest.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B _unsettled_charge_through — 0080 §F's debt predicate, cut at a mint instant
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 「Is this owner in debt NOW, counting only charges minted at or before `p_through`?」 The body below is
-- `owner_has_unsettled_charge`'s (0080 §F) copied BY SCRIPT with ONE conjunct added — the scope arms,
-- the server-minted rule and both debt shapes (failed; dispatched-pending older than an hour) are
-- evaluated at NOW, exactly as the money gate evaluates them. 257 `0226-H1` pins that the
-- comment-stripped source differs from 0080's by exactly that conjunct and that at 'infinity' the two
-- agree for every owner in the harness population; a later change to either reddens it until both move.
-- ⚠ A NEW definer (so the ACL below is its first), server-only like the gate it copies.
create or replace function _unsettled_charge_through(p_owner uuid, p_through timestamptz) returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from payments p
    join bookings b on b.id = p.booking_id
    where b.owner_id = p_owner
      and p.created_at <= p_through           -- [0226 §B] the ONE added conjunct: minted at or before
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
  )
$$;

revoke execute on function _unsettled_charge_through(uuid, timestamptz) from public, anon, authenticated;
grant  execute on function _unsettled_charge_through(uuid, timestamptz) to service_role;

comment on function _unsettled_charge_through is
  '0226 §B: owner_has_unsettled_charge (0080 §F) restricted to charges minted at or before p_through —
the debt predicate itself, evaluated now, plus one conjunct (p.created_at <= p_through). At ''infinity''
it equals owner_has_unsettled_charge. Read by generate_recurring_bookings'' pause dedupe as the
continuity witness: an earlier notice counts only while a charge that existed when it was written is
still unsettled. Server-only. 257 0226-H1 pins it against 0080''s source and over the population.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §C generate_recurring_bookings — the pause dedupe keys on the debt it was about
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0224 §H's body, copied BY SCRIPT; ONE edit, inside the ⓓ guard's subquery (one conjunct, two lines).
-- The money gates (`owner_has_unsettled_charge`, the card switch), the dog lock, the lock_timeout, the
-- ownership belt, the inserts and every string are 0224's byte for byte — the build script asserts
-- every other line identical. §0c says why this key and names its residue.
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
  end loop;
  return n;
end $$;

revoke execute on function generate_recurring_bookings() from public, anon, authenticated;

comment on function generate_recurring_bookings is
  '0080 §H (was 0026): 반복 예약 자동 생성 크론 — 72h 창, 같은 러너 우선(가용성 재검증), 겹침 가드
+ [0080 §0-ter #3] 결제 게이트 둘 + [0111] 복사 시점 소유권 재확인 + [0180] 강아지별 xact 락 —
+ [0224 §H] the pause notice (「반복 예약 일시 중지」) is sent at most once per 24 h per owner per episode
+ [0226 §C] and an episode ends when the series produces a booking again OR — for a debt block — when
every charge that existed at the last notice has been paid (the witness is _unsettled_charge_through).
Title, body and NULL ref unchanged. 255 0224-C1 and 257 0226-C2/C3/C4 pin it.';

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — apply-time SHAPE only (behaviour is suite 257's — 0131-G4's lesson)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare
  v_bad text := '';
  fn text;
  v_src text;
begin
  foreach fn in array array['sweep_run_end_recovery()', 'generate_recurring_bookings()',
                            '_unsettled_charge_through(uuid,timestamptz)'] loop
    if to_regprocedure('public.' || fn) is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if not exists (select 1 from pg_proc p where p.oid = to_regprocedure('public.' || fn)
                    and p.prosecdef and 'search_path=public, pg_temp' = any(coalesce(p.proconfig, '{}')))
      then v_bad := v_bad || ' ' || fn || ': not a definer with the in-body search_path;'; end if;
    if has_function_privilege('anon', to_regprocedure('public.' || fn), 'execute')
       or has_function_privilege('authenticated', to_regprocedure('public.' || fn), 'execute')
      then v_bad := v_bad || ' ' || fn || ': a client role can execute (server-only);'; end if;
  end loop;
  foreach fn in array array['sweep_run_end_recovery', 'generate_recurring_bookings', '_unsettled_charge_through'] loop
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = fn;
    if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(' || fn || ');'; end if;
  end loop;
  if v_bad <> '' then raise exception '0226 VERIFY failed:%', v_bad; end if;
  raise notice '0226 VERIFY ok — three server-only definers, in-body search_path, sources present';
end $$;
