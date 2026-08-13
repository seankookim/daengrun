# ⑩ The 10% cancel tier — pay the runner, and tell them

**Status: ✅ RULED BY SEAN 2026-08-13 — "pay the runner and let them know, reward them ykwim."**
**Unbuilt.**

## The defect this fixes

`app/src/store.ts:183` tells the owner, in the cancel sheet:

> `<24h confirmed → 10% (split 50/50 runner·platform); runner en route → 50%, ALL of it runner`

Only the **en-route 50%** tier writes a ledger row (`record_enroute_cancel_comp`, 0081). The
**<24h 10%** tier writes nothing. So today a cancel twelve hours out charges the owner ₩1,690
on a 3km booking, the platform keeps all of it, and the runner who held that slot — and who
the app has just told the owner is being compensated — receives nothing, and is never told the
cancellation happened as a money event at all.

That is margin resting on a false sentence. It was surfaced by building the full scenario
table, not by a bug report, because nothing in the system contradicts itself loudly enough to
notice: the copy is in the client, the ledger write is in SQL, and neither knows about the other.

## The ruling

**Pay the runner their half, and notify them as a positive event.** Sean's framing — "reward
them" — is the design instruction, not just the payment instruction. A runner who kept an
evening free and lost it should hear that they were compensated for holding it, in the voice
the product uses for good news, not as a silent ledger line they might find later.

## Build notes

- Mirror `record_enroute_cancel_comp` (0081): a `ledger_items` row for the runner, idempotent,
  written before the notification that claims it exists (0081's own lesson — never tell a runner
  compensation "was recorded" when the write failed).
- Split is 50/50 runner·platform, matching the copy that already ships.
- The notification is a reward, not an alert: name the fact that they held the slot.
- This does NOT change the owner's side — the fee and its ladder (0066) are unchanged.
- Pin it: a <24h cancel produces exactly one runner ledger row of the right amount, and the
  en-route tier still produces exactly one at the full fee.
