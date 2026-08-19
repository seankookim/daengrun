-- ═══ 132 gated-runner exit suite — 0096 pins (the deadlock, and the line the fix refuses) ═══
--
-- ═══ WHY THIS SUITE EXISTS, WHICH IS THE WHOLE LESSON ════════════════════════════════════
-- The defect 0096 fixes was invisible to a fully green harness. Three migrations, each correct,
-- each implementing one of Sean's rulings, composed into a runner who could never work again:
--   0092's gate blocks until both return stamps · 0089 removed the party force · 0083's sweep
--   escalates to `incident_review`, where `confirm_return_tx` raised `not_active`.
-- Every pin was green. 119 R16 even ASSERTED the `not_active` raise — correctly, for the world
-- before 0092 existed. **No suite owned the composition**, because each suite pins its own
-- migration and the failing property spanned three.
-- So E3 below is deliberately an END-TO-END pin across all three: it drives the real sweep, then
-- asks `runner_work_gate` — the actual production predicate — whether the runner is free. It is
-- the pin that would have caught this, and it is the reason this file is not just two arms bolted
-- onto 119.
--
-- ═══ THE LINE (E2) ══════════════════════════════════════════════════════════════════════
-- 0096 lets a party stamp from `incident_review` and NOTHING ELSE. No seal, no settlement, no
-- status change. `incident_review` remains a money dead end — `settle_run_tx`,
-- `_settle_sealed_run` and `force_return_tx` all still require `active`, and `0066:56` still
-- allows only `→ refund_pending`. What changed is that the CUSTODY stamp is no longer hostage to
-- a MONEY state. E2 is written to redden if a future edit "helpfully" lets the seal through.
--
-- Style: sibling of 119/125/128/130 — `_pass('gre',…)`/`_fail('gre',…)`, one begin…exception per
--   case, `_fail` args pre-computed into v_msg (the 110 header law). Self-contained fixtures.
-- ⚠ No pin here asserts a money AMOUNT. Every money claim is presence/absence.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   E1 ← 0096 §6: restore `if b.status <> 'active' then raise 'not_active'` — the parties can no
--        longer stamp from `incident_review` and the deadlock returns intact          → RED
--   E2 ← 0096 §6: drop the `and v_may_settle` from the seal branch — `settlement_ready_at` is
--        written from `incident_review`, i.e. "money may move" is asserted about a booking whose
--        only legal transition is `refund_pending`. 🔴 The subtle half of the fix   → RED
--   E3 ← either of the above (it is the composition, so it reddens under both) — kept as its own
--        pin because it is the only one that measures what a RUNNER experiences       → RED
--   E4 ← 0096 §6: widen the gate past `('active','incident_review')` — a cancelled or refunding
--        booking accepts a custody stamp it has no custody for                        → RED
--   E5 ← 0096 §7: grant `ops_gated_runners` to authenticated (it lists other runners' bookings),
--        or let its predicate drift from `0092`'s (a second rule that disagrees with the gate
--        is worse than no detection — it would report the wrong people)               → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-14, from the worktree. Method: revert applied
--     to `0096` in place, WHOLE harness run (the database is dropped and recreated each run, so a
--     migration edit fully re-applies), then restored from a pristine copy and re-verified by md5
--     + a green run. Pristine `0096` md5 `657f607e889dbf26e8c52a72d65be0e7`; green is **544/0**.
--       Q1 the gate reverted to 0083's `if b.status <> 'active'` — i.e. **the deadlock restored
--          exactly as it shipped** → 539/5, red = [119 R16, E1, E2, E3, E5]. R16's detail is the
--          trap in one line: `승격 행 인계가 거부됐다=not_active 보호자 도장이 실제로 남지 않았다`.
--          ⚠ E2 and E5's reds are CASCADES and are named rather than engineered apart: plpgsql
--          rolls back a `begin…exception` block's writes when it catches, so E1's rollback takes
--          its fixture booking with it and E2 then reports `not_found`. That is the subtransaction
--          semantics, not a second defect. E3 firing is the load-bearing result — it is the pin
--          that would have caught the original composition, and it does.
--       Q2 `and v_may_settle` dropped from the seal branch ("both stamps are in, so seal it") →
--          543/1, red = **[E2] alone**, detail `승격 행에 씰이 찍혔다 (돈의 막다른 길이 뚫렸다)`.
--          The subtle half of the fix, caught in isolation. ⚠ Note 125 F4's DB-wide invariant did
--          NOT fire here, correctly: that invariant forbids a seal WITHOUT stamps, and this
--          mutation writes a seal WITH both stamps. Different shape, so E2 has to own this.
--       Q3 the status gate deleted entirely (the lazy "anything not already settled" widening) →
--          543/1, red = [E4] alone, detail `refund_pending에서 인계가 통과했다` — a booking whose
--          custody is already gone accepting a custody stamp.
--     E5's grant matrix is not separately mutated: it is the 116 C21 idiom (proven under that
--     suite) and its predicate-agreement arm is proven by Q1's cascade. Named, not claimed fresh.
set client_min_messages = warning;

-- ---------- suite-local helpers ----------
-- A marketplace booking whose run has STOPPED and which the 2h sweep has escalated — i.e. the
-- exact trap state. Built through the REAL sweep rather than by setting the status directly, so
-- the fixture cannot drift from the thing that actually produces this state in production.
create or replace function t_gre_escalated(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'active', now() - interval '4 hours', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into v;
  insert into runs (booking_id, started_at, trace)
  values (v, now() - interval '4 hours', '[]'::jsonb);
  perform set_config('request.jwt.claim.sub', p_runner::text, false);
  perform end_run_tx(v, 3.2, 1800, 'completed', null, null);
  perform set_config('request.jwt.claim.sub', '', false);
  -- age it past the 2h escalation window, then drive the REAL janitor
  update bookings set run_ended_at = now() - interval '3 hours' where id = v;
  update runs set ended_at = now() - interval '3 hours' where booking_id = v;
  perform sweep_run_end_recovery();
  return v;
end $$;

do $$
declare
  oo uuid; rr uuid; rz uuid; dg uuid; rt uuid;
  b1 uuid; b2 uuid;
  v_bad text := ''; v_msg text; v_js jsonb; v_ts timestamptz; v_n int; v_txt text;
begin
  oo := t_user('gre_oo', 'owner');
  rr := t_user('gre_rr', 'runner'); rz := t_user('gre_rz', 'runner');
  dg := t_dog(oo, '갇힌견'); rt := t_route('갇힌 코스');

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [E1] the parties can say the dog is home, even after escalation
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    b1 := t_gre_escalated(oo, dg, rt, rr);
    -- the fixture must really be in the trap, or every arm below is vacuous
    if (select b.status::text from bookings b where b.id = b1) <> 'incident_review'
      then v_bad := v_bad || ' 픽스처가 승격되지 않았다 (실제 스윕이 이 상태를 안 만든다)'; end if;

    -- ⓐ the runner stamps from incident_review
    perform set_config('request.jwt.claim.sub', rr::text, false);
    v_js := confirm_return_tx(b1, 'runner');
    if not coalesce((v_js->>'stamped')::boolean, false) then v_bad := v_bad || ' 러너 스탬프 거부'; end if;
    if not coalesce((v_js->>'case_open')::boolean, false) then v_bad := v_bad || ' case_open이 거짓'; end if;
    -- ⓑ idempotent — a double tap is the same tap, here too
    v_js := confirm_return_tx(b1, 'runner');
    if coalesce((v_js->>'stamped')::boolean, true) then v_bad := v_bad || ' 재탭이 다시 찍혔다'; end if;
    -- ⓒ the party gate is UNCHANGED by the widening — the runner still cannot stamp the owner
    begin
      perform confirm_return_tx(b1, 'owner');
      v_bad := v_bad || ' 러너가 보호자 쪽을 대신 찍었다';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' 대리 거부=' || sqlerrm; end if;
    end;
    -- ⓓ a stranger gets nothing
    perform set_config('request.jwt.claim.sub', rz::text, false);
    begin
      perform confirm_return_tx(b1, 'runner');
      v_bad := v_bad || ' 제3자가 찍었다';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' 제3자 거부=' || sqlerrm; end if;
    end;
    -- ⓔ the owner stamps — the pair completes while the case is still open
    perform set_config('request.jwt.claim.sub', oo::text, false);
    v_js := confirm_return_tx(b1, 'owner');
    perform set_config('request.jwt.claim.sub', '', false);
    if not coalesce((v_js->>'both_confirmed')::boolean, false)
      then v_bad := v_bad || ' 양측 확인이 보고되지 않았다'; end if;
    if (select b.status::text from bookings b where b.id = b1) <> 'incident_review'
      then v_bad := v_bad || ' 인계 확인이 케이스를 닫아버렸다 (조사자의 일을 대신했다)'; end if;

    if v_bad = ''
      then call _pass('gre','E1 승격 뒤에도 인계는 확인된다 — 실제 스윕이 만든 incident_review 행에서 양측이 스탬프를 찍을 수 있고, 멱등이며, 당사자 게이트·제3자 거부는 그대로이고, 확인이 케이스를 닫지는 않는다');
    else v_msg := v_bad; call _fail('gre','E1 승격 뒤에도 인계는 확인된다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('gre','E1 승격 뒤에도 인계는 확인된다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [E2] 🔴 …and the money dead end is completely undisturbed
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The seductive next edit is "both stamps are in, so seal it". That would assert money may
  -- move out of a state whose only legal transition is `refund_pending` (0066:56) — the dead end
  -- 0083 §0h named and 0072 could not open for marketplace. b1 arrives here fully stamped from
  -- E1, which is exactly the condition under which a loose implementation would seal.
  begin
    v_bad := '';
    if (select b.runner_confirmed_return_at is not null and b.owner_confirmed_return_at is not null
          from bookings b where b.id = b1) is not true
      then v_bad := v_bad || ' 픽스처: 양측 스탬프가 없다 (E2가 무의미해진다)'; end if;

    -- ⓐ no seal. "money may move" is not asserted about this row.
    if (select b.settlement_ready_at from bookings b where b.id = b1) is not null
      then v_bad := v_bad || ' 승격 행에 씰이 찍혔다 (돈의 막다른 길이 뚫렸다)'; end if;
    -- ⓑ no money
    if exists (select 1 from ledger_items li where li.booking_id = b1)
      then v_bad := v_bad || ' 원장이 생겼다'; end if;
    if exists (select 1 from payments p where p.booking_id = b1)
      then v_bad := v_bad || ' 결제 행이 생겼다'; end if;
    if (select r.settled_at from runs r where r.booking_id = b1) is not null
      then v_bad := v_bad || ' settled_at이 찍혔다'; end if;
    -- ⓒ the other three functions still refuse — 0096 let ONE thing through, not the wall
    begin
      perform _settle_sealed_run(b1, jsonb_build_object(
        'base',9900,'distance_pay',9600,'addon_pay',0,'guarantee',0,'fee',3900));
      v_bad := v_bad || ' _settle_sealed_run이 승격 행을 정산했다';
    exception when others then
      if sqlerrm <> 'not_active' then v_bad := v_bad || ' _settle_sealed_run 거부=' || sqlerrm; end if;
    end;
    begin
      perform force_return_tx(b1, 'ops', '판정', jsonb_build_object('kind','ops'));
      v_bad := v_bad || ' force_return_tx가 승격 행을 통과시켰다';
    exception when others then
      if sqlerrm <> 'not_active' then v_bad := v_bad || ' force_return_tx 거부=' || sqlerrm; end if;
    end;
    -- ⓓ the sealed shape stays consistent with 125 F4's DB-wide invariant: this row has stamps
    --   and no seal, which is the OPPOSITE of the shape that invariant forbids (seal, no stamps)
    if exists (select 1 from bookings b
                where b.settlement_ready_at is not null and b.return_forced_by is null
                  and (b.runner_confirmed_return_at is null or b.owner_confirmed_return_at is null))
      then v_bad := v_bad || ' 스탬프 없는 씰 행이 생겼다 (125 F4 불변식 위반)'; end if;

    if v_bad = ''
      then call _pass('gre','E2 돈의 막다른 길은 그대로 — 양측 스탬프가 다 찍힌 승격 행에도 씰·원장·결제·settled_at이 하나도 없고, _settle_sealed_run과 force_return_tx는 여전히 not_active로 거부하며, 스탬프 없는 씰이라는 금지된 형상도 생기지 않는다 (0096은 커스터디 스탬프 하나만 통과시켰다)');
    else v_msg := v_bad; call _fail('gre','E2 돈의 막다른 길은 그대로', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('gre','E2 돈의 막다른 길은 그대로', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [E3] 🔴 THE COMPOSITION — the runner actually gets out
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The pin that would have caught the original defect. It spans 0083 (the sweep), 0089 (no party
  -- force), 0092 (the gate) and 0096 (the exit), and it asks the PRODUCTION predicate
  -- `runner_work_gate` — not a reimplementation of it — whether the runner may work.
  begin
    v_bad := '';
    b2 := t_gre_escalated(oo, dg, rt, rz);

    -- ⓐ escalated and unconfirmed → gated, and gated ON THIS BOOKING
    v_js := runner_work_gate(rz);
    if not coalesce((v_js->>'gated')::boolean, false)
      then v_bad := v_bad || ' 승격 직후인데 게이트되지 않았다 (픽스처가 위험을 재현 못 한다)'; end if;
    if (v_js->>'booking_id') is distinct from b2::text
      then v_bad := v_bad || ' 다른 예약을 지목했다'; end if;
    if (v_js->>'status') is distinct from 'incident_review'
      then v_bad := v_bad || ' 상태 보고=' || coalesce(v_js->>'status','∅'); end if;

    -- ⓑ 0089's law is intact: the runner cannot force their own way out
    begin
      perform force_return_tx(b2, 'runner', '내보내줘', jsonb_build_object('kind','x'));
      v_bad := v_bad || ' 러너가 스스로 강제했다 (0089가 뚫렸다)';
    exception when others then
      if sqlerrm <> 'force_party_forbidden' then v_bad := v_bad || ' 러너 강제 거부=' || sqlerrm; end if;
    end;

    -- ⓒ one stamp is NOT enough — the ruling survives the fix
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform confirm_return_tx(b2, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    v_js := runner_work_gate(rz);
    if not coalesce((v_js->>'gated')::boolean, false)
      then v_bad := v_bad || ' 러너 혼자 확인으로 게이트가 풀렸다 (한쪽 확정이 부활했다)'; end if;
    if (v_js->>'waiting_on') is distinct from 'owner'
      then v_bad := v_bad || ' waiting_on=' || coalesce(v_js->>'waiting_on','∅'); end if;

    -- ⓓ 🔴 the owner stamps → THE RUNNER IS FREE, with the case still open and no ops involved
    perform set_config('request.jwt.claim.sub', oo::text, false);
    perform confirm_return_tx(b2, 'owner');
    perform set_config('request.jwt.claim.sub', '', false);
    v_js := runner_work_gate(rz);
    if coalesce((v_js->>'gated')::boolean, true)
      then v_bad := v_bad || ' 양측 확인 뒤에도 러너가 묶여 있다 (교착이 살아있다)'; end if;
    if (select b.status::text from bookings b where b.id = b2) <> 'incident_review'
      then v_bad := v_bad || ' 러너를 풀려고 케이스를 닫았다'; end if;
    -- and it cost no money and no adjudicator
    if exists (select 1 from ledger_items li where li.booking_id = b2)
      then v_bad := v_bad || ' 러너를 푸는 데 돈이 움직였다'; end if;
    if (select b.return_forced_by from bookings b where b.id = b2) is not null
      then v_bad := v_bad || ' ops 개입이 필요했다 (자력 출구가 아니다)'; end if;

    if v_bad = ''
      then call _pass('gre','E3 합성 — 실제 스윕이 승격시킨 예약에서 러너는 처음엔 묶이고(0092), 스스로 강제할 수 없고(0089), 한쪽 확인으로도 풀리지 않으며, 양측이 확인하는 순간 풀린다 — 케이스는 열린 채, 돈은 그대로, ops 개입 없이. 이 핀이 원래 결함을 잡았을 핀이다');
    else v_msg := v_bad; call _fail('gre','E3 합성', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('gre','E3 합성', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [E4] the gate widened by exactly two states, not by "not completed"
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The lazy widening is `if b.status = 'cancelled_owner' then …` or dropping the check entirely.
  -- A cancelled or refunding booking has no custody to confirm, and a stamp there would feed
  -- `runner_work_gate` a row that means nothing.
  begin
    v_bad := '';
    b2 := t_gre_escalated(oo, dg, rt, rr);
    update bookings set status = 'refund_pending' where id = b2;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      perform confirm_return_tx(b2, 'runner');
      v_bad := v_bad || ' refund_pending에서 인계가 통과했다';
    exception when others then
      if sqlerrm <> 'not_active' then v_bad := v_bad || ' refund_pending 거부=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    -- and `run_not_ended` still guards the pre-stop case (positive control on the other raise)
    insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
      base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (oo, dg, rr, rt, 'active', now() - interval '10 minutes', 5.0, 9900, 15000, 0, 24900, 9900)
    returning id into b2;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      perform confirm_return_tx(b2, 'runner');
      v_bad := v_bad || ' 러닝이 안 끝났는데 인계가 통과했다';
    exception when others then
      if sqlerrm <> 'run_not_ended' then v_bad := v_bad || ' run_not_ended 거부=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    update bookings set status = 'completed' where id = b2;

    if v_bad = ''
      then call _pass('gre','E4 정확히 두 상태만 — refund_pending은 여전히 not_active로 거부되고(커스터디가 없는 예약에 인계는 없다), 정지 전 확인은 run_not_ended로 거부된다 (양성 대조)');
    else v_msg := v_bad; call _fail('gre','E4 정확히 두 상태만', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('gre','E4 정확히 두 상태만', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [E5] detection agrees with the gate, and is not a client surface
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- ⑫'s memo: an ops signal whose remedy does not apply is worse than an unmonitored state. So
  -- the two things pinned are (i) detection uses the SAME predicate as the gate — a second rule
  -- that disagreed would report the wrong people — and (ii) every row names a remedy that is now
  -- actually reachable by the parties, which is only true because of 0096 §6.
  begin
    v_bad := '';
    b2 := t_gre_escalated(oo, dg, rt, rz);   -- rz is free again after E3; re-gate them

    if not exists (select 1 from ops_gated_runners() g where g.booking_id = b2 and g.runner_id = rz)
      then v_bad := v_bad || ' 묶인 러너가 탐지되지 않았다'; end if;
    select g.waiting_on, g.remedy into v_txt, v_msg from ops_gated_runners() g where g.booking_id = b2;
    if v_txt is distinct from 'both' then v_bad := v_bad || ' waiting_on=' || coalesce(v_txt,'∅'); end if;
    if coalesce(v_msg,'') = '' then v_bad := v_bad || ' remedy가 비었다'; end if;
    if v_msg not like '%confirm_return_tx%'
      then v_bad := v_bad || ' remedy가 당사자 경로를 가리키지 않는다=' || coalesce(v_msg,'∅'); end if;

    -- 🔴 detection agrees with the GATE, row for row. Any runner the gate blocks must appear,
    -- and no runner it frees may. This is the "second rule" guard.
    select count(*) into v_n from (
      select distinct b.runner_id from bookings b
       where b.runner_id is not null
         and coalesce((runner_work_gate(b.runner_id)->>'gated')::boolean, false)
    ) x;
    if v_n <> (select count(distinct g.runner_id) from ops_gated_runners() g)
      then v_bad := v_bad || ' 탐지와 게이트의 러너 수가 다르다 (규칙이 갈라졌다)'; end if;

    -- clearing it removes the row — detection is derived, like the gate itself
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform confirm_return_tx(b2, 'runner');
    perform set_config('request.jwt.claim.sub', oo::text, false);
    perform confirm_return_tx(b2, 'owner');
    perform set_config('request.jwt.claim.sub', '', false);
    if exists (select 1 from ops_gated_runners() g where g.booking_id = b2)
      then v_bad := v_bad || ' 해소된 뒤에도 탐지에 남아있다'; end if;

    -- grants: it lists OTHER runners' bookings, so it is server-only
    if has_function_privilege('authenticated', 'ops_gated_runners()', 'execute')
      then v_bad := v_bad || ' 탐지가 authenticated에 열렸다'; end if;
    if has_function_privilege('anon', 'ops_gated_runners()', 'execute')
      then v_bad := v_bad || ' 탐지가 anon에 열렸다'; end if;
    if not has_function_privilege('service_role', 'ops_gated_runners()', 'execute')
      then v_bad := v_bad || ' 탐지가 service_role에서 막혔다'; end if;
    if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'ops_gated_runners'
           and p.prosecdef and 'search_path=public, pg_temp' = any(p.proconfig)) <> 1
      then v_bad := v_bad || ' definer/search_path 미설정'; end if;

    if v_bad = ''
      then call _pass('gre','E5 탐지 — 묶인 러너를 게이트와 행 단위로 같은 술어로 찾아내고(규칙이 갈라지면 엉뚱한 사람을 보고한다), 각 행이 0096 이후 실제로 당사자가 쓸 수 있는 remedy를 이름으로 갖고, 해소되면 사라지며, service_role 전용이다');
    else v_msg := v_bad; call _fail('gre','E5 탐지', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('gre','E5 탐지', v_msg);
  end;
end $$;
