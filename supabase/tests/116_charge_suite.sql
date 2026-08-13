-- ═══ 116 charge suite — 0080 pins (the settle-time charge machine) ═══
-- Purpose: 0080 is the first file in this repo that decides HOW MUCH an owner is charged. Every
--   rule in it is somebody's argued decision (toss-plan §0-ter and its absorbed adversarial
--   findings), and a money rule with no pin is a money rule the next refactor is free to
--   improve. These pins hold the basis table, the ceiling, the frozen numbers, the mints'
--   idempotence, the derived debt state, the two sweeps, the recurring gates, the two seals,
--   and the two honesty-copy fixes.
-- Style: sibling of 105-114 — `_pass('chg',…)`/`_fail('chg',…)`, one begin…exception per case.
--   ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
--   Money facts are asserted against LITERALS, never recomputed with the function's own
--   expression (105's law) — otherwise the pin agrees with whatever the function does.
-- ⚠ [0084, 2026-08-13] AMENDED BY A LATER MIGRATION — four pins, one ruling. 0080 §D shipped
--   `dog_condition`/`incident` as a shared provisional (`amount 0, rule 'g1_waive'`) and said in
--   its own comment that when Sean ruled, "the change is this one arm plus its pin". He ruled
--   (confirmed directly, after two sessions recorded it differently): dog_condition charges FULL
--   ACTUALS and therefore stops being a special case at all — same path, same value and same
--   `actual_capped` rule as `completed`; incident stays ₩0 and becomes reviewable
--   (`incident_pending_review`). So **C1's single G1 line split in two, and C6/C9/C23 re-point
--   their waive fixtures from `dog_condition` to `incident`** — dog_condition no longer produces
--   a waived row at all. Nothing else in this suite moved; every property the ruling ADDS (the
--   completed/aborted identity, the accepted 200m cost, the review marker, the fifth
--   reconciliation arm) is pinned in `120_g1_ops_cutover_suite.sql`, not here.
-- ⚠ The cutover switch (`ops_flags.payments_live_since`) ships NULL = charging off, and while
--   it is NULL the mints and the invariant-#1 sweep write nothing at all. So this suite sets it
--   once in the seed (a week back) to get a running machine, C14 and C22 own the switch itself,
--   and C22 restores the shipped NULL as its last act.
-- ⚠ Global side effects, deliberately (this suite runs last): C9/C24 call
--   sweep_settled_without_payments(), C10/C25 call sweep_stale_payment_intents(), C13/C14 call
--   generate_recurring_bookings(), C17 calls expire_unmatched_bookings(). Each of those is a
--   whole-table batch, so every affected pin measures a DELTA or its own rows by id (the 100 W7
--   idiom), never an absolute count of the table.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   C1  ← §D: change any basis-table arm (e.g. give runner_personal the base fare back,
--         or drop the `owner_caused_planned` arm so D2 charges actuals)                  → RED
--   C2  ← §D: drop the `least(…, b.km)` ceiling — the owner can then be charged more
--         than the price they consented to (§0-ter #4)                                   → RED
--   C3  ← §D: compute from live constants (`7900 + 3000 * basis`) instead of the
--         booking's own base_fare/distance_fare/km (§0-ter #6)                           → RED
--   C4  ← §D: replace the `unknown_end_reason` raise with a fallback (e.g. treat unknown
--         as 'completed') — a money function must fail closed                            → RED
--   C5  ← §E: delete the exists-check in mint_settle_charge_intent (every call mints a
--         second row = a second order_id = a genuinely possible double charge)           → RED
--         ⚠ the exists-check's CONCURRENT half (the per-booking pg_advisory_xact_lock) is
--         invisible to this suite — one connection cannot race itself. Its pin is
--         90_race_check.sh RD; deleting the lock leaves C5 green and turns RD red.
--   C6  ← §E: mint status 'pending' with amount 0 instead of 'waived', or drop the
--         `payments_waived_is_zero` check                                                → RED
--   C7  ← §B: drop 'waived' from `payments_settled_has_key` (a deliberate non-charge can
--         no longer be recorded at all, so invariant #1 regains its exception)           → RED
--   C8  ← §F: anchor "settled" on `bookings.status` instead of runs/ledger existence
--         (§0-ter #11 — an incident_review move then drops a failed charge out of the
--         lock), or drop the dispatched-pending arm, or drop the
--         `(p.raw->>'kind') is not null` restriction (arm ⑧ — widget-era debris on a
--         settled booking then locks an owner who owes nothing, with no CTA able to
--         clear it: collect-charges refuses kind-less rows)                              → RED
--   C9  ← §G: drop sweep_settled_without_payments (the settle-crash class becomes
--         invisible: runner paid, nobody recorded that the owner owes)                   → RED
--   C10 ← §I: remove `and (raw->>'dispatched_at') is null` from the stale sweep — a row
--         Toss may already have charged gets closed `failed` (§0-ter #2)                 → RED
--   C11 ← §I: drop the `stale_dispatched` arm of payments_reconciliation (the rows the
--         sweep now refuses to touch have no reader), or drop the `ladder_exhausted`
--         arm (spent-ladder debt is invisible to ops), or widen any arm so two arms
--         claim one row                                                                  → RED
--   C12 ← §B: drop the `payments (booking_id) where status='failed'` partial index       → RED
--   C13 ← §H: delete the `owner_has_unsettled_charge` gate, or move the notify out of
--         the once-per-owner guard so a 2-series owner is told twice                     → RED
--   C14 ← §H: drop `v_live and` from the instrument gate (card-less owners stop getting
--         their recurring runs BEFORE the cutover — today's behavior broken)             → RED
--   C22 ← §E: drop either cutover guard from mint_settle_charge_intent — the
--         `payments_live_since is null` return (pre-cutover intents appear, the stale
--         sweep turns them to failed, §F reads false debt) or the
--         `runs.ended_at < payments_live_since` return (the flip bills every free pilot
--         run retroactively). THE money pin of the 2026-08-13 amendment.                 → RED
--   C15 ← §A/§C: `alter table billing_keys disable row level security`, or add any
--         policy to either sealed table                                                  → RED
--   C16 ← §A: widen my_billing_card to drop the `profile_id = auth.uid()` scope, or add
--         billing_key to its return shape, or drop `revoke … from public, anon`
--         (a signed-out client could then call it — auth.uid() null returns zero rows
--         today, but the grant is the seal, not the query's luck)                        → RED
--   C17 ← §J-ⓐ: revert the e_match notification body to the unconditional
--         '전액 환불 처리돼요' (a refund promise for money never taken)                    → RED
--   C18 ← §J-ⓑ: revert club_incident_settle step ⑥ to the unconditional
--         'N원이 환불돼요'                                                                → RED
--   C19 ← §K-ⓐ: drop the `exists (select 1 from ledger_items …)` idempotence guard (a
--         second call double-pays the runner), or write the fee to platform_fee          → RED
--   C20 ← §E: mint a zero-amount cancel-fee row instead of nothing (§0-ter #13)          → RED
--   C21 ← §A-§K: `grant execute on function mint_settle_charge_intent(uuid,text,numeric)
--         to authenticated` — a client that can mint its own charge intents              → RED
--         (the array also carries sweep_stale_payment_intents(): 0080 recreates it, and
--         `create or replace` keeps whatever ACL the body inherits from 0076 — the one
--         definer in this file whose seal is inherited rather than written)
--   C23 ← §D: delete the `v_amount < PG_MIN_CHARGE` arm — a sub-₩100 charge becomes a
--         real intent, the PG refuses it, and the permanent decline walks the ladder
--         into false debt and an account lock over ₩30                                   → RED
--   C24 ← §G: drop the sweep's `actual_km is null` skip (an unmeasured run is charged its
--         base + addons on a guessed 0 km), or revert its exists-check to a bare
--         `not exists (payments …)` so kind-less widget debris blinds the sweep and a
--         genuinely settled booking never gets a charge row (R3 P3-9)                    → RED
--   C25 ← §I: drop the notification CTE from sweep_stale_payment_intents (an hour later
--         §F locks the account and nothing ever told the owner why), or drop that CTE's
--         `(raw->>'kind') is not null` filter (widget debris then notifies owners about
--         charges that never existed — 100 W7's silence argument)                        → RED
--
--   ─── the two CONCURRENCY claims are pinned outside this file ───
--   90_race_check.sh RD ← §E: delete the `pg_advisory_xact_lock('mint:'…)` from
--         mint_settle_charge_intent — two concurrent minters both pass the exists-check
--         and insert, two order_ids, two chargeable intents                              → RED
--   90_race_check.sh RE ← §K-ⓐ: delete the `pg_advisory_xact_lock('comp:'…)` from
--         record_enroute_cancel_comp — ledger_items has no unique key, so two concurrent
--         callers both write the compensation row and the runner is paid twice           → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs (clean cluster each time; restore → green every
--     time). Method, both rounds: edit 0080 → rm -rf .pgtest → full harness → restore.
--     ROUND 1, 2026-08-13, when the suite was C1-C22 and green was 410/0 — five clean reverts:
--       C2   → 409/1, red = [C2]            C5   → 409/1, red = [C5]
--       C19  → 409/1, red = [C19]
--       C22  → 409/1, red = [C22]  (mint's `ended_at < since` guard removed)
--       C22′ → 409/1, red = [C22]  (mint's `since is null` guard removed — the other arm)
--     ROUND 2, 2026-08-13, after the adversarial-round-2 absorptions; green is now 415/0
--     (C23-C25 + race RD/RE). Six clean reverts, each red exactly one pin:
--       §E mint's `pg_advisory_xact_lock('mint:'…)` deleted → 414/1, red = [race RD],
--         detail `rows=2 order_ids=2` — two committed intents on one settled booking.
--       §K-ⓐ's `pg_advisory_xact_lock('comp:'…)` deleted → 414/1, red = [race RE],
--         detail `rows=2 sum=24900` — the runner paid the 12,450 fee twice.
--       §F's `(p.raw->>'kind') is not null` deleted → 414/1, red = [C8],
--         detail `위젯 잔해(정산+confirmed 형제)가 잠금이 됨`.
--       §D's below_pg_minimum arm deleted → 414/1, red = [C23] (₩90 minted as a pending charge).
--       §G's exists-check reverted to a bare `not exists (payments …)` → 414/1, red = [C24].
--       §I's notification CTE deleted → 414/1, red = [C25] (`민팅 행 통지=0`).
--     FOUR CASCADES, measured, and every one of them is correct rather than sloppy:
--       C10 → 408/2, red = [C10, C11] (round 1). With dispatched pendings auto-failing again,
--         C11's stale_dispatched fixture stops existing, so the arm has nothing to catch. C11
--         is genuinely broken by that revert; it is not a false alarm.
--       C14 → 406/4, red = [C14, recur G2, recur G3, recur G5] (round 1). Dropping `v_live and`
--         stops card-less generation BEFORE the cutover, and the 0026-era suite is precisely
--         the thing that consumes that contract — the old suite going red IS the evidence the
--         gate is flag-keyed for a reason (114 R3's shape).
--       C6 → 412/3, red = [C6, C9, C23] (round 2, measured). Minting amount-0 as `pending`
--         instead of `waived` breaks every pin that reads a deliberate zero: C6 directly, C9's
--         G1 fixture (`G1 정산=pending/0`), and C23's sub-floor mint. Three probes of one rule.
--       C7 → 411/4, red = [C6, C7, C9, C23] (round 2, measured). Dropping 'waived' from
--         payments_settled_has_key does not merely fail C7's own probe — it makes the waived
--         row UNWRITABLE, so both mints raise a check violation and the invariant-#1 sweep
--         leaves 5 settled bookings with no row at all. The blast radius IS the argument for
--         the constraint: 'waived' is load-bearing for invariant #1, not decoration.
--   ⚠ HONESTY NOTE, measured: removing §G's `and rn.ended_at >= v_since` predicate ALONE
--     leaves the harness green. That predicate is defense-in-depth plus a batch-size
--     optimization — the enforcement point is the mint's own guard, which refuses the row
--     anyway, so no probe can distinguish. It is named in C22's revert list as the mint guard
--     for that reason. An author who deletes BOTH is caught; one who deletes only the sweep's
--     is not, and pretending otherwise would be a dead pin (110's S1 lesson).
--   ⚠ HONESTY NOTE, structural: `dispatch_due_charges()`'s due predicate (§K — the retry
--     ladder's wake-up rule) has NO pin in this suite and cannot have one here. The function
--     returns 0 without ever exposing the count when the vault is absent, and the local harness
--     is exactly that environment (no vault schema), so no probe can tell a correct predicate
--     from a broken one. Its real pin is the TS twin it must agree with:
--     supabase/functions/collect-charges/handler.ts:107 `isDue()` and its Deno tests. The two
--     are ONE rule written twice and change together; if the vault ever gets stubbed in the
--     shim, this is the first pin to add.
--     The remaining pins are NOT machine-proven; they are named above with the single revert
--     that would redden each, and their probe shapes are clones of already-proven siblings
--     (109 P3/P10 for the seals and the grant matrix, 100 W7 for the batch-delta idiom).
set client_min_messages = warning;

-- ---------- suite-local helpers ----------
-- A booking whose fare columns are chosen by the caller: the frozen-numbers pin (C3) needs a
-- row whose implied per-km is deliberately NOT today's constant, which t_av_booking cannot do.
create or replace function t_chg_bk(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid,
                                    p_status booking_status, p_when timestamptz, p_km numeric,
                                    p_base int, p_dist int, p_addon int)
returns uuid language sql as $$
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, p_status, p_when, p_km,
          p_base, p_dist, p_addon, p_base + p_dist + p_addon, 9900)
  returning id
$$;

-- "This booking was settled" in the only way §F recognises: a runs row with ended_at.
-- [0083 amendment] …and, since 0083, a `settled_at`. `runs.ended_at` now means the SERVICE STOP
-- (0083 §1/§6), so on its own it no longer says money moved: a row with only `ended_at` describes
-- a run that stopped and was never returned. This helper has always claimed to build a SETTLED
-- booking, so it stamps both — which is also what lets this sweep's predicate move onto
-- `settled_at` (0083 §0f's handoff) as a one-line change rather than a fixture rewrite.
create or replace function t_chg_settled(p_booking uuid, p_reason text, p_km numeric)
returns void language sql as $$
  insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
  values (p_booking, now() - interval '40 minutes', now(), now(), p_km, p_reason::end_reason)
$$;

do $$
declare
  oo uuid; oz uuid; rr uuid; dg uuid; rt uuid;
  bk1 uuid; bk2 uuid;
  v_bad text := ''; v_msg text; v_n int; v_n2 int; v_pre int; v_err boolean;
  v_amount int; v_basis numeric; v_rule text;
  c record; m record; m2 record;
  b_a uuid; b_b uuid; b_c uuid; b_d uuid;
  p_a uuid; p_b uuid; p_c uuid;
  o_dbt uuid; o_pre uuid; o_fee uuid; o_disp uuid; o_card uuid;
  v_id uuid; v_status text; v_key text;
  v_bool boolean; v_bool2 boolean;
begin
  -- ---------- seed ----------
  oo := t_user('chg_oo', 'owner'); oz := t_user('chg_oz', 'owner');
  rr := t_user('chg_rr', 'runner');
  dg := t_dog(oo, '청구견'); rt := t_route('청구 코스');
  -- The suite's baseline world is POST-cutover: charging on since a week ago. The shipped
  -- default is NULL (charging off), and C14/C22 are the pins that own the switch itself — every
  -- other pin needs the machine actually running, so the switch is set once here and restored
  -- to NULL at the end. A week back, not now(), because the fixtures below settle runs at now()
  -- and a same-instant boundary would make the scope predicate a coin flip.
  update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();
  -- planned 5.0km, implied 3,000/km, 2,000 in addons → full charge 26,900
  bk1 := t_chg_bk(oo, dg, rt, rr, 'confirmed', now() + interval '3 hours', 5.0, 9900, 15000, 2000);
  -- planned 4.0km at an implied 2,500/km — a price nobody sells today (C3's whole point)
  bk2 := t_chg_bk(oo, dg, rt, rr, 'confirmed', now() + interval '9 hours', 4.0, 9900, 10000, 500);

  -- ---------- [C1] the basis table, arm by arm ----------
  -- Six rows of toss-plan §0-ter's table, each with the literal it must produce. The rule
  -- string is asserted too: it is what a future author greps for when Sean rules on G1, and a
  -- silently renamed rule is a silently rewritten decision.
  begin
    v_bad := '';
    select * into c from compute_owner_charge(bk1, 'completed', 5.0);
    if c.amount <> 26900 or c.basis_km <> 5.0 or c.rule <> 'actual_capped'
      then v_bad := v_bad || ' completed@5.0=' || c.amount || '/' || c.rule; end if;
    select * into c from compute_owner_charge(bk1, 'completed', 3.0);
    if c.amount <> 20900 or c.basis_km <> 3.0                    -- 9900 + 9000 + 2000
      then v_bad := v_bad || ' completed@3.0=' || c.amount; end if;
    select * into c from compute_owner_charge(bk1, 'owner_request', 3.0);
    if c.amount <> 26900 or c.basis_km <> 5.0 or c.rule <> 'owner_caused_planned'
      then v_bad := v_bad || ' owner_request@3.0=' || c.amount || '/' || c.rule; end if;
    select * into c from compute_owner_charge(bk1, 'runner_personal', 3.0);
    if c.amount <> 9000 or c.rule <> 'runner_personal_distance_only'  -- distance ONLY (#10)
      then v_bad := v_bad || ' runner_personal@3.0=' || c.amount || '/' || c.rule; end if;
    -- [0084 §A, Sean's ruling ① 2026-08-13] the shared `g1_waive` arm SPLIT IN TWO.
    -- dog_condition stopped being a special case entirely: it takes the same actual-basis path as
    -- `completed`, so at 3.0km on bk1 it is the SAME 20,900 the under-run arm above asserts, with
    -- the same `actual_capped` rule. That identity is the ruling — an aborted run is billed for
    -- what happened — and 120 J1 asserts it as an identity rather than as a coincidence of
    -- literals. `incident` keeps the zero and gains a rule string that says why.
    select * into c from compute_owner_charge(bk1, 'dog_condition', 3.0);
    if c.amount <> 20900 or c.basis_km <> 3.0 or c.rule <> 'actual_capped'
      then v_bad := v_bad || ' dog_condition=' || c.amount || '/' || c.rule; end if;
    select * into c from compute_owner_charge(bk1, 'incident', 3.0);
    if c.amount <> 0 or c.basis_km <> 0 or c.rule <> 'incident_pending_review'
      then v_bad := v_bad || ' incident=' || c.amount || '/' || c.rule; end if;

    if v_bad = ''
      then call _pass('chg','C1 기준표 — 완주 26900·언더런 20900·보호자사유 planned 26900·러너사유 거리만 9000·[0084] 컨디션 중단은 특별취급 없음(완주와 같은 20900/actual_capped)·사건은 0/incident_pending_review (rule 문자열까지)');
    else v_msg := v_bad; call _fail('chg','C1 기준표', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C1 기준표', v_msg);
  end;

  -- ---------- [C2] the ceiling — the owner can never be charged more than the quote ----------
  -- §0-ter #4: the ×2+2 validity band bounds runner payout fraud, never the owner's card.
  -- All three chargeable arms are probed over-run, because a ceiling that only holds on the
  -- arm the fixture happens to use is not a ceiling (110 S1's lesson).
  begin
    v_bad := '';
    select * into c from compute_owner_charge(bk1, 'completed', 8.0);
    if c.amount <> 26900 or c.basis_km <> 5.0 then v_bad := v_bad || ' completed@8.0=' || c.amount
      || '(basis ' || c.basis_km || ')'; end if;
    select * into c from compute_owner_charge(bk1, 'runner_personal', 8.0);
    if c.amount <> 15000 or c.basis_km <> 5.0 then v_bad := v_bad || ' runner_personal@8.0=' || c.amount; end if;
    select * into c from compute_owner_charge(bk1, 'owner_forced', 8.0);
    if c.amount <> 26900 or c.basis_km <> 5.0 then v_bad := v_bad || ' owner_forced@8.0=' || c.amount; end if;
    -- and a negative/absent actual cannot become a negative charge
    select * into c from compute_owner_charge(bk1, 'completed', 0);
    if c.amount <> 11900 or c.basis_km <> 0 then v_bad := v_bad || ' completed@0=' || c.amount; end if;

    if v_bad = ''
      then call _pass('chg','C2 상한 min(actual, planned) — 오버런 3개 팔 전부 계획가로 고정, 0km도 음수 불가 (§0-ter #4)');
    else v_msg := v_bad; call _fail('chg','C2 상한', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C2 상한', v_msg);
  end;

  -- ---------- [C3] frozen numbers — a constant change must not reprice a consented booking ----------
  -- bk2's implied per-km is 2,500 and its base is the RETIRED 9,900 owner base (live is 7,900).
  -- If the charge were rebuilt from live PRICING it would read 7900 + 3000×basis; every literal
  -- below is unreachable from the live constants, so this pin cannot pass by coincidence.
  begin
    v_bad := '';
    select * into c from compute_owner_charge(bk2, 'completed', 2.0);
    if c.amount <> 15400 then v_bad := v_bad || ' @2.0=' || c.amount || '(기대 15400)'; end if;   -- 9900+5000+500
    select * into c from compute_owner_charge(bk2, 'completed', 4.0);
    if c.amount <> 20400 then v_bad := v_bad || ' @4.0=' || c.amount || '(기대 20400)'; end if;   -- 9900+10000+500
    select * into c from compute_owner_charge(bk2, 'runner_personal', 2.0);
    if c.amount <> 5000 then v_bad := v_bad || ' runner_personal@2.0=' || c.amount; end if;
    if v_bad = ''
      then call _pass('chg','C3 동결 금액 — 예약 행의 base/distance/km에서만 계산 (2,500/km·구 9,900 base 그대로, 라이브 상수 무관) §0-ter #6');
    else v_msg := v_bad; call _fail('chg','C3 동결 금액', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C3 동결 금액', v_msg);
  end;

  -- ---------- [C4] fail closed — an unpriceable input is an exception, not a number ----------
  begin
    v_bad := '';
    begin
      select * into c from compute_owner_charge(bk1, 'no_such_reason', 5.0);
      v_bad := v_bad || ' 미지의 사유:통과(' || coalesce(c.amount::text,'∅') || ')';
    exception when others then
      if sqlerrm <> 'unknown_end_reason' then v_bad := v_bad || ' 미지의 사유:' || sqlerrm; end if;
    end;
    begin
      select * into c from compute_owner_charge(bk1, null, 5.0);
      v_bad := v_bad || ' null 사유:통과';
    exception when others then
      if sqlerrm <> 'unknown_end_reason' then v_bad := v_bad || ' null 사유:' || sqlerrm; end if;
    end;
    begin
      select * into c from compute_owner_charge(gen_random_uuid(), 'completed', 5.0);
      v_bad := v_bad || ' 없는 예약:통과';
    exception when others then
      if sqlerrm <> 'not_found' then v_bad := v_bad || ' 없는 예약:' || sqlerrm; end if;
    end;
    if v_bad = ''
      then call _pass('chg','C4 닫힌 실패 — 미지/NULL end_reason은 unknown_end_reason, 없는 예약은 not_found (추측 금액 없음)');
    else v_msg := v_bad; call _fail('chg','C4 닫힌 실패', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C4 닫힌 실패', v_msg);
  end;

  -- ---------- [C5] mint idempotence — the second row is the double charge ----------
  -- order_id doubles as the Toss Idempotency-Key, so two rows for one event are two keys and
  -- two chargeable intents. Three fixtures, because the exists-check is deliberately
  -- asymmetric: prepaid blocks, an existing SERVER intent blocks, widget debris does not.
  begin
    v_bad := '';
    b_a := t_chg_bk(oo, dg, rt, rr, 'completed', now() - interval '2 hours', 5.0, 9900, 15000, 2000);
    perform t_chg_settled(b_a, 'completed', 5.0);
    select * into m from mint_settle_charge_intent(b_a, 'completed', 5.0);
    if not m.minted or m.status <> 'pending' or m.amount <> 26900 or m.order_id not like 'dr\_%'
      then v_bad := v_bad || ' 첫 민팅=' || m.status || '/' || m.amount || '/' || coalesce(m.order_id,'∅'); end if;
    if (select p.raw->>'kind' from payments p where p.id = m.payment_id) is distinct from 'settle_charge'
      then v_bad := v_bad || ' raw.kind 누락'; end if;
    select * into m2 from mint_settle_charge_intent(b_a, 'completed', 5.0);
    if m2.minted or m2.payment_id <> m.payment_id
      then v_bad := v_bad || ' 재민팅=' || m2.minted::text; end if;
    select count(*) into v_n from payments where booking_id = b_a;
    if v_n <> 1 then v_bad := v_bad || ' 행수=' || v_n; end if;

    -- prepaid (widget era, confirmed) → never a second charge
    b_b := t_chg_bk(oz, dg, rt, rr, 'completed', now() - interval '2 hours', 5.0, 9900, 15000, 2000);
    perform t_chg_settled(b_b, 'completed', 5.0);
    insert into payments (booking_id, payment_key, order_id, amount, status)
    values (b_b, 'tviva_chg_prepaid', 'ord_chg_prepaid', 26900, 'confirmed');
    select * into m from mint_settle_charge_intent(b_b, 'completed', 5.0);
    if m.minted or m.status <> 'confirmed' then v_bad := v_bad || ' 선결제=' || m.status || '/' || m.minted::text; end if;
    select count(*) into v_n from payments where booking_id = b_b;
    if v_n <> 1 then v_bad := v_bad || ' 선결제 행수=' || v_n; end if;

    -- widget-era FAILED intent (no raw.kind) — nothing was captured pre-service, so it must
    -- NOT silence the real post-service charge.
    b_c := t_chg_bk(oz, dg, rt, rr, 'completed', now() - interval '2 hours', 5.0, 9900, 15000, 2000);
    perform t_chg_settled(b_c, 'completed', 5.0);
    insert into payments (booking_id, order_id, amount, status)
    values (b_c, 'ord_chg_widget_dead', 26900, 'failed');
    select * into m from mint_settle_charge_intent(b_c, 'completed', 5.0);
    if not m.minted or m.status <> 'pending' then v_bad := v_bad || ' 위젯 잔해=' || m.status || '/' || m.minted::text; end if;
    select count(*) into v_n from payments where booking_id = b_c;
    if v_n <> 2 then v_bad := v_bad || ' 위젯 잔해 행수=' || v_n; end if;

    if v_bad = ''
      then call _pass('chg','C5 민팅 멱등 — 재호출은 같은 행(minted=false)·선결제는 청구 안 함·위젯 잔해(kind 없음)는 막지 않음');
    else v_msg := v_bad; call _fail('chg','C5 민팅 멱등', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C5 민팅 멱등', v_msg);
  end;

  -- ---------- [C6] waived — a deliberate zero, recorded as one ----------
  begin
    v_bad := '';
    -- [0084 §A] the waive fixture moved from dog_condition to incident. Under Sean's ruling ①
    -- dog_condition is a real charge (base fare, flat), so it no longer produces a waived row at
    -- all; `incident` is the remaining deliberate zero. The row's review marker is 120 J3's pin —
    -- this one is still only about the SHAPE of a waive (zero, keyless, rule recorded).
    b_d := t_chg_bk(oo, dg, rt, rr, 'completed', now() - interval '2 hours', 5.0, 9900, 15000, 2000);
    perform t_chg_settled(b_d, 'incident', 1.2);
    select * into m from mint_settle_charge_intent(b_d, 'incident', 1.2);
    if not m.minted or m.status <> 'waived' or m.amount <> 0
      then v_bad := v_bad || ' 사건 민팅=' || m.status || '/' || m.amount; end if;
    if (select p.payment_key from payments p where p.id = m.payment_id) is not null
      then v_bad := v_bad || ' waived에 payment_key가 있다'; end if;
    if (select p.raw->>'rule' from payments p where p.id = m.payment_id) is distinct from 'incident_pending_review'
      then v_bad := v_bad || ' rule 미기록'; end if;
    -- and 'waived' cannot be used to hide a real amount
    begin
      insert into payments (booking_id, order_id, amount, status)
      values (b_d, 'ord_chg_fat_waive', 26900, 'waived');
      v_bad := v_bad || ' 금액 있는 waived:통과';
    exception when check_violation then null;
    end;
    if v_bad = ''
      then call _pass('chg','C6 waived 형상 — [0084] 사건 종료는 0원 waived 한 줄(키 없음·rule 기록)·0이 아닌 waived는 거부');
    else v_msg := v_bad; call _fail('chg','C6 waived 형상', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C6 waived 형상', v_msg);
  end;

  -- ---------- [C7] payments_settled_has_key admits waived and still refuses keyless confirmed ----------
  -- 0076's invariant is loosened by exactly one member. If it were dropped instead, a confirmed
  -- row with no payment_key becomes legal again = an approved charge we cannot refund.
  begin
    v_bad := '';
    begin
      insert into payments (booking_id, order_id, amount, status)
      values (bk1, 'ord_chg_waive_ok', 0, 'waived');
    exception when others then v_bad := v_bad || ' 키 없는 waived:거부됨(' || sqlerrm || ')';
    end;
    begin
      insert into payments (booking_id, order_id, amount, status)
      values (bk1, 'ord_chg_keyless_confirm', 100, 'confirmed');
      v_bad := v_bad || ' 키 없는 confirmed:통과';
    exception when check_violation then null;
    end;
    begin
      insert into payments (booking_id, order_id, amount, status)
      values (bk1, 'ord_chg_keyless_cancel', 100, 'canceled');
      v_bad := v_bad || ' 키 없는 canceled:통과';
    exception when check_violation then null;
    end;
    delete from payments where order_id = 'ord_chg_waive_ok';
    if v_bad = ''
      then call _pass('chg','C7 settled_has_key — waived는 키 없이 합법, confirmed/canceled는 여전히 키 필수');
    else v_msg := v_bad; call _fail('chg','C7 settled_has_key', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C7 settled_has_key', v_msg);
  end;

  -- ---------- [C8] debt derivation — anchored on runs/ledger/cancel_fee, never bookings.status ----------
  -- §0-ter #11 is the sharp one: after a failed charge the booking may be moved to
  -- incident_review or refund_pending, and a status-anchored lock would silently release.
  begin
    v_bad := '';
    -- ① settled + failed → locked
    o_dbt := t_user('chg_debt', 'owner');
    b_a := t_chg_bk(o_dbt, dg, rt, rr, 'completed', now() - interval '3 hours', 5.0, 9900, 15000, 0);
    perform t_chg_settled(b_a, 'completed', 5.0);
    insert into payments (booking_id, order_id, amount, status, raw)
    values (b_a, 'ord_chg_debt_1', 24900, 'failed', jsonb_build_object('kind','settle_charge','attempts',1))
    returning id into p_a;
    if not owner_has_unsettled_charge(o_dbt) then v_bad := v_bad || ' failed→잠금 안 됨'; end if;
    -- ② the status move must not release the lock (#11)
    update bookings set status = 'incident_review' where id = b_a;
    if not owner_has_unsettled_charge(o_dbt) then v_bad := v_bad || ' incident_review 이동에 잠금 해제됨'; end if;
    -- ③ collection succeeds → released
    update payments set status = 'confirmed', payment_key = 'tviva_chg_debt_ok' where id = p_a;
    if owner_has_unsettled_charge(o_dbt) then v_bad := v_bad || ' confirmed 후에도 잠김'; end if;

    -- ④ widget-era failed intent BEFORE service (booking never settled) → not debt
    o_pre := t_user('chg_pre', 'owner');
    b_b := t_chg_bk(o_pre, dg, rt, null, 'payment_hold', now() + interval '2 hours', 5.0, 9900, 15000, 0);
    insert into payments (booking_id, order_id, amount, status) values (b_b, 'ord_chg_pre_fail', 24900, 'failed');
    if owner_has_unsettled_charge(o_pre) then v_bad := v_bad || ' 서비스 전 실패가 잠금이 됨'; end if;

    -- ⑤ cancelled-with-fee is the second scope arm (§0-ter #5)
    o_fee := t_user('chg_fee', 'owner');
    b_c := t_chg_bk(o_fee, dg, rt, rr, 'cancelled_owner', now() + interval '2 hours', 5.0, 9900, 15000, 0);
    update bookings set cancel_fee = 12450, cancel_reason = 'owner_cancel_enroute' where id = b_c;
    insert into payments (booking_id, order_id, amount, status, raw)
    values (b_c, 'ord_chg_fee_fail', 12450, 'failed', jsonb_build_object('kind','cancel_fee','attempts',3));
    if not owner_has_unsettled_charge(o_fee) then v_bad := v_bad || ' 취소 수수료 미수가 잠금 아님'; end if;

    -- ⑥ dispatched-pending: stale = debt, fresh = not, never-dispatched = not
    o_disp := t_user('chg_disp', 'owner');
    b_d := t_chg_bk(o_disp, dg, rt, rr, 'completed', now() - interval '3 hours', 5.0, 9900, 15000, 0);
    perform t_chg_settled(b_d, 'completed', 5.0);
    insert into payments (booking_id, order_id, amount, status, raw)
    values (b_d, 'ord_chg_disp', 24900, 'pending',
            jsonb_build_object('kind','settle_charge','attempts',1,
                               'dispatched_at', (now() - interval '2 hours')::text))
    returning id into p_b;
    if not owner_has_unsettled_charge(o_disp) then v_bad := v_bad || ' 발송 후 1시간+ pending이 잠금 아님'; end if;
    update payments set raw = jsonb_set(raw, '{dispatched_at}', to_jsonb(now()::text)) where id = p_b;
    if owner_has_unsettled_charge(o_disp) then v_bad := v_bad || ' 방금 발송한 pending이 잠금이 됨'; end if;
    update payments set raw = raw - 'dispatched_at' where id = p_b;
    if owner_has_unsettled_charge(o_disp) then v_bad := v_bad || ' 미발송 pending이 잠금이 됨'; end if;

    -- ⑦ the client mirror is the same truth, scoped to auth.uid()
    perform set_config('request.jwt.claim.sub', o_fee::text, false);
    v_bool := my_unsettled_charge();
    perform set_config('request.jwt.claim.sub', o_pre::text, false);
    v_bool2 := my_unsettled_charge();
    perform set_config('request.jwt.claim.sub', '', false);
    if not v_bool or v_bool2 then v_bad := v_bad || ' my_unsettled_charge 스코프=' || v_bool::text || '/' || v_bool2::text; end if;

    -- ⑧ widget-era debris on a SETTLED booking must not lock (round-2 R1 P1-2). The §2 flow's
    -- shape exactly: the first widget intent failed, the retry succeeded (confirmed sibling), and
    -- the run later settled. The scope arm is satisfied and the `failed` arm would be too — so
    -- without the `raw.kind` restriction this owner is locked forever, and no CTA in the product
    -- can clear it (collect-charges refuses kind-less rows: handler.ts:75). The plan's dropped
    -- "no later confirmed row" clause is what `kind` restores, in a stronger form.
    declare
      o_widget uuid; b_w uuid;
    begin
      o_widget := t_user('chg_widget', 'owner');
      b_w := t_chg_bk(o_widget, dg, rt, rr, 'completed', now() - interval '3 hours', 5.0, 9900, 15000, 0);
      perform t_chg_settled(b_w, 'completed', 5.0);
      insert into payments (booking_id, order_id, amount, status)
      values (b_w, 'ord_chg_widget_lock_fail', 24900, 'failed');          -- kind-less: widget era
      insert into payments (booking_id, payment_key, order_id, amount, status)
      values (b_w, 'tviva_chg_widget_ok', 'ord_chg_widget_lock_ok', 24900, 'confirmed');
      if owner_has_unsettled_charge(o_widget)
        then v_bad := v_bad || ' 위젯 잔해(정산+confirmed 형제)가 잠금이 됨'; end if;
      -- positive control: the SAME row with raw.kind DOES lock (else ⑧ passes by coincidence)
      update payments set raw = jsonb_build_object('kind','settle_charge','attempts',1)
        where order_id = 'ord_chg_widget_lock_fail';
      if not owner_has_unsettled_charge(o_widget)
        then v_bad := v_bad || ' kind 붙은 같은 행이 잠금이 아니다 (⑧이 우연히 통과)'; end if;
      update payments set raw = '{}'::jsonb where order_id = 'ord_chg_widget_lock_fail';
    end;

    if v_bad = ''
      then call _pass('chg','C8 미수금 파생 — 정산 앵커는 runs/ledger(상태 이동 무관)·취소수수료 포함·발송1h+ pending만 미수·서비스 전 실패는 무관·정산된 예약의 위젯 잔해도 무관(kind 없는 행)·my_ 미러 스코프');
    else v_msg := v_bad; call _fail('chg','C8 미수금 파생', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('chg','C8 미수금 파생', v_msg);
  end;

  -- ---------- [C9] invariant #1 sweep — every settled booking has a row (§0-ter #1) ----------
  -- ⚠ GLOBAL: this mints for every settled booking in the database that lacks a row (the
  -- earlier suites' completed runs included). Assertions are therefore per-booking, plus a
  -- second-run delta for the "never double" half.
  begin
    v_bad := '';
    b_a := t_chg_bk(oo, dg, rt, rr, 'completed', now() - interval '4 hours', 5.0, 9900, 15000, 2000);
    perform t_chg_settled(b_a, 'completed', 4.0);                 -- 9900 + 12000 + 2000 = 23900
    b_b := t_chg_bk(oo, dg, rt, rr, 'completed', now() - interval '4 hours', 5.0, 9900, 15000, 2000);
    perform t_chg_settled(b_b, 'incident', 0.9);                  -- [0084] 사건 → waived
    b_c := t_chg_bk(oo, dg, rt, rr, 'completed', now() - interval '4 hours', 5.0, 9900, 15000, 2000);
    perform t_chg_settled(b_c, 'completed', 5.0);
    insert into payments (booking_id, payment_key, order_id, amount, status)
    values (b_c, 'tviva_chg_already', 'ord_chg_already', 26900, 'confirmed');  -- already has a row

    perform sweep_settled_without_payments();

    select p.status, p.amount into v_status, v_amount from payments p where p.booking_id = b_a;
    if v_status is distinct from 'pending' or v_amount is distinct from 23900
      then v_bad := v_bad || ' 미민팅 정산=' || coalesce(v_status,'∅') || '/' || coalesce(v_amount::text,'∅'); end if;
    select p.status, p.amount into v_status, v_amount from payments p where p.booking_id = b_b;
    if v_status is distinct from 'waived' or v_amount is distinct from 0
      then v_bad := v_bad || ' 사건 정산=' || coalesce(v_status,'∅') || '/' || coalesce(v_amount::text,'∅'); end if;

    select count(*) into v_pre from payments;
    perform sweep_settled_without_payments();
    select count(*) into v_n from payments;
    if v_n <> v_pre then v_bad := v_bad || ' 2회차 스윕이 ' || (v_n - v_pre) || '행 추가'; end if;
    select count(*) into v_n from payments where booking_id = b_c;
    if v_n <> 1 then v_bad := v_bad || ' 기존 행 있는 예약에 추가=' || v_n; end if;
    -- and the invariant itself now holds globally — in its post-amendment form: the sweep owes
    -- a row for runs that ended AT OR AFTER the cutover moment, and owes nothing for pilot-era
    -- runs (charging them retroactively is the failure this scope exists to prevent).
    -- "has a row" is the sweep's own definition (round-2 R3 P3-9): kind-bearing, or a row that
    -- settles the question (confirmed/waived). A run missing end_reason or actual_km is outside
    -- the invariant by design — the sweep refuses to price it rather than guess.
    select count(*) into v_n from bookings b join runs r on r.booking_id = b.id
      where r.ended_at is not null and r.end_reason is not null and r.actual_km is not null
        and r.ended_at >= (select f.payments_live_since from ops_flags f where f.id)
        and not exists (select 1 from payments p where p.booking_id = b.id
                          and ((p.raw->>'kind') is not null or p.status in ('confirmed','waived')));
    if v_n <> 0 then v_bad := v_bad || ' 결제행 없는 정산 예약 ' || v_n || '건 잔존'; end if;

    if v_bad = ''
      then call _pass('chg','C9 불변식 #1 스윕 — 정산됐는데 결제행 없는 예약을 민팅(23900)·[0084] 사건은 waived·기존 행은 불가침·2회차는 0행 (§0-ter #1)');
    else v_msg := v_bad; call _fail('chg','C9 불변식 #1 스윕', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C9 불변식 #1 스윕', v_msg);
  end;

  -- ---------- [C10] the stale sweep never closes a dispatched intent (§0-ter #2) ----------
  -- 0076's predicate was a widget argument (`payment_key is null` = nothing captured). For a
  -- server-initiated billing charge the key arrives only in the response, so a keyless pending
  -- may ALREADY have charged the card. The dispatched_at marker is the difference.
  begin
    v_bad := '';
    -- ⓐ never dispatched, keyless, old → the only class that may auto-fail
    insert into payments (booking_id, order_id, amount, status, created_at)
    values (bk1, 'ord_chg_stale_plain', 26900, 'pending', now() - interval '2 hours')
    returning id into p_a;
    -- ⓑ dispatched two hours ago → must SURVIVE (reconciliation's job, not the sweep's)
    insert into payments (booking_id, order_id, amount, status, created_at, raw)
    values (bk1, 'ord_chg_stale_disp', 26900, 'pending', now() - interval '2 hours',
            jsonb_build_object('kind','settle_charge','attempts',1,
                               'dispatched_at', (now() - interval '2 hours')::text))
    returning id into p_b;
    -- ⓒ 0076's original protected class — a pending that carries a payment_key
    insert into payments (booking_id, payment_key, order_id, amount, status, created_at)
    values (bk1, 'tviva_chg_captured', 'ord_chg_stale_key', 26900, 'pending', now() - interval '2 hours')
    returning id into p_c;
    -- ⓓ a fresh intent is not debris
    insert into payments (booking_id, order_id, amount, status)
    values (bk1, 'ord_chg_fresh', 26900, 'pending');

    select count(*) into v_pre from payments
     where status = 'pending' and payment_key is null and (raw->>'dispatched_at') is null
       and created_at < now() - interval '1 hour';
    select sweep_stale_payment_intents() into v_n;

    if (select p.status from payments p where p.id = p_a) <> 'failed' then v_bad := v_bad || ' 미발송 잔해:안 닫힘'; end if;
    if (select p.status from payments p where p.id = p_b) <> 'pending' then v_bad := v_bad || ' 발송된 pending:닫힘(장부 왜곡)'; end if;
    if (select p.status from payments p where p.id = p_c) <> 'pending' then v_bad := v_bad || ' 키 있는 pending:닫힘'; end if;
    if (select p.status from payments p where p.order_id = 'ord_chg_fresh') <> 'pending' then v_bad := v_bad || ' 새 인텐트:조기 종료'; end if;
    if v_n <> v_pre or v_pre < 1 then v_bad := v_bad || ' 반환=' || v_n || ' 기대=' || v_pre; end if;

    if v_bad = ''
      then call _pass('chg','C10 좌초 스윕 개정 — dispatched_at 있는 pending은 생존(토스에 이미 물어본 행), 미발송 키없는 1시간+만 failed (§0-ter #2)');
    else v_msg := v_bad; call _fail('chg','C10 좌초 스윕 개정', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C10 좌초 스윕 개정', v_msg);
  end;

  -- ---------- [C11] reconciliation's third arm has the rows the sweep now refuses ----------
  -- The sweep's new mercy is only correct if somebody reads what it spared. Also asserts the
  -- three kinds stay DISJOINT — an ops query that lists one row twice is a query nobody reads.
  begin
    v_bad := '';
    select count(*) into v_n from payments_reconciliation()
      where kind = 'stale_dispatched' and payment_id = p_b;
    if v_n <> 1 then v_bad := v_bad || ' stale_dispatched 미포착=' || v_n; end if;
    select count(*) into v_n from payments_reconciliation()
      where kind = 'stale_pending' and payment_id = p_b;
    if v_n <> 0 then v_bad := v_bad || ' 같은 행이 stale_pending에도=' || v_n; end if;
    select count(*) into v_n from payments_reconciliation()
      where kind = 'stale_pending' and payment_id = p_c;
    if v_n <> 1 then v_bad := v_bad || ' 키 있는 pending이 stale_pending에 없음=' || v_n; end if;
    if has_function_privilege('authenticated', 'payments_reconciliation()', 'execute')
      then v_bad := v_bad || ' authenticated:실행가능'; end if;

    -- the fourth arm (round-2 R1 P3): the ladder is spent, so nothing automatic will ever touch
    -- this row again — it is debt with no timer behind it, and ops is the only remaining reader.
    -- C8's ⑤ fixture is exactly that row (cancel_fee, attempts 3, still failed).
    select count(*) into v_n from payments_reconciliation()
      where kind = 'ladder_exhausted' and payment_id in
        (select id from payments where order_id = 'ord_chg_fee_fail');
    if v_n <> 1 then v_bad := v_bad || ' 래더 소진 행 미포착=' || v_n; end if;
    -- a failed row with rungs LEFT is not exhausted (else the arm is just "every failed row")
    insert into payments (booking_id, order_id, amount, status, raw)
    values (bk1, 'ord_chg_ladder_live', 26900, 'failed',
            jsonb_build_object('kind','settle_charge','attempts',1))
    returning id into v_id;
    select count(*) into v_n from payments_reconciliation()
      where kind = 'ladder_exhausted' and payment_id = v_id;
    if v_n <> 0 then v_bad := v_bad || ' 재시도 남은 failed가 소진으로 분류됨'; end if;
    -- and a kind-less widget failure is not this machine's row at all, at any attempt count
    update payments set raw = jsonb_build_object('attempts', 3) where id = v_id;
    select count(*) into v_n from payments_reconciliation()
      where kind = 'ladder_exhausted' and payment_id = v_id;
    if v_n <> 0 then v_bad := v_bad || ' kind 없는 위젯 실패가 소진으로 분류됨'; end if;
    delete from payments where id = v_id;

    -- DISJOINT, measured across the whole query rather than per fixture: an ops board that lists
    -- one row under two names is a board people stop reading.
    select count(*) into v_n from (
      select payment_id from payments_reconciliation() group by payment_id having count(*) > 1
    ) d;
    if v_n <> 0 then v_bad := v_bad || ' 두 팔에 동시 등장하는 행 ' || v_n || '개'; end if;

    -- probe debris out, so the next reader of the ops query does not inherit our noise
    delete from payments where order_id in
      ('ord_chg_stale_plain','ord_chg_stale_disp','ord_chg_stale_key','ord_chg_fresh');

    if v_bad = ''
      then call _pass('chg','C11 조정 질의 3·4번째 팔 — 발송 후 결과 미상 행은 stale_dispatched, 3회 실패로 끝난 행은 ladder_exhausted(재시도 남은 행·kind 없는 행은 제외), 네 팔 전부 서로소');
    else v_msg := v_bad; call _fail('chg','C11 조정 질의 3·4번째 팔', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C11 조정 질의 3·4번째 팔', v_msg);
  end;

  -- ---------- [C12] the failed-row partial index exists and is shaped like its query (§0-ter #12) ----------
  begin
    v_bad := '';
    select count(*) into v_n from pg_indexes
     where tablename = 'payments' and indexname = 'payments_failed_booking_idx'
       and indexdef ilike '%booking_id%' and indexdef ilike '%failed%';
    if v_n <> 1 then v_bad := v_bad || ' 부분 인덱스 없음/형상 불일치'; end if;
    if v_bad = ''
      then call _pass('chg','C12 failed 부분 인덱스 — payments(booking_id) where status=failed (미수금 파생·재시도 래더의 술어와 같은 모양)');
    else v_msg := v_bad; call _fail('chg','C12 failed 부분 인덱스', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C12 failed 부분 인덱스', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════
  -- recurring gates (§0-ter #3) — the cron that bypasses create-booking-hold's lock
  -- ═══════════════════════════════════════════════════════════════════════════════════
  declare
    o_rec uuid; d_r1 uuid; d_r2 uuid; b_r1 uuid; b_r2 uuid;
    s_r1 uuid; s_r2 uuid; v_when timestamptz; v_noti_pre int; v_noti int;
  begin
    o_rec := t_user('chg_recur', 'owner');
    d_r1 := t_dog(o_rec, '반복견1'); d_r2 := t_dog(o_rec, '반복견2');
    v_when := date_trunc('hour', now()) + interval '26 hours';
    b_r1 := t_chg_bk(o_rec, d_r1, rt, rr, 'confirmed', v_when, 5.0, 9900, 15000, 0);
    b_r2 := t_chg_bk(o_rec, d_r2, rt, rr, 'confirmed', v_when + interval '3 hours', 5.0, 9900, 15000, 0);
    perform set_config('request.jwt.claim.sub', o_rec::text, false);
    s_r1 := create_recurring_series(b_r1);
    s_r2 := create_recurring_series(b_r2);
    perform set_config('request.jwt.claim.sub', '', false);
    -- push the originals a week back so the next occurrence lands inside the 72h window
    update bookings set scheduled_at = scheduled_at - interval '7 days' where id in (b_r1, b_r2);

    -- ---------- [C13] debt gate — skip + notify, ONCE per owner per sweep ----------
    begin
      v_bad := '';
      b_a := t_chg_bk(o_rec, d_r1, rt, rr, 'completed', now() - interval '5 hours', 5.0, 9900, 15000, 0);
      perform t_chg_settled(b_a, 'completed', 5.0);
      insert into payments (booking_id, order_id, amount, status, raw)
      values (b_a, 'ord_chg_recur_debt', 24900, 'failed', jsonb_build_object('kind','settle_charge','attempts',3))
      returning id into p_a;

      select count(*) into v_noti_pre from notifications
        where profile_id = o_rec and title = '반복 예약 일시 중지';
      perform generate_recurring_bookings();
      select count(*) into v_n from bookings where series_id in (s_r1, s_r2) and id not in (b_r1, b_r2);
      select count(*) into v_noti from notifications
        where profile_id = o_rec and title = '반복 예약 일시 중지';

      if v_n <> 0 then v_bad := v_bad || ' 미수금 보호자에게 ' || v_n || '건 생성됨'; end if;
      if (v_noti - v_noti_pre) <> 1
        then v_bad := v_bad || ' 통지 ' || (v_noti - v_noti_pre) || '건 (시리즈 2개여도 1건이어야 한다)'; end if;
      if not exists (select 1 from notifications where profile_id = o_rec
                     and body like '반복 예약이 결제 문제로 쉬어가요%')
        then v_bad := v_bad || ' 통지 본문 불일치'; end if;

      delete from payments where id = p_a;      -- debt cleared for C14
      if v_bad = ''
        then call _pass('chg','C13 반복 예약 미수금 게이트 — 잠긴 보호자는 생성 0 + 스윕당 통지 1건(시리즈 2개여도) §0-ter #3');
      else v_msg := v_bad; call _fail('chg','C13 반복 예약 미수금 게이트', v_msg); end if;
    exception when others then v_msg := sqlerrm; call _fail('chg','C13 반복 예약 미수금 게이트', v_msg);
    end;

    -- ---------- [C14] instrument gate is SWITCH-KEYED — today's behavior survives the migration ----------
    -- The whole cutover promise is here: while payments_live_since is NULL, a card-less owner
    -- keeps getting their recurring runs exactly as they do today. Setting the moment is what
    -- makes a missing billing key a reason to stop.
    begin
      v_bad := '';
      if exists (select 1 from billing_keys where profile_id = o_rec)
        then v_bad := v_bad || ' 픽스처 오염: 이미 카드 있음'; end if;

      -- ⓐ switch off (the shipped default), no card → generation proceeds (0026 behavior preserved)
      update ops_flags set payments_live_since = null, updated_at = now();
      perform generate_recurring_bookings();
      select count(*) into v_n from bookings where series_id in (s_r1, s_r2) and id not in (b_r1, b_r2);
      if v_n <> 2 then v_bad := v_bad || ' 컷오버 전 생성=' || v_n || ' (2 기대)'; end if;
      delete from bookings where series_id in (s_r1, s_r2) and id not in (b_r1, b_r2);

      -- ⓑ switch on, still no card → skip + notify
      update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();
      select count(*) into v_noti_pre from notifications
        where profile_id = o_rec and title = '반복 예약 일시 중지';
      perform generate_recurring_bookings();
      select count(*) into v_n from bookings where series_id in (s_r1, s_r2) and id not in (b_r1, b_r2);
      select count(*) into v_noti from notifications
        where profile_id = o_rec and title = '반복 예약 일시 중지';
      if v_n <> 0 then v_bad := v_bad || ' 컷오버 후 카드 없이 생성=' || v_n; end if;
      if (v_noti - v_noti_pre) <> 1 then v_bad := v_bad || ' 카드 없음 통지=' || (v_noti - v_noti_pre); end if;

      -- ⓒ card linked → generation resumes
      insert into billing_keys (profile_id, billing_key, card)
      values (o_rec, 'bkey_chg_recur', jsonb_build_object('brand','신한','last4','4242'));
      perform generate_recurring_bookings();
      select count(*) into v_n from bookings where series_id in (s_r1, s_r2) and id not in (b_r1, b_r2);
      if v_n <> 2 then v_bad := v_bad || ' 카드 연결 후 생성=' || v_n || ' (2 기대)'; end if;

      if v_bad = ''
        then call _pass('chg','C14 반복 예약 결제수단 게이트 — payments_live_since가 NULL이면 카드 없이도 오늘처럼 생성, 설정되면 중단+통지, 카드 연결 시 재개');
      else v_msg := v_bad; call _fail('chg','C14 반복 예약 결제수단 게이트', v_msg); end if;
    exception when others then
      v_msg := sqlerrm; call _fail('chg','C14 반복 예약 결제수단 게이트', v_msg);
    end;
    -- leave the suite's live baseline in place regardless of how C14 exited
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();
  end;

  -- ---------- [C15] billing_keys + ops_flags are SEALED (RLS, zero policies, read AND write) ----------
  -- 68 V1's law, applied by hand because these two tables are not in that array (this suite
  -- cannot edit 68). The 빌링키 is a bearer credential: a read leak is a charge leak.
  begin
    v_bad := '';
    if not exists (select 1 from pg_class where relname = 'billing_keys' and relrowsecurity)
      then v_bad := v_bad || ' billing_keys:RLS off'; end if;
    if not exists (select 1 from pg_class where relname = 'ops_flags' and relrowsecurity)
      then v_bad := v_bad || ' ops_flags:RLS off'; end if;
    select count(*) into v_n from pg_policies where tablename in ('billing_keys','ops_flags');
    if v_n <> 0 then v_bad := v_bad || ' 정책 ' || v_n || '개 (0이어야 한다)'; end if;

    -- the card's OWNER is refused too — the only legitimate read is my_billing_card()
    v_key := (select f.payments_live_since::text from ops_flags f where f.id);   -- pre-probe value
    o_card := t_user('chg_card', 'owner');
    insert into billing_keys (profile_id, billing_key, card)
    values (o_card, 'bkey_chg_sealed', jsonb_build_object('brand','국민','last4','9999'));
    perform set_config('request.jwt.claim.sub', o_card::text, false);
    begin
      set local role authenticated;
      select count(*) into v_n from billing_keys;
      select count(*) into v_n2 from ops_flags;
      reset role;
      if v_n <> 0 then v_bad := v_bad || ' 소유자에게 billing_keys ' || v_n || '행'; end if;
      if v_n2 <> 0 then v_bad := v_bad || ' authenticated에게 ops_flags ' || v_n2 || '행'; end if;
    exception when others then reset role; v_bad := v_bad || ' 읽기 프로브 오류';
    end;
    reset role;
    begin
      set local role anon;
      perform set_config('request.jwt.claim.sub', '', true);
      select count(*) into v_n from billing_keys;
      reset role;
      if v_n <> 0 then v_bad := v_bad || ' anon에게 billing_keys ' || v_n || '행'; end if;
    exception when others then reset role; v_bad := v_bad || ' anon 프로브 오류';
    end;
    reset role;
    -- writes: insert must raise, update/delete must touch nothing
    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin
      set local role authenticated;
      insert into billing_keys (profile_id, billing_key) values (oo, 'forged');
      v_bad := v_bad || ' 클라 insert:통과';
      reset role;
    exception when others then reset role;
    end;
    reset role;
    begin
      set local role authenticated;
      update ops_flags set payments_live_since = now();
      if found then v_bad := v_bad || ' 클라 update:행변경'; end if;
      reset role;
    exception when others then reset role;
    end;
    reset role;
    begin
      set local role authenticated;
      delete from billing_keys;
      if found then v_bad := v_bad || ' 클라 delete:행삭제'; end if;
      reset role;
    exception when others then reset role;
    end;
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);
    if (select f.payments_live_since::text from ops_flags f where f.id) is distinct from v_key
      then v_bad := v_bad || ' 컷오버 시점이 클라 쓰기로 움직였다'; end if;

    if v_bad = ''
      then call _pass('chg','C15 봉인 — billing_keys·ops_flags RLS on·정책 0·anon/authenticated/카드 소유자 전부 0행·insert/update/delete 거부');
    else v_msg := v_bad; call _fail('chg','C15 봉인', v_msg); end if;
  exception when others then reset role; perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('chg','C15 봉인', v_msg);
  end;

  -- ---------- [C16] my_billing_card — mine only, display fields only ----------
  begin
    v_bad := '';
    insert into billing_keys (profile_id, billing_key, card)
    values (oo, 'bkey_chg_oo_secret', jsonb_build_object('brand','현대','last4','1111'))
    on conflict (profile_id) do update set billing_key = excluded.billing_key, card = excluded.card;

    perform set_config('request.jwt.claim.sub', oo::text, false);
    select count(*) into v_n from my_billing_card();
    if v_n <> 1 then v_bad := v_bad || ' 본인 카드 행수=' || v_n; end if;
    if exists (select 1 from my_billing_card() x where x.brand <> '현대' or x.last4 <> '1111')
      then v_bad := v_bad || ' 표시 필드 불일치'; end if;
    perform set_config('request.jwt.claim.sub', oz::text, false);
    select count(*) into v_n from my_billing_card();
    if v_n <> 0 then v_bad := v_bad || ' 타인에게 ' || v_n || '행'; end if;
    perform set_config('request.jwt.claim.sub', '', false);
    select count(*) into v_n from my_billing_card();
    if v_n <> 0 then v_bad := v_bad || ' 미인증에게 ' || v_n || '행'; end if;

    -- the key itself has no place in the return shape (structural, not value-based)
    select count(*) into v_n
    from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality as a(n, m, o)
    where p.proname = 'my_billing_card' and p.pronamespace = 'public'::regnamespace
      and a.m = 't' and a.n ~* 'billing|key|token|secret';
    if v_n <> 0 then v_bad := v_bad || ' 반환 형상에 키스러운 컬럼 ' || v_n || '개'; end if;
    if not has_function_privilege('authenticated', 'my_billing_card()', 'execute')
      then v_bad := v_bad || ' authenticated 실행 불가 (설정 화면이 죽는다)'; end if;
    -- the GRANT is the seal, not the query's luck: a signed-out caller returns zero rows today
    -- only because auth.uid() is null, and that is a property of the body, not of the ACL.
    if has_function_privilege('anon', 'my_billing_card()', 'execute')
      then v_bad := v_bad || ' anon 실행 가능 (0080의 revoke가 사라졌다)'; end if;

    if v_bad = ''
      then call _pass('chg','C16 my_billing_card — 본인 1행(brand/last4)·타인 0행·미인증 0행·anon 실행 불가·billing_key는 반환 형상에 자리 자체가 없음');
    else v_msg := v_bad; call _fail('chg','C16 my_billing_card', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('chg','C16 my_billing_card', v_msg);
  end;

  -- ---------- [C17] e_match copy is conditional on money actually having been taken ----------
  -- ⚠ GLOBAL: expire_unmatched_bookings() is a batch (100 W7 runs it too). Assertions are by
  -- ref_id. The prepaid booking keeps 0060's refund promise; the post-pay booking gets the
  -- honest sentence. The two-sibling-CTE contract and e_hold's silence are W7's pins, not ours.
  begin
    v_bad := '';
    b_a := t_chg_bk(oo, dg, rt, null, 'matching', now() - interval '90 minutes', 5.0, 9900, 15000, 0);
    insert into payments (booking_id, payment_key, order_id, amount, status)
    values (b_a, 'tviva_chg_e_prepaid', 'ord_chg_e_prepaid', 24900, 'confirmed');
    b_b := t_chg_bk(oz, dg, rt, null, 'matching', now() - interval '90 minutes', 5.0, 9900, 15000, 0);

    perform expire_unmatched_bookings();

    select count(*) into v_n from notifications
      where ref_id = b_a and title = '매칭 만료' and body = '시작 시간까지 러너를 찾지 못했어요 — 전액 환불 처리돼요';
    if v_n <> 1 then v_bad := v_bad || ' 선결제 예약의 환불 문장=' || v_n; end if;
    select count(*) into v_n from notifications
      where ref_id = b_b and title = '매칭 만료' and body = '시작 시간까지 러너를 찾지 못했어요 — 결제된 금액이 없어 청구되지 않아요';
    if v_n <> 1 then v_bad := v_bad || ' 후불 예약의 정직 문장=' || v_n; end if;
    select count(*) into v_n from notifications where ref_id = b_b and body like '%환불%';
    if v_n <> 0 then v_bad := v_bad || ' 후불 예약에 환불 약속 ' || v_n || '건'; end if;
    if (select status::text from bookings where id = b_b) <> 'expired'
      then v_bad := v_bad || ' 만료 동작 자체가 깨졌다'; end if;

    if v_bad = ''
      then call _pass('chg','C17 매칭 만료 카피 — 선결제 예약만 "전액 환불 처리돼요", 후불 예약은 "결제된 금액이 없어 청구되지 않아요" (§0-ter #13)');
    else v_msg := v_bad; call _fail('chg','C17 매칭 만료 카피', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C17 매칭 만료 카피', v_msg);
  end;

  -- ---------- [C18] 0072 step ⑥ copy is conditional too ----------
  -- Fixture is built by direct insert rather than through the club RPC chain: this pin is about
  -- ONE sentence, and reproducing the delegation flow would make it fail for a dozen unrelated
  -- reasons (110 owns that flow). Both bookings are subjects of the same case, settled
  -- 'refund_full' (refund = total_price > 0 — the only branch whose copy moved).
  declare
    v_club uuid; v_sess uuid; v_inc uuid; b_pp uuid; b_np uuid; v_js jsonb;
  begin
    v_bad := '';
    insert into club_test_accounts (profile_id, note) values (rr, 'chg suite')
      on conflict (profile_id) do nothing;
    insert into clubs (name, district, host_profile_id) values ('청구 클럽', '성수동', rr)
      returning id into v_club;
    insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
      values (v_club, rr, now() + interval '2 days', '청구 집결지') returning id into v_sess;
    insert into club_incidents (session_id, severity, state, opened_by, case_owner, summary)
      values (v_sess, 'S2', 'open', rr, rr, '카피 픽스처') returning id into v_inc;

    b_pp := t_av_booking(oo, dg, rt, rr, now() - interval '1 hour', 5.0, 'incident_review');
    b_np := t_av_booking(oz, dg, rt, rr, now() - interval '1 hour', 5.0, 'incident_review');
    insert into club_incident_subjects (incident_id, subject_type, subject_id)
      values (v_inc, 'booking', b_pp), (v_inc, 'booking', b_np);
    insert into payments (booking_id, payment_key, order_id, amount, status)
      values (b_pp, 'tviva_chg_club_prepaid', 'ord_chg_club_prepaid', 24900, 'confirmed');

    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_js := club_incident_settle(v_inc, b_pp, 'refund_full', '선결제 케이스');
    v_js := club_incident_settle(v_inc, b_np, 'refund_full', '후불 케이스');
    perform set_config('request.jwt.claim.sub', '', false);

    select count(*) into v_n from notifications
      where ref_id = b_pp and title = '케이스 정산 결정' and body = '24900원이 환불돼요 — 케이스에서 근거를 볼 수 있어요';
    if v_n <> 1 then v_bad := v_bad || ' 선결제 케이스의 환불 문장=' || v_n; end if;
    select count(*) into v_n from notifications
      where ref_id = b_np and title = '케이스 정산 결정' and body = '이번 건은 청구되지 않아요 — 케이스에서 근거를 볼 수 있어요';
    if v_n <> 1 then v_bad := v_bad || ' 후불 케이스의 정직 문장=' || v_n; end if;
    select count(*) into v_n from notifications where ref_id = b_np and body like '%환불%';
    if v_n <> 0 then v_bad := v_bad || ' 후불 케이스에 환불 약속 ' || v_n || '건'; end if;
    -- the money logic itself is untouched (R6 scope): both bookings moved and both got fee items
    select count(*) into v_n from club_fee_items where booking_id in (b_pp, b_np) and kind = 'incident_settlement';
    if v_n <> 2 then v_bad := v_bad || ' 정산 근거 행=' || v_n; end if;
    if (select status::text from bookings where id = b_np) <> 'refund_pending'
      then v_bad := v_bad || ' 부킹 이동이 깨졌다'; end if;

    if v_bad = ''
      then call _pass('chg','C18 케이스 정산 카피 — 잡힌 돈이 있는 케이스만 "24900원이 환불돼요", 후불 케이스는 "이번 건은 청구되지 않아요" (돈 로직은 0072 그대로)');
    else v_msg := v_bad; call _fail('chg','C18 케이스 정산 카피', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('chg','C18 케이스 정산 카피', v_msg);
  end;

  -- ---------- [C19] en-route cancel compensation — the runner's only ledger path ----------
  -- settle_run_tx never runs for cancelled_owner, so without this the 50% Sean defined as
  -- runner compensation (2026-08-11) reaches the runner through nothing at all.
  begin
    v_bad := '';
    b_a := t_chg_bk(oo, dg, rt, rr, 'cancelled_owner', now() + interval '2 hours', 5.0, 9900, 15000, 0);
    update bookings set cancel_fee = 12450, cancel_reason = 'owner_cancel_enroute' where id = b_a;
    select * into m from record_enroute_cancel_comp(b_a);
    if not m.written or m.comp <> 12450 then v_bad := v_bad || ' 1회차=' || m.comp || '/' || m.written::text; end if;
    select count(*) into v_n from ledger_items where booking_id = b_a;
    if v_n <> 1 then v_bad := v_bad || ' 원장 행수=' || v_n; end if;
    if exists (select 1 from ledger_items li where li.booking_id = b_a
               and (li.remaining_guarantee <> 12450 or li.platform_fee <> 0
                    or li.base <> 0 or li.distance_pay <> 0 or li.addon_pay <> 0 or li.tip <> 0))
      then v_bad := v_bad || ' 원장 형상 불일치 (전액 보상·수수료 0이어야 한다)'; end if;
    if (select li.runner_id from ledger_items li where li.booking_id = b_a) <> rr
      then v_bad := v_bad || ' 수취인이 그 러너가 아니다'; end if;
    -- idempotent: a retry of the cancel action must not pay twice
    select * into m2 from record_enroute_cancel_comp(b_a);
    select count(*) into v_n from ledger_items where booking_id = b_a;
    if m2.written or v_n <> 1 then v_bad := v_bad || ' 2회차=' || m2.written::text || ' 행수=' || v_n; end if;

    -- the free tier (unmatched cancel, no fee, no en-route reason) writes nothing
    b_b := t_chg_bk(oo, dg, rt, rr, 'cancelled_owner', now() + interval '2 hours', 5.0, 9900, 15000, 0);
    update bookings set cancel_fee = 0 where id = b_b;
    select * into m from record_enroute_cancel_comp(b_b);
    select count(*) into v_n from ledger_items where booking_id = b_b;
    if m.written or m.comp <> 0 or v_n <> 0 then v_bad := v_bad || ' 무료 취소에 보상 기록=' || v_n; end if;

    if v_bad = ''
      then call _pass('chg','C19 인루트 취소 보상 — 수수료 전액이 러너 원장으로(수수료 0)·재호출 멱등·무료 취소는 무기록 (§0-ter #5)');
    else v_msg := v_bad; call _fail('chg','C19 인루트 취소 보상', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C19 인루트 취소 보상', v_msg);
  end;

  -- ---------- [C20] cancel-fee mint — same rails, and zero mints nothing (§0-ter #13) ----------
  begin
    v_bad := '';
    b_a := t_chg_bk(oo, dg, rt, rr, 'cancelled_owner', now() + interval '2 hours', 5.0, 9900, 15000, 0);
    update bookings set cancel_fee = 2490, cancel_reason = 'owner_cancel' where id = b_a;
    select * into m from mint_cancel_fee_intent(b_a);
    if not m.minted or m.amount <> 2490 or m.status <> 'pending'
      then v_bad := v_bad || ' 민팅=' || m.amount || '/' || m.status || '/' || m.minted::text; end if;
    if (select p.raw->>'kind' from payments p where p.id = m.payment_id) is distinct from 'cancel_fee'
      then v_bad := v_bad || ' raw.kind가 cancel_fee가 아니다'; end if;
    select * into m2 from mint_cancel_fee_intent(b_a);
    select count(*) into v_n from payments where booking_id = b_a;
    if m2.minted or v_n <> 1 then v_bad := v_bad || ' 재민팅=' || m2.minted::text || ' 행수=' || v_n; end if;

    -- fee 0 → nothing at all (matching expiry / free-tier cancels charge nothing)
    b_b := t_chg_bk(oo, dg, rt, null, 'cancelled_owner', now() + interval '2 hours', 5.0, 9900, 15000, 0);
    update bookings set cancel_fee = 0 where id = b_b;
    select count(*) into v_n from mint_cancel_fee_intent(b_b);
    select count(*) into v_n2 from payments where booking_id = b_b;
    if v_n <> 0 or v_n2 <> 0 then v_bad := v_bad || ' 수수료 0에서 행 ' || v_n || '/' || v_n2; end if;

    if v_bad = ''
      then call _pass('chg','C20 취소 수수료 민팅 — 같은 레일(kind=cancel_fee)·멱등·수수료 0이면 아무것도 만들지 않는다 (§0-ter #13)');
    else v_msg := v_bad; call _fail('chg','C20 취소 수수료 민팅', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C20 취소 수수료 민팅', v_msg);
  end;

  -- ---------- [C21] grant matrix — the charge machinery is server-only ----------
  -- A definer function bypasses payments' RLS by construction, so an execute grant is the whole
  -- seal. A client that can call mint_settle_charge_intent can mint its own charge intents;
  -- one that can call compute_owner_charge can enumerate other people's prices.
  declare
    fns text[] := array[
      'compute_owner_charge(uuid,text,numeric)',
      'mint_settle_charge_intent(uuid,text,numeric)',
      'mint_cancel_fee_intent(uuid)',
      'owner_has_unsettled_charge(uuid)',
      'sweep_settled_without_payments()',
      -- recreated by 0080 (§I) rather than written fresh, so its seal is INHERITED through
      -- `create or replace` from 0076:102. An inherited ACL is exactly the kind that a later
      -- recreate drops without anybody noticing, which is why it belongs in this array.
      'sweep_stale_payment_intents()',
      'record_enroute_cancel_comp(uuid)',
      'dispatch_due_charges()'];
    f text;
  begin
    v_bad := '';
    foreach f in array fns loop
      if to_regprocedure(f) is null then v_bad := v_bad || ' ' || f || ':없음'; continue; end if;
      if has_function_privilege('authenticated', f, 'execute') then v_bad := v_bad || ' ' || f || ':authenticated'; end if;
      if has_function_privilege('anon', f, 'execute') then v_bad := v_bad || ' ' || f || ':anon'; end if;
      if not has_function_privilege('service_role', f, 'execute') then v_bad := v_bad || ' ' || f || ':service_role 불가'; end if;
    end loop;
    -- positive control: the two client RPCs ARE callable (else this pin proves nothing)
    if not has_function_privilege('authenticated', 'my_unsettled_charge()', 'execute')
      then v_bad := v_bad || ' my_unsettled_charge:authenticated 불가'; end if;
    if has_function_privilege('anon', 'my_unsettled_charge()', 'execute')
      then v_bad := v_bad || ' my_unsettled_charge:anon 가능'; end if;

    if v_bad = ''
      then call _pass('chg','C21 권한 매트릭스 — 청구 기계 8종은 service_role 전용, 클라 RPC 2종만 authenticated (양성 대조 포함)');
    else v_msg := v_bad; call _fail('chg','C21 권한 매트릭스', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C21 권한 매트릭스', v_msg);
  end;

  -- ---------- [C23] the PG's floor — a charge Toss would refuse is never minted ----------
  -- round-2 R1 P2-2. Below ₩100 the PG declines by rule, so an intent minted there is a permanent
  -- decline: three ladder rungs, three notifications, a debt state and an account lock, over an
  -- amount smaller than the messages about it. The arm returns 0, and the mint therefore writes a
  -- `waived` row — the event is still recorded, exactly as G1 is.
  declare
    b_min uuid;
  begin
    v_bad := '';
    -- implied 2,000/km (10,000 over 5.0km), so the runner_personal distance component is
    -- 0.05km → ₩100 exactly, and 0.045km → ₩90. The boundary is probed on both sides because
    -- `< 100` and `<= 100` are different rules and only one of them is Toss's.
    b_min := t_chg_bk(oo, dg, rt, rr, 'completed', now() - interval '2 hours', 5.0, 9900, 10000, 0);
    select * into c from compute_owner_charge(b_min, 'runner_personal', 0.045);
    if c.amount <> 0 or c.rule <> 'below_pg_minimum'
      then v_bad := v_bad || ' 90원=' || c.amount || '/' || c.rule; end if;
    select * into c from compute_owner_charge(b_min, 'runner_personal', 0.05);
    if c.amount <> 100 or c.rule <> 'runner_personal_distance_only'
      then v_bad := v_bad || ' 정확히 100원=' || c.amount || '/' || c.rule; end if;
    -- zero stays zero-with-its-own-rule: the floor arm must not swallow the deliberate zero.
    -- [0084 §A] that zero is now `incident` alone — dog_condition became a real charge, and its
    -- own relationship with the floor (a frozen base under ₩100 falls through to below_pg_minimum
    -- rather than duplicating the rule) is pinned in 120 J1.
    select * into c from compute_owner_charge(b_min, 'incident', 0.01);
    if c.rule <> 'incident_pending_review' then v_bad := v_bad || ' 사건 0원이 최소금액 팔에 삼켜짐=' || c.rule; end if;
    -- and a 0km end is still 'actual_capped' 9,900 (base+addons keep it far above the floor)
    select * into c from compute_owner_charge(b_min, 'completed', 0);
    if c.amount <> 9900 or c.rule <> 'actual_capped'
      then v_bad := v_bad || ' 기본요금 있는 종료가 최소금액 팔로=' || c.amount || '/' || c.rule; end if;

    -- the mint's half: a sub-floor charge becomes a waived row, never a pending one with a ladder
    perform t_chg_settled(b_min, 'runner_personal', 0.02);
    select * into m from mint_settle_charge_intent(b_min, 'runner_personal', 0.02);
    if not m.minted or m.status <> 'waived' or m.amount <> 0
      then v_bad := v_bad || ' 민팅=' || m.status || '/' || m.amount; end if;
    if (select p.raw->>'rule' from payments p where p.id = m.payment_id) is distinct from 'below_pg_minimum'
      then v_bad := v_bad || ' rule 미기록'; end if;
    if (select p.raw ? 'attempts' from payments p where p.id = m.payment_id)
      then v_bad := v_bad || ' waived에 래더(attempts)가 붙었다'; end if;

    if v_bad = ''
      then call _pass('chg','C23 PG 최소 결제금액 — 0원 초과 100원 미만은 청구하지 않고 waived로 기록(below_pg_minimum)·정확히 100원은 청구·G1/기본요금 팔은 불변 (round-2 R1 P2-2)');
    else v_msg := v_bad; call _fail('chg','C23 PG 최소 결제금액', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C23 PG 최소 결제금액', v_msg);
  end;

  -- ---------- [C24] the invariant-#1 sweep's two blind spots ----------
  -- ⚠ GLOBAL (sweep_settled_without_payments is a whole-table batch — per-booking assertions).
  --   ⓐ round-2 R3 P3-9: "has a payments row" must mean what the MINT means by it. A kind-less
  --      widget row captured nothing and does not block the mint, so letting it block the sweep
  --      leaves a settled booking with no charge intent and nothing left to notice.
  --   ⓑ round-2 R1 P3: a run with no actual_km cannot be priced. Charging base + addons on a
  --      guessed 0 km is the same sin as guessing 'completed' for a missing end_reason.
  declare
    b_dbr uuid; b_nokm uuid;
  begin
    v_bad := '';
    -- ⓐ settled booking whose only payments row is widget-era debris (canceled — which the
    -- settled_has_key invariant requires to carry its key, so it is real widget debris)
    b_dbr := t_chg_bk(oo, dg, rt, rr, 'completed', now() - interval '6 hours', 5.0, 9900, 15000, 2000);
    perform t_chg_settled(b_dbr, 'completed', 4.0);                 -- 9900 + 12000 + 2000 = 23900
    insert into payments (booking_id, payment_key, order_id, amount, status)
    values (b_dbr, 'tviva_chg_sweep_dbr', 'ord_chg_sweep_widget_cancel', 26900, 'canceled');

    -- ⓑ settled run with no measured distance
    -- [0083 amendment] settled_at joins the fixture for the same reason it joined
    -- t_chg_settled: since 0083, "the run stopped" and "money happened" are two columns.
    b_nokm := t_chg_bk(oo, dg, rt, rr, 'completed', now() - interval '6 hours', 5.0, 9900, 15000, 2000);
    insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
    values (b_nokm, now() - interval '40 minutes', now(), now(), null, 'completed');

    perform sweep_settled_without_payments();

    select p.status, p.amount into v_status, v_amount from payments p
      where p.booking_id = b_dbr and (p.raw->>'kind') is not null;
    if v_status is distinct from 'pending' or v_amount is distinct from 23900
      then v_bad := v_bad || ' 위젯 잔해가 스윕을 가렸다=' || coalesce(v_status,'∅') || '/' || coalesce(v_amount::text,'∅'); end if;
    select count(*) into v_n from payments where booking_id = b_dbr;
    if v_n <> 2 then v_bad := v_bad || ' 잔해 예약 행수=' || v_n; end if;

    select count(*) into v_n from payments where booking_id = b_nokm;
    if v_n <> 0 then v_bad := v_bad || ' 거리 없는 러닝을 청구했다=' || v_n; end if;
    -- positive control: measure the run and the SAME sweep mints it (so ⓑ is a refusal to price,
    -- not the sweep failing to see the booking at all)
    update runs set actual_km = 3.0 where booking_id = b_nokm;
    perform sweep_settled_without_payments();
    select p.status, p.amount into v_status, v_amount from payments p where p.booking_id = b_nokm;
    if v_status is distinct from 'pending' or v_amount is distinct from 20900   -- 9900+9000+2000
      then v_bad := v_bad || ' 거리 채운 뒤에도 민팅 안 됨=' || coalesce(v_status,'∅') || '/' || coalesce(v_amount::text,'∅'); end if;

    if v_bad = ''
      then call _pass('chg','C24 스윕 사각지대 — kind 없는 위젯 잔해는 스윕을 가리지 못하고(민팅과 같은 정의), actual_km 없는 러닝은 추측 청구 대신 건너뛴다(거리 채우면 민팅)');
    else v_msg := v_bad; call _fail('chg','C24 스윕 사각지대', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C24 스윕 사각지대', v_msg);
  end;

  -- ---------- [C25] closing a minted intent tells the owner; closing debris does not ----------
  -- round-2 R1 P3. An hour after this flip §F reads the row as debt and create-booking-hold starts
  -- refusing new bookings — so silence here means the owner learns about it by being refused. The
  -- copy names what actually happened (we could not ATTEMPT the charge; the card did not decline)
  -- and points at 설정 > 결제 관리. Widget debris stays silent: nothing was minted, nothing is
  -- owed, and there is nothing for the owner to do (100 W7's e_hold argument, same shape).
  declare
    b_note uuid; b_dbg uuid;
  begin
    v_bad := '';
    b_note := t_chg_bk(oo, dg, rt, rr, 'completed', now() - interval '7 hours', 5.0, 9900, 15000, 0);
    insert into payments (booking_id, order_id, amount, status, created_at, raw)
    values (b_note, 'ord_chg_note_kind', 24900, 'pending', now() - interval '2 hours',
            jsonb_build_object('kind','settle_charge','attempts',0));
    b_dbg := t_chg_bk(oz, dg, rt, rr, 'completed', now() - interval '7 hours', 5.0, 9900, 15000, 0);
    insert into payments (booking_id, order_id, amount, status, created_at)
    values (b_dbg, 'ord_chg_note_widget', 24900, 'pending', now() - interval '2 hours');

    perform sweep_stale_payment_intents();

    -- both rows close (else the notification difference is just "one of them never flipped")
    if (select p.status from payments p where p.order_id = 'ord_chg_note_kind') <> 'failed'
      then v_bad := v_bad || ' kind 행이 닫히지 않음'; end if;
    if (select p.status from payments p where p.order_id = 'ord_chg_note_widget') <> 'failed'
      then v_bad := v_bad || ' 위젯 행이 닫히지 않음'; end if;

    select count(*) into v_n from notifications
      where ref_id = b_note and kind = 'booking' and title = '결제 처리 안내'
        and body = '지난 러닝 이용료 결제를 시도하지 못했어요 — 설정 > 결제 관리에서 확인해주세요';
    if v_n <> 1 then v_bad := v_bad || ' 민팅 행 통지=' || v_n || ' (정확히 1건)'; end if;
    if (select profile_id from notifications where ref_id = b_note and title = '결제 처리 안내' limit 1) <> oo
      then v_bad := v_bad || ' 통지 수신자가 그 보호자가 아니다'; end if;
    select count(*) into v_n from notifications where ref_id = b_dbg;
    if v_n <> 0 then v_bad := v_bad || ' 위젯 잔해가 ' || v_n || '건 통지했다'; end if;

    if v_bad = ''
      then call _pass('chg','C25 좌초 스윕 통지 — 서버가 민팅한 행을 닫을 때만 보호자에게 "결제 처리 안내"(설정 > 결제 관리) 1건, kind 없는 위젯 잔해는 침묵');
    else v_msg := v_bad; call _fail('chg','C25 좌초 스윕 통지', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('chg','C25 좌초 스윕 통지', v_msg);
  end;

  -- ---------- [C22] the cutover switch is a LINE IN TIME, not a light switch ----------
  -- Two failures a boolean would have shipped (Unit B's report, 2026-08-13), pinned as one
  -- claim because they are the same claim from both sides of the moment:
  --   ⓐ while charging is OFF, the mints write NOTHING. A pending intent minted for a card-less
  --      pilot owner is flipped to `failed` by the 1h stale sweep an hour later, and §F then
  --      reads that as debt — a pilot-wide account lock manufactured out of a feature nobody
  --      turned on yet.
  --   ⓑ after the flip, runs that ended BEFORE the moment are never charged, by the mint or by
  --      the invariant-#1 sweep. Otherwise the morning after the cutover bills every free pilot
  --      run ever recorded. This is the money pin of the amendment.
  declare
    b_old uuid; b_new uuid;
  begin
    v_bad := '';
    update ops_flags set payments_live_since = null, updated_at = now();

    b_old := t_chg_bk(oo, dg, rt, rr, 'completed', now() - interval '40 days', 5.0, 9900, 15000, 0);
    insert into runs (booking_id, started_at, ended_at, actual_km, end_reason)
    values (b_old, now() - interval '40 days', now() - interval '40 days', 5.0, 'completed');
    b_d := t_chg_bk(oo, dg, rt, rr, 'cancelled_owner', now() + interval '2 hours', 5.0, 9900, 15000, 0);
    update bookings set cancel_fee = 2490, cancel_reason = 'owner_cancel' where id = b_d;

    -- ⓐ charging off: both mints are silent, and the sweep does nothing
    select count(*) into v_n from mint_settle_charge_intent(b_old, 'completed', 5.0);
    if v_n <> 0 then v_bad := v_bad || ' OFF인데 settle 민팅 ' || v_n || '행 반환'; end if;
    select count(*) into v_n from mint_cancel_fee_intent(b_d);
    if v_n <> 0 then v_bad := v_bad || ' OFF인데 cancel_fee 민팅 ' || v_n || '행 반환'; end if;
    select count(*) into v_n from payments where booking_id in (b_old, b_d);
    if v_n <> 0 then v_bad := v_bad || ' OFF인데 결제행 ' || v_n || '건 생성'; end if;
    select sweep_settled_without_payments() into v_n;
    if v_n <> 0 then v_bad := v_bad || ' OFF인데 스윕이 ' || v_n || '건 민팅'; end if;

    -- ⓑ flip the switch to an hour ago: the 40-day-old run stays free, forever
    update ops_flags set payments_live_since = now() - interval '1 hour', updated_at = now();
    select count(*) into v_n from mint_settle_charge_intent(b_old, 'completed', 5.0);
    if v_n <> 0 then v_bad := v_bad || ' 컷오버 이전 러닝을 민팅했다'; end if;
    perform sweep_settled_without_payments();
    select count(*) into v_n from payments where booking_id = b_old;
    if v_n <> 0 then v_bad := v_bad || ' 스윕이 컷오버 이전 러닝을 소급 청구했다 (' || v_n || '행)'; end if;

    -- ⓒ and a run that ends after the moment IS charged — otherwise ⓐⓑ pass by doing nothing
    b_new := t_chg_bk(oo, dg, rt, rr, 'completed', now() - interval '20 minutes', 5.0, 9900, 15000, 0);
    perform t_chg_settled(b_new, 'completed', 5.0);
    select * into m from mint_settle_charge_intent(b_new, 'completed', 5.0);
    if not coalesce(m.minted, false) or m.amount <> 24900
      then v_bad := v_bad || ' 컷오버 이후 러닝이 청구되지 않는다=' || coalesce(m.amount::text,'∅'); end if;

    -- restore the SHIPPED default (charging off) — this is the state 0080 leaves behind
    update ops_flags set payments_live_since = null, updated_at = now();

    if v_bad = ''
      then call _pass('chg','C22 컷오버 시점 — OFF면 두 민팅·스윕 전부 무기록(거짓 미수금 없음), 켠 뒤에도 이전 러닝은 영구 무료, 이후 러닝만 청구');
    else v_msg := v_bad; call _fail('chg','C22 컷오버 시점', v_msg); end if;
  exception when others then
    update ops_flags set payments_live_since = null;
    v_msg := sqlerrm; call _fail('chg','C22 컷오버 시점', v_msg);
  end;
end $$;
