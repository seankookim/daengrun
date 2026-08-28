# Codex review — the card/billing chain (0137–0150) + its two edge functions

**Date:** 2026-08-28 · **Reviewer:** codex `gpt-5.6-sol` @ `xhigh`, read-only sandbox
**Verdict: REJECT · 7 findings** (2 MEDIUM, 5 HIGH)
**Frozen at:** `719d2d5` — `git archive` export, `git init`'d so codex would read it
**Raw log:** not committed (13 KB stdout / 578 KB stderr); reproduce from
`docs/reviews/2026-08-28-codex-billing-chain.prompt.md`

This is the first review the card chain has ever had. It was flagged in the 2026-08-27 handoff as
「the largest concentration of unreviewed risk in the repo」 and that turned out to be right.

⚠ **Everything here is LATENT.** `payments_live_since` and `card_registration_live_since` are both
NULL and there are 0 billing keys, so none of it fires today. Findings 3 and 4 arm on the
**registration** flag alone — charging does not have to be switched on.

---

## How the run was verified as real

Per `CLAUDE.md` §codex, a run is done when a verdict **value** is in the artifact, never on exit
status or log size. Detector used: `grep -cE '^FINDINGS: [0-9]+'` → **1**. The prompt contains the
literal `FINDINGS: <n>`, which cannot match a digit, so the echo is excluded **by construction**
rather than by remembering to exclude it. Both detectors were run against the prompt file itself
before launch and returned 0. Streams captured separately; `usage limit` and
`not inside a trusted directory` both checked positively and both absent.

---

## The 7 findings

| # | Sev | One line | Fires when |
|---|---|---|---|
| 1 | HIGH | An 8th-attempt worker crash strands the row **before its own cleanup can run** — expired lease, live token, `processing` forever | registration flag on + a revocation reaches attempt 8 |
| 2 | HIGH | The health view reports a **clean queue after revocation has given up** | registration flag on |
| 3 | HIGH | Issuance has **no durable record before Toss is called** — a lost response leaves a live provider credential in neither `billing_keys` nor the queue | registration flag on |
| 4 | HIGH | Ambiguous swap compensation can **revoke the key it just stored** — Postgres says K is current, Toss has destroyed it | registration flag on |
| 5 | HIGH | `cron.schedule` failure is swallowed by `WHEN OTHERS` into a NOTICE — **a failed install reports as a successful migration** | at apply, in any env where scheduling fails |
| 6 | MED | No uniqueness on outstanding rows — the **same key can be DELETEd twice**, and a false `abandoned` obligation can result | registration flag on |
| 7 | MED | The unauthenticated cron endpoint compares its secret with **ordinary `!==`**, not a constant-time check | once `CRON_COLLECT_KEY` is set |

Finding 2 deserves its own sentence because it is the shape this repo keeps meeting: **the one
dashboard-shaped object in the family reports the queue clean precisely because rows were given up
on.** `due_now` counts `pending` and expired-`processing` **with `attempts < 8`**, so it
structurally excludes every `abandoned`, `failed`, `done` and cap-stuck row. The 2026-08-27 handoff
had already found this by hand; codex found it independently, cold, and located the second half —
the worker returns HTTP 200 and reconciliation **discards `failed`, `revoked` and `stale`**.

### What codex cleared, explicitly

Worth recording, because a review's negatives are evidence too and they are the part nobody quotes:

- **The token audit passes.** Every final decision site clears the claim token (0148:110-118,
  0149:44-50, 0149:57-65, 0141:141-152), so a late worker report **cannot** flip `abandoned` → `done`.
  The surviving hole is finding 1 — the cap decision that may never execute at all.
- **`billing_key_swap`'s widened `swapped=false`** (it gained `gate_closed` and `key_busy` on top of
  deletion) has exactly one runtime consumer, and it maps all three distinctly
  (`register-billing-key/handler.ts:234-261`). **No widened-boolean consumer defect survived** —
  which is the defect class `CLAUDE.md` §④ was written about, checked and found closed here.
- No missing body-level `search_path`, no same-file definer-ACL gap, no dropped view, no `select *`,
  no direct client enqueue hole.

---

## Production verification — 3 of codex's 5 open questions, CLOSED

Codex said these could not be settled from source. They can be settled from the database, and this
is the pairing `CLAUDE.md` prescribes: **codex reads cold, an executing agent measures.** All reads,
no writes.

### ✅ OQ4 — "source cannot confirm the cron job exists or is monitored" → IT EXISTS AND RUNS

```
cron.job    jobid 23 · revoke-billing-keys · '8-58/10 * * * *' · active = true
cron.job_run_details   110 runs, ALL succeeded, latest 2026-08-28 00:48 UTC
```

🔴 **This narrows finding 5 from breached to latent, and the distinction is the whole point.**
Codex's *reasoning* is right — `WHEN OTHERS` genuinely converts a failed `cron.schedule` into a
successful migration, and that is a real defect worth fixing. But its *impact sentence* —
「nobody invokes the dispatcher; pending keys remain live indefinitely」 — is **false of this
deployment**: the schedule installed and has run 110 times. It is true of any environment where
scheduling fails, which is exactly what the swallow makes invisible. Same shape as `0121:240`'s
definer: **latent, not breached, because the creating migration happened to succeed.**

### ✅ OQ2 — effective base-table ACLs → SEALED, BUT ASYMMETRICALLY, AND THAT IS A NEW FINDING

| table | RLS | policies | anon SELECT | auth SELECT | auth INSERT |
|---|---|---|---|---|---|
| `billing_key_revocations` | on | 0 | **false** | **false** | **false** |
| `billing_keys` | on | 0 | **true** | **true** | **true** |

Codex called raw access 「effectively sealed」 and **that conclusion is correct** — RLS on with zero
policies is fail-closed by construction. But the two siblings get there by different numbers of
mechanisms. `billing_key_revocations` was explicitly revoked (0138:44-49) **and** has RLS.
`billing_keys` has **only** RLS.

**So `billing_keys` is protected by one mechanism where its sibling has two, and the grants are
already sitting there.** The day anyone adds a policy to `billing_keys` for a legitimate reason —
「let a user see their own card」 is an obviously reasonable future ask — the SELECT and **INSERT**
grants arm with it, with no code change and nothing that fails. Same sentence as the `net` grant in
the 2026-08-27 handoff: **removing the grant converts 「protected by a setting」 into 「protected by
not being granted」.** Hygiene, not an incident — and it belongs to the next slice that touches this
family, not to a churn migration.

⚠ **HONEST LIMIT ON THE MEASUREMENT, and it is the trap this repo has already been bitten by.**
I also ran the reachability test — `set local role anon; select count(*) from billing_keys` → 0,
with a control (`set local role anon; select count(*) from clubs` → **1**, so the role switch
demonstrably works). **That 0 licenses nothing.** `billing_keys` has **0 rows**, and an empty table
returns 0 to every role alike; the read cannot distinguish 「RLS denied me」 from 「there was nothing
to see」. The fail-closed conclusion rests on **RLS-with-zero-policies**, not on that query. Recorded
because 「a table populated only during an operation cannot be assessed by looking at it between
operations」 is already a law here, and it applies to a table that is empty for any reason.

### ✅ OQ1 — `net.http_request_queue` reachability → ALREADY SETTLED, do not re-derive it

The dispatcher does place the cron key in pg_net's request headers (0150:354-357). The privilege
half is real and the reachability half is already measured, on 2026-08-27, in `CLAUDE.md`:
`anon` holds `USAGE` on `net` and `SELECT` on `net._http_response` **and**
`net.http_request_queue` — **and PostgREST exposes only `public, graphql_public`**, so the anon key
gets `406 PGRST106` on `net` against a `200` control on `public.clubs`. **A needless grant behind
one config line, not a live exposure.** It is 🔴 OPEN item 6 in the handoff and needs Supabase
support, because `net` is owned by `supabase_admin` and REVOKE only removes grants issued by the
current role (0151 aborted itself proving exactly this).

### ⬜ STILL OPEN — the two that need someone who is not us

- **Toss issuance replay.** Findings 3 and 6 both bottom out in one question codex could not answer
  and neither can I: *can Toss replay or look up a billing-key issuance by a persisted idempotency
  key, and what does a repeated DELETE return?* That answer **decides the recovery protocol** for
  both. It is a provider-documentation / provider-support question, and it is a prerequisite for
  turning card registration on — not a thing to design around by guessing.
- **Edge-instance affinity between `prepare` and `issue`.** The registration nonce is isolate-local
  memory. Without affinity, valid flows fail as `stale_attempt`. Unresolved from source; needs a
  Deno-deploy behaviour answer or a durable nonce.

---

## What I recommend, in order

1. **Nothing here blocks anything today** — both money flags are NULL. Do not treat this as an
   incident.
2. 🔴 **Findings 3 and 4 must close before `card_registration_live_since` is ever set.** They arm on
   the registration flag alone, they both produce a real card in a wrong state, and they both depend
   on the Toss replay answer above. **That provider question is now on the critical path to
   launching card registration** — it is the thing to ask first, because the fix shape is unknown
   until it is answered.
3. Findings 1, 2, 6 are queue-integrity and observability; they want one slice together, since 1 and
   2 are the same row seen from two ends (the row that strands, and the dashboard that hides it).
4. Finding 7 (constant-time compare) is small, self-contained, and worth doing now — the endpoint is
   live and reachable today even though the queue is empty.
5. Finding 5's fix is one line of intent: let the schedule failure abort. The 110 successful runs
   mean there is no urgency, only a trap for the next rebuilt environment.

## What is still unreviewed

This review covered the **billing/revocation** chain. The 2026-08-27 handoff counted **52 slices
landed that day labelled NOT REVIEWED**; the club-session chain (0134, 0136, 0142, 0144, 0146,
0147), 0152, and the client half of all of it have **still had no codex pass**. One review found
seven things. The remaining set has had none.
