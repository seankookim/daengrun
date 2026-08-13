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

`app/app/owner/schedule.tsx:604` tells the owner, in the live cancel sheet (the
`store.ts:183` comment carrying the same words sits above the MOCK booking array — same
sentence, only one of them on a screen a user sees):

> `<24h confirmed → 10% (split 50/50 runner·platform); runner en route → 50%, ALL of it runner`

Only the **en-route 50%** tier writes a ledger row (`record_enroute_cancel_comp`, **0080 §K (0080:1119)**). The
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

- Mirror `record_enroute_cancel_comp` (**0080 §K**, 0080:1119): a `ledger_items` row for the runner, idempotent,
  written before the notification that claims it exists (0081's own lesson — never tell a runner
  compensation "was recorded" when the write failed).
- Split is 50/50 runner·platform, matching the copy that already ships.
- The notification is a reward, not an alert: name the fact that they held the slot.
- This does NOT change the owner's side — the fee and its ladder (0066) are unchanged.
- Pin it: a <24h cancel produces exactly one runner ledger row of the right amount, and the
  en-route tier still produces exactly one at the full fee.

**While you are in there, fix the CLASS, not just this instance.** This defect —
`schedule.tsx:604` promising the owner a 50/50 split that no ledger row backs — is the same class
as the fabricated `condition_note` found the same day (`run.tsx:444` sent a hardcoded
`'러너 판단: 컨디션 저하 관찰'` to every owner as the runner's own account of their dog):
**UI asserting a fact the system does not produce.** Both survived a long time for the same
reason — the copy was entirely plausible, so nobody read it against the code that would have
to make it true. Grep for other promises of that shape while the context is loaded: split
percentages, "정산됐어요"/"기록됐어요"-style confirmations, any sentence naming money or an
action whose backing write you cannot point to. A sentence the ledger cannot honour is a
honesty-doctrine violation regardless of whether anyone has complained about it yet.

---

## BUILT 2026-08-13 — `0085_cancel_share.sql` + suite `121`

`record_late_cancel_share(uuid)` pays the runner `round(cancel_fee * 0.5)` on the
`owner_cancel_late` tier. Gates: harness **467/0**, deno **161/0**, five mutations each
failing exactly its own pin. The shipped copy needed no edit — it is now true.

**The trap, measured before it shipped.** A 50/50 split invites recording the platform's
half in `ledger_items.platform_fee`, which reads as honest double entry. `my_ledger_total`
(0027:13) sums `base + distance_pay + addon_pay + tip + remaining_guarantee − platform_fee`,
so at 50/50 that nets the runner to **zero** — correct-looking row, correct amount, correct
count, no money. Pin S2 is the only one that fails under that mutation. The ledger is the
runner's ledger, not a double-entry book.

## The class sweep (the build note's "fix the class, not the instance")

Audited every user-facing money/state claim in `app/` against the write that would have to
produce it. **Split, percentage, commission, points, hold-expiry, club-ladder and
notification claims all came back BACKED** — the full clean list is in the audit. Four
instances of the class survive, none of them fixed by this slice:

| # | Claim | Verdict |
|---|---|---|
| A | `app/app/club/run/[sid].tsx:35` — hardcoded `note: '러너 판단: 컨디션 저하 관찰'`, rendered to the owner as **러너 노트** | **UNBACKED — this is literally the bug `611f014` fixed on `runner/run.tsx`, still live on the club surface.** The runner never types it; the owner reads a client constant as their runner's account of their dog. 0084:120-122 records a ruling that depends on this note being real. |
| B | `app/app/owner/report.tsx:387-391` — "결제 금액 {total_price}원" and "조기 종료 시 정산 조정은 고객센터를 통해 처리돼요" | **UNBACKED ×2.** The figure is the FROZEN PLANNED total, not what was charged (`compute_owner_charge` caps at `least(actual, km)` and drops base+addons for `runner_personal`) — so an early-ended run prints a number the owner was never billed, on the one screen they open to check what a run cost. And there is no 고객센터 surface anywhere in the client. |
| C | `app/app/owner/live.tsx:514` — "최소 기본요금 9,900원은 결제되며" | **UNBACKED.** 9,900 is `runnerCompBase`, the RUNNER's floor (ctx.ts:9-13 warns the two pots are different); the owner's base is 7,900 and `compute_owner_charge` never reads `min_fare`. Worse, `owner_request` charges **planned** distance (D2), so the sentence quotes a floor when only the ceiling will be billed. |
| D | same line — "러너에게는 잔여 거리 보장이 적용돼요" | **CONDITIONAL.** The guarantee is real only for `owner_request`/`owner_forced`; the owner's stop request never sets the end reason (it is a chat message + notification), and the runner then picks freely — 컨디션/개인 사유 pay bare actuals with `guarantee = 0`. |

**A is the finding that justifies the instruction.** The class-fix note existed because
`store.ts`'s 50/50 and `run.tsx`'s fabricated note were the same defect; the sweep then
found the *same* fabricated note on a second surface nobody had grepped. Fixing an instance
does not fix the class, and only a sweep tells you which.

Recommended order: **B** (wrong money figure + phantom process, most visible) → **C/D**
(one line, delete the min-fare clause and condition the guarantee) → **A** (mechanically
identical to a fix already shipped once — mirror `run.tsx`'s runner-typed field).
Each needs its own slice; none is in 0085.

### Post-merge review — one defect found and fixed (2026-08-13)

The charge-slice session reviewed the merged slice and found a real one: **both comp-failure
paths pinged `enroute_comp_failed`**, whose ops copy names `record_enroute_cancel_comp` — a
function that **refuses a late-tier booking by design** (0080:1137 gates on
`owner_cancel_enroute`). An operator following that remedy would run a no-op, mark the alert
handled, and the runner would never be paid: silent non-payment behind a green ops queue,
which is precisely the failure ⑩ exists to prevent. **A remedy that refuses by design is
worse than no remedy, because it closes the queue item.**

Fixed: a distinct `late_comp_failed` class naming `record_late_cancel_share`, plus a routing
pin that goes RED under the exact shipped defect (verified by reverting it). deno 162/0.

The class list lives in two places by design (`_shared/ops.ts` and 0084's `ops_recipients`
table comment); the TS half is functional and done, and the documentary half should pick up
`late_comp_failed` the next time a migration touches that comment — an unregistered class
routes to zero subscribers and correctly falls back to the env operator (0084 J6), so nothing
is broken in the meantime.
