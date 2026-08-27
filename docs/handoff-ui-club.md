# Handoff — UI / client-honesty lane (the "b6" session), 2026-08-27

**Read first:** `CLAUDE.md` (permanent laws) · `DESIGN.md` (design 정본) ·
`docs/fleet-orders.md` (fleet operating layer) · `docs/session-handoff.md`
(**the announcer session owns that file — do not edit it from this lane**).
`supabase/migrations/REGISTRY.md` in-flight table carries the live path claims.

This file covers ONE lane: the club session/console/run screens, the client
honesty fixes, and the share-card surfaces. It is deliberately separate so two
sessions never write one handoff.

---

## 1. Status table

| System | State | Provenance |
|---|---|---|
| Trunk | `4f81534` on `origin/redesign-v4` | **[verified-now]** `git rev-parse` after fetch; gates below re-run ON this SHA |
| Working tree | clean; my worktree `.claude/worktrees/roster-custody` | **[verified-now]** |
| tsc | clean, exit 0 | **[verified-now]** `./node_modules/.bin/tsc --noEmit` |
| lint | **6 errors** / 273 warnings — 6 IS the baseline, not a failure | **[verified-now]** |
| npm test | exit 0 · **707 PASS · 0 FAIL** | **[verified-now]**, counted with `grep -c '^PASS'`, NOT through `tail` |
| Migrations | **0 pending** — production applied through 0152 | **[verified-now]** `supabase migration list --linked` |
| Charging | OFF — `payments_live_since` null, `card_registration_live_since` null | **[reported]** by the announcer; I did not re-run |
| Codex on this lane | **Only 2 slices ever got a verdict.** See §6. | **[verified-now]** from my own run logs |
| Device verification | Add-dog door + sheet + error path verified live. Chips/return legs NOT. | **[verified-now]** §11 |

⚠ **The lint "6 errors" is the pass condition.** All six are pre-existing
`react-hooks/exhaustive-deps` in other files (course-map, fitness, matching,
request ×2, shop). 7 means you added one.

---

## 2. Goal & current state

Ship a Banpo pilot where **every screen tells the truth**. This lane's job all
session was one defect class: *the app asserting something the server does not
say*. Raw enum tokens in Korean UI, fallbacks that overstate, claims of records
and money that never happened, controls whose effect is discarded.

Workstreams:
- **Club roster / console honesty** — DONE, landed.
- **Add-dog door (`session_add_my_dog`)** — DONE, device-verified.
- **Return legs (집 반환 + 현장 반환)** — DONE, not device-verified.
- **Run-screen freeze obligations** — DONE, not device-verified.
- **Share-card / report "unknown ≠ 0"** — DONE, 2 P1s handed to the announcer.
- **Guest (게스트) affordance counterpart** — **NOT STARTED. Reframed by
  `docs/decisions/guest-gps-options.md`; the cheap half is no longer blocked.** §9.

---

## 3. What shipped (grouped, with SHAs)

**Roster & console vocabulary**
- `8874d89` roster binds `RosterDog.custody` → 「동반」 / 「위탁」 / 「자리 확정」.
  Before this, an owner-handled dog and a paid delegation rendered identically.
- `47a370f` `a0d014c` `4608a7d` `9ff9885` console charge chips: killed a raw
  `none`/`hold` English leak; 「자리 잡는 중 · mm:ss」 with a live countdown;
  `none` → 「자리 미확정」 so an approved dog is never invisible.
- `d6dd28f` 0140's `dog_limit` translated on **both** doors (it is a trigger, so
  `session_rsvp` raises it too).

**Credential / label correctness**
- `729c1a6` `app/src/lib/tier.ts` — five call sites mapped `runners.tier` with
  copied logic; three sent an unmatched value to 「마스터」, the TOP credential,
  while the server gate is a negative predicate. One positive-match helper +
  mutation-verified pin.
- `77a9205` `app/src/lib/claim-status.ts` — same treatment for `claim_status`.

**Doors that did not exist**
- `78d4777`…`afbb7bc` add-dog door for `session_add_my_dog` (0134 §C). Six codex
  rounds; see §6.
- `3585afc` entry point into the announcer's 동반 run screen.
- `b35810d` 집 반환 길찾기 · `200286d` 현장 반환 chat path.
- `0714ac8` run-screen freeze obligations, gated on `runEnded` (0147).

**Deploy-window safety**
- `cbdac06` `f4dd59d` `7f5751e` `2b5d1c1` — `app/src/lib/rpc-skew.ts`: a
  PGRST202 from an **undeployed** function is translated to Korean, but ONLY for
  functions on a named list. List is now **empty** (correct resting state).

**Unknown ≠ zero**
- `e6ed11b` `6456791` — `actualKm`/`durationSec` nullable at source; every
  consumer re-decided; `run-share-card.tsx` `km` made nullable and 「완주」 keyed
  to `endReason`.

**Notifications & report** (agent work, I read the diffs and re-measured gates)
- `528c74a` safety notifications were a **dead tap** (4 live rows); the 20-minute
  deadline notification dead-ended on 「이 러닝을 찾을 수 없어요」 (7 live rows).
- `d3bdaa2` `incident` / `owner_forced` end reasons named, so an incident run
  stops rendering unexplained.
- `aa48f02` 71 sub-15pt sites raised to the ruled floor.

---

## 4. Standing doctrines that bit hardest here

Canonical: `CLAUDE.md`. The five that cost real time this session:

1. **Bind real fields or omit.** Never render a state the payload cannot back.
2. **Loading is not 0 — and neither is unknown.** `?? 0` on a measurement is a
   fabrication. A dash is the same lie wearing different clothes.
3. **No dead buttons.** A control whose effect is discarded is the same defect
   even when the discard is server-side.
4. **A push that succeeds is a claim; the file read back off origin is the fact.**
   Applies to `pg_proc` too — "deploying" ≠ "deployed".
5. **`git commit -- <explicit paths>`**, absolute paths, and cut every worktree
   from `origin/redesign-v4`.

---

## 5. Working-relationship norms (Sean)

- **Terse.** "go ahead", "you can", "sure", "use codex yourself dawg". Brevity is
  approval, not disengagement. He does not want the plan re-litigated.
- **He wants volume and parallelism** — "use agents generously", "make yourself
  useful", and he called the announcer out for narrating instead of building.
- **He reads plain user-language reports.** For status he asked explicitly for
  「CLEAR, NO JARGON, TO THE POINT」: what a user can now do, what stopped lying,
  what is live vs merely landed, what needs him.
- **He rules by short verbatim sentences** that become law — 「1 dog per person」,
  「Stays free」, 「the self runs are still part of the pack. so yes.」 Quote them
  verbatim in code comments; do not paraphrase.
- **He grants autonomy and expects you to use it.** He also expects to be told
  plainly when something is unverified — that is not treated as failure.
- **Honesty over polish.** Landing over a REJECT with residuals named is
  acceptable; claiming a review that did not happen is not.

---

## 6. Decision log (with WHY, including reversals and refusals)

**Codex status on this lane — say this out loud, it is easy to misread.**
Only two slices carry a real value-matched verdict: the console money copy and
the companion entry (both APPROVE-WITH-FIXES, fixes applied). The **add-dog door
was REJECTED six times**; I landed it over the sixth with residuals named in the
commit. Everything else says NOT REVIEWED in its commit message. [verified-now]

**REVERSED: 「완주」 keying.** First I dropped 완주 when distance was unknown,
arguing 완주 is *a claim about the distance*. Codex refuted it: distance presence
is not proof of completion — a measured `dog_condition` stop still published
완주. Now keyed on `endReason === 'completed'`, matching what the report hero
already did. The exported card was the one getting it wrong. `6456791`

**REVERSED (announcer's ruling, twice):** `none` in the console →
「no chip」 → gate the row out → **「자리 미확정」**. The middle version made an
ordinary approved dog visible in NO section of the console. `9ff9885`

**REFUSED: seeding a production row while a money cron could not be proven blind.**
Held for hours; the announcer's caution turned out to rest on a substring grep
(`custody` matching `custody_phase`). Once measured — blind by
`payout_state='payable'` — I seeded one row, screenshotted, deleted, and verified
the before/after counts matched.

**REFUSED: pulling the `PENDING_DEPLOY` entries when told the stack "is
deploying".** `pg_proc` said 0. Removing them would have restored a raw
PostgREST sentence in a Korean screen. Removed only after I read `pg_proc`
myself. `2b5d1c1`

**REFUSED: fixing the run-screen obligations unconditionally.** The server
REQUIRES a valid `end_reason` on the non-frozen path, so stripping the picker
would have 400'd every ordinary club settle — trading a defect that arms at
deploy for one that fires immediately. Asked for `runEnded` instead; the
announcer built 0147. `0714ac8`

**STOPPED a fix loop deliberately.** After five codex rounds where each fix
produced the *mirror image* of the previous defect (lock→leak→remove→unguarded→
mutex→early-release; issued-ordering→discards-successes→applied-ordering→inverse),
I stopped rather than attempt a sixth ref. **When consecutive review rounds keep
producing inverses, the surface lacks a primitive** — here, query invalidation.

---

## 7. Architecture, contracts, DO-NOT-REFACTOR

**Ordering / coupling**
- Migrations 0131–0152 are **live**. `session_add_my_dog`, `runEnded`,
  `dog_limit`, `session_record_companion_run` all exist in `pg_proc`
  [verified-now]. A build may now ship without a skew window.
- **`rpc-skew.ts`'s `PENDING_DEPLOY` list must stay EMPTY** unless a NEW
  undeployed RPC gets a client caller. A test pins the contents; adding an entry
  requires updating the pin, which is the point.

**Deliberate, do not "fix"**
- `app/src/components/charge-states.tsx:37` — `STATUS_LABEL[status] ?? status`
  looks like the raw-token defect. It is safe: `payments_status_vocab` CHECK has
  exactly six values and the map covers all six, so the fallback is unreachable.
  ⚠ **I earlier said it was safe because the domain is OPEN. That was wrong** and
  an audit agent corrected it. The genuinely open documented case is
  `delete-account-sheet.tsx:52-58`.
- `app/app/runner/home.tsx:443` keeps its OWN 3-entry tier map on purpose
  (plan §6.3): on a runner's own home an `applicant` reads 「러너」, never
  「지원자」. `tier.ts`'s header records this. Do not fold it in.
- `owner/meetup.tsx`, `runner/meetup.tsx`, `runner/run.tsx`, `owner/fitness.tsx`
  hero — DO-NOT-REFACTOR per CLAUDE.md. I read `runner/meetup.tsx:319` for the
  nmap idiom and copied it without touching the file.
- **The 도착 button does not exist on purpose.** Arrival is the existing
  two-sided seal (`session_confirm_return`); directions record nothing, so no
  word implies they did.
- **No phone affordance anywhere in the return flow.** Ruled and already
  refused: `docs/labs/round6-picks-and-live-map.md:77-79`. Cited at both sites.

**Mutation-verified pure modules — re-run the BATTERIES, not just the suite**
- `app/src/lib/tier.ts` + `app/test/tier.test.cjs` (7/7 mutations caught)
- `app/src/lib/rpc-skew.ts` + `app/test/rpc-skew.test.cjs` (6/6)
- `app/src/lib/claim-status.ts` + its test (6/6) [reported] by its agent
A green suite after editing one of these predicates means very little on its own.

---

## 8. File map (this lane)

| Path | Role |
|---|---|
| `app/app/club/session/[sid].tsx` | roster chips, add-dog door + sheet, return legs, companion entry |
| `app/app/club/console/[sid].tsx` | host charge chips, money copy |
| `app/app/club/run/[sid].tsx` | freeze-gated end reasons + GPS refusal |
| `app/app/club/receipt/[bid].tsx` | 기록 없음 states |
| `app/app/owner/report.tsx` | reason chips, unknown-distance states |
| `app/app/shot/[bid].tsx` | share studio; skin G no longer prints a unit without a number |
| `app/src/components/run-share-card.tsx` | exported PNG; `km` nullable, 완주 by `endReason` |
| `app/src/lib/tier.ts` · `rpc-skew.ts` · `claim-status.ts` | pure modules + pins |
| `app/src/lib/api.ts` | **SHARED** — I touched `runEnded`, `runnerTierLabel`, `addMyDogToSession`, `fetchRunReportOrNull`'s projection, and `clubRpc`'s skew branch. Nothing else. |

**Not mine, landed on trunk while I wrote this** (`de902e6`, `0d5d8a7`): the
사고 신고 client half — `app/app/incident/[bid].tsx`, `app/app/safety.tsx`,
`push.ts`, and ~239 lines of `api.ts`. Another lane owns it; the gates above
were re-run WITH it present and stayed green.

**Run the pins:** `cd app && bash test/run-tier-label-tests.sh` (same shape for
`run-rpc-skew-tests.sh`, `run-claim-status-tests.sh`). They esbuild the REAL
source — never a retyped copy.

---

## 9. Pending on Sean

### Ops
- **Device smoke on hardware.** 934 type-size changes went out across the fleet
  (71 of them mine). That class reads clean in a diff and wraps on a phone.
  Nothing is device-verified except §11.
- Nothing else from this lane needs a credential or a console toggle.

### Decisions
1. **Guest (게스트) — SUPERSEDED while this file was being written. Read
   `docs/decisions/guest-gps-options.md` (landed `c2dcd49`, 2026-08-27), not the
   version of this item I first wrote.** A read-only scout re-derived the facts
   at source and corrected my framing on three counts:
   - **The join CTA is already written and already honest.**
     `app/app/club/[id].tsx:518-531` promises exactly free · own account · one
     seat, and `:507-513` is a 🔴 comment explaining why GPS is deliberately not
     claimed. I had this as "the free-guest ruling is still invisible in-app" —
     **that was wrong**; nothing is owed here.
   - **It is a pack gap, not a guest gap.** A 동반 owner with a dog is equally
     invisible (`app/app/club/companion/[sid].tsx` has no publisher), and the
     host sees nothing at all. A guest-only build would be the narrow version of
     something missing for everyone.
   - **The constraint that decides it is legal, not product.** The drafted
     privacy policy says location is 「해당 예약의 보호자에게만」
     (`docs/legal/privacy-policy.md:88-91`), and that document is with counsel
     now. Every widening option requires rewriting that sentence.

   ⚠ The scout also flagged that my four "Measured" guest facts most likely
   re-read the source comment at `[id].tsx:507-513` rather than measuring
   independently. They were correct, but **do not count the handoff and the
   comment as two confirmations** — that is one read counted twice.

   **What is actually on Sean:** pick A (guests watch the pack) / B (everyone on
   the map) / C (record, not map), plus the who-may-watch rule. The memo's own
   read, and mine after reading it, is **C now + checked-in as the rule if A ever
   ships** — C needs no realtime work, no privacy-policy change, and closes the
   uncontested half. **Separately queued:** a guest currently hands the host
   their phone number under `phone-host-scope = wide` (`0053:412-444`), GPS
   entirely aside. That one is not blocked on the GPS decision.
2. **Should the share studio refuse to build a card at all when distance is
   unknown?** The report closes its share door; the receipt card still renders
   and states the absence in words. I made the card incapable of lying either
   way but did not pick. *Tradeoff:* consistency vs. keeping an honest receipt
   available.
3. **Pre-existing:** the report's share text says 「완주」 for **every** stopped
   run with a measured distance — the hero title on the same screen is careful,
   the share text is not. One line from what I changed; not mine to rule.

---

## 10. Known gotchas & false-success modes (all cost time this session)

- **`npm test | tail -1` prints only the LAST suite.** I quoted "30 pass" for
  hours; the real run is 707. Count `^PASS`/`^FAIL` and check the exit code.
- **`git diff HEAD~1` includes uncommitted changes**; `git show --stat HEAD` is
  the commit. I nearly flagged a correct agent over this.
- **The main clone is stale.** It answered honestly about ~40-commit-old code
  twice and I twice believed work had vanished. **Absolute paths, always** —
  `cd app` in a chained command carries the shell's previous cwd.
- **`strings -a` finds NO Korean in a Hermes bundle.** Non-ASCII lives in a
  UTF-16 table. A Korean grep returns 0 whether the string ships or not. Use a
  UTF-16LE byte search.
- **A comment quoting removed code matches every grep hunting that code.** Filter
  comments before counting: `grep -vE '^\s*(//|\*|/\*)'`.
- **A column name is a substring of every longer column containing it.**
  `custody` matches `custody_phase`. Anchor it.
- **My own codex wall-detector false-positived** on `docs/fleet-orders.md`, where
  we documented the detector. The check matched its own documentation.
- **`codex exec` echoes the whole prompt into stderr** (~80–85% of a burned log).
  Grep **stdout** for a verdict VALUE, never the bare word; the `<X>` placeholder
  must occupy the value position.
- A **Debug** RN build silently loads another session's Metro bundle on :8081.
  Build **Release** and prove the binary carries your code.

---

## 11. Device verification — what IS confirmed

Release build of trunk on a **second** simulator (iPhone 17 `21DD10F5`), leaving
ui6's device and Metro untouched. **[verified-now]**

- Add-dog door renders, correctly gated.
- Sheet shows the full waiver, **both** dogs (no Android 3-button truncation),
  and 「확인하고 데려가기」.
- Pressing it called the **deployed** RPC; the server refused (session dated 8/8)
  and the screen showed 「이 세션은 마감됐어요」 — **not raw English.**
- The refusal wrote nothing: `owner_handled_rows 0, total 8`, unchanged.
- 15pt floor renders without wrapping on the screens walked.

**NOT verified on device:** 동반/위탁 chips (needs a live non-ended dog), both
return legs (needs a delegated dog in `return_pending`), the frozen-pair gates
(needs a host to press 러닝 종료), 기록 없음 states, share cards.

---

## 12. Known-good — do not redo

The roster chip vocabulary, the console charge words, `tier.ts`/`rpc-skew.ts`/
`claim-status.ts` and their batteries, the add-dog sheet, and the return legs are
at the bar. They carry long comments explaining WHY; those comments are load-
bearing — several record measurements that are expensive to re-derive.

---

## 13. Strategic read

**The remaining honesty debt is concentrated in `api.ts`, not in screens.** Every
screen defect I fixed traced back to a projection that flattened a server state:
`?? 0`, `?? 'pending'`, `default: 'CLEARED'`. Two P1s are already handed to the
announcer (`api.ts:2425/2666/2769` NULL-km collapse; the feed's 「— km」 via
`:4246` + `community.tsx:588`). If I were choosing the next lane, it would be a
systematic pass over `api.ts`'s projections rather than more screen work —
**make the type nullable at the source and let tsc enumerate the consumers.**
That is what found `run-share-card.tsx`, which nobody had listed and which
exports a PNG.

If pushed back on ("screens are what users see"): the screens are now honest
*given their inputs*. The next lie will arrive through a projection, and it will
appear on several screens at once, which is exactly what happened with `tier`
(five sites) and `actualKm` (nine).

**Second:** the add-dog door needs a data layer before it is truly right. Six
rejections localized the problem — no query invalidation, plus a fetch with a
privacy side effect. That is a slice, not a patch.

---

## 14. Next steps

1. **[read-only]** Verify trunk and gates before anything:
   `git fetch && git rev-parse --short origin/redesign-v4`, then the §15 block.
   Confirm `PENDING_DEPLOY` is still empty on executable lines.
2. **[local-edit, NOT needs-user]** Option C from the guest memo is unblocked
   and cheap: let a checked-in dogless member record a walk. One predicate in
   `session_record_companion_run` (allow `v_dog is null`; `participant_activities
   .dog_id` is **already nullable**, `0030:104`) plus its pins, and a CTA on
   `app/app/club/session/[sid].tsx` reusing the companion screen. No realtime
   work, no privacy-policy change. Do **not** wait on the A/B ruling for this.
3. **[local-edit]** If the announcer has not taken them, the two `api.ts` P1s.
   Expect tsc to go red at the boundary of whatever file surface you allow; stop
   and widen deliberately rather than reaching in silently.

---

## 15. Verification commands

**Safe / read-only**
```bash
cd /Users/sean/dev/daengrun && git fetch -q origin && git rev-parse --short origin/redesign-v4  # was 4f81534 when written
cd app && ./node_modules/.bin/tsc --noEmit                 # expect: silent
npm run lint 2>&1 | grep problems                          # expect: 6 errors
npm test > /tmp/t.out 2>&1; echo $?; grep -c '^FAIL' /tmp/t.out   # expect: 0 and 0
bash test/run-tier-label-tests.sh                          # pure-module pins
supabase migration list --linked | tr ',' '\n' | grep -c '"remote":""'   # expect 0
```
**Expensive — do not run casually**
```bash
# Release build to a simulator (~10 min). NEVER build Debug while another
# session runs Metro on :8081 — you will silently load their JavaScript.
xcodebuild -workspace ios/app.xcworkspace -scheme app -configuration Release \
  -sdk iphonesimulator -destination 'id=<A SECOND DEVICE>' ARCHS=arm64 build
```

---

## 16. Environment / test data left behind

**None.** One temporary `owner_handled` row was created and deleted during
verification; before/after counts both read `owner_handled 0 / total 8`
[verified-now]. No feature flags touched. `.env` copies made into the worktree
for builds were deleted. No agent worktrees hold unpushed work — everything this
lane produced is on trunk.
