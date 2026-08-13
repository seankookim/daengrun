-- ═══ 121 cancel-share suite — 0085 pins (⑩ the 10% tier's runner half) ═══
-- Purpose: 0066 charges an owner 10% for cancelling a confirmed booking inside 24h, and the
--   owner is told — in the pre-commit cancel sheet, app/app/owner/schedule.tsx:604 — that the
--   fee is "시간을 비워둔 러너에게 50%, 도그스하이에 50% 배분". Until 0085 nothing paid that
--   half. These pins hold the sentence true: the amount, the recipient, the ledger SHAPE (the
--   one that decides whether the runner is actually paid), idempotence, and every arm that must
--   write nothing.
-- Style: sibling of 105-120 — `_pass('cs',…)`/`_fail('cs',…)`, one begin…exception per case.
--   ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
--   Money facts are asserted against LITERALS, never recomputed with the function's own
--   expression (105's law) — otherwise the pin agrees with whatever the function does.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   S1 ← 0085: change the 0.5 literal (the owner was shown 50% before they confirmed), or
--        drop the `round(...)::int`                                                      → RED
--   S2 ← 0085: move the share out of `remaining_guarantee`, or record the platform's half
--        in `platform_fee`. THE pin of this suite: my_ledger_total (0027:13) SUBTRACTS
--        platform_fee, so a 50/50 written as remaining_guarantee=X, platform_fee=X nets the
--        runner to ZERO while every row-count and amount assertion still passes         → RED
--   S3 ← 0085: drop the `exists (select 1 from ledger_items …)` guard — a retried cancel
--        then pays twice                                                                → RED
--   S4 ← 0085: loosen the `cancel_reason = 'owner_cancel_late'` gate (e.g. accept any
--        cancelled_owner row) — the en-route tier would then be paid twice, once at 100%
--        by 0080 and once at 50% here                                                   → RED
--   S5 ← 0085: pay on a free tier (fee 0 / unmatched / ≥24h) instead of returning 0,false → RED
--   S6 ← 0085: drop the shared 'comp:' advisory-lock key, or the grant/revoke lines      → RED
do $$
declare
  oo uuid; rr uuid; dg uuid; rt uuid;
  v_bad text := ''; v_msg text; v_n int;
  m record; m2 record;
  b_late uuid; b_enr uuid; b_free uuid; b_nr uuid;
  v_share int; v_net bigint; v_missing text;
begin
  -- ---------- seed ----------
  -- t_user/t_dog/t_route come from 10_settle_suite; t_chg_bk from 116 (both already applied
  -- when this suite runs — harness.sh:70-109 fixes the order).
  oo := t_user('cs_oo', 'owner');
  rr := t_user('cs_rr', 'runner');
  dg := t_dog(oo, '취소견'); rt := t_route('취소 코스');

  -- A 3km booking priced 7,900 + 9,000 = 16,900. 0066's <24h tier = 10% = 1,690.
  -- Half of that, the runner's, is 845. Every number below is that literal chain, written
  -- out rather than recomputed.
  b_late := t_chg_bk(oo, dg, rt, rr, 'cancelled_owner', now() + interval '3 hours', 3.0, 7900, 9000, 0);
  update bookings set cancel_fee = 1690, cancel_reason = 'owner_cancel_late' where id = b_late;

  -- ---------- [S1] the amount, and it is written ----------
  begin
    select * into m from record_late_cancel_share(b_late);
    if not m.written or m.comp <> 845 then
      v_bad := v_bad || ' 1회차=' || coalesce(m.comp::text, 'null') || '/' || coalesce(m.written::text, 'null');
    end if;
    select count(*) into v_n from ledger_items where booking_id = b_late;
    if v_n <> 1 then v_bad := v_bad || ' 원장 행수=' || v_n; end if;
    if (select li.runner_id from ledger_items li where li.booking_id = b_late) <> rr then
      v_bad := v_bad || ' 수취인이 그 러너가 아니다';
    end if;
    if v_bad = '' then
      call _pass('cs','S1 10% 티어 러너 배분 — 수수료 1,690의 절반 845가 그 러너의 원장에 1행');
    else v_msg := v_bad; call _fail('cs','S1 10% 티어 러너 배분', v_msg); end if;
  exception when others then call _fail('cs','S1 10% 티어 러너 배분', sqlerrm); end;

  -- ---------- [S2] the ledger SHAPE — the pin that decides whether the runner is paid ----------
  -- A 50/50 split invites `remaining_guarantee = 845, platform_fee = 845`, which reads as honest
  -- double entry and pays the runner NOTHING: my_ledger_total sums
  -- base+distance+addon+tip+remaining_guarantee-platform_fee. So this asserts the shape AND the
  -- net the runner actually sees. The platform's half never enters the runner's ledger.
  begin
    v_bad := '';
    if exists (select 1 from ledger_items li where li.booking_id = b_late
               and (li.remaining_guarantee <> 845 or li.platform_fee <> 0
                    or li.base <> 0 or li.distance_pay <> 0 or li.addon_pay <> 0 or li.tip <> 0))
    then v_bad := v_bad || ' 원장 형상 불일치 (보상 845·수수료 0이어야 한다)'; end if;
    select coalesce(sum(base + distance_pay + addon_pay + tip
                        + coalesce(remaining_guarantee, 0) - platform_fee), 0)
      into v_net from ledger_items where runner_id = rr;
    if v_net <> 845 then v_bad := v_bad || ' 러너 실수령 net=' || v_net || ' (845여야 한다)'; end if;
    if v_bad = '' then
      call _pass('cs','S2 원장 형상 — 보상은 remaining_guarantee, platform_fee 0, 러너 net 845 (플랫폼 몫은 러너 장부에 들어가지 않는다)');
    else v_msg := v_bad; call _fail('cs','S2 원장 형상', v_msg); end if;
  exception when others then call _fail('cs','S2 원장 형상', sqlerrm); end;

  -- ---------- [S3] idempotence — a retried cancel must not pay twice ----------
  begin
    v_bad := '';
    select * into m2 from record_late_cancel_share(b_late);
    select count(*) into v_n from ledger_items where booking_id = b_late;
    if m2.written or v_n <> 1 then
      v_bad := v_bad || ' 2회차=' || coalesce(m2.written::text,'null') || ' 행수=' || v_n;
    end if;
    -- the idempotency arm still REPORTS the amount, because the caller's copy names it and the
    -- row does exist (cancel_owner.ts treats comp>0 as "sentence is true")
    if m2.comp <> 845 then v_bad := v_bad || ' 재호출 보고액=' || m2.comp || ' (845를 그대로 보고해야 한다)'; end if;
    if v_bad = '' then
      call _pass('cs','S3 멱등 — 재호출은 쓰지 않고, 이미 있는 금액 845를 그대로 보고');
    else v_msg := v_bad; call _fail('cs','S3 멱등', v_msg); end if;
  exception when others then call _fail('cs','S3 멱등', sqlerrm); end;

  -- ---------- [S4] the en-route tier is NOT this function's ----------
  -- Without the reason gate the 50% tier would be paid twice: 100% by 0080's comp and another
  -- 50% here. The shared 'comp:' lock means whichever ran first also blocks the other via the
  -- existence check — this pin holds the gate that makes that a belt on top of braces.
  begin
    v_bad := '';
    b_enr := t_chg_bk(oo, dg, rt, rr, 'cancelled_owner', now() + interval '1 hour', 3.0, 7900, 9000, 0);
    update bookings set cancel_fee = 8450, cancel_reason = 'owner_cancel_enroute' where id = b_enr;
    select * into m from record_late_cancel_share(b_enr);
    select count(*) into v_n from ledger_items where booking_id = b_enr;
    if m.written or m.comp <> 0 or v_n <> 0 then
      v_bad := v_bad || ' 인루트건에 기록=' || coalesce(m.written::text,'null') || ' 금액=' || m.comp || ' 행수=' || v_n;
    end if;
    if v_bad = '' then
      call _pass('cs','S4 인루트 티어는 이 함수의 것이 아니다 — 0085는 쓰지 않는다 (0080이 전액 지급)');
    else v_msg := v_bad; call _fail('cs','S4 인루트 티어 배제', v_msg); end if;
  exception when others then call _fail('cs','S4 인루트 티어 배제', sqlerrm); end;

  -- ---------- [S5] every free arm writes nothing ----------
  begin
    v_bad := '';
    -- fee 0 with the marker (a ≥24h cancel that somehow carried it) — pays nothing
    b_free := t_chg_bk(oo, dg, rt, rr, 'cancelled_owner', now() + interval '48 hours', 3.0, 7900, 9000, 0);
    update bookings set cancel_fee = 0, cancel_reason = 'owner_cancel_late' where id = b_free;
    select * into m from record_late_cancel_share(b_free);
    select count(*) into v_n from ledger_items where booking_id = b_free;
    if m.written or m.comp <> 0 or v_n <> 0 then
      v_bad := v_bad || ' 무료취소에 기록=' || coalesce(m.written::text,'null') || ' 행수=' || v_n;
    end if;
    -- no runner (unmatched) — nobody to pay
    b_nr := t_chg_bk(oo, dg, rt, NULL, 'cancelled_owner', now() + interval '3 hours', 3.0, 7900, 9000, 0);
    update bookings set cancel_fee = 1690, cancel_reason = 'owner_cancel_late' where id = b_nr;
    select * into m2 from record_late_cancel_share(b_nr);
    select count(*) into v_n from ledger_items where booking_id = b_nr;
    if m2.written or v_n <> 0 then
      v_bad := v_bad || ' 러너없음에 기록=' || coalesce(m2.written::text,'null') || ' 행수=' || v_n;
    end if;
    if v_bad = '' then
      call _pass('cs','S5 지급 없는 팔 — 수수료 0·러너 없음은 무기록 (0,false)');
    else v_msg := v_bad; call _fail('cs','S5 지급 없는 팔', v_msg); end if;
  exception when others then call _fail('cs','S5 지급 없는 팔', sqlerrm); end;

  -- ---------- [S6] the seal — grants, and the shared lock key ----------
  -- Same shape as 116 C21's grant matrix: a definer that authenticated can execute is a
  -- self-serve payout. Also asserts the function reaches for the SAME 'comp:' key space 0080
  -- uses — the source-level fact that makes the two comp writers mutually exclusive.
  begin
    v_bad := ''; v_missing := '';
    if has_function_privilege('authenticated', 'record_late_cancel_share(uuid)', 'execute')
       or has_function_privilege('anon', 'record_late_cancel_share(uuid)', 'execute')
    then v_bad := v_bad || ' 클라이언트가 실행 가능 (definer 지급 함수)'; end if;
    if not has_function_privilege('service_role', 'record_late_cancel_share(uuid)', 'execute')
    then v_bad := v_bad || ' service_role이 실행 불가'; end if;
    select p.prosrc into v_missing from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where p.proname = 'record_late_cancel_share' and n.nspname = 'public';
    if v_missing is null or position('comp:' in v_missing) = 0 then
      v_bad := v_bad || ' 0080과 같은 comp: 자문 락 키를 쓰지 않는다';
    end if;
    if position('pg_advisory_xact_lock' in coalesce(v_missing,'')) = 0 then
      v_bad := v_bad || ' 자문 락이 없다';
    end if;
    if v_bad = '' then
      call _pass('cs','S6 봉인 — anon/authenticated 실행 불가·service_role 가능·0080과 동일한 comp: 자문 락');
    else v_msg := v_bad; call _fail('cs','S6 봉인', v_msg); end if;
  exception when others then call _fail('cs','S6 봉인', sqlerrm); end;

end $$;
