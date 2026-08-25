# Spec v2 addendum — Mode A (the owner who runs their own dog), full delineation — v2

**Provenance.** Ordered by Sean 2026-08-25 (console rulings #2, verbatim): *"on top of both
options, the owner can participate themselves and just pay the club fee and not pay for a
runner. we need to figure out all the screens and maps and etc for this side as well, full
flushed."* Money answer ruled in the follow-up round (F2): **participation stays FREE**, and
his copy is verbatim — surfaces state **「무료로 크루 참가」**. This v2 folds a blind
adversarial review of draft 1 (16 findings, LAND-AFTER-FIXES — log in §7). 🔵 = proposal,
reversible; 🔴 = his.

---

## 1. The participant ladder (A0-A6) — one row per state

The subject is the SELF-RUN PARTICIPANT — an owner with their dog, and (per ruling #6) any
dogless crew member; both hold only a `session_people` row and share every state below except
the dog-specific cells.

| # | State | Underlying facts (shipped unless marked NEW) | Participant sees / does |
|---|---|---|---|
| A0 | 참여 신청 | `session_rsvp(p_session, p_dog, waiver)` — `session_people` + (with a dog) `session_dogs (custody='owner_handled')`, no booking, no money, no host decision (0048:158-191). **Format law (review F6): `session_rsvp` never reads `club_sessions.format` — a `delegated_only` session accepts 동반 dogs today, and `_club_total_dogs` (0048:78-82) makes them eat the shared dog cap. NEW server gate: 동반-with-dog refused in `delegated_only` (dogless RSVP stays open); client CTA gated the same way (`session/[sid].tsx:1215` is format-blind today).** **Silent-no-op defect (F4): if the dog is already DELEGATED in this session, the dog insert `on conflict … do nothing` (0048:189-191) succeeds silently — the owner gets a success haptic while holding zero 동반 dogs, and the client's `already_registered` handler (`session/[sid].tsx:230`) is dead code (that token is `session_delegate_dog`'s, never rsvp's). NEW: rsvp raises `already_delegated` on the conflict; client renders it.** | the mode fork; capacity shown honestly WITH its pool ("남은 자리 N — 위탁과 공용"); the free line, his words: 「무료로 크루 참가」 |
| A0-h | 호스트 본인의 개 (F5) | **Structurally impossible today**: the host already holds `session_people (role='host_runner', unique(session_id, profile_id))` (0030:76/189), so `session_rsvp` raises `already_joined`, and no other writer creates an `owner_handled` row. In a Banpo club the host IS a dog owner — ruling #10's "each possible step and scenario" makes this unskippable. 🔵 NEW small arm: `session_host_add_dog(p_session, p_dog)` — host-gated, inserts only the `session_dogs (owner_handled)` row (their people row exists), same format/capacity/conflict gates as A0 | host's session screen gains a 내 아이도 함께 button |
| A0-x | 모드 전환 A→B/C (F7) | Today the switch is DESTRUCTIVE: `session_delegate_dog` refuses while the 동반 row lives (`already_registered` — `service_state` is null on owner_handled rows, always "distinct from 'ended'"), so the owner must `session_cancel_rsvp` first — which DELETES their `session_people` row (shell access, chat, incident standing, check-in evidence) and re-opens their seat to a race (0052:220-221). "I twisted my ankle, run my dog for me" is a routine, high-emotion path. 🔵 NEW: a switch arm on `session_delegate_dog` (or a dedicated RPC) that converts the 동반 row to a delegation application IN PLACE — people row kept, seat kept, then the normal P0 ladder | one 러너에게 맡기기 door on the A-mode card, honest about what changes |
| A1 | 신청 완료 → 세션 전 | pass/ticket exists; the S2 board adds their 보호자 동반 / crew row (today invisible — 0053:330) | ticket · board · free cancel (see A6) |
| A2 | 체크인 | `session_checkin` (0030:245), window T−2h..+6h, TWO client entry points (F11): the pass (`pass/[sid].tsx:124`) AND the session screen (`session/[sid].tsx:1226`). ⚠ **The stamp is WIDE (F3): it marks `checked_in_at` on EVERY `session_dogs` row where `responsible_profile_id = auth.uid()` (0030:258-259) — including a mixed-mode owner's DELEGATED, un-handed-over dog, which then satisfies the no-show fee's attendance gate (0118:1247) without a handoff.** The two ladders meet HERE, at a money gate — draft 1's "they meet only at the board and recap" was false. Named for S4: the per-pairing evidence redesign (main spec §7.4 + ruling #14's durable owner-attended record) must scope this stamp per-pairing so an owner's personal check-in never manufactures attendance evidence for a delegated dog | one check-in tap; both entry points stay |
| A2-x | 창을 놓친 참가자 (F12) | check-in window missed → no `checked_in_at`, excluded from recap counts (0118:1134) and no activity row — but A3 is still physically reachable | the run view works regardless; the recap honestly omits them (copy says why) |
| A3 | 러닝 — his "screens and maps" | **NEW SURFACE — the participant run view** (§2, §3). Today no club screen serves a self-runner or crew: `club/run/[sid].tsx` drives delegated BOOKINGS. F13: dogless crew (ruling #6) get this view too — it is a PARTICIPANT view, not an owner view | route map with the COURSE polyline (new client work — F10: today's run screen draws only the runner's own breadcrumb, `:372`, and never reads `routes_public`) · crew/dog list with board STATES (no live GPS of others — §5) · own tracking per §3 · **the SOS/case entry, which they already have standing for** (shell `full` → `club_incident_open`, 0049:14, 0067:68) |
| A4 | 종료 — 즉시 해제 | RULED (morning commentary): owner-run dogs release at their own finish. The shipped half: `owner_handled` rows are outside `_club_dogs_unresolved` (0045:328-336). The other half is a PROPERTY S5 MUST PRESERVE, not a shipped fact (F9): the run-end confirmation's population must keep excluding `owner_handled` — pinned in S5's suite | their finish tap closes THEIR record (§3); zero host dependency |
| A5 | 리캡/기록 | recap counts checked-in people/dogs (0118:1131-1147) — includes them today; their run report exists once §3 records, carrying the care stats his Q1 ruling put in every report | recap post · own run report |
| A5-x | 세션이 끝나지 않으면 (F12) | `club_finish_session` is host-only; ruling #3's 6h auto-confirm covers RUN-END, not session close. For a session with ZERO delegated pairings the two-phase finish has no money job at all — S5 note: **owner_only-in-practice sessions close directly** (the closer's `run_confirmed_at` requirement applies only when delegated pairings existed), plus the main spec's 🔵 auto-close when all pairings resolve | nothing hangs on the host for a pure-동반 session |
| A6 | 이탈/취소 | `session_cancel_rsvp` (0052:205) — free, BUT (F8) it has NO time gate at all: it works mid-run and after `done`, deletes the `session_people` row, cascades away the `participant_activities` record (0030:104 `on delete cascade`), erases recap presence and incident standing. 🔵 NEW gate: refuse after the participant checked in (`already_checked_in`) — leaving after check-in is a real-world event, not a record deletion; their standing and records survive | cancel with honest copy: free before check-in; after check-in the record stands |

**The mixed-mode participant** (the review's "biggest missing scenario") is now first-class:
one person may hold a 동반 dog AND a delegated dog. The ladders meet at A2's wide stamp (money
— S4 closes), at A0's shared dog cap, at `session_cancel_rsvp`'s `delegation_active` refusal
(shipped, correct — the delegation must resolve first), and — if they are also a committed
runner — at `_club_runner_load`'s own-동반견 term (0047:62-64): **a handling runner who brings
their own dog spends one delegated slot on it**, and the commit surface must say so (F14).

## 2. Screens (client — per state)

- **Session screen fork**: A-mode card renders A0→A6 states; the 「무료로 크루 참가」 line
  (his verbatim copy) on the fork; the format-gated CTA (A0); the A0-x switch door.
- **Pass**: unchanged EXCEPT it remains one of two check-in entry points (F11) — both stay.
- **Participant run view** — NEW, one screen serving self-run owners AND dogless crew (F13):
  course polyline from `routes_public` (new work), own live position/stats when tracking
  (§3), crew list with board states, per-participant finish, SOS/case entry carried forward.
  🔵 Build as a `participant` mode of `club/run/[sid]` — the GPS/trace/map plumbing is there
  (map card `:395-422`), but the honest estimate: course polyline, bookingless finish, and
  the mode fork are all new code; only the map shell and GPS watcher are reuse (F10 sized).
- **Board (S2)**: 보호자 동반 + crew rows as specced.
- **Recap/report**: the owner running-report surface once §3 records.

## 3. What records a self-run — REDONE after review (F1, F2 were both right)

Draft 1's premise was wrong twice. The facts as verified:

- `dogs.cumulative_km` / `streak_days` are **dead columns** — zero writers anywhere. The real
  fitness system is a CLIENT derivation: `fetchFitness` (api.ts:2490-2596) computes weekly km,
  buckets, streaks, and the fitness-age gate from `bookings (status='completed')` joined to
  `runs`. Any record that should move the owner's 체력 card must be read THERE.
- **`participant_activities` (0030:101-113) already IS the record draft 1 proposed to
  invent**: session_id, person, dog, km, pace, duration, photos, a NULLABLE `run_id`, a
  `source` enum with an unproduced `'self_reported'` value, and `unique(session_id,
  person_id)` idempotency. Two shipped producers: `session_checkin` (`'checkin_only'`,
  0030:262-264) and the runs trigger `_club_log_activity` (`'gps_verified'`, 0038:139-160).

**The design, v2** 🔵:
1. The participant run view's finish WRITES `participant_activities` — upserting the
   participant's row from `'checkin_only'` to `'gps_verified'` (GPS-measured km/pace, same
   fix-gating as the runner screen) — a new party-gated RPC, no new table, no `runs` row, no
   booking, no money reader touched. The dead `self_runs` idea is dropped.
2. **Traces and photos do NOT ride `participant_activities`** (F15): its RLS is
   `using (auth.uid() is not null)` (0030:138) — every authed user reads every row. km/pace
   at session scope is board-adjacent and acceptable; a GPS TRACE is not. Traces go to an
   owner-only store (own table, owner-read RLS, joining 0120's retention regime when it
   lands); photos use owner-scoped storage ACLs. The world-readable RLS on
   `participant_activities` itself is flagged for the slice's adversarial review (tighten to
   session-party? — reviewer's call with a pin either way).
3. **Does a self-run move the owner's 체력 card?** 🔵 YES — it is the same dog genuinely
   running, and a fitness card that ignores it is dishonest by the repo's own laws. This is a
   `fetchFitness` extension (union the owner's `'gps_verified'`/`'self_reported'`
   participant_activities into the weekly/streak derivation) — CLIENT work, no server schema
   change, and the exact coupling drafted option ⓐ was punished for is simply named here as
   the real, bounded cost. If Sean ever wants self-runs excluded from 체력, it's one filter.

## 4. Money — CLOSED by ruling F2

Free, permanently unless he reopens it; surfaces carry his verbatim 「무료로 크루 참가」. No
mint, no refund arm, no ladder interaction. A6's copy stays fee-less.

## 5. Privacy edges

1. **No live GPS of other participants** 🔵 — board states tell the story; the map shows the
   ROUTE. Revisit only with his ranked-dashboard idea, as its own consented design.
2. Self-run traces: owner-only by construction (§3.2) — a NEW requirement, not an inherited
   one (F15: the existing club tables are authed-world-readable; nothing here inherits a
   boundary that doesn't exist).

## 6. Sequencing

- The A0 gates (format, `already_delegated`), A0-h, A0-x, and the A6 gate are ONE small
  server slice (rsvp-family hardening) — independent of S2-S5, adversarial cycle, suite pins
  both ways.
- The participant run view + §3's record RPC ride AFTER S2 (board states feed the crew list).
- A2's wide-stamp money fix belongs to S4 (it IS the per-pairing evidence redesign) — named
  there, not duplicated here.
- A4's exclusion property and A5-x's zero-delegation close rule are S5 pins.
- Nothing here blocks the delegated-side slices; the mixed-mode meeting points are named
  above and owned by the slices that already exist.

## 7. Review log

Draft 1 → one blind adversarial pass (2026-08-25): LAND-AFTER-FIXES, 16 findings. All folded:
F1 (fitness accruals live in `fetchFitness`, not the dead columns — §3 redone) · F2
(`participant_activities` is the shipped record — the invented table dropped) · F3 (A2's wide
stamp is a money-gate meeting point — named, S4 owns the close) · F4 (silent no-op RSVP +
dead client handler — A0 gate ordered) · F5 (the host cannot run their own dog — A0-h) · F6
(no format gate — A0) · F7 (destructive mode switch — A0-x) · F8 (cancel-rsvp has no time
gate and cascades records away — A6 gate) · F9 (`club_confirm_run_end` cited as shipped —
rephrased as an S5-preserved property) · F10 (reuse overclaimed; course polyline is new —
§2 resized) · F11 (two check-in entry points) · F12 (three terminal states — A2-x, A5-x,
host-cancel folded into A6's copy scope) · F13 (crew get the run view) · F14 (runner's own
dog burns a slot — named with its surface) · F15 (privacy leaned on projection — §5 restated
as new requirements) · F16 ("FULFILLED" softened: §15-bis is fulfilled when this document's
slices land, not by the document). Verdict after fold: implementation brief for the three
slices in §6.
