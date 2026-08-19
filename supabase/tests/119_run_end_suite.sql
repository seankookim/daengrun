-- ═══ 119 run-end suite — 0083 pins (the freeze · the seal · 귀가 · the janitor) ═══
-- What this suite pins: that 귀가 is a SERVER INVARIANT rather than a screen behaviour. Every
--   claim below was a sentence somebody could have written in a plan and shipped without; two
--   adversarial rounds (a product/state-machine reviewer and codex on the money path) turned
--   each of them into a hole with a name, and these are those holes measured.
-- Style: sibling of 103/115/116 — `_pass('ren',…)`/`_fail('ren',…)`, one begin…exception per
--   case. ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
--   Money facts are read through `compute_owner_charge` / the mint rather than recomputed with
--   the function's own expression (105's law).
-- ⚠ NO PIN IN THIS FILE ASSERTS A G1 AMOUNT. `dog_condition` / `incident` pricing is Sean's
--   ruling landing in a sibling migration (the payments session's 0084), and a fixture that
--   hardcoded ₩0 or a base fare would go red under it FOR A CORRECT REASON — the worst kind of
--   red. Every charge figure here is either read out of `compute_owner_charge` at assertion time
--   or belongs to the `completed` arm, which no ruling touches.
-- ⚠ Global side effects, deliberately (this suite runs last): R10/R11 set
--   `ops_flags.payments_live_since` and R4 sets `ops_flags.return_seal_since`; both are restored
--   to the shipped NULL by their own last act, and R14 re-asserts that restoration at the end so
--   a mid-suite exception cannot leave the cutover switch on for the next reader.
--   R12 calls `sweep_run_end_recovery()` and R10/R11 call `sweep_settled_without_payments()` —
--   whole-table batches, so every affected assertion is per-booking or a delta (100 W7 idiom).
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   R1  ← §3: drop the `bookings.run_ended_at` stamp from end_run_tx, or let it move the booking
--         status (the freeze must be invisible to the state machine — plan §1)          → RED
--   R2  ← §2: delete the `_guard_booking_insert` trigger (a client draft is then born holding a
--         forged return stamp), or drop `run_ended_at is not null` from `_guard_run_cols`
--         (a runner rewrites the frozen distance during 귀가), or drop the `run_ended`
--         rejection from append_run_event/append_run_photo (a 응가 event stamped after the
--         stop, which settle_run_tx pays +30 miles for — 0028:88)                        → RED
--   R3  ← §6: settle inside confirm_return_tx on the FIRST stamp instead of on both        → RED
--   R4  ← §6: delete either arm of settle_run_tx's seal gate — the `return_not_sealed`
--         raise (settlement mid-귀가, codex's verified bypass) or the `run_not_ended`
--         raise (an old client settling a run it never ended, plan §2)                    → RED
--   R5  ← 0089 §2: let `force_return_tx` accept `runner` or `owner` again (delete the
--         `force_party_forbidden` raise) — from the phone OR from the server class, which is
--         the same hole one caller-class away                                             → RED
--         · or drop its `evidence_required` / `reason_required` refusals, or its ops gate  → RED
--         · or re-introduce a grace period before an ops force is permitted (ⓓ's positive
--           control forces seconds after the stop and would go red)                       → RED
--   R6  ← 0089 §2: stop recording the ops force (actor/eligible_at/reason/evidence), or let a
--         second force overwrite the first (the first resolution is what a dispute reads) → RED
--         · 🔴 or restore 0083's `runner_confirmed_return_at = case when p_side = 'runner'…`
--           — write ANY party confirmation stamp from a force. That inference ("implied by the
--           act") is precisely what Sean's 2026-08-13 ruling denies, and this is the pin that
--           stops it coming back                                                          → RED
--   R7  ← §8: delete the `owner_la_run_end` trigger — the owner's lock screen keeps saying
--         러닝 중 for the whole walk home (plan §4d)                                       → RED
--   R8  ← §8: drop `b.run_ended_at is null` from owner_la_sweep_stale's arm ① (every 귀가
--         gets "위치가 갱신되지 않았어요" 90s in), or drop the `run_ended_at` guard from
--         `_owner_la_trace_tg` (the final trace commit pushes a 러닝 중 banner), or point
--         arm ② at runs.trace instead of custody_last_seen_at (plan §5)                   → RED
--   R9  ← §3/§6: make end_run_tx raise instead of returning {unchanged:true} on a second
--         stop, or drop `_settle_sealed_run`'s already-settled branch so the loser of a
--         concurrent return gets a raw `not_active` (plan §3's last sentence)             → RED
--   R10 ← §6-ⓒ: restore `ended_at = excluded.ended_at` in settle_run_tx's on-conflict (a run
--         that STOPPED before the cutover is charged because it SETTLED after it — codex
--         #3 scenario A, and the whole reason runs.settled_at exists)                     → RED
--   R11 ← §1/§6: write `runs.settled_at` anywhere other than settle_run_tx (at the stop, say,
--         alongside ended_at) — the column stops meaning "money happened" and the scenario-B
--         fix that 0080's sweep is about to be built on quietly becomes a no-op       → RED
--         ⚠ SCENARIO B ITSELF IS NOT CLOSED IN THIS SLICE and this pin does not claim it is.
--         `sweep_settled_without_payments` (0080 §G) still anchors on `runs.ended_at`, which
--         now means the STOP — so post-cutover it would charge an unreturned dog. That
--         function belongs to 0080 and is being modified by the payments session in this
--         same wave, so re-creating it from here would silently revert their work. The fix
--         is one predicate in their file (`and rn.settled_at is not null`); the migration's
--         §0f states it, and `payments_live_since` must not be flipped before it lands.
--         What R11 pins is the PROPERTY that fix depends on.
--   R12 ← §9: delete the 2h escalation from sweep_run_end_recovery — a return nobody confirmed
--         stays `active` forever and blocks the runner's FUTURE accepts
--         (transition-booking/index.ts:58)                                                 → RED
--         · or make the sweep invent a settlement for a sealed row (it has no price — §0g)  → RED
--   R13 ← §3/§6: grant execute on end_run_tx to authenticated (a client that freezes its own
--         basis without crossing the edge function), or drop any revoke in the array      → RED
--         · 0089 §6: re-grant `force_return_tx` to `authenticated`. It moved out of the
--           client-facing control group and into the service_role-only array in this file for
--           the same reason it lost the party path: a phone has no business adjudicating a
--           return, so it must not even hold the privilege                                 → RED
--         · its sibling, pinned by R3: drop the `quote_from_client` refusal so a client-role
--           caller may hand confirm_return_tx / force_return_tx a PRICE                    → RED
--   R14 ← §3/§6: widen end_run_tx's end_reason whitelist to the full enum — a runner freezes
--         `incident` (owner charged nothing, G1 pre-empted) or `owner_forced` (owner
--         charged the full planned distance), and `settle-run` refuses both with a named
--         400, so the run freezes into a state that can NEVER settle                      → RED
--   R15 ← §6-ⓔ (settle_run_tx's freeze enforcement): delete the `frozen_measurement_mismatch`
--         gate, or restore
--         `actual_km/end_reason = excluded.…` in its on-conflict — the client's POST body
--         then decides the runner's payout AND (through the mint) the owner's charge on a
--         run whose numbers were frozen at the stop                                       → RED
--         · or refuse a differing `duration_sec` instead of preserving it (a run that can
--           never settle — plan §1's deadlock rule) → RED via R15's positive-control arm
--   R16 ← §9-ⓑ: drop `settlement_ready_at is null` from the escalation predicate — a sealed
--         booking whose settlement died is pushed into `incident_review`, which no money
--         path can leave (0066:56 allows only → refund_pending, and club_incident_settle is
--         club-only), so the runner becomes permanently unpayable                         → RED
--         · or move the sealed row's alarm from a notification to a status change          → RED
--   R17 ← §6's force_return_tx: restore `return {'forced':false,'settled':true,'unchanged':true}`
--         on its re-entry branch — it claims a settlement on a row it left `active`,
--         and the ops retry carrying the price (the only caller allowed to carry one)
--         never settles                                                                    → RED
--         · 0089 §2: the whole sequence is now ops→ops (an ops seal, then an ops retry with
--           the price). A revert that let a PARTY drive either leg reddens R5, not this pin;
--           what R17 owns is that the re-entry branch tells the truth about settlement.
--
--   ─── the CONCURRENCY half is pinned outside this file ───
--   One connection cannot race itself, so R9 pins the SEQUENTIAL idempotence (a second stop,
--   a second confirm, a second force) and the already-settled verification branch. The genuine
--   two-connection claim — two confirm_return_tx calls landing on the second stamp at once must
--   produce ONE ledger row — belongs in `90_race_check.sh` alongside RD/RE and is named here as
--   the gap it is, rather than pretended away (110's S1 lesson).
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-13. Method: the revert was applied to a COPY
--     of the migration at a short path (the harness cannot run from a worktree — macOS's 103-byte
--     Unix socket limit), the md5 of the mutated file was recorded, `rm -rf .pgtest` gave a clean
--     cluster, the WHOLE harness ran, and the tree was then restored from the pristine source and
--     re-verified by md5 + a green run. Green with this suite is **478/0** (baseline with 0084
--     present, this suite absent from the count: 475/0).
--     Pristine 0083 md5 `565f2d2c26b302a0e801b21aa9d0b3d1`. ⚠ The three runs below were executed
--     against `9f6e0fad15fdaff2f04f363b3cc88712`, which differs from the shipped file by ONE
--     COMMENT ONLY (the push-routing note in §9); that revision was re-run green afterwards, and
--     the exact md5s are recorded rather than smoothed over so a later reader can check.
--       R15 settle_run_tx's whole `frozen_measurement_mismatch` block deleted (§6-ⓔ, the freeze
--           enforcement) → 477/1, red = [R15] alone,
--           detail `동결 후 다른 숫자로 정산:통과 … 거부됐는데 상태가 움직였다 거부됐는데 원장이
--           생겼다` — the attack end to end: a booking frozen at 3.2km/`completed`, sealed by both
--           sides, settled on a POSTed 9.9km/`owner_request` with the ledger to match.
--       R16 §9-ⓑ's `settlement_ready_at is null` predicate deleted → 477/1, red = [R16] alone,
--           detail `씰 행을 승격시켰다(러너 영구 미지급)=incident_review … 스윕 뒤 정산 불가=
--           not_active … 재구동 원장 행수=0` — the dead end, measured as the thing it actually
--           costs: not a wrong status, an unpayable runner.
--       R17 §6's force re-entry restored to `{'forced':false,'settled':true,'unchanged':true}`
--           → 477/1, red = [R17] alone, detail `방금 정산해놓고 unchanged=true 재진입 정산 뒤에도
--           completed 아님 원장 행수=0` — `settled: true` on a booking with no ledger row.
--     ─── earlier rounds (against the pre-fix file, md5 `9caa848aec3fa0cac0e1ac26bc90b63f`) ───
--       R4  §6's `return_not_sealed` raise deleted → 462/3, red = [R4, R5, R6].
--           R4's own detail is the bypass reproducing verbatim: `귀가 중 직접 정산:통과 …
--           거부됐는데 원장이 생겼다`. The two cascades are CORRECT, not noise: R5/R6 exercise the
--           force valves on the same booking R4 proves is unsettleable, so once a mid-귀가 settle
--           succeeds they are measuring an already-completed booking. Named here rather than
--           engineered away — separating the fixtures would hide that these three pins are three
--           probes of one gate.
--       R10 §6-ⓒ's `ended_at = coalesce(runs.ended_at, …)` reverted to `excluded.ended_at`
--           → 464/1, red = [R10] alone, detail `정산이 정지 시각을 현재로 끌어왔다 (컷오버 버그
--           재발) 컷오버 이전 정지 러닝을 민팅했다 스윕이 … 청구했다 (1행)` — codex #3 scenario A
--           reproducing end to end, from the timestamp through the mint to the sweep.
--       R3  §6-ⓓ/ⓔ's `quote_from_client` refusal deleted (both entry points) → 464/1,
--           red = [R3] alone, detail `클라가 가격을 넘겼다` — a client-role caller handing the
--           server the runner's payout.
--       R2  §4's `run_ended` rejection deleted from append_run_event → 464/1, red = [R2] alone,
--           detail `종료 후 이벤트 append:통과 이벤트가 실제로 들어갔다` — the 응가 stamp after
--           the stop that `settle_run_tx` pays +30 miles for (0028:88).
--     The remaining pins are NOT machine-proven; each is named above with the single revert that
--     would redden it, and their probe shapes are clones of already-proven siblings (103 L7-L13
--     for the LA arms, 116 C21 for the grant matrix, 100 W7 for the batch-delta idiom).
--     ─── 0089 round (2026-08-13, Sean's both-parties ruling) ───
--     R5/R6/R13/R17 were REWRITTEN, not repaired: their subject (a party may force a return) was
--     ruled out of existence, so they now pin its absence. Green with 0089 and its sibling suite
--     125 present is **511/0** (this suite's own count is unchanged at 17 pins). Pristine 0089
--     md5 `d2be2fc506d18d816de64be37df188ab`. Two reverts were executed against a COPY at a
--     short path, then restored byte-for-byte by md5 and re-run green:
--       0089 §6's ops-only door collapsed to `if p_side not in ('runner','owner','ops') then
--           raise exception 'bad_side'` (the party path back, recording `ops`) → 508/3,
--           red = [R5, R6, 125 F2]. R5's detail `러너 강제 거부 사유=not_party … 서버가 러너 대신
--           강제:통과 거부된 시도가 강제를 기록했다 거부된 시도가 씰을 찍었다` — the SERVER-class
--           arm is the one that goes through, which is precisely the caller class ⓐ added.
--       0089 §6's stamp comment replaced by 0083's inference (`runner_confirmed_return_at =
--           coalesce(b.runner_confirmed_return_at, v_now)` + the owner twin) → 507/4,
--           red = [R6, R17, 125 F3, 125 F4]. R6's detail is the reverted sentence, named:
--           `강제가 러너 확인 스탬프를 찍었다 (0083의 "행위에 내포됨" 부활) 강제가 보호자 확인
--           스탬프를 찍었다 …`. R17 reddens on BOTH its legs (the unsettled seal and the settled
--           retry), which is the point of asserting the stamps twice there.
set client_min_messages = warning;

-- ---------- suite-local helpers ----------
-- An `active` marketplace booking with a live runs row — the state a run is in the moment before
-- the runner presses stop. Fare columns are explicit so the frozen-quote assertions below read
-- against literals rather than against today's constants.
create or replace function t_ren_live(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'active', now() - interval '40 minutes', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into v;
  insert into runs (booking_id, started_at, trace)
  values (v, now() - interval '40 minutes', '[]'::jsonb);
  return v;
end $$;

-- The payout the edge function computes AT SETTLE from the frozen measurement and hands to
-- confirm_return_tx / force_return_tx. A fixture, not a rule: this suite is not the place that
-- owns pricing, and since Sean's G1 ruling the real basis depends on end_reason — which is
-- exactly why 0083 freezes the measurement and takes the price as an argument (migration §0g).
create or replace function t_ren_quote(p_km numeric) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'base', 9900, 'distance_pay', round(p_km * 3000)::int, 'addon_pay', 0,
    'guarantee', 0, 'fee', round((9900 + round(p_km * 3000)) * 0.2)::int)
$$;

do $$
declare
  oo uuid; oz uuid; rr uuid; rz uuid; dg uuid; rt uuid;
  bk uuid; b_a uuid; b_b uuid; b_c uuid;
  v_bad text := ''; v_msg text; v_n int; v_n2 int; v_txt text; v_pre int;
  v_js jsonb; v_ts timestamptz; v_ts2 timestamptz; v_km numeric; v_base bigint;
  v_body jsonb; v_amount int; v_status text;
  v_club uuid; v_sess uuid;
begin
  oo := t_user('ren_oo', 'owner'); oz := t_user('ren_oz', 'owner');
  rr := t_user('ren_rr', 'runner'); rz := t_user('ren_rz', 'runner');
  dg := t_dog(oo, '귀가견'); rt := t_route('귀가 코스');

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R1] the freeze happens WITHOUT a status change (plan §1)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The whole design rests on this: stopping the run must not move the booking, because the dog
  -- is still in the runner's hands and every custody-inclusive consumer (available_runners,
  -- pickup-address access) has to keep behaving as if it is. The freeze is a column, not a state.
  begin
    v_bad := '';
    bk := t_ren_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_js := end_run_tx(bk, 3.2, 2100, 'completed', null,
                       jsonb_build_array(jsonb_build_object('lat', 37.51, 'lng', 127.01, 't', 1)));
    perform set_config('request.jwt.claim.sub', '', false);

    if coalesce((v_js->>'unchanged')::boolean, true) then v_bad := v_bad || ' unchanged=true'; end if;
    if (select b.status::text from bookings b where b.id = bk) <> 'active'
      then v_bad := v_bad || ' 상태가 움직였다=' || (select b.status::text from bookings b where b.id = bk); end if;
    if (select b.run_ended_at from bookings b where b.id = bk) is null
      then v_bad := v_bad || ' run_ended_at 미기록'; end if;
    select r.actual_km, r.duration_sec, r.end_reason::text, r.ended_at, r.settled_at
      into v_km, v_n, v_txt, v_ts, v_ts2
      from runs r where r.booking_id = bk;
    if v_km <> 3.2 or v_n <> 2100 or v_txt <> 'completed'
      then v_bad := v_bad || ' 동결값=' || v_km || '/' || v_n || '/' || v_txt; end if;
    if v_ts is null then v_bad := v_bad || ' ended_at(정지 시각) 미기록'; end if;
    if v_ts2 is not null then v_bad := v_bad || ' 정지인데 settled_at이 찍혔다'; end if;
    if (select jsonb_array_length(r.trace) from runs r where r.booking_id = bk) <> 1
      then v_bad := v_bad || ' 마지막 트레이스가 커밋되지 않았다'; end if;

    if v_bad = ''
      then call _pass('ren','R1 동결 — 러너 정지가 부킹 상태를 움직이지 않고(active 유지) 거리·시간·사유·트레이스와 ended_at(=정지 시각)을 얼린다(돈은 얼지 않는다), settled_at은 아직 없다');
    else v_msg := v_bad; call _fail('ren','R1 동결', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R1 동결', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R2] no client forgery — of a stamp, of a frozen number, or of a post-stop event
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- `bk` is the booking R1 just froze; the runner below is its own runner, so every refusal here
  -- is a refusal of the MOST privileged client that exists for this row.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rr::text, false);

    -- ⓐ the stamps are not client-writable (0058 deny-all — restated because these columns are new)
    begin
      set local role authenticated;
      update bookings set owner_confirmed_return_at = now() where id = bk;
      reset role;
      v_bad := v_bad || ' 귀가 스탬프 직접 쓰기:통과';
    exception when others then reset role;
    end;
    reset role;

    -- ⓑ …and cannot be smuggled in through an INSERT.
    -- ⚠ UPDATED 2026-08-19 by `0111_booking_entry_rebuild.sql`. This arm's PARENTHETICAL was
    --   "(plan §7 — owners may insert drafts)" and that is no longer true: 0111 revokes client
    --   INSERT on `bookings` outright and drops `bookings owner insert`, because a client-forged
    --   draft could name another user's dog and an arbitrary victim as `runner_id` (measured
    --   ACCEPTED against production). So this refusal is now a **42501 grant refusal**, not the
    --   **P0001** raise of `_guard_booking_insert_cols` — whose client branch is unreachable by
    --   construction from here on. The BEHAVIOURAL assertion is unchanged and still worth its
    --   line: a client cannot land a draft carrying a return stamp. The new property (why) is
    --   owned by suite 146 D-4·D-5·D-6 (executed refusals) and D-20 (the grant catalog).
    --   ⚠ **And the cost, stated plainly so a future re-grant is not made blind:** whoever ever
    --   re-grants client INSERT on `bookings` gets `_guard_booking_insert_cols`'s 12-column
    --   return/handoff blacklist back **UNTESTED**. This arm used to be its test. After 0111 the
    --   guard's `current_user in ('authenticated','anon')` branch is unreachable BY CONSTRUCTION,
    --   so that property is now pinned by nothing here — and it cannot be, because no pin can
    --   reach the branch. Restoring the grant means re-writing this arm's expectation back to
    --   P0001 first, not merely observing that the harness is still green.
    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin
      set local role authenticated;
      insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare,
                            addon_fare, total_price, min_fare, owner_confirmed_return_at)
      values (oo, dg, 'draft', now() + interval '1 day', 5.0, 9900, 15000, 0, 24900, 9900, now());
      reset role;
      v_bad := v_bad || ' 초안에 귀가 스탬프 심기:통과';
    exception when others then reset role;
    end;
    reset role;
    -- positive control: the same insert WITHOUT the stamp is still legal — so ⓑ is not passing
    -- because booking creation is dead.
    -- ⚠ UPDATED 2026-08-19 by 0111: this ran as `authenticated` and asserted that an OWNER could
    --   insert a clean draft. After 0111 no client can insert a booking at all, so that claim is
    --   false and the control has to move to the role that legitimately writes this row —
    --   `service_role`, which is what `create-booking-hold` uses. The control's PURPOSE is
    --   unchanged and still load-bearing: ⓑ must not be green merely because the write path
    --   itself is broken. Suite 146 D-11 owns the same property for the full hold path
    --   (bookings + slot_holds), and D-20 pins that `service_role` keeps INSERT on all three
    --   tables — the failure mode that turns a revoke into an outage.
    begin
      set local role service_role;
      insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare,
                            addon_fare, total_price, min_fare)
      values (oo, dg, 'draft', now() + interval '1 day', 5.0, 9900, 15000, 0, 24900, 9900);
      reset role;
    exception when others then reset role;
      v_bad := v_bad || ' 서버(service_role) 초안 insert도 거부됨 (ⓑ가 우연히 통과 — 예약 생성이 죽었다)';
    end;
    reset role;

    -- ⓒ the frozen run row is closed to the runner during 귀가
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      set local role authenticated;
      update runs set actual_km = 9.9 where booking_id = bk;
      reset role;
      v_bad := v_bad || ' 동결 거리 덮어쓰기:통과';
    exception when others then reset role;
    end;
    reset role;
    begin
      set local role authenticated;
      update runs set trace = '[]'::jsonb where booking_id = bk;
      reset role;
      v_bad := v_bad || ' 종료 후 트레이스 쓰기:통과';
    exception when others then reset role;
    end;
    reset role;

    -- ⓓ the append RPCs — the verified gap: a 응가 event stamped after stopping is +30 miles
    begin
      perform append_run_event(bk, jsonb_build_object('kind','poop','at', now()));
      v_bad := v_bad || ' 종료 후 이벤트 append:통과';
    exception when others then
      if sqlerrm <> 'run_ended' then v_bad := v_bad || ' 이벤트 거부 사유=' || sqlerrm; end if;
    end;
    begin
      perform append_run_photo(bk, 'https://x/y.jpg');
      v_bad := v_bad || ' 종료 후 사진 append:통과';
    exception when others then
      if sqlerrm <> 'run_ended' then v_bad := v_bad || ' 사진 거부 사유=' || sqlerrm; end if;
    end;
    if (select coalesce(jsonb_array_length(r.events), 0) from runs r where r.booking_id = bk) <> 0
      then v_bad := v_bad || ' 이벤트가 실제로 들어갔다'; end if;

    -- positive control: the SAME append on a still-running booking works (else ⓓ proves nothing)
    b_a := t_ren_live(oo, dg, rt, rr);
    begin
      perform append_run_event(b_a, jsonb_build_object('kind','poop','at', now()));
    exception when others then v_bad := v_bad || ' 러닝 중 append도 거부됨 (ⓓ가 우연히 통과): ' || sqlerrm;
    end;
    if (select coalesce(jsonb_array_length(r.events), 0) from runs r where r.booking_id = b_a) <> 1
      then v_bad := v_bad || ' 러닝 중 append가 기록되지 않았다'; end if;
    perform set_config('request.jwt.claim.sub', '', false);

    if v_bad = ''
      then call _pass('ren','R2 위조 불가 — 귀가 스탬프는 update로도 draft insert로도 못 심고, 동결된 거리·트레이스는 러너 본인도 못 바꾸고, 종료 뒤 이벤트·사진 append는 run_ended로 거부(러닝 중에는 정상 동작)');
    else v_msg := v_bad; call _fail('ren','R2 위조 불가', v_msg); end if;
  exception when others then reset role; perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R2 위조 불가', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R3] one stamp is not a return — and settlement is not permitted on it
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_js := confirm_return_tx(bk, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);

    if not coalesce((v_js->>'stamped')::boolean, false) then v_bad := v_bad || ' 러너 스탬프 미기록'; end if;
    if coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 한쪽 스탬프로 정산됨'; end if;
    if (select b.status::text from bookings b where b.id = bk) <> 'active'
      then v_bad := v_bad || ' 한쪽 스탬프에 부킹이 종결됨'; end if;
    if (select b.settlement_ready_at from bookings b where b.id = bk) is not null
      then v_bad := v_bad || ' 한쪽 스탬프에 씰이 찍혔다'; end if;
    if exists (select 1 from ledger_items li where li.booking_id = bk)
      then v_bad := v_bad || ' 원장 행이 생겼다'; end if;
    -- the runner cannot stamp the owner's side for them
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      v_js := confirm_return_tx(bk, 'owner');
      v_bad := v_bad || ' 러너가 보호자 스탬프를 찍었다';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' 상대측 스탬프 거부 사유=' || sqlerrm; end if;
    end;
    -- …and a caller with an identity of its own can never hand the server a PRICE. Settlement is
    -- priced by the code that owns pricing; a client that could pass a quote would be a client
    -- that pays itself (migration §6-ⓓ).
    begin
      v_js := confirm_return_tx(bk, 'runner', t_ren_quote(3.2));
      v_bad := v_bad || ' 클라가 가격을 넘겼다';
    exception when others then
      if sqlerrm <> 'quote_from_client' then v_bad := v_bad || ' 클라 가격 거부 사유=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);

    if v_bad = ''
      then call _pass('ren','R3 한쪽 스탬프는 정산이 아니다 — 러너 확인만으로는 씰도 원장도 없고 부킹은 active 그대로, 러너가 보호자 몫을 대신 찍을 수도, 가격을 넘길 수도 없다 (Sean D-r2)');
    else v_msg := v_bad; call _fail('ren','R3 한쪽 스탬프', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R3 한쪽 스탬프', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R4] `completed` is UNREACHABLE without both stamps or a recorded force (plan §2)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The bypass codex found, measured from both directions: the run that stopped and has not been
  -- returned, and the old client settling a run it never ended at all.
  begin
    v_bad := '';
    -- ⓐ ended, one stamp, direct settle_run_tx (this IS what settle-run does today)
    begin
      perform settle_run_tx(bk, 3.2, 2100, 'completed', null, 9900, 9600, 0, 0, 3900);
      v_bad := v_bad || ' 귀가 중 직접 정산:통과';
    exception when others then
      if sqlerrm <> 'return_not_sealed' then v_bad := v_bad || ' 귀가 중 정산 거부 사유=' || sqlerrm; end if;
    end;
    if (select b.status::text from bookings b where b.id = bk) <> 'active'
      then v_bad := v_bad || ' 거부됐는데 상태가 움직였다'; end if;
    if exists (select 1 from ledger_items li where li.booking_id = bk)
      then v_bad := v_bad || ' 거부됐는데 원장이 생겼다'; end if;

    -- ⓑ the OLD-CLIENT arm: a run that never ended. Ungated while the switch is NULL (today's
    -- behaviour, which is what lets this migration deploy before the new build reaches phones),
    -- refused with a DISTINCT code once Sean sets it (§9 D-r4①).
    b_b := t_ren_live(oz, dg, rt, rz);
    if (select f.return_seal_since from ops_flags f where f.id) is not null
      then v_bad := v_bad || ' 픽스처 오염: 씰 스위치가 이미 켜져 있다'; end if;
    update ops_flags set return_seal_since = now() - interval '1 hour', updated_at = now();
    begin
      perform settle_run_tx(b_b, 5.0, 2100, 'completed', null, 9900, 15000, 0, 0, 4980);
      v_bad := v_bad || ' 스위치 ON인데 종료 없는 정산:통과';
    exception when others then
      if sqlerrm <> 'run_not_ended' then v_bad := v_bad || ' 구 클라 거부 사유=' || sqlerrm; end if;
    end;
    if (select b.status::text from bookings b where b.id = b_b) <> 'active'
      then v_bad := v_bad || ' 구 클라 거부인데 상태가 움직였다'; end if;
    -- a run STARTED before the moment finishes under the old rule (nothing on a phone strands)
    update runs set started_at = now() - interval '3 hours' where booking_id = b_b;
    begin
      perform settle_run_tx(b_b, 5.0, 2100, 'completed', null, 9900, 15000, 0, 0, 4980);
    exception when others then v_bad := v_bad || ' 스위치 이전에 시작된 러닝이 정산 불가=' || sqlerrm;
    end;
    if (select b.status::text from bookings b where b.id = b_b) <> 'completed'
      then v_bad := v_bad || ' 스위치 이전 시작 러닝이 정산되지 않았다'; end if;
    update ops_flags set return_seal_since = null, updated_at = now();   -- restore the shipped default

    if v_bad = ''
      then call _pass('ren','R4 씰 게이트 — 귀가 중 직접 정산은 return_not_sealed(상태·원장 무변화), 스위치 켠 뒤 종료 기록 없는 정산은 run_not_ended("앱 업데이트"), 스위치 이전에 시작된 러닝은 구 규칙으로 끝난다');
    else v_msg := v_bad; call _fail('ren','R4 씰 게이트', v_msg); end if;
  exception when others then
    update ops_flags set return_seal_since = null;
    v_msg := sqlerrm; call _fail('ren','R4 씰 게이트', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R15] the seal is not enough — the FROZEN NUMBERS are enforced on the path that ships
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- R4 proves settlement is impossible before the dog is home. It does NOT prove that the
  -- settlement which then happens is the one that was frozen — and it could not, because its
  -- probe hands `settle_run_tx` the numbers that already match the frozen row, so a mismatch is
  -- never attempted. R6 does read the frozen row, but through `force_return_tx` →
  -- `_settle_sealed_run`, i.e. the HELPER. The shipping caller is neither:
  -- `settle-run/handler.ts:113-124` calls `settle_run_tx` DIRECTLY with `p.actual_km` /
  -- `p.end_reason` off the HTTP body. This pin is that exact call, made after the seal.
  -- The attack it measures: freeze 3.2km/`completed` on a 5km plan, seal both sides, then POST
  -- 9.9km/`owner_request` — inside settle-run's own validity band (planned×2+2) — for a runner
  -- paid on 9.9km plus the owner_request guarantee AND an owner billed the full planned distance.
  begin
    v_bad := '';
    b_a := t_ren_live(oo, dg, rt, rr);                     -- 계획 5.0km
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b_a, 3.2, 2100, 'completed', null, null);
    perform confirm_return_tx(b_a, 'runner');
    perform set_config('request.jwt.claim.sub', oo::text, false);
    perform confirm_return_tx(b_a, 'owner');               -- 씰만 (클라는 가격을 못 넘긴다)
    perform set_config('request.jwt.claim.sub', '', false);
    if (select b.settlement_ready_at from bookings b where b.id = b_a) is null
      then v_bad := v_bad || ' 픽스처: 씰이 안 찍혔다'; end if;

    -- ⓐ 거리와 사유를 함께 바꾼 정산 (그 공격 그대로)
    begin
      perform settle_run_tx(b_a, 9.9, 2100, 'owner_request', null, 9900, 29700, 0, 2550, 8000);
      v_bad := v_bad || ' 동결 후 다른 숫자로 정산:통과';
    exception when others then
      if sqlerrm <> 'frozen_measurement_mismatch' then v_bad := v_bad || ' 불일치 거부 사유=' || sqlerrm; end if;
    end;
    -- ⓑ 각각 하나씩도 전부 공격이다 — 거리만, 사유만
    begin
      perform settle_run_tx(b_a, 9.9, 2100, 'completed', null, 9900, 29700, 0, 0, 9800);
      v_bad := v_bad || ' 거리만 부풀린 정산:통과';
    exception when others then
      if sqlerrm <> 'frozen_measurement_mismatch' then v_bad := v_bad || ' 거리 불일치 거부 사유=' || sqlerrm; end if;
    end;
    begin
      perform settle_run_tx(b_a, 3.2, 2100, 'owner_request', null, 9900, 9600, 0, 2700, 4400);
      v_bad := v_bad || ' 사유만 바꾼 정산:통과';
    exception when others then
      if sqlerrm <> 'frozen_measurement_mismatch' then v_bad := v_bad || ' 사유 불일치 거부 사유=' || sqlerrm; end if;
    end;
    -- 거부는 아무것도 남기지 않는다 — 상태도, 원장도, 동결값도
    if (select b.status::text from bookings b where b.id = b_a) <> 'active'
      then v_bad := v_bad || ' 거부됐는데 상태가 움직였다'; end if;
    if exists (select 1 from ledger_items li where li.booking_id = b_a)
      then v_bad := v_bad || ' 거부됐는데 원장이 생겼다'; end if;
    select r.actual_km, r.end_reason::text into v_km, v_txt from runs r where r.booking_id = b_a;
    if v_km <> 3.2 or v_txt <> 'completed'
      then v_bad := v_bad || ' 거부가 동결값을 바꿨다=' || v_km || '/' || v_txt; end if;

    -- ⓒ 양성 대조 + 돈을 움직이지 않는 입력의 처리: 동결된 거리·사유로 부르면 정산되고,
    --    같이 넘어온 duration_sec은 (거부가 아니라) 동결값이 보존된다 — 거부하면 영원히
    --    정산 불가가 되는데 그 숫자는 돈을 한 푼도 움직이지 않기 때문 (마이그레이션 §6-ⓔ).
    begin
      perform settle_run_tx(b_a, 3.2, 60, 'completed', null, 9900, 9600, 0, 0, 3900);
    exception when others then v_bad := v_bad || ' 동결값 그대로인 정산이 거부됨=' || sqlerrm;
    end;
    if (select b.status::text from bookings b where b.id = b_a) <> 'completed'
      then v_bad := v_bad || ' 동결값 정산이 완료되지 않았다'; end if;
    select count(*) into v_n from ledger_items where booking_id = b_a;
    if v_n <> 1 then v_bad := v_bad || ' 원장 행수=' || v_n; end if;
    select r.actual_km, r.duration_sec, r.avg_pace_sec_per_km into v_km, v_n, v_n2
      from runs r where r.booking_id = b_a;
    if v_km <> 3.2 then v_bad := v_bad || ' 정산이 동결 거리를 바꿨다=' || v_km; end if;
    if v_n <> 2100 then v_bad := v_bad || ' 정산이 동결 시간을 덮어썼다=' || v_n; end if;
    if v_n2 <> round(2100 / 3.2) then v_bad := v_bad || ' 정산이 동결 페이스를 덮어썼다=' || v_n2; end if;

    if v_bad = ''
      then call _pass('ren','R15 동결 강제 — 씰이 찍힌 뒤에도 settle-run이 부르는 그 경로(settle_run_tx 직접 호출)에서 동결값과 다른 거리·사유는 frozen_measurement_mismatch로 거부되고(상태·원장·동결값 무변화), 동결값 그대로면 정산되며 돈을 안 움직이는 duration은 거부 대신 보존된다');
    else v_msg := v_bad; call _fail('ren','R15 동결 강제', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R15 동결 강제', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R5] the force is an OPS ADJUDICATION — a party can never reach it (0089 §0, Sean's ruling)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- Sean, 2026-08-13, verbatim: "no, the confirmation must happen with both parties and never
  -- just the runner. also handoff." 0083 let a party force 20 minutes after the stop and release
  -- its own money; 0089 removes that path, so what this pin measures is now its ABSENCE — refused
  -- by name, from the phone AND from the server class, because the edge function calling on a
  -- runner's behalf is the same hole one caller-class away.
  -- ⚠ `force_too_early` is not asserted here because IT NO LONGER EXISTS. The grace existed only
  -- to make a party wait, and ops has always bypassed it (0089 §2). The only honest way to pin
  -- the absence of an error is a call that must succeed, which is ⓓ.
  begin
    v_bad := '';
    -- ⓐ a party force is refused BY NAME — as the runner, as the owner…
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      perform force_return_tx(bk, 'runner', '보호자가 문 앞에 없어요',
                              jsonb_build_object('kind','pickup_radius','m',12));
      v_bad := v_bad || ' 러너 강제:통과';
    exception when others then
      if sqlerrm <> 'force_party_forbidden' then v_bad := v_bad || ' 러너 강제 거부 사유=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin
      perform force_return_tx(bk, 'owner', '내가 이미 받았어요', jsonb_build_object('kind','owner_tap'));
      v_bad := v_bad || ' 보호자 강제:통과';
    exception when others then
      if sqlerrm <> 'force_party_forbidden' then v_bad := v_bad || ' 보호자 강제 거부 사유=' || sqlerrm; end if;
    end;
    -- …and from the SERVER class too. An edge function that authenticates the runner and then
    -- dials as service_role is exactly how the removed path would come back; the refusal is
    -- about the SIDE, never about who is holding the phone.
    perform set_config('request.jwt.claim.sub', '', false);
    begin
      perform force_return_tx(bk, 'runner', '엣지가 러너 대신 부른다', jsonb_build_object('kind','ops'));
      v_bad := v_bad || ' 서버가 러너 대신 강제:통과';
    exception when others then
      if sqlerrm <> 'force_party_forbidden' then v_bad := v_bad || ' 서버 대리 강제 거부 사유=' || sqlerrm; end if;
    end;

    -- ⓑ the ops path keeps its own two requirements — an adjudication with no evidence is an
    --    assertion wearing a uniform, and one with no reason is unreadable in a dispute
    begin
      perform force_return_tx(bk, 'ops', '이유만 있음', null);
      v_bad := v_bad || ' 증거 없는 강제:통과';
    exception when others then
      if sqlerrm <> 'evidence_required' then v_bad := v_bad || ' 증거 거부 사유=' || sqlerrm; end if;
    end;
    begin
      perform force_return_tx(bk, 'ops', '', jsonb_build_object('kind','ops_review'));
      v_bad := v_bad || ' 사유 없는 강제:통과';
    exception when others then
      if sqlerrm <> 'reason_required' then v_bad := v_bad || ' 사유 거부=' || sqlerrm; end if;
    end;
    -- ⓒ a phone claiming to be ops is still not ops (0083's gate, unchanged)
    perform set_config('request.jwt.claim.sub', rz::text, false);
    begin
      perform force_return_tx(bk, 'ops', '내가 운영이다', jsonb_build_object('kind','ops'));
      v_bad := v_bad || ' 폰이 ops를 자칭:통과';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' ops 자칭 거부 사유=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    if (select b.return_forced_by from bookings b where b.id = bk) is not null
      then v_bad := v_bad || ' 거부된 시도가 강제를 기록했다'; end if;
    if (select b.settlement_ready_at from bookings b where b.id = bk) is not null
      then v_bad := v_bad || ' 거부된 시도가 씰을 찍었다'; end if;
    if (select b.status::text from bookings b where b.id = bk) <> 'active'
      then v_bad := v_bad || ' 거부된 시도가 정산했다'; end if;

    -- ⓓ THE GRACE IS GONE. 0083 made a party wait 20 minutes before forcing; with nobody left to
    --    make wait, an ops force seconds after the stop must simply work — and it must record
    --    return_eligible_at = the stop itself rather than inventing a waiting period that no
    --    longer exists for anyone (0089 §6).
    b_a := t_ren_live(oz, dg, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(b_a, 4.2, 1900, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    begin
      v_js := force_return_tx(b_a, 'ops', '정지 직후 운영 판정',
                              jsonb_build_object('kind','ops_review'), t_ren_quote(4.2));
      if not coalesce((v_js->>'forced')::boolean, false)
        then v_bad := v_bad || ' 정지 직후 ops 강제가 기록되지 않았다'; end if;
    exception when others then v_bad := v_bad || ' 정지 직후 ops 강제 거부=' || sqlerrm;
    end;
    -- [0089, review fix] return_eligible_at must be NULL: with the party path gone there is no
    -- waiting period for anyone, so writing it would always equal run_ended_at — a cache of a
    -- derivable value, which 0083 §1 forbids of this schema. NULL is what makes "no grace exists"
    -- readable in the data rather than inferable from a rule.
    select b.return_eligible_at, b.run_ended_at into v_ts, v_ts2 from bookings b where b.id = b_a;
    if v_ts is not null
      then v_bad := v_bad || ' 자격 시각이 기록됐다 (파생값 캐시 — 0083 §1 금지)'; end if;
    if v_ts2 is null then v_bad := v_bad || ' 정지 시각 미기록'; end if;
    if (select b.status::text from bookings b where b.id = b_a) <> 'completed'
      then v_bad := v_bad || ' 정지 직후 ops 강제가 정산하지 않았다'; end if;

    if v_bad = ''
      then call _pass('ren','R5 강제는 운영 판정이다 — 러너·보호자의 강제는 폰에서도 서버 대리 호출에서도 force_party_forbidden(Sean: "확인은 양측이 함께, 러너 혼자서는 절대"), ops 경로는 증거·사유가 없으면 거부, 폰이 자칭한 ops는 not_party, 거부는 강제도 씰도 남기지 않는다 — 그리고 유예는 사라졌다: 정지 직후 ops 강제가 성사되고 자격 시각은 기록되지 않는다(유예가 없으니 파생 캐시를 두지 않는다)');
    else v_msg := v_bad; call _fail('ren','R5 강제는 운영 판정', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R5 강제는 운영 판정', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R6] the ops force RECORDS an adjudication — and CONFIRMS NOTHING (0089 §2)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- 🔴 THE PIN THAT STOPS 0083's INFERENCE COMING BACK. 0083 wrote the forcing side's own
  -- confirmation stamp (`runner_confirmed_return_at = case when p_side = 'runner' then …`) and
  -- called it "implied by the act". Sean's ruling denies exactly that inference: an adjudication
  -- RESOLVES a return, it does not CONFIRM one. So the fixture here is a booking on which nobody
  -- has stamped anything, and after the force BOTH stamps must still be NULL while
  -- settlement_ready_at exists — the shape a dispute reads as "nobody confirmed, ops resolved",
  -- which a design that stamps a side cannot express at all.
  -- (`bk`, which R3 already runner-stamped, would have made that assertion unreadable; the fresh
  -- booking is the whole reason this pin no longer reuses it.)
  begin
    v_bad := '';
    b_a := t_ren_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b_a, 3.2, 2100, 'completed', null, null);
    -- run as the SERVER class (no auth.uid()) — ops is a server-side override that a phone cannot
    -- claim (R5 ⓒ), and it is the only caller allowed to carry a price.
    perform set_config('request.jwt.claim.sub', '', false);
    v_js := force_return_tx(b_a, 'ops', '보호자 연락 두절 — 운영이 인계를 판정',
                            jsonb_build_object('kind','ops_review','m',12,'src','custody'),
                            t_ren_quote(3.2));

    if not coalesce((v_js->>'forced')::boolean, false) then v_bad := v_bad || ' forced=false'; end if;
    if coalesce(v_js->>'forced_by','') <> 'ops' then v_bad := v_bad || ' 응답 행위자=' || coalesce(v_js->>'forced_by','∅'); end if;
    if not coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 강제인데 정산 안 됨'; end if;
    if (select b.status::text from bookings b where b.id = b_a) <> 'completed'
      then v_bad := v_bad || ' 강제 후에도 completed 아님'; end if;
    select b.return_forced_by, b.return_forced_at, b.return_eligible_at, b.return_force_reason
      into v_txt, v_ts, v_ts2, v_msg from bookings b where b.id = b_a;
    if v_txt is distinct from 'ops' then v_bad := v_bad || ' 행위자=' || coalesce(v_txt,'∅'); end if;
    if v_ts is null then v_bad := v_bad || ' 강제 시각 미기록'; end if;
    if v_ts2 is not null then v_bad := v_bad || ' 자격 시각이 기록됐다 (파생값 캐시)'; end if;
    if coalesce(v_msg,'') = '' then v_bad := v_bad || ' 사유 미기록'; end if;
    if (select b.return_force_evidence->>'kind' from bookings b where b.id = b_a) is distinct from 'ops_review'
      then v_bad := v_bad || ' 증거 미기록'; end if;

    -- 🔴 THE RULING ITSELF: the force wrote NEITHER party's confirmation.
    if (select b.runner_confirmed_return_at from bookings b where b.id = b_a) is not null
      then v_bad := v_bad || ' 강제가 러너 확인 스탬프를 찍었다 (0083의 "행위에 내포됨" 부활)'; end if;
    if (select b.owner_confirmed_return_at from bookings b where b.id = b_a) is not null
      then v_bad := v_bad || ' 강제가 보호자 확인 스탬프를 찍었다 (0083의 "행위에 내포됨" 부활)'; end if;
    -- …and the seal it DID write is what released the money, so the two facts are distinguishable
    if (select b.settlement_ready_at from bookings b where b.id = b_a) is null
      then v_bad := v_bad || ' 강제가 씰을 찍지 않았다'; end if;

    -- the settlement itself used the FROZEN numbers, not the caller's
    if (select li.base from ledger_items li where li.booking_id = b_a) <> 9900
      then v_bad := v_bad || ' 원장 base가 동결 견적과 다르다'; end if;
    if (select r.actual_km from runs r where r.booking_id = b_a) <> 3.2
      then v_bad := v_bad || ' 정산이 동결 거리를 바꿨다'; end if;
    if (select r.settled_at from runs r where r.booking_id = b_a) is null
      then v_bad := v_bad || ' settled_at 미기록'; end if;
    -- and the force is IMMUTABLE — the first resolution is the one that stands
    v_js := force_return_tx(b_a, 'ops', '내가 다시 쓴다', jsonb_build_object('kind','ops_rewrite'));
    select b.return_force_reason into v_msg from bookings b where b.id = b_a;
    if v_msg <> '보호자 연락 두절 — 운영이 인계를 판정'
      then v_bad := v_bad || ' 두 번째 강제가 첫 기록을 덮어썼다=' || coalesce(v_msg,'∅'); end if;
    -- …and the party refusal comes BEFORE the completed early-return: a runner cannot even reach
    -- a settled row's idempotent success by claiming a side.
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      perform force_return_tx(b_a, 'runner', '정산된 예약에 편승', jsonb_build_object('kind','ops'));
      v_bad := v_bad || ' 정산 뒤 러너 강제:통과';
    exception when others then
      if sqlerrm <> 'force_party_forbidden' then v_bad := v_bad || ' 정산 뒤 러너 강제 거부 사유=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    select count(*) into v_n from ledger_items where booking_id = b_a;
    if v_n <> 1 then v_bad := v_bad || ' 원장 행수=' || v_n; end if;

    if v_bad = ''
      then call _pass('ren','R6 강제 기록 — ops 강제는 행위자=ops·강제 시각·사유·증거를 남기되 자격 시각은 남기지 않고(파생 캐시 금지) 같은 트랜잭션에서 동결값으로 정산하되, 🔴 어느 쪽의 확인 스탬프도 찍지 않는다(씰만 찍힌다 — "아무도 확인 안 함, 운영이 판정함"이 읽히는 모양), 두 번째 강제는 첫 결론을 덮지 않고, 정산된 뒤에도 당사자 강제는 force_party_forbidden (원장 1행)');
    else v_msg := v_bad; call _fail('ren','R6 강제 기록', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R6 강제 기록', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R17] a force that has not settled must never SAY it settled — and must still be able to
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- R6's second-force probe runs against a booking that is ALREADY `completed`, so it lands on
  -- the completed early-return and never reaches the re-entry branch. That branch is the one a
  -- real ops resolution uses, because sealing and pricing are two steps: an ops force with no
  -- price (seals, settles nothing) → an ops retry WITH the price, once the payout has been
  -- computed from the frozen measurement. It used to answer `settled: true` to a booking it had
  -- left `active` — a false claim AND a dead end, since the retry it lied to was the call that
  -- would have paid the runner.
  -- ⚠ Both legs are `ops` since 0089: the party leg does not exist any more (R5 owns that), and
  -- no aging is needed either — the 20-minute grace retired with it.
  begin
    v_bad := '';
    b_a := t_ren_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b_a, 4.0, 1800, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);

    -- ① ops seals. Recorded — and NOTHING settled, which it must say out loud.
    v_js := force_return_tx(b_a, 'ops', '보호자 연락 두절 — 운영 판정',
                            jsonb_build_object('kind','ops_review','m',9));
    if not coalesce((v_js->>'forced')::boolean, false) then v_bad := v_bad || ' 강제가 기록되지 않았다'; end if;
    if coalesce((v_js->>'settled')::boolean, false)
      then v_bad := v_bad || ' 정산 없이 settled=true'; end if;
    if (select b.settlement_ready_at from bookings b where b.id = b_a) is null
      then v_bad := v_bad || ' 강제가 씰을 찍지 않았다'; end if;
    if (select b.status::text from bookings b where b.id = b_a) <> 'active'
      then v_bad := v_bad || ' 가격 없이 정산됐다'; end if;
    if exists (select 1 from ledger_items li where li.booking_id = b_a)
      then v_bad := v_bad || ' 가격 없이 원장이 생겼다'; end if;
    -- …and the unsettled half of the seal is just as stamp-free as the settled one (R6's law,
    -- re-measured on the branch where the force STOPS instead of settling)
    if (select b.runner_confirmed_return_at from bookings b where b.id = b_a) is not null
       or (select b.owner_confirmed_return_at from bookings b where b.id = b_a) is not null
      then v_bad := v_bad || ' 가격 없는 강제가 확인 스탬프를 찍었다'; end if;

    -- ② the ops retry, WITH the price — the branch that used to return settled:true and stop
    v_js := force_return_tx(b_a, 'ops', '서버 재시도', jsonb_build_object('kind','retry'),
                            t_ren_quote(4.0));
    if coalesce((v_js->>'forced')::boolean, true) then v_bad := v_bad || ' 재진입이 강제를 다시 기록했다'; end if;
    if not coalesce((v_js->>'settled')::boolean, false)
      then v_bad := v_bad || ' 가격을 들고 재진입했는데 정산되지 않았다 (러너가 영원히 미지급)'; end if;
    if coalesce((v_js->>'unchanged')::boolean, true) then v_bad := v_bad || ' 방금 정산해놓고 unchanged=true'; end if;
    if (select b.status::text from bookings b where b.id = b_a) <> 'completed'
      then v_bad := v_bad || ' 재진입 정산 뒤에도 completed 아님'; end if;
    select count(*) into v_n from ledger_items where booking_id = b_a;
    if v_n <> 1 then v_bad := v_bad || ' 원장 행수=' || v_n; end if;
    -- 첫 결론은 그대로다 (기록 불변 — R6의 법이 재진입에서도 유지된다)
    select b.return_forced_by, b.return_force_reason into v_txt, v_msg from bookings b where b.id = b_a;
    if v_txt <> 'ops' or v_msg <> '보호자 연락 두절 — 운영 판정'
      then v_bad := v_bad || ' 재진입이 첫 강제 기록을 덮었다=' || coalesce(v_txt,'∅') || '/' || coalesce(v_msg,'∅'); end if;
    -- 정산이 일어난 뒤에도 확인 스탬프는 여전히 양쪽 다 비어 있다
    if (select b.runner_confirmed_return_at from bookings b where b.id = b_a) is not null
       or (select b.owner_confirmed_return_at from bookings b where b.id = b_a) is not null
      then v_bad := v_bad || ' 재진입 정산이 확인 스탬프를 찍었다'; end if;
    -- ③ …그리고 이제야 settled=true·unchanged=true가 참이다 (completed 조기 반환)
    v_js := force_return_tx(b_a, 'ops', '또 재시도', jsonb_build_object('kind','retry'), t_ren_quote(4.0));
    if not coalesce((v_js->>'settled')::boolean, false) or not coalesce((v_js->>'unchanged')::boolean, false)
      then v_bad := v_bad || ' 정산 뒤 재호출 응답=' || coalesce(v_js::text,'∅'); end if;
    select count(*) into v_n from ledger_items where booking_id = b_a;
    if v_n <> 1 then v_bad := v_bad || ' 3회차 뒤 원장 행수=' || v_n; end if;

    if v_bad = ''
      then call _pass('ren','R17 강제 재진입 — 가격 없는 ops 강제는 씰만 찍고 settled=false를 정직하게 답하며(확인 스탬프는 양쪽 다 비어 있다), 같은 예약에 가격을 들고 재진입하면 첫 강제 기록은 그대로 둔 채 그때 정산된다(원장 1행·스탬프는 여전히 비어 있다), 정산이 끝난 뒤에야 settled·unchanged가 참이 된다');
    else v_msg := v_bad; call _fail('ren','R17 강제 재진입', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R17 강제 재진입', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R7] the owner's lock screen learns about 귀가 (plan §4d)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The status does not change at the stop, so 0063's status-triggered composer cannot see this
  -- phase at all — which is why it needs a trigger of its own.
  begin
    v_bad := '';
    b_a := t_ren_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', oo::text, false);
    perform owner_la_register(b_a, 'act-ren-1', repeat('ab', 40), 'development');
    perform set_config('request.jwt.claim.sub', '', false);

    select coalesce(max(id), 0) into v_base from net._stub_calls;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b_a, 4.0, 1800, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);

    select count(*) into v_n from net._stub_calls where id > v_base;
    select body into v_body from net._stub_calls where id > v_base order by id desc limit 1;
    if v_n <> 1 then v_bad := v_bad || ' 푸시 수=' || v_n; end if;
    if v_body->'props'->>'phase' is distinct from 'homeward'
      then v_bad := v_bad || ' phase=' || coalesce(v_body->'props'->>'phase','∅'); end if;
    if v_body->'props'->>'km' is distinct from '4.00'
      then v_bad := v_bad || ' 동결 거리=' || coalesce(v_body->'props'->>'km','∅'); end if;
    if v_body->'props'->>'statusLine' is distinct from '집으로 가는 중'
      then v_bad := v_bad || ' 문구=' || coalesce(v_body->'props'->>'statusLine','∅'); end if;
    if coalesce(v_body->'props'->>'targetKm', '') <> '' or coalesce(v_body->'props'->>'pace', '') <> ''
      then v_bad := v_bad || ' 귀가에 목표/페이스 주장이 붙었다'; end if;

    if v_bad = ''
      then call _pass('ren','R7 귀가 배너 — 상태가 안 바뀌는 전이를 전용 트리거가 잡아 phase=homeward를 밀고, 동결 거리를 싣되 목표·페이스 주장은 싣지 않는다');
    else v_msg := v_bad; call _fail('ren','R7 귀가 배너', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R7 귀가 배너', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R8] the two running-only LA consumers are silent during 귀가 (plan §4d, §5)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- ⓐ the trace trigger: a write to a frozen run must not push 러닝 중.
  -- ⓑ the stale sweep: the trace stopped BECAUSE the run ended, so a trace-based staleness claim
  --    is a lie the server would be telling itself 90 seconds into every walk home.
  -- ⓒ …and the honest counterpart: a dead heartbeat still produces a no-signal state.
  begin
    v_bad := '';
    -- ⓐ (b_a is the 귀가 booking from R7, LA-registered)
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    update runs set trace = jsonb_build_array(
      jsonb_build_object('lat', 37.5440, 'lng', 127.0557, 't', floor(extract(epoch from now())) - 300),
      jsonb_build_object('lat', 37.5460, 'lng', 127.0557, 't', floor(extract(epoch from now())) - 260),
      jsonb_build_object('lat', 37.5480, 'lng', 127.0557, 't', floor(extract(epoch from now())) - 220))
    where booking_id = b_a;
    select count(*) into v_n from net._stub_calls where id > v_base;
    if v_n <> 0 then v_bad := v_bad || ' 귀가 중 트레이스 저장이 ' || v_n || '건 푸시했다'; end if;

    -- ⓑ a fresh heartbeat: the sweep says NOTHING, even though the trace is 220s old
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform custody_ping(b_a);
    perform set_config('request.jwt.claim.sub', '', false);
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    perform owner_la_sweep_stale();
    select count(*) into v_n from net._stub_calls where id > v_base;
    if v_n <> 0 then v_bad := v_bad || ' 신선한 하트비트인데 ' || v_n || '건 푸시'; end if;

    -- ⓒ the heartbeat dies: the sweep reports no-signal, in the 귀가 phase, never 'stale'
    update bookings set custody_last_seen_at = now() - interval '4 minutes' where id = b_a;
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    perform owner_la_sweep_stale();
    select count(*) into v_n from net._stub_calls where id > v_base;
    select body into v_body from net._stub_calls where id > v_base order by id desc limit 1;
    if v_n <> 1 then v_bad := v_bad || ' 죽은 하트비트 푸시 수=' || v_n; end if;
    if v_body->'props'->>'phase' is distinct from 'homeward'
      then v_bad := v_bad || ' 죽은 하트비트 phase=' || coalesce(v_body->'props'->>'phase','∅'); end if;
    if v_body->'props'->>'statusLine' is distinct from '4분째 위치 신호가 없어요'
      then v_bad := v_bad || ' 문구=' || coalesce(v_body->'props'->>'statusLine','∅'); end if;
    -- and the same sweep, run again, does not repeat itself in the same minute
    select coalesce(max(id), 0) into v_base from net._stub_calls;
    perform owner_la_sweep_stale();
    select count(*) into v_n from net._stub_calls where id > v_base;
    if v_n <> 0 then v_bad := v_bad || ' 같은 분에 재푸시 ' || v_n || '건'; end if;

    if v_bad = ''
      then call _pass('ren','R8 러닝 전용 소비자 봉인 — 귀가 중 트레이스 저장은 무음, 스테일 스윕은 트레이스가 아니라 custody_last_seen_at을 읽고(신선하면 무음), 하트비트가 죽으면 homeward/무신호를 분당 1회');
    else v_msg := v_bad; call _fail('ren','R8 러닝 전용 소비자 봉인', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R8 러닝 전용 소비자 봉인', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R9] idempotence — a second stop, a second confirm, and the loser of a return
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- plan §3's last sentence: "a concurrent loser returns idempotent success after verifying the
  -- same frozen outcome, not a raw not_active". One connection cannot race itself, so what is
  -- measured here is the SEQUENTIAL form of exactly that path (the loser's read happens after the
  -- winner commits either way — the lock only decides when).
  begin
    v_bad := '';
    b_c := t_ren_live(oz, dg, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    v_js := end_run_tx(b_c, 5.0, 2400, 'completed', null, null);
    v_ts := (v_js->>'run_ended_at')::timestamptz;
    -- a second stop reporting DIFFERENT numbers must change nothing at all
    v_js := end_run_tx(b_c, 9.9, 60, 'runner_personal', null, null);
    if not coalesce((v_js->>'unchanged')::boolean, false) then v_bad := v_bad || ' 2회차 종료 unchanged=false'; end if;
    if (select r.actual_km from runs r where r.booking_id = b_c) <> 5.0
      then v_bad := v_bad || ' 2회차 종료가 동결 거리를 바꿨다'; end if;
    if (select b.run_ended_at from bookings b where b.id = b_c) is distinct from v_ts
      then v_bad := v_bad || ' 2회차 종료가 정지 시각을 옮겼다'; end if;

    -- both stamps → settlement, once
    v_js := confirm_return_tx(b_c, 'runner');
    v_js := confirm_return_tx(b_c, 'runner');                 -- double tap
    if coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 러너 재탭이 정산했다'; end if;
    perform set_config('request.jwt.claim.sub', '', false);   -- the owner's edge call, with a price
    v_js := confirm_return_tx(b_c, 'owner', t_ren_quote(5.0));
    if not coalesce((v_js->>'sealed')::boolean, false) then v_bad := v_bad || ' 두 번째 스탬프가 봉인하지 않았다'; end if;
    if not coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 두 번째 스탬프가 정산하지 않았다'; end if;
    -- the loser: the same call again, on a booking that is now completed
    v_js := confirm_return_tx(b_c, 'owner', t_ren_quote(5.0));
    if not coalesce((v_js->>'settled')::boolean, false) or not coalesce((v_js->>'unchanged')::boolean, false)
      then v_bad := v_bad || ' 패자 응답=' || coalesce(v_js::text,'∅'); end if;
    -- …and the primitive itself answers the loser the same way, after VERIFYING the outcome
    v_js := _settle_sealed_run(b_c, t_ren_quote(5.0));
    if not coalesce((v_js->>'unchanged')::boolean, false)
      then v_bad := v_bad || ' 프리미티브 패자 응답=' || coalesce(v_js::text,'∅'); end if;
    select count(*) into v_n from ledger_items where booking_id = b_c;
    if v_n <> 1 then v_bad := v_bad || ' 원장 행수=' || v_n; end if;
    select count(*) into v_n from miles_ledger where ref_id = b_c and reason = 'run_complete';
    if v_n <> 2 then v_bad := v_bad || ' 마일 행수=' || v_n || ' (러너/보호자 각 1)'; end if;

    if v_bad = ''
      then call _pass('ren','R9 멱등 — 두 번째 종료는 다른 숫자를 들고 와도 unchanged(동결 불변), 같은 쪽 재탭은 정산하지 않고, 이미 정산된 예약의 재호출은 동결 결과를 확인한 뒤 성공을 돌려준다 (원장 1행·마일 2행)');
    else v_msg := v_bad; call _fail('ren','R9 멱등', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R9 멱등', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R10] scenario A — a pre-cutover STOP stays free even when the return lands after it
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- codex #3, the class the plan had not considered: `runs.ended_at` used to mean SETTLEMENT, so
  -- a run that stopped at 09:58 and was settled at 10:08 read as post-cutover and got charged.
  -- This is the pin that keeps 0080's "no retroactive charging" law true from the other side, and
  -- it is also what stops `settle_run_tx` ever refreshing `ended_at` again.
  -- ⚠ money read through the mint, never asserted as a literal.
  begin
    v_bad := '';
    b_a := t_ren_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b_a, 5.0, 2400, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    -- the stop happened two hours ago; charging goes live one hour ago; the dog comes home NOW
    update bookings set run_ended_at = now() - interval '2 hours' where id = b_a;
    update runs set ended_at = now() - interval '2 hours' where booking_id = b_a;
    update ops_flags set payments_live_since = now() - interval '1 hour', updated_at = now();

    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform confirm_return_tx(b_a, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    v_js := confirm_return_tx(b_a, 'owner', t_ren_quote(5.0));

    if not coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 정산되지 않았다'; end if;
    if (select r.ended_at from runs r where r.booking_id = b_a) > now() - interval '1 hour'
      then v_bad := v_bad || ' 정산이 정지 시각을 현재로 끌어왔다 (컷오버 버그 재발)'; end if;
    if (select r.settled_at from runs r where r.booking_id = b_a) is null
      then v_bad := v_bad || ' settled_at 미기록'; end if;
    -- the mint refuses it: the run ended before the moment, so it is free forever
    select count(*) into v_n from mint_settle_charge_intent(b_a, 'completed', 5.0);
    if v_n <> 0 then v_bad := v_bad || ' 컷오버 이전 정지 러닝을 민팅했다'; end if;
    perform sweep_settled_without_payments();
    select count(*) into v_n from payments where booking_id = b_a;
    if v_n <> 0 then v_bad := v_bad || ' 스윕이 컷오버 이전 정지 러닝을 청구했다 (' || v_n || '행)'; end if;

    -- positive control: a run that STOPS after the moment IS charged, on the FROZEN distance —
    -- and the amount is whatever compute_owner_charge says it is, never a literal typed here.
    b_b := t_ren_live(oz, dg, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(b_b, 3.0, 1500, 'completed', null, null);
    perform confirm_return_tx(b_b, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    perform confirm_return_tx(b_b, 'owner', t_ren_quote(3.0));
    perform sweep_settled_without_payments();
    select q.amount into v_amount from compute_owner_charge(b_b, 'completed', 3.0) q;
    select p.amount, p.raw->>'basis_km' into v_n, v_txt from payments p
      where p.booking_id = b_b and (p.raw->>'kind') is not null;
    if v_n is distinct from v_amount
      then v_bad := v_bad || ' 컷오버 이후 청구액이 기준표와 다르다=' || coalesce(v_n::text,'∅')
                          || '/' || coalesce(v_amount::text,'∅'); end if;
    if v_txt::numeric is distinct from 3.0
      then v_bad := v_bad || ' 청구 기준 거리가 동결값이 아니다=' || coalesce(v_txt,'∅'); end if;

    update ops_flags set payments_live_since = null, updated_at = now();
    if v_bad = ''
      then call _pass('ren','R10 시나리오 A — 컷오버 이전에 멈춘 러닝은 귀가·정산이 이후에 일어나도 영구 무료(정산이 ended_at을 덮지 않는다), 이후에 멈춘 러닝만 동결 거리 기준으로 청구된다 (codex #3)');
    else v_msg := v_bad; call _fail('ren','R10 시나리오 A', v_msg); end if;
  exception when others then
    update ops_flags set payments_live_since = null;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R10 시나리오 A', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R11] `runs.settled_at` means MONEY HAPPENED — the anchor scenario B's fix needs
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- codex #3 scenario B: 0080's invariant-#1 sweep mints for "a runs row with an ended_at and no
  -- payment". Once `ended_at` means the STOP (§6), that predicate would charge the owner five
  -- minutes into every 귀가 — for a dog still on the leash. The fix is one predicate in 0080's own
  -- file (`and rn.settled_at is not null`), and it is NOT in this slice: that function belongs to
  -- the charge machine and is being modified by another session in the same wave, so re-creating
  -- it here would silently revert their work while every pin still passed.
  -- ⚠ THIS PIN THEREFORE DOES NOT CLAIM SCENARIO B IS CLOSED. It pins the property the fix rests
  -- on and would notice its loss: `settled_at` is written by settlement and by nothing else, so
  -- an ended-but-unreturned run is distinguishable from a settled one by that column alone.
  -- (The migration's §0f carries the handoff and the "do not flip payments_live_since yet" gate.)
  begin
    v_bad := '';
    b_a := t_ren_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b_a, 4.5, 2100, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);

    -- stopped, not returned: a stop stamp and a stop time, but no money and no ledger
    select r.ended_at, r.settled_at into v_ts, v_ts2 from runs r where r.booking_id = b_a;
    if v_ts is null then v_bad := v_bad || ' 정지 시각 미기록'; end if;
    if v_ts2 is not null then v_bad := v_bad || ' 정지만 했는데 settled_at이 찍혔다'; end if;
    if exists (select 1 from ledger_items li where li.booking_id = b_a)
      then v_bad := v_bad || ' 정지만 했는데 원장이 있다'; end if;
    if (select b.status::text from bookings b where b.id = b_a) <> 'active'
      then v_bad := v_bad || ' 정지가 상태를 움직였다'; end if;

    -- the return completes → settlement, and ONLY now does settled_at exist
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform confirm_return_tx(b_a, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    v_js := confirm_return_tx(b_a, 'owner', t_ren_quote(4.5));
    if not coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 귀가 완료가 정산하지 않았다'; end if;
    select r.ended_at, r.settled_at into v_ts2, v_ts from runs r where r.booking_id = b_a;
    if v_ts is null then v_bad := v_bad || ' 정산 뒤에도 settled_at 없음'; end if;
    if v_ts2 is distinct from (select b.run_ended_at from bookings b where b.id = b_a)
      then v_bad := v_bad || ' 정산이 정지 시각을 옮겼다'; end if;
    -- ⚠ never `>` : now() is transaction-constant inside this do-block, so the stop and the
    -- settlement share one instant here. What must hold is that settlement is never EARLIER than
    -- the stop it settles — the ordering, not a measurable gap the fixture cannot produce.
    if v_ts < v_ts2 then v_bad := v_bad || ' settled_at이 정지 시각보다 앞선다'; end if;

    -- the two timestamps are genuinely two facts: every OTHER settled run in the database carries
    -- both, and no run in the database carries settled_at without ended_at (a settlement with no
    -- stop is the shape 0080's mint reads as post-cutover — 0083 §6's run_stop_not_recorded).
    select count(*) into v_n from runs r where r.settled_at is not null and r.ended_at is null;
    if v_n <> 0 then v_bad := v_bad || ' 정지 없이 정산된 러닝 ' || v_n || '건'; end if;

    if v_bad = ''
      then call _pass('ren','R11 정산 앵커 — settled_at은 정산만 쓴다: 멈추기만 한 러닝은 ended_at만 갖고(원장·정산 시각 없음), 인계가 끝나야 settled_at이 생기며 그때도 정지 시각은 움직이지 않는다 (시나리오 B 수리가 딛고 설 성질 — 마이그레이션 §0f)');
    else v_msg := v_bad; call _fail('ren','R11 정산 앵커', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R11 정산 앵커', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R12] the janitor — nothing strands, and a dead settlement gets re-driven
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ GLOBAL: sweep_run_end_recovery() is a whole-table batch, so both arms are asserted per
  -- booking (100 W7 idiom).
  begin
    v_bad := '';
    -- ⓐ a sealed return whose settlement never happened (the crash class codex #4 names). The
    -- fixture writes the durable fact directly, which is exactly what the process would have
    -- left behind if it died one statement later. ⚠ The sweep REPORTS this rather than settling
    -- it — pricing is end_reason-dependent and lives outside SQL (migration §0g) — so what is
    -- pinned is that the row is still `active` afterwards and that no ledger appeared. Whether
    -- it may later be ESCALATED is R16's question, and the answer there is never.
    b_a := t_ren_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b_a, 4.0, 1800, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    update bookings set runner_confirmed_return_at = now(), owner_confirmed_return_at = now(),
                        settlement_ready_at = now()
     where id = b_a;

    -- ⓑ a 귀가 nobody ever confirmed. `active` is LIVE to the runner-accept guard
    -- (transition-booking/index.ts:58), so leaving it there blocks the runner's future bookings.
    b_b := t_ren_live(oz, dg, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(b_b, 5.0, 2400, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    update bookings set run_ended_at = now() - interval '3 hours' where id = b_b;
    update runs set ended_at = now() - interval '3 hours' where booking_id = b_b;

    -- ⓒ a fresh 귀가 must be left completely alone by both arms
    b_c := t_ren_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b_c, 3.0, 1500, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);

    perform sweep_run_end_recovery();

    -- a sealed-but-unsettled row is reported, not touched: no invented settlement, and no
    -- escalation either — ever, at any age. R16 owns that claim and the reason for it (the
    -- escalated state is a money dead end); what R12 pins here is that the sweep's ⓐ arm writes
    -- no money of its own.
    if (select b.status::text from bookings b where b.id = b_a) <> 'active'
      then v_bad := v_bad || ' 스윕이 값을 지어내 정산했다=' || (select b.status::text from bookings b where b.id = b_a); end if;
    if exists (select 1 from ledger_items li where li.booking_id = b_a)
      then v_bad := v_bad || ' 스윕이 원장을 썼다 (가격은 SQL에 없다)'; end if;
    if (select b.status::text from bookings b where b.id = b_b) <> 'incident_review'
      then v_bad := v_bad || ' 2시간 좌초가 승격되지 않았다=' || (select b.status::text from bookings b where b.id = b_b); end if;
    if exists (select 1 from ledger_items li where li.booking_id = b_b)
      then v_bad := v_bad || ' 승격이 정산까지 해버렸다 (아무도 강아지가 집에 있다고 말하지 않았다)'; end if;
    select count(*) into v_n from notifications where ref_id = b_b and title = '귀가 확인이 필요해요';
    if v_n <> 2 then v_bad := v_bad || ' 좌초 통지=' || v_n || ' (양측 1건씩)'; end if;
    if (select b.status::text from bookings b where b.id = b_c) <> 'active'
      then v_bad := v_bad || ' 갓 끝난 귀가를 건드렸다'; end if;

    -- and re-running the janitor changes nothing (its work is idempotent by construction)
    select count(*) into v_pre from notifications where title = '귀가 확인이 필요해요';
    perform sweep_run_end_recovery();
    select count(*) into v_n from notifications where title = '귀가 확인이 필요해요';
    if v_n <> v_pre then v_bad := v_bad || ' 2회차 스윕이 통지 ' || (v_n - v_pre) || '건 추가'; end if;
    if exists (select 1 from ledger_items li where li.booking_id in (b_a, b_b))
      then v_bad := v_bad || ' 승격된 예약에 원장이 생겼다'; end if;

    if v_bad = ''
      then call _pass('ren','R12 청소부 — 씰만 남은 정산은 값을 지어내지 않고 보고만 하며(원장 없음·승격도 없음), 아무도 인계를 확인하지 않은 채 종료 2시간이 지난 예약만 incident_review로 승격되고(양측 통지·원장 없음), 갓 끝난 귀가는 건드리지 않고, 2회차는 아무것도 더 하지 않는다');
    else v_msg := v_bad; call _fail('ren','R12 청소부', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R12 청소부', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R16] the janitor may never make a settleable booking unsettleable
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- R12 asks whether the escalation HAPPENS and whether a ledger row appears. It never asks the
  -- question that matters afterwards: can money still move? It cannot. `incident_review` is a
  -- money dead end — `settle_run_tx`, `_settle_sealed_run`, `confirm_return_tx` and
  -- `force_return_tx` all require `active`, the transition map allows only
  -- `incident_review → refund_pending` (0066:56), and the one commercial exit that exists
  -- (`club_incident_settle`, 0072) is structurally club-only. So escalating a SEALED row — one
  -- where both sides said the dog is home and only the payout is missing — would make an owner
  -- who did not tap confirm within 2 hours able to leave the runner permanently unpayable.
  -- This pin measures both halves: the sealed row is never escalated and is still settleable
  -- afterwards, and the row that IS escalated is in the state we intend, dead end included.
  begin
    v_bad := '';
    -- ⓐ sealed, unsettled, and OLD — past the stranding deadline and past the seal alarm
    b_a := t_ren_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b_a, 4.0, 1800, 'completed', null, null);
    perform confirm_return_tx(b_a, 'runner');
    perform set_config('request.jwt.claim.sub', oo::text, false);
    perform confirm_return_tx(b_a, 'owner');                 -- 씰만, 가격 없이 (정산은 죽었다)
    perform set_config('request.jwt.claim.sub', '', false);
    update bookings set run_ended_at = now() - interval '9 hours',
                        settlement_ready_at = now() - interval '8 hours' where id = b_a;
    update runs set ended_at = now() - interval '9 hours' where booking_id = b_a;

    -- ⓑ …and a 귀가 nobody ever confirmed, the same age (this one SHOULD escalate)
    b_b := t_ren_live(oz, dg, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(b_b, 5.0, 2400, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    update bookings set run_ended_at = now() - interval '9 hours' where id = b_b;
    update runs set ended_at = now() - interval '9 hours' where booking_id = b_b;

    perform sweep_run_end_recovery();

    -- 씰이 찍힌 행은 나이가 아무리 들어도 승격되지 않는다 — 그 상태여야 아직 지급할 수 있다
    if (select b.status::text from bookings b where b.id = b_a) <> 'active'
      then v_bad := v_bad || ' 씰 행을 승격시켰다(러너 영구 미지급)=' || (select b.status::text from bookings b where b.id = b_a); end if;
    -- 대신 알람이 양측에 1회 — 상태를 옮기지 않는 경보
    select count(*) into v_n from notifications where ref_id = b_a and title = '정산을 확인하고 있어요';
    if v_n <> 2 then v_bad := v_bad || ' 씰 알람 통지=' || v_n || ' (양측 1건씩)'; end if;
    select count(*) into v_n from notifications where ref_id = b_a and title = '귀가 확인이 필요해요';
    if v_n <> 0 then v_bad := v_bad || ' 씰 행에 좌초 통지가 갔다=' || v_n; end if;
    -- 2회차는 알람을 반복하지 않는다 (1회성)
    perform sweep_run_end_recovery();
    select count(*) into v_n from notifications where ref_id = b_a and title = '정산을 확인하고 있어요';
    if v_n <> 2 then v_bad := v_bad || ' 2회차 알람 누적=' || v_n; end if;

    -- 그리고 핵심: 돈이 아직 움직인다. 정산 경로가 돌아오면 러너는 지급된다.
    v_js := null;
    begin
      v_js := _settle_sealed_run(b_a, t_ren_quote(4.0));
    exception when others then v_bad := v_bad || ' 스윕 뒤 정산 불가=' || sqlerrm;
    end;
    if not coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 스윕 뒤 재구동이 정산하지 않았다'; end if;
    if (select b.status::text from bookings b where b.id = b_a) <> 'completed'
      then v_bad := v_bad || ' 재구동 뒤에도 completed 아님'; end if;
    select count(*) into v_n from ledger_items where booking_id = b_a;
    if v_n <> 1 then v_bad := v_bad || ' 재구동 원장 행수=' || v_n; end if;

    -- ⓒ 승격된 행의 상태는 의도한 그대로다 — incident_review, 원장 없음, 그리고 진짜 막다른 길
    if (select b.status::text from bookings b where b.id = b_b) <> 'incident_review'
      then v_bad := v_bad || ' 미확인 좌초가 승격되지 않았다=' || (select b.status::text from bookings b where b.id = b_b); end if;
    if exists (select 1 from ledger_items li where li.booking_id = b_b)
      then v_bad := v_bad || ' 승격이 원장을 썼다'; end if;
    begin
      perform _settle_sealed_run(b_b, t_ren_quote(5.0));
      v_bad := v_bad || ' 승격된 행이 정산됐다';
    exception when others then
      if sqlerrm <> 'not_active' then v_bad := v_bad || ' 승격 행 정산 거부 사유=' || sqlerrm; end if;
    end;
    -- ⓒ [REWRITTEN BY 0096 — this arm asserted the exact behaviour 0096 changes, and it was
    --    RIGHT for the world before 0092 existed.] It used to require that
    --    `confirm_return_tx` on an escalated row raises `not_active`, i.e. that
    --    `incident_review` is a dead end for the CUSTODY stamp as well as for money.
    --    0092's work gate turned that into a trap: the gate blocks a runner until both stamps
    --    land, 0089 removed the party force, so a `not_active` here left the runner with NO
    --    party-reachable exit at all — permanently unable to earn. 0096 admits the stamp and
    --    keeps money out. What this arm now pins is that SPLIT, which is the load-bearing part:
    --    the stamp lands, and the money dead end is completely undisturbed.
    v_ts := (select b.settlement_ready_at from bookings b where b.id = b_b);
    perform set_config('request.jwt.claim.sub', oz::text, false);
    begin
      v_js := confirm_return_tx(b_b, 'owner');
      if not coalesce((v_js->>'stamped')::boolean, false)
        then v_bad := v_bad || ' 승격 행에서 인계 스탬프가 찍히지 않았다 (러너가 영구히 묶인다)'; end if;
      if coalesce((v_js->>'sealed')::boolean, true)
        then v_bad := v_bad || ' 승격 행에서 봉인됐다 (돈이 움직일 수 있다고 말한다)'; end if;
      if not coalesce((v_js->>'case_open')::boolean, false)
        then v_bad := v_bad || ' case_open이 참이 아니다'; end if;
    exception when others then
      v_bad := v_bad || ' 승격 행 인계가 거부됐다=' || sqlerrm;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    if (select b.owner_confirmed_return_at from bookings b where b.id = b_b) is null
      then v_bad := v_bad || ' 보호자 도장이 실제로 남지 않았다'; end if;
    -- 🔴 the money dead end is UNCHANGED — this is what 0096 refuses to cross
    if (select b.settlement_ready_at from bookings b where b.id = b_b) is distinct from v_ts
      then v_bad := v_bad || ' 승격 행에 씰이 찍혔다 (돈의 막다른 길이 뚫렸다)'; end if;
    if exists (select 1 from ledger_items li where li.booking_id = b_b)
      then v_bad := v_bad || ' 승격 행에 원장이 생겼다'; end if;
    -- …그리고 나머지 세 함수의 active 전용 게이트는 그대로다 (위의 _settle_sealed_run 팔이 증명).
    -- 0066:56은 여전히 refund_pending만 허용하므로 상업적 출구는 열리지 않았다 — 0096이 통과시킨
    -- 것은 커스터디 스탬프 하나뿐이고, 그것이 러너를 푸는 데 필요한 전부다.
    if (select b.status::text from bookings b where b.id = b_b) <> 'incident_review'
      then v_bad := v_bad || ' 인계 확인이 승격 행의 상태를 움직였다'; end if;

    if v_bad = ''
      then call _pass('ren','R16 막다른 길 방지 — 씰이 찍힌 미정산 행은 몇 시간이 지나도 승격되지 않고(상태 무이동 알람만 양측 1회·2회차 반복 없음) 스윕 뒤에도 재구동으로 정산되며, 아무도 확인하지 않은 행만 incident_review로 간다. 🔴 [0096] 그 상태에서 정산은 여전히 not_active로 막히지만 커스터디 스탬프는 통과한다 — 씰도 원장도 상태 변화도 없이 (돈의 막다른 길은 보존, 러너만 풀린다)');
    else v_msg := v_bad; call _fail('ren','R16 막다른 길 방지', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R16 막다른 길 방지', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R13] the grant matrix — the freeze is server-only, the doorstep is not
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- `end_run_tx` takes the runner's PAYOUT as an argument. A client that can execute it is a
  -- client that sets its own wage — so this is a money seal, not hygiene.
  -- 🔴 0089 MOVED ONE ROW. `force_return_tx` was in the client-facing group here because a party
  -- could force from their phone; with the party path gone it is an ops adjudication, so it is
  -- service_role-only and `authenticated` must be REFUSED. The grant is the second belt behind
  -- `force_party_forbidden` (R5): even a caller who found a way to name a side never gets to
  -- execute the function at all.
  declare
    fns text[] := array[
      'end_run_tx(uuid,numeric,int,text,text,jsonb)',
      '_settle_sealed_run(uuid,jsonb)',
      'sweep_run_end_recovery()',
      'settle_run_tx(uuid,numeric,int,text,text,int,int,int,int,int)',
      'sweep_settled_without_payments()',
      'force_return_tx(uuid,text,text,jsonb,jsonb)'];
    f text;
  begin
    v_bad := '';
    foreach f in array fns loop
      if to_regprocedure(f) is null then v_bad := v_bad || ' ' || f || ':없음'; continue; end if;
      if has_function_privilege('authenticated', f, 'execute') then v_bad := v_bad || ' ' || f || ':authenticated'; end if;
      if has_function_privilege('anon', f, 'execute') then v_bad := v_bad || ' ' || f || ':anon'; end if;
      if not has_function_privilege('service_role', f, 'execute') then v_bad := v_bad || ' ' || f || ':service_role 불가'; end if;
    end loop;
    -- positive control: the three client-facing RPCs ARE callable (else the pin proves nothing —
    -- and in particular, `force_return_tx` above is not passing because the whole §6 family got
    -- revoked by accident)
    foreach f in array array['confirm_return_tx(uuid,text,jsonb)',
                             'custody_ping(uuid)', 'append_run_event(uuid,jsonb)'] loop
      if not has_function_privilege('authenticated', f, 'execute')
        then v_bad := v_bad || ' ' || f || ':authenticated 불가'; end if;
      if has_function_privilege('anon', f, 'execute') then v_bad := v_bad || ' ' || f || ':anon 가능'; end if;
    end loop;

    if v_bad = ''
      then call _pass('ren','R13 권한 매트릭스 — 동결·정산·스윕에 더해 강제까지 service_role 전용(0089: 강제는 운영 판정이므로 폰은 실행 권한 자체를 갖지 않는다), 인계 확인·하트비트·append만 authenticated (양성 대조 포함)');
    else v_msg := v_bad; call _fail('ren','R13 권한 매트릭스', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('ren','R13 권한 매트릭스', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [R14] the freeze accepts only what settle-run accepts — and clubs are out by predicate
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- THE DEADLOCK RULE (payments session, 2026-08-13): the freeze happens EARLIER than
  -- settle-run's gate, so the set accepted here must be a SUBSET of what settle-run accepts.
  -- `incident` would hand the owner a free run under Sean's G1 ruling and pre-empt a case review;
  -- `owner_forced` would bill the owner the full planned distance on a runner's say-so. Both get
  -- a named 400 from settle-run — so a run frozen with either would be a run that can NEVER
  -- settle: the runner is never paid and the booking never leaves `active`.
  -- No amount is asserted here on purpose: what makes these two dangerous is a pricing ruling
  -- that is still landing, and a fixture that named its number would go red for the wrong reason.
  begin
    v_bad := '';
    b_a := t_ren_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    foreach v_txt in array array['incident', 'owner_forced', 'no_such_reason'] loop
      begin
        perform end_run_tx(b_a, 5.0, 2400, v_txt, null, null);
        v_bad := v_bad || ' ' || v_txt || ':동결 통과';
      exception when others then
        if sqlerrm <> 'end_reason_not_runner_declarable'
          then v_bad := v_bad || ' ' || v_txt || ' 거부 사유=' || sqlerrm; end if;
      end;
    end loop;
    if (select b.run_ended_at from bookings b where b.id = b_a) is not null
      then v_bad := v_bad || ' 거부된 사유가 러닝을 얼렸다'; end if;
    -- the four a runner MAY declare all freeze (else the whitelist is just "refuse everything")
    foreach v_txt in array array['completed', 'dog_condition', 'owner_request', 'runner_personal'] loop
      b_b := t_ren_live(oo, dg, rt, rr);
      begin
        perform end_run_tx(b_b, 5.0, 2400, v_txt,
                           case when v_txt = 'dog_condition' then '뒷다리를 절어요' end, null);
      exception when others then v_bad := v_bad || ' ' || v_txt || ' 동결 실패=' || sqlerrm;
      end;
      if (select r.end_reason::text from runs r where r.booking_id = b_b) is distinct from v_txt
        then v_bad := v_bad || ' ' || v_txt || ' 사유가 동결되지 않았다'; end if;
    end loop;
    -- 컨디션 종료는 메모 없이 얼릴 수 없다 (§8-bis — 조작된 상수가 돈 통제였던 그 자리)
    b_b := t_ren_live(oo, dg, rt, rr);
    begin
      perform end_run_tx(b_b, 5.0, 2400, 'dog_condition', null, null);
      v_bad := v_bad || ' 메모 없는 컨디션 종료:통과';
    exception when others then
      if sqlerrm <> 'condition_note_required' then v_bad := v_bad || ' 메모 거부 사유=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);

    -- clubs: "out of scope" as a predicate, not as a sentence in a plan (plan §7)
    insert into club_test_accounts (profile_id, note) values (rr, 'ren suite')
      on conflict (profile_id) do nothing;
    insert into clubs (name, district, host_profile_id) values ('귀가 클럽', '성수동', rr)
      returning id into v_club;
    insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
      values (v_club, rr, now() + interval '2 days', '귀가 집결지') returning id into v_sess;
    b_c := t_ren_live(oo, dg, rt, rr);
    update bookings set club_session_id = v_sess where id = b_c;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      perform end_run_tx(b_c, 5.0, 2400, 'completed', null, null);
      v_bad := v_bad || ' 클럽 예약 동결:통과';
    exception when others then
      if sqlerrm <> 'club_out_of_scope' then v_bad := v_bad || ' 클럽 동결 거부 사유=' || sqlerrm; end if;
    end;
    begin
      perform confirm_return_tx(b_c, 'runner');
      v_bad := v_bad || ' 클럽 인계 확인:통과';
    exception when others then
      if sqlerrm <> 'club_out_of_scope' then v_bad := v_bad || ' 클럽 인계 거부 사유=' || sqlerrm; end if;
    end;
    -- …and a club settlement is NOT gated by the seal (the club path keeps its own custody model)
    begin
      perform settle_run_tx(b_c, 5.0, 2400, 'completed', null, 9900, 15000, 0, 0, 4980);
    exception when others then v_bad := v_bad || ' 클럽 정산이 귀가 씰에 걸렸다=' || sqlerrm;
    end;
    perform set_config('request.jwt.claim.sub', '', false);

    -- the shipped defaults are back (a mid-suite exception must not leave a switch on)
    if (select f.return_seal_since from ops_flags f where f.id) is not null
      then v_bad := v_bad || ' return_seal_since가 켜진 채 남았다'; end if;
    if (select f.payments_live_since from ops_flags f where f.id) is not null
      then v_bad := v_bad || ' payments_live_since가 켜진 채 남았다'; end if;

    if v_bad = ''
      then call _pass('ren','R14 동결 어휘 + 클럽 범위 — 러너가 선언할 수 있는 네 사유만 얼고(incident·owner_forced는 settle-run이 400으로 거부하므로 얼면 영원히 정산 불가), 컨디션은 메모 필수, 클럽 예약은 동결·인계 확인 자체가 거부되고 클럽 정산은 씰과 무관, 두 스위치는 배포 기본값으로 복귀');
    else v_msg := v_bad; call _fail('ren','R14 동결 어휘 + 클럽 범위', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ren','R14 동결 어휘 + 클럽 범위', v_msg);
  end;
end $$;
