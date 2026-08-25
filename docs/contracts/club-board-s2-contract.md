# Club board S2 — contract v1

**Scope.** Spec v2 §12's slice **S2**: the NEW member projection `club_session_board(p_session)`
(spec §9), the operational board's additive columns, and the console-predicate de-duplication
(§13 C15/C17). Server-only except one console read swap. Nothing here is built.

**Ruling authority** (`docs/decisions/2026-08-25-console-rulings.md`, verbatim column):

- **#9 board effectively-public — ACCEPTED.** "Fine for the pilot" / *"always fine; it's like a
  public dashboard. may extend it to live ranked dashboard in community."* The reader class is
  ruled; §2's honesty note is now a disclosure to state, not a question to ask.
- **#6 guests can be crew.** "Guests can be crew too" — ruled AGAINST the spec's runner-only
  proposal. §4 below is the corrected predicate; the spec's own citation for the old one is
  wrong (see §11 CORRECTION 1).
- **#2 pickup mode = both**, and his comment — *"the owner can participate themselves and just
  pay the club fee and not pay for a runner. we need to figure out all the screens and maps and
  etc for this side as well, full flushed"* — is what ORDERS `owner_handled` (보호자 동반) onto
  the board. Today those dogs appear on no board at all (`0053:330`).
  Follow-up **F2** fixed the money: "Stays free", copy 「무료로 크루 참가」 — so an
  `owner_handled` row carries no money field and never will.
- **Fifth round (palette/type)** — client-side only; it does NOT touch this slice. No server
  object here renders a color. Named so nobody folds it in.

**Format note.** This document is the pre-implementation contract in the house shape
(`docs/contracts/runner-money-strip-contract.md`): every claim carries `file:line`, every
privacy property is written as a REFUSAL, and every pin states in words what its green proves.
All citations below were re-read at source in this worktree, not copied from the spec — three
spec claims did not survive that re-read and are corrected in §11.

---

## 0. The invariant, stated honestly

> **`club_session_board` returns exactly one class of fact: WHERE IS THIS DOG RIGHT NOW, and WHO
> IS AT THIS SESSION. It never returns an address, a money value, a phone or emergency contact,
> an incident, a health/breed attribute, or the identity of a runner who has not yet accepted —
> to anyone.**

**Named residual, not closable by this slice.** The gate is `club_members` OR shell ≠ `none`
(§2), and **`club_join` is unconditional**: `0048:197-204` inserts a membership row for any
signed-in caller against any existing club — no approval, no host gate — and it is granted to
`authenticated` at `0048:216`. `session_runner_commit` also auto-inserts membership
(`0043:246-247`). So the gate is **one self-serve tap from public**, and `club_members` is
already world-readable to any authenticated client (`0030:131`, `create policy "members public
read" … using (true)`). Sean ruled this acceptable (#9). This contract therefore treats every
returned column as **published to the neighborhood** and admits nothing it would not put on a
poster. That is the whole design constraint — not the gate.

**Second named residual (pre-existing, NOT widened here).** `club_delegation_board` already
emits its whole `session` object to a grade-`none` caller — including
`'fare', (select club_fare(km) from routes …)` at `0053:236`, ungated (the grade filters start
at `0053:252` for `runners` and `0053:335-336` for `dogs`; the `session` object at
`0053:230-250` has no filter). Club fare is therefore already effectively public. This slice
does **not** close that and does **not** copy it: the member board carries no fare (§5 R2). If
someone wants it closed, that is its own slice with the runner-money contract's §0 residual
argument attached.

---

## 1. Shape — one definer, no wrapper/impl split, flat whitelisted rows

**Studied precedent.** The operational board is a two-function split:
`club_delegation_board(uuid)` (`0052:149`, plpgsql, `grant execute … to authenticated` at
`0052:159`) computes `v_access := _club_shell_access(p_session, auth.uid())` and passes it to
`_club_delegation_board_impl(uuid, text)` (`0053:227`, `language sql`, `revoke execute … from
public, anon, authenticated` at `0053:338`). The split exists for exactly one reason: the
payload is **grade-parameterised** — three different payloads for host/full/limited/none — and a
`language sql` payload builder that takes a grade as an argument must never be reachable by a
client, or the client picks its own grade.

**S2 does NOT reuse the split. `club_session_board` ships as ONE `security definer` function.**
Reason: after ruling #9 the projection is **not grade-parameterised**. There is one gate and one
payload; the only caller-dependent element is the pick-pending name arm (§5 R3), which is an
inline `case when` on `auth.uid()` exactly like `0053:315-320` — it needs no grade argument, so
there is no second object to hide. Adding a split here would create a revoked helper whose only
argument is a constant, i.e. ceremony without a gate. If a future grade split appears (host-only
columns on the member board — not in this slice), `0052:149`/`0053:227` is the precedent to
copy then.

**Return type.** `returns table (…)` — flat, whitelisted, one row per board entry. **Not
jsonb.** The operational board is jsonb for historical reasons; a new object obeys the house
rule ("flat whitelisted returns"), and a flat signature is what makes the absence pins in §8
mechanical (a column that does not exist cannot leak).

```
club_session_board(p_session uuid) returns table (
  row_kind        text,        -- 'delegated' | 'owner_handled' | 'crew'
  seq             int,         -- stable render order; session_dogs.seq for dog rows, NULL for crew
  dog_name        text,        -- dogs.name        (NULL on crew rows)
  dog_photo_url   text,        -- dogs.photo_url   (0010:2)          (NULL on crew rows)
  owner_name      text,        -- profiles.name of the dog's owner, or the crew member's own name
  is_mine         boolean,     -- this row is the caller's own dog / the caller's own crew row
  state           text,        -- the P-ladder label — see §3
  state_since     timestamptz, -- when the CURRENT state began; see §5 R6 for what it may not be
  runner_name     text,        -- ONLY at P4+; NULL at P3 to third parties — §5 R3
  runner_photo_url text        -- same gate as runner_name, same arm, same NULL
)
```

**Session header facts are NOT in this return.** `club_session_detail` (`0053:353`, granted to
`authenticated`) already answers scheduledAt / meetupPoint / status / capacity / hostName /
peopleCount ungated. Duplicating them here would create a second copy of a shipped projection —
the exact defect §13 C15 exists to delete. The client composes header + board. **Refusal:** no
column of this function may duplicate a `club_session_detail` field.

**Discipline for the function** (transcribed from the runner-money contract §2 and 0116 §D):
`security definer` · **`set search_path = public, pg_temp` written IN THE BODY** (98 H1 fails
the harness on omission; ALTER-applied config is reset by `create or replace` — measured) ·
`stable` · party gate before any projection · `revoke execute … from public, anon` +
`grant execute … to authenticated` explicitly, never default PUBLIC EXECUTE · party predicates
written `exists(…)` / `coalesce(…, false)`, never a bare column comparison (§10 T2).

**No `_club_require_v2()`.** The shipped board does not call it (`0052:149-158` has no
`perform`), and a read surface that dies when the feature flag is off would take the club home
down with it. Transcribed deliberately, not omitted.

---

## 2. The gate

```
if auth.uid() is not null and not coalesce(
     exists (select 1 from club_members m
              join club_sessions cs on cs.id = p_session
             where m.club_id = cs.club_id and m.profile_id = auth.uid())
  or _club_shell_access(p_session, auth.uid()) <> 'none'
, false) then
  return;                     -- zero rows. NOT an exception. See §10 T3.
end if;
```

- **Party gate before state gate** — the gate runs before a single row of the projection is
  built (0116 §D house law, `0116:387-388`).
- **`_club_shell_access` is callable here**: it is revoked from `public, anon, authenticated`
  (`0049:26`) but this is a definer owned by the migration role, so the inner call is checked as
  the OWNER. Its grades are `host` (host or backup host) / `full` (a `session_people` row with
  `attendance <> 'no_show'`, or a committed runner, or an approved delegating owner) / `limited`
  (a delegating owner not yet approved) / `none` (`0049:9-25`). **`limited` passes this gate** —
  a person with a pending application to this session may see the board; that is strictly weaker
  than what ruling #9 already accepts.
- **Null-uid exemption, deliberate, copied from 0116 §D's shared shape** (`0116:390-396`): the
  gate fires only when `auth.uid() is not null`. After the revokes the only EXECUTE holders are
  `authenticated` (which by construction carries a JWT `sub`) and server roles (which carry
  none), so a null uid is ops/harness, never a client. **The suite pins this rather than leaving
  it as an assumption** — same sentence 0116 wrote about its own four.
- **`anon` never gets EXECUTE.** Ruling #9 accepted that the gate is one tap from public; it did
  not order an anon grant, and a signed-in identity is what makes the audit trail exist. Written
  as a refusal because "effectively public" is exactly the phrase that talks someone into
  `grant … to anon` six weeks from now.

---

## 3. Which rows, and which states

### 3a. Delegated pairings — ALL P-ladder states, nothing paid excluded

```
where sd.session_id = p_session
  and sd.custody = 'runner_delegated'
  and (sd.service_state is distinct from 'ended' or sd.booking_id is not null)
```

This is `0053:331-332`'s liveness clause **minus the third arm**. `0053:333`'s
`or (d.owner_profile_id = auth.uid() and d.approval in ('rejected','withdrawn'))` is the owner's
own "honest last word" card (0053 §4) — a private courtesy to the applicant. **Refusal: a
rejected or withdrawn application NEVER appears on the member board, for anyone, including its
own owner.** The operational board keeps it; the public dashboard does not publish who was
turned down.

Consequences, each deliberate:

- **P2 `paid` (booking `matching`, `runner_id` null) and P3 `pick_pending` are INCLUDED.** They
  carry `service_state='confirmed'`, so today's clause already admits them — "today's board
  excludes nothing paid" is verified true at `0053:331`, and the member board keeps that
  property. The member board is where 러너 선택 중 / 수락 대기 become visible; a board that
  showed only paired dogs would show an empty session for the hour that matters most.
- **P0 `signed_up` (approval `pending`) is INCLUDED** — spec §9's label list opens at 대기 중.
  This publishes "this member has applied to delegate". It is a named disclosure with its own
  pin (§8 P6), not a side effect; if Sean ever wants applications private, the one-line change
  is `and sd.approval <> 'pending'` and the pin flips with it.
- **`assignment_state` is never returned raw** — only the derived `state` label. A third party
  learns 수락 대기, never `declined`/`replacement_needed`, so a 맹견-refused, a lapsed, and a
  declined pick are **indistinguishable to non-owners** (0119 disclosure edge, carried from
  spec v1). This survives ruling F1's pending 맹견 removal either way, because the board never
  read a breed column to begin with.

### 3b. `owner_handled` rows — NEW; today invisible

```
  or (sd.custody = 'owner_handled' and sd.service_state is distinct from 'ended')
```

Today's board queries `d.custody = 'runner_delegated'` and nothing else (`0053:330`), so 동반견
appear on **no** board. Ruling #2 puts them on this one. `row_kind='owner_handled'`, `state` =
**보호자 동반** — the label already exists server-side at `0116:570`, and reusing that string
is the point (one vocabulary, two projections). `runner_name` is NULL by construction. These
rows are created by `session_rsvp(p_session, p_dog)` at `0048:188-190` and carry no booking, so
there is no money field to accidentally include (F2: 무료).

### 3c. Crew rows — dogless RSVPs, **guests included** (ruling #6)

```
select … from session_people sp
where sp.session_id = p_session
  and sp.attendance <> 'no_show'
  and sp.role in ('runner_attending', 'owner_attending')
  and not exists (select 1 from session_dogs sd
                   where sd.session_id = p_session
                     and sd.owner_profile_id = sp.profile_id
                     and sd.service_state is distinct from 'ended')
```

**Role-blind between the two RSVP roles — this is where ruling #6 overrides the spec.**
`session_rsvp` assigns `runner_attending` **only** when the caller is a runner with
`tier <> 'applicant'`; every other dogless RSVP gets `owner_attending` (`0048:178-180`, insert
at `0048:182-183`). The spec's "companions = `session_people(role='runner_attending')`" would
therefore have listed only runners and dropped every guest — precisely what "Guests can be crew
too" rules out. See §11 CORRECTION 1.

Excluded roles, each for a reason: `host_runner` is already named as `hostName` by
`club_session_detail`; `handling_runner` is a committed runner, surfaced through the pairing
rows. Note `session_runner_commit` **promotes** a `runner_attending`/`owner_attending` row to
`handling_runner` (`0043:238-240`), so a crew member who commits leaves the crew list by
construction — pinned as a transition (§8 P8), not assumed.

`owner_name` on a crew row is the person's own `profiles.name`; `dog_name`/`dog_photo_url` are
NULL. Copy 함께 달려요 is the client's (§10.4), not the server's.

### 3d. The state label vocabulary

`state` is derived from the same axes `club_dog_ui_state` reads (`0116:552`, v5, the newest of
six definitions), rendered into spec §9's ladder words:
대기 중 → 러너 선택 중 → 수락 대기 → {runner}와 페어링 → 픽업 이동 중 → 이동 중 → 도착 →
러닝 중 → 러닝 완료 → 귀가 중 → 귀가 완료, plus 보호자 동반 for 3b.

**Do NOT call `club_dog_ui_state` from this function.** Two reasons, both measured: (a) it
returns a jsonb blob with `openIncidentId`-adjacent severity/blocker fields and a
`secondaryBadges` array (`0116:610-620`) that are operational, not public — pulling it in and
then stripping fields is the leak shape this contract exists to refuse; (b) `auth.uid()` reads a
GUC and is **preserved across a definer boundary** (`0116:549-551`), so its own party gate
(`0116:562-568`) would fire inside our definer and NULL out rows for a member whose grade is
`none` — the member board's gate is deliberately wider than the shell grade, so the two gates
would fight. The member board derives its own labels from `session_dogs` columns directly.

⚠ **The stages P5/P7/P9/P10 do not exist yet.** Their producing columns land in S4/S5
(§7.1's four stamps, §7.5's `finished_pending_host`). S2 ships the vocabulary for the states
that exist today and the S4/S5 slices extend it via `create or replace`, each copying the newest
body faithfully (§10 T4). §13 C16's re-write of `club_dog_ui_state` for the new stages is
likewise an S4/S5 job — S2 touches C16 not at all. See §11 CORRECTION 3.

---

## 4. What the function must NEVER return (refusal specs)

Written as refusals, not intentions: each line is a property a reviewer can execute against the
shipped function, and each has a pin in §8.

- **R1 — No address, ever.** No column from `addresses`; no call to `booking_pickup_address`
  (`0060`/`0065`); no `bookings.address_id`; **and no 동/area band string** either. Spec §8.2's
  area-band disclosure is runner-facing pick/pairing surfaces only; the board is not one.
  (Verified: no club path touches `addresses` today — club bookings mint with `address_id` NULL,
  `0081:184-197`. S2 must not be the first.)
- **R2 — No money, of any kind.** Not `total_price`, `base_fare`, `distance_fare`, `addon_fare`,
  `min_fare`, `addons`; not `club_fare()`; not `charge_state`, `refund_state`, `hold_status`,
  `hold_expires_at`, `payout_state`, `payout_hold`, `payout_hold_reason`; not a ledger value; not
  a fee, a rate, or a gross. Fares appear on the consent screen only (Sean's ruling ④ — header
  law `delegate/[sid].tsx:20-27`, rendered fare `:201-237`). The pre-existing ungated
  `session.fare` on the operational board (`0053:236`) is a residual this slice neither copies
  nor widens (§0).
- **R3 — A pick-pending row carries NO runner identity to third parties.** At P3
  (`assignment_state='proposed'` with a live `proposal_expires_at`), `runner_name` and
  `runner_photo_url` are NULL unless the caller is one of: the dog's **owner** (the Mode B
  chooser — and in Mode C still the person who must see who was chosen for them), the
  **proposed runner**, or the session's **host or backup host**. This is `0053:315-320`'s
  sub-gate logic **inverted for the new chooser**: today host + proposed-runner see the
  candidate and the owner does not; after the chooser swap the owner authored the pick and must,
  while every other member sees 수락 대기 with no name until P4 makes the pairing public.
  *Sean's board shows pairs, not courtships.*
- **R4 — No phone, no emergency contact, no consent payload.** The function never joins
  `delegation_consents` (`emergency_contact`, `pickup_contact`, `pickup_name`, `vet_limit_krw`,
  `photo_consent` — `0048:140-149`), never touches `club_session_roster`'s people/phone-log path
  (`0049:203+`), and never calls `_club_phone_visible` (`0049:167`).
- **R5 — No incident anything.** No `openIncidentId`, no join to `club_incidents` or
  `club_incident_subjects`, no severity, no blocker array, no `review_needed`, no
  `objection_used`. A dog inside an incident renders as its custody state and nothing more.
  Third parties learning "this member's dog is in a case" is a real harm and the operational
  board is where that fact belongs (`0053:321-327`).
- **R6 — No raw per-leg timestamps.** `state_since` (when the CURRENT state began) is the only
  time value. The S4 door stamps (`pickup_departed_at`, `pickup_arrived_at`,
  `return_departed_at`, `return_arrived_at`) are NEVER returned individually: published to the
  neighborhood they read "this named person's home was empty from 08:12 to 09:40". Also
  excluded: `checked_in_at`, `checked_out_at`, `proposal_expires_at`,
  `owner_confirmed_handoff_at`, `runner_confirmed_handoff_at`.
- **R7 — No dog attributes beyond name + photo.** No `breed`, `weight_kg`, `birth_date`,
  `memo`, `vaccinations`, `preferences`, `collar`, `cumulative_km`, `fitness_age` (`0001:37-54`,
  `0033:6`). And **no dangerous-breed status column in either direction** — the board never read
  one, which is why ruling F1's removal slice cannot touch this contract.
- **R8 — No ids that are not needed to render.** No `booking_id`, no `session_dog_id` on
  third-party rows, no `runner_profile_id`, no `owner_profile_id`. `is_mine` answers the only
  identity question the client has. (An id is a join key to every table above.)

---

## 5. The operational board — additive only

Both objects are **functions**, not views; `create or replace function` preserves the existing
ACL the same way the view law preserves grants, and 0053 re-asserts the revoke line anyway
(`0053:338`) — S2 does the same, belt and braces.

⚠ **REFUSAL: neither signature changes.** `club_delegation_board(uuid)` and
`_club_delegation_board_impl(uuid, text)` keep their argument lists exactly. Adding a parameter
does not replace a function — it **mints a new one, which starts with default PUBLIC EXECUTE**,
and the revoke at `0053:338` names the old signature and would silently miss it. Every S2 column
is additive inside the existing jsonb.

**5a. `load` on `runners[]`.** Add `'load', _club_runner_load(s.id, a.runner_profile_id)`
beside the existing `'assigned'` (`0053:258-260`). `assigned` counts only accepted bookings
(`b.status in ('confirmed','picked_up','active','completed')`); the enforcement formula is
`_club_runner_load` = accepted + **live proposals** + own 동반견 (`0047:52-65`, revoked from
clients at `0047:66`). That divergence is the known dead-chip bug: `console/[sid].tsx:446`
pre-gates on `full = r.assigned >= r.cap` while the server refuses on the wider number, so a
runner sitting on a live pick renders tappable and the tap always fails — a dead button under
the honesty law, and the same class the surrounding comment block (`console/[sid].tsx:440-444`)
already fixed for two other arms. **`assigned` stays** (removing it is a client-visible change
with no caller demanding it); `load` is added and the chip's predicate moves to it in the same
push (0088 atomicity class).

**5b. `finish_blocker` on `dogs[]` — the C15 de-duplication, done ONCE on the server.**

`console/[sid].tsx:202-206` is a hand-copy of `_club_dogs_unresolved` (`0045:328-336`), verified
line-for-line: the same three explicit phases, the same `custodian_type in ('runner','host')`
arm, the same booking-status set. Two copies of a lifecycle predicate is the defect; **exposing
a third copy inside the board would make it three.** So:

1. Factor the predicate into a per-row helper — `_club_dog_finish_blocker(p_session_dog uuid)
   returns text`, values `'unreturned'` | `'run_not_ended'` | NULL — revoked from
   `public, anon, authenticated`.
2. **Re-create `_club_dogs_unresolved` to count over the helper**, so the count and the
   classification cannot drift. This is the only way the de-duplication is real; anything else
   just relocates the copy.
3. The board's `dogs[]` gains `'finishBlocker', _club_dog_finish_blocker(d.id)`.
4. `console/[sid].tsx:202-206` is deleted and reads `d.finishBlocker`.

⚠ `_club_dogs_unresolved` **gates session closure** (`club_finish_session`, `0045:343`,
`dogs_not_returned`). Re-creating it is a lifecycle-adjacent change and the harness must prove
the count is **byte-identical for every existing fixture** before the helper is trusted (§8 P11).
The console's *second* client predicate, `runStuck` (`console/[sid].tsx:214+`), is served by the
`'run_not_ended'` value now; its server-side re-anchoring rides S5 with C1 when
`finished_pending_host` enters the phase list.

**5c. What S2 does NOT add to the operational board.** `pickup_mode`, the four §7.1 stamps, and
`finished_pending_host` — **their columns and enum values do not exist yet**; they are created
by S4 and S5 and projected by the same-slice `create or replace`. Spec §9 reads as though all
four land here; §12 puts the columns in S4/S5. §11 CORRECTION 3 records the contradiction and
this resolution.

---

## 6. Client work in this slice — exactly one swap

- `console/[sid].tsx`: delete the `unreturned` predicate (`:202-206`), read `d.finishBlocker`;
  move the runner chip's `full` from `r.assigned` to `r.load` (`:446`). Types in
  `src/lib/api.ts` (`DelegationDog`, `DelegationRunner`) gain the two fields.
- **Nothing else.** The member board's SCREEN is §10.4's club-home work and belongs to ui6, not
  to S2.

**Stated so nobody mis-verifies the slice:** `club_session_board` lands with **zero client
consumers**. That is correct — S2 gates S3 (the board must render picks before the pick RPCs
exist) — and it means S2 cannot be verified by opening the app. It is verified by the harness.

---

## 7. What this slice does NOT do

Each named deliberately (0073/0075 discipline):

- **No pick RPCs.** `session_pick_runner`, self-pick refusals, the two gate widenings, the 2h
  TTL, the §11 deprecations — all S3. S2 must not add a single write path.
- **No schema change to `session_dogs`.** No new column, no new enum value, no new trigger. This
  is what keeps the 0119 gates at ZERO changes (§13 C28: the UPDATE trigger requires
  `custody`/`dog_id` to have MOVED, `0119:430-433`) and it is why S2 needs no 154 re-target.
- **No `club_dog_ui_state` change** (§13 C16 is S4/S5 — see §11 CORRECTION 3).
- **No money movement, no ladder change, no fee.** Ruling 13 (runnerless cancel = zero) and the
  §5.2 rung reorder are announcer v5's single ladder-amendment slice; S2 must not touch
  `session_cancel_delegation`.
- **No new grant on any table.** The projection reads through a definer; no table ACL moves, so
  the 0088 whole-request-403 hazard is not in this slice's path.
- **No membership mechanism.** Host-approved joins were the alternative Sean declined at #9;
  `club_join` stays unconditional.
- **No 맹견 work.** Ruling F1's removal is its own slice under the full adversarial cycle; the
  board never read a breed column, so the two slices are disjoint by construction.
- **No client screen.** See §6.

---

## 8. Suite + predicted mutation battery

New suite (number two-sided from the remote tip at write time — §10 T1). Every pin states its
proposition in words; **pin and mutation name the same observable** (v5 lesson); and each pin
carries the **unstated-scope** line — what its green actually proves, and what it does not.

| # | Pin (proposition) | Green proves | Green does NOT prove |
|---|---|---|---|
| P1 | A `club_members` row for the session's club → rows returned | the membership arm of the gate fires | nothing about shell grades |
| P2 | Shell `full` with **no** `club_members` row → rows returned | the shell arm is a real OR, not decoration | — |
| P3 | Shell `limited` (pending applicant, no membership) → rows returned | `limited` is admitted deliberately, not by accident | — |
| P4 | Neither member nor party → **zero rows, no exception** | the gate refuses | — |
| P5 | **Nonexistent `p_session` uuid → zero rows**, byte-identical to P4 | no enumeration oracle over session ids | that other club RPCs share the property (they do not — §10 T3) |
| P6 | A P0 `approval='pending'` row IS returned; a `rejected` and a `withdrawn` row are NOT — **including to their own owner** | the 0053:333 self-arm did not leak into the public projection | — |
| P7 | A dogless RSVP by a **non-runner guest** (role `owner_attending`) appears as `row_kind='crew'` | ruling #6 — the corrected predicate, not the spec's | — |
| P8 | The same person after `session_runner_commit` (role → `handling_runner`, `0043:238-240`) is **no longer** a crew row | the promotion transition is handled | — |
| P9 | An `owner_handled` dog appears with `state='보호자 동반'` and every money-shaped column absent | ruling #2's visibility + F2's no-money | — |
| P10 | Rows exist at P2 (`matching`) and P3 (`proposed`) — nothing paid is excluded | the liveness clause matches `0053:331` | — |
| P11 | `_club_dogs_unresolved` returns the **same integer** as the shipped body for every fixture in 116/153's corpus, after the helper re-write | the de-duplication is behaviour-preserving | that `club_finish_session` is otherwise unchanged (assert that separately) |
| P12 | `console`-shaped classification: a `return_pending` dog → `'unreturned'`; a `picked_up` dog with no run end → `'run_not_ended'`; a `resolved` dog → NULL | the classification the client will render | — |
| P13 | `load` on `runners[]` counts a **live proposal**; `assigned` does not | the dead-chip divergence is now visible to the client | that the chip was fixed (that is a client pin) |
| P14 | **Absence pins**: the function's `pg_proc` OUT-column list contains no name matching `addr\|fare\|price\|fee\|gross\|rate\|phone\|emergency\|incident\|breed\|weight\|memo\|booking_id\|profile_id` | R1/R2/R4/R5/R7/R8 as a shape property, not a spot check | that a *value* isn't smuggled into `state` (P15) |
| P15 | For a fixture with a known fare, address, and emergency contact, **no returned text column contains any of those substrings** | the values are not smuggled through a label | — |
| P16 | **R3 four ways**: at P3, `runner_name` is NULL to an unrelated member; NON-NULL to the dog's owner; NON-NULL to the proposed runner; NON-NULL to the **backup** host | the inverted sub-gate, including the nullable-backup arm | — |
| P17 | At P4 (`confirmed`, `runner_id` set) `runner_name` is non-NULL to an unrelated member | pairs are public; courtships are not | — |
| P18 | Null-uid caller (harness/service role) gets rows without a gate error | 0116 §D's shared exemption is deliberate, pinned not assumed | that a client can ever be null-uid (it cannot — EXECUTE holders) |
| P19 | `has_function_privilege('anon', 'club_session_board(uuid)', 'execute')` is **false**; `authenticated` is true | the ACL, both directions | — |
| P20 | The function's `prosrc` contains `search_path` = `public, pg_temp` **in the body** | 98 H1's rule locally (98 H1 also covers it schema-wide) | — |
| P21 | Caller selector is `auth.uid()`, never `current_user` (`0111:27` — postgres inside a definer) | the party selector is the JWT, not the role | — |
| P22 | `club_delegation_board`'s existing payload is byte-identical apart from the two added keys, for a host, a full, a limited and a none caller | the additive claim | — |

**Mutation battery** (each mutation must redden exactly the pin that names it, and no other):

| Mutation | Expected red |
|---|---|
| Delete the `club_members` arm of the gate | P1 |
| Delete the shell arm | P2, P3 |
| Invert the gate to `= 'none'` | P4 |
| `raise exception 'not_found'` on missing session instead of returning zero rows | P5 |
| Re-add `0053:333`'s self rejected/withdrawn arm | P6 |
| Narrow crew to `role = 'runner_attending'` (the spec's wrong predicate) | P7 |
| Drop the `handling_runner` exclusion | P8 |
| Drop the `owner_handled` branch | P9 |
| Add `and sd.approval <> 'pending'` | P6 |
| Change the helper's phase list | P11 **and** P12 together — *this is the proof the copy is gone; if only one reddens, a second copy still exists* |
| Point `load` at the `assigned` expression | P13 |
| Add a `fare` column to the return | P14 |
| Interpolate the fare into the `state` label | P15 (**not** P14 — that is why both exist) |
| Rewrite R3's gate as `auth.uid() in (cs.host_profile_id, cs.backup_host_profile_id)` without `exists`/`coalesce` | P16's backup-host arm — the `0116:425` fail-open, reproduced one arm over |
| Remove the P3 sub-gate entirely | P16 |
| Reject null-uid | P18 |
| `grant execute … to anon` | P19 |
| Drop `pg_temp` from the body | P20 (and 98 H1) |
| Swap `auth.uid()` for `current_user` | P21 |
| Change `_club_delegation_board_impl`'s signature | P22 + a fresh PUBLIC-EXECUTE ACL pin |

---

## 9. Performance — the readership changes by an order of magnitude

**Measured today.** `club_delegation_board` has five app consumers: `club/[id].tsx:114`,
`club/session/[sid].tsx:127`, `club/delegate/[sid].tsx:63`, `club/run/[sid].tsx:119`,
`club/console/[sid].tsx:77` (plus `dev/club-lab.tsx:49`). **None of them polls it.** Every one
loads inside `useFocusEffect` (`[id]:119`, `session:130`, `console:81`, `run:125`) plus
pull-to-refresh; the `setInterval`s nearby are clock ticks that call `setNow`
(`console:88`, `session:168`, `session:175`) or a run-elapsed counter (`run:149-152`) — **not
refetches**. So the call rate today is per-screen-focus, not per-second. Do not "optimise
polling"; there is none. If a future slice adds polling or a realtime subscription, that slice
owns the re-measurement.

**What changes.** The operational board's readership is a handful of parties per session; the
member board's is every club member, and `club/[id].tsx:114` already fetches a board on **every
focus of the club home** for `nextSession`. Requirements:

- The function is **`stable`** (not volatile) — same statement-level caching the shipped board
  gets, and it is what makes the projection safe to call twice in one render path.
- **Both scans are index-covered today, verified:** `session_dogs` has `unique (session_id,
  dog_id)` (`0030:90`) and `session_people` has `unique (session_id, profile_id)` (`0030:76`) —
  both btree, both leading on `session_id`. No new index is needed, and the contract says so
  rather than adding one speculatively.
- **Prefer joins to correlated per-row subqueries** where the shape allows. Today's board issues
  ~5 scalar subqueries per dog (`0053:279-289`); at pilot scale (`people_capacity` default 12,
  `delegated_dog_capacity` smaller) that is trivial, and this is a preference, not a pin — no
  performance claim is made in this contract that was not measured, and none was measured beyond
  the index facts above.
- **The projection is stable in the API sense too**: the return is a fixed column list, so a new
  state does not change the shape — only the `state` string vocabulary grows (S4/S5).

---

## 10. Traps

- **T1 — The number is two-sided, at WRITE time.** A number is taken when EITHER its file or its
  REGISTRY row reaches origin. Measured in this worktree at drafting (2026-08-25): the highest
  migration present on **any** remote branch is `0126`, the highest suite `160` — so the next
  free pair is *currently* `0127`/`161`. **Do not write that number down as settled**; re-resolve
  immediately before creating the file (`git fetch` + `git ls-tree` across every remote ref, and
  read REGISTRY on origin), and **push the migration and its REGISTRY row in the same breath** —
  a row trailing its file by an hour is the whole collision window. `.githooks/pre-push` enforces
  both halves. ⚠ `ls supabase/tests | sort` is LEXICAL; use `grep -oE '^[0-9]+' | sort -n`.
- **T2 — The 0116 §D party-gate law, and its measured fail-open.** Party gate before state gate;
  "no such thing" and "not yours" get the SAME answer (`0116:387-388`). And the gate is written
  `coalesce(…, false)` over `exists(…)` arms, **never** a bare column comparison inside a
  `not(…)`: 151 B5 caught `club_incident_settle_quote` FAIL-OPEN on its first run because
  `bookings.runner_id` was NULL, the disjunction collapsed to NULL, and `not NULL` never fired —
  a stranger read a full fare breakdown (`0116:425-433`). The R3 sub-gate in this slice contains
  a **nullable** `backup_host_profile_id`, which is exactly the shape that trap takes. P16's
  backup-host arm is the pin; the mutation is in §8.
- **T3 — Anti-enumeration: missing session ≡ no access.** Both return **zero rows**. ⚠ Today's
  board does NOT have this property: `_club_delegation_board_impl` is
  `select … from club_sessions s where s.id = p_session`, so a missing session yields NULL
  while a `none`-grade caller yields a populated object with empty arrays (`0053:229-250` — and
  `club/run/[sid].tsx:112`'s comment documents the client relying on the NULL). The new function
  must not inherit that distinction. Fixing the old one is not in this slice; the divergence is
  recorded so nobody "harmonises" the new function to the old behaviour.
- **T4 — The faithful-copy trap on a re-created function.** `_club_delegation_board_impl` will be
  `create or replace`d by S2, again by S4, again by S5. Each must start from the **newest body on
  origin**, not from the spec or from an earlier migration — 0086 §B records the exact failure
  (a body rebuilt from an older definition applies later and silently reverts the newer one while
  the harness stays green, because the reverted slice's pins live in the reverted slice's suite).
  Every S2 migration header names which version of which object it re-creates (REGISTRY
  silent-collision law).
- **T5 — `create or replace` resets ALTER-applied `search_path`.** `set search_path = public,
  pg_temp` goes in the BODY of every function this slice creates or re-creates, including the
  re-created board impl and `_club_dogs_unresolved`. 98 H1 watches the whole schema.
- **T6 — A signature change is a new object with PUBLIC EXECUTE.** §5's refusal. The revoke
  lines name signatures; a new argument slips past them.
- **T7 — "Effectively public" is not "public".** Ruling #9 accepted the reader class; it did not
  grant anon, did not open the operational board, and did not authorise any column this contract
  refuses. The pressure to widen will arrive wearing his words — the widening needs its own card.

---

## 11. Spec claims that did NOT survive re-verification

Reported per the drafting brief. Everything else cited from spec §1/§6.4/§9/§13 re-verified
clean at source, including the load-bearing ones: `0052:149` wrapper / `0053:227` impl;
`0053:330` (`custody = 'runner_delegated'` only → `owner_handled` invisible); `0053:331-333`
liveness + self-arm; `0053:315-320` proposed-runner sub-gate; `0053:258-260` `assigned`;
`0047:52-65` `_club_runner_load`; `console/[sid].tsx:202-206` and `:446`; `0048:197-204` +
`:216` unconditional `club_join`; `0043:246-247` commit auto-membership; `0045:328-336`
`_club_dogs_unresolved`; `0116:552` `club_dog_ui_state`; `0116:425` the fail-open.

**CORRECTION 1 — the crew predicate is wrong, and the ruling makes it load-bearing.**
Spec §2 (Actors) and §4.4/C6 say a dogless companion is
`session_rsvp(dog:=null)` → `session_people(role='runner_attending')`, cited to **`0048:181`**.
Two problems. (a) The line is off: `0048:181` is the `begin` of the insert block; the role
expression is `0048:178-180` and the insert `0048:182-183`. (b) The substance is wrong:
`v_role := case when p_dog is null and exists (select 1 from runners where profile_id =
auth.uid() and tier <> 'applicant') then 'runner_attending' else 'owner_attending' end` — a
dogless **guest** who is not a runner gets `owner_attending`. Under ruling #6 ("Guests can be
crew too") a crew predicate keyed on `runner_attending` would list only runners and drop every
guest. §3c carries the corrected predicate. *The spec should be amended in §2 and §4.4.*

**CORRECTION 2 — two citation ranges are loose (substance holds).** §9's "grade filters
`0053:252/268`" is one filter spanning `252`→`268` (`268` is its closing `else '[]' end`), and
"`0053:334-336`" starts on a comment line (the predicate is `335-336`). §9's "`0048:197-216`"
for unconditional `club_join` spans two unrelated objects (`club_leave` is `206-213`); the
function is `197-204` and its grant is `216`. Both underlying claims are true.

**CORRECTION 3 — §9 and §12 disagree about what S2 can project.** §9 says the operational board
grows `pickup_mode`, the §7.1 stamps, `finished_pending_host` **and** `load` in this slice; §12
creates those first three in S4 and S5. S2 cannot project a column that does not exist. Resolved
in §5c: S2 ships `load` + `finishBlocker`; the other three ride the slices that create them.
Same for §13 C16, which is tagged `RW (S2)` but describes labels for P5/P7/P9/P10 — states whose
producers are S4/S5 columns; S2 does not touch `club_dog_ui_state` at all.

**Observation, not a correction:** §9's "no money — fares appear ONLY on the consent screen" is
the right rule for the NEW board but is already false for the operational one — `session.fare`
is emitted ungated to every grade at `0053:236`. Recorded in §0 as a pre-existing residual this
slice neither copies nor widens.

---

## 12. Review path

Adversarial cycle (0059 doctrine): this contract → one fresh **blind** adversarial voice
(reviewer executes the R1-R8 refusals as attacks against the proposed shape, not against prose)
→ implement → harness (`supabase/tests/harness.sh`, PG16 at `tests/.pgtest`, all pins green) →
**mutation battery executed**, each mutation reddening exactly its named pin → three app gates
(`tsc --noEmit`, `check-rpc-contracts.mjs`, `check-route-native-imports.mjs`) → land and push the
migration with its REGISTRY row in one push → `supabase migration list` readback + the
anon-definer check.

**DONE test:** a reviewer holding an `authenticated` JWT for an account that joined the club one
minute ago, calling `club_session_board` against a live session, **cannot name** any address,
any money value, any phone or emergency contact, any incident, any breed or health attribute,
or the identity of any runner who has not yet accepted — and gets the **same** answer for a
session id that does not exist as for one they cannot see.

---

## 13. DELTA — 2026-08-25 evening re-scope (Sean's sixth round)

**This section does not rewrite the contract.** It marks which arms and pins the re-scope moves,
precisely enough that an implementer knows what changed before writing the migration. Source:
`docs/decisions/2026-08-25-console-rulings.md:156-196` (his verbatim) and
`docs/plans/2026-08-25-club-delegation-spec-v2.md` §16 (the spec amendments).

**Status of the four rulings, because one is not settled:** the PACK MODEL (§16.1), NO HOST
APPROVAL (§16.2) and the PROFILES LANE (§16.4) are instructions and are settled. **NO HOST
PAIR-REALLOCATION (§16.3) is PROVISIONAL** — it reverses Sean's own explicit approval on console
card 10 (04:26:44Z) and awaits one confirming tap. Deltas below are tagged accordingly; a
⚠️PROVISIONAL delta must not be implemented until he confirms.

### 13a. INVALIDATED — these do not survive as written

| Contract arm | file:line here | What the re-scope does |
|---|---|---|
| **§3a's P0 inclusion bullet** ("P0 `signed_up` (approval `pending`) is INCLUDED") | `:177-180` | **§16.2 removes the producer.** `session_delegate_dog` writes `approval='approved'` at insert (spec §4.2b, replacing `0048:136`'s `'pending'`), so no new row is ever `pending`. The bullet's named disclosure ("this member has applied to delegate") still happens — it just is not distinguishable from "has signed up and not yet paid." Rewrite the bullet around the new resting state; the one-line escape hatch it offers (`and sd.approval <> 'pending'`) becomes a no-op |
| **Pin P6**, both halves | `:409` | Splits. (a) "a P0 `approval='pending'` row IS returned" — no such row can be constructed for a new fixture; restate as "a signed-up, unpaid row IS returned." (b) "a `rejected` … row is NOT [returned], including to their own owner" — **`rejected` loses its only producer** (the reject arm at `0084:624-630` retires; there is no `session_reject_dog`). The `withdrawn` half SURVIVES intact — `session_cancel_delegation` still writes it (`0124:74`). Keep the `rejected` arm as a legacy-row pin with a comment, or retire it naming the successor |
| **Mutation "Add `and sd.approval <> 'pending'` → P6"** | `:439` | Becomes a **predicted-green mutation** — nothing is pending, so the added predicate matches nothing. Record it with M2's honest label (`club-rsvp-hardening-contract.md:548`, the 0126 M2 precedent): a mutation whose predicted red set is empty is recorded, never quietly dropped |
| **Pin P3's fixture** ("Shell `limited` (pending applicant, no membership)") | `:406` | The *grade* survives; its *producer* does not. `_club_shell_access` grades `limited` on a delegating owner whose `approval <> 'approved'` (`0049:19-22`), which after §16.2 is nobody. 🔴 **Spec §14 OPEN-B may re-key the grade entirely** (proposed: `full` ⇐ `booking_id is not null`, `limited` ⇐ the row exists). **Do not write P3's fixture until OPEN-B is answered** — under the proposal the fixture becomes "signed up, unpaid"; under the alternative reading `limited` has no members at all and P3 retires |
| ⚠️PROVISIONAL — **§6's client swap, second half** ("move the runner chip's `full` from `r.assigned` to `r.load` (`:446`)") and **§5a's stated justification** | `:361-363`, `:320-326` | **§16.3 deletes the chip grid entirely** (`console/[sid].tsx:445-460`, with `:161-186` and `:465-490`). There is then no chip to fix and no dead button to close — §5a's whole rationale ("the known dead-chip bug") evaporates. **`load` itself still ships**, because spec §10.1's P2 owner pick surface consumes it (`name, tier, pace fit, load/cap`) — but its *consumer* moves from the host console to the owner's pick list, and **pin P13's client half is void** while P13's server half (`load` counts a live proposal; `assigned` does not) stands unchanged. If Sean declines the reversal, this row reverts wholesale |

### 13b. CHANGED — survives, with a moved boundary

| Contract arm | file:line here | Change |
|---|---|---|
| **§3d state vocabulary** | `:229-249` | **§16.1 (settled).** The ladder is no longer N independent per-dog states through the run. Once the pack is running the board renders **one** 러닝 중 band and divergence renders as a named **exception** (미출발 · 지각 · 조기 종료), never as a peer state. The `state` column and its type do not change; what changes is which values are legal simultaneously and how the client groups them. The exception shape already exists server-side as a badge, not a stage (`0116:616-618`, 조기 반환) — copy that pattern rather than adding stages. §3d's ⚠ note that P5/P7/P9/P10 land in S4/S5 is unaffected |
| **§3a's `assignment_state` bullet** | `:182-186` | Reinforced, not changed. It already says a 맹견-refused, lapsed and declined pick are indistinguishable to non-owners. §16.2 adds one more thing that becomes indistinguishable — there is no host rejection left to distinguish. The bullet's forward-looking clause about ruling F1 stands |
| **§7's "No membership mechanism"** | `:388-389` | Still true and now stronger. §16.2 goes further than declining host-approved joins: it retires the club's **only** exclusion mechanism anywhere (spec §4.2c ② — there is no blocklist, no ban, no `status` on `club_members` (`0030:30-36`), no host member-removal RPC). **S2 must not become the place someone adds one**; spec §14 **OPEN-D** owns the question |
| **§4 R3 + pins P16/P17** | `:270-278`, `:419-420` | Substance holds; one arm gains a question. R3 admits the **host or backup host** to a pick-pending runner identity. ⚠️PROVISIONAL: after §16.3 the host is not a chooser at all, so their standing to see an unaccepted pick rests only on being the session's operator. **Not invalidated** — the operational board shows them more than this anyway — but flagged so the blind reviewer attacks it deliberately rather than inheriting it. P16's backup-host fail-open arm (§10 T2) is unaffected and stays exactly as specified |

### 13c. UNAFFECTED — checked, not assumed

Each was re-read against the amendments and does not move: **§0**'s two residuals (the
`club_join` gate and `0053:236`'s ungated fare) · **§1**'s single-definer shape and its
`_club_require_v2` refusal · **§2**'s gate structure, null-uid exemption and anon refusal ·
**§3b** `owner_handled` rows (no pairing, no host decision, unaffected by all four rulings) ·
**§3c** crew rows and CORRECTION 1's role-blind predicate · **§4** R1/R2/R4/R5/R6/R7/R8 in full ·
**§5b** `finish_blocker` and the `_club_dogs_unresolved` re-write (its phase list is S5's, not
S2's, and no ruling touches custody phases) · **§8** pins P1-P2, P4-P5, P7-P12, P14-P15, P18-P22 ·
**§9** performance (no consumer count changes) · **§10** T1-T7 · **§11** CORRECTIONS 1-3 · **§12**.

### 13d. Sequencing — S2 now has a sibling

Spec §12 inserts **S2.5** (the admission retirement) between S2 and S3. S2 and S2.5 are
**disjoint by construction and may land in either order**: S2 adds a read projection and touches
no write path (§7's own refusal); S2.5 rewrites `session_delegate_dog`, `session_approve_dog`,
`session_reconsider_dog` and `session_runner_withdraw` and touches no projection except
`_club_delegation_board_impl`'s approval counts (spec §13 C42) — **which IS a collision with §5's
`create or replace` of that same function.** Whichever lands second rebuilds from the newest body
on origin, per §10 T4, and names it in its header. Claim `_club_delegation_board_impl` in
REGISTRY's in-flight table before either slice edits it.

⚠ S2.5 carries a measured fixture sweep across **18 shipped suites + `upgrade_seed_v1.sql`, 74
call sites** (spec §16.2's table), several of which are behaviour pins that MIGRATE rather than
fixture-edit. None of them is a pin in this contract's new suite, but four are files this
contract's own §8 corpus overlaps through `_club_dogs_unresolved` (P11 asserts the count is
byte-identical "for every fixture in 116/153's corpus" — and `153_club_cancel_fee_suite.sql` is
on S2.5's list). **Run P11 against the post-S2.5 corpus if S2.5 lands first**, or the byte-identical
claim is measured against a corpus that is about to change.
