-- ═══ 120 G1 / ops-routing / cutover suite — 0084 pins (Sean's rulings, 2026-08-13) ═══
-- Purpose: 0084 turns three of Sean's six rulings into SQL. Two of them REPLACE a shipped
--   provisional (the G1 basis arm, the OPS_PROFILE_ID env var) and one of them exists ONLY to
--   stop a decision from being undone by a one-line UPDATE (the cutover guard). All three are
--   the kind of thing that reverts silently: a rule string is one word, a routing table is one
--   fallback away from looking fine while nobody is told, and a guard is one `update ops_flags`
--   away from irrelevant. These pins hold the new basis arm and its flatness, the reviewable
--   incident waive and its ops arm, the routing table's seal and its class filtering, the cutover
--   setter's refusal, and the club fare's sixth (SQL-side) display.
-- ⚠ Ruling ① was recorded two different ways by two sessions on the same day and Sean confirmed
--   the answer directly: `dog_condition` charges FULL ACTUALS — it is not a special case, and J1
--   pins that as an IDENTITY with `completed` rather than as a literal, so a re-introduced
--   condition arm cannot pass by computing the same number today. The withdrawn reading (base
--   fare, flat) is named in J1's mutation entry because it is the edit somebody will propose
--   again the first time a dog limps at 200m and the owner is billed ₩8,500.
-- Style: sibling of 105-118 — `_pass('goc',…)`/`_fail('goc',…)`, one begin…exception per case.
--   ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
--   Money facts are asserted against LITERALS (105's law): 7,900 is the marketplace owner base
--   after the D2 decoupling, 9,900 is the club base 0081 §A freezes, and both are written out
--   rather than recomputed from the function under test.
-- ⚠ EVERY PIN PROVISIONS ITS OWN FIXTURE — no pin reads a row, a switch, a card or a
--   subscription that a sibling created. That is 117's P2-1 lesson taken literally: a pin there
--   probed a seat an earlier pin had already consumed, so it was measuring an unrelated
--   `not_payable`, and it still went red under mutation only because the earlier pin's failure
--   rolled its block back and restored the fixture. A pin that can be satisfied by another pin's
--   failure is not a pin. Concretely here: J3 mints its own three bookings and owns the cutover
--   switch for the length of its own block; J4 does NOT read J3's rows — it inserts its own
--   payments rows directly, because J4 is about the QUERY and J3 is about the MINT; J7 captures
--   the flag's value at entry rather than assuming J3 restored it; J8 builds its own bookings and
--   deletes them again.
-- ⚠ The cutover switch ships NULL and 116 C22 / 117 restore NULL, so this suite starts
--   pre-cutover. J3 and J7 each set it for themselves and each put it back; the suite's last line
--   restores NULL unconditionally — this suite runs last, and leaving it set would be a lie about
--   the shipped state to anyone reading the database afterwards.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   J1  ← §A-ⓐ: give `dog_condition` a special case again in ANY direction — 0080's
--         `return 0, 'g1_waive'`, the withdrawn base-flat reading (`v_amount := b.base_fare`,
--         `basis 0`, rule `condition_base`), a condition discount, or dropping the ceiling from
--         the arm it now shares with `completed`. The identity arm catches every one of them;
--         the ⓒ literal catches specifically the "surely we shouldn't bill 8,500 for 200m"
--         edit that this pin exists to make somebody argue for out loud            → RED
--   J2  ← §A-ⓑ: give `incident` a nonzero amount, or leave its rule as `g1_waive` /
--         `actual_capped` (the rule string is what §B keys the review marker on, so a
--         renamed incident rule silently turns every waive back into a silent one)       → RED
--   J3  ← §B: delete the `review`/`review_opened_at` object from the mint's raw (the waive is
--         silent again), or key it on `end_reason = 'incident'` instead of on the RULE so a
--         sub-floor waive inherits a case that does not exist                            → RED
--   J4  ← §C: drop the `incident_waive_pending` arm (nobody reads the open reviews, and the
--         waived owner who never disputes a fabricated abort is unobserved), or drop its
--         `review_resolved_at is null` clause (the board can never be cleared), or measure
--         `age` from `created_at` instead of `review_opened_at`                          → RED
--   J5  ← §E: `alter table ops_recipients disable row level security`, or add any policy to
--         it — the roster becomes readable (who is on call) and writable (subscribe yourself
--         to other people's incidents)                                                   → RED
--   J6  ← §E: drop `and r.active` from ops_recipients_for (an unsubscribed operator keeps
--         being paged), drop the `event_class` filter (routing collapses to "tell everyone",
--         which is exactly the pilot behaviour Sean ruled against), or make an unknown class
--         raise instead of returning zero rows (zero rows IS the env-fallback signal — Unit
--         Q's `_shared/ops.ts` reads emptiness, not an error)                             → RED
--   J7  ← §D-ⓑ: delete the `p_when <= now()` refusal, or weaken it to `<` so `now()` itself
--         squeaks through — `= now()` is the literal value 0080 §0d ⑦ used to prescribe and
--         ruling ⑥ overturned, so it is the case that must be refused, not the boundary  → RED
--   J8  ← §D-ⓐ: count cancelled/completed bookings as in-flight (the operator sets the cutover
--         past a booking that ended weeks ago and charges nobody's straddler while a real one
--         slips through), or drop the `km*8+25` duration so the answer is just the latest
--         scheduled_at (a 10km run's last 105 minutes stop counting)                     → RED
--   J9  ← §A/§C/§D/§E: `grant execute … to authenticated` on any of the six server-only
--         surfaces — most sharply `set_payments_live_since`, which a client could then use to
--         start charging everybody, and `ops_recipients_for`, which is a staff roster        → RED
--
--   J10 ← §F: restore 0043:283's '20분 안에 결제하면 자리가 확정돼요 · N원' (a second price
--         disclosure, in a surface no client change can reach, using a 결제 verb for a step
--         where no money moves in either era)                                            → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-13. Method: edit 0084 → stop the server →
--     `rm -rf .pgtest` → full harness → restore → green. (Stopping the server first is not
--     optional: `rm -rf` under a live postmaster deletes the socket it is holding and the NEXT
--     run dies mid-migration with "connection to server on socket … failed", which reads like a
--     migration bug and is not one. Measured twice before the teardown was fixed.)
--     Baseline measured on this branch BEFORE 0084: **451/0** (0082 + suite 118 had already moved
--     it off the 438 the 117 header records). Green with this file: **461/0** (451 + J1-J10).
--     FIVE reverts, every one measured, each reddening exactly the pins that own the rule:
--       ⓐ §A dog_condition given a special case again — the WITHDRAWN base-flat reading
--         (`return base_fare, 0, 'condition_base'`) → **458/3, red = [chg C1, J1, J3]**.
--         J1 reports the whole shape of the disagreement in one line: `컨디션 2.8km=7900/
--         condition_base(basis 0) 같은 거리에서 중단(7900)과 완주(18300)가 다르다 … 200m 중단=
--         7900 (기대 8500) 컨디션 전용 rule이 되살아났다 클럽 200m 중단=9900 (기대 10500)`.
--         116 C1 reports `dog_condition=9900/condition_base` — the amended pin doing exactly the
--         job 0084 §0c claims for it. J3 goes red too, and that is CORRECT rather than coupling:
--         its ⓑ control asserts that a condition abort is an ordinary charge, which is the same
--         rule seen from the mint's side. Three probes of one decision, in three files.
--       ⓑ §B's review object deleted from the mint's raw → **460/1, red = [J3]**, detail
--         `사건 waived에 review 마커 없음 review_opened_at 없음`. J4 stays green because it
--         inserts its own payments rows; before that decoupling this revert would have reddened
--         both and the signature would have stopped naming the mint (117 P2-1's failure mode,
--         avoided by construction rather than by luck).
--       ⓒ §C's `incident_waive_pending` arm deleted → **460/1, red = [J4]**, detail
--         `열린 사건 면제 미포착=0 열린 사건이 0개 팔에 등장 경과 시간=∅`. 116 C11's
--         disjointness assertion stays green (removing an arm cannot create an overlap), which is
--         why J4 carries its own.
--       ⓓ §D-ⓑ's `p_when <= now()` refusal deleted → **460/1, red = [J7]**, detail
--         `과거 시각이 통과 … 거부됐는데 스위치가 움직였다 now()가 통과`. Both halves of the same
--         removal, and the second is the one that matters (`= now()` is the undoing ⑥ names).
--       ⓔ §F's approval copy reverted to 0043:283 → **460/1, red = [J10]**, detail
--         `본문에 요금 자릿수가 있다: 20분 안에 결제하면 자리가 확정돼요 · 24900원 … 본문에 결제
--         주장이 남았다`. The structural arms and the exact-string arm both fire, which is what
--         they are for: one catches a fare coming back under any wording, the other catches a
--         silent rewording.
--     The remaining pins (J2, J5, J6, J8, J9) are NOT machine-proven; each is named above with
--     the single revert that would redden it, and their probe shapes are clones of proven
--     siblings (116 C1 for the basis arms, 116 C15 for the sealed-table probe, 116 C21 for the
--     grant matrix, 117 K8 for the ACL capture-restore read, 117 K6 for the copy probe).
--   ⚠ HONESTY NOTE, structural: `set_payments_live_since` is a SETTER, not a constraint, so
--     `update ops_flags set payments_live_since = now()` still undoes ruling ⑥ and NO pin here
--     can see it. The airtight form is a BEFORE UPDATE trigger, and 0084 §D records why it is not
--     written yet: five shipped pins in suites this slice may not edit (116 C14/C22, 117 K4/K5/K6)
--     deliberately set the flag into the past to simulate the post-cutover era, and a trigger
--     would fail the harness rather than fail a mistake. J7 pins the door; the wall is a follow-up
--     that gives those suites a bypass first.
--   ⚠ HONESTY NOTE, structural: ruling ①'s "verify incident first" has TWO halves and only one is
--     here. The SQL half is J2/J3/J4 — the zero is recorded, marked, and listed. The half that
--     actually prevents the abuse is a refusal list in `settle-run/handler.ts` (Unit Q), because
--     the function whitelists all six `end_reason` values on a public endpoint and an assigned
--     runner can POST `incident` today. Nothing in this harness can see TypeScript. If that
--     refusal is ever removed, every pin in this file stays green and the free-run button is back.
set client_min_messages = warning;

-- ---------- suite-local helpers ----------
-- Own copies rather than 116's t_chg_bk/t_chg_settled: this suite must not depend on which
-- earlier suite happened to define a helper (117's precedent, same argument as its club_flags
-- line). Callers choose every fare column, because the whole point of J1 is that the charge is
-- read out of the booking's own frozen numbers and not out of a live constant.
create or replace function t_goc_bk(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid,
                                    p_status booking_status, p_when timestamptz, p_km numeric,
                                    p_base int, p_dist int, p_addon int)
returns uuid language sql as $$
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, p_status, p_when, p_km,
          p_base, p_dist, p_addon, p_base + p_dist + p_addon, p_base)
  returning id
$$;

-- "This booking was settled" in the only way the mint and §F recognise: a runs row with ended_at.
create or replace function t_goc_settled(p_booking uuid, p_reason text, p_km numeric)
returns void language sql as $$
  insert into runs (booking_id, started_at, ended_at, actual_km, end_reason)
  values (p_booking, now() - interval '40 minutes', now(), p_km, p_reason::end_reason)
$$;

do $$
declare
  oo uuid; oz uuid; rr uuid; dg uuid; dz uuid; rt uuid;
  v_bad text := ''; v_msg text; v_n int; v_err text;
  c record; m record;
  v_prev timestamptz; v_want timestamptz; v_got timestamptz;
begin
  -- ---------- seed (identities only — every pin builds its own rows) ----------
  oo := t_user('goc_oo', 'owner'); oz := t_user('goc_oz', 'owner');
  rr := t_user('goc_rr', 'runner');
  dg := t_dog(oo, '룰링견'); dz := t_dog(oz, '클럽룰링견');
  rt := t_route('룰링 코스');

  -- ---------- [J1] dog_condition is NOT a special case — an abort is billed for what happened ----------
  -- Sean's ruling ①, confirmed directly on 2026-08-13 after two sessions recorded it differently
  -- (one had "base fee only, 7,900 flat"; that reading is withdrawn). The rule is option C: full
  -- actuals, the same path `completed` takes, ceiling included.
  -- The pin is written as an IDENTITY rather than as a pile of literals, because the identity is
  -- the ruling: `dog_condition` and `completed` must produce the same answer on the same fixture
  -- at the same measured distance. A literal-only pin would still pass if somebody re-introduced
  -- a condition arm that happened to compute the same number today and drifted tomorrow.
  --   ⓐ identity with `completed`, on two distances and with the rule string
  --   ⓑ the ceiling still applies (an abort cannot be charged past the quote)
  --   ⓒ the ACCEPTED COST, as a literal: a dog that limps at 200m is billed ₩8,500, and it does
  --      NOT auto-waive — only a sub-₩100 total does. Sean accepted this explicitly; the
  --      mitigation is copy on the run report (0083's surface), not a discount here.
  --   ⓓ no condition-specific rule string exists to grep for — that absence IS the ruling
  --   ⓔ the club consequence (ruling ④): the same abort costs more inside a session, because the
  --      frozen base is 9,900 there and 7,900 outside. Intended, and pinned so it stays a decision.
  begin
    v_bad := '';
    declare
      b_mkt uuid; b_bare uuid; b_club uuid; v_cond int; v_done int;
    begin
      -- marketplace shape: 7,900 base + 15,000 distance over 5.0km + 2,000 addons
      b_mkt := t_goc_bk(oo, dg, rt, rr, 'completed', now() - interval '2 hours', 5.0, 7900, 15000, 2000);
      -- no addons, so the ⓒ literal is the sentence Sean was shown, not an addon-inflated cousin
      b_bare := t_goc_bk(oo, dg, rt, rr, 'completed', now() - interval '2 hours', 5.0, 7900, 15000, 0);
      -- club shape: 0081 §A's insert, literally — 9,900 + (club_fare(5.0) - 9,900) + 0
      b_club := t_goc_bk(oz, dz, rt, rr, 'completed', now() - interval '2 hours', 5.0, 9900, 15000, 0);

      -- ⓐ identity: 7900 + round(15000/5 * 2.8) + 2000 = 7900 + 8400 + 2000 = 18300
      select * into c from compute_owner_charge(b_mkt, 'dog_condition', 2.8);
      v_cond := c.amount;
      if c.amount <> 18300 or c.basis_km <> 2.8 or c.rule <> 'actual_capped'
        then v_bad := v_bad || ' 컨디션 2.8km=' || c.amount || '/' || c.rule
                             || '(basis ' || c.basis_km || ')'; end if;
      select * into c from compute_owner_charge(b_mkt, 'completed', 2.8);
      v_done := c.amount;
      if v_cond <> v_done
        then v_bad := v_bad || ' 같은 거리에서 중단(' || v_cond || ')과 완주(' || v_done || ')가 다르다'; end if;
      select * into c from compute_owner_charge(b_mkt, 'dog_condition', 0.2);
      if c.amount <> (select x.amount from compute_owner_charge(b_mkt, 'completed', 0.2) x)
        then v_bad := v_bad || ' 짧은 거리에서 항등이 깨진다=' || c.amount; end if;
      -- and it MOVES with distance — the withdrawn reading was a flat number, so a pin that only
      -- compared two arms would pass under it too
      if c.amount = v_cond then v_bad := v_bad || ' 거리와 무관한 정액이다 (철회된 해석)'; end if;

      -- ⓑ the ceiling: an overrun abort is still capped at the quote (7900+15000+2000)
      select * into c from compute_owner_charge(b_mkt, 'dog_condition', 9.0);
      if c.amount <> 24900 or c.basis_km <> 5.0
        then v_bad := v_bad || ' 초과거리 중단이 견적을 넘는다=' || c.amount; end if;

      -- ⓒ the accepted cost: 200m on a no-addon 3,000/km booking = 7,900 + 600 = 8,500
      select * into c from compute_owner_charge(b_bare, 'dog_condition', 0.2);
      if c.amount <> 8500 or c.rule <> 'actual_capped'
        then v_bad := v_bad || ' 200m 중단=' || c.amount || '/' || c.rule || ' (기대 8500)'; end if;
      -- explicitly NOT waived: only a sub-₩100 total is, and a base fare is never that small
      if c.amount = 0 then v_bad := v_bad || ' 200m 중단이 면제됐다 (그 결정은 철회됐다)'; end if;

      -- ⓓ no condition-specific rule string anywhere in the arm's answers
      if exists (select 1 from compute_owner_charge(b_mkt, 'dog_condition', 2.8) x
                 where x.rule in ('condition_base', 'g1_waive'))
        then v_bad := v_bad || ' 컨디션 전용 rule이 되살아났다'; end if;

      -- ⓔ ruling ④'s premium follows the frozen base: 9900 + 600 = 10500 vs the bare 8500
      select * into c from compute_owner_charge(b_club, 'dog_condition', 0.2);
      if c.amount <> 10500
        then v_bad := v_bad || ' 클럽 200m 중단=' || c.amount || ' (기대 10500)'; end if;
    end;

    if v_bad = ''
      then call _pass('goc','J1 컨디션 중단은 특별취급 없음 — 같은 픽스처·같은 거리에서 완주와 항등(2.8km 18300/actual_capped)·거리에 따라 움직인다·상한은 그대로(초과 24900)·200m 중단은 8500이고 면제되지 않는다(받아들인 비용, 완화는 리포트 카피)·컨디션 전용 rule 없음·클럽은 동결 base 때문에 10500(메모 ④)');
    else v_msg := v_bad; call _fail('goc','J1 컨디션 중단 실제기준 청구', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('goc','J1 컨디션 중단 실제기준 청구', v_msg);
  end;

  -- ---------- [J2] incident charges nothing, and the rule string says WHY ----------
  -- The amount is 0080's, unchanged, and the reason it must stay 0 is architectural rather than
  -- generous: 0072's `club_incident_settle` already owns an incident's money and quotes
  -- refund_full / settle_measured / pay_full for a human. Charging at settle would pre-empt that
  -- and manufacture the refund post-pay deleted. What is new is that the zero NAMES itself, and
  -- the name is load-bearing: §B keys the review marker on the rule string, so a rename here
  -- silently turns every incident waive back into a silent one.
  begin
    v_bad := '';
    declare
      b_i uuid;
    begin
      b_i := t_goc_bk(oo, dg, rt, rr, 'completed', now() - interval '2 hours', 5.0, 7900, 15000, 2000);
      select * into c from compute_owner_charge(b_i, 'incident', 2.8);
      if c.amount <> 0 or c.basis_km <> 0 or c.rule <> 'incident_pending_review'
        then v_bad := v_bad || ' 사건=' || c.amount || '/' || c.rule; end if;
      -- an overrun cannot make an incident cost money either (the ceiling arm is not involved)
      select * into c from compute_owner_charge(b_i, 'incident', 40.0);
      if c.amount <> 0 then v_bad := v_bad || ' 초과거리 사건=' || c.amount; end if;
      -- the retired provisional is gone from BOTH arms (0080:232 promised g1_waive as the grep
      -- handle for this change; a code path still answering it is a decision Sean overruled)
      if exists (select 1 from compute_owner_charge(b_i, 'incident', 2.8) x where x.rule = 'g1_waive')
        then v_bad := v_bad || ' 사건이 아직 g1_waive'; end if;
      if exists (select 1 from compute_owner_charge(b_i, 'dog_condition', 2.8) x where x.rule = 'g1_waive')
        then v_bad := v_bad || ' 컨디션이 아직 g1_waive'; end if;
      -- and the two arms did not collapse back into one
      if (select x.rule from compute_owner_charge(b_i, 'incident', 2.8) x)
       = (select x.rule from compute_owner_charge(b_i, 'dog_condition', 2.8) x)
        then v_bad := v_bad || ' 두 팔이 같은 rule로 합쳐졌다'; end if;
    end;

    if v_bad = ''
      then call _pass('goc','J2 사건은 0원, 이유를 이름에 담는다 — incident_pending_review(0072가 돈을 판단한다)·거리 초과에도 0·구 g1_waive는 두 팔 모두에서 사라짐·컨디션과 합쳐지지 않음');
    else v_msg := v_bad; call _fail('goc','J2 사건 0원 + 검토 대기 rule', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('goc','J2 사건 0원 + 검토 대기 rule', v_msg);
  end;

  -- ---------- [J3] the mint makes the incident waive REVIEWABLE ----------
  -- Why this is not decoration: a waived owner never disputes a fabricated abort, so waiving
  -- REMOVES the free fraud detector (the card statement). The replacement is a human looking, and
  -- a marker nobody reads is not a human looking — which is why J4 exists in the same file.
  -- Three fixtures, all this pin's own, because the marker's correctness is entirely about which
  -- rows DON'T get it:
  --   ⓐ incident      → waived 0, marked, no ladder
  --   ⓑ dog_condition → a real PENDING charge now, with a ladder, and NO marker (it is not a case)
  --   ⓒ below_pg_minimum → also a waive, also no marker (the marker means "a case is open",
  --      not "a zero happened") — this is the control that catches keying on `amount = 0`
  --      instead of on the rule.
  -- Owns the cutover switch for the length of the block and puts it back: the mints write nothing
  -- while it is NULL, so a pin that inherited it from a sibling would silently measure nothing.
  begin
    v_bad := '';
    declare
      b_i uuid; b_c uuid; b_f uuid; v_raw jsonb;
      -- the condition control's expected pair, in one place. 7900 + round(15000/5 * 1.2) + 2000
      -- = 7900 + 3600 + 2000 = 13500, i.e. exactly what `completed` would charge at 1.2km — J1
      -- owns that identity, this pin only needs a value to recognise the row by.
      v_cond_amount int  := 13500;
      v_cond_rule   text := 'actual_capped';
    begin
      update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

      b_i := t_goc_bk(oo, dg, rt, rr, 'completed', now() - interval '2 hours', 5.0, 7900, 15000, 2000);
      perform t_goc_settled(b_i, 'incident', 1.2);
      b_c := t_goc_bk(oo, dg, rt, rr, 'completed', now() - interval '2 hours', 5.0, 7900, 15000, 2000);
      perform t_goc_settled(b_c, 'dog_condition', 1.2);
      -- implied 2,000/km, so runner_personal at 0.02km is ₩40 — the sub-floor waive
      b_f := t_goc_bk(oo, dg, rt, rr, 'completed', now() - interval '2 hours', 5.0, 9900, 10000, 0);
      perform t_goc_settled(b_f, 'runner_personal', 0.02);

      -- ⓐ the incident waive
      select * into m from mint_settle_charge_intent(b_i, 'incident', 1.2);
      if not coalesce(m.minted, false) or m.status <> 'waived' or m.amount <> 0
        then v_bad := v_bad || ' 사건 민팅=' || coalesce(m.status,'∅') || '/' || coalesce(m.amount::text,'∅'); end if;
      select p.raw into v_raw from payments p where p.id = m.payment_id;
      if (v_raw->>'review') is distinct from 'incident_pending'
        then v_bad := v_bad || ' 사건 waived에 review 마커 없음'; end if;
      if (v_raw->>'review_opened_at') is null
        then v_bad := v_bad || ' review_opened_at 없음';
      elsif (v_raw->>'review_opened_at')::timestamptz > now() + interval '1 minute'
        then v_bad := v_bad || ' review_opened_at이 미래'; end if;
      if v_raw ? 'attempts' then v_bad := v_bad || ' 면제행에 래더(attempts)가 붙었다'; end if;

      -- ⓑ the condition abort is a CHARGE now — pending, base fare, with a ladder, unmarked
      select * into m from mint_settle_charge_intent(b_c, 'dog_condition', 1.2);
      if not coalesce(m.minted, false) or m.status <> 'pending' or m.amount <> v_cond_amount
        then v_bad := v_bad || ' 컨디션 민팅=' || coalesce(m.status,'∅') || '/' || coalesce(m.amount::text,'∅'); end if;
      select p.raw into v_raw from payments p where p.id = m.payment_id;
      if (v_raw->>'rule') is distinct from v_cond_rule
        then v_bad := v_bad || ' 컨디션 rule 미기록=' || coalesce(v_raw->>'rule','∅'); end if;
      -- basis_km records the distance that was actually BILLED, so under ruling ①'s full-actuals
      -- answer it is the measured 1.2km — not 0. A zero here would mean the row is claiming a flat
      -- charge, which is the withdrawn reading.
      if coalesce((v_raw->>'basis_km')::numeric, -1) <> 1.2
        then v_bad := v_bad || ' 컨디션 basis_km=' || coalesce(v_raw->>'basis_km','∅') || ' (기대 1.2 — 실제 청구한 거리)'; end if;
      if not (v_raw ? 'attempts') then v_bad := v_bad || ' 청구행에 래더가 없다 (발송되지 않는다)'; end if;
      if v_raw ? 'review' then v_bad := v_bad || ' 컨디션 청구에 사건 마커가 붙었다'; end if;

      -- ⓒ another waive class, deliberately unmarked
      select * into m from mint_settle_charge_intent(b_f, 'runner_personal', 0.02);
      if not coalesce(m.minted, false) or m.status <> 'waived'
        then v_bad := v_bad || ' 최소금액 민팅=' || coalesce(m.status,'∅'); end if;
      select p.raw into v_raw from payments p where p.id = m.payment_id;
      if (v_raw->>'rule') is distinct from 'below_pg_minimum'
        then v_bad := v_bad || ' 최소금액 rule 미기록'; end if;
      if v_raw ? 'review'
        then v_bad := v_bad || ' 사건이 아닌 면제에 검토 마커가 붙었다 (금액 0에 키를 걸었다)'; end if;

      update ops_flags set payments_live_since = null, updated_at = now();
    end;

    if v_bad = ''
      then call _pass('goc','J3 사건 면제는 검토 대상이 된다 — waived 행에 review=incident_pending + review_opened_at(래더 없음)·컨디션 중단은 이제 7900 pending 청구(래더 있음·마커 없음)·최소금액 면제에도 마커 없음(rule에 키, 금액 0에 키 아님)');
    else v_msg := v_bad; call _fail('goc','J3 사건 면제 검토 마커', v_msg); end if;
  exception when others then
    update ops_flags set payments_live_since = null, updated_at = now();
    v_msg := sqlerrm; call _fail('goc','J3 사건 면제 검토 마커', v_msg);
  end;

  -- ---------- [J4] payments_reconciliation's fifth arm reads the open reviews ----------
  -- The waive's mercy is only honest if somebody is looking at it. Rows are inserted DIRECTLY
  -- rather than minted: this pin is about the QUERY, and going through the mint would make it
  -- fail for J3's reasons as well as its own (117 P2-1). Direct inserts also let the resolved
  -- case exist at all — nothing writes `review_resolved_at` yet (0072's adjudication is the
  -- intended writer), so the only way to pin that the arm CAN be cleared is to write it here.
  begin
    v_bad := '';
    declare
      b_o uuid; b_r uuid; b_w uuid; p_open uuid; p_done uuid; p_plain uuid; v_age interval;
    begin
      b_o := t_goc_bk(oz, dz, rt, rr, 'completed', now() - interval '5 hours', 5.0, 7900, 15000, 0);
      b_r := t_goc_bk(oz, dz, rt, rr, 'completed', now() - interval '5 hours', 5.0, 7900, 15000, 0);
      b_w := t_goc_bk(oz, dz, rt, rr, 'completed', now() - interval '5 hours', 5.0, 7900, 15000, 0);

      -- ⓐ an open case, opened three hours ago
      insert into payments (booking_id, order_id, amount, status, raw)
      values (b_o, 'ord_goc_review_open', 0, 'waived',
              jsonb_build_object('kind','settle_charge','rule','incident_pending_review',
                                 'end_reason','incident','review','incident_pending',
                                 'review_opened_at', now() - interval '3 hours'))
      returning id into p_open;
      -- ⓑ the same row after a human closed it
      insert into payments (booking_id, order_id, amount, status, raw)
      values (b_r, 'ord_goc_review_done', 0, 'waived',
              jsonb_build_object('kind','settle_charge','rule','incident_pending_review',
                                 'end_reason','incident','review','incident_pending',
                                 'review_opened_at', now() - interval '3 hours',
                                 'review_resolved_at', now() - interval '1 hour'))
      returning id into p_done;
      -- ⓒ a waive that is not a case at all
      insert into payments (booking_id, order_id, amount, status, raw)
      values (b_w, 'ord_goc_review_none', 0, 'waived',
              jsonb_build_object('kind','settle_charge','rule','below_pg_minimum',
                                 'end_reason','runner_personal'))
      returning id into p_plain;

      select count(*) into v_n from payments_reconciliation()
        where kind = 'incident_waive_pending' and payment_id = p_open;
      if v_n <> 1 then v_bad := v_bad || ' 열린 사건 면제 미포착=' || v_n; end if;
      select count(*) into v_n from payments_reconciliation()
        where kind = 'incident_waive_pending' and payment_id = p_done;
      if v_n <> 0 then v_bad := v_bad || ' 판단이 끝난 행이 아직 보드에 있다'; end if;
      select count(*) into v_n from payments_reconciliation()
        where kind = 'incident_waive_pending' and payment_id = p_plain;
      if v_n <> 0 then v_bad := v_bad || ' 사건이 아닌 면제가 보드에 올라왔다'; end if;
      -- the open row appears under this arm and NO other (it is a waive; nothing else reads waived)
      select count(*) into v_n from payments_reconciliation() where payment_id = p_open;
      if v_n <> 1 then v_bad := v_bad || ' 열린 사건이 ' || v_n || '개 팔에 등장'; end if;

      -- age is the age of the REVIEW, not of the row: the operator's question is "how long has
      -- this been waiting on me". Both rows were created just now; only review_opened_at is old.
      select r.age into v_age from payments_reconciliation() r
        where r.kind = 'incident_waive_pending' and r.payment_id = p_open;
      if v_age is null or v_age < interval '2 hours' or v_age > interval '4 hours'
        then v_bad := v_bad || ' 경과 시간=' || coalesce(v_age::text,'∅') || ' (검토 시작 기준 약 3시간)'; end if;

      -- five arms, still disjoint, measured across the whole query (116 C11's idiom)
      select count(*) into v_n from (
        select payment_id from payments_reconciliation() group by payment_id having count(*) > 1
      ) d;
      if v_n <> 0 then v_bad := v_bad || ' 두 팔에 동시 등장하는 행 ' || v_n || '개'; end if;

      -- probe debris out — a suite that leaves money-shaped rows on the ops board is a trap for
      -- the next author (117 P3-2's argument, same shape)
      delete from payments where id in (p_open, p_done, p_plain);
    end;

    if v_bad = ''
      then call _pass('goc','J4 조정 질의 다섯 번째 팔 — 열린 사건 면제는 incident_waive_pending으로 보이고(경과는 검토 시작 기준), 판단이 끝난 행·사건 아닌 면제는 빠지며, 다섯 팔은 여전히 서로소');
    else v_msg := v_bad; call _fail('goc','J4 조정 질의 사건 면제 팔', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('goc','J4 조정 질의 사건 면제 팔', v_msg);
  end;

  -- ---------- [J5] ops_recipients is SEALED (116 C15's shape, third sealed table) ----------
  -- A client READ is a staff roster; a client WRITE is a subscription to other people's
  -- incidents. Neither has a surface. Probed with a real row present, so "0 rows" is a seal
  -- rather than an empty table.
  begin
    v_bad := '';
    declare
      v_ops uuid; v_n2 int;
    begin
      v_ops := t_user('goc_ops1', 'owner');
      insert into ops_recipients (profile_id, event_class) values (v_ops, 'charge_ladder_exhausted');

      if not exists (select 1 from pg_class where relname = 'ops_recipients' and relrowsecurity)
        then v_bad := v_bad || ' RLS off'; end if;
      select count(*) into v_n from pg_policies where tablename = 'ops_recipients';
      if v_n <> 0 then v_bad := v_bad || ' 정책 ' || v_n || '개 (0이어야 한다)'; end if;

      perform set_config('request.jwt.claim.sub', v_ops::text, false);
      begin
        set local role authenticated;
        select count(*) into v_n from ops_recipients;
        reset role;
        -- even the SUBSCRIBER themselves cannot read the roster
        if v_n <> 0 then v_bad := v_bad || ' 당사자에게 ' || v_n || '행'; end if;
      exception when others then reset role; v_bad := v_bad || ' authenticated 읽기 프로브 오류';
      end;
      reset role;
      begin
        set local role anon;
        perform set_config('request.jwt.claim.sub', '', true);
        select count(*) into v_n2 from ops_recipients;
        reset role;
        if v_n2 <> 0 then v_bad := v_bad || ' anon에게 ' || v_n2 || '행'; end if;
      exception when others then reset role; v_bad := v_bad || ' anon 읽기 프로브 오류';
      end;
      reset role;
      -- writes: insert must raise, update/delete must touch nothing
      perform set_config('request.jwt.claim.sub', oo::text, false);
      begin
        set local role authenticated;
        insert into ops_recipients (profile_id, event_class) values (oo, 'charge_ladder_exhausted');
        v_bad := v_bad || ' 클라 insert:통과 (스스로를 구독할 수 있다)';
        reset role;
      exception when others then reset role;
      end;
      reset role;
      begin
        set local role authenticated;
        update ops_recipients set active = false;
        if found then v_bad := v_bad || ' 클라 update:행변경 (남의 알림을 끌 수 있다)'; end if;
        reset role;
      exception when others then reset role;
      end;
      reset role;
      begin
        set local role authenticated;
        delete from ops_recipients;
        if found then v_bad := v_bad || ' 클라 delete:행삭제'; end if;
        reset role;
      exception when others then reset role;
      end;
      reset role;
      perform set_config('request.jwt.claim.sub', '', false);
      -- and the row this pin planted is still exactly as it was
      if not exists (select 1 from ops_recipients where profile_id = v_ops and active)
        then v_bad := v_bad || ' 구독 행이 클라 쓰기로 움직였다'; end if;
      delete from ops_recipients where profile_id = v_ops;
    end;

    if v_bad = ''
      then call _pass('goc','J5 ops_recipients 봉인 — RLS on·정책 0·anon/authenticated/당사자 전부 0행·insert/update/delete 거부 (명단은 클라 사실이 아니고, 쓰기는 남의 사건 구독이다)');
    else v_msg := v_bad; call _fail('goc','J5 ops_recipients 봉인', v_msg); end if;
  exception when others then reset role; perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('goc','J5 ops_recipients 봉인', v_msg);
  end;

  -- ---------- [J6] ops_recipients_for — per-class routing, active only, empty is an answer ----------
  -- Sean ruled C over A/B because "full scale" is about ROUTING, not plurality: one operator
  -- subscribes to money, another to safety, without a code change. So the pin is not "it returns
  -- rows", it is "it returns THESE rows and not the others".
  begin
    v_bad := '';
    declare
      op_a uuid; op_b uuid; op_gone uuid; v_first uuid;
    begin
      op_a := t_user('goc_ops_a', 'owner');
      op_b := t_user('goc_ops_b', 'owner');
      op_gone := t_user('goc_ops_gone', 'owner');
      -- created_at is the documented order, so A is planted first and explicitly older
      insert into ops_recipients (profile_id, event_class, created_at)
      values (op_a, 'charge_ladder_exhausted', now() - interval '2 days');
      insert into ops_recipients (profile_id, event_class, created_at)
      values (op_b, 'charge_ladder_exhausted', now() - interval '1 day');
      insert into ops_recipients (profile_id, event_class) values (op_b, 'incident_waive_pending');

      -- ⓐ two recipients on one class, oldest subscription first
      select count(*) into v_n from ops_recipients_for('charge_ladder_exhausted')
        where ops_recipients_for in (op_a, op_b);
      if v_n <> 2 then v_bad := v_bad || ' 두 수신자 라우팅=' || v_n; end if;
      select x into v_first from ops_recipients_for('charge_ladder_exhausted') x limit 1;
      if v_first is distinct from op_a then v_bad := v_bad || ' 순서가 구독 순이 아니다'; end if;

      -- ⓑ class filtering — the whole point of the table
      select count(*) into v_n from ops_recipients_for('incident_waive_pending');
      if v_n <> 1 then v_bad := v_bad || ' 다른 클래스 수신자 수=' || v_n; end if;
      if exists (select 1 from ops_recipients_for('incident_waive_pending') x where x = op_a)
        then v_bad := v_bad || ' 구독하지 않은 클래스로 라우팅됐다'; end if;

      -- ⓒ active=false unsubscribes without losing the row (who was on call is an audit fact)
      update ops_recipients set active = false where profile_id = op_a and event_class = 'charge_ladder_exhausted';
      if exists (select 1 from ops_recipients_for('charge_ladder_exhausted') x where x = op_a)
        then v_bad := v_bad || ' 비활성 수신자가 계속 호출된다'; end if;
      if not exists (select 1 from ops_recipients where profile_id = op_a and not active)
        then v_bad := v_bad || ' 비활성화가 행을 지웠다 (감사 사실 유실)'; end if;

      -- ⓓ nobody subscribed = ZERO ROWS, not an error. That emptiness IS the signal Unit Q's
      -- _shared/ops.ts reads to fall back to OPS_PROFILE_ID; a raise here would take the fallback
      -- with it and turn a mis-provisioned table into silence.
      select count(*) into v_n from ops_recipients_for('settled_without_payment');
      if v_n <> 0 then v_bad := v_bad || ' 구독자 없는 클래스가 ' || v_n || '행'; end if;
      select count(*) into v_n from ops_recipients_for('no_such_event_class_at_all');
      if v_n <> 0 then v_bad := v_bad || ' 존재하지 않는 클래스가 ' || v_n || '행'; end if;

      -- ⓔ a departed operator stops being paged (on delete cascade)
      insert into ops_recipients (profile_id, event_class) values (op_gone, 'enroute_comp_failed');
      delete from profiles where id = op_gone;
      if exists (select 1 from ops_recipients where profile_id = op_gone)
        then v_bad := v_bad || ' 삭제된 프로필의 구독이 남았다'; end if;

      delete from ops_recipients where profile_id in (op_a, op_b);
    end;

    if v_bad = ''
      then call _pass('goc','J6 이벤트 클래스 라우팅 — 한 클래스에 두 수신자(구독 순)·다른 클래스는 자기 사람만·active=false는 행을 남기고 호출만 끊는다·구독자 없는 클래스는 0행(예외 아님 — 그 비어 있음이 env 폴백 신호다)·프로필 삭제는 구독까지 정리');
    else v_msg := v_bad; call _fail('goc','J6 이벤트 클래스 라우팅', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('goc','J6 이벤트 클래스 라우팅', v_msg);
  end;

  -- ---------- [J7] set_payments_live_since refuses the past — ruling ⑥, executable ----------
  -- Sean's words: "a decision that lives only in a memo is one `update ops_flags set … = now()`
  -- away from being undone." `= now()` is therefore the case that must be REFUSED, not the
  -- boundary that squeaks through — 0080 §0d ⑦ literally prescribed that statement, and the
  -- adversarial round executed what it does: a card-less owner confirmed a club seat pre-flip,
  -- the switch was set to now(), the run settled, and a 24,900 pending intent was minted against
  -- an owner with zero cards, which dispatches, fails, and locks the account.
  -- Captures the flag at entry rather than assuming a sibling restored it.
  begin
    v_bad := '';
    select f.payments_live_since into v_prev from ops_flags f where f.id;

    -- ⓐ a past timestamp
    v_err := '';
    begin
      perform set_payments_live_since(now() - interval '1 day');
      v_bad := v_bad || ' 과거 시각이 통과';
    exception when others then v_err := sqlerrm;
    end;
    if v_err <> 'cutover_must_be_future' then v_bad := v_bad || ' 과거 거부 코드=' || coalesce(nullif(v_err,''),'∅'); end if;
    select f.payments_live_since into v_got from ops_flags f where f.id;
    if v_got is distinct from v_prev then v_bad := v_bad || ' 거부됐는데 스위치가 움직였다'; end if;

    -- ⓑ now() itself — the exact statement ruling ⑥ overturned
    v_err := '';
    begin
      perform set_payments_live_since(now());
      v_bad := v_bad || ' now()가 통과';
    exception when others then v_err := sqlerrm;
    end;
    if v_err <> 'cutover_must_be_future' then v_bad := v_bad || ' now() 거부 코드=' || coalesce(nullif(v_err,''),'∅'); end if;

    -- ⓒ a future timestamp is accepted and actually lands (else ⓐⓑ pass by refusing everything)
    v_want := now() + interval '30 days';
    if set_payments_live_since(v_want) is distinct from v_want
      then v_bad := v_bad || ' 반환값이 설정값과 다르다'; end if;
    select f.payments_live_since into v_got from ops_flags f where f.id;
    if v_got is distinct from v_want then v_bad := v_bad || ' 미래 시각이 저장되지 않았다'; end if;

    -- ⓓ NULL is accepted — turning charging OFF is the emergency lever and the safe direction;
    -- refusing it would leave a raw UPDATE as the only way to stop the machine, which is the
    -- habit this function exists to replace.
    if set_payments_live_since(null) is not null then v_bad := v_bad || ' NULL 반환이 NULL이 아니다'; end if;
    select f.payments_live_since into v_got from ops_flags f where f.id;
    if v_got is not null then v_bad := v_bad || ' 끄기가 먹히지 않았다'; end if;

    -- put back whatever this suite inherited
    update ops_flags set payments_live_since = v_prev, updated_at = now();

    if v_bad = ''
      then call _pass('goc','J7 컷오버 세터 — 과거 시각도 now()도 cutover_must_be_future로 거부(스위치 불변)·미래 시각은 저장·NULL(끄기)은 허용 (메모만으로 사는 결정은 update 한 줄 앞에 있다)');
    else v_msg := v_bad; call _fail('goc','J7 컷오버 세터', v_msg); end if;
  exception when others then
    update ops_flags set payments_live_since = v_prev, updated_at = now();
    v_msg := sqlerrm; call _fail('goc','J7 컷오버 세터', v_msg);
  end;

  -- ---------- [J8] longest_inflight_booking_end — the number ⑥ needs to be usable ----------
  -- A guard that refuses the past is only actionable if the operator can compute the right
  -- future. Global max by construction, so this pin plants a booking far beyond anything any
  -- other suite leaves behind and asserts the answer IS that booking's end — a LITERAL 105
  -- minutes for a 10km run (10*8+25), computed by hand rather than from the function's own
  -- formula (117 P3-1's tautology lesson).
  begin
    v_bad := '';
    declare
      b_live uuid; b_short uuid; b_dead uuid; v_anchor timestamptz;
    begin
      v_anchor := date_trunc('hour', now()) + interval '400 days';
      -- 10.0km → 10*8+25 = 105 minutes of run window
      b_live := t_goc_bk(oo, dg, rt, rr, 'confirmed', v_anchor, 10.0, 7900, 30000, 0);
      -- a shorter run at the SAME instant must not win — the duration is part of the answer
      b_short := t_goc_bk(oo, dg, rt, rr, 'matching', v_anchor, 2.0, 7900, 6000, 0);
      -- the furthest-out booking, still LIVE for now: it must dominate while it is confirmed and
      -- disappear from the answer the moment it is cancelled. Probed in that direction because
      -- the transition map refuses `cancelled_owner → confirmed` (0066 §1) — a resurrection
      -- fixture is not merely artificial here, it is illegal, and the legal direction pins the
      -- same claim: the status filter, not the fixture's ordering, is what produces the answer.
      b_dead := t_goc_bk(oz, dz, rt, rr, 'confirmed', v_anchor + interval '100 days', 10.0, 7900, 30000, 0);

      v_got := longest_inflight_booking_end();
      if v_got is distinct from v_anchor + interval '100 days' + interval '105 minutes'
        then v_bad := v_bad || ' 가장 먼 진행중 예약이 답이 아니다=' || coalesce(v_got::text,'∅'); end if;

      update bookings set status = 'cancelled_owner' where id = b_dead;
      v_got := longest_inflight_booking_end();
      if v_got is distinct from v_anchor + interval '105 minutes'
        then v_bad := v_bad || ' 최장 진행중 종료=' || coalesce(v_got::text,'∅')
                             || ' (기대 ' || (v_anchor + interval '105 minutes')::text || ')'; end if;
      if v_got is not null and v_got <= now() then v_bad := v_bad || ' 과거를 돌려줬다'; end if;

      -- clean the 400-day fixtures out: they are the global maximum of every later reader
      delete from bookings where id in (b_live, b_short, b_dead);
    end;

    if v_bad = ''
      then call _pass('goc','J8 최장 진행중 예약 종료 — 예정 시각 + (km*8+25)분 리터럴 105분·같은 시각의 짧은 러닝은 이기지 못함·가장 먼 예약을 취소하면 답이 그만큼 당겨진다(취소는 진행중이 아니다) (⑥의 컷오버 값을 사람이 계산할 수 있게 하는 질의)');
    else v_msg := v_bad; call _fail('goc','J8 최장 진행중 예약 종료', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('goc','J8 최장 진행중 예약 종료', v_msg);
  end;

  -- ---------- [J9] grant matrix — everything 0084 adds or recreates is server-only ----------
  -- A definer bypasses RLS by construction, so the execute grant is the whole seal. The sharpest
  -- two are new in this file: `set_payments_live_since` would let a client START CHARGING
  -- EVERYBODY, and `ops_recipients_for` is a staff roster. The three recreated ones are here
  -- because `create or replace` is exactly where an inherited ACL goes missing (116 C21's
  -- argument about sweep_stale_payment_intents, same hazard, this file's three).
  declare
    fns text[] := array[
      'set_payments_live_since(timestamptz)',
      'longest_inflight_booking_end()',
      'ops_recipients_for(text)',
      'compute_owner_charge(uuid,text,numeric)',
      'mint_settle_charge_intent(uuid,text,numeric)',
      'payments_reconciliation()'];
    f text;
  begin
    v_bad := '';
    foreach f in array fns loop
      if to_regprocedure(f) is null then v_bad := v_bad || ' ' || f || ':없음'; continue; end if;
      if has_function_privilege('authenticated', f, 'execute') then v_bad := v_bad || ' ' || f || ':authenticated'; end if;
      if has_function_privilege('anon', f, 'execute') then v_bad := v_bad || ' ' || f || ':anon'; end if;
      if has_function_privilege('public', f, 'execute') then v_bad := v_bad || ' ' || f || ':public'; end if;
      if not has_function_privilege('service_role', f, 'execute') then v_bad := v_bad || ' ' || f || ':service_role 불가'; end if;
    end loop;
    -- positive control: the client RPCs next door are STILL callable, so this pin is measuring a
    -- seal rather than a broken probe
    if not has_function_privilege('authenticated', 'my_unsettled_charge()', 'execute')
      then v_bad := v_bad || ' my_unsettled_charge:authenticated 불가 (프로브가 깨졌다)'; end if;
    if not has_function_privilege('authenticated', 'my_billing_card()', 'execute')
      then v_bad := v_bad || ' my_billing_card:authenticated 불가 (프로브가 깨졌다)'; end if;

    if v_bad = ''
      then call _pass('goc','J9 권한 매트릭스 — 0084이 만들거나 재정의한 6종 전부 service_role 전용(컷오버 세터·운영 명단·기준표·민팅·조정 질의), 클라 RPC 2종은 그대로 authenticated (양성 대조)');
    else v_msg := v_bad; call _fail('goc','J9 권한 매트릭스', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('goc','J9 권한 매트릭스', v_msg);
  end;

  -- ---------- [J10] the sixth club price display, and it is in a notification ----------
  -- Ruling ④: keep 9,900, disclose it ONCE at the join/consent moment. Five of the six displays
  -- are React (the session screen's big number, CTA, '승인 시 가격', status line, pay sheet) and
  -- the client unit owns them. The sixth is `session_approve_dog`'s owner notification, and no
  -- client change can reach it — the app renders notification bodies verbatim and 0024 pushes
  -- them to the lock screen, so a fare in there is a second disclosure on a schedule nobody
  -- controls. It also used the '결제' verb at a step where no money moves in either era (0081 §B
  -- retired the same claim from the confirmation notification one step later).
  -- Asserted STRUCTURALLY — no 3+ digit run, no 'N원', no '결제' — rather than only against the
  -- exact new sentence: the pin must survive a copy edit and still catch a fare coming back, and
  -- "there is money in the body" is the property, not "the body is this string". The exact string
  -- is asserted too, so a silently reworded sentence is still visible.
  -- Its own club, session, host, runners and dogs, like every pin in this file.
  begin
    v_bad := '';
    declare
      hh uuid; r2 uuid; ow uuid; d_ok uuid; d_no uuid;
      v_club uuid; v_sess uuid; sd_ok uuid; sd_no uuid; v_body text;
    begin
      update club_flags set enabled = true where name = 'club_delegation_v2';
      hh := t_user('goc_hh', 'runner'); update runners set tier = 'veteran' where profile_id = hh;
      r2 := t_user('goc_r2', 'runner'); update runners set tier = 'veteran' where profile_id = r2;
      ow := t_user('goc_cow', 'owner');
      d_ok := t_dog(ow, '승인견'); d_no := t_dog(ow, '거절견');

      perform set_config('request.jwt.claim.sub', hh::text, false);
      v_club := club_request_district('룰링동');
      perform club_claim_host(v_club);
      v_sess := club_create_session(v_club, now() + interval '30 hours', '룰링 집결지', rt, 8, 'mixed');
      perform session_runner_commit(v_sess);
      perform set_config('request.jwt.claim.sub', r2::text, false);
      perform session_runner_commit(v_sess);

      perform set_config('request.jwt.claim.sub', ow::text, false);
      sd_ok := session_delegate_dog(v_sess, d_ok, t_consent());
      sd_no := session_delegate_dog(v_sess, d_no, t_consent());
      perform set_config('request.jwt.claim.sub', hh::text, false);
      perform session_approve_dog(sd_ok, true);
      perform session_approve_dog(sd_no, false);
      perform set_config('request.jwt.claim.sub', '', false);

      select n.body into v_body from notifications n
        where n.profile_id = ow and n.title = '위탁 승인 — 결제 대기' and n.ref_id = v_sess;
      if v_body is null then v_bad := v_bad || ' 승인 알림이 없다 (프로브가 깨졌다)';
      else
        -- "no digits at all" would be the cleanest rule and it is the wrong one: the sentence
        -- legitimately says "20분". A fare is a 3+ digit run (`club_fare` returns 9,900 upward and
        -- the SQL concatenated it uncommaed as e.g. 24900), and the hold duration is two digits —
        -- so a 3-digit floor separates the money from the minutes without banning arithmetic.
        if v_body ~ '[0-9]{3,}' then v_bad := v_bad || ' 본문에 요금 자릿수가 있다: ' || v_body; end if;
        if v_body ~ '[0-9][ ]*원' then v_bad := v_bad || ' 본문에 N원이 있다: ' || v_body; end if;
        if v_body like '%결제%' then v_bad := v_bad || ' 본문에 결제 주장이 남았다'; end if;
        if v_body like '%원%' then v_bad := v_bad || ' 본문에 요금 단위가 남았다'; end if;
        if v_body <> '20분 안에 자리를 확정하면 돼요'
          then v_bad := v_bad || ' 본문이 조용히 바뀌었다: ' || v_body; end if;
      end if;

      -- behaviour preservation: 0043's approval still opens the 20-minute hold, and the rejection
      -- branch and its sentence are untouched (the reproduction changed one line, not the flow)
      if (select approval from session_dogs where id = sd_ok) <> 'approved'
        then v_bad := v_bad || ' 승인이 기록되지 않았다'; end if;
      if (select hold_status from session_dogs where id = sd_ok) <> 'active'
        then v_bad := v_bad || ' 20분 홀드가 열리지 않았다'; end if;
      if (select hold_expires_at from session_dogs where id = sd_ok) <= now()
        then v_bad := v_bad || ' 홀드 만료가 과거다'; end if;
      if (select approval from session_dogs where id = sd_no) <> 'rejected'
        then v_bad := v_bad || ' 거절 분기가 깨졌다'; end if;
      if not exists (select 1 from notifications where profile_id = ow and title = '위탁 신청 거절'
                     and body = '이번 세션에는 함께하지 못하게 됐어요')
        then v_bad := v_bad || ' 거절 문장이 바뀌었다'; end if;
    end;

    if v_bad = ''
      then call _pass('goc','J10 승인 알림에서 요금·결제 제거 (메모 ④의 여섯 번째 노출면) — 본문에 요금 자릿수도 N원도 ''결제''도 없고 "20분 안에 자리를 확정하면 돼요"뿐(앱은 알림 본문을 그대로 렌더한다)·20분 홀드와 거절 분기는 0043 그대로');
    else v_msg := v_bad; call _fail('goc','J10 승인 알림 요금 제거', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('goc','J10 승인 알림 요금 제거', v_msg);
  end;

  -- restore the SHIPPED default (charging off) — the state 0080 leaves behind, and the state
  -- anyone reading this database after the harness should see. Unconditional: J3 and J7 each put
  -- it back themselves, and this line is what covers the path where one of them died first.
  update ops_flags set payments_live_since = null, updated_at = now();
  perform set_config('request.jwt.claim.sub', '', false);
end $$;
