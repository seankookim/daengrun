-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 251 — 0220: a booking that ENDED without a run is told so (tag `pst0`)
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Pins 0220-T1 · T2 · T3 · T4 · T5 · C1 · S1.
--
-- ─── WHAT EACH PIN IS FOR ─────────────────────────────────────────────────────────────────────
--  · **0220-T1** — THE REPRODUCTION. Charging live, a `cancelled_owner` booking with
--    `cancel_fee = 0`, no `runs` row and no `payments` row answers `no_charge`/`cancelled_free`.
--    On trunk's body this same fixture answered `awaiting_settlement` — measured before the fix
--    (0220's header carries the six-line transcript). The pin asserts the WORLD first: charging
--    live, zero runs, zero payments. Without those three the arm is green over a fixture that
--    never contained the defect (the absence-pin law).
--  · **0220-T2** — the positive-fee half, measured as a DELTA THIS PIN CAUSES rather than as a
--    state it finds. ONE booking: `cancel_fee = 12450` and no payments row reads `fee_unminted`;
--    minting the intent on that same row flips it to `charge_pending`; deleting the row flips it
--    back. So the answer is attributable to the payments row, not to the status — and the minted
--    arm is the CONTROL that 0220 did not swallow a case 0207 already answered correctly.
--  · **0220-T3** — the other three endings, each with its OWN reason token. `cancelled_runner` →
--    `cancelled_by_runner`, `expired` → `expired`, `no_show` → `no_show`, beside T1's
--    `cancelled_free`. The four tokens are asserted DISTINCT as a set: a collapse to one word
--    (the shape `0207 §0a`'s deliberate `not_charging` collapse would suggest) reddens here, and
--    only here.
--  · **0220-T4** — the five answers that must NOT move, because a refinement that eats its
--    neighbours is not a refinement: `settled_without_payment` · `settling` · a stopped run on a
--    `completed` booking (`awaiting_settlement` survives — the one state the shipped copy was
--    always right about) · `incident_review` and `refund_pending`, which LOOK terminal and are
--    not (`0117:637-640`, `0193:973`) · and 🔴 the CUTOVER PAIR: the same terminal booking read
--    with `payments_live_since` NULL answers `no_charge`/**`not_charging`**, not
--    `cancelled_free`. The flag still outranks the fork.
--  · **0220-T5** — THE REFINEMENT, measured instead of argued. 0220's whole blast-radius claim is
--    「the only rows whose answer can change are rows that answered `awaiting_settlement`」. Two
--    measurements, in opposite directions: every fixture answering a 0220 word has NO settled run
--    (which is exactly the pre-0220 branch condition, re-derived from the DATA rather than from
--    the function), and `payments_reconciliation()` arm eight reports NONE of them — with a
--    CONTROL booking the board DOES report, so 「the board says nothing」 is not an empty board.
--  · **0220-C1** — the invariants 0207 bought, still true of the new states: exactly one row for
--    every fixture with a non-NULL state; `amount_won` NULL on every new state WITH a control
--    that a real payments row still produces one; and the party gate — runner, stranger, and a
--    booking that does not exist all get the identical `not_party`, anonymous gets
--    `not_authenticated`, the owner passes on the same id.
--  · **0220-S1** — the deployed shape: definer, in-body `search_path`, ACL both directions, and
--    the comment-stripped body carrying the terminal set, the coalesced fee read, the fork
--    POSITIONED inside the old `awaiting_settlement` branch and behind the cutover pair, with a
--    NO-FUNCTION/NO-SOURCE arm and a two-sided stripper control.
--
-- ─── WHAT IS DELIBERATELY NOT PINNED ──────────────────────────────────────────────────────────
-- ⚠ **A terminal booking whose run genuinely SETTLED.** 0220 leaves that population on the
--   settlement ladder, and this harness cannot manufacture the case honestly: `settle_run_tx`
--   never runs for a cancelled booking (`cancel_owner.ts:298`), so a settled run under a
--   `cancelled_*` status is a row no writer produces. A pin over it would be asserting behaviour
--   about a state the product cannot reach, and its green would read as coverage forever. This
--   paragraph is the limitation; there is no arm for it. (The tell, per the house law: I could
--   not describe a mutation that would redden such a pin.)
-- ⚠ **`unknown`.** Unchanged from 0207 and pinned there (`0207-S2`), by the same argument.
--
-- ─── FIXTURE NOTES THAT ARE LOAD-BEARING ──────────────────────────────────────────────────────
--  ① This suite builds its OWN world (`pst0_*` profiles, `t_pst_*` helpers). A pin that inherits
--    another suite's setup is testing that setup (`175 V2`), and 238's fixtures move for 238's
--    reasons — 238 has no terminal-status booking at all, which is why 0220's defect survived it.
--  ② `ops_flags` is armed by WHOLE-ROW SNAPSHOT and restored by value in every pin that touches
--    it, INCLUDING each exception handler (203 ①: fixture state escaping a pin produced three
--    reds, two of them naming the wrong thing).
--  ③ Bookings are INSERTED at their terminal status rather than transitioned into it. Correct
--    here: this file is about a READ, and the transition ladders are pinned where they live
--    (`152` for the late protocol, `116` for the charge ladder). What 0220 reads is the STORED
--    status and the STORED fee, and those are what the fixtures set.
--  ④ Every call goes through `t_pst_state`, which sets the caller's claim, reports the ROW **or**
--    the raise and never both, and always clears the claim.
--
-- ─── MUTATION MAP — MEASURED against these exact files, control (1493/0) observed FIRST. Every
--     plant asserted its own landing and the harness was `&&`-chained to it, so an unlanded plant
--     yields no row at all rather than a plausible green one. Reproduced in the REGISTRY row.
--
--   M1   the terminal fork deleted              27740→26925 B  ⇒ APPLY ABORTS at 0220's own
--        VERIFY: `TERMINAL-STATE-MISSING(fee_unminted) TERMINAL-SET-DIVERGED(0075:750)
--        TERMINAL-FORK-ABSENT`. That measures the VERIFY block, not this suite — hence M1s.
--   M1s  M1 + those three VERIFY arms removed   27740→26106 B  ⇒ **1488/5**: T1 · T2 · T3 · C1 · S1
--        ⚠ T4 and T5 stay GREEN, and that is a fact about what they pin rather than a gap: T4
--        pins the NEIGHBOURS (which do not move when the fork vanishes) and T5 pins the
--        REFINEMENT, which is vacuously satisfied when there are no 0220 answers to refine.
--        **T5 cannot detect the fork's ABSENCE.** T1 and T3 own that, and they do.
--   M2s  the fee>0 branch deleted (+strip)      27740→26597 B  ⇒ **1491/2**: T2
--        (`before=no_charge/cancelled_free`) and S1 (`NO-fee_unminted-ARM`)
--   M3   the fork keys on the FEE alone, with the status array LITERAL left in place so S1's
--        presence arm cannot be what notices    27740→27767 B  ⇒ **1491/2**: T4 (b_stop ·
--        incident_review · refund_pending all swallowed) **and 0207-P4**, 238's shipped pin,
--        independently — two suites, two different fixtures, one defect
--   M4   the `awaiting_settlement` assignment hoisted textually above the fork —
--        **BEHAVIOUR IDENTICAL**                27740→27728 B  ⇒ APPLY ABORTS:
--        `FORK-AFTER-AWAITING(term=2988 await=2912)`
--   M4b  M4 + the VERIFY order arm removed      27740→27219 B  ⇒ **1492/1**: **S1 ALONE**. A
--        behaviour-preserving edit that no behavioural pin can see; the source ORDER arm is the
--        only detector there is, which is the whole reason it exists.
--   M5   the cutover pair no longer outranks the fork   27740→27852 B ⇒ APPLY ABORTS:
--        `CUTOVER-NOT-FIRST(cut=2847 term=2778)`
--   M5s  M5 + the migration's order/cutover VERIFY arms removed  27740→26698 B ⇒ **1491/2**:
--        T4 (with the flag NULL b_free answers `no_charge/cancelled_free` instead of
--        `not_charging`) and S1
--   M6   §B's `revoke … from public, anon` deleted    27740→27663 B ⇒ harness **1493/0, GREEN**
--        — the harness applies every migration from scratch in numeric order, so 0207's revoke is
--        preserved and this whole class is structurally invisible to it — while
--        `node scripts/check-definer-acl.mjs` goes **exit 1**. The source-vs-runtime division
--        measured in both directions: neither is evidence for the other.
--   restore ⇒ **1493/0** again, re-run after the LAST edit rather than the last interesting one.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
set client_min_messages = warning;

-- ---------- suite-local helpers ④ ----------
-- ONE call, fully judged: the caller's claim, the row as jsonb, or the raise. Never both.
create or replace function t_pst_state(p_uid uuid, p_booking uuid) returns jsonb
language plpgsql as $$
declare v jsonb; v_n int;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  begin
    select count(*)::int into v_n from my_booking_payment_state(p_booking) x;
    select to_jsonb(x) into v from my_booking_payment_state(p_booking) x;
    perform set_config('request.jwt.claim.sub', '', false);
    return jsonb_build_object('n', v_n, 'row', coalesce(v, 'null'::jsonb));
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- the state alone, or the literal word `RAISED:<sqlerrm>`.
create or replace function t_pst_st(p_uid uuid, p_booking uuid) returns text
language plpgsql as $$
declare v jsonb;
begin
  v := t_pst_state(p_uid, p_booking);
  if v->>'raised' is not null then return 'RAISED:' || (v->>'raised'); end if;
  return coalesce(v->'row'->>'state', '(null)');
end $$;

-- `state/reason` as one comparable string — `(null)` for an absent reason, so a pin that expects
-- a token cannot be satisfied by a NULL.
create or replace function t_pst_sr(p_uid uuid, p_booking uuid) returns text
language plpgsql as $$
declare v jsonb;
begin
  v := t_pst_state(p_uid, p_booking);
  if v->>'raised' is not null then return 'RAISED:' || (v->>'raised'); end if;
  return coalesce(v->'row'->>'state', '(null)') || '/' || coalesce(v->'row'->>'reason', '(null)');
end $$;

-- a booking that ENDED without a run: no `runs` row, no `payments` row, a stored `cancel_fee`.
create or replace function t_pst_ended(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid,
                                       p_status booking_status, p_fee int)
returns uuid language plpgsql as $$
declare v uuid;
begin
  v := t_av_booking(p_owner, p_dog, p_route, p_runner, now() - interval '2 days', 5.0, p_status);
  update bookings set cancel_fee = p_fee where id = v;
  return v;
end $$;

-- arm eight's own answer for ONE booking — the SECOND measurement T5 compares against.
create or replace function t_pst_board(p_booking uuid) returns boolean
language sql as $$
  select exists (select 1 from payments_reconciliation() r
                  where r.kind = 'settled_without_payment' and r.booking_id = p_booking)
$$;

do $$
declare
  ow uuid; rn uuid; oz uuid; rt uuid;
  d1 uuid; d2 uuid; d3 uuid; d4 uuid; d5 uuid; d6 uuid; d7 uuid; d8 uuid; d9 uuid; da uuid;
  b_free uuid;   -- cancelled_owner, fee 0        → no_charge / cancelled_free   🔴 the finding
  b_fee  uuid;   -- cancelled_owner, fee 12450    → fee_unminted (T2's stage)
  b_run  uuid;   -- cancelled_runner, fee 0       → no_charge / cancelled_by_runner
  b_exp  uuid;   -- expired, fee 0                → no_charge / expired
  b_ns   uuid;   -- no_show, fee 0                → no_charge / no_show
  b_inc  uuid;   -- incident_review, fee 0        → awaiting_settlement (LOOKS terminal, is not)
  b_ref  uuid;   -- refund_pending, fee 0         → awaiting_settlement (ditto)
  b_swp  uuid;   -- completed, settled 3h ago     → settled_without_payment (control)
  b_new  uuid;   -- completed, settled 10 min ago → settling                (control)
  b_stop uuid;   -- completed, run never settled  → awaiting_settlement     (control)
  v_flags jsonb; v_cur jsonb;
  v_bad text := ''; v_msg text; v_n int; v_txt text; v_js jsonb;
  v_src text; v_raw text; v_oid oid; v_secdef boolean; v_path boolean;
  v_gate int; v_read int; v_term int; v_await int; v_cut int;
  b_all uuid[]; b_new_words uuid[];
  v_id uuid;
begin
  perform set_config('request.jwt.claim.sub', '', false);

  -- ---------- shared seed (OUTSIDE every pin — 203 ①) ----------
  ow := t_user('pst0_ow', 'owner');
  rn := t_user('pst0_rn', 'runner');
  oz := t_user('pst0_oz', 'owner');           -- a stranger who is a perfectly real owner
  rt := t_route('종결 결제 상태 코스');
  d1 := t_dog(ow, '무료취소견'); d2 := t_dog(ow, '수수료취소견'); d3 := t_dog(ow, '러너취소견');
  d4 := t_dog(ow, '만료견');     d5 := t_dog(ow, '노쇼견');       d6 := t_dog(ow, '사건견');
  d7 := t_dog(ow, '환불대기견'); d8 := t_dog(ow, '미가격견');     d9 := t_dog(ow, '갓정산견');
  da := t_dog(ow, '중단견');

  select to_jsonb(f.*) into v_flags from ops_flags f where f.id;

  b_free := t_pst_ended(ow, d1, rt, rn,   'cancelled_owner',  0);
  b_fee  := t_pst_ended(ow, d2, rt, rn,   'cancelled_owner',  12450);
  b_run  := t_pst_ended(ow, d3, rt, rn,   'cancelled_runner', 0);
  b_exp  := t_pst_ended(ow, d4, rt, null, 'expired',          0);
  b_ns   := t_pst_ended(ow, d5, rt, rn,   'no_show',          0);
  b_inc  := t_pst_ended(ow, d6, rt, rn,   'incident_review',  0);
  b_ref  := t_pst_ended(ow, d7, rt, rn,   'refund_pending',   0);

  -- the three settlement-ladder controls, built exactly as 238 builds them
  b_swp := t_av_booking(ow, d8, rt, rn, now() - interval '4 hours', 5.0, 'completed');
  insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
  values (b_swp, now() - interval '4 hours', now() - interval '3 hours',
          now() - interval '3 hours', null, 'completed'::end_reason);
  b_new := t_av_booking(ow, d9, rt, rn, now() - interval '2 hours', 5.0, 'completed');
  insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
  values (b_new, now() - interval '2 hours', now() - interval '10 minutes',
          now() - interval '10 minutes', null, 'completed'::end_reason);
  b_stop := t_av_booking(ow, da, rt, rn, now() - interval '4 hours', 5.0, 'completed');
  insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
  values (b_stop, now() - interval '4 hours', now() - interval '3 hours', null,
          null, 'completed'::end_reason);

  b_all       := array[b_free, b_fee, b_run, b_exp, b_ns, b_inc, b_ref, b_swp, b_new, b_stop];
  b_new_words := array[b_free, b_fee, b_run, b_exp, b_ns];

  ------------------------------------------------------------------------------------------
  -- [0220-T1] THE REPRODUCTION — a free cancellation is told it is free, not told to wait
  ------------------------------------------------------------------------------------------
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    -- CONTROL, first: the world must be the one the defect needs. Charging LIVE (otherwise the
    -- cutover pair answers and this pin measures 0084, not 0220), no `runs` row (otherwise the
    -- settlement ladder answers) and no `payments` row (otherwise arm ④ answers). An absence
    -- asserted over a world that never held the thing is worth zero.
    if (select f.payments_live_since from ops_flags f where f.id) is null then
      v_bad := v_bad || ' CONTROL: charging is not live — this fixture cannot reach the fork';
    end if;
    select count(*) into v_n from runs r where r.booking_id = b_free;
    if v_n <> 0 then v_bad := v_bad || ' CONTROL: b_free has a runs row (' || v_n || ')'; end if;
    select count(*) into v_n from payments p where p.booking_id = b_free;
    if v_n <> 0 then v_bad := v_bad || ' CONTROL: b_free has a payments row (' || v_n || ')'; end if;
    if (select coalesce(b.cancel_fee, -1) from bookings b where b.id = b_free) <> 0 then
      v_bad := v_bad || ' CONTROL: b_free''s stored cancel_fee is not 0';
    end if;

    -- 🔴 the finding itself. On trunk's body this read `awaiting_settlement`.
    v_txt := t_pst_sr(ow, b_free);
    if v_txt is distinct from 'no_charge/cancelled_free' then
      v_bad := v_bad || ' b_free=' || coalesce(v_txt, 'NULL') || ' (want no_charge/cancelled_free)';
    end if;
    -- …and it must NOT be the word the whole finding is about.
    if t_pst_st(ow, b_free) = 'awaiting_settlement' then
      v_bad := v_bad || ' 🔴 b_free still answers awaiting_settlement — the 0220 fork is not firing';
    end if;
    -- no number: `bookings.cancel_fee` is 0 here, but the contract is that a number in
    -- `amount_won` means a PAYMENTS row answered (0207-P6), and none did.
    v_js := t_pst_state(ow, b_free);
    if (v_js->'row'->>'amount_won') is not null then
      v_bad := v_bad || ' b_free invented an amount: ' || (v_js->'row'->>'amount_won');
    end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('pst0','0220-T1 the reproduction: with charging live, a cancelled_owner booking carrying cancel_fee 0 with no runs row and no payments row answers no_charge/cancelled_free — on trunk''s body this exact fixture answered awaiting_settlement, whose shipped copy promises a bill that can never arrive. All four preconditions (flag live, zero runs, zero payments, stored fee 0) are asserted BEFORE the answer, so the arm cannot be green over a world that never contained the defect; and amount_won stays NULL because no payments row answered');
    else v_msg := v_bad; call _fail('pst0','0220-T1 free cancellation is told it is free', v_msg); end if;
  exception when others then
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('pst0','0220-T1 free cancellation is told it is free', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0220-T2] A FEE THAT WAS NEVER BILLED — and the minting is a DELTA THIS PIN CAUSES
  ------------------------------------------------------------------------------------------
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    -- CONTROL: the fee is really stored and really positive, and nothing has been minted.
    if (select coalesce(b.cancel_fee, 0) from bookings b where b.id = b_fee) <= 0 then
      v_bad := v_bad || ' CONTROL: b_fee carries no positive cancel_fee';
    end if;
    select count(*) into v_n from payments p where p.booking_id = b_fee;
    if v_n <> 0 then v_bad := v_bad || ' CONTROL: b_fee already has a payments row'; end if;

    -- ⓐ BEFORE: a fee is owed and no intent exists.
    v_txt := t_pst_sr(ow, b_fee);
    if v_txt is distinct from 'fee_unminted/(null)' then
      v_bad := v_bad || ' before=' || coalesce(v_txt, 'NULL') || ' (want fee_unminted with no reason)';
    end if;
    -- no number here either, and this is the arm that earns the rule: `cancel_fee` is a REAL
    -- stored 12450 and printing it would make `amount_won` mean two different things.
    v_js := t_pst_state(ow, b_fee);
    if (v_js->'row'->>'amount_won') is not null then
      v_bad := v_bad || ' fee_unminted printed bookings.cancel_fee as amount_won: '
                     || (v_js->'row'->>'amount_won');
    end if;

    -- ⓑ MINT IT — the same booking, one new row. `mint_cancel_fee_intent`'s own shape (0118:600).
    insert into payments (booking_id, order_id, amount, status, raw)
    values (b_fee, 'dr_pst0_fee', 12450, 'pending',
            jsonb_build_object('kind', 'cancel_fee', 'fee_kind', 'cancel_fee', 'attempts', 0));
    v_txt := t_pst_st(ow, b_fee);
    if v_txt is distinct from 'charge_pending' then
      v_bad := v_bad || ' after mint=' || coalesce(v_txt, 'NULL') || ' (want charge_pending — 0207''s arm ④ must still own a minted row)';
    end if;
    -- and NOW there is a number, from the row that answered
    v_js := t_pst_state(ow, b_fee);
    if (v_js->'row'->>'amount_won') is distinct from '12450' then
      v_bad := v_bad || ' a minted row did not carry its own amount: '
                     || coalesce(v_js->'row'->>'amount_won', 'NULL');
    end if;

    -- ⓒ UNMINT IT — back to the honest word. The answer is attributable to the payments row.
    delete from payments where booking_id = b_fee and order_id = 'dr_pst0_fee';
    v_txt := t_pst_st(ow, b_fee);
    if v_txt is distinct from 'fee_unminted' then
      v_bad := v_bad || ' after unmint=' || coalesce(v_txt, 'NULL') || ' (want fee_unminted)';
    end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('pst0','0220-T2 a cancellation whose fee was never minted says so — one cancelled_owner booking carrying cancel_fee 12450 reads fee_unminted with no reason and NO amount (bookings.cancel_fee is a real number and is still refused, because a number in amount_won means a payments row answered), minting the intent on that same booking flips it to charge_pending carrying 12450 from the row that answered, and deleting the row flips it back — so the answer is attributable to the payments row rather than to the status, and 0207''s arm ④ was not swallowed');
    else v_msg := v_bad; call _fail('pst0','0220-T2 the unminted fee, as a caused delta', v_msg); end if;
  exception when others then
    delete from payments where booking_id = b_fee and order_id = 'dr_pst0_fee';
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('pst0','0220-T2 the unminted fee, as a caused delta', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0220-T3] THE OTHER THREE ENDINGS, EACH WITH ITS OWN WORD
  ------------------------------------------------------------------------------------------
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    if t_pst_sr(ow, b_run) is distinct from 'no_charge/cancelled_by_runner' then
      v_bad := v_bad || ' cancelled_runner=' || coalesce(t_pst_sr(ow, b_run), 'NULL'); end if;
    if t_pst_sr(ow, b_exp) is distinct from 'no_charge/expired' then
      v_bad := v_bad || ' expired=' || coalesce(t_pst_sr(ow, b_exp), 'NULL'); end if;
    if t_pst_sr(ow, b_ns) is distinct from 'no_charge/no_show' then
      v_bad := v_bad || ' no_show=' || coalesce(t_pst_sr(ow, b_ns), 'NULL'); end if;

    -- 🔴 THE ARM THAT MAKES THE THREE ABOVE MEAN SOMETHING: the four endings must produce four
    -- DIFFERENT reasons. 0207 §0a collapsed `no_charge`'s two causes into one token deliberately,
    -- and a later reader could 「simplify」 these the same way — that collapse would leave each
    -- equality above satisfiable only by luck and this set arm is what refuses it.
    select count(distinct r) into v_n from (
      select t_pst_sr(ow, b_free) as r union all select t_pst_sr(ow, b_run)
      union all select t_pst_sr(ow, b_exp) union all select t_pst_sr(ow, b_ns)) z;
    if v_n <> 4 then
      v_bad := v_bad || ' the four endings produced only ' || v_n || ' distinct state/reason pairs';
    end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('pst0','0220-T3 every ending in 0075:750''s four gets its own reason — cancelled_runner→cancelled_by_runner, expired→expired, no_show→no_show beside T1''s cancelled_free, each asserted by value AND the four asserted DISTINCT as a set, so a later collapse into one token (the shape 0207 §0a chose for not_charging, and the wrong choice here because these four leak nothing the owner does not already read on the same screen) reddens this pin rather than passing by luck');
    else v_msg := v_bad; call _fail('pst0','0220-T3 four endings, four reasons', v_msg); end if;
  exception when others then
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('pst0','0220-T3 four endings, four reasons', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0220-T4] THE FIVE ANSWERS THAT MUST NOT MOVE — a refinement that eats its neighbours is not
  ------------------------------------------------------------------------------------------
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    if t_pst_st(ow, b_swp)  is distinct from 'settled_without_payment' then
      v_bad := v_bad || ' b_swp=' || coalesce(t_pst_st(ow, b_swp), 'NULL'); end if;
    if t_pst_st(ow, b_new)  is distinct from 'settling' then
      v_bad := v_bad || ' b_new=' || coalesce(t_pst_st(ow, b_new), 'NULL'); end if;
    -- the one state the shipped copy was ALWAYS right about: a run that stopped and never settled
    if t_pst_st(ow, b_stop) is distinct from 'awaiting_settlement' then
      v_bad := v_bad || ' b_stop=' || coalesce(t_pst_st(ow, b_stop), 'NULL'); end if;
    -- LOOK terminal, are not: both are recoverable by a human (0117:637-640, 0193:973 groups them
    -- outside its four). A booking in either still has a real financial process in front of it.
    if t_pst_st(ow, b_inc)  is distinct from 'awaiting_settlement' then
      v_bad := v_bad || ' incident_review was swallowed by the terminal fork: '
                     || coalesce(t_pst_st(ow, b_inc), 'NULL'); end if;
    if t_pst_st(ow, b_ref)  is distinct from 'awaiting_settlement' then
      v_bad := v_bad || ' refund_pending was swallowed by the terminal fork: '
                     || coalesce(t_pst_st(ow, b_ref), 'NULL'); end if;

    -- 🔴 THE CUTOVER PAIR STILL OUTRANKS THE FORK. The SAME free cancellation, read with the flag
    -- NULL, must answer `not_charging` — 0084:264-266's sentence, not 0220's. This is the arm a
    -- fork hoisted in front of the flag check would redden, and it is measured on one booking in
    -- two worlds so the difference is attributable to the flag alone.
    update ops_flags set payments_live_since = null, updated_at = now();
    if t_pst_sr(ow, b_free) is distinct from 'no_charge/not_charging' then
      v_bad := v_bad || ' with the flag NULL b_free=' || coalesce(t_pst_sr(ow, b_free), 'NULL')
                     || ' (want no_charge/not_charging — the cutover pair outranks the fork)';
    end if;
    if t_pst_sr(ow, b_fee) is distinct from 'no_charge/not_charging' then
      v_bad := v_bad || ' with the flag NULL b_fee=' || coalesce(t_pst_sr(ow, b_fee), 'NULL');
    end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('pst0','0220-T4 the neighbours are untouched — settled_without_payment, settling and a stopped-but-unsettled run all answer exactly as they did before 0220, incident_review and refund_pending are NOT swallowed by the terminal fork (they LOOK terminal and are recoverable by a human, 0117:637-640), and 🔴 the cutover pair still outranks the fork: the SAME free cancellation read with payments_live_since NULL answers no_charge/not_charging rather than no_charge/cancelled_free, measured on one booking in two flag worlds so the difference is attributable to the flag alone');
    else v_msg := v_bad; call _fail('pst0','0220-T4 the neighbours are untouched', v_msg); end if;
  exception when others then
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('pst0','0220-T4 the neighbours are untouched', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0220-T5] THE REFINEMENT, MEASURED — nothing left the populations it was not allowed to
  ------------------------------------------------------------------------------------------
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    -- CONTROL FIRST: the board must actually be reporting something, or 「the board reports none
    -- of them」 is an empty board agreeing with an empty claim.
    if t_pst_board(b_swp) is not true then
      v_bad := v_bad || ' CONTROL: arm eight reports nothing even for b_swp — this pin''s second measurement is empty';
    end if;

    -- ① every fixture answering a 0220 word has NO SETTLED RUN — which is the pre-0220 branch
    --    condition (`v_settled is null or v_ended_raw is null`) re-derived from the DATA rather
    --    than from the function, so the two sides are independent measurements.
    foreach v_id in array b_all loop
      v_txt := t_pst_st(ow, v_id);
      if v_txt in ('no_charge', 'fee_unminted')
         and exists (select 1 from runs r where r.booking_id = v_id
                       and r.ended_at is not null and r.settled_at is not null) then
        v_bad := v_bad || ' ' || left(v_id::text, 8) || ' answers ' || v_txt
                       || ' although its run SETTLED — the fork escaped the awaiting_settlement branch';
      end if;
      -- ② and arm eight must not have lost or gained a row: the board's population is exactly the
      --    `settled_without_payment` answer, before and after 0220.
      if (v_txt = 'settled_without_payment') is distinct from (t_pst_board(v_id) is true) then
        v_bad := v_bad || ' BOARD DISAGREE ' || left(v_id::text, 8) || ': screen=' || v_txt
                       || ' board=' || coalesce(t_pst_board(v_id)::text, 'NULL');
      end if;
    end loop;

    -- ③ and the five new-word fixtures are, specifically, invisible to the board — which is the
    --    half of the finding that says nobody else was going to catch this.
    foreach v_id in array b_new_words loop
      if t_pst_board(v_id) is not false then
        v_bad := v_bad || ' the board now reports ' || left(v_id::text, 8);
      end if;
    end loop;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('pst0','0220-T5 the fork is a strict REFINEMENT of awaiting_settlement, measured rather than argued — over all ten fixtures, no booking answering a 0220 word has a settled run (the pre-0220 branch condition re-derived from the rows rather than read off the function), the screen and payments_reconciliation arm eight still agree as SETS with the board observed reporting FIRST, and the five terminal fixtures are specifically invisible to the board, which is why the owner was the only person being told anything about them');
    else v_msg := v_bad; call _fail('pst0','0220-T5 the fork refines awaiting_settlement', v_msg); end if;
  exception when others then
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('pst0','0220-T5 the fork refines awaiting_settlement', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0220-C1] 0207'S INVARIANTS, STILL TRUE OF THE NEW STATES
  ------------------------------------------------------------------------------------------
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    -- exactly one row, always, with a non-NULL state. Zero rows would hand the caller back the
    -- absence-with-two-meanings 0207 exists to remove.
    foreach v_id in array b_all loop
      v_js := t_pst_state(ow, v_id);
      if (v_js->>'n') is distinct from '1' then
        v_bad := v_bad || ' rows=' || coalesce(v_js->>'n', 'RAISED') || ' for ' || left(v_id::text, 8);
      end if;
      if (v_js->'row'->>'state') is null then
        v_bad := v_bad || ' NULL state for ' || left(v_id::text, 8);
      end if;
    end loop;

    -- amount_won is NULL on every state no payments row answered…
    foreach v_id in array b_new_words loop
      v_js := t_pst_state(ow, v_id);
      if (v_js->'row'->>'amount_won') is not null then
        v_bad := v_bad || ' amount on ' || left(v_id::text, 8) || '=' || (v_js->'row'->>'amount_won');
      end if;
    end loop;
    -- …and the CONTROL that stops that arm passing merely because nothing in the fixture has an
    -- amount: a real payments row still produces one.
    insert into payments (booking_id, order_id, amount, status, raw)
    values (b_ns, 'dr_pst0_ctl', 7700, 'pending',
            jsonb_build_object('kind', 'cancel_fee', 'attempts', 0));
    v_js := t_pst_state(ow, b_ns);
    if (v_js->'row'->>'amount_won') is distinct from '7700' then
      v_bad := v_bad || ' CONTROL: a real payments row produced no amount ('
                     || coalesce(v_js->'row'->>'amount_won', 'NULL') || ')';
    end if;
    delete from payments where booking_id = b_ns and order_id = 'dr_pst0_ctl';

    -- the party gate, on the NEW states too: one word for the runner, the stranger and a booking
    -- that does not exist, so the id is not an existence oracle.
    if t_pst_st(rn, b_free) is distinct from 'RAISED:not_party' then
      v_bad := v_bad || ' runner=' || coalesce(t_pst_st(rn, b_free), 'NULL'); end if;
    if t_pst_st(oz, b_free) is distinct from 'RAISED:not_party' then
      v_bad := v_bad || ' stranger=' || coalesce(t_pst_st(oz, b_free), 'NULL'); end if;
    if t_pst_st(ow, '00000000-0000-0000-0000-000000000000'::uuid) is distinct from 'RAISED:not_party' then
      v_bad := v_bad || ' ghost=' || coalesce(t_pst_st(ow, '00000000-0000-0000-0000-000000000000'::uuid), 'NULL'); end if;
    if t_pst_st(null, b_free) is distinct from 'RAISED:not_authenticated' then
      v_bad := v_bad || ' anon=' || coalesce(t_pst_st(null, b_free), 'NULL'); end if;
    -- CONTROL: the owner passes on the same id, so the three refusals are about the CALLER.
    if t_pst_st(ow, b_free) is distinct from 'no_charge' then
      v_bad := v_bad || ' CONTROL: the owner cannot read the id the other three were refused'; end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('pst0','0220-C1 0207''s invariants survive the new vocabulary — exactly one row with a non-NULL state for all ten fixtures, amount_won NULL on all five terminal answers WITH the control that a real payments row still produces one (so the NULL arm is not passing because the fixture has no money in it), and the party gate unchanged: the runner, a stranger who is a real owner, and a booking that does not exist all get the identical not_party, anonymous gets not_authenticated, and the owner passes on the same id');
    else v_msg := v_bad; call _fail('pst0','0220-C1 one row, no invented amount, one refusal word', v_msg); end if;
  exception when others then
    delete from payments where order_id = 'dr_pst0_ctl';
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('pst0','0220-C1 one row, no invented amount, one refusal word', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0220-S1] THE DEPLOYED SHAPE — read back from the catalog, comments stripped
  ------------------------------------------------------------------------------------------
  begin
    v_bad := '';
    select p.oid, p.prosrc, p.prosecdef,
           coalesce(array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%', false)
      into v_oid, v_raw, v_secdef, v_path
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'my_booking_payment_state' and p.pronargs = 1;

    -- loud on absence: a NULL prosrc makes every position() below NULL, and a set of silent arms
    -- is exactly how a source pin passes on a function that is not there at all.
    if v_oid is null then
      v_bad := v_bad || ' NO-FUNCTION(my_booking_payment_state/1)';
    elsif v_raw is null then
      v_bad := v_bad || ' NO-SOURCE(prosrc is NULL — every arm below would have been silent)';
    else
      v_src := regexp_replace(v_raw, '--[^\n]*', '', 'g');
      -- stripper control, both directions: it must have removed SOMETHING (or our own prose could
      -- satisfy every arm below — the comment-matching law) and the arms below fail loudly if it
      -- removed everything.
      if (length(v_src) < length(v_raw)) is not true then
        v_bad := v_bad || ' STRIPPER-NO-OP'; end if;

      -- the terminal set is 0075:750's four, by literal
      if (v_src like '%''expired'', ''cancelled_owner'', ''cancelled_runner'', ''no_show''%') is not true then
        v_bad := v_bad || ' TERMINAL-SET-DIVERGED(0075:750)'; end if;
      -- the fee read is coalesced: `bookings.cancel_fee` is nullable (0001:185) and a bare
      -- comparison on NULL would make the zero-fee arm silent — the plpgsql NULL-IF collapse
      if (v_src like '%coalesce(tb.cancel_fee, 0)%') is not true then
        v_bad := v_bad || ' FEE-READ-NOT-COALESCED(0001:185)'; end if;
      if (position('fee_unminted' in v_src) > 0) is not true then
        v_bad := v_bad || ' NO-fee_unminted-ARM'; end if;

      -- POSITION, which is the property §0b of 0220 rests on: cutover pair, then the fork, then
      -- the surviving awaiting_settlement assignment. Presence of each is asserted before any
      -- comparison, because position() returns 0 for ABSENT and 0 < n is true.
      v_cut   := position('v_state := ''no_charge''; v_reason := ''not_charging''' in v_src);
      v_term  := position('''cancelled_owner'', ''cancelled_runner''' in v_src);
      v_await := position('v_state := ''awaiting_settlement''' in v_src);
      if (v_cut > 0) is not true then v_bad := v_bad || ' CUTOVER-ARM-GONE';
      elsif (v_term > 0) is not true then v_bad := v_bad || ' TERMINAL-FORK-ABSENT';
      elsif (v_await > 0) is not true then v_bad := v_bad || ' AWAITING-ARM-GONE(the fork must REFINE that branch, not replace it)';
      elsif (v_cut < v_term) is not true then v_bad := v_bad || ' CUTOVER-NOT-FIRST';
      elsif (v_term < v_await) is not true then v_bad := v_bad || ' FORK-AFTER-AWAITING';
      end if;

      -- the party gate still precedes every read, including 0220's own `from bookings tb`
      v_gate := position('not_party' in v_src);
      v_read := least(nullif(position('from payments p' in v_src), 0),
                      nullif(position('from ops_flags f' in v_src), 0),
                      nullif(position('from runs r' in v_src), 0),
                      nullif(position('from bookings tb' in v_src), 0));
      if (v_gate > 0) is not true then v_bad := v_bad || ' PARTY-GATE-ABSENT';
      elsif (v_read > 0) is not true then v_bad := v_bad || ' NO-READ-FOUND';
      elsif (v_gate < v_read) is not true then
        v_bad := v_bad || ' GATE-AFTER-READ(gate=' || v_gate || ' read=' || v_read || ')'; end if;

      -- 0207's three load-bearing strings survived the re-declaration
      if (v_src like '%(p.raw->>''kind'') is not null or p.status in (''confirmed'', ''waived'')%') is not true then
        v_bad := v_bad || ' QUALIFYING-PREDICATE-DIVERGED(0173:211)'; end if;
      if (v_src like '%now() - interval ''1 hour''%') is not true then
        v_bad := v_bad || ' GRACE-MISSING(0173:207)'; end if;
      if (v_src like '%payments_live_since%') is not true then
        v_bad := v_bad || ' CUTOVER-SCOPE-MISSING(0084:264)'; end if;

      if v_secdef is not true then v_bad := v_bad || ' NOT-SECURITY-DEFINER'; end if;
      if v_path   is not true then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is distinct from false then
        v_bad := v_bad || ' ANON-CAN-EXECUTE'; end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is distinct from true then
        v_bad := v_bad || ' AUTHENTICATED-CANNOT-EXECUTE'; end if;
    end if;

    if v_bad = ''
      then call _pass('pst0','0220-S1 the deployed shape: SECURITY DEFINER with an in-body search_path and the ACL asserted in BOTH directions (anon refused, authenticated granted — a definer reading payments.raw born PUBLIC-executable is the worst shape this repo can produce), and in the comment-stripped body: 0075:750''s four statuses by literal, the fee read coalesced so a NULL cancel_fee cannot silence the zero-fee arm, a fee_unminted arm, the ORDER cutover < fork < awaiting_settlement with each one''s PRESENCE asserted before any position comparison (position() returns 0 for absent and 0 < n is true), the party gate before every read including 0220''s own `from bookings tb`, 0207''s three load-bearing predicates intact, and a NO-FUNCTION/NO-SOURCE arm plus a stripper control so none of the above can be satisfied by our own prose');
    else v_msg := v_bad; call _fail('pst0','0220-S1 the deployed shape', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('pst0','0220-S1 the deployed shape', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
