# Ops dashboard — the read contract (trust ↔ ui)

**Owner of this document:** trust (`claude/deploy-edge-functions-money-68e990`).
**Status:** **v2 — RULED. Sean, 2026-08-15: _"B. a simple web build is fine."_** Standalone local
web tool on his machine. **§3's party-gated RPC is CANCELLED, not deferred** — no migration, no
number to claim, and `ops_gated_runners`/`ops_unsettled_runs` keep their service_role-only grants
exactly as `133 U5` pins them. The superseded design is kept below the ruling, per this repo's
convention that the reasoning must survive so nobody "corrects" a ruling back toward a model's
advice.
**Why it exists:** Sean commissioned a dashboard (2026-08-15, *"give me a dashboard with possible
solutions and etc all things necessary"*). The split agreed with announcer: **trust owns what is
true, ui owns what he sees.** This file is the seam. ui builds against THIS, never against the
tables — a contract in a chat message dies with the session.

---

## 🔴 0. WHAT THE RULING CHANGED — read this first

A standalone tool holds the **service key**, so it can call both detection functions directly and
needs none of the RPC machinery below. **§1 and §2 remain fully in force** — §1 explains *why*
there is no in-app option without new work, and §2 is the exact shape of what you call. **§3 is
dead** for this slice. **§4 (boundaries) and §5 (ui owns) stand unchanged.**

**And the whole security question moved.** With no client involved there is no party gate to get
right — instead there is a **service key on a laptop**, which bypasses every RLS policy in the
database. That is now the entire attack surface of this slice, and §8 is the blocking review.

## 1. Why there is no in-app version without new work: the app CANNOT call the detection functions

Measured against production, 2026-08-15:

| function | `anon` execute | `authenticated` execute | `service_role` execute | definer |
|---|---|---|---|---|
| `ops_gated_runners()` | **false** | **false** | true | yes |
| `ops_unsettled_runs()` | **false** | **false** | true | yes |

The app ships an **anon** key and a logged-in Sean is **`authenticated`**. Neither can execute
either function. **`supabase.rpc('ops_gated_runners')` from the client returns a permission
error, not data** — and it would fail at runtime, not at build time, which is exactly the seam
this repo keeps shipping ("each side's test replaces the other with a fake").

That is deliberate on `0097`'s part, not an oversight: suite `133 U5` pins these as
service_role-only, detection-only, no writes. **The fix is not to widen those grants** — it is a
separate, party-gated read RPC. Widening them would hand every logged-in user the full
unsettled-money picture.

## 2. What exists today, exactly (measured, do not re-derive)

```
ops_gated_runners()  → TABLE(runner_id uuid, booking_id uuid, status text,
                             gated_since timestamptz, waiting_on text, remedy text)

ops_unsettled_runs() → TABLE(booking_id uuid, runner_id uuid, status text,
                             run_ended_at timestamptz, unpaid_for interval,
                             both_confirmed boolean, escalated boolean, why text)
```

Both `security definer`, both `stable` (computed live — **no staleness, and no history**: a row
disappears the moment the condition clears and nothing records that it ever existed). `waiting_on`
and `remedy`/`why` are already human-facing strings chosen by `0096`/`0097` — **ui should render
them, not re-derive them.** If a rule lives in two places it drifts; that is this repo's fifth
untested join and it is still open on the money side.

`ops_recipients` (`0084`): `(profile_id, event_class, active, created_at)`, PK `(profile_id,
event_class)`, RLS on, no policies — server-only. **It is EMPTY today (0 rows).** The only
event class any shipped code passes is `owner_cancel_enroute` (`supabase/functions/_shared/ops.ts`);
`0096`/`0097` are pull-only and emit nothing.

## 3. ~~What trust will provide~~ — CANCELLED by the ruling, kept for the reasoning

⚠ **Everything in this section is superseded.** It was the right answer to "an ops screen inside
the app" and is the wrong answer to "a local web build". It is retained because if an in-app
version is ever wanted, this is the design and its rationale — the party gate raising rather than
returning empty is the part worth not re-deriving.

<details><summary>Superseded design (in-app, party-gated RPC)</summary>

### What trust would have provided (proposed — NOT built)

One RPC, because one screen should be one round trip and because the party gate must be
server-side:

```
ops_dashboard() → jsonb
```

- **`security definer`, `set search_path = public, pg_temp` in the body** (ALTER-applied config is
  reset by `create or replace` — measured; test 98 H1 fails the harness on any omission).
- **Party gate BEFORE state gate** (repo law): `auth.uid()` must be an `active` row in
  `ops_recipients`; anyone else gets `forbidden`, never an empty result. An empty result and a
  refusal must not look alike — an ops screen that silently renders nothing for an unauthorized
  caller is indistinguishable from "all clear", which is the worst possible failure for this
  screen specifically.
- **Granted to `authenticated` only.** Never `anon`.
- **Flat, whitelisted keys** — no `select *`, no row passthrough.

Proposed shape, one key per panel:

```jsonc
{
  "gated_runners":   [ /* ops_gated_runners() rows */ ],
  "unsettled_runs":  [ /* ops_unsettled_runs() rows */ ],
  "charge_machine":  { "payments_live_since": null, "payments": 0, "billing_keys": 0, "ledger_items": 8 },
  "generated_at":    "2026-08-15T…Z"
}
```

`generated_at` is not decoration: every panel is computed live at call time, so it is the only
thing that lets ui say *"as of"* honestly instead of implying a freshness it cannot know.

</details>

## 4. Boundaries — what trust will NOT do

Agreed with announcer, and they are hard lines:

- **No state-machine functions.** `runner_work_gate`, `confirm_return_tx`, the force paths and the
  `0083`/`0087`/`0089`/`0092`/`0094`/`0096` lineage are **custody's**, dormant or not. This slice
  reads; it does not change what a gate means.
- **No money movement.** `charge_machine` is counters only. `sweep_settled_without_payments()`
  **mints** — it is never called to observe a zero.
- **No widening of `ops_gated_runners` / `ops_unsettled_runs` grants.**
- **Nothing in `app/`.** That is ui's, entirely.

## 5. What ui owns

Everything visual, plus these product calls trust should not make:

1. **What "possible solutions" means per row.** `remedy` and `why` are server strings; whether the
   screen turns them into a button, a link, or prose is ui's.
2. **Whether a blocked pair is actionable in-app.** `0089` made force ops-only, so the remedy for
   a stuck gate may be "contact them", not a tap.
3. **Empty vs zero.** Repo honesty law: loading is not 0, and a failure renders as a failure.
   `gated_runners: []` means *measured, none* — it must not look like *not loaded*.

## 6. Open questions for ui

1. ✅ **RULED — standalone local web build** (Sean, 2026-08-15: *"B. a simple web build is fine."*).
   Was: *does the dashboard live in the app or outside it?*
2. **Do you need history, or is "right now" enough?** Both functions are live-computed with no
   record. History means a table and a writer — a materially bigger slice, and it belongs to
   whoever owns retention, not to this one.
3. **Is `charge_machine` wanted at launch?** It is inert until cutover (`payments_live_since` is
   null, measured) and a panel of zeros may read as broken rather than as *not started*.

## 7. Gate

The RPC is a migration touching a security-definer function and a party gate, so: `/autoplan`
first (`0059` doctrine), number claimed in `REGISTRY.md` **on origin** before the file is written,
suite with mutation-verified pins, harness green at its new baseline. **Reviewer is money or a
fresh adversarial subagent — not me.** I normally hold blocking review on this surface, and a
reviewer who also built the thing is not a reviewer.


---

## 8. 🔴 KEY HANDLING — trust's blocking review for the standalone tool

**This is the whole of my review scope for this slice, and it is blocking.** Stated up front so
ui builds against it rather than being vetoed late.

**The stake, plainly:** the `service_role` key **bypasses every RLS policy in the database**. It
is not "an admin key for ops tables" — it reads and writes `profiles`, `payments`, `billing_keys`,
everything. A leak of it is total compromise of production data, and unlike a password it cannot
be rotated without touching every server that uses it.

Requirements, each of which fails the review on its own:

1. **The key is NEVER in the page.** Not a JS constant, not inlined at build time, not a
   `data-` attribute, not a comment. Anything in the page is readable by anyone who opens
   devtools or the file — and the page is on a laptop that goes to cafés.
2. **A local server process holds it, read from the environment at start** (`process.env.…`).
   The browser talks to that process; only the process talks to Supabase.
3. **Bind `127.0.0.1`, never `0.0.0.0`.** A service key behind a `0.0.0.0` bind is on every
   network the laptop joins, including hotel wifi. This is the single most likely mistake.
4. **The key is never logged, echoed in an error, or returned in a response.** Error handlers
   included — a stack trace with a config dump is the classic leak.
5. **No secret in the repo.** The key lives in an ignored env file; `git check-ignore` it before
   the first commit, not after.
6. **Fixed queries only — no user input reaches a query.** With a service-role key there is no
   RLS backstop, so an injection is not "read someone else's row", it is the whole database.
7. **Respond with the whitelisted panel keys only** (§3's shape is still the right *response*
   shape even though its RPC is cancelled). Never raw passthrough of a query result.

**How I will review it:** by reading the process boundary and by executing — `curl` the tool from
a second device on the same network and confirm it refuses, and grep the served page for the key
prefix. Not by reading a description of the design. **Bring it to me before it runs against
production**, and note that requirement 3 is the one that is invisible in code review and obvious
in one command.
