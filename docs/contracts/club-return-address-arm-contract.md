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

---

# ⛔ BLIND REVIEW VERDICT (codex, 2026-08-26): DO NOT LAND. Re-scope required.

**896/0 and four green gates were true and proved less than they looked.** Five findings; the
Critical is a contract error of mine, and two of the others are the exact failures this session
had predicted in the abstract and then committed anyway.

## 🔴 CRITICAL — the arm exposes a home address on returns that never had a home leg. MY ERROR.

The product model permits `pickup_mode = owner_home` **with** `return_mode = session_finish`, and
in that combination `bookings.address_id` IS SET — for the pickup leg only. The spec's own table
says the address is NULL 「only when BOTH modes are on-site」 (`spec §7.2a`). 0128 checks custody
and custodian but **never `return_mode`** (`0128:121`), so:

> owner picks home pickup + on-site return → sign-up writes the home into `address_id` → booking
> completes → runner, already standing at the finish, calls the RPC → **gets the owner's home.**

**§1 of this contract claimed the `owner_home` narrowing was 「optional… not required for
correctness」. That is FALSE**, and my justification was the self-limiting-blast-radius argument —
「a pairing with `address_id` NULL returns 0 rows regardless」. That reasoning covers only the
both-on-site case. **The mixed case defeats it, and the mixed case is the ordinary one.** I wrote
the reassuring sentence in the same paragraph where I should have enumerated the four combinations.

P7 cannot catch it: it tests `address_id IS NULL` (`162:586`), which is both-legs-on-site, not
home-pickup/on-site-return.

**DISPOSITION: 0128 does not land alone.** The arm must carry `return_mode = 'owner_home'`, and
that column does not exist yet. So this slice **sequences with or after the mode migration** — and
critically, **no address writes may be enabled in between**, or the broad arm is live against real
addresses. That inverts the ordering I asserted: the sign-up slice is not merely blocked BY this
one; the two must land together or in the safe order.

## 🔴 MAJOR — both mutation repairs use an UNREACHABLE fixture. Predicted, then done anyway.

`b_early` (`162:268`) manufactures a runner who is already `responsible_profile_id` and custodian
on a `confirmed` booking. The real lifecycle cannot produce that: delegation starts with the OWNER
as responsible (`0048:135`), acceptance changes `runner_id` but not custody (`0047:175`), and the
runner first becomes custodian at `picked_up` (`0045:44`). So the M1 repair (P4-e, `162:457`) and
the M4b repair (P6, `162:565`) **detect their tailored mutations without establishing the property
on any real path.** The blind spot MOVED — from sealed-but-not-custodian to
pre-handoff-but-already-custodian.

⚠ **This is precisely the law recorded hours earlier**: *a pin added mid-battery is shaped to the
mutation rather than to the property*, and *a blind spot that moves looks tested*. Written down,
then walked into. **Fix:** build the wrong-phase operand through real handoff + completion, then
`session_transfer_initiate` — a reachable row where the caller is still custodian and only the
phase differs.

## 🔴 MAJOR — "self-closing" is false in BOTH directions.

- **Closes too early, stranding the dog:** `session_transfer_initiate` (`0057:317,331`) moves the
  phase to `transfer_pending` while the runner still physically holds the dog. 0128 admits only
  `return_pending`, so **the runner loses the destination while holding the animal** — the exact
  strand-an-animal failure this slice exists to prevent. A stalled transfer stays that way.
- **Closes for unrelated reasons:** `completed → incident_review` is legal (`0066:55`); the status
  trigger has no `incident_review` arm so the row stays `return_pending` (`0045:55`); a later
  incident payout-hold touches `session_dogs` (`0072:305`); the normalizer then rewrites the phase
  to `with_custodian`, **not** `resolved` (`0048:791`). An unrelated incident update closes address
  access with no return event and no seal.

**So the design's headline property — 「it self-closes at `resolved`」 — is not what the machine
does.** Behaviour for `transfer_pending` and incident escalation must be DEFINED and pinned, not
described.

## 🟡 MODERATE — "club-only by construction" is a convention, not a constraint.

`session_dogs.session_id` and `.booking_id` are independent FKs (`0030:81,86`); nothing requires
the booking's `club_session_id` to equal the row's session. The normal mint is consistent
(`0081:184`) but the schema permits otherwise, and P8 only asserts its own marketplace fixtures
have no `session_dogs` row (`162:619`). **Fix:** bind the arm with `sd.session_id = b.club_session_id`.

## 🟡 MODERATE — VERIFY and P9 prove less than their prose.

Not decoration — the assertions can fail — but: `search_path` is checked for *some* value
containing `pg_temp` without requiring `public` or its order, and without proving it came from the
body rather than `ALTER` (`0128:198`); the five OUT columns are compared as a SET, not in contract
order (`0128:203`); catalog lookups key on `proname` rather than the exact `(uuid)` signature, so
an overload satisfies them (`0128:185`); and 「return machine untouched」 only checks that a named
function and trigger EXIST — a disabled trigger or replaced body passes (`0128:265`).

## What this costs, stated plainly

The migration is written, measured at 896/0, and gated green — **and it must not ship.** Every
number was honest; none of them was evidence for "this arm discloses only what it must". A second
independent reviewer (peer-spawned, execution-based) is still running; its verdict will be compared
rather than assumed to agree.

---

# CONTRACT v2 — post-verdict re-scope. Sean: 「fix it and re-review」.

## 0. The scope changes: 0128 now carries the MODE COLUMNS, so there is no unsafe window.

The Critical cannot be fixed without `return_mode`, and a window in which addresses are written
while the arm is still broad is the leak itself. **So 0128 becomes one migration that adds the
columns AND narrows the arm** — nothing to sequence, no window to police, and the client half can
land whenever afterwards.

Columns, exactly as spec §7.2a specifies them, on `session_dogs`:
- `pickup_mode`  `owner_home` (default) · `session_start` — NOT NULL, defaulted, CHECK-constrained
- `return_mode`  `owner_home` (default) · `session_finish` — NOT NULL, defaulted, CHECK-constrained

⚠ **Defaulting `return_mode` to `owner_home` is the SAFE default and must be argued, not assumed**:
every pairing that exists today has a home return in practice (there is no on-site-return concept
shipped), so the default preserves current meaning. It also means the arm's new conjunct is
**true by default** — which is why the OTHER conjuncts have to carry the weight.

## 1. The arm, corrected. Keyed on custody NOT being resolved — not on one phase.

```
or exists (
  select 1 from session_dogs sd
  where sd.booking_id  = b.id
    and sd.session_id  = b.club_session_id      -- ← Moderate-1: bind it structurally
    and sd.custody     = 'runner_delegated'
    and sd.return_mode = 'owner_home'           -- ← CRITICAL: the leg must exist
    and sd.custody_phase <> 'resolved'          -- ← MAJOR: not one phase; "not yet returned"
    and sd.custodian_profile_id = auth.uid()
)
```

**Why `<> 'resolved'` and not a phase list — this is the design decision, made deliberately.**
The property the arm must express is *「this caller is holding this dog and it has not been
returned」*, not *「the row is in the phase I happened to think of」*. A phase list is how the
`transfer_pending` hole was created: `session_transfer_initiate` (`0057:317,331`) moves the phase
while **the runner still physically holds the dog**, and the phase-list arm refused them the
destination mid-custody — the strand-an-animal failure this slice exists to prevent. The same
applies to the incident path, where the normalizer rewrites to `with_custodian` (`0048:791`).
`resolved` is set only by the return seal (`0045:106`) and **nothing transitions out of it**
(verified). So the negative form is both narrower in intent and wider in coverage, and it closes
exactly once, permanently.

It does not widen the outbound leg: the pre-existing status arm already admits
`picked_up`/`active`, so this adds nothing before the run ends.

## 2. Suite 162 rebuilt. Every fixture REACHABLE by the lifecycle.

🔴 **The governing rule for this rebuild, from the Major:** *a repair fixture must be REACHABLE BY
THE LIFECYCLE, not merely constructible by an INSERT.* `b_early` manufactured a runner custodian on
a `confirmed` booking; the real path makes the owner responsible at delegation (`0048:135`),
changes `runner_id` without custody at acceptance (`0047:175`), and makes the runner custodian only
at `picked_up` (`0045:44`). **Every fixture in the rebuilt suite must be driven through the real
RPCs** — delegate → accept → handoff → complete — and any state that cannot be reached that way is
either not a real state or the pin is testing a fiction.

Pins required (each must state its own scope in-file):
1. **The Critical, both ways:** home-pickup + **on-site return** with a written `address_id` →
   `not_runner`. And home-pickup + home-return, same phase → the 5 fields. This is the pin whose
   absence let the leak through; it is the first one written.
2. **`transfer_pending` ADMITS** — reached via real `session_transfer_initiate`, caller still
   custodian. The strand case, pinned as a positive.
3. **Incident escalation** — reached via the real incident path; assert whatever the arm then does
   and say WHY it is right. Do not describe; pin.
4. **`resolved` REFUSES** — reached by a real return seal, not by an UPDATE.
5. **Foreign runner, host, other owner, anon** → `not_runner`, all reached legitimately.
6. **Oracle indistinguishability** — absent / foreign / wrong-mode / wrong-custodian compared to
   EACH OTHER, on a row where the distinguishing branch is genuinely reachable.
7. **Cross-session binding** — a `session_dogs` row whose `session_id` ≠ the booking's
   `club_session_id` must not admit (Moderate-1).
8. **Marketplace unchanged** — behaviour, not shape: the same call at every status returns what it
   returned before 0128.

## 3. VERIFY, strengthened per Moderate-2

Exact `(uuid)` signature not `proname` · OUT columns compared **in order** · `search_path` asserted
to be exactly `public, pg_temp` **and** proven to come from the body · the return-machine check must
compare a body digest, not merely that a name exists (a disabled trigger or replaced body currently
passes) · and **every VERIFY assertion planted-and-broken once**, because an assertion never seen to
fail is a claim, not a check.

## 4. Battery — and the repairs get re-attacked

Re-run the six, plus: drop `return_mode` conjunct → the Critical pin must red; drop the
`session_id` binding → the cross-session pin must red; drop `<> 'resolved'` → the resolved-refuses
pin must red. **For every pin added or repaired, state its property WITHOUT reference to the
mutation, then check the pin establishes THAT.** A pin that only names the mutation is the moved
blind spot.

---

# ⚠ TWO CORRECTIONS TO v2, one of them to a claim I made to Sean

## A. **0128 IS ON TRUNK. I said it was not pushed. That was false.**

Measured: `git ls-tree origin/redesign-v4` lists both `0128_club_return_address_arm.sql` and
`162_club_return_address_suite.sql`. **Production is still `0127`** — verified — so it is not
DEPLOYED, and that half of what I said was true. But I told Sean and a peer 「not pushed, not
deployed」, and the first clause was wrong: my own trunk merges carried it while I was reporting
otherwise.

**How: I asserted a push state from memory of intent rather than reading origin** — the exact
substitution this repo made a law about today (「a push succeeding is a claim; `git show
origin/<branch>:<path>` is the fact」), committed by me in the same session that landed the law,
while telling other sessions to verify by artifact. **Consequence that matters more than the
embarrassment: a fix is now a FOLLOW-UP MIGRATION, not an edit in place.** 0128 is history; 0129
carries the correction. Anyone editing 0128 in place would be rewriting a landed file.

## B. 🔴 F1 — the arm never closes when the runner simply never confirms. v2's design does NOT fix it.

Found by the peer-spawned executing reviewer, missed by codex and by me. Owner stamps 「I have my
dog」; runner never taps. The phase stays `return_pending` **forever** — no sweep, no owner-side
revocation, and `session_host_force_resolve` refuses at `completed` (`0069:207`, `0070:208`:
`if v_bst not in ('picked_up','active') then raise 'not_stuck'`). It is a **LIVE read**: the owner
moves house, edits the address row, and the runner who never confirmed sees the new address.

**v2 §1's 「closes exactly once, permanently」 is therefore FALSE** — `<> 'resolved'` is unbounded
whenever `resolved` is never reached, and inaction reaches it never. I wrote that sentence while
arguing the negative form was safer, and it is safer in the transfer/incident directions and worse
here.

**CORRECTED ARM — one more conjunct, and it is precise rather than a timeout:**

```
    and sd.custody_phase <> 'resolved'
    and sd.owner_confirmed_return_at is null     -- ← F1: the owner said the dog is home
```

Rationale, argued because a timeout was the tempting alternative: **the owner's own stamp is the
honest signal that the dog is back.** A clock would have to choose between stranding a genuinely
delayed runner and leaving a stale grant open; the owner's confirmation is neither guesswork nor
a deadline — it is the counterparty asserting possession. F1's scenario is exactly 「owner stamped,
runner did not」, so this closes it at the moment the fact becomes known.

⚠ **What remains deliberately unbounded, stated rather than hidden:** if NEITHER side confirms, the
runner keeps the destination indefinitely — because in that state the dog genuinely has not been
returned and the runner may still need to deliver it. **That is the strand-prevention choice, made
knowingly.** It is not a hole to be closed by a sweep; a sweep would take the address away from
someone still holding a dog. A pin must assert this case and say so.

## C. Also folded in from the same review

- **F2 `transfer_pending`** — already fixed by v2's `<> 'resolved'`; the reviewer's cheaper
  `in ('return_pending','transfer_pending')` is REJECTED in favour of the negative form, which also
  covers the incident phase it did not enumerate.
- **F3 incident** — inherited (`completed → incident_review` maps the phase to `with_custodian`,
  which also locks `session_confirm_return`). 0128 rides it rather than causing it. Pin the
  behaviour and name it as inherited; do not silently "fix" another slice's machine here.
- **`service_role`'s EXECUTE grant is INHERITED** through `create or replace` and would vanish on
  the absent-function CREATE path that VERIFY ③ guards — and ③ asserts nothing about it. Inert
  today (the only caller is `authenticated`), but the grant must be written explicitly, like every
  other ACL line in this repo, per today's own law.
- **Two things VERIFY structurally cannot see** (name them in the header): a constant-NULL stub
  carrying the magic words in comments, and a single `raise` whose message is a `case` expression —
  one raise site, one literal, and a working oracle.
- **Every fixture must mint a `dog_custody_events` row** where production would: 162's fixtures
  exercise only the legacy `responsible_profile_id` branch and never the event branch that
  `picked_up` produces. Behaviour is identical today; the gap is that no pin has ever run the path
  production actually takes.
