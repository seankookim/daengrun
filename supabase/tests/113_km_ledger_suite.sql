-- ═══ 113 km-ledger suite — 0075 pins (km 원장, Sean 결정 D1/D2 2026-08-12) ═══
-- Purpose: the km ledger is the app's first stored-value system. What must hold is not
--   "the numbers add up" but the DECISIONS: paid never expires (schema), granted burns first,
--   the welcome grant books the run it advertises (D2), settlement never fails for funds,
--   and the tables are sealed the way `addresses` never was.
-- Style: sibling of 105-112 — `_pass('km',…)` / `_fail('km',…)`, one begin…exception per case.
--   ⚠ `_fail` arguments pre-computed into v_msg, never a subquery (110 header law).
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   K1  ← 0075: km_claim_welcome v_km := 3 (grant shrinks)                          → RED
--   K2  ← 0075: drop the exists guard in km_claim_welcome (double-mint)             → RED
--   K3  ← 0075: _km_consume order by (bucket='paid') DESC (paid burns first)        → RED
--   K4  ← 0075: drop the v_held>0 early return in km_reserve (re-reserve)           → RED
--   K5  ← 0075: drop the final `raise km_insufficient` in _km_consume               → RED
--   K6  ← 0075: km_settle v_charge := v_held (ignore actual)                        → RED
--   K7  ← 0075: drop the run_debit idempotency guard in km_settle                   → RED
--   K8  ← 0075: drop least(…, planned+2) clamp in km_settle (charge actual)         → RED
--   K9  ← 0075: drop greatest(floor,…) in km_settle (charge under 3km)              → RED
--   K10 ← 0075: _km_close_hold always mints a new granted lot (never returns to source) → RED
--        (⚠ an earlier header named the defunct `_km_return` here — the spec review caught it;
--         the executed mutation always patched the real function, only this name was stale)
--   K11 ← 0075: drop constraint km_lots_paid_never_expires                          → RED
--   K12 ← 0075: drop the ledger insert in km_expire_sweep (silent burn)             → RED
--   K13 ← 0075: drop the expires_at>now() filter in km_balance granted              → RED
--   K14 ← 0075: grant execute on km_grant to authenticated                          → RED
--   K15 ← 0075: km_reserve gate v_avail < b.km + 2 (strict buffer — the D2 revert)  → RED
--   K16 ← 0075: drop least(…, v_held) in km_settle charge (breaks charge≤hold)      → RED
--   K17 ← 0075: settle releases-then-consumes from current balance (the draft's
--         provenance-destroying shape, codex #6)                                    → RED
--   K18 ← 0075: expired-held return mints a fresh 30d lot (the draft's D-1
--         infinite-renewal machine, codex #7)                                       → RED
--   K19 ← 0075: drop trigger km_release_on_terminal_gate (spec-review I5 — a dead
--         booking strands its hold)                                                 → RED
--   K20 ← 0075: drop the `+ Σ(run_debit)` term from km_balance held (eng L1 — the
--         one netting site no pin watched; it is the number the screen renders)     → RED
--   K21 ← 0075: drop the km_already_settled guard in km_reserve                     → RED
--   K22 ← 0075: km_lots policy using(true) (eng H1 — the harness runs as table
--         owner, so policies had NEVER EXECUTED; K14's catalog reads stayed green)  → RED
--   K23 ← 0075: km_purchase omits its ledger row (mint outside the ledger)          → RED
--
--   🔎 Found by this suite BEFORE any mutation (baseline 371/1): the hold-netting in
--     reserve/settle/balance counted only booking_reserve−reserve_release, so a canceled
--     booking's hold looked open forever — stale idempotent returns, phantom held_km, and a
--     cancel⋈settle double-debit window. K16's fixture (cancel-then-rebook) caught it; the
--     fix is the two-term netting (−Σ(홀드·반환) + Σ(차감)) now in all three sites.
--   ⚠ UNPINNABLE, verified by inspection: the welcome cohort cap (500) — reddening it needs
--     500 seeded accounts, which the harness does not do. It is a **budget alarm**, not a hard
--     cap (check-then-insert can overshoot by concurrent claims — spec-review I11); the real
--     kill switch is `revoke execute on function km_claim_welcome() from authenticated`.
--   ⚠ UNPINNABLE single-connection: the `for update` booking mutex in reserve/settle/release
--     (spec-review I2 — two concurrent closers would double-return without it). A one-conn
--     suite cannot red a lock; the 2-conn race pin belongs to 90_race_check (test-plan GAP-1).
--
--   ✔ MUTATION-PROVEN by full-harness runs on 2026-08-12 (restore → 379/0). Measured, not
--     predicted — every line below is an observed run of the FINAL text (four cycles were run;
--     earlier cycles' results were discarded whenever a review changed the code under them):
--       MUT K4/K5/K7/K8/K9/K12/K13/K14/K16/K18/K19/K20/K21/K22/K23 → 378/1, clean singles
--       MUT K3  (spend order flipped)      → 377/2, red = [K3, K6]
--       MUT K11 (drop paid-never-expires)  → 377/2, red = [K11, K12]
--       MUT K1  (welcome 5→3)              → 375/4, red = [K1, K15, K3, K6]
--       MUT K2  (guard+index both dropped) → 375/4, red = [K2, K15, K3, K6]
--       MUT K6  (charge := held)           → 375/4, red = [K6, K7, K8, K17]
--       MUT K15 (strict D2 revert)         → 376/3, red = [K15, K16, K18]
--       MUT K17 (release-then-consume)     → 376/3, red = [K17, K23, K20]
--       MUT K10 (mint-new-lot returns)     → 373/6, red = [K10, K6, K12, K13, K17, K18]
--     The cascades are correct, not sloppy: K1/K2 reshape the granted balance every later pin
--     derives from; K6's charge:=held changes what K7 returns, what K8's synthetic sees, and
--     K17's charge assert; K15's strict gate starves K16/K18's tight-balance fixtures; K17's
--     draft shape is exactly the provenance/reconciliation failure K23 and K20 exist to watch;
--     K10's new-lot minting breaks expiry accounting (K12/K13) and grace (K18) wholesale.
--   🔎 Worth keeping from the cycles: MUT K8 round 1 was a MISS — the original K8 fixture
--     could not observe the planned+2 clamp because after D2, hold ≤ planned+2 makes the hold
--     clamp subsume it on every REACHABLE state. The pin only became real with a synthetic
--     over-hold the fixture writes by hand (111 N2's defense-in-depth lesson, remeasured here).
--   (a pin that has not been seen red is not yet a pin, 0059 doctrine)
--
--   K15 is the pin that carries Sean's D2 decision. The drafted strict gate demanded
--   balance ≥ planned+2, under which the welcome 5km could not book the 5km run it
--   advertises. K15 books a 5km run on exactly 5km of granted balance — the strict-gate
--   revert makes it red. Nobody re-tightens this without seeing Sean's name on it.
--
-- 🔴 What these pins deliberately do NOT assert: that anything CALLS this ledger. 0075 §0
--   is explicit — no edge function is wired; the marketplace still bills ₩. The cutover
--   slice owns those call sites and their own pins (booking+reserve atomicity, expiry-sweep
--   release). A pin claiming end-to-end km billing would be the dangerous kind of green.

do $$
declare
  ow uuid; oz uuid;
  dg uuid;
  b1 uuid; b2 uuid; b3 uuid; b4 uuid; bz uuid;
  v_num numeric; v_num2 numeric; v_int int; v_msg text; v_err text;
  v_paid numeric; v_granted numeric; v_held numeric;
  v_cnt int; v_cnt2 int;
  v_lot uuid;
begin
  -- ---------- seed ----------
  ow := t_user('km_ow', 'owner');
  oz := t_user('km_oz', 'owner');
  insert into dogs (owner_id, name) values (ow, '김초코') returning id into dg;
  -- bookings: direct insert (transition trigger fires on UPDATE only — 10_settle idiom)
  insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (ow, dg, 'active', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into b1;
  insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (ow, dg, 'active', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into b2;
  insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (ow, dg, 'active', now(), 1.0, 9900, 3000, 0, 12900, 9900) returning id into b3;
  insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (ow, dg, 'active', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into b4;
  insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (oz, dg, 'active', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into bz;

  perform set_config('request.jwt.claim.sub', ow::text, false);

  -- ---------- [K1] 환영 5km — 금액·버킷·만료·원장 won_value까지 ----------
  begin
    v_num := km_claim_welcome();
    select coalesce(sum(km_remaining), 0) into v_granted from km_lots
     where profile_id = ow and bucket = 'granted' and source = 'welcome' and expires_at > now();
    select coalesce(sum(won_value), 0) into v_int from km_ledger
     where profile_id = ow and reason = 'grant';
    if v_num = 5 and v_granted = 5 and v_int = 25000
      then call _pass('km','K1 환영 증여 — 5km granted, 30일 만료, 원장 won_value 25000');
      else v_msg := 'ret=' || v_num || ' granted=' || v_granted || ' won=' || v_int;
           call _fail('km','K1 환영 증여', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K1', v_msg);
  end;

  -- ---------- [K2] 재청구는 0 — 두 번째 로트는 없다 ----------
  begin
    v_num := km_claim_welcome();
    select count(*) into v_cnt from km_lots where profile_id = ow and source = 'welcome';
    if v_num = 0 and v_cnt = 1
      then call _pass('km','K2 환영 멱등 — 재청구 0, 로트 1개 (unique index가 레이스도 봉쇄)');
      else v_msg := 'ret=' || v_num || ' lots=' || v_cnt; call _fail('km','K2 환영 멱등', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K2', v_msg);
  end;

  -- ---------- [K15] 🔴 Sean D2 — 환영 5km가 5km 러닝을 예약한다 ----------
  -- 유상 로트를 넣기 **전에** 시험한다: 잔액이 정확히 granted 5뿐인 상태가 이 핀의 요점이다.
  -- 게이트가 greatest(3, planned)=5 ≤ 5 를 통과하고, 홀드는 min(5, 7)=5가 잡혀야 한다.
  begin
    v_num := km_reserve(b4);
    select coalesce(-sum(delta), 0) into v_held from km_ledger
     where booking_id = b4 and reason in ('booking_reserve', 'reserve_release');
    if v_num = 5 and v_held = 5
      then call _pass('km','K15 D2 베스트-에포트 버퍼 — 환영 5km로 5km 예약, 홀드 5 (버퍼는 여유 있을 때만)');
      else v_msg := 'ret=' || v_num || ' held=' || v_held; call _fail('km','K15 D2 게이트', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K15 D2 게이트', v_msg);
  end;
  -- 되돌린다 — 이후 핀들은 b4를 취소 반환 시험(K10)에 다시 쓴다.
  begin
    perform km_release(b4, 'cancel_refund');
  exception when others then null;
  end;

  -- ---------- 유상 30km 주입 (구매 경로는 Toss 이후 — 시험에선 로트 직접 삽입) ----------
  perform km_purchase(ow, 30, 150000);   -- C2: 유상은 원장을 통해서만 태어난다

  -- ---------- [K3] 소비 순서 — 증여 먼저, 유상은 나중 ----------
  begin
    v_num := km_reserve(b1);  -- planned 5 → hold 7 (잔액 35, 여유 충분)
    select coalesce(sum(km_remaining), 0) into v_granted from km_lots
     where profile_id = ow and bucket = 'granted';
    select coalesce(sum(km_remaining), 0) into v_paid from km_lots
     where profile_id = ow and bucket = 'paid';
    if v_num = 7 and v_granted = 0 and v_paid = 28
      then call _pass('km','K3 소비 순서 — 홀드 7 = 증여 5 전소 + 유상 2 (죽을 것부터 태운다)');
      else v_msg := 'hold=' || v_num || ' granted=' || v_granted || ' paid=' || v_paid;
           call _fail('km','K3 소비 순서', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K3', v_msg);
  end;

  -- ---------- [K4] 홀드 멱등 — 재호출은 재소비가 아니다 ----------
  begin
    select count(*) into v_cnt from km_ledger where booking_id = b1 and reason = 'booking_reserve';
    v_num := km_reserve(b1);
    select count(*) into v_cnt2 from km_ledger where booking_id = b1 and reason = 'booking_reserve';
    if v_num = 7 and v_cnt2 = v_cnt
      then call _pass('km','K4 홀드 멱등 — 재호출 7 반환, 원장 행 불변');
      else v_msg := 'ret=' || v_num || ' rows ' || v_cnt || '→' || v_cnt2;
           call _fail('km','K4 홀드 멱등', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K4', v_msg);
  end;

  -- ---------- [K5] 빈 잔액은 km_insufficient — 예약 게이트가 유일하게 막는 곳 ----------
  begin
    begin
      v_num := km_reserve(bz);  -- oz는 로트가 하나도 없다
      v_err := '<no error>';
    exception when others then v_err := sqlerrm;
    end;
    select count(*) into v_cnt from km_ledger where profile_id = oz;
    if v_err like '%km_insufficient%' and v_cnt = 0
      then call _pass('km','K5 잔액 부족 — km_insufficient, 원장 무기록');
      else v_msg := 'err=' || v_err || ' rows=' || v_cnt; call _fail('km','K5 잔액 부족', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K5', v_msg);
  end;

  -- ---------- [K6] 정산 언더런 — 실측만 깎고 나머지는 돌아온다 (덜 달렸으면 돌려준다) ----------
  begin
    v_num := km_settle(b1, 4.0);
    select coalesce(sum(km_remaining), 0) into v_granted from km_lots
     where profile_id = ow and bucket = 'granted';
    select coalesce(sum(km_remaining), 0) into v_paid from km_lots
     where profile_id = ow and bucket = 'paid';
    select coalesce(sum(won_value), 0) into v_int from km_ledger
     where booking_id = b1 and reason = 'run_debit';
    -- 해제 역순: 유상 +2 → 30, 증여 +5 → 5. 차감 4는 증여에서: granted 1, paid 30.
    if v_num = 4 and v_granted = 1 and v_paid = 30 and v_int = 20000
      then call _pass('km','K6 언더런 정산 — 청구 4, 증여로 귀환, run_debit won_value 20000');
      else v_msg := 'charge=' || v_num || ' granted=' || v_granted || ' paid=' || v_paid || ' won=' || v_int;
           call _fail('km','K6 언더런 정산', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K6', v_msg);
  end;

  -- ---------- [K7] 정산 멱등 — settle-run 재시도는 이중 청구가 아니다 ----------
  begin
    select count(*) into v_cnt from km_ledger where booking_id = b1;
    v_num := km_settle(b1, 4.0);
    select count(*) into v_cnt2 from km_ledger where booking_id = b1;
    if v_num = 4 and v_cnt2 = v_cnt
      then call _pass('km','K7 정산 멱등 — 재호출 4 반환, 원장 행 불변');
      else v_msg := 'ret=' || v_num || ' rows ' || v_cnt || '→' || v_cnt2;
           call _fail('km','K7 정산 멱등', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K7', v_msg);
  end;

  -- ---------- [K8] 오버런 클램프 — planned+2 밖은 플랫폼이 흡수한다 ----------
  -- 🔎 [뮤테이션 사이클이 가르쳐준 것] 첫 K8(정상 경로만)은 내부 클램프를 지우는 뮤테이션에
  -- **초록**이었다: D2 이후 홀드 ≤ planned+2이고 청구 ≤ 홀드라서, 도달 가능한 모든 상태에서
  -- 홀드 클램프가 내부 클램프를 덮는다. 즉 내부 least는 심층 방어다 — 그리고 심층 방어를 핀으로
  -- 지키려면 겉 방어가 비켜난 **합성 상태**가 필요하다 (111 N2의 owner_id 발견과 같은 무늬).
  -- 그래서 홀드 9를 픽스처가 직접 쓴다 (km_reserve로는 불가능한 상태) — 이때 내부 클램프만이
  -- 청구를 7로 막는다.
  begin
    v_num := km_reserve(b2);   -- granted 1 + paid 6 = hold 7 (정상 경로)
    v_num2 := km_settle(b2, 9.0);  -- actual 9 → clamp min(9, 7) = 7
    -- 합성 과홀드: planned 5짜리 새 예약에 홀드 9를 손으로 쓴다
    insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (ow, dg, 'active', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into bz;
    select id into v_lot from km_lots
     where profile_id = ow and bucket = 'paid' and km_remaining >= 9 limit 1;
    update km_lots set km_remaining = km_remaining - 9 where id = v_lot;
    insert into km_ledger (profile_id, lot_id, delta, won_value, reason, booking_id)
    values (ow, v_lot, -9, 45000, 'booking_reserve', bz);
    v_paid := km_settle(bz, 12.0);  -- 내부 클램프만 남는 상태: min(greatest(3, least(12, 7)), 9) = 7
    if v_num = 7 and v_num2 = 7 and v_paid = 7
      then call _pass('km','K8 오버런 클램프 — 정상 7 + 합성 과홀드 9에서도 청구 7 (내부 클램프 단독 관측)');
      else v_msg := 'hold=' || v_num || ' charge=' || v_num2 || ' synth_charge=' || v_paid;
           call _fail('km','K8 오버런', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K8', v_msg);
  end;

  -- ---------- [K9] 3km 바닥 — 픽업·인계 오버헤드는 건당이다 ----------
  begin
    v_num := km_reserve(b3);   -- planned 1 → hold greatest(3, 3) = 3
    v_num2 := km_settle(b3, 0.5);  -- actual 0.5 → charge greatest(3, 0.5) = 3
    if v_num = 3 and v_num2 = 3
      then call _pass('km','K9 3km 바닥 — planned 1km 홀드 3, 실측 0.5km 청구 3');
      else v_msg := 'hold=' || v_num || ' charge=' || v_num2; call _fail('km','K9 바닥', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K9', v_msg);
  end;

  -- ---------- [K16] 청구 ≤ 홀드 불변식 — 정산은 돈 문제로 실패하지 않는다 (D2 짝) ----------
  -- 타이트 잔액 재현: 새 예약(b4 재사용), 남은 잔액을 계산해 홀드가 버퍼를 다 못 잡는 상태를 만든다.
  begin
    -- 현재 잔액: granted 1 - (K8이 1 소비) … 실측으로 다시 센다.
    select coalesce(sum(km_remaining), 0) into v_num from km_lots
     where profile_id = ow and km_remaining > 0
       and (bucket = 'paid' or expires_at is null or expires_at > now());
    -- 5km 예약(b4): 게이트는 5 필요. 잔액을 정확히 5.5로 조정한다 (초과분은 별도 유령 소비가
    -- 아니라 시험 전용 로트 조정 — 원장 밖 직접 UPDATE는 시험에서만 허용).
    update km_lots set km_remaining = 0 where profile_id = ow and km_remaining > 0;
    perform km_purchase(ow, 5.5, 27500);
    v_num := km_reserve(b4);        -- hold = min(5.5, 7) = 5.5
    v_num2 := km_settle(b4, 9.0);   -- clamp = min(greatest(3, min(9,7)), 5.5) = 5.5
    if v_num = 5.5 and v_num2 = 5.5
      then call _pass('km','K16 청구≤홀드 — 타이트 잔액 5.5, 홀드 5.5, 실측 9 청구 5.5 (초과는 플랫폼 흡수)');
      else v_msg := 'hold=' || v_num || ' charge=' || v_num2; call _fail('km','K16 청구≤홀드', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K16', v_msg);
  end;

  -- ---------- [K10] 취소 반환 — km은 원래 로트로 돌아간다, 새 로트가 아니라 ----------
  begin
    -- 깨끗한 상태로: 잔액 10 유상 단일 로트, 새 예약 홀드 후 취소.
    update km_lots set km_remaining = 0 where profile_id = ow and km_remaining > 0;
    v_lot := km_purchase(ow, 10, 50000);
    insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (ow, dg, 'active', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into b1;  -- 새 부킹 재사용 변수
    v_num := km_reserve(b1);            -- hold 7 → lot 3 남음
    v_num2 := km_release(b1, 'cancel_refund');
    select km_remaining into v_paid from km_lots where id = v_lot;
    select count(*) into v_cnt from km_lots
     where profile_id = ow and source = 'refund';
    if v_num = 7 and v_num2 = 7 and v_paid = 10 and v_cnt = 0
      then call _pass('km','K10 취소 반환 — 홀드 7이 원래 유상 로트로 (refund 신규 로트 0개)');
      else v_msg := 'hold=' || v_num || ' rel=' || v_num2 || ' lot=' || v_paid || ' refund_lots=' || v_cnt;
           call _fail('km','K10 취소 반환', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K10', v_msg);
  end;

  -- ---------- [K11] 유상은 만료가 **스키마로** 불가능하다 ----------
  begin
    begin
      insert into km_lots (profile_id, bucket, source, km_total, km_remaining, won_paid, expires_at)
      values (ow, 'paid', 'purchase', 1, 1, 5000, now() + interval '30 days');
      v_err := '<no error>';
    exception when others then v_err := sqlerrm;
    end;
    if v_err like '%km_lots_paid_never_expires%'
      then call _pass('km','K11 유상 무만료 — 만료일 붙은 유상 로트는 제약이 거부한다');
      else v_msg := 'err=' || v_err; call _fail('km','K11 유상 무만료', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K11', v_msg);
  end;

  -- ---------- [K12] 만료 소각 — 소각은 원장에 남는다, 조용히 사라지지 않는다 ----------
  begin
    perform km_grant(ow, 2, 'recovery', -1);  -- 어제 만료된 증여 2km
    v_int := km_expire_sweep();
    select coalesce(sum(km_remaining), 0) into v_granted from km_lots
     where profile_id = ow and source = 'recovery';
    select count(*) into v_cnt from km_ledger
     where profile_id = ow and reason = 'expiry';
    select coalesce(sum(km_remaining), 0) into v_paid from km_lots
     where profile_id = ow and bucket = 'paid';
    if v_int >= 1 and v_granted = 0 and v_cnt >= 1 and v_paid = 10
      then call _pass('km','K12 만료 소각 — 증여 소각 + expiry 원장 행, 유상 무손상');
      else v_msg := 'swept=' || v_int || ' granted=' || v_granted || ' expiry_rows=' || v_cnt || ' paid=' || v_paid;
           call _fail('km','K12 만료 소각', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K12', v_msg);
  end;

  -- ---------- [K13] 잔액은 스윕 전에도 죽은 증여를 세지 않는다 ----------
  begin
    perform km_grant(ow, 3, 'recovery', -1);  -- 만료됐지만 아직 스윕 안 됨
    select granted_km into v_granted from km_balance();
    if v_granted = 0
      then call _pass('km','K13 잔액 정직 — 만료 지난 증여는 스윕 전에도 잔액이 아니다');
      else v_msg := 'granted=' || v_granted; call _fail('km','K13 잔액 정직', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K13', v_msg);
  end;

  -- ---------- [K17] 차감 출처 보존 — 러닝 중 도착한 증여는 이 정산의 돈이 아니다 (codex #6) ----------
  begin
    -- 깨끗한 상태: 유상 10만 남기고, 예약 홀드(7) 후 **러닝 중** 새 증여 3km 도착 시나리오.
    update km_lots set km_remaining = 0 where profile_id = ow and km_remaining > 0;
    v_lot := km_purchase(ow, 10, 50000);
    insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (ow, dg, 'active', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into b2;
    v_num := km_reserve(b2);                    -- 유상에서 7 홀드
    perform km_grant(ow, 3, 'recovery', 30);    -- 러닝 중 증여 도착 (만료 30일)
    v_num2 := km_settle(b2, 5.0);               -- 청구 5
    -- 차감은 홀드했던 유상 로트에서 나가야 한다: 유상 = 10 − 7 + 2(반환) = 5, 증여는 3 그대로.
    select km_remaining into v_paid from km_lots where id = v_lot;
    select coalesce(sum(km_remaining), 0) into v_granted from km_lots
     where profile_id = ow and source = 'recovery' and km_remaining > 0;
    select count(*) into v_cnt from km_ledger l join km_lots k on k.id = l.lot_id
     where l.booking_id = b2 and l.reason = 'run_debit' and k.source = 'recovery';
    if v_num = 7 and v_num2 = 5 and v_paid = 5 and v_granted = 3 and v_cnt = 0
      then call _pass('km','K17 차감 출처 — 러닝 중 도착한 증여 무손상, 차감은 홀드 로트에서만');
      else v_msg := 'hold=' || v_num || ' charge=' || v_num2 || ' paid_lot=' || v_paid
                 || ' new_grant=' || v_granted || ' debit_on_grant_rows=' || v_cnt;
           call _fail('km','K17 차감 출처', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K17', v_msg);
  end;

  -- ---------- [K18] 홀드 중 만료 = 72시간 유예, 재발행 아님 (codex #7 — D-1 무한 연장 봉쇄) ----------
  begin
    update km_lots set km_remaining = 0 where profile_id = ow and km_remaining > 0;
    perform km_grant(ow, 5, 'recovery', 30);
    insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
    values (ow, dg, 'active', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into b3;
    v_num := km_reserve(b3);   -- 증여 5 홀드
    -- 홀드 중 만료를 시뮬레이트 (픽스처 전용 직접 UPDATE)
    update km_lots set expires_at = now() - interval '1 hour'
     where profile_id = ow and source = 'recovery' and km_total = 5;
    v_num2 := km_release(b3, 'cancel_refund');
    select count(*) into v_cnt from km_lots
     where profile_id = ow and source = 'refund';   -- 새 로트가 없어야 한다
    select count(*) into v_cnt2 from km_lots
     where profile_id = ow and source = 'recovery' and km_total = 5 and km_remaining = 5
       and expires_at > now() and expires_at <= now() + interval '73 hours';
    if v_num = 5 and v_num2 = 5 and v_cnt = 0 and v_cnt2 = 1
      then call _pass('km','K18 만료 유예 — 같은 로트로 귀환 + 72h 유예 (30일 재발행 기계 아님)');
      else v_msg := 'hold=' || v_num || ' rel=' || v_num2 || ' new_lots=' || v_cnt || ' graced=' || v_cnt2;
           call _fail('km','K18 만료 유예', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K18', v_msg);
  end;

  -- ---------- [K14] 봉인 — addresses의 교훈을 태어날 때 적용했다 ----------
  begin
    if     not has_function_privilege('authenticated', 'km_grant(uuid,numeric,text,int)', 'execute')
       and not has_function_privilege('authenticated', 'km_reserve(uuid)', 'execute')
       and not has_function_privilege('authenticated', 'km_settle(uuid,numeric)', 'execute')
       and not has_function_privilege('authenticated', 'km_release(uuid,text)', 'execute')
       and not has_function_privilege('authenticated', 'km_expire_sweep()', 'execute')
       and not has_function_privilege('anon', 'km_claim_welcome()', 'execute')
       and     has_function_privilege('authenticated', 'km_claim_welcome()', 'execute')
       and     has_function_privilege('authenticated', 'km_balance()', 'execute')
       and not has_table_privilege('authenticated', 'km_lots', 'insert')
       and not has_table_privilege('authenticated', 'km_lots', 'update')
       and not has_table_privilege('authenticated', 'km_lots', 'delete')
       and     has_table_privilege('authenticated', 'km_lots', 'select')
       and not has_table_privilege('authenticated', 'km_ledger', 'insert')
       and not has_table_privilege('authenticated', 'km_ledger', 'update')
       and not has_table_privilege('anon', 'km_lots', 'select')
       and (select count(*) from pg_policies where tablename in ('km_lots','km_ledger') and cmd = 'SELECT') = 2
      then call _pass('km','K14 봉인 — 쓰기 경로는 definer만, 테이블은 본인 select만 (컬럼 그랜트 법)');
      else call _fail('km','K14 봉인', 'privilege matrix mismatch — 개별 has_*_privilege를 직접 확인할 것');
    end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K14', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;

-- ---------- [K19] §K 종결 트리거 — 예약이 죽으면 홀드가 풀린다 (스펙리뷰 I5) ----------
-- do-블록을 분리한 이유: 상태 전이 트리거(enforce_booking_transition)가 허용하는 경로로
-- 가야 해서 confirmed → cancelled_owner 전이를 실제로 밟는다.
do $$
declare
  ow uuid; dg uuid; bk uuid;
  v_num numeric; v_msg text; v_paid numeric;
begin
  ow := t_user('km_ow2', 'owner');
  insert into dogs (owner_id, name) values (ow, '박보리') returning id into dg;
  perform km_purchase(ow, 10, 50000);
  insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (ow, dg, 'confirmed', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into bk;

  begin
    v_num := km_reserve(bk);   -- 홀드 7 → 잔액 3
    update bookings set status = 'cancelled_owner' where id = bk;   -- 종결 전이 → 트리거
    select coalesce(sum(km_remaining), 0) into v_paid from km_lots where profile_id = ow;
    if v_num = 7 and v_paid = 10
      then call _pass('km','K19 종결 트리거 — cancelled_owner 전이가 홀드 7을 자동 반환');
      else v_msg := 'hold=' || v_num || ' paid_after=' || v_paid;
           call _fail('km','K19 종결 트리거', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K19', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;

-- ---------- [K20] 잔액의 held_km — 세 넷팅 사이트 중 유일하게 안 핀돼 있던 곳 (eng L1) ----------
-- ---------- [K21] 정산된 예약 재홀드 금지 · [K22] RLS 실행 검증 · [K23] 원장↔로트 조정 ----------
do $$
declare
  ow3 uuid; oz3 uuid; dg3 uuid; bk3 uuid;
  v_num numeric; v_held numeric; v_msg text; v_err text;
  v_cnt int; v_bad int;
begin
  ow3 := t_user('km_ow3', 'owner');
  oz3 := t_user('km_oz3', 'owner');
  insert into dogs (owner_id, name) values (ow3, '이콩이') returning id into dg3;
  perform km_purchase(ow3, 20, 100000);
  insert into bookings (owner_id, dog_id, status, scheduled_at, km, base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (ow3, dg3, 'active', now(), 5.0, 9900, 15000, 0, 24900, 9900) returning id into bk3;
  perform set_config('request.jwt.claim.sub', ow3::text, false);

  -- [K20] 홀드 전 0 → 홀드 후 7 → 정산 후 0. km_balance().held_km은 화면이 그릴 숫자다 —
  -- run_debit 항을 지우는 뮤테이션이 다른 세 사이트에선 빨개지지만 여기선 안 빨개졌었다.
  begin
    v_num := km_reserve(bk3);
    select held_km into v_held from km_balance();
    perform km_settle(bk3, 4.0);
    select held_km into v_num from km_balance();
    if v_held = 7 and v_num = 0
      then call _pass('km','K20 잔액 held — 홀드 7 표시, 정산 후 0 (두 항 넷팅이 화면까지 온다)');
      else v_msg := 'held_after_reserve=' || v_held || ' held_after_settle=' || v_num;
           call _fail('km','K20 잔액 held', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K20', v_msg);
  end;

  -- [K21] 정산된 예약에 재홀드는 오류다 — 조용한 재차감이 아니라
  begin
    begin
      v_num := km_reserve(bk3);
      v_err := '<no error>';
    exception when others then v_err := sqlerrm;
    end;
    if v_err like '%km_already_settled%'
      then call _pass('km','K21 정산 후 재홀드 거절 — km_already_settled');
      else v_msg := 'err=' || v_err; call _fail('km','K21 재홀드', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K21', v_msg);
  end;

  -- [K22] RLS를 **실행**한다 (eng H1: 하네스는 postgres = 테이블 소유자라 정책이 한 번도
  -- 돈 적 없었다; K14는 카탈로그만 읽는다 — using(true)로 바꿔도 초록이었다). 101 S1 관용구.
  begin
    perform set_config('request.jwt.claim.sub', oz3::text, false);
    set local role authenticated;
    select count(*) into v_cnt from km_lots;      -- oz3의 눈: ow3의 로트가 보이면 안 된다
    select count(*) into v_bad from km_ledger;
    reset role;
    perform set_config('request.jwt.claim.sub', ow3::text, false);
    set local role authenticated;
    select count(*) into v_num from km_lots;      -- ow3의 눈: 자기 로트는 보여야 한다
    reset role;
    if v_cnt = 0 and v_bad = 0 and v_num >= 1
       and not has_table_privilege('anon', 'km_ledger', 'select')
       and not has_function_privilege('authenticated', '_km_consume(uuid,numeric,text,uuid)', 'execute')
       and not has_function_privilege('authenticated', '_km_close_hold(uuid,uuid,numeric,text)', 'execute')
      then call _pass('km','K22 RLS 실행 — 남의 로트·원장 0행, 내 로트 보임, 내부 함수·anon 봉인');
      else v_msg := 'foreign_lots=' || v_cnt || ' foreign_ledger=' || v_bad || ' own_lots=' || v_num;
           call _fail('km','K22 RLS 실행', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('km','K22', v_msg);
  end;

  -- [K23] 조정 — 원장으로 태어난 모든 로트에서 km_remaining = Σ(delta where reason≠run_debit).
  -- run_debit은 로트를 움직이지 않는 전환이므로 제외 (0075 §F). ow3·km_ow2(K19)처럼 픽스처가
  -- 손대지 않은 사용자만 — km_ow의 상태는 시험 목적으로 직접 조정돼 있어 대상이 아니다 (헤더).
  begin
    select count(*) into v_bad
    from km_lots k
    where k.profile_id in (ow3, oz3)
      and k.km_remaining <> coalesce((
        select sum(l.delta) from km_ledger l
        where l.lot_id = k.id and l.reason <> 'run_debit'), 0);
    if v_bad = 0
      then call _pass('km','K23 조정 — 원장산 로트 전수: km_remaining = Σ원장(전환 제외)');
      else v_msg := 'divergent_lots=' || v_bad; call _fail('km','K23 조정', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('km','K23', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
