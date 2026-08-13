# Pace-State UI — design plan (owner live · runner live · Live Activities · prefs)

Provenance: TODOS.md "From money-model late amendments (2026-08-12 evening, Sean)" —
*"live pace vs suggested minimum: green = at/faster than suggestion, yellow = deviating
slower. Suggested minimum pace 8 min/km, strong-suggestion band 7~9 min/km,
owner-adjustable in preferences."* Why it exists: completion is now minimum-DISTANCE
only, so pace-state is the **quality signal that polices the slow-stroll incentive**
— without ranking pace publicly (runner stats stay volume-led) and without
money-bearing thresholds.

Status: DRAFT for /plan-design-review (2026-08-13). Review report at the end.

---

## §1 State semantics (the machine)

One derived value, `paceState`, computed identically on every surface:

```
paceState(prev, {windowPaceSec, suggestSec, km, elapsedSec, stale}) → state

inputs:  windowPaceSec = ROLLING-WINDOW pace (Sean D6, 2026-08-13): pace over the
                      last 180s of ACCEPTED trace — window span ÷ billable window
                      distance. The state judges what the runner is doing NOW and
                      is recoverable; the DISPLAYED 페이스 stat stays the
                      cumulative average (the run's record). Two numbers, two
                      jobs, only one ever printed. Consequence accepted: a red
                      light or care stop can briefly yellow the window — the
                      care-stop line (§3b), hysteresis, and recoverability are
                      the mitigations; fewer than 2 accepted points in the
                      window → 'unknown'.
         suggestSec = suggestion SNAPSHOTTED AT RUN START (runs.pace_suggest_sec,
                      copied from dogs.preferences.paceSuggestSec on run creation;
                      default 480 = 8'00", clamped 420..540 = the 7'00"~9'00" band)
         prev       = previous state (hysteresis is a latch — it NEEDS memory)

states:  'unknown'  → NO CLAIM RENDERED (absence, not gray — honesty law §7)
         'good'     → green   (paceSec ≤ suggestSec; latched: stays good until
                               paceSec > suggestSec + HYST)
         'slow'     → yellow  (paceSec > suggestSec + HYST; latched: stays slow
                               until paceSec ≤ suggestSec)
         prev=null (mount/remount/server row missing) → benefit of the doubt:
                    'slow' only if paceSec > suggestSec + HYST, else 'good'
                    (inside the band, absence of memory never yellows a runner)
```

- **⚠ Elapsed-time precondition (owner side)**: `owner/live.tsx` today clocks from
  the FIRST FIX AFTER MOUNT (`startAt.current`) — an owner opening the screen at
  km 2.3 would compute a fabricated 0'52" pace and a lying green chip. Pace-state
  may NOT ship on that clock: owner elapsed must come from `runs.started_at`
  (the `fetchRunStartedAt` idiom already exists runner-side). This is a
  precondition of §1, not an inherited detail.
- **State memory**: client keeps `prev` in a ref (remount ⇒ prev=null rule above);
  the 0063 trigger reads `prev` from `owner_la_tokens.last_state->>'paceState'`
  (already stored per push). One function shape on both sides.
- **Freeze-at-run-start (fairness)**: the suggestion is snapshotted into the run
  row when the run starts. A mid-run pref edit affects the NEXT run — the goalpost
  cannot move while the runner is being measured. (Server triggers and both
  clients all read the snapshot: one truth, zero drift.)

- **Honesty gate**: `paceState = 'unknown'` until `km ≥ 0.30` AND `elapsedSec ≥ 180`
  (the window must be FULL before it judges — 120s of a 180s window is not a
  measurement).
  Below that, cumulative average pace is noise (the existing formatter already refuses
  below 0.05km); claiming green at 80m would be a fabricated measurement — same law
  as the 체력나이 gate ("측정처럼 보이는 비측정 금지").
- **Stale trumps pace — and blanks the datum**: when GPS is stale (≥90s, the
  existing rule), the pace claim is dropped (`'unknown'`) AND the pace stat itself
  renders `—` (codex finding: a last-known pace number that still looks current is
  the exact false claim this rule exists to prevent; the stale strip owns the
  explanation). The hidden hysteresis latch survives staleness for recovery.
  "No signal" and "too slow" must never look alike. Runner-side stale is hereby
  DEFINED (it has no clock today): time since last ACCEPTED fix ≥90s while
  running → unknown.
- **Hysteresis** `HYST = 15 sec/km`, applied on the good→slow edge only: flip to
  `slow` when `windowPaceSec > suggestSec + 15`; flip back to `good` when
  `windowPaceSec ≤ suggestSec`. A rolling window can flutter around the
  threshold; the 15s slack + the latch prevent chip flicker at the boundary.
  (State changes do NOT bypass the LA 20s throttle — see §5.)
- **Two claim states only** (per Sean's spec). The 7~9 band is the **adjustable range
  of the suggestion**, not a third visual zone. A three-zone traffic light would
  grade the runner; two states + absence is a suggestion, not a scoreboard.
- **Live-only**: pace-state exists during the run and dies with it. It is never
  written to `runs`, never shown on the report/record card, never aggregated into
  runner stats. That is the "no public ranking" clause made structural.
- **Ambient-only — never notifies**: a state change fires NO push, NO alert, NO
  haptic, on either side. It is a color you notice when you look, not an
  interruption. (A yellow push would weaponize the signal into owner→runner
  nagging — the surveillance failure mode, designed out structurally.)
- **Scope**: marketplace runs only (`owner/live.tsx`, `runner/run.tsx`, both LAs).
  Club runs (`club/run/[sid].tsx`) are excluded — no per-dog owner pace exists for a
  club session, and club has its own world.

## §2 Pace-truth reconciliation (the two-truths hazard)

A per-booking pace already exists: `bookings.pace_label` ("가볍게 8'+" / "보통 7'" /
"신나게 6'"), chosen on the (frozen) request screen and consumed by matching's
`paceFit`. Decision:

- **`pace_label` stays untouched** — it is a *matching input* (what kind of run the
  owner wants), and the request screen is frozen.
- **`paceSuggestSec` is the *quality floor*** (how slow is too slow for this dog) —
  a per-dog preference, not per-booking. The two answer different questions and
  never render on the same surface, so they cannot contradict on screen.
- The live screens today read neither; they will read ONLY `paceSuggestSec`.
- **Open for Sean (D-p1)**: should the request screen's "가볍게 8'+" pick nudge the
  suggestion for that booking? Recommendation: NO for v1 (request screen frozen;
  per-dog default is one truth). Recorded so it's a decision, not an accident.

## §3 Surface specs

**Glance-order law (all four surfaces)**: what the viewer reads 1st/2nd/3rd today
— owner island: km → 시간/페이스 → actions; runner panel: km → 시간/페이스 →
earnings; both LAs: km → footer pace/elapsed. Pace-state must be read **4th** —
it colors or sits beside the existing pace datum and never outranks the km hero.
Any variant that makes the chip compete with km fails this law.

**Data plumbing (Slice A responsibility, named so no slice invents it)**: neither
live screen has the suggestion today. The run-start snapshot (`runs.pace_suggest_sec`)
is the single source: the runner reads it alongside `runs.started_at` (existing
fetch, widened); the owner reads it the same way (which also fixes the elapsed
precondition — one fetch returns `started_at` + snapshot). Pre-run (before a runs
row exists) the caption may show the dog's current pref via a widened `MeetupInfo`;
at run start the snapshot takes over.

**The standard precedes the verdict**: the `권장 8'00"` target caption renders
from the moment the surface renders — in the unknown state it appears ALONE (no
chip). The runner's first contact with the owner's floor must never be a yellow
verdict popping in at 0.3km.

Shared component grammar: the **§3b status chip** (16/800, radius 0, tinted fill,
no border, on the same baseline row as the datum it qualifies — here, the 페이스
stat). Colors are existing tokens only (style freeze):

**Role tokens (codex adoption)**: the chip colors become named `paceSignal` role
tokens in theme.ts's paper block — `paceGoodInk` / `paceGoodWash` / `paceSlowInk`
/ `paceSlowWash` — so paper screens never import `lilac.*` and no raw hex rides
in JSX. Same hues as existing tokens (freeze-compliant: new NAMES, zero new
colors); all new app labels use `useBodyFont`/`useBodyBold` (no system-font
fallback). LA widgets keep their system font — the existing widget surfaces
already do; that is OS-surface precedent, not a new exception.

| state | fill (tint) | text | copy (권장-family — Sean D7, codex's 기준 overruled) |
|---|---|---|---|
| good | `paceGoodWash` (≈95% white wash of ready `#119B58`, GO_TINT precedent) | `paceGoodInk` = readyDeep `#0E7F49` (5.06:1 class) | 페이스 양호 |
| slow | `paceSlowWash` (amberSoft hue `#FBEED9`) | `paceSlowInk` = deep amber `#9D580A` class — NOT `#C77414` (3.09:1 on the wash, FAILS 4.5; codex measured) | 권장보다 느려요 |
| unknown | — chip absent — | — | — |

Caption everywhere: `권장 8'00"`. (D7: Sean kept his original 권장 wording —
recorded as a deliberate overrule of codex's utility-language finding, not an
oversight. The value stays owner-adjustable; the app supplies default + band.)

Exact ink values verified ≥4.5:1 against their washes at build; two-tier law
(§5): display hue for surfaces, ink version for text.

Copy law: informational, never accusatory — a slower pace may be the dog's need;
the chip reports deviation from the owner's suggestion, it does not scold. Color
never carries meaning alone (a11y): the chip always has its text label.

### 3a. `owner/live.tsx` (paper world, zero-coral-fills screen)

- The stats Row (km hero / 시간 / 페이스) keeps its geometry and its ink numbers —
  **no number recolor on either side**. The runner side decided "don't celebrate";
  the owner side celebrating speed would be philosophically inconsistent. The chip
  is the single printing of the state.
- **Exact geometry**: ONE full-width row between the progress track and the
  actions Row — chip left, `권장 8'00"` caption right-aligned 14pt dim. The
  caption renders from mount (standard-precedes-verdict); the chip pops in when
  state ≠ unknown — an accepted discrete insertion (모프 법). When the stale
  strip appears, the chip drops from this same row (caption stays), so the two
  never stack a double reflow.
- Emphasis budget: the chip is a status chip (tinted fill), not a CTA — it does not
  spend the coral-line-plus-one-CTA budget, and green here is a true state (§3b
  "state-only" jurisdiction satisfied).
- Nothing else on the island moves. No pulse, no animation — a state color swap is
  discrete (모프 법, §6 motion).

### 3b. `runner/run.tsx` (dark ink panel — logic frozen, UI slots only)

- Same chip component values; tinted fills carry their own light background, so
  contrast is chip-internal (readyDeep on ready-tint 5.06:1; pending on amberSoft
  ≥4.5:1 — verify at build).
- Placement: a full-width strip between the MiniStat row and the earnings row —
  chip left, `권장 8'00"` right in `#BBBBBB` 14pt. Both `panel` and `island`
  layouts get it (same JSX slot).
- MiniStat numbers stay as they are (no recolor — same one-printing law as 3a).
- Runner-voice copy, actionable not judging: good → 페이스 양호 · slow →
  `권장 페이스보다 느려요` (+ target shown). No haptic, no interruption mid-run.
- **Care stops are legitimate**: one dim 14pt line in the run context (or run-prep)
  notes that 물/응가 stops slow the average and that's expected — the signal must
  not pressure a runner out of care behavior (the app's own event buttons).

### 3c. Runner Live Activity (`RunActivity.tsx` — local updates)

- New prop `paceState: '' | 'good' | 'slow'` (empty string = unknown; all LA props
  are strings by contract).
- **PICKED: Ⓒ② modified (Sean D12)** — mini pill with a text label (양호 / 느림)
  beside the footer pace, restyled to **paper chip grammar**: wash fill + deep
  ink text (`paceGoodWash`/`paceGoodInk`, `paceSlowWash`/`paceSlowInk`),
  **radius 0**, label ≥13pt. "Bright and candid but following the app's style" —
  the light wash pops on the dark banner and the SAME chip grammar now runs
  across all four surfaces. No date/clock chrome anywhere in the banner (Sean:
  card-inside-card, removed from the lab).
- Wash fills carry their own background, so the light/dark lock-screen material
  problem mostly dissolves; verify the wash edges on light material at build
  (a 1px `rgba` ink hairline is the permitted fallback if the wash melts into
  white material).
- Unknown = current CREAM/DIM behavior, unchanged. No other layout change.

### 3d. Owner Live Activity (`OwnerRunActivity.tsx` + 0063 rails)

- Same `paceState` prop, **precomputed server-side** — the widget never computes
  (contract at OwnerRunActivity.tsx:15-17).
- Rendered beside the footer pace (running phase only): same Ⓒ②-modified pill
  (paper wash + deep ink, radius 0). ⚠ **Structural note**: `footLeft` is ONE concatenated string
  (`pace + ' · ' + elapsed`) in a single Text node — rendering a pace pill/color
  requires splitting the footer into separate Text nodes (pace first, elapsed
  keeps its dim). This is a widget-layout change; suite-103 pins check the PROPS
  payload (strings in), not the JSX, so no pin breaks — but the split must be
  deliberate, not discovered.
- `stale`/`done`/`ended` phases: `paceState: ''` always (stale already blanks
  pace; done/ended render settled facts, not live claims).

## §4 Prefs field (owner-adjustable)

- **Home**: `owner/dog.tsx` (per-dog — `dogs.preferences` jsonb was born for this;
  its 0001 comment literally lists "페이스"). **Its own §3b section** (codex: a
  behavioral run control must not bury among name/breed/weight): section title
  `권장 최소 페이스` (D7 권장-family), one row, same single save button as
  the rest of the form (no second save action).
- **Input = Ⓓ② five chips (Sean D13)**: `7'00" / 7'30" / 8'00" / 8'30" / 9'00"`,
  selected = ink fill + white 16/800 label, radius 0, gaps ≥10px, the `"` unit
  kept on every chip (lab's flagged cons fixed at build). One tap, whole band
  visible — the inverted-scale trap of a stepper never arises. Default selection
  8'00" when the key is absent. Helper copy describes BEHAVIOR, not colors:
  `이 값보다 느려지면 러너에게 안내해요`. A11y: chips are a radiogroup with
  `accessibilityState.selected`; 44pt touch height.
- Stepper −/+ buttons render **44×44** (Fitts 44pt minimum, §7b — the 40×40
  icon-control spec is for chrome buttons; form steppers take the a11y floor).
- **Storage**: `dogs.preferences.paceSuggestSec` (int, seconds). ⚠ `updateMyDog`
  (api.ts:170-183) **replaces the whole preferences jsonb** with `{tags}` — the
  write must become a merge (spread existing keys) in the same slice, or every dog
  save wipes the pace field.
- **Run-start snapshot**: new column `runs.pace_suggest_sec int` — populated when
  the runs row is created, from `coalesce((dogs.preferences->>'paceSuggestSec')::int, 480)`
  clamped 420..540 (server clamps because it never trusts a client-written jsonb
  on a signal path — 클라 불신). The 0063 triggers and both clients read the
  snapshot; nobody reads `dogs.preferences` mid-run (§1 freeze law).

## §5 LA payload extension (0063 rails, additive)

- New SQL helpers: `_owner_la_window_pace(p_trace jsonb, p_window_ms int)
  returns int` — windowed pace over the last 180s of accepted trace (same
  billable rule as `_owner_la_trace_km`, filtered to `t ≥ max(t) − 180000`;
  <2 accepted points → null) — and `_owner_la_pace_state(p_prev text,
  p_window_sec int, p_km numeric, p_elapsed int, p_suggest int) returns text`
  mirroring §1 exactly INCLUDING the latch (gate: km ≥ 0.30 AND elapsed ≥ 180
  → ''; prev-aware two-threshold hysteresis; prev=null benefit-of-the-doubt
  rule; null window pace → ''). Called from `_owner_la_trace_tg` with
  `p_prev = last_state->>'paceState'` (already stored per push) and
  `p_suggest = runs.pace_suggest_sec`; the stale sweep and booking trigger
  hard-set `''` (stale/done/ended never carry a pace claim).
- **Owner-screen window source**: the owner accumulates `(t_localArrival, km)`
  pairs from `subscribePos` events (LivePos carries no timestamp — local arrival
  stamps are honest enough for a 180s window; hysteresis absorbs jitter). The
  runner computes from `getTraceSnapshot()` directly.
- **`paceState` rides the existing props object** — NOT folded into `phase`.
  Phase changes bypass the 20s throttle (L13); a pace flip must NOT (it would turn
  a 60s-cadence channel chatty). Accepted consequence: up to ~20s latency on a
  color change on the owner's lock screen — fine for an ambient signal.
- Suite-103 pins stay green by construction: L5/L7 field-equality checks are
  additive-safe; L10/L11/L14 branches emit `paceState: ''`. New pins to add:
  P1 good-state payload, P2 slow-state payload, P3 gate (short trace → ''),
  P4 stale sweep carries '', P5 clamp on out-of-band prefs value at snapshot,
  P6 pace flip inside 20s does not push (throttle law preserved), P7 hysteresis
  latch (in-band value keeps prev state), P8 snapshot immunity (mid-run
  dogs.preferences edit does not move the run's threshold).
- Client (`live.tsx` laProps + `run.tsx` laProps): compute the same state from the
  same inputs (shared helper in `src/lib/pace.ts` — ONE implementation of §1 for
  all client surfaces; the SQL fn is its server mirror, like `_owner_la_trace_km`
  mirrors `mergeFixes`).
- Migration number: **0079** — 0078 was taken by the Banpo route catalog (3723a34,
  landed on redesign-v4 mid-slice). Renumbered at merge exactly as this line
  anticipated; the collision would have broken `db push`.

## §6 Edge cases (each is a designed state, not an accident)

| case | behavior |
|---|---|
| no GPS fix yet | unknown → no chip, stats already show — (existing law) |
| km < 0.30 or elapsed < 120s | unknown → no chip (§1 gate) |
| GPS stale ≥90s | pace claim dropped; stale strip owns the screen (stale ≠ slow) |
| pace exactly at threshold | good (≤ is good; the suggestion is a floor, inclusive) |
| owner never set the pref | default 480 everywhere (client + server same constant) |
| pref out of band (bad write) | clamp 420..540 on read, both sides |
| foreground-only mode (owner sees mode:'fg') | unchanged; pace-state computes the same |
| run ends | LA end payloads carry paceState '' — no posthumous verdict |
| owner edits pref MID-run | no effect on the live run — threshold is frozen in `runs.pace_suggest_sec` at run start (fairness: the goalpost cannot move mid-measurement); applies from the next run |
| owner screen vs owner LA disagree | both clock from `runs.started_at` after the §1 elapsed precondition lands (the per-mount clock is banned); residual sub-second drift is absorbed by the hysteresis band |
| pref FETCH FAILS (≠ unset) | `paceState = 'unknown'`, no chip, caption absent — defaulting to 480 against an owner who may have set 9'00" would claim knowledge the client doesn't have; coalesce-to-480 is only for a confirmed-absent key |
| Dynamic Island compact/minimal | UNCHANGED — km only, no pace-state (too small for an honest claim; color without label fails a11y law) |
| club session run | out of scope; club/run/[sid].tsx untouched |
| 귀가 state (future run-end flow TODO) | when built: stats freeze at run-stop ⇒ paceState freezes to '' at 귀가 entry (custody is not a run; no pace claim). Recorded here so the two TODOS entries compose. |

## §7 Accessibility & motion

- Chip text always accompanies color (color-blind safe by construction);
  `accessibilityLabel` on the chip: `페이스 상태: 양호` / `페이스 상태: 권장보다 느림`.
- All floors: chip 16/800; target caption 14pt (detail floor); contrast per §3
  table, verified at build.
- Zero animation. State color swaps are discrete (모프 법). Nothing to reduce for
  reduced-motion.

## §8 Build plan (Fable orchestrates + reviews · Opus 5 agents develop)

1. **Slice A (client lib + prefs + plumbing)**: `src/lib/pace.ts` (prev-aware
   state fn + constants + unit tests in app/test), dog.tsx field, `updateMyDog`
   merge fix, api.ts DogProfile mapping, **owner elapsed fix** (owner reads
   `runs.started_at` + `pace_suggest_sec` via the widened run fetch — the §1
   precondition), MeetupInfo pre-run caption field. Gate: tsc + app/test green.
2. **Slice B (screens)**: owner/live.tsx pace row (chip + caption, exact §3a
   geometry); runner/run.tsx strip (both layouts) + care-stop line + runner stale
   clock. Gate: tsc; UI slots only in the frozen runner file.
3. **Slice C (LAs + rails)**: RunActivity/OwnerRunActivity paceState rendering
   (footer split, adaptive pairs); laProps call sites; 00XX migration
   (`runs.pace_suggest_sec` + snapshot populate + `_owner_la_pace_state` +
   trigger wiring) + suite pins P1–P8. Gate: SQL harness green (388+ / 0),
   deno unaffected.
4. Review pass (Fable): diff review vs this plan §1–§7, honesty-law sweep,
   contrast checks, pin verification.

## NOT in scope (considered, deferred, one-line why)

- **Run-end flow (stop confirm · 귀가 · return handoff)** — its own TODOS entry;
  §6 records the composition point (state freezes to '' at 귀가) so they don't collide.
- **Club runs** — no per-dog owner suggestion exists for a club session; club world.
- **Report/record surfaces** — live-only is a design pillar, not an omission.
- **Instantaneous/split pace** — unsmoothed instant pace is noise; cumulative avg
  is the only honest live number we have today.
- **Pace in matching/runner stats** — volume-led stats are doctrine (TODOS spec).
- **Request-screen changes** — frozen (handoff §6); pace_label untouched.
- **Push/haptic on state change** — designed out (§1 ambient-only), not deferred.
- **Android LA** — activities are Apple-only today (module platform note).

## What already exists (reuse, don't reinvent)

- §3b status-chip component spec (16/800, radius 0, tinted fill) — the chip IS this.
- `paper.ready/readyDeep`, `paper.pending`, `lilac.amberSoft` tokens; GO_TINT 95%-wash precedent.
- `M'SS"` pace formatter (4 client copies + `_owner_la_fmt_pace` SQL mirror) — reused as-is;
  the new shared `src/lib/pace.ts` should absorb ONE client copy per touched file, not all four.
- 0063 LA rails (register/push/throttle/sweep) — extended, not rebuilt.
- `dogs.preferences` jsonb + dog.tsx form grammar — the pref's natural home.
- Suite-103 harness patterns for payload pins.

## §9 Decisions — ALL RESOLVED (Sean, 2026-08-13 session)

- **D6 metric**: state judges a ROLLING 3-MIN WINDOW; displayed pace stays
  cumulative. (Codex's cumulative-average objection absorbed.)
- **D7 naming**: 권장-family kept (페이스 양호 / 권장보다 느려요 / 권장 최소
  페이스) — Sean's deliberate overrule of codex's 기준 proposal.
- **D8 (=D-p1)**: pace_label and 권장 stay independent in v1; request screen
  untouched; the 권장 caption is visible to the runner from the start.
- **D9**: freeze-at-run-start confirmed (`runs.pace_suggest_sec` snapshot).
- **D10–D13 lab picks**: Ⓐ② full-width row · Ⓑ① chip strip · Ⓒ② modified
  (no date chrome; paper wash + deep ink pill, radius 0) · Ⓓ② five chips.
- **D-p2 fast-edge welfare (logged, not built)**: the band's 7'00" floor polices
  nothing — a 4'30" runner with a small dog shows green. Under-band pacing is a
  dog-welfare question, deliberately NOT a signal in v1 (a "too fast" claim needs
  per-dog physiology data we don't have — 측정처럼 보이는 비측정 금지). Revisit
  with breed/weight data.

## Approved Mockups

| Screen/Section | Reference | Direction | Notes |
|---|---|---|---|
| Owner live island | docs/labs/pace-state-lab.html §A Ⓐ② | Full-width pace row (chip + 권장 caption) between progress and actions | Ink stats, no number recolor; caption from mount |
| Runner dark panel | §B Ⓑ① | Chip strip between MiniStats and earnings, both layouts | Wash chip carries own bg on ink panel |
| Both Live Activities | §C Ⓒ② (modified per Sean) | Labeled mini pill (양호/느림), paper wash + deep ink, radius 0, ≥13pt | No date/clock chrome; footer split into separate Text nodes |
| dog.tsx pref | §D Ⓓ② | Five chips 7'00"~9'00", ink-fill selection | Own §3b section, single save |
| State truth table | §E | unknown/good/slow/stale/done | Stale blanks pace datum to `—` (codex adoption supersedes §E's dimmed numbers) |

## Implementation Tasks
Synthesized from this review's findings. Each task derives from a specific
finding above. Checkbox as you ship.

- [ ] **T1 (P1, human: ~3h / CC: ~20min)** — client lib — build `src/lib/pace.ts`:
  prev-aware `paceState` fn, rolling-window pace over trace pairs, constants
  (480/420..540/HYST 15/WINDOW 180s/gates), unit tests
  - Surfaced by: blind F2 (stateless hysteresis) + Sean D6 (rolling window)
  - Files: app/src/lib/pace.ts, app/test/
  - Verify: app tests + tsc
- [ ] **T2 (P1, human: ~2h / CC: ~15min)** — prefs — dog.tsx 권장 최소 페이스
  section (Ⓓ② chips) + `updateMyDog` jsonb MERGE fix + DogProfile mapping +
  `paceSignal` role tokens in theme.ts
  - Surfaced by: scout (jsonb replace hazard) + codex (token roles, own section) + D13
  - Files: app/app/owner/dog.tsx, app/src/lib/api.ts, app/src/theme.ts
  - Verify: tsc; save a dog → pace key survives
- [ ] **T3 (P1, human: ~2h / CC: ~15min)** — plumbing — owner elapsed from
  `runs.started_at` (§1 precondition) + widened run fetch (started_at +
  pace_suggest_sec) both roles + MeetupInfo pre-run caption field
  - Surfaced by: blind F1 (fabricated green) + F3 (no data path)
  - Files: app/src/lib/api.ts, app/app/owner/live.tsx
  - Verify: tsc; owner re-entry mid-run shows honest elapsed
- [ ] **T4 (P1, human: ~3h / CC: ~20min)** — screens — Ⓐ② row on owner live
  (chip + caption, stale blanks pace to `—`) + Ⓑ① strip on runner run (both
  layouts) + runner stale clock + care-stop line
  - Surfaced by: D10/D11 picks + codex stale-datum + blind F5/F9/F10
  - Files: app/app/owner/live.tsx, app/app/runner/run.tsx
  - Verify: tsc; §E truth table walked on sim
- [ ] **T5 (P1, human: ~4h / CC: ~25min)** — LA + rails — paceState prop through
  both activities (Ⓒ② pill, footer Text split), laProps call sites, migration
  0079 (`runs.pace_suggest_sec` snapshot + `_owner_la_window_pace` +
  `_owner_la_pace_state` + trigger wiring) + suite pins P1–P8
  - Surfaced by: D12 pick + blind F8 + §5 design
  - Files: app/src/activities/*.tsx, app/src/lib/runActivity.ts,
    app/src/lib/ownerActivity.ts, supabase/migrations/0079_pace_state.sql,
    supabase/tests/115_pace_state_suite.sql
  - Verify: SQL harness green (388+/0)
- [ ] **T6 (P3, human: ~10min / CC: ~2min)** — docs — TODOS.md: mark the
  pace-state entry built; add D-p2 fast-edge welfare as a logged follow-up
  - Surfaced by: Pass 7 / D-p2
  - Files: TODOS.md
  - Verify: read

## GSTACK REVIEW REPORT

| Review | Trigger | Why | Runs | Status | Findings |
|--------|---------|-----|------|--------|----------|
| CEO Review | `/plan-ceo-review` | Scope & strategy | 0 (7d) | — | — |
| Codex Review | `/codex review` | Independent 2nd opinion | 1 (voice) | issues absorbed | 8 hard-rule + 9 substance findings; 15 absorbed, 2 overruled by Sean (D7 naming, strip-vs-inline resolved by lab pick) |
| Eng Review | `/plan-eng-review` | Architecture & tests (required) | 0 (7d) | — | — |
| Design Review | `/plan-design-review` | UI/UX gaps | 1 | clean | score: 3/10 → 9/10, 8 decisions |
| DX Review | `/plan-devex-review` | Developer experience gaps | 0 (7d) | — | — |

- **CODEX:** rejected the draft's mechanics (stateless hysteresis, cumulative
  metric, contrast failures, token leakage) — all absorbed or resolved by Sean's
  D6/D7 rulings; the two-state + honesty-gate core survived unchallenged.
- **CROSS-MODEL:** Codex and the blind Claude reviewer independently converged on
  three findings (stateful latch, single elapsed truth, labeled LA pill) — all
  three are now in the plan; their one disagreement (inline chip vs full-width
  row) was settled by Sean's Ⓐ② pick.
- **VERDICT:** DESIGN CLEARED (9/10, 0 unresolved) — eng review required before
  ship per gstack default; this session proceeds to build with the SQL harness +
  tsc gates as the working eng gate.

NO UNRESOLVED DECISIONS
