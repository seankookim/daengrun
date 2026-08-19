-- ═══ 0100: a length written into `routes.name` must still be true tomorrow ═══
--
-- ═══ §0 WHAT THIS FILE IS — AND THE DEFECT IT IS *NOT* FIXING ═══
-- Reported to me as: "`routes.name` embeds course length and it DISAGREES with the `km` column
-- after rounding (`잠원 한신2차 리버 루프 2.78km` beside `km=2.8`)", with the proposed fix being
-- "ingest never writes length into the name, plus clean the 32 existing names."
--
-- **Both halves of that are wrong, and the measurement is the whole reason this file is small.**
--
-- ⓐ **There is no disagreement.** Measured across the live catalog before writing a line: 26 of
--    32 names carry a trailing km token and **all 26 round exactly to their `km`.** Zero
--    offenders. `2.78km` beside `km=2.8` is not a contradiction — it is the NAME carrying more
--    precision than a `numeric(4,1)` column can hold. Nothing is lying. ui already handled the
--    on-screen artifact at display, correctly, and that patch is not owed a schema change.
--
-- ⓑ **"Clean the 32 names" is impossible, not merely unnecessary.** `routes_town_name_key`
--    (0078:36) is UNIQUE on `(town, name)`, and stripping the token collapses THREE 반포동 rows
--    onto `몽마르뜨 언덕 루프` — 1.6 km, 4.8 km and 5.4 km are three different loops around the
--    same hill whose only distinguishing text IS the km token. There, the number is doing
--    IDENTIFICATION work, not measurement. Renaming them is a product decision about what to
--    call three loops, not a data cleanup, and it is not mine to invent.
--
-- ═══ §0b SO WHAT IS ACTUALLY BROKEN — the class is temporal, not present-tense ═══
-- Nothing stops a name's length from going STALE. The names agree today because a human kept
-- them agreeing, by hand, each time. That is not a property, it is an ongoing effort, and it has
-- already been paid at least once: mid-sprint, upstream re-cut `반포 서래섬 리버 루프 3.71km`
-- into a `3.31km` loop and had to remember to rename the row. Nothing would have complained if
-- they had not — the catalog would simply have published "3.71km" over geometry measuring 3.31,
-- and it would have read as a measurement because it looks exactly like the 25 true ones.
--
-- That is the same shape as everything else on this table this week: `trace` had no element
-- contract until 0099, `elevation_gain_m` had no tie to its geometry until 0098 §B-bis. Each
-- time the data was fine and the *guarantee* was missing, and each time the drift arrived from a
-- writer who did not know the rule rather than from a writer who broke it.
--
-- So: keep the token, and require it to be TRUE. A re-cut that forgets the name now fails loudly
-- at the write instead of silently publishing a length nothing measured.
--
-- ═══ §0c SCOPE ═══
-- ⓐ Names WITHOUT a trailing km token are untouched and always valid — six rows today, and
--    `서래섬 유채 루프` should never be forced to grow a number.
-- ⓑ Only a TRAILING token counts. A name that merely contains digits, or the letters km inside a
--    word, is not a length claim and is not read as one.
-- ⓒ Rounded comparison, because `km` is `numeric(4,1)` and the token legitimately carries more
--    precision: `3.715` in a name against `km = 3.7` is agreement, not conflict.
-- ⓓ Does NOT rename anything, does NOT touch `routes_town_name_key`, does NOT constrain `km`
--    itself, and writes no data. Zero rows change.

-- ─────────────────────────────────────────────────────────────────────────────
-- §A  THE EXTRACTOR
-- ─────────────────────────────────────────────────────────────────────────────
-- Separate immutable function rather than an inline expression, for the reason 0099 §A gives:
-- the CHECK stays readable, and the suite can pin the EXTRACTION independently of the
-- comparison. `nullif(…, p_name)` is the no-match signal — `regexp_replace` returns its input
-- unchanged when the pattern does not match, so "unchanged" means "this name makes no length
-- claim", which is the common case and must never raise.
create or replace function _route_name_km_token(p_name text) returns numeric
language sql immutable
set search_path = public, pg_temp
as $fn$
  select nullif(
           regexp_replace(p_name, '^.*?([0-9]+(\.[0-9]+)?)\s*km\s*$', '\1', 'i'),
           p_name
         )::numeric;
$fn$;

comment on function _route_name_km_token(text) is
  'The length a route NAME claims, or NULL when it claims none: the trailing "<number>km" token (case-insensitive, optional space before km). NULL for a name that merely contains digits — only a trailing token is a length claim. Used by routes_name_km_agrees.';

-- ─────────────────────────────────────────────────────────────────────────────
-- §B  THE CONSTRAINT
-- ─────────────────────────────────────────────────────────────────────────────
-- No `not valid`: all 26 tokens were measured against their `km` before this was written and all
-- 26 agree, so this validates immediately and the validation IS the proof rather than a promise.
alter table routes
  add constraint routes_name_km_agrees check (
    _route_name_km_token(name) is null
    or round(_route_name_km_token(name), 1) = km
  );

comment on column routes.name is
  'Display name. MAY end in a "<number>km" token, and where it does that token MUST round to the km column — enforced by routes_name_km_agrees since 0100, because a length in a name is read as a measurement and nothing kept it true when geometry was re-cut. The token is not decoration: three 반포동 loops share the base name 몽마르뜨 언덕 루프 and only the km distinguishes them, so it cannot simply be stripped (routes_town_name_key is UNIQUE on (town,name)). If you re-cut a route''s geometry, change the name in the same statement or the write is refused.';
