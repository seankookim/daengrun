# Wave 3 — server honesty slice (contracts, 2026-08-07)

Scoped from honesty-batch-sunbaek-spec.md WAVE 3 + wave-2.5 riders, against the scout fact
sheet @ 8151139 (all claims code-verified). Sean pre-approved the wave at the 2.5 gate (D2=A).
Process: full adversarial cycle + PG16 harness (target 235+N/0). Build in MAIN checkout.

## Sequencing law (restated per eng review)

**The load-bearing hole in create-booking-hold is `dog_id`, not just address**: index.ts:52-54
writes `dog_id` from the body with zero ownership validation on a service-role client, and the
0042 marketplace view joins dogs and exposes name/breed/weight/memo/photo/preferences/
vaccinations to EVERY active runner — so an attacker can publish a victim's dog dossier into
the open pool today with no acceptance needed, and the dog-clash guard doubles as an
availability DoS on the victim's dog. Item 4 closes both. The address vector is closed twice:
item 4's check AND the RPC's internal `a.owner_id = b.owner_id` re-verification (legacy
poisoned rows stay unreadable).

## Item 1 — 0060 `booking_pickup_address(p_booking uuid)` definer RPC

```
returns table (label text, addr text, detail text)
language plpgsql stable security definer
set search_path = public, pg_temp        -- IN BODY (98 H1 law; never ALTER-applied)
```
(plpgsql, NOT sql — RAISE is a plpgsql statement; body shape: gate-if → raise / `return query`.
**lat/lng DROPPED from the contract** — every production value is NULL (no geocoding path
exists); pinning dead columns forces the coordinate slice to edit W6 later. ⚑ Sean-review.)
- Gate (single predicate, NULL-safe per 0054:74 / 0055:50 coalesce idiom): booking exists AND
  `coalesce(b.runner_id = auth.uid(), false)` AND (`b.status in
  ('runner_enroute','picked_up','active')` OR (`b.status = 'confirmed'` AND
  `b.scheduled_at < now() + interval '24 hours'`)) — else `raise exception 'not_runner'`.
  Absence and not-yours are INDISTINGUISHABLE (0054:73 oracle principle).
  ⚑ **Sean-review decision (conservative default, two-way door):** a confirmed booking can sit
  for DAYS; exposing the home address from accept time contradicts 0001:124's session-scoped
  posture. 24h window keeps day-of route planning + the runner/home card useful (far-out jobs
  simply render no address line — the card's address row is conditional). Widen = one-line
  migration if Sean prefers.
- `address_id is null` OR address row's `owner_id <> b.owner_id` (poisoned legacy row) →
  **return zero rows** (client renders 미지정). Error ≠ empty — distinct signals.
- **NEVER selects `gate_code_enc`** — structural exclusion pinned by a V10-clone contract
  test (proargnames + runtime jsonb_object_keys vs whitelist + leak regex extended with
  `gate|code|enc|owner|phone`); the runtime-keys half MUST run against the W1 happy fixture
  (≥1 row — to_jsonb over zero rows yields NULL keys and the assert collapses).
- Tail: `revoke execute … from public, anon; grant execute … to authenticated;` + comment.
- STABLE (no audit logging this wave — the "access log" rider is a Sean call; note
  gate_code_access_log is an empty never-written shell, and adding a log makes the fn
  volatile. Template when wanted: club_phone_access_log 0049 pattern).

## Item 2 — 0060 hold expiry (same migration; not money arithmetic)

- `expire_unmatched_bookings()` REPLACED (must re-state `set search_path = public, pg_temp`
  in body — the 0055 ALTER dies on create-or-replace). **MANDATED STRUCTURE: two sibling
  CTEs** — `e_match` (existing matching/runner_pending clause unchanged, drives the existing
  '매칭 만료' noti CTE; X1/X2/D13 stay green, `club_session_id is null` carried) and
  `e_hold` (`status='payment_hold' and created_at < now() - interval '30 minutes' and
  club_session_id is null` → expired, **NO notification** — nothing was charged; '전액 환불'
  would be a lie). Return `(select count(*) from e_match) + (select count(*) from e_hold)`.
  A merged single-UPDATE is FORBIDDEN: RETURNING yields NEW values only (PG16), the classes
  become indistinguishable, and every hold owner gets the refund lie. (`created_at` is the
  anchor — bookings has no TTL column and `scheduled_at` keeps next week's hold alive.)
- `payment_ok` in transition-booking becomes a CAS (`.eq('status','payment_hold')` on the
  update, select-returning) → expiry-vs-pay race resolves to an explicit 409 with the pinned
  string `'결제 시간이 만료됐어요 — 예약을 다시 만들어주세요'` (pay.tsx renders server
  strings verbatim; payphase maps expired→cancelled so the retry path lands honestly).
  NOTE for the builder: the `bk.runner_id ? "runner_pending" : "matching"` branch at :29 is
  pre-existing DEAD code (payment_hold→runner_pending is not in the 0047 transition map and
  createBookingHold never sends runner_id) — do not preserve it as if it worked; keep
  matching as the sole CAS target and leave a comment.
  A parked pay screen CAN be inside the grace window (no timer exists on pay.tsx) — the CAS
  409 + honest terminal screen IS the designed degradation, not an impossibility claim.
- `purge_expired_holds()` REPLACED: drop the `booking_id is null` clause (every real hold
  carries booking_id → today it purges nothing and slot_holds grows unbounded), KEEP
  `expires_at < now()` (is_slot_available reads only future-expiry rows — safe), re-state
  pg_temp in body, and **add the missing cron** (`purge-holds`, `*/5 * * * *` on a different
  minute offset than expire-unmatched via `1-56/5`, wrapped in the guarded do-block pattern).
  Note: 0057 revoked all roles — cron executes as job owner, unaffected; keep the revoke.

## Item 3 — arrival becomes server truth (0060 column + transition-booking action)

- 0060: `alter table bookings add column arrived_at timestamptz;` (guard trigger 0058 blocks
  client writes already; check 98/80 column-enumeration pins and extend if they assert an
  exact set).
- transition-booking new action `arrived`: gate `isRunner` + CAS UPDATE
  `.is('arrived_at', null).eq('status','runner_enroute')` with select-returning.
  **IDEMPOTENT SUCCESS (non-negotiable — prevents a handoff lock-out):** when the CAS
  returns 0 rows AND `bk.arrived_at` is already set → `return { unchanged: true }` (200,
  NO notify — mirrors the :39 re-tap idiom). Only a genuinely wrong state (status ≠
  runner_enroute AND arrived_at null) throws 409. Notify fires ONLY when a row returned
  (exactly-once by construction; the `enroute` double-fire bug is NOT copied — rider).
  Notify: `notify(bk.owner_id, "러너 도착", "러너가 픽업 장소에 도착했어요 — 인계를
  준비해주세요")`. No status change. Also add `arrived_at: null` to transition-booking's
  runner-swap `resetPatch` (:77 class) — a stale stamp from a replaced runner must not
  suppress the new runner's arrival (0057/0038 reset patches are riders, named).
- push.ts routeForNotification: owner branch matches EXACT titles (substring collides with
  live `새 사진 도착 📷` / `위탁 배정 도착` / `위탁 신청 도착`):
  `const LIVE_TITLES = ['러너 도착', '러너 이동 중']; LIVE_TITLES.includes(title) ?
  '/owner/meetup' : '/owner/report'` — the two literals are a server↔client contract pair
  (transition-booking:186 + new arrived case). alerts.tsx:62 shares this router; its
  tag-taxonomy regex does NOT gain `도착` (would recolor the photo/club titles) — the
  untagged rendering of 러너 도착 in the inbox is accepted (rider).
- fetchBookingSync widens: SELECT + BookingSync gain `arrivedAt` (`arrived_at`). NOT covered
  by check-rpc (plain select) → e2e step asserts the field (wave-2 M4 precedent).
- Client copy flips IN THE SAME COMMIT — **BOTH sides consume `arrivedAt`:**
  - runner/meetup 도착 확인 button calls the server action; local stage advances ONLY on
    success or `{unchanged:true}` (P1-4 law); on failure: loud strip + stage unchanged.
    **syncNow gains a restore branch** (placed after the runnerConfirmed branch):
    `else if (s2.arrivedAt) setStage((cur) => (cur === 'enroute' ? 'arrived' : cur));` —
    without it, a remount after arrival strands the runner on 'enroute' forever (gear check
    + handoff CTA gated behind 'arrived'). Post-success hint `보호자에게 도착 알림이 갔어요`
    is state-derived (survives remount via arrivedAt); pre-tap hint → `도착을 확인하면
    보호자에게 알림이 가요`.
  - owner/meetup: retire the :320-321 '도착 상태는 서버에 없다' comment+copy. The `러너 도착`
    string goes on the surfaces LIVE at that moment — the eta pill (:217-219) and rail label
    (:293) — NOT the stage==='enroute' status card (unreachable once arrived: the frozen
    mapping puts the screen in stage 'arrived' by then). One added useState for arrivedAt;
    hook-placement law below.

## Item 4 — create-booking-hold ownership checks (edge function)

After the missing-fields check: `dogs` row where `id = dog_id AND owner_id = uid` must exist
→ else 403 with the SINGLE opaque message `forbidden` for both absent and foreign
(enumeration oracle, 0054:73). Same for `address_id` when present (`addresses.owner_id = uid`).
Two maybeSingle() selects on the service-role client. Verified safe: recurring (0026) and club
(0043) bookings insert server-side and bypass this function — no legit flow breaks.
e2e negative step: owner tries a foreign dog → 403; the foreign dog is created via the
admin() client under a throwaway profile so the step works in --solo mode too (in solo the
"other owner" would otherwise be the caller and the step would false-pass).

## Item 5 — client rebind (api.ts + runner screens)

- api.ts: `PickupAddress {label, addr, detail}` + `fetchBookingAddress(id):
  Promise<PickupAddress | null>` — `rpc('booking_pickup_address', { p_booking: id })` (NEVER
  the `{ p_booking }` shorthand — check-rpc's key regex requires the colon and would fail the
  gate); zero rows → null; error THROWS (tri-state law).
- runner/meetup pickup card (:214-220): loading `주소 확인 중...` / loaded real `label` title
  + `addr · detail` body (14pt floor; s.cardBody 14/20 holds 3 lines) / null → existing
  미지정+채팅 copy stays / error → loud strip `주소를 불러오지 못했어요 · 다시 시도`
  (paper.critical family), chat chip always alive. **NO 길찾기 button, NO map** — all
  production lat/lng are NULL (no geocoding path exists); dead-button law. Coordinate slice
  (geocode on addAddress or map-pin picker) = named separate item.
- runner/home in-progress card: fetch keyed on `current?.bookingId` ONLY (the RunnerJob field
  — `current.id` does not exist; never map the 20-row jobs list); renders label/addr
  one-liner when the RPC returns rows (far-out confirmed jobs: no rows under the 24h window →
  no address line, by design).
- **Hook-placement law (both meetup files, frozen once-law):** new useState goes at the END
  of each file's existing useState cluster (runner: after `check` :71, before `useRef poll`
  :73; owner: after `synced` :67 — poll sits BEFORE the cluster there); new useEffect
  immediately AFTER the fetchMeetupInfo effect (runner :90-93 / owner :92-95) — NEVER after
  the hydrated-gate effect (runner :174 / owner :188, which must remain the last effect;
  hook count changes allowed ONLY at those insertion points, sequence otherwise
  byte-identical).

## Test plan (harness target 246/0, macOS invocation per memory/handoff)

New suite **`100_wave3_suite.sql`**, harness.sh line APPENDED AFTER the 99 line (suites are
hardcoded, not globbed; running last lets it reuse 97's t_av_* helpers and keeps its global
`expire_unmatched_bookings()` call behind every other suite — 95-99 fixtures are future-dated
so pick a disjoint window, e.g. 2026-10-20). 11 pins (each with a named single-revert
mutation proof in the header, 99 convention):
- W1 RPC happy: assigned runner + confirmed booking → exactly label/addr/detail (lat/lng are NOT
  in the contract — see Item 1; the suite asserts the 3-column shape).
- W2 gates (97 V9 clone, 5 sub-cases): stranger / nonexistent booking / owner / unauth /
  anon role → 'not_runner' ×4 + permission-denied.
- W3 status gate: completed booking → 'not_runner' (IN_FLIGHT only).
- W4 null address_id → zero rows (not an error).
- W5 poisoned address (owner mismatch) → zero rows.
- W6 shape+leak (97 V10 clone, regex + gate|code|enc|owner|phone).
- W7 payment_hold expiry: 31-min-old payment_hold → expired, ZERO notifications; 29-min-old
  survives; club hold untouched; matching-class behavior unchanged (X1 stays green).
- W8 purge: expired hold WITH booking_id deleted; future-expiry hold survives.
- W9 arrived_at: CAS semantics — second update matches no row (single notification), guard
  trigger still blocks client writes (S2-adjacent).
- W10 batch-fn grants: `has_function_privilege('authenticated', fn, 'execute') = false` for
  expire_unmatched_bookings() + purge_expired_holds() (99 S1 covers anon only; this catches
  a future drop+create re-grant).
- W11 transition-trigger non-interaction: postgres-role `update bookings set arrived_at=now()`
  on runner_enroute succeeds with status unchanged (before-update-OF-STATUS trigger doesn't
  fire); same statement as authenticated raises booking_protected_columns.
- e2e.mjs additions: arrived step (notify body + arrived_at set + double-call → 200
  {unchanged} + still ONE notification) · ownership 403 step (admin-created foreign dog,
  solo-safe) · fetchBookingSync arrivedAt field assert.

## Sean queue after this wave
0. Blast-radius measurement BEFORE db push (SQL editor):
   `select count(*), min(created_at) from bookings where status='payment_hold' and
   created_at < now() - interval '30 minutes';` — silent mass-expiry is fine at N=12,
   a conversation at N=1200.
1. `supabase db push` (0060) → `supabase functions deploy transition-booking
   create-booking-hold` → prod 0-row anon-definer check → device smoke → `git push`.
⚑ Sean-review decisions taken conservatively (both two-way doors): confirmed-status address
window = 24h pre-run · lat/lng dropped from the RPC contract until the coordinate slice.

## NOT in scope (named)
Geocoding/coordinates/길찾기/real meetup map (separate slice) · gate-code decrypt path ·
address access audit log (Sean call; RPC stays STABLE until then) · enroute double-fire fix
(rider) · signed-out→[] collapse in fetchMyDogs · CLAUDE.md commit-language line reconcile
(rides in this wave's commit as a one-line docs fix).
