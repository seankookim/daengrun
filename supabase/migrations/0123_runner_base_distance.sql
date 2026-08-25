-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0123 — runner home base + pre-accept DISTANCE BANDS (Sean's Q6, distance half, ruling B)
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Sean's Q6 ruling, verbatim (2026-08-25, docs/decisions/awaiting-sean.md §0-untricies):
--   「q6: if the runner is searching for a run, then a how far away they are from the starting
--    point is a metric they need to see and doesnt show the actual address anyways; also
--    include the 동.」
-- and the disposition that unblocked THIS half, also verbatim:
--   「go with B for distance, and the runner should be able to switch this address in
--    settings.」  [end of his words]
--
-- 0122 built the 동 half and REFUSED this one, for a reason that ruling B answers rather than
-- waives: distance needs a runner position, and 0122 could only have taken one by READING the
-- device outside a run — which `docs/legal/privacy-policy.md` publishes the opposite of
-- (「러닝 중이 아닐 때는 위치를 수집하지 않습니다」). Ruling B does not read a device at all.
-- The runner TYPES a place once, in settings, and may change or remove it. That is a stored
-- datum the user authored, not a reading we took — the same distinction 0122's header draws
-- between `addresses.addr` and a live coordinate, and it is why B is buildable today while A
-- (live device position) still is not.
--
-- ── DATA CLASSIFICATION, and the one place it is HARDER than 0122's ─────────────────────────
-- ⚠ Say the uncomfortable half first: **a stored runner coordinate is 개인위치정보 at rest.**
-- 0122 could argue its way out (a 법정동 label of a fixed address is 개인정보 at 동 granularity,
-- not 위치정보); this file cannot and does not try. It stores a point. Consequences, all
-- implemented below rather than asserted:
--   · 1-YEAR RETENTION is the product answer riding with the ruling; counsel Q3 in
--     `docs/biz/location-law-counsel-brief.md` asks whether the cap binds this item and how it
--     is counted. STILL NOT BUILT: there is no sweep, because a base has no natural clock — it
--     is current until the runner changes it. 🔴 FLAGGED, not silently assumed away.
--     ⚠ One thing DID change on 2026-08-25, and it changes the size of the remedy rather than
--     the decision: this file now carries `base_set_at` (§1), added for the cooldown, not for
--     retention. So if counsel says the cap binds regardless, the sweep is now a WHERE clause
--     over an existing column plus 0120's ledger shape — still a slice, no longer a schema
--     change. Do not read that as the sweep being half-written. It is not written.
--   · 제16조 (접근기록) — `open_request_distance()` (§8) is STABLE and writes NOTHING, including
--     no access ledger, which is the SAME posture 0122 N5 pinned but for a DIFFERENT reason and
--     the difference matters: 0122 wrote nothing because nothing it handled was 개인위치정보;
--     this file writes nothing because the caller is reading THEIR OWN stored base and is
--     never handed anyone else's. No 개인위치정보 is *provided to a third party* here — a band
--     is a fact about the caller's own distance, and the pickup point it is measured against is
--     never returned in any form. If counsel disagrees, the remedy is again ONE function: route
--     §8 through 0120's `location_access_log`. That is why the window is a single choke point.
--   · ACCOUNT DELETION is wired from day one (§4), and the end-to-end pin lives in suite 150
--     alongside 0122's — see the 0122 lesson quoted there.
--
-- ── MULTILATERATION: WHAT WAS CLAIMED, WHAT WAS MEASURED, AND WHAT ACTUALLY BOUNDS IT ───────
-- ⚠ AN EARLIER DRAFT OF THIS HEADER CLAIMED: 「every annulus a runner can draw is centred on a
-- grid vertex, so the intersection of annuli centred on a ~1.1 km lattice cannot resolve the
-- target below that lattice.」 **THAT CLAIM IS FALSE, and it was MEASURED false** — the blind
-- review of 2026-08-25 drove 323 probes through the two REAL RPCs on this branch and localized a
-- stranger's pickup to **8.8 m**. Wrong by ~125×. Four base changes already beat the 동 that
-- 0122 discloses. The error was believing a coarse lattice coarsens the ANSWER. It does not: an
-- observation is an annulus whose WIDTH comes from the band ladder and whose CENTRE is a lattice
-- vertex, and intersecting annuli with DIFFERENT centres shrinks the feasible region without
-- bound. Measured across five band designs in the same review — the number of DISTINCT CENTRES
-- is everything, and coarsening the band EDGES buys nothing:
--        1 probe  → ~1.9 km box        16 probes → ~0.15 km
--        4 probes → ~0.6  km           81+ probes → a point
-- So the mechanism that bounds disclosure is NOT the grid. It is the RATE at which one account
-- can produce a new CENTRE, and §5 enforces that with a cooldown.
--
-- ── THE FOUR CLAIMS THIS FILE WILL MAKE, each executable ────────────────────────────────────
--   (i)   QUANTIZATION bounds a SINGLE observation. One band read from an on-grid base locates
--         the pickup no better than a band's width around a ~1.1 km vertex. That is real, and it
--         is all quantization was ever worth. Kept, as a belt (§1 CHECK + §5 round), not as the
--         defence. Pinned: 158 P8.
--   (ii)  THE COOLDOWN bounds the observation COUNT. One successful base change per
--         _base_change_cooldown() per account (§4b/§5), so annuli-per-address ≤ base moves ≤
--         elapsed/cooldown. **This is the defence.** Pinned: 158 P13/P14/P16.
--         🔴 AT SEAN'S RULED N = 7 DAYS, HERE IS THE ACTUAL BOUND — arithmetic, not adjective,
--         read straight off the review's own measured curve: one account needs ~3 weeks to reach
--         the 3 annuli that beat a 동, ~4 weeks for the 4 that give a ~0.6 km box, ~4 months for
--         the 16 that give ~0.15 km, and well over a year for the 81 that resolve a point. So it
--         bounds the CASUAL and the OPPORTUNISTIC, and it does not stop a patient adversary.
--         Nobody should read the word "defence" above as more than that sentence.
--   (iii) K COLLUDING CERTIFIED ACCOUNTS get K annuli at once, and that is IRREDUCIBLE while a
--         per-base distance is shown at all — usefulness and safety are the same knob. Said out
--         loud rather than defended away. What stands there instead: the pool is gated on
--         `is_active_runner()` (certified identity — 본인인증 + 신원확인, so accounts are not
--         free), and ACCEPTING a booking discloses the exact address LEGITIMATELY inside 24 h
--         (0060/0065). For a runner who can actually be assigned, the attack is strictly more
--         expensive than the honest path; what this file defends against is a certified runner
--         who wants an address WITHOUT taking the job, and the cooldown makes that cost months.
--   (iv)  base_set_at / base_change_count make the probing PATTERN visible after the fact —
--         「this account moved its base 300 times」 is a question ops can now ask. ⚠ There is
--         deliberately NO history of old coordinates: a coordinate history is 개인위치정보 with
--         its own retention problem, and it would store precisely the trail the attacker's
--         probes drew. A timestamp and a counter give the pattern without storing where.
--
-- ── RESIDUAL RISK, AND WHOSE CALL IT IS ────────────────────────────────────────────────────
-- Everything (iii) names and the patient-adversary half of (ii) is risk this file ACCEPTS rather
-- than removes. That acceptance is **Sean's, on the record**: asked for N with the measured
-- curve in front of him he answered 「7 days」 and added, verbatim,
--   「wait, this is fine. no need to over worry about such abuse.」  [end of his words]
-- (2026-08-25 14:19 KST, `docs/decisions/2026-08-25-console-rulings.md` third round T1.)
-- So the size of this machine is a product ruling and not an engineering guess, in BOTH
-- directions: the number is his, and so is the instruction not to build more around it. What
-- was considered and dropped under that instruction, named so nobody re-derives it as new: a
-- band freeze table, a coordinate history, a per-address probe ledger, a velocity heuristic.
-- Anyone who wants one of those should re-ask him, not re-reason it.
--
-- BANDS ARE RECOMPUTED ON READ — no freeze table, deliberately. With the cooldown, the annuli a
-- single account can accumulate against one address are already bounded by its base moves, so
-- freezing buys nothing the attacker is short of, and it would cost the property the client's
-- copy depends on: a band always reflects the runner's CURRENT base, so 「기준 위치에서 ~1km」 is
-- true when it is read rather than true as of some earlier base (requests.tsx).
-- ⚠ This is the reason the client may NOT write ANY of these four columns directly (§3).
-- `runners` has a table-wide UPDATE for `authenticated` under `"runners self write"` (0057 §6
-- narrowed the COLUMNS by a BLACKLIST — measured: `_guard_runner_cols` enumerates
-- tier/commission/실적/검증 and nothing else), so a new column on this table is client-writable
-- by default. A client that could PATCH `base_lat` would step around the quantization; a client
-- that could PATCH `base_set_at` or `base_change_count` would step around the cooldown, which
-- is the load-bearing one — so the guard covers the ROW of four, not the pair.
--
-- ── WHAT THIS FILE REFUSES TO DO (the contract, so a reviewer can execute it) ───────────────
--   ✗ §8 never returns metres, coordinates, an address, an address id, or a 동. Its declared
--     return type is (booking_id uuid, distance_band text) and that shape is the seal — but the
--     0122 blind review measured that a TYPE seals numbers, not text, so the suite's positive
--     pins assert VALUES from a fixture at a known separation, not shapes;
--   ✗ it does not touch `open_request_pickup_dong()` (0122 §3) by a byte. Two windows, two
--     classifications, two rows in a reviewer's table. Merging them would put a 개인위치정보
--     derivation and a 개인정보 label behind one grant, and the day counsel answers Q3 the wrong
--     way, the 동 half would have to be taken down with the distance half;
--   ✗ it does not touch `booking_pickup_address` (0060 + 0065) or `marketplace_open_requests`
--     (98 H6 pins that view at exactly 17 columns) — same two seals 0122 named;
--   ✗ it does not add a second haversine. `_route_dist_m` (0082 §D) is THE distance function in
--     this repo and §8 calls it. A private copy here would be two formulas one refactor apart;
--   ✗ §8 never raises for a caller without a JWT — `auth.uid() is null` is 0 rows. And
--     `current_user` is never consulted as an identity (BLOCKER-10's class: inside a definer it
--     is always the owner).
--
-- ── THE HOLE THIS SLICE CLOSES ON ITSELF (§2), and why it is not scope creep ────────────────
-- `runners` is anon-readable and always has been — 0093:59 records it as a deliberate,
-- pseudonymous surface (「`runners` (profile_id, tier, bio) — anon-readable, pseudonymous, no
-- name」). RLS on that table is `"runners public read" … using (tier <> 'applicant' or
-- profile_id = auth.uid())`, which is a ROW rule, and there are NO column grants, so Supabase's
-- default privileges hand anon and authenticated a table-wide SELECT. Adding a coordinate to
-- that table without §2 would publish **every certified runner's home area to anybody with the
-- anon key** — 0088's exact class (RLS never covered columns; `profiles.phone` was readable for
-- months). So the slice that CREATES the column closes its own read path, the way 0122 §2
-- closed its own write path, and the broader question of what else on `runners` should be
-- column-gated stays a separate slice, untouched here.
-- 0088's own recorded instruction is followed literally rather than reinvented: 「본인 조회가
-- 필요해지면 my_profile() definer를 새로 만들 것 — 이 그랜트를 다시 넓히지 말 것」. Hence §6.

-- ═══ §1 the columns ═══════════════════════════════════════════════════════════════════════
-- Nullable pair with no default and no backfill. NULL means "no base set" and the client
-- renders a real door to settings, never a guessed centre (a defaulted base would silently
-- become a claim about where a runner lives).
alter table runners
  add column base_lat numeric(9,6),
  add column base_lng numeric(9,6);

-- 🔴 THE RATE LIMITER'S STATE — server-only, and the reason it is TWO scalars and not a table.
-- `base_set_at` is what §5 refuses against; `base_change_count` is the pattern ops can ask about.
-- ⚠ NO HISTORY OF OLD COORDINATES, anywhere, ever. A `runner_base_history` table would be the
-- honest-looking version of this and it is the wrong one: it stores 개인위치정보 with its own
-- retention clock, and what it stores is exactly the trail a probing attacker drew — we would be
-- keeping the attack for them. A timestamp and a counter answer 「did this account move its base
-- 300 times?」 without answering 「where to?」, which is the only half ops needs.
-- `base_change_count` is NOT NULL DEFAULT 0 on purpose: a NULL counter is a counter with a
-- fourth state nobody handles, and every existing runners row must start this life at zero
-- rather than at 「unknown」. `base_set_at` IS nullable — NULL means 「never set a base」, which
-- is a real state and the one that must always be allowed through (§5's first-ever set).
alter table runners
  add column base_set_at timestamptz,
  add column base_change_count int not null default 0;

-- 0065's form, transcribed rather than re-derived. `(a is null) = (b is null)` is deliberate:
-- CHECK passes on NULL, so the naive `or` form silently admits half-pairs. The bounds are
-- Korea-plausible and deliberately disjoint (33..39 / 124..132) so a lat/lng swap is a
-- constraint violation instead of a runner whose base is in the Yellow Sea.
alter table runners add constraint runners_base_shape check (
  (base_lat is null) = (base_lng is null)
  and (base_lat is null or (base_lat between 33 and 39 and base_lng between 124 and 132))
);

-- THE GRID IS A CONSTRAINT, NOT A HABIT. §5 rounds, but §5 is one writer and this column will
-- outlive it; service_role and any future definer would otherwise be free to store a 6dp point.
-- ⚠ CALIBRATED, 2026-08-25: what that costs is the resolution of a SINGLE observation (header,
-- claim i) — it is a real property and a cheap one, and it is NOT what stops multilateration.
-- The earlier draft of this file leaned the whole privacy argument on this CHECK and the review
-- measured the argument false. Keep the belt; do not re-promote it to the defence.
-- `round(numeric, int)` is IMMUTABLE, so it may sit in a CHECK. Kept SEPARATE from
-- runners_base_shape so a violation names which law broke — "out of Korea" and "off grid" are
-- different bugs with different fixes.
alter table runners add constraint runners_base_grid check (
  base_lat is null or (base_lat = round(base_lat, 2) and base_lng = round(base_lng, 2))
);

comment on column runners.base_lat is
  '러너 활동 기준 위치 (위도) — Sean 2026-08-25 ruling B. 개인위치정보 at rest: the runner sets it
in settings and may change or clear it. SNAPPED TO 0.01° (~1.1km) BEFORE storage by
set_runner_base (0123 §5) and enforced by runners_base_grid. ⚠ THE GRID IS A BELT, NOT THE
DEFENCE — an earlier version of this comment claimed no sequence of base moves could resolve a
pickup below the grid, and the 2026-08-25 blind review MEASURED that false (323 probes → 8.8 m).
What bounds disclosure is the COOLDOWN on changes (base_set_at, §5); quantization bounds one
observation, the cooldown bounds how many. Full argument in this file''s header. NOT readable by
anon or authenticated (0123 §2 column grant); the owner reads their own through my_runner_base()
(§6). Cleared on account deletion by the tombstone arm (§4). Retention: 1 year is the product
answer riding with the ruling; counsel Q3 pending — there is no sweep here and that is stated,
not hidden.';
comment on column runners.base_lng is
  '러너 활동 기준 위치 (경도) — 짝은 base_lat. 두 값은 runners_base_shape에 의해 항상 함께
NULL이거나 함께 존재한다 (반쪽 좌표 금지). 나머지는 base_lat의 주석과 동일.';
comment on column runners.base_set_at is
  '마지막으로 기준 위치를 **설정한** 시각 (0123 §5). 이 파일의 실제 방어선이다: §5는
base_set_at + _base_change_cooldown() 이전의 재설정을 base_change_cooldown으로 거절한다 —
관측 1회의 해상도는 격자가 묶고, 관측 **횟수**는 이 컬럼이 묶는다. NULL = 한 번도 설정한 적
없음 (최초 설정은 언제나 허용). ⚠ 해제((NULL,NULL))는 이 값을 **건드리지 않는다** — 해제가
시계를 되돌리면 「지웠다 다시 찍기」가 쿨다운 우회 경로가 된다 (158 P13ⓑ). 클라이언트는 읽지도
(§2) 쓰지도(§3) 못한다; 본인은 my_runner_base()의 can_change_at으로 **다시 바꿀 수 있는 시각**만
받는다. 옛 좌표 이력은 어디에도 저장하지 않는다 (§1 주석).';
comment on column runners.base_change_count is
  '기준 위치를 성공적으로 바꾼 횟수 (0123 §5). 거절에는 증가하지 않는다 — 그래야 이 숫자가
「몇 번 시도했나」가 아니라 「몇 개의 서로 다른 중심을 만들었나」를 뜻하고, 다변측량 관측 수의
상한이 된다 (158 P15). 사후 가시성 전용: 어디로 옮겼는지는 저장하지 않는다.';

-- ═══ §2 the read grant — the four new columns are sealed BY CONSTRUCTION ═══════════════════
-- ⚠ REWRITTEN AT THE MERGE (2026-08-25). This section used to revoke-and-regrant the whole
-- `runners` read whitelist — 22 columns, derived from the PRE-0121 grant state, because this
-- branch was cut before the runner-money strip landed. Applied after 0121 it silently re-granted
-- `commission_rate` (and ten other columns 0121 deliberately dropped), which is the 0086 §B
-- silent-revert class this REGISTRY exists to prevent — and 156 P6 caught it on the first merged
-- harness run (890/2, 「(e)rate-readable」). The whole lesson in one line: a whitelist written as
-- a literal in two files is one migration-ordering accident away from being two whitelists.
--
-- So this file now re-creates NOTHING here. 0121 §O owns the `runners` read grant (11 columns:
-- profile_id, tier, bio, specialties, photos, avg_pace_sec_per_km, total_runs, total_km,
-- respond_rate_pct, trainer_certified, online — granted to authenticated only; anon gets
-- nothing, 0121's measured call). Column-specific grants do NOT extend to columns added later,
-- so base_lat / base_lng / base_set_at / base_change_count are unreadable to every client role
-- the moment §1 creates them, with no statement required — the seal is structural.
-- 158 N7ⓗ pins the LIVE grant against 0121's literal list (both directions: an extra grant and
-- an over-revoke each redden — and the re-grant this section used to BE reddens ⓗ with the full
-- eleven-column excess, measured), and N7ⓒ additionally runs real queries as `authenticated`,
-- which catches an RLS-level break the catalog comparison cannot see.
-- Explicit, not redundant — 0088 §D's own note applies unchanged: settle-run reads
-- commission_rate and transition-booking reads tier through the admin client, so stating this
-- here means a future blanket `revoke … from public` that catches service_role turns 158 N7 red
-- instead of turning settlement off in production.
grant select on runners to service_role;

-- ═══ §3 the base is definer-written — a client may not author it ═══════════════════════════
-- Copied shape: `_guard_address_dong` (0122 §2), same table-guard family, same reasoning about
-- WHY a `current_user` branch is correct HERE and wrong three files away (0119 §D). This guard
-- protects a SERVER-QUANTIZED column FROM a client, so asking the role is asking exactly the
-- right question; the real writer (§5) is a definer and runs as the owner, so it passes.
-- ⚠ This is a SECOND trigger on `runners`, not a re-creation of `_guard_runner_cols` (0057 §6).
-- Deliberate: 0057 owns that function, the REGISTRY law is "add your own, re-create nothing you
-- did not create", and multiple BEFORE UPDATE triggers on one table all fire. Re-creating
-- 0057's blacklist to append two names would put this file in the way of the next security
-- slice for no gain.
create or replace function _guard_runner_base() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  if current_user in ('authenticated', 'anon') then
    -- INSERT: a runners row may be born without a base (that is the normal path — ensureRunner
    -- writes profile_id/tier). It may not be born WITH one, off-grid or on, and it may not be
    -- born with a pre-aged clock either.
    -- UPDATE: no value in the FOUR may move, in either direction, INCLUDING to NULL. Clearing is
    -- a legitimate act and it has a door (§5 with NULL,NULL) — but it goes through the door, so
    -- that "cleared" and "never set" stay one state with one writer. `is distinct from` on the
    -- ROW is deliberate: `<>` is NULL-blind and would let a client erase a base it cannot write.
    -- 🔴 base_set_at / base_change_count are in this tuple and that is the LOAD-BEARING half.
    -- The coordinate columns being client-writable would have cost resolution on one observation;
    -- `base_set_at` being client-writable costs the cooldown ENTIRELY — a client could stamp it
    -- backwards and take a new centre every request. `runners` carries a table-wide UPDATE for
    -- `authenticated` (0057 §6's blacklist names neither), so without this line the rate limit is
    -- a suggestion. `base_change_count` rides along for the same reason it exists: a counter an
    -- attacker can zero is not a pattern anybody can read.
    if (tg_op = 'INSERT' and (new.base_lat is not null or new.base_lng is not null
                              or new.base_set_at is not null or new.base_change_count <> 0))
       or (tg_op = 'UPDATE'
           and (new.base_lat, new.base_lng, new.base_set_at, new.base_change_count)
               is distinct from (old.base_lat, old.base_lng, old.base_set_at, old.base_change_count))
    then
      raise exception 'runner_base_definer_only'
        using detail = '활동 기준 위치는 설정 화면에서만 바꿀 수 있어요';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists _guard_runner_base_write on runners;
create trigger _guard_runner_base_write before insert or update on runners
  for each row execute function _guard_runner_base();

comment on function _guard_runner_base is
  '0123 §3 — runners.base_lat/base_lng/base_set_at/base_change_count are definer-written.
authenticated/anon may neither set them on INSERT nor change them on UPDATE (including to NULL);
set_runner_base (§5) is the only door. It QUANTIZES (a direct PATCH would store a 6dp point) and
it RATE-LIMITS (a direct PATCH of base_set_at would delete the cooldown, which is this file''s
actual anti-multilateration defence — the grid is only a belt, measured 2026-08-25). Does not
re-create _guard_runner_cols (0057 §6); both triggers fire.';

-- ═══ §4 account deletion — the base dies with the account, and 0115 is byte-untouched ══════
-- 🔴 The 0122 BLOCKER-1 class, headed off rather than repeated. That review measured a derived
-- 법정동 SURVIVING `delete_my_account_tx` because 0115's redaction list is a named-column
-- allowlist that could not know about a column added later, and the row it lives on is KEPT
-- FOREVER as an FK anchor — so 0115:443's own invariant ("LOCATES NOTHING AND IDENTIFIES
-- NOBODY") had quietly become false. A stored coordinate is a worse thing to leave behind than
-- a 동 label, so this file does not wait to be told.
-- MECHANISM CHOICE, stated because a reviewer should attack the alternative: 0115 is NOT
-- re-created. `delete_my_account_tx` is 445 lines of money-and-consent decisions and this file
-- would have to reproduce every one of them to add two column names to one UPDATE — exactly the
-- silent-revert trap 0086 §B records (a faithful-looking copy that applies later and undoes the
-- newer definition while the harness stays green). Instead the cascade rides the TOMBSTONE
-- itself: `profiles.deleted_at` going non-null is 0115 §B's definition of a deleted account, it
-- is set inside that transaction, and it is unreachable by a client (0091:198 grants UPDATE on
-- name/district/avatar_url/role/id only). So the invariant is stated where it belongs — a
-- tombstoned profile's runner row cannot hold an activity base — and it holds for any future
-- deletion path, not only for today's statement order.
-- The inner UPDATE passes §3's guard because whoever set `deleted_at` is postgres (the definer)
-- or service_role, never `authenticated`.
-- ⚠ SECURITY DEFINER, changed in the 2026-08-25 fix round (review MINOR-1). It was INVOKER, and
-- the review measured the coupling: this body READS and WRITES the four columns §2 revoked from
-- every client role, so under INVOKER the only thing keeping it from an insufficient_privilege
-- was the WHEN clause happening never to fire for a client — i.e. a privilege argument standing
-- on a routing accident. `authenticated` cannot set `profiles.deleted_at` today (0091:198 grants
-- UPDATE on name/district/avatar_url/role/id only), which is exactly the kind of fact that is
-- true until one migration widens a grant. DEFINER makes the cascade a property of the trigger
-- rather than of who happened to fire it. In-body search_path was already here (0055 doctrine)
-- and 98 H1 now watches this function too, correctly.
create or replace function _runner_base_tombstone() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  -- All FOUR columns, not the coordinate pair: leaving `base_set_at`/`base_change_count` on a
  -- tombstoned row would keep a behavioural trace of a deleted account for no purpose the
  -- pattern-visibility argument (§1) can carry — that argument is about LIVE accounts, and a
  -- dead one can never set a base again (§5's party gate refuses a tombstoned profile).
  update runners set base_lat = null, base_lng = null,
                     base_set_at = null, base_change_count = 0
   where profile_id = new.id
     and (base_lat is not null or base_lng is not null
          or base_set_at is not null or base_change_count <> 0);
  return null;
end $$;

-- 🔴 THE REVOKE THAT SECURITY DEFINER OWES. A newly created function carries a PUBLIC EXECUTE
-- grant, and 0057 §1's standing sweep (99 S1: "no public security definer function is
-- anon-executable") counts EVERY prosecdef function in `public` — trigger functions included.
-- MEASURED on the first fix-round harness run: flipping this one function to DEFINER without
-- these two lines turned 99 S1 red on its own (862/1), naming exactly this function. That is the
-- sweep doing its job, and it is the reason MINOR-1 is a two-line change and not a one-word one.
-- Nobody calls a trigger function directly; the trigger itself does not consult EXECUTE.
revoke execute on function _runner_base_tombstone() from public, anon, authenticated;

drop trigger if exists _runner_base_tombstone_tg on profiles;
create trigger _runner_base_tombstone_tg after update on profiles
  for each row
  when (new.deleted_at is not null and old.deleted_at is distinct from new.deleted_at)
  execute function _runner_base_tombstone();

comment on function _runner_base_tombstone is
  '0123 §4 — a tombstoned profile (profiles.deleted_at, 0115 §B) cannot keep a runner activity
base, nor the rate-limiter state that rides with it (all four columns). Fires on the tombstone
stamp itself rather than on delete_my_account_tx''s `update runners` statement, so it does not
depend on that function''s statement order and 0115 needs no edit. SECURITY DEFINER since the
2026-08-25 fix round: the body touches columns no client role may read or write, and INVOKER made
that safe only by way of the WHEN clause never firing for a client. End-to-end pin: suite 150
(with 0122''s dong); mechanism pin: suite 158 P10.';

-- ═══ §4b BASE_CHANGE_COOLDOWN — the one named constant, and it is a RULING ═════════════════
-- 🔵 **N = 7 DAYS. SEAN'S RULING, 2026-08-25 14:19 KST**, recorded in
-- `docs/decisions/2026-08-25-console-rulings.md` third round T1. His comment, verbatim:
--   「wait, this is fine. no need to over worry about such abuse.」  [end of his words]
-- Two things that comment settles, and the second is the more important one for whoever reads
-- this next:
--   · the NUMBER — the question put to him was "runner base-move cooldown N", options ran from
--     days to months, and he took the lightest. The bound that buys is spelled out in the
--     header's claim (ii) in weeks and months rather than in adjectives, so nobody has to trust
--     the word "defence";
--   · the POSTURE — an explicit instruction not to over-engineer this abuse class. This file
--     therefore carries the cooldown, two cheap counters, and honest wording, and NOTHING
--     heavier: no freeze table, no coordinate history, no per-address probe ledger, no
--     velocity heuristic. Each of those was considered and dropped under this ruling. A future
--     reader tempted to add one should re-ask Sean rather than re-derive it — **the parameter
--     is a product ruling, not an engineering guess**, and so is the size of the machine
--     around it.
-- The trade it makes on the other side is real too and stays visible: a runner who actually
-- moves house waits a week to see honest distances.
-- WHY A FUNCTION and not a plpgsql `constant` inside §5, which is what the fix-round brief asked
-- for: §6 needs the SAME number to tell the client when the door reopens (`can_change_at`), and
-- the client must not compute it — that is the rounding lesson one section down, verbatim ("a
-- client that mirrors a server rule makes two rules"). A constant local to §5 would have forced
-- a second copy into §6 or into the app. One name, two callers, no copies.
-- IMMUTABLE and no ACL: it is a literal. It is not security definer, so 98 H1/99 S1 correctly do
-- not watch it, and anon learning that the cooldown is 7 days learns what this comment prints
-- (and what the client's own Korean sentence prints).
create or replace function _base_change_cooldown() returns interval
language sql immutable as $$ select interval '7 days' $$;

comment on function _base_change_cooldown() is
  '0123 §4b — the runner activity-base change cooldown. **7 days, Sean''s ruling 2026-08-25**
(docs/decisions/2026-08-25-console-rulings.md third round T1, verbatim: 「wait, this is fine. no
need to over worry about such abuse.」) — a product ruling, not an engineering guess, and the
same comment is why nothing heavier than a cooldown plus two counters was built around it. THE
single place this interval exists: set_runner_base (§5) refuses against it and
my_runner_base (§6) publishes base_set_at + this as `can_change_at` so the client can lock its
own button instead of re-deriving the rule. This number IS the anti-multilateration bound — the
0.01° grid is a belt (the lattice claim was measured false 2026-08-25); what actually limits an
attacker is how few DISTINCT CENTRES one account can produce per unit time.';

-- ═══ §5 the writer — the ONE door: it quantizes, and it rate-limits ════════════════════════
-- Party gate before state gate (house law): the caller must BE a runner. Note what the gate
-- deliberately is NOT — it does not require `certified`. An applicant may set a base (it is
-- their own datum and they will need it the day they are certified) and still sees zero rows
-- from §8, because that window inherits the open pool's tier gate. Two different questions,
-- two different gates, and 158 P3/P9 pin them apart.
create or replace function set_runner_base(p_lat numeric, p_lng numeric)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_last timestamptz;
  v_lat numeric;
  v_lng numeric;
begin
  if v_uid is null then raise exception 'not_signed_in'; end if;
  -- PARTY GATE — a runners row, AND a live profile. The `deleted_at is null` join is the fix
  -- round's MINOR-2 and it is not hypothetical: `runners` rows are KEPT FOREVER as FK anchors
  -- (0115 §B), so without this a tombstoned account that still holds a session could re-attach a
  -- coordinate to a row §4 had just cleared — deletion would be undone by the deleted user.
  -- Pinned 158 P12ⓓ; mutation (drop the join) reddens it.
  if not exists (
    select 1 from runners r
    join profiles p on p.id = r.profile_id
    where r.profile_id = v_uid and p.deleted_at is null
  ) then
    raise exception 'not_a_runner'
      using detail = '러너로 등록된 계정만 활동 기준 위치를 설정할 수 있어요';
  end if;

  -- CLEARING is a first-class act, not an error: a runner may remove the base and go back to
  -- seeing no distances. It goes through this door so "cleared" and "never set" are one state.
  -- 🔴 IT IS DELIBERATELY NOT RATE-LIMITED, AND IT DELIBERATELY DOES NOT TOUCH base_set_at.
  -- Two decisions, opposite directions, both load-bearing:
  --   · not rate-limited, because withdrawing stored 개인위치정보 must never be something the
  --     product refuses. A cooldown on deletion would be a retention policy wearing a rate
  --     limit's clothes.
  --   · does not reset the clock, because if it did, 「clear, then set」 would be the bypass and
  --     the cooldown would bound nothing at all. Clearing yields no annulus, so nothing is owed
  --     back for it. The user-visible consequence is real and the client says it out loud
  --     (base-pin.tsx): clearing during a cooldown means waiting to set a new one.
  if p_lat is null and p_lng is null then
    update runners set base_lat = null, base_lng = null where profile_id = v_uid;
    return;
  end if;
  -- A half-pair is a caller bug, and it must be a NAMED refusal here rather than a 23514 from
  -- runners_base_shape — the client turns this into a Korean sentence.
  if p_lat is null or p_lng is null then
    raise exception 'base_half_pair'
      using detail = '위도와 경도는 함께 저장돼요';
  end if;

  -- Bounds are checked on what the caller GAVE, so the refusal is about their input; the grid
  -- is applied after. Quantization provably cannot push an in-bounds value out: rounding to 2dp
  -- moves a value by at most 0.005°, and the bounds are inclusive at 33/39/124/132, so the
  -- extreme cases (38.999 → 39.00, 131.996 → 132.00, 33.001 → 33.00) all land ON the boundary
  -- and stay legal. Stated because the opposite order would need this argument and get it wrong.
  if not (p_lat between 33 and 39 and p_lng between 124 and 132) then
    raise exception 'base_out_of_bounds'
      using detail = '서비스 지역을 벗어났어요';
  end if;

  -- 🔴 THE COOLDOWN — this file's actual anti-multilateration defence (header, claim ii).
  -- ORDER: after the input gates, before the write. Deliberate — a half-pair or an out-of-bounds
  -- coordinate is the CALLER'S bug and must name itself, and a caller learns nothing from the
  -- ordering (both refusals are about their own account). Putting it first would have made every
  -- malformed call during a cooldown answer 'base_change_cooldown', which reads as "the server is
  -- confused" and loses the client its Korean sentence.
  -- The comparison is against the last SUCCESSFUL set only (§4b), which is why clearing above
  -- returns before reaching here and why a refusal below leaves base_set_at untouched.
  select r.base_set_at into v_last from runners r where r.profile_id = v_uid;
  if v_last is not null and v_last > now() - _base_change_cooldown() then
    raise exception 'base_change_cooldown'
      using detail = '활동 기준 위치는 자주 바꿀 수 없어요';
  end if;

  v_lat := round(p_lat, 2);
  v_lng := round(p_lng, 2);

  -- OWN ROW ONLY. There is no p_runner argument and there must never be one: the identity is
  -- auth.uid() and nothing the caller can spell.
  -- The stamp and the counter move in the SAME statement as the coordinate, so there is no
  -- window in which a base exists with no clock on it. `base_change_count` counts SUCCESSES, not
  -- attempts (158 P15): what it is for is bounding how many distinct annulus CENTRES this account
  -- has produced, and a refused call produced none.
  update runners
     set base_lat = v_lat, base_lng = v_lng,
         base_set_at = now(),
         base_change_count = base_change_count + 1
   where profile_id = v_uid;
end $$;

revoke execute on function set_runner_base(numeric, numeric) from public, anon;
grant  execute on function set_runner_base(numeric, numeric) to authenticated;

comment on function set_runner_base(numeric, numeric) is
  'The ONLY writer for runners.base_lat/base_lng/base_set_at/base_change_count (0123 §5, Sean''s
ruling B 2026-08-25). Party gate: the caller must have a runners row AND a live profile
(deleted_at is null) — tier is NOT consulted, that is §8''s question. Writes auth.uid()''s own row
and no other; there is no runner argument. Two limits, and they are not equals: it SNAPS to 0.01°
(~1.1km), which bounds ONE observation, and it REFUSES a change inside _base_change_cooldown()
with `base_change_cooldown`, which bounds the observation COUNT — the second is the real defence
(the lattice-resolution claim was measured false on 2026-08-25: 323 probes → 8.8 m). First-ever
set is always allowed (base_set_at NULL). (NULL, NULL) clears the base, is never rate-limited,
and never resets the clock — otherwise clear-then-set is the bypass. Returns void deliberately:
the client re-reads through my_runner_base() rather than drawing what it sent, because the SERVER
owns both the rounding rule and the cooldown (address-pin.tsx''s recorded idiom — a client that
mirrors a server rule makes two rules).';

-- ═══ §6 the reader — the owner's own base, and nobody else's ═══════════════════════════════
-- §2 makes the columns unreadable by every client role, which is right and which leaves the
-- runner unable to see their own setting. 0088's comment already answered this exact shape:
-- 「본인 조회가 필요해지면 my_profile() definer를 새로 만들 것 — 이 그랜트를 다시 넓히지 말 것
-- (그랜트는 내 행과 러너의 행을 구분하지 못한다)」. A grant cannot tell my row from a stranger's;
-- a definer can, so here it is.
-- Returns a coordinate, and that is not a disclosure: it is the caller's own, quantized, and it
-- is the value they themselves put there. 0 rows for a non-runner and for a caller with no JWT
-- (never an exception — the settings screen must not explode at a session boundary). A runner
-- with no base gets ONE row of (null, null), which is the honest "you are a runner and you have
-- not set one" — distinguishable by the client from "not a runner" (0 rows) and from a dead leg.
--
-- THE THIRD COLUMN, added in the 2026-08-25 fix round, is a DEAD-BUTTON fix and nothing else.
-- Once §5 can refuse with `base_change_cooldown`, a 「이 위치로 지정」 button that is guaranteed to
-- fail is a dead button in a state the product knows about in advance, and CLAUDE.md's law says a
-- visible action has a real effect in EVERY state. So the server publishes WHEN the door reopens
-- and the client locks its own button.
--   · `can_change_at` and not `base_set_at`: the client must not hold the cooldown RULE, only its
--     consequence. Handing over the raw stamp would make the app compute `stamp + 7 days` and
--     there would be two definitions of the number the moment Sean moves it (§4b).
--   · NULL means "no cooldown running" — never set a base, or the window already elapsed. The
--     client's check is a single `can_change_at > now()`, with no arithmetic of its own.
--   · Not a disclosure: it is derived from the caller's OWN stamp, and the interval it is derived
--     with is published in §4b's comment anyway.
create or replace function my_runner_base()
returns table (base_lat numeric, base_lng numeric, can_change_at timestamptz)
language sql stable security definer set search_path = public, pg_temp as $$
  select r.base_lat, r.base_lng,
         case when r.base_set_at is null then null::timestamptz
              else r.base_set_at + _base_change_cooldown() end
  from runners r
  where auth.uid() is not null and r.profile_id = auth.uid()
$$;

revoke execute on function my_runner_base() from public, anon;
grant  execute on function my_runner_base() to authenticated;

comment on function my_runner_base() is
  'The caller''s OWN activity base (0123 §6): (base_lat, base_lng, can_change_at). Exists because
§2''s column grant deliberately cannot distinguish my row from a stranger''s — 0088''s recorded
instruction rather than a wider grant. 0 rows = not a runner (or no JWT, never an exception); a
row of NULLs = a runner who has not set a base. `can_change_at` = base_set_at +
_base_change_cooldown() (§4b), NULL when no cooldown is running; it exists so the client can LOCK
the confirm button instead of offering a press that §5 is certain to refuse, and it hands over the
cooldown''s consequence rather than its rule so the number keeps living in exactly one place.
Never returns anyone else''s base, and never returns base_set_at or base_change_count raw.';

-- ═══ §7 the band vocabulary — five words, in ONE place ═════════════════════════════════════
-- The ladder lives here and only here, so a boundary can be moved in one edit and so the suite
-- has one object to pin.
-- ⚠ THIS COMMENT USED TO SAY the ladder is 「deliberately COARSE relative to the 0.01° base grid —
-- a fine ladder over a coarse lattice gives the lattice its resolution back」. **Measured false**
-- on 2026-08-25: the blind review re-ran its localization across FIVE band designs and the band
-- EDGES barely moved the result — an annulus's width sets how much ONE probe narrows, and the
-- intersection of many probes is dominated by the number of distinct CENTRES, not by their
-- width. So this ladder is coarse because coarse is what a runner needs to read at a glance
-- (「~1km」 is a decision; 「1,112 m」 is a location), not because it buys a privacy property.
-- The property comes from §4b's cooldown. Do not re-derive the boundaries from a safety argument
-- they cannot support; do move them if the product reads better.
-- Not STRICT: the NULL arm is written out because NULL is a real, meaningful answer here (no
-- address, no pin, or a poisoned row — §8's absence grammar) and a strict function would make
-- that path invisible to a reader.
create or replace function _distance_band(p_m double precision) returns text
language sql immutable as $$
  select case
    when p_m is null   then null::text
    when p_m < 1000    then '~1km'
    when p_m < 2000    then '1-2km'
    when p_m < 3000    then '2-3km'
    when p_m < 5000    then '3-5km'
    else                    '5km+'
  end
$$;

comment on function _distance_band(double precision) is
  '0123 §7 — the closed band vocabulary: ~1km · 1-2km · 2-3km · 3-5km · 5km+. THE single place
these five strings and their four boundaries exist. Metres go in; a metre NEVER comes out (158
N6). Coarse because a runner reads a decision, not a location — NOT because band width is a
privacy control: widening the ladder was measured (2026-08-25) to buy almost nothing against
multilateration, which is bounded by §4b''s cooldown instead. See 0123''s header.
⚠ DELIBERATELY NO ACL. It is not security definer (so 98 H1 and 99 S1 do not watch it, correctly)
and it reads nothing: metres in, one of five strings out. anon may call it and learn that 1500 is
「1-2km」, which is the ladder this comment already publishes. Revoking it would imply the ladder is
a secret; the base and the pickup are the secrets, and neither is reachable from here.';

-- ═══ §8 the disclosure window — two flat columns, no metres, no coordinates ════════════════
-- Row set = **exactly what the caller can already see**, INHERITED from 0122 §3's arms rather
-- than re-typed, and inherited from 0122 rather than from the view directly for the same reason
-- 0122 gave: re-typing a predicate makes one gate two, and the next 0056 fixes one of them.
--   ⓐ `select id from marketplace_open_requests` — the 0042 view as narrowed by 0056, carrying
--      its five gates (status='matching' · runner_id is null · club_session_id is null ·
--      is_active_runner() · not-declined-by-me);
--   ⓑ the caller's own directed rows — `status = 'runner_pending' and runner_id = auth.uid()`,
--      club rows excluded on the same doctrine as the view.
-- `auth.uid() is not null` is written even though `col = auth.uid()` already yields nothing for
-- a NULL uid — 0122's belt, kept for 0122's reason (a bare `col = auth.uid()` is one schema
-- change away from the repo's most-repeated bug).
--
-- NO PARAMETERS, and that is the ruling made structural — and after the 2026-08-25 measurement
-- it is the single most load-bearing line in this function's signature. Under ruling B the base
-- is STORED, so there is nothing caller-supplied to quantize at call time and no argument a
-- caller could use to probe from a position they have not committed to. `open_request_distance(
-- p_lat, p_lng)` would not merely be "the same feature with a weaker contract": it would hand an
-- attacker UNLIMITED distinct centres per second, and the review's measured curve (81+ probes →
-- a point) says that resolves a stranger's pickup exactly. The cooldown in §5 works only because
-- a centre must be COMMITTED to be observed from. Adding a parameter here deletes it entirely.
--
-- NULL BASE → ZERO ROWS, structurally: the base subquery is a source of the join, so a runner
-- with no base produces an empty relation before any booking is considered. The client renders
-- nothing and offers the settings door. (It must distinguish that from a dead RPC leg — see
-- api.ts; a failed leg renders nothing at all, no door, because we do not know.)
--
-- LEFT JOIN, and the poison check rides the ON clause — 0122 §3's exact decision, for its exact
-- reason: a booking with no address, an address with no pin, and an address whose owner ≠ the
-- booking's owner (0060's poisoned-row case) all produce the SAME answer, a present row with a
-- NULL band. `_route_dist_m` is STRICT, so a NULL coordinate short-circuits to NULL and
-- `_distance_band(null)` is NULL — one shape, one meaning, no inference channel. An inner join
-- would instead make "this booking has no address" a visible fact.
create or replace function open_request_distance()
returns table (booking_id uuid, distance_band text)
language sql stable security definer set search_path = public, pg_temp as $$
  select b.id,
         _distance_band(_route_dist_m(
           rb.base_lat::double precision, rb.base_lng::double precision,
           a.lat::double precision,       a.lng::double precision))
  from (
    select r.base_lat, r.base_lng
    from runners r
    where auth.uid() is not null
      and r.profile_id = auth.uid()
      and r.base_lat is not null
  ) rb
  cross join (
    select id from marketplace_open_requests
    union
    select b2.id from bookings b2
    where b2.status = 'runner_pending'
      and auth.uid() is not null
      and b2.runner_id = auth.uid()
      and b2.club_session_id is null
  ) v
  join bookings b on b.id = v.id
  left join addresses a on a.id = b.address_id and a.owner_id = b.owner_id
$$;

revoke execute on function open_request_distance() from public, anon;
grant  execute on function open_request_distance() to authenticated;

comment on function open_request_distance() is
  'Distance BANDS from the caller''s stored base to the pickup of each request they can already
see (0123 §8, Sean''s Q6 ruling B 2026-08-25). Flat two columns (booking_id, distance_band) —
never metres, never a coordinate, never an address or an address id, never a 동. No parameters:
under ruling B the base is stored, so there is nothing to supply and nothing to probe from.
Row set = marketplace_open_requests (the 0042/0056 choke point, INHERITED not re-typed) ∪ the
caller''s own runner_pending non-club rows — the same two arms as open_request_pickup_dong()
(0122 §3), which this file does not touch. No base = 0 rows. NULL distance_band = unknown (no
address, no pin, or a poisoned row) and the client renders absence, never a placeholder. No JWT
= 0 rows, never an exception. STABLE: writes nothing, including no 제16조 access ledger — the
caller is measuring from their OWN stored base and is never handed anyone else''s position; if
counsel Q3 says otherwise the remedy is this one function, which is why it is a single choke
point (header).';
