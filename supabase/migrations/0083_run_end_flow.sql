-- ═══ 0083: the run-end flow — 귀가 becomes a SERVER INVARIANT, not a screen behaviour ═══
--
-- Source of truth: `docs/plans/run-end-flow-plan.md` v4 (Sean ruled §9 on 2026-08-13).
-- Doctrine it implements, already written at `0078_route_catalog.sql:6-7`:
--   접근(커스터디, 무과금) → 루프(THE run, 과금 구간) → 귀가(커스터디, 동결).
--
-- ═══ §0 WHY THIS FILE EXISTS — three false claims the plan's two adversarial rounds killed ═══
-- (plan §0-bis; codex's verdict on v1/v2 was "reject the plan as written")
--   ① "Ceasing trace writes freezes the charge." FALSE — `actual_km` comes from the client's
--      in-memory `gpsKm` (`run.tsx:193`), never from the trace. A doorstep settle would have
--      billed the walk home.
--   ② "`settle_run_tx` needs no change." codex: *"the most dangerous sentence in the plan."*
--      `settle-run` claims ANY `active` booking (`0028:60`) and checks neither `run_ended_at` nor
--      any return stamp — an old client, the `reachedTarget` effect, or a direct API call settles
--      mid-귀가 and pays out while the dog is still on the leash. **That bypass exists today.**
--   ③ `runs.ended_at` currently means SETTLEMENT time. Delay settlement to the doorstep and a run
--      that stopped at 09:58 — before a 10:00 `payments_live_since` cutover — gets charged
--      because it settled at 10:08. That breaks 0080's "no retroactive charging" law from the
--      other direction.
-- codex's closing sentence is this file's design brief: *"this design converts '귀가 is unbilled'
-- from a server invariant into a promise that one version of one screen will behave correctly."*
--
-- ═══ §0b MAP OF THE FILE ═══
--   §1  columns          — the stamps, the heartbeat, the frozen payout quote, settled_at
--   §2  protection       — INSERT-side guard (new) + `_guard_run_cols` bites at run-stop
--   §3  end_run_tx       — THE freeze (plan §1). One transaction, idempotent, marketplace-only
--   §4  append gates     — `append_run_event` / `append_run_photo` reject after the stop (§1)
--   §5  custody_ping     — the non-billable 귀가 heartbeat (plan §5)
--   §6  the seal         — `settle_run_tx` gated + ONE settlement primitive + the two entries
--   §8  LA               — 귀가 phase, and the two running-only consumers guarded (plan §4d/§5)
--   §9  janitor          — durable recovery + the 2h stranding escalation (plan §3/§7)
--   (§7 is deliberately ABSENT. Three things this file hands to another owner, each named in the
--    header rather than left to be found in an incident: §0f the sweep anchor · §0g a runner
--    payout price in SQL · §0h a marketplace incident-settlement exit)
--
-- ═══ §0c WHAT THIS FILE DOES **NOT** DO (0073/0075 lesson: an unstated scope reads as a seal) ═══
-- - It does not touch any edge function. `settle-run`'s gate BEHAVIOUR (the "앱을 업데이트해
--   주세요" refusal, plan §2 / §9 D-r4①) is a TypeScript half that reads the three distinct error
--   codes this file raises (`return_not_sealed`, `run_not_ended`, `frozen_measurement_mismatch`);
--   the follow-on slice owns it. ⚠ But the LAW those messages express is enforced HERE and does
--   not wait for that slice: §6-ⓔ refuses a settlement whose km/end_reason are not the frozen
--   ones, so the client half can only change what the runner READS, never what is paid.
-- - It does not price anything. `settle_run_tx`'s money arithmetic is reproduced byte-faithful and
--   the runner payout is still computed by the pricing code, at settle, from the numbers §3 froze.
--   No fare, rate or basis rule is written in this file — deliberately, because the fault-based
--   basis (Sean's G1 ruling) changed four times in one day and belongs where it can be pinned by
--   the money suite that owns it.
-- - It does not change `compute_owner_charge`, the mints, the debt derivation, the retry ladder,
--   `payments_reconciliation`, or any 0081/0082 object.
-- - It does not add a booking status or a transition-map edge. `active → incident_review` (§9) is
--   already legal (`0047:40`).
-- - It does not fix the owner-cancel-during-귀가 expression (plan §7: "Do not add the edge") nor
--   the four scheduled-capacity consumers (plan §4's capacity gap) — client/edge slices.
--
-- ═══ §0d WHOSE TEXT EACH RE-CREATED OBJECT WAS BUILT ON (concurrent-session hygiene) ═══
-- Five shipped objects are re-created here. For each: the version on origin that this file
-- copied, and whether the change EXTENDS it (a condition added to the same body) or REPLACES it.
--   · `_guard_run_cols`        ← 0079 §1 (pace-state session). EXTENDS: one freeze condition + two
--                                 column names in the protected list; every other line byte-equal.
--   · `_owner_la_trace_tg`     ← 0079 §5. EXTENDS: one silence guard. 103 L7-L13 pin the rest.
--   · `owner_la_sweep_stale`   ← 0079 §5. EXTENDS: one join predicate on arm ①, plus a second
--                                 loop of its own. Arm ① is otherwise byte-equal (103 L11/L12).
--   · `settle_run_tx`          ← 0028. EXTENDS: the seal gate + the two timestamp lines. The money
--                                 arithmetic is byte-faithful. Verified against the payments
--                                 session's 0084 before writing: that file does not touch it.
--   · `append_run_event` / `append_run_photo` ← 0018. **REPLACES** — reported rather than done
--                                 quietly: they are one-statement `language sql` bodies, and a
--                                 phase gate that raises cannot be added to a single UPDATE
--                                 without rewriting them in plpgsql. The `where exists` party
--                                 check becomes an explicit `not_run_runner` raise; nothing else
--                                 about what they write changes.
-- Everything else in this file is new and owned here.
--
-- Merged and disjoint: 0081 (club money gates), 0082 (route ladder). Note for 0082:
-- `promote_route_from_run` sets `routes.checked_at` from `runs.ended_at` — under §6 that is now
-- the SERVICE-STOP date rather than the settlement date, which is the more honest value for
-- "when was this course walked" and needs no edit there.
-- Not yet merged: `0084_g1_ops_cutover.sql` (Sean's money rulings). It re-creates
-- `compute_owner_charge`, `mint_settle_charge_intent` and `payments_reconciliation`; this file
-- re-creates none of those. Its G1 arm is 🔴 CONFLICTED on origin
-- (`docs/decisions/g1-abort-charge-basis.md` — Sean answered twice, differently), so nothing here
-- or in `119_run_end_suite.sql` encodes or asserts a G1 amount: every money figure is read
-- through `compute_owner_charge` at assertion time, and whichever way that ruling lands, not one
-- run-end pin moves.
--
-- ═══ §0f THE ONE THING THIS FILE OPENS AND DOES NOT CLOSE — read before the cutover ═══
-- `sweep_settled_without_payments` (0080 §G) mints the invariant-#1 charge for every booking whose
-- run has an `ended_at` and no payments row. That predicate was written when `ended_at` meant
-- SETTLEMENT. §6 makes it mean the STOP — so from this migration onward the sweep can see a run
-- that stopped and **has not been returned yet**, and mint a charge for a dog still on the leash.
-- That is codex #3's scenario B, and it is a hole this file creates.
-- It is NOT fixed here, deliberately: 0080 owns that function and the payments session is
-- modifying it in the same wave, so re-creating it from this file would silently revert their
-- work while every harness pin still passed. The fix is one predicate, in their file, on their
-- schedule:
--       and rn.settled_at is not null        -- (0083 §1: did money actually happen)
-- `runs.settled_at` exists as of this migration precisely so that line can be written. Do NOT use
-- `bookings.status` (§0-ter #11 / 116 C8 — a settled booking legitimately moves on) and do NOT use
-- `ledger_items` presence (0080 §K writes a ledger row for a CANCELLED booking, which is not a
-- run). The same substitution is the honest form of `owner_has_unsettled_charge`'s
-- `runs.ended_at is not null` scope arm (0080 §F), for the same reason.
-- ⚠ **`ops_flags.payments_live_since` must not be flipped until that predicate lands.** While it
-- is NULL the sweep returns 0 before reading anything, so the hole is unreachable today — which
-- is the whole of why this is a handoff and not an emergency. 119 R11 pins the property the fix
-- depends on (`settled_at` is written by settlement and by nothing else) rather than pretending
-- the sweep is already anchored.
--
-- ═══ §0g THE SECOND HANDOFF — a true settlement re-drive needs a price, and SQL has none ═══
-- Sean's G1 ruling made the RUNNER's payout basis depend on `end_reason` (`runner_personal` loses
-- its distance component entirely). That pricing lives in TypeScript, so §9's recovery arm can
-- report a sealed-but-unsettled booking but cannot settle it, and `_settle_sealed_run` takes the
-- price as an argument instead of deriving it. Two ways to close that, in preference order:
--   ① a `compute_runner_payout(booking, end_reason, actual_km)` in SQL, sibling to 0080 §D's
--      `compute_owner_charge` and pinned by the same suite. Then `_settle_sealed_run` drops its
--      `p_quote` parameter, the §9 sweep becomes a real idempotent re-drive, and the fault table
--      exists once instead of twice. This is the end-state 0080 §D already argued for ("a money
--      rule that lives only in a Deno function is a money rule no pin can protect").
--   ② failing that, a pg_net dispatcher in 0080 §K's shape that wakes the settle path.
-- Until one of them lands, a settlement that dies between the seal and the ledger is repaired by
-- the 2h escalation and a human — visible, bounded, and slower than it should be. Said out loud
-- here rather than left for somebody to discover in an incident.
--
-- ═══ §0h THE THIRD HANDOFF — `incident_review` has no marketplace money exit ═══
-- §9's arm ⓑ moves a stranded 귀가 to `incident_review`, which is the state the product already
-- uses for "a human has to look at this". For a CLUB booking that is a complete answer:
-- `club_incident_settle` (`0072 §B`) adjudicates the three outcomes and moves real money. For a
-- MARKETPLACE booking it is currently a one-way door:
--   · every money entry point requires `status = 'active'` — `settle_run_tx`'s atomic claim,
--     `_settle_sealed_run`, `confirm_return_tx`, `force_return_tx`;
--   · the transition map allows `incident_review → refund_pending` and nothing else (`0066:56`);
--   · `club_incident_settle` cannot be reached: it calls `_club_require_v2()` and requires a
--     `club_incidents` row, a locked `club_sessions` row and a `club_incident_subjects` mapping
--     naming the booking — none of which exists for a marketplace run.
-- So today the only thing arm ⓑ can safely escalate is a booking where NOBODY said the dog is
-- home: there is no settlement to protect, and a refund/ops decision is the honest end. That is
-- the predicate the arm now carries (`settlement_ready_at is null`), and it is the whole reason
-- a sealed row gets an alarm instead of a status change.
-- What is still MISSING, named here rather than left to be discovered in an incident:
--   **a marketplace incident-settlement exit** — the sibling of `club_incident_settle` for a
--   booking with no club: an ops-called, party-gated, idempotent RPC that reads the frozen
--   measurement, takes the same three outcomes (refund_full · settle_measured · pay_full), writes
--   `ledger_items` for the runner and a payments adjustment for the owner, and moves the booking
--   OUT of `incident_review`. It needs (a) the runner-payout price — the same thing §0g needs, so
--   the two handoffs share a dependency; (b) an `incident_review → completed` edge in the
--   transition map, or an explicit terminal of its own; (c) an ops actor model outside the club
--   host/case-owner one. Until it exists, every marketplace `incident_review` booking is a manual
--   database job, which is exactly why §9 escalates as few of them as it possibly can.
--
-- ═══ §0e DOCTRINE (0059 money-path list) ═══
-- self-contained migration · byte-faithful reproduction of the latest definition (0057 §2) ·
-- every definer carries `set search_path = public, pg_temp` IN THE BODY (98 H1 — ALTER-applied
-- config is reset by `create or replace`, and `settle_run_tx` / the two append RPCs got their
-- pg_temp from 0055's ALTER, so recreating them without it would silently unseal three definers)
-- · party gate before state gate · no derived cache columns · mutation-proven pins
-- (`119_run_end_suite.sql`, R1-R14).

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §1 COLUMNS — every fact this flow needs, and who is allowed to write it
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Plan §1 (the freeze), §3 (timestamp semantics), §5 (the heartbeat), §7 (schema completeness —
-- `return_forced_by` was referenced by v2 and never declared).

alter table bookings
  add column run_ended_at               timestamptz,
  add column runner_confirmed_return_at timestamptz,
  add column owner_confirmed_return_at  timestamptz,
  add column return_forced_by           text
    check (return_forced_by in ('runner', 'owner', 'ops')),
  add column return_forced_at           timestamptz,
  add column return_force_reason        text,
  add column return_force_evidence      jsonb,
  add column return_eligible_at         timestamptz,
  add column settlement_ready_at        timestamptz,
  add column custody_last_seen_at       timestamptz;

comment on column bookings.run_ended_at is
  '0083 §1 — THE service-stop moment (러닝 종료), stamped by end_run_tx ONLY. Its presence is the
phase machine (plan §4): active + null = running · active + not null = 귀가(homeward). Server-
stamped: the client cannot write it (0058 deny-all on UPDATE, §2''s trigger on INSERT)';
comment on column bookings.runner_confirmed_return_at is
  '0083 §1 — the runner''s 인계 확인 at the door. Written only by confirm_return_tx/force_return_tx';
comment on column bookings.owner_confirmed_return_at is
  '0083 §1 — the owner''s confirmation on the live/meetup intermediary surface. Sean''s D-r1
ruling: THIS interaction is the evidence, and the runner is paid once the dog is returned — so
this stamp (or a recorded force) is what releases settlement. Server-written only';
comment on column bookings.return_forced_by is
  '0083 §1 (plan §7) — who used the release valve: runner | owner | ops. NULL = a genuine
two-sided return. Non-null is the second way settlement becomes permissible';
comment on column bookings.return_forced_at is
  '0083 §1 — when the force was recorded (server clock, on a locked row — never an app timer)';
comment on column bookings.return_force_reason is
  '0083 §1 — the actor''s stated reason. Recorded immutably: force_return_tx refuses to overwrite
an existing force, so the first resolution is the one that stands';
comment on column bookings.return_force_evidence is
  '0083 §1 (plan §7) — the evidence payload: pickup-radius proof from the custody channel, an
owner interaction, or an ops override. REQUIRED by force_return_tx — a force with no evidence is
an assertion, and this is the row a dispute is read from';
comment on column bookings.return_eligible_at is
  '0083 §1 — when the force first BECAME permissible (run_ended_at + the §9 D-r1 grace). Recorded
alongside the force so a dispute can see the clock the server used, not the one the app showed';
comment on column bookings.settlement_ready_at is
  '0083 §1 (plan §3, codex #4) — the DURABLE fact that the return is sealed. Written in the same
locked transaction as the second stamp (or the force), immediately before settlement. It exists
so that a crash between "sealed" and "settled" is REPAIRABLE: §9''s sweep re-drives every row
that carries it and never reached completed. Never a cache of anything derivable';
comment on column bookings.custody_last_seen_at is
  '0083 §1 (plan §5) — the NON-BILLABLE custody heartbeat, written by custody_ping. Homeward LA
freshness reads THIS, never runs.trace: the trace deliberately stops at the run''s end, so a
trace-based staleness check would push "위치가 갱신되지 않았어요" into every 귀가. Structurally
unable to reach the run row — that is the entire point of a separate column';

alter table runs add column settled_at timestamptz;

comment on column runs.settled_at is
  '0083 §1 (plan §3, codex #3) — when MONEY MOVED. Written by settle_run_tx. The companion half of
the timestamp fix: runs.ended_at now means the service STOP, always, so 0080''s cutover
comparison (`runs.ended_at >= payments_live_since`) can no longer be dragged forward by a late
doorstep settlement. A pre-cutover stop stays free forever, whenever its return lands';
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §2 PROTECTION — the stamps are server-stamped, on INSERT as well as UPDATE
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Plan §7 ("Schema completeness"): the UPDATE side is already sealed — `_guard_booking_cols`
-- (0058 §3) is deny-all for `authenticated`/`anon`, so every column added in §1 is covered the
-- moment it exists, and reproducing that function here would change nothing. The INSERT side is
-- NOT: `0002_rls.sql:95` lets an owner insert their own booking (`status = 'draft'`), and no
-- trigger has ever looked at what an insert carries. A draft born with
-- `owner_confirmed_return_at` already set is a forged return stamp waiting for a run to reach it.
--
-- Deliberately a LIST and not 0058's deny-all: an owner's draft legitimately carries a dozen
-- columns, so the shape of this guard is 0057 §4's blacklist, restricted to the columns whose
-- only honest writer is the server. The two handoff stamps join it for the same reason they are
-- in the UPDATE guard (`0057:399-403` — a forged handoff confirmation makes `confirm_handoff`
-- announce "펫보험 적용" without the owner's real confirmation); their insert-side hole is closed
-- here because it is the same hole, one statement earlier.
-- Role judgement is `current_user`, exactly as 0057/0058 argue: service_role edge functions and
-- definer RPCs are not `authenticated`/`anon` and never enter the branch.
create or replace function _guard_booking_insert_cols() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.run_ended_at               is not null
    or new.runner_confirmed_return_at is not null
    or new.owner_confirmed_return_at  is not null
    or new.return_forced_by           is not null
    or new.return_forced_at           is not null
    or new.return_force_reason        is not null
    or new.return_force_evidence      is not null
    or new.return_eligible_at         is not null
    or new.settlement_ready_at        is not null
    or new.custody_last_seen_at       is not null
    or new.owner_confirmed_handoff_at is not null
    or new.runner_confirmed_handoff_at is not null
    then
      raise exception 'booking_protected_columns'
        using detail = '인계·귀가 확인 시각은 서버만 기록해요 — 새 예약에 미리 담을 수 없어요';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists _guard_booking_insert on bookings;
create trigger _guard_booking_insert before insert on bookings
  for each row execute function _guard_booking_insert_cols();

comment on function _guard_booking_insert_cols is
  '0083 §2 (plan §7): the INSERT half of the stamp seal. 0058 §3 closed UPDATE with a deny-all,
but owners may INSERT drafts (0002:95) — so a client could be born holding a return/handoff
confirmation. Blacklist rather than deny-all, because a draft legitimately carries most columns';

-- ── the run row closes at the STOP, not at the settlement ──────────────────────────────
-- 0079 §1's definition of `_guard_run_cols`, reproduced under 0057 §5 discipline with exactly ONE
-- addition: `run_ended_at is not null` joins the full-freeze condition (codex #7).
-- WHY the FULL freeze and not merely re-listing the protected columns: after the stop there is no
-- legitimate client write to this row AT ALL. The billable window is closed (plan §1), the final
-- trace was committed inside `end_run_tx`, and 귀가 rides `custody_last_seen_at` + broadcast —
-- a path structurally unable to reach `runs`. Leaving events/photos/trace open would leave
-- exactly the hole §4 closes on the RPC side: a 응가 event stamped after stopping, which
-- `settle_run_tx` rewards with miles (`0028:88-103`).
-- The exception name is distinct on purpose: `run_frozen_after_settlement` and
-- `run_frozen_after_end` are different facts and a client that maps them to one sentence is
-- telling the runner the run was settled when it was not.
create or replace function _guard_run_cols() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
declare v_status text; v_ended timestamptz;
begin
  if current_user in ('authenticated', 'anon') then
    -- ① 정산 후 동결 — 부킹이 종단이면 클라 쓰기 전면 거부 (호출자=해당 부킹 러너라 RLS로 정당히 읽힘)
    select b.status::text, b.run_ended_at into v_status, v_ended
      from bookings b where b.id = new.booking_id;
    if v_status in ('completed', 'incident_review') then
      raise exception 'run_frozen_after_settlement'
        using detail = '정산·인시던트 종료된 러닝 기록은 변경할 수 없어요';
    end if;
    -- [0083 §2] ①-b 종료 후 동결 — 러닝이 끝나면(귀가 구간) run 행은 통째로 닫힌다
    if v_ended is not null then
      raise exception 'run_frozen_after_end'
        using detail = '러닝이 끝나 기록이 동결됐어요 — 귀가 구간에는 러닝 기록을 바꿀 수 없어요';
    end if;
    -- ② 클라 쓰기 가능 표면 = 라이브 append 3종(events/photos/trace)뿐 — 그 외 변경 거부
    if new.actual_km          is distinct from old.actual_km
    or new.duration_sec       is distinct from old.duration_sec
    or new.avg_pace_sec_per_km is distinct from old.avg_pace_sec_per_km
    or new.end_reason         is distinct from old.end_reason
    or new.condition_note     is distinct from old.condition_note
    or new.started_at         is distinct from old.started_at
    or new.ended_at           is distinct from old.ended_at
    or new.booking_id         is distinct from old.booking_id
    or new.pace_suggest_sec   is distinct from old.pace_suggest_sec   -- [0079] 스냅샷 동결
    or new.settled_at         is distinct from old.settled_at         -- [0083] 정산 시각
    then
      raise exception 'run_protected_columns'
        using detail = '거리·시간·페이스·종료사유는 서버(정산)만 기록해요 — 클라는 events/photos/trace만';
    end if;
  end if;
  return new;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §3 end_run_tx — THE freeze (plan §1)
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- One transaction that closes the run and freezes every settlement input: the final trace, the
-- distance, the duration, the reason, the condition note, `runs.ended_at = the service stop`,
-- the payout quote, and `bookings.run_ended_at`. After it commits, the run-mutation window is
-- shut (§2, §4) and 귀가 begins — a custody phase that cannot touch a single billable number.
--
-- ⚠ WHAT IS FROZEN IS THE MEASUREMENT, NOT THE MONEY — and that distinction is the whole of
-- this file's money argument. An earlier draft also froze a computed payout quote
-- ({base, distance_pay, addon_pay, guarantee, fee}, built from settle-run/handler.ts:76-87). It
-- was removed on the day Sean's G1 ruling made the runner's basis DEPEND on `end_reason`
-- (`runner_personal` loses its distance component entirely) — a frozen quote built from the old
-- single formula would have paid a runner for distance the ruling says they do not get, on
-- numbers WE froze. The boundary plan §1 defends is "no metre walked after the stop reaches the
-- money"; freezing `actual_km` / `duration_sec` / `end_reason` / `ended_at` achieves that
-- completely, and freezing a formula's OUTPUT defends nothing extra while rotting the next time
-- pricing moves. Pricing is computed at settle by the code that owns it.
--
-- ⚠ SERVICE_ROLE ONLY. `p_actual_km` is the number both ledgers are computed from; a client that
-- could call this directly would freeze its own basis without ever crossing the edge function
-- that authenticates it. Same boundary `settle_run_tx` has had since 0020, one step earlier.
--
-- ⚠ THE END_REASON WHITELIST IS NARROWER THAN THE ENUM, and this is the newest money finding
-- (payments session, 2026-08-13, on top of Sean's G1 ruling). Under that ruling `incident`
-- charges the owner NOTHING and hands the money question to a case review (`0072`); a runner who
-- could freeze `end_reason = 'incident'` at the stop would therefore hand their own client a free
-- run and pre-empt a review nobody opened. `owner_forced` is excluded for the mirror-image
-- reason: it charges the owner exactly the PLANNED distance (0080 §D's D2 arm) and pays the
-- runner a 50% guarantee, so a runner able to declare it is a runner able to bill for distance
-- that did not happen. Both are legitimate outcomes — they are simply not RUNNER-declarable, and
-- neither reaches a booking through a run-stop. An owner-forced end arrives through
-- transition-booking, and an incident through the incident path; both are follow-on slices, and
-- each needs its own server entry point rather than a hole in this one.
create or replace function end_run_tx(
  p_booking         uuid,
  p_actual_km       numeric,
  p_duration_sec    int,
  p_end_reason      text,
  p_condition_note  text,
  p_trace           jsonb
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b        record;
  v_now    timestamptz := now();
  v_claim  uuid;
  v_uid    uuid := auth.uid();
  v_km     numeric;
begin
  -- ── party gate before state gate (repo law) ────────────────────────────────────────────
  select bk.id, bk.runner_id, bk.owner_id, bk.status::text as status, bk.km,
         bk.club_session_id, bk.run_ended_at
    into b
  from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;
  -- A client-role caller can never reach here (the function is service_role-only), but when a
  -- caller identity IS present it must be the assigned runner: the edge function passes the
  -- runner's JWT through in the tests and in any future definer chain.
  if v_uid is not null and v_uid is distinct from b.runner_id then
    raise exception 'not_run_runner';
  end if;
  if b.runner_id is null then raise exception 'not_run_runner'; end if;

  -- ── marketplace only (plan §7: "clubs are out of scope" is not a server guard) ─────────
  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;

  -- ── idempotence: a second stop is not an error, it is the same stop (plan §1) ──────────
  -- Checked under the row lock, so the claim below can only ever confirm this answer.
  if b.run_ended_at is not null then
    return jsonb_build_object('unchanged', true, 'run_ended_at', b.run_ended_at);
  end if;
  if b.status <> 'active' then raise exception 'not_active'; end if;

  -- ── input sanity at the boundary the numbers are frozen at ─────────────────────────────
  -- 0028 ④'s rule, moved to where it now matters: after this statement nobody can correct these
  -- numbers, so the validity band has to hold HERE. The band itself is settle-run's
  -- (`handler.ts:66` — planned×2+2, the payout-fraud bound) and the 50% completion floor is
  -- Sean's 2026-07-29 incentive gate (`handler.ts:72`).
  if p_end_reason not in ('completed', 'dog_condition', 'owner_request', 'runner_personal') then
    raise exception 'end_reason_not_runner_declarable';
  end if;
  -- ⚠ ROUNDED TO THE STORED SCALE FIRST (`runs.actual_km` is numeric(5,2) — 0001:239). The freeze
  -- must operate on the number that will actually BE frozen, because §6-ⓔ refuses a settlement
  -- whose km differs from the stored one: freezing 3.2473829 into a column that holds 3.25 and
  -- then reporting 3.2473829 back to the caller would make the caller's honest echo a mismatch.
  v_km := round(p_actual_km, 2);
  if v_km is null or v_km < 0 or v_km > 100 then raise exception 'invalid_km'; end if;
  if v_km > coalesce(b.km, 0) * 2 + 2 then raise exception 'km_out_of_band'; end if;
  if p_duration_sec is not null and p_duration_sec < 0 then raise exception 'invalid_duration'; end if;
  if p_end_reason = 'completed' and v_km < coalesce(b.km, 0) * 0.5 then
    raise exception 'completed_needs_half_distance';
  end if;
  if p_end_reason = 'dog_condition' and coalesce(btrim(p_condition_note), '') = '' then
    raise exception 'condition_note_required';   -- §8-bis: a money control on a fabricated constant
  end if;
  -- ── freeze the run row FIRST, stamp the booking second ────────────────────────────────
  -- Order is load-bearing: §8's homeward LA trigger fires on the `run_ended_at` UPDATE and reads
  -- the frozen numbers off `runs`. Stamping first would push a 귀가 banner carrying blanks.
  -- The upsert mirrors 0028 ③ (a settle with no runs row must not lose the run); `started_at` is
  -- honestly back-derived from the measured duration exactly as that migration argued.
  insert into runs (booking_id, started_at, ended_at, actual_km, duration_sec,
                    avg_pace_sec_per_km, end_reason, condition_note, trace)
  values (
    p_booking,
    case when p_duration_sec is not null then v_now - make_interval(secs => p_duration_sec) end,
    v_now, v_km, p_duration_sec,
    case when p_duration_sec is not null and v_km > 0 then round(p_duration_sec / v_km)::int end,
    p_end_reason::end_reason, p_condition_note,
    coalesce(p_trace, '[]'::jsonb)
  )
  on conflict (booking_id) do update set
    ended_at            = excluded.ended_at,
    actual_km           = excluded.actual_km,
    duration_sec        = excluded.duration_sec,
    avg_pace_sec_per_km = excluded.avg_pace_sec_per_km,
    end_reason          = excluded.end_reason,
    condition_note      = excluded.condition_note,
    started_at          = coalesce(runs.started_at, excluded.started_at),
    -- the FINAL trace commits inside this transaction (plan §1); a null argument means the
    -- caller had nothing new, never "erase what the run recorded".
    trace               = case when p_trace is null then runs.trace else p_trace end;

  update bookings set run_ended_at = v_now
   where id = p_booking and run_ended_at is null
  returning id into v_claim;
  if v_claim is null then
    -- Unreachable under the row lock taken above; kept because "0 rows ⇒ unchanged, never an
    -- error" is the contract this function promises its caller (plan §1).
    return jsonb_build_object('unchanged', true, 'run_ended_at', (
      select bk.run_ended_at from bookings bk where bk.id = p_booking));
  end if;

  return jsonb_build_object(
    'unchanged', false,
    'run_ended_at', v_now,
    'actual_km', v_km,
    'end_reason', p_end_reason);
end $$;
revoke execute on function end_run_tx(uuid, numeric, int, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function end_run_tx(uuid, numeric, int, text, text, jsonb) to service_role;

comment on function end_run_tx is
  '0083 §3 (plan §1): THE freeze. Validates the assigned runner + active + marketplace, commits
the final trace, freezes actual_km/duration_sec/end_reason/condition_note and runs.ended_at =
the SERVICE STOP, then stamps bookings.run_ended_at. The MEASUREMENT is frozen; the money is not
(the payout basis is end_reason-dependent since Sean''s G1 ruling and belongs to the pricing
code — see the header). Idempotent: a second stop returns {unchanged:true}, never an error.
end_reason is restricted to the four a runner may declare. service_role only';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §4 the atomic append RPCs get the same phase gate (plan §1, verified gap)
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- 0018's two functions check ONLY `b.runner_id = auth.uid()` — verified by reading them. So a
-- runner can stamp a 응가 event AFTER stopping, and `settle_run_tx` pays +30 miles to both
-- parties for it (`0028:88-103`). During 귀가 that is a reward for a walk nobody measured.
--
-- Two changes beyond the phase gate, both deliberate:
--   ⓐ a non-runner now gets `not_run_runner` instead of silence. 0018's `update … where exists`
--      shape made every refusal a successful no-op, which is exactly the "silent catch → happy
--      UI" the repo's honesty law forbids. Nothing in the client depends on the silence
--      (grep: no caller inspects the return), and a failure that looks like a success is how a
--      lost 응가 도장 goes unnoticed — the very race 0018 was written to fix.
--   ⓑ `set search_path = public, pg_temp` in the BODY. 0018 wrote only `public`; 0055's ALTER
--      added pg_temp, and `create or replace` resets ALTER-applied config (98 H1's whole point),
--      so recreating them without it would silently unseal two definers.
create or replace function append_run_event(p_booking uuid, p_event jsonb) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare b record;
begin
  select bk.runner_id, bk.run_ended_at into b from bookings bk where bk.id = p_booking;
  if b.runner_id is null or b.runner_id is distinct from auth.uid() then
    raise exception 'not_run_runner';
  end if;
  if b.run_ended_at is not null then
    raise exception 'run_ended'
      using detail = '러닝이 끝난 뒤에는 기록을 추가할 수 없어요 — 귀가 구간이에요';
  end if;
  update runs set events = coalesce(events, '[]'::jsonb) || jsonb_build_array(p_event)
   where booking_id = p_booking;
end $$;

create or replace function append_run_photo(p_booking uuid, p_url text) returns text[]
language plpgsql security definer set search_path = public, pg_temp as $$
declare b record; v_photos text[];
begin
  select bk.runner_id, bk.run_ended_at into b from bookings bk where bk.id = p_booking;
  if b.runner_id is null or b.runner_id is distinct from auth.uid() then
    raise exception 'not_run_runner';
  end if;
  if b.run_ended_at is not null then
    raise exception 'run_ended'
      using detail = '러닝이 끝난 뒤에는 사진을 추가할 수 없어요 — 귀가 구간이에요';
  end if;
  update runs set photos = coalesce(photos, '{}') || p_url
   where booking_id = p_booking
  returning photos into v_photos;
  return v_photos;
end $$;

grant execute on function append_run_event(uuid, jsonb), append_run_photo(uuid, text) to authenticated;

comment on function append_run_event is
  '0083 §4 (was 0018): 러닝 이벤트 원자 append. [0083] run_ended_at이 찍힌 뒤에는 거부 — 정지 후
찍은 응가 도장에 settle_run_tx가 마일을 주던 구멍(0028:88). 남의 예약도 침묵 대신 not_run_runner';
comment on function append_run_photo is
  '0083 §4 (was 0018): 러닝 사진 원자 append. [0083] 종료 후 거부 + 비당사자는 not_run_runner';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §5 custody_ping — the non-billable heartbeat (plan §5)
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- The honesty counterpart to §8's sweep guard. Guarding `owner_la_sweep_stale` on
-- `run_ended_at is null` stops the false "위치가 갱신되지 않았어요" during every 귀가 — but it
-- also means NOTHING could report a genuinely dead 귀가, because the custody channel is a
-- realtime broadcast and Postgres cannot see it (codex #9: a runner whose phone dies leaves the
-- owner's lock screen reading 집으로 가는 중 forever).
-- So the custody path writes one column, and one column only. This function CANNOT touch `runs`,
-- cannot move a number that money is computed from, and cannot resurrect a frozen run — which is
-- what "explicitly non-billable path" has to mean in a schema rather than in a screen.
create or replace function custody_ping(p_booking uuid) returns timestamptz
language plpgsql security definer set search_path = public, pg_temp as $$
declare b record; v_now timestamptz := now();
begin
  select bk.runner_id, bk.status::text as status into b from bookings bk where bk.id = p_booking;
  if b.runner_id is null or b.runner_id is distinct from auth.uid() then
    raise exception 'not_run_runner';
  end if;
  -- Custody exists from pickup to the door. Outside that there is no dog to be responsible for,
  -- and a heartbeat on a finished booking would keep a dead LA looking alive.
  if b.status not in ('picked_up', 'active') then raise exception 'not_in_custody'; end if;
  update bookings set custody_last_seen_at = v_now where id = p_booking;
  return v_now;
end $$;
revoke execute on function custody_ping(uuid) from public, anon;
grant execute on function custody_ping(uuid) to authenticated;

comment on function custody_ping is
  '0083 §5 (plan §5): the 귀가 heartbeat. Runner-only, custody-phase-only, and structurally
incapable of touching runs — it writes bookings.custody_last_seen_at and nothing else. Homeward
LA freshness reads that column; the trace is not consulted, because the trace correctly stopped';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §6 THE SEAL — settlement becomes impossible until the dog is home
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Plan §2's precondition, enforced server-side on a locked row:
--     settle is permitted iff  run_ended_at is not null
--                         AND  (both return stamps present OR a recorded force)
--
-- ── ⓐ the cutover switch for the OLD-CLIENT arm (plan §2, §9 D-r4①) ───────────────────
-- The gate has two halves and only one of them can be unconditional today.
--   · A booking that WENT THROUGH `end_run_tx` is gated immediately and forever: `run_ended_at`
--     is set, so settlement requires the seal. Nothing can turn that off.
--   · A booking that never stopped — the old-client bypass, where a deployed app calls
--     `settle-run` on an `active` booking directly — cannot be refused unconditionally the day
--     this migration applies: the clients that do it are on phones, and refusing them before the
--     new build ships would strand real runs mid-flight. That is precisely the hazard §9 D-r4
--     names ("it does not retroactively help builds already on phones").
-- So the second half is a MOMENT, not a boolean, and it is 0080 §0c's idiom applied to a
-- non-money law: `ops_flags.return_seal_since` ships NULL, and once Sean sets it, every
-- marketplace run STARTED at or after it must go through the seal. Runs already in flight finish
-- under the old rule by construction, and the refusal carries its own error code so the client
-- can say "앱 업데이트가 필요해요" rather than a generic failure or a silent no-op.
alter table ops_flags add column if not exists return_seal_since timestamptz;

comment on column ops_flags.return_seal_since is
  '0083 §6 — the moment the RETURN SEAL becomes mandatory for runs that have not been ended
through end_run_tx (the old-client arm of plan §2''s gate). NULL = only new-flow bookings
(run_ended_at set) are gated, which is every booking the shipped client creates once the run-end
build lands. Set it AFTER that build reaches devices (§9 D-r4 sequencing); runs started before
the moment finish under the old rule. A moment rather than a boolean for the same reason
payments_live_since is one: a flip must not strand a run that is already on the leash';

-- ── ⓑ settle_run_tx, recreated: gated, and honest about which timestamp means what ─────
-- 0028's body reproduced under 0057 §2 discipline. FIVE changes, and not one of them touches the
-- money arithmetic (the ledger row, the miles gates, the patch bonus, the runner stats, the
-- completion-rate formula, the drop roll and the notification are byte-faithful):
--   ⓐ header `search_path = public` → `public, pg_temp` (98 H1 — 0055's ALTER put it there and
--      `create or replace` would drop it).
--   ⓑ THE GATE (plan §2), on the row this function already locks.
--   ⓒ `ended_at` is no longer overwritten with `now()` on the conflict path. It means the
--      SERVICE STOP (plan §3) and `end_run_tx` already wrote it; refreshing it at settlement is
--      exactly the bug that would charge a pre-cutover run because it settled post-cutover
--      (codex #3). A run with no stop stamp still gets `now()`, which is today's behaviour for
--      every legacy and club path.
--   ⓓ `settled_at = now()` — the fact that used to be conflated with ⓒ, recorded separately.
--   ⓔ **THE FREEZE IS ENFORCED HERE, ON THE PATH THAT SHIPS.** ⓑ only asks WHETHER the dog is
--      home; it never asked whether the numbers the caller brought are the numbers the stop
--      froze. And `settle-run/handler.ts:113-124` does not go through `_settle_sealed_run` (the
--      one place that reads the frozen row) — it calls THIS function with `p.actual_km` /
--      `p.end_reason` straight off the HTTP body. So the attack that survived every gate above
--      was: freeze 3.2km/`completed`, seal both sides, then POST `actual_km: 9.9,
--      end_reason: 'owner_request'`. The seal passes (the dog IS home), the runner is paid on
--      9.9km plus the `owner_request` 50% guarantee, `runs` is rewritten to match, and
--      `compute_owner_charge`'s D2 arm then bills the OWNER the full PLANNED distance. Every
--      metre walked home and every reason swap reached both ledgers through the client's JSON.
--      Two halves, because they defend different things:
--        · a MISMATCH RAISES (`frozen_measurement_mismatch`). It has to raise rather than
--          silently substitute: the money is computed OUTSIDE this function (handler.ts:97-110,
--          from the very numbers being refused) and arrives as five already-computed ints, so
--          accepting the row while quietly correcting the measurement would pay a 9.9km ledger
--          onto a 3.2km run — a worse lie than the one being closed.
--        · and the frozen columns are NOT REWRITTEN even so. Belt and braces on the two inputs
--          that move no money (`duration_sec`, `condition_note`): refusing on those would risk
--          the deadlock plan §1 names in red (a run that can never settle = a runner never
--          paid), while preserving them costs nothing and keeps the row the stop's row.
--      Scale note: `runs.actual_km` is `numeric(5,2)` (`0001:239`), so the comparison is made at
--      the STORED scale — §3 rounds to that scale before freezing, and this rounds the caller's
--      number the same way before comparing. Comparing raw would refuse a client that echoed
--      back its own 3.2473829 and strand the run forever, which is the deadlock again.
create or replace function settle_run_tx(
  p_booking uuid,
  p_actual_km numeric,
  p_duration_sec int,
  p_end_reason text,
  p_condition_note text,
  p_base int,
  p_distance_pay int,
  p_addon_pay int,
  p_guarantee int,
  p_fee int
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_owner uuid;
  v_runner uuid;
  v_route uuid;
  v_claimed int;
  v_is_full boolean := (p_end_reason = 'completed');
  v_has_poop boolean := false;
  v_total_runs int;
  v_drop jsonb := null;
  v_roll float;
  v_miles int;
  v_profile uuid;
  v_course_runs int;
  v_club uuid;                 -- [0083]
  v_run_ended timestamptz;     -- [0083]
  v_ready timestamptz;         -- [0083]
  v_seal_since timestamptz;    -- [0083]
  v_started timestamptz;       -- [0083]
  v_fz_km numeric;             -- [0083 ⓔ]
  v_fz_reason text;            -- [0083 ⓔ]
begin
  -- [0028 ④] 입력 새니티 — 돈 계산 입력은 서버 경계에서 한 번 더
  if p_actual_km is null or p_actual_km < 0 or p_actual_km > 100 then
    raise exception 'invalid_km';
  end if;
  if p_duration_sec is not null and p_duration_sec < 0 then
    raise exception 'invalid_duration';
  end if;

  select owner_id, runner_id, route_id, club_session_id, run_ended_at, settlement_ready_at
    into v_owner, v_runner, v_route, v_club, v_run_ended, v_ready
  from bookings where id = p_booking for update;
  if v_owner is null then
    raise exception 'not_found';
  end if;

  -- ── [0083 §6] THE RETURN SEAL (plan §2) ────────────────────────────────────────────────
  -- Clubs keep their own custody machinery (`session_custody_transfer`, 0045) and are out of this
  -- flow's scope by contract, so the gate is marketplace-only — stated as a predicate here rather
  -- than as a sentence in a plan (plan §7).
  if v_club is null then
    if v_run_ended is not null then
      if v_ready is null then
        -- The run stopped and the dog is not home. This is the bypass codex found: today this
        -- function pays the runner out mid-귀가.
        raise exception 'return_not_sealed'
          using detail = '아직 인계가 확인되지 않았어요 — 강아지가 집에 도착한 뒤 정산돼요';
      end if;
    else
      select f.return_seal_since into v_seal_since from ops_flags f where f.id;
      if v_seal_since is not null then
        select r.started_at into v_started from runs r where r.booking_id = p_booking;
        if coalesce(v_started, now()) >= v_seal_since then
          -- An old client settling a run it never ended. Distinct code on purpose (§9 D-r4①):
          -- the client renders "앱 업데이트가 필요해요", never a generic failure, never a no-op.
          raise exception 'run_not_ended'
            using detail = '러닝 종료 기록이 없어요 — 앱을 최신 버전으로 업데이트해주세요';
        end if;
      end if;
    end if;
  end if;

  -- ── [0083 §6-ⓔ] THE FREEZE, ENFORCED (plan §1/§2, codex minimum bar #3) ────────────────
  -- Once the stop is stamped, the client's numbers cannot change what is paid or charged. The
  -- shipping caller (`settle-run/handler.ts`) hands us its own `actual_km`/`end_reason`; if they
  -- are not the frozen ones, the price it computed from them is not this run's price either, so
  -- the only honest answer is a refusal. See ⓔ in the header for why this raises rather than
  -- substitutes, and why the comparison is made at the stored scale.
  if v_run_ended is not null then
    select rn.actual_km, rn.end_reason::text into v_fz_km, v_fz_reason
      from runs rn where rn.booking_id = p_booking;
    if round(p_actual_km, 2) is distinct from v_fz_km
       or p_end_reason is distinct from v_fz_reason then
      raise exception 'frozen_measurement_mismatch'
        using detail = '러닝 종료 때 기록된 거리·사유로만 정산할 수 있어요';
    end if;
  end if;

  -- 원자 클레임 — active에서만 completed로 (중복 정산 락, 기존 로직 그대로)
  update bookings set status = 'completed' where id = p_booking and status = 'active';
  get diagnostics v_claimed = row_count;
  if v_claimed = 0 then
    raise exception 'not_active';
  end if;

  -- run 기록 마감 ([0028 ①] 이넘 캐스트 · [0028 ③] upsert — start 이벤트 유실 시에도 기록 보존)
  -- [0083 ⓒⓓ] ended_at은 **서비스 정지 시각**이므로 이미 있으면 덮어쓰지 않는다. 돈이 움직인
  -- 시각은 settled_at이 따로 기록한다 (plan §3).
  insert into runs (booking_id, started_at, ended_at, actual_km, duration_sec, avg_pace_sec_per_km, end_reason, condition_note, settled_at)
  values (
    p_booking,
    case when p_duration_sec is not null then now() - make_interval(secs => p_duration_sec) else null end,
    now(), p_actual_km, p_duration_sec,
    case when p_duration_sec is not null and p_actual_km > 0 then round(p_duration_sec / p_actual_km)::int end,
    p_end_reason::end_reason, p_condition_note, now()
  )
  on conflict (booking_id) do update set
    ended_at = coalesce(runs.ended_at, excluded.ended_at),   -- [0083] 정지 시각 보존
    settled_at = now(),                                       -- [0083] 돈이 움직인 시각
    -- [0083 ⓔ] 동결된 러닝(정지 스탬프 있음)은 정산이 측정값을 **다시 쓰지 않는다**. 위 게이트가
    -- 거리·사유 불일치를 이미 거부하므로 그 둘은 어차피 같은 값이고, 돈을 움직이지 않는
    -- duration_sec·condition_note는 거부(=영구 미정산 위험) 대신 여기서 조용히 보존된다.
    -- 정지 스탬프가 없는 행(레거시·클럽 경로)은 0028 그대로 excluded가 이긴다.
    actual_km = case when v_run_ended is null then excluded.actual_km else runs.actual_km end,
    duration_sec = case when v_run_ended is null then excluded.duration_sec else runs.duration_sec end,
    avg_pace_sec_per_km = case when v_run_ended is null then excluded.avg_pace_sec_per_km
                               else runs.avg_pace_sec_per_km end,
    end_reason = case when v_run_ended is null then excluded.end_reason else runs.end_reason end,
    condition_note = case when v_run_ended is null then excluded.condition_note
                          else runs.condition_note end,
    started_at = coalesce(runs.started_at, excluded.started_at);

  -- 원장 (돈은 서버만 쓴다)
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip, remaining_guarantee, platform_fee)
  values (v_runner, p_booking, p_base, p_distance_pay, p_addon_pay, 0, p_guarantee, p_fee);

  -- 응가 도장 여부 (러닝 이벤트)
  select exists (
    select 1 from runs, jsonb_array_elements(coalesce(events, '[]'::jsonb)) e
    where booking_id = p_booking and e->>'kind' = 'poop'
  ) into v_has_poop;

  -- 인센티브 게이트 — '완주'만 마일·러닝 카운트·드랍 (기존 독트린 그대로)
  if v_is_full then
    insert into miles_ledger (profile_id, delta, reason, ref_id) values
      (v_runner, 50, 'run_complete', p_booking),
      (v_owner, 50, 'run_complete', p_booking);
    if v_has_poop then
      insert into miles_ledger (profile_id, delta, reason, ref_id) values
        (v_runner, 30, 'poop_bonus', p_booking),
        (v_owner, 30, 'poop_bonus', p_booking);
    end if;

    -- 패치 승급 보너스 (0025) — 코스 누적이 정확히 10/25가 된 당사자에게
    -- [0028 ②] '완주'만 카운트: status='completed'는 조기 종료 정산도 포함하므로
    -- runs.end_reason='completed' 조인이 진짜 완주 기준 (인센티브는 완주만)
    if v_route is not null then
      for v_profile in select distinct unnest(array[v_runner, v_owner]) loop
        select count(*) into v_course_runs from bookings b
        join runs r on r.booking_id = b.id and r.end_reason = 'completed'
        where b.route_id = v_route and b.status = 'completed'
          and (b.owner_id = v_profile or b.runner_id = v_profile);
        if v_course_runs = 10 then
          insert into miles_ledger (profile_id, delta, reason, ref_id)
          values (v_profile, 200, 'patch_gold', p_booking);
        elsif v_course_runs = 25 then
          insert into miles_ledger (profile_id, delta, reason, ref_id)
          values (v_profile, 500, 'patch_master', p_booking);
        end if;
      end loop;
    end if;
  end if;

  -- 러너 스탯 — total_km은 실주행이니 항상, total_runs는 완주만
  update runners set
    total_runs = total_runs + (case when v_is_full then 1 else 0 end),
    total_km = coalesce(total_km, 0) + p_actual_km
  where profile_id = v_runner
  returning total_runs into v_total_runs;

  -- [0028 ⑤] completion_rate 실화 — 0001 정책 주석 그대로: 러너 개인 사유 종료만 반영
  -- (dog_condition/owner_* 무영향). 완주 / (완주 + runner_personal). 모수 0이면 null 유지.
  update runners set completion_rate = sub.rate
  from (
    select case when count(*) = 0 then null
      else round(count(*) filter (where r.end_reason = 'completed')::numeric / count(*), 3) end as rate
    from runs r join bookings b on b.id = r.booking_id
    where b.runner_id = v_runner and r.end_reason in ('completed', 'runner_personal')
  ) sub
  where profile_id = v_runner;

  -- 드랍 판정 + 롤 — 10회 픽 우선, 5회 미니 (settle-run JS 롤과 동일 확률)
  if v_is_full and v_total_runs % 10 = 0 then
    v_drop := jsonb_build_object('kind', 'pick',
      'contents', jsonb_build_object('options', jsonb_build_array('boost', 'miles', 'gear')));
  elsif v_is_full and v_total_runs % 5 = 0 then
    v_miles := 500 + floor(random() * 700)::int;
    v_roll := random();
    v_drop := jsonb_build_object('kind', 'mini', 'contents',
      jsonb_build_object('miles', v_miles)
      || case when v_roll < 0.10 then jsonb_build_object('card', '드랍 카드')
              when v_roll < 0.15 then jsonb_build_object('gear', '기어 교환권')
              else '{}'::jsonb end);
  end if;
  if v_drop is not null then
    -- [0028] jsonb ->> 는 text — drop_type 이넘 명시 캐스트
    insert into drops (runner_id, run_count_at, kind, contents)
    values (v_runner, v_total_runs, (v_drop->>'kind')::drop_type, v_drop->'contents');
  end if;

  insert into notifications (profile_id, kind, title, body, ref_id)
  values (v_owner, 'booking', '러닝 완료',
          round(p_actual_km, 2)::text || 'km 러닝이 끝났어요 — 리포트를 확인하세요', p_booking);

  return jsonb_build_object('total_runs', v_total_runs, 'drop', v_drop->>'kind');
end $$;

revoke execute on function settle_run_tx(uuid, numeric, int, text, text, int, int, int, int, int) from public, anon, authenticated;

comment on function settle_run_tx is
  '0083 §6 (was 0028): 정산 원자 트랜잭션 — 금액 계산·원장·마일·패치·스탯·드랍 전부 0028 그대로.
[0083] ⓑ 귀가 씰 게이트: 마켓플레이스 예약은 run_ended_at이 찍혔으면 settlement_ready_at 없이는
return_not_sealed로 거부하고, ops_flags.return_seal_since 이후 시작된 러닝은 종료 기록 없이 부르면
run_not_ended로 거부한다(구 클라 — "앱 업데이트가 필요해요"). ⓒ ended_at은 서비스 정지 시각이라
덮어쓰지 않는다. ⓓ 돈이 움직인 시각은 settled_at. ⓔ 동결 강제: 정지 스탬프가 있으면 호출자가 들고 온
거리·사유가 동결값과 다를 때 frozen_measurement_mismatch로 거부하고(금액은 이 함수 바깥에서 그 숫자로
계산돼 들어오므로 조용히 바꿔치기하면 9.9km 원장이 3.2km 러닝에 붙는다), on conflict도 동결된 측정값을
덮어쓰지 않는다 — settle-run이 _settle_sealed_run을 거치지 않고 이 함수를 직접 부르기 때문에
"클라 금융 입력 무시"는 여기서 지켜져야 한다';

-- ── ⓒ THE settlement primitive — one implementation, three callers, zero copies ─────────
-- codex #4: "both stamped → settle-eligible" is not an implementation. If the second stamp
-- commits and the process dies, nothing repairs `active + both stamps + no ledger`. So:
--   · the second stamp calls THIS, inside its own locked transaction (atomic);
--   · `settlement_ready_at` is written first and is durable, so §9's sweep can re-drive a row
--     whose settlement never happened (recoverable);
--   · settlement is never implemented separately in confirm_return_tx, force_return_tx, a sweep
--     or a client path — all four call this function and none of them contains a second copy.
-- A CONCURRENT LOSER gets idempotent success, not a raw `not_active`: it blocks on the row lock,
-- and by the time it reads, the winner's outcome is committed — so it VERIFIES that outcome
-- (completed + settled_at + a ledger row) and reports it. A settlement that half-happened is the
-- one answer this function will not give: it raises instead.
--
-- ⚠ `p_quote` IS AN ARGUMENT AND IS NEVER STORED. The runner's payout basis depends on
-- `end_reason` since Sean's G1 ruling, so it is priced by the code that owns pricing, at settle,
-- from the FROZEN measurement — which is why this parameter exists and why nothing in this file
-- computes a fare. Its provenance is gated by the two entry points below: only a caller with no
-- identity of its own (the edge function, service_role) may supply one; a client-role caller
-- seals and stops. See §0f for what still has to be built before this becomes a true re-drive.
create or replace function _settle_sealed_run(p_booking uuid, p_quote jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b record; r record; v_tx jsonb; v_has_ledger boolean; v_has_settled boolean;
begin
  if p_quote is null
     or jsonb_typeof(p_quote->'base') <> 'number'
     or jsonb_typeof(p_quote->'distance_pay') <> 'number'
     or jsonb_typeof(p_quote->'addon_pay') <> 'number'
     or jsonb_typeof(p_quote->'guarantee') <> 'number'
     or jsonb_typeof(p_quote->'fee') <> 'number' then
    raise exception 'settle_quote_malformed';
  end if;
  select bk.id, bk.status::text as status, bk.club_session_id,
         bk.run_ended_at, bk.settlement_ready_at
    into b
  from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;

  -- ① idempotence BEFORE the state gate (110 S3's law): "already done" is not a failure.
  if b.status = 'completed' then
    select r2.settled_at is not null into v_has_settled from runs r2 where r2.booking_id = p_booking;
    select exists (select 1 from ledger_items li where li.booking_id = p_booking) into v_has_ledger;
    if coalesce(v_has_settled, false) and v_has_ledger then
      return jsonb_build_object('settled', true, 'unchanged', true);
    end if;
    -- completed with no ledger / no settled_at is a torn settlement. Reporting success here would
    -- tell a caller the runner was paid when the row says otherwise.
    raise exception 'settlement_inconsistent';
  end if;
  if b.status <> 'active' then raise exception 'not_active'; end if;

  -- ② the seal itself. Both are re-read under the lock rather than trusted from the caller.
  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;
  if b.run_ended_at is null then raise exception 'run_not_ended'; end if;
  if b.settlement_ready_at is null then raise exception 'return_not_sealed'; end if;

  -- ③ every MEASUREMENT comes from the frozen row. Not the caller's, not the client's, not
  -- now()'s — the caller supplies only the price it computed FROM these numbers.
  select rn.actual_km, rn.duration_sec, rn.end_reason::text as end_reason,
         rn.condition_note, rn.ended_at
    into r
  from runs rn where rn.booking_id = p_booking;
  -- `ended_at` is load-bearing for the CHARGE side, not just for this function: the settle mint
  -- compares `coalesce(r.ended_at, now())` against the cutover (`0080:362`), so a run reaching
  -- settlement with a null stop stamp would silently read as post-cutover and bill a pilot-era
  -- run. end_run_tx always writes it; this is the structural guarantee that nothing else can.
  if r.ended_at is null then raise exception 'run_stop_not_recorded'; end if;
  if r.actual_km is null or r.end_reason is null then
    -- Fail closed: a run whose freeze is incomplete cannot be settled, and guessing is how a
    -- money function invents a number (0080 §G's skip-with-a-notice argument, as an exception
    -- because here there IS a caller waiting for an answer).
    raise exception 'run_freeze_incomplete';
  end if;

  v_tx := settle_run_tx(
    p_booking, r.actual_km, r.duration_sec, r.end_reason, r.condition_note,
    (p_quote->>'base')::int,
    (p_quote->>'distance_pay')::int,
    (p_quote->>'addon_pay')::int,
    (p_quote->>'guarantee')::int,
    (p_quote->>'fee')::int);

  return jsonb_build_object('settled', true, 'unchanged', false,
                            'total_runs', v_tx->'total_runs', 'drop', v_tx->>'drop');
end $$;
revoke execute on function _settle_sealed_run(uuid, jsonb) from public, anon, authenticated;
grant execute on function _settle_sealed_run(uuid, jsonb) to service_role;

comment on function _settle_sealed_run is
  '0083 §6: THE settlement primitive (plan §3, codex #4) — the ONLY place settlement is
implemented. Locks the booking, answers an already-settled caller idempotently after verifying
the same frozen outcome (completed + settled_at + ledger), refuses anything unsealed, and settles
on the FROZEN measurement with the price its caller computed from it. Called by confirm_return_tx
and force_return_tx (server-class callers only); copied by nobody';

-- ── ⓓ confirm_return_tx — the doorstep, and the second stamp settles ───────────────────
-- Sean's D-r1: "the owner's interaction on the intermediary screen IS the evidence, and the
-- runner is paid once the dog is returned." D-r2: the owner stamp is required; the recipient
-- declaration (plan §6) is what keeps a remotely-tapped stamp honest.
-- The response deliberately carries NO owner payment state: the runner is paid either way (the
-- ordering law), and the collection outcome is not their business (settle-run/handler.ts:17-22).
create or replace function confirm_return_tx(
  p_booking uuid, p_side text, p_quote jsonb default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b record; v_uid uuid := auth.uid(); v_now timestamptz := now();
  v_both boolean; v_settled jsonb := null; v_stamped boolean := false;
begin
  if p_side not in ('runner', 'owner') then raise exception 'bad_side'; end if;
  -- A caller with an identity of its own is a CLIENT, and a client must never hand us a price.
  -- It may seal — the stamp is its own truthful act — and settlement then belongs to the server
  -- call that follows. (0077's caller-class doctrine, applied to the one argument that is money.)
  if v_uid is not null and p_quote is not null then raise exception 'quote_from_client'; end if;

  select bk.id, bk.owner_id, bk.runner_id, bk.status::text as status, bk.club_session_id,
         bk.run_ended_at, bk.runner_confirmed_return_at, bk.owner_confirmed_return_at,
         bk.settlement_ready_at, bk.return_forced_by
    into b
  from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;

  -- party gate before state gate. Two caller classes, both legitimate:
  --   · a client-role/JWT-bearing caller must BE the side it claims;
  --   · a server caller (the edge function, service_role, no auth.uid()) has already
  --     authenticated its user — 0077's caller-class doctrine, stated rather than assumed.
  if v_uid is not null then
    if p_side = 'runner' and v_uid is distinct from b.runner_id then raise exception 'not_party'; end if;
    if p_side = 'owner'  and v_uid is distinct from b.owner_id  then raise exception 'not_party'; end if;
  elsif current_user not in ('service_role', 'postgres') then
    raise exception 'not_signed_in';
  end if;

  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;

  -- idempotence before the state gate: a booking already settled answers "done", never an error.
  if b.status = 'completed' then
    return jsonb_build_object('stamped', false, 'settled', true, 'unchanged', true);
  end if;
  if b.status <> 'active' then raise exception 'not_active'; end if;
  if b.run_ended_at is null then raise exception 'run_not_ended'; end if;

  -- ① the stamp (idempotent — a double tap is the same tap)
  if p_side = 'runner' and b.runner_confirmed_return_at is null then
    update bookings set runner_confirmed_return_at = v_now where id = p_booking;
    v_stamped := true;
  elsif p_side = 'owner' and b.owner_confirmed_return_at is null then
    update bookings set owner_confirmed_return_at = v_now where id = p_booking;
    v_stamped := true;
  end if;

  -- ② the seal — both stamps, or a force that already happened
  select (bk.runner_confirmed_return_at is not null and bk.owner_confirmed_return_at is not null)
         or bk.return_forced_by is not null
    into v_both
  from bookings bk where bk.id = p_booking;

  if v_both then
    -- ③ THE SEAL IS DURABLE FIRST (plan §3's second permitted shape, codex #4). Whatever happens
    -- to the process after this statement, the fact that the dog is home survives — which is what
    -- makes the §9 sweep able to see a settlement that never happened.
    if b.settlement_ready_at is null then
      update bookings set settlement_ready_at = v_now
       where id = p_booking and settlement_ready_at is null;
    end if;
    -- ④ …and settlement rides the SAME transaction whenever the caller brought a price, through
    -- the one primitive (never a second implementation here).
    if p_quote is not null then
      v_settled := _settle_sealed_run(p_booking, p_quote);
    end if;
  end if;

  return jsonb_build_object(
    'stamped', v_stamped,
    'sealed', coalesce(v_both, false),
    'settled', coalesce((v_settled->>'settled')::boolean, false),
    'unchanged', coalesce((v_settled->>'unchanged')::boolean, false));
end $$;
revoke execute on function confirm_return_tx(uuid, text, jsonb) from public, anon;
grant execute on function confirm_return_tx(uuid, text, jsonb) to authenticated;

comment on function confirm_return_tx is
  '0083 §6 (plan §3, Sean D-r1/D-r2): 인계 확인 — 한쪽 스탬프는 아무것도 봉인하지 않고, 두 번째
스탬프가 settlement_ready_at을 내구적으로 찍은 뒤 (가격을 들고 온 서버 호출이면) 같은 잠긴
트랜잭션에서 _settle_sealed_run을 호출한다. 신원이 있는 호출자(클라)는 가격을 넘길 수 없다
(quote_from_client). 당사자 게이트 선행, 클럽 거부, 종료 전 거부, 멱등. 반환값에 보호자 결제
상태는 없다 — 러너는 어느 쪽이든 지급되고 그건 러너의 정보가 아니다';

-- ── ⓔ force_return_tx — the release valve, with the evidence that makes it one ──────────
-- codex #10 and Sean's §9 D-r1 residual: server time on a locked fresh row; evidence is a
-- pickup-radius proof from the custody channel, an owner interaction, or an ops override; the
-- row records actor, eligibility time, reason and evidence; and it is a DURABLE SERVER process,
-- never an app-local timer — a runner who pockets the phone must still be paid.
-- The grace is 20 minutes from the stop, because the stop is when the peer was notified (Sean's
-- proposal at §9, awaiting his confirmation at build — flagged in this slice's report).
-- Ops (`service_role` with no caller identity) may force without waiting: an ops override is a
-- human who has already looked, and making them wait out a timer helps nobody.
create or replace function force_return_tx(
  p_booking  uuid,
  p_side     text,
  p_reason   text,
  p_evidence jsonb,
  p_quote    jsonb default null
) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  b record; v_uid uuid := auth.uid(); v_now timestamptz := now();
  v_eligible timestamptz; v_settled jsonb;
  FORCE_GRACE constant interval := interval '20 minutes';
begin
  if p_side not in ('runner', 'owner', 'ops') then raise exception 'bad_side'; end if;
  if v_uid is not null and p_quote is not null then raise exception 'quote_from_client'; end if;
  -- A force with no evidence is an assertion. This row is what a dispute is read from.
  if p_evidence is null or jsonb_typeof(p_evidence) <> 'object' or p_evidence = '{}'::jsonb then
    raise exception 'evidence_required';
  end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'reason_required'; end if;

  select bk.id, bk.owner_id, bk.runner_id, bk.status::text as status, bk.club_session_id,
         bk.run_ended_at, bk.runner_confirmed_return_at, bk.owner_confirmed_return_at,
         bk.settlement_ready_at, bk.return_forced_by,
         bk.return_eligible_at            -- [0083] re-entry reports the FIRST force's clock
    into b
  from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;

  if p_side = 'ops' then
    -- ops is a server-side override; a phone cannot claim it.
    if v_uid is not null or current_user not in ('service_role', 'postgres') then
      raise exception 'not_party';
    end if;
  elsif v_uid is not null then
    if p_side = 'runner' and v_uid is distinct from b.runner_id then raise exception 'not_party'; end if;
    if p_side = 'owner'  and v_uid is distinct from b.owner_id  then raise exception 'not_party'; end if;
  elsif current_user not in ('service_role', 'postgres') then
    raise exception 'not_signed_in';
  end if;

  if b.club_session_id is not null then raise exception 'club_out_of_scope'; end if;

  if b.status = 'completed' then
    return jsonb_build_object('forced', false, 'settled', true, 'unchanged', true);
  end if;
  if b.status <> 'active' then raise exception 'not_active'; end if;
  if b.run_ended_at is null then raise exception 'run_not_ended'; end if;

  -- A force already recorded is IMMUTABLE — the first resolution is the one a dispute reads. But
  -- the RECORD being immutable does not mean the money already moved, and this branch used to say
  -- `settled: true` on the way out. Control only reaches here with `status = 'active'` (completed
  -- returned above, everything else raised), so that claim was provably false — and it broke the
  -- intended flow as well: a client cannot supply a quote (`quote_from_client`), so the real
  -- sequence is force-without-price from the phone, then a server retry WITH the price, which
  -- landed here and never settled. `confirm_return_tx` has always handled the same case correctly;
  -- the asymmetry was an oversight, not a design. So: the force stays first-writer-wins, and a
  -- caller that brought a price still settles through the one primitive.
  if b.return_forced_by is not null then
    if p_quote is not null then
      v_settled := _settle_sealed_run(p_booking, p_quote);
    end if;
    return jsonb_build_object(
      'forced', false,
      'forced_by', b.return_forced_by,
      'eligible_at', b.return_eligible_at,
      'sealed', true,
      -- never claimed unless `_settle_sealed_run` actually ran and said so
      'settled', coalesce((v_settled->>'settled')::boolean, false),
      'unchanged', coalesce((v_settled->>'unchanged')::boolean, true));
  end if;

  -- eligibility, computed from the SERVER's stop stamp
  v_eligible := b.run_ended_at + FORCE_GRACE;
  if p_side <> 'ops' and v_now < v_eligible then
    raise exception 'force_too_early'
      using detail = '조금만 더 기다려주세요 — 인계 확인은 러닝 종료 20분 뒤부터 강제할 수 있어요';
  end if;

  update bookings set
      return_forced_by      = p_side,
      return_forced_at      = v_now,
      return_force_reason   = p_reason,
      return_force_evidence = p_evidence,
      return_eligible_at    = v_eligible,
      -- the forcing side's own confirmation is implied by the act; the peer's is not invented.
      runner_confirmed_return_at = case when p_side = 'runner'
        then coalesce(b.runner_confirmed_return_at, v_now) else b.runner_confirmed_return_at end,
      owner_confirmed_return_at = case when p_side = 'owner'
        then coalesce(b.owner_confirmed_return_at, v_now) else b.owner_confirmed_return_at end,
      settlement_ready_at   = coalesce(b.settlement_ready_at, v_now)
  where id = p_booking;

  if p_quote is not null then
    v_settled := _settle_sealed_run(p_booking, p_quote);
  end if;

  return jsonb_build_object(
    'forced', true,
    'forced_by', p_side,
    'eligible_at', v_eligible,
    'sealed', true,
    'settled', coalesce((v_settled->>'settled')::boolean, false),
    'unchanged', coalesce((v_settled->>'unchanged')::boolean, false));
end $$;
revoke execute on function force_return_tx(uuid, text, text, jsonb, jsonb) from public, anon;
grant execute on function force_return_tx(uuid, text, text, jsonb, jsonb) to authenticated;

comment on function force_return_tx is
  '0083 §6 (plan §7 / codex #10 / Sean §9 D-r1 잔여): 인계 강제 — 서버 시계, 잠긴 행, 종료 20분 뒤부터
(ops 오버라이드는 즉시). 행위자·자격 시각·사유·증거를 기록하고, 이미 기록된 강제는 덮어쓰지 않는다
(첫 결론이 분쟁의 근거). 증거 없는 강제는 evidence_required로 거부. 씰은 항상 내구적으로 찍히고,
가격을 들고 온 서버 호출이면 같은 트랜잭션에서 _settle_sealed_run 하나로 정산한다 —
**이미 강제가 기록된 예약에 재진입해도 마찬가지다**: 기록은 불변이되 가격을 들고 오면 그때 정산되고,
settled는 _settle_sealed_run이 실제로 정산했을 때만 참이다 (클라는 가격을 못 넘기므로
"폰이 강제 → 서버가 가격을 들고 재시도"가 정상 경로다)';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §8 LIVE ACTIVITY — 귀가 is a phase, and the two running-only consumers are guarded
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Plan §4's audit, the three rows this file owns:
--   · LA trace trigger  → running-only, guarded here
--   · LA stale sweep    → running-only, guarded here (and given a 귀가 arm of its own, §5)
--   · a new booking-side trigger drives the 귀가 phase itself
-- (`available_runners` and pickup-address access are custody-INCLUSIVE and correct as they are —
--  the runner still needs the address to return the dog. The four scheduled-capacity consumers
--  are the plan's capacity gap and belong to an edge/client slice.)

-- ── ⓐ the trace trigger goes silent at the stop ────────────────────────────────────────
-- 0079 §5's definition, reproduced with exactly ONE addition: the `run_ended_at` guard, placed
-- with the other silence conditions. WHY it is not merely redundant with §2's freeze: the guard
-- there stops CLIENT writes, while this trigger fires on any write at all — including the final
-- trace commit inside `end_run_tx` itself, which must not push a 'running' banner one statement
-- before the 귀가 banner. 103 L7/L8/L9/L13 pin everything else byte-for-byte.
create or replace function _owner_la_trace_tg() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_status text; v_dog text; v_runner text; v_target numeric;
  v_km numeric; v_sec int; v_props jsonb;
  v_prev text; v_suggest int; v_window int; v_state text;   -- [0079]
  v_run_ended timestamptz;                                  -- [0083]
begin
  if not exists (select 1 from owner_la_tokens t where t.booking_id = new.booking_id) then
    return new;
  end if;

  select b.status::text, d.name, coalesce(p.name, '러너'), b.km, b.run_ended_at
    into v_status, v_dog, v_runner, v_target, v_run_ended
    from bookings b
    join dogs d on d.id = b.dog_id
    left join profiles p on p.id = b.runner_id
   where b.id = new.booking_id;
  if v_status is distinct from 'active' then return new; end if;
  -- [0083] 귀가 중이면 트레이스는 러닝을 말하지 않는다 — 동결된 기록이거나 마지막 커밋이다.
  if v_run_ended is not null then return new; end if;

  if coalesce(jsonb_array_length(new.trace), 0) < 2 then return new; end if;
  v_km := _owner_la_trace_km(new.trace);
  if v_km < 0.01 then return new; end if;

  v_sec := greatest(0, floor(extract(epoch from (now() - coalesce(new.started_at, now()))))::int);

  -- [0079] the claim. Note what it reads: new.pace_suggest_sec (the SNAPSHOT on this run row),
  -- never dogs.preferences — the freeze law is enforced by where the number comes from.
  select t.last_state->>'paceState' into v_prev
    from owner_la_tokens t
   where t.booking_id = new.booking_id
   order by t.created_at, t.profile_id
   limit 1;
  v_suggest := coalesce(new.pace_suggest_sec, 480);
  v_window  := _owner_la_window_pace(new.trace, 180000);
  v_state   := _owner_la_pace_state(v_prev, v_window, v_km, v_sec, v_suggest);

  v_props := jsonb_build_object(
    'phase', 'running',
    'dogName', v_dog,
    'runnerName', v_runner,
    'km', to_char(v_km, 'FM999990.00'),
    'targetKm', rtrim(rtrim(to_char(v_target, 'FM999990.0'), '0'), '.'),
    'pace', _owner_la_fmt_pace(v_sec, v_km),
    'elapsed', _owner_la_fmt_elapsed(v_sec),
    'statusLine', '방금 업데이트',
    'paceState', v_state);                                   -- [0079]
  perform _owner_la_push(new.booking_id, 'update', v_props);
  return new;
exception when others then
  return new;  -- push is an auxiliary channel — it must never block a trace save (0024 precedent)
end $$;

-- ── ⓑ the 귀가 banner — a booking-side trigger on the stop stamp ────────────────────────
-- Separate from `_owner_la_booking_tg` on purpose: that trigger is `after update OF STATUS`
-- (0063:364) and the whole point of the freeze is that the STATUS DOES NOT CHANGE at the stop
-- (plan §1 — the booking stays `active` through 귀가). A phase that no status transition
-- announces needs its own trigger on the column that does change.
-- The numbers are the FROZEN ones and they are labelled as frozen by carrying no target and no
-- pace: 귀가 has no distance goal and a pace claim about a walk home would be a fabricated
-- measurement (0079's honesty gate, same argument, different phase).
create or replace function _owner_la_run_end_tg() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_dog text; v_runner text; v_km numeric; v_sec int; v_props jsonb;
begin
  if new.run_ended_at is null or old.run_ended_at is not null then return new; end if;
  if not exists (select 1 from owner_la_tokens t where t.booking_id = new.id) then return new; end if;

  select d.name, coalesce(p.name, '러너') into v_dog, v_runner
    from bookings b
    join dogs d on d.id = b.dog_id
    left join profiles p on p.id = b.runner_id
   where b.id = new.id;
  select r.actual_km, r.duration_sec into v_km, v_sec from runs r where r.booking_id = new.id;

  v_props := jsonb_build_object(
    'phase', 'homeward',
    'dogName', v_dog,
    'runnerName', v_runner,
    'km', case when v_km is null then '' else to_char(v_km, 'FM999990.00') end,
    'targetKm', '',
    'pace', '',
    'elapsed', case when v_sec is null then '' else _owner_la_fmt_elapsed(v_sec) end,
    'statusLine', '집으로 가는 중',
    'paceState', '');
  -- min_gap 0: a phase change must never wait out the ambient throttle (103 L13's argument).
  perform _owner_la_push(new.id, 'update', v_props, null, 0);
  return new;
exception when others then
  return new;  -- a lock-screen banner never blocks the freeze
end $$;

drop trigger if exists owner_la_run_end on bookings;
create trigger owner_la_run_end after update of run_ended_at on bookings
  for each row execute function _owner_la_run_end_tg();

revoke execute on function _owner_la_run_end_tg() from public, anon, authenticated;

comment on function _owner_la_run_end_tg is
  '0083 §8 (plan §4d): the 귀가 banner. Fires on bookings.run_ended_at because the STATUS does not
change at the stop — the booking stays active through 귀가, which is exactly why 0063''s
status-triggered composer cannot see this phase. Frozen km/elapsed, no target, no pace claim';

-- ── ⓒ the stale sweep: running-only, plus a 귀가 arm that reads the heartbeat ───────────
-- 0079 §5's sweep, reproduced with TWO changes:
--   ⓐ arm ① gains `b.run_ended_at is null`. Without it the sweep pushes "N분째 위치가
--      갱신되지 않았어요" 90 seconds into EVERY 귀가 — the trace stopped because the run ended,
--      which is the one situation where a staleness claim is a lie the server told itself.
--   ⓑ arm ② is the honesty counterpart (plan §5, codex #9): 귀가 freshness reads
--      `custody_last_seen_at`, never the trace, so a runner whose phone dies still produces a
--      no-signal state instead of an eternal 집으로 가는 중.
-- 103 L11/L12's fixtures are running-phase and untouched by both.
create or replace function owner_la_sweep_stale() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; v_last_t numeric; v_age int; v_min int; v_km numeric; v_line text; v_props jsonb;
  v_n int := 0;
begin
  for r in
    select t.booking_id, t.last_state, run.trace, b.km as target_km,
           d.name as dog_name, coalesce(p.name, '러너') as runner_name
      from owner_la_tokens t
      join bookings b on b.id = t.booking_id and b.status = 'active'
                     and b.run_ended_at is null            -- [0083] 러닝 구간 전용
      join runs run on run.booking_id = b.id
      join dogs d on d.id = b.dog_id
      left join profiles p on p.id = b.runner_id
  loop
    -- No fix ever received → the LA is still on the handoff card; there is no number to grey out.
    if coalesce(jsonb_array_length(r.trace), 0) < 2 then continue; end if;
    v_last_t := (r.trace->-1->>'t')::numeric;
    v_age := floor(extract(epoch from now()) - v_last_t)::int;
    if v_age < 90 then continue; end if;

    v_min := greatest(1, v_age / 60);
    v_line := v_min || '분째 위치가 갱신되지 않았어요';
    if coalesce(r.last_state->>'phase', '') = 'stale'
       and coalesce(r.last_state->>'statusLine', '') = v_line then
      continue;  -- same minute already pushed
    end if;

    v_km := _owner_la_trace_km(r.trace);
    v_props := jsonb_build_object(
      'phase', 'stale',
      'dogName', r.dog_name,
      'runnerName', r.runner_name,
      'km', case when v_km < 0.01 then '' else to_char(v_km, 'FM999990.00') end,
      'targetKm', rtrim(rtrim(to_char(r.target_km, 'FM999990.0'), '0'), '.'),
      'pace', '',
      'elapsed', '',
      'statusLine', v_line,
      'paceState', '');                                      -- [0079] stale never carries a claim
    v_n := v_n + _owner_la_push(r.booking_id, 'update', v_props, null, 0);
  end loop;

  -- [0083 §8-ⓑ] 귀가 arm — freshness from the heartbeat, never from the trace (plan §5)
  for r in
    select t.booking_id, t.last_state,
           coalesce(b.custody_last_seen_at, b.run_ended_at) as seen_at,
           run.actual_km, run.duration_sec,
           d.name as dog_name, coalesce(p.name, '러너') as runner_name
      from owner_la_tokens t
      join bookings b on b.id = t.booking_id and b.status = 'active'
                     and b.run_ended_at is not null
      left join runs run on run.booking_id = b.id
      join dogs d on d.id = b.dog_id
      left join profiles p on p.id = b.runner_id
  loop
    v_age := floor(extract(epoch from (now() - r.seen_at)))::int;
    if v_age < 90 then continue; end if;              -- a beating heart says nothing new

    v_min := greatest(1, v_age / 60);
    v_line := v_min || '분째 위치 신호가 없어요';
    if coalesce(r.last_state->>'statusLine', '') = v_line
       and coalesce(r.last_state->>'phase', '') = 'homeward' then
      continue;                                       -- same minute already pushed (arm ① idiom)
    end if;

    v_props := jsonb_build_object(
      'phase', 'homeward',
      'dogName', r.dog_name,
      'runnerName', r.runner_name,
      'km', case when r.actual_km is null then '' else to_char(r.actual_km, 'FM999990.00') end,
      'targetKm', '',
      'pace', '',
      'elapsed', case when r.duration_sec is null then '' else _owner_la_fmt_elapsed(r.duration_sec) end,
      'statusLine', v_line,
      'paceState', '');
    v_n := v_n + _owner_la_push(r.booking_id, 'update', v_props, null, 0);
  end loop;
  return v_n;
end $$;

comment on function owner_la_sweep_stale is
  '0083 §8 (was 0079/0063): 스테일 스윕 두 팔. ① 러닝 구간(run_ended_at is null)만 트레이스 기준
90초 무갱신을 stale로 — 귀가에는 트레이스가 의도적으로 멈추므로 그 팔이 들어가면 매 귀가마다
거짓 경고가 나간다. ② 귀가 구간은 custody_last_seen_at(하트비트) 기준 — 러너 폰이 죽어도
"집으로 가는 중"이 영원히 살아있지 않게 (plan §5, codex #9)';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §9 THE JANITOR — nothing strands, and nothing settles twice
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Two failure classes, one sweep, because both are "a booking that stopped and then stopped
-- moving" and an operator reading two crons for one symptom reads neither.
--   ⓐ SEALED BUT UNSETTLED (plan §3, codex #4). `settlement_ready_at` is set and the booking never
--      reached completed — the process died between the seal and the settlement.
--      ⚠ THIS SWEEP CANNOT SETTLE IT, and pretending otherwise would be the dishonesty this file
--      exists to remove. The runner's payout basis is `end_reason`-dependent (Sean's G1 ruling)
--      and is computed by the pricing code, which is TypeScript — a cron in Postgres has no way
--      to call it. So this arm REPORTS: a notice per row, and the ⓑ deadline catches whatever is
--      still there two hours later. The true re-drive is one follow-up away and its shape already
--      exists in this repo: 0080 §K's `dispatch_due_charges` (vault → pg_net → an edge function).
--      §0f names it. What IS durable today is the fact — `settlement_ready_at` survives the crash,
--      so nothing has to be reconstructed from a screen.
--   ⓑ STRANDING (plan §7). The run stopped and NOBODY EVER CONFIRMED the return, so the booking
--      never left `active`. `active` is not inert: it is LIVE to the runner-accept conflict guard
--      (`transition-booking/index.ts:58`), so the runner's future bookings are blocked by a dog
--      they returned two days ago. After 2 hours it escalates to `incident_review`, an edge the
--      transition map already allows (`0047:40`). Deliberately NOT a settlement: this sweep never
--      decides that money moved.
--      🔴 **AND IT MUST NEVER TOUCH A SEALED ROW** (`settlement_ready_at is not null`) — that
--      predicate is the whole of this arm's safety. `incident_review` is a MONEY DEAD END:
--      `settle_run_tx`, `_settle_sealed_run`, `confirm_return_tx` and `force_return_tx` all
--      require `active`, and the transition map allows `incident_review → refund_pending` ONLY
--      (`0066:56`). The single commercial exit that exists, `club_incident_settle` (`0072`), is
--      structurally club-only — it needs a `club_incidents` row, a locked `club_sessions` row and
--      a `club_incident_subjects` mapping, none of which a marketplace booking can have. So an
--      earlier draft of this arm, which escalated sealed rows too, made an owner who simply did
--      not tap confirm within 2 hours able to render the runner **permanently unpayable**, with
--      no human path either. A sealed row is exactly the row whose money can still move; it gets
--      arm ⓐ's alarm instead, which moves no state. See §0h.
-- Both parties are told. Both titles ('귀가 확인이 필요해요' from ⓑ, '정산을 확인하고 있어요' from
-- ⓐ) avoid '요청' (which `push.ts:41` routes to /runner/requests) and carry the booking id, so the
-- runner lands on their calendar and the owner on their bid-scoped report; the RETURN_TITLES
-- routing table the plan §6 describes belongs to the client slice and owns both of these.
create or replace function sweep_run_end_recovery() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  r record; n int := 0;
  STRAND_AFTER constant interval := interval '2 hours';
  -- A sealed row is RECOVERABLE — the money can still move the moment the pricing path re-drives
  -- it — so its alarm is longer than the stranding deadline and, crucially, moves no state.
  SEAL_ALARM_AFTER constant interval := interval '6 hours';
begin
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
클럽 전용)이라 승격하면 러너가 영구 미지급이 된다 — §0h. 승격은 정산이 아니다. 양측에 통지';

-- Cron. Minute offsets: every mod-5 slot is already taken (*/5 expire-unmatched · 1-56/5
-- purge-holds · 2-57/5 sweep-settled-charges · 3-58/5 sweep-payment-intents · 4-59/5
-- dispatch-due-charges), so 0060:145's stagger doctrine cannot be honoured literally. A
-- 10-minute cadence at minute 8 therefore shares its tick with `sweep-payment-intents`, which is
-- the one 5-minute batch that touches neither `bookings` nor `runs` — the collision the doctrine
-- is actually about is avoided even though the offset is not free. Guarded do-block so the
-- migration still applies where pg_cron does not exist (the local harness is that environment).
do $$ begin
  perform cron.schedule('run-end-recovery', '8-58/10 * * * *', 'select sweep_run_end_recovery()');
exception when others then
  raise notice 'pg_cron unavailable — call sweep_run_end_recovery() from an external scheduler';
end $$;
