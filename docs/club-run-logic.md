# HIGH CLUB Group Run — Logic Spec v3 (orthogonal-state architecture)

> 2026-07-30 v3. Supersedes v2 after second-round critique (26 sections). Central correction adopted:
> **v2's single `session_dogs.state` conflated five independent systems.** v3 stores orthogonal axes and
> derives display. R-work does not start until Sean approves this document.
> Honest scope note: **delegation has never shipped to users** — 0037–0039 exist in DB but no UI was ever
> released; the only data is Sean's test rows. Migration-compatibility machinery is scoped to that reality
> (§11), not to a live-marketplace fiction. Completeness claims are retired; §12 is a living
> known-unmodeled register.

---

## 1. The orthogonal per-dog model (replaces v2 §1)

Five stored axes on a delegated `session_dogs` row. No axis ever encodes another axis's information.

```
service_state     requested → approved → confirmed → in_service → concluded(outcome) | cancelled(actor, reason)
payment_state     none → hold(deadline) → paid → refund_pending → refunded   | payment_failed | refund_failed
assignment_state  unassigned → proposed(runner, deadline) → accepted | declined(reason) → unassigned…
                  accepted → revoked → replacement_needed
custody_state     owner → outbound_pending → runner → transfer_pending → return_pending → returned
                  (projection of dog_custody_events — events are the source of truth, column is a cache)
incident_state    none | open(severity) | investigating | resolved   — orthogonal condition, any time, any axis
```

**Cross-axis invariants** (enforced in RPCs, asserted by harness):
- `confirmed` requires `payment_state=paid`. `in_service` requires `assignment=accepted` AND `custody=runner`.
- `custody ∈ {runner, return_pending, transfer_pending}` requires `payment=paid` (insurance never covers unpaid).
- `concluded` requires `custody=returned` (v2's central fix, restated as an invariant).
- `incident=open` blocks: payout release, session end for this dog, consent-free cancellation.
- Money mutations require payment-axis transitions only; custody mutations require custody events only.

**Display is a projection**, not a state: one server-side function (board RPC) maps the axis tuple to the
single Korean stage label the UI shows (신청 대기 · 승인—결제 대기 · 결제 완료—배정 대기 · 러너 수락 대기 ·
인계 대기 · 러너 보호 중 · 러닝 중 · 반환 대기 · 완료 · + exception labels 결제 실패/기한 만료/재배정 중/
환불 처리 중/인시던트 확인 중). Flap letters remain flavor beside the Korean label. One projection function =
one place to fix wording; `incident` overlays as a banner, never replaces the stage.

**Payment sub-axes** (critique 12/13 adopted): `owner_charge_state` (none/hold/authorized*/captured*/refund_*)
and `runner_payout_state` (none → earned@run_done → payable@returned → released@D+1 | held@incident).
Mock today implements hold/paid/refund_pending + earned/payable/released flags; authorize/capture/void/webhook
handling is **the real-PG project** — v2's claim that a PG "slots in without redesign" is retired. "Settled"
is retired from the vocabulary: charge finalization, payout calculation, payout release, and record closure
are four distinct moments.

## 2. Assignment loop (critique 2 — fully modeled)

`paid → proposed(runner, deadline 5m) → accepted | declined(reason) → unassigned (attempt n+1)`
- Runner may revoke acceptance **before handoff** → `replacement_needed` (reliability strike if habitual).
- Owner may decline the accepted runner before handoff → owner-cancel path (§6 fee table; first decline
  with stated cause = free, converts to refund or attend-mode).
- **Guaranteed-assignment deadline = T-10m**: any paid dog not `accepted` by then → automatic full refund +
  push+banner + offer: convert to owner-attended (dog runs with owner) or move to next session (priority flag).
  A paid dog can never be stuck: the deadline is a cron+RPC-enforced hard stop.
- All-runners-declined earlier than T-10m → host notified immediately; owner notified with the same options.

## 3. Session model: lifecycle × outcome (critique 4 adopted)

```
lifecycle  scheduled → checkin_open → in_progress → returning → ended
outcome    completed | completed_partial | completed_incident | cancelled_before_start | aborted_after_start
reason     weather / host_unavailable / runner_capacity / route_closed / safety / low_viability / other(text)
```
- `ended` is reachable only when: no dog in custody ∈ {runner, transfer_pending, return_pending}, no run
  active, no incident `open` without an ops acknowledgement. (Finish-blocking, now axis-precise.)
- Abort-after-start = host/ops action with reason; triggers per-dog resolution (early settle + returns) first.

## 4. People: capabilities, not one role (critique 7 adopted)

A participant is a set of capabilities, already derivable from existing tables (no schema rewrite):
`is_host` (club_sessions.host / assumed backup) · `is_handling` (committed assignment) · `is_attending`
(session_people) · `owns_participating_dog` (session_dogs) · `is_authorized_pickup` (new, per-dog field).
The action matrix (§9) is keyed on **capabilities**; a host-who-handles simply matches two rows. UI renders
the union of its capability panels. `session_people.role` survives as display garnish only.

## 5. Host absence & override constraints (critiques 5, 8 adopted)

- **Backup host**: optional `backup_host_profile_id` per session (certified+); backup (or ops) can
  `assume_host(reason)` — logged event, participants notified. Host not checked in by **T-30m** → alert
  backup + ops + participants ("진행 지연 가능"). Host absent at T → backup assumes or ops cancels with
  full refunds. Host cannot leave (session cannot end) while any dog is out — if unreachable, ops close-out.
  Beta honesty: **ops = Sean (admin role)**, stated in-product as "운영팀"; SLA is best-effort and the
  consent doc says so. [Co-host governance stays P-D; backup-host is the pilot-safe subset.]
- **Override taxonomy** replaces v2's blanket host override:
  - `witness_confirm`: host physically witnessed the handoff/return, one side's device unavailable → host
    confirms on their behalf; requires host **not a party** to that custody edge, reason + (optional) photo.
  - `assisted_confirm`: party present, app broken → host device collects the party's own confirmation.
  - **Dispute = never overridable**: conflicting claims → `incident(open)`, payout hold, ops review.
  - Host-as-runner cannot witness_confirm their own dogs' edges — falls to backup host or ops.

## 6. Money rules (destinations decided; amounts remain Sean's)

Architecture decided now (critique's "not harmless leftovers" point accepted):
- **Fee destinations**: cancellation/no-show fees are ledger-typed rows — `fee_platform` and
  `fee_supply_compensation` (affected runner/host pool). Split ratio = Sean (default 50/50).
- **Host compensation mechanism**: `host_fee` ledger line per `completed*` session, platform-funded,
  visible in host ledger; independent of whether host handled dogs. Amount = Sean (placeholder 0 in beta
  until set — no fake money).
- Owner cancel ladder (defaults, Sean tunes): free until paid; paid → free ≥24h before; <24h 10%;
  after acceptance 20%; after handoff = early-return settle path, not a cancel. No-show (outbound handoff
  never completed by cutoff) = 취소 규정의 최상단 단계 + reliability strike; beta(mock) charges nothing but
  records everything.
- Refund failure → `refund_failed` + ops alert + banner (never silent). Reconciliation job = PG milestone.

## 7. Capacity: the equation + serialization (critique 9 adopted)

```
available_for_approval = promised_capacity − |paid ∪ confirmed dogs| − |active holds|
available_day_of       = present_capacity  − |accepted assignments|
```
- **Every capacity-touching transition takes the session row lock first** (approve, pay, hold-expiry, commit,
  withdraw, propose, accept, emergency transfer) — already the codebase pattern, now a stated law. Payment RPC
  re-checks hold validity under the lock (pay-vs-expiry race → deterministic: whoever holds the lock first
  wins; expired-but-unpaid → friendly "다시 신청" path). Cron expiry and RPCs serialize on the same lock.
  Idempotency: all money/custody RPCs take a client idempotency key; replays return the original result.
- Recovery window after capacity loss is **adaptive, not 15m flat** (critique 15):
  ≥24h out → 24h · 2–24h → 60m · at check-in → 15m · dog already in custody → emergency path immediately.
  During the window affected dogs show **자리 재확인 중**; caps are never raised beyond a runner's verified
  personal cap to "save" a session (restated invariant).
- Runner no-show resolution (critique 14): late at T-30 → capacity-at-risk alerts; replacement flow =
  backup-host/host invites eligible certified runners (beta: manual); unreplaced by **T-10 deadline** →
  the §2 hard stop resolves every affected dog (refund + options + compensation credit [amount = Sean]).

## 8. Viability, eligibility, consent (critiques 10, 20, 21)

- **Mixed viability = two independent tests**: (a) attendance minimum (if configured), (b) **delegated
  coverage**: present+accepted capacity ≥ paid dogs. Social component may proceed while the delegated
  component fails → partial-session rules: outcome `completed_partial`, failed dogs auto-refund via §2 stop.
- **Physical gate at handoff**: outbound confirmation embeds a checklist (equipment present, dog condition,
  combined-load OK). Refusal-at-handoff: runner/host may refuse with reason → if disclosure was false →
  owner-fault cancel (fee ladder top + strike); else full refund + credit. Dog-info edits after approval
  reset to `requested` (re-approval); second-dog acceptance shows the runner the **combination** (pairwise
  review), and accepting dog B re-confirms A+B together.
- **Consent**: immutable acceptance rows (doc id+version, dog, session, booking, vet-payment authorization
  limit ₩[Sean], photo consent, custody acknowledgement). **Material changes** (time >±30m, meetup, price,
  route distance class, waiver version) → re-accept required by deadline else free-cancel+refund. Runner
  identity change = notify + free-cancel right, not re-consent. Photo consent revocable forward-only.

## 9. Action matrix v2 — canonical + exception rows (critique 23)

Canonical rows as spec v2 §8 (kept), now keyed on capabilities, plus exception rows (roster+chat in every row):

| Exception state | Host/backup | Owner | Runner |
|---|---|---|---|
| payment_failed / hold expired | status label | 재시도/재신청 | — |
| proposed declined / replacement_needed | 다른 러너 제안 | 상태+옵션 보기 | (다른 러너) 수락 |
| capacity_at_risk / 자리 재확인 중 | 대체 러너 초대·창 관리 | 옵션(대기/전환/환불) | 캡 내 증원 수락 |
| owner no-show at cutoff | 노쇼 처리 확인 | — | 배정 해제 통지 |
| runner no-show | §7 대체 플로우 | 진행 위험 고지 수신 | — |
| handoff/return disputed | **incident만** (오버라이드 불가) | 진술 제출 | 진술 제출 |
| incident open | 인시던트 콘솔·SOS | 상태 열람·연락 | 보고·증빙 업로드 |
| refund_pending/failed | 라벨 (실패시 ops 알림) | 상태·문의 | — |
| session aborted_after_start | 사유 기록·개별 정리 | 환불/부분 정산 열람 | 조기 정산 |
| host absent | (backup) assume_host | 고지 수신 | 고지 수신 |
| emergency transfer | 개시/승인 | 통지·연락 | 수락(양측) |

## 10. Custody events, transfers, GPS segments (critiques 6, 17)

- `dog_custody_events`: from/to as `custodian_type ∈ {profile, clinic, authority, other_authorized}` +
  profile_id nullable + external_name/contact for non-profiles. **Transfers are two-sided**: initiator →
  receiver `accept` (capacity- and verification-checked) → event effective; exception: incapacitated-runner
  emergency = host/ops attestation auto-opens an incident. Events carry timestamp + location; liability
  periods are exactly the event intervals. Authorized-pickup person: named per-dog at consent, may confirm
  return as `other_authorized`.
- `dog_run_segments` (runner_id, run_id/trace ref, joined_at, left_at, transfer_event_id): a dog's record is
  its segments — transfers mid-run, pace-group splits, and late joins are segment boundaries; a dog never
  inherits trace outside its segments. Server timestamps are authoritative (client clock untrusted);
  out-of-order/duplicate batches dropped by sequence; staleness surfaced on live view ("n분 전 위치");
  session-level events (start/pause/returning/end) separate from per-dog events. Spoof detection = post-PG.

## 11. Rollout & drift control (critiques 3, 25 — scoped to pre-launch reality)

- **Single choke point for the pool**: a `marketplace_open_requests` view becomes the only source for
  runner-inbox/open-request reads (replaces per-query filters); club bookings are structurally incapable of
  appearing. DB CHECK: booking with club_session_id can never hold pool-only statuses beyond `matching`, and
  a documented mapping table `session_dogs axes ↔ bookings.status` + **reconciliation query shipped as a
  harness case AND an admin/cron drift check** (logs, never auto-mutates).
- Old `approval` column: v3 migration backfills axes from it, dual-writes for one slice, drops it in the
  cleanup migration — harness asserts sync during the window. (Only Sean's test rows exist; wipe is the fallback.)
- Feature flag `club_delegation` (server-checked in RPCs + app config): OFF for any non-test account until
  R-slices AND shell UI are complete — no intermediate state ever reaches a user. Rollback = flag off.
  Old-app compatibility: moot pre-launch (no released delegation UI); the flag discipline still ships.
- Harness gains an **adversarial class** (critique 26, scoped to what a single-node harness can honestly
  test): permission-leak (each role calls every other role's RPCs), idempotency replays, stale-client
  repeats, out-of-order confirmations, duplicate webhook simulation, cron-vs-RPC same-transaction ordering,
  suspended/deleted-account actors, finish-during-incident. True multi-connection races: a two-psql bash
  harness extension for the top three (last-slot pay, pay-vs-expiry, withdraw-vs-pay); remaining race safety
  rests on the single-lock law (§7) — stated as an argument, not a test result.

## 12. Known-unmodeled register (open, tracked, not blocking pilot with Sean-only)

Chat moderation depth (edit windows, attachment types beyond photo, ack receipts, retention tuning) ·
phone-access logging UI · notification delivered/opened analytics (pilot ships ack-required in-app banners
for critical events; push analytics later) · multi-incident triage UI · insurance notification workflow ·
tax/receipt handling (PG) · masked calling · auto-compatibility scoring · series visible-generation 7–14d ·
weather automation · member-governance edge cases beyond §8 of v2 (obligations survive membership changes —
that invariant IS adopted: suspension/block/leave never interrupts an unresolved custody or refund).

## 13. Build order v3 (feature-flagged; starts on Sean's approval of this doc)

- **R0 (0040)**: axis columns + backfill from `approval` + projection function + `marketplace_open_requests`
  view + flag plumbing + reconciliation harness case. (Pure schema/read — no behavior change yet.)
- **R1 (0041)**: payment axis live — approve=hold(20m), owner pay RPC creates booking (idempotent), expiry
  cron, host read-only labels, capacity equation under session lock.
- **R2 (0042)**: custody events + two-sided return + override taxonomy + transfers (custodian types) +
  finish/ended gating + payout earned/payable/released/held.
- **R3 (0043)**: assignment loop (propose/accept/decline/revoke, T-10 hard stop) + split windows + adaptive
  recovery + no-show flows + backup host / assume_host.
- **R4 (0044)**: consent records + eligibility fields & physical gate + viability v3 + dog caps + cancel/fee
  ledger types + metrics split (physical runs vs dogs served) + membership-separation with obligation invariant.
- **R5 (0045)**: shell backend — chat + capability roster + phone rule B (lifecycle-scoped) + notification
  matrix with ack-required banners.
- **R6 (0046)**: emergency minimum (SOS, incident axis wiring, severity, contact hierarchy, evidence) +
  segments/GPS rules + series occurrence identity (`series_id + original_scheduled_start`) + adversarial
  harness class.
- Then UI on lab v3 direction. Each slice: harness green + drift query green before the next.

*Sean's open numbers (architecture no longer depends on them): fee split ratio & ladder amounts, host fee
amount, compensation credit amount, vet authorization default limit, window/default tuning, chat push defaults.*
