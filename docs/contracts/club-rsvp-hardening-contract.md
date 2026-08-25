# Club RSVP-family hardening — contract v1

**Subject.** The `rsvp-family hardening` slice named in `docs/plans/2026-08-25-club-mode-a-addendum.md`
§6, bullet 1: the A0 gates (format, `already_delegated`), the A0-h host arm, and the A6 cancel gate.
**Four small server arms in ONE migration.** Independent of S2–S5; the addendum's A0-x mode-switch
conversion is **NOT** in this slice (see §7).

**Provenance.** Addendum v2 rows A0, A0-h, A0-x, A6 + §6, which fold blind-review findings F4
(silent-no-op RSVP), F5 (the host cannot run their own dog), F6 (no format gate), F7 (destructive
mode switch — deferred), F8 (cancel-rsvp has no time gate and cascades records away). Money is
CLOSED by Sean's ruling F2 (`docs/decisions/2026-08-25-console-rulings.md:101`, 04:41:25):
participation is free, surfaces state 「무료로 크루 참가」 — **client work, out of scope here, landing
site named in §7.**

**Every line cited below was re-verified at source by the author.** Four addendum citations were
found imprecise; §1 records each one and what it actually says. No addendum claim was found
materially wrong.

---

## 0. The invariant, stated honestly

> **A 동반 (owner-handled) dog row exists in a session if and only if a human deliberately put it
> there, in a session whose format admits companion dogs, under the shared dog cap — and once a
> participant has physically checked in, no RPC deletes their session record.**

Three refusals and one new door. Nothing in this slice moves money, mints a charge, touches a
booking, changes a capacity number, or alters what a delegated dog does. `delegation_active`
(0052:213-217) stays exactly as shipped — this slice adds a gate *above* it, it does not soften it.

**Named residual, not closable here:** the format gate is an ENTRY gate. It is complete only
because `club_sessions.format` has no post-creation writer — there is no format-mutating RPC
(measured: `club_create_session` 0037:377 and `club_series_start` 0037:438 are the only writers),
and `club_sessions` carries exactly one RLS policy, `"sessions public read" … for select using
(true)` (0030:133), so an authenticated client's UPDATE matches no policy and changes zero rows.
§5 pins that fact rather than assuming it. If a format-edit RPC is ever added, it inherits the
question of what to do with 동반 rows already in the session, and this line is where it learns that.

---

## 1. Verified state at source — every citation, checked

| Claim | Cited as | Verified | Verdict |
|---|---|---|---|
| `session_rsvp` never reads `club_sessions.format` | 0048:158-191 | 0048:158 is the definition; its SELECT (0048:165-167) takes `status, scheduled_at, people_capacity, club_id, total_dog_capacity` — **`format` is absent** | ✅ CONFIRMED |
| The silent no-op on an already-delegated dog | 0048:189-191 | the INSERT spans 0048:188-190; **the `on conflict … do nothing` is line 190**, and 191 is `end if` | ✅ mechanism confirmed, **line cite off by one** |
| Conflict arbiter is the partial index | (implied) | `session_dogs_session_id_dog_id_key` DROPPED at 0043:28; `session_dogs_active_uni on session_dogs (session_id, dog_id) where (service_state is distinct from 'ended')` created at 0043:29-31. `owner_handled` rows carry `service_state = NULL`, so they are INSIDE the index | ✅ CONFIRMED |
| The client's `already_registered` handler is dead code | `session/[sid].tsx:230` | the handler is at **`session/[sid].tsx:229`**, inside `rsvpWith` (:217-231); 230 is the `finally`. The token is raised only by `session_delegate_dog` (0048:124, 0043:194, 0037:182) and never by `session_rsvp` | ✅ CONFIRMED, **line cite off by one**. Worse than the addendum says: `haptic('success')` fires at :221 before the handler can ever be reached |
| The host cannot `session_rsvp` | 0030:76 / 0030:189 | `session_people … unique (session_id, profile_id)` at **0030:76** ✅; `club_create_session` inserts the host's `session_people` row at **0037:380**, not 0030:189 (0030's own create-session is superseded by 0037 §?) | ✅ mechanism confirmed, **one cite points at a superseded file** |
| No other writer creates an `owner_handled` row | A0-h | measured: `custody = 'owner_handled'` is written by `session_rsvp` (0048:189) and by nothing else | ✅ CONFIRMED |
| `session_cancel_rsvp` has NO time gate | 0052:205 | 0052:205-222 is the whole body: party (209-210) → `host_cannot_leave` (211) → `delegation_active` (213-217) → deletes (218-221). **No clock, no attendance read** | ✅ CONFIRMED |
| The cancel cascades `participant_activities` away | 0030:104 | `person_id uuid references session_people on delete cascade` at **0030:104** ✅; the delete that triggers it is **0052:220** | ✅ CONFIRMED |
| The seat re-opens to a race | 0052:220-221 | `update club_sessions set status = 'open' … and status = 'full'` at 0052:221 | ✅ CONFIRMED |
| `session_delegate_dog` refuses while the 동반 row lives | A0-x | 0048:122-124 — `service_state is distinct from 'ended'` ⇒ `already_registered`; `owner_handled` rows have NULL `service_state` | ✅ CONFIRMED (and this slice does **not** touch it) |
| The shared dog cap | 0048:78-82 | `_club_total_dogs` counts every non-ended `session_dogs` row regardless of custody, at 0048:78-82 | ✅ CONFIRMED |
| The wide check-in stamp | 0030:258-259 | `update session_dogs set checked_in_at = now() where session_id = … and responsible_profile_id = auth.uid() and checked_in_at is null` | ✅ CONFIRMED — **S4's, not this slice's** |
| 동반 dogs are invisible on the board | 0053:330 | `where d.session_id = s.id and d.custody = 'runner_delegated'` at 0053:330 | ✅ CONFIRMED — **S2's** |
| The client CTA is format-blind | `session/[sid].tsx:1215` | `{isOpenish && !sess.joined && (<ClubCta label="함께 뛰기 — 동의하고 참여" …/>)}` — reads no format | ✅ CONFIRMED |

**Two facts the addendum does not state, both load-bearing here:**

1. **Neither function survives `create or replace` as-is.** `session_rsvp` (0048:159) and
   `session_cancel_rsvp` (0052:206) both carry bare `set search_path = public`, and pass 98 H1
   today only because `0055_definer_hardening.sql:171` retro-sealed them by ALTER. `create or
   replace` RESETS an ALTER-applied config (0116's header, measured). **Every function this
   migration writes carries `set search_path = public, pg_temp` in its own body**, or 98 H1
   (`98_hardening_suite.sql:50-63`) turns red — which is the point.
2. **The A6 gate is not a UI regression, it closes a direct-RPC hole.** `session/[sid].tsx:1223`
   renders the cancel CTA only while `sess.myAttendance === 'rsvp'`; a checked-in participant is
   already offered no cancel button. The record deletion is reachable only by calling
   `session_cancel_rsvp` directly, which any authenticated client can (0052:224). The gate makes
   the server say what the UI already implies.

---

## 2. Object ownership (REGISTRY silent-collision law)

This migration EXTENDS two existing objects and creates one. Each names the version it builds on:

- `session_rsvp(uuid, uuid, text)` ← **0048 §E** (0048:158; which supersedes 0043:34, which
  supersedes 0030:194 — 0043's own comment at :33 mis-states the newest definition as 0030; the
  newest is 0048 and this file says so).
- `session_cancel_rsvp(uuid)` ← **0052 §3** (0052:205; supersedes 0030:232).
- **NEW:** `session_add_my_dog(uuid, uuid)`. Nothing else in the repo creates or replaces it.

**Deliberately NOT touched, each named:** `session_delegate_dog` (0048 §D — A0-x/S3's territory,
and 66 F6 pins its cap order), `session_checkin` (0030:245 — the wide stamp is S4's), `club_
delegation_board` (0053 — 동반 rows on the board are S2's), `_club_total_dogs` (0048:78),
`_club_dogs_unresolved` (0045:328 — A4's exclusion property is S5's pin), `club_finish_session`,
every money object.

**Discipline for all three functions:** SECURITY DEFINER · `set search_path = public, pg_temp` in
the body · explicit `auth.uid() is null` rejection before anything else · party gate before state
gate (0116 §D ⓐ, 0116:422-423) · gates written `coalesce(…, false)` / `is distinct from` where a
NULL column can enter the predicate (0116:425-433's measured fail-open) · flat void returns · the
new function gets `revoke execute … from public, anon` + `grant execute … to authenticated`
explicitly, never default PUBLIC EXECUTE · `create or replace` on the two existing ones for grant
preservation (0030:330-331 / 0052:224 already hold the client grant).

---

## 3. The four arms

### §A — A0 format gate: a 동반 dog cannot enter a `delegated_only` session

**Token: `companion_closed`.** *(`format_closed` was considered and REJECTED: 0048:110, 0043:185,
0043:232 and 0037:93/173 all raise it with the OPPOSITE meaning — "this session does not admit
delegation" — and `delegate/[sid].tsx` maps it to a delegation sentence. Reusing it inverted would
make one token mean two contradictory things to the same client.)*

**Placement and gate order** inside `session_rsvp`, stated as the full post-slice order:

1. `auth.uid() is null` → `not_signed_in` (0048:164, unchanged)
2. session lookup `for update`, **now also selecting `format`** (0048:165-167 + one column) → `not_found` (168, unchanged)
3. `session_closed` (169, unchanged)
4. `session_full` — people cap (170-171, unchanged)
5. `not_your_dog` (172-174, unchanged) — **the party gate over the only object the caller named**
6. **NEW `companion_closed`** — `if p_dog is not null and v_format = 'delegated_only'`
7. **NEW `already_delegated`** (§B)
8. `dog_capacity_full` (175-177, unchanged predicate)
9. people insert → `already_joined` (181-186, unchanged)
10. dog insert (187-191, §B's belt)
11. full-transition (193, unchanged)

**Why 6 sits where it does.** *After* `not_your_dog`, because 0116 §D ⓐ puts the party gate over
the named object first and `not_your_dog` is already the one-sentence anti-enumeration answer for
"no such dog" and "someone else's dog" alike; moving the format gate above it would answer a
question about a dog id the caller has not been shown to own. *Before* `dog_capacity_full`, because
a `delegated_only` session's companion cap state is none of a 동반 applicant's business, and
`dog_capacity_full` would be a truthful sentence that sends the user to wait for a seat that will
never admit their dog.

**The predicate is positive, not negative.** `v_format = 'delegated_only'` — never `v_format not in
('owner_only','mixed')`. 0119's own lesson (154 G-header): a negative match admits any enum value
added later. If a fourth format is ever added it must fail this gate loudly, not silently pass.

**Both-ways pins.**
- `A1` `delegated_only` + own dog → `companion_closed`, **and zero writes**: no `session_people`
  row, no `session_dogs` row, and `club_sessions.status` unmoved. (The gate is above the people
  insert; this pin is what proves it.)
- `A2` `delegated_only` + `p_dog := null` → **SUCCEEDS**. Ruling #6's dogless crew are first-class
  participants; the role resolves per 0048:178-180.
- `A3` `mixed` + own dog → SUCCEEDS (95:38's shipped path, re-pinned here because §A could break it).
- `A4` `owner_only` + own dog → SUCCEEDS (30 C6's shipped path, same reason).
- `A5` `delegated_only` + a **stranger's** dog → `not_your_dog`, **not** `companion_closed` (order proof).

**§A's green proves:** no dog can reach a `delegated_only` session through the 동반 door, and the
dogless door stays open in every format.
**It does NOT prove:** (a) that the client stops offering the CTA — `session/[sid].tsx:1215` is
format-blind and stays that way after this slice (client work, §7); (b) anything about a session
whose format changed after 동반 dogs entered — see §0's named residual and its pin `A6`; (c) that
`_club_total_dogs` (0048:78-82) counts correctly — the shared cap is unchanged and unexamined here.

### §B — A0 `already_delegated`: the silent no-op becomes a refusal

**Token: `already_delegated`.**

**The defect, mechanically.** `session_delegate_dog` creates **no** `session_people` row. So an
owner who delegated a dog and never RSVP'd can call `session_rsvp(session, that_same_dog)`:
`already_joined` (0048:185) does not fire because they have no people row, the people row is
INSERTED, and then the dog insert hits `session_dogs_active_uni` (0043:29-31 — the delegated row's
`service_state` is `requested`/`approved`/`confirmed`/`in_service`, all `distinct from 'ended'`)
and does nothing. The RPC returns void. `session/[sid].tsx:221` fires `haptic('success')`. The
owner holds zero 동반 dogs and a people row they did not intend, and `:229`'s `already_registered`
branch is unreachable.

**Two belts, both required.**
1. **Pre-check, above the people insert** (step 7 of §A's order), mirroring 0048:122-124's shape:
   `if p_dog is not null and exists (select 1 from session_dogs where session_id = p_session and
   dog_id = p_dog and service_state is distinct from 'ended') then raise exception
   'already_delegated'; end if;` — placed there specifically so a refusal leaves **no orphan people
   row**, which is the worse half of the defect.
2. **Belt at the insert:** keep `on conflict … do nothing` and follow it with
   `if not found then raise exception 'already_delegated'; end if;`. The `for update` on
   `club_sessions` (0048:167) serializes same-session RSVPs, so belt 1 is not racy today — belt 2
   is what keeps that true if the lock is ever narrowed, and the mutation battery proves each belt
   independently by deleting the other.

**Why the token is honest even though the index also covers 동반 rows.** The arbiter fires on any
active row for that `(session, dog)`, companion or delegated. The companion shape is
**unreachable through `session_rsvp`**: an active `owner_handled` row implies its owner holds a
`session_people` row (they are written together at 0048:182-189, or by §C for the caller's own
people row), so `already_joined` (0048:185) answers first. Pin `B4` asserts exactly that, so the
token never lies. §C, where the companion shape IS reachable, uses a different token.

**Gate order note — a deliberate divergence from `session_delegate_dog`.** 0048 checks
`dog_capacity_full` (118-120) *before* `already_registered` (122-124). This slice puts
`already_delegated` *before* `dog_capacity_full` in `session_rsvp`: a dog already occupying a slot
cannot honestly be refused for lack of a slot. **`session_delegate_dog`'s order is NOT changed
here** — it is a money-path function outside this slice's blast radius, 66 F6 pins its
`dog_capacity_full` arm through it, and flipping it would be a drive-by edit. The inconsistency is
named, not fixed.

**Both-ways pins.**
- `B1` dog delegated in this session (`service_state = 'confirmed'`), owner has no people row →
  `already_delegated`, **and `session_people` count for that owner is still 0** (the orphan-row
  pin — this is the pin the whole arm exists for).
- `B2` same, but the delegation is `ended` (host-rejected, per 95 G5's shape) → **SUCCEEDS**; the
  companion row is created and the ended history row survives untouched.
- `B3` mutation-facing: with the pre-check removed, the belt still raises `already_delegated` (and
  vice versa) — two pins, one guarantee, from two angles.
- `B4` an owner who already RSVP'd that dog and calls again → **`already_joined`**, never
  `already_delegated` (the token-honesty pin).
- `B5` the client-visible half is NOT pinned here: `:229` still matches `already_registered` and
  will not render this token. Named as client work in §7, deliberately not silently "fixed" by
  choosing the old token — the old token means something else.

**§B's green proves:** `session_rsvp` never returns success without having done what it was asked,
and never leaves a people row behind on a refusal.
**It does NOT prove:** that the owner has a way to convert the delegation into a 동반 run — that is
A0-x, **S3's**, and until it lands the honest path is still cancel-then-rsvp with everything §7
says that costs.

### §C — A0-h: `session_add_my_dog(p_session uuid, p_dog uuid)` — NEW

**Name.** The addendum proposed `session_host_add_dog`. **Superseded, deliberately: the name
follows the gate, and the gate is membership, not hostship.** The structural gap F5 found — "your
`session_people` row already exists, so `session_rsvp` can only ever answer `already_joined`
(0030:76 / 0048:185)" — is not unique to the host. A dogless RSVP (0048:178-180, ruling #6's crew)
hits it identically the moment that person decides to bring their dog. Gating on hostship would
build the door for one person and leave the same wall standing for everyone else in the same
session. 🔵 **Reversible**: narrowing to `host_profile_id` is one predicate and one pin. The
host arm — F5's named case — is pinned explicitly regardless (`C1`).

**Gate order, complete:**

1. `auth.uid() is null` → `not_signed_in`
2. session lookup `for update` (`status, scheduled_at, format, total_dog_capacity,
   people_capacity`) → `not_found` if the row is absent
3. **PARTY GATE — `not_joined`**: `if not exists (select 1 from session_people where session_id =
   p_session and profile_id = auth.uid())`. One sentence for "no such session" and "not your
   session" is impossible here (step 2 already answers `not_found` for a missing session, exactly
   as `session_rsvp` does at 0048:168 and `session_cancel_rsvp` does by returning `not_joined` for
   both) — **`club_sessions` is `for select using (true)` (0030:133), so session existence is
   already public and this discloses nothing new.** That is the reason it is acceptable, and the
   reason is written into the migration comment.
4. **STATE — `session_closed`**: `if v_status not in ('open','full') or v_when < now()`. ⚠ This
   follows **`session_delegate_dog` (0048:109), NOT `session_rsvp` (0048:169)**, and the divergence
   is deliberate: `session_rsvp` refuses a `full` session because the applicant needs a *seat*.
   This caller already holds their seat; only the DOG cap can refuse them. Written into the body
   as a comment so nobody "harmonizes" it later.
5. **`not_your_dog`** — party gate over the dog, same predicate and same one-sentence idiom as
   0048:172-174.
6. **`companion_closed`** — identical predicate to §A. One law, two doors.
7. **`already_added` / `already_delegated`** — here BOTH shapes are reachable (a second call for
   the same dog; or a dog this owner delegated). They get **distinct tokens**, split on `custody`:
   `runner_delegated` → `already_delegated`, `owner_handled` → `already_added`. This is not an
   enumeration oracle: steps 3 and 5 have already established that the caller is a party to the
   session AND the owner of the dog, so the caller is entitled to know which of their own rows
   exists. The justification is written into the body — a future reader must not "fix" it into one
   sentence without re-reading why two are safe here.
8. **`dog_capacity_full`** — `_club_total_dogs(p_session) >= coalesce(v_total_cap, v_people_cap)`,
   byte-identical to 0048:118-120 and 0048:175-177. The shared pool is shared; this door does not
   get its own budget.
9. **INSERT exactly one row**: `session_dogs (session_id, dog_id, owner_profile_id,
   custody = 'owner_handled', responsible_profile_id = auth.uid())`, with the same
   `on conflict … do nothing` + `if not found then raise 'already_added'` belt as §B.
10. **Writes nothing else.** No `session_people` row (it exists — that is the precondition). No
    `club_sessions.status` transition (the people count did not move; 0048:193's transition would
    be a lie here). No notification, no booking, no money.

Returns `void`. ACL: `revoke execute on function session_add_my_dog(uuid, uuid) from public, anon;
grant execute … to authenticated;`.

**0119 맹견 inheritance, checked not assumed.** The dangerous-breed trigger refuses at the two
custody-TRANSFER points; 154 G4 pins that `동반 참여(owner_handled)` stays open as the remedy the
refusal token names. This arm writes the identical row shape `session_rsvp` writes, so it inherits
that behaviour by construction — **and `C6` pins it**, because a slice that silently closed the
one remedy 0119 points at would be a real regression discovered by a user, not by the harness.

**Both-ways pins.**
- `C1` **the F5 case**: host of a `mixed` session adds their own dog → one `session_dogs` row,
  `custody = 'owner_handled'`, `responsible_profile_id` = host, `booking_id` NULL, **zero
  `bookings` rows created**, `session_people` count unchanged, `club_sessions.status` unchanged.
- `C2` a dogless `owner_attending` who already RSVP'd adds a dog → SUCCEEDS (the widened gate's
  own justification, pinned).
- `C3` a stranger (no `session_people` row) → `not_joined`, and zero rows written.
- `C4` a party adding **someone else's** dog → `not_your_dog` (order proof: party-over-dog before
  every state gate below it).
- `C5` `delegated_only` session, host, own dog → `companion_closed` (§A's law reaching the second door).
- `C6` a declared 맹견, owner_handled, via this arm → **SUCCEEDS** (0119's remedy survives).
- `C7` calling twice with the same dog → `already_added`; calling with a dog this caller has
  delegated → `already_delegated` (the two-token split, both directions).
- `C8` `full` session, host, own dog, cap available → **SUCCEEDS** (the §C-step-4 divergence, pinned
  as behaviour, not as a comment).
- `C9` cap exhausted → `dog_capacity_full`, and the pool is the SHARED one: a session whose cap is
  consumed entirely by delegated dogs refuses this arm (the 0048:78-82 pool made executable).
- `C10` ACL: `anon` holds no EXECUTE; `authenticated` does; the function is DEFINER with `pg_temp`
  in its own `proconfig` (98 H1 covers the last one schema-wide, so `C10` asserts the first two).

**§C's green proves:** the host — and every other seated participant — can put their own dog in a
session under the same format, cap, ownership and conflict law that governs `session_rsvp`.
**It does NOT prove:** (a) that any human can reach it — the 내 아이도 함께 button is client work
(§7); (b) that the dog appears anywhere — `club_delegation_board` filters to
`custody = 'runner_delegated'` (0053:330), so this dog is invisible on the board until **S2**;
(c) that check-in behaves — `session_checkin`'s stamp (0030:258-259) will reach this row correctly
*because it is `owner_handled`*, which is the CORRECT half of the wide stamp; the defective half
(a delegated, un-handed-over dog) is **S4's** and is untouched here.

### §D — A6: `session_cancel_rsvp` refuses after check-in

**Token: `already_checked_in`.**

**Gate order, complete** (the whole post-slice body):

1. **NEW** `auth.uid() is null` → `not_signed_in`. ⚠ **Behaviour change, named:** today a
   null-uid caller falls through to `not_joined` (0052:209-210 — fail-closed, but by accident of
   the SELECT returning no row). Measured: no migration and no edge function calls
   `session_cancel_rsvp`; the only callers are `api.ts:3516` (`cancelClubRsvp`) and the suites, all
   JWT-bearing. Pinned both ways (`D7`).
2. `select role, checked_in_at into v_role, v_checked from session_people where session_id =
   p_session and profile_id = auth.uid()` — 0052:209 plus one column.
3. **PARTY GATE** `if v_role is null then raise 'not_joined'` (0052:210, unchanged). This is
   already the one-sentence anti-enumeration answer: a session that does not exist and a session
   the caller never joined produce the identical row-absent condition and the identical token.
   Preserved deliberately — do not "improve" it into a `not_found`/`not_joined` split.
4. **ROLE GATE** `if v_role = 'host_runner' then raise 'host_cannot_leave'` (0052:211, unchanged,
   still second — the host's exit is a different product question, not a timing question).
5. **NEW STATE GATE** `if v_checked is not null then raise 'already_checked_in'`.
6. `delegation_active` (0052:213-217, unchanged predicate) — **now fourth.**
7. deletes + seat re-open (0052:218-221, unchanged).

**Two orderings ruled, each with its reason:**

- **`already_checked_in` BEFORE `delegation_active`.** Both are refusals, so no invariant is
  weakened either way — but `already_checked_in` is **terminal** (a check-in cannot be undone) and
  `delegation_active` is **resolvable** (cancel the delegation and retry). Answering the resolvable
  one first sends a mixed-mode owner to cancel a real delegation — a money-bearing act — and then
  refuses them anyway. That is a dead-end the honesty laws exist to prevent. `D2` pins the
  conjunction explicitly so the order is a measured property, not a comment.
- **The predicate is `checked_in_at is not null`, not `attendance = 'checked_in'`.** `session_
  checkin` sets both (0030:254-256), but `attendance` can subsequently move to `'no_show'` while
  `checked_in_at` stays stamped (95:52 does exactly that by UPDATE). A participant who checked in
  and was later marked no-show still physically attended; their record must still stand. The
  timestamp is the durable evidence and cannot be laundered by an attendance move. `D5` pins that
  shape directly.

**Both-ways pins.**
- `D1` **the load-bearing one**: a checked-in participant holding a 동반 dog calls cancel →
  `already_checked_in`, **and all four survive**: the `session_people` row, the `owner_handled`
  `session_dogs` row, the `participant_activities` row (the 0030:104 cascade did not fire), and
  `club_sessions.status` unmoved. F8's whole finding, made executable.
- `D2` checked in **AND** holding an active delegation → `already_checked_in` (never
  `delegation_active`) — the order ruling.
- `D3` not checked in, no delegation → **CANCELS**: people row gone, `owner_handled` row gone,
  `full` → `open`. 30 C10's shipped property, re-pinned in-slice because §D could break it.
- `D4` not checked in, **active** delegation → `delegation_active` (95 G4's property, re-pinned:
  proof the new gate did not displace the shipped one).
- `D5` `checked_in_at` stamped **and** `attendance = 'no_show'` → `already_checked_in` (the
  predicate-choice pin).
- `D6` a host who is checked in → `host_cannot_leave`, not `already_checked_in` (role-before-state
  order proof).
- `D7` null-uid caller → `not_signed_in`; a signed-in stranger → `not_joined` (both directions of
  the new step 1, and proof the anti-enumeration answer at step 3 is intact).
- `D8` not checked in, `ended` delegation → CANCELS, `owner_handled` row deleted, the ended
  delegation row and its `delegation_consents` row survive (95 G5's property, re-pinned).

**§D's green proves:** a participant's attendance record, activity row, and incident standing
cannot be deleted by an RPC once they have physically checked in.
**It does NOT prove:** (a) that leaving mid-session is *recorded* anywhere — this slice only refuses
the deletion; a real "I left early" state is not in scope and is not silently faked; (b) that the
host cannot delete the record another way (`club_finish_session`, host cancel paths, and the
0118 no-show ladder are untouched); (c) that the copy a user reads is honest — the A6 sentence
("free before check-in; after check-in the record stands") is client work, §7.

---

## 4. Mixed-mode interactions — what this slice does and does not move

The addendum's "biggest missing scenario" (one person holding a 동반 dog AND a delegated dog)
touches this slice at four points. Three are preserved; one is deferred:

1. **`delegation_active` STAYS** (0052:213-217, unchanged predicate, now at gate 6). The delegation
   must resolve before the person leaves the session. §D adds a gate above it; `D4` pins that the
   shipped refusal still answers when the person is not checked in.
2. **The shared dog cap stays shared.** `_club_total_dogs` (0048:78-82) counts companion and
   delegated rows together; §A, §B and §C all use `coalesce(total_dog_capacity, people_capacity)`
   unchanged. `C9` pins that §C's new door draws from the same pool. **No cap number moves.**
3. **The wide check-in stamp is S4's, not this slice's.** 0030:258-259 stamps every `session_dogs`
   row where `responsible_profile_id = auth.uid()`, including a mixed-mode owner's delegated,
   un-handed-over dog — which then satisfies the no-show fee's attendance gate. That is a MONEY
   defect and it belongs to S4's per-pairing evidence redesign. **This slice does not touch
   `session_checkin`** and does not pin around it. Naming it here so the next reader does not
   mistake §D's green for a fix.
4. **A0-x — the mode switch — is NOT this slice. It is S3's.** Today the switch is destructive:
   `session_delegate_dog` refuses while the companion row lives (`already_registered`, 0048:122-124
   — an `owner_handled` row's `service_state` is NULL and therefore always `distinct from 'ended'`),
   so the owner must `session_cancel_rsvp` first, which deletes their people row and re-opens their
   seat to a race (0052:220-221). **This slice makes that path measurably worse for one shape and
   the trade is deliberate:** an owner who has already checked in can no longer cancel-then-delegate
   at all (§D refuses). That is correct — handing a dog over after check-in is a *handoff*, not a
   re-application — but it means the in-place conversion arm is now the only honest door for that
   case, and S3 carries it. **`session_delegate_dog` is not edited here** (see §2).

Also named, owned elsewhere: `_club_runner_load`'s own-동반견 term (0047:62-64 — a handling runner
who brings their own dog spends a delegated slot, F14's surface question) is untouched; §C's new
door can create exactly that row for a committed runner, and the commit surface's honesty about it
is client work in the same S-client bucket as §7.

---

## 5. Blast radius on shipped suites — measured, not assumed

Every suite that drives `session_rsvp` or `session_cancel_rsvp` was read, not grepped:

| Suite | Call sites | Session format | Would it see a new refusal? |
|---|---|---|---|
| `30_club_suite.sql` | rsvp `:94, :107, :119, :129, :132, :136, :209`; cancel `:148, :154` | `club_create_session(…, 4)` — `p_format` defaults to `'owner_only'` (0037:364) | **NO.** §A never fires (`owner_only`). C10's cancel (`:148`, o2) and the host refusal (`:154`) both happen at C10, **before** C11's check-in (`:173`) — and C11's checked-in user (`o`) never cancels. |
| `95_audit_gates_suite.sql` | rsvp `:38, :43, :46`; cancel `:142, :164` | `'mixed'` (`:33`) | **NO.** §A never fires. G4's canceller (`oo`) and G5's (`pp`) are never checked in — only `rr` checks in (`:36`). §D's gate is not reached. |
| `154_dangerous_breed_suite.sql` | rsvp `:400` | `'mixed'` (`:204`) | **NO.** G4-ⓑ's 동반 remedy stays open; `C6` re-pins it from the new door. |
| `153_club_cancel_fee_suite.sql` | rsvp `:986` (`session_rsvp(s_att, null::uuid)`) | `'mixed'` (`:631`) / built at `:302` | **NO.** Dogless — §A explicitly leaves that door open (`A2`), §B's pre-check is `p_dog is not null`-guarded. No cancel call in this suite. |
| `108_incident_accountability_suite.sql` | rsvp `:194` (dogless) | `'mixed'` (`:57`) | **NO.** Same reason. A5's guest-RSVP-then-open-incidents path is untouched. |
| `66_r4_suite.sql` | `dog_capacity_full` at `:166` | — | **NO.** F6 drives `session_delegate_dog` (`:159, :163`), whose gate order this slice explicitly does not change (§B). |

**Result: ZERO shipped pins change behaviour, and therefore zero shipped pins are re-pinned in this
slice.** Every companion-dog RSVP in the suite corpus lives in an `owner_only` or `mixed` session;
every cancel happens before its caller checks in. The suite-updates-in-slice law (CLAUDE.md) is
satisfied vacuously here — **and that is a finding worth stating rather than a silence**, because a
reviewer's first instinct will be that four new refusals must have reddened something. They do not,
which is also why §3's pins deliberately RE-PIN the shipped properties they sit next to (`A3`, `A4`,
`D3`, `D4`, `D8`) from the new suite: those propositions are now load-bearing on code this slice
rewrote, and a pin in another file is not a pin on this migration.

⚠ **One suite is affected structurally, not behaviourally:** `150_account_deletion_suite.sql:486`
and `:550` insert `club_sessions` rows with `format = 'delegated_only'` **directly**, not through
`club_create_session`, and never call `session_rsvp`. No change. Named because it is the only
`delegated_only` fixture in the corpus and a reader grepping for the string will land there.

⚠ **Harness registration:** the new suite line appends at the tail of `supabase/tests/harness.sh`
(currently `:201`, suite 160). **Suite 155 (parked 0120, `claude/wf-location`) and any other
in-flight branch land at the SAME tail and WILL textually conflict — resolve by NUMBER, never by
side** (0122 MINOR-8's rule, 0118-row precedent, restated at `158`'s registration line).

---

## 6. Numbering — two-sided at write time

**The number is taken when EITHER its row or its file reaches origin.** Resolve BOTH immediately
before writing the file, never from this document:

```
git fetch && git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | grep -oE '[0-9]{4}' | sort -n | tail -3
git fetch && git ls-tree --name-only origin/redesign-v4 supabase/tests/      | grep -oE '[0-9]+_'   | grep -oE '[0-9]+' | sort -n | tail -3
git show origin/redesign-v4:supabase/migrations/REGISTRY.md   # the row side
```

**Measured at contract-writing time (2026-08-25):** files on origin end at **0126 / 160**; the
REGISTRY tail agrees (0126 is the last row, `0125` is claimed row-first with its file authoring in
a trunk worktree). That would make **0127 / 161** the next free pair — **and it is already wrong.**

🔴 **Observed live, during the writing of this document:** an untracked
`supabase/migrations/0127_remove_dangerous_breed_gate.sql` (console card 15, the 맹견-gate removal)
appeared **in this same worktree**, claimed by a parallel session, with no REGISTRY row and nothing
on origin. It is invisible to `git ls-tree origin/redesign-v4` and invisible to the REGISTRY, so
both halves of the two-sided check say 0127 is free **and both are wrong**. This is collision seven's
mechanism reproduced in real time and it is the reason this section refuses to name a number:
**re-resolve at write time, and add a third read — `ls supabase/migrations/ | tail -3` on your own
tree** — before writing the file. ⚠ 0127's removal slice also deletes the 맹견 refusal that §C's
pin `C6` inherits; if it lands first, `C6`'s proposition changes from "the remedy survives" to
"there is no gate to survive" and the pin must be restated, not deleted. ⚠ `ls supabase/tests
| sort` is LEXICAL (`117_` sorts before `97_`); use the numeric form above. **Push the migration and
its REGISTRY row in the same breath** — a row trailing its file is the entire collision window, and
`.githooks/pre-push` refuses a push that introduces a number present on another remote branch or one
without a REGISTRY row (enable once per clone: `git config --local core.hooksPath
/Users/sean/dev/daengrun/.githooks`, pointing at the **main clone**, never `$(git rev-parse
--show-toplevel)`).

---

## 7. Not in this slice — each named deliberately

- **🔴 The F2 copy 「무료로 크루 참가」 is CLIENT work and lands nowhere in this migration.**
  Sean's ruling (console F2, 2026-08-25 04:41:25, verbatim: *"state 무료로 크루 참가"*) is about a
  rendered line, and the server has no money arm to add — participation is free *by the absence of
  code*, not by a mint that returns zero. Measured: the string appears today only in
  `docs/plans/2026-08-25-club-mode-a-addendum.md`, `docs/decisions/2026-08-25-console-rulings.md:101`
  and `docs/contracts/maenggyeon-gate-removal-contract.md:100` — **in no client file.** Its landing
  sites, named so the client slice does not have to re-derive them:
  - `app/app/club/session/[sid].tsx:1214-1222` — the 함께 뛰기 CTA block; the free line sits on the
    A-mode fork beside it, and the same block is where §A's format gate must be mirrored so the CTA
    stops being format-blind (dead-button law: a CTA whose server answer is certain to be
    `companion_closed` must not be offered).
  - `app/app/club/session/[sid].tsx:229` — `already_registered` gains an `already_delegated` branch
    (§B5). Do **not** repoint it at the old token; that token means something else.
  - `app/app/club/session/[sid].tsx:270-274` — `doCancelRsvp`'s error map gains
    `already_checked_in` with A6's honest sentence (free before check-in; after check-in the record
    stands), and `:1223-1235`'s cancel branch is where the copy is stated *before* the tap.
  - the 내 아이도 함께 entry point for §C — no host surface exists today; it is new client work.
  - `app/src/lib/api.ts:3515-3516` — the two RPC wrappers; §C needs a third.
- **A0-x, the in-place mode switch — S3's** (§4.4). This slice narrows the destructive path
  deliberately and does not replace it.
- **A2's wide check-in stamp — S4's** (§4.3). Money gate; untouched here.
- **A4's `owner_handled` exclusion from `_club_dogs_unresolved` (0045:328-336) and A5-x's
  zero-delegation close rule — S5's pins.** This slice creates more `owner_handled` rows (§C), which
  makes S5's preservation property *more* load-bearing, not less. Named for S5's author.
- **동반 dogs on the board (0053:330) — S2's.**
- **The participant run view and `participant_activities` writes (§3 of the addendum) — after S2.**
  Note for that slice: `participant_activities`' RLS is `using (auth.uid() is not null)` (0030:138),
  i.e. every authed user reads every row. Not this slice's to fix, and this slice writes no
  `participant_activities` rows.
- **No money movement, no booking, no notification, no capacity number, no client behaviour.**
- **`session_delegate_dog`'s gate order** (0048:118-124) — inconsistency named in §B, not fixed.

---

## 8. Suite + mutation plan

**Suite `<161>_club_rsvp_hardening_suite.sql`.** Every pin states its proposition in words; pin and
mutation name the same observable. Party gates pinned both ways including the null-UID arm, and an
`auth.uid()`-vs-`current_user` proof arm on the new function (0111:27 — `current_user` is `postgres`
inside a definer, so a party gate written against it is no gate at all).

Fixture shape: one club, one host (runner), two owners with two dogs each, one dogless crew member,
and **three sessions — `owner_only`, `mixed`, `delegated_only`** (the last is what the corpus has
never had, and it is why §A could ship green against every existing suite).

⚠ **Fixture archaeology to respect** (recorded by 0124's suite, measured): `session_checkin` is
start-windowed (`checkin_window`, 0030:251-253) and `club_create_session` refuses anything inside
`now() + 1 hour` (`too_soon`, 0037:372). §D's checked-in fixtures must be built at `now() + ~90
minutes` and then moved (`update club_sessions set scheduled_at = …`, 30 C11's `:172` idiom), or
they will measure the window instead of the gate.

**Predicted mutation battery** — each mutation, the pin set it must redden, and nothing else:

| # | Mutation | Predicted red set |
|---|---|---|
| M1 | delete §A's format gate | `A1` (and `A5` stays green — it is above the gate) |
| M2 | invert §A's predicate to `v_format not in ('owner_only','mixed')` | **no red predicted today** — the enum has exactly three values. Recorded as a deliberate no-op mutation whose purpose is to prove the *positive-match* discipline is currently unfalsifiable; the pin that would catch it is a fourth format, and §A's comment says so. (A mutation with a predicted-green outcome is recorded, not hidden — 0126's M2 precedent.) |
| M3 | move §A's gate above `not_your_dog` | `A5` (order proof) |
| M4 | delete §B's pre-check, keep the belt | `B1`'s orphan-people-row arm alone (`B3` proves the belt still raises) |
| M5 | delete §B's belt, keep the pre-check | `B3`'s belt arm alone |
| M6 | delete both §B halves (restore 0048:190 verbatim) | `B1`, `B3` — and the RPC returns success, which is F4 reproduced |
| M7 | move §B above `already_joined` | `B4` (token honesty) |
| M8 | §C party gate → `true` | `C3` |
| M9 | §C party gate → `current_user`-based | `C3` + the `auth.uid()` proof arm |
| M10 | §C step 4 → `session_rsvp`'s `v_status <> 'open'` | `C8` |
| M11 | §C collapses the two tokens into one | `C7` |
| M12 | §C also inserts a `session_people` row | `C1` (people-count arm) |
| M13 | §C uses its own cap instead of `_club_total_dogs` | `C9` |
| M14 | §C drops the ACL revoke / grants `anon` | `C10` |
| M15 | delete §D's new gate | `D1`, `D2`, `D5` |
| M16 | §D's gate placed BELOW `delegation_active` | `D2` alone (the ordering pin, in isolation — this is the mutation that proves `D2` is not a duplicate of `D1`) |
| M17 | §D's predicate → `attendance = 'checked_in'` | `D5` alone |
| M18 | §D's gate placed ABOVE `host_cannot_leave` | `D6` |
| M19 | delete §D's null-uid reject | `D7`'s first arm |
| M20 | drop `pg_temp` from any of the three bodies | **98 H1** (schema-wide; no new pin needed, and this mutation is what proves that) |

**M2's honest label:** a mutation whose predicted red set is empty is *not* evidence the pin works.
It is recorded because the alternative — quietly not running it — is how a vacuous CHECK shipped in
0122 (MINOR-6, measured vacuous). Every other row above must be **executed** and its observed red
set recorded next to the prediction; a prediction that misses is a finding about the pins, not a
typo to correct silently.

**Gates before commit** (from `app/`): `./node_modules/.bin/tsc --noEmit` ·
`node scripts/check-rpc-contracts.mjs` · `node scripts/check-route-native-imports.mjs`. Note the RPC
checker collects signatures from migrations and validates *client* call sites, so §C's new function
with no client caller passes trivially — it starts being checked the day the client slice (§7) calls
it, which is the right time.

**Harness:** `supabase/tests/harness.sh` (PG16 at `tests/.pgtest`; `pg_ctl` must start in the same
shell invocation). All pins pass; record the baseline count before the slice and the delta after.

---

## 9. Review path

This contract goes to one blind adversarial voice **before** implementation (the reviewer EXECUTES
the attacks, per the 0059 doctrine and CLAUDE.md's migration cycle), with three questions put
explicitly because the author has already ruled on them and a ruling is not a proof:

1. **§C's widened gate** — membership vs. hostship. Is a seated `owner_attending` adding a dog a
   feature or a hole? (Reversal cost: one predicate, one pin.)
2. **§D's ordering** — `already_checked_in` above `delegation_active`. Is there a mixed-mode shape
   where answering the terminal refusal first destroys information the user needed?
3. **§C's two-token split** at step 7 — is the party-gate justification for two sentences sound, or
   does some path reach step 7 without both gates having fired?

Then: implement → measure (harness + the three app gates) → mutation battery with every observed red
set recorded → adversarial re-read → land **and push the same session** (Ship means push; work that
exists only in a worktree reserves nothing).

**DONE test:** a reviewer holding a `delegated_only` session, a `mixed` session, an owner with one
delegated and one companion dog, and a checked-in participant cannot — through any RPC an
`authenticated` JWT can call — (a) place a companion dog in the `delegated_only` session, (b) obtain
a success return from `session_rsvp` without a `session_dogs` row appearing, (c) leave a
`session_people` row behind on any refusal, or (d) delete a checked-in participant's
`participant_activities` row. Reaching any of those ONLY as the host through
`club_finish_session`/host-cancel paths, or through the S4 wide-stamp defect, confirms a named
out-of-scope item (§7), not a defeat.
