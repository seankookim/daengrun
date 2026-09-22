-- ═══ 232 — 0201: the ops memo stops being party-readable, and late stamps stop hiding a strand ═══
-- ═══        0201-M1 · M2 · L1 · G1 · S1, tag `sml`                                           ═══
--
-- THE PROPOSITIONS THIS FILE OWNS. Each is stated WITHOUT reference to any mutation, because a pin
-- written while staring at a mutation tends to assert what that mutation broke rather than the
-- property the guard exists to hold (CLAUDE.md, the mid-battery law).
--
--   · M1 **THE OPS MEMO IS NOT READABLE BY A PARTY, THROUGH THE DOOR A PARTY ACTUALLY USES.** A
--        sentinel memo is written through the REAL resolver, on TWO bookings — one rescued from
--        `active`, one from `incident_review` — and then each booking's whole row is read AS
--        `authenticated`, by the OWNER and by the RUNNER, exactly as `fetchBookingSync` reads it.
--        The sentinel appears in NO value of either row, for either party. `return_force_reason`
--        carries the rescued-from TOKEN, and the two tokens DIFFER, so a hard-wired constant
--        cannot satisfy both arms. Controls, because an absence pin over a world that never held
--        the thing is worth zero (`0151` N1/N2): the journal still holds the memo verbatim, the
--        party's read really does return a row, and a stranger's identical read returns none.
--        0199's `note_public` is asserted unchanged in the same block — the party-facing sentence
--        is still 0199's and did not silently become the token.
--   · M2 **THE COPIES 0193 ALREADY WROTE ARE SCRUBBED, AND ONLY THOSE.** Two bookings are put into
--        the PRE-0201 data shape by hand (the memo planted back into `return_force_reason` after a
--        real resolution — the fixture must contain the defect or the repair is untestable), one
--        from each rescued-from state. A THIRD booking is forced through `force_return_tx`, which
--        writes free text to the same column and leaves NO journal row. One call: both planted rows
--        carry their token, the memo is gone from both, `force_return_tx`'s reason is untouched,
--        and every journal memo survives. A second call changes nothing (idempotent, returns 0).
--   · L1 **AN UNSEALED `incident_review` RETURN IS A STRAND WHATEVER ITS STAMP COUNT.** The REAL
--        sweep escalates a zero-stamp return; both parties then stamp LATE and 0096 lets the stamps
--        land while refusing to seal (asserted, because that is the state the finding is about);
--        with the flag armed the next tick reports it to the `return_strand` roster EXACTLY ONCE,
--        and `ops_resolve_return_tx` settles it. Controls: with `return_strand_minutes` NULL the
--        arm is still inert on this very row (the off switch was not traded away for the fix), a
--        second tick adds nothing, and a SEALED `incident_review` row aged past the same deadline
--        is NOT reported — the seal exclusion survived the widening.
--   · G1 `ops_is_member` answers about a roster and only about a roster: an active `return_strand`
--        recipient is true, a stranger is false, a `payout_due`-only recipient is FALSE for
--        `return_strand` and TRUE for their own class (so `p_kind` is an argument and not
--        decoration), and an `active = false` row is false. A caller with an identity of its own
--        is refused `not_party` (control: the same pair with no identity answers true); a NULL
--        actor and a blank kind are refused by name; and the ACL is asserted in both directions —
--        `authenticated` and `anon` cannot execute it at all, `service_role` can.
--   · S1 Deployed shape for all four objects: definer + in-body `search_path`, ACL by effective
--        privilege in BOTH directions, and comment-STRIPPED source arms that distinguish the fixed
--        world from the broken one — `return_force_reason` assigned from `v_reason` and never from
--        `v_memo`, the memo still reaching the journal, the sweep's new disjunct present in BOTH
--        the candidate query and the locked-row recheck with the OLD conjunct absent from each,
--        and 0193's own invariants (5 executable row locks, the job lock, the two `safety`
--        inserts, the seal exclusion) intact after the re-declaration. NO-FUNCTION / NO-SOURCE
--        arms fail loudly rather than passing on an absence.
--
-- ─── WHAT THIS SUITE DELIBERATELY DOES NOT OWN ───
--  · 0193's own properties (the exit, the refusals, the bell's off switch, B5, C9) belong to 224,
--    and 0199's party gate belongs to 230. Nothing here re-asserts them. Two arms in those files
--    MOVED in this slice and are named in their own comments — `224 0193-R1` and `230 0199-V5`
--    both asserted that the memo was in `bookings.return_force_reason`, which was true and was the
--    defect.
--  · 🔴 **NAMED GAP (a fact about the system, not a blind pin).** The `active` half of arm ⓕ's new
--    disjunct is NOT separately observable in this harness: it would need an `active` booking with
--    BOTH return stamps and no seal, and no path reaches that state — a client-class second stamp
--    on an `active` row seals it (0096 §6) and a server-class one without a price is refused
--    (0193 §B). So L1 proves the `incident_review` arm ADMITS and that a sealed row is still
--    excluded; it does not prove the `active` arm is load-bearing. `0201-S1` holds it by source.
--  · 🔴 **NAMED GAP.** `force_return_tx` writes free text to the same party-readable column and
--    0201 deliberately leaves it (zero callers — measured; see 0201 §0b). M2 pins that the SCRUB
--    does not touch such a row; nothing here pins that writing free text there is fine, because it
--    is not — a pin over that function's current shape would fix the bug in place.
--
-- ─── FIXTURE NOTES ───
--  ① This suite builds its OWN world (`t_sml_*`, `sml_` profiles) rather than borrowing 224's.
--     A pin that inherits another suite's setup is testing that setup (`175 V2`'s law), and 224's
--     fixtures move for 224's reasons.
--  ② `ops_recipients` gets FOUR rows in three classes, all on profiles this file creates: an
--     active `return_strand` operator, a `payout_due`-only operator, and an INACTIVE
--     `return_strand` row. G1 needs all three to show `p_kind` and `active` are real predicates.
--  ③ `ops_flags.return_strand_minutes` is read as NULL first (the shipped value — the off switch is
--     the property, not an accident of ordering), armed for L1, then **reset to NULL** at the end
--     of L1 and in its exception handler, so any later suite sees what production sees.
--  ④ M2 plants the memo back into `return_force_reason` BY HAND, after a real resolution. That is
--     the point rather than a shortcut: today's resolver cannot produce the row the scrub exists to
--     repair, so a fixture built only from today's code could not contain the defect (`0151`'s
--     measured lesson, in the direction where the current code is the wrong fixture).
--  ⑤ L1's sealed control is likewise hand-sealed on an escalated row. `confirm_return_tx` refuses
--     to seal in `incident_review` (0096) and that refusal is the whole finding, so the one state
--     that isolates the seal exclusion from the stamp predicate has to be written directly. Both
--     plants run as `postgres`; 0057/0083's column guards fire only for `authenticated`/`anon`.
--
-- ─── MUTATION MAP — measured against these exact files, not predicted ───
-- In the REGISTRY row. Lab: a copy of `supabase/` OUTSIDE the worktree, every plant assert-verified
-- and CHAIN-GATED to its harness run (`plant && harness`), control observed clean FIRST.
set client_min_messages = warning;

-- ---------- suite-local fixtures ① ----------
-- A marketplace run that is LIVE (started, not stopped). Sibling of 224's `t_crs_live`.
create or replace function t_sml_live(p_owner uuid, p_dog uuid, p_route uuid, p_runner uuid)
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
create or replace function t_sml_quote(p_km numeric) returns jsonb
language sql immutable as $$
  select jsonb_build_object(
    'base', 9900, 'distance_pay', round(p_km * 3000)::int, 'addon_pay', 0,
    'guarantee', 0, 'fee', round((9900 + round(p_km * 3000)) * 0.2)::int)
$$;

-- age a stopped run so the sweep's deadlines are past (the run row moves with it — a frozen stop
-- whose `runs.ended_at` disagrees with `bookings.run_ended_at` is not a state the product makes)
create or replace function t_sml_age(p_booking uuid, p_ago interval) returns void
language sql as $$
  with b as (update bookings set run_ended_at = now() - p_ago where id = p_booking returning id)
  update runs set ended_at = now() - p_ago where booking_id = (select id from b)
$$;

-- Read ONE booking row exactly as the app reads it — AS `authenticated`, under that party's claim,
-- whole row as JSON. Reports the row OR the raise, never both and never a swallowed success, so
-- 「the memo is absent」 and 「nothing could be read at all」 are two different answers.
create or replace function t_sml_row_as(p_uid uuid, p_booking uuid) returns jsonb
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

-- One (party, booking) pair, fully judged: the row must be readable (the control that makes
-- 「absent」 mean something) and NONE of the needles may appear anywhere in it. Returns the failure
-- text, empty when clean — a function rather than four copies of the same nine lines, because a
-- copy is a place to drift.
create or replace function t_sml_leak(p_who text, p_uid uuid, p_booking uuid, p_needles text[])
returns text language plpgsql as $$
declare v_js jsonb; v_bad text := ''; v_needle text;
begin
  v_js := t_sml_row_as(p_uid, p_booking);
  if v_js->>'raised' is not null then
    return ' ' || p_who || ' 읽기가 터졌다 [' || (v_js->>'raised') || ']';
  end if;
  if (v_js->>'n')::int is distinct from 1 then
    v_bad := v_bad || ' 대조: ' || p_who || '가 자기 예약을 못 읽는다 (n=' || coalesce(v_js->>'n','?') || ')';
  end if;
  foreach v_needle in array p_needles loop
    if (position(v_needle in coalesce(v_js->>'row', '')) > 0) is not false then
      v_bad := v_bad || ' 🔴 ' || p_who || '가 읽는 예약 행에 운영 메모가 있다 (' || left(v_needle, 24) || ')';
    end if;
  end loop;
  return v_bad;
end $$;

-- the 0199 party-facing read, as one party, flattened — so M1 can assert the sentence did not
-- silently become the token.
create or replace function t_sml_note_as(p_uid uuid, p_booking uuid) returns jsonb
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

-- How many strand bells this booking has been given — to ONE recipient, or to everybody when
-- `p_profile` is NULL. ⚠ The per-recipient form is the one that matters: `return_strand` is a
-- SHARED roster and 224 puts its own operator on it, so a global count over this title measures
-- other suites' fixtures as well as this one's (231's fixture note ⑤, same trap).
create or replace function t_sml_bells(p_booking uuid, p_profile uuid default null) returns int
language sql as $$
  select count(*)::int from notifications
   where ref_id = p_booking and title = '반환 좌초 — 확인 필요'
     and (p_profile is null or profile_id = p_profile)
$$;

do $$
declare
  oo uuid; rr uuid; oz uuid; rz uuid; dg uuid; dz uuid; rt uuid;
  sx uuid;                                  -- a stranger with no relationship to anything here
  ops uuid; opd uuid; opx uuid;             -- return_strand · payout_due only · return_strand INACTIVE
  bS uuid; bI uuid;                         -- M1: rescued from active / from incident_review
  pA uuid; pI uuid; pF uuid;                -- M2: two planted copies + one force_return_tx row
  bL uuid; bSeal uuid;                      -- L1: the late-stamped strand + the sealed control
  c_memo  constant text := '보호자와 통화 — SML-SENTINEL-4417 개는 집에 있다고 확인';
  c_memo2 constant text := 'CCTV 확인 — SML-SENTINEL-9023 귀가 확인됨';
  c_tok_s constant text := 'ops_resolved:strand';
  c_tok_r constant text := 'ops_resolved:review';
  c_free  constant text := '강제 종료 사유 SML-FORCE-5150 — 손으로 적은 문장';
  c_bell  constant text := '반환 좌초 — 확인 필요';
  v_bad text := ''; v_msg text; v_js jsonb; v_js2 jsonb; v_n int; v_src text; v_raw text;
  v_oid oid; v_txt text;
begin
  perform set_config('request.jwt.claim.sub', '', false);
  oo := t_user('sml_oo', 'owner');   oz := t_user('sml_oz', 'owner');
  rr := t_user('sml_rr', 'runner');  rz := t_user('sml_rz', 'runner');
  sx := t_user('sml_sx', 'owner');
  dg := t_dog(oo, '메모견');          dz := t_dog(oz, '늦은견');
  rt := t_route('좌초 메모 코스');
  ops := t_user('sml_ops', 'owner');
  opd := t_user('sml_opd', 'owner');
  opx := t_user('sml_opx', 'owner');
  -- ② three classes, three answers
  insert into ops_recipients (profile_id, event_class, active) values
    (ops, 'return_strand', true),
    (opd, 'payout_due',    true),
    (opx, 'return_strand', false)
  on conflict (profile_id, event_class) do nothing;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0201-M1] THE OPS MEMO IS NOT A PARTY-READABLE FACT
  -- 🔴 Read through the door a party actually holds: role `authenticated`, that party's claim, the
  --    whole `bookings` row. 0199's V5 tested the RPC and was green while the memo sat one
  --    PostgREST call away — the finding is about the SECOND copy, so the pin reads the column.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ⓐ a ONE-STAMP strand, rescued from `active`
    bS := t_sml_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(bS, 4.0, 1500, 'completed', null, null);
    perform confirm_return_tx(bS, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_sml_age(bS, interval '5 hours');
    v_js := ops_resolve_return_tx(bS, t_sml_quote(4.0), c_memo, ops);
    if (v_js->>'from_status') is distinct from 'active'
      then v_bad := v_bad || ' ⓐ from_status=' || coalesce(v_js->>'from_status','(null)'); end if;

    -- ⓑ a ZERO-STAMP timeout, escalated by the REAL sweep, rescued from `incident_review`
    bI := t_sml_live(oz, dz, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(bI, 3.0, 1200, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_sml_age(bI, interval '5 hours');
    perform sweep_run_end_recovery();
    if (select b.status::text from bookings b where b.id = bI) <> 'incident_review'
      then v_bad := v_bad || ' ⓑ 픽스처가 승격되지 않았다'; end if;
    v_js := ops_resolve_return_tx(bI, t_sml_quote(3.0), c_memo2, ops);
    if (v_js->>'from_status') is distinct from 'incident_review'
      then v_bad := v_bad || ' ⓑ from_status=' || coalesce(v_js->>'from_status','(null)'); end if;

    -- CONTROL ①: the sentinels really are in the database. Without this the arms below are an
    -- absence pin over an empty world (0151 N1/N2's lesson).
    if (select r.memo from return_resolutions r where r.booking_id = bS) is distinct from c_memo
      then v_bad := v_bad || ' 대조: 저널에 ⓐ의 운영 메모가 없다'; end if;
    if (select r.memo from return_resolutions r where r.booking_id = bI) is distinct from c_memo2
      then v_bad := v_bad || ' 대조: 저널에 ⓑ의 운영 메모가 없다'; end if;

    -- THE TOKEN, and the two answers DIFFER — a constant cannot satisfy both
    if (select b.return_force_reason from bookings b where b.id = bS) is distinct from c_tok_s
      then v_bad := v_bad || ' ⓐ 판정 토큰=' || coalesce((select b.return_force_reason from bookings b where b.id = bS), '(null)'); end if;
    if (select b.return_force_reason from bookings b where b.id = bI) is distinct from c_tok_r
      then v_bad := v_bad || ' ⓑ 판정 토큰=' || coalesce((select b.return_force_reason from bookings b where b.id = bI), '(null)'); end if;
    if c_tok_s = c_tok_r then v_bad := v_bad || ' 대조: 두 토큰이 같은 낱말이다 (상수가 통과한다)'; end if;

    -- THE READ, as each party, on each booking — over the WHOLE row rather than one column, so a
    -- memo that rode a different column or arrived concatenated into another value is caught too.
    -- Both sentinels AND both full memos are needles on BOTH rows: a resolver that wrote the wrong
    -- booking's memo would otherwise look clean.
    v_bad := v_bad
      || t_sml_leak('ⓐ 보호자', oo, bS, array['SML-SENTINEL-4417', 'SML-SENTINEL-9023', c_memo, c_memo2])
      || t_sml_leak('ⓐ 러너',   rr, bS, array['SML-SENTINEL-4417', 'SML-SENTINEL-9023', c_memo, c_memo2])
      || t_sml_leak('ⓑ 보호자', oz, bI, array['SML-SENTINEL-4417', 'SML-SENTINEL-9023', c_memo, c_memo2])
      || t_sml_leak('ⓑ 러너',   rz, bI, array['SML-SENTINEL-4417', 'SML-SENTINEL-9023', c_memo, c_memo2]);

    -- CONTROL ②: a stranger's identical read returns nothing, so 「the memo is absent」 is not
    -- 「this session cannot read bookings at all」.
    v_js := t_sml_row_as(sx, bS);
    if v_js->>'raised' is not null then v_bad := v_bad || ' 남 읽기가 터졌다 [' || (v_js->>'raised') || ']';
    elsif (v_js->>'n')::int is distinct from 0
      then v_bad := v_bad || ' 🔴 남이 이 예약을 읽었다 (n=' || coalesce(v_js->>'n','?') || ')'; end if;

    -- 0199's sentence is STILL 0199's — the party-facing copy did not become the token
    v_js  := t_sml_note_as(oo, bS);
    v_js2 := t_sml_note_as(rz, bI);
    if (v_js->'rows'->0->>'note_public') is distinct from '운영팀이 귀가를 확인 처리했어요'
      then v_bad := v_bad || ' 0199의 active 문장이 바뀌었다=' || coalesce(v_js->'rows'->0->>'note_public','(null)'); end if;
    if (v_js2->'rows'->0->>'note_public') is distinct from '운영팀이 검토 후 정산 처리했어요'
      then v_bad := v_bad || ' 0199의 incident_review 문장이 바뀌었다=' || coalesce(v_js2->'rows'->0->>'note_public','(null)'); end if;
    if (position('SML-SENTINEL' in coalesce(v_js::text, '') || coalesce(v_js2::text, '')) > 0) is not false
      then v_bad := v_bad || ' 🔴 운영 메모가 0199의 당사자 답에 실렸다'; end if;

    if v_bad = ''
      then call _pass('sml','0201-M1 운영 메모는 당사자가 읽는 예약 행에 없다 — 실제 문으로 쓴 센티넬 메모 두 개가 **봉인된 저널에는 그대로 있고**(대조), authenticated 롤로 각 당사자(보호자·러너)가 읽은 예약 행 **전체 JSON**의 어떤 값에도 없다; return_force_reason에는 구조된 상태가 고르는 토큰이 있고 active와 incident_review의 답이 **서로 달라** 상수는 통과하지 못한다; 남은 같은 행을 0행으로 읽고(대조) 0199의 당사자 문장 두 개는 그대로다');
    else v_msg := v_bad; call _fail('sml','0201-M1 운영 메모 비노출(당사자 직접 읽기)', v_msg); end if;
  exception when others then reset role; perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('sml','0201-M1 운영 메모 비노출(당사자 직접 읽기)', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0201-M2] THE SCRUB — the rows 0193 already wrote, and NOTHING ELSE
  -- 🔴 The fixture is planted BY HAND (④) because today's resolver cannot produce the row the
  --    repair exists for. A fixture that omits the defect cannot test the fix, and the pin reads
  --    identically in both worlds.
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ⓐ a resolved-from-`active` row, then the PRE-0201 data shape planted back
    pA := t_sml_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(pA, 4.0, 1400, 'completed', null, null);
    perform confirm_return_tx(pA, 'runner');
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_sml_age(pA, interval '5 hours');
    perform ops_resolve_return_tx(pA, t_sml_quote(4.0), c_memo, ops);
    update bookings set return_force_reason = c_memo where id = pA;

    -- ⓑ the same, from `incident_review`, so the scrub's own `case` is measured in two directions
    pI := t_sml_live(oz, dz, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(pI, 3.0, 1000, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_sml_age(pI, interval '5 hours');
    perform sweep_run_end_recovery();
    perform ops_resolve_return_tx(pI, t_sml_quote(3.0), c_memo2, ops);
    update bookings set return_force_reason = c_memo2 where id = pI;

    -- ⓒ a `force_return_tx` row: `return_forced_by = 'ops'`, free text, and NO journal row. This is
    --    the arm that separates 「scrubbed the 0193 copies」 from 「overwrote every ops reason」.
    pF := t_sml_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(pF, 3.0, 900, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_sml_age(pF, interval '5 hours');
    perform force_return_tx(pF, 'ops', c_free, jsonb_build_object('source', 'sml fixture'), t_sml_quote(3.0));

    -- CONTROL: all three plants landed, in the shape the scrub is about
    if (select b.return_force_reason from bookings b where b.id = pA) is distinct from c_memo
      then v_bad := v_bad || ' 대조: ⓐ의 옛 사본이 심기지 않았다'; end if;
    if (select b.return_force_reason from bookings b where b.id = pI) is distinct from c_memo2
      then v_bad := v_bad || ' 대조: ⓑ의 옛 사본이 심기지 않았다'; end if;
    if (select b.return_force_reason from bookings b where b.id = pF) is distinct from c_free
      then v_bad := v_bad || ' 대조: ⓒ의 force_return_tx 사유가 없다'; end if;
    if (select b.return_forced_by from bookings b where b.id = pF) is distinct from 'ops'
      then v_bad := v_bad || ' 대조: ⓒ에 ops 마커가 없다 (조인 밖이라서가 아니라 마커가 없어서 남는다면 이 팔은 무의미)'; end if;
    if exists (select 1 from return_resolutions where booking_id = pF)
      then v_bad := v_bad || ' 대조: ⓒ에 저널 행이 있다 (force_return_tx가 저널을 쓰게 됐다)'; end if;

    -- THE REPAIR
    select _scrub_ops_return_reasons() into v_n;
    if v_n is distinct from 2 then v_bad := v_bad || ' 스크럽 행 수=' || coalesce(v_n::text,'(null)') || ' (2여야)'; end if;
    if (select b.return_force_reason from bookings b where b.id = pA) is distinct from c_tok_s
      then v_bad := v_bad || ' ⓐ 스크럽 뒤 값=' || coalesce((select b.return_force_reason from bookings b where b.id = pA),'(null)'); end if;
    if (select b.return_force_reason from bookings b where b.id = pI) is distinct from c_tok_r
      then v_bad := v_bad || ' ⓑ 스크럽 뒤 값=' || coalesce((select b.return_force_reason from bookings b where b.id = pI),'(null)'); end if;
    if (select b.return_force_reason from bookings b where b.id = pF) is distinct from c_free
      then v_bad := v_bad || ' 🔴 ⓒ force_return_tx의 사유가 덮였다'; end if;
    -- the operator's audit trail survives — a repair that deleted the memo everywhere would pass
    -- both arms above and destroy the only record there is
    if (select r.memo from return_resolutions r where r.booking_id = pA) is distinct from c_memo
      then v_bad := v_bad || ' 🔴 스크럽이 저널의 ⓐ 메모를 지웠다'; end if;
    if (select r.memo from return_resolutions r where r.booking_id = pI) is distinct from c_memo2
      then v_bad := v_bad || ' 🔴 스크럽이 저널의 ⓑ 메모를 지웠다'; end if;

    -- IDEMPOTENT: the second call is a no-op, which is also the global arm — nothing else in this
    -- database is still carrying a 0193-written copy.
    select _scrub_ops_return_reasons() into v_n;
    if v_n is distinct from 0 then v_bad := v_bad || ' 두 번째 호출이 행 수=' || coalesce(v_n::text,'(null)') || ' (0이어야)'; end if;
    if (select b.return_force_reason from bookings b where b.id = pA) is distinct from c_tok_s
      then v_bad := v_bad || ' 두 번째 호출이 ⓐ를 바꿨다'; end if;

    if v_bad = ''
      then call _pass('sml','0201-M2 0193이 이미 쓴 사본만 스크럽된다 — 실제 해결 뒤 손으로 되심은 옛 데이터 모양 두 개(active·incident_review)가 각자의 토큰으로 바뀌고, 저널 조인 밖에 있는 force_return_tx의 사유는 그대로 남으며(덮어쓰기가 아니라 대상 식별이라는 증거), 저널의 운영 메모는 두 건 모두 살아 있다; 두 번째 호출은 0행이다(멱등 — 그리고 이 데이터베이스에 남은 사본이 더 없다는 전역 팔)');
    else v_msg := v_bad; call _fail('sml','0201-M2 스크럽', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('sml','0201-M2 스크럽', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0201-L1] TWO LATE STAMPS DO NOT HIDE AN UNSETTLEABLE RETURN
  -- 🔴 The fixture sits where the OLD and NEW predicates DISAGREE — an unsealed `incident_review`
  --    row with BOTH stamps — because a behavioural pin can only see a predicate change when its
  --    fixture leaves the agreement zone (the fixture-agreement law).
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- CONTROL ①: the shipped flag really is NULL (③)
    if (select f.return_strand_minutes from ops_flags f where f.id) is not null
      then v_bad := v_bad || ' 출하 플래그가 NULL이 아니다'; end if;

    bL := t_sml_live(oz, dz, rt, rz);
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform end_run_tx(bL, 3.5, 1300, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_sml_age(bL, interval '5 hours');
    perform sweep_run_end_recovery();                 -- 0188 ⓑ-① escalates it
    if (select b.status::text from bookings b where b.id = bL) <> 'incident_review'
      then v_bad := v_bad || ' 픽스처가 승격되지 않았다'; end if;

    -- …and NOW both parties confirm, LATE. 0096 lets the stamps land and refuses to seal — which
    -- is the state the finding is about, so it is asserted rather than assumed.
    perform set_config('request.jwt.claim.sub', rz::text, false);
    perform confirm_return_tx(bL, 'runner');
    perform set_config('request.jwt.claim.sub', oz::text, false);
    v_js := confirm_return_tx(bL, 'owner');
    perform set_config('request.jwt.claim.sub', '', false);
    if not coalesce((v_js->>'both_confirmed')::boolean, false)
      then v_bad := v_bad || ' 늦은 양측 스탬프가 기록되지 않았다'; end if;
    if (select b.settlement_ready_at from bookings b where b.id = bL) is not null
      then v_bad := v_bad || ' incident_review에서 봉인이 찍혔다 (0096 위반 — 전제가 거짓)'; end if;
    if exists (select 1 from ledger_items li where li.booking_id = bL)
      then v_bad := v_bad || ' 늦은 양측 스탬프가 정산했다 (전제가 거짓)'; end if;
    if (select r.settled_at from runs r where r.booking_id = bL) is not null
      then v_bad := v_bad || ' 늦은 양측 스탬프가 돈을 움직였다 (전제가 거짓)'; end if;
    -- 🔴 WHAT THIS COSTS, MEASURED RATHER THAN ASSUMED, AND IT CORRECTED THIS PIN'S OWN PREMISE.
    --    The draft asserted the runner was work-gated here, by analogy with 224 `0193-R1`/`R2`.
    --    The harness answered NOT GATED: `_runner_work_gate_blocking` (0092) reads the RETURN
    --    STAMPS, and both of them are now present — late, but present. So in exactly this shape the
    --    runner is free to take work and the ONLY thing stuck is the money: no seal, no
    --    `runs.settled_at`, no ledger row, and — before 0201 — nobody told. That is the honest and
    --    slightly worse version of codex's sentence: the case is invisible from BOTH directions,
    --    because the one symptom a human would have noticed (a runner complaining they are blocked)
    --    is absent too.
    if coalesce((runner_work_gate(rz)->>'gated')::boolean, true)
      then v_bad := v_bad || ' 전제가 바뀌었다: 양측 스탬프가 있는데 러너가 아직 게이트에 걸려 있다 (0092가 스탬프 말고 다른 것을 본다)'; end if;

    -- CONTROL ②: with the flag NULL the arm is STILL inert on this very row. The fix widened WHICH
    -- rows the arm considers and must not have widened WHETHER it runs.
    perform sweep_run_end_recovery();
    if t_sml_bells(bL) <> 0 then v_bad := v_bad || ' NULL 플래그인데 좌초 벨이 울렸다=' || t_sml_bells(bL); end if;

    -- ⑤ the SEALED control, built before the flag is armed. An `incident_review` row that IS sealed
    --   is arm ⓐ's subject (a pricing re-drive, 0083 §0f) and must stay out of this bell — it is
    --   the one fixture that isolates the seal exclusion from the stamp predicate.
    bSeal := t_sml_live(oo, dg, rt, rr);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform end_run_tx(bSeal, 3.0, 1100, 'completed', null, null);
    perform set_config('request.jwt.claim.sub', '', false);
    perform t_sml_age(bSeal, interval '5 hours');
    perform sweep_run_end_recovery();
    if (select b.status::text from bookings b where b.id = bSeal) <> 'incident_review'
      then v_bad := v_bad || ' 봉인 대조 픽스처가 승격되지 않았다'; end if;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform confirm_return_tx(bSeal, 'runner');
    perform set_config('request.jwt.claim.sub', oo::text, false);
    perform confirm_return_tx(bSeal, 'owner');
    perform set_config('request.jwt.claim.sub', '', false);
    update bookings set settlement_ready_at = now() - interval '1 hour' where id = bSeal;
    if (select b.settlement_ready_at from bookings b where b.id = bSeal) is null
      then v_bad := v_bad || ' 봉인 대조: 손으로 찍은 봉인이 남지 않았다'; end if;

    -- ARM IT. 60 minutes; both rows are five hours old.
    update ops_flags set return_strand_minutes = 60, updated_at = now() where id;
    perform sweep_run_end_recovery();
    select count(*) into v_n from notifications
     where ref_id = bL and title = c_bell and profile_id = ops and kind = 'system';
    if v_n <> 1 then v_bad := v_bad || ' 🔴 늦게 양측이 찍은 incident_review 행의 ops 통지=' || v_n || ' (1이어야 — codex #2)'; end if;
    if t_sml_bells(bL, ops) <> 1 then v_bad := v_bad || ' 이 스위트의 운영자에게 간 벨=' || t_sml_bells(bL, ops); end if;
    -- the INACTIVE roster row got nothing — an unsubscription is honoured by the writer too, not
    -- only by `ops_is_member` (G1's arm is about the read; this one is about the bell)
    if t_sml_bells(bL, opx) <> 0 then v_bad := v_bad || ' 🔴 비활성 명부 행에도 벨이 갔다=' || t_sml_bells(bL, opx); end if;
    v_n := t_sml_bells(bL);   -- every recipient on the shared roster; 224 has its own operator here
    -- the body carries NO booking id (0084 §E), the same rule 0193 wrote it under
    if exists (select 1 from notifications
               where ref_id = bL and title = c_bell and body like '%' || bL::text || '%')
      then v_bad := v_bad || ' ops 본문에 예약 id가 들어 있다'; end if;
    -- THE SEALED ROW IS STILL EXCLUDED
    if t_sml_bells(bSeal) <> 0
      then v_bad := v_bad || ' 🔴 봉인된 incident_review 행이 좌초로 보고됐다=' || t_sml_bells(bSeal); end if;

    -- EXACTLY ONCE ACROSS TWO TICKS — as a DELTA on the count this tick could change, not as an
    -- absolute over a title other suites' fixtures also write
    perform sweep_run_end_recovery();
    if t_sml_bells(bL) <> v_n then v_bad := v_bad || ' 두 번째 틱이 중복 통지했다 (' || v_n || ' → ' || t_sml_bells(bL) || ')'; end if;
    if t_sml_bells(bL, ops) <> 1 then v_bad := v_bad || ' 두 번째 틱이 같은 운영자에게 또 보냈다=' || t_sml_bells(bL, ops); end if;

    -- …and the door the bell points at actually ends it
    v_js := ops_resolve_return_tx(bL, t_sml_quote(3.5), '양측 뒤늦게 확인 — 정산 진행', ops);
    if not coalesce((v_js->>'settled')::boolean, false)
      then v_bad := v_bad || ' 보고된 행이 ops 문으로 정산되지 않았다'; end if;
    if (select b.status::text from bookings b where b.id = bL) <> 'completed'
      then v_bad := v_bad || ' 해결 뒤 completed가 아니다'; end if;
    select count(*) into v_n from ledger_items li where li.booking_id = bL;
    if v_n <> 1 then v_bad := v_bad || ' 원장 행 수=' || v_n; end if;
    if (select r.settled_at from runs r where r.booking_id = bL) is null
      then v_bad := v_bad || ' runs.settled_at이 없다 (돈이 움직인 시각)'; end if;

    -- ③ put the flag back to what production ships with
    update ops_flags set return_strand_minutes = null, updated_at = now() where id;
    if (select f.return_strand_minutes from ops_flags f where f.id) is not null
      then v_bad := v_bad || ' 플래그를 되돌리지 못했다 (뒤 스위트가 다른 세상을 본다)'; end if;

    if v_bad = ''
      then call _pass('sml','0201-L1 늦은 양측 확인이 좌초를 숨기지 않는다 — 0스탬프 타임아웃으로 incident_review가 된 행에 양측이 **뒤늦게** 찍으면 0096은 스탬프만 받고 봉인하지 않으므로 그 행은 혼자서는 절대 정산되지 않는다. ⚠ 측정이 이 핀의 전제를 고쳤다: 그때 러너는 **묶여 있지 않다**(0092는 반환 스탬프를 보고, 늦게라도 둘 다 있다) — 즉 막힌 건 오직 돈이고 사람이 알아챌 증상조차 없다. 이제 마감을 넘기면 이 스위트의 운영자에게 정확히 1건이 가고(비활성 명부 행에는 0건, 본문에 예약 id 없음) 두 번째 틱은 아무것도 더하지 않으며(전역 총수 델타 0 — 공유 명부라 절대수는 다른 스위트를 잰다) ops 문이 그 행을 completed·settled_at·원장 1행으로 끝낸다. 대조 둘: 플래그가 NULL이면 같은 행에 아무것도 가지 않고(끄기 스위치는 그대로), **봉인된** incident_review 행은 같은 마감을 넘겨도 보고되지 않는다(봉인 제외 조건은 확장에 먹히지 않았다 — 그건 0083 §0f의 가격 재구동 몫)');
    else v_msg := v_bad; call _fail('sml','0201-L1 늦은 양측 확인과 좌초 벨', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', false);
    update ops_flags set return_strand_minutes = null where id;
    v_msg := sqlerrm; call _fail('sml','0201-L1 늦은 양측 확인과 좌초 벨', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0201-G1] THE MEMBERSHIP READ THE EDGE CALLS BEFORE IT READS ANYTHING ELSE
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- the roster, in both directions
    if ops_is_member('return_strand', ops) is not true
      then v_bad := v_bad || ' 명부에 있는 운영자가 false'; end if;
    if ops_is_member('return_strand', sx) is not false
      then v_bad := v_bad || ' 🔴 명부에 없는 사람이 true'; end if;
    -- `p_kind` is an ARGUMENT: payout_due membership must not open return_strand's door, and the
    -- same person answering TRUE for their own class is what makes the first arm about the class
    -- rather than about the person.
    if ops_is_member('return_strand', opd) is not false
      then v_bad := v_bad || ' 🔴 payout_due 소속이 return_strand를 열었다'; end if;
    if ops_is_member('payout_due', opd) is not true
      then v_bad := v_bad || ' 대조: payout_due 소속이 자기 클래스에서도 false'; end if;
    -- `active = false` is an unsubscription, not a row to ignore (0084 §E)
    if ops_is_member('return_strand', opx) is not false
      then v_bad := v_bad || ' 🔴 비활성 명부 행이 통과했다'; end if;

    -- the arguments, refused BY NAME so the edge needs no second vocabulary
    begin
      perform ops_is_member('return_strand', null);
      v_bad := v_bad || ' actor 없이 통과했다';
    exception when others then
      if sqlerrm <> 'ops_actor_required' then v_bad := v_bad || ' actor 부재 거절 이름=' || sqlerrm; end if;
    end;
    begin
      perform ops_is_member('  ', ops);
      v_bad := v_bad || ' 빈 클래스로 통과했다';
    exception when others then
      if sqlerrm <> 'ops_kind_required' then v_bad := v_bad || ' 빈 클래스 거절 이름=' || sqlerrm; end if;
    end;

    -- ① A CALLER WITH AN IDENTITY OF ITS OWN IS NOT A SERVER. Driven by setting the claim, because
    --    that is the only way to reach the gate: `authenticated` cannot execute the function at all
    --    (asserted separately below), which is the stronger protection and the one that hides this
    --    branch from a role-based probe.
    perform set_config('request.jwt.claim.sub', ops::text, false);
    begin
      perform ops_is_member('return_strand', ops);
      v_bad := v_bad || ' 🔴 자기 신원을 가진 호출자가 명부를 물었다';
    exception when others then
      if sqlerrm <> 'not_party' then v_bad := v_bad || ' 신원 있는 호출자 거절 이름=' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    -- CONTROL: the SAME pair answers true once the identity is gone, so the refusal is about WHO
    -- asked and not about the pair.
    if ops_is_member('return_strand', ops) is not true
      then v_bad := v_bad || ' 대조: 신원을 지운 뒤에도 같은 쌍이 true가 아니다'; end if;

    -- ② the ACL, which is what makes it unreachable from a phone at all
    if has_function_privilege('authenticated', 'public.ops_is_member(text,uuid)', 'execute')
      then v_bad := v_bad || ' 🔴 authenticated가 명부 조회를 실행할 수 있다 (임의 쌍 오라클)'; end if;
    if has_function_privilege('anon', 'public.ops_is_member(text,uuid)', 'execute')
      then v_bad := v_bad || ' 🔴 anon이 명부 조회를 실행할 수 있다'; end if;
    if not has_function_privilege('service_role', 'public.ops_is_member(text,uuid)', 'execute')
      then v_bad := v_bad || ' service_role이 명부 조회를 실행할 수 없다 (엣지의 사전 거절이 죽는다)'; end if;
    -- and measured rather than inferred from the grant: an `authenticated` session is refused
    begin
      set local role authenticated;
      perform ops_is_member('return_strand', ops);
      reset role;
      v_bad := v_bad || ' 🔴 authenticated 롤로 명부 조회가 실행됐다';
    exception when others then
      reset role;
      if sqlstate <> '42501' then v_bad := v_bad || ' authenticated 롤 거절 코드=' || sqlstate || ' ' || sqlerrm; end if;
    end;

    if v_bad = ''
      then call _pass('sml','0201-G1 명부 조회는 명부에 대해서만 답한다 — 활성 return_strand 수신자는 true, 남은 false, **payout_due 전용 수신자는 return_strand에서 false이고 자기 클래스에서는 true**(클래스가 진짜 인자라는 양방향), active=false 행은 false; actor 부재·빈 클래스는 이름으로 거절되고 자기 신원을 가진 호출자는 not_party(대조: 신원을 지우면 같은 쌍이 true); ACL은 양방향 — authenticated·anon은 실행 자체가 불가(권한으로도, 실제 실행으로도 42501)하고 service_role만 가능하다');
    else v_msg := v_bad; call _fail('sml','0201-G1 명부 조회', v_msg); end if;
  exception when others then reset role; perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('sml','0201-G1 명부 조회', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [0201-S1] THE DEPLOYED SHAPE — four objects, and the source arms distinguish both worlds
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- ── the resolver ──────────────────────────────────────────────────────────────────────
    select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'ops_resolve_return_tx';
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(ops_resolve_return_tx)';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 해결 RPC가 definer가 아니다'; end if;
      if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 해결 RPC 본문 search_path 없음'; end if;
      select prosrc into v_raw from pg_proc where oid = v_oid;
      if v_raw is null or btrim(v_raw) = '' then v_bad := v_bad || ' NO-SOURCE(ops_resolve_return_tx)';
      else
        -- comments STRIPPED: this file and 0201 both explain the memo rule at length, and an
        -- un-stripped match is satisfied by the prose rather than by the code.
        v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
        if (v_src ~ 'return_force_reason\s*=\s*v_reason') is not true
          then v_bad := v_bad || ' 해결 RPC: 고정 토큰 배정이 없다'; end if;
        if (v_src ~ 'return_force_reason\s*=\s*(v_memo|p_memo)') is not false
          then v_bad := v_bad || ' 🔴 해결 RPC: 운영 메모가 당사자 칸에 배정된다'; end if;
        -- the memo must still REACH the journal — a fix that deleted it everywhere passes the
        -- two arms above and destroys the audit trail
        if (v_src ~ 'insert into return_resolutions') is not true
          then v_bad := v_bad || ' 해결 RPC: 저널 기록이 없다'; end if;
        if (v_src ~ '\mv_memo\M') is not true
          then v_bad := v_bad || ' 해결 RPC: 메모가 본문에서 사라졌다'; end if;
        -- 0193's ordering invariant, re-asserted because 0201 re-declared the function
        if not (position('ops_recipients_for(c_ops_class)' in v_src) > 0
                and position('ops_recipients_for(c_ops_class)' in v_src) < position('for update' in v_src))
          then v_bad := v_bad || ' 해결 RPC: ops 게이트가 잠금보다 뒤에 있다'; end if;
        -- CRUDE CONTROL: the raw source DOES carry the words these arms look for, so a stripper
        -- that blanked the whole body would not read as a clean pass.
        if (v_raw ~ 'return_force_reason') is not true
          then v_bad := v_bad || ' 대조: 원본 소스에 return_force_reason이라는 낱말이 없다 (주석 제거 팔이 무의미)'; end if;
      end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 해결 RPC가 authenticated에 열려 있다'; end if;
      if has_function_privilege('service_role', v_oid, 'execute') is not true
        then v_bad := v_bad || ' 해결 RPC를 service_role이 실행할 수 없다'; end if;
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
        if (v_src ~ 'return_forced_by = ''ops''') is not true
          then v_bad := v_bad || ' 스크럽: ops 마커 조건이 없다'; end if;
      end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 스크럽이 authenticated에 열려 있다'; end if;
    end if;

    -- ── the membership read ───────────────────────────────────────────────────────────────
    select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'ops_is_member';
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(ops_is_member)';
    else
      if (select prosecdef from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 명부 조회가 definer가 아니다'; end if;
      if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
        then v_bad := v_bad || ' 명부 조회 본문 search_path 없음'; end if;
      select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
      if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(ops_is_member)';
      else
        if (v_src ~ 'v_uid is not null or current_user not in \(''service_role'', ''postgres''\)') is not true
          then v_bad := v_bad || ' 명부 조회: 서버 전용 호출자 게이트가 없다'; end if;
        if (v_src ~ 'ops_recipients_for\(p_kind\)') is not true
          then v_bad := v_bad || ' 명부 조회: 0084의 창구를 쓰지 않는다 (두 번째 소속 구현)'; end if;
      end if;
    end if;

    -- ── the sweep ─────────────────────────────────────────────────────────────────────────
    select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'sweep_run_end_recovery';
    if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(sweep_run_end_recovery)';
    else
      select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
      if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(sweep_run_end_recovery)';
      else
        -- BOTH halves of 0201 §D, each matched in a form the OTHER world cannot satisfy: the old
        -- candidate conjunct began `and not (`, the new disjunct begins `or not (`. A match on
        -- `not (b.runner_confirmed_return_at` alone is present in both and is uninformative.
        if (v_src ~ 'and \(b\.status = ''incident_review''') is not true
          then v_bad := v_bad || ' 스윕 ⓕ: 후보 쿼리에 incident_review 분기가 없다'; end if;
        if (v_src ~ 'and not \(b\.runner_confirmed_return_at is not null and b\.owner_confirmed_return_at is not null\)') is not false
          then v_bad := v_bad || ' 🔴 스윕 ⓕ: 후보 쿼리에 옛 「스탬프 2개면 제외」가 남아 있다'; end if;
        if (v_src ~ 'if \(v_b\.status is distinct from ''incident_review''\)') is not true
          then v_bad := v_bad || ' 스윕 ⓕ: 잠긴 행 재확인이 후보 쿼리와 다르다'; end if;
        if (v_src ~ 'if v_b\.runner_confirmed_return_at is not null\s+and v_b\.owner_confirmed_return_at is not null then continue') is not false
          then v_bad := v_bad || ' 🔴 스윕 ⓕ: 잠긴 행 재확인에 옛 조건이 남아 있다'; end if;
        -- the widening must not have eaten the seal exclusion (L1's behavioural control's source half)
        if (v_src ~ 'and b\.settlement_ready_at is null') is not true
          then v_bad := v_bad || ' 스윕 ⓕ: 봉인 제외 조건이 사라졌다'; end if;
        -- 0193/0188/0183/0181's arms survived the re-declaration
        if (select count(*) from regexp_matches(v_src, 'for update skip locked', 'g')) <> 5
          then v_bad := v_bad || ' 스윕: 행 락 수가 5가 아니다(ⓑ·ⓒ·ⓓ·ⓔ·ⓕ)'; end if;
        if (select count(*) from regexp_matches(v_src, '''safety''::noti_kind, ''귀가 확인이 필요해요''', 'g')) <> 2
          then v_bad := v_bad || ' 스윕: 귀가 승격이 safety 2건이 아니다'; end if;
        if (v_src ~ 'pg_try_advisory_xact_lock') is not true then v_bad := v_bad || ' 스윕: 잡 락 유실'; end if;
        if (v_src ~ 'handoff_ops_alerted_at') is not true then v_bad := v_bad || ' 스윕: ⓔ 팔 유실'; end if;
      end if;
      if has_function_privilege('authenticated', v_oid, 'execute') is not false
        then v_bad := v_bad || ' 스윕이 authenticated에 열려 있다'; end if;
    end if;

    -- ── the journal is still SEALED — 0201 re-declared its only writer and must not have opened it
    if (select relrowsecurity from pg_class where oid = 'return_resolutions'::regclass) is not true
      then v_bad := v_bad || ' return_resolutions에 RLS가 없다'; end if;
    if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'return_resolutions')
      then v_bad := v_bad || ' return_resolutions에 정책이 있다'; end if;
    if has_table_privilege('authenticated', 'public.return_resolutions', 'select') is not false
      then v_bad := v_bad || ' authenticated가 저널을 직접 읽는다'; end if;

    if v_bad = ''
      then call _pass('sml','0201-S1 배포 형상 네 객체 — 해결 RPC·스크럽·명부 조회는 definer에 본문 search_path를 갖고 ACL이 양방향으로 맞으며, 주석 벗긴 소스에서 판정 사유 칸은 v_reason을 받고 v_memo/p_memo는 **절대** 받지 않으면서 메모는 여전히 저널로 가고(모두 지운 수정은 통과하지 못한다) ops 게이트는 잠금보다 앞이다(원본에 낱말이 있다는 크루드 대조 포함); 스윕 ⓕ는 후보 쿼리와 잠긴 행 재확인 **양쪽**에 새 분기를 갖고 옛 조건은 양쪽 모두에서 사라졌으며(두 세계를 구분하는 형태로 매칭) 봉인 제외·행 락 5개·safety 2건·잡 락·ⓔ 팔은 그대로다; 저널은 여전히 봉인이다. NO-FUNCTION·NO-SOURCE는 큰 소리로 실패');
    else v_msg := v_bad; call _fail('sml','0201-S1 배포 형상', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('sml','0201-S1 배포 형상', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
