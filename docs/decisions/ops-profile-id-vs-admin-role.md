# ③ OPS_PROFILE_ID — env var vs an admin role

**Status: ✅ RULED BY SEAN 2026-08-13 — "build for full scale, not just for pilot" →
option C, a dedicated `ops_recipients` table.** Being built in the charge-slice session.

> ⚠ Supersedes this memo's earlier resolution ("env var stays for the pilot"). That
> recommendation was pilot-sized reasoning; Sean rejected the framing, not just the
> option. Recorded so nobody restores the env-var-only answer by citing the analysis
> below.

## The ruling

`ops_recipients (profile_id, event_class, active)`. C beats B (`profiles.is_ops`) because
"full scale" is really about **routing**, not plurality: the charge machine already emits
four distinct marker classes (auto-cancel failure, retry exhaustion, dispatched-stale,
settled-without-payments) plus a comp-write failure, and at scale those don't all go to
the same person. The table lets one operator subscribe to money and another to safety
with no code change. The env var stays readable as a fallback **for exactly one release**,
so a mis-provisioned table cannot silence ops.

## What was already fixed and stays fixed, independent of this ruling

**The payload redaction (`f9f7be7`) is orthogonal and shipped.** Ops alerts carry no
financial detail: they say what happened and name `payments_reconciliation()` as where
the detail lives; identifiers stay in `console.error`. This closed a real disclosure —
`OPS_PROFILE_ID` is an env-held uuid and 0024 pushes notification bodies verbatim to a
lock screen, so a valid-but-wrong value put another customer's order number and ₩ amount
on a stranger's phone. Found by this session's adversarial round, fixed by the
charge-slice session. **It stays true under `ops_recipients`** — a routing table changes
who is notified, not what a wrong row would leak.

## Options as they were put

| # | Shape | Trade |
|---|---|---|
| A | Keep the env var (was shipped) | Simplest, one operator, no migration. A wrong/rotated id fails loudly but not visibly in-product. |
| B | `profiles.is_ops boolean` | DB-native, survives env drift. The column must be sealed from client writes or it's a privilege-escalation path, and it needs a pin. |
| **C** | **Dedicated `ops_recipients` table — RULED** | Cleanest for many operators + per-event-class routing. |

## Still open, and now more relevant under C

- **Reconciliation arm per marker class.** `payments_reconciliation()` had two arms
  (orphan_capture, stale_pending); the charge machine's newer marker classes need their
  own, each pinned to 0 rows on clean fixtures. Routing alerts to the right person is
  worth little if the class has no query behind it.
- **A heartbeat on the pull-based net.** Reconciliation is a manual query; nothing alarms
  if the habit lapses. A cron that loud-LOGS (never notifies — no dependency on the
  recipient table it would be reporting on) when the query returns >0 rows.
