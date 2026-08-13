# Handoff — club-delegation / money-decisions session (2026-08-13)

**Branch:** `claude/club-delegation-money-gaps-b59eb8` · identical to `origin/redesign-v4`, nothing
unmerged, nothing in flight.
**Opener for whoever picks this up:** *"read docs/handoff-club-delegation-money-gaps.md, then
docs/decisions/README.md, then docs/retro-2026-08-13.md."*

---

## 1. What this session was, in one paragraph

It started as three open money questions and became **the decision record for the whole money
model plus two shipped slices**. Thirteen decision memos now live in `docs/decisions/`, each
carrying Sean's own words; ⑩ (cancel-fee runner share, `0085`) and ⑬ (chat notifications, `0090`)
were built here; four honesty defects were found and fixed across client screens; and the
coordination infrastructure five parallel sessions needed — the migration registry, the in-flight
claim table, the four rules — was largely written here. The retrospective is
`docs/retro-2026-08-13.md`.

**The single most important thing to carry forward:** *"The schema is in production, the code that
drives it is not, and the money is switched off."*

---

## 2. Ground truth right now (verified, not inferred)

| Fact | State | How verified |
|---|---|---|
| Schema | **DEPLOYED, `0001`–`0091`, every row `local == remote`** | I ran `supabase migration list` |
| Edge functions | **NOT deployed.** Production runs pre-`0078` functions against a post-`0091` schema | no commit, doc, or checklist records a deploy |
| Charging | **OFF.** `payments_live_since` is NULL; both minters return early; crons find nothing | code-verified — ⚠ **nobody has read the live row** |
| `profiles` P0 | **CLOSED in production** (`0088`+`0091`) | verified externally with the anon key |
| Next free number | **0094 / suite 130** | `supabase/migrations/REGISTRY.md` on origin |
| My branch | 0 ahead, 0 behind trunk, clean, claim released | `git status` |

⚠ **`0088` alone 403s every signup.** It omits `SELECT` on `role`, which PostgREST's role-picker
upsert reads via `excluded.role`. `0091` grants it. **If these two are ever separated, `0091` is
the one that must not be dropped.**

---

## 3. 🔴 Live in production RIGHT NOW — read before anything else

**① The course catalog is empty for every installed app.** `0082`'s backfill classified every
route as `candidate` (its own comment says no row qualifies as `active`), and `active` became a
generated column. The **shipped** client filters `.eq('active', true)` at `api.ts:62` and `:917`.
Degradation, not an outage — the request screen handles empty honestly, so people book route-less
— and **today's client already fixes it** with an active→candidate fallback. **Fixed by shipping
the app, not by touching the database.**

**② `0085` and `0086` are deployed but unreachable.** Their only callers are edge functions, and
none were deployed. So **a runner whose evening is cancelled inside 24h still gets ₩0 while the
owner is told they got 50%** — the exact bug `0085` exists to fix, still live. Same for `0086`'s
pass-through runner pay.

**③ The ops runbook silently changed.** `update routes set active = false` — the incident
vocabulary for 81 migrations — now **errors**. Replacement: `set status = 'suspended'`.

**④ A tapped chat push lands on the wrong screen** for installed clients (they don't know the
`'새 메시지'` routing key). Wrong destination, not a crash.

---

## 4. Comprehensive next tasks

### 🔴 P0 — do these first

1. **Deploy the edge functions**, in the runbook order (`session-handoff.md` §3 ②–④):
   `create-booking-hold` → `collect-charges --no-verify-jwt` → `settle-run transition-booking
   confirm-payment`. **This is what makes `0085`/`0086` reachable and stops the still-live
   ₩0-to-runner bug.** The schema half is done; the deploy is stopped mid-runbook.
2. **Smoke a real signup and role-switch against production.** `0088`+`0091` are verified
   *applied*; nobody has verified *a human can sign up*. Those are different claims, and this is
   the one that would be a hard outage if wrong.
3. **Read the live `ops_flags.payments_live_since` row** with a credential that can see it. Every
   "charging is off" statement in every document is inferred from code. The announcer named the
   pattern precisely: *"I verify the code and then describe the world."*
4. **Ship an app build** — it fixes the empty catalog (fallback already written), teaches clients
   the chat routing key, and carries the launch-crash fix. ⚠ `app/ios/` is gitignored, so a clean
   checkout needs `pod install`; and `expo-updates` is configured but needs a prebuild + new
   binary before any OTA can reach anyone.

### 🟡 P1 — money correctness, before the cutover

5. **The fifth untested join, and it is live money.** `dispatch_due_charges()` (0080) and
   `isDue()` (`collect-charges/handler.ts:152`) are **one rule written twice** and have already
   drifted: SQL hardcodes `< 3` where TS imports `MAX_ATTEMPTS`; on an unparseable
   `next_retry_at` the SQL cast **raises** (outer handler returns 0 → the batch is never woken)
   while TS deliberately treats it as **due**; and the comment binding them points at
   `handler.ts:110` while `isDue` is at `152`. Neither side can pin the other and **both say so**.
   Fix shape: compute the rule once in SQL and have TS call it, or a differential test over shared
   fixtures (needs a `vault` stub in the harness shim — `116:161` names it as the first pin to add).
6. **⑪ two-sided incident verification** — RULED, unbuilt, unowned, next free `0094`/`130`.
   ⚠ **Correction to something this session claimed:** I said ⑫'s exit *is* ⑪'s machine. It is
   not. Sean said the **dog** is confirmed by both sides, which is `0083`'s return stamps
   (shipped) — not incident verification. `0092` shipped ⑫ alone and ⑪ remains independent.
   Before building it, resolve `incident-verification.md` §0: the App Store privacy answer
   declares phone purpose as *"contact during handoff"*, and ⑪ exposes numbers **during an
   incident**. **Has that questionnaire been filed?** And `profiles.phone` may be null in
   practice (PASS unintegrated) — `0062_runner_applications:380` suggests the real data is on the
   application, not the profile.
7. **The `ledger_items` re-anchor and `set_payments_live_since` hard refusals** — named as
   cutover gates in the handoff, still unbuilt.
8. **Club price-invisibility** — ruling ④ requires a **one-line disclosure** on the club payment
   surface before cutover (Sean's wording). The notification half shipped (`0084`), so club
   pricing is currently disclosed inconsistently between the app and its notifications.

### 🟡 P2 — the honesty class, which keeps producing findings

9. **Fix the class, not the instance — it has paid off every time.** Three sweeps found: a 50/50
   split nothing paid (fixed, `0085`), a fabricated `condition_note` on a second surface nobody
   had grepped (fixed), a report screen printing the quoted price as the charged one beside a
   support process that does not exist (fixed), a stop sheet stating the inverse of the billing
   rule (fixed), an ops alert naming a remedy that refuses its own case (fixed).
   **Still open:** the `n=0` copy shape — *"0개 코스의 만남 장소는 정해져 있고…"* is the **third**
   instance of a count interpolated into prose that assumes it is non-zero. Sweep for it.
10. **The spec-written-never-built class**, new today and with a cheap detector: `profiles.district`
    and `routes.town` are different vocabularies (overlap: one value of five), so an owner in 성수
    saw 0 courses against 13 real ones — **and the plan had already specified the fallback.**
    Detector: **when a plan says "falling back to X", grep for X.**
11. **A canonical launch-town list** — label + bbox as a code constant, booking town derived from
    pickup coordinates. Deliberately *not* auto-normalizing 뚝섬/서울숲 → 성수동: that is a
    geography judgement, not something code should invent.

### ⚪ P3 — process debt with named fixes

12. **Wire the guards into git.** `check-route-native-imports.mjs` and `check-rpc-contracts.mjs`
    are prose in `CLAUDE.md`'s commit gate, not hooks — `grep -c "check-" .githooks/pre-push` is
    **0**. And `deno test` is in no gate at all, so **four of the five cross-language contract
    pins run only when a human remembers.** There is no CI.
13. **The registry's third guard** — a claim with a row but no file, and no file elsewhere, is
    still invisible. `9a31b8d` named the patch and it was never written.
14. **Session identity is invisible in git.** 193 commits, one author, five sessions. A trailer
    naming the session would make every future retro sharper at zero cost.
15. **`docs/decisions/README.md`'s rule-3 corollary is falsified and still on origin** — it holds
    up "every build that has ever existed is compatible" as the exemplar of a good answer, and the
    `excluded.role` 403 disproved it the same afternoon. Correct it *in place* with the original
    preserved, the pattern `security-profiles-column-exposure.md` used: *"deleting it would leave
    the record tidy and the lesson gone."*

---

## 5. Where the decisions live, and how to read them

`docs/decisions/` — thirteen memos plus `README.md` (the index and the rules) and
`awaiting-sean.md` (his queue). **Read the status line, not the body** — and if you change a
memo, **change line 3 first**; that convention was broken twice today by the session that wrote
it. Every memo keeps its superseded recommendation *below* the ruling so the reasoning survives
and nobody "corrects" a ruling back toward a model's advice.

**Four standing rules, each earned by a failure the same day:**
1. **Unpushed reserves nothing — decisions included.**
2. **Quote the human, and mark where the quote ends.** An inference placed next to a ruling
   inherits the ruling's authority.
3. **Verify, don't relay — including a well-formed artifact.** A checklist that reads well, a
   green suite, a commit message, a code comment, and an announcer's broadcast all failed this.
4. **For irreversible actions, the session holding the human's word does it — and quotes him.**

---

## 6. Things I got wrong, so you don't inherit them

- **I published a retro asserting a causal arc I never checked.** Timestamps refuted it: the
  auto-resolver ate a claim **eight minutes before** the hook it supposedly emboldened existed.
  Corrected in place.
- **I claimed "not one defect was found by its author."** Wrong: 6 self-caught, 5 cross-session —
  and self-caught was *faster*. The real finding is that **reflexive review (turning a fresh rule
  on your own fresh work) has the highest yield**.
- **I asserted a grep result in a commit message without running it**, and cited an unmerged
  branch fix as shipped. Both rule 1 and rule 3, in one sentence, an hour after writing them.
- **I claimed ⑪ and ⑫ were one slice.** They are not — see task 6.
- **I left a new trigger function `anon`-executable**; the existing security sweep caught it.

**The pattern in all of them: precision without verification is indistinguishable from precision
with it.** None of these were vague. Vagueness gets questioned.

---

## 7. Coordination notes for a parallel session

- **Claim before you edit a shared surface**: `supabase/migrations/REGISTRY.md`, in-flight table,
  path-keyed, with `exclusive`/`shared` and **the tree named**. It cost ten seconds each time and
  would have prevented two duplicated hours.
- **Numbers come from that file, never from a message** — including a message from the announcing
  session, which was wrong three times.
- **Never auto-resolve a REGISTRY conflict by picking a winner.** Keep both rows and mark it.
- **Name temp harness dirs after your session, not the migration** — two sessions derived
  `/tmp/dr85` from `0085` and deleted each other's postmaster mid-run.
- **The harness cannot run from a worktree path longer than ~103 bytes** (unix socket cap). Copy
  `supabase/{migrations,tests}` to a short `/tmp` path. It is not a property of worktrees; it is
  103 bytes.
