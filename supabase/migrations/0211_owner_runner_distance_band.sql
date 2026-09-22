-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0211 — the OWNER direction of the distance band (0123's mirror), with the cooldown carried over
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 242_owner_runner_distance_band_suite.sql (tag `ordb`)
--        0211-P1 · P2 · P3 · P4 · P5 · P6 · S1
-- Deploy: `supabase db push` only, plus a client build. No edge function, no cron, no secret,
--         no enum, no table grant to any client role.
--
-- ─── §0 WHAT IS MISSING, MEASURED ON TRUNK 6d02769 ─────────────────────────────────────────────
-- `fetchCertifiedRunners` (api.ts) orders the owner's runner shelf by `total_runs` and the card
-- prints `r.district || '근처'`. Its own comment says, verbatim:
--   「Real nearest-first needs a runner home-base coordinate, which the schema does not have.」
-- **That sentence has been false since 0123 landed.** `runners.base_lat` / `base_lng` exist
-- (0123 §1), `runner/base-pin.tsx` writes them through `set_runner_base` (0123 §5), and the
-- RUNNER direction of the band has shipped since the same day (`open_request_distance`, 0123 §8).
-- So the owner is the only party in this product who is shown a proximity WORD (「근처」) with no
-- proximity FACT behind it, while the fact sits one join away.
--
-- ⚠ 「근처」 is the honesty defect, not the ranking. `district` is the RUNNER's own 동네 string
--   (`profiles.district`, 0001:32) and has never been compared to the reader's; the owner-home
--   comment at `owner/home.tsx:769` records Sean catching exactly that in a screenshot
--   (「성수 계정에 반포동 러너가 「동네」로 걸렸다」) and renaming the shelf rather than fixing it,
--   because the fix needed this file. This slice removes the word and puts a measured band where
--   it was — and where there is no band, it puts NOTHING (never a placeholder).
--
-- ─── §0a WHAT THIS FILE IS NOT ────────────────────────────────────────────────────────────────
--   ✗ it does not touch `open_request_distance()` (0123 §8), `open_request_pickup_dong()`
--     (0122 §3), `set_runner_base` / `my_runner_base` / `_distance_band` / `_base_change_cooldown`
--     (0123 §5/§6/§7/§4b) or `_route_dist_m` (0082 §D) by a byte. It CALLS three of them. A second
--     band ladder or a second haversine would be two rules one refactor apart — 0123's own §0
--     refusal, transcribed;
--   ✗ it never returns metres, a coordinate, an address, an address id, or a 동. Two flat columns,
--     `(runner_id uuid, band text)`, and the band is one of `_distance_band`'s five closed
--     strings or NULL. ⚠ 0122's blind review measured that a TYPE seals numbers and not TEXT, so
--     242 asserts VALUES from a fixture at a known separation, never shapes;
--   ✗ it does not re-create `runners`' read grant (0121 §O owns it) and adds no column to
--     `runners`, `profiles` or `addresses`;
--   ✗ it does not rate-limit an owner's ability to CHANGE their address. An address is how this
--     product books a walk; a cooldown on editing one would be a privacy control charged to the
--     core flow. §2 bounds the observation CENTRE instead, which is the thing the attack needs.
--
-- ─── §0b THE ATTACK, AND WHY THE RUNNER DIRECTION'S DEFENCE DOES NOT COME FREE ─────────────────
-- 0123's header records the measurement that settles the shape of this file, and it was measured
-- against the runner direction on 2026-08-25: 323 probes through the two real RPCs localized a
-- stranger's pickup to **8.8 m**. The mechanism, in that header's own words, is that 「an
-- observation is an annulus whose WIDTH comes from the band ladder and whose CENTRE is a lattice
-- vertex, and intersecting annuli with DIFFERENT centres shrinks the feasible region without
-- bound」 — so what bounds disclosure is **the rate at which one account can produce a new
-- CENTRE**, and 0123 §5 enforces exactly that with `_base_change_cooldown()` (7 days, Sean's
-- ruling, 0123 §4b).
--
-- 🔴 **THAT COOLDOWN IS KEYED TO THE RUNNER DIRECTION ONLY, AND IT DOES NOT CROSS OVER.** In
-- 0123 §8 the observer's centre is `runners.base_lat/base_lng` — a value that can only be written
-- through `set_runner_base`, which refuses a second write inside the cooldown. In THIS direction
-- the observer is an owner and their centre is their default address, which they may add, edit,
-- re-pin and re-default as often as they like (`addresses`, 0001:117; `_guard_address_dong`,
-- 0122 §2, guards the DERIVED 동 and nothing about the rate). So a straight mirror of §8 — 「read
-- the caller's address, measure, return a band」 — would hand an owner **unlimited distinct
-- centres per second** against every certified runner in the pool. That is precisely the shape
-- 0123 §8's 「NO PARAMETERS」 paragraph refuses, arriving through the address book instead of
-- through an argument, and it would be the weaker of the two directions by a wide margin.
--
-- **§2 is the symmetric extension, and it is the smallest one that exists.** The owner's
-- observation centre is PINNED on first use and may move once per `_base_change_cooldown()` —
-- the same interval, the same function, the same 「last SUCCESSFUL move」 clock semantics as
-- `runners.base_set_at`, and the same after-the-fact counter as `base_change_count`. An owner who
-- asks from the pinned cell always gets an answer; an owner whose default address has moved to a
-- different cell inside the cooldown gets **zero rows** until it elapses. So:
--   annuli per account ≤ centre moves ≤ elapsed / cooldown — 0123's claim (ii), word for word.
--
-- ⚠ **WHY A ROW AND NOT A DERIVED CLOCK.** `addresses` has `created_at` and no update stamp, and
--   an owner with several saved addresses can produce a new centre by flipping `is_default` with
--   no row written at all. There is no existing column from which 「how many distinct centres has
--   this account observed from」 can be read. The pin is two quantized numbers, a timestamp and a
--   counter — the exact four values 0123 §1 put on `runners`, for the exact same job, on the one
--   table that can hold them for an owner.
-- ⚠ **AND IT IS NOT ONE OF THE FOUR THINGS SEAN RULED OUT.** 0123 §4b names them: 「a band freeze
--   table, a coordinate history, a per-address probe ledger, a velocity heuristic」. This is none
--   of those — it stores no band, no history (one current cell, overwritten), nothing per-address
--   and no heuristic. It is the cooldown he DID rule, in the only place an owner's copy of it can
--   live. **If he would rather ship this direction with no bound at all, §1 and §2 are one object
--   and one branch to delete; that is his call and not this file's.**
--
-- ─── §0c THE LADDER — what is measured, what is read, and what is neither ──────────────────────
-- 0123's header carries a claim its own review measured FALSE, and the correction is written
-- there as a warning to exactly this file: a coarse lattice under the OBSERVER does not coarsen
-- the ANSWER. So the ceiling below is stated as a LADDER (CLAUDE.md: write the rung, not the
-- verdict) and the two rungs are deliberately not summed.
--
--   | rung                                                             | status |
--   |---|---|
--   | the TARGET of this direction is `runners.base_lat/base_lng`, which `runners_base_grid` (0123 §1) CHECKs onto a 0.01° (~1.1 km) lattice — so the datum itself holds no finer answer, and a perfect localization returns one ~1.1 km cell | **READ** from the live constraint; `0211-S1` asserts the constraint is still there and ENFORCED, so this rung cannot go stale silently |
--   | whether N annuli actually identify WHICH lattice vertex | **NOT MEASURED HERE.** Assume yes. 0123's curve (16 probes → ~0.15 km) is about a continuous target and does not transfer as a number |
--   | one account produces at most one new centre per `_base_change_cooldown()` | **MEASURED**, `0211-P4` |
--   | K colluding accounts get K annuli at once | **IRREDUCIBLE and WORSE HERE THAN IN 0123** — see below |
--
-- 🔴 **THE ASYMMETRY THAT MUST NOT BE HIDDEN.** 0123's claim (iii) accepts collusion on the
-- ground that 「the pool is gated on `is_active_runner()` (certified identity — 본인인증 +
-- 신원확인, so accounts are not free)」. **That argument is not available here.** This window's
-- caller is an owner, and an owner account is an ordinary signup. So the per-account cooldown
-- bounds a PERSON only as far as they are willing to make accounts, and the honest ceiling for a
-- determined multi-account adversary is the first rung: **the ~1.1 km cell the runner themselves
-- declared**, which is the same order as the 동 that `profiles.district` already prints on the
-- runner's public card and that `open_request_pickup_dong` (0122) already discloses in the other
-- direction. That is the whole of what this window can ever give up, and it is said here rather
-- than left for a reviewer to find. Exits, if Sean wants it bounded further and NOT re-derived by
-- a later session: gate the window on an owner who has completed a booking (an account with a
-- payment history is not free), or do not ship the owner direction. Both are product calls.
--
-- ─── §0d DATA CLASSIFICATION — this direction discloses a THIRD PARTY's derived position ───────
-- ⚠ **0123 §8's 제16조 (접근기록) argument DOES NOT CARRY OVER, and pretending it does would be
-- the worst thing in this file.** That function writes no access ledger because, in its own
-- words, 「the caller is reading THEIR OWN stored base and is never handed anyone else's」 — the
-- pickup it measures against is the caller's counterparty in a request the caller can already
-- see. **Here the band is a fact derived from the RUNNER's stored 개인위치정보 and handed to an
-- owner**, and no amount of banding changes whose datum it is about.
-- What stands in front of it, stated as facts rather than as comfort:
--   · the disclosed value is one of five closed strings, never a metre and never a coordinate;
--   · it is derived from a value the runner themselves quantized to ~1.1 km before storing it;
--   · the runner OPTED IN by setting a base at all, and can clear it at any time through
--     `set_runner_base(null, null)` — after which this window returns NULL for them forever, with
--     no other state to unwind (0123 §5's clearing door is the off switch for BOTH directions,
--     and `0211-P2` measures that it is);
--   · the row set is exactly the pool the caller can already enumerate (§3).
-- 🔴 **STILL FLAGGED, NOT ASSUMED AWAY:** counsel Q3 in `docs/biz/location-law-counsel-brief.md`
-- is open, and if an access record is owed anywhere in this product it is owed HERE FIRST — this
-- is the only window in the repo that hands one party a derived fact about another party's stored
-- position. `location_access_log` does not exist yet (0115:743 and 0122:32 name it as the
-- forward-looking shape; grep confirms zero occurrences outside comments). The remedy, when it
-- does, is ONE function — this one — which is why it is a single choke point, the same reason
-- 0122 and 0123 each gave for theirs.
--
-- ─── §0e THE CONSEQUENCE THE COOLDOWN CHARGES THE HONEST OWNER ────────────────────────────────
-- An owner who genuinely moves house, or who switches their default to a second saved address
-- more than ~1.1 km away, sees **no distance chips at all** until the cooldown elapses. Two
-- decisions behind that, both deliberate:
--   · **no rows rather than a stale band.** Measuring from the pinned centre would keep the chip
--     alive and make it say 「this runner is ~1km from you」 about a place the owner no longer
--     lives. A band computed from an abandoned address is a fabricated field with a real number
--     on it — CLAUDE.md's first honesty law, and the failure mode is that nobody can tell;
--   · **it is the same bill the runner already pays.** 0123 §4b states it in one line: 「a runner
--     who actually moves house waits a week to see honest distances」. The owner direction is not
--     entitled to a lighter version of the trade the ruled direction makes.
-- The client renders absence the way it renders every other absent band — the chip is simply not
-- drawn, no placeholder, no explanation invented (`api.ts`, `owner/home.tsx`). ⚠ **NAMED GAP:**
-- the owner is not TOLD why the chips went away. `my_runner_base()`'s `can_change_at` is 0123's
-- answer to the same problem on the runner side, and the analogous read here would be a second
-- function. It is not built, because a missing optional chip is not a dead button (there is no
-- control to press), and inventing a sentence is how this becomes two features.

-- ═══ §1 the observation centre — one row per owner, sealed by construction ═════════════════════
-- Four values, and they are 0123 §1's four with the same jobs:
--   centre_lat/centre_lng   ← base_lat/base_lng        (the committed centre, 0.01°-quantized)
--   pinned_at               ← base_set_at              (the cooldown's clock — THE defence)
--   centre_change_count     ← base_change_count        (after-the-fact pattern visibility)
-- ⚠ NO HISTORY OF OLD CENTRES, ever, for 0123 §1's reason said again because it applies again: a
-- history of an account's past centres is exactly the trail a probing attacker drew, and storing
-- it would be keeping the attack for them. One current cell, overwritten in place.
-- `centre_change_count` counts SUCCESSFUL moves and not asks, so it is an upper bound on how many
-- distinct annulus centres this account has ever produced (`0211-P4` reads it back).
-- FK is `on delete cascade`: a real row deletion takes the pin with it. The TOMBSTONE path — the
-- one this product actually uses (0115 §B keeps the profile row forever) — is §4.
create table owner_distance_centres (
  profile_id          uuid primary key references profiles on delete cascade,
  centre_lat          numeric(9,6) not null,
  centre_lng          numeric(9,6) not null,
  pinned_at           timestamptz  not null default now(),
  centre_change_count int          not null default 0
);

-- THE GRID IS A CONSTRAINT, NOT A HABIT — 0123 §1's sentence, and its warning with it. §2 rounds,
-- but §2 is one writer and this column will outlive it. ⚠ CALIBRATED: what this buys is the
-- resolution of a SINGLE observation and it is NOT what stops multilateration (0123's lattice
-- claim was measured false on 2026-08-25). Keep the belt; do not re-promote it to the defence.
alter table owner_distance_centres add constraint owner_distance_centres_grid check (
  centre_lat = round(centre_lat, 2) and centre_lng = round(centre_lng, 2)
);

-- 🔴 SEALED FROM EVERY CLIENT ROLE, TWO WAYS, AND BOTH ARE LOAD-BEARING.
-- ⚠ Supabase's default privileges grant `all on tables` to `anon, authenticated` for every table
--   postgres creates (production, and `00_shim.sql:128` mirrors it) — so a new table is
--   client-readable AND client-writable the instant it exists unless this line runs. A client
--   that could UPDATE `pinned_at` would delete the cooldown entirely, which is the same
--   load-bearing half 0123 §3 names on `runners`: the coordinates cost resolution on one
--   observation, the CLOCK costs the whole bound.
-- RLS is enabled with ZERO policies on top of the revoke (0084 §E's shape) so that a future
-- migration which widens a grant does not silently open this table as well. The writer in §2 is
-- SECURITY DEFINER and runs as the table's owner, which is not subject to its own RLS.
revoke all on owner_distance_centres from public, anon, authenticated;
alter table owner_distance_centres enable row level security;

comment on table owner_distance_centres is
  '0211 §1 — 보호자 계정의 **관측 중심점**. 0123 §5의 쿨다운을 소유자 방향으로 옮긴 것이고, 그게
이 테이블의 유일한 존재 이유다: 러너의 기준 위치는 `set_runner_base`만 쓸 수 있어 이동 횟수가
이미 묶여 있지만, 보호자의 중심은 기본 주소라 마음대로 바꿀 수 있다 — 묶지 않으면 초당 무제한의
서로 다른 중심을 만들 수 있고, 그게 다변측량을 푸는 유일한 자원이다 (0123 헤더의 측정).
네 값은 0123 §1의 네 값과 같은 일을 한다: centre_lat/lng = 커밋된 중심(0.01° 양자화) ·
pinned_at = 쿨다운 시계(실제 방어선) · centre_change_count = 사후 가시성.
**옛 중심의 이력은 어디에도 저장하지 않는다** — 그건 공격자가 그린 궤적을 우리가 대신 보관하는
것이다. RLS on + 0 policies + 모든 클라이언트 롤 revoke: 읽기도 쓰기도 §2의 definer 하나뿐.';
comment on column owner_distance_centres.pinned_at is
  '마지막으로 중심을 **옮긴** 시각. 같은 격자 칸에서의 재조회는 이 값을 건드리지 않는다 — 건드리면
매일 조회하는 보호자는 영원히 이사할 수 없고, 시계가 「마지막 성공한 이동」을 뜻하지 않게 된다
(0123의 base_set_at과 같은 의미론, 같은 이유).';

-- ═══ §2 · §3 the window — party gate, then the centre, then the bands ══════════════════════════
-- PARTY GATE BEFORE ANY READ (house law), and it is three conjuncts, all about the CALLER:
--   ① a JWT                     — `not_signed_in`
--   ② `profiles.role = 'owner'` — `not_an_owner`; a runner or a stranger is refused here, before
--      this function has looked at anybody's base. ⚠ This is a REFUSAL and not zero rows, which
--      is the opposite of 0123 §8's posture, on purpose: §8's caller is a runner browsing a pool
--      that is legitimately empty for them, so 0 rows is a real answer; here the caller is a
--      screen that only exists for owners, and a wrong-party call is a bug that must name itself.
--   ③ `deleted_at is null`      — 0123 §5's MINOR-2 fix, transcribed: `profiles` rows are KEPT
--      FOREVER (0115 §B), so without this a tombstoned account holding a live session keeps a
--      disclosure window open. §4 clears the pin; this stops it being re-created.
--
-- THE CENTRE, and the two things it must be:
--   · DETERMINISTIC. `addresses.is_default` has no unique constraint (0001:126), so an owner may
--     hold several. `order by created_at, id limit 1` makes 「the default address」 one row and not
--     whichever one postgres felt like — a non-deterministic pick would hand the attacker extra
--     centres for free, with nothing written and no clock consulted.
--   · QUANTIZED BEFORE IT IS COMPARED. The cell, not the point, is what the cooldown is about:
--     an owner correcting a pin by 40 m has not produced a new centre and must not be charged for
--     one, and an owner who moves 3 km has.
-- NO CENTRE → ZERO ROWS, structurally (the owner has no default address, or it has no pin). Same
-- grammar as 0123 §8's null base, same client rendering: nothing, and never a guessed cell.
--
-- 🔴 THE COOLDOWN, and the three branches are the whole of §0b:
--   ⓐ no pin yet      → pin the current cell, count 0, answer from it. The first observation is
--                        always allowed (0123 §5's 「first-ever set」, same rule);
--   ⓑ same cell       → answer, and DO NOT touch the clock. If a re-ask refreshed `pinned_at`,
--                        an owner who opens their home screen daily could never move at all, and
--                        the stamp would stop meaning 「last successful move」;
--   ⓒ different cell, cooldown elapsed → move the pin (CAS on the same predicate, so two
--                        concurrent callers cannot both spend the one move), count it, answer;
--   ⓓ different cell, inside the cooldown → **RETURN ZERO ROWS.** No band from the new centre
--                        (that is the annulus the attack wants) and no band from the old one
--                        (that would be a fabricated distance — §0e).
--
-- ROW SET = EXACTLY THE POOL THE CALLER CAN ALREADY ENUMERATE, and it is transcribed from
-- `runners`' own RLS rather than invented: 0002/0093's `"runners public read" … using (tier <>
-- 'applicant' or profile_id = auth.uid())`. It has to be transcribed — this function is a definer
-- (it must be: §2 of 0123 revoked `base_lat` from every client role, so an INVOKER body could not
-- read the column at all), and a definer does not see the policy. `0211-P3` is the arm that
-- measures the transcription rather than trusting it.
-- ⚠ A runner with NO BASE is a PRESENT ROW with a NULL band, not an absent one: `_route_dist_m`
--   is STRICT, so a NULL coordinate short-circuits and `_distance_band(null)` is NULL. One shape,
--   one meaning — 「we cannot say how far」 — and the client omits the chip. A tombstoned runner
--   lands in the same bucket, because §4 of 0123 cleared their base; that conflation is deliberate
--   (an absent row would make 「this account is deleted」 a visible fact).
-- ⚠ THE CAP is a screen's worth and it RAISES rather than truncating. A silently truncated answer
--   is a list that lies about its own completeness; `too_many_runners` is a caller bug that names
--   itself. It buys no privacy (a longer array produces no new CENTRE, and centres are the whole
--   resource) and is not sold as if it did.
create or replace function owner_runner_distance_bands(p_runner_ids uuid[])
returns table (runner_id uuid, band text)
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  v_uid       uuid := auth.uid();
  v_lat       numeric;
  v_lng       numeric;
  v_pin_lat   numeric;
  v_pin_lng   numeric;
  v_pinned_at timestamptz;
begin
  if v_uid is null then
    raise exception 'not_signed_in';
  end if;
  if not exists (
    select 1 from profiles p
     where p.id = v_uid and p.role = 'owner' and p.deleted_at is null
  ) then
    raise exception 'not_an_owner'
      using detail = '보호자 계정에서만 볼 수 있어요';
  end if;

  -- a caller bug, named. `coalesce(array_length(...), 0)` because array_length of an empty array
  -- is NULL and plpgsql takes a NULL `if` as false — the collapse CLAUDE.md records, written out
  -- here rather than relied upon.
  if coalesce(array_length(p_runner_ids, 1), 0) > 50 then
    raise exception 'too_many_runners'
      using detail = '한 번에 너무 많은 러너를 물었어요';
  end if;

  select round(a.lat, 2), round(a.lng, 2)
    into v_lat, v_lng
    from addresses a
   where a.owner_id = v_uid
     and a.is_default
     and a.lat is not null
     and a.lng is not null
   order by a.created_at, a.id
   limit 1;
  if v_lat is null then
    return;                                   -- no centre → 0 rows, the 0123 §8 grammar
  end if;

  select c.centre_lat, c.centre_lng, c.pinned_at
    into v_pin_lat, v_pin_lng, v_pinned_at
    from owner_distance_centres c
   where c.profile_id = v_uid;

  -- §0b: the cooldown is the defence — one new CENTRE per account per interval, and nothing else
  -- in this function bounds anything. The three branches below are that rule and only that rule.
  -- ⚠ `on conflict on constraint`, never `on conflict (profile_id)`: an inference spec is an
  --   EXPRESSION context, so plpgsql resolves its names against this function's own `returns
  --   table` OUT parameters — the runtime `column reference is ambiguous` that 0208 shipped past a
  --   clean apply and a green gate pin. The named form has no expression context at all.
  if v_pin_lat is null then                   -- ⓐ first observation, always allowed
    insert into owner_distance_centres (profile_id, centre_lat, centre_lng, pinned_at,
                                        centre_change_count)
    values (v_uid, v_lat, v_lng, now(), 0)
    on conflict on constraint owner_distance_centres_pkey do nothing;
    -- re-read: a concurrent first call may have won the insert, and its cell is then the pin
    select c.centre_lat, c.centre_lng, c.pinned_at
      into v_pin_lat, v_pin_lng, v_pinned_at
      from owner_distance_centres c
     where c.profile_id = v_uid;
    if (v_pin_lat, v_pin_lng) is distinct from (v_lat, v_lng) then
      return;                                 -- the winner pinned a different cell; ⓓ applies
    end if;
  elsif (v_pin_lat, v_pin_lng) is distinct from (v_lat, v_lng) then
    if v_pinned_at > now() - _base_change_cooldown() then
      return;                                 -- ⓓ moved inside the cooldown → ZERO ROWS
    end if;
    update owner_distance_centres c           -- ⓒ elapsed: spend the one move, CAS-guarded
       set centre_lat = v_lat, centre_lng = v_lng, pinned_at = now(),
           centre_change_count = c.centre_change_count + 1
     where c.profile_id = v_uid
       and c.pinned_at <= now() - _base_change_cooldown();
    if not found then
      return;                                 -- a concurrent caller spent it first
    end if;
  end if;
  -- ⓑ falls through with the pin untouched — no write, no clock move

  return query
    select r.profile_id,
           _distance_band(_route_dist_m(
             v_lat::double precision,       v_lng::double precision,
             r.base_lat::double precision,  r.base_lng::double precision))
      from runners r
     where r.profile_id = any(p_runner_ids)
       and (r.tier <> 'applicant' or r.profile_id = v_uid);
end $$;

revoke execute on function owner_runner_distance_bands(uuid[]) from public, anon;
grant  execute on function owner_runner_distance_bands(uuid[]) to authenticated;

comment on function owner_runner_distance_bands(uuid[]) is
  'Distance BANDS from the caller''s own default address to each named runner''s stored activity
base (0211 §2/§3) — the OWNER-side mirror of open_request_distance() (0123 §8), sharing its band
ladder (_distance_band, 0123 §7) and its haversine (_route_dist_m, 0082 §D). Flat two columns
(runner_id, band): never metres, never a coordinate, never an address, never a 동. Party gate
BEFORE any read — a JWT, profiles.role = ''owner'', and a live profile; a runner or a stranger is
REFUSED (not_an_owner), which is deliberately unlike §8''s 0-rows posture because this screen only
exists for owners. Row set is transcribed from `runners`'' own RLS (tier <> ''applicant'' or self)
because a definer does not see the policy; a runner with no base is a PRESENT row with a NULL band
(_route_dist_m is STRICT) and the client omits the chip. No default address, or one with no pin =
0 rows. 🔴 ANTI-PROBING: the caller''s observation CENTRE is pinned to a 0.01° cell on first use
and may move at most once per _base_change_cooldown() (0123 §4b, Sean''s 7 days) — asking again
from the SAME cell never touches the clock, and asking from a DIFFERENT cell inside the cooldown
returns ZERO ROWS rather than a band from either centre. Without that, an owner''s address book
would be an unlimited supply of annulus centres, which 0123''s review measured to be the ONE
resource multilateration needs (323 probes → 8.8 m in the other direction). ⚠ Unlike §8 this
window hands one party a fact derived from ANOTHER party''s stored 개인위치정보 — 0123 §8''s
「own base」 access-record argument does NOT carry over. Counsel Q3 is open and the remedy is this
one function. See 0211 §0b–§0e.';

-- ═══ §4 account deletion — the pin dies with the account ═══════════════════════════════════════
-- 0123 §4's mechanism, for 0123 §4's reason, on this file's own table: `delete_my_account_tx`
-- (0115) is a named-column allowlist that cannot know about state added later, and the profile row
-- is KEPT FOREVER as an FK anchor — so 0115:443's invariant (「LOCATES NOTHING AND IDENTIFIES
-- NOBODY」) would quietly become false the day this table shipped. A ~1.1 km cell locates
-- something. The cascade rides the TOMBSTONE stamp rather than 0115's statement order, so it holds
-- for any future deletion path and 0115 needs no edit — and this file re-creates NOTHING there,
-- which is the silent-revert trap 0086 §B records.
-- ⚠ SECURITY DEFINER, and the revoke below is not optional: 99 S1 sweeps EVERY prosecdef function
--   in `public` for anon-executability, trigger functions included, and 0123 §4 measured that
--   flipping exactly this kind of function to DEFINER without the revoke reddens S1 on its own.
create or replace function _owner_distance_centre_tombstone() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  delete from owner_distance_centres where profile_id = new.id;
  return null;
end $$;

revoke execute on function _owner_distance_centre_tombstone() from public, anon, authenticated;

drop trigger if exists _owner_distance_centre_tombstone_tg on profiles;
create trigger _owner_distance_centre_tombstone_tg after update on profiles
  for each row
  when (new.deleted_at is not null and old.deleted_at is distinct from new.deleted_at)
  execute function _owner_distance_centre_tombstone();

comment on function _owner_distance_centre_tombstone() is
  '0211 §4 — a tombstoned profile (profiles.deleted_at, 0115 §B) cannot keep an observation centre.
DELETE and not a blanking: unlike 0123 §4''s runners row, which is an FK anchor other tables point
at, this row exists only to rate-limit a live account and a dead account can never observe again
(§2''s party gate refuses a tombstone). Fires on the stamp itself, so it does not depend on
delete_my_account_tx''s statement order and 0115 is byte-untouched. Does not re-create
_runner_base_tombstone (0123 §4); both triggers fire.';

-- ═══ §5 VERIFY — apply-time, on whatever database this file actually lands on ══════════════════
-- The suite asserts these against the schema the harness builds from scratch; this block asserts
-- them against the schema THIS file just built, and aborts before anything downstream runs
-- (0131-G4: a property checked only at apply is protected until someone recreates the object, and
-- one checked only in a suite is not checked on the environment the file lands on).
-- ⚠ Comments are STRIPPED before every source match. `prosrc` is source PLUS our own prose, and
--   this body documents its own guards in comments — an un-stripped match would be satisfied by
--   the writing that EXPLAINS the guard (CLAUDE.md, the comment-matching law). Arm ⑧ is the crude
--   control that the stripper did something.
do $$
declare
  v_bad text := '';
  v_src text;
  v_raw text;
  v_oid oid;
begin
  select p.oid into v_oid from pg_proc p
   where p.proname = 'owner_runner_distance_bands' and p.pronamespace = 'public'::regnamespace;
  -- absence must be LOUD: every arm below is vacuously true on a function that is not there.
  if v_oid is null then v_bad := v_bad || ' MISSING(owner_runner_distance_bands)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' NOT-DEFINER'; end if;
    if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
          from pg_proc where oid = v_oid) is distinct from true
      then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH'; end if;
    -- a CREATE is born PUBLIC-executable (0116:636). The NULL arm goes FIRST, because
    -- aclexplode(NULL) returns zero rows and an `exists` test alone is silent on exactly that.
    if (select proacl from pg_proc where oid = v_oid) is null
      then v_bad := v_bad || ' DEFAULT-PUBLIC-ACL';
    elsif exists (select 1 from pg_proc p, aclexplode(p.proacl) a
                   where p.oid = v_oid and (a.grantee = 0 or a.grantee = 'anon'::regrole))
      then v_bad := v_bad || ' PUBLIC-OR-ANON'; end if;
    -- the positive half: a seal that also shut the front door ships an outage.
    if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true
      then v_bad := v_bad || ' AUTHENTICATED-CANNOT'; end if;
    -- ① no metre / coordinate column on the way out — §0a's refusal, by NAME not by care
    if exists (select 1 from unnest((select proargnames from pg_proc where oid = v_oid)) n
                where n in ('distance_m', 'metres', 'meters', 'lat', 'lng', 'base_lat', 'base_lng',
                            'dong', 'address_id'))
      then v_bad := v_bad || ' COORDINATE-OR-METRE-ON-THE-WIRE'; end if;
    -- ② no caller-supplied centre. `open_request_distance(p_lat, p_lng)` is the shape 0123 §8
    --    refuses in its own header, and it would delete the cooldown outright.
    if exists (select 1 from unnest((select proargnames from pg_proc where oid = v_oid)) n
                where n in ('p_lat', 'p_lng', 'p_from_lat', 'p_from_lng', 'p_owner', 'p_uid'))
      then v_bad := v_bad || ' TAKES-A-CENTRE-OR-A-SUBJECT'; end if;

    select prosrc into v_raw from pg_proc where oid = v_oid;
    if v_raw is null or btrim(v_raw) = '' then
      v_bad := v_bad || ' NO-SOURCE(owner_runner_distance_bands)';
    else
      v_src := regexp_replace(v_raw, '--[^' || chr(10) || ']*', '', 'g');
      -- ③ the party gate, and that it is the caller's own uid and a live owner
      if (v_src ~ 'not_an_owner') is distinct from true
        then v_bad := v_bad || ' NO-PARTY-REFUSAL'; end if;
      if (v_src ~ 'p\.role = ''owner''') is distinct from true
        then v_bad := v_bad || ' NO-OWNER-ROLE-GATE'; end if;
      if (v_src ~ 'p\.deleted_at is null') is distinct from true
        then v_bad := v_bad || ' NO-TOMBSTONE-GATE'; end if;
      -- ④ THE COOLDOWN IS THE DEFENCE (§0b). Both halves: the interval comes from 0123 §4b's one
      --    named place, and the comparison is against the pin's own clock.
      if (v_src ~ '_base_change_cooldown\(\)') is distinct from true
        then v_bad := v_bad || ' NO-COOLDOWN(the owner direction is unbounded)'; end if;
      if (v_src ~ 'v_pinned_at > now\(\) - _base_change_cooldown\(\)') is distinct from true
        then v_bad := v_bad || ' COOLDOWN-NOT-COMPARED-TO-THE-PIN'; end if;
      -- ⑤ the band comes from 0123 §7's ladder and the distance from 0082 §D's haversine —
      --    a private copy of either is two rules one refactor apart
      if (v_src ~ '_distance_band\(_route_dist_m\(') is distinct from true
        then v_bad := v_bad || ' BAND-NOT-FROM-THE-SHARED-LADDER'; end if;
      -- ⑥ the row set is transcribed from `runners`' RLS, not widened
      if (v_src ~ 'r\.tier <> ''applicant''') is distinct from true
        then v_bad := v_bad || ' ROW-SET-WIDER-THAN-THE-POLICY'; end if;
      -- ⑦ the answer is measured from the CURRENT cell (v_lat/v_lng), never from the stored pin.
      --    Measuring from `v_pin_lat` would silently ship §0e's fabricated band.
      if (v_src ~ 'v_pin_lat::double precision') is not distinct from true
        then v_bad := v_bad || ' ANSWERS-FROM-THE-STALE-PIN'; end if;
      -- ⑧ CRUDE CONTROL for the stripper: the RAW body contains a `--` comment opening with
      --    「§0b: the cooldown is the defence」, so a stripper that silently did nothing would make
      --    ③–⑦ pass for the wrong reason and this arm is the only thing that can tell.
      if (v_raw ~ '§0b: the cooldown is the defence') is distinct from true
        then v_bad := v_bad || ' STRIP-CONTROL-ABSENT(the source arms above prove nothing)'; end if;
    end if;
  end if;

  -- ⑨ §1's seal, both mechanisms. A grant arm alone would be a false arm on a table whose
  --    default privileges were never revoked, and an RLS arm alone is silent on a direct grant.
  if (select relrowsecurity from pg_class where oid = 'owner_distance_centres'::regclass)
       is distinct from true
    then v_bad := v_bad || ' CENTRES-TABLE-RLS-OFF'; end if;
  if exists (select 1 from pg_class c, aclexplode(c.relacl) a
              where c.oid = 'owner_distance_centres'::regclass
                and a.grantee in (0, 'anon'::regrole, 'authenticated'::regrole))
    then v_bad := v_bad || ' CENTRES-TABLE-CLIENT-GRANT'; end if;
  -- ⑩ the grid CHECK on the pin, and 0123's on the target. The second is a READ this file's
  --    §0c ladder rests its first rung on — if 0123's constraint is ever dropped, that rung is
  --    gone and this VERIFY is where it must be noticed.
  if not exists (select 1 from pg_constraint
                  where conrelid = 'owner_distance_centres'::regclass
                    and conname = 'owner_distance_centres_grid' and contype = 'c')
    then v_bad := v_bad || ' CENTRE-GRID-CHECK-MISSING'; end if;
  if not exists (select 1 from pg_constraint
                  where conrelid = 'runners'::regclass
                    and conname = 'runners_base_grid' and contype = 'c' and convalidated)
    then v_bad := v_bad || ' TARGET-GRID-CHECK-MISSING(0123 §1 — §0c rung 1 is gone)'; end if;
  -- ⑪ the tombstone trigger exists AND is enabled. `pg_get_triggerdef` renders a DISABLED trigger
  --    identically (CLAUDE.md, 2026-08-26) — `tgenabled` is the state, the def is only the shape.
  if not exists (select 1 from pg_trigger
                  where tgrelid = 'profiles'::regclass
                    and tgname = '_owner_distance_centre_tombstone_tg'
                    and not tgisinternal and tgenabled = 'O')
    then v_bad := v_bad || ' TOMBSTONE-TRIGGER-MISSING-OR-DISABLED'; end if;

  if v_bad <> '' then raise exception '0211 VERIFY failed:%', v_bad; end if;
end $$;
