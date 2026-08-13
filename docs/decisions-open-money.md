# Open money decisions — briefs for Sean (2026-08-13)

> ⚠ **CONSOLIDATION PENDING — read `docs/decisions/` first if it exists on your branch.**
> A parallel session wrote the same three memos (①–③) as `docs/decisions/*.md` on branch
> `claude/club-delegation-money-gaps-b59eb8`, and reports you delegated the calls there.
> That set is agreed to be canonical; THIS file folds into it and retires once you confirm.
> Both sets reach the same recommendation on all three. Differences worth knowing before
> you read either: their G1 memo has the exact absorption formula and a sharper fraud
> framing (a waived owner never disputes a fabricated abort — the waive removes the free
> fraud detector); this file has the one thing theirs lacks — that `incident` must stay ₩0
> **at settle** under every option, for an architectural reason and not a generous one
> (0072's incident settlement owns that money question; charging at settle pre-empts the
> case and manufactures the refund post-pay deleted). Memos ④/⑤ below are club-specific and
> exist only here.
> **Nothing has been built on the relayed adoption.** G1 keeps its 🔴 provisional marker and
> D-3 is unbuilt; per the protocol both sessions agreed on, your review+merge is the
> confirmation.

Written after the charge slice landed (0080). Each memo: **what is shipped today**, the
options, what each costs, and a recommendation. Sean picks by number; a one-line answer per
memo is enough. Nothing here blocks the code that exists — every item has a recorded
provisional that is live right now — but items ①/② gate the `payments_live_since` flip.

---

## ① G1 — what does an ABORTED run charge the owner? (the last basis-table hole)

**Shipped provisional:** `dog_condition` and `incident` both charge **nothing**
(`compute_owner_charge` rule `g1_waive`, a `waived` payments row with amount 0). The runner
is still paid normally by `settle_run_tx` — the platform absorbs it. Grep handle: `g1_waive`.

**Context.** The basis table already decided everything else: completed and runner-caused
early ends charge actuals; owner-caused ends charge the planned distance (D2, anti-gaming);
`runner_personal` charges distance only, no base (the owner shouldn't pay a base fee for
service the runner ended). Two `end_reason` values were left to you:
- `dog_condition` — the runner stops because the dog is limping, overheating, panicking.
  Requires a `condition_note` (server-enforced), so every one of these leaves a written record.
- `incident` — written by the custody/emergency path (0045), not by a runner's normal
  settle. An incident already has its own money machinery: `club_incident_settle` (0072)
  quotes `refund_full | settle_measured | pay_full` and a human decides.

**Options**

| # | Rule | Owner pays (0.8km of a 3km run) | Consequence |
|---|---|---|---|
| A | **Charge nothing** (shipped provisional) | ₩0 | Maximum trust. Platform absorbs the runner's full pay every time. Repeatable: an owner with a chronically unfit dog gets free runs indefinitely, and nothing in the system notices. |
| B | **Distance only, no base** (mirrors `runner_personal`) | ₩2,400 | Owner pays for the distance that actually happened; the ₩7,900 base is absorbed. Small enough never to punish a welfare stop, real enough that repeat aborts aren't free. Tiny aborts auto-waive anyway (the `below_pg_minimum` <₩100 arm). |
| C | **Full actuals** (base + distance) | ₩10,300 | "Pay what happened." Risks the thing we least want: an owner who feels charged for a stopped run pressures the runner to keep going next time. |
| D | **Split by cause** — `dog_condition` = B, `incident` = A | ₩2,400 / ₩0 | Treats the two differently because they *are* different: one is a judgment call about the dog, the other is a case under review. |

**Recommendation: D.**
- `incident` → charge nothing **at settle time**, because the charge decision belongs to the
  incident review that already exists (0072). Charging at settle would pre-empt the case and
  create a refund we'd then owe — exactly the refund machinery post-pay deleted.
- `dog_condition` → distance-only (B). A welfare stop must never cost the owner a base fee,
  or the incentive points the wrong way; but a completely free outcome puts unbounded,
  invisible cost on the platform for a case that recurs with the same dogs.

**⚠ Related gaming vector, independent of your answer (flagging, not fixing):**
`completion_rate` counts only `completed` + `runner_personal`, so `dog_condition` is
currently a stat-free early exit for a runner. Under option B or C the runner is also paid
actuals with no completion-rate cost. If aborts cluster on particular runners, that's the
signal to watch — a per-runner abort-rate metric is the cheap countermeasure, not a
price change.

---

## ② D-3 — is charging with no in-app confirmation OK? (needs counsel, not engineering)

**Shipped today.** Price is shown once on the request screen; the card is linked once (that
flow is a later slice); after the run the charge fires silently. The owner learns from the
card issuer's own 승인 알림. Receipts live in 설정 → 결제 관리 and in the booking detail's
결제 내역. Failures/debt/lock states are loud. No 전자상거래법 business-info footer exists
yet — deliberately omitted rather than faked, because the numbers don't exist until
사업자등록 lands.

**The question for counsel** (not for us to guess): in Korea, for a marketplace charging a
saved card after service on server-computed actuals, is one-time consent at card link +
price disclosure at booking + on-demand receipts sufficient, or is a per-charge notice
required? Specifically worth asking: 전자상거래법 정보 제공 duties, 여신전문금융업법 around
자동결제 disclosure, and whether the 자동결제 심사 itself imposes notification terms.

**Options if counsel says more is needed**

| # | Response | Cost |
|---|---|---|
| A | Accept as-is (shipped) | Zero. Depends entirely on counsel agreeing. |
| B | Per-charge push ("러닝 이용료가 결제됐어요") | Small (one notification insert in the charge path). Costs the Kakao-T invisibility you deliberately chose. |
| C | Monthly summary notification | Small-medium (a cron + a summary surface). Keeps invisibility per-run, satisfies a "the user must be told" reading. |

**Recommendation:** ask counsel with the three options in hand; if the answer is ambiguous,
ship **C** — it preserves the doctrine and is defensible, whereas B trades away the exact
psychology the token model was abandoned in favor of. Do not ship B by default out of
caution; that is the invisible-cost version of a legal decision.

**Hard dependency either way:** the 전자상거래법 footer (사업자 정보 + 통신판매업 신고번호)
must appear on the payment surfaces the day those numbers exist. That is a legal
requirement of the screen, not a design choice — it is already noted in the plan §3.

---

## ③ OPS_PROFILE_ID — env var vs an admin role

**Shipped today.** `confirm-payment` and the cancel-fee comp path notify an operator by
inserting a `notifications` row for `Deno.env.get("OPS_PROFILE_ID")`. If the env var is
unset, the code does **not** fail silently — it `console.error`s loudly, and the real
consumer of those events is the `payments_reconciliation()` query (plus, since the charge
slice, its new `ladder_exhausted` arm). The notification is speed, not the safety net.

**Options**

| # | Shape | Trade |
|---|---|---|
| A | Keep the env var (shipped) | Simplest. One operator only. A wrong/rotated profile id fails loudly but not visibly in-product. Changing it needs no migration. |
| B | `profiles.is_ops boolean`, notify every ops profile | DB-native, survives env drift, supports a second operator later. Requires care: the column must be sealed from client writes or it is a privilege-escalation path, and it needs a pin. |
| C | Dedicated `ops_recipients` table | Cleanest for many operators + per-event routing. Overbuilt for a one-person pilot. |

**Recommendation: A for the pilot, revisit at the second operator.** The failure mode the
env var has (unset → no push) is already covered by the reconciliation query, which is the
thing an operator is supposed to read daily. B's real cost isn't the column, it's another
sealed-surface pin to maintain for zero present benefit. Revisit the moment someone other
than you needs to see ops events — that's the trigger, not a date.

---

## ④ club_fare — should a club owner pay ₩9,900 base when a marketplace owner pays ₩7,900?

**Shipped today, unchanged by the club money-gates slice (0081).** `club_fare(km) = 9,900 +
round(km × 3,000)` (0043:14) is the single price source for every club surface: the ticket
cell, the board, the 승인 알림 ("20분 안에 결제하면 자리가 확정돼요 · N원"), and the booking
`session_pay_delegation` writes. The marketplace owner base has been **₩7,900** since the D2
decoupling (owner 7,900 / runner 9,900); that change swept the TypeScript constants under tsc
pressure and could not reach this SQL function. Consequence, at a 5km route:

| | base | distance | owner pays |
|---|---|---|---|
| marketplace | 7,900 | 15,000 | **22,900** |
| club 위탁 | 9,900 | 15,000 | **24,900** |

**This is not a bug, and specifically not a quote-vs-charge bug.** The booking's decomposition
is internally consistent — `9,900 + (club_fare − 9,900) + 0 = club_fare` — so 0080 §D, which
charges from those frozen columns, bills a completed club run *exactly the quote the owner
saw*. Nothing is mispriced against itself. What differs is the **cross-product** price: the
same dog, the same distance, ₩2,000 more inside a club session. 0081 K7 pins the
decomposition, so whichever way you rule, the parts and the total can no longer drift apart.

**Options**

| # | Rule | 5km owner price | Consequence |
|---|---|---|---|
| A | **Keep 9,900, deliberately** (shipped) | 24,900 | Reframes the gap as a group-logistics premium: a host coordinates, a runner takes 2 dogs, there is a 집결지. Costs nothing to ship. Risk: it is currently a premium nobody ever decided or explained, and the first owner who books both ways will ask. |
| B | **Align to 7,900** — one owner price everywhere | 22,900 | The simplest sentence a product can have ("보호자 요금은 하나"). ₩2,000 per club run off the top line; club runs are the ones with the *most* platform cost (host coordination, capacity, incidents). One-line change to `club_fare` + K7/50 D5's literals. |
| C | **A separate published club price** (e.g. 8,900 base, or per-dog banding) | your call | Makes the premium a stated product fact instead of an artifact — but it needs a surface that explains it, and today no club screen has a "why is this more" line. |

**Recommendation: B — align to 7,900, and do it before the cutover, not after.**
Three reasons. ① The gap is not a decision anyone made; it is 0043 fossilising the pre-D2
constant, and shipping an unintended premium into *real* charges is a worse first impression
than the ₩2,000 is worth. ② Club is the acquisition surface (the pilot's growth loop is
sessions, not solo runs) — the wrong direction to be the expensive one. ③ Post-cutover the
change gets harder in a way it is not today: bookings freeze their fare columns at creation,
so after the flip you would have two live prices in the wild for weeks, and every support
conversation would need the history. Before the flip, nothing has been charged, so the
correction is invisible.
If you take A instead, the honest form of A is a one-line disclosure on the club payment sheet
("클럽 위탁은 기본요금이 달라요") — an undisclosed premium is the version that costs trust.
**Whatever you pick, no code moves until you say so:** 0081 ships the gates and leaves the
formula untouched; the change, when it comes, is `club_fare`'s literal plus the 24,900
literals in `117 K3/K7` and `50 D5`.

**Related, not part of this decision:** club cancel fees are structurally uncollectable
post-cutover (they land in `club_fee_items`, never `bookings.cancel_fee`) — that one is
written up at the end of memo ⑤, and it is a separate ruling from this price.

---

## ⑤ Should a club booking be cancellable once the runner is en route?

**Shipped today (2026-08-13, this session).** The marketplace cancel path now REFUSES club
bookings (`cancel_owner`, mirroring the club exclusion `runner_accept` already had). It had
to: a club booking reaches /owner/schedule, and its cancel button was quoting 0066's
marketplace ladder (0 / 50% en-route / 0 ≥24h / 10% <24h) onto a club booking, writing
`bookings.cancel_fee` at a rate the club never agreed to, and leaving the club side blind —
no `club_fee_items`, no host notification, no assignment revocation. Post-cutover that wrong
number becomes a real charge.

**The gap the refusal exposes.** The club's own exit, `session_cancel_delegation`
(0057:190), accepts booking status `matching` and `confirmed` only — past that it raises
`already_handed_off`. The marketplace opened `runner_enroute → cancelled_owner` (your
2026-08-11 call, 50% = runner compensation); that was never extended to club. So an
en-route club booking now has **no owner-initiated cancel at all**. Past handoff the club's
designed answer is a case, not a cancellation — which is coherent, but it is a narrowing,
and you should know it happened.

| # | Rule | Consequence |
|---|---|---|
| A | **Leave it** (shipped) — club cancels stop at `confirmed`; past that it's a case | Coherent with the club's own model. An owner who needs out while the runner is en route has only the case path, which is slower and feels heavier than a cancel. |
| B | Extend the club ladder with an en-route tier mirroring the marketplace 50% | Restores the capability with club-correct bookkeeping (club_fee_items + host notify + revocation). Real work in club SQL, and it commits you to paying club runners the same comp the marketplace pays. |
| C | Route en-route club cancels into the incident flow explicitly (a button, not a dead end) | Cheapest honest middle: no new money rule, but the owner gets a path instead of a wall. |

**Recommendation: C now, B only if it actually comes up.** The capability gap is real but
the volume is probably zero in a Banpo pilot; a dead end is the part worth fixing today.

**Also from the adversarial round, for your awareness:** after the flip a card-less owner
can still book a MARKETPLACE run (create-booking-hold treats "no card" as routing — it sends
them down the widget path) but is refused outright from club sessions and recurring
generation, which are post-pay-only and have no widget fallback. That asymmetry is
defensible and 0081 is accurate about it, but it means the first card-less owner after the
flip experiences the club as broken rather than as "link a card first". If that reads wrong
to you, the fix is a club-side empty state pointing at card registration, not a gate change.

**Related, documented not fixed:** club cancel fees are structurally uncollectable
post-cutover — `session_cancel_delegation` writes only `club_fee_items`, never
`bookings.cancel_fee`, so `mint_cancel_fee_intent` sees zero and the debt derivation's
cancel arm never fires for club. That may be exactly right (0048's mock-era doctrine is
"record, don't charge"), which is why it is a decision: at cutover, club cancel fees either
become real money or stay recorded-only forever.

## ⑥ The cutover straddle — a booking confirmed before the flip, charged after it

**Not a defect anyone introduced; a consequence of where the two clocks sit.** The
instrument gate asks "does this owner have a card?" at *confirmation*
(0081 §A, `create-booking-hold`, `generate_recurring_bookings`); the charge asks "was
this run after the cutover?" at *run end* (0080 §E, `ended_at < payments_live_since →
mint nothing`). A booking that straddles the flip therefore passes a gate that didn't
require a card, and then gets charged. Executed by the adversarial round: a card-less
owner confirmed a club seat pre-flip, the switch was set, the run settled — and a
`24,900 pending settle_charge` was minted against an owner with zero cards. It dispatches,
fails, and the debt derivation locks the account.

All three booking paths have this window; the club's is the widest, because a session's
`scheduled_at` is unbounded while recurring only reaches 72h ahead. The straddling
bookings are also the one population that never sees the new post-pay sentence, since
their confirmation copy was written pre-flip.

| # | Mitigation | Cost |
|---|---|---|
| A | **Sequence the card-register slice before the flip** (already 0080 §0d ⑦) and flip when few bookings are in flight | Free; relies on the ordering being honoured, and doesn't cover a club session booked weeks out. |
| B | Set `payments_live_since` to a FUTURE timestamp past the longest in-flight booking | Free, one value; makes the boundary explicit instead of "now". Straddlers stay free by construction. |
| C | Charge only bookings whose *creation* was post-flip (add a booking-level marker) | A schema change and a second clock; the most precise, the most machinery. |

**Recommendation: B.** It costs one deliberate value at flip time and turns the straddle
from a class of surprise charges into a decision. A is not sufficient alone for club.

## Not decisions, just reminders of what the flip waits on

The `payments_live_since` cutover is gated on, in order: 사업자등록 → 통신판매업 →
Toss contract **with 자동결제 심사 in the same application** · billing TEST keys + the §4-2
sandbox matrix · the club-delegation money gates (in progress as its own migration) ·
①/② above. Everything shipped is inert until that timestamp is set.
