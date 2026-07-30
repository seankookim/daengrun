# HIGH CLUB Group Run — Logic Spec v3.3 (canonical, self-contained — R0A approved)

> 2026-07-30 v3.3 (= v3.2 + five final inline corrections from round 5). Supersedes all prior versions.
> **Acceptance standard** (the completeness bar this spec is held to, in place of "every scenario"):
> ① independent truths modeled independently ② safety invariants hold under every transition ③ external
> side effects idempotent & auditable ④ unknown scenarios can always enter a safe incident/ops state
> ⑤ money never releases before physical responsibility is resolved ⑥ no actor gains capabilities through
> UI state ⑦ the known-unmodeled register is tied to rollout gates (§15).
> Pre-launch reality: delegation never shipped; data = Sean's test rows. Build starts at R0A on Sean's go.

---

## 1. Object model (authoritative table per concern)

| Concern | Authoritative source |
|---|---|
| Club membership | club_members |
| Session hosting | club_sessions.host_profile_id (+ assume_host events) |
| Attendance (humans) | session_people |
| Dog participation (ALL dogs) | session_dogs (`participation_mode` owner_handled \| runner_delegated) |
| Handling commitment & caps | session_runner_assignments |
| Assignment attempts | assignment_events (history; current = latest) |
| Money (charge/refund/payout) | bookings + payment_attempts + ledger_items |
| Physical responsibility | dog_custody_events (history; session_dogs custodian columns = cached projection) |
| Incidents | club_incidents / club_incident_subjects / club_incident_evidence (`club_` prefix — 0001 owns a booking-level `incidents` table) |
| Run records | runs + dog_run_segments |
| Consent | delegation_consents (immutable) |

Humans live in session_people; dogs in session_dogs; money on bookings; responsibility in custody events.
No polymorphic mixing.

## 1b. Logical ↔ physical name map (implementation contract)

The spec uses logical names; SQL references **physical names only** until the cleanup rename slice.
Verification queries must be written against the physical column.

| Logical (spec) | Physical (schema) | Note |
|---|---|---|
| participation_mode | `session_dogs.custody` | 0042 adds `participation_mode` as a GENERATED read-only alias (query-only, never written); true rename happens in the cleanup slice after v1 RPCs retire |
| incidents / incident_subjects / incident_evidence | `club_incidents` / `club_incident_subjects` / `club_incident_evidence` | 0001 owns a booking-level `incidents` table |
| hold(deadline) | `hold_status` + `hold_expires_at` | |
| payout_hold(reason, incident) | `payout_hold` + `payout_hold_reason` + `payout_hold_incident` | |
| assignment proposed(runner, expires) | `assignment_state` + `current_runner_profile_id` + `proposal_expires_at` | events in `assignment_events` |
| custodian projection | `custodian_type` / `custodian_profile_id` / `custodian_external` + `custody_phase` | v1-era: `responsible_profile_id` remains the v1 truth until R2 retires it |
| new attempt link | `previous_attempt_id` | partial-unique lands in R1 |

**Rule for R0B and later slices: no SQL or app code references `participation_mode` as a base column
until the cleanup rename migration; reads use `custody` (or the 0042 alias once applied).**

## 2. Per-dog stored model

**ALL participating dogs** (both modes) carry: custody projection + custody events + incident linkage.
**Delegated dogs only** add: charge/refund/payout, assignment, consent, booking. (Safety infrastructure
never depends on payment category — an owner-attended dog can be emergency-transferred, hospitalized,
investigated.)

```
participation_mode   owner_handled | runner_delegated

service_state        requested → approved → confirmed → in_service → ended       (delegated only)
completion_outcome   (at ended) completed | partial | no_service
termination_type     (at ended) normal | early_return | cancelled | vet_transfer | session_aborted
service_reason       code (host_rejected / owner_cancel / runner_capacity / no_show_owner / no_show_runner /
                     safety / weather / disclosure_false / assignment_failed / session_cancelled / other)
cancelled_by         owner | host | runner | system | ops        (when termination=cancelled)

charge_state         none → hold → paid
                     **CACHED PROJECTION (0043/0044): authoritative charge truth = hold columns +
                     bookings + payment_attempts; charge_state is derived (paid ⇔ booking exists,
                     hold ⇔ unexpired active hold) and drift-checked like every cache.**
hold_status          none | active(expires_at) | consumed | released | expired
                     (hold columns are RPC-owned PRIMARY storage from R1)
refund_state         none → pending → refunded | failed          (refund never erases that charge was paid)
payout_state         none → earned → payable → released | void
payout_hold          none | held(reason, incident_id)            (overlay — earned+held, payable+held valid)
payment_attempts     history of SUCCESSFUL/idempotent DB operations (attempt id, idempotency key,
                     kind(charge|refund), result, at) — ordinary DB failures cannot persist here
                     (rollback); external PG failure history = the later payment-wrapper's table

assignment_state     unassigned → proposed(runner, expires) → accepted | declined → unassigned…
                     accepted → revoked → replacement_needed → unassigned…
                     **assignment_events is authoritative; assignment_state + current runner columns are
                     cached projections (same rule as custody). Assignment drift is a harness+cron
                     reconciliation check alongside booking-status drift.** An active proposal RESERVES
                     the proposed runner's load.

custody: custodian_type  owner | runner | host | clinic | authority | authorized_person
         custodian_profile_id? / custodian_external?             (projection of custody events)
         custody_phase  with_custodian → outbound_pending | transfer_pending | return_pending → (loops)
```

- **Custodian = responsible party. One projection, one concept** (v3.1's duplicate `responsible_*` removed):
  whoever holds the dog holds the responsibility; escape doesn't vacate it (last custodian remains until an
  accepted transfer). UI "책임자" renders the custodian.
- **`service_contract_state` removed** — contract status is derived (paid ∧ not refunded ∧ not ended-void).
- **Hold expiry is real-time, never cron-dependent**: every capacity predicate evaluates
  `hold_status='active' AND hold_expires_at > now()` directly — a hold frees capacity the second it
  expires; the */5 cron only stamps `expired` + notifies. Pay-after-expiry re-checks capacity and
  proceeds inside ONE session-locked transaction — no intermediate hold row is ever left behind
  (failure = full rollback, zero partial commercial state; in-DB failure-attempt persistence is
  impossible under rollback — external recording is the real-PG wrapper's job).
- **Hold expiry is deterministic**: `hold_status=expired`, `charge_state→none`, capacity freed by predicate;
  `service_state` stays `approved` (approval = eligibility; only holds/payment reserve). Owner may retry
  payment via the pay RPC, which re-checks capacity and opens a fresh hold under the session lock. Board
  shows 기한 만료 from hold_status. No host re-approval needed.
- **Host rejection stored**: ended + no_service + cancelled + reason=host_rejected + cancelled_by=host +
  note. **`ended` is immutable** — reversal never mutates it back: a host reversal (or permitted owner
  re-request after reversal) creates a **new request attempt row** linked to the rejected one
  (`previous_attempt_id`); the unique-active constraint becomes partial (one ACTIVE row per session+dog).
  Rejection history is preserved verbatim; still per-occurrence only.

**Cross-axis invariants** (RPC-enforced, harness-asserted):
- confirmed ⇐ charge=paid ∧ hold=consumed. in_service ⇐ assignment=accepted ∧ custodian=(that runner).
- Custody transitions never gated on charge (safety over commerce). **refund pending→refunded requires that
  dog's custody resolved.** payout released requires custody resolved ∧ payout_hold=none.
- ended requires custody_phase ∉ {outbound_pending, transfer_pending, return_pending} ∧ custodian_type ∈
  **terminal allowlist {owner, authorized_person, clinic, authority}**. `host` and `runner` custodians are
  NEVER a resolved terminal state — unless that person is separately recorded as the dog's owner or
  authorized pickup. (Hospitalization doesn't hold the session; the case stays open under ops.)
- Open incident on a dog ⇒ payout_hold=held ∧ consent-free cancellation blocked.
- Insurance coverage = insurer-agreement projection, undefined until confirmed [G4 blocker].

## 3. Money events & fees

- Charge finalization, payout calculation (earned @ run end), payout eligibility (payable @ custody
  resolved), payout release (D+1 batch) are four moments; "settled" is not in the vocabulary.
- Fee destinations (amounts = Sean): late-cancel/no-show → 50% fee_platform · 50% fee_supply_compensation
  (accepted runner if one existed; else present committed runners pro-rata by present cap; else platform).
  host_fee: session reached in_progress ∧ outcome completed/completed_partial (aborted_after_start 50%);
  split pro-rata if hosting was assumed mid-session. Owner cancel ladder defaults: free till paid · ≥24h
  free · <24h 10% · post-acceptance 20% · post-handoff = early-return settle. No-show (outbound never
  completed by cutoff) = ladder top + reliability strike. Mock era charges nothing, records everything.
- Real-PG (authorize/capture/void, webhooks, receipts, reconciliation) is its own project; these axes are
  its landing shape — no stronger claim.

## 4. Session model

```
lifecycle  scheduled → checkin_open → in_progress → returning → ended
outcome    completed | completed_partial | cancelled_before_start | aborted_after_start
reason     weather / host_unavailable / runner_capacity / route_closed / safety / low_viability / other
```
- ~~completed_incident~~ removed — incident presence is derived from linked cases (no duplicate truth).
- ended gate: every dog passes the §2 ended-custody rule ∧ no active run ∧ every open incident has safety
  actions complete + an ops case owner. Incidents always block payout release; they block session end only
  until custody/runs/safety resolve. Meetups and investigations run on different clocks.
- Viability per format: owner_only = min attending teams · delegated_only = min paid dogs ∧ ≥1 present
  runner · mixed = attendance test ∧ coverage test (present+accepted load headroom ≥ paid dogs). Social
  part may proceed while delegation fails → completed_partial + §5 hard stop resolves failed dogs.

## 5. Assignment (Model A — fixed)

**Host proposes → runner accepts → owner sees the confirmed runner card and holds an objection right until
handoff.** While merely proposed, the owner sees 배정 진행 중 — no candidate card (runner privacy; declines
stay invisible churn). Matrix and schema agree on this everywhere.
- Timeline: proposals from runner check-in · target T-30 · **objection rules split**: ordinary
  preference-based objection until T-20 (free once with stated cause → refund or attend-offer); material
  safety/identity/disclosure objection allowed until outbound handoff; after handoff never a cancel — early-
  return or incident flow only · recovery to **T-10 hard stop**: paid ∧ not accepted →
  automatic full refund + options (attend-conversion OFFER: requires owner attending + people & dog capacity
  + acceptance + waiver; or next-session priority). A paid dog structurally cannot be stuck.
- Proposal expiry 5m; declines with reason; revoke-before-handoff → replacement_needed (+strike if habitual).

## 6. Capacity — the full family (restored) + load-based safety

```
people_capacity                 session column (2–60); consumed by session_people
total_dog_capacity              session column (default = people_capacity); ALL participating dogs
owner_handled_dog_limit         per attending owner (default 2)
handler_tier_cap                certified 1 · veteran/master 2 · applicant 0   (verified personal cap)
handler_load(person)            ALL dogs physically controlled: own attending dog(s) + accepted delegated +
                                emergency-transferred. **handler_load ≤ handler_tier_cap + 0** — own dogs
                                count; a veteran with their own dog has 1 delegated slot. [Sean may tune]
promised_capacity               Σ committed handlers' (tier_cap − own attending dogs)
consumes_delegated(dog)         hold=active ∨ (charge=paid ∧ refund≠refunded ∧ service≠ended)
available_for_approval          promised − Σ consumes_delegated
present_capacity                same sum over checked-in committed handlers
available_day_of                present − accepted assignments − **active proposals**
```
- **Per-runner enforcement is primary** (aggregates are overview only): every assignment, proposal, and
  transfer checks `runner_current_load + active_proposals + requested_transfer_load ≤ verified_handler_cap`
  for that runner — an aggregate can look safe while one runner is overloaded.
- Law: every capacity/money transition takes the session row lock first (approve, pay, expiry, commit,
  withdraw, propose, accept, revoke, transfer); cron and RPC serialize on it; idempotency keys on all
  money/custody RPCs (replay returns original result).
- Adaptive recovery on capacity loss: ≥24h→24h · 2–24h→60m · at check-in→15m · in-custody→emergency now;
  affected dogs show 자리 재확인 중; caps never exceeded to save a session. Runner late at T-30 →
  capacity-at-risk alerts + manual replacement invites; unresolved → §5 hard stop (+credit [Sean]).

## 7. Custody events, overrides, transfers

- dog_custody_events: from/to (custodian type + profile?/external?), event_type (outbound / return /
  emergency_transfer / vet_transfer / authority_transfer), initiated_by, confirmation_kind {app_user,
  authorized_person_pin, host_witnessed_receipt, clinic_receipt, ops_attestation}, occurred_at, location?,
  reason, evidence link. Two-sidedness = two artifacts, not two RPC calls. Operational record only — legal
  liability follows terms/insurance.
- Overrides: witness_confirm (host not a party + ≥1 strong artifact: absent party's one-time PIN / QR /
  signature / timestamped photo) · assisted_confirm (the party confirms on host's device) · disputes never
  overridable → incident · self-override banned (host-as-runner → backup/ops).
- Transfers: initiator → receiver acceptance (verification + load headroom + combination check);
  incapacitated-runner exception = host/ops attestation, auto-opens incident.
  **Runner→runner transfer is ONE atomic transaction** (assignment truth can never diverge from custody):
  ① close runner A's assignment interval (assignment_event: replaced) ② verify runner B eligibility +
  `runner_current_load + active_proposals + requested_transfer_load ≤ verified_handler_cap` ③ create+accept
  replacement assignment event for B ④ record the custody transfer event ⑤ open a new dog_run_segment under
  B ⑥ notify owner + host. **Clinic/authority transfers instead end or suspend the service** (termination_type
  vet_transfer / appropriate) — a clinic never becomes an "assigned runner".

## 8. Incidents (schema lands in **R0A** — earlier slices depend on it)

incidents (severity S1/S2/S3, state open→investigating→resolved, opened_by, case_owner, summary) ·
incident_subjects (dog|person|session|booking) · incident_evidence (photo|text|location|document).
Multiple concurrent cases first-class; disputes are incidents; chat preserved as evidence while open
(overrides archive clock). SOS/severity UI/contact hierarchy wiring completes in R6, tables exist from R0A.

## 9. Session shell & communication

- 개요·참가자·채팅 tabs on every session screen, every stage. **Access requires actual participation**:
  requested/expired/rejected → own record + 개요 + a limited host-message channel only (no group chat —
  requesting is not a door into a private room); approved/paid/confirmed owners, attending owners, committed
  runners, host/backup → full roster + group chat; public → 개요.
- **Private channel preserved**: the existing per-booking owner↔runner chat continues alongside group chat
  (health details, arrival, pickup person, disputes). Shell shows 그룹 채팅 · 담당 러너와 대화 (once accepted).
- Chat lifecycle: writable from participation until all own-relevant custody resolved + 24h (incidents
  extend); read-only archive permanently attached. Moderation (pilot): report→host+ops flag, local block,
  delete-own 5m, photos, rate limit. Push: host announcements ON · mentions ON · system-critical ALWAYS ·
  ordinary configurable (default OFF).
- Roster: capability-aware (host: everything incl. read-only charge labels, custody, flags, capacity meter;
  runner: own dogs full detail — medical/behavior limited to host + that dog's runner — plus group overview;
  owner: host, runner pool, own dog full, others per consent). Phones rule B (host↔all; owner↔accepted
  runner; else 호스트 경유), lifecycle-scoped visibility, consent-gated, access-logged; emergency contact +
  authorized-pickup captured at consent.
- Critical notifications (assignment result, location/time change, cancellation, capacity collapse,
  emergency, return overdue, payment deadline) = push AND persistent ack-required shell banner; unacked →
  escalate host/ops.

## 10. Board projection — structured, plural

```
primary_stage      Korean label (one per §2 combination; flaps = flavor beside it, never alone)
secondary_badges   [환불 처리 중, 인시던트 확인 중, 자리 재확인 중, 결제 실패, 기한 만료, 재검토 중 …]
blocking_issues[]  + primary_issue (visual precedence)
required_actors[]  (handoff/return = [owner, runner]; transfer = [sender, receiver]; …)
allowed_actions    server-computed for the viewer's capabilities
severity           info | warn | critical
```
One projection function; capabilities per user (is_host incl. assumed, is_handling, is_attending,
owns_participating_dog, is_authorized_pickup, is_ops) derived from authoritative tables; UI renders the
union of matching matrix rows (canonical + exception rows as v3.1 §10, updated: `proposed` row shows the
owner 배정 진행 중, not a candidate card).

## 11. Timing & scheduling (canonical table — self-contained)

| Rule | Value (config; ordering fixed) |
|---|---|
| Creation min notice | owner_only 2h · delegation-enabled 24h |
| Series generation | ≤72h ahead, hourly; occurrence key = series_id + original_scheduled_start (stable through reschedule); snapshot route/price/rules at generation; exception dates; edits touch future-unpaid only; pause keeps existing sessions |
| Delegation prerequisites | route required (fare must be computable); requests allowed at zero capacity (demand queue — approval consumes) |
| Runner check-in | T-45m .. T-10m (late at T-30 → capacity-at-risk) |
| Participant check-in | T-45m .. T+15m |
| Assignment | proposals from runner check-in · target T-30 · preference objection T-20 (safety: until handoff) · hard stop T-10 |
| Outbound handoff | T-30m .. T+15m (physical checklist embedded) |
| Payment hold | 20m from approval |
| Return grace | 60m after run end → escalation (host alert → incident) |
| Recovery windows | adaptive table §6 |
| Host absence | not checked in T-30 → alert backup/ops; absent at T → assume_host or ops-cancel |
| Stale session | host reminder T+12h · ops alert T+24h · admin close-out; never automatic custody transfer |

**Conflict guards (restored)**: overlap checks for dog bookings (exists), runner private bookings, runner/
host/owner club sessions — using planned duration (route-based) + prep/travel buffers (beta constant 25m),
same formula everywhere. One human or dog cannot be committed in two places.

## 12. Consent, eligibility, edits

- delegation_consents immutable (doc id+version, dog, session, booking, vet-payment limit ₩[Sean], photo
  consent revocable-forward, custody acknowledgement, authorized-pickup person, emergency contact).
  Material change (time >±30m, meetup, price, route class, waiver version) → re-accept by deadline else
  free-cancel+refund. Runner change → notify + free-cancel right.
- **Field-materiality for dog edits** (paid dogs never return to `requested`): safety-critical fields
  (weight class, reactivity, bite, medical, equipment requirement) → assignment revoked + 재검토 badge +
  host re-review by min(48h, T-10): approve → continue (payment stays captured, capacity stays reserved) ·
  reject → automatic full refund. Cosmetic fields (name/photo/notes) → no reset.
- Physical gate at handoff: checklist (equipment, condition, combined load); refusal → disclosure false =
  owner-fault cancel (+strike) else full refund + credit. Runner acceptance always shows the combination
  with already-accepted dogs.

## 13. GPS & records

dog_run_segments (runner, run ref, joined_at, left_at, transfer_event) — a dog's record is its segments;
no inherited history. Baseline integrity **before any real delegated run** (R6, not PG-gated):
impossible-speed rejection, jump filter, stale-fix display ("n분 전 위치"), server-authoritative timestamps,
sequence validation, overlap validation. Session events (start/pause/returning/end) ≠ per-dog events.
Runner metrics: one physical run = +1 run/distance/drop-cadence; dogs served = +N; payouts per booking.

## 14. Choke point & rollout mechanics

- **R0A** (schema only): axis columns per §2 + participation_mode + custody/incident/assignment-event/
  payment-attempt/segment tables + backfill from `approval` + dual-write sync + structured projection +
  flag plumbing + drift reconciliation (harness case + cron, logs only).
- **R0B** (access change, separate slice): `marketplace_open_requests` view — column allowlist (no owner
  address/health/payment fields), security-invoker semantics audited (or an RPC instead), base-table pool
  reads denied via parties-only RLS, full inventory of existing marketplace queries migrated, service-role
  preserved, leak tests (each role × every exposed path; club bookings invisible everywhere; non-party
  direct reads fail). R0B acknowledges it touches the live marketplace read path — it is not "pure schema".
- Feature flag `club_delegation_v2` server-checked in delegation entry RPCs; OFF globally until
  backend+shell complete; rollback = flag off. **Testing never flips the global flag**: a
  `club_test_accounts` allowlist (service-role managed) grants per-account entry while global stays OFF. Old `approval` drops in cleanup slice after dual-write parity is asserted.

## 15. Rollout gates & register

G1 harness-only (current) · G2 Sean two-role device tests, no real custody (needs R0A–R3 + debug UIs) ·
G3 real owner-attended social pilot (needs shell UI; no delegation) · G4 closed delegated beta (needs ALL
R-slices, emergency minimum + offline info card, mandatory backup host for delegated sessions, honest
support-hours display, insurer-confirmed coverage, return-dispute procedure, GPS baseline, reviewed consent
docs, conflict guards) · G5 public (real PG + reconciliation, ops tooling, analytics, register below).
Register (gate-tagged): chat moderation depth/ack receipts (G5) · phone access-log UI (G4) · push analytics
(G5) · multi-incident triage UI (G5) · insurance workflow (G4) · tax/receipts (G5) · masked calling (G5) ·
auto-compatibility (G5) · series 7–14d visibility (G4) · weather (G5) · governance long tail (G5; the
invariant that service obligations survive membership changes is canonical now).

## 16. Build order (each slice: migration + harness + drift + debug UI)

R0A schema (§14) → R0B choke point → R1 charge/hold/refund live (approve=hold 20m, pay RPC creates booking
idempotently, expiry, host labels, capacity predicates) → R2 custody events + returns + overrides +
transfers + ended-gating + payout lifecycle/holds (incident tables already exist) → R3 assignment loop +
timeline + proposal reservation + recovery + no-show + backup/assume_host → R4 consents + eligibility/edits
+ viability + capacity family + fee ledger + metrics split + membership separation (RSVP ≠ join; guest RSVP;
obligations survive membership changes) → R5 shell backend (group chat + private channel + capability roster
+ phones B + ack banners) → R6 incident wiring/SOS/severity/evidence + GPS baseline + segments + series
occurrence identity + adversarial harness (permission-leak, idempotency replay, out-of-order, stale-client,
2-connection races: last-slot pay, pay-vs-expiry, withdraw-vs-pay) → production UI (lab v3 direction), G2+.

*Sean's open numbers: fee ratios/ladder · host_fee · credit amounts · vet limit · window tuning · chat push
defaults · handler-load own-dog rule tuning (§6).*
