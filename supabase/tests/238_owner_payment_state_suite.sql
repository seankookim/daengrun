-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 238 — 0207: the owner is told the payment STATE, not a row count. Tag `ops7`.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Pins 0207-P1 · P2 · P3 · P4 · P5 · P6 · P7 · S1 · S2.
--
-- ─── WHAT EACH PIN ESTABLISHES, STATED WITHOUT REFERENCE TO ANY MUTATION ───────────────────────
--  · **0207-P1** — the function and `payments_reconciliation()` arm eight AGREE, as SETS, over a
--        fixture family built to straddle every one of arm eight's conjuncts. This is the pin the
--        whole slice exists for: the owner's sentence and the ops board's row are the same fact.
--        Two independent measurements, not one printed twice — the board is a `union all` of eight
--        `select`s rooted in `payments`, the function is a plpgsql ladder rooted in `runs`, and
--        they share no code.
--  · **0207-P2** — the REASON is arm eight's own `case`, in the sweep's own order: `end_reason`
--        NULL first (`0116:100` runs before `0116:112`), then `actual_km`, then `unpriced`. Read
--        out of BOTH surfaces on the same three bookings, so a reason that drifted on one side
--        shows as a disagreement rather than as two matching mistakes.
--  · **0207-P3** — a `payments` row DECIDES, and each of the six statuses the vocabulary admits
--        gets its own state: confirmed→charged (with `charged_at`), waived→waived (+the open
--        incident marker), pending→charge_pending, failed below the cap→charge_retrying, failed at
--        the cap→arrears/ladder_exhausted, failed+relink BELOW the cap→arrears/card_relink (the
--        arm that proves the relink conjunct is checked independently of the count), and
--        canceled/partial_canceled→refunded carrying which.
--  · **0207-P4** — the cutover pair (`0084:264-266`): the flag NULL and a pre-cutover run both
--        answer `no_charge`, and an unsettled run answers `awaiting_settlement` — the one state
--        today's shipped copy is honest about. The grace boundary is crossed in both directions.
--  · **0207-P5** — the PARTY GATE runs before any read: the RUNNER, a stranger and a
--        **non-existent** booking all get the identical `not_party` (that identity is the only
--        evidence of ORDER available from outside), an anonymous caller gets `not_authenticated`,
--        and the owner passes on the same id (the control that makes the refusals mean something).
--  · **0207-P6** — EXACTLY ONE ROW, ALWAYS, for every fixture in this file and in BOTH flag
--        worlds, with a non-null `state`; and `amount_won` is non-null exactly when a payments row
--        answered. Zero rows would hand the client back the absence-with-two-meanings this slice
--        removes.
--  · **0207-P7** — the qualifying predicate is arm eight's WIDER one (`0173:211`): kind-less widget
--        debris does NOT answer the charge question (the booking stays `settled_without_payment`),
--        while a kind-bearing `canceled` row DOES (it becomes `refunded`). Those are exactly the
--        two rows where the wider predicate and the mint's narrower one disagree — the fixture
--        sits in the divergence zone on purpose, because one anywhere else would be testing the
--        fixture (`175 V2`'s neighbour law).
--  · **0207-S1** — the deployed shape: definer, in-body `search_path`, ACL both directions, the
--        gate PRECEDING the first read in comment-stripped source, and NO-FUNCTION / NO-SOURCE
--        arms that fail loudly instead of collapsing to silence.
--  · **0207-S2** — every status `payments_status_vocab` admits has an explicit arm in the
--        function's comment-stripped source. The CHECK's literals are read out of `pg_constraint`
--        rather than typed here, so this pin reddens BOTH when an arm is deleted AND when the
--        vocabulary grows without one.
--
-- ─── NAMED GAPS — facts about the system, written as prose because a pin could not redden ─────
--  · 🔴 **The `unknown` arm is NOT pinned.** Every value `payments_status_vocab` (`0080:145-147`)
--    admits has an explicit arm, so no fixture this harness can build reaches the `else`. A pin
--    over it would be green by construction and would read as coverage forever (the house law: a
--    limitation is prose, not an unfalsifiable arm). `0207-S2` pins the property that makes the
--    `else` unreachable, which is the part that can actually break.
--  · **`charged_at`'s provenance is asserted as a VALUE, not as a mechanism.** P3 compares it to
--    the row's own `updated_at`; that every capture writer sets the two in ONE statement is a fact
--    about three TypeScript files (`confirm-payment:186,286`, `collect-charges:305-310`,
--    `_shared/charge.ts` §flip) that no SQL pin can reach. Named here rather than implied.
--  · **`_charge_int`'s absent-vs-garbage collapse** (`0116:211-217` returns NULL for both) is
--    exercised only through the direction a real writer can produce. Adding a garbage fixture
--    would run the same code path twice and report it as two measurements.
--  · 🔴 **`security invoker` IS NOT BEHAVIOURALLY OBSERVABLE FROM THIS HARNESS, and the battery
--    measured it rather than the suite assuming it.** `my_booking_payment_state` calls three
--    helpers that are revoked from `authenticated` (`_charge_int`, `_charge_bool`,
--    `charge_max_attempts` — `0116:285-289`), so as INVOKER it raises `42501` for every real
--    caller. Planting `security invoker` reddens **`0207-S1` alone** (1437/1) and NO behavioural
--    pin, because every call in this file is made by the SUPERUSER THAT OWNS those helpers. So
--    `S1`'s `prosecdef` arm is not belt-and-braces beside the P-pins — it is the only detector
--    this repo has for that edit, and no fixture here could replace it.
--  · ⚠ **Removing the `revoke` reddens two STANDING guards this file did not write** — `[hard] H9`
--    and `[sec] S1`, the schema-wide definer-ACL sweeps — alongside `0207-S1` (1435/3). Recorded
--    because it is corroboration from an independent instrument rather than a second copy of this
--    file's own opinion, and because it is the evidence that those sweeps are live.
--
-- ─── FIXTURE NOTES THAT ARE LOAD-BEARING ──────────────────────────────────────────────────────
--  ① This suite builds its OWN world (`ops7_*` profiles, `t_o7_*` helpers) rather than borrowing
--    203's. A pin that inherits another suite's setup is testing that setup (`175 V2`'s law), and
--    203's fixtures move for 203's reasons.
--  ② `ops_flags` is armed by WHOLE-ROW SNAPSHOT and restored by value in every pin that touches
--    it, INCLUDING each exception handler — 203 ① records what happens when fixture state escapes
--    a pin (three reds, two naming the wrong thing).
--  ③ `runs` rows are INSERTED directly rather than driven through `end_run_tx`/`confirm_return_tx`.
--    Correct here for 203 ②'s reason: this file is about a QUERY, and the real settle path cannot
--    produce the states the query exists to report — a NULL `actual_km` is precisely the row
--    `settle_run_tx` never writes. `119 R10` owns the real path end-to-end.
--  ④ Every call goes through `t_o7_state`, which sets the caller's claim, reports the ROW **or**
--    the raise and never both, and always clears the claim — so 「the state is X」 and 「nothing
--    could be read at all」 are two different answers rather than one swallowed one.
--
-- ─── MUTATION MAP — measured against these exact files. Reproduced in the REGISTRY row. ───────
set client_min_messages = warning;

-- ---------- suite-local helpers ④ ----------
-- ONE call, fully judged: the caller's claim, the row as jsonb, or the raise. Never both.
create or replace function t_o7_state(p_uid uuid, p_booking uuid) returns jsonb
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

-- the state alone, or the literal word `RAISED:<sqlerrm>` — for the arms that compare one string.
-- ONE inner call, deliberately: a `case` over three invocations would set and clear the claim
-- three times and make every such arm a different measurement from the ones that read the row.
create or replace function t_o7_st(p_uid uuid, p_booking uuid) returns text
language plpgsql as $$
declare v jsonb;
begin
  v := t_o7_state(p_uid, p_booking);
  if v->>'raised' is not null then return 'RAISED:' || (v->>'raised'); end if;
  return coalesce(v->'row'->>'state', '(null)');
end $$;

-- a settled, unpriceable booking aged by `p_ago`, with NO payments row — the shape arm eight is
-- anchored on. `p_km` / `p_reason` NULL are the sweep's two traced refusals.
create or replace function t_o7_settled(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid,
                                        p_ago interval, p_km numeric, p_reason text,
                                        p_status booking_status default 'completed')
returns uuid language plpgsql as $$
declare v uuid;
begin
  v := t_av_booking(p_owner, p_dog, p_route, p_runner,
                    now() - p_ago - interval '1 hour', 5.0, p_status);
  insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
  values (v, now() - p_ago - interval '1 hour', now() - p_ago, now() - p_ago,
          p_km, p_reason::end_reason);
  return v;
end $$;

-- arm eight's own answer for ONE booking. The SECOND measurement P1/P7 compare against.
create or replace function t_o7_board(p_booking uuid) returns boolean
language sql as $$
  select exists (select 1 from payments_reconciliation() r
                  where r.kind = 'settled_without_payment' and r.booking_id = p_booking)
$$;

create or replace function t_o7_board_reason(p_booking uuid) returns text
language sql as $$
  select r.payment_status from payments_reconciliation() r
   where r.kind = 'settled_without_payment' and r.booking_id = p_booking
$$;

do $$
declare
  ow uuid; rn uuid; oz uuid; rt uuid;
  d1 uuid; d2 uuid; d3 uuid; d4 uuid; d5 uuid; d6 uuid; d7 uuid; d8 uuid; d9 uuid;
  b_km   uuid;   -- settled 3h, actual_km NULL       → settled_without_payment / missing_actual_km
  b_er   uuid;   -- settled 3h, end_reason NULL      → settled_without_payment / missing_end_reason
  b_un   uuid;   -- settled 3h, both present         → settled_without_payment / unpriced
  b_inc  uuid;   -- settled 3h, booking moved to incident_review (the bookings.status divergence)
  b_new  uuid;   -- settled 10 minutes ago           → settling
  b_stop uuid;   -- run stopped, never settled       → awaiting_settlement
  b_old  uuid;   -- settled, but the run ENDED before the cutover → no_charge
  b_pay  uuid;   -- settled 3h, P3's stage for a payments row
  b_wid  uuid;   -- settled 3h, P7's stage for widget debris
  v_flags jsonb; v_cur jsonb;
  v_bad text := ''; v_msg text; v_n int; v_js jsonb; v_txt text; v_b boolean;
  v_src text; v_raw text; v_oid oid; v_secdef boolean; v_path boolean;
  v_gate int; v_read int; v_lit text; v_def text;
  b_all uuid[];
  v_id uuid;
begin
  perform set_config('request.jwt.claim.sub', '', false);

  -- ---------- shared seed (OUTSIDE every pin — 203 ①'s law: a caught exception rolls a pin's own
  -- writes back, and a fixture more than one pin depends on must not live inside one) ----------
  ow := t_user('ops7_ow', 'owner');
  rn := t_user('ops7_rn', 'runner');
  oz := t_user('ops7_oz', 'owner');           -- a stranger who is a perfectly real owner
  rt := t_route('결제 상태 코스');
  d1 := t_dog(ow, '무측정견');  d2 := t_dog(ow, '무사유견');  d3 := t_dog(ow, '미가격견');
  d4 := t_dog(ow, '사건견');    d5 := t_dog(ow, '갓정산견');  d6 := t_dog(ow, '목줄견');
  d7 := t_dog(ow, '파일럿견');  d8 := t_dog(ow, '청구견');    d9 := t_dog(ow, '위젯견');

  select to_jsonb(f.*) into v_flags from ops_flags f where f.id;

  b_km   := t_o7_settled(ow, d1, rt, rn, interval '3 hours', null, 'completed');
  b_er   := t_o7_settled(ow, d2, rt, rn, interval '3 hours', 5.0,  null);
  b_un   := t_o7_settled(ow, d3, rt, rn, interval '3 hours', 5.0,  'completed');
  -- the divergence zone for the `bookings.status` substitution `0116:47-52` refuses BY NAME: a
  -- SETTLED booking that legitimately moved on. An anchor on the display status HIDES it.
  b_inc  := t_o7_settled(ow, d4, rt, rn, interval '3 hours', null, 'completed', 'incident_review');
  -- identical to b_km in every respect but the clock, so the grace is the ONLY difference
  b_new  := t_o7_settled(ow, d5, rt, rn, interval '10 minutes', null, 'completed');
  b_pay  := t_o7_settled(ow, d8, rt, rn, interval '3 hours', 5.0,  'completed');
  b_wid  := t_o7_settled(ow, d9, rt, rn, interval '3 hours', null, 'completed');
  -- the run STOPPED and was never settled: the dog may still be on the leash
  b_stop := t_av_booking(ow, d6, rt, rn, now() - interval '4 hours', 5.0, 'completed');
  insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
  values (b_stop, now() - interval '4 hours', now() - interval '3 hours', null,
          null, 'completed'::end_reason);
  -- a settled run that ENDED 30 days ago — `0084:266`'s 「pilot-era run: free, forever」
  b_old  := t_o7_settled(ow, d7, rt, rn, interval '30 days', 5.0, 'completed');

  b_all := array[b_km, b_er, b_un, b_inc, b_new, b_stop, b_old, b_pay, b_wid];

  ------------------------------------------------------------------------------------------
  -- [0207-P1] THE OWNER'S SENTENCE AND THE OPS BOARD'S ROW ARE THE SAME FACT
  ------------------------------------------------------------------------------------------
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    -- CONTROL: the board must actually be reporting something, or 「they agree」 is two empties
    -- agreeing. An absence measured over a world that never held the thing is worth zero.
    if t_o7_board(b_km) is not true then
      v_bad := v_bad || ' CONTROL: the board reports nothing for b_km — this pin''s second measurement is empty';
    end if;

    foreach v_id in array b_all loop
      v_b   := t_o7_board(v_id);
      v_txt := t_o7_st(ow, v_id);
      if (v_txt = 'settled_without_payment') is distinct from (v_b is true) then
        v_bad := v_bad || ' DISAGREE ' || left(v_id::text, 8) || ': screen=' || v_txt
                       || ' board=' || coalesce(v_b::text, 'NULL');
      end if;
    end loop;

    -- the booking that moved on to `incident_review` is IN the agreeing set, which is what makes
    -- this a measurement of the RUN's settlement rather than of the booking's display status.
    if t_o7_st(ow, b_inc) is distinct from 'settled_without_payment' then
      v_bad := v_bad || ' a settled booking now at incident_review vanished from the screen=' ||
        t_o7_st(ow, b_inc);
    end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('ops7','0207-P1 the owner-facing state and payments_reconciliation arm eight agree as SETS over nine fixtures straddling every conjunct (anchor, grace, cutover scope, display status, qualifying row) — including a settled booking that moved on to incident_review, which a bookings.status anchor would hide; the board is observed reporting FIRST, so the agreement is not two empties matching');
    else v_msg := v_bad; call _fail('ops7','0207-P1 board/screen set agreement', v_msg); end if;
  exception when others then
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ops7','0207-P1 board/screen set agreement', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0207-P2] THE REASON IS THE SWEEP'S OWN, IN THE SWEEP'S OWN ORDER
  ------------------------------------------------------------------------------------------
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    v_js := t_o7_state(ow, b_er);
    if v_js->'row'->>'reason' is distinct from 'missing_end_reason' then
      v_bad := v_bad || ' end_reason-NULL reason=' || coalesce(v_js->'row'->>'reason', 'NULL'); end if;
    if t_o7_board_reason(b_er) is distinct from (v_js->'row'->>'reason') then
      v_bad := v_bad || ' board disagrees on the end_reason row: board=' ||
        coalesce(t_o7_board_reason(b_er), 'NULL'); end if;

    v_js := t_o7_state(ow, b_km);
    if v_js->'row'->>'reason' is distinct from 'missing_actual_km' then
      v_bad := v_bad || ' actual_km-NULL reason=' || coalesce(v_js->'row'->>'reason', 'NULL'); end if;
    if t_o7_board_reason(b_km) is distinct from (v_js->'row'->>'reason') then
      v_bad := v_bad || ' board disagrees on the actual_km row'; end if;

    v_js := t_o7_state(ow, b_un);
    if v_js->'row'->>'reason' is distinct from 'unpriced' then
      v_bad := v_bad || ' both-columns-present reason=' || coalesce(v_js->'row'->>'reason', 'NULL')
                     || ' (expected unpriced — the mint''s exception leaves no database trace)'; end if;
    if t_o7_board_reason(b_un) is distinct from 'unpriced' then
      v_bad := v_bad || ' board disagrees on the unpriced row'; end if;

    -- 🔴 THE ORDER. A run missing BOTH columns must say `missing_end_reason` — the sweep refuses
    --    on end_reason first (`0116:100` precedes `0116:112`), so that is the reason an operator
    --    would read, and a screen naming the other column would send a person to the wrong place.
    if (select r.end_reason from runs r where r.booking_id = b_er) is not null then
      v_bad := v_bad || ' CONTROL: b_er''s end_reason is not NULL'; end if;
    update runs set actual_km = null where booking_id = b_er;
    if (t_o7_state(ow, b_er))->'row'->>'reason' is distinct from 'missing_end_reason' then
      v_bad := v_bad || ' 🔴 with BOTH columns missing the order inverted=' ||
        coalesce((t_o7_state(ow, b_er))->'row'->>'reason', 'NULL'); end if;
    update runs set actual_km = 5.0 where booking_id = b_er;

    -- 🔴 AND THE AMOUNT IS NOT GUESSED (0173:100-101). The defining property of these rows is
    --    that nobody could price them; a number here would be fabricated.
    if (t_o7_state(ow, b_un))->'row'->>'amount_won' is not null then
      v_bad := v_bad || ' 🔴 an unpriceable row carries an amount=' ||
        coalesce((t_o7_state(ow, b_un))->'row'->>'amount_won', '?'); end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('ops7','0207-P2 the reason is the sweep''s own refusal in the sweep''s own order — missing_end_reason before missing_actual_km (a run missing BOTH says end_reason, because 0116:100 runs before 0116:112), then unpriced when both columns are present; every reason is read from the ops board too and must match, so a drift on one side shows as a disagreement rather than as two matching mistakes; and amount_won stays NULL because nobody could price the row');
    else v_msg := v_bad; call _fail('ops7','0207-P2 reason ladder equals the sweep''s', v_msg); end if;
  exception when others then
    update runs set actual_km = 5.0 where booking_id = b_er;
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ops7','0207-P2 reason ladder equals the sweep''s', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0207-P3] A `payments` ROW DECIDES — every status the vocabulary admits, its own state
  ------------------------------------------------------------------------------------------
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    -- CONTROL: before any row exists this booking is the settled-without-payment case, so every
    -- state below is attributable to the ROW rather than to the function having gone quiet.
    if t_o7_st(ow, b_pay) is distinct from 'settled_without_payment' then
      v_bad := v_bad || ' CONTROL: a settled booking with no payments row is not settled_without_payment=' ||
        t_o7_st(ow, b_pay); end if;

    insert into payments (booking_id, order_id, amount, status, raw)
    values (b_pay, 'ord_ops7', 24900, 'pending',
            jsonb_build_object('kind', 'settle_charge', 'attempts', 0));

    -- ⓐ pending — the mint's own output (0084:299)
    v_js := t_o7_state(ow, b_pay);
    if v_js->'row'->>'state' is distinct from 'charge_pending' then
      v_bad := v_bad || ' pending state=' || coalesce(v_js->'row'->>'state', 'NULL'); end if;
    if (v_js->'row'->>'amount_won')::int is distinct from 24900 then
      v_bad := v_bad || ' pending amount=' || coalesce(v_js->'row'->>'amount_won', 'NULL'); end if;
    if (v_js->'row'->>'intent_at')::timestamptz is distinct from
       (select p.created_at from payments p where p.order_id = 'ord_ops7') then
      v_bad := v_bad || ' intent_at is not the payments row''s created_at'; end if;
    if v_js->'row'->>'charged_at' is not null then
      v_bad := v_bad || ' 🔴 an uncollected row carries charged_at'; end if;

    -- ⓑ failed BELOW the cap, relink false — the ladder will fire again on its own
    update payments set status = 'failed',
      raw = jsonb_build_object('kind','settle_charge','attempts', charge_max_attempts() - 1)
      where order_id = 'ord_ops7';
    if t_o7_st(ow, b_pay) is distinct from 'charge_retrying' then
      v_bad := v_bad || ' failed-with-rungs-left state=' || t_o7_st(ow, b_pay); end if;

    -- ⓒ failed AT the cap — arm four's own `ladder_exhausted` (0173:162-167)
    update payments set raw = jsonb_build_object('kind','settle_charge','attempts', charge_max_attempts())
      where order_id = 'ord_ops7';
    v_js := t_o7_state(ow, b_pay);
    if v_js->'row'->>'state' is distinct from 'arrears' then
      v_bad := v_bad || ' ladder-exhausted state=' || coalesce(v_js->'row'->>'state', 'NULL'); end if;
    if v_js->'row'->>'reason' is distinct from 'ladder_exhausted' then
      v_bad := v_bad || ' ladder-exhausted reason=' || coalesce(v_js->'row'->>'reason', 'NULL'); end if;

    -- ⓓ 🔴 the relink flag with the ladder still BELOW the cap. `charge_row_due` ⓐ requires BOTH,
    --    so a function that only counted attempts would say 「retrying」 about a row that will
    --    never be retried (0116:237-239 — it waits for the owner, not for the clock). This arm is
    --    where the relink conjunct is separately observable from the count.
    update payments set raw = jsonb_build_object('kind','settle_charge','attempts', 1,
                                                 'needs_card_relink', true)
      where order_id = 'ord_ops7';
    v_js := t_o7_state(ow, b_pay);
    if v_js->'row'->>'state' is distinct from 'arrears' then
      v_bad := v_bad || ' relink-needed state=' || coalesce(v_js->'row'->>'state', 'NULL'); end if;
    if v_js->'row'->>'reason' is distinct from 'card_relink' then
      v_bad := v_bad || ' relink-needed reason=' || coalesce(v_js->'row'->>'reason', 'NULL'); end if;

    -- ⓔ confirmed — the money moved, and `charged_at` is the row's own confirm instant
    update payments set status = 'confirmed', payment_key = 'pk_ops7',
      raw = jsonb_build_object('kind','settle_charge','attempts',1),
      updated_at = now() - interval '20 minutes'
      where order_id = 'ord_ops7';
    v_js := t_o7_state(ow, b_pay);
    if v_js->'row'->>'state' is distinct from 'charged' then
      v_bad := v_bad || ' confirmed state=' || coalesce(v_js->'row'->>'state', 'NULL'); end if;
    if (v_js->'row'->>'charged_at')::timestamptz is distinct from
       (select p.updated_at from payments p where p.order_id = 'ord_ops7') then
      v_bad := v_bad || ' charged_at is not the payments row''s updated_at'; end if;

    -- ⓕ refunded, both shapes — arm six's two statuses (0173:179), each named
    update payments set status = 'canceled', refunded_amount = 24900 where order_id = 'ord_ops7';
    v_js := t_o7_state(ow, b_pay);
    if v_js->'row'->>'state' is distinct from 'refunded' then
      v_bad := v_bad || ' canceled state=' || coalesce(v_js->'row'->>'state', 'NULL'); end if;
    if v_js->'row'->>'reason' is distinct from 'canceled' then
      v_bad := v_bad || ' canceled reason=' || coalesce(v_js->'row'->>'reason', 'NULL'); end if;
    update payments set status = 'partial_canceled', refunded_amount = 10000 where order_id = 'ord_ops7';
    if (t_o7_state(ow, b_pay))->'row'->>'reason' is distinct from 'partial_canceled' then
      v_bad := v_bad || ' partial_canceled reason=' ||
        coalesce((t_o7_state(ow, b_pay))->'row'->>'reason', 'NULL'); end if;

    -- ⓖ waived — a DECISION at zero, not an absence; and the open incident marker rides `reason`
    --    (arm five's own predicate, 0173:172-174: resolution is the ABSENCE of the resolved key)
    update payments set status = 'waived', amount = 0, payment_key = null, refunded_amount = 0,
      raw = jsonb_build_object('kind','settle_charge','review','incident_pending',
                               'review_opened_at', now() - interval '2 hours')
      where order_id = 'ord_ops7';
    v_js := t_o7_state(ow, b_pay);
    if v_js->'row'->>'state' is distinct from 'waived' then
      v_bad := v_bad || ' waived state=' || coalesce(v_js->'row'->>'state', 'NULL'); end if;
    if v_js->'row'->>'reason' is distinct from 'incident_review' then
      v_bad := v_bad || ' the open review marker is not carried as a reason=' ||
        coalesce(v_js->'row'->>'reason', 'NULL'); end if;
    update payments set raw = raw || jsonb_build_object('review_resolved_at', now())
      where order_id = 'ord_ops7';
    if (t_o7_state(ow, b_pay))->'row'->>'reason' is not null then
      v_bad := v_bad || ' 🔴 a RESOLVED review still says it is under review=' ||
        coalesce((t_o7_state(ow, b_pay))->'row'->>'reason', '?'); end if;

    delete from payments where order_id = 'ord_ops7';
    -- and BACK: the state returns to what it was, so every answer above was the row's
    if t_o7_st(ow, b_pay) is distinct from 'settled_without_payment' then
      v_bad := v_bad || ' CONTROL: the row was deleted and the state did not return=' ||
        t_o7_st(ow, b_pay); end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('ops7','0207-P3 a payments row decides, and each status the vocabulary admits gets its own state — pending→charge_pending (amount and intent_at from the row, no charged_at), failed below the cap→charge_retrying, failed at the cap→arrears/ladder_exhausted, failed BELOW the cap with needs_card_relink→arrears/card_relink (the relink conjunct observed independently of the count), confirmed→charged with charged_at = the row''s updated_at, canceled/partial_canceled→refunded naming which, waived→waived carrying incident_review only while the review is open; deleting the row returns the booking to settled_without_payment (the control)');
    else v_msg := v_bad; call _fail('ops7','0207-P3 the payments row decides', v_msg); end if;
  exception when others then
    delete from payments where order_id = 'ord_ops7';
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ops7','0207-P3 the payments row decides', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0207-P4] THE CUTOVER PAIR, THE UNSETTLED RUN, AND THE GRACE BOUNDARY
  ------------------------------------------------------------------------------------------
  begin
    v_bad := '';
    -- ⓐ the flag NULL: the mint returns and writes nothing (0084:264). Nothing is coming.
    update ops_flags set payments_live_since = null, updated_at = now();
    if t_o7_st(ow, b_km) is distinct from 'no_charge' then
      v_bad := v_bad || ' charging off, state=' || t_o7_st(ow, b_km); end if;
    if (t_o7_state(ow, b_km))->'row'->>'reason' is distinct from 'not_charging' then
      v_bad := v_bad || ' charging off, reason=' ||
        coalesce((t_o7_state(ow, b_km))->'row'->>'reason', 'NULL'); end if;

    -- ⓑ the flag SET, and this run ended 30 days before it: 「pilot-era run: free, forever」
    --    (0084:266). The SAME bookings must cross in BOTH directions as the flag moves, so this
    --    arm measures the predicate rather than a constant.
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();
    if t_o7_st(ow, b_old) is distinct from 'no_charge' then
      v_bad := v_bad || ' pre-cutover run state=' || t_o7_st(ow, b_old); end if;
    if t_o7_st(ow, b_km) is distinct from 'settled_without_payment' then
      v_bad := v_bad || ' CONTROL: the flag is on and a post-cutover run is still no_charge=' ||
        t_o7_st(ow, b_km); end if;
    update ops_flags set payments_live_since = now() - interval '60 days', updated_at = now();
    if t_o7_st(ow, b_old) is distinct from 'settled_without_payment' then
      v_bad := v_bad || ' CONTROL: the cutover moved behind the run and it is still no_charge=' ||
        t_o7_st(ow, b_old); end if;

    -- ⓒ the run STOPPED and was never settled — the only state today's shipped copy
    --   (「아직 청구 내역이 없어요 — 정산이 끝나면 여기에 표시돼요」) is true of
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();
    if t_o7_st(ow, b_stop) is distinct from 'awaiting_settlement' then
      v_bad := v_bad || ' unsettled run state=' || t_o7_st(ow, b_stop); end if;

    -- ⓓ the GRACE: settled ten minutes ago, otherwise identical to b_km. The only difference is
    --   the clock, so `settling` and `settled_without_payment` are one conjunct apart (0173:207).
    if t_o7_st(ow, b_new) is distinct from 'settling' then
      v_bad := v_bad || ' inside-the-grace state=' || t_o7_st(ow, b_new); end if;
    if t_o7_board(b_new) is not false then
      v_bad := v_bad || ' CONTROL: a row inside the grace is on the ops board'; end if;
    update runs set settled_at = now() - interval '3 hours' where booking_id = b_new;
    if t_o7_st(ow, b_new) is distinct from 'settled_without_payment' then
      v_bad := v_bad || ' 🔴 the grace was crossed and the state is still settling=' ||
        t_o7_st(ow, b_new); end if;
    update runs set settled_at = now() - interval '10 minutes' where booking_id = b_new;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('ops7','0207-P4 the cutover pair and the two honest absences — payments_live_since NULL and a run that ended before the flip both answer no_charge/not_charging, and the same bookings cross in BOTH directions when the flag moves (so it is the predicate and not a constant); an unsettled run answers awaiting_settlement, the one state today''s shipped copy was ever true of; and a booking settled ten minutes ago answers settling, flipping to settled_without_payment on the clock alone once the grace is crossed');
    else v_msg := v_bad; call _fail('ops7','0207-P4 cutover pair, unsettled run, grace boundary', v_msg); end if;
  exception when others then
    update runs set settled_at = now() - interval '10 minutes' where booking_id = b_new;
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ops7','0207-P4 cutover pair, unsettled run, grace boundary', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0207-P5] THE PARTY GATE, AND THE IDENTITY THAT IS THE ONLY EVIDENCE OF ORDER
  ------------------------------------------------------------------------------------------
  -- A payment state is the PAYER's fact. The runner is not a party to it — their money view is
  -- `ledger_items`, and `payments.raw` carries the provider's response, which is why 0071 ships a
  -- single owner-only policy. So 「the counterparty」, 「a stranger」 and 「no such booking」 must all
  -- be one word; if they differed the id would be an existence oracle and the gate would be
  -- running after a read.
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    v_js := t_o7_state(rn, b_km);
    if v_js->>'raised' is distinct from 'not_party' then
      v_bad := v_bad || ' runner answer=' || coalesce(v_js::text, 'NULL'); end if;
    v_js := t_o7_state(oz, b_km);
    if v_js->>'raised' is distinct from 'not_party' then
      v_bad := v_bad || ' stranger answer=' || coalesce(v_js::text, 'NULL'); end if;
    -- 🔴 a booking that DOES NOT EXIST must be byte-identical to one that does
    v_js := t_o7_state(ow, '00000000-0000-0000-0000-0000000007db'::uuid);
    if v_js->>'raised' is distinct from 'not_party' then
      v_bad := v_bad || ' absent-booking answer=' || coalesce(v_js::text, 'NULL')
                     || ' (existence oracle — the gate is behind a read)'; end if;
    v_js := t_o7_state(null, b_km);
    if v_js->>'raised' is distinct from 'not_authenticated' then
      v_bad := v_bad || ' anonymous answer=' || coalesce(v_js::text, 'NULL'); end if;

    -- CONTROL ①: the owner passes on the very same id, so the refusals above are the gate and not
    -- a broken function.
    v_js := t_o7_state(ow, b_km);
    if v_js->>'raised' is not null then
      v_bad := v_bad || ' CONTROL: the owner cannot read [' || (v_js->>'raised') || ']'; end if;
    if v_js->'row'->>'state' is distinct from 'settled_without_payment' then
      v_bad := v_bad || ' CONTROL: the owner''s state=' ||
        coalesce(v_js->'row'->>'state', 'NULL'); end if;
    -- CONTROL ②: the stranger is a REAL owner with a REAL profile — the refusal is about THIS
    -- booking, not about the caller being unknown to the database.
    if (select count(*) from profiles p where p.id = oz) is distinct from 1 then
      v_bad := v_bad || ' CONTROL: the stranger is not a real profile'; end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('ops7','0207-P5 the party gate runs before any read — the RUNNER (whose money view is ledger_items, never payments), a stranger who is a real owner, and a booking that does not exist all get the identical not_party, which is the only evidence of ORDER observable from outside; an anonymous caller gets not_authenticated; and the owner passes on the same id (two controls)');
    else v_msg := v_bad; call _fail('ops7','0207-P5 party gate before any read', v_msg); end if;
  exception when others then
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ops7','0207-P5 party gate before any read', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0207-P6] EXACTLY ONE ROW, ALWAYS — the absence-with-two-meanings cannot come back
  ------------------------------------------------------------------------------------------
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();
    foreach v_id in array b_all loop
      v_js := t_o7_state(ow, v_id);
      if (v_js->>'n')::int is distinct from 1 then
        v_bad := v_bad || ' rows<>1 ' || left(v_id::text, 8) || '=' ||
          coalesce(v_js->>'n', v_js::text); end if;
      if v_js->'row'->>'state' is null then
        v_bad := v_bad || ' NULL state ' || left(v_id::text, 8); end if;
      if v_js->'row'->>'amount_won' is not null then
        v_bad := v_bad || ' 🔴 a row-less state carries an amount ' || left(v_id::text, 8) ||
          ' state=' || coalesce(v_js->'row'->>'state','NULL'); end if;
    end loop;
    -- the other direction, so the arm above is not green merely because nothing has an amount:
    -- a real payments row MUST produce one.
    insert into payments (booking_id, order_id, amount, status, raw)
    values (b_pay, 'ord_ops7_p6', 24900, 'pending',
            jsonb_build_object('kind', 'settle_charge', 'attempts', 0));
    v_js := t_o7_state(ow, b_pay);
    if (v_js->>'n')::int is distinct from 1 then
      v_bad := v_bad || ' rows<>1 with a payments row=' || coalesce(v_js->>'n', '?'); end if;
    if (v_js->'row'->>'amount_won')::int is distinct from 24900 then
      v_bad := v_bad || ' CONTROL: a real payments row produced no amount=' ||
        coalesce(v_js->'row'->>'amount_won', 'NULL'); end if;
    delete from payments where order_id = 'ord_ops7_p6';

    -- and in the OTHER flag world, because the no-row branch is the one that could `return` early
    update ops_flags set payments_live_since = null, updated_at = now();
    foreach v_id in array b_all loop
      if ((t_o7_state(ow, v_id))->>'n')::int is distinct from 1 then
        v_bad := v_bad || ' rows<>1 with charging off ' || left(v_id::text, 8); end if;
    end loop;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('ops7','0207-P6 exactly one row always — for every fixture in this file and in BOTH flag worlds, with a non-null state; zero rows would hand the caller back the absence-with-two-meanings this slice exists to remove. amount_won is NULL on every state no payments row answered, and a real payments row produces one (the control that stops the NULL arm passing merely because nothing in the fixture has an amount)');
    else v_msg := v_bad; call _fail('ops7','0207-P6 exactly one row, always', v_msg); end if;
  exception when others then
    delete from payments where order_id = 'ord_ops7_p6';
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ops7','0207-P6 exactly one row, always', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0207-P7] THE QUALIFYING PREDICATE IS THE WIDER ONE — measured in the divergence zone
  ------------------------------------------------------------------------------------------
  -- `0173:211` is DELIBERATELY WIDER than the mint's own existence check (`0116:96-106`, review
  -- round 2 finding 4 — aligning them enabled a ₩15,000+₩20,000 double-charge). The two rows
  -- where the wider and the narrower predicates DISAGREE are exactly these two.
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    -- ⓐ kind-LESS widget debris is not an answer to this booking's charge. A narrower predicate
    --   would let it blind the screen over a settled run that was never billed.
    insert into payments (booking_id, order_id, amount, status, raw)
    values (b_wid, 'ord_ops7_wid', 24900, 'pending', jsonb_build_object('attempts', 0));
    if t_o7_st(ow, b_wid) is distinct from 'settled_without_payment' then
      v_bad := v_bad || ' kind-less widget debris masked the state=' || t_o7_st(ow, b_wid); end if;
    if t_o7_board(b_wid) is not true then
      v_bad := v_bad || ' CONTROL: the board does not report the same row — the predicate narrowed on BOTH sides'; end if;

    -- ⓑ a kind-BEARING refund-vocabulary row IS an answer: this machine has touched the booking
    --   and a human resolves it. The mint's narrower check would miss it.
    update payments set status = 'canceled', payment_key = 'pk_ops7_wid', refunded_amount = 24900,
      raw = jsonb_build_object('kind', 'settle_charge', 'attempts', 1)
      where order_id = 'ord_ops7_wid';
    if t_o7_st(ow, b_wid) is distinct from 'refunded' then
      v_bad := v_bad || ' a kind-bearing refund-vocabulary row was not taken as an answer=' ||
        t_o7_st(ow, b_wid); end if;
    if t_o7_board(b_wid) is not false then
      v_bad := v_bad || ' CONTROL: the board still reports the same row as unpaid'; end if;

    delete from payments where order_id = 'ord_ops7_wid';
    if t_o7_st(ow, b_wid) is distinct from 'settled_without_payment' then
      v_bad := v_bad || ' CONTROL: the row was deleted and the state did not return=' ||
        t_o7_st(ow, b_wid); end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('ops7','0207-P7 the qualifying predicate is arm eight''s deliberately wider one — kind-less widget debris does NOT answer the charge question (the booking stays settled_without_payment and the ops board agrees) while a kind-bearing canceled row DOES (it becomes refunded and the board drops it); those two rows are exactly where the wider predicate and the mint''s narrower one disagree, so the fixture sits in the divergence zone rather than in the agreement zone');
    else v_msg := v_bad; call _fail('ops7','0207-P7 the wider qualifying predicate', v_msg); end if;
  exception when others then
    delete from payments where order_id = 'ord_ops7_wid';
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('ops7','0207-P7 the wider qualifying predicate', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0207-S1] THE DEPLOYED SHAPE — what makes every arm above mean anything
  ------------------------------------------------------------------------------------------
  -- A property checked only at apply (the migration's VERIFY) is protected exactly until someone
  -- recreates the function. `prosecdef`, the in-body `search_path` and the ACL are the
  -- preconditions this function's answers RIDE on.
  begin
    v_bad := '';
    select p.oid, p.prosrc, p.prosecdef,
           coalesce(array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%', false)
      into v_oid, v_raw, v_secdef, v_path
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'my_booking_payment_state' and p.pronargs = 1;

    -- NO-FUNCTION / NO-SOURCE, loudly and FIRST: a NULL `prosrc` makes every `position()` below
    -- NULL, and a set of silent arms is exactly how a source pin passes on a function that is not
    -- there at all (the plpgsql NULL-IF collapse that cost this repo five pins in one afternoon).
    if v_oid is null then
      v_bad := v_bad || ' NO-FUNCTION(my_booking_payment_state/1)';
    elsif v_raw is null then
      v_bad := v_bad || ' NO-SOURCE(my_booking_payment_state)';
    else
      -- ⚠ comments stripped BEFORE matching: `prosrc` is the body plus our own prose, and this
      --   function's prose names every predicate it implements. Un-stripped, a body that only
      --   DOCUMENTED the gate would satisfy the position arm below — the instrument would reward
      --   the documentation as if it were the implementation.
      v_src  := regexp_replace(v_raw, '--[^\n]*', '', 'g');
      v_gate := position('not_party' in v_src);
      v_read := least(nullif(position('from payments p' in v_src), 0),
                      nullif(position('from ops_flags f' in v_src), 0),
                      nullif(position('from runs r' in v_src), 0));
      if (v_gate > 0) is not true then v_bad := v_bad || ' the gate word is not in the body';
      elsif (v_read > 0) is not true then v_bad := v_bad || ' no read found (nothing to measure the order against)';
      elsif (v_gate < v_read) is not true then
        v_bad := v_bad || ' the gate is behind a read (gate=' || v_gate || ' read=' || v_read || ')'; end if;
      -- arm eight's predicate, verbatim — a re-derivation here stops the two surfaces agreeing
      -- for a reason no behavioural fixture in this file would necessarily catch.
      if (v_src like '%(p.raw->>''kind'') is not null or p.status in (''confirmed'', ''waived'')%') is not true
        then v_bad := v_bad || ' the qualifying predicate has drifted from 0173:211'; end if;
      if (v_src like '%now() - interval ''1 hour''%') is not true
        then v_bad := v_bad || ' the grace constant is not in the body'; end if;
      if (v_src like '%payments_live_since%') is not true
        then v_bad := v_bad || ' the cutover scope is not in the body'; end if;
      -- the two anchors 0116:47-52 refuses BY NAME, asserted positively so a NULL cannot silence them
      if (v_src like '%b.status = ''completed''%') is true
        then v_bad := v_bad || ' 🔴 bookings.status anchor'; end if;
      if (v_src like '%ledger_items%') is true
        then v_bad := v_bad || ' 🔴 ledger_items anchor'; end if;
      -- CRUDE CONTROL, in the other direction: the words really are findable in the UNSTRIPPED
      -- source, so the two absence arms above are not green because the match itself is broken.
      if (v_raw like '%payments%') is not true
        then v_bad := v_bad || ' CONTROL: even the word payments is unfindable in the raw source — the match is broken'; end if;
    end if;

    if v_secdef is not true then v_bad := v_bad || ' not SECURITY DEFINER'; end if;
    if v_path   is not true then v_bad := v_bad || ' no in-body search_path'; end if;
    if has_function_privilege('anon', 'my_booking_payment_state(uuid)', 'execute')
       is distinct from false then v_bad := v_bad || ' 🔴 anon can execute'; end if;
    if has_function_privilege('authenticated', 'my_booking_payment_state(uuid)', 'execute')
       is distinct from true then v_bad := v_bad || ' authenticated cannot execute'; end if;

    if v_bad = ''
      then call _pass('ops7','0207-S1 the deployed shape — SECURITY DEFINER with an in-body search_path, ACL both directions (anon refused, authenticated granted), and in comment-stripped source the party gate PRECEDES the first read of payments/runs/ops_flags, arm eight''s qualifying predicate appears verbatim, the 1-hour grace and the cutover scope are present, and neither anchor 0116:47-52 refuses by name is there (with a crude control proving the match itself works); NO-FUNCTION and NO-SOURCE fail loudly instead of collapsing to silence');
    else v_msg := v_bad; call _fail('ops7','0207-S1 deployed shape', v_msg); end if;
  exception when others then
    v_msg := sqlerrm; call _fail('ops7','0207-S1 deployed shape', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0207-S2] EVERY STATUS THE VOCABULARY ADMITS HAS AN ARM
  ------------------------------------------------------------------------------------------
  -- 🔴 Widening what an enum can MEAN breaks a correct caller with no edit to the caller. The
  -- literals are read out of `pg_constraint` rather than typed here, so this pin reddens both when
  -- an arm is deleted AND when a seventh status is added without one — the obligation that
  -- outlives this slice. Each literal is matched WITH ITS QUOTES: 'canceled' is a substring of
  -- 'partial_canceled', and an unquoted match would be satisfied by the wrong arm.
  begin
    v_bad := '';
    select pg_get_constraintdef(c.oid) into v_def
      from pg_constraint c
     where c.conrelid = 'payments'::regclass and c.conname = 'payments_status_vocab';
    select p.prosrc into v_raw from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'my_booking_payment_state' and p.pronargs = 1;

    if v_def is null then
      v_bad := v_bad || ' NO-CONSTRAINT(payments_status_vocab) — this pin has no vocabulary source';
    elsif v_raw is null then
      v_bad := v_bad || ' NO-SOURCE(my_booking_payment_state)';
    else
      v_src := regexp_replace(v_raw, '--[^\n]*', '', 'g');
      v_n := 0;
      for v_lit in select t.x[1] from regexp_matches(v_def, '''([a-z_]+)''', 'g') as t(x) loop
        v_n := v_n + 1;
        if (position('''' || v_lit || '''' in v_src) > 0) is not true then
          v_bad := v_bad || ' no arm for status: ' || v_lit;
        end if;
      end loop;
      -- CONTROL: the constraint really did yield a vocabulary. A zero-literal read would make the
      -- loop above pass unconditionally — the emptiest possible false green.
      if v_n < 6 then
        v_bad := v_bad || ' CONTROL: only ' || v_n || ' status words were read out of the CHECK (expected at least 6)';
      end if;
    end if;

    if v_bad = ''
      then call _pass('ops7','0207-S2 every status payments_status_vocab admits has an explicit arm in the function''s comment-stripped source — the literals are read out of pg_constraint rather than typed here, each matched WITH its quotes (canceled is a substring of partial_canceled), and the literal count is asserted so an empty vocabulary read cannot pass the loop unconditionally; this pin reddens when an arm is deleted AND when the vocabulary grows without one');
    else v_msg := v_bad; call _fail('ops7','0207-S2 the vocabulary has no unmapped status', v_msg); end if;
  exception when others then
    v_msg := sqlerrm; call _fail('ops7','0207-S2 the vocabulary has no unmapped status', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
