-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 253 — 0222: the 0218 §C repair preserves every non-NULL historical payload into the sealed
--       journal regardless of its equality with the public composer, invents nothing, and stays
--       idempotent
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Tag `fep`. Pins 0222-P1 · P2 · P3 · S1.
--
-- ─── WHAT EACH PIN ESTABLISHES, WITHOUT REFERENCE TO ANY MUTATION ───
--  · **0222-P1** — the constructible row codex 2026-09-25 #2 describes, PLANTED (a force-kind
--        journal row with NULL `evidence` whose `bookings` column holds EXACTLY the composer's
--        five-key output), beside a second row of the same shape whose column holds a caller's
--        object with a sentinel. The abort mechanism is REPRODUCED by value before the fix is
--        measured: 0218 ③'s own predicate, quoted, selects the caller-object row and NOT the
--        composed-payload row, and 0218's CHECK, issued on that state, raises `check_violation`
--        — the exact statement that aborted the apply in 0222's header. Then ONE repair call
--        preserves BOTH rows (preserved = 2, a delta the pin caused from a four-zero baseline),
--        the journal holds each payload by jsonb equality, the column is the composed shape on
--        both, neither party reads the sentinel any more, and the CHECK goes back on with 0218's
--        own definition and is accepted.
--  · **0222-P2** — idempotency, counted: a further call returns four zeros; the journal row count
--        and every fixture's (reason, evidence) pair are identical before and after; the composed
--        payload P1 preserved is still in the journal, byte-identical.
--  · **0222-P3** — nothing is INVENTED: a force-kind journal row with NULL `evidence` whose column
--        is ALSO NULL (a shape no door produces — every force since 0083 refuses NULL evidence —
--        planted by hand) is left alone by the repair on the first call AND on the second: the
--        journal stays NULL, the column is not composed on its behalf (the mechanism — a composed
--        column is exactly what a later ③ would copy into the journal as a caller's object), no
--        count moves, nothing raises. The fixture is then restored and the CHECK is re-accepted.
--  · **0222-S1** — the deployed shape of the re-declared repair: definer, in-body `search_path`,
--        ACL both ways (service_role only), comment-stripped source with ③'s three conjuncts
--        present, 0218's equality skip ABSENT, ④ keyed on journal evidence present and still
--        comparing against the value it writes, ①/② intact; crude control that the raw source
--        carries the words; 0218's CHECK back with 0218's definition. NO-FUNCTION / NO-SOURCE
--        fail loudly.
--
-- ─── NAMED GAPS (facts about the system, not blind pins) ───
--  · 🔴 **0222 cannot un-abort 0218.** If a database holds the P1 row when 0218 applies, 0218
--    aborts at its CHECK before 0222 exists (0222 §0c states the argument that bounds production
--    and the pre-flight query that would convert it into an observation). This suite proves the
--    canonical repair is correct wherever it runs; it cannot prove a push succeeds.
--  · The composed-payload row is preserved into the journal AS the caller's object. That is a
--    true statement about the fixture (the payload WAS the column's content) and an over-
--    preservation in the sealed journal, never a party-readable fact. Nothing here asserts
--    provenance, because nothing can.
--
-- ─── FIXTURE NOTES ───
--  ① This suite builds its OWN world (`t_fep_*`, `fep_` profiles); 249's helpers are not reused.
--  ② Every force is called WITHOUT a quote (0089's unpriced branch) — money is not what this is.
--  ③ P1 measures the repair's baseline FIRST (four zeros before any plant), so the counts after
--     are deltas the pin CAUSED. The harness applied 0222 before any suite ran, and 249 (which
--     runs earlier in `harness.sh`) leaves every one of its rows repaired.
--  ④ P1 and P3 plant the 0205 shape by dropping 0218's `return_resolutions_evidence_check` for the
--     plant and re-adding it with 0218's own definition; S1 asserts it is back. A plpgsql block
--     with a handler is a savepoint, so a raise mid-plant rolls the DROP back as well.
--  ⑤ P1's composed-payload row carries NO party stamp (both booleans false) and the sentinel row
--     carries ONE (runner), so the two composed values differ from each other and from a matched
--     pair a bug could produce by accident.
--
-- ─── MUTATION MAP — measured against these exact files, not predicted ───
-- In the REGISTRY row. Lab: a copy of `supabase/` OUTSIDE the worktree, every plant
-- assert-verified and CHAIN-GATED to its harness run (`plant && harness`).
set client_min_messages = warning;

-- ---------- suite-local fixtures ① ----------
create or replace function t_fep_live(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid)
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

-- age a stopped run (the run row moves with it)
create or replace function t_fep_age(p_booking uuid, p_ago interval) returns void
language sql as $$
  with b as (update bookings set run_ended_at = now() - p_ago where id = p_booking returning id)
  update runs set ended_at = now() - p_ago where booking_id = (select id from b)
$$;

-- the DIRECT two-column read a party holds — `select return_force_evidence, return_force_reason`
-- AS `authenticated` under that party's claim. Reports the columns OR the raise, never both.
create or replace function t_fep_cols_as(p_uid uuid, p_booking uuid) returns jsonb
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

-- one (party, booking) pair: the row must be READABLE (the control that makes 「absent」 mean
-- something) and the needle must not appear in the evidence column
create or replace function t_fep_leak(p_who text, p_uid uuid, p_booking uuid, p_needle text)
returns text language plpgsql as $$
declare v_js jsonb; v_bad text := '';
begin
  v_js := t_fep_cols_as(p_uid, p_booking);
  if v_js->>'raised' is not null then
    return ' ' || p_who || ' 읽기가 터졌다 [' || (v_js->>'raised') || ']';
  end if;
  if (v_js->>'n')::int is distinct from 1 then
    v_bad := v_bad || ' 대조: ' || p_who || '가 자기 예약을 못 읽는다 (n=' || coalesce(v_js->>'n', '?') || ')';
  end if;
  if (position(p_needle in coalesce(v_js->'cols'->>'evidence', '')) > 0) is not false then
    v_bad := v_bad || ' 🔴 ' || p_who || '가 읽는 증거 칸에 운영자 텍스트가 있다 (' || left(p_needle, 24) || ')';
  end if;
  return v_bad;
end $$;

do $$
declare
  oo uuid; rr uuid; dg uuid; rt uuid;
  ox uuid; rx uuid; dx uuid;
  pX uuid;                                   -- P1: the composed-payload row (codex #2's row)
  pY uuid;                                   -- P1: the caller-object row beside it
  pZ uuid;                                   -- P3: column NULL + journal NULL
  c_keys    constant text[] := array['forced_at', 'from_status', 'owner_stamped', 'runner_stamped', 'source'];
  c_zero    constant jsonb := '{"backfilled":0,"reasons_scrubbed":0,"evidence_preserved":0,"evidence_scrubbed":0}'::jsonb;
  c_evX0    constant jsonb := jsonb_build_object('kind', 'ops_review', 'src', 'fep-x');   -- what the LIVE force journals for X, before the plant
  c_evY     constant jsonb := jsonb_build_object('memo', 'FEP-SENTINEL-2231 운영자 사적 메모 — 당사자가 보면 안 됨', 'kind', 'ops_review');
  c_evZ0    constant jsonb := jsonb_build_object('kind', 'ops_review', 'src', 'fep-z');   -- restored after P3
  v_pubX jsonb; v_pubY jsonb; v_pubZ jsonb; v_tsX timestamptz; v_tsY timestamptz; v_tsZ timestamptz;
  v_bad text := ''; v_msg text; v_js jsonb; v_n int; v_src text; v_raw text; v_oid oid;
  v_txt text; v_ev jsonb; v_keys text[]; v_def text; v_cnt int; v_snap jsonb; v_snap2 jsonb;
begin
  perform set_config('request.jwt.claim.sub', '', false);
  oo := t_user('fep_oo', 'owner');   rr := t_user('fep_rr', 'runner');
  ox := t_user('fep_ox', 'owner');   rx := t_user('fep_rx', 'runner');
  dg := t_dog(oo, '보존견');          dx := t_dog(ox, '공백견');
  rt := t_route('증거 보존 코스');

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0222-P1] THE CONSTRUCTIBLE ROW — reproduced by VALUE, then preserved regardless of equality
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ③ baseline: the repair has nothing to do BEFORE anything is planted
    v_js := _seal_force_evidence_0218();
    if v_js is distinct from c_zero
      then v_bad := v_bad || ' 대조: 심기 전 수리가 무언가를 고쳤다=' || coalesce(v_js::text, '(null)'); end if;

    -- X: no party stamp (⑤) — a real force through the LIVE body
    pX := t_fep_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(pX, 3.0, 900, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_fep_age(pX, interval '5 hours');
    perform force_return_tx(pX, 'ops', '0205 시절 강제 — FEP-X-1101', c_evX0);
    -- Y: ONE party stamp (runner) — the same door, a caller object with a sentinel
    pY := t_fep_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(pY, 3.0, 900, 'completed', null, null);
    perform confirm_return_tx(pY, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_fep_age(pY, interval '5 hours');
    perform force_return_tx(pY, 'ops', '0205 시절 강제 — FEP-Y-1102', jsonb_build_object('kind', 'ops_review'));

    select b.return_forced_at into v_tsX from bookings b where b.id = pX;
    select b.return_forced_at into v_tsY from bookings b where b.id = pY;
    if v_tsX is null or v_tsY is null then v_bad := v_bad || ' 대조: 강제 시각이 NULL이다'; end if;
    -- the two composed values: X's from (active, false, false), Y's from (active, true, false)
    v_pubX := _force_evidence_public('active', false, false, v_tsX);
    v_pubY := _force_evidence_public('active', true,  false, v_tsY);
    if v_pubX is not distinct from v_pubY then v_bad := v_bad || ' 대조: 두 조합값이 같다 (⑤가 무너졌다)'; end if;

    -- ④ 0218 §A's CHECK forbids the shape being planted; dropped for the plant, re-added below
    alter table return_resolutions drop constraint return_resolutions_evidence_check;
    -- X = codex #2's row: journal NULL, column EXACTLY the five composed keys, as a 0205 shell
    --     caller could legally have typed them (0205's contract was any non-empty object)
    update return_resolutions set evidence = null where booking_id = pX;
    update bookings set return_force_evidence = v_pubX where id = pX;
    -- Y = the row 249 E4 already covers: journal NULL, the caller's object in the column
    update return_resolutions set evidence = null where booking_id = pY;
    update bookings set return_force_evidence = c_evY where id = pY;

    -- CONTROL: both plants landed
    if (select r.evidence from return_resolutions r where r.booking_id = pX) is not null
      then v_bad := v_bad || ' 대조: X 저널 증거가 NULL로 심기지 않았다'; end if;
    if (select b.return_force_evidence from bookings b where b.id = pX) is distinct from v_pubX
      then v_bad := v_bad || ' 대조: X 칸이 조합기 출력과 같게 심기지 않았다'; end if;
    if (select r.evidence from return_resolutions r where r.booking_id = pY) is not null
      then v_bad := v_bad || ' 대조: Y 저널 증거가 NULL로 심기지 않았다'; end if;
    if (select b.return_force_evidence from bookings b where b.id = pY) is distinct from c_evY
      then v_bad := v_bad || ' 대조: Y 칸에 호출자 객체가 심기지 않았다'; end if;
    -- CONTROL: the hole on Y is real (0218 #3 reproduced — the owner reads the sentinel)
    v_txt := t_fep_leak('보호자(수리 전)', oo, pY, 'FEP-SENTINEL-2231');
    if (position('FEP-SENTINEL-2231' in v_txt) > 0) is not true
      then v_bad := v_bad || ' 대조: 심은 뒤 보호자가 Y의 센티널을 못 읽는다 [' || v_txt || ']'; end if;

    -- 🔴 REPRODUCE THE MECHANISM BY VALUE (0218's body is gone from this DB — its predicate is not):
    --    (i) 0218 ③'s exact conjunct set, quoted, selects Y and NOT X — equality is what excluded X
    select count(*) into v_n
      from return_resolutions r join bookings b on b.id = r.booking_id
     where r.booking_id in (pX, pY)
       and r.source in ('force_return_tx', 'backfill_0218')
       and r.evidence is null
       and b.return_forced_by = 'ops'
       and b.return_force_evidence is not null
       and b.return_force_evidence is distinct from
           _force_evidence_public(r.from_status, r.runner_stamped, r.owner_stamped, b.return_forced_at);
    if v_n is distinct from 1
      then v_bad := v_bad || ' 대조: 0218 ③의 술어가 고른 행 수=' || coalesce(v_n::text, '(null)') || ' (Y 하나여야 — X는 같음으로 걸러진다)'; end if;
    select count(*) into v_n
      from return_resolutions r join bookings b on b.id = r.booking_id
     where r.booking_id = pX
       and b.return_force_evidence is distinct from
           _force_evidence_public(r.from_status, r.runner_stamped, r.owner_stamped, b.return_forced_at);
    if v_n is distinct from 0
      then v_bad := v_bad || ' 대조: X의 칸이 저널 행 기준 조합값과 다르다 (심기가 codex #2의 행이 아니다)'; end if;
    --    (ii) 0218:492-494 on this state — the statement that aborted the apply
    begin
      alter table return_resolutions add constraint return_resolutions_evidence_check
        check (source = 'ops_resolve_return_tx' or evidence is not null);
      -- it went ON: the world has no NULL row, the reproduction failed — take it off again so the
      -- rest of the pin can run, and say so
      alter table return_resolutions drop constraint return_resolutions_evidence_check;
      v_bad := v_bad || ' 🔴 대조: 심은 상태에서 0218의 CHECK이 붙었다 — 중단이 재현되지 않았다';
    exception when check_violation then null;
             when others then v_bad := v_bad || ' 대조: CHECK 재현의 오류 이름=' || sqlerrm;
    end;

    -- THE REPAIR — counts are a delta this pin caused (baseline was four zeros)
    v_js := _seal_force_evidence_0218();
    if (v_js->>'evidence_preserved')::int is distinct from 2
      then v_bad := v_bad || ' 🔴 evidence_preserved=' || coalesce(v_js->>'evidence_preserved', '(null)') || ' (2여야 — 같음과 무관하게 둘 다)'; end if;
    if (v_js->>'evidence_scrubbed')::int is distinct from 1
      then v_bad := v_bad || ' evidence_scrubbed=' || coalesce(v_js->>'evidence_scrubbed', '(null)') || ' (1이어야 — Y의 칸만)'; end if;
    if (v_js->>'backfilled')::int is distinct from 0
      then v_bad := v_bad || ' backfilled=' || coalesce(v_js->>'backfilled', '(null)') || ' (0이어야)'; end if;
    if (v_js->>'reasons_scrubbed')::int is distinct from 0
      then v_bad := v_bad || ' reasons_scrubbed=' || coalesce(v_js->>'reasons_scrubbed', '(null)') || ' (0이어야)'; end if;
    -- PRESERVED, by jsonb equality: X's journal holds the composed payload, Y's the caller object
    if (select r.evidence from return_resolutions r where r.booking_id = pX) is distinct from v_pubX
      then v_bad := v_bad || ' 🔴 X 저널 증거가 칸에 있던 다섯 키 객체가 아니다=' ||
        coalesce((select r.evidence::text from return_resolutions r where r.booking_id = pX), '(null)'); end if;
    if (select r.evidence from return_resolutions r where r.booking_id = pY) is distinct from c_evY
      then v_bad := v_bad || ' 🔴 Y 저널 증거가 호출자 객체가 아니다=' ||
        coalesce((select r.evidence::text from return_resolutions r where r.booking_id = pY), '(null)'); end if;
    -- the COLUMNS: X unchanged (already composed), Y scrubbed — both the composer's output, five keys
    select b.return_force_evidence into v_ev from bookings b where b.id = pX;
    if v_ev is distinct from v_pubX then v_bad := v_bad || ' X 칸이 수리 뒤 달라졌다=' || coalesce(v_ev::text, '(null)'); end if;
    select b.return_force_evidence into v_ev from bookings b where b.id = pY;
    if v_ev is distinct from v_pubY then v_bad := v_bad || ' Y 칸이 조합 모양이 아니다=' || coalesce(v_ev::text, '(null)'); end if;
    select array_agg(k order by k) into v_keys from jsonb_object_keys(coalesce(v_ev, '{}'::jsonb)) k;
    if v_keys is distinct from c_keys then v_bad := v_bad || ' Y 칸 키 집합=' || coalesce(array_to_string(v_keys, ','), '(null)'); end if;
    -- neither party reads the sentinel any more
    v_bad := v_bad || t_fep_leak('보호자(수리 후)', oo, pY, 'FEP-SENTINEL-2231');
    v_bad := v_bad || t_fep_leak('러너(수리 후)',  rr, pY, 'FEP-SENTINEL-2231');

    -- ④ 0218's CHECK goes back on with 0218's own definition — and is ACCEPTED, which is the
    --    sentence the whole slice exists for
    begin
      alter table return_resolutions add constraint return_resolutions_evidence_check
        check (source = 'ops_resolve_return_tx' or evidence is not null);
    exception when others then
      v_bad := v_bad || ' 🔴 수리 뒤에도 0218의 CHECK이 거절됐다 (적용 중단 그대로)=' || sqlerrm;
    end;

    if v_bad = ''
      then call _pass('fep','0222-P1 codex #2의 행 — 심기 전 수리는 0·0·0·0(기준선); 저널 evidence NULL이고 칸이 조합기 출력과 정확히 같은 행(X)과 칸에 센티널 든 호출자 객체가 있는 행(Y)을 심으면 보호자가 Y의 센티널을 읽고(대조), 0218 ③의 술어를 그대로 평가하면 Y만 고르고 X는 같음으로 걸러지며(재현 ⅰ), 그 상태에 0218의 CHECK을 붙이면 check_violation으로 거절된다(재현 ⅱ — 적용 중단의 바로 그 문장); 한 번의 수리로 preserved=2·scrubbed=1(델타), X 저널은 다섯 키 객체를 그대로, Y 저널은 호출자 객체를 그대로 보관하고 두 칸은 조합 모양이며 양쪽 당사자는 센티널을 못 읽고, 0218의 CHECK은 0218의 정의 그대로 다시 붙는다');
    else v_msg := v_bad; call _fail('fep','0222-P1 codex #2의 행', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fep','0222-P1 codex #2의 행', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0222-P2] IDEMPOTENCY, COUNTED — a further call changes nothing
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select count(*)::int into v_cnt from return_resolutions;
    select jsonb_agg(jsonb_build_object('id', b.id, 'r', b.return_force_reason, 'e', b.return_force_evidence) order by b.id)
      into v_snap from bookings b where b.id in (pX, pY);
    if v_cnt < 2 then v_bad := v_bad || ' 대조: 저널에 픽스처 행이 모자란다 (' || v_cnt || ')'; end if;
    if jsonb_array_length(coalesce(v_snap, '[]'::jsonb)) is distinct from 2
      then v_bad := v_bad || ' 대조: 스냅샷 행 수=' || jsonb_array_length(coalesce(v_snap, '[]'::jsonb)); end if;
    if (select r.evidence from return_resolutions r where r.booking_id = pX) is distinct from v_pubX
      then v_bad := v_bad || ' 대조: X 저널에 보존된 객체가 없다 (P1이 실패했다면 이 핀은 그 뒤를 잰다)'; end if;

    v_js := _seal_force_evidence_0218();
    if v_js is distinct from c_zero
      then v_bad := v_bad || ' 🔴 두 번째 수리가 무언가를 바꿨다=' || coalesce(v_js::text, '(null)'); end if;
    select count(*)::int into v_n from return_resolutions;
    if v_n is distinct from v_cnt
      then v_bad := v_bad || ' 🔴 두 번째 수리 뒤 저널 행 수 ' || v_cnt || ' → ' || v_n; end if;
    select jsonb_agg(jsonb_build_object('id', b.id, 'r', b.return_force_reason, 'e', b.return_force_evidence) order by b.id)
      into v_snap2 from bookings b where b.id in (pX, pY);
    if v_snap2 is distinct from v_snap
      then v_bad := v_bad || ' 🔴 두 번째 수리 뒤 예약 행의 (사유, 증거)가 달라졌다'; end if;
    if (select r.evidence from return_resolutions r where r.booking_id = pX) is distinct from v_pubX
      then v_bad := v_bad || ' 🔴 두 번째 수리가 X의 저널 증거를 바꿨다'; end if;
    if (select r.evidence from return_resolutions r where r.booking_id = pY) is distinct from c_evY
      then v_bad := v_bad || ' 🔴 두 번째 수리가 Y의 저널 증거를 바꿨다'; end if;

    if v_bad = ''
      then call _pass('fep','0222-P2 멱등 — 수리를 한 번 더 부르면 0·0·0·0을 돌려주고 저널 행 수와 두 픽스처의 (사유, 증거)가 전후 동일하며 X에 보존된 다섯 키 객체와 Y의 호출자 객체가 그대로다');
    else v_msg := v_bad; call _fail('fep','0222-P2 멱등', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fep','0222-P2 멱등', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0222-P3] NOTHING IS INVENTED — column NULL + journal NULL stays NULL, on the first call and
  --           the second (the second is where a composed column would have become 「evidence」)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    pZ := t_fep_live(ox, dx, rt, rx);
    perform set_config('request.jwt.claim.sub', rx::text, false);
    perform end_run_tx(pZ, 3.0, 900, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_fep_age(pZ, interval '5 hours');
    perform force_return_tx(pZ, 'ops', '공백 강제 — FEP-Z-1103', c_evZ0);
    select b.return_forced_at into v_tsZ from bookings b where b.id = pZ;
    v_pubZ := _force_evidence_public('active', false, false, v_tsZ);
    -- CONTROL: the live door journalled the object and composed the column (so the NULLs below
    -- are NULLs of things that existed)
    if (select r.evidence from return_resolutions r where r.booking_id = pZ) is distinct from c_evZ0
      then v_bad := v_bad || ' 대조: 살아있는 강제가 저널에 객체를 쓰지 않았다'; end if;
    if (select b.return_force_evidence from bookings b where b.id = pZ) is distinct from v_pubZ
      then v_bad := v_bad || ' 대조: 살아있는 강제가 칸을 조합하지 않았다'; end if;

    -- ④ the plant: BOTH NULL — a shape no door produces (evidence_required since 0083)
    alter table return_resolutions drop constraint return_resolutions_evidence_check;
    update return_resolutions set evidence = null where booking_id = pZ;
    update bookings set return_force_evidence = null where id = pZ;
    if (select r.evidence from return_resolutions r where r.booking_id = pZ) is not null
      then v_bad := v_bad || ' 대조: Z 저널 증거가 NULL로 심기지 않았다'; end if;
    if (select b.return_force_evidence from bookings b where b.id = pZ) is not null
      then v_bad := v_bad || ' 대조: Z 칸이 NULL로 심기지 않았다'; end if;

    -- FIRST call: no count moves, nothing raises, nothing is written for Z
    v_js := _seal_force_evidence_0218();
    if v_js is distinct from c_zero
      then v_bad := v_bad || ' 🔴 첫 수리가 NULL/NULL 행에서 무언가를 했다=' || coalesce(v_js::text, '(null)'); end if;
    if (select r.evidence from return_resolutions r where r.booking_id = pZ) is not null
      then v_bad := v_bad || ' 🔴 첫 수리가 저널 증거를 지어냈다=' ||
        coalesce((select r.evidence::text from return_resolutions r where r.booking_id = pZ), '(null)'); end if;
    -- the mechanism: the column is NOT composed on a journal-less row (a composed column is what
    -- the next ③ would copy into the journal)
    if (select b.return_force_evidence from bookings b where b.id = pZ) is not null
      then v_bad := v_bad || ' 🔴 첫 수리가 저널 증거 없는 행의 칸을 조합했다 (다음 호출의 ③이 베낄 값)=' ||
        coalesce((select b.return_force_evidence::text from bookings b where b.id = pZ), '(null)'); end if;
    -- SECOND call: the same — this is the arm that sees a two-step fabrication
    v_js := _seal_force_evidence_0218();
    if v_js is distinct from c_zero
      then v_bad := v_bad || ' 🔴 두 번째 수리가 NULL/NULL 행에서 무언가를 했다=' || coalesce(v_js::text, '(null)'); end if;
    if (select r.evidence from return_resolutions r where r.booking_id = pZ) is not null
      then v_bad := v_bad || ' 🔴 두 번째 수리가 저널 증거를 지어냈다 (두 단계 조작)=' ||
        coalesce((select r.evidence::text from return_resolutions r where r.booking_id = pZ), '(null)'); end if;
    if (select b.return_force_evidence from bookings b where b.id = pZ) is not null
      then v_bad := v_bad || ' 🔴 두 번째 수리가 칸을 조합했다'; end if;
    -- the neighbours are untouched: X's and Y's journal and columns as P1 left them
    if (select r.evidence from return_resolutions r where r.booking_id = pX) is distinct from v_pubX
      then v_bad := v_bad || ' X 저널이 달라졌다'; end if;
    if (select b.return_force_evidence from bookings b where b.id = pY) is distinct from v_pubY
      then v_bad := v_bad || ' Y 칸이 달라졌다'; end if;

    -- restore the fixture to what the live door wrote, then ④ the CHECK back on — accepted
    update return_resolutions set evidence = c_evZ0 where booking_id = pZ;
    update bookings set return_force_evidence = v_pubZ where id = pZ;
    begin
      alter table return_resolutions add constraint return_resolutions_evidence_check
        check (source = 'ops_resolve_return_tx' or evidence is not null);
    exception when others then
      v_bad := v_bad || ' 🔴 되돌린 뒤에도 0218의 CHECK이 거절됐다=' || sqlerrm;
    end;
    -- and a third call on the restored world is still four zeros (the restore did not create work)
    v_js := _seal_force_evidence_0218();
    if v_js is distinct from c_zero
      then v_bad := v_bad || ' 되돌린 뒤 수리가 무언가를 했다=' || coalesce(v_js::text, '(null)'); end if;

    if v_bad = ''
      then call _pass('fep','0222-P3 지어내지 않는다 — 살아있는 강제가 저널·칸을 채운 뒤(대조) 둘 다 NULL로 심으면(어느 문도 만들 수 없는 모양) 첫 수리도 두 번째 수리도 0·0·0·0을 돌려주고 저널 증거를 지어내지 않으며 칸도 조합하지 않는다(조합된 칸은 다음 호출의 ③이 저널로 베낄 값 — 두 단계 조작의 기제); 이웃 X·Y는 그대로고, 픽스처를 되돌리면 0218의 CHECK이 다시 붙고 세 번째 호출도 0이다');
    else v_msg := v_bad; call _fail('fep','0222-P3 지어내지 않는다', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fep','0222-P3 지어내지 않는다', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0222-S1] THE DEPLOYED SHAPE — the re-declared repair, source arms comment-stripped
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
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
        -- ③ preserves by PRESENCE
        if (v_src ~ 'set evidence\s*=\s*b\.return_force_evidence') is not true
          then v_bad := v_bad || ' 수리 ③: 저널 evidence에 칸 값을 배정하지 않는다'; end if;
        if (v_src ~ 'r\.evidence is null') is not true
          then v_bad := v_bad || ' 수리 ③: 보존이 이미 보존된 행을 다시 덮는다'; end if;
        if (v_src ~ 'b\.return_force_evidence is not null') is not true
          then v_bad := v_bad || ' 수리 ③: 칸이 NULL인 행에 NULL을 「보존」한다'; end if;
        -- 🔴 0218's equality skip — the composer called on the JOURNAL row's own fields beside the
        --    column — must be ABSENT. ④'s comparison uses the `x.` subquery and is the next arm.
        if (v_src ~ 'return_force_evidence\s+is\s+distinct\s+from\s+_force_evidence_public\(\s*r\.') is not false
          then v_bad := v_bad || ' 🔴 수리 ③: 칸 값이 조합기 출력과 같으면 보존을 건너뛴다 (codex #2 그대로)'; end if;
        if (v_src ~ 'return_force_evidence is distinct from\s+_force_evidence_public\(x\.') is not true
          then v_bad := v_bad || ' 수리 ④: 스크럽이 쓰려는 값과 비교하지 않는다'; end if;
        if (v_src ~ 'r\.evidence is not null') is not true
          then v_bad := v_bad || ' 수리 ④: 저널 증거 없는 행의 칸을 조합한다'; end if;
        -- ①/② intact
        if (v_src ~ '''backfill_0218''') is not true
          then v_bad := v_bad || ' 수리 ①: 백필 행을 쓰지 않는다'; end if;
        if (v_src ~ 'not exists \(select 1 from return_resolutions') is not true
          then v_bad := v_bad || ' 수리 ①: 「저널 행 없음」 조건이 없다'; end if;
        if (v_src ~ 'return_forced_by = ''ops''') is not true
          then v_bad := v_bad || ' 수리: ops 마커 조건이 없다'; end if;
        if (v_src ~ '''ops_resolved:strand''') is not true or (v_src ~ '''ops_resolved:review''') is not true
          then v_bad := v_bad || ' 수리 ②: 알려진 토큰 목록이 빠졌다'; end if;
        -- CRUDE CONTROL: the raw source DOES carry the words these arms look for
        if (v_raw ~ '_force_evidence_public') is not true
          then v_bad := v_bad || ' 대조: 원본 소스에 _force_evidence_public이 없다 (주석 제거 팔이 무의미)'; end if;
        if (v_raw ~ 'return_force_evidence') is not true
          then v_bad := v_bad || ' 대조: 원본 소스에 return_force_evidence가 없다'; end if;
      end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 수리가 authenticated에 열려 있다'; end if;
      if has_function_privilege('anon', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 수리가 anon에 열려 있다'; end if;
      if has_function_privilege('service_role', v_oid, 'execute') is not true
        then v_bad := v_bad || ' 수리를 service_role이 실행할 수 없다'; end if;
    end if;

    -- 0218's CHECK, back with 0218's definition (P1/P3 re-add it; a pin that dropped it and died
    -- rolled the drop back — either way it must be here)
    select pg_get_constraintdef(oid) into v_def from pg_constraint
     where conrelid = 'return_resolutions'::regclass and conname = 'return_resolutions_evidence_check';
    if v_def is null then v_bad := v_bad || ' 저널: 증거 CHECK이 없다 (P1/P3이 되돌리지 않았다?)';
    elsif (v_def ~ 'evidence IS NOT NULL') is not true
      then v_bad := v_bad || ' 저널: 증거 CHECK의 정의가 다르다=' || v_def; end if;
    -- …and it still refuses the shape this slice is about (a force-kind row with NULL evidence)
    begin
      insert into return_resolutions (booking_id, resolved_by, from_status, runner_stamped, owner_stamped, memo, source, evidence)
      values (pX, null, 'active', false, false, '증거 없는 강제 행', 'force_return_tx', null);
      v_bad := v_bad || ' 🔴 증거 없는 강제 행이 들어왔다';
    exception when check_violation then null;
             when others then v_bad := v_bad || ' 증거 없음 거절 이름=' || sqlerrm;
    end;
    -- still SEALED
    if (select relrowsecurity from pg_class where oid = 'return_resolutions'::regclass) is not true
      then v_bad := v_bad || ' return_resolutions에 RLS가 없다'; end if;
    if has_table_privilege('authenticated', 'public.return_resolutions', 'select') is not false
      then v_bad := v_bad || ' 저널이 authenticated에 열려 있다'; end if;

    if v_bad = ''
      then call _pass('fep','0222-S1 배포 형상 — 다시 선언된 수리는 definer·본문 search_path·ACL 양방향(service_role만)이고, 주석 벗긴 소스에서 ③은 칸 값 배정·저널 NULL 조건·칸 not null 조건을 갖되 저널 행 기준 조합값과의 같음 비교(0218의 건너뛰기)는 없으며, ④는 쓰려는 값과 비교하고 저널 증거 있는 행만 고르고, ①·②(백필 source·저널 없음 조건·ops 마커·토큰 목록)는 그대로다(크루드 대조 포함); 0218의 증거 CHECK은 0218의 정의 그대로 붙어 있어 증거 없는 강제 행을 거절하고 저널은 여전히 봉인이다. NO-FUNCTION·NO-SOURCE는 큰 소리로 실패');
    else v_msg := v_bad; call _fail('fep','0222-S1 배포 형상', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('fep','0222-S1 배포 형상', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
