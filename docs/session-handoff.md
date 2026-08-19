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
