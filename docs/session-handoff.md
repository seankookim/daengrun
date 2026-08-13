# SESSION HANDOFF — 2026-08-13 · charge slice + club money gates SHIPPED · `redesign-v4` @ 534d2aa

**Opener for the next session: "read docs/session-handoff.md fully, then continue."**
Previous handoff: `docs/session-handoff-archive-20260812-final.md`. Plan of record:
`docs/plans/payments-toss-plan.md` §0-bis/§0-ter (unchanged as design; this session BUILT it).

## 1. What this session did

**Both slices are merged and pushed to `origin/redesign-v4` (534d2aa). Nothing is deployed** —
no `db push`, no `functions deploy`; the deploy order in §3 has ops prerequisites only Sean
can clear, and everything shipped is inert until `ops_flags.payments_live_since` is set.

**① The §0-ter settle-time charge machine**, built via 4 parallel build agents +
3 attack-executing adversarial reviewers + 2 fix agents. Then **merged current redesign-v4
back in** (route catalog + pace-state + harness loud-fail landed mid-build) and renumbered:
the migration is **0080_charge_machine.sql** (0078/0079 were claimed by route-catalog and
pace-state), the suite is **116_charge_suite.sql** (115 = pace-state). Lesson, learned twice
in one day: parallel branches pick "next free number" against their fork point — check
`ls supabase/migrations | tail` against CURRENT redesign-v4 at merge time — and it happened a
THIRD time after that (a route-discovery session planned its promotion guards as 0081 while
0081 was being written here; they were told to take 0082/suite 118).

**② Club money gates (0081)** — the third booking-creation path. 0080 §H had named its own
exclusion: it gated create-booking-hold and generate_recurring_bookings and left
`session_pay_delegation` open, while club runs DO reach the charge branch
(club_start_delegated_runs → club/run/[sid].tsx:247 → settle-run → mint, no club exclusion
anywhere). Now gated with 0080 §H's two predicates verbatim, plus the club confirmation
stopped claiming '결제 완료' for a payment that never happens there, plus club_fare lost its
PUBLIC execute. Independently reviewed (verdict: migration sound; one pin repaired — see §2).

| Gate | Result (final tree) |
|---|---|
| SQL harness | **438 / 0** (redesign-v4 baseline 403 + 116 charge C1–C25 + races RD/RE + 117 club K1–K8) |
| Deno | **133 / 0** (`deno test -A supabase/functions/_test/`) |
| Client | tsc clean · check-rpc green |
| Mutations | 44 executed across build+review+fix waves (each: apply → red → restore → green) |

Inventory: `0080_charge_machine.sql` (billing_keys · ops_flags.payments_live_since ·
compute_owner_charge basis table · mint_settle_charge_intent / mint_cancel_fee_intent ·
owner_has_unsettled_charge + my_unsettled_charge · my_billing_card · sweeps + reconciliation
4-arm · recurring gates · 0060/0072 conditional copy · record_enroute_cancel_comp ·
dispatch_due_charges) · `_shared/charge.ts` + `tossBillingCharge`/`tossGetByOrderId` ·
settle-run charge branch (handler split) · `collect-charges` (owner CTA + cron batch +
verification arm) · create-booking-hold debt gate + card instant-CAS + compensating delete ·
cancel_owner fee machine (refund return RETIRED) · client: `/payments` 결제 관리 ·
schedule-sheet 결제 내역 · charge-states.tsx banners · request lock banner · 3 stale
refund-copy fixes · pay-lab 청구 예외 tab.

## 2. Decisions layered ON TOP of §0-ter this session (all verified/executed)

- **Per-attempt idempotency keys** (`{order_id}_a{n}`): Toss retains a key 15 days and
  REPLAYS the first response — same-key retries would replay the decline and void the
  ladder. Double-charge safety = constant orderId (DUPLICATED_ORDER_ID) + already-processed
  arm + **claim-CAS on raw.attempts** (two dispatchers cannot both charge; R2 P1-1) +
  **pg_advisory_xact_lock in both mints and the comp fn** (two minters cannot create two
  orderIds for one debt; R1 P1-1, race-pinned RD/RE).
- **`ops_flags.payments_live_since timestamptz` (null = OFF) is THE cutover switch.**
  Mints/sweep scope to `runs.ended_at >= since`: no retroactive charging of pilot runs,
  no false debt for card-less pilot owners. Currently NULL — everything is inert.
- **Debt derives from server-minted rows only** (`raw->>'kind' is not null`) — widget-era
  decline debris must never lock a paid owner (R1 P1-2).
- **Outages are not declines**: Toss 5xx/401/403/non-JSON → unresolved dispatched-pending,
  never the ladder, never "카드사에서 거절" copy; the cron's 15-min verification arm
  (tossGetByOrderId) auto-resolves them before the 1h debt line (R2 P1-2).
- **confirm-payment refuses server intents** (kind gate) and merges raw — it could
  previously consume a charge intent and destroy its markers, bricking collection with
  the lock stuck on (R3 P1-1).
- **Privacy**: settle-run's response to the runner carries NO owner collection state —
  pre-slice shape exactly; outcomes live in payments rows + logs.
- **'waived' status** (amount 0, no key, `payments_waived_is_zero`) keeps invariant #1
  (every settled booking has a payments row) over the G1 charge-nothing arm and the new
  `below_pg_minimum` (<₩100) arm.
- 🔴 G1 (dog_condition/incident basis) is STILL Sean's open call — provisional
  charge-nothing shipped, grep handle `g1_waive`.
- **Ops alerts carry no financial detail** — OPS_PROFILE_ID is an env-held uuid and 0024
  pushes notification bodies verbatim to a lock screen, so a valid-but-wrong value put another
  customer's order number and ₩ amount on a stranger's phone. Payload removed (detail lives in
  console.error + payments_reconciliation()); a second cross-check env var was rejected as
  moving the question. Pinned.
- **Club bookings are refused by the marketplace cancel ladder** — they reach /owner/schedule
  and were being quoted 0066's rates into a club-blind state. Refused server-side; the client
  routes to the club session screen. Copy says 진행, not 취소, because the club exit refuses
  past handoff (memo ⑤).
- **A pin can be mutation-proven and still be hollow** (club review P2-1): 117's K2 probed a
  seat an earlier pin had consumed, so it died at the state gate before the money gates, and
  it only went red under mutation because the earlier pin's failure rolled back and restored
  its fixture. Repaired; the lesson is kept in the suite's mutation map. Worth remembering the
  next time a mutation map reads as proof.

## 3. DEPLOY ORDER (verified per-function by R3 — violating it breaks bookings)

① `supabase db push` (0080) **FIRST** — create-booking-hold hard-blocks on its fns/tables
(fail-closed by design). Inert while payments_live_since is NULL.
② `functions deploy create-booking-hold`
③ `functions deploy collect-charges --no-verify-jwt` (X-Cron-Key IS the credential; owner
path still JWT-validated via caller())
④ `functions deploy settle-run transition-booking confirm-payment` (order-safe, errors caught)
⑤ app build
⑥ vault secret (`charge_dispatch`: {url, cron_key}) + edge env `CRON_COLLECT_KEY` + `OPS_PROFILE_ID`
⑦ `payments_live_since` flip — LAST, set to a **FUTURE timestamp past the longest in-flight
booking** (Sean's ruling ⑥ — never `now()`; `longest_inflight_booking_end()` computes it and
`set_payments_live_since()` refuses a past value). BLOCKING preconditions, all of them:
  · 자동결제 심사 + billing TEST keys + §4-2 sandbox matrix
  · card-register slice shipped (Ⓐ is already approved in `docs/labs/pay-rebuild-lab.html` —
    post-pay cannot function without linked cards, and a card-less owner is refused from club
    and recurring entirely)
  · **the `dog_condition` report copy shipped** — the runner's own `condition_note` surfaced
    and "stopping was the right call" stated. Under Sean's G1 = full actuals, a dog that limps
    at 200m bills the owner ~₩8,500, so the record card is both the welfare mitigation AND the
    dispute surface. A bill with no account of why the runner stopped is the exact incentive we
    are trying to avoid — an owner who pressures the next runner to keep going. Owned by the
    run-end-flow session; mirrored in their plan so it sits in two documents that get read.
  · club price disclosure live (ruling ④ keeps 9,900 as a *stated* premium — the single
    disclosure is on the 승낙서, `app/app/club/delegate/[sid].tsx`)
  · **the sweep is re-anchored on `ledger_items`, and the setter REFUSES without it.**
    ⚠ SUPERSEDES the `runs.settled_at` plan below — that column is client-forgeable and the
    hole is bigger than "the sweep can't see a run". `0002_rls.sql:107` lets an assigned runner
    INSERT a `runs` row with EVERY column pre-filled, and `_guard_run_cols` (0057:465) is
    `before update` only. `sweep_settled_without_payments` selects on `runs.ended_at` and then
    mints through `mint_settle_charge_intent` using `end_reason` and `actual_km` **read off
    that same client-inserted row** — so post-cutover a runner could insert
    `ended_at = now(), actual_km = 10, end_reason = 'completed'` for their own booking and the
    sweep would charge the owner's card for a run that never happened. `settle_run_tx`'s atomic
    claim protects the normal path; the sweep bypasses it by reading `runs` directly.
    **The invariant sweep trusted client-writable data. That is ours, not the run-end slice's.**
    Anchor on **`ledger_items`** instead: RLS on, exactly one policy (`self read`, 0002:124),
    **no INSERT policy for any client role** — only `settle_run_tx` (definer) writes it. It is
    the artifact of settlement having actually happened, in a table no client can reach.
    Exclude the cancel-comp row by requiring a `runs` row and a non-cancel status; ledger
    existence is not a status, so §0-ter #11 still holds. `runs.settled_at` remains the
    semantic marker (money moved ≠ service stopped) but stops being load-bearing:
    **an anchor in a client-insertable table is one policy change away from being forgeable
    again, even after the guard lands.** Two independent facts beat one guarded one.
    **And the checklist becomes code:** `set_payments_live_since` (0084:468) enforces only
    `cutover_must_be_future`. It gains hard refusals — no flip while the sweep lacks its
    predicate, none while a settled-but-uncharged booking exists in the shape it cannot see.
    A checklist is advice; a refusal is a gate, and the 2am operator cannot skip a gate by
    not reading a header.
    SEQUENCING (forced, agreed with run-end-flow): their `runs` INSERT lockdown + atomic
    `start_run_tx` + BEFORE INSERT guard land in 0083 FIRST; our re-anchor and the setter
    refusals land after, because the harness must see their guard to pin ours.
  · ~~the sweep is re-anchored on `runs.settled_at`~~ (superseded, kept for the reasoning) — run-end-flow's 0083 redefines
    `runs.ended_at` as service-STOP time, which opens a hole in MY
    `sweep_settled_without_payments`: it would see a run that stopped, not yet returned, and
    mint a charge for a dog still on the leash. One predicate closes it, in my file, after
    their column exists: `and rn.settled_at is not null`. Deliberately NOT in 0084 — the
    column does not exist until 0083 applies, and coupling my gate to their unmerged branch
    buys nothing. It lands as its own small migration once 0083 is on redesign-v4, and the
    same substitution is the honest form of `owner_has_unsettled_charge`'s `ended_at` scope
    arm. Two anchors are wrong and 0083 §0f records why: `bookings.status` (§0-ter #11 /
    116 C8 — a settled booking legitimately moves to incident_review) and `ledger_items`
    presence (0081 writes a ledger row for a CANCELLED booking, which is not a run).
    **Note the window: the hole opens when 0083 merges and closes when that migration lands.
    Charging is off throughout, which is why this is a cutover gate and not an incident.**
    ⚠ **AND THE PIN MUST GO RED WITHOUT THE PREDICATE.** 0083's adversarial round demonstrated
    scenario B *inside a green harness*: `116_charge_suite.sql:209` sets
    `payments_live_since = now() - interval '7 days'`, so the suite deliberately switches the
    cutover flag ON in order to test anything at all — which disables the exact production
    bound (`0080:579-580`, null flag → return 0) that makes this safe today. A suite that turns
    off the guard cannot notice a missing predicate behind it. So the fix ships with a pin that
    is RED without `and rn.settled_at is not null` and green with it; adding the predicate
    without that pin leaves the same blind spot one migration later.
    The general form, from the same round and worth more than the specific fix: **a green suite
    proves the pins pass, not that the path is covered.** Both 0083 blockers had green pins —
    one tested a helper instead of the shipping path, the other asserted an escalation happened
    without asking whether money could still move afterwards.

## 4. Pending on Sean

**Ops:** ① 사업자등록 → 통신판매업 → Toss (일반 + 자동결제 심사 one application) — unchanged,
still the critical path; ② dashboard TEST keys + variantKey 카드/간편결제-only (docs demo
WIDGET keys are recorded in app/.env.example + plan §5 — they unblock the A3 device spike
NOW, but not billing); ③ ~~review + merge + push~~ — DONE this session: both slices are on
`origin/redesign-v4` (branch `claude/club-money-gates` also pushed). Local
`redesign-v4` in the main checkout is BEHIND origin on purpose — another session had
uncommitted work there, so the remote was advanced instead of fast-forwarding their tree.
`git pull` with a clean tree.

**Decisions — EIGHT memos in `docs/decisions/` (one directory; `decisions-open-money.md`
retired into it, Sean's rulings ported from `0fbaa64`). SEVEN are ruled, ONE is stuck:**
- ✅ **① G1 FULLY RULED — fault-based, both ledgers mirrored.** `dog_condition`: owner
  7,900 + 3,000×**distance actually run**, runner 9,900 + 3,000×same — nobody at fault, so
  nobody eats a gap. `owner_request`/`owner_forced`: owner PLANNED (D2), runner actuals.
  `runner_personal`: owner distance-only base-waived (#10 stands), **runner 9,900 base only,
  no distance** — the one deliberate asymmetry, platform absorbs it. `incident`: **₩0, verify
  first** (his instinct caught a free-run hole — `settle-run` whitelisted all six
  `end_reason` values on a public endpoint; now four). ⚠ a CLUB abort charges 9,900 (frozen
  base + ④). Required copy: report says stopping was right + shows the real `condition_note`.
- ✅ **② D-3 = A, accept as-is — NOTHING TO BUILD.** No per-charge push, no monthly
  summary. The statement-row slice is **CANCELLED, not deferred**. Counsel question
  survives as validation; 전자상거래법 footer still mandatory at 사업자등록.
- ✅ **③ OPS = `ops_recipients` table**, per-event-class routing ("build for full scale").
  Env var readable one more release. Payload redaction stands.
- ✅ **④ club_fare: keep ₩9,900** — premium stands, funds host comp (⑦) — **and club goes
  price-invisible**, disclosed once at join. ⚠ a club `dog_condition` abort therefore
  charges 9,900, since the charge reads the booking's frozen base.
- ✅ **⑤ en-route club cancel = A, leave it**; card-less club state routes to card
  registration. ✅ **⑥ cutover = FUTURE `payments_live_since`**, never `now()` (§3 ⑦ carries
  the query). ✅ **⑦ host cut from platform margin, never runner pay.** ✅ **⑧ card
  registration inline at first booking, not onboarding.**
Also still open: lab picks Ⓡ①②③ + Ⓖ rule · Ⓛ③ spec-plate graft + ₩/원 (carried from the
2026-08-12 handoff §9). **Migration/suite numbers: claim in `supabase/migrations/REGISTRY.md`
on origin BEFORE writing** — 0083/0084 are disputed there, procedure named in the file. **Migration/suite numbers: claim in
`supabase/migrations/REGISTRY.md` on origin BEFORE writing the file** (four collisions on
2026-08-13); 0083/suite 119 is next free.

## 5. Next prompts (exact openers)

- **⑩+⑪ money slice** (both RULED, both UNBUILT, unclaimed as of 2026-08-13): "read
  docs/decisions/cancel-fee-runner-share.md and incident-verification.md, then build them as
  one slice at the next free REGISTRY number." ⑩ = the 10% cancel tier pays the runner their
  half and notifies it as a reward (mirror `record_enroute_cancel_comp`'s idempotent ledger
  write, and write the row BEFORE the notification that claims it — 0081's lesson). ⑪ =
  two-sided incident verification on the `confirm_handoff` shape; disagreement routes to
  0072, and the runner is paid normally throughout.
- **⑨ runner_personal pass-through + `runner_incapacity`** (RULED, UNBUILT): encode the
  FORMULA — `(1 − commission) × the owner's actual charge` — never the illustrative figures.
  Two traps in its build notes: the enum value needs its OWN migration file (`alter type ...
  add value` used in the same transaction passes under autocommit and fails on `db push`),
  and it must NOT enter `CLIENT_END_REASONS` until its abuse story exists — it is
  self-declared AND pays the declarer more than the honest alternative.

- **Cutover-gate slice** (the last code before the flip): "read docs/session-handoff.md,
  then build the cutover-gate items as migration 0082+: per-runner dog_condition-rate +
  absorbed-KRW telemetry with the condition_note surfaced on the record card (the waive
  removes the free fraud detector), the payments_reconciliation >0-rows heartbeat, and
  D-3's monthly statement IF Sean has confirmed it."
- **Device-verify** (runnable NOW with docs demo keys, AFTER merge): "read
  docs/session-handoff.md; run the A3 device build with the docs demo keys in
  app/.env.example (variantKey DEFAULT), execute the §4-2 sandbox matrix through pay-lab
  incl. the TODOS 2026-08-13 §4 probes, report the verdict."
- **Card-register slice** (after Sean's Ⓐ pick): must include card-path postConfirm parity
  (TODOS 2026-08-13 §2) or card users lose nomination/recurring.

## 6. Known-good — do not "fix" (adds to the previous handoff's list, which stands)

- settle-run's runner-side guarantee recomputes from live PRICING.perKm — RUNNER money,
  0059 doc still true, deliberately out of this slice (0075 §0-⑤ tracks it).
- The due rule is ONE rule written twice (0080 dispatch_due_charges ↔ collect-charges
  isDue, pairing comments both sides) — change together or not at all.
- e_hold's 30-min silence (W7) is widget-flow law; the card path never strands there
  (compensating delete). The two-sibling-CTE shape in expire_unmatched_bookings is a
  pinned contract.
- charge.ts outcome writers CAS on status only, NOT attempts — extending the CAS there
  makes a legitimate capture unwritable mid-race (Fix-B's reasoned non-fix).
- `payment_hold` remains a transient instant state for card-linked bookings — zero
  transition-map delta is the design.

## 7. Environment (adds to previous)

- The SQL harness CANNOT run from a `.claude/worktrees/...` checkout (unix-socket path
  >103 bytes) — copy `supabase/tests` + `supabase/migrations` to /tmp and run there.
  (harness.sh now fails LOUDLY on suite parse errors — the loud-fail fix merged today.)
- deno 2.9.5 lives in session scratchpads — reinstall if gone. app/ worktrees have no
  node_modules — symlink the main checkout's for tsc, remove after.
- Toss docs demo keys + the 15-day idempotency facts are recorded in plan §5's banner.
- Migration/suite numbers: verify against CURRENT redesign-v4 at merge time, not at
  branch time (0078 was claimed three times today).

---

# 세션 핸드오프 — 2026-08-13 (오후) 루트 트랙: 0082 사다리 · K4/K5 · 지도 브라우즈 설계

읽을 동반 문서: `docs/plans/route-discovery-recommendation-plan.md` (정본 — autoplan 리뷰 전문 + K6/T1 빌드 스펙) ·
`docs/design/k6-map-browse-lab.html` (Sean이 A안 확정) · `supabase/migrations/REGISTRY.md` (번호 청구 원장) ·
체크포인트 `~/.gstack/projects/seankookim-daengrun/checkpoints/route-track-20260813.md`

## 1. 이 세션이 한 일 — 전부 push 완료, **배포 없음**

| 커밋 | 내용 |
|---|---|
| `7133738` | 플랜 (autoplan: CEO+디자인+엔지니어링 각 2보이스). Sean 게이트에서 Kernel+Browse v0으로 재스코프 |
| `a95aa34` | **0082_route_ladder** + 스위트 118 — 상태 사다리, `active` GENERATED, RLS `using(true)`, 승격 함수. 뮤테이션 검증 완료 |
| `81c071b` | create-booking-hold 코스 게이트 (suspended/retired 409 · candidate는 ack 필요 · km 엄격 타입 · 날짜 검증) |
| `dbff51b` | 레포 위생 — 미추적 비즈니스 문서 7종 백업, 에이전트 툴링 ignore, CLAUDE.md 번호 법 |
| `a8a17aa` | **K4** 실좌표 트레이스 — `traceToBox`(종횡비 보존), 버그 사본 4개 은퇴, `fetchRouteById` |
| `7c61837` | **K5 코어** — candidate 자동선택 금지(경로 3곳), 수동 선택 끈적임, 선택 스냅샷 |
| `e34298a` | **K5 칩** — 흙길/그늘/조명, 폴드 **밖**, 자동배정과 합성, 어두운 슬롯에 조명 자동 켜짐 |
| `845c76e` | REGISTRY: 0082 이넘 독립성 |
| `fe09b5b`·`722ff40`·`dbf8114` | K7 스파이크 + K6 랩 3안 + 지도 브라우즈 랩 3안 |

**게이트: 하네스 461/0 · tsc 클린 · deno 142/0** (0084 합류 트리 기준 재측정).

## 2. Sean 결정 (이 세션)

- **D1 = C** 커널+브라우즈 v0 (전체 스케일링 머신 대신)
- **D-VIS = A** candidate는 **의도적으로만** 예약 가능 (자동선택 금지 · 앰버 포스처 · 서버 ack 게이트 · PR-0 분모 제외)
- **T-KM = A** 의도적 코스 선택 시 **코스 km이 권위** — 인라인 가격 델타 동의 시트 (자동배정은 절대 km을 바꾸지 않는다)
- **C+B 선택** (루트 표면 + 돈 흐르게) — 한강 이벤트 대신. **반증 조건: 어떤 경로로든 실예약 5건. 재검토일 2026-09-13**
- **지도 브라우즈 = A안** (3단 시트: peek/list/detail). 빌드 스펙은 플랜 §K6/T1에 기록됨

## 3. ⚠ Sean에게 걸린 것 (둘 다 미해결)

1. **사업자등록을 아직 내지 마세요.** `launch-checklist.md:48-51` — 예비창업패키지 2027(~₩40M, 무등록 요구)과
   **되돌릴 수 없는 갈림길**. 그리고 돈은 **등록 없이도 움직인다**: `:29`의 최단 유료 경로와 `:62-63`의
   수동 계좌이체 브리지(`payments.md:26-28`)는 PG도 사업자등록도 요구하지 않는다. 사업자등록이 막는 건
   **Toss PG**지 매출이 아니다. (이 세션에서 제가 "이번 주에 내세요"라고 잘못 조언했다가 철회했습니다.)
2. **PR-0 계측은 코드에 존재하지만 값은 0.** 실예약이 흐르기 전까지 킬 라인은 발화할 수 없다.

## 4. 다음 세션이 바로 할 일

1. **[빌드] 지도 브라우즈 A안** — 스펙은 플랜 §K6/T1에 완성돼 있다. 새 화면 `app/app/owner/course-map.tsx`,
   진입점은 request.tsx 코스 폴드. K5 칩을 공용 컴포넌트로 들어올리고, 시트 DETAIL 단과 `course/[id]`가
   같은 상세 본문 컴포넌트를 쓰게 할 것(중복 방지).
2. **[빌드] K7 러너 지도** — 스파이크 완료로 **불확실성 0**: `docs/design/k7-map-primitives-spike.md`.
   컨트롤드 `camera` 프롭 → `initialCamera` + `NaverMapViewRef`; fit/follow/pan-override 전부 네이티브
   (`animateCameraWithTwoCoords` · `setLocationTrackingMode('Follow')` · `onCameraChanged.reason==='Gesture'`).
3. **[Sean] 사업자등록 갈림길 판정** — 이게 결정될 때까지 돈 경로는 수동 브리지로 간다.

## 5. 이 세션에서 배운 교차 세션 법칙 (전부 CLAUDE.md/REGISTRY에 반영됨)

- **번호는 origin의 REGISTRY.md에서** 청구한다. `ls`는 목록이 아니다 — 그리고 렉시컬 정렬이라 `117_`이 `97_`보다 앞에 온다.
  **시퀀스의 구멍은 공석이 아니라 청구된 자리다** (0083이 그 예).
- **이넘 값 추가는 자기 파일에.** `alter type ... add value` + 같은 트랜잭션 사용은 하네스 `--single-transaction`에서
  터진다(= `db push`와 동일). 오토커밋에서는 통과해서 더 위험하다.
- **0082는 이넘 독립적이다** — `promote_route_from_run`이 `end_reason='completed'`만 보므로 이넘 값이 늘어도
  코스 승격에 닿지 않는다. 이 성질이 깨지면 REGISTRY도 같이 고칠 것.
- **잘못된 방송은 원본과 같은 도달범위로 철회한다.** (제가 `0084:188`을 "낡은 코드"라고 오독→방송→철회했습니다.
  그 줄은 `compute_owner_charge`(보호자 원장) 안이고, ⑨는 **러너** 지급을 바꾼다. 줄이 낡았다고 말하기 전에
  **감싸는 함수**를 먼저 확인할 것.)
- **`git remote set-head`는 클론당 1회** (`refs/remotes`는 워크트리 공유). 워크트리마다 다른 건 **베이스**다.
- `redesign-v4`가 GitHub 기본 브랜치가 됐고 **`main`은 삭제**됐다 — 새 워크트리가 낡은 채 태어나던 원인이 제거됨.

## 6. 알려진 상태 — "고치지" 말 것

- **반포 시드 9개는 전부 `candidate` + `trace='[]'`가 정상**이다. 파운더 워크(개 동반 완주)만이 활성화 경로다.
- **`fetchCoursePatches`가 전 상태를 읽는 것은 의도**다 — earned 패치는 상태 무관(은퇴한 코스가 달린 기록을
  지우지 않는다), locked만 active. 사다리 도입 때 candidate 완주 패치가 사라지던 버그를 고친 것.
- **`compute_owner_charge`의 `runner_personal_distance_only` 팔은 낡지 않았다** (⑨는 러너 측만 바꾼다).
- 워크트리 `keen-maxwell-add64d`는 `dacf789`에 269 커밋 뒤처져 있다 — 이 세션의 모든 작업은 **메인 체크아웃**에서 했다.

## 7. 환경 (이전 핸드오프에 추가)

- **deno는 이제 `brew install deno` (2.9.5)** — 예전 핸드오프가 가리키던 세션 스크래치패드 경로는 사라졌다.
- 하네스는 워크트리에서 못 돈다(유닉스 소켓 경로 한계) — 메인 체크아웃에서 실행.
- `git pull --rebase origin redesign-v4`처럼 브랜치를 명시하면 `origin/HEAD` 갱신 이후 "Cannot rebase onto
  multiple branches"가 난다. 그냥 `git pull --rebase`를 쓸 것(트래킹 설정이 해결).
