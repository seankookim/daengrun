-- ═══ 204 — 0174's `payments_reconciliation().row_key` — 0174-K1…K4, tag `rgk` ═══════════════
--
-- THE PROPOSITION THIS FILE OWNS: every row of the reconciliation query carries a NON-NULL key
-- that identifies its SUBJECT, so two correct rows are never mistaken for one row listed twice.
-- `0118:1372-1376` warned whoever added arm eight that `116 C11` and `120 J4` assert disjointness
-- with `group by payment_id having count(*) > 1`, and SQL groups every NULL into one group. 0173
-- added the second NULL-emitting arm and recorded the warning as unfired-in-this-fixture-chain
-- (its own words: 「the pins are green because the two populations are disjoint in this fixture
-- chain, not because anything asserts they must stay disjoint」). The wave-2 re-attack found the
-- narrower case: **two rows from arm EIGHT ALONE, on two different bookings, already collide.**
-- 0174 is the fix and this file is its battery.
--
-- ⚠ WHAT IS DELIBERATELY *NOT* PINNED HERE, because a fourth copy would be manufactured coverage:
--     · `203 0173-A1…A5` — what arm eight SEES, its reason vocabulary, its anchor, its grace.
--     · `153 P14`        — what arm seven sees, and that it leaves the board when minted.
--     · `116 C11` / `120 J4` — the disjointness invariant itself, which 0174 re-keys in place.
--   This suite asserts only what the KEY is and what it distinguishes. Nothing here mints.
--
-- ─── MUTATION MAP (plants `&&`-chained to their run, so an unlanded plant yields NO row) ────
--   CONTROL (0174's VERIFY demoted to a notice, NO plant) ⇒ 1229 / 0, so nothing below is the
--   demotion itself. Un-demoted, plants (i) and (ii) ABORT THE APPLY at 0174's VERIFY, which
--   would measure the VERIFY and not this file (0131-G4's distinction).
--   (i)  arm eight's key `'booking:' || b.id::text` → `null::text`
--          ⇒ 1226 / 3, RED = [0174-K1] [0174-K2] [0174-K4]
--   (ii) the key prefixed with the ARM NAME on every arm — the form 0174's header refuses, and
--        the form a reader reaches for first
--          ⇒ 1227 / 2, RED = [0174-K2] [0174-K3]
--   (iii) THE NOT-WEAKENED CONTROL, and the only plant that leaves this file's own pins alone:
--        drop `and (p.raw->>'dispatched_at') is null` from `stale_pending`, so ONE payments row
--        is claimed by both `stale_pending` and `stale_dispatched`
--          ⇒ 1228 / 1, RED = **[116 C11]** (`두 팔에 동시 등장하는 행 1개`) — exactly what C11's
--        own mutation map requires (「widen any arm so two arms claim one row」), now through the
--        re-keyed grouping. This is the measurement that says 0174 refined the invariant rather
--        than deleting it.
--
-- 🔴 **WHAT I PREDICTED AND THE BATTERY REFUSED, kept here because the correction is the useful
--    part.** This map's first draft said plant (i) would redden `116 C11` and `120 J4` — 「the
--    measurement that shows the moved invariant now SEES the collision」. **It does not. Measured:
--    both stay GREEN.** The cause is not a blind pin; it is that the property is **not observable
--    through those two doors** (the mutation-reddens-nothing law): at the point 116 and 120
--    execute, the board holds fewer than two `payment_id is null` rows — `0118:1376-1381` already
--    records that no fixture in suites 30…108 can reach arm seven at all, and 116/120 build no
--    arm-eight row either. So C11 and J4 could not have caught this defect before 0174 and cannot
--    demonstrate the fix now; **that is 0173's recorded gap restated, and it is exactly why this
--    file exists.** `0174-K1` is the pin that reaches the state — it re-runs the OLD grouping on
--    its own live fixture and REQUIRES a collision before asserting the new key resolves it, so
--    its number is a delta it caused. Plant (iii) is what keeps C11 and J4 honest.
--   The measured sets are reproduced in the commit message and in the REGISTRY row.
--
-- ─── FIXTURE NOTES THAT ARE LOAD-BEARING ───────────────────────────────────────────────────
--  ① `ops_flags` is armed by WHOLE-ROW SNAPSHOT and restored by whole-row value, including in the
--     exception handler of every pin that touches it (203's note ①). Both bookings-anchored arms
--     read `payments_live_since` — arm eight directly, arm seven through
--     `_club_fee_event_collectable` — so leaving the flag set would change what every later reader
--     of this database sees, and this suite runs LAST.
--  ② `runs` rows are INSERTED directly and arm seven's four `bookings` columns are SET directly,
--     rather than driven through `settle_run_tx` / `_club_record_fee`. That is correct HERE and
--     would be wrong in 202 or 153: this suite is about the QUERY's KEY, and `153 P14` already
--     owns arm seven's real production path end-to-end (mint injector + queue injector). What
--     this file needs from arm seven is one row, on a booking that is not any of arm eight's.
--  ③ The counts below are QUERY-WIDE, not fixture-scoped, and that is deliberate: the property is
--     about the whole board, and a fixture-scoped count would be satisfied by a key that
--     distinguishes my four rows and flattens everyone else's. The cost is that these pins also
--     see rows earlier suites left behind — which is exactly the population an operator sees.
set client_min_messages = warning;

do $$
declare
  ow uuid; rn uuid; rt uuid;
  dg1 uuid; dg2 uuid; dg3 uuid; dg4 uuid;
  b_e1  uuid;      -- [arm eight] settled, unpriceable, past the grace
  b_e2  uuid;      -- [arm eight] a SECOND one, different booking — the re-attack's own case
  b_c7  uuid;      -- [arm seven] a recorded, collectable club fee with no payments row
  b_pay uuid;      -- [arm two]  a payment-bearing row, so K3 is not vacuous
  p_pay uuid;
  v_flags jsonb; v_cur jsonb;
  v_bad text := ''; v_msg text; v_n int; v_n2 int; v_rows int;
  v_k1 text; v_k2 text; v_k7 text; v_kp text;
begin
  -- ---------- shared seed, OUTSIDE every pin (151's three-red cascade) ----------
  ow := t_user('rgk_ow', 'owner');
  rn := t_user('rgk_rn', 'runner');
  dg1 := t_dog(ow, '키하나견'); dg2 := t_dog(ow, '키둘견');
  dg3 := t_dog(ow, '수수료견'); dg4 := t_dog(ow, '결제행견');
  rt  := t_route('키 코스');

  -- the whole row, by value — `to_jsonb` so a column added to ops_flags later travels with it
  select to_jsonb(f.*) into v_flags from ops_flags f where f.id;

  -- ⓐ / ⓑ TWO arm-eight rows, on two DIFFERENT bookings. Both settled 3h ago with a NULL
  --   `actual_km` — the row `settle_run_tx` never writes and the sweep refuses (0116:112) — so
  --   both are correct, both carry `payment_id = NULL`, and under the old key they were ONE group.
  b_e1 := t_av_booking(ow, dg1, rt, rn, now() - interval '4 hours', 5.0, 'completed');
  insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
  values (b_e1, now() - interval '4 hours', now() - interval '3 hours', now() - interval '3 hours',
          null, 'completed'::end_reason);
  b_e2 := t_av_booking(ow, dg2, rt, rn, now() - interval '4 hours', 5.0, 'completed');
  insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
  values (b_e2, now() - interval '4 hours', now() - interval '3 hours', now() - interval '3 hours',
          null, 'completed'::end_reason);

  -- ⓒ ONE arm-seven row, on a third booking. Arm seven's four predicates, set by value
  --   (note ②): a positive `cancel_fee`, a fee KIND, an event past the one-hour threshold, and a
  --   cutover SNAPSHOT at or before the event — which is what `_club_fee_event_collectable`
  --   (`0118:513-527`) asks, together with a non-null `payments_live_since`. No payments row, so
  --   `_cancel_fee_existing_payment` is empty and the arm admits it.
  b_c7 := t_av_booking(ow, dg3, rt, null, now() - interval '5 hours', 5.0, 'refund_pending');
  update bookings
     set cancel_fee          = 2490,
         club_fee_kind       = 'cancel_fee',
         club_fee_event_at   = now() - interval '3 hours',
         club_fee_cutover_at = now() - interval '7 days'
   where id = b_c7;

  -- ⓓ a PAYMENT-BEARING row, so K3's identity arm has a subject. `stale_pending`: pending, older
  --   than an hour, never dispatched (0118 arm two).
  b_pay := t_av_booking(ow, dg4, rt, rn, now() - interval '4 hours', 5.0, 'completed');
  insert into payments (booking_id, order_id, amount, status, created_at)
  values (b_pay, 'ord_rgk_stale', 26900, 'pending', now() - interval '3 hours')
  returning id into p_pay;

  ------------------------------------------------------------------------------------------
  -- [0174-K1] two NULL-payment_id rows from DIFFERENT arms are TWO keys, not one
  ------------------------------------------------------------------------------------------
  -- ⚠ This pin is a DELTA IT CAUSES, not a state it finds. Its middle arm re-runs the OLD
  --   grouping on the same live query and requires it to COLLIDE — so if the defect stopped being
  --   reproducible in this fixture, the pin says so out loud instead of passing for free. That is
  --   the difference between testing the rule and testing the setup.
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    -- the two subjects are really on the board, each exactly once, each with no payments row
    select count(*) into v_n from payments_reconciliation()
      where kind = 'settled_without_payment' and booking_id = b_e1 and payment_id is null;
    if v_n is distinct from 1 then
      v_bad := v_bad || ' NO-SUBJECT(여덟째 팔 행이 없다=' || coalesce(v_n::text,'NULL') || ')'; end if;
    select count(*) into v_n from payments_reconciliation()
      where kind = 'club_fee_unminted' and booking_id = b_c7 and payment_id is null;
    if v_n is distinct from 1 then
      v_bad := v_bad || ' NO-SUBJECT(일곱째 팔 행이 없다=' || coalesce(v_n::text,'NULL') || ')'; end if;

    -- ⓐ THE OLD KEY STILL COLLIDES on exactly this state — the defect, reproduced, not assumed
    select count(*) into v_n from (
      select payment_id from payments_reconciliation() group by payment_id having count(*) > 1
    ) d;
    if v_n < 1 then
      v_bad := v_bad || ' 🔴 결함이 재현되지 않는다: payment_id 로 묶어도 충돌이 없다(' || coalesce(v_n::text,'NULL') || ') — 이 핀은 픽스처를 재는 중이다';
    end if;

    -- ⓑ THE NEW KEY DOES NOT — and the two subjects' keys are genuinely different values
    select r.row_key into v_k1 from payments_reconciliation() r
      where r.kind = 'settled_without_payment' and r.booking_id = b_e1;
    select r.row_key into v_k7 from payments_reconciliation() r
      where r.kind = 'club_fee_unminted' and r.booking_id = b_c7;
    if v_k1 is null or v_k7 is null then
      v_bad := v_bad || ' NULL-KEY(여덟째=' || coalesce(v_k1,'∅') || ' 일곱째=' || coalesce(v_k7,'∅') || ')';
    elsif v_k1 = v_k7 then
      v_bad := v_bad || ' 서로 다른 팔의 두 예약이 같은 키를 갖는다(' || v_k1 || ')';
    end if;
    select count(*) into v_n from (
      select row_key from payments_reconciliation() group by row_key having count(*) > 1
    ) d;
    if v_n is distinct from 0 then
      v_bad := v_bad || ' row_key 로 묶어도 충돌이 남는다 ' || coalesce(v_n::text,'NULL') || '개'; end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('rgk','0174-K1 결제행 없는 두 팔이 한 키로 뭉치지 않는다 — 일곱째(club_fee_unminted)와 여덟째(settled_without_payment)가 서로 다른 예약에 동시에 떠 있을 때 payment_id 로 묶으면 실제로 충돌하고(결함 재현), row_key 로 묶으면 두 키다');
    else v_msg := v_bad; call _fail('rgk','0174-K1 결제행 없는 두 팔이 한 키로 뭉치지 않는다', v_msg); end if;
  exception when others then
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    v_msg := sqlerrm; call _fail('rgk','0174-K1 결제행 없는 두 팔이 한 키로 뭉치지 않는다', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0174-K2] two rows from the SAME arm, on two bookings, are TWO keys
  ------------------------------------------------------------------------------------------
  -- K1 could in principle be satisfied by a key that merely distinguishes ARMS — the form 0174's
  -- header refuses, because it also destroys the duplicate detection. This pin cannot: both rows
  -- come from arm eight, so an arm-name key gives them ONE key and this goes red.
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    select r.row_key into v_k1 from payments_reconciliation() r
      where r.kind = 'settled_without_payment' and r.booking_id = b_e1;
    select r.row_key into v_k2 from payments_reconciliation() r
      where r.kind = 'settled_without_payment' and r.booking_id = b_e2;
    if v_k1 is null or v_k2 is null then
      v_bad := v_bad || ' NULL-KEY(' || coalesce(v_k1,'∅') || ' / ' || coalesce(v_k2,'∅') || ')';
    elsif v_k1 = v_k2 then
      v_bad := v_bad || ' 같은 팔의 서로 다른 두 예약이 같은 키를 갖는다(' || v_k1 || ') — 팔 이름만 구분하는 키다';
    end if;
    -- the key names its subject: the BOOKING, because no payments row exists to name
    if v_k1 is distinct from 'booking:' || b_e1::text then
      v_bad := v_bad || ' 키가 예약을 가리키지 않는다(' || coalesce(v_k1,'∅') || ')'; end if;
    -- and neither is part of any collision group
    select count(*) into v_n from (
      select row_key from payments_reconciliation() group by row_key having count(*) > 1
    ) d;
    if v_n is distinct from 0 then
      v_bad := v_bad || ' 충돌 그룹 ' || coalesce(v_n::text,'NULL') || '개'; end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('rgk','0174-K2 같은 팔의 두 예약도 두 키다 — 여덟째 팔 행 둘(각기 다른 예약)이 booking:<id> 로 서로 다른 키를 갖는다(팔 이름만 구분하는 키였다면 여기서 붙는다)');
    else v_msg := v_bad; call _fail('rgk','0174-K2 같은 팔의 두 예약도 두 키다', v_msg); end if;
  exception when others then
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    v_msg := sqlerrm; call _fail('rgk','0174-K2 같은 팔의 두 예약도 두 키다', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0174-K3] THE CONTROL — on the payment-bearing arms the key IS the payment_id
  ------------------------------------------------------------------------------------------
  -- This is what makes 0174 a refinement rather than a replacement: `116 C11` and `120 J4` group
  -- by `row_key` from 0174 onward, and on every arm those two pins' own fixtures touch, `row_key`
  -- is `payment_id::text` — so the grouping they assert is byte-identical to the one they
  -- asserted before, and the change is confined to the rows where the old key was NULL.
  -- ⚠ NAMED GAP, honest rather than papered over: the strongest statement of 「not weakened」
  --   would be a fixture where ONE payments row is claimed by TWO arms, proving the key still
  --   collides there. **The harness cannot manufacture it** — the eight arms are mutually
  --   exclusive on `payments.status` (confirmed / pending / failed / waived / canceled), so no
  --   row reachable by INSERT satisfies two of them, and any pin asserting it would be green by
  --   construction (the unfalsifiable-pin law). The property is instead established by the
  --   ALGEBRAIC identity below, which can fail, and measured directly by mutation (iii) in this
  --   file's header, which widens an arm in the function itself and watches C11 and J4 redden.
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    -- a subject, so this pin is not vacuous
    select r.row_key into v_kp from payments_reconciliation() r
      where r.kind = 'stale_pending' and r.payment_id = p_pay;
    if v_kp is distinct from p_pay::text then
      v_bad := v_bad || ' 결제행 있는 행의 키가 결제 id 가 아니다(' || coalesce(v_kp,'∅') || ')'; end if;

    -- and the identity holds across the WHOLE board, not only my fixture
    select count(*) filter (where r.payment_id is not null),
           count(*) filter (where r.payment_id is not null
                              and r.row_key is distinct from r.payment_id::text)
      into v_n, v_n2
    from payments_reconciliation() r;
    if v_n < 1 then
      v_bad := v_bad || ' 🔴 공허: 결제행을 가진 행이 보드에 하나도 없다'; end if;
    if v_n2 is distinct from 0 then
      v_bad := v_bad || ' 결제행 있는 행 중 키≠payment_id 가 ' || coalesce(v_n2::text,'NULL') || '개 (팔 이름이 키에 섞였다 — 한 행을 두 팔이 물어도 안 잡힌다)'; end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('rgk','0174-K3 결제행이 있는 팔에서는 키가 곧 payment_id — 보드 전체에서 payment_id 가 있는 행은 예외 없이 row_key = payment_id::text 이므로 116 C11·120 J4 가 그 모집단에 대해 주장하는 바는 0174 전후로 동일하다(팔 이름을 키에 붙였다면 여기서 깨진다)');
    else v_msg := v_bad; call _fail('rgk','0174-K3 결제행이 있는 팔에서는 키가 곧 payment_id', v_msg); end if;
  exception when others then
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    v_msg := sqlerrm; call _fail('rgk','0174-K3 결제행이 있는 팔에서는 키가 곧 payment_id', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0174-K4] NO row, from any arm, ever has a NULL key
  ------------------------------------------------------------------------------------------
  -- 0174's VERIFY runs this same count at apply time, where the database may legitimately hold
  -- zero reconciliation rows and `0 = 0` is vacuously true. Here it runs against a board proven
  -- non-empty and holding at least one row from each of the two arms that emit no payment_id —
  -- the two that make a NULL key possible at all. The non-emptiness arm is what stops this pin
  -- from being the vacuous version of itself.
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    select count(*), count(*) filter (where r.row_key is null)
      into v_rows, v_n
    from payments_reconciliation() r;
    if v_rows < 4 then
      v_bad := v_bad || ' 🔴 공허: 보드에 행이 ' || coalesce(v_rows::text,'NULL') || '개뿐이다(기대 ≥4)'; end if;
    if v_n is distinct from 0 then
      v_bad := v_bad || ' row_key 가 NULL 인 행 ' || coalesce(v_n::text,'NULL') || '개 / 전체 ' || coalesce(v_rows::text,'NULL'); end if;
    -- both NULL-payment_id arms are actually represented, or this pin is only about the easy rows
    select count(distinct r.kind) into v_n2 from payments_reconciliation() r
      where r.payment_id is null
        and r.kind in ('club_fee_unminted', 'settled_without_payment');
    if v_n2 is distinct from 2 then
      v_bad := v_bad || ' 결제행 없는 팔이 ' || coalesce(v_n2::text,'NULL') || '/2 만 보드에 있다'; end if;
    -- an empty string is not a key either — it would group exactly like NULL used to
    if exists (select 1 from payments_reconciliation() r where r.row_key = '') then
      v_bad := v_bad || ' 빈 문자열 키가 있다(NULL 과 똑같이 뭉친다)'; end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('rgk','0174-K4 어떤 팔의 어떤 행도 키가 비어 있지 않다 — 결제행 없는 두 팔이 모두 올라와 있는 비어 있지 않은 보드에서 row_key NULL 0개, 빈 문자열 0개(0174 의 VERIFY 는 같은 셈을 적용 시점에 하지만 행이 0개면 공허하다 — 이 핀이 그 버전이 아니다)');
    else v_msg := v_bad; call _fail('rgk','0174-K4 어떤 팔의 어떤 행도 키가 비어 있지 않다', v_msg); end if;
  exception when others then
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    v_msg := sqlerrm; call _fail('rgk','0174-K4 어떤 팔의 어떤 행도 키가 비어 있지 않다', v_msg);
  end;

  -- final restore, by VALUE, outside every subtransaction — a pin that failed above rolled its
  -- own restore back with it. This suite runs LAST; leaving the cutover set would be a lie about
  -- the shipped state to anyone reading the database afterwards (120's argument).
  v_cur := v_flags;
  update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                       updated_at = (v_cur->>'updated_at')::timestamptz where id;
end $$;
