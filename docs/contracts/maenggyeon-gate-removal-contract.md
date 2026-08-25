# 맹견 gate removal — contract v2 (post dual review; pre-implementation)

**Ruling.** Sean, 2026-08-25, twice — the second time with the legal-review context in front
of him: **"Remove it completely"** (rulings doc F1). Informed and settled. The counsel
communication (the pending brief package — `docs/legal/` briefs Sean sends by email; the flag
line goes into the TRANSIT-INSURANCE brief since it is the one touching custody exposure)
gains one line stating the check was removed by decision on 2026-08-25. ⚠ WORDING (codex #8):
the line says the CHECK/FEATURE was removed and the declaration fields deleted from the
schema — never "data destroyed": a dropped column is logical forgetting (heap/WAL/backups
retain bytes until their own lifecycles), and counsel must not receive an overclaim.

**Review history.** v1 → two independent voices (Claude eng: FIX-FIRST/14 with two findings
measured on a live PG16; codex: FIX-FIRST/8). All folded here; the three critical redesigns:
the SIX-trigger inventory (v1 said four — the missed `dogs` declaration trigger bricks every
dog write if left), the named-inventory VERIFY (a `%dangerous%` name sweep cannot see
`dog_custody_gate`/`dog_custody_refusal_detail` — the silent-cron half-removal), and the
**expand/contract split** replacing v1's single atomic landing (a git landing does not change
installed binaries; EAS OTA exists but is explicitly non-atomic — `fallbackToCacheTimeout: 0`
launches the cached bundle first).

---

## 0. Shape: TWO slices. Slice A removes the behavior. Slice B removes the columns, later.

**Slice A (now):** drop every trigger and function; restore the recurring generator; client
stops rendering/writing anything 맹견; edge function's token mapping removed and redeployed.
The three `dogs` columns and the enum STAY, unread and unwritten. Consequence: **zero
deploy-order constraint** — an old installed binary that still selects/writes the columns
keeps working; a new binary works; the gate is OFF everywhere, which is the entire content of
the ruling.

**Slice B (its own migration, after distribution):** drop the CHECK, the three columns, the
enum — only once ZERO installed bundles reference them, MEASURED: every EAS channel
(`development` / `preview` / `testflight` / `production` per eas.json) checked for bundles
whose JS contains `dangerous_status`, plus the OTA fleet state; recorded in Slice B's header.
Not scheduled by calendar — scheduled by that measurement.

## 1. Slice A server inventory — exact, from the reviews' verified sweeps

DROP, in order (each an explicit statement; `create or replace` cannot drop a trigger):

1. Triggers, all SIX: `bookings_dangerous_dog` · `bookings_dangerous_dog_move` ·
   `session_dogs_dangerous_dog` · `session_dogs_dangerous_dog_move` ·
   **`dogs_dangerous_declaration`** (v1's miss — its function reads
   `new.dangerous_declared_at`; left behind after a column drop it bricks EVERY insert/update
   on `dogs`, measured) · the DELETE-latch trigger (0119 F4).
2. Trigger functions, all THREE: `_guard_dangerous_dog_custody()` ·
   **`_guard_dog_dangerous_declaration()`** · the latch fn.
3. `dog_custody_gate` · `dog_custody_refusal_detail` · `_breed_reads_as_dangerous`
   (plpgsql bodies carry no dependency records — measured: dropping a called function
   succeeds silently and fails at the next insert; ORDER is discipline, the VERIFY is the
   net).
4. `generate_recurring_bookings` restored to **0111:272-395 verbatim, plus 0111:396-401's
   comment** (measured: 0119 is the latest replace and its delta is exactly the belt — the
   ⓕ pre-check, a P0001-token-only subtransaction that RE-RAISES all other errors, and the
   post-loop warning; there is NO other-errors handler to preserve, v1's contrary sentence
   was false). Header states explicitly: the loop returns to 0111's no-per-row-isolation
   semantics — a deliberate restoration, acknowledged against 0116 §C's one-bad-row law.
5. The columns' CHECK (`dogs_dangerous_basis_pairs_with_status`) is NOT touched in Slice A
   (it constrains columns that remain); the enum and columns are NOT touched.

**VERIFY block (the load-bearing net — named inventory, never a name pattern):**
- Absence BY EXACT NAME: each of the 6 triggers, 3 guard fns, `dog_custody_gate`,
  `dog_custody_refusal_detail`, `_breed_reads_as_dangerous`.
- `pg_get_functiondef('generate_recurring_bookings()')` contains NONE of:
  `dog_custody_gate`, `dog_dangerous_`, the belt's warning literal.
- Schema-wide: `not exists (select 1 from pg_proc where pronamespace='public'::regnamespace
  and prosrc like '%dog_custody_gate%')` — no dangling caller anywhere.
- Trigger-count inventory on `bookings`/`dogs`/`session_dogs` equals counts MEASURED at
  authoring (not asserted).
- `pg_description`: the recurring function's comment no longer claims a custody belt.
- Constraint sweep includes the pair-CHECK by name (present in A — it must still exist;
  absent in B).

## 2. Slice A client + edge inventory (ui6 executes; SAME git landing as the migration)

- **`dangerousRefusalFrom` call sites — NINE in SIX files** (v1 named three; v2 said SEVEN and
  was wrong **while its own enumeration below totalled nine** — `club/session` carries four, and
  the prose contradicted the list beside it. Measured at implementation, 2026-08-25. The lesson
  is not the number: a count written in prose next to an enumeration is a second source that can
  drift from the first, and the enumeration is the one that was right. Where they disagree,
  count the list.):
  `club/delegate/[sid].tsx:102` · `club/session/[sid].tsx` ×4 (:346/:373/:402/:670) ·
  `runner/requests.tsx:374` · `owner/request.tsx:564` · **`owner/meetup.tsx:255`** ·
  **`runner/meetup.tsx:258`**. ⚠ The two meetup files are DO-NOT-REFACTOR; the removal
  reverts their catch to the pre-0119 generic alert — a behavioral edit to a frozen flow,
  argued here once: it restores the exact pre-0119 shape (the freeze's own baseline), touches
  only the catch branch 0119 added, and the freeze's owner (ui6) executes it knowingly.
- **`dog.tsx`, the full edit list (the silent-save-deadlock finding):** the 맹견 radio
  section (:383-450) AND the `danger === 'undeclared'` save guard (:187-190 — left behind it
  permanently blocks every dog save with a question the screen no longer asks) AND the state
  hydration (:92) AND the `adopt` payload writes (:233-234) AND the irreversibility notice
  (:448-450).
- **`api.ts`:** `DOG_SELECT`'s two columns (:352) · `DangerousStatus`/`DangerousBasis` types
  (:307-309) · the two `DogProfile` fields + `mapDog` lines (:299-303, :331-332) ·
  `updateMyDog`'s `dangerous` param + patch (:389, :401-404).
- **`dangerous-copy` module: DELETED**, not stubbed — `app/src/lib/dangerous-copy.ts`, PLUS
  `app/test/dangerous-copy.test.cjs` + `app/test/run-dangerous-copy-tests.sh` + the
  `package.json:55` test-chain link (leaving the chain breaks `npm test` for everyone; the
  commit gate does not catch it).
- **Edge:** `create-booking-hold/handler.ts:314-322` token→409 mapping removed; the function
  REDEPLOYED in the landing, version read back. `_test/booking_danger_token_test.ts`
  DELETED — it injects the refusal itself and would stay green forever pinning a behavior
  the server can no longer produce (the unstated-scope class, live in the repo). ⚠ Its real path
  is `supabase/functions/_test/booking_danger_token_test.ts` — the tests sit in a SHARED `_test/`
  directory at the functions root, not under each function. This contract said
  `create-booking-hold/_test/…` and no such path exists; corrected at implementation.
- Client copy: the 「무료로 크루 참가」-style surfaces are untouched; only 맹견 strings go.

## 3. Pre-slice census (ask production, don't infer)

Before authoring: `select dangerous_status, count(*) from dogs group by 1` against the linked
project, pasted into Slice A's header. If any row is `declared_dangerous`, that is a product
question routed to Sean (does that owner get told the declaration is forgotten?) BEFORE the
slice lands — not an implementation detail.

## 4. Suite plan (numbers two-sided at write time; expect ≥158-free-check)

- Suite 154 RETIRED whole; harness line dropped in the same commit. Fixture unwind in Slice A
  is **prose-only** (the columns survive A) — the fixture-value lines in
  10/seed/113/139/146/149 come out in **Slice B**, where their mechanism differs by suite:
  `t_dog`/seed are `language sql` (parse-time death), the 113/139/146/149 inserts sit in DO
  blocks where a missed column is a caught pin failure — both red, different shapes, stated
  so nobody generalizes.
- New suite pins (Slice A):
  1. A pit-bull-breed dog BOOKS (`count(*)=1` asserted, 154 G1's shape), DELEGATES, and its
     recurring series generates — and an unrelated series generates in the same sweep (G6's
     pairing, so the pin is red when the sweep is dead, not just when the gate lives).
  2. **Ordinary `insert into dogs` and `update dogs set name=…` succeed** — the one-line pin
     that reds the highest-severity half-removal (the missed declaration trigger).
  3. The named-inventory VERIFY assertions, re-run as pins (they outlive the migration).
  4. ACL sweep: no client role holds EXECUTE on any dropped-name (vacuously true — asserted
     as absence-of-object, which subsumes it).
  5. Update-path behavior: booking status moves (accept, handoff stamps) and session_dogs
     custody moves raise nothing 맹견-shaped for any breed.
- Scope stated honestly: prosrc/trigger pins prove the SCHEMA half; the edge function and
  client bundle are proven by the deploy readback + the deleted-test discipline + smoke
  ("save an unchanged dog profile; book a pit-bull-breed dog end to end"), listed as smoke,
  never implied as pins.
- **Mutation battery (executable, predicted-then-measured):** re-add each of the six triggers
  individually → named red sets · re-add `dog_custody_gate` + a synthetic caller → the
  schema-wide prosrc pin reds · re-add the ⓕ belt to the generator → the functiondef pin
  reds · (Slice B adds: re-add one column → fixture suites red per their two mechanisms).

## 5. What this does NOT do

- No change to any money, custody, or club object beyond the listed drops.
- No breed-data edits; `dogs.breed` free text untouched.
- Slice A deletes no data at all; Slice B deletes the three columns' contents (logically —
  see the counsel-wording rule) after the census and the distribution measurement.
- Does not edit the legal readiness review (history); the ruling record + the brief line
  carry the change.

## 6. Doc sweep (same push)

REGISTRY 0119 row gains a supersession note naming the removal migration (and its own
"three/four triggers" miscounts corrected to six while open) · `awaiting-sean.md`'s
"맹견 refused-vs-conditions" open item CLOSED as mooted by F1 ·
`docs/handoff-codex/legal-ops-domain.md:42`'s "맹견 exclusion DOES NOT EXIST" line gets a
dated note (true again, by ruling, not by drift) · the in-flight claim row converts to the
real numbered rows at authoring (provisional number re-resolved two-sided; 0126 is now
deployed, so expect ≥0127 — measure, don't trust this sentence either).

## 7. Review path

This v2 → implementation (author: me; client half: ui6 in the same landing) → measurement
(full harness + the battery; announce before runs) → **blind implementation review with v5 as
the money-suite reviewer** (their standing offer: branch+tip+contract only, no author
reasoning) → land Slice A + deploy + edge redeploy + readbacks → Slice B on the distribution
measurement, own mini-cycle.
