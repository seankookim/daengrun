# HIGH CLUB Group Run — Logic Spec v2 (post-critique redesign)

> 2026-07-30 v2. Supersedes v1 after Sean's review + external critique (27 sections, considered in full).
> Verdict triage: **[ADOPT-NOW]** = rebuild before real dogs/payments · **[ADOPT-PILOT]** = before opening to
> anyone beyond Sean's test circle · **[DEFER]** = explicitly postponed with reason · **[PUSHBACK]** = disagree, with reason.
> §1–§8 is the new canonical design. §9 is the item-by-item triage. §10 is the build order.

---

## 0. The three separations the critique demanded (all adopted)

1. **Host approval ≠ customer payment ≠ runner assignment.** Three actors, three decisions, three states.
   The host console never renders a purchase-shaped control — payment appears there only as a read-only status.
2. **Run completion ≠ physical return.** Custody stays with the runner until a two-sided RETURN confirmation —
   symmetric with the outbound handoff. Settlement of money and return of the dog are decoupled.
3. **Session shell ≠ stage screens.** 개요 · 참가자 · 채팅 are permanent tabs of every session page for every
   authorized role at every stage. Stage content changes; the shell never does.

## 1. Delegation state machine v2 (canonical, per dog)

`session_dogs.state` (new column; old `approval` retained during migration):

| # | state | Korean UI label (primary) | flap (flavor) | money | custody |
|---|---|---|---|---|---|
| 1 | requested | 신청 대기 | PENDING | none | owner |
| 2 | approved_unpaid | 승인 — 결제 대기 (기한 20분) | CLEARED | capacity **hold** with deadline | owner |
| 3 | paid | 결제 완료 — 러너 배정 대기 | — (BOOKED?) | booking exists | owner |
| 4 | assigned | 배정 제안 — 러너 수락 대기 | — | booking | owner |
| 5 | accepted | 담당 확정 — 인계 대기 | — | booking, runner locked | owner |
| 6 | in_custody | 러너가 보호 중 | BOARDED | insurance active | **runner** |
| 7 | running | 러닝 중 | RUNNING | — | runner |
| 8 | run_done | 러닝 종료 — 반환 대기 | — | run settled (or held, §5) | **runner** (critical fix) |
| 9 | returned | 반환 완료 | SETTLED | final | owner |
| E1 | refused | 거절됨 (+사유, 호스트 정정 가능) | REFUSED | none | owner |
| E2 | expired_unpaid | 결제 기한 만료 | — | hold released | owner |
| E3 | cancelled | 취소됨 (actor+reason 기록) | — | fee policy §6 | owner |
| E4 | incident | 인시던트 — 운영 확인 중 | — | settlement hold | explicit per event |

- **Booking creation moves from approval to PAYMENT** (mock `payment_ok` today; the state machine is
  PG-shaped so real PG slots in without redesign: attempt id, idempotency key, amount snapshot, failure states).
- 2→3 is the owner's action, on the owner's screen only. Approval hold: 20 min (config), expiry cron releases
  capacity + notifies owner; re-request allowed while capacity remains.
- 4→5 is the **runner's acceptance** [ADOPT-NOW]: host proposes; runner sees the dog card (weight, energy,
  reactivity/bite disclosures, medical notes, equipment, owner notes, pay) and accepts or flags. Owner sees the
  runner card only after acceptance. Beta shortcut kept honest: host proposal + runner accept are two taps
  minutes apart at the meetup, but they are two records.
- Internal `bookings.status` keeps using the existing graph (created at payment as `matching`, pool-hidden);
  **UI never renders internal status words** — it renders `session_dogs.state` labels above. [PUSHBACK-lite on
  renaming enum values: truthfulness is a UI+spec obligation; enum surgery on a live money table is risk without
  user-visible benefit. The spec label table above is the contract.]

## 2. Custody — event-sourced, two-sided both directions

- `dog_custody_events` table [ADOPT-NOW]: session_dog_id, from_profile, to_profile, event_type
  (outbound_handoff / return_handoff / emergency_transfer / vet_transfer / host_override), initiated_by,
  confirmed_by, occurred_at, reason, booking_id. `responsible_profile_id` becomes a **projection** of the last
  event; history is immutable.
- Outbound: two-sided confirm (existing stamps) → in_custody. Return: two-sided confirm
  (러너 "반환했어요" / 보호자 "인계받았어요") → returned. **Run completion does NOT flip custody** (v1 flaw fixed).
- Host override path: host confirms on behalf of an unresponsive side, with reason logged (dead phone, dispute).
  Emergency transfer: runner→runner or runner→host, logged, both notified, owner notified.
- Unresolved return past grace (60 min after run end, config) → escalation: repeated push + host alert + incident state.

## 3. Session lifecycle & capacity v2

**Lifecycle** (session): `scheduled → checkin_open → in_progress → returning → done | cancelled(reason)`.
Finish is **blocked** while any dog is in states 6–8 or any run active [ADOPT-NOW]. Stale sessions: reminder to
host at T+12h, ops alert at T+24h, admin close-out — never automatic custody transfer.

**Registration axes** (independent of lifecycle; the single `full` flag stops being load-bearing):
- People: open / full.
- Delegation: requests_open / capacity_full / closed.
- UI composes truthfully: "동반 정원 마감 · 위탁 2자리".

**Capacity v2**: `promised` (committed caps) / `present` (checked-in committed caps) / `assigned`.
Before runner check-in, capacity is a promise — owner screens say so ("러너 2명 확약"). Runner late at T-30m →
host alert + owners of unassigned paid dogs notified ("배정 지연 가능") [ADOPT-PILOT]. Also new dog caps:
max owner-handled dogs per attendee (default 2), total dog cap per session (default = people_capacity, config).

**Viability replaces min_attendance** [ADOPT-NOW]: owner_only = min attending teams · delegated_only = min paid
dogs AND ≥1 present runner · mixed = min total active teams. Host-notification-only behavior unchanged.

**Windows v2** (config constants, replacing the single T-2h..T+6h):

| Window | Default |
|---|---|
| Runner check-in | T-45m .. T-10m (late = capacity-at-risk) |
| Participant check-in | T-45m .. T+15m |
| Assignment + acceptance | runner check-in .. T-10m |
| Outbound handoff | T-30m .. T+15m |
| Payment deadline after approval | +20m |
| Return grace after run end | 60m → escalation |
| Creation min notice | owner_only 2h · delegation-enabled 24h · series window 72h |

## 4. Session shell — 개요 · 참가자 · 채팅 (permanent)

- Fixed tabs on every session screen, every stage, every authorized role (host / committed runners / RSVP'd
  owners / owners with any delegation record incl. pending). Rejected/expired requesters keep read access to
  their own record, not chat. Public viewers get 개요 only.
- **Chat**: writable from first participation until **all dogs returned + 24h grace** (not frozen at finish —
  return coordination, lost items, photos). Then read-only archive. Push [ADOPT, upgraded from v1]: host
  announcements ON, mentions ON, system-critical (cancel/location/time/assignment) ALWAYS, ordinary messages
  user-configurable (default OFF beta).
- **Roster**: role-aware richness. Host sees everything (states, payment labels, custody, safety flags,
  capacity meter). Runner sees own dogs in detail + group overview; medical/behavior details visible only to
  host + that dog's runner. Owner sees host, runner pool, own dog's full record, others per consent.
  Phones: rule B (host↔all; owner↔assigned runner mutual; else host relay), visibility tied to **unresolved
  participation** (from confirmation until all own handoffs resolved + grace), not a fixed clock [ADOPT].

## 5. Money v2

- Pricing single source of truth [ADOPT-NOW]: one SQL function `club_fare(km)`; ctx.ts constant retired for club
  paths; booking stores amount snapshot + pricing version.
- Payment states (mock now, PG-shaped): §1 table + failure paths (auth fail, timeout, duplicate tap →
  idempotency key, refund fail). Reconciliation job = real-PG milestone [DEFER until PG].
- Settlement on run end stays per booking (money), but if return is unresolved or incident open → **settlement
  hold** flag; release on resolution [ADOPT-NOW].
- **Runner metrics fix** [ADOPT-NOW]: one physical run = +1 total_runs, distance counted once, drop cadence on
  physical runs; dogs served = +N (new counter); payouts per booking unchanged; owner-side miles per booking
  unchanged; runner miles once per physical run + per-dog service bonus (small).
- Owner cancel rules [ADOPT-NOW]: free until payment; after payment free until T-24h*; inside T-24h fee
  (10%, existing rule) — cancel releases capacity, promotes next pending, notifies host+runner, audit row.
  (*delegation bookings are created inside T-72h typically; exact fee ladder = Sean decision, default above.)
- No-show (= outbound handoff never completed by cutoff): beta = full refund + reliability strike recorded;
  post-PG = late/no-show fee ladder [ADOPT numbers later].
- Withdraw stranding v2 [ADOPT-NOW]: affected dogs → **자리 재확인 중** (not instant refund): 15-min host
  recovery window (invite backup runner / another runner raises cap / offer another session) → auto-refund only
  after window lapses; original priority preserved; runner recommit auto-restores. Withdraw also splits into
  "위탁 담당에서 빠지기" vs "세션에서 나가기". Repeated commit/withdraw → reliability strike.

## 6. Club & membership

- **RSVP ≠ membership** [ADOPT-PILOT]: guest RSVP allowed; join prompt after first attended session; delegation
  requires join at payment (they're becoming a service customer). Membership states: member/host/suspended/left
  (moderator/co-host [DEFER P-D]). Leave club, host removes member, block, report [ADOPT-PILOT]. Host transfer,
  abandoned-club handling [DEFER P-D — already planned there].
- **Host incentive** [Sean decision needed]: options — fixed host credit per completed session, reduced
  commission on host's own delegated dogs, trust-score/exposure, paid host fee funded from delegated bookings.
  Placeholder recommendation: 500 miles/completed session + commission −2%p during beta.

## 7. Field reality (emergency, GPS, conflicts, series)

- **Emergency minimum** [ADOPT-NOW, minimal]: persistent SOS on run screens → host+owner+ops alert with live
  location; incident state on the dog (settlement hold, custody event, report text+photos); emergency transfer
  RPC. Vet authorization + preferred clinic captured in the delegation consent. Full ops console [DEFER].
- **Consent** [ADOPT-NOW]: `delegation_consents` immutable row (doc id+version, user, dog, session, booking,
  timestamp, photo consent, vet authorization, custody acknowledgement) written at request; re-accept on
  material change. Not a version string on session_dogs.
- **GPS** [ADOPT-PILOT]: per-run active time range (joined_at/left_at) over the shared trace — late joiner's
  run records only their segment (no inherited history); impossible-jump filter exists (smoothing);
  disconnect → last-fix timestamp shown honestly on owner live view ("2분 전 위치"); session-level events
  (group started/paused/returning/ended) separate from per-dog events.
- **Conflict checks** [ADOPT-PILOT]: extend the dog clash guard to humans — host/runner/owner overlapping club
  sessions + runner's private bookings, using planned route duration + buffers instead of km×8+25 everywhere.
- **Series** [ADOPT-PILOT]: occurrence key `series_id+date` replaces ±1h dedup; snapshot route/price/rules at
  generation; exception dates; edits affect future-unpaid occurrences only. Visible-further-ahead generation
  (7–14d, delegation opens nearer) [DEFER — good idea, after pilot].

## 8. Language & the action matrix

- **Plain Korean is primary** for all safety/money states (§1 table); flaps stay as the beloved visual flavor,
  always paired with the Korean label, never alone on critical states [ADOPT — the lingo sheet remains, but it
  explains flavor, it doesn't carry meaning alone].
- **Role×stage action matrix** (drives every screen; roster+chat in every cell):

| Stage | Host | Owner | Runner |
|---|---|---|---|
| requested | 승인/거절(+사유) | 요청 수정/취소 | 수요 보기 |
| approved_unpaid | 결제 대기 라벨 | **결제하기** (기한 표시) | — |
| paid | 배정 제안 | 상태 보기 | 커밋/수락 대기 |
| assigned | 제안 변경 | 러너 후보 카드 | **수락/우려 제기** |
| accepted→handoff | 관찰/중재 | 인계 확인(보내는 쪽) | 인계 확인(받는 쪽) |
| running | 세션 콘솔·SOS | 라이브·채팅 | 러닝·이벤트·SOS |
| run_done→return | 관찰/중재/오버라이드 | **반환 확인** | **반환 확인** |
| returned | 리캡 발행 | 리뷰/공유 | 리뷰/공유 |

- Recap counts v2 [ADOPT]: "8명 참여 · 7마리 완주 · 동반 4 · 위탁 3" — humans and dogs separately; drop-and-go
  owners appear in the service record, not the attendance count. Private details stay private.
- Notification matrix expanded [ADOPT-PILOT]: + payment-due, payment-failed, runner committed/withdrew,
  capacity-at-risk, assignment proposed/accepted/declined, T-24h reminder, check-in open, late alerts,
  return ETA/unresolved, review request. All deep-link to the session shell.

## 9. Critique triage (by its numbering)

1,2 payment/role split **ADOPT-NOW** · 3 return handoff+custody events **ADOPT-NOW** · 4 runner acceptance
**ADOPT-NOW** · 5 status/capacity split + dog caps **ADOPT-NOW** · 6 withdraw grace **ADOPT-NOW** ·
7 no-show/promised-capacity **ADOPT-PILOT** · 8 windows **ADOPT-NOW** · 9 payment machine **ADOPT states now,
PG infra when PG lands** · 10 pay-before-knowing-runner: **keep day-of assignment** (it's the product: club
sells a verified pool + host assignment) but sell it honestly pre-payment + runner card on acceptance **ADOPT** ·
11 finish blocking **ADOPT-NOW**, outcome enum → status+reason [PUSHBACK: reason codes over enum explosion] ·
12 emergency **ADOPT-NOW minimal** · 13 eligibility disclosures **ADOPT-NOW** (fields at request; auto-matching
DEFER) · 14 membership **ADOPT-PILOT** · 15 series **ADOPT-PILOT** · 16 conflicts **ADOPT-PILOT** ·
17 GPS **ADOPT-PILOT** · 18 host incentive **Sean decision** · 19 metrics **ADOPT-NOW** · 20 consent
**ADOPT-NOW** · 21 viability **ADOPT-NOW** · 22 roster richness **ADOPT** (rule B, lifecycle-based) ·
23 plain Korean **ADOPT** (flaps demoted to flavor) · 24 action matrix **ADOPT** (§8) · 25 notifications
**ADOPT-PILOT** · 26 recap **ADOPT** · 27 policy recs **ADOPT as defaults, fee numbers = Sean**.
Masked calling, global club chat, auto-compatibility scoring, dynamic pricing, weather automation — **DEFER**
(critique agrees).

## 10. Build order (backend slices, each harness-gated)

- **R1 (0040)**: state column + payment separation (approve=hold+deadline, owner pay RPC creates booking,
  expiry cron), `club_fare()` single source, host read-only payment labels, plain-Korean state contract.
- **R2 (0041)**: return handoff (two-sided + host override) · `dog_custody_events` · custody projection ·
  finish blocking · settlement hold.
- **R3 (0042)**: runner acceptance flow · split windows · promised/present capacity · late-runner alerts ·
  withdraw grace (자리 재확인 중).
- **R4 (0043)**: consent records · eligibility fields on request · viability rules · dog caps · owner-cancel
  rules · metrics fix · membership separation.
- **R5 (0044)**: session shell backend — chat + rich roster RPC (phone rule B, lifecycle visibility).
- **R6 (0045)**: emergency minimal (SOS, incident, emergency transfer) · notification matrix · recap v2 ·
  series occurrence keys · conflict checks.
- Then UI on the shell (lab v3 direction).

*Open for Sean: fee ladder numbers (§5), host incentive (§6), window defaults (§3 table), chat push defaults.*
