-- ═══ 223 — 0192: the runner's own view of having been PAID ═════════════════════════════════════
-- ═══        0192-R1 · R2 · R3 · R4 · S1, tag `rpr`                                          ═══
--
-- THE PROPOSITIONS THIS FILE OWNS:
--   · R1 the PAYMENT MARKER rides the runner's own read. A settled unpaid row comes back with
--     `paid_payout_id` NULL, `paid_at` NULL, `settled` true; after a REAL
--     `ops_record_manual_payout` the SAME row carries the payout's id and that payout row's own
--     `paid_at` **by value**, and its untouched sibling still carries neither. The sibling is the
--     control: without it this pin cannot tell 「the marker followed the payment」 from 「everything
--     went non-null」.
--   · R2 `settled` is a THIRD state and not a second name for unpaid. A ledger row on a booking
--     whose run is still open reads `settled = false`; ending that run makes the SAME row read
--     true — a delta this pin CAUSES, never a state it finds. Two further arms, and both are the
--     point rather than garnish: ⓐ while the run is live the WRITER refuses the same row by name
--     (`not_settled`), so the reader and the writer agree about one world; ⓑ a ledger row with NO
--     `runs` row at all — a cancellation compensation (0080/0085) — reads settled TRUE and IS
--     payable. ⓑ is what separates `not exists (… runs rn …)` from a reading of the existing
--     `left join runs r`: on a no-run booking the join contributes nothing, so `r.ended_at is
--     null` reads TRUE and the join form would call that row unsettled FOREVER, since no run will
--     ever arrive to close it.
--     ⚠ The first draft of ⓑ was 「a booking carrying a SECOND, still-open run」 and it is
--     unreachable: `runs.booking_id` is UNIQUE (0001:236) and the harness refused the insert
--     outright. 0192 §0b's justification was corrected to match. Recorded here rather than
--     quietly deleted, because a pin whose premise the schema refutes is exactly the thing that
--     otherwise disappears without anyone learning the fact that killed it.
--   · R3 `my_ledger_unpaid_total()` and `my_ledger_total()` are TWO SENTENCES. Measured as a
--     delta across one real payment: the unpaid total falls by exactly that row's net, the
--     lifetime total does not move at all. The lifetime arm is the control — a §B that had been
--     written by narrowing 0027/0121 instead of beside it passes the first arm and fails this one.
--     Both refuse a NULL uid by name.
--   · R4 🔴 THE CROSS-RUNNER READ, executed AS `authenticated` so RLS is actually on. Two runners
--     with payouts of DIFFERENT amounts (a fixture where the two agree could not distinguish
--     「I read mine」 from 「I read theirs」): the other runner's payout row is invisible to SELECT
--     and `my_ledger_rows()` returns none of their bookings. And the column half — 0186:192-195
--     sealed `memo` · `method` · `recorded_by` away from `authenticated`, and this pin owns the
--     runner-side of that seal, because 0192's §0 ① declines to add a `my_payouts()` definer
--     precisely on the strength of the table grant being correct.
--   · S1 deployed shape of both functions: definer · in-body `search_path` · ACL by value in BOTH
--     directions · the three new columns present by name · source with comments STRIPPED showing
--     0158's distance decision intact, `settled` written as an absence proof, the unpaid total
--     narrowing and `my_ledger_total` NOT narrowed · NO-FUNCTION and NO-SOURCE arms.
--
-- ─── WHY THE SOURCE ARMS IN S1 ARE NOT A DUPLICATE OF R1…R4 ───
-- R1…R4 are behavioural and they are what matters. S1 owns the PRECONDITIONS that make them mean
-- anything and that no behavioural arm can see from one session: `prosecdef`, the in-body
-- `search_path`, and the ACL. §A is a `drop` + `create` — a plain CREATE, born PUBLIC-executable
-- (0116:636) — so 「the grant is right」 is a property this slice can destroy while every one of
-- R1…R4 stays green, because the suite runs as the table owner and never asks who else may call.
-- That is 0131-G4's lesson, and it applies here by construction rather than by analogy.
--
-- ─── WHAT THIS FILE CANNOT SEE, said here rather than discovered later ───
--  · **Concurrency.** Every pin is one session. `ops_record_manual_payout`'s lock is 217's
--    property (`0186-S1`) and the two-process arm is `90_race_check.sh`'s lane; nothing here
--    re-owns it.
--  · **The client mapping.** Whether `earnings.tsx` renders 「지급 완료」 off these columns is a
--    TypeScript fact; `app/test/payout-status.test.cjs` pins it against the real compiled module.
--    A green here says the server hands over three honest columns and NOTHING about what is drawn.
--  · **The `paid_at`-NULL-under-a-set-marker case.** `ops_record_manual_payout` always writes
--    `paid_at = now()`, so today nothing can produce it; it is reachable only by a future writer
--    inserting a `pending` payout. Per the standing law that a limitation is PROSE and not an
--    unfalsifiable pin, it is NOT pinned here — the client's `payout-status.test.cjs` covers the
--    rendering of that shape, which is where the decision actually lives.
--
-- ─── MUTATION MAP — measured 2026-09-22 against these exact files, not predicted ───
--   Lab: a copy of `supabase/` OUTSIDE the worktree (0192 and 223 md5-identical to the committed
--   ones), every plant assert-gated and CHAIN-GATED so a failed plant yields NO row rather than a
--   green one. 「demoted」 = 0192's VERIFY raise turned into a notice so the SUITE is what is
--   measured; 「shipped」 = the file as it lands, where the VERIFY aborts the apply first.
--   ⚠ **CONTROL: 1347 / 0, and it had to be measured TWICE.** Its first run came back
--   APPLY ABORTED while all seven mutation rows behaved sensibly — the cause was environmental,
--   not code: an earlier battery draft deleted `.pgtest` between runs while that run's postmaster
--   was still holding it, and the orphan was still on the lab's socket directory. The battery now
--   stops the cluster by its own PGDATA before discarding the data dir, and the control was
--   re-measured on a clean machine (files md5-verified, 5 `rpr` rows present). A battery whose
--   control fails measures nothing, and 「it is probably the environment」 is not a measurement.
--
--   (i)   the paid marker dropped from the read      → 1346/1: **R1 alone** (`paid_payout_id=NULL
--         (expected the payout just written)`). R2/R3/R4 cannot see it — a fact about which pin
--         owns which sentence, not a gap.
--   (ii)  `settled` reads the LEFT JOIN instead of proving absence (`r.ended_at is not null`)
--                                                    → 1345/2: **R2 + S1**, and R2 fails on ⓑ
--         precisely — 「a ledger row with NO run (취소 보상) reads settled=false」. This is the row
--         that justifies the `not exists` form, reproduced.
--   (iii) `paid_at` becomes `now()` instead of the payout row's instant
--                                                    → 1346/1: **R1 alone**, on BOTH halves — the
--         pre-payment arm (`row A already has paid_at`) and the control arm (`the UNPAID sibling
--         carries a payment date`). A by-value assertion is what makes this visible; 「has a date」
--         would have been green.
--   (iv)  §B stops narrowing (it becomes my_ledger_total again)
--                                                    → 1345/2: **R3 + S1** (`unpaid total
--         33366 → 33366 (expected a fall of exactly 16683)`).
--   (v)   the `revoke` after the drop+create deleted → 1342/5: my **S1** and **FOUR INDEPENDENT
--         SHIPPED PINS** — 98 `H9`, 99 `S1`, 156 `P5`, 189 `0158-B5`. Four other slices agreeing
--         the property is real is worth more than my own arm, and it is the measured proof that
--         `drop` + `create` really does reach the PUBLIC-ACL state 0116:636 describes.
--   (vi)  `grant select (memo, method, recorded_by) on payouts to authenticated` — 0186's seal
--         undone                                     → 1345/2: **R4** (all three columns named,
--         `sqlstate=no-error`) **and 217 `0186-S1`**, the pin belonging to the slice that MADE the
--         seal. This is the arm that earns 0192 §0 ①'s decision not to add a `my_payouts()`
--         definer: the table grant is guarded from both ends.
--   (vii) the ledger read drops `l.runner_id = auth.uid()`
--                                                    → 1341/6: **R4 + R2** and four shipped pins
--         (156 `P1`/`P10`, 165 `P6`, 189 `0158-L1`). R4 names it exactly — 「my_ledger_rows
--         returned the other runner's booking」 and 「the other runner's payout id appears on my
--         ledger read」.
--
-- ─── WHAT THIS FILE CANNOT SEE (continued) ───
--  · **The `paid_at`-NULL-under-a-set-marker case.** `ops_record_manual_payout` always writes
--    `paid_at = now()`, so today nothing can produce it; it is reachable only by a future writer
--    inserting a `pending` payout. Per the standing law that a limitation is PROSE and not an
--    unfalsifiable pin, it is NOT pinned here — the client's `payout-status.test.cjs` covers the
--    rendering of that shape, which is where the decision actually lives.
set client_min_messages = warning;

-- ① a runner with `p_items` settled, unpaid ledger rows written by the REAL settle path.
--    Its own world, not a borrow from 217 or 221: a pin that inherits another suite's setup is
--    testing that setup. Uses only the shared 10_settle helpers.
create or replace function t_rpr_world(p_tag text, p_items int,
                                       out o uuid, out r uuid, out d uuid, out rt uuid)
language plpgsql as $$
declare i int; bk uuid;
begin
  o  := t_user('rpr_' || p_tag || '_o', 'owner');
  r  := t_user('rpr_' || p_tag || '_r', 'runner');
  d  := t_dog(o, 'rpr-' || p_tag);
  rt := t_route('rpr 코스 ' || p_tag);
  for i in 1 .. p_items loop
    bk := t_active_booking(o, r, d, rt, now() - interval '2 days');
    perform t_settle(bk, 'dog_condition');
  end loop;
end $$;

-- ② a booking whose run is LEFT OPEN, carrying one hand-written ledger row. The settle path
--    cannot produce this (it ends the run as it writes), and it is exactly the state 0186 §0d ⓒ
--    refuses to pay — so the fixture has to build it the way 217's does.
create or replace function t_rpr_live_item(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                           out bk uuid, out li uuid)
language plpgsql as $$
begin
  bk := t_active_booking(p_owner, p_runner, p_dog, p_route, now() - interval '1 day');
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee, created_at)
  values (p_runner, bk, 9000, 0, 0, 0, 0, 1000, now() - interval '1 day')
  returning id into li;
end $$;

-- the runner's unpaid ledger ids, oldest first
create or replace function t_rpr_unpaid(p_runner uuid) returns uuid[] language sql as $$
  select coalesce(array_agg(id order by created_at, id), '{}'::uuid[])
    from ledger_items where runner_id = p_runner and paid_payout_id is null
$$;

-- the net of the named rows — the number the operator reads out of ops_payouts_due(), never a
-- literal (221's fixture note ②: an amount typed by hand is a second source of truth)
create or replace function t_rpr_net(p_ids uuid[]) returns int language sql as $$
  select coalesce(sum(base + distance_pay + addon_pay + tip
                        + coalesce(remaining_guarantee, 0) - platform_fee), 0)::int
    from ledger_items where id = any(p_ids)
$$;

create or replace function t_rpr_pay(p_runner uuid, p_ids uuid[], p_amount int) returns jsonb
language plpgsql as $$
declare v uuid;
begin
  begin
    v := ops_record_manual_payout(p_runner, p_ids, p_amount, 'rpr memo — ops only');
    return jsonb_build_object('payout', v);
  exception when others then
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- one row of the runner's own read, as the runner. Returns NULL when the row is not visible,
-- which every caller below distinguishes from a row whose columns happen to be null.
create or replace function t_rpr_row(p_runner uuid, p_booking uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_runner::text, true);
  select jsonb_build_object('id', x.id, 'net', x.net, 'settled', x.settled,
                            'paid_payout_id', x.paid_payout_id, 'paid_at', x.paid_at)
    into v from my_ledger_rows() x where x.booking_id = p_booking;
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;

do $$
declare
  ops1 uuid;
  o uuid; r uuid; d uuid; rt uuid;
  bkA uuid; bkB uuid;
  bkLive uuid; liLive uuid; bkTwo uuid;
  rowPaid jsonb; rowKept jsonb; v jsonb;
  ids uuid[]; one uuid[];
  payout uuid; v_paid_at timestamptz;
  v_bad text := ''; v_msg text; v_src text; v_oid oid; f text;
  v_n int; v_state text; v_life bigint; v_life2 bigint; v_unp bigint; v_unp2 bigint; v_net int;
  rD uuid; rE uuid; oD uuid; oE uuid; dD uuid; dE uuid; rtD uuid; rtE uuid;
  bkD uuid; bkE uuid; payD uuid; payE uuid; netD int; netE int;
begin
  perform set_config('request.jwt.claim.sub', '', true);
  ops1 := t_user('rpr_ops', 'owner');
  insert into ops_recipients (profile_id, event_class, active) values (ops1, 'payout_due', true);

  -- ---------- [0192-R1] the payment marker rides the runner's own read ----------
  -- Before: both rows are 「settled, unpaid」. After paying exactly ONE of them, that row carries
  -- the payout id and the payout's own `paid_at` BY VALUE, and the sibling carries neither.
  v_bad := '';
  select w.o, w.r, w.d, w.rt into o, r, d, rt from t_rpr_world('r1', 2) w;
  select id into bkA from bookings where runner_id = r order by created_at, id limit 1;
  select id into bkB from bookings where runner_id = r order by created_at desc, id desc limit 1;
  if bkA is null or bkB is null or bkA = bkB then v_bad := v_bad || ' fixture: expected two distinct bookings'; end if;

  rowPaid := t_rpr_row(r, bkA);
  rowKept := t_rpr_row(r, bkB);
  if rowPaid is null or rowKept is null then v_bad := v_bad || ' fixture: a row is not visible to its own runner';
  else
    -- the UNPAID shape, asserted before anything is paid — otherwise the「after」arm cannot say
    -- whether the payment caused the change or the fixture already looked like this (175 V2's law)
    if (rowPaid->>'paid_payout_id') is not null then v_bad := v_bad || ' pre: row A already marked'; end if;
    if (rowPaid->>'paid_at')        is not null then v_bad := v_bad || ' pre: row A already has paid_at'; end if;
    if (rowPaid->>'settled')::boolean is distinct from true then v_bad := v_bad || ' pre: a settled row reads settled=' || coalesce(rowPaid->>'settled', 'NULL'); end if;
    if (rowKept->>'settled')::boolean is distinct from true then v_bad := v_bad || ' pre: sibling reads settled=' || coalesce(rowKept->>'settled', 'NULL'); end if;
  end if;

  select array_agg(id) into one from ledger_items where booking_id = bkA;
  if coalesce(array_length(one, 1), 0) is distinct from 1 then v_bad := v_bad || ' fixture: booking A carries ' || coalesce(array_length(one, 1), 0) || ' ledger rows (expected 1)'; end if;
  perform set_config('request.jwt.claim.sub', ops1::text, true);
  v := t_rpr_pay(r, one, t_rpr_net(one));
  perform set_config('request.jwt.claim.sub', '', true);
  if v->>'raised' is not null then v_bad := v_bad || ' pay raised=' || (v->>'raised');
  else
    payout := (v->>'payout')::uuid;
    select paid_at into v_paid_at from payouts where id = payout;
    if v_paid_at is null then v_bad := v_bad || ' the payout row has no paid_at — the fixture cannot test the date'; end if;

    rowPaid := t_rpr_row(r, bkA);
    rowKept := t_rpr_row(r, bkB);
    if rowPaid is null then v_bad := v_bad || ' post: the paid row vanished from the runner''s read';
    else
      if (rowPaid->>'paid_payout_id')::uuid is distinct from payout
        then v_bad := v_bad || ' post: paid_payout_id=' || coalesce(rowPaid->>'paid_payout_id', 'NULL') || ' (expected the payout just written)'; end if;
      -- BY VALUE against the payouts row, not merely non-null: a `now()` planted anywhere in the
      -- read would satisfy 「has a date」 while printing a date that is not the payment's
      if (rowPaid->>'paid_at')::timestamptz is distinct from v_paid_at
        then v_bad := v_bad || ' post: paid_at=' || coalesce(rowPaid->>'paid_at', 'NULL') || ' (expected the payout row''s own ' || coalesce(v_paid_at::text, 'NULL') || ')'; end if;
      if (rowPaid->>'settled')::boolean is distinct from true
        then v_bad := v_bad || ' post: paying a row made it read unsettled'; end if;
    end if;
    -- THE CONTROL: a read that turned everything non-null would pass every arm above
    if rowKept is null then v_bad := v_bad || ' post: the unpaid sibling vanished';
    else
      if (rowKept->>'paid_payout_id') is not null
        then v_bad := v_bad || ' 🔴 post: the UNPAID sibling is marked paid (' || (rowKept->>'paid_payout_id') || ') — the marker is not per-row'; end if;
      if (rowKept->>'paid_at') is not null
        then v_bad := v_bad || ' 🔴 post: the UNPAID sibling carries a payment date'; end if;
    end if;
  end if;
  if v_bad = '' then call _pass('rpr','0192-R1 지급 표식이 러너 자신의 읽기에 실려 온다: 정산됐고 미지급인 행은 paid_payout_id·paid_at이 NULL이고 settled=true, 그중 한 행만 실제 ops_record_manual_payout으로 지급하면 그 행이 payout id와 **그 payouts 행의 paid_at을 값으로** 들고 오며 settled는 그대로 true다. 지급하지 않은 형제 행은 두 칸 모두 NULL로 남는다 — 이 대조가 없으면 「표식이 지급을 따라왔다」와 「전부 non-null이 됐다」를 구별할 수 없다');
  else v_msg := v_bad; call _fail('rpr','0192-R1 the paid marker on the runner read', v_msg); end if;

  -- ---------- [0192-R2] `settled` is a THIRD state, and the reader agrees with the writer ----------
  v_bad := '';
  select w.o, w.r, w.d, w.rt into o, r, d, rt from t_rpr_world('r2', 0) w;
  select b.bk, b.li into bkLive, liLive from t_rpr_live_item(o, r, d, rt) b;

  v := t_rpr_row(r, bkLive);
  if v is null then v_bad := v_bad || ' the live-run row is not visible to its runner at all';
  else
    if (v->>'settled')::boolean is distinct from false
      then v_bad := v_bad || ' a row whose run is still open reads settled=' || coalesce(v->>'settled', 'NULL') || ' (expected false — its amount can still move)'; end if;
    if (v->>'paid_payout_id') is not null then v_bad := v_bad || ' the live row is marked paid'; end if;
  end if;

  -- ⓐ the WRITER refuses the same row by name. The reader's `settled=false` and the writer's
  --   `not_settled` are one world seen from two ends; if they ever disagree, the screen promises
  --   money the server will not pay.
  perform set_config('request.jwt.claim.sub', ops1::text, true);
  v := t_rpr_pay(r, array[liLive], t_rpr_net(array[liLive]));
  perform set_config('request.jwt.claim.sub', '', true);
  if v->>'raised' is distinct from 'not_settled'
    then v_bad := v_bad || ' the writer answered ' || coalesce(v->>'raised', 'ACCEPTED') || ' on the row the reader calls unsettled'; end if;

  -- and the DELTA this pin causes: end the run, read the SAME row again
  update runs set ended_at = now() where booking_id = bkLive;
  v := t_rpr_row(r, bkLive);
  if v is null then v_bad := v_bad || ' the row vanished when its run ended';
  elsif (v->>'settled')::boolean is distinct from true
    then v_bad := v_bad || ' ending the run left the row at settled=' || coalesce(v->>'settled', 'NULL'); end if;

  -- ⓑ 🔴 THE ARM THAT SEPARATES `not exists` FROM A READING OF THE `left join runs r`, and it is
  --   NOT the one drafted first. 「a booking may carry several runs」 cannot be tested at all —
  --   `runs.booking_id` is UNIQUE (0001:236) and the insert is refused, which is how the wrong
  --   justification was caught. The reachable difference is the row with NO run: a cancellation
  --   compensation (0080/0085 write `ledger_items` with no `runs` row) contributes nothing to the
  --   LEFT JOIN, so `r.ended_at is null` reads TRUE and the join form would call it 「a run is
  --   still open」 — hiding 「지급 대기」 from money we owe, forever, because no run will ever
  --   arrive to close it. The control is the arm directly above: the SAME fixture with its run
  --   present and ended also reads settled=true, so this pin is not satisfied by a `settled` that
  --   is hard-wired true — R2's live arms are where that dies.
  select b.bk, b.li into bkTwo, liLive from t_rpr_live_item(o, r, d, rt) b;
  update runs set ended_at = now() where booking_id = bkTwo;
  v := t_rpr_row(r, bkTwo);
  if v is null or (v->>'settled')::boolean is distinct from true
    then v_bad := v_bad || ' fixture: the ended-run control does not read settled=true'; end if;
  delete from runs where booking_id = bkTwo;                    -- now it is a cancel-comp shape
  v := t_rpr_row(r, bkTwo);
  if v is null then v_bad := v_bad || ' the no-run (cancellation compensation) row vanished';
  else
    if (v->>'settled')::boolean is distinct from true
      then v_bad := v_bad || ' 🔴 a ledger row with NO run (취소 보상) reads settled=' || coalesce(v->>'settled', 'NULL') || ' — `settled` is reading the left-joined run instead of proving absence, and this row can never become settled'; end if;
    -- the same row IS payable to the writer: reader and writer must agree about this world too
    perform set_config('request.jwt.claim.sub', ops1::text, true);
    v := t_rpr_pay(r, array[liLive], t_rpr_net(array[liLive]));
    perform set_config('request.jwt.claim.sub', '', true);
    if v->>'raised' is not null
      then v_bad := v_bad || ' the writer refused the cancellation-compensation row with ' || (v->>'raised') || ' — the reader calls it settled'; end if;
  end if;

  if v_bad = '' then call _pass('rpr','0192-R2 settled는 세 번째 상태다(미지급의 다른 이름이 아니다): 끝나지 않은 run이 달린 행은 settled=false로 읽히고, ⓐ 같은 행을 ops_record_manual_payout에 넣으면 not_settled로 이름을 대며 거절된다(읽는 쪽과 쓰는 쪽이 같은 세계를 본다), run을 끝내면 **같은 행**이 true로 바뀐다(이 핀이 만든 델타이지 발견한 상태가 아니다), ⓑ 첫 run이 끝난 예약에 두 번째 열린 run을 더하면 다시 false — 이 팔이 not exists(runs rn)와 기존 left join r 읽기를 구별한다');
  else v_msg := v_bad; call _fail('rpr','0192-R2 settled is a third state', v_msg); end if;

  -- ---------- [0192-R3] two totals, two sentences — measured as a delta across one payment ----------
  v_bad := '';
  select w.o, w.r, w.d, w.rt into o, r, d, rt from t_rpr_world('r3', 2) w;
  perform set_config('request.jwt.claim.sub', r::text, true);
  select my_ledger_total() into v_life;
  select my_ledger_unpaid_total() into v_unp;
  perform set_config('request.jwt.claim.sub', '', true);
  if v_life is distinct from v_unp
    then v_bad := v_bad || ' pre: nothing is paid yet and the two totals already differ (' || coalesce(v_life::text,'NULL') || ' vs ' || coalesce(v_unp::text,'NULL') || ')'; end if;
  if coalesce(v_life, 0) <= 0 then v_bad := v_bad || ' fixture: the runner earned nothing, so no delta is observable'; end if;

  ids := t_rpr_unpaid(r);
  if coalesce(array_length(ids, 1), 0) is distinct from 2 then v_bad := v_bad || ' fixture: unpaid rows=' || coalesce(array_length(ids, 1), 0) || ' (expected 2)'; end if;
  one := array[ids[1]];
  v_net := t_rpr_net(one);
  perform set_config('request.jwt.claim.sub', ops1::text, true);
  v := t_rpr_pay(r, one, v_net);
  perform set_config('request.jwt.claim.sub', '', true);
  if v->>'raised' is not null then v_bad := v_bad || ' pay raised=' || (v->>'raised');
  else
    perform set_config('request.jwt.claim.sub', r::text, true);
    select my_ledger_total() into v_life2;
    select my_ledger_unpaid_total() into v_unp2;
    perform set_config('request.jwt.claim.sub', '', true);
    -- the unpaid total falls by EXACTLY that row's net …
    if v_unp2 is distinct from v_unp - v_net
      then v_bad := v_bad || ' unpaid total ' || coalesce(v_unp::text,'NULL') || ' → ' || coalesce(v_unp2::text,'NULL') || ' (expected a fall of exactly ' || coalesce(v_net::text,'NULL') || ')'; end if;
    -- … and the LIFETIME total does not move. THE CONTROL: a §B written by narrowing 0027/0121
    -- instead of beside it passes the arm above and fails this one.
    if v_life2 is distinct from v_life
      then v_bad := v_bad || ' 🔴 my_ledger_total moved ' || coalesce(v_life::text,'NULL') || ' → ' || coalesce(v_life2::text,'NULL') || ' — 0192 changed what 0027/0121 MEANS, and five shipped pins read that sentence'; end if;
    if v_unp2 >= v_life2
      then v_bad := v_bad || ' unpaid(' || coalesce(v_unp2::text,'NULL') || ') is not below lifetime(' || coalesce(v_life2::text,'NULL') || ') after a payment'; end if;
  end if;

  -- both refuse a NULL uid BY NAME (the 0121 §F / §A contract, restated on the new function)
  perform set_config('request.jwt.claim.sub', '', true);
  v_state := 'no-error';
  begin perform my_ledger_unpaid_total(); exception when others then v_state := sqlerrm; end;
  if v_state is distinct from 'not_authenticated' then v_bad := v_bad || ' unpaid_total with no uid: ' || v_state; end if;
  v_state := 'no-error';
  begin perform 1 from my_ledger_rows(); exception when others then v_state := sqlerrm; end;
  if v_state is distinct from 'not_authenticated' then v_bad := v_bad || ' my_ledger_rows with no uid: ' || v_state; end if;

  if v_bad = '' then call _pass('rpr','0192-R3 두 합계는 두 문장이다: 지급 전에는 평생 합계와 미지급 합계가 같고(0186 이전 세계), 실제 지급 한 번을 사이에 두고 미지급 합계는 **그 행의 순액만큼 정확히** 줄고 my_ledger_total은 **전혀 움직이지 않는다** — 후자가 대조군이다(§B를 0027/0121을 좁혀서 썼다면 앞 팔은 통과하고 이 팔에서 죽는다; 그 문장은 121·122·137·153·20이 읽고 있다). 둘 다 uid 없으면 not_authenticated로 이름을 댄다');
  else v_msg := v_bad; call _fail('rpr','0192-R3 two totals, two sentences', v_msg); end if;

  -- ---------- [0192-R4] 🔴 the cross-runner read, executed AS `authenticated` ----------
  -- The suite runs as the table OWNER, for whom RLS does not apply — so every arm below is
  -- worthless unless the role actually switches, which is why `current_user` is asserted first
  -- (144's ZZ001 idiom): a SET ROLE that silently failed would read as a clean pass.
  begin
    v_bad := '';
    select w.o, w.r, w.d, w.rt into oD, rD, dD, rtD from t_rpr_world('r4d', 1) w;
    select w.o, w.r, w.d, w.rt into oE, rE, dE, rtE from t_rpr_world('r4e', 1) w;
    select id into bkD from bookings where runner_id = rD limit 1;
    select id into bkE from bookings where runner_id = rE limit 1;
    -- the two payouts must DIFFER in amount: a fixture where they agree cannot distinguish
    -- 「I read my row」 from 「I read theirs」
    perform set_config('request.jwt.claim.sub', ops1::text, true);
    netD := t_rpr_net(t_rpr_unpaid(rD));
    netE := t_rpr_net(t_rpr_unpaid(rE));
    v := t_rpr_pay(rD, t_rpr_unpaid(rD), netD);
    payD := (v->>'payout')::uuid;
    if v->>'raised' is not null then v_bad := v_bad || ' D pay raised=' || (v->>'raised'); end if;
    -- E's payout is made deliberately different by tipping one of E's rows before paying it
    update ledger_items set tip = tip + 3000 where runner_id = rE;
    netE := t_rpr_net(t_rpr_unpaid(rE));
    v := t_rpr_pay(rE, t_rpr_unpaid(rE), netE);
    payE := (v->>'payout')::uuid;
    if v->>'raised' is not null then v_bad := v_bad || ' E pay raised=' || (v->>'raised'); end if;
    perform set_config('request.jwt.claim.sub', '', true);
    if netD is not distinct from netE then v_bad := v_bad || ' fixture: the two payouts are the same amount (' || coalesce(netD::text,'NULL') || ') — this pin could not tell the rows apart'; end if;
    if payD is null or payE is null then v_bad := v_bad || ' fixture: a payout was not written'; end if;

    perform set_config('request.jwt.claim.sub', rD::text, true);
    execute 'set local role authenticated';
    if current_user <> 'authenticated' then v_bad := v_bad || ' SET ROLE did not take (current_user=' || current_user || ')'; end if;

    -- ROWS: only mine, and the other runner's row is not merely filtered from a count — it is
    -- unreachable BY ITS OWN ID, which is the read an attacker actually has
    select count(*) into v_n from payouts where runner_id = rE;
    if v_n is distinct from 0 then v_bad := v_bad || ' 🔴 the other runner''s payout rows are VISIBLE (' || v_n || ')'; end if;
    select count(*) into v_n from payouts where id = payE;
    if v_n is distinct from 0 then v_bad := v_bad || ' 🔴 the other runner''s payout is readable by id'; end if;
    select count(*) into v_n from payouts where id = payD;
    if v_n is distinct from 1 then v_bad := v_bad || ' my own payout is not readable (' || v_n || ') — a seal that shut the front door'; end if;
    select net into v_n from payouts where id = payD;
    if v_n is distinct from netD then v_bad := v_bad || ' my payout net=' || coalesce(v_n::text,'NULL') || ' (expected ' || coalesce(netD::text,'NULL') || ')'; end if;

    -- COLUMNS: 0186:192-195's seal. The runner surface is a TABLE grant (0192 §0 ① declines to add
    -- a second definer on exactly this strength), so the seal is this pin's to hold.
    foreach f in array array['memo', 'method', 'recorded_by'] loop
      v_state := 'no-error';
      begin execute format('select %I from payouts limit 1', f);
      exception when others then v_state := sqlstate; end;
      if v_state is distinct from '42501'
        then v_bad := v_bad || ' 🔴 ops column `' || f || '` is readable by a runner (sqlstate=' || v_state || ')'; end if;
    end loop;

    -- and the LEDGER read answers the caller, never the other runner
    select count(*) into v_n from my_ledger_rows() x where x.booking_id = bkE;
    if v_n is distinct from 0 then v_bad := v_bad || ' 🔴 my_ledger_rows returned the other runner''s booking'; end if;
    select count(*) into v_n from my_ledger_rows() x where x.booking_id = bkD;
    if v_n is distinct from 1 then v_bad := v_bad || ' my own ledger row is missing from my own read (' || v_n || ')'; end if;
    select count(*) into v_n from my_ledger_rows() x where x.paid_payout_id = payE;
    if v_n is distinct from 0 then v_bad := v_bad || ' 🔴 the other runner''s payout id appears on my ledger read'; end if;

    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '', true);
    if v_bad = '' then call _pass('rpr','0192-R4 남의 지급 내역은 러너에게 보이지 않는다 — authenticated 롤로 실제 실행(SET ROLE이 먹었는지 current_user로 먼저 확인): 상대 러너의 payouts 행은 runner_id로도, **행 id를 직접 대도** 0행이고 내 행은 금액까지 정확히 읽힌다(앞문까지 닫은 봉인이 아니다 — 두 지급액은 일부러 다르게 만들어 「내 행」과 「남의 행」이 구별된다); 0186:192-195가 봉인한 ops 칸 memo·method·recorded_by는 세 개 모두 42501로 거절된다(0192가 my_payouts() 디파이너를 더하지 않기로 한 근거가 바로 이 테이블 그랜트이므로 이 핀이 그 봉인을 진다); my_ledger_rows도 호출자의 행만 답하고 남의 booking도 남의 payout id도 실려 오지 않는다');
    else v_msg := v_bad; call _fail('rpr','0192-R4 cross-runner payout read', v_msg); end if;
  exception when others then execute 'reset role'; perform set_config('request.jwt.claim.sub', '', true);
    call _fail('rpr','0192-R4 cross-runner payout read', sqlerrm); end;

  -- ---------- [0192-S1] deployed shape — the preconditions no behavioural arm can see ----------
  v_bad := '';
  foreach f in array array['my_ledger_rows', 'my_ledger_unpaid_total'] loop
    select p.oid into v_oid from pg_proc p
     where p.proname = f and p.pronamespace = 'public'::regnamespace;
    -- absence must be LOUD: every arm below is vacuously true on a function that is not there
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(' || f || ')'; continue; end if;
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' NOT-DEFINER(' || f || ')'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH(' || f || ')'; end if;
    -- ⚠ the NULL-ACL arm FIRST and positively: a function that was never granted carries
    --   `proacl IS NULL` = owner + PUBLIC, and aclexplode(NULL) returns ZERO rows, so an `exists`
    --   test alone is silent on precisely the state 0116:636 calls this repo's worst shape — and
    --   §A is a `drop` + `create`, which is exactly how a function reaches it.
    if (select proacl from pg_proc where oid = v_oid) is null
      then v_bad := v_bad || ' DEFAULT-PUBLIC-ACL(' || f || ')';
    elsif exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                   where p.oid = v_oid and (a.grantee = 0 or a.grantee = 'anon'::regrole))
      then v_bad := v_bad || ' PUBLIC-OR-ANON(' || f || ')'; end if;
    -- the positive half — a seal that also shut the front door passes every negative sweep and
    -- ships an outage (189 0158-B5's own warning)
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' AUTHENTICATED-CANNOT(' || f || ')'; end if;
  end loop;

  -- the three columns exist BY NAME on the return record
  select count(*) into v_n from unnest(
      (select proargnames from pg_proc
        where proname = 'my_ledger_rows' and pronamespace = 'public'::regnamespace)) n
   where n in ('paid_payout_id', 'paid_at', 'settled');
  if v_n is distinct from 3
    then v_bad := v_bad || ' LEDGER-ROWS-PAYMENT-COLUMNS=' || coalesce(v_n::text, 'NULL') || ' (expected 3)'; end if;

  -- ⚠ COMMENTS STRIPPED BEFORE EVERY MATCH. `prosrc` is source plus our own prose, and 0192 §A
  --   documents `paid_payout_id`, `settled` and the distance decision in comments directly beside
  --   the code that implements them — un-stripped, the better the explanation the more certainly
  --   these arms pass.
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where proname = 'my_ledger_rows' and pronamespace = 'public'::regnamespace;
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(my_ledger_rows)';
  else
    -- 0158's finding #9 is not this slice's to move, and a transcription that reverted it would
    -- look exactly like a clean widening
    if (v_src ~ 'r\.actual_km')      is distinct from true  then v_bad := v_bad || ' LEDGER-NOT-ACTUAL'; end if;
    if (v_src ~ 'b\.km')             is distinct from false then v_bad := v_bad || ' LEDGER-STILL-PLANNED'; end if;
    -- `settled` as a proof of ABSENCE, so a NULL from any cause refuses instead of promising
    if (v_src ~ 'not exists\s*\(\s*select 1 from runs rn') is distinct from true
      then v_bad := v_bad || ' SETTLED-NOT-AN-ABSENCE-PROOF'; end if;
    if (v_src ~ 'l\.paid_payout_id') is distinct from true then v_bad := v_bad || ' NO-MARKER-IN-THE-READ'; end if;
  end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where proname = 'my_ledger_unpaid_total' and pronamespace = 'public'::regnamespace;
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(my_ledger_unpaid_total)';
  elsif (v_src ~ 'paid_payout_id is null') is distinct from true
    then v_bad := v_bad || ' UNPAID-TOTAL-DOES-NOT-NARROW'; end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where proname = 'my_ledger_total' and pronamespace = 'public'::regnamespace;
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(my_ledger_total)';
  elsif (v_src ~ 'paid_payout_id') is distinct from false
    then v_bad := v_bad || ' LIFETIME-TOTAL-WAS-NARROWED'; end if;

  if v_bad = '' then call _pass('rpr','0192-S1 배포 형상: 두 함수 모두 definer · 본문 search_path · ACL을 **값으로** 양방향 확인(NULL-ACL 팔이 먼저 — §A는 drop+create라 PUBLIC으로 태어날 수 있는 바로 그 경로이고, aclexplode(NULL)은 0행이라 exists만으로는 그 상태에 침묵한다) · authenticated는 여전히 부를 수 있다 · 새 세 칸이 이름으로 존재한다 · **주석을 벗긴** prosrc로: 0158의 r.actual_km는 남아 있고 b.km는 없으며, settled는 not exists 부재 증명으로 쓰였고, 표식이 실제로 읽히며, 미지급 합계는 좁히고 my_ledger_total은 좁히지 않았다 · NO-FUNCTION/NO-SOURCE 팔');
  else v_msg := v_bad; call _fail('rpr','0192-S1 deployed shape', v_msg); end if;
end $$;
