# Prompt — add an elevation column to `routes`

> # ⚠ DO NOT RUN THIS PROMPT. IT WAS COMPLETED ON 2026-08-14. — note added 2026-08-21
>
> This is the worst kind of stale doc: it is self-contained, it reads as live, and following it
> produces **duplicate work AND a migration-number collision**. The migration it asks for is
> **`supabase/migrations/0098_route_elevation.sql`** — `REGISTRY.md` row 0098 reads
> **BUILT + DEPLOYED + VERIFIED 2026-08-14** (applied to production and read back: 32 rows · 20
> measured · 12 NULL · range 0–63). Verified today: `0098:120` is
> `alter table routes add column elevation_gain_m integer;`.
>
> **Every judgment call this prompt leaves open was made, and made the way the prompt argued
> for:** nullable with no default; the `routes_elevation_gain_nonneg` floor with deliberately no
> upper bound; and the column comment says in so many words that NULL means "no measurement",
> never "flat". 0098 also went further than the ask — §B-bis clears the value automatically when
> `trace` changes, because a gain measured on a replaced line describes a route that no longer
> exists.
>
> **Kept, not deleted, for two reasons.** Its §"Process gates" (take the number from the remote
> tip; a number is taken when EITHER its row or its file reaches origin; `ls | sort` is lexical so
> `117_` sorts before `97_`) is repo law that outlived this one migration and is worth reading
> before any migration. And the stale figures below are a dated snapshot worth keeping honest:
> "32 rows across 8 towns, 20 with GPX" was true on 2026-08-14 — measured 2026-08-21 there are
> **152 GPX files** in `docs/routes/strava/`, and the `routes` row count is production DB state
> this session did not query.
>
> If you actually need a NEW elevation-related column, this is not your prompt; start from the
> REGISTRY and take a fresh number.

Hand this to a fresh session. It is self-contained.
**(⚠ It is also finished — see the banner above before reading another line.)**

---

You own one small additive migration for the daengrun repo: giving `routes` somewhere to store
elevation. Read `CLAUDE.md` first, then `docs/session-handoff.md`, then this brief.

## What is needed and why

Route geometry is now sourced from Strava (Sean's ruling, 2026-08-14) and **every route has a
measured elevation gain that currently has nowhere to live.** The catalog has 32 rows across 8
towns; 20 of them carry real GPX-derived geometry, and for each of those the gain is already
measured and sitting in `docs/routes/strava/manifest.json` as `elevationGainM`. Values range
**+0 m (flat riverside) to +63 m (도곡 매봉산)**.

Without a column: the backend cannot serve it, the UI cannot show it, and an owner choosing between
a flat 5 km riverside route and a 5 km route over a hill sees the same thing. For a **dog** run that
difference is not cosmetic.

## The change

Add to `public.routes`:

```sql
alter table public.routes
  add column if not exists elevation_gain_m integer;

comment on column public.routes.elevation_gain_m is
  '누적 오르막(m). GPX 트랙포인트에서 계산 — 3m 미만 변화는 GPS 노이즈로 간주해 제외. '
  'Strava 자체 표기와 약 25% 차이가 나는데, 이는 버그가 아니라 정의 차이다(Strava는 자체 DEM 보정). '
  'NULL은 "측정 안 됨"이지 "평지"가 아니다.';
```

Judgment calls that are yours, not prescribed here:
- whether to also add `elevation_loss_m` (on a closed loop it is near-mirror; on an open route it
  is not — and 반포 서래섬 currently has a 215 m closure gap, so "loops are closed" is not
  universally true in this catalog)
- whether a check constraint is worth it (`elevation_gain_m >= 0` is safe; an upper bound is not —
  Seoul has real hills)
- whether it belongs in the `ROUTE_LIST_COLS` select or only the detail select (client owns that
  call; coordinate rather than decide alone)

**Nullable, no default.** NULL must mean "not measured", and a default of 0 would silently assert
every unmeasured route is flat — which is the exact class of error this catalog has been cleaning
up all day (a route named "3km" that measured 5.4 km; a row claiming `km` 2.0 that measured 1.6).

## Process gates — these are the reason this is a separate session

1. **Take the migration number from the REMOTE tip, never from a doc.** Several sessions work this
   repo at once and each claims numbers. Resolve immediately before writing the file:
   ```
   git fetch && git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3
   ```
   ⚠ `ls | sort` is LEXICAL, so `117_` sorts before `97_`. Use `grep -oE '^[0-9]+' | sort -n | tail -1`.
2. **A number is taken when EITHER its row or its file reaches origin — the check is two-sided.**
   Reading only the REGISTRY row is reading half the state. **Push the migration and its REGISTRY
   row in the same breath.**
3. `.githooks/pre-push` enforces both. Enable once per clone:
   `git config core.hooksPath "$(git rev-parse --show-toplevel)/.githooks"`
4. **Run the SQL harness**: `supabase/tests/harness.sh` (PG16 container at `tests/.pgtest`;
   `pg_ctl` must start in the same shell invocation). All pins must pass.
5. `/autoplan` is the standing gate for any migration in this repo.
6. Commit gate before committing, from `app/`: `./node_modules/.bin/tsc --noEmit`,
   `node scripts/check-rpc-contracts.mjs`, `node scripts/check-route-native-imports.mjs`.

## Things that will bite

- **`routes.active` is a GENERATED column since 0082** (`generated always as (status = 'active')
  stored`). Writing it is an error. Do not touch it.
- **Views change via `create or replace` only** — never DROP, or grants are lost.
- If you add any security-definer function (you almost certainly should not need one), it MUST
  carry `set search_path = public, pg_temp` **in the function body** — ALTER-applied config is
  reset by `create or replace`, measured. Test 98 H1 watches the whole schema and will fail the
  harness on any omission.
- **A suite whose pinned behaviour legitimately changes must be updated in the same slice**, with a
  comment saying why and naming which new pin owns the new property.

## Backfill

After the column exists, the values are ready. `docs/routes/strava/manifest.json` has
`elevationGainM` per route keyed by `name` + `town`. A backfill is a plain UPDATE guarded the same
way the rest of this track guards writes:

```sql
update routes set elevation_gain_m = <value>
where town = <town> and name = <name>
  and status <> 'active' and verified_run_id is null;
```

`docs/routes/strava/build-manifest.mjs` regenerates the manifest from the GPX corpus if you want to
re-derive rather than trust the file. Prefer re-deriving — it is one command and it removes a
trust assumption.

**Do NOT backfill 0 for routes without GPX.** Twelve of the 32 rows have no measured elevation.
They stay NULL.

## Explicitly out of scope

- Do not change `shade` or `lighting`. No geometry source supplies them; NULL is legible as absent,
  a guess is not. Sean ruled that offering rows with unknown lighting is fine — that permits
  serving them, not populating them.
- Do not change `status` or attempt to make any route `active`. `routes_active_is_earned` requires
  a `verified_run_id` from a settled run, set only by `promote_route_from_run`. No GPX can satisfy
  it, by design.
- Do not touch `app/` — client owns it. Coordinate on whether `RouteInfo` should carry the new
  field; do not decide it alone.
- Do not add a column for turn cues, progress, or route shape. Those are **functions of the
  `trace`** and are computed at render time by `docs/routes/strava/route-guidance.mjs`. Storing
  them would create a second copy of the truth that can drift from the geometry it describes.

## Definition of done

- Migration file + REGISTRY row pushed together, number verified against the remote tip
- Harness green
- `supabase migration list` read back after the push — verify, do not assume
- Elevation backfilled for the routes that have a measured value, NULL for the rest
- A one-line note in `docs/session-handoff.md` saying the column exists and what NULL means
