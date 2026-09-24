-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 249 — 0218: the caller's evidence object is SEALED, the party-readable column is server-composed,
--       and the pre-0205 shell forces get the journal row they never had
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Tag `fes`. Pins 0218-E1 · E2 · E3 · E4 · E5 · E6 · E7 · S1.
--
-- ─── WHAT EACH PIN ESTABLISHES, WITHOUT REFERENCE TO ANY MUTATION ───
--  · **0218-E1** — after an ops force whose `p_evidence` carries a memo sentinel, BOTH parties can
--        read their own booking row through the door they actually hold (role `authenticated`,
--        their claim — the readability control that makes 「absent」 mean something), and the
--        sentinel is in NO value of the whole row AND not in a direct
--        `select return_force_evidence, return_force_reason` either — two parties × two reads;
--        a stranger reads nothing; `my_return_resolution` hands back 0199's fixed sentence.
--        The sentinel IS in the database (the journal) — measured first, so the absences are
--        absences of a thing that exists.
--  · **0218-E2** — the sealed journal row holds the caller's object VERBATIM (jsonb equality,
--        not containment), with 0205's shape around it (source, NULL actor, memo); a second force
--        with a different object neither writes a second row nor overwrites the first object —
--        immutability of the evidence, where it is now observable.
--  · **0218-E3** — the party-readable column's key set is EXACTLY the documented five
--        (`forced_at, from_status, owner_stamped, runner_stamped, source`), each value is the
--        server's fact, and the whole value equals the composer's output — an equality, so a
--        sixth key (anything typed) reddens it as surely as a missing one.
--  · **0218-E4** — the repair on a 0205-SHAPED row (journal row with NULL evidence, the caller's
--        object in `bookings`): the hole is REPRODUCED first (the owner reads the sentinel out of
--        their own row), then ONE call preserves the object into the journal and replaces the
--        column with the composed shape, as a DELTA the pin caused; a RESOLVER's row is
--        byte-identical before and after (the target set is keyed on `source`).
--  · **0218-E5** — the repair on a PRE-0205 shape (free text in the reason column, the caller's
--        object in the evidence column, `return_forced_by = 'ops'`, NO journal row): the hole is
--        reproduced (owner reads both), 0205 §C's scrub is measured BLIND to it (the finding's
--        mechanism), then ONE call writes a sealed `backfill_0218` row carrying the text and the
--        object with `created_at = return_forced_at`, re-tokens the public reason, composes the
--        column — and a second fixture whose reason is ALREADY a token is journalled and scrubbed
--        but not re-tokened (the known-token conjunct). The party's 0199 read shows the fixed
--        sentence with the FORCE's instant; the journal itself is unreadable to the party.
--  · **0218-E6** — idempotency, counted: a further call returns four zeros, the journal row count
--        is unchanged, and every fixture's (reason, evidence) pair is identical before and after;
--        0205's scrub still returns 0 and does not relabel a backfilled `ops_forced`.
--  · **0218-E7** — the controls: NULL / `{}` / non-object evidence are refused BY NAME
--        (`evidence_required`), an empty reason by `reason_required`, every refusal writes nothing,
--        and a minimal valid force still works as before — forced, sealed, journalled, composed.
--  · **0218-S1** — the deployed shape of the three functions and the table, source arms
--        comment-stripped, with the crude control that the raw source carries the words, and the
--        three CHECKs refusing the three shapes that would dissolve what §A holds.
--
-- ─── NAMED GAPS (facts about the system, not blind pins) ───
--  · 🔴 **A backfilled row's stamp booleans are AS OF THE BACKFILL** (0218 §0d). `confirm_return_tx`
--    accepts a late party stamp after a force, so for a row the force itself never journalled no
--    fixture can distinguish 「recorded at force time」 from 「recorded now」. Stated in 0218's
--    header and the table comment; not asserted here, because there is no mutation that could
--    redden such an arm.
--  · **The RESOLVER's evidence still carries `resolved_by`** (executing review F6, 0214 §0c: its
--    own slice). E4's control asserts only that 0218's repair does not TOUCH it — not that it is
--    right.
--  · **Client vocabulary does not exist**: `grep -rn return_force_evidence app/` → 0.
--
-- ─── FIXTURE NOTES ───
--  ① This suite builds its OWN world (`t_fes_*`, `fes_` profiles) rather than borrowing 236's.
--  ② Every force is called WITHOUT a quote, so it seals and settles nothing (0089's unpriced
--     branch); the money path is not what this file is about.
--  ③ E4 and E5 measure the repair's baseline FIRST — `_seal_force_evidence_0218()` is called
--     before anything is planted and must return four zeros — so the counts afterwards are deltas
--     these pins CAUSED. Every earlier suite's force rows were repaired at 0218's apply (the
--     harness applies migrations before any suite runs), and the one suite that hand-plants an
--     `ops` marker (224:575) does so as a PARTY and is refused.
--  ④ E4 plants the 0205 shape by dropping 0218's `return_resolutions_evidence_check` for the
--     plant and re-adding it with 0218's own definition; S1 asserts it is back. A pin that could
--     not build the pre-fix world would be an absence pin over an empty world (0151's lesson).
--  ⑤ E1/E3's fixture carries exactly ONE party stamp (runner), so the two composed booleans are
--     `true`/`false` rather than a matched pair a bug could produce by accident; E5's likewise.
--
-- ─── MUTATION MAP — measured against these exact files, not predicted ───
-- In the REGISTRY row. Lab: a copy of `supabase/` OUTSIDE the worktree, every plant
-- assert-verified and CHAIN-GATED to its harness run (`plant && harness`).
set client_min_messages = warning;

-- ---------- suite-local fixtures ① ----------
create or replace function t_fes_live(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid)
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

-- The quote the EDGE computes and hands to the resolver. A fixture, not a rule (137 owns pricing).
create or replace function t_fes_quote(p_km numeric) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'base', 9900, 'distance_pay', round(p_km * 3000)::int, 'addon_pay', 0,
    'guarantee', 0, 'fee', round((9900 + round(p_km * 3000)) * 0.2)::int)
$$;

-- age a stopped run (the run row moves with it)
create or replace function t_fes_age(p_booking uuid, p_ago interval) returns void
language sql as $$
  with b as (update bookings set run_ended_at = now() - p_ago where id = p_booking returning id)
  update runs set ended_at = now() - p_ago where booking_id = (select id from b)
$$;

-- Read ONE booking row exactly as the app reads it — AS `authenticated`, under that party's claim,
-- whole row as JSON. Reports the row OR the raise, never both.
create or replace function t_fes_row_as(p_uid uuid, p_booking uuid) returns jsonb
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

-- The DIRECT two-column read codex #3 is about — `select return_force_evidence, return_force_reason`
-- as a party — reported the same way.
create or replace function t_fes_cols_as(p_uid uuid, p_booking uuid) returns jsonb
language plpgsql as $$
declare v jsonb; v_n int;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  begin
    set local role authenticated;
    select count(*)::int into v_n from bookings b where b.id = p_booking;
    select jsonb_build_object('reason', b.return_force_reason, 'evidence', b.return_force_evidence)
      into v from bookings b where b.id = p_booking;
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);
    return jsonb_build_object('n', v_n, 'cols', coalesce(v, 'null'::jsonb));
  exception when others then
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- One (party, booking) pair, fully judged: the row must be READABLE (the control that makes
-- 「absent」 mean something) and none of the needles may appear anywhere in it.
create or replace function t_fes_leak(p_who text, p_uid uuid, p_booking uuid, p_needles text[])
returns text language plpgsql as $$
declare v_js jsonb; v_bad text := ''; v_needle text;
begin
  v_js := t_fes_row_as(p_uid, p_booking);
  if v_js->>'raised' is not null then
    return ' ' || p_who || ' 읽기가 터졌다 [' || (v_js->>'raised') || ']';
  end if;
  if (v_js->>'n')::int is distinct from 1 then
    v_bad := v_bad || ' 대조: ' || p_who || '가 자기 예약을 못 읽는다 (n=' || coalesce(v_js->>'n','?') || ')';
  end if;
  foreach v_needle in array p_needles loop
    if (position(v_needle in coalesce(v_js->>'row', '')) > 0) is not false then
      v_bad := v_bad || ' 🔴 ' || p_who || '가 읽는 예약 행에 운영자 텍스트가 있다 (' || left(v_needle, 24) || ')';
    end if;
  end loop;
  return v_bad;
end $$;

-- the 0199 party-facing read, as one party, flattened — with `resolved_at` so E5 can assert the
-- backfilled row shows the FORCE's instant.
create or replace function t_fes_note_as(p_uid uuid, p_booking uuid) returns jsonb
language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  begin
    select coalesce(jsonb_agg(jsonb_build_object(
             'resolved_at', x.resolved_at, 'rescued_from', x.rescued_from, 'note_public', x.note_public)), '[]'::jsonb)
      into v from my_return_resolution(p_booking) x;
    perform set_config('request.jwt.claim.sub', '', false);
    return jsonb_build_object('rows', v, 'n', jsonb_array_length(v));
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    return jsonb_build_object('raised', sqlerrm);
  end;
end $$;

-- the journal read AS a party — expected to be refused outright (RLS on, zero policies, no grant)
create or replace function t_fes_journal_as(p_uid uuid, p_booking uuid) returns text
language plpgsql as $$
declare v_n int;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), false);
  begin
    set local role authenticated;
    select count(*)::int into v_n from return_resolutions r where r.booking_id = p_booking;
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);
    return 'rows=' || v_n;
  exception when others then
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);
    return 'raised=' || sqlerrm;
  end;
end $$;

do $$
declare
  oo uuid; rr uuid; dg uuid; rt uuid;
  oz uuid; rz uuid; dz uuid;
  ops uuid;                                  -- a rostered `return_strand` operator (E4's resolver control)
  bE uuid;                                   -- E1/E2/E3: the forced booking
  pE uuid; pR uuid;                          -- E4: a 0205-shaped plant + a resolver control
  pB uuid; pT uuid;                          -- E5: two pre-0205-shaped plants (free text · already a token)
  pC uuid;                                   -- E7: the controls
  c_tok     constant text  := 'ops_forced';
  c_keys    constant text[] := array['forced_at', 'from_status', 'owner_stamped', 'runner_stamped', 'source'];
  c_zero    constant jsonb := '{"backfilled":0,"reasons_scrubbed":0,"evidence_preserved":0,"evidence_scrubbed":0}'::jsonb;
  c_reason  constant text  := '보호자 연락 두절 — FES-REASON-3310 셸에서 판정';
  c_ev      constant jsonb := jsonb_build_object('memo', 'FES-SENTINEL-4471 운영자 사적 메모 — 당사자가 보면 안 됨',
                                                 'kind', 'ops_review', 'src', 'fes');
  c_ev2     constant jsonb := jsonb_build_object('memo', 'FES-SENTINEL-9905 두 번째 강제의 증거', 'kind', 'ops_rewrite');
  c_ev4     constant jsonb := jsonb_build_object('memo', 'FES-OLD-5583 0205 시절에 친 메모', 'kind', 'ops_review');
  c_memo    constant text  := 'CCTV 확인 — FES-RES-MEMO-7701 귀가 확인됨';
  c_pre     constant text  := 'FES-PRE0205-7719 보호자 연락 두절 — 0205 이전 셸 판정';
  c_pre_ev  constant jsonb := jsonb_build_object('memo', 'FES-PRE-EV-2264 손으로 친 증거', 'note', 'typed');
  c_tok_ev  constant jsonb := jsonb_build_object('memo', 'FES-PRE-TOK-6630 토큰 사유의 증거');
  c_sent    constant text  := '운영팀이 귀가를 확인 처리했어요';
  v_bad text := ''; v_msg text; v_js jsonb; v_n int; v_src text; v_raw text; v_oid oid;
  v_txt text; v_ts timestamptz; v_ev jsonb; v_ev_before jsonb; v_keys text[]; v_def text;
  v_cnt int; v_snap jsonb; v_snap2 jsonb;
begin
  perform set_config('request.jwt.claim.sub', '', false);
  oo := t_user('fes_oo', 'owner');   rr := t_user('fes_rr', 'runner');
  oz := t_user('fes_oz', 'owner');   rz := t_user('fes_rz', 'runner');
  dg := t_dog(oo, '봉인견');          dz := t_dog(oz, '백필견');
  rt := t_route('증거 봉인 코스');
  ops := t_user('fes_ops', 'owner');
  insert into ops_recipients (profile_id, event_class, active) values (ops, 'return_strand', true)
  on conflict (profile_id, event_class) do nothing;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0218-E1] THE CALLER'S EVIDENCE OBJECT IS NOT A PARTY-READABLE FACT — two parties, two reads
  -- 🔴 Read through the doors a party actually holds: the whole row (what `fetchBookingSync`
  --    gets) AND the direct two-column select codex #3 named. A pin over the RPC's return would
  --    be green with the memo sitting one PostgREST call away.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ⑤ ONE party stamp, so E3's two booleans are not a matched pair
    bE := t_fes_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(bE, 4.0, 1500, 'completed', null, null);
    perform confirm_return_tx(bE, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_fes_age(bE, interval '5 hours');
    -- ② no quote: seals, settles nothing
    v_js := force_return_tx(bE, 'ops', c_reason, c_ev);

    -- CONTROL ①: the force actually happened
    if coalesce((v_js->>'forced')::boolean, false) is not true
      then v_bad := v_bad || ' 대조: 강제가 기록되지 않았다=' || coalesce(v_js::text, '(null)'); end if;
    if (select b.return_forced_by from bookings b where b.id = bE) is distinct from 'ops'
      then v_bad := v_bad || ' 대조: ops 마커가 없다'; end if;
    if (select b.settlement_ready_at from bookings b where b.id = bE) is null
      then v_bad := v_bad || ' 대조: 씰이 찍히지 않았다'; end if;
    -- CONTROL ②: the sentinel really is in the database. An absence measured over a world that
    -- never held the thing is worth exactly zero (0151 N1/N2).
    if (select r.evidence from return_resolutions r where r.booking_id = bE) is distinct from c_ev
      then v_bad := v_bad || ' 대조: 저널에 호출자 증거 객체가 없다 (부재 팔이 무의미)'; end if;

    -- THE PROPERTY ①: neither party can find the memo, the reason, or their sentinels anywhere
    -- in their own row
    v_bad := v_bad || t_fes_leak('보호자', oo, bE, array['FES-SENTINEL-4471', c_reason, 'FES-REASON-3310']);
    v_bad := v_bad || t_fes_leak('러너',  rr, bE, array['FES-SENTINEL-4471', c_reason, 'FES-REASON-3310']);

    -- THE PROPERTY ②: the DIRECT two-column select, as each party
    v_js := t_fes_cols_as(oo, bE);
    if v_js->>'raised' is not null
      then v_bad := v_bad || ' 보호자 직접 읽기가 터졌다 [' || (v_js->>'raised') || ']';
    else
      if (v_js->>'n')::int is distinct from 1
        then v_bad := v_bad || ' 대조: 보호자 직접 읽기 n=' || coalesce(v_js->>'n', '?'); end if;
      if (v_js->'cols'->>'reason') is distinct from c_tok
        then v_bad := v_bad || ' 보호자가 읽는 사유=' || coalesce(v_js->'cols'->>'reason', '(null)'); end if;
      if (position('FES-SENTINEL-4471' in coalesce(v_js->'cols'->>'evidence', '')) > 0) is not false
        then v_bad := v_bad || ' 🔴 보호자가 return_force_evidence에서 센티널을 읽었다'; end if;
      if (v_js->'cols'->'evidence' ? 'memo') is not false
        then v_bad := v_bad || ' 🔴 보호자가 읽는 증거에 memo 키가 있다'; end if;
    end if;
    v_js := t_fes_cols_as(rr, bE);
    if v_js->>'raised' is not null
      then v_bad := v_bad || ' 러너 직접 읽기가 터졌다 [' || (v_js->>'raised') || ']';
    else
      if (v_js->>'n')::int is distinct from 1
        then v_bad := v_bad || ' 대조: 러너 직접 읽기 n=' || coalesce(v_js->>'n', '?'); end if;
      if (v_js->'cols'->>'reason') is distinct from c_tok
        then v_bad := v_bad || ' 러너가 읽는 사유=' || coalesce(v_js->'cols'->>'reason', '(null)'); end if;
      if (position('FES-SENTINEL-4471' in coalesce(v_js->'cols'->>'evidence', '')) > 0) is not false
        then v_bad := v_bad || ' 🔴 러너가 return_force_evidence에서 센티널을 읽었다'; end if;
      if (v_js->'cols'->'evidence' ? 'memo') is not false
        then v_bad := v_bad || ' 🔴 러너가 읽는 증거에 memo 키가 있다'; end if;
    end if;

    -- CONTROL ③: a STRANGER reads nothing, so ①/② are the party gate + the seal working, not an
    -- empty table
    v_js := t_fes_row_as(oz, bE);
    if v_js->>'raised' is null and (v_js->>'n')::int is distinct from 0
      then v_bad := v_bad || ' 대조: 남이 예약 행을 읽었다 (n=' || coalesce(v_js->>'n', '?') || ')'; end if;

    -- the one party-facing read of the journal hands back the FIXED sentence, never the object
    v_js := t_fes_note_as(oo, bE);
    if v_js->>'raised' is not null
      then v_bad := v_bad || ' 보호자 0199 읽기가 터졌다 [' || (v_js->>'raised') || ']';
    else
      if (v_js->>'n')::int is distinct from 1
        then v_bad := v_bad || ' 보호자 0199 행 수=' || coalesce(v_js->>'n', '?'); end if;
      if (v_js->'rows'->0->>'note_public') is distinct from c_sent
        then v_bad := v_bad || ' 보호자가 받은 문장=' || coalesce(v_js->'rows'->0->>'note_public', '(null)'); end if;
      if (position('FES-SENTINEL-4471' in coalesce(v_js::text, '')) > 0) is not false
        then v_bad := v_bad || ' 🔴 0199 읽기에 호출자 증거가 실렸다'; end if;
    end if;

    if v_bad = ''
      then call _pass('fes','0218-E1 호출자 증거 객체는 당사자가 읽는 사실이 아니다 — p_evidence에 memo 센티널을 담아 셸 강제하면 저널에는 그 객체가 있고(대조), 보호자·러너가 각자 authenticated로 자기 예약 행 전체를 읽어도(읽기는 성공 — 대조) 직접 두 칸을 골라 읽어도 센티널도 memo 키도 사유 문장도 없으며 사유 칸은 ops_forced다; 남은 아무것도 못 읽고(대조) 0199의 당사자 읽기는 고정 문장만 준다');
    else v_msg := v_bad; call _fail('fes','0218-E1 호출자 증거 비노출', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fes','0218-E1 호출자 증거 비노출', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0218-E2] THE JOURNAL HOLDS THE OBJECT VERBATIM — AND THE FIRST OBJECT IS THE ONE THAT STANDS
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select count(*)::int into v_n from return_resolutions where booking_id = bE;
    if v_n is distinct from 1 then v_bad := v_bad || ' 저널 행 수=' || v_n; end if;
    -- each column on its own line: a multi-target `into` on no row leaves every target NULL and
    -- reports the FIRST arm instead of the missing row
    if (select r.evidence from return_resolutions r where r.booking_id = bE) is distinct from c_ev
      then v_bad := v_bad || ' 🔴 저널 evidence가 호출자 객체 그대로가 아니다=' ||
        coalesce((select r.evidence::text from return_resolutions r where r.booking_id = bE), '(null)'); end if;
    if (select r.source from return_resolutions r where r.booking_id = bE) is distinct from 'force_return_tx'
      then v_bad := v_bad || ' 저널 source=' || coalesce((select r.source from return_resolutions r where r.booking_id = bE), '(null)'); end if;
    if (select r.resolved_by from return_resolutions r where r.booking_id = bE) is not null
      then v_bad := v_bad || ' 🔴 저널에 행위자가 적혔다 (0089는 auth.uid()를 든 호출자를 거절한다)'; end if;
    if (select r.memo from return_resolutions r where r.booking_id = bE) is distinct from c_reason
      then v_bad := v_bad || ' 저널 memo가 사유가 아니다'; end if;
    if (select r.from_status from return_resolutions r where r.booking_id = bE) is distinct from 'active'
      then v_bad := v_bad || ' 저널 from_status가 active가 아니다'; end if;

    -- IMMUTABILITY of the evidence, read where it is observable: a second force with a DIFFERENT
    -- object is refused (first-writer-wins), writes no row, overwrites nothing — and its sentinel
    -- is nowhere a party can read either
    v_js := force_return_tx(bE, 'ops', '두 번째 — FES-REASON-9902', c_ev2);
    if coalesce((v_js->>'forced')::boolean, true) is not false
      then v_bad := v_bad || ' 두 번째 강제가 다시 기록됐다=' || coalesce(v_js::text, '(null)'); end if;
    select count(*)::int into v_n from return_resolutions where booking_id = bE;
    if v_n is distinct from 1 then v_bad := v_bad || ' 🔴 두 번째 강제가 저널 행을 더 썼다 (행 수=' || v_n || ')'; end if;
    if (select r.evidence from return_resolutions r where r.booking_id = bE) is distinct from c_ev
      then v_bad := v_bad || ' 🔴 두 번째 강제가 첫 증거 객체를 덮었다'; end if;
    v_bad := v_bad || t_fes_leak('보호자(2차)', oo, bE, array['FES-SENTINEL-9905', 'FES-REASON-9902']);

    if v_bad = ''
      then call _pass('fes','0218-E2 저널이 호출자 객체를 그대로 보관한다 — return_resolutions 한 행에 evidence = p_evidence(jsonb 동등), source=force_return_tx, 행위자 NULL, memo=사유, from_status=active; 다른 객체를 든 두 번째 강제는 거절되고 행을 더 쓰지도 첫 객체를 덮지도 않으며 그 센티널도 당사자 행에 없다');
    else v_msg := v_bad; call _fail('fes','0218-E2 저널의 호출자 객체', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fes','0218-E2 저널의 호출자 객체', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0218-E3] THE PARTY-READABLE COLUMN IS EXACTLY THE DOCUMENTED FIVE — an equality
  -- 🔴 The key SET, not an absence: a sixth key (anything the caller typed) reddens this as
  --    surely as a missing one, and 「memo is absent」 alone would be green on `{}`.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select b.return_force_evidence, b.return_forced_at into v_ev, v_ts from bookings b where b.id = bE;
    if v_ev is null then v_bad := v_bad || ' 증거 칸이 NULL이다';
    else
      select array_agg(k order by k) into v_keys from jsonb_object_keys(v_ev) k;
      if v_keys is distinct from c_keys
        then v_bad := v_bad || ' 키 집합=' || coalesce(array_to_string(v_keys, ','), '(null)'); end if;
      if v_ev->>'source' is distinct from 'force_return_tx'
        then v_bad := v_bad || ' source=' || coalesce(v_ev->>'source', '(null)'); end if;
      if v_ev->>'from_status' is distinct from 'active'
        then v_bad := v_bad || ' from_status=' || coalesce(v_ev->>'from_status', '(null)'); end if;
      -- ⑤ runner stamped, owner not — the UPDATE-before state, not a matched pair
      if (v_ev->>'runner_stamped')::boolean is not true
        then v_bad := v_bad || ' runner_stamped가 true가 아니다'; end if;
      if (v_ev->>'owner_stamped')::boolean is not false
        then v_bad := v_bad || ' owner_stamped가 false가 아니다'; end if;
      if v_ts is null then v_bad := v_bad || ' return_forced_at이 NULL이다';
      elsif v_ev->>'forced_at' is distinct from to_char(v_ts at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
        then v_bad := v_bad || ' forced_at=' || coalesce(v_ev->>'forced_at', '(null)') || ' ≠ 행의 return_forced_at'; end if;
      -- the WHOLE value equals the composer's — the composer IS the shape
      if v_ev is distinct from _force_evidence_public('active', true, false, v_ts)
        then v_bad := v_bad || ' 칸 전체가 조합기 출력과 다르다'; end if;
      -- the caller's keys are not there (implied by the set; named so the failure names them)
      if (v_ev ? 'memo') is not false then v_bad := v_bad || ' 🔴 memo 키가 있다'; end if;
      if (v_ev ? 'kind') is not false then v_bad := v_bad || ' 🔴 kind 키가 있다'; end if;
      if (v_ev ? 'src')  is not false then v_bad := v_bad || ' 🔴 src 키가 있다'; end if;
    end if;

    if v_bad = ''
      then call _pass('fes','0218-E3 당사자가 읽는 증거 칸은 문서의 다섯 키 정확히 그것이다 — {forced_at, from_status, owner_stamped, runner_stamped, source} 집합 동등, source=force_return_tx, from_status=active, 스탬프 불린은 UPDATE 이전 상태(러너 true·보호자 false), forced_at은 행의 return_forced_at을 UTC ISO로 쓴 것이며 값 전체가 _force_evidence_public의 출력과 같다; memo·kind·src 같은 호출자 키는 없다');
    else v_msg := v_bad; call _fail('fes','0218-E3 조합 모양', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fes','0218-E3 조합 모양', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0218-E4] THE REPAIR ON A 0205-SHAPED ROW — preserve first, then scrub, as a DELTA
  -- 🔴 The hole is REPRODUCED before the fix is measured: the owner reads the sentinel out of
  --    their own row on the planted shape. Codex's finding was READ; this is where it is
  --    MEASURED (the review's own instruction for every correct-forward).
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ③ baseline: the repair has nothing to do BEFORE anything is planted
    v_js := _seal_force_evidence_0218();
    if v_js is distinct from c_zero
      then v_bad := v_bad || ' 대조: 심기 전 수리가 무언가를 고쳤다=' || coalesce(v_js::text, '(null)'); end if;

    -- ⓐ a REAL resolver adjudication — the control that the repair's set is keyed on `source`
    pR := t_fes_live(oz, dz, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(pR, 3.0, 1000, 'completed', null, null);
    perform confirm_return_tx(pR, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_fes_age(pR, interval '5 hours');
    perform ops_resolve_return_tx(pR, t_fes_quote(3.0), c_memo, ops);
    select b.return_force_evidence into v_ev_before from bookings b where b.id = pR;
    if v_ev_before is null then v_bad := v_bad || ' 대조: 해결기 증거가 없다 (대조 팔이 무의미)'; end if;

    -- ⓑ a 0205-SHAPED force row: a real force through the NEW body, then the pre-0218 data shape
    --    planted back by hand — the caller's object in `bookings`, NULL in the journal.
    pE := t_fes_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(pE, 3.0, 900, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_fes_age(pE, interval '5 hours');
    perform force_return_tx(pE, 'ops', '0205 시절 강제 — FES-REASON-5500', jsonb_build_object('kind', 'ops_review', 'src', 'fes-e4'));
    -- ④ 0218 §A's CHECK forbids the shape being planted; dropped for the plant, re-added below
    --    with 0218's own definition (S1 asserts it is back)
    alter table return_resolutions drop constraint return_resolutions_evidence_check;
    update return_resolutions set evidence = null where booking_id = pE;
    update bookings set return_force_evidence = c_ev4 where id = pE;

    -- CONTROL: the plant landed AND the hole is real — codex #3, reproduced
    v_txt := t_fes_leak('보호자(수리 전)', oo, pE, array['FES-OLD-5583']);
    if (position('FES-OLD-5583' in v_txt) > 0) is not true
      then v_bad := v_bad || ' 대조: 심은 뒤 보호자가 센티널을 못 읽는다 — 구멍이 재현되지 않았다 [' || v_txt || ']'; end if;
    if (select r.evidence from return_resolutions r where r.booking_id = pE) is not null
      then v_bad := v_bad || ' 대조: 저널 증거가 NULL로 심기지 않았다'; end if;

    -- THE REPAIR — counts are a delta this pin caused (baseline was four zeros)
    v_js := _seal_force_evidence_0218();
    if (v_js->>'evidence_preserved')::int is distinct from 1
      then v_bad := v_bad || ' evidence_preserved=' || coalesce(v_js->>'evidence_preserved', '(null)') || ' (1이어야)'; end if;
    if (v_js->>'evidence_scrubbed')::int is distinct from 1
      then v_bad := v_bad || ' evidence_scrubbed=' || coalesce(v_js->>'evidence_scrubbed', '(null)') || ' (1이어야)'; end if;
    if (v_js->>'backfilled')::int is distinct from 0
      then v_bad := v_bad || ' backfilled=' || coalesce(v_js->>'backfilled', '(null)') || ' (0이어야 — 저널 행이 있는 강제다)'; end if;
    if (v_js->>'reasons_scrubbed')::int is distinct from 0
      then v_bad := v_bad || ' reasons_scrubbed=' || coalesce(v_js->>'reasons_scrubbed', '(null)') || ' (0이어야)'; end if;
    -- PRESERVED: the journal holds the caller's object — copied from bookings, the pre-0218 truth
    if (select r.evidence from return_resolutions r where r.booking_id = pE) is distinct from c_ev4
      then v_bad := v_bad || ' 🔴 수리가 호출자 증거를 저널에 보존하지 않았다=' ||
        coalesce((select r.evidence::text from return_resolutions r where r.booking_id = pE), '(null)'); end if;
    -- SCRUBBED: the column is the composed shape, and neither party can read the sentinel
    select b.return_force_evidence, b.return_forced_at into v_ev, v_ts from bookings b where b.id = pE;
    if v_ev is distinct from _force_evidence_public('active', false, false, v_ts)
      then v_bad := v_bad || ' 스크럽 뒤 칸=' || coalesce(v_ev::text, '(null)'); end if;
    v_bad := v_bad || t_fes_leak('보호자(수리 후)', oo, pE, array['FES-OLD-5583']);
    v_bad := v_bad || t_fes_leak('러너(수리 후)',  rr, pE, array['FES-OLD-5583']);
    -- CONTROL: the resolver's row is byte-identical — outside the set by the discriminator
    if (select b.return_force_evidence from bookings b where b.id = pR) is distinct from v_ev_before
      then v_bad := v_bad || ' 🔴 수리가 해결기 행의 증거를 건드렸다'; end if;
    if (select r.evidence from return_resolutions r where r.booking_id = pR) is not null
      then v_bad := v_bad || ' 수리가 해결기 저널 행에 증거를 썼다'; end if;

    -- ④ restore the CHECK with 0218's own definition
    alter table return_resolutions add constraint return_resolutions_evidence_check
      check (source = 'ops_resolve_return_tx' or evidence is not null);

    -- PRESERVED EVIDENCE IS IMMUTABLE: a caller-shaped value planted into `bookings` AFTER the
    -- journal already holds an object is scrubbed again but does NOT replace the journal's copy —
    -- the first preservation wins, exactly as the first force wins (E2). This is the arm the
    -- `r.evidence is null` conjunct exists for; without this fixture, deleting that conjunct
    -- would redden nothing, because after a scrub the column is the composed shape and the
    -- other guard already refuses to copy that.
    update bookings set return_force_evidence = jsonb_build_object('memo', 'FES-REPLANT-8812 다시 심은 값') where id = pE;
    v_js := _seal_force_evidence_0218();
    if (v_js->>'evidence_preserved')::int is distinct from 0
      then v_bad := v_bad || ' 🔴 두 번째 심기가 저널의 첫 증거를 덮었다 (preserved=' || coalesce(v_js->>'evidence_preserved', '(null)') || ')'; end if;
    if (v_js->>'evidence_scrubbed')::int is distinct from 1
      then v_bad := v_bad || ' 두 번째 심기 뒤 scrubbed=' || coalesce(v_js->>'evidence_scrubbed', '(null)') || ' (1이어야)'; end if;
    if (select r.evidence from return_resolutions r where r.booking_id = pE) is distinct from c_ev4
      then v_bad := v_bad || ' 🔴 저널의 첫 증거 객체가 바뀌었다'; end if;
    v_bad := v_bad || t_fes_leak('보호자(재심기 후)', oo, pE, array['FES-REPLANT-8812']);

    if v_bad = ''
      then call _pass('fes','0218-E4 0205 모양 행의 수리 — 심기 전 수리는 0·0·0·0(기준선), 저널 행은 있되 evidence NULL이고 bookings에 호출자 객체가 있는 행을 심으면 보호자가 자기 행에서 센티널을 읽는다(구멍 재현 — 대조); 한 번의 수리로 preserved=1·scrubbed=1(델타), 저널이 호출자 객체를 보관하고 칸은 조합 모양이 되어 양쪽 당사자 행에 센티널이 없으며, 해결기 행의 증거는 수리 전후 동일하다(source로 대상 집합을 고른다 — 대조); 저널이 이미 객체를 가진 뒤 bookings에 다시 심은 값은 스크럽되되 저널의 첫 객체를 덮지 않는다(보존은 한 번 — r.evidence is null 조건의 존재 이유)');
    else v_msg := v_bad; call _fail('fes','0218-E4 0205 모양 행의 수리', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fes','0218-E4 0205 모양 행의 수리', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0218-E5] THE BACKFILL ON A PRE-0205 SHAPE — free text, caller object, NO journal row
  -- 🔴 Codex #4, reproduced first: the owner reads the free text AND the evidence sentinel out of
  --    their own row, and 0205 §C's scrub is measured BLIND to the row (its mechanism).
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ⓐ free text, one runner stamp (⑤)
    pB := t_fes_live(oz, dz, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(pB, 3.0, 900, 'completed', null, null);
    perform confirm_return_tx(pB, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_fes_age(pB, interval '3 days');
    -- 0089 §6's UPDATE, in effect: marker, instant, free text, the caller's object, the seal — and
    -- no journal row, because that writer had none to write
    update bookings
       set return_forced_by = 'ops', return_forced_at = now() - interval '3 days',
           return_force_reason = c_pre, return_force_evidence = c_pre_ev,
           settlement_ready_at = now() - interval '3 days'
     where id = pB;
    -- ⓑ the same shape whose reason is ALREADY a token (the known-token conjunct)
    pT := t_fes_live(oz, dz, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(pT, 3.0, 900, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_fes_age(pT, interval '3 days');
    update bookings
       set return_forced_by = 'ops', return_forced_at = now() - interval '2 days',
           return_force_reason = c_tok, return_force_evidence = c_tok_ev,
           settlement_ready_at = now() - interval '2 days'
     where id = pT;

    -- CONTROLS: the plants landed, no journal rows, and the hole is REAL
    if (select count(*) from return_resolutions where booking_id in (pB, pT)) is distinct from 0
      then v_bad := v_bad || ' 대조: 심은 행에 저널 행이 있다'; end if;
    v_txt := t_fes_leak('보호자(백필 전)', oz, pB, array['FES-PRE0205-7719', 'FES-PRE-EV-2264']);
    if (position('FES-PRE0205-7719' in v_txt) > 0) is not true
      then v_bad := v_bad || ' 대조: 보호자가 free text를 못 읽는다 — #4가 재현되지 않았다 [' || v_txt || ']'; end if;
    if (position('FES-PRE-EV-2264' in v_txt) > 0) is not true
      then v_bad := v_bad || ' 대조: 보호자가 증거 센티널을 못 읽는다 — #3의 옛 행이 재현되지 않았다'; end if;
    -- 0205 §C's scrub is BLIND to these rows — the finding's mechanism, measured
    select _scrub_ops_return_reasons() into v_n;
    if v_n is distinct from 0
      then v_bad := v_bad || ' 대조: 0205의 스크럽이 ' || coalesce(v_n::text, '(null)') || '행을 고쳤다 (그렇다면 #4는 거짓이다)'; end if;
    if (select b.return_force_reason from bookings b where b.id = pB) is distinct from c_pre
      then v_bad := v_bad || ' 대조: 0205의 스크럽이 free text를 바꿨다'; end if;

    -- THE REPAIR
    v_js := _seal_force_evidence_0218();
    if (v_js->>'backfilled')::int is distinct from 2
      then v_bad := v_bad || ' backfilled=' || coalesce(v_js->>'backfilled', '(null)') || ' (2여야)'; end if;
    if (v_js->>'reasons_scrubbed')::int is distinct from 1
      then v_bad := v_bad || ' reasons_scrubbed=' || coalesce(v_js->>'reasons_scrubbed', '(null)') || ' (1이어야 — 토큰 사유는 그대로)'; end if;
    if (v_js->>'evidence_preserved')::int is distinct from 0
      then v_bad := v_bad || ' evidence_preserved=' || coalesce(v_js->>'evidence_preserved', '(null)') || ' (0이어야 — 백필이 삽입에서 이미 담았다)'; end if;
    if (v_js->>'evidence_scrubbed')::int is distinct from 2
      then v_bad := v_bad || ' evidence_scrubbed=' || coalesce(v_js->>'evidence_scrubbed', '(null)') || ' (2여야)'; end if;

    -- ⓐ the public reason is the token; text and object are in a sealed backfill row stamped
    --    with the FORCE's own instant
    if (select b.return_force_reason from bookings b where b.id = pB) is distinct from c_tok
      then v_bad := v_bad || ' ⓐ 백필 뒤 사유=' || coalesce((select b.return_force_reason from bookings b where b.id = pB), '(null)'); end if;
    select count(*)::int into v_n from return_resolutions where booking_id = pB;
    if v_n is distinct from 1 then v_bad := v_bad || ' ⓐ 저널 행 수=' || v_n; end if;
    if (select r.source from return_resolutions r where r.booking_id = pB) is distinct from 'backfill_0218'
      then v_bad := v_bad || ' ⓐ 저널 source=' || coalesce((select r.source from return_resolutions r where r.booking_id = pB), '(null)'); end if;
    if (select r.resolved_by from return_resolutions r where r.booking_id = pB) is not null
      then v_bad := v_bad || ' 🔴 ⓐ 백필 행에 행위자가 적혔다'; end if;
    if (select r.from_status from return_resolutions r where r.booking_id = pB) is distinct from 'active'
      then v_bad := v_bad || ' ⓐ 저널 from_status가 active가 아니다'; end if;
    if (select r.memo from return_resolutions r where r.booking_id = pB) is distinct from c_pre
      then v_bad := v_bad || ' 🔴 ⓐ 저널 memo가 free text가 아니다 (텍스트가 사라졌다)'; end if;
    if (select r.evidence from return_resolutions r where r.booking_id = pB) is distinct from c_pre_ev
      then v_bad := v_bad || ' 🔴 ⓐ 저널 evidence가 호출자 객체가 아니다'; end if;
    if (select r.runner_stamped from return_resolutions r where r.booking_id = pB) is not true
      then v_bad := v_bad || ' ⓐ 저널 runner_stamped가 true가 아니다'; end if;
    if (select r.owner_stamped from return_resolutions r where r.booking_id = pB) is not false
      then v_bad := v_bad || ' ⓐ 저널 owner_stamped가 false가 아니다'; end if;
    select b.return_forced_at into v_ts from bookings b where b.id = pB;
    if (select r.created_at from return_resolutions r where r.booking_id = pB) is distinct from v_ts
      then v_bad := v_bad || ' ⓐ 저널 created_at이 강제 시각이 아니다'; end if;
    select b.return_force_evidence into v_ev from bookings b where b.id = pB;
    if v_ev is distinct from _force_evidence_public('active', true, false, v_ts)
      then v_bad := v_bad || ' ⓐ 백필 뒤 칸=' || coalesce(v_ev::text, '(null)'); end if;
    v_bad := v_bad || t_fes_leak('보호자(백필 후)', oz, pB, array[c_pre, 'FES-PRE0205-7719', 'FES-PRE-EV-2264']);
    v_bad := v_bad || t_fes_leak('러너(백필 후)',  rz, pB, array[c_pre, 'FES-PRE0205-7719', 'FES-PRE-EV-2264']);

    -- ⓑ the known-token conjunct: journalled and scrubbed, NOT re-tokened (nothing to re-token)
    if (select b.return_force_reason from bookings b where b.id = pT) is distinct from c_tok
      then v_bad := v_bad || ' ⓑ 토큰 사유가 바뀌었다=' || coalesce((select b.return_force_reason from bookings b where b.id = pT), '(null)'); end if;
    if (select r.source from return_resolutions r where r.booking_id = pT) is distinct from 'backfill_0218'
      then v_bad := v_bad || ' ⓑ 저널 행이 없거나 source가 다르다'; end if;
    if (select r.memo from return_resolutions r where r.booking_id = pT) is distinct from c_tok
      then v_bad := v_bad || ' ⓑ 저널 memo가 칸에 있던 값(토큰)이 아니다'; end if;
    if (select r.evidence from return_resolutions r where r.booking_id = pT) is distinct from c_tok_ev
      then v_bad := v_bad || ' 🔴 ⓑ 저널 evidence가 호출자 객체가 아니다'; end if;
    select b.return_force_evidence, b.return_forced_at into v_ev, v_ts from bookings b where b.id = pT;
    if v_ev is distinct from _force_evidence_public('active', false, false, v_ts)
      then v_bad := v_bad || ' ⓑ 백필 뒤 칸=' || coalesce(v_ev::text, '(null)'); end if;
    v_bad := v_bad || t_fes_leak('보호자(ⓑ)', oz, pT, array['FES-PRE-TOK-6630']);

    -- the party's 0199 read: the FIXED sentence with the FORCE's instant, never the text —
    -- 0218 §0d's named widening, pinned rather than discovered
    select b.return_forced_at into v_ts from bookings b where b.id = pB;
    v_js := t_fes_note_as(oz, pB);
    if v_js->>'raised' is not null
      then v_bad := v_bad || ' 보호자 0199 읽기가 터졌다 [' || (v_js->>'raised') || ']';
    else
      if (v_js->>'n')::int is distinct from 1
        then v_bad := v_bad || ' 보호자 0199 행 수=' || coalesce(v_js->>'n', '?'); end if;
      if (v_js->'rows'->0->>'note_public') is distinct from c_sent
        then v_bad := v_bad || ' 보호자가 받은 문장=' || coalesce(v_js->'rows'->0->>'note_public', '(null)'); end if;
      if (v_js->'rows'->0->>'resolved_at')::timestamptz is distinct from v_ts
        then v_bad := v_bad || ' 보호자가 받은 resolved_at이 강제 시각이 아니다'; end if;
      if (position('FES-PRE' in coalesce(v_js::text, '')) > 0) is not false
        then v_bad := v_bad || ' 🔴 0199 읽기에 운영자 텍스트가 실렸다'; end if;
    end if;
    -- …and the journal itself is not a door: the party is refused outright
    v_txt := t_fes_journal_as(oz, pB);
    if (position('permission denied' in v_txt) > 0) is not true
      then v_bad := v_bad || ' 🔴 당사자가 저널을 직접 읽었다 [' || v_txt || ']'; end if;

    if v_bad = ''
      then call _pass('fes','0218-E5 0205 이전 셸 강제의 백필 — free text·호출자 객체·ops 마커·저널 행 없음 모양을 심으면 보호자가 둘 다 자기 행에서 읽고(#3·#4 재현 — 대조) 0205의 스크럽은 0을 돌려주며 아무것도 바꾸지 않는다(눈먼 이유 — 대조); 한 번의 수리로 backfilled=2·reasons=1·preserved=0·scrubbed=2, free text 행은 사유가 ops_forced가 되고 봉인된 backfill_0218 행(행위자 NULL·from_status=active·memo=텍스트·evidence=객체·created_at=강제 시각·스탬프 true/false)이 생기며 칸은 조합 모양이 되어 양쪽 당사자 행에 텍스트가 없다; 이미 토큰인 행은 저널·스크럽만 되고 사유는 그대로다; 0199는 고정 문장과 강제 시각을 주고 저널 직접 읽기는 permission denied다');
    else v_msg := v_bad; call _fail('fes','0218-E5 0205 이전 셸 강제의 백필', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fes','0218-E5 0205 이전 셸 강제의 백필', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0218-E6] IDEMPOTENCY, COUNTED — a further call changes nothing, and 0205's scrub is still
  --           blind to the backfill kind
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select count(*)::int into v_cnt from return_resolutions;
    select jsonb_agg(jsonb_build_object('id', b.id, 'r', b.return_force_reason, 'e', b.return_force_evidence) order by b.id)
      into v_snap from bookings b where b.id in (bE, pE, pR, pB, pT);
    if v_cnt < 4 then v_bad := v_bad || ' 대조: 저널에 픽스처 행이 모자란다 (' || v_cnt || ')'; end if;
    if jsonb_array_length(coalesce(v_snap, '[]'::jsonb)) is distinct from 5
      then v_bad := v_bad || ' 대조: 스냅샷 행 수=' || jsonb_array_length(coalesce(v_snap, '[]'::jsonb)); end if;

    v_js := _seal_force_evidence_0218();
    if v_js is distinct from c_zero
      then v_bad := v_bad || ' 🔴 두 번째 수리가 무언가를 바꿨다=' || coalesce(v_js::text, '(null)'); end if;
    select count(*)::int into v_n from return_resolutions;
    if v_n is distinct from v_cnt
      then v_bad := v_bad || ' 🔴 두 번째 수리 뒤 저널 행 수 ' || v_cnt || ' → ' || v_n; end if;
    select jsonb_agg(jsonb_build_object('id', b.id, 'r', b.return_force_reason, 'e', b.return_force_evidence) order by b.id)
      into v_snap2 from bookings b where b.id in (bE, pE, pR, pB, pT);
    if v_snap2 is distinct from v_snap
      then v_bad := v_bad || ' 🔴 두 번째 수리 뒤 예약 행의 (사유, 증거)가 달라졌다'; end if;
    -- 0205's scrub: still 0, and a backfilled `ops_forced` is NOT relabelled ops_resolved:strand
    select _scrub_ops_return_reasons() into v_n;
    if v_n is distinct from 0
      then v_bad := v_bad || ' 0205 스크럽이 ' || coalesce(v_n::text, '(null)') || '행을 고쳤다'; end if;
    if (select b.return_force_reason from bookings b where b.id = pB) is distinct from c_tok
      then v_bad := v_bad || ' 🔴 0205 스크럽이 백필 행의 ops_forced를 덮었다=' ||
        coalesce((select b.return_force_reason from bookings b where b.id = pB), '(null)'); end if;

    if v_bad = ''
      then call _pass('fes','0218-E6 멱등 — 수리를 한 번 더 부르면 0·0·0·0을 돌려주고 저널 행 수와 다섯 픽스처의 (사유, 증거)가 전후 동일하다; 0205의 스크럽도 0이고 백필 행의 ops_forced를 ops_resolved:strand로 덮지 않는다(source 판별자로 눈먼다)');
    else v_msg := v_bad; call _fail('fes','0218-E6 멱등', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fes','0218-E6 멱등', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0218-E7] THE CONTROLS — 0089's refusals by NAME, nothing written by a refusal, and a
  --           minimal valid force still works as before
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    pC := t_fes_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(pC, 3.0, 900, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_fes_age(pC, interval '5 hours');
    -- (f) NULL / {} / non-object evidence → evidence_required
    begin
      perform force_return_tx(pC, 'ops', '사유는 있음 — FES-CTRL', null);
      v_bad := v_bad || ' 🔴 NULL 증거가 통과했다';
    exception when others then
      if sqlerrm <> 'evidence_required' then v_bad := v_bad || ' NULL 증거 거절 이름=' || sqlerrm; end if;
    end;
    begin
      perform force_return_tx(pC, 'ops', '사유는 있음 — FES-CTRL', '{}'::jsonb);
      v_bad := v_bad || ' 🔴 빈 객체 증거가 통과했다';
    exception when others then
      if sqlerrm <> 'evidence_required' then v_bad := v_bad || ' 빈 객체 거절 이름=' || sqlerrm; end if;
    end;
    begin
      perform force_return_tx(pC, 'ops', '사유는 있음 — FES-CTRL', '[1]'::jsonb);
      v_bad := v_bad || ' 🔴 배열 증거가 통과했다';
    exception when others then
      if sqlerrm <> 'evidence_required' then v_bad := v_bad || ' 배열 거절 이름=' || sqlerrm; end if;
    end;
    -- (g) an empty reason with good evidence → reason_required (0205's refusal, unchanged)
    begin
      perform force_return_tx(pC, 'ops', '   ', jsonb_build_object('kind', 'ops_review'));
      v_bad := v_bad || ' 🔴 빈 사유가 통과했다';
    exception when others then
      if sqlerrm <> 'reason_required' then v_bad := v_bad || ' 빈 사유 거절 이름=' || sqlerrm; end if;
    end;
    -- nothing was written by any refusal
    if (select b.return_forced_by from bookings b where b.id = pC) is not null
      then v_bad := v_bad || ' 거절이 ops 마커를 남겼다'; end if;
    if (select b.return_force_evidence from bookings b where b.id = pC) is not null
      then v_bad := v_bad || ' 거절이 증거 칸을 썼다'; end if;
    if (select count(*) from return_resolutions where booking_id = pC) is distinct from 0
      then v_bad := v_bad || ' 거절이 저널 행을 남겼다'; end if;
    -- POSITIVE CONTROL: a minimal valid force works as before — forced, sealed, journalled, composed
    v_js := force_return_tx(pC, 'ops', '최소 증거 — FES-MIN-1188', jsonb_build_object('kind', 'ops_review'));
    if coalesce((v_js->>'forced')::boolean, false) is not true
      then v_bad := v_bad || ' 대조: 최소 증거 강제가 기록되지 않았다=' || coalesce(v_js::text, '(null)'); end if;
    if (select b.settlement_ready_at from bookings b where b.id = pC) is null
      then v_bad := v_bad || ' 대조: 최소 증거 강제가 씰을 찍지 않았다'; end if;
    if (select r.evidence from return_resolutions r where r.booking_id = pC) is distinct from jsonb_build_object('kind', 'ops_review')
      then v_bad := v_bad || ' 최소 증거가 저널에 그대로 없다'; end if;
    select array_agg(k order by k) into v_keys
      from jsonb_object_keys(coalesce((select b.return_force_evidence from bookings b where b.id = pC), '{}'::jsonb)) k;
    if v_keys is distinct from c_keys
      then v_bad := v_bad || ' 최소 증거 강제 뒤 칸 키 집합=' || coalesce(array_to_string(v_keys, ','), '(null)'); end if;

    if v_bad = ''
      then call _pass('fes','0218-E7 대조 — NULL·빈 객체·배열 증거는 evidence_required로, 빈 사유는 reason_required로 이름 그대로 거절되고 어느 거절도 마커·증거 칸·저널 행을 남기지 않으며, 최소 증거 {kind}를 든 강제는 전과 같이 성사되어 씰을 찍고 저널에 객체를 그대로 두며 칸은 다섯 키 조합 모양이다');
    else v_msg := v_bad; call _fail('fes','0218-E7 대조', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fes','0218-E7 대조', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0218-S1] THE DEPLOYED SHAPE — three functions and one table, source arms comment-stripped
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
        v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
        -- the ASSIGNMENT, not the word
        if (v_src ~ 'return_force_evidence\s*=\s*_force_evidence_public\(') is not true
          then v_bad := v_bad || ' 강제: 증거 칸에 서버 조합값 배정이 없다'; end if;
        if (v_src ~ 'return_force_evidence\s*=\s*p_evidence') is not false
          then v_bad := v_bad || ' 🔴 강제: 호출자 증거 객체가 당사자 칸에 배정된다'; end if;
        -- the object must still REACH the journal — a fix that dropped p_evidence passes the two
        -- arms above and destroys the adjudication's only justification
        if (v_src ~ 'insert into return_resolutions[^;]*evidence[^;]*p_evidence') is not true
          then v_bad := v_bad || ' 강제: 호출자 증거가 저널 INSERT에 없다'; end if;
        if (v_src ~ 'raise exception ''evidence_required''') is not true
          then v_bad := v_bad || ' 강제: evidence_required 거절이 사라졌다'; end if;
        -- 0205's and 0089's rules, re-asserted because 0218 re-declared the function
        if (v_src ~ 'return_force_reason\s*=\s*v_token') is not true
          then v_bad := v_bad || ' 강제: 고정 토큰 배정이 없다'; end if;
        if (v_src ~ 'return_force_reason\s*=\s*p_reason') is not false
          then v_bad := v_bad || ' 🔴 강제: 호출자 free text가 당사자 칸에 배정된다'; end if;
        if (v_src ~ '\mp_reason\M') is not true
          then v_bad := v_bad || ' 강제: 사유가 본문에서 사라졌다'; end if;
        if (v_src ~ 'raise exception ''force_party_forbidden''') is not true
          then v_bad := v_bad || ' 강제: 당사자 거절이 사라졌다 (2026-08-13 판단)'; end if;
        if (v_src ~ 'raise exception ''reason_required''') is not true
          then v_bad := v_bad || ' 강제: reason_required 거절이 사라졌다'; end if;
        if (v_src ~ 'runner_confirmed_return_at\s*=') is not false
          then v_bad := v_bad || ' 🔴 강제: 러너 스탬프를 위조한다'; end if;
        if (v_src ~ 'owner_confirmed_return_at\s*=') is not false
          then v_bad := v_bad || ' 🔴 강제: 보호자 스탬프를 위조한다'; end if;
        if (v_src ~ 'return_eligible_at\s*=') is not false
          then v_bad := v_bad || ' 강제: 파생 캐시를 다시 쓴다'; end if;
        -- CRUDE CONTROL: the raw source DOES carry the words these arms look for
        if (v_raw ~ 'return_force_evidence') is not true
          then v_bad := v_bad || ' 대조: 원본 소스에 return_force_evidence라는 낱말이 없다 (주석 제거 팔이 무의미)'; end if;
      end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 강제가 authenticated에 열려 있다 (0089 §2 위반)'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 강제가 anon에 열려 있다'; end if;
      if has_function_privilege('service_role', v_oid, 'execute') is not true
        then v_bad := v_bad || ' 강제를 service_role이 실행할 수 없다'; end if;
    end if;

    -- ── the composer ──────────────────────────────────────────────────────────────────────
    select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = '_force_evidence_public';
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(_force_evidence_public)';
    else
      -- by VALUE on a sample call: the key set is an equality
      select array_agg(k order by k) into v_keys
        from jsonb_object_keys(_force_evidence_public('active', true, false, now())) k;
      if v_keys is distinct from c_keys
        then v_bad := v_bad || ' 조합기 키 집합=' || coalesce(array_to_string(v_keys, ','), '(null)'); end if;
      if (_force_evidence_public('active', true, false, now())->>'source') is distinct from 'force_return_tx'
        then v_bad := v_bad || ' 조합기 source 값이 force_return_tx가 아니다'; end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 조합기가 authenticated에 열려 있다'; end if;
    end if;

    -- ── the repair ────────────────────────────────────────────────────────────────────────
    select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = '_seal_force_evidence_0218';
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(_seal_force_evidence_0218)';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 수리가 definer가 아니다'; end if;
      if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 수리 본문 search_path 없음'; end if;
      select prosrc into v_raw from pg_proc where oid = v_oid;
      if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(_seal_force_evidence_0218)';
      else
        v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
        if (v_src ~ '''backfill_0218''') is not true
          then v_bad := v_bad || ' 수리: 백필 행을 쓰지 않는다'; end if;
        if (v_src ~ 'not exists \(select 1 from return_resolutions') is not true
          then v_bad := v_bad || ' 수리: 「저널 행 없음」 조건이 없다'; end if;
        if (v_src ~ 'r\.evidence is null') is not true
          then v_bad := v_bad || ' 수리: 보존이 이미 보존된 행을 다시 덮는다'; end if;
        if (v_src ~ 'return_force_evidence is distinct from') is not true
          then v_bad := v_bad || ' 수리: 스크럽이 쓰려는 값과 비교하지 않는다'; end if;
        if (v_src ~ 'return_forced_by = ''ops''') is not true
          then v_bad := v_bad || ' 수리: ops 마커 조건이 없다'; end if;
        if (v_src ~ '''ops_resolved:strand''') is not true or (v_src ~ '''ops_resolved:review''') is not true
          then v_bad := v_bad || ' 수리: 알려진 토큰 목록이 빠졌다'; end if;
        if (v_raw ~ 'backfill_0218') is not true
          then v_bad := v_bad || ' 대조: 원본 소스에 backfill_0218이 없다'; end if;
      end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 수리가 authenticated에 열려 있다'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 수리가 anon에 열려 있다'; end if;
    end if;

    -- ── the table ─────────────────────────────────────────────────────────────────────────
    if (select data_type from information_schema.columns
         where table_schema = 'public' and table_name = 'return_resolutions' and column_name = 'evidence')
       is distinct from 'jsonb'
      then v_bad := v_bad || ' 저널: evidence 칸이 없거나 jsonb가 아니다'; end if;
    select pg_get_constraintdef(oid) into v_def from pg_constraint
     where conrelid = 'return_resolutions'::regclass and conname = 'return_resolutions_source_check';
    if (v_def ~ 'backfill_0218') is not true
      then v_bad := v_bad || ' 저널: source CHECK이 backfill_0218을 모른다'; end if;
    select pg_get_constraintdef(oid) into v_def from pg_constraint
     where conrelid = 'return_resolutions'::regclass and conname = 'return_resolutions_actor_check';
    if (v_def ~ 'backfill_0218') is not true
      then v_bad := v_bad || ' 저널: 행위자 CHECK이 backfill_0218을 모른다'; end if;
    select pg_get_constraintdef(oid) into v_def from pg_constraint
     where conrelid = 'return_resolutions'::regclass and conname = 'return_resolutions_evidence_check';
    if v_def is null then v_bad := v_bad || ' 저널: 증거 CHECK이 없다 (E4가 되돌리지 않았다?)';
    elsif (v_def ~ 'evidence IS NOT NULL') is not true
      then v_bad := v_bad || ' 저널: 증거 CHECK의 정의가 다르다=' || v_def; end if;
    -- the CHECKs refuse the three shapes that would dissolve §A — and admit the right one (control)
    begin
      insert into return_resolutions (booking_id, resolved_by, from_status, runner_stamped, owner_stamped, memo, source, evidence)
      values (bE, null, 'active', false, false, '증거 없는 강제 행', 'force_return_tx', null);
      v_bad := v_bad || ' 🔴 증거 없는 강제 행이 들어왔다';
    exception when check_violation then null;
             when others then v_bad := v_bad || ' 증거 없음 거절 이름=' || sqlerrm;
    end;
    begin
      insert into return_resolutions (booking_id, resolved_by, from_status, runner_stamped, owner_stamped, memo, source, evidence)
      values (bE, ops, 'active', false, false, '행위자를 든 백필 행', 'backfill_0218', '{"x":1}'::jsonb);
      v_bad := v_bad || ' 🔴 백필 행이 행위자를 들고 들어왔다';
    exception when check_violation then null;
             when others then v_bad := v_bad || ' 백필+행위자 거절 이름=' || sqlerrm;
    end;
    begin
      insert into return_resolutions (booking_id, resolved_by, from_status, runner_stamped, owner_stamped, memo, source, evidence)
      values (bE, null, 'active', false, false, '모르는 기록자', 'backfill_9999', '{"x":1}'::jsonb);
      v_bad := v_bad || ' 🔴 모르는 source가 들어왔다';
    exception when check_violation then null;
             when others then v_bad := v_bad || ' 모르는 source 거절 이름=' || sqlerrm;
    end;
    begin
      insert into return_resolutions (booking_id, resolved_by, from_status, runner_stamped, owner_stamped, memo, source, evidence)
      values (bE, null, 'active', true, false, '모양이 맞는 백필 행', 'backfill_0218', '{"x":1}'::jsonb);
      delete from return_resolutions where booking_id = bE and memo = '모양이 맞는 백필 행';
    exception when others then
      v_bad := v_bad || ' 대조: 모양이 맞는 백필 행도 거절됐다 (CHECK이 전부를 막는다)=' || sqlerrm;
    end;
    select count(*)::int into v_n from return_resolutions where booking_id = bE;
    if v_n is distinct from 1 then v_bad := v_bad || ' 대조 뒤 저널 행 수=' || v_n; end if;
    -- still SEALED
    if (select relrowsecurity from pg_class where oid = 'return_resolutions'::regclass) is not true
      then v_bad := v_bad || ' return_resolutions에 RLS가 없다'; end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'return_resolutions')
      then v_bad := v_bad || ' return_resolutions에 정책이 있다 (클라이언트 표면)'; end if;
    if has_table_privilege('authenticated', 'public.return_resolutions', 'select') is not false
      then v_bad := v_bad || ' 저널이 authenticated에 열려 있다'; end if;
    if has_table_privilege('anon', 'public.return_resolutions', 'select') is not false
      then v_bad := v_bad || ' 저널이 anon에 열려 있다'; end if;

    if v_bad = ''
      then call _pass('fes','0218-S1 배포 형상 — force_return_tx는 definer·본문 search_path·ACL 양방향(service_role만)이고 주석 벗긴 소스에서 증거 칸은 _force_evidence_public을 받고 p_evidence는 절대 받지 않으면서 p_evidence는 저널 INSERT에 있고 evidence_required·토큰·당사자 거절·스탬프 비위조는 그대로다(크루드 대조 포함); 조합기는 값으로 다섯 키를 만들고 authenticated에 닫혀 있다; 수리는 definer·search_path·백필 source·저널 없음 조건·보존 NULL 조건·쓰려는 값 비교·ops 마커·토큰 목록을 갖고 닫혀 있다; 저널은 evidence jsonb 칸과 backfill_0218을 아는 CHECK 둘, 증거 CHECK(E4가 되돌린 정의)을 갖고 증거 없는 강제 행·행위자 든 백필 행·모르는 source를 거절하되 모양이 맞는 백필 행은 받으며(대조) 여전히 봉인이다. NO-FUNCTION·NO-SOURCE는 큰 소리로 실패');
    else v_msg := v_bad; call _fail('fes','0218-S1 배포 형상', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fes','0218-S1 배포 형상', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
