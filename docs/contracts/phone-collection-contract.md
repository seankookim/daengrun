# Phone collection at onboarding. Contract.

**Status:** contract only. No migration, no client code, no suite is written by this document.
**Written:** 2026-08-26. Every citation below was read at source; the production figures were
measured with `db query --linked` on the same day and are labelled where they appear.

**Why now.** Sean, verbatim (round-6 plan on trunk; console cards `phone-policy` /
`phone-required` at 2026-08-26T01:46–01:47Z), recorded in
`docs/decisions/2026-08-25-console-rulings.md` tenth and eleventh rounds:

> "i think we should have the owner and any new person insert phone number on onboarding for
> safety and contact purposes"

and, to the two follow-ups: the 개인정보처리방침 wording → **"Add it to the lawyer email"**;
phone at signup → **"Required"**, with the comment **"the existing ones are fake so it's fine."**

---

## 0. This is NOT a reversal of the earlier refusal. Read this section before the rest.

`app/src/lib/api.ts:3126-3127` (verified verbatim at source):

> ⚠ 연락처는 묻지 않는다. profiles.phone 은 전원 NULL 이고 읽는 화면이 없다 — 받아두기만 하는
> 필드를 묻는 건 넛지가 아니라 수집이고, §12 가 전화 버튼을 거부한 것과 같은 이유다.

The refusal's stated ground is **「받아두기만 하는 필드」 — a field nobody reads.** It was
**conditional on the absence of a reader**, and the condition is now false three times over:

1. Sean names **safety** and **contact** as purposes.
2. The club return flow is a third reader — and its policy shipped 15 months of migrations ago
   (§1).
3. Measured this hour: `club_phone_access_log` holds **0 rows**, `profiles` holds **10 rows with
   0 non-null phones**. The reader exists in code and has *never once fired*, precisely because
   the data was withheld.

So the record must read **"the field acquired the purpose it lacked"**, not "a founder overrode a
privacy call". Any future reader of this slice who concludes the latter has been misled by the
diff. The implementing migration and the client change both carry a pointer back to this section;
`api.ts:3126-3127` is rewritten in place to say *why the condition is now satisfied*, and is not
merely deleted — a deleted objection teaches nothing.

---

## 1. What is already built. Verify before writing anything; three of these are cheaper than the brief assumed.

| Piece | State | Evidence |
|---|---|---|
| The column | **EXISTS**, nullable, unconstrained | `supabase/migrations/0001_init.sql:30` — `phone text, -- PASS 본인인증 후 확정` |
| Who-may-see-whose | **SHIPPED** | `_club_phone_visible`, `0049_session_shell.sql:167-192` (comment 165-166, revoke 193) |
| Reveal audit table | **SHIPPED**, RLS on with no policy | `0049:156-163` |
| Audit write | **SHIPPED**, twice | `0049:236` (superseded) and `0053_audit_followups.sql:435` (live) |
| Roster reader | **SHIPPED** | `club_session_roster`, live body at `0053:392-484`; 0049:195 is the superseded copy |
| **The render** | **SHIPPED on the session shell** | `app/app/club/session/[sid].tsx:908-913` — a tappable `tel:` chip, a 「호스트 경유」 chip for the non-entitled case, and the disclosure line 「번호가 보이면 열람이 기록돼요」 at `:943` |
| Client type | **SHIPPED** | `app/src/lib/api.ts:3677-3678` — `phone: string \| null; phoneVia: 'direct' \| 'host'` |
| **Deletion of the value** | **ALREADY HANDLED** | `0115_account_deletion.sql:421` — `phone = null` inside the tombstone UPDATE |
| The collection point | **MISSING, and structurally blocked** | §3 |
| The 현장 render | **MISSING** | `app/app/club/run/[sid].tsx` fetches the roster at `:123` and renders no phone anywhere |

`_club_phone_visible`'s rule, read at `0049:167-192`: **host ↔ everyone** (both directions,
including backup host) · **owner ↔ their own dog's accepted runner** (both directions,
`custody='runner_delegated'` joined to `bookings.runner_id`) · otherwise 비공개 (via host). Its
lifetime gate is session `open`/`full` **OR** an unresolved custody the viewer or target is party
to (`custody_phase <> 'resolved'` and `service_state is distinct from 'ended'`). The 현장 반환
moment is inside that gate already.

⚠ **Corrections to the brief this contract was written from, all verified:**
- `_club_phone_visible` is `0049:**167**-192`, not 165-192 (165-166 are its 전화 규칙 B comment).
- "What is missing is the collection point, the render, and deletion" is **wrong on two of
  three**. The render exists on the session shell screen and is missing only on the run screen;
  and `profiles.phone` is **already in 0115's redaction list** (`0115:421`), so deletion of *this*
  column is not owed. What is owed is §4's proof, and a tombstone-keyed clear for **any new
  column this slice adds** — see §4.
- The record's "11 accounts" is `auth.users` (measured: 11). `profiles` has **10** rows, so one
  auth user has no profile row at all. Immaterial to this slice; recorded because the figure has
  been used as a scale argument all week.

---

## 2. The column: application-level requirement, NOT `NOT NULL`.

**ADOPTED: `profiles.phone` stays nullable. "Required" is enforced at the collection point.**

Arguing it rather than asserting it, because "required means NOT NULL" is the instinct:

- **`NOT NULL` cannot be satisfied by onboarding, because the row is created before onboarding.**
  `app/app/index.tsx:72` inserts the profile at the **role-select screen** with `{ id, role, name }`
  — one tap, two full-bleed buttons, Sean's own design order for that screen. A `NOT NULL` phone
  aborts that INSERT, so the app could not create a profile at all without moving collection onto
  the role-select screen, which is neither what he asked for ("on onboarding") nor compatible with
  that screen. This is not a fixture problem; it is the launch path.
- **The fixtures argument, measured, and it cuts both ways.** `t_user()` (`supabase/tests/10_settle_suite.sql:9-17`)
  does `insert into profiles (id, role, name)` and is called **354 times across 68 suites**; a
  further **8 raw inserts across 6 files** exist, and `127_profiles_write_grant_suite.sql:251,256`
  are raw *deliberately* — they are testing grants and must state their column list. Sean's "the
  existing ones are fake so it's fine" licenses discarding the ten **production** rows; it says
  nothing about the harness, and the harness is where every future guarantee is measured. One
  helper edit would fix 354 of them, but the remaining 6 files would each need a change made for
  a constraint that buys nothing the collection point does not already buy.
- **What `NOT NULL` would actually protect against is a write path that skips the RPC** — and
  §3's design removes every such path for `authenticated`. The only writer left is `service_role`,
  i.e. our own edge functions, which a `NOT NULL` would inconvenience without constraining.

**ADOPTED alongside it: a shape CHECK.** `check (phone is null or phone ~ '^01[0-9]{8,9}$')` —
normalized Korean mobile digits, no hyphens, no country prefix. Existing rows are all NULL and
pass (measured: 0 non-null). This is the schema-level guarantee that lets the render format the
number instead of trusting whatever was typed.

⚠ **Cost of the CHECK, stated because it is a real one:** `127_profiles_write_grant_suite.sql:81`
declares `v_phone constant text := '010-8900-0091'` (hyphenated) and `:148` writes
`'010-0000-0000'`. Both are fixtures for pins about **privilege**, not about format; both must be
normalized to digits in the same slice, with a one-line comment saying the pin's proposition is
unchanged. That is the house rule (a suite whose pinned behaviour legitimately changes is updated
in the same slice) applied to a fixture rather than to an assertion — say so explicitly in the
diff so a reviewer does not read it as a pin being softened.

---

## 3. The collection point. It cannot be a PATCH, and that is a feature.

**Measured wall:** `authenticated` has
- **no UPDATE grant on `phone`** — `0091_profiles_write_grants.sql:198` grants
  `update (name, district, avatar_url, role, id)` only, and `:194` names phone as OUT **on
  purpose**;
- **no SELECT grant on `phone`** — `0088_profiles_column_grants.sql:135` grants
  `select (id, name, handle, avatar_url, district)`, `0091:180` adds `role`. Nothing else.
- and **`127 W2` pins the write refusal** (`127_profiles_write_grant_suite.sql:134-162`,
  「W2 phone 쓰기 거부(PASS 본인인증 컬럼)」).

So `updateMyProfile` (`app/src/lib/api.ts:1814-1819`) — a plain
`supabase.from('profiles').update(p)` — **cannot** carry phone, and widening its grant would turn
a shipped pin red for a reason the pin's own comment still endorses.

**ADOPTED: a new `SECURITY DEFINER` RPC, `set_my_phone(p_phone text) returns void`.**

Contract:
- **No target parameter.** It writes `auth.uid()`'s row and only that row. The absence of a
  target uuid is the party gate; there is no argument that could be wrong.
- **Party gate before state gate** (house law): `auth.uid() is null` → `not_signed_in`; then the
  tombstone refusal (below); then normalization; then the write.
- **Refuses a tombstoned profile.** `where id = auth.uid() and deleted_at is null`, and raise if
  zero rows. A deleted account must not be able to re-attach a contact number, and the
  0123 §5 precedent is exactly this posture (a party gate that refuses a tombstone).
- **Normalizes before it validates**: strip everything but digits, rewrite a leading `+82`/`82`
  to `0`, then apply the same regex as the CHECK. Raise `invalid_phone` on failure — a visible
  failure, never a silent no-op (honesty law).
- **`set search_path = public, pg_temp` in the body** (98 H1 — ALTER-applied config is reset by
  `create or replace`).
- **`revoke execute … from public, anon` + `grant execute … to authenticated`, written
  explicitly in the same file that first defines the function.** This satisfies
  `check-definer-acl.mjs` by construction (the ACL is set by the defining file), and it is what
  99 S1 sweeps for. 0123 measured the cost of omitting it: 862/1, the sweep naming the function.
- Registered in `check-rpc-contracts.mjs`'s view automatically — the script reads
  `create or replace function` out of the migrations dir (`app/scripts/check-rpc-contracts.mjs:36-41`),
  so the only requirement is that the client's `rpc('set_my_phone', { p_phone })` argument name
  matches the SQL parameter exactly.

**The grant list is NOT widened. `127 W2` and `127 W8` stay green untouched** — and §6 pins that
as a proposition rather than assuming it.

**Where the field goes.**
- Owner: `app/app/onboard/owner.tsx` step 1, beside 이름/동네 (`:184-202`). The CTA is already
  gated on dog name + address (`:152`); phone joins that predicate. The step counter at `:179-180`
  stays `1 / 2` — this adds a field, not a step.
- Runner: `app/app/onboard/runner.tsx`, beside 동네 (`:114`), joining the `ready` predicate at
  `:178`.
- **Nowhere else.** Not the role-select screen (§2), and **not as a retro-active gate** — no
  existing user is blocked from a session for lacking a number. Sean ruled a signup requirement,
  not a service refusal, and the difference is a refusal he never made.

⚠ **The derived first-run gate means "required at signup" binds exactly the new cohort, by
construction.** `app/app/index.tsx:83-98`: an owner with ≥1 dog routes to `/owner/home`, a runner
with a district routes to `/runner/home` — neither ever sees the onboarding screen. Nothing
backfills. This is the correct behaviour under his ruling and it is why the empty state in §5 is
not optional.

---

## 4. 🔴 DELETION. The first thing this slice's review checks.

**Verified, and it changes the shape of the work:** `delete_my_account_tx` **already nulls
`profiles.phone`** — `0115_account_deletion.sql:418-425`:

```
update profiles set
  name = '탈퇴한 사용자', handle = null, phone = null, avatar_url = null,
  district = null, deleted_at = now()
where id = p_uid;
```

`grep -n "phone *= *null" supabase/migrations/*.sql` returns exactly two lines: `0115:421` (this
one) and `0115:493` (`runner_applications.contact_phone`). There is **no other purge anywhere** —
no cron, no sweep.

So the rider inherited from the tenth round is **discharged for the column itself, and it becomes
two obligations instead of one**:

**(a) PROVE it, do not assume it.** Suite 150 is the account-deletion suite; this slice adds an
end-to-end pin that a number set through `set_my_phone` is null after `delete_my_account_tx`, and
mutation-proves it (§6, M1). Until that pin exists, `0115:421` is a line of code someone read —
which is the exact substitution this repo has been bitten by all week (a green light is evidence
for one sentence; write the sentence down).

**(b) ANY NEW COLUMN this slice adds rides the TOMBSTONE, never 0115's allowlist.** If the slice
adds `phone_set_at`, `phone_verified_at`, or anything else on `profiles`, it does **not** re-create
`delete_my_account_tx`. `0123_runner_base_distance.sql:297-312` states the reasoning and this
contract adopts it verbatim in mechanism: 0115 is **445 lines of money-and-consent decisions**, and
reproducing them to add a column name to one UPDATE is the silent-revert trap `0086 §B:124` records
— a faithful-looking copy that applies later and undoes the newer definition while the harness
stays green.

The mechanism, copying `_runner_base_tombstone` (`0123:325-353`) exactly:

```
create or replace function _profile_phone_tombstone() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$ … $$;
revoke execute on function _profile_phone_tombstone() from public, anon, authenticated;
drop trigger if exists _profile_phone_tombstone_tg on profiles;
create trigger _profile_phone_tombstone_tg after update on profiles
  for each row
  when (new.deleted_at is not null and old.deleted_at is distinct from new.deleted_at)
  execute function _profile_phone_tombstone();
```

Why this and not the allowlist, restated so a reviewer can attack it: `profiles.deleted_at` going
non-null is **0115 §B's own definition of a deleted account**, it is set inside that transaction,
and it is client-unreachable (`0091:198` grants UPDATE on name/district/avatar_url/role/id only).
The invariant therefore holds for **any future deletion path**, not only for today's statement
order, and 0115 stays byte-untouched.

⚠ **If the slice adds no new column, it adds no trigger.** A trigger that clears a column 0115
already clears is dead weight that a future reader will mistake for the mechanism. In that case
obligation (a) is the whole of the deletion work — and it is still the first thing the review
checks.

**What deletion does NOT reach, stated so nobody believes it does:**
- `club_phone_access_log` is on 0115's **KEEP** list (`0115:638` and the watchdog's retention
  array at `0115:814`). It stores `session_id / viewer_profile_id / target_profile_id /
  accessed_at` and **no phone value** (`0049:156-163`), so a kept row is a record that a reveal
  happened, not a copy of the number. Measured: 0 rows today. Correct as-is; named here because
  "the log survives deletion" sounds alarming until you read its columns.
- `delegation_consents.emergency_contact` / `.pickup_contact` (`0040:143`, written by
  `session_delegate_dog` at `0048:142-148`, **required** — `0048:102` raises when blank) are
  **third-party phone numbers, kept forever and unredacted** as consent evidence (`0115:78`,
  `:636`). Measured: **4 rows carry a non-empty emergency contact today**, and they are already
  rendered to the handling runner (`0053:459`, surfaced at `app/app/club/run/[sid].tsx:311`).
  **Not this slice's to change** — it is a deliberate retention decision — but it is a fact
  counsel needs (§7) and it is the sharpest existing counter-example to the claim that this
  product does not yet hand contact details to a counterparty.

---

## 5. The render.

**On the session shell: already correct, do not rebuild it.** `app/app/club/session/[sid].tsx:908-913`
renders the chip when `p.phone` is non-null, the 「호스트 경유」 chip when it is null and the person
is neither me nor the host, and nothing at all for me/host — plus the standing disclosure line at
`:943`. The server has already decided entitlement; the client renders what it was given and
invents nothing. That is the shape, and it needs no change.

**On the run screen (현장 반환): missing, and this is the slice's client work.**
`app/app/club/run/[sid].tsx` already fetches the roster (`:123`) into `roster` and handles its
failure honestly (`rosterErr`, `:450-455`). Add a contact row to the return card.

**ADOPTED: the entitled set is `roster.people.filter(p => p.phone)` — a client-side filter, no
server change.** `_club_phone_visible` has *already* restricted what came back, so any non-null
number in that array is one this runner is entitled to see. Label each by `p.role` /
`p.isHost` using the existing `ROLE_LINE` map.

⚠ **REJECTED: adding `ownerProfileId` to the roster's dog objects.** It would let the screen say
「이 아이의 보호자」 precisely instead of listing entitled people — but the dog JSON
(`0053:450-466`) carries `ownerName` and no id, so getting it means a `create or replace` of
`club_session_roster`, a shipped `SECURITY DEFINER`, for a **label**. That recreation would owe an
explicit `revoke`+`grant` in the new file (house law: a `create or replace` relying on grant
preservation is a latent PUBLIC-EXECUTE hole), and the honest trade is that a precise label is not
worth touching a money-adjacent definer. If per-dog labelling is later wanted, `ownerProfileId` is
the additive change and it arrives with its own ACL lines.

**The empty state is a REAL state, and it must be drawn as one.** Any user without a number —
every account that exists today, measured 0/10 — renders as 「호스트 경유」 on the shell and, on the
run screen, as an explicit line pointing at the shipped channel: `club_chat_messages` (`0008`,
realtime added at `0049:150`). No blank, no spinner, no fabricated placeholder, no dead button
(honesty laws).

⚠ **A property of the shipped audit that whoever draws this must know, because it is
counter-intuitive.** The access-log INSERT (`0053:435-447`) fires **inside `club_session_roster`**,
for every entitled target with a non-null phone, deduped per (session, viewer, target) — i.e. it
is written **when the roster is fetched**, not when a human looks at a number, and the number is
in the client's memory either way. Two consequences: (i) a "tap to reveal" affordance would log
before the tap and is therefore a lie about the audit's meaning — do not build one; (ii) the
shipped copy 「번호가 보이면 열람이 기록돼요」 is accurate for the shell (chips render immediately)
and must be repeated verbatim on the run screen. **Do not "improve" it into 「번호를 볼 때 기록돼요」**
— that sentence is false about this mechanism.

---

## 6. Suite plan. One proposition per pin; the mutation names the pin that reddens.

**Numbering.** Do **not** take a number from this document. Resolve both against the remote tip
immediately before writing the file:
`git fetch && git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | grep -oE '[0-9]{4}' | sort -n | tail -1`
(same for `supabase/tests/`, `grep -oE '^[0-9]+' | sort -n | tail -1` — `ls | sort` is lexical and
lies). Push the migration and its REGISTRY row in the same breath. *(Tips were 0128 / 162 when this
was written; that is context, not a reservation.)*

**Fixtures must be reachable by the lifecycle.** Every phone in the suite is written through
`set_my_phone`, never by a raw `update profiles`; every club state is reached through the shipped
RPCs — `club_create_session` (`0030:174`) → `session_rsvp` (`0048:158`) → `session_delegate_dog`
(`0048:89`) → `session_propose_dog` (`0048:441`) → `club_start_delegated_runs` — never by writing
`session_dogs.custody_phase` directly. A pin fed by a hand-built row measures the pin.

| Pin | Proposition — the ONE sentence it is evidence for |
|---|---|
| P1 | An authenticated caller can set **their own** phone through `set_my_phone`, and it lands normalized. |
| P2 | `set_my_phone` has **no target parameter**, so the row written is `auth.uid()`'s and no argument can redirect it. (Asserted against `pg_proc.proargnames`, not against behaviour.) |
| P3 | A profile with `deleted_at is not null` is **refused** by `set_my_phone`. |
| P4 | A non-mobile / malformed input **raises** `invalid_phone` and writes nothing — the failure is visible, not a no-op. |
| P5 | `authenticated` **still** cannot `update profiles set phone` directly, and still cannot `select phone`. *(This does not duplicate `127 W2`: W2 pins the pre-existing refusal, P5 pins that **this slice did not widen it**. Both stay.)* |
| P6 | 🔴 A number set through `set_my_phone` is **NULL after `delete_my_account_tx`**. |
| P7 | With a **real** phone present, an entitled viewer's `club_session_roster` returns it and writes **exactly one** `club_phone_access_log` row; a second fetch writes none (dedup). |
| P8 | With a real phone present, a **non-entitled** viewer gets `phone = null`, `phoneVia = 'host'`, and **no** log row. |
| P9 | Once custody resolves **and** the session is no longer `open`/`full`, an ex-entitled viewer's roster returns `null` — the lifetime gate closes. |
| P10 | *(only if a new column is added)* The tombstone trigger clears it when `profiles.deleted_at` goes non-null, **independently of `delete_my_account_tx`'s statement order** — proven by stamping `deleted_at` directly as `postgres`. |

P7–P9 are the load-bearing new ones: **that entire path has never executed in production or in
the harness**, because it is gated on `p.phone is not null` (`0053:438`) and no phone has ever
existed. Measured: `club_phone_access_log` = 0 rows.

**Standing sweeps that must stay green and are not re-implemented here:** 98 H1 (in-body
`search_path` on every definer), 99 S1 (no `public` definer is anon-executable — it counts trigger
functions too), and `check-definer-acl.mjs`. Their greens are evidence for **their own** sentences
and for nothing in the table above.

### Mutation battery — three propositions, not one

For the deletion guarantee, plant the failure **without** the fix and **with** it, per the house
discipline; "the pin notices something" is the weakest of the three claims and the one most often
mistaken for the other two.

⚠ **Every mutation is applied to the RUNNING harness database with `create or replace` / `grant`
inside a transaction that is rolled back. NEVER by editing a file in `supabase/migrations/`** —
even transiently, even restoring from a copy taken seconds earlier (measured 2026-08-25: a
copy-modify-restore is a read-modify-write with a multi-second window, and it silently ate a
subagent's work).

| # | Mutation | Must redden | Proves |
|---|---|---|---|
| M1a | `create or replace delete_my_account_tx` **minus** `phone = null` | **P6** | the hole is real and reproduces |
| M1b | restore the shipped body, re-run | **nothing** (P6 green) | the shipped line actually closes it |
| M2 | `grant update (phone) on profiles to authenticated` | **P5 and `127 W2`** | the grant wall is what holds, not the RPC's politeness |
| M3 | drop the `deleted_at is null` arm from `set_my_phone` | **P3** | the tombstone refusal is load-bearing |
| M4 | re-create the new definer **without** its `revoke` | **99 S1** | the ACL line is not decoration (0123 measured 862/1 on exactly this) |
| M5 | `create or replace _club_phone_visible` → `select true` | **P8 and P9** | the entitlement gate, not the UI, is what withholds the number |
| M6 | drop the dedup `not exists` from the log INSERT | **P7** | the audit counts reveals, not fetches |
| M7 | *(new column only)* trigger dropped | **P10** | the tombstone cascade is real |

**A control that cannot fail is not a control.** M1b is the control and it is a *real* one: it is
the same pin, the same fixture, the same command, differing only in the one line under test. Do
not substitute "everything is green at the end" — that measures the suite, not the system.

---

## 7. Retention — what the code will do, so counsel can describe it accurately.

**This section states behaviour. It does NOT draft policy wording** — that is counsel's, by Sean's
ruling.

| Item | What the code does after this slice |
|---|---|
| `profiles.phone` | Kept for the life of the account. Cleared **only** by `delete_my_account_tx` (`0115:421`), which sets it to NULL in the same statement that stamps the tombstone. No cron, no dormancy purge, no expiry exists — verified by exhaustive grep. |
| Disclosure window | A number is returned to a counterparty **only** while `_club_phone_visible` is true: the session is `open`/`full`, **or** a custody the viewer or target is party to is unresolved (`0049:167-192`). Outside that window the roster returns `null` and the counterparty sees 「호스트 경유」. |
| Who can receive it | Host ↔ every session member (both directions, backup host included); owner ↔ the accepted runner of **their own** dog (both directions). Nobody else, ever — enforced server-side, not by the UI. |
| Reveal record | Every reveal writes `club_phone_access_log` (session, viewer, target, timestamp — **no number**), deduped per session/viewer/target. Kept indefinitely as an access-audit record (`0115:638`), including past the account's deletion. |
| Adjacent, pre-existing, not changed by this slice | `delegation_consents.emergency_contact` and `.pickup_contact` — **third-party** numbers the owner types at delegation, **required** (`0048:102`), shown to the handling runner (`0053:459`), and **kept forever unredacted** as consent evidence (`0115:78`). Measured: 4 such rows exist today. |

**Facts counsel needs, that the current policy gets wrong.** `docs/legal/privacy-policy.md` already
mentions the phone number, and this slice makes two of its sentences false:

1. `:45` calls it **「전화번호 (선택 — 인계 시 연락용)」**. After this slice it is **required at
   signup**, and its purposes are the two Sean named (safety, contact) plus the club return flow.
2. `:45-47` scopes the mutual disclosure to **「사건이 접수되어 처리 중인 예약에 한해」** — an
   incident-only window, owner↔runner, marketplace-shaped. The shipped club rule is **wider on
   both axes**: it includes **host ↔ every member**, and its window is any live session or any
   unresolved custody, incident or not.
3. `:106-117`'s retention table has **no row for the phone number**, and `:113`'s own HTML comment
   already flags the table as a placeholder awaiting counsel.

Those three are facts about the system, supplied so a lawyer can write accurate text. No wording
is proposed here.

---

## 8. 🔴 The ship gate is EXTERNAL. This is a gate, not a footnote.

Sean routed the 개인정보처리방침 text to counsel (**"Add it to the lawyer email"**, 01:46:38Z). It
rides the pending legal email alongside the 맹견-removal item (`docs/legal/contract-status-counsel-brief.md`
§6 is the existing "별건" section that shape belongs in).

**Therefore:**

- ✅ **The build may proceed now** — migration, RPC, onboarding fields, run-screen render, suite,
  battery, commit, push. None of that collects anything from a real person.
- ⛔ **Collection must not be enabled for real users before the revised policy text exists in the
  app.** Concretely, the gate is: **no build carrying the onboarding phone field is distributed to
  any non-fixture user until the 개인정보처리방침 revision naming item / purpose / retention /
  **recipient** is live in-app.** "Recipient" is the load-bearing word — a runner or host seeing an
  owner's number is a third-party disclosure, and it is the part the current text does not cover
  (§7).
- The gate is naturally satisfied today and that is **luck, not design**: charging is off
  (`ops_flags.payments_live_since` is null) and all 10 profiles are fixtures. It stops being luck
  the day a real person signs up, which is why this is written as a precondition with a named
  checker rather than as a note.
- **Who clears it:** Sean, by confirming counsel's text has landed. Not a session, not a green
  gate. A session may report the build is ready; it may not report the gate is cleared.
- **Cheap belt, if the release schedule gets close before counsel replies:** put the onboarding
  field behind an `ops_flags` row read at render (the `payments_live_since` idiom), so the gate is
  a database fact rather than a release-timing assumption. Specify it only if the timing actually
  collides — an unnecessary flag is its own liability, and a flag on an *import* would not help
  anyway (that is a different failure class; see the route-native-imports gate).

---

## 9. What this does NOT do.

- **Does not verify the number.** `0001:30`'s comment says 「PASS 본인인증 후 확정」 — the original
  design intent was a carrier/PASS identity check. This slice stores a **self-declared** string
  that passes a shape check. For a field justified by *safety*, that distinction is real, and it
  is OPEN-1 below.
- **Does not backfill.** Nothing writes a number into the 10 existing rows, and nothing should.
- **Does not gate anything retro-actively.** No existing user is blocked from a session, a
  booking, or a delegation for lacking a number.
- **Does not touch `_club_phone_visible`, `club_session_roster`, or `delete_my_account_tx`.** All
  three are shipped and correct for this purpose; the slice supplies data they already know how to
  handle.
- **Does not widen any grant.** `0088`/`0091`'s column lists are untouched, and `127 W2`/`W8` stay
  green as written.
- **Does not build a call button, a masked-relay number, or an in-app voice channel.** Rule B plus
  a `tel:` link is the whole surface.
- **Does not touch `delegation_consents`' third-party contacts**, nor their retention.
- **Does not draft privacy-policy wording.**
- **Does not resolve the 현장 반환 arm's other open questions** — the three-party room's scope and
  lifetime (eleventh round, R7-3) and the club run-end primitive (R7-1) are separate slices and are
  not made easier or harder by this one.

---

## 10. OPEN — SEAN

Each answerable in one sentence.

1. **Verified or self-declared?** The number is typed by the user and only shape-checked — no SMS
   or PASS verification. For a field whose stated purpose is safety, is a self-typed number enough
   for the pilot, or should it be verified before launch?
2. **Host sees everyone's number.** Rule B has shipped since `0049` but has never disclosed
   anything, because no number existed. The moment collection lands, **the host can see every
   session member's number, and every member can see the host's** — the widest arm of the rule.
   Confirm that is what you want live on day one, or should the host arm be narrowed to members
   with an active delegation?
3. **Retention.** The number is kept for the life of the account and cleared only on account
   deletion — no dormancy purge exists. Is "until withdrawal" the retention period counsel should
   write, or should a dormant account's number expire (and after how long)?
4. **Editable and clearable afterwards?** Required at signup, but 마이/설정 could let a user change
   or blank it later — which would make the requirement a one-time formality. Should the number be
   editable but **not** clearable once set?

---

## 11. Discipline this slice inherits

- `/autoplan` is the standing gate: any migration or money-adjacent change runs scout → contract →
  implement → adversarial review where reviewers **execute** attacks → pins → revise → verify.
- Commit gate from `app/`: `tsc --noEmit`, `check-rpc-contracts.mjs`,
  `check-route-native-imports.mjs`, `check-definer-acl.mjs`.
- Harness `supabase/tests/harness.sh` green, with the §6 battery run and its results reported as
  measured numbers, not as "all pass".
- Commit with an explicit pathspec — `git commit -m "…" -- <paths>` — because another agent's
  staged work rides a bare `git add`.
- Ship means push. Commit each verified slice against green gates and push it the same session.
