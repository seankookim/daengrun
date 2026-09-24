-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 236 — 0205: force_return_tx writes a TOKEN, and the operator's sentence goes to the journal
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Tag `frt`. Pins 0205-F1 · F2 · F3 · S1.
--
-- ─── WHAT EACH PIN ESTABLISHES, WITHOUT REFERENCE TO ANY MUTATION ───
--  · **0205-F1** — after an ops force carrying a sentinel sentence, BOTH parties can read their
--        own booking row (the control that makes 「absent」 mean something) and the sentinel is in
--        NO value of it; `return_force_reason` is exactly `ops_forced`; the sentence is in the
--        sealed journal; and `my_return_resolution` — the one party-facing read of that journal —
--        returns 0199's FIXED sentence and never the sentinel. Read through the door a party
--        actually holds: role `authenticated`, that party's claim, the whole row.
--  · **0205-F2** — the journal row's SHAPE (`source`, the NULL actor, the rescued-from state, the
--        two stamp booleans as they were AT THE MOMENT, the memo), the IMMUTABILITY of the first
--        adjudication now that the column is a constant, and the table's two CHECKs refusing the
--        three shapes that would dissolve what §A kept.
--  · **0205-F3** — the scrub still identifies its own target set now that the world has a second
--        row kind. A 0193-shaped copy is repaired; a force row's `ops_forced` is NOT, although it
--        now HAS a journal row — which is the premise 0201 §B's comment relied on and 0205 §B
--        falsified. Measured as a DELTA the pin caused, not a state it found.
--  · **0205-S1** — the deployed shape of both re-declared functions and of the altered table.
--
-- ─── NAMED GAPS (facts about the system, not blind pins) ───
--  · **`return_force_evidence` — the gap this paragraph used to name is CLOSED by 0218 (2026-09-25).**
--    As of 0205 this file said: «`force_return_tx` requires evidence and stores the caller's
--    free-form jsonb in a party-readable column, so an operator who types prose into it leaks
--    prose … unpinned, because a pin over 「the caller chose good jsonb」 would be a pin over the
--    caller.» That was true of 0205's body and codex 2026-09-25 #3 found the hole it described.
--    0218 §B makes the column SERVER-COMPOSED (`_force_evidence_public`) and journals the
--    caller's object verbatim in the sealed `return_resolutions.evidence`; the pin is now over
--    the SERVER, and `249 0218-E1·E3·E4` own it (sentinel inside `p_evidence`, both parties,
--    whole row and direct select). This suite's F1 still supplies memo-less evidence on purpose:
--    its subject is the REASON column, and it is left as 0205 wrote it.
--  · 🔴 **The `else` arm of 0201 §A's token `case` stays unreachable from THIS door and is not
--    pinned here.** `force_return_tx` raises `not_active` on anything but `active`, so its journal
--    rows can only ever carry `from_status = 'active'`. F2 asserts that value; it does not and
--    cannot prove the scrub's other two arms, which are 232 `0201-M2`'s.
--  · **Client vocabulary is not pinned here and does not exist.** `grep -rn return_force_reason
--    app/` → 0; the token is machine-readable and the one sentence a party sees is 0199's.
--
-- ─── FIXTURE NOTES ───
--  ① This suite builds its OWN world (`t_frt_*`, `frt_` profiles) rather than borrowing 232's.
--     A pin that inherits another suite's setup is testing that setup (`175 V2`'s law), and 232's
--     fixtures move for 232's reasons.
--  ② Every force here is called WITHOUT a quote, so it seals and settles nothing (`0089`'s
--     unpriced branch, 119 `R17` ①). The money path is not what this file is about and dragging
--     `_settle_sealed_run` into the fixture would make every arm depend on pricing.
--  ③ F3 measures the scrub's own baseline FIRST — `_scrub_ops_return_reasons()` is called before
--     anything is planted and must return 0 — so the 1 it returns afterwards is a delta this pin
--     CAUSED rather than a number it found in a database eleven other suites have written to.
--  ④ F1's fixture carries exactly ONE party stamp (runner), so F2's two stamp booleans are
--     `true`/`false` rather than a matched pair a bug could produce by accident.
--
-- ─── MUTATION MAP — measured against these exact files, not predicted ───
-- In the REGISTRY row. Lab: a copy of `supabase/` OUTSIDE the worktree, every plant
-- assert-verified and CHAIN-GATED to its harness run (`plant && harness`).
set client_min_messages = warning;

-- ---------- suite-local fixtures ① ----------
-- A marketplace run that is LIVE (started, not stopped). Sibling of 232's `t_sml_live`.
create or replace function t_frt_live(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid)
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
create or replace function t_frt_quote(p_km numeric) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'base', 9900, 'distance_pay', round(p_km * 3000)::int, 'addon_pay', 0,
    'guarantee', 0, 'fee', round((9900 + round(p_km * 3000)) * 0.2)::int)
$$;

-- age a stopped run (the run row moves with it — a frozen stop whose `runs.ended_at` disagrees
-- with `bookings.run_ended_at` is not a state the product makes)
create or replace function t_frt_age(p_booking uuid, p_ago interval) returns void
language sql as $$
  with b as (update bookings set run_ended_at = now() - p_ago where id = p_booking returning id)
  update runs set ended_at = now() - p_ago where booking_id = (select id from b)
$$;

-- Read ONE booking row exactly as the app reads it — AS `authenticated`, under that party's claim,
-- whole row as JSON. Reports the row OR the raise, never both and never a swallowed success, so
-- 「the sentence is absent」 and 「nothing could be read at all」 are two different answers.
create or replace function t_frt_row_as(p_uid uuid, p_booking uuid) returns jsonb
language plpgsql as $$
declare v jsonb; v_n int;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  begin
    set local role authenticated;
    select count(*)::int into v_n from bookings b where b.id = p_booking;
    select to_jsonb(b) into v from bookings b where b.id = p_booking;
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);
    return jsonb_build_object('n', v_n, 'row', coalesce(v, 'null'::jsonb));
  exception when others then
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- One (party, booking) pair, fully judged: the row must be READABLE (the control that makes
-- 「absent」 mean something — an absence pin over an empty world licenses nothing, 0151's lesson)
-- and none of the needles may appear anywhere in it.
create or replace function t_frt_leak(p_who text, p_uid uuid, p_booking uuid, p_needles text[])
returns text language plpgsql as $$
declare v_js jsonb; v_bad text := ''; v_needle text;
begin
  v_js := t_frt_row_as(p_uid, p_booking);
  if v_js->>'raised' is not null then
    return ' ' || p_who || ' 읽기가 터졌다 [' || (v_js->>'raised') || ']';
  end if;
  if (v_js->>'n')::int is distinct from 1 then
    v_bad := v_bad || ' 대조: ' || p_who || '가 자기 예약을 못 읽는다 (n=' || coalesce(v_js->>'n','?') || ')';
  end if;
  foreach v_needle in array p_needles loop
    if (position(v_needle in coalesce(v_js->>'row', '')) > 0) is not false then
      v_bad := v_bad || ' 🔴 ' || p_who || '가 읽는 예약 행에 운영자 문장이 있다 (' || left(v_needle, 24) || ')';
    end if;
  end loop;
  return v_bad;
end $$;

-- the 0199 party-facing read, as one party, flattened — so F1 can assert the fixed sentence did
-- not silently become the operator's.
create or replace function t_frt_note_as(p_uid uuid, p_booking uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  begin
    select coalesce(jsonb_agg(jsonb_build_object(
             'rescued_from', x.rescued_from, 'note_public', x.note_public)), '[]'::jsonb)
      into v from my_return_resolution(p_booking) x;
    perform set_config('request.jwt.claim.sub', '', false);
    return jsonb_build_object('rows', v, 'n', jsonb_array_length(v));
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

do $$
declare
  oo uuid; rr uuid; dg uuid; rt uuid;
  oz uuid; rz uuid; dz uuid;
  ops uuid;                                  -- a rostered `return_strand` operator (F3 only)
  bF uuid;                                   -- F1/F2: the forced booking
  pR uuid; pF uuid;                          -- F3: a 0193-shaped planted copy + a force row
  c_tok   constant text := 'ops_forced';
  c_sent  constant text := '보호자 연락 두절 — FRT-SENTINEL-8821 운영자가 셸에서 판정';
  c_sent2 constant text := '내가 다시 쓴다 — FRT-SENTINEL-9902';
  c_memo  constant text := 'CCTV 확인 — FRT-MEMO-7734 귀가 확인됨';
  c_tok_s constant text := 'ops_resolved:strand';
  v_bad text := ''; v_msg text; v_js jsonb; v_n int; v_src text; v_raw text; v_oid oid;
  v_txt text;
begin
  perform set_config('request.jwt.claim.sub', '', false);
  oo := t_user('frt_oo', 'owner');   rr := t_user('frt_rr', 'runner');
  oz := t_user('frt_oz', 'owner');   rz := t_user('frt_rz', 'runner');
  dg := t_dog(oo, '강제견');          dz := t_dog(oz, '판정견');
  rt := t_route('강제 토큰 코스');
  ops := t_user('frt_ops', 'owner');
  insert into ops_recipients (profile_id, event_class, active) values (ops, 'return_strand', true)
  on conflict (profile_id, event_class) do nothing;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0205-F1] THE OPERATOR'S SENTENCE IS NOT A PARTY-READABLE FACT
  -- 🔴 Read through the door a party actually holds — role `authenticated`, that party's claim,
  --    the whole `bookings` row — because that is the door codex's #1 was about. A pin over the
  --    RPC's return would be green with the sentence sitting one PostgREST call away, which is
  --    exactly how 0199's V5 was green while 0193 was leaking.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ④ ONE party stamp, so F2's two booleans are not a matched pair
    bF := t_frt_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(bF, 4.0, 1500, 'completed', null, null);
    perform confirm_return_tx(bF, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_frt_age(bF, interval '5 hours');
    -- ② no quote: seals, settles nothing
    v_js := force_return_tx(bF, 'ops', c_sent, jsonb_build_object('kind', 'ops_review', 'src', 'frt'));

    -- CONTROL ①: the force actually happened. Without this every arm below is an absence pin
    -- over a booking nothing ever wrote to.
    if coalesce((v_js->>'forced')::boolean, false) is not true
      then v_bad := v_bad || ' 대조: 강제가 기록되지 않았다=' || coalesce(v_js::text, '(null)'); end if;
    if (select b.return_forced_by from bookings b where b.id = bF) is distinct from 'ops'
      then v_bad := v_bad || ' 대조: ops 마커가 없다'; end if;
    if (select b.settlement_ready_at from bookings b where b.id = bF) is null
      then v_bad := v_bad || ' 대조: 씰이 찍히지 않았다'; end if;
    -- CONTROL ②: the sentence really is in the database. An absence measured over a world that
    -- never held the thing is worth exactly zero (0151 N1/N2).
    if (select r.memo from return_resolutions r where r.booking_id = bF) is distinct from c_sent
      then v_bad := v_bad || ' 대조: 저널에 운영자 문장이 없다 (부재 팔이 무의미)'; end if;

    -- THE PROPERTY ①: the party-readable column carries the TOKEN
    if (select b.return_force_reason from bookings b where b.id = bF) is distinct from c_tok
      then v_bad := v_bad || ' 판정 토큰이 아니다=' ||
        coalesce((select b.return_force_reason from bookings b where b.id = bF), '(null)'); end if;

    -- THE PROPERTY ②: neither party can find the sentence anywhere in their own row
    v_bad := v_bad || t_frt_leak('보호자', oo, bF, array[c_sent, 'FRT-SENTINEL-8821']);
    v_bad := v_bad || t_frt_leak('러너',  rr, bF, array[c_sent, 'FRT-SENTINEL-8821']);

    -- THE PROPERTY ③: the one party-facing read of the journal (0199 §A) hands back the FIXED
    -- sentence and not the operator's. 0205 §A names this widening deliberately — a party whose
    -- return was forced now reads a true sentence rather than nothing — so it is pinned rather
    -- than discovered.
    v_js := t_frt_note_as(oo, bF);
    if v_js->>'raised' is not null
      then v_bad := v_bad || ' 보호자 0199 읽기가 터졌다 [' || (v_js->>'raised') || ']';
    else
      if (v_js->>'n')::int is distinct from 1
        then v_bad := v_bad || ' 보호자 0199 행 수=' || coalesce(v_js->>'n', '?'); end if;
      if (v_js->'rows'->0->>'note_public') is distinct from '운영팀이 귀가를 확인 처리했어요'
        then v_bad := v_bad || ' 보호자가 받은 문장=' ||
          coalesce(v_js->'rows'->0->>'note_public', '(null)'); end if;
      if (position('FRT-SENTINEL-8821' in coalesce(v_js::text, '')) > 0) is not false
        then v_bad := v_bad || ' 🔴 0199 읽기에 운영자 문장이 실렸다'; end if;
    end if;
    v_js := t_frt_note_as(rr, bF);
    if (v_js->'rows'->0->>'note_public') is distinct from '운영팀이 귀가를 확인 처리했어요'
      then v_bad := v_bad || ' 러너가 받은 문장=' ||
        coalesce(v_js->'rows'->0->>'note_public', '(null)'); end if;

    -- CONTROL ③: a STRANGER still gets nothing, so ③'s green is the party gate working rather
    -- than the journal being empty.
    v_js := t_frt_note_as(oz, bF);
    if (v_js->>'raised') is distinct from 'not_party'
      then v_bad := v_bad || ' 대조: 남이 0199를 읽었다=' || coalesce(v_js::text, '(null)'); end if;

    if v_bad = ''
      then call _pass('frt','0205-F1 운영자 문장은 당사자가 읽는 예약 행에 없다 — 셸 강제(force_return_tx)가 사유를 받으면 bookings.return_force_reason에는 고정 토큰 ops_forced만 남고 문장은 봉인된 return_resolutions에만 들어가며, 보호자·러너가 각자 authenticated로 자기 예약 행 전체를 읽어도(읽기 자체는 성공한다 — 대조) 문장도 센티널도 어디에도 없다; 0199의 당사자 읽기는 고정 한국어 문장을 돌려주고(강제 행도 이제 보인다 — 0205 §A가 이름 붙인 확장) 남에게는 not_party다');
    else v_msg := v_bad; call _fail('frt','0205-F1 운영자 문장 비노출', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('frt','0205-F1 운영자 문장 비노출', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0205-F2] THE JOURNAL ROW'S SHAPE, THE IMMUTABILITY IT NOW CARRIES, AND THE CHECKS
  -- 🔴 Immutability MOVED. While the column held free text, 「the second force did not overwrite
  --    the first」 was observable there (119 R6). With a constant in the column the two worlds are
  --    indistinguishable through it, so the journal is the only place the property can be read —
  --    which is why this pin asserts the row COUNT and the FIRST sentence, not the column.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- the shape, on F1's booking (one runner stamp, rescued from `active`). Each column is read
    -- on its own line rather than through one multi-column `into`: a `select … into a, b, c` that
    -- returns no row leaves every target NULL, and an `is distinct from` against NULL then reports
    -- the FIRST arm and hides that the row is simply missing.
    select r.source into v_txt from return_resolutions r where r.booking_id = bF;
    if v_txt is distinct from 'force_return_tx'
      then v_bad := v_bad || ' 저널 source=' || coalesce(v_txt, '(null)'); end if;
    if (select r.resolved_by from return_resolutions r where r.booking_id = bF) is not null
      then v_bad := v_bad || ' 🔴 저널에 행위자가 적혔다 (0089는 auth.uid()를 든 호출자를 거절한다 — 있을 수 없는 프로필)'; end if;
    if (select r.from_status from return_resolutions r where r.booking_id = bF) is distinct from 'active'
      then v_bad := v_bad || ' 저널 from_status=' ||
        coalesce((select r.from_status from return_resolutions r where r.booking_id = bF), '(null)'); end if;
    if (select r.runner_stamped from return_resolutions r where r.booking_id = bF) is not true
      then v_bad := v_bad || ' 저널: 러너 스탬프가 true가 아니다 (UPDATE 전 상태를 안 읽었다)'; end if;
    if (select r.owner_stamped from return_resolutions r where r.booking_id = bF) is not false
      then v_bad := v_bad || ' 저널: 보호자 스탬프가 false가 아니다'; end if;
    if (select r.memo from return_resolutions r where r.booking_id = bF) is distinct from c_sent
      then v_bad := v_bad || ' 저널 memo가 첫 문장이 아니다'; end if;
    -- 0089's rule survived the re-declaration: NO party confirmation stamp was forged
    if (select b.owner_confirmed_return_at from bookings b where b.id = bF) is not null
      then v_bad := v_bad || ' 🔴 강제가 보호자 확인 스탬프를 찍었다 (0089 §2 부활)'; end if;

    -- IMMUTABILITY, read where it is now observable. A second force with a DIFFERENT sentence.
    v_js := force_return_tx(bF, 'ops', c_sent2, jsonb_build_object('kind', 'ops_rewrite'));
    if coalesce((v_js->>'forced')::boolean, true) is not false
      then v_bad := v_bad || ' 두 번째 강제가 다시 기록됐다=' || coalesce(v_js::text, '(null)'); end if;
    select count(*)::int into v_n from return_resolutions where booking_id = bF;
    if v_n is distinct from 1
      then v_bad := v_bad || ' 🔴 두 번째 강제가 저널 행을 더 썼다 (행 수=' || v_n || ')'; end if;
    if (select r.memo from return_resolutions r where r.booking_id = bF) is distinct from c_sent
      then v_bad := v_bad || ' 🔴 두 번째 강제가 첫 문장을 덮었다'; end if;
    if (select b.return_force_reason from bookings b where b.id = bF) is distinct from c_tok
      then v_bad := v_bad || ' 두 번째 강제 뒤 토큰이 바뀌었다'; end if;
    -- …and the second sentence is nowhere a party can read it either
    v_bad := v_bad || t_frt_leak('보호자(2차)', oo, bF, array[c_sent2, 'FRT-SENTINEL-9902']);

    -- THE CHECKS. §A kept the resolver's invariant by moving it from the column to the source;
    -- these three arms are what make that a rule rather than a sentence in a comment.
    -- ⚠ [0218] EVERY INSERT BELOW NOW CARRIES `evidence`. 0218 §A added a third CHECK
    --    (`return_resolutions_evidence_check`: a force-kind row must carry evidence), so without
    --    it the CONTROL insert is refused and the three refusal arms stop measuring the constraint
    --    each is about — an evidence-less force row trips the evidence CHECK before the actor
    --    CHECK, and `check_violation` cannot tell which fired. The fixture now sits where ONLY the
    --    constraint under test disagrees. The evidence CHECK's own refusal is `249 0218-S1`'s.
    begin
      insert into return_resolutions (booking_id, resolved_by, from_status,
                                      runner_stamped, owner_stamped, memo, source, evidence)
      values (bF, ops, 'active', false, false, '위조된 행위자', 'force_return_tx', '{"kind": "frt"}'::jsonb);
      v_bad := v_bad || ' 🔴 강제 행이 행위자를 들고 들어왔다';
    exception when check_violation then null;
             when others then v_bad := v_bad || ' 강제+행위자 거절 이름=' || sqlerrm;
    end;
    begin
      insert into return_resolutions (booking_id, resolved_by, from_status,
                                      runner_stamped, owner_stamped, memo, source, evidence)
      values (bF, null, 'active', false, false, '행위자 없는 해결기 행', 'ops_resolve_return_tx', '{"kind": "frt"}'::jsonb);
      v_bad := v_bad || ' 🔴 해결기 행이 행위자 없이 들어왔다 (0193의 불변식이 녹았다)';
    exception when check_violation then null;
             when others then v_bad := v_bad || ' 해결기-행위자 거절 이름=' || sqlerrm;
    end;
    begin
      insert into return_resolutions (booking_id, resolved_by, from_status,
                                      runner_stamped, owner_stamped, memo, source, evidence)
      values (bF, null, 'active', false, false, '모르는 기록자', 'somebody_else', '{"kind": "frt"}'::jsonb);
      v_bad := v_bad || ' 🔴 모르는 source가 들어왔다';
    exception when check_violation then null;
             when others then v_bad := v_bad || ' 모르는 source 거절 이름=' || sqlerrm;
    end;
    -- CONTROL: the three refusals above are the CHECKs refusing, not the table refusing every
    -- insert. A well-shaped force row goes in — and comes straight back out, so no later arm and
    -- no later suite inherits it. (0218: well-shaped now includes `evidence`.)
    begin
      insert into return_resolutions (booking_id, resolved_by, from_status,
                                      runner_stamped, owner_stamped, memo, source, evidence)
      values (bF, null, 'active', true, false, '모양이 맞는 행', 'force_return_tx', '{"kind": "frt"}'::jsonb);
      delete from return_resolutions where booking_id = bF and memo = '모양이 맞는 행';
    exception when others then
      v_bad := v_bad || ' 대조: 모양이 맞는 강제 행도 거절됐다 (CHECK이 전부를 막는다)=' || sqlerrm;
    end;
    select count(*)::int into v_n from return_resolutions where booking_id = bF;
    if v_n is distinct from 1 then v_bad := v_bad || ' 대조 뒤 저널 행 수=' || v_n; end if;

    if v_bad = ''
      then call _pass('frt','0205-F2 저널 행의 모양과 첫 판정의 불변성 — 강제가 쓰는 행은 source=force_return_tx·행위자 NULL·from_status=active이고 두 스탬프 불린은 UPDATE 이전 상태(러너 true·보호자 false)이며 memo는 운영자 문장이다; 두 번째 강제는 저널 행을 더 쓰지도 첫 문장을 덮지도 않는다(칸이 상수가 된 뒤 불변성이 읽히는 유일한 자리) — 그리고 CHECK 둘이 세 가지 모양을 거절한다: 행위자를 든 강제 행·행위자 없는 해결기 행·모르는 source, 반면 모양이 맞는 강제 행은 통과한다(대조)');
    else v_msg := v_bad; call _fail('frt','0205-F2 저널 행의 모양', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('frt','0205-F2 저널 행의 모양', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0205-F3] THE SCRUB'S TARGET SET, AFTER THE WORLD GAINED A SECOND ROW KIND
  -- 🔴 0201 §B's comment states its targeting argument as a fact about the WORLD: «force_return_tx's
  --    rows write no journal row and are therefore outside the set BY CONSTRUCTION rather than by
  --    a filter someone has to remember.» 0205 §B falsifies that sentence. This pin is what notices
  --    if §C was not written — un-taught, the scrub relabels a shell force as a resolver rescue.
  -- ③ The baseline is measured, not assumed: the scrub is called BEFORE anything is planted and
  --    must return 0, so the 1 it returns afterwards is a delta this pin caused.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ③ the world is already clean (232 M2's global arm left it so). If it is not, every count
    --    below measures another suite's leftovers instead of this fixture.
    select _scrub_ops_return_reasons() into v_n;
    if v_n is distinct from 0
      then v_bad := v_bad || ' 대조: 심기 전 스크럽이 ' || coalesce(v_n::text, '(null)') || '행을 고쳤다 (기준선이 0이 아니다)'; end if;

    -- ⓐ a REAL resolver adjudication, then the PRE-0201 data shape planted back by hand. Today's
    --    resolver cannot produce the row the scrub exists to repair (232's fixture note ④).
    pR := t_frt_live(oz, dz, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(pR, 3.0, 1000, 'completed', null, null);
    perform confirm_return_tx(pR, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_frt_age(pR, interval '5 hours');
    perform ops_resolve_return_tx(pR, t_frt_quote(3.0), c_memo, ops);
    update bookings set return_force_reason = c_memo where id = pR;

    -- ⓑ a force row — which NOW has a journal row, which is the entire point of this pin
    pF := t_frt_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(pF, 3.0, 900, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_frt_age(pF, interval '5 hours');
    perform force_return_tx(pF, 'ops', c_sent, jsonb_build_object('source', 'frt fixture'));

    -- CONTROL: both plants landed, in the shape the scrub is about
    if (select b.return_force_reason from bookings b where b.id = pR) is distinct from c_memo
      then v_bad := v_bad || ' 대조: ⓐ의 옛 사본이 심기지 않았다'; end if;
    if (select b.return_force_reason from bookings b where b.id = pF) is distinct from c_tok
      then v_bad := v_bad || ' 대조: ⓑ에 강제 토큰이 없다'; end if;
    if (select b.return_forced_by from bookings b where b.id = pF) is distinct from 'ops'
      then v_bad := v_bad || ' 대조: ⓑ에 ops 마커가 없다 (조인 밖이라서가 아니라 마커가 없어서 남는다면 이 팔은 무의미)'; end if;
    -- 🔴 THE CONTROL THAT MAKES THIS PIN DIFFERENT FROM 232's: ⓑ IS in the journal now.
    if (select r.source from return_resolutions r where r.booking_id = pF) is distinct from 'force_return_tx'
      then v_bad := v_bad || ' 대조: ⓑ에 강제 저널 행이 없다 (조인 안에 있지 않으면 source 조건은 시험되지 않는다)'; end if;
    if (select r.source from return_resolutions r where r.booking_id = pR) is distinct from 'ops_resolve_return_tx'
      then v_bad := v_bad || ' 대조: ⓐ의 저널 행이 해결기 행이 아니다'; end if;

    -- THE REPAIR
    select _scrub_ops_return_reasons() into v_n;
    if v_n is distinct from 1
      then v_bad := v_bad || ' 스크럽 행 수=' || coalesce(v_n::text, '(null)') || ' (1이어야 — 심기 전 0에서의 델타)'; end if;
    if (select b.return_force_reason from bookings b where b.id = pR) is distinct from c_tok_s
      then v_bad := v_bad || ' ⓐ 스크럽 뒤 값=' ||
        coalesce((select b.return_force_reason from bookings b where b.id = pR), '(null)'); end if;
    if (select b.return_force_reason from bookings b where b.id = pF) is distinct from c_tok
      then v_bad := v_bad || ' 🔴 ⓑ 강제 토큰이 해결기 토큰으로 덮였다=' ||
        coalesce((select b.return_force_reason from bookings b where b.id = pF), '(null)'); end if;
    -- the operator audit trail survives on BOTH kinds — a repair that deleted the text everywhere
    -- would pass the two arms above and destroy the only record there is
    if (select r.memo from return_resolutions r where r.booking_id = pR) is distinct from c_memo
      then v_bad := v_bad || ' 🔴 스크럽이 저널의 ⓐ 메모를 지웠다'; end if;
    if (select r.memo from return_resolutions r where r.booking_id = pF) is distinct from c_sent
      then v_bad := v_bad || ' 🔴 스크럽이 저널의 ⓑ 문장을 지웠다'; end if;

    -- IDEMPOTENT, and the global arm: nothing else in this database still carries a copy
    select _scrub_ops_return_reasons() into v_n;
    if v_n is distinct from 0
      then v_bad := v_bad || ' 두 번째 호출이 행 수=' || coalesce(v_n::text, '(null)') || ' (0이어야)'; end if;

    if v_bad = ''
      then call _pass('frt','0205-F3 스크럽의 대상 집합 — 세상에 두 번째 행 종류가 생긴 뒤에도 0193이 쓴 사본만 고쳐진다: 손으로 되심은 해결기 사본은 자기 토큰으로 바뀌고, 저널 행을 **가진** 강제 행의 ops_forced는 그대로 남으며(0201 §B의 「구조적으로 집합 밖」 논거가 0205 §B로 거짓이 된 자리 — source 판별자가 없으면 여기서 붉어진다), 양쪽 저널의 운영자 텍스트는 둘 다 살아 있다; 기준선은 심기 전 0으로 측정했고 두 번째 호출은 0이다(멱등 + 전역 팔)');
    else v_msg := v_bad; call _fail('frt','0205-F3 스크럽의 대상 집합', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('frt','0205-F3 스크럽의 대상 집합', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0205-S1] THE DEPLOYED SHAPE — two functions and one table, and the source arms
  --           distinguish both worlds
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ── the force ─────────────────────────────────────────────────────────────────────────
    select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'force_return_tx';
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(force_return_tx)';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 강제가 definer가 아니다'; end if;
      if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 강제 본문 search_path 없음'; end if;
      select prosrc into v_raw from pg_proc where oid = v_oid;
      if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(force_return_tx)';
      else
        -- comments STRIPPED: 0205 explains the token rule at length inside this very body, and an
        -- un-stripped match is satisfied by the prose rather than by the code.
        v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
        if (v_src ~ 'return_force_reason\s*=\s*v_token') is not true
          then v_bad := v_bad || ' 강제: 고정 토큰 배정이 없다'; end if;
        if (v_src ~ 'return_force_reason\s*=\s*p_reason') is not false
          then v_bad := v_bad || ' 🔴 강제: 호출자 free text가 당사자 칸에 배정된다'; end if;
        -- the sentence must still REACH the journal — a fix that dropped `p_reason` passes the two
        -- arms above and destroys the adjudication's only justification
        if (v_src ~ 'insert into return_resolutions') is not true
          then v_bad := v_bad || ' 강제: 저널 기록이 없다'; end if;
        if (v_src ~ '\mp_reason\M') is not true
          then v_bad := v_bad || ' 강제: 사유가 본문에서 사라졌다'; end if;
        -- 0089's rules, re-asserted because 0205 re-declared the function
        if (v_src ~ 'raise exception ''force_party_forbidden''') is not true
          then v_bad := v_bad || ' 강제: 당사자 거절이 사라졌다 (2026-08-13 판단)'; end if;
        if (v_src ~ 'raise exception ''reason_required''') is not true
          then v_bad := v_bad || ' 강제: reason_required 거절이 사라졌다'; end if;
        if (v_src ~ 'runner_confirmed_return_at\s*=') is not false
          then v_bad := v_bad || ' 🔴 강제: 러너 스탬프를 위조한다'; end if;
        if (v_src ~ 'owner_confirmed_return_at\s*=') is not false
          then v_bad := v_bad || ' 🔴 강제: 보호자 스탬프를 위조한다'; end if;
        -- CRUDE CONTROL: the raw source DOES carry the words these arms look for, so a stripper
        -- that blanked the whole body would not read as a clean pass.
        if (v_raw ~ 'return_force_reason') is not true
          then v_bad := v_bad || ' 대조: 원본 소스에 return_force_reason이라는 낱말이 없다 (주석 제거 팔이 무의미)'; end if;
      end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 강제가 authenticated에 열려 있다 (0089 §2 위반)'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 강제가 anon에 열려 있다'; end if;
      if has_function_privilege('service_role', v_oid, 'execute') is not true
        then v_bad := v_bad || ' 강제를 service_role이 실행할 수 없다'; end if;
    end if;

    -- ── the scrub ─────────────────────────────────────────────────────────────────────────
    select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = '_scrub_ops_return_reasons';
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(_scrub_ops_return_reasons)';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 스크럽이 definer가 아니다'; end if;
      if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 스크럽 본문 search_path 없음'; end if;
      select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
      if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(_scrub_ops_return_reasons)';
      else
        if (v_src ~ 'from return_resolutions') is not true
          then v_bad := v_bad || ' 스크럽: 저널 조인이 없다 (텍스트로 고르고 있다)'; end if;
        if (v_src ~ 'r\.source\s*=\s*''ops_resolve_return_tx''') is not true
          then v_bad := v_bad || ' 🔴 스크럽: source 판별자가 없다 (강제 행의 토큰을 덮는다)'; end if;
        if (v_src ~ 'return_forced_by = ''ops''') is not true
          then v_bad := v_bad || ' 스크럽: ops 마커 조건이 없다'; end if;
      end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 스크럽이 authenticated에 열려 있다'; end if;
    end if;

    -- ── the table ─────────────────────────────────────────────────────────────────────────
    if (select is_nullable from information_schema.columns
         where table_schema = 'public' and table_name = 'return_resolutions'
           and column_name = 'source') is distinct from 'NO'
      then v_bad := v_bad || ' 저널: source 칸이 없거나 NULL 허용이다'; end if;
    if (select is_nullable from information_schema.columns
         where table_schema = 'public' and table_name = 'return_resolutions'
           and column_name = 'resolved_by') is distinct from 'YES'
      then v_bad := v_bad || ' 저널: resolved_by의 NOT NULL이 풀리지 않았다 (강제가 행을 쓸 수 없다)'; end if;
    if (exists (select 1 from pg_constraint where conrelid = 'return_resolutions'::regclass
                 and conname = 'return_resolutions_actor_check')) is not true
      then v_bad := v_bad || ' 저널: 행위자 CHECK이 없다 (해결기의 불변식이 칸에서도 규칙에서도 사라졌다)'; end if;
    if (exists (select 1 from pg_constraint where conrelid = 'return_resolutions'::regclass
                 and conname = 'return_resolutions_source_check')) is not true
      then v_bad := v_bad || ' 저널: source 값 CHECK이 없다'; end if;
    -- 0205 added a column, not a door — the journal is still sealed
    if (select relrowsecurity from pg_class where oid = 'return_resolutions'::regclass) is not true
      then v_bad := v_bad || ' return_resolutions에 RLS가 없다'; end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'return_resolutions')
      then v_bad := v_bad || ' return_resolutions에 정책이 있다 (클라이언트 표면)'; end if;
    if has_table_privilege('authenticated', 'public.return_resolutions', 'select') is not false
      then v_bad := v_bad || ' 저널이 authenticated에 열려 있다'; end if;
    if has_table_privilege('anon', 'public.return_resolutions', 'select') is not false
      then v_bad := v_bad || ' 저널이 anon에 열려 있다'; end if;

    if v_bad = ''
      then call _pass('frt','0205-S1 배포 형상 — force_return_tx와 스크럽은 definer에 본문 search_path를 갖고 ACL이 양방향으로 맞으며(강제는 service_role만·authenticated/anon 아님, 0089 §2), 주석 벗긴 소스에서 판정 사유 칸은 v_token을 받고 p_reason은 **절대** 받지 않으면서 사유는 여전히 저널로 가고(모두 지운 수정은 통과하지 못한다) 당사자 거절·reason_required·스탬프 비위조는 그대로다(원본에 낱말이 있다는 크루드 대조 포함); 스크럽은 저널 조인에 source 판별자를 갖는다; 저널은 source가 NOT NULL·resolved_by가 NULL 허용이되 CHECK 둘이 모양을 지키고 여전히 봉인이다. NO-FUNCTION·NO-SOURCE는 큰 소리로 실패');
    else v_msg := v_bad; call _fail('frt','0205-S1 배포 형상', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('frt','0205-S1 배포 형상', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
