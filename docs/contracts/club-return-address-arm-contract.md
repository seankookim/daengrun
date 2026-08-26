# 0128 — the club return-address arm. Contract.

**Why now.** Sean, 2026-08-25: "go ahead with the address fix". It blocks TWO ordered slices —
the club sign-up screen (which starts writing `bookings.address_id`) and the runner's post-run
navigation branch (「집 반환 → navigate the runner to the owner set address」, round 6).

## 0. The defect, measured — it is STRUCTURAL, not an oversight

- `booking_pickup_address` (`0065`) admits the assigned runner at `runner_enroute` / `picked_up` /
  `active`, or `confirmed` inside T−24h. `completed` is **not** in the set.
- The club deliberately inverts settle-vs-return: reaching `completed` sets
  `session_dogs.custody_phase = 'return_pending'` and **keeps custody with the runner**
  (`0045:55-60`, comment 「[R2 핵심] 정산 ≠ 반환: 국면만 반환 대기, 커스터디는 러너 유지」).
  Both club return RPCs then REQUIRE that phase (`0045:79`, `0045:137`, `not_return_pending`).
- **Therefore the club's entire return window lies outside the address gate by construction.**
  The separation that makes club custody honest is exactly what puts the return past the window.
- Marketplace is unaffected and cannot be reasoned about together: `confirm_return_tx` refuses
  club bookings (`0083:383`, `club_out_of_scope`) and claims `completed` only FROM `active`
  (`0083:719-720`), so a marketplace booking is still `active` through its whole return leg.
- **Latent today only because club bookings mint with `address_id` NULL** (`0081:184-186`). It
  arms the moment sign-up writes one.

## 1. The fix — a custody-aware arm. NOT a status-list widening.

⚠ **Rejected: adding `completed` to the status list.** That re-opens the pickup address for
**every finished booking, forever**, for a runner whose custody ended months ago. It is the
tempting one-liner and it is a privacy regression.

⚠ **Rejected: a separate club-return RPC.** It duplicates the party gate, and a second copy of an
admission rule is how the two copies drift.

**ADOPTED:** one additional arm inside `booking_pickup_address`, admitting the caller when
**that pairing's custody is live and the caller is holding it**:

```
or exists (
  select 1 from session_dogs sd
  where sd.booking_id = b.id
    and sd.custody = 'runner_delegated'
    and sd.custody_phase = 'return_pending'
    and sd.custodian_profile_id = auth.uid()
)
```
Properties that make this the right shape:
- **A live custody fact, not a terminal status.** It is true only while this dog is in this
  runner's hands awaiting return.
- **It self-closes.** `session_confirm_return` moves the phase to `resolved`; the arm goes false
  with no sweep, no expiry job, no flag.
- **Its blast radius is bounded by data that already exists.** A pairing with `address_id` NULL
  returns 0 rows regardless — so an on-site-return pairing cannot leak an address it never had.
  (When `return_mode` ships, the arm MAY narrow further to `owner_home`; it is not required for
  correctness, and the narrowing is recorded as optional rather than owed.)

## 2. Invariants that MUST NOT move

1. **The probing-oracle blocker.** Absent booking / foreign booking / wrong state all raise the
   SAME string `not_runner` (`0065`, deliberate since 0060). The new arm must not introduce a
   distinguishable outcome — no new exception, no early return, no different error for "exists
   but wrong phase".
2. **The poisoned-row guard stays**: `a.owner_id = b.owner_id` in the body; a mismatched address
   yields 0 rows, not an error.
3. **Flat 5-column return** `label/addr/detail/lat/lng` — unchanged.
4. **`security definer` + `set search_path = public, pg_temp` IN THE BODY** (house law; ALTER-set
   config is wiped by `create or replace`).
5. **Explicit ACL, written not inherited** — `revoke … from public, anon` + `grant … to
   authenticated`, repeated verbatim from `0065`. This function was FIRST defined in `0060`, so
   `check-definer-acl.mjs` requires the same-file ACL; relying on preservation is the class this
   repo closed today.
6. **Marketplace behaviour byte-identical.** The arm is club-only by construction
   (`session_dogs` rows exist only for club pairings) — assert it anyway.

## 3. Suite 162 — pins, each stating its own scope

1. **The defect reproduces WITHOUT the arm** (the hole is real, not just "a pin notices"):
   a club pairing at `completed`/`return_pending` with a written `address_id` raises `not_runner`
   on the pre-0128 definition.
2. **The arm admits exactly that case** and returns the 5 fields.
3. **It refuses a DIFFERENT runner** in the same session at the same phase → `not_runner`.
4. **It refuses after the return seals** (phase → `resolved`) → `not_runner`. The self-closing
   property, asserted rather than assumed.
5. **It refuses a runner whose custody row is `owner_handled`** (dog never delegated).
6. **Oracle preservation**: absent booking, foreign booking, and wrong-phase all raise the
   identical string. Compare the three SQLSTATE+message pairs to each other, not to a literal.
7. **`address_id` NULL at `return_pending` → 0 rows, no error** (the bounded-blast-radius claim).
8. **Marketplace control**: a non-club booking's behaviour at every status is unchanged from
   pre-0128 — the arm added nothing and removed nothing.
9. **ACL + `prosecdef` + `search_path`** on the recreated function, asserted directly (the class
   `0127` closed this afternoon).

## 4. Mutation battery — THREE propositions, per today's law

For each guard: plant the failure **without** the fix (does the hole reproduce?) and **with** it
(is it closed?). A single mutation proves only that a pin notices something.
- M1 drop the `custody_phase` condition → pin 4 reds (arm no longer self-closes).
- M2 drop `custodian_profile_id = auth.uid()` → pin 3 reds (any runner in the session reads it).
- M3 drop the `custody = 'runner_delegated'` condition → pin 5 reds.
- M4 replace the shared `not_runner` with a distinct string on one path → pin 6 reds.
- M5 run pin 1 against the UNFIXED function → it must red; against the fixed one → green.
  (This is the hole-is-real / fix-closes-it pair, and it is the one that matters.)

## 5. Out of scope, deliberately

No `return_mode` column (spec-only today). No change to `session_confirm_return`. No change to
the transfer ritual — Sean ruled 「THIS interaction is the evidence」 (`0083:182-186`) and a
destination is not an interaction. No marketplace change of any kind.
