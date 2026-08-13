# ⑩ The 10% cancel tier — pay the runner, and tell them

**Status: ✅ RULED BY SEAN 2026-08-13 — "pay the runner and let them know, reward them ykwim."**
**BUILT 2026-08-13 — `0085_cancel_share.sql` + `121_cancel_share_suite.sql` + the
`transition-booking/cancel_owner.ts` half, by `claude/club-delegation-money-gaps-b59eb8`.**

> ⚠ **This memo was handed to TWO sessions and built twice on the same afternoon.** The payments
> session (`claude/g1-ops-club-decisions`) built a complete second implementation before finding
> the first mid-flight, and yielded it whole; nothing of the duplicate ships. The reason it got
> that far is written here, at the top, because this line is where the second session would have
> looked: **the Status line of a decision memo is the only cross-session record of who is building
> it.** Claiming a migration number protects the number, not the work. See
> `supabase/migrations/REGISTRY.md`'s standing-conflicts section.

**Two corrections to the text below**, recorded rather than rewritten (both were true-enough
navigation aids that cost a reader time):
- `record_enroute_cancel_comp` is **0080 §K (0080:1119)**, not 0081. The same misattribution is in
  REGISTRY.md's shared-object table.
- the shipped 50/50 sentence a runner never saw the other half of is
  **`app/app/owner/schedule.tsx:604`** (the live cancel sheet). `app/src/store.ts:183` is a comment
  above the mock booking array describing the same policy — real, but not the screen.

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

**While you are in there, fix the CLASS, not just this instance.** This defect —
`store.ts:183` promising the owner a 50/50 split that no ledger row backs — is the same class
as the fabricated `condition_note` found the same day (`run.tsx:444` sent a hardcoded
`'러너 판단: 컨디션 저하 관찰'` to every owner as the runner's own account of their dog):
**UI asserting a fact the system does not produce.** Both survived a long time for the same
reason — the copy was entirely plausible, so nobody read it against the code that would have
to make it true. Grep for other promises of that shape while the context is loaded: split
percentages, "정산됐어요"/"기록됐어요"-style confirmations, any sentence naming money or an
action whose backing write you cannot point to. A sentence the ledger cannot honour is a
honesty-doctrine violation regardless of whether anyone has complained about it yet.
