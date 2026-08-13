-- ═══ 122 runner-stop-pay suite — 0086 pins (⑨a: a `runner_personal` stop pays pass-through) ═══
-- Purpose: the ruling moves one number and nothing else — no status, no notification, no owner
--   charge. That makes the pins unusually literal: the two returned integers ARE the behaviour.
-- Style: sibling of 105-121 — `_pass('rsp',…)`/`_fail('rsp',…)`, one begin…exception per case.
--   ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
--
-- ⚠ THESE PINS ASSERT A FORMULA, NOT THE MEMO'S FIGURES. `docs/decisions/runner-stop-split.md`
--   records 2,010 / 8,643 — those are ONE KILOMETRE OF A THREE-KILOMETRE BOOKING, and a suite that
--   only checked them would stay green while somebody hard-coded them. So P1 checks the
--   pass-through against `compute_owner_charge`'s own answer at four distances, checks that
--   doubling the distance doubles the pay, checks that the commission is a parameter — and only
--   then, as one arm among many, checks that the rule reproduces the recorded illustration.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   P1  ← 0086 §A: any drift from `gross = compute_owner_charge(…, 'runner_personal', km).amount`
--         — hard-code 2,010, re-add `base_fare`, re-add addons, drop the min(actual, planned)
--         ceiling, or treat the commission as a constant                                    → RED
--   P2  ← 0086 §A: restore the pre-⑨a runner formula (`max(9,900 + 3,000×km + addons, min_fare)`)
--         for this arm. This pin is the RULING, as an inequality that survives price changes: a
--         1km stop on a 3km booking must pay less than the flat base, the min_fare floor must not
--         resurrect it, addons must not ride along, and the platform must not lose money   → RED
--   P3  ← 0086 §A: default a missing/absurd commission instead of raising (a corrupted runners row
--         then silently pays 100% or 0%), or answer something other than 0 when the owner's charge
--         is 0 (`below_pg_minimum` — the runner's share of nothing is nothing)              → RED
--   P4  ← 0086 §A: `grant execute … to authenticated` — a client that can call this function
--         enumerates other people's charges (it is a definer over `bookings`)               → RED
--
--   ⚠ `net = gross − fee` is NOT pinnable here: the SQL returns the two halves and
--     `settle-run/handler.ts` does the subtraction. `settle_charge_test.ts`'s two `runner_personal`
--     tests pin it. That gap is structural and is the same one 117's header records for the client
--     half of its error codes — this harness only sees SQL.
--
--   ✔ MUTATION-PROVEN by full-harness runs (clean cluster each time — stop the postmaster before
--     `rm -rf .pgtest`, or the orphan holds a deleted socket path and the next run dies at the shim
--     looking like a migration bug).
--     ⚠ MEASURED AGAINST THE MERGED TREE, not this branch: `origin/redesign-v4`'s
--     `supabase/{migrations,tests}` (which already carries 0085/121, the ⑩ slice) + this file and
--     0086 laid on top. That is the state these pins will actually live in, and it is 6 pins richer
--     than this branch's own baseline. **Green = 471/0** (467 on origin's tip + P1-P4). Four
--     reverts of 0086 §A, each measured on a clean cluster, restore → 471/0 every time:
--       ⓐ `v_amount := 3000` — the memo's 1km-of-3km illustration, hard-coded →
--          **469/2, red = [P1, P3]**. P1: `0.5km gross=3000/보호자청구=1500 · 2배 비례 깨짐:
--          3000→3000 · 상한=3000 (9000 기대)`. P3 goes red too, which the first draft of this map
--          did not predict: a hard-coded amount also breaks the below-minimum arm
--          (`최소금액 미만=below_pg_minimum 3000/990`) and the negative-distance arm. P2 stays
--          GREEN — 3,000 is still below the flat base, which is exactly why P2 cannot be the pin
--          that protects the formula.
--       ⓑ `compute_owner_charge(…, 'runner_personal', …)` → `'completed'` (the base creeps back
--          in — the single most likely "fix") → **468/3, red = [P1, P2, P3]**
--          (P2: `옛 공식(base+거리)만큼 지급한다: 10900 · min_fare 바닥이 되살아났다 · 플랫폼이
--          손해를 본다 · 애드온이 지급에 섞였다: 14900`).
--       ⓒ `raise exception 'invalid_commission'` → `p_commission := 0.33` →
--          **470/1, red = [P3]** (all four bad rates pass: `커미션 null 통과: gross=3000 fee=990`).
--       ⓓ `grant execute … to authenticated` added → **470/1, red = [P4]** (`authenticated`).
--          Nothing else in the harness sees it — 98 H1 watches search_path, not grants.
--
--   ─── the TypeScript half, measured the same way (`deno test -A supabase/functions/_test/`) ───
--     Green = 162/0 (158 before this slice + 4). Two reverts of `settle-run/handler.ts`:
--       ⓔ the `runner_personal` arm made unreachable (the pre-⑨a formula returns) →
--          **159/3**, red = the three ⑨a tests (`is paid the PASS-THROUGH`, `the stop's LEDGER
--          ROW`, `the payout RPC failing FAILS CLOSED`).
--       ⓕ `base = 0` dropped so the 9,900 line survives into the ledger row, with
--          `distancePay = gross - base` keeping the total right → **161/1, red = the LEDGER ROW
--          test alone.** That separation is the point: the runner's TOTAL can be correct while
--          their breakdown claims a base fee nobody paid.
set client_min_messages = warning;

-- ---------- suite-local fixture ----------
-- A marketplace-priced booking: owner base 7,900 + 3,000/km (ctx.ts PRICING, the D2 world), so the
-- frozen columns this suite reads are the ones `create-booking-hold` really writes. `min_fare` is
-- the shipped 9,900 — P2 needs it present to prove the pass-through does NOT floor on it.
create or replace function t_rsp_bk(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid,
                                    p_km numeric, p_base int, p_dist int, p_addon int)
returns uuid language sql as $$
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'active', now() + interval '2 hours', p_km,
          p_base, p_dist, p_addon, p_base + p_dist + p_addon, 9900)
  returning id
$$;

do $$
declare
  oo uuid; rr uuid; dg uuid; rt uuid; b_pt uuid; b_tiny uuid;
  c record; pay record; pay2 record;
  v_bad text := ''; v_msg text; v_err text; v_g int; v_km numeric; v_c numeric;
begin
  -- ---------- seed ----------
  -- The memo's own fixture: a 3km booking (7,900 + 9,000 = 16,900), stopped partway.
  oo := t_user('rsp_owner', 'owner');
  rr := t_user('rsp_runner', 'runner');
  dg := t_dog(oo, '중단견');
  rt := t_route('중단정산 코스');
  b_pt := t_rsp_bk(oo, dg, rt, rr, 3.0, 7900, 9000, 0);

  -- ---------- [P1] the pass-through IS the owner's charge, times the runner's share ----------
  begin
    v_bad := '';
    -- ⓐ the DEFINING property, at four distances, asserted against compute_owner_charge's own
    --    answer — so it cannot be satisfied by a constant, and the min(actual, planned) ceiling
    --    comes along for free.
    foreach v_km in array array[0.5, 1.0, 2.4, 5.0] loop
      select * into c from compute_owner_charge(b_pt, 'runner_personal', v_km);
      select * into pay from compute_runner_personal_payout(b_pt, v_km, 0.33);
      if pay.gross <> c.amount then
        v_bad := v_bad || ' ' || v_km || 'km gross=' || pay.gross || '/보호자청구=' || c.amount;
      end if;
      if pay.fee <> round(c.amount * 0.33)::int then
        v_bad := v_bad || ' ' || v_km || 'km fee=' || pay.fee;
      end if;
      if pay.fee > pay.gross then v_bad := v_bad || ' ' || v_km || 'km 수수료가 총액을 넘는다'; end if;
    end loop;
    -- ⓑ it SCALES: twice the distance is twice the pay. A hard-coded figure dies here.
    select * into pay from compute_runner_personal_payout(b_pt, 1.0, 0.33);
    select * into pay2 from compute_runner_personal_payout(b_pt, 2.0, 0.33);
    if pay2.gross <> pay.gross * 2 then
      v_bad := v_bad || ' 2배 비례 깨짐: ' || pay.gross || '→' || pay2.gross;
    end if;
    -- ⓒ the ceiling: 5km declared on a 3km plan pays the 3km charge, never more
    select * into pay2 from compute_runner_personal_payout(b_pt, 5.0, 0.33);
    if pay2.gross <> 9000 then v_bad := v_bad || ' 상한=' || pay2.gross || ' (9000 기대)'; end if;
    -- ⓓ the COMMISSION is a parameter, not a constant: the same stop at 20% pays more
    select * into pay2 from compute_runner_personal_payout(b_pt, 1.0, 0.20);
    if pay2.gross <> pay.gross or pay2.fee <> 600 or pay2.gross - pay2.fee <> 2400
      then v_bad := v_bad || ' 20% 커미션=' || pay2.gross || '/' || pay2.fee; end if;
    -- ⓔ ...and, one arm among many, the rule reproduces the memo's recorded illustration:
    --    1km of a 3km booking at 33% → owner 3,000 · runner 2,010 · platform 990.
    if pay.gross <> 3000 or pay.fee <> 990 or pay.gross - pay.fee <> 2010
      then v_bad := v_bad || ' 메모 예시 불일치: ' || pay.gross || '/' || pay.fee; end if;

    if v_bad = ''
      then call _pass('rsp','P1 패스스루 = 보호자 청구액 × 러너 몫 — 네 거리에서 compute_owner_charge와 항등·거리 2배면 지급 2배·계획 초과는 상한·커미션은 파라미터·기록된 예시(1km/3km → 3000·990·2010) 재현 (⑨a: 수식이 결정이고 숫자는 예시다)');
    else v_msg := v_bad; call _fail('rsp','P1 패스스루 수식', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rsp','P1 패스스루 수식', v_msg);
  end;

  -- ---------- [P2] the ruling itself: a stop no longer pays a flat base ----------
  -- The pre-⑨a formula paid `max(9,900 + 3,000×actual + addons, min_fare)` less commission —
  -- ₩8,643 net on this fixture against a ₩3,000 owner charge, i.e. the platform funding ₩5,643 of
  -- a run that did not happen. Stated as inequalities so it survives every future price change.
  begin
    v_bad := '';
    select * into pay from compute_runner_personal_payout(b_pt, 1.0, 0.33);
    select * into c from compute_owner_charge(b_pt, 'runner_personal', 1.0);
    if pay.gross >= (select base_fare + round(distance_fare / km * 1.0) from bookings where id = b_pt)
      then v_bad := v_bad || ' 옛 공식(base+거리)만큼 지급한다: ' || pay.gross; end if;
    if pay.gross >= (select min_fare from bookings where id = b_pt)
      then v_bad := v_bad || ' min_fare 바닥이 되살아났다: ' || pay.gross; end if;
    -- the platform never loses money on this arm any more — the ruling's own claim
    if c.amount - pay.gross < 0 then v_bad := v_bad || ' 플랫폼이 손해를 본다'; end if;
    if c.amount - (pay.gross - pay.fee) <> pay.fee
      then v_bad := v_bad || ' 플랫폼 몫이 수수료와 다르다'; end if;
    -- addons are NOT paid on a stop, because the owner is not charged for them (#10)
    v_g := pay.gross;
    update bookings set addon_fare = 4000, total_price = 20900 where id = b_pt;
    select * into pay2 from compute_runner_personal_payout(b_pt, 1.0, 0.33);
    update bookings set addon_fare = 0, total_price = 16900 where id = b_pt;
    if pay2.gross <> v_g then v_bad := v_bad || ' 애드온이 지급에 섞였다: ' || pay2.gross; end if;

    if v_bad = ''
      then call _pass('rsp','P2 중단은 더 이상 정액 base를 지급하지 않는다 — 1km 중단 지급 < base+거리·min_fare 바닥 없음·애드온 미지급·플랫폼 몫 = 수수료 (⑨a가 되돌려진 것을 잡는 핀)');
    else v_msg := v_bad; call _fail('rsp','P2 정액 base 은퇴', v_msg); end if;
  exception when others then
    update bookings set addon_fare = 0, total_price = 16900 where id = b_pt;
    v_msg := sqlerrm; call _fail('rsp','P2 정액 base 은퇴', v_msg);
  end;

  -- ---------- [P3] it fails closed on a commission it cannot trust, and on nothing to pay ------
  -- This runs BEFORE settle_run_tx, so a raise costs a retriable 500 with nothing written. A
  -- silent default would write the wrong money into a ledger nobody re-reads.
  begin
    v_bad := '';
    foreach v_c in array array[null::numeric, -0.1, 1.0, 1.5] loop
      begin
        select * into pay from compute_runner_personal_payout(b_pt, 1.0, v_c);
        v_bad := v_bad || ' 커미션 ' || coalesce(v_c::text, 'null') || ' 통과: gross=' || pay.gross || ' fee=' || pay.fee;
      exception when others then v_err := sqlerrm;
        if v_err not like '%invalid_commission%' then v_bad := v_bad || ' 커미션 거절 코드=' || v_err; end if;
      end;
    end loop;
    -- 0% is legitimate (a promo runner keeps everything) and must NOT raise
    select * into pay from compute_runner_personal_payout(b_pt, 1.0, 0);
    if pay.fee <> 0 or pay.gross <> 3000 then v_bad := v_bad || ' 0% 커미션=' || pay.gross || '/' || pay.fee; end if;
    -- below the PG minimum the owner is charged 0 (0084 §A ⑤), so the runner's share of it is 0
    b_tiny := t_rsp_bk(oo, dg, rt, rr, 3.0, 7900, 9000, 0);
    select * into c from compute_owner_charge(b_tiny, 'runner_personal', 0.01);
    select * into pay from compute_runner_personal_payout(b_tiny, 0.01, 0.33);
    if c.rule <> 'below_pg_minimum' or pay.gross <> 0 or pay.fee <> 0
      then v_bad := v_bad || ' 최소금액 미만=' || c.rule || ' ' || pay.gross || '/' || pay.fee; end if;
    -- a negative/absent distance cannot pay a negative wage (the basis clamps at 0)
    select * into pay from compute_runner_personal_payout(b_pt, -5.0, 0.33);
    if pay.gross <> 0 or pay.fee <> 0 then v_bad := v_bad || ' 음수 거리=' || pay.gross; end if;
    -- an unknown booking raises, exactly as the mint does
    begin
      select * into pay from compute_runner_personal_payout(gen_random_uuid(), 1.0, 0.33);
      v_bad := v_bad || ' 없는 예약이 통과';
    exception when others then v_err := sqlerrm;
      if v_err not like '%not_found%' then v_bad := v_bad || ' 없는 예약 코드=' || v_err; end if;
    end;

    if v_bad = ''
      then call _pass('rsp','P3 신뢰할 수 없는 커미션은 거절(null·음수·1.0·1.5 → invalid_commission), 0%는 정상·최소금액 미만 청구는 지급도 0·음수 거리도 0·없는 예약은 not_found (settle_run_tx 앞이라 raise는 재시도로 끝난다)');
    else v_msg := v_bad; call _fail('rsp','P3 실패 폐쇄', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rsp','P3 실패 폐쇄', v_msg);
  end;

  -- ---------- [P4] grant matrix — server-only ----------
  -- A definer bypasses RLS by construction, so the execute grant is the whole seal: this function
  -- reads any booking's frozen fare columns and answers a price.
  declare
    f text := 'compute_runner_personal_payout(uuid,numeric,numeric)';
  begin
    v_bad := '';
    if to_regprocedure(f) is null then v_bad := ' 함수 없음';
    else
      if has_function_privilege('authenticated', f, 'execute') then v_bad := v_bad || ' authenticated'; end if;
      if has_function_privilege('anon', f, 'execute') then v_bad := v_bad || ' anon'; end if;
      if not has_function_privilege('service_role', f, 'execute') then v_bad := v_bad || ' service_role 불가'; end if;
    end if;
    -- positive control: a runner-facing RPC IS callable (else this pin proves nothing)
    if not has_function_privilege('authenticated', 'my_ledger_total()', 'execute')
      then v_bad := v_bad || ' 대조군(my_ledger_total) 불가 — 핀이 무의미'; end if;

    if v_bad = ''
      then call _pass('rsp','P4 권한 매트릭스 — 패스스루 함수는 service_role 전용(anon·authenticated 거부), 러너 집계 RPC는 그대로 authenticated (양성 대조)');
    else v_msg := v_bad; call _fail('rsp','P4 권한 매트릭스', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rsp','P4 권한 매트릭스', v_msg);
  end;
end $$;
