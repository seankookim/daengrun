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
| Schema | ~~**DEPLOYED, `0001`–`0091`**~~ → **DEPLOYED, `0001`–`0094`, every row `local == remote`** | `supabase migration list` |
| Edge functions | ~~**NOT deployed.**~~ → **ALL FIVE DEPLOYED.** | `supabase functions list` + `functions download` + a redeploy from trunk |
| Charging | **OFF.** `payments_live_since` is NULL | ✅ **NOW OBSERVED, not inferred** — see below |

🔴 **Three of the four rows above were wrong, and the deploy session found it by running the
commands rather than reading them.** Corrected in place, with the originals struck through,
because the *shape* of the error is the reusable part:

- **"Edge functions NOT deployed" was false when it was written.** All five were deployed
  2026-08-13 at **16:57** (`collect-charges`, `--no-verify-jwt` intact) and **17:18** (the other
  four) — i.e. between the last commit this document cites and the document itself. The evidence
  it rests on is *"no commit, doc, or checklist records a deploy"*, which is an argument from
  the repo's silence about an action that leaves no trace in the repo. **A deploy is not a
  commit.** `supabase functions list` answers it in two seconds and was never run.
- **So `0085` and `0086` were already reachable.** `supabase functions download` shows
  `record_late_cancel_share` (0085's only caller) in the live `transition-booking` bundle and
  `compute_runner_personal_payout` (0086's) in `settle-run`. The "still-live ₩0-to-runner bug"
  in §3 ② and §4 P0 #1 had already been closed for hours. It is struck through below.
- **`0092` was NOT applied, while `0093` WAS** — `migration list` returned `0092` with an empty
  remote. So `0d143b8`'s *"⑫ status: BUILT AND DEPLOYED (0092)"* was true for `BUILT` only, and
  the deployed `transition-booking` bundle called just `is_slot_available` — no `runner_work_gate`.
  ⚠ **Deploying that bundle before `0092` applied would have 500'd every runner ACCEPT**, which
  is why order was checked before anything was pushed.
- **`payments_live_since` has now been read in the world.** P0 #3 is DONE:
  `supabase db query --linked "select * from ops_flags"` →
  `{"payments_live_since": null, "return_seal_since": null, "updated_at": "2026-08-13 07:57:02+00"}`.
  One row, both flags null. **Charging is off in production as a fact, not as an inference from
  the guards.** The retro's *"I verify the code and then describe the world"* is closed for this
  claim — and the tool that closes it is `supabase db query --linked`, which nobody had used;
  the session that got `[]` from an RLS-hidden table was reading through the anon key.
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

**② ~~`0085` and `0086` are deployed but unreachable.~~ CLOSED — and it was already closed when
this was written.** Both callers are in the live bundles (`functions download`, verified
2026-08-13 evening). The runner-gets-₩0 bug is not live. Kept struck through rather than deleted
because the reasoning was sound and only its premise was stale: *"their only callers are edge
functions, and none were deployed"* — the second clause was never checked against the API.

**③ The ops runbook silently changed.** `update routes set active = false` — the incident
vocabulary for 81 migrations — now **errors**. Replacement: `set status = 'suspended'`.

**④ A tapped chat push lands on the wrong screen** for installed clients (they don't know the
`'새 메시지'` routing key). Wrong destination, not a crash.

---

## 4. Comprehensive next tasks

### 🔴 P0 — do these first

1. ✅ **DONE 2026-08-13 (deploy session).** All five deployed from trunk in the runbook order
   ②–④, gates green first (tsc 0 · check-rpc ✅ · check-route-native ✅ · harness **539/0** ·
   deno **185/0**). **Exactly one function actually changed: `transition-booking`.** The CLI
   reported *"No change found"* for the other four — an independent confirmation, from a hash it
   computes rather than from a document, that the 16:57/17:18 deploy was already current. That
   makes `functions deploy` its own parity oracle: **run it, and "no change" is evidence.**
   Post-deploy verification, each observed rather than assumed:
   · the live bundle now calls `runner_work_gate` (re-downloaded and grepped)
   · the endpoint boots — `POST /transition-booking` with no auth → **401
     `UNAUTHORIZED_NO_AUTH_HEADER`**, not a 500 import crash
   · `runner_work_gate` on five real production runners → `{"gated": false}` ×5
   ⚠ **The gate was measured against production BEFORE it could bite**: 0 bookings match its
   predicate (`run_ended_at` set + `active`, or `incident_review`, with a return stamp missing,
   non-club) and 0 distinct runners. ⑫ went live gating nobody, which is the only reason this
   was a safe deploy rather than a decision for Sean.
   🔴 **Standing hazard it introduces, worth watching now that it is live:** the exit requires
   the OWNER's return stamp too, and `0089` made force ops-only. **An owner who simply never
   taps confirm blocks that runner from all future work until ops intervenes.** That is Sean's
   ruling working as written, not a defect — but it is the first gate in this system whose
   release depends on a counterparty's attention, and nothing pages ops when it fires.
2. **Smoke a real signup and role-switch against production.** `0088`+`0091` are verified
   *applied*; nobody has verified *a human can sign up*. Those are different claims, and this is
   the one that would be a hard outage if wrong.
3. ✅ **DONE 2026-08-13 (deploy session).** `supabase db query --linked "select * from ops_flags"`
   → one row, `payments_live_since` **null**, `return_seal_since` **null**, `updated_at`
   `2026-08-13 07:57:02+00`. Charging is off in the world, not just in the code. **The blocker
   was never permission — it was that nobody knew `db query --linked` exists**; it runs through
   the Management API as a login role, so RLS is not in the way. Use it for every future
   "what is actually true in production" question instead of reasoning from migrations.
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
