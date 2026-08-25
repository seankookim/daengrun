-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 158 — 0123 runner home base + pre-accept distance bands (Sean's Q6, distance half, ruling B)
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Contract under test: `supabase/migrations/0123_runner_base_distance.sql`, built to Sean's
-- ruling (2026-08-25, verbatim in that file's header and in docs/decisions/awaiting-sean.md
-- §0-untricies): 「go with B for distance, and the runner should be able to switch this
-- address in settings.」
--
-- What this suite is actually guarding. 0122 opened the first pre-accept disclosure about where
-- a dog lives (a 동 label). 0123 opens the second, and it is harder in two directions at once:
--   ① it STORES a runner coordinate — 개인위치정보 at rest, on `runners`, a table that is
--      anon-readable by RLS and had no column grants. So half the pins here are not about the
--      band at all; they are about the column not becoming a public map of where runners live;
--   ② a distance band is an ANNULUS, and annuli intersect. ⚠ THIS SUITE'S FIRST VERSION SAID
--      「the quantization is the whole defence」 AND THAT WAS MEASURED FALSE on 2026-08-25: the
--      blind review drove 323 probes through the two real RPCs and localized a stranger's pickup
--      to 8.8 m, ~125× below the lattice the header promised, with 4 base changes already beating
--      the 동. Coarsening the band EDGES was measured across five designs and buys nothing — the
--      number of distinct annulus CENTRES is what resolves the target. So the defence is the
--      COOLDOWN on base changes (0123 §4b/§5), and this suite pins the two separately:
--      quantization as a stored FACT (P8, one observation's resolution) and the change RATE as
--      behaviour (P13/P14/P15) plus the disclosure it actually bounds (P16).
-- And the standing failure direction both slices share: a green suite that measures nothing
-- because the value never flows (the 0065 W6 near-miss — `to_jsonb` emits NULL-valued keys, so
-- a key-set assertion alone stays green under a body returning constants). Every positive pin
-- here therefore asserts a VALUE against a fixture at a KNOWN separation.
--
-- House law observed: pins BOTH ways · fixtures and any write more than one pin depends on live
-- at TOP LEVEL, outside every exception block (151's recorded lesson) · every `set local role`
-- arm resets the role on BOTH paths (98 H2's idiom) · absent and foreign must be
-- indistinguishable (0054:73) · this suite runs last and still closes its own
-- matching/runner_pending rows at the end so it cannot pollute an open pool (80/98/157).
--
-- ─── THE FIXTURE GEOMETRY, stated once so every band pin is checkable by hand ──────────────
-- rA's base (after quantization) = (37.51, 127.00). One degree of latitude = 2πR/360 with
-- R = 6,371,000 m (0082 §D's constant) = 111,194.9 m. Every fixture address sits due NORTH of
-- rA's base, so the separation is a pure latitude delta and needs no cosine:
--     +0.005° → 555.97 m   → '~1km'    (nearest boundary 1,000 m — 444 m of margin)
--     +0.010° → 1,111.9 m  → '1-2km'   (nearest boundary 1,000 m — 112 m)
--     +0.020° → 2,223.9 m  → '2-3km'   (nearest boundary 2,000 m — 224 m)
--     +0.040° → 4,447.8 m  → '3-5km'   (nearest boundary 5,000 m — 552 m)
--     +0.100° → 11,119.5 m → '5km+'
-- Margins are named because they are what makes these pins robust to the float arithmetic
-- rather than to a rounding accident; the tightest is 112 m, ~10% of its band.
--
-- 🔴 rB's base is (37.55, 127.00) — a DIFFERENT vertex, and that is a fix-round change with a
-- reason (review MAJOR-1a / mutation X1). Every runner fixture used to share (37.51, 127.00), so
-- NO pin in this suite could tell 「measured from the CALLER'S base」 from 「measured from a
-- hardcoded 37.51,127.00」 — the reviewer hardcoded exactly that constant into §8 and the whole
-- suite stayed green. Distances from rB, same pure-latitude arithmetic:
--     ad_1  37.515 → 0.035° → 3,891.8 m  → '3-5km'
--     ad_2  37.520 → 0.030° → 3,335.8 m  → '3-5km'   ← P12ⓐ's arm (rA reads '1-2km' here)
--     ad_3  37.530 → 0.020° → 2,223.9 m  → '2-3km'
--     ad_5  37.550 → 0.000° →     0.0 m  → '~1km'
--     ad_far 37.610 → 0.060° → 6,671.7 m → '5km+'
-- ⚠ P4's control band moved from '1-2km' to '3-5km' for exactly this reason. The pin did not get
-- weaker: it still asserts a VALUE on b_dec for the non-decliner, and now that value is one only
-- rB's own base can produce.
--
-- ─── THE COOLDOWN AND WHY FIXTURES PERFORM SURGERY ON base_set_at ──────────────────────────
-- 0123 §5 now allows ONE successful base change per _base_change_cooldown() (7 days — Sean's
-- ruling 2026-08-25, T1). Pins name the FUNCTION, not the number, everywhere it is possible to;
-- the two places a literal is unavoidable (P14's clock-aging surgery, P14's precondition) use
-- 8 days / 7 days and say so, so moving the ruling moves exactly two lines in this file.
-- Pins that need to observe the WRITER repeatedly (P8's quantization arms, P9's stage restores)
-- are not measuring the cooldown and must not be blocked by it, so they clear the clock with a
-- top-level `update runners set base_set_at = null` as postgres. That is legitimate fixture
-- surgery and it is not a hole: §3's guard refuses that same UPDATE for authenticated/anon and
-- N7ⓘ measures it. The cooldown ITSELF is measured WITHOUT any surgery by P13, and its expiry is
-- measured with the one surgery that is the point of the pin (P14 ages the stamp by 8 days).
--
-- ─── MUTATION MAP ───────────────────────────────────────────────────────────────────────────
--     ⚠ MIXED PROVENANCE, and each line says which it is. M1–M28 were written as HYPOTHESES by
--     the building session, which did not run the harness. M29–M37 were added by the 2026-08-25
--     FIX ROUND and every one of them was EXECUTED against a live cluster; where a fix round
--     mutation was measured the line says [MEASURED] and gives the observed red set. The three
--     reviewer mutations that motivated this round (X1/X2/X3) are recorded at the bottom with
--     their before/after, because "the pin now catches it" is the only evidence a fix round can
--     offer that is worth anything.
--   M1  §8 body returns a constant band ('1-2km') for every row      → RED=[P1] (four of five arms)
--   M2  §8 `_distance_band(...)` → the raw metres through the text column
--                                                                    → RED=[P1, N6ⓑ]
--       (N1 stays GREEN — the declared TYPE is still text; 0122's blind review measured exactly
--        this asymmetry when `a.dong` became `a.addr`, and it is why N6 exists at all)
--   M3  §8's base subquery loses `and r.base_lat is not null`        → RED=[P2ⓐ]
--       (a base-less runner would get rows with NULL bands instead of no rows — the client's
--        settings door and its leg-failure silence become the same picture)
--   M4  §8 arm ⓐ re-typed as a literal predicate copy omitting the 0056 decline term
--                                                                    → RED=[P4ⓐ]
--   M5  §8 loses arm ⓑ (the directed UNION)                          → RED=[P6ⓐ]
--   M6  §8 arm ⓑ loses `club_session_id is null`                     → RED=[P5ⓑ]
--   M7  §8 arm ⓑ loses `b2.runner_id = auth.uid()`                   → RED=[P6ⓑ]
--   M8  §8 `left join addresses` → inner `join`                      → RED=[P7ⓐ, P7ⓒ]
--       (P7ⓑ — an address row present with a NULL pin — SURVIVES an inner join; that
--        disjointness is exactly why the three arms are separate)
--   M9  §8 drops the `a.owner_id = b.owner_id` poison check          → RED=[P7ⓒ]
--   M10 §5 `round(p_lat, 2)` → `p_lat` (quantization deleted)        → RED=[P8ⓐ]
--       ⚠ predicted to redden P8ⓐ ONLY — the runners_base_grid CHECK would ALSO refuse the
--       unrounded value, so the mutation may instead surface as a 23514 inside set_runner_base
--       and redden P8ⓐ by exception rather than by inequality. Named both ways so the
--       measurement can say which, because "the belt caught it" is a different finding from
--       "the writer caught it".
--   M11 `runners_base_grid` CHECK dropped                            → RED=[P8ⓒ] alone
--       (P8ⓐ stays green — §5 still rounds; this is the belt, and a belt with no pin is a
--        claim, which is 157 F's measured lesson)
--   M12 §3 trigger never attached                                    → RED=[N7ⓓ, N7ⓔ, N7ⓕ]
--   M13 §3 guard's row-level `is distinct from` → `<>` on each column → RED=[N7ⓕ] alone
--       (`<>` is NULL-blind: a client could ERASE a base it cannot write)
--   M14/M15/M16 — SUPERSEDED at the landing merge (2026-08-25): §2 no longer carries a revoke
--       or a whitelist (0121 §O owns the grant; the four new columns are sealed by
--       construction). Their properties moved to M39-M42 below, re-measured against the
--       rewritten §2 + the literal-11 ⓗ.
--   M17 §4 trigger never attached                                    → RED=[150 acd P2 (the
--       end-to-end arm this slice adds there), 158 P10ⓐ, 158 P10ⓑ]
--   M18 §4's WHEN clause loosened to fire on every profiles UPDATE   → PREDICTED GREEN — a
--       performance regression, not a correctness one. Recorded as a predicted no-op rather
--       than omitted (0119 M9's precedent).
--   M19 §5's party gate (`exists … runners`) deleted                 → RED=[P9ⓐ]
--   M20 §5's `not_signed_in` guard deleted                           → RED=[P9ⓑ]
--       (auth.uid() NULL would make `profile_id = null` update zero rows and return quietly —
--        a success answer for a write that did not happen)
--   M21 §6 `my_runner_base` drops `r.profile_id = auth.uid()`        → RED=[P11]
--   M22 `grant execute on open_request_distance() to anon`           → RED=[N2ⓐ] and,
--       predicted from 157's measured C, 0057 §1's schema-wide anon sweep (99 S1) co-fires.
--       Named as a prediction of a CO-FIRE because 157's map under-predicted exactly this.
--   M23 §8 loses `set search_path = public, pg_temp`                 → RED=[N3ⓒ] and 98 H1
--   M24 §8 `stable` → `volatile`                                     → RED=[N5ⓐ]
--   M25 §8 widened: `returns table (…, dist_m double precision)`     → RED=[N1]
--   M26 `open_request_pickup_dong` (0122 §3) recreated with a third band column
--                                                                    → RED=[N4ⓐ]
--   M27 `booking_pickup_address` (0060/0065) recreated with a sixth column
--                                                                    → RED=[N4ⓑ]
--   M28 §7's `'~1km'` boundary moved from 1000 to 1500               → RED=[P1ⓑ]
--       (the +0.010° fixture at 1,111.9 m would drop a band)
--   ── FIX ROUND 2026-08-25 — every line below was EXECUTED. Clean run = **863 pass / 0 fail** ──
--   M29 §5's cooldown block deleted entirely            → 858/5  RED=[P13ⓑ+ⓒ, P14ⓑ, P15ⓐ+ⓑ,
--       P16ⓑ, N7's post-check] — a broad superset, and the breadth IS the finding: with the
--       cooldown gone, P16's refused probe SUCCEEDS, which moves rA's stored centre, which is
--       what N7's after-state check then reports. Five pins have to lie at once to hide it.
--   M30 §5's clear arm made to reset the clock
--       (`… base_lat=null, base_lng=null, base_set_at=null`) → 862/1 RED=[P13ⓒ] ALONE, exactly
--       as predicted. This is the bypass (지웠다 다시 찍기) and it is invisible to every other
--       pin in the file — P13ⓑ stays green because the PLAIN re-set is still refused. A suite
--       without ⓒ would ship a cooldown that any runner turns off with one extra tap.
--   M31 §5 stamps base_set_at, does NOT increment count  → 860/3 RED=[P13ⓐ(전제), P15ⓐ, N7ⓙ]
--       ⚠ N7ⓙ reddening is a MEASURED SURPRISE worth keeping: §3's guard fires on CHANGE
--       (`is distinct from`), so with the counter frozen at 0 the client's `set base_change_count
--       = 0` is a no-op UPDATE, the guard correctly does not fire, and the pin reads that as the
--       write having succeeded. The guard is not weaker than it looks; the pin cannot tell a
--       permitted no-op from a permitted write, and under this mutation there is nothing to tell.
--   M32a §5 increments the counter and THEN raises       → 863/0 **PREDICTED RED, MEASURED
--       NO-OP** — and this refutation is why P15ⓑ is shaped the way it is. `raise` aborts the
--       call, the increment rolls back with it, and that is equally true in production where
--       PostgREST gives every RPC its own transaction. "Counts attempts" is not merely unbuilt,
--       it is UNREACHABLE through a raising refusal. Recorded rather than dropped (0119 M9's
--       precedent: a mutation that cannot happen is a finding about the design, not a gap).
--   M32b §5 counts the attempt and refuses SILENTLY      → 859/4 RED=[P13ⓑ+ⓒ, P14ⓑ, P15ⓐ+ⓑ,
--       P16ⓑ] — the reachable shape of the same idea, and P15ⓑ does catch it.
--   M33 §5's party gate loses `and p.deleted_at is null` → 862/1 RED=[P12ⓓ] alone
--   M34 §8's distance source hardcoded to (37.51,127.00) — **the reviewer's X1, which the
--       pre-fix suite passed 863/0** → 862/2 RED=[P4, P12ⓐ]. P4 co-fires only because rB now
--       sits on its own vertex; before the fixture change BOTH of those pins were green.
--   M35 — SUPERSEDED with M14-M16 (above); the photos over-revoke is now M39.
--   X3  150's `t_acd_rich` base_lat fixture line deleted — **the reviewer's X3, previously
--       green** → 862/1 RED=[acd P2] 「픽스처 전제 붕괴」. The vacuous-green door is shut.
--   M39 `revoke select (photos) on runners from authenticated` (post-rewrite analog of the
--       reviewer's X2) → 890/2 RED=[156 P6(f) whitelist-lost, N7ⓗ 「누락={photos}」]
--   M40 `grant select (commission_rate, funnel_step) … to authenticated` (the silent-revert
--       direction, two columns) → 890/2 RED=[156 P6(e) rate-readable, N7ⓗ 「초과=
--       {commission_rate,funnel_step}」] — two independent alarms, one per owner.
--   M41 `revoke select (tier) … from authenticated` → 881/11 — ⓒ+ⓗ(누락={tier}) plus a
--       measured storefront cascade: [pcg G1,G3,G4 · pwg W1,W2,W4,W5,W6 · acd N5 ·
--       156 P6(f)] all die on `permission denied for table runners`. An over-revoke is the
--       LOUD direction; the quiet direction is M40's, which is why ⓗ exists.
--   M42 `grant select (base_lat, base_lng) … to anon, authenticated` (the modern M15) →
--       891/1 RED=[N7 one line: ⓐ anon read a base · ⓑ authenticated read a foreign base ·
--       ⓗ 초과={base_lat,base_lng}] — the core privacy pins keep their own measured red.
--   M-escape: the DELETED §2 itself (22-column regrant, this branch's original state) was
--       measured against the rewritten pins during the landing merge: ⓗ 「초과=」 the full
--       eleven-column set + 156 P6(e) — i.e. the literal-11 pin catches the exact escape that
--       reached the first merged run, from both watchers. (The computed all-minus-4 form of ⓗ
--       had CERTIFIED that state as correct — the reason the expectation is now a literal.)
--   M36 §3's guard tuple narrowed back to (base_lat, base_lng) → 862/1 RED=[N7ⓘ, N7ⓙ] — the
--       load-bearing one. Observed detail: base_set_at was rewritten to 2023-11-30, i.e. the
--       client had just granted itself an unlimited supply of annulus centres.
--   M37 §4's tombstone stops clearing base_set_at/count  → 862/1 RED=[P10ⓒ] alone
--   M38 §4's `revoke execute on _runner_base_tombstone` deleted → 862/1 RED=[99 S1] — NOT a pin
--       in this suite. Measured on the first fix-round run before it was written: flipping the
--       trigger to SECURITY DEFINER hands PUBLIC an EXECUTE grant, and 0057 §1's schema-wide
--       sweep counts trigger functions too. Recorded here because the next person to flip an
--       invoker trigger to definer will hit it, and the sweep will be the only thing that says so.
set client_min_messages = warning;

do $$
declare
  oo uuid; zz uuid;                              -- owner · foreign owner (poisoned address)
  rA uuid; rB uuid; rApp uuid; rNo uuid; rDel uuid;
  rCd uuid;                                      -- 쿨다운 전용 픽스처 (P13~P15) — rA 무대를 안 건드린다
  dg uuid; rt uuid;
  ad_1 uuid; ad_2 uuid; ad_3 uuid; ad_5 uuid; ad_far uuid;
  ad_nopin uuid; ad_poison uuid;
  clb uuid; cs uuid;
  b_1 uuid; b_2 uuid; b_3 uuid; b_5 uuid; b_far uuid;
  b_dec uuid; b_club uuid; b_dir uuid; b_dirclub uuid;
  b_nopin uuid; b_poison uuid; b_noaddr uuid;
  b_win uuid; b_out uuid;                        -- N4ⓑ의 실동작 대조군 (24h 창 안 · 창 밖)
  v_n int; v_n2 int; v_n3 int;
  v_pre_r int; v_pre_bk int; v_post_r int; v_post_bk int;
  v_b1 text; v_b2 text; v_b3 text; v_b5 text; v_bf text;
  v_txt text; v_txt2 text; v_bad text; v_src text; v_vol text;
  v_lat numeric; v_lng numeric; v_lat2 numeric; v_lng2 numeric;
  v_ts timestamptz; v_ts2 timestamptz; v_cnt int; v_cnt2 int;
  v_cols text[]; v_keys text[]; v_types text[]; v_cols2 text[]; v_bands text[];
  v_exp_cols  text[] := array['booking_id', 'distance_band'];      -- 0123 §8's whole contract
  v_exp_types text[] := array['uuid', 'text'];
  v_exp_dong  text[] := array['booking_id', 'pickup_dong'];        -- 0122 §3, must not move
  v_exp_pickup text[] := array['label', 'addr', 'detail', 'lat', 'lng'];  -- 0065's sealed shape
  v_vocab text[] := array['~1km', '1-2km', '2-3km', '3-5km', '5km+'];
  v_t timestamptz := timestamptz '2026-12-10 10:00:00+09';  -- fixed window, disjoint from 157
begin
  -- ═══ 시드 (TOP LEVEL — 151의 교훈: 두 핀 이상이 의존하는 쓰기는 예외 블록 밖에서 산다) ═══
  oo := t_user('rbd_oo', 'owner');
  zz := t_user('rbd_zz', 'owner');
  rA := t_user('rbd_rA', 'runner');       -- 기준 위치 있음 (주역)
  rB := t_user('rbd_rB', 'runner');       -- 기준 위치 있음 (대조군)
  rApp := t_user('rbd_rApp', 'runner');   -- 기준 위치 있음 + applicant → 창은 0행이어야 한다
  rNo := t_user('rbd_rNo', 'runner');     -- 기준 위치 **없음**
  rDel := t_user('rbd_rDel', 'runner');   -- 기준 위치 있음 → 계정 삭제 (P10)
  rCd := t_user('rbd_rCd', 'runner');     -- 쿨다운 전용 (P13~P15) — 이 러너의 시계만 움직인다
  update runners set tier = 'applicant' where profile_id = rApp;   -- is_active_runner() = false
  dg := t_dog(oo, '거리견'); rt := t_route('거리 확인 코스');

  -- 기준 위치는 **쓰기 경로로** 심는다 — 직접 UPDATE로 심으면 §5(양자화·게이트)를 우회한 값이
  -- 무대가 되고, 그 순간 P1의 밴드는 「저장된 값이 맞다」가 아니라 「내가 넣은 값이 맞다」가 된다.
  perform set_config('request.jwt.claim.sub', rA::text, false);
  perform set_runner_base(37.5100, 127.0000);
  -- 🔴 rB는 **다른 격자 꼭짓점**이다. 전원이 같은 기준점을 쓰면 이 스위트의 어떤 핀도
  -- 「호출자의 기준점에서 쟀다」와 「37.51,127.00을 하드코딩했다」를 구분하지 못한다 —
  -- 리뷰가 실제로 그 상수를 §8에 박아 넣었고 스위트는 전부 초록이었다 (X1). P12ⓐ가 그 구멍이다.
  perform set_config('request.jwt.claim.sub', rB::text, false);
  perform set_runner_base(37.5500, 127.0000);
  perform set_config('request.jwt.claim.sub', rApp::text, false);
  perform set_runner_base(37.5100, 127.0000);
  perform set_config('request.jwt.claim.sub', rDel::text, false);
  perform set_runner_base(37.5100, 127.0000);
  perform set_config('request.jwt.claim.sub', rCd::text, false);
  perform set_runner_base(37.5100, 127.0000);   -- 최초 설정 — 쿨다운은 언제나 이걸 허용한다 (P13ⓒ)
  -- rNo 는 의도적으로 호출하지 않는다 (P2)

  -- 주소 — 전부 기준점 정북(경도 동일). ad_1 은 REAL gate code·메모·동까지 갖는다: 없으면
  -- N1의 누수 스캔이 「샐 게 없어서 초록」이 된다 (100 W6 픽스처 노트의 함정).
  insert into addresses (owner_id, label, addr, detail, gate_code_enc, lat, lng, dong)
    values (oo, '가까운 집', '서울 서초구 신반포로 1', '101동 1203호', 'ENC::절대노출금지',
            37.515000, 127.000000, '반포동')
    returning id into ad_1;                                  -- +0.005° → 556 m
  insert into addresses (owner_id, label, addr, lat, lng)
    values (oo, '1km 집', '서울 서초구 신반포로 2', 37.520000, 127.000000)
    returning id into ad_2;                                  -- +0.010° → 1,112 m
  insert into addresses (owner_id, label, addr, lat, lng)
    values (oo, '2km 집', '서울 서초구 신반포로 3', 37.530000, 127.000000)
    returning id into ad_3;                                  -- +0.020° → 2,224 m
  insert into addresses (owner_id, label, addr, lat, lng)
    values (oo, '4km 집', '서울 서초구 신반포로 4', 37.550000, 127.000000)
    returning id into ad_5;                                  -- +0.040° → 4,448 m
  insert into addresses (owner_id, label, addr, lat, lng)
    values (oo, '먼 집', '서울 서초구 신반포로 5', 37.610000, 127.000000)
    returning id into ad_far;                                -- +0.100° → 11,120 m
  -- 핀이 없는 주소 (프로덕션 1일차의 실상태). **있는 행 · NULL 값**이어야 한다 — 없는 행도,
  -- 추측한 좌표도 아니다.
  insert into addresses (owner_id, label, addr)
    values (oo, '핀 없는 집', '서울 서초구 신반포로 6')
    returning id into ad_nopin;
  -- 오염된 행: 주소는 zz의 것인데 부킹은 oo의 것 (0060이 기록한 바로 그 경우)
  insert into addresses (owner_id, label, addr, lat, lng)
    values (zz, '남의 집', '서울 강남구 테헤란로 1', 37.500000, 127.030000)
    returning id into ad_poison;

  b_1       := t_av_booking(oo, dg, rt, null, v_t,                         5.0, 'matching');
  b_2       := t_av_booking(oo, dg, rt, null, v_t + interval '1 day',      5.0, 'matching');
  b_3       := t_av_booking(oo, dg, rt, null, v_t + interval '2 days',     5.0, 'matching');
  b_5       := t_av_booking(oo, dg, rt, null, v_t + interval '3 days',     5.0, 'matching');
  b_far     := t_av_booking(oo, dg, rt, null, v_t + interval '4 days',     5.0, 'matching');
  b_dec     := t_av_booking(oo, dg, rt, null, v_t + interval '5 days',     5.0, 'matching');
  b_club    := t_av_booking(oo, dg, rt, null, v_t + interval '6 days',     5.0, 'matching');
  b_nopin   := t_av_booking(oo, dg, rt, null, v_t + interval '7 days',     5.0, 'matching');
  b_poison  := t_av_booking(oo, dg, rt, null, v_t + interval '8 days',     5.0, 'matching');
  b_noaddr  := t_av_booking(oo, dg, rt, null, v_t + interval '9 days',     5.0, 'matching');
  b_dir     := t_av_booking(oo, dg, rt, rA,   v_t + interval '10 days',    5.0, 'runner_pending');
  b_dirclub := t_av_booking(oo, dg, rt, rA,   v_t + interval '11 days',    5.0, 'runner_pending');
  b_win     := t_av_booking(oo, dg, rt, rA,   now() + interval '2 hours',  5.0, 'confirmed');
  b_out     := t_av_booking(oo, dg, rt, rA,   now() + interval '48 hours', 5.0, 'confirmed');

  -- address_id / club_session_id 배정은 status·runner·dog 어느 것도 건드리지 않는 postgres
  -- 세션 UPDATE라 전이 트리거도 0119 커스터디 트리거도 안 뜬다 (WHEN 절이 움직임 범위다).
  update bookings set address_id = ad_1     where id in (b_1, b_win, b_out);
  update bookings set address_id = ad_2     where id in (b_2, b_dec, b_club);
  update bookings set address_id = ad_3     where id in (b_3, b_dir, b_dirclub);
  update bookings set address_id = ad_5     where id = b_5;
  update bookings set address_id = ad_far   where id = b_far;
  update bookings set address_id = ad_nopin where id = b_nopin;
  update bookings set address_id = ad_poison where id = b_poison;
  -- b_noaddr 는 일부러 address_id NULL 유지 (P7ⓐ)

  insert into clubs (name, district, host_profile_id) values ('거리 클럽', '반포동', rB)
    returning id into clb;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
    values (clb, rB, v_t + interval '6 days', '반포 집결지') returning id into cs;
  update bookings set club_session_id = cs where id in (b_club, b_dirclub);

  insert into booking_declines (booking_id, runner_profile_id) values (b_dec, rA);

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P1] 다섯 밴드 전부 VALUE로 — 알려진 이격거리의 픽스처에 대해 사다리가 실제로 작동한다
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 값을 단언하는 이유는 0065 W6 헤더가 기록한 니어미스이고, 여기선 한 단계 더 나쁘다: 밴드는
  -- **문자열**이라 선언 타입(text)이 아무것도 막지 못한다 (0122 블라인드 리뷰의 측정 B —
  -- `a.dong → a.addr`가 N1을 통과했다). 다섯 밴드를 한 번에 보는 것이 상수 응답에 대한 방어다:
  -- 어떤 상수를 넣어도 최소 네 팔이 붉어진다.
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select x.distance_band into v_b1 from open_request_distance() x where x.booking_id = b_1;
    select x.distance_band into v_b2 from open_request_distance() x where x.booking_id = b_2;
    select x.distance_band into v_b3 from open_request_distance() x where x.booking_id = b_3;
    select x.distance_band into v_b5 from open_request_distance() x where x.booking_id = b_5;
    select x.distance_band into v_bf from open_request_distance() x where x.booking_id = b_far;
    v_bad := '';
    if v_b1 is distinct from '~1km'  then v_bad := v_bad || ' ⓐ 556m=' || coalesce(v_b1,'∅'); end if;
    if v_b2 is distinct from '1-2km' then v_bad := v_bad || ' ⓑ 1112m=' || coalesce(v_b2,'∅'); end if;
    if v_b3 is distinct from '2-3km' then v_bad := v_bad || ' ⓒ 2224m=' || coalesce(v_b3,'∅'); end if;
    if v_b5 is distinct from '3-5km' then v_bad := v_bad || ' ⓓ 4448m=' || coalesce(v_b5,'∅'); end if;
    if v_bf is distinct from '5km+'  then v_bad := v_bad || ' ⓔ 11120m=' || coalesce(v_bf,'∅'); end if;
    if v_bad = ''
      then call _pass('rbd','P1 다섯 밴드 값 — 556/1112/2224/4448/11120m → ~1km·1-2km·2-3km·3-5km·5km+ (상수 응답이면 최소 네 팔이 붉어진다)');
    else call _fail('rbd','P1 다섯 밴드 값', v_bad); end if;
  exception when others then call _fail('rbd','P1 다섯 밴드 값', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P2] 기준 위치가 없으면 0행 — NULL 밴드가 붙은 행이 아니라 **행 자체가 없다**
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 이 구분이 화면을 가른다: 0행이면 클라가 「기준 위치를 설정하면 거리도 보여요 ›」라는 진짜 문을
  -- 열 수 있고, NULL 밴드가 붙은 행이면 그 상태가 「주소에 핀이 없다」와 구분되지 않는다.
  -- 대조군 rA를 같은 순간에 재는 이유는 언제나 같다 — 「함수가 그냥 비어 있다」를 배제한다.
  begin
    perform set_config('request.jwt.claim.sub', rNo::text, false);
    select count(*) into v_n from open_request_distance();
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select count(*) into v_n2 from open_request_distance();
    if v_n = 0 and v_n2 > 0
      then call _pass('rbd','P2 기준 위치 없음 → 0행 (대조군 rA는 ' || v_n2 || '행) — NULL 밴드 행이 아니라 부재');
    else call _fail('rbd','P2 기준 위치 없음 0행',
                    'nobase=' || coalesce(v_n::text,'∅') || ' control=' || coalesce(v_n2::text,'∅')); end if;
  exception when others then call _fail('rbd','P2 기준 위치 없음 0행', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P3] 지원자(applicant)는 0행 — 그리고 이 팔은 **기준 위치를 가진 지원자**로 잰다
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- rApp에게 기준 위치를 준 것이 이 핀의 전부다. 안 줬다면 0행은 tier 게이트가 아니라 P2의
  -- 이유로 나왔을 것이고, 그건 아무것도 증명하지 않는 초록이다 (0065 W6 계열의 공허).
  -- 두 게이트가 다르다는 사실도 여기서 못박는다: §5(쓰기)는 tier를 안 보고 §8(창)은 본다.
  begin
    perform set_config('request.jwt.claim.sub', rApp::text, false);
    select count(*) into v_n from open_request_distance();
    select base_lat into v_lat from runners where profile_id = rApp;   -- 전제: 기준 위치는 있다
    perform set_config('request.jwt.claim.sub', rB::text, false);
    select count(*) into v_n2 from open_request_distance();
    if v_lat is null then
      call _fail('rbd','P3 지원자 0행', '픽스처 전제 붕괴: rApp에게 기준 위치가 없다 — 이 팔은 tier 게이트를 재지 못한다');
    elsif v_n = 0 and v_n2 > 0
      then call _pass('rbd','P3 지원자 0행 — 기준 위치를 **가진** 지원자가 0행 (대조군 certified ' || v_n2 || '행): 쓰기 게이트는 tier를 안 보고 창은 본다');
    else call _fail('rbd','P3 지원자 0행',
                    'applicant=' || coalesce(v_n::text,'∅') || ' certified=' || coalesce(v_n2::text,'∅')); end if;
  exception when others then call _fail('rbd','P3 지원자 0행', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P4] 거절 원장 상속 — 거절한 러너에게는 없고, 대조군에게는 밴드까지 온전히 있다
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 0056의 제외 술어는 러너별 사실이다. 이 핀이 지키는 건 술어가 아니라 **상속**이다: §8이 뷰를
  -- 부르는 대신 술어를 베껴 적었다면 다음 0056이 한 곳만 고치고 여기가 낡는다 (157 P3와 같은 팔).
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select count(*) into v_n from open_request_distance() x where x.booking_id = b_dec;
    perform set_config('request.jwt.claim.sub', rB::text, false);
    select count(*) into v_n2 from open_request_distance() x where x.booking_id = b_dec;
    select x.distance_band into v_txt from open_request_distance() x where x.booking_id = b_dec;
    -- ⚠ 3-5km이지 1-2km가 아니다 (픽스처 라운드 2026-08-25): rB의 기준점은 이제 (37.55,127.00)
    -- 이고 ad_2는 37.52 — 0.03° = 3,335.8 m. 값이 바뀐 이유를 여기 적는 이유는, 이 숫자가
    -- 「대조군도 밴드를 본다」에 더해 「대조군은 **자기** 기준점에서 본다」까지 재기 때문이다.
    if v_n = 0 and v_n2 = 1 and v_txt = '3-5km'
      then call _pass('rbd','P4 거절 상속 — 거절자 0행 ⟷ 대조군 1행(밴드 3-5km: rB 자기 기준점에서 잰 값)');
    else call _fail('rbd','P4 거절 상속',
                    'decliner=' || coalesce(v_n::text,'∅') || ' control=' || coalesce(v_n2::text,'∅')
                    || ' band=' || coalesce(v_txt,'∅')); end if;
  exception when others then call _fail('rbd','P4 거절 상속', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P5] 클럽 부킹은 두 팔 모두에서 부재 — ⓐ 뷰가 구조적으로 배제 · ⓑ 지명 팔이 명시적으로 배제
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- ⓑ를 따로 보는 이유: ⓐ의 배제는 뷰에서 공짜로 오지만 ⓑ는 이 파일이 직접 쓴 한 줄이고, 지워도
  -- ⓐ의 핀은 초록으로 남는다. 클럽 예약은 마켓플레이스 요청이 아니다 (0042/0117 교리).
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select count(*) into v_n  from open_request_distance() x where x.booking_id = b_club;
    select count(*) into v_n2 from open_request_distance() x where x.booking_id = b_dirclub;
    select count(*) into v_n3 from open_request_distance() x where x.booking_id = b_dir;
    if v_n = 0 and v_n2 = 0 and v_n3 = 1
      then call _pass('rbd','P5 클럽 배제 양팔 — 오픈 클럽 0행 · 지명 클럽 0행 ⟷ 같은 러너의 비클럽 지명은 1행');
    else call _fail('rbd','P5 클럽 배제 양팔',
                    'open_club=' || coalesce(v_n::text,'∅') || ' dir_club=' || coalesce(v_n2::text,'∅')
                    || ' dir_plain=' || coalesce(v_n3::text,'∅')); end if;
  exception when others then call _fail('rbd','P5 클럽 배제 양팔', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P6] 지명 행은 **지명된 사람에게만** — 값까지 확인한다
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- ⓐ 지명 팔이 통째로 사라지면 rA가 0행 · ⓑ `runner_id = auth.uid()`가 사라지면 rB가 1행.
  -- 두 방향이 서로 다른 변이를 잡는다.
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select count(*) into v_n from open_request_distance() x where x.booking_id = b_dir;
    select x.distance_band into v_txt from open_request_distance() x where x.booking_id = b_dir;
    perform set_config('request.jwt.claim.sub', rB::text, false);
    select count(*) into v_n2 from open_request_distance() x where x.booking_id = b_dir;
    if v_n = 1 and v_txt = '2-3km' and v_n2 = 0
      then call _pass('rbd','P6 지명은 지명자에게만 — rA 1행(2-3km) ⟷ rB 0행');
    else call _fail('rbd','P6 지명은 지명자에게만',
                    'nominee=' || coalesce(v_n::text,'∅') || ' band=' || coalesce(v_txt,'∅')
                    || ' other=' || coalesce(v_n2::text,'∅')); end if;
  exception when others then call _fail('rbd','P6 지명은 지명자에게만', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P7] 부재의 문법 — 주소 없음 · 핀 없음 · 오염된 행이 **전부 같은 답**을 낸다 (1행, NULL 밴드)
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 셋이 같아야 하는 이유는 프라이버시다: 다르면 「이 부킹엔 주소가 없다」가 러너에게 보이는
  -- 사실이 되고, 그건 우리가 준 적 없는 정보다 (0054:73 · 0122 §3의 같은 결정).
  -- ⓑ가 중요한 이유는 변이 M8과의 분리다 — inner join으로 후퇴하면 ⓐ·ⓒ만 사라지고 ⓑ는 산다.
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    v_bad := '';
    select count(*) into v_n  from open_request_distance() x where x.booking_id = b_noaddr;
    select x.distance_band into v_txt from open_request_distance() x where x.booking_id = b_noaddr;
    if v_n <> 1 or v_txt is not null then v_bad := v_bad || ' ⓐ 주소없음 rows=' || v_n || ' band=' || coalesce(v_txt,'∅'); end if;
    select count(*) into v_n2 from open_request_distance() x where x.booking_id = b_nopin;
    select x.distance_band into v_txt from open_request_distance() x where x.booking_id = b_nopin;
    if v_n2 <> 1 or v_txt is not null then v_bad := v_bad || ' ⓑ 핀없음 rows=' || v_n2 || ' band=' || coalesce(v_txt,'∅'); end if;
    select count(*) into v_n3 from open_request_distance() x where x.booking_id = b_poison;
    select x.distance_band into v_txt from open_request_distance() x where x.booking_id = b_poison;
    if v_n3 <> 1 or v_txt is not null then v_bad := v_bad || ' 🔴 ⓒ 오염된 주소로 거리가 계산됐다 rows=' || v_n3 || ' band=' || coalesce(v_txt,'∅'); end if;
    if v_bad = ''
      then call _pass('rbd','P7 부재의 문법 — 주소없음·핀없음·오염 셋 다 1행 NULL 밴드 (구분 불가)');
    else call _fail('rbd','P7 부재의 문법', v_bad); end if;
  exception when others then call _fail('rbd','P7 부재의 문법', sqlerrm);
  end;

  -- ═══ [P8] 양자화는 실재한다 — 저장된 값으로 확인한다 (반다변측량 계약의 전부) ═══════════════
  -- 이 핀이 없으면 0123은 **러너가 자기 기준점을 옮겨가며 남의 픽업 지점을 삼각측량하는 도구**다.
  -- 밴드는 고리(annulus)이고 고리는 교차한다. 0.01° 격자가 유일한 방어이므로, 함수의 성질이
  -- 아니라 **저장된 사실**로 잰다: 세 팔 — ⓐ 다른 입력이 같은 칸으로 접힌다 · ⓑ 다른 칸은
  -- 실제로 다르다(ⓐ가 「전부 같은 상수」로도 초록이 되는 것을 막는다) · ⓒ 격자를 벗어난 값은
  -- **서버 역할로도** 저장되지 않는다(CHECK 벨트 — 벨트에 핀이 없으면 주장일 뿐이다, 157 F).
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rA::text, false);
    -- 🔴 쿨다운 해제는 **픽스처 수술**이다. 이 핀은 양자화를 재지 쿨다운을 재지 않는데, §5는
    -- 이제 7일에 한 번만 성공하므로 양자화를 네 번 관찰하려면 시계를 네 번 되돌려야 한다.
    -- postgres 세션의 직접 UPDATE이고 §3 가드는 authenticated/anon만 막으므로 통과한다 —
    -- 클라가 같은 UPDATE를 못 한다는 사실 자체는 N7ⓘ가 따로 잰다. 쿨다운은 P13이 **수술 없이**
    -- 잰다. 수술을 pin 안에 숨기지 않고 이렇게 적는 이유는, 숨기면 다음 사람이 이 핀을 보고
    -- 「쿨다운이 없나 보다」라고 읽기 때문이다.
    update runners set base_set_at = null where profile_id = rA;
    -- ⓐ 0.004° 떨어진 두 입력 → 같은 저장값
    perform set_runner_base(37.5080, 127.0040);
    select base_lat, base_lng into v_lat, v_lng from runners where profile_id = rA;
    update runners set base_set_at = null where profile_id = rA;
    perform set_runner_base(37.5120, 127.0000);
    select base_lat, base_lng into v_lat2, v_lng2 from runners where profile_id = rA;
    if v_lat is distinct from v_lat2 or v_lng is distinct from v_lng2 then
      v_bad := v_bad || ' 🔴 ⓐ 0.004° 차이가 다른 값으로 저장됐다 (' || coalesce(v_lat::text,'∅') || ',' || coalesce(v_lng::text,'∅')
               || ') vs (' || coalesce(v_lat2::text,'∅') || ',' || coalesce(v_lng2::text,'∅') || ')';
    end if;
    if v_lat is distinct from 37.51 or v_lng is distinct from 127.00 then
      v_bad := v_bad || ' ⓐ 접힌 칸이 예상과 다르다=' || coalesce(v_lat::text,'∅') || ',' || coalesce(v_lng::text,'∅');
    end if;
    -- ⓑ 다른 칸은 다르다 — ⓐ가 「무엇을 넣든 상수」로 초록이 되는 것을 막는 대조군
    update runners set base_set_at = null where profile_id = rA;
    perform set_runner_base(37.5160, 127.0000);
    select base_lat into v_lat2 from runners where profile_id = rA;
    if v_lat2 is not distinct from v_lat then
      v_bad := v_bad || ' 🔴 ⓑ 다른 격자칸(37.516→37.52)이 같은 값으로 접혔다 — 상수 저장';
    end if;
    if v_lat2 is distinct from 37.52 then
      v_bad := v_bad || ' ⓑ 다른 칸 값이 예상과 다르다=' || coalesce(v_lat2::text,'∅'); end if;
    -- ⓒ CHECK 벨트: service_role 로도 격자 밖 값은 못 넣는다 (§3 트리거는 클라만 막는다)
    begin
      set local role service_role;
      execute 'update runners set base_lat = 37.512345, base_lng = 127.0 where profile_id = $1' using rA;
      v_bad := v_bad || ' 🔴 ⓒ 격자 밖 6dp 좌표가 저장됐다 (runners_base_grid 부재 = 다변측량 해상도 복귀)';
      reset role;
    exception when others then
      reset role;
      if sqlerrm !~ 'runners_base_grid' then v_bad := v_bad || ' ⓒ 예외가 격자 CHECK가 아니다: ' || sqlerrm; end if;
    end;
    -- 무대 원복 — 이후 핀들이 (37.51, 127.00) 기준을 쓴다
    perform set_config('request.jwt.claim.sub', rA::text, false);
    update runners set base_set_at = null where profile_id = rA;
    perform set_runner_base(37.5100, 127.0000);
    select base_lat, base_lng into v_lat, v_lng from runners where profile_id = rA;
    if v_lat is distinct from 37.51 or v_lng is distinct from 127.00 then
      v_bad := v_bad || ' 정리 실패: base=' || coalesce(v_lat::text,'∅') || ',' || coalesce(v_lng::text,'∅'); end if;
    if v_bad = ''
      then call _pass('rbd','P8 양자화 실재 — 0.004° 차이는 같은 칸(37.51,127.00)으로 접히고, 다른 칸은 실제로 다르며, 격자 밖 값은 service_role로도 CHECK가 거절한다');
    else call _fail('rbd','P8 양자화 실재', v_bad); end if;
  exception when others then
    begin reset role; exception when others then null; end;
    call _fail('rbd','P8 양자화 실재', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P9] 쓰기 게이트 — 러너가 아니면 거절 · JWT 없으면 거절 · 반쪽/범위 밖 거절 · (NULL,NULL) 해제
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- ⓑ가 특히 조용한 실패를 막는다: `not_signed_in`이 없으면 `profile_id = null`이 0행을 갱신하고
  -- 함수는 **성공한 척** 돌아온다 — 일어나지 않은 쓰기에 대한 성공 응답.
  begin
    v_bad := '';
    begin  -- ⓐ 보호자(러너 행 없음)
      perform set_config('request.jwt.claim.sub', oo::text, false);
      perform set_runner_base(37.5100, 127.0000);
      v_bad := v_bad || ' 🔴 ⓐ 러너가 아닌 계정이 기준 위치를 저장했다';
    exception when others then
      if sqlerrm !~ 'not_a_runner' then v_bad := v_bad || ' ⓐ 예외가 파티 게이트가 아니다: ' || sqlerrm; end if;
    end;
    begin  -- ⓑ JWT 없음
      perform set_config('request.jwt.claim.sub', '', false);
      perform set_runner_base(37.5100, 127.0000);
      v_bad := v_bad || ' 🔴 ⓑ JWT 없는 호출이 조용히 성공했다 (0행 갱신 = 일어나지 않은 쓰기)';
    exception when others then
      if sqlerrm !~ 'not_signed_in' then v_bad := v_bad || ' ⓑ 예외가 not_signed_in이 아니다: ' || sqlerrm; end if;
    end;
    perform set_config('request.jwt.claim.sub', rB::text, false);
    begin  -- ⓒ 반쪽 좌표 — 23514가 아니라 이름 붙은 거절이어야 한다 (클라가 한국어 문장으로 바꾼다)
      perform set_runner_base(37.5100, null);
      v_bad := v_bad || ' 🔴 ⓒ 반쪽 좌표가 통과했다';
    exception when others then
      if sqlerrm !~ 'base_half_pair' then v_bad := v_bad || ' ⓒ 예외가 base_half_pair가 아니다: ' || sqlerrm; end if;
    end;
    begin  -- ⓓ 범위 밖 (도쿄)
      perform set_runner_base(35.6800, 139.7700);
      v_bad := v_bad || ' 🔴 ⓓ 서비스 지역 밖 좌표가 저장됐다';
    exception when others then
      if sqlerrm !~ 'base_out_of_bounds' then v_bad := v_bad || ' ⓓ 예외가 범위 게이트가 아니다: ' || sqlerrm; end if;
    end;
    -- ⓔ (NULL, NULL) 해제 — 러너는 기준 위치를 **뺄 수 있어야 한다** (Sean: switch this address)
    perform set_runner_base(null, null);
    select base_lat, base_lng into v_lat, v_lng from runners where profile_id = rB;
    if v_lat is not null or v_lng is not null then
      v_bad := v_bad || ' 🔴 ⓔ (NULL,NULL)이 기준 위치를 지우지 못했다'; end if;
    select count(*) into v_n from open_request_distance();   -- 해제 직후엔 0행 (P2와 같은 상태)
    if v_n <> 0 then v_bad := v_bad || ' ⓔ 해제 뒤에도 ' || v_n || '행이 나온다'; end if;
    -- rB 무대 원복 (P4·P12 대조군이 쓴다). 해제는 시계를 **안 되돌리므로**(§5, 그게 우회를 막는
    -- 유일한 이유다) 원복 전에 픽스처 수술이 필요하다 — 그 성질 자체는 P13ⓑ가 잰다.
    update runners set base_set_at = null where profile_id = rB;
    perform set_runner_base(37.5500, 127.0000);
    if v_bad = ''
      then call _pass('rbd','P9 쓰기 게이트 — 비러너·JWT부재·반쪽·범위밖 4종 거절 ⟷ (NULL,NULL) 해제는 실제로 지우고 창이 즉시 0행이 된다');
    else call _fail('rbd','P9 쓰기 게이트', v_bad); end if;
  exception when others then call _fail('rbd','P9 쓰기 게이트', sqlerrm);
  end;

  -- ═══ [P10] 계정 삭제 — 저장된 좌표는 계정과 함께 죽는다 (0122 BLOCKER-1 계열의 선제 차단) ═══
  -- 0122의 블라인드 리뷰는 파생 동이 `delete_my_account_tx`를 **살아남는 것**을 실측했다: 0115의
  -- 레닥션은 이름 붙은 컬럼 화이트리스트고, 나중에 생긴 컬럼을 알 수 없으며, 그 행은 FK 앵커로
  -- 영구 보존된다. 저장된 좌표는 동 라벨보다 나쁜 잔존물이므로 이 파일은 기다리지 않는다.
  -- 두 팔: ⓐ 메커니즘(툼스톤 스탬프 자체가 지운다 — 0115의 문장 순서에 의존하지 않는다)
  --        ⓑ 끝-대-끝(진짜 delete_my_account_tx). 150 스위트가 화이트리스트 팔을 함께 갖는다.
  begin
    v_bad := '';
    -- ⓐ 메커니즘: deleted_at 스탬프만으로 지워진다 (rApp — 이 팔 이후 창 핀에 안 쓰인다)
    select base_lat into v_lat from runners where profile_id = rApp;
    if v_lat is null then v_bad := v_bad || ' 픽스처 전제 붕괴: rApp에 기준 위치가 없다'; end if;
    select base_set_at into v_ts from runners where profile_id = rApp;
    if v_ts is null then v_bad := v_bad || ' 픽스처 전제 붕괴: rApp에 base_set_at이 없다'; end if;
    update profiles set deleted_at = now() where id = rApp;
    select base_lat, base_lng into v_lat, v_lng from runners where profile_id = rApp;
    if v_lat is not null or v_lng is not null then
      v_bad := v_bad || ' 🔴 ⓐ 툼스톤 스탬프 뒤에도 좌표가 남았다=' || coalesce(v_lat::text,'∅') || ',' || coalesce(v_lng::text,'∅'); end if;
    -- ⓒ 좌표만이 아니라 **속도 제한 상태까지** 죽는다. 이 팔이 따로 있는 이유: base_set_at /
    -- base_change_count는 살아 있는 계정의 패턴 가시성을 위한 것이고(0123 §1), 죽은 계정에 대해
    -- 그건 목적 없는 행동 흔적이다. 좌표만 지우는 툼스톤은 이 팔에서만 붉어진다 (M37).
    select base_set_at, base_change_count into v_ts, v_cnt from runners where profile_id = rApp;
    if v_ts is not null or v_cnt <> 0 then
      v_bad := v_bad || ' 🔴 ⓒ 툼스톤 뒤에도 변경 시각/횟수가 남았다 set_at=' || coalesce(v_ts::text,'∅')
               || ' count=' || coalesce(v_cnt::text,'∅'); end if;
    -- ⓑ 끝-대-끝: 실제 계정 삭제 경로
    select base_lat into v_lat from runners where profile_id = rDel;
    if v_lat is null then v_bad := v_bad || ' 픽스처 전제 붕괴: rDel에 기준 위치가 없다'; end if;
    perform delete_my_account_tx(rDel);
    select base_lat, base_lng into v_lat, v_lng from runners where profile_id = rDel;
    if v_lat is not null or v_lng is not null then
      v_bad := v_bad || ' 🔴 ⓑ 계정 삭제 뒤에도 좌표가 남았다=' || coalesce(v_lat::text,'∅') || ',' || coalesce(v_lng::text,'∅')
               || ' (0115:443의 "LOCATES NOTHING AND IDENTIFIES NOBODY"가 거짓이 된다)'; end if;
    if v_bad = ''
      then call _pass('rbd','P10 삭제 — 툼스톤 스탬프가 좌표 + 변경 시각/횟수 네 컬럼을 전부 지우고(메커니즘), 진짜 delete_my_account_tx도 지운다(끝-대-끝). 0115는 한 바이트도 안 고쳤다');
    else call _fail('rbd','P10 삭제', v_bad); end if;
  exception when others then call _fail('rbd','P10 삭제', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P11] 본인 조회 — my_runner_base()는 내 것만 준다 (§2가 컬럼을 닫은 뒤의 유일한 문)
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 세 상태가 서로 달라야 한다: 러너+기준있음(값 1행) · 러너+기준없음(NULL 1행) · 비러너(0행).
  -- 셋이 뭉개지면 설정 화면이 「러너가 아님」과 「아직 안 정함」을 구분하지 못한다.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select count(*) into v_n from my_runner_base();
    select x.base_lat, x.base_lng into v_lat, v_lng from my_runner_base() x;
    if v_n <> 1 or v_lat is distinct from 37.51 or v_lng is distinct from 127.00 then
      v_bad := v_bad || ' ⓐ 본인 조회 rows=' || v_n || ' base=' || coalesce(v_lat::text,'∅') || ',' || coalesce(v_lng::text,'∅'); end if;
    perform set_config('request.jwt.claim.sub', rNo::text, false);
    select count(*) into v_n2 from my_runner_base();
    select x.base_lat into v_lat2 from my_runner_base() x;
    if v_n2 <> 1 or v_lat2 is not null then
      v_bad := v_bad || ' ⓑ 기준 미설정 러너 rows=' || v_n2 || ' lat=' || coalesce(v_lat2::text,'∅') || ' (1행 NULL이어야 한다)'; end if;
    perform set_config('request.jwt.claim.sub', oo::text, false);
    select count(*) into v_n3 from my_runner_base();
    if v_n3 <> 0 then v_bad := v_bad || ' 🔴 ⓒ 비러너가 ' || v_n3 || '행을 받았다'; end if;
    perform set_config('request.jwt.claim.sub', '', false);
    begin
      select count(*) into v_n from my_runner_base();
      if v_n <> 0 then v_bad := v_bad || ' 🔴 ⓓ JWT 없는 호출이 ' || v_n || '행'; end if;
    exception when others then v_bad := v_bad || ' 🔴 ⓓ JWT 없는 호출이 예외를 던졌다 (설정 화면이 세션 경계에서 터진다): ' || sqlerrm;
    end;
    -- ⓔ 형상 — 정확히 3컬럼 {base_lat, base_lng, can_change_at}. 세 번째는 픽스 라운드에서
    -- 붙었고 목적은 하나다: §5가 쿨다운으로 거절할 수 있게 된 순간, 「이 위치로 지정」 버튼은
    -- 미리 알 수 있는 상태에서 반드시 실패하는 죽은 버튼이 된다 (CLAUDE.md 죽은 버튼 금지법).
    -- ⚠ 여기서 봉인하는 건 **원본이 안 나간다**는 쪽이다: base_set_at도 base_change_count도
    -- 컬럼으로 나가면 안 된다 (클라가 규칙을 재계산하게 되고, 규칙이 두 개가 된다).
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select array_agg(a.n order by a.o) into v_cols2
    from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality as a(n, m, o)
    where p.proname = 'my_runner_base' and p.pronamespace = 'public'::regnamespace and a.m = 't';
    if not (coalesce(array_length(v_cols2, 1), 0) = 3
            and v_cols2 @> array['base_lat','base_lng','can_change_at']
            and array['base_lat','base_lng','can_change_at'] @> v_cols2) then
      v_bad := v_bad || ' ⓔ my_runner_base 형상=' || coalesce(v_cols2::text,'∅')
               || ' (base_set_at/base_change_count가 그대로 나가면 여기서 붉어진다)'; end if;
    -- 값: 기준을 가진 rA는 미래 시각을 받고, 한 번도 안 정한 rNo는 NULL을 받는다
    select x.can_change_at into v_ts from my_runner_base() x;
    if v_ts is null or v_ts <= now() then
      v_bad := v_bad || ' ⓔ 기준을 가진 러너의 can_change_at이 미래가 아니다=' || coalesce(v_ts::text,'∅'); end if;
    perform set_config('request.jwt.claim.sub', rNo::text, false);
    select x.can_change_at into v_ts from my_runner_base() x;
    if v_ts is not null then
      v_bad := v_bad || ' ⓔ 한 번도 안 정한 러너에게 잠금 시각이 있다=' || v_ts::text; end if;
    perform set_config('request.jwt.claim.sub', rA::text, false);
    if v_bad = ''
      then call _pass('rbd','P11 본인 조회 — 기준있음 1행(값) · 기준없음 1행(NULL) · 비러너 0행 · JWT부재 0행(예외 아님) · 형상 3컬럼 {base_lat,base_lng,can_change_at}(원본 스탬프·카운터는 안 나간다)');
    else call _fail('rbd','P11 본인 조회', v_bad); end if;
  exception when others then call _fail('rbd','P11 본인 조회', sqlerrm);
  end;

  -- ═══ [P12] 거리는 **호출자 자신의** 기준점에서 잰다 (리뷰 X1이 뚫은 구멍) ═══════════════════
  -- 이 스위트의 모든 러너가 (37.51,127.00)을 공유했기 때문에, §8의 거리 원점을 그 상수로
  -- **하드코딩해도** 795줄이 전부 초록이었다. 리뷰어가 실제로 그렇게 했고 아무 핀도 안 붉어졌다.
  -- 구멍의 모양이 중요하다: 값을 단언하는 것만으로는 부족하고(P1은 값을 단언한다), 값이
  -- **누구의 것인지**를 단언해야 한다. 그러려면 서로 다른 기준점을 가진 두 호출자가 같은 부킹을
  -- 봐야 한다. ⓑ는 여기에 recompute-on-read까지 못박는다: 기준점을 옮기면 같은 부킹의 밴드가
  -- 따라 움직인다 — 프리즈 테이블이 없다는 결정이 실행 가능해지는 지점이고, requests.tsx의
  -- 「기준 위치에서 ~1km」가 읽는 순간의 사실이라는 근거다.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select x.distance_band into v_txt  from open_request_distance() x where x.booking_id = b_2;
    perform set_config('request.jwt.claim.sub', rB::text, false);
    select x.distance_band into v_txt2 from open_request_distance() x where x.booking_id = b_2;
    if v_txt is distinct from '1-2km' then
      v_bad := v_bad || ' ⓐ rA(37.51)가 본 b_2=' || coalesce(v_txt,'∅') || ' (1112m → 1-2km 이어야 한다)'; end if;
    if v_txt2 is distinct from '3-5km' then
      v_bad := v_bad || ' ⓐ rB(37.55)가 본 b_2=' || coalesce(v_txt2,'∅') || ' (3336m → 3-5km 이어야 한다)'; end if;
    if v_txt is not distinct from v_txt2 then
      v_bad := v_bad || ' 🔴 ⓐ 같은 부킹이 두 러너에게 같은 밴드다 — 거리 원점이 호출자의 기준점이 아니라 상수일 수 있다'; end if;
    -- ⓑ 기준점을 옮기면 밴드가 따라온다 (recompute-on-read · 프리즈 테이블 없음)
    update runners set base_set_at = null where profile_id = rB;    -- 픽스처 수술 (쿨다운은 P13이 잰다)
    perform set_runner_base(37.5100, 127.0000);
    select x.distance_band into v_txt2 from open_request_distance() x where x.booking_id = b_2;
    if v_txt2 is distinct from '1-2km' then
      v_bad := v_bad || ' ⓑ 기준점을 옮긴 뒤 b_2=' || coalesce(v_txt2,'∅') || ' (밴드가 현재 기준점을 안 따른다)'; end if;
    update runners set base_set_at = null where profile_id = rB;
    perform set_runner_base(37.5500, 127.0000);                     -- rB 무대 원복
    -- ⓓ 툼스톤 계정은 기준 위치를 **다시 붙일 수 없다** (§5 파티 게이트의 deleted_at 조인).
    -- P10ⓐ가 방금 rApp의 좌표를 지웠고, 게이트가 없으면 그 계정이 세션 하나로 되붙일 수 있다 —
    -- 삭제를 삭제된 사용자가 되돌리는 모양이다.
    perform set_config('request.jwt.claim.sub', rApp::text, false);
    begin
      perform set_runner_base(37.5100, 127.0000);
      v_bad := v_bad || ' 🔴 ⓓ 툼스톤 계정이 기준 위치를 다시 저장했다 (§5 파티 게이트에 deleted_at이 없다)';
    exception when others then
      if sqlerrm !~ 'not_a_runner' then v_bad := v_bad || ' ⓓ 예외가 파티 게이트가 아니다: ' || sqlerrm; end if;
    end;
    select base_lat into v_lat from runners where profile_id = rApp;
    if v_lat is not null then v_bad := v_bad || ' 🔴 ⓓ 툼스톤 계정에 좌표가 다시 생겼다=' || v_lat::text; end if;
    perform set_config('request.jwt.claim.sub', rA::text, false);
    if v_bad = ''
      then call _pass('rbd','P12 자기 기준점 — 같은 부킹이 rA(37.51)에겐 1-2km · rB(37.55)에겐 3-5km ⟷ rB의 기준점을 옮기면 밴드가 따라온다(프리즈 없음) ⟷ 툼스톤 계정은 되붙이지 못한다');
    else call _fail('rbd','P12 자기 기준점', v_bad); end if;
  exception when others then call _fail('rbd','P12 자기 기준점', sqlerrm);
  end;

  -- ═══ [P13] 쿨다운 — 이 파일의 **실제** 반다변측량 방어선 ══════════════════════════════════
  -- 왜 P8이 아니라 여기가 방어선인가: 2026-08-25 블라인드 리뷰가 두 실제 RPC를 통해 323회
  -- 관측해 남의 픽업 지점을 8.8 m까지 좁혔다 — 격자가 약속한 해상도의 ~1/125. 다섯 가지 밴드
  -- 설계에서 측정한 결론은 밴드 폭이 아니라 **서로 다른 중심의 개수**가 전부라는 것이었고,
  -- 그래서 한 계정이 단위 시간에 만들 수 있는 중심의 수를 §5가 묶는다.
  -- 세 팔, 그리고 ⓒ가 가장 중요하다 — 우회 경로이기 때문이다.
  begin
    v_bad := '';
    -- ⓐ 전제: 최초 설정은 언제나 허용된다 (rCd는 시드에서 한 번 저장했고 그게 전부다)
    select base_set_at, base_change_count into v_ts, v_cnt from runners where profile_id = rCd;
    if v_ts is null or v_cnt <> 1 then
      v_bad := v_bad || ' ⓐ 최초 설정 전제 붕괴 set_at=' || coalesce(v_ts::text,'∅') || ' count=' || coalesce(v_cnt::text,'∅'); end if;
    perform set_config('request.jwt.claim.sub', rCd::text, false);
    -- ⓑ 창 안 재설정 → 이름 붙은 거절, 그리고 저장값은 **안 움직인다**
    begin
      perform set_runner_base(37.5500, 127.0000);
      v_bad := v_bad || ' 🔴 ⓑ 쿨다운 창 안에서 기준 위치가 다시 저장됐다 (관측 횟수의 상한이 없다 = 삼각측량 가능)';
    exception when others then
      if sqlerrm !~ 'base_change_cooldown' then v_bad := v_bad || ' ⓑ 예외가 쿨다운이 아니다: ' || sqlerrm; end if;
    end;
    select base_lat into v_lat from runners where profile_id = rCd;
    if v_lat is distinct from 37.51 then
      v_bad := v_bad || ' 🔴 ⓑ 거절됐는데 값이 움직였다=' || coalesce(v_lat::text,'∅'); end if;
    -- ⓒ 🔴 우회 경로: 해제는 언제나 허용되지만 시계를 **되돌리지 않는다**. 되돌린다면
    -- 「지웠다 다시 찍기」가 쿨다운을 0으로 만들고, 이 파일의 방어선은 존재하지 않는 것과 같다.
    perform set_runner_base(null, null);                 -- 해제 자체는 쿨다운의 대상이 아니다
    select base_lat, base_set_at into v_lat, v_ts from runners where profile_id = rCd;
    if v_lat is not null then v_bad := v_bad || ' ⓒ 해제가 실패했다 (해제는 쿨다운을 받지 않는다)'; end if;
    if v_ts is null then v_bad := v_bad || ' 🔴 ⓒ 해제가 base_set_at을 지웠다 — 지웠다 다시 찍기가 쿨다운 우회로가 된다'; end if;
    begin
      perform set_runner_base(37.5500, 127.0000);
      v_bad := v_bad || ' 🔴 ⓒ 해제 뒤 재설정이 통과했다 (우회 경로가 열려 있다)';
    exception when others then
      if sqlerrm !~ 'base_change_cooldown' then v_bad := v_bad || ' ⓒ 해제 뒤 예외가 쿨다운이 아니다: ' || sqlerrm; end if;
    end;
    if v_bad = ''
      then call _pass('rbd','P13 쿨다운 — 최초 설정은 허용 ⟷ 창 안 재설정은 base_change_cooldown으로 거절되고 값도 안 움직인다 ⟷ 해제는 허용되지만 시계를 안 되돌린다(지웠다 다시 찍기 우회 차단)');
    else call _fail('rbd','P13 쿨다운', v_bad); end if;
  exception when others then call _fail('rbd','P13 쿨다운', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P14] 쿨다운 만료 — 창이 지나면 실제로 열리고, 열리자마자 **다시 닫힌다** (N=7일, T1 룰링)
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 재스탬프를 재는 이유: 스탬프 없이 쓰기만 하는 §5는 한 번 만료된 계정에게 **무제한**을 준다
  -- (base_set_at이 31일 전에 얼어붙고 모든 후속 변경이 통과한다). 그건 쿨다운이 아니라
  -- 「한 번의 대기」다. 그래서 이 핀은 성공 하나가 아니라 성공→재잠금 두 단계를 잰다.
  -- ⚠ 시계 노화는 postgres 세션의 직접 UPDATE다. service_role로 해도 결과는 같고(§3 가드는
  -- authenticated/anon만 본다), 여기서 역할을 바꾸면 reset 경로만 하나 늘 뿐 재는 게 늘지 않는다.
  -- 클라가 같은 UPDATE를 못 한다는 사실은 N7ⓘ가 따로 잰다.
  begin
    v_bad := '';
    -- 8일 = 7일 룰링(§4b) + 여유 1일. 이 파일에서 숫자가 불가피한 두 줄 중 하나다.
    update runners set base_set_at = now() - interval '8 days' where profile_id = rCd;
    select base_set_at into v_ts from runners where profile_id = rCd;
    if v_ts is null or v_ts > now() - _base_change_cooldown() then
      v_bad := v_bad || ' 전제 붕괴: 시계 노화가 안 됐다=' || coalesce(v_ts::text,'∅'); end if;
    perform set_config('request.jwt.claim.sub', rCd::text, false);
    begin
      perform set_runner_base(37.5300, 127.0000);
    exception when others then
      v_bad := v_bad || ' 🔴 ⓐ 쿨다운이 지났는데도 거절됐다: ' || sqlerrm;
    end;
    select base_lat, base_set_at into v_lat, v_ts2 from runners where profile_id = rCd;
    if v_lat is distinct from 37.53 then
      v_bad := v_bad || ' ⓐ 만료 뒤 저장값=' || coalesce(v_lat::text,'∅') || ' (37.53 이어야 한다)'; end if;
    if v_ts2 is null or v_ts2 < now() - interval '1 minute' then
      v_bad := v_bad || ' 🔴 ⓑ 성공했는데 재스탬프되지 않았다=' || coalesce(v_ts2::text,'∅') || ' — 한 번 만료된 계정이 영구 무제한이 된다'; end if;
    begin
      perform set_runner_base(37.5600, 127.0000);
      v_bad := v_bad || ' 🔴 ⓑ 방금 성공한 직후 또 성공했다 (창이 다시 닫히지 않았다)';
    exception when others then
      if sqlerrm !~ 'base_change_cooldown' then v_bad := v_bad || ' ⓑ 재잠금 예외가 쿨다운이 아니다: ' || sqlerrm; end if;
    end;
    if v_bad = ''
      then call _pass('rbd','P14 쿨다운 만료 — 창(7일, T1 룰링)이 지난 계정은 실제로 바꿀 수 있고(37.53 저장), 성공은 시각을 다시 찍어 창이 즉시 다시 닫힌다 (한 번의 대기가 아니라 주기)');
    else call _fail('rbd','P14 쿨다운 만료', v_bad); end if;
  exception when others then call _fail('rbd','P14 쿨다운 만료', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [P15] 변경 횟수 — **성공에만** 증가한다 (사후 가시성의 의미가 여기서 정해진다)
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 이 숫자가 시도를 세면 「300번 시도했지만 전부 막혔다」와 「300개의 서로 다른 중심을 만들었다」가
  -- 같은 값이 되고, ops가 그걸 보고 답할 수 있는 질문이 사라진다. 상한이 되려면 성공만 센다.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rCd::text, false);
    select base_change_count into v_cnt from runners where profile_id = rCd;
    -- ⓑ 거절(방금 P14가 창을 다시 닫았다) → 증가하지 않는다
    begin perform set_runner_base(37.5700, 127.0000); exception when others then null; end;
    select base_change_count into v_cnt2 from runners where profile_id = rCd;
    if v_cnt2 <> v_cnt then
      v_bad := v_bad || ' 🔴 ⓑ 거절인데 횟수가 늘었다 ' || v_cnt || '→' || v_cnt2; end if;
    -- ⓐ 성공 → 정확히 1 증가
    update runners set base_set_at = null where profile_id = rCd;   -- 픽스처 수술 (쿨다운은 P13/P14가 잰다)
    perform set_runner_base(37.5700, 127.0000);
    select base_change_count into v_cnt2 from runners where profile_id = rCd;
    if v_cnt2 <> v_cnt + 1 then
      v_bad := v_bad || ' 🔴 ⓐ 성공했는데 횟수가 ' || v_cnt || '→' || v_cnt2 || ' (정확히 +1이어야 한다)'; end if;
    perform set_config('request.jwt.claim.sub', rA::text, false);
    if v_bad = ''
      then call _pass('rbd','P15 변경 횟수 — 성공에 정확히 +1 ⟷ 거절에는 0 (「몇 개의 서로 다른 중심을 만들었나」가 답 가능한 질문으로 남는다)');
    else call _fail('rbd','P15 변경 횟수', v_bad); end if;
  exception when others then call _fail('rbd','P15 변경 횟수', sqlerrm);
  end;

  -- ═══ [P16] 관측 해상도 — 리뷰가 요구한 공격 모양의 핀 ═══════════════════════════════════════
  -- 다른 핀들은 전부 「쿨다운이 작동한다」를 잰다. 이 핀은 그것이 **공개량을 실제로 묶는지**를
  -- 잰다. 다변측량은 서로 다른 중심에서 얻은 고리를 교차시키는 것이므로, 한 창 안에서 러너가
  -- 무한히 호출해도 얻는 정보가 늘지 않아야 한다 — 그리고 그건 「밴드가 결정적이다」가 아니라
  -- 「새 중심을 못 만든다」로 성립한다. 두 팔이 함께 그 말을 한다:
  --   ⓐ 같은 창 안에서 N회 호출 → **바이트 동일**한 밴드 (호출 자체는 새 관측이 아니다)
  --   ⓑ 그 창 안에서 중심을 옮기려는 시도는 거절되고, 저장된 중심도 밴드도 그대로다
  -- 즉 이 계정이 이 주소에 대해 가질 수 있는 고리의 수는 쿨다운 경과 횟수로 묶인다. 주장 아니라
  -- 측정이다 (리뷰의 곡선: 1회 → ~1.9 km · 4회 → ~0.6 km · 16회 → ~0.15 km · 81회+ → 점).
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rA::text, false);
    v_bands := '{}'::text[];
    for v_n in 1..5 loop
      select x.distance_band into v_txt from open_request_distance() x where x.booking_id = b_2;
      v_bands := v_bands || coalesce(v_txt, '∅');
    end loop;
    select count(distinct b) into v_n2 from unnest(v_bands) b;
    if v_n2 <> 1 or v_bands[1] is distinct from '1-2km' then
      v_bad := v_bad || ' 🔴 ⓐ 같은 창 안 5회 호출이 서로 다른 답을 냈다=' || v_bands::text; end if;
    -- ⓑ 새 중심을 만들려는 시도 — 거절되고, 아무것도 안 움직인다
    begin
      perform set_runner_base(37.5200, 127.0000);
      v_bad := v_bad || ' 🔴 ⓑ 같은 창 안에서 새 중심을 만들 수 있었다 (관측 수의 상한이 없다)';
    exception when others then
      if sqlerrm !~ 'base_change_cooldown' then v_bad := v_bad || ' ⓑ 예외가 쿨다운이 아니다: ' || sqlerrm; end if;
    end;
    select base_lat, base_lng into v_lat, v_lng from runners where profile_id = rA;
    if v_lat is distinct from 37.51 or v_lng is distinct from 127.00 then
      v_bad := v_bad || ' 🔴 ⓑ 거절된 시도가 중심을 움직였다=' || coalesce(v_lat::text,'∅') || ',' || coalesce(v_lng::text,'∅'); end if;
    select x.distance_band into v_txt from open_request_distance() x where x.booking_id = b_2;
    if v_txt is distinct from v_bands[1] then
      v_bad := v_bad || ' 🔴 ⓑ 거절된 시도 뒤 밴드가 바뀌었다 ' || v_bands[1] || '→' || coalesce(v_txt,'∅'); end if;
    if v_bad = ''
      then call _pass('rbd','P16 관측 해상도 — 한 쿨다운 창 안에서 5회 호출이 바이트 동일(1-2km)하고, 그 창 안에서 새 중심을 만들려는 시도는 거절되며 중심도 밴드도 안 움직인다: 공개량이 호출 수가 아니라 **경과한 쿨다운 수**로 묶인다');
    else call _fail('rbd','P16 관측 해상도', v_bad); end if;
  exception when others then call _fail('rbd','P16 관측 해상도', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [N1] 반환 형상 — 선언 2컬럼 = 런타임 2키 = {booking_id, distance_band}, 좌표어 0
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- ⚠ 이 핀은 **숫자를 봉인하지 문자열을 봉인하지 않는다** (0122 블라인드 리뷰 측정 B). 밴드가
  -- 실제로 밴드인지는 P1(값)과 N6(어휘)이 지킨다. 여기가 잡는 건 컬럼이 하나 더 붙는 변이다.
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select array_agg(a.n order by a.o) into v_cols
    from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality as a(n, m, o)
    where p.proname = 'open_request_distance' and p.pronamespace = 'public'::regnamespace
      and a.m = 't';
    select array_agg(format_type(a.t, null) order by a.o) into v_types
    from pg_proc p, unnest(p.proallargtypes, p.proargmodes) with ordinality as a(t, m, o)
    where p.proname = 'open_request_distance' and p.pronamespace = 'public'::regnamespace
      and a.m = 't';
    select array_agg(k order by k) into v_keys from (
      select jsonb_object_keys(j) as k from (
        select to_jsonb(x) as j from open_request_distance() x
        where x.booking_id = b_1 limit 1) s) t;
    select count(*) into v_n
    from unnest(coalesce(v_cols, '{}'::text[]) || coalesce(v_keys, '{}'::text[])) c
    where c ~* 'lat|lng|coord|geo|addr|label|detail|gate|code|enc|owner|phone|price|fare|metre|meter|_m$|dist_m|dong';
    if coalesce(array_length(v_cols, 1), 0) = 2 and v_cols @> v_exp_cols and v_exp_cols @> v_cols
       and coalesce(array_length(v_keys, 1), 0) = 2 and v_keys @> v_exp_cols and v_exp_cols @> v_keys
       and v_types = v_exp_types and v_n = 0
      then call _pass('rbd','N1 반환 형상 — 선언 2컬럼 = 런타임 2키 = {booking_id,distance_band}, 타입 (uuid,text), 좌표·미터어 0');
    else call _fail('rbd','N1 반환 형상',
                    'proargnames=' || coalesce(v_cols::text,'∅') || ' types=' || coalesce(v_types::text,'∅')
                    || ' 런타임키=' || coalesce(v_keys::text,'∅') || ' 누수어=' || coalesce(v_n::text,'∅')); end if;
  exception when others then call _fail('rbd','N1 반환 형상', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [N2] ACL — anon 불가 · authenticated 가능 · JWT 없는 호출은 0행이지 예외가 아니다 (세 함수)
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- service_role은 EXECUTE를 **가진다**, 그리고 그건 이 파일이 준 게 아니라 Supabase(와 심)의
  -- default privileges다. 그래서 '회수했다'가 아니라 **'가져도 JWT 없이는 아무것도 안 나온다'**를
  -- 못박는다 — 그게 실제 봉인이고 회수는 벨트다 (157 N2의 같은 논증).
  begin
    v_bad := '';
    if has_function_privilege('anon', 'open_request_distance()', 'execute')
      then v_bad := v_bad || ' 🔴 anon이 거리 밴드를 조회할 수 있다'; end if;
    if has_function_privilege('anon', 'set_runner_base(numeric,numeric)', 'execute')
      then v_bad := v_bad || ' 🔴 anon이 러너 기준 위치를 쓸 수 있다'; end if;
    if has_function_privilege('anon', 'my_runner_base()', 'execute')
      then v_bad := v_bad || ' 🔴 anon이 기준 위치를 읽을 수 있다'; end if;
    if not has_function_privilege('authenticated', 'open_request_distance()', 'execute')
      then v_bad := v_bad || ' 🔴 authenticated가 창 실행 권한을 잃었다 (인박스 다리가 죽는다)'; end if;
    if not has_function_privilege('authenticated', 'set_runner_base(numeric,numeric)', 'execute')
      then v_bad := v_bad || ' 🔴 authenticated가 쓰기 권한을 잃었다 (설정 화면이 죽는다)'; end if;
    if not has_function_privilege('authenticated', 'my_runner_base()', 'execute')
      then v_bad := v_bad || ' 🔴 authenticated가 본인 조회 권한을 잃었다'; end if;
    begin  -- JWT 없는 창 호출
      perform set_config('request.jwt.claim.sub', '', false);
      select count(*) into v_n from open_request_distance();
      if v_n <> 0 then v_bad := v_bad || ' 🔴 JWT 없는 호출이 ' || v_n || '행을 돌려줬다'; end if;
    exception when others then
      v_bad := v_bad || ' 🔴 JWT 없는 호출이 예외를 던졌다 (0행이어야 한다): ' || sqlerrm;
    end;
    perform set_config('request.jwt.claim.sub', rA::text, false);   -- 무대 원복
    if v_bad = ''
      then call _pass('rbd','N2 ACL 3함수 — anon 전부 불가 · authenticated 전부 가능 · JWT 없는 창 호출은 0행(예외 아님)');
    else call _fail('rbd','N2 ACL 3함수', v_bad); end if;
  exception when others then call _fail('rbd','N2 ACL 3함수', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [N3] 본문 search_path 봉인 — definer 셋 전부 (로컬 단언; 98 H1은 전수 감시)
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- ALTER로 붙인 config는 create or replace가 초기화한다(실측, 0055/0114). 그래서 본문이다.
  begin
    v_bad := '';
    for v_txt2 in select unnest(array['set_runner_base', 'my_runner_base', 'open_request_distance']) loop
      select coalesce(array_to_string(p.proconfig, ','), '') || '|' || p.prosecdef::text into v_txt
      from pg_proc p where p.proname = v_txt2 and p.pronamespace = 'public'::regnamespace;
      if v_txt is null or v_txt not like '%search_path%' or v_txt not like '%pg_temp%' or v_txt not like '%|true' then
        v_bad := v_bad || ' ' || v_txt2 || '=' || coalesce(v_txt,'∅');
      end if;
    end loop;
    -- 트리거 함수 둘은 invoker지만 search_path는 여전히 필요하다 (0055 교리)
    for v_txt2 in select unnest(array['_guard_runner_base', '_runner_base_tombstone']) loop
      select coalesce(array_to_string(p.proconfig, ','), '') into v_txt
      from pg_proc p where p.proname = v_txt2 and p.pronamespace = 'public'::regnamespace;
      if v_txt is null or v_txt not like '%search_path%' or v_txt not like '%pg_temp%' then
        v_bad := v_bad || ' ' || v_txt2 || '=' || coalesce(v_txt,'∅');
      end if;
    end loop;
    if v_bad = ''
      then call _pass('rbd','N3 봉인 — definer 3종 secdef+본문 search_path · 트리거 함수 2종 본문 search_path');
    else call _fail('rbd','N3 봉인', v_bad); end if;
  exception when others then call _fail('rbd','N3 봉인', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [N4] 이웃한 두 창은 손대지 않았다 — ⓐ 0122 §3 · ⓑ 0060/0065의 봉인된 주소 창
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 0123을 구현하는 가장 쉬운 방법은 0122의 창에 컬럼을 하나 더 붙이는 것이었고, 그건 서로 다른
  -- 분류(개인정보 / 개인위치정보)를 한 그랜트 뒤에 합치는 일이다 — counsel Q3가 반대로 답하는 날
  -- 동 절반까지 같이 내려야 한다. 명시적으로 거절했고, 여기서 형상 + 실동작으로 확인한다.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rA::text, false);
    -- ⓐ 0122 §3: 2컬럼 그대로 + 실제로 값이 흐른다 (ad_1 의 동)
    select array_agg(a.n order by a.o) into v_cols2
    from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality as a(n, m, o)
    where p.proname = 'open_request_pickup_dong' and p.pronamespace = 'public'::regnamespace
      and a.m = 't';
    if not (coalesce(array_length(v_cols2, 1), 0) = 2 and v_cols2 @> v_exp_dong and v_exp_dong @> v_cols2)
      then v_bad := v_bad || ' 🔴 ⓐ 0122 창의 반환 컬럼이 변했다: ' || coalesce(v_cols2::text,'∅'); end if;
    select x.pickup_dong into v_txt from open_request_pickup_dong() x where x.booking_id = b_1;
    if v_txt is distinct from '반포동'
      then v_bad := v_bad || ' 🔴 ⓐ 0122 창이 더 이상 동을 돌려주지 않는다=' || coalesce(v_txt,'∅'); end if;
    -- ⓑ 0060/0065: 5컬럼 그대로 · 게이트 문구 생존 · 밴드/기준어 미주입 · 실동작 양방향
    select p.prosrc into v_src from pg_proc p
    where p.proname = 'booking_pickup_address' and p.pronamespace = 'public'::regnamespace;
    select array_agg(a.n order by a.o) into v_cols2
    from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality as a(n, m, o)
    where p.proname = 'booking_pickup_address' and p.pronamespace = 'public'::regnamespace
      and a.m = 't';
    if not (coalesce(array_length(v_cols2, 1), 0) = 5 and v_cols2 @> v_exp_pickup and v_exp_pickup @> v_cols2)
      then v_bad := v_bad || ' 🔴 ⓑ 주소 창 반환 컬럼이 변했다: ' || coalesce(v_cols2::text,'∅'); end if;
    if coalesce(v_src, '') !~ 'not_runner' then v_bad := v_bad || ' 🔴 ⓑ not_runner 게이트가 사라졌다'; end if;
    if coalesce(v_src, '') !~ '24 hours'   then v_bad := v_bad || ' 🔴 ⓑ 24h 창이 사라졌다'; end if;
    if coalesce(v_src, '') ~* 'band|base_lat|base_lng'
      then v_bad := v_bad || ' 🔴 ⓑ 0123이 봉인된 주소 창에 거리/기준 위치를 밀어 넣었다'; end if;
    begin
      perform * from booking_pickup_address(b_out);       -- 48h — 창 밖
      v_bad := v_bad || ' 🔴 ⓑ 24h 창 밖인데 주소가 나왔다';
    exception when others then
      if sqlerrm !~ 'not_runner' then v_bad := v_bad || ' ⓑ 창 밖 예외가 not_runner가 아니다: ' || sqlerrm; end if;
    end;
    select x.addr into v_txt from booking_pickup_address(b_win) x;   -- 2h — 창 안
    if v_txt is distinct from '서울 서초구 신반포로 1'
      then v_bad := v_bad || ' 🔴 ⓑ 창 안 배정 러너가 주소를 못 읽는다: ' || coalesce(v_txt,'∅'); end if;
    if v_bad = ''
      then call _pass('rbd','N4 이웃 창 무손상 — 0122 §3은 2컬럼·동 값 그대로 ⟷ 0060/0065는 5컬럼·게이트 문구·양방향 실동작 그대로');
    else call _fail('rbd','N4 이웃 창 무손상', v_bad); end if;
  exception when others then call _fail('rbd','N4 이웃 창 무손상', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [N5] 이 창은 아무것도 쓰지 않는다 — ⓐ provolatile='s' · ⓑ 호출 전후 행 수 불변
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- 0120 §E는 정반대 결정(제공 전 원장 기록 → VOLATILE)을 했다. 그 차이가 곧 이 파일의 분류
  -- 논증이다: 호출자는 **자기 기준점**에서 재고 있고 남의 위치를 받지 않는다. counsel Q3가
  -- 반대로 답하면 고칠 곳은 이 함수 하나 — 그래서 단일 초크포인트다. 결정이 조용히 뒤집히면
  -- (= 함수가 쓰기 시작하면) 여기서 터진다.
  begin
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select p.provolatile::text into v_vol from pg_proc p
    where p.proname = 'open_request_distance' and p.pronamespace = 'public'::regnamespace;
    select count(*) into v_pre_r  from runners;
    select count(*) into v_pre_bk from bookings;
    perform count(*) from open_request_distance();
    perform count(*) from open_request_distance();   -- 두 번 — 첫 호출만 쓰는 형태도 잡는다
    select count(*) into v_post_r  from runners;
    select count(*) into v_post_bk from bookings;
    if v_vol = 's' and v_pre_r = v_post_r and v_pre_bk = v_post_bk
      then call _pass('rbd','N5 무쓰기 — STABLE + 호출 전후 runners/bookings 행 수 불변 (제16조 원장 미기록이 결정이라는 사실을 실행 가능하게 만든다)');
    else call _fail('rbd','N5 무쓰기',
                    'volatile=' || coalesce(v_vol,'∅')
                    || ' runners ' || coalesce(v_pre_r::text,'∅') || '→' || coalesce(v_post_r::text,'∅')
                    || ' bookings ' || coalesce(v_pre_bk::text,'∅') || '→' || coalesce(v_post_bk::text,'∅')); end if;
  exception when others then call _fail('rbd','N5 무쓰기', sqlerrm);
  end;

  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- [N6] 어휘는 닫혀 있다 — 돌아온 밴드는 다섯 중 하나이고, 절대 숫자가 아니다
  -- ─────────────────────────────────────────────────────────────────────────────────────────
  -- N1이 못 잡는 절반이다: 선언 타입 text는 '1834' 도 '서울 서초구…' 도 통과시킨다. 미터가
  -- text 컬럼을 타고 나가는 변이(M2)를 잡는 건 이 핀뿐이다. ⓒ는 사다리 자체를 경계값으로 잰다.
  begin
    v_bad := '';
    perform set_config('request.jwt.claim.sub', rA::text, false);
    select array_agg(distinct x.distance_band) into v_bands
    from open_request_distance() x where x.distance_band is not null;
    if v_bands is null then
      v_bad := v_bad || ' 픽스처 전제 붕괴: NULL 아닌 밴드가 하나도 없다';
    else
      if not (v_vocab @> v_bands) then
        v_bad := v_bad || ' 🔴 ⓐ 어휘 밖 값=' || v_bands::text; end if;
      select count(*) into v_n from unnest(v_bands) b where b ~ '^[0-9.]+$';
      if v_n > 0 then v_bad := v_bad || ' 🔴 ⓑ 숫자로 파싱되는 밴드가 ' || v_n || '개 (미터가 새고 있다)'; end if;
    end if;
    -- ⓒ 사다리 경계 — 999/1000/1999/2000/2999/3000/4999/5000 (경계는 반열림 [下, 上))
    if _distance_band(999)   is distinct from '~1km'  then v_bad := v_bad || ' ⓒ 999m'; end if;
    if _distance_band(1000)  is distinct from '1-2km' then v_bad := v_bad || ' ⓒ 1000m'; end if;
    if _distance_band(1999)  is distinct from '1-2km' then v_bad := v_bad || ' ⓒ 1999m'; end if;
    if _distance_band(2000)  is distinct from '2-3km' then v_bad := v_bad || ' ⓒ 2000m'; end if;
    if _distance_band(2999)  is distinct from '2-3km' then v_bad := v_bad || ' ⓒ 2999m'; end if;
    if _distance_band(3000)  is distinct from '3-5km' then v_bad := v_bad || ' ⓒ 3000m'; end if;
    if _distance_band(4999)  is distinct from '3-5km' then v_bad := v_bad || ' ⓒ 4999m'; end if;
    if _distance_band(5000)  is distinct from '5km+'  then v_bad := v_bad || ' ⓒ 5000m'; end if;
    if _distance_band(null)  is not null              then v_bad := v_bad || ' ⓒ NULL 입력이 값을 냈다'; end if;
    if v_bad = ''
      then call _pass('rbd','N6 어휘 폐쇄 — 돌아온 밴드는 다섯 중 하나 · 숫자 파싱 0개 · 사다리 경계 8종 + NULL 입력');
    else call _fail('rbd','N6 어휘 폐쇄', v_bad); end if;
  exception when others then call _fail('rbd','N6 어휘 폐쇄', sqlerrm);
  end;

  -- ═══ [N7] 저장된 좌표는 읽을 수도 쓸 수도 없다 — §2 컬럼 그랜트 + §3 쓰기 봉인 ═══════════
  -- 이 핀이 이 스위트에서 가장 무겁다. `runners`는 anon 읽기가 열린 테이블이고(0093:59가 기록한
  -- 의도된 표면) RLS는 **행** 규칙이며 컬럼 그랜트는 없었다 — 0088이 profiles.phone에서 겪은
  -- 바로 그 계열. §2가 없으면 0123은 「모든 인증 러너의 집 근처」를 anon 키 하나로 공개한다.
  -- 열 팔: ⓐ anon 못 읽음 · ⓑ authenticated 본인 행도 못 읽음(그랜트는 내 행을 구분 못 한다)
  -- ⓒ 화이트리스트 컬럼은 계속 읽힌다, 실동작으로(과잉 회수 방향) · ⓓ INSERT 주입 거절
  -- ⓔ UPDATE 변경 거절 · ⓕ NULL로 지우기 거절 · ⓖ 기존 쓰기 경로(online/bio) 생존
  -- ⓗ 🔴 **집합 동등성** — 그랜트된 컬럼 = 오늘의 컬럼 − 서버 전용 4개
  -- ⓘ base_set_at 클라 쓰기 거절 (쿨다운 자체를 지우는 경로) · ⓙ base_change_count 클라 쓰기 거절.
  --
  -- ⓗ가 ⓒ를 대체하지 않고 **더한다**, 그리고 그 이유가 이 픽스 라운드의 MAJOR-2다: ⓒ는
  -- 세 컬럼만 찍어보는 스팟 체크였고 (지금은 tier/bio — commission_rate는 0121이 봉인, 156 P6
  -- 소관), 리뷰어가 화이트리스트에서
  -- `photos`를 빼자 스위트 전체가 초록으로 남았다 — 스토어프런트 읽기 하나가 조용히 죽은 채로.
  -- 화이트리스트를 감시할 수 있는 단언은 집합 동등성 하나뿐이다(양방향을 한 번에 본다). ⓒ는
  -- 카탈로그가 아니라 **실제 쿼리**라서 남긴다: 그랜트가 맞는데 RLS가 막는 경우를 ⓗ는 못 본다.
  begin
    v_bad := '';
    select base_set_at, base_change_count into v_ts, v_cnt from runners where profile_id = rA;
    begin
      set local role anon;
      perform set_config('request.jwt.claim.sub', '', true);
      begin  -- ⓐ
        execute 'select count(base_lat) from runners' into v_n;
        v_bad := v_bad || ' 🔴 ⓐ anon이 base_lat을 읽었다 (인증 러너 전원의 거주 지역 공개)';
      exception when insufficient_privilege then null;
        when others then v_bad := v_bad || ' ⓐ 예외가 권한 거부가 아니다: ' || sqlerrm; end;
      reset role;
    exception when others then reset role; v_bad := v_bad || ' anon 경로 예외:' || sqlerrm;
    end;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', rA::text, true);
      begin  -- ⓑ 본인 행도 못 읽는다 — 문은 my_runner_base()뿐 (0088의 기록된 지시)
        execute 'select count(base_lng) from runners where profile_id = $1' into v_n using rA;
        v_bad := v_bad || ' 🔴 ⓑ authenticated가 base_lng를 직접 읽었다 (그랜트는 내 행과 남의 행을 구분하지 못한다)';
      exception when insufficient_privilege then null;
        when others then v_bad := v_bad || ' ⓑ 예외가 권한 거부가 아니다: ' || sqlerrm; end;
      begin  -- ⓒ 과잉 회수 방향 — 스토어프런트 컬럼은 계속 읽혀야 한다.
        -- ⚠ commission_rate는 이 목록에서 **제거됐다** (머지, 2026-08-25): 0121이 러너 몫의
        -- 비밀 판정(Sean 「keep the margin a secret」)으로 클라 SELECT를 봉인했고, 그 봉인은
        -- 156 P6의 핀이다. 원형 ⓒ는 읽힘을 기대해서, 0121 위에서는 ⓒ 자신이 붉었다 — 견적은
        -- 이제 서버의 expected_net으로 온다 (0121 §D). 읽혀야 하는 대조군은 tier/bio.
        execute 'select count(tier) + count(bio) from runners' into v_n;
      exception when others then
        v_bad := v_bad || ' 🔴 ⓒ 화이트리스트 컬럼(tier/bio)이 막혔다 — 스토어프런트가 죽는다: ' || sqlerrm; end;
      begin  -- ⓓ INSERT 주입
        execute 'insert into runners (profile_id, base_lat, base_lng) values ($1, 37.51, 127.00)'
          using gen_random_uuid();
        v_bad := v_bad || ' 🔴 ⓓ 클라가 기준 위치를 심은 채로 러너 행을 만들 수 있다';
      exception when others then
        if sqlerrm !~ 'runner_base_definer_only' then v_bad := v_bad || ' ⓓ 예외가 가드가 아니다: ' || sqlerrm; end if;
      end;
      begin  -- ⓔ UPDATE 변경 — 양자화 우회의 정확한 경로
        execute 'update runners set base_lat = 37.512345, base_lng = 127.001234 where profile_id = $1' using rA;
        v_bad := v_bad || ' 🔴 ⓔ 클라가 6dp 기준 위치를 직접 썼다 (양자화 계약이 무너진다)';
      exception when others then
        if sqlerrm !~ 'runner_base_definer_only' then v_bad := v_bad || ' ⓔ 예외가 가드가 아니다: ' || sqlerrm; end if;
      end;
      begin  -- ⓕ NULL로 지우기 — `<>`는 NULL 앞에서 눈이 먼다
        execute 'update runners set base_lat = null, base_lng = null where profile_id = $1' using rA;
        v_bad := v_bad || ' 🔴 ⓕ 클라가 기준 위치를 지울 수 있다 (`is distinct from`이 `<>`로 후퇴)';
      exception when others then
        if sqlerrm !~ 'runner_base_definer_only' then v_bad := v_bad || ' ⓕ 예외가 가드가 아니다: ' || sqlerrm; end if;
      end;
      begin  -- ⓘ 🔴 base_set_at 직접 쓰기 — **쿨다운을 통째로 지우는 경로**
        -- 좌표를 직접 쓰면 관측 하나의 해상도를 잃지만, 시계를 직접 쓰면 관측 **횟수**의 상한을
        -- 잃는다. 2026-08-25 측정 기준 후자가 실제 방어선이므로 이 팔이 ⓔ보다 무겁다.
        -- `runners`에는 authenticated의 테이블 전체 UPDATE가 있고 0057 §6의 블랙리스트는 이
        -- 컬럼을 모른다 — §3의 가드가 없으면 이 UPDATE는 그냥 통과한다.
        execute 'update runners set base_set_at = now() - interval ''999 days'' where profile_id = $1' using rA;
        v_bad := v_bad || ' 🔴 ⓘ 클라가 base_set_at을 되돌렸다 (쿨다운이 존재하지 않는 것과 같다)';
      exception when others then
        if sqlerrm !~ 'runner_base_definer_only' then v_bad := v_bad || ' ⓘ 예외가 가드가 아니다: ' || sqlerrm; end if;
      end;
      begin  -- ⓙ base_change_count 직접 쓰기 — 지울 수 있는 카운터는 패턴이 아니다
        execute 'update runners set base_change_count = 0 where profile_id = $1' using rA;
        v_bad := v_bad || ' 🔴 ⓙ 클라가 변경 횟수를 0으로 되돌렸다 (사후 가시성이 사라진다)';
      exception when others then
        if sqlerrm !~ 'runner_base_definer_only' then v_bad := v_bad || ' ⓙ 예외가 가드가 아니다: ' || sqlerrm; end if;
      end;
      begin  -- ⓖ 기존 쓰기 경로 생존 (api.ts setRunnerOnline / updateRunnerBio)
        execute 'update runners set online = true, bio = $1 where profile_id = $2' using '소개', rA;
      exception when others then
        v_bad := v_bad || ' 🔴 ⓖ 기존 스토어프런트 쓰기가 새 가드에 막혔다: ' || sqlerrm; end;
      reset role;
    exception when others then reset role; v_bad := v_bad || ' authenticated 경로 예외:' || sqlerrm;
    end;
    -- ⓗ 🔴 집합 동등성: authenticated에게 SELECT가 열린 컬럼 == **0121 §O의 리터럴 11개**.
    -- ⚠ 머지에서 고쳐 쓴 핀이다 (2026-08-25). 원형은 「오늘의 컬럼 − 서버 전용 4」를 카탈로그에서
    -- **계산**했고, 그래서 0123 §2(구판)가 0121의 화이트리스트를 22컬럼으로 되돌렸을 때 이 핀은
    -- 그 되돌림을 **정답으로 인증**했다 — 붉어진 건 156 P6(commission_rate 봉인)이었다. 계산식
    -- 기대값은 「지금 그랜트된 것」과 「그랜트되어야 하는 것」을 구분하지 못한다; 기대값은 소유자
    -- (0121)의 리터럴이어야 하고, 새 컬럼이 생기면 이 목록과 어긋나 붉어지는 것으로 「클라가
    -- 읽어도 되는가」의 강제 결정은 그대로 산다. 스팟 체크가 못 보던 누락 방향(리뷰어의 X2:
    -- photos 빼기)도 그대로 본다.
    v_cols := array['avg_pace_sec_per_km', 'bio', 'online', 'photos', 'profile_id',
                    'respond_rate_pct', 'specialties', 'tier', 'total_km', 'total_runs',
                    'trainer_certified'];  -- = 0121 §O의 grant, 알파벳순 (원문은 0121:218-220)
    select array_agg(a.attname order by a.attname) into v_cols2
      from pg_attribute a
     where a.attrelid = 'runners'::regclass and a.attnum > 0 and not a.attisdropped
       and has_column_privilege('authenticated', 'runners', a.attname, 'select');
    if coalesce(array_length(v_cols, 1), 0) = 0 then
      v_bad := v_bad || ' ⓗ 전제 붕괴: runners에 컬럼이 없다';
    elsif not (v_cols @> coalesce(v_cols2, '{}'::text[]) and coalesce(v_cols2, '{}'::text[]) @> v_cols) then
      v_bad := v_bad || ' 🔴 ⓗ 그랜트 집합이 0121의 리터럴 11개와 다르다: 초과='
               || coalesce((select array_agg(c) from unnest(coalesce(v_cols2,'{}'::text[])) c where not (v_cols @> array[c]))::text, '{}')
               || ' 누락='
               || coalesce((select array_agg(c) from unnest(v_cols) c where not (coalesce(v_cols2,'{}'::text[]) @> array[c]))::text, '{}');
    end if;
    -- service_role은 계속 전 컬럼을 읽는다 (settle-run의 commission_rate 등 — 0088 §D의 같은 이유)
    if not has_column_privilege('service_role', 'runners', 'base_lat', 'select')
      then v_bad := v_bad || ' service_role이 base_lat SELECT를 잃었다 — 심/운영의 권한 모델이 변했다'; end if;
    -- 기준 위치와 **속도 제한 상태**는 여전히 그대로여야 한다 (ⓔ/ⓕ/ⓘ/ⓙ가 진짜로 막혔는지의 사후 확인)
    select base_lat, base_lng into v_lat, v_lng from runners where profile_id = rA;
    if v_lat is distinct from 37.51 or v_lng is distinct from 127.00 then
      v_bad := v_bad || ' 🔴 클라 경로 뒤 기준 위치가 움직였다=' || coalesce(v_lat::text,'∅') || ',' || coalesce(v_lng::text,'∅'); end if;
    select base_set_at, base_change_count into v_ts2, v_cnt2 from runners where profile_id = rA;
    if v_ts2 is distinct from v_ts or v_cnt2 is distinct from v_cnt then
      v_bad := v_bad || ' 🔴 클라 경로 뒤 쿨다운 상태가 움직였다 set_at=' || coalesce(v_ts::text,'∅') || '→' || coalesce(v_ts2::text,'∅')
               || ' count=' || coalesce(v_cnt::text,'∅') || '→' || coalesce(v_cnt2::text,'∅'); end if;
    if v_bad = ''
      then call _pass('rbd','N7 좌표+쿨다운 봉인 — anon·authenticated 모두 서버 전용 4컬럼 SELECT 불가(본인 행 포함) · 그랜트 집합 = 0121 §O의 리터럴 11 (집합 동등성 — 계산식 기대값은 되돌림을 인증한다, 머지에서 측정) ⟷ 화이트리스트 컬럼 실동작 생존 · 클라 INSERT/UPDATE/삭제 + base_set_at/base_change_count 5종 거절 ⟷ 기존 스토어프런트 쓰기 생존 · service_role 전 컬럼');
    else call _fail('rbd','N7 좌표+쿨다운 봉인', v_bad); end if;
  exception when others then reset role; call _fail('rbd','N7 좌표+쿨다운 봉인', coalesce(v_bad, '') || ' ' || sqlerrm);
  end;

  -- ═══ 시드 정리 — 오픈 풀 오염 방지 (80/98/157 선례). matching/runner_pending → expired 허용 ═══
  update bookings set status = 'expired'
    where id in (b_1, b_2, b_3, b_5, b_far, b_dec, b_club, b_nopin, b_poison, b_noaddr,
                 b_dir, b_dirclub);
end $$;
