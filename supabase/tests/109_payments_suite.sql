-- ═══ 109 payments suite — 0071 pins (the accounting artifact for money coming IN) ═══
-- Purpose: `payments` is the first table that will ever hold a record of a real charge. It is
--   empty today and stays empty until Sean's filings and TOSS_SECRET_KEY exist — so what these
--   pins protect is its SHAPE, before anything valuable is in it. That is the cheap moment.
-- Style: sibling of 105-108 — `_pass('pay',…)`/`_fail('pay',…)`, one begin…exception per case.
--   Write attempts run under `set local role authenticated` (68 V1's idiom): the shim grants
--   authenticated full table DML by default exactly like Supabase does, so a seal that is only a
--   missing grant would pass a naive test and fail in production. RLS is what must refuse.
--
-- ⚠ This table is NOT in 68 V1's sealed array and must not be added to it. That pin asserts
--   **policy count = 0**; `payments` deliberately carries one (the owner reads their own receipt).
--   P3 below pins the exact shape instead — one policy, SELECT-only — which is strictly stronger
--   than membership in that array would have been.
--
-- ─── MUTATION map — each pin goes RED under exactly one revert (house law) ───
--   P1 ← 0071: drop `alter table payments enable row level security`               → RED
--   P2 ← 0071: widen the policy's `using` to `true` (any signed-in user reads
--        every payment row in the system)                                          → RED
--   P3 ← 0071: add any INSERT/UPDATE/DELETE policy — e.g. `for all using (true)`   → RED
--   P4 ← 0071: drop `unique` from payment_key (a repeated confirm becomes a
--        second charge record instead of a rejected duplicate)                     → RED
--   P5 ← 0071: drop the `payments_refund_within_amount` check, or the
--        `amount >= 0` check                                                       → RED
--   P6 ← 0066/0001: this pin holds the surrounding map — `payment_hold → matching`
--        must stay legal and unaccompanied by new edges (105 E7 idiom). Toss lands
--        inside the existing hold window, so the map must NOT need changing.       → RED
--   ✔ MUTATION-PROVEN by full-harness runs on 2026-08-11 (restore → 330/0 every time):
--       P4 → 329/1, red = [P4]        P5 → 329/1, red = [P5]
--     P1/P2/P3 CASCADE, and the cascade is correct rather than sloppy — say it plainly:
--       P1 (RLS off)        → 325/5, red = [P1, P2, P3, P4, P5]
--       P2 (policy → true)  → 328/2, red = [P1, P2]
--       P3 (write policy)   → 327/3, red = [P1, P2, P3]
--     A `using (true)` policy leaks to anon as well, so P1's "anon sees 0 rows" is genuinely
--     violated by P2's and P3's reverts; and with RLS off the client writes in P3 actually land,
--     which is why P1 also disturbs P4/P5. Every one of those pins is really broken by that
--     revert — none is a false alarm. P4 was nonetheless retightened afterwards to count only
--     its own duplicate keys instead of the whole table, so it measures its own claim and not
--     the suite's accumulated state.
--     P6 was not machine-proven (the probe would have to reimplement enforce_booking_transition);
--     it follows 105 E7's already-proven shape.
set client_min_messages = warning;

do $$
declare
  oo uuid; oz uuid; rr uuid; dg uuid; rt uuid; bk uuid; bk2 uuid;
  v_bad text := ''; v_n int; v_err boolean; v_pid uuid; b_ok uuid; b_no uuid; v_msg text;
begin
  -- ---------- seed ----------
  oo := t_user('pay_oo', 'owner'); oz := t_user('pay_oz', 'owner');
  rr := t_user('pay_rr', 'runner');
  dg := t_dog(oo, '결제견'); rt := t_route('결제 코스');
  bk := t_av_booking(oo, dg, rt, rr, now() + interval '3 hours', 5.0, 'confirmed');
  bk2 := t_av_booking(oo, dg, rt, rr, now() + interval '5 hours', 5.0, 'confirmed');
  -- service_role이 쓰는 경로를 모사 (엣지 함수 = confirm-payment). postgres 세션은 RLS를 우회한다.
  insert into payments (booking_id, payment_key, order_id, amount, status, raw)
  values (bk, 'tviva_probe_key_1', 'ord_probe_1', 24900, 'confirmed',
          jsonb_build_object('method', '카드', 'approvedAt', now()))
  returning id into v_pid;

  -- ---------- [P1] RLS가 켜져 있다 + 익명은 0행 ----------
  begin
    if not exists (select 1 from pg_class where relname = 'payments' and relrowsecurity)
      then call _fail('pay','P1 RLS','payments에 RLS가 꺼져 있다'); else
      set local role anon;
      perform set_config('request.jwt.claim.sub', '', true);
      select count(*) into v_n from payments;
      reset role;
      if v_n = 0 then call _pass('pay','P1 RLS 켜짐 + 익명 0행 — 결제 기록은 비로그인에 보이지 않는다');
      else call _fail('pay','P1 익명 누수','n=' || v_n); end if;
    end if;
  exception when others then reset role; call _fail('pay','P1', sqlerrm);
  end;

  -- ---------- [P2] 보호자는 자기 행만, 무관자는 0행 ----------
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', oo::text, true);
    select count(*) into v_n from payments;
    reset role;
    if v_n <> 1 then call _fail('pay','P2 보호자 읽기','자기 결제가 안 보인다 n=' || v_n); else
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', oz::text, true);
      select count(*) into v_n from payments;
      reset role;
      if v_n <> 0 then call _fail('pay','P2 타인 누수','무관 보호자에게 n=' || v_n); else
        -- 러너는 의도적으로 독자가 아니다 — raw가 결제자의 카드 메타를 담는다
        set local role authenticated;
        perform set_config('request.jwt.claim.sub', rr::text, true);
        select count(*) into v_n from payments;
        reset role;
        if v_n = 0
          then call _pass('pay','P2 등급 — 보호자 자기 행만·타 보호자 0·담당 러너도 0 (raw는 결제자의 것)');
        else call _fail('pay','P2 러너 누수','n=' || v_n); end if;
      end if;
    end if;
  exception when others then reset role; call _fail('pay','P2', sqlerrm);
  end;

  -- ---------- [P3] 클라이언트는 쓸 수 없다 — 본인 것도 (정책은 SELECT 하나뿐) ----------
  -- 68 V1의 교훈: 읽기만 검사하면 쓰기가 열린 채로 초록이 된다. insert·update·delete 전부 본다.
  begin
    if (select count(*) from pg_policies where tablename = 'payments') <> 1
      then
      select 'SELECT 정책 하나만 있어야 한다 — n=' || count(*)::text into v_msg
      from pg_policies where tablename = 'payments';
      call _fail('pay','P3 정책 수', coalesce(v_msg,'∅')); else
      if exists (select 1 from pg_policies where tablename = 'payments' and cmd <> 'SELECT')
        then call _fail('pay','P3 정책 종류','SELECT 아닌 정책이 있다'); else
        v_err := false;
        begin
          set local role authenticated;
          perform set_config('request.jwt.claim.sub', oo::text, true);
          insert into payments (booking_id, payment_key, order_id, amount, status)
          values (bk2, 'client_forged_key', 'ord_forged', 1, 'confirmed');
          reset role;
        exception when others then v_err := true; reset role;
        end;
        reset role;
        if not v_err then v_bad := v_bad || ' insert:통과'; end if;
        begin
          set local role authenticated;
          perform set_config('request.jwt.claim.sub', oo::text, true);
          update payments set amount = 1, refunded_amount = 24900 where id = v_pid;
          if found then v_bad := v_bad || ' update:행변경'; end if;
          reset role;
        exception when others then reset role;
        end;
        reset role;
        begin
          set local role authenticated;
          perform set_config('request.jwt.claim.sub', oo::text, true);
          delete from payments where id = v_pid;
          if found then v_bad := v_bad || ' delete:행삭제'; end if;
          reset role;
        exception when others then reset role;
        end;
        reset role;
        if v_bad = '' and (select amount from payments where id = v_pid) = 24900
          then call _pass('pay','P3 클라 무쓰기 — 정책은 SELECT 하나뿐, 본인 행도 insert/update/delete 불가');
        else call _fail('pay','P3 쓰기 누수', coalesce(nullif(v_bad,''),'금액 변조됨')); end if;
      end if;
    end if;
  exception when others then reset role; call _fail('pay','P3', sqlerrm);
  end;

  -- ---------- [P4] 같은 payment_key 두 번 = 두 번째 청구 기록이 아니라 거부 ----------
  -- confirm 재호출(네트워크 재시도·유저 더블탭)이 매출을 두 번 적으면 안 된다.
  begin
    v_err := false;
    begin
      insert into payments (booking_id, payment_key, order_id, amount, status)
      values (bk2, 'tviva_probe_key_1', 'ord_probe_2', 24900, 'confirmed');
    exception when unique_violation then v_err := true;
    end;
    if not v_err then call _fail('pay','P4 멱등','같은 payment_key가 두 번 들어갔다'); else
      -- order_id도 우리 쪽 멱등이다
      v_err := false;
      begin
        insert into payments (booking_id, payment_key, order_id, amount, status)
        values (bk2, 'tviva_probe_key_2', 'ord_probe_1', 24900, 'confirmed');
      exception when unique_violation then v_err := true;
      end;
      -- 자기 주장만 측정한다: 전체 행 수를 세면 다른 핀이 깨졌을 때 덩달아 빨개진다
      if v_err
         and (select count(*) from payments where payment_key = 'tviva_probe_key_1') = 1
         and (select count(*) from payments where order_id = 'ord_probe_1') = 1
        then call _pass('pay','P4 멱등 — payment_key(PG)·order_id(우리) 둘 다 중복 거부, 행은 1건 그대로');
      else call _fail('pay','P4 order_id','중복 order_id가 통과했다'); end if;
    end if;
  exception when others then call _fail('pay','P4', sqlerrm);
  end;

  -- ---------- [P5] 돈 컬럼의 산술 불변식 ----------
  begin
    v_bad := '';
    begin
      update payments set refunded_amount = 24901 where id = v_pid;   -- 결제액보다 큰 환불
      v_bad := v_bad || ' over-refund:통과';
    exception when check_violation then null;
    end;
    begin
      insert into payments (booking_id, payment_key, order_id, amount, status)
      values (bk2, 'tviva_neg', 'ord_neg', -1, 'confirmed');           -- 음수 결제
      v_bad := v_bad || ' negative:통과';
    exception when check_violation then null;
    end;
    begin
      insert into payments (booking_id, payment_key, order_id, amount, status)
      values (bk2, 'tviva_bad_status', 'ord_bad', 100, 'refund_pending');  -- 없는 상태
      v_bad := v_bad || ' bad-status:통과';
    exception when check_violation then null;
    end;
    if v_bad = '' and (select refunded_amount from payments where id = v_pid) = 0
      then call _pass('pay','P5 산술 불변식 — 환불 ≤ 결제액·음수 금액 거부·상태 어휘 고정');
    else call _fail('pay','P5 불변식', coalesce(nullif(v_bad,''),'refunded_amount 변경됨')); end if;
  exception when others then call _fail('pay','P5', sqlerrm);
  end;

  -- ---------- [P6] 전이 맵은 손대지 않는다 — Toss는 기존 홀드 창 안에서 끝난다 ----------
  -- 이 계획이 브리지보다 극적으로 작은 이유 전체가 이 한 줄이다: 새 상태도, 새 이넘도, 전이 맵
  -- 변경도 없다. 그 전제가 조용히 깨지면 여기서 터진다 (105 E7 관용구).
  begin
    v_bad := '';
    begin
      b_ok := t_av_booking(oo, dg, rt, null, now() + interval '9 hours', 5.0, 'payment_hold');
      update bookings set status = 'matching' where id = b_ok;
      if (select status::text from bookings where id = b_ok) <> 'matching'
        then v_bad := v_bad || ' hold→matching:미적용'; end if;
    exception when others then v_bad := v_bad || ' hold→matching:차단됨(' || sqlerrm || ')';
    end;
    begin
      b_no := t_av_booking(oo, dg, rt, null, now() + interval '11 hours', 5.0, 'payment_hold');
      update bookings set status = 'completed' where id = b_no;       -- 있어선 안 되는 지름길
      v_bad := v_bad || ' hold→completed:허용됨';
    exception when others then null;   -- 기대: invalid transition
    end;

    if v_bad = ''
      then call _pass('pay','P6 전이 맵 무변경 — payment_hold→matching 생존·지름길 없음 (새 상태 불필요의 근거)');
    else call _fail('pay','P6 전이 맵', v_bad); end if;
  exception when others then call _fail('pay','P6', sqlerrm);
  end;
end $$;
