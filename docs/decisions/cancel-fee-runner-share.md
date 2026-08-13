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
