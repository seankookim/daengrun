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
migration is one `create or replace` + **four** policy recreations to walk back, and §E.6 says how.
⚠ A **second** 🔵 lands in this file — §C.3(5)'s wider reportable set for `open_incident_tx`, taken
in review (F4) — and it reverses independently of O-4. §E.6 covers both.

**Written by:** scout, read-only. No code, migration, suite or production row was written by this
pass. Every production statement below was a `select` through `supabase db query --linked`.

**Trunk at scout's write time:** `8d33cde`, production migration tip **0111** (measured, §A.1).
**Revised 2026-08-19 after adversarial execution** (F1–F13, §Review log): trunk `c8e7d3f`, production
tip **0113** — the numbers moved twice while this document sat still, which is exactly why §E.1 says
re-resolve rather than copy.

---

## A. Measured state

### A.1 Production (SELECT-only, `supabase db query --linked`, 2026-08-19)

`supabase migration list --linked` — remote tip **0111** at the scout's pass. `0105` absent from
every environment (as `0111`'s REGISTRY row asserts); `0110` claimed on the registry but **not yet
applied** (its file was not on trunk). The live schema was exactly `0001…0104, 0106…0109, 0111`.

⚠ **Superseded numbers, re-resolved 2026-08-19 at this revision (F10).** `0110`, `0112` and `0113`
have all landed and are marked **BUILT + DEPLOYED + VERIFIED** in `supabase/migrations/REGISTRY.md`
(rows 152/154/155). Production tip is therefore **0113**, suite tip **148**, and REGISTRY row 156
says next free = **0114 / suite 149**. **The measured policy table below is UNAFFECTED and does not
need re-taking:** all three of those migrations are catalog/route work
(`0110_routes_public_projection`, `0112_views_no_client_dml`, `0113_routes_geometry_revoke`) and
`grep -lniE 'chat_threads|chat_messages|reviews|notifications|incidents|is_booking_party'` over the
three files returns **nothing**. The schema facts in §A.1 stand; only the numbers moved. Re-resolve
again at write time (§E.1) — between the scout's pass, the reviewer's execution (which measured
0112) and this revision, the tip advanced twice.

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
| `notifications` | `noti self update` | UPDATE | `profile_id = auth.uid()` — **USING only, no `with_check`** (0002:139) |
| `runs` | `runs runner update` | UPDATE | `exists (select 1 from bookings b where b.id = booking_id and b.runner_id = auth.uid())`, **both USING and WITH CHECK** (0057:432-434, which added the missing `with_check` to 0002:110's version) |

⚠ **Added 2026-08-19 (F12) — the two UPDATE policies, both UNCHANGED by this slice**, listed so the
inventory is the whole party-membership surface and not only the parts that move:

- **`noti self update`** is the recipient's read-receipt door (`read_at`). Being **USING-only**, a
  `with_check` is absent — which sounds alarming and is not: with no `with_check`, PostgreSQL
  **re-applies the USING expression to the post-update row**, so a caller cannot retarget a
  notification at someone else. Attempting `update notifications set profile_id = <victim>` is
  refused **`42501`** (the attacker's own measurement; the new row fails the re-applied USING). It
  therefore adds nothing to the B-11 chain: `profile_id` is already pinned to `auth.uid()` on both
  sides of the write, and the policy this slice narrows (`noti party insert`) is the only way a row
  is *created*. **Not narrowed** — it is scoped to the recipient, not to party membership, and gating
  it on booking status would strand a user unable to mark an old notification read.
- **`runs runner update`** is live trace persistence (`api.ts:1807` `saveTrace`), column-policed by
  `_guard_run_cols` (0057:436, 0079:53). `0087:82-84` explicitly rules it **UNTOUCHED** — "dropping
  it would take live trace persistence down with it." It needs no status filter of its own: no `runs`
  row can exist before `start_run`, which requires `confirmed`+ (§C.4), so the predicate is
  post-accept by construction.

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
| **terminal, acceptance NOT provable from status alone** | `expired`, `cancelled_owner`, `refund_pending` | ⚠ each is reachable from a pre-acceptance state: `matching`/`runner_pending → expired` (`0017:9`, cron 30-min sweep), `matching`/`runner_pending → cancelled_owner` (`0066:46-47`), `payment_hold`/`matching → refund_pending` (`0066:45-46`). **NOT-provable ≠ never-accepted — see the correction directly below.** |

⚠ **Corrected 2026-08-19 (F3, adversarial review).** An earlier revision of the row above implied
`refund_pending` was *only* a pre-acceptance sink. It is not. `enforce_booking_transition`'s final
arm — `else new.status in ('refund_pending')` (`0066:56`) — is a **catch-all over every status with
no explicit `when`**, i.e. `incident_review`, `no_show`, `cancelled_runner`, `cancelled_owner` and
`expired`. That is documented in prose at `0083:130` ("the transition map allows
`incident_review → refund_pending` and nothing else") and it is **exercised in production code, not
merely permitted**: `club_incident_settle` moves a settled incident to `refund_pending` whenever the
adjudicated refund is positive (`0072:179`, re-stated at `0080:1049`), and
`club_session_cancel_after_assign` walks `confirmed → cancelled_runner → refund_pending` in two
statements precisely because the direct edge is illegal (`0038:219-221`, its own comment says so).

So `refund_pending` is reachable **from both directions** — from `payment_hold`/`matching` where
nobody ever accepted, and from the accepted set after an incident settles. The status alone cannot
tell the two apart, which is why it stays **excluded** from §C.1's set; but the exclusion now costs
something real (a genuinely-accepted post-incident party loses write surfaces), and that cost is
named in §C.2 and is the reason for the 🔵 decision in §C.3(5).

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

🔴 **Corrected 2026-08-19 (F5, adversarial review). The earlier revision's headline claim was
STALE.** It said the owner-home hero widget renders 「러너와 채팅」 at `:1010` and named `:985/:1010`
as the entry points. **`app/app/owner/home.tsx` on trunk contains ZERO `/chat` navigation** — those
lines are gone (the hero widget was rebuilt; `bea1bc8` and after). The claim was true when the scout
measured it and false by the time the reviewer executed. Replaced with the exhaustive measured table
below: `grep -rn "pathname: '/chat'\|'/chat'" app src` over the whole client, at trunk `c8e7d3f`.

**Every `/chat` entry point in the client, and its status gate:**

| site | how it passes `bid` | reachable pre-accept? |
|---|---|---|
| `app/owner/schedule.tsx:401` | `{ bid: selected.id }` | 🔴 **YES — the one real dead button.** The booking sheet's runner card carries a 「채팅」 chip and the card is **unconditional**: its `runner` object falls back to `selected.runnerName`, which for an unmatched booking reads "러너를 찾고 있어요" (`:81`, `:118-124`). Shows at `matching` and `runner_pending`. |
| `app/owner/meetup.tsx:387` | `bookingId ? { bid: bookingId } : {}` | meetup is a post-accept screen, but the **`: {}` fallback** means a tap with no `bookingId` lands on `/chat` bare, where `fetchCurrentOwnerBookingId` re-filters on `IN_FLIGHT`. Safe by the fallback's own gate, not by the caller's. Not named in any prior write-up. |
| `app/runner/meetup.tsx:374` | `jobId ? { bid: jobId } : {}` | same shape, runner side. Same reasoning. |
| `app/owner/live.tsx:398`, `:716`, `:792` | `{ bid: bookingId }` | post-accept — `live` only mounts on an in-flight booking. ⚠ The reviewer measured these at `:230/:446/:505`; the file moved under `ae13416` the same day. **Line numbers in this file drift daily — re-grep, do not cite these.** |
| `app/runner/run.tsx:1170` | `router.push('/chat')` — no params | post-accept, and the bare push falls through to the `IN_FLIGHT` resolver. |
| `app/src/lib/push.ts:42` (`CHAT_TITLE`), `:48` (`RUN_STOP_TITLE`) | `{ bid: refId }` | post-accept **by construction**: both titles are written by triggers/flows that only fire on a booking with both parties set (`notify_chat_message` returns early when `runner_id` is null, `0090:58-61`). |

So: **one** genuine pre-accept dead button (`owner/schedule.tsx:401`), two `: {}` fallbacks that are
safe only because `/chat`'s own resolver is `IN_FLIGHT`-filtered, and nothing on owner-home at all.

- `STATUS_MAP` (`app/src/lib/api.ts:690-706`) flattens `payment_hold`, `matching` **and
  `runner_pending`** all to the display status `'pending'`. This is still the trap §E.5 gates
  against — the flattening is what makes a naive `status === 'pending'` check unable to tell a
  nominated booking from an unpaid one.
- ⚠ **`app/chat.tsx:139` renders the refusal with transient copy.** The `state === 'error'` branch
  says 「채팅을 불러오지 못했어요 — 잠시 후 다시 시도해주세요」 — *"try again in a moment"* — for what
  will be a **permanent-by-design** refusal after this migration. Waiting will never help. That is
  the second ui2 item in §E.5.
- `app/src/lib/api.ts:2507-2533` `openChatForBooking` explicitly supports the pre-match case —
  `peerName = '러너 (매칭 전)'` when `runner_id` is null — and calls `ensureThread` (`:2391-2401`),
  which **INSERTs into `chat_threads` as `authenticated`**. That INSERT is the policy this slice
  narrows.
- Everything else is already accept-gated **by the resolver, per the table above**: the `/chat`
  fallback with no `bid` (`fetchCurrentOwnerBookingId`, `:1038-1045`) filters on
  `IN_FLIGHT = ['confirmed','runner_enroute','picked_up','active']` (`:1025`) — which is what makes
  the two `: {}` fallbacks (`owner/meetup.tsx:387`, `runner/meetup.tsx:374`) and the bare push
  (`runner/run.tsx:1170`) safe; `owner/live.tsx` mounts only in flight. **`app/runner/requests.tsx` —
  the nomination inbox — contains no chat entry point at all** (grepped: zero `/chat`, zero `채팅`).
- Reviews: `app/owner/review.tsx:37` and `app/runner/review.tsx:50` insert directly; both are reached
  only from post-run screens (`owner/report.tsx:496`, `runner/done.tsx:166`).
- Incidents: **no client caller exists** — `open_incident_tx`, `verify_incident_tx` and
  `incident_contact` are grepped to zero call sites in `app/`. 0094's own header says the same.
- Client `notifications` INSERTs: `addRunEvent` (`:1889`), `notifyKmMilestone` (`:1900`), `sendSOS`
  (`:2565`, gated on `IN_FLIGHT`), `notifyRunStop` (`:2589`). All fire during `active`/live only.

⚒ **Consequence, stated honestly:** after this migration the schedule sheet's chat chip
(`owner/schedule.tsx:401`) **still renders at `matching`/`runner_pending`, and tapping it now
fails** — `ensureThread` throws a PostgREST RLS error and `app/chat.tsx` surfaces it *as a transient
error the user is told to retry* (`:139`). Nothing silently succeeds, so it is not a lie about
outcome; but it is a **dead button** telling the user a **false story about time** — both are
CLAUDE.md honesty-law violations, and this slice is server-only. One button, one string: the client
follow-up is named in §E.5 and belongs to **ui2**.

### A.5 Suites and e2e scripts that touch these surfaces

- `supabase/tests/143_realtime_chat_bk_suite.sql` — the realtime rooms. **C3** (`:84-95`) pins, in
  words, "chat_threads `threads party` is `is_booking_party()` with NO status gate — a cancelled
  booking's thread is still readable by its parties on the table, so the room must admit them too",
  and asserts the `cancelled_owner` fixture's room is open to both parties. **B1** (`:98-106`) pins
  that the owner alone may join `bk-<booking>` while `runner_id` is null at `matching` — the radar
  screen. Both are directly in the path of a naive narrow (§C.4).
- `supabase/tests/146_booking_entry_suite.sql` — **D-15** (`:776-798`) pins **`request_runner`'s**
  one-statement CAS green (*"request_runner의 한 문장 CAS(service_role)는 그대로 1행: 지명은 이
  경로에서만 일어난다"*), i.e. **B-11.2**, not B-11.1. ⚠ **Corrected 2026‑08‑19 (O-5 adversarial
  review, F13): an earlier revision of this line said D-15 pins the bare `payment_ok` CAS. It does
  not, and NOTHING does** — `grep -rn payment_ok supabase/tests/ supabase/functions/_test/` returns
  only prose inside `harness.sh:184`. The residual statement at
  `docs/security-booking-party-forgery.md:128` still stands, but it is carried by D-15's
  `request_runner` arm alone. This slice does not change D-15 and must not. *(Consequence for the
  adjacent slice: O-5's removal of `payment_ok` deletes behaviour that no pin asserts, which is why
  that contract adds one — a 400 `unknown action` pin — rather than relying on this one.)*
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
| **B-11.1** | `transition-booking` `payment_ok` → `matching` | owner-gated bare CAS (`transition-booking/index.ts:44-46`) | **verifies nothing about payment** — no PG receipt, no ledger row, no amount, zero money moved | unchanged **by this slice** — and **no pin asserts it** (F13; D-15 pins `request_runner`, §A.5). O-5 (pay-after-run) **deletes this step entirely** and adds a 400 `unknown action` pin in its place; this link then disappears from the chain, which shortens B-11 without narrowing it |
| **B-11.2** | `transition-booking` `request_runner` with `meta.runner_id = <any real runner>` → `bookings.runner_id = victim`, `status = runner_pending` | owner-gated (`:153`) | **allowed, and it is the product** (O-4: the nomination IS the request flow) | **unchanged — explicitly preserved** |
| **B-11.3** | victim receives 「지명 러닝 요청」 push | `service_role` insert (`:198`) → `notify_push` (`0024:44`) | product | **unchanged — explicitly preserved.** ⚠ residual, see NOTE below |
| **B-11.a** | attacker `insert into chat_threads (booking_id)` | `threads party insert` (0008:5) | ✅ allowed — `is_booking_party` true at `runner_pending` | 🚫 **refused** |
| **B-11.b** | attacker `insert into chat_messages` — arbitrary free text to the victim | `messages party send` (0002:145) | ✅ allowed | 🚫 **refused** (thread cannot exist; and the policy itself refuses) |
| **B-11.c** | that message → `notify_chat_message` (`0090:42-95`) → `notifications` row → `notify_push` → **push on the victim's phone**, sender name in the body (`0090:90`) | definer trigger, fires whenever `owner_id` and `runner_id` are both non-null (`:59-61`) | ✅ reached | 🚫 **unreachable** — no message, no trigger |
| **B-11.d** | attacker writes a notification **with a title and body of their choosing** straight at the victim | `noti party insert` (0009:7) | ✅ allowed — and `0024` pushes `title`/`body` **verbatim to a lock screen** (`0090:33-37` says so). This is the single most direct form of the harm O-4 names, and it needs no chat thread at all. | 🚫 **refused** |
| **B-11.e** | attacker inserts a `review` naming the victim | `reviews author insert` (0002:119) | ✅ allowed | 🚫 **refused** |
| **B-11.f** | attacker calls `open_incident_tx(booking)` | inline party gate, **no state gate** (`0094:140`) | ✅ allowed | 🚫 **refused** |
| **B-11.g** | …then `incident_contact(booking)` returns **both parties' `name` + `phone`** while the incident is open (`0088:238-270`) | party + "open incident exists" | ✅ reached. ⚠ **This is a phone-number disclosure the earlier write-ups did not name.** It is inert *today only because* `profiles.phone` is universally NULL (PASS not integrated, `0088`'s own comment) — it becomes live the day PASS lands, with no further code change. | 🚫 **unreachable transitively** — no incident can be opened pre-accept, so the state gate never passes. `incident_contact` itself is **not edited** (0094 §4 forbids narrowing that door). |
| **B-11.h** | attacker joins `chat-<thread>` / `bk-<booking>` realtime rooms | `party channel read` → `channel_allowed` (0108) | ✅ allowed | **unchanged — and see §C.4 for why narrowing them closes nothing and breaks two pins** |
| **B-11.i** | attacker uploads a photo to `media/{uid}/chat/{thread}/…` | `media owner insert` is **path-based only** (`0064:55-61`) | ✅ allowed | ✅ still allowed — but the object is an orphan: `media party read` delegates chat reads to `chat_messages` RLS (`0064:94-96`), and no message row can reference it. Named as an accepted residual, not a target. |

⚠ **NOTE on B-11.3 — the nomination push is NOT rate-limited (F11, adversarial review).** The only
brake in `request_runner` is a no-op on the *same* target: re-nominating the runner already in
`bookings.runner_id` changes nothing and emits nothing. **Alternating between two runners re-fires
indefinitely** — each call flips `runner_id`, so each call is a real change, each pushes 「지명 러닝
요청」 to the new target and 「지명이 변경됐어요」 to the displaced one (`:197-198`). Every one of
those inserts is `service_role`, so **this slice cannot touch it**: §C narrows `authenticated`
policies only, and O-4 protects the nomination push by decision. The result is a push-spam channel at
two strangers, with fixed system copy.

**This is named as a residual, not fixed here.** The fix belongs where the loop is — a rate limit in
`request_runner` itself (per-owner or per-booking nomination budget), in the same edge function O-5
is already rewriting. Adjacent slice; it does not change §C, and no pin here owns it. Naming it so
that "chat/push/reviews/incidents closed" is not read as "the notification surface is quiet".

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

**The cost of the status set instead — TWO states, not one (corrected, F3):**

1. **`cancelled_owner`** — after an owner cancels a **confirmed** booking (the 0066 en-route ladder,
   runner possibly already at the door), neither party can send a *new* chat message or write a
   review on it.
2. **`refund_pending` reached post-incident** — §A.2's correction: `club_incident_settle` puts a
   settled incident booking there whenever the refund is positive (`0072:179`, `0080:1049`), and
   `0038:219-221` walks `confirmed → cancelled_runner → refund_pending`. Those parties **did**
   accept, ran, and had an incident adjudicated — and they lose the same write surfaces. This is the
   costlier of the two, because it lands on exactly the bookings where the parties most plausibly
   still have something to say to each other.

**Reading the existing history is unaffected in both cases** (§C.4 keeps every SELECT policy wide),
and the realtime room stays open (143 C3 stays green). **Incident *reporting* is explicitly carved
back out of both** — see §C.3(5)'s 🔵 decision, which gives `open_incident_tx` its own wider set
precisely because these two states are where a safety report is most likely to be needed. If Sean or
ops later wants post-cancel/post-incident *messaging* back too, that is the moment to build
`runner_accepted_at` — record it as the named successor, not as a bug.

### C.3 Policies that SWITCH to `is_booking_party_active` — the complete list

**Four policies and one RPC.** The four are `drop policy if exists` + `create policy` under the
**same name** (policies are not `create or replace`-able; the view rule in CLAUDE.md is about views,
not policies). Every name below was read out of production `pg_policies` in §A.1, so every DROP has
a target. ⚠ Row (5) is an RPC and, after F4, **does not use `is_booking_party_active` at all** — so
"the five switches" is a misnomer worth not repeating: four policies switch to the narrow predicate,
one function gets a **wider** set of its own.

| # | table | policy | cmd | new predicate |
|---|---|---|---|---|
| 1 | `chat_threads` | `threads party insert` | INSERT | `is_booking_party_active(booking_id)` |
| 2 | `chat_messages` | `messages party send` | INSERT | `sender_id = auth.uid() and exists (select 1 from chat_threads t where t.id = thread_id and is_booking_party_active(t.booking_id))` |
| 3 | `reviews` | `reviews author insert` | INSERT | `author_id = auth.uid() and is_booking_party_active(booking_id)` |
| 4 | `notifications` | `noti party insert` | INSERT | `kind = 'booking' and ref_id is not null and is_booking_party_active(ref_id) and exists (select 1 from bookings b where b.id = notifications.ref_id and (notifications.profile_id = b.owner_id or notifications.profile_id = b.runner_id))` |
| 5 | *(RPC, not a policy)* `open_incident_tx` | — | — | a state gate raising a **distinctly named** error — but over its **OWN, WIDER set**, not `is_booking_party_active`. See the 🔵 decision below. |

Notes the implementer must not improvise around:

- **(2)** keeps `sender_id = auth.uid()`. Removing it would let a party forge the *sender* of a
  message inside a legitimate thread — a separate hole, currently closed, must stay closed.
- **(4)** keeps the recipient arm (`profile_id` must be one of the two parties) as a *separate*
  `exists`. Do not fold it into the predicate function: the function answers about `auth.uid()`, the
  recipient arm is about the row being written. Two different questions.
- **(5)** `open_incident_tx` is `create or replace function` — so it **must** re-state
  `set search_path = public, pg_temp` (it already does, `0094:131`; do not drop it). It raises a name
  of its own, e.g. `raise exception 'booking_not_reportable'`, never reusing `not_party` — 0094 §10's
  own law: "DISTINCT FACTS GET DISTINCT NAMES". Keep the `for update` and the
  one-open-incident-per-booking return. **Its set and its placement are specified immediately below
  and are not the implementer's to choose.**

#### 🔵 ANNOUNCER DECISION — `open_incident_tx` gets its own, wider set (F4)

**The finding.** Applying `is_booking_party_active` to `open_incident_tx` closes a **safety door**.
Two states in the excluded list are ones a genuinely-accepted party can legitimately be standing in
when they need to report:

- **`cancelled_owner`** — 0066's en-route cancel. The owner cancelled while **the runner was already
  moving, possibly at the door**. If something goes wrong in that exact minute, the state is
  `cancelled_owner` and, under a naive narrow, neither party can open an incident.
- **`refund_pending`** — reached post-incident from the accepted set (§A.2's correction). A party
  whose *first* incident settled would be unable to report a *second* fact about the same run.

A status filter designed to stop an attacker talking to a stranger must not also stop a real party
reporting a dog injury. **Chat, reviews and notifications are conveniences that can wait for an
accept; an incident report is not.**

**The decision (🔵, announcer-directed under the overnight grant — same class as O-4, reversible in
one word).** `open_incident_tx` gets its **own** state set:

> **reportable set = the accepted set (`confirmed`, `runner_enroute`, `picked_up`, `active`,
> `completed`, `no_show`, `incident_review`, `cancelled_runner`) `+ 'cancelled_owner' +
> 'refund_pending'`.**
>
> Chat, reviews and notifications — policies (1)–(4) — keep the **narrow** set unchanged.

**Why this is still safe, stated as the security argument it has to be.** The reportable set is
*strictly* the accepted set plus two states whose only pre-acceptance in-edges are
`matching`/`runner_pending`/`payment_hold`. So the attacker's B-11.f path is **still refused**: at
`runner_pending` the booking is not reportable, and to reach `cancelled_owner` or `refund_pending`
from there the attacker must cancel — which lands them in a state that *is* in the set. ⚠ **That is
the residual and it is accepted deliberately:** an attacker who nominates and then cancels CAN open
an incident on a stranger. What that buys them is bounded and is not the harm O-4 names — an
incident is **not free text delivered to the victim**. It writes a row on `incidents`, whose only
reader is the victim themselves plus ops; it sends no push; and `incident_contact`'s phone door
(B-11.g) opens on it — which is the real cost, and is why the set is *two states* and not "everyone".
The line drawn: **a party who was in the accepted set may still report; a party who never was,
cannot.** Reporting is not free text to a stranger — the victim must have been accepted once.

**Implementation shape.** Do **not** reuse `is_booking_party_active` here. Either an inline
`b.status not in (…)` list against the already-fetched `b` record (preferred — the row is in hand
from the `for update` select at `0094:136-137`, so it costs nothing and the set is legible at the
call site), or a second named predicate. If a second predicate is written it must be named for what
it means (`is_booking_reportable`), never a boolean flag on the first.

**Placement (F9) — AFTER the party gate and AFTER the idempotent existing-incident return.** Order:
① signed-in ② `for update` fetch ③ party gate (`0094:140-142`, house law: party before state) ④
`p_kind`/`p_severity` validation ⑤ **existing-open-incident lookup and early `return v_id`**
(`0094:148-152`) ⑥ **NEW state gate** ⑦ insert.

*Why after ⑤ and not before it:* an incident opened legitimately at `active` and still open when the
booking moves to `refund_pending` must keep returning its id. Placing the gate before ⑤ would make a
double-tap on an **already-open** case raise `booking_not_reportable` — turning 0094's deliberate
"a double-tap in an emergency does not produce two cases" affordance into a refusal at the worst
possible moment, and stranding the caller with no id to pass to `incident_contact`. The gate's job is
to refuse the **creation** of a case on a never-accepted booking; it has no business refusing to hand
back a case that already exists. Note the alternative — gate before ⑤ *with the wider set* — is
nearly moot, because `refund_pending` is now in the set; it is rejected anyway because it would still
refuse the id at `expired`, and because "gate the write, not the read" is the clearer law to leave
behind.

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

⚠ **NOTE (this review's F13 — see the Review log's numbering note) — what the realtime decision
actually leans on.** `party channel read`'s qual is
`realtime.messages.extension = 'broadcast' and my_channel_allowed(realtime.topic(), 'read')`
(`0108:191-195`, read back verbatim from production in §A.1). Apart from `extension`, it references
**no column of the row being read** — once the topic gate passes, the predicate is **row-independent**
and admits every message in that room. So `channel_allowed` is **defence-in-depth only**: it decides
who may join a topic, and nothing after that. The reviewer's wire-level execution confirmed the same
conclusion from the other side — the rooms are **receive-only** for a client, because
`run channel write` is the only INSERT policy on `realtime.messages` and its predicate is false for
every non-`run2-` topic, so no attacker→victim broadcast can originate in a `chat-`/`bk-` room at all.

**That is the load-bearing fact for §C.4's [REC].** Leaving the rooms wide is safe *because the
containment is the write policy and the underlying table's RLS*, not because `channel_allowed` is
carefully scoped — it is not, and it does not need to be. Recording it here so that a future reader
who tightens `channel_allowed` understands they are adjusting a door, not a lock, and so that anyone
who ever adds an INSERT policy for a `chat-` topic knows this entire paragraph stops being true.

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
  reroute — adjacent slice (O-5), which **deletes** the arm. ⚠ It is **not** pinned by 146 D-15
  (**O-5 review's F13**, §A.5 — not this review's F13, see the Review log's numbering note) —
  nothing pins it at all; O-5 adds the pin that outlives it. D-15 itself pins `request_runner` and
  stays green either way.
- CSO #13 (`request_runner` lacks a `club_session_id` check) — adjacent, same file, different
  finding, **still open after this slice**.
- The latent `reviews.target_kind`/`target_id` issue (a party may review any profile id) — untouched;
  it becomes real the day a rating rollup lands.
- `profiles` grants, `incident_contact`, `verify_incident_tx`, `force_verify_incident_tx`,
  `notify_push`, `notify_chat_message`, `run_channel_allowed`, `my_channel_allowed`.
- **The two UPDATE policies (F12): `noti self update` and `runs runner update`** — inventoried in
  §A.1 with the reason each is correctly left alone (read receipts are recipient-scoped, not
  party-scoped; `runs` rows cannot exist pre-accept, and `0087:82-84` rules that policy untouched).
  Listed here so "unstated scope reads as a seal" does not apply to them either.
- **Rate-limiting `request_runner`'s nomination push (F11)** — a real residual, `service_role`,
  unreachable from any policy this slice writes. Adjacent slice, same file as O-5.
- **`dogs.memo` on the pre-accept request card (F6)** — a real residual on the client. ui2, adjacent.
- DO-NOT-REFACTOR (CLAUDE.md): fitness collapsing hero; meetup stage machine / polling /
  `confirmHandoff`; the three deliberately-distinct availability predicates. Nothing here reaches
  any of them.
- **`app/` — this slice is server-only.** See §E.5 for the ui2 hand-off.

### C.6 What this slice legitimately claims when it lands

CSO finding #2 / F2 / B-11: **CLOSED for the surfaces O-4 names** — chat (thread + message + the push
that rides it), **attacker-authored notification rows** (the `noti party insert` path, B-11.d),
reviews, incident *opening on a never-accepted booking* (§C.3(5)'s reportable set), and transitively
the phone door. **The nomination itself remains open by decision, not by omission.** Whoever writes
the REGISTRY row or the CSO status table must carry that sentence, and must also carry that
`payment_ok` still verifies nothing (O-5's slice), so a booking still reaches `matching` with zero
money moved.

⚠ **Narrowed 2026-08-19 (F6). "Attacker-authored notifications: CLOSED" was too broad as written.**
What closes is the **row** — the attacker can no longer INSERT a `notifications` row with a title and
body of their choosing (B-11.d, the lock-screen arm). The **nomination push's own body is fixed
system copy** written by `request_runner` as `service_role` (`transition-booking/index.ts:198`).
**But the push opens the 요청 탭, and that card renders owner-authored free text:**

- `app/runner/requests.tsx:233-266` renders `req.dogName`, `req.breed`, `req.weightKg` and — at
  `:264-266` — **`req.memo`**, labelled 「메모: …」, `numberOfLines={2}`.
- `memo` is `dogs.memo`, mapped straight through at `app/src/lib/api.ts:768`
  (`mapOpenRequest`, the directed/nominated path; `REQ_SELECT` at `:782` pulls `dogs(… memo …)`).
- The attacker owns the dog (B-11.0 — every ownership check legitimately passes), so **`dogs.memo` is
  attacker-controlled free text**, and it reaches a nominated stranger **pre-acceptance**, on the
  strength of a nomination alone.

**State the residual plainly rather than claim a closure that is not there:** after this slice an
attacker still has a ~2-line free-text channel to any runner they can nominate, rendered inside a
product surface, needing no chat thread and no accept. It is quieter than a lock-screen push (in-app,
truncated, requires opening the tab) but it is not nothing, and it is **not** closed by anything in
§C — `dogs.memo` reaches the card through the runner's legitimate read of an open/directed request,
not through any policy this slice touches.

**Follow-up, adjacent — owner: ui2, NOT this slice.** Do not render `dogs.memo` on a card whose
booking is `runner_pending` (or in the open pool) — the memo is care instructions for a runner who
has *accepted*, so gate it on the accepted set and show it on the job screen instead. **`dogName`,
`breed` and `weightKg` stay** — they are the information the runner actually decides on, and a dog's
name is not a message. Server-side hardening (a length cap or a memo column split) is a *third*
slice and is not recommended yet: the client gate removes the delivery path, which is the harm.

---

## D. Attack pins the adversarial reviewer must EXECUTE

Every pin runs under `set local role authenticated` + `set_config('request.jwt.claim.sub', …)`.
Assertions written `is not true` / `is not false`, never bare `if f()` — 143's header law: plpgsql
`if` skips on NULL in **both** directions, and a predicate that returns NULL instead of false turned
0 of 14 pins red once already. `_fail` args pre-computed into a variable (the 110 header law).

🔴 **THE SQLSTATE LAW — every INSERT arm asserts `42501` BY NAME.** `146:24-27` states it and
explains why: *"ONLY the expected sqlstate counts… caught by NAME, not `when others`, which would
swallow a typo'd column as a security pass."* Write
`exception when insufficient_privilege then <pass>` (or `when sqlstate '42501'`), and let every other
sqlstate propagate as a failure. **A `when others` here is not a shortcut, it is a false green** —
and F1 below is the proof that this suite was *already* producing one.

🔴 **F1 — P-1 and P-2 as originally specified were FALSE GREENS. Fixture corrected.**
`chat_threads.booking_id` is **UNIQUE** — `booking_id uuid not null references bookings unique`
(`supabase/migrations/0001_init.sql:362`), constraint `chat_threads_booking_id_key`. And this §D's
own fixture **pre-seeds a thread on `b_pend`** so that P-3 has one to insert a message into. So
P-1's and P-2's inserts, aimed at the same booking, raise **`23505` unique_violation** — not
`42501` — **and they do so with the migration ABSENT.** Under a `when others` catch, both pins pass
against an unpatched database and the suite measures the unique index instead of the policy. Two of
the three headline denial pins asserted nothing.

**The fix is fixture-shaped, not assertion-shaped** (though both are applied): the thread-creation
arms need a `runner_pending` booking that has **no thread**.

**Fixture (corrected):** attacker `atk` (owner) with own dog + own address; victim `vic` (a real
`runners` row); a `stranger`.

| handle | status | `runner_id` | thread pre-seeded? | used by |
|---|---|---|---|---|
| `b_pend` | `runner_pending` | `vic` | **YES** (as postgres — simulates a reassignment leftover) | P-3 (message insert), P-7, P-11, P-13 |
| **`b_pend2`** ← **NEW** | `runner_pending` | `vic` | **NO** | **P-1, P-2** (thread insert) |
| `b_conf` | `confirmed` | `vic` | no | P-10, P-22, P-24, P-27, P-28 |
| `b_cxo` | `cancelled_owner` | `vic` | **NO** (see P-9) | P-9 |
| **`b_cxo2`** ← **NEW** | `cancelled_owner` | `vic` | **YES** | P-9's message arm |
| `b_done` | `completed` | `vic` | no | P-23 |
| `b_open` | `matching` | null | no | P-8, P-12 |
| `b_other` | `confirmed` | two other users | **NO** for P-14's thread arm | P-14 |
| **`b_other2`** ← **NEW** | `confirmed` | two other users | **YES** | P-14's message arm |

**The general rule this encodes — apply it to any arm added later:** *a thread-INSERT arm must target
a booking with **no** thread; a message-INSERT arm must target one **with** a thread. Never the same
booking for both.* Every multi-arm pin (P-8, P-9, P-10, P-14) must be read against this rule before
it is written, because the unique index will silently absorb the arm that violates it.

⚠ **Mutation-verify the fixture itself, not only the migration** (0112's lesson, REGISTRY row 154 —
"a fixture that establishes the property under test makes the suite an echo of itself"): run P-1/P-2
**with the migration reverted** and confirm they go **RED**. If they stay green, the fixture is still
measuring the unique index.

### Negative arms — pre-acceptance is refused

| pin | what the reviewer executes | must |
|---|---|---|
| **P-1** | as `atk`: `insert into chat_threads (booking_id) values (**b_pend2**)` | RAISE, **sqlstate `42501` asserted by name**. ⚠ NOT `b_pend` — see F1. |
| **P-2** | as `vic`: the same insert, also on **`b_pend2`** | RAISE `42501` — the narrow is symmetric; a nominated runner cannot open the channel either. ⚠ Sharing `b_pend2` with P-1 is safe **only because P-1 must be refused**: no row is created, so P-2 cannot collide on the unique index. If P-1 ever legitimately succeeds, P-2 must move to its own booking — otherwise P-2 silently becomes a 23505 pin. |
| **P-3** | on `b_pend` (thread pre-seeded as postgres); as `atk`: `insert into chat_messages (thread_id, sender_id, body)` | RAISE `42501`. ⚠ This is the arm that catches an implementation that gates only thread creation. |
| **P-4** | as `atk`: `insert into reviews (booking_id, author_id, target_kind, target_id, rating, visibility)` naming `vic`, on `b_pend` | RAISE `42501` |
| **P-5** | as `atk`: `insert into notifications (profile_id, kind, title, body, ref_id) values (vic, 'booking', '<attacker text>', '<attacker text>', b_pend)` | RAISE `42501`. **The lock-screen arm — the most direct form of the harm.** |
| **P-6** | as `atk`: `select open_incident_tx(b_pend, 'dog_injury')` | RAISE **`booking_not_reportable`** (**not** `not_party`, and **not** `42501` — this is a plpgsql raise, `P0001`; assert on the MESSAGE. Distinct facts, distinct names.) |
| **P-7** | as `atk`: `select count(*) from incident_contact(b_pend)` | `0` — no open incident can exist, so the phone door never opens |
| **P-8** | on `b_open` (`matching`, `runner_id` null): P-1's thread insert, P-4, P-5, P-6 | all RAISE (`42501` for the three inserts, `booking_not_reportable` for P-6). `b_open` has no thread, so the thread arm is clean; **do not add a message arm here** — there is no thread to reference and it would fail on the FK, another false green. |
| **P-9** | thread arm on **`b_cxo`** (no thread); message arm on **`b_cxo2`** (thread seeded); review + notification arms on either; all as `atk` | all RAISE `42501` — the "nominate then cancel" bypass. ⚠ Split across two bookings per F1. **No `open_incident_tx` arm here** — `cancelled_owner` is now *inside* the reportable set (§C.3(5)'s 🔵 decision); its coverage is P-31/P-32. |
| **P-10** | as `stranger`: P-1 (on a thread-free booking), P-3…P-6 against `b_conf` | all RAISE — the party gate is unweakened. Note the stranger's thread arm must also target a thread-free booking, or it measures the unique index too. |
| **P-11** | `channel_allowed('chat-'||th_pend, atk, 'read')` and `(…, vic, 'read')` where `th_pend` is the postgres-seeded thread on `b_pend` | **`true`** — deliberate: the rooms are unchanged (§C.4), and this pin exists so the deviation from the brief is *recorded as a decision* rather than discovered later as a bug |
| **P-12** | `channel_allowed('bk-'||b_open, atk, 'read')` | **`true`** — the radar screen; 143 B1's property, re-pinned here |
| **P-13** | `is_booking_party_active(b_pend)` as `atk`, and as `vic` | both `is not true` |
| **P-14** | as `atk`: thread insert on **`b_other`** (thread-free), message insert on **`b_other2`** (thread seeded), review + notification on either — all **another user's** `confirmed` booking | all RAISE `42501`. ⚠ Split across two bookings per F1: `b_other` at `confirmed` would otherwise be *inside* the new set, so a thread arm colliding on 23505 here is the same false green wearing a different status. |
| **P-15** | as `atk`: `insert into chat_messages` with **`sender_id = vic`** into a **legitimate `confirmed`** thread (`b_conf`, where `atk` IS an admitted party) | RAISE `42501` — **see P-15's own paragraph below; this pin is NEW and unconditional (F2).** |

#### P-15 — the sender-forgery property gets an owner (F2)

The original §D listed "drop `sender_id = auth.uid()` from policy (2)" as a mutation with the
conditional remedy *"whichever existing pin owns sender forgery — if none does, write one."* **The
reviewer executed the mutation: removing `sender_id = auth.uid()` from `messages party send` left the
harness at 660/0. Nothing owns it.** The conditional is therefore resolved, and P-15 above is an
**unconditional new pin**, not a contingency.

The property is **true in production today** — `messages party send`'s `with_check` is
`sender_id = auth.uid() and exists (…)` (§A.1, read from `pg_policies`) — so P-15 is green the moment
it is written, against the unpatched database. That is correct and is the point: this slice must not
*silently inherit* an unpinned invariant it is rewriting the policy around. §C.3(2) says the clause
stays; P-15 is what makes that sentence enforceable instead of aspirational.

**Shape:** `b_conf` is `atk`-owner/`vic`-runner and inside the accepted set, so `atk` is a fully
legitimate party and the `exists (… is_booking_party_active …)` arm **passes**. The only thing that
can refuse the insert is the `sender_id` clause. That isolation is what makes the pin diagnostic —
run it as `vic` inserting with `sender_id = atk` as well, so neither direction is assumed from the
other.

### Positive arms — the product still works (a policy that admits nobody is green on every denial)

| pin | what the reviewer executes | must |
|---|---|---|
| **P-20** | `atk`→`vic` accept simulated: `update bookings set status='confirmed' where id=b_pend` (as postgres), then as `atk`: create thread, send message; as `vic`: send message | all SUCCEED |
| **P-21** | after P-20, `notify_chat_message` wrote a `notifications` row for the recipient (`0090:85-91`) | **exactly one row PER RECIPIENT**, `title = '새 메시지'`. ⚠ **Corrected (F8): "exactly one row" was wrong and would have been red on a correct implementation.** The trigger's throttle is scoped to the recipient — `where n.profile_id = v_to and n.ref_id = v_booking and n.title = '새 메시지' and n.read_at is null` (`0090:71-80`) — so it suppresses a *second* nudge to the same person, not a first nudge to the other one. **P-20 sends in both directions** (`atk`→`vic`, then `vic`→`atk`), so the correct expected count is **2 rows total, 1 per `profile_id`**. Assert `count(*) group by profile_id` = 1 for each, never a bare total. |
| **P-22** | as `atk` and as `vic` on `b_conf`: `insert into notifications` at each other | SUCCEED — SOS / 러닝 중단 요청 / km 마일스톤 keep working (`api.ts:1889`, `:1900`, `:2565`, `:2589`) |
| **P-23** | as `atk` on `b_done` (`completed`): `insert into reviews`; as `vic` likewise | both SUCCEED — the review screens fire post-run |
| **P-24** | as `atk` on `b_conf`: `select open_incident_tx(...)`, then `select count(*) from incident_contact(b_conf)` | id returned; **2 rows** |
| **P-25** | **the nomination push still lands**: `request_runner` semantics reproduced as `service_role` — `insert into notifications (profile_id, kind, title, body, ref_id) values (vic, 'booking', '지명 러닝 요청', …, b_pend)` under `set local role service_role` | SUCCEEDS. 🔴 The single most important positive pin: it is what proves O-4's protected half survived. Mutation check: it must stay green when the *authenticated* arm (P-5) is red. |
| **P-26** | as `vic` (nominated, not accepted): `select id, status, runner_id from bookings where id = b_pend` | **1 row** — the runner can SEE the request |
| **P-27** | thread + messages seeded on `b_conf`, then `update bookings set status='cancelled_owner'`; as `atk` and `vic`: `select` the thread and its messages | both SUCCEED — history survives cancel (§C.2's accepted cost is write-only) |
| **P-28** | `channel_allowed('chat-'||th_conf, atk,'read')` after the same cancel | `true` — 143 C3's property re-pinned here |

#### The 🔵 incident-opener decision gets its own pins (F4)

§C.3(5) gives `open_incident_tx` a **wider** set than every other surface. A decision with no pin is
a comment, so the wider set gets a matched positive/negative pair. Neither is covered by any pin
above: P-6 alone would stay green under a naive `is_booking_party_active` gate, which is precisely the
implementation the 🔵 decision rejects.

| pin | what the reviewer executes | must |
|---|---|---|
| **P-31** | 🔵 **positive — the safety door stays open.** `b_saf` = `atk`/`vic` booking driven through a **real accept path**: `runner_pending → confirmed → runner_enroute → cancelled_owner` (as postgres, respecting `enforce_booking_transition`; `0066:47,52` make every edge legal). Then as `atk`: `select open_incident_tx(b_saf, 'dog_injury')`; and again as `vic` | **an id is returned, both times** — a party who really was accepted may still report at `cancelled_owner`, the 0066 en-route-cancel state where the runner may be standing at the door. 🔴 This is the pin that fails if the implementer reuses `is_booking_party_active` here. |
| **P-32** | 🔵 **positive — post-incident.** `b_ref` driven `confirmed → cancelled_runner → refund_pending` (`0038:219-221`'s own two-step, because the direct edge is illegal). As `atk`: `open_incident_tx(b_ref, 'other')` | id returned — `refund_pending` reached from the accepted set is reportable (§A.2's F3 correction) |
| **P-33** | 🔵 **negative — the wider set is still a set.** P-6 restated as this decision's own negative: at `runner_pending` (`b_pend`) and at `matching` (`b_open`), `open_incident_tx` still raises `booking_not_reportable` | RAISE — **the widening did not become "everyone"**. P-6/P-8 already execute this; P-33 exists so the *decision* has a negative of its own recorded next to its positive, and so a future widening of the reportable set reddens something. |
| **P-34** | **idempotence survives the state move (F9's placement).** As `atk` on `b_conf`: `open_incident_tx(...)` → `id1`. Then (as postgres) `b_conf → incident_review → refund_pending`. Then as `atk`: `open_incident_tx(b_conf, …)` again | returns **`id1`, not a raise and not a new id** — the existing-open-incident return (`0094:148-152`) sits BEFORE the state gate, so an already-open case still hands back its id. 🔴 This pin is what a gate placed too early reddens; it is the executable form of §C.3(5)'s placement argument. |

### Mutation verification (each must redden the named pin **alone**)

⚠ **Corrected 2026-08-19 (F7).** The "reddens X **alone**" column was written from the pin list as
*designed*, not as *executed*. Three rows were wrong: two understated their blast radius (a mutation
reddens every pin that shares the property, and saying "alone" where it is false trains the next
reader to ignore a real second failure), and the `runner_pending` row over-claimed P-1/P-2, which
were the false greens F1 fixes. **"Alone" is kept only where it was verified to hold.**

| mutation | reddens |
|---|---|
| add `'cancelled_owner'` to the status set in `is_booking_party_active` | **P-9** alone |
| add `'runner_pending'` to the set | **P-3, P-4, P-5, P-6, P-7, P-13** — ⚠ **and, only after F1's fixture fix, P-1 and P-2.** Before that fix P-1/P-2 were green either way (23505 from `chat_threads_booking_id_key`, not 42501), so this row silently over-claimed two pins. **Re-run this mutation after the fixture change and confirm P-1/P-2 actually flip** — it is the check that proves F1 landed. |
| revert policy (2) to `is_booking_party` while keeping (1) narrowed | **P-3** alone |
| revert policy (4) to `is_booking_party` | **P-5**, **P-8's notification arm**, **P-9's notification arm** — ⚠ **not "P-5 alone"**: policy (4) is the one predicate behind every attacker-authored `notifications` insert, and P-8 (`matching`) and P-9 (`cancelled_owner`) each exercise it on their own booking. A reviewer who saw three reds and expected one would have gone looking for a second defect that does not exist. |
| drop the state gate from `open_incident_tx` | **P-6**, **P-7**, **P-8's `open_incident` arm** — ⚠ P-8 repeats the incident arm on `b_open`, so it reddens too. (P-33 also reddens; it is the same property restated for the 🔵 decision, which is deliberate — a decision's own negative should move with it.) |
| replace the 🔵 reportable set with `is_booking_party_active` in `open_incident_tx` | **P-31**, **P-32** — the 🔵 decision's positives. Nothing else moves; every negative stays green, which is exactly why the decision needed positives of its own. |
| move the state gate **before** the existing-open-incident return | **P-34** alone — F9's placement argument, executable |
| drop `set search_path = public, pg_temp` from the new function body | **98 H1** |
| drop `sender_id = auth.uid()` from policy (2) | **P-15** — ⚠ **resolved, no longer conditional (F2).** The reviewer executed this mutation against the harness and it reddened **nothing** (660/0 with the clause removed). P-15 is now an unconditional pin in the negative-arms table and this row names it. |

### Whole-harness obligation

`supabase/tests/harness.sh` must be **all green**. Any suite whose pinned behaviour *legitimately*
moves is updated **in the same slice** with a comment saying WHY and naming the new pin that owns the
new property (CLAUDE.md's suite law). Candidates measured in §A.5 — 143 (C3/B1 must stay green,
which is the point of §C.4), 146 (D-15 must stay green), 104 M9, 126, 130, 106 — all fixtures are
inside the new set, so **the expectation is zero suite edits**; a red one is a signal to re-read
§C.4, not to widen the predicate.

⚠ **Baseline count — take it, do not cite it.** The reviewer executed §C's target state at **660/0**.
`0112` and `0113` have since landed with their own suites, and their REGISTRY rows record **663/0**
and **666/0**. So the number to beat is whatever `harness.sh` reports on the tree you cut from —
**measure it before the first line of the migration is written**, and the only meaningful assertion
afterwards is *baseline + this suite's pin count, zero red*. A count copied from this document is the
same class of mistake as a migration number copied from it (§E.1).

⚠ **And mutation-test the FIXTURE, not only the migration.** F1 is this slice's own instance of the
defect `0112` recorded (REGISTRY row 154): every pin passed both before and after, because the suite
was measuring a fixture-established property — there, a view the suite itself recreated; here, a
unique index the suite's own seeding triggered. **All green is not evidence. All green plus every
mutation reddening its named pin is.**

---

## E. Ordering + deploy

### E.1 Number — RE-RESOLVE AT WRITE TIME, do not copy this line

**This line has now been wrong twice. Read that as the instruction, not as a defect in the document.**

- scout's pass: file tip `0111`, `0110` claimed-but-absent, registry said next free **`0112` / suite
  `147`**.
- reviewer's execution: `0112_views_no_client_dml.sql` had landed **and deployed**; next free was
  **`0113` / suite `148`**.
- **this revision (F10, re-resolved just now):** `0113_routes_geometry_revoke.sql` has *also* landed
  and deployed. Trunk carries `0110`, `0112`, `0113`; every one is **BUILT + DEPLOYED + VERIFIED** in
  `REGISTRY.md` (rows 152/154/155). Suite tip **148**. Registry row 156: **next free = `0114`, suite
  `149`**.

The catalog slice that was "racing for the same row" took `0112` **and** `0113` while this contract
was being reviewed. **Re-resolve again immediately before writing the file** — per CLAUDE.md the
check is two-sided (a number is taken when EITHER its row or its file reaches origin):

```
git fetch && git ls-tree --name-only origin/redesign-v4 supabase/migrations/ | tail -3
git ls-tree --name-only origin/redesign-v4 supabase/tests/ | grep -oE '[0-9]+' | sort -n | tail -1
```

⚠ `ls supabase/tests | sort` is LEXICAL. **Push the migration and its REGISTRY row in the same
breath.** `.githooks/pre-push` enforces both halves; ensure
`git config --local core.hooksPath /Users/sean/dev/daengrun/.githooks` (the **main clone's** stable
path, never `$(git rev-parse --show-toplevel)`).

### E.2 One file, in this order

1. header: O-4 verbatim + 🔵 provenance + the §C.4 deviation from the brief, argued, **and the second
   🔵 — §C.3(5)'s wider reportable set for `open_incident_tx`, with the safety argument.** Two
   distinct 🔵 decisions ride in this file; a header naming only one is how the second gets read as
   an implementer's improvisation.
2. `create or replace function is_booking_party_active` with `set search_path = public, pg_temp`
   **in the body**, then the revoke/grant pair
3. the **four policy** switches of §C.3 (1)–(4) as `drop policy if exists` + `create policy` under
   the same names
4. `create or replace function open_incident_tx(...)` — §C.3(5): the state gate over the **wider
   reportable set**, placed after the party gate AND after the existing-open-incident return (F9),
   raising `booking_not_reportable`; `set search_path = public, pg_temp` re-stated in the body
5. `comment on function` for both functions. `is_booking_party_active`'s comment states the
   accepted/active set and why `cancelled_owner` and `refund_pending` are excluded;
   `open_incident_tx`'s states **why its set is deliberately wider than every policy's** — otherwise
   the next reader "fixes" the inconsistency

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

Server-only slices must not strand a screen. **Corrected 2026-08-19 (F5): the earlier list named
`app/owner/home.tsx:985/:1010`, which no longer exist — owner-home has ZERO `/chat` navigation on
trunk.** The measured list (§A.4's table, re-grepped at `c8e7d3f`) is **three items, and only the
first is a dead button**:

**ui2-1 — `app/owner/schedule.tsx:401`, the 「채팅」 chip on the booking sheet's runner card.** The
only genuine pre-accept `/chat` entry point in the client. Must be **hidden** (not merely disabled
with a shrug) when `rawStatus ∈ {payment_hold, matching, runner_pending}` — **gate on `rawStatus`,
never on the flattened `STATUS_MAP` value**, which collapses all three into `'pending'` (CLAUDE.md's
honesty law names this exact trap). `app/owner/schedule.tsx` already reads `selected.rawStatus` at
`:494-533`, so the idiom is in the file. **This is the one true dead button; between the migration
landing and this shipping, it is a visible action with no effect.**

**ui2-2 — `app/chat.tsx:139`, honest copy for a permanent refusal.** The `state === 'error'` branch
renders 「채팅을 불러오지 못했어요 — 잠시 후 다시 시도해주세요」. After this migration that string is
told to a user whose refusal is **permanent by design** — waiting will never help, and the app is
lying about time even while it correctly refuses the action. Needs a distinguishable pre-accept
branch, e.g. 「수락 전에는 채팅을 열 수 없어요」 ("chat can't be opened before the runner accepts"),
ideally with the reason (러너가 요청을 수락하면 채팅이 열려요). **ui2 words it** — the strings above
are placeholders for the shape, not approved copy; Korean UI copy is the one thing that stays Korean
(CLAUDE.md) and is ui2's call. The branch condition should key off the RLS refusal specifically, not
every error, so a genuine network failure keeps its retry message.

**ui2-3 — the two `: {}` fallbacks, verify-only, likely no change.** `app/owner/meetup.tsx:387` and
`app/runner/meetup.tsx:374` push `/chat` with `bid` **if present, else `{}`**. Neither was named in
any prior write-up. They are safe today because the bare-`/chat` resolver re-filters on `IN_FLIGHT`
(`api.ts:1025`, `:1038-1045`) — **safe by the callee's gate, not the caller's**, which is a fragile
place for a guarantee to live. ui2 should confirm the fallback still lands on the empty state rather
than an error, and consider passing nothing at all rather than an empty param object.

Nothing else needs work: `owner/live.tsx` (three sites), `runner/run.tsx:1170` and `src/lib/push.ts`
(`:42`, `:48`) are post-accept by construction, and `app/runner/requests.tsx` has no chat entry point
at all. ⚠ **Separately, `runner/requests.tsx` carries the F6 memo item** (do not render `dogs.memo`
on a `runner_pending` card) — that is the same owner (ui2) but a different finding; see §C.6.

Sequence server-first regardless (0103 §0's law — migration first, client second, never the reverse);
the window is honest-error, not silent-success.

### E.6 Reversal — **two 🔵 decisions, two independent reversals**

**O-4 (the whole slice).** If Sean reverses D2: one migration re-creating policies (1)–(4) with
`is_booking_party` and dropping the `open_incident_tx` state gate, plus
`drop function is_booking_party_active`. No data migration; the only client change is un-hiding
`owner/schedule.tsx:401`'s chip and reverting `chat.tsx`'s copy branch (§E.5). Say this in the header
so the cost of reversal is visible to whoever reads the ruling.

**§C.3(5)'s reportable set (the second 🔵) reverses on its own, and narrower.** If Sean judges that
an incident must *not* be openable at `cancelled_owner`/`refund_pending`, the change is **one list
in one function body** — replace the inline set with `is_booking_party_active(p_booking)` — plus
deleting P-31/P-32 and keeping P-33. It does not touch a policy, a grant, or the other 🔵. Recorded
separately because a reader who sees "O-4 reversed" must not assume the safety-door widening went
with it, or the reverse.

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
4. **NEW (F4) — the second 🔵, and it is the one worth his single word.** §C.3(5) gives
   `open_incident_tx` a wider set than every other surface so that a party who **was** accepted can
   still report a safety incident at `cancelled_owner` (0066 en-route cancel — runner possibly at the
   door) and at post-incident `refund_pending`. The accepted residual: an attacker who nominates a
   stranger and then cancels their own booking **can** open an incident on them — no push, no free
   text, but it does open `incident_contact`'s phone door (inert until PASS lands, §B B-11.g). The
   judgement Sean actually owns is the direction of the trade: **a real party losing the ability to
   report a hurt dog, versus an attacker gaining a phone number they cannot read today.** This
   document takes the first as the worse outcome. Reversible in one list (§E.6), and it does not move
   with O-4.

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
   **four** policies need to change (plus one RPC), **none** of them on `runs` or `incidents` — and **two** of the
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
7. ⚠ **`REGISTRY.md` said `0112`/suite `147` were free; the catalog trace-revoke slice was racing for
   the same row — and won it, twice.** ✅ **RESOLVED as history (F10):** `0112` and `0113` both landed
   and deployed while this contract was under review. Not a contradiction — it was the window
   CLAUDE.md's two-sided rule exists to close, and the rule closed it. Next free is `0114`/suite
   `149` at this revision. §E.1 is the standing instruction; a number copied from this document
   instead of re-resolved is collision seven.

---

## Review log — adversarial execution of §C, 2026-08-19

**Verdict: FIX-CONTRACT-FIRST** (on evidence and scope, not on design). §C was executed in the
harness: **660/0, all 41 §D pins green, and the realtime rooms proven receive-only at the wire.** The
target end state is sound. What failed review was the *contract's* evidence — two headline pins that
could not fail, a property with no owner, a state machine read one arm short, and a client table that
had gone stale under the document. Every fix below is applied above; nothing in §C.1's predicate or
§C.4's realtime [REC] changed.

⚠ **Numbering note — two review streams share this file's F-labels.** F1–F13 **below and everywhere
this revision cites them** are *this* review (O-4 / §C, executed 2026-08-19). §A.5 and §C.5 also cite
an **F13 belonging to the O-5 (pay-after-run) review** — the `payment_ok` / 146 D-15 correction,
marked there as such. They are unrelated findings that collided on a number; both call-sites are now
qualified. Do not merge the two lists.

| # | finding | fix applied |
|---|---|---|
| **F1** | **P-1/P-2 were FALSE GREENS.** `chat_threads.booking_id` is UNIQUE (`chat_threads_booking_id_key`, `0001_init.sql:362`) and §D's fixture pre-seeds a thread on `b_pend` for P-3 — so both thread-insert pins raise `23505`, not `42501`, **with the migration absent**. | New thread-free `b_pend2` for P-1/P-2 (`b_pend` keeps its thread for P-3); same split for P-9 (`b_cxo2`) and P-14 (`b_other2`); the general rule written out; **every INSERT arm now asserts sqlstate `42501` BY NAME, never `when others`** (`146:24-27`). |
| **F2** | **`sender_id = auth.uid()` had NO owner** — the reviewer deleted it from `messages party send` and the harness stayed **660/0**. | The conditional mutation row is resolved into **P-15, an unconditional new pin** (vic inserting with `sender_id = atk` on a legitimate `confirmed` thread → `42501`). Green today; that is the point. |
| **F3** | **`refund_pending` IS reachable from provably-accepted states.** `0066:56`'s `else` arm is a catch-all over `incident_review`/`no_show`/`cancelled_runner`/`cancelled_owner`/`expired`; documented at `0083:130`; exercised by `club_incident_settle` (`0072:179`, `0080:1049`) and `0038:219-221`. | §A.2's row corrected with the full mechanism; it stays excluded from §C.1 (still not *provable* from status), but **§C.2's cost paragraph now names `refund_pending` (post-incident) alongside `cancelled_owner`** as a real, second cost. |
| **F4** | 🔵 **DECISION — the state gate on `open_incident_tx` closes a SAFETY door.** At `cancelled_owner` (runner possibly at the door) and `refund_pending` (post-incident) a genuinely accepted party could no longer report. | `open_incident_tx` gets its **own, wider reportable set = accepted set + `cancelled_owner` + `refund_pending`**; policies (1)–(4) keep the narrow set. Specified in §C.3(5) with its security argument and residual, pinned by **P-31/P-32 (positive)** and **P-33 (negative)**, reversible independently (§E.6), and surfaced to Sean as §F.4. |
| **F5** | **§A.4/§E.5 were STALE:** `owner/home.tsx` on trunk has **zero** `/chat` navigation — `:985/:1010` no longer exist. | Replaced with the exhaustive measured table (`schedule.tsx:401` = the one real pre-accept dead button; `owner/meetup.tsx:387` + `runner/meetup.tsx:374` = the previously-unnamed `: {}` fallbacks; `owner/live.tsx` ×3, `runner/run.tsx:1170`, `push.ts:42,48` = post-accept). Plus `chat.tsx:139`'s transient copy for a permanent refusal → ui2. |
| **F6** | **§C.6's "attacker-authored notifications: CLOSED" was too broad.** The push body is fixed system copy, but the 요청 탭 card it opens renders `req.memo` (`runner/requests.tsx:264-266`; `memo = dogs.memo` via `api.ts:768`) — **owner-authored free text reaching a nominated stranger pre-acceptance.** | Claim narrowed to the notification *row*; the residual stated explicitly; client follow-up named for ui2 (don't render `dogs.memo` on a `runner_pending` card; name/breed/weight stay) as **adjacent, not this slice**. |
| **F7** | **The mutation table's "alone" column was written from design, not execution** — two rows understated blast radius, one over-claimed pins F1 had masked. | revert policy (4) → **P-5 + P-8(noti) + P-9(noti)**; drop the incident state gate → **P-6, P-7, P-8(open_incident)**; add `runner_pending` → **P-3…P-7, P-13** (P-1/P-2 only after F1's fixture fix, and re-running that mutation is now the check that F1 landed). "Alone" kept only where verified. |
| **F8** | **P-21's "exactly one row" would have been red on a correct implementation.** `notify_chat_message` throttles **per recipient** (`0090:71-80`), and P-20 sends both directions. | → **"exactly one row PER RECIPIENT"**, 2 rows total, asserted `group by profile_id`. |
| **F9** | Placement of the new state gate was unspecified. | Specified: **after the party gate AND after the idempotent existing-incident return** (`0094:148-152`), with the reason — an already-open incident whose booking moved to `refund_pending` must still return its id rather than raise at the worst possible moment. The alternative (before, with the wider set) is named and rejected. **P-34** pins it. |
| **F10** | Migration numbers stale. | Production tip re-resolved: **0113** (`0112` and `0113` both deployed), suite tip **148**, **next free `0114` / suite `149`**; §A.1's numbers fixed with proof the measured policy table is unaffected; §E.1 rewritten as "wrong twice, re-resolve again". |
| **F11** | **NOTE — the nomination push is not rate-limited.** `request_runner` no-ops only on the *same* target; alternating two runners re-fires indefinitely, all `service_role`. | Named as a residual under §B B-11.3 with the fix pointed at `request_runner` itself — **adjacent slice**, untouchable from here (this slice narrows `authenticated` only). |
| **F12** | §A.1's policy inventory incomplete. | Added `noti self update` (USING-only; retarget refused `42501`) and `runs runner update`, both marked **unchanged**, so the inventory is the whole surface rather than only the parts that move. |
| **F13** | **NOTE — `party channel read`'s qual is row-independent once the topic gate passes** (`0108:191-195`); it is defence-in-depth only. | Recorded in §C.4 as the thing the realtime [REC] actually leans on: containment is the **write** policy + the base table's RLS, not `channel_allowed`'s scoping. Flags what stops being true if an INSERT policy is ever added for a `chat-` topic. |

**Implement as designed after these.** The predicate (§C.1), the four policy switches (§C.3(1)–(4)),
the realtime non-change (§C.4) and the ordering (§E.2) all survived execution unchanged. The
corrections are to the pins that were supposed to prove it, the state-machine fact underneath the
exclusion list, the client table, the numbers — **and one design change, the 🔵 in §C.3(5), which
came out of the review rather than the plan.**
