-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 161 — 0127 맹견 gate REMOVAL (Slice A). Replaces suite 154, which is retired in the same commit.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Sean ruled removal twice, the second time with the legal-review context in front of him
-- (`docs/decisions/2026-08-25-console-rulings.md` F1, 2026-08-25 04:39:43Z: "Remove it
-- completely"). 154 pinned the gate; every one of its pins is now false-by-ruling, so its harness
-- line is dropped in this commit and this file takes its place. The file 154 stays on disk as the
-- record of what the gate did — retirement is the harness dropping it, not a deletion.
--
-- ── WHAT THIS SUITE IS FOR ──────────────────────────────────────────────────────────────────
-- A removal has two failure modes and only one of them is loud:
--   · UNDER-removal — a trigger or a caller survives. The worst case is not "the gate still
--     refuses": `dogs_dangerous_declaration` fires on EVERY dogs write, so left behind with its
--     function gone it bricks every dog profile save in the product. P2 is the one-line pin that
--     reds on exactly that, and it is the highest-value pin in this file.
--   · OVER-removal — Slice B smuggled into Slice A. The three columns, the pair CHECK and the
--     enum MUST survive here; that is what lets an old installed bundle keep working while the
--     new one distributes. P6 owns that boundary.
-- The behavioural pins (P1/P2/P5) come first and the catalog pins (P3/P4/P6) re-run 0127's own
-- VERIFY assertions — because a VERIFY runs once, at apply time, and these outlive it: they fail
-- the day someone re-creates one of these objects in a later migration.
--
-- ── EVERY PIN IS WRITTEN BOTH WAYS ──────────────────────────────────────────────────────────
-- A removal suite fails in a characteristic way: "nothing raised" scores green when the write
-- never happened at all. So every arm that asserts a success also asserts its EFFECT — a
-- count(*), a changed value, a surviving row — and every catalog absence is paired with a
-- positive control that the thing which must REMAIN is still there (0111's belts in P4, the
-- columns' writability and the pair CHECK's refusal in P6).
--
-- ── MUTATION MAP — PREDICTED, THEN MEASURED 2026-08-25 ───────────────────────────────────────
-- Each mutation is applied ALONE against the post-0127 schema, by appending its DDL to the END of
-- 0127 (after the VERIFY block, so the VERIFY still passes and the suite sees the mutated schema).
-- 12 runs, baseline 885/0. **ZERO MISSES: no predicted pin stayed green under any mutation.**
-- Seven of nine reddened a strict SUPERSET of the prediction; M7 and M8 landed exactly; M9c was
-- refused by postgres itself. The prediction lines below are left as written — the measurement
-- follows each — because a map edited to match its own results stops being evidence.
-- Three properties the battery established that the predictions did NOT say, all benign but all
-- worth knowing before anyone reads a red run:
--   ⓐ **P6 is the broadest UNDER-removal detector in this file, not the slice-boundary pin its
--      header calls it.** Its trigger-count arm (14/2/1) reds on EVERY trigger re-add — M1 through
--      M6 — because a re-added trigger changes a count, not just a behaviour. Strictly extra
--      sensitivity, but a red P6 does not by itself mean "Slice B ran early".
--   ⓑ **P5 is not isolated from the INSERT trigger.** Under M1 (an INSERT-path mutation) P5 reds,
--      because P5 ⓐ builds its own `t_av_booking` fixture through that same trigger. Its detail
--      then reads as a `_move` failure when the cause is the INSERT gate. So a red P5 ALONE does
--      not name which trigger came back — **P3 is the pin that names it.** Read P3 first.
--   ⓒ **Two detail strings degrade to a raw error under mutation.** P1's and P5's
--      `exception when others` handlers replace the accumulated `v_bad` with bare `sqlerrm`, so
--      under M1/M3 they report the token `dog_dangerous_undeclared` instead of the authored arm
--      message; under M9 the same happens to P6. The pins red correctly — they just name the
--      symptom rather than the diagnosis. Do not "fix" this by removing the handlers: an
--      uncaught raise would abort the whole suite instead of failing one pin.
-- Each mutation is applied ALONE against the post-0127 schema:
--   M1  PREDICTED  re-add `bookings_dangerous_dog` (+ its function + `dog_custody_gate`)
--                  → RED = [P1 ⓐ booking, P3 (trigger name + function names + prosrc)]
--                    (P1 ⓒ also reds: the cron INSERT goes through the same trigger)
--   M2  PREDICTED  re-add `bookings_dangerous_dog_move`  → RED = [P5 ⓐ, P3]
--   M3  PREDICTED  re-add `session_dogs_dangerous_dog`   → RED = [P1 ⓑ, P3]
--   M4  PREDICTED  re-add `session_dogs_dangerous_dog_move` → RED = [P5 ⓑ, P3]
--                  and P5 ⓒ (the ordinary-dog control) stays GREEN — that asymmetry is what names
--                  the cause as the gate rather than as a club rule
--   M5  PREDICTED  re-add `dogs_dangerous_declaration`   → RED = [P2 ⓒ latch, P2 ⓓ stamp, P3]
--                  ⚠ P2 ⓐ/ⓑ (plain insert + rename) stay GREEN with the function present — they
--                  go red only in the half-removal where the TRIGGER survives its FUNCTION, which
--                  P3's named-trigger arm catches first. Both halves are pinned on purpose.
--   M6  PREDICTED  re-add `dogs_dangerous_delete`        → RED = [P2 ⓔ, P3]
--   M7  PREDICTED  re-add `dog_custody_gate` + a synthetic caller function
--                  → RED = [P3 (function-name inventory AND the schema-wide prosrc scan)]
--                    — the mutation nothing else can see, since neither name contains "dangerous"
--   M8  PREDICTED  re-add the ⓕ belt to `generate_recurring_bookings` (needs the gate back, so M7
--                  rides along) → RED = [P4 (functiondef), P3, P1 ⓒ pit-bull series]
--                  and P1's unrelated-series arm stays GREEN — which is the pairing that tells
--                  "the gate is back" apart from "the sweep is dead".
--   M9  PREDICTED  drop one of the three columns / the pair CHECK / the enum (i.e. run Slice B
--                  early) → RED = [P6], and 0127's own VERIFY would already have refused it.
--
-- ── MEASURED (2026-08-25; 12 runs, ~27-33s each, no `[axes] X8` flake in any of them) ─────────
--   M1  MEASURED  RED = [P1, P3, P5, P6]  (881/4)  superset — P5 via ⓑ above; P6 via ⓐ
--   M2  MEASURED  RED = [P5, P3, P6]      (882/3)  superset — P5 ⓐ named it exactly
--   M3  MEASURED  RED = [P1, P3, P6]      (882/3)  superset; P5 stayed GREEN, correctly — the RSVP
--                 insert is `owner_handled`-exempt and this mutation is an UPDATE trigger
--   M4  MEASURED  RED = [P5 (ⓑ only), P3, P6] (882/3) — **the predicted asymmetry held exactly**:
--                 the detail names only 동반→위탁, with no 대조군 line. This is the arm that tells
--                 the gate apart from a club rule, and it behaved as designed.
--   M5  MEASURED  RED = [P2 (ⓒ+ⓓ only), P3, P6] (882/3) — the ⚠ above CONFIRMED: ⓐ/ⓑ green with
--                 the function present. P3's prosrc arm correctly did NOT fire (the declaration
--                 guard calls nothing that 0127 dropped).
--   M6  MEASURED  RED = [P2 (ⓔ only), P3, P6] (882/3) — ⓔ named both halves (the P0001 token AND
--                 the surviving-row count)
--   M7  MEASURED  RED = [P3 only]         (884/1)  **EXACT** — both arms fired: the name inventory
--                 and the schema-wide prosrc scan. The mutation nothing else can see was caught by
--                 the arm authored for it, and by nothing else. This is the pin that earns its keep.
--   M8  MEASURED  RED = [P1, P4, P3]      (882/3)  **EXACT** — P1 named ONLY the 핏불테리어 series
--                 (=0) while the unrelated owner's series still generated, so the pairing in ④
--                 works: it separates "the gate is back" from "the sweep is dead".
--   M9  MEASURED  drop `dogs.dangerous_declared_at` → RED = [P6, P2] (883/2); details are the raw
--                 `column … does not exist`, per ⓒ above
--   M9b MEASURED  drop the pair CHECK → RED = [P6 only] (884/1), with the authored detail
--                 "CHECK이 사라졌다 — Slice B가 앞당겨졌다". Cleanest red in the battery.
--   M9c MEASURED  drop the enum → **GUARD-REFUSED before any pin ran.** Postgres's own dependency
--                 graph refused it at apply time: `cannot drop type dog_dangerous_status because
--                 other objects depend on it / column dangerous_status of table dogs`. The column
--                 that Slice A deliberately keeps IS the guard on the enum — a structural
--                 protection nobody authored, and one Slice B must dismantle in the right order.
--   BLAST RADIUS: across all 11 runs that reached the suites, EVERY ❌ was `[mgn-off]`. No mutation
--   reddened any of the other 884 pins in either direction.
--
-- ── FIXTURE NOTES ───────────────────────────────────────────────────────────────────────────
-- ① Shared state is built at TOP LEVEL, outside every pin: a plpgsql `begin … exception` block is
--    a SUBTRANSACTION, so a catching pin rolls back everything it wrote and later pins then report
--    `not_found` about a fixture that existed a moment ago (151's header, 154's ①).
-- ② EVERY dog in this file that must exercise the removed gate is created as the SHAPE 0119
--    refused hardest: `breed = '핏불테리어'` (0119 §B's screen matched the 핏불 stem) AND
--    `dangerous_status` left at its DEFAULT `undeclared` (0119 §C refused undeclared outright,
--    before the screen was even consulted). One dog, both doors — so no arm here can be green
--    because it happened to pick the one shape the old gate let through.
-- ③ Each arm gets its OWN dog. Sharing one dog across the booking, delegation and recurring arms
--    couples them through the live-overlap guard in `generate_recurring_bookings` and through
--    `session_dogs`'s unique(session_id, dog_id) — a coupled fixture is how one failure paints
--    three red messages that name the wrong thing.
-- ④ P1 ⓒ calls `generate_recurring_bookings()`, which sweeps EVERY series in the database,
--    including those seeded by earlier suites. Its arms are keyed on `series_id`, never on global
--    counts. Both series owners get a `billing_keys` row so the 0080 `no_card` money gate cannot
--    silently suppress generation if an earlier suite left `payments_live_since` set — that would
--    red this pin for a reason that has nothing to do with 맹견.
-- ⑤ The trigger-count numbers in P6 assume the harness list in this commit. 154 created a
--    test-only trigger on `bookings` (`a_mgn_flip_dog_during_recurring_insert`); dropping its
--    harness line is what makes an exact count assertable. Re-registering 154 before this file
--    would red P6 — correctly, since the two suites cannot both be true.
--
-- ── SCOPE, STATED HONESTLY ──────────────────────────────────────────────────────────────────
-- These pins prove the SCHEMA half only. The edge function's removed token mapping is proven by
-- the deploy readback and by the deletion of `_test/booking_danger_token_test.ts`; the client half
-- is proven by ui6's landing and by smoke ("save an unchanged dog profile; book a 핏불테리어 dog
-- end to end"). Smoke is smoke — it is never implied to be a pin here.
-- ═══════════════════════════════════════════════════════════════════════════════════════════
set client_min_messages = warning;

do $$
declare
  o_book uuid; o_del uuid; o_move uuid; o_rsvp uuid; o_ctrl uuid; o_ser uuid; o_ser2 uuid; o_dogs uuid;
  hh uuid; rr uuid; rt uuid;
  d_book uuid; d_del uuid; d_move uuid; d_rsvp uuid; d_ser uuid; d_ser2 uuid; d_ctrl uuid;
  d_tmp uuid; d_stamp uuid; d_kill uuid;
  v_club uuid; v_s uuid; sd_del uuid; sd_rsvp uuid; sd_ctrl uuid;
  b_book uuid; b_move uuid;
  ser_pit uuid; ser_plain uuid;
  v_bad text; v_msg text; v_err text; v_def text; v_cmt text; v_left text;
  v_n int; v_n2 int; v_dow int; v_rule jsonb;
  v_stamp constant timestamptz := '2020-01-02 03:04:05+00';
begin
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- shared seed — TOP LEVEL, outside every pin (fixture note ①)
  -- ══════════════════════════════════════════════════════════════════════════════════════
  o_book := t_user('rmv_o_book', 'owner');
  o_del  := t_user('rmv_o_del',  'owner');
  o_move := t_user('rmv_o_move', 'owner');
  o_rsvp := t_user('rmv_o_rsvp', 'owner');
  -- ⚠ the control dog needs its OWN owner: `session_rsvp` inserts a `session_people` row and
  --   raises `already_joined` on the unique violation (0048:180-186), so one owner cannot RSVP
  --   twice into the same session. Sharing an owner here would red P5 ⓒ for a club-membership
  --   reason and read as "the gate is back".
  o_ctrl := t_user('rmv_o_ctrl', 'owner');
  o_ser  := t_user('rmv_o_ser',  'owner');
  o_ser2 := t_user('rmv_o_ser2', 'owner');
  o_dogs := t_user('rmv_o_dogs', 'owner');
  hh     := t_user('rmv_host', 'runner'); update runners set tier = 'veteran' where profile_id = hh;
  rr     := t_user('rmv_run',  'runner');
  rt     := t_route('맹견해제 코스');

  -- fixture note ②/③ — one dog per arm, every one of them the shape 0119 refused twice over
  insert into dogs (owner_id, name, breed) values (o_book, '예약핏불', '핏불테리어') returning id into d_book;
  insert into dogs (owner_id, name, breed) values (o_del,  '위탁핏불', '핏불테리어') returning id into d_del;
  insert into dogs (owner_id, name, breed) values (o_move, '이동핏불', '핏불테리어') returning id into d_move;
  insert into dogs (owner_id, name, breed) values (o_rsvp, '동반핏불', '핏불테리어') returning id into d_rsvp;
  insert into dogs (owner_id, name, breed) values (o_ser,  '반복핏불', '핏불테리어') returning id into d_ser;
  -- the unrelated series' dog: an ORDINARY one (t_dog still writes declared_none — that line
  -- leaves in Slice B with the columns), so the control arm is a different shape from the subject
  d_ser2 := t_dog(o_ser2, '반복평범이');
  -- P5 ⓒ's control dog: ordinary, its own owner (see above), and its custody flip was legal even
  -- under 0119 — which is exactly what makes it a control rather than a second subject
  d_ctrl := t_dog(o_ctrl, '대조평범이');

  -- club stage, mirroring 154's: open, routed, 30h out, no check-in window in play
  perform set_config('request.jwt.claim.sub', hh::text, false);
  v_club := club_request_district('해제동');
  perform club_claim_host(v_club);
  v_s := club_create_session(v_club, now() + interval '30 hours', '해제 집결지', rt, 8, 'mixed');
  perform set_config('request.jwt.claim.sub', '', false);

  -- fixture note ④ — the money gate must not be the thing that decides P1 ⓒ
  insert into billing_keys (profile_id, billing_key) values (o_ser,  'bk_rmv_1')
    on conflict (profile_id) do nothing;
  insert into billing_keys (profile_id, billing_key) values (o_ser2, 'bk_rmv_2')
    on conflict (profile_id) do nothing;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P1] 🔴 A 핏불테리어 DOG COMPLETES THE WHOLE CUSTODY JOURNEY — book, delegate, recur
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- The ruling in one pin: all breeds are accepted, on all three paths a stranger can take the
  -- dog. Each arm asserts the ROW, never just the absence of an exception — an insert that
  -- silently did nothing must not read as "the gate is gone".
  begin
    v_bad := '';

    -- ⓐ marketplace: the shape `create-booking-hold` writes (runner_id NULL, matching)
    b_book := t_av_booking(o_book, d_book, rt, null::uuid, now() + interval '20 hours', 5.0, 'matching');
    select count(*) into v_n from bookings where id = b_book;
    if v_n <> 1 then
      v_bad := v_bad || ' 🔴 핏불테리어 강아지의 마켓 부킹이 생기지 않았다(count=' || v_n || ')'; end if;

    -- ⓑ club: `session_delegate_dog` writes `session_dogs` at custody = 'runner_delegated' long
    --   before any booking exists — 0119 refused here first, at APPLICATION time.
    perform set_config('request.jwt.claim.sub', o_del::text, false);
    sd_del := session_delegate_dog(v_s, d_del, t_consent());
    perform set_config('request.jwt.claim.sub', '', false);
    select count(*) into v_n from session_dogs
     where id = sd_del and dog_id = d_del and custody = 'runner_delegated';
    if v_n <> 1 then
      v_bad := v_bad || ' 🔴 핏불테리어 강아지의 클럽 위탁 신청이 접수되지 않았다(count=' || v_n || ')'; end if;

    -- ⓒ cron: the series generates — AND an unrelated owner's series generates in the SAME sweep.
    --   Both arms are required (154 G6's pairing, kept): the pit-bull arm alone would stay green
    --   if the whole sweep died, and the unrelated arm alone would stay green if the gate were
    --   back and only refusing the one dog.
    v_dow  := extract(dow from ((now() at time zone 'Asia/Seoul') + interval '1 day'))::int;
    v_rule := jsonb_build_object('weekdays', jsonb_build_array(v_dow), 'time', '10:00', 'tz', 'Asia/Seoul');
    insert into recurring_series (owner_id, dog_id, route_id, rule, km, addons,
                                  base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (o_ser, d_ser, rt, v_rule, 5.0, '[]'::jsonb, 9900, 15000, 0, 24900, 9900)
      returning id into ser_pit;
    insert into recurring_series (owner_id, dog_id, route_id, rule, km, addons,
                                  base_fare, distance_fare, addon_fare, total_price, min_fare)
      values (o_ser2, d_ser2, rt, v_rule, 5.0, '[]'::jsonb, 9900, 15000, 0, 24900, 9900)
      returning id into ser_plain;

    v_err := null;
    begin
      perform generate_recurring_bookings();
    exception when others then v_err := sqlerrm;
    end;
    if v_err is not null then
      v_bad := v_bad || ' 🔴 시간별 스윕이 예외로 죽었다 [' || v_err || ']'; end if;

    select count(*) into v_n  from bookings where series_id = ser_pit;
    select count(*) into v_n2 from bookings where series_id = ser_plain;
    if v_n <> 1 then
      v_bad := v_bad || ' 🔴 핏불테리어 시리즈가 반복 예약을 만들지 않았다(=' || v_n || ') — 게이트나 벨트가 살아 있다'; end if;
    if v_n2 <> 1 then
      v_bad := v_bad || ' 🔴 무관한 보호자의 시리즈도 생성되지 않았다(=' || v_n2 || ') — 스윕 자체가 죽었다는 뜻이고, 이 핀의 다른 팔은 그 경우 무의미하다'; end if;

    if v_bad = ''
      then call _pass('mgn-off','P1 모든 견종이 받아들여진다 — 핏불테리어 견종에 미신고 상태인 강아지가 마켓 부킹(1건)·클럽 위탁 신청(runner_delegated 행)·반복 예약 생성(1건)을 전부 통과하고, 같은 스윕에서 무관한 보호자의 시리즈도 그대로 1건 생성된다 (Sean F1 2026-08-25 "Remove it completely")');
    else v_msg := v_bad; call _fail('mgn-off','P1 세 경로 전부 통과', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('mgn-off','P1 세 경로 전부 통과', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P2] 🔴 THE HIGHEST-VALUE PIN — ordinary writes to `dogs` still work
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- `dogs_dangerous_declaration` was `before insert or update on dogs FOR EACH ROW` with no WHEN.
  -- It is the trigger a four-item inventory misses, and left behind with its function dropped it
  -- does not "stop gating" — it fails EVERY insert and update on `dogs`: onboarding, a rename, a
  -- weight edit, every profile save in the product. ⓐ/ⓑ are the one-line pins for that. ⓒ/ⓓ/ⓔ
  -- then pin the three behaviours the trigger pair actively imposed, each of which must now be
  -- gone: the one-way latch, the server-stamped timestamp, and the DELETE latch.
  begin
    v_bad := '';

    -- ⓐ an ordinary insert
    insert into dogs (owner_id, name) values (o_dogs, '새강아지') returning id into d_tmp;
    select count(*) into v_n from dogs where id = d_tmp;
    if v_n <> 1 then v_bad := v_bad || ' 🔴 평범한 강아지 INSERT가 실패했다'; end if;

    -- ⓑ an ordinary rename — and the value really moved (a 0-row UPDATE is not a pass)
    update dogs set name = '이름바꿈' where id = d_tmp;
    select count(*) into v_n from dogs where id = d_tmp and name = '이름바꿈';
    if v_n <> 1 then v_bad := v_bad || ' 🔴 평범한 강아지 UPDATE가 반영되지 않았다'; end if;

    -- ⓒ the one-way latch is GONE. 0119 §F raised `dog_dangerous_declaration_final` on exactly
    --   this write; the columns survive Slice A, so the write itself is still legal SQL and its
    --   only former obstacle was the trigger.
    update dogs set dangerous_status = 'declared_dangerous', dangerous_basis = 'listed_breed'
     where id = d_tmp;
    v_err := null;
    begin
      update dogs set dangerous_status = 'declared_none', dangerous_basis = null where id = d_tmp;
    exception when others then v_err := sqlerrm;
    end;
    if v_err is not null then
      v_bad := v_bad || ' 🔴 declared_dangerous → declared_none이 여전히 거절된다 [' || v_err || '] — 래치가 살아 있다'; end if;
    select count(*) into v_n from dogs
     where id = d_tmp and dangerous_status = 'declared_none' and dangerous_basis is null;
    if v_n <> 1 then v_bad := v_bad || ' 되돌리기가 반영되지 않았다'; end if;

    -- ⓓ the timestamp is no longer server-stamped. 0119 §F ⓑ overwrote whatever the client sent
    --   (null for `undeclared`); with the trigger gone the supplied value survives verbatim. This
    --   arm is what tells "the trigger is gone" apart from "the trigger is present but quiet".
    insert into dogs (owner_id, name, dangerous_declared_at)
      values (o_dogs, '도장강아지', v_stamp) returning id into d_stamp;
    select count(*) into v_n from dogs where id = d_stamp and dangerous_declared_at = v_stamp;
    if v_n <> 1 then
      v_bad := v_bad || ' 🔴 클라이언트가 보낸 dangerous_declared_at이 여전히 서버 값으로 덮인다 — 신고 트리거가 살아 있다'; end if;

    -- ⓔ the DELETE latch is gone, executed AS the owner (`authenticated`), which is the only role
    --   0119 §F's delete guard refused. As postgres it would have passed even with the guard live,
    --   so this arm must run under the app role or it measures nothing.
    insert into dogs (owner_id, name, dangerous_status, dangerous_basis)
      values (o_dogs, '삭제대상', 'declared_dangerous', 'designated') returning id into d_kill;
    perform set_config('request.jwt.claim.sub', o_dogs::text, false);
    v_err := null;
    begin
      set local role authenticated;
      delete from dogs where id = d_kill;
    exception when others then v_err := coalesce(sqlstate, '') || '/' || sqlerrm;
    end;
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);
    if v_err is not null then
      v_bad := v_bad || ' 🔴 보호자가 맹견 신고된 강아지를 지울 수 없다 [' || v_err || '] — DELETE 래치가 살아 있다'; end if;
    select count(*) into v_n from dogs where id = d_kill;
    if v_n <> 0 then v_bad := v_bad || ' 🔴 DELETE가 예외 없이 아무 행도 지우지 않았다(남은 행=' || v_n || ')'; end if;

    if v_bad = ''
      then call _pass('mgn-off','P2 강아지 쓰기가 평범해졌다 — INSERT·이름 변경이 통과하고(신고 트리거가 남아 있으면 제품의 모든 강아지 저장이 죽는다), 편도 래치가 풀려 declared_dangerous → declared_none이 성공하며, dangerous_declared_at은 더 이상 서버가 덮어쓰지 않고, 보호자(authenticated)가 신고된 강아지를 직접 삭제할 수 있다');
    else v_msg := v_bad; call _fail('mgn-off','P2 강아지 쓰기 정상화', v_msg); end if;
  exception when others then
    reset role;
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('mgn-off','P2 강아지 쓰기 정상화', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P3] the NAMED inventory — 0127's VERIFY, re-run as a pin that outlives the migration
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- Names one by one, never a pattern: a `%dangerous%` sweep passes while `dog_custody_gate` and
  -- `dog_custody_refusal_detail` sit untouched, and that blind spot IS the silent half-removal.
  -- The last arm is the schema-wide `prosrc` scan — plpgsql carries no dependency records, so a
  -- caller left behind is invisible to the catalog and only fails at the next execution (a cron at
  -- 07 past the hour, or a club application, hours after the migration went green).
  begin
    v_bad := '';

    select string_agg(x.tbl || '.' || x.trg, ', ' order by x.tbl, x.trg) into v_left
      from (values ('bookings',     'bookings_dangerous_dog'),
                   ('bookings',     'bookings_dangerous_dog_move'),
                   ('session_dogs', 'session_dogs_dangerous_dog'),
                   ('session_dogs', 'session_dogs_dangerous_dog_move'),
                   ('dogs',         'dogs_dangerous_declaration'),
                   ('dogs',         'dogs_dangerous_delete')) as x(tbl, trg)
     where exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                    where not t.tgisinternal and c.relnamespace = 'public'::regnamespace
                      and c.relname = x.tbl and t.tgname = x.trg);
    if v_left is not null then v_bad := v_bad || ' 🔴 트리거가 살아남았다 [' || v_left || ']'; end if;

    select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text) into v_left
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and p.proname in ('_guard_dangerous_dog_custody', '_guard_dog_dangerous_declaration',
                         '_guard_dangerous_dog_delete', 'dog_custody_gate',
                         'dog_custody_refusal_detail', '_breed_reads_as_dangerous');
    if v_left is not null then v_bad := v_bad || ' 🔴 함수가 살아남았다 [' || v_left || ']'; end if;

    select string_agg(p.proname, ', ' order by p.proname) into v_left
      from pg_proc p
     where p.pronamespace = 'public'::regnamespace
       and (p.prosrc like '%dog_custody_gate%'
         or p.prosrc like '%dog_custody_refusal_detail%'
         or p.prosrc like '%_breed_reads_as_dangerous%');
    if v_left is not null then
      v_bad := v_bad || ' 🔴 삭제된 객체를 아직 호출하는 함수가 있다 [' || v_left || ']'; end if;

    if v_bad = ''
      then call _pass('mgn-off','P3 이름으로 확인한 부재 — 0119의 트리거 6개와 함수 6개가 각각 정확한 이름으로 사라졌고(`%dangerous%` 패턴은 dog_custody_gate·dog_custody_refusal_detail을 못 본다 — 그게 조용한 반쪽 제거의 정확한 형태다), public 스키마 어느 함수 본문도 삭제된 객체를 호출하지 않는다');
    else v_msg := v_bad; call _fail('mgn-off','P3 이름 인벤토리', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('mgn-off','P3 이름 인벤토리', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P4] the restored generator — 0111's body back, with 0111's belts intact
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- Both directions. The negative half alone passes on an empty stub; the positive half names two
  -- things that predate 0119 and must have come back with the restoration. The comment is checked
  -- too: a comment still claiming a custody belt is a lie the next reader would act on.
  begin
    v_bad := '';
    select pg_get_functiondef('generate_recurring_bookings()'::regprocedure) into v_def;
    if v_def is null then v_bad := v_bad || ' 🔴 generate_recurring_bookings가 없다';
    else
      if v_def like '%dog_custody_gate%' or v_def like '%dog_dangerous_%'
         or v_def like '%recurring custody gate skipped%' then
        v_bad := v_bad || ' 🔴 크론 본문에 0119의 커스터디 벨트가 남아 있다'; end if;
      if v_def not like '%dog/address not owned by series owner%' then
        v_bad := v_bad || ' 🔴 0111 ⓔ 소유권 벨트가 복원되지 않았다 — 제거가 과했다'; end if;
      if v_def not like '%owner_has_unsettled_charge%' then
        v_bad := v_bad || ' 🔴 0080 결제 게이트가 사라졌다 — 제거가 과했다'; end if;
    end if;
    if not exists (select 1 from pg_proc p
                    where p.oid = 'generate_recurring_bookings()'::regprocedure::oid
                      and p.proconfig @> array['search_path=public, pg_temp']) then
      v_bad := v_bad || ' 🔴 search_path가 본문에 없다 (98 H1: ALTER로 붙인 설정은 create or replace가 지운다)'; end if;

    select obj_description('generate_recurring_bookings()'::regprocedure, 'pg_proc') into v_cmt;
    if v_cmt is null then v_bad := v_bad || ' 🔴 크론 함수의 주석이 사라졌다';
    else
      if v_cmt like '%0119%' or v_cmt like '%custody gate%' then
        v_bad := v_bad || ' 🔴 주석이 아직 없는 벨트를 설명한다'; end if;
      if v_cmt not like '%[0111]%' then
        v_bad := v_bad || ' 🔴 주석이 0111:396-401의 복원본이 아니다'; end if;
    end if;

    if v_bad = ''
      then call _pass('mgn-off','P4 크론이 0111로 되돌아왔다 — 본문에 dog_custody_gate·dog_dangerous_·벨트 경고 문자열이 하나도 없고, 0111 ⓔ 소유권 벨트와 0080 결제 게이트는 그대로이며, search_path는 본문에 있고, 주석도 0111의 것이다. ⚠ 복원은 0111의 무-행별-격리 의미까지 되돌린다 — 의도된 결정이며 0127 헤더가 그렇게 말한다');
    else v_msg := v_bad; call _fail('mgn-off','P4 크론 복원', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('mgn-off','P4 크론 복원', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P5] the UPDATE paths — the row that MOVES raises nothing 맹견-shaped, for any breed
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- 0119's two `_move` triggers fired on the writes that carry a dog TOWARD a stranger: a runner
  -- being assigned, the status advancing, the arrival and both handoff stamps, and a session_dogs
  -- row changing custody. INSERT-only pins cannot see them, so this pin walks the real sequence
  -- and asserts the row's END STATE — a raise-free UPDATE that changed nothing would be no proof.
  begin
    v_bad := '';
    b_move := t_av_booking(o_move, d_move, rt, null::uuid, now() + interval '26 hours', 5.0, 'matching');

    -- ⓐ the marketplace row moves outward: runner assigned → accepted → stamps → custody
    --   (the order respects 0066's transition map and 0117's stamp guard, which allows stamps
    --    while the status is confirmed/runner_enroute/picked_up/active)
    v_err := null;
    begin
      update bookings set runner_id = rr, status = 'runner_pending' where id = b_move;
      update bookings set status = 'confirmed' where id = b_move;
      update bookings set arrived_at = now() where id = b_move;
      update bookings set owner_confirmed_handoff_at = now(),
                          runner_confirmed_handoff_at = now() where id = b_move;
      update bookings set status = 'runner_enroute' where id = b_move;
      update bookings set status = 'picked_up' where id = b_move;
    exception when others then v_err := sqlerrm;
    end;
    -- The walk stops at `picked_up` deliberately: that is where custody has actually passed to the
    -- stranger, and 0119's own WHEN clause exempted rows already at picked_up/active — so every
    -- write past this point was never gated and would add fixture risk without adding a pin.
    if v_err is not null then
      v_bad := v_bad || ' 🔴 핏불테리어 강아지의 예약이 진행 중에 거절됐다 [' || v_err || ']'; end if;
    select count(*) into v_n from bookings
     where id = b_move and status = 'picked_up' and runner_id = rr
       and arrived_at is not null
       and owner_confirmed_handoff_at is not null and runner_confirmed_handoff_at is not null;
    if v_n <> 1 then
      v_bad := v_bad || ' 🔴 예약이 실제로 이동하지 않았다 — 예외가 없는 것과 쓰기가 반영된 것은 다르다'; end if;

    -- ⓑ the club row moves into delegated custody by UPDATE — 0119's side door, refused there,
    --   open here. Seeded as a 동반 row first (which the old INSERT trigger exempted), so this arm
    --   isolates the UPDATE trigger exactly.
    perform set_config('request.jwt.claim.sub', o_rsvp::text, false);
    perform session_rsvp(v_s, d_rsvp);
    perform set_config('request.jwt.claim.sub', '', false);
    select id into sd_rsvp from session_dogs where session_id = v_s and dog_id = d_rsvp;
    if sd_rsvp is null then
      v_bad := v_bad || ' 🔴 동반 RSVP 픽스처가 만들어지지 않았다';
    else
      v_err := null;
      begin
        update session_dogs set custody = 'runner_delegated', responsible_profile_id = hh
         where id = sd_rsvp;
      exception when others then v_err := sqlerrm;
      end;
      if v_err is not null then
        v_bad := v_bad || ' 🔴 동반 → 위탁 커스터디 이동이 거절됐다 [' || v_err || ']'; end if;
      select count(*) into v_n from session_dogs where id = sd_rsvp and custody = 'runner_delegated';
      if v_n <> 1 then
        v_bad := v_bad || ' 🔴 커스터디가 실제로 이동하지 않았다(=' || v_n || ')'; end if;
    end if;

    -- ⓒ CONTROL for ⓑ, and it is a diagnostic one. The same flip on an ORDINARY dog was already
    --   legal under 0119 (declared_none passed the gate), so if ⓑ and ⓒ fail TOGETHER the cause is
    --   structural — a club axis rule or a constraint — and not a surviving 맹견 trigger. Without
    --   this arm a red ⓑ would be read as "the gate is back", which is the wrong repair.
    perform set_config('request.jwt.claim.sub', o_ctrl::text, false);
    perform session_rsvp(v_s, d_ctrl);
    perform set_config('request.jwt.claim.sub', '', false);
    select id into sd_ctrl from session_dogs where session_id = v_s and dog_id = d_ctrl;
    if sd_ctrl is null then
      v_bad := v_bad || ' 대조군 동반 RSVP 픽스처가 만들어지지 않았다';
    else
      v_err := null;
      begin
        update session_dogs set custody = 'runner_delegated', responsible_profile_id = hh
         where id = sd_ctrl;
      exception when others then v_err := sqlerrm;
      end;
      if v_err is not null then
        v_bad := v_bad || ' ⚠ 대조군(평범한 강아지)의 커스터디 이동도 거절됐다 ['
                       || v_err || '] — 원인은 맹견 트리거가 아니라 구조적인 것이다'; end if;
    end if;

    if v_bad = ''
      then call _pass('mgn-off','P5 이동 경로도 조용하다 — 핏불테리어 강아지의 예약이 러너 지명·수락·도착·인계 도장 양쪽·픽업(커스터디 이전 지점)까지 아무것도 raise하지 않고 실제로 picked_up에 도달하며, session_dogs의 동반 → 위탁 커스터디 UPDATE도 통과한다 (0119의 두 _move 트리거가 걸려 있던 바로 그 쓰기들). 평범한 강아지의 같은 이동이 대조군으로 함께 실행되므로, 둘이 같이 붉어지면 원인은 맹견이 아니라 구조적인 것이다');
    else v_msg := v_bad; call _fail('mgn-off','P5 UPDATE 경로', v_msg); end if;
  exception when others then
    perform set_config('request.jwt.claim.sub', '', false);
    v_msg := sqlerrm; call _fail('mgn-off','P5 UPDATE 경로', v_msg);
  end;

  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- [P6] 🔴 THE SLICE BOUNDARY — Slice A must NOT have taken the columns
  -- ══════════════════════════════════════════════════════════════════════════════════════
  -- This is the OVER-removal direction, and it is the one that costs a deploy-order constraint:
  -- while the columns exist, an installed bundle that still selects or writes them keeps working
  -- and this landing is safe in any order. Slice B drops them only once ZERO bundles reference
  -- them, MEASURED. So here the columns must EXIST and ACCEPT WRITES, the pair CHECK must still
  -- refuse a mismatched pair (a CHECK that exists but no longer constrains is not a CHECK), and
  -- the enum must still be a type. The trigger counts close the same door from the other side:
  -- 14/2/1, measured two ways at authoring (the whole migration chain incl. `create constraint
  -- trigger`, and the linked project's live pg_trigger on 2026-08-25 — identical name lists).
  begin
    v_bad := '';

    select count(*) into v_n from information_schema.columns
     where table_schema = 'public' and table_name = 'dogs'
       and column_name in ('dangerous_status', 'dangerous_basis', 'dangerous_declared_at');
    if v_n <> 3 then v_bad := v_bad || ' 🔴 세 컬럼이 남아 있지 않다(=' || v_n || ') — Slice B가 앞당겨졌다'; end if;

    if not exists (select 1 from pg_type where typnamespace = 'public'::regnamespace
                     and typname = 'dog_dangerous_status') then
      v_bad := v_bad || ' 🔴 dog_dangerous_status 이넘이 사라졌다 — Slice B가 앞당겨졌다'; end if;

    -- the columns still take a write, both values of the pair
    update dogs set dangerous_status = 'declared_dangerous', dangerous_basis = 'designated',
                    dangerous_declared_at = now()
     where id = d_book;
    select count(*) into v_n from dogs
     where id = d_book and dangerous_status = 'declared_dangerous' and dangerous_basis = 'designated';
    if v_n <> 1 then v_bad := v_bad || ' 🔴 남아 있는 컬럼에 쓰기가 안 된다'; end if;

    -- …and the CHECK still constrains (present AND enforcing — the mismatched pair is refused)
    if not exists (select 1 from pg_constraint
                    where conrelid = 'dogs'::regclass
                      and conname = 'dogs_dangerous_basis_pairs_with_status') then
      v_bad := v_bad || ' 🔴 dogs_dangerous_basis_pairs_with_status CHECK이 사라졌다 — Slice B가 앞당겨졌다';
    else
      v_err := null;
      begin
        update dogs set dangerous_basis = null where id = d_book;   -- 맹견인데 문이 없다
      exception when others then v_err := sqlerrm;
      end;
      if v_err is null then
        v_bad := v_bad || ' 🔴 CHECK이 남아 있는데 어긋난 짝을 막지 못했다'; end if;
    end if;

    select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid
     where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname = 'bookings';
    if v_n <> 14 then v_bad := v_bad || ' 🔴 bookings 트리거 수가 14가 아니다(=' || v_n || ')'; end if;
    select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid
     where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname = 'dogs';
    if v_n <> 2 then v_bad := v_bad || ' 🔴 dogs 트리거 수가 2가 아니다(=' || v_n || ') — 기대: t_dogs_touch, club_dog_materiality'; end if;
    select count(*) into v_n from pg_trigger t join pg_class c on c.oid = t.tgrelid
     where not t.tgisinternal and c.relnamespace = 'public'::regnamespace and c.relname = 'session_dogs';
    if v_n <> 1 then v_bad := v_bad || ' 🔴 session_dogs 트리거 수가 1이 아니다(=' || v_n || ') — 기대: club_v1_axes_sync'; end if;

    if v_bad = ''
      then call _pass('mgn-off','P6 슬라이스 경계 — 세 신고 컬럼과 이넘과 짝 CHECK이 그대로 살아 있고(설치된 구버전 번들이 계속 읽고 쓸 수 있어야 배포 순서 제약이 0이 된다), 컬럼은 여전히 쓰기를 받고 CHECK은 여전히 어긋난 짝을 거절하며, bookings/dogs/session_dogs 트리거 수는 측정값 14/2/1이다. 컬럼·CHECK·이넘 제거는 배포 실측 뒤 Slice B의 일이다');
    else v_msg := v_bad; call _fail('mgn-off','P6 슬라이스 경계', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('mgn-off','P6 슬라이스 경계', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
