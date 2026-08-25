-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 157 — 0122 pickup 동: the pre-accept disclosure window, and the seals around it
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Contract under test: `supabase/migrations/0122_pickup_dong.sql`, built to Sean's Q6 ruling
-- (2026-08-25, verbatim in that file's header and in docs/decisions/awaiting-sean.md
-- §0-undetricies): 「…doesnt show the actual address anyways; also include the 동.」
--
-- What this suite is actually guarding. 0122 opens the FIRST pre-accept disclosure this product
-- has ever made about where a dog lives — every earlier location surface was assigned-runner-only
-- (0060/0065) or party-only. Two failure directions, and the pins are written both ways for each:
--   ① the window widens by accident — a coordinate rides along, the row set stops matching the
--      pool the runner can already see, or a client learns to author the label;
--   ② the window is soldered shut by accident — a green suite that measures nothing because the
--      value never flows (the 0065 W6 near-miss: `to_jsonb` emits NULL-valued keys, so a
--      key-set assertion alone stays green under a body returning constants). Every positive pin
--      here therefore asserts a VALUE, not a shape.
--
-- House law observed: pins BOTH ways · fixtures and any write more than one pin depends on live
-- at TOP LEVEL, outside every exception block (151's recorded lesson) · every `set local role`
-- arm resets the role on BOTH paths (98 H2's idiom) · absent and foreign must be indistinguishable
-- (0054:73) · this suite runs last, and still closes its own matching/runner_pending rows at the
-- end so it cannot pollute an open pool if another suite is ever appended (80/98 precedent).
--
-- ─── PREDICTED MUTATION MAP — ⚠ PREDICTIONS, NOT MEASUREMENTS ────────────────────────────────
--     This session did not run the harness (fleet law: parallel runs braid on one postmaster and
--     produce phantom reds). Everything below is a HYPOTHESIS written before measurement, in the
--     152 convention, reproduced so the measuring agent can contradict it line by line. Nothing
--     here is a number anyone observed.
--   M1  §3 arm ⓐ re-typed as a literal predicate copy that omits the 0056 decline term
--       (i.e. the drift the INHERITANCE exists to prevent)              → RED=[P3ⓐ]
--   M2  §3 loses arm ⓑ (the directed UNION) entirely                    → RED=[P6ⓐ]
--   M3  §3 arm ⓑ loses `club_session_id is null`                        → RED=[P4ⓑ]
--   M4  §3 arm ⓑ loses `b2.runner_id = auth.uid()`                      → RED=[P6ⓑ]
--   M5  §3 `left join addresses` → inner `join`                         → RED=[P7ⓐ, P7ⓑ]
--       (P5 stays GREEN — an address WITH a row and a NULL dong survives an inner join; only
--        the address-less and poisoned cases vanish. That disjointness is the point of P7.)
--   M6  §3 widened: `returns table (…, lat numeric, lng numeric)` + the two columns selected
--                                                                       → RED=[N1]
--   M7  `grant execute on open_request_pickup_dong() to anon`           → RED=[N2ⓐ]
--   M15 §3 arm ⓐ replaced by an unconditional `select id from bookings where status='matching'`
--       (the fail-open this window's inheritance exists to make impossible)
--                                                                       → RED=[P2, P3ⓐ, P4ⓐ, N2ⓓ]
--   M8  §3 loses `set search_path = public, pg_temp`                    → RED=[N3] and 98 H1
--       (cross-suite co-fire expected and correct — H1 is the standing whole-schema watch)
--   M9  §2 trigger never attached                                       → RED=[N7ⓐ, N7ⓑ, N7ⓒ]
--   M10 §2 guard's `is distinct from` → `<>`                            → RED=[N7ⓒ] alone
--       (the NULL-blind form lets a client ERASE a label it cannot write — the asymmetry)
--   M11 `addresses_dong_len` loses its upper bound                      → RED=[N7ⓕ]
--   M12 §3 `stable` → `volatile`                                        → RED=[N5ⓐ]
--   M13 §3 arm ⓑ's `auth.uid() is not null` belt deleted                → PREDICTED GREEN — a
--       semantic no-op today (`col = NULL` is already never true). Recorded as a predicted
--       no-op rather than omitted, so the measurer can refute it (0119 M9's precedent: a
--       predicted-red mutation that measured as a no-op is a finding about the MAP, not the code).
--   M14 `booking_pickup_address` recreated with a sixth `dong` column   → RED=[N4ⓐ]
-- ─── MEASURED 2026-08-25 — blind reviewer's battery (their runs, not relayed) + the fix round ───
--   Baseline as reviewed: 839/0. Reviewer's six mutations (labels theirs):
--     A poison-check dropped                  → 838/1 RED=[P7] (detail names the leaked 역삼동)
--     B a.dong → a.addr (text through the 2-col seal) → 835/4 RED=[P1,P3,P5,P6] — N1 stayed GREEN:
--       the declared TYPE seals coordinates (numbers), not text; the VALUE pins are the catch.
--       The migration's "the type is the seal" sentence was corrected accordingly.
--     C revoke line deleted                   → 837/2 RED=[sec S1, N2] — map's M7 predicted [N2ⓐ]
--       alone and was INCOMPLETE: 0057 §1's schema-wide anon sweep co-fires (0118-row precedent
--       for naming prediction misses out loud).
--     D unconditional UNION widening          → 837/2 RED=[P2, N2ⓓ]
--     E guard role-set narrowed to anon       → 838/1 RED=[N7], all three arms named
--     F CHECK lower bound 1 → 0               → 839/0 GREEN — MEASURED VACUITY; closed by the new
--       ⓖ arm below, and the §1 comment's wrong justification ('' draws a token — false, '' is
--       falsy at every render site) was corrected rather than left to mislead.
--   Fix-round mutations (central session's own measurements, post-fix):
--     M-P8 derivation arm deleted             → MEASURED 838/2 RED=[150 acd P2, 157 P8] — the
--       BLOCKER's both halves independently: 동 surviving account deletion AND the mechanism
--     M-G  lower bound back to 0              → MEASURED 838/2 RED=[N7(ⓖ), P8] — P8's red is a
--       FIXTURE CASCADE (the mutated CHECK lets ⓖ's '' land, so P8ⓐ later reads '' where it
--       expects 반포동), not a P8 property; named so the map never over-claims P8's coverage.
--   Post-fix baseline 840/0 · deno 236/0 (incl. the new reverse party-gate pair).
set client_min_messages = warning;

do $$
declare
  oo uuid; zz uuid;                        -- owner · foreign owner (poisoned-address stage)
  rA uuid; rB uuid; rApp uuid;             -- active runner · control runner · applicant
  dg uuid; rt uuid;
  ad_ok uuid; ad_nodong uuid; ad_poison uuid;
  clb uuid; cs uuid;
  b_open uuid; b_nodong uuid; b_dec uuid; b_club uuid;
  b_dir uuid; b_dirclub uuid; b_poison uuid; b_noaddr uuid;
  b_near uuid; b_far uuid;                 -- N4's live control + its pre-window twin
  v_n int; v_n2 int; v_n3 int;
  v_pre_addr int; v_pre_bk int; v_post_addr int; v_post_bk int;
  v_txt text; v_txt2 text; v_bad text; v_src text; v_vol text;
  v_cols text[]; v_keys text[]; v_types text[]; v_cols2 text[];
  v_exp_cols  text[] := array['booking_id', 'pickup_dong'];        -- 0122 §3's whole contract
  v_exp_types text[] := array['uuid', 'text'];
  v_exp_pickup text[] := array['label', 'addr', 'detail', 'lat', 'lng'];  -- 0065's sealed shape
  v_t timestamptz := timestamptz '2026-11-20 10:00:00+09';  -- fixed window, disjoint from 95~100
begin
  -- ═══ 시드 (TOP LEVEL — 151의 교훈: 두 핀 이상이 의존하는 쓰기는 예외 블록 밖에서 산다) ═══
  oo := t_user('dong_oo', 'owner');
  zz := t_user('dong_zz', 'owner');
  rA := t_user('dong_rA', 'runner');       -- t_user makes a runner 'certified'
  rB := t_user('dong_rB', 'runner');
  rApp := t_user('dong_rApp', 'runner');
  update runners set tier = 'applicant' where profile_id = rApp;   -- is_active_runner() = false
  dg := t_dog(oo, '동네견'); rt := t_route('동 확인 코스');

  -- ad_ok carries a REAL gate code, a REAL door note and REAL coordinates. Not decoration:
  -- without them N1's leak scan would be a "nothing to leak" false green, which is exactly the
  -- trap 100 W6's fixture note records for gate_code_enc.
  insert into addresses (owner_id, label, addr, detail, gate_code_enc, lat, lng, dong)
    values (oo, '우리 집', '서울 서초구 신반포로 123', '101동 1203호', 'ENC::절대노출금지',
            37.508123, 126.995456, '반포동')
    returning id into ad_ok;
  -- pinned address, 동 not yet resolved (day-one production state: the reverse call has not run
  -- or did not match). Must be a PRESENT row with a NULL — never an absent row, never a guess.
  insert into addresses (owner_id, label, addr, lat, lng)
    values (oo, '본가', '서울 서초구 반포대로 45', 37.500111, 126.990222)
    returning id into ad_nodong;
  -- poisoned row: belongs to zz while the booking belongs to oo (0060's own case).
  insert into addresses (owner_id, label, addr, dong)
    values (zz, '남의 집', '서울 강남구 테헤란로 1', '역삼동')
    returning id into ad_poison;

  b_open    := t_av_booking(oo, dg, rt, null, v_t,                        5.0, 'matching');
  b_nodong  := t_av_booking(oo, dg, rt, null, v_t + interval '1 day',     5.0, 'matching');
  b_dec     := t_av_booking(oo, dg, rt, null, v_t + interval '2 days',    5.0, 'matching');
  b_club    := t_av_booking(oo, dg, rt, null, v_t + interval '3 days',    5.0, 'matching');
  b_poison  := t_av_booking(oo, dg, rt, null, v_t + interval '4 days',    5.0, 'matching');
  b_noaddr  := t_av_booking(oo, dg, rt, null, v_t + interval '5 days',    5.0, 'matching');
  b_dir     := t_av_booking(oo, dg, rt, rA,   v_t + interval '6 days',    5.0, 'runner_pending');
  b_dirclub := t_av_booking(oo, dg, rt, rA,   v_t + interval '7 days',    5.0, 'runner_pending');
  b_near    := t_av_booking(oo, dg, rt, rA,   now() + interval '2 hours', 5.0, 'confirmed');
  b_far     := t_av_booking(oo, dg, rt, rA,   now() + interval '48 hours',5.0, 'confirmed');

  -- address_id / club_session_id assignment is a postgres-session UPDATE that touches neither
  -- status, runner nor dog, so no transition trigger and no 0119 custody trigger fires (their
  -- WHEN clauses are movement-scoped — 0119 §D's trap note).
  update bookings set address_id = ad_ok      where id in (b_open, b_dec, b_club, b_dir, b_dirclub, b_near, b_far);
  update bookings set address_id = ad_nodong  where id = b_nodong;
  update bookings set address_id = ad_poison  where id = b_poison;
  -- b_noaddr keeps address_id NULL deliberately (P7ⓐ).

  insert into clubs (name, district, host_profile_id) values ('동 클럽', '반포동', rB)
    returning id into clb;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
    values (clb, rB, v_t + interval '3 days', '반포 집결지') returning id into cs;
  update bookings set club_session_id = cs where id in (b_club, b_dirclub);

  insert into booking_declines (booking_id, runner_profile_id) values (b_dec, rA);

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P1] 해피 경로 + VALUE 단언 — 활성 러너의 오픈 요청은 그 부킹의 동을 정확히 돌려준다
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 값을 단언하는 이유는 0065 W6 헤더가 기록한 니어미스다: 본문을 `null::text` 상수로 바꿔도
  -- 키 집합 검사는 초록으로 남는다. 이 핀이 붉어지지 않으면 나머지 전부가 의미를 잃는다.
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select count(*) into v_n from open_request_pickup_dong() x where x.booking_id = b_open;
    select x.pickup_dong into v_txt from open_request_pickup_dong() x where x.booking_id = b_open;
    if v_n = 1 and v_txt = '반포동'
      then call _pass('dong','P1 오픈 요청 동 — 활성 러너에게 1행, 값이 정확히 반포동');
    else call _fail('dong','P1 오픈 요청 동',
                    'rows=' || coalesce(v_n::text,'∅') || ' dong=' || coalesce(v_txt,'∅')); end if;
  exception when others then call _fail('dong','P1 오픈 요청 동', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P2] 지원자(applicant)는 0행 — 오픈 풀 게이트는 뷰에서 상속된다
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 두 팔의 게이트가 서로 다르다는 사실을 여기서 말해 둔다: ⓐ는 is_active_runner()(tier)를
  -- 상속하고, ⓑ는 tier를 보지 않는다 — ⓑ의 게이트는 **지명당했는가**이고 그건 tier보다 강한
  -- 조건이다 (보호자가 콕 집은 사람만 통과). rApp은 지명받은 행이 없으므로 전체가 0행이어야 한다.
  -- 대조군으로 rB(certified, 거절 없음)가 같은 순간에 1행 이상을 봐야 '함수가 그냥 비어 있다'가
  -- 아니라 '이 호출자에게만 비어 있다'가 된다.
  begin
    perform set_config('request.jwt.claim.sub', rApp::text, false);
    select count(*) into v_n from open_request_pickup_dong();
    perform set_config('request.jwt.claim.sub', rB::text, false);
    select count(*) into v_n2 from open_request_pickup_dong();
    if v_n = 0 and v_n2 > 0
      then call _pass('dong','P2 지원자 0행 — tier 게이트 상속 (대조군 certified는 ' || v_n2 || '행)');
    else call _fail('dong','P2 지원자 0행',
                    'applicant=' || coalesce(v_n::text,'∅') || ' certified=' || coalesce(v_n2::text,'∅')); end if;
  exception when others then call _fail('dong','P2 지원자 0행', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P3] 거절 원장 상속 — 거절한 러너에게는 없고, 대조군 러너에게는 있다
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 0056의 제외 술어는 **러너별 사실**이다. 이 핀이 지키는 것은 그 술어가 아니라 **상속**이다:
  -- 0122 §3이 뷰를 부르는 대신 술어를 베껴 적었다면 다음 0056이 한 곳만 고치고 여기가 낡는다.
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select count(*) into v_n from open_request_pickup_dong() x where x.booking_id = b_dec;
    perform set_config('request.jwt.claim.sub', rB::text, false);
    select count(*) into v_n2 from open_request_pickup_dong() x where x.booking_id = b_dec;
    select x.pickup_dong into v_txt from open_request_pickup_dong() x where x.booking_id = b_dec;
    if v_n = 0 and v_n2 = 1 and v_txt = '반포동'
      then call _pass('dong','P3 거절 상속 — 거절자 0행 ⟷ 대조군 1행(동 값 온전)');
    else call _fail('dong','P3 거절 상속',
                    'decliner=' || coalesce(v_n::text,'∅') || ' control=' || coalesce(v_n2::text,'∅')
                    || ' dong=' || coalesce(v_txt,'∅')); end if;
  exception when others then call _fail('dong','P3 거절 상속', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P4] 클럽 부킹은 두 팔 모두에서 부재 — ⓐ 뷰가 구조적으로 배제 · ⓑ 지명 팔이 명시적으로 배제
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- ⓑ를 따로 보는 이유: ⓐ의 배제는 뷰에서 공짜로 오지만 ⓑ는 이 파일이 직접 쓴 한 줄이고,
  -- 지워도 ⓐ의 핀은 초록으로 남는다. 클럽 예약은 마켓플레이스 요청이 아니다 (0042/0117 교리).
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select count(*) into v_n  from open_request_pickup_dong() x where x.booking_id = b_club;      -- ⓐ
    select count(*) into v_n2 from open_request_pickup_dong() x where x.booking_id = b_dirclub;   -- ⓑ
    -- 대조군: 클럽이 아닌 지명 행은 같은 호출에서 보인다 — '지명 팔 자체가 죽었다'와 구분된다
    select count(*) into v_n3 from open_request_pickup_dong() x where x.booking_id = b_dir;
    if v_n = 0 and v_n2 = 0 and v_n3 = 1
      then call _pass('dong','P4 클럽 배제 — 오픈 클럽 0행 ⓐ · 지명 클럽 0행 ⓑ ⟷ 비클럽 지명 1행');
    else call _fail('dong','P4 클럽 배제',
                    'open_club=' || coalesce(v_n::text,'∅') || ' directed_club=' || coalesce(v_n2::text,'∅')
                    || ' directed_plain=' || coalesce(v_n3::text,'∅')); end if;
  exception when others then call _fail('dong','P4 클럽 배제', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P5] 동이 NULL인 주소 — 행은 **있고** 값이 NULL이다 (지어내지 않는다)
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 이게 day-one 실제 상태다: 0122는 백필하지 않으므로 기존 주소는 전부 dong IS NULL이고,
  -- 역지오코딩이 돌기 전까지 그대로다. 행을 통째로 감추면 클라는 '요청이 없다'로 읽고,
  -- 값을 지어내면 낯선 사람 화면에 거짓말이 인쇄된다. 정답은 '있는데 모른다'뿐이다.
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select count(*) into v_n from open_request_pickup_dong() x where x.booking_id = b_nodong;
    select count(*) into v_n2 from open_request_pickup_dong() x
      where x.booking_id = b_nodong and x.pickup_dong is null;
    if v_n = 1 and v_n2 = 1
      then call _pass('dong','P5 동 미해결 — 행 존재 + 값 NULL (부재도 아니고 추측도 아니다)');
    else call _fail('dong','P5 동 미해결',
                    'rows=' || coalesce(v_n::text,'∅') || ' null_rows=' || coalesce(v_n2::text,'∅')); end if;
  exception when others then call _fail('dong','P5 동 미해결', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P6] 지명 팔 — 지명당한 러너는 자기 runner_pending 행의 동을 보고, 다른 러너는 못 본다
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select count(*) into v_n from open_request_pickup_dong() x where x.booking_id = b_dir;
    select x.pickup_dong into v_txt from open_request_pickup_dong() x where x.booking_id = b_dir;
    perform set_config('request.jwt.claim.sub', rB::text, false);
    select count(*) into v_n2 from open_request_pickup_dong() x where x.booking_id = b_dir;
    -- rB는 활성 러너이고 같은 순간 오픈 풀은 보인다 — '이 호출자가 아무것도 못 본다'와 구분
    select count(*) into v_n3 from open_request_pickup_dong() x where x.booking_id = b_open;
    if v_n = 1 and v_txt = '반포동' and v_n2 = 0 and v_n3 = 1
      then call _pass('dong','P6 지명 팔 — 지명자 1행(반포동) ⟷ 타 러너 0행(같은 호출에서 오픈 풀은 정상)');
    else call _fail('dong','P6 지명 팔',
                    'nominee=' || coalesce(v_n::text,'∅') || ' dong=' || coalesce(v_txt,'∅')
                    || ' other=' || coalesce(v_n2::text,'∅') || ' other_open=' || coalesce(v_n3::text,'∅')); end if;
  exception when others then call _fail('dong','P6 지명 팔', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P7] 주소가 없거나 오염된 행도 **행은 있고 값은 NULL** — 세 가지 모름이 한 가지 모습
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 0122가 inner join 대신 left join을 고른 결정의 핀. inner join이면 '이 부킹엔 주소가 없다'와
  -- '주소는 있는데 동을 모른다'가 화면에서 구분 가능해진다 — 낯선 사람에게 세는 추론 채널이고,
  -- 러너에게는 아무 쓸모가 없다. 오염 행(주소 소유자 ≠ 부킹 소유자)은 0060이 이미 0행으로
  -- 다루는 케이스이고, 여기서는 '값 없음'으로 같은 자리에 앉는다.
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select count(*) into v_n  from open_request_pickup_dong() x
      where x.booking_id = b_noaddr and x.pickup_dong is null;                       -- ⓐ 주소 없음
    select count(*) into v_n2 from open_request_pickup_dong() x
      where x.booking_id = b_poison and x.pickup_dong is null;                       -- ⓑ 오염 행
    -- ⓑ의 진짜 위험: 오염 주소는 '역삼동'을 들고 있다. 새면 남의 집 동네가 인쇄된다.
    select count(*) into v_n3 from open_request_pickup_dong() x where x.pickup_dong = '역삼동';
    if v_n = 1 and v_n2 = 1 and v_n3 = 0
      then call _pass('dong','P7 주소 부재·오염 — 둘 다 행 존재 + NULL, 남의 주소의 동은 한 번도 안 나온다');
    else call _fail('dong','P7 주소 부재·오염',
                    'noaddr_null=' || coalesce(v_n::text,'∅') || ' poison_null=' || coalesce(v_n2::text,'∅')
                    || ' leaked_역삼동=' || coalesce(v_n3::text,'∅')); end if;
  exception when others then call _fail('dong','P7 주소 부재·오염', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [N1] 페이로드 키 집합이 정확히 {booking_id, pickup_dong} — 좌표 모양의 값은 자리 자체가 없다
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 100 W6의 기법 그대로 두 반쪽을 본다: (1) 선언 표면 = proargnames(모드 't') + 그 타입,
  -- (2) 런타임 키 = 실제 행의 to_jsonb 키 집합. **P1의 해피 fixture에 대고 돌린다** —
  -- 0행이면 to_jsonb가 NULL이 되어 단언이 조용히 무너진다(V10 헤더의 함정).
  -- 타입까지 보는 이유: 이름을 pickup_dong으로 두고 타입만 numeric으로 바꾸는 확장은 이름
  -- 검사만으로는 안 잡힌다. 좌표는 '이름'이 아니라 '수'로 샌다.
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select array_agg(a.n order by a.o) into v_cols
    from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality as a(n, m, o)
    where p.proname = 'open_request_pickup_dong' and p.pronamespace = 'public'::regnamespace
      and a.m = 't';
    select array_agg(format_type(a.t, null) order by a.o) into v_types
    from pg_proc p, unnest(p.proallargtypes, p.proargmodes) with ordinality as a(t, m, o)
    where p.proname = 'open_request_pickup_dong' and p.pronamespace = 'public'::regnamespace
      and a.m = 't';
    select array_agg(k order by k) into v_keys from (
      select jsonb_object_keys(j) as k from (
        select to_jsonb(x) as j from open_request_pickup_dong() x
        where x.booking_id = b_open limit 1) s) t;
    select count(*) into v_n
    from unnest(coalesce(v_cols, '{}'::text[]) || coalesce(v_keys, '{}'::text[])) c
    where c ~* 'lat|lng|coord|geo|addr|label|detail|gate|code|enc|owner|phone|price|fare';
    if coalesce(array_length(v_cols, 1), 0) = 2 and v_cols @> v_exp_cols and v_exp_cols @> v_cols
       and coalesce(array_length(v_keys, 1), 0) = 2 and v_keys @> v_exp_cols and v_exp_cols @> v_keys
       and v_types = v_exp_types and v_n = 0
      then call _pass('dong','N1 반환 형상 — 선언 2컬럼 = 런타임 2키 = {booking_id,pickup_dong}, 타입 (uuid,text), 좌표어 0');
    else call _fail('dong','N1 반환 형상',
                    'proargnames=' || coalesce(v_cols::text,'∅') || ' types=' || coalesce(v_types::text,'∅')
                    || ' 런타임키=' || coalesce(v_keys::text,'∅') || ' 누수어=' || coalesce(v_n::text,'∅')); end if;
  exception when others then call _fail('dong','N1 반환 형상', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [N2] ACL + JWT 부재 — anon 불가 · authenticated 가능 · **sub 없는 호출은 0행이지 예외가 아니다**
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- ⓒ service_role은 EXECUTE를 **가진다**, 그리고 그건 이 파일이 준 게 아니다: Supabase(와 심)의
  -- default privileges가 postgres가 만드는 public 함수에 자동으로 준다. 그래서 '회수했다'가 아니라
  -- **'가져도 아무것도 안 나온다'**를 못박는다 — ⓓ가 그 증명이다. 그게 실제 봉인이고, 회수는
  -- 하나 더 있는 벨트일 뿐이다.
  -- ⓓ JWT가 없는 호출(sub 미설정)은 **0행**이다. 예외가 아니다 — 예외였다면 클라의 인박스 세 번째
  -- 다리가 로그아웃 경계에서 요청함 전체를 넘어뜨릴 수 있다. 그리고 이 함수는 절대 current_user를
  -- 신원으로 읽지 않는다(BLOCKER-10 계열: definer 안에서 current_user는 언제나 함수 소유자다) —
  -- 만약 읽었다면 sub 없는 이 호출이 postgres/service_role의 것으로 통과했을 것이다.
  begin
    v_bad := '';
    if has_function_privilege('anon', 'open_request_pickup_dong()', 'execute')
      then v_bad := v_bad || ' 🔴 anon이 픽업 동을 조회할 수 있다 (계정 없이 동네 수집)'; end if;
    if not has_function_privilege('authenticated', 'open_request_pickup_dong()', 'execute')
      then v_bad := v_bad || ' 🔴 authenticated가 실행 권한을 잃었다 (러너 인박스의 세 번째 다리가 죽는다)'; end if;
    if not has_function_privilege('service_role', 'open_request_pickup_dong()', 'execute')
      then v_bad := v_bad || ' service_role EXECUTE 부재 — 심/운영의 default privileges 모델이 변했다 (이 파일의 변화가 아니다)'; end if;
    begin  -- ⓓ sub 없는 호출
      perform set_config('request.jwt.claim.sub', '', false);
      select count(*) into v_n from open_request_pickup_dong();
      if v_n <> 0 then v_bad := v_bad || ' 🔴 ⓓ JWT 없는 호출이 ' || v_n || '행을 돌려줬다'; end if;
    exception when others then
      v_bad := v_bad || ' 🔴 ⓓ JWT 없는 호출이 예외를 던졌다 (0행이어야 한다): ' || sqlerrm;
    end;
    perform set_config('request.jwt.claim.sub', rA::text, false);   -- 무대 원복
    if v_bad = ''
      then call _pass('dong','N2 ACL — anon 불가 · authenticated 가능 · service_role은 가져도 JWT 없이 0행(예외 아님)');
    else call _fail('dong','N2 ACL', v_bad); end if;
  exception when others then call _fail('dong','N2 ACL', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [N3] 본문 search_path 봉인 (로컬 단언 — 98 H1은 전수, 여기는 이 슬라이스의 자기 몫)
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  begin
    select coalesce(array_to_string(p.proconfig, ','), ''), p.prosecdef::text into v_txt, v_txt2
    from pg_proc p
    where p.proname = 'open_request_pickup_dong' and p.pronamespace = 'public'::regnamespace;
    if v_txt like '%search_path%' and v_txt like '%pg_temp%' and v_txt2 = 'true'
      then call _pass('dong','N3 봉인 — definer + 본문 search_path=public,pg_temp');
    else call _fail('dong','N3 봉인', 'proconfig=' || coalesce(v_txt,'∅') || ' secdef=' || coalesce(v_txt2,'∅')); end if;
  exception when others then call _fail('dong','N3 봉인', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [N4] 봉인된 주소 창(0060/0065)은 손대지 않았다 — 형상 ⓐ + 실동작 ⓑ
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 0122가 '동을 러너에게 준다'를 구현하는 가장 쉬운 방법은 booking_pickup_address에 컬럼을
  -- 하나 더 붙이는 것이었고, 그건 배정 러너 전용 창을 넓히는 일이다 — 이 슬라이스는 그걸
  -- 명시적으로 거절했다. ⓐ 선언 형상 5컬럼 그대로 + 본문에 'dong'이라는 글자가 없음.
  -- ⓑ 게이트가 살아 있음: 24h 창 밖의 confirmed 부킹은 배정 러너에게도 not_runner다.
  begin
    select p.prosrc into v_src from pg_proc p
    where p.proname = 'booking_pickup_address' and p.pronamespace = 'public'::regnamespace;
    select array_agg(a.n order by a.o) into v_cols2
    from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality as a(n, m, o)
    where p.proname = 'booking_pickup_address' and p.pronamespace = 'public'::regnamespace
      and a.m = 't';
    v_bad := '';
    if not (coalesce(array_length(v_cols2, 1), 0) = 5 and v_cols2 @> v_exp_pickup and v_exp_pickup @> v_cols2)
      then v_bad := v_bad || ' 🔴 반환 컬럼이 변했다: ' || coalesce(v_cols2::text,'∅'); end if;
    if coalesce(v_src, '') !~ 'not_runner' then v_bad := v_bad || ' 🔴 not_runner 게이트가 본문에서 사라졌다'; end if;
    if coalesce(v_src, '') !~ '24 hours'   then v_bad := v_bad || ' 🔴 24h 창이 본문에서 사라졌다'; end if;
    if coalesce(v_src, '') ~* 'dong'       then v_bad := v_bad || ' 🔴 0122가 봉인된 주소 창에 동을 밀어 넣었다'; end if;
    -- ⓑ 실동작: 창 밖 confirmed(48h) → not_runner · 창 안 confirmed(2h) → 5필드 정상
    perform set_config('request.jwt.claim.sub', rA::text, false);
    begin
      perform * from booking_pickup_address(b_far);
      v_bad := v_bad || ' 🔴 24h 창 밖인데 주소가 나왔다';
    exception when others then
      if sqlerrm !~ 'not_runner' then v_bad := v_bad || ' 창 밖 예외가 not_runner가 아니다: ' || sqlerrm; end if;
    end;
    select x.addr into v_txt from booking_pickup_address(b_near) x;
    if v_txt is distinct from '서울 서초구 신반포로 123'
      then v_bad := v_bad || ' 🔴 창 안 배정 러너가 주소를 못 읽는다 (0122가 게이트를 깼다): ' || coalesce(v_txt,'∅'); end if;
    if v_bad = ''
      then call _pass('dong','N4 주소 창 무손상 — 5컬럼·게이트 문구 그대로·동 미주입 ⟷ 창 밖 not_runner · 창 안 정상');
    else call _fail('dong','N4 주소 창 무손상', v_bad); end if;
  exception when others then call _fail('dong','N4 주소 창 무손상', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [N5] 이 창은 아무것도 쓰지 않는다 — ⓐ provolatile='s' · ⓑ 호출 전후 행 수 불변
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 0120 §E는 정반대 결정을 했다(제공 전 원장 기록 → VOLATILE). 그 차이가 곧 분류다:
  -- 고정 주소의 동 라벨은 개인위치정보가 아니므로 제16조 원장이 붙지 않는다. 그 결정이
  -- 조용히 뒤집히면(= 함수가 쓰기를 시작하면) 여기서 터진다.
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select p.provolatile::text into v_vol from pg_proc p
    where p.proname = 'open_request_pickup_dong' and p.pronamespace = 'public'::regnamespace;
    select count(*) into v_pre_addr from addresses;
    select count(*) into v_pre_bk   from bookings;
    perform count(*) from open_request_pickup_dong();
    perform count(*) from open_request_pickup_dong();   -- 두 번 — 첫 호출만 쓰는 형태도 잡는다
    select count(*) into v_post_addr from addresses;
    select count(*) into v_post_bk   from bookings;
    if v_vol = 's' and v_pre_addr = v_post_addr and v_pre_bk = v_post_bk
      then call _pass('dong','N5 무쓰기 — STABLE + 호출 전후 addresses/bookings 행 수 불변');
    else call _fail('dong','N5 무쓰기',
                    'volatile=' || coalesce(v_vol,'∅')
                    || ' addresses ' || coalesce(v_pre_addr::text,'∅') || '→' || coalesce(v_post_addr::text,'∅')
                    || ' bookings ' || coalesce(v_pre_bk::text,'∅') || '→' || coalesce(v_post_bk::text,'∅')); end if;
  exception when others then call _fail('dong','N5 무쓰기', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [N6] 저장 상태의 addresses는 여전히 소유자 전용 — 새 컬럼이 테이블을 열지 않았다
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 러너는 창(§3)으로만 동을 읽는다. 테이블 직읽기가 열려 있으면 창의 행 집합 제한이 전부 무의미
  -- 해진다 (거절한 요청의 동도, 남의 집 주소도 그냥 읽힌다). 실제 역할로 실행한다 — 정책 텍스트를
  -- 읽는 게 아니라 행이 나오는지를 본다.
  begin
    v_bad := '';
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', rA::text, true);       -- 러너: 남의 주소
      execute 'select count(*) from addresses where id = $1' into v_n using ad_ok;
      execute 'select count(*) from addresses' into v_n2;                -- 전수 스캔도 0이어야 한다
      perform set_config('request.jwt.claim.sub', oo::text, true);       -- 소유자: 대조군
      execute 'select count(*) from addresses where id = $1' into v_n3 using ad_ok;
      reset role;
    exception when others then reset role; v_bad := 'RLS경로 예외:' || sqlerrm;
    end;
    if v_bad = '' and v_n = 0 and v_n2 = 0 and v_n3 = 1
      then call _pass('dong','N6 addresses 소유자 전용 유지 — 러너 직읽기 0행(전수 포함) ⟷ 소유자 1행');
    else call _fail('dong','N6 addresses 소유자 전용',
                    'runner_row=' || coalesce(v_n::text,'∅') || ' runner_all=' || coalesce(v_n2::text,'∅')
                    || ' owner_row=' || coalesce(v_n3::text,'∅') || ' ' || v_bad); end if;
  exception when others then reset role; call _fail('dong','N6 addresses 소유자 전용', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [N7] 동은 서버가 쓴다 — 클라는 심을 수도, 바꿀 수도, 지울 수도 없다 (0122 §2)
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 이 핀이 없으면 0122는 **보호자가 낯선 러너에게 임의 문자열을 보내는 채널**을 연다: addresses에는
  -- 컬럼 그랜트가 하나도 없고(0073 §2 실측) authenticated는 테이블 전체 UPDATE를 갖는다. 0114 §C.6이
  -- 지명 카드에서 pace_label 인쇄를 거절한 것과 같은 계열이다.
  -- 여섯 팔, 양방향: ⓐ INSERT 주입 거절 · ⓑ UPDATE 변경 거절 · ⓒ NULL로 지우기 거절(is distinct from)
  -- ⓓ 기존 쓰기 경로 생존(setAddressPin 형상 = lat/lng만 갱신) · ⓔ service_role은 쓴다 · ⓕ 길이 상한.
  begin
    v_bad := '';
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', oo::text, true);
      begin  -- ⓐ
        execute 'insert into addresses (owner_id, label, addr, dong) values ($1, $2, $3, $4)'
          using oo, '주입', '서울 어딘가 1', '위조동';
        v_bad := v_bad || ' 🔴 ⓐ 클라가 dong을 심은 채로 주소를 만들 수 있다';
      exception when others then
        if sqlerrm !~ 'address_dong_server_only' then v_bad := v_bad || ' ⓐ 예외가 가드가 아니다: ' || sqlerrm; end if;
      end;
      begin  -- ⓑ
        execute 'update addresses set dong = $1 where id = $2' using '위조동', ad_ok;
        v_bad := v_bad || ' 🔴 ⓑ 클라가 자기 주소의 dong을 바꿀 수 있다 (낯선 러너 화면에 인쇄된다)';
      exception when others then
        if sqlerrm !~ 'address_dong_server_only' then v_bad := v_bad || ' ⓑ 예외가 가드가 아니다: ' || sqlerrm; end if;
      end;
      begin  -- ⓒ  NULL로 지우기 — `<>`는 NULL 앞에서 눈이 먼다
        execute 'update addresses set dong = null where id = $1' using ad_ok;
        v_bad := v_bad || ' 🔴 ⓒ 클라가 dong을 지울 수 있다 (`is distinct from`이 `<>`로 후퇴)';
      exception when others then
        if sqlerrm !~ 'address_dong_server_only' then v_bad := v_bad || ' ⓒ 예외가 가드가 아니다: ' || sqlerrm; end if;
      end;
      begin  -- ⓓ 기존 경로 생존: setAddressPin은 lat/lng만 보낸다 (api.ts) — 막히면 안 된다
        execute 'update addresses set lat = $1, lng = $2 where id = $3' using 37.508500, 126.995900, ad_ok;
      exception when others then
        v_bad := v_bad || ' 🔴 ⓓ 핀 저장(lat/lng 갱신)이 가드에 막혔다: ' || sqlerrm;
      end;
      reset role;
    exception when others then reset role; v_bad := v_bad || ' 클라 경로 예외:' || sqlerrm;
    end;
    begin  -- ⓔ service_role(역지오코딩 기록자)은 쓴다
      set local role service_role;
      execute 'update addresses set dong = $1 where id = $2' using '반포본동', ad_ok;
      execute 'update addresses set dong = $1 where id = $2' using '반포동', ad_ok;   -- 원복
      reset role;
    exception when others then reset role; v_bad := v_bad || ' 🔴 ⓔ service_role이 dong을 못 쓴다 (엣지 기록자가 죽는다): ' || sqlerrm;
    end;
    begin  -- ⓕ 길이 상한 — 20자 초과는 CHECK가 거절
      set local role service_role;
      execute 'update addresses set dong = $1 where id = $2' using repeat('가', 21), ad_ok;
      v_bad := v_bad || ' 🔴 ⓕ 21자 dong이 저장됐다 (상한 없음 = 남의 화면에 무한 문자열)';
      reset role;
    exception when others then
      reset role;
      if sqlerrm !~ 'addresses_dong_len' then v_bad := v_bad || ' ⓕ 예외가 길이 CHECK가 아니다: ' || sqlerrm; end if;
    end;
    begin  -- ⓖ 하한 — '' 는 NULL의 두 번째 철자가 될 수 없다 (0073의 규칙). [블라인드 리뷰 MINOR-6:
           -- 하한을 0으로 완화한 변이가 839/0 초록으로 측정됐다 — 핀 없는 제약은 주장일 뿐이다.]
      set local role service_role;
      execute 'update addresses set dong = $1 where id = $2' using '', ad_ok;
      v_bad := v_bad || ' 🔴 ⓖ 빈 문자열 dong이 저장됐다 (하한 소멸 = unknown의 두 철자)';
      reset role;
    exception when others then
      reset role;
      if sqlerrm !~ 'addresses_dong_len' then v_bad := v_bad || ' ⓖ 예외가 길이 CHECK가 아니다: ' || sqlerrm; end if;
    end;
    -- 값이 원복됐는지 확인 (ⓔ의 두 번째 문장) — 이후 핀은 없지만 상태를 남기고 끝내지 않는다
    select a.dong into v_txt from addresses a where a.id = ad_ok;
    if v_txt is distinct from '반포동' then v_bad := v_bad || ' 정리 실패: dong=' || coalesce(v_txt,'∅'); end if;
    if v_bad = ''
      then call _pass('dong','N7 dong은 서버 소유 — 클라 삽입·변경·삭제 3종 거절 ⟷ 핀 저장 생존 · service_role 기록 · 20자 상한 · '' 하한');
    else call _fail('dong','N7 dong 서버 소유', v_bad); end if;
  exception when others then reset role; call _fail('dong','N7 dong 서버 소유', sqlerrm);
  end;

  -- ═══ [P8] 파생의 신선도 — 핀이 움직이면 라벨이 지워진다 (블라인드 리뷰 BLOCKER-1/MAJOR-2의 팔) ═══
  -- dong은 (lat,lng)의 파생값이다. 좌표가 바뀌었는데 라벨이 남으면: (a) 이사한 핀의 옛 동이
  -- 낯선 러너의 카드에 무기한 찍히고(역지오코딩 실패 시 영원히 — 그리고 쓰기 봉인 때문에 아무도
  -- 못 고친다), (b) 0115의 계정 삭제가 lat/lng를 NULL로 만들어도 동이 살아남아 "LOCATES NOTHING
  -- AND IDENTIFIES NOBODY"가 거짓이 된다(리뷰어가 실측: 삭제 후 dong='반포동'). 한 팔이 둘 다
  -- 닫는다 — 0115는 한 바이트도 안 고치고, 좌표 NULL화가 이 트리거를 지나며 라벨을 지운다.
  -- 끝-대-끝 삭제 핀은 150 스위트가 갖는다(픽스처+화이트리스트 팔, 이 슬라이스에서 갱신);
  -- 여기는 메커니즘 세 팔: 이동=지움 · 동일좌표 재확인=보존 · 좌표 소거=지움.
  begin
    v_bad := '';
    -- 준비: ad_ok 의 dong 은 위에서 '반포동'으로 원복돼 있다
    -- ⓐ 동일 좌표 재확인(no-op 핀 저장) — 라벨 보존
    update addresses set lat = lat, lng = lng where id = ad_ok;
    select a.dong into v_txt from addresses a where a.id = ad_ok;
    if v_txt is distinct from '반포동' then v_bad := v_bad || ' ⓐ 동일좌표 재핀이 라벨을 지웠다=' || coalesce(v_txt,'∅'); end if;
    -- ⓑ 핀 이동 — 라벨 지움 (권한 있는 어느 경로로든: 역할 무관, 파생 팔은 무조건이다)
    update addresses set lat = 37.520000, lng = 127.020000 where id = ad_ok;
    select a.dong into v_txt from addresses a where a.id = ad_ok;
    if v_txt is not null then v_bad := v_bad || ' 🔴 ⓑ 이동한 핀에 옛 동이 남았다=' || v_txt; end if;
    -- service_role 재파생은 여전히 열려 있다 (지움이 봉인이 아니라 신선도임의 증명)
    set local role service_role;
    execute 'update addresses set dong = $1 where id = $2' using '옥수동', ad_ok;
    reset role;
    select a.dong into v_txt from addresses a where a.id = ad_ok;
    if v_txt is distinct from '옥수동' then v_bad := v_bad || ' ⓑ 재파생이 막혔다=' || coalesce(v_txt,'∅'); end if;
    -- ⓒ 좌표 소거(0115 익명화가 지나가는 바로 그 길) — 라벨도 지워진다
    update addresses set lat = null, lng = null where id = ad_ok;
    select a.dong into v_txt from addresses a where a.id = ad_ok;
    if v_txt is not null then v_bad := v_bad || ' 🔴 ⓒ 좌표를 지웠는데 동이 살아남았다=' || v_txt || ' (0115 불변식 위반의 메커니즘)'; end if;
    if v_bad = ''
      then call _pass('dong','P8 파생 신선도 — 핀 이동/좌표 소거는 라벨을 지우고(0115 익명화가 공짜로 올라탄다), 동일좌표 재확인은 보존하며, service_role 재파생은 열려 있다');
      else call _fail('dong','P8 파생 신선도', v_bad); end if;
  exception when others then
    begin reset role; exception when others then null; end;
    call _fail('dong','P8 파생 신선도', sqlerrm);
  end;

  -- ═══ 시드 정리 — 오픈 풀 오염 방지 (80/98 선례). matching/runner_pending → expired는 허용 전이 ═══
  update bookings set status = 'expired'
    where id in (b_open, b_nodong, b_dec, b_club, b_poison, b_noaddr, b_dir, b_dirclub);
end $$;
