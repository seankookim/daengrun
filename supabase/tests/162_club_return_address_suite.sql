-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 162 — 0128 the club return-address arm. Nine pins, each stating its own scope.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Contract: `docs/contracts/club-return-address-arm-contract.md`. Sean, 2026-08-25:
-- 「go ahead with the address fix」.
--
-- ── WHAT 0128 DID, IN ONE SENTENCE ──────────────────────────────────────────────────────────
-- `booking_pickup_address` gained ONE disjunct: the caller is admitted when that pairing's
-- `session_dogs` row is `runner_delegated` + `return_pending` and the caller IS its
-- `custodian_profile_id`. Nothing else about the function moved.
--
-- ── WHY A CUSTODY ARM AND NOT A STATUS LIST — the thing these pins exist to keep true ───────
-- The club sets `custody_phase = 'return_pending'` at `completed` and KEEPS custody with the
-- runner (0045:55-60, 「정산 ≠ 반환」), and both return RPCs require that phase (0045:79, 0045:137).
-- So the club's whole return window sits outside 0065's `active`-only gate BY CONSTRUCTION. The
-- tempting fix — add `completed` to the status list — re-opens every finished booking's pickup
-- address FOREVER to a runner whose custody ended months ago. P4 is the pin that tells the two
-- fixes apart: a status list never closes, and a custody arm closes by itself at `resolved`.
--
-- ── THE THREE PROPOSITIONS, KEPT SEPARATE (CLAUDE.md §Migrations, 2026-08-25) ────────────────
-- "the hole is real", "a pin notices something" and "the fix closes it" are three claims, and a
-- single mutation proves only the middle one. So:
--   · **P1 is the hole**, and it is a DIFFERENTIAL, not an assertion about a stub. `t_cra_pre0128`
--     below is 0065:44-67 transcribed verbatim; P1 ⓐ shows it REFUSES the club return fixture,
--     ⓑ shows the shipped function ADMITS the same fixture, and ⓒ shows the two agree on a
--     marketplace control — which is what makes ⓐ evidence about the pre-0128 GATE rather than
--     about a hand-written function that happens to refuse.
--     ⚠ SCOPE, said plainly: a transcription is not the shipped pre-0128 function. What proves
--     that is M5 in the battery below — pin 2 run against the reverted body — and ⓒ is the
--     standing guard that the transcription has not drifted from the gate it copies.
--   · **P2-P8 are the fix**, each on its own conjunct or its own boundary.
--   · **The battery** is the measurement, at the bottom of this header.
--
-- ── EVERY PIN ASSERTS ITS OWN PRECONDITION ──────────────────────────────────────────────────
-- A gate suite fails in a characteristic way: "it raised not_runner" scores green when the
-- fixture was never in the state the pin claims to be about. So every refusal pin first asserts
-- the `session_dogs` state it is refusing FROM (a wrong-runner pin asserts the row really is
-- `return_pending`; the self-close pin asserts the seal really moved the phase), and P4 asserts
-- the pre-seal ADMISSION before it asserts the post-seal refusal. `t_cra_state()` is the helper
-- that makes that one line instead of five.
--
-- ── THE FIXTURES ARE BUILT THROUGH THE REAL MACHINERY WHERE ONE EXISTS ──────────────────────
-- `return_pending` is never written by hand here: every pairing reaches it by an `update bookings
-- set status = 'completed'` firing `_club_custody_transition_v2` (0045:64) — the same trigger that
-- puts production there. `resolved` likewise comes from two real `session_confirm_return` calls,
-- not from an UPDATE. The ONE place this file writes a state the product cannot reach is P5 ⓑ,
-- which suspends `club_v1_axes_sync` for two statements and restores the row immediately — P5's
-- own header says why that is the honest way to test a second belt rather than a contrivance, and
-- P5 ⓐ measures the reachable truth beside it.
--
-- ── MUTATION BATTERY — PREDICTED, THEN MEASURED. Six runs, 2026-08-26. ──────────────────────
-- Each mutation is applied ALONE, by appending the mutated `create or replace` to the END of a
-- COPY of 0128 in a scratch tree outside the worktree (a full copy of `supabase/`, so the harness
-- resolves `../migrations` inside the copy and touches nothing anyone owns) — never by editing the live file, because
-- another agent may share this tree and a copy-modify-restore is a read-modify-write with a
-- multi-second window. Baseline on that copy: 896/0, identical to the worktree.
--
-- 🔴 TWO OF THE SIX FOUND A HOLE IN THIS SUITE RATHER THAN CONFIRMING A PIN, and both fixes are
-- in the file above. That is the battery doing its job: a prediction that lands is worth less
-- than one that misses, and neither miss was visible by reading the code.
--
--   M1  drop the `custody_phase = 'return_pending'` conjunct
--       PREDICTED  RED = [P4]  (contract §4: "the arm no longer self-closes")
--       MEASURED (first run)  RED = [P4], 895/1 — and the detail named **P4 ⓔ ALONE**, an arm
--                  that did not exist when the battery started. 🔴 THE CONTRACT'S REASONING WAS
--                  WRONG: sealing also moves `custodian_profile_id` to the owner, so a sealed
--                  pairing keeps being refused on the CUSTODIAN conjunct even with the phase
--                  conjunct gone — P4 ⓒ stays green. Without ⓔ this mutation would have reddened
--                  NOTHING and the phase conjunct would have had no pin at all. ⓔ pins the
--                  direction the contract did not think of: the arm must not open at DELEGATION
--                  time.
--       MEASURED (final)  RED = [P6, P4 ⓔ], 894/2 — P6 joins once its wrong-phase probe is
--                  `b_early` (the M4b fix below): with the phase conjunct gone that probe returns
--                  `ok:rows=1` while the other three still refuse, so the four stop agreeing.
--                  Superset, and the two pins name different halves — P4 ⓔ "it opened early",
--                  P6 "and that made the outcomes distinguishable".
--   M2  drop `custodian_profile_id = auth.uid()`
--       PREDICTED  RED = [P3]
--       MEASURED   RED = [P3, P6], 894/2 — benign superset, confirmed on the final suite. P6 reds
--                  because with the custodian conjunct gone the FOREIGN probe (r2's pairing,
--                  itself `return_pending`) returns `ok:rows=1`, so the four probes stop agreeing.
--                  Two pins, one guarantee, two angles. P3's detail is the attack executed:
--                  「같은 세션의 다른 러너가 남의 집 주소를 읽었다」.
--   M3  drop `custody = 'runner_delegated'`
--       PREDICTED  RED = [P5 ⓑ ONLY] — see P5's header for why ⓐ cannot move
--       MEASURED   RED = [P5], 895/1 — exact, via ⓑ.
--   M4  rename the shared refusal string on the club path
--       PREDICTED  RED = [P6]
--       MEASURED   RED = [w3 W2, w3 W3, dong N4, rbd N4, cra P3, P4, P5], 889/7 — **and P6 GREEN,
--                  CORRECTLY.** This mutation renames one string; it does not make two paths
--                  distinguishable, and P6 measures indistinguishability rather than spelling.
--                  Four shipped suites red on the literal, which is what owns the spelling. The
--                  green P6 here is the single best piece of evidence that P6 says what it means,
--                  so the mutation is KEPT rather than replaced.
--   M4b the real oracle break — a distinct string for "your row exists, you are its custodian,
--       the phase is wrong"
--       PREDICTED  RED = [P6]
--       MEASURED (first run, P6 probing the SEALED pairing)  RED = [P4 ⓔ], **P6 GREEN — A MISS.**
--                  🔴 The sealed pairing is not a wrong-phase-as-custodian state: sealing moved
--                  the custodian to the owner, so the caller never reaches the distinguishing
--                  branch. P6's third probe is now `b_early` (delegated, `with_custodian`, caller
--                  IS the custodian) with the sealed pairing kept as a fourth.
--       MEASURED (after the fix)  RED = [P6, P4 ⓔ], 894/2 — exact on P6, whose detail prints the
--                  distinguishable pair: 잘못된국면=[P0001|not_return_pending] against
--                  [P0001|not_runner] on the other three. P4 ⓔ rides along because the same
--                  branch answers it with the new string.
--   M5  revert the body to 0065 — the UNFIXED function
--       PREDICTED  RED = [P2, P4, P7]
--       MEASURED   RED = [P1, P2, P3, P4, P7], 891/5 — superset, and the details are the point:
--                  P1 failed on **ⓑ** (`ⓑ0128raise:not_runner`) while **ⓐ stayed green**. That is
--                  the hole-is-real / fix-closes-it pair measured as two propositions instead of
--                  one: the pre-0128 gate refuses this fixture (ⓐ, true in both runs) and the
--                  shipped function stops admitting it the moment the arm is removed (ⓑ). P3's
--                  red is its POSITIVE control (r2 on its own pairing), not its refusal arm.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
set client_min_messages = warning;

-- ── the pre-0128 gate, transcribed from 0065:44-67 ──────────────────────────────────────────
-- `security invoker` on purpose, and it is NOT a weakening of the transcription: this suite calls
-- both functions from the postgres session with `request.jwt.claim.sub` set, exactly the way
-- 100_wave3 has called `booking_pickup_address` since 0060, and the gate reads `auth.uid()` — not
-- `current_user` — so definer-ness cannot change a single outcome here. Making it a definer WOULD
-- change something else: it would add an unsealed SECURITY DEFINER to the schema, green only
-- because 98 H9 and 99 S1 run BEFORE this file. A pin that is green because of harness ordering is
-- the failure mode this repo names most often, so the twin is an invoker and holds no client ACL.
create or replace function t_cra_pre0128(p_booking uuid)
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
    from bookings b
    join addresses a on a.id = b.address_id
    where b.id = p_booking
      and a.owner_id = b.owner_id;
end $$;
revoke execute on function t_cra_pre0128(uuid) from public, anon, authenticated;

-- One line of state for a pairing, so a precondition assertion is one line and not five.
create or replace function t_cra_state(p_booking uuid) returns text
language sql stable as $$
  select coalesce((select sd.custody || '/' || sd.custody_phase || '/' ||
                          coalesce(sd.custodian_profile_id::text, '∅')
                     from session_dogs sd where sd.booking_id = p_booking), '<no session_dogs row>')
$$;

-- Did this call raise, and with what? Returns '' on success (with the row count appended), or the
-- SQLSTATE + message. P6 compares three of these TO EACH OTHER rather than to a literal — a shared
-- literal would still be shared if all three paths regressed to the same NEW string, and it is the
-- INDISTINGUISHABILITY that is the property, not the spelling.
create or replace function t_cra_probe(p_booking uuid) returns text
language plpgsql stable as $$
declare v_n int;
begin
  select count(*) into v_n from booking_pickup_address(p_booking);
  return 'ok:rows=' || v_n;
exception when others then
  return sqlstate || '|' || sqlerrm;
end $$;

do $$
declare
  oo uuid; zz uuid; rr uuid; r2 uuid;
  dg uuid; dg2 uuid; dg3 uuid; dg4 uuid; dg5 uuid; dg6 uuid; rt uuid;
  ad uuid; ad2 uuid;
  v_club uuid; v_sess uuid;
  b_club uuid; b_other uuid; b_oh uuid; b_null uuid; b_seal uuid; b_early uuid; b_mkt uuid;
  sd_club uuid; sd_other uuid; sd_oh uuid; sd_null uuid; sd_seal uuid; sd_early uuid;
  cx uuid;
  v_n int; v_n2 int; v_bad text; v_st text; v_msg text;
  v_label text; v_addr text; v_detail text; v_lat numeric; v_lng numeric;
  v_a text; v_b text; v_c text; v_d text;
  v_live boolean; v_pre boolean;
  v_cfg text; v_secdef boolean; v_pub boolean; v_anon boolean; v_auth boolean;
  v_all text[] := array['draft','quoted','payment_hold','matching','runner_pending','confirmed',
                        'runner_enroute','picked_up','active','completed','cancelled_owner',
                        'cancelled_runner','expired','no_show','incident_review','refund_pending'];
begin
  -- ═══ FIXTURES ════════════════════════════════════════════════════════════════════════════
  -- The flag is enabled here rather than inherited from suite 50, so this file does not depend on
  -- a sibling's side effect for `session_confirm_return` to be callable (117's precedent).
  update club_flags set enabled = true where name = 'club_delegation_v2';

  oo := t_user('cra_oo', 'owner');  zz := t_user('cra_zz', 'owner');
  rr := t_user('cra_rr', 'runner'); r2 := t_user('cra_r2', 'runner');
  dg  := t_dog(oo, '반환견');   dg2 := t_dog(zz, '남의 반환견');
  dg3 := t_dog(oo, '동반견');   dg4 := t_dog(oo, '주소없는견');  dg5 := t_dog(oo, '봉인견');
  dg6 := t_dog(oo, '아직안돌아온견');
  rt  := t_route('반환 코스');

  -- gate_code_enc is filled ON PURPOSE — so a leak pin measures "structurally absent", never
  -- "the column happened to be empty" (100 W6's rule, transcribed).
  insert into addresses (owner_id, label, addr, detail, gate_code_enc, lat, lng)
    values (oo, '우리 집', '서울 서초구 신반포로 270', '203동 1502호', 'ENC::절대노출금지',
            37.508123, 126.995456)
    returning id into ad;
  insert into addresses (owner_id, label, addr, detail, gate_code_enc, lat, lng)
    values (zz, '남의 집', '서울 강남구 테헤란로 1', '5층', 'ENC::남의것', 37.500001, 127.030001)
    returning id into ad2;

  insert into clubs (name, district) values ('반환 클럽', '반포') returning id into v_club;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
  values (v_club, oo, now() - interval '3 hours', '{"lat":37.51,"lng":127.01}'::jsonb)
  returning id into v_sess;

  -- ⓐ THE TARGET — oo's dog, delegated to rr, in the same club session as ⓑ.
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare, club_session_id, address_id)
  values (oo, dg, rr, rt, 'active', now() - interval '2 hours', 5.0, 9900, 15000, 0, 24900, 9900,
          v_sess, ad)
  returning id into b_club;
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id,
    booking_id, custody, custodian_type, custodian_profile_id)
  values (v_sess, dg, oo, rr, b_club, 'runner_delegated', 'runner', rr) returning id into sd_club;

  -- ⓑ A SECOND PAIRING IN THE SAME SESSION, custodian r2 — P3's attacker is a legitimate runner
  --    standing in the same park, not a stranger. That is the case a session-scoped arm would let
  --    through and a custodian-scoped arm refuses.
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare, club_session_id, address_id)
  values (zz, dg2, r2, rt, 'active', now() - interval '2 hours', 5.0, 9900, 15000, 0, 24900, 9900,
          v_sess, ad2)
  returning id into b_other;
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id,
    booking_id, custody, custodian_type, custodian_profile_id)
  values (v_sess, dg2, zz, r2, b_other, 'runner_delegated', 'runner', r2) returning id into sd_other;

  -- ⓒ AN ACCOMPANIED DOG — `custody = 'owner_handled'`, i.e. never delegated. See P5.
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare, club_session_id, address_id)
  values (oo, dg3, rr, rt, 'active', now() - interval '2 hours', 5.0, 9900, 15000, 0, 24900, 9900,
          v_sess, ad)
  returning id into b_oh;
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id,
    booking_id, custody, custodian_type, custodian_profile_id)
  values (v_sess, dg3, oo, rr, b_oh, 'owner_handled', 'runner', rr) returning id into sd_oh;

  -- ⓓ NO ADDRESS AT ALL — today's production shape (0081:184-186 mints club bookings with
  --    `address_id` NULL). P7's bounded-blast-radius claim.
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare, club_session_id)
  values (oo, dg4, rr, rt, 'active', now() - interval '2 hours', 5.0, 9900, 15000, 0, 24900, 9900,
          v_sess)
  returning id into b_null;
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id,
    booking_id, custody, custodian_type, custodian_profile_id)
  values (v_sess, dg4, oo, rr, b_null, 'runner_delegated', 'runner', rr) returning id into sd_null;

  -- ⓔ P4's stage — sealed later, by two real `session_confirm_return` calls.
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare, club_session_id, address_id)
  values (oo, dg5, rr, rt, 'active', now() - interval '2 hours', 5.0, 9900, 15000, 0, 24900, 9900,
          v_sess, ad)
  returning id into b_seal;
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id,
    booking_id, custody, custodian_type, custodian_profile_id)
  values (v_sess, dg5, oo, rr, b_seal, 'runner_delegated', 'runner', rr) returning id into sd_seal;

  -- ⓕ DELEGATED BUT NOT YET RETURNING — `confirmed` at T+48h, phase `with_custodian`. The other
  --    half of P4: the arm must open at RETURN time, not at DELEGATION time. Without this the
  --    `custody_phase` conjunct has no pin at all (found by running the battery, not by reading).
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare, club_session_id, address_id)
  values (oo, dg6, rr, rt, 'confirmed', now() + interval '48 hours', 5.0, 9900, 15000, 0, 24900,
          9900, v_sess, ad)
  returning id into b_early;
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id,
    booking_id, custody, custodian_type, custodian_profile_id)
  values (v_sess, dg6, oo, rr, b_early, 'runner_delegated', 'runner', rr) returning id into sd_early;

  -- ⓖ A MARKETPLACE booking for rr — no club session, no session_dogs row. P1 ⓒ's control.
  b_mkt := t_av_booking(oo, dg, rt, rr, now() + interval '2 hours', 5.0, 'confirmed');
  update bookings set address_id = ad where id = b_mkt;

  -- THE TRIGGER, not an UPDATE: `completed` is what puts a club pairing into `return_pending`
  -- (0045:55-60). Everything below reads state this transition produced.
  update bookings set status = 'completed'
   where id in (b_club, b_other, b_oh, b_null, b_seal);

  -- Fixture precondition, asserted loudly and once — every pin below is meaningless if this is
  -- wrong, and a suite that discovers it pin by pin reports five confusing reds instead of one.
  begin
    v_bad := '';
    if t_cra_state(b_club) <> 'runner_delegated/return_pending/' || rr::text
      then v_bad := v_bad || ' 대상=' || t_cra_state(b_club); end if;
    if t_cra_state(b_other) <> 'runner_delegated/return_pending/' || r2::text
      then v_bad := v_bad || ' 동세션타러너=' || t_cra_state(b_other); end if;
    -- ⚠ NOT `return_pending/rr` — see P5. `_club_compute_axes` (0048:698-706) returns early for
    --    `owner_handled` and the BEFORE trigger `club_v1_axes_sync` (0040:280-282) writes that
    --    result back over every insert and update, so an accompanied dog's row is NORMALIZED to
    --    owner custody at `with_custodian` no matter what anyone stores. This line is the
    --    measurement, not an expectation that was lowered to fit.
    if t_cra_state(b_oh) <> 'owner_handled/with_custodian/' || oo::text
      then v_bad := v_bad || ' 동반견=' || t_cra_state(b_oh); end if;
    if t_cra_state(b_null) <> 'runner_delegated/return_pending/' || rr::text
      then v_bad := v_bad || ' 주소없음=' || t_cra_state(b_null); end if;
    if t_cra_state(b_seal) <> 'runner_delegated/return_pending/' || rr::text
      then v_bad := v_bad || ' 봉인대상=' || t_cra_state(b_seal); end if;
    -- the one pairing that must NOT have moved: never went to `completed`, so it is still
    -- `with_custodian` — P4 ⓔ's stage.
    if t_cra_state(b_early) <> 'runner_delegated/with_custodian/' || rr::text
      then v_bad := v_bad || ' 인계전=' || t_cra_state(b_early); end if;
    if (select status from bookings where id = b_club) <> 'completed'
      then v_bad := v_bad || ' 대상상태=' || (select status from bookings where id = b_club); end if;
    if v_bad = ''
      then call _pass('cra','P0 픽스처 전제 — 다섯 클럽 페어링이 `completed` 전이 트리거(0045:64)를 통해 각자 도달해야 할 상태에 정확히 도달했다: 위탁 네 건은 return_pending에, 동반견 한 건은 축 정규화기가 강제하는 owner/with_custodian에. custody/custodian 값도 각 핀이 주장하는 그대로다 (손으로 쓴 국면은 이 파일에 없다). ⚠ 이 핀은 형식이 아니다 — 첫 초안이 계약의 동반견 형상을 기대했고 여기서 붉어졌다. 없었다면 P5가 엉뚱한 이유로 초록이었을 것이다');
    else call _fail('cra','P0 픽스처 전제', v_bad); end if;
  exception when others then call _fail('cra','P0 픽스처 전제', sqlerrm);
  end;

  -- ═══ [P1] THE HOLE IS REAL — a differential against 0065's transcribed gate ═══════════════
  -- ⓐ the pre-0128 gate REFUSES the club return fixture. That is the defect, reproduced.
  -- ⓑ the shipped function ADMITS it. Same fixture, same caller, same instant.
  -- ⓒ the two AGREE on a marketplace control — so ⓐ is a fact about the GATE, not about a
  --   hand-written function that happens to refuse everything.
  -- ⚠ SCOPE: a transcription is not the shipped pre-0128 function. M5 is what measures that.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rr::text, false);
    if t_cra_state(b_club) not like 'runner_delegated/return_pending/%'
      then v_bad := v_bad || ' 전제실패:' || t_cra_state(b_club); end if;
    -- ⓐ
    begin
      perform 1 from t_cra_pre0128(b_club);
      v_bad := v_bad || ' ⓐ0065가 허용했다(구멍이 재현되지 않는다)';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' ⓐ' || sqlerrm; end if;
    end;
    -- ⓑ
    begin
      select count(*) into v_n from booking_pickup_address(b_club);
      if v_n <> 1 then v_bad := v_bad || ' ⓑ0128 rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' ⓑ0128raise:' || sqlerrm;
    end;
    -- ⓒ marketplace control — both admit the in-window confirmed booking for its own runner,
    --   both refuse the same booking for a foreign caller.
    begin
      select count(*) into v_n  from t_cra_pre0128(b_mkt);
      select count(*) into v_n2 from booking_pickup_address(b_mkt);
      if v_n <> 1 or v_n2 <> 1 then v_bad := v_bad || ' ⓒ마켓양성 0065=' || v_n || ' 0128=' || v_n2; end if;
    exception when others then v_bad := v_bad || ' ⓒ마켓양성raise:' || sqlerrm;
    end;
    perform set_config('request.jwt.claim.sub', zz::text, false);
    v_pre := false; v_live := false;
    begin perform 1 from t_cra_pre0128(b_mkt); exception when others then v_pre := true; end;
    begin perform 1 from booking_pickup_address(b_mkt); exception when others then v_live := true; end;
    if not (v_pre and v_live) then v_bad := v_bad || ' ⓒ마켓음성 0065거절=' || v_pre || ' 0128거절=' || v_live; end if;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    if v_bad = ''
      then call _pass('cra','P1 구멍이 실재한다 (차등 측정) — 같은 클럽 반환 픽스처에 대해 0065 전사본은 not_runner로 거절하고 0128은 1행을 준다. 두 정의가 마켓플레이스 대조군(진행 창 안 양성 + 타인 음성)에서는 일치하므로, ⓐ의 거절은 「전사가 어긋났다」가 아니라 pre-0128 게이트의 성질이다. ⚠ 범위: 전사본은 배포된 pre-0128 함수가 아니다 — 그건 M5가 측정한다');
    else call _fail('cra','P1 구멍이 실재한다', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', rr::text, false);
    call _fail('cra','P1 구멍이 실재한다', sqlerrm);
  end;

  -- ═══ [P2] THE ARM ADMITS EXACTLY THAT CASE, and the five fields carry real values ═════════
  -- Values, not shapes: a body selecting constant NULLs keeps every key and would pass a key-set
  -- check (0065 W6's recorded near-miss, transcribed).
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rr::text, false);
    select count(*) into v_n from booking_pickup_address(b_club);
    select x.label, x.addr, x.detail, x.lat, x.lng
      into v_label, v_addr, v_detail, v_lat, v_lng
      from booking_pickup_address(b_club) x;
    if v_n <> 1 then v_bad := v_bad || ' rows=' || v_n; end if;
    if v_label is distinct from '우리 집' then v_bad := v_bad || ' label=' || coalesce(v_label,'∅'); end if;
    if v_addr is distinct from '서울 서초구 신반포로 270' then v_bad := v_bad || ' addr=' || coalesce(v_addr,'∅'); end if;
    if v_detail is distinct from '203동 1502호' then v_bad := v_bad || ' detail=' || coalesce(v_detail,'∅'); end if;
    if v_lat is distinct from 37.508123 or v_lng is distinct from 126.995456
      then v_bad := v_bad || ' 좌표=' || coalesce(v_lat::text,'∅') || ',' || coalesce(v_lng::text,'∅'); end if;
    -- the leak surface did not widen with the arm
    select count(*) into v_n2 from (
      select jsonb_object_keys(j) as k from (
        select to_jsonb(x) as j from booking_pickup_address(b_club) x limit 1) s) t
     where k ~* 'gate|code|enc|owner|phone|club|custody|session';
    if v_n2 <> 0 then v_bad := v_bad || ' 누수키=' || v_n2; end if;
    if v_bad = ''
      then call _pass('cra','P2 팔이 정확히 그 경우를 허용한다 — `completed`/`return_pending`이고 자기가 custodian인 클럽 러너가 1행과 label/addr/detail/lat/lng 실값을 받는다 (형상이 아니라 값으로 단언 — 상수 NULL 본문은 키 검사만으로는 초록이다). gate_code_enc는 채워져 있는데도 반환 키에 자리 자체가 없다');
    else call _fail('cra','P2 팔이 그 경우를 허용한다', v_bad); end if;
  exception when others then call _fail('cra','P2 팔이 그 경우를 허용한다', sqlerrm);
  end;

  -- ═══ [P3] A DIFFERENT RUNNER IN THE SAME SESSION AT THE SAME PHASE → not_runner ═══════════
  -- The `custodian_profile_id = auth.uid()` conjunct. Without it the arm becomes session-scoped,
  -- and every runner at the meetup reads every owner's home address.
  begin
    v_bad := '';
    if t_cra_state(b_other) not like 'runner_delegated/return_pending/%'
      then v_bad := v_bad || ' 전제실패(공격자 자신의 페어링이 return_pending이 아니다):' || t_cra_state(b_other); end if;
    if (select runner_id from bookings where id = b_club) = r2
      then v_bad := v_bad || ' 전제실패: r2가 대상 부킹의 러너다'; end if;
    perform set_config('request.jwt.claim.sub', r2::text, false);
    begin
      perform 1 from booking_pickup_address(b_club);
      v_bad := v_bad || ' 예외없음(같은 세션의 다른 러너가 남의 집 주소를 읽었다)';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' ' || sqlerrm; end if;
    end;
    -- positive control: r2 IS admitted to its OWN pairing, so the refusal above is scope and not
    -- a broken fixture / a runner who cannot read anything.
    begin
      select count(*) into v_n from booking_pickup_address(b_other);
      if v_n <> 1 then v_bad := v_bad || ' 대조군(자기 페어링) rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' 대조군raise:' || sqlerrm;
    end;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    if v_bad = ''
      then call _pass('cra','P3 같은 세션·같은 국면의 다른 러너는 거절 — custodian이 아닌 러너는 not_runner를 받고(팔이 세션 범위였다면 미트업의 모든 러너가 모든 보호자의 집 주소를 읽는다), 같은 러너가 자기 페어링에서는 1행을 받는 양성 대조가 붙어 있어 거절이 「아무것도 못 읽는 러너」로 오독되지 않는다');
    else call _fail('cra','P3 같은 세션의 다른 러너', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', rr::text, false);
    call _fail('cra','P3 같은 세션의 다른 러너', sqlerrm);
  end;

  -- ═══ [P4] IT SELF-CLOSES — the property that makes this a custody arm and not a status list ═
  -- Asserted, never assumed, and in three beats: admitted BEFORE the seal · the seal really moved
  -- the phase to `resolved` (through two real `session_confirm_return` calls, not an UPDATE) ·
  -- refused AFTER. A status-list fix passes the first beat and fails the third forever.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rr::text, false);
    -- ⓐ before
    begin
      select count(*) into v_n from booking_pickup_address(b_seal);
      if v_n <> 1 then v_bad := v_bad || ' ⓐ봉인 전 rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' ⓐ봉인 전 raise:' || sqlerrm;
    end;
    -- ⓑ the real seal — both sides, the way 0045 requires
    perform set_config('request.jwt.claim.sub', oo::text, false);
    perform session_confirm_return(sd_seal);
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform session_confirm_return(sd_seal);
    if t_cra_state(b_seal) <> 'runner_delegated/resolved/' || oo::text
      then v_bad := v_bad || ' ⓑ봉인 후 상태=' || t_cra_state(b_seal); end if;
    -- ⓒ after
    begin
      perform 1 from booking_pickup_address(b_seal);
      v_bad := v_bad || ' ⓒ봉인 뒤에도 주소가 열려 있다 (팔이 자기폐쇄하지 않는다)';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' ⓒ' || sqlerrm; end if;
    end;
    -- ⓓ the booking is still `completed` — so the refusal is the PHASE closing, not the status
    --   moving. Without this arm a reader cannot tell the self-close from a state change.
    if (select status from bookings where id = b_seal) <> 'completed'
      then v_bad := v_bad || ' ⓓ부킹 상태가 completed가 아니다=' || (select status from bookings where id = b_seal); end if;
    -- ⓔ THE OTHER HALF OF THE SAME CONJUNCT — the arm must open at RETURN time, not at DELEGATION
    --   time. A dog delegated to rr but not yet handed over (booking `confirmed` at T+48h, phase
    --   `with_custodian`) is refused, exactly as the marketplace refuses a booking outside its 24h
    --   window. 🔴 This arm exists because the battery measured that WITHOUT it, dropping the
    --   `custody_phase` conjunct (M1) reddened NOTHING: after the seal `session_confirm_return`
    --   also moves `custodian_profile_id` to the owner, so ⓒ keeps refusing on the custodian
    --   conjunct alone and the phase conjunct had no pin of its own. Found by running the
    --   mutation, not by reading the code.
    if t_cra_state(b_early) <> 'runner_delegated/with_custodian/' || rr::text
      then v_bad := v_bad || ' ⓔ전제실패:' || t_cra_state(b_early); end if;
    begin
      perform 1 from booking_pickup_address(b_early);
      v_bad := v_bad || ' ⓔ아직 인계도 안 된 위탁견의 주소가 열렸다 (팔이 반환 시점이 아니라 위탁 시점에 열린다)';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' ⓔ' || sqlerrm; end if;
    end;
    if v_bad = ''
      then call _pass('cra','P4 팔은 반환 시점에만 열리고 스스로 닫힌다 — ⓐ 봉인 전 1행 ⟶ ⓑ 양측 `session_confirm_return` 실호출로 국면이 resolved ⟶ ⓒ 같은 러너·같은 부킹이 not_runner이고 ⓓ 부킹은 여전히 completed이므로 닫힌 것은 상태가 아니라 커스터디 국면이다 (스윕도, 만료 잡도, 지워야 할 플래그도 없다 — `completed`를 상태 목록에 더하는 수정은 ⓐ를 통과하고 ⓒ에서 영원히 실패한다). ⓔ 반대편: 아직 인계 전인 위탁 페어링(confirmed T+48h·with_custodian)은 거절된다 — 🔴 이 팔이 없었을 때 M1(custody_phase 연언 제거)은 아무것도 붉히지 못했다. 봉인이 custodian_profile_id도 보호자로 옮기기 때문에 ⓒ는 custodian 연언만으로 계속 거절했고, 국면 연언에는 자기 핀이 없었다. 코드를 읽어서가 아니라 뮤테이션을 돌려서 찾았다');
    else call _fail('cra','P4 팔은 스스로 닫힌다', v_bad); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', rr::text, false);
    call _fail('cra','P4 팔은 스스로 닫힌다', sqlerrm);
  end;

  -- ═══ [P5] AN ACCOMPANIED DOG (custody = 'owner_handled') → not_runner ═════════════════════
  -- 🔴 MEASURED CORRECTION TO THE CONTRACT (2026-08-26). §3 pin 5 and §4 M3 were written as though
  -- an `owner_handled` row could sit at `return_pending` with a runner custodian. IT CANNOT, and
  -- the reason is upstream of 0128: `_club_compute_axes` (0048:698-706, inherited from 0040:180)
  -- RETURNS EARLY for `owner_handled` with `custodian_type='owner'`,
  -- `custodian_profile_id = owner_profile_id`, `custody_phase='with_custodian'` — and
  -- `club_v1_axes_sync` (0040:280-282) is a BEFORE INSERT OR UPDATE trigger that writes that
  -- result back over the row on every write. The first draft of this suite asserted the
  -- contract's shape and P0 caught it; the shape is unreachable through the table.
  --
  -- That makes the `custody = 'runner_delegated'` conjunct a SECOND BELT, not the primary guard —
  -- so the pin is written in two arms that measure two different things, and only ⓑ can redden
  -- under M3:
  --   ⓐ **the reachable product truth**, through the real machinery: an accompanied dog's pairing
  --     normalizes to owner custody, so the session's runner — who IS this booking's `runner_id`
  --     — gets `not_runner`. This arm is green with or without the conjunct, and says so.
  --   ⓑ **the conjunct's own job**, with the normalizer suspended for exactly two statements.
  --     Suspending `club_v1_axes_sync` is not a contrivance: it is what a dropped trigger, a
  --     `disable trigger`, or a future rewrite of `_club_compute_axes` looks like from the arm's
  --     point of view, and the arm must hold without depending on another trigger staying
  --     installed. The row is re-normalized immediately afterwards so nothing downstream inherits
  --     a planted state.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rr::text, false);
    -- ⓐ reachable truth
    if t_cra_state(b_oh) <> 'owner_handled/with_custodian/' || oo::text
      then v_bad := v_bad || ' ⓐ전제실패:' || t_cra_state(b_oh); end if;
    if (select runner_id from bookings where id = b_oh) is distinct from rr
      then v_bad := v_bad || ' ⓐ전제실패: rr이 이 부킹의 러너가 아니다'; end if;
    begin
      perform 1 from booking_pickup_address(b_oh);
      v_bad := v_bad || ' ⓐ예외없음(동반견 부킹의 러너에게 주소가 열렸다)';
    exception when others then
      if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' ⓐ' || sqlerrm; end if;
    end;
    -- ⓑ the conjunct, with the normalizer suspended
    begin
      alter table session_dogs disable trigger club_v1_axes_sync;
      update session_dogs set custody = 'owner_handled', custodian_type = 'runner',
             custodian_profile_id = rr, custody_phase = 'return_pending'
       where id = sd_oh;
      if t_cra_state(b_oh) <> 'owner_handled/return_pending/' || rr::text
        then v_bad := v_bad || ' ⓑ심기 실패:' || t_cra_state(b_oh); end if;
      begin
        perform 1 from booking_pickup_address(b_oh);
        v_bad := v_bad || ' ⓑ예외없음(위탁된 적 없는 개의 주소가 열렸다 — custody 연언이 죽었다)';
      exception when others then
        if sqlerrm not like '%not_runner%' then v_bad := v_bad || ' ⓑ' || sqlerrm; end if;
      end;
    exception when others then v_bad := v_bad || ' ⓑ' || sqlerrm;
    end;
    -- restore, unconditionally: re-enable first, then one write so the normalizer rewrites the row
    begin
      alter table session_dogs enable trigger club_v1_axes_sync;
      update session_dogs set custody = 'owner_handled' where id = sd_oh;
      if t_cra_state(b_oh) <> 'owner_handled/with_custodian/' || oo::text
        then v_bad := v_bad || ' 복원 실패:' || t_cra_state(b_oh); end if;
    exception when others then v_bad := v_bad || ' 복원:' || sqlerrm;
    end;
    if v_bad = ''
      then call _pass('cra','P5 위탁되지 않은 개는 거절 — ⓐ 도달 가능한 진실: `owner_handled` 페어링은 축 정규화기(0048:698-706 + 0040:280-282의 BEFORE 트리거)에 의해 항상 보호자 커스터디·with_custodian로 정규화되므로, 그 부킹의 러너조차 not_runner를 받는다. ⓑ 연언 자체의 몫: 정규화기를 두 문장 동안 끄고 (owner_handled + 러너 custodian + return_pending) 행을 실제로 심어도 여전히 not_runner다 — 개를 넘겨받은 적 없는 러너에게 목적지를 빚진 적이 없기 때문이고, 이 팔은 다른 트리거가 설치돼 있다는 사실에 의존하지 않는다. 🔴 계약 §3 핀5·§4 M3은 이 행 모양이 도달 가능하다고 전제했으나 아니다(P0가 잡았다) — `custody` 연언은 1차 가드가 아니라 두 번째 벨트이고, M3은 ⓑ로만 붉어진다. 행은 즉시 재정규화되어 아래 어떤 것도 심어진 상태를 물려받지 않는다');
    else call _fail('cra','P5 위탁되지 않은 개', v_bad); end if;
  exception when others then
    begin alter table session_dogs enable trigger club_v1_axes_sync; exception when others then null; end;
    call _fail('cra','P5 위탁되지 않은 개', sqlerrm);
  end;

  -- ═══ [P6] ORACLE PRESERVATION — the three refusals are indistinguishable FROM EACH OTHER ═══
  -- 0054:73's doctrine: the moment "absent" and "exists but you may not" differ, an attacker
  -- sweeps uuids and learns which bookings are real. The arm is a disjunct inside the SAME
  -- boolean, so a wrong-phase caller cannot be told apart — this pin measures that rather than
  -- trusting it. Compared TO EACH OTHER, not to a literal: three paths that all regressed to the
  -- same NEW string would still be indistinguishable, and indistinguishability is the property.
  -- (0128's VERIFY ④ owns the complementary half — that the body has exactly ONE raise site.)
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rr::text, false);
    if t_cra_state(b_early) <> 'runner_delegated/with_custodian/' || rr::text
      then v_bad := v_bad || ' 전제실패(국면 프로브가 with_custodian/custodian=rr이 아니다):' || t_cra_state(b_early); end if;
    if t_cra_state(b_seal) not like '%/resolved/%'
      then v_bad := v_bad || ' 전제실패(봉인 프로브가 resolved가 아니다 — P4가 먼저 돌아야 한다):' || t_cra_state(b_seal); end if;
    v_a := t_cra_probe(gen_random_uuid());          -- absent
    v_b := t_cra_probe(b_other);                    -- foreign (r2's pairing, rr is not its runner)
    -- 🔴 THE WRONG-PHASE PROBE IS `b_early`, NOT `b_seal`, AND THE DIFFERENCE IS THE WHOLE PIN.
    -- The first draft probed the SEALED pairing and M4b — an implementation that raises a distinct
    -- string for "your row exists, you are its custodian, the phase is wrong" — LEFT P6 GREEN.
    -- Sealing moves `custodian_profile_id` to the owner, so after it rr is no longer the custodian
    -- and never reaches the distinguishing branch at all. The state an oracle-breaking body can
    -- actually tell apart is the one where the caller IS the custodian and only the PHASE is
    -- wrong, which is `b_early` (delegated, `with_custodian`, booking `confirmed` at T+48h).
    -- `b_seal` is kept as a fourth probe rather than dropped: post-seal is its own path.
    v_c := t_cra_probe(b_early);                    -- exists, rr IS runner AND custodian, phase wrong
    v_d := t_cra_probe(b_seal);                     -- exists, sealed, custody has moved to the owner
    if v_a like 'ok:%' or v_b like 'ok:%' or v_c like 'ok:%' or v_d like 'ok:%'
      then v_bad := v_bad || ' 넷 중 하나가 통과했다'; end if;
    if not (v_a = v_b and v_b = v_c and v_c = v_d)
      then v_bad := v_bad || ' 부재=[' || v_a || '] 타인=[' || v_b || '] 잘못된국면=[' || v_c
                          || '] 봉인후=[' || v_d || ']'; end if;
    if v_bad = ''
      then call _pass('cra','P6 오라클 보존 — 부재 부킹·타인 부킹·「존재하고 내가 러너이자 custodian인데 국면만 틀린」 부킹·봉인 뒤 부킹, 네 경로의 SQLSTATE+메시지 쌍이 서로 바이트 동일하다. 리터럴과 비교하지 않는다: 네 경로가 같은 새 문자열로 함께 회귀해도 구별불가라는 성질은 유지되고, 성질은 철자가 아니라 구별불가성이다(M4가 그것을 측정했다 — 공유 문자열의 개명은 shipped 핀 넷을 붉히지만 P6는 옳게 초록으로 남는다). 🔴 세 번째 프로브가 봉인된 페어링이던 첫 초안에서 M4b는 P6를 초록으로 통과했다: 봉인이 custodian을 보호자로 옮기므로 호출자는 구별 분기에 도달조차 못 한다. 0128 팔은 같은 불리언 안의 or이지 두 번째 raise 지점이 아니다');
    else call _fail('cra','P6 오라클 보존', v_bad); end if;
  exception when others then call _fail('cra','P6 오라클 보존', sqlerrm);
  end;

  -- ═══ [P7] address_id NULL at return_pending → 0 ROWS, not an error ════════════════════════
  -- The bounded-blast-radius claim, and today's actual production shape. The gate opens; the JOIN
  -- decides there is nothing to hand over. 0 rows and an exception are different signals to the
  -- client (「미지정 — 채팅으로 물어보기」 vs 「불러오지 못했어요 — 재시도」), and collapsing them
  -- leaves a runner pressing retry forever (0060's W4 reasoning, unchanged).
  begin
    v_bad := '';
    if t_cra_state(b_null) not like 'runner_delegated/return_pending/%'
      then v_bad := v_bad || ' 전제실패:' || t_cra_state(b_null); end if;
    if (select address_id from bookings where id = b_null) is not null
      then v_bad := v_bad || ' 전제실패: address_id가 NULL이 아니다'; end if;
    perform set_config('request.jwt.claim.sub', rr::text, false);
    begin
      select count(*) into v_n from booking_pickup_address(b_null);
      if v_n <> 0 then v_bad := v_bad || ' rows=' || v_n; end if;
    exception when others then v_bad := v_bad || ' raise:' || sqlerrm;
    end;
    if v_bad = ''
      then call _pass('cra','P7 주소 없는 클럽 페어링 — 오늘의 실제 운영 형상(0081:184-186은 address_id 없이 클럽 부킹을 만든다)에서 return_pending인 custodian이 호출하면 예외가 아니라 0행이다. 게이트는 열리고, 넘길 것이 없다고 결정하는 것은 JOIN이다 — 그래서 현장 반환 페어링은 애초에 가진 적 없는 주소를 흘릴 수 없다');
    else call _fail('cra','P7 주소 없는 클럽 페어링', v_bad); end if;
  exception when others then call _fail('cra','P7 주소 없는 클럽 페어링', sqlerrm);
  end;

  -- ═══ [P8] MARKETPLACE CONTROL — byte-identical behaviour at EVERY status ══════════════════
  -- Two assertions in one sweep, and they catch opposite failures:
  --   · AGREEMENT with the 0065 transcription — the arm added nothing and removed nothing.
  --   · the ABSOLUTE expected set (the 3 in-flight states + `confirmed` inside 24h) — because
  --     agreement alone stays green if BOTH definitions broke the same way.
  -- Every status the enum has, including the ones nobody thinks about.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rr::text, false);
    foreach v_st in array v_all loop
      cx := t_av_booking(oo, dg, rt, rr, now() + interval '2 hours', 5.0, v_st::booking_status);
      update bookings set address_id = ad where id = cx;
      if exists (select 1 from session_dogs where booking_id = cx)
        then v_bad := v_bad || ' ' || v_st || ':클럽행이 생겼다'; end if;
      v_pre := false; v_live := false; v_n := -1; v_n2 := -1;
      begin select count(*) into v_n  from t_cra_pre0128(cx);        exception when others then v_pre  := true; end;
      begin select count(*) into v_n2 from booking_pickup_address(cx); exception when others then v_live := true; end;
      if v_pre <> v_live or v_n <> v_n2 then
        v_bad := v_bad || ' ' || v_st || ':0065(raise=' || v_pre || ',rows=' || v_n
                       || ') vs 0128(raise=' || v_live || ',rows=' || v_n2 || ')';
      end if;
      if v_st in ('runner_enroute','picked_up','active','confirmed') then
        if v_live or v_n2 <> 1 then v_bad := v_bad || ' ' || v_st || ':열려야 하는데 안 열렸다'; end if;
      else
        if not v_live then v_bad := v_bad || ' ' || v_st || ':닫혀야 하는데 열렸다'; end if;
      end if;
      delete from bookings where id = cx;
    end loop;
    if v_bad = ''
      then call _pass('cra','P8 마켓플레이스 무손상 — booking_status 16개 값 전부에서 0128과 0065 전사본의 결과(예외 여부 + 행 수)가 완전히 일치하고, 동시에 절대 기대집합(진행 중 3종 + 24h 안 confirmed만 1행, 나머지 12종은 not_runner)도 만족한다. 두 단언이 함께 있어야 하는 이유: 일치만 보면 두 정의가 같은 방향으로 망가져도 초록이고, 절대값만 보면 「팔이 마켓에 아무것도 더하지 않았다」를 말하지 못한다. 각 부킹에 session_dogs 행이 없음도 함께 단언하므로 팔은 구조적으로 도달 불가다');
    else call _fail('cra','P8 마켓플레이스 무손상', v_bad); end if;
  exception when others then call _fail('cra','P8 마켓플레이스 무손상', sqlerrm);
  end;

  -- ═══ [P9] THE RECREATION'S SEALS — ACL · prosecdef · in-body search_path ══════════════════
  -- The class 0127 closed this afternoon, asserted here for THIS function rather than inferred
  -- from a sibling's green. 0128 recreates a definer first defined in 0060, so on any database
  -- where the function was absent the statement is a CREATE and the ACL is whatever the file
  -- wrote — which is why the revoke/grant pair is in 0128 and why this pin reads the catalog.
  -- ⚠ SCOPE: this reads the ACL the HARNESS built, applying every migration in order from
  -- scratch, so it structurally cannot see the absent-function apply path (98 H9's own text says
  -- the same about itself). 0128's VERIFY ③ is what covers that path, and `check-definer-acl.mjs`
  -- covers the source. Three checks, three different propositions; none is evidence for another.
  begin
    v_bad := '';
    select p.prosecdef, coalesce(array_to_string(p.proconfig, ','), '')
      into v_secdef, v_cfg
      from pg_proc p
     where p.proname = 'booking_pickup_address' and p.pronamespace = 'public'::regnamespace;
    select has_function_privilege('public',        'booking_pickup_address(uuid)', 'execute'),
           has_function_privilege('anon',          'booking_pickup_address(uuid)', 'execute'),
           has_function_privilege('authenticated', 'booking_pickup_address(uuid)', 'execute')
      into v_pub, v_anon, v_auth;
    if not coalesce(v_secdef, false) then v_bad := v_bad || ' secdef=false'; end if;
    if v_cfg not like '%search_path=%' or v_cfg not like '%pg_temp%'
      then v_bad := v_bad || ' proconfig=[' || v_cfg || ']'; end if;
    if v_pub  then v_bad := v_bad || ' PUBLIC이 실행 가능'; end if;
    if v_anon then v_bad := v_bad || ' anon이 실행 가능'; end if;
    if not v_auth then v_bad := v_bad || ' authenticated가 실행 불가(과회수 — 모든 러너의 픽업 화면이 죽는다)'; end if;
    -- executed, not only asserted: anon really is refused at the role boundary
    begin
      set local role anon;
      perform 1 from booking_pickup_address(b_club);
      reset role;
      v_bad := v_bad || ' anon 실제 호출이 통과';
    exception when others then
      reset role;
      if sqlerrm not like '%permission denied%' then v_bad := v_bad || ' anon실호출:' || sqlerrm; end if;
    end;
    if v_bad = ''
      then call _pass('cra','P9 재생성의 봉인 — 0128이 되살린 booking_pickup_address는 security definer이고 search_path가 본문에 박혀 있으며(ALTER로 준 값은 create or replace가 지운다), PUBLIC·anon 실행 불가·authenticated 실행 가능이 카탈로그에서 확인되고 anon의 실제 호출은 permission denied로 막힌다. ⚠ 범위: 이 핀은 하네스가 순서대로 쌓은 스키마의 ACL만 본다 — 함수가 없는 DB에 적용되는 경로는 0128의 VERIFY ③이, 소스는 check-definer-acl.mjs가 본다. 셋은 서로의 증거가 아니다');
    else call _fail('cra','P9 재생성의 봉인', v_bad); end if;
  exception when others then
    reset role;
    call _fail('cra','P9 재생성의 봉인', sqlerrm);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
