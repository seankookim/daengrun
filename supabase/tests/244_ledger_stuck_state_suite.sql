-- ═══ 244 — 0213: the stuck-payout answer stops being read out of a 30-row window
-- ═══        0213-A1 · A2 · A3 · A4 · A5 · S1, tag `lss`
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a pin
-- written while staring at a mutation tends to assert what that mutation broke rather than the
-- property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · A1 **THE ANSWER COMES FROM THE ROW THE CAP HID.** A runner with 35 settled, unpaid ledger
--        rows aged 1…35 days: `oldest_awaiting_at` is the created_at of row 35 — read back from
--        the row itself, never from a predicate this suite re-typed. 🔴 And the arm that makes
--        that attributable rather than lucky: the SAME caller's `my_ledger_rows()` returns exactly
--        30 rows, its oldest is STRICTLY NEWER, and **row 35 is not among them at all**. The
--        fixture therefore sits where the capped read and the uncapped read DISAGREE; a fixture of
--        ≤ 30 rows is in the agreement zone and would be green under either implementation
--        (CLAUDE.md, the 175-V2 fixture-agreement law). ⚠ Two rows OLDER than the answer sit in
--        the fixture, excluded by a DIFFERENT conjunct each — one unpaid with its run still open
--        (60 days), one settled but already paid (90 days) — so both conjuncts of the awaiting
--        predicate are load-bearing here. Without them, deleting either conjunct would change no
--        number and the pin would be blind rather than passing.
--   · A2 **`unpaid_won` IS 0192 §B'S NUMBER, MEASURED AGAINST 0192 §B.** It equals
--        `my_ledger_unpaid_total()` read by the same caller — a RESULT, not a transcription. The
--        fixture carries an UNSETTLED unpaid row, so on it the unpaid modulus and the awaiting
--        modulus are genuinely different numbers, and the suite asserts that difference FIRST:
--        without it, an implementation that used one predicate for both columns would satisfy the
--        equality and the pin would measure nothing. The other side is asserted too — the number
--        is STRICTLY BELOW the runner's lifetime sum, because the fixture's paid row's money is in
--        one and must not be in the other.
--   · A3 **THE AWAITING COLUMNS AGREE WITH THE WRITER, NOT WITH THE WIDER PREDICATE.** Two
--        runners swept in ONE real `ops_payouts_stuck_sweep()` tick. The one whose oldest
--        SETTLED-unpaid row is 35 days old is told; the one whose oldest settled-unpaid row is 3
--        days old is NOT — even though that second runner also holds an unpaid row 60 days old
--        whose run is still open. `oldest_awaiting_at` reads 3 days for them, never 60. An
--        implementation that dropped the settled conjunct would call that runner two months stuck
--        while the function that actually pays them says nothing, and the screen would promise
--        money the writer refuses (0186 §0d ⓒ).
--   · A4 **ONE ROW, THE CALLER'S OWN, AND NOTHING FOR ANYONE ELSE.** A second runner reads their
--        own numbers in the same instant; a profile with no ledger rows at all gets exactly ONE
--        row of zeros and a NULL instant (never zero rows — 「no rows」 and 「nothing owed」 are
--        different facts and a caller would have to invent a meaning for the absence); an
--        anonymous caller is refused by name.
--   · A5 **`has_bank_account` IS A READ, NOT A GUESS.** Two runners in the same instant differ
--        only in whether a `bank_accounts` row exists and read different booleans, so the answer
--        is attributable to the row rather than to the call; then inserting and deleting that row
--        moves the boolean both ways. Every value is a delta this pin caused.
--   · S1 **DEPLOYED SHAPE.** definer + in-body `search_path`; ACL by value in BOTH directions;
--        NO subject argument of any spelling (the party gate is an absence, and a `p_runner`
--        added later reddens no behavioural arm on a fixture where caller and subject are one
--        person — 0203 `E4`); no margin or bank column in the OUT list; and the comment-stripped
--        body with a NO-SOURCE arm, a two-sided stripper control, and the `limit` that must not
--        have come back.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose, not pins — the harness cannot reach it) ───
--   · That the SCREEN calls this function. `app/test/*.cjs` cannot import a `.tsx` route module,
--     so re-planting `fetchLedger()` into `runner/home.tsx` would redden nothing here. The pure
--     half is pinned by `app/test/payout-status.test.cjs` (`payoutStuckDays` over an aggregate);
--     the binding is prose in 0213's header and a device smoke step. Same source-vs-runtime
--     division as `check-definer-acl` beside 98 H1 — and the same warning: neither is evidence
--     for the other.
--   · Performance. The function walks every ledger row the runner owns and there is no index arm
--     here; `ledger_items.runner_id` carries 0001's index and the harness cannot measure a plan
--     that means anything at fixture scale.
--
-- ─── FIXTURE NOTES ───
--  ① `request.jwt.claim.sub` is set and cleared inside every helper (218 ①'s rule): a leftover
--     claim would make a 「no caller」 arm silently measure the wrong thing.
--  ② `ops_payouts_stuck_sweep()` is GLOBAL — it walks every runner in the database and earlier
--     suites have their own ledger rows. So nothing here reads a global count: every number is a
--     DELTA around the tick, scoped to this suite's own profiles.
--  ③ The 35 settled rows are written by the REAL settle path (`t_active_booking` + `t_settle`),
--     so the candidate set is exactly what production would produce; only `created_at` is moved,
--     because the condition under test is an AGE and the harness cannot wait.
set client_min_messages = warning;

-- The function under test, read as one caller. `rows_back` is counted separately because
-- `select … into` takes the first row silently, and 「exactly one row」 is one of A4's claims.
create or replace function t_lss_state(p_uid uuid,
                                       out unpaid bigint, out oldest timestamptz,
                                       out cnt int, out bank boolean,
                                       out rows_back int, out raised text)
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  select count(*) into rows_back from my_ledger_stuck_state();
  select s.unpaid_won, s.oldest_awaiting_at, s.awaiting_count, s.has_bank_account
    into unpaid, oldest, cnt, bank
    from my_ledger_stuck_state() s;
  perform set_config('request.jwt.claim.sub', '', true);
exception when others then
  raised := sqlerrm;
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- 0192 §B, read by the same caller. The shipped function, never a copy of its predicate.
create or replace function t_lss_unpaid_rpc(p_uid uuid) returns bigint language plpgsql as $$
declare v bigint;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  v := my_ledger_unpaid_total();
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;

-- The CAPPED list, read by the same caller — A1's control arm.
create or replace function t_lss_capped(p_uid uuid, p_booking uuid,
                                        out n int, out oldest timestamptz, out has_bk boolean)
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  select count(*), min(x.created_at) into n, oldest from my_ledger_rows() x;
  select exists (select 1 from my_ledger_rows() y where y.booking_id = p_booking) into has_bk;
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- A runner with `p_items` settled, unpaid ledger rows aged 1, 2, … p_items days — so the OLDEST is
-- row number p_items, which is precisely the row a `limit 30` on a `created_at desc` order drops.
create or replace function t_lss_runner(p_tag text, p_items int,
                                        out o uuid, out r uuid, out d uuid, out rt uuid,
                                        out oldest_bk uuid)
language plpgsql as $$
declare i int; bk uuid;
begin
  o  := t_user('lss_' || p_tag || '_o', 'owner');
  r  := t_user('lss_' || p_tag || '_r', 'runner');
  d  := t_dog(o, 'lss-' || p_tag);
  rt := t_route('lss 코스 ' || p_tag);
  for i in 1 .. p_items loop
    bk := t_active_booking(o, r, d, rt, now() - interval '2 days');
    perform t_settle(bk, 'dog_condition');
    update ledger_items set created_at = now() - make_interval(days => i) where booking_id = bk;
    if i = p_items then oldest_bk := bk; end if;
  end loop;
end $$;

-- An UNPAID row whose run is still open — 0192 §A's third state. `t_active_booking` leaves
-- `runs.ended_at` NULL, so this row is unpaid and NOT settled: it belongs to `my_ledger_unpaid_total`
-- and must not belong to the awaiting columns.
create or replace function t_lss_live(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                      p_age interval, p_net int, out bk uuid, out li uuid)
language plpgsql as $$
begin
  bk := t_active_booking(p_owner, p_runner, p_dog, p_route, now() - interval '1 day');
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee, created_at)
  values (p_runner, bk, p_net + 1000, 0, 0, 0, 0, 1000, now() - p_age)
  returning id into li;
end $$;

-- A settled row that HAS BEEN PAID — 0186's marker, pointed at a real `payouts` row. Without one
-- in the fixture the `paid_payout_id is null` conjunct is not load-bearing anywhere: every arm
-- would read the same with it deleted, which is a blind pin rather than a passing one (CLAUDE.md,
-- 「a fixture that omits the defect cannot test the fix」).
create or replace function t_lss_paid(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                      p_age interval, out bk uuid, out li uuid)
language plpgsql as $$
declare v_po uuid;
begin
  bk := t_active_booking(p_owner, p_runner, p_dog, p_route, now() - interval '1 day');
  perform t_settle(bk, 'completed');
  insert into payouts (runner_id, period_start, period_end, gross, tax_withheld, net,
                       status, paid_at)
  values (p_runner, (now() - p_age)::date, (now() - p_age)::date, 10000, 330, 9670,
          'paid', now() - p_age)
  returning id into v_po;
  update ledger_items set created_at = now() - p_age, paid_payout_id = v_po
   where booking_id = bk returning id into li;
end $$;

-- Every ledger row the runner owns, paid or not — A2's control that the paid row's money is
-- genuinely PRESENT in the fixture and genuinely absent from `unpaid_won`.
create or replace function t_lss_lifetime(p_runner uuid) returns bigint language sql as $$
  select coalesce(sum(base + distance_pay + addon_pay + tip
                        + coalesce(remaining_guarantee, 0) - platform_fee), 0)::bigint
    from ledger_items where runner_id = p_runner
$$;

-- The awaiting sum, derived by THIS SUITE from the rows — used only as A2's control that the
-- fixture genuinely separates the two moduli, never as the expected value of a shipped column.
create or replace function t_lss_awaiting_sum(p_runner uuid) returns bigint language sql as $$
  select coalesce(sum(l.base + l.distance_pay + l.addon_pay + l.tip
                        + coalesce(l.remaining_guarantee, 0) - l.platform_fee), 0)::bigint
    from ledger_items l
   where l.runner_id = p_runner and l.paid_payout_id is null
     and not exists (select 1 from runs rn
                      where rn.booking_id = l.booking_id and rn.ended_at is null)
$$;

-- The runner's own stuck-payout notifications, scoped by every field 0210 §E's writer sets.
create or replace function t_lss_told(p_runner uuid) returns int language sql as $$
  select count(*)::int from notifications
   where profile_id = p_runner and kind = 'booking'
     and title = '정산 지급이 늦어지고 있어요' and ref_id is null
$$;

do $$
declare
  oA uuid; rA uuid; dA uuid; rtA uuid; bkA uuid;
  oB uuid; rB uuid; dB uuid; rtB uuid; bkB uuid;
  oC uuid; rC uuid; dC uuid; rtC uuid; bkC uuid;
  ownerX uuid;
  st record; st2 record; cap record;
  v_bad text; v_msg text; v_n int; v_raw text; v_src text; v_oid oid;
  v_planted timestamptz; v_rpc bigint; v_await bigint;
  v_beforeA int; v_afterA int; v_beforeC int; v_afterC int;
begin
  perform set_config('request.jwt.claim.sub', '', true);                                        -- ①

  -- rA: 35 settled unpaid rows aged 1…35 days, PLUS one unpaid row aged 60 days whose run is
  --     still open, PLUS one settled row aged 90 days that has already been PAID. So all three
  --     conjuncts have a row that only they exclude, and the three predicates disagree about the
  --     oldest instant by construction: 90d (any row) · 60d (unpaid) · 35d (unpaid and settled).
  select w.o, w.r, w.d, w.rt, w.oldest_bk into oA, rA, dA, rtA, bkA from t_lss_runner('a', 35) w;
  perform t_lss_live(oA, rA, dA, rtA, interval '60 days', 7000);
  perform t_lss_paid(oA, rA, dA, rtA, interval '90 days');
  insert into bank_accounts (runner_id, bank, account_enc, holder)
  values (rA, '토스뱅크', 'ENC-LSS-A', '김러너') on conflict (runner_id) do nothing;

  -- rB: two settled unpaid rows, two days old. No bank row.
  select w.o, w.r, w.d, w.rt into oB, rB, dB, rtB from t_lss_runner('b', 2) w;

  -- rC: ONE settled unpaid row three days old, plus an unpaid row 60 days old whose run is open.
  --     The writer does not owe them a message; the wider predicate would say two months.
  select w.o, w.r, w.d, w.rt, w.oldest_bk into oC, rC, dC, rtC, bkC from t_lss_runner('c', 1) w;
  update ledger_items set created_at = now() - interval '3 days' where runner_id = rC;
  perform t_lss_live(oC, rC, dC, rtC, interval '60 days', 5000);

  ownerX := t_user('lss_owner_x', 'owner');

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0213-A1] the answer comes from the row the cap hid
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select created_at into v_planted from ledger_items where booking_id = bkA;
    if v_planted is null then v_bad := v_bad || ' fixture: the oldest planted row has no ledger item'; end if;
    -- FIXTURE CONTROL: two rows OLDER than the answer exist and are excluded by a different
    -- conjunct each — one unpaid-but-open (60d), one settled-but-paid (90d). Without them the
    -- awaiting predicate's conjuncts are not load-bearing anywhere and every arm below would read
    -- the same with them deleted.
    select count(*) into v_n from ledger_items l
     where l.runner_id = rA and l.created_at < v_planted
       and (l.paid_payout_id is not null
            or exists (select 1 from runs rn where rn.booking_id = l.booking_id and rn.ended_at is null));
    if v_n is distinct from 2
      then v_bad := v_bad || ' fixture: ' || coalesce(v_n::text,'NULL')
                          || ' excluded rows older than the answer (expected 2 — one open-run, one paid)'; end if;

    select * into st from t_lss_state(rA);
    if st.raised is not null then v_bad := v_bad || ' the read raised ' || st.raised;
    else
      if st.oldest is distinct from v_planted
        then v_bad := v_bad || ' oldest_awaiting_at=' || coalesce(st.oldest::text, 'NULL')
                            || ' but the oldest settled unpaid row was written at ' || v_planted::text; end if;
      if st.cnt is distinct from 35
        then v_bad := v_bad || ' awaiting_count=' || coalesce(st.cnt::text, 'NULL') || ' (expected 35 — the live row must not be counted)'; end if;
    end if;

    -- 🔴 THE CONTROL THAT MAKES THE ARM ABOVE ATTRIBUTABLE. The same caller's capped list holds
    --    exactly 30 rows, its oldest is strictly NEWER, and the row the answer came from is not
    --    in it at all — so this fixture is OUTSIDE the zone where the two reads agree.
    select * into cap from t_lss_capped(rA, bkA);
    if cap.n is distinct from 30
      then v_bad := v_bad || ' fixture: my_ledger_rows() returned ' || coalesce(cap.n::text, 'NULL')
                          || ' rows — the 30-row cap is not biting and this pin proves nothing'; end if;
    if (cap.oldest > v_planted) is not true
      then v_bad := v_bad || ' fixture: the capped list''s oldest (' || coalesce(cap.oldest::text, 'NULL')
                          || ') is not strictly newer than the planted row — the two reads agree here'; end if;
    if cap.has_bk is not false
      then v_bad := v_bad || ' 🔴 the capped list CAN see the row the answer comes from — the fixture is in the agreement zone'; end if;

    if v_bad = '' then call _pass('lss','0213-A1 답은 캡이 가린 행에서 나온다 — 35건(1~35일) 중 가장 오래된 35번째 행의 created_at 이 oldest_awaiting_at 이고(술어를 다시 옮겨 적은 값이 아니라 그 행에서 읽었다), awaiting_count 는 35다(열린 run 이 달린 행은 안 센다). 같은 호출자의 my_ledger_rows() 는 정확히 30행이고 그 최소 시각은 **엄격히 더 최신**이며 답이 나온 그 행은 목록에 아예 없다 — 두 읽기가 어긋나는 자리에 픽스처가 놓여 있다');
    else v_msg := v_bad; call _fail('lss','0213-A1 the answer comes from the row the cap hid', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('lss','0213-A1 the answer comes from the row the cap hid', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0213-A2] unpaid_won is 0192 §B's number, measured against 0192 §B
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v_rpc   := t_lss_unpaid_rpc(rA);
    v_await := t_lss_awaiting_sum(rA);

    -- CONTROL FIRST, and it is what makes the equality below mean anything: on this fixture the
    -- two moduli are DIFFERENT numbers. Without the live row they would be equal, and a function
    -- that used the awaiting predicate for both columns would pass the equality by luck.
    if (v_rpc > v_await) is not true
      then v_bad := v_bad || ' fixture: unpaid(' || coalesce(v_rpc::text,'NULL') || ') is not strictly greater than awaiting('
                          || coalesce(v_await::text,'NULL') || ') — the two predicates agree here and this pin measures nothing'; end if;

    select * into st from t_lss_state(rA);
    if st.raised is not null then v_bad := v_bad || ' the read raised ' || st.raised;
    else
      if st.unpaid is distinct from v_rpc
        then v_bad := v_bad || ' unpaid_won=' || coalesce(st.unpaid::text,'NULL')
                            || ' but my_ledger_unpaid_total()=' || coalesce(v_rpc::text,'NULL'); end if;
      if st.unpaid is not distinct from v_await
        then v_bad := v_bad || ' 🔴 unpaid_won equals the AWAITING sum — the two moduli have been collapsed into one predicate'; end if;
      -- the other side of 0192 §B's predicate: money already PAID is in the lifetime and must not
      -- be in the unpaid. The fixture's 90-day paid row is what makes this comparison non-vacuous.
      if (st.unpaid < t_lss_lifetime(rA)) is not true
        then v_bad := v_bad || ' unpaid_won=' || coalesce(st.unpaid::text,'NULL')
                            || ' is not strictly below the lifetime sum (' || coalesce(t_lss_lifetime(rA)::text,'NULL')
                            || ') — a row already paid is being counted as still owed'; end if;
    end if;

    if v_bad = '' then call _pass('lss','0213-A2 unpaid_won 은 0192 §B의 수다 — 같은 호출자로 읽은 my_ledger_unpaid_total() 과 **같고**(옮겨 적기가 아니라 결과), 같은 픽스처의 awaiting 합과는 **다르다**. 먼저 두 모수가 실제로 갈리는 자리인지 확인한다(열린 run 이 달린 미지급 행 때문에 unpaid > awaiting) — 갈리지 않는 픽스처였다면 한 술어로 두 칸을 채운 구현도 이 등식을 통과한다');
    else v_msg := v_bad; call _fail('lss','0213-A2 unpaid_won is 0192 §B''s number', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('lss','0213-A2 unpaid_won is 0192 §B''s number', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0213-A3] the awaiting columns agree with the WRITER, not with the wider predicate
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- rC's numbers BEFORE the tick: three days, one row — never sixty, though a sixty-day-old
    -- unpaid row of theirs is sitting right there with its run still open.
    select * into st from t_lss_state(rC);
    if st.raised is not null then v_bad := v_bad || ' rC read raised ' || st.raised;
    else
      if st.cnt is distinct from 1
        then v_bad := v_bad || ' rC awaiting_count=' || coalesce(st.cnt::text,'NULL') || ' (expected 1 — the open-run row is not awaiting)'; end if;
      if (st.oldest > now() - interval '7 days') is not true
        then v_bad := v_bad || ' 🔴 rC oldest_awaiting_at=' || coalesce(st.oldest::text,'NULL')
                            || ' is older than the writer''s threshold — the settled conjunct is gone and the screen would promise money the writer refuses'; end if;
      if (st.unpaid > 0) is not true
        then v_bad := v_bad || ' fixture: rC has no unpaid money at all, so 「unpaid but not awaiting」 is not what is being measured'; end if;
    end if;

    -- ONE real tick. Deltas only — the sweep is global and earlier suites own rows in it (②).
    v_beforeA := t_lss_told(rA);
    v_beforeC := t_lss_told(rC);
    perform ops_payouts_stuck_sweep();
    v_afterA  := t_lss_told(rA);
    v_afterC  := t_lss_told(rC);
    if (v_afterA - v_beforeA) is distinct from 1
      then v_bad := v_bad || ' the writer told rA ' || (v_afterA - v_beforeA)::text
                          || ' times (expected 1 — their oldest awaiting row is 35 days old)'; end if;
    if (v_afterC - v_beforeC) is distinct from 0
      then v_bad := v_bad || ' 🔴 the writer told rC ' || (v_afterC - v_beforeC)::text
                          || ' times, but this function reports their oldest awaiting row as three days old — reader and writer disagree'; end if;

    if v_bad = '' then call _pass('lss','0213-A3 awaiting 칸은 **쓰는 쪽**과 같은 세계를 본다 — 한 번의 진짜 ops_payouts_stuck_sweep() 틱에서, 가장 오래된 정산완료·미지급 행이 35일인 러너는 통보받고 3일인 러너는 통보받지 않는다(둘 다 60일 된 미지급 행을 갖고 있지만 그 행의 run 은 아직 안 끝났다). 그 러너의 oldest_awaiting_at 은 3일이지 60일이 아니다 — 정산 conjunct 를 빼면 화면은 서버가 지급을 거절하는 돈을 두 달째 밀렸다고 말하게 된다');
    else v_msg := v_bad; call _fail('lss','0213-A3 the awaiting columns agree with the writer', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('lss','0213-A3 the awaiting columns agree with the writer', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0213-A4] one row, the caller's own, and nothing for anyone else
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select * into st  from t_lss_state(rA);
    select * into st2 from t_lss_state(rB);
    if st.raised is not null or st2.raised is not null
      then v_bad := v_bad || ' a runner read raised ' || coalesce(st.raised, st2.raised);
    else
      if st2.cnt is distinct from 2
        then v_bad := v_bad || ' rB awaiting_count=' || coalesce(st2.cnt::text,'NULL') || ' (expected 2 — their own rows)'; end if;
      if st2.unpaid is not distinct from st.unpaid
        then v_bad := v_bad || ' 🔴 two different runners read the SAME unpaid_won (' || coalesce(st.unpaid::text,'NULL') || ')'; end if;
      if (st2.unpaid > 0) is not true
        then v_bad := v_bad || ' fixture: rB has no money, so an equal-numbers arm would be vacuous'; end if;
      if st.rows_back is distinct from 1 or st2.rows_back is distinct from 1
        then v_bad := v_bad || ' a runner got ' || coalesce(st.rows_back::text,'NULL') || '/'
                            || coalesce(st2.rows_back::text,'NULL') || ' rows (expected exactly 1 each)'; end if;
    end if;

    -- a profile with NO ledger rows: one row of measured zeros, never zero rows
    select * into st from t_lss_state(ownerX);
    if st.raised is not null then v_bad := v_bad || ' a profile with no ledger rows raised ' || st.raised;
    else
      if st.rows_back is distinct from 1
        then v_bad := v_bad || ' a profile with no ledger rows got ' || coalesce(st.rows_back::text,'NULL')
                            || ' rows — 「no rows」 and 「nothing owed」 are different facts'; end if;
      if st.unpaid is distinct from 0
        then v_bad := v_bad || ' empty unpaid_won=' || coalesce(st.unpaid::text,'NULL') || ' (expected a measured 0)'; end if;
      if st.cnt is distinct from 0
        then v_bad := v_bad || ' empty awaiting_count=' || coalesce(st.cnt::text,'NULL'); end if;
      if st.oldest is not null
        then v_bad := v_bad || ' empty oldest_awaiting_at=' || st.oldest::text || ' (expected NULL — the screen draws nothing for NULL)'; end if;
    end if;

    -- anonymous, refused BY NAME and before any read
    select * into st from t_lss_state(null);
    if st.raised is distinct from 'not_authenticated'
      then v_bad := v_bad || ' an anonymous caller got ' || coalesce(st.raised, 'AN ANSWER') || ' instead of not_authenticated'; end if;

    if v_bad = '' then call _pass('lss','0213-A4 한 행, 그리고 호출자 자신의 것 — 두 러너가 같은 순간에 각자의 수를 읽고(서로 다르다), 원장 행이 하나도 없는 프로필은 **0행이 아니라 1행**으로 측정된 0과 NULL 시각을 받으며(「행이 없다」와 「줄 돈이 없다」는 다른 사실이다), 익명 호출은 not_authenticated 로 이름을 대며 거절된다');
    else v_msg := v_bad; call _fail('lss','0213-A4 one row, the caller''s own', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('lss','0213-A4 one row, the caller''s own', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0213-A5] has_bank_account is a read, not a guess
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- SAME INSTANT, two runners differing only in the row. A hard-wired boolean of either value
    -- satisfies one arm and dies on the other, which is what makes this a control pair rather
    -- than one measurement printed twice.
    select * into st  from t_lss_state(rA);
    select * into st2 from t_lss_state(rB);
    if st.bank is not true  then v_bad := v_bad || ' rA has a bank_accounts row and reads has_bank_account=' || coalesce(st.bank::text,'NULL'); end if;
    if st2.bank is not false then v_bad := v_bad || ' rB has NO bank_accounts row and reads has_bank_account=' || coalesce(st2.bank::text,'NULL'); end if;

    -- and both directions as deltas this pin caused
    insert into bank_accounts (runner_id, bank, account_enc, holder)
    values (rB, '카카오뱅크', 'ENC-LSS-B', '박러너') on conflict (runner_id) do nothing;
    select * into st2 from t_lss_state(rB);
    if st2.bank is not true then v_bad := v_bad || ' registering an account left has_bank_account=' || coalesce(st2.bank::text,'NULL'); end if;
    delete from bank_accounts where runner_id = rB;
    select * into st2 from t_lss_state(rB);
    if st2.bank is not false then v_bad := v_bad || ' removing the account left has_bank_account=' || coalesce(st2.bank::text,'NULL'); end if;

    if v_bad = '' then call _pass('lss','0213-A5 has_bank_account 은 읽기다 — 같은 순간에 bank_accounts 행 유무로만 다른 두 러너가 서로 다른 값을 읽고(어느 쪽으로 고정된 상수도 두 팔을 동시에 만족시키지 못한다), 행을 넣으면 true 로 빼면 false 로 **이 핀이 만든 델타**로 움직인다');
    else v_msg := v_bad; call _fail('lss','0213-A5 has_bank_account is a read', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('lss','0213-A5 has_bank_account is a read', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0213-S1] the deployed shape
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- 0213's VERIFY block asserts overlapping properties at APPLY time. That protects them exactly
  -- until someone recreates the function in a LATER migration, which the VERIFY never sees — so
  -- the standing pin lives here as well, deliberately, and the two are not redundant.
  begin
    v_bad := '';
    select oid into v_oid from pg_proc
     where proname = 'my_ledger_stuck_state' and pronamespace = 'public'::regnamespace;
    if v_oid is null then v_bad := v_bad || ' MISSING(my_ledger_stuck_state)';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
        then v_bad := v_bad || ' not a SECURITY DEFINER'; end if;
      if (select 'search_path=public, pg_temp' = any (proconfig) from pg_proc where oid = v_oid)
           is distinct from true
        then v_bad := v_bad || ' no in-body search_path'; end if;
      if (select proacl from pg_proc where oid = v_oid) is null
        then v_bad := v_bad || ' the default PUBLIC ACL survived (a CREATE is born PUBLIC-executable)';
      elsif exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                     where p.oid = v_oid and (a.grantee = 0 or a.grantee = 'anon'::regrole))
        then v_bad := v_bad || ' PUBLIC or anon can execute a definer over sealed money rows'; end if;
      if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true
        then v_bad := v_bad || ' authenticated cannot call it (a seal that shut the front door too)'; end if;

      -- the party gate is an ABSENCE, and no fare component or bank field rides out
      if (select count(*) from unnest(
            coalesce((select proargnames from pg_proc where oid = v_oid), '{}'::text[])) n
           where n in ('p_runner','p_uid','p_profile','p_runner_profile_id','p_runner_id'))
           is distinct from 0
        then v_bad := v_bad || ' it takes a SUBJECT — the gate must be auth.uid() and nothing else'; end if;
      if exists (select 1 from unnest(
                   coalesce((select proargnames from pg_proc where oid = v_oid), '{}'::text[])) n
                  where n in ('gross_won','fee_won','commission_rate','platform_fee','gross',
                              'account_enc','bank','holder'))
        then v_bad := v_bad || ' a margin component or a bank field is in the OUT list'; end if;

      select prosrc into v_raw from pg_proc where oid = v_oid;
      if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(my_ledger_stuck_state)';
      else
        -- Comments stripped before every match: `prosrc` is source PLUS our own prose, and this
        -- body documents every predicate it implements — un-stripped, a check for a conjunct is
        -- satisfied by the paragraph EXPLAINING the conjunct (CLAUDE.md, the comment-matching law).
        v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
        if (v_src ~ '\mlimit\M') is distinct from false
          then v_bad := v_bad || ' a `limit` came back into the body — this function exists because the LIST has one'; end if;
        if (v_src ~ 'l\.runner_id = auth\.uid\(\)') is distinct from true
          then v_bad := v_bad || ' the ledger read is not scoped to the caller'; end if;
        if (v_src ~ 'ba\.runner_id = auth\.uid\(\)') is distinct from true
          then v_bad := v_bad || ' the bank read is not scoped to the caller'; end if;
        if (v_src ~ 'not_authenticated') is distinct from true
          then v_bad := v_bad || ' the anonymous refusal is gone'; end if;
        if (v_src ~ 'not exists \(select 1 from runs rn') is distinct from true
          then v_bad := v_bad || ' the settled conjunct is gone from the body'; end if;
        -- TWO-SIDED stripper control: the raw text HAS a `--` comment carrying the word the arm
        -- above forbids, and the stripped text has NOT. A stripper that silently did nothing
        -- would make that arm fail for a reason that has nothing to do with the code.
        if (v_raw ~ '-- 🔴 NO `limit`') is distinct from true
          then v_bad := v_bad || ' STRIP-CONTROL-ABSENT (the arms above prove nothing)'; end if;
        if (v_src ~ '-- 🔴 NO `limit`') is distinct from false
          then v_bad := v_bad || ' the comment stripper did not run'; end if;
      end if;
    end if;

    if v_bad = '' then call _pass('lss','0213-S1 배포 형상 — definer + 본문 search_path, PUBLIC/anon 실행 불가이고 authenticated 는 부를 수 있다; **주체 인자가 없다**(파티 게이트가 부재로 성립한다 — 나중에 p_runner 가 붙어도 호출자와 대상이 같은 픽스처에서는 어떤 행동 팔도 붉어지지 않는다), 수수료 구성요소도 계좌 칸도 OUT 목록에 없다; 주석을 제거한 본문에 limit 이 없고 두 읽기 모두 auth.uid() 로 좁혀져 있으며 not_authenticated 거절과 정산 conjunct 가 살아 있다; 스트리퍼는 양쪽으로 통제된다(원문에는 그 주석이 있고 제거본에는 없다); 함수가 없으면 NO-SOURCE 로 **크게** 실패한다');
    else v_msg := v_bad; call _fail('lss','0213-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('lss','0213-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
