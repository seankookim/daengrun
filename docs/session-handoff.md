# CATALOG — MEASURED, NOT FIXED: 3 routes whose `km` disagrees with their own line (2026-08-19)

Measured across all **68** catalog rows (the catalog has grown past 32 — geometry keeps ingesting).
Cumulative trace length vs the `km` column, drift > 0.15 km:

    서리풀–몽마르뜨 종주 5km   km=5.0  measured=4.84
    한강 반포–잠원 7km        km=7.0  measured=6.72
    반포한강 그랜드 루프       km=5.0  measured=4.78

All three are **original 0078 seeds**: `km` was TYPED when the row was created and the geometry was
DRAWN later by the OSM seeder, so the two were never derived from each other. Every GPX-ingested
row agrees with its line.

## Why this is not a billing defect — checked before reporting it as one

`bookings.km` comes from the **owner's distance dial** (`app/app/owner/request.tsx:94`, 0.5 km
steps), NOT from `routes.km`; the route is only *recommended* to match (`autoPick(km)`, :170). No
server path copies `routes.km` into a booking. So an owner dials 5 km and is billed for 5 km. The
defect is honesty, not money: the catalog advertises 5.0 for a line that measures 4.78, and with
Sean's #14/#15 the run is approach-leg + route anyway.

## ⚠ MY OWN 0100 CONSTRAINT BLOCKS THE OBVIOUS FIX — this is the part to read

`routes_name_km_agrees` requires a trailing `<number>km` token in the NAME to round to the `km`
COLUMN. Two of these three carry such a token (`…종주 5km`, `…반포–잠원 7km`). So correcting
`km` 5.0 → 4.8 **is refused by the constraint** unless the name changes in the same statement.

That is the constraint working as designed (a length in a name must stay true), and it means the
honest data fix requires **renaming user-facing course names** — a product decision, not a cleanup.
I did not do it overnight. Options for Sean:
  ⓐ rename to the measured figure (`서리풀–몽마르뜨 종주 4.8km`) and correct `km` in one statement;
  ⓑ drop the km token from those names and correct `km` freely — but check the unique
    `(town, name)` index first, the way the 몽마르뜨 trio blocked exactly this in 0100;
  ⓒ re-cut the geometry to actually be 5 km and leave both alone.
`반포한강 그랜드 루프` has no token, so its `km` can be corrected on its own at any time.

## What I deliberately did NOT do

- No overnight rename of user-facing names.
- Did not take the 맹견 gate (offered by announcer): dogs schema + booking-time refusal is
  custody's surface, not catalog's.
- The anchor `근사값 — 소비 금지` contract stays unflipped — with the entry point computed from the
  trace (#14/#15) the anchor is a bounding-box prefilter, which the comment already permits.

# CATALOG — THE THREE-STEP GEOMETRY SEQUENCE IS COMPLETE (2026-08-19 overnight)

**0110 → ui (c73cea5) → 0113, all live and verified.** Final probe:
`anon base trace=refused 42501 | anon via projection rows=68 | anon catalog rows=68 | service_role=reads`

**Promotion is now UNBLOCKED.** 0110 §C refused activation while client roles held base geometry;
0113 removed that grant, so the gate is satisfied by the shipped schema. A route can be promoted.

## Shipped tonight
- **0110** `routes_public` — 16 columns, no evidence columns, geometry endpoint-trimmed
  (**promoted routes only** — candidates are drawn lines and Sean's #14/#15 bills the approach leg
  off their points) and rounded 6dp→4dp.
- **0112** 🔴 P0 — anon could UPDATE and DELETE catalog rows straight through `routes_public`
  (measured: update changed 1 row; delete passed privilege AND RLS, stopped only by an FK). A
  single-table view is `is_insertable_into=YES` and the postgres default ACL grants client DML.
  **A definer view has no RLS behind it.** Suite 147 D3 is a whole-schema watchdog.
- **0113** base geometry closed to client roles; the projection is the only path.

## ⚠ Things that will bite the next person
- **A recreated view gets a FRESH default ACL** — any migration that recreates `routes_public`
  re-opens 0112's P0. 147 D3 makes that red instead of quiet.
- **`service_role` holds TABLE-WIDE select**, so a column revoke against it is a no-op (0098 M4).
  You cannot fence it out of a column; a leaked service key is unmitigated.
- **A fixture may borrow state; it may not set it.** Three suites tonight went green for a false
  reason because a fixture established the property under test. Only mutation testing found them.
- Smoke: a dev build older than `c73cea5` shows an EMPTY catalog until rebuilt. That is 0113
  working. (`eas build:list` → `[]`: no installed binaries exist, which is why the revoke was free.)

## Open / not mine
- The anchor `근사값 — 소비 금지` contract stays UNFLIPPED and should — with the entry point
  computed from the trace (#14/#15), the anchor is only a bounding-box prefilter, which is the use
  the comment already permits. No provenance discriminator exists; flipping it would be pure risk.
- Money/ui: on a **promoted** route, an owner whose pin is nearest a trimmed end gets a displaced
  entry point and a longer billed approach. Deliberate; nothing is billed differently yet.

# CATALOG — 0112 P0 CLOSED (2026-08-19 overnight). Trace revoke is step 3 and is NOT done.

**Live and verified:** `anon UPDATE=refused 42501 | anon DELETE=refused 42501 | anon SELECT rows=68
| views still writable by a client role: NONE`.

## What the hole was, because the lesson generalises

`routes_public` (my 0110) is a SINGLE-TABLE view → `is_insertable_into = YES`, and the postgres
default ACL grants `anon`/`authenticated` INSERT/UPDATE/DELETE on every new relation. 0110 granted
SELECT and never revoked the rest. Measured as anon, rolled back: **UPDATE changed 1 row; DELETE got
past privilege AND past RLS, stopped only by a foreign key.** A route with no bookings would have
been deleted by an anonymous caller.

**RLS did not save it and structurally could not.** A view without `security_invoker` executes
against its base tables as the VIEW'S OWNER, so RLS on `routes` never runs. Hence:
- **a TABLE** with client DML is fine — RLS stands behind the privilege (60 of 62 base tables rely
  on exactly this, measured; a schema-wide default-privilege revoke would break the app).
- **a definer VIEW** with client DML has nothing behind it.
The rule is view-specific. Suite 147 D3 enumerates the schema so the next definer view cannot be
born writable.

## ⚠ STEP 3 (the trace revoke) IS NOT DONE, AND HAS A PRECONDITION NOBODY HAS CHECKED

ui shipped `fetchRoutes`/`fetchRouteById` onto `routes_public` (trunk c73cea5, verified on a
SIMULATOR). That is **not** evidence about binaries already installed on real devices. Revoking
`select (trace, trace_thumb)` on `routes` breaks any older build still selecting `trace` — PostgREST
403s the whole request, so the catalog goes empty for those users. This is the 0082 §A-3 concern
verbatim ("kept so pre-0082 app builds keep working across a non-atomic Expo rollout") and the
0088/0091 outage shape.

**Before landing the revoke, establish: is there any installed/TestFlight build older than
c73cea5 that reads `routes.trace`?** If the answer is "no released binaries yet" the revoke is free.
If it is "yes", it waits for turnover. Nobody has measured this; do not infer it from a simulator.

## Deploy path

`bash scripts/deploy-migrations.sh` (dry-run, prints pending set) then `--push <exact filenames>`.
Verified by me: `--push` on a HELD file exits 3, on a non-pending file exits 4, dry-run exits 0.

# CATALOG — 0110 `routes_public` IS LIVE; the revoke is NOT (2026-08-19, overnight)

**Live in production and probed:** `candidate base=200 pub=200 | lat=37.5298 (4dp) | evidence=absent
| activation=route_geometry_still_public`. Harness 640/0, 4 pins, 4 mutations.

## ⚠ THE SEQUENCE IS NOT FINISHED. Step 2 of 3 is ui's and it has not shipped.

1. ✅ **0110 (done):** `routes_public` exists — 16 app columns, no evidence columns, geometry
   endpoint-trimmed and rounded to 4dp. 0107's promotion gate is satisfied.
2. ⬜ **ui:** switch geometry reads to `routes_public`. **Exact change:** in `app/src/lib/api.ts`,
   `ROUTE_LIST_COLS` (:47) and `ROUTE_FULL_COLS` (:48) keep their column lists **unchanged** but
   read `.from('routes_public')` instead of `.from('routes')` at :162 and :199. The six embedded
   `routes(name)` / `routes(name, area)` selects (:484, :773, :1781, :2492, :3641, :3700) **stay on
   `routes`** — they read name/area only, which is not being revoked.
3. ⬜ **catalog, next free number:** `revoke select (trace, trace_thumb) on routes from anon,
   authenticated`. **MUST come after step 2** — revoke-first 403s the whole catalog (0088/0091).

**Until step 3, no route can be promoted.** `_routes_guard_geometry_public_tg` refuses activation
while anon can still read `routes.trace` from the base table. That is deliberate: it makes the
window between "0107's gate opens" and "geometry actually closed" unrepresentable rather than
something someone has to remember.

## The finding that shaped 0110, worth keeping

**A view alone would have satisfied 0107 while protecting nothing** — anon reads `routes.trace`
directly at 6dp (~11 cm) from the base table, so every trim in the projection would have been
optional for the reader. 0107 was correct about identity columns; nobody had joined that to the
geometry half. Mutation M4 reproduces it: drop the trigger and promotion succeeds while the base
table hands anon the full-precision track.

## ⚠ Correction forced mid-build — read before touching the trim

Sean's rulings **#14/#15** make the entry point **the nearest point ON the trace** to the owner's
pin, and make the approach leg **count toward km**. The trace is therefore a **money input**.
Trimming every route would have moved a real owner's entry point up to 200 m and **billed them for
the difference** — to de-identify a line **nobody ever walked** (all 32 rows are `source='algo'`
drawn geometry). So the trim is conditioned on `status='active'`: the only state whose geometry was
derived from a settled run. The discriminator is `status`, **never `verified_run_id`** — 0107's gate
refuses a view that so much as depends on that column, even inside a CASE.

⚠ Live trade-off for money/ui: on a **promoted** route, an owner whose pin is nearest a trimmed end
gets a displaced entry point and a longer billed approach. Correct side to err on (the alternative
publishes a previous owner's home), but it is a real consequence, not a rounding artifact. Nothing
is billed differently today — no route is active.

## Decisions taken under Sean's overnight grant — one-line reversible

- **4dp precision — DERIVED.** Points average 42 m apart, so 11 m is below sampling resolution
  (shape unchanged) and above door resolution (no address inferable). Only value that is both.
- **200 m trim — A JUDGEMENT, labelled as one.** `least(200 m, 20% of length)` per end. No
  measurement yields 200; the 20% clamp keeps a 1.6 km route at ≥60% of itself.
- **`authenticated` treated exactly like `anon`.** A logged-in stranger is still a stranger.

# ANNOUNCER v3 — live state pointer (2026-08-19, late evening; branch `claude/announcer-v3-handoff-f0774a`)

**If you are the next announcer, read in this order:** `/announcer` (method) → `docs/handoff-announcer.md`
(roster + deploy discipline + the v3 addenda, all measured) → `docs/decisions/awaiting-sean.md` §0-decies /
§0-undecies / §0-duodecies (Sean's open items, lettered) → the console
(https://claude.ai/code/artifact/aad92054-9264-4431-9835-d03ef86b3f6b, update in place, never a new URL).

**State at this write (verify, don't relay):** 0106–0109 and **0111** applied in production; **0105 is GONE**
(superseded by 0111, file deleted, HELD empty — the wrapper `bash scripts/deploy-migrations.sh --push <names>`
is still the only deploy path). 0111 went contract → attacked (21/21) → implemented → independent
adversarial review (FIX-FIRST, comment-class) → round 2 (657/0) → trunk → `create-booking-hold` v9 +
0111 deployed → verified live at the DB boundary AND over the wire (self-cleaning probe: body runner_id →
400; legit hold writes runner_id null; direct PostgREST writes → 42501). REGISTRY rows 0105 SUPERSEDED /
0111 DEPLOYED carry the evidence. /cso #2 is PARTIALLY CLOSED: F2 (B-11 nomination chain) stays open.
**Not closed by 0111:** the legit nomination chain (own dog → payment_ok → request_runner) — B-11 in the
contract; `is_booking_party` status filter is the adjacent slice; Sean's D1/D2 decides its shape.
Live sessions at this write: ui, legal, route geometry. Offline: trust, money, catalog (0110 designed
below, not built). Nothing unpushed anywhere except the in-flight 0111 tree until it pushes.

---

# CATALOG — 0110 `routes_public` IS DESIGNED AND CLAIMED, NOT BUILT (2026-08-19)

**Claimed: migration 0110, suite 145, row on trunk.** Nothing written yet. Read this before
starting it — the design is settled and one finding in it is load-bearing.

## 🔴 The finding that shapes the slice, measured 2026-08-19

**Satisfying 0107's gate with a view alone would unblock the exact leak 0107 exists to prevent.**

    has_column_privilege('anon','routes','trace','SELECT')       -> TRUE
    has_column_privilege('anon','routes','trace_thumb','SELECT') -> TRUE
    has_column_privilege('anon','routes','anchor_lat','SELECT')  -> false   (0107 shut these)
    has_column_privilege('anon','routes','verified_run_id',...)  -> false

0107 refuses promotion until `public.routes_public` exists. The moment it does, the gate opens and
`promote_route_from_run` DERIVES an active route's geometry from a **settled run's trace** — at that
instant `routes.trace` stops being a drawn line and becomes a recording of where one identifiable
person walked one dog, endpoints at the pickup and dropoff. And anon reads `routes.trace` **directly
at 6 decimal places (~11 cm)**, because 0107's whitelist grants it on the base table. Any trimming
the view does is therefore optional for the reader.

**This is not a defect in 0107** — its job was the identity columns and it did that correctly
(anchors and all three evidence columns are genuinely shut; verified). The geometry half was never
in its scope. It matters now because 0110 is the thing that opens the gate.

## The design — three parts, two owners, ORDER IS LOAD-BEARING

1. **catalog, 0110:** create `routes_public` — endpoint-trimmed, 4dp coordinates, no identity cols.
2. **ui:** switch `ROUTE_LIST_COLS`/`ROUTE_FULL_COLS` (api.ts:47-48) and the six embedded
   `routes(name)` / `routes(name, area)` selects to read geometry from the view. Ship a release.
3. **catalog, 0111:** revoke `select (trace, trace_thumb)` on `routes` from anon + authenticated.

⚠ **Revoke-first is an outage — 0088/0091 exactly.** Revoke before ui ships and the catalog 403s.
⚠ **View-first has its own window:** after step 1 the gate is open while step 3 has not landed, so a
promotion in that gap publishes a real track at 11 cm. **So 0110 must ALSO extend
`promote_route_from_run` (EXTENDS 0107's version — name it in the header, per the REGISTRY law) with
a second refusal: fail closed while anon still holds `select` on `routes.trace`.** Promotion then
stays blocked across the whole sequence and unblocks only when the last step lands. No window, and
the gate states its own precondition.

## Decided by measurement — reuse the reasoning, do not re-derive

- **Coordinate precision 6dp → 4dp.** Points average **42 m** apart (32 rows, 6,325 points,
  avg 4.59 km / 117 pts). 4dp ≈ 11 m: below the sampling resolution, so the drawn line is
  unchanged; above door resolution, so an address is not inferable. 5dp ≈ 1.1 m resolves a doorway;
  3dp ≈ 110 m exceeds point spacing and visibly distorts. **4dp is the only value that is both.**
- Identity columns excluded — required by 0107's transitive `pg_depend` gate, which catches
  aliasing, `select *`, WHERE-only use, and chained views (three levels tested).

## ⚠ TWO DECISIONS THAT ARE SEAN'S — do not silently pick them

- **The endpoint trim DISTANCE.** Precision was derivable; this is not. It is a judgement about how
  much of a route's start may be public. Default it, put it in ONE named constant, flag it.
- **Whether `authenticated` is treated like `anon`.** A logged-in stranger is still a stranger.

## Suggested shape

An immutable helper `_route_trace_public(trace jsonb, trim_metres double precision)` that walks
points with ordinality, drops from each end until cumulative distance exceeds the trim, and rounds
survivors to 4dp — so the constant lives in one place and the suite can pin trim and precision
separately. Then the view names its columns explicitly (**never `select *`** — 0107's header says
why: the select list is the only control from the view's seat).

## Deploy is BLOCKED fleet-wide until 0105 resolves

`db push` fails closed naming 0105; `--include-all` would apply **0105 as well as yours**. The
fleet recipe: detached tree at trunk -> `mv` 0105 aside -> `--dry-run` and READ the list (only your
files) -> push -> restore. That is a workaround with a shelf life, not a procedure.
🔴 **Never run the CLI's other hint, `migration repair --status reverted 0106 0107 0108`** — it marks
three genuinely-applied migrations as reverted and corrupts the ledger.

# Session handoff — announcer, 2026-08-19 (CSO audit → P0 remediation → three of four closed)

**Read with this:** `docs/handoff-announcer.md` (roster + deploy discipline, written 2h ago) ·
`docs/decisions/awaiting-sean.md` (§0-* head = everything Sean owns) · `docs/fleet-roster.md` §7
(method lessons) · `.gstack/security-reports/2026-08-19-cso.json` (audit JSON, local) ·
`docs/design/screen-functionality-spec.md` (per-screen spec for ui) · `docs/biz/location-law-counsel-brief.md`
(v5, for the lawyer) · prior handoff archived at `docs/session-handoff-archive-20260819.md`.

Tags: **[verified-now]** checked this session against code/gate/live · **[from-history]** earlier in
conversation · **[reported]** a subagent/session said so, I did not confirm · **[uncertain]** inference.

## 1. Status table

| System | State | Provenance |
|---|---|---|
| Trunk `origin/redesign-v4` | `28228d7`; main checkout 0/0, clean | [verified-now] |
| Migrations on trunk | files through `0108` (0105 present, unapplied); 0109 on `claude/p0-truncate` @ `326d230` unlanded | [verified-now] |
| Applied in production | 0100–0104, **0106, 0107, 0108** · **0105 NOT applied (deliberate)** | [verified-now] `migration list --linked` |
| Realtime | `private_only = true` | [verified-now] management API |
| Auth (dashboard-only) | email provider still ON; `uri_allow_list` still carries `exp://**` + LAN IPs | [verified-now] |
| Charging | `payments_live_since` null · payments 0 · billing_keys 0 · `ops_recipients` 0 rows | [verified-now] |
| Edge functions | create-booking-hold v8 · transition-booking v33 · settle-run v14 · open-drop v8 · geocode v1 · collect-charges v1 · confirm-payment v1 — none redeployed today | [verified-now] |
| Harness | last full runs on merged candidates: 0108 606/0 · 0106 629/0 · 0107 637/0 · 0109 596/0 | [verified-now] for 0106/0107/0108 (I ran them); [reported] for 0109 |
| App commit gate | tsc · rpc 95/161 · native-imports 54 green at each land | [reported] by builders; my own run earlier today [verified-now] |
| Client on device | ui verified on simulator: private channels all four families, club-chat live as host; TestFlight build **never uploaded** (needs Sean's Apple 2FA) | [reported] ui |
| EAS | 0 builds ever, 0 updates ever | [verified-now] `eas build:list/update:list --json` |

## 2. Goal & current state

Sean ran a full app audit, then `/cso` with an external charter. Verdict `BLOCK` was accepted; he
ordered P0 remediation and then said, verbatim: *"dont ask me for permission. im gone for break. full
speed on the app."* Standing rule: **gates, not permission** (harness → /autoplan → adversarial
reviewer ≠ author → land on trunk → deploy → verify live → record).

| Workstream | State |
|---|---|
| CRIT live GPS public broadcast | **CLOSED** at the realtime boundary, both instruments, one run, production [verified-now negative half by me; positive half reported by ui with raw lines] |
| HIGH forged booking (`bookings owner insert`) | **OPEN** — trust's 0105 rebuild in progress; trunk's 0105 is the REJECTED version (kept out of every deploy) [from-history + verified-now that 0105 is unapplied] |
| HIGH reward-drop rewrite | **CLOSED** — 0106 applied; attack live → 42501 [verified-now] |
| Route evidence columns (latent) | **CLOSED** — 0107 applied; anon over-the-wire: app cols 200, `verified_runner_id` 401 [verified-now] |
| TRUNCATE defense-in-depth | built (0109), unlanded, undeployed [reported] |
| Dashboard toggles | untouched (Sean's) [verified-now] |
| TestFlight | prepped to the 2FA prompt [reported ui] |
| ui journey mocks (⑧ v2) | in progress against `screen-functionality-spec.md` [reported] |

## 3. What shipped this session (by theme)

**Realtime authorization** — 0103/0104 (trust; run2-* private policies + oracle), 0108 (`claude/p0-realtime`
@ 7c6ce21 → trunk; chat/bk/club-chat policies, closes 0103's `run_channel_allowed` party oracle via
`my_channel_allowed`), client f106b2b + 9012d7a (ui; all four families private + setAuth,
`LiveLinkState` four states), `private_only=true` (me, management API PATCH). Tests:
`app/scripts/e2e-run-channel.mjs` (21/21), `e2e-party-channels.mjs` (6/6), legal's
`docs/legal/evidence/run-channel-private-matrix.mjs` + `run-channel-probe.mjs`.
**Drops seal** — 0106 (`claude/p0-drops` @ 933aa52 → trunk; revoke client I/U/D, immutable-once-opened
trigger with owner-with-client-JWT tier, contents CHECK, `drops_pick_opened_has_choice`; suite 141 D1–D20).
**Route evidence** — 0107 (`claude/p0-routes` @ ae01373 → trunk; table revoke + 17-col grant,
promote_route_from_run fails closed with a TRANSITIVE pg_depend walk; suite 142 V1–V8; edits 118 additively).
**Verification** — 0101/0102 verified deployed (REGISTRY rows annotated) [reported by agent, recorded].
**Service-role key** — moved out of `app/.env` to `~/.config/daengrun/ops.env`; scripts refuse app/ paths;
proof: 0 builds/updates ever, local Hermes bundle carries one JWT (anon), 0 service value (0550f9b).
**Docs** — counsel brief v5 (region fixed; §2/§2-bis/§4 corrected; footer provenance; Q6 with numbers) ·
`docs/security-dashboard-checklist-2026-08-19.md` · `docs/design/screen-functionality-spec.md` ·
queue §0-* (rulings verbatim; false severity in §1-bis corrected; legal's release-not-approval) ·
roster §7 (≈15 method lines) · `docs/handoff-announcer.md`.

## 4. Standing doctrines (canonical: `CLAUDE.md`, `docs/fleet-roster.md`, `docs/decisions/README.md`)
1. **Verify at send time; never relay** — and relay measurement and inference SEPARATELY, labelled, saying who has opened the artifact.
2. **Closure = the unauthorized operation rejected at the server/DB/realtime boundary** (Sean's rule) — never "UI no longer exposes it".
3. **Both instruments in one run** — a stranger refused AND the real party still receiving; negative-only passes on a dead feature.
4. **Migration numbers from REGISTRY on origin, never a message**; land on trunk BEFORE deploy; never deploy from a tree carrying an unfinished migration (→ move 0105 aside).
5. **✅ only for Sean's own words on origin**; date every constraint and derived dataset; "withdrawn" must say which (argument vs change).

## 5. Working-relationship norms
Sean writes short, decisive, sometimes retracts ("i never said…") — his latest word governs and gets
recorded verbatim with `[end of his words]`. He wants **plain-language reports under a `–––––REPORT–––––`
banner with clear questions and lettered answer choices** (his instruction). No jargon. He picks by
LOOKING (labs by number; "i want to see how it looks like before choosing anything"). He grants broad
autonomy ("full speed", "deploy agents, as many as you want") but physical/credential steps stay his by
nature (Apple 2FA, dashboard, secret values). He is on break as of this handoff.

## 6. Decision log with WHY
- **Kakao-only sign-in** (Sean "b") — email door removed client-side; server toggle pending; SMS never existed.
- **Payments: start paperwork, keep charge machine** (Sean "4: A"); **forget 예비창업패키지** (Sean, supersedes an earlier learning).
- **Ops dashboard = standalone local web tool** (Sean "B"), not in-app RPC — trust's contract v2 cancels the RPC.
- **Alerts go to Sean's account** (aa73ce8a = s4kim2025); **all 9 runners are test data** (Sean "3: b") → marked in club_test_accounts (trust).
- **Launch towns = towns with GPX** (a derivation, not a list; 13 towns now [reported]).
- **Route promotion fails closed** until a de-identified `routes_public` exists — REVOKE not DROP (`routes_active_is_earned` needs the columns).
- **Namespace bump `run2-` KEPT** (its rationale as a *control* withdrawn; the shipped change is load-bearing — a revert would break live tracking; server-first if ever changed).
- **`private_only` flipped without a staging project** — reasoned: forced-upgrade population zero (no build ever shipped), the flip is subtractive relative to already-private joins, rollback is one PATCH; sequenced AFTER 0108 + client so chat/bk did not die.
- **Refusals**: ui refused to enter Sean's Apple credentials under any authorization (correct; carve-out by nature). I refused to deploy trunk's 0105 (reviewer-rejected). Legal refused to assert *whose* account until measured; Sean then confirmed in his words.
- **Reversal**: I relayed "work locally, no db push" as Sean's constraint; he later said *"i never said…"* — retracted on origin, §0-septies-bis; never cite it.

## 7. Architecture & contracts (deliberate things that look wrong)
- **DO-NOT-REFACTOR**: collapsing hero on `owner/fitness` (not home), meetup stage machine, three availability predicates (CLAUDE.md).
- **Ordering**: realtime policies (0103/0104/0108) → client private (f106b2b/9012d7a) → `private_only`. Any new channel family needs a `realtime.messages` policy BEFORE the client marks it private, or it dies.
- **`send()==='ok'` ≠ authorized** — assert non-delivery to an authorized listener.
- **`routes.km` is display; the owner's km dial prices** (create-booking-hold). Route name km token is TRUE by 0100's constraint and identifies five rows — render raw.
- **Trust review is standing** on RLS/grants/search_path/state transitions/money at PLAN time.
- **Views here are definer by default (owner postgres)** — a view's SELECT list is the control; explicit columns, never `select *`; gate on pg_depend transitively, not names.

## 8. File map (touched/created this session)
`docs/session-handoff.md` (this) · `docs/handoff-announcer.md` · `docs/fleet-roster.md` §7 · `docs/decisions/awaiting-sean.md` §0-* · `docs/design/screen-functionality-spec.md` · `docs/biz/location-law-counsel-brief.md` (v5) · `docs/biz/payments-paperwork-checklist.md` (money) · `docs/security-dashboard-checklist-2026-08-19.md` · `docs/pre-charging-checklist.md` §4-bis (money) · `docs/contracts/ops-dashboard-read-contract.md` (trust) · `docs/legal/evidence/*.mjs` (legal) · `supabase/migrations/0103,0104,0106,0107,0108_*.sql` + suites 139–143 · `0109` on branch · `app/scripts/seed-route-traces.mjs`, `e2e-club.mjs` (ops.env), `e2e-run-channel.mjs`, `e2e-party-channels.mjs` (ui) · `app/src/lib/geo.ts`, `api.ts` (private channels) · `app/.env.example` (rule) · `~/.config/daengrun/ops.env` (chmod 600, outside repo) · `.gstack/security-reports/2026-08-19-cso.json`.
Harness: `/abs/path/supabase/tests/harness.sh` (ABSOLUTE path — `$0` self-pin breaks relative) with `PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH LC_ALL=C`.

## 9. Pending on Sean's side
**Ops (only he can):** (a) dashboard: Auth → Providers → Email → disable; (b) dashboard: URL config → allowlist = `daengrun://login` only (do NOT use `supabase config push`); (c) TestFlight: ui drives to the prompt, he enters Apple 2FA — build from f106b2b or later; (d) forward counsel brief v5 (if v1 was sent, follow up now — Q6 has a statutory clock).
**Decisions:** (e) tap targets 18 vs 44 pt — ui renders both, he picks by looking; (f) hill note threshold ruled 40 m already; nothing else open.

## 10. Known bugs, gotchas, false-success producers
`supabase db query` multi-statement returns the LAST row-producing statement (a 0-row UPDATE shows the preceding `set_config` row → looks ALLOWED); parse JSON with python (grep is line-based). Data-modifying CTE invisible to RLS subqueries in the same statement — chain probes as separate statements. `do $$…$$` auto-commits (use begin/rollback). Bare column REVOKE under a table-wide grant is a no-op. Views definer by default. `--headed` per-command for gstack browse; a bare call spawns a second daemon. Harness `$0` self-pin needs an absolute path. `db push` applies every pending file → move unfinished migrations aside in a detached deploy tree. `eas build:inspect` archive uses .gitignore (docs/ uploads); `.easignore` REPLACES .gitignore. Fresh worktrees can arrive 100+ behind carrying REGISTRY rows without files. supabase-js reuses channels by topic — one client per listener in tests. Management API GET omits `private_only` when unset. `has_column_privilege` metadata looks identical for "granted all" vs "whitelisted" — execute reads as the role.

## 11. Known-good — do not "fix"
Money paths (amounts never client-supplied; idempotency; four independent off-switches) · 184/184 definers search_path-pinned · profiles column grants exactly 0088/0091 · horizontal reads (A sees 0 of B) · `_guard_runner_cols`/`_guard_run_cols`/`_guard_booking_cols` triggers · storage path scoping · 0099 trace CHECK · run2- topic + `RUN_TOPIC` helper · `unknownExcluded()` chips · `LiveLinkState` four states · the exclude-0105 deploy discipline.

## 12. Ideas discussed, not built
Real de-identified `routes_public` projection (endpoint trim/precision/aggregation; catalog owns) · anchor-contract flip with a measured discriminator (anchor→trace[0] distance; needs Sean's word) · GraphHopper router (RETRACTED by route geometry; Strava stands) · in-app ops dashboard RPC (cancelled) · notifications template RPC (client INSERT of arbitrary title/body still open — folds into 0105's party-sweep) · `[auth]` in config.toml (blocked: `config push` would clobber Kakao; auth-surface check pins the full config via keychain token instead) · SMS/phone sign-in (deferred past pilot) · repo-wide narrowing of anon/authenticated table grants (E-10; risky, not started).

## 13. Strategic read
The single most valuable next engineering act is **trust's 0105 rebuild landing** — it is the last open P0 and its reviewer found a real money-mint path (`recurring_series` → cron → bookings with client fares) that becomes live the day charging flips. Everything else is defense-in-depth or product polish. Second: **the TestFlight upload**, because every realtime fix is now correct-for-new-binaries and the only clients that exist are dev builds — the first real device is where signup, Kakao, and live-location get their true test. Third: the two dashboard toggles, one minute of Sean's time, closing an open door on the only login route. If pushed back on "why not ship features": three of four exploit chains closed in one day proves the fleet can hold the bar; the remaining one is where real money leaks. Do not let it drift behind mocks.

## 14. Next 1–3 steps
1. **[read-only]** `git fetch; git log origin/redesign-v4 -5`; `supabase migration list --linked`; confirm 0105 still unapplied and whether trust's rebuild has landed (grep REGISTRY 0105 row).
2. **[needs-deploy]** land 0109 (`claude/p0-truncate` @ 326d230): merge trunk, harness (absolute path), push trunk, deploy from a detached tree with 0105 moved aside, `--include-all`, verify T2 query live.
3. **[needs-user]** ping Sean for the two dashboard toggles + TestFlight 2FA; then trust re-measures `/auth/v1/settings` and ui upgrades "Kakao only in the app" → "Kakao only".

## 15. Verification commands
Safe: `supabase migration list --linked` · `supabase db query --linked "select * from ops_flags"` · `curl -H "Authorization: Bearer $(security find-generic-password -s 'Supabase CLI' -w)" https://api.supabase.com/v1/projects/zjabnywjpvpgmtajygqy/config/realtime` · `DAENGRUN_APP_DIR=app node docs/legal/evidence/run-channel-private-matrix.mjs` (from legal's branch) · `git rev-list --left-right --count origin/redesign-v4...HEAD`.
Expensive/destructive (do not run casually): `supabase db push` (from a detached tree with 0105 aside only) · `PATCH …/config/realtime {"private_only":false}` (rollback) · `eas build` (Sean's 2FA).

## Environment & test data left behind
None on production: every probe ran in `begin…rollback`; ui's e2e-party-channels is self-cleaning; ui deleted its club_chat test row (id=1) [reported]. Local: three harness postmasters may still be running under `.claude/worktrees/p0-*/supabase/tests/.pgtest` (kill via their postmaster.pid). Scratch deploy trees under the scratchpad (`deploy-0106/0107/0108`) — disposable.

## Agent work at handoff
Completed: 0106/0107/0108/0109 builders; three adversarial reviewers (verdicts folded in); 0101/0102 verifier. None running. Coverage gaps: harness for 0109 not run by me; ui's positive arms [reported]; trust's 0105 rebuild state unknown to me since their session went offline.
