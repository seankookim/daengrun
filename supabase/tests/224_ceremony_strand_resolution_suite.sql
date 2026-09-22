-- ═══ 224 — 0193: the run-end ceremony's dead ends get an EXIT (codex REJECT/9 on 0188/0189/0190) ═══
--           0193-Q1 · Q2 · R1 · R2 · R3 · R4 · B5 · C9 · S1, tag `crs`
--
-- ═══ WHAT THIS SUITE OWNS, AND WHAT IT DELIBERATELY DOES NOT ═════════════════════════════
-- 0083/0089/0092/0096/0188 are pinned by 119/125/131/132/133/219. Nothing here re-asserts them.
-- This suite owns exactly what 0193 changed or created:
--   Q — `confirm_return_tx`'s new gate, in BOTH directions. Q1 is the interleaving codex A3
--       describes, driven through the real functions in the real order; Q2 is the CLIENT capability
--       0083 §6 designed and 0188 §B argued must survive. Q2 is not decoration: a gate written
--       without its `v_uid is null` conjunct refuses everybody, and the first draft of 0193 did
--       exactly that — measured, three shipped pins red (119 R15 · R16 · 133 U2).
--   R — the ops exit (A1 · A2) and its bell. R1 the one-stamp strand, R2 the zero-stamp timeout
--       that 0066:56 turned into a money dead end, R3 the refusals, R4 the sweep's new arm and its
--       OFF switch.
--   B — the 귀가 escalation pushing through 예약 알림 off, measured through the REAL sweep rather
--       than by probing the title family (codex B5's own words).
--   C — the pre-0190 orphan bank row.
--   S — the deployed shape.
--
-- ⚠ NO PIN HERE ASSERTS A MONEY AMOUNT. Every money claim is presence/absence of a `ledger_items`
--   row and the state of `runs.settled_at` — 132's header's rule. Pricing belongs to 137, and the
--   amount equality on a payout belongs to 217 P3.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   0193-Q1 ← delete the `quote_required` raise in §B: the interleaving seals with no settlement
--             and nothing in the app can repair it                                      → RED
--   0193-Q2 ← delete `v_uid is null` from `v_seals_now`: the gate now refuses a CLIENT's
--             second stamp too, which is 0083 §6's designed capability. ⚠ MEASURED BEFORE
--             THIS SUITE EXISTED — the first draft of 0193 shipped without that conjunct and
--             119 R15 · 119 R16 · 133 U2 went red. Q2 is what makes that visible HERE, in
--             the slice that owns the property, instead of three files away              → RED
--   0193-R1 ← delete the `_settle_sealed_run` call from `ops_resolve_return_tx`: the strand
--             is marked resolved and the runner is still unpaid — A1 with a receipt       → RED
--   0193-R2 ← delete §C-a's `incident_review → active` disjunct: the adjudication cannot
--             move the row and A2's dead end is back                                     → RED
--   0193-R3 ← delete the `not_ops` gate: anyone who can reach the edge can settle any
--             stranded booking, and the 「refused before any read」 arm (a NON-EXISTENT
--             booking must answer `not_ops`, never `not_found`) is what makes that sharp  → RED
--   ⚠ NAMED GAP, measured rather than reasoned: §C-a's `current_user not in
--     ('authenticated','anon')` conjunct is NOT separately observable here. 0058 F3 made
--     `_guard_booking_cols` a DENY-ALL, so a party's direct UPDATE dies with
--     `booking_protected_columns` before the transition map runs, and every other caller in
--     this harness is `postgres`, for whom the conjunct is always true. R3 ⓖ pins what is
--     true (the party path is closed, by that guard, BY NAME); the conjunct itself is pinned
--     by source in S1. This is 「the property is not observable through this door」, not 「the
--     pin is blind」 — and writing it down is the difference.
--   0193-R4 ← delete arm ⓕ, or make it ignore a NULL flag: either the strand is never
--             reported or it is reported on a deadline nobody chose                       → RED
--   0193-B5 ← revert the escalation's writer to `kind = 'booking'` AND drop the title from
--             `_noti_urgent_noti_titles()`: 예약 알림 off silences 「the dog is unaccounted
--             for」. ⚠ TWO reverts, because 0193 closes it twice on purpose (the writer for
--             new rows, the family for rows already written) — and a pin that only saw one
--             would call the slice done after half of it                                  → RED
--   0193-C9 ← delete the `deleted_at`/unpaid predicates from `_release_orphan_bank_rows`:
--             either nothing is released (the defect) or a LIVE runner's destination is
--             deleted, and the two controls separate those                                → RED
--   0193-S1 ← any deployed-shape drift (definer · in-body search_path · ACL by value · the
--             ops gate ahead of the lock · no stamp forgery · the journal sealed)          → RED
--
--   ✔ MUTATION-PROVEN. Battery run 2026-09-22 in an md5-identical lab OUTSIDE the worktree
--   (`/private/tmp/dr-0193-lab`; never edit a live migration to test a hypothetical). Every plant
--   is `&&`-CHAINED to its harness run, so an unlanded plant yields NO row rather than a plausible
--   green one, and each prints `PLANT LANDED` before the run. CONTROL OBSERVED FIRST and
--   re-observed after the one pin repair below: **1351 / 0, no red pins.**
--   「demoted」 = 0193's own VERIFY raise turned into a notice so the SUITE is what is measured;
--   「un-demoted」 = the shipped file, where VERIFY aborts the apply before any suite runs.
--
--     (i)  §B's guard → `if false` (the A3 hole, restored)
--            un-demoted → APPLY ABORTS: `0193 VERIFY failed: confirm_return_tx: 가격 없는 봉인
--                         가드가 없다`
--            demoted    → **1349 / 2 — `0193-Q1` + `0193-S1`**, and Q1's detail is the defect in
--                         its own words: 「서버의 두 번째 스탬프가 가격 없이 통과했다 (정산 없는
--                         봉인)」 + the owner stamp and the seal were written anyway.
--                         ⚠ `0193-Q2` stays GREEN, which is the point: the plant does not touch
--                         the client's designed capability, and a pin that reddened with Q1 here
--                         would be the same claim counted twice.
--     (ii) the ops roster gate → `if false` (the A1 door, unguarded)
--            un-demoted → APPLY ABORTS: `0193 VERIFY failed: 해결 RPC: ops 게이트가 잠금보다 뒤에
--                         있다`
--            demoted    → **1349 / 2 — `0193-R3` + `0193-S1`**, and R3's detail is what its
--                         sharpest arm exists for: a non-ops caller settled a stranded booking,
--                         AND 「없는 예약의 거절 이름이 다르다=not_found」 — the endpoint became an
--                         ORACLE for which bookings exist. The refusal-by-name arms alone would
--                         have reported only the first half.
--
--     (iii) `v_uid is null` deleted from `v_seals_now` — the Q2 control, i.e. 「what if the new
--           gate were NOT narrowed to a server caller」
--            un-demoted → APPLY ABORTS: `0193 VERIFY failed: confirm_return_tx: 서버 한정 조건이
--                         봉인 예측의 첫 조건이 아니다`
--            demoted    → **1345 / 6**, and this is the strongest row in the battery because
--                         HALF OF IT IS OTHER PEOPLE'S PINS: `0193-Q2` + `0193-S1` here, and
--                         **`119 R15` · `119 R16` · `133 U2`** — three shipped pins in two other
--                         files, written for 0083/0097's reasons years before this slice, all
--                         refusing with `quote_required`. Independent agreement that the
--                         capability 0188 §B argued for is real and that the conjunct is what
--                         preserves it. ⚠ `0193-Q1` stays GREEN (the plant widens the gate, it
--                         does not remove it), which is the pair behaving as two propositions.
--
--   🔴 TWO PIN REPAIRS CAME OUT OF THIS BATTERY, and it is a repair to the INSTRUMENT rather than
--   to the property. Plant (i) originally left the apply GREEN un-demoted, because VERIFY and S1
--   matched the STRINGS `quote_required` and `v_uid is null` — and `if false then raise exception
--   'quote_required'` leaves both in the body. **A dead raise satisfies every check for its own
--   name**: the pattern was present in the guarded and unguarded states alike, which is the
--   uninformative-detector class, committed inside the arms written to enforce rigour. Both now
--   match the GUARD (`if v_seals_now and p_quote is null then`, and `v_seals_now := coalesce(
--   v_uid is null`), and (i) was re-run to the result recorded above. Stated without reference to
--   the mutation: a source arm must match the CONDITION that makes a refusal reachable, never the
--   refusal's vocabulary.
--   And the second, from plant (iii): `0193-R3`'s `already_sealed` arm BORROWED Q2's fixture, and
--   under a plant that reddens Q2 it reported `not_found` — a plpgsql `begin … exception` block is
--   a SUBTRANSACTION, so Q2's caught raise rolled its booking back and R3 was probing a row that no
--   longer existed. R3 was still red, so nothing was hidden; what was lost is the arm's MEANING.
--   It now builds its own sealed row, and plant (iii) was RE-RUN against the repair: same total
--   (1345 / 6), same pin set, and R3's detail is now `quote_required` — the arm failing for a
--   reason that NAMES the plant instead of for a booking that had ceased to exist. Stated without
--   reference to the mutation: a pin must not depend on a fixture created inside another pin's
--   rollback boundary.
--
-- ─── FIXTURE NOTES ───
--  ① This suite builds its own world (`t_crs_*`) rather than borrowing 219's `t_rec_live`: a pin
--     that inherits another suite's setup is testing that setup, and 219's fixtures move for 219's
--     reasons.
--  ② `ops_recipients` gets ONE row, in a class (`return_strand`) this file creates and nobody else
--     counts. 217 P6's counts are scoped to its own two profiles since 0190, so nothing global is
--     disturbed; the row is left in place because R1/R2/R3 need it and it is this class's only
--     member.
--  ③ `ops_flags.return_strand_minutes` is READ as NULL first (the shipped value — the arm's off
--     switch is the property, not an accident of ordering), then set for R4, then **reset to NULL**
--     at the end of R4 so any later suite sees what production sees.
--  ④ C9's tombstone is stamped BY HAND, and that is the point rather than a shortcut: today's
--     `delete_my_account_tx` (0190 §B) already releases a fully-paid runner's bank row, so the
--     orphan shape can only be manufactured the way it actually arose — a deletion that ran under
--     the OLD code. A fixture built with today's function could not contain the defect (0151's
--     measured lesson, in the one direction where the current code is the wrong fixture).
--  ⑤ B5 counts pushes BY THEIR PAYLOAD (token and title), not as a global delta: the sweep is a
--     janitor and runs over every leftover row in the database, so a count that is not scoped to
--     this fixture's token measures the other suites. ⚠ AMENDED 2026-09-22 (0204): the rows
--     counted are `push_outbox` rows, not `net._stub_calls` rows — see the `[0204]` note on
--     `t_crs_pushes` below. The payload scoping, which is what this note is about, is unchanged.
set client_min_messages = warning;

-- ---------- suite-local fixtures ① ----------
-- A marketplace run that is LIVE (started, not stopped). Sibling of 219's `t_rec_live`.
create or replace function t_crs_live(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'active', now() - interval '50 minutes', 5.0,
          9900, 15000, 0, 24900, 9900)
  returning id into v;
  insert into runs (booking_id, started_at, trace)
  values (v, now() - interval '50 minutes', '[]'::jsonb);
  return v;
end $$;

-- The quote the EDGE computes and hands to the RPC. A fixture, not a rule (137 owns pricing).
create or replace function t_crs_quote(p_km numeric) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'base', 9900, 'distance_pay', round(p_km * 3000)::int, 'addon_pay', 0,
    'guarantee', 0, 'fee', round((9900 + round(p_km * 3000)) * 0.2)::int)
$$;

-- age a stopped run so the sweep's deadlines are past (the run row moves with it — a frozen stop
-- whose `runs.ended_at` disagrees with `bookings.run_ended_at` is not a state the product makes)
create or replace function t_crs_age(p_booking uuid, p_ago interval) returns void
language sql as $$
  with b as (update bookings set run_ended_at = now() - p_ago where id = p_booking returning id)
  update runs set ended_at = now() - p_ago where booking_id = (select id from b)
$$;

-- pushes produced for ONE token and ONE title ⑤
-- ⚠ [0204] THIS NOW COUNTS `push_outbox` ROWS, NOT `net._stub_calls`, AND B5's THREE DELTAS AND
--   THEIR EXPECTED VALUES ARE UNCHANGED. `notify_push` used to decide AND post in one statement;
--   0204 splits that into row → outbox and outbox → HTTP one cron tick later, because pg_net is
--   asynchronous and a deletion committing in between was never re-examined (Codex B8). B5's
--   subject is the CLASSIFICATION — a `귀가 확인이 필요해요` row reaches the send boundary even
--   with `booking = false`, under both `kind = 'safety'` and the pre-0193 `kind = 'booking'` — and
--   that decision still happens where it did. The payload match is kept (token + title), so the
--   pin still identifies its own push rather than counting anything that moved. outbox → HTTP is
--   owned by `235_push_outbox_suite.sql` (`0204-R1`…`R4`).
create or replace function t_crs_pushes(p_token text, p_title text) returns int
language sql as $$
  select count(*)::int from push_outbox
   where token = p_token and title = p_title
$$;

do $$
declare
  oo uuid; rr uuid; oz uuid; rz uuid; dg uuid; dz uuid; rt uuid; ops uuid;
  b1 uuid; b2 uuid; b3 uuid; b4 uuid; b5 uuid; b6 uuid; b7 uuid; b8 uuid; b9 uuid; b_sealed uuid;
  ob uuid; rb uuid; db uuid; bb uuid;                    -- B5's own world
  c_live uuid; c_tomb uuid; c_owed uuid; c_o uuid; c_d uuid; c_rt uuid; c_pay uuid;
  v_bad text := ''; v_msg text; v_js jsonb; v_n int; v_src text; v_status text;
  v_before int; v_after int;
begin
  perform set_config('request.jwt.claim.sub', '', false);
  oo := t_user('crs_oo', 'owner');  oz := t_user('crs_oz', 'owner');
  rr := t_user('crs_rr', 'runner'); rz := t_user('crs_rz', 'runner');
  dg := t_dog(oo, '해결견'); dz := t_dog(oz, '좌초견');
  rt := t_route('좌초 코스');
  ops := t_user('crs_ops', 'owner');
  insert into ops_recipients (profile_id, event_class, active)
  values (ops, 'return_strand', true) on conflict (profile_id, event_class) do nothing;   -- ②

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0193-Q1] THE INTERLEAVING — the stop commits between the edge's price read and its confirm
  -- 🔴 This is codex A3 driven through the real functions in the real order. The edge reads the
  --    booking BEFORE the stop, so `run_ended_at` is NULL, `quoteFor` finds no `runs.actual_km`
  --    to price from and returns null — and the 503 that exists to stop exactly this cannot fire,
  --    because it is conditioned on the same stale `run_ended_at`. Then the stop commits, the
  --    runner stamps, and the edge's call is the SECOND stamp with a null quote.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    b1 := t_crs_live(oo, dg, rt, rr);
    -- CONTROL: the fixture really is in the pre-stop state the edge would have read.
    if (select b.run_ended_at from bookings b where b.id = b1) is not null
      then v_bad := v_bad || ' 픽스처가 이미 정지된 상태다 (인터리빙 구역이 아니다)'; end if;
    if exists (select 1 from runs r where r.booking_id = b1 and r.actual_km is not null)
      then v_bad := v_bad || ' 픽스처에 이미 실측이 있다 (엣지가 가격을 구할 수 있었다)'; end if;

    -- …now the stop commits and the runner stamps (R6a, seconds after the stop)
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b1, 5.0, 1800, 'completed', null, null);
    perform confirm_return_tx(b1, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);

    -- the edge's confirm arrives, carrying the NULL quote it computed before the stop, as the
    -- SERVER (no `auth.uid()` — `transition-booking` uses `admin()`)
    begin
      perform confirm_return_tx(b1, 'owner', null);
      v_bad := v_bad || ' 서버의 두 번째 스탬프가 가격 없이 통과했다 (정산 없는 봉인)';
    exception when others then
      if sqlerrm <> 'quote_required' then v_bad := v_bad || ' 거절 이름=' || sqlerrm; end if;
    end;
    -- NOTHING was written — a refusal costs a retry, never a half-written ceremony
    if (select b.owner_confirmed_return_at from bookings b where b.id = b1) is not null
      then v_bad := v_bad || ' 거절했는데 보호자 스탬프가 찍혔다'; end if;
    if (select b.settlement_ready_at from bookings b where b.id = b1) is not null
      then v_bad := v_bad || ' 거절했는데 봉인이 찍혔다'; end if;
    if (select b.status::text from bookings b where b.id = b1) <> 'active'
      then v_bad := v_bad || ' 거절이 상태를 옮겼다'; end if;
    if exists (select 1 from ledger_items li where li.booking_id = b1)
      then v_bad := v_bad || ' 거절했는데 원장이 생겼다'; end if;
    -- the runner's own stamp survives: the refusal is about THIS call, not about the ceremony
    if (select b.runner_confirmed_return_at from bookings b where b.id = b1) is null
      then v_bad := v_bad || ' 거절이 러너의 스탬프까지 되돌렸다'; end if;

    -- THE RETRY — what `confirm_return.ts` does on `quote_required`: re-read, re-price, call once
    -- more. This is also the CONTROL that stops 「refuse everything」 passing this pin.
    v_js := confirm_return_tx(b1, 'owner', t_crs_quote(5.0));
    if not coalesce((v_js->>'sealed')::boolean, false) then v_bad := v_bad || ' 재시도가 봉인하지 않았다'; end if;
    if not coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 재시도가 정산하지 않았다'; end if;
    if (select b.status::text from bookings b where b.id = b1) <> 'completed'
      then v_bad := v_bad || ' 재시도 뒤 completed가 아니다'; end if;
    select count(*) into v_n from ledger_items li where li.booking_id = b1;
    if v_n <> 1 then v_bad := v_bad || ' 재시도 뒤 원장 행 수=' || v_n; end if;

    if v_bad = ''
      then call _pass('crs','0193-Q1 정지가 엣지의 가격 조회와 확인 사이에 커밋돼도 봉인만 남지 않는다 — 신원 없는(서버) 호출자의 두 번째 스탬프가 가격 없이 오면 quote_required로 거절되고 스탬프·봉인·상태·원장 아무것도 쓰이지 않으며(러너의 스탬프도 그대로), 다시 가격을 들고 온 재시도는 봉인·정산·completed·원장 1행으로 끝난다');
    else v_msg := v_bad; call _fail('crs','0193-Q1 인터리빙은 봉인만 남기지 않는다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('crs','0193-Q1 인터리빙은 봉인만 남기지 않는다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0193-Q2] …AND THE CLIENT'S DESIGNED CAPABILITY SURVIVES. THE CONTROL THAT COSTS SOMETHING.
  -- 🔴 A SEPARATE PROPOSITION from Q1, and the one that stops the fix being a blanket refusal.
  --    0083 §6: a client-class caller 「may seal — the stamp is its own truthful act — and
  --    settlement then belongs to the server call that follows」; 0188 §B argued explicitly that a
  --    raise must NOT delete that, and suites 133 · 119 R12/R16 · 125 F4 all depend on it. The
  --    gate's `v_uid is null` conjunct is the whole narrowing, and a draft of 0193 that omitted it
  --    reddened three shipped pins in three other files — none of which would have told a reader
  --    WHY. This pin says why, here.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    b2 := t_crs_live(oz, dz, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(b2, 4.0, 1500, 'completed', null, null);
    perform confirm_return_tx(b2, 'runner');
    -- the OWNER's own tap, as a phone: no `p_quote` is even possible (`quote_from_client`)
    perform set_config('request.jwt.claim.sub', oz::text, false);
    v_js := confirm_return_tx(b2, 'owner');
    perform set_config('request.jwt.claim.sub', '', false);
    if not coalesce((v_js->>'stamped')::boolean, false) then v_bad := v_bad || ' 클라 스탬프가 거부됐다'; end if;
    if not coalesce((v_js->>'sealed')::boolean, false) then v_bad := v_bad || ' 클라의 두 번째 스탬프가 봉인하지 않았다 (0083 §6의 능력이 사라졌다)'; end if;
    if coalesce((v_js->>'settled')::boolean, true) then v_bad := v_bad || ' 클라가 가격 없이 정산했다'; end if;
    if (select b.settlement_ready_at from bookings b where b.id = b2) is null
      then v_bad := v_bad || ' 봉인이 행에 남지 않았다'; end if;
    if exists (select 1 from ledger_items li where li.booking_id = b2)
      then v_bad := v_bad || ' 가격 없는 봉인이 원장을 만들었다'; end if;
    if (select b.status::text from bookings b where b.id = b2) <> 'active'
      then v_bad := v_bad || ' 봉인만 했는데 상태가 옮겨졌다'; end if;
    -- …and a client STILL may not hand over a price (the other half of the one sentence)
    perform set_config('request.jwt.claim.sub', oz::text, false);
    begin
      perform confirm_return_tx(b2, 'owner', t_crs_quote(4.0));
      v_bad := v_bad || ' 클라가 가격을 넘겼다';
    exception when others then
      if sqlerrm <> 'quote_from_client' then v_bad := v_bad || ' 클라 가격 거부 이름=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);

    if v_bad = ''
      then call _pass('crs','0193-Q2 새 게이트는 서버 호출자에게만 걸린다 — 신원이 있는 호출자(폰)의 두 번째 스탬프는 0083 §6 설계대로 봉인만 하고 정산하지 않으며(원장 0행·상태 active 유지), 가격을 넘기려 하면 여전히 quote_from_client다. 이 대조가 없으면 「전부 거절」이 Q1을 통과한다');
    else v_msg := v_bad; call _fail('crs','0193-Q2 클라의 봉인 능력은 살아 있다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('crs','0193-Q2 클라의 봉인 능력은 살아 있다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0193-R1] THE ONE-STAMP STRAND HAS AN EXIT — and it never forges the missing stamp
  -- codex A1: the runner stamps, the owner never does, and 0188 ⓑ-② (correctly) refuses to move
  -- the row. One alarm at two hours, then permanent silence, `active` forever, work-gated, unpaid.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    b3 := t_crs_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b3, 4.0, 1500, 'completed', null, null);
    perform confirm_return_tx(b3, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_crs_age(b3, interval '5 hours');
    -- CONTROL: the fixture is the strand 0188 ⓑ-② preserves — one stamp, no seal, still `active`
    if (select b.runner_confirmed_return_at from bookings b where b.id = b3) is null
      then v_bad := v_bad || ' 픽스처에 러너 스탬프가 없다'; end if;
    if (select b.owner_confirmed_return_at from bookings b where b.id = b3) is not null
      then v_bad := v_bad || ' 픽스처에 보호자 스탬프가 있다 (좌초가 아니다)'; end if;
    -- …and the runner really is held by it (the thing this costs a real person)
    if not coalesce((runner_work_gate(rr)->>'gated')::boolean, false)
      then v_bad := v_bad || ' 좌초된 러너가 게이트에 걸려 있지 않다 (전제가 거짓)'; end if;

    v_js := ops_resolve_return_tx(b3, t_crs_quote(4.0), '보호자와 통화 — 개는 집에 있다고 확인', ops);
    if not coalesce((v_js->>'resolved')::boolean, false) then v_bad := v_bad || ' 해결되지 않았다'; end if;
    if (v_js->>'from_status') is distinct from 'active' then v_bad := v_bad || ' from_status=' || coalesce(v_js->>'from_status','(null)'); end if;
    if not coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 해결이 정산하지 않았다 (A1이 그대로 남는다)'; end if;
    if (select b.status::text from bookings b where b.id = b3) <> 'completed'
      then v_bad := v_bad || ' 해결 뒤 completed가 아니다'; end if;
    if (select r.settled_at from runs r where r.booking_id = b3) is null
      then v_bad := v_bad || ' runs.settled_at이 없다 (돈이 움직인 시각)'; end if;
    select count(*) into v_n from ledger_items li where li.booking_id = b3;
    if v_n <> 1 then v_bad := v_bad || ' 원장 행 수=' || v_n || ' (정확히 1)'; end if;
    -- 🔴 NO FORGED STAMP. 0089's ruling: an ops act is an adjudication, not a confirmation, and a
    -- later reader must be able to tell them apart.
    if (select b.owner_confirmed_return_at from bookings b where b.id = b3) is not null
      then v_bad := v_bad || ' 🔴 ops가 보호자의 스탬프를 위조했다'; end if;
    if (select b.return_forced_by from bookings b where b.id = b3) is distinct from 'ops'
      then v_bad := v_bad || ' ops 마커가 없다'; end if;
    -- ⚠ [0201 §A] THIS ARM MOVED, AND IT MOVED FOR A TRUE REASON (codex 2026-09-22 #1). It used to
    --   assert that `return_force_reason` held the operator's MEMO — which was exactly the defect:
    --   `authenticated` has table SELECT on `bookings` and 0002:92 scopes it to the two parties, so
    --   a private ops note in this column is read by both of them through PostgREST. 0201 §A writes
    --   a fixed token keyed by the rescued-from state instead, and the memo stays in the sealed
    --   journal (asserted two lines below, unchanged). **232 `0201-M1` owns the new property** —
    --   the memo absent from every party-readable value, both tokens, both parties.
    if (select b.return_force_reason from bookings b where b.id = b3) is distinct from 'ops_resolved:strand'
      then v_bad := v_bad || ' 판정 토큰이 기록되지 않았다=' || coalesce((select b.return_force_reason from bookings b where b.id = b3), '(null)'); end if;
    if (select position('보호자와 통화' in coalesce(b.return_force_reason, '')) > 0 from bookings b where b.id = b3) is not false
      then v_bad := v_bad || ' 🔴 운영 메모가 당사자가 읽는 칸에 실렸다'; end if;
    -- the journal, with the facts the resolving UPDATE destroys
    select count(*) into v_n from return_resolutions where booking_id = b3;
    if v_n <> 1 then v_bad := v_bad || ' 저널 행 수=' || v_n; end if;
    if not exists (select 1 from return_resolutions
                   where booking_id = b3 and resolved_by = ops and from_status = 'active'
                     and runner_stamped and not owner_stamped)
      then v_bad := v_bad || ' 저널이 누가·어디서·무엇이 빠진 채였는지를 담지 않았다'; end if;
    -- and the runner is free
    if coalesce((runner_work_gate(rr)->>'gated')::boolean, true)
      then v_bad := v_bad || ' 해결 뒤에도 러너가 묶여 있다'; end if;
    -- IDEMPOTENCE: a second resolve is "done", never a second ledger row or a second journal row
    v_js := ops_resolve_return_tx(b3, t_crs_quote(4.0), '재시도', ops);
    if coalesce((v_js->>'resolved')::boolean, true) then v_bad := v_bad || ' 재호출이 다시 해결했다'; end if;
    if not coalesce((v_js->>'unchanged')::boolean, false) then v_bad := v_bad || ' 재호출이 unchanged가 아니다'; end if;
    select count(*) into v_n from ledger_items li where li.booking_id = b3;
    if v_n <> 1 then v_bad := v_bad || ' 재호출 뒤 원장 행 수=' || v_n; end if;
    select count(*) into v_n from return_resolutions where booking_id = b3;
    if v_n <> 1 then v_bad := v_bad || ' 재호출 뒤 저널 행 수=' || v_n; end if;

    if v_bad = ''
      then call _pass('crs','0193-R1 한쪽만 찍힌 좌초에 도달 가능한 출구가 생겼다 — ops가 해결하면 completed·settled_at·원장 1행이 되고 러너가 풀리며, **빠진 당사자 스탬프는 절대 위조되지 않고**(0089) return_forced_by=ops 마커와 return_resolutions 저널(누가·어느 상태에서·어느 스탬프가 빠졌는지)만 남는다; 재호출은 unchanged로 원장도 저널도 늘리지 않는다. ⚠ 0201 §A 이후 return_force_reason은 운영 메모가 아니라 구조된 상태가 고르는 고정 토큰(ops_resolved:strand)이다 — 그 칸은 당사자가 직접 읽으므로(0002:92) 메모를 쓰면 곧 유출이었다(codex 2026-09-22 #1; 232 0201-M1이 새 성질을 소유)');
    else v_msg := v_bad; call _fail('crs','0193-R1 한쪽 좌초의 출구', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('crs','0193-R1 한쪽 좌초의 출구', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0193-R2] THE ZERO-STAMP TIMEOUT IS NO LONGER A MONEY DEAD END (codex A2)
  -- 🔴 THE HOLE IS REPRODUCED FIRST, unfixed, on the fixture the REAL sweep made — the
  --    three-proposition law: 「the hole is real」, 「something notices」 and 「the fix closes it」 are
  --    different claims and a single arm proves only the middle one.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    b4 := t_crs_live(oz, dz, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(b4, 3.0, 1200, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_crs_age(b4, interval '5 hours');
    perform sweep_run_end_recovery();                 -- the REAL janitor escalates it (0188 ⓑ-①)
    if (select b.status::text from bookings b where b.id = b4) <> 'incident_review'
      then v_bad := v_bad || ' 0스탬프 행이 승격되지 않았다=' || (select b.status::text from bookings b where b.id = b4); end if;

    -- ⓐ THE HOLE, UNFIXED: settlement is impossible from here through every shipped 1:1 door
    begin
      perform _settle_sealed_run(b4, t_crs_quote(3.0));
      v_bad := v_bad || ' incident_review에서 정산 프리미티브가 통과했다';
    exception when others then
      if sqlerrm <> 'not_active' then v_bad := v_bad || ' 프리미티브 거절 이름=' || sqlerrm; end if;
    end;
    -- …and the runner is still held, which is what makes it cost a person
    if not coalesce((runner_work_gate(rz)->>'gated')::boolean, false)
      then v_bad := v_bad || ' 승격된 예약의 러너가 풀려 있다 (0092 둘째 팔의 전제가 거짓)'; end if;

    -- ⓑ THE EXIT
    v_js := ops_resolve_return_tx(b4, t_crs_quote(3.0), 'CCTV 확인 — 개는 귀가했음', ops);
    if (v_js->>'from_status') is distinct from 'incident_review' then v_bad := v_bad || ' from_status=' || coalesce(v_js->>'from_status','(null)'); end if;
    if not coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 승격된 행이 정산되지 않았다 (A2가 그대로)'; end if;
    if (select b.status::text from bookings b where b.id = b4) <> 'completed'
      then v_bad := v_bad || ' 해결 뒤 completed가 아니다'; end if;
    select count(*) into v_n from ledger_items li where li.booking_id = b4;
    if v_n <> 1 then v_bad := v_bad || ' 원장 행 수=' || v_n; end if;
    if not exists (select 1 from return_resolutions
                   where booking_id = b4 and from_status = 'incident_review'
                     and not runner_stamped and not owner_stamped)
      then v_bad := v_bad || ' 저널이 0스탬프 승격을 그렇게 기록하지 않았다'; end if;
    if coalesce((runner_work_gate(rz)->>'gated')::boolean, true)
      then v_bad := v_bad || ' 해결 뒤에도 러너가 묶여 있다'; end if;

    -- ⓒ THE OTHER HALF OF A2, on its own fixture: both parties DID say the dog is home, late —
    -- 0096 lets the stamps land and deliberately refuses to seal, so the run still cannot settle.
    b5 := t_crs_live(oz, dz, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(b5, 3.0, 900, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_crs_age(b5, interval '5 hours');
    perform sweep_run_end_recovery();
    if (select b.status::text from bookings b where b.id = b5) <> 'incident_review'
      then v_bad := v_bad || ' 둘째 픽스처가 승격되지 않았다'; end if;
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform confirm_return_tx(b5, 'runner');
    perform set_config('request.jwt.claim.sub', oz::text, false);
    v_js := confirm_return_tx(b5, 'owner');
    perform set_config('request.jwt.claim.sub', '', false);
    if not coalesce((v_js->>'both_confirmed')::boolean, false) then v_bad := v_bad || ' 늦은 양측 스탬프가 기록되지 않았다'; end if;
    if (select b.settlement_ready_at from bookings b where b.id = b5) is not null
      then v_bad := v_bad || ' incident_review에서 봉인이 찍혔다 (0096 위반)'; end if;
    if exists (select 1 from ledger_items li where li.booking_id = b5)
      then v_bad := v_bad || ' 늦은 양측 스탬프가 정산했다'; end if;
    v_js := ops_resolve_return_tx(b5, t_crs_quote(3.0), '양측 뒤늦게 확인 — 정산 진행', ops);
    if not coalesce((v_js->>'settled')::boolean, false) then v_bad := v_bad || ' 양측이 확인한 승격 행이 정산되지 않았다'; end if;
    if not exists (select 1 from return_resolutions
                   where booking_id = b5 and runner_stamped and owner_stamped)
      then v_bad := v_bad || ' 저널이 양측 확인을 기록하지 않았다'; end if;
    select count(*) into v_n from ledger_items li where li.booking_id = b5;
    if v_n <> 1 then v_bad := v_bad || ' 둘째 픽스처 원장 행 수=' || v_n; end if;

    if v_bad = ''
      then call _pass('crs','0193-R2 0스탬프 타임아웃이 돈의 막다른 길에서 나온다 — 실제 스윕이 만든 incident_review 행은 오늘도 _settle_sealed_run에 not_active로 막히고 러너는 묶여 있지만(고치지 않은 채 재현한 팔), ops 해결이 그 행을 completed·원장 1행으로 끝내고 러너를 푼다. 양측이 뒤늦게 확인한 행(0096은 스탬프는 받고 봉인은 하지 않는다)도 같은 문으로 정산된다');
    else v_msg := v_bad; call _fail('crs','0193-R2 승격된 행도 정산에 도달한다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('crs','0193-R2 승격된 행도 정산에 도달한다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0193-R3] THE REFUSALS — and the sharpest arm is the one that proves the gate is FIRST
  -- 🔴 A non-ops caller must get the SAME answer for a booking that exists and one that does not.
  --    If the gate sat after the lock, the two would differ (`not_ops` vs `not_found`) and this
  --    endpoint would be an oracle for which bookings are stranded. That arm is the only thing
  --    that can tell 「gated」 from 「gated in the right place」.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    b6 := t_crs_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b6, 3.0, 900, 'completed', null, null);
    perform confirm_return_tx(b6, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_crs_age(b6, interval '5 hours');

    -- ⓐ a real person who is not on the roster
    begin
      perform ops_resolve_return_tx(b6, t_crs_quote(3.0), '내 예약이니까', oz);
      v_bad := v_bad || ' 비ops가 남의 좌초를 정산했다';
    exception when others then
      if sqlerrm <> 'not_ops' then v_bad := v_bad || ' 비ops 거절 이름=' || sqlerrm; end if;
    end;
    -- ⓑ …and a booking that DOES NOT EXIST answers identically. This is 「refused before any read」.
    begin
      perform ops_resolve_return_tx(gen_random_uuid(), t_crs_quote(3.0), '떠보기', oz);
      v_bad := v_bad || ' 없는 예약에 대해서도 통과했다';
    exception when others then
      if sqlerrm <> 'not_ops' then v_bad := v_bad || ' 🔴 없는 예약의 거절 이름이 다르다=' || sqlerrm || ' (게이트가 읽기보다 뒤에 있다 — 예약 존재 여부의 오라클)'; end if;
    end;
    -- ⓒ no actor at all
    begin
      perform ops_resolve_return_tx(b6, t_crs_quote(3.0), '메모', null);
      v_bad := v_bad || ' actor 없이 통과했다';
    exception when others then
      if sqlerrm <> 'ops_actor_required' then v_bad := v_bad || ' actor 부재 거절 이름=' || sqlerrm; end if;
    end;
    -- ⓓ a PHONE may not adjudicate, even the ops person's phone (0089's rule for force_return_tx)
    perform set_config('request.jwt.claim.sub', ops::text, false);
    begin
      perform ops_resolve_return_tx(b6, null, '내 폰에서 바로', ops);
      v_bad := v_bad || ' 신원 있는 호출자가 판정했다';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' 폰 거절 이름=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    -- ⓔ argument sanity, both of them
    begin
      perform ops_resolve_return_tx(b6, t_crs_quote(3.0), '   ', ops);
      v_bad := v_bad || ' 빈 메모로 판정됐다';
    exception when others then
      if sqlerrm <> 'memo_required' then v_bad := v_bad || ' 빈 메모 거절 이름=' || sqlerrm; end if;
    end;
    begin
      perform ops_resolve_return_tx(b6, null, '가격 없이', ops);
      v_bad := v_bad || ' 가격 없이 판정됐다 (정산 없는 봉인이 생긴다)';
    exception when others then
      if sqlerrm <> 'quote_required' then v_bad := v_bad || ' 무가격 거절 이름=' || sqlerrm; end if;
    end;
    -- ⓕ a sealed row is refused BY NAME — it is arm ⓐ's subject, not this door's (0083 §0f).
    -- 🔴 ITS OWN FIXTURE, and the first version BORROWED Q2's `b2`. Measured in the battery: under
    --    the plant that reddens Q2, this arm reported `not_found` — because a plpgsql
    --    `begin … exception` block is a SUBTRANSACTION, so Q2's caught raise rolled its fixture
    --    back and this arm was probing a booking that no longer existed. The refusal was still
    --    RED, so nothing was hidden; what was lost is the arm's MEANING, which is the
    --    fixture-inheritance law (「a pin that inherits another pin's setup is testing the setup」)
    --    arriving through a door nobody watches: the rollback boundary of a neighbouring pin.
    b_sealed := t_crs_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b_sealed, 3.0, 1100, 'completed', null, null);
    perform confirm_return_tx(b_sealed, 'runner');
    perform set_config('request.jwt.claim.sub', oo::text, false);
    perform confirm_return_tx(b_sealed, 'owner');            -- client-class: seals, settles nothing
    perform set_config('request.jwt.claim.sub', '', false);
    if (select b.settlement_ready_at from bookings b where b.id = b_sealed) is null
      then v_bad := v_bad || ' ⓕ 픽스처가 봉인되지 않았다 (already_sealed를 시험할 수 없다)'; end if;
    begin
      perform ops_resolve_return_tx(b_sealed, t_crs_quote(3.0), '봉인된 행', ops);
      v_bad := v_bad || ' 봉인된 행이 이 문으로 들어왔다';
    exception when others then
      if sqlerrm <> 'already_sealed' then v_bad := v_bad || ' 봉인 행 거절 이름=' || sqlerrm; end if;
    end;
    -- NOTHING above touched the booking
    if (select b.status::text from bookings b where b.id = b6) <> 'active'
      then v_bad := v_bad || ' 거절들이 상태를 옮겼다'; end if;
    if (select b.return_forced_by from bookings b where b.id = b6) is not null
      then v_bad := v_bad || ' 거절들이 ops 마커를 남겼다'; end if;
    if exists (select 1 from return_resolutions where booking_id = b6)
      then v_bad := v_bad || ' 거절들이 저널을 남겼다'; end if;
    if exists (select 1 from ledger_items li where li.booking_id = b6)
      then v_bad := v_bad || ' 거절들이 원장을 남겼다'; end if;

    -- ⓖ THE PRECONDITION. A PARTY cannot walk their own case back out of review by a direct
    --    UPDATE, executed AS `authenticated` — which is what a phone actually is.
    -- 🔴 MEASURED, AND IT CORRECTED THIS PIN'S OWN PREMISE. The draft asserted the refusal would
    --    come from §C-a's role conjunct (「0057 admits a party update and `_guard_booking_cols`
    --    does not protect `status`」). The harness answered `booking_protected_columns`: **0058 F3
    --    promoted that guard from a column blacklist to a DENY-ALL** (`if current_user in
    --    ('authenticated','anon') and new is distinct from old then raise`), so a party's direct
    --    UPDATE of a booking dies before the transition map is consulted at all.
    --    So this arm pins what is TRUE — the party path is closed, and closed by that guard, by
    --    NAME, so a future relaxation of the deny-all shows up here — and §C-a's role conjunct is
    --    a BELT behind it.
    -- ⚠ NAMED GAP rather than a reshaped pin (the house law): the role conjunct is **not
    --    separately observable in this harness**. A client-role caller dies at the deny-all, and
    --    every other caller here is `postgres`, for whom the conjunct is always true. It is pinned
    --    by SOURCE in `0193-S1`; the behavioural arm belongs to whoever relaxes 0058 F3.
    b7 := t_crs_live(oz, dz, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(b7, 3.0, 1000, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_crs_age(b7, interval '5 hours');
    perform sweep_run_end_recovery();
    if (select b.status::text from bookings b where b.id = b7) <> 'incident_review'
      then v_bad := v_bad || ' ⓖ 픽스처가 승격되지 않았다'; end if;
    perform set_config('request.jwt.claim.sub', oz::text, false);
    set role authenticated;
    begin
      update bookings set status = 'active', return_forced_by = 'ops', return_forced_at = now()
       where id = b7;
      v_bad := v_bad || ' 🔴 당사자가 직접 incident_review를 되돌렸다 (판정 우회)';
    exception when others then
      -- BY NAME, not 「something refused」: 0058 F3's deny-all is what closes this today, and if a
      -- future slice narrows it back to a column list the refusal changes name here rather than
      -- disappearing silently.
      if sqlerrm <> 'booking_protected_columns'
        then v_bad := v_bad || ' 당사자 직접 UPDATE 거절 이름=' || sqlerrm; end if;
    end;
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);
    if (select b.status::text from bookings b where b.id = b7) <> 'incident_review'
      then v_bad := v_bad || ' 당사자의 직접 UPDATE가 상태를 옮겼다'; end if;
    -- CONTROL: the same edge IS available to the ops door, so the refusal above is about WHO
    -- asked and not about the edge being closed to everybody.
    v_js := ops_resolve_return_tx(b7, t_crs_quote(3.0), '당사자 우회 대조', ops);
    if (select b.status::text from bookings b where b.id = b7) <> 'completed'
      then v_bad := v_bad || ' 대조: ops도 이 행을 옮기지 못했다 (전이 간선 자체가 막혔다)'; end if;

    if v_bad = ''
      then call _pass('crs','0193-R3 판정 문은 ops만, 그리고 게이트가 읽기보다 먼저다 — 명부에 없는 사람은 **존재하는 예약과 존재하지 않는 예약에 똑같이 not_ops**를 받고(존재 여부 오라클이 되지 않는다), actor 부재·폰 호출·빈 메모·무가격·이미 봉인된 행은 각각 이름으로 거절되며 예약에는 상태·마커·저널·원장 어느 것도 남지 않는다. 그리고 incident_review→active 간선은 당사자의 직접 UPDATE로는 열리지 않고(authenticated로 실행 — 0058 F3의 deny-all이 booking_protected_columns로 먼저 막는다. 이름으로 고정했으므로 그 가드가 완화되면 여기서 이름이 바뀐다; §C-a의 역할 조건은 그 뒤의 벨트이고 이 하네스에서는 단독 관측이 불가능하다 — 명시된 갭이며 0193-S1이 소스로 고정한다) ops 문으로는 열린다(대조)');
    else v_msg := v_bad; call _fail('crs','0193-R3 판정 문의 거절들', v_msg); end if;
  exception when others then reset role; perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('crs','0193-R3 판정 문의 거절들', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0193-R4] THE BELL, AND ITS OFF SWITCH — `return_strand_minutes` NULL is the shipped state
  -- 🔴 The OFF arm is the one that matters and it is the easy one to skip: a flag that ships NULL
  --    and an arm that ignores the flag are indistinguishable until somebody looks.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- CONTROL ①: the shipped value really is NULL (③)
    if (select f.return_strand_minutes from ops_flags f where f.id) is not null
      then v_bad := v_bad || ' 출하 플래그가 NULL이 아니다'; end if;

    b8 := t_crs_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(b8, 4.5, 1600, 'completed', null, null);
    perform confirm_return_tx(b8, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_crs_age(b8, interval '5 hours');

    perform sweep_run_end_recovery();
    select count(*) into v_n from notifications where ref_id = b8 and title = '반환 좌초 — 확인 필요';
    if v_n <> 0 then v_bad := v_bad || ' NULL 플래그인데 ops에 알렸다=' || v_n; end if;
    -- CONTROL ②: the sweep DID run over this row — 0188 ⓑ-②'s alarm fired. Without this arm,
    -- 「the strand arm is inert」 and 「the sweep never saw the row」 are the same green.
    select count(*) into v_n from notifications where ref_id = b8 and title = '반환 확인이 멈춰 있어요';
    if v_n <> 2 then v_bad := v_bad || ' 대조: 스윕이 이 행을 아예 보지 않았다 (ⓑ-② 통지=' || v_n || ')'; end if;

    -- arm it
    update ops_flags set return_strand_minutes = 60, updated_at = now() where id;
    perform sweep_run_end_recovery();
    select count(*) into v_n from notifications
     where ref_id = b8 and title = '반환 좌초 — 확인 필요' and profile_id = ops and kind = 'system';
    if v_n <> 1 then v_bad := v_bad || ' 플래그를 켰는데 ops 통지=' || v_n || ' (1이어야)'; end if;
    -- the body carries NO id and NO amount (0084 §E)
    if exists (select 1 from notifications
               where ref_id = b8 and title = '반환 좌초 — 확인 필요' and body like '%' || b8::text || '%')
      then v_bad := v_bad || ' ops 본문에 예약 id가 들어 있다'; end if;
    -- EXACTLY ONCE ACROSS TWO TICKS
    perform sweep_run_end_recovery();
    select count(*) into v_n from notifications where ref_id = b8 and title = '반환 좌초 — 확인 필요';
    if v_n <> 1 then v_bad := v_bad || ' 두 번째 틱이 중복 통지했다=' || v_n; end if;

    -- a YOUNGER strand is not told — the deadline is a predicate, not decoration
    b9 := t_crs_live(oz, dz, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(b9, 3.0, 600, 'completed', null, null);
    perform confirm_return_tx(b9, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_crs_age(b9, interval '10 minutes');
    perform sweep_run_end_recovery();
    select count(*) into v_n from notifications where ref_id = b9 and title = '반환 좌초 — 확인 필요';
    if v_n <> 0 then v_bad := v_bad || ' 10분 된 반환이 좌초로 보고됐다=' || v_n; end if;
    -- …and it IS told once it ages past the deadline (the same row, so the arm is not simply blind)
    perform t_crs_age(b9, interval '3 hours');
    perform sweep_run_end_recovery();
    select count(*) into v_n from notifications where ref_id = b9 and title = '반환 좌초 — 확인 필요';
    if v_n <> 1 then v_bad := v_bad || ' 마감을 넘긴 뒤에도 보고되지 않았다=' || v_n; end if;

    -- ③ put the flag back to the value production ships with
    update ops_flags set return_strand_minutes = null, updated_at = now() where id;
    if (select f.return_strand_minutes from ops_flags f where f.id) is not null
      then v_bad := v_bad || ' 플래그를 되돌리지 못했다 (뒤 스위트가 다른 세상을 본다)'; end if;

    if v_bad = ''
      then call _pass('crs','0193-R4 좌초 벨과 그 끄기 스위치 — return_strand_minutes가 NULL이면(출하 값) 팔은 아무것도 하지 않고(대조: 같은 행에서 0188 ⓑ-②는 발화하므로 스윕은 그 행을 분명히 보았다), 켜면 return_strand 명부에 정확히 1건이 가고(본문에 예약 id 없음) 두 번째 틱은 아무것도 더 하지 않으며, 마감 이전의 반환은 보고되지 않다가 마감을 넘기면 보고된다');
    else v_msg := v_bad; call _fail('crs','0193-R4 좌초 벨과 끄기 스위치', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    update ops_flags set return_strand_minutes = null where id;
    v_msg := sqlerrm; call _fail('crs','0193-R4 좌초 벨과 끄기 스위치', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0193-B5] 「귀가 확인이 필요해요」 PUSHES WITH 예약 알림 OFF — measured through the REAL sweep
  -- codex B5's own instruction: 「test the real escalation with booking notifications disabled
  -- rather than pinning the urgent family to exactly three titles」. So nothing here probes a
  -- title: the janitor writes the row and `notify_push` decides, exactly as in production.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    ob := t_user('crs_b5_o', 'owner');
    rb := t_user('crs_b5_r', 'runner');
    db := t_dog(ob, 'B5견');
    insert into push_tokens (profile_id, token) values (ob, 'ExponentPushToken[crs-b5-owner]');
    -- every preference OFF — the state that silenced this push before 0193
    perform set_config('request.jwt.claim.sub', ob::text, false);
    perform set_notification_prefs(false, false, false, false);
    perform set_config('request.jwt.claim.sub', '', false);

    bb := t_crs_live(ob, db, rt, rb);
    perform set_config('request.jwt.claim.sub', rb::text, false);
    perform end_run_tx(bb, 3.5, 1300, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_crs_age(bb, interval '5 hours');

    -- CONTROL, taken FIRST: an ordinary booking notification to this owner is SILENCED. Without
    -- it, 「the escalation pushed」 is equally consistent with 「this fixture pushes everything」.
    v_before := t_crs_pushes('ExponentPushToken[crs-b5-owner]', '일정 변경 요청');
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (ob, 'booking', '일정 변경 요청', 'b5 대조', bb);
    v_after := t_crs_pushes('ExponentPushToken[crs-b5-owner]', '일정 변경 요청');
    if v_after - v_before <> 0
      then v_bad := v_bad || ' 대조: 평범한 booking 알림도 푸시됐다 (이 픽스처는 아무것도 못 막는다)'; end if;

    v_before := t_crs_pushes('ExponentPushToken[crs-b5-owner]', '귀가 확인이 필요해요');
    perform sweep_run_end_recovery();
    v_after := t_crs_pushes('ExponentPushToken[crs-b5-owner]', '귀가 확인이 필요해요');
    if (select b.status::text from bookings b where b.id = bb) <> 'incident_review'
      then v_bad := v_bad || ' 픽스처가 승격되지 않았다 (승격 알림 자체가 없다)'; end if;
    if v_after - v_before <> 1
      then v_bad := v_bad || ' 🔴 예약 알림 off에서 귀가 승격이 침묵했다 (푸시 델타=' || (v_after - v_before) || ')'; end if;
    -- the row itself is written as SAFETY — classified at the WRITER, which is the half that
    -- covers every future row without relying on a title list
    if not exists (select 1 from notifications
                   where ref_id = bb and title = '귀가 확인이 필요해요' and profile_id = ob
                     and kind = 'safety')
      then v_bad := v_bad || ' 승격 행이 kind=safety로 쓰이지 않았다 (제목 목록에만 의존하게 된다)'; end if;
    -- …and the BELT, for rows a pre-0193 tick already wrote as `booking`: the same title with the
    -- old kind still pushes. Two closures, and a pin that saw only one would call it done.
    v_before := t_crs_pushes('ExponentPushToken[crs-b5-owner]', '귀가 확인이 필요해요');
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (ob, 'booking', '귀가 확인이 필요해요', '0193 이전에 쓰인 행', bb);
    v_after := t_crs_pushes('ExponentPushToken[crs-b5-owner]', '귀가 확인이 필요해요');
    if v_after - v_before <> 1
      then v_bad := v_bad || ' 0193 이전 형태(kind=booking)의 승격 행이 침묵했다 (벨트가 없다)'; end if;

    if v_bad = ''
      then call _pass('crs','0193-B5 귀가 승격은 예약 알림을 꺼도 도착한다 — 실제 스윕이 쓴 행이 kind=safety로 분류돼 네 스위치가 모두 false인 수신자에게 푸시되고(대조: 같은 수신자의 평범한 booking 알림은 그대로 침묵한다), 0193 이전에 kind=booking으로 쓰인 같은 제목의 행도 긴급 제목 벨트로 도착한다 — 두 겹 다 측정된다');
    else v_msg := v_bad; call _fail('crs','0193-B5 귀가 승격은 꺼지지 않는다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('crs','0193-B5 귀가 승격은 꺼지지 않는다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0193-C9] THE PRE-0190 ORPHAN — tombstoned, fully paid, and reachable by nothing
  -- ⚠ ④ the tombstone is stamped by hand ON PURPOSE: today's `delete_my_account_tx` (0190 §B)
  --   already releases a fully-paid runner's row, so the orphan can only be manufactured the way
  --   it actually arose — a deletion that ran under the OLD code.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    c_o  := t_user('crs_c9_o', 'owner');
    c_d  := t_dog(c_o, 'C9견');
    c_rt := t_route('C9 코스');
    c_tomb := t_user('crs_c9_tomb', 'runner');   -- tombstoned + fully paid  → RELEASE
    c_live := t_user('crs_c9_live', 'runner');   -- live + fully paid        → KEEP (control)
    c_owed := t_user('crs_c9_owed', 'runner');   -- tombstoned + still owed  → KEEP (control)
    insert into bank_accounts (runner_id, bank, account_enc, holder) values
      (c_tomb, '토스뱅크', 'ENC-C9-TOMB', '김탈퇴'),
      (c_live, '토스뱅크', 'ENC-C9-LIVE', '김현역'),
      (c_owed, '토스뱅크', 'ENC-C9-OWED', '김미지급');
    perform t_settle(t_active_booking(c_o, c_tomb, c_d, c_rt, now() - interval '3 days'), 'dog_condition');
    perform t_settle(t_active_booking(c_o, c_live, c_d, c_rt, now() - interval '3 days'), 'dog_condition');
    perform t_settle(t_active_booking(c_o, c_owed, c_d, c_rt, now() - interval '3 days'), 'dog_condition');
    -- a PRE-0190 payout: the rows are marked paid without 0190's release ever running
    insert into payouts (runner_id, period_start, period_end, gross, tax_withheld, net,
                         status, instant, paid_at, method)
    values (c_tomb, current_date - 3, current_date - 3, 24900, 0, 16683, 'paid', false, now(), 'manual')
    returning id into c_pay;
    update ledger_items set paid_payout_id = c_pay where runner_id = c_tomb;
    insert into payouts (runner_id, period_start, period_end, gross, tax_withheld, net,
                         status, instant, paid_at, method)
    values (c_live, current_date - 3, current_date - 3, 24900, 0, 16683, 'paid', false, now(), 'manual')
    returning id into c_pay;
    update ledger_items set paid_payout_id = c_pay where runner_id = c_live;
    -- …and the deletions that ran under the OLD code ④
    update profiles set deleted_at = now() - interval '10 days' where id in (c_tomb, c_owed);

    -- CONTROL: all three rows are present before the call. An absence pin over an empty world is
    -- the purest form of a green that licenses nothing (0151's measured lesson).
    select count(*) into v_n from bank_accounts where runner_id in (c_tomb, c_live, c_owed);
    if v_n <> 3 then v_bad := v_bad || ' 픽스처에 계좌 3행이 없다=' || v_n; end if;

    v_n := _release_orphan_bank_rows();
    if v_n < 1 then v_bad := v_bad || ' 해제된 행이 없다=' || v_n; end if;
    if exists (select 1 from bank_accounts where runner_id = c_tomb)
      then v_bad := v_bad || ' 🔴 탈퇴+전액지급 러너의 계좌가 남아 있다 (C9 그대로)'; end if;
    -- the two controls, and they fail under OPPOSITE mutations: 「always release」 fails the live
    -- one, 「never release」 fails the orphan, so no constant satisfies the three together
    if not exists (select 1 from bank_accounts
                   where runner_id = c_live and account_enc = 'ENC-C9-LIVE' and holder = '김현역')
      then v_bad := v_bad || ' 🔴 살아 있는 러너의 입금처가 삭제됐다'; end if;
    if not exists (select 1 from bank_accounts
                   where runner_id = c_owed and account_enc = 'ENC-C9-OWED' and holder = '김미지급')
      then v_bad := v_bad || ' 🔴 아직 지급할 돈이 남은 탈퇴 러너의 입금처가 삭제됐다'; end if;
    -- the ledger is evidence and is never touched by a retention decision
    select count(*) into v_n from ledger_items where runner_id = c_tomb;
    if v_n <> 1 then v_bad := v_bad || ' 해제가 원장을 건드렸다=' || v_n; end if;
    -- idempotent: a second call releases nothing more
    if _release_orphan_bank_rows() <> 0 then v_bad := v_bad || ' 두 번째 호출이 또 무언가를 해제했다'; end if;

    if v_bad = ''
      then call _pass('crs','0193-C9 0190 이전에 탈퇴하고 전액 지급된 러너의 보관 계좌가 해제된다 — 0190 §C는 새 payout 안에서만 해제하고 그런 러너에게는 새 payout이 없으며 탈퇴 재시도도 0115:227-234에서 조기 반환하므로, 이 함수가 없으면 그 행은 영원히 남는다. 대조 두 개는 반대 방향 변이에서 각각 빨개진다: 살아 있는 러너의 입금처는 남고, 아직 미지급이 있는 탈퇴 러너의 입금처도 남는다. 원장은 증거이므로 건드리지 않고, 재호출은 0행이다');
    else v_msg := v_bad; call _fail('crs','0193-C9 0190 이전 고아 계좌 해제', v_msg); end if;
  exception when others then
    v_msg := sqlerrm; call _fail('crs','0193-C9 0190 이전 고아 계좌 해제', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0193-S1] THE DEPLOYED SHAPE — because a property checked only at apply is protected exactly
  -- until somebody recreates the function (0131-G4). Comments are STRIPPED before every match:
  -- `prosrc` is source PLUS our prose and 0193 documents every predicate checked here, so an
  -- un-stripped read would be satisfied by the paragraph explaining the guard. Absence fails
  -- LOUDLY — a NULL `prosrc` makes every `~` NULL and every bare `if` silent.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ⓐ ops_resolve_return_tx
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'ops_resolve_return_tx';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(ops_resolve_return_tx)';
    else
      -- the gate PRECEDES the lock — the position, not the presence, is the property R3 ⓑ measures
      if not (position('ops_recipients_for(c_ops_class)' in v_src) > 0
              and position('ops_recipients_for(c_ops_class)' in v_src) < position('for update' in v_src))
        then v_bad := v_bad || ' ops 게이트가 잠금보다 뒤'; end if;
      if (v_src ~ 'c_ops_class constant text := ''return_strand''') is not true
        then v_bad := v_bad || ' ops 클래스 텍스트가 다르다'; end if;
      -- NO STAMP FORGERY, and it is matched as an ASSIGNMENT: the two column names also appear in
      -- the READS that build the journal row, so a bare word match would count those and be
      -- uninformative in both states
      if (v_src ~ 'runner_confirmed_return_at\s*=\s*') is true
        then v_bad := v_bad || ' 러너 스탬프를 쓴다 (위조)'; end if;
      if (v_src ~ 'owner_confirmed_return_at\s*=\s*') is true
        then v_bad := v_bad || ' 보호자 스탬프를 쓴다 (위조)'; end if;
      if (v_src ~ '_settle_sealed_run\(p_booking, p_quote\)') is not true
        then v_bad := v_bad || ' 정산 프리미티브를 쓰지 않는다'; end if;
      if (v_src ~ 'insert into return_resolutions') is not true
        then v_bad := v_bad || ' 저널을 쓰지 않는다'; end if;
      if (v_src ~ 'return_forced_by\s*=\s*''ops''') is not true
        then v_bad := v_bad || ' 0089의 ops 마커를 쓰지 않는다'; end if;
    end if;
    -- ⓑ confirm_return_tx's new gate, and the conjunct that narrows it
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'confirm_return_tx';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(confirm_return_tx)';
    else
      -- ⚠ MATCH THE GUARD, NOT THE VOCABULARY. The first version matched the bare strings
      -- `quote_required` and `v_uid is null`; a mutation replacing the guard with `if false then`
      -- left both in the body, so the pattern was present in the guarded and unguarded states
      -- alike — uninformative, inside the pin written to enforce rigour. (Q1 reddens behaviourally
      -- under that plant either way; this arm is what makes the SOURCE half mean something.)
      if (v_src ~ 'if v_seals_now and p_quote is null then') is not true
        then v_bad := v_bad || ' 가격 없는 봉인 가드가 없다 (죽은 raise는 이름만 남긴다)'; end if;
      if (v_src ~ 'raise exception ''quote_required''') is not true
        then v_bad := v_bad || ' quote_required 거절이 없다'; end if;
      if (v_src ~ 'v_seals_now := coalesce\(\s*v_uid is null') is not true
        then v_bad := v_bad || ' 서버 한정 조건이 봉인 예측의 첫 조건이 아니다 (클라의 봉인 능력이 사라진다)'; end if;
      if (v_src ~ 'quote_from_client') is not true then v_bad := v_bad || ' quote_from_client 유실'; end if;
      if (v_src ~ 'status not in \(''active'', ''incident_review''\)') is not true
        then v_bad := v_bad || ' 0096의 incident_review 팔 유실'; end if;
    end if;
    -- ⓒ the transition map's four conjuncts and its NULL defence
    select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'enforce_booking_transition';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(enforce_booking_transition)';
    else
      if (v_src ~ 'current_user not in \(''authenticated'', ''anon''\)') is not true
        then v_bad := v_bad || ' 전이맵: 클라 역할 판별 없음'; end if;
      if (v_src ~ 'new\.return_forced_by = ''ops''') is not true
        then v_bad := v_bad || ' 전이맵: ops 마커 조건 없음'; end if;
      if (v_src ~ 'old\.settlement_ready_at is null') is not true
        then v_bad := v_bad || ' 전이맵: 미봉인 조건 없음'; end if;
      if (v_src ~ 'ok is not true') is not true
        then v_bad := v_bad || ' 전이맵: NULL 붕괴 방어 없음 (NULL이면 모든 전이가 통과한다)'; end if;
    end if;
    -- ⓓ the definers' own shape and their ACL BY VALUE
    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public' and p.proname = 'ops_resolve_return_tx'
                     and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%')
      then v_bad := v_bad || ' 해결 RPC definer/search_path 형상 유실'; end if;
    if has_function_privilege('authenticated', 'public.ops_resolve_return_tx(uuid,jsonb,text,uuid)', 'execute') is not false
      then v_bad := v_bad || ' authenticated가 해결 RPC를 실행할 수 있다'; end if;
    if has_function_privilege('anon', 'public.ops_resolve_return_tx(uuid,jsonb,text,uuid)', 'execute') is not false
      then v_bad := v_bad || ' anon이 해결 RPC를 실행할 수 있다'; end if;
    if has_function_privilege('service_role', 'public.ops_resolve_return_tx(uuid,jsonb,text,uuid)', 'execute') is not true
      then v_bad := v_bad || ' service_role이 해결 RPC를 실행할 수 없다 (엣지가 죽는다 — 양성 대조)'; end if;
    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                   where n.nspname = 'public' and p.proname = '_release_orphan_bank_rows'
                     and p.prosecdef and array_to_string(p.proconfig, ',') like '%search_path=public, pg_temp%')
      then v_bad := v_bad || ' 고아 해제 definer/search_path 형상 유실'; end if;
    if has_function_privilege('authenticated', 'public._release_orphan_bank_rows()', 'execute') is not false
      then v_bad := v_bad || ' authenticated가 고아 해제를 실행할 수 있다'; end if;
    -- ⓔ the journal is SEALED (RLS on, zero policies, no client grant)
    if (select relrowsecurity from pg_class where oid = 'return_resolutions'::regclass) is not true
      then v_bad := v_bad || ' return_resolutions에 RLS가 없다'; end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'return_resolutions')
      then v_bad := v_bad || ' return_resolutions에 정책이 있다 (클라이언트 표면)'; end if;
    if has_table_privilege('authenticated', 'public.return_resolutions', 'select') is not false
      then v_bad := v_bad || ' authenticated가 판정 저널을 읽을 수 있다'; end if;
    if has_table_privilege('anon', 'public.return_resolutions', 'select') is not false
      then v_bad := v_bad || ' anon이 판정 저널을 읽을 수 있다'; end if;
    -- ⓕ the flag ships NULL-able and carries no default (a default would be a number nobody chose)
    if (select column_default from information_schema.columns
         where table_schema = 'public' and table_name = 'ops_flags'
           and column_name = 'return_strand_minutes') is not null
      then v_bad := v_bad || ' 좌초 플래그에 기본값이 있다 (아무도 고르지 않은 마감)'; end if;

    if v_bad = ''
      then call _pass('crs','0193-S1 배포 형상 — 해결 RPC는 definer+in-body search_path에 service_role 전용(authenticated·anon 모두 불가, 양성 대조 포함)이고 ops 게이트가 행 잠금보다 앞서며 당사자 스탬프에 대입하지 않고 _settle_sealed_run과 return_resolutions를 쓴다; confirm_return_tx는 quote_required와 이를 서버로 한정하는 v_uid is null을 모두 갖고 0096의 팔도 살아 있다; 전이맵은 네 조건과 ok is not true(NULL 붕괴 방어)를 갖는다; 판정 저널은 RLS 켜짐·정책 0개·클라 읽기 불가; 좌초 플래그에는 기본값이 없다 (주석 제거 후 매칭, 소스 부재는 큰 소리로 실패)');
    else v_msg := v_bad; call _fail('crs','0193-S1 배포 형상', v_msg); end if;
  exception when others then
    v_msg := sqlerrm; call _fail('crs','0193-S1 배포 형상', v_msg);
  end;
end $$;
