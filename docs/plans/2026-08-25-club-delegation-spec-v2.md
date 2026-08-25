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

Status: DRAFT **v2.5** — both blind rounds folded in (Claude voice: 15 findings; codex voice: 9
findings; dispositions in §15), then **re-scoped 2026-08-25 evening by Sean's sixth-round
rulings** (§16), amended the same evening by his **seventh round** — the club sign-up setup
screen (§16.7) — and **v2.5: §16.3's drafted retirement of the host recovery pen is WITHDRAWN**,
because he confirmed at `2026-08-25T09:03:48.227Z` that the pen stays (§16.3). Nothing here is
built.

⚠ **READ §16 FIRST.** Four of his rulings change this machine. One REVERSES a position this
document argued for at length (§4.2, host admission) and is settled. **One — §16.3, the retirement
of the host recovery pen — was never executed: it reversed his OWN explicit approval (console
card 10, 04:26:44Z), so it was held PROVISIONAL, put back to him, and he answered
「keep host reassignment functionality when such cases happen for that pair. if no one can, the
host can take care.」 (09:03:48Z). §6.6 therefore stands as originally written, and §16.3 is now
an amendment record of a withdrawn amendment rather than a live change.** Every section touched
carries an inline `[AMENDED 2026-08-25 · §16.n]` marker. Where a ruling collides with money or
custody correctness the collision is stated in §16 as a collision, not smoothed away.

⚠ **THEN READ §16.7** — his seventh round, the sign-up setup screen. It REVERSES one sentence of
§7.2 (*"return mirrors pickup, same flag"*): the return point becomes the owner's own choice,
independent of pickup. Net schema surface: **one column**, `session_dogs.return_mode`. It also
adds the host pickup monitor (§10.2a), records **OPEN-F** (runner pay when a leg disappears —
money, unanswered, no number proposed), and surfaces a shipped disclosure-gate hole that §8.1
arms (§8.6). §16.7b states a collision with the relay that carried his words; §16.7f states what
retired and why the *reason* matters.

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

**[AMENDED 2026-08-25 · §16.1 and §16.2]** — the **Scope** column is new and is the pack
model made explicit; **P1 is RETIRED**. Scope values: **⟨pair⟩** = genuinely per-pairing (the
rung's fact differs dog by dog, and something depends on the difference) · **⟨pack⟩** = the
rung's fact is session-wide by Sean's ruling; per-dog rows still exist mechanically but the
board reads them as one band and per-dog divergence is an EXCEPTION, not a state ·
**⟨pair·money⟩** = per-pairing AND load-bearing for money or custody correctness, so it may
NOT be collapsed (§16.1 states each conflict).

| # | State | Scope | Underlying facts | Money | Entered by |
|---|---|---|---|---|---|
| P0 | `signed_up` | ⟨pair⟩ | `session_dogs` row, `custody='runner_delegated'`, `approval` written **`'approved'` at INSERT** (§4.2 as amended; today `'pending'`, 0048:135-136) | none | owner: `session_delegate_dog` (0048:89) — 0119 gate fires HERE (INSERT trigger, 0119:415) |
| ~~P1~~ | ~~`admitted`~~ | — | **RETIRED — RULED §16.2.** The host does not admit. `session_approve_dog`'s admission role, the pay-pending-approval step and the console queue all retire; the `approval` COLUMN survives and every downstream reader of it is byte-identical (§4.2 as amended). What the rung really carried — the **delegated-capacity reservation** (`hold_status='active'` + `hold_expires_at`, the sole input to `_club_delegated_reserved`, 0043:70-79) — does NOT disappear with it; §4.2 says where it goes and §14 OPEN-A asks Sean the one number | none | — |
| P2 | `paid` | ⟨pair·money⟩ | booking minted `status='matching'`, `runner_id=null` (0081:184) | seat real; no charge (0081:207) | owner: `session_pay_delegation` — **mint timing unchanged** (§5.1); its capacity re-check (0081:154-157) becomes the delegated cap's enforcer (§4.2) |
| P3 | `pick_pending` | ⟨pair⟩ | `proposed_runner_profile_id` set, `proposal_expires_at` = now()+TTL | none | owner (Mode B) or platform (Mode C) — the chooser swap, §6 |
| P4 | `paired` | ⟨pair·money⟩ | booking `confirmed`, `runner_id` set (0057:132-134) | 20% rung arms **only inside the 24h window** (§5.2 — round-1 F1) | runner: `session_proposal_respond(true)` — approval stays the runner's, with no self-pair path (§6.1) |
| P5 | `pickup_enroute` | ⟨pair⟩ — **Sean's named edge** | **booking stays `confirmed`**; 출발/도착 stamps are NEW `session_dogs` columns (§7.1 — round-1 F3) | — | runner taps 출발/도착 (server-stamped) |
| P6 | `picked_up` | ⟨pair·money⟩ — **Sean's named edge** | both handoff stamps → booking `picked_up`; custody trigger flips custodian to runner (0045:44-53) | — | both-stamp `confirm_handoff` at the DOOR (or at start for 현장 인계 pairings, §7.2) |
| P7 | `at_start` | ⟨pair·money⟩ — **Sean's named edge**, and it CONVERGES: this is the last rung before the pack | dog-at-start stamp (§7.4 — the no-show predicate's positive side) | — | runner's `session_checkin` stamps held dogs (0030:259 mechanism, re-anchored) |
| P8 | `running` | **⟨pack⟩** — one shared start, RULED | booking `active`, `runs` row (0050:169-198). ⚠ measured: `club_start_delegated_runs` is already **per-RUNNER, not per-pairing** — it flips *every* `picked_up` booking that runner holds in one call (0050:174-191) | — | runner: `club_start_delegated_runs`. Nothing today enforces one shared start across runners — §14 OPEN-C |
| P9 | `run_finished` | **⟨pack⟩ by expectation, ⟨pair·money⟩ by construction — the sharpest conflict, §16.1** | booking `completed` via settle-run (0083:628); `custody_phase` = new `finished_pending_host` (§7.5) — **escapable by construction** (§7.6) | runner paid at settle on **per-dog GPS-measured `actual_km`/`duration_sec`** (`run/[sid].tsx:255-270`); club has no return seal (marketplace-only guard, 0083:677-688); NOT payable yet | runner settles per dog — this IS Sean's "per-runner finish", and it stays per-dog because the money is |
| P10 | `returning` | **⟨pack⟩ — already session-wide in this spec, and the ruling confirms it** | `custody_phase='return_pending'` | — | **host run-end confirmation flips all P9 pairings at once** (§7.5) |
| P11 | `resolved` | ⟨pair·money⟩ — **Sean's named edge** ("some are returning or finished completely") | both return stamps → `_club_finalize_return` (0070:343): custodian back to owner, `payable` | payout `earned→payable` | both-stamp at the home door (or 현장 반환) |
| P12 | `released` | ⟨pair·money⟩ | `payout_state='released'` | supply money leaves | cron `club_release_payouts` (0072:221) — UNCHANGED, still requires `resolved` + no open incident |

Cancellation arms exit this ladder at defined points only (§5.3). Incident states
(`incident_review`, holds, settlement) are orthogonal and UNCHANGED (0070/0072/0080 — §13
C9-C14). The 맹견 gate fires at P0 (INSERT) and at every custody-bound move exactly as landed —
zero 0119 changes, and §7.1's stamp design is chosen specifically so that stays true (§13 C28).

**What actually changed vs today, in one sentence each:**
1. The chooser at P3 is the owner or the platform; the host keeps only a recovery role
   (§6.6 — RULED 2026-08-25 09:03:48Z, the pen stays).
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
6. **[AMENDED · §16.1] The session runs as ONE PACK** — shared start, shared-or-similar end,
   per-dog variation only at the custody edges. §1.1.

### 1.1 The pack model [AMENDED 2026-08-25 · §16.1]

🔴 **RULED.** Sean, sixth round, verbatim (full paragraph at
`docs/decisions/2026-08-25-console-rulings.md:158-165`):

> "what does the different states mean? aren't they all supposed to be in near sync? same start
> time, maybe different arrival states as some can be doing pick up or arrival, but also same end
> or maybe some are returning or finished completely. … the club will be running in a pack so end
> times would probably be all the same or similar."

**The rule, restated in this spec's vocabulary:** the run itself is a session-wide fact. Per-dog
variation is legitimate at the **edges** — before (some at pickup, some arrived) and after (some
returning, some finished) — and is a defect anywhere else. The struck model of independent
per-pairing mid-run progression is retired.

**What that actually changes** — this spec's analysis, deliberately small, because the ruling is
mostly a re-interpretation and the machine already largely obeys it:

1. **The ladder gains a Scope column** (§1) rather than losing rungs. No rung is deleted by this
   ruling and no new machinery is added. Sean named the edges he wants to keep (pickup/arrival,
   returning/finished) and they are exactly P5-P7 and P10-P11, which were already per-pairing.
2. **The board reads P7→P9 as one band, not as N independent states.** This is the ruling's real
   content and it is where the labs' "different states" came from. Concretely, for the §9 member
   projection and the operational board: once the pack is running, the session renders **one**
   러닝 중 band, and a pairing that diverges renders as a named **exception** against it
   (미출발 · 지각 · 조기 종료), never as a peer state. The label vocabulary is already built for
   this — `club_dog_ui_state` carries 조기 반환 as a BADGE on a partial completion
   (`0116:616-618`), not as a stage, which is precisely the exception shape.
3. **The mid-run rungs were never as independent as the labs implied.** Measured:
   `club_start_delegated_runs` (`0050:169-198`) is **per-RUNNER, not per-pairing** — one call
   flips every `picked_up` booking that runner holds and opens a `runs` row for each
   (`0050:174-191`). A three-dog runner's dogs already start together. What is NOT synchronised
   is two different runners, and nothing in the schema enforces it (§14 OPEN-C).
4. **P10 was already session-wide** and the ruling confirms the design: the host's run-end
   confirmation flips every `finished_pending_host` pairing to `return_pending` at once (§7.5.2).
   The pack model is the reason that is right, not a coincidence.

#### 1.1a Where per-pairing independence is LOAD-BEARING and must NOT collapse

Flagged as conflicts rather than resolved, per the brief. Each is a ⟨pair·money⟩ rung in §1.

- 🔴 **P9 is the sharp one. The money is per-dog and cannot become per-pack.** The runner's
  payout basis is computed per booking from that dog's own GPS trace: `run/[sid].tsx:255-270`
  measures `actual_km` from the points after *that dog's* `runs.started_at` and passes it with a
  per-dog `duration_sec` into `settleRun` → `settle_run_tx` (`0083:628`). Two dogs on the same
  pack run do not necessarily produce the same km — one may be handed back early, and the shipped
  `end_reason` enum has `dog_condition` / `owner_request` / `runner_personal` alongside
  `completed` (`run/[sid].tsx:230`) precisely so that is expressible. A session-wide finish that
  wrote one km for every dog would either overpay or underpay a runner on a real, shipped path,
  and 「러너 지급을 조용히 깎지 않는다」 is a MONEY CANON law. **Resolution: P9 stays per-dog in
  the machine and reads as the pack's end on the board.** Sean's own words permit this — "maybe
  some are … finished completely" — so there is no conflict with the ruling, only with a naive
  reading of it. The `조기 반환` badge (`0116:616-618`) is how the divergence surfaces honestly.
- 🔴 **P6 and P11 are custody transfers between two named humans and are irreducibly
  per-pairing.** Custody flips on that pairing's two handoff stamps (`0045:44-53`) and resolves
  on that pairing's two return stamps (`_club_finalize_return`, `0070:343`). A pack-scoped
  custody flip would mean one owner's tap moving another owner's dog into a stranger's custody.
  Never collapse; Sean named these as edges anyway.
- 🔴 **P7 carries the no-show money predicate** (§7.4) and is evaluated per pairing at the host's
  confirmation tap. Collapsing it to "the pack arrived" would charge or refund the wrong owners.
- **P8 as a GATE stays per-pairing** even though P8 as a *label* is the pack: a dog that was never
  picked up cannot be `active`, and `club_start_delegated_runs` refuses `nothing_to_start`
  (`0050:177`) rather than inventing one. The pack does not drag an absent dog along.

- **[AMENDED · §16.7] `pickup_mode`/`return_mode` are per-pairing and sit exactly on the edges
  the ruling protects.** They compose cleanly — see §16.7e for the check. The on-site arms
  *shrink* the edges rather than widening them: the dog arrives where the pack forms, so there is
  no per-dog scatter before the run and none after it. Do not read that as "the pack has one
  pickup": a 집 픽업 pairing beside a 현장 인계 pairing is Sean's own named before-edge variation
  (*"some can be doing pick up or arrival"*), not a divergence to be flattened.

**One gate this spec proposes actually moves (🔵), and only one:** the run-end confirmation's
blocking population (§7.5.2) already reads "no pairing still at `picked_up` or `active`", which is
a pack-scoped predicate over per-pairing rows — correct as written, and it is named here so a
later reader does not "fix" it into a per-pairing gate in the pack model's name. Everything else
in §16.1 is display and copy.

---

## 2. Actors

| Actor | Gains | Loses | Identity/standing mechanism (today's, reused) |
|---|---|---|---|
| Owner | per-session mode fork; Mode B pick + pick withdrawal; per-pairing pickup mode; custody timeline visibility | nothing | `session_dogs.owner_profile_id`; shell `limited/full` (0049:9) |
| Paired runner | approves picks made days ahead; a self-exit lever (§6.2); door pickup; transit custody; per-dog finish; return leg | being chosen at the scene | `session_runner_assignments` commit (0043:217); tier cap (0037:37) |
| Dogless companion | board visibility; ride-along | — (never paid — ruled) | `session_rsvp(dog:=null)` → `session_people(role='runner_attending')` (0048:181) — §4.4 |
| Host **[AMENDED · §16.2]** | run-end confirmation; session lifecycle (kept); force-resolve/override/cases (kept, with widened phases §7.6); materiality re-review (kept — safety, §4.2); `session_assignment_revoke` (kept — un-pair, §6.6a); **the recovery pen (KEPT — §6.6; RULED 09:03:48Z, §16.3)** | the PRIMARY matching role — the chooser at P3 becomes the owner or the platform (§6.1), and the pen survives only as recovery inside `[T−2h, T+6h]` (§6.6) · **admission: approve AND reject** (§4.2 as amended) · the club's only exclusion lever, with nothing replacing it (§4.2c ②) | `host_profile_id`; backup-host asymmetries per §14.5 (a money-routing question, not just permissions) |
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

RULED 2026-08-25 evening (sixth round — §16, verbatim at
`docs/decisions/2026-08-25-console-rulings.md:158-165`): **the session runs as one pack** ·
**no host approval of owners or runners** (this REVERSES §4.2's original argument) ·
Instagram-style profiles are their own future lane, parked at
`docs/plans/2026-08-25-profiles-lane-seed.md`.

RULED 2026-08-25 **09:03:48Z** (console card `host-realloc-confirm`, verbatim at
`docs/decisions/2026-08-25-console-rulings.md:277`): **「keep host reassignment functionality when
such cases happen for that pair. if no one can, the host can take care.」** — **the host's pair
reassignment STAYS.** This settles, in favour of his own 04:26:44Z approval, the question his
sixth round opened (*"pair reallocation functionality for the host? is that really necessary, i
dont think so"*). §6.6 stands as originally written and §16.3's drafted retirement is withdrawn
— see §16.3 for the approve → doubt → confirm sequence. ⚠️ Two things this ruling does NOT settle,
both measured and recorded at §6.6c rather than reconciled away: the shipped
`session_assignment_revoke` returns the booking to the matching POOL rather than handing it to a
runner the host picks, and his last-resort clause 「if no one can, the host can take care」 has no
mechanism today and is unpriced.

RULED 2026-08-25 evening (seventh round — §16.7, verbatim there): **the club sign-up flow is a
setup screen** (self-run vs request-a-runner → pickup point → session details → return point) ·
**the return point is the owner's own choice, independent of pickup** — which REVERSES §7.2's
"return mirrors pickup, same flag" · **pickup and return are each {집, 현장} and nothing more**
(*"then just do either on site or home address"* — this RETIRES the custom-address arm he had
floated hours earlier, and with it the 「not too far」 distance question, §16.7f) · **the host
monitors pickup statuses** (§10.2a).

PROPOSED by this spec (🔵, each reversible): per-pairing pickup mode {door, start-point} (§7.2)
· pick TTL 2h with lapse-back (§6.3) · the three unconditional escape hatches for
`finished_pending_host` (§7.6) · host recovery-propose window (§6.6) — **RETAINED**; the drafted
§16.3 retirement is withdrawn (RULED 09:03:48Z), and the window itself remains this spec's own
🔵 proposal ·
companions = runner-tier RSVP (§4.4) · Mode C pilot inputs and their new CHECK bounds (§6.5) ·
mode-switch fee copy (§5.3) · address at T−24h, area band at pairing (§8) · **[NEW, §16.2]**
`approval='approved'` at sign-up (§4.2b) · **[NEW, §16.2]** re-keying the `full` shell grade from
approval to payment (§4.2b ① — a shipped security predicate; 🔴 OPEN-B).

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

### 4.2 ~~Host admission SURVIVES~~ → **HOST ADMISSION RETIRES** [AMENDED 2026-08-25 · §16.2]

🔴 **THIS SECTION IS REVERSED BY SEAN'S RULING.** His words (sixth round, verbatim, full
paragraph at `docs/decisions/2026-08-25-console-rulings.md:158-165`):

> "for the host console, why is the host accepting or rejecting an owner? they shuold be able
> to sign up and runners too without the host's permission."

The paragraph below the rule is **this spec's analysis of what that costs**, marked as such. The
ruling itself is one sentence: **owners sign up (and pay) and runners commit without the host's
permission.**

The original §4.2 argued admission survives because it is "vetting an animal into a group run the
host is responsible for." That argument is overruled and its text is struck; the reasoning is
kept below only where it names something the ruling now leaves uncovered.

#### 4.2a What retires — every server arm, named

| Object | file:line (verified) | Disposition |
|---|---|---|
| `session_approve_dog(uuid, boolean)` — **approve arm** | `0084:610-648`; writes exactly `approval='approved'`, `hold_status='active'`, `hold_expires_at = now()+20min` at `0084:635-637` | **Deprecate by refusal** (house doctrine, §11): the function KEEPS its name and signature, its body becomes a single `raise exception 'host_admission_retired'`, and its EXECUTE is revoked from `authenticated`. It does NOT vanish — installed bundles call it from `console/[sid].tsx:138` via `approveDelegation` (`api.ts:3691-3692`) and must get a named token, not a 404 |
| `session_approve_dog` — **reject arm** | `0084:624-630` (there is **no** `session_reject_dog`; verified: zero hits repo-wide) | Retires with the same refusal. See 4.2c — this is the club's ONLY exclusion mechanism |
| `session_approve_dog`'s owner notification | `0084:641-643` 「위탁 승인 — 결제 대기」/「20분 안에 자리를 확정하면 돼요」 | Retires. ⚠ Suite 120's notification-coverage sweep names it explicitly at `120_g1_ops_cutover_suite.sql:711` |
| `session_delegate_dog`'s host notification | `0048:152-153` 「위탁 신청 도착 … 승인/거절을 결정하세요」 | Retires or re-copies — it instructs the host to do a thing the host can no longer do (dead-instruction class, honesty law) |
| `session_delegate_dog`'s inserted `approval` value | `0048:135-136`, today `'pending'` | 🔵 **becomes `'approved'`** — see 4.2b |
| `session_reconsider_dog` | `0043:362-382`, host-only, gated `approval='rejected'` (`0043:371`, `not_rejected`) | Retires by refusal — its gate's precondition can no longer be produced |
| The `rejected` re-application block | `0048:129-133` | Loses its producer for new rows. Keep the code (legacy rows exist); see 4.2c |
| `_club_compute_axes`'s `pending` and `rejected` arms | `0048:710-714` | Keep the code; both become unreachable for new rows. `service_state='requested'` and `service_reason='host_rejected'` become legacy-only values |
| Console admission queue (client) | `console/[sid].tsx:128` (`pending` filter), `:130-145` (`doApprove`), `:352-378` (심사 section incl. the 승인/거절 buttons at `:374-375`) | Removed |
| Client approval copy | `session/[sid].tsx:46` (`PENDING: '호스트가 확인 중이에요 …'`), `:702`, `:753`, `:774-785` (the PENDING flap card), `:897-905` (the re-apply door); `delegate/[sid].tsx:92`, `:116`, `:261`; `club/[id].tsx:467` (`'승인 · 배정 · 세션 운영'`) | Re-written in the same client slice |
| `api.ts:3691-3692` `approveDelegation` | rpc `session_approve_dog` | Deleted with its one production caller |

**What does NOT retire, and why** — each was checked, not assumed:

- **`session_review_dog`** (`0048:259-286`) — materiality re-review. It gates on
  `review_needed` (`0048:269`) and **reads `approval` nowhere**; it is a safety re-check when a
  dog's declared weight changes under a live delegation, not admission. Survives byte-identical,
  with `console/[sid].tsx:147-158` and `:379-394`. Its producer, `_club_dog_materiality_tg`, DOES
  read `approval = 'approved'` (`0048:232`) — under 4.2b that predicate becomes true one step
  earlier, which is a widening in the *safe* direction (more dogs re-reviewed, never fewer).
- **`session_assignment_revoke`** (`0057:158-185`, host-only at `:168`) — dissolving a pairing
  before handoff. It is not admission and Sean's ruling does not touch it. The host's ability to
  *re-pair* after dissolving also survives (§6.6, RULED 09:03:48Z). ⚠️ But what this function
  actually does on revoke is return the booking to the matching POOL — not hand it to a runner the
  host picks (`0057:177-179`, measured). That gap between the ruling and the mechanism is §6.6c.
- **The `approval` COLUMN itself** (`session_dogs.approval`, `0030:87`, widened `0048:73-75`).
  Retire the ACTOR, keep the COLUMN — see 4.2b.

#### 4.2b The minimal reconciliation (🔵 — analysis, not ruled): keep the column, flip the default

`approval` is read by six live objects, and every one of them means *"this dog is admitted to
this session"* rather than *"a host said yes"*:

`_club_shell_access` `0049:19-20` · `session_pay_delegation` `0081:148-151` (`not_payable`) ·
`session_propose_dog` `0048:457-459` (`not_approved`) · `_club_incident_can_open` `0067:77` ·
`_club_dog_materiality_tg` `0048:232` · `_club_delegation_board_impl` `0053:239/241/283/333`.

So the smallest correct change is **`session_delegate_dog` inserts `approval='approved'`**
(`0048:136`) and every reader above stays **byte-identical**. Sign-up IS admission; P0 and the
retired P1 collapse into one rung. This is a proposal (🔵), reversible in one word, and it is
the shape §11's deprecation table and §12's S3 assume.

**Three consequences of that flip, each named rather than absorbed:**

1. 🔴 **The `limited` shell grade loses its meaning, and 0049's own stated principle breaks.**
   `_club_shell_access` promotes a delegating owner from `limited` to `full` on
   `sd.approval='approved'` (`0049:19-20`); `full` is what grants group chat, the roster, phone
   visibility, and incident standing (`_club_incident_can_open` admits `full`, `0067:68`). Flip
   the default and **every owner reaches `full` the instant they sign up, before paying** — but
   0049's own header states the opposite rule in the code, at `0049:5`: 「신청만 한 사람은 그룹
   채팅에 들어오지 못한다 — 신청은 사적 공간의 문이 아니다」 ("someone who has merely applied
   does not enter the group chat; an application is not the door to a private space"). That
   principle is not the host's — it survives the ruling, and naive self-admission violates it.
   🔵 **Proposed re-key: `full` keys on `sd.booking_id is not null` (paid) instead of
   `sd.approval='approved'`; `limited` keys on the row existing.** This restates 0049's principle
   in the vocabulary the ruling leaves standing, and it matches §5.1's own words about pay time —
   *"the moment the seat becomes real."* It is a change to a shipped security predicate and
   therefore rides the full adversarial cycle with pins both ways. **See §14 OPEN-B**, because
   the alternative reading (an unpaid applicant SHOULD be in the group chat now that nobody is
   vetting them) is a product call, not an engineering one.
2. **The delegated-capacity reservation moves — see 4.2c.**
3. **`session_runner_withdraw`'s eviction sweep strands rows.** When a committed runner
   withdraws and the derived cap shrinks, `0043:441-450` pushes excess delegations back to
   `approval='pending'` (with a full refund at `:443-445`, or a released hold at `:447-449`) —
   i.e. **back to the host's queue.** With no host queue, those rows are zombies: `pending`
   refuses pay (`0081:151`), drops the owner to `limited` (`0049:21-22`), and nothing can
   advance them. 🔵 The sweep must instead either restore the self-admitted resting value
   (`approval='approved'`, hold cleared, seat lost to the cap but re-payable if room returns) or
   terminate the row as `withdrawn` with the same refund. Named as inherited work of the ruling's
   slice; the choice is the implementer's with a pin either way.

#### 4.2c What the admission gate was carrying that now has NO cover

Written as holes, per the honesty law — not as risks that will "be handled".

**① The delegated-dog capacity had exactly one unconditional enforcer, and it was approve.**
Measured, and it contradicts what §5.1 implies about `session_pay_delegation`:

- `delegated_dog_capacity` (`0030:60`, derived from committed handling-runner caps by
  `_club_rederive_capacity`, `0037:55`) is checked at **approve** unconditionally
  (`0084:632-633`, `no_capacity`) and at **pay** only when the hold has already lapsed
  (`0081:154-157` — the `if not (v_hold='active' and v_hexp > now())` branch).
- It is **never** checked at delegate-insert. `session_delegate_dog` checks only the *total*-dog
  cap: `_club_total_dogs` vs `coalesce(total_dog_capacity, people_capacity)` (`0048:115-120`,
  `dog_capacity_full`) — a different cap with a different helper and a different token.
- `_club_delegated_reserved` (`0043:70-79`) counts **active unexpired holds + live bookings**. An
  `approval='pending'` application counts for nothing. **The 20-minute hold is not a
  pay-pending-approval formality; it is the reservation token**, and approve was its only writer.

Retire approve and the reservation has no writer — at which point the `if not (…)` guard at
`0081:154` is *always* true, so the pay-time check fires unconditionally and the cap IS still
enforced. **The cap survives; the RESERVATION does not.** Concretely: today two owners cannot
both be told "you have 20 minutes to pay for the last slot"; after the retirement they can, and
the second one's payment fails with `no_capacity` after they have already decided to pay. That is
a worse experience, and it is the honest cost. Two ways out, and the choice is Sean's number, not
an engineering call — **§14 OPEN-A**: `session_delegate_dog` writes the hold itself at sign-up
(reservation preserved, but the clock now starts when nobody has looked at the application, and
20 minutes was calibrated to "a human just approved you"), or there is no reservation and
capacity is an honest first-to-pay race with the pay screen saying so.

⚠ The pins that own this property are pinned THROUGH approve and must MIGRATE, not be
fixture-edited: `50_delegation_suite.sql` D7 (`:174-200`) and M2/M3/M5 (`:444-500`) — see §16.2's
suite table.

**② The club loses its only exclusion mechanism, entirely.** Measured: there is **no blocklist,
no ban, no host member-removal RPC, and no `status` column on `club_members`** (DDL `0030:30-36`:
`role` is only `host`|`member`). `club_join` is unconditional for any signed-in user
(`0048:197-204`, granted at `:216`). The only DELETE paths are `club_leave` (self-service,
`0048:212`) and account deletion. The **sole** exclusion lever in the entire club product was the
reject arm at `0084:625`: it wrote `approval='rejected'`, the axes trigger mapped that to
`service_reason='host_rejected'` (`0048:713-714` via `0040:280-282`), and `session_delegate_dog`
then refused re-application (`0048:129-133`, token `rejected`) — per-session, per-dog, one attempt
deep, never following the owner or the dog anywhere else.

Retire the reject arm and **a host has no way to keep any dog or any person out of any session,
for any reason, including a documented safety reason.** That is the direct and intended reading
of Sean's sentence, and this spec does not soften it. What partially covers the gap, honestly
labelled:

- *After* a pairing exists: `session_assignment_revoke` (`0057:158-185`) un-pairs, and the runner
  can decline a pick — but neither removes the dog from the session.
- *During* the session: `club_incident_open` and the host's force-resolve/override tools
  (`0070`) — after something has happened, never before.
- Nothing at all covers "this dog should not be in this session."

**This is a hole, not a residual.** It is out of scope for the four amendments (Sean did not ask
for a replacement and this spec will not invent a bouncer he retired), and it is the subject of
**§14 OPEN-D**, phrased so one sentence closes it.

**③ A small disclosure widening, named.** `_club_delegation_board_impl` emits `'approval', d.approval`
(`0053:283`) and both an approved-count and a pending-count in its header (`0053:239`, `0053:241`).
Under 4.2b the pending count is permanently 0 and the field is a constant. The member board (§9)
never carried it; the S2 contract's pin P6 (`docs/contracts/club-board-s2-contract.md:409`) is
affected — see §16.5.

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
RULED (14.6, 2026-08-25): **guests can be crew too** — any dogless RSVP, runner-tier or
guest, may be listed as crew on the board. Standing needs no new machinery: every RSVP holds
a `session_people` row → shell `full` → incident standing (0049:14, 0067:68). ⚠ ERRATUM
(S2 contract verification): the crew predicate is "dogless `session_people` row", NEVER the
`runner_attending` role — 0048:178-180 assigns `runner_attending` only to non-applicant
runners; a dogless GUEST gets `owner_attending`, so a role-keyed crew query would drop every
guest, the exact thing this ruling forbids. The board's crew row shows name and role only.

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

**SUPERSEDED for the runnerless arm, ruled 14.13 (2026-08-25):** when no runner ever
accepted, cancellation is FREE at any time — "should be no fee if the owner was not
connected; it's our job to connect them." The 10% runnerless arm and ruling B's halving of
it retire together in their own migration (153's ladder pins re-target in that slice); the
marketplace's unaccepted tier gets checked against the same principle in its own slice.
Post-acceptance fees are untouched by this ruling. Slot comp reading: a
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

**[AMENDED · §16.2]** The `P0/P1` row below becomes `P0` alone — P1 is retired and there is no
approval-pending state to exit from. The withdraw arm itself is unchanged (`session_cancel_delegation`,
latest at `0124:38`, writes `approval='withdrawn'` at `0124:74`), and it becomes the ONLY pre-pay
exit — the host-reject exit (`0084:625`) retires with the rest of admission.

| Exit at | Path | Money | Mechanism |
|---|---|---|---|
| P0 ~~/P1~~ | owner withdraws | none; hold released (if §14 OPEN-A puts a hold at sign-up; otherwise nothing to release) | 0118:1025-1032 arm → superseded by `0124:38`, unchanged by this spec |
| P2 | owner cancels | ladder (free/10%), ruling B — no runner | `session_cancel_delegation` 0118:989 with §5.2's rung order |
| P3 | owner withdraws the pick (free) or cancels; runner declines; TTL lapses | decline/lapse/withdraw move NO money and return to P2; cancel rides the ladder (runnerless) | withdraw: `session_proposal_revoke` gate widened to the pick's author (§6.2 — round-1 F10) · decline: 0057:145 arm · lapse: recovery cron 0068:41-57 with §6.3's TTL |
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
   (`docs/contracts/runner-money-strip-contract.md` — on `claude/runner-money-strip`, at v2
   @ 481890b after its own two blind reviews; cited as a contract-in-flight, and S2+
   re-verify it landed before binding to it): `expected_net` computed server-side, never a
   component set, gross, fee, or rate — and per contract v2 the mechanism is an inline
   scalar subquery inside a definer-owned view, NEVER a callable helper (its reviewers
   killed the `rate()` helper: view bodies don't shield function EXECUTE, so any helper a
   view can call, a client can call). One line that contract asks this spec to carry: club
   pricing today inherits the public km-linear `club_fare` (0043:14), so its §0 residuals
   (v2 names two, the public-linear-pricing class first) apply to club too; if club pricing
   ever decouples runner net from the public per-km line, that is the door to closing the
   first — a pricing decision, Sean's, not assumed here.

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
  on both RPCs. The host recovery propose (§6.6) keeps its shipped self-proposal semantics —
  `session_propose_dog` and its auto-accepting self-proposal arm (`0048:492-503`) survive inside
  the recovery window, which is the "host covers at the scene" path. (§16.3 drafted their
  retirement; that amendment is withdrawn — RULED 09:03:48Z.)
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
  window RETAINS two jobs: check-in, and bounding the host-side *recovery* propose (§6.6, which
  stays — RULED 09:03:48Z).
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
with the owner notified** (recovery cron 0068:41-57 already expires stale proposals — it gains
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

### 6.6 The recovery pen — **KEPT** [RULED 2026-08-25 09:03:48Z · §16.3 withdrawn]

**The host's residual matching role: recovery only (🔵 — and RULED, 14.10).**

When a pick lapses inside T−2h, or a pairing dissolves at the meetup (revoke, decline,
no-show), someone must cover NOW. This spec proposes the host regains the propose pen **only
inside the old window [T−2h, T+6h]** and only for dogs at P2 — `session_propose_dog` survives
with its gate narrowed to that recovery window. Board copy names it 재배정, distinct from
picks. The window itself remains a 🔵 proposal; **that the host has the pen at all is now RULED**,
not proposed.

**Provenance, because this section was drafted retired and then restored.** §16.3 drafted the
pen's retirement off his sixth-round *"pair reallocation functionality for the host? is that
really necessary, i dont think so"*, held it PROVISIONAL because it reversed his own
04:26:44Z approval of console card 10, and put the question back to him. He answered on the
console at `2026-08-25T09:03:48.227Z`:

> "keep host reassignment functionality when such cases happen for that pair. if no one can, the
> host can take care."

So the pen stays, and §16.3 is now a record of a withdrawn amendment. The full sequence and why
it cost a marker change rather than a rebuild is in §16.3; the ruling's own record is
`docs/decisions/2026-08-25-console-rulings.md` (eighth and ninth rounds).

⚠️ **His answer is NOT fully expressed by the shipped mechanism, and §6.6c states that gap as a
gap.** Read §6.6c before implementing anything in this section.

#### 6.6a Bail shapes — where each one lands, and who acts next

| Bail shape | Mechanism (unchanged) | Lands at | Who acts next |
|---|---|---|---|
| Runner declines a pick | `session_proposal_respond(false)`, `0057:145` arm | P2 | owner re-picks / auto-connects |
| Pick TTL lapses | `club_assignment_recovery` ②, `0068:41-57` | P2 | owner |
| Owner withdraws their own pick | `session_proposal_revoke`, gate widened §6.2 | P2 | owner |
| Runner self-exits a pairing | `session_assignment_revoke`, gate widened §6.2; strike at `0057:174` | P2 | owner |
| Host dissolves a pairing (runner gone dark) | `session_assignment_revoke`, `0057:158-185`, host arm KEPT | P2 | owner re-picks; **or the host, inside the recovery window (§6.6)** — but see §6.6c on what the shipped function actually does |
| Runner no-show at the door | §7.4's predicate; pairing dissolves at run-end confirmation | refund arm | — |

Three copy strings were flagged as dead instructions while §16.3's retirement was drafted. **With
the pen restored, two of them are correct again inside the recovery window** — the host really can
propose again — and the residual is narrower than the retirement made it look:

- `0068:51-53` — the lapse notification goes to the **host** with 「제안이 응답 없이 만료됐어요
  — 다시 제안하세요」 ("propose again"). Correct for a lapse inside `[T−2h, T+6h]`. ⚠️ Residual: a
  **v2 owner-authored pick** that lapses OUTSIDE that window tells the host to do something only
  the owner can do there. 🔵 add the owner as a recipient; the recipient does not move.
- `0068:71-75` — the T−30 runner-late alarm 「교체 제안을 준비하세요」 is inside the window by
  construction (T−30 < T−2h is false — T−30 is *within* the window), so it is correct as shipped.
  🔵 add the owner as a recipient.
- Client: `console/[sid].tsx:432` 「거절됨 — 다른 러너에게 제안하세요」 — correct while the grid is
  gated to the recovery window (§10.2).

#### 6.6b What the pen covers — the case that makes it worth keeping

The pen's real job was never "matching"; it is **latency at the worst moment**. Three honest
statements, in decreasing order of how much v2's own design already absorbs. They were written to
put in front of Sean as the answer to his own question, and his 09:03:48Z 「keep」 is the answer to
them — so they are retained, re-pointed at the world where the pen exists:

1. **v2 shrinks the pen's job a great deal on its own.** In the at-the-scene world the pen
   covered a dog physically present at the meetup with no runner, whose owner had often already
   left. Under v2, custody starts at the owner's **door** (§7.1): a bail before P6 leaves the dog
   at home with its owner, who is reachable and holds the re-pick surface. A bail after P6 was
   never the pen's business — the runner is holding the dog and that is incident machinery
   (§7.3, 0070/0072/0080), untouched. So the pen is a narrow backstop, not a second matcher, and
   the narrowed `[T−2h, T+6h]` gate is sized to exactly that.
2. **The case it exists for is the late bail in 집 픽업 mode, inside the last hour.** A pick that
   lapses or a runner who self-exits at T−40min returns the dog to P2. Without the pen the owner
   must, in minutes: notice, open the pick surface, find a committed runner with cap headroom, and
   get an accept — while the pack is forming at the meetup point. The pen lets the host, who is
   standing at the meetup and can see who actually turned up, close that on behalf of an owner who
   might be at work. The measured aggravating facts that make the owner-only path hard here:
   capacity is consumed by live picks (`_club_runner_load`, `0047:52-66`), so a runner sitting on
   someone else's lapsing pick is invisible as available; and the pick TTL is 2h (RULED 14.1),
   which inside the last hour clamps to `scheduled_at` (§6.3) and can therefore be minutes.
3. **The pack model (§16.1) sharpens it.** One shared start means the pack does not wait. An
   unpaired dog at `scheduled_at` is a dog that does not run. The terminal outcome without a
   backstop is honest — the never-picked-up refund arm fires at run-end confirmation (§7.5.2) and
   the owner pays nothing — so nobody would be *charged* for the gap; they would just lose the
   session. That bound is why the retirement was affordable; it is not why it was right.

**What this spec still does NOT do:** invent machinery beyond the pen. No auto-reassign, no
standby-runner pool. §14 OPEN-E, which asked whether "the dog does not run and is fully refunded"
was an acceptable outcome, is **dissolved by this ruling** — the pen is the mitigation.

#### 6.6c ⚠️ The ruling and the shipped mechanism DISAGREE — three open items, recorded not reconciled

All three were measured at source while executing this reversion. **The model owes the ruling, not
the reverse:** none of the following is licence to reinterpret his words to fit the code, and the
implementing slice owns closing each one.

1. 🔴 **`session_assignment_revoke` does not hand the dog to a runner the host chooses — it
   returns the booking to the MATCHING POOL.** Live definition `0057:158-185` (0047:221 is
   superseded by it); the write is `0057:177-179`: `update bookings set runner_id = null,
   status = 'matching', owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null`.
   The host un-assigns; the pool re-fills. **His ruling implies the host picks** — 「keep host
   reassignment functionality… **if no one can, the host can take care**」 only makes sense if the
   host is looking at candidates and can see that none exist. ⚠️ Do NOT assert that the pool
   re-fill IS what he meant. The slice owes either a host-chooses path (which §6.6's
   `session_propose_dog` pen supplies for a dog at P2, i.e. AFTER a revoke — so the two-step
   revoke→propose may already be the shape, and that is a design claim to verify, not to assume)
   or an explicit question back to him.
2. ✅ **It refuses once handoff has happened** — `perform 1 from bookings where … (
   owner_confirmed_handoff_at is not null or runner_confirmed_handoff_at is not null); if found
   then raise exception 'already_handed_off'` (`0057:171-173`). So reassignment exists only
   BEFORE custody transfers. This **fits** the case he was answering (*"left before the start of
   the session?"*, seventh round) and forecloses any mid-run reassignment story. Recorded as a
   verified limit, not a gap.
3. 🔴 **「if no one can, the host can take care」 has NO mechanism today.** Nothing anywhere
   expresses the host becoming the runner for that pair. It carries an unpriced **money**
   question — is the host paid runner-pay on top of the host fee? — and a **party-gate** question,
   since host and runner would be one person on one booking (and §6.1's self-pairing refusals
   exist precisely to stop one account holding both sides). ⚠️ His separate 09:05:51Z ruling
   **"Same pay either way"** does NOT cover this: that one is about a runner whose *leg* is
   skipped, not about who walks the dog. OPEN and unpriced; nothing builds against it.

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

### 7.2 Per-pairing pickup mode (🔵) — the attending-owner scenario, solved where it lives [AMENDED 2026-08-25 · §16.7]

C7's missing scenario (a Mode B owner who attends — in a Banpo pilot the most likely case)
is not an edge: it's a per-pairing choice. At P2 the owner picks **집 픽업** (default; the flow
above) or **현장 인계** (owner brings the dog to the start and both-stamps there — today's
shipped chain, byte-identical). ~~Return mirrors pickup (집 반환 / 현장 반환, same flag).~~ One
column on the pairing (`pickup_mode`), zero new custody mechanics for the 현장 arm, and the
"pointless return trip to an empty home" the review flagged becomes unconstructable. 맹견 gate,
ladder, and finish logic are pickup-mode-blind. 🔴 §14.2 for Sean's nod since it reshapes his
"the runner should pick them up" default into a default-plus-option — **given, 14.2 "BOTH"**.

#### 7.2a [AMENDED · §16.7] RETURN stops sharing the flag — one change, and it is a reversal

🔴 **RULED** (Sean, 2026-08-25 evening; verbatim and provenance in §16.7). The option set above
is **unchanged** — he collapsed his own richer draft back to it: *"then just do either on site or
home address."* No third pickup arm, no custom-address arm on either leg. What his ruling DOES
change is the sentence struck above:

**"Return mirrors pickup, same flag" is STRUCK.** He specifies the return point as a choice the
owner makes *for itself*: the runner meets the owner *"where the owner desires"*, either at the
owner's address or at the site where the run finished. Pickup-at-home with collection-on-site is
a combination an owner can want, and one two-valued flag expresses two of the four combinations,
not four. This is a **reversal of this spec's own design**, not a widening of the option set, and
it is recorded as one.

**The fields, settled here so client and server bind the same names** (🔵 for the *names*; the
*model* is his):

| Field | Home | Values | Notes |
|---|---|---|---|
| `pickup_mode` | `session_dogs` | `owner_home` (default) · `session_start` | NOT NULL, defaulted. Unchanged in meaning; UI 집 픽업 · 현장 인계 |
| `return_mode` | `session_dogs` | `owner_home` (default) · `session_finish` | **NEW — the whole of this amendment's schema surface.** UI 집 반환 · 현장 반환 |
| the address VALUE | `bookings.address_id` (**shipped**, `0001:170`) | an `addresses` row, or NULL | Serves whichever legs are address legs. NULL only when BOTH modes are on-site — which is today's shipped club mint unchanged (`0081:184-186` omits `address_id` from the column list) |

**No `return_address_id` column, and that is a finding, not an omission.** With the custom-address
arm gone, the only address either leg can name is the owner's own — so one address per pairing is
sufficient for all four combinations, and `bookings.address_id` already is that column:

| `pickup_mode` | `return_mode` | `bookings.address_id` | Who reads it |
|---|---|---|---|
| `owner_home` | `owner_home` | set | both legs |
| `owner_home` | `session_finish` | set | pickup leg only |
| `session_start` | `owner_home` | **set** | return leg only |
| `session_start` | `session_finish` | NULL | nobody — today's shipped mint |

Row 3 is the one worth reading twice: an address must be captured at sign-up even when no pickup
leg exists, and §8's item 1 as written (*"현장 인계 pairings pass null and never enter the address
surface"*) makes exactly that row unbuildable. §8.6 restates the rule on `return_mode`.

**Why `pickup_mode` stays an explicit NOT NULL column rather than being derived from
`address_id IS NULL`:** NULL is already overloaded. `booking_pickup_address` returns 0 rows for
「주소 미지정」 *and* for a poisoned row, and says so (`0065:58-59`, `0060:68`) — so a NULL address
cannot distinguish "the owner chose on-site" from "the owner has not answered yet". A screen
rendering 「현장 인계」 off an absent address would be asserting a choice nobody made, which is the
fabricated-data law. The mode is the source; the address is its consequence, and the two must
agree.

**Unchanged by all of this:** the two-sided transfer ritual on both legs — see §16.7d. The
destination is a field; the transfer is still two named humans stamping.

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
6. **[AMENDED · §16.7] The capture rule is keyed on BOTH modes, and the disclosure gate has a
   hole the club path walks into.** Two corrections this slice must carry:
   - **Capture:** item 1's rule (*"현장 인계 pairings pass null"*) is now wrong for one of the
     four §7.2a combinations — `pickup_mode='session_start'` with `return_mode='owner_home'`
     needs the address for the RETURN leg. Restated: `p_address_id` is required unless **both**
     modes are on-site, and refused when both are.
   - 🔴 **The shipped disclosure RPC cannot serve a home return, and this slice is what arms
     it.** `booking_pickup_address`'s gate admits the runner at
     `runner_enroute`/`picked_up`/`active`, or at `confirmed` inside T−24h (`0065:50-53`) —
     **`completed` is not in the set.** The club's return leg happens *after* `completed`: the
     custody trigger's `completed` arm is what opens the return phase (`0045:55-59`), and §7.5.1
     changes only which `custody_phase` value it writes, not the booking status that triggers it.
     So a runner on a 집 반환 leg is refused `not_runner` for the address they are standing
     outside. The marketplace does not have this bug — 0083 keeps its booking at `active` through
     the homeward leg and `completed` comes after (`0083:176-179`) — so this is a club/marketplace
     divergence, **latent only because club bookings mint with `address_id` NULL today**
     (`0081:184-186`). The moment item 1 starts writing addresses, it is live.
     §10.3's P10 row (*"return leg per dog: address"*) is the screen requirement with no producer.
     Fix shape (🔵, for the adversarial cycle to rule on): widen the gate to admit the assigned
     runner while that pairing's `custody_phase` is unresolved, rather than adding `completed` to
     a status list shared with the marketplace — the custody phase is the fact that actually
     means "this runner still holds this dog", and `index.ts:238-241`'s history is exactly what a
     careless status widening costs.

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
| ~~P0 신청 대기~~ **[AMENDED · §16.2]** | **RETIRED as a waiting state.** Sign-up lands directly on the pay card. `session/[sid].tsx:774-785` (the `PENDING` flap card) and `STAGE_HINT.PENDING` at `:46` (「호스트가 확인 중이에요 …」) are deleted, along with `delegate/[sid].tsx:92`'s 「호스트가 확인하면 알려드릴게요 … 심사에 들어갔어요」 success copy and `:261`'s 「승인 후 20분 안에 …」 | — |
| P2-entry 결제 대기 (was P1) | ● pay card — today's `HOLDING` block, `session/[sid].tsx:746-771`, pay CTA `:762`, withdraw `:767-769`. The 20-min DrainRing at `:751` survives ONLY if §14 OPEN-A puts a hold at sign-up; if not, the ring and `:753`'s 「홀드가 끝났어요 — 승인부터 다시 필요할 수 있어요」 both go, and the card must say honestly that the slot is not reserved | pay (`자리 확정하기` — gains address pick §8.1 + pickup-mode pick §7.2) · withdraw (free) |
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

**[AMENDED · §16.2 — the console loses ONE of its three sections.]** §16.3 had drafted a second
loss (the propose grid); that amendment is **withdrawn** (RULED 09:03:48Z, §16.3), so the grid
stays, gated to §6.6's recovery window.

KEEPS: materiality re-review (`doReview`, `:147-158`; rows `:379-394`) · cases section
(assign/resolve, `:512-541`) · force-resolve + custody override with the self-override dead-button
logic (`:216-245`, rows `:557-600`, reason sheet `:619-650`) and the §7.6-widened phases · session
cancel (`doCancelSession` `:260-278`, CTA `:612-614`) · the unresolved/blocker read, which moves
server-side (§9, S2 contract §5b).

LOSES — **the admission queue entirely** (§16.2): the `pending` filter `:128`, `doApprove`
`:130-145`, the whole 심사 section `:352-378` including the 승인/거절 buttons at `:374-375` and
the capacity-0 warning `:354-360`, and the `approval === 'approved'` stat chip at `:306`.

KEEPS, NARROWED — **the runner-chip propose grid** (§6.6): `:161-186` (buckets + `doPropose`),
the chip grid `:445-460` with its `blocked`/`why` pre-gate, the proposed rows and their
`DrainRing` + revoke `:465-490`, and `:432`'s 「거절됨 — 다른 러너에게 제안하세요」 all survive, but
the whole grid is **gated to the recovery window `[T−2h, T+6h]` and to dogs at P2**, and is
relabelled 재배정 so it reads as recovery rather than as matching. Outside the window it does not
render at all — the owner's pick surface is the only door (§10.1). The accepted-pairs rows
`:491-509` keep `doRevoke` (`assignmentRevoke`, `:187-197`). ⚠️ §6.6c ①: `doRevoke` returns the
booking to the matching pool, so "revoke then re-propose" is two taps on two different surfaces —
the S5 author must not render it as one hand-pick action until that gap is closed.

Net: after §16.2 the console loses its gatekeeping surface and keeps one operational surface plus
one narrow recovery surface (run-end confirmation, pairs timeline, recovery 재배정, cases, custody
tools, session lifecycle). `club/[id].tsx:467`'s console subtitle 「승인 · 배정 · 세션 운영」 is
false in its first word (there is no 승인) and misleading in its second (배정 is recovery-only),
and re-writes.
GAINS: ● the run-end confirmation (§7.5) — one button, enabled when no pairing is still out
(picked_up/active), with the blocker rendering server-classified (§9 kills the duplicated
predicate); its evidence view shows the §7.4 arrival/no-show flags per pairing so the host
sees exactly what money will move BEFORE tapping · a pairs timeline (watch, not choose).
Backup host: may confirm run-end (RULED 14.5); host fee routes to the real host regardless
(§7.5.2). Ruled bar for this whole subsection (his 14.10 comment): the host UI must include
"all steps of the flow — each possible step and scenario" — the S5 client slice delivers the
host console as a complete per-state enumeration, not a summary screen.

#### 10.2a [AMENDED · §16.7] GAINS — the pickup monitor 🔴 RULED

Sean's words: *"pick up statuses have to be monitored by the host."* A per-pairing pickup strip
on the console, before the pack forms. What it must display, and where each column comes from —
**measured, and three of the seven do not exist yet**:

| Column | Producer | Shipped? |
|---|---|---|
| which mode this pairing chose | `session_dogs.pickup_mode` (§7.2a) | ❌ unbuilt |
| 동 band — **never the address** (§8.4) | `addresses.dong` (`0122:57`, nullable, renders absent not placeholder `0122:55-56`) | column yes; host-side projection ❌ |
| runner departed · arrived at the door | `session_dogs.pickup_departed_at` / `pickup_arrived_at` (§7.1, `:831-833`) | ❌ unbuilt |
| both-stamp handoff done | `bookings.owner_confirmed_handoff_at` / `runner_confirmed_handoff_at` (`0001:182-183`), already projected as `ownerConfirmed`/`runnerConfirmed` (`0053:295-296`) | ✅ |
| who holds the dog now | `session_dogs.custody_phase` / `custodian_type` → `custodyPhase`/`custodianType` (`0053:300-301`) | ✅ |
| stage label + exception badge | `club_dog_ui_state` (`0116:552`) | ✅, but its vocabulary has **no pickup-leg stage** — it jumps 「담당 확정 — 인계 대기」 (`0116:595`) → 「러너가 보호 중」 (`0116:596-597`) |
| overdue | derived: `club_sessions.scheduled_at` (`0030:55`) vs the stamps above | derivable once the stamps exist |

Readership and delivery: the host grade already sees every delegated dog
(`_club_delegation_board_impl`, `p_access in ('host','full')`, `0053:335`), so this is a
projection widening on the OPERATIONAL board — `create or replace`, grant-preserving, the view
law observed (§9 already schedules exactly this widening).

**The honest consequence, stated rather than designed around: the shipped board cannot satisfy
this ruling.** Its only pickup signal is two booleans (`0053:295-296`), which distinguish
"handed off" from "not handed off" and nothing else — a host reading it cannot tell a runner who
has not left from one standing at the door. So **the pickup monitor hard-depends on §7.1's four
stamps landing**; until they do, the console shows a two-state strip and must say so rather than
implying a leg it cannot see.

**And `session_start` pairings must render as their own class, not as stalled pickups.** They
produce no pickup leg and therefore no `pickup_departed_at`/`pickup_arrived_at` — ever. Sorted
into the same list as 집 픽업 rows they are permanently "not departed", i.e. the monitor invents
N alarms per session. 「현장 인계 예정」 is a distinct row state, and it resolves at the start
site the moment the both-stamp lands.

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

**[AMENDED 2026-08-25 · §16.2 — three rows added, one changed.]** §16.3 had additionally rewritten
four rows to retire the propose family; that amendment is **withdrawn** (RULED 09:03:48Z), so those
rows read as originally drafted.

| Surface | Action | Pins |
|---|---|---|
| **`session_approve_dog(uuid, boolean)`** `0084:610-648` **[NEW ROW · §16.2]** | **Deprecate by refusal**: `create or replace` to a body that raises `host_admission_retired`; revoke EXECUTE from `authenticated`. Name and signature KEPT — installed bundles call it (`api.ts:3691-3692` ← `console/[sid].tsx:138`) and must get a named token, never a missing function | 1 refusal pin + an ACL pin. ⚠ 18 shipped suites call it in fixture setup — see §16.2's suite table; that sweep is IN this slice, not deferred |
| **`session_reconsider_dog`** `0043:362-382` **[NEW ROW · §16.2]** | Deprecate by refusal — its `approval='rejected'` precondition (`0043:371`) can no longer be produced | 1 refusal pin |
| **`session_delegate_dog`** `0048:89-155` **[NEW ROW · §16.2]** | `create or replace`: insert `approval='approved'` (`0048:136`) instead of `'pending'`; host notification `0048:152-153` retires or re-copies; 🔴 the hold write is §14 OPEN-A | positive pins on the new resting state; the `dog_capacity_full` arm (`0048:118-119`) RE-PINNED unchanged in-slice because 66 F6 pins it from another file |
| `session_propose_dog` host-primary role | **gate NARROWS to the §6.6 recovery window** `[T−2h, T+6h]`, dogs at P2 only. Name, signature and the auto-accepting self-proposal arm (`0048:492-503`) all KEPT — that arm is the "host covers at the scene" path the pen exists for. Its client caller (`api.ts:3677-3678` ← `console/[sid].tsx:174`) stays, behind the narrowed gate | gate pins both ways (inside/outside the window); the `assign_window` pins it carries stay live and gain a P2 pin |
| `session_assign_dog` | already an alias (0047:143-146) over propose — revoke `authenticated` EXECUTE + refusal pin; `api.ts:3696-3697` call site deleted (its one consumer is `dev/club-lab.tsx:278`; **verified: no production screen calls it**) | 1 refusal pin |
| `session_proposal_revoke` `0047:201-218` | gate WIDENS: host **OR** the live pick's author-owner (§6.2). The host arm stays — it is the pen's revoke half (§6.6). ⚠ Observed while verifying: this function has **no `auth.uid() is null` guard** (its sibling got one at `0057:162`; this one was never hardened) — the slice that touches it adds one | gate pins both ways + a null-uid pin |
| `session_assignment_revoke` `0057:158-185` | gate WIDENS: host OR the assigned runner (self-exit, §6.2). **Host arm KEPT** (§6.6, RULED). ⚠️ §6.6c ①: its body returns the booking to `matching` (`0057:177-179`), it does not re-pair — the re-pair half is `session_propose_dog` behind the recovery gate | gate pins both ways; a pin on the `matching` resting state so the two-step shape is asserted, not assumed |
| ~~`session_reconsider_dog`,~~ `session_review_dog` | `session_review_dog` (`0048:259-286`) **KEPT** — verified it gates on `review_needed` (`0048:269`) and reads `approval` nowhere, so it is safety, not admission. `session_reconsider_dog` moved to its own row above | — |
| `session_proposal_respond`, `session_owner_objection` | KEPT — the accept/objection rails the pick layer rides | gate-delta pins only |
| Console admission queue (client) **[NEW ROW · §16.2]** | removed: `:128`, `:130-145`, `:306`, `:352-378` | — |
| Console propose grid (client) | **removed outside the recovery window** and relabelled 재배정 inside it (§10.2): `:161-186`, `:432`, `:445-490` all survive behind the gate | — |
| `club_expire_delegation_holds()` `0043:385-408` **[NEW ROW · §16.2]** | Depends on §14 OPEN-A: if sign-up writes no hold, this cron has nothing to sweep and its 「결제 기한 만료」 notification (`0043:395-396`) never fires — retire it in the same breath rather than leaving a live cron that can never match a row | 1 pin either way |

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
| **S2.5** **[NEW · §16.2]** | **Admission retirement.** `session_approve_dog` + `session_reconsider_dog` → refusal; `session_delegate_dog` writes `approval='approved'`; the `session_runner_withdraw` eviction fix (§4.2b ③); the shell-grade re-key if OPEN-B says so; the hold decision from OPEN-A; the console + client copy half; **and the measured fixture sweep across 18 shipped suites + `upgrade_seed_v1.sql` (§16.2), which is IN this slice**. Sequenced before S3 because S3's pick gates read `approval` (`0048:457`) | **🔴 OPEN-A and OPEN-B answered.** Not gated on S2 |
| S3 | Pick layer (§6.1-6.4): `session_pick_runner`, self-pick refusals, gate moves + the two widenings, TTL (2h — RULED 14.1), deprecations §11 **including `session_propose_dog`'s narrowing to the §6.6 recovery window and the console grid's gating**, viability re-read (§13). ⚠ §5.2's LADDER implementation (rung reorder + runnerless-zero, both ruled) moved OUT of S3 into announcer v5's single ladder-amendment slice — one function, one slice, per the silent-collision law | S2 (board renders picks) + **S2.5** (pick gates read `approval`) — 14.1/14.10/14.11 ruled. ⚠️ **§6.6c ①** (host-chooses vs pool re-fill) is this slice's to close or to route back to Sean; **§6.6c ③** (host-as-runner) is NOT in S3 and nothing may build against it |
| S4 | Door custody (§7.1-7.4): the four stamps + club edge action, address slice (§8), no-show re-anchor + 153 P4/P9/P10/P12 re-pins, copy-drift rows (§13), client legs | S3; riders (honest transit copy); 🔴 14.2 |
| S5 | Two-phase finish (§7.5): `finished_pending_host` + the three §7.6 escapes, `club_confirm_run_end` (6h auto-confirm ceiling — RULED 14.3), closer split, console respec | S4 — **gate OPEN** (14.3 and 14.5 both ruled) |
| S6 | Mode C (§6.5): columns + CHECK bounds, ranking definer, `session_auto_pick`, onboarding surface, pinned-address door | S3; **counsel brief answered** (rider); 🔴 14.4 |

Every S2-S6 migration: adversarial cycle (0059 doctrine), numbers two-sided from the remote tip
at write time, REGISTRY row in the same push, suites updated in-slice. Client halves land
atomically with any grant move (0088 law); no binary reaches a device before its `db push`
(the 0119 deploy-order law, now standing).

Kill criterion: NONE — ruled 14.7 (2026-08-25, "why call it off? no need i think"). The
redesign is unconditional; the review's proposed shelving mechanism is retired unbuilt.

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
| C16 | `club_dog_ui_state` 0116:552 | axes → stage | new stages (P5/P7/P9/P10 labels — their PRODUCERS are S4/S5 columns, so this rewrite rides S4/S5, NOT S2; S2 touches it not at all — erratum from the S2 contract) | RW (S4/S5) |
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
| C37 | **`_club_shell_access`** `0049:9-25` **[NEW · §16.2]** | `sd.approval='approved'` → `full`, else `limited` (`0049:19-22`) | 🔴 **RW or U depending on OPEN-B.** Naive self-admission makes every signed-up owner `full` before paying, violating 0049's own written principle at `0049:5`. 🔵 re-key `full` to `booking_id is not null`. A shipped SECURITY predicate — full adversarial cycle, pins both ways, and it moves chat, roster, phone AND incident standing together | RW (S2.5) |
| C38 | **`_club_incident_can_open`** `0067:68-77` **[NEW · §16.2]** | shell `full` + `sd.approval='approved'` at `0067:77` | Rides C37 — both terms widen or neither does. Named separately because it is the standing gate, and standing that arrives before payment is the part a reviewer must attack | RA (S2.5) |
| C39 | **`session_runner_withdraw`** eviction sweep `0043:432-455` **[NEW · §16.2]** | pushes excess delegations to `approval='pending'` + refund (`:443-449`) | **RW — it evicts into a queue that no longer exists.** §4.2b ③: either restore the self-admitted resting value or terminate the row as `withdrawn` with the same refund. Its two notification bodies (`:444-445`, `:449-450`) say 「승인 대기로 돌아갑니다」 and are false either way | RW (S2.5) |
| C40 | **`_club_delegated_reserved`** `0043:70-79` **[NEW · §16.2]** | active unexpired hold **OR** live booking | Body untouched; its INPUT changes. Approve was the only hold writer (`0084:635-637`), so after the retirement the hold term is dead unless OPEN-A puts a hold at sign-up. **The cap survives** (0081:154's guard is then always true, so the pay-time check always fires); **the reservation does not** — §4.2c ① | U (body) / RA (semantics), S2.5 |
| C41 | **`_club_compute_axes`** `0048:709-714` **[NEW · §16.2]** | `approval` → `service_state` | Code KEPT; the `pending`→`requested` and `rejected`→`host_rejected` arms become legacy-only (no producer for new rows). Do not delete — historical rows render through them | U (flagged), S2.5 |
| C42 | **`_club_delegation_board_impl`** `0053:239/241/283/333` **[NEW · §16.2]** | approved-count, pending-count, `'approval'` field, the owner's own rejected/withdrawn self-arm | pending-count becomes a constant 0; the `rejected` half of the self-arm loses its producer. Additive-only slices (S2) must not be blamed for it — this is S2.5's | RW (S2.5) |
| C43 | **`club_assignment_recovery`** `0068:41-57` and `0068:58-81` | expired-proposal cleanup; T−30 runner-late alarm | **U for the host arm** — with the pen kept (§6.6), `0068:51-53` 「다시 제안하세요」 and `0068:71-75` 「교체 제안을 준비하세요」 both address an action the host still has, and T−30 is inside the recovery window by construction. **RA, narrowly:** a v2 owner-authored pick that lapses OUTSIDE `[T−2h, T+6h]` still notifies only the host; 🔵 add the owner as a recipient on both (§6.6a). §16.3 had this as a full RW recipient-move; that is withdrawn | RA (S3) |
| — | **Copy-drift work list** (client + notification strings that state the OLD flow, each re-written in its slice): 0081:222 「집결지에서 배정」 · 0057:140 「집결지에서 인계」 · 0048:511 「5분 안에」 (+0084:603-607's warning that suites assert club titles verbatim — re-pin with the copy) · index.ts:324 「곧 러닝을 시작해요」 · 0118:1133-1134 recap `v_dogs` meaning note (§7.4) · **[§16.2]** 0084:641-643 approve notification · 0084:625-628 reject notification · 0048:152-153 「승인/거절을 결정하세요」 · 0043:394-396 hold-expiry notification · 0043:444-450 eviction notifications · client: `session/[sid].tsx:46/:702/:753`, `delegate/[sid].tsx:92/:116/:261`, `club/[id].tsx:467` · **[§6.6, narrowed]** 0068:51-53 and 0068:71-75 — recipient ADD (owner), not a move; `console/[sid].tsx:432` needs no re-copy, only the recovery gate | | | (S2.5, S3-S5) |

---

## 14. Sean's answers — RULED 2026-08-25 afternoon (console; verbatim record in docs/decisions/2026-08-25-console-rulings.md)

1. **Pick TTL: 2 hours** ✅ ("2 hours is good")
2. **Pickup mode: BOTH** ✅ — 집 픽업 default + 현장 인계 option. PLUS a new order in his
   comment: the owner-participates side (Mode A) gets a FULL per-side/per-state delineation —
   "all the screens and maps and etc for this side as well, full flushed" — see §16. His
   "just pay the club fee" raises the Mode A participation-fee question (today: free) —
   follow-up card pending; no Mode A fee builds until answered.
3. **Finish ceiling: 6-hour auto-confirm** ✅ — S5's hard gate is OPEN. System confirms 6h
   after the last runner-finish with host notification; the §7.6 escapes ship regardless.
4. **Owner distance pref in Mode C: skip** ✅
5. **Backup host may confirm** ✅ — host fee still routes to `host_profile_id` (§7.5.2).
6. **Guests CAN be crew** ✅ — overrides §4.4's runner-only proposal; §4.4 updated: any
   dogless RSVP may be listed as crew (standing already exists via `session_people`).
7. **NO kill criterion** ✅ ("why call it off? no need i think") — §12's kill paragraph
   removed; the redesign is unconditional.
8. **Refund quirk: FIX** ✅ — rides S4.
9. **Board public: accepted** ✅ ("it's like a public dashboard") — future idea parked: live
   ranked dashboard in community.
10. **Host recovery backstop: approved** ✅ — **SETTLED, and settled TWICE.** Console **card 10,
    "Host recovery pen inside T−2h" → "Give the host the 2-hour backstop", 04:26:44Z**
    (`docs/decisions/2026-08-25-console-rulings.md:20`). Later the same day, about the same
    object, he wrote *"pair reallocation functionality for the host? is that really necessary, i
    dont think so."* — a question carrying an opinion, not an instruction, and a reversal of this
    very tap. It was NOT executed; it was held provisional and put back to him, and at
    **09:03:48Z** he answered 「keep host reassignment functionality when such cases happen for
    that pair. if no one can, the host can take care.」 Card 10 stands, §6.6 stands, and §16.3 is
    a withdrawn amendment. Full sequence at §16.3 and at
    `docs/decisions/2026-08-25-console-rulings.md` (eighth and ninth rounds).
    ⚠️ The second half of his 09:03:48Z answer is a NEW arm with no mechanism and no price —
    §6.6c ③. It is not covered by this ✅.
    **The rest of his 14.10 comment is unaffected either way** — 「make sure all the host ui and
    screens include all steps of the flow」 is about completeness, not about the pen, and §10.2's
    bar stands: the host console is a complete per-state enumeration of what the host CAN do.
11. **Rung reorder: free-24h always wins** ✅ — §5.2 is ruled as written.
12. **R17 User Challenge: WAIT** ✅ — deferral accepted; the flip-activation package is the
    standing pre-flip slice.
13. **Runnerless cancel fee: ZERO** ✅ ("should be no fee if the owner was not connected;
    it's our job to connect them") — supersedes 10%-vs-5%; the runnerless 10% arm retires in
    its own migration; §5.2's table gains the ruled zero (see the note there).
14. **Durable owner-attended record: BUILD** ✅ — the Custody decision closes as B; lands
    with S4.
15. **맹견 gate: removal ordered — HELD for one explicit confirm** ⚠ — his comment orders
    all breeds accepted and the gate forgotten; held only because the prompting card omitted
    the gate's legal-review origin (readiness-review-nonlocation-2026-08-19.md). A
    context-complete confirm card is on the console. **Until confirmed: 0119 is frozen as
    deployed; no session touches it.** If confirmed, removal executes with counsel flagged.
16. **동네 피드: rename** ✅ — policy stays, name changes (ui6 copy job).

Still open, unchanged by this round: the schedule-list window card · the looks bundle ·
counsel briefs (S6's gate) · the Mode A participation-fee follow-up · the 맹견 confirm.

### 14-OPEN. New questions created by the sixth-round rulings [2026-08-25 · §16]

🔴 **Six were opened** (five from the sixth round, **OPEN-F added by the seventh, §16.7**)**, each
answerable in one sentence, each blocking only its own slice.** None is a
disagreement with a ruling; each is a thing a ruling left undetermined and that this spec refuses
to guess. They are ordered by which slice they block. **OPEN-E is now DISSOLVED** by the
09:03:48Z ruling (§16.3) — it is kept below, struck, rather than deleted. **Two NEW open items
were opened by that same ruling and live at §6.6c, not here**, because they are gaps between his
words and the shipped mechanism rather than questions the spec declined to answer.

**OPEN-A — the seat reservation (blocks S2.5).**
> When an owner signs up a dog and has not yet paid, does their slot stay held for them for a
> while, or is it a first-to-pay race with no reservation at all?

*Why it exists (analysis, §4.2c ①):* the 20-minute hold was written by the host's approve tap and
was the only input to the delegated-capacity reservation. With no approve tap there is no writer.
Holding at sign-up preserves today's behaviour but starts a clock nobody has looked at; not
holding is simpler and honest but two owners can both be told to pay for one slot. If he wants a
hold, the number is also his — 20 minutes was calibrated to "a human just approved you."

**OPEN-B — the group chat door (blocks S2.5).**
> Should someone who has signed a dog up but not paid yet be in the session's group chat, see the
> roster, and be able to open a safety case — or only after they pay?

*Why it exists (analysis, §4.2b ①):* `_club_shell_access` promotes on `approval='approved'`
(`0049:19-20`), and 0049's own code states the principle at `0049:5` — 「신청만 한 사람은 그룹
채팅에 들어오지 못한다」. Self-admission makes that promotion instant. This spec proposes re-keying
`full` to "paid", which restates 0049's rule in the vocabulary the ruling leaves standing — but it
is a product call about who is inside a private space, so it is his.

**OPEN-C — one pack, one start (blocks S4/S5 display, not any gate).**
> Does the pack leave at the scheduled time regardless, or does the board show each runner's own
> start until everyone has started?

*Why it exists (analysis, §1.1):* nothing today enforces a shared start across runners —
`club_start_delegated_runs` (`0050:169-198`) starts one runner's dogs, and any runner may call it
at any time once they hold a `picked_up` booking. Under the honesty law the board cannot claim a
pack start that no fact produces. Either answer is buildable with zero new machinery; the wrong
one is a board that lies.

**OPEN-D — the host has no way to keep anyone out (blocks nothing; it is a product hole).**
> Now that the host cannot reject an application, should a host be able to remove a dog or a
> person from a session at all — for a safety reason — or is that a report-to-us matter?

*Why it exists (analysis, §4.2c ②):* measured, the reject arm at `0084:625` was the **only**
exclusion mechanism anywhere in the club — there is no blocklist, no ban, no `status` on
`club_members` (`0030:30-36`), and no host member-removal RPC. Retiring it leaves nothing. This
spec deliberately proposes no replacement, because Sean removed a bouncer and a differently-named
bouncer would be the spec overruling him.

**OPEN-E — the late bail. ~~OPEN~~ → DISSOLVED 2026-08-25 09:03:48Z.**
> If a runner drops out an hour before the session and the owner cannot find another one in time,
> is "the dog does not run and is fully refunded" the right outcome — or should something else
> happen?

*Why it existed, and why it is gone:* it existed only under §16.3's retirement of the pen, and its
own text said so — "if he declines the reversal and keeps the pen, OPEN-E largely dissolves,
because the pen IS the mitigation." He kept the pen. **The mitigation is the pen** (§6.6), the
late-bail path is the host's recovery 재배정 inside `[T−2h, T+6h]`, and the refund arm remains the
terminal outcome only when even that fails. Kept here rather than deleted because the question
being asked and then dissolved is the evidence that no replacement mechanism was invented.
⚠️ What is NOT dissolved and is now tracked at **§6.6c**: whether the pen as shipped actually lets
the host *choose*, and whether 「if no one can, the host can take care」 has any mechanism or price.

**OPEN-F — what a runner earns when a leg disappears (blocks the §16.7 slice's money half only).
[NEW · §16.7]** 🔴 **MONEY — Sean's, and no number is proposed here.** One card, two arms,
because they are the same question mirrored:

> When the owner brings the dog to the start themselves, the runner does no pickup leg. When the
> owner collects at the finish, the runner does no carry-home leg. Both are strictly less work
> than the 집 arms. Does the runner earn the same, or less — and if less, by how much on each
> leg?

*Why it exists (analysis, and the shipped facts that bound it):*
- **There is no leg term to adjust.** The club price is `club_fare(km) = 9900 + round(km*3000)`
  (`0043:14`, comment `0081:286-287`) and the mint decomposes it as base 9900 + distance + 0
  addon (`0081:188-198`). Pickup and return travel are priced nowhere — not in the owner's fare,
  not in the runner's basis, which is that dog's own GPS-measured km through `settle_run_tx`
  (`run/[sid].tsx:255-270` → `0083:628`). So "the same" is not a decision to keep the status quo
  by inertia; it is already what every shipped line computes.
- **Which makes the DEFAULT arm the safe one, and any cut a deliberate act.** 「러너 지급을
  조용히 깎지 않는다」 is a MONEY CANON law (§1.1a). A differential that appeared because someone
  reasoned "less work, less pay" without his word would be exactly the silent cut it forbids.
- **It cannot be answered by looking at the owner's side either.** Whether the owner pays less
  for an on-site pairing is a second question with the same shape, and the two are not forced to
  move together — the commission split is where they meet, and 0121 stripped the runner-facing
  money surface precisely so that split is stated once.
- ⚠ This question was **not** created by the seventh round. §7.2's 현장 인계 arm has carried it
  since 14.2 ruled "BOTH"; the seventh round only doubled it by decoupling return. Naming it now
  rather than at implementation is the whole point.

## 15-bis. ORDERED ADDENDUM — Mode A (owner-participates), full delineation

Ruled with 14.2 (his comment, verbatim in the rulings doc): *"the owner can participate
themselves and just pay the club fee and not pay for a runner. we need to figure out all the
screens and maps and etc for this side as well, full flushed."* Spec v2's §4.3 (Mode A =
copy-plus-board) is therefore INSUFFICIENT by his word. A spec addendum (same review rigor)
must delineate the self-run owner side per-state: sign-up fork · pass/ticket · check-in ·
the live run surface a self-running owner sees (map, route, crew) · their dog on the board ·
finish/release · receipt. Open money question riding it: his "just pay the club fee" — today
a 동반 owner pays NOTHING (RSVP mints no booking, 0048:158); whether a participation fee
exists, and its shape, is a follow-up console card — no Mode A fee builds before his answer.

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

**Round 3 — re-scope, 2026-08-25 evening (§16).** Not a review: four of Sean's rulings landed
after v2.2 was drafted and one of them reverses a position this document argued at length. No
blind voice ran on the re-scope; §16.6 says what that means for the review path.

---

## 16. AMENDMENT RECORD — Sean's sixth round, 2026-08-25 evening

**Provenance.** Relayed through the ui6-a5 lab-critique channel while he reviewed the round-4
HTML labs; recorded verbatim with its dispositions at
`docs/decisions/2026-08-25-console-rulings.md:156-196`. **His full paragraph, unaltered:**

**Status of the four, up front:** §16.1 (pack model), §16.2 (no host approval) and §16.4
(profiles lane) are **instructions and are settled**. §16.3 (no host pair-reallocation) was held
**PROVISIONAL** — it reversed his own explicit approval on console card 10 and arrived as a
question carrying an opinion — and is now **WITHDRAWN**: he confirmed at 09:03:48Z that the host's
reassignment stays. §16.3 below is retained as the record of that sequence.

> "i like the pin board 1, but what does the different states mean? aren't they all supposed
> to be in near sync? same start time, maybe different arrival states as some can be doing
> pick up or arrival, but also same end or maybe some are returning or finished completely.
> also, clicking on each names should go to their profiles with their posts (like instagram).
> for the host console, why is the host accepting or rejecting an owner? they shuold be able
> to sign up and runners too without the host's permission. pair reallocation functionality
> for the host? is that really necessary, i dont think so. the club will be running in a pack
> so end times would probably be all the same or similar."

Everything below the quote is **this spec's analysis**, not his. Where analysis and ruling could
be confused, the ruling is quoted inline at the point of use.

### 16.1 PACK MODEL → §1.1 (new), §1 ladder Scope column

**Ruled**, three sentences of his paragraph. Amendment: §1.1 states the rule, the ladder gains a
Scope column, and §1.1a names four places where per-pairing independence is load-bearing and must
NOT collapse. **The sharpest conflict is P9**: the runner's payout basis is per-dog GPS-measured
km (`run/[sid].tsx:255-270` → `settle_run_tx`, `0083:628`) and the shipped `end_reason` enum
already expresses one dog ending early — a pack-scoped finish would over- or underpay a runner on
a real path. Resolved WITHOUT overruling him, because his own words permit the divergence
("maybe some are … finished completely"): P9 stays per-dog in the machine and reads as the pack's
end on the board. P6/P11 (custody transfers between two named humans) and P7 (the no-show money
predicate) are flagged the same way. Net new machinery: **none.** New OPEN: **OPEN-C**.

### 16.2 NO HOST APPROVAL → §4.2 REVERSED, plus §1, §2, §3, §5.3, §10.1, §10.2, §11, §12 (S2.5), §13 (C37-C42)

**Ruled**, and it reverses this spec: *"why is the host accepting or rejecting an owner? they
shuold be able to sign up and runners too without the host's permission."* The original §4.2 had
argued admission survives as "vetting an animal into a group run the host is responsible for."
Struck.

Amendment: P1 retires; `session_approve_dog` (both arms), `session_reconsider_dog`, the pay-
pending-approval step and the console admission queue all deprecate **by refusal** (house doctrine
— the RPC keeps its name and signature and raises a named token, because installed bundles call
it). The `approval` COLUMN survives and `session_delegate_dog` writes `'approved'` at insert, so
all six downstream readers stay byte-identical (§4.2b).

**Three findings that a naive retirement would have shipped as bugs**, each measured, each written
up in §4.2:

1. **The delegated-capacity RESERVATION dies with approve** (§4.2c ①). `delegated_dog_capacity` is
   enforced at approve unconditionally (`0084:632-633`) and at pay only when the hold has lapsed
   (`0081:154-157`); it is **never** enforced at delegate-insert, which checks a *different* cap
   with a *different* helper (`_club_total_dogs`, `0048:115-120`). The 20-minute hold is the
   reservation token and approve was its only writer. The cap survives, the reservation does not
   → **OPEN-A**.
2. **The `limited` shell grade collapses and 0049's own written principle breaks** (§4.2b ①).
   `_club_shell_access` promotes on `approval='approved'` (`0049:19-20`) and `0049:5` states
   「신청만 한 사람은 그룹 채팅에 들어오지 못한다」. Chat, roster, phone AND incident standing all
   move together → **OPEN-B**.
3. **The club loses its only exclusion mechanism entirely** (§4.2c ②). There is no blocklist, no
   ban, no `status` on `club_members` (`0030:30-36`), no host member-removal RPC, and `club_join`
   is unconditional (`0048:197-204`). The reject arm at `0084:625` → `host_rejected` →
   `session_delegate_dog`'s re-application refusal (`0048:129-133`) was the whole of it →
   **OPEN-D**.

Plus one stranding the retirement creates: `session_runner_withdraw`'s eviction sweep pushes
excess delegations back to `approval='pending'` (`0043:441-450`), i.e. into a queue that no longer
exists (§4.2b ③, C39).

#### The inherited suite sweep — MEASURED, and it is IN the S2.5 slice

A peer reviewer on another slice relayed that suites **66, 110, 153, 159** (+161, unlanded) would
go red. **Re-measured here rather than inherited, per the relayed-fact law — the real number is
larger:** `grep -rn session_approve_dog supabase/tests/` returns **74 call sites across 18 shipped
suite files plus `upgrade_seed_v1.sql`.** The peer named 4 of the 18.

| Class | Files | What the slice owes |
|---|---|---|
| **A — fixture setup only** (`perform session_approve_dog(sd, true)` to reach `approved`) | `50`(14) `60`(8) `65`(2) `66`(4) `67`(1) `68`(1) `90_race_setup`(4) `95`(2) `96`(2) `106`(3) `107`(5) `108`(3) `110`(2) `117`(7) `120`(3) `151`(1) `153`(2) `159`(6) | Delete the line — under §4.2b the row is already `approved` at insert, so the call would raise `not_pending` (`0084:621`). Mechanical, but 74 sites |
| **B — PINS ON APPROVE'S OWN BEHAVIOUR** — these MIGRATE, they are not fixture-edited | see below | Re-pin onto the new owner, with a comment naming the successor (CLAUDE.md's suite-updates-in-slice law) |

**Class B, itemised** (the part a fixture sweep would silently destroy):

- `50_delegation_suite.sql` **D7** (`:174-200`) — 정원 소진: approve refuses `no_capacity` at the
  cap. **This pin OWNS the delegated-capacity property.** Successor: `session_pay_delegation`'s
  now-unconditional re-check (`0081:154-157`).
- `50_delegation_suite.sql` **M2/M3/M5** (`:444-500`) — the reservation contract: the hold frees
  the slot on expiry, a second holder blocks an expired holder's pay, a paid dog blocks a
  newcomer. Their fate depends entirely on **OPEN-A**; if there is no hold, M2 and M3 have no
  subject and must be retired with a comment, not deleted silently.
- `50_delegation_suite.sql` **D6** (`:154-172`) — host rejection → `approval='rejected'` →
  re-registration refused with `rejected`. **Both halves lose their producer.** Restate as a
  legacy-row property or retire.
- `106_incident_subject_suite.sql:73` (「ob = REJECTED ⇒ 'limited' 영구」), `95_audit_gates_suite.sql:49`,
  `96_audit_followups_suite.sql:43` — all pin the `limited` shell grade **produced by a rejection**.
  Same loss; and they intersect **OPEN-B**, which may re-key `limited` anyway.
- `120_g1_ops_cutover_suite.sql:711` + `:745-746` — the notification-coverage sweep names
  `session_approve_dog`'s owner notification explicitly.
- `60_custody_suite.sql:315` and `upgrade_seed_v1.sql:39/:59` — consume approve's **return value**
  (v1-era, when approve minted the booking). Legacy shape; the seed is not a suite and needs its
  own decision.

**The slice may not defer this.** House law: a suite whose pinned behaviour legitimately changes is
updated in the same slice, with a WHY comment naming which new pin owns the new property. A
contract that ships without this table hands the implementer a red harness and no explanation.

### 16.3 NO HOST PAIR-REALLOCATION → **DRAFTED, HELD PROVISIONAL, WITHDRAWN 2026-08-25 09:03:48Z**

⚠️ **This amendment is WITHDRAWN. §6.6 stands as originally written.** The entry is kept — not
deleted — because the sequence is the most useful thing in it.

**The sequence, in his own words and timestamps:**

| # | When | His words | What the spec did |
|---|---|---|---|
| ① approve | **04:26:44Z** | console card 10, "Host recovery pen inside T−2h" → **"Give the host the 2-hour backstop"** (`docs/decisions/2026-08-25-console-rulings.md:20`) | §6.6 written with the pen; §14.10 ✅ |
| ② doubt | sixth round, same day | *"pair reallocation functionality for the host? is that really necessary, **i dont think so**."* | ⚠️ **NOT EXECUTED.** §6.6 re-scoped as retired but marked PROVISIONAL, original text preserved verbatim at §6.6-orig, every downstream row tagged PROVISIONAL, §14.10 marked CONTESTED not struck, and the question put back to him on the console with §6.6b's account of what the pen covers in front of him |
| ③ confirm | **09:03:48.227Z** | card `host-realloc-confirm`: **「keep host reassignment functionality when such cases happen for that pair. if no one can, the host can take care.」** (`docs/decisions/2026-08-25-console-rulings.md:277`) | This reversion: §6.6-orig's text becomes §6.6 again, every PROVISIONAL marker cleared, §14.10 back to SETTLED, OPEN-E dissolved, §6.6c opened |

**Why the hold was worth what it cost.** ② was a question carrying an opinion, not an instruction,
and it reversed ①. The recording session's own reading of ② was that he had changed his mind — and
that reading was **wrong**, as ③ proves. Because the retirement was held rather than executed,
being wrong cost a marker change instead of a rebuild: no migration was written, no suite was
re-pinned, no client file was touched, and `session_propose_dog` was never deprecated. **A ruling
that reverses the human's own explicit approval is the exact case where you stop and ask** — and
the value of asking is not that you were right to doubt, it is that the cost of being wrong stays
bounded. Had ② been executed on the inference, ③ would have arrived against a landed deprecation.

**What ③ additionally changes, beyond restoring ①.** Three consequences the eighth round records
(`docs/decisions/2026-08-25-console-rulings.md`, eighth round):
- **The `reassign_dogs_first` trap dissolves.** `session_runner_withdraw` refuses while that
  runner holds a `confirmed`/`picked_up`/`active` booking (`0043:420-424`, verified);
  `session_assignment_revoke`
  (`0057:158-185`, host-only at `:168`) is the only actor that can move such a dog. Retiring the
  host arm would have made the guard unsatisfiable and trapped runners in commitments they could
  not exit. With the pen kept, the guard stays satisfiable.
- **159's L5 pin stays reachable** — the accept → host-revoke → near-cancel FREE scenario keeps a
  live flow behind it. No pin rescoping, no fixture migration.
- **The seventh round's "someone else should carry it over" is MECHANISM, not gap** — the
  carrying-over IS the host's reassignment. His two answers agree: the earlier one says what
  happens to the dog, this one says who makes it happen.

**What ③ does NOT settle — see §6.6c, and do not reconcile it silently.** 「if no one can, the host
can take care」 implies a host who is looking at candidates, and the shipped
`session_assignment_revoke` returns the booking to the matching pool instead (`0057:177-179`); the
last-resort host-as-runner arm has no mechanism and no price. **The model owes the ruling, not the
reverse.**

**Markers cleared by this reversion** (each verified in place): §0 header · §1 item 1 · §2 host
row · §3 authority map · §3 proposed list · §4.2's `session_assignment_revoke` note · §6.1's
self-proposal clause · §6.2's window clause · §6.6 heading and body (§6.6-orig folded back in;
the duplicate section is gone) · §6.6a · §6.6b · §10.2 · §11 header and four rows · §12 S3 ·
§13 C43 and the copy-drift row · §14.10 · §14 OPEN-E · §16 status block · §16.6 · §16.7h.

### 16.4 INSTAGRAM-STYLE PROFILES → parked, NOT in this spec

**Ruled** as a direction, not as club-v2 work: *"clicking on each names should go to their
profiles with their posts (like instagram)."* Per the recording session's disposition
(`docs/decisions/2026-08-25-console-rulings.md:181-183`) this is "a NEW spec lane, not a club-v2
bolt-on." **Parked with the verbatim as its seed at
`docs/plans/2026-08-25-profiles-lane-seed.md`. Nothing is designed there and nothing enters this
spec.** The §9 member board's names stay untappable in club-v2.

### 16.5 Contract deltas

Both drafted contracts were re-verified against the re-scoped spec and each carries a dated delta
section appended to it — `docs/contracts/club-board-s2-contract.md` §13 and
`docs/contracts/club-rsvp-hardening-contract.md` §10. Neither contract is rewritten; the deltas
name which arms and pins moved.

### 16.6 What this re-scope did NOT do

Named, per the honesty law:

- **No blind adversarial voice has read the re-scope.** v2.2's two rounds reviewed the *struck*
  §4.2 and §6.6. S2.5 and the amended S3 need a fresh blind pass before implementation, and
  §4.2b ①'s shell-grade re-key is a shipped SECURITY predicate that needs the full cycle.
- **No migration, no suite, and no client file was touched.** This is a documentation amendment;
  everything above is unbuilt.
- **No replacement was invented** for either retired mechanism. OPEN-D and OPEN-E exist precisely
  so the spec does not quietly rebuild what Sean removed.
- **The §16.3 amendment was NOT executed, only drafted.** Its superseded text is preserved at
  §6.6-orig, its every downstream row is tagged PROVISIONAL, and §14.10 is marked CONTESTED rather
  than struck. Restoration is a marker change. **The one thing that must happen before anyone
  builds either way: card 10's reversal goes to Sean, with §6.6b's account of what the pen was
  covering in front of him — that analysis is the answer to his question, and it is why the
  question is worth asking rather than assuming.**
- **Erratum, noted not acted on:** this spec cites the 0119 맹견 gate throughout (P0, §7.1, C28).
  `supabase/migrations/0127_remove_dangerous_breed_gate.sql` exists on this branch (commit
  `15722f5`, its own message marks it **UNMEASURED**) and drops those triggers per ruling F1. Every
  0119 citation in this spec is therefore provisional on 0127's landing. Out of scope for these
  four amendments; flagged so the S2.5/S3 authors re-read before binding to a 0119 line number.

---

## 16.7 AMENDMENT — Sean's SEVENTH round, 2026-08-25 evening: the sign-up setup screen

**Provenance.** He was asked to pick from a five-option review; he declined the options and
specified the flow instead. Recorded at
`docs/plans/2026-08-25-return-point-and-round5.md` under `# RESOLUTION`. Everything outside the
quote blocks in this section is **this spec's analysis** and carries none of a ruling's
authority.

**Verbatim ①** (the flow):

> "as the owner goes through the process of signing up for a session, the app should prompt them
> with a set up screen asking all necessary things, including but not limited to whether they will
> run themselves in which case the starting point address and other things need to be shown, or
> whether they will request a runner, at which point the next required questions include but are
> not limited to where they ask the runner to pick up the dog … and also be shown all
> session details like time, group number, etc etc, and also whether the owner will pick up the dog
> at the club's ending point and meet the runner after the run is finished on site or whether they
> ask the runner to bring the dog back home so the owner can stay home."

**Verbatim ②** (the two legs, and the host):

> "a requested runner can initially meet and pick up the dog from the owner at the owner's selected
> point … in which case pick up statuses have to be monitored by the host, or they can meet the
> owner and the dog at the starting site of the session run if the owner has decided so… once the
> club session run has finished, the runner with the dog should meet the owner where the owner
> desires, which can either be the owner's custom address … or at the site where the run has
> finished (where once again the owner and the runner has to complete the transfer and mutual
> confirmation ritual) and the runner does not need to do a go-back-to-owner-home service"

**Verbatim ③** (within the hour, collapsing his own option set — relayed to this session by the
coordinating session; ⚠ **not verified against origin by this session**, and it is the load-bearing
sentence of §16.7f, so a reader acting on §16.7f should confirm it):

> "then just do either on site or home address."

### 16.7a The model, as ruled

| Choice | Options | Where it lands |
|---|---|---|
| Who runs the dog | self-run · request a runner | already the Mode A/B fork (§4.1); the setup screen is its front door |
| PICKUP point | 집 (default) · 현장 (session start) | `session_dogs.pickup_mode` — §7.2, unchanged |
| RETURN point | 집 (default) · 현장 (run finish) | `session_dogs.return_mode` — **NEW**, §7.2a |
| Session details shown | time, group number, … | already public via `club_session_detail`; a screen job, no model |
| Both transfers | the shipped two-sided ritual — **untouched** | §16.7d |
| Host | monitors pickup statuses | §10.2a — **new console surface** |

**Net schema surface of this entire amendment: one column.** That is the honest size of it, and
§16.7b explains why the first reading of his words made it look larger.

### 16.7b COLLISION — the "new third pickup option" was already this spec's second one

The relay that carried his resolution reported that `pickup_mode` *"widens from two options to
three"* and that the session-start arm was *"the part no review anticipated"*, inverting two CEO
objections (`2026-08-25-return-point-and-round5.md`, RESOLUTION §"What this settles"). Measured
against this spec, both halves are wrong, and in opposite directions:

1. **Session-start pickup is §7.2's 현장 인계, verbatim** — *"owner brings the dog to the start
   and both-stamps there — today's shipped chain, byte-identical"* (§7.2, unedited above). Sean did not add
   it; he **ruled it already** at §14.2 (*"Pickup mode: BOTH"*). A review cannot fail to
   anticipate a thing the spec it was reviewing had already proposed and had already had approved.
2. **The genuinely new arm was the custom address** — and far from inverting F7 (a second address
   disclosure per booking), it *was* F7. The relay attributed the privacy win to the wrong arm.
3. **And that arm is now retired anyway** (verbatim ③), which is why §7.2's option set survives
   this round completely unedited.

**A second correction, still live regardless of the collapse: `pickup_mode` is not shipped.**
`grep -rn pickup_mode supabase/ app/` returns **zero hits**. §7.2 marks it 🔵 and §3 files
it under PROPOSED. What is RULED is the option SET (14.2); the column is unbuilt. So this is not a
CHECK widening on a live enum with rows to back-fill — it is the first write of two columns, and
the implementing slice should stop looking for a migration that changes an existing constraint.

### 16.7c Where the return field lives, and why not on `bookings`

A prior plan proposed `bookings.return_kind`; a review killed it as belonging on the pairing row.
Re-derived here from the schema rather than inherited:

**The pairing row is `session_dogs`, and the return ritual already lives there.**
`_club_finalize_return` — the club's shared return terminal, called from both writers
(`0069:49`, re-created `0070:343`) — reads
`session_dogs.owner_confirmed_return_at` / `runner_confirmed_return_at` (`0070:349`, columns added
`0045:13-14`). The return *destination* must sit beside the return *stamps* it describes.

**`bookings` has identically-named columns that belong to a different flow.**
`bookings.owner_confirmed_return_at` / `runner_confirmed_return_at` were added by 0083
(`0083:165-166`) for the **marketplace** run-end flow. Two tables, four columns, one pair of names —
a `return_kind` on `bookings` would sit next to the marketplace's stamps and read as theirs.
That alone is enough.

Three more, each independent:
- `session_dogs` is the only row present in every mode: `booking_id` is **nullable** (`0030:86`,
  「위탁견만」), so a self-run dog — the setup screen's first fork — has no booking at all.
- `bookings` is the marketplace's own table (`0001:164`); a club-only enum there is a dead column
  on every marketplace row and a new thing for four other flows to read past.
- A re-attempt creates a **new** `session_dogs` row rather than reusing one — the active-attempt
  partial unique index (`0043:28-31`) admits a second row once the first is `service_state='ended'`
  — so per-pairing keying is already the schema's own unit for a choice that a dissolution resets.

**But the address VALUE deliberately stays on `bookings.address_id`** (`0001:170`), and that is
not an inconsistency: it is the key to a **shipped** security-definer disclosure gate
(`booking_pickup_address`, `0060:54` → `0065:41-44`, whose return type 0065 already had to
drop-and-recreate once). Moving it would rewrite a shipped disclosure RPC for no gain; §7.2a's
four-combination table shows one address serves every case. The asymmetry is: **the mode is club
state, the address is a disclosure key.**

### 16.7d The transfer ritual is NOT rebuilt — verified, not assumed

Sean's own words keep it (*"once again the owner and the runner has to complete the transfer and
mutual confirmation ritual"*), and this amendment adds nothing to it. Verified against shipped
code so no implementer reads a destination field as a custody model:

- Custody resolves **only** when both human stamps are present: `_club_finalize_return` returns
  false unless `owner_confirmed_return_at` and `runner_confirmed_return_at` are both non-null
  (`0070:349`), then writes the `dog_custody_events` row and flips `custody_phase='resolved'` /
  `payout_state='payable'` (`0069:59-71`).
- The force valve records the **weaker** side's evidence, deliberately, so an override cannot
  launder itself into a clean two-sided return (`0070:343-356`, `session_dogs.return_override`
  `0045:14`).
- Sean has ruled on this object before, and the ruling is in the schema's own comment:
  *"THIS interaction is the evidence, and the runner is paid once the dog is returned"*
  (`0083:182-186`, his D-r1 ruling, on `bookings.owner_confirmed_return_at`).

**So: `return_mode` says WHERE the two humans meet. It never says WHO takes custody, and an
address must never be allowed to receive a dog.** A 집 반환 pairing whose owner is absent is not
a completed return — it is the force valve's population, unchanged.

### 16.7e The on-site arms against the PACK MODEL (§1.1) — they compose

Checked rather than assumed, because §1.1 is a ruling and this is analysis:

- §1.1's rule is that the run is session-wide and per-dog variation is legitimate **at the edges**
  — before (*"some can be doing pick up or arrival"*) and after (*"some are returning or finished
  completely"*). Pickup and return points are exactly those two edges and nothing
  else; nothing in either mode reaches the mid-run band the ruling protects.
- The on-site arms **shrink** the edges rather than widening them: the dog arrives where the pack
  forms, so `session_start` produces no per-dog scatter before the run and `session_finish` none
  after it. They are the most pack-conformant arms available.
- **No collision.** The one thing worth naming is operational, not structural: at T−0 a
  `session_start` pairing compresses three per-pairing rituals into one moment and one place —
  the pack forming, the owner→runner custody transfer, and the runner's `session_checkin` that
  stamps `checked_in_at` for every dog they hold (`0030:259`, §7.4). §7.4 already keeps
  the 현장 arm's evidence semantics byte-identical, so there are no new mechanics —
  but the *load* is real and it is the host's, and it grows with every owner who picks 현장.
- **The finish site is the start site, by the catalog's own model** — not by assumption.
  0078 records the course model in its header: 「카탈로그 행은 루프 자체만 담는다 (앵커에서 출발,
  앵커로 복귀)」 (`0078:7`), and every route carries exactly one anchor
  (`anchor_name`/`anchor_detail`, `0078:21-22`). So 「출발 지점」 and 「종료 지점」 name the same
  place, and copy implying two places would be false. ⚠ Two consequences for the screen session:
  `club_sessions.route_id` is **nullable** (`0030:56`) so the only always-present place string is
  `meetup_point` (`0030:57`, NOT NULL, already projected as `meetupPoint`, `0053:231`); and
  `anchor_lat/lng` are explicitly **forbidden from app consumption** until a founder walk confirms
  them (`0078:16`), so no on-site arm can carry a proximity check the way §7.4's 집 arm does.

### 16.7f RETIRED, and the distinction matters: the 「not too far」 question

His first message (`2026-08-25-return-point-and-round5.md:6-15`) said the owner may choose *"some
other address that's not too far"* — and note it attached that phrase to the **return** point,
not to pickup. His resolution then added a custom-address arm to **pickup** as well, and repeated
no distance language on either.

Earlier today a session recorded the constraint as *moot* because the resolution did not repeat
it, and then corrected itself: **not repeating a constraint is not retracting it**
(commit `9f80a53`). That correction was right, and this section must not be read as undoing it.

**What retires it is different in kind, and that is the point of writing it down:** verbatim ③
removes the **custom-address arm itself**. With no address other than the owner's own on either
leg, there is no subject for a distance rule to bound — you cannot tell an owner their own home
is too far. **The constraint dies because its feature died, not because he went quiet about it.**
An inference from silence and a retirement of the subject look identical in a summary and are
opposites in a spec; the first is what we got wrong this morning.

**Therefore: no OPEN card, and F6 does not return.** The consequence F6 carried — that a bounded
option is unenforceable because `addresses.lat/lng` are NULL until the owner pins (`0001:124-125`
nullable; `0065:29-33`'s CHECK passes on NULL by construction) — is now unreachable rather than
unanswered. ⚠ If verbatim ③ turns out to have been mis-relayed, **all of this reverts together**:
the custom-address arm, the distance question, and F6's enforceability consequence are one
package, and §16.7's provenance block flags ③ as the unverified line precisely so that check is
cheap.

### 16.7g The money is OPEN and untouched — **OPEN-F** (§14-OPEN)

Both on-site arms delete a runner leg. No number is proposed here, in either direction. The
shipped facts that bound the question — that no leg term exists in `club_fare` (`0043:14`) or in
the mint's decomposition (`0081:188-198`), so "unchanged" is what every shipped line already
computes and a cut would be a deliberate act against 「러너 지급을 조용히 깎지 않는다」 — are set
out at OPEN-F. Note there that the 현장 인계 half of this question has been open since 14.2; the
seventh round doubled it by decoupling return, it did not create it.

### 16.7h What this amendment did NOT do

- **No migration, no suite, no client file.** Documentation only; everything above is unbuilt.
- **No screen was designed.** The setup screen (self-run vs runner → pickup → session details →
  return) is another session's; this section owns only what the MODEL must support for it.
- **The return ritual was not touched** (§16.7d) and no arrival-receives-custody shape was
  introduced anywhere.
- **§8.6's disclosure-gate finding is NOT fixed here** — it is stated with a 🔵 fix shape and
  belongs to S4's adversarial cycle. It is latent today and armed by §8.1.
- **§10.2a's monitor is specified, not sequenced** — it hard-depends on §7.1's four stamps, which
  are themselves unbuilt.
- **Not addressed here, flagged for the next pass:** the coordinating session relays that Sean
  ruled at 09:03Z that host pair reassignment **stays**, which would revert §16.3 from PROVISIONAL
  and restore §6.6-orig as §6.6. ⚠ **This session did not verify that against origin and has
  changed nothing in §3, §6.6, §14.10 or §16.3** — a relayed decision is evidence, not authority,
  and the sections still read PROVISIONAL. Whoever executes that reversion owns the verification.

---

*The spec decides nothing Sean didn't say; every 🔵 is reversible in one word; every 🔴 blocks
only its own slice.*
