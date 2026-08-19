-- ═══ 137 runner-payout suite — 0101 pins (§0g: the runner's price moved out of TypeScript) ═══
-- Purpose: `compute_runner_payout` is a pure extraction of `settle-run/handler.ts:135-187`. There
--   is no new behaviour to describe, so the pins are the only thing that can say the port was
--   faithful — and a pin that merely re-derives the SQL's own formula would say nothing at all.
-- Style: sibling of 105-136 — `_pass('rpay',…)`/`_fail('rpay',…)`, one begin…exception per case.
--   ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
--
-- ═══ WHERE THE NUMBERS COME FROM — read this before touching a single literal ═══
-- Every expected value in `_rpay_expect` below was CAPTURED, not derived. The procedure, per
-- `docs/decisions/g0-runner-payout-in-sql.md`'s three steps:
--   ① 0101 §A was built.
--   ② an EQUIVALENCE run drove the **live, pre-change `settle-run/handler.ts`** — the real Deno
--      handler, through its frozen path (which skips every input validation, so all six
--      `end_reason`s and every distance are reachable) — over this exact fixture matrix, and read
--      the five money arguments it handed `settle_run_tx` plus the gross/fee it answered. The same
--      matrix was run through `compute_runner_payout` in this cluster. **51 rows, 0 mismatches.**
--   ③ this file: the TypeScript arithmetic was DELETED, and the equivalence pin was replaced by
--      the captured table below. The literals are the TypeScript's own output, frozen at the last
--      moment it existed.
-- ⚠ THAT IS THE WHOLE POINT, and it is why re-deriving these numbers from the SQL would destroy
--   the pin without reddening anything. An equivalence pin is scaffolding with a demolition date,
--   and the date is the moment the thing it compares to stops existing (trust, plan review). If
--   0101 §A ever changes on purpose, these literals must be changed by a HUMAN who states which
--   money rule moved — never by re-running the function and pasting what it said.
--
-- ─── the fixture matrix, and what each fixture is FOR ───
--   A · 3.0km, no addons, min_fare 9,900 (the shipped default — never binds, since the runner base
--       alone is 9,900). Carries all six `end_reason`s at actual = 0 / 1.5 (below) / 3.0 (exactly)
--       / 4.5 (above planned), so the four distance positions and the whole enum are covered here.
--   B · 2.0km WITH addons (river 3,000 + snack 2,000). The addons arm, and — at actual 3.0 on a
--       2.0 plan — the owner-caused clamp a second time on a different shape.
--   C · 1.0km, min_fare 20,000. The floor BINDS here and only here: 9,900 + 3,000 = 12,900 is under
--       it. A booking whose min_fare is the shipped 9,900 can never demonstrate the floor, because
--       the base equals it — which is exactly why the first draft of this matrix had no C.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   R1  ← 0101 §A: `RUNNER_COMP_BASE := 7900` (reading the OWNER's base — the D2 collapse, the
--         single most likely porter error, and one no owner-side pin can see)              → RED
--   R2  ← 0101 §A: drop the `greatest(…, min_fare)` floor, or turn it into a CEILING       → RED
--   R3  ← 0101 §A: drop the `greatest(0, …)` clamp on the guarantee — an owner-caused stop
--         whose actual already passed the plan then pays the runner LESS than the same
--         distance under any other reason (a pay cut for being cut short)                  → RED
--   R4  ← 0101 §A: apply the `min_fare` floor to the `runner_personal` arm (that floor IS the
--         flat base ⑨a retires), re-derive the arm instead of delegating to 0086 §A, or let
--         `base`/`addon` be anything but 0 (a fee the owner never paid, in the ledger)      → RED
--   R5  ← 0101 §A: compute the fee twice — `fee := gross - round(gross × (1−commission))`,
--         the "re-round the subtraction" error 0086 §A already forbids. Off by exactly ₩1 on
--         every gross whose commission lands on a half-won, and invisible everywhere else   → RED
--   R6  ← 0101 §A: `grant execute … to authenticated` (or anon). The function is a definer over
--         `bookings` with NO party gate — deliberately — so the grant is the entire seal, and
--         nothing else in the harness watches it (99 S1 is anon-only, 98 H1 watches search_path).
--         Also covers fail-closed: an unknown end_reason and an unknown booking must raise  → RED
--
--   ⚠ WHAT THESE PINS DELIBERATELY DO NOT ASSERT:
--   · That `settle-run` calls this function. The harness only sees SQL (122's header records the
--     same structural gap). `settle_charge_test.ts` is the other half and must be read as part of
--     this slice, not instead of it.
--   · That `net = gross − fee`. The SQL returns the two halves; the subtraction is the caller's,
--     by design (⑤) — so it is pinned in Deno, not here.
--   · The 50%-of-planned completion gate. It stayed in TypeScript on purpose (an eligibility rule,
--     not a price), which is why this function will happily price `completed` at 0km — a state no
--     runner can reach through `settle-run`, and one §0h's ops exit needs an answer for.
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-19, on this branch
--     (`claude/payments-toss-plan-slice-8079f7`, level with `origin/redesign-v4`).
--     **Baseline before 0101 = 566/0. Green with 0101 + this file = 572/0.** Every mutation was
--     applied to 0101 §A alone and reverted after; restore → 572/0.
--       ⓐ `RUNNER_COMP_BASE := 7900` → **568/4, red = [R1, R2, R3, R5]**. R1 names it exactly:
--          `base=7900 (9900 기대 — 러너 기준) · base가 보호자 기본요금과 같아졌다 (D2 붕괴)`, and
--          every A/B row is short by ₩2,000. R1 is the only pin ⓐ reddens that no other mutation
--          does. ⚠ **R2 going red is a finding, not a smear, and it is the one I did not predict:**
--          its floor rows stay green (20,000 absorbs a 2,000 drop — the floor HIDES the bug) and it
--          fails on its CONTRAST arm instead, `바닥이 천장이 됐다: 16900`. A pin written only on the
--          binding fixture would have stayed green while every runner was underpaid.
--       ⓑ the `greatest(0, …)` clamp dropped → **570/2, red = [R3, R5]** — and R3's message is the
--          bug in one line: `보장이 음수: -2250 · 계획 초과 조기종료가 감봉된다: 21150 < 23400`. Two
--          fixture shapes catch it (A at 4.5km of 3.0, B at 3.0km of 2.0), which is why B is in the
--          matrix at all.
--       ⓒ the `min_fare` floor applied to the `runner_personal` arm → **570/2, red = [R4, R5]**
--          (`중단에 min_fare 바닥이 되살아났다: 20000 (1500 기대)` and, on the 9,900 fixtures,
--          `위임 불일치: 9900/3267 vs 0086=4500/1485`). R4 is exclusive to this one.
--       ⓓ `v_fee := v_gross - round(v_gross × (1 − commission))` — the re-rounded subtraction →
--          **571/1, red = [R5] alone**, and ONLY on the four half-won rows:
--          `4306 vs 4307 · 5494 vs 5495 · 6847 vs 6848`. ₩1. Every other row in the matrix is
--          identical under both formulas, which is the entire reason 13,050 / 16,650 / 20,750 were
--          engineered into the fixtures rather than left to chance — a matrix of round numbers
--          would have proven the fee pin can never see this.
--       ⓔ `grant execute … to authenticated` added → **571/1, red = [R6] alone** (`authenticated`).
--          Nothing else in the harness notices — 99 S1 sweeps anon only, 98 H1 watches search_path.
--          That is trust's detector ③ exactly: the privilege and the protection live in different
--          places, so only a pin aimed AT the privilege can see it move.
--
--   ─── the TypeScript half (`deno test -A supabase/functions/_test/`) ───
--     ⚠ Baseline 185/0. With `settle-run/handler.ts` switched to this function it is **161/24**,
--     because `_test/settle_charge_test.ts` installs the OLD `compute_runner_personal_payout` fake
--     and no `compute_runner_payout` one, so every settle path 500s on `no rpc`. That file was
--     OUTSIDE this slice's allowed surface and is deliberately unchanged — see the slice report.
--     Measured, not guessed: adding a stand-in for this function to `scene()` takes it to 183/2,
--     and the last two are the two tests that install the old fake by name.
set client_min_messages = warning;

-- ---------- suite-local fixtures ----------
create or replace function t_rpay_bk(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid,
                                     p_km numeric, p_addons jsonb, p_base int, p_dist int,
                                     p_addon int, p_min int)
returns uuid language sql as $$
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    addons, base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'active', now() + interval '2 hours', p_km,
          p_addons, p_base, p_dist, p_addon, p_base + p_dist + p_addon, p_min)
  returning id
$$;

-- ═══ THE CAPTURED TABLE (step ②). Do not regenerate — see the header. ═══
create temp table _rpay_expect (
  label text, reason text, km numeric, comm numeric,
  base int, distance int, addon int, guarantee int, gross int, fee int
);
insert into _rpay_expect values
  ('A','completed'      ,0   ,0.33, 9900,     0,    0,    0,  9900, 3267),
  ('A','completed'      ,1.05,0.33, 9900,  3150,    0,    0, 13050, 4307),
  ('A','completed'      ,1.5 ,0.00, 9900,  4500,    0,    0, 14400,    0),
  ('A','completed'      ,1.5 ,0.20, 9900,  4500,    0,    0, 14400, 2880),
  ('A','completed'      ,1.5 ,0.33, 9900,  4500,    0,    0, 14400, 4752),
  ('A','completed'      ,3.0 ,0.33, 9900,  9000,    0,    0, 18900, 6237),
  ('A','completed'      ,4.5 ,0.33, 9900, 13500,    0,    0, 23400, 7722),
  ('A','dog_condition'  ,0   ,0.33, 9900,     0,    0,    0,  9900, 3267),
  ('A','dog_condition'  ,1.5 ,0.33, 9900,  4500,    0,    0, 14400, 4752),
  ('A','dog_condition'  ,3.0 ,0.33, 9900,  9000,    0,    0, 18900, 6237),
  ('A','dog_condition'  ,4.5 ,0.33, 9900, 13500,    0,    0, 23400, 7722),
  ('A','incident'       ,0   ,0.33, 9900,     0,    0,    0,  9900, 3267),
  ('A','incident'       ,1.5 ,0.33, 9900,  4500,    0,    0, 14400, 4752),
  ('A','incident'       ,3.0 ,0.33, 9900,  9000,    0,    0, 18900, 6237),
  ('A','incident'       ,4.5 ,0.33, 9900, 13500,    0,    0, 23400, 7722),
  ('A','owner_forced'   ,0   ,0.33, 9900,     0,    0, 4500, 14400, 4752),
  ('A','owner_forced'   ,1.5 ,0.33, 9900,  4500,    0, 2250, 16650, 5495),
  ('A','owner_forced'   ,3.0 ,0.33, 9900,  9000,    0,    0, 18900, 6237),
  ('A','owner_forced'   ,4.5 ,0.33, 9900, 13500,    0,    0, 23400, 7722),
  ('A','owner_request'  ,0   ,0.33, 9900,     0,    0, 4500, 14400, 4752),
  ('A','owner_request'  ,1.5 ,0.33, 9900,  4500,    0, 2250, 16650, 5495),
  ('A','owner_request'  ,3.0 ,0.33, 9900,  9000,    0,    0, 18900, 6237),
  ('A','owner_request'  ,4.5 ,0.33, 9900, 13500,    0,    0, 23400, 7722),
  ('A','runner_personal',0   ,0.33,    0,     0,    0,    0,     0,    0),
  ('A','runner_personal',1.5 ,0.33,    0,  4500,    0,    0,  4500, 1485),
  ('A','runner_personal',3.0 ,0.33,    0,  9000,    0,    0,  9000, 2970),
  ('A','runner_personal',4.5 ,0.33,    0,  9000,    0,    0,  9000, 2970),
  ('B','completed'      ,1.0 ,0.33, 9900,  3000, 5000,    0, 17900, 5907),
  ('B','completed'      ,3.0 ,0.33, 9900,  9000, 5000,    0, 23900, 7887),
  ('B','dog_condition'  ,1.0 ,0.33, 9900,  3000, 5000,    0, 17900, 5907),
  ('B','dog_condition'  ,3.0 ,0.33, 9900,  9000, 5000,    0, 23900, 7887),
  ('B','incident'       ,1.0 ,0.33, 9900,  3000, 5000,    0, 17900, 5907),
  ('B','incident'       ,3.0 ,0.33, 9900,  9000, 5000,    0, 23900, 7887),
  ('B','owner_forced'   ,1.0 ,0.33, 9900,  3000, 5000, 1500, 19400, 6402),
  ('B','owner_forced'   ,3.0 ,0.33, 9900,  9000, 5000,    0, 23900, 7887),
  ('B','owner_request'  ,1.0 ,0.33, 9900,  3000, 5000, 1500, 19400, 6402),
  ('B','owner_request'  ,3.0 ,0.33, 9900,  9000, 5000,    0, 23900, 7887),
  ('B','runner_personal',1.0 ,0.33,    0,  3000,    0,    0,  3000,  990),
  ('B','runner_personal',3.0 ,0.33,    0,  6000,    0,    0,  6000, 1980),
  ('C','completed'      ,0.5 ,0.33, 9900,  1500,    0,    0, 20000, 6600),
  ('C','completed'      ,1.0 ,0.33, 9900,  3000,    0,    0, 20000, 6600),
  ('C','dog_condition'  ,0.5 ,0.33, 9900,  1500,    0,    0, 20000, 6600),
  ('C','dog_condition'  ,1.0 ,0.33, 9900,  3000,    0,    0, 20000, 6600),
  ('C','incident'       ,0.5 ,0.33, 9900,  1500,    0,    0, 20000, 6600),
  ('C','incident'       ,1.0 ,0.33, 9900,  3000,    0,    0, 20000, 6600),
  ('C','owner_forced'   ,0.5 ,0.33, 9900,  1500,    0,  750, 20750, 6848),
  ('C','owner_forced'   ,1.0 ,0.33, 9900,  3000,    0,    0, 20000, 6600),
  ('C','owner_request'  ,0.5 ,0.33, 9900,  1500,    0,  750, 20750, 6848),
  ('C','owner_request'  ,1.0 ,0.33, 9900,  3000,    0,    0, 20000, 6600),
  ('C','runner_personal',0.5 ,0.33,    0,  1500,    0,    0,  1500,  495),
  ('C','runner_personal',1.0 ,0.33,    0,  3000,    0,    0,  3000,  990);

create temp table _rpay_bk (label text, id uuid);

do $$
declare
  oo uuid; rr uuid; dg uuid; rt uuid; f uuid;
  e record; got record; pay record;
  v_bad text := ''; v_msg text; v_err text; v_n int;
begin
  -- ---------- seed ----------
  oo := t_user('rpay_owner', 'owner');
  rr := t_user('rpay_runner', 'runner');
  dg := t_dog(oo, '지급견');
  rt := t_route('지급 코스');
  insert into _rpay_bk values
    ('A', t_rpay_bk(oo, dg, rt, rr, 3.0, '[]'::jsonb, 7900, 9000, 0, 9900)),
    ('B', t_rpay_bk(oo, dg, rt, rr, 2.0,
        '[{"key":"river","label":"한강","price":3000},{"key":"snack","label":"간식","price":2000}]'::jsonb,
        7900, 6000, 5000, 9900)),
    ('C', t_rpay_bk(oo, dg, rt, rr, 1.0, '[]'::jsonb, 7900, 3000, 0, 20000));

  -- ---------- [R1] the plain arm, at the captured numbers — and the 9,900 that is NOT 7,900 -----
  -- `completed` / `dog_condition` / `incident` all price identically (the reason changes nothing
  -- on the runner's side unless the OWNER caused the end), across the four distance positions and
  -- with addons present and absent.
  begin
    v_bad := ''; v_n := 0;
    for e in select * from _rpay_expect
             where reason in ('completed','dog_condition','incident') and label in ('A','B')
             order by label, reason, km, comm loop
      select id into f from _rpay_bk where label = e.label;
      select * into got from compute_runner_payout(f, e.reason, e.km, e.comm);
      v_n := v_n + 1;
      if (got.base, got.distance, got.addon, got.guarantee, got.gross)
         is distinct from (e.base, e.distance, e.addon, e.guarantee, e.gross) then
        v_bad := v_bad || ' ' || e.label || '/' || e.reason || '/' || e.km || 'km: ('
          || got.base || ',' || got.distance || ',' || got.addon || ',' || got.guarantee || ','
          || got.gross || ') 기대=(' || e.base || ',' || e.distance || ',' || e.addon || ','
          || e.guarantee || ',' || e.gross || ')';
      end if;
    end loop;
    if v_n <> 21 then v_bad := v_bad || ' 케이스 수=' || v_n || ' (21 기대)'; end if;
    -- ① D2, said out loud: the runner's base is the RUNNER's number. Reading `bookings.base_fare`
    --    (7,900 on every fixture here) would satisfy every "is it a constant?" check and underpay
    --    every runner on every run.
    select id into f from _rpay_bk where label = 'A';
    select * into got from compute_runner_payout(f, 'completed', 1.5, 0.33);
    if got.base <> 9900 then v_bad := v_bad || ' base=' || got.base || ' (9900 기대 — 러너 기준)'; end if;
    if got.base = (select base_fare from bookings where id = f)
      then v_bad := v_bad || ' base가 보호자 기본요금과 같아졌다 (D2 붕괴)'; end if;
    -- the addons come from the `addons` ARRAY, not the frozen `addon_fare` column: B's two addons
    -- sum to 5,000 and A has none.
    select id into f from _rpay_bk where label = 'B';
    select * into got from compute_runner_payout(f, 'completed', 1.0, 0.33);
    if got.addon <> 5000 then v_bad := v_bad || ' 애드온=' || got.addon; end if;

    if v_bad = ''
      then call _pass('rpay','R1 기본 지급 — completed·dog_condition·incident 21케이스가 캡처값과 won 단위로 일치(거리 0·미달·정확·초과, 애드온 유무), base는 러너의 9,900이지 보호자의 7,900이 아니다 (D2)');
    else v_msg := v_bad; call _fail('rpay','R1 기본 지급 캡처값', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rpay','R1 기본 지급 캡처값', v_msg);
  end;

  -- ---------- [R2] the min_fare FLOOR — only fixture C can show it ----------
  -- The shipped default is 9,900, which equals the runner base, so on A and B the floor is a
  -- tautology. C's floor is 20,000: 9,900 + 3,000 = 12,900 is under it, so the floor is the answer.
  begin
    v_bad := ''; v_n := 0;
    for e in select * from _rpay_expect
             where reason in ('completed','dog_condition','incident') and label = 'C'
             order by reason, km loop
      select id into f from _rpay_bk where label = e.label;
      select * into got from compute_runner_payout(f, e.reason, e.km, e.comm);
      v_n := v_n + 1;
      if (got.base, got.distance, got.addon, got.guarantee, got.gross)
         is distinct from (e.base, e.distance, e.addon, e.guarantee, e.gross) then
        v_bad := v_bad || ' ' || e.reason || '/' || e.km || 'km: gross=' || got.gross
          || ' 기대=' || e.gross;
      end if;
      -- the floor lifts the TOTAL and leaves the components alone — a floor that rewrote `base`
      -- or `distance` would balance the ledger row against a gross nobody can reconstruct
      if got.base + got.distance + got.addon + got.guarantee > got.gross
        then v_bad := v_bad || ' 구성요소 합이 gross를 넘는다'; end if;
    end loop;
    if v_n <> 6 then v_bad := v_bad || ' 케이스 수=' || v_n || ' (6 기대)'; end if;
    -- ...and it is a FLOOR, not a ceiling: A at 3.0km answers 18,900, far above its 9,900 min_fare.
    select id into f from _rpay_bk where label = 'A';
    select * into got from compute_runner_payout(f, 'completed', 3.0, 0.33);
    if got.gross <> 18900 then v_bad := v_bad || ' 바닥이 천장이 됐다: ' || got.gross; end if;

    if v_bad = ''
      then call _pass('rpay','R2 min_fare는 바닥이다 — 20,000 바닥 예약 6케이스가 캡처값(20,000)과 일치하고 구성요소는 그대로, 9,900 바닥 예약은 18,900을 그대로 지급 (천장이 아니다)');
    else v_msg := v_bad; call _fail('rpay','R2 min_fare 바닥', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rpay','R2 min_fare 바닥', v_msg);
  end;

  -- ---------- [R3] the owner-caused guarantee, and THE CLAMP ----------
  -- Both owner-caused ends pay the remaining half of the PLANNED distance. Above plan there is no
  -- remainder, and without `greatest(0, …)` the "guarantee" turns negative and docks the runner —
  -- the bug the clamp was added for.
  begin
    v_bad := ''; v_n := 0;
    for e in select * from _rpay_expect
             where reason in ('owner_request','owner_forced')
             order by label, reason, km loop
      select id into f from _rpay_bk where label = e.label;
      select * into got from compute_runner_payout(f, e.reason, e.km, e.comm);
      v_n := v_n + 1;
      if (got.base, got.distance, got.addon, got.guarantee, got.gross)
         is distinct from (e.base, e.distance, e.addon, e.guarantee, e.gross) then
        v_bad := v_bad || ' ' || e.label || '/' || e.reason || '/' || e.km || 'km: guarantee='
          || got.guarantee || '/gross=' || got.gross || ' 기대=' || e.guarantee || '/' || e.gross;
      end if;
      if got.guarantee < 0 then v_bad := v_bad || ' 보장이 음수: ' || got.guarantee; end if;
    end loop;
    if v_n <> 16 then v_bad := v_bad || ' 케이스 수=' || v_n || ' (16 기대)'; end if;
    -- the clamp stated as the property it protects: an owner-caused end can never pay LESS than
    -- the same distance under a reason with no guarantee at all.
    select id into f from _rpay_bk where label = 'A';
    declare g_owner int; g_plain int;
    begin
      select gross into g_owner from compute_runner_payout(f, 'owner_request', 4.5, 0.33);
      select gross into g_plain from compute_runner_payout(f, 'completed', 4.5, 0.33);
      if g_owner < g_plain then
        v_bad := v_bad || ' 계획 초과 조기종료가 감봉된다: ' || g_owner || ' < ' || g_plain;
      end if;
    end;

    if v_bad = ''
      then call _pass('rpay','R3 보호자 사유 보장 — owner_request·owner_forced 16케이스가 캡처값과 일치(계획의 남은 절반), 실거리가 계획을 넘으면 보장은 0으로 클램프되고 절대 음수가 되지 않는다 (초과 종료가 감봉이 되던 버그)');
    else v_msg := v_bad; call _fail('rpay','R3 보호자 사유 보장·클램프', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rpay','R3 보호자 사유 보장·클램프', v_msg);
  end;

  -- ---------- [R4] runner_personal — delegated, decomposed, and NOT floored ----------
  -- ⑨a (0086 §A) owns this arm. 0101 §A must ask it, not re-derive it, and must lay the answer out
  -- as all-distance: base 0, addon 0. Writing 9,900 into `base` would put a fee the owner never
  -- paid — and this run never earned — into every earnings breakdown that reads `ledger_items`.
  begin
    v_bad := ''; v_n := 0;
    for e in select * from _rpay_expect where reason = 'runner_personal' order by label, km loop
      select id into f from _rpay_bk where label = e.label;
      select * into got from compute_runner_payout(f, e.reason, e.km, e.comm);
      v_n := v_n + 1;
      if (got.base, got.distance, got.addon, got.guarantee, got.gross)
         is distinct from (e.base, e.distance, e.addon, e.guarantee, e.gross) then
        v_bad := v_bad || ' ' || e.label || '/' || e.km || 'km: (' || got.base || ','
          || got.distance || ',' || got.addon || ',' || got.gross || ') 기대=(' || e.base || ','
          || e.distance || ',' || e.addon || ',' || e.gross || ')';
      end if;
      -- DELEGATION, not duplication: identical to 0086 §A's own answer at every point. A
      -- re-derivation that happens to agree today dies here the first time ⑨a moves.
      select * into pay from compute_runner_personal_payout(f, e.km, e.comm);
      if got.gross <> pay.gross or got.fee <> pay.fee then
        v_bad := v_bad || ' ' || e.label || '/' || e.km || 'km 위임 불일치: ' || got.gross || '/'
          || got.fee || ' vs 0086=' || pay.gross || '/' || pay.fee;
      end if;
    end loop;
    if v_n <> 8 then v_bad := v_bad || ' 케이스 수=' || v_n || ' (8 기대)'; end if;
    -- ③ the floor does NOT apply here, and fixture C is the only place that is visible: a 0.5km
    -- stop on a booking with a 20,000 floor pays 1,500. The floor IS the flat base ⑨a retires.
    select id into f from _rpay_bk where label = 'C';
    select * into got from compute_runner_payout(f, 'runner_personal', 0.5, 0.33);
    if got.gross <> 1500 then
      v_bad := v_bad || ' 중단에 min_fare 바닥이 되살아났다: ' || got.gross || ' (1500 기대)';
    end if;
    -- addons do not ride along on a stop either — B carries 5,000 of them and is paid distance only
    select id into f from _rpay_bk where label = 'B';
    select * into got from compute_runner_payout(f, 'runner_personal', 1.0, 0.33);
    if got.addon <> 0 or got.gross <> 3000
      then v_bad := v_bad || ' 중단에 애드온이 섞였다: ' || got.addon || '/' || got.gross; end if;

    if v_bad = ''
      then call _pass('rpay','R4 runner_personal 위임 — 8케이스가 캡처값과 일치하고 0086 §A의 답과 항등(재유도 아님), base 0·애드온 0·전액이 distance, 20,000 바닥 예약에서도 바닥 미적용 (그 바닥이 ⑨a가 은퇴시킨 정액 base다)');
    else v_msg := v_bad; call _fail('rpay','R4 runner_personal 위임', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rpay','R4 runner_personal 위임', v_msg);
  end;

  -- ---------- [R5] the fee is rounded ONCE ----------
  -- ⑤ `fee = round(gross × commission)`, and the runner's net is the CALLER's subtraction. The
  -- error this pin exists for is computing the net first and subtracting back: off by exactly ₩1
  -- whenever gross × commission lands on a half-won, and invisible on every other row — so the
  -- captured half-won cases (13,050→4,307 · 16,650→5,495 · 20,750→6,848) are load-bearing, not
  -- decoration. Every fee in the matrix is checked, plus the two commission variants.
  begin
    v_bad := ''; v_n := 0;
    for e in select * from _rpay_expect order by label, reason, km, comm loop
      select id into f from _rpay_bk where label = e.label;
      select * into got from compute_runner_payout(f, e.reason, e.km, e.comm);
      v_n := v_n + 1;
      if got.fee <> e.fee then
        v_bad := v_bad || ' ' || e.label || '/' || e.reason || '/' || e.km || 'km@' || e.comm
          || ': fee=' || got.fee || ' 기대=' || e.fee;
      end if;
      -- the law, as an identity that survives every future price change
      if got.fee <> round(got.gross * e.comm)::int then
        v_bad := v_bad || ' ' || e.label || '/' || e.reason || '/' || e.km || 'km 이중 반올림: '
          || got.fee || ' vs ' || round(got.gross * e.comm)::int;
      end if;
      if got.fee > got.gross then v_bad := v_bad || ' 수수료가 총액을 넘는다'; end if;
    end loop;
    if v_n <> 51 then v_bad := v_bad || ' 케이스 수=' || v_n || ' (51 기대)'; end if;
    -- the commission is a PARAMETER, not a constant: the same 14,400 gross at 0% / 20% / 33%
    if (select count(distinct fee) from _rpay_expect where gross = 14400 and reason = 'completed') <> 3
      then v_bad := v_bad || ' 커미션 변주 케이스가 사라졌다'; end if;

    if v_bad = ''
      then call _pass('rpay','R5 수수료는 한 번만 반올림 — 51케이스 fee가 캡처값과 일치하고 round(gross×커미션)과 항등, 반올림 경계(13,050·16,650·20,750)에서도 ±1이 없다 (net은 호출자의 뺄셈이지 두 번째 반올림이 아니다)');
    else v_msg := v_bad; call _fail('rpay','R5 수수료 단일 반올림', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rpay','R5 수수료 단일 반올림', v_msg);
  end;

  -- ---------- [R6] the seal: server-only, and fail-closed ----------
  -- 🔴 trust's plan-review condition. A definer bypasses RLS by construction and this one has NO
  -- party gate — correct, because no client can reach it. But that means the GRANT is the entire
  -- protection: grant `execute` to `authenticated` and it becomes a pricing oracle over every
  -- booking in the table (addons, min_fare, km, and a price), and nothing else in this harness
  -- would notice. The privilege and the protection live in different places, so the pin has to
  -- watch the privilege.
  declare
    fn text := 'compute_runner_payout(uuid,text,numeric,numeric)';
  begin
    v_bad := '';
    if to_regprocedure(fn) is null then v_bad := ' 함수 없음';
    else
      if has_function_privilege('authenticated', fn, 'execute') then v_bad := v_bad || ' authenticated'; end if;
      if has_function_privilege('anon', fn, 'execute') then v_bad := v_bad || ' anon'; end if;
      if not has_function_privilege('service_role', fn, 'execute') then v_bad := v_bad || ' service_role 불가'; end if;
      if not (select prosecdef from pg_proc where oid = to_regprocedure(fn))
        then v_bad := v_bad || ' definer 아님'; end if;
    end if;
    -- positive control: a runner-facing RPC IS callable, or this pin proves nothing
    if not has_function_privilege('authenticated', 'my_ledger_total()', 'execute')
      then v_bad := v_bad || ' 대조군(my_ledger_total) 불가 — 핀이 무의미'; end if;
    -- fail closed on a reason nobody ruled on, and on a booking that does not exist
    select id into f from _rpay_bk where label = 'A';
    begin
      select * into got from compute_runner_payout(f, 'vibes', 1.0, 0.33);
      v_bad := v_bad || ' 미지의 사유가 가격을 받았다';
    exception when others then v_err := sqlerrm;
      if v_err not like '%unknown_end_reason%' then v_bad := v_bad || ' 미지의 사유 코드=' || v_err; end if;
    end;
    begin
      select * into got from compute_runner_payout(gen_random_uuid(), 'completed', 1.0, 0.33);
      v_bad := v_bad || ' 없는 예약이 통과';
    exception when others then v_err := sqlerrm;
      if v_err not like '%not_found%' then v_bad := v_bad || ' 없는 예약 코드=' || v_err; end if;
    end;

    if v_bad = ''
      then call _pass('rpay','R6 봉인 — security definer이면서 service_role 전용(anon·authenticated 거부, 러너 RPC는 그대로 호출 가능한 양성 대조), 미지의 종료 사유는 unknown_end_reason·없는 예약은 not_found로 폐쇄 (파티 게이트가 없으므로 그랜트가 보호의 전부다)');
    else v_msg := v_bad; call _fail('rpay','R6 봉인·실패 폐쇄', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rpay','R6 봉인·실패 폐쇄', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- R7 [0102] — an invalid commission RAISES on BOTH arms. The general arm used to compute
  -- round(gross × 1.0) and hand the runner ₩0 with no error, while 0086 §A raised on the same
  -- input: one function, two answers. `settle_run_tx` commits runner pay FIRST, so that zero
  -- would be committed before anything could object. 0 stays legitimate — a promo runner keeps
  -- everything — so the pin proves the boundary, not merely that something raises.
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    declare v_n int; v_raised int := 0; v_zero_ok boolean := false;
    begin
      -- 1.0 → must raise on the GENERAL arm (the one 0102 fixes)
      begin
        perform * from compute_runner_payout(f, 'completed', 1.5, 1.0);
      exception when others then
        if sqlerrm like '%invalid_commission%' then v_raised := v_raised + 1; end if;
      end;
      -- 1.0 → must still raise on the DELEGATED arm (0086 §A, unchanged — proves no regression)
      begin
        perform * from compute_runner_payout(f, 'runner_personal', 1.5, 1.0);
      exception when others then
        if sqlerrm like '%invalid_commission%' then v_raised := v_raised + 1; end if;
      end;
      -- 0 → must NOT raise. A promo runner keeping 100% is a real configuration.
      begin
        select count(*) into v_n from compute_runner_payout(f, 'completed', 1.5, 0);
        v_zero_ok := (v_n = 1);
      exception when others then v_zero_ok := false;
      end;

      if v_raised = 2 and v_zero_ok then
        call _pass('rpay', 'R7 수수료율 경계 — 1.0은 두 팔 모두 invalid_commission으로 거부(러너에게 ₩0을 조용히 주지 않는다), 0은 정상 통과(프로모 러너)');
      else
        call _fail('rpay', 'R7 수수료율 경계',
          format('raised=%s/2 · zero_ok=%s — 1.0이 통과하면 settle_run_tx가 러너 지급 0원을 먼저 커밋한다', v_raised, v_zero_ok));
      end if;
    end;
  end;

end $$;