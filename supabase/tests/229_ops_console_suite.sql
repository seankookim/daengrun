-- ═══ 229 — 0198: the payout loop becomes operable from a phone ════════════════════════════════
-- ═══        0198-M1 · M2 · D1 · D2 · G1 · S1, tag `opc`                                    ═══
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a
-- pin written while staring at a mutation tends to assert what that mutation broke rather than
-- the property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · M1 `ops_me()` answers about the CALLER and only the caller. Five caller shapes, five
--        distinct answers: an active `payout_due` operator is `is_ops = true` with that class in
--        `kinds`; an INACTIVE row is `false` and the class is ABSENT from `kinds`; an operator for
--        ANOTHER class is `false` with that other class PRESENT in `kinds`; an ordinary runner is
--        `false` with `kinds = '{}'` (an empty array, never NULL); no caller at all raises
--        `not_signed_in` rather than answering `false`.
--   · M2 🔴 **`is_ops` IS THE GATE'S OWN ANSWER — in BOTH directions.** For every caller shape,
--        `ops_me().is_ops` is TRUE exactly when `ops_payouts_due()` admits that same caller and
--        FALSE exactly when it raises `not_ops`. This is the no-dead-button law as a measurement:
--        a console entry drawn on a check that disagrees with the door behind it is a button that
--        opens onto a refusal. Both directions matter — an `is_ops` hard-wired true and one
--        hard-wired false each satisfy exactly one of them.
--   · D1 `ops_runner_payout_detail(p_runner)` returns exactly the rows `ops_payouts_due()` counted
--        for that runner: a PAID row is excluded, a row whose booking still has an OPEN run is
--        excluded, another runner's row is excluded, and Σ `net_won` **equals** that runner's
--        `unpaid_net_won` to the won. A negative row is INCLUDED (0186 §B's `having sum > 0` is a
--        per-RUNNER clause and dropping an individual negative row would let the tickable rows sum
--        to more than the total). A cancellation-compensation row — no `runs` row at all — is
--        present with `cancel_comp = true` and a NULL `settled_at`.
--   · D2 🔴 **THE CONSOLE LOOP CLOSES.** The ids this function returns are accepted by
--        `ops_record_manual_payout` as `p_ledger_item_ids`, the sum of the returned `net_won` is
--        accepted as `p_amount_won`, and after the write those rows are GONE from a second read
--        while the untouched rows remain. A sum that is wrong by one won is refused
--        `amount_mismatch` and writes nothing — the client computing the number does not soften
--        0186 §C's equality (0198 §0b).
--   · G1 **PARTY BEFORE READ.** A runner, a signed-in stranger, an INACTIVE ops row and an ops row
--        for ANOTHER class all get `not_ops` from `ops_runner_payout_detail` — and **a runner who
--        exists and a uuid that is nobody answer identically**, which is the only arm that can
--        show the gate runs before the read. A NULL runner also answers `not_ops`, not
--        `no_runner`. No caller ⇒ `not_signed_in`. An ACTIVE operator passes (the control without
--        which the pin is satisfied by refusing everyone). `no_runner` is reachable for an
--        operator, so the word is not dead.
--   · S1 Deployed shape: two definers, in-body `search_path`, ACL by EFFECTIVE privilege in both
--        directions, `ops_me` takes ZERO arguments (0198 §0d's structural defence), and the
--        comment-STRIPPED source showing the ops gate ahead of both the read and the `no_runner`
--        check, 0186's predicate carried textually, and `is_ops` computed through
--        `ops_recipients_for` rather than re-derived from `kinds`. NO-FUNCTION / NO-SOURCE arms
--        fail loudly, because `position(… in NULL)` is NULL and every bare `IF` over it is silent.
--
-- ─── FIXTURE NOTES ───
--  ① Every count and every sum in this file is SCOPED to this suite's own runners. `ledger_items`
--     and `payouts` are written by a dozen other suites in the same database, so a global figure
--     would measure the harness rather than this slice (217's note ⑥).
--  ② The world is built as the table owner (the harness default) so `status` and dates can be set
--     freely; every ASSERTION about the product goes through the RPC with `request.jwt.claim.sub`
--     set, which is how a real caller arrives.
--  ③ `request.jwt.claim.sub` is cleared EXPLICITLY for the no-caller arms — a leftover claim makes
--     `not_signed_in` unreachable and the arm then passes for the wrong reason.
--  ④ D2 writes a real payout, so it runs LAST among the behavioural pins and D1 reads its subject
--     before that write lands. The one row D2 consumes belongs to a runner no other pin sums.
--
-- ─── MUTATION MAP — MEASURED 2026-09-22 against these exact files, never predicted ───
-- Lab: a copy of `supabase/` OUTSIDE the worktree (229 md5-identical to the committed file,
-- verified both ways), every plant restored from pristine first and **CHAIN-GATED** to its harness
-- run (`plant.py && harness.sh`), so a failed plant yields NO ROW rather than a green one — and it
-- earned its keep: the very first control attempt printed `PLANT FAILED — NO RUN` on a bad anchor,
-- which under an ungated structure would have been a tidy 1384/0 row for a mutation that did not
-- exist. 「demoted」 = 0198 §C's VERIFY raise turned into a `notice`, so what is measured is the
-- SUITE rather than the apply. **Control observed clean FIRST: 1384 / 0**, and again after the one
-- pin repair below (same number).
--
-- ⚠ **THESE NUMBERS CORRECTED MY OWN PREDICTIONS IN NINE OF SEVENTEEN ROWS, and what is written
--   here is the measurement rather than the draft.** The error was systematic and in one
--   direction: I kept predicting a behavioural pin ALONE where S1 also reddens, because most of
--   these plants delete or rewrite a string S1 reads back out of `prosrc`. Worth naming, because
--   「S1 went red too」 is NOT a second witness — it is the same edit seen through a different
--   instrument, and reading it as corroboration is the endorsement-echo law one level down.
--
--   (i)    the ops gate deleted from `ops_runner_payout_detail`
--                                        → 1382/2: **G1** + S1. G1 names the runner / stranger /
--          inactive / other-class / owner callers now reading a stranger's money rows.
--   (ii)   the gate moved BELOW the `p_runner is null` check
--                                        → 1382/2: **G1** + S1. G1's failure names
--          `null 러너/…: no_runner` five times — the word that tells a non-operator the gate did
--          not decide first (0194 §F④'s ordering note, reproduced rather than asserted).
--   (iii)  the gate moved BELOW the READ and nothing else (still ahead of the argument check, so
--          this plant isolates read-vs-gate order from (ii)'s argument-vs-gate order)
--                                        → 1383/1: **S1 ALONE — a NAMED GAP, not a pass.** The
--          raise unwinds the whole function whatever order the statements are in, so a stranger's
--          observable experience is byte-identical in both worlds and **no fixture can separate
--          them**. S1's `position('not_ops') < position('from ledger_items')` arm and 0198 §C's
--          twin are the only available detectors, which is exactly why they exist (221 L1's
--          shape). Per the standing rule a limitation is PROSE: no behavioural pin is written for
--          it, because every arm one could write would be green by construction.
--          ⚠ The FIRST version of this plant moved the gate below the read AND below the argument
--          check at once, and it reddened G1 — which would have been recorded as 「the behavioural
--          pins do see it」. They do not; they saw the argument half. **A conflated plant answers
--          a question you did not ask, in the flattering direction.**
--   (iv)   `is_ops` re-derived as `'payout_due' = any(v_kinds)` instead of through the roster
--                                        → 1383/1: **S1 ALONE.** ⚠ Named as a gap in the same
--          breath: the re-derivation is CORRECT today, so M1/M2 are not blind — there is no
--          reachable state where the two disagree while `ops_recipients_for` is unchanged. What S1
--          buys is that the drift becomes visible the day someone edits that function, which is
--          the only day it matters.
--   (v)    `is_ops` hard-wired TRUE       → 1381/3: **M1** + **M2** + S1. M2 names the four non-ops
--          callers whose console entry now opens onto `not_ops`.
--   (vi)   `is_ops` hard-wired FALSE      → 1381/3: **M1** + **M2** + S1. M2 names the active
--          operator now locked out of a console they can use.
--          ⚠ (v) and (vi) together are what make M2 a genuine CONTROL PAIR rather than one
--          measurement printed twice: neither hard-wiring satisfies both arms, so no constant
--          `is_ops` passes. The test applied here is CLAUDE.md's — name the failure mode each arm
--          is blind to; if the two lists are identical, you have one control, not two.
--   (vii)  the `active` conjunct dropped from `kinds`
--                                        → 1383/1: **M1 ALONE**, naming the inactive operator
--          whose retired class came back into their list.
--   (viii) `coalesce(…, '{}')` dropped from `kinds` (a NULL array for a non-operator)
--                                        → 1382/2: **M1** + S1. This plant exists only because the
--          first battery reddened M1's empty-array arm with nothing — every other mutation
--          preserves it by construction, so its non-blindness was the one thing the set had not
--          established (226 (v)'s lesson: a battery that never attacks its positive control has
--          measured everything except whether that control can fail).
--   (ix)   `and l.paid_payout_id is null` dropped from the detail predicate
--                                        → 1381/3: **D1** + **D2** + S1. D1 names 「지급된 행이
--          목록에 있다」 and the Σ mismatch against `ops_payouts_due()`; D2 names the
--          `already_paid` its batch now walks into.
--   (x)    the `not exists (… ended_at is null)` conjunct dropped
--                                        → 1381/3: **D1** + **D2** + S1 — the open-run row joins
--          the list and the operator's sum stops matching the total on their own screen.
--   (xi)   the settled conjunct written as the LEFT JOIN reading (`r.ended_at is not null`)
--          instead of `not exists`
--                                        → 1381/3: **D1** + **D2** + S1. D1 names the cancel-comp
--          row that VANISHED — 0192 §0b's measured finding, reproduced here rather than borrowed.
--   (xii)  the individual NEGATIVE row filtered out (0186 §B's per-RUNNER `having sum > 0`
--          transposed onto the ROW level as a `where … > 0`)
--                                        → 1382/2: **D1** + **D2**, S1 GREEN. ⚠ Note the
--          DIRECTION: the plant makes the list look tidier and the sum BIGGER, which reaches an
--          operator as `amount_mismatch` on a batch they ticked correctly. ⚠ And S1's green is
--          reported honestly rather than quietly: S1's `having` arm is a TEXTUAL belt against the
--          literal clause, and this plant is the realistic transposition, which carries no
--          `having`. A literal `having` is not plantable here — the query has no `group by` to
--          hang one on — so that arm guards a regression this battery structurally cannot
--          produce, and it is D1/D2 that hold the property.
--   (xiii) `where l.runner_id = p_runner` dropped
--                                        → 1382/2: **D1** + **D2**.
--          🔴 **AND THIS PLANT FOUND A REAL DEFECT IN D2 RATHER THAN IN THE CODE.** On the first
--          run it produced NO ROW AT ALL: D2's control arm read rC's single row as a scalar
--          subquery, the un-scoped function returned every unpaid row in the database, and
--          postgres raised `more than one row returned by a subquery`. The suite died with
--          `SUITE PARSE/EXEC FAILED` and **all six pins reported nothing** — a pin that ERRORS
--          takes its siblings down with it, which is the 「a battery that never ran」 shape inside
--          a single file. Repaired to counts (which cannot raise) and re-measured above. Per the
--          mid-battery law the repair is defensive only — it changes no proposition, and the
--          control reads 1384/0 before and after — but it is recorded here rather than quietly
--          fixed.
--   (xiv)  the argument added back to `ops_me` (`ops_me(p_uid uuid default null)` reading that uid)
--                                        → 1383/1: **S1 ALONE** (`pronargs` + the overload count).
--          ⚠ A GAP stated rather than papered over: nothing behavioural can catch this, because a
--          genuine `ops_me(uuid)` would be a NEW function and every existing caller keeps the
--          zero-argument one. 0198 §0d's structural defence is enforceable only as a catalog fact,
--          and S1 plus 0198 §C are the two places it is enforced.
--   (xv)   the ACL revoke deleted from §B (the definer left PUBLIC-executable)
--                                        → 1381/3: **S1** + **98 H9** + **99 S1**. The last two
--          are the standing schema-wide sweeps and their reddening is the point — a per-function
--          ACL pin only catches the function you already suspected, which by definition is not the
--          one that bites you.
--   (xvi)  a `limit 1` added to the detail query
--                                        → 1381/3: **D1** + **D2** + S1. The failure an operator
--          would live is paying ONE row and believing a runner is paid off.
--   (xvii) `dog_name` returned as NULL for everyone
--                                        → 1383/1: **D1 ALONE.** Planted because D1 asserts an
--          ABSENT `settled_at` and an absent dog on the cancel-comp row, and a function returning
--          NULL for every row would satisfy both — the control arms (`liU2`'s dog, `liU1`'s stamp)
--          are what separate 「absent because it is genuinely absent」 from 「absent because nothing
--          is ever carried」, and this plant is the measurement that they do.
--
-- ⚠ **WHAT THIS BATTERY DOES NOT ESTABLISH, said here rather than left to be assumed:** no
--   mutation attacks `ops_payouts_due()` or `ops_record_manual_payout()` themselves. They are
--   0186's functions and 217 owns them; D1 and D2 use them as ORACLES (the total to agree with,
--   the writer to be accepted by), which is a real measurement of THIS slice's agreement with them
--   and is not evidence about their own correctness.
set client_min_messages = warning;

-- ① the wrappers. A bare `exception when others` is the point: the pins compare the WORD, so a
-- refusal that changed its vocabulary reddens instead of silently passing.
create or replace function t_opc_me(p_uid uuid) returns jsonb language plpgsql as $$
declare r record;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select * into r from ops_me();
    return jsonb_build_object('is_ops', r.is_ops, 'kinds', to_jsonb(r.kinds),
                              'kinds_null', (r.kinds is null));
  exception when others then return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

create or replace function t_opc_detail(p_uid uuid, p_runner uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', d.ledger_item_id, 'booking', d.booking_id, 'net', d.net_won,
             'dog', d.dog_name, 'comp', d.cancel_comp, 'created', d.created_at,
             'settled', d.settled_at) order by d.created_at, d.ledger_item_id), '[]'::jsonb)
      into v from ops_runner_payout_detail(p_runner) d;
    return jsonb_build_object('rows', v);
  exception when others then return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- `ops_payouts_due()` seen as this caller sees it — M2's oracle and D1's total
create or replace function t_opc_due(p_uid uuid) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    select coalesce(jsonb_agg(jsonb_build_object('runner', d.runner_profile_id,
             'net', d.unpaid_net_won, 'items', d.unpaid_items) order by d.runner_profile_id),
           '[]'::jsonb)
      into v from ops_payouts_due() d;
    return jsonb_build_object('rows', v);
  exception when others then return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

create or replace function t_opc_pay(p_uid uuid, p_runner uuid, p_ids uuid[], p_amount int)
returns jsonb language plpgsql as $$
declare v uuid;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  begin
    v := ops_record_manual_payout(p_runner, p_ids, p_amount, 'opc 콘솔 배치');
    return jsonb_build_object('payout', v);
  exception when others then return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- a booking whose run is ended (settled) or still open, as 217 does it
create or replace function t_opc_bk(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                    p_live boolean)
returns uuid language plpgsql as $$
declare v uuid;
begin
  v := t_active_booking(p_owner, p_runner, p_dog, p_route);
  if p_live is not true then
    update runs set ended_at = now(), settled_at = now() where booking_id = v;
  end if;
  return v;
end $$;

-- a booking with NO run at all — the cancellation-compensation shape (0080 §K · 0085)
create or replace function t_opc_bk_norun(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid)
returns uuid language plpgsql as $$
declare v uuid;
begin
  v := t_active_booking(p_owner, p_runner, p_dog, p_route);
  delete from runs where booking_id = v;
  return v;
end $$;

-- one ledger row: net = p_gross − p_fee
create or replace function t_opc_item(p_runner uuid, p_booking uuid, p_gross int, p_fee int,
                                      p_age interval)
returns uuid language sql as $$
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee, created_at)
  values (p_runner, p_booking, p_gross, 0, 0, 0, 0, p_fee, now() - p_age)
  returning id
$$;

do $$
declare
  ops1   uuid;  -- active payout_due operator
  opsoff uuid;  -- payout_due, active = false
  opsx   uuid;  -- active, but for ANOTHER event class
  outsdr uuid;  -- an ordinary owner, no ops row at all
  o      uuid;
  rA     uuid;  -- the detail subject: paid + unpaid + open-run + negative + cancel-comp
  rB     uuid;  -- D2's batch subject, summed by nobody else
  rC     uuid;  -- a second runner, so D1 can show scoping
  dA uuid; dB uuid; dC uuid; rt uuid;
  bkPaid uuid; bkU1 uuid; bkU2 uuid; bkLive uuid; bkNeg uuid; bkComp uuid;
  liPaid uuid; liU1 uuid; liU2 uuid; liLive uuid; liNeg uuid; liComp uuid;
  bkB1 uuid; bkB2 uuid; liB1 uuid; liB2 uuid;
  bkC uuid; liC uuid;
  v_pay  uuid;
  v jsonb; v2 jsonb; vd jsonb;
  v_bad text := '';
  v_msg text;
  v_src text;
  v_oid oid;
  v_n int;
  v_sum bigint;
  v_due bigint;
  v_ids uuid[];
  fn text;
  caller text;
begin
  perform set_config('request.jwt.claim.sub', '', true);                                    -- ③

  ops1   := t_user('opc_ops1',    'owner');
  opsoff := t_user('opc_opsoff',  'owner');
  opsx   := t_user('opc_opsx',    'owner');
  outsdr := t_user('opc_outsider','owner');
  o      := t_user('opc_owner',   'owner');
  rA     := t_user('opc_runnerA', 'runner');
  rB     := t_user('opc_runnerB', 'runner');
  rC     := t_user('opc_runnerC', 'runner');
  dA := t_dog(o, 'opc-보리'); dB := t_dog(o, 'opc-초코'); dC := t_dog(o, 'opc-단추');
  rt := t_route('opc 코스');

  insert into ops_recipients (profile_id, event_class, active) values
    (ops1,   'payout_due',            true),
    (opsoff, 'payout_due',            false),
    (opsx,   'charge_dispatch_stale', true);

  -- runner A's world. Nets: paid 5000 (excluded) · U1 9000 · U2 4000 · live 6000 (excluded)
  -- · negative −800 · cancel-comp 3000. Σ of what the detail must return = 9000+4000−800+3000
  -- = 15,200 — and that must equal `ops_payouts_due().unpaid_net_won` for rA.
  bkPaid := t_opc_bk(o, rA, dA, rt, false); liPaid := t_opc_item(rA, bkPaid, 6000, 1000, interval '20 days');
  bkU1   := t_opc_bk(o, rA, dA, rt, false); liU1   := t_opc_item(rA, bkU1,  10000, 1000, interval '9 days');
  bkU2   := t_opc_bk(o, rA, dB, rt, false); liU2   := t_opc_item(rA, bkU2,   5000, 1000, interval '5 days');
  bkLive := t_opc_bk(o, rA, dA, rt, true);  liLive := t_opc_item(rA, bkLive,  7000, 1000, interval '4 days');
  bkNeg  := t_opc_bk(o, rA, dA, rt, false); liNeg  := t_opc_item(rA, bkNeg,    200, 1000, interval '3 days');
  bkComp := t_opc_bk_norun(o, rA, dC, rt);  liComp := t_opc_item(rA, bkComp,  3000,    0, interval '2 days');
  -- the paid row gets a real marker, written the way 0186 §C writes it
  insert into payouts (runner_id, period_start, period_end, gross, tax_withheld, net,
                       status, instant, paid_at, method, memo, recorded_by)
  values (rA, (now() - interval '20 days')::date, (now() - interval '20 days')::date,
          6000, 0, 5000, 'paid', false, now() - interval '19 days', 'manual', 'opc 사전 지급', ops1)
  returning id into v_pay;
  update ledger_items set paid_payout_id = v_pay where id = liPaid;

  -- runner B — D2's batch: two settled unpaid rows, nets 7000 and 2000.
  bkB1 := t_opc_bk(o, rB, dB, rt, false); liB1 := t_opc_item(rB, bkB1, 8000, 1000, interval '8 days');
  bkB2 := t_opc_bk(o, rB, dB, rt, false); liB2 := t_opc_item(rB, bkB2, 2500,  500, interval '6 days');
  -- runner C — one settled unpaid row, net 1000. Never appears in rA's or rB's list.
  bkC  := t_opc_bk(o, rC, dC, rt, false); liC  := t_opc_item(rC, bkC,  1500,  500, interval '7 days');

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0198-M1] ops_me answers about the CALLER and only the caller
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';

  v := t_opc_me(ops1);
  if v->>'raised' is not null then v_bad := v_bad || ' 현역 ops가 거절됨: ' || (v->>'raised');
  else
    if (v->>'is_ops')::boolean is not true then v_bad := v_bad || ' 현역 ops의 is_ops=' || coalesce(v->>'is_ops','NULL'); end if;
    if (v->'kinds' @> '["payout_due"]'::jsonb) is not true then v_bad := v_bad || ' 현역 ops의 kinds에 payout_due가 없다: ' || coalesce(v->>'kinds','NULL'); end if;
  end if;

  -- INACTIVE: not an operator, and the retired class is ABSENT from the list. Asserting only
  -- `is_ops = false` here would not see a `kinds` that forgot the `active` conjunct.
  v := t_opc_me(opsoff);
  if v->>'raised' is not null then v_bad := v_bad || ' 비활성 ops가 거절됨: ' || (v->>'raised');
  else
    if (v->>'is_ops')::boolean is not false then v_bad := v_bad || ' 비활성 ops의 is_ops=' || coalesce(v->>'is_ops','NULL'); end if;
    if (v->'kinds' @> '["payout_due"]'::jsonb) then v_bad := v_bad || ' 비활성 클래스가 kinds에 남았다: ' || coalesce(v->>'kinds','NULL'); end if;
  end if;

  -- ANOTHER class: 0198 §0d's whole point — an operator, but not for this desk. `is_ops` is
  -- false AND `kinds` carries the class, which is what lets the refusal screen say so.
  v := t_opc_me(opsx);
  if v->>'raised' is not null then v_bad := v_bad || ' 타클래스 ops가 거절됨: ' || (v->>'raised');
  else
    if (v->>'is_ops')::boolean is not false then v_bad := v_bad || ' 타클래스 ops의 is_ops=' || coalesce(v->>'is_ops','NULL'); end if;
    if (v->'kinds' @> '["charge_dispatch_stale"]'::jsonb) is not true then v_bad := v_bad || ' 타클래스가 kinds에 없다: ' || coalesce(v->>'kinds','NULL'); end if;
    if (v->'kinds' @> '["payout_due"]'::jsonb) then v_bad := v_bad || ' 타클래스 ops가 payout_due를 갖고 있다'; end if;
  end if;

  -- an ordinary member of the product: false, and an EMPTY ARRAY rather than NULL. A NULL array
  -- makes `array_length(kinds,1) = 0` and `kinds[1] is null` disagree on the client.
  foreach caller in array array[outsdr::text, rA::text, o::text] loop
    v := t_opc_me(caller::uuid);
    if v->>'raised' is not null then v_bad := v_bad || ' 일반 사용자(' || left(caller,8) || ')가 거절됨: ' || (v->>'raised');
    else
      if (v->>'is_ops')::boolean is not false then v_bad := v_bad || ' 일반 사용자(' || left(caller,8) || ')의 is_ops=' || coalesce(v->>'is_ops','NULL'); end if;
      if (v->>'kinds_null')::boolean is not false then v_bad := v_bad || ' 일반 사용자(' || left(caller,8) || ')의 kinds가 NULL이다'; end if;
      if v->>'kinds' is distinct from '[]' then v_bad := v_bad || ' 일반 사용자(' || left(caller,8) || ')의 kinds=' || coalesce(v->>'kinds','NULL'); end if;
    end if;
  end loop;

  -- no caller at all: a WORD, not `false`. 세션 만료와 「운영자가 아님」은 다른 사실이다.
  perform set_config('request.jwt.claim.sub', '', true);                                    -- ③
  v := t_opc_me(null);
  if v->>'raised' is distinct from 'not_signed_in' then v_bad := v_bad || ' 무기명: ' || coalesce(v->>'raised', 'ACCEPTED is_ops=' || coalesce(v->>'is_ops','?')); end if;

  if v_bad = '' then call _pass('opc','0198-M1 ops_me는 호출자 자신에 대해서만 답한다 — 현역/비활성/타클래스/일반 사용자 네 형태가 전부 다르게 나오고(비활성 클래스는 kinds에서도 빠진다, 타클래스는 kinds에 남되 is_ops=false), 일반 사용자의 kinds는 NULL이 아니라 빈 배열이며, 무기명은 false가 아니라 not_signed_in');
  else v_msg := v_bad; call _fail('opc','0198-M1 ops_me 자기 자격', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0198-M2] is_ops is the GATE'S answer — both directions
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- The console entry is drawn on `ops_me().is_ops`; the doors behind it gate on
  -- `ops_recipients_for('payout_due')`. If those two can disagree, the entry is a button that
  -- opens onto a refusal — which this house's honesty law calls a dead button whichever way it
  -- fails. Measured against the REAL door (`ops_payouts_due`), per caller, in both directions.
  -- ⚠ Two arms, two different blind spots: the ADMITS arm cannot be satisfied by an `is_ops`
  --   hard-wired false and the REFUSES arm cannot be satisfied by one hard-wired true. Neither
  --   hard-wiring passes both, which is what makes this a control pair rather than one
  --   measurement printed twice.
  v_bad := '';
  foreach caller in array array[ops1::text, opsoff::text, opsx::text, outsdr::text, rA::text, o::text] loop
    v  := t_opc_me(caller::uuid);
    vd := t_opc_due(caller::uuid);
    if v->>'raised' is not null then v_bad := v_bad || ' ops_me가 거절됨(' || left(caller,8) || '): ' || (v->>'raised'); continue; end if;
    if (v->>'is_ops')::boolean is true then
      -- claims the console is usable ⇒ the real door must admit them
      if vd->>'raised' is not null
      then v_bad := v_bad || ' is_ops=true인데 문이 거절(' || left(caller,8) || '): ' || (vd->>'raised'); end if;
    else
      -- claims it is not ⇒ the real door must refuse them, by that exact word
      if vd->>'raised' is distinct from 'not_ops'
      then v_bad := v_bad || ' is_ops=false인데 문이 통과(' || left(caller,8) || '): ' || coalesce(vd->>'raised','ADMITTED'); end if;
    end if;
  end loop;
  -- the pair is non-degenerate: this fixture really does contain both an admitted caller and a
  -- refused one. Without this, a world where every caller fell on one side would satisfy the loop
  -- above while measuring only one direction.
  if (t_opc_me(ops1)->>'is_ops')::boolean is not true then v_bad := v_bad || ' 대조: 통과하는 호출자가 픽스처에 없다'; end if;
  if (t_opc_me(outsdr)->>'is_ops')::boolean is not false then v_bad := v_bad || ' 대조: 거절되는 호출자가 픽스처에 없다'; end if;
  if v_bad = '' then call _pass('opc','0198-M2 is_ops는 실제 문의 답이다 — 여섯 호출자 전부에 대해 is_ops=true면 ops_payouts_due()가 통과시키고 false면 정확히 not_ops로 거절한다(양방향, 양쪽에 실제 호출자가 있음을 대조로 확인). 한쪽으로 고정된 is_ops는 둘 중 하나만 만족한다');
  else v_msg := v_bad; call _fail('opc','0198-M2 is_ops와 게이트의 일치', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0198-D1] the detail is exactly what the total counted
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  v := t_opc_detail(ops1, rA);
  if v->>'raised' is not null then v_bad := v_bad || ' 상세가 거절됨: ' || (v->>'raised');
  else
    select count(*)::int into v_n from jsonb_array_elements(v->'rows');
    if v_n is distinct from 4 then v_bad := v_bad || ' 행 개수=' || v_n || '(4 기대)'; end if;
    -- the four that must be there, and the two that must not
    if (select count(*)::int from jsonb_array_elements(v->'rows') e
         where (e->>'id')::uuid in (liU1, liU2, liNeg, liComp)) is distinct from 4
    then v_bad := v_bad || ' 미지급·정산 완료 네 행이 다 안 나왔다'; end if;
    if (select count(*)::int from jsonb_array_elements(v->'rows') e
         where (e->>'id')::uuid = liPaid) is distinct from 0
    then v_bad := v_bad || ' 지급된 행이 목록에 있다'; end if;
    if (select count(*)::int from jsonb_array_elements(v->'rows') e
         where (e->>'id')::uuid = liLive) is distinct from 0
    then v_bad := v_bad || ' 아직 끝나지 않은 run의 행이 목록에 있다'; end if;
    -- another runner's rows never appear
    if (select count(*)::int from jsonb_array_elements(v->'rows') e
         where (e->>'id')::uuid in (liB1, liB2, liC)) is distinct from 0
    then v_bad := v_bad || ' 남의 행이 목록에 있다'; end if;
    -- the NEGATIVE row is present, with its sign intact. Dropping it would make the tickable
    -- rows sum to MORE than the total (0198 §B's no-`having` note).
    if (select (e->>'net')::int from jsonb_array_elements(v->'rows') e where (e->>'id')::uuid = liNeg)
       is distinct from -800 then v_bad := v_bad || ' 음수 행의 순액이 −800이 아니다'; end if;
    -- the cancel-comp row: no `runs` row at all ⇒ `cancel_comp` true and `settled_at` NULL.
    -- Reading the LEFT JOIN instead of `not exists` deletes this row entirely (0192 §0b).
    if (select (e->>'comp')::boolean from jsonb_array_elements(v->'rows') e where (e->>'id')::uuid = liComp)
       is not true then v_bad := v_bad || ' 취소보상 행의 cancel_comp가 true가 아니다'; end if;
    if (select e->>'settled' from jsonb_array_elements(v->'rows') e where (e->>'id')::uuid = liComp)
       is not null then v_bad := v_bad || ' 취소보상 행에 settled_at이 채워졌다'; end if;
    -- an ordinary row DOES carry both a dog and a settlement stamp — without this arm the two
    -- assertions above pass on a function that returns NULL for everyone.
    if (select e->>'dog' from jsonb_array_elements(v->'rows') e where (e->>'id')::uuid = liU2)
       is distinct from 'opc-초코' then v_bad := v_bad || ' 개 이름이 안 실렸다'; end if;
    if (select (e->>'comp')::boolean from jsonb_array_elements(v->'rows') e where (e->>'id')::uuid = liU1)
       is not false then v_bad := v_bad || ' 대조: 보통 행의 cancel_comp가 false가 아니다'; end if;
    if (select e->>'settled' from jsonb_array_elements(v->'rows') e where (e->>'id')::uuid = liU1)
       is null then v_bad := v_bad || ' 대조: 보통 행에 settled_at이 없다'; end if;
    -- 🔴 THE AGREEMENT. Σ of what the operator can tick == what the operator is looking at.
    select coalesce(sum((e->>'net')::int), 0) into v_sum from jsonb_array_elements(v->'rows') e;
    vd := t_opc_due(ops1);
    select (e->>'net')::bigint into v_due from jsonb_array_elements(vd->'rows') e
     where (e->>'runner')::uuid = rA;
    if v_sum is distinct from 15200 then v_bad := v_bad || ' 상세 합계=' || v_sum || '(15200 기대)'; end if;
    if v_due is distinct from v_sum then v_bad := v_bad || ' 총계(' || coalesce(v_due::text,'NULL') || ')와 상세 합계(' || v_sum || ')가 다르다'; end if;
    if (select (e->>'items')::int from jsonb_array_elements(vd->'rows') e where (e->>'runner')::uuid = rA)
       is distinct from v_n then v_bad := v_bad || ' 총계의 행 수와 상세의 행 수가 다르다'; end if;
  end if;
  -- a runner who owes nothing is an EMPTY LIST, not a refusal — the console draws an empty state
  if (t_opc_detail(ops1, ops1)->>'rows') is distinct from '[]'
  then v_bad := v_bad || ' 원장이 없는 사람에게 빈 목록이 아닌 답이 왔다'; end if;
  if v_bad = '' then call _pass('opc','0198-D1 상세 = 총계가 센 그 행들 — 지급된 행·열린 run의 행·남의 행은 빠지고, 음수 행은 부호 그대로 남고, run이 아예 없는 취소보상 행은 cancel_comp=true·settled_at=NULL로 들어오며(보통 행은 반대, 대조), 순액 합계가 ops_payouts_due()의 unpaid_net_won·unpaid_items와 정확히 일치한다');
  else v_msg := v_bad; call _fail('opc','0198-D1 상세와 총계의 일치', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0198-D2] the console loop closes — read the ids, sum the nets, pay, re-read
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  v := t_opc_detail(ops1, rB);
  if v->>'raised' is not null then v_bad := v_bad || ' rB 상세가 거절됨: ' || (v->>'raised');
  else
    select array_agg((e->>'id')::uuid), coalesce(sum((e->>'net')::int), 0)
      into v_ids, v_sum from jsonb_array_elements(v->'rows') e;
    if coalesce(array_length(v_ids,1),0) is distinct from 2 then v_bad := v_bad || ' rB 상세가 2행이 아니다'; end if;
    if v_sum is distinct from 9000 then v_bad := v_bad || ' rB 상세 합계=' || v_sum || '(9000 기대)'; end if;

    -- the client's number is a SECOND OPINION and 0186 §C still refuses a wrong one (0198 §0b).
    -- Off by ONE won, so what is measured is the equality rather than a sign or a magnitude.
    v2 := t_opc_pay(ops1, rB, v_ids, (v_sum + 1)::int);
    if v2->>'raised' is distinct from 'amount_mismatch' then v_bad := v_bad || ' 1원 틀린 금액: ' || coalesce(v2->>'raised','ACCEPTED'); end if;
    select count(*)::int into v_n from ledger_items where id = any(v_ids) and paid_payout_id is not null;
    if v_n is distinct from 0 then v_bad := v_bad || ' 거절된 배치가 행을 표시했다(' || v_n || ')'; end if;

    -- ...and the exact sum is accepted, with the ids exactly as returned
    v2 := t_opc_pay(ops1, rB, v_ids, v_sum::int);
    if v2->>'raised' is not null then v_bad := v_bad || ' 정확한 배치가 거절됨: ' || (v2->>'raised');
    else
      select count(*)::int into v_n from ledger_items
       where id = any(v_ids) and paid_payout_id = (v2->>'payout')::uuid;
      if v_n is distinct from 2 then v_bad := v_bad || ' 지급 후 표시된 행이 ' || v_n || '개다(2 기대)'; end if;
    end if;

    -- the paid rows LEAVE the list — otherwise the operator pays the same batch twice
    v2 := t_opc_detail(ops1, rB);
    if v2->>'rows' is distinct from '[]' then v_bad := v_bad || ' 지급한 행이 목록에 남았다: ' || coalesce(v2->>'rows','NULL'); end if;
    -- and the runner leaves `ops_payouts_due()` as well — the two reads agree AFTER the write too
    vd := t_opc_due(ops1);
    if (select count(*)::int from jsonb_array_elements(vd->'rows') e where (e->>'runner')::uuid = rB)
       is distinct from 0 then v_bad := v_bad || ' 다 지급한 러너가 총계에 남았다'; end if;
    -- the untouched runners are untouched. THE CONTROL, and it is not decoration: a writer that
    -- marked every unpaid row in the table would satisfy every arm above.
    -- ⚠ COUNTED, never read as a scalar subquery. Measured 2026-09-22: the first draft wrote
    --    `(select (e->>'id')::uuid from jsonb_array_elements(v2->'rows') e)`, and under the plant
    --    that drops `where l.runner_id = p_runner` that subquery returns EVERY unpaid row in the
    --    database — so it raised `more than one row returned by a subquery` and the whole suite
    --    died with `SUITE PARSE/EXEC FAILED`. **A pin that ERRORS instead of FAILING takes its
    --    five siblings down with it and reports nothing about any of them**, which is the
    --    「a battery that never ran reads as success」 shape one level down. A count cannot do that.
    v2 := t_opc_detail(ops1, rC);
    if (select count(*)::int from jsonb_array_elements(v2->'rows')) is distinct from 1
    then v_bad := v_bad || ' 대조: rC의 행 수가 변했다'; end if;
    if (select count(*)::int from jsonb_array_elements(v2->'rows') e
         where (e->>'id')::uuid = liC) is distinct from 1
    then v_bad := v_bad || ' 대조: rC의 행이 그 행이 아니다'; end if;
    if (select count(*)::int from jsonb_array_elements(v2->'rows') e
         where (e->>'id')::uuid = liC and (e->>'net')::int = 1000) is distinct from 1
    then v_bad := v_bad || ' 대조: rC의 순액이 움직였다'; end if;
    if (select count(*)::int from ledger_items where id = liC and paid_payout_id is not null)
       is distinct from 0 then v_bad := v_bad || ' 대조: rC의 행에 지급 표식이 붙었다'; end if;
    if (select count(*)::int from jsonb_array_elements(t_opc_detail(ops1, rA)->'rows')) is distinct from 4
    then v_bad := v_bad || ' 대조: rA의 행 수가 변했다'; end if;
  end if;
  if v_bad = '' then call _pass('opc','0198-D2 콘솔 루프가 닫힌다 — 상세가 준 id 배열과 순액 합계를 그대로 ops_record_manual_payout에 넘기면 받아들여지고, 1원 틀린 합계는 amount_mismatch로 거절하며 아무 행도 표시하지 않는다; 지급 후 그 행들은 상세에서도 총계에서도 사라지고 다른 러너들의 행은 그대로다(대조)');
  else v_msg := v_bad; call _fail('opc','0198-D2 콘솔 루프', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0198-G1] the ops party gate, ahead of the read and ahead of the argument check
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  foreach caller in array array[rA::text, outsdr::text, opsoff::text, opsx::text, o::text] loop
    -- a runner who EXISTS and a uuid that is NOBODY must produce the identical word. This is the
    -- only arm that can show the gate decided before anything was read: a gate that ran after the
    -- lookup would answer differently for the two.
    v  := t_opc_detail(caller::uuid, rA);
    v2 := t_opc_detail(caller::uuid, gen_random_uuid());
    if v->>'raised' is distinct from 'not_ops'
    then v_bad := v_bad || ' 있는 러너/' || left(caller,8) || ': ' || coalesce(v->>'raised','ACCEPTED'); end if;
    if v2->>'raised' is distinct from 'not_ops'
    then v_bad := v_bad || ' 없는 러너/' || left(caller,8) || ': ' || coalesce(v2->>'raised','ACCEPTED'); end if;
    if v->>'raised' is distinct from v2->>'raised'
    then v_bad := v_bad || ' ' || left(caller,8) || ': 있는 러너와 없는 러너의 답이 다르다'; end if;
    -- and a NULL runner is still `not_ops`, never `no_runner` — the difference between those two
    -- words is itself information about the gate (0194 §F④'s ordering note).
    if (t_opc_detail(caller::uuid, null)->>'raised') is distinct from 'not_ops'
    then v_bad := v_bad || ' null 러너/' || left(caller,8) || ': ' || coalesce(t_opc_detail(caller::uuid, null)->>'raised','ACCEPTED'); end if;
  end loop;

  perform set_config('request.jwt.claim.sub', '', true);                                    -- ③
  v := t_opc_detail(null, rA);
  if v->>'raised' is distinct from 'not_signed_in' then v_bad := v_bad || ' 무기명: ' || coalesce(v->>'raised','ACCEPTED'); end if;

  -- the control, without which every arm above is satisfied by refusing everyone
  v := t_opc_detail(ops1, rA);
  if v->>'raised' is not null then v_bad := v_bad || ' 대조: 현역 ops도 거절됨 ' || (v->>'raised'); end if;
  -- ...and `no_runner` is REACHABLE, so the word is not dead: an operator passing null gets it
  if (t_opc_detail(ops1, null)->>'raised') is distinct from 'no_runner'
  then v_bad := v_bad || ' ops의 null 러너: ' || coalesce(t_opc_detail(ops1, null)->>'raised','ACCEPTED'); end if;

  if v_bad = '' then call _pass('opc','0198-G1 ops 파티 게이트가 읽기보다도 인자 검사보다도 먼저 — 러너·남·비활성 ops·타클래스 ops·보호자 다섯 호출자가 **있는 러너와 없는 러너에게 똑같이** not_ops를 받고(그 동일성이 순서의 유일한 증거) null 러너도 no_runner가 아니라 not_ops다; 무기명은 not_signed_in; 현역 ops는 통과하고 그에게는 no_runner가 실제로 도달 가능하다(대조 둘)');
  else v_msg := v_bad; call _fail('opc','0198-G1 ops 파티 게이트', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0198-S1] deployed shape
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ Every `prosrc` match strips comments first. 0198 documents its own guards at length, and a
  -- check that a guard is CALLED is otherwise satisfied by the paragraph EXPLAINING it — the
  -- better the explanation, the more certainly green.
  -- ⚠ Every arm is an explicit boolean (`is not true` / `is distinct from`), never a bare `IF`:
  -- `position(… in NULL)` is NULL, and a bare `IF` over NULL is SILENT — which would make these
  -- arms quietest on the most complete kind of missing.
  v_bad := '';
  foreach fn in array array['ops_me()', 'ops_runner_payout_detail(uuid)'] loop
    v_oid := to_regprocedure(fn);
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || fn || ')'; continue; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') = 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ' || fn || ':search_path가 본문에 없거나 다르다'; end if;
    -- both directions: a definer born PUBLIC-executable is the worst shape this repo produces
    -- (0116:636), and an ACL that quietly stops granting `authenticated` kills the console.
    if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ' || fn || ':PUBLIC 실행 가능'; end if;
    if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false
      then v_bad := v_bad || ' ' || fn || ':anon 실행 가능'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is not true
      then v_bad := v_bad || ' ' || fn || ':authenticated 실행 불가'; end if;
  end loop;

  -- 0198 §0d's STRUCTURAL defence: `ops_me` has no argument, so no caller can point it at a third
  -- party. Nothing behavioural can see this — an `ops_me(uuid)` overload would be a new function
  -- and every existing caller keeps the zero-arg one — so the catalog is the only detector.
  if (select pronargs from pg_proc where oid = to_regprocedure('ops_me()')) is distinct from 0
    then v_bad := v_bad || ' ops_me가 인자를 받는다(제3자 오라클)'; end if;
  if (select count(*)::int from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
       where ns.nspname = 'public' and p.proname = 'ops_me') is distinct from 1
    then v_bad := v_bad || ' ops_me 오버로드가 생겼다'; end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('ops_runner_payout_detail(uuid)');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_runner_payout_detail)';
  else
    if (position('raise exception ''not_ops''' in v_src) > 0) is not true
      then v_bad := v_bad || ' 상세:ops 게이트가 없다'; end if;
    if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is not true
      then v_bad := v_bad || ' 상세:0084 로스터 창구를 안 쓴다'; end if;
    -- the ORDER: gate before the read, and gate before the argument check. The behavioural pins
    -- can see the second (G1's null-runner arm) and CANNOT see the first, because a raise unwinds
    -- the whole function either way — so this arm is the only detector for it.
    if (position('raise exception ''not_ops''' in v_src)
        < position('from ledger_items' in v_src)) is not true
      then v_bad := v_bad || ' 상세:ops 게이트가 원장 읽기보다 뒤'; end if;
    if (position('raise exception ''not_ops''' in v_src)
        < position('raise exception ''no_runner''' in v_src)) is not true
      then v_bad := v_bad || ' 상세:인자 검사가 게이트보다 앞'; end if;
    -- 0186 §B's predicate, carried textually rather than re-derived
    if (position('l.paid_payout_id is null' in v_src) > 0) is not true
      then v_bad := v_bad || ' 상세:0186의 미지급 술어가 없다'; end if;
    if (v_src ~ 'not exists \(select 1 from runs rn') is not true
      then v_bad := v_bad || ' 상세:정산 절이 not exists가 아니다(LEFT JOIN 읽기는 취소보상 행을 지운다)'; end if;
    -- 0198 §B's two deliberate absences. `having` would drop the negative row; `limit` would make
    -- a truncated list look like a paid-off runner.
    if (position('having' in v_src) > 0) then v_bad := v_bad || ' 상세:having 절이 생겼다(개별 음수 행이 빠진다)'; end if;
    if (v_src ~ '\mlimit\M') then v_bad := v_bad || ' 상세:limit이 생겼다(잘린 배치)'; end if;
  end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = to_regprocedure('ops_me()');
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_me)';
  else
    -- §0d: `is_ops` through the gate's own window. `'payout_due' = any(kinds)` is correct TODAY,
    -- so no behavioural arm can see the difference — this is the only place the drift is caught,
    -- and it is caught on the day `ops_recipients_for` changes rather than after.
    if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is not true
      then v_bad := v_bad || ' ops_me:is_ops를 로스터 창구로 계산하지 않는다'; end if;
    if (position('raise exception ''not_signed_in''' in v_src) > 0) is not true
      then v_bad := v_bad || ' ops_me:무기명 거절이 없다'; end if;
    -- the empty-array answer is in the source, not an accident of the fixture
    if (v_src ~ '''\{\}''::text\[\]') is not true
      then v_bad := v_bad || ' ops_me:kinds의 빈 배열 기본값이 없다'; end if;
  end if;

  -- the roster table is still SEALED (0084 §E): RLS on, zero policies. `ops_me` is a definer
  -- precisely because nothing may read this table directly, and a policy appearing here would
  -- make the staff roster client-readable while every pin above stayed green.
  if (select relrowsecurity from pg_class where oid = 'ops_recipients'::regclass) is not true
    then v_bad := v_bad || ' ops_recipients의 RLS가 꺼졌다'; end if;
  if (select count(*)::int from pg_policies where schemaname = 'public' and tablename = 'ops_recipients')
     is distinct from 0
    then v_bad := v_bad || ' ops_recipients에 정책이 생겼다(명부가 읽힌다)'; end if;

  if v_bad = '' then call _pass('opc','0198-S1 배포 형상 — 두 definer·본문 search_path가 정확히 일치·유효 권한으로 본 ACL 양방향·ops_me는 인자 0개이고 오버로드 없음(제3자 오라클 불가)·주석 벗긴 소스로 게이트가 읽기보다도 인자 검사보다도 앞·0186 술어를 글자 그대로·having과 limit의 부재·is_ops를 로스터 창구로 계산·ops_recipients는 여전히 RLS on/정책 0개·NO-FUNCTION/NO-SOURCE 팔');
  else v_msg := v_bad; call _fail('opc','0198-S1 배포 형상', v_msg); end if;
end $$;
