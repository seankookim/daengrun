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
trunk tip (≥ `5bd2d59`, after the 0118+0119 landings) with file:line citations. This is the
THIRD draft: draft 1 went through TWO independent blind adversarial reviews (a fresh Claude
voice and a codex voice, neither shown the author's reasoning) returning 15 + 9 findings,
several design-breaking; every one is answered in-text below and logged in §15.
Decisions Sean has not made are 🔴 (§14). Proposals this spec makes on its own authority are 🔵
— reversible in one word.

Status: DRAFT v2.2 — both blind rounds folded in (Claude voice: 15 findings; codex voice: 9
findings; dispositions in §15); ready for Sean. Nothing here is built.

---

## 0. Corrections compliance — how v2 answers the four-voice review

| # | v1's error | v2's answer |
|---|---|---|
| C1 | "0118 gates survive unchanged" — FALSE; home pickup auto-satisfies `owner_confirmed_handoff_at` hours early | New no-show predicate with named producers for every term (§7.4), P4/P9/P10/P12 re-pinned in the same slice (§12 S4) |
| C2 | Mid-run case entry "preliminary" | VERIFIED — entry point at `club/run/[sid].tsx:289-309` (SOS → `club_incident_open` → case route); the R respec carries it forward verbatim (§10.3) |
| C3 | "Address exposure reuses gate_code idiom" — overstated | Club address path is a NEW numbered security slice (§8) that OWNS its disclosure-window decision; `gate_code_access_log` is a documented dead shell (0060:52) |
| C4 | Retire five functions (~88 pin edits) | DEPRECATE: revoke + refusal pins, reversible (§11). `session_assign_dog` is already a one-line alias over propose (0047:143-146) — the retirement v1 planned was mostly already done |
| C5 | Free mode-switch contradicts the ladder | Mode switch after payment IS a paid-delegation cancel and rides the ladder; the UI says so before the tap (§5.3). Mint timing does NOT move (§5.1, reasoned) |
| C6 | Dogless companion = safety hole | Companions are `session_rsvp(p_dog := null)` runner-tier attendees — existing machinery: identity (runner tier), party standing (`session_people` → shell `full` → incident standing), headcount capacity, zero money (§4.4) |
| C7 | Six silent decisions | Each is now explicit: mode exclusivity §4.1 · per-dog approval §4.2 · transit-inside-custody §7.3 · pending picks and capacity §6.4 · Mode A copy-only VERIFIED §4.3 · **the attending Mode-B owner: per-pairing pickup mode ∈ {집 픽업, 현장 인계} (§7.2, 🔵)** |
| C8 | "Board data shape is close" — FALSE | The member board is a NEW sanitized projection (§9); today's board returns runners/dogs only to host/full/limited-owner (grade filters 0053:252/268 and 0053:334-336) and queries `runner_delegated` only (0053:330) |
| C9 | "Cap semantics unchanged" contradicted `_club_runner_load` | v2 ADOPTS today's load semantics unchanged (accepted + live picks + own 동반견, 0047:52-65) — a pending pick consumes capacity, which makes the concurrent-approval conflict structurally impossible (§6.4) |
| C10 | Two-phase finish consumer blast radius unnamed | The consumer-by-consumer table is §13 — including the transfer family, the edge functions that WRITE these states, and the copy-drift list (round-1 findings 7 and 8) |
| C11 | (upgrade of C2) | Same as C2; the run screen's per-dog SOS branching (0-dog / 1-dog / multi-dog) is preserved as-is |

Two peer-supplied facts also honored: club fees never route through `quote_cancel_fee` (it
raises `club_out_of_scope` in every entry point — 0117:415/856/1002; 0117 LANDED on trunk and
DEPLOYED mid-drafting, 2026-08-25, so this is now a trunk fact; §5.4's club quote surface is
specified against the club ladder directly), and every handoff stamp today is pairing-scoped
and erased by six reassignment paths (0118:1207-1216) — so this machine is **keyed per-pairing**, and the
one place a per-person durable fact is wanted is named and left to Sean's open Custody decision
(§7.4).

---

## 1. The one coupled machine — overview

The RETHINK's demand, met head-on: pairing, money, custody, cancellation, and finish are one
machine whose single subject is the **pairing** — a `session_dogs` row plus its booking. Session-
level state stays thin (`open/full/done/cancelled`, unchanged CHECK, 0030:62) plus one new
timestamp (`run_confirmed_at`, §7.5); everything else lives per-pairing, because that is where
the shipped machine already keys everything (axes trigger 0040:281, custody trigger 0045:64,
fee writer 0118:789) and because per-pairing keying is what survives the stamp-erasure class.

### The per-pairing state ladder (Mode B/C; Mode A short-circuits in §4.3)

| # | State | Underlying facts | Money | Entered by |
|---|---|---|---|---|
| P0 | `signed_up` | `session_dogs` row, `custody='runner_delegated'`, `approval='pending'` | none | owner: `session_delegate_dog` (0048:89) — 0119 gate fires HERE (INSERT trigger, 0119:415) |
| P1 | `admitted` | `approval='approved'`, 20-min hold (0084:635) | none | host: `session_approve_dog` — admission survives (§4.2) |
| P2 | `paid` | booking minted `status='matching'`, `runner_id=null` (0081:184) | seat real; no charge (0081:207) | owner: `session_pay_delegation` — **mint timing unchanged** (§5.1) |
| P3 | `pick_pending` | `proposed_runner_profile_id` set, `proposal_expires_at` = now()+TTL | none | owner (Mode B) or platform (Mode C) — the chooser swap, §6 |
| P4 | `paired` | booking `confirmed`, `runner_id` set (0057:132-134) | 20% rung arms **only inside the 24h window** (§5.2 — round-1 F1) | runner: `session_proposal_respond(true)` — approval stays the runner's, with no self-pair path (§6.1) |
| P5 | `pickup_enroute` | **booking stays `confirmed`**; 출발/도착 stamps are NEW `session_dogs` columns (§7.1 — round-1 F3) | — | runner taps 출발/도착 (server-stamped) |
| P6 | `picked_up` | both handoff stamps → booking `picked_up`; custody trigger flips custodian to runner (0045:44-53) | — | both-stamp `confirm_handoff` at the DOOR (or at start for 현장 인계 pairings, §7.2) |
| P7 | `at_start` | dog-at-start stamp (§7.4 — the no-show predicate's positive side) | — | runner's `session_checkin` stamps held dogs (0030:259 mechanism, re-anchored) |
| P8 | `running` | booking `active`, `runs` row (0050:169-186) | — | runner: `club_start_delegated_runs` |
| P9 | `run_finished` | booking `completed` via settle-run (0083:628); `custody_phase` = new `finished_pending_host` (§7.5) — **escapable by construction** (§7.6) | runner paid at settle (club has no return seal — the marketplace-only guard, 0083:677-688); NOT payable yet | runner settles per dog — this IS Sean's "per-runner finish" |
| P10 | `returning` | `custody_phase='return_pending'` | — | **host run-end confirmation flips all P9 pairings at once** (§7.5) |
| P11 | `resolved` | both return stamps → `_club_finalize_return` (0070:343): custodian back to owner, `payable` | payout `earned→payable` | both-stamp at the home door (or 현장 반환) |
| P12 | `released` | `payout_state='released'` | supply money leaves | cron `club_release_payouts` (0072:221) — UNCHANGED, still requires `resolved` + no open incident |

Cancellation arms exit this ladder at defined points only (§5.3). Incident states
(`incident_review`, holds, settlement) are orthogonal and UNCHANGED (0070/0072/0080 — §13
C9-C14). The 맹견 gate fires at P0 (INSERT) and at every custody-bound move exactly as landed —
zero 0119 changes, and §7.1's stamp design is chosen specifically so that stays true (§13 C28).

**What actually changed vs today, in one sentence each:**
1. The chooser at P3 is the owner or the platform; the host keeps only a marked recovery role
   (§6.6, 🔵/🔴).
2. P5-P7 are new legs: custody starts at the owner's door and the dog travels to the start
   inside the runner's custody (§7).
3. P9→P10 inverts today's automatic `completed → return_pending` (0045:55-59): the return leg
   begins at the host's run-end confirmation, which is where Sean put it — with three
   unconditional escape hatches so no dog and no account can be stranded on one human tap
   (§7.6).
4. The no-show money predicate re-anchors from "handoff stamp at the scene" to door + start
   evidence with named producers for every term (§7.4) — the C1 correction.
5. The cancel ladder's free-24h ruling is preserved by HOISTING the free window above the
   post-accept rung — early pairing must not reprice early cancellation (§5.2).

---

## 2. Actors

| Actor | Gains | Loses | Identity/standing mechanism (today's, reused) |
|---|---|---|---|
| Owner | per-session mode fork; Mode B pick + pick withdrawal; per-pairing pickup mode; custody timeline visibility | nothing | `session_dogs.owner_profile_id`; shell `limited/full` (0049:9) |
| Paired runner | approves picks made days ahead; a self-exit lever (§6.2); door pickup; transit custody; per-dog finish; return leg | being chosen at the scene | `session_runner_assignments` commit (0043:217); tier cap (0037:37) |
| Dogless companion | board visibility; ride-along | — (never paid — ruled) | `session_rsvp(dog:=null)` → `session_people(role='runner_attending')` (0048:181) — §4.4 |
| Host | run-end confirmation; admission (kept); session lifecycle (kept); force-resolve/override/cases (kept, with widened phases §7.6); a marked recovery-propose window (§6.6 🔵) | choosing runners as the primary path | `host_profile_id`; backup-host asymmetries per §14.5 (a money-routing question, not just permissions) |
| Club member (non-party) | the sanitized board (§9) — with its readership honestly stated (🔴 14.9) | — | NEW projection; today they see the `session` object only (0053:229-249 emits it ungated) |

---

## 3. What is ruled vs proposed — the authority map

RULED (Sean's words, on origin): owner/app chooses, runner approves · home pickup by the paired
runner, responsibility door-to-door · every step visible on the club public home · replaces
at-the-scene matching · dogless companions unpaid · per-runner finish → host final confirmation
→ return home; owner-run dogs release immediately · Mode C = the deterministic ranking he
sketched · riders: honest transit copy, no-show predicate at arrival, Mode C behind counsel ·
**owner cancellation free ≥24h before the session** (2026-08-21, recorded at 0118:210 — §5.2
exists to keep this true).

PROPOSED by this spec (🔵, each reversible): per-pairing pickup mode {door, start-point} (§7.2)
· pick TTL 2h with lapse-back (§6.3) · the three unconditional escape hatches for
`finished_pending_host` (§7.6) · host recovery-propose window (§6.6 — with its own 🔴) ·
companions = runner-tier RSVP (§4.4) · Mode C pilot inputs and their new CHECK bounds (§6.5) ·
mode-switch fee copy (§5.3) · address at T−24h, area band at pairing (§8).

STILL SEAN'S (🔴): the list in §14. Nothing below builds until the review passes; S4-S6 (§12)
additionally wait on the named riders, and S5 is HARD-GATED on 🔴 14.3 (§7.6).

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

### 4.2 Host admission SURVIVES; host matching narrows to a marked recovery role

Sean moved the *chooser*, not the bouncer: *"the customer or the app chooses the to-be-paired
runner … instead of the host."* Today's `session_approve_dog` (0084:610) is dog admission —
vetting an animal into a group run the host is responsible for — and it writes no pairing.
It stays, byte-identical, as P0→P1. What changes is the host's chooser role:
`session_propose_dog`'s `not_host` gate (0048:452) stops being the only path to a pairing;
§6 makes the owner/platform the author and §6.6 confines the host's pen to a recovery window —
a confinement this spec proposes (🔵) and Sean must bless (🔴 14.10), because his words said
"replace", and a recovery window is a residue of the replaced thing. `session_review_dog`
(materiality re-review, 0048:259) also survives untouched — safety, not matching. The host also
keeps `session_assignment_revoke` (dissolving a pairing before handoff, 0057:158-185) — named
here explicitly because it is chooser power in dissolve form; it stays because somebody
responsible for the session must be able to un-pair a runner who goes dark, and its strike rail
(0057:174) is the accountability ledger.

### 4.3 Mode A is copy-plus-one-gap, and the gap is the board

VERIFIED (v1 claimed, review challenged, scout confirmed): `session_rsvp` with a dog writes
`custody='owner_handled'`, no booking, no approval, no money (0048:189-191); the axes trigger
short-circuits every axis (0048:698); the 0119 trigger's WHEN clause skips it (0119:415-416);
release-at-finish is structural (no custody to resolve). Mode A needs **no machinery** — but it
does need the board: today `owner_handled` dogs are invisible (`custody='runner_delegated'`
filter, 0053:330) while Sean's board shows *"who's dog is running with who AND which dogs are
waiting"*. The §9 projection adds them.

### 4.4 Dogless companions = the machinery that already exists

Sean: *"Runners that don't have a dog can also just come along; they just won't be paid
anything."* The review's C6 objection (unverified stranger among customers' dogs, no incident
standing) dissolves once companions are what the schema already models: a certified runner
calling `session_rsvp(p_session, null)` gets `session_people(role='runner_attending')`
(0048:181), which yields shell `full` (0049:14) → board visibility, chat, and
`club_incident_open` standing (0067:68 admits shell `full`). They occupy `people_capacity`
headcount (0048:170-171), hold no delegated slot, touch no bookings, appear in no money path.
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
(0081:139-192) and are measured; (c) slot-based comp needs the booking to exist BEFORE
acceptance so the supply half has a ledger anchor the moment P4 arms. The C5 consequence is
handled as UI honesty (§5.3), not as a mint move. The club-vs-marketplace base-fare gap
(9,900 vs 7,900, memo ④, 0081:174-182) is inherited unchanged and stays on Sean's queue — not
this spec's to fix.

### 5.2 The ladder — the free window is HOISTED, or early pairing reprices early cancels (round-1 F1)

The shipped rung ORDER checks post-accept first (0118:1044-1054): `confirmed`+runner → 20%
regardless of time. That order is harmless today only because a pairing cannot exist before
T−2h (`assign_window`, 0048:454) — the 20% rung is structurally unreachable inside the free
window. The moment picks open at session creation (§6.2), that shield is gone: a Monday
pairing cancelled Wednesday for a Sunday session would pay 20% + the supply half, against
Sean's recorded ruling that ≥24h cancels are free (0118:210, `cancel_free_hours=24`, 0048:15).

**v2's ladder, therefore (a rung REORDER, not a rate change):**

| Rung | v2 predicate |
|---|---|
| free | `scheduled_at − now() ≥ cancel_free_hours` — **checked FIRST, pairing-blind** |
| 20% post-accept | inside 24h AND `confirmed` AND `runner_id not null` |
| 10% late | inside 24h, unpaired |

Ruling B (runnerless → platform half only, 0118:816-826) is untouched. Slot comp reading: a
runner whose pairing is cancelled ≥24h out held a re-fillable slot (the pick surface is open;
capacity frees instantly) — no supply half, consistent with slot-based comp's own logic. Inside
24h the slot is likely unfillable and the 20%/supply-half arm compensates exactly as ruled.
🔴 14.11: this reorder is the only reading that keeps BOTH his rulings (free ≥24h · slot-based
comp) true at once, but it is money semantics — one word to confirm. §13 reclassifies
`session_cancel_delegation` as RW (rung reorder + suite 153's ladder pins re-pinned in-slice).

Two honest carries: acceptance is STATE-anchored and reversible — the six demotion paths that
null `runner_id` and erase stamps (0118:1197-1201) still demote an owner off the 20% rung. And
the runner's supply half on a fee accrues to `ledger_items` with `platform_fee=0` exactly as
landed (0118:878-886) — v2 adds no new fee writer; `_club_record_fee` (0118:789) remains the
only one.

### 5.3 Cancellation arms, per state (the coupled machine's exit table)

| Exit at | Path | Money | Mechanism |
|---|---|---|---|
| P0/P1 | owner withdraws | none; hold released | 0118:1025-1032 arm, unchanged |
| P2 | owner cancels | ladder (free/10%), ruling B — no runner | `session_cancel_delegation` 0118:989 with §5.2's rung order |
| P3 | owner withdraws the pick (free) or cancels; runner declines; TTL lapses | decline/lapse/withdraw move NO money and return to P2; cancel rides the ladder (runnerless) | withdraw: `session_proposal_revoke` gate widened to the pick's author (§6.2 — round-1 F10) · decline: 0057:145 arm · lapse: recovery cron 0068:41-58 with §6.3's TTL |
| P4 | owner cancels | free ≥24h; inside 24h: 20% + supply half (slot held) | §5.2 |
| P4 | mode switch → A | **same as owner cancel at P4 — the UI states the fee before the tap** (C5) | client copy + the §5.4 quote surface |
| P4 | runner exits | pairing dissolves to P2, stamps nulled, owner keeps seat; strike via `assignment_events` (policy number = Sean, 0057:174) | `session_assignment_revoke` gate widened to admit the assigned runner's SELF-exit alongside the host (§6.2 — round-1 F10) |
| P5/P6 boundary | owner cancels | allowed until the door both-stamp (booking still `confirmed` — §7.1), then REFUSED `already_handed_off` (0118:1037) | unchanged predicate; the wall moves to the DOOR in wall-clock only |
| P6+ | anything wrong | incident machinery, not cancellation (0070/0072/0080) | unchanged |
| session-wide | host cancels session | full refunds both arms, no fee; refused if any dog past the door (`session_in_flight`, 0038:235-239 — `picked_up`/`active` already covers door-mode custody). A cancel while a runner is EN ROUTE to a door is permitted and dissolves those pairings pre-custody with runner notification — named, accepted, copy says so | unchanged + copy |
| session-wide | host confirms run end | no-show fee (§7.4 predicate) + refunds of never-picked-up pairings | `club_confirm_run_end` (§7.5) |

### 5.4 Two club money surfaces this spec ORDERS (new server asks, own slices)

1. **Club cancel quote.** The marketplace `quote_cancel_fee` refuses club rows by design
   (`club_out_of_scope`, 0117:415 — landed on trunk and deployed 2026-08-25), and the
   honesty law forbids quoting the ladder from client constants. Before any owner-cancel
   confirm in club: a read-only definer `quote_club_cancel_fee(p_session_dog)` returning the
   §5.2 ladder's answer (rung, pct, won amount, ruling-B halving) computed from the same
   predicates `session_cancel_delegation` charges from — party-gated to the owner, flat
   whitelisted return. A failed quote blocks the cancel button (the mirror's own law, applied
   to club).
2. **Runner-facing money.** Club runner surfaces (pick cards, session pay lines, finish
   screens) are net-only BY CONSTRUCTION per the runner-money contract §5
   (`docs/contracts/runner-money-strip-contract.md` — on `claude/runner-money-strip` @
   f6ed2cf, under review; cited as a contract-in-flight, and S2+ re-verify it landed before
   binding to it): `expected_net` computed server-side, never a component set, gross, fee, or
   rate. One line that contract asks this spec to carry: club pricing today inherits the
   public km-linear `club_fare` (0043:14), so its §0 named residual (rate regressable from
   net-vs-km) applies to club too; if club pricing ever decouples runner net from the public
   per-km line, that is the door to closing it — a pricing decision, Sean's, not assumed here.

### 5.5 The objection arbitrage (round-2 F4) — a shipped hole the long pairing window would blow open

`session_owner_objection` (0047:250) was designed for the at-the-scene world: `preference`
objections are windowed (T−20, once) but `safety` objections are unlimited (0047:257-275), and
`p_want_refund=true` exits a `confirmed` booking to a FULL refund with no fee and no supply
comp (0047:280-287) — while `p_want_refund=false` demotes to `matching`, from which a cancel
prices on the cheaper runnerless rungs. Today the exposure window is minutes (a pairing cannot
exist before T−2h); under v2 a pairing lives for days, and the objection becomes the obvious
free-cancel lever around the whole ladder.

S3 re-specifies it (🔵, a behavior change to a shipped function, its pins updated in-slice):
- **Objection un-pairs; it never refunds.** Both kinds return the pairing to P2 (runner
  cleared, stamps cleared, seat KEPT — the owner objected to a runner, not to the service).
  The full-refund exit at P4 exists only through cancel (the §5.2 ladder) or incident
  adjudication.
- **`safety` objections open an incident row** in the same transaction — free, unlimited, and
  ACCOUNTABLE: a safety claim about a runner is exactly what the incident machinery exists to
  record, and a pattern of them is visible instead of silently farming free exits.
- **The demote-then-cancel arbitrage is priced away by the same move**: with no refund exit
  and the seat kept, an owner who objects and then cancels prices on the ladder as of the
  cancel — and 🔴 14.11's rung question includes whether the post-accept rung should read
  "was OWNER-dissolved after an acceptance inside the window" from `assignment_events`
  (event-anchored, author-sensitive) rather than live state, which closes the residual
  demote-first arbitrage for good. One package, one word.

---

## 6. The pick layer — chooser swap on today's proposal machinery

### 6.1 One machine, two choosers — and no self-pairing

`pick = proposal with a different author.` The shipped proposal machinery
(`proposed_runner_profile_id` + `proposal_expires_at` + `assignment_events` + accept/decline in
`session_proposal_respond`, 0057:104) is reused whole, with two deliberate deviations:

- **No self-proposal arm.** The shipped host path auto-confirms a self-proposal
  (0048:492-500). An owner-authored pick must NEVER inherit that: `session_pick_runner` and
  `session_auto_pick` both refuse `p_runner = sd.owner_profile_id` (`self_pick`), and an
  owner-authored pick ALWAYS requires the runner's accept — otherwise an owner who is also a
  committed runner pairs themselves, both-stamps their own handoff (the edge fn supports one
  account on both sides, index.ts:305-312), and collects the runner payout — or the supply
  half of their own cancel fee — on a booking they own (round-1 F5, both paths). Refusal pins
  on both RPCs; the host recovery propose (§6.6) keeps its shipped self-proposal semantics
  (host covering at the scene is today's behavior, unchanged).
- The runner's accept gate — the part Sean kept ("which the runner can approve") — is
  byte-identical, including the load re-check `load − 1 ≥ cap → runner_cap_full` (0057:126).

New RPC `session_pick_runner(p_session_dog, p_runner)` — party gate: the dog's owner (P2 only,
one live pick per dog — `proposal_active`, 0048:473-475). Mode C's entry
`session_auto_pick(p_session_dog)` — owner-called ("connect me"), definer ranks (§6.5) and
writes the pick; the runner still accepts. Both write `assignment_events('proposed',
reason='owner_pick' | 'auto_pick:<rank-vector>')` so the chooser is auditable.

### 6.2 Gates that move, and the two that must WIDEN (round-1 F10)

Today's propose gates assume the meetup: assign window `[T−2h, T+6h]` (0048:454) and
`runner_not_checked_in` (0048:465-467). A pick made days early can satisfy neither. v2:

- **Window**: picks open at session creation and close at `scheduled_at`. The T−2h..T+6h
  window RETAINS one job: it bounds the host-side *recovery* propose (§6.6) and check-in.
- **Checked-in**: dropped for picks; replaced by `committed` (`runner_not_committed`,
  0048:464) + cap headroom + the 0119 gate + §6.5's hard filters. The runner's physical
  presence obligation moves to P5/P7 (§7.4).
- **`session_proposal_revoke` gate WIDENS**: today host-only (0047:210). v2 admits the pick's
  author-owner revoking their OWN live pick — otherwise §10.1's "withdraw pick" and "re-pick"
  are dead buttons (`proposal_active` blocks a second pick while one lives).
- **`session_assignment_revoke` gate WIDENS**: today host-only (0057:168). v2 admits the
  ASSIGNED runner dissolving their own pairing (self-exit, pre-handoff) — otherwise §5.3's
  "runner exits" row has no mechanism. Self-exit writes the same `assignment_events` strike
  trail; the strike policy numbers remain Sean's.
- **What does NOT move**: `not_approved` (must be P2 — paid), `review_pending`, one-live-pick,
  `already_handed_off`, cap check at propose AND at accept. All byte-identical.

### 6.3 Pick TTL (🔵 2h, 🔴 the number is Sean's)

5 minutes (0048:507) is meetup-scale and dies with the meetup context. A pre-session pick needs
hours: 🔵 **2h with a push to the runner at issue and at T−15min, lapse returns the dog to P2
with the owner notified** (recovery cron 0068:41-58 already expires stale proposals — it gains
nothing but the new TTL). A pick issued <2h before `scheduled_at` clamps to `scheduled_at`.
Sean picks the number (§14.1). The shipped 「5분 안에 수락 여부를 결정하세요」 notification copy
(0048:511) is TTL-bearing and re-writes with the slice (§13 copy row).

### 6.4 Capacity — adopted verbatim, and why that answers C9

`_club_runner_load` = accepted + live proposals + own 동반견, per session (0047:52-65).
v2 changes NOTHING. Consequences, stated so nobody re-derives them: a runner sitting on a live
pick is capacity-consumed, so a cap-1 runner shows unavailable to every other owner until they
answer or the TTL lapses — serialization by consumption, which is exactly what makes the
concurrent-approval conflict impossible (two accepts for one slot can't both pass the accept
re-check, and under consumption the second pick can't even be issued). The board's `assigned`
count divergence (accepted-only, 0053:257-260, vs the enforcement formula — the known
dead-chip pre-gate at `console/[sid].tsx:440-460`, `full = r.assigned >= r.cap` at `:446`)
gets fixed in the §9 projection: the board exposes `load` and `cap`, and every pick surface
pre-gates on the same number the server enforces.

### 6.5 Mode C — the ranking algorithm (Sean's ladder, made buildable)

**Constraints first**: deterministic (same inputs → same pick, no randomness, no learned
weights — the 비포펫 patent gates: no learned runner model), auditable (the rank vector is
logged in `assignment_events.reason`), and the runner still accepts (Mode C is Mode B with a
different author — a bad auto-pick costs a decline, never a custody).

**Inputs — what exists vs what must be built** (scouted at line):

| Ladder step (Sean's order) | Input | Schema today |
|---|---|---|
| 1. Proximity runner-home ↔ owner-home/start | runner home coords | **MISSING — new**: `runners.home_address_id → addresses(id)` (a runner IS a profile and `addresses.owner_id → profiles` already fits; onboarding + runner profile screen gain the field). Owner side: the pickup address chosen at P2 (§8), `addresses.lat/lng` (nullable — pinned addresses only, 0065:29-33) |
| 2. Runner's distance preference | `runners.service_radius_km` | EXISTS, read by nothing (0001:64) — adopted as the pickup-radius **hard filter** |
| 3. Owner's distance preference | — | **MISSING**, and in-club the run distance is route-fixed (`bookings.km` read from the route at 0081:159), so the only distance the owner can have a preference about is the pickup leg. 🔵 pilot: SKIP this rung (vacuous at Banpo scale); 🔴 §14.4 if Sean wants it as a stored preference now |
| 4. Pace | `runners.avg_pace_sec_per_km` (0001:63, self-declared) vs `dogs.preferences.paceSuggestSec` (clamped 420-540, 0079:38-42) | EXISTS both sides |
| 5. The other handful | `max_dog_weight_kg`, `specialties` (exist, unread — 0001:62-65) vs `dogs.weight_kg`, `preferences.tags` | EXISTS, adopt as filters/tiebreak |

**Input integrity (round-1 F11).** The four adopted `runners` columns are self-declared AND
client-writable today (`runners self write` policy, 0057:482-485) with NO CHECK on the live
table (the 0.5–20 radius and 180–900 pace bounds live only on `runner_applications`, 0062:67-69).
The moment they become an allocator of paid work, S6 adds the table-level CHECKs (mirroring
0062's bounds) in the same migration — an unbounded self-write feeding a ranker is a gamed
ranker by construction. Beyond bounds, the design's honest position: these are DECLARATIONS,
and a runner who inflates radius or mirrors the common pace to farm picks wins rank but not
custody — the accept step, the decline/strike rail, and the host's dissolve lever are the
backstops; no behavioral scoring is added (patent gate).

**The algorithm** (lexicographic, over the session's committed runners):

```
ELIGIBLE(r) :=  committed(r, session)                          -- 0043:217 row
            AND r.profile_id <> sd.owner_profile_id            -- §6.1 self-pick refusal
            AND load(r) < cap(r)                               -- 0047:52 / 0037:37
            AND pickup_dist(r, addr) ≤ r.service_radius_km     -- step-2 hard filter
            AND dog.weight ≤ r.max_dog_weight_kg (when set)
            AND dog passes dog_custody_gate                    -- 0119, already fires at P0

RANK within eligible, in order (first difference wins):
  1. pickup_dist band (500 m buckets — banding kills float-order flap)
  2. |dog_pace − runner_pace| band (30 sec/km buckets)
  3. fewer accepted dogs this session (spread load)
  4. earlier commitment (NEW `session_runner_assignments.committed_at` — round-2 F7a: the
     table has NO order column today (0030:93-99) and recommit is an order-losing upsert
     (0043:242-245); the column lands in S6 with upsert semantics that preserve first-commit)
  5. runner_profile_id (total order; determinism terminator)
```

**Distance is definer-internal, never rendered per-runner (round-2 F7c).** The first draft
showed owners a distance band per committed runner; because an owner controls their query
coordinate (their own pin), repeated picks from chosen pins would intersect 500m annuli and
triangulate a runner's home. So: the pick list renders pace fit, tier, and load/cap — no
distance-derived value, banded or otherwise. Proximity exists only inside `session_auto_pick`'s
ranking, whose output is one runner, not a geometry. The runner-home pin itself rides the same
client-write path whose falsely-pinned-address repair is already a named open slice (0073:35-38)
— S6 depends on that repair for input honesty and says so.

`pickup_dist` is the equirectangular approximation already precedented inline at 0110:92-106 —
no PostGIS (`0001:4` installs pgcrypto only), correct to well under a band width at district
scale. **A NULL coordinate is an explicit gate, not a silent empty** (round-1 F11): the Mode C
door requires the chosen pickup address to be PINNED (`lat/lng` present) and says so
(「자동 연결하려면 주소 핀을 먼저 찍어주세요」 + the pin flow) — an un-pinned owner is told the
one performable remedy, never shown a fabricated "no runners". A genuinely empty eligible set
gets the honest sentence (「지금 연결할 수 있는 크루 러너가 없어요」) and the Mode B list.

**Missing-column work list (S6):** `runners.home_address_id` (+ onboarding surface) + the
input CHECKs above · `session_runner_assignments.committed_at` (rank tiebreak 4) ·
`club_sessions.start_lat/lng` or a geocoded meetup point (`meetup_point` is free text,
0030:57; `routes.anchor_lat/lng` exist but are marked do-not-consume until founder-walk GPS,
0078:23-24 — the spec does NOT lean on them) · the 0073 pinned-address repair as a
dependency.

**Counsel rider**: Mode C ships behind the intermediary-status brief (Sean's accepted rider).
S6 is sequenced last for exactly this reason (§12).

### 6.6 The host's residual matching role: recovery only (🔵 — and 🔴 14.10)

When a pick lapses inside T−2h, or a pairing dissolves at the meetup (revoke, decline,
no-show), someone must cover NOW. This spec proposes the host regains the propose pen **only
inside the old window [T−2h, T+6h]** and only for dogs at P2 — `session_propose_dog` survives
with its gate narrowed to that recovery window. Board copy names it 재배정, distinct from
picks. This is a 🔵 proposal wearing a 🔴 (14.10): Sean's words were "replace" and "instead of
the host", and a recovery window is a residue of the replaced thing — he may prefer owner-only
re-picks with no host pen at all. The kill-criterion fallback (§12) is likewise HIS choice,
not this spec's default.

---

## 7. Custody — door to door

### 7.1 The pickup leg (P5): the booking stays `confirmed`; the stamps are new and club-owned (round-1 F3)

The marketplace's `runner_enroute` status is NOT reused. Routing P5 through it would (a) strand
the pairing outside every club money predicate — the no-show WHERE and `_club_refund_confirmed`
both select `status='confirmed'` (0118:1156-1162, 0118:945-954), so an owner no-show at the door would be
neither charged nor refunded; (b) kill the owner's cancel with a false `already_handed_off`
(0118:1037) — the exact un-priced en-route hole `cancel_owner.ts:50-55` already documents; and
(c) collide with `enroute`'s own 24h wall (index.ts:242-245). And NOT routing through it while
still leaning on `bookings.arrived_at` would leave the arrival term with no producer — its CAS
matches zero rows at `confirmed` (measured, 0118:1189-1190).

So P5 is club-owned: **the booking holds at `confirmed` until the door both-stamp**, and the
leg's telemetry lives on `session_dogs` — four new server-stamped columns
(`pickup_departed_at`, `pickup_arrived_at`, `return_departed_at`, `return_arrived_at`), written
by a club edge action under service_role (the 0083 protected-columns law; client writes
refused). Consequences, each deliberate:
- Every shipped `confirmed`-keyed predicate — the §5.2 ladder, the refund arm, the no-show
  WHERE — stays correct without edits to its status set.
- The owner's cancel stays alive until custody actually transfers (§5.3's P5/P6 row).
- `bookings.arrived_at` is untouched, so 0119's `bookings_dangerous_dog_move` trigger
  (which fires on `arrived_at` changes, 0119:400) never sees the return leg — the
  mid-run-declaration trap 0119 was built to avoid (0119:419-426) cannot re-arm (round-1 F14).
  The `session_dogs` UPDATE trigger is also stamp-safe by construction: it requires
  `custody`/`dog_id` to have MOVED (0119:430-433), and stamp writes move neither.
- On pairing, the runner sees the pickup brief (§8's disclosure schedule), the pickup window
  (🔵 stated in copy from `scheduled_at` minus route travel, not a new negotiation machine),
  the dog card, and the honest-transit sentence (rider: until insurance signs, the copy states
  plainly that the transit leg is runner-responsibility, insured status shown as it is).

### 7.2 Per-pairing pickup mode (🔵) — the attending-owner scenario, solved where it lives

C7's missing scenario (a Mode B owner who attends — in a Banpo pilot the most likely case)
is not an edge: it's a per-pairing choice. At P2 the owner picks **집 픽업** (default; the flow
above) or **현장 인계** (owner brings the dog to the start and both-stamps there — today's
shipped chain, byte-identical). Return mirrors pickup (집 반환 / 현장 반환, same flag). One
column on the pairing (`pickup_mode`), zero new custody mechanics for the 현장 arm, and the
"pointless return trip to an empty home" the review flagged becomes unconstructable. 맹견 gate,
ladder, and finish logic are pickup-mode-blind. 🔴 §14.2 for Sean's nod since it reshapes his
"the runner should pick them up" default into a default-plus-option.

### 7.3 Transit is inside the run's custody — stated, with its evidence gap named

From the door both-stamp (P6) the dog is in the runner's custody (`custodian_type='runner'`,
0045:44-53 — the trigger doesn't care where the stamps happened). There is no between-legs
machine: a dog picked up that never arrives at start is a P6 pairing whose P7 event is overdue —
host-visible board state (지각/미도착), and the host's force-resolve already admits `picked_up`
(0070:208), so the tool covers the transit leg by construction. **The evidence does not**
(round-1 F15): `runs` and `dog_run_segments` exist only from `club_start_delegated_runs`
(0050:180-190), so the transit legs carry no GPS trace and `club_incident_settle_quote`'s
`measured_km` cannot see them (0116:413-420). v2 accepts this gap for the pilot and says so —
transit incidents are adjudicated on stamps, the case's own evidence uploads, and human
judgment; a transit trace is named future work, not silently implied. SOS/case entry is
available to the runner from pairing onward, not only during the run (0067's gates admit a
runner who holds a dog; the run screen's entry point extends to the transit surface, §10.3).

### 7.4 Arrival-at-start, and the re-anchored no-show money (C1) — every term with a producer

**The broken thing**: under home pickup every delegated owner produces
`owner_confirmed_handoff_at` at their own door hours before the session — the exact signal the
0118 attendance gate reads (0118:1246-1250) — so the 20% rung would become structurally
unreachable: the third inertness of that gate, this time by design.

**The new predicate set** (per-pairing, all server-stamped, each term's producer named):

- **Dog-at-start (the positive fact)**: the runner's `session_checkin` at the start stamps
  `session_dogs.checked_in_at` for every dog they hold (`responsible_profile_id = auth.uid()`,
  0030:259 — the mechanism EXISTS; what moves is that the custody trigger's premature
  `checked_in_at = coalesce(...)` stamp at `picked_up` (0045:53) is REMOVED for door-mode
  pairings, because at the door that stamp would mean "at the owner's home" — the C1 bug
  wearing a new column). 현장 인계 pairings keep today's semantics untouched. One named
  consequence: the recap counter `v_dogs` reads `checked_in_at` (0118:1133-1134) and its
  meaning sharpens from "handed off" to "was at the start" — correct for a recap, noted for
  the pin.
- **Owner no-show (the chargeable fact), 집 픽업 arm**: runner arrived at the door
  (`pickup_arrived_at` present — producer: the §7.1 edge action, **proximity-verified**: the
  stamp is accepted only with a client-reported location within ~150m of the pinned pickup
  address, checked server-side against `addresses.lat/lng`; an un-pinned address therefore
  can never produce arrival evidence, so a no-show charge is impossible against it — stated,
  not silent) AND no handoff occurred (both handoff stamps null) AND the pairing was live at
  `scheduled_at`. A bare self-attested tap is NOT accepted as evidence for a 20% charge
  (round-2 F2) — and the charge fires only at the host's confirmation tap, whose evidence
  view (§10.2) shows every no-show candidate first; the owner's dispute rail is the incident
  machinery.
- **Owner no-show, 현장 인계 arm** (round-2 F1b — the first draft's predicate demanded a door
  stamp this mode never produces): 현장 pairings keep TODAY'S shipped evidence semantics
  byte-identical — no `session_dogs.checked_in_at` and no handoff stamps at confirmation time
  (0118:1246-1250's own shape) — which is correct there because the handoff point IS the
  start.
- **Runner no-show at the door**: `pickup_arrived_at` absent at `scheduled_at` → pairing
  dissolves at host confirmation into the refund arm (owner charged nothing), runner strike
  via `assignment_events` (0057:174), policy numbers Sean's.
- **Stamp lifecycle (round-2 F2)**: the four §7.1 stamps are CLEARED by every
  pairing-dissolution path — they join the handoff stamps in the eraser set
  (0118:1207-1216's six paths, plus §6.2's widened revokes), each clearing pinned. The first
  draft claimed "a reassignment creates a pairing whose stamps start null" — false as
  written: dissolution reuses the same `session_dogs` row (0057:132-136 clears only the
  handoff stamps), so without explicit clearing a replaced runner's stale arrival would
  charge an owner for a successor runner who never appeared. The clearing IS the fix.
- **Suite consequence, same slice**: 153's P4/P9/P10/P12 re-pin to the new predicate; each
  re-pinned pin names its successor in a comment (the suite-updates-in-slice law).

The pairing-scope lesson is honored: all facts are per-pairing, and dissolution clears them
(above) so demotion to P2 re-derives the money rung cleanly (§5.2). The one thing per-pairing
keying cannot express —
"this OWNER attended, durably" — is Sean's open Custody A/B decision and is deliberately NOT
smuggled in here; if he picks B, the durable column lands in S4 alongside this predicate.

### 7.5 Two-phase finish (Sean's run-end flow) — the ordering inversion, with its population and idempotency pinned (round-1 F6)

Today: settle → `return_pending` immediately (0045:55-59) → both-stamp return →
`club_finish_session` LAST (blocked until all returns resolve, 0045:328 → 0118:1121).
Sean's flow: per-runner finish → **host final confirmation** → THEN the return legs → release.

v2's mapping — three changes, everything else untouched:

1. **`custody_phase` gains `finished_pending_host`** (CHECK extension; the dead
   `outbound_pending` value — 0040:48/0045:20 domain, zero writers anywhere — is retired in
   the same breath). The custody trigger's `completed` arm writes it instead of
   `return_pending`; `payout_state → earned` unchanged (runner money at settle is already the
   shipped truth, 0083:677-688).
2. **`club_confirm_run_end(p_session)`** — NEW. Caller: `host_profile_id` (backup admission
   is 🔴 14.5, and it is a MONEY question, not a permission one — see below). Gates, exact:
   `run_confirmed_at is null` (**the idempotency guard** — a second tap raises
   `already_confirmed`; without this the host-fee insert and recap blast, which today dedupe
   on the status flip at 0118:1119/1129, would double-fire) · `now() ≥ scheduled_at` (strict,
   the ruled time gate) · **no pairing still out running or unsettled** — precisely: no live
   booking at `picked_up` or `active` (a dog on the course or unreturned-to-the-flow blocks
   confirmation; the host's tools for a stuck one are force-resolve/override, §7.6).
   Pairings at `confirmed`/`matching` — never handed off — do NOT block: they ARE the money
   block's population (round-1 F6a): the §7.4 no-show fees and the never-picked-up refunds
   fire here, exactly the money that today lives in `club_finish_session` (0118:1149-1264),
   moved whole: recap post, `_club_refund_bookings`, no-show WHERE (with §7.4's evidence
   set), `_club_refund_confirmed`, host fee. **The host fee's recipient becomes
   `s.host_profile_id`, never `auth.uid()`** (0118:1261's `auth.uid()` is safe only while the
   caller is provably the host; the moment 14.5 admits the backup, `auth.uid()` would route
   the session's host fee to whoever tapped — a money-routing change masquerading as a
   permission toggle). Then: stamps `run_confirmed_at` and flips every `finished_pending_host`
   pairing to `return_pending` — the return legs begin, per Sean.
   Mode A pairings are untouched by all of it: released at their own finish, structurally
   (§4.3).
3. **`club_finish_session` becomes the closer**: requires `run_confirmed_at` present +
   `_club_dogs_unresolved = 0` (the predicate is UNCHANGED, 0045:328 —
   `finished_pending_host` joins its unresolved list) + the incident-ownership gate
   (0118:1122) — and now only flips `status='done'`. Money has already moved at confirmation;
   release still waits on `resolved` per pairing (C6 unchanged). 🔵 auto-close when the last
   pairing resolves and both gates pass; the host CAN still close manually.

The load-bearing ordering invariants, preserved and named: runner-paid-at-settle precedes
return (shipped, 0083:677-688) · `payable` requires `resolved` on the normal path
(0070:369-375) with the one shipped exception — an incident SETTLEMENT may set `payable` and
release without custody resolution (0072:187-190, 0072:232-244), human judgment substituting
for the custody question · `released` requires no open incident (0072:227-245) · chat/phone
lifetime keys on unresolved custody and
therefore correctly survives through the return legs (0049:36-43, 0049:174-180 — verified,
both key on `<> 'resolved'`).

### 7.6 `finished_pending_host` ships ESCAPABLE, or it does not ship (round-1 F2)

The first draft left this state with a 🔴 ceiling and a claimed fallback; the blind review
proved the fallback does not exist — every shipped exit refuses the state (force-resolve
requires `picked_up|active`, 0070:208 · override and confirm-return require `return_pending`,
0070:257/0045:79 · transfer requires `with_custodian|return_pending`, 0045:180-184 · the stale
sweep only touches `matching`, 0070:316 · release requires `resolved`, 0072:235), the
return-delay alarm goes structurally silent (it keys on `return_pending`, 0068:103), and
`delete_account` blocks on `checked_out_at` for BOTH parties indefinitely (0115:358-364,
0115:391-395 — the file's own comment cites the 5.1.1(v) unreasonable-obstacle clause). A dog
in a stranger's custody, phone numbers mutually visible (0049:175), and no tool, alarm, or
sweep — hanging on one human tap. Unshippable.

S5 therefore lands with three UNCONDITIONAL mechanical escapes (not policy, not timers):

1. `session_host_force_resolve` admits `finished_pending_host` (its job — "this pairing is
   stuck, open a case, custody question to humans" — is exactly right here; one line in its
   status set, its own pin).
2. `session_transfer_initiate` admits `finished_pending_host` for the clinic/authority arm —
   a runner holding a dog that needs a vet between last settle and the host's tap must not be
   phase-blocked (0045:7-9's return-phase-only rule extends to this phase, which is
   return-adjacent by construction; its own pin).
3. The return-delay alarm gains an arm: `finished_pending_host` older than 6h since that
   pairing's settle (`bookings.updated_at` at `completed`, or the run's `ended_at`) fires the
   same host-nagging notification — the alarm that today catches a stalled return also
   catches a stalled confirmation. (Its §13 C7 row is corrected accordingly — the first
   draft's re-anchor to `run_confirmed_at+6h` was itself the silent-alarm bug.)

The auto-confirm ceiling (system performs the confirmation after N hours, money moves on a
timer toward paying completed work) remains 🔴 14.3 — but it is now a POLICY question layered
on an already-safe machine, and **S5 is hard-gated on Sean answering it** either way: with the
ceiling (his N) or explicitly without it (host-tap-or-alarm indefinitely, escapes above
covering the dog). No un-escapable state ships under either answer.

---

## 8. The club address slice — NEW security surface, owning its disclosure window (C3, round-1 F4)

Verified: no club code path touches `addresses` today — club bookings mint with `address_id`
NULL (0081:184-197 column list), and the only booking→address read in the schema is
`booking_pickup_address` (0060/0065). The slice:

1. **Owner picks a pickup address at P2** (pay time — the moment the seat becomes real):
   `session_pay_delegation` gains `p_address_id`, validated owner-owns-address, written to the
   minted booking (signature change → `api.ts` + `check-rpc-contracts` in the same slice).
   현장 인계 pairings (§7.2) pass null and never enter the address surface.
2. **The disclosure schedule is a DECISION, and here it is** (the first draft's "existing
   gate, unchanged" hid it): the shipped gate releases the address to the assigned runner at
   `confirmed` only inside T−24h (0065:49-56), and that bound is not incidental — the
   unconditional-`runner_enroute` branch was already exploited once to open an address 30
   days early and was closed with a time gate (index.ts:238-241). v2 KEEPS the shipped
   schedule byte-identical: **full address at T−24h; at pairing the runner sees the area band
   only** (동 label — 「반포동 픽업」), which is what pickup planning actually needs days out.
   §10.3's P4 row says exactly this. No widening, no new branch, zero new disclosure logic —
   now true because the schedule is the design, not a side effect.
3. **No access log in this slice** (the first draft said "unchanged gate" AND "add logging" —
   contradictory: `booking_pickup_address` is STABLE, and 0060:52-53 records that making it
   volatile-with-log is an open Sean judgment). v2 keeps STABLE/no-log and points at 0060's
   standing question rather than half-deciding it.
4. **Board/board-adjacent surfaces NEVER carry addresses** (§9 privacy row); the area band is
   runner-facing pick/pairing surfaces only.
5. Adversarial cycle mandatory (0116 §D party-gate law; 0088 whole-request-403 hazard on any
   grant move). This is S4's server half and does not land without its pins.

---

## 9. The board — a NEW sanitized member projection (C8), with its readership stated honestly

Today's `club_delegation_board` serves the OPERATIONAL views (owner/runner/host) and its grades
are correct for them (0052:149 wrapper + 0053:227 impl). What Sean asked for — *"all this
process can be shown in the club public home"* — is a different reader: the club member.
Verified: members-without-party get empty `runners`/`dogs` arrays (grade filters 0053:252/268
and 0053:334-336), `owner_handled` dogs appear nowhere (0053:330), and
`club_overview`/`club_session_detail` carry no per-dog state at all.

**NEW `club_session_board(p_session)`** — nominal gate: `club_members` row or shell ≠ none.
**Stated plainly (round-1 F9): that gate is one self-serve tap from public.** `club_join` is
unconditional for any signed-in user (0048:197-216, no approval, no host gate;
`session_runner_commit` also auto-inserts membership, 0043:246-247). So this projection is,
in practice, readable by any authenticated user who joins the club — and it renders a live
"this named person's dog is currently out with a runner" feed. Sean's words do put this on the
club public home, so the intent is ruled — but the reader class is his to see: 🔴 14.9 asks
whether the pilot accepts effectively-public (recommended for Banpo scale, where the club IS
the neighborhood) or wants a real membership gate first (host-approved joins — a new
mechanism, not in this spec's slices).

Returns, per live pairing and per 동반 dog: dog first name + photo · owner display name ·
state label from the P-ladder (대기 중 → 러너 선택 중 → 수락 대기 → {runner}와 페어링 →
픽업 이동 중 → 이동 중 → 도착 → 러닝 중 → 러닝 완료 → 귀가 중 → 귀가 완료) · 동반 rows
(보호자 동반) · companion crew rows (이름 + 함께 달려요). Plus the session header facts already
public via `club_session_detail`.

**Privacy rows (each verified against a shipped precedent):** no addresses ever (§8.4); the
area band is not on the board · no money — fares appear ONLY on the consent screen (Sean's
ruling ④ — header law `delegate/[sid].tsx:20-27`, rendered fare `:201-237`) · pick-pending runner names render to the CHOOSER and
the picked runner only (the 0053:315-323 sub-gate's logic, inverted for the new chooser: in
Mode B the owner authored the pick and sees it; other members see 수락 대기 with no name until
P4 makes the pairing public — Sean's board shows pairs, not courtships) · a 맹견-refused or
lapsed pick is indistinguishable from a declined one to non-owners (0119 disclosure edge,
carried from v1) · phone/emergency data stays roster-gated (0049) — the board never joins it.

The operational board grows the new state columns (`pickup_mode`, the §7.1 stamps,
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
| P2 결제 완료 — 러너 선택 | ● NEW pick surface: committed-runner list (name, tier, pace fit, load/cap — **never money, never distance**: round-2 F7c's triangulation oracle) + 자동 연결 door (Mode C; requires pinned address, §6.5) | pick (B) · auto-pick (C) · cancel (ladder-quoted first, §5.4) |
| P3 수락 대기 | ● pick-pending card + TTL ring (DrainRing idiom) | withdraw pick (free — §6.2's widened revoke) · cancel (quoted) |
| P4 페어링 확정 | ● paired card: runner name/photo, pickup window, pickup mode | cancel (quoted — free ≥24h per §5.2) · objection (re-specified, §5.5) |
| P5 픽업 이동 중 | ○ runner en-route + arrival state (§7.1 stamps) | cancel still available until the door both-stamp (§5.3) · chat |
| P6 인계 | ● both-stamp door handoff (exists: `confirmHandoff(...,'owner')`, `:341` — re-copy for the door) | confirm handoff |
| P7-P8 이동/러닝 | ○ timeline states + live | open case (party standing unchanged) |
| P9 러닝 완료 | ○ "러닝 완료 — 호스트 확인 대기" | — |
| P10 귀가 중 | ● return-pending card | confirm return (exists, `:359`) |
| P11-P12 종료 | ● receipt door (`club/receipt/[bid].tsx` — unchanged, T②+T① carousel as landed) | share nudges (as landed) |

Mode A owner: unchanged surfaces (`session_rsvp`/pass/check-in); board shows them 보호자 동반.
Copy honesty rows: transit sentence until insurance (rider) · mode-switch-after-pay states the
fee (§5.3) · a failed quote blocks the cancel confirm (§5.4) · the shipped 「담당 러너는
집결지에서 배정돼요」 pay copy (0081:222) and 「집결지에서 인계를 확인하세요」 accept copy
(0057:140) are FALSE under v2 and re-write in the same client slice (§13 copy rows).

### 10.2 Host — `club/console/[sid].tsx` respec (693 lines today)

KEEPS: admission queue (approve/reject — `doApprove`, `:138`) · materiality re-review
(`doReview`, `:154`) · cases section (assign/resolve, `:512-541`) · force-resolve + custody
override with the self-override dead-button logic (`:216-226`) and the §7.6-widened phases ·
session cancel (`:268`).
LOSES: the runner-chip propose grid (`:440-461`) as the PRIMARY flow — it narrows to the §6.6
recovery window and renames 재배정, appearing only when a P2 dog exists inside T−2h.
GAINS: ● the run-end confirmation (§7.5) — one button, enabled when no pairing is still out
(picked_up/active), with the blocker rendering server-classified (§9 kills the duplicated
predicate); its evidence view shows the §7.4 arrival/no-show flags per pairing so the host
sees exactly what money will move BEFORE tapping · a pairs timeline (watch, not choose).
Backup host: same console minus the arms the server refuses them — which arms those are is
🔴 14.5, now including the host-fee routing consequence (§7.5.2).

### 10.3 Runner — `club/session/[sid].tsx` (runner cards) + `club/run/[sid].tsx` respec (Sean's "R" question)

| State | Runner sees | Runner can do |
|---|---|---|
| committed, no pick | ○ my cap/load, session card | withdraw commit (blocked by live charges — unchanged, 0043:421) |
| P3 pick inbox | ● pick card: dog profile (0119 tokens render here — landed wiring), owner first name, pickup mode + **area band** (NOT the address — §8.2), **expected net (contract §5)**, pace fit | accept / decline (+reason) — unchanged RPC |
| P4 paired | ● pickup brief: area band; **full address unlocks at T−24h** (§8.2), window, dog card | self-exit (§6.2, strike-tracked) · 출발 → 도착 (§7.1 stamps) |
| P6 door | ● both-stamp handoff | confirm handoff |
| P7 at start | ● start check-in (stamps held dogs — §7.4) | check in |
| P8 running | ● run console (trace, photos nudge as landed, **SOS per-dog entry preserved verbatim** — `run/[sid].tsx:285-309`, C2/C11) | finish per dog (settle — exists, `:264-270`) |
| P9 finished | ○ "호스트 확인 대기 — 귀가 대기" (+ §7.6's vet-transfer door if needed) | transfer (emergency) |
| P10 returning | ● return leg per dog: address, 도착 stamp + both-stamp return | confirm return |
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
| `session_propose_dog` host-primary role | gate NARROWS to the §6.6 recovery window (create or replace; same name — the referencing suites keep resolving) — 🔴 14.10 owns whether even that survives | window pins re-pinned in-slice |
| `session_assign_dog` | already an alias (0047:143) — revoke `authenticated` EXECUTE + refusal pin; `api.ts:3614` call site deleted (its one consumer is `dev/club-lab.tsx:16`) | 1 refusal pin |
| `session_proposal_revoke` | gate WIDENS: host OR the live pick's author-owner (§6.2) | gate pins both ways |
| `session_assignment_revoke` | gate WIDENS: host OR the assigned runner (self-exit, §6.2) | gate pins both ways |
| `session_reconsider_dog`, `session_review_dog` | KEPT (admission family, §4.2) — v1 wrongly listed review for retirement | — |
| `session_proposal_respond`, `session_owner_objection` | KEPT — the accept/objection rails the pick layer rides | gate-delta pins only |
| Console propose grid (client) | removed outside recovery window | — |

Suite 154 (0119) note, corrected from the first draft: **G4 drives `session_delegate_dog`
(154:389), which survives untouched — no G4 re-target is needed**; the first draft's contrary
claim mis-attributed a note to the 0119 REGISTRY row that does not exist there. What 154 DOES
need at S4 is a stamp-columns awareness check only if its fixtures assert `session_dogs`
column sets — verified at write time by the S4 author.

Nothing is DROPped; every EXECUTE revoke ships with the pin that proves the refusal (house
closure doctrine). Each landed suite whose pinned behaviour legitimately moves is updated in
the same slice with a WHY comment naming the successor pin.

---

## 12. Sequencing — slices, in dependency order

| Slice | Contents | Gated on |
|---|---|---|
| S1 | Runner-money strip (independent, claimed by announcer v5, contract @ f6ed2cf on its branch) | — (in flight) |
| S2 | §9 member board projection (+ 🔴 14.9 readership word) + operational-board state columns + the console-predicate de-duplication | spec review + Sean's read |
| S3 | Pick layer (§6.1-6.4): `session_pick_runner`, self-pick refusals, gate moves + the two widenings, TTL, deprecations §11, §5.2 rung reorder (🔴 14.11) + 153 ladder re-pins, viability re-read (§13) | S2 (board renders picks); 🔴 14.1, 14.10, 14.11 |
| S4 | Door custody (§7.1-7.4): the four stamps + club edge action, address slice (§8), no-show re-anchor + 153 P4/P9/P10/P12 re-pins, copy-drift rows (§13), client legs | S3; riders (honest transit copy); 🔴 14.2 |
| S5 | Two-phase finish (§7.5): `finished_pending_host` + the three §7.6 escapes, `club_confirm_run_end`, closer split, console respec | S4; **hard-gated on 🔴 14.3** (ceiling yes-with-N or explicitly no); 🔴 14.5 |
| S6 | Mode C (§6.5): columns + CHECK bounds, ranking definer, `session_auto_pick`, onboarding surface, pinned-address door | S3; **counsel brief answered** (rider); 🔴 14.4 |

Every S2-S6 migration: adversarial cycle (0059 doctrine), numbers two-sided from the remote tip
at write time, REGISTRY row in the same push, suites updated in-slice. Client halves land
atomically with any grant move (0088 law); no binary reaches a device before its `db push`
(the 0119 deploy-order law, now standing).

Kill criterion (review #2's shape; Sean accepted the shape, the numbers and the fallback are
his): if no club session with ≥2 delegated dogs runs within N weeks of S3 landing, S4-S6
shelve — and what matching remains (owner-picks with scene handoff, or restored host matching)
is 🔴 14.7's second half, not this spec's default.

---

## 13. Consumer-by-consumer migration table (C10) — every reader AND writer of pairing/custody/finish order

Classes: **U** unchanged · **RA** re-anchored (same logic, new event/caller) · **RW** rewritten
· **N** new.

| # | Consumer | Reads/writes | v2 | Class |
|---|---|---|---|---|
| C1 | `_club_dogs_unresolved` 0045:328 | unresolved custody phases | predicate + `finished_pending_host` in its list; now gates the CLOSER | RA (S5) |
| C2 | `club_finish_session` 0118:1102 | C1 + incident ownership + money block | SPLIT: money+recap → `club_confirm_run_end` (idempotent via `run_confirmed_at`, host-fee recipient = `host_profile_id`); close → thin closer | RW (S5) |
| C3 | custody trigger `_club_custody_transition_v2` 0045:34 | booking status picked_up/completed | picked_up arm: unchanged mechanics, fires at door; drops the premature `checked_in_at` stamp for door-mode (§7.4); completed arm writes `finished_pending_host` | RW (S4+S5) |
| C4 | `session_confirm_return` 0069:84 | `return_pending` | untouched | U |
| C5 | `_club_finalize_return` 0070:343 | both stamps, weaker-kind record | untouched | U |
| C6 | `club_release_payouts` 0072:221 | payable + no hold + (`resolved` **OR an `incident_settlement` fee item** — 0072:232-244, round-2 F6) + no open incident | untouched — release keys on resolved-or-adjudicated, not on finish; the incident arm deliberately lets a human settlement release money while custody is still unresolved, and that remains true for `finished_pending_host` | U |
| C7 | return-delay alarm 0068:96-121 | `return_pending` + `scheduled_at`+6h | gains the `finished_pending_host`-age arm (§7.6.3); its `return_pending` arm re-bases on `run_confirmed_at` so returns aren't "late" before they can begin | RW (S5) |
| C8 | `club_stale_delegation_sweep` 0070:302 | stale open sessions, `matching` bookings | untouched (it is the no-host-ever recovery for un-picked seats; it never covered `completed` — §7.6's escapes do) | U |
| C9-C11 | incident settle/quote/resolve 0080:977, 0116:413, 0072:260 | incident_review, stamps, settlement items | untouched; quote's `took_custody` reads handoff stamps which exist in both pickup modes (0116:420) | U |
| C12 | `club_incident_open` 0070:393 | party + payout holds | untouched | U |
| C13 | `session_host_force_resolve` 0070:171 | `picked_up|active` | **admits `finished_pending_host`** (§7.6.1) | RA (S5) |
| C14 | `session_custody_override` 0070:243 | `return_pending` | untouched | U |
| C15 | console client predicate `console/[sid].tsx:202-206` | client copy of C1 | RETIRED — server classification via board (§9) | RW (S2/S5) |
| C16 | `club_dog_ui_state` 0116:552 | axes → stage | new stages (P5/P7/P9/P10 labels); party gate byte-identical | RW (S2) |
| C17 | board impl 0053:227 | projection | + state columns/load; member projection is NEW beside it | RW+N (S2) |
| C18 | `_club_compute_axes` 0048:687 | booking status, custody events, cancel_reason | derives the new states; the `club_not_picked_up→no_show_owner` unconditional label (0048:748 — wrong for the refunded runnerless arm) is corrected while the function is open | RW (S4) |
| C19 | chat lifetime `_club_chat_writable` 0049:29 | done + unresolved custody | untouched — verified the predicate survives returns-after-done (0049:40) | U |
| C20 | phone lifetime `_club_phone_visible` 0049:167 | unresolved custody (0049:175) | untouched — and §7.6's escapability is what keeps its lifetime bounded | U |
| C21 | `_club_incident_can_open` 0067:68 | shell/owner/held-runner | untouched | U |
| C22 | `delete_account` arms 10/11 0115:358-394 | `checked_out_at is null` | untouched — bounded again by §7.6's escapability | U |
| C23 | `session_cancel_delegation` 0118:989 | rung order + matching/confirmed boundary | **RW — §5.2's rung reorder**; the `already_handed_off` wall is unchanged and correct because P5 keeps `confirmed` (§7.1) | RW (S3) |
| C24 | `cancel_owner.ts:57` 409 | club exclusion | untouched | U |
| C25 | settle-run reasons | `incident` ownership | untouched | U |
| C26 | materiality trigger 0048:222 | booking status; stamp eraser | untouched; its stamp erasure is money-safe under §7.4's per-pairing predicates | U |
| C27 | `session_review_dog` reject arm 0048:278 | refunds `matching` only | KEPT; the confirmed-not-refunded quirk is pre-existing, now NAMED — 🔴 14.8 one-word fix rider | U (flagged) |
| C28 | 0119 gates 0119:250-433 | custody-bound writes | ZERO changes — held true BY §7.1's design: no `bookings.arrived_at` reuse (the `_move` trigger fires on it, 0119:400), stamps live on `session_dogs` where the UPDATE trigger requires custody/dog_id movement (0119:430-433). Suite 154 needs no G4 re-target (§11) | U |
| C29 | **`session_transfer_initiate/accept/cancel`** 0057:304, 0058:104, 0058:208 | `with_custodian|return_pending` / `transfer_pending` | initiate **admits `finished_pending_host`** for clinic/authority (§7.6.2); accept/cancel restore-phase logic gains the same value in its restore map | RA (S5) |
| C30 | **`transition-booking/index.ts`** (edge) | WRITER of handoff stamps (:313-315), the both-stamp→`picked_up` flip (:320-322), `arrived_at`+enroute (:236-283 — NOT reused by club, §7.1) | `confirm_handoff` serves the door unchanged (it never cared where); its 「러너가 곧 러닝을 시작해요」 copy (:324) re-writes for the door context; the club 출발/도착 stamps are a NEW club edge action beside it | RA (S4) |
| C31 | **`settle-run` edge + `settle_run_tx`** 0083:628 | producer of `completed` | untouched — its output transition is re-interpreted by C3, not by it | U |
| C32 | **`create-booking-hold`** (edge) | marketplace mint; 0119 writer inventory | untouched — club mints via `session_pay_delegation` | U |
| C33 | `session_pay_delegation` 0081:122 | mint | +`p_address_id`, +`pickup_mode` (§7.2, §8.1) — signature change rides `api.ts` + `check-rpc-contracts` in-slice | RW (S4) |
| C34 | viability `club_session_viability` 0048:354-388 | headroom over CHECKED-IN runners | headroom re-reads over PAIRED runners pre-session (checked-in is too late once pairing precedes the meetup) | RA (S3) |
| C35 | `session_checkin` 0030:245 | window + session_people + held-dog stamp | untouched for people; its dog-stamp clause becomes §7.4's positive predicate | RA (S4) |
| C36 | 0118 no-show WHERE 0118:1157-1250 | confirmed+runner+time+attendance | attendance evidence set replaced (§7.4); moves into `club_confirm_run_end` | RW (S4+S5) |
| — | **Copy-drift work list** (client + notification strings that state the OLD flow, each re-written in its slice): 0081:222 「집결지에서 배정」 · 0057:140 「집결지에서 인계」 · 0048:511 「5분 안에」 (+0084:603-607's warning that suites assert club titles verbatim — re-pin with the copy) · index.ts:324 「곧 러닝을 시작해요」 · 0118:1133-1134 recap `v_dogs` meaning note (§7.4) | | | (S3-S5) |

---

## 14. 🔴 Open with Sean (everything in one place, one word each where possible)

1. **Pick TTL** — 2h with lapse-back proposed (§6.3). · 「2시간」 / your number
2. **Per-pairing pickup mode** {집 픽업 default, 현장 인계 option} (§7.2) — solves the
   attending-owner case; reshapes "the runner should pick them up" into default-plus-option.
   · 「좋아」 / 「집 픽업만」
3. **Host-never-confirms ceiling** (§7.6) — the machine ships escapable either way; this is
   the POLICY: after N hours the system confirms and money moves toward paying completed
   work, or no timer ever and the alarm nags forever. **S5 waits on this word.**
   · 「N시간으로」 / 「타이머 없이」
4. **Owner distance preference in Mode C** — skip in pilot (vacuous: run distance is
   route-fixed; only the pickup leg remains) or store a field now (§6.5). · 「스킵」 / 「필드로」
5. **Backup host and run-end confirmation** — NOTE this is money routing, not just
   permissions: the host fee routes to `host_profile_id` regardless of who taps (§7.5.2), and
   today's asymmetry is wider than one function (backup may force-resolve, 0070:195-196, but
   not finish, and custody-override is host-only, 0070:254). · 「백업도 확인 가능」 / 「호스트만」
6. **Non-runner companions** — runner-tier only proposed (§4.4); guests remain plain RSVPs.
   · 「러너만」 / 「게스트도 크루로」
7. **Kill criterion** — N weeks without a ≥2-delegated-dog session after S3 → S4-S6 shelve;
   AND the fallback state (owner-picks-with-scene-handoff vs restored host matching) is yours
   (§12). · N = ? · fallback = ?
8. **C27 quirk** — a `confirmed` booking rejected at materiality re-review is not refunded by
   that arm (0048:278 filters `matching`). Pre-existing; fix in S4 or leave documented.
   · 「고쳐」 / 「그대로」
9. **Board readership** (§9) — `club_join` is one unconditional tap, so the member board is
   effectively public-to-any-signed-in-user. Accept for the pilot (recommended — the club IS
   the neighborhood at Banpo scale) or gate membership first (new mechanism, delays S2).
   · 「공개 수용」 / 「가입 승인제부터」
10. **The host recovery window** (§6.6) — your "replace" vs a T−2h recovery pen for lapsed
    picks. · 「회수 창 좋아」 / 「호스트 펜 완전 제거」
11. **The ladder rung reorder** (§5.2) — free-≥24h checked first, pairing-blind; keeps your
    free-24h ruling true once pairing moves early. The alternative (state-anchored 20%
    whenever paired) reprices early cancels and contradicts 0118:210. · 「재정렬 좋아」 /
    「페어링되면 20%」
12. Standing, unchanged by this spec: the club 9,900-vs-7,900 base gap (memo ④) · 맹견
    refused-vs-conditions · breed-alias scope · the Custody A/B durable-attendance decision
    (§7.4 interlocks with it) · counsel briefs (S6's gate) · 0060's address-log judgment
    (§8.3).

---

## 15. Review log

**Round 1 — blind Claude voice, 2026-08-25** (given the scout facts and Sean's verbatim
rulings; not shown the author's reasoning). Verdict on draft 1: RETHINK, 15 findings.
Disposition: F1 → §5.2 rung hoist + 🔴 14.11 · F2 → §7.6 rebuilt (three unconditional escapes;
S5 hard-gated on 14.3; the false "shipped fallback" claim retracted) · F3 → §7.1 rebuilt
(booking holds `confirmed`; four club-owned `session_dogs` stamps; no `runner_enroute`, no
`arrived_at` reuse) · F4 → §8.2/8.3 rebuilt (T−24h schedule owned as the decision; area band
at pairing; log contradiction dropped) · F5 → §6.1 self-pick refusals; self-proposal arm
excluded from owner picks · F6 → §7.5.2 population disambiguated, idempotency guard, host-fee
recipient pinned to `host_profile_id` · F7 → C29 added; transfer admits the new phase · F8 →
C30-C36 + copy-drift list added · F9 → §9 readership stated; 🔴 14.9 · F10 → §6.2 gate
widenings (owner pick-revoke, runner self-exit) · F11 → §6.5 CHECK bounds + pinned-address
door + gaming note · F12 → §6.6 marked 🔵+🔴 14.10; kill fallback moved to 14.7 · F13 → the
fabricated G4/0119-row attribution removed; corrected in §11 · F14 → dissolved by F3's design
(named in C28) · F15 → §7.3 evidence gap stated. Citation audit: all 16 flagged cites
corrected in place (line-number fixes; the runner-money contract and 0117 facts now cited as
on-branch, not trunk; 0117 then LANDED and DEPLOYED mid-drafting and its cites were refreshed
to trunk facts — the runner-money contract remains on its branch).

**Round 2 — blind codex voice (gpt-5.6-sol, read-only sandbox), 2026-08-25.** Reviewed
draft 1 concurrently with round 1; verdict REQUEST CHANGES, 9 findings + 27 citation checks
(135 verified). Four were already answered by the round-1 fold (its F1 enroute dead zone,
F3 circular confirm gate, F5 stranded transfer family, F8 dead withdraw button — the v2.1
designs for §7.1/§7.5/§7.6/§6.2 hold against codex's concrete sequences). Five were NEW and
are folded here as v2.2: F1b → §7.4's 현장 인계 arm keeps today's evidence semantics (the
door-stamp predicate can never fire for a mode with no door) · F2 → the §7.1 stamps are
proximity-verified at write and CLEARED by every dissolution path (the "stamps start null"
claim was false — dissolution reuses the row; explicit clearing is the fix), and the fee
fires only at the host's evidence-shown confirmation tap · F4 → §5.5: objection un-pairs but
never refunds; safety objections open an incident; the event-anchored rung question joins
🔴 14.11 · F6 → C6/§7.5 corrected: release is resolved-OR-incident-settled (0072:232-244),
not resolved-only · F7 → §6.5: `committed_at` added (rank tiebreak 4 referenced a column
that does not exist), owner-visible distance bands deleted (triangulation oracle), input
CHECKs + the 0073 pin-repair dependency named. Codex's citation deltas patched. What codex
could not attack: the 0119 coverage and the load formula — both held.

*The spec decides nothing Sean didn't say; every 🔵 is reversible in one word; every 🔴 blocks
only its own slice.*
