-- ═══ 230 — 0199: the ops adjudication becomes visible to the two people it was about ═══════════
-- ═══        0199-V1…V6 · H1 · S1, tag `rvz`                                              ═══
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a
-- pin written while staring at a mutation tends to assert what that mutation broke rather than
-- the property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · V1 The OWNER of a booking a real `ops_resolve_return_tx` call rescued gets exactly one row:
--        `resolved_at` equal to the JOURNAL row's `created_at` (not `now()`, not the booking's
--        `return_forced_at` — the pin reads the journal and compares), `rescued_from` the raw
--        server word `active`, and `note_public` the fixed 귀가 sentence.
--   · V2 The RUNNER of that same booking gets the IDENTICAL row. A separate proposition from V1
--        and not a re-print of it: a gate written `owner_id = auth.uid()` passes V1 and dies here,
--        and the runner is the party this rescue actually unblocks (0092's work gate).
--   · V3 The sentence is chosen BY `rescued_from`, measured in both directions — a booking
--        rescued from `incident_review` returns the OTHER sentence, and the two differ. A
--        hard-wired constant satisfies neither pair; V1/V2 alone cannot see one.
--   · V4 **PARTY BEFORE STATE.** A signed-in stranger gets `not_party` and learns NOTHING:
--        the same single word for (a) the resolved booking, (b) a uuid no booking has, and
--        (c) a real booking with no resolution at all. The id is therefore not an existence
--        oracle and not a resolution oracle. No caller ⇒ `not_authenticated`. Control: the party
--        passes on the same id in the same block, so 「refused」 cannot come from a broken session.
--   · V5 **THE OPS MEMO NEVER LEAVES THE SERVER.** The operator's sentence is written through the
--        REAL door with a sentinel in it, is genuinely present in the database afterwards
--        (`return_resolutions.memo` AND `bookings.return_force_reason` — the control that makes
--        「absent」 mean something), and appears in NO value of the party's row. The row has
--        exactly three columns and `memo` is not one of them, asserted by NAME off the catalog.
--        ⚠ An absence pin over a fixture that never contained the thing is worth zero (ui6's
--        `0151` N1/N2). The sentinel is the fixture containing the defect.
--   · V6 A party of a booking ops never touched gets ZERO ROWS and NO RAISE. 「운영팀이 개입한 적
--        없음」 is the ordinary state of every healthy run, and a raise there would make the
--        client's `catch` the normal path and teach the screen to read a transport failure as
--        「없음」.
--   · H1 0182 §A's `handoff_cycle_at` / `handoff_escalated_at` and 0183 §A's
--        `handoff_ops_alerted_at` are readable by a PARTY and invisible to a stranger through the
--        ordinary `bookings` read, executed AS `authenticated`. This is the measurement behind
--        0199 §0b's decision NOT to add a definer for them: the claim is that the existing grant
--        + `bookings party read` already answer correctly, and an unexecuted claim is prose.
--        `fetchBookingSync` now selects all three, and `handoff-escalation.ts` separates the last
--        two — 「운영팀에 알렸어요」 is bound to `handoff_ops_alerted_at` ALONE, because
--        `handoff_escalated_at` means only that the PARTIES were told (0183:86) and a strip that
--        conflated them would promise a waiting owner that ops is on it while the roster is empty
--        (0155). The pin asserts the read; the .cjs suite asserts the copy.
--   · S1 Deployed shape: definer, in-body `search_path`, ACL by effective privilege in BOTH
--        directions, the party gate BEFORE the journal read in the comment-STRIPPED source, no
--        `memo` / `return_force_reason` token in the body, and the journal still sealed (RLS on,
--        zero policies, `authenticated` cannot select it). NO-FUNCTION / NO-SOURCE arms fail
--        loudly rather than passing on an absence.
--
-- ─── FIXTURE NOTES ───
--  ① This suite builds its OWN world (its own owner, runner, stranger, dog, route, ops row) and
--     every count is scoped to its own booking ids. `return_resolutions` is shared with 224.
--  ② The `incident_review` fixture is reached by a DIRECT UPDATE (a legal edge, 0066:54) rather
--     than by running `sweep_run_end_recovery()`. The sweep is a global janitor and this suite's
--     propositions are about the READ; 224 `0193-R2` already pins that the sweep produces that
--     state from the product path, and re-running it here would let this file's fixture touch
--     rows other suites left behind.
--  ③ `request.jwt.claim.sub` is SESSION-scoped here (`set_config(..., false)`, 224's idiom) and
--     is cleared explicitly before the no-caller arm — a leftover claim would make
--     `not_authenticated` unreachable and that arm would pass for the wrong reason.
--  ④ H1's booking is INSERTed already carrying a handoff stamp, because `_handoff_cycle_tg`
--     (0183) derives `handoff_cycle_at` and will not take it from a statement; the escalation
--     record is then set by an UPDATE, which the trigger's `else` branch deliberately preserves.
--
-- ─── MUTATION MAP — measured 2026-09-22 against these exact files, not predicted ───
-- In the REGISTRY row. Lab: a copy of `supabase/` OUTSIDE the worktree, every plant
-- assert-verified and CHAIN-GATED to its harness run (`plant && harness`), control observed
-- clean FIRST.
set client_min_messages = warning;

-- ---------- suite-local fixtures ----------
-- A marketplace run that is LIVE (started, not stopped). Sibling of 224's `t_crs_live`; kept
-- suite-local rather than shared, so a later edit to 224's fixture cannot silently move this
-- file's subject.
create or replace function t_rvz_live(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid)
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

-- the quote the EDGE computes and hands to the RPC (a fixture, not a rule — 137 owns pricing)
create or replace function t_rvz_quote(p_km numeric) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'base', 9900, 'distance_pay', round(p_km * 3000)::int, 'addon_pay', 0,
    'guarantee', 0, 'fee', round((9900 + round(p_km * 3000)) * 0.2)::int)
$$;

create or replace function t_rvz_age(p_booking uuid, p_ago interval) returns void
language sql as $$
  with b as (update bookings set run_ended_at = now() - p_ago where id = p_booking returning id)
  update runs set ended_at = now() - p_ago where booking_id = (select id from b)
$$;

-- Call the party door as p_uid and report EITHER the rows OR the raise word — never both, and
-- never a swallowed success. The pins compare the WORD, so a refusal that changed its vocabulary
-- reddens instead of silently passing; and `n` is reported separately from the rows so that
-- 「zero rows」 and 「it raised」 are two different answers rather than one empty-looking one.
create or replace function t_rvz_read_as(p_uid uuid, p_booking uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  begin
    select coalesce(jsonb_agg(jsonb_build_object(
             'resolved_at', x.resolved_at,
             'rescued_from', x.rescued_from,
             'note', x.note_public)), '[]'::jsonb)
      into v from my_return_resolution(p_booking) x;
    return jsonb_build_object('rows', v, 'n', jsonb_array_length(v));
  exception when others then return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

do $$
declare
  oo    uuid;   -- the owner of the resolved bookings
  rr    uuid;   -- the runner of the resolved bookings
  sx    uuid;   -- a signed-in STRANGER, party to nothing here
  dg    uuid;
  rt    uuid;
  ops   uuid;   -- an active `return_strand` operator
  bA    uuid;   -- rescued from `active`      (the one-stamp strand)
  bI    uuid;   -- rescued from `incident_review` (0188 ⓑ-①'s zero-stamp timeout)
  bN    uuid;   -- a live booking ops never touched — V6's subject and V4's (c)
  bH    uuid;   -- H1's subject: a handoff that was escalated
  c_memo   constant text := '보호자와 통화 — RVZ-SENTINEL-8841 개는 집에 있다고 확인';
  c_note_a constant text := '운영팀이 귀가를 확인 처리했어요';
  c_note_i constant text := '운영팀이 검토 후 정산 처리했어요';
  v_js   jsonb;
  v_js2  jsonb;
  v_bad  text := '';
  v_msg  text;
  v_n    int;
  v_src  text;
  v_oid  oid;
  v_txt  text;
  v_ts   timestamptz;
begin
  perform set_config('request.jwt.claim.sub', '', false);
  oo  := t_user('rvz_owner',    'owner');
  rr  := t_user('rvz_runner',   'runner');
  sx  := t_user('rvz_stranger', 'owner');
  ops := t_user('rvz_ops',      'owner');
  dg  := t_dog(oo, '해결견');
  rt  := t_route('rvz 코스');
  insert into ops_recipients (profile_id, event_class, active)
  values (ops, 'return_strand', true) on conflict (profile_id, event_class) do nothing;

  -- ── the world, built through the REAL doors ──────────────────────────────────────────────
  -- bA: the runner stamped, the owner never did, five hours passed. 0188 ⓑ-② correctly refuses
  -- to move it; `ops_resolve_return_tx` is the exit 0193 §A built.
  bA := t_rvz_live(oo, dg, rt, rr);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform end_run_tx(bA, 4.0, 1500, 'completed', null, null);
  perform confirm_return_tx(bA, 'runner');
  perform set_config('request.jwt.claim.sub', '', false);
  perform t_rvz_age(bA, interval '5 hours');
  v_js := ops_resolve_return_tx(bA, t_rvz_quote(4.0), c_memo, ops);

  -- bI: nobody stamped; the row is in `incident_review` (fixture note ②) and ops adjudicates.
  bI := t_rvz_live(oo, dg, rt, rr);
  perform set_config('request.jwt.claim.sub', rr::text, false);
  perform end_run_tx(bI, 3.0, 1200, 'completed', null, null);
  perform set_config('request.jwt.claim.sub', '', false);
  perform t_rvz_age(bI, interval '5 hours');
  update bookings set status = 'incident_review' where id = bI;
  v_js2 := ops_resolve_return_tx(bI, t_rvz_quote(3.0), 'rvz CCTV 확인 — 귀가함', ops);

  -- bN: a live run nobody adjudicated.
  bN := t_rvz_live(oo, dg, rt, rr);

  -- 🔴 THE JOURNAL ROW IS BACK-DATED, and this line is the whole reason V1's instant arm means
  -- anything. `return_resolutions.created_at` defaults to `now()`, which in plpgsql is the
  -- TRANSACTION's start time — so a function that stamped its own `now()` instead of reading the
  -- journal would return the IDENTICAL value and V1 would be green on the defect. Measured:
  -- replacing `r.created_at` with `now()` reddened NOTHING until this line existed. The fixture
  -- must sit where the two candidate rules DISAGREE (CLAUDE.md, the fixture-agreement law), and
  -- an adjudication the parties read hours later is also the realistic case.
  update return_resolutions set created_at = created_at - interval '3 hours' where booking_id = bA;

  -- ① fixture honesty: the world this file asserts about is the world it thinks it built
  v_bad := '';
  if not coalesce((v_js->>'resolved')::boolean, false)  then v_bad := v_bad || ' bA가 해결되지 않았다'; end if;
  if (v_js->>'from_status') is distinct from 'active'   then v_bad := v_bad || ' bA from_status=' || coalesce(v_js->>'from_status','(null)'); end if;
  if not coalesce((v_js2->>'resolved')::boolean, false) then v_bad := v_bad || ' bI가 해결되지 않았다'; end if;
  if (v_js2->>'from_status') is distinct from 'incident_review'
    then v_bad := v_bad || ' bI from_status=' || coalesce(v_js2->>'from_status','(null)'); end if;
  select count(*)::int into v_n from return_resolutions where booking_id in (bA, bI);
  if v_n is distinct from 2 then v_bad := v_bad || ' 저널 행 수=' || v_n || ' (정확히 2)'; end if;
  if exists (select 1 from return_resolutions where booking_id = bN)
    then v_bad := v_bad || ' 손대지 않은 예약에 저널 행이 있다'; end if;
  if v_bad <> '' then v_msg := v_bad; call _fail('rvz','fixture', v_msg); v_bad := ''; end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0199-V1] the OWNER is told
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v_js := t_rvz_read_as(oo, bA);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 보호자 읽기가 거절됨: ' || (v_js->>'raised');
    else
      if (v_js->>'n')::int is distinct from 1 then v_bad := v_bad || ' 행 수=' || (v_js->>'n'); end if;
      if (v_js->'rows'->0->>'rescued_from') is distinct from 'active'
        then v_bad := v_bad || ' rescued_from=' || coalesce(v_js->'rows'->0->>'rescued_from','(null)'); end if;
      if (v_js->'rows'->0->>'note') is distinct from c_note_a
        then v_bad := v_bad || ' 문장=' || coalesce(v_js->'rows'->0->>'note','(null)'); end if;
      -- the INSTANT is the journal's own, not now() and not a second clock read. A screen prints
      -- this date beside the sentence; a function that stamped its own read time would look
      -- correct for exactly as long as nobody compared it with the record.
      select r.created_at into v_ts from return_resolutions r where r.booking_id = bA;
      if (v_js->'rows'->0->>'resolved_at')::timestamptz is distinct from v_ts
        then v_bad := v_bad || ' resolved_at이 저널의 created_at과 다르다'; end if;
    end if;
    if v_bad = '' then call _pass('rvz','0199-V1 보호자가 운영팀의 판정을 본다 — 정확히 1행, rescued_from=active(서버 원어), 고정 문장 「운영팀이 귀가를 확인 처리했어요」, 그리고 resolved_at은 저널 행의 created_at 그 값이다(읽는 시각이 아니라)');
    else v_msg := v_bad; call _fail('rvz','0199-V1 보호자 가시성', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('rvz','0199-V1 보호자 가시성', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0199-V2] the RUNNER is told the same thing — a gate keyed on `owner_id` passes V1 and dies
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v_js  := t_rvz_read_as(rr, bA);
    v_js2 := t_rvz_read_as(oo, bA);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 러너 읽기가 거절됨: ' || (v_js->>'raised');
    else
      if (v_js->>'n')::int is distinct from 1 then v_bad := v_bad || ' 러너 행 수=' || (v_js->>'n'); end if;
      -- IDENTICAL, not merely 「also non-empty」: the two parties must not be shown two different
      -- accounts of one decision.
      if (v_js->'rows') is distinct from (v_js2->'rows')
        then v_bad := v_bad || ' 러너와 보호자가 서로 다른 행을 받았다'; end if;
      if (v_js->'rows'->0->>'note') is distinct from c_note_a
        then v_bad := v_bad || ' 러너 문장=' || coalesce(v_js->'rows'->0->>'note','(null)'); end if;
    end if;
    if v_bad = '' then call _pass('rvz','0199-V2 러너도 같은 판정을 본다 — 보호자가 받은 행과 글자 그대로 동일(한 결정에 두 개의 서술이 존재하지 않는다); owner_id만 보는 게이트는 V1을 통과하고 여기서 죽는다');
    else v_msg := v_bad; call _fail('rvz','0199-V2 러너 가시성', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('rvz','0199-V2 러너 가시성', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0199-V3] the sentence is CHOSEN by rescued_from — both directions, so no constant passes
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v_js  := t_rvz_read_as(oo, bI);
    v_js2 := t_rvz_read_as(oo, bA);
    if v_js->>'raised' is not null then v_bad := v_bad || ' incident_review 읽기가 거절됨: ' || (v_js->>'raised');
    else
      if (v_js->'rows'->0->>'rescued_from') is distinct from 'incident_review'
        then v_bad := v_bad || ' rescued_from=' || coalesce(v_js->'rows'->0->>'rescued_from','(null)'); end if;
      if (v_js->'rows'->0->>'note') is distinct from c_note_i
        then v_bad := v_bad || ' incident 문장=' || coalesce(v_js->'rows'->0->>'note','(null)'); end if;
      -- the pair, which is what a constant cannot satisfy
      if (v_js->'rows'->0->>'note') = (v_js2->'rows'->0->>'note')
        then v_bad := v_bad || ' 두 구조 상태가 같은 문장을 냈다 (상수)'; end if;
    end if;
    if v_bad = '' then call _pass('rvz','0199-V3 문장은 rescued_from이 고른다 — incident_review 구조는 「운영팀이 검토 후 정산 처리했어요」이고 active 구조의 문장과 다르다; 어느 한쪽으로 고정된 상수는 두 팔을 동시에 만족시킬 수 없다');
    else v_msg := v_bad; call _fail('rvz','0199-V3 문장 선택', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('rvz','0199-V3 문장 선택', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0199-V4] PARTY BEFORE STATE — the id is neither an existence oracle nor a resolution oracle
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- (a) a real, RESOLVED booking the stranger is not party to
    v_js := t_rvz_read_as(sx, bA);
    if (v_js->>'raised') is distinct from 'not_party'
      then v_bad := v_bad || ' (a) 남의 해결된 예약 답=' || coalesce(v_js->>'raised', 'n=' || (v_js->>'n')); end if;
    -- (b) a uuid no booking has — must be the SAME word, or the refusal itself says 「이건 있다」
    v_js := t_rvz_read_as(sx, '00000000-0000-0000-0000-0000000019de'::uuid);
    if (v_js->>'raised') is distinct from 'not_party'
      then v_bad := v_bad || ' (b) 없는 예약 답=' || coalesce(v_js->>'raised', 'n=' || (v_js->>'n')); end if;
    -- (c) a real booking with NO resolution — same word again, so the refusal does not leak
    --     whether ops has ever been involved either
    v_js := t_rvz_read_as(sx, bN);
    if (v_js->>'raised') is distinct from 'not_party'
      then v_bad := v_bad || ' (c) 해결 없는 남의 예약 답=' || coalesce(v_js->>'raised', 'n=' || (v_js->>'n')); end if;
    -- (d) no caller at all
    v_js := t_rvz_read_as(null, bA);
    if (v_js->>'raised') is distinct from 'not_authenticated'
      then v_bad := v_bad || ' (d) 무기명 답=' || coalesce(v_js->>'raised', 'n=' || (v_js->>'n')); end if;
    -- (e) CONTROL, same id, same block: the party passes. Without it 「전부 거절」 is green.
    v_js := t_rvz_read_as(oo, bA);
    if (v_js->>'n')::int is distinct from 1
      then v_bad := v_bad || ' (e) 대조 실패: 당사자도 못 읽는다 ' || coalesce(v_js->>'raised', 'n=' || (v_js->>'n')); end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then call _pass('rvz','0199-V4 파티 게이트가 어떤 읽기보다 먼저 — 남에게는 해결된 예약·없는 uuid·해결 없는 예약 셋 다 not_party 한 단어라 id가 존재 오라클도 개입 오라클도 되지 않는다; 무기명은 not_authenticated; 같은 id에서 당사자는 통과(대조)');
    else v_msg := v_bad; call _fail('rvz','0199-V4 파티 게이트', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('rvz','0199-V4 파티 게이트', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0199-V5] THE OPS MEMO NEVER LEAVES — and the fixture contains the defect
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- CONTROL FIRST: the sentinel really is in the database. An absence pin over a world that
    -- never held the thing is worth exactly zero (0151 N1/N2's lesson), so this arm is what makes
    -- the three arms below mean anything.
    if (select r.memo from return_resolutions r where r.booking_id = bA) is distinct from c_memo
      then v_bad := v_bad || ' 대조 실패: 저널에 운영 메모가 없다'; end if;
    if (select b.return_force_reason from bookings b where b.id = bA) is distinct from c_memo
      then v_bad := v_bad || ' 대조 실패: 예약에 판정 사유가 없다'; end if;

    v_js := t_rvz_read_as(oo, bA);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 읽기가 거절됨: ' || (v_js->>'raised');
    else
      -- by VALUE, over the WHOLE returned row rather than over a column list: a memo that arrived
      -- concatenated into the sentence, or in a fourth column added later, is caught here too.
      v_txt := v_js->'rows'->>0;
      if (position('RVZ-SENTINEL-8841' in coalesce(v_txt, '')) > 0) is not false
        then v_bad := v_bad || ' 🔴 운영 메모가 당사자 행에 실렸다'; end if;
      if (position(c_memo in coalesce(v_txt, '')) > 0) is not false
        then v_bad := v_bad || ' 🔴 운영 메모 전문이 당사자 행에 실렸다'; end if;
    end if;
    -- the CONTRACT, off the catalog: exactly three output columns, named, and `memo` is not one.
    select count(*)::int into v_n from unnest((select proargnames from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'my_return_resolution')) a
     where a in ('resolved_at', 'rescued_from', 'note_public');
    if v_n is distinct from 3 then v_bad := v_bad || ' 출력 칸 이름 세 개가 아니다 (' || v_n || ')'; end if;
    if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname = 'my_return_resolution'
                 and ('memo' = any(coalesce(p.proargnames, '{}'))
                      or 'return_force_reason' = any(coalesce(p.proargnames, '{}'))))
      then v_bad := v_bad || ' 🔴 시그니처에 memo/판정사유 칸이 있다'; end if;
    if v_bad = '' then call _pass('rvz','0199-V5 운영 메모는 서버를 떠나지 않는다 — 실제 문(ops_resolve_return_tx)으로 쓴 센티넬 메모가 저널과 예약에는 분명히 있고(대조 2개: 부재 핀이 빈 세계 위에 서지 않도록) 당사자 행의 어떤 값에도 없다; 출력은 resolved_at·rescued_from·note_public 정확히 셋이고 memo는 시그니처에도 없다');
    else v_msg := v_bad; call _fail('rvz','0199-V5 운영 메모 비노출', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('rvz','0199-V5 운영 메모 비노출', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0199-V6] no adjudication ⇒ zero rows, and NOT an error
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    v_js := t_rvz_read_as(oo, bN);
    if v_js->>'raised' is not null
      then v_bad := v_bad || ' 🔴 해결 기록이 없는데 예외를 던졌다: ' || (v_js->>'raised');
    elsif (v_js->>'n')::int is distinct from 0
      then v_bad := v_bad || ' 행 수=' || (v_js->>'n'); end if;
    -- the same for the RUNNER side, because 「absence」 must not be an owner-only answer
    v_js := t_rvz_read_as(rr, bN);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 러너 쪽이 예외를 던졌다: ' || (v_js->>'raised');
    elsif (v_js->>'n')::int is distinct from 0 then v_bad := v_bad || ' 러너 쪽 행 수=' || (v_js->>'n'); end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = '' then call _pass('rvz','0199-V6 운영팀이 개입한 적 없으면 0행이고 예외가 아니다 — 양측 모두; 여기서 예외를 던지면 클라이언트의 catch가 정상 경로가 되고 화면은 진짜 통신 실패를 「없음」으로 읽게 된다');
    else v_msg := v_bad; call _fail('rvz','0199-V6 부재는 0행', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('rvz','0199-V6 부재는 0행', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0199-H1] the escalation record is a PARTY fact through the ordinary bookings read
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- This is the measurement behind 0199 §0b's decision not to build a definer for these two
  -- columns. Executed AS `authenticated`, which is the role the app actually holds.
  begin
    v_bad := '';
    insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
      base_fare, distance_fare, addon_fare, total_price, min_fare, owner_confirmed_handoff_at)
    values (oo, dg, rr, rt, 'confirmed', now() + interval '2 hours', 5.0,
            9900, 15000, 0, 24900, 9900, now() - interval '40 minutes')
    returning id into bH;
    -- fixture note ④: the cycle boundary is DERIVED by 0183's trigger (the insert minted it
    -- because the row was born with a stamp); the escalation records are set by an UPDATE, which
    -- the trigger's `else` branch preserves.
    update bookings set handoff_escalated_at   = now() - interval '10 minutes',
                        handoff_ops_alerted_at = now() - interval '9 minutes'
     where id = bH;
    if (select b.handoff_cycle_at from bookings b where b.id = bH) is null
      then v_bad := v_bad || ' 픽스처: handoff_cycle_at이 없다'; end if;
    if (select b.handoff_escalated_at from bookings b where b.id = bH) is null
      then v_bad := v_bad || ' 픽스처: handoff_escalated_at이 없다'; end if;
    if (select b.handoff_ops_alerted_at from bookings b where b.id = bH) is null
      then v_bad := v_bad || ' 픽스처: handoff_ops_alerted_at이 없다'; end if;

    perform set_config('request.jwt.claim.sub', oo::text, false);
    begin
      set local role authenticated;
      -- all THREE columns the client's `fetchBookingSync` projection now names. The ops column is
      -- asserted separately rather than folded in, because the strip's two sentences turn on it
      -- alone: a read that returned the escalation but not the ops alert would silently pin the
      -- copy to the weaker branch forever, and nothing else would notice.
      select count(*)::int into v_n from bookings
       where id = bH and handoff_escalated_at is not null and handoff_cycle_at is not null
         and handoff_ops_alerted_at is not null;
      if v_n is distinct from 1 then v_bad := v_bad || ' 보호자가 escalation 세 칸을 못 읽는다 (' || v_n || ')'; end if;
    exception when others then v_bad := v_bad || ' 보호자 읽기가 터졌다 [' || sqlstate || ' ' || sqlerrm || ']'; end;
    reset role;

    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      set local role authenticated;
      select count(*)::int into v_n from bookings
       where id = bH and handoff_escalated_at is not null and handoff_ops_alerted_at is not null;
      if v_n is distinct from 1 then v_bad := v_bad || ' 러너가 escalation을 못 읽는다 (' || v_n || ')'; end if;
    exception when others then v_bad := v_bad || ' 러너 읽기가 터졌다 [' || sqlstate || ' ' || sqlerrm || ']'; end;
    reset role;

    perform set_config('request.jwt.claim.sub', sx::text, false);
    begin
      set local role authenticated;
      select count(*)::int into v_n from bookings where id = bH;
      if v_n is distinct from 0 then v_bad := v_bad || ' 남이 그 예약 행을 읽었다 (' || v_n || ')'; end if;
      -- CONTROL: the stranger's session works — zero rows came from the POLICY, not from a
      -- broken claim. Without this arm a cleared jwt would make the stranger arm pass for free.
      select count(*)::int into v_n from bookings where owner_id = sx;
      if v_n is distinct from 0 then v_bad := v_bad || ' 대조 전제: 이방인이 예약을 갖고 있다'; end if;
      select count(*)::int into v_n from routes where id = rt;
      if v_n is distinct from 1 then v_bad := v_bad || ' 대조: 이방인 세션이 아예 아무것도 못 읽는다'; end if;
    exception when others then v_bad := v_bad || ' 남 읽기가 터졌다 [' || sqlstate || ' ' || sqlerrm || ']'; end;
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);

    if v_bad = '' then call _pass('rvz','0199-H1 인계 에스컬레이션은 당사자 사실이다 — authenticated로 실행해 보호자·러너는 handoff_cycle_at·handoff_escalated_at·handoff_ops_alerted_at 세 칸을 그대로 읽고 남은 그 예약을 0행으로 읽는다(대조: 같은 세션이 routes는 읽는다); 그래서 0199는 이 칸들에 definer를 더하지 않는다. ops 칸을 따로 단언하는 이유는 스트립의 두 문장이 그 칸 하나로 갈리기 때문이다 — 0183:86의 구분(당사자에게 알림 ≠ 운영 명부가 받음)');
    else v_msg := v_bad; call _fail('rvz','0199-H1 에스컬레이션 가시성', v_msg); end if;
  exception when others then reset role; perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('rvz','0199-H1 에스컬레이션 가시성', v_msg);
  end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0199-S1] the deployed shape
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'my_return_resolution';
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(my_return_resolution)';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' definer가 아니다'; end if;
      if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}'))
            from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 본문 search_path가 없다'; end if;
      -- ACL by EFFECTIVE privilege, in BOTH directions. A `create` that relied on grant
      -- preservation is born PUBLIC-executable (0116:636), and this reads a sealed journal.
      if has_function_privilege('anon', v_oid, 'execute') is not false
        then v_bad := v_bad || ' anon이 실행할 수 있다'; end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not true
        then v_bad := v_bad || ' authenticated가 실행할 수 없다'; end if;

      -- COMMENTS STRIPPED before matching. `prosrc` is source plus our own prose, and every
      -- sentence in 0199 §A names `memo` and `not_party` — an un-stripped match would be
      -- satisfied by the writing that EXPLAINS the guard (CLAUDE.md, the comment-matching law).
      select prosrc into v_src from pg_proc where oid = v_oid;
      if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(my_return_resolution)';
      else
        v_src := regexp_replace(v_src, '--[^' || chr(10) || ']*', '', 'g');
        if (v_src ~ 'not_party') is not true then v_bad := v_bad || ' not_party 거절이 없다'; end if;
        if (v_src ~ 'not_authenticated') is not true then v_bad := v_bad || ' not_authenticated 거절이 없다'; end if;
        if (position('not_party' in v_src) < position('return_resolutions' in v_src)) is not true
          then v_bad := v_bad || ' 파티 게이트가 저널 읽기보다 뒤에 있다'; end if;
        if (v_src ~ '\mmemo\M') is not false
          then v_bad := v_bad || ' 🔴 본문이 memo를 참조한다'; end if;
        if (v_src ~ 'return_force_reason') is not false
          then v_bad := v_bad || ' 🔴 본문이 return_force_reason을 참조한다'; end if;
        -- the crude/stripped control: the raw source DOES contain the words, so a stripper that
        -- silently did nothing would make the two arms above pass for the wrong reason.
        select prosrc into v_txt from pg_proc where oid = v_oid;
        if (v_txt ~ '\mmemo\M') is not true
          then v_bad := v_bad || ' 대조: 원본 소스에 memo라는 낱말이 아예 없다 (주석 제거 팔이 무의미)'; end if;
      end if;
    end if;
    -- the journal is STILL sealed — this slice answered a party without unsealing anything
    if (select relrowsecurity from pg_class where oid = 'return_resolutions'::regclass) is not true
      then v_bad := v_bad || ' 저널에 RLS가 없다'; end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'return_resolutions')
      then v_bad := v_bad || ' 저널에 정책이 생겼다 (클라이언트 표면)'; end if;
    if has_table_privilege('authenticated', 'public.return_resolutions', 'select') is not false
      then v_bad := v_bad || ' authenticated가 저널을 직접 읽는다'; end if;
    if has_table_privilege('anon', 'public.return_resolutions', 'select') is not false
      then v_bad := v_bad || ' anon이 저널을 직접 읽는다'; end if;
    if v_bad = '' then call _pass('rvz','0199-S1 배포 형상 — definer·본문 search_path·유효 권한으로 본 ACL 양방향(anon 불가·authenticated 가능); 주석 벗긴 소스에서 파티 거절이 저널 읽기보다 앞이고 memo·return_force_reason 낱말이 본문에 없다(원본에는 있다는 크루드 대조 포함); 저널은 여전히 봉인 — RLS 켜짐·정책 0개·anon도 authenticated도 직접 읽지 못한다; NO-FUNCTION·NO-SOURCE는 큰 소리로 실패');
    else v_msg := v_bad; call _fail('rvz','0199-S1 배포 형상', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('rvz','0199-S1 배포 형상', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
