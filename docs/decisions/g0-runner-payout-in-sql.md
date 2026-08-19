# §0g — `compute_runner_payout` in SQL: the contract, before anyone builds it

**Owner: money.** Status: **specified, not built.** This is the prerequisite for §0h (the
marketplace incident-settlement exit), and it is the smaller half of it.

Written 2026-08-15 under Sean's standing grant ("full speed, don't ask permission on fruitful
work"). The build is gated — `/autoplan` per CLAUDE.md, trust's plan-time review on money
movement, harness with mutation-verified pins. **The contract is written down first because the
arithmetic is the entire risk**, and an arithmetic contract that lives only in a session's context
is one context loss away from being re-derived wrong.

---

## Why this exists

`0083 §0g` named it: Sean's G1 ruling made the runner's payout basis depend on `end_reason`, that
pricing lives in TypeScript, and so §9's recovery arm can *report* a sealed-but-unsettled booking
but cannot *settle* it. `_settle_sealed_run` takes the price as an argument instead of deriving it.

**Half of it is already done and that is easy to miss.** `0086 §A`'s
`compute_runner_personal_payout` moved the `runner_personal` arm to SQL. What remains is the
general function — the sibling of `0080 §D`'s `compute_owner_charge`, which is the shape that
argument always pointed at: *"a money rule that lives only in a Deno function is a money rule no
pin can protect."*

**What it unlocks, in order:** `_settle_sealed_run` can drop `p_quote` · §9's sweep becomes a real
idempotent re-drive instead of a NOTICE · **§0h becomes buildable**, because an ops-called
settlement exit needs to price the run itself.

---

## The contract

    compute_runner_payout(p_booking uuid, p_end_reason text, p_actual_km numeric,
                          p_commission numeric)
      returns table (base int, distance int, addon int, guarantee int, gross int, fee int)

Ported from `supabase/functions/settle-run/handler.ts:135-187`, which is the live definition and
the only source of truth today. Transcribed here so a reviewer can check the port without reading
Deno:

```
base        := PRICING.runnerCompBase              -- 9,900 · runner basis, NOT the owner's 7,900
distance    := round(p_actual_km * PRICING.perKm)
addon       := sum(booking.addons[].price)
guarantee   := 0

if p_end_reason = 'runner_personal':
    -- delegate; do NOT re-derive. 0086 §A already owns this arm.
    (gross, fee) := compute_runner_personal_payout(p_booking, p_actual_km, p_commission)
    base := 0  · addon := 0 · distance := gross
else:
    gross := max(base + distance + addon, booking.min_fare)
    if p_end_reason in ('owner_request', 'owner_forced'):
        full_distance := round(booking.km * PRICING.perKm)
        guarantee     := max(0, round((full_distance - distance) * 0.5))
        gross         := gross + guarantee
    fee := round(gross * p_commission)
```

### The five things that will be got wrong

1. **`base` is 9,900, not 7,900.** The runner basis and the owner basis were deliberately
   decoupled (D2). Reading `pricing.ownerBaseFare` here silently underpays every runner.
2. **`runner_personal` sets `base := 0` and `addon := 0`, and the whole payout becomes
   `distance`.** Not cosmetic: writing 9,900 into `base` puts a fee the owner never paid, and the
   run never earned, into every earnings breakdown that reads the ledger. `handler.ts:170` says so.
3. **The `min_fare` floor does NOT apply to `runner_personal`** — that floor *is* the flat base
   that ⑨a retires. It applies only in the `else` arm.
4. **The guarantee is clamped at 0.** An early stop where actual exceeded planned once produced a
   negative guarantee, i.e. a pay cut. `max(0, …)` is a fix, not decoration.
5. **`fee` is `round(gross * commission)` computed ONCE.** Never re-round a subtraction; the
   runner's net is the caller's subtraction, exactly as 0086 §A already insists.

### Deliberately NOT in scope

- **The 50%-of-planned completion gate** (`handler.ts:128`) stays in TypeScript. It is an
  *eligibility* rule about whether `completed` may be claimed, not a price, and moving it would
  change an error path this slice has no business touching.
- **No behaviour change.** This slice is a pure extraction. `settle-run` calls the new function and
  must produce byte-identical ledger rows for every `end_reason`.

---

## How it must be verified

**Equivalence, not plausibility.** The pin that matters compares SQL against the TypeScript it
replaces, per `end_reason`, across the boundaries — not a handful of happy numbers:

- every `end_reason` in the enum, including the ones the client cannot send
- `actual_km` = 0 · below planned · exactly planned · above planned
- a booking whose `min_fare` binds, and one where it does not
- `owner_request` where `distance > full_distance` (the clamp's reason for existing)
- addons present and absent
- **mutation-verified**: swapping 9,900→7,900, dropping the clamp, applying `min_fare` to
  `runner_personal`, and re-rounding the fee must each redden a distinct named pin

⚠ **The equivalence pin has a shelf life.** Once `settle-run` calls the SQL, the TypeScript
arithmetic is dead code and the comparison compares SQL to itself. Delete the TS arithmetic in the
same slice, or the pin becomes a fake contract of exactly the class the repo has been bitten by.

---

## Sequencing

1. This function + its suite, `settle-run` switched to call it, TS arithmetic deleted. **No
   behaviour change; ledger rows byte-identical.**
2. `_settle_sealed_run` drops `p_quote` (its callers stop passing a price).
3. §9's sweep becomes a real re-drive.
4. **§0h** — the ops-called marketplace settlement exit, which can now price what it settles.

Steps 2–4 are separate slices. Landing 1 alone is already worth it: it is the difference between a
money rule a pin can protect and one it cannot.
