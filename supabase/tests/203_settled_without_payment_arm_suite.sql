-- ═══ 203 — 0173's reconciliation arm eight, `settled_without_payment` — 0173-A1…A5, tag `swp` ═══
--
-- THE PROPOSITION THIS FILE OWNS: a settled booking the sweep CANNOT price is visible to ops.
-- `sweep_settled_without_payments()` refuses such a row with nothing but a `raise notice`
-- (`0116:100` missing end_reason · `0116:112` missing actual_km · `0116:125` a mint that raised),
-- and until 0173 `payments_reconciliation()` had no arm that could see a booking with NO payments
-- row at all. Every existing arm starts `from payments p`.
--
-- ⚠ WHAT IS DELIBERATELY *NOT* PINNED HERE, because it is already owned three ways and a fourth
--   copy would be manufactured coverage (202's argument, same shape):
--     · `116 C9`  — the sweep mints exactly one row for a settled booking, idempotently.
--     · `116 C22` — the flag gate: charging off ⇒ 0 minted; flipped ⇒ pre-cutover runs stay free.
--     · `116 C24` — the sweep's two blind spots, each with its positive control.
--     · `151 B1`  — the `settled_at` anchor and the deliberately-wider existence predicate.
--   This suite asserts only what the ARM does, and the arm is a READ. Nothing here mints.
--
-- ─── MUTATION MAP (measured on the full harness, each plant `&&`-chained to its run so an
--     unlanded plant yields NO row rather than a green one) ───────────────────────────────
--   Every plant also DEMOTES 0173's VERIFY `raise exception` to a notice so the suite can speak;
--   un-demoted, plant (i) ABORTS THE APPLY (`0173 VERIFY FAILED: ANCHOR-MISSING(runs.settled_at)
--   WRONG-ANCHOR(bookings.status)`), which measures the VERIFY and not this file (0131-G4's
--   distinction). CONTROL: the demotion WITHOUT a plant ⇒ 1225 / 0, so nothing below is the
--   demotion itself.
--   (i)  arm eight's anchor `rn.settled_at is not null` → `b.status = 'completed'`
--                                                    → RED = [0173-A4] + [0173-A5]
--   (ii) the grace conjunct `rn.settled_at < now() - interval '1 hour'` deleted
--                                                    → RED = [0173-A3] + [0173-A5]
--   A5 is in both sets BY DESIGN — it is a SOURCE pin and both plants are source changes; a
--   different KIND of evidence, not a second copy of the behavioural pin. A1 and A2 stay green
--   under both, which is what makes A3 and A4 two measurements rather than one printed twice.
--
-- 🔴 **A4's FIRST DRAFT COULD NOT SEE PLANT (i), AND THE CAUSE IS A REAL PROPERTY OF THE ARM
--    RATHER THAN A WEAK PIN.** Measured: with the anchor swapped for `b.status = 'completed'` the
--    run returned **1224 / 1 — A5 ALONE**. Both negative fixtures were silent, because the GRACE
--    conjunct reads THE SAME COLUMN as the anchor: `rn.settled_at < now() - interval '1 hour'` is
--    NULL — hence false — on an unsettled run, so it keeps ⓕ out whether or not the anchor is
--    there. **`rn.settled_at is not null` is REDUNDANT given the grace conjunct and is not
--    independently observable through any fixture.** Written down as a named gap rather than
--    papered over; it stays in the arm for readability and because a later slice may legitimately
--    re-key the grace onto another column, at which point it becomes load-bearing again.
--    The repair was NOT to reshape a pin around the mutation. ⓖ states the property on its own
--    terms — `116 C8`'s sentence, *the population is the RUN's settlement, not the booking's
--    display status* — with a fixture in the zone where the two predicates DISAGREE: a settled,
--    unpriceable booking sitting at `incident_review`. A `bookings.status` anchor HIDES it, and
--    hiding is the direction `0116:47-52` documents as the danger.
--   The measured sets are reproduced in the commit message and in the REGISTRY row.
--
-- ─── FIXTURE NOTES THAT ARE LOAD-BEARING ───────────────────────────────────────────────────
--  ① `ops_flags` is armed by WHOLE-ROW SNAPSHOT and restored by whole-row value, including in the
--     exception handler of every pin that touches it. The arm's scope conjunct reads
--     `payments_live_since` through a scalar sub-select, so leaving the flag set would change what
--     every later reader of this database sees — and 151 B1's own header records what happens when
--     fixture state escapes a pin (three reds, two naming the wrong thing).
--  ② `runs` rows are INSERTED directly rather than driven through `end_run_tx`/`confirm_return_tx`.
--     That is correct HERE and would be wrong in 202: this suite is about the QUERY, and the real
--     settle path cannot produce the states the query exists to report — a NULL `actual_km` is
--     precisely the row `settle_run_tx` never writes. `119 R10` owns the real path end-to-end.
--  ③ [A4]'s two NEGATIVE controls are the two anchors `0116:47-52` refuses BY NAME, and each is shaped so
--     that adopting that anchor makes it appear: ⓐ a CANCELLED booking carrying a `ledger_items`
--     row and no run at all (`0080 §K` writes one for a cancelled booking — an arm anchored on
--     ledger presence reports an owner charge missing for a run that never happened); ⓑ a booking
--     sitting at `bookings.status = 'completed'` whose run STOPPED and was never settled (the dog
--     is still on the leash). Neither may appear — plus ⓖ, the POSITIVE arm: a settled,
--     unpriceable booking that has moved on to `incident_review` and MUST still be reported.
--     See the mutation map — ⓖ is the only one of the three a `bookings.status` anchor moves.
set client_min_messages = warning;

do $$
declare
  ow uuid; rn uuid; dg uuid; dg2 uuid; dg3 uuid; dg4 uuid; dg5 uuid; dg6 uuid; dg7 uuid; rt uuid;
  b_km    uuid;      -- settled, actual_km NULL, past the grace      → missing_actual_km
  b_er    uuid;      -- settled, end_reason NULL, past the grace     → missing_end_reason
  b_un    uuid;      -- settled, both columns present, past the grace → unpriced
  b_new   uuid;      -- settled 10 minutes ago                       → inside the grace
  b_cxl   uuid;      -- [A4 ⓐ] cancelled + ledger row, no run
  b_stop  uuid;      -- [A4 ⓑ] bookings.status completed, run never settled
  b_inc   uuid;      -- [A4 ⓒ] SETTLED but the booking moved on to incident_review
  v_flags jsonb; v_cur jsonb;
  v_bad text := ''; v_msg text; v_n int; v_age interval; v_txt text; v_arm text;
  v_secdef boolean; v_pathok boolean;
begin
  -- ---------- shared seed (OUTSIDE every pin — a caught exception rolls a pin's own writes
  -- back, and 151's header records the three-red cascade that follows when a fixture more than
  -- one pin depends on lives inside one) ----------
  ow := t_user('swp_ow', 'owner');
  rn := t_user('swp_rn', 'runner');
  dg  := t_dog(ow, '무측정견'); dg2 := t_dog(ow, '무사유견'); dg3 := t_dog(ow, '미가격견');
  dg4 := t_dog(ow, '취소견');   dg5 := t_dog(ow, '목줄견'); dg6 := t_dog(ow, '갓정산견'); dg7 := t_dog(ow, '사건견');
  rt := t_route('조정 코스');

  -- the whole row, by value — `to_jsonb` so a column added to ops_flags later travels with it
  select to_jsonb(f.*) into v_flags from ops_flags f where f.id;

  -- ⓐ settled 3h ago, priced by nothing: `actual_km` NULL is the row `settle_run_tx` never
  --    writes, which is exactly why the sweep refuses it (0116:112) and exactly why nothing else
  --    can see it.
  b_km := t_av_booking(ow, dg, rt, rn, now() - interval '4 hours', 5.0, 'completed');
  insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
  values (b_km, now() - interval '4 hours', now() - interval '3 hours', now() - interval '3 hours',
          null, 'completed'::end_reason);
  -- ⓑ the other traced refusal (0116:100). Same shape, different missing column.
  b_er := t_av_booking(ow, dg2, rt, rn, now() - interval '4 hours', 5.0, 'completed');
  insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
  values (b_er, now() - interval '4 hours', now() - interval '3 hours', now() - interval '3 hours',
          5.0, null);
  -- ⓒ both columns present and STILL no payments row after an hour of five-minute sweeps. From
  --    SQL this is indistinguishable from a mint that raised — 0116:125 catches with a NOTICE and
  --    leaves no database trace — so the reason says `unpriced`, the observable fact, and does
  --    not assert a cause.
  b_un := t_av_booking(ow, dg3, rt, rn, now() - interval '4 hours', 5.0, 'completed');
  insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
  values (b_un, now() - interval '4 hours', now() - interval '3 hours', now() - interval '3 hours',
          5.0, 'completed'::end_reason);
  -- ⓓ [A3] settled TEN MINUTES ago. Identical to ⓐ in every other respect — same NULL actual_km,
  --    same end_reason, same cutover scope — so the grace is the ONLY difference between a row
  --    that appears and a row that does not.
  b_new := t_av_booking(ow, dg6, rt, rn, now() - interval '30 minutes', 5.0, 'completed');
  insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
  values (b_new, now() - interval '30 minutes', now() - interval '10 minutes',
          now() - interval '10 minutes', null, 'completed'::end_reason);
  -- ⓔ [A4 ⓐ] the `ledger_items` wrong anchor, in the flesh: a CANCELLED booking with a runner
  --    ledger row and NO runs row at all.
  b_cxl := t_av_booking(ow, dg4, rt, rn, now() - interval '5 hours', 5.0, 'cancelled_owner');
  insert into ledger_items (runner_id, booking_id, base, remaining_guarantee)
  values (rn, b_cxl, 0, 4950);
  -- ⓕ [A4 ⓑ] the `bookings.status` wrong anchor: completed on the booking, unsettled on the run.
  b_stop := t_av_booking(ow, dg5, rt, rn, now() - interval '4 hours', 5.0, 'completed');
  insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
  values (b_stop, now() - interval '4 hours', now() - interval '3 hours', null,
          null, 'completed'::end_reason);
  -- ⓖ [A4 ⓒ] THE POSITIVE ARM, and the one that makes the `bookings.status` substitution
  --    OBSERVABLE. ⚠ It exists because the negative arms could not see it: ⓕ is masked by the
  --    grace conjunct, which reads the SAME column as the anchor and is NULL-false on an unsettled
  --    run, so deleting the anchor alone changes nothing there. The property this arm states,
  --    WITHOUT reference to any mutation, is `116 C8`'s own sentence: the arm's population is
  --    defined by the RUN'S SETTLEMENT, not by the booking's display status — a settled booking
  --    legitimately moves on to incident_review / refund_pending, and anchoring on
  --    `bookings.status` would HIDE exactly the crash class this arm exists to surface.
  b_inc := t_av_booking(ow, dg7, rt, rn, now() - interval '4 hours', 5.0, 'incident_review');
  insert into runs (booking_id, started_at, ended_at, settled_at, actual_km, end_reason)
  values (b_inc, now() - interval '4 hours', now() - interval '3 hours', now() - interval '3 hours',
          null, 'completed'::end_reason);

  ------------------------------------------------------------------------------------------
  -- [0173-A1] the arm SEES the booking nothing else could, and names the sweep's own reason
  ------------------------------------------------------------------------------------------
  -- Positive side. Without it the whole file could be satisfied by an arm that returns nothing —
  -- which is what an absent arm returns.
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    select count(*) into v_n from payments_reconciliation()
      where kind = 'settled_without_payment' and booking_id = b_km;
    if v_n is distinct from 1 then
      v_bad := v_bad || ' 측정 없는 정산 런이 조정 질의에 없다(행수=' || coalesce(v_n::text,'NULL') || ')';
    else
      -- the REASON, and the three columns whose emptiness IS the finding
      select r.payment_status, r.age into v_txt, v_age from payments_reconciliation() r
       where r.kind = 'settled_without_payment' and r.booking_id = b_km;
      if v_txt is distinct from 'missing_actual_km' then
        v_bad := v_bad || ' 사유=' || coalesce(v_txt,'∅') || ' (기대 missing_actual_km)';
      end if;
      if v_age is null or v_age < interval '2 hours' or v_age > interval '4 hours' then
        v_bad := v_bad || ' 경과=' || coalesce(v_age::text,'∅') || ' (정산 시각 기준 약 3시간)';
      end if;
      if exists (select 1 from payments_reconciliation() r
                  where r.kind = 'settled_without_payment' and r.booking_id = b_km
                    and (r.payment_id is not null or r.amount is not null)) then
        v_bad := v_bad || ' 🔴 없는 결제행의 id/금액이 채워져 있다 — 아무도 계산하지 않은 숫자';
      end if;
    end if;

    -- the other two reasons, derived from the same columns the sweep reads and in the SWEEP'S
    -- OWN ORDER (end_reason first — 0116:100 runs before 0116:112)
    select r.payment_status into v_txt from payments_reconciliation() r
     where r.kind = 'settled_without_payment' and r.booking_id = b_er;
    if v_txt is distinct from 'missing_end_reason' then
      v_bad := v_bad || ' 사유(end_reason NULL)=' || coalesce(v_txt,'∅'); end if;
    select r.payment_status into v_txt from payments_reconciliation() r
     where r.kind = 'settled_without_payment' and r.booking_id = b_un;
    if v_txt is distinct from 'unpriced' then
      v_bad := v_bad || ' 사유(두 칼럼 다 있음)=' || coalesce(v_txt,'∅') || ' (기대 unpriced — 민트 예외는 DB에 흔적을 남기지 않는다)'; end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('swp','0173-A1 여덟째 팔이 보인다 — 정산은 됐는데(runs.settled_at) 스윕이 가격을 못 매긴 예약이 settled_without_payment 로 뜨고, 사유는 스윕 자신의 거절 순서대로 missing_end_reason·missing_actual_km·unpriced 이며, 결제행이 없으므로 payment_id·amount 는 비어 있다(추측한 숫자가 아니다)');
    else v_msg := v_bad; call _fail('swp','0173-A1 여덟째 팔이 보인다', v_msg); end if;
  exception when others then
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    v_msg := sqlerrm; call _fail('swp','0173-A1 여덟째 팔이 보인다', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0173-A2] THE CONTROL — the arm cannot cry on the healthy case
  ------------------------------------------------------------------------------------------
  -- A1 alone is green under an arm that lists EVERY settled booking. This pin makes the same row
  -- disappear by doing the only thing that resolves the finding — the row exists now — and then
  -- brings it back, so the disappearance is attributable to the payments row rather than to the
  -- arm having gone quiet. The third leg is the sweep's DELIBERATELY WIDER predicate
  -- (`0116:96-106`, pinned by `151 B1 ⓒ′`): kind-less widget debris does NOT count as a payment,
  -- so narrowing this arm's copy of that predicate reddens here.
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    insert into payments (booking_id, order_id, amount, status, raw)
    values (b_km, 'ord_swp_minted', 24900, 'pending',
            jsonb_build_object('kind', 'settle_charge', 'attempts', 0));
    select count(*) into v_n from payments_reconciliation()
      where kind = 'settled_without_payment' and booking_id = b_km;
    if v_n is distinct from 0 then
      v_bad := v_bad || ' 🔴 청구행이 생겼는데도 보드에 남아 있다(행수=' || coalesce(v_n::text,'NULL') || ') — 건강한 행에 우는 팔';
    end if;

    -- kind-less widget debris is NOT an answer to this booking's charge (the wider predicate)
    update payments set raw = jsonb_build_object('attempts', 0) where order_id = 'ord_swp_minted';
    select count(*) into v_n from payments_reconciliation()
      where kind = 'settled_without_payment' and booking_id = b_km;
    if v_n is distinct from 1 then
      v_bad := v_bad || ' kind 없는 위젯 잔해가 팔을 막았다(행수=' || coalesce(v_n::text,'NULL') || ') — 술어가 민트보다 좁아졌다';
    end if;

    -- and back, so the disappearance above was the row and not the arm
    delete from payments where order_id = 'ord_swp_minted';
    select count(*) into v_n from payments_reconciliation()
      where kind = 'settled_without_payment' and booking_id = b_km;
    if v_n is distinct from 1 then
      v_bad := v_bad || ' 결제행을 지웠는데 돌아오지 않는다(행수=' || coalesce(v_n::text,'NULL') || ') — 사라진 이유가 결제행이 아니었다';
    end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('swp','0173-A2 통제 — 자격 있는 payments 행이 생기면 같은 예약이 보드에서 내려가고(건강한 행에 울지 않는다), kind 없는 위젯 잔해는 답이 아니므로 그대로 남으며(0116:96-106 의 더 넓은 술어), 행을 지우면 다시 올라온다');
    else v_msg := v_bad; call _fail('swp','0173-A2 통제 — 자격 있는 결제행이 생기면 내려간다', v_msg); end if;
  exception when others then
    delete from payments where order_id = 'ord_swp_minted';
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    v_msg := sqlerrm; call _fail('swp','0173-A2 통제 — 자격 있는 결제행이 생기면 내려간다', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0173-A3] SCOPE — inside the grace the sweep still owns it, and charging-off is silent
  ------------------------------------------------------------------------------------------
  -- Without the grace this arm lists every settled booking in the seconds after it settles and
  -- becomes the board nobody reads (`0118:1378-1381`'s argument, at twelve failed sweeps instead
  -- of six). `b_new` differs from `b_km` in NOTHING but its `settled_at`.
  -- The second arm is the cutover scope: with `payments_live_since` NULL the sweep does nothing
  -- at all (`0116:72`), so an arm that reported rows in that era would be arraigning the pilot.
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    select count(*) into v_n from payments_reconciliation()
      where kind = 'settled_without_payment' and booking_id = b_new;
    if v_n is distinct from 0 then
      v_bad := v_bad || ' 🔴 10분 전에 정산된 런이 벌써 보드에 있다(행수=' || coalesce(v_n::text,'NULL') || ') — 유예 없음: 스윕이 아직 할 일이다';
    end if;
    -- the same query must still be able to say YES, or the arm above is green because the arm is
    -- dead rather than because the grace holds
    select count(*) into v_n from payments_reconciliation()
      where kind = 'settled_without_payment' and booking_id = b_km;
    if v_n is distinct from 1 then
      v_bad := v_bad || ' NO-SUBJECT(유예 밖 행이 안 보인다 — 이 핀의 대조군이 사라졌다)';
    end if;

    -- charging OFF ⇒ the whole arm is silent, including for the row A1 just saw
    update ops_flags set payments_live_since = null, updated_at = now();
    select count(*) into v_n from payments_reconciliation()
      where kind = 'settled_without_payment';
    if v_n is distinct from 0 then
      v_bad := v_bad || ' 🔴 청구 OFF 시대에 ' || coalesce(v_n::text,'NULL') || '행 — 파일럿 런을 소급 고발한다';
    end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('swp','0173-A3 범위 — 유예(1시간, 0118:1378 의 상수 그대로) 안쪽 정산은 아직 스윕의 몫이라 뜨지 않고(같은 질의가 유예 밖 행에는 여전히 YES 라고 답한다), payments_live_since 가 NULL 인 청구 OFF 시대에는 팔 전체가 0행이다');
    else v_msg := v_bad; call _fail('swp','0173-A3 범위 — 유예와 컷오버', v_msg); end if;
  exception when others then
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    v_msg := sqlerrm; call _fail('swp','0173-A3 범위 — 유예와 컷오버', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0173-A4] THE ANCHOR — the two substitutes `0116:47-52` refuses, each in the flesh
  ------------------------------------------------------------------------------------------
  -- ⓐ `ledger_items` presence: `0080 §K` writes a ledger row for a CANCELLED booking, which is
  --    not a run at all. An arm anchored there reports a missing owner charge for a run that
  --    never happened.
  -- ⓑ `bookings.status`: a booking can be `completed` while its run was never settled — the stop
  --    is not the return (`0083 §6`) — and, in the other direction, a settled booking legitimately
  --    moves on to `incident_review`/`refund_pending` (`116 C8`), which is why anchoring there
  --    HIDES the crash class this arm exists to catch.
  begin
    v_bad := '';
    update ops_flags set payments_live_since = now() - interval '7 days', updated_at = now();

    select count(*) into v_n from payments_reconciliation()
      where kind = 'settled_without_payment' and booking_id = b_cxl;
    if v_n is distinct from 0 then
      v_bad := v_bad || ' 🔴 취소된 예약(원장 행 있음)이 보드에 있다(행수=' || coalesce(v_n::text,'NULL') || ') — 앵커가 ledger_items 로 미끄러졌다';
    end if;
    select count(*) into v_n from payments_reconciliation()
      where kind = 'settled_without_payment' and booking_id = b_stop;
    if v_n is distinct from 0 then
      v_bad := v_bad || ' 🔴 정산 안 된 런(bookings.status=completed)이 보드에 있다(행수=' || coalesce(v_n::text,'NULL') || ') — 앵커가 bookings.status 로 미끄러졌다';
    end if;
    -- ⓒ the POSITIVE arm: settled, past the grace, unpriceable — and the booking has moved on to
    -- incident_review. It MUST still be reported, because the population is the RUN's settlement
    -- and not the booking's display status (116 C8). This is the arm a `bookings.status` anchor
    -- reddens; the two negatives above cannot see that substitution, because the grace conjunct
    -- reads the same column as the anchor and is NULL-false on an unsettled run.
    select count(*) into v_n from payments_reconciliation()
      where kind = 'settled_without_payment' and booking_id = b_inc;
    if v_n is distinct from 1 then
      v_bad := v_bad || ' 🔴 incident_review 로 옮겨간 정산 예약이 보드에서 사라졌다(행수=' || coalesce(v_n::text,'NULL') || ') — 앵커가 bookings.status 로 미끄러졌다(116 C8 이 숨기는 바로 그 부류)';
    end if;

    -- both negative fixtures really are in scope for everything EXCEPT the anchor — otherwise this
    -- pin is green because the rows are invisible for some other reason and it measures nothing
    if not exists (select 1 from ledger_items l where l.booking_id = b_cxl) then
      v_bad := v_bad || ' NO-SUBJECT(취소 예약에 원장 행이 없다)'; end if;
    if not exists (select 1 from runs r where r.booking_id = b_stop and r.ended_at is not null
                     and r.ended_at >= now() - interval '7 days' and r.settled_at is null) then
      v_bad := v_bad || ' NO-SUBJECT(정지-미정산 런이 픽스처에 없다)'; end if;
    if (select b.status from bookings b where b.id = b_stop) is distinct from 'completed' then
      v_bad := v_bad || ' NO-SUBJECT(정지 픽스처가 completed 가 아니다 — bookings.status 대체 앵커를 못 잡는다)'; end if;

    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    if v_bad = ''
      then call _pass('swp','0173-A4 앵커 — runs.settled_at 이지 다른 두 개가 아니다(0116:47-52): 원장 행을 가진 취소 예약도 bookings.status=completed 이지만 반환 봉인이 없는 런도 보드에 오르지 않고(두 픽스처가 앵커 말고는 전부 범위 안이라는 것까지 값으로 확인), 거꾸로 incident_review 로 옮겨간 정산 예약은 여전히 보고된다 — 모집단은 런의 정산이지 예약의 표시 상태가 아니다(116 C8)');
    else v_msg := v_bad; call _fail('swp','0173-A4 앵커 — runs.settled_at 이지 다른 두 개가 아니다', v_msg); end if;
  exception when others then
    v_cur := v_flags;
    update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                         updated_at = (v_cur->>'updated_at')::timestamptz where id;
    v_msg := sqlerrm; call _fail('swp','0173-A4 앵커 — runs.settled_at 이지 다른 두 개가 아니다', v_msg);
  end;

  ------------------------------------------------------------------------------------------
  -- [0173-A5] the DEPLOYED source, comments stripped, with a NO-SOURCE arm
  ------------------------------------------------------------------------------------------
  -- A different KIND of evidence from A1-A4: those four ask what the query DOES on this fixture
  -- chain, this one asks what the shipped function IS. Neither is evidence for the other — the
  -- `check-definer-acl` division. Comments are stripped before matching because `prosrc` is the
  -- body PLUS our own prose and 0173's arm carries an inline comment naming the arm: un-stripped,
  -- a migration that DOCUMENTED the arm and failed to add it would satisfy this pin, and the
  -- better the documentation the more certainly it would pass.
  begin
    v_bad := '';
    select p.prosrc, p.prosecdef,
           coalesce(array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%', false)
      into v_txt, v_secdef, v_pathok
    from pg_proc p where p.oid = 'payments_reconciliation()'::regprocedure;

    if v_txt is null then
      v_bad := v_bad || ' NO-SOURCE(payments_reconciliation) — prosrc 가 NULL 이라 아래 모든 팔이 침묵했을 것이다';
    else
      v_txt := regexp_replace(v_txt, '--[^\n]*', '', 'g');
      if position('settled_without_payment' in v_txt) = 0 then
        v_bad := v_bad || ' ARM-ABSENT(settled_without_payment)';
      else
        -- scoped to the arm: arm six also says `settled_at is not null`, through alias `r`;
        -- only arm eight uses `rn`
        v_arm := substr(v_txt, position('settled_without_payment' in v_txt));
        if (v_arm like '%rn.settled_at is not null%') is not true then
          v_bad := v_bad || ' ANCHOR-MISSING(runs.settled_at)'; end if;
        if (v_arm like '%rn.settled_at < now() - interval ''1 hour''%') is not true then
          v_bad := v_bad || ' GRACE-MISSING(1 hour)'; end if;
        if (v_arm like '%payments_live_since%') is not true then
          v_bad := v_bad || ' CUTOVER-SCOPE-MISSING'; end if;
        if (v_arm like '%b.status = ''completed''%') is true then
          v_bad := v_bad || ' WRONG-ANCHOR(bookings.status)'; end if;
        if (v_arm like '%ledger_items%') is true then
          v_bad := v_bad || ' WRONG-ANCHOR(ledger_items)'; end if;
      end if;
      -- the seven it was built on are still there
      select count(*)::int into v_n from (
        select unnest(array['orphan_capture','stale_pending','stale_dispatched','ladder_exhausted',
                            'incident_waive_pending','refund_shaped_server_charge',
                            'club_fee_unminted']) as a
      ) q where position(q.a in v_txt) > 0;
      if v_n is distinct from 7 then
        v_bad := v_bad || ' BASE-ARMS=' || coalesce(v_n::text,'NULL') || '/7 (전진 재정의가 기존 팔을 떨어뜨렸다)'; end if;
    end if;

    if v_secdef is not true then v_bad := v_bad || ' NOT-SECURITY-DEFINER'; end if;
    if v_pathok is not true then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH'; end if;
    if has_function_privilege('anon', 'payments_reconciliation()', 'execute') is distinct from false
      then v_bad := v_bad || ' anon:실행가능'; end if;
    if has_function_privilege('authenticated', 'payments_reconciliation()', 'execute') is distinct from false
      then v_bad := v_bad || ' authenticated:실행가능'; end if;
    if has_function_privilege('service_role', 'payments_reconciliation()', 'execute') is distinct from true
      then v_bad := v_bad || ' service_role:실행불가'; end if;

    if v_bad = ''
      then call _pass('swp','0173-A5 배포된 소스(주석 제거) — 여덟째 팔이 실제로 runs.settled_at 을 읽고 1시간 유예와 payments_live_since 범위를 지니며 두 잘못된 앵커를 쓰지 않는다, 기존 일곱 팔은 그대로, definer·in-body search_path·ACL(anon/authenticated 불가, service_role 가능)까지 값으로');
    else v_msg := v_bad; call _fail('swp','0173-A5 배포된 소스 핀', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('swp','0173-A5 배포된 소스 핀', v_msg);
  end;

  -- final restore, by VALUE, outside every subtransaction — a pin that failed above rolled its
  -- own restore back with it
  v_cur := v_flags;
  update ops_flags set payments_live_since = (v_cur->>'payments_live_since')::timestamptz,
                       updated_at = (v_cur->>'updated_at')::timestamptz where id;
end $$;
