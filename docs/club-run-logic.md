# HIGH CLUB Group Run — Logic Spec v3.1 (canonical, self-contained)

> 2026-07-30 v3.1. Supersedes v2/v3 entirely — no prior version is required reading; shell and matrix rules
> are restated here in full. R0 (migration 0040) starts against THIS document after Sean's go.
> Reality note: delegation has never shipped to users (0037–0039 exist, UI never released, data = Sean's test
> rows). §14 defines rollout gates; deferral claims are made per-gate, never absolutely.

---

## 1. Per-dog stored model (the axes — payment stored once)

```
service_state      requested → approved → confirmed → in_service → ended
service_outcome    (set at ended) completed | partial | early_return | no_service | vet_transfer | cancelled
service_reason     code (owner_cancel / runner_capacity / no_show_owner / no_show_runner / safety / weather /
                   disclosure_false / assignment_failed / session_cancelled / other)
cancelled_by       owner | host | runner | system | ops   (when outcome=cancelled)

owner_charge_state    none → hold(deadline) → paid → refund_pending → refunded
                      | payment_failed | refund_failed        ← the ONLY stored charge truth
runner_payout_state   none → earned → payable → released | held | void

assignment_state   unassigned → proposed(runner, expires) → accepted | declined(reason) → unassigned…
                   accepted → revoked → replacement_needed → unassigned…
                   (attempts live in assignment_events — history, not overwritten)

custody_phase          with_owner → outbound_pending → with_custodian → transfer_pending
                       → return_pending → resolved
current_custodian_type owner | runner | host | clinic | authority | authorized_person
current_custodian_profile_id  (nullable — app users)
current_custodian_external    (nullable — name/contact for clinic·authority·pickup person)
                       ← ALL of this is a projection of dog_custody_events (source of truth)

service_contract_state  none → active(from payment) → void(refund completed / cancelled)
incident linkage        via incidents tables (§4) — per-dog "incident_state" is a PROJECTION (has-open-case)
```

- There is **no generic `payment_state` column** — any combined payment label is display projection over
  the two stored payment axes. (v3's duplication removed.)
- `responsible_*` projection matches custodian shape: `responsible_custodian_type` +
  `responsible_profile_id?` + `responsible_external_ref?`. **The invariant is: exactly one responsible
  custodian at all times, of any type** — a hospitalized dog's responsible custodian is the clinic, recorded,
  with the case owned by ops. (v3's nullable-profile hole closed.)

**Cross-axis invariants (RPC-enforced, harness-asserted):**
- `confirmed` ⇐ `owner_charge=paid`. `in_service` ⇐ `assignment=accepted` ∧ `custody=with_custodian(runner)`.
- **Custody transitions are never gated on charge state** (safety over commerce — an emergency transfer of
  any dog, even owner-attended or refund-pending, is always legal). Instead:
  **refund cannot COMPLETE (refund_pending→refunded) while that dog's custody is unresolved.**
- `service_state=ended` requires custody ∉ {outbound_pending, transfer_pending, return_pending} AND
  custodian is no longer a session runner (owner, authorized person, clinic, authority all qualify —
  hospitalization does not hold a session hostage; the case stays open under ops).
- Open incident on a dog ⇒ `runner_payout_state=held` for that booking + consent-free cancellation blocked.
- Insurance coverage is **policy-derived, not asserted**: `coverage` is a projection to be defined with the
  actual insurer agreement [gate-4 blocker, §14]; the spec makes no coverage claims of its own.

## 2. Assignment timeline & loop

- Proposals begin at runner check-in; **assignment target T-30** · owner review/objection cutoff **T-20** ·
  recovery window until **T-10 = hard stop**: any paid dog not `accepted` by T-10 → automatic full refund +
  banner/push + options. A paid dog structurally cannot be stuck.
- Proposal expiry 5m; declines recorded with reason in `assignment_events`; **an active proposal reserves the
  proposed runner's capacity** (§6) so two dogs can't chase one final slot.
- Owner may object to the accepted runner before handoff (first objection with stated cause = free; converts
  to refund or attend-mode). Runner may revoke before handoff → `replacement_needed` (+strike if habitual).
- **Convert-to-attend is an offer, never automatic**: requires owner physically attending + people & dog
  capacity + owner acceptance + owner-attended waiver. Otherwise refund. Move-to-next-session sets a
  priority flag on the next occurrence.

## 3. Session model

```
lifecycle  scheduled → checkin_open → in_progress → returning → ended
outcome    completed | completed_partial | completed_incident | cancelled_before_start | aborted_after_start
reason     weather / host_unavailable / runner_capacity / route_closed / safety / low_viability / other
```
- `ended` gate (contradiction from v3 resolved): every dog satisfies the §1 ended-custody rule, no run
  active, and every open incident has **safety actions complete + an ops case owner**. Then the meetup ends;
  investigations continue on their own clock. **Open incidents always block payout release; they block
  session end only until custody/runs/safety are resolved and ops owns the case.**
- Viability (per format): owner_only = min attending teams · delegated_only = min paid dogs AND ≥1 present
  runner · **mixed = attendance test AND coverage test (present+accepted capacity ≥ paid dogs)** — social
  component may proceed while the delegated component fails → outcome `completed_partial`, failed dogs
  resolved by the §2 hard stop.

## 4. Incidents — records, not a state

```
incidents           id, session_id, severity(S1 안전위협/S2 부상·분쟁/S3 경미), state open→investigating→resolved,
                    opened_by, case_owner(ops), opened_at, resolved_at, summary
incident_subjects   incident_id, subject_type(dog|person|session|booking), subject_id
incident_evidence   incident_id, kind(photo|text|location|document), payload, created_by, created_at
```
Multiple concurrent incidents per dog/session are first-class; a fight involving two dogs and three humans is
one incident with five subjects. Chat of the session is preserved as evidence while any case is open
(overrides the 24h archive rule). Disputes (handoff/return/payment) are incidents, never overrides.

## 5. Custody events, overrides, transfers

- `dog_custody_events`: from/to custodian (type + profile?/external?), event_type (outbound / return /
  emergency_transfer / vet_transfer / authority_transfer / host_witness / ops_attestation), initiated_by,
  **confirmation_kind ∈ {app_user, authorized_person_pin, host_witnessed_receipt, clinic_receipt,
  ops_attestation}**, occurred_at, location?, reason, evidence link. Non-app custodians confirm via PIN /
  photographed receipt / ops attestation — two-sidedness means *two artifacts*, not two RPC calls.
  Timestamps are the **operational** custody record; legal liability follows terms/insurance, and the spec
  does not claim otherwise.
- **Override taxonomy**: `witness_confirm` (host physically witnessed; requires host not a party to that
  edge + **at least one strong artifact**: one-time PIN from the absent party's registered phone, QR,
  signature capture, or timestamped photo) · `assisted_confirm` (the party themselves confirms on the host's
  device — their PIN/tap, not the host's) · **disputes are never overridable** → incident. Self-override
  banned (host-as-runner falls to backup host or ops).
- Emergency transfer: initiator → receiver acceptance (verification + remaining-cap + combination check);
  incapacitated-runner exception = host/ops attestation which auto-opens an S1/S2 incident.

## 6. Capacity — exact predicates, one lock

```
consumes_capacity(dog) := owner_charge ∈ {hold(unexpired), paid, refund_pending} ∧ service_state ≠ ended
reserved_session_capacity  := Σ consumes_capacity
available_for_approval     := promised_capacity(Σ committed caps) − reserved_session_capacity
runner_remaining_capacity  := verified_personal_cap − active accepted_assignments − active proposals
available_day_of           := Σ present committed caps − Σ accepted_assignments
```
- Refunded / cancelled / ended dogs release capacity by predicate, not by special-case code.
- **Law: every transition touching capacity or money takes the session row lock first** (approve, pay,
  hold-expiry, commit, withdraw, propose, accept, revoke, transfer). Cron and RPC serialize on the same
  lock; pay-vs-expiry is decided by lock order; all money/custody RPCs carry a client idempotency key and
  replays return the original result.
- Adaptive recovery after capacity loss: ≥24h→24h · 2–24h→60m · at check-in→15m · dog in custody→emergency
  path now. During recovery affected dogs display 자리 재확인 중. Personal caps are never exceeded to save a
  session. Runner no-show: late at T-30 → capacity-at-risk alerts + replacement invitations (beta: manual by
  host/backup); unresolved → §2 hard stop with compensation credit [amount: Sean].

## 7. Money

- Stored per booking: amount snapshot + pricing version (single source `club_fare()`; ctx.ts retired for club).
- Payout timeline: `earned` at run end (calculation) → `payable` at custody resolution → `released` at D+1
  batch → `held` by incident → `void` on ownerless outcomes. Charge finalization, payout calculation, payout
  release, record closure = four distinct moments; "settled" is not a word this system uses.
- **Fee destinations & triggers (recipients now defined; amounts = Sean):**
  - Late-cancel/no-show fee: 50% `fee_platform`, 50% `fee_supply_compensation` → the dog's **accepted runner**
    if one existed at the time; otherwise pro-rata across **present committed runners** by present cap; if
    none present, 100% platform. [ratios = Sean-tunable]
  - `host_fee`: earned when the session reached `in_progress` and outcome ∈ {completed, completed_partial,
    completed_incident} — independent of whether the host handled dogs; single line per session; splits
    equally if hosting was assumed mid-session (original + backup, pro-rata by phase). Not earned for
    cancelled_before_start; aborted_after_start earns 50%. [amounts = Sean; 0 during mock era — no fake money]
  - Owner cancel ladder (defaults, Sean tunes): free until paid · paid ≥24h free · <24h 10% · after
    acceptance 20% · after handoff = early-return settle, not a cancel. No-show = ladder top + strike.
- Real-PG integration is its own project (authorize/capture/void, webhooks, dedup, receipts, reconciliation);
  the axes above are its landing shape, and no stronger claim is made.

## 8. Session shell (restated in full — self-contained)

- **개요 · 참가자 · 채팅** are fixed tabs of every session screen, every stage, for every authorized
  participant: host/backup, committed runners, attending owners, owners with any delegation record
  (including pending). Rejected/expired requesters keep read access to their own record only. Public: 개요 only.
- **Chat**: writable from first participation until all dogs' custody resolved + 24h (open incidents extend);
  then read-only archive, permanently attached to the session. Empty room shows one system line (time +
  meetup) — real data only. Participants who leave/are removed lose write, their past messages remain.
  Pilot moderation: report → host flag + ops; block hides locally; delete-own within 5 min; photos allowed;
  simple rate limit. Push: host announcements ON, mentions ON, system-critical ALWAYS, ordinary configurable
  (default OFF).
- **Roster**: capability-aware. Host sees all humans+dogs with per-dog stage/badges, charge labels
  (read-only), custody, assignment, safety flags, capacity meter. Runner sees own dogs in full detail
  (medical/behavior limited to host + that dog's runner), group overview, other runners+assignments. Owner
  sees host, runner pool, own dog full record, others per consent. **Phones — rule B**: host ↔ everyone;
  owner ↔ their accepted runner mutual; else 호스트 경유 relay. Visibility = confirmed participation until
  own handoffs resolved + grace (lifecycle-based, not clock-based); reveals are consent-gated at
  join/payment and access-logged. Emergency contact + authorized-pickup contact are separate fields captured
  at consent.
- **Critical notifications** (assignment result, location/time change, cancellation, capacity collapse,
  emergency, return overdue, payment deadline) additionally render as **persistent in-app banners in the
  shell requiring acknowledgement**; unacknowledged past threshold → escalate to host/ops. Delivery/open
  analytics = later; ack is now.

## 9. Board projection — structured payload, not a label

The board RPC returns per dog (and per session) a **UI-state object**; precedence lives in ONE server function:
```
primary_stage      Korean label (신청 대기 · 승인—결제 대기 · 결제 완료—배정 대기 · 러너 수락 대기 · 인계 대기 ·
                   러너 보호 중 · 러닝 중 · 반환 대기 · 완료 …)
secondary_badges   [환불 처리 중, 인시던트 확인 중, 자리 재확인 중, 결제 실패, …]
blocking_issue     what stops forward motion (nullable)
required_actor     owner | host | runner | ops | none
allowed_actions    from the action matrix (server-computed for the viewer's capabilities)
severity           info | warn | critical   (drives banner styling)
```
Flap letters remain flavor beside `primary_stage`, never alone on money/safety states.

## 10. Capabilities & action matrix (restated in full)

Capabilities per user per session (derived, no schema rewrite): `is_host` (incl. assumed backup) ·
`is_handling` (committed) · `is_attending` · `owns_participating_dog` · `is_authorized_pickup` · `is_ops`.
A user matches every applicable row; UI renders the union. Roster+chat available in **every** row.

**Canonical rows** (per dog unless noted):

| Stage | is_host | owns_dog | is_handling |
|---|---|---|---|
| requested | 승인/거절(+사유) | 요청 수정/취소 | 수요 보기 |
| approved(hold) | 결제 대기 라벨 | **결제하기**(기한) | — |
| paid/unassigned | 배정 제안 | 상태 보기 | 수락 대기 |
| proposed | 제안 변경 | 러너 후보 카드 | **수락/거절(사유)** |
| accepted→handoff | 관찰/중재(witness·assisted) | 인계 확인+체크리스트 | 인계 확인+체크리스트 |
| in_service | 세션 콘솔·SOS | 라이브·채팅 | 러닝·이벤트·SOS |
| run_done→return | 관찰/중재 | **반환 확인** | **반환 확인** |
| ended | 리캡 발행(세션) | 리뷰/공유 | 리뷰/공유 |

**Exception rows**: payment_failed/expired → owner 재시도/재신청, host label only · declined/replacement →
host 재제안, runner pool 수락 · capacity-at-risk/자리 재확인 중 → host 대체 초대·창 관리, owner 옵션(대기/
전환/환불), runner 캡 내 수락 · owner no-show → host 노쇼 처리, runner 배정 해제 통지 · runner no-show →
§6 대체 플로우 · handoff/return dispute → **incident only** (진술 제출 양측) · incident open → host 콘솔·
owner 열람·runner 보고/증빙 · refund_pending/failed → labels + ops alert on failure · aborted_after_start →
host 사유 기록·개별 정리 · host absent → backup assume_host · emergency transfer → 개시/양측 수락.

## 11. GPS & records

- `dog_run_segments` (runner, run/trace ref, joined_at, left_at, transfer_event): a dog's record = its
  segments; transfers, pace-splits, late joins are segment boundaries; no inherited history.
- **Baseline integrity ships before any real delegated run** (moved out of the PG milestone):
  impossible-speed rejection, jump filter (exists — smoothing), stale-fix detection + honest "n분 전 위치",
  server-authoritative timestamps, sequence validation, segment-overlap validation. Advanced anti-cheat later.
- Session-level events (start/pause/returning/end) separate from per-dog events. Runner metrics: one physical
  run = +1 run/distance/drop-cadence; dogs served = +N (separate counter); payouts per booking.

## 12. Consent & eligibility

- `delegation_consents` immutable rows: doc id+version, dog, session, booking, vet-payment authorization
  limit ₩[Sean], photo consent (revocable forward-only), custody acknowledgement, authorized-pickup person,
  emergency contact. **Material change** (time >±30m, meetup, price, route distance class, waiver version) →
  re-accept by deadline else free-cancel+refund. Runner identity change → notify + free-cancel right.
- Request carries disclosures (weight/energy/reactivity/bite/medical/equipment). Edits after approval reset
  to `requested`. Runner acceptance shows the **combination** with already-accepted dogs. **Physical gate at
  handoff**: checklist (equipment, condition, combined load); refusal-at-handoff → disclosure false = owner-
  fault cancel (+strike) else full refund + credit.

## 13. Choke point & drift control (enforced, not conventional)

- `marketplace_open_requests` view becomes the only pool read path: bookings RLS tightened to
  **parties-only** (owner/runner of the row) + pool reads via the granted view; app queries migrated in the
  same slice; harness leak tests assert club bookings are invisible through every exposed path and that
  non-party direct reads fail.
- Documented mapping `axes ↔ bookings.status` + reconciliation query as harness case AND cron drift check
  (logs, never mutates). Old `approval` column: backfill → one-slice dual-write → drop; harness asserts sync.
- Feature flag `club_delegation` server-checked in every RPC; OFF for non-test accounts until backend AND
  shell UI complete. Rollback = flag off. (Pre-launch: no old clients exist; the discipline ships anyway.)

## 14. Rollout gates (replaces vague "pilot-ok")

1. **G1 DB simulation** (harness only) — current.
2. **G2 Sean two-role device testing, no real custody** — requires R0–R3 + debug UI.
3. **G3 real-world owner-attended social pilot** — requires shell UI, roster/chat, viability, no delegation.
4. **G4 closed delegated beta (known participants, real dogs)** — requires ALL of: R0–R6, emergency minimum
   incl. offline info card + contact hierarchy, mandatory backup-host rule for delegated sessions, honest
   support-hours display (no fictional 24/7 운영팀), insurer-confirmed coverage rules, return-dispute
   procedure, GPS baseline integrity, consent docs reviewed.
5. **G5 public delegated launch** — real PG + reconciliation, ops tooling, notification analytics, the §15 register.
Backup host: optional at G2–G3, **mandatory for delegated sessions from G4**.

## 15. Known-unmodeled register (tracked; gate at which each blocks)

Chat moderation depth/ack receipts (G5) · phone access-log UI (G4) · push delivery analytics (G5) ·
multi-incident triage UI (G5) · insurance notification workflow (G4) · tax/receipts (G5, PG) · masked calling
(G5) · auto-compatibility scoring (G5) · series 7–14d visible generation (G4) · weather automation (G5) ·
membership-governance long tail (G5; the invariant that **service obligations survive membership changes** is
already canonical).

## 16. Build order (thin UI per slice — no big-bang)

Each slice = migration + harness green + drift green + **a dev-flagged debug screen exercising the flow**
(critique 19 adopted: human-flow validation never waits for R6).
- **R0 (0040)**: axis columns (§1 exactly) + backfill + dual-write sync + structured projection function +
  `marketplace_open_requests` view + RLS tightening + app query migration + flag plumbing + drift harness case.
- **R1 (0041)**: charge axis live (hold 20m → owner pay RPC creates booking, idempotent; expiry cron; host
  read-only labels) + capacity predicates under the lock. Debug UI: approve vs pay.
- **R2 (0042)**: custody events (custodian types, confirmation kinds) + two-sided return + overrides +
  transfers + ended-gating + payout earned/payable/released/held. Debug UI: custody board.
- **R3 (0043)**: assignment loop + timeline (T-30/-20/-10) + proposal reservation + adaptive recovery +
  no-show flows + backup/assume_host. Debug UI: assignment timeline.
- **R4 (0044)**: consents + disclosures/physical gate + viability v3 + dog caps + cancel/fee ledger recipients
  + metrics split + membership separation w/ obligation invariant. Debug UI: consent+eligibility.
- **R5 (0045)**: shell backend (chat, capability roster, phone rule B, ack-required banners). Debug UI: shell.
- **R6 (0046)**: incidents tables + SOS + severity + contact hierarchy + evidence + GPS baseline integrity +
  segments + series occurrence identity (`series_id + original_scheduled_start`, stable through reschedule)
  + adversarial harness class (permission-leak, idempotency replay, out-of-order, stale-client, 2-connection
  races for last-slot/pay-vs-expiry/withdraw-vs-pay). Debug UI: emergency flow.
- Then production UI on lab v3 direction, gate G2 onward.

*Sean's open numbers (architecture independent): fee split ratios & ladder amounts · host_fee amount ·
compensation credit · vet authorization default limit · window tuning · chat push defaults.*
