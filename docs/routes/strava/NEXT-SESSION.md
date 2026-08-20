# Kickoff prompt — route geometry, next session

Paste the block below into a fresh chat. It assumes the repo and nothing else.

---

You own **route geometry** for daengrun. Invoke `/route-geometry` first — the skill is the method
and it already holds everything three sessions learned by breaking it. Then read
`docs/handoff-route-geometry-strava.md` **§22–§24** (the current state and the four failures found
last night), and `docs/routes/geo/BUILD-QUEUE.md` (a vetted, ranked execution queue).

**Where things stand, measured 2026-08-20 after the depth day (§25):** 87 rows in `routes`, 73 candidate, 14 retired, across
30 towns. 73 GPX, 73/73 basemaps, audit passing, everything on origin. Breadth AND the first
depth pass are done — derive fresh counts before trusting these (§7 of the skill).

**Depth pass one is DONE (2026-08-20): 18 single-route towns → 4.** The remaining singles are
광장동 (river slot structurally closed — no north-bank 나들목, see GEOGRAPHY.md; an INLAND second
route is the only depth available there) and 송파동/방이동/장안동 (truthful-label splits, not
coverage gaps). **Your job now: Sean's bench review export is the input** — 18 new routes await
his verdicts at localhost:5178 (`python3 -m http.server 5178 --directory docs/routes/strava/bench`).
Read handoff §25 for the geocoder traps this cost (bridges autocomplete to CHURCHES; the cure is
coordinate waypoints from features.json) before building anything new. BUILD-QUEUE.md is exhausted:
every entry is built, discarded-with-reason, or REJECTED. 12,582 indexed complexes back the next
queue when one is wanted.

## The method, in one paragraph

Start at a residential complex. Go to the **nearest** park / stream / river — never the one that
happens to sit at the radius that makes your target distance come out; that single mistake caused
every rejection in Sean's 31-route review. **Lap the green**; the route's length comes from the lap,
not from walking further out. Come back, ideally a different way, never via a waypoint on the
opposite bearing. **2–3 waypoints, 4 maximum.** If nothing green is in reach, a plain simple loop is
correct. Distances 1.5–7.5 km, non-integer fine.

`node docs/routes/geo/plan-route.mjs "<complex name>" <targetKm>` emits a ready-to-run build
command using exactly this logic. `cluster.mjs <구>` lists anchors worth using.

## Two rules that each cost a whole route

**On a long river, name a BRIDGE, not the river.** `안양천` measured 12.96 km on two identical
runs; `오목교` measured 5.44 km and came out a genuine loop. `중랑천` 8.37 km; `겸재교` 3.54 km.

**A name that could be anywhere IS anywhere.** `어울림공원` produced a 27.64 km route — that park
name exists in many Korean cities. The planner flags these; the measure-before-save gate catches
the rest.

## Browser — one shared headed Chromium

    browse disconnect && browse --headed goto https://www.strava.com/athlete/routes

`--headed` is **per-daemon, not per-command**: any bare `browse` call — including a subagent's
"harmless" headless one — starts a competing daemon and breaks the builder. **Subagents must never
touch `browse` at all.** A mount failure is usually the daemon sitting on its local `/welcome` tab,
not a lost login; one `goto` fixes it. Check `pgrep` for chromium and `bun run server.ts` counts
before retrying blind.

## The standing grant

Sean, 2026-08-19: *"dont ask me for permission ... full speed on the app."* Build, gate, ship,
record. What that does **not** retire: credential values, one confirmation before irreversibly
destroying real production data (retire rows, don't delete), the measure-before-save gates, and
facts only he holds — **`shade` and `lighting` stay NULL**, and no route is marked dog-access
verified by a session that did not verify it.

## Boundaries

Never write a migration or touch `supabase/`. Never touch the DO-NOT-REFACTOR list in `CLAUDE.md`.
No GPX can publish a route — `routes_active_is_earned` needs a `verified_run_id` from a settled run,
so rows stay `candidate` with `source='algo'` (never `founder`: a drawn line was not walked).
`app/` belongs to the client/ui sessions; ask them rather than editing it.

## The one habit that matters most here

**Make every operation report what it actually did.** Last night: an UPDATE matched zero rows and
said nothing, so a route Sean had rejected stayed on offer; a route was named for a lake lobe it
never reached and reported as delivered; a blocked `fetch` would have shipped in a page that failed
silently. None of the existing tooling caught any of them, because each check watches one specific
claim and these lived in the gaps. Prefer `returning name` over a bare UPDATE, refuse on empty
output, and assert that an artifact contains what it must. **Silence is the failure mode, not
error.**

When you finish a slice: ingest (`build-manifest.mjs` → `ingest.mjs`, never with output
suppressed), run `audit-candidates.mjs`, regenerate `bench/routes.json`, commit, and push to
trunk.

**The bench is local only** — `python3 -m http.server 5178 --directory docs/routes/strava/bench`,
then http://localhost:5178. It needs `config.js` (gitignored) holding a Naver Web Dynamic Map
client ID, with `http://localhost:5178` in the NCP service-URL allowlist. There is no published
copy: Sean removed it, because two surfaces meant two builds and two places for a number to drift.
Sean reviews there and exports accept/reject/comment JSON — that export is the input to your next
round.
