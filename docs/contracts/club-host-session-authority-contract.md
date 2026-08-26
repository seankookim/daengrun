# Club host session authority — contract v1

**Subject.** The two powers a club host does not have today, both ruled by Sean on the console
2026-08-25, designed here as **one slice** because both are a host acting on `session_people` and
splitting them would duplicate the party gate.

1. **Host verification of attendance.** 「the host should have a way to verify (perhaps the list?)」
   — `docs/plans/2026-08-25-round6-picks-and-live-map.md:16-17`, verbatim.
2. **Host removal from ONE walk.** 「Host can remove someone from one walk」 —
   `docs/decisions/2026-08-25-console-rulings.md:278`, card `host-remove-anyone`, 09:04:13Z. The
   narrowest of three options; the other two (club-level ban, do nothing) were not chosen.

**This is a CONTRACT. No migration and no suite were written.** Nothing under `supabase/`, `app/`
or anywhere else was touched by the session that wrote this file.

**Every citation below was re-verified at source by the author of this file.** §1 records each one,
including the two that were imprecise and the one that is *stronger* than it was handed to me.

---

## 0. The invariant, stated honestly

> **A host may record that a person WAS present, and may end one person's participation in ONE
> session — and neither act may move money, touch a booking, take a dog's responsible party away
> from it, delete a record of something that physically happened, or transfer control of the
> session.**

Two new doors and one undo. The money boundary is held **by refusal, not by accounting**: the
removal arm refuses outright on every shape where a booking exists, so no code path in this slice
can reach `bookings`, `_club_record_cancel_fee`, `_club_record_no_show_fee`, or a ladder. That is
the design, and §5 is the pin that makes it a measured property rather than a promise.

---

## 1. Verified state at source — every claim, checked

| Claim as handed to me | Verified at | Verdict |
|---|---|---|
| `0030:254` is the ONLY statement in the schema that writes `session_people.attendance`, and it is self-service | `0030:254-255` is `update session_people set attendance = 'checked_in', checked_in_at = now() where session_id = p_session and profile_id = auth.uid()`. Swept `update session_people` (6 hits: `0030:254`, `0037:102,132`, `0038:183`, `0043:239,428` — the last five write **`role`**, not `attendance`), `insert into session_people` (8 hits, none names an `attendance` column — all take the default `'rsvp'`), `delete from session_people` (2 hits: `0030:240`, `0052:220`, both `profile_id = auth.uid()`) | ✅ **CONFIRMED, and stronger than stated** — see the three findings below |
| Every other occurrence is a reader: `0031:50,54,71,74,116,126` | All six read: `:50`/`:54` `club_my_stats` (attended + streak), `:71`/`:74` `club_host_stats` (totalTeams + returning), `:116`/`:126` the recap's team count and aggregation | ✅ CONFIRMED |
| The host literally cannot mark anyone present today | `session_checkin` is defined **once** (`0030:245`) and never replaced — no second `create or replace function session_checkin` exists anywhere in `supabase/` or `app/` | ✅ CONFIRMED |
| Sean's removal ruling, 09:04:13Z, narrowest of three | `docs/decisions/2026-08-25-console-rulings.md:278` (table row) and `:288-290` (the disposition: 「`session`-scoped removal, no club-level ban, no blocklist」) | ✅ CONFIRMED verbatim |
| No `status` on `club_members` (`0030:30-36`) | `club_members` is `(club_id, profile_id, role, joined_at)` at `0030:30-36`. `role` is `check (role in ('host','member'))`. **`alter table club_members` appears exactly once in the whole migration set** — `0030:119`, `enable row level security`. The table has never gained a column | ✅ CONFIRMED |
| `club_join` is unconditional | `0048:197-204`: `not_signed_in` if uid is null, `not_found` if the club row is absent, then `insert … on conflict do nothing`. No status, no ban, no invite, no approval | ✅ CONFIRMED |
| The reject arm was the only exclusion mechanism | `0084:625-631` — `if not p_approve then update session_dogs set approval = 'rejected' … return null`. It excluded a **dog's delegation application**, never a person | ✅ CONFIRMED, with one precision: even the retired arm could not remove a *person* |
| `backup_host_profile_id` treatment elsewhere | Two shipped patterns, split by kind — see §3 | ✅ CONFIRMED; the split is real and this slice follows it deliberately |

### Three findings the brief did not contain, all measured

**F-1. `no_show` has NO WRITER ANYWHERE.** Zero statements in `supabase/migrations/` set
`attendance = 'no_show'`. The value is written in exactly one place in the repository:
`supabase/tests/95_audit_gates_suite.sql:52`, a **fixture UPDATE**. So one of the three declared
attendance states is, in production, unreachable — and every pin that reads it today is reading a
state the lifecycle cannot produce, which is the fixture-reachability law
(`docs/contracts/club-return-address-arm-contract.md:243-246`) pointing at itself. §4 uses this:
giving `no_show` a real writer costs nothing and breaks no reader, because **every reader already
handles it correctly**.

**F-2. `session_people.attendance` is not a stats column. It is a GATE column, in two places where
being wrong has physical consequences.**

- `0047:92-94` — `session_propose_dog` refuses with `runner_not_checked_in` unless the target
  runner holds `attendance = 'checked_in'`. **A host who could write that value could place a live
  dog with a runner who never opened the app.** A runner's own check-in is that runner's consent
  to receive dogs, not merely evidence of their body.
- `0047:328-330` — `club_assume_host` refuses with `host_present` while the host holds
  `attendance = 'checked_in'`. **Attendance is an input to a control-transfer gate**, so anything
  that can *clear* the host's attendance can hand the session to the backup host. This is what
  turns "you cannot remove the host" from politeness into a privilege-escalation guard (§4, R2).

**F-3. The host's own trust card is computed from this column.** `club_host_stats` (latest
definition `0116:659-688`, superseding `0031:66`) returns `totalTeams` and `returning` from
`sp.attendance = 'checked_in'` (`0116:673,676`); `club_my_stats` (`0031:43-63`) returns another
person's `attended` count and `streak` from the same predicate. **A host who can write attendance
writes their own trust score and other people's streaks.** That is a direct incentive conflict and
it is why §4's verify arm is *additive only*, never a no-show writer, and why it records **who
asserted the fact**.

### The read surface the ask needs already exists

`club_session_roster` (`0053:392-449`, superseding `0049:195`) already returns, per person,
`profileId · name · role · attendance · runnerCap · isHost · isBackup · isMe · phone`, gated on
`_club_shell_access` (`0053:400-404`). **Sean's 「perhaps the list?」 is already rendered; only the
writer is missing.** This slice adds the writer and three fields to that payload — it does not
build a new list.

---

## 2. Object ownership (REGISTRY silent-collision law)

**NEW objects** (nothing in the repo creates or replaces any of these):

- columns `session_people.checked_in_by`, `.removed_by`, `.removed_at`, `.removed_reason`
- `session_host_mark_present(uuid, uuid)`
- `session_host_unmark_present(uuid, uuid)`
- `session_host_remove(uuid, uuid, text)`
- `_club_session_authority(uuid, uuid)` — internal, server-only EXECUTE

**EXTENDED** — each names the version it builds on:

- `club_session_roster(uuid)` ← **0053 §7** (`0053:392`; supersedes `0049:195`). Three fields added
  to the people objects. Nothing removed, nothing reordered.
- `club_session_detail(uuid)` ← **0053 §6** (`0053:351`; supersedes `0052:167` ← `0036:5` ←
  `0031:80` ← `0030:277`). One field added to each person object (§4, the display-honesty term).

**Deliberately NOT touched, each named and each with its reason:**

| Object | Why not |
|---|---|
| `session_checkin` (`0030:245`) | The wide `session_dogs` stamp at `0030:258-259` is **S4's** (spec v2 §7.4; `club-rsvp-hardening-contract.md` §4.3 names it a money defect). This slice must not go near it — see §5 |
| `session_propose_dog` (`0047:69`) | F-2's hole is closed **inside the new RPC** instead (§4, R-V3), so the custody path takes zero edits |
| `club_assume_host` (`0047:319`) | Closed by refusal R2 instead, same reason |
| `session_cancel_delegation` (`0124:38`) | The money ladder. Removal REFUSES rather than calling it — §5 |
| `session_assignment_revoke` (`0057:158`) | The host's existing dog tool, and its `already_handed_off` guard (`0057:172-174`) must not gain a back door |
| `club_finish_session` (`0118:1102`) | The no-show money gate (`0118:1245-1249`) is untouched and unread by this slice |
| `session_cancel_rsvp` (`0052:205`) | **⚠ CLAIMED BY ANOTHER CONTRACT.** `docs/contracts/club-rsvp-hardening-contract.md` §D adds an `already_checked_in` gate to it. See §8 |
| `_club_total_dogs` (`0048:78`), `_club_dogs_unresolved` (`0045:328`), `_club_runner_load` (`0047:52`) | Read, never written; §4 relies on their measured predicates |

**Discipline for every function this migration writes:** SECURITY DEFINER · `set search_path =
public, pg_temp` **in the body**, never ALTER-applied (`create or replace` resets an ALTER config —
98 H1, `98_hardening_suite.sql:50-63`, sweeps the whole `public` schema) · explicit
`auth.uid() is null` → `not_signed_in` first · **party gate before state gate** (0116 §D ⓐ) ·
explicit `revoke execute … from public, anon` **in this file** followed by
`grant execute … to authenticated`, never relying on grant preservation (CLAUDE.md's
create-or-replace law; `check-definer-acl.mjs` is a commit gate) · every NULL-capable term written
`exists (…)` / `is distinct from` / `coalesce(…, false)`, never `not (uid in (a, b))`.

**Numbers come from the remote tip at authoring time, not from this file.** At the moment of
writing, `origin/redesign-v4` holds migrations through **0128** and suites through **162**, and
this worktree additionally holds an unpushed local `0129`. Re-resolve both, two-sided (row AND
file, across all remote branches), and write the REGISTRY in-flight row **before** authoring.

---

## 3. The party gate — one gate, both arms

**The shipped treatment of `backup_host_profile_id` is two patterns, split by kind. Measured:**

| Pattern | Where |
|---|---|
| **Host only** (`s.host_profile_id <> auth.uid()` → `not_host`) | `session_propose_dog` `0047:80` · `session_assignment_revoke` `0057:167` · `club_set_backup_host` `0047:308` · `club_approve_dog` `0084:622` · `club_finish_session` `0118:1115-1118` |
| **Host or backup** (`exists (… auth.uid() in (host, backup))`) | `_club_shell_access` `0049:11-13` · `club_incident_resolve` `0052:453` · `club_incident_settle` `0072:122-124` · `club_incident_settle_quote` `0116:437-438` · `club_incident_subjects` gates `0067:98,112` · roster `0053:419,427,443` |

The line is legible: **routine session administration is host-only; incident and safety
adjudication admits the backup.**

**Ruling for this slice: BOTH arms admit host and backup host — ONE gate, one token.**

Four reasons, in order of weight:
1. Removal is a **safety** act, and safety adjudication is the family that already admits the
   backup (`0067`, `0072`, `0116`).
2. The backup host is the person who is physically there when the host is not — that is what
   `club_assume_host` (`0047:319`) exists for. A verify affordance the on-site authority cannot
   use is a dead button in the only situation it is needed.
3. `_club_shell_access` (`0049:11-13`) **already treats them as one authority class**, and the
   roster this feature draws on (`0053:400-404`) is gated by exactly that function. Splitting the
   write authority from the read authority would be inventing a third pattern.
4. The two escalation risks a shared gate creates are both closed by explicit refusals — R2
   (neither host may be removed) and R-V3 (a committed runner's check-in must be first-person).
   **Those refusals become load-bearing rather than decorative**, which is the honest place to put
   the safety.

🔵 **Reversible in one predicate and one pin** if Sean wants host-only: drop the backup term from
`_club_session_authority` and flip pin `P3`.

**The gate, written once:**

```
create or replace function _club_session_authority(p_session uuid, p_profile uuid) returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select case
    when exists (select 1 from club_sessions s where s.id = p_session
                 and p_profile in (s.host_profile_id, s.backup_host_profile_id)) then 'host'
    else 'none'
  end;
$$;
revoke execute on function _club_session_authority(uuid, uuid) from public, anon, authenticated;
```

⚠ **The `exists` wrapper is the whole point and it was earned, not copied.** `0116:410-412`,
`0072:117-122` and `0058` F1 all record the same measured fail-open: `auth.uid() in (host, NULL)`
collapses to **NULL** for an unrelated caller, `not (NULL)` never fires, and the gate opens. Inside
`exists`, a NULL predicate is "no row". `110 S2` caught this shape reproduced two migrations after
the file that sealed it. Never write the bare form. Pin `P4` asserts it with a NULL backup host.

**Common preamble for all three RPCs, in this order:**

1. `auth.uid() is null` → `not_signed_in`
2. `select * into s from club_sessions where id = p_session for update` → **`not_found`** if
   absent. Safe to answer distinctly: `club_sessions` is `for select using (true)` (`0030:133`),
   so session existence is already public and this discloses nothing new. The reason goes in the
   body comment.
3. **PARTY GATE** — `if _club_session_authority(p_session, auth.uid()) <> 'host' then raise
   exception 'not_host'`. `not_host` is the token every host-gated club RPC already raises
   (`0047:80`, `0057:167`, `0084:622`), so no client learns a new word.
4. **PARTY GATE OVER THE NAMED SUBJECT** — `select … into sp from session_people where session_id =
   p_session and profile_id = p_profile`; absent → **`not_joined`**. This is before every state
   gate, per 0116 §D ⓐ. It is not an enumeration oracle: step 3 has already established the caller
   administers this session, so they are entitled to know who is in it — they can read the same
   fact from `club_session_roster` (`0053:392`). The justification goes in the body.
5. Then, and only then, the state gates in §4.

---

## 4. The three arms

### §A — `session_host_mark_present(p_session uuid, p_profile uuid)`

**What it writes: exactly one row, in exactly one table, three columns.**

```
update session_people
   set attendance = 'checked_in', checked_in_at = now(), checked_in_by = auth.uid()
 where session_id = p_session and profile_id = p_profile;
```

**Nothing else. In particular it does NOT touch `session_dogs`. That is the money boundary — see §5.**

#### Is host-marked attendance the same value as self-check-in? — ARGUED

**Answer: the same `attendance` VALUE, a distinguishable FACT, carried in a new column
(`checked_in_by`) rather than a new enum member.**

The alternative — a fourth `attendance` value, e.g. `host_verified` — was considered and
**rejected on measurement**. Fourteen shipped predicates read this column, and they split into two
shapes:

- `attendance = 'checked_in'` — `0031:50,54,71,74,116,126` · `0047:93,330` · `0045:355,364` ·
  `0048:372,408,417` · `0116:673,676` · `0118:1131,1145`
- `attendance <> 'no_show'` — `0030:205,314` · `0048:170,361` · `0049:15` · `0051:22`

A fourth value is **admitted** by every negative reader and **excluded** by every positive one, in
a pattern nobody chose. That is `0119`'s own lesson made concrete — *a negative match admits any
enum value added later* (`154` G-header, quoted in `club-rsvp-hardening-contract.md` §A) — and it
would silently split the recap from the seat count. A new column changes **zero** readers.

**But the fact must be distinguishable, and here is why it is not a nicety:**

| Consumer | What a host-written value would do |
|---|---|
| `club_host_stats` `0116:673,676` | The host writes their **own** `totalTeams` and `returning` trust card (F-3) |
| `club_my_stats` `0031:50,54` | The host writes another person's `attended` count and `streak` |
| `club_finish_session` `0118:1130-1146` | `v_teams` drives a **public `feed_posts` row** (「N팀이 함께 달렸어요」) and a notification to every counted person |
| `session_propose_dog` `0047:92-94` | **A live dog placed with a runner who never opened the app** (F-2) |
| `club_assume_host` `0047:328-330` | An input to a control-transfer gate (F-2) |

`checked_in_by` makes each of those answerable. This slice **consumes it in exactly one place**
(R-V3 below) and leaves the rest as an honest, queryable distinction for the surfaces that need it.
It also — deliberately — creates the durable per-person attendance fact that `0118:1207-1224`'s
**named OPEN RESIDUAL** says the schema lacks. Wiring it into a fee gate is **NOT this slice** (§7).

#### Refusals, each decided

| # | Shape | Token | Why |
|---|---|---|---|
| R-V1 | caller is not host/backup | `not_host` | §3 |
| R-V2 | target holds no `session_people` row | `not_joined` | §3 step 4 |
| R-V3 | **target holds a committed `session_runner_assignments` row** (`status = 'committed'`, `0037:106`) | `runner_self_checkin_required` | **F-2's hole, closed here instead of in the custody path.** `0047:92-94` treats a runner's check-in as that runner's *consent to receive dogs*. A third party cannot consent for them. Closing it here costs zero edits to `session_propose_dog` |
| R-V4 | target already `checked_in` | **no-op, returns success** | Idempotent by design: a host tapping 확인 twice on a flaky connection must not see an error, and the row is already in the asserted state. **It does NOT overwrite `checked_in_by`** — a self-check-in stays a self-check-in forever (`P7`) |
| R-V5 | target `attendance = 'no_show'` | `already_removed` when `removed_by is not null`; **succeeds** when `removed_by is null` | A removed person is not re-admitted by a verify tap — that would be removal with an undo button the ruling did not grant. A true no-show (no writer today, F-1) is correctable |
| R-V6 | session `status not in ('open','full')` | `session_closed` | Once `club_finish_session` has run, the recap is published (`0118:1136-1140`) and a feed post exists. Rewriting attendance afterwards changes a published number |
| R-V7 | `now() < s.scheduled_at - interval '2 hours'` | `checkin_window` | **Byte-identical to the lower bound `session_checkin` already enforces** (`0030:250-252`). A host cannot certify tomorrow's attendance today. ⚠ The UPPER bound (`+6 hours`) is deliberately **not** copied: R-V6 is the honest ceiling, because a host who finishes late must still be able to correct the sheet before publishing it |
| R-V8 | null uid | `not_signed_in` | §3 step 1 |

### §B — `session_host_unmark_present(p_session uuid, p_profile uuid)`

**A one-way host write with no undo is an inescapable state**, which is precisely what round-1 F2
found design-breaking in spec v2 and what the no-dead-buttons law forbids. A mis-tap on a roster is
not hypothetical.

```
update session_people
   set attendance = 'rsvp', checked_in_at = null, checked_in_by = null
 where session_id = p_session and profile_id = p_profile
   and checked_in_by is not null;
```

| # | Shape | Token |
|---|---|---|
| R-U1 | `checked_in_by is null` (a **self** check-in) | `not_host_verified` |
| R-U2 | `checked_in_by <> auth.uid()` | **allowed** — the acting host may correct the backup's tap and vice versa; both are the same authority class (§3), and a two-host session where each can only undo their own taps is a deadlock waiting to happen |
| R-U3 | session not `open`/`full` | `session_closed` |
| R-U4 | target holds a live delegation or is a responsible party for any dog | `custody_active` — same predicates as R5 in §C. Un-verifying someone whose dog is mid-custody would drop them out of `presentRunners` (`0048:369-371`) and `session_propose_dog`'s gate while they are holding an animal |

**Nulling `checked_in_at` is safe here and ONLY here** because the row was never self-stamped: the
`checked_in_by is not null` conjunct is what guarantees it. A self-check-in's timestamp is durable
evidence that survives an attendance move — `club-rsvp-hardening-contract.md` §D5 pins exactly that
shape — and nothing in this slice may launder it.

### §C — `session_host_remove(p_session uuid, p_profile uuid, p_reason text)`

#### What removal MEANS mechanically

**The `session_people` row STAYS and gains a state. It is not deleted.** Three measured reasons,
the first of which is decisive:

1. **A DELETE is undone by the removed person in one tap.** `session_rsvp`'s `already_joined`
   (`0048:181-186`) fires only on the surviving `unique (session_id, profile_id)` row (`0030:76`).
   Delete the row and the person can immediately RSVP again. **Removal-by-deletion is not
   removal.** The surviving row is what makes Sean's 「one walk」 mechanically true — and it is also
   what makes it *only* one walk: the next session is a different row, so nothing carries forward.
   That is the ruling, expressed as a constraint rather than as a policy someone must remember.
2. **A DELETE destroys a run record.** `participant_activities.person_id` is
   `references session_people on delete cascade` (`0030:104`), and `session_checkin` writes a
   `checkin_only` activity row (`0030:262-264`). The person was there; that fact is not the host's
   to erase.
3. It matches the direction the family is already moving: `0052:213-217` refuses to delete over an
   active delegation, and `club-rsvp-hardening-contract.md` §D refuses to delete after check-in.

#### The state value: `no_show` + a `removed_by` triple. ARGUED.

```
update session_people
   set attendance = 'no_show', removed_by = auth.uid(), removed_at = now(),
       removed_reason = p_reason
 where session_id = p_session and profile_id = p_profile;
-- checked_in_at and checked_in_by are NOT touched.
update club_sessions set status = 'open' where id = p_session and status = 'full';
```

**Why `no_show` and not a new `removed` value.** F-1 measured that `no_show` has **no writer
anywhere in the schema** — so giving it one breaks nothing — and every one of the twenty shipped
readers already does the right thing for a removed person, with **zero reader edits**:

| Reader | Effect of `no_show` | Correct? |
|---|---|---|
| `session_rsvp` seat count `0048:170` | the seat is freed | ✅ the ruling's point |
| `club_overview` / `next_session` rsvpCount `0030:314`, `0051:22` | count drops | ✅ |
| `_club_shell_access` `0049:15` | `'full'` → `'limited'`/`'none'` — chat, roster and phone access drop (`0053:400-404`) | ✅ removal means out of the room |
| `club_session_viability` `0048:361,369-371` | `v_teams` and `presentRunners` drop | ✅ |
| `session_propose_dog` `0047:92-94` | the removed person can receive no new dogs | ✅ |
| `club_finish_session` `0118:1130-1146` | excluded from the recap count and the notification | ✅ |
| `club_my_stats` / `club_host_stats` `0031:50,54`, `0116:673,676` | no attended credit, streak breaks | ✅ decided: a removed walk is not an attended walk |
| `session_rsvp` re-join `0048:181-186` | `already_joined` — removal sticks | ✅ |

The alternative — widening the `attendance` CHECK with `'removed'` — requires editing **five**
shipped functions across `0030`/`0048`/`0049`/`0051` (every `<> 'no_show'` predicate becomes
`not in ('no_show','removed')`), one of them the viability function the board reads. That is a wide
blast radius on shipped money-adjacent code to buy a word.

⚠ **The word is bought anyway, in its own column.** `removed_by is not null` is what distinguishes
「호스트가 이번 산책에서 제외했어요」 from 「미참석」, and **the two must never be shown as the same
thing** — that is the display-vocabulary law (CLAUDE.md: *when display vocabulary flattens server
states, gate logic and badges on `rawStatus`*). So `club_session_roster` and `club_session_detail`
**gain the distinguishing fields in THIS migration**, not later:

- roster people objects (`0053:425-431`) gain `checkedInBy`, `removedBy`, `removedAt`
- `club_session_detail` people objects (`0053:371`) gain `removed` (boolean, `removed_by is not
  null`) — the detail screen is read by non-hosts, so it gets the boolean, never the actor's id

Publishing a removed person to the whole roster as 미참석 would be a shipped lie; shipping the
server fields and no copy would be the same lie with an alibi. **The Korean copy is client work
(§7) and it lands in the same slice.**

#### What happens to their dog

**`owner_handled` (동반) rows: ENDED, not deleted.**

```
update session_dogs
   set service_state = 'ended', completion_outcome = 'no_service',
       termination_type = 'cancelled', cancelled_by = 'host'
 where session_id = p_session and owner_profile_id = p_profile
   and custody = 'owner_handled' and service_state is distinct from 'ended';
```

Every value here is already legal vocabulary — `0040:16-24` declares `completion_outcome in
('completed','partial','no_service')`, `termination_type in (…,'cancelled',…)` and **`cancelled_by
in ('owner','host','runner','system','ops')`**. `'host'` was already a permitted actor; this slice
is the first thing to write it. **No new column on `session_dogs`.**

`'ended'` is the right state and not merely a convenient one, measured:
- `_club_total_dogs` (`0048:78-82`) counts `service_state is distinct from 'ended'`, so the dog cap
  slot is released — the shared pool stays honest.
- `session_dogs_active_uni` (`0043:29-31`) is partial on the same predicate, so the owner could
  bring that dog to a *different* session.
- `_club_dogs_unresolved` (`0045:328-336`) counts only `custody = 'runner_delegated'`, so an ended
  companion row cannot block `club_finish_session`.
- `session_cancel_rsvp` **deletes** these rows (`0052:218-219`). This slice deliberately diverges:
  a self-cancellation is a person changing their mind, a removal is a record of something that was
  done to them, and the row is the only place that record can live.

**`runner_delegated` rows: NEVER. The removal refuses instead.** See R5 and §5.

#### Refusals, each decided

| # | Shape | Token | Decision and reason |
|---|---|---|---|
| **R1** | **removing yourself** (`p_profile = auth.uid()`) | `cannot_remove_self` | The self door is `session_cancel_rsvp` (`0052:205`) and it carries three gates — `host_cannot_leave` (`:211`), `delegation_active` (`:213-217`), and (pending) `already_checked_in`. A self-removal through the host door launders past all three. Also: this refusal is subsumed by R2 for the host, but is written **separately and first** so it still holds if R2's predicate is ever narrowed |
| **R2** | **removing the host or the backup host** (`p_profile in (s.host_profile_id, s.backup_host_profile_id)`, written NULL-safely) | `cannot_remove_host` | **Two reasons, one of which is a privilege escalation.** ① `club_assume_host` (`0047:328-330`) refuses a takeover while the host holds `attendance = 'checked_in'`; since this slice admits the backup host (§3), a backup who could set the host to `no_show` would **seize the session**. ② `club_finish_session` (`0118:1114-1118`) is keyed to `host_profile_id = auth.uid()`, and the host's `host_runner` row is written at session creation (`0037:380`); removing it strands the session's own recap arithmetic. ⚠ **This refusal is why §3's shared gate is safe. If it is ever weakened, §3 must be re-argued** |
| **R3** | **removing someone already checked in** | **ALLOWED** | A safety removal happens *at the meetup*, after everyone has arrived. Refusing after check-in would make the feature useless in the only scenario that motivates it. **`checked_in_at` is preserved and never nulled** — the person physically arrived, that fact is not erasable, and `club-rsvp-hardening-contract.md` §D5 already pins the "checked in then marked no-show" shape as legitimate. What changes is the seat, the shell access and the credit |
| **R4** | **removing after the run started** | **ALLOWED while `status in ('open','full')`; `session_closed` otherwise** | There is no `'started'` status — `club_sessions.status` is `open`/`full`/`done`/`cancelled` (`0030:62`) and only `club_finish_session` writes `done`. The honest line is the host's own finish: once `done`, `club_my_stats` (`0031:47`) counts the session, a `feed_posts` row exists (`0118:1136`) and every counted person has been notified (`0118:1143-1146`). A post-hoc removal would rewrite a published recap. ⚠ **NAMED RESIDUAL: this permits removing someone while the pack is out.** Removal is an **administrative** act — a record, a seat, and room access. It does not physically remove anyone and the product must not imply that it does; if the person is holding a dog, R5 refuses. The copy must say what it does and what it does not |
| **R5a** | **target owns a live delegation** — `exists (select 1 from session_dogs where session_id = p_session and owner_profile_id = p_profile and custody = 'runner_delegated' and service_state is distinct from 'ended')` | `delegation_active` | **THE MONEY REFUSAL — see §5.** Same predicate and same token as `session_cancel_rsvp` (`0052:213-217`), deliberately, so one word means one thing |
| **R5b** | **target is the responsible party for any live dog** — `exists (select 1 from session_dogs where session_id = p_session and responsible_profile_id = p_profile and custody = 'runner_delegated' and coalesce(custody_phase,'') <> 'resolved')` | `custody_active` | `0030`'s stated invariant is 「모든 강아지는 항상 명시적 책임자 1명」 (`0030:3`, `responsible_profile_id NOT NULL`). Removing the responsible party leaves a live dog answerable to someone who is no longer in the session. The host's tool for this is `session_assignment_revoke` (`0057:158`), which itself refuses `already_handed_off` (`0057:172-174`) — **removal must not be a back door around that refusal** |
| **R5c** | **target is a committed runner with load > 0** — `_club_runner_load(p_session, p_profile) > 0` (`0047:52-64`) | `custody_active` | Catches the proposal window R5b misses: `_club_runner_load` counts *proposed-and-unexpired* dogs (`0047:57-60`) that have no `responsible_profile_id` yet. The host must revoke or let the proposals lapse first |
| **R6** | committed runner, **load zero** | **ALLOWED, and `session_runner_assignments` is NOT touched** | Measured: every gate that consumes a commitment also reads attendance — `club_session_viability`'s `presentRunners`/`v_headroom` aggregate requires `attendance = 'checked_in'` (`0048:369-371`), and `session_propose_dog` requires it (`0047:92-94`). Setting `no_show` already removes them from both. Writing a second table would be a change with no consumer. **`P12` pins this rather than asserting it** |
| **R7** | target holds an **open incident** as case owner or subject | `incident_open` | Mirrors `session_cancel_delegation` (`0124:69-76`). Removing a party mid-case drops their `_club_shell_access` to `'limited'` (`0049:15`) and with it their view of the case that names them. ⚠ Predicate joins `club_incident_subjects` on `subject_type = 'dog'` for dogs this person owns **and** `club_incidents.case_owner`; see `0067` for the shape |
| **R8** | target not in the session | `not_joined` | §3 step 4 |
| **R9** | target already removed (`removed_by is not null`) | **no-op, returns success** | Idempotent. `removed_reason` and `removed_at` keep the FIRST removal's values — the record is of the act, and a second tap is not a second act |
| **R10** | non-host caller / null uid | `not_host` / `not_signed_in` | §3 |

**Gate order, complete, for `session_host_remove`:**
`not_signed_in` → `not_found` → `not_host` → `not_joined` → `cannot_remove_self` →
`cannot_remove_host` → `session_closed` → `delegation_active` → `custody_active` →
`incident_open` → (already-removed no-op) → writes.

Party over the subject before every state gate. `cannot_remove_self` and `cannot_remove_host`
precede `session_closed` because they are **structural** — they are never resolvable by waiting,
and answering a resolvable refusal first sends a host to fix something that will not help. Same
reasoning, and the same precedent, as `club-rsvp-hardening-contract.md` §D's terminal-before-
resolvable ordering.

`p_reason` is `text`, nullable, stored verbatim, **never rendered to the removed person by this
slice** and never used in a predicate. It exists because a removal with no recorded reason is an
unauditable act, and because whatever strike policy Sean eventually rules will need to read
something. Whether the removed person is told anything at all is **OPEN — SEAN, Q3**.

---

## 5. 🔴 MONEY — read this section before writing a line

**This slice mints no fee, cancels no booking, refunds nothing, and writes no ledger row. It holds
that property BY REFUSAL, and the refusal is the design.**

**The defect it is refusing to become.** If `session_host_remove` cancelled a removed owner's
delegation, the only shipped path is `session_cancel_delegation` (latest `0124:38`), whose ladder
(`0124:100-111`) prices `post_acceptance` at `club_cfg_required('cancel_post_accept_pct')` — **20%,
charged to the OWNER**, recorded with `cancel_reason = 'club_owner_cancel'` (`0124:118`) and a
notification reading 「위탁 취소가 접수됐어요 — 취소 수수료 N%가 결제 예정으로 기록됐어요」
(`0124:128-131`). **A host tap would bill an owner 20% under a reason naming the owner as the
canceller.** That is a money defect of the worst available shape: wrong payer, wrong attribution,
wrong copy, initiated by a third party. R5a exists to make it unreachable.

**The second defect it is refusing to become — the verify arm.** `session_checkin` (`0030:258-259`)
stamps `session_dogs.checked_in_at` for **every** dog the caller is responsible for. That column is
one of the two terms in the 0118 no-show fee's attendance gate:

```
and now() >= s.scheduled_at
and not exists (select 1 from session_dogs sd where sd.booking_id = b.id and sd.checked_in_at is not null)
and b.owner_confirmed_handoff_at is null;                                    -- 0118:1245-1249
```

**If `session_host_mark_present` mirrored that stamp, a host would gain unilateral power to
suppress — or, by not tapping, to leave standing — a 20% no-show fee against an owner.**
`session_host_mark_present` therefore **writes to `session_people` and to nothing else**, and pin
`P6` measures a whole-table row-and-column diff over `session_dogs` and `bookings` across the call.
This is the entire reason §A's write is specified column-by-column instead of "mark them present".

**The genuinely useful thing this creates, and does NOT spend.** `0118:1207-1224` names an
**OPEN RESIDUAL**: a delegation-only owner who confirmed handoff and was then reassigned is
「byte-identical to one who never came」 and gets charged 20%, because `owner_confirmed_handoff_at`
is nulled by six functions and 「closing it needs a durable 'this owner attended' fact that the
reassignment paths do not reset, which is a new column and a product decision about what the stamp
means」. `session_people.checked_in_at` + `checked_in_by` **is** such a fact, and nothing in this
slice resets it. **Wiring it into the fee gate is explicitly NOT this slice** — it is a money-path
change, it belongs with spec v2 §7.4's per-pairing evidence redesign (S4), and it must go through
the money-path review with the money canon open. Named here so the next reader finds the hook
instead of rebuilding it.

**🔴 REQUIRED PROCESS.** This migration touches `session_dogs` (the companion-row end) and sits one
predicate away from three fee paths. Per CLAUDE.md, **`/autoplan` is the standing gate for any
migration or money-path change**, and the full adversarial cycle applies: scout → contract →
implement → adversarial review where reviewers EXECUTE attacks → mutation-verified pins → verify.
**A reviewer's first assignment is to attack §5's two refusals**, not the happy path.

---

## 6. Suite plan — propositions first, then the battery

New suite (number resolved from the remote tip at authoring; ≥163 at the time of writing).

🔴 **Governing fixture rule** (`club-return-address-arm-contract.md:243-246`): *a fixture must be
REACHABLE BY THE LIFECYCLE, not merely constructible by an INSERT.* Every fixture below is driven
through the real RPC chain — `club_create_session` → `session_rsvp` → `session_delegate_dog` →
`club_approve_dog` → `session_propose_dog` → `session_proposal_respond` → `session_checkin` — and
any state that cannot be reached that way is either not a real state or the pin is testing a
fiction. ⚠ **`attendance = 'no_show'` is the trap**: `95:52` reaches it by direct UPDATE because
nothing else could (F-1). After this slice `session_host_remove` is the lifecycle path, and **every
new pin must reach it that way**; a fixture UPDATE would be pinning the pin.

**Each pin states its own proposition in-file, without reference to any mutation.**

### Party and shape

| Pin | Proposition |
|---|---|
| `P1` | The named host can mark a participant present; the row changes and `checked_in_by` = the host |
| `P2` | A signed-in stranger, a plain member, and an `owner_attending` participant each get `not_host` and write zero rows |
| `P3` | The **backup host** can mark present and can remove (§3's ruling, made behaviour) |
| `P4` | With `backup_host_profile_id` **NULL**, an unrelated caller gets `not_host` — the `exists` NULL-safety, both directions (`0116:410-412`'s measured fail-open) |
| `P5` | Anon/null-uid → `not_signed_in`; a nonexistent session → `not_found`; a real session and a non-participant target → `not_joined`; each writes nothing |

### The money boundary

| Pin | Proposition |
|---|---|
| `P6` | 🔴 Across a successful `session_host_mark_present`, a **whole-schema before/after row-count diff** shows exactly one table changed, and within `session_dogs` and `bookings` **every column of every row is byte-identical** — in particular `session_dogs.checked_in_at`, `bookings.owner_confirmed_handoff_at`, `bookings.status`, `bookings.runner_id` |
| `P7` | A self-check-in via `session_checkin`, then `session_host_mark_present` on the same person → success, and `checked_in_by` is **still NULL** (R-V4: a host tap never relabels a first-person fact) |
| `P8` | 🔴 A removal attempt against an owner holding a `confirmed` delegated booking → `delegation_active`, and **zero rows in `club_fee_items`, zero in `bookings` changed, zero `notifications`**. The fee the shipped ladder *would* have minted is computed in-pin from `club_cfg` and asserted **absent** |
| `P9` | The same owner, after `session_cancel_delegation` runs legitimately (owner-initiated, free window), can then be removed — the refusal is about the live booking, not about the person |

### Removal mechanics

| Pin | Proposition |
|---|---|
| `P10` | After removal: the `session_people` row **exists**, `attendance = 'no_show'`, `removed_by`/`removed_at`/`removed_reason` set, `checked_in_at` **unchanged** (stamped if they had checked in), the `participant_activities` row **survives**, and `club_sessions.status` moved `full` → `open` |
| `P11` | The removed person calling `session_rsvp` on the same session → **`already_joined`** (removal sticks — the load-bearing consequence of not deleting), and calling `session_rsvp` on a **different** session of the same club → **succeeds** (「one walk」, made executable) |
| `P12` | A committed runner with load 0 is removed → `session_runner_assignments` row **unchanged**, and `club_session_viability`'s `presentRunners` **drops** anyway (R6's justification measured, not asserted) |
| `P13` | A removed participant's companion dog row: `service_state = 'ended'`, `completion_outcome = 'no_service'`, `cancelled_by = 'host'`; `_club_total_dogs` **decreases**; the same dog can then `session_rsvp` into another session (partial index released) |
| `P14` | `_club_shell_access` for the removed person drops from `'full'` to `'limited'`/`'none'`, and `club_session_roster` called by them raises `not_party` or returns `people = []` per `0053:400-404` |
| `P15` | `club_finish_session` after a removal: the removed person is absent from `v_teams`, absent from the recap notification set, and `club_my_stats.streak` for them breaks |

### Refusals

| Pin | Proposition |
|---|---|
| `P16` | Host removes themselves → `cannot_remove_self` (**not** `cannot_remove_host` — order proof) |
| `P17` | Backup host removes the host → `cannot_remove_host`, and `club_assume_host` **still** refuses with `host_present` afterwards (R2's escalation, closed and measured) |
| `P18` | Host removes the backup host → `cannot_remove_host` |
| `P19` | A checked-in participant is removed → **SUCCEEDS**, `checked_in_at` preserved (R3) |
| `P20` | A `done` session → `session_closed` for all three RPCs; a `cancelled` session likewise |
| `P21` | Runner holding a `picked_up` dog → `custody_active`; the same runner after the return seal → **removable** |
| `P22` | Runner holding only an unexpired **proposal** → `custody_active` (R5c — the window R5b misses); after `proposal_expires_at` passes → removable |
| `P23` | Target with an open incident → `incident_open`; after `club_incident_resolve` → removable |
| `P24` | Second removal of the same person → success, and `removed_at`/`removed_reason` hold the **first** call's values |

### Verify-arm refusals

| Pin | Proposition |
|---|---|
| `P25` | A committed runner → `runner_self_checkin_required`; the same runner after calling `session_checkin` themselves → the row is `checked_in` with `checked_in_by` NULL, and `session_propose_dog` then **succeeds** (F-2 closed, and the legitimate path proven still open) |
| `P26` | `now() < scheduled_at - 2h` → `checkin_window`; inside the window → succeeds; **after** `scheduled_at + 6h` but still `open` → **succeeds** (the deliberate divergence from `0030:250-252`, pinned as behaviour, not as a comment) |
| `P27` | Unmark of a **self** check-in → `not_host_verified`; unmark of a host-verified row → back to `rsvp` with both columns NULL; unmark by the *other* host → succeeds (R-U2) |
| `P28` | Unmark of someone holding a live dog → `custody_active` (R-U4) |
| `P29` | Verify on a removed person → `already_removed` |

### Standing invariants

| Pin | Proposition |
|---|---|
| `P30` | All four new functions: `prosecdef` true, `proconfig` exactly `search_path=public, pg_temp` **and proven to come from the body**; `anon` and `PUBLIC` hold no EXECUTE on any of them; `_club_session_authority` holds **no** `authenticated` EXECUTE (it takes a caller-supplied profile id with no party gate — `0116` §D's shape) |
| `P31` | `club_session_roster` and `club_session_detail` return the new fields, **and every pre-existing field of both is byte-identical** to its pre-slice value on an untouched session |
| `P32` | The `attendance` CHECK constraint is **unchanged** — still exactly `('rsvp','checked_in','no_show')`. A future session must not widen it without re-reading §4 |

### Mutation battery — each mutation names the pin that must redden

🔴 **Three propositions, not one** (CLAUDE.md): "the hole is real", "the pin notices", and "the fix
closes it" are different claims. For M1 and M2 — the money mutations — plant the failure **without**
the fix (does the hole reproduce?) **and** with it (is it closed?). **A control that cannot fail is
not a control.**

| # | Mutation | Must redden | Notes |
|---|---|---|---|
| M1 | 🔴 Replace R5a's refusal with a call to `session_cancel_delegation` | `P8` | **Run BOTH ways.** Unfixed, the pin must show a real `club_fee_items` row at 20% against the owner — the defect reproduced, not a pin's opinion of it. Fixed, `pub`-style assertion: zero fee rows |
| M2 | 🔴 Add `session_checkin`'s wide `session_dogs` stamp (`0030:258-259`) to `session_host_mark_present` | `P6` | Same both-ways discipline. Unfixed, the diff must show `session_dogs.checked_in_at` moving — and a paired probe must show the 0118 no-show fee for that booking flipping from minted to suppressed. That is the money consequence, measured |
| M3 | Change §3's gate to `if not (auth.uid() in (s.host_profile_id, s.backup_host_profile_id))` | `P4` | The `0058` F1 / `110 S2` fail-open, planted deliberately. If `P4` stays green the pin is testing nothing |
| M4 | Drop the backup term from `_club_session_authority` | `P3` | Proves `P3` measures the §3 ruling and not an accident |
| M5 | Drop R2's `backup_host_profile_id` term | `P18` and `P17` | Two pins, and `P17`'s second half (assume-host still refuses) is the escalation half |
| M6 | Delete R1 (`cannot_remove_self`) | `P16` | With R2 still present a host self-removal now answers `cannot_remove_host` — **`P16` must red on the TOKEN**, which is why it asserts the token and not merely "raises" |
| M7 | Change removal from `update … set attendance` to `delete from session_people` | `P10`, `P11` | `P11`'s `already_joined` is the pin the whole design decision rests on |
| M8 | Delete the `checked_in_at` preservation (null it on removal) | `P10`, `P19` | |
| M9 | Delete R5b (`responsible_profile_id` arm) | `P21` | |
| M10 | Delete R5c (`_club_runner_load` arm) | `P22` only | If `P21` also reds, the two arms are not disjoint and R5c is redundant — say so in the header rather than keeping a gate nobody needs |
| M11 | Delete R-V3 (`runner_self_checkin_required`) | `P25` | And a paired probe must show `session_propose_dog` then succeeding against a never-present runner — F-2's hole, reproduced |
| M12 | Delete R-V6/`R-U3` (`session_closed`) | `P20` | |
| M13 | Delete R-V7 (`checkin_window`) | `P26` first half; `P26` second half must stay GREEN | The divergence pin, both directions |
| M14 | Change the removal state to a new `'removed'` enum value (and widen the CHECK) | `P32`, and expect `P10`/`P14`/`P15` to move | **This mutation is the argument in §4 made executable.** Its red set is the list of shipped readers a future "simplification" would silently change. Record the exact set in the suite header |
| M15 | Delete `session_host_unmark_present` entirely | `P27` | |
| M16 | Delete the `checked_in_by is not null` conjunct in §B | `P27` first half | Proves §B cannot launder a self-check-in |
| M17 | Delete the roster/detail field additions | `P31` | |
| M18 | **CONTROL** — change only a comment | **nothing** | If any pin reds, the suite is order-dependent or leaking state between fixtures. ⚠ Verify the two arms of every control read genuinely different files (the symlink control that could not fail, 2026-08-25) |

**Every VERIFY assertion in the migration gets planted-and-broken once.** An assertion never seen
to fail is a claim, not a check.

---

## 7. What this does NOT do — explicitly

1. **No club-level exclusion.** No ban, no blocklist, no `status` on `club_members`, no change to
   `club_join` (`0048:197`). A removed person remains a member and can RSVP to the next session.
   That is Sean's ruling, not an omission — 「Host can remove someone from one walk」.
2. **No revival of host approval.** `club_approve_dog`'s reject arm (`0084:625`) stays retired.
   This slice does not gate entry; it acts on people who are already in.
3. **No money.** No fee, no refund, no ledger, no booking write, no `club_fee_items` row. §5.
4. **It does not close `0118`'s attendance residual** (`0118:1207-1224`). It creates the durable
   fact that could; spending it is S4's and needs the money-path review.
5. **It does not touch `session_checkin`** or the wide `session_dogs` stamp (`0030:258-259`). That
   defect is S4's (spec v2 §7.4) and this slice is not a partial fix for it.
6. **It does not physically remove anyone.** Removal is a record, a seat and room access. The copy
   must not imply a bouncer.
7. **It does not make host-verified attendance count as consent to receive dogs.** R-V3.
8. **It does not notify anyone.** Every existing club RPC writes `notifications` rows; this one
   writes none, deliberately, because **who is told about a removal and in what words is Q3**.
   Shipping a notification before that ruling would be the spec answering a founder question.
9. **No client work is included, and the slice is not shippable without it.** Named landing sites:
   `app/app/club/session/[sid].tsx` (the roster rows and the two host affordances),
   `app/src/lib/api.ts` (`SessionPerson` at `:3436` gains the three fields; three new RPC wrappers).
   Korean copy for 제외됨 vs 미참석 is required by §4's display-honesty term and **lands in the same
   commit** as the migration, per the 0127 precedent. **⚠ `api.ts` is a SHARED surface — claim it
   in the REGISTRY in-flight table and tell ui6 before editing.**
10. **It does not build a live map, a pass, or a session-level position feed.** D3
    (`docs/decisions/2026-08-25-console-rulings.md:512-527`) is unanswered and unrelated.

---

## 8. Collision surface — read before authoring

**`docs/contracts/club-rsvp-hardening-contract.md` §D edits `session_cancel_rsvp` (`0052:205`) to
add an `already_checked_in` gate on `checked_in_at is not null`.** That contract is written and, at
the time of writing, holds no REGISTRY in-flight row. Three interactions, all real:

1. **This slice makes that gate reachable by a third party.** After §A, a host tap stamps
   `checked_in_at`, and the removed-from-cancelling person is someone the host put in that state.
   **Whether a host-verified check-in should block the participant's own cancellation is a genuine
   design question** — and the honest answer is that it should NOT: `already_checked_in` exists
   because *you were physically there*, and a host's assertion is not that. **The gate should read
   `checked_in_at is not null and checked_in_by is null`.** Whichever contract lands second owns
   that conjunct, and it must be pinned in that slice, not assumed here.
2. Both slices add gates to functions in the same family and both claim `club_session_detail`'s
   people payload indirectly. Sequence them; do not build in parallel.
3. `club-rsvp-hardening-contract.md` §C's new `session_add_my_dog` writes an `owner_handled` row.
   §C of *this* contract ends such rows on removal. No conflict, but the pin sets overlap — the
   later suite should re-pin the earlier property rather than assume it.

**Also in flight, from the REGISTRY:** the 맹견-removal client half claims
`app/app/club/session/[sid].tsx` and four named symbols in `app/src/lib/api.ts` for the
`club-delegation-spec-v2-a41fbc` tree. This slice's client half touches the same two files.

---

## 9. OPEN — SEAN

Four, each answerable in one sentence. **None of them blocks writing the migration**; Q1 and Q3
block the client half.

**Q1 — Can a host remove a DOG that is being walked by a runner, or only a PERSON?**
Sean's words were 「remove someone from one walk」 and the spec's OPEN-D asked about 「a dog or a
person」. This contract implements **people only**, and refuses (`delegation_active`) when the
person has a live delegation — because cancelling it would bill that owner 20% (§5). If he wants
a host to be able to send a *dog* home, that is a different mechanism with its own money answer.
*One-sentence answers: "people only" · "dogs too — and the owner pays nothing" · "dogs too — and
the owner pays the normal cancel fee".*

**Q2 — Should the host be able to mark someone ABSENT (no-show), or only PRESENT?**
This contract is **present-only**: absence is the default and nothing today writes `no_show` (F-1).
A host-marked no-show would be a distinct claim about a person, and once any fee gate reads it, it
is money.
*One-sentence answers: "present only" · "let the host mark no-show too".*

**Q3 — Is the removed person told, and in what words?**
This contract writes **no notification**, deliberately. Every other club RPC notifies. The options
are silence, a neutral line (「이번 세션 참여가 종료됐어요」), or the host's reason relayed verbatim
— and the third has a harassment surface.
*One-sentence answers: "say nothing" · "neutral line" · "tell them the reason".*

**Q4 — Should the backup host hold both powers, or only the host?**
This contract gives both to both (§3), on the reasoning that the backup is the person who is
actually on site and that safety adjudication already admits them (`0067`/`0072`/`0116`) — with
`cannot_remove_host` closing the takeover path. The alternative is host-only, reversible in one
predicate.
*One-sentence answers: "both" · "host only".*

---

## 10. Provenance

- Sean, `docs/plans/2026-08-25-round6-picks-and-live-map.md:16-17` (verify) ·
  `docs/decisions/2026-08-25-console-rulings.md:278,288-290` (removal, 09:04:13Z)
- The measurement that started it: `docs/decisions/2026-08-25-console-rulings.md:507-516` (D2)
- Spec v2 OPEN-D, `docs/plans/2026-08-25-club-delegation-spec-v2.md:1524-1531`
- Adjacent contract: `docs/contracts/club-rsvp-hardening-contract.md`
- Money canon: memory `daengrun-money-models.md` — **open it before the review, not after**
