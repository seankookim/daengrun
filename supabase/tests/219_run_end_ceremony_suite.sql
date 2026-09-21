-- ═══ 219 run-end ceremony suite — 0188 pins (⑪ + ⑫ finally have product callers) ═══
--
-- ═══ WHAT THIS SUITE OWNS, AND WHAT IT DELIBERATELY DOES NOT ═════════════════════════════
-- 0083/0092/0096 are pinned by 119/131/132/133. Nothing here re-asserts them. This suite owns
-- exactly what the run-end ceremony slice CHANGED or ARMED:
--   A — the SEQUENCE. `end_run_tx` → work gate → two stamps → settle, driven through the real
--       functions in the real order, because the defect class this slice exists in is a
--       COMPOSITION defect and no single-migration suite can see one (132's own header).
--   B — arm ⓑ's narrowing, pinned in the DIVERGENCE ZONE. The shipped pins on that arm
--       (119 R12/R16, 132 E1/E2, 133) all escalate ZERO-STAMP fixtures, so they sit where the
--       old rule and the new one AGREE and could not see this predicate change at all. A pin
--       whose fixture cannot distinguish two rules is testing the fixture (CLAUDE.md), so B1/B2
--       put a row where they DISAGREE: exactly one return stamp.
--   C — the club wall, from the 1:1 door.
--
-- ⚠ NO PIN HERE ASSERTS A MONEY AMOUNT. Every money claim is presence/absence of a ledger row —
--   the 132 header's rule. Pricing belongs to 137.
--
--   D — the GRANT, because a grant is a door (added after the cold review — see below).
--
-- 🔴 THIS HEADER USED TO CARRY A GAP PARAGRAPH SAYING THE OPPOSITE, AND IT WAS WRONG IN THE WAY
--   THAT COSTS MOST. It read: a party calling `confirm_return_tx` directly cannot bring a price,
--   so a direct second stamp seals without settling — "but the product cannot produce it, every
--   surface goes through `transition-booking`". That sentence is about the app's BUTTONS. The
--   function is in `public` and was granted to `authenticated`, and PostgREST exposes `public`:
--   `api.ts` already proves a client-role RPC to a `public` definer works, because it calls
--   `runner_work_gate` exactly that way. So the door was the API, not the UI — reachability is a
--   fact about the DEPLOYMENT, never about which screens we drew (CLAUDE.md's grant-is-not-a-door
--   law, and this is the same error running in the other direction: a *product* argument used to
--   license a *privilege* conclusion). Found by a cold executing reviewer; closed by 0188 §B's
--   revoke and pinned by `0188-D1`. The paragraph is kept, corrected, rather than deleted: a
--   header that quietly stops claiming something is how the next session inherits the belief.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   0188-A1 ← delete `end_run_tx`'s `run_ended_at` stamp: the work gate never arms       → RED
--   0188-A2 ← 0083 §6-ⓑ: drop the `if v_ready is null then raise 'return_not_sealed'`:
--             a run settles with the dog still out — the bypass the ceremony closes      → RED
--   0188-A3 ← 0083 §6: let `_settle_sealed_run` run without a seal (same conjunct, other
--             side) — A2 and A3 are DIFFERENT propositions: A2 is "the hole reproduces
--             unfixed", A3 is "the ceremony closes it" (the three-proposition law)       → RED
--   0188-B1 ← 0188 arm ⓑ: remove the `runner_confirmed_return_at is not null or …` branch
--             (i.e. restore 0083's unconditional escalation) — a row a party has already
--             confirmed is escalated and its money path dies                             → RED
--   0188-B2 ← the same revert. B2 is a SEPARATE proposition from B1 and is the one that
--             costs money: B1 says "the status did not move", B2 says "the run can still
--             be settled afterwards". A future edit could satisfy B1 and break B2 by
--             moving the row somewhere else that is not `active`                         → RED
--   0188-B3 ← 0092:112-117: delete the `or b.status = 'incident_review'` arm of the work
--             gate. This pin is the EVIDENCE for 0188's claim that escalation frees no
--             runner; without the arm the claim would be false and the narrowing would be
--             trading a real unblock for a money path                                    → RED
--   0188-B4 ← 0188 arm ⓑ: delete the `for update skip locked` re-check — the destructive
--             branch trusts an unlocked snapshot again. ⚠ This is the PRECONDITION pin
--             (CLAUDE.md: mutate what the guard READS, not only what it does): B1/B2
--             attack the branch, B4 attacks the lock that makes the branch's input true   → RED
--   0188-C1 ← `end_run_tx`'s `club_out_of_scope` raise — a club booking ends through the
--             1:1 door and 0168's two-phase stop is bypassed                             → RED
--   0188-D1 ← 0188 §B: restore `grant execute on confirm_return_tx to authenticated` — a
--             phone can be the stamp that seals, with no price and no repair. ⚠ Its
--             POSITIVE arm reddens under the opposite mutation (revoking service_role
--             too), which is the failure that would otherwise look like this pin passing → RED
--
--   ✔ MUTATION-PROVEN — the battery and its control are recorded in this slice's report.
set client_min_messages = warning;

-- ---------- suite-local fixtures ----------
-- A marketplace run that is LIVE (started, not stopped). Sibling of 119's `t_ren_live`, declared
-- here rather than reused so this suite does not break if 119's fixture is re-shaped for its own
-- reasons — a shared fixture is a shared failure mode (119/132 both learned this).
create or replace function t_rec_live(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'active', now() - interval '50 minutes', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into v;
  insert into runs (booking_id, started_at, trace)
  values (v, now() - interval '50 minutes', '[]'::jsonb);
  return v;
end $$;

-- The quote the EDGE computes and hands to `confirm_return_tx`. A fixture, not a rule — this
-- suite does not own pricing (137 does), and 0083 takes the price as an argument precisely so
-- that the basis can depend on `end_reason` without this file knowing about it.
create or replace function t_rec_quote(p_km numeric) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'base', 9900, 'distance_pay', round(p_km * 3000)::int, 'addon_pay', 0,
    'guarantee', 0, 'fee', round((9900 + round(p_km * 3000)) * 0.2)::int)
$$;

do $$
declare
  oo uuid; rr uuid; oz uuid; rz uuid; dg uuid; dz uuid; rt uuid;
  b1 uuid; b2 uuid; b3 uuid; b_club uuid; cs uuid; v_club uuid;
  v_bad text := ''; v_msg text; v_js jsonb; v_n int; v_src text; v_status text;
begin
  oo := t_user('rec_oo', 'owner');  oz := t_user('rec_oz', 'owner');
  rr := t_user('rec_rr', 'runner'); rz := t_user('rec_rz', 'runner');
  dg := t_dog(oo, '봉인견'); dz := t_dog(oz, '좌초견');
  rt := t_route('반환 코스');

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0188-A1] THE SEQUENCE — the stop freezes and ARMS the gate; it does not complete anything
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    b1 := t_rec_live(oo, dg, rt, rr);
    -- before the stop the runner is free: the gate must not be armed by a run merely being live
    -- (0092 §3 is explicit that "currently running" is a DIFFERENT rule with different false
    -- positives, and the accept path's own conflict guard owns that one).
    v_js := runner_work_gate(rr);
    if coalesce((v_js->>'gated')::boolean, true) then v_bad := v_bad || ' 러닝 중인데 게이트가 걸렸다'; end if;

    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_js := end_run_tx(b1, 5.0, 1800, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    if coalesce((v_js->>'unchanged')::boolean, true) then v_bad := v_bad || ' 첫 종료가 unchanged'; end if;
    -- the status STAYS active — "ended, not yet returned" is a phase, not a state (0083 §1)
    select b.status::text into v_status from bookings b where b.id = b1;
    if v_status <> 'active' then v_bad := v_bad || ' 종료가 상태를 옮겼다=' || v_status; end if;
    if (select b.run_ended_at from bookings b where b.id = b1) is null
      then v_bad := v_bad || ' run_ended_at이 안 찍혔다'; end if;
    -- …and the measurement is frozen on the RUN row, which is what settlement re-reads
    if (select r.actual_km from runs r where r.booking_id = b1) is distinct from 5.00
      then v_bad := v_bad || ' 실측이 얼지 않았다'; end if;
    if (select r.ended_at from runs r where r.booking_id = b1) is null
      then v_bad := v_bad || ' runs.ended_at(서비스 정지)이 없다'; end if;
    -- THE GATE IS NOW ARMED, and it names the exit. This is the R1c strip's entire input.
    v_js := runner_work_gate(rr);
    if not coalesce((v_js->>'gated')::boolean, false) then v_bad := v_bad || ' 종료 뒤에도 게이트가 안 걸렸다'; end if;
    if (v_js->>'booking_id') is distinct from b1::text then v_bad := v_bad || ' 게이트가 다른 예약을 지목'; end if;
    if (v_js->>'waiting_on') is distinct from 'both' then v_bad := v_bad || ' waiting_on=' || coalesce(v_js->>'waiting_on','(null)'); end if;
    if (v_js->>'exit') is distinct from 'both_confirm_return' then v_bad := v_bad || ' exit 이름이 다르다'; end if;
    -- a second stop is the same stop, never an error (the retry path the client depends on)
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_js := end_run_tx(b1, 9.9, 9999, 'owner_request', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    if not coalesce((v_js->>'unchanged')::boolean, false) then v_bad := v_bad || ' 재종료가 멱등이 아니다'; end if;
    if (select r.actual_km from runs r where r.booking_id = b1) is distinct from 5.00
      then v_bad := v_bad || ' 재종료가 얼린 숫자를 덮어썼다 (9.9km로 재정산 가능)'; end if;

    if v_bad = ''
      then call _pass('rec','0188-A1 정지는 얼리고 게이트를 무장시킨다 — 러닝 중엔 게이트 없음, end_run_tx 뒤 상태는 active 그대로·run_ended_at·실측/서비스정지 동결, 게이트가 이 예약을 waiting_on=both/both_confirm_return로 지목, 재정지는 멱등이며 얼린 숫자를 못 덮는다');
    else v_msg := v_bad; call _fail('rec','0188-A1 정지는 얼리고 게이트를 무장시킨다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('rec','0188-A1 정지는 얼리고 게이트를 무장시킨다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0188-A2] THE HOLE REPRODUCES — a stopped run refuses to settle before the dog is home
  -- ⚠ A2 and A3 are the three-proposition law's first two arms and must not be merged: this one
  --   says the BYPASS IS REAL AND CLOSED at the stop, A3 says THE CEREMONY OPENS IT. A single
  --   pin would prove only that something notices.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- b1 is stopped and unsealed, from A1.
    begin
      perform settle_run_tx(b1, 5.0, 1800, 'completed', null, 9900, 15000, 0, 0, 4980);
      v_bad := v_bad || ' 봉인 없이 정산됐다 (강아지가 아직 밖에 있다)';
    exception when others then
      if sqlerrm <> 'return_not_sealed' then v_bad := v_bad || ' 거절 이름=' || sqlerrm; end if;
    end;
    -- and the one-stamp state is still refused — a half-ceremony is not a ceremony
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_js := confirm_return_tx(b1, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    if not coalesce((v_js->>'stamped')::boolean, false) then v_bad := v_bad || ' 러너 스탬프 거부'; end if;
    if coalesce((v_js->>'sealed')::boolean, true) then v_bad := v_bad || ' 한쪽 스탬프가 봉인했다'; end if;
    if (select b.settlement_ready_at from bookings b where b.id = b1) is not null
      then v_bad := v_bad || ' 한쪽 스탬프가 settlement_ready_at을 찍었다'; end if;
    begin
      perform settle_run_tx(b1, 5.0, 1800, 'completed', null, 9900, 15000, 0, 0, 4980);
      v_bad := v_bad || ' 한쪽 스탬프만으로 정산됐다';
    exception when others then
      if sqlerrm <> 'return_not_sealed' then v_bad := v_bad || ' 한쪽 거절 이름=' || sqlerrm; end if;
    end;
    if exists (select 1 from ledger_items li where li.booking_id = b1)
      then v_bad := v_bad || ' 봉인 전에 원장이 생겼다'; end if;
    -- the gate now names the OWNER, not the runner — "확인해주세요" to someone who already
    -- confirmed is a lie about their own action (0092 §6), and this is the field that prevents it
    v_js := runner_work_gate(rr);
    if (v_js->>'waiting_on') is distinct from 'owner' then v_bad := v_bad || ' 러너 스탬프 뒤 waiting_on=' || coalesce(v_js->>'waiting_on','(null)'); end if;
    if (v_js->>'exit') is distinct from 'owner_confirm_return' then v_bad := v_bad || ' 러너 스탬프 뒤 exit가 다르다'; end if;

    if v_bad = ''
      then call _pass('rec','0188-A2 봉인 전 정산은 막힌다 — 종료만 한 행도, 한쪽 스탬프만 있는 행도 return_not_sealed, 씰도 원장도 없음; 러너가 찍으면 게이트는 보호자를 지목한다(이미 찍은 쪽에 확인하라고 말하지 않는다)');
    else v_msg := v_bad; call _fail('rec','0188-A2 봉인 전 정산은 막힌다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('rec','0188-A2 봉인 전 정산은 막힌다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0188-A3] THE SECOND STAMP SETTLES — in ONE transaction, exactly once, and it frees the gate
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- The SERVER-class call: no `auth.uid()`, and a price. This is what the edge does, and it is
    -- the whole answer to "who triggers settle" — the stamp and the settlement are one statement,
    -- so a client that dies after its tap cannot strand anything.
    v_js := confirm_return_tx(b1, 'owner', t_rec_quote(5.0));
    if not coalesce((v_js->>'stamped')::boolean, false) then v_bad := v_bad || ' 보호자 스탬프 거부'; end if;
    if not coalesce((v_js->>'sealed')::boolean, false) then v_bad := v_bad || ' 두 번째 스탬프가 봉인하지 않았다'; end if;
    if not coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 두 번째 스탬프가 정산하지 않았다'; end if;
    if (select b.status::text from bookings b where b.id = b1) <> 'completed'
      then v_bad := v_bad || ' 정산 뒤 상태가 completed가 아니다'; end if;
    if (select r.settled_at from runs r where r.booking_id = b1) is null
      then v_bad := v_bad || ' runs.settled_at이 없다 (돈이 움직인 시각)'; end if;
    select count(*) into v_n from ledger_items li where li.booking_id = b1;
    if v_n <> 1 then v_bad := v_bad || ' 원장 행 수=' || v_n || ' (정확히 1)'; end if;
    -- EXACTLY ONCE: a re-tap on a settled booking is "done", never a second ledger row
    v_js := confirm_return_tx(b1, 'owner', t_rec_quote(5.0));
    if not coalesce((v_js->>'unchanged')::boolean, false) then v_bad := v_bad || ' 정산 뒤 재탭이 unchanged가 아니다'; end if;
    select count(*) into v_n from ledger_items li where li.booking_id = b1;
    if v_n <> 1 then v_bad := v_bad || ' 재탭 뒤 원장 행 수=' || v_n; end if;
    -- …and the runner is free. This is the pin that measures what a RUNNER experiences, which is
    -- the only thing ⑫'s ruling is actually about.
    v_js := runner_work_gate(rr);
    if coalesce((v_js->>'gated')::boolean, true) then v_bad := v_bad || ' 양측 확인 뒤에도 게이트가 남았다'; end if;

    if v_bad = ''
      then call _pass('rec','0188-A3 두 번째 스탬프가 같은 트랜잭션에서 봉인·정산한다 — completed·settled_at·원장 1행, 재탭은 unchanged로 원장을 늘리지 않고, 러너의 작업 게이트가 풀린다');
    else v_msg := v_bad; call _fail('rec','0188-A3 두 번째 스탬프가 봉인·정산한다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('rec','0188-A3 두 번째 스탬프가 봉인·정산한다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0188-B1] THE DIVERGENCE ZONE — one stamp present, past the deadline: NOT escalated
  -- 🔴 This fixture is the entire point. 119 R12/R16, 132 E1/E2 and 133 all age a ZERO-stamp row,
  --    where 0083's rule and 0188's rule AGREE — so every one of them stays green under this
  --    change for a true reason and none of them can see it. A predicate change is only visible
  --    from a fixture inside the set where the two predicates disagree (CLAUDE.md).
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    b2 := t_rec_live(oz, dz, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(b2, 4.0, 1500, 'completed', null, null);
    -- the runner stamps — which is what R6a makes happen seconds after the stop
    perform confirm_return_tx(b2, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    -- age it well past STRAND_AFTER (the owner is at work; two hours is not long)
    update bookings set run_ended_at = now() - interval '5 hours' where id = b2;
    update runs set ended_at = now() - interval '5 hours' where booking_id = b2;

    -- CONTROL: the fixture really is in the zone the two rules disagree about
    if (select b.runner_confirmed_return_at from bookings b where b.id = b2) is null
      then v_bad := v_bad || ' 픽스처에 스탬프가 없다 (분기 구역이 아니다)'; end if;
    if (select b.settlement_ready_at from bookings b where b.id = b2) is not null
      then v_bad := v_bad || ' 픽스처가 이미 봉인됐다 (팔 ⓑ의 대상이 아니다)'; end if;

    perform sweep_run_end_recovery();

    if (select b.status::text from bookings b where b.id = b2) <> 'active'
      then v_bad := v_bad || ' 한쪽이 확인한 행이 승격됐다=' || (select b.status::text from bookings b where b.id = b2); end if;
    -- both parties told, once each, with the RIGHT sentence for each side
    select count(*) into v_n from notifications where ref_id = b2 and title = '반환 확인이 멈춰 있어요';
    if v_n <> 2 then v_bad := v_bad || ' 정체 통지=' || v_n || ' (양측 1건씩)'; end if;
    if not exists (select 1 from notifications where ref_id = b2 and profile_id = oz
                   and body like '%앱에서 인계를 확인해주세요%')
      then v_bad := v_bad || ' 안 찍은 쪽에 확인 요청 문장이 안 갔다'; end if;
    if not exists (select 1 from notifications where ref_id = b2 and profile_id = rz
                   and body like '%상대방 확인을 기다리고%')
      then v_bad := v_bad || ' 이미 찍은 쪽에 대기 문장이 안 갔다 (자기 행동에 대한 거짓말)'; end if;
    if exists (select 1 from notifications where ref_id = b2 and profile_id = rz
               and body like '%확인해주세요%')
      then v_bad := v_bad || ' 이미 찍은 러너에게 확인하라고 했다'; end if;
    -- one-shot: a second tick adds nothing
    perform sweep_run_end_recovery();
    select count(*) into v_n from notifications where ref_id = b2 and title = '반환 확인이 멈춰 있어요';
    if v_n <> 2 then v_bad := v_bad || ' 2회차가 통지를 추가했다=' || v_n; end if;
    if (select b.status::text from bookings b where b.id = b2) <> 'active'
      then v_bad := v_bad || ' 2회차가 승격했다'; end if;

    if v_bad = ''
      then call _pass('rec','0188-B1 한쪽이 "개가 집에 왔다"고 말한 좌초는 승격되지 않는다 — 상태 active 유지, 양측에 1회씩 알리되 이미 찍은 쪽에는 확인하라고 말하지 않으며, 2회차 스윕은 아무것도 더 하지 않는다');
    else v_msg := v_bad; call _fail('rec','0188-B1 한쪽이 확인한 좌초는 승격되지 않는다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('rec','0188-B1 한쪽이 확인한 좌초는 승격되지 않는다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0188-B2] …AND THE MONEY PATH SURVIVES IT. THIS IS THE PIN THAT COSTS SOMETHING.
  -- 🔴 A SEPARATE PROPOSITION from B1, deliberately. B1 asserts the status did not move to
  --    `incident_review`; B2 asserts the run can still be SETTLED afterwards. A future edit could
  --    satisfy B1 and break B2 by parking the row in some other non-`active` state, and B1 would
  --    stay green while a runner who walked a dog is never paid.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- the owner finally taps, that evening — hours past the old deadline
    v_js := confirm_return_tx(b2, 'owner', t_rec_quote(4.0));
    if not coalesce((v_js->>'sealed')::boolean, false) then v_bad := v_bad || ' 늦은 두 번째 스탬프가 봉인하지 않았다'; end if;
    if not coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 늦은 두 번째 스탬프가 정산하지 않았다'; end if;
    if (select b.status::text from bookings b where b.id = b2) <> 'completed'
      then v_bad := v_bad || ' 늦은 확인 뒤 completed가 아니다'; end if;
    select count(*) into v_n from ledger_items li where li.booking_id = b2;
    if v_n <> 1 then v_bad := v_bad || ' 늦은 확인 뒤 원장 행 수=' || v_n; end if;
    v_js := runner_work_gate(rz);
    if coalesce((v_js->>'gated')::boolean, true) then v_bad := v_bad || ' 늦은 확인 뒤에도 게이트가 남았다'; end if;

    if v_bad = ''
      then call _pass('rec','0188-B2 늦게 온 두 번째 확인도 정산된다 — 마감 다섯 시간 뒤 보호자가 찍어도 봉인·정산·completed·원장 1행이 되고 러너가 풀린다 (0083 팔 ⓑ의 승격은 이 경로를 영구히 없앴다: incident_review는 0066:56로 refund_pending 외에 출구가 없고 _settle_sealed_run은 active 전용)');
    else v_msg := v_bad; call _fail('rec','0188-B2 늦게 온 두 번째 확인도 정산된다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('rec','0188-B2 늦게 온 두 번째 확인도 정산된다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0188-B3] THE EVIDENCE FOR THE NARROWING — escalation frees NOBODY
  -- 0188's header claims the escalation buys nothing it was bought for. That is a claim about
  -- 0092, so it is pinned against 0092 rather than asserted in prose: a runner whose booking the
  -- REAL sweep escalated is still gated, because the gate's second arm reads the status too.
  -- Without this pin the narrowing would be trading a real unblock for a money path.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    b3 := t_rec_live(oz, dz, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(b3, 3.0, 1200, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    -- ZERO stamps — the agreement zone, where 0083's rule and 0188's rule say the same thing
    update bookings set run_ended_at = now() - interval '5 hours' where id = b3;
    update runs set ended_at = now() - interval '5 hours' where booking_id = b3;
    perform sweep_run_end_recovery();
    if (select b.status::text from bookings b where b.id = b3) <> 'incident_review'
      then v_bad := v_bad || ' 아무도 확인 안 한 행이 승격되지 않았다=' || (select b.status::text from bookings b where b.id = b3); end if;
    -- THE POINT: the escalation did not free the runner.
    v_js := runner_work_gate(rz);
    if not coalesce((v_js->>'gated')::boolean, false)
      then v_bad := v_bad || ' 승격이 러너를 풀어줬다 (0188의 전제가 거짓이 된다 — 좁히기를 재검토할 것)'; end if;
    if (v_js->>'booking_id') is distinct from b3::text then v_bad := v_bad || ' 게이트가 승격된 예약을 안 지목'; end if;
    if (v_js->>'status') is distinct from 'incident_review' then v_bad := v_bad || ' 게이트가 상태를 잘못 보고'; end if;

    if v_bad = ''
      then call _pass('rec','0188-B3 승격은 아무도 풀어주지 않는다 — 실제 스윕이 만든 incident_review 행에서도 0092의 게이트 둘째 팔이 러너를 그대로 잡고 있다 (0083이 승격의 이유로 든 문장이 0092 이후 거짓이라는 증거)');
    else v_msg := v_bad; call _fail('rec','0188-B3 승격은 아무도 풀어주지 않는다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('rec','0188-B3 승격은 아무도 풀어주지 않는다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0188-B4] THE PRECONDITION — the branch is only as good as the lock under it
  -- ⚠ B1/B2 attack what the guard DOES. This attacks what it READS: without `for update skip
  --   locked` + the re-check, a stamp committing between the candidate read and the UPDATE
  --   escalates a row that had just become settleable — the exact defect, re-opened by a race
  --   rather than by a predicate. A battery that only attacks the branch will always miss it.
  -- ⚠ Comments are stripped before matching: this migration's own header documents the predicate
  --   it is being checked for, and `prosrc` is source PLUS our prose. Un-stripped, a check for
  --   CALLING the lock would be satisfied by a comment EXPLAINING it, and the better the
  --   explanation the more surely (the comment-matching law). Absence fails LOUDLY — a NULL
  --   `prosrc` makes every `~` NULL and every bare `if` silent, which is how a pin whose whole
  --   job is to notice something missing is silent about the most complete version of missing.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'sweep_run_end_recovery';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(sweep_run_end_recovery)';
    else
      -- 🔴 NOT a bare `~ 'for update skip locked'`. That was this pin's first form and the battery
      -- measured it blind: arms ⓒ/ⓓ/ⓔ each carry the same clause, so the pattern is present
      -- whether or not ARM ⓑ has one — present in both the fixed and the unfixed state, which is
      -- the uninformative-detector class (CLAUDE.md), inside a pin written to enforce rigour.
      -- Measured: removing arm ⓑ's lock left this arm silent and reddened only 214's count pin.
      -- Two arms that CAN tell the states apart:
      --   ① the COUNT — every arm that writes locks first, so the count is a thing the mutation
      --      moves. ⚠ [0193] 4 → 5: arm ⓕ (the strand's ops bell) is the fifth arm that writes and
      --      it locks like the rest. Updated here rather than left to fail for a true reason (the
      --      house law); THE NEW ARM'S OWN PROPERTY is owned by 224 `0193-R4`, and what this line
      --      owns is unchanged — 「every arm that writes is locked」.
      if (select count(*) from regexp_matches(v_src, 'for update skip locked', 'g')) <> 5
        then v_bad := v_bad || ' 행 락 수가 5가 아니다(ⓑ·ⓒ·ⓓ·ⓔ·ⓕ)'; end if;
      --   ② and arm ⓑ's OWN skip notice, a string no other arm contains, which is only reachable
      --      from the `if not found` that a `skip locked` lock makes possible at all.
      if (v_src ~ 'strand % — row locked by a writer, left for the next tick') is not true
        then v_bad := v_bad || ' 팔 ⓑ의 skip-locked 분기 없음'; end if;
      -- the escalation is reached only through the both-stamps-absent branch, and there is
      -- exactly ONE of it. Matching the ASSIGNMENT, not the word: `incident_review` also appears
      -- in `c_dead`, the deny-list arms ⓒ/ⓓ/ⓔ share, so a bare word match counts three.
      if (select count(*) from regexp_matches(v_src, 'set status = ''incident_review''', 'g')) <> 1
        then v_bad := v_bad || ' 승격 구문이 1개가 아니다'; end if;
      if (v_src ~ 'runner_confirmed_return_at is not null or v_b\.owner_confirmed_return_at is not null')
        is not true then v_bad := v_bad || ' 반환 스탬프 분기 없음'; end if;
      -- the locked row is re-asserted against every predicate of the candidate query, not just
      -- re-read (a lock with no re-check is a lock that proves nothing)
      if (v_src ~ 'v_b\.status <> ''active'' or v_b\.run_ended_at is null or v_b\.settlement_ready_at is not null')
        is not true then v_bad := v_bad || ' 잠근 뒤 재확인 없음'; end if;
      -- [cold review #8] …and the club conjunct, which the first version's comment claimed and
      -- the code omitted. A pin that matches a comment's promise rather than the code is the
      -- documentation-measuring class; this arm makes the promise checkable.
      if (v_src ~ 'v_b\.club_session_id is not null') is not true
        then v_bad := v_bad || ' 잠근 뒤 클럽 재확인 없음'; end if;
      -- [cold review #3] the candidate must DRAIN and must be ordered by something meaningful —
      -- `order by b.id` over v4 uuids with a `limit` on a non-draining set shadows new rows forever.
      if (v_src ~ 'order by b\.run_ended_at') is not true
        then v_bad := v_bad || ' 팔 ⓑ 후보가 오래된 순이 아니다'; end if;
      if (v_src ~ 'nt\.ref_id = b\.id and nt\.title = c_ret_title') is not true
        then v_bad := v_bad || ' 이미 알린 행이 후보에서 빠지지 않는다(드레인 없음)'; end if;
      if (v_src ~ 'v_b\.run_ended_at >= now\(\) - STRAND_AFTER') is not true
        then v_bad := v_bad || ' 잠근 뒤 마감 재확인 없음'; end if;
    end if;
    -- and the deployed shape, because a property checked only at apply is protected exactly until
    -- someone recreates the function (0131-G4's lesson)
    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname='public' and p.proname='sweep_run_end_recovery'
                     and p.prosecdef
                     and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%')
      then v_bad := v_bad || ' definer/search_path 형상 유실'; end if;
    if has_function_privilege('authenticated', 'public.sweep_run_end_recovery()', 'execute')
      then v_bad := v_bad || ' authenticated가 스윕을 실행할 수 있다'; end if;

    if v_bad = ''
      then call _pass('rec','0188-B4 파괴적 분기의 전제 — 팔 ⓑ는 행을 잠그고(for update skip locked) 후보 질의의 모든 술어를 다시 확인한 뒤에만 승격하며, 승격 구문은 정확히 1개이고, 배포된 함수는 definer+search_path를 유지하고 authenticated에게 열려 있지 않다 (주석 제거 후 매칭·소스 부재는 큰 소리로 실패)');
    else v_msg := v_bad; call _fail('rec','0188-B4 파괴적 분기의 전제', v_msg); end if;
  exception when others then
    v_msg := sqlerrm; call _fail('rec','0188-B4 파괴적 분기의 전제', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0188-D1] THE GRANT IS THE DOOR — a PHONE may not be the stamp that seals
  -- 🔴 Found by the cold reviewer, and it is armed BY this slice. `confirm_return_tx` is in
  --    `public` and was granted to `authenticated`, which PostgREST exposes, so a signed-in party
  --    could POST the RPC directly. A client may not bring a price (`quote_from_client`) — so if
  --    theirs was the SECOND stamp the row sealed and settled NOTHING, and afterwards both stamps
  --    exist, so every confirm CTA in the product is gone by construction and the runner is
  --    unpayable with no in-app repair. Inert before this slice (`run_not_ended` for every
  --    reachable marketplace row); reachable after it.
  -- ⚠ TWO ARMS, and the second is not decoration: a revoke that also took `service_role`'s grant
  --    would strand EVERY settlement instead of one, and the failure would look like this pin
  --    passing. The positive control is what tells the two apart.
  -- ⚠ This is the arm 119 R13's positive control used to own; it moved here rather than being
  --    deleted (the house law: name which new pin owns the changed property).
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if has_function_privilege('authenticated', 'public.confirm_return_tx(uuid,text,jsonb)', 'execute')
      then v_bad := v_bad || ' authenticated가 아직 confirm_return_tx를 실행할 수 있다'; end if;
    if has_function_privilege('anon', 'public.confirm_return_tx(uuid,text,jsonb)', 'execute')
      then v_bad := v_bad || ' anon이 confirm_return_tx를 실행할 수 있다'; end if;
    -- POSITIVE CONTROL — the server must still be able to stamp, or nothing settles at all
    if not has_function_privilege('service_role', 'public.confirm_return_tx(uuid,text,jsonb)', 'execute')
      then v_bad := v_bad || ' service_role이 confirm_return_tx를 실행할 수 없다 (모든 정산이 좌초한다)'; end if;
    -- …and the function still exists with the shape the edge calls
    if to_regprocedure('public.confirm_return_tx(uuid,text,jsonb)') is null
      then v_bad := v_bad || ' confirm_return_tx가 없다'; end if;
    -- the neighbours 119 R13 owns are untouched by this revoke — a revoke that caught the family
    -- would look identical to a correct one from inside this pin alone
    if not has_function_privilege('authenticated', 'public.custody_ping(uuid)', 'execute')
      then v_bad := v_bad || ' custody_ping까지 회수됐다 (§6 가족 전체를 걷어찼다)'; end if;
    if has_function_privilege('authenticated', 'public.force_return_tx(uuid,text,text,jsonb,jsonb)', 'execute')
      then v_bad := v_bad || ' force_return_tx가 authenticated에 열렸다 (0089 위반)'; end if;

    if v_bad = ''
      then call _pass('rec','0188-D1 폰은 봉인하는 스탬프가 될 수 없다 — confirm_return_tx는 authenticated·anon 모두에서 회수됐고(직접 RPC 두 번째 스탬프 = 가격 없는 봉인 = 앱에서 고칠 수 없는 미지급), service_role은 그대로 실행할 수 있으며(양성 대조: 이게 없으면 모든 정산이 좌초한다), custody_ping은 남고 force_return_tx는 여전히 닫혀 있다');
    else v_msg := v_bad; call _fail('rec','0188-D1 폰은 봉인하는 스탬프가 될 수 없다', v_msg); end if;
  exception when others then
    v_msg := sqlerrm; call _fail('rec','0188-D1 폰은 봉인하는 스탬프가 될 수 없다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0188-C1] THE CLUB WALL, from the 1:1 door — refused BY NAME, not by a status accident
  -- Clubs run their own custody machine (0045/0069) and their own two-phase stop (0168). The 1:1
  -- ceremony must be unable to reach one, and it must say so with the club's own error rather
  -- than a generic state refusal — the ordering (club gate ABOVE the status gate) is what makes
  -- that true, and 119 R14 pins the same ordering on `confirm_return_tx`.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    insert into club_test_accounts (profile_id, note) values (rr, 'rec suite')
      on conflict (profile_id) do nothing;
    insert into clubs (name, district, host_profile_id) values ('반환 클럽', '반포동', rr)
      returning id into v_club;
    insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
      values (v_club, rr, now() - interval '2 hours', '반환 집결지') returning id into cs;
    b_club := t_rec_live(oo, dg, rt, rr);
    update bookings set club_session_id = cs where id = b_club;

    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      perform end_run_tx(b_club, 3.0, 1200, 'completed', null, null);
      v_bad := v_bad || ' 클럽 예약이 1:1 종료 문을 통과했다';
    exception when others then
      if sqlerrm <> 'club_out_of_scope' then v_bad := v_bad || ' 클럽 종료 거절 이름=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    -- the stop never happened, so nothing downstream can have moved
    if (select b.run_ended_at from bookings b where b.id = b_club) is not null
      then v_bad := v_bad || ' 거절했는데 run_ended_at이 찍혔다'; end if;
    -- and the return door refuses by the same name, ABOVE the status gate
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      perform confirm_return_tx(b_club, 'runner');
      v_bad := v_bad || ' 클럽 예약이 1:1 반환 문을 통과했다';
    exception when others then
      if sqlerrm <> 'club_out_of_scope' then v_bad := v_bad || ' 클럽 반환 거절 이름=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    -- …and the sweep's run-end arms never look at a club row at all
    update bookings set run_ended_at = now() - interval '6 hours' where id = b_club;
    perform sweep_run_end_recovery();
    if (select b.status::text from bookings b where b.id = b_club) <> 'active'
      then v_bad := v_bad || ' 스윕이 클럽 행을 옮겼다=' || (select b.status::text from bookings b where b.id = b_club); end if;
    select count(*) into v_n from notifications
      where ref_id = b_club and title in ('반환 확인이 멈춰 있어요', '귀가 확인이 필요해요');
    if v_n <> 0 then v_bad := v_bad || ' 스윕이 클럽 행에 반환 알림을 썼다=' || v_n; end if;

    if v_bad = ''
      then call _pass('rec','0188-C1 클럽은 1:1 의식에 닿지 않는다 — end_run_tx·confirm_return_tx 모두 club_out_of_scope로 이름을 붙여 거절하고(상태 게이트보다 위), 거절 뒤 run_ended_at도 없으며, 스윕의 반환 팔들은 클럽 행을 옮기지도 알리지도 않는다');
    else v_msg := v_bad; call _fail('rec','0188-C1 클럽은 1:1 의식에 닿지 않는다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('rec','0188-C1 클럽은 1:1 의식에 닿지 않는다', v_msg);
  end;
end $$;
