# Handoff — the edge-function deploy session (2026-08-13 evening)

**Branch:** `claude/deploy-edge-functions-money-68e990` · 0 ahead / 0 behind trunk, clean, claim
released. Everything below is on `origin/redesign-v4` at `b3aab88`.
**Opener for whoever picks this up:** *"read docs/handoff-deploy-edge-functions.md, then
docs/session-handoff.md §3-ter."*

---

## 1. What is actually deployed — measured, so you don't re-derive it from git

`supabase functions list`, 2026-08-13 evening:

| function | version | `verify_jwt` | deployed |
|---|---|---|---|
| `create-booking-hold` | 8 | true | 17:18 |
| `collect-charges` | 1 | **false** ✓ (`--no-verify-jwt` intact) | 16:57 |
| `settle-run` | 14 | true | 17:18 |
| `transition-booking` | **33** | true | **17:42 — this session** |
| `confirm-payment` | 1 | true | 17:18 |

**Schema: `0001`–`0094`, every row `local == remote`.** Charging OFF —
`payments_live_since` **null**, observed with `db query --linked`, not inferred.

**Exactly one function changed in this session's deploy: `transition-booking` (v32→v33)**, which
picks up `0092`'s `runner_work_gate` call. The other four printed **`No change found in
Function: X`**.

> 🔑 **`functions deploy` is its own parity oracle.** That line comes from a hash the CLI
> computes against the live bundle, not from a document. Deploying five and getting four "no
> change" lines is a stronger statement about what is live than any handoff, and it costs one
> command. Use it instead of arguing from the repo.

---

## 2. Two runbook rules this deploy earned

**① Ordering is PER-RPC, not per-function.** `docs/session-handoff.md` §3 orders the five
functions; that is not enough. `transition-booking` calls `runner_work_gate` and throws
`HttpError(500)` on any RPC error — so deploying it while `0092` was unapplied would have **500'd
every runner ACCEPT**. Before deploying any function, check that every RPC it newly calls exists
in the remote. Now written into §3-ter.

**② `migration list` must be read row by row — an out-of-order gap is invisible at the tail.**
Found this evening: `0093` **applied**, `0092` with an **empty remote**, sitting *below* it.
Plain `supabase db push` applies **neither** (it only takes versions above the remote max) and
prints **"Remote database is up to date."** Anything that eyeballs the last row — or trusts that
message — concludes all is well. `0d143b8`'s *"⑫ status: BUILT AND DEPLOYED (0092)"* was true for
`BUILT` only. Another session applied `0092`+`0094` later that evening; the gap is closed, the
failure shape is not.

---

## 3. 🔴 The one thing that needs an owner and has none

**⑫'s work gate is live, and its release depends on a counterparty who has no reason to act.**

`runner_work_gate` (0092) blocks a runner from accepting new work until **both** return stamps
land, and `0089` made force **ops-only**. So:

> **An owner who simply never taps confirm blocks that runner from all future bookings until ops
> intervenes — and nothing pages ops when it fires.**

That is Sean's ruling working exactly as written (*"dont let them make new runs until the dog is
confirmed by both sides"*), not a defect. But it is the first gate in this system whose exit is
not in the blocked party's hands, and it is unmonitored. **It went live gating nobody** — measured
before deploying: 0 bookings and 0 runners match its predicate (`run_ended_at` set + `active`, or
`incident_review`, with a return stamp missing, non-club). That measurement is why this was a safe
deploy rather than a decision for Sean; it is not a guarantee about tomorrow.

**What it needs:** an ops alert on a gate that has been held more than N hours, routed through
`ops_recipients` (ruling ③, already built). Until then the only detector is a runner complaining.

---

## 4. Corrections to facts other documents assert

- **`ledger_items` is 8 rows, not 0.** §3 ⑦'s cutover gate re-anchors the sweep onto that exact
  table, so it is **not** the empty surface the plan assumes. Whoever builds the re-anchor and the
  `set_payments_live_since` hard refusals must handle existing rows.
- **The edge functions were never undeployed.** The handoff's P0 #1 and the retro's closing
  section both said `0085`/`0086` were unreachable and a cancelled runner was getting ₩0. False
  when written — both callers were already in the live bundles. Corrected in place in both files,
  struck through with the originals kept.
- **`payments_live_since` is observed, not inferred.** P0 #3 is closed. Money canary, read-only
  this evening: `payments` 0 · `billing_keys` 0 · `runs` ended 9 · `payments_live_since` null.
  ⚠ `sweep_settled_without_payments()` **mints** — never call it to observe a zero.

---

## 5. What remains

1. **Ship an app build.** The only thing that refills the empty course catalog (`0082` made
   `active` generated and its own backfill set every row to `candidate`; today's client carries
   the fallback). Also teaches installed clients the `'새 메시지'` chat routing key.
2. **Smoke a real signup + role-switch.** `0088`+`0091` are verified *applied*; nobody has
   verified *a human can sign up*. Different claims, and this is the one that is a hard outage
   if wrong.
3. **Tell the operator the runbook changed** — `update routes set active = false` now **errors**
   (`active` is generated); replacement is `set status = 'suspended'`.
4. **The ⑫ gate alert** (§3 above).
5. **NOT the cutover.** `payments_live_since` stays null; it is gated on Sean's
   사업자등록 → 통신판매업 → Toss chain, plus the `ledger_items` re-anchor and the setter's hard
   refusals. Being named for a deploy is not being named for the cutover.

---

## 6. The method note, which is the transferable part

**This repo has no habit of querying production, and it showed in every document.** Deployed
schema, deployed functions and live flag values were each described from the repo all day, by
five sessions, with two of the three descriptions wrong. Nothing here was carelessness — every
claim was precise, well-formed and confidently sourced, which is exactly why nobody re-checked it.

`docs/session-handoff.md` **§3-ter** now carries the four commands and the four traps. The one
that unlocked the rest: **`supabase db query --linked` runs as a login role and never meets
RLS** — so `[]` through the anon key means *hidden*, not *empty*. A session had already hit that
and correctly refused to count it as evidence; the answer was one flag away the whole time.

**The gap between "we can't check this" and "nobody checked this" is where this class lives.**
Every session that day landed on the first phrasing.
