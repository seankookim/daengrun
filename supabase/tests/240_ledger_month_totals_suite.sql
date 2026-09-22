-- ═══ 240 — 0209: the runner's earnings get a KST shape, and a collected field stops hiding ═════
-- ═══        0209-M1 · M2 · M3 · M4 · M5 · N1 · S1, tag `lmt`                              ═══
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a
-- pin written while staring at a mutation tends to assert what that mutation broke rather than
-- the property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · M1 **THE MONTH BOUNDARY IS KOREA'S, AND NO SESSION TIMEZONE CAN REACH IT.** Three ledger
--        rows one second and nine hours apart straddle two KST month boundaries; each lands in
--        the KST month it belongs to, and the WHOLE READ returns the identical answer under
--        `America/New_York` and under `Asia/Seoul`. The row at the last second of a KST month and
--        the row at the first instant of the next are ONE SECOND apart and must be in DIFFERENT
--        months — a `date_trunc` that consults the session zone collapses them into one, which is
--        exactly the mutation that came back GREEN on 0121's M3 because the harness machine ran
--        KST. ⚠ A UTC-only arm would not be enough either: this suite's disagreeing zone is
--        New_York, per the 2026-08-27 measurement (25 pins red under New_York, ZERO under Seoul).
--   · M2 **ONE LEDGER, ONE ANSWER.** Over a window wide enough to hold every row this runner has,
--        Σ of the month nets **equals `my_ledger_total()`** on the same fixture — including the
--        cancellation-compensation row, which has no `runs` row and is money all the same. This
--        is the pin that makes the transcribed summand a measurement instead of a promise: a
--        drifted summand cannot satisfy an equality against the function it was copied from.
--        The same arm reads the ORDER back (newest month first) from the function's own row
--        order, not from a re-sort.
--   · M3 **`paid_won` IS A FILTER ON THE SAME NET, MEASURED AS A DELTA THIS SUITE CAUSED.** One
--        booking's rows are paid through the REAL door (`ops_record_manual_payout`) and that
--        month's `paid_won` moves 0 → exactly those rows' net, while its `net_won` does not move
--        at all and stays STRICTLY GREATER than `paid_won` (the month holds an unpaid comp row
--        too, so a `paid_won` that were simply a copy of `net_won` is visible here). Controls:
--        the other two months' `paid_won` stay 0 across the same action. ⚠ Before/after, never a
--        state found lying around — 175 `V2`'s law.
--   · M4 **ANOTHER RUNNER'S MONTHS ARE NOT IN MY ANSWER, AND THE GATE IS AN ABSENCE.** The second
--        runner gets their own single month and none of the first runner's three; their month's
--        net equals their OWN lifetime total. Anonymous ⇒ `not_authenticated`. An owner (no
--        ledger rows) gets zero rows and no raise. Controls: both runners pass on their own data
--        in the same block. 🔴 And the gate is asserted over `pg_proc.proargnames` — the function
--        takes NO subject argument, so `auth.uid()` is the only runner it can be asked about. A
--        `p_runner` added later reddens no behavioural arm on a fixture where the caller and the
--        subject are the same person (0203 `E4`'s law), so this arm is the only one that sees it.
--   · M5 **THE WINDOW IS KST MONTHS BACK, AND AN ABSURD ONE IS CLAMPED RATHER THAN OBEYED.**
--        `p_months => 1` returns only the current KST month; `=> 3` reaches two months back and
--        not eight; `=> 24` reaches the eight-month-old row (the control that proves the row
--        exists and that 1/3 excluded it rather than never having it). NULL and a missing
--        argument both behave as 6. Zero and a negative clamp to the SAME ANSWER as 1, and 9999
--        to the same answer as 24 — compared as whole result sets, so a clamp that merely
--        happened not to crash is not enough.
--   · N1 **`dogs.neutered` REACHES THE RUNNER'S CARD, ALL THREE VALUES, AND NOTHING ELSE MOVED.**
--        Both request views expose the column and each carries the dog's ACTUAL value — true,
--        false, and NULL for a dog whose owner never answered — so a constant satisfies none of
--        the three. `anon` still cannot read either view, `authenticated` still can (the control
--        that the grant was not simply deleted), and 0121 §D's fare seal is still shut.
--   · S1 Deployed shape: definer, in-body `search_path`, ACL by effective privilege in BOTH
--        directions with the NULL-ACL arm first, no margin column and no subject argument among
--        `proargnames`, and — on the COMMENT-STRIPPED source — the KST anchoring of both
--        `date_trunc` calls, the `l.runner_id = auth.uid()` row scope and the anonymous refusal,
--        with the crude control that the RAW source really does contain the comments the
--        stripper is supposed to remove. NO-FUNCTION / NO-SOURCE fail loudly rather than passing
--        on an absence.
--
-- ─── FIXTURE NOTES ───
--  ① This suite builds its OWN world (two runners, their own owners, dogs, routes, and an ops
--     operator) and every assertion is scoped to ids it created. It borrows only the shared
--     `10_settle` helpers. A pin that inherits another suite's setup is testing that setup.
--  ② **Every instant is computed RELATIVE TO `now()`**, never written as a literal date. A suite
--     whose fixture is 「June 2026」 stops measuring the window the moment the calendar passes it,
--     and it stops SILENTLY — the rows simply fall outside `p_months` and every arm reads as a
--     correct exclusion. Relative instants keep the same three boundaries true forever.
--  ③ **Ledger rows are BACKDATED by UPDATE, and that is the one thing here production cannot
--     do.** `ledger_items.created_at` defaults to `now()`, so no shipped writer can produce a row
--     dated last month. Everything else about those rows — amounts, runner attribution, the
--     `runs` row, the booking — is what the REAL settle path wrote (`t_settle`), and the payout
--     in M3 goes through the REAL ops door. The column under test is precisely the one being set,
--     which is the narrowest possible exception and is stated rather than hidden.
--  ④ The cancellation-compensation row is written by `record_late_cancel_share` (0085), the real
--     door, on a `cancelled_owner` booking with no `runs` row — so M2's Σ and the run-count
--     asymmetry are measured on the shape production actually produces, not on a hand-built one.
--  ⑤ `request.jwt.claim.sub` is SESSION-scoped here (`set_config(..., false)`, 230's idiom) and
--     is cleared explicitly before the no-caller arm — a leftover claim would make
--     `not_authenticated` unreachable and that arm would pass for the wrong reason.
--
-- ─── MUTATION MAP — measured against these exact files, not predicted ───
-- In the REGISTRY row. Lab: a copy of `supabase/` OUTSIDE the worktree, every plant
-- assert-verified and CHAIN-GATED to its harness run (`plant && harness`), control observed
-- clean FIRST.
set client_min_messages = warning;

-- ---------- suite-local fixtures ----------
-- a runner and everything one needs, through the real doors
create or replace function t_lmt_world(p_tag text,
                                       out o uuid, out r uuid, out d uuid, out rt uuid)
language plpgsql as $$
begin
  o  := t_user('lmt_' || p_tag || '_o', 'owner');
  r  := t_user('lmt_' || p_tag || '_r', 'runner');
  d  := t_dog(o, 'lmt-' || p_tag);
  rt := t_route('lmt 코스 ' || p_tag);
end $$;

-- one settled booking through the real settle path, then its ledger rows moved to `p_at`
-- (fixture note ③ — the ONLY thing here production cannot do, and it is the column under test).
create or replace function t_lmt_settled_at(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                            p_at timestamptz) returns uuid
language plpgsql as $$
declare v uuid;
begin
  v := t_active_booking(p_owner, p_runner, p_dog, p_route, now() - interval '2 days');
  perform t_settle(v, 'dog_condition');
  update ledger_items set created_at = p_at where booking_id = v;
  return v;
end $$;

-- a cancellation-compensation row: a `cancelled_owner` booking with NO `runs` row, paid by the
-- real 0085 door. 3km at 7,900 + 9,000 = 16,900; 0066's <24h tier is 10% = 1,690; the runner's
-- half is 845 — 121's own literal chain, and this suite never recomputes it.
create or replace function t_lmt_comp_at(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                         p_at timestamptz) returns uuid
language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare, cancel_fee, cancel_reason)
  values (p_owner, p_dog, p_runner, p_route, 'cancelled_owner', now() + interval '3 hours', 3.0,
          7900, 9000, 0, 16900, 7900, 1690, 'owner_cancel_late')
  returning id into v;
  perform record_late_cancel_share(v);
  update ledger_items set created_at = p_at where booking_id = v;
  return v;
end $$;

-- a booking the OPEN request view will show (unassigned, matching) …
create or replace function t_lmt_open_bk(p_owner uuid, p_dog uuid, p_route uuid) returns uuid
language sql as $$
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, null, p_route, 'matching', now() + interval '2 days', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id
$$;

-- … and one the DIRECTED view will show (named runner, awaiting their answer)
create or replace function t_lmt_directed_bk(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid)
returns uuid language sql as $$
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'runner_pending', now() + interval '2 days', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id
$$;

-- Call the door as p_uid, optionally inside a named session timezone, and report EITHER the rows
-- OR the raise word — never both, and never a swallowed success. The rows are aggregated WITHOUT
-- an `order by`, so the array preserves the FUNCTION's own ordering and M2 can read it back.
-- ⚠ `p_months_given = false` calls the function with NO ARGUMENT, which is the only way to
--   measure the declared default rather than a value this file supplies.
create or replace function t_lmt_read_as(p_uid uuid, p_months int, p_tz text default null,
                                         p_months_given boolean default true) returns jsonb
language plpgsql as $$
declare v jsonb; v_old text;
begin
  v_old := current_setting('timezone');
  if p_tz is not null then perform set_config('timezone', p_tz, true); end if;
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  begin
    if p_months_given then
      select coalesce(jsonb_agg(jsonb_build_object(
               'month', x.month_start::text, 'net', x.net_won,
               'runs', x.run_count, 'paid', x.paid_won)), '[]'::jsonb)
        into v from my_ledger_month_totals(p_months) x;
    else
      select coalesce(jsonb_agg(jsonb_build_object(
               'month', x.month_start::text, 'net', x.net_won,
               'runs', x.run_count, 'paid', x.paid_won)), '[]'::jsonb)
        into v from my_ledger_month_totals() x;
    end if;
    perform set_config('timezone', v_old, true);
    return jsonb_build_object('rows', v, 'n', jsonb_array_length(v));
  exception when others then
    perform set_config('timezone', v_old, true);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- one month of a read, by KST month start — NULL when the month is absent from the answer, which
-- every caller below distinguishes from a month whose numbers happen to be zero.
create or replace function t_lmt_row(p_js jsonb, p_month date) returns jsonb
language sql immutable as $$
  select e from jsonb_array_elements(coalesce(p_js->'rows', '[]'::jsonb)) e
   where e->>'month' = p_month::text
   limit 1
$$;

-- the runner's own lifetime total, read through the shipped function as that runner
create or replace function t_lmt_lifetime(p_uid uuid) returns bigint
language plpgsql as $$
declare v bigint;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, false);
  v := my_ledger_total();
  perform set_config('request.jwt.claim.sub', '', false);
  return v;
end $$;

-- the net of a booking's ledger rows — read off the rows, never a literal
create or replace function t_lmt_bk_net(p_booking uuid) returns bigint
language sql as $$
  select coalesce(sum(base + distance_pay + addon_pay + tip
                        + coalesce(remaining_guarantee, 0) - platform_fee), 0)::bigint
    from ledger_items where booking_id = p_booking
$$;

-- pay a booking's unpaid rows through the REAL ops door, as an ops caller
create or replace function t_lmt_pay(p_ops uuid, p_runner uuid, p_booking uuid) returns uuid
language plpgsql as $$
declare v uuid; v_ids uuid[];
begin
  select coalesce(array_agg(id order by id), '{}'::uuid[]) into v_ids
    from ledger_items where booking_id = p_booking and paid_payout_id is null;
  perform set_config('request.jwt.claim.sub', p_ops::text, false);
  v := ops_record_manual_payout(p_runner, v_ids, t_lmt_bk_net(p_booking)::int, 'lmt 월별 지급');
  perform set_config('request.jwt.claim.sub', '', false);
  return v;
end $$;

-- the request-view rows a runner can see for one booking, as JSON (so an absent COLUMN and an
-- absent ROW are distinguishable, and a value can be compared without naming a type)
create or replace function t_lmt_view_row(p_uid uuid, p_view text, p_booking uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, false);
  execute format('select to_jsonb(v) from %I v where v.id = %L', p_view, p_booking) into v;
  perform set_config('request.jwt.claim.sub', '', false);
  return v;
end $$;

do $$
declare
  oA uuid; rA uuid; dA uuid; rtA uuid;   -- the runner this suite is about
  oB uuid; rB uuid; dB uuid; rtB uuid;   -- a SECOND runner — the stranger, with real rows
  ops uuid;
  d_yes uuid; d_no uuid; d_unknown uuid; -- three dogs for N1, three values of `neutered`
  bk_open uuid; bk_directed uuid;
  bk_a uuid; bk_b uuid; bk_c uuid; bk_d uuid; bk_e uuid;
  -- KST calendar anchors, all RELATIVE to now() (fixture note ②)
  v_kst  timestamp;
  m0 date; mM1 date; mM2 date; mM8 date;
  i_a timestamptz; i_b timestamptz; i_c timestamptz; i_d timestamptz; i_e timestamptz;
  v_js jsonb; v_js2 jsonb; v_row jsonb; v_row2 jsonb;
  v_sum bigint; v_life bigint; v_before bigint; v_after bigint;
  v_paid_bk bigint;
  v_bad text := ''; v_msg text; v_src text; v_raw text; v_oid oid; v_n int;
begin
  perform set_config('request.jwt.claim.sub', '', false);
  ops := t_user('lmt_ops', 'owner');
  insert into ops_recipients (profile_id, event_class, active)
  values (ops, 'payout_due', true) on conflict (profile_id, event_class) do nothing;

  select w.o, w.r, w.d, w.rt into oA, rA, dA, rtA from t_lmt_world('a') w;
  select w.o, w.r, w.d, w.rt into oB, rB, dB, rtB from t_lmt_world('b') w;

  -- ── the KST calendar, computed once ─────────────────────────────────────────────────────
  v_kst := now() at time zone 'Asia/Seoul';
  m0  := date_trunc('month', v_kst)::date;
  mM1 := (date_trunc('month', v_kst) - interval '1 month')::date;
  mM2 := (date_trunc('month', v_kst) - interval '2 months')::date;
  mM8 := (date_trunc('month', v_kst) - interval '8 months')::date;
  -- ⓐ the LAST SECOND of KST month M-2 …
  i_a := (date_trunc('month', v_kst) - interval '1 month') at time zone 'Asia/Seoul'
           - interval '1 second';
  -- ⓑ … and the FIRST INSTANT of KST month M-1. One second apart, two different months — and
  --    the SAME UTC month, because KST midnight on the 1st is 15:00 UTC on the last day before.
  i_b := (date_trunc('month', v_kst) - interval '1 month') at time zone 'Asia/Seoul';
  -- ⓒ 23:59 UTC on the last KST calendar day of month M-1 = 08:59 KST on the 1st of month M0.
  --    The brief's own sentence, and the one a UTC bucket gets backwards by a whole month.
  i_c := ((m0 - 1) + time '23:59') at time zone 'UTC';
  -- ⓓ well inside month M-8 — the row `p_months => 3` must not reach and `=> 24` must
  i_d := (date_trunc('month', v_kst) - interval '8 months' + interval '10 days 05:00')
           at time zone 'Asia/Seoul';
  -- ⓔ inside month M-1, the cancellation-compensation row (money, but not a run)
  i_e := (date_trunc('month', v_kst) - interval '1 month' + interval '5 days 12:00')
           at time zone 'Asia/Seoul';

  bk_a := t_lmt_settled_at(oA, rA, dA, rtA, i_a);
  bk_b := t_lmt_settled_at(oA, rA, dA, rtA, i_b);
  bk_c := t_lmt_settled_at(oA, rA, dA, rtA, i_c);
  bk_d := t_lmt_settled_at(oA, rA, dA, rtA, i_d);
  bk_e := t_lmt_comp_at(oA, rA, dA, rtA, i_e);
  -- runner B earns in the CURRENT month only
  perform t_lmt_settled_at(oB, rB, dB, rtB, now());

  -- three dogs, three values of `neutered` — the third is a dog whose owner never answered
  d_yes     := t_dog(oA, 'lmt-중성화-예');
  d_no      := t_dog(oA, 'lmt-중성화-아니오');
  d_unknown := t_dog(oA, 'lmt-중성화-무응답');
  update dogs set neutered = true  where id = d_yes;
  update dogs set neutered = false where id = d_no;
  bk_open     := t_lmt_open_bk(oA, d_yes, rtA);
  bk_directed := t_lmt_directed_bk(oA, d_no, rtA, rA);

  -- ① fixture honesty: the world this file asserts about is the world it thinks it built
  v_bad := '';
  if (select count(*) from ledger_items where booking_id = bk_a) is distinct from 1
    then v_bad := v_bad || ' bk_a의 원장 행이 1개가 아니다'; end if;
  if (select count(*) from ledger_items where booking_id = bk_e) is distinct from 1
    then v_bad := v_bad || ' 취소 보상 행이 쓰이지 않았다'; end if;
  if (select count(*) from runs where booking_id = bk_e) is distinct from 0
    then v_bad := v_bad || ' 취소 보상 예약에 runs 행이 있다 (보상 행이 아니다)'; end if;
  if (select created_at from ledger_items where booking_id = bk_b limit 1) is distinct from i_b
    then v_bad := v_bad || ' bk_b의 created_at이 심어지지 않았다'; end if;
  if (select created_at from ledger_items where booking_id = bk_a limit 1) is distinct from i_a
    then v_bad := v_bad || ' bk_a의 created_at이 심어지지 않았다'; end if;
  -- the two boundary instants must be ONE SECOND apart, or M1 is measuring nothing
  if (i_b - i_a) is distinct from interval '1 second'
    then v_bad := v_bad || ' 경계 두 시각이 1초 차이가 아니다'; end if;
  -- …and they must sit in the SAME month once read through a non-KST clock, or the mutation M1
  -- exists to catch could not even be constructed on this fixture
  if date_trunc('month', i_a at time zone 'UTC')
       is distinct from date_trunc('month', i_b at time zone 'UTC')
    then v_bad := v_bad || ' 대조 실패: UTC로 읽으면 두 경계 행이 이미 다른 달이다 (M1이 무의미)'; end if;
  if (select neutered from dogs where id = d_unknown) is not null
    then v_bad := v_bad || ' 무응답 강아지의 neutered가 NULL이 아니다'; end if;
  if v_bad <> '' then v_msg := v_bad; call _fail('lmt','fixture', v_msg); v_bad := ''; end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0209-M1] the month boundary is Korea's, under a clock that disagrees
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- the disagreeing zone FIRST — a green here is the one that means something
    v_js  := t_lmt_read_as(rA, 12, 'America/New_York');
    v_js2 := t_lmt_read_as(rA, 12, 'Asia/Seoul');
    if v_js->>'raised' is not null then v_bad := v_bad || ' New_York 읽기가 거절됨: ' || (v_js->>'raised');
    elsif v_js2->>'raised' is not null then v_bad := v_bad || ' Seoul 읽기가 거절됨: ' || (v_js2->>'raised');
    else
      -- ⓐ the last second of M-2 is in M-2 …
      v_row := t_lmt_row(v_js, mM2);
      if v_row is null then v_bad := v_bad || ' 🔴 M-2의 마지막 1초 행이 M-2 달에 없다';
      elsif (v_row->>'net')::bigint <> t_lmt_bk_net(bk_a)
        then v_bad := v_bad || ' M-2 net=' || (v_row->>'net') || ' (기대 ' || t_lmt_bk_net(bk_a) || ')'; end if;
      -- ⓑ … and the first instant of M-1 is in M-1. One second later, one month later.
      v_row2 := t_lmt_row(v_js, mM1);
      if v_row2 is null then v_bad := v_bad || ' 🔴 M-1의 첫 순간 행이 M-1 달에 없다';
      elsif (v_row2->>'net')::bigint <> t_lmt_bk_net(bk_b) + t_lmt_bk_net(bk_e)
        then v_bad := v_bad || ' M-1 net=' || (v_row2->>'net')
                   || ' (기대 ' || (t_lmt_bk_net(bk_b) + t_lmt_bk_net(bk_e)) || ')'; end if;
      -- the PAIR is what a session-zone date_trunc cannot satisfy: it puts both in one month
      if v_row is not null and v_row2 is not null
         and (v_row->>'month') is not distinct from (v_row2->>'month')
        then v_bad := v_bad || ' 🔴 1초 차이의 두 행이 같은 달에 들어갔다 (세션 타임존이 경계를 골랐다)'; end if;
      -- ⓒ 23:59 UTC on the last KST day of M-1 is 08:59 KST on the 1st of M0 — the NEXT month
      v_row := t_lmt_row(v_js, m0);
      if v_row is null then v_bad := v_bad || ' 🔴 UTC 23:59 행이 다음 KST 달에 없다';
      elsif (v_row->>'net')::bigint <> t_lmt_bk_net(bk_c)
        then v_bad := v_bad || ' M0 net=' || (v_row->>'net') || ' (기대 ' || t_lmt_bk_net(bk_c) || ')'; end if;
      if t_lmt_row(v_js, mM1) is not null
         and (t_lmt_row(v_js, mM1)->>'net')::bigint = t_lmt_bk_net(bk_b) + t_lmt_bk_net(bk_e)
                                                      + t_lmt_bk_net(bk_c)
        then v_bad := v_bad || ' 🔴 UTC 23:59 행이 전 달로 묶였다'; end if;
      -- 🔴 and the whole answer must be the SAME under both clocks, element for element
      if (v_js->'rows') is distinct from (v_js2->'rows')
        then v_bad := v_bad || ' 🔴 New_York과 Seoul 세션의 답이 다르다 — 세션 타임존이 답을 고른다'; end if;
      -- run counts: the comp row is money in M-1 and NOT a run there
      v_row := t_lmt_row(v_js, mM1);
      if v_row is not null and (v_row->>'runs')::int is distinct from 1
        then v_bad := v_bad || ' M-1 러닝 횟수=' || (v_row->>'runs') || ' (기대 1 — 보상 행은 세지 않는다)'; end if;
    end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then call _pass('lmt','0209-M1 달 경계는 KST다 — 1초 차이인 두 행(어떤 KST 달의 마지막 1초 · 다음 KST 달의 첫 순간)이 **서로 다른 달**에 들어가고, UTC 23:59에 쓰인 행은 +9시간 뒤인 **다음 KST 달**로 묶인다; 같은 읽기를 America/New_York 세션과 Asia/Seoul 세션에서 돌려 답이 원소 하나까지 동일하다(세션 타임존이 date_trunc의 답을 고르면 두 경계 행이 한 달로 무너지고, 그게 0121 M3가 KST 기계 위에서 초록을 냈던 바로 그 변이다); 같은 달의 취소 보상 행은 돈에는 들어가고 러닝 횟수에는 안 들어간다');
    else v_msg := v_bad; call _fail('lmt','0209-M1 KST 달 경계', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('lmt','0209-M1 KST 달 경계', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0209-M2] one ledger, one answer — Σ(월별 net) = my_ledger_total()
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v_js := t_lmt_read_as(rA, 24);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 읽기가 거절됨: ' || (v_js->>'raised');
    else
      select coalesce(sum((e->>'net')::bigint), 0) into v_sum
        from jsonb_array_elements(v_js->'rows') e;
      v_life := t_lmt_lifetime(rA);
      if v_sum is distinct from v_life
        then v_bad := v_bad || ' 🔴 Σ월별=' || v_sum || ' ≠ my_ledger_total=' || v_life; end if;
      -- the equality is only interesting if BOTH sides are non-zero and the comp row is inside it
      if v_life <= 0 then v_bad := v_bad || ' 대조 실패: 평생 누계가 0이다 (등식이 공허하다)'; end if;
      if v_life <= t_lmt_bk_net(bk_e)
        then v_bad := v_bad || ' 대조 실패: 평생 누계가 보상 행 하나보다 크지 않다'; end if;
      -- four distinct KST months, one row each — a GROUP BY that lost its grouping is visible
      if (v_js->>'n')::int is distinct from 4
        then v_bad := v_bad || ' 달 행 수=' || (v_js->>'n') || ' (기대 4)'; end if;
      select count(distinct e->>'month') into v_n from jsonb_array_elements(v_js->'rows') e;
      if v_n is distinct from 4 then v_bad := v_bad || ' 서로 다른 달이 ' || v_n || '개뿐이다'; end if;
      -- …and the FUNCTION's own order is newest month first (read back, never re-sorted)
      for v_n in 0 .. (v_js->>'n')::int - 2 loop
        if ((v_js->'rows'->v_n->>'month')::date <= (v_js->'rows'->(v_n + 1)->>'month')::date)
          then v_bad := v_bad || ' 🔴 정렬이 최신 달 우선이 아니다 (' || v_n || ')'; end if;
      end loop;
    end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then call _pass('lmt','0209-M2 한 원장에 답은 하나 — 모든 행을 담는 창에서 **월별 net의 합이 my_ledger_total()과 같다**(같은 픽스처에서, runs 행이 없는 취소 보상 행까지 포함해서). 합산식을 옮겨 적은 것이 아니라 옮겨 적은 결과가 원본과 같음을 재는 팔이고, 누계가 0이 아니며 보상 행 하나보다 크다는 대조가 등식이 공허하지 않음을 고정한다; 네 개의 서로 다른 KST 달이 각각 한 행이고, **함수 자신의 행 순서**가 최신 달 우선이다(다시 정렬하지 않고 읽는다)');
    else v_msg := v_bad; call _fail('lmt','0209-M2 합계 정합', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('lmt','0209-M2 합계 정합', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0209-M4] another runner's months are not in my answer, and the gate is an ABSENCE
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- (run BEFORE M3 so the payment M3 performs cannot be what makes the two runners differ)
  begin
    v_bad := '';
    v_js := t_lmt_read_as(rB, 24);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 상대 러너 읽기가 거절됨: ' || (v_js->>'raised');
    else
      if (v_js->>'n')::int is distinct from 1
        then v_bad := v_bad || ' 상대 러너의 달 수=' || (v_js->>'n') || ' (기대 1)'; end if;
      if t_lmt_row(v_js, mM2) is not null then v_bad := v_bad || ' 🔴 남의 M-2 달이 실렸다'; end if;
      if t_lmt_row(v_js, mM8) is not null then v_bad := v_bad || ' 🔴 남의 M-8 달이 실렸다'; end if;
      v_row := t_lmt_row(v_js, m0);
      if v_row is null then v_bad := v_bad || ' 대조 실패: 상대 러너가 자기 달도 못 읽는다';
      else
        -- their month equals THEIR OWN lifetime total — a leak of my rows into their month
        -- shows up as an inequality here even if the month count happens to be right
        if (v_row->>'net')::bigint is distinct from t_lmt_lifetime(rB)
          then v_bad := v_bad || ' 🔴 상대 러너의 달 net=' || (v_row->>'net')
                     || ' ≠ 그들의 평생 누계 ' || t_lmt_lifetime(rB); end if;
        -- …and it is NOT my number (the two worlds must be distinguishable at all)
        if (v_row->>'net')::bigint is not distinct from t_lmt_lifetime(rA)
          then v_bad := v_bad || ' 대조 실패: 두 러너의 숫자가 같아 구별할 수 없다'; end if;
      end if;
    end if;
    -- an owner has no ledger rows: zero rows, and NOT a raise
    v_js := t_lmt_read_as(oA, 24);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 보호자 호출이 예외를 일으켰다: ' || (v_js->>'raised');
    elsif (v_js->>'n')::int is distinct from 0 then v_bad := v_bad || ' 보호자 행 수=' || (v_js->>'n'); end if;
    -- no caller at all
    v_js := t_lmt_read_as(null, 24);
    if (v_js->>'raised') is distinct from 'not_authenticated'
      then v_bad := v_bad || ' 무기명 답=' || coalesce(v_js->>'raised', 'n=' || (v_js->>'n')); end if;
    -- CONTROL, same block: the owner of the rows still reads all four months
    v_js := t_lmt_read_as(rA, 24);
    if (v_js->>'n')::int is distinct from 4
      then v_bad := v_bad || ' 대조 실패: 주인이 자기 달들을 못 읽는다 '
                 || coalesce(v_js->>'raised', 'n=' || (v_js->>'n')); end if;
    -- 🔴 THE GATE IS AN ABSENCE. Without this arm, adding a `p_runner` reddens nothing on a
    --    fixture where the caller IS the subject (0203 E4).
    select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'my_ledger_month_totals';
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(my_ledger_month_totals)';
    else
      if (select count(*) from unnest((select proargnames from pg_proc where oid = v_oid)) nm
           where nm in ('p_runner','p_uid','p_profile','p_runner_profile_id','p_subject'))
           is distinct from 0
        then v_bad := v_bad || ' 🔴 함수가 대상 러너를 인자로 받는다 — 게이트가 부재가 아니게 됐다'; end if;
      -- the control for the arm above: `p_months` IS in proargnames, so a NULL/empty proargnames
      -- (which would make the count 0 for free) cannot be what makes it pass
      if (select count(*) from unnest((select proargnames from pg_proc where oid = v_oid)) nm
           where nm = 'p_months') is distinct from 1
        then v_bad := v_bad || ' 대조 실패: proargnames에 p_months가 없다 (위 팔이 공짜로 통과한다)'; end if;
    end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then call _pass('lmt','0209-M4 파티 게이트 — 상대 러너는 **자기 달 하나**만 받고 그 달의 net이 그들 자신의 평생 누계와 정확히 같다(내 행이 한 줄이라도 섞이면 달 수가 맞아도 이 등식이 깨진다), 내 M-2·M-8 달은 그들의 답에 없다; 원장이 없는 보호자는 0행이고 예외가 아니다; 무기명은 not_authenticated; 대조 — 주인은 같은 블록에서 네 달을 그대로 읽는다. 🔴 그리고 게이트는 **조건절이 아니라 부재**다: proargnames에 대상 러너 인자가 없고(p_months는 있다는 대조 포함), 이 팔이 없으면 나중에 p_runner가 생겨도 행동 팔은 하나도 안 빨개진다');
    else v_msg := v_bad; call _fail('lmt','0209-M4 파티 게이트', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('lmt','0209-M4 파티 게이트', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0209-M5] the window is KST months back, and an absurd one is clamped
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- p_months => 1 : the current KST month alone
    v_js := t_lmt_read_as(rA, 1);
    if v_js->>'raised' is not null then v_bad := v_bad || ' (1) 거절됨: ' || (v_js->>'raised');
    else
      if (v_js->>'n')::int is distinct from 1 then v_bad := v_bad || ' (1) 달 수=' || (v_js->>'n'); end if;
      if t_lmt_row(v_js, m0)  is null     then v_bad := v_bad || ' (1) 이번 달이 없다'; end if;
      if t_lmt_row(v_js, mM1) is not null then v_bad := v_bad || ' (1) 지난달이 창 안에 들어왔다'; end if;
    end if;
    -- p_months => 3 : reaches M-2 and NOT M-8
    v_js2 := t_lmt_read_as(rA, 3);
    if v_js2->>'raised' is not null then v_bad := v_bad || ' (3) 거절됨: ' || (v_js2->>'raised');
    else
      if (v_js2->>'n')::int is distinct from 3 then v_bad := v_bad || ' (3) 달 수=' || (v_js2->>'n'); end if;
      if t_lmt_row(v_js2, mM2) is null     then v_bad := v_bad || ' (3) M-2가 없다'; end if;
      if t_lmt_row(v_js2, mM8) is not null then v_bad := v_bad || ' 🔴 (3) M-8이 3개월 창에 들어왔다'; end if;
    end if;
    -- CONTROL: the M-8 row EXISTS — so (1) and (3) excluded it rather than never having it
    v_js := t_lmt_read_as(rA, 24);
    if t_lmt_row(v_js, mM8) is null
      then v_bad := v_bad || ' 대조 실패: 24개월 창에서도 M-8이 없다 (앞의 배제가 무의미)'; end if;
    -- the DEFAULT, measured two ways: an explicit NULL and NO ARGUMENT AT ALL
    v_js  := t_lmt_read_as(rA, 6);
    v_js2 := t_lmt_read_as(rA, null);
    if (v_js->'rows') is distinct from (v_js2->'rows')
      then v_bad := v_bad || ' NULL p_months가 6과 다른 답을 냈다'; end if;
    v_js2 := t_lmt_read_as(rA, null, null, false);   -- my_ledger_month_totals() — no argument
    if (v_js->'rows') is distinct from (v_js2->'rows')
      then v_bad := v_bad || ' 🔴 선언된 기본값이 6이 아니다 (인자 없는 호출이 다른 답을 냈다)'; end if;
    -- the CLAMPS, compared as whole result sets
    v_js := t_lmt_read_as(rA, 1);
    if (t_lmt_read_as(rA, 0)->'rows')  is distinct from (v_js->'rows')
      then v_bad := v_bad || ' p_months=0이 1로 조여지지 않았다'; end if;
    if (t_lmt_read_as(rA, -5)->'rows') is distinct from (v_js->'rows')
      then v_bad := v_bad || ' 음수 p_months가 1로 조여지지 않았다'; end if;
    v_js := t_lmt_read_as(rA, 24);
    if (t_lmt_read_as(rA, 9999)->'rows') is distinct from (v_js->'rows')
      then v_bad := v_bad || ' 큰 p_months가 24로 조여지지 않았다'; end if;
    -- …and the two clamp targets are DIFFERENT answers, or both comparisons above are vacuous
    if (t_lmt_read_as(rA, 1)->'rows') is not distinct from (t_lmt_read_as(rA, 24)->'rows')
      then v_bad := v_bad || ' 대조 실패: 1개월 창과 24개월 창의 답이 같다 (조임 비교가 공허하다)'; end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then call _pass('lmt','0209-M5 창은 **KST 달 수**다 — 1이면 이번 달만, 3이면 M-2까지 닿고 M-8에는 못 닿으며, 24면 M-8이 나온다(그 행이 실재한다는 대조라 앞의 배제가 「없던 행」이 아니다); 기본값은 두 가지로 잰다 — NULL을 준 호출과 **인자 없는 호출**이 둘 다 6과 같은 답이다; 0·음수는 1과, 9999는 24와 **결과 집합 전체가** 같고, 1과 24의 답이 서로 다르다는 대조가 그 비교들이 공허하지 않음을 고정한다');
    else v_msg := v_bad; call _fail('lmt','0209-M5 창·기본값·조임', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('lmt','0209-M5 창·기본값·조임', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0209-N1] `dogs.neutered` reaches the runner's card — all three values
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v_row := t_lmt_view_row(rA, 'runner_open_requests', bk_open);
    if v_row is null then v_bad := v_bad || ' 오픈 요청 뷰에 그 예약이 없다';
    else
      if not (v_row ? 'neutered') then v_bad := v_bad || ' 🔴 오픈 요청 뷰에 neutered 칸이 없다';
      elsif (v_row->>'neutered') is distinct from 'true'
        then v_bad := v_bad || ' 오픈 요청 neutered=' || coalesce(v_row->>'neutered','(null)') || ' (기대 true)'; end if;
      -- nothing else moved: 0121 §D's fare seal is still shut on the row the runner reads
      if v_row ?| array['base_fare','distance_fare','addon_fare','total_price','min_fare','commission_rate']
        then v_bad := v_bad || ' 🔴 요금 칸이 요청 뷰로 돌아왔다 (0121 §D)'; end if;
    end if;
    v_row := t_lmt_view_row(rA, 'my_directed_requests', bk_directed);
    if v_row is null then v_bad := v_bad || ' 지명 요청 뷰에 그 예약이 없다';
    else
      if not (v_row ? 'neutered') then v_bad := v_bad || ' 🔴 지명 요청 뷰에 neutered 칸이 없다';
      elsif (v_row->>'neutered') is distinct from 'false'
        then v_bad := v_bad || ' 지명 요청 neutered=' || coalesce(v_row->>'neutered','(null)') || ' (기대 false)'; end if;
      if v_row ?| array['base_fare','distance_fare','addon_fare','total_price','min_fare','commission_rate']
        then v_bad := v_bad || ' 🔴 요금 칸이 지명 뷰로 돌아왔다 (0121 §D)'; end if;
    end if;
    -- the THIRD value: a dog whose owner never answered stays NULL through the view. Without this
    -- arm a view hard-wired to `true` satisfies the first arm and a view hard-wired to any
    -- constant satisfies one of the two — three different values is what no constant can be.
    update bookings set dog_id = d_unknown where id = bk_open;
    v_row := t_lmt_view_row(rA, 'runner_open_requests', bk_open);
    if v_row is null then v_bad := v_bad || ' 무응답 강아지의 예약이 뷰에서 사라졌다';
    elsif not (v_row ? 'neutered') then v_bad := v_bad || ' 🔴 무응답 행에 neutered 칸이 없다';
    elsif (v_row->>'neutered') is not null
      then v_bad := v_bad || ' 🔴 무응답이 값으로 바뀌었다: ' || (v_row->>'neutered'); end if;
    update bookings set dog_id = d_yes where id = bk_open;
    -- the ACLs 0121:150-153 set, both directions
    if has_table_privilege('anon', 'public.runner_open_requests', 'select') is not false
      then v_bad := v_bad || ' 🔴 anon이 오픈 요청 뷰를 읽는다'; end if;
    if has_table_privilege('anon', 'public.my_directed_requests', 'select') is not false
      then v_bad := v_bad || ' 🔴 anon이 지명 요청 뷰를 읽는다'; end if;
    if has_table_privilege('authenticated', 'public.runner_open_requests', 'select') is not true
      then v_bad := v_bad || ' 대조 실패: authenticated가 오픈 요청 뷰를 못 읽는다 (그랜트가 통째로 사라졌다)'; end if;
    if has_table_privilege('authenticated', 'public.my_directed_requests', 'select') is not true
      then v_bad := v_bad || ' 대조 실패: authenticated가 지명 요청 뷰를 못 읽는다'; end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then call _pass('lmt','0209-N1 0001부터 모아 온 dogs.neutered가 러너의 요청 카드에 닿는다 — 두 뷰 모두 칸을 내보내고 값은 그 강아지의 **실제 값**이다(true·false·무응답 NULL 세 가지라 어느 상수도 세 팔을 동시에 만족시킬 수 없다; 무응답은 값이 아니라 NULL로 나가고 클라가 아무것도 안 그린다); 나머지는 한 칸도 안 움직였다 — 0121 §D의 요금 봉인이 두 뷰 모두에서 그대로이고, anon은 여전히 못 읽고 authenticated는 여전히 읽는다(그랜트를 통째로 지운 게 아니라는 대조)');
    else v_msg := v_bad; call _fail('lmt','0209-N1 중성화 칸', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('lmt','0209-N1 중성화 칸', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0209-M3] paid_won is a filter on the same net — a DELTA this suite caused
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- ⚠ LAST among the behaviour pins: this one writes. Everything above reads a world no payout
  --   has touched, so none of those greens can be produced by this payment.
  begin
    v_bad := '';
    v_js := t_lmt_read_as(rA, 24);
    v_row := t_lmt_row(v_js, mM1);
    if v_row is null then v_bad := v_bad || ' 지급 전 M-1 달이 없다';
    else
      v_before := (v_row->>'paid')::bigint;
      v_sum    := (v_row->>'net')::bigint;
      if v_before is distinct from 0
        then v_bad := v_bad || ' 대조 실패: 지급 전 paid_won=' || v_before || ' (0이어야 한다)'; end if;
    end if;
    -- pay ONE booking's rows through the REAL ops door
    v_paid_bk := t_lmt_bk_net(bk_b);
    if t_lmt_pay(ops, rA, bk_b) is null then v_bad := v_bad || ' 지급 행이 만들어지지 않았다'; end if;
    if (select count(*) from ledger_items
         where booking_id = bk_b and paid_payout_id is not null) is distinct from 1
      then v_bad := v_bad || ' 대조 실패: 원장 행에 지급 표식이 안 붙었다'; end if;

    v_js := t_lmt_read_as(rA, 24);
    v_row := t_lmt_row(v_js, mM1);
    if v_row is null then v_bad := v_bad || ' 🔴 지급 뒤 M-1 달이 사라졌다';
    else
      v_after := (v_row->>'paid')::bigint;
      if (v_after - v_before) is distinct from v_paid_bk
        then v_bad := v_bad || ' 🔴 paid_won 델타=' || (v_after - v_before)
                   || ' (기대 ' || v_paid_bk || ')'; end if;
      -- net_won did NOT move — paying money does not earn money
      if (v_row->>'net')::bigint is distinct from v_sum
        then v_bad := v_bad || ' 🔴 지급이 net_won을 움직였다: ' || v_sum || ' → ' || (v_row->>'net'); end if;
      -- …and paid_won is STRICTLY less than net_won, because the comp row in the same month is
      -- still unpaid. A `paid_won` that were a second copy of `net_won` is visible only here.
      if (v_after < (v_row->>'net')::bigint) is not true
        then v_bad := v_bad || ' 🔴 paid_won이 net_won과 같거나 크다 (필터가 아니라 사본이다)'; end if;
    end if;
    -- CONTROLS: the other two months were not touched by this payment
    if (t_lmt_row(v_js, mM2)->>'paid')::bigint is distinct from 0
      then v_bad := v_bad || ' 🔴 M-2의 paid_won이 움직였다'; end if;
    if (t_lmt_row(v_js, m0)->>'paid')::bigint is distinct from 0
      then v_bad := v_bad || ' 🔴 M0의 paid_won이 움직였다'; end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then call _pass('lmt','0209-M3 paid_won은 같은 net을 0186의 표식(paid_payout_id)으로 가른 것이다 — **실제 문**(ops_record_manual_payout)으로 한 예약의 행을 지급하면 그 달의 paid_won이 0에서 정확히 그 행들의 net만큼 **오르고**(이 스위트가 일으킨 전/후 델타이지 굴러다니던 상태가 아니다), 같은 달의 net_won은 한 푼도 안 움직이며, 같은 달에 미지급 보상 행이 남아 있으므로 paid_won < net_won이다(둘이 같으면 필터가 아니라 사본이다); 대조 — 나머지 두 달의 paid_won은 0 그대로다');
    else v_msg := v_bad; call _fail('lmt','0209-M3 지급 표식', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('lmt','0209-M3 지급 표식', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0209-S1] the deployed shape
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'my_ledger_month_totals';
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(my_ledger_month_totals)';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' definer가 아니다'; end if;
      if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}'))
            from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 본문 search_path가 없다'; end if;
      -- ACL by EFFECTIVE privilege, in BOTH directions, NULL arm FIRST: aclexplode(NULL) returns
      -- zero rows, so an `exists` test alone is silent on exactly the born-PUBLIC state (0116:636).
      if (select proacl from pg_proc where oid = v_oid) is null
        then v_bad := v_bad || ' ACL이 NULL이다 (기본 PUBLIC)'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false
        then v_bad := v_bad || ' anon이 실행할 수 있다'; end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not true
        then v_bad := v_bad || ' authenticated가 실행할 수 없다'; end if;
      -- 🔴 the margin ruling, asserted by NAME (Sean 2026-08-24). A month net is a sum of numbers
      --    the runner already reads; a component beside it hands the fee back by subtraction.
      if (select count(*) from unnest((select proargnames from pg_proc where oid = v_oid)) nm
           where nm in ('gross_won','fee_won','commission_rate','platform_fee','gross','fee'))
           is distinct from 0
        then v_bad := v_bad || ' 🔴 러너 화면 함수에 마진 칸이 있다'; end if;
      -- the output columns are exactly the four
      if (select count(*) from unnest((select proargnames from pg_proc where oid = v_oid)) nm
           where nm in ('month_start','net_won','run_count','paid_won')) is distinct from 4
        then v_bad := v_bad || ' 출력 네 칸이 이름대로 있지 않다'; end if;

      select prosrc into v_raw from pg_proc where oid = v_oid;
      if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(my_ledger_month_totals)';
      else
        -- COMMENTS STRIPPED before matching: `prosrc` is source plus our own prose, and this
        -- body's comments name Asia/Seoul and auth.uid() — an un-stripped match would be
        -- satisfied by the writing that EXPLAINS the guard (CLAUDE.md, the comment-matching law).
        v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
        if (v_src ~ 'date_trunc\(''month'', l\.created_at at time zone ''Asia/Seoul''\)') is not true
          then v_bad := v_bad || ' 🔴 달 경계가 KST로 고정돼 있지 않다 (date_trunc가 timestamptz를 받는다)'; end if;
        if (v_src ~ 'date_trunc\(''month'', now\(\) at time zone ''Asia/Seoul''\)') is not true
          then v_bad := v_bad || ' 🔴 창의 기준점이 KST로 고정돼 있지 않다'; end if;
        if (v_src ~ 'l\.runner_id = auth\.uid\(\)') is not true
          then v_bad := v_bad || ' 행 범위(l.runner_id = auth.uid())가 없다'; end if;
        if (v_src ~ 'not_authenticated') is not true
          then v_bad := v_bad || ' not_authenticated 거절이 없다'; end if;
        -- `ledger_items` exactly once, so a later edit cannot slip an unscoped second read beside it
        if (select count(*) from regexp_matches(v_src, '\mledger_items\M', 'g')) is distinct from 1
          then v_bad := v_bad || ' ledger_items를 한 번보다 많이 읽는다'; end if;
        -- the CRUDE CONTROL for the stripper: the RAW source really does carry `--` comments, so a
        -- stripper that silently did nothing cannot be what makes the arms above pass.
        if (v_raw ~ '-- §0d') is not true
          then v_bad := v_bad || ' 대조: 원본 소스에 §0d 주석이 없다 (주석 제거 팔이 무의미)'; end if;
        if (v_src ~ '§0d') is not false
          then v_bad := v_bad || ' 대조: 주석이 실제로 제거되지 않았다'; end if;
      end if;
    end if;
    -- `ledger_items` stays table-sealed (0121:224, restated 0186:200) — every runner read of it
    -- is an RPC, and a file that re-granted the table would pass every arm above.
    if has_table_privilege('authenticated', 'public.ledger_items', 'select') is not false
      then v_bad := v_bad || ' 🔴 authenticated가 ledger_items를 직접 읽는다'; end if;
    if v_bad = '' then call _pass('lmt','0209-S1 배포 형상 — definer·본문 search_path·ACL 양방향(NULL-ACL 팔 먼저)·proargnames에 마진 칸도 대상 러너 인자도 없고 출력 네 칸은 이름대로 있다; 주석 벗긴 소스에서 **두 date_trunc가 모두 KST 벽시계 위에서** 돌고(timestamptz에 걸면 세션 타임존이 답을 고른다) 행 범위 l.runner_id = auth.uid()와 not_authenticated 거절이 있으며 ledger_items를 **정확히 한 번** 읽는다 — 원본에는 §0d 주석이 있고 벗긴 소스에는 없다는 양방향 크루드 대조 포함; 0121:224의 테이블 봉인은 그대로(authenticated는 ledger_items를 직접 못 읽는다); NO-FUNCTION·NO-SOURCE는 큰 소리로 실패');
    else v_msg := v_bad; call _fail('lmt','0209-S1 배포 형상', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('lmt','0209-S1 배포 형상', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
