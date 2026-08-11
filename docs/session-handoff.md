# SESSION HANDOFF — 2026-08-11 pm · club security slice shipped · action rollout complete

**Opener for the next session: "read docs/session-handoff.md fully, then continue."**

Companion docs to read before working:
- **`CLAUDE.md`** — permanent law book (language, gates, migration doctrine, ops authority).
- **`DESIGN.md`** — design law book. Read before ANY UI work.
- **`TODOS.md`** — deferred work + what the adversarial cycle found and I deliberately did NOT fix.
- `docs/design/design-review-20260811.md` — full-app review; the P2/P3 backlog lives here.

**Build in the MAIN checkout `/Users/sean/dev/daengrun`, branch `redesign-v4`.**
Worktrees under `.claude/worktrees/` are stale snapshots — never build or gate there.

Fact tags: **[verified-now]** checked this session · **[reported]** a subagent said
so, not independently confirmed · **[from-history]** remembered, recheck ·
**[uncertain]** assumption.

---

## ⓪ STATUS

| System | State | Provenance |
|---|---|---|
| git | 3 commits on redesign-v4, 0 dirty tracked files | **[verified-now]** |
| Database | prod through **0072** — local == remote, pushed + verified | **[verified-now]** |
| Real customers | **zero** — all 23 prod bookings belong to `s4kim2025` (in `club_test_accounts`). 8 completed runs, all solo testing | **[verified-now]** (`scripts/pilot-metrics.mjs`) |
| SQL harness | **336 / 0** (was 305 — 31 new pins across 106-110) | **[verified-now]** |
| tsc | 0 errors | **[verified-now]** |
| check-rpc | 76 calls / 111 signatures, all match | **[verified-now]** |
| Prod post-push checks | anon denied on all 6 new/changed RPCs (401, not 404 — they exist) · `payments` anon SELECT 0 rows + anon INSERT refused by RLS | **[verified-now]** |
| geo runner | 38 / 0 | **[verified-now]** |
| Device verification | runner home · owner report · owner schedule + booking sheet · my/passport walked on sim | **[verified-now]** |
| Club screens | code + gates only — **not seen on screen** (this account has no club, so the club world is unreachable in the sim) | **[uncertain]** |

**Pushed 2026-08-11 pm (Sean: "push ahead").** 0067-0071 applied, `migration list` shows
local == remote, and the post-push verification was empirical rather than assumed: all six
new/changed club RPCs return 401 permission-denied to anon (401, not 404 — so they exist AND
are sealed), and `payments` refuses an anon INSERT with a row-level-security error rather than
a missing-grant error, which is the distinction 0057 exists to enforce.

## ⓪b Correction to a commit message I wrote

`12f5963`'s body says *"Every pin mutation-proven by a full-harness run under its own named
revert."* **That was an overclaim** and the review caught it: 106's own header lists S1/S3/S4/S5/S7
as proven and silently omits **S2 and S6**, and 107 R3 could not go red at all under the
`self_override` revert it claimed to guard (every R3 actor was a non-party host, so no call ever
reached that line — the reviewer proved it by deleting the guard and getting 317/0). R3 is rewritten
and both halves are now pinned (107 R3 + R6). The lesson is already written into 106's header from
the S5 incident and it applies to the message too: **a pin that cannot go red reads as proof.**

## ① Goal & current state

Korean dog-running marketplace (Banpo pilot, PMF gate: M1 rebooking ≥60%).
Pre-revenue; payments are still mocked. This session was **not** feature work on
the critical path — it was the coordinates slice, then a full design-system
rebuild, then an honesty sweep that turned out to matter more than either.

Workstreams: coordinates **done** · design system **done (v1 complete, P2 open)**
· honesty sweep **P1 done, P2/P3 open** · payments **not started** · incident
reporting **not started**.

## ② What shipped — 13 commits, `c5f22db` → `5b832eb`, 66 files

**Product**
- **0065 coordinates/geocoding** — `owner/address-pin.tsx` (pin-first capture),
  real pickup maps on both meetup screens, 길찾기 with web fallback,
  `geocode-address` edge fn as an honest no-op until the NCP secret exists,
  `scripts/geocode-backfill.mjs`. Course maps stay honestly dark (`routes.trace`
  is schematic `{x,y}`, not geo).
- **0066 en-route cancel at 50%** — Sean's decision. Transition map widened for
  `runner_enroute → cancelled_owner`; `picked_up` stays blocked and is pinned so
  we can't over-widen later. Fee ladder moved from TS **into SQL**
  (`marketplace_cancel_fee`) so the SQL-only harness can pin a money constant. A
  **CAS on the quoted status** closes the quote-then-depart race the widening
  itself created. Prod check: 12,450 on a 24,900 booking = exactly 50%.
  **[verified-now]**
- **Community + compose** — Instagram *anatomy* on paper grammar; `app/compose.tsx`
  (completed-run picker with honest preconditions); entry rows on both homes.
  Post→delete round trip verified against prod. **[verified-now]**

**Design system** — `DESIGN.md` created and hardened four times; paper chrome on
every main tab; type/density wave (gutter 15 finally *enforced* — it previously
had zero importers); GO premium Ⓐ④ + energy green; brand lockup masthead; emoji
purge (~160 marks / 33 files); owner + runner + request rebuilt to §3b including
the **gear distance dial**; 7 legacy-green runner screens scrapped.

**Honesty sweep** — full-app review (51 screens + 13 components) then every P1
fixed. Details in §⑥.

## ③ Standing doctrines — the 5 that bite most

Full law is in CLAUDE.md + DESIGN.md; these are the ones that will trip you:
1. **Honesty is a hard law, not a preference.** No mock data in real surfaces; no
   dead buttons; loading ≠ empty ≠ error; never render a claim the system can't
   substantiate. Most of this session's value came from enforcing it.
2. **Commit gate**: `tsc --noEmit` + `check-rpc-contracts.mjs` + **`bash app/test/run-geo-tests.sh`** (added this session — it existed but was wired to nothing, the exact failure shape commit `12027d1` had already fixed once).
3. **Money changes get their own migration + adversarial cycle** (0059 doctrine),
   with mutation-proof pins: each pin must go red under a single named revert.
4. **Definer functions**: `set search_path = public, pg_temp` in the body, revoke
   public/anon, party gate before state gate, identical errors for absent vs
   not-yours. Return-type changes need `drop` + **`create or replace`** (the
   check-rpc parser only reads the latter) plus re-issued grants and comment.
5. **Never `git add -A`** — untracked investor decks and secrets live in the tree.

## ④ Working-relationship norms — brief a new teammate

- **Decides by number.** Sean picks from numbered labs (`Ⓐ①`, `Ⓑ②`). When a
  design choice is real, build a lab in `docs/labs/`, don't argue in prose.
- **Quality bar words:** "no cheap", "no AI slop", "professional", "steelman it".
  When he says a doc exists but isn't being used, he means *make it binding*, not
  *mention it more*.
- **Grants autonomy explicitly and expects it to be used** ("make all decisions
  by yourself", "deploy agents for a second opinion"). Under that grant: decide,
  act, and report the reasoning — don't queue questions.
- **Wants the disagreement surfaced, not smoothed.** Independent-voice findings
  that contradict the plan should be shown with their evidence; he'll overrule or
  accept, but he wants to see it.
- **Corrections are terse and precise** ("that's still the old style", "thought
  you were using it"). They're usually pointing at a systemic cause, not the
  instance — fix the root.
- Verification: he will not accept "should work". Run the app, look at the screen.

## ⑤ Decision log — with WHY, reversals, and refusals

**Decisions**
- **Pin-first capture over geocode-first** — geocoding needs a secret only Sean
  can provision, so geocode-first would ship dead. A user-confirmed pin also
  beats a building centroid for a meetup point.
- **50% en-route cancel fee** (Sean) — runner compensation for someone who
  already set out. Fee ladder in SQL so it's pinnable.
- **`picked_up → cancelled_owner` stays blocked** — past the handoff, an owner
  exit is an incident, not a cancellation.
- **DESIGN.md §3b component spec** — the root fix for "every screen invents its
  own header": one section-header grammar, four button kinds, status chips on the
  datum's row. Abolishing latin kickers + subtitles killed ROSTER / VERIFIED
  COURSES / NEXT RUN·BOARDING PASS / 동네에서 함께 in one rule.
- **`pick-ui-library` + `ask-sonner` are taste references only** — they're web
  libraries (Sonner, base-ui, cmdk, Framer Motion); nothing to install in RN.

**Reversals / supersessions — do NOT re-litigate**
- **Club widget margins**: the paper wave made all cards full-bleed sharp
  (2026-08-10); **Sean vetoed** and restored its side margins the same day. It is
  the ONE standing exception — margins yes, rounded corners no.
- **Gutter 11 → 15** (2026-08-11) supersedes the 2026-07-28 "0.9x compression".
  Not a reversal in practice: the audit proved gutter-11 had **zero importers**,
  so 15 is the first value ever actually enforced.
- **Energy green**: I specified `#12A05C`; measured contrast was 3.382:1, failing
  the ≥3.5 gate in my own spec, so it shipped as **`#119B58`** (3.588:1).
  Measure before trusting a hex — including mine.

**Refusals — and why**
- **Did not execute the destructive cancel** against the prod test booking. The
  button, copy, and fee math are verified; pulling the trigger would permanently
  kill a booking I can't restore.
- **Did not widen the transition map for `picked_up`**, and did not write a
  migration when a fix "needed" one — money/schema changes go through Sean.
- **Did not bind the 신원인증 badge** to `runners.identity_verified`: the
  codebase's own rulings (0061, `api.ts:1255`, meetup P1-6) establish those
  values are fabricated. Binding would render a review that never happened.
- **Did not carry the mock's "지난번 그대로 채워뒀어요" copy** into the request
  rebuild — draft defaults are static, so the claim would be false.
- **Did not invent a settlement-intent table** to save two dead buttons; removed
  them instead.

## ⑥ The honesty sweep — what was actually wrong

Review verdicts: **PASS 8 · MINOR 30 · NEEDS WORK 25 · SCRAP 1**. All P1s fixed
in `331bcf4`. **[reported]** by the review agent, **[verified-now]** that gates
pass after the fixes.

1. **Mock data reached customers.** Every completed run's celebration screen named
   the *mock* dog 초코 (handover line, receipt, photo hint, CTA), and `run.tsx`
   used the mock's km as the **auto-settle threshold** — a fabricated number
   deciding money. Fixed: real name rides the settle result and degrades to
   naming no dog when unknown; auto-settle is **hard-off** without a real target,
   announced honestly. Also deleted: an invented "근처 동물병원 650m" (no data
   source), `runner/detail.tsx` (100% mock, orphaned, URL-servable), the
   `runRequests` array itself.
2. **A silent catch was destroying data.** `runner/availability.tsx` rendered the
   default all-쉬는날 grid on a *failed* load, so one 저장하기 overwrote the
   runner's real schedule with an empty set. Save bar now only mounts after a real
   load + hard guard in `save()` — structurally unreachable.
3. **~30 silent-catch sites across 22 screens** now render loading ≠ empty ≠
   error — including the club **consent document** (was lying on a legal surface)
   and two screens painting a slot 가능 when the check had **failed**.
4. **Trust theater**: owner stop button made no server call; matching fabricated
   an 88% response rate carrying 35% of the displayed score; 신원인증 badge had no
   data source. All three fixed or removed.

## ⑦ Architecture, contracts, DO-NOT-REFACTOR

- **DO-NOT-REFACTOR** (CLAUDE.md §, DESIGN.md §9): owner-home + fitness collapsing
  heroes (pinned overlay + paddingTop reservation + transform/opacity native
  driver only — no height animation) · meetup stage machines, polling,
  confirmHandoff, once-law hydration ordering (new state goes at the END of the
  hook bundle) · the 2-layer matching compositor · availability's 3 deliberately
  distinct predicates.
- **Pixel budgets that must be re-derived if touched**, not eyeballed: GO stack
  237 ≤ RING_BIG 240 and the disc interior 75 ≤ 140 (`owner/home.tsx` top);
  `headerHFor` (header height follows the ticker's real presence — never reserve
  space for a conditional element); runner-home column cages (bibNoCol, stubAct,
  stop column, ledger label).
- **BUG A**: Oswald (`useNumFont`) requires an explicit `lineHeight ≥ 1.2×` or
  ascenders clip. Use `Math.ceil`, not `round` (round gave 1.236× at the new GO
  sizes — caught this session).
- **Contracts**: `booking_pickup_address` returns label/addr/detail/lat/lng, gated
  to the assigned runner in the in-flight window or ≤24h before a confirmed
  booking; identical `not_runner` for absent/foreign/wrong-status.
  `bookings.km` is `numeric(4,1)` — fractional km is safe end to end **[verified-now]**.

## ⑧ File map — new this session

| Path | Role |
|---|---|
| `DESIGN.md` | design law book (token worlds, §3b components, §7b declutter, §7c Apple motion) |
| `supabase/migrations/0065_address_coordinates.sql` | lat/lng CHECK + widened pickup RPC |
| `supabase/migrations/0066_enroute_cancel.sql` | transition widening + `marketplace_cancel_fee` |
| `supabase/tests/105_enroute_cancel_suite.sql` | 7 pins, each with its red-making revert documented |
| `supabase/functions/geocode-address/index.ts` | NCP geocode; `{available:false}` without the secret |
| `scripts/geocode-backfill.mjs` | dry-run default; `--yes` to write; prints scoped undo |
| `app/app/owner/address-pin.tsx` | pin picker (center chain, spot chips, safe-area confirm) |
| `app/app/compose.tsx` | feed composer (completed-run picker) |
| `app/src/components/PickupMap.tsx` | memoized static map + ready-crossfade with timeout |
| `app/src/components/brandmark.tsx` | logo lockup (uses `app/assets/logo.png`) |
| `app/src/lib/reducedMotion.ts` | `useReducedMotion` — wired into only 2 loops so far |
| `docs/design/design-review-20260811.md` | the full review + P2/P3 backlog |
| `docs/labs/go-premium-lab.html`, `docs/labs/declutter-lab.html` | numbered labs |
| `docs/plans/coordinates-geocoding-plan.md`, `docs/plans/type-density-audit-20260810.md` | plan + audit |

Run commands: harness `pkill -f "bin/postgres" && cd supabase/tests && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bash harness.sh` · geo `bash app/test/run-geo-tests.sh` · app `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 npx expo run:ios` (from `app/`).

## 🔴 ⑨ Pending on Sean

**Ops** (unblocks already-shipped features)
1. **NCP console — TWO checkboxes**: Mobile Dynamic Map **and** Geocoding API, on
   the app registered for `com.seankookim.daengrun`. Device maps + geocode
   pre-centering are blocked until this. Also closes launch-checklist §5.
2. **`supabase secrets set NAVER_GEOCODE_SECRET=...`** — until then the picker is
   pin-only *by design* and backfill refuses to run.
3. **Counsel**: privacy policy carries a coordinates rider (HTML-comment marked);
   also flag that §1 never listed the pickup **address itself** as collected data.
4. **Spot-chip review** (5 min): 세빛섬 is map-calibrated; the other 7 in
   `address-pin.tsx` CHIPS are my map reading — swap any by name.
5. **Device smoke**: 길찾기 with the Naver Map app installed (sim only proved the
   web fallback) · pocket-walk GPS · APNs.
6. Standing: seed-runner decision · owner LA relay + config row · media purge ·
   변호사 / 위치기반 신고 / interviews / TestFlight.

**Decisions — nothing proceeds without these**
| Decision | Tradeoff | Blocks |
|---|---|---|
| **Mid-run stop delivery** | The owner's stop reason now goes via chat — the only real channel (no owner-side transition exists for an active run). But chat has **no push**, so it can go unseen. Real fix = an owner-stop transition (money ⇒ own migration + adversarial cycle) or a chat push. | A real early-stop flow |
| **Prod `identity_verified` cleanup** | Values are fabricated seeds. Cleaning them is the prerequisite for re-adding the 신원인증 badge **and** for safety.tsx's verification claim. | Trust copy across 2 screens |
| **Settlement intent** | `earnings.tsx`'s two CTAs were removed (no honest store exists). If early settlement is real product intent, it needs a table + flow. | P3 until payments |
| **안심 결제 chip** | Removed from request per the lab mock. Restore? | Cosmetic |
| **Declutter lab Ⓐ variants** | Never picked (you gave an explicit home list instead). The **5 "free surgeries"** still apply — chiefly merging the find-now radar island, which calls the GO disc's own handler (zero information loss). | A denser cleanup |

## ⑩ Known-good — do NOT "fix" these

Named by the review so the next wave doesn't regress them: **zero
TouchableOpacity app-wide** · **zero colored emoji** · `compose.tsx` · the
receipt seal ceremony · `club/case`'s LoadGate idiom (now promoted to a shared
component in `club-ui.tsx`) · the GPS honesty stack in `run.tsx` · shot's photo
truthfulness · the 0060/0065 pickup-address gating.

Also deliberate, don't "simplify": dark artifacts (passport record face, seal
band, club night world, settlement ticket, floating request ticket incl. its
**round** punch-hole notches) and Peak moments (GO press, handoff seal, run
completion, done screen) — these are exempt from decluttering by §7b.

## ⑪ Gotchas & failure modes

- **Tools that exit 0 on failure**: Expo/CocoaPods without a UTF-8 locale dies on
  a Unicode error but still exits 0, leaving a stale binary. Always
  `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`, and verify by bundle container path.
- **Harness**: `pkill -f "bin/postgres"` first — orphaned clusters give
  misleading errors.
- **The "Open debugger to view warnings" banner** is RN LogBox in dev builds, not
  a product bug (resolved mystery from the prior handoff).
- **check-rpc only parses `create or replace function`** — a bare `create` after a
  `drop` makes the gate silently validate a stale signature forever.
- **`to_jsonb` emits NULL-valued keys**, so a key-count contract pin stays green
  under a constant-NULL body. Value assertions are required (see 100 W6).
- **CHECK passes when its expression is NULL** — `(a is null) = (b is null)` is
  the NULL-proof pair form; the naive `OR` version admits half-pairs (proven red).
- 🔴 **The SQL harness cannot detect enum-migration transaction failures**
  (found 2026-08-11). `harness.sh` runs `psql -f` per suite with **no
  `--single-transaction`** → statement-level autocommit. `supabase db push`
  applies each migration file **inside a transaction**. `alter type … add value`
  followed by *same-transaction use* of that value raises `unsafe use of new
  value of enum type`. So a single-file enum migration goes **green on the gate
  and fails on push**. `language sql` bodies are parsed at CREATE (they break);
  `plpgsql` bodies are not (they survive) — so the failure is also inconsistent.
  **Law: any migration adding an enum value gets its own file, containing only
  the `add value`.** No gate we own catches a regression here. `bookings.status`
  is an enum (`0001_init.sql:9`), and zero migrations had ever added a value —
  there was no precedent to copy. **[verified-now]**

## ⑫ Environment & test data on prod

`s4kim2025` has one address ("Home", pin at 세빛섬 37.512203/126.996087) attached
to **two 8/4 `runner_enroute` bookings** — staged to verify map + cancel
surfaces. One belongs to a recurring series. The in-app cancel is the honest way
to clear them. I briefly nulled `owner_confirmed_handoff_at` on one to reach a
screen state and **restored it to its exact original timestamp**. **[verified-now]**

Prod `addresses` had **0 rows** before this session's test pin, so the geocode
backfill is moot until real users add addresses.

## ⑬ Ephemeral artifacts — re-attach if needed

Images Sean pasted this session (they do **not** carry over): the **running-dog
logo** (now committed as `app/assets/logo.png` — it arrived as flat RGB with the
transparency checkerboard baked in as literal pixels; I flattened everything that
isn't the black hound or the red streak to white, 864KB → 107KB), **Instagram UI
screenshots** (used for feed card anatomy — identity header, edge-to-edge media,
action row under content, caption, timestamp), and **two app screenshots** of the
intermediary confirmation screen + a paper screen he liked (the source of the
"square sharp cards, coral thin separator, that go-back button" direction, now
codified as DESIGN.md §2 paper chrome + §3b). Re-attach only for pixel work.

## ⑭ Agent state & coverage gaps

All subagents completed; none left running. The design review's findings are
**[reported]** — I verified the gates after its fixes, not each of its 51 screen
audits. Its own coverage note: the 7 runner screens were converted concurrently
and are tagged `[CIF]` in the doc — **re-verify those findings** against the
converted code. Of ~25 silent-catch screens, **22 were fixed**; the sweep listed
its own remainder (owner/pay authorizing dead-end, club receipt photo-consent
gate failing *open*, chat/cards/index/shot P3s, frozen-screen sites).

## ⑮ Strategic read — my recommendation, and the counterargument

**Ship the payments bridge next, not more design.** The design system crossed
from liability to asset this session, and the honesty floor is now defensible.
What remains between here and a paying customer is: payments (`payment_ok` is a
mock and pay.tsx says so), incident reporting on the safety screen, and real
runners. The CEO voice raised this twice today, and the manual bank-transfer
bridge in `payments.md §파일럿 브리지` is **buildable code, not Sean-gated** —
unlike the PG track.

**The counterargument, honestly:** the P2 tier of the review is cheap and
compounding (reduced motion across ~8 remaining loops, the `ui.tsx`/ClubTag
component sweep clears ~30 findings from one file, the gear dial's momentum
projection). Doing payments on top of a component layer that still ships 9.5pt
Korean chips means re-touching those screens later. My read: **do the ClubTag /
ui.tsx sweep first** (it's one file and clears the most findings per hour), then
payments — and let reduced motion and the dial ride along with whatever screens
payments touches.

## ⑯ Next 1–3  *(rewritten 2026-08-11 pm — §⑯-0, -0b and -3 are all DONE)*

**Done this session.** The three items the last handoff put in order all shipped:
- **§⑯-0 SECURITY** → `0067_incident_subject_gate.sql`. Both traps were handled as briefed: 95 G12
  was rewritten in the same commit (it was green *because* the validation was absent), and
  `club_sos` became a thin wrapper rather than being dropped and repointed, still returning `uuid`.
  One thing the brief did not anticipate: **`_club_shell_access`'s permanent `'limited'` must NOT be
  narrowed** — 0053 §5 made it permanent on purpose (a rejected applicant reads their own rejection
  card and their own host_channel thread) and 96 F5 pins it. The right cut was a separate
  `_club_incident_can_open`: seeing the door and freezing money are different rights.
- **§⑯-0b** → C1 `0068` (the T-10 auto-refund deleted, 65 A8 inverted in the same commit),
  C3 `0067 §E` (SOS unified, owner finally notified), C4/H5 `0069` + `0070 §F`.
- **§⑯-3** → `ed0adb9`. ClubCta's coral was 2.83:1 white; it now uses `paper.action` (4.84:1, the
  same hex already shipping as MONEY_DEEP/GO_SKIN.deep), `violet` is retired as an action tone, and
  `secondary`/`destructive` faces exist so 10 `quiet` CTAs stopped standing in for them.
  report.tsx migrated to paper and went from six CTAs to three. runner/home.tsx retired its local
  coral consts, demoted the fake coral `<View>`, and the bib strap inverted to ink.

**Then the adversarial cycle ran, and it mattered.** Codex + an independent Claude engineer, both
executing attacks against a live scratch DB. Neither could reopen the payout freeze. They found
that **four sentences written in 0067/0069's own headers were false as shipped** — fixed in
`0070_incident_accountability.sql`, whose header is the best single account of it. The one worth
knowing by heart: **`session_host_force_resolve` was unusable in exactly the shape the audit
described.** Host-only + self-override-banned meant that in a small club, where the host runs the
dogs, nobody could call it — and the console drew the button anyway, so C4's "fix" was a dead
button. 0070 §F opens it to the backup host and narrows self-override to the dog's *owner*: a host
reporting their own run stuck is self-incrimination, not self-dealing.

**Also done: the payments table (`0071` + pins `109`).** That was the *entire* unblocked payments
list per toss-plan §5-1, and it closes finding R7 — `ledger_items` recorded only the runner's
payout, so nothing anywhere said money had arrived (no revenue record, no tax record, no refund
handle). Nothing charges anyone; the transition map is untouched, and P6 pins that premise because
the whole reason the Toss track is small rests on it. **Step 1 of §5 is now empty: everything
remaining on payments is behind Sean's filings.**

## 🔴 The strategic call I'd put in front of you first (Codex, standing in for you)

You delegated decisions to Codex for the unattended run. It ranked the work, I built all five, and
then it said something worth reading before you pick up the next thing:

> "The absence of real runners and customers changes the answer completely: after these five, stop
> building. The next unit of progress is a real two-person run followed by a second booking — not
> reduced motion, emoji cleanup, rewards polish, another club abstraction, or more backend
> hardening. Existing rebooking UX is already sufficient to test; the company now needs people,
> observation, and a trustworthy number."

I agree, and the metric I built proves the shape of it: `node scripts/pilot-metrics.mjs` reports
**—**, because every booking in production is yours. The remaining TODOS backlog is real but it is
all downstream of having one real owner and one real runner.

## 🔴 Payments — where it actually stands (asked + answered 2026-08-11)

**Real payments cannot be made yet, and 사업자등록 is the first of four locks, all Sean-only:**

| Lock | Detail | Blocks |
|---|---|---|
| 사업자등록 | 홈택스, same-day, free. 개인사업자 is fine to start | everything below |
| 통신판매업 신고 | 시/군/구, after 사업자등록. ~₩40,000/yr 등록면허세 | the PG contract |
| 토스페이먼츠 계약 | 1–2 week review; needs both documents above | the live switch |
| `TOSS_SECRET_KEY` | `supabase secrets set …` — Sean only, value never relayed | `confirm-payment` |

Realistically **~2–3 weeks from the day the first filing goes in**, and the clock cannot start
without Sean. ⚠ 예비창업패키지 2027 (~₩40M) closes the moment 사업자등록 lands — decided already,
restated here because the timing question keeps coming back.

What is true today and must stay true until the switch: `pay.tsx:299`'s
"실결제는 발생하지 않았어요" is **accurate**, and `pay.tsx:334` → `api.ts:230` `payment_ok` is the
only path a booking has into `matching`. Deleting either before `confirm-payment` is live bricks
confirmation and turns an honest sentence into a lie. They are toss-plan step 3, not step 1.

## ⑯-b Unattended run, 2026-08-11 (Sean away, Codex in the decision seat)

Seven commits. Codex ranked the work; every item below is its pick, executed and gate-verified.

- **Harness law, repo-wide** (`28da5b0`). The `_fail`-subquery defect was 12 executable sites across
  five suites, not the 4 a single-line grep found. Mechanically rewritten (`v_msg := <expr>` then
  call), and verified the only way this defect allows: forced a pin's assertion false against a
  fresh harness and watched its failure path render instead of raise.
- **Mid-run stop actually arrives** (`db320b1`). Chat carries no push; the notification does. The
  routing was the real work — a `booking` notification sent runners to `/runner/calendar`.
- **Accepting is a promise** (`5209c2c`). Both doors on runner/requests committed on one tap.
  The reschedule door was worse: it silently moved an already-confirmed booking's time.
- **The completion screen stops lying about money** (`4557e99`). On settlement failure the runner
  taps "나중에 (추정치 표시)" and the next screen printed that estimate as 오늘의 수익 on a receipt.
  `runResult.settled` now separates server-confirmed money from a client guess. Also deleted
  "수익은 매주 수요일 정산됩니다" and "매주 정산" — there is no payout operation to schedule.
- **The PMF gate is computable** (`78ce95e`). See §⑯-b above.
- **Club H3/H4** (`082bf32`). Stopped rendering a fabricated club (with an OFFICIAL badge) for both
  "loading" and "no club exists"; gave the host the session-cancel door that has existed server-side
  since 0038 with zero call sites.
- **Backlog truth** (`c12f4ee`). Four TODOS entries listed finished work as open — done.tsx's dog
  name, club H1, club H2, M5. Verified each in code before believing Codex, then corrected.

**Next 1–3, in order:**

1. 🔴 **`incident_review` has no commercial exit** (TODOS, both voices). Force-resolve and the 0058
   clinic transfer both park bookings in a terminal state where the owner stays charged and the
   runner can never be paid. The console now says so honestly instead of claiming 정산은 보류돼요,
   but a disclosure is not a fix. This is the payments track's first real customer.
3. **[needs-user]** The rest of §⑨: NCP checkboxes, geocode secret, counsel flags, chip review.
   Plus `identity_verified` (9/9 fabricated) and the seed-runner decision — both re-measured
   against prod and unchanged.

3b. **[local-edit]** The P2 tier: reduced motion across the ~8 remaining loops · gear-dial momentum
   projection · the surviving CIF items (`rewards.tsx:181`, `rewards.tsx:38/42/43`,
   `requests.tsx` accept-without-confirm, `calendar.tsx:92`) · `apply.tsx:964,:985` opacity state
   paints · and the **new** emoji finding in TODOS: `seed.sql` ships `♒`/`☀` in `routes.features`
   which iOS renders as colour emoji by font fallback, on the owner home, right now.

## ⑰ Verification commands

**Safe / read-only**
```bash
git -C /Users/sean/dev/daengrun log --oneline -5 && git status --porcelain
cd /Users/sean/dev/daengrun/app && ./node_modules/.bin/tsc --noEmit
cd /Users/sean/dev/daengrun/app && node scripts/check-rpc-contracts.mjs
bash /Users/sean/dev/daengrun/app/test/run-geo-tests.sh
cd /Users/sean/dev/daengrun && supabase migration list
node /Users/sean/dev/daengrun/scripts/diag.mjs
```
**Expensive but non-destructive** — PG16 harness (~2 min; kill orphans first)
```bash
pkill -f "bin/postgres"; cd /Users/sean/dev/daengrun/supabase/tests && \
  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bash harness.sh 2>&1 | tail -3
```
**Destructive / changes the world — confirm with Sean first**
`supabase db push` · `supabase functions deploy <name>` ·
`node scripts/geocode-backfill.mjs --yes` · `node scripts/wipe-test-data.mjs` ·
`node scripts/migrate-private-media.mjs --yes --purge` · any in-app cancel of the
8/4 test bookings.
