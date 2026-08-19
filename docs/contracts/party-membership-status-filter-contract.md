# Contract — party membership narrowed to accepted states (closes /cso #2's residual, F2 / B-11)

**Scope owner:** the adjacent slice named in `docs/contracts/booking-entry-rebuild-contract.md` §C.5
and `docs/security-booking-party-forgery.md` §E.9 ("Owner: the adjacent slice — `is_booking_party`'s
status filter / narrowing party membership to accepted+active").

**Shape decided by:** Sean's D1/D2 question, answered as **decision O-4** under the overnight grant
(`docs/decisions/awaiting-sean.md:274`, §0-overnight, 🔵 reversible in one word):

> **D2-narrow**: the nomination itself still reaches the runner (system-authored notification — that
> IS the request flow), but free-text chat, reviews and incidents require the booking to be in an
> accepted/active state; party membership for those surfaces gets a status filter.
> *Rationale recorded with it:* "attacker-authored push/chat to a stranger is the harm, a system
> '요청이 왔어요' is the product."

⚠ O-4 is 🔵 (announcer-decided under grant), not ✅ (Sean's own words on origin). Per CLAUDE.md, *a
relayed decision is evidence, not authority.* The implementer builds to it; if Sean reverses D2, the
migration is one `create or replace` + five policy recreations to walk back, and §E.6 says how.

**Written by:** scout, read-only. No code, migration, suite or production row was written by this
pass. Every production statement below was a `select` through `supabase db query --linked`.

**Trunk at write time:** `8d33cde`. Production migration tip: **0111** (measured, §A.1).

---

## A. Measured state

### A.1 Production (SELECT-only, `supabase db query --linked`, 2026-08-19)

`supabase migration list --linked` — remote tip **0111**. `0105` absent from every environment (as
`0111`'s REGISTRY row asserts); `0110` claimed on the registry but **not yet applied** (its file is
not on trunk). So the live schema is exactly `0001…0104, 0106…0109, 0111`.

**`is_booking_party` as it exists in production** (`pg_get_functiondef`):

```sql
CREATE OR REPLACE FUNCTION public.is_booking_party(b_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (
    select 1 from bookings b
    where b.id = b_id and (b.owner_id = auth.uid() or b.runner_id = auth.uid())
  );
$function$
```

⚠ **The repo file says `set search_path = public` only** (`supabase/migrations/0002_rls.sql:16`).
Production carries `public, pg_temp` because `0055_definer_hardening.sql:171` ALTERs every definer
in a loop. CLAUDE.md's law applies directly: **ALTER-applied config is reset by `create or
replace`.** Any file that re-creates this function MUST write `set search_path = public, pg_temp`
**in the body**, or suite 98 H1 (whole-schema definer sweep) goes red. This is the single most
likely way to fail this slice on the first harness run.

**Every policy in production whose predicate is party membership** (`pg_policies`, verbatim `qual` /
`with_check`; the table is the source of truth for §C's DROP/CREATE targets — all names below exist):

| table | policy | cmd | predicate (production) |
|---|---|---|---|
| `chat_threads` | `threads party` | SELECT | `is_booking_party(booking_id)` |
| `chat_threads` | `threads party insert` | INSERT | `is_booking_party(booking_id)` |
| `chat_messages` | `messages party read` | SELECT | `exists (select 1 from chat_threads t where t.id = chat_messages.thread_id and is_booking_party(t.booking_id))` |
| `chat_messages` | `messages party send` | INSERT | `sender_id = auth.uid() and exists (… is_booking_party(t.booking_id))` |
| `reviews` | `reviews author insert` | INSERT | `author_id = auth.uid() and is_booking_party(booking_id)` |
| `reviews` | `reviews public read` | SELECT | `visibility = 'public' and is_booking_party(booking_id)` |
| `reviews` | `reviews author read` | SELECT | `author_id = auth.uid()` |
| `reviews` | `reviews storefront read` | SELECT | `visibility = 'public' and target_kind = 'runner'` (0011) |
| `runs` | `runs party read` | SELECT | `is_booking_party(booking_id)` |
| `incidents` | `incidents party` | SELECT | `reporter_id = auth.uid() or (booking_id is not null and is_booking_party(booking_id))` |
| `notifications` | `noti party insert` | INSERT | inline: `kind='booking' and ref_id is not null and exists (select 1 from bookings b where b.id = ref_id and (b.owner_id=auth.uid() or b.runner_id=auth.uid()) and (notifications.profile_id = b.owner_id or … = b.runner_id))` (0009:7) |
| `bookings` | `bookings party read` | SELECT | inline: `owner_id = auth.uid() or runner_id = auth.uid()` (0002:92) |

Two policies named in older docs are **already gone from production** and must not be "restored":
`incidents report` (INSERT, dropped by `0094:121`) and `runs runner write` (INSERT, dropped by
`0087:124`). There is **no INSERT policy on `incidents` or `runs` in production**.

**`realtime.messages` policies in production** (all three exist under exactly these names):

| policy | cmd | predicate |
|---|---|---|
| `party channel read` | SELECT (`to authenticated`) | `extension = 'broadcast' and my_channel_allowed(realtime.topic(), 'read')` |
| `run channel read` | SELECT (`to authenticated`) | `… and realtime.topic() like 'run2-%' and my_channel_allowed(…, 'read')` |
| `run channel write` | INSERT (`to authenticated`) | `… and realtime.topic() like 'run2-%' and my_channel_allowed(…, 'write')` |

**Definer functions in production whose body mentions `is_booking_party`** (`pg_proc.prosrc like
'%is_booking_party%'`, schema `public`): exactly **two** — `channel_allowed` (0108, in a *comment*
only; the body re-derives the predicate inline) and `incident_contact` (0088 §E, likewise a comment;
its body does `select owner_id, runner_id into b … ` for the stated reason "one read beats two",
`0088:247-249`). **No production definer calls the function.** So the consumer set is the policy
table above plus the inline party gates listed in A.3.

**`bookings` has no acceptance timestamp column** (`information_schema.columns`, 41 columns read):
there is `owner_confirmed_handoff_at`, `runner_confirmed_handoff_at`, `arrived_at`,
`run_ended_at`, `settlement_ready_at` — and **nothing that records "the runner accepted"**. This is
load-bearing for §C.2's choice of predicate.

### A.2 The booking status machine

`booking_status` enum (`supabase/migrations/0001_init.sql:9-14`), 17 values. Latest transition map is
`enforce_booking_transition` in `supabase/migrations/0066_enroute_cancel.sql:37-62` (base 0047).
Classification for this slice:

| class | statuses | why |
|---|---|---|
| **pre-acceptance** | `draft`, `quoted`, `payment_hold`, `matching`, `runner_pending` | no runner has said yes. `runner_pending` is the *nomination* state: `runner_id` is set, consent is not. |
| **accepted / active** | `confirmed`, `runner_enroute`, `picked_up`, `active` | reachable only through an accept (§A.2's accept sites) |
| **post-run terminal, provably accepted** | `completed`, `no_show`, `incident_review`, `cancelled_runner` | every in-edge is from `confirmed`/`runner_enroute`/`picked_up`/`active` (`0066:49-55`) |
| **terminal, acceptance NOT provable from status alone** | `expired`, `cancelled_owner`, `refund_pending` | ⚠ each is reachable from a pre-acceptance state: `matching`/`runner_pending → expired` (`0017:9`, cron 30-min sweep), `matching`/`runner_pending → cancelled_owner` (`0066:46-47`), `payment_hold → refund_pending` (`0066:45`) |

**Where the runner ACCEPTS** — `supabase/functions/transition-booking/index.ts`, action
`runner_accept` (`:52-146`). Two arms, both landing on `status: 'confirmed'` via `resetPatch`
(`:121`):
- open pool (`:122-135`): requires `bk.status = 'matching'` and `runner_id is null`, CAS on
  `is('runner_id', null)`.
- nomination (`:136-143`): CAS `eq('runner_id', uid).eq('status','runner_pending')`.
Then `notify(bk.owner_id, "러너 매칭 완료", …)` (`:144`).

**Where the nomination push is emitted** — action `request_runner` (`:148-200`): owner-gated
(`:153`), nominee must be a real runner (`:157-159`), state gate `matching|runner_pending` (`:163`),
clash gate (`:169-187`), CAS to `{runner_id: target, status: 'runner_pending'}` (`:191-194`), then
`notify(target, "지명 러닝 요청", "보호자가 회원님을 지명했어요 — 요청 탭에서 응답해주세요")`
(`:198`) and, if a previous nominee was displaced, `notify(displaced, "지명이 변경됐어요", …)`
(`:197`).

🔴 **The nomination push is written as `service_role` and therefore bypasses RLS entirely.**
`notify` (`:25-26`) writes through `db = admin()` (`_shared/ctx.ts` — the SERVICE_ROLE_KEY client).
`noti party insert` is a policy on `authenticated`; `service_role` never consults it. **Narrowing
that policy cannot touch the nomination flow.** This is the measurement that makes O-4 buildable:
the product half ("a system 요청이 왔어요") and the harm half ("attacker-authored push") are already
on two different authorities, and this slice only narrows the client one. `notify_push` (`0024:44`,
AFTER INSERT on `notifications`) fires on the row regardless of who wrote it — untouched.

### A.3 Inline party gates that are the same predicate spelled out

These do not call `is_booking_party` but ARE party membership, and B-11 reaches two of them:

| site | gate | status filter today |
|---|---|---|
| `open_incident_tx` (`supabase/migrations/0094_incident_verification.sql:124-159`) | `v_uid is distinct from b.owner_id and v_uid is distinct from b.runner_id → raise 'not_party'` (`:140-142`) | **none** |
| `incident_contact` (`0088:238-270`) | party gate (`:247-253`) then state gate `exists open incident` (`:255-259`) | none of its own — inherits from `open_incident_tx` |
| `verify_incident_tx` (`0094:165-217`) | caller must BE the side they claim (`:181`) | none |
| `noti party insert` (`0009:7-15`) | inline owner/runner on `ref_id` | **none** |
| `bookings party read` (`0002:92`) | inline owner/runner | none — **and must stay that way** (§C.4) |
| `channel_allowed` chat/bk arms (`0108:128-136`) | re-derives owner/runner inline | none — deliberately, "mirror the table" (`0108:34-41`) |

### A.4 What the client does today at `runner_pending` — the honest UX answer

**Yes: the owner is offered chat on a nominated-but-unaccepted booking. The runner is not.**

- `STATUS_MAP` (`app/src/lib/api.ts:690-706`) flattens `payment_hold`, `matching` **and
  `runner_pending`** all to the display status `'pending'`. `app/owner/home.tsx:497-498` recovers the
  distinction as `fnDirected = liveNext?.status === 'pending' && !!liveNext.matched` ("★ 지명 응답
  대기").
- `app/owner/home.tsx:1010` — the final `else` branch of the hero widget (`:920` `active` → `:932`
  `handoff` → `:948` `confirmed` → else) renders **「러너와 채팅」** and pushes `/chat` with
  `bid = liveNext.id`. That branch is what a `pending` booking renders. **So the owner-home chat
  button is live at `runner_pending`.**
- `app/owner/schedule.tsx:401` — the booking sheet's runner card carries a 「채팅」 chip and the card
  is **unconditional** (its `runner` object falls back to `selected.runnerName`, which for an
  unmatched booking reads "러너를 찾고 있어요", `:81`, `:118-124`). So the chip shows at `matching`
  and `runner_pending` too.
- `app/src/lib/api.ts:2507-2533` `openChatForBooking` explicitly supports the pre-match case —
  `peerName = '러너 (매칭 전)'` when `runner_id` is null — and calls `ensureThread` (`:2391-2401`),
  which **INSERTs into `chat_threads` as `authenticated`**. That INSERT is the policy this slice
  narrows.
- Everything else is already accept-gated: the `/chat` fallback with no `bid`
  (`fetchCurrentOwnerBookingId`, `:1038-1045`) filters on `IN_FLIGHT = ['confirmed',
  'runner_enroute','picked_up','active']` (`:1025`); `owner/live.tsx`, `owner/meetup.tsx`,
  `runner/run.tsx`, `runner/meetup.tsx` are all post-accept screens; **`app/runner/requests.tsx` — the
  nomination inbox — contains no chat entry point at all** (grepped: zero `/chat`, zero `채팅`).
- Reviews: `app/owner/review.tsx:37` and `app/runner/review.tsx:50` insert directly; both are reached
  only from post-run screens (`owner/report.tsx:496`, `runner/done.tsx:166`).
- Incidents: **no client caller exists** — `open_incident_tx`, `verify_incident_tx` and
  `incident_contact` are grepped to zero call sites in `app/`. 0094's own header says the same.
- Client `notifications` INSERTs: `addRunEvent` (`:1889`), `notifyKmMilestone` (`:1900`), `sendSOS`
  (`:2565`, gated on `IN_FLIGHT`), `notifyRunStop` (`:2589`). All fire during `active`/live only.

⚒ **Consequence, stated honestly:** after this migration the owner-home chat button and the schedule
sheet's chat chip **still render at `matching`/`runner_pending`, and tapping them now fails** —
`ensureThread` throws a PostgREST RLS error and `app/chat.tsx` surfaces it. That is an honest refusal
rather than a lie (nothing silently succeeds), but it is a **dead button under CLAUDE.md's honesty
law**, and this slice is server-only. The client follow-up is named in §E.5 and belongs to **ui2**.

### A.5 Suites and e2e scripts that touch these surfaces

- `supabase/tests/143_realtime_chat_bk_suite.sql` — the realtime rooms. **C3** (`:84-95`) pins, in
  words, "chat_threads `threads party` is `is_booking_party()` with NO status gate — a cancelled
  booking's thread is still readable by its parties on the table, so the room must admit them too",
  and asserts the `cancelled_owner` fixture's room is open to both parties. **B1** (`:98-106`) pins
  that the owner alone may join `bk-<booking>` while `runner_id` is null at `matching` — the radar
  screen. Both are directly in the path of a naive narrow (§C.4).
- `supabase/tests/146_booking_entry_suite.sql` — **D-15** pins the bare `payment_ok` CAS green;
  "that pin passing IS the statement of the residual" (`docs/security-booking-party-forgery.md:128`).
  This slice does not change it and must not.
- `supabase/tests/104_private_media_suite.sql` — M9 (`:150-162`) inserts a `chat_messages` row **as
  `authenticated`**, on a `t_active_booking` fixture (`active`) → inside the new set, stays green.
- `supabase/tests/126_chat_notify_suite.sql`, `130_incident_verification_suite.sql` (fixture
  `active`), `106_incident_subject_suite.sql` (`picked_up`) — fixtures inside the new set; their
  `chat_threads` inserts run as harness `postgres`, which RLS does not police.
- `app/scripts/e2e-party-channels.mjs` — creates the booking at `status:'confirmed'` (`:40`) and does
  **every** write as `service_role` (`svc`, `:40-48`, `:70`). Unaffected by an `authenticated`-only
  narrow. `app/scripts/e2e-run-channel.mjs` exercises the `run2-` family only, which this slice does
  not touch.

---

## B. Threat list — the B-11 chain, step by step, and every surface it reaches

The chain is **already executed** by the 0111 reviewer against 0111's own target state
(`docs/contracts/booking-entry-rebuild-contract.md:144`, `docs/security-booking-party-forgery.md:115-135`).
Nothing here is hypothetical; this section names *which policy* each step lands on.

| # | step | authority | today | after §C |
|---|---|---|---|---|
| **B-11.0** | `create-booking-hold` with the attacker's **own** dog, own address, own fares | authenticated → edge fn as `service_role` | **allowed, and correct** — every ownership check passes because the attacker really does own everything | unchanged, deliberately |
| **B-11.1** | `transition-booking` `payment_ok` → `matching` | owner-gated bare CAS (`transition-booking/index.ts:44-46`) | **verifies nothing about payment** — no PG receipt, no ledger row, no amount, zero money moved | unchanged — adjacent slice (pay-after-run, O-5), pinned by 146 D-15 |
| **B-11.2** | `transition-booking` `request_runner` with `meta.runner_id = <any real runner>` → `bookings.runner_id = victim`, `status = runner_pending` | owner-gated (`:153`) | **allowed, and it is the product** (O-4: the nomination IS the request flow) | **unchanged — explicitly preserved** |
| **B-11.3** | victim receives 「지명 러닝 요청」 push | `service_role` insert (`:198`) → `notify_push` (`0024:44`) | product | **unchanged — explicitly preserved** |
| **B-11.a** | attacker `insert into chat_threads (booking_id)` | `threads party insert` (0008:5) | ✅ allowed — `is_booking_party` true at `runner_pending` | 🚫 **refused** |
| **B-11.b** | attacker `insert into chat_messages` — arbitrary free text to the victim | `messages party send` (0002:145) | ✅ allowed | 🚫 **refused** (thread cannot exist; and the policy itself refuses) |
| **B-11.c** | that message → `notify_chat_message` (`0090:42-95`) → `notifications` row → `notify_push` → **push on the victim's phone**, sender name in the body (`0090:90`) | definer trigger, fires whenever `owner_id` and `runner_id` are both non-null (`:59-61`) | ✅ reached | 🚫 **unreachable** — no message, no trigger |
| **B-11.d** | attacker writes a notification **with a title and body of their choosing** straight at the victim | `noti party insert` (0009:7) | ✅ allowed — and `0024` pushes `title`/`body` **verbatim to a lock screen** (`0090:33-37` says so). This is the single most direct form of the harm O-4 names, and it needs no chat thread at all. | 🚫 **refused** |
| **B-11.e** | attacker inserts a `review` naming the victim | `reviews author insert` (0002:119) | ✅ allowed | 🚫 **refused** |
| **B-11.f** | attacker calls `open_incident_tx(booking)` | inline party gate, **no state gate** (`0094:140`) | ✅ allowed | 🚫 **refused** |
| **B-11.g** | …then `incident_contact(booking)` returns **both parties' `name` + `phone`** while the incident is open (`0088:238-270`) | party + "open incident exists" | ✅ reached. ⚠ **This is a phone-number disclosure the earlier write-ups did not name.** It is inert *today only because* `profiles.phone` is universally NULL (PASS not integrated, `0088`'s own comment) — it becomes live the day PASS lands, with no further code change. | 🚫 **unreachable transitively** — no incident can be opened pre-accept, so the state gate never passes. `incident_contact` itself is **not edited** (0094 §4 forbids narrowing that door). |
| **B-11.h** | attacker joins `chat-<thread>` / `bk-<booking>` realtime rooms | `party channel read` → `channel_allowed` (0108) | ✅ allowed | **unchanged — and see §C.4 for why narrowing them closes nothing and breaks two pins** |
| **B-11.i** | attacker uploads a photo to `media/{uid}/chat/{thread}/…` | `media owner insert` is **path-based only** (`0064:55-61`) | ✅ allowed | ✅ still allowed — but the object is an orphan: `media party read` delegates chat reads to `chat_messages` RLS (`0064:94-96`), and no message row can reference it. Named as an accepted residual, not a target. |

**Surfaces deliberately NOT in the chain, verified:**
- `runs` — no INSERT policy exists in production (0087 dropped it); rows are minted by `start_run`
  as `service_role` on a `confirmed`+ booking. `runs party read` cannot leak a row that cannot exist.
- `bookings party read` — the victim seeing the request is the product.
- `club-chat-<session>` and every `club_*` table — different membership model
  (`_club_shell_access`, `0052:250`), reached through `session_proposal_respond`, never through
  `is_booking_party`. **Out of scope; measurement confirms it, it is not an assumption.**

---

## C. Target end state

### C.1 The new predicate

```sql
create or replace function is_booking_party_active(b_id uuid) returns boolean
language sql stable security definer
set search_path = public, pg_temp          -- ⚠ IN THE BODY (§A.1: 0055's ALTER is wiped by c-o-r)
as $$
  select exists (
    select 1 from bookings b
    where b.id = b_id
      and (b.owner_id = auth.uid() or b.runner_id = auth.uid())
      and b.status in (
        'confirmed', 'runner_enroute', 'picked_up', 'active',   -- accepted, live
        'completed', 'no_show', 'incident_review',              -- post-run, provably accepted
        'cancelled_runner'                                      -- only reachable from confirmed+
      )
  );
$$;

revoke execute on function is_booking_party_active(uuid) from public, anon;
grant  execute on function is_booking_party_active(uuid) to authenticated, service_role;
```

`is_booking_party` itself is **NOT modified** — not its body, not its grants. Two predicates, one
narrow and one wide, with every policy stating which it means. (Editing the wide one in place would
force every SELECT policy to narrow at the same time; §C.4 explains why that is wrong.)

⚠ **The exclusion list is the interesting half.** Excluded: `draft`, `quoted`, `payment_hold`,
`matching`, `runner_pending` (never accepted) **and `expired`, `cancelled_owner`, `refund_pending`**
— because §A.2 measures that each of those three is reachable *directly from a pre-acceptance
state*. If `cancelled_owner` were included, the whole slice would be defeated by one extra call: the
attacker nominates, cancels their own booking, and is a full party again.

### C.2 Why a status set and not an acceptance timestamp — [REC], with the alternative named

The strictly cleaner predicate is a monotone witness: a `bookings.runner_accepted_at` column,
stamped by both `runner_accept` arms, and the predicate becomes `party and runner_accepted_at is not
null`. It would distinguish "cancelled after the runner accepted" from "cancelled while a nomination
was pending", which the status set cannot.

**[REC] do NOT build it in this slice.** It costs: a new column and its backfill (every historical
`completed` booking needs a stamp or the predicate silently locks existing chats); writes in **both**
`runner_accept` arms (`transition-booking/index.ts:121` `resetPatch`); and a **clear** in
`request_runner`'s CAS (`:191-194`) and `runner_decline` (`:209`), because otherwise a
`confirmed → matching → request_runner` reassignment leaves the *previous* runner's stamp in place
and hands the new, unaccepted nominee full party rights — reintroducing the exact hole. That is an
edge-function change plus a data migration, i.e. a different blast radius and a different reviewer.

**The cost of the status set instead:** after an owner cancels a **confirmed** booking
(`cancelled_owner`, the 0066 en-route ladder), neither party can send a *new* chat message or write
a review on it. **Reading the existing history is unaffected** (§C.4 keeps every SELECT policy wide),
and the realtime room stays open (143 C3 stays green). If Sean or ops later wants post-cancel
messaging back, that is the moment to build `runner_accepted_at` — record it as the named successor,
not as a bug.

### C.3 Policies that SWITCH to `is_booking_party_active` — the complete list

All five are `drop policy if exists` + `create policy` under the **same name** (policies are not
`create or replace`-able; the view rule in CLAUDE.md is about views, not policies). Every name below
was read out of production `pg_policies` in §A.1, so every DROP has a target.

| # | table | policy | cmd | new predicate |
|---|---|---|---|---|
| 1 | `chat_threads` | `threads party insert` | INSERT | `is_booking_party_active(booking_id)` |
| 2 | `chat_messages` | `messages party send` | INSERT | `sender_id = auth.uid() and exists (select 1 from chat_threads t where t.id = thread_id and is_booking_party_active(t.booking_id))` |
| 3 | `reviews` | `reviews author insert` | INSERT | `author_id = auth.uid() and is_booking_party_active(booking_id)` |
| 4 | `notifications` | `noti party insert` | INSERT | `kind = 'booking' and ref_id is not null and is_booking_party_active(ref_id) and exists (select 1 from bookings b where b.id = notifications.ref_id and (notifications.profile_id = b.owner_id or notifications.profile_id = b.runner_id))` |
| 5 | *(RPC, not a policy)* `open_incident_tx` | — | — | after the existing party gate at `0094:140-142`, add a state gate that raises a **distinctly named** error |

Notes the implementer must not improvise around:

- **(2)** keeps `sender_id = auth.uid()`. Removing it would let a party forge the *sender* of a
  message inside a legitimate thread — a separate hole, currently closed, must stay closed.
- **(4)** keeps the recipient arm (`profile_id` must be one of the two parties) as a *separate*
  `exists`. Do not fold it into the predicate function: the function answers about `auth.uid()`, the
  recipient arm is about the row being written. Two different questions.
- **(5)** `open_incident_tx` is `create or replace function` — so it **must** re-state
  `set search_path = public, pg_temp` (it already does, `0094:131`; do not drop it). The new gate
  goes **after** the party gate (house law: party before state) and raises a name of its own, e.g.
  `raise exception 'booking_not_active'`, never reusing `not_party` — 0094 §10's own law: "DISTINCT
  FACTS GET DISTINCT NAMES". Keep the `for update` and the one-open-incident-per-booking return.

### C.4 What KEEPS plain `is_booking_party` — and why each one is deliberate

**Every SELECT policy stays wide. Nothing in the read direction is narrowed.**

| kept as-is | why |
|---|---|
| `bookings party read` (0002:92) | 🔴 **The nominated runner MUST be able to SELECT the booking.** This is O-4's protected half — the runner opens 요청 탭, reads the request, accepts or declines. Narrowing this breaks the request flow the decision exists to preserve. |
| `threads party` (SELECT) · `messages party read` (SELECT) | chat history must survive cancel/complete (`0108:34-37`: "chat persists after cancel/complete, exactly as the table lets it"). And there is nothing pre-accept to read: after §C.3 no thread and no message can be created before acceptance. Narrowing these buys zero and costs the history. |
| `reviews public read`, `reviews author read`, `reviews storefront read` | the write is what this slice gates. A review that cannot be written cannot be read. |
| `incidents party` (SELECT) | same argument; `open_incident_tx` is the only writer and it is gated in (5). |
| `runs party read` | no `runs` row can exist before `start_run`, which requires `confirmed`+. |
| `incident_contact` (0088 §E) | 🔴 **explicitly not edited.** 0094 §4 rules that the phone door opens on the *open*, and warns that "narrowing it to verified-only would be the same error wearing a safety costume". Gating the *opener* (5) shuts B-11.g transitively without touching a door two rulings have already settled. |
| `verify_incident_tx` (0094 §10) | can only be called on an incident that exists; (5) is the gate. |

**The realtime policies — [REC] LEAVE `channel_allowed` UNCHANGED. This deviates from the scoping
brief, and here is the measurement.**

The brief asked for "the realtime chat-/bk- room policies" to switch. They must not:

- 🔴 **`bk-<booking>` narrowing breaks the owner's own radar screen.** `0108:38-41` states the rule
  and `143 B1` (`supabase/tests/143_realtime_chat_bk_suite.sql:101`) pins it: *"매칭 중(runner_id
  null) 오너가 레이더 채널에 못 들어간다"* must be false — the owner watches `bk-<booking>` at
  `matching`, before any runner exists. An accepted-only predicate makes `app/owner/radar.tsx` deaf
  for every user. And the room carries **no attacker→victim channel**: it is a `postgres_changes`
  room delivering UPDATEs of a booking row both parties can already SELECT, and `run channel write`
  is the only INSERT policy on `realtime.messages` (it returns false for every non-`run2-` topic).
- 🔴 **`chat-<thread>` narrowing turns `143 C3` red for a false reason.** C3 (`:84-95`) pins that a
  `cancelled_owner` booking's chat room stays open to its parties, *because the table lets them read
  it*. 0108's stated law is "**mirror the table, do not invent**" (`0108:33`). §C.4 leaves
  `threads party` / `messages party read` wide, so the faithful mirror is the wide predicate. A
  narrowed room would be a room that admits **fewer** people than the table — the exact deviation
  0108 §2 flagged as an "accepted delta" and refused to widen elsewhere.
- And it closes nothing: after §C.3 there is no thread to have a room, and no message to broadcast.

**Club chat is OUT OF SCOPE — measured, not assumed.** `club-chat-<session>` resolves through
`_club_shell_access(session, uid)` (`0108:137-140`, mirroring `club chat read`, `0052:250`), a
membership model with no `bookings` row and no `is_booking_party` in its path. Club delegation
bookings are assigned by `session_proposal_respond`, not `request_runner`. Nothing in §C touches a
`club_*` object.

### C.5 What is NOT touched (say it out loud — 0073/0075's lesson: unstated scope reads as a seal)

- `is_booking_party` itself — body and grants unchanged.
- `create-booking-hold`, `transition-booking`, `confirm-payment`, `settle-run` — **no edge function
  changes are expected in this slice** (§E.4 confirms this by measurement rather than assertion).
- The `payment_ok` bare CAS (`transition-booking/index.ts:29-51`) and the whole pay-after-run
  reroute — adjacent slice (O-5), pinned green by 146 D-15, which stays green.
- CSO #13 (`request_runner` lacks a `club_session_id` check) — adjacent, same file, different
  finding, **still open after this slice**.
- The latent `reviews.target_kind`/`target_id` issue (a party may review any profile id) — untouched;
  it becomes real the day a rating rollup lands.
- `profiles` grants, `incident_contact`, `verify_incident_tx`, `force_verify_incident_tx`,
  `notify_push`, `notify_chat_message`, `run_channel_allowed`, `my_channel_allowed`.
- DO-NOT-REFACTOR (CLAUDE.md): fitness collapsing hero; meetup stage machine / polling /
  `confirmHandoff`; the three deliberately-distinct availability predicates. Nothing here reaches
  any of them.
- **`app/` — this slice is server-only.** See §E.5 for the ui2 hand-off.

### C.6 What this slice legitimately claims when it lands

CSO finding #2 / F2 / B-11: **CLOSED for the surfaces O-4 names** — chat (thread + message + the push
that rides it), attacker-authored notifications, reviews, incidents (and, transitively, the phone
door). **The nomination itself remains open by decision, not by omission.** Whoever writes the
REGISTRY row or the CSO status table must carry that sentence, and must also carry that
`payment_ok` still verifies nothing (O-5's slice), so a booking still reaches `matching` with zero
money moved.

---

## D. Attack pins the adversarial reviewer must EXECUTE

Every pin runs under `set local role authenticated` + `set_config('request.jwt.claim.sub', …)`.
Assertions written `is not true` / `is not false`, never bare `if f()` — 143's header law: plpgsql
`if` skips on NULL in **both** directions, and a predicate that returns NULL instead of false turned
0 of 14 pins red once already. `_fail` args pre-computed into a variable (the 110 header law).

**Fixture:** attacker `atk` (owner) with own dog + own address; victim `vic` (a real `runners` row);
`b_pend` = attacker's booking, `runner_id = vic`, `status = 'runner_pending'`; `b_conf` = same pair
at `'confirmed'`; `b_cxo` = same pair at `'cancelled_owner'`; `b_done` = same pair at `'completed'`;
`b_open` = attacker's booking at `'matching'`, `runner_id` null; a `stranger`.

### Negative arms — pre-acceptance is refused

| pin | what the reviewer executes | must |
|---|---|---|
| **P-1** | as `atk`: `insert into chat_threads (booking_id) values (b_pend)` | RAISE (RLS) |
| **P-2** | as `vic`: same insert on `b_pend` | RAISE — the narrow is symmetric; a nominated runner cannot open the channel either |
| **P-3** | thread pre-seeded on `b_pend` **as postgres** (simulating a reassignment leftover); as `atk`: `insert into chat_messages (thread_id, sender_id, body)` | RAISE. ⚠ This is the arm that catches an implementation that gates only thread creation. |
| **P-4** | as `atk`: `insert into reviews (booking_id, author_id, target_kind, target_id, rating, visibility)` naming `vic` | RAISE |
| **P-5** | as `atk`: `insert into notifications (profile_id, kind, title, body, ref_id) values (vic, 'booking', '<attacker text>', '<attacker text>', b_pend)` | RAISE. **The lock-screen arm — the most direct form of the harm.** |
| **P-6** | as `atk`: `select open_incident_tx(b_pend, 'dog_injury')` | RAISE `booking_not_active` (**not** `not_party` — distinct facts, distinct names) |
| **P-7** | as `atk`: `select count(*) from incident_contact(b_pend)` | `0` — no open incident can exist, so the phone door never opens |
| **P-8** | repeat P-1/P-4/P-5/P-6 on `b_open` (`matching`, `runner_id` null) | all RAISE |
| **P-9** | repeat P-1/P-3/P-4/P-5 on `b_cxo` (`cancelled_owner`) as `atk` | all RAISE — the "nominate then cancel" bypass |
| **P-10** | as `stranger`: every one of P-1…P-6 against `b_conf` | all RAISE — the party gate is unweakened |
| **P-11** | `channel_allowed('chat-'||th_pend, atk, 'read')` and `(…, vic, 'read')` where `th_pend` is the postgres-seeded thread on `b_pend` | **`true`** — deliberate: the rooms are unchanged (§C.4), and this pin exists so the deviation from the brief is *recorded as a decision* rather than discovered later as a bug |
| **P-12** | `channel_allowed('bk-'||b_open, atk, 'read')` | **`true`** — the radar screen; 143 B1's property, re-pinned here |
| **P-13** | `is_booking_party_active(b_pend)` as `atk`, and as `vic` | both `is not true` |
| **P-14** | as `atk`, every write in P-1/P-3/P-4/P-5 against **another user's** `confirmed` booking | all RAISE |

### Positive arms — the product still works (a policy that admits nobody is green on every denial)

| pin | what the reviewer executes | must |
|---|---|---|
| **P-20** | `atk`→`vic` accept simulated: `update bookings set status='confirmed' where id=b_pend` (as postgres), then as `atk`: create thread, send message; as `vic`: send message | all SUCCEED |
| **P-21** | after P-20, `notify_chat_message` wrote a `notifications` row for the recipient (`0090:87-92`) | exactly one row, `title = '새 메시지'` |
| **P-22** | as `atk` and as `vic` on `b_conf`: `insert into notifications` at each other | SUCCEED — SOS / 러닝 중단 요청 / km 마일스톤 keep working (`api.ts:1889`, `:1900`, `:2565`, `:2589`) |
| **P-23** | as `atk` on `b_done` (`completed`): `insert into reviews`; as `vic` likewise | both SUCCEED — the review screens fire post-run |
| **P-24** | as `atk` on `b_conf`: `select open_incident_tx(...)`, then `select count(*) from incident_contact(b_conf)` | id returned; **2 rows** |
| **P-25** | **the nomination push still lands**: `request_runner` semantics reproduced as `service_role` — `insert into notifications (profile_id, kind, title, body, ref_id) values (vic, 'booking', '지명 러닝 요청', …, b_pend)` under `set local role service_role` | SUCCEEDS. 🔴 The single most important positive pin: it is what proves O-4's protected half survived. Mutation check: it must stay green when the *authenticated* arm (P-5) is red. |
| **P-26** | as `vic` (nominated, not accepted): `select id, status, runner_id from bookings where id = b_pend` | **1 row** — the runner can SEE the request |
| **P-27** | thread + messages seeded on `b_conf`, then `update bookings set status='cancelled_owner'`; as `atk` and `vic`: `select` the thread and its messages | both SUCCEED — history survives cancel (§C.2's accepted cost is write-only) |
| **P-28** | `channel_allowed('chat-'||th_conf, atk,'read')` after the same cancel | `true` — 143 C3's property re-pinned here |

### Mutation verification (each must redden the named pin **alone**)

| mutation | reddens |
|---|---|
| add `'cancelled_owner'` to the status set in `is_booking_party_active` | **P-9** |
| add `'runner_pending'` to the set | P-1…P-7, P-13 |
| revert policy (2) to `is_booking_party` while keeping (1) narrowed | **P-3** only |
| revert policy (4) to `is_booking_party` | **P-5** only |
| drop the state gate from `open_incident_tx` | **P-6**, **P-7** |
| drop `set search_path = public, pg_temp` from the new function body | **98 H1** |
| drop `sender_id = auth.uid()` from policy (2) | whichever existing pin owns sender forgery — if none does, **write one**; the property must not become unpinned as a side effect of this slice |

### Whole-harness obligation

`supabase/tests/harness.sh` must be **all green**. Any suite whose pinned behaviour *legitimately*
moves is updated **in the same slice** with a comment saying WHY and naming the new pin that owns the
new property (CLAUDE.md's suite law). Candidates measured in §A.5 — 143 (C3/B1 must stay green,
which is the point of §C.4), 146 (D-15 must stay green), 104 M9, 126, 130, 106 — all fixtures are
inside the new set, so **the expectation is zero suite edits**; a red one is a signal to re-read
§C.4, not to widen the predicate.

---

## E. Ordering + deploy

### E.1 Number — RE-RESOLVE AT WRITE TIME, do not copy this line

At this scout's write: `git ls-tree --name-only origin/redesign-v4 supabase/migrations/` → tip
`0111`; `0110` is **CLAIMED** in `REGISTRY.md` (routes public projection, worktree
`claude/elevation-gain-migration-6e96a5`) with its file not yet on origin; the registry's own row
says **`0112` = next free, suite `147`**. **The catalog's trace-revoke slice is racing for the same
row.** Per CLAUDE.md the check is two-sided and must be redone immediately before the file is
written:

```
git fetch && git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3
git ls-tree --name-only origin/redesign-v4 supabase/tests/ | grep -oE '[0-9]+' | sort -n | tail -1
```

⚠ `ls supabase/tests | sort` is LEXICAL. **Push the migration and its REGISTRY row in the same
breath.** `.githooks/pre-push` enforces both halves; ensure
`git config --local core.hooksPath /Users/sean/dev/daengrun/.githooks` (the **main clone's** stable
path, never `$(git rev-parse --show-toplevel)`).

### E.2 One file, in this order

1. header: O-4 verbatim + 🔵 provenance + the §C.4 deviation from the brief, argued
2. `create or replace function is_booking_party_active` with `set search_path = public, pg_temp`
   **in the body**, then the revoke/grant pair
3. the five switches of §C.3 as `drop policy if exists` + `create policy` under the same names
4. `create or replace function open_incident_tx(...)` with the state gate added
5. `comment on function` for both functions, stating the accepted/active set and why
   `cancelled_owner` is excluded

### E.3 Realtime policies

**None are changed** (§C.4). Stating this in the migration header is required, not optional — the
scoping brief asked for them and a silent omission would read as an oversight. Had they changed, they
would be ordinary migration statements guarded by `if to_regclass('realtime.messages') is null`
exactly as `0108:179-217` does.

### E.4 Edge functions — confirmed: no change expected

Measured, not assumed: `transition-booking`, `create-booking-hold`, `confirm-payment`, `settle-run`
all write through `admin()` (`_shared/ctx.ts`, SERVICE_ROLE_KEY), which does not consult RLS.
`open_incident_tx` has zero edge callers. **Verification step, not a belief:** run
`supabase functions deploy` for `transition-booking` after the migration and confirm it prints
**"No change found"** — the parity oracle from the production-verification memory. If it does not,
stop: something in this slice reached a function it should not have.

### E.5 Client follow-up — a SEPARATE item, owner **ui2**

Server-only slices must not strand a screen. Two live entry points open chat on a booking the server
will now refuse (§A.4, measured):

- `app/owner/home.tsx:1010` — 「러너와 채팅」 in the `pending` branch of the hero widget
- `app/owner/schedule.tsx:401` — the 「채팅」 chip on the booking sheet's runner card

Both must be hidden (not merely disabled with a shrug) when `rawStatus ∈ {payment_hold, matching,
runner_pending}` — **gate on `rawStatus`, never on the flattened `STATUS_MAP` value**, which collapses
all three into `'pending'` (CLAUDE.md's honesty law names this exact trap). `app/owner/schedule.tsx`
already reads `selected.rawStatus` at `:494-533`, so the idiom is in the file. The runner side needs
nothing (`app/runner/requests.tsx` has no chat entry). **This is not optional cleanup: between the
migration landing and the client shipping, those two buttons are dead buttons.** Sequence
server-first anyway (0103 §0's law — migration first, client second, never the reverse); the window
is honest-error, not silent-success.

### E.6 Reversal (O-4 is 🔵)

If Sean reverses D2: one migration re-creating the five policies with `is_booking_party` and dropping
the `open_incident_tx` state gate, plus `drop function is_booking_party_active`. No data migration,
no client change beyond restoring the two buttons. Say this in the header so the cost of reversal is
visible to whoever reads the ruling.

### E.7 Gate sequence

1. `supabase/tests/harness.sh` all green, including the new suite, **and** every mutation in §D
   verified to redden the named pin alone
2. from `app/`: `./node_modules/.bin/tsc --noEmit`, `node scripts/check-rpc-contracts.mjs`,
   `node scripts/check-route-native-imports.mjs` (all three, even for a server-only slice —
   `check-rpc-contracts` is the one that notices an RPC signature moving)
3. `/autoplan` — the standing gate for any migration (0059 doctrine); its subagents are read-only
   reviewers and do **not** replace the harness
4. land on trunk **with** the REGISTRY row
5. `bash scripts/deploy-migrations.sh` (dry-run, read the printed pending set), then
   `bash scripts/deploy-migrations.sh --push <NNNN>_<name>.sql` — the script cuts a fresh detached
   worktree at `origin/redesign-v4`, moves `HELD` files aside, and refuses if the pending set differs
   from what you named

### E.8 Verify-live (do not assume — read back)

1. `supabase migration list --linked` → the new number is remote
2. `supabase db query --linked "select pg_get_functiondef(oid) from pg_proc where proname='is_booking_party_active'"`
   → confirm `SET search_path TO 'public', 'pg_temp'` is present **in the definition** (the 98 H1
   property, confirmed in production and not merely in the file)
3. `supabase db query --linked "select tablename, policyname, cmd, with_check from pg_policies where policyname in ('threads party insert','messages party send','reviews author insert','noti party insert')"`
   → all four `with_check` texts name `is_booking_party_active`
4. `supabase db query --linked "select policyname from pg_policies where schemaname='realtime' and tablename='messages'"`
   → still exactly `party channel read`, `run channel read`, `run channel write` (proof §C.4 held)
5. the anon-definer check (99 S1's property) against production after a security migration
6. `node app/scripts/e2e-party-channels.mjs` → all arms pass (it writes as `service_role` on a
   `confirmed` booking, so a failure here means something narrowed that should not have)
7. `node app/scripts/e2e-run-channel.mjs` → full pass count as the script reports it (`n/n 통과`);
   the `run2-` family is untouched, so any drop is a regression this slice caused
8. **Manual, on a real client build:** owner nominates a runner → the runner's phone receives
   「지명 러닝 요청」. If that push does not land, the slice is wrong and must be reverted, because it
   is the half O-4 exists to protect. ⚠ Claim nothing about device visuals — hand Sean the smoke
   list; do not report a device-visual success.

---

## F. Facts only Sean holds

Kept to true lookups; nothing manufactured.

1. **O-4 itself — already decided 🔵**, announcer-directed under the overnight grant
   (`docs/decisions/awaiting-sean.md:274`). Nothing in §C requires re-asking it. It needs Sean's
   ratification only in the sense that every 🔵 does: one word to keep or reverse.
2. **The one genuinely new question this measurement raises, and it is small:** should post-cancel
   messaging survive on a booking that *was* confirmed? §C.2's status set says no (write-side only;
   history still readable). Recovering it needs `runner_accepted_at` — a column, a backfill, and
   edge-function writes. **[REC] do not ask him yet** — ask only if ops or a pilot user hits it,
   because the honest framing requires an incident to point at. Recorded here so the answer is not
   invented later.
3. **Nothing in this slice requires a credential's value**, so nothing is Sean-only for that reason.

⚠ Deliberately **not** on this list: the D1/D2 shape question. O-4 answered it. Re-asking a decided
question as if it were open is how two sessions ended up holding contradictory records of one money
decision (CLAUDE.md).

---

## G. Contradictions between artifacts

1. 🔴 **`0002_rls.sql:16` and production disagree about `is_booking_party`'s `search_path`.** The
   file says `set search_path = public`; production says `public, pg_temp`, because `0055:171` ALTERs
   every definer in a loop. Anyone reading the migration file believes the function is one
   `create or replace` away from losing `pg_temp` — **and they are right**, which is why §C.1
   creates a *new* function with the setting in its body rather than editing the old one. Neither
   document is wrong; together they are a trap, and this is its written form.
2. 🔴 **The scoping brief vs `143 B1` / `0108 §2` on the realtime rooms.** The brief lists "the
   realtime chat-/bk- room policies" among the surfaces that switch. `143 B1`
   (`supabase/tests/143_realtime_chat_bk_suite.sql:101`) and `0108:38-41` pin that `bk-<booking>`
   **must** admit the owner while `runner_id` is null at `matching` — the radar screen — and `143 C3`
   (`:84-95`) pins that `chat-<thread>` survives cancel. Switching them reddens two shipped pins for
   a false reason and closes nothing (no thread, no message exists pre-accept). §C.4 resolves it by
   **not** switching them, and P-11/P-12/P-28 pin the deviation so it reads as a decision.
3. ⚠ **"Incidents insert" is not where the docs imply.** The brief and §C.5 of the booking-entry
   contract both speak of an `incidents` INSERT policy. `"incidents report"` was **dropped by
   `0094:121`** and production has **no INSERT policy on `incidents` at all** (`pg_policies`,
   measured). The real gate is the definer `open_incident_tx` (`0094:124-159`), whose party check is
   written inline (`:140-142`) and does **not** call `is_booking_party` — so a grep-driven
   implementation would have narrowed five policies and silently left the incident path wide open.
   Same class of miss for `runs`: `"runs runner write"` was dropped by `0087:124`.
4. ⚠ **`is_booking_party`'s "9+ consumers" is an overcount that hides an undercount.** §C.5 of the
   booking-entry contract says narrowing "touches 9+ policies across `runs`, `reviews`,
   `chat_threads`, `chat_messages`, `incidents` and the 0108 realtime policies". Measured: only
   **five** policies need to change, **none** of them on `runs` or `incidents` — and **two** of the
   surfaces that do need changing (`noti party insert`, `open_incident_tx`) are **absent from that
   list** because they spell the predicate inline. The count was never the useful number; the
   *authority* of each writer is (`authenticated` vs `service_role`), and that is what §A.3 tabulates.
5. ⚠ **The phone-number consequence is un-named in every prior write-up.** §E.9 of
   `docs/security-booking-party-forgery.md` lists "chat, push, reviews, `incidents` rows, and the
   0108 realtime rooms" — it never follows the incident row to `incident_contact` (`0088:238-270`),
   which hands **both parties' `name` and `phone`** to anyone who can open an incident. It is inert
   today only because `profiles.phone` is universally NULL (PASS not integrated). **It arms itself
   with no further code change on the day PASS lands.** That raises this slice's urgency above what
   the existing documents convey, and §B B-11.g is where it is now written down.
6. ⚠ **A legal note that intersects the review surface.** `docs/decisions/awaiting-sean.md`
   (§0-quindecies, the non-location legal review) records: *"reviews RLS is party-scoped while the
   client queries all public runner reviews (anon → 401, 1 row; not exposed) — widening that read
   path is the moment §11 goes live, so it is a legal decision, not a UI fix."* §C.4 keeps every
   review READ policy exactly as it is, so this slice neither triggers nor forecloses that decision.
   Named so a future reader does not read "reviews narrowed" and think the legal item moved.
7. ⚠ **`REGISTRY.md` says `0112`/suite `147` are free; the catalog trace-revoke slice is racing for
   the same row.** Not a contradiction yet — it is the window CLAUDE.md's two-sided rule exists to
   close. §E.1 is the instruction; a number copied from this document instead of re-resolved is
   collision seven.
