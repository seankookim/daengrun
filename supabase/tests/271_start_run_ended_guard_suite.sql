-- ═══ 271 start_run_tx ended-run guard — 0240 pins (0240-S1 ~ S7) ═══
-- What this suite pins: that `start_run_tx` REFUSES a start on a run that has already ended —
--   `bookings.run_ended_at` set while the status is still `active` (end_run_tx, 0083 §3, leaves it
--   there until settlement) — and that everything else 0087 §2 promised survived the copy.
-- Sibling of 123 (0087's suite): the same helpers (`_pass('sreg',…)` / `_fail('sreg',…)`), one
--   begin…exception per case, the caller's identity faked with `request.jwt.claim.sub` and always
--   reset. Fixtures start where production starts: a `picked_up` booking, started through
--   `start_run_tx` and ended through `end_run_tx` — never a hand-stamped `run_ended_at` alone.
--   The ONE hand-stamped fixture (S1 arm B) is a state the real path cannot reach — `active` +
--   `run_ended_at` + NO runs row, because end_run_tx always upserts the row — and it exists so the
--   conjunct is measured on the fixture where 0087's OTHER answer, the repair insert, would have
--   fired (on 0087's body this booking is ACCEPTED and given a runs row). ⚠ It does NOT observe the
--   ORDER of the refusal against the repair: a raise placed after the insert rolls the insert back
--   inside the case's subtransaction, so 「refused, no row」 reads the same in both orders (measured:
--   the conjunct moved below the insert leaves S1 GREEN and reddens S7 alone). The order is SOURCE
--   POSITION, owned by S7 and 0240 §B VERIFY; the case says so where it is used.
-- ⚠ Every refusal is captured by `t_sreg_try(...)`, which returns the message text or '' — so
--   every assertion below is an EXACT BOOLEAN (`is distinct from true` / `is not true`), never a
--   bare IF on a predicate that could be NULL (the plpgsql-NULL law: a bare IF on NULL is silent,
--   and the pins it kills are exactly the ones whose job is to notice that something is missing).
-- ⚠ `_fail` details are pre-computed into v_msg, never a subquery (110's law).
-- ⚠ S7 reads prosrc with COMMENTS STRIPPED: the comment inside 0240's body names the very tokens
--   the pin looks for, so an un-stripped match would be measuring the documentation.
--
-- ─── MUTATION map — each pin goes RED under a named revert (house law) ───
--   S1  ← delete the conjunct (`if b.run_ended_at is not null then raise …`), or replace its
--         raise with the unchanged return                                                   → RED
--         ⚠ moving the conjunct BELOW the repair insert leaves S1 GREEN, arm B included: the raise
--         rolls the repair back, so that order has no behavioural signature — S7 owns it
--   S2  ← invert the conjunct (`is null`), let a second start raise, or let the idempotent branch
--         overwrite `started_at`                                                             → RED
--   S3  ← delete 0087's repair insert, or turn its coalesce into an overwrite of NULL         → RED
--   S4  ← CONTROL — delete the picked_up claim or the `not_picked_up` state gate              → RED
--   S5  ← move the ended check ABOVE the party gate (its stranger arm); delete the conjunct
--         (its own-runner CONTROL arm — deliberately, so the fixture is proven to sit where the
--         two gates diverge rather than in their agreement zone)                            → RED
--   S6  ← `security invoker`, drop the in-body search_path, grant execute to authenticated /
--         anon / public, or drop the function (NO-FUNCTION)                                  → RED
--   S7  ← any of S1's reverts, move the conjunct BELOW the repair insert / the unchanged return
--         (source position ONLY — measured 1592/1, S7 alone), or drop the function (NO-SOURCE) → RED
--   ⚠ Dropping 0240's REVOKE/GRANT lines alone reddens NOTHING here: the harness applies 0087
--     first, so `create or replace` PRESERVES the ACL and S6 then measures a preserved grant, not
--     this file's. That class is structurally unreachable by this harness (CLAUDE.md
--     §check-definer-acl) and is the source gate's job — the 0240 REGISTRY row records the
--     battery, including that row, as measured.
set client_min_messages = warning;

-- ---------- suite-local helpers ----------
-- A marketplace booking born in the state a case needs (123's constructor law: `enforce_booking_
-- transition` has no downgrade edges, so the status is an argument, never a later patch).
-- `p_ended` exists for S1 arm B alone — an INSERT-time stamp, so no UPDATE trigger runs on a row
-- that has no runs row (see that arm for why it is hand-built).
create or replace function t_sreg_picked(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid,
                                         p_status booking_status default 'picked_up',
                                         p_ended timestamptz default null)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare, run_ended_at)
  values (p_owner, p_dog, p_runner, p_route, p_status, now() - interval '10 minutes', 5.0,
          9900, 15000, 0, 24900, 9900, p_ended)
  returning id into v;
  return v;
end $$;

-- "what did the start say?" — runs start_run_tx AS p_uid; '' on success, the refusal's message
-- otherwise. The identity is reset on both paths, so a raise never leaks a login into the next case.
create or replace function t_sreg_try(p_booking uuid, p_uid uuid) returns text
language plpgsql as $$
declare v_err text := '';
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, false);
  begin
    perform start_run_tx(p_booking);
  exception when others then
    v_err := sqlerrm;
  end;
  perform set_config('request.jwt.claim.sub', '', false);
  return v_err;
end $$;

-- the start that must SUCCEED — returns the payload, re-raises anything else (a case wants to know)
create or replace function t_sreg_start(p_booking uuid, p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, false);
  begin
    v := start_run_tx(p_booking);
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    raise;
  end;
  perform set_config('request.jwt.claim.sub', '', false);
  return v;
end $$;

-- the REAL end: end_run_tx as the assigned runner (3.2 km of 5.0 — above the 50% completion floor,
-- inside the km band, `completed` is runner-declarable). This is what stamps run_ended_at.
create or replace function t_sreg_end(p_booking uuid, p_uid uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, false);
  begin
    v := end_run_tx(p_booking, 3.2, 2100, 'completed', null, null);
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    raise;
  end;
  perform set_config('request.jwt.claim.sub', '', false);
  return v;
end $$;

-- an ended-but-unsettled booking on the REAL path: picked_up → start_run_tx → end_run_tx.
-- Afterwards: status still `active`, run_ended_at set, one runs row with started_at AND ended_at.
create or replace function t_sreg_ended(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid)
returns uuid language plpgsql as $$
declare v uuid;
begin
  v := t_sreg_picked(p_owner, p_dog, p_route, p_runner);
  perform t_sreg_start(v, p_runner);
  perform t_sreg_end(v, p_runner);
  return v;
end $$;

do $$
declare
  oo uuid; rr uuid; rz uuid; dg uuid; rt uuid;
  bk uuid; b_b uuid; b_c uuid;
  v_bad text := ''; v_msg text; v_err text; v_err2 text;
  v_n int; v_n2 int; v_noti int; v_noti2 int;
  v_js jsonb; v_ts timestamptz; v_ts2 timestamptz; v_ended timestamptz; v_ended2 timestamptz;
  v_status text; v_oid oid; v_raw text; v_src text;
  v_p_party int; v_p_gate int; v_p_repair int; v_p_unch int;
begin
  oo := t_user('sreg_oo', 'owner');
  rr := t_user('sreg_rr', 'runner'); rz := t_user('sreg_rz', 'runner');
  dg := t_dog(oo, '종료견'); rt := t_route('종료 코스');

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0240-S1] a start on an ENDED run is refused with `run_ended`, and nothing moves
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- Arm A is the real path. The fixture is asserted to be IN the state the pin is about (active
  -- + run_ended_at + one runs row with a started_at) before the start is attempted, because a
  -- refusal measured on a fixture that never reached the state would be a green about nothing.
  begin
    v_bad := '';
    bk := t_sreg_ended(oo, dg, rt, rr);
    select b.status::text, b.run_ended_at into v_status, v_ended from bookings b where b.id = bk;
    if (v_status = 'active') is not true
      then v_bad := v_bad || ' 픽스처 상태가 active가 아니다=' || coalesce(v_status, '∅'); end if;
    if (v_ended is not null) is not true then v_bad := v_bad || ' 픽스처에 run_ended_at이 없다'; end if;
    select r.started_at into v_ts from runs r where r.booking_id = bk;
    if (v_ts is not null) is not true then v_bad := v_bad || ' 픽스처 runs.started_at이 없다'; end if;
    if (select count(*) from runs r where r.booking_id = bk and r.ended_at is not null) is distinct from 1
      then v_bad := v_bad || ' 픽스처 runs 행(ended_at)이 1이 아니다'; end if;
    select count(*) into v_noti from notifications where profile_id in (oo, rr);

    v_err := t_sreg_try(bk, rr);
    if (v_err like '%run_ended%') is distinct from true
      then v_bad := v_bad || ' 종료된 러닝의 시작이 run_ended로 거부되지 않았다=' || coalesce(nullif(v_err, ''), '(통과)'); end if;

    select b.status::text, b.run_ended_at into v_status, v_ended2 from bookings b where b.id = bk;
    if (v_status = 'active') is not true
      then v_bad := v_bad || ' 거부됐는데 상태가 움직였다=' || coalesce(v_status, '∅'); end if;
    if v_ended2 is distinct from v_ended then v_bad := v_bad || ' 거부됐는데 run_ended_at이 움직였다'; end if;
    select r.started_at into v_ts2 from runs r where r.booking_id = bk;
    if v_ts2 is distinct from v_ts then v_bad := v_bad || ' 거부됐는데 started_at이 움직였다'; end if;
    select count(*) into v_n from runs where booking_id = bk;
    if v_n is distinct from 1 then v_bad := v_bad || ' 거부됐는데 runs 행 수가 변했다=' || v_n; end if;
    select count(*) into v_noti2 from notifications where profile_id in (oo, rr);
    if v_noti2 is distinct from v_noti
      then v_bad := v_bad || ' 거부됐는데 알림 행이 변했다=' || v_noti || '→' || v_noti2; end if;

    -- Arm B — HAND-BUILT, and here is why: `active` + `run_ended_at` + NO runs row is a state the
    -- real path cannot produce (end_run_tx always upserts the runs row). It is the fixture on which
    -- 0087's OTHER answer would fire: on 0087's body this booking is ACCEPTED and the repair insert
    -- gives it a runs row (measured, M1v — S1 red with a row born here); with the conjunct it is
    -- refused and no row survives. ⚠ What it does NOT prove: the ORDER of the refusal against the
    -- repair. A raise placed after the insert rolls the insert back inside t_sreg_try's
    -- begin…exception subtransaction, so `count = 0` reads the same whether the check precedes or
    -- follows the repair (measured: the conjunct moved below the insert leaves this arm GREEN and
    -- reddens S7 alone). The order is source position — S7 and 0240 §B VERIFY own it. The stamp
    -- goes in at INSERT time so no update trigger runs on a row that has no run.
    b_b := t_sreg_picked(oo, dg, rt, rr, 'active', now() - interval '5 minutes');
    if (select count(*) from runs where booking_id = b_b) is distinct from 0
      then v_bad := v_bad || ' 팔B 픽스처에 runs 행이 있다'; end if;
    v_err2 := t_sreg_try(b_b, rr);
    if (v_err2 like '%run_ended%') is distinct from true
      then v_bad := v_bad || ' 팔B: 거부되지 않았다=' || coalesce(nullif(v_err2, ''), '(통과)'); end if;
    select count(*) into v_n2 from runs where booking_id = b_b;
    if v_n2 is distinct from 0
      then v_bad := v_bad || ' 팔B: 거부됐는데 runs 행이 남았다=' || v_n2; end if;

    if v_bad = ''
      then call _pass('sreg','0240-S1 종료된 러닝은 다시 시작할 수 없다 — 실경로(start_run_tx→end_run_tx) 픽스처는 run_ended로 거부, 상태·run_ended_at·started_at·runs 행·알림 무변; 손도장 팔B(runs 행 없음)도 거부되고 runs 행이 남지 않는다');
    else v_msg := v_bad; call _fail('sreg','0240-S1 종료된 러닝은 다시 시작할 수 없다', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('sreg','0240-S1 종료된 러닝은 다시 시작할 수 없다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0240-S2] a second start on a LIVE run is still the SAME start (0087's idempotence kept)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The runner's screen re-fires the start on every re-entry (0087 §2's reason for the branch);
  -- the new conjunct must not turn that into an error, move the clock, or add a row anywhere.
  begin
    v_bad := '';
    bk := t_sreg_picked(oo, dg, rt, rr);
    v_js := t_sreg_start(bk, rr);
    if (v_js->>'unchanged')::boolean is distinct from false then v_bad := v_bad || ' 첫 시작이 unchanged=false가 아니다'; end if;
    select r.started_at into v_ts from runs r where r.booking_id = bk;
    if (v_ts is not null) is not true then v_bad := v_bad || ' 첫 시작에 started_at이 없다'; end if;
    select count(*) into v_noti from notifications where profile_id in (oo, rr);

    v_js := t_sreg_start(bk, rr);
    if (v_js->>'unchanged')::boolean is distinct from true then v_bad := v_bad || ' 재시작이 unchanged=true가 아니다'; end if;
    if (v_js->>'started_at')::timestamptz is distinct from v_ts then v_bad := v_bad || ' 재시작 응답의 started_at이 첫 시작과 다르다'; end if;
    select r.started_at into v_ts2 from runs r where r.booking_id = bk;
    if v_ts2 is distinct from v_ts then v_bad := v_bad || ' 재시작이 started_at을 옮겼다'; end if;
    select count(*) into v_n from runs where booking_id = bk;
    if v_n is distinct from 1 then v_bad := v_bad || ' runs 행이 1이 아니다=' || v_n; end if;
    select b.status::text, b.run_ended_at into v_status, v_ended from bookings b where b.id = bk;
    if (v_status = 'active') is not true then v_bad := v_bad || ' 상태가 active가 아니다=' || coalesce(v_status, '∅'); end if;
    if v_ended is not null then v_bad := v_bad || ' 살아있는 러닝에 run_ended_at이 생겼다'; end if;
    select count(*) into v_noti2 from notifications where profile_id in (oo, rr);
    if v_noti2 is distinct from v_noti
      then v_bad := v_bad || ' 재시작이 알림 행을 바꿨다=' || v_noti || '→' || v_noti2; end if;

    if v_bad = ''
      then call _pass('sreg','0240-S2 살아있는 러닝의 재시작은 여전히 같은 시작 — unchanged=true·같은 started_at·runs 1행·run_ended_at NULL·알림 무변');
    else v_msg := v_bad; call _fail('sreg','0240-S2 살아있는 러닝의 재시작', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('sreg','0240-S2 살아있는 러닝의 재시작', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0240-S3] 0087's REPAIR on a live run survived the copy
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- (a) no runs row at all (the two-step's crash window) → a row is born with the server's clock;
  -- (b) a row whose started_at is NULL → repaired. Both are `run_ended_at IS NULL` worlds, so the
  -- new conjunct is silent here by construction — this is the pin that proves it stayed silent.
  begin
    v_bad := '';
    bk := t_sreg_picked(oo, dg, rt, rr);
    perform t_sreg_start(bk, rr);
    delete from runs where booking_id = bk;
    if (select count(*) from runs where booking_id = bk) is distinct from 0
      then v_bad := v_bad || ' (a) runs 행을 지우지 못했다'; end if;
    v_js := t_sreg_start(bk, rr);
    if (v_js->>'unchanged')::boolean is distinct from true then v_bad := v_bad || ' (a) 복구 시작이 unchanged=true가 아니다'; end if;
    select r.started_at into v_ts from runs r where r.booking_id = bk;
    if (v_ts is not null and v_ts > now() - interval '1 minute') is not true
      then v_bad := v_bad || ' (a) runs 행이 서버 시각으로 태어나지 않았다=' || coalesce(v_ts::text, '∅'); end if;
    if (v_js->>'started_at')::timestamptz is distinct from v_ts
      then v_bad := v_bad || ' (a) 응답의 started_at이 행과 다르다'; end if;

    b_c := t_sreg_picked(oo, dg, rt, rr);
    perform t_sreg_start(b_c, rr);
    update runs set started_at = null where booking_id = b_c;
    if (select r.started_at is null from runs r where r.booking_id = b_c) is not true
      then v_bad := v_bad || ' (b) started_at을 비우지 못했다'; end if;
    v_js := t_sreg_start(b_c, rr);
    if (v_js->>'unchanged')::boolean is distinct from true then v_bad := v_bad || ' (b) 복구 시작이 unchanged=true가 아니다'; end if;
    select r.started_at into v_ts2 from runs r where r.booking_id = b_c;
    if (v_ts2 is not null) is not true then v_bad := v_bad || ' (b) started_at 결손이 복구되지 않았다'; end if;
    if (select count(*) from runs where booking_id = b_c) is distinct from 1
      then v_bad := v_bad || ' (b) runs 행이 1이 아니다'; end if;

    if v_bad = ''
      then call _pass('sreg','0240-S3 0087의 복구 경로 보존 — 살아있는 러닝에서 runs 행 없음은 서버 시각으로 태어나고, started_at NULL은 복구된다');
    else v_msg := v_bad; call _fail('sreg','0240-S3 0087의 복구 경로 보존', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('sreg','0240-S3 0087의 복구 경로 보존', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0240-S4] CONTROL — the start itself, and 0087's own state gate
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    bk := t_sreg_picked(oo, dg, rt, rr);
    v_js := t_sreg_start(bk, rr);
    if (v_js->>'unchanged')::boolean is distinct from false then v_bad := v_bad || ' 첫 시작이 unchanged=false가 아니다'; end if;
    select b.status::text, b.run_ended_at into v_status, v_ended from bookings b where b.id = bk;
    if (v_status = 'active') is not true then v_bad := v_bad || ' 상태가 active로 가지 않았다=' || coalesce(v_status, '∅'); end if;
    if v_ended is not null then v_bad := v_bad || ' 시작이 run_ended_at을 찍었다'; end if;
    select r.started_at into v_ts from runs r where r.booking_id = bk;
    if (v_ts is not null and v_ts > now() - interval '1 minute') is not true
      then v_bad := v_bad || ' 서버 started_at이 아니다=' || coalesce(v_ts::text, '∅'); end if;
    if (v_js->>'started_at')::timestamptz is distinct from v_ts then v_bad := v_bad || ' 응답의 started_at이 행과 다르다'; end if;
    if (select count(*) from runs where booking_id = bk) is distinct from 1 then v_bad := v_bad || ' runs 행이 1이 아니다'; end if;

    -- a booking that has not been handed over still cannot start (0087's gate, not this file's)
    b_c := t_sreg_picked(oo, dg, rt, rr, 'confirmed');
    v_err := t_sreg_try(b_c, rr);
    if (v_err like '%not_picked_up%') is distinct from true
      then v_bad := v_bad || ' confirmed에서 시작이 not_picked_up으로 거부되지 않았다=' || coalesce(nullif(v_err, ''), '(통과)'); end if;
    if (select count(*) from runs where booking_id = b_c) is distinct from 0 then v_bad := v_bad || ' 거부됐는데 runs 행이 생겼다'; end if;
    if (select b.status::text from bookings b where b.id = b_c) is distinct from 'confirmed'
      then v_bad := v_bad || ' 거부됐는데 상태가 움직였다'; end if;

    if v_bad = ''
      then call _pass('sreg','0240-S4 대조 — picked_up → active, unchanged=false, 서버 시각의 runs 1행; confirmed는 not_picked_up (0087 §2 그대로)');
    else v_msg := v_bad; call _fail('sreg','0240-S4 대조 — 시작 자체', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('sreg','0240-S4 대조 — 시작 자체', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0240-S5] party gate BEFORE the new state gate (repo law)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The fixture must sit where the two gates DIVERGE, or the pin cannot tell "party gate first"
  -- from "ended check absent": the assigned runner on this booking is told run_ended (the
  -- CONTROL arm — it goes red when the conjunct is deleted, deliberately), and a different runner
  -- or a ghost id on the SAME booking is told not_run_runner and never run_ended. Run state is not
  -- disclosed to a non-party.
  begin
    v_bad := '';
    bk := t_sreg_ended(oo, dg, rt, rr);
    select b.run_ended_at into v_ended from bookings b where b.id = bk;
    if (v_ended is not null) is not true then v_bad := v_bad || ' 픽스처에 run_ended_at이 없다'; end if;

    v_err := t_sreg_try(bk, rr);
    if (v_err like '%run_ended%') is distinct from true
      then v_bad := v_bad || ' 대조: 당사자 러너에게 run_ended가 아니다=' || coalesce(nullif(v_err, ''), '(통과)'); end if;

    v_err2 := t_sreg_try(bk, rz);
    if (v_err2 like '%not_run_runner%') is distinct from true
      then v_bad := v_bad || ' 남의 러너에게 not_run_runner가 아니다=' || coalesce(nullif(v_err2, ''), '(통과)'); end if;
    if (v_err2 like '%run_ended%') is distinct from false
      then v_bad := v_bad || ' 남의 러너에게 run_ended가 새어 나갔다 (상태 게이트가 당사자 게이트보다 먼저 섰다)'; end if;

    v_err2 := t_sreg_try(bk, gen_random_uuid());
    if (v_err2 like '%not_run_runner%') is distinct from true
      then v_bad := v_bad || ' 유령 id에게 not_run_runner가 아니다=' || coalesce(nullif(v_err2, ''), '(통과)'); end if;
    if (v_err2 like '%run_ended%') is distinct from false
      then v_bad := v_bad || ' 유령 id에게 run_ended가 새어 나갔다'; end if;

    select b.status::text, b.run_ended_at into v_status, v_ended2 from bookings b where b.id = bk;
    if (v_status = 'active') is not true then v_bad := v_bad || ' 거부됐는데 상태가 움직였다=' || coalesce(v_status, '∅'); end if;
    if v_ended2 is distinct from v_ended then v_bad := v_bad || ' 거부됐는데 run_ended_at이 움직였다'; end if;
    if (select count(*) from runs where booking_id = bk) is distinct from 1 then v_bad := v_bad || ' runs 행 수가 변했다'; end if;

    if v_bad = ''
      then call _pass('sreg','0240-S5 당사자 게이트가 상태 게이트보다 먼저 — 종료된 러닝에서 남의 러너·유령 id는 not_run_runner(run_ended 무유출), 당사자 러너는 run_ended (대조); 무변');
    else v_msg := v_bad; call _fail('sreg','0240-S5 당사자 게이트가 상태 게이트보다 먼저', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('sreg','0240-S5 당사자 게이트가 상태 게이트보다 먼저', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0240-S6] the preconditions the guard READS, pinned every run (0131-G4's lesson)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- A property checked only at apply (0240 §B) is protected exactly until someone re-creates the
  -- function. The NULL-ACL arm stands first: a NULL proacl is PUBLIC-executable (0116:636).
  begin
    v_bad := '';
    v_oid := to_regprocedure('start_run_tx(uuid)')::oid;
    if v_oid is null then v_bad := v_bad || ' 🔴 NO-FUNCTION(start_run_tx(uuid))';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' definer가 아니다'; end if;
      if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 본문 search_path가 없다'; end if;
      if (select pronamespace = 'public'::regnamespace from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' public 스키마가 아니다'; end if;
      if (select proacl from pg_proc where oid = v_oid) is null
        then v_bad := v_bad || ' 🔴 ACL이 NULL이다 (기본 PUBLIC 실행)'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 🔴 anon이 실행할 수 있다'; end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 🔴 authenticated가 실행할 수 있다'; end if;
      if has_function_privilege('public', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 🔴 PUBLIC이 실행할 수 있다'; end if;
      if has_function_privilege('service_role', v_oid, 'execute') is not true
        then v_bad := v_bad || ' service_role이 실행할 수 없다'; end if;
    end if;
    if v_bad = ''
      then call _pass('sreg','0240-S6 전제 — definer·본문 search_path·public 스키마·ACL 비NULL·anon/authenticated/PUBLIC 실행 불가·service_role 실행 가능');
    else v_msg := v_bad; call _fail('sreg','0240-S6 전제', v_msg); end if;
  exception when others then
    v_msg := sqlerrm; call _fail('sreg','0240-S6 전제', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0240-S7] deployed SOURCE, comments stripped — the raise, its conjunct, and its POSITION
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- Every presence is asserted before any position is compared (a position of 0 compares as
  -- "before everything" and would make an ORDER arm green on an absent token).
  begin
    v_bad := '';
    select p.prosrc into v_raw from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname = 'start_run_tx';
    if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' 🔴 NO-SOURCE(start_run_tx)';
    else
      v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
      if (v_src ~ 'raise\s+exception\s+''run_ended''') is not true
        then v_bad := v_bad || ' 🔴 run_ended raise가 본문에 없다'; end if;
      if (v_src ~ 'if\s+b\.run_ended_at\s+is\s+not\s+null\s+then\s+raise\s+exception\s+''run_ended''') is not true
        then v_bad := v_bad || ' 🔴 run_ended_at 조건절이 raise에 붙어 있지 않다'; end if;
      v_p_party  := position('not_run_runner' in v_src);
      v_p_gate   := position('b.run_ended_at is not null' in v_src);
      v_p_repair := position('insert into runs' in v_src);
      v_p_unch   := position('''unchanged'', true' in v_src);
      if (v_p_party > 0 and v_p_repair > 0 and v_p_unch > 0) is not true
        then v_bad := v_bad || ' 🔴 0087 형상 소실 (당사자 게이트/복구 insert/unchanged 반환 중 하나가 없다)'; end if;
      if (v_p_gate > 0) is not true then v_bad := v_bad || ' 🔴 종료 조건절이 없다'; end if;
      if (v_p_gate > 0 and v_p_party > 0 and v_p_gate > v_p_party) is not true
        then v_bad := v_bad || ' 🔴 종료 검사가 당사자 게이트보다 앞이다'; end if;
      if (v_p_gate > 0 and v_p_repair > 0 and v_p_unch > 0 and v_p_gate < v_p_repair and v_p_gate < v_p_unch) is not true
        then v_bad := v_bad || ' 🔴 종료 검사가 복구/unchanged 반환보다 뒤다'; end if;
      -- 0087's own load-bearing shape survived the copy (123 S1/S6 pin the behaviour; this is the text)
      if (v_src ~ 'on conflict \(booking_id\) do update set started_at = excluded\.started_at') is not true
        then v_bad := v_bad || ' 0087 클레임 경로의 덮어쓰기가 사라졌다'; end if;
      if (v_src ~ 'coalesce\(runs\.started_at, excluded\.started_at\)') is not true
        then v_bad := v_bad || ' 0087 복구 경로의 coalesce가 사라졌다'; end if;
      if (v_src ~ 'where id = p_booking and status = ''picked_up''') is not true
        then v_bad := v_bad || ' 0087 원자 클레임이 사라졌다'; end if;
    end if;
    if v_bad = ''
      then call _pass('sreg','0240-S7 배포 소스(주석 제거) — run_ended raise와 조건절이 있고, 당사자 게이트 뒤·복구 insert와 unchanged 반환 앞에 선다; 0087의 덮어쓰기·coalesce·원자 클레임 보존; NO-SOURCE는 빨강');
    else v_msg := v_bad; call _fail('sreg','0240-S7 배포 소스', v_msg); end if;
  exception when others then
    v_msg := sqlerrm; call _fail('sreg','0240-S7 배포 소스', v_msg);
  end;
end $$;
