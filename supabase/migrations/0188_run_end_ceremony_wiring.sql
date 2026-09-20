-- 0188 — ⑪ + ⑫ 런엔드 의식(儀式)을 실제로 태우는 슬라이스의 서버 몫.
--        러닝 종료 → 양측 반환 봉인 → 정산. 서버는 이미 있었고, 제품 호출자가 0명이었다.
--
-- ═══ §0 WHAT THIS SLICE IS, AND WHAT THIS FILE IS ════════════════════════════════════════
-- RULED and ASSIGNED 2026-08-13 (`docs/decisions/awaiting-sean.md` §5) to a session that ended.
-- The machinery has been shipped and INERT ever since: `end_run_tx` (0083 §3) had zero callers,
-- `settle-run` flipped `active → completed` directly, `runner_work_gate` (0092) could only block
-- on states the marketplace path never produced, and `confirm_return_tx` answered a completed
-- booking `{stamped:false, settled:true, unchanged:true}` — so a client button drawn today would
-- have drawn a seal that never happened (`docs/labs/RULINGS-2026-08-19-journey.md:83-89`).
--
-- The re-sequencing this slice builds, end to end:
--   ① runner stops  → edge `transition-booking { action: 'end_run' }` → `end_run_tx` freezes
--      km/duration/reason/note/trace and stamps `bookings.run_ended_at`. Status STAYS `active` —
--      「끝났지만 아직 돌려주지 않았다」 is exactly the state ⑫'s work gate reads (0092 §3).
--   ② the owner is asked (「반환 확인 요청」), and the runner is work-gated from the same instant.
--   ③ both parties stamp → edge `{ action: 'confirm_return' }` → `confirm_return_tx`.
--   ④ THE SECOND STAMP SETTLES, inside the same locked transaction, because the edge brings a
--      price. This is 0083's own designed shape, finally used: `_settle_sealed_run` is the one
--      settlement primitive and `p_quote` exists precisely so that a caller with no identity of
--      its own (service_role, the edge) may supply one while a client-role caller may not
--      (`quote_from_client`). Nothing new was needed in SQL for it.
--
-- 🔴 WHO TRIGGERS SETTLE — decided, and the decision is why this file is small. NOT the client
-- (a phone that dies after its tap must not strand a settlement) and NOT a new SQL re-drive
-- (`sweep_run_end_recovery` arm ⓐ still cannot settle, and that is CORRECT: a SQL settle would
-- skip `collectAfterSettle`, so the day charging flips it would commit a settled run with no
-- `payments` row. 0083 §0f already names the right shape — a pg_net dispatcher to an EDGE
-- function — and it is a follow-up with its own contract). The answer is: **the edge action that
-- carries the stamp also carries the price**, so stamp and settlement are ONE transaction on the
-- server and there is no window between them for anything to crash into.
--
-- 🔴 WHAT GUARDS `settle-run`'s DIRECT PATH — nothing new, and that is the point. Once the client
-- ends through `end_run_tx`, `run_ended_at` is stamped, and `settle_run_tx`'s §6-ⓑ gate refuses
-- with `return_not_sealed` until `settlement_ready_at` exists. The guard has been shipped since
-- 0083; this slice is what ARMS it. The remaining hole is 0083's deliberate old-client arm
-- (`run_ended_at is null`), closed by Sean setting `ops_flags.return_seal_since` AFTER the build
-- reaches devices — a production write, Sean's, named in this slice's report and not done here.
-- Pinned both ways by 219 (0188-A2 / 0188-A3).
--
-- ⚠ CHARGING IS FLAG-GATED OFF, so 「the return ceremony lands before charging flips」 is satisfied
-- BY CONSTRUCTION rather than by sequencing discipline: `collectAfterSettle` answers
-- `skipped_not_live` and writes nothing while `ops_flags.payments_live_since` is NULL.
--
-- ⚠ CLUBS ARE UNTOUCHED. `end_run_tx`, `confirm_return_tx`, `_settle_sealed_run` and both sweep
-- arms below all refuse or exclude `club_session_id is not null`; the club two-phase stop (0168)
-- is a different door and this slice does not reach it. Pinned: 219 0188-C1.
--
-- ═══ §A THE ONE SQL CHANGE — and the defect that forced it ═══════════════════════════════
-- `sweep_run_end_recovery` is recreated (0183's body is the latest definition) with arms ⓐ, ⓒ,
-- ⓓ and ⓔ reproduced BYTE-IDENTICALLY — measured, not asserted, and the measurement is stated
-- with its BOUNDARY and its UNIT so anyone can reproduce it:
--
--     from the literal line `  -- ⓒ [0181] THE ASK THAT NEVER ARRIVED`
--     up to (not including) the line `end $$;`
--     → 14,650 BYTES, byte-for-byte equal between 0183 and this file (14,355 characters)
--
-- Everything before that, apart from arm ⓑ, differs by exactly twelve ADDED constant lines.
-- ⚠ An earlier draft of this header said "14,364 bytes" with no boundary. That number was a
-- CHARACTER count over a slightly different span, labelled bytes — a cold reviewer measured
-- 14,652 on their own boundary and could not reproduce mine, which is the correct outcome for a
-- number quoted without the span it was taken over. A measurement's write-up outlives the thing
-- measured (CLAUDE.md), so it has to carry enough to be re-run.
--
-- The handoff-recovery chain (0181-0185) is not disturbed; suites 212-216 are its detector.
--
-- Arm ⓑ changes, and the reason is written where the arm is. In one sentence: this slice is the
-- first thing that can hand that arm a real row, and on a row where a party has already said the
-- dog is home its escalation makes the run PERMANENTLY UNPAYABLE while freeing nobody. It now
-- escalates only a return NOBODY confirmed, and alarms the rest without moving state.
--
-- ⚠ The existing pins on arm ⓑ (119 R12/R16 · 132 E1/E2 · 133) all escalate ZERO-STAMP fixtures —
-- checked before writing, not after — so they sit in the zone where the old rule and the new one
-- AGREE and stay green for a true reason. A pin that only agrees proves nothing about a predicate
-- change, so 219 puts `0188-B1`/`0188-B2` in the DIVERGENCE zone (exactly one stamp present) and
-- mutation-verifies them by reverting the conjunct.

-- ── the recreated sweep ───────────────────────────────────────────────────────────────────
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
        insert into notifications (profile_id, kind, title, body, ref_id)
        values (v_b.owner_id, 'booking', '귀가 확인이 필요해요',
                '러닝은 끝났는데 인계 확인이 없어요 — 담당자가 확인을 도와드릴게요', v_b.id);
        if v_b.runner_id is not null then
          insert into notifications (profile_id, kind, title, body, ref_id)
          values (v_b.runner_id, 'booking', '귀가 확인이 필요해요',
                  '인계 확인이 되지 않아 담당자 확인으로 넘어갔어요 — 정산은 확인 뒤에 진행돼요', v_b.id);
        end if;
        n := n + 1;
      end if;
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

-- THE ACL IS SET IN THIS FILE, not inherited. `create or replace` preserves an ACL only where the
-- function already exists; on an apply where it does not (a partial prior apply, a rebuilt
-- environment) this statement is a plain CREATE and a SECURITY DEFINER is born PUBLIC-executable
-- (0116:636). `check-definer-acl.mjs` exists for exactly this class and this file is its 82nd.
revoke execute on function sweep_run_end_recovery() from public, anon, authenticated;
grant execute on function sweep_run_end_recovery() to service_role;

-- ═══ §B [cold review #2] THE GRANT IS THE DOOR, AND THIS SLICE IS WHAT ARMS IT ═════════════
-- `confirm_return_tx` is granted to `authenticated` (0096:184) and lives in `public`, which
-- PostgREST exposes — `api.ts` already proves a client-role RPC to a `public` definer works, by
-- calling `runner_work_gate` that way. So any signed-in party can POST
-- `/rest/v1/rpc/confirm_return_tx {p_booking, p_side}` with the shipped anon key and their own
-- JWT. The party gate passes (they ARE that side), and a client may not bring a price
-- (`quote_from_client`) — so if theirs is the SECOND stamp the row is SEALED and NOT SETTLED.
--
-- 🔴 That state was INERT before this slice and is armed by it. `confirm_return_tx` requires
-- `run_ended_at`, and until the run-end ceremony had a client nothing ever stamped it on a
-- marketplace booking, so the RPC raised `run_not_ended` for every reachable row. It now
-- succeeds, and there is no product repair afterwards: both stamps exist, so the confirm CTA is
-- gone from BOTH new screens by construction, `runner/run.tsx` no longer calls `settle-run`, and
-- arm ⓐ can only raise an alarm. The runner is unpayable and nothing in the app can fix it.
--
-- ⚠ THE FIX IS THE REVOKE, NOT A RAISE, and the difference matters. The obvious alternative —
-- raise when `v_both and v_may_settle and p_quote is null` — would delete a DESIGNED capability:
-- 0083 §6 states that a client-class caller "may seal — the stamp is its own truthful act — and
-- settlement then belongs to the server call that follows", and suite 133 exists precisely to
-- detect the sealed-but-unsettled row (119 R12/R16 pin it too). A server caller must still be
-- able to seal now and settle later. What must stop is a PHONE being the stamp that seals.
--
-- After this, every party stamp goes through `transition-booking { action: 'confirm_return' }`,
-- which is service_role and always brings a price — so 0096's remedy ("either party may
-- confirm_return_tx") is unchanged in substance and now reads "through the app". This converts
-- "protected by nobody calling it" into "protected by not being granted" (the grant-is-not-a-door
-- law, applied in the closing direction).
-- ⚠ 119 `R13`'s ACL matrix lists this function in its POSITIVE control (authenticated MUST be
-- able to execute). That pin's asserted behaviour legitimately changes here and is updated in the
-- same slice; `0188-D1` is the pin that now owns the new property.
revoke execute on function confirm_return_tx(uuid, text, jsonb) from authenticated;

comment on function sweep_run_end_recovery is
  '0083 §9 + 0181 ⓒ + 0182 ⓓ + 0183 ⓔ + [0188 ⓑ] — 귀가/인계 청소부. ⓐ 씰은 찍혔는데 정산이 안 된 행을
NOTICE로 드러내고 6시간 뒤 양측에 1회 알린다(상태 무이동). **ⓑ [0188] 반환 좌초: 아무도 확인하지 않은
행(스탬프 0개)만 incident_review로 승격하고, 한쪽이라도 "개가 집에 왔다"고 말한 행은 절대 옮기지 않고
양측에 1회만 알린다 — 승격은 돈의 막다른 길이고(0066:56은 incident_review → refund_pending 하나뿐,
_settle_sealed_run은 active 전용), 0096 이후 뒤늦은 양측 스탬프가 가능해지면서 그 조합이 "개를 데려다
줬고 양측이 확인했는데 영원히 지급 불가"가 된다. 게다가 승격은 아무도 풀어주지 않는다: 0092의 작업
게이트는 스탬프 두 개를 읽고 incident_review도 잡는다.** ⓒ 한쪽만 찍힌 인계의 사라진 확인 요청을 사이클
식별자로 1회 재발송. ⓓ 30분 넘게 한쪽뿐인 인계는 양측+ops에 1회(상태 무이동). ⓔ ops 로스터가 비어
있어 밀린 ops 승격을 매 틱 재시도. 한 틱만 돈다(어드바이저리 try-lock). service_role 전용';

-- ── VERIFY — the apply refuses a body that does not carry this slice's shape ───────────────
-- Runs at APPLY time and pins nothing by itself: `check-definer-acl`'s lesson is that source
-- checked at apply is protected exactly until someone recreates the function, so 219 owns the
-- standing pins and this block owns "the file that just ran did what it says".
-- ⚠ Comments are stripped before matching. `prosrc` is source PLUS our own prose, and this file
-- documents the very predicate it is checking for — un-stripped, the check would pass on a
-- function that merely EXPLAINS the fix (the comment-matching class, CLAUDE.md).
do $$
declare v_src text; v_bad text := '';
begin
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'sweep_run_end_recovery';
  if v_src is null then raise exception '0188 VERIFY: NO-SOURCE(sweep_run_end_recovery)'; end if;
  -- the narrowing itself: the escalation branch is reached only with BOTH stamps absent
  if (v_src ~ 'runner_confirmed_return_at is not null or v_b\.owner_confirmed_return_at is not null')
     is not true then v_bad := v_bad || ' 반환 스탬프 분기 없음;'; end if;
  -- Exactly ONE escalation STATEMENT, and it is inside that branch's else.
  -- ⚠ The pattern is the assignment, not the word: `incident_review` also appears in `c_dead`,
  -- the fourteen-status deny-list arms ⓒ/ⓓ/ⓔ share — so a bare word match counts three and this
  -- check fired on its own first run. A detector that cannot tell an escalation from a deny-list
  -- entry is measuring the vocabulary, not the behaviour.
  if (select count(*) from regexp_matches(v_src, 'set status = ''incident_review''', 'g')) <> 1
    then v_bad := v_bad || ' incident_review 승격 구문이 1개가 아님;'; end if;
  -- the locked re-check (the precondition that makes the branch's input trustworthy)
  if (v_src ~ 'for update skip locked') is not true then v_bad := v_bad || ' 잠금 재확인 없음;'; end if;
  -- the alarm title the client routes on
  if (v_src ~ '반환 확인이 멈춰 있어요') is not true then v_bad := v_bad || ' 알림 제목 없음;'; end if;
  -- and the four arms we promised not to disturb are still in the body
  if (v_src ~ 'handoff_ops_alerted_at') is not true then v_bad := v_bad || ' ⓔ 팔 유실;'; end if;
  if (v_src ~ 'pg_try_advisory_xact_lock') is not true then v_bad := v_bad || ' 잡 락 유실;'; end if;
  if v_bad <> '' then raise exception '0188 VERIFY failed:%', v_bad; end if;
  -- the definer's own shape — checked here because a recreated definer that loses `search_path`
  -- or gains PUBLIC execute is the class 98 H1 and check-definer-acl exist for.
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname='public' and p.proname='sweep_run_end_recovery'
                   and p.prosecdef and array_to_string(p.proconfig,',') like '%search_path=public, pg_temp%')
    then raise exception '0188 VERIFY: definer/search_path shape lost'; end if;
  if has_function_privilege('authenticated', 'public.sweep_run_end_recovery()', 'execute')
    then raise exception '0188 VERIFY: authenticated may execute the sweep'; end if;
end $$;
