-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 154 — 0119 맹견 gate: the field, the booking-time refusal, and the ways it must NOT fire
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Every pin is written BOTH ways. This repo's recorded failure is the one-sided gate pin — a
-- fixture that only exercises the side the fix already allowed stays green when the fix is deleted
-- (110 S1's header records it twice; 146 D-11/D-12/D-14 exist because "11/14 green with the
-- feature dead" was MEASURED here). A gate that refuses everything is not a working gate, so every
-- refusal below is paired with the legitimate caller that must still get through:
--
--   G1  refusal on the booking path        ⟷ an ordinary marketplace booking still inserts
--   G2  undeclared/absent dog refused      ⟷ the same dog books the moment the owner answers
--   G3  breed screen catches a contradiction ⟷ ordinary breeds pass, and the screen never re-opens
--   G4  club delegation refused at APPLY   ⟷ 동반 참여(owner_handled) still works — the remedy
--                                            §C's third token names has to actually exist
--   G5  a dog MOVING into custody refused  ⟷ a dog ALREADY in custody still comes home
--   G6  a 맹견 series is skipped           ⟷ everybody else's recurring booking is still generated
--   G7  the declaration latches            ⟷ correcting upward, and un-answering, still work
--   G8  the pair constraint refuses halves ⟷ both complete shapes are accepted
--   G9  the doors themselves
--   G10 late declaration re-gates UPDATE   ⟷ picked_up/active marketplace return stays open
--   G11 check→INSERT declaration race      ⟷ every other recurring series still generates,
--                                            with one aggregate WARNING rather than N
--   G12 DELETE cannot erase the latch       ⟷ ordinary DELETE and the ops escape hatch stay open
--
-- ─── PREDICTED MUTATION MAP — ⚠ PREDICTIONS, NOT MEASUREMENTS ─────────────────────────────────
-- ⚠ **THIS SESSION DID NOT RUN THE HARNESS.** Parallel harness runs braid on one postmaster and
-- produce phantom reds, so a dedicated agent measures after this slice. Everything below is what
-- the author expects each mutation to redden, written down BEFORE measurement so the measurement
-- can contradict it. Read it as a hypothesis to be falsified, never as a result.
--   0119 §D delete the `bookings_dangerous_dog` trigger        → RED = [G1, G2, G3, G6?]
--        (G6 only if the belt is also gone — see below; with §E intact G6 stays green, which is
--         itself the statement that the belt and the trigger are different objects)
--   0119 §D delete the `session_dogs_dangerous_dog` trigger    → RED = [G4]
--   0119 §D delete `session_dogs_dangerous_dog_move`           → RED = [G5 ⓑ]
--   0119 §D drop the `_move` trigger's movement condition
--        (i.e. re-merge it into `before insert or update`)     → RED = [G5 ⓐ]  ← the trap arm
--   0119 §D drop the `owner_handled` exemption from the WHEN   → RED = [G4 ⓑ] (and the migration's
--                                                                own VERIFY block refuses first)
--   0119 §C rewrite ⓑ as `<> 'declared_dangerous'`             → RED = [G2 ⓐ, G2 ⓒ]
--        ← THE FAIL-OPEN THIS FILE EXISTS FOR. Every other pin stays green under it.
--   0119 §C drop the `coalesce(…, false)` around the match     → RED = [G2 ⓒ]
--   0119 §C delete the ⓒ breed arm                             → RED = [G3 ⓐ]
--   0119 §B `_breed_reads_as_dangerous` loses its `coalesce`   → RED = [G2 ⓔ]
--        (breed IS NULL ⇒ NULL ⇒ `if NULL` never fires… in the SAFE direction here, so the arm
--         that catches it is the POSITIVE one: a nameless dog must still be bookable)
--   0119 §E delete the ⓕ belt from generate_recurring_bookings → RED = [G6]  (the sweep raises and
--        BOTH series get nothing — 0116 §C's shape, reproduced)
--   0119 §F delete the latch                                   → RED = [G7 ⓐ]
--   0119 §F delete the ⓑ stamp discipline                      → RED = [G7 ⓓ, G7 ⓔ]
--   0119 §A delete the pair CHECK constraint                   → RED = [G8]
--   grant execute on dog_custody_gate to authenticated         → RED = [G9]
--
-- ─── FIX-FIRST ROUND — PREDICTED MUTATIONS, NOT MEASUREMENTS ───────────────────────────────────
-- No harness or test was run while authoring this round. PREDICTED post-fix clean count: 743/0
-- (the previously measured 740/0 plus G10, G11 and G12). Every red set below is PREDICTED.
--   F1 post-apply DROP `bookings_dangerous_dog_move`             → RED = [G9, G10 late-accept]
--   F1 delete its old picked_up/active exemption                → migration VERIFY aborts;
--        if VERIFY is bypassed, RED = [G10 real homeward arm]
--   F2 delete only the per-row INSERT exception handler         → RED = [G11] alone
--   F2 replace its three-token filter with catch-all continue   → RED = [G11 unknown-P0001 arm]
--   F5 drop owner_handled from the session UPDATE trigger WHEN  → migration VERIFY aborts;
--        if VERIFY is bypassed, RED = [G5 real return-home arm]
--   F5 drop owner_handled from the session INSERT trigger WHEN  → migration VERIFY aborts
--        (the predecessor mutation applied; this one must not)
--   F4 post-apply DROP `dogs_dangerous_delete`                   → RED = [G9, G12 auth-delete]
--   F4 remove its current_user scope so it blocks ops too       → RED = [G12 ops arm] alone
--   F7 restore a refused-series WARNING inside the loop         → RED = [G11 warning-shape arm]
-- PREDICTED G11 runtime shape: its clean series has 1 booking, each of 3 refused series has 0, and one
-- aggregate WARNING naming count=3 plus 3 distinct dog ids. These are predictions for the measuring
-- agent to falsify, not observed counts.
--
-- ─── Two fixture facts that are load-bearing ────────────────────────────────────────────────
--  ① **The positive-control booking carries `runner_id = NULL`, deliberately.** That is the real
--     marketplace shape (`create-booking-hold` writes a literal null, 0111 §0d) AND it is the
--     exact NULL that caught 0116 §D's first draft fail-open. A gate fixture in this repo carries
--     a NULL in a party column or it is not a gate fixture.
--  ② **G4's two arms are ORDERED and the order is the pin.** `session_delegate_dog` refuses
--     `already_registered` if a `session_dogs` row exists, so the 동반 RSVP must come SECOND. Run
--     them the other way round and ⓐ would be green for the wrong reason — refused by the
--     duplicate check, not by the 맹견 gate — which is the vacuity class this suite is written
--     against.
-- ─── MEASURED 2026-08-24 (announcer session, main loop) — 16 full harness runs ─────────────────
-- FIRST-EVER measurement of this slice. Baseline 740/0 (731 base + G1~G9). Final clean 740/0,
-- tree byte-identical to tip 2371502. Every mutation grep/py-proven applied before its run.
--   M1  drop bookings trigger      → 735/5 RED=[G1,G2,G3,G4,G9]   predicted [G1,G2,G3,G6?]
--       ⚠ miss(benign): G9 co-fires on ANY door deletion (count 4→3); G4's fixture couples to
--       this trigger (its 동반 arm books through bookings). G6 stayed GREEN with §E intact —
--       the author's own hypothesis, CONFIRMED: the belt and the trigger are different objects.
--   M2  drop session trigger       → 738/2 RED=[G4,G9]            predicted [G4]      (+G9 count)
--   M3  drop _move trigger         → 738/2 RED=[G5,G9]            predicted [G5 ⓑ]    (+G9 count)
--   M4  drop _move's movement cond → MIGRATION ABORTS at 0119's own VERIFY; zero suites run.
--       predicted [G5 ⓐ]. Guard STRONGER than mapped — and therefore G5 ⓐ's recorded red set is
--       UNREACHABLE by this mutation (the 0118 P11-ARM2 class). Do not cite [G5 ⓐ] as measured.
--   M5  drop owner_handled WHEN    → migration APPLIES (⚠ the VERIFY does NOT refuse, contrary
--       to the map AND to the verify block's own stated purpose at 0119:630-632), then suite 154
--       ABORTS as PARSE/EXEC FAILED — the 동반 fixture hits the unexempted gate and the DO block
--       dies. Red either way, but LOUD-UGLY not LOUD-NAMED, and the verify's coverage claim is
--       false for this trigger. → follow-up for the review round: teach the VERIFY the plain
--       trigger's WHEN, the way it already knows _move's.
--   M6  §C fail-open rewrite       → 739/1 RED=[G2 ⓐ+ⓒ] alone     EXACT — the headline mutation
--   M7  drop outer coalesce        → 739/1 RED=[G2 ⓒ] alone       EXACT
--   M8  delete breed arm           → 739/1 RED=[G3 ⓐ] alone       EXACT
--   M9  §B drop coalesce           → 740/0 GREEN. Prediction REFUTED — and classified, not
--       shrugged at: _breed_reads_as_dangerous has exactly ONE call site (0119:262) and it is
--       the POSITIVE form, where NULL and false behave identically. The mutation is a semantic
--       no-op; no behavioral pin can red on it. The coalesce is defense-in-depth for a future
--       NEGATED caller. G2 ⓔ is not theatre — its property (nameless dog bookable) holds.
--   M10 delete §E belt             → 739/1 RED=[G6] alone, both arms EXACT
--   M11 delete §F latch            → 739/1 RED=[G7 ⓐ] alone       EXACT
--   M12 delete §F stamp discipline → 739/1 RED=[G7 ⓓⓔ] alone      EXACT
--   M13 delete §A pair CHECK       → 739/1 RED=[G8] alone, all 3 halves EXACT
--   M14 grant gate to authenticated→ 739/1 RED=[G9] alone         EXACT
-- Net: 8 exact · 3 benign supersets · 1 guard-stronger-than-map (M4) · 1 refuted-as-no-op (M9)
-- · 1 verify-coverage gap found (M5). Zero mutations scored a dangerous green.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
set client_min_messages = warning;

-- G11's test-only TOCTOU injector. The recurring belt has already read the dog before this trigger
-- can run. Its name sorts before `bookings_dangerous_dog`, so the INSERT sees declared_none at the
-- belt, this trigger flips it, and the production trigger raises the real custody token. Because
-- the production INSERT now owns a per-row exception subtransaction, this update is rolled back
-- with the refused INSERT and the loop can continue. A second GUC makes the same trigger raise an
-- unrelated P0001, proving the handler re-raises anything outside the three custody tokens.
create or replace function _mgn_flip_dog_during_recurring_insert() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
declare
  v_target text := nullif(current_setting('mgn.toctou_series', true), '');
  v_error_target text := nullif(current_setting('mgn.toctou_error_series', true), '');
begin
  if v_error_target is not null and new.series_id::text is not distinct from v_error_target then
    raise exception using errcode = 'P0001', message = 'mgn_unknown_insert_failure';
  elsif v_target is not null and new.series_id::text is not distinct from v_target then
    update dogs
       set dangerous_status = 'declared_dangerous', dangerous_basis = 'designated'
     where id = new.dog_id;
  end if;
  return new;
end $$;

drop trigger if exists a_mgn_flip_dog_during_recurring_insert on bookings;
create trigger a_mgn_flip_dog_during_recurring_insert before insert on bookings
  for each row when (new.series_id is not null)
  execute function _mgn_flip_dog_during_recurring_insert();

do $$
declare
  oc uuid; od uuid; ou uuid; ox uuid; og5 uuid; or1 uuid; or2 uuid;
  hh uuid; rr uuid; rt uuid;
  dc uuid; dd uuid; du uuid; dx uuid; dn uuid; dg5 uuid; dz uuid; dr1 uuid; dr2 uuid; dtmp uuid;
  dlate uuid; dlate_u uuid; dhome uuid; dr3 uuid; dr4 uuid; dr5 uuid; dr6 uuid; dr7 uuid;
  ddel_bad uuid; ddel_ok uuid; ddel_ops uuid;
  v_club uuid; v_s uuid; sd_g5 uuid; sd_rsvp uuid; sd_tmp uuid;
  ser1 uuid; ser2 uuid; ser3 uuid; ser4 uuid; ser5 uuid; ser6 uuid; ser7 uuid;
  v_bad text; v_msg text; v_err text; v_src text; v_n int; v_n2 int; v_bid uuid;
  v_dow int; v_rule jsonb; v_at timestamptz; v_at2 timestamptz;
  b_ok uuid;
begin
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- shared seed — built at TOP LEVEL, outside every pin
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- 151's header records why: a plpgsql `begin … exception` block is a SUBTRANSACTION, so when one
  -- pin catches, everything that block wrote is ROLLED BACK — and three later pins then report
  -- `not_found` about a fixture that existed a moment earlier, with two of the three red messages
  -- naming the wrong thing. State more than one pin depends on lives out here.
  oc  := t_user('mgn_oc', 'owner');
  od  := t_user('mgn_od', 'owner');
  ou  := t_user('mgn_ou', 'owner');
  ox  := t_user('mgn_ox', 'owner');
  og5 := t_user('mgn_og5','owner');
  or1 := t_user('mgn_or1','owner');
  or2 := t_user('mgn_or2','owner');
  hh  := t_user('mgn_hh', 'runner'); update runners set tier = 'veteran' where profile_id = hh;
  rr  := t_user('mgn_rr', 'runner');
  rt  := t_route('맹견 코스');

  -- t_dog now declares `declared_none` (0119 changed that one line — see 10_settle_suite.sql).
  dc  := t_dog(oc, '보통이');
  dg5 := t_dog(og5, '교대견');
  dr1 := t_dog(or1, '반복이');

  -- a dog whose owner answered YES, through the LISTED-BREED door
  insert into dogs (owner_id, name, breed, dangerous_status, dangerous_basis)
    values (od, '로트', '로트와일러', 'declared_dangerous', 'listed_breed') returning id into dd;
  -- ⚠ …and one through the OTHER door, with a breed the screen would never catch. This is what
  -- keeps §B honest as a SCREEN: the refusal must come from the DECLARATION, not from the regex.
  insert into dogs (owner_id, name, breed, dangerous_status, dangerous_basis)
    values (od, '조용이', '골든 리트리버', 'declared_dangerous', 'designated') returning id into dz;
  insert into dogs (owner_id, name, breed, dangerous_status, dangerous_basis)
    values (or2, '반복맹견', '도사견', 'declared_dangerous', 'listed_breed') returning id into dr2;
  -- nobody has ever been asked about this one — the DEFAULT, i.e. every dog that already exists
  insert into dogs (owner_id, name) values (ou, '미신고') returning id into du;
  -- declared not-맹견, and the breed the owner typed says otherwise
  insert into dogs (owner_id, name, breed, dangerous_status)
    values (ox, '핏불이', '아메리칸 핏불테리어', 'declared_none') returning id into dx;
  -- declared not-맹견 with NO breed at all — the NULL that §B's coalesce exists for
  insert into dogs (owner_id, name, breed, dangerous_status)
    values (oc, '견종미상', null, 'declared_none') returning id into dn;

  -- club stage: a session that is open, routed and in the future. No check-in — G4/G5 never
  -- assign a runner, and check-in has a window a 30h-out session refuses.
  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_club := club_request_district('맹견동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '30 hours', '맹견 집결지', rt, 8, 'mixed');
  -- a LEGITIMATE delegation, at top level, for G5 to inherit. Its dog is declared_none TODAY;
  -- G5 is what happens when that stops being true while the dog is already in custody.
  perform set_config('request.jwt.claim.sub', og5::text, false);
  sd_g5 := session_delegate_dog(v_s, dg5, t_consent());
  perform set_config('request.jwt.claim.sub', '', false);
  -- G5 ⓑ's own 동반 row, seeded HERE and not borrowed from G4 ⓑ. Two pins sharing one fixture is
  -- how a single failure paints three red messages that name the wrong thing (151's header). It
  -- goes in as `owner_handled`, which the INSERT trigger's WHEN clause exempts — so this insert
  -- succeeding is itself the first half of the exemption being real.
  insert into session_dogs (session_id, dog_id, owner_profile_id, custody, responsible_profile_id)
    values (v_s, dz, od, 'owner_handled', od) returning id into sd_tmp;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [G1] the booking is refused at the SERVER, and an ordinary booking still inserts
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';

    -- ⓐ POSITIVE CONTROL, and fixture note ①: `runner_id = NULL`, the real marketplace shape.
    --   Without this arm a gate that refuses every booking scores green on the three below.
    b_ok := t_av_booking(oc, dc, rt, null::uuid, now() + interval '20 hours', 5.0, 'matching');
    select count(*) into v_n from bookings where id = b_ok;
    if v_n <> 1 then v_bad := v_bad || ' 🔴 신고를 마친 강아지의 평범한 부킹이 안 생겼다 — 게이트가 전부를 막는다'; end if;

    -- ⓑ 🔴 THE REFUSAL
    v_err := null;
    begin
      perform t_av_booking(od, dd, rt, null::uuid, now() + interval '20 hours', 5.0, 'matching');
    exception when others then v_err := sqlerrm;
    end;
    if v_err is null then v_bad := v_bad || ' 🔴 맹견 부킹이 생성됐다 — 낯선 사람에게 넘어갔다';
    elsif v_err <> 'dog_dangerous_custody_refused' then
      v_bad := v_bad || ' 거절은 됐지만 토큰이 다르다 [' || v_err || ']'; end if;

    -- ⓒ 🔴 THE ROLE THAT ACTUALLY WRITES. `create-booking-hold` inserts as **service_role**, and
    --   `session_pay_delegation` / the cron insert as definers. A guard written like 0083 §2's
    --   (`if current_user in ('authenticated','anon')`) would exempt every real writer and still
    --   pass ⓑ, because ⓑ runs as postgres. This arm is the one that can tell them apart.
    v_err := null;
    begin
      set local role service_role;
      insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                            base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (od, dd, null, rt, 'draft', now() + interval '21 hours', 5.0, 9900, 15000, 0, 24900, 9900);
    exception when others then v_err := sqlerrm;
    end;
    reset role;
    if v_err is null then v_bad := v_bad || ' 🔴 service_role(엣지 함수의 역할)로는 맹견 부킹이 통과했다 — 역할 분기가 실제 writer 전부를 면제한다';
    elsif v_err <> 'dog_dangerous_custody_refused' then
      v_bad := v_bad || ' service_role 경로의 토큰이 다르다 [' || v_err || ']'; end if;

    -- ⓓ the token names a remedy that EXISTS. Not a generic apology, not an invented process —
    --   the 동반 path, which G4 ⓑ then proves is really open.
    v_msg := dog_custody_refusal_detail('dog_dangerous_custody_refused');
    if v_msg is null or position('동반' in v_msg) = 0 then
      v_bad := v_bad || ' 🔴 맹견 거절문이 수행 가능한 구제책(동반 참여)을 지목하지 않는다 [' || coalesce(v_msg,'∅') || ']'; end if;

    if v_bad = ''
      then call _pass('mgn','G1 부킹 경계에서 서버가 거절한다 — 신고된 맹견은 postgres로도 service_role(엣지 함수의 역할)로도 부킹을 만들 수 없고, 신고를 마친 강아지의 평범한 마켓 부킹(runner_id NULL)은 그대로 생성되며, 거절문은 실제로 열려 있는 길(동반 참여)을 지목한다');
    else v_msg := v_bad; call _fail('mgn','G1 부킹 거절', v_msg); end if;
  exception when others then
    reset role; v_msg := sqlerrm; call _fail('mgn','G1 부킹 거절', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [G2] 🔴 UNKNOWN MUST NOT FAIL OPEN — and it must not become a wall either
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- This is the pin the whole design is arranged around. `dog_custody_gate` lets a dog through on
  -- a POSITIVE `= 'declared_none'` match; the tempting rewrite is `<> 'declared_dangerous'`, which
  -- reads as the same rule and admits three different things: an undeclared dog, a dog id that
  -- names no row (every column NULL ⇒ the comparison is NULL ⇒ `if not NULL` never fires), and any
  -- enum value a future migration adds. ⓐ and ⓒ are the arms that separate the two spellings.
  begin
    v_bad := '';

    -- ⓐ nobody was ever asked ⇒ refused, and told what to do about it
    v_err := null;
    begin
      perform t_av_booking(ou, du, rt, null::uuid, now() + interval '20 hours', 5.0, 'matching');
    exception when others then v_err := sqlerrm;
    end;
    if v_err is null then v_bad := v_bad || ' 🔴 미신고 강아지가 통과했다 — 모르는 것은 허용의 근거가 아니다';
    elsif v_err <> 'dog_dangerous_undeclared' then v_bad := v_bad || ' 미신고 토큰이 다르다 [' || v_err || ']'; end if;

    -- ⓑ a null dog id refuses rather than falling through
    if dog_custody_gate(null) is distinct from 'dog_dangerous_undeclared' then
      v_bad := v_bad || ' 🔴 dog_custody_gate(null)이 통과시킨다 [' || coalesce(dog_custody_gate(null),'NULL') || ']'; end if;

    -- ⓒ 🔴 a dog id that names NO ROW — refused, and with the SAME sentence as an undeclared one.
    --   Two facts in one arm: the NULL-safety (a missing row must not read as permission) and the
    --   house law that 「no such thing」 and 「not yours」 answer identically, so this definer is
    --   not an enumeration oracle over other people's dogs (0054:73 / 0067 §C).
    if dog_custody_gate(gen_random_uuid()) is distinct from 'dog_dangerous_undeclared' then
      v_bad := v_bad || ' 🔴 없는 강아지 id가 미신고와 다른 답을 받았다 — fail-open이거나 열거 오라클이다 ['
                     || coalesce(dog_custody_gate(gen_random_uuid()),'NULL') || ']'; end if;

    -- ⓓ …and it is a QUESTION, not a wall: the instant the owner answers, the same dog books.
    --   Without this arm, "refuse everything undeclared, forever" would score green.
    update dogs set dangerous_status = 'declared_none' where id = du;
    v_bid := t_av_booking(ou, du, rt, null::uuid, now() + interval '20 hours', 5.0, 'matching');
    select count(*) into v_n from bookings where id = v_bid;
    if v_n <> 1 then v_bad := v_bad || ' 🔴 보호자가 답한 뒤에도 부킹이 안 된다 — 구제책이 구제하지 않는다'; end if;

    -- ⓔ a declared dog with NO breed string at all must still book (§B's coalesce — a NULL breed
    --   must read as "no match", never as NULL propagating out of the screen)
    v_bid := t_av_booking(oc, dn, rt, null::uuid, now() + interval '22 hours', 5.0, 'matching');
    select count(*) into v_n from bookings where id = v_bid;
    if v_n <> 1 then v_bad := v_bad || ' 🔴 견종이 비어 있는 강아지가 거절됐다 — 스크린의 NULL이 새어 나온다'; end if;

    if v_bad = ''
      then call _pass('mgn','G2 모르는 것은 허용이 아니다 — 미신고 강아지·없는 강아지 id·null 인자가 전부 같은 문장으로 거절되고(열거 오라클 금지), 보호자가 답하는 순간 같은 강아지가 예약되며, 견종이 비어 있어도 통과한다. `= declared_none` 양성 일치를 `<> declared_dangerous`로 바꾸면 ⓐ와 ⓒ가 붉어진다');
    else v_msg := v_bad; call _fail('mgn','G2 미신고 fail-open', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('mgn','G2 미신고 fail-open', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [G3] the breed screen — a second belt that can only ever ADD a refusal
  -- ══════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';

    -- ⓐ 🔴 the evasion: type a listed breed, answer "not a 맹견"
    v_err := null;
    begin
      perform t_av_booking(ox, dx, rt, null::uuid, now() + interval '20 hours', 5.0, 'matching');
    exception when others then v_err := sqlerrm;
    end;
    if v_err is null then v_bad := v_bad || ' 🔴 견종에 「아메리칸 핏불테리어」를 적고 「맹견 아님」을 고른 강아지가 통과했다';
    elsif v_err <> 'dog_dangerous_breed_conflict' then v_bad := v_bad || ' 모순 토큰이 다르다 [' || v_err || ']'; end if;

    -- ⓑ the five stems read dangerous; the breeds this product actually carries do not.
    --   Both directions in one arm: a screen that fires on everything is not a screen.
    if not _breed_reads_as_dangerous('도사견')                then v_bad := v_bad || ' 도사견 미검출'; end if;
    if not _breed_reads_as_dangerous('아메리칸 핏불테리어')     then v_bad := v_bad || ' 핏불 미검출'; end if;
    if not _breed_reads_as_dangerous('Pit-Bull Terrier')       then v_bad := v_bad || ' Pit-Bull(표기변형) 미검출'; end if;
    if not _breed_reads_as_dangerous('스태퍼드셔 불 테리어')    then v_bad := v_bad || ' 스태퍼드셔 미검출'; end if;
    if not _breed_reads_as_dangerous('AmStaff')                then v_bad := v_bad || ' AmStaff 미검출'; end if;
    if not _breed_reads_as_dangerous('로트와일러')              then v_bad := v_bad || ' 로트와일러 미검출'; end if;
    if not _breed_reads_as_dangerous('rottweiler')             then v_bad := v_bad || ' rottweiler 미검출'; end if;
    if     _breed_reads_as_dangerous('웰시코기')                then v_bad := v_bad || ' 🔴 웰시코기가 맹견으로 읽힌다'; end if;
    if     _breed_reads_as_dangerous('골든 리트리버')           then v_bad := v_bad || ' 🔴 골든 리트리버가 맹견으로 읽힌다'; end if;
    if     _breed_reads_as_dangerous('진돗개')                  then v_bad := v_bad || ' 🔴 진돗개가 맹견으로 읽힌다'; end if;
    if     _breed_reads_as_dangerous('시바견')                  then v_bad := v_bad || ' 🔴 시바견이 맹견으로 읽힌다'; end if;
    if     _breed_reads_as_dangerous(null::text)               then v_bad := v_bad || ' 🔴 견종 NULL이 맹견으로 읽힌다'; end if;

    -- ⓒ 🔴 THE SCREEN NEVER RE-OPENS A CLOSED DOOR. `dz` is declared 맹견 through the 기질평가
    --   door with a breed no regex would ever flag. If the gate consulted the screen first — or
    --   used it as the source of truth — this dog walks. The refusal must come from the
    --   DECLARATION, and it must carry the declaration's token, not the conflict one.
    v_err := null;
    begin
      perform t_av_booking(od, dz, rt, null::uuid, now() + interval '23 hours', 5.0, 'matching');
    exception when others then v_err := sqlerrm;
    end;
    if v_err is distinct from 'dog_dangerous_custody_refused' then
      v_bad := v_bad || ' 🔴 견종으로는 안 잡히는 기질평가 지정견의 결과가 틀렸다 [' || coalesce(v_err,'통과') || ']'; end if;

    -- ⓓ the contradiction is remediable by the owner, which is what makes its token honest:
    --   fix whichever of the two fields is wrong and the booking goes through.
    update dogs set breed = '믹스' where id = dx;
    v_bid := t_av_booking(ox, dx, rt, null::uuid, now() + interval '24 hours', 5.0, 'matching');
    select count(*) into v_n from bookings where id = v_bid;
    if v_n <> 1 then v_bad := v_bad || ' 🔴 견종을 고친 뒤에도 거절된다 — 모순 토큰의 구제책이 거짓이다'; end if;

    if v_bad = ''
      then call _pass('mgn','G3 견종 스크린은 거절만 더한다 — 「맹견 아님」+법정 견종 표기는 모순으로 거절되고(고치면 바로 예약된다), 다섯 어간과 표기 변형은 잡히고 웰시코기·골든·진돗개·시바·NULL은 안 잡히며, 견종으로는 절대 안 잡히는 기질평가 지정견은 스크린이 아니라 신고 때문에 거절된다 — 스크린은 닫힌 문을 다시 열지 못한다');
    else v_msg := v_bad; call _fail('mgn','G3 견종 스크린', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('mgn','G3 견종 스크린', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [G4] the club path refuses at APPLICATION time — and 동반 참여 stays open
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- Two separate claims, and the second is the load-bearing one. If 동반 were refused too, §C's
  -- third refusal token would be naming a remedy that does not exist — which is the failure this
  -- whole slice is written against ("a token must name something its reader can actually DO").
  -- ⚠ ORDER: delegate FIRST. See fixture note ② in the header.
  begin
    v_bad := '';

    -- ⓐ 🔴 refused before the HOST ever spends a decision on it
    perform set_config('request.jwt.claim.sub', od::text, false);
    v_err := null;
    begin
      perform session_delegate_dog(v_s, dd, t_consent());
    exception when others then v_err := sqlerrm;
    end;
    if v_err is null then v_bad := v_bad || ' 🔴 맹견 위탁 신청이 접수됐다 — 호스트가 승인할 수 없는 신청을 심사하게 된다';
    elsif v_err <> 'dog_dangerous_custody_refused' then v_bad := v_bad || ' 클럽 위탁 토큰이 다르다 [' || v_err || ']'; end if;
    -- and nothing was left behind for the host to look at
    select count(*) into v_n from session_dogs where session_id = v_s and dog_id = dd;
    if v_n <> 0 then v_bad := v_bad || ' 거절 뒤에도 session_dogs 행이 남았다=' || v_n; end if;

    -- ⓑ 🔴 THE REMEDY IS REAL — 동반 참여는 그대로 열려 있다. custody stays with the 소유자,
    --   no booking is created, and this file never touches that path.
    perform session_rsvp(v_s, dd);
    select id into sd_rsvp from session_dogs where session_id = v_s and dog_id = dd;
    if sd_rsvp is null then
      v_bad := v_bad || ' 🔴 맹견의 동반 참여가 막혔다 — 거절문이 지목한 유일한 길이 닫혀 있다';
    else
      select count(*) into v_n from session_dogs where id = sd_rsvp and custody = 'owner_handled';
      if v_n <> 1 then v_bad := v_bad || ' 동반 행의 custody가 owner_handled가 아니다'; end if;
      select count(*) into v_n from bookings where dog_id = dd;
      if v_n <> 0 then v_bad := v_bad || ' 🔴 동반 참여가 부킹을 만들었다=' || v_n || ' (그러면 커스터디가 넘어간 것이다)'; end if;
    end if;

    -- ⓒ POSITIVE CONTROL — an ordinary delegation still works on the same session (sd_g5 was
    --   created at top level; assert it survived and is really a delegated row)
    select count(*) into v_n from session_dogs
     where id = sd_g5 and custody = 'runner_delegated' and dog_id = dg5;
    if v_n <> 1 then v_bad := v_bad || ' 🔴 평범한 위탁 신청이 접수되지 않았다 — 게이트가 클럽 전체를 막는다'; end if;

    perform set_config('request.jwt.claim.sub', '', false);
    if v_bad = ''
      then call _pass('mgn','G4 클럽은 결제가 아니라 신청에서 거절한다 — 맹견 위탁은 호스트가 심사하기 전에 막히고 행이 남지 않으며, 같은 세션의 평범한 위탁은 접수되고, **보호자 동반 참여(owner_handled)는 그대로 열려 있다** — 그게 §C 세 번째 거절문이 지목한 길이고, 닫혀 있으면 그 문장이 거짓이 된다');
    else v_msg := v_bad; call _fail('mgn','G4 클럽 신청 거절', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('mgn','G4 클럽 신청 거절', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [G5] 🔴 THE GATE MUST NOT BECOME A TRAP — a dog already in custody comes home
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The dangerous version of this feature is a `before insert or update` trigger with only the
  -- custody test on it. It re-evaluates the gate on EVERY write to a delegated row — booking_id,
  -- hold_status, custody_phase, check-in, and the return transitions. So an owner who answers the
  -- question honestly WHILE their dog is out, or a support agent correcting a wrong answer
  -- mid-session, would make every subsequent custody write raise, INCLUDING the ones that bring
  -- the dog back. A safety gate that strands a dog with a stranger is worse than no gate.
  begin
    v_bad := '';

    -- the situation: dg5 is already delegated (top-level fixture), and only now does its owner
    -- declare it a 맹견.
    update dogs set dangerous_status = 'declared_dangerous', dangerous_basis = 'designated'
     where id = dg5;
    if dog_custody_gate(dg5) is distinct from 'dog_dangerous_custody_refused' then
      v_bad := v_bad || ' 픽스처가 상황을 재현하지 못한다 — 신고 후에도 게이트가 거절하지 않는다'; end if;

    -- ⓐ 🔴 the row that is ALREADY there keeps working. First exercise two ordinary writes, then
    --   execute the return nobody had run before this fix round: runner_delegated → owner_handled.
    --   PREDICTED mutation: remove `owner_handled` from THIS UPDATE trigger's own WHEN (not its
    --   sibling INSERT trigger) → migration VERIFY aborts; with VERIFY bypassed, this arm is red.
    begin
      update session_dogs set checked_in_at = now() where id = sd_g5;
      update session_dogs set custody = custody where id = sd_g5;
      update session_dogs
         set custody = 'owner_handled', responsible_profile_id = og5
       where id = sd_g5;
    exception when others then
      v_bad := v_bad || ' 🔴 이미 위탁 중인 개의 커스터디 행에 쓸 수 없다 [' || sqlerrm
                     || '] — 반환 경로가 죽는다. 게이트가 덫이 됐다';
    end;
    -- PREDICTED count: exactly one returned row, now owner_handled by its owner.
    select count(*) into v_n from session_dogs
     where id = sd_g5 and custody = 'owner_handled' and responsible_profile_id = og5;
    if v_n <> 1 then
      v_bad := v_bad || ' 🔴 위탁 중이던 맹견이 owner_handled로 돌아오지 못했다 — 실제 반환 전이가 열려 있지 않다'; end if;

    -- ⓑ 🔴 but a row MOVING INTO a stranger's custody is still refused. Without this arm the
    --   `_move` trigger could simply be deleted and ⓐ would stay green. `sd_tmp` is this pin's
    --   OWN 동반 row (seeded at top level), so a G4 failure cannot paint this arm.
    v_err := null;
    begin
      update session_dogs set custody = 'runner_delegated' where id = sd_tmp;
    exception when others then v_err := sqlerrm;
    end;
    if v_err is null then
      select count(*) into v_n from session_dogs where id = sd_tmp and custody = 'runner_delegated';
      if v_n <> 1 then v_err := 'no_row_updated'; end if;   -- 0행 UPDATE를 통과로 읽지 않는다
    end if;
    if v_err is null then v_bad := v_bad || ' 🔴 동반 행이 UPDATE 한 번으로 위탁 행이 됐다 — INSERT만 막으면 문이 옆에 하나 더 있다';
    elsif v_err <> 'dog_dangerous_custody_refused' then v_bad := v_bad || ' 이동 거절 토큰이 다르다 [' || v_err || ']'; end if;

    if v_bad = ''
      then call _pass('mgn','G5 게이트는 덫이 아니다 — 러닝 중에 보호자가 맹견 신고를 해도 이미 위탁 중인 행의 **실제 반환 전이(runner_delegated→owner_handled)**가 성공하고, 동시에 동반 행을 UPDATE로 위탁 행으로 바꾸는 옆문은 막힌다. 두 session 트리거의 WHEN은 각자 owner_handled 면제를 가져야 한다');
    else v_msg := v_bad; call _fail('mgn','G5 덫 방지', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('mgn','G5 덫 방지', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [G6] one refused series must not stop the hourly sweep FOR EVERYBODY
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- `generate_recurring_bookings` inserts inside a `for` loop with no per-row handler, so a raise
  -- from §D's trigger aborts the whole statement and every OTHER owner's series silently stops
  -- generating — 0116 §C's defect ("one unparseable timestamp stopped charge dispatch for
  -- EVERYBODY"), reproduced one migration later. §E's ⓕ belt is what keeps the refusal from
  -- becoming an outage; this pin is what keeps the belt.
  -- ⚠ The two arms must BOTH be here: the clean series alone would stay green if the gate were
  -- deleted outright, and the gated series alone would stay green if the sweep simply died.
  begin
    v_bad := '';
    -- tomorrow 10:00 KST — always between ~10h and ~34h out, i.e. inside the cron's (2h, 72h) window
    v_dow  := extract(dow from ((now() at time zone 'Asia/Seoul') + interval '1 day'))::int;
    v_rule := jsonb_build_object('weekdays', jsonb_build_array(v_dow), 'time', '10:00', 'tz', 'Asia/Seoul');

    insert into recurring_series (owner_id, dog_id, route_id, rule, km, addons,
                                  base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (or1, dr1, rt, v_rule, 5.0, '[]'::jsonb, 9900, 15000, 0, 24900, 9900) returning id into ser1;
    insert into recurring_series (owner_id, dog_id, route_id, rule, km, addons,
                                  base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (or2, dr2, rt, v_rule, 5.0, '[]'::jsonb, 9900, 15000, 0, 24900, 9900) returning id into ser2;

    -- the fixture really is poisonous — the trigger DOES refuse this dog
    if dog_custody_gate(dr2) is null then
      v_bad := v_bad || ' 픽스처가 위험을 재현하지 못한다 — 맹견 시리즈의 강아지가 게이트를 통과한다'; end if;

    -- 🔴 THE PIN — the sweep must RETURN, not raise
    v_err := null;
    begin
      perform generate_recurring_bookings();
    exception when others then v_err := sqlerrm;
    end;
    if v_err is not null then
      v_bad := v_bad || ' 🔴 맹견 시리즈 하나가 매시간 스윕 전체를 죽였다 [' || v_err || '] — 0116 §C를 한 파일 뒤에 다시 저질렀다'; end if;

    select count(*) into v_n  from bookings where series_id = ser1;
    select count(*) into v_n2 from bookings where series_id = ser2;
    if v_n <> 1 then v_bad := v_bad || ' 🔴 무관한 보호자의 반복 예약이 안 생겼다(=' || v_n || ') — 남의 강아지 하나가 모두의 예약을 멈춘다'; end if;
    if v_n2 <> 0 then v_bad := v_bad || ' 🔴 맹견 시리즈가 부킹을 만들었다(=' || v_n2 || ')'; end if;

    if v_bad = ''
      then call _pass('mgn','G6 거절이 정전이 되지 않는다 — 맹견 시리즈가 섞여 있어도 generate_recurring_bookings가 raise 없이 돌아오고, 무관한 보호자의 반복 예약은 그대로 생성되며(1건), 맹견 시리즈만 0건이다. §E의 continue 벨트를 지우면 트리거가 raise해 두 시리즈가 함께 0건이 된다 (0116 §C의 그 형태)');
    else v_msg := v_bad; call _fail('mgn','G6 크론 벨트', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('mgn','G6 크론 벨트', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [G7] the declaration latches, the timestamp is the server's
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- `dogs owner all` (0002:63) + table-wide UPDATE means the owner writes this field directly.
  -- Without ⓐ the whole gate is one UPDATE away from off — 「a gate that EXISTS is not a gate that
  -- GUARDS」. Without ⓑ/ⓒ the latch would be a wall that punishes a mis-tap.
  begin
    v_bad := '';

    -- ⓐ 🔴 declared_dangerous is one-way
    v_err := null;
    begin
      update dogs set dangerous_status = 'declared_none', dangerous_basis = null where id = dd;
    exception when others then v_err := sqlerrm;
    end;
    if v_err is null then v_bad := v_bad || ' 🔴 맹견 신고를 앱에서 되돌렸다 — 게이트가 UPDATE 한 번 거리다';
    elsif v_err <> 'dog_dangerous_declaration_final' then v_bad := v_bad || ' 래치 토큰이 다르다 [' || v_err || ']'; end if;
    select count(*) into v_n from dogs where id = dd and dangerous_status = 'declared_dangerous';
    if v_n <> 1 then v_bad := v_bad || ' 래치가 터진 뒤 상태가 바뀌어 있다'; end if;

    -- ⓑ correcting UPWARD is always allowed (declared_none → declared_dangerous)
    dtmp := t_dog(oc, '늦게안것');
    begin
      update dogs set dangerous_status = 'declared_dangerous', dangerous_basis = 'designated' where id = dtmp;
    exception when others then v_bad := v_bad || ' 🔴 뒤늦은 맹견 신고가 거절됐다 [' || sqlerrm || '] — 정직해지는 방향이 막혀 있다';
    end;

    -- ⓒ un-answering is allowed: it only moves the owner into a state that is itself refused, so
    --   it buys nothing, and refusing it would make a form mis-tap permanent.
    dtmp := t_dog(oc, '오탭');
    begin
      update dogs set dangerous_status = 'undeclared' where id = dtmp;
    exception when others then v_bad := v_bad || ' declared_none → undeclared가 거절됐다 [' || sqlerrm || ']';
    end;
    select count(*) into v_n from dogs where id = dtmp and dangerous_declared_at is null;
    if v_n <> 1 then v_bad := v_bad || ' 미신고로 돌아갔는데 신고 시각이 남아 있다'; end if;

    -- ⓓ 🔴 the stamp is the SERVER's — a client-supplied value on INSERT is discarded (0083 §2's
    --   rule applied to a legal record: a row born holding a stamp is a forged stamp)
    insert into dogs (owner_id, name, dangerous_status, dangerous_declared_at)
      values (oc, '도장위조', 'declared_none', timestamptz '2000-01-01 00:00:00+09') returning id into dtmp;
    select count(*) into v_n from dogs
      where id = dtmp and dangerous_declared_at > now() - interval '1 hour';
    if v_n <> 1 then v_bad := v_bad || ' 🔴 클라이언트가 담아 온 신고 시각이 그대로 저장됐다'; end if;

    -- ⓔ …and an update that does not touch the status leaves the stamp alone (a "touch" that
    --   silently re-dates a legal record is the other half of the same defect)
    select dangerous_declared_at into v_at from dogs where id = dtmp;
    update dogs set name = '도장위조2', dangerous_declared_at = timestamptz '2000-01-01 00:00:00+09'
     where id = dtmp;
    select dangerous_declared_at into v_at2 from dogs where id = dtmp;
    if v_at2 is distinct from v_at then
      v_bad := v_bad || ' 🔴 상태를 안 건드린 UPDATE가 신고 시각을 바꿨다 [' || coalesce(v_at2::text,'∅') || ']'; end if;

    -- ⓕ 🔴 …AS THE OWNER, THROUGH THE ORDINARY CLIENT PATH. Two things this arm settles that no
    --   other arm can, because every arm above runs as postgres:
    --   ① **the remedy is really performable.** §C's tokens tell an owner to answer the question
    --      on the dog profile; `dogs owner all` (0002:63) + table-wide UPDATE is the surface they
    --      would use, and until it is EXECUTED as `authenticated` "they can just edit it" is an
    --      assumption. A refusal naming an action its reader cannot take is the defect this whole
    --      slice is written against.
    --   ② **the trigger function's revoke is safe.** `_guard_dog_dangerous_declaration` is revoked
    --      from anon/authenticated (0106 §'s house pattern). EXECUTE on a trigger function is
    --      checked at CREATE TRIGGER, not at fire time — but that is a belief until something runs
    --      it, and if it is wrong the owner gets 42501 on every dog edit in the product. This arm
    --      is what turns the belief into a measurement.
    dtmp := t_dog(oc, '보호자직접');
    perform set_config('request.jwt.claim.sub', oc::text, false);
    v_err := null;
    begin
      set local role authenticated;
      update dogs set dangerous_status = 'declared_dangerous', dangerous_basis = 'listed_breed'
       where id = dtmp;
    exception when others then v_err := coalesce(sqlstate, '') || '/' || sqlerrm;
    end;
    reset role;
    if v_err is not null then
      v_bad := v_bad || ' 🔴 보호자가 자기 강아지에 직접 신고를 못 한다 [' || v_err
                     || '] — 거절문이 지목한 행동을 그 독자가 수행할 수 없다'; end if;
    select count(*) into v_n from dogs where id = dtmp and dangerous_status = 'declared_dangerous';
    if v_n <> 1 then v_bad := v_bad || ' 보호자 신고가 반영되지 않았다'; end if;
    -- and the latch answers the OWNER with the latch token, not with a permission error
    v_err := null;
    begin
      set local role authenticated;
      update dogs set dangerous_status = 'declared_none', dangerous_basis = null where id = dtmp;
    exception when others then v_err := sqlerrm;
    end;
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_err is distinct from 'dog_dangerous_declaration_final' then
      v_bad := v_bad || ' 🔴 보호자가 되돌리기를 시도했을 때의 답이 래치 토큰이 아니다 [' || coalesce(v_err,'통과') || ']'; end if;

    if v_bad = ''
      then call _pass('mgn','G7 신고는 편도이고 도장은 서버 것이다 — 맹견 신고는 앱에서 되돌릴 수 없고(플랫폼이 지정 해제 서류를 읽을 수 없으므로), 뒤늦게 맹견으로 고치는 방향과 오탭을 미신고로 되돌리는 방향은 열려 있으며, dangerous_declared_at은 INSERT의 클라 값도 상태를 안 건드린 UPDATE도 무시하고 서버가 찍는다. 마지막 팔은 **authenticated 역할로 보호자가 직접** 실행한다 — 거절문이 지목한 행동이 실제로 수행 가능하다는 것과, 트리거 함수의 revoke가 발화 시점 42501을 만들지 않는다는 것을 믿음이 아니라 실행으로 확인한다');
    else v_msg := v_bad; call _fail('mgn','G7 래치·서버 도장', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('mgn','G7 래치·서버 도장', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [G8] the pair moves together — a declaration with no door, and a door with no declaration
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- `dangerous_basis` is a legal record, not a gate input, so its only protection is the CHECK.
  -- Both halves and both accepted shapes, because a constraint that refuses everything would
  -- satisfy the two negative arms on their own.
  begin
    v_bad := '';

    v_err := null;
    begin insert into dogs (owner_id, name, dangerous_status) values (oc, '문없는신고', 'declared_dangerous');
    exception when others then v_err := sqlstate; end;
    if v_err is distinct from '23514' then v_bad := v_bad || ' 근거 없는 맹견 신고가 23514로 안 막혔다 [' || coalesce(v_err,'통과') || ']'; end if;

    v_err := null;
    begin insert into dogs (owner_id, name, dangerous_status, dangerous_basis)
          values (oc, '신고없는문', 'declared_none', 'listed_breed');
    exception when others then v_err := sqlstate; end;
    if v_err is distinct from '23514' then v_bad := v_bad || ' 신고 없는 근거가 23514로 안 막혔다 [' || coalesce(v_err,'통과') || ']'; end if;

    v_err := null;
    begin insert into dogs (owner_id, name, dangerous_status, dangerous_basis)
          values (oc, '모르는문', 'declared_dangerous', 'because_i_said_so');
    exception when others then v_err := sqlstate; end;
    if v_err is distinct from '23514' then v_bad := v_bad || ' 임의의 근거 문자열이 23514로 안 막혔다 [' || coalesce(v_err,'통과') || ']'; end if;

    -- both complete shapes are accepted (the arm that catches "refuse everything")
    begin
      insert into dogs (owner_id, name, dangerous_status, dangerous_basis)
        values (oc, '견종문', 'declared_dangerous', 'listed_breed');
      insert into dogs (owner_id, name, dangerous_status, dangerous_basis)
        values (oc, '지정문', 'declared_dangerous', 'designated');
    exception when others then v_bad := v_bad || ' 🔴 정상적인 두 문(listed_breed/designated)이 거절됐다 [' || sqlerrm || ']';
    end;

    if v_bad = ''
      then call _pass('mgn','G8 신고와 근거는 짝으로만 움직인다 — 근거 없는 맹견 신고·신고 없는 근거·모르는 근거 문자열은 전부 23514, listed_breed와 designated 두 온전한 형태는 통과. dangerous_basis는 게이트 입력이 아니라 기록이므로 지켜 주는 것이 CHECK뿐이다');
    else v_msg := v_bad; call _fail('mgn','G8 짝 제약', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('mgn','G8 짝 제약', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [G9] the doors — privileges and the trigger inventory, pinned rather than assumed
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- No behavioural pin above changes a database role or counts a trigger, so `grant execute …
  -- to authenticated` on the gate reddens NOTHING without this arm — and `dog_custody_gate` is a
  -- SECURITY DEFINER that takes a caller-supplied dog id, i.e. exactly the shape 0116 §D spent a
  -- migration closing. It answers 「is that household's dog a 맹견」 for any uuid, with no party
  -- gate, because it is not supposed to be reachable by a client at all.
  begin
    v_bad := '';
    if has_function_privilege('anon',          'dog_custody_gate(uuid)', 'execute') then v_bad := v_bad || ' 🔴 anon이 맹견 게이트를 실행할 수 있다'; end if;
    if has_function_privilege('authenticated', 'dog_custody_gate(uuid)', 'execute') then v_bad := v_bad || ' 🔴 authenticated가 남의 강아지 uuid로 맹견 여부를 물을 수 있다 (당사자 게이트 없는 definer — 0116 §D)'; end if;
    if has_function_privilege('anon',          '_breed_reads_as_dangerous(text)', 'execute') then v_bad := v_bad || ' anon이 견종 스크린을 실행할 수 있다'; end if;
    if has_function_privilege('authenticated', '_breed_reads_as_dangerous(text)', 'execute') then v_bad := v_bad || ' authenticated가 견종 스크린을 실행할 수 있다'; end if;
    if has_function_privilege('anon',          'dog_custody_refusal_detail(text)', 'execute') then v_bad := v_bad || ' anon이 거절문 함수를 실행할 수 있다'; end if;
    if not has_function_privilege('service_role', 'dog_custody_gate(uuid)', 'execute') then v_bad := v_bad || ' 🔴 service_role이 게이트를 잃었다 (엣지 함수 경로가 죽는다)'; end if;

    -- PREDICTED count=6: the six triggers by name and table. A dropped trigger is the cheapest way to turn this
    -- whole slice off, and it leaves no other trace.
    select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid
     where not t.tgisinternal
       and ((c.relname = 'bookings'     and t.tgname in ('bookings_dangerous_dog',
                                                         'bookings_dangerous_dog_move'))
         or (c.relname = 'session_dogs' and t.tgname in ('session_dogs_dangerous_dog',
                                                          'session_dogs_dangerous_dog_move'))
         or (c.relname = 'dogs'         and t.tgname in ('dogs_dangerous_declaration',
                                                         'dogs_dangerous_delete')));
    if v_n <> 6 then v_bad := v_bad || ' 🔴 게이트 트리거가 6개가 아니다=' || v_n; end if;

    -- 98 H1 sweeps every definer in public, but say it here too: this slice's own definers.
    select count(*) into v_n from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.prosecdef
       and p.proname in ('dog_custody_gate', '_guard_dangerous_dog_custody')
       and coalesce(array_to_string(p.proconfig, ','), '') not like '%pg_temp%';
    if v_n <> 0 then v_bad := v_bad || ' 🔴 이 슬라이스의 definer ' || v_n || '개가 본문 search_path 봉인 없이 산다'; end if;

    if v_bad = ''
      then call _pass('mgn','G9 게이트는 올바른 문 뒤에 있다 — dog_custody_gate는 당사자 게이트 없는 definer라 클라이언트 역할에 EXECUTE가 없고(남의 강아지 uuid로 맹견 여부를 묻는 오라클이 된다) service_role만 쥐며, 여섯 트리거가 이름·테이블까지 제자리에 있고, 이 슬라이스의 definer 둘 다 본문에 search_path=public, pg_temp를 쓴다');
    else v_msg := v_bad; call _fail('mgn','G9 문·권한', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('mgn','G9 문·권한', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [G10] late declarations re-gate outward booking UPDATEs, never the trip home
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- PREDICTED mutations:
  --   · post-apply DROP bookings_dangerous_dog_move → late-accept is red (+ G9 count);
  --   · delete its old picked_up/active exemption → migration VERIFY aborts; with VERIFY bypassed,
  --     start_run_tx is refused and the real homeward arm is red.
  begin
    v_bad := '';

    -- The constructed attack: INSERT while declared_none, declare dangerous, then accept through
    -- the role the edge actually uses. The refusal must happen on this UPDATE with the existing
    -- custody token, and the pre-custody row must remain unassigned.
    dlate := t_dog(oc, '늦은신고');
    v_bid := t_av_booking(oc, dlate, rt, null::uuid,
                          now() + interval '26 hours', 5.0, 'matching');
    update dogs
       set dangerous_status = 'declared_dangerous', dangerous_basis = 'designated'
     where id = dlate;
    v_err := null;
    begin
      set local role service_role;
      update bookings set runner_id = rr, status = 'confirmed' where id = v_bid;
    exception when others then v_err := sqlerrm;
    end;
    reset role;
    if v_err is distinct from 'dog_dangerous_custody_refused' then
      v_bad := v_bad || ' 🔴 늦게 맹견 신고된 부킹의 service_role 수락 결과가 틀리다 ['
                     || coalesce(v_err, '통과') || ']'; end if;
    -- PREDICTED count=1: the refused row is still matching and unassigned.
    select count(*) into v_n from bookings
     where id = v_bid and status = 'matching' and runner_id is null;
    if v_n <> 1 then
      v_bad := v_bad || ' 🔴 거절된 늦은 수락이 부킹을 배정/확정 상태로 남겼다'; end if;

    -- The other refused state can also arise after INSERT: declared_none → undeclared is deliberately
    -- allowed by the latch because it buys no custody. The UPDATE gate must read it at acceptance.
    dlate_u := t_dog(oc, '늦은미신고');
    v_bid := t_av_booking(oc, dlate_u, rt, null::uuid,
                          now() + interval '27 hours', 5.0, 'matching');
    update dogs set dangerous_status = 'undeclared' where id = dlate_u;
    v_err := null;
    begin
      set local role service_role;
      update bookings set runner_id = rr, status = 'confirmed' where id = v_bid;
    exception when others then v_err := sqlerrm;
    end;
    reset role;
    if v_err is distinct from 'dog_dangerous_undeclared' then
      v_bad := v_bad || ' 🔴 부킹 뒤 미신고로 돌아간 개의 수락 결과가 틀리다 ['
                     || coalesce(v_err, '통과') || ']'; end if;
    -- PREDICTED count=1: the late-undeclared row also stays matching and unassigned.
    select count(*) into v_n from bookings
     where id = v_bid and status = 'matching' and runner_id is null;
    if v_n <> 1 then
      v_bad := v_bad || ' 🔴 거절된 미신고 수락이 부킹을 배정/확정 상태로 남겼다'; end if;

    -- Positive control in the outage direction: a safe dog reaches picked_up first, is declared
    -- dangerous only then, and executes the real marketplace return chain. `start_run_tx` exercises
    -- picked_up→active (making the old-status exemption load-bearing); end_run_tx and both
    -- confirm_return_tx calls exercise the actual stop and two doorstep return stamps.
    dhome := t_dog(oc, '귀가중');
    b_ok := t_av_booking(oc, dhome, rt, rr,
                         now() - interval '30 minutes', 5.0, 'picked_up');
    update dogs
       set dangerous_status = 'declared_dangerous', dangerous_basis = 'designated'
     where id = dhome;
    begin
      perform start_run_tx(b_ok);
      perform end_run_tx(b_ok, 5.0, 1800, 'completed', null, '[]'::jsonb);
      perform confirm_return_tx(b_ok, 'runner', null);
      perform confirm_return_tx(b_ok, 'owner', null);
    exception when others then
      v_bad := v_bad || ' 🔴 이미 picked_up이던 맹견의 실제 귀가 전이가 막혔다 [' || sqlerrm || ']';
    end;
    -- PREDICTED count=1: the active row carries the stop and both return stamps.
    select count(*) into v_n from bookings
     where id = b_ok and status = 'active' and run_ended_at is not null
       and runner_confirmed_return_at is not null and owner_confirmed_return_at is not null
       and settlement_ready_at is not null;
    if v_n <> 1 then
      v_bad := v_bad || ' 🔴 귀가 전이가 끝났지만 양측 반환 씰이 온전하지 않다'; end if;

    -- (re-verdict F1b, 2026-08-24) the constructed case the fix round itself broke: a COMPLETED
    -- booking sits OUTSIDE the picked_up/active top exemption, and its one legitimate runner
    -- change is the emergency transfer bringing a return_pending dog HOME
    -- (session_transfer_accept reassigns runner_id, 0058:133). The unscoped runner arm refused
    -- it. The arm is now scoped to outward statuses; this arm reds if that scope is ever removed
    -- AND the apply-time VERIFY (which owns the first belt) is bypassed.
    update bookings set status = 'completed' where id = b_ok;
    begin
      v_bid := t_user('mgn_transfer_runner', 'runner');    -- a real second runner (v_bid reused)
      set local role service_role;
      update bookings set runner_id = v_bid where id = b_ok; -- transfer shape: a NEW custodian id
      reset role;
    exception when others then
      reset role;
      v_bad := v_bad || ' 🔴 completed 부킹의 비상 인계(러너 교체) 귀가가 막혔다 [' || sqlerrm || ']';
    end;
    if v_bad = ''
      then call _pass('mgn','G10 늦은 신고는 다시 문을 닫되 귀가는 막지 않는다 — declared_none으로 생성된 부킹도 뒤늦게 맹견 또는 미신고 상태가 되면 service_role 수락 UPDATE에서 각각 기존 토큰으로 거절되고, 이미 picked_up이던 행은 실제 귀가 체인을 끝내며, completed 부킹의 비상 인계(러너 교체)도 막히지 않는다 (F1b)');
    else v_msg := v_bad; call _fail('mgn','G10 늦은 신고·귀가 방향', v_msg); end if;
  exception when others then
    reset role; v_msg := sqlerrm; call _fail('mgn','G10 늦은 신고·귀가 방향', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [G11] a declaration between belt-check and INSERT skips one row, not the whole sweep
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- PREDICTED mutations:
  --   · delete the per-row INSERT exception handler → this call raises and every series is 0;
  --   · catch every P0001 instead of only the three custody tokens → the unknown-error arm is red;
  --   · restore a refused-series WARNING inside the loop → the warning-shape arm is red.
  -- PREDICTED execution: clean series 1 booking; race + two pre-refused series 0;
  -- exactly one aggregate WARNING reports 3 series and 3 distinct dogs.
  begin
    v_bad := '';
    -- G6's already-pinned refused series would legitimately join this later sweep. Pause that one
    -- fixture so this pin's expected aggregate is exactly its own three dogs, not four.
    update recurring_series set paused = true where id = ser2;
    v_dow  := extract(dow from ((now() at time zone 'Asia/Seoul') + interval '1 day'))::int;
    v_rule := jsonb_build_object('weekdays', jsonb_build_array(v_dow), 'time', '10:00', 'tz', 'Asia/Seoul');

    dr3 := t_dog(or1, '레이스견');
    insert into dogs (owner_id, name, dangerous_status, dangerous_basis)
      values (or2, '반복맹견둘', 'declared_dangerous', 'designated') returning id into dr4;
    insert into dogs (owner_id, name, dangerous_status, dangerous_basis)
      values (or2, '반복맹견셋', 'declared_dangerous', 'listed_breed') returning id into dr5;
    dr6 := t_dog(or1, '반복정상둘');

    insert into recurring_series (owner_id, dog_id, route_id, rule, km, addons,
                                  base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (or1, dr3, rt, v_rule, 5.0, '[]'::jsonb, 9900, 15000, 0, 24900, 9900)
      returning id into ser3;
    insert into recurring_series (owner_id, dog_id, route_id, rule, km, addons,
                                  base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (or2, dr4, rt, v_rule, 5.0, '[]'::jsonb, 9900, 15000, 0, 24900, 9900)
      returning id into ser4;
    insert into recurring_series (owner_id, dog_id, route_id, rule, km, addons,
                                  base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (or2, dr5, rt, v_rule, 5.0, '[]'::jsonb, 9900, 15000, 0, 24900, 9900)
      returning id into ser5;
    insert into recurring_series (owner_id, dog_id, route_id, rule, km, addons,
                                  base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (or1, dr6, rt, v_rule, 5.0, '[]'::jsonb, 9900, 15000, 0, 24900, 9900)
      returning id into ser6;

    perform set_config('mgn.toctou_series', ser3::text, true);
    v_err := null;
    begin
      perform generate_recurring_bookings();
    exception when others then v_err := sqlerrm;
    end;
    perform set_config('mgn.toctou_series', '', true);

    if v_err is not null then
      v_bad := v_bad || ' 🔴 체크 뒤 신고 레이스 하나가 스윕 전체를 죽였다 [' || v_err || ']'; end if;
    -- PREDICTED counts: clean=1; race/pre-refused=0; raced dog rolled back to declared_none=1.
    select count(*) into v_n from bookings where series_id = ser6;
    if v_n <> 1 then v_bad := v_bad || ' 🔴 무관한 정상 시리즈가 생성되지 않았다=' || v_n; end if;
    select count(*) into v_n from bookings where series_id in (ser3, ser4, ser5);
    if v_n <> 0 then v_bad := v_bad || ' 🔴 레이스/맹견 시리즈가 부킹을 만들었다=' || v_n; end if;
    select count(*) into v_n from dogs where id = dr3 and dangerous_status = 'declared_none';
    if v_n <> 1 then
      v_bad := v_bad || ' 레이스 트리거의 신고 UPDATE가 거절된 INSERT와 함께 롤백되지 않았다'; end if;

    -- PostgreSQL exposes WARNINGs to the client but not to an exception handler. Execute the N=3
    -- case above so the measuring agent sees the runtime cardinality, and pair it with a structural
    -- pin that can fail: the one custody-warning statement must occur once, after the loop.
    select pg_get_functiondef('generate_recurring_bookings()'::regprocedure) into v_src;
    v_n := position('recurring custody gate skipped % series' in v_src);
    v_n2 := position('end loop;' in v_src);
    if v_n = 0 or v_n2 = 0 or v_n < v_n2
       or position('recurring custody gate skipped % series' in substring(v_src from v_n + 1)) > 0 then
      v_bad := v_bad || ' 🔴 맹견 반복 경고가 루프 뒤 한 문장으로 집계되지 않았다'; end if;

    -- The handler is narrow by contract. A different P0001 from the same INSERT must still abort
    -- the invocation; swallowing it would hide arbitrary booking/notification defects as skips.
    dr7 := t_dog(or1, '반복알수없는오류');
    insert into recurring_series (owner_id, dog_id, route_id, rule, km, addons,
                                  base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (or1, dr7, rt, v_rule, 5.0, '[]'::jsonb, 9900, 15000, 0, 24900, 9900)
      returning id into ser7;
    perform set_config('mgn.toctou_error_series', ser7::text, true);
    v_err := null;
    begin
      perform generate_recurring_bookings();
    exception when others then v_err := sqlerrm;
    end;
    perform set_config('mgn.toctou_error_series', '', true);
    if v_err is distinct from 'mgn_unknown_insert_failure' then
      v_bad := v_bad || ' 🔴 알려지지 않은 P0001을 반복 벨트가 삼켰다 ['
                     || coalesce(v_err, '통과') || ']'; end if;
    -- PREDICTED count=0: the re-raised invocation leaves no target booking.
    select count(*) into v_n from bookings where series_id = ser7;
    if v_n <> 0 then v_bad := v_bad || ' 알려지지 않은 오류 뒤 대상 부킹이 남았다=' || v_n; end if;

    if v_bad = ''
      then call _pass('mgn','G11 반복 벨트의 TOCTOU는 한 행에 갇힌다 — 체크 뒤 INSERT 직전에 맹견으로 바뀐 시리즈는 실제 INSERT 트리거 토큰으로 건너뛰고, 미리 거절된 두 시리즈와 함께 0건이며, 무관한 시리즈는 1건 생성된다. 세 거절은 루프 뒤 WARNING 한 번에 집계되고(PREDICTED count=3/distinct dogs=3), 다른 P0001은 그대로 다시 raise된다');
    else v_msg := v_bad; call _fail('mgn','G11 반복 TOCTOU·경고 집계', v_msg); end if;
  exception when others then
    perform set_config('mgn.toctou_series', '', true);
    perform set_config('mgn.toctou_error_series', '', true);
    v_msg := sqlerrm; call _fail('mgn','G11 반복 TOCTOU·경고 집계', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [G12] DELETE cannot erase the declaration latch, and the guard must not become a wall
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- PREDICTED mutations:
  --   · post-apply DROP dogs_dangerous_delete → auth dangerous DELETE succeeds (+ G9 count);
  --   · remove the current_user scope → the postgres ops arm is red, while the ordinary arm keeps
  --     an over-broad "deny every dog DELETE" mutation red as well.
  begin
    v_bad := '';
    insert into dogs (owner_id, name, dangerous_status, dangerous_basis)
      values (oc, '삭제우회', 'declared_dangerous', 'designated') returning id into ddel_bad;
    ddel_ok := t_dog(oc, '일반삭제');
    insert into dogs (owner_id, name, dangerous_status, dangerous_basis)
      values (oc, '운영삭제', 'declared_dangerous', 'listed_breed') returning id into ddel_ops;

    perform set_config('request.jwt.claim.sub', oc::text, false);
    v_err := null;
    begin
      set local role authenticated;
      delete from dogs where id = ddel_bad;
    exception when others then v_err := sqlerrm;
    end;
    reset role;
    if v_err is distinct from 'dog_dangerous_declaration_delete_final' then
      v_bad := v_bad || ' 🔴 authenticated 맹견 DELETE 결과가 틀리다 ['
                     || coalesce(v_err, '통과') || ']'; end if;
    -- PREDICTED counts: refused dangerous row remains=1; ordinary delete leaves=0; ops delete leaves=0.
    select count(*) into v_n from dogs where id = ddel_bad;
    if v_n <> 1 then v_bad := v_bad || ' 거절된 맹견 DELETE가 행을 지웠다'; end if;

    v_err := null;
    begin
      set local role authenticated;
      delete from dogs where id = ddel_ok;
    exception when others then v_err := sqlerrm;
    end;
    reset role;
    if v_err is not null then
      v_bad := v_bad || ' 🔴 평범한 강아지 DELETE까지 막혔다 [' || v_err || ']'; end if;
    select count(*) into v_n from dogs where id = ddel_ok;
    if v_n <> 0 then v_bad := v_bad || ' 평범한 강아지 DELETE가 행을 남겼다'; end if;

    -- The explicit ops escape hatch: INVOKER keeps current_user=postgres here, so a verified
    -- de-designation/data-correction path is not trapped by the app-role latch.
    begin
      delete from dogs where id = ddel_ops;
    exception when others then
      v_bad := v_bad || ' 🔴 postgres 운영 DELETE가 막혔다 [' || sqlerrm || ']';
    end;
    select count(*) into v_n from dogs where id = ddel_ops;
    if v_n <> 0 then v_bad := v_bad || ' postgres 운영 DELETE가 행을 남겼다'; end if;
    perform set_config('request.jwt.claim.sub', '', false);

    if v_bad = ''
      then call _pass('mgn','G12 DELETE로 신고 래치를 지울 수 없다 — authenticated 보호자는 맹견 행을 삭제할 수 없지만 평범한 강아지는 그대로 삭제하며, INVOKER current_user가 postgres인 운영 경로는 맹견 행도 처리할 수 있다');
    else v_msg := v_bad; call _fail('mgn','G12 DELETE 래치·운영 경로', v_msg); end if;
  exception when others then
    reset role; perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('mgn','G12 DELETE 래치·운영 경로', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;

drop trigger if exists a_mgn_flip_dog_during_recurring_insert on bookings;
drop function if exists _mgn_flip_dog_during_recurring_insert();
