# HIGH CLUB Group Run — Complete Logic Description (for critique)

> 2026-07-30. Everything below is **implemented and harness-verified (109/109)** unless marked
> **[PROPOSED]** (designed this session, not built — group chat, roster/phones, lingo sheet) or
> **[OPEN]** (undecided policy — listed at the end for your critique).
> Source of truth: migrations 0030–0039, edge functions `transition-booking`/`settle-run`, `docs/hi-club-plan.md` v2.1.

---

## 0. The one-sentence model

A club session is a pre-fixed place+time where multiple runners (each handling 0–2 delegated dogs) and
owners (running with their own dog, or dropping their dog off and leaving) run together — everyone a member
of the same club. **Invariant: every dog has exactly one explicit responsible person at every moment.**

## 1. Objects

| Object | Key fields | Notes |
|---|---|---|
| club | status `collecting → active` | Ghost-club ban: collecting = interest-gathering surface, no fake activity. Activated only by a certified+ runner claiming host. |
| club_series | weekday/time rule, format, status active/paused | Retention unit. Cron (hourly :20) materializes sessions: 72h window, 2h min notice, ±1h dedup, copies format, auto-joins current host. |
| club_session | scheduled_at, meetup_point, format `owner_only/delegated_only/mixed`, people_capacity (2–60, default 12), delegated_dog_capacity (derived), min_attendance (default 2), status `open/full/done/cancelled` | Delegation formats **require a route** (price must be computable — no route, no delegation). |
| session_people | role `host_runner/handling_runner/runner_attending/owner_attending`, attendance `rsvp/checked_in/no_show`, waiver_version | One row per human. |
| session_dogs | custody `owner_handled/runner_delegated`, **responsible_profile_id NOT NULL**, approval `auto/pending/approved/rejected`, booking_id, checked_in_at/checked_out_at, seq | One row per dog. `seq` = monotonic registration order. |
| session_runner_assignments | delegated_capacity, status `committed/withdrawn` | A runner's pledge to handle dogs + their personal cap. |
| booking (club-linked) | `club_session_id` set; normal booking otherwise | Money/insurance/settlement unit — the session only gives N bookings a shared venue. |
| participant_activities | source `gps_verified/self_reported/checkin_only`, km/pace/duration, run_id | Measurement-source honesty, schematized. |

## 2. Capacity — two independent budgets

1. **People capacity**: consumed by session_people rows (RSVP, handling runners). Atomic under session row
   lock; reaching it flips status to `full` (display only — delegation is unaffected).
2. **Delegated-dog capacity** = **sum of COMMITTED runners' personal caps**, re-derived on every
   commit/withdraw (never stored stale). Personal cap = min(2, tier): certified 1 · veteran/master 2 ·
   applicant 0 (rejected). A drop-and-go owner consumes **no** people slot.

## 3. Lifecycle — social path (P-A/P-B, unchanged by P-C)

RSVP (open/full & future; optional own dog → session_dogs `owner_handled`, responsible=owner;
**RSVP = club membership**; waiver_version recorded) → check-in (window **T-2h..T+6h**;
`participant_activities` checkin_only) → host finishes → recap feed post **iff ≥1 checked-in team**
(0-team sessions post nothing) + next-RSVP embedded. Host cannot leave own session.

## 4. Lifecycle — delegation path (P-C)

### 4.1 Runner commits (`session_runner_commit`)
Requires: certified+ tier, session open/full & future, format mixed/delegated_only.
Effects: joins session_people as `handling_runner` (host keeps `host_runner`; attending roles upgrade;
people-capacity check if new), assignment row committed with personal cap, **session capacity re-derived**,
club membership. Re-commit after withdraw = same RPC (idempotent upsert).

### 4.2 Runner withdraws (`session_runner_withdraw`)
**Blocked** (`reassign_dogs_first`) if any of their club bookings in this session are confirmed/picked_up/active —
host must reassign those dogs first. Otherwise: assignment → withdrawn, role demoted to `runner_attending`
(withdrawing handling ≠ leaving the session), capacity re-derived. **Stranding**: if approved dogs now exceed
capacity, the excess reverts to `pending` **latest-registered first** (`seq` desc), their bookings are fully
refunded (`refund_pending`, reason `club_runner_withdrawn`), owner + host notified. No silent stranding.

### 4.3 Owner registers (`session_delegate_dog`) — *demand queue, no money*
Requires: session open/full & future, delegation format, **route present**, caller owns the dog, dog not
already registered (a **rejected** dog cannot re-register for the same session). Effects: session_dogs row
(`runner_delegated`, `pending`, **responsible = owner** — invariant holds pre-handoff), club membership,
host notified. **No booking, no payment, no people slot.** Registration is allowed even at 0 capacity
(it's demand signal); approval is what consumes capacity.

### 4.4 Host approves / rejects (`session_approve_dog`) — *money enters here*
Host-only, pending-only, session open/full & future, under session row lock.
- **Reject** → `rejected`, owner notified (community ink). Terminal for this session.
- **Approve** → capacity check (approved < derived capacity, else `no_capacity`) → **dog double-booking
  guard** (any live booking overlapping scheduled±duration, duration = km×8+25min — same formula everywhere)
  → **booking created**: normal price **9,900 + km×3,000** (constants duplicated in `ctx.ts` PRICING and 0037 —
  change together), no addons, status `matching`, runner_id null, `club_session_id` set → owner notified (booking ink).

Club bookings are invisible to the general open pool (api.ts feeds filter `club_session_id is null`) and
excluded from the 0017 auto-expiry cron — **the session lifecycle owns their fate**.

### 4.5 Host assigns, day-of (`session_assign_dog`)
Window = check-in window (**T-2h..T+6h**), session open/full. Dog must be approved with booking; runner must
be **committed AND checked in** (dogs only go to runners physically present); per-runner assignment count
re-verified against personal cap (second line of defense).
- First assignment: booking `matching → confirmed`, runner_id set, **both handoff stamps reset**
  (stale-stamp accident prevention — runner_accept precedent).
- Reassignment: allowed while `confirmed` only (swap runner, reset stamps). After handoff → `already_handed_off`.
- Both owner and runner notified with names.

### 4.6 Handoff = custody flip (existing mechanism, reused)
The per-booking **two-sided confirmation** (transition-booking `confirm_handoff`, meta.side supported for
solo-testing) is the insurance anchor — unchanged. Both stamps → booking `picked_up` → **DB trigger** flips
`session_dogs.responsible_profile_id` to the runner + stamps dog check-in. Trigger-based so the invariant is
server-owned regardless of which code path drives the transition.

### 4.7 The run itself
- `club_start_delegated_runs`: all MY picked_up club bookings → `active` + runs rows, one call; owners notified.
  A dog handed off late can join later (same call again — it only touches picked_up ones).
- **Shared trace**: `club_save_run_trace` writes one GPS track into all my active runs (owners' live view
  reads their own booking as usual). Run **events stay per-booking** (a poop stamp is a fact about one dog).
- **Per-dog early return**: standard settle-run on that booking (e.g. `owner_request`) — that dog settles,
  custody returns, the rest keep running. Early-settle pay rules unchanged (min_fare floor, ≥50% km for
  "completion", km clamp 0..planned×2+2 server-side).

### 4.8 Settlement (per booking — existing settle-run, untouched)
For each dog: booking `completed` (atomic claim), runs row finalized, ledger row (runner payout with tier
commission — **N dogs = N payouts by design; never surfaced to owners**), miles +50 owner & runner on full
completion (+30 poop bonus), patch gold/master at exactly 10/25 course completions, drop rolls on runner's
total_runs cadence, record-detection trigger (0034), **custody trigger returns responsibility to the owner +
dog checked out**, `participant_activities` row written as **gps_verified** (runs trigger).

### 4.9 Session close-out
- **Host cancel** (`club_cancel_session`): blocked while any dog is out (`picked_up/active` → `session_in_flight`).
  Otherwise session → cancelled; refund fan-out: `matching` → refund_pending directly; `confirmed` → two-step
  `cancelled_runner → refund_pending` (transition map untouched); owners notified (booking), participants notified (community).
- **Host finish** (`club_finish_session`): recap (≥1 team) + any never-picked-up delegated bookings
  (`matching` or `confirmed`) fully refunded — no run = no charge.
- **Min attendance**: hourly cron (:40) notifies the host once (dedup) when a session inside T-3h has
  fewer people than min_attendance. **No auto-cancel** — a human opens sessions, a human closes them.

## 5. Notifications inventory

| Event | To | Ink |
|---|---|---|
| Delegation request | host | community |
| Approve (=payment) / assignment / handoff done / run start / run done / all refunds | owner (+runner for assignment) | booking |
| Reject / stranding alert / min-attendance / session cancel (participants) / series session opened / recap | involved parties | community |

## 6. Timing windows (single table)

| Rule | Value |
|---|---|
| Session creation min notice | ≥ 1h ahead (manual), ≥ 2h (series cron) |
| Series generation window | ≤ 72h ahead, hourly :20, ±1h dedup |
| Check-in / assignment / handoff window | T-2h .. T+6h |
| Min-attendance host ping | inside T-3h, once |
| Booking duration formula (clash math) | km × 8 + 25 min |

## 7. [PROPOSED] Session group chat

Purpose: meetup coordination (running late, spot changes within the meetup point, "which bench").
- **Scope: per-session thread** (the coordination unit; club-wide chat deferred — retention risk of a dead
  global room, and sessions self-archive).
- **Participants** = session_people ∪ delegating owners ∪ committed runners ∪ host. Auto-membership, no join step.
- **Lifecycle**: writable while session `open/full`; **read-only once done/cancelled** (archive stays attached
  to the session page). Nothing pre-seeded — empty room shows a single system line with meetup point + time
  (real data, not fake activity).
- **Mechanics**: `club_session_chat` table (body ≤ 500 chars), realtime via the 0008 publication pattern,
  write through an RPC that validates participation + session state; reads via RLS (participants only).
- **Push**: v1 = none (badge on the session screen only). Option: push for host messages only ("host
  announcement" toggle) — proposed default OFF to avoid noise. **[OPEN-7a]** your call.
- Moderation: host can't delete others' messages in v1 (small trusted groups); report path = existing support.

## 8. [PROPOSED] Session roster + phone numbers

Purpose: "in case" — a dog bolts, an owner is late for return handoff, an emergency at the meetup.
- Roster (names, roles, dogs, check-in state) visible to **all session participants** — already mostly true
  via session detail; delegating owners get added to the visible list (today they're only visible as dogs).
- **Phone visibility — recommended rule (B)**: host sees all participants' phones; owner ↔ their assigned
  runner see each other's; everyone else sees names only, with a "호스트에게 연결" relay affordance.
  Alternative (A): all participants see all phones while the session is live (simpler, beta-acceptable,
  bigger PII surface). **[OPEN-8a]** pick A or B (doc recommends B).
- Server-side enforcement: a dedicated roster RPC computes per-viewer phone visibility; numbers never ship
  to clients that shouldn't render them. Visible from T-2h until T+6h (the physical-coordination window),
  hidden outside it **[OPEN-8b]** — or always-on for host?

## 9. [PROPOSED] Club lingo sheet

A single reusable bottom-sheet ("?" chip next to any flap display and in the club/session headers) defining,
in one line each: the six flap words (PENDING/CLEARED/REFUSED/BOARDED/RUNNING/SETTLED), 커스터디/책임자,
인계(양측 확인 = 보험 기점), 게이트(담당 러너), 정원(커밋 러너 캡 합), 커밋, 위탁/동반, 체크인 창.
Static content, shipped with the app; same sheet everywhere so the vocabulary is learned once.

## 10. [OPEN] Undecided policies — the critique list

1. **Owner no-show**: today a no-show's booking is fully refunded at session finish (never picked up = no
   charge). Runner reserved a cap slot for nothing. Options: keep (beta-friendly) / late-cancel fee (e.g.
   50% inside T-2h) / no-show fee. Requires defining "no-show" measurably (not handed off by session end).
2. **Owner-initiated cancel of a delegated booking**: the standard cancel path technically works and — quirk —
   is always **free** while `matching` ("unmatched" rule), but 10% fee after assignment (assignment happens
   ≤2h before start, so always inside the 24h window). No UI exposes this today; the semantics
   (freeing capacity? notifying host? deadline?) are undefined. Needs an explicit club-side rule.
3. **Runner stat inflation**: a 2-dog club run settles as 2 bookings → runner's total_runs +2, double miles,
   faster drop cadence, each dog's course completion counts toward patches. Defensible (they did handle two
   dogs — it's also the pay model) but it accelerates gamification economy vs solo runners. Keep or normalize?
4. **Delegation consent/waiver**: RSVP records waiver_version; delegation registration currently records
   nothing. The entry form (F1) should capture a delegation-specific consent line (custody transfer, insurance
   scope) — field exists conceptually, not in schema. Add `waiver_version` to session_dogs?
5. **min_attendance for delegated_only sessions** counts PEOPLE — a session with host + 3 delegated dogs and
   no attendees reads as "under-attended". Should delegated dogs count toward viability?
6. **Demand threshold (10 teams)**: still a constant with no behavior.
7. Chat push policy [7a] · phone visibility A/B [8a] and window [8b] above.
8. **Recap composition**: teams = checked-in people; dogs = checked-in dogs (incl. delegated). A drop-and-go
   owner is invisible in "teams" — intended? (Their dog shows in the dog count and their run in the feed?)

---
*Critique welcome on any line — items in §10 block nothing that's already built; chat/roster/lingo (§7–9)
wait for your verdict before implementation.*
