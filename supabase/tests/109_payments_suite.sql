-- ═══ 109 payments suite — 0071 + 0076 pins (the accounting artifact for money coming IN) ═══
-- Purpose: `payments` is the first table that will ever hold a record of a real charge. It is
--   empty today and stays empty until Sean's filings and TOSS_SECRET_KEY exist — so what these
--   pins protect is its SHAPE, before anything valuable is in it. That is the cheap moment.
--   P1-P6 pin 0071's table. **P7-P11 pin 0076's intent layer** — the `pending` vocabulary, the
--   nullable payment_key that pending requires, `profiles.toss_customer_key`, the stale-intent
--   sweep, and the reconciliation query that is the real consumer of `raw.needs_manual_cancel`.
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
--
-- ─── MUTATION map, 0076 half (same law: one named revert, one red pin) ───
--   P7  ← 0076 §A: drop `'pending'` from `payments_status_vocab` (the intent can no
--         longer be written at all — confirm-payment has nothing to complete)          → RED
--   P8  ← 0076 §A: drop `payments_settled_has_key`. Then a `confirmed` row with no
--         payment_key becomes legal = an approved charge we cannot cancel or refund
--         because we never recorded its handle. (The mirror revert — restoring
--         `payment_key not null` — makes P8's pending-insert probe red instead.)        → RED
--   P9  ← 0076 §B: drop `profiles_toss_customer_key_uidx`, or make the column default
--         to `id` (two profiles share a Toss customerKey / our internal id leaks
--         into the PG's records — the exact thing Toss's FAQ forbids)                   → RED
--   P10 ← 0076 §D: drop `payments_reconciliation()`, narrow its orphan predicate, or
--         grant execute back to authenticated (the marker's only reader disappears,
--         or the payer's card metadata becomes readable through a definer function)     → RED
--   P11 ← 0076 §C: widen `sweep_stale_payment_intents()` to also close pendings that
--         carry a payment_key. That row may have been captured; closing it `failed`
--         erases from our ledger the fact that money left someone's card.               → RED
--   ✔ MUTATION-PROVEN by full-harness runs on 2026-08-12 (restore → 384/0 every time):
--       P8  → 383/1, red = [P8]          P9  → 383/1, red = [P9]
--       P10 → 383/1, red = [P10]         P11 → 383/1, red = [P11]
--     P7 CASCADES, and the cascade is correct rather than sloppy — say it plainly:
--       P7 (no 'pending' in the vocabulary) → 381/3, red = [P7, P8, P11]
--     With `pending` gone, an intent row cannot be written at all, so P8's "two NULL
--     payment_keys coexist" probe and P11's whole fixture have nothing to stand on.
--     Every one of those three is genuinely broken by that revert — none is a false alarm.
--     ⚠ P11 originally aged P8's probe row and therefore went red under P8's revert too.
--     That was a false alarm (P8's revert lets its own `canceled` probe land, which moved
--     the row out of the sweep's predicate), so P11 was retightened to mint its own row —
--     the same correction P4 received in 0071. A pin must measure its own claim.
set client_min_messages = warning;

do $$
declare
  oo uuid; oz uuid; rr uuid; dg uuid; rt uuid; bk uuid; bk2 uuid;
  v_bad text := ''; v_n int; v_err boolean; v_pid uuid; b_ok uuid; b_no uuid; v_msg text;
  v_pend uuid; v_kept uuid; v_orphan uuid; b_orph uuid; v_swept int; v_key uuid;
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

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- 0076 — 결제 인텐트 (돈이 움직이기 전에 서버가 먼저 적는다)
  -- ══════════════════════════════════════════════════════════════════════════════════════

  -- ---------- [P7] 상태 어휘에 'pending'이 합류했다 — 그리고 여전히 아무거나는 아니다 ----------
  -- 이 한 줄이 0076 전체의 전제다: pending 행을 쓸 수 없으면 confirm-payment는 완성할 인텐트가
  -- 없고, 캡처와 INSERT 사이의 크래시 창이 그대로 되돌아온다.
  begin
    v_bad := '';
    begin
      insert into payments (booking_id, order_id, amount, status)
      values (bk2, 'ord_intent_1', 24900, 'pending') returning id into v_pend;
    exception when others then v_bad := v_bad || ' pending:거부됨(' || sqlerrm || ')';
    end;
    -- 어휘가 넓어졌다고 열린 것은 아니다 — 오타는 여전히 거부돼야 한다
    begin
      insert into payments (booking_id, order_id, amount, status)
      values (bk2, 'ord_garbage', 100, 'pendign');
      v_bad := v_bad || ' 오타:통과';
    exception when check_violation then null;
    end;
    begin
      insert into payments (booking_id, order_id, amount, status)
      values (bk2, 'ord_garbage2', 100, 'authorized');   -- 그럴듯하지만 우리 어휘가 아니다
      v_bad := v_bad || ' authorized:통과';
    exception when check_violation then null;
    end;
    if v_bad = '' and v_pend is not null
      then call _pass('pay','P7 인텐트 어휘 — pending 수용·오타/유사어 거부 (0076 §A)');
    else call _fail('pay','P7 상태 어휘', coalesce(nullif(v_bad,''),'pending 행이 안 생겼다')); end if;
  exception when others then call _fail('pay','P7', sqlerrm);
  end;

  -- ---------- [P8] payment_key: pending은 없이 살고, 결제된 행은 반드시 들고 있다 ----------
  -- not null을 푼 것은 인텐트를 위해서지 느슨해지려고가 아니다. 대가를 두 방향으로 되받는다:
  --   ① NULL 여러 개는 공존한다 (안 그러면 두 번째 인텐트를 만들 수 없다)
  --   ② confirmed/canceled에 키가 없는 것은 금지 — 승인받았다면서 그 증거를 못 대는 행은
  --      취소도 환불도 못 하는 행이다 (payments_settled_has_key)
  --   ③ 진짜 중복 키는 0071 때와 똑같이 거부된다 (P4의 주장이 nullable 아래서도 산다)
  begin
    v_bad := '';
    begin
      insert into payments (booking_id, order_id, amount, status)
      values (bk2, 'ord_intent_2', 24900, 'pending');    -- 두 번째 NULL payment_key
    exception when others then v_bad := v_bad || ' 두번째NULL:거부됨(' || sqlerrm || ')';
    end;
    begin
      insert into payments (booking_id, payment_key, order_id, amount, status)
      values (bk2, null, 'ord_keyless_confirm', 24900, 'confirmed');
      v_bad := v_bad || ' 키없는confirmed:통과';
    exception when check_violation then null;
    end;
    begin
      update payments set status = 'canceled' where id = v_pend;   -- 키 없이 취소로 승격
      v_bad := v_bad || ' 키없는canceled:통과';
    exception when check_violation then null;
    end;
    begin
      insert into payments (booking_id, payment_key, order_id, amount, status)
      values (bk2, 'tviva_probe_key_1', 'ord_dupe_key', 24900, 'confirmed');
      v_bad := v_bad || ' 중복키:통과';
    exception when unique_violation then null;
    end;
    if v_bad = '' and (select status from payments where id = v_pend) = 'pending'
      then call _pass('pay','P8 payment_key — NULL 공존(인텐트)·키 없는 확정 금지·중복 키 여전히 거부');
    else call _fail('pay','P8 payment_key', coalesce(nullif(v_bad,''),'pending 행 상태가 바뀌었다')); end if;
  exception when others then call _fail('pay','P8', sqlerrm);
  end;

  -- ---------- [P9] toss_customer_key — 프로필당 하나, 그리고 id가 아니다 ----------
  -- id를 그대로 쓰면(또는 id에서 유도하면) 우리 내부 식별자가 외부 PG의 로그에 영구히 박힌다.
  -- unique가 없으면 두 사람이 같은 customerKey를 갖고, Toss가 기억한 결제수단이 섞인다.
  begin
    v_bad := '';
    if not exists (select 1 from information_schema.columns
                   where table_name = 'profiles' and column_name = 'toss_customer_key'
                     and is_nullable = 'NO')
      then v_bad := v_bad || ' 컬럼:없거나 nullable'; end if;
    if not exists (select 1 from pg_indexes
                   where tablename = 'profiles' and indexname = 'profiles_toss_customer_key_uidx')
      then v_bad := v_bad || ' unique인덱스:없음'; end if;
    select count(*) into v_n from profiles where toss_customer_key = id;
    if v_n > 0 then v_bad := v_bad || ' id와 동일:' || v_n || '건'; end if;
    select count(*) into v_n from profiles;
    if (select count(distinct toss_customer_key) from profiles) <> v_n
      then v_bad := v_bad || ' 중복 customer_key 존재'; end if;
    -- 실제로도 거부하는지 — 스키마 조회만 믿지 않는다 (68 V1의 교훈: 형태 검사는 통과하고 동작은 열린다)
    select toss_customer_key into v_key from profiles where id = oo;
    begin
      update profiles set toss_customer_key = v_key where id = oz;
      v_bad := v_bad || ' 중복 대입:통과';
    exception when unique_violation then null;
    end;
    if v_bad = '' then call _pass('pay','P9 toss_customer_key — not null·프로필당 유일·profiles.id와 무관 (0076 §B)');
    else call _fail('pay','P9 customer_key', v_bad); end if;
  exception when others then call _fail('pay','P9', sqlerrm);
  end;

  -- ---------- [P10] 조정 질의 — 마커의 실제 소비자가 존재하고, 봉인돼 있고, 실제로 잡는다 ----------
  -- toss-plan §2-7: 자동 취소마저 실패하면 행은 confirmed로 남고 raw.needs_manual_cancel이 찍힌다.
  -- 그 마커를 읽는 주체가 없으면 그건 사고 기록이 아니라 사고 은폐다. 세 가지를 본다:
  --   ① 깨끗한 픽스처에서 0행 (거짓 양성으로 매일 울리는 질의는 곧 무시된다)
  --   ② 진짜 고아 캡처를 실제로 집는다 (돈은 받았는데 부킹이 앞으로 못 간 행)
  --   ③ anon·authenticated는 실행할 수 없다 (definer 함수는 payments의 RLS를 우회한다 —
  --      권한을 안 잠그면 이 함수 하나가 P2·P3를 통째로 무효화한다)
  begin
    v_bad := '';
    if to_regprocedure('payments_reconciliation()') is null then
      call _fail('pay','P10 조정 질의','payments_reconciliation()가 없다 — 마커의 소비자가 없다');
    else
      if has_function_privilege('authenticated', 'payments_reconciliation()', 'execute')
        then v_bad := v_bad || ' authenticated:실행가능'; end if;
      if has_function_privilege('anon', 'payments_reconciliation()', 'execute')
        then v_bad := v_bad || ' anon:실행가능'; end if;
      select count(*) into v_n from payments_reconciliation();
      if v_n <> 0 then v_bad := v_bad || ' 깨끗한 픽스처에서 ' || v_n || '행'; end if;

      -- 고아 캡처를 하나 만든다: 결제는 confirmed인데 부킹은 payment_hold에 남아 있다
      -- (= CAS 0행 이후 자동 취소까지 실패한 그 행)
      b_orph := t_av_booking(oo, dg, rt, null, now() + interval '13 hours', 5.0, 'payment_hold');
      insert into payments (booking_id, payment_key, order_id, amount, status, raw)
      values (b_orph, 'tviva_orphan', 'ord_orphan', 24900, 'confirmed',
              jsonb_build_object('needs_manual_cancel', true, 'auto_cancel_reason', 'hold_expired'))
      returning id into v_orphan;
      if not exists (select 1 from payments_reconciliation()
                     where kind = 'orphan_capture' and payment_id = v_orphan and needs_manual_cancel)
        then v_bad := v_bad || ' 고아 캡처:안 잡힘'; end if;
      delete from payments where id = v_orphan;

      if v_bad = ''
        then call _pass('pay','P10 조정 질의 — 깨끗하면 0행·고아 캡처는 집어냄·anon/authenticated 실행 불가 (0076 §D)');
      else call _fail('pay','P10 조정 질의', v_bad); end if;
    end if;
  exception when others then call _fail('pay','P10', sqlerrm);
  end;

  -- ---------- [P11] 좌초 인텐트 스윕 — 잔해는 치우고, 돈이 걸린 행은 건드리지 않는다 ----------
  -- 위젯 도중 앱이 죽으면 pending이 남는다. 그건 치워야 할 잔해다.
  -- 하지만 payment_key가 붙은 pending은 **캡처가 일어났을 수도 있는 행**이고, 그걸 failed로
  -- 닫는 것은 돈이 나간 사실을 우리 장부에서 지우는 것이다. 스윕의 침묵이 여기서는 정확함이다.
  begin
    v_bad := '';
    -- 자기 행을 새로 만든다 — P8이 만졌던 v_pend를 재활용하면 P8을 되돌렸을 때 P11이 덩달아
    -- 빨개진다 (P4가 전체 행 수를 세다가 같은 이유로 재조정된 그 교훈). 각 핀은 자기 주장만 잰다.
    insert into payments (booking_id, order_id, amount, status, created_at)
    values (bk2, 'ord_stale_intent', 24900, 'pending', now() - interval '2 hours')
    returning id into v_pend;
    insert into payments (booking_id, payment_key, order_id, amount, status, created_at)
    values (bk2, 'tviva_captured_pending', 'ord_captured', 24900, 'pending', now() - interval '2 hours')
    returning id into v_kept;
    -- 방금 만든 인텐트(1시간 미만)는 살아 있어야 한다 — 결제 화면에 사람이 앉아 있을 수 있다
    insert into payments (booking_id, order_id, amount, status)
    values (bk2, 'ord_fresh_intent', 24900, 'pending');

    select sweep_stale_payment_intents() into v_swept;

    if (select status from payments where id = v_pend) <> 'failed'
      then v_bad := v_bad || ' 늙은 키없는 pending:안 닫힘'; end if;
    if (select status from payments where id = v_kept) <> 'pending'
      then v_bad := v_bad || ' 캡처 가능성 있는 pending:닫힘(장부 왜곡)'; end if;
    if (select status from payments where order_id = 'ord_fresh_intent') <> 'pending'
      then v_bad := v_bad || ' 새 인텐트:조기 종료'; end if;
    if v_swept <> 1 then v_bad := v_bad || ' 반환값=' || v_swept || ' (1이어야 한다)'; end if;
    if has_function_privilege('authenticated', 'sweep_stale_payment_intents()', 'execute')
      then v_bad := v_bad || ' authenticated:실행가능'; end if;

    -- 프로브 잔해 회수 — 다음 스위트가 조정 질의를 읽을 때 우리 흔적이 노이즈가 되지 않게
    delete from payments where order_id in
      ('ord_intent_1','ord_intent_2','ord_stale_intent','ord_captured','ord_fresh_intent');

    if v_bad = ''
      then call _pass('pay','P11 좌초 인텐트 스윕 — 키 없는 1시간+만 failed·캡처 가능 행 보존·새 인텐트 생존 (0076 §C)');
    else call _fail('pay','P11 스윕', v_bad); end if;
  exception when others then call _fail('pay','P11', sqlerrm);
  end;
end $$;
