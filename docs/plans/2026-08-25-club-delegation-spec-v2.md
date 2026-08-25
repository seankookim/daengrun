# Club delegation restructure — spec v2 (the coupled machine)

**Provenance.** Sean greenlit the restructure 2026-08-25 morning (verbatim in
`docs/decisions/2026-08-24-sean-ui-club-commentary.md` §2026-08-25): the paired runner picks the
dog up at home and *"carr[ies] the responsibility from the getgo"*; the owner or the app chooses
the runner *"instead of the host"*; Mode C is *"a function of proximity … then runner's
preference of distance, then owner's, then pacing, then the other handful"* — an algorithm to
build, deterministic; and he ordered: *"please update the host side screen and delineate all
necessary features per side and per state in the flow of a full club session."* The CEO riders he
accepted: honest transit copy until insurance signs · the no-show predicate moves to
arrival-at-start · Mode C rides the counsel brief.

**Method.** This spec starts from the four-voice review's eleven FACT CORRECTIONS and the
RETHINK verdict (*"pairing, booking/payment, custody, cancellation, and finish order are one
coupled state machine"*), not from spec v1's claims. Every code fact below was re-scouted at
trunk tip (≥ `5bd2d59`, after the 0118+0119 landings) with file:line citations; where v1 was
wrong, the correction is applied inline and marked ⟨C*n*⟩. Decisions Sean has not made are 🔴
(§14). Proposals this spec makes on its own authority are 🔵 — reversible in one word.

Status: DRAFT v2 for blind review, then Sean. Nothing here is built.

---

## 0. Corrections compliance — how v2 answers the review

| # | v1's error | v2's answer |
|---|---|---|
| C1 | "0118 gates survive unchanged" — FALSE; home pickup auto-satisfies `owner_confirmed_handoff_at` hours early | New no-show predicate anchored at the door and at start (§7.4), P4/P9/P10/P12 re-pinned in the same slice (§12 S4) |
| C2 | Mid-run case entry "preliminary" | VERIFIED — entry point at `club/run/[sid].tsx:289-309` (SOS → `club_incident_open` → case route); the R respec carries it forward verbatim (§10.3) |
| C3 | "Address exposure reuses gate_code idiom" — overstated | Club address path is a NEW numbered security slice (§8); `gate_code_access_log` is a documented dead shell (0060:52); the live pattern to copy is `club_phone_access_log` (0049:236-248) |
| C4 | Retire five functions (~88 pin edits) | DEPRECATE: revoke + refusal pins, reversible (§11). `session_assign_dog` is already a one-line alias over propose (0047:143-146) — the retirement v1 planned was mostly already done |
| C5 | Free mode-switch contradicts the ladder | Mode switch after payment IS a paid-delegation cancel and rides the ladder; the UI says so before the tap (§5.3). Mint timing does NOT move (§5.1, reasoned) |
| C6 | Dogless companion = safety hole | Companions are `session_rsvp(p_dog := null)` runner-tier attendees — existing machinery: identity (runner tier), party standing (`session_people` → shell `full` → incident standing), headcount capacity, zero money (§4.4) |
| C7 | Six silent decisions | Each is now explicit: mode exclusivity §4.1 · per-dog approval §4.2 · transit-inside-custody §7.3 · pending picks and capacity §6.4 · Mode A copy-only VERIFIED §4.3 · **the attending Mode-B owner: per-pairing pickup mode ∈ {집 픽업, 현장 인계} (§7.2, 🔵)** |
| C8 | "Board data shape is close" — FALSE | The member board is a NEW sanitized projection (§9); today's board returns runners/dogs only to host/full/limited-owner and queries `runner_delegated` only (0053:249,331,336) |
| C9 | "Cap semantics unchanged" contradicted `_club_runner_load` | v2 ADOPTS today's load semantics unchanged (accepted + live picks + own 동반견, 0047:52-65) — a pending pick consumes capacity, which makes the concurrent-approval conflict structurally impossible (§6.4) |
| C10 | Two-phase finish consumer blast radius unnamed | The consumer-by-consumer table is §13 — 28 consumers classified unchanged / re-anchored / rewritten, with the settle→return→release ordering preserved where money depends on it |
| C11 | (upgrade of C2) | Same as C2; additionally the run screen's per-dog SOS branching (0-dog / 1-dog / multi-dog) is preserved as-is |

Two peer-supplied facts also honored: club fees never route through `quote_cancel_fee`
(`club_out_of_scope` by design — a club cancel-quote surface is a NEW server ask, §5.4), and
every handoff stamp today is pairing-scoped and erased by six reassignment paths (0118:1197-1201)
— so this machine is **keyed per-pairing**, and the one place a per-person durable fact is needed
is named and left to Sean's open Custody decision (§7.4).

---

## 1. The one coupled machine — overview

The RETHINK's demand, met head-on: pairing, money, custody, cancellation, and finish are one
machine whose single subject is the **pairing** — a `session_dogs` row plus its booking. Session-
level state stays thin (`open/full/done/cancelled`, unchanged CHECK, 0030:61) plus one new
timestamp (`run_confirmed_at`, §7.5); everything else lives per-pairing, because that is where
the shipped machine already keys everything (axes trigger 0040:281, custody trigger 0045:64,
fee writer 0118:789) and because per-pairing keying is what survives the stamp-erasure class.

### The per-pairing state ladder (Mode B/C; Mode A short-circuits in §4.3)

| # | State (name is new; columns are today's) | Underlying facts | Money | Entered by |
|---|---|---|---|---|
| P0 | `signed_up` | `session_dogs` row, `custody='runner_delegated'`, `approval='pending'` | none | owner: `session_delegate_dog` (0048:89) — 0119 gate fires HERE (INSERT trigger, 0119:415) |
| P1 | `admitted` | `approval='approved'`, 20-min hold (0084:635) | none | host: `session_approve_dog` — admission survives (§4.2) |
| P2 | `paid` | booking minted `status='matching'`, `runner_id=null` (0081:184) | seat real; no charge (0081:207) | owner: `session_pay_delegation` — **mint timing unchanged** (§5.1) |
| P3 | `pick_pending` | `proposed_runner_profile_id` set, `proposal_expires_at` = now()+TTL | none | owner (Mode B) or platform (Mode C) — the chooser swap, §6 |
| P4 | `paired` | booking `confirmed`, `runner_id` set (0057:131) | 20% rung arms (state-anchored, §5.2) | runner: `session_proposal_respond(true)` — approval stays the runner's |
| P5 | `pickup_enroute` | runner arrival stamp at the door (§7.1) | — | runner taps 출발/도착 |
| P6 | `picked_up` | both handoff stamps → booking `picked_up`; custody trigger flips custodian to runner (0045:44-53) | — | both-stamp `confirm_handoff` at the DOOR (or at start for 현장 인계 pairings, §7.2) |
| P7 | `at_start` | dog's arrival at start recorded (§7.4 — the new no-show predicate's positive side) | — | runner's `session_checkin` stamps held dogs (0030:259 mechanism, re-anchored) |
| P8 | `running` | booking `active`, `runs` row (0050:169-186) | — | runner: `club_start_delegated_runs` |
| P9 | `run_finished` | booking `completed` via settle-run (0083:628); **custody_phase HOLDS at a new `finished_pending_host` value** (§7.5) | runner paid at settle (club has no return seal — 0083:668-681); NOT payable yet | runner settles per dog — this IS Sean's "per-runner finish" |
| P10 | `returning` | `custody_phase='return_pending'` | — | **host run-end confirmation flips all P9 pairings at once** (§7.5) |
| P11 | `resolved` | both return stamps → `_club_finalize_return` (0070:343): custodian back to owner, `payable` | payout `earned→payable` | both-stamp at the home door (or 현장 반환) |
| P12 | `released` | `payout_state='released'` | supply money leaves | cron `club_release_payouts` (0072:221) — UNCHANGED, still requires `resolved` + no open incident |

Cancellation arms exit this ladder at defined points only (§5.3). Incident states
(`incident_review`, holds, settlement) are orthogonal and UNCHANGED (0070/0072/0080 — §13
C9-C14). The 맹견 gate fires at P0 (INSERT) and at every custody-bound move exactly as landed —
zero 0119 changes (§13 C28).

**What actually changed vs today, in one sentence each:**
1. The chooser at P3 is the owner or the platform, never the host (§6).
2. P5-P7 are new legs: custody starts at the owner's door and the dog travels to the start
   inside the runner's custody (§7).
3. P9→P10 inverts today's automatic `completed → return_pending` (0045:55-59): the return leg
   now begins at the host's run-end confirmation, which is where Sean put it (§7.5).
4. The no-show money predicate re-anchors from "handoff stamp at the scene" to "door + start
   evidence" (§7.4) — the C1 correction.

---

## 2. Actors

| Actor | Gains | Loses | Identity/standing mechanism (today's, reused) |
|---|---|---|---|
| Owner | per-session mode fork; Mode B pick; per-pairing pickup mode; custody timeline visibility | nothing | `session_dogs.owner_profile_id`; shell `limited/full` (0049:9) |
| Paired runner | approves picks made days ahead; door pickup; transit custody; per-dog finish; return leg | being chosen at the scene | `session_runner_assignments` commit (0043:217); tier cap (0037:37) |
| Dogless companion | board visibility; ride-along | — (never paid — ruled) | `session_rsvp(dog:=null)` → `session_people(role='runner_attending')` (0048:181) — §4.4 |
| Host | run-end confirmation; admission (kept); session lifecycle (kept); force-resolve/override/cases (kept) | choosing runners (`session_propose_dog`'s host gate) | `host_profile_id`; backup host asymmetries preserved-and-named (§10.2) |
| Club member (non-party) | the sanitized board (§9) | — | NEW projection; today they see `session` object only (0053:229-249) |

---

## 3. What is ruled vs proposed — the authority map

RULED (Sean's words, on origin): owner/app chooses, runner approves · home pickup by the paired
runner, responsibility door-to-door · every step visible on the club public home · replaces
at-the-scene matching · dogless companions unpaid · per-runner finish → host final confirmation
→ return home; owner-run dogs release immediately · Mode C = the deterministic ranking he
sketched · riders: honest transit copy, no-show predicate at arrival, Mode C behind counsel.

PROPOSED by this spec (🔵, each reversible): per-pairing pickup mode {door, start-point} (§7.2)
· pick TTL 2h with lapse-back (§6.3) · host-confirm recovery ceiling (§7.6) · companions =
runner-tier RSVP (§4.4) · Mode C pilot inputs (§6.5) · mode-switch fee copy (§5.3).

STILL SEAN'S (🔴): the list in §14. Nothing below builds until the review passes; S4-S6 (§12)
additionally wait on the named riders.

---

## 4. The entry fork and admission

### 4.1 Mode is per-dog-per-session, exclusive, and switchable only while unpaired

At sign-up the owner chooses per dog: **A 동반** (run it myself) · **B 지정** (pick from the
committed list) · **C 자동** (the app connects). One dog, one mode, one session — enforced by the
existing partial unique index `session_dogs_active_uni` (0043:28-31): a dog has at most one live
row per session, and the row's `custody` value IS the A-vs-B/C fact. B↔C is a chooser flag, not a
state (§6.1); switching costs nothing at any point before P4. Switching B/C→A before P2 is the
free withdrawal arm (0118:1025-1032, `withdrawn`, hold released); after P2 it is a paid cancel
and rides the ladder with the UI saying so first (§5.3). A→B/C is cancel-RSVP + delegate, both
free (0052:205; note `delegation_active` blocks the reverse order — sequence is delegate-last).

### 4.2 Host admission SURVIVES; host matching DIES

Sean moved the *chooser*, not the bouncer: *"the customer or the app chooses the to-be-paired
runner … instead of the host."* Today's `session_approve_dog` (0084:610) is dog admission —
vetting an animal into a group run the host is responsible for — and it writes no pairing.
It stays, byte-identical, as P0→P1. What dies is the host's chooser role: `session_propose_dog`'s
`not_host` gate (0048:454). §6.2 replaces the gate, §11 deprecates the host-facing surface.
`session_review_dog` (materiality re-review, 0048:259) also survives untouched — it is safety,
not matching.

### 4.3 Mode A is copy-plus-one-gap, and the gap is the board

VERIFIED (v1 claimed, review challenged, scout confirmed): `session_rsvp` with a dog writes
`custody='owner_handled'`, no booking, no approval, no money (0048:189-191); the axes trigger
short-circuits every axis (0048:697); the 0119 trigger's WHEN clause skips it (0119:415-416);
release-at-finish is structural (no custody to resolve). Mode A needs **no machinery** — but it
does need the board: today `owner_handled` dogs are invisible (`custody='runner_delegated'`
filter, 0053:331) while Sean's board shows *"who's dog is running with who AND which dogs are
waiting"*. The §9 projection adds them.

### 4.4 Dogless companions = the machinery that already exists

Sean: *"Runners that don't have a dog can also just come along; they just won't be paid
anything."* The review's C6 objection (unverified stranger among customers' dogs, no incident
standing) dissolves once companions are what the schema already models: a certified runner
calling `session_rsvp(p_session, null)` gets `session_people(role='runner_attending')`
(0048:181), which yields shell `full` (0049:14) → board visibility, chat, and
`club_incident_open` standing (0067:68 admits shell `full`). They occupy `people_capacity`
headcount (0048:172), hold no delegated slot, touch no bookings, appear in no money path.
One consequence to carry honestly: a companion who is ALSO someone's paired runner counts their
own 동반견 toward load (0047:61-63) — a companion cannot bring their own dog AND be at full cap.
🔵 Companions are runner-tier only (`tier <> 'applicant'`, the existing role predicate). A
non-runner friend is a guest RSVP — allowed today, visible as a person, never listed as crew.
🔴 §14.6 if Sean wants non-runner companions labeled as crew on the board.

---

## 5. Money — where 0118 meets the new flow

### 5.1 Mint timing does not move

Today: delegate (no money) → admit (hold) → **pay mints the booking** (`matching`,
`runner_id=null`, `total_price=club_fare(km)`, 0081:184-192) → pairing later. v2 keeps exactly
this. Reasons, in order of weight: (a) the fee ladder's base is `bookings.total_price` read
under lock (0118:1035) — mint-at-pairing would leave P3 cancels with no fee object while a
runner's attention was already spent; (b) the idempotency contract, the unsettled-charge gate,
the billing-key gate, and the capacity re-check all live inside `session_pay_delegation`'s lock
(0081:145-192) and are measured; (c) slot-based comp needs the booking to exist BEFORE
acceptance so the supply half has a ledger anchor the moment P4 arms. The C5 consequence is
handled as UI honesty (§5.3), not as a mint move. The club-vs-marketplace base-fare gap
(9,900 vs 7,900, memo ④, 0081:174-182) is inherited unchanged and stays on Sean's queue — not
this spec's to fix.

### 5.2 The ladder maps onto the new states without a number changing

The three rungs (0118:1041-1054) and ruling B (0118:816-826) are state predicates, and the
states survive:

| Rung | Today's predicate | v2 predicate | Delta |
|---|---|---|---|
| free ≥24h | booking not confirmed-with-runner, ≥24h out | P2/P3 ≥24h out | none |
| 10% late | same, <24h | P2/P3 <24h | none |
| 20% post-accept | `confirmed AND runner_id not null` (0118:1035-1037) | P4+ (pairing = acceptance) | the acceptance event's producer changes (runner accepts an owner/platform pick instead of a host proposal); the predicate is untouched |
| Ruling B | runnerless → platform half only | a lapsed/declined pick (P3→P2) is runnerless → platform half only | none — and slot-based comp is exactly satisfied: a `pick_pending` runner holds capacity (§6.4) but no slot-comp; only P4 acceptance holds a slot |

Two honest carries: acceptance is STATE-anchored and reversible — the six demotion paths that
null `runner_id` and erase stamps (0118:1197-1201) still demote an owner off the 20% rung, and
under v2 the owner-facing pick surfaces make reassignment rarer but not impossible (objection,
materiality, cancel-repick all survive). And the runner's supply half on a fee accrues to
`ledger_items` with `platform_fee=0` exactly as landed (0118:878-886) — v2 adds no new fee
writer; `_club_record_fee` (0118:789) remains the only one.

### 5.3 Cancellation arms, per state (the coupled machine's exit table)

| Exit at | Path | Money | Mechanism |
|---|---|---|---|
| P0/P1 | owner withdraws | none; hold released | 0118:1025-1032 arm, unchanged |
| P2 | owner cancels | ladder (free/10%), ruling B — no runner | `session_cancel_delegation` 0118:989, unchanged |
| P3 | owner cancels or re-picks; runner declines; TTL lapses | ladder on cancel (still runnerless); decline/lapse move NO money and return to P2 | decline: 0057:145 arm · lapse: recovery cron 0068:41-58 with TTL from §6.3 |
| P4 | owner cancels | 20% + supply half to the paired runner (slot held) | 0118:1039-1090, unchanged |
| P4 | mode switch → A | **same as owner cancel at P4 — the UI states the fee before the tap** (C5) | client copy + the §5.4 quote surface |
| P4 | runner exits | pairing dissolves to P2, stamps nulled, owner keeps seat; runner strike via `assignment_events` (policy number = Sean, 0057:174) | `session_assignment_revoke` re-gated (§6.2) |
| P5/P6 boundary | owner cancels | REFUSED past handoff — `already_handed_off` (0118:1037) — the boundary moves to the DOOR | unchanged predicate, earlier wall-clock |
| P6+ | anything wrong | incident machinery, not cancellation (0070/0072/0080) | unchanged |
| session-wide | host cancels session | full refunds both arms, no fee, refused if any dog P6+ (`session_in_flight`, 0038:235-239) | unchanged |
| session-wide | host confirms run end | no-show fee (new predicate §7.4) + refunds of never-picked-up | re-anchored `club_finish_session` money block (§7.5) |

### 5.4 Two club money surfaces this spec ORDERS (new server asks, own slices)

1. **Club cancel quote.** `quote_cancel_fee` refuses club rows by design (0117 §9b), and the
   honesty law forbids quoting the ladder from client constants. Before any owner-cancel
   confirm in club: a read-only definer `quote_club_cancel_fee(p_session_dog)` returning the
   ladder's answer (rung, pct, won amount, ruling-B halving) computed from the same predicates
   `session_cancel_delegation` charges from — party-gated to the owner, flat whitelisted return.
   A failed quote blocks the cancel button (the mirror's own law, applied to club).
2. **Runner-facing money.** Club runner surfaces (pick cards, session pay lines, finish
   screens) are net-only BY CONSTRUCTION per the runner-money contract §5
   (`docs/contracts/runner-money-strip-contract.md` @ f6ed2cf): `expected_net` computed
   server-side, never a component set, gross, fee, or rate. One line the contract asks this
   spec to carry: club pricing today inherits the public km-linear `club_fare` (0043:14), so
   the §0 named residual (rate regressable from net-vs-km) applies to club too; if club
   pricing ever decouples runner net from the public per-km line, that is the door to closing
   it — a pricing decision, Sean's, not assumed here.

---

## 6. The pick layer — chooser swap on today's proposal machinery

### 6.1 One machine, two choosers

`pick = proposal with a different author.` The shipped proposal machinery
(`proposed_runner_profile_id` + `proposal_expires_at` + `assignment_events` + accept/decline in
`session_proposal_respond`, 0057:104) is reused whole. Mode B: the owner authors the pick.
Mode C: a definer authors it from the §6.5 ranking. The runner's accept gate — the part Sean
kept ("which the runner can approve") — is byte-identical, including the load re-check
`load − 1 ≥ cap → runner_cap_full` (0057:126).

New RPC `session_pick_runner(p_session_dog, p_runner)` — party gate: the dog's owner (P2 only,
one live pick per dog — today's `proposal_active` gate, 0048:~480). Mode C's entry
`session_auto_pick(p_session_dog)` — owner-called ("connect me"), definer ranks and writes the
pick; the runner still accepts. Both write `assignment_events('proposed', reason='owner_pick'
| 'auto_pick:<rank-vector>')` so the chooser is auditable.

### 6.2 Gates that must MOVE (the pre-session reality)

Today's propose gates assume the meetup: assign window `[T−2h, T+6h]` (0048:456) and
`runner_not_checked_in` (0048:470). A pick made days early can satisfy neither. v2:

- **Window**: picks open at session creation and close at `scheduled_at` (a pick during the run
  is meaningless; late coverage is the host-side recovery, below). The T−2h..T+6h window
  RETAINS one job: it stays the bound on the host-side *recovery* propose (§6.6) and on
  check-in itself.
- **Checked-in**: dropped for picks; replaced by `committed` (already required —
  `runner_not_committed`, 0048:465) + cap headroom + the 0119 gate + the §6.5 hard filters.
  The runner's physical presence obligation moves to P5/P7 where it now belongs (§7.4).
- **What does NOT move**: `not_approved` (must be P2 — paid), `review_pending`, one-live-pick,
  `already_handed_off`, cap check at propose AND at accept. All byte-identical.

### 6.3 Pick TTL (🔵 2h, 🔴 the number is Sean's)

5 minutes (0048:507) is meetup-scale and dies with the meetup context. A pre-session pick needs
hours: 🔵 **2h with a push to the runner at issue and at T−15min, lapse returns the dog to P2
with the owner notified** (recovery cron 0068:41-58 already expires stale proposals — it gains
nothing but the new TTL). A pick issued <2h before `scheduled_at` clamps to `scheduled_at`.
Sean picks the number (§14.1).

### 6.4 Capacity — adopted verbatim, and why that answers C9

`_club_runner_load` = accepted + live proposals + own 동반견, per session (0047:52-65).
v2 changes NOTHING. Consequences, stated so nobody re-derives them: a runner sitting on a live
pick is capacity-consumed, so a cap-1 runner shows unavailable to every other owner until they
answer or the TTL lapses — serialization by consumption, which is exactly what makes the
concurrent-approval conflict impossible (two accepts for one slot can't both pass the accept
re-check, and under consumption the second pick can't even be issued). The board's `assigned`
count divergence (accepted-only, 0053:257-260, vs the enforcement formula — the papered-over
dead-chip case at `console/[sid].tsx:181`) gets fixed in the §9 projection: the board exposes
`load` and `cap`, and every pick surface pre-gates on the same number the server enforces.

### 6.5 Mode C — the ranking algorithm (Sean's ladder, made buildable)

**Constraints first**: deterministic (same inputs → same pick, no randomness, no learned
weights — the 비포펫 patent gates: no learned runner model), auditable (the rank vector is
logged in `assignment_events.reason`), and the runner still accepts (Mode C is Mode B with a
different author — a bad auto-pick costs a decline, never a custody).

**Inputs — what exists vs what must be built** (scouted at line):

| Ladder step (Sean's order) | Input | Schema today |
|---|---|---|
| 1. Proximity runner-home ↔ owner-home/start | runner home coords | **MISSING — new**: `runners.home_address_id → addresses(id)` (a runner IS a profile and `addresses.owner_id → profiles` already fits; onboarding + runner profile screen gain the field). Owner side: the pickup address chosen at P2 (§8), `addresses.lat/lng` (nullable — pinned addresses only, 0065:29-33) |
| 2. Runner's distance preference | `runners.service_radius_km` | EXISTS, dead column (0001:64; zero read sites) — adopted as the pickup-radius **hard filter** |
| 3. Owner's distance preference | — | **MISSING**, and in-club the run distance is route-fixed (`bookings.km` forced from `routes.km`, 0081:196), so the only distance the owner can have a preference about is the pickup leg. 🔵 pilot: SKIP this rung (vacuous at Banpo scale); 🔴 §14.4 if Sean wants it as a stored preference now |
| 4. Pace | `runners.avg_pace_sec_per_km` (0001:63, self-declared) vs `dogs.preferences.paceSuggestSec` (clamped 420-540, 0079:38-42) | EXISTS both sides |
| 5. The other handful | `max_dog_weight_kg`, `specialties` (both exist, both dead — 0001:62-65) vs `dogs.weight_kg`, `preferences.tags` | EXISTS, adopt as filters/tiebreak |

**The algorithm** (lexicographic, over the session's committed runners):

```
ELIGIBLE(r) :=  committed(r, session)                          -- 0043:217 row
            AND load(r) < cap(r)                               -- 0047:52 / 0037:37
            AND pickup_dist(r, addr) ≤ r.service_radius_km     -- step-2 hard filter
            AND dog.weight ≤ r.max_dog_weight_kg (when set)
            AND dog passes dog_custody_gate                    -- 0119, already fires at P0

RANK within eligible, in order (first difference wins):
  1. pickup_dist band (500 m buckets — banding kills float-order flap)
  2. |dog_pace − runner_pace| band (30 sec/km buckets)
  3. fewer accepted dogs this session (spread load)
  4. earlier session_runner_commit (seq — commitment rewarded)
  5. runner_profile_id (total order; determinism terminator)
```

`pickup_dist` is the equirectangular approximation already precedented inline at 0110:92-106 —
no PostGIS (`0001:4` installs pgcrypto only), correct to well under a band width at district
scale. Empty eligible set → the owner is told honestly ("지금 연결할 수 있는 크루 러너가
없어요") and offered Mode B's list or A — never a fabricated pick.

**Missing-column work list (S6):** `runners.home_address_id` (+ onboarding surface) ·
`club_sessions.start_lat/lng` or a geocoded meetup point (`meetup_point` is free text, 0030:57;
`routes.anchor_lat/lng` exist but are marked do-not-consume until founder-walk GPS, 0078:23-24 —
the spec does NOT lean on them) · nothing else; every other input exists.

**Counsel rider**: Mode C ships behind the intermediary-status brief (Sean's accepted rider).
S6 is sequenced last for exactly this reason (§12).

### 6.6 The host's residual matching role: recovery only

When a pick lapses inside T−2h, or a pairing dissolves at the meetup (revoke, decline,
no-show), someone must cover NOW. The host regains the propose pen **only inside the old
window [T−2h, T+6h]** and only for dogs at P2 — `session_propose_dog` survives with its gate
narrowed to that recovery window instead of being the primary path (this also keeps suite 154
G4's fixture drivable until its re-target, §11). Board copy names it 재배정, distinct from picks.

---

## 7. Custody — door to door

### 7.1 The pickup leg (P5)

On pairing, the runner sees: pickup address (§8), pickup window (🔵 `scheduled_at` minus route
travel minus run prep; concretely a stated window agreed in copy, not a new negotiation
machine), dog card, and the honest-transit sentence (rider: until insurance signs, the copy
states plainly that the transit leg is runner-responsibility, insured status shown as it is).
Runner taps 출발 (board state flips) and 도착 at the door — the arrival stamp is server-stamped
(the marketplace's `arrived_at` idiom; club bookings get the same column treatment, service-role
writer only, 0083 protected-columns law).

### 7.2 Per-pairing pickup mode (🔵) — the attending-owner scenario, solved where it lives

C7's missing scenario (a Mode B owner who attends — in a Banpo pilot the most likely case)
is not an edge: it's a per-pairing choice. At P2 the owner picks **집 픽업** (default; the flow
above) or **현장 인계** (owner brings the dog to the start and both-stamps there — today's
shipped chain, byte-identical). Return mirrors pickup (집 반환 / 현장 반환, same flag). One
column on the pairing (`pickup_mode`), zero new custody mechanics for the 현장 arm, and the
"pointless return trip to an empty home" the review flagged becomes unconstructable. 맹견 gate,
ladder, and finish logic are pickup-mode-blind. 🔴 §14.2 for Sean's nod since it reshapes his
"the runner should pick them up" default into a default-plus-option.

### 7.3 Transit is inside the run's custody — now stated, not implied

From the door both-stamp (P6) the dog is in the runner's custody (`custodian_type='runner'`,
0045:47-53 — the trigger doesn't care where the stamps happened). There is no between-legs
machine: a dog picked up that never arrives at start is a P6 pairing whose P7 event is overdue —
host-visible board state (지각/미도착), host tools unchanged (force-resolve requires
`picked_up|active`, 0070:210 — it already covers the transit leg **by construction**). SOS/case
entry is available to the runner from pairing onward, not only during the run (0067's gates
admit a runner who holds a dog; the run screen's entry point extends to the transit surface,
§10.3).

### 7.4 Arrival-at-start, and the re-anchored no-show money (C1 — the correction that forced v2)

**The broken thing**: under home pickup every delegated owner produces
`owner_confirmed_handoff_at` at their own door hours before the session — the exact signal the
0118 attendance gate reads (0118:1246-1250) — so the 20% rung would become structurally
unreachable: the third inertness of that gate, this time by design.

**The new predicate set** (per-pairing, all server-stamped, none erasable by reassignment
without its money consequence being re-derived):

- **Dog-at-start (the positive fact)**: the runner's `session_checkin` at the start stamps
  `session_dogs.checked_in_at` for every dog they hold (`responsible_profile_id = auth.uid()`,
  0030:259 — the mechanism EXISTS; what moves is that the custody trigger's premature
  `checked_in_at = coalesce(...)` stamp at `picked_up` (0045:53) is REMOVED for door-mode
  pairings, because at the door that stamp would mean "at the owner's home", which is exactly
  the C1 bug wearing a new column). 현장 인계 pairings keep today's semantics untouched.
- **Owner no-show (the chargeable fact)**: runner arrived at the door (arrival stamp §7.1
  present) AND no handoff occurred (both handoff stamps null) AND the pairing was live at
  `scheduled_at`. Fee: the ladder's top rung via `_club_record_no_show_fee` — the same writer,
  the same two-gate SHAPE as 0118 (time gate `now() ≥ scheduled_at` strict, evidence gates as
  `not exists` + bare `is null`, never `not(A and B)` over nullables — 0118:1237-1244), with
  the attendance evidence now: no door handoff AND no dog-at-start AND runner-arrival present.
  A pairing with NO arrival stamp charges the owner nothing — one-sided absence is not
  evidence of the owner's fault (the runner side is accountability, not owner fee).
- **Runner no-show at the door**: arrival stamp absent at `scheduled_at` → pairing dissolves at
  host confirmation into the refund arm (owner charged nothing), runner strike via
  `assignment_events` — the existing accountability rail (0057:174), policy numbers Sean's.
- **Suite consequence, same slice**: 153's P4/P9/P10/P12 re-pin to the new predicate; each
  re-pinned pin names its successor in a comment (the suite-updates-in-slice law).

The pairing-scope lesson is honored: all three facts are per-pairing and reassignment-safe by
construction (a reassignment creates a new pairing whose stamps start null — demotion to P2
already re-derives the money rung, §5.2). The one thing per-pairing keying cannot express —
"this OWNER attended, durably" — is Sean's open Custody A/B decision and is deliberately NOT
smuggled in here; if he picks B, the durable column lands in S4 alongside this predicate.

### 7.5 Two-phase finish (Sean's run-end flow) — the ordering inversion, done without breaking money

Today: settle → `return_pending` immediately (0045:55-59) → both-stamp return →
`club_finish_session` LAST (blocked until all returns resolve, 0045:328 → 0118:1121).
Sean's flow: per-runner finish → **host final confirmation** → THEN the return legs → release.

v2's mapping — three changes, everything else untouched:

1. **`custody_phase` gains `finished_pending_host`** (CHECK extension; the dead
   `outbound_pending` value, 0045:19 with zero writers, is retired in the same breath).
   The custody trigger's `completed` arm writes it instead of `return_pending`; `payout_state
   → earned` unchanged (runner money at settle is already the shipped truth, 0083:668-681).
2. **`club_confirm_run_end(p_session)`** — NEW, host (and 🔵 backup host — fixing the named
   asymmetry where backup can force-resolve but not finish, 0080:1002 vs 0118:1113, 🔴 §14.5):
   requires every delegated pairing to be at `finished_pending_host`, a cancellation arm, or an
   incident state (i.e. no dog still running — the runner-finish prompts Sean described are the
   client surface of reaching that state); stamps `club_sessions.run_confirmed_at`; flips all
   `finished_pending_host` pairings to `return_pending` (the return legs begin, per Sean —
   "after which the runner goes back to each owner's home"); and **carries the money block that
   today lives in `club_finish_session`** (recap post, never-picked-up refunds, the §7.4
   no-show fees, host fee) — the fee's time gate reads the same strict `now() ≥ scheduled_at`.
   Mode A pairings are untouched by it: released at their own finish, structurally (§4.3).
3. **`club_finish_session` becomes the closer**: requires `run_confirmed_at` present +
   `_club_dogs_unresolved = 0` (the predicate is UNCHANGED, 0045:328 — `finished_pending_host`
   joins its unresolved list) + the incident-ownership gate (0118:1122) — and now only flips
   `status='done'`. Money has already moved at confirmation; release still waits on `resolved`
   per pairing (C6 unchanged). 🔵 auto-close when the last pairing resolves and both gates
   pass, so a host never has to remember a second tap; the host CAN still close manually.

The load-bearing ordering invariants, preserved and named: runner-paid-at-settle precedes
return (shipped, 0083:668) · `payable` requires `resolved` (0070:381) · `released` requires
no open incident (0072:227-245) · chat/phone lifetime keys on unresolved custody and therefore
now correctly survives through the return legs (0049:36-43, 0049:174-180 — no change needed,
verified in §13 C19/C20).

### 7.6 Host never confirms — the recovery ceiling (🔴 §14.3)

A stalled human step now sits on the money path (the R1-class question, still open from v1).
Proposal unchanged from v1 §5 but now mechanically grounded: a bounded ceiling after the last
pairing reaches `finished_pending_host` (🔵 6h — the same constant the return-delay alarm
already uses, 0068:96-121), then the system performs the confirmation with an ops note and a
host notification. It moves money on a timer, toward paying completed work, on evidence
(settled runs); the silent-stalemate rule permits it, but a timer on money is Sean's word.
Until ruled, the fallback is the shipped one: the stale sweep refunds and the session stays
open — honest, just slow.

---

## 8. The club address slice — NEW security surface, named as its own work item (C3)

Verified: no club code path touches `addresses` today — club bookings mint with `address_id`
NULL (0081:184-197 column list), and the only booking→address read in the schema is
`booking_pickup_address` (0060/0065). The slice:

1. **Owner picks a pickup address at P2** (pay time — the moment the seat becomes real):
   `session_pay_delegation` gains `p_address_id`, validated owner-owns-address, written to the
   minted booking. 현장 인계 pairings (§7.2) pass null and never enter the address surface.
2. **The read path is the EXISTING gate, unchanged**: `booking_pickup_address`'s predicate —
   assigned runner only, en-route/picked-up/active or confirmed-within-24h (0065:52-62) —
   already expresses exactly the club need once club bookings carry an address. Zero new
   disclosure logic; the club reuses a measured gate rather than growing a sibling.
3. **Access logging** copies the live idiom (`club_phone_access_log`'s shape — dedup by
   viewer/target/session, rows only for values actually returned, 0049:236-248), NOT the dead
   `gate_code_access_log` shell (0060:52).
4. **Board/board-adjacent surfaces NEVER carry addresses** (§9 privacy row).
5. Adversarial cycle mandatory (0116 §D party-gate law; 0088 whole-request-403 hazard on any
   grant move). This is S4's server half and does not land without its pins.

---

## 9. The board — a NEW sanitized member projection (C8)

Today's `club_delegation_board` serves the OPERATIONAL views (owner/runner/host) and its grades
are correct for them (0052:149 wrapper + 0053:227 impl). What Sean asked for — *"all this
process can be shown in the club public home"* — is a different reader: the club member.
Verified: members-without-party get `runners: []`, `dogs: []` (0053:249,336), `owner_handled`
dogs appear nowhere (0053:331), and `club_overview`/`club_session_detail` carry no per-dog
state at all. Extending the operational board's grades would widen a measured surface; instead:

**NEW `club_session_board(p_session)`** — party gate: club MEMBER (`club_members` row — the
concept exists and is currently unused for visibility, 0030:30-36) or any shell grade ≠ none.
Returns, per live pairing and per 동반 dog: dog first name + photo · owner display name ·
state label from the P-ladder (대기 중 → 러너 선택 중 → 수락 대기 → {runner name}와 페어링 →
픽업 이동 중 → 이동 중 → 도착 → 러닝 중 → 러닝 완료 → 귀가 중 → 귀가 완료) · 동반 rows
(보호자 동반) · companion crew rows (이름 + 함께 달려요). Plus the session header facts already
public via `club_session_detail`.

**Privacy rows (each verified against a shipped precedent):** no addresses ever (§8.4) · no
money — fares appear ONLY on the consent screen (Sean's ruling ④, `delegate/[sid].tsx:20-27`)
· pick-pending runner names render to the CHOOSER and the picked runner only (the 0053:315-323
sub-gate's logic, inverted for the new chooser: in Mode B the owner authored the pick and sees
it; other members see 수락 대기 with no name until P4 makes the pairing public — Sean's board
shows pairs, not courtships) · a 맹견-refused or lapsed pick is indistinguishable from a
declined one to non-owners (0119 disclosure edge, carried from v1) · phone/emergency data stays
roster-gated (0049) — the board never joins it.

The operational board grows the new state columns (`pickup_mode`, arrival stamps,
`finished_pending_host`, `load`) via `create or replace` — grant-preserving, view law observed.
The console's client-side copy of `_club_dogs_unresolved` (`console/[sid].tsx:202-206`, the
known second copy of a server predicate) is retired in the respec: the operational board
exposes the blocker classification server-side and the console renders it (§10.2).

---

## 10. Screens — per side, per state (ui6 executes post-review; trunk ≥ 7dc88c9 is the base)

Legend: ● = primary surface · ○ = visible state · — = not shown. Every cell names today's file.

### 10.1 Owner (Mode B/C pairing) — `club/session/[sid].tsx` (owner cards) + `club/delegate/[sid].tsx`

| State | Owner sees | Owner can do |
|---|---|---|
| P0 신청 대기 | ● application card (exists: approval badge) | withdraw (free) |
| P1 승인 — 결제 대기 | ● hold card + DrainRing 20min (exists, `:751`) | pay (`자리 확정하기` — gains address pick §8.1 + pickup-mode pick §7.2) · withdraw (free) |
| P2 결제 완료 — 러너 선택 | ● NEW pick surface: committed-runner list (name, tier, pace, load/cap, distance band — **never money**) + 자동 연결 door (Mode C) | pick (B) · auto-pick (C) · cancel (ladder-quoted first, §5.4) |
| P3 수락 대기 | ● pick-pending card + TTL ring (DrainRing idiom) | withdraw pick (free) · cancel (quoted) |
| P4 페어링 확정 | ● paired card: runner name/photo, pickup window, pickup mode | cancel (quoted 20%) · objection (unchanged, 0047:250) |
| P5 픽업 이동 중 | ○ runner en-route + arrival state | — (chat) |
| P6 인계 | ● both-stamp door handoff (exists: `confirmHandoff(...,'owner')`, `:341` — re-copy for the door) | confirm handoff |
| P7-P8 이동/러닝 | ○ timeline states + live | SOS-adjacent: open case (party standing unchanged) |
| P9 러닝 완료 | ○ "러닝 완료 — 호스트 확인 대기" | — |
| P10 귀가 중 | ● return-pending card | confirm return (exists, `:359`) |
| P11-P12 종료 | ● receipt door (`club/receipt/[bid].tsx` — unchanged, T②+T① carousel as landed) | share nudges (as landed) |

Mode A owner: unchanged surfaces (`session_rsvp`/pass/check-in); board shows them 보호자 동반.
Copy honesty rows: transit sentence until insurance (rider) · mode-switch-after-pay states the
fee (§5.3) · a failed quote blocks the cancel confirm (§5.4).

### 10.2 Host — `club/console/[sid].tsx` respec (693 lines today)

KEEPS: admission queue (approve/reject — `doApprove`, `:138`) · materiality re-review
(`doReview`, `:154`) · cases section (assign/resolve, `:512-541`) · force-resolve + custody
override with the self-override dead-button logic (`:216-226`) · session cancel (`:268`).
LOSES: the runner-chip propose grid (`:445-461`) as the PRIMARY flow — it narrows to the §6.6
recovery window and renames 재배정, appearing only when a P2 dog exists inside T−2h.
GAINS: ● the run-end confirmation (§7.5) — one button, enabled when every pairing is terminal-
or-finished, with the same blocker rendering the finish gate has today, now server-classified
(§9 kills the duplicated predicate) · a pairs timeline (watch, not choose) · arrival/no-show
flags (§7.4) feeding the confirmation screen's evidence view.
Backup host: same console minus the arms the server refuses them (today: finish; §14.5 asks
Sean to level it).

### 10.3 Runner — `club/session/[sid].tsx` (runner cards) + `club/run/[sid].tsx` respec (Sean's "R" question)

| State | Runner sees | Runner can do |
|---|---|---|
| committed, no pick | ○ my cap/load, session card | withdraw commit (blocked by live charges — unchanged, 0043:421) |
| P3 pick inbox | ● pick card: dog profile (0119 tokens render here — landed wiring), owner first name, pickup mode+area band (NOT address), **expected net (contract §5)**, pace fit | accept / decline (+reason) — unchanged RPC |
| P4 paired | ● pickup brief: address NOW visible (gate §8.2), window, dog card | 출발 → 도착 (arrival stamp) |
| P6 door | ● both-stamp handoff | confirm handoff |
| P7 at start | ● start check-in (stamps held dogs — §7.4) | check in |
| P8 running | ● run console (trace, photos nudge as landed, **SOS per-dog entry preserved verbatim** — `run/[sid].tsx:285-309`, C2/C11) | finish per dog (settle — exists, `:264-270`) |
| P9 finished | ○ "호스트 확인 대기 — 귀가 대기" | — |
| P10 returning | ● return leg per dog: address, 도착+both-stamp | confirm return |
| P11 done | ● net-only earnings line (contract §5) | — |

The R screen (`run/[sid]`) is recalibrated, not deleted (v1 had this right): it gains the
pickup/transit/return legs as phases around the run phase it already owns, and its SOS entry
extends to every custody-holding phase (§7.3).

### 10.4 Member (non-party) — club home `club/[id].tsx`

● the §9 board replaces the empty-array silence: live state rows during a session, waiting/
paired states before it. No actions. Companion crew rows listed. (The club home's other jobs —
overview, series, tickets — untouched; the purple section IS the cover photo slot, already
answered.)

---

## 11. Deprecations — closure by refusal, reversible (C4)

| Surface | Action | Pins |
|---|---|---|
| `session_propose_dog` host-primary role | gate NARROWS to the §6.6 recovery window (create or replace; same name — ~17 suites keep resolving) | window pins re-pinned in-slice; suite 154 G4's fixture re-targets to `session_pick_runner` when S3 lands (the 0119 row's own note) |
| `session_assign_dog` | already an alias (0047:143) — revoke `authenticated` EXECUTE + refusal pin; `api.ts:3614` call site deleted (its one consumer is `dev/club-lab.tsx:16`) | 1 refusal pin |
| `session_reconsider_dog`, `session_review_dog` | KEPT (admission family, §4.2) — v1 wrongly listed review for retirement | — |
| `session_proposal_respond`, `session_proposal_revoke`, `session_assignment_revoke`, `session_owner_objection` | KEPT — they are the accept/dissolve rails the pick layer rides | gate-delta pins only |
| Console propose grid (client) | removed outside recovery window | — |

Nothing is DROPped; every EXECUTE revoke ships with the pin that proves the refusal (house
closure doctrine). Each landed suite whose pinned behaviour legitimately moves is updated in
the same slice with a WHY comment naming the successor pin.

---

## 12. Sequencing — slices, in dependency order

| Slice | Contents | Gated on |
|---|---|---|
| S1 | Runner-money strip (independent, claimed by announcer v5, contract @ f6ed2cf) | — (in flight) |
| S2 | §9 member board projection + operational-board state columns + the console-predicate de-duplication | spec review + Sean's read |
| S3 | Pick layer (§6.1-6.4, 6.6): `session_pick_runner`, gate moves, TTL, deprecations §11 | S2 (board renders picks); 🔴 14.1 |
| S4 | Door custody (§7.1-7.4) + address slice (§8) + no-show re-anchor + 153 re-pins + client legs | S3; riders (honest transit copy); 🔴 14.2 |
| S5 | Two-phase finish (§7.5): `finished_pending_host`, `club_confirm_run_end`, closer split, console respec | S4; 🔴 14.3, 14.5 |
| S6 | Mode C (§6.5): columns, ranking definer, `session_auto_pick`, onboarding surface | S3; **counsel brief answered** (rider); 🔴 14.4 |

Every S2-S6 migration: adversarial cycle (0059 doctrine), numbers two-sided from the remote tip
at write time, REGISTRY row in the same push, suites updated in-slice. Client halves land
atomically with any grant move (0088 law); no binary reaches a device before its `db push`
(the 0119 deploy-order law, now standing).

Kill criterion (review #2, Sean accepted the shape, the number is his): if no club session with
≥2 delegated dogs runs within N weeks of S3 landing, S4-S6 shelve and the §6.6 recovery window
becomes the permanent matching path. 🔴 14.7 picks N.

---

## 13. Consumer-by-consumer migration table (C10) — every reader of pairing/custody/finish order

Scouted at line; classes: **U** unchanged · **RA** re-anchored (same logic, new event/caller) ·
**RW** rewritten · **N** new.

| # | Consumer | Reads | v2 | Class |
|---|---|---|---|---|
| C1 | `_club_dogs_unresolved` 0045:328 | unresolved custody phases | predicate + `finished_pending_host` in its list; now gates the CLOSER, not the money step | RA (S5) |
| C2 | `club_finish_session` 0118:1102 | C1 + incident ownership + money block | SPLIT: money+recap → `club_confirm_run_end`; close → thin `club_finish_session` | RW (S5) |
| C3 | custody trigger `_club_custody_transition_v2` 0045:34 | booking status picked_up/completed | picked_up arm: unchanged mechanics, fires at door; drops the premature `checked_in_at` stamp for door-mode (§7.4); completed arm writes `finished_pending_host` | RW (S4+S5) |
| C4 | `session_confirm_return` 0069:84 | `return_pending` | untouched | U |
| C5 | `_club_finalize_return` 0070:343 | both stamps, weaker-kind record | untouched | U |
| C6 | `club_release_payouts` 0072:221 | payable + resolved + no open incident | untouched — the release ordering survives the inversion because it keys on `resolved`, not on finish | U |
| C7 | return-delay alarm 0068:96-121 | `return_pending` + `scheduled_at`+6h | base moves to `run_confirmed_at`+6h (returns can't be late before they begin) | RA (S5) |
| C8 | `club_stale_delegation_sweep` 0070:302 | stale open sessions, matching bookings | untouched (it is the no-host-ever recovery) | U |
| C9-C11 | incident settle/quote/resolve 0080:977, 0116:413, 0072:260 | incident_review, stamps, settlement items | untouched; quote's `took_custody` reads handoff stamps which exist in both pickup modes | U |
| C12 | `club_incident_open` 0070:393 | party + payout holds | untouched | U |
| C13 | `session_host_force_resolve` 0070:171 | picked_up/active | untouched — covers the transit leg by construction (§7.3) | U |
| C14 | `session_custody_override` 0070:243 | return_pending | untouched | U |
| C15 | console client predicate `console/[sid].tsx:202` | client copy of C1 | RETIRED — server classification via board (§9) | RW (S2/S5) |
| C16 | `club_dog_ui_state` 0116:552 | axes → stage | new stages (P5/P7/P9/P10 labels); party gate byte-identical | RW (S2) |
| C17 | board impl 0053:227 | projection | + state columns/load; member projection is NEW beside it | RW+N (S2) |
| C18 | `_club_compute_axes` 0048:687 | booking status, custody events, cancel_reason | derives the new states; the `club_not_picked_up→no_show_owner` unconditional label (0048:747 — wrong for the refunded runnerless arm) is corrected while the function is open | RW (S4) |
| C19 | chat lifetime `_club_chat_writable` 0049:29 | done + unresolved custody | untouched — verified the predicate already survives returns-after-done | U |
| C20 | phone lifetime `_club_phone_visible` 0049:167 | unresolved custody | untouched | U |
| C21 | `_club_incident_can_open` 0067:68 | shell/owner/held-runner | untouched | U |
| C22 | `delete_account` arms 10/11 0115:358-394 | `checked_out_at is null` | untouched (`checked_out_at` writer is still C5) | U |
| C23 | `session_cancel_delegation` 0118:989 | matching/confirmed boundary | untouched; the `already_handed_off` wall moves earlier in wall-clock only | U |
| C24 | `cancel_owner.ts:57` 409 | club exclusion | untouched | U |
| C25 | settle-run reasons | `incident` ownership | untouched | U |
| C26 | materiality trigger 0048:222 | booking status; stamp eraser | untouched; its stamp erasure is money-safe under §7.4's per-pairing predicates | U |
| C27 | `session_review_dog` reject arm 0048:278 | refunds `matching` only | KEPT; the confirmed-not-refunded quirk is pre-existing, now NAMED here so it stops being silent — 🔴 14.8 one-word fix rider | U (flagged) |
| C28 | 0119 gates 0119:250-433 | custody-bound writes | ZERO changes; G4 fixture re-targets at S3 | U |
| — | `session_checkin` 0030:245 | window + session_people | untouched for people; its dog-stamp clause becomes the §7.4 positive predicate | RA (S4) |
| — | 0118 no-show WHERE 0118:1157-1250 | confirmed+runner+time+attendance | attendance evidence set replaced (§7.4); moves into `club_confirm_run_end` | RW (S4+S5) |
| — | viability 0048:354 | headroom over checked-in runners | headroom re-reads over PAIRED runners pre-session (checked-in is too late to be the coverage question once pairing precedes the meetup) | RA (S3) |

---

## 14. 🔴 Open with Sean (everything in one place, one word each where possible)

1. **Pick TTL** — 2h with lapse-back proposed (§6.3). · 「2시간」 / your number
2. **Per-pairing pickup mode** {집 픽업 default, 현장 인계 option} (§7.2) — solves the
   attending-owner case; slightly reshapes "the runner should pick them up" into
   default-plus-option. · 「좋아」 / 「집 픽업만」
3. **Host-never-confirms ceiling** — 6h after last runner-finish, then system confirms with ops
   note (§7.6). Moves money on a timer toward paying completed work. · 「좋아」 / 「타이머 반대」
4. **Owner distance preference in Mode C** — skip in pilot (vacuous: run distance is
   route-fixed; only the pickup leg remains) or store a field now (§6.5). · 「스킵」 / 「필드로」
5. **Backup host may confirm run end?** Today backup can force-resolve but not finish
   (0080:1002 vs 0118:1113). §7.5 proposes leveling it. · 「백업도」 / 「호스트만」
6. **Non-runner companions** — runner-tier only proposed (§4.4); guests remain plain RSVPs.
   · 「러너만」 / 「게스트도 크루로」
7. **Kill criterion N** — no session with ≥2 delegated dogs within N weeks of S3 → S4-S6
   shelve (§12). · N = ?
8. **C27 quirk** — a `confirmed` booking rejected at materiality re-review is not refunded by
   that arm (0048:278 filters `matching`). Pre-existing; one-word rider to fix in S4 or leave
   documented. · 「고쳐」 / 「그대로」
9. Standing, unchanged by this spec: the club 9,900-vs-7,900 base gap (memo ④) · 맹견
   refused-vs-conditions · breed-alias scope · the Custody A/B durable-attendance decision
   (§7.4 interlocks with it) · counsel briefs (S6's gate).

---

*Review path: blind adversarial review (fresh Claude voice + codex, neither shown this spec's
reasoning, both given the scout facts and Sean's verbatim rulings) → revise → Sean. The spec
decides nothing he didn't say; every 🔵 is reversible in one word; every 🔴 blocks only its own
slice.*
