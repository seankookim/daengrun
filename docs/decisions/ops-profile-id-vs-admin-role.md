# OPS_PROFILE_ID — env var vs an admin role in the DB

**Status: ADOPTED — A (env var stays), 2026-08-13; the hardening question is
RESOLVED by payload redaction.** Sean delegated the call to this memo's
recommendation in the club-delegation session (/autoplan). The adversarial round
confirmed the memo's honest weakness as a real vulnerability, and the charge-slice
session fixed it (commit f9f7be7 on its branch) — differently and better than this
memo's original C proposal. Recorded here as the resolution of record.

## The question

Ops alerts (auto-cancel failure, and now the charge machine's exception classes) are
delivered as a `notifications` insert to the profile id in the `OPS_PROFILE_ID` env
var. Should the recipient instead be defined in the database (an admin role/flag)?

## Resolution

**A — env var stays for the pilot.** Zero migration; per-environment by nature;
matches reality (ops = Sean). Setup is a launch-checklist item (§2): unset = loud
log only, and the reconciliation machinery — 4-arm in 0080, plus the 15-min
verification arm in collect-charges — is the actual safety net, not the
notification.

**The wrong-uuid hole: CONFIRMED and FIXED by redaction, not recipient validation.**
The adversarial round's finding was real: a valid-but-WRONG uuid delivered another
customer's order number and ₩ amount to a stranger's lock screen (0024's trigger
pushes the notification body verbatim, with sound). Fix shipped in the charge-slice
session (f9f7be7): **ops alert payloads carry no identifiers** — they say what
happened and name `payments_reconciliation()` as where the detail lives; order ids
and amounts stay in `console.error`. Pinned so it can't creep back.

This supersedes the two validation shapes this memo previously floated:
- *Existence validation* was a placebo — `notifications.profile_id` already has an
  FK; a dangling uuid fails loudly today.
- *OPS_EMAIL cross-check* was rejected by the charge-slice session with a reason
  this memo accepts: a second env var that must ALSO be right just moves the
  question. Removing the sensitive payload removes the harm class instead of
  guarding its delivery.

**B (admin role / ops_recipients) trigger, unchanged:** when a second operator
exists, the right shape is an `ops_events` queue (dedupe, severity, ack/resolution)
— not a recipients table bolted onto customer notifications. Recorded so B doesn't
get built as the wrong table later.

## Still open for the next money slice

- **Heartbeat on the pull-based net:** reconciliation is a manual daily query by one
  person; nothing alarms if the habit lapses. A cron that loud-LOGS (never notifies
  — no dependency on the same env var) when `payments_reconciliation()` returns
  >0 rows. ~10 lines, rides any ≥0082 migration.
- Launch checklist §2 carries the env setup item (`supabase secrets set
  OPS_PROFILE_ID=...` per environment; also listed in handoff deploy order ⑥).

## Decision (Sean)

- [x] A — env var stays for the pilot, with redacted ops payloads (shipped) —
      **ADOPTED 2026-08-13 via delegation**
- [ ] B — `ops_events` queue when a second operator exists

Why: solo operator; the safety net is reconciliation, not the notification — and
with redacted payloads a misconfigured recipient can no longer leak money data.
