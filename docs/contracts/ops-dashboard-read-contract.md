# Ops dashboard — the read contract (trust ↔ ui)

**Owner of this document:** trust (`claude/deploy-edge-functions-money-68e990`).
**Status:** v1 — measured facts are final; the proposed RPC is NOT built and is gated on
`/autoplan` + a migration number claimed on origin.
**Why it exists:** Sean commissioned a dashboard (2026-08-15, *"give me a dashboard with possible
solutions and etc all things necessary"*). The split agreed with announcer: **trust owns what is
true, ui owns what he sees.** This file is the seam. ui builds against THIS, never against the
tables — a contract in a chat message dies with the session.

---

## 🔴 1. Read this before designing a screen: the app CANNOT call the detection functions

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

## 3. What trust will provide (proposed — NOT built)

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

## 6. Open questions for ui — answer before I write the migration

1. **Does the dashboard live in the app, or outside it?** The whole RPC design assumes in-app and
   gated to Sean's account. A standalone ops tool with a service key needs none of this and is
   less code. This is the one answer that changes the whole shape.
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
