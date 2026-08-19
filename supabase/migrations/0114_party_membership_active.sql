-- ═══ 0114: party membership narrowed to accepted states (closes /cso #2's last open half, F2 / B-11) ═══
--
-- Contract: `docs/contracts/party-membership-status-filter-contract.md` (v2 — scouted, attacked,
-- F1–F13 folded in). Every fact cited below was measured there against production, not inferred.
--
-- ═══ §0 THE HOLE ═══
-- `is_booking_party(b_id)` (`0002:15-22`) asks exactly one question — *is auth.uid() the owner or
-- the runner of this booking row?* — and **no question about the booking's status**. So the moment
-- a booking carries `runner_id = <victim>`, the victim is a full party for every write surface
-- that predicate guards, whether or not they ever said yes.
--
-- Setting `runner_id` to any real runner is not an exploit: it is `request_runner`, the product's
-- nomination flow (`transition-booking/index.ts:148-200`), owner-gated and working as designed.
-- 0111 closed the *forged* booking row; what it explicitly did NOT close (its own header says so)
-- is the legitimate one. The chain, executed by 0111's reviewer, is B-11:
--
--   B-11.0  attacker creates a hold with their OWN dog, OWN address, OWN fares  → every
--           ownership check legitimately passes. Nothing is forged.
--   B-11.1  `payment_ok` → `matching`. A bare owner-gated CAS that verifies NOTHING about
--           payment — no PG receipt, no ledger row, zero money moved. ⚠ Still open after this
--           file; it is O-5 (pay-after-run), which DELETES the arm.
--   B-11.2  `request_runner` with `meta.runner_id = <any real runner>` → `runner_id = victim`,
--           `status = runner_pending`. **This IS the product and stays open by decision (O-4).**
--   B-11.3  victim receives 「지명 러닝 요청」. `service_role` insert, so no policy here can touch
--           it. **Protected on purpose.**
--   B-11.a  attacker INSERTs `chat_threads` on the booking                   → closed by §2 (1)
--   B-11.b  attacker INSERTs `chat_messages` — arbitrary free text at a stranger → closed by §2 (2)
--   B-11.c  that message trips `notify_chat_message` (`0090:42-95`) → a push on the victim's
--           phone with the sender's name in it                              → unreachable after (2)
--   B-11.d  attacker writes a `notifications` row with a title and body OF THEIR CHOOSING
--           straight at the victim — `0024` pushes both VERBATIM to a lock screen. **The most
--           direct form of the harm, and it needs no chat thread at all.**  → closed by §2 (4)
--   B-11.e  attacker INSERTs a `review` naming the victim                   → closed by §2 (3)
--   B-11.f  attacker calls `open_incident_tx(booking)` — party gate, no state gate → closed by §3
--   B-11.g  …then `incident_contact(booking)` returns BOTH parties' `name` AND `phone` while the
--           incident is open (`0088:238-270`). Inert TODAY only because `profiles.phone` is
--           universally NULL (PASS not integrated) — **it arms itself with no further code change
--           on the day PASS lands.** → unreachable transitively once §3 refuses the open.
--
-- ═══ §0b THE DECISION THIS BUILDS TO — O-4, 🔵 ═══
-- `docs/decisions/awaiting-sean.md:274` (§0-overnight), announcer-decided under Sean's overnight
-- grant, verbatim:
--
--   > **D2-narrow**: the nomination itself still reaches the runner (system-authored notification
--   > — that IS the request flow), but free-text chat, reviews and incidents require the booking
--   > to be in an accepted/active state; party membership for those surfaces gets a status filter.
--   > *Rationale:* "attacker-authored push/chat to a stranger is the harm, a system '요청이 왔어요'
--   > is the product."
--
-- ⚠ 🔵 means announcer-decided, NOT ✅ (Sean's own words on origin). Per CLAUDE.md *a relayed
-- decision is evidence, not authority.* Reversal cost, so it is visible to whoever rules: one
-- migration re-creating policies (1)–(4) with `is_booking_party`, dropping §3's state gate, and
-- `drop function is_booking_party_active`. No data migration. Client side: un-hide
-- `owner/schedule.tsx`'s chat chip and revert `chat.tsx`'s copy branch.
--
-- ═══ §0c THE SECOND 🔵 — `open_incident_tx` GETS ITS OWN, WIDER SET (contract F4) ═══
-- A separate announcer decision, taken in adversarial review, **which reverses independently of
-- O-4.** Applying the narrow predicate to the incident opener closes a SAFETY door:
--
--   · `cancelled_owner` is 0066's en-route cancel — the owner cancelled while **the runner was
--     already moving, possibly at the door.** If something goes wrong in that exact minute, that
--     is the status the booking is standing in.
--   · `refund_pending` is reachable FROM the accepted set, not only from `payment_hold`/`matching`
--     (contract F3): `0066:56`'s final `else` arm is a catch-all, and `club_incident_settle`
--     (`0072:179`, `0080:1049`) and `0038:219-221` both exercise it. A party whose FIRST incident
--     settled would be unable to report a SECOND fact about the same run.
--
-- A status filter designed to stop an attacker talking to a stranger must not also stop a real
-- party reporting a hurt dog. **Chat, reviews and notifications are conveniences that can wait for
-- an accept; an incident report is not.** So §3's reportable set = the accepted set + those two.
--
-- Why that is still safe: both added states have pre-acceptance in-edges only from
-- `matching`/`runner_pending`/`payment_hold`, so B-11.f at `runner_pending` is still refused.
-- ⚠ **Accepted residual, deliberately:** an attacker who nominates and then cancels their own
-- booking CAN open an incident on a stranger. What that buys is bounded — an incident is not free
-- text delivered to the victim; it writes a row whose only readers are the victim and ops, and it
-- sends no push. It does open B-11.g's phone door, which is the real cost and is why the set is
-- two states and not "everyone". **The line drawn: a party who was in the accepted set may still
-- report; a party who never was, cannot.**
-- Reversal: replace §3's inline list with `is_booking_party_active(p_booking)`. One list, one
-- function body. It does not touch a policy or a grant, and it does NOT move with O-4.
--
-- ═══ §0d WHAT THIS FILE DOES **NOT** CLOSE — say it out loud (0073/0075's lesson) ═══
-- ⓐ **The nomination push is not rate-limited** (contract F11). `request_runner` no-ops only on
--    the SAME target; **alternating between two runners re-fires indefinitely** — each call flips
--    `runner_id`, so each is a real change, pushing 「지명 러닝 요청」 at the new target and
--    「지명이 변경됐어요」 at the displaced one (`:197-198`). Every one is `service_role`. This file
--    narrows `authenticated` policies only, so it cannot reach that loop at all. The fix belongs
--    in `request_runner` (a per-owner/per-booking nomination budget) — adjacent slice, same file
--    as O-5. Named so "chat/push/reviews/incidents closed" is not read as "the notification
--    surface is quiet".
-- ⓑ **`dogs.memo` reaches a nominated stranger pre-acceptance** (contract F6). The 요청 탭 card
--    renders `req.memo` (`app/runner/requests.tsx:264-266` ← `api.ts:768` ← `dogs.memo`), and the
--    attacker owns the dog, so it is **attacker-controlled free text** — a ~2-line channel needing
--    no chat thread and no accept. It arrives through the runner's legitimate read of a directed
--    request, not through any policy here. Client fix (do not render the memo on a
--    `runner_pending` card; name/breed/weight stay) is **ui2's**, adjacent.
-- ⓒ **`payment_ok` still verifies nothing** — a booking still reaches `matching` with zero money
--    moved. O-5's slice.
-- ⓓ **CSO #13** (`request_runner` lacks a `club_session_id` check) — same file, different finding,
--    still open.
-- ⓔ `reviews.target_kind`/`target_id` (a party may review any profile id) — untouched; it becomes
--    real the day a rating rollup lands.
-- ⓕ `is_booking_party` itself, `incident_contact`, `verify_incident_tx`, `noti self update`,
--    `runs runner update`, every club_* object, and `app/` (this slice is server-only).
--
-- ═══ §0e THE ACCEPTED COST — TWO STATES LOSE **SEND** AND KEEP **READ** ═══
-- `cancelled_owner` and `refund_pending` are excluded from the narrow set because neither is
-- *provable* from status alone (each has a pre-acceptance in-edge; if `cancelled_owner` were
-- included the whole slice would fall to one extra call — nominate, cancel, be a full party again).
-- The price is real and is not hidden:
--   1. after an owner cancels a CONFIRMED booking, neither party can send a new chat message or
--      write a review on it;
--   2. a post-incident `refund_pending` booking — parties who **did** accept, ran, and had an
--      incident adjudicated — loses the same write surfaces. This is the costlier of the two.
-- **Reading is unaffected in both cases: every SELECT policy stays wide** (§4), so chat history,
-- reviews and the incident row all survive, and §3 explicitly carves incident *reporting* back
-- out for exactly these two states.
-- The strictly cleaner predicate is a monotone witness — a `bookings.runner_accepted_at` stamped
-- by both `runner_accept` arms — and it is **deliberately not built here**: it needs a column, a
-- backfill of every historical booking (or existing chats lock silently), writes in both accept
-- arms, AND a **clear** in `request_runner`'s CAS and `runner_decline`, because otherwise a
-- `confirmed → matching → request_runner` reassignment leaves the previous runner's stamp behind
-- and hands the new unaccepted nominee full party rights — reintroducing this exact hole. That is
-- an edge-function change plus a data migration: different blast radius, different reviewer. It is
-- the **named successor**, not a bug, and the moment to build it is when ops or a pilot user
-- actually hits the cost above.
--
-- ═══ §0f THE REALTIME POLICIES ARE **NOT** CHANGED — this is a decision, not an omission ═══
-- The scoping brief asked for "the realtime chat-/bk- room policies" to switch. They must not, and
-- stating that here is required (contract §E.3) because a silent skip reads as an oversight.
--   · `bk-<booking>` narrowed would **break the owner's own radar screen**: `0108:38-41` and
--     `143 B1` pin that the owner watches `bk-<booking>` at `matching`, before any runner exists.
--     An accepted-only predicate makes `app/owner/radar.tsx` deaf for every user.
--   · `chat-<thread>` narrowed turns **`143 C3`** red for a false reason — it pins that a
--     `cancelled_owner` booking's room stays open *because the table lets its parties read it*,
--     and 0108's stated law is "mirror the table, do not invent". §4 keeps the table's SELECT
--     policies wide, so the faithful mirror is the wide predicate. A narrowed room would admit
--     FEWER people than the table.
--   · And it closes nothing: after §2 there is no thread to have a room and no message to
--     broadcast. The rooms are **receive-only** — `run channel write` is the only INSERT policy on
--     `realtime.messages` and its predicate is false for every non-`run2-` topic, so no
--     attacker→victim broadcast can originate in a `chat-`/`bk-` room at all.
-- ⚠ For the future reader: `party channel read`'s qual references no column of the row being read
-- once the topic gate passes (`0108:191-195`), so `channel_allowed` is **defence-in-depth only** —
-- a door, not a lock. Containment is the write policy plus the base table's RLS. **If anyone ever
-- adds an INSERT policy for a `chat-` topic, this entire paragraph stops being true.**
-- Club chat (`club-chat-<session>`) resolves through `_club_shell_access` (`0052:250`), a
-- membership model with no `bookings` row in its path — out of scope, measured, not assumed.
--
-- ═══ §0g SUITE + MUTATION ═══
-- `supabase/tests/149_party_active_suite.sql` (P-1 … P-34). Baseline on this tree **666/0**,
-- after **694/0**. Nine mutations executed; the full map with every red SET lives in that header.
-- Three of them never reach a pin because §5 refuses the deploy first — the fail-closed half:
--   · policy (4) reverted to `is_booking_party` → `0114: write policy did not switch to
--     is_booking_party_active: notifications.noti party insert`
--   · policy (2) reverted                        → the same, `chat_messages.messages party send`
--   · `set search_path` dropped from §1's body   → `0114: definer written without pg_temp in its
--     body: is_booking_party_active(uuid)`
-- ⚠ Two of the contract's predicted red sets came back FALSE and are corrected there, both in the
-- informative direction: adding `runner_pending` to §1's set does **not** redden the incident pins
-- (§3 consults its own set and never calls §1's predicate — the 🔵 decision's independence, proven
-- rather than asserted), and reverting policy (2) reddens P-9's message arm as well as P-3.

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §1  the new predicate — narrow, and NEXT TO the wide one rather than replacing it
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠⚠ `set search_path = public, pg_temp` IS IN THE BODY, and that is load-bearing. The repo file
-- for `is_booking_party` says `set search_path = public` only (`0002:16`); production carries
-- `public, pg_temp` because `0055:171` ALTERs every definer in a loop. **ALTER-applied config is
-- reset by `create or replace`** (CLAUDE.md, measured). A definer born without pg_temp in its own
-- header lets a caller `create temp table bookings(...)` and shadow the table this gate reads.
-- Suite 98 H1 sweeps the whole schema every harness run and would catch it — the rule is to not
-- need catching.
--
-- `is_booking_party` is **NOT modified** — not its body, not its grants. Two predicates, one wide
-- and one narrow, every policy stating which it means. Editing the wide one in place would force
-- every SELECT policy to narrow at the same time, which §4 explains is wrong.
create or replace function is_booking_party_active(b_id uuid) returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  -- `coalesce(exists(...), false)` — belt on a brace. `exists` cannot yield NULL, but 143's header
  -- law is that a predicate returning NULL instead of false is invisible to a plpgsql `if` in BOTH
  -- directions, and that once turned 0 of 14 pins red. Nothing that guards a write returns NULL.
  select coalesce(exists (
    select 1 from bookings b
    where b.id = b_id
      and (b.owner_id = auth.uid() or b.runner_id = auth.uid())
      and b.status in (
        -- accepted and live: reachable only through `runner_accept` (both arms land on
        -- `confirmed`, `transition-booking/index.ts:121`)
        'confirmed', 'runner_enroute', 'picked_up', 'active',
        -- post-run terminal, PROVABLY accepted: every in-edge is from the four above (`0066:49-55`)
        'completed', 'no_show', 'incident_review',
        -- only reachable from `confirmed`/`runner_enroute`
        'cancelled_runner'
      )
  ), false);
$$;

comment on function is_booking_party_active(uuid) is
  '0114 (O-4 🔵): is_booking_party PLUS a status filter — true only when the caller is a party AND the
booking is in the accepted set (confirmed·runner_enroute·picked_up·active·completed·no_show·
incident_review·cancelled_runner). Guards the four WRITE surfaces a nominated-but-not-accepted
stranger could otherwise be reached through: chat thread, chat message, review, notification row.
⚠ EXCLUDED and the exclusion is the interesting half: draft·quoted·payment_hold·matching·
runner_pending never saw an accept, and expired·cancelled_owner·refund_pending are each reachable
DIRECTLY from a pre-acceptance state (0017:9, 0066:45-47) — so status alone cannot tell "cancelled
after the runner accepted" from "cancelled while a nomination was pending". Including
cancelled_owner would defeat the whole slice in one extra call: nominate, cancel, be a full party
again. The cost is that a genuinely-accepted party loses SEND (not READ) after an owner cancel and
after a post-incident refund_pending; recovering it needs a bookings.runner_accepted_at column, a
backfill, and a clear in request_runner — the named successor, not a bug.
⚠ NOT for reads. Every SELECT policy deliberately keeps plain is_booking_party (0114 §4), and
open_incident_tx deliberately uses a WIDER set of its own (0114 §3) — do not "fix" that
inconsistency, it is two decisions.';

-- Grants: the 0094 shape. `authenticated` MUST hold execute or every policy in §2 refuses
-- unconditionally and chat/reviews/notifications go dark for everybody — §5 fails the deploy on
-- that rather than letting it become a harness mystery. `service_role` bypasses RLS anyway; the
-- grant is there so a definer running under it can call the predicate directly.
revoke execute on function is_booking_party_active(uuid) from public, anon;
grant  execute on function is_booking_party_active(uuid) to authenticated, service_role;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §2  the four WRITE policies switch — drop + recreate under the SAME name
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- Policies are not `create or replace`-able (the view rule in CLAUDE.md is about views). Every
-- name below was read out of production `pg_policies`, so every DROP has a live target and the
-- `if exists` is belt, not a guess. **Nothing except the predicate changes** — every other term is
-- carried across verbatim.

-- (1) chat_threads — B-11.a. `ensureThread` (`api.ts:2391-2401`) INSERTs here as `authenticated`;
--     this is the statement that stops.
drop policy if exists "threads party insert" on chat_threads;
create policy "threads party insert" on chat_threads
  for insert with check (is_booking_party_active(booking_id));

-- (2) chat_messages — B-11.b, and B-11.c dies with it (no message, no `notify_chat_message`).
--     ⚠ `sender_id = auth.uid()` STAYS. Removing it would let a legitimate party forge the SENDER
--     of a message inside a legitimate thread — a different hole, currently closed, and until this
--     slice **owned by no pin at all**: the contract's reviewer deleted the clause and the harness
--     stayed 660/0. Suite 149's P-15 is its owner now, so the clause is enforceable rather than
--     aspirational.
drop policy if exists "messages party send" on chat_messages;
create policy "messages party send" on chat_messages
  for insert with check (
    sender_id = auth.uid()
    and exists (
      select 1 from chat_threads t
      where t.id = chat_messages.thread_id and is_booking_party_active(t.booking_id)
    )
  );

-- (3) reviews — B-11.e. Only the WRITE moves; all three read policies stay as they are (§4).
drop policy if exists "reviews author insert" on reviews;
create policy "reviews author insert" on reviews
  for insert with check (
    author_id = auth.uid() and is_booking_party_active(booking_id)
  );

-- (4) notifications — B-11.d, the lock-screen arm and the most direct form of the harm: `0024`
--     pushes `title` and `body` VERBATIM to a phone, and this path needs no chat thread.
--     ⚠ The recipient arm stays a SEPARATE `exists`. Do not fold it into the predicate function:
--     the function answers about `auth.uid()` (may the CALLER write here), the recipient arm is
--     about the row being written (is the TARGET one of the two parties). Two different questions.
--     ⚠ This does NOT touch the nomination push (B-11.3): `notify` writes through `admin()`, the
--     SERVICE_ROLE client, and `service_role` never consults a policy. That separation of
--     authority is what makes O-4 buildable at all — the product half and the harm half were
--     already on two different roles.
drop policy if exists "noti party insert" on notifications;
create policy "noti party insert" on notifications
  for insert with check (
    kind = 'booking'
    and notifications.ref_id is not null
    and is_booking_party_active(notifications.ref_id)
    and exists (
      select 1 from bookings b
      where b.id = notifications.ref_id
        and (notifications.profile_id = b.owner_id or notifications.profile_id = b.runner_id)
    )
  );

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §3  open_incident_tx — B-11.f, and the second 🔵: its OWN, WIDER reportable set
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- There is **no INSERT policy on `incidents`** in production — `incidents report` was dropped by
-- `0094:121`. The gate is this definer, whose party check is spelled out inline and does **not**
-- call `is_booking_party`. A grep-driven implementation would have narrowed four policies and left
-- the incident path wide open. (Same class of miss for `runs`: `runs runner write` went at
-- `0087:124`, so `runs party read` cannot leak a row that cannot exist.)
--
-- Re-created verbatim from `0094:124-159` except for gate ⑥. `set search_path = public, pg_temp`
-- is re-stated because `create or replace` would otherwise drop what 0055's ALTER put there.
--
-- ⚠⚠ **PLACEMENT — gate ⑥ sits AFTER the party gate AND AFTER the idempotent existing-incident
-- return, and that ordering is the specification, not a detail.** An incident opened legitimately
-- at `active` and still open when the booking moves on must keep returning its id. Gating before
-- the lookup would make a double-tap on an ALREADY-OPEN case raise — turning 0094's deliberate
-- "a double-tap in an emergency does not produce two cases" affordance into a refusal at the worst
-- possible moment, and stranding the caller with no id to hand to `incident_contact`. **The gate's
-- job is to refuse CREATING a case on a never-accepted booking; it has no business refusing to
-- hand back a case that already exists.** Gate the write, not the read. Suite 149's P-34 is the
-- executable form of this paragraph.
--
-- ⚠ The error name is `booking_not_reportable`, never `not_party` and never a reuse of the
-- narrow predicate's vocabulary — 0094 §10's own law, DISTINCT FACTS GET DISTINCT NAMES. It is
-- deliberately not called "not active" either: the set is WIDER than active, and a name that said
-- otherwise would mislead the next reader into "fixing" §3 to match §1.
create or replace function open_incident_tx(
  p_booking  uuid,
  p_kind     text,
  p_severity text default 'normal',
  p_note     text default null,
  p_media    text[] default '{}'
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare b record; v_uid uuid := auth.uid(); v_id uuid;
begin
  -- ① signed in
  if v_uid is null then raise exception 'not_signed_in'; end if;
  -- ② `for update` fetch, so two simultaneous opens serialise on the booking
  select bk.id, bk.owner_id, bk.runner_id, bk.status::text as status
    into b from bookings bk where bk.id = p_booking for update;
  if b.id is null then raise exception 'not_found'; end if;
  -- ③ party gate BEFORE state gate (house law), on THIS booking — 0094 §2's fix, unchanged
  if v_uid is distinct from b.owner_id and v_uid is distinct from b.runner_id then
    raise exception 'not_party';
  end if;
  -- ④ argument validation
  if p_kind not in ('dog_injury','lost_dog','third_party','equipment','other')
    then raise exception 'bad_kind'; end if;
  if p_severity not in ('normal','urgent','sos') then raise exception 'bad_severity'; end if;

  -- ⑤ One OPEN incident per booking. A second open is not an error — it returns the existing one,
  -- so a double-tap in an emergency does not produce two cases for one event, and the caller
  -- still gets a usable id rather than a raise it has to interpret under stress.
  -- ⚠ THIS STAYS ABOVE ⑥. See the placement paragraph in the header.
  select i.id into v_id from incidents i
   where i.booking_id = p_booking and i.resolved_at is null
   order by i.created_at limit 1;
  if v_id is not null then return v_id; end if;

  -- ⑥ [0114 🔵] state gate — the REPORTABLE set. Deliberately wider than
  -- `is_booking_party_active`: the accepted set PLUS `cancelled_owner` (0066's en-route cancel —
  -- the runner may be standing at the door) and `refund_pending` (reached from the accepted set
  -- after an incident settles, `0072:179` / `0038:219-221`). Those are precisely the two states a
  -- genuinely-accepted party is most likely to be standing in when they need to report, and an
  -- incident report is not a convenience that can wait for an accept.
  -- Written inline against the already-fetched row rather than as a second function: the record is
  -- in hand from ② so it costs nothing, and the set stays legible at the call site.
  -- ⚠ Still a SET, not "everyone": at `runner_pending`, `matching`, `payment_hold`, `draft`,
  -- `quoted` and `expired` this refuses, which is what keeps B-11.f closed.
  if b.status not in (
       'confirmed', 'runner_enroute', 'picked_up', 'active',
       'completed', 'no_show', 'incident_review', 'cancelled_runner',
       'cancelled_owner',                                  -- 🔵 en-route cancel: report still open
       'refund_pending'                                    -- 🔵 post-incident: a second fact
     ) then
    raise exception 'booking_not_reportable'
      using detail = '수락 전이거나 종료된 예약에는 사고를 접수할 수 없어요',
            hint   = '0114 §3: the reportable set is the accepted set + cancelled_owner + refund_pending.';
  end if;

  -- ⑦ insert
  insert into incidents (booking_id, reporter_id, kind, severity, note, media)
  values (p_booking, v_uid, p_kind, p_severity, p_note, coalesce(p_media, '{}'))
  returning id into v_id;
  return v_id;
end $$;

-- grants re-stated: `create or replace` preserves them, but 0094's pair is repeated so this file
-- reads as the whole truth about the function rather than a patch on one.
revoke execute on function open_incident_tx(uuid, text, text, text, text[]) from public, anon;
grant  execute on function open_incident_tx(uuid, text, text, text, text[]) to authenticated, service_role;

comment on function open_incident_tx(uuid, text, text, text, text[]) is
  '0094 §9 + 0114 §3. Opens (or idempotently returns) the one OPEN incident on a booking. Gate order:
signed-in → for-update fetch → PARTY → argument validation → existing-open-incident RETURN → STATE.
⚠ The state gate deliberately uses a WIDER set than is_booking_party_active: accepted set +
cancelled_owner + refund_pending (0114 🔵). That is not an inconsistency to be tidied away — chat,
reviews and notifications are conveniences that can wait for an accept, an incident report is not,
and those two states are exactly where a real party (runner at the door on an en-route cancel; a
second fact after the first incident settled) most plausibly needs to report. Refuses with
`booking_not_reportable`, a name of its own (0094 §10: distinct facts, distinct names).
⚠ The state gate sits AFTER the idempotent return on purpose: an incident opened legitimately and
still open when the booking moves on must keep handing back its id. Gate the write, not the read.
Accepted residual: an attacker who nominates a stranger and then cancels their own booking can open
an incident on them — no push, no free text, but it does open incident_contact''s phone door.';

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §4  what deliberately KEEPS plain `is_booking_party` — nothing in the READ direction narrows
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- No statement here; this section exists because unstated scope reads as a seal, and §5 EXECUTES
-- it as a fail-closed assertion so a future over-narrow is a failed deploy rather than a surprise.
--   · `bookings party read` — 🔴 **the nominated runner MUST be able to SELECT the booking.** That
--     is O-4's protected half: the runner opens 요청 탭, reads the request, accepts or declines.
--     Narrowing it breaks the exact flow this decision exists to preserve.
--   · `threads party` (SELECT) and `messages party read` (SELECT) — chat history must survive
--     cancel/complete (`0108:34-37`), and after §2 there is nothing pre-accept to read anyway.
--     Narrowing buys zero and costs the history.
--   · `reviews public read` / `reviews author read` / `reviews storefront read` — the WRITE is
--     what this slice gates; a review that cannot be written cannot be read. (Widening the review
--     READ path is a separate, LEGAL decision — §0-quindecies — which this file neither triggers
--     nor forecloses.)
--   · `incidents party` (SELECT) — §3 is the only writer and it is gated.
--   · `runs party read` — no `runs` row can exist before `start_run`, which requires `confirmed`+.
--   · `incident_contact` — 🔴 explicitly not edited. 0094 §4 rules that the phone door opens on the
--     OPEN and warns that narrowing it to verified-only "would be the same error wearing a safety
--     costume". Gating the OPENER shuts B-11.g transitively without touching a door two rulings
--     have already settled.
--   · `verify_incident_tx` — can only be called on an incident that exists; §3 is the gate.
--   · `noti self update` (USING-only, and correctly so — with no `with_check` PostgreSQL re-applies
--     USING to the post-update row, so retargeting a notification at a victim is refused 42501) and
--     `runs runner update` (`0087:82-84` rules it untouched; dropping it would take live trace
--     persistence down with it). Both are recipient/runner-scoped, not party-scoped.

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §5  verify — fail CLOSED, in both directions
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- Two directions on purpose, because this slice can fail two ways and only one of them is loud:
-- an UNDER-narrow leaves the hole open (a policy that did not actually switch), and an
-- OVER-narrow takes chat, reviews and notifications down for every honest user. 0111's M2 is the
-- precedent — an over-revoke that only the catalog could see.
do $$
declare v_bad text; v_n int;
begin
  -- ① the four WRITE policies must name the new predicate. `pg_get_expr` on the real catalog, not
  --    a re-read of this file: a policy that failed to drop, or one recreated under a typo'd name,
  --    shows up here as a missing row rather than as a silent pre-0114 predicate in production.
  select string_agg(x.tbl || '.' || x.pol, ', ' order by x.tbl)
    into v_bad
    from (values ('chat_threads','threads party insert'),
                 ('chat_messages','messages party send'),
                 ('reviews','reviews author insert'),
                 ('notifications','noti party insert')) as x(tbl, pol)
   where not exists (
     select 1 from pg_policies p
      where p.schemaname = 'public' and p.tablename = x.tbl and p.policyname = x.pol
        and p.cmd = 'INSERT'
        and coalesce(p.with_check, '') like '%is_booking_party_active%'
   );
  if v_bad is not null then
    raise exception '0114: write policy did not switch to is_booking_party_active: %', v_bad
      using hint = 'the drop/create pair did not land, or the policy name drifted. All four names were read from production pg_policies — a missing row means the DROP hit nothing.';
  end if;

  -- ② the OVER-narrow guard (§4). Every SELECT policy must still carry the WIDE predicate. If a
  --    later hand narrows one of these, chat history and the nominated runner's view of their own
  --    request go with it — and no negative pin would notice, because a policy that admits nobody
  --    is green on every denial test.
  select string_agg(x.tbl || '.' || x.pol, ', ' order by x.tbl)
    into v_bad
    from (values ('chat_threads','threads party'),
                 ('chat_messages','messages party read'),
                 ('reviews','reviews public read'),
                 ('runs','runs party read'),
                 ('incidents','incidents party')) as x(tbl, pol)
   where not exists (
     select 1 from pg_policies p
      where p.schemaname = 'public' and p.tablename = x.tbl and p.policyname = x.pol
        and coalesce(p.qual, '') like '%is_booking_party%'
        and coalesce(p.qual, '') not like '%is_booking_party_active%'
   );
  if v_bad is not null then
    raise exception '0114 OVER-NARROW: a READ policy no longer carries plain is_booking_party: %', v_bad
      using hint = '0114 §4 — nothing in the read direction narrows. Chat history must survive cancel/complete and the nominated runner must still SELECT their own booking (O-4''s protected half).';
  end if;

  -- ③ 98 H1's property, asserted here so it is a FAILED DEPLOY rather than a red harness later:
  --    both functions this file writes must carry pg_temp in their OWN proconfig. 0055's ALTER is
  --    wiped by `create or replace`, so this is the exact statement that can regress it.
  select string_agg(p.oid::regprocedure::text, ', ' order by p.oid::regprocedure::text)
    into v_bad
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.prokind = 'f'
     and p.proname in ('is_booking_party_active', 'open_incident_tx')
     and coalesce(array_to_string(p.proconfig, ','), '') not like '%pg_temp%';
  if v_bad is not null then
    raise exception '0114: definer written without pg_temp in its body: %', v_bad
      using hint = 'write `set search_path = public, pg_temp` in the CREATE statement. An ALTER after the fact is reset by the next create or replace (CLAUDE.md, measured).';
  end if;

  -- ④ the second OVER-narrow guard: `authenticated` must hold EXECUTE on the new predicate. Every
  --    policy in §2 calls it as the invoking role, so without the grant all four refuse
  --    unconditionally — chat, reviews and in-app notifications go dark for everybody, and the
  --    symptom is indistinguishable from the narrow "working".
  if not has_function_privilege('authenticated', 'is_booking_party_active(uuid)', 'EXECUTE') then
    raise exception '0114 OVER-REVOKE: authenticated cannot execute is_booking_party_active'
      using hint = 'the four §2 policies evaluate as the invoking role. Without this grant they refuse every write, honest or not.';
  end if;

  -- ⑤ §3's reportable set must name only real enum values. `b.status` is compared as TEXT there,
  --    so a typo would not raise — it would silently make the gate stricter than written and close
  --    a safety door the 🔵 decision deliberately opened.
  select string_agg(s, ', ' order by s) into v_bad
    from unnest(array['confirmed','runner_enroute','picked_up','active','completed','no_show',
                      'incident_review','cancelled_runner','cancelled_owner','refund_pending']) s
   where s not in (select unnest(enum_range(null::booking_status))::text);
  if v_bad is not null then
    raise exception '0114: reportable set names a value that is not a booking_status: %', v_bad;
  end if;

  -- ⑥ the realtime rooms are untouched (§0f). Guarded on the table existing so this is inert where
  --    the platform schema is absent; where it exists, a room that vanished under this slice is a
  --    silent outage on chat/booking-status live updates.
  if to_regclass('realtime.messages') is not null then
    select count(*) into v_n from pg_policies
     where schemaname = 'realtime' and tablename = 'messages'
       and policyname in ('party channel read', 'run channel read', 'run channel write');
    if v_n <> 3 then
      raise exception '0114: realtime.messages policies changed (% of 3 present) — this file must not touch them', v_n
        using hint = '0114 §0f: the rooms stay wide. 143 B1 pins the radar screen at matching and 143 C3 pins chat surviving cancel.';
    end if;
  end if;
end $$;
