-- ═══ 0098: routes learn how much they climb — and the number stays tied to the geometry ═══
--
-- ═══ §0 WHAT THIS FILE IS ═══
-- Route geometry is sourced from Strava since Sean's 2026-08-14 ruling, and every ingested route
-- carries a measured elevation gain that currently has nowhere to live. The catalog is 32 rows
-- across 8 towns; 20 of them have GPX behind them and therefore a measured gain, ranging +0 m
-- (flat riverside) to +63 m (도곡 매봉산). The rest have geometry but no GPX — nothing has
-- measured them, and they stay NULL.
--
-- Without the column the backend cannot serve it, the client cannot show it, and an owner
-- choosing between a flat 5 km riverside loop and a 5 km loop over a hill sees the same thing.
-- For a DOG run that difference is not cosmetic — it is the difference between a walk and a
-- climb for an animal that cannot tell you it is struggling.
--
-- Surface: one column, one check constraint, one guard trigger, one backfill + its postcondition.
-- No view, no policy, no grant, no security-definer function. Verified rather than assumed:
-- `routes` has NO column-level grants anywhere in 0001-0097 (unlike `profiles`, where 0088/0091
-- make any new column a whitelist decision), and NO view in the repo selects from `routes`.
--
-- ═══ §0b DESIGN DECISION 1 — nullable, no default ═══
-- `NULL` means "no elevation is recorded for this row's current geometry". `0` means "the
-- measurement ran and returned zero". A `default 0` would collapse those and silently assert
-- that every unmeasured route is level ground — a claim nobody has made and no instrument has
-- checked. That is the class of error this catalog spent 2026-08-14 removing: a route named
-- "3km" that measured 5.4, and a row claiming `km` 2.0 whose geometry measures 1.6.
--
-- Not hypothetical: TWO of the measured values are genuinely 0 (잠실엘스 외곽 생활권 루프 and
-- 잠원 한신2차 리버 루프 — flat riverside, measured, really zero). 0-vs-NULL is a distinction
-- this dataset makes today, in real rows. A default would have destroyed information.
--
-- ⚠ Precision about what 0 proves, because the column comment must not overclaim: the
--   derivation discards elevation changes under 3 m as GPS noise, so 0 means "no accumulated
--   rise above the noise floor", NOT a survey-grade proof of physical flatness.
--
-- Consequence the client must honour, stated here because the column cannot enforce it:
-- rendering NULL as "0m" or "평지" re-introduces the lie at the last mile. NULL renders as
-- absent (the `unknownExcluded()` shape already shipped for `shade`/`lighting`), never as flat.
--
-- ═══ §0b-bis DESIGN DECISION 2 — elevation is a property OF A GEOMETRY, not of a name ═══
-- This is the correction that adversarial review (2026-08-14) forced, and it is the more
-- important half of the file. The first draft keyed the backfill on `(town, name)` alone. Two
-- ways that is wrong, both measured rather than imagined:
--
--   ⓐ **A name can outlive the geometry it described.** `0078:54` seeds
--      `('몽마르뜨 언덕 루프', 반포동)` with `trace '[]'` and `km 2.0`. The measured 34 m comes
--      from a 1.59 km GPX. On any database that has 0078's seeds but not the Strava ingest —
--      the harness, a fresh branch DB — a name-only join stamps "+34 m measured" onto a row
--      with NO GEOMETRY AT ALL. The migration would have committed exactly the lie it exists
--      to prevent, in the one environment where every reviewer would see it.
--   ⓑ **The geometry can be re-cut under a stable name.** Between this file being drafted and
--      being reviewed, upstream replaced `반포 서래섬 리버 루프 3.71km` with a re-cut
--      `3.31km`. A name-keyed payload for the 3.71 row silently matched ZERO rows and reported
--      success. One session was enough for the drift to happen once.
--
-- So the payload carries `km` as a geometry fingerprint and the join requires the row to have
-- real geometry. `routes.km` is `numeric(4,1)` and every ingested row's `km` is derived from its
-- own trackpoints, so a km match plus a non-empty trace is a cheap, honest statement that this
-- row IS the route that was measured. A row whose geometry was re-cut no longer matches, which
-- is correct — its old elevation was measured on a line that no longer exists.
--
-- §B-bis extends the same rule forward in time with a trigger, because a fingerprint checked
-- once at backfill says nothing about tomorrow.
--
-- ═══ §0c WHAT THIS FILE DELIBERATELY DOES NOT DO ═══
--
-- ⓐ **No `elevation_loss_m`.** Not because "loops are closed" — they are not: 반포 서래섬
--    carried a 215 m closure gap. Because nothing measures it and nothing reads it.
--    `build-manifest.mjs` computes gain only, so the column would ship 32 NULLs, and a NULL
--    column with no producer and no consumer is an unkept promise that reads as a missing
--    backfill. Add it in the slice that has both a value and a reader.
--
-- ⓑ **No turn cues, no progress, no route shape.** Those are FUNCTIONS of `trace`, computed at
--    render time by `route-guidance.mjs`. Storing them makes a second copy of a truth that can
--    drift. Elevation is different in kind: the source GPX carries `<ele>` per trackpoint,
--    `trace` does NOT (it is lat/lng only), so gain is not derivable from anything this
--    database stores. That is the test for whether a number earns a column.
--
-- ⓒ **`shade` and `lighting` untouched.** No geometry source supplies them. Sean ruled that
--    offering rows with unknown lighting is fine — that permits SERVING them, not inventing them.
--
-- ⓓ **`status` untouched; no route becomes `active`.** `routes_active_is_earned` (0082) needs a
--    `verified_run_id` from a settled run, set only by `promote_route_from_run`. No GPX can
--    satisfy it, by design.
--
-- ⓔ **`anchor_lat`/`anchor_lng` and their 0078 `근사값 — 소비 금지` comment untouched.**
--    Flipping that contract needs a provenance discriminator that does not exist yet (measured
--    2026-08-14: all 32 rows read `source='algo'`, so no `source` predicate separates
--    GPX-anchored rows from 0078's approximations). A different slice; not claimed here.
--
-- ⓕ **`active` is GENERATED since 0082.** Writing it is an error by construction. Nothing here
--    goes near it; noted because the backfill touches this table.
--
-- ═══ §0d WHERE THE NUMBERS COME FROM, AND WHY THEY ARE NOT REPRODUCIBLE FROM THIS TREE ═══
-- ⚠ Stated plainly because a reviewer looked for them and could not find them: the GPX corpus,
--   `build-manifest.mjs` and `route-properties.json` are NOT on this branch or on trunk. They
--   live in `docs/routes/strava/` on `claude/strava-route-loops-74c5d2` (route-geometry's tree).
--   Anyone re-deriving must read them from that ref, e.g.
--   `git archive origin/claude/strava-route-loops-74c5d2 docs/routes/strava | tar -x`.
--
-- What was actually done for these 20 values, 2026-08-14: `build-manifest.mjs` was re-run over
-- the GPX corpus rather than trusting the committed `manifest.json`, and it reproduced every
-- value; `route-properties.json` (keyed by production `routes.id`) agreed independently; and
-- every `(town, name, km)` triple below was verified against production to select exactly one
-- row, each with real geometry and `status='candidate'`.
--
-- The algorithm, written down because the column's meaning IS the algorithm: walk the
-- trackpoints, accumulate positive `<ele>` deltas against a moving reference, discard any change
-- under 3 m as GPS noise. This runs ~25% below Strava's own displayed figure — a definition
-- difference (Strava corrects against its own DEM), not a bug. Anyone who "fixes" the 25% by
-- scaling these numbers is fabricating a measurement.

-- ─────────────────────────────────────────────────────────────────────────────
-- §A  THE COLUMN
-- ─────────────────────────────────────────────────────────────────────────────
-- No `if not exists`. This is a numbered one-shot migration: `db push` applies it exactly once
-- and the harness applies from zero, so the guard buys nothing — and it would SILENTLY ACCEPT a
-- pre-existing `elevation_gain_m` of the wrong type or nullability and then comment and
-- constrain it as if it were this file's. Failing loudly on unexpected state is the point.
alter table routes
  add column elevation_gain_m integer;

comment on column routes.elevation_gain_m is
  'Cumulative ascent in metres for THIS ROW''S CURRENT geometry, derived from GPX trackpoint elevations: positive deltas summed against a moving reference, changes under 3m discarded as GPS noise. Runs ~25% below Strava''s own figure — a definition difference (Strava corrects against its own DEM), not a bug; do not scale it to agree. NULL means NO MEASUREMENT IS RECORDED for the current geometry — never "flat". 0 is a real computed value meaning no rise above the 3m noise floor, which is not the same as survey-grade flatness. Cleared automatically when `trace` changes (0098 §B-bis), because a gain measured on a replaced line describes a route that no longer exists. Not derivable from `trace`, which stores lat/lng only — which is why this is a column and not a computed function like closure or turn cues.';

-- ─────────────────────────────────────────────────────────────────────────────
-- §B  THE FLOOR, AND ONLY THE FLOOR
-- ─────────────────────────────────────────────────────────────────────────────
-- `>= 0` is safe by definition: cumulative ASCENT cannot be negative, and the derivation only
-- adds positive deltas, so a negative value can only arrive from a future writer that has
-- confused gain with net change. The constraint makes that loud at write time instead of letting
-- it render as a nonsense course card.
--
-- NO upper bound, deliberately. Seoul has real hills, this catalog already reaches +63 m on a
-- 7.7 km loop, and a ceiling picked from a 20-route sample would eventually reject a correct
-- measurement — the failure mode where a guard becomes the bug. No `not valid` needed: the
-- column was created NULL above, so the constraint validates immediately.
alter table routes
  add constraint routes_elevation_gain_nonneg
  check (elevation_gain_m is null or elevation_gain_m >= 0);

-- ─────────────────────────────────────────────────────────────────────────────
-- §B-bis  THE NUMBER FOLLOWS THE LINE IT MEASURED
-- ─────────────────────────────────────────────────────────────────────────────
-- `promote_route_from_run` (0082:136-148) REPLACES `trace` and `trace_thumb` with a
-- post-settlement, dog-run-derived trace. It knows nothing about this column, and it cannot be
-- taught without re-creating an object 0082 owns. Without this trigger, a promoted route keeps a
-- gain measured on the CANDIDATE line while every reader believes it describes the certified
-- one — the quietest possible form of the exact error this file was written to prevent. The
-- trace seeder has the same shape when it re-seeds changed geometry.
--
-- Rule: if `trace` changes and the same statement does not supply a new elevation, the old
-- elevation is not merely suspect, it is about a line that no longer exists → NULL, which is
-- this column's honest word for "nobody has measured the thing you are looking at". A writer
-- that DOES know the new gain sets both columns in one statement and is passed through.
--
-- Not security-definer (it needs no elevated rights and grants none), so 0055's definer sealing
-- and 98 H1 do not apply; `search_path` is pinned in the body anyway so a future `create or
-- replace` cannot silently inherit a caller's path.
create or replace function _routes_elevation_follows_geometry() returns trigger
language plpgsql
set search_path = public, pg_temp
as $fn$
begin
  if new.trace is distinct from old.trace
     and new.elevation_gain_m is not distinct from old.elevation_gain_m then
    new.elevation_gain_m := null;
  end if;
  return new;
end $fn$;

create trigger routes_elevation_follows_geometry
  before update on routes
  for each row execute function _routes_elevation_follows_geometry();

-- ─────────────────────────────────────────────────────────────────────────────
-- §C  BACKFILL — the rows whose CURRENT geometry is the one that was measured
-- ─────────────────────────────────────────────────────────────────────────────
-- Keyed on `(town, name, km)` rather than production uuids so the file means the same thing in
-- every environment, and on km rather than name alone for the reasons in §0b-bis. On a database
-- without the Strava ingest this updates only what genuinely matches — notably NOT 0078's
-- trace-less `몽마르뜨 언덕 루프` seed, which shares a name and differs in both km and geometry.
--
-- Four guards, each carrying its weight:
--   · `jsonb_array_length(r.trace) >= 2` — no geometry, no measurement. THE guard for ⓐ above.
--   · `r.km = v.km`                      — the geometry fingerprint. THE guard for ⓑ above.
--   · `r.elevation_gain_m is null`       — idempotent; never overwrites a later real measurement
--   · `status <> 'active'` + `verified_run_id is null` — the seeder's own refusals: a value
--                                          derived from an imported line must never overwrite
--                                          one earned by a dog-accompanied run
update routes r
   set elevation_gain_m = v.gain
  from (values
    ('도곡동', '도곡 매봉산 양재천 루프 7.66km', 7.7, 63),
    ('반포동', '몽마르뜨 언덕 루프', 1.6, 34),
    ('반포동', '몽마르뜨 언덕 루프 4.79km', 4.8, 46),
    ('반포동', '몽마르뜨 언덕 루프 5.4km', 5.4, 51),
    ('반포동', '반포 서래섬 리버 루프 3.31km', 3.3, 14),
    ('성수동', '성수 서울숲 루프 6.46km', 6.5, 22),
    ('송파동', '올림픽선수촌앞 올림픽 공원 4.58 km', 4.6, 11),
    ('압구정동', '압구정 은행공원 생활권 루프 5.82km', 5.8, 25),
    ('이촌동', '이촌 가족공원 루프 5.05km', 5.1, 14),
    ('이촌동', '이촌 박물관 루프 2.73km', 2.7, 13),
    ('이촌동', '이촌 한강 박물관 루프 7.63km', 7.6, 26),
    ('잠실동', '잠실 레이크팰리스·석촌호수 서호 루프 3.97km', 4.0,  8),
    ('잠실동', '잠실 리센츠 한강 루프 2.75km', 2.8,  7),
    ('잠실동', '잠실 석촌호수 루프 3.39km', 3.4,  7),
    ('잠실동', '잠실 아시아선수촌·아시아공원 루프 3.89km', 3.9, 20),
    ('잠실동', '잠실엘스 외곽 생활권 루프 3.06km', 3.1,  0),
    ('잠원동', '잠원 근린공원 루프 5.4km', 5.4,  6),
    ('잠원동', '잠원 한신2차 공원·역세권 루프 4.97km', 5.0, 13),
    ('잠원동', '잠원 한신2차 리버 루프 2.78km', 2.8,  0),
    ('잠원동', '잠원 한신2차 생활권 루프 6.82km', 6.8, 17)
  ) as v(town, name, km, gain)
 where r.town = v.town
   and r.name = v.name
   and r.km   = v.km
   and jsonb_array_length(r.trace) >= 2
   and r.elevation_gain_m is null
   and r.status <> 'active'
   and r.verified_run_id is null;

-- §C-bis  POSTCONDITION — a backfill that matches nothing must not report success.
-- The count itself cannot be asserted (it is 20 in production, 0 on a fresh database, and
-- anything in between on a partially-ingested one — all legitimate). What CAN be asserted in
-- every environment is CONSISTENCY: no row may end up carrying an elevation that disagrees with
-- the payload for its own (town, name, km). That is vacuously true on an empty catalog and
-- catches the states a silent UPDATE cannot distinguish — a half-applied backfill, a value
-- written by hand, a payload edited without re-deriving.
do $post$
declare v_bad text;
begin
  select string_agg(format('%s/%s km=%s: row=%s payload=%s', r.town, r.name, r.km,
                           coalesce(r.elevation_gain_m::text, 'null'), v.gain), '; ')
    into v_bad
    from routes r
    join (values
      ('도곡동', '도곡 매봉산 양재천 루프 7.66km', 7.7, 63),
      ('반포동', '몽마르뜨 언덕 루프', 1.6, 34),
      ('반포동', '몽마르뜨 언덕 루프 4.79km', 4.8, 46),
      ('반포동', '몽마르뜨 언덕 루프 5.4km', 5.4, 51),
      ('반포동', '반포 서래섬 리버 루프 3.31km', 3.3, 14),
      ('성수동', '성수 서울숲 루프 6.46km', 6.5, 22),
      ('송파동', '올림픽선수촌앞 올림픽 공원 4.58 km', 4.6, 11),
      ('압구정동', '압구정 은행공원 생활권 루프 5.82km', 5.8, 25),
      ('이촌동', '이촌 가족공원 루프 5.05km', 5.1, 14),
      ('이촌동', '이촌 박물관 루프 2.73km', 2.7, 13),
      ('이촌동', '이촌 한강 박물관 루프 7.63km', 7.6, 26),
      ('잠실동', '잠실 레이크팰리스·석촌호수 서호 루프 3.97km', 4.0,  8),
      ('잠실동', '잠실 리센츠 한강 루프 2.75km', 2.8,  7),
      ('잠실동', '잠실 석촌호수 루프 3.39km', 3.4,  7),
      ('잠실동', '잠실 아시아선수촌·아시아공원 루프 3.89km', 3.9, 20),
      ('잠실동', '잠실엘스 외곽 생활권 루프 3.06km', 3.1,  0),
      ('잠원동', '잠원 근린공원 루프 5.4km', 5.4,  6),
      ('잠원동', '잠원 한신2차 공원·역세권 루프 4.97km', 5.0, 13),
      ('잠원동', '잠원 한신2차 리버 루프 2.78km', 2.8,  0),
      ('잠원동', '잠원 한신2차 생활권 루프 6.82km', 6.8, 17)
    ) as v(town, name, km, gain)
      on r.town = v.town and r.name = v.name and r.km = v.km
   where jsonb_array_length(r.trace) >= 2
     and r.status <> 'active'
     and r.verified_run_id is null
     and r.elevation_gain_m is distinct from v.gain;
  if v_bad is not null then
    raise exception 'elevation backfill disagrees with the measured payload: %', v_bad
      using hint = 're-derive from the GPX corpus (see §0d) before editing either side';
  end if;
end $post$;
