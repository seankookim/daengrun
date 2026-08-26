-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 163 — 0129, the club return-address arm CORRECTED. Fifteen pins, each stating its own scope.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Contract: `docs/contracts/club-return-address-arm-contract.md` — CONTRACT v2 plus the two
-- corrections after the horizontal rules. Sean: 「go ahead with the address fix」, then 「fix it and
-- re-review」.
--
-- ── WHAT 0129 CHANGED, IN ONE SENTENCE ──────────────────────────────────────────────────────
-- `booking_pickup_address`'s club disjunct went from three conjuncts to six: the pairing must
-- belong to this booking's club session, be `runner_delegated`, have `return_mode = 'owner_home'`,
-- not be `resolved`, have no `owner_confirmed_return_at`, and the caller must BE its
-- `custodian_profile_id`. `session_dogs` gained `pickup_mode`/`return_mode` in the same migration
-- so no window exists where addresses are written against the broad arm.
--
-- ═══ 🔴 THE GOVERNING RULE OF THIS REBUILD, AND WHY 162 NEEDED ONE ═══════════════════════════
-- **A fixture must be REACHABLE BY THE LIFECYCLE, not merely constructible by an INSERT.**
-- 162's repair fixtures manufactured a runner who was already `responsible_profile_id` and
-- custodian on a `confirmed` booking. The real path cannot produce that row: delegation makes the
-- OWNER responsible (`0048:135`), acceptance changes `bookings.runner_id` without touching custody
-- (`0047:175`), and the runner first becomes custodian at `picked_up` (`0045:44`). So 162's M1 and
-- M4b repairs detected their tailored mutations **without establishing the property on any real
-- path** — the blind spot did not close, it MOVED.
--
-- Therefore every pairing in this file is built by `t163_pair()`, which drives the actual RPC
-- chain end to end:
--   `club_request_district` → `club_claim_host` → `club_create_session` → `session_runner_commit`
--   → `session_checkin` (host and runner) → `session_delegate_dog` → `session_approve_dog`
--   → `session_pay_delegation` → `session_assign_dog` → `session_proposal_respond`
--   → handoff stamps + `picked_up` → `club_start_delegated_runs` → `settle_run_tx('completed')`
-- and the pins that need a further state use the real RPC for it too: `session_transfer_initiate`,
-- `session_transfer_accept`, `session_confirm_return`, `club_incident_open`,
-- `session_host_force_resolve`.
--
-- ⚠ **THE THREE WRITES THAT ARE NOT AN RPC CALL, AND WHY EACH IS THE PRODUCTION PATH:**
--   1. **the handoff stamps + `status = 'picked_up'`** — there is no SQL RPC for the door
--      handoff; the client calls the `transition-booking` edge function, which runs as
--      `service_role`. `_guard_booking_cols` (`0058:143`) blocks `authenticated`/`anon` and lets
--      every server role through, so an UPDATE from this postgres session IS that path rather
--      than a bypass — and `enforce_booking_transition` (`0066:40`) still validates
--      `confirmed → picked_up`, so the state machine is enforced, not stepped around. This is
--      also how 107 builds its custody fixtures.
--   2. **`bookings.address_id`** — written at club sign-up. That slice has not landed (club
--      bookings still mint with `address_id` NULL, `0081:184-186`); this is an INPUT the product
--      will supply, not a lifecycle STATE the machine produces.
--   3. **`session_dogs.return_mode` / `.pickup_mode`** — same: the owner's own choice at sign-up,
--      written by an RPC that does not exist yet. `session_dogs` has a SELECT-only client policy
--      (`0030:136`), so these are server-authored columns and the harness's postgres session is
--      the server.
--   The distinction that makes these three legitimate and 162's `b_early` not: **an input the
--   product will supply is not the same as a machine state the product cannot reach.** Every
--   CUSTODY state below is reached by the machine.
--
-- ── EVERY FIXTURE MINTS A `dog_custody_events` ROW, WHERE PRODUCTION WOULD ──────────────────
-- 162's fixtures were INSERTed, so `_club_compute_axes` (`0048:786-800`) always fell through to
-- the LEGACY `responsible_profile_id` branch and the event branch that `picked_up` produces
-- (`0045:44-53`) was never once exercised. Behaviour is identical today; the gap was that no pin
-- had ever run the path production actually takes. P0 asserts the outbound event exists on every
-- pairing, so the branch is not merely present but taken.
--
-- ── EVERY PIN ASSERTS ITS OWN PRECONDITION ──────────────────────────────────────────────────
-- A gate suite fails in a characteristic way: 「it raised not_runner」 scores green when the
-- fixture was never in the state the pin claims to be about. `t163_state()` makes the precondition
-- one line, and every refusal pin states the state it is refusing FROM.
--
-- ── THE THREE PROPOSITIONS, KEPT SEPARATE (CLAUDE.md §Migrations) ────────────────────────────
-- 「the hole is real」, 「a pin notices something」 and 「the fix closes it」 are three claims. P1 ⓒ is
-- the first: 0128's arm is transcribed as `t163_arm0128` and shown to ADMIT the leak fixture that
-- 0129 refuses. P13 ⓐ is the standing guard that the transcriptions have not drifted from the
-- gates they copy. The battery at the bottom is the measurement.
--
-- ── ⚠ 162 P4 ⓔ AND P6 GO RED UNDER 0129, AND THAT IS THE FINDING, NOT A REGRESSION ──────────
-- Both pin the behaviour of `b_early` — 162's manufactured runner-custodian on a `confirmed`
-- booking, the exact row the blind review named as unreachable. Under 0129 that row is admitted
-- (custodian is the runner, phase is not `resolved`, mode is home), and on the REAL path the same
-- point in the lifecycle is refused because the custodian is still the OWNER. **P12 below
-- establishes that property on a reachable fixture**, which is what 162 P4 ⓔ was reaching for.
-- 162 is not touched by this slice; the disposition of its two stale pins is reported upward with
-- CLAUDE.md's rule quoted (*a suite whose pinned behaviour legitimately changes MUST be updated in
-- the same slice*).
--
-- ── MUTATION BATTERY — PREDICTED, THEN MEASURED. See the commit message for the table. ───────
-- Each mutation is applied ALONE, by appending a mutated `create or replace` to the END of a COPY
-- of 0129 in a scratch tree OUTSIDE the worktree — never by editing the live file, because another
-- agent may share this tree and a copy-modify-restore is a read-modify-write with a multi-second
-- window.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
set client_min_messages = warning;

-- ── the PRE-CLUB gate, transcribed from 0065:44-67 ──────────────────────────────────────────
-- `security invoker` on purpose and it is not a weakening: this suite calls every function from
-- the postgres session with `request.jwt.claim.sub` set, and the gate reads `auth.uid()` — not
-- `current_user` — so definer-ness cannot change one outcome here. Making it a definer WOULD add
-- an unsealed SECURITY DEFINER to the schema, green only because 98 H9 and 99 S1 run earlier in
-- the harness; a pin that is green because of file ordering is the failure this repo names most.
create or replace function t163_pre0065(p_booking uuid)
returns table (label text, addr text, detail text, lat numeric, lng numeric)
language plpgsql stable security invoker set search_path = public, pg_temp as $$
begin
  if not coalesce((
        select b.runner_id = auth.uid()
           and (b.status in ('runner_enroute', 'picked_up', 'active')
                or (b.status = 'confirmed' and b.scheduled_at < now() + interval '24 hours'))
        from bookings b where b.id = p_booking), false)
  then
    raise exception 'not_runner';
  end if;
  return query
    select a.label, a.addr, a.detail, a.lat, a.lng
    from bookings b join addresses a on a.id = b.address_id
    where b.id = p_booking and a.owner_id = b.owner_id;
end $$;
revoke execute on function t163_pre0065(uuid) from public, anon, authenticated;

-- ── 0128's SHIPPED arm, transcribed from 0128:104-131 ───────────────────────────────────────
-- This exists for exactly one proposition: **the Critical is a real hole, not a pin's opinion.**
-- P1 ⓒ shows this body HANDS OVER the owner's home on a home-pickup / on-site-return pairing that
-- 0129 refuses. Without it, P1 ⓑ would only prove that the shipped function refuses something.
create or replace function t163_arm0128(p_booking uuid)
returns table (label text, addr text, detail text, lat numeric, lng numeric)
language plpgsql stable security invoker set search_path = public, pg_temp as $$
begin
  if not coalesce((
        select (b.runner_id = auth.uid()
                and (b.status in ('runner_enroute', 'picked_up', 'active')
                     or (b.status = 'confirmed' and b.scheduled_at < now() + interval '24 hours')))
            or exists (
                 select 1 from session_dogs sd
                 where sd.booking_id = b.id
                   and sd.custody = 'runner_delegated'
                   and sd.custody_phase = 'return_pending'
                   and sd.custodian_profile_id = auth.uid())
        from bookings b where b.id = p_booking), false)
  then
    raise exception 'not_runner';
  end if;
  return query
    select a.label, a.addr, a.detail, a.lat, a.lng
    from bookings b join addresses a on a.id = b.address_id
    where b.id = p_booking and a.owner_id = b.owner_id;
end $$;
revoke execute on function t163_arm0128(uuid) from public, anon, authenticated;

-- One line of state for a pairing, so a precondition assertion is one line and not six.
create or replace function t163_state(p_booking uuid) returns text
language sql stable as $$
  select coalesce((select sd.custody || '/' || sd.custody_phase || '/' ||
                          coalesce(sd.custodian_profile_id::text, '∅') || '/' || sd.return_mode ||
                          '/owner_confirmed=' ||
                          case when sd.owner_confirmed_return_at is null then 'no' else 'yes' end
                     from session_dogs sd where sd.booking_id = p_booking), '<no session_dogs row>')
$$;

-- Did this call raise, and with what? '' never happens — success returns the row count. P7
-- compares five of these TO EACH OTHER rather than to a literal: five paths that all regressed to
-- the same NEW string would still be indistinguishable, and INDISTINGUISHABILITY is the property,
-- not the spelling.
create or replace function t163_probe(p_booking uuid) returns text
language plpgsql stable as $$
declare v_n int;
begin
  select count(*) into v_n from booking_pickup_address(p_booking);
  return 'ok:rows=' || v_n;
exception when others then
  return sqlstate || '|' || sqlerrm;
end $$;

-- ── THE FIXTURE FACTORY — one complete pairing, driven through the real RPC chain ───────────
-- Each call builds its own club, session, host, runner, owner, dog and route, so no two fixtures
-- can interact through a shared runner capacity (`_club_runner_load` counts `completed` pairings
-- forever, `0047:57`, and a certified runner's cap is 1 — `0037:39`). p_stop = 'confirmed' stops
-- after acceptance, before the handoff; 'return_pending' drives all the way through settlement.
create or replace function t163_pair(
  p_tag text, p_return_mode text default 'owner_home',
  p_address boolean default true, p_stop text default 'return_pending'
) returns jsonb
language plpgsql as $$
declare
  v_host uuid; v_runner uuid; v_owner uuid; v_dog uuid; v_route uuid;
  v_club uuid; v_sess uuid; v_sd uuid; v_bk uuid; v_addr uuid; v_km numeric;
begin
  v_host   := t_user('t163h_' || p_tag, 'runner');
  v_runner := t_user('t163r_' || p_tag, 'runner');
  update runners set tier = 'veteran' where profile_id = v_runner;
  v_owner  := t_user('t163o_' || p_tag, 'owner');
  v_dog    := t_dog(v_owner, '반환견' || p_tag);
  v_route  := t_route('t163 코스 ' || p_tag);
  select km into v_km from routes where id = v_route;

  -- gate_code_enc is filled ON PURPOSE — so a leak pin measures 「structurally absent」 and never
  -- 「the column happened to be empty」 (100 W6's rule, transcribed).
  if p_address then
    insert into addresses (owner_id, label, addr, detail, gate_code_enc, lat, lng)
    values (v_owner, '우리 집', '서울 서초구 신반포로 270', '203동 1502호', 'ENC::절대노출금지',
            37.508123, 126.995456)
    returning id into v_addr;
  end if;

  perform set_config('request.jwt.claim.sub', v_host::text, false);
  v_club := club_request_district('t163' || p_tag);
  perform club_claim_host(v_club);
  v_sess := club_create_session(v_club, now() + interval '90 minutes', 't163 집결지', v_route, 8, 'mixed');
  perform session_runner_commit(v_sess);
  perform session_checkin(v_sess);
  perform set_config('request.jwt.claim.sub', v_runner::text, false);
  perform session_runner_commit(v_sess);
  perform session_checkin(v_sess);

  perform set_config('request.jwt.claim.sub', v_owner::text, false);
  v_sd := session_delegate_dog(v_sess, v_dog, t_consent());
  -- the owner's own sign-up choice (see the header: an INPUT the product will supply, not a
  -- machine state). Written here, before anything else, so the whole rest of the lifecycle runs
  -- over it — which is what lets P10 assert the axes normalizer never clobbers it.
  update session_dogs set pickup_mode = 'owner_home', return_mode = p_return_mode where id = v_sd;

  perform set_config('request.jwt.claim.sub', v_host::text, false);
  perform session_approve_dog(v_sd, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, false);
  v_bk := session_pay_delegation(v_sd, 't163-idem-' || p_tag, true);
  if v_addr is not null then
    update bookings set address_id = v_addr where id = v_bk;
  end if;

  perform set_config('request.jwt.claim.sub', v_host::text, false);
  perform session_assign_dog(v_sd, v_runner);
  perform set_config('request.jwt.claim.sub', v_runner::text, false);
  perform session_proposal_respond(v_sd, true);

  if p_stop = 'confirmed' then
    perform set_config('request.jwt.claim.sub', '', false);
    return jsonb_build_object('host', v_host, 'runner', v_runner, 'owner', v_owner, 'dog', v_dog,
      'session', v_sess, 'session_dog', v_sd, 'booking', v_bk, 'address', v_addr, 'route', v_route);
  end if;

  -- the door handoff — the service_role transition path (see the header's note 1). This is the
  -- write that mints the `outbound` dog_custody_events row and moves custody to the runner.
  update bookings set owner_confirmed_handoff_at = now(), runner_confirmed_handoff_at = now()
   where id = v_bk;
  update bookings set status = 'picked_up' where id = v_bk;

  perform set_config('request.jwt.claim.sub', v_runner::text, false);
  perform club_start_delegated_runs(v_sess);
  perform t_settle(v_bk, 'completed', v_km, 1800);   -- ⇒ custody_phase = return_pending (0045:55)

  perform set_config('request.jwt.claim.sub', '', false);
  return jsonb_build_object('host', v_host, 'runner', v_runner, 'owner', v_owner, 'dog', v_dog,
    'session', v_sess, 'session_dog', v_sd, 'booking', v_bk, 'address', v_addr, 'route', v_route);
end $$;

do $$
declare
  f_home jsonb; f_site jsonb; f_xfer jsonb; f_ext jsonb; f_inc jsonb; f_f1 jsonb;
  f_seal jsonb; f_open jsonb; f_null jsonb; f_pre jsonb; f_cross jsonb; f_mkt jsonb;
  v_bad text; v_n int; v_n2 int; v_st text; v_cx uuid; v_j jsonb; v_dog2 uuid; f_md jsonb;
  v_label text; v_addr text; v_detail text; v_lat numeric; v_lng numeric;
  v_a text; v_b text; v_c text; v_d text; v_e text;
  v_live boolean; v_pre boolean;
  v_cfg text[]; v_secdef boolean; v_pub boolean; v_anon boolean; v_auth boolean; v_svc boolean;
  v_other_sess uuid; v_spare uuid; v_mkt_owner uuid; v_mkt_dog uuid; v_mkt_route uuid;
  v_mkt_runner uuid; v_mkt_addr uuid; v_km numeric;
  v_all text[] := array['draft','quoted','payment_hold','matching','runner_pending','confirmed',
                        'runner_enroute','picked_up','active','completed','cancelled_owner',
                        'cancelled_runner','expired','no_show','incident_review','refund_pending'];
begin
  -- The flag is enabled HERE rather than inherited from suite 50, so this file does not depend on
  -- a sibling's side effect for the club RPCs to be callable (117's precedent).
  update club_flags set enabled = true where name = 'club_delegation_v2';

  -- ═══ FIXTURES — every one driven through the real RPC chain by t163_pair() ════════════════
  f_home  := t163_pair('ha', 'owner_home');                       -- the positive: 집 반환
  f_site  := t163_pair('sf', 'session_finish');                   -- THE CRITICAL: 현장 반환, address WRITTEN
  f_xfer  := t163_pair('tx', 'owner_home');                       -- → transfer_pending below
  f_ext   := t163_pair('ex', 'owner_home');                       -- → external custody below
  f_inc   := t163_pair('ic', 'owner_home');                       -- → incident opened below
  f_f1    := t163_pair('f1', 'owner_home');                       -- → owner-only return stamp below
  f_seal  := t163_pair('sl', 'owner_home');                       -- → two-sided seal below
  f_open  := t163_pair('ub', 'owner_home');                       -- the deliberately unbounded case
  f_null  := t163_pair('nl', 'owner_home', false);                -- no address at all
  f_pre   := t163_pair('pr', 'owner_home', true, 'confirmed');    -- accepted, NOT handed over
  f_cross := t163_pair('cs', 'owner_home');                       -- P8's cross-session operand

  -- a marketplace booking for P13's control, plus its own owner/dog/route so nothing is shared
  v_mkt_owner  := t_user('t163_mo', 'owner');
  v_mkt_runner := t_user('t163_mr', 'runner');
  v_mkt_dog    := t_dog(v_mkt_owner, '마켓견');
  v_mkt_route  := t_route('t163 마켓 코스');
  insert into addresses (owner_id, label, addr, detail, gate_code_enc, lat, lng)
  values (v_mkt_owner, '마켓 집', '서울 강남구 테헤란로 1', '5층', 'ENC::마켓', 37.5, 127.03)
  returning id into v_mkt_addr;

  -- ═══ [P0] FIXTURE PRECONDITION — asserted ONCE and loudly ═════════════════════════════════
  -- Every pin below is meaningless if this is wrong, and a suite that discovers it pin by pin
  -- reports eleven confusing reds instead of one. Two propositions here, not one:
  --   ⓐ each pairing reached the state its pin claims, through the real transition trigger;
  --   ⓑ each pairing carries an `outbound` `dog_custody_events` row — the branch `picked_up`
  --      produces and the branch `_club_compute_axes` actually reads (0048:786). 162's INSERTed
  --      fixtures never had one, so every pin in that file exercised the LEGACY
  --      `responsible_profile_id` fallback instead of the path production takes.
  begin
    v_bad := '';
    if t163_state((f_home->>'booking')::uuid)
       <> 'runner_delegated/return_pending/' || (f_home->>'runner') || '/owner_home/owner_confirmed=no'
      then v_bad := v_bad || ' home=' || t163_state((f_home->>'booking')::uuid); end if;
    if t163_state((f_site->>'booking')::uuid)
       <> 'runner_delegated/return_pending/' || (f_site->>'runner') || '/session_finish/owner_confirmed=no'
      then v_bad := v_bad || ' site=' || t163_state((f_site->>'booking')::uuid); end if;
    -- the pre-handoff pairing must NOT have moved: acceptance changes `bookings.runner_id` and
    -- nothing else (0047:175), so custody is still the OWNER's. This is the measurement that
    -- 162's `b_early` contradicted.
    if t163_state((f_pre->>'booking')::uuid)
       <> 'runner_delegated/with_custodian/' || (f_pre->>'owner') || '/owner_home/owner_confirmed=no'
      then v_bad := v_bad || ' pre=' || t163_state((f_pre->>'booking')::uuid); end if;
    if (select status from bookings where id = (f_pre->>'booking')::uuid) <> 'confirmed'
      then v_bad := v_bad || ' pre상태=' || (select status::text from bookings where id = (f_pre->>'booking')::uuid); end if;
    -- ⓑ the event branch, on every completed pairing
    for v_j in select x from unnest(array[f_home, f_site, f_xfer, f_ext, f_inc, f_f1, f_seal,
                                          f_open, f_null, f_cross]) as t(x)
    loop
      if not exists (select 1 from dog_custody_events e
                      where e.session_dog_id = (v_j->>'session_dog')::uuid
                        and e.event_type = 'outbound' and e.to_type = 'runner'
                        and e.to_profile_id = (v_j->>'runner')::uuid)
        then v_bad := v_bad || ' outbound누락=' || (v_j->>'session_dog'); end if;
      if (select status from bookings where id = (v_j->>'booking')::uuid) <> 'completed'
        then v_bad := v_bad || ' 미완료=' || (v_j->>'booking'); end if;
      if (select b.club_session_id from bookings b where b.id = (v_j->>'booking')::uuid)
         is distinct from (v_j->>'session')::uuid
        then v_bad := v_bad || ' 세션불일치=' || (v_j->>'booking'); end if;
    end loop;
    if (select address_id from bookings where id = (f_null->>'booking')::uuid) is not null
      then v_bad := v_bad || ' nl에 주소가 있다'; end if;
    if (select address_id from bookings where id = (f_site->>'booking')::uuid) is null
      then v_bad := v_bad || ' CRITICAL 픽스처에 주소가 없다 (누출을 재현할 수 없다)'; end if;
    if v_bad = ''
      then call _pass('crf','P0 fixture precondition — eleven pairings each reached, through the real RPC chain and the real `completed` transition trigger (0045:64), exactly the state its pin claims: ten at runner_delegated/return_pending with the runner as custodian, and the pre-handoff one still at with_custodian with the OWNER as custodian (acceptance changes bookings.runner_id and nothing else, 0047:175). Every completed pairing also carries the `outbound` dog_custody_events row that `picked_up` mints (0045:44), so `_club_compute_axes` takes its EVENT branch (0048:786) — the path production takes and the one 162''s INSERTed fixtures never once exercised. And each booking''s club_session_id equals its pairing''s session_id, which is the reachable half of P8');
    else call _fail('crf','P0 fixture precondition', v_bad); end if;
  exception when others then call _fail('crf','P0 fixture precondition', sqlerrm);
  end;

  -- ═══ [P1] THE CRITICAL, BOTH WAYS — the pin whose absence let the leak through ════════════
  -- ⓐ 집 픽업 + 집 반환, address written → the five fields, asserted as VALUES. A body selecting
  --   constant NULLs keeps every key and passes a key-set check (0065 W6's recorded near-miss),
  --   and 0129's own VERIFY says in its header that it cannot see that body.
  -- ⓑ 집 픽업 + 현장 반환, address written (spec §7.2a row 2 — `address_id` IS SET, for the pickup
  --   leg only), same phase, same runner, same instant → not_runner.
  -- ⓒ THE HOLE IS REAL: 0128's shipped arm, transcribed, HANDS OVER that same home. Without ⓒ,
  --   ⓑ would only prove that the current function refuses something.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', f_home->>'runner', false);
    select count(*) into v_n from booking_pickup_address((f_home->>'booking')::uuid);
    select x.label, x.addr, x.detail, x.lat, x.lng into v_label, v_addr, v_detail, v_lat, v_lng
      from booking_pickup_address((f_home->>'booking')::uuid) x;
    if v_n <> 1 then v_bad := v_bad || ' ⓐrows=' || v_n; end if;
    if v_label is distinct from '우리 집' then v_bad := v_bad || ' ⓐlabel=' || coalesce(v_label,'∅'); end if;
    if v_addr is distinct from '서울 서초구 신반포로 270' then v_bad := v_bad || ' ⓐaddr=' || coalesce(v_addr,'∅'); end if;
    if v_detail is distinct from '203동 1502호' then v_bad := v_bad || ' ⓐdetail=' || coalesce(v_detail,'∅'); end if;
    if v_lat is distinct from 37.508123 or v_lng is distinct from 126.995456
      then v_bad := v_bad || ' ⓐ좌표=' || coalesce(v_lat::text,'∅') || ',' || coalesce(v_lng::text,'∅'); end if;
    -- the leak surface did not widen with the arm
    select count(*) into v_n2 from (
      select jsonb_object_keys(j) as k from (
        select to_jsonb(x) as j from booking_pickup_address((f_home->>'booking')::uuid) x limit 1) s) t
     where k ~* 'gate|code|enc|owner|phone|club|custody|session|mode';
    if v_n2 <> 0 then v_bad := v_bad || ' ⓐ누수키=' || v_n2; end if;

    -- ⓑ the Critical
    perform set_config('request.jwt.claim.sub', f_site->>'runner', false);
    if t163_state((f_site->>'booking')::uuid) not like '%/session_finish/%'
      then v_bad := v_bad || ' ⓑ전제실패:' || t163_state((f_site->>'booking')::uuid); end if;
    begin
      select count(*) into v_n from booking_pickup_address((f_site->>'booking')::uuid);
      v_bad := v_bad || ' ⓑ현장 반환 페어링에 집 주소가 열렸다 (rows=' || v_n || ') — 0128의 CRITICAL이 그대로다';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' ⓑ' || sqlerrm; end if;
    end;
    -- ⓒ the hole is real — 0128's arm, transcribed, hands the home over
    begin
      select count(*) into v_n from t163_arm0128((f_site->>'booking')::uuid);
      select x.addr into v_addr from t163_arm0128((f_site->>'booking')::uuid) x;
      if v_n <> 1 or v_addr is distinct from '서울 서초구 신반포로 270'
        then v_bad := v_bad || ' ⓒ0128 전사본이 누출을 재현하지 못했다 rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' ⓒ0128전사본raise:' || sqlerrm;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = ''
      then call _pass('crf','P1 THE CRITICAL, both directions — ⓐ a 집 픽업 + 집 반환 pairing at return_pending gives its custodian ONE row carrying the real label/addr/detail/lat/lng (values, not shapes: a constant-NULL body keeps every key, and 0129''s VERIFY header says outright that it cannot see that body), with gate_code_enc populated and yet structurally absent from the return keys. ⓑ the same runner, same phase, same instant, on a 집 픽업 + **현장 반환** pairing whose address_id IS WRITTEN (spec §7.2a row 2 — the address serves the PICKUP leg only) gets not_runner. ⓒ and the hole is real rather than a pin''s opinion: 0128''s shipped arm, transcribed here, HANDS THAT HOME OVER — one row, the owner''s street address, to a runner standing at the finish line. This is the pin whose absence let the Critical through 0128''s 896/0 and four green gates');
    else call _fail('crf','P1 THE CRITICAL', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('crf','P1 THE CRITICAL', sqlerrm);
  end;

  -- ═══ [P2] `transfer_pending` ADMITS — the strand case, pinned as a POSITIVE ═══════════════
  -- `session_transfer_initiate` (0057:317,331) moves the phase to `transfer_pending` while the
  -- runner STILL PHYSICALLY HOLDS THE DOG. 0128 keyed on `return_pending` and therefore refused
  -- that runner the destination mid-custody — the strand-an-animal failure this slice exists to
  -- prevent. Reached by the real RPC, and asserted as an admission, not described in a comment.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', f_xfer->>'runner', false);
    begin
      select count(*) into v_n from booking_pickup_address((f_xfer->>'booking')::uuid);
      if v_n <> 1 then v_bad := v_bad || ' 이양 전 rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' 이양 전 raise:' || sqlerrm;
    end;
    -- the real ritual: the holding runner proposes handing the dog to another runner and the
    -- transfer STALLS (nobody accepts) — 0057's own scenario.
    perform session_transfer_initiate((f_xfer->>'session_dog')::uuid, 'runner',
                                      (f_xfer->>'host')::uuid, null, '반환 중 러너 교대 요청');
    if t163_state((f_xfer->>'booking')::uuid)
       <> 'runner_delegated/transfer_pending/' || (f_xfer->>'runner') || '/owner_home/owner_confirmed=no'
      then v_bad := v_bad || ' 이양 후 상태=' || t163_state((f_xfer->>'booking')::uuid); end if;
    begin
      select count(*) into v_n from booking_pickup_address((f_xfer->>'booking')::uuid);
      if v_n <> 1 then v_bad := v_bad || ' 이양 후 rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' 이양 후 raise:' || sqlerrm || ' (개를 안은 러너가 목적지를 잃었다)';
    end;
    -- the same fixture measured against 0128's arm: it REFUSES, which is the defect
    begin
      perform 1 from t163_arm0128((f_xfer->>'booking')::uuid);
      v_bad := v_bad || ' 0128 전사본이 거절하지 않았다 (결함이 재현되지 않는다)';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' 0128전사본:' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = ''
      then call _pass('crf','P2 transfer_pending ADMITS — a real `session_transfer_initiate` (0057:317) during the return window moves the phase to transfer_pending while the runner is still holding the dog, and 0129 keeps handing them the destination (1 row before, 1 row after). 0128''s arm, transcribed, REFUSES the identical fixture — so the strand is measured on both sides, not asserted. ⚠ This is why the phase conjunct is the NEGATIVE form `<> ''resolved''` and not a list: a list is what created this hole, and the next phase nobody enumerates creates it again');
    else call _fail('crf','P2 transfer_pending ADMITS', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('crf','P2 transfer_pending ADMITS', sqlerrm);
  end;

  -- ═══ [P3] ESCALATION DURING THE RETURN WINDOW — what the arm does, and why it is right ════
  -- 🔴 A MEASURED CORRECTION TO THE CONTRACT. Contract v2's F3 describes `completed →
  -- incident_review` closing address access via the normalizer's `with_custodian` rewrite. The
  -- transition MAP permits that edge (0066:55) but **no shipped writer performs it from
  -- `completed`**: `session_host_force_resolve` raises `not_stuck` outside picked_up/active
  -- (0070:208), `session_transfer_accept`'s external branch guards
  -- `if v_bst in ('picked_up','active')` (0058:163, and 0045:257 before it), and
  -- `sweep_run_end_recovery` claims it only `from 'active'` AND only for
  -- `club_session_id is null` (0083:1474). So that scenario is not reachable from the return
  -- window and a pin on it would be a fiction. What IS reachable is measured in two arms:
  --   ⓐ an incident OPENED on the dog and booking — the real `club_incident_open`, which really
  --     writes `session_dogs` (payout_hold, 0070:437) and therefore really re-fires the axes
  --     normalizer. The arm STILL ADMITS, and that is correct: the runner is still holding the
  --     dog and still has to deliver it. An incident is a money and safety event, not a return.
  --   ⓑ an EXTERNAL custody transfer — initiate + accept with an artifact, the real ritual. Here
  --     custody genuinely LEAVES the runner (custodian_type becomes the clinic, profile NULL), and
  --     the arm REFUSES. The destination follows the dog; it does not follow the person who used
  --     to hold it.
  begin
    v_bad := '';
    -- ⓐ incident opened by the host on the dog + booking
    perform set_config('request.jwt.claim.sub', f_inc->>'host', false);
    perform club_incident_open((f_inc->>'session')::uuid, 'S2', '반환 중 이상 징후 신고',
                               (f_inc->>'dog')::uuid, (f_inc->>'booking')::uuid, null);
    if not exists (select 1 from session_dogs where id = (f_inc->>'session_dog')::uuid
                     and payout_hold = 'held' and payout_hold_reason = 'incident')
      then v_bad := v_bad || ' ⓐ전제실패: 인시던트가 session_dogs를 쓰지 않았다'; end if;
    if t163_state((f_inc->>'booking')::uuid)
       <> 'runner_delegated/return_pending/' || (f_inc->>'runner') || '/owner_home/owner_confirmed=no'
      then v_bad := v_bad || ' ⓐ인시던트 뒤 상태=' || t163_state((f_inc->>'booking')::uuid); end if;
    perform set_config('request.jwt.claim.sub', f_inc->>'runner', false);
    begin
      select count(*) into v_n from booking_pickup_address((f_inc->>'booking')::uuid);
      if v_n <> 1 then v_bad := v_bad || ' ⓐrows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' ⓐraise:' || sqlerrm; end;
    -- ⓑ external custody transfer — the dog leaves the runner's hands, for real
    perform set_config('request.jwt.claim.sub', f_ext->>'runner', false);
    begin
      select count(*) into v_n from booking_pickup_address((f_ext->>'booking')::uuid);
      if v_n <> 1 then v_bad := v_bad || ' ⓑ이양 전 rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' ⓑ이양 전 raise:' || sqlerrm; end;
    perform session_transfer_initiate((f_ext->>'session_dog')::uuid, 'clinic', null,
                                      '반포동물병원', '반환 중 부상');
    perform session_transfer_accept((f_ext->>'session_dog')::uuid,
                                    jsonb_build_object('receipt', 'clinic-receipt-163'));
    if t163_state((f_ext->>'booking')::uuid) not like 'runner_delegated/with_custodian/∅/%'
      then v_bad := v_bad || ' ⓑ외부 이양 뒤 상태=' || t163_state((f_ext->>'booking')::uuid); end if;
    -- ⓑ-bis THE REACHABILITY MEASUREMENT, executed rather than read off the transition map: the
    --   external branch escalates to `incident_review` only `if v_bst in ('picked_up','active')`
    --   (0058:163). This pairing is `completed`, so the booking must still BE `completed` after
    --   the accept. That is contract v2 §F3's scenario failing to occur, measured on every run
    --   instead of trusted to a sentence — the day a writer appears, this reddens.
    if (select status from bookings where id = (f_ext->>'booking')::uuid) <> 'completed'
      then v_bad := v_bad || ' ⓑ-bis 외부 이양이 completed 부킹을 ' ||
        (select status::text from bookings where id = (f_ext->>'booking')::uuid) || '로 옮겼다'; end if;
    begin
      perform 1 from booking_pickup_address((f_ext->>'booking')::uuid);
      v_bad := v_bad || ' ⓑ개를 병원에 넘긴 러너에게 집 주소가 계속 열려 있다';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' ⓑ' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = ''
      then call _pass('crf','P3 escalation during the return window — ⓐ a REAL `club_incident_open` on the dog and booking writes session_dogs (payout_hold, 0070:437) and re-fires the axes normalizer, and the arm STILL ADMITS: the runner is still holding the dog and still has to deliver it, so an incident is a money/safety event and not a return. ⓑ a REAL external custody transfer (initiate → accept with artifact) moves the custodian to the clinic and the arm REFUSES — the destination follows the DOG, not the person who used to hold it. 🔴 MEASURED CORRECTION TO CONTRACT v2 §F3: `completed → incident_review` is a legal EDGE (0066:55) with NO shipped writer from `completed` — force_resolve raises not_stuck (0070:208), transfer_accept''s external branch guards picked_up/active (0058:163), and the run-end sweep claims it only from `active` on non-club bookings (0083:1474). The pin ⓑ-bis re-measures that claim on every run instead of trusting this sentence, so the day a new writer appears the argument is re-opened rather than silently stale');
    else call _fail('crf','P3 escalation during the return window', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('crf','P3 escalation during the return window', sqlerrm);
  end;

  -- ═══ [P4] `resolved` REFUSES — reached by a REAL return seal, never by an UPDATE ══════════
  -- Three beats: admitted before · the seal really moved the phase, through two real
  -- `session_confirm_return` calls · refused after, with the booking STILL `completed` so what
  -- closed is the custody phase and not the status. A status-list fix passes beat one and fails
  -- beat three forever.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', f_seal->>'runner', false);
    begin
      select count(*) into v_n from booking_pickup_address((f_seal->>'booking')::uuid);
      if v_n <> 1 then v_bad := v_bad || ' ⓐ봉인 전 rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' ⓐ봉인 전 raise:' || sqlerrm; end;
    perform set_config('request.jwt.claim.sub', f_seal->>'owner', false);
    perform session_confirm_return((f_seal->>'session_dog')::uuid);
    perform set_config('request.jwt.claim.sub', f_seal->>'runner', false);
    perform session_confirm_return((f_seal->>'session_dog')::uuid);
    if t163_state((f_seal->>'booking')::uuid)
       <> 'runner_delegated/resolved/' || (f_seal->>'owner') || '/owner_home/owner_confirmed=yes'
      then v_bad := v_bad || ' ⓑ봉인 후 상태=' || t163_state((f_seal->>'booking')::uuid); end if;
    begin
      perform 1 from booking_pickup_address((f_seal->>'booking')::uuid);
      v_bad := v_bad || ' ⓒ봉인 뒤에도 주소가 열려 있다';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' ⓒ' || sqlerrm; end if;
    end;
    if (select status from bookings where id = (f_seal->>'booking')::uuid) <> 'completed'
      then v_bad := v_bad || ' ⓓ부킹 상태=' || (select status::text from bookings where id = (f_seal->>'booking')::uuid); end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = ''
      then call _pass('crf','P4 `resolved` REFUSES — ⓐ one row before the seal ⟶ ⓑ two REAL `session_confirm_return` calls (owner then runner, the way 0045:106 requires) move the phase to resolved and the custodian back to the owner ⟶ ⓒ the same runner on the same booking gets not_runner, while ⓓ the booking is STILL `completed` — so what closed is the custody phase, not the status. There is no sweep, no expiry job and no flag to forget to clear. The tempting one-liner (add `completed` to the marketplace status list) passes ⓐ and fails ⓒ forever');
    else call _fail('crf','P4 `resolved` REFUSES', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('crf','P4 `resolved` REFUSES', sqlerrm);
  end;

  -- ═══ [P5] F1 — the OWNER'S OWN STAMP closes it, even though the runner never confirmed ════
  -- The defect the executing reviewer found and both contracts missed: the owner says 「I have my
  -- dog」, the runner never taps, `session_confirm_return` seals only when BOTH stamps exist
  -- (0045:106), so the phase stays `return_pending` FOREVER — no sweep, and
  -- `session_host_force_resolve` refuses at `completed` (0070:208). It is a LIVE read, so the
  -- owner who later moves house shows their new address to a runner who never confirmed.
  -- Beats: admitted before the owner's stamp · the stamp is real and the phase did NOT move ·
  -- refused after. The middle beat is what makes the refusal attributable to the F1 conjunct
  -- rather than to the phase.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', f_f1->>'runner', false);
    begin
      select count(*) into v_n from booking_pickup_address((f_f1->>'booking')::uuid);
      if v_n <> 1 then v_bad := v_bad || ' ⓐ스탬프 전 rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' ⓐ스탬프 전 raise:' || sqlerrm; end;
    perform set_config('request.jwt.claim.sub', f_f1->>'owner', false);
    perform session_confirm_return((f_f1->>'session_dog')::uuid);   -- owner only; runner never taps
    if t163_state((f_f1->>'booking')::uuid)
       <> 'runner_delegated/return_pending/' || (f_f1->>'runner') || '/owner_home/owner_confirmed=yes'
      then v_bad := v_bad || ' ⓑ스탬프 뒤 상태=' || t163_state((f_f1->>'booking')::uuid); end if;
    perform set_config('request.jwt.claim.sub', f_f1->>'runner', false);
    begin
      perform 1 from booking_pickup_address((f_f1->>'booking')::uuid);
      v_bad := v_bad || ' ⓒ보호자가 「개를 받았다」고 도장을 찍었는데도 주소가 계속 열려 있다 (F1)';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' ⓒ' || sqlerrm; end if;
    end;
    -- and 0128's arm, transcribed, keeps it open — the hole reproduced rather than described
    begin
      select count(*) into v_n from t163_arm0128((f_f1->>'booking')::uuid);
      if v_n <> 1 then v_bad := v_bad || ' ⓓ0128 전사본 rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' ⓓ0128전사본raise:' || sqlerrm || ' (F1이 재현되지 않는다)';
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = ''
      then call _pass('crf','P5 F1 — the owner''s own stamp closes the grant. ⓐ one row before ⟶ ⓑ a REAL owner-side `session_confirm_return` sets owner_confirmed_return_at while the phase STAYS `return_pending` (the seal needs both stamps, 0045:106) ⟶ ⓒ the runner who never confirmed now gets not_runner. Beat ⓑ is load-bearing: it is what makes the refusal attributable to the F1 conjunct rather than to the phase conjunct. ⓓ 0128''s arm, transcribed, still hands the address over — and since this is a LIVE read, that is an owner who moved house showing their NEW address to a runner who never tapped. Argued rather than timed out: a clock has to choose between stranding a genuinely delayed runner and leaving a stale grant open; the counterparty asserting possession is neither guesswork nor a deadline');
    else call _fail('crf','P5 F1 owner stamp closes it', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('crf','P5 F1 owner stamp closes it', sqlerrm);
  end;

  -- ═══ [P6] EVERYONE ELSE IS REFUSED — foreign runner · host · another owner · the owner · anon ═
  -- All reached legitimately: the foreign runner is a real custodian of a real pairing standing in
  -- a real club session, the host really hosts one, the other owner really owns one. Each refusal
  -- carries the positive control that proves it is SCOPE and not 「this caller can read nothing」.
  begin
    v_bad := '';
    -- a foreign runner: f_open's runner, who really is a custodian at return_pending
    perform set_config('request.jwt.claim.sub', f_open->>'runner', false);
    begin
      perform 1 from booking_pickup_address((f_home->>'booking')::uuid);
      v_bad := v_bad || ' 다른 러너가 남의 집 주소를 읽었다';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' 타러너:' || sqlerrm; end if;
    end;
    begin   -- positive control on that runner's OWN pairing
      select count(*) into v_n from booking_pickup_address((f_open->>'booking')::uuid);
      if v_n <> 1 then v_bad := v_bad || ' 대조군(타러너 자기 페어링) rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' 대조군raise:' || sqlerrm; end;
    -- the HOST of the target's own session
    perform set_config('request.jwt.claim.sub', f_home->>'host', false);
    begin
      perform 1 from booking_pickup_address((f_home->>'booking')::uuid);
      v_bad := v_bad || ' 호스트가 보호자의 집 주소를 읽었다';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' 호스트:' || sqlerrm; end if;
    end;
    -- ANOTHER owner
    perform set_config('request.jwt.claim.sub', f_site->>'owner', false);
    begin
      perform 1 from booking_pickup_address((f_home->>'booking')::uuid);
      v_bad := v_bad || ' 남의 보호자가 읽었다';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' 타보호자:' || sqlerrm; end if;
    end;
    -- THE OWNER THEMSELVES — this RPC is the runner's disclosure surface, not an address reader
    perform set_config('request.jwt.claim.sub', f_home->>'owner', false);
    begin
      perform 1 from booking_pickup_address((f_home->>'booking')::uuid);
      v_bad := v_bad || ' 보호자 본인이 이 RPC를 통과했다 (이 함수는 러너 공개 표면이다)';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' 보호자본인:' || sqlerrm; end if;
    end;
    -- ANON: no JWT at all
    perform set_config('request.jwt.claim.sub', '', false);
    begin
      perform 1 from booking_pickup_address((f_home->>'booking')::uuid);
      v_bad := v_bad || ' JWT 없는 호출이 통과했다';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' 무JWT:' || sqlerrm; end if;
    end;
    if v_bad = ''
      then call _pass('crf','P6 everyone else is refused — a foreign runner (himself a real custodian at return_pending in his own real session), the target session''s HOST, another owner, the pairing''s OWN owner, and a caller with no JWT at all each get not_runner. The foreign runner carries a positive control on his own pairing, so the refusal reads as scope and not as 「this caller can read nothing」. The owner arm matters on its own: this RPC is the RUNNER''s disclosure surface, and an owner who could call it would make it an address reader with a different party gate');
    else call _fail('crf','P6 everyone else is refused', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('crf','P6 everyone else is refused', sqlerrm);
  end;

  -- ═══ [P7] ORACLE INDISTINGUISHABILITY — five paths compared TO EACH OTHER ═════════════════
  -- 0054:73's doctrine: the moment 「absent」 and 「exists but you may not」 differ, an attacker
  -- sweeps uuids and learns which bookings are real. Compared to each other, never to a literal —
  -- five paths that all regressed to the same NEW string would still be indistinguishable, and
  -- indistinguishability is the property, not the spelling.
  -- 🔴 THE THIRD PROBE IS THE ONE THAT MATTERS AND IT IS THE WRONG-MODE ONE: the caller IS the
  -- custodian, the phase IS right, and ONLY `return_mode` differs. That is the branch an
  -- oracle-breaking body can actually tell apart (162's first draft probed a SEALED pairing, where
  -- the custodian has already moved to the owner, so the caller never reached the distinguishing
  -- branch at all and the mutation passed green). 0129's VERIFY names the complementary hole it
  -- cannot see: one `raise` whose message is a `case` expression satisfies every text count.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', f_site->>'runner', false);
    if t163_state((f_site->>'booking')::uuid)
       <> 'runner_delegated/return_pending/' || (f_site->>'runner') || '/session_finish/owner_confirmed=no'
      then v_bad := v_bad || ' 전제실패(모드 프로브):' || t163_state((f_site->>'booking')::uuid); end if;
    if t163_state((f_seal->>'booking')::uuid) not like '%/resolved/%'
      then v_bad := v_bad || ' 전제실패(봉인 프로브 — P4가 먼저 돌아야 한다):' || t163_state((f_seal->>'booking')::uuid); end if;
    v_a := t163_probe(gen_random_uuid());                      -- absent
    v_b := t163_probe((f_home->>'booking')::uuid);             -- foreign (this caller is not its custodian)
    v_c := t163_probe((f_site->>'booking')::uuid);             -- HIS OWN pairing, only the mode is wrong
    v_d := t163_probe((f_f1->>'booking')::uuid);               -- owner already stamped (F1 branch)
    v_e := t163_probe((f_seal->>'booking')::uuid);             -- sealed
    if v_a like 'ok:%' or v_b like 'ok:%' or v_c like 'ok:%' or v_d like 'ok:%' or v_e like 'ok:%'
      then v_bad := v_bad || ' 다섯 중 하나가 통과했다'; end if;
    if not (v_a = v_b and v_b = v_c and v_c = v_d and v_d = v_e)
      then v_bad := v_bad || ' 부재=[' || v_a || '] 타인=[' || v_b || '] 모드틀림=[' || v_c
                          || '] F1=[' || v_d || '] 봉인후=[' || v_e || ']'; end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = ''
      then call _pass('crf','P7 oracle indistinguishability — five paths (absent booking · a booking this caller does not hold · **his OWN pairing where only return_mode differs** · a pairing whose owner already stamped · a sealed pairing) return byte-identical SQLSTATE+message pairs. Compared to EACH OTHER, not to a literal: five paths regressing together to a new string would still be indistinguishable, and the property is indistinguishability, not spelling. 🔴 The third probe is the load-bearing one — it is the only state where the caller reaches the distinguishing branch, and 162''s first draft probed a SEALED pairing instead (where the custodian has already moved to the owner) and let an oracle-breaking mutation pass green. 0129''s club arm is a disjunct inside ONE boolean, never a second raise site — and its VERIFY names the shape it cannot see: a single `raise` whose message is a `case` expression, which this pin is what catches');
    else call _fail('crf','P7 oracle indistinguishability', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('crf','P7 oracle indistinguishability', sqlerrm);
  end;

  -- ═══ [P8] CROSS-SESSION BINDING (Moderate-1) — two arms, and only ⓑ can redden ════════════
  -- `session_dogs.session_id` and `.booking_id` are independent FKs (0030:81,86); nothing in the
  -- schema requires the booking's `club_session_id` to equal the row's session. Written as two
  -- arms that measure two different things, and each says which:
  --   ⓐ **the reachable truth** — every pairing the real chain built has them equal (P0 asserts it
  --     across all ten). This arm is green with or without the conjunct and says so; it is the
  --     standing evidence that the mint is consistent TODAY.
  --   ⓑ **the conjunct's own job** — a mismatch planted directly, because the mint cannot produce
  --     one. This is not a contrivance: it is what a future mint, a repair script or a
  --     re-parenting migration looks like from the arm's point of view, and 「club-only by
  --     construction」 must be a CONSTRAINT rather than a convention. The row is restored
  --     immediately so nothing downstream inherits a planted state.
  begin
    v_bad := '';
    -- ⓐ reachable truth, restated on this fixture specifically
    if (select b.club_session_id from bookings b where b.id = (f_cross->>'booking')::uuid)
       is distinct from (select sd.session_id from session_dogs sd
                          where sd.booking_id = (f_cross->>'booking')::uuid)
      then v_bad := v_bad || ' ⓐ실제 민트가 이미 어긋나 있다'; end if;
    perform set_config('request.jwt.claim.sub', f_cross->>'runner', false);
    begin
      select count(*) into v_n from booking_pickup_address((f_cross->>'booking')::uuid);
      if v_n <> 1 then v_bad := v_bad || ' ⓐrows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' ⓐraise:' || sqlerrm; end;
    -- ⓑ the conjunct, with a mismatch planted and restored
    v_other_sess := (f_open->>'session')::uuid;
    begin
      update session_dogs set session_id = v_other_sess
       where id = (f_cross->>'session_dog')::uuid;
      if (select sd.session_id from session_dogs sd where sd.id = (f_cross->>'session_dog')::uuid)
         is distinct from v_other_sess
        then v_bad := v_bad || ' ⓑ심기 실패'; end if;
      begin
        perform 1 from booking_pickup_address((f_cross->>'booking')::uuid);
        v_bad := v_bad || ' ⓑ부킹의 클럽 세션과 다른 세션에 속한 행이 주소를 열었다 (클럽 한정이 관례일 뿐 제약이 아니다)';
      exception when others then
        if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' ⓑ' || sqlerrm; end if;
      end;
    exception when others then v_bad := v_bad || ' ⓑ' || sqlerrm;
    end;
    -- restore, unconditionally
    begin
      update session_dogs set session_id = (f_cross->>'session')::uuid
       where id = (f_cross->>'session_dog')::uuid;
      if (select sd.session_id from session_dogs sd where sd.id = (f_cross->>'session_dog')::uuid)
         is distinct from (f_cross->>'session')::uuid
        then v_bad := v_bad || ' 복원 실패'; end if;
      select count(*) into v_n from booking_pickup_address((f_cross->>'booking')::uuid);
      if v_n <> 1 then v_bad := v_bad || ' 복원 후 rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' 복원:' || sqlerrm;
    end;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = ''
      then call _pass('crf','P8 cross-session binding — ⓐ the reachable truth: every pairing the real RPC chain builds has session_dogs.session_id = bookings.club_session_id, and its custodian is admitted. ⓑ the conjunct''s own job: with the row RE-PARENTED to a different club session (a state the mint cannot produce, planted because 0030:81,86 are independent FKs and nothing forbids it), the same custodian on the same booking gets not_runner. ⚠ ⓑ is not a contrivance — it is what a future mint, a repair script or a re-parenting migration looks like from the arm''s point of view, and it is what turns 「club-only by construction」 from a convention into a constraint. The row is restored immediately and the restoration is re-measured, so nothing below inherits a planted state');
    else call _fail('crf','P8 cross-session binding', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('crf','P8 cross-session binding', sqlerrm);
  end;

  -- ═══ [P9] THE DELIBERATELY UNBOUNDED CASE — pinned so nobody 「fixes」 it ═══════════════════
  -- 🔴 READ THIS BEFORE CLOSING IT. If NEITHER side confirms the return, the runner keeps the
  -- destination indefinitely. That is not an oversight and it is not F1: F1 is 「the owner said the
  -- dog is home」, which this arm honours. Here nobody has said anything, and in that state THE DOG
  -- GENUINELY HAS NOT BEEN RETURNED — the runner may still be standing outside the door. A sweep
  -- or a timeout closing this would take the address away from someone still holding an animal,
  -- which is the strand-an-animal failure the whole slice exists to prevent.
  -- The second half is what makes the unboundedness STRUCTURAL rather than an accident: there is
  -- no operator escape hatch at this point either — `session_host_force_resolve` really raises
  -- `not_stuck` at `completed` (0070:208), executed here rather than quoted.
  begin
    v_bad := '';
    if t163_state((f_open->>'booking')::uuid)
       <> 'runner_delegated/return_pending/' || (f_open->>'runner') || '/owner_home/owner_confirmed=no'
      then v_bad := v_bad || ' 전제실패:' || t163_state((f_open->>'booking')::uuid); end if;
    perform set_config('request.jwt.claim.sub', f_open->>'runner', false);
    begin
      select count(*) into v_n from booking_pickup_address((f_open->>'booking')::uuid);
      if v_n <> 1 then v_bad := v_bad || ' rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' raise:' || sqlerrm; end;
    perform set_config('request.jwt.claim.sub', f_open->>'host', false);
    begin
      perform session_host_force_resolve((f_open->>'session_dog')::uuid, '아무도 확인하지 않았다',
                                          jsonb_build_object('note', 'x'));
      v_bad := v_bad || ' 호스트 강제 종결이 completed에서 통과했다 (0070:208의 not_stuck이 사라졌다)';
    exception when others then
      if sqlerrm not like '%not_stuck%' then v_bad := v_bad || ' 강제종결:' || sqlerrm; end if;
    end;
    -- and the state really did not move
    if t163_state((f_open->>'booking')::uuid)
       <> 'runner_delegated/return_pending/' || (f_open->>'runner') || '/owner_home/owner_confirmed=no'
      then v_bad := v_bad || ' 강제 종결 시도가 상태를 바꿨다:' || t163_state((f_open->>'booking')::uuid); end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = ''
      then call _pass('crf','P9 the deliberately unbounded case, asserted so nobody closes it by accident — when NEITHER side confirms the return, the runner keeps the destination and this pin says that is CORRECT: in that state the dog genuinely has not been returned and the runner may still be standing outside the door, so a sweep or a timeout would take the address away from someone still holding an animal. It is not F1 (there the OWNER stamped, and the arm honours that stamp — P5). The second half makes the unboundedness structural rather than accidental: `session_host_force_resolve` really raises not_stuck at `completed` (0070:208, executed here rather than quoted) and really leaves the state untouched, so there is no operator escape hatch to mistake for one either. ⚠ If a future slice wants to bound this, the honest instrument is a NEW owner-side signal, never a clock');
    else call _fail('crf','P9 the deliberately unbounded case', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('crf','P9 the deliberately unbounded case', sqlerrm);
  end;

  -- ═══ [P10] THE MODE COLUMNS THEMSELVES — defaults, NOT NULL, CHECK EXECUTED, survival ═════
  -- 0129's VERIFY ④ is CATALOG-only and says so; this is the executed half. Four propositions:
  --   ⓐ a pairing minted by the real `session_delegate_dog` gets `owner_home`/`owner_home` — the
  --     argued-safe default, measured on a real mint rather than read off `pg_attrdef`.
  --   ⓑ the CHECK really refuses, on a real row, in a subtransaction that is rolled back.
  --   ⓒ NOT NULL really refuses.
  --   ⓓ the axes normalizer (a BEFORE INSERT OR UPDATE trigger that rewrites fifteen columns on
  --     every write, 0040:258) never clobbers the modes — asserted across a pairing that has been
  --     through the entire lifecycle including a transfer.
  begin
    v_bad := '';
    -- ⓐ the DEFAULT on a real mint. `t163_pair` writes the modes explicitly (it has to — the
    --    factory has to be able to build the 현장 반환 fixture), so this reads a row the factory
    --    never touched: a second dog delegated into the same session by the real
    --    `session_delegate_dog`, whose insert names neither column.
    f_md := t163_pair('md');
    v_dog2 := t_dog((f_md->>'owner')::uuid, '기본값견');
    perform set_config('request.jwt.claim.sub', f_md->>'owner', false);
    v_spare := session_delegate_dog((f_md->>'session')::uuid, v_dog2, t_consent());
    perform set_config('request.jwt.claim.sub', '', false);
    if (select return_mode || '/' || pickup_mode from session_dogs where id = v_spare)
       <> 'owner_home/owner_home'
      then v_bad := v_bad || ' ⓐ=' || (select return_mode || '/' || pickup_mode from session_dogs where id = v_spare); end if;
    -- ⓑ the CHECK, executed against a real row
    begin
      update session_dogs set return_mode = 'somewhere_else' where id = v_spare;
      v_bad := v_bad || ' ⓑCHECK가 불법 값을 받아들였다';
    exception when check_violation then null;
      when others then v_bad := v_bad || ' ⓑ' || sqlstate || ':' || sqlerrm;
    end;
    begin
      update session_dogs set pickup_mode = 'from_the_moon' where id = v_spare;
      v_bad := v_bad || ' ⓑCHECK(pickup)가 불법 값을 받아들였다';
    exception when check_violation then null;
      when others then v_bad := v_bad || ' ⓑp' || sqlstate || ':' || sqlerrm;
    end;
    -- ⓒ NOT NULL, executed
    begin
      update session_dogs set return_mode = null where id = v_spare;
      v_bad := v_bad || ' ⓒNOT NULL이 NULL을 받아들였다';
    exception when not_null_violation then null;
      when others then v_bad := v_bad || ' ⓒ' || sqlstate || ':' || sqlerrm;
    end;
    -- the row survived all three refusals unchanged
    if (select return_mode || '/' || pickup_mode from session_dogs where id = v_spare)
       <> 'owner_home/owner_home'
      then v_bad := v_bad || ' 거절 뒤 행이 변했다=' || (select return_mode || '/' || pickup_mode from session_dogs where id = v_spare); end if;
    -- ⓓ the normalizer never clobbered the mode on a pairing that went the whole way
    if (select return_mode from session_dogs where id = (f_site->>'session_dog')::uuid)
       <> 'session_finish'
      then v_bad := v_bad || ' ⓓ정규화기가 모드를 덮어썼다=' || (select return_mode from session_dogs where id = (f_site->>'session_dog')::uuid); end if;
    if (select return_mode from session_dogs where id = (f_xfer->>'session_dog')::uuid)
       <> 'owner_home'
      then v_bad := v_bad || ' ⓓ이양 뒤 모드가 변했다'; end if;
    if v_bad = ''
      then call _pass('crf','P10 the mode columns, executed — ⓐ a pairing minted by the real `session_delegate_dog` carries owner_home/owner_home, the argued-safe default (no on-site return is shipped, so any other default would silently REVOKE the destination for every in-flight club return the moment 0129 applies). ⓑ the two named CHECK constraints really refuse an illegal value on a real row (23514), and ⓒ NOT NULL really refuses NULL — 0129''s VERIFY ④ is CATALOG-only and says so, and this is the half it cannot do on an empty table. ⓓ the axes normalizer (0040:258, a BEFORE trigger that rewrites fifteen columns on every write) never clobbers the modes: a pairing driven through delegation, payment, assignment, handoff, settlement AND a custody transfer still reports the mode its owner chose at sign-up. ⚠ The consequence of the default, stated: `return_mode = ''owner_home''` is TRUE BY DEFAULT, so the other five conjuncts carry the weight until the sign-up slice writes real answers');
    else call _fail('crf','P10 the mode columns', v_bad); end if;
  exception when others then call _fail('crf','P10 the mode columns', sqlerrm);
  end;

  -- ═══ [P11] address_id NULL at return_pending → 0 ROWS, not an error ═══════════════════════
  -- Today's actual production shape (0081:184-186 mints club bookings with `address_id` NULL). The
  -- gate opens; the JOIN decides there is nothing to hand over. 0 rows and an exception are
  -- different signals to the client (「미지정 — 채팅으로 물어보기」 vs 「불러오지 못했어요 — 재시도」),
  -- and collapsing them leaves a runner pressing retry forever (0060 W4's reasoning, unchanged).
  begin
    v_bad := '';
    if t163_state((f_null->>'booking')::uuid) not like 'runner_delegated/return_pending/%'
      then v_bad := v_bad || ' 전제실패:' || t163_state((f_null->>'booking')::uuid); end if;
    if (select address_id from bookings where id = (f_null->>'booking')::uuid) is not null
      then v_bad := v_bad || ' 전제실패: address_id가 NULL이 아니다'; end if;
    perform set_config('request.jwt.claim.sub', f_null->>'runner', false);
    begin
      select count(*) into v_n from booking_pickup_address((f_null->>'booking')::uuid);
      if v_n <> 0 then v_bad := v_bad || ' rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' raise:' || sqlerrm; end;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = ''
      then call _pass('crf','P11 address-less club pairing — in today''s real production shape (0081:184-186 mints club bookings without address_id), the custodian at return_pending gets 0 ROWS, not an exception. The gate opens and the JOIN decides there is nothing to hand over, which is why a both-legs-on-site pairing cannot leak an address it never had. ⚠ SCOPE: this is the bounded-blast-radius claim for the both-on-site row of spec §7.2a''s table ONLY — the mixed row (집 픽업 + 현장 반환) DOES carry an address, and P1 ⓑ is what covers it. Reading this pin as covering both is exactly the reasoning error that produced 0128''s Critical');
    else call _fail('crf','P11 address-less club pairing', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('crf','P11 address-less club pairing', sqlerrm);
  end;

  -- ═══ [P12] PRE-HANDOFF IS REFUSED, ON A REACHABLE FIXTURE ═════════════════════════════════
  -- 🔴 THIS IS THE HONEST REPLACEMENT FOR 162 P4 ⓔ. That pin asserted the same property on a row
  -- the product cannot make: a runner who is already custodian on a `confirmed` booking. The real
  -- chain produces the opposite — `session_delegate_dog` makes the OWNER responsible (0048:135),
  -- `session_proposal_respond` changes `bookings.runner_id` and touches no custody column
  -- (0047:175), and the runner becomes custodian only at `picked_up` (0045:44). So the PROPERTY —
  -- 「the arm opens when the runner is holding the dog, not when the dog is merely assigned to
  -- them」 — is established here by the custody axis itself rather than by a manufactured phase.
  -- Stated without reference to any mutation: **an accepted-but-not-yet-handed-over club pairing
  -- discloses no address to its assigned runner.**
  begin
    v_bad := '';
    if t163_state((f_pre->>'booking')::uuid)
       <> 'runner_delegated/with_custodian/' || (f_pre->>'owner') || '/owner_home/owner_confirmed=no'
      then v_bad := v_bad || ' 전제실패:' || t163_state((f_pre->>'booking')::uuid); end if;
    if (select runner_id from bookings where id = (f_pre->>'booking')::uuid)
       is distinct from (f_pre->>'runner')::uuid
      then v_bad := v_bad || ' 전제실패: 러너가 배정되지 않았다'; end if;
    if exists (select 1 from dog_custody_events where session_dog_id = (f_pre->>'session_dog')::uuid)
      then v_bad := v_bad || ' 전제실패: 인계 전인데 커스터디 이벤트가 있다'; end if;
    if (select scheduled_at from bookings where id = (f_pre->>'booking')::uuid) >= now() + interval '24 hours'
      then v_bad := v_bad || ' 전제실패: 마켓 24h 창 밖이라 거절이 클럽 팔 때문인지 알 수 없다'; end if;
    perform set_config('request.jwt.claim.sub', f_pre->>'runner', false);
    -- ⚠ the session is 90 minutes out, so the MARKETPLACE arm's `confirmed` + T−24h branch is
    --   genuinely live here. That makes this the STRONGEST form of the pin: the address IS
    --   disclosed, by the pre-existing gate, and the club arm adds nothing — which is precisely
    --   contract v2 §1's claim that the negative phase form 「does not widen the outbound leg」.
    begin
      select count(*) into v_n from booking_pickup_address((f_pre->>'booking')::uuid);
      if v_n <> 1 then v_bad := v_bad || ' 마켓 24h 팔이 안 열렸다 rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' 마켓 24h 팔:' || sqlerrm; end;
    -- the club arm alone, isolated: flip the mode so the club disjunct is dead, and confirm the
    -- answer is unchanged — i.e. the disclosure above came from the marketplace arm, not from the
    -- club arm opening at delegation time.
    update session_dogs set return_mode = 'session_finish' where id = (f_pre->>'session_dog')::uuid;
    begin
      select count(*) into v_n from booking_pickup_address((f_pre->>'booking')::uuid);
      if v_n <> 1 then v_bad := v_bad || ' 모드를 꺼도 마켓 팔이 살아 있어야 한다 rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' 모드끔:' || sqlerrm; end;
    update session_dogs set return_mode = 'owner_home' where id = (f_pre->>'session_dog')::uuid;
    -- now push the same booking OUT of the marketplace window and re-ask: with the club arm the
    -- only candidate, an accepted-but-unhanded pairing discloses nothing.
    update bookings set scheduled_at = now() + interval '10 days'
     where id = (f_pre->>'booking')::uuid;
    begin
      perform 1 from booking_pickup_address((f_pre->>'booking')::uuid);
      v_bad := v_bad || ' 인계 전인 위탁 페어링이 주소를 열었다 (팔이 반환 시점이 아니라 위탁 시점에 열린다)';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' ' || sqlerrm; end if;
    end;
    if t163_state((f_pre->>'booking')::uuid) not like '%/with_custodian/' || (f_pre->>'owner') || '/%'
      then v_bad := v_bad || ' 커스터디언이 러너로 옮겨갔다:' || t163_state((f_pre->>'booking')::uuid); end if;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = ''
      then call _pass('crf','P12 an accepted-but-not-yet-handed-over club pairing discloses no address to its assigned runner — and the fixture is REACHABLE, which 162 P4 ⓔ''s was not. The real chain leaves the OWNER as custodian at `confirmed` (delegation makes the owner responsible 0048:135; acceptance changes bookings.runner_id and no custody column 0047:175; the runner becomes custodian only at picked_up 0045:44) and there is no dog_custody_events row yet — asserted, not assumed. Measured in three beats so the source of each answer is unambiguous: inside T−24h the address IS disclosed BY THE MARKETPLACE ARM (which is contract v2 §1''s claim that the negative phase form does not widen the outbound leg, made executable); flipping return_mode off changes nothing, proving that disclosure was not the club arm; and pushed outside the 24h window, with the club arm the only candidate, the same runner gets not_runner');
    else call _fail('crf','P12 pre-handoff is refused', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('crf','P12 pre-handoff is refused', sqlerrm);
  end;

  -- ═══ [P13] MARKETPLACE UNCHANGED — byte-identical behaviour at EVERY status ═══════════════
  -- Two assertions in one sweep, catching opposite failures:
  --   · AGREEMENT with the 0065 transcription — 0129 added nothing and removed nothing.
  --   · the ABSOLUTE expected set (the 3 in-flight states + `confirmed` inside 24h) — because
  --     agreement alone stays green if BOTH definitions broke the same way.
  -- Every status the enum has, including the ones nobody thinks about. Each booking is also
  -- asserted to have no `session_dogs` row AND a NULL `club_session_id`, which is what makes the
  -- club arm structurally unreachable here: `sd.session_id = b.club_session_id` is NULL for every
  -- candidate row, so `exists` is false before any other conjunct is even considered.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', v_mkt_runner::text, false);
    foreach v_st in array v_all loop
      v_cx := t_av_booking(v_mkt_owner, v_mkt_dog, v_mkt_route, v_mkt_runner,
                           now() + interval '2 hours', 5.0, v_st::booking_status);
      update bookings set address_id = v_mkt_addr where id = v_cx;
      if exists (select 1 from session_dogs where booking_id = v_cx)
        then v_bad := v_bad || ' ' || v_st || ':클럽행이 생겼다'; end if;
      if (select club_session_id from bookings where id = v_cx) is not null
        then v_bad := v_bad || ' ' || v_st || ':club_session_id가 NULL이 아니다'; end if;
      v_pre := false; v_live := false; v_n := -1; v_n2 := -1;
      begin select count(*) into v_n  from t163_pre0065(v_cx);           exception when others then v_pre  := true; end;
      begin select count(*) into v_n2 from booking_pickup_address(v_cx); exception when others then v_live := true; end;
      if v_pre <> v_live or v_n <> v_n2 then
        v_bad := v_bad || ' ' || v_st || ':0065(raise=' || v_pre || ',rows=' || v_n
                       || ') vs 0129(raise=' || v_live || ',rows=' || v_n2 || ')';
      end if;
      if v_st in ('runner_enroute','picked_up','active','confirmed') then
        if v_live or v_n2 <> 1 then v_bad := v_bad || ' ' || v_st || ':열려야 하는데 안 열렸다'; end if;
      else
        if not v_live then v_bad := v_bad || ' ' || v_st || ':닫혀야 하는데 열렸다'; end if;
      end if;
      delete from bookings where id = v_cx;
    end loop;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = ''
      then call _pass('crf','P13 marketplace unchanged — across all 16 booking_status values, 0129 and the 0065 transcription agree exactly (raise-or-not AND row count) and both satisfy the ABSOLUTE expected set (the 3 in-flight states + `confirmed` inside 24h give 1 row; the other 12 raise not_runner). Both assertions are needed: agreement alone stays green if the two definitions broke the same way, and the absolute set alone cannot say 「the club arm added nothing」. Each booking is also asserted to have NO session_dogs row and a NULL club_session_id — which is what makes the club arm structurally unreachable here rather than incidentally false: `sd.session_id = b.club_session_id` is NULL for every candidate row, so `exists` is false before any other conjunct is considered. This sweep is also the standing guard that the two transcriptions in this file have not drifted from the gates they copy');
    else call _fail('crf','P13 marketplace unchanged', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    call _fail('crf','P13 marketplace unchanged', sqlerrm);
  end;

  -- ═══ [P14] THE RECREATION'S SEALS — ACL (incl. service_role) · prosecdef · search_path ════
  -- The class 0127 closed, asserted here for THIS function rather than inferred from a sibling's
  -- green. 0129 recreates a definer first defined in 0060, so on any database where the function
  -- was absent the statement is a CREATE and the ACL is whatever the file wrote.
  -- 🔴 `service_role` is new here and is the point: its grant came from Supabase's default
  -- privileges at first CREATE and has ridden `create or replace` preservation ever since. 0129
  -- writes it explicitly; this pin reads the catalog to confirm it landed.
  -- ⚠ SCOPE: this reads the ACL the HARNESS built, applying every migration in order from scratch,
  -- so it structurally CANNOT see the absent-function apply path (98 H9's own text says the same
  -- about itself). 0129's VERIFY ③ covers that path and `check-definer-acl.mjs` covers the source.
  -- Three checks, three different propositions; none is evidence for another.
  begin
    v_bad := '';
    select p.prosecdef, p.proconfig into v_secdef, v_cfg
      from pg_proc p where p.oid = 'booking_pickup_address(uuid)'::regprocedure;
    select has_function_privilege('public',        'booking_pickup_address(uuid)', 'execute'),
           has_function_privilege('anon',          'booking_pickup_address(uuid)', 'execute'),
           has_function_privilege('authenticated', 'booking_pickup_address(uuid)', 'execute'),
           has_function_privilege('service_role',  'booking_pickup_address(uuid)', 'execute')
      into v_pub, v_anon, v_auth, v_svc;
    if not coalesce(v_secdef, false) then v_bad := v_bad || ' secdef=false'; end if;
    if v_cfg is distinct from array['search_path=public, pg_temp']
      then v_bad := v_bad || ' proconfig=[' || coalesce(array_to_string(v_cfg, ','), '∅') || ']'; end if;
    if v_pub  then v_bad := v_bad || ' PUBLIC이 실행 가능'; end if;
    if v_anon then v_bad := v_bad || ' anon이 실행 가능'; end if;
    if not v_auth then v_bad := v_bad || ' authenticated 실행 불가 (과회수 — 모든 러너의 픽업 화면이 죽는다)'; end if;
    if not v_svc  then v_bad := v_bad || ' service_role 실행 불가 (0129가 명시한 grant가 착륙하지 않았다)'; end if;
    -- executed, not only asserted: anon really is refused at the role boundary
    begin
      set local role anon;
      perform 1 from booking_pickup_address((f_home->>'booking')::uuid);
      reset role;
      v_bad := v_bad || ' anon 실제 호출이 통과';
    exception when others then
      reset role;
      if sqlerrm not like '%permission denied%' then v_bad := v_bad || ' anon실호출:' || sqlerrm; end if;
    end;
    if v_bad = ''
      then call _pass('crf','P14 the recreation''s seals — booking_pickup_address is SECURITY DEFINER, its proconfig is EXACTLY {search_path=public, pg_temp} (an ALTER-applied value is wiped by create-or-replace, so its presence right after 0129 is what proves it came from the body), PUBLIC and anon cannot execute, authenticated CAN, **service_role CAN — the grant 0129 writes explicitly instead of inheriting it through preservation** — and anon''s real call at the role boundary is denied. ⚠ SCOPE: this reads the ACL the harness built by applying every migration in order from scratch, so it structurally cannot see the absent-function apply path — 0129''s VERIFY ③ owns that and check-definer-acl.mjs owns the source. Three checks, three propositions, none evidence for another');
    else call _fail('crf','P14 the recreation''s seals', v_bad); end if;
  exception when others then
    reset role;
    call _fail('crf','P14 the recreation''s seals', sqlerrm);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
