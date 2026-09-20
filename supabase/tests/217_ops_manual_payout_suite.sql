-- ═══ 217 — 0186: the ops manual payout journal — 0186-P1…P6 · S1, tag `mpj` ═══════════════════
--
-- THE PROPOSITIONS THIS FILE OWNS:
--   · P1 the OPS PARTY GATE comes before everything. No caller ⇒ `not_signed_in`; a signed-in
--     non-ops caller ⇒ `not_ops` from BOTH functions — including when the same call also carries a
--     foreign runner, unknown ids and a wrong amount, which is the 「party gate before state gate」
--     law made observable: the refusal must be `not_ops`, never the state refusal underneath it.
--     An INACTIVE row and an ACTIVE row for a DIFFERENT class are both `not_ops`. Nothing written.
--   · P2 the read's VALUES: per-runner unpaid net (the 0121 expression), item count and oldest, a
--     fully-paid runner absent, a zero-net runner absent, a row whose booking still has a LIVE run
--     excluded from both the population and the total, oldest-first ordering.
--   · P3 the amount is an EQUALITY: +1 and −1 both ⇒ `amount_mismatch` with nothing written; the
--     exact sum writes `net = gross − platform_fee` and `tax_withheld = 0`.
--   · P4 every refusal by NAME, each writing nothing: `not_runner_item` (a foreign runner's row;
--     an id that does not exist), `already_paid`, `not_settled`, `no_items` (empty AND null),
--     `bad_amount` (0 and negative), `no_runner`.
--   · P5 the happy path and IDEMPOTENCY: exactly one `payouts` row with the recorded facts,
--     exactly the named ledger rows marked and the runner's other row untouched; the second
--     identical call ⇒ `already_paid` with the payout count still 1; a mixed paid/unpaid batch ⇒
--     `already_paid`, nothing written; a duplicated id is one row, not two.
--   · P6 the sweep: a runner unpaid past 7 days ⇒ one notification per ACTIVE recipient of
--     `payout_due`, `system` kind, `ref_id` = the runner, a body with no digit and no id; the
--     immediate second call writes nothing (the 20-hour window); 6 days, fully paid, zero-net and
--     live-run runners are never notified; past the window it notifies again.
--   · S1 deployed shape: three definers (prosecdef · in-body search_path · ACL by value), the four
--     columns, `recorded_by` deliberately WITHOUT an FK, the `payouts` column seal in both
--     directions, the ledger column not client-readable, the cron row read back from `cron.job`,
--     and the source order gate→lock→state→write with a NO-SOURCE arm.
--
-- ─── MUTATION MAP — measured 2026-09-21 against these exact files, not predicted ───
--   Lab: a copy of `supabase/` OUTSIDE the worktree (`/tmp/dr-0186-lab-…`, suite md5-identical to
--   the committed one), every plant restored-from-pristine then asserted to have landed
--   (`assert s.count(old)==1`) and `&&`-CHAINED to its harness run, so a failed plant yields NO
--   row rather than a green one. Control observed clean FIRST: **1314 / 0**. 「demoted」 = 0186's
--   VERIFY raise turned into a notice, so the SUITE is what is measured; 「un-demoted」 = the
--   shipped file, where VERIFY aborts the apply before any suite runs. The whole set was re-run
--   after the LAST edit (the S1 repair and the 10-hour arm), not after the last interesting one.
--
--   (i)    the ops gate deleted from the WRITER      → 1308/6: P1 + P2 + P3 + P4 + P5 + S1. The
--          cascade is real and not noise — with the gate gone, P1's non-ops calls SUCCEED and
--          write payouts and marks, which is exactly the damage, and the later arms see it.
--   (ii)   the ops gate deleted from the READ        → 1312/2: P1 + S1
--   (iii)  the amount equality becomes ±1 tolerance  → 1312/2: P3 + S1
--   (iv)   the `already_paid` gate deleted           → 1311/3: P4 + P5 (the second identical call
--          writes a SECOND payout — the double payment this function exists to refuse) + S1
--   (v)    the `not_settled` gate deleted            → 1311/3: P4 + P6 + S1
--   (vi)   the settled predicate deleted from the READ → 1311/3: P1 + P2 + S1
--   (vii)  the row lock deleted (`for update` dropped) → 1313/1: **S1 ALONE, and that is a NAMED
--          GAP rather than a pass.** A lock's absence is invisible to every single-session pin —
--          the reader is the writer, so the refusals still fire in order. Two operators racing is
--          what the lock is for and this suite has one connection; the property is pinned by TEXT
--          only. Whoever next touches this function should add a `90_race_check.sh` arm.
--   (viii) the sweep's dedupe guard replaced by `where true` → 1312/2: P6 + S1.
--          ⚠ S1 was GREEN here on the first measurement, and that is the finding this battery
--          bought: the arm matched the `interval '20 hours'` LITERAL, which the plant left
--          declared while deleting its only use. Repaired to match the CONSUMPTION
--          (`created_at > now() - DEDUPE_WINDOW` inside a `not exists`), then re-measured.
--   (ix)   `STUCK_AFTER` 7 days → 1 day             → 1312/2: P6 (the 6-day runner fires) + S1
--   (x)    the cron registration deleted             → 1313/1: S1 (the `cron.job` arm);
--          **un-demoted the apply ABORTS** — `0186 VERIFY FAILED: CRON(ops-payouts-stuck)=0`
--   (xi)   the `payouts` column seal deleted         → 1313/1: S1;
--          **un-demoted the apply ABORTS** — `0186 VERIFY FAILED: payouts:OPS-COLUMNS-READABLE`
--   (xii)  `tax_withheld` computed as 3.3% of gross  → 1313/1: P3 (§0e — a number nobody withheld)
--   (xiii) the marking narrowed to the first id only → 1313/1: P5 (a payout whose batch is half
--          unmarked is a double payment waiting to be made)
--   (xiv)  the dedupe window shrunk to 1 second, the `not exists` guard KEPT → 1312/2: P6 + S1.
--          Written as an INDEPENDENT attack on the sentence (viii) exposed, rather than re-running
--          the mutation the repair was written against. ⚠ On its first measurement it reddened S1
--          ALONE: `now()` is frozen inside this transaction, so 「immediately again」 and 「21 hours
--          later」 agree for every window between one second and twenty hours — P6's fixture sat
--          in the two rules' AGREEMENT zone. The 10-hour arm (fixture note ⑦) puts it where they
--          disagree, and P6 now sees it.
--
-- ─── FIXTURE NOTES ───
--  ① `t_mpj_call` / `t_mpj_due` wrap the RPCs so a raise becomes {raised: <name>} instead of
--     aborting the whole block (the 0179 #14 class). The inner subtransaction ROLLS BACK on a
--     raise, which is exactly the 「nothing written」 property the refusal pins then measure.
--  ② `request.jwt.claim.sub` is the only identity: both ops functions read `auth.uid()`. It is
--     cleared at the top and set per-arm; a leftover claim would silently pass every gate.
--  ③ A 「settled」 fixture is a booking whose `runs` row has `ended_at`; a 「live」 one leaves it
--     NULL. That is the §0d ⓒ predicate's only input, and `t_mpj_bk`'s boolean is the whole
--     difference between the two worlds the read and the writer must separate.
--  ④ `now()` is constant inside this block (one transaction), so ages are written as explicit
--     `created_at = now() - <interval>` and the dedupe window is moved by rewriting `created_at`
--     backwards — never by waiting.
--  ⑤ The ops roster is TWO active recipients on purpose: a per-runner-per-day pin that cannot tell
--     「one notification」 from 「one recipient」 would be measuring the fixture.
--  ⑦ NAMED GAP, measured rather than assumed: `now()` is frozen inside this transaction, so the
--     sweep's dedupe can only be exercised by rewriting `created_at`. The 10-hour arm is what
--     makes the WINDOW'S VALUE observable — 「immediately again」 and 「21 hours later」 agree for
--     any window between one second and twenty hours (battery plant xiv). The exact 20 hours is
--     owned by S1's source arms; P6 owns 「a notification 10 hours old still suppresses and one
--     21 hours old does not」, which is the product sentence.
--  ⑥ EVERY count is scoped to this suite's five runners. `payouts` and `ledger_items` are shared
--     with every other suite in the same database (150's fixtures write `payouts`; a dozen suites
--     write `ledger_items`), so a global `count(*)` would measure the harness, not this slice —
--     measured: the first draft read 68 due runners and 1 pre-existing payout. A scoped count
--     stays true the day someone adds a fixture three suites away.
set client_min_messages = warning;

-- ① the wrappers
create or replace function t_mpj_call(p_runner uuid, p_ids uuid[], p_amount int, p_memo text)
returns jsonb language plpgsql as $$
declare v uuid;
begin
  begin
    v := ops_record_manual_payout(p_runner, p_ids, p_amount, p_memo);
    return jsonb_build_object('payout', v);
  exception when others then
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

create or replace function t_mpj_due() returns jsonb language plpgsql as $$
declare v jsonb;
begin
  begin
    select coalesce(jsonb_agg(to_jsonb(d) order by d.oldest_unpaid_at, d.runner_profile_id),
                    '[]'::jsonb)
      into v from ops_payouts_due() d;
    return jsonb_build_object('rows', v);
  exception when others then
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- ③ a booking with a run, ended or still live
create or replace function t_mpj_bk(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                    p_live boolean)
returns uuid language plpgsql as $$
declare v uuid;
begin
  v := t_active_booking(p_owner, p_runner, p_dog, p_route);
  if p_live is not true then update runs set ended_at = now() where booking_id = v; end if;
  return v;
end $$;

-- one ledger row: net = p_gross − p_fee, aged by p_age
create or replace function t_mpj_item(p_runner uuid, p_booking uuid, p_gross int, p_fee int,
                                      p_age interval)
returns uuid language sql as $$
  insert into ledger_items (runner_id, booking_id, base, distance_pay, addon_pay, tip,
                            remaining_guarantee, platform_fee, created_at)
  values (p_runner, p_booking, p_gross, 0, 0, 0, 0, p_fee, now() - p_age)
  returning id
$$;

-- how many of these ids carry a paid marker
create or replace function t_mpj_marked(p_ids uuid[]) returns int language sql as $$
  select count(*)::int from ledger_items where id = any(p_ids) and paid_payout_id is not null
$$;

do $$
declare
  ops1 uuid; ops2 uuid; opsx uuid; opsoff uuid; outsider uuid;
  o uuid; rA uuid; rB uuid; rC uuid; rD uuid; rE uuid;
  dA uuid; dB uuid; dC uuid; dD uuid; dE uuid; rt uuid;
  bkA1 uuid; bkA2 uuid; bkA3 uuid; bkB uuid; bkC uuid; bkD uuid; bkE uuid; bkElive uuid;
  liA1 uuid; liA2 uuid; liA3 uuid; liB uuid; liC uuid; liD uuid; liE uuid; liElive uuid;
  v jsonb; vd jsonb; row0 jsonb; p record; nrec record;
  v_bad text := ''; v_msg text; v_src text; v_oid oid;
  v_n int; v_n0 int; v_pay uuid; v_pay2 uuid;
begin
  perform set_config('request.jwt.claim.sub', '', true);                                       -- ②

  ops1     := t_user('mpj_ops1',     'owner');
  ops2     := t_user('mpj_ops2',     'owner');
  opsx     := t_user('mpj_ops_other','owner');   -- active, but for a DIFFERENT event class
  opsoff   := t_user('mpj_ops_off',  'owner');   -- payout_due, but active = false
  outsider := t_user('mpj_outsider', 'owner');
  o  := t_user('mpj_owner',  'owner');
  rA := t_user('mpj_runnerA','runner'); rB := t_user('mpj_runnerB','runner');
  rC := t_user('mpj_runnerC','runner'); rD := t_user('mpj_runnerD','runner');
  rE := t_user('mpj_runnerE','runner');
  dA := t_dog(o,'mpj-A'); dB := t_dog(o,'mpj-B'); dC := t_dog(o,'mpj-C');
  dD := t_dog(o,'mpj-D'); dE := t_dog(o,'mpj-E');
  rt := t_route('mpj 코스');

  insert into ops_recipients (profile_id, event_class, active) values
    (ops1,   'payout_due',            true),                                                   -- ⑤
    (ops2,   'payout_due',            true),
    (opsoff, 'payout_due',            false),
    (opsx,   'charge_dispatch_stale', true);

  -- runner A — three settled unpaid rows, the oldest 9 days old. nets 9000 / 4000 / 1000.
  bkA1 := t_mpj_bk(o, rA, dA, rt, false); liA1 := t_mpj_item(rA, bkA1, 10000, 1000, interval '9 days');
  bkA2 := t_mpj_bk(o, rA, dA, rt, false); liA2 := t_mpj_item(rA, bkA2,  5000, 1000, interval '3 days');
  bkA3 := t_mpj_bk(o, rA, dA, rt, false); liA3 := t_mpj_item(rA, bkA3,  1200,  200, interval '1 day');
  -- runner B — one settled row, 8 days old, net 7000 (the batch that gets paid in P5)
  bkB  := t_mpj_bk(o, rB, dB, rt, false); liB  := t_mpj_item(rB, bkB,   8000, 1000, interval '8 days');
  -- runner C — one row on a booking whose run is STILL LIVE, 8 days old, net 5000
  bkC  := t_mpj_bk(o, rC, dC, rt, true);  liC  := t_mpj_item(rC, bkC,   6000, 1000, interval '8 days');
  -- runner D — one settled row whose net is exactly 0, 8 days old
  bkD  := t_mpj_bk(o, rD, dD, rt, false); liD  := t_mpj_item(rD, bkD,   3000, 3000, interval '8 days');
  -- runner E — one settled row 8 days old (net 2000) AND one live-run row (net 4000)
  bkE     := t_mpj_bk(o, rE, dE, rt, false); liE     := t_mpj_item(rE, bkE,    2500,  500, interval '8 days');
  bkElive := t_mpj_bk(o, rE, dE, rt, true);  liElive := t_mpj_item(rE, bkElive, 4500,  500, interval '8 days');

  -- ---------- [0186-P1] the ops party gate, ahead of every state gate ----------
  v_bad := '';
  -- ⑥ every count here is SCOPED to this suite's five runners. `payouts` and `ledger_items` are
  -- shared with every other suite in the same database, so a global count would measure the
  -- harness rather than this slice — and would read as a finding the day someone adds a fixture.
  select count(*)::int into v_n0 from payouts where runner_id = any(array[rA, rB, rC, rD, rE]);
  if v_n0 is distinct from 0 then v_bad := v_bad || ' fixture: this suite''s runners already have payouts (' || v_n0 || ')'; end if;

  -- no caller at all
  perform set_config('request.jwt.claim.sub', '', true);
  vd := t_mpj_due();
  if vd->>'raised' is distinct from 'not_signed_in' then v_bad := v_bad || ' due/no-caller: ' || coalesce(vd->>'raised', 'ACCEPTED'); end if;
  v := t_mpj_call(rA, array[liA1], 9000, 'x');
  if v->>'raised' is distinct from 'not_signed_in' then v_bad := v_bad || ' record/no-caller: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;

  -- a signed-in stranger, an inactive ops row, and an ops row for another class
  foreach v_msg in array array[outsider::text, opsoff::text, opsx::text, o::text, rA::text] loop
    perform set_config('request.jwt.claim.sub', v_msg, true);
    vd := t_mpj_due();
    if vd->>'raised' is distinct from 'not_ops' then v_bad := v_bad || ' due/non-ops(' || left(v_msg, 8) || '): ' || coalesce(vd->>'raised', 'ACCEPTED'); end if;
    v := t_mpj_call(rA, array[liA1], 9000, 'x');
    if v->>'raised' is distinct from 'not_ops' then v_bad := v_bad || ' record/non-ops(' || left(v_msg, 8) || '): ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  end loop;

  -- THE ORDER LAW: the same call carrying a foreign runner, an id that does not exist, a
  -- zero amount and a null runner must still answer `not_ops` — the party gate decides first.
  perform set_config('request.jwt.claim.sub', outsider::text, true);
  v := t_mpj_call(rB, array[liA1, gen_random_uuid()], 1, 'x');
  if v->>'raised' is distinct from 'not_ops' then v_bad := v_bad || ' order/foreign+unknown: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  v := t_mpj_call(null, '{}'::uuid[], 0, null);
  if v->>'raised' is distinct from 'not_ops' then v_bad := v_bad || ' order/empty+bad-amount+no-runner: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;

  -- the control: the gate CAN pass, for an active recipient of this class
  perform set_config('request.jwt.claim.sub', ops1::text, true);
  vd := t_mpj_due();
  if vd->>'raised' is not null then v_bad := v_bad || ' control/ops1-refused: ' || (vd->>'raised'); end if;
  select count(*)::int into v_n from jsonb_array_elements(vd->'rows') r
   where (r.value->>'runner_profile_id')::uuid = any(array[rA, rB, rC, rD, rE]);
  if v_n is distinct from 3 then v_bad := v_bad || ' control/ops1-rows=' || coalesce(v_n::text, 'NULL') || ' (expected 3 of this suite''s runners: A, B, E — not C (live run) and not D (zero net))'; end if;

  select count(*)::int into v_n from payouts where runner_id = any(array[rA, rB, rC, rD, rE]);
  if v_n is distinct from 0 then v_bad := v_bad || ' a-refusal-wrote-a-payout (' || v_n || ')'; end if;
  if t_mpj_marked(array[liA1, liA2, liA3, liB, liC, liD, liE, liElive]) is distinct from 0 then v_bad := v_bad || ' a-refusal-marked-a-ledger-row'; end if;

  if v_bad = '' then call _pass('mpj','0186-P1 ops 파티 게이트가 맨 앞: 호출자 없음 ⇒ not_signed_in; 로그인한 비-ops·비활성 수신자·다른 이벤트 클래스 수신자·보호자·러너 모두 두 함수에서 not_ops; 남의 러너 + 없는 id + 0원 + null 러너를 함께 실어도 답은 여전히 not_ops(상태 게이트가 아니라 파티 게이트가 먼저 결정한다); 활성 수신자는 통과한다(대조); 어떤 거절도 payouts 행도 원장 표시도 남기지 않는다');
  else v_msg := v_bad; call _fail('mpj','0186-P1 ops gate', v_msg); end if;

  -- ---------- [0186-P2] the read's values, not its shape ----------
  v_bad := '';
  perform set_config('request.jwt.claim.sub', ops1::text, true);
  vd := t_mpj_due();
  if vd->>'raised' is not null then v_bad := v_bad || ' raised=' || (vd->>'raised'); end if;
  select count(*)::int into v_n from jsonb_array_elements(vd->'rows') r
   where (r.value->>'runner_profile_id')::uuid = any(array[rA, rB, rC, rD, rE]);
  if v_n is distinct from 3 then v_bad := v_bad || ' rows=' || coalesce(v_n::text, 'NULL') || ' (expected exactly A, B, E among this suite''s runners)'; end if;

  -- runner A: 9000 + 4000 + 1000 = 14000 over 3 items, oldest 9 days back
  select r.value into row0 from jsonb_array_elements(vd->'rows') r where (r.value->>'runner_profile_id')::uuid = rA;
  if row0 is null then v_bad := v_bad || ' A: absent';
  else
    if (row0->>'unpaid_net_won')::bigint is distinct from 14000 then v_bad := v_bad || ' A:net=' || coalesce(row0->>'unpaid_net_won', 'NULL') || ' (expected 14000)'; end if;
    if (row0->>'unpaid_items')::int is distinct from 3 then v_bad := v_bad || ' A:items=' || coalesce(row0->>'unpaid_items', 'NULL'); end if;
    if (row0->>'oldest_unpaid_at')::timestamptz is distinct from now() - interval '9 days' then v_bad := v_bad || ' A:oldest=' || coalesce(row0->>'oldest_unpaid_at', 'NULL'); end if;
  end if;

  -- runner E: the LIVE-run row is excluded from the total as well as from the population
  select r.value into row0 from jsonb_array_elements(vd->'rows') r where (r.value->>'runner_profile_id')::uuid = rE;
  if row0 is null then v_bad := v_bad || ' E: absent';
  else
    if (row0->>'unpaid_net_won')::bigint is distinct from 2000 then v_bad := v_bad || ' E:net=' || coalesce(row0->>'unpaid_net_won', 'NULL') || ' (expected 2000 — the live-run row must not be summed)'; end if;
    if (row0->>'unpaid_items')::int is distinct from 1 then v_bad := v_bad || ' E:items=' || coalesce(row0->>'unpaid_items', 'NULL') || ' (expected 1)'; end if;
  end if;

  -- runner C (live run only) and runner D (net 0) are absent
  if exists (select 1 from jsonb_array_elements(vd->'rows') r where (r.value->>'runner_profile_id')::uuid = rC) then v_bad := v_bad || ' C: a live-run-only runner is listed as due'; end if;
  if exists (select 1 from jsonb_array_elements(vd->'rows') r where (r.value->>'runner_profile_id')::uuid = rD) then v_bad := v_bad || ' D: a zero-net runner is listed as due'; end if;

  -- oldest first: A (9d) before B (8d) before E (8d, later id order) before nothing
  select (r.value->>'runner_profile_id')::uuid into v_pay2
    from jsonb_array_elements(vd->'rows') with ordinality as r(value, n)
   where (r.value->>'runner_profile_id')::uuid = any(array[rA, rB, rC, rD, rE])
   order by r.n limit 1;
  if v_pay2 is distinct from rA then v_bad := v_bad || ' order: the first of this suite''s runners is not A (the oldest)'; end if;

  if v_bad = '' then call _pass('mpj','0186-P2 읽기의 값: 러너별 미지급 순액 = 0121의 식(base+distance+addon+tip+guarantee−platform_fee) 합, 건수, 가장 오래된 시각; 끝나지 않은 run이 달린 행은 모수에서도 합계에서도 빠진다(러너 E는 2000/1건); 살아 있는 run만 가진 러너와 순액 0인 러너는 아예 나오지 않는다; 오래된 순 정렬');
  else v_msg := v_bad; call _fail('mpj','0186-P2 due read', v_msg); end if;

  -- ---------- [0186-P3] the amount is an equality, never a tolerance ----------
  v_bad := '';
  perform set_config('request.jwt.claim.sub', ops1::text, true);
  v := t_mpj_call(rB, array[liB], 7001, 'off by one up');
  if v->>'raised' is distinct from 'amount_mismatch' then v_bad := v_bad || ' +1: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  v := t_mpj_call(rB, array[liB], 6999, 'off by one down');
  if v->>'raised' is distinct from 'amount_mismatch' then v_bad := v_bad || ' -1: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  -- the gross (pre-commission) figure must not be accepted in place of the net
  v := t_mpj_call(rB, array[liB], 8000, 'the gross, not the net');
  if v->>'raised' is distinct from 'amount_mismatch' then v_bad := v_bad || ' gross-as-net: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  select count(*)::int into v_n from payouts where runner_id = any(array[rA, rB, rC, rD, rE]);
  if v_n is distinct from 0 then v_bad := v_bad || ' a-mismatch-wrote-a-payout (' || v_n || ')'; end if;
  if t_mpj_marked(array[liB]) is distinct from 0 then v_bad := v_bad || ' a-mismatch-marked-the-row'; end if;

  -- the exact net: 8000 − 1000
  v := t_mpj_call(rB, array[liB], 7000, '  국민 123-456  ');
  if v->>'raised' is not null then v_bad := v_bad || ' exact: raised=' || (v->>'raised'); end if;
  v_pay := (v->>'payout')::uuid;
  if v_pay is null then v_bad := v_bad || ' exact: no payout id returned';
  else
    select * into p from payouts where id = v_pay;
    if p.net is distinct from 7000  then v_bad := v_bad || ' net=' || coalesce(p.net::text, 'NULL'); end if;
    if p.gross is distinct from 8000 then v_bad := v_bad || ' gross=' || coalesce(p.gross::text, 'NULL') || ' (expected the pre-commission earnings)'; end if;
    if p.tax_withheld is distinct from 0 then v_bad := v_bad || ' tax_withheld=' || coalesce(p.tax_withheld::text, 'NULL') || ' (0186 §0e: nothing was withheld, and a computed 3.3% would be a number nobody took)'; end if;
    if (p.gross - p.net) is distinct from 1000 then v_bad := v_bad || ' gross−net is not the platform fee'; end if;
    if p.memo is distinct from '국민 123-456' then v_bad := v_bad || ' memo=' || coalesce(p.memo, 'NULL') || ' (the memo is stored trimmed)'; end if;
  end if;
  if v_bad = '' then call _pass('mpj','0186-P3 금액은 동일성이다: +1원·−1원·순액 대신 총액 모두 amount_mismatch이고 payouts 행도 원장 표시도 남지 않는다; 정확히 맞으면 net=잠긴 행들의 순액, gross=수수료 전 수입, gross−net=platform_fee, tax_withheld=0(아무도 떼지 않았으므로 — 계산된 3.3%는 아무도 내지 않은 숫자다)');
  else v_msg := v_bad; call _fail('mpj','0186-P3 amount equality', v_msg); end if;

  -- ---------- [0186-P4] every refusal by name, and none of them writes ----------
  v_bad := '';
  perform set_config('request.jwt.claim.sub', ops2::text, true);
  select count(*)::int into v_n0 from payouts where runner_id = any(array[rA, rB, rC, rD, rE]);

  v := t_mpj_call(rA, array[liB], 7000, null);                       -- liB belongs to runner B
  if v->>'raised' is distinct from 'not_runner_item' then v_bad := v_bad || ' foreign-runner: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  v := t_mpj_call(rA, array[liA1, gen_random_uuid()], 9000, null);   -- an id that does not exist
  if v->>'raised' is distinct from 'not_runner_item' then v_bad := v_bad || ' unknown-id: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  v := t_mpj_call(rB, array[liB], 7000, null);                       -- already paid by P3
  if v->>'raised' is distinct from 'already_paid' then v_bad := v_bad || ' already-paid: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  v := t_mpj_call(rC, array[liC], 5000, null);                       -- the booking's run is live
  if v->>'raised' is distinct from 'not_settled' then v_bad := v_bad || ' live-run: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  v := t_mpj_call(rE, array[liE, liElive], 6000, null);               -- one settled + one live
  if v->>'raised' is distinct from 'not_settled' then v_bad := v_bad || ' mixed-live: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  v := t_mpj_call(rA, '{}'::uuid[], 9000, null);
  if v->>'raised' is distinct from 'no_items' then v_bad := v_bad || ' empty-array: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  v := t_mpj_call(rA, null, 9000, null);
  if v->>'raised' is distinct from 'no_items' then v_bad := v_bad || ' null-array: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  v := t_mpj_call(rA, array[liA1], 0, null);
  if v->>'raised' is distinct from 'bad_amount' then v_bad := v_bad || ' zero-amount: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  v := t_mpj_call(rA, array[liA1], -9000, null);
  if v->>'raised' is distinct from 'bad_amount' then v_bad := v_bad || ' negative-amount: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  v := t_mpj_call(rA, array[liA1], null, null);
  if v->>'raised' is distinct from 'bad_amount' then v_bad := v_bad || ' null-amount: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  v := t_mpj_call(null, array[liA1], 9000, null);
  if v->>'raised' is distinct from 'no_runner' then v_bad := v_bad || ' null-runner: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;

  select count(*)::int into v_n from payouts where runner_id = any(array[rA, rB, rC, rD, rE]);
  if v_n is distinct from v_n0 then v_bad := v_bad || ' a-refusal-wrote-a-payout (' || v_n0 || '→' || v_n || ')'; end if;
  if t_mpj_marked(array[liA1, liA2, liA3, liC, liD, liE, liElive]) is distinct from 0 then v_bad := v_bad || ' a-refusal-marked-a-ledger-row'; end if;

  if v_bad = '' then call _pass('mpj','0186-P4 이름으로 거절하고 아무것도 쓰지 않는다: 남의 러너 행·존재하지 않는 id ⇒ not_runner_item · 이미 지급된 행 ⇒ already_paid · 끝나지 않은 run이 달린 행(단독이든 섞였든) ⇒ not_settled · 빈 배열/NULL 배열 ⇒ no_items · 0원/음수/NULL ⇒ bad_amount · 러너 NULL ⇒ no_runner; 열한 번의 거절 뒤 payouts 수도 원장 표시도 그대로');
  else v_msg := v_bad; call _fail('mpj','0186-P4 refusals', v_msg); end if;

  -- ---------- [0186-P5] the happy path, and the second call writes nothing ----------
  v_bad := '';
  perform set_config('request.jwt.claim.sub', ops1::text, true);
  select count(*)::int into v_n0 from payouts where runner_id = any(array[rA, rB, rC, rD, rE]);
  -- A's two oldest rows only: 9000 + 4000 = 13000. liA3 must stay untouched.
  v := t_mpj_call(rA, array[liA1, liA2], 13000, '신한 987 · 2건');
  if v->>'raised' is not null then v_bad := v_bad || ' happy: raised=' || (v->>'raised'); end if;
  v_pay := (v->>'payout')::uuid;
  select count(*)::int into v_n from payouts where runner_id = any(array[rA, rB, rC, rD, rE]);
  if v_n is distinct from v_n0 + 1 then v_bad := v_bad || ' payouts ' || v_n0 || '→' || v_n || ' (expected exactly one new row)'; end if;
  select * into p from payouts where id = v_pay;
  if p.runner_id  is distinct from rA        then v_bad := v_bad || ' runner_id'; end if;
  if p.method     is distinct from 'manual'  then v_bad := v_bad || ' method=' || coalesce(p.method, 'NULL'); end if;
  if p.memo       is distinct from '신한 987 · 2건' then v_bad := v_bad || ' memo=' || coalesce(p.memo, 'NULL'); end if;
  if p.recorded_by is distinct from ops1     then v_bad := v_bad || ' recorded_by is not the calling operator'; end if;
  if p.paid_at    is null                    then v_bad := v_bad || ' paid_at is NULL'; end if;
  if p.status::text is distinct from 'paid'  then v_bad := v_bad || ' status=' || coalesce(p.status::text, 'NULL'); end if;
  if p.instant    is distinct from false     then v_bad := v_bad || ' instant'; end if;
  if p.net        is distinct from 13000     then v_bad := v_bad || ' net=' || coalesce(p.net::text, 'NULL'); end if;
  if p.period_start is distinct from ((now() - interval '9 days') at time zone 'Asia/Seoul')::date then v_bad := v_bad || ' period_start=' || coalesce(p.period_start::text, 'NULL') || ' (expected the KST date of the oldest row)'; end if;
  if p.period_end   is distinct from ((now() - interval '3 days') at time zone 'Asia/Seoul')::date then v_bad := v_bad || ' period_end=' || coalesce(p.period_end::text, 'NULL'); end if;
  -- exactly the named rows, and only them
  if (select paid_payout_id from ledger_items where id = liA1) is distinct from v_pay then v_bad := v_bad || ' liA1 not marked'; end if;
  if (select paid_payout_id from ledger_items where id = liA2) is distinct from v_pay then v_bad := v_bad || ' liA2 not marked'; end if;
  if (select paid_payout_id from ledger_items where id = liA3) is not null then v_bad := v_bad || ' liA3 was marked and was never named'; end if;
  select count(*)::int into v_n from ledger_items where paid_payout_id = v_pay;
  if v_n is distinct from 2 then v_bad := v_bad || ' rows carrying this payout = ' || v_n || ' (expected 2)'; end if;

  -- the second identical call: already_paid, and the payout count does not move
  select count(*)::int into v_n0 from payouts where runner_id = any(array[rA, rB, rC, rD, rE]);
  v := t_mpj_call(rA, array[liA1, liA2], 13000, '신한 987 · 2건');
  if v->>'raised' is distinct from 'already_paid' then v_bad := v_bad || ' second-call: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  -- a batch mixing one paid row with one unpaid row is refused whole
  v := t_mpj_call(rA, array[liA2, liA3], 5000, 'mixed');
  if v->>'raised' is distinct from 'already_paid' then v_bad := v_bad || ' mixed-batch: ' || coalesce(v->>'raised', 'ACCEPTED'); end if;
  select count(*)::int into v_n from payouts where runner_id = any(array[rA, rB, rC, rD, rE]);
  if v_n is distinct from v_n0 then v_bad := v_bad || ' a-repeat-wrote-a-payout (' || v_n0 || '→' || v_n || ')'; end if;
  if (select paid_payout_id from ledger_items where id = liA3) is not null then v_bad := v_bad || ' the mixed batch marked the unpaid row'; end if;

  -- a duplicated id is ONE row, not two: liA3's net is 1000, named twice
  v := t_mpj_call(rA, array[liA3, liA3], 1000, 'dup');
  if v->>'raised' is not null then v_bad := v_bad || ' duplicate-id: ' || (v->>'raised') || ' (a typo is not a double payment)'; end if;
  v_pay2 := (v->>'payout')::uuid;
  if v_pay2 is not null and (select net from payouts where id = v_pay2) is distinct from 1000 then v_bad := v_bad || ' duplicate-id doubled the amount'; end if;

  if v_bad = '' then call _pass('mpj','0186-P5 정상 경로와 멱등성: payouts 행이 정확히 하나 생기고(러너·manual·메모·기록자 uid·paid_at·paid·instant false·net·KST 기간) 이름 붙인 원장 행만 표시된다(같은 러너의 다른 행은 그대로); 같은 호출을 두 번 하면 already_paid이고 payouts 수는 그대로; 지급된 행과 미지급 행을 섞으면 통째로 거절되고 미지급 행도 안 건드린다; 같은 id를 두 번 적어도 한 행으로 센다');
  else v_msg := v_bad; call _fail('mpj','0186-P5 happy path + idempotency', v_msg); end if;

  -- ---------- [0186-P6] the twice-daily stuck sweep ----------
  v_bad := '';
  perform set_config('request.jwt.claim.sub', '', true);   -- the cron carries no identity
  delete from notifications where profile_id in (ops1, ops2, opsoff, opsx);
  -- state now: A has only liA3 left… which P5 just paid. B paid. C live. D zero-net.
  -- So give runner A a fresh 10-day-old settled row and leave everyone else as they are.
  liA1 := t_mpj_item(rA, bkA1, 20000, 2000, interval '10 days');

  -- Runner E is the second expected row and is the interesting one: E holds a settled 8-day-old
  -- unpaid item AND a live-run item. The settled one alone must fire; the live one must neither
  -- fire on its own (runner C) nor be needed to.
  v_n := ops_payouts_stuck_sweep();
  if v_n is distinct from 2 then v_bad := v_bad || ' first-sweep returned ' || coalesce(v_n::text, 'NULL') || ' (expected exactly 2 runners: A and E)'; end if;
  -- ⚠ [0190] SCOPED TO THIS SUITE'S OWN RECIPIENTS, for the reason fixture note ⑥ already gives
  -- about `payouts` and `ledger_items` and this pin did not apply to `ops_recipients`: the roster
  -- is a shared table, so a global 「how many were told」 measures the harness. Measured when
  -- 90_race_check.sh's RP arm (0190) seeded two more `payout_due` recipients: this read 4.
  select count(*)::int into v_n from notifications
   where ref_id = rA and kind = 'system' and profile_id in (ops1, ops2);
  if v_n is distinct from 2 then v_bad := v_bad || ' A: recipients told = ' || v_n || ' (expected 2 active: ops1, ops2)'; end if;
  select count(*)::int into v_n from notifications
   where ref_id = rE and kind = 'system' and profile_id in (ops1, ops2);
  if v_n is distinct from 2 then v_bad := v_bad || ' E: recipients told = ' || v_n || ' (expected 2 — the settled row alone is enough)'; end if;
  if exists (select 1 from notifications where ref_id in (rA, rE) and profile_id in (opsoff, opsx)) then v_bad := v_bad || ' an inactive or wrong-class recipient was told'; end if;
  select * into nrec from notifications where ref_id = rA and profile_id = ops1;
  if nrec.kind::text is distinct from 'system' then v_bad := v_bad || ' kind=' || coalesce(nrec.kind::text, 'NULL'); end if;
  if nrec.body ~ '[0-9]' then v_bad := v_bad || ' the body carries a digit: ' || nrec.body; end if;
  if position(rA::text in coalesce(nrec.body, '')) > 0 or position(rA::text in coalesce(nrec.title, '')) > 0 then v_bad := v_bad || ' the body or title carries an id'; end if;
  -- the paid, the live-run-only and the zero-net runners were never notified
  if exists (select 1 from notifications where ref_id in (rB, rC, rD)) then v_bad := v_bad || ' a paid / live-run / zero-net runner was notified'; end if;

  -- the immediate second sweep writes nothing (the 20-hour window)
  select count(*)::int into v_n0 from notifications;
  v_n := ops_payouts_stuck_sweep();
  if v_n is distinct from 0 then v_bad := v_bad || ' second-sweep returned ' || coalesce(v_n::text, 'NULL') || ' (expected 0 — once per runner per day)'; end if;
  select count(*)::int into v_n from notifications;
  if v_n is distinct from v_n0 then v_bad := v_bad || ' the second sweep wrote ' || (v_n - v_n0) || ' notification(s)'; end if;

  -- a 6-day-old row never fires: give runner C a SETTLED 6-day row and sweep again
  bkC := t_mpj_bk(o, rC, dC, rt, false);
  perform t_mpj_item(rC, bkC, 9000, 1000, interval '6 days');
  v_n := ops_payouts_stuck_sweep();
  if v_n is distinct from 0 then v_bad := v_bad || ' a 6-day-old unpaid row fired the sweep'; end if;
  if exists (select 1 from notifications where ref_id = rC) then v_bad := v_bad || ' runner C (6 days) was notified'; end if;

  -- past the window it notifies again — the dedupe is a window, not a one-shot
  -- THE SECOND TICK OF THE SAME DAY, 12 hours later, must still be silent — that is what 「once
  -- per runner per day」 means with a twice-daily cron. A fixture that only tests 「immediately
  -- again」 and 「21 hours later」 cannot tell a 20-hour window from a one-second one (measured:
  -- battery plant xiv shrinks the window to 1 second and both of those arms stay green, because
  -- `now()` is frozen inside this transaction). 10 hours is inside the window and outside the
  -- 「immediately」 case, which is where the two rules disagree.
  update notifications set created_at = now() - interval '10 hours' where ref_id = rA and profile_id in (ops1, ops2);
  v_n := ops_payouts_stuck_sweep();
  if v_n is distinct from 0 then v_bad := v_bad || ' ten-hours-later sweep returned ' || coalesce(v_n::text, 'NULL') || ' (expected 0 — the second tick of the same day is silent)'; end if;
  select count(*)::int into v_n from notifications where ref_id = rA and profile_id in (ops1, ops2);
  if v_n is distinct from 2 then v_bad := v_bad || ' ten-hours-later wrote ' || (v_n - 2) || ' extra notification(s)'; end if;

  -- ONLY A's rows are moved back, so the sweep must wake for A and stay silent for E: the window
  -- is per (recipient, runner), not a global clock.
  update notifications set created_at = now() - interval '21 hours' where ref_id = rA and profile_id in (ops1, ops2);
  v_n := ops_payouts_stuck_sweep();
  if v_n is distinct from 1 then v_bad := v_bad || ' past-window sweep returned ' || coalesce(v_n::text, 'NULL') || ' (expected 1: A only)'; end if;
  select count(*)::int into v_n from notifications
   where ref_id = rA and profile_id in (ops1, ops2) and created_at > now() - interval '1 hour';
  if v_n is distinct from 2 then v_bad := v_bad || ' past-window told ' || v_n || ' recipient(s) for A (expected 2)'; end if;
  select count(*)::int into v_n from notifications where ref_id = rE and profile_id in (ops1, ops2);
  if v_n is distinct from 2 then v_bad := v_bad || ' E was re-notified inside its own window (' || v_n || ')'; end if;

  if v_bad = '' then call _pass('mpj','0186-P6 막힌 지급 스윕: 7일을 넘긴 미지급 정산이 있는 러너마다(A와 E — E는 살아 있는 run 행과 정산된 행을 함께 갖고 있고 정산된 쪽만으로 울린다) payout_due의 활성 수신자 전원에게 1회(system, ref_id=러너, 본문에 숫자도 id도 없다); 비활성·다른 클래스 수신자는 안 받는다; 곧바로 다시 돌리면 아무것도 안 쓴다(20시간 창); 6일짜리·지급 완료·순액 0·살아 있는 run만 가진 러너는 한 번도 안 울린다; A의 행만 창 밖으로 옮기면 A에게만 다시 알린다(창은 러너별이고 원샷이 아니다)');
  else v_msg := v_bad; call _fail('mpj','0186-P6 stuck sweep', v_msg); end if;

  -- ---------- [0186-S1] deployed shape ----------
  v_bad := '';
  -- ops_payouts_due
  select p2.oid into v_oid from pg_proc p2 join pg_namespace ns on ns.oid = p2.pronamespace
   where ns.nspname = 'public' and p2.proname = 'ops_payouts_due';
  if v_oid is null then v_bad := v_bad || ' A:NO-FUNCTION(ops_payouts_due)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' A:definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' A:search_path 없음'; end if;
    if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false or has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' A:public/anon 실행 가능'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' A:authenticated 실행 불가'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' A:NO-SOURCE';
    else
      if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is distinct from true then v_bad := v_bad || ' A:ops 로스터를 0084의 한 창구로 안 읽음'; end if;
      if (position('raise exception ''not_ops''' in v_src) > 0
          and position('raise exception ''not_ops''' in v_src) < position('from ledger_items l' in v_src)) is distinct from true then v_bad := v_bad || ' A:게이트가 원장 읽기보다 뒤'; end if;
      if (v_src ~ 'r\.ended_at is null') is distinct from true then v_bad := v_bad || ' A:settled 술어 없음'; end if;
      if (v_src ~ 'l\.paid_payout_id is null') is distinct from true then v_bad := v_bad || ' A:미지급 술어 없음'; end if;
    end if;
  end if;

  -- ops_record_manual_payout — the ORDER is the property: gate → lock → state → write
  select p2.oid into v_oid from pg_proc p2 join pg_namespace ns on ns.oid = p2.pronamespace
   where ns.nspname = 'public' and p2.proname = 'ops_record_manual_payout';
  if v_oid is null then v_bad := v_bad || ' B:NO-FUNCTION(ops_record_manual_payout)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' B:definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' B:search_path 없음'; end if;
    if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false or has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' B:public/anon 실행 가능'; end if;
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' B:authenticated 실행 불가'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' B:NO-SOURCE';
    else
      if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is distinct from true then v_bad := v_bad || ' B:ops 로스터를 0084의 한 창구로 안 읽음'; end if;
      -- the LOCK is a precondition of every state gate below it, and deleting it is invisible to
      -- a single-session pin (the reader is the writer) — so the order is pinned by text.
      if (v_src ~ 'from ledger_items l where l\.id = any\(v_ids\) order by l\.id for update;') is distinct from true then v_bad := v_bad || ' B:행 락 없음'; end if;
      if (position('raise exception ''not_ops''' in v_src) > 0
          and position('for update;' in v_src) > 0
          and position('raise exception ''not_ops''' in v_src) < position('for update;' in v_src)) is distinct from true then v_bad := v_bad || ' B:파티 게이트가 락보다 뒤'; end if;
      if (position('for update;' in v_src) > 0
          and position('raise exception ''already_paid''' in v_src) > 0
          and position('for update;' in v_src) < position('raise exception ''already_paid''' in v_src)) is distinct from true then v_bad := v_bad || ' B:상태 게이트가 락보다 앞'; end if;
      if (position('raise exception ''already_paid''' in v_src) > 0
          and position('insert into payouts' in v_src) > 0
          and position('raise exception ''already_paid''' in v_src) < position('insert into payouts' in v_src)) is distinct from true then v_bad := v_bad || ' B:쓰기가 상태 게이트보다 앞'; end if;
      -- the amount gate is an EQUALITY on a NULL-safe operator, never `<>` and never a tolerance
      if (v_src ~ 'v_net is distinct from p_amount_won::bigint') is distinct from true then v_bad := v_bad || ' B:금액 비교가 is distinct from이 아님'; end if;
      if (v_src ~ 'r\.paid_payout_id is not null') is distinct from true then v_bad := v_bad || ' B:already_paid 술어 없음'; end if;
      if (v_src ~ 'rn\.ended_at is null') is distinct from true then v_bad := v_bad || ' B:not_settled 술어 없음'; end if;
      select count(*) into v_n from regexp_matches(v_src, 'insert into payouts', 'g');
      if v_n is distinct from 1 then v_bad := v_bad || ' B:payouts 삽입 ' || v_n || '개(1 기대)'; end if;
    end if;
  end if;

  -- ops_payouts_stuck_sweep
  select p2.oid into v_oid from pg_proc p2 join pg_namespace ns on ns.oid = p2.pronamespace
   where ns.nspname = 'public' and p2.proname = 'ops_payouts_stuck_sweep';
  if v_oid is null then v_bad := v_bad || ' C:NO-FUNCTION(ops_payouts_stuck_sweep)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' C:definer 아님'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp' from pg_proc where oid = v_oid) is distinct from true then v_bad := v_bad || ' C:search_path 없음'; end if;
    if has_function_privilege('public', v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false
    or has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from false then v_bad := v_bad || ' C:클라 실행 가능'; end if;
    if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from true then v_bad := v_bad || ' C:service_role 실행 불가'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null then v_bad := v_bad || ' C:NO-SOURCE';
    else
      if (v_src ~ 'interval ''7 days''')  is distinct from true then v_bad := v_bad || ' C:7일 임계 없음'; end if;
      if (v_src ~ 'interval ''20 hours''') is distinct from true then v_bad := v_bad || ' C:20시간 중복 방지 창 없음'; end if;
      -- ⚠ DECLARING the window is not USING it. Measured in the battery (plant viii): replacing
      -- the whole `where not exists (…)` guard with `where true` left the constant's declaration
      -- in place, so an arm that only matched the literal stayed GREEN on a sweep that notifies
      -- every tick. The property is that the insert is CONDITIONAL on no prior notification for
      -- the same (recipient, runner) inside the window — so match the consumption, not the value.
      if (v_src ~ 'where not exists \(') is distinct from true then v_bad := v_bad || ' C:중복 방지 가드(not exists) 없음'; end if;
      if (v_src ~ 'created_at > now\(\) - DEDUPE_WINDOW') is distinct from true then v_bad := v_bad || ' C:20시간 창을 선언만 하고 쓰지 않는다'; end if;
      if (v_src ~ 'ops_recipients_for\(c_ops_class\)') is distinct from true then v_bad := v_bad || ' C:수신자 조회 없음'; end if;
      if (v_src ~ 'rn\.ended_at is null') is distinct from true then v_bad := v_bad || ' C:settled 술어 없음'; end if;
    end if;
  end if;

  -- the four columns, the deliberate absence of an FK on recorded_by, and the seals
  if (select data_type from information_schema.columns where table_schema='public' and table_name='ledger_items' and column_name='paid_payout_id') is distinct from 'uuid' then v_bad := v_bad || ' ledger_items.paid_payout_id 없음'; end if;
  if (select is_nullable from information_schema.columns where table_schema='public' and table_name='ledger_items' and column_name='paid_payout_id') is distinct from 'YES' then v_bad := v_bad || ' paid_payout_id가 nullable이 아님'; end if;
  if (select column_default from information_schema.columns where table_schema='public' and table_name='ledger_items' and column_name='paid_payout_id') is not null then v_bad := v_bad || ' paid_payout_id에 기본값이 붙었다(오늘의 모든 행을 지급됨으로 주장한다)'; end if;
  select count(*)::int into v_n from pg_constraint
   where contype = 'f' and conrelid = 'ledger_items'::regclass and confrelid = 'payouts'::regclass;
  if v_n is distinct from 1 then v_bad := v_bad || ' ledger_items→payouts FK ' || v_n || '/1'; end if;
  foreach v_msg in array array['method','memo','recorded_by'] loop
    if (select count(*)::int from information_schema.columns where table_schema='public' and table_name='payouts' and column_name = v_msg) is distinct from 1 then v_bad := v_bad || ' payouts.' || v_msg || ' 없음'; end if;
    if has_column_privilege('authenticated', 'payouts', v_msg, 'SELECT') is distinct from false then v_bad := v_bad || ' payouts.' || v_msg || ' 를 클라가 읽는다'; end if;
  end loop;
  -- 0186 §A: recorded_by is deliberately NOT an FK — 0115's edge list into profiles is explicit
  -- and pinned (150 N6-2/N7), and neither restrict nor set null is this slice's decision.
  select count(*)::int into v_n from pg_constraint
   where contype = 'f' and conrelid = 'payouts'::regclass and confrelid = 'profiles'::regclass;
  if v_n is distinct from 0 then v_bad := v_bad || ' payouts→profiles FK가 생겼다 (' || v_n || ') — 0115의 삭제 폐포가 이 파일의 결정이 아니다'; end if;
  -- the self-read half of the seal still works
  foreach v_msg in array array['id','runner_id','period_start','period_end','gross','tax_withheld','net','status','instant','paid_at'] loop
    if has_column_privilege('authenticated', 'payouts', v_msg, 'SELECT') is distinct from true then v_bad := v_bad || ' payouts self-read 깨짐: ' || v_msg; end if;
  end loop;
  if has_column_privilege('authenticated', 'ledger_items', 'paid_payout_id', 'SELECT') is distinct from false then v_bad := v_bad || ' ledger_items.paid_payout_id 를 클라가 읽는다'; end if;
  if has_column_privilege('anon', 'payouts', 'net', 'SELECT') is distinct from false then v_bad := v_bad || ' anon이 payouts를 읽는다'; end if;

  -- the cron ARTIFACT (0177's law: cron.schedule returning is a claim, a row in cron.job is a fact)
  select count(*)::int into v_n from cron.job
   where jobname = 'ops-payouts-stuck' and active
     and schedule = '25 0,9 * * *' and command = 'select ops_payouts_stuck_sweep()';
  if v_n is distinct from 1 then v_bad := v_bad || ' cron.job(ops-payouts-stuck) ' || v_n || '/1 (jobname·schedule·command·active 일치)'; end if;

  if v_bad = '' then call _pass('mpj','0186-S1 배포 형상: 세 definer 모두 prosecdef·본문 search_path·값으로 확인한 ACL(두 ops 함수는 authenticated, 스윕은 service_role 전용, public/anon은 아무 데도 없다); 기록 함수의 순서는 파티 게이트 → for update 락 → 상태 게이트 → 쓰기이고 payouts 삽입은 1개, 금액 비교는 is distinct from; ledger_items.paid_payout_id는 nullable·기본값 없음·payouts FK 하나; payouts.method/memo/recorded_by는 클라에 안 보이고 기존 열 열 개는 그대로 보인다; recorded_by에 profiles FK는 일부러 없다(0115의 간선 목록); cron.job에 행 하나');
  else v_msg := v_bad; call _fail('mpj','0186-S1 shape', v_msg); end if;
end $$;

drop function if exists t_mpj_call(uuid, uuid[], int, text);
drop function if exists t_mpj_due();
drop function if exists t_mpj_bk(uuid, uuid, uuid, uuid, boolean);
drop function if exists t_mpj_item(uuid, uuid, int, int, interval);
drop function if exists t_mpj_marked(uuid[]);
