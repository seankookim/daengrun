# Session handoff — refreshed 2026-09-15 (new Mac, first session) — everything below the 09-15 block is the 08-31 record

**Read this before doing anything.** `CLAUDE.md` holds the permanent laws; this file holds
current state. **New since 08-31: `docs/codex-claude-protocol.md` (who does what — Codex astra
writes, Claude orchestrates/gates/lands) and `docs/prompts/codex-app-master.md` (Sean's paste
sheet for the Codex app).** Where a line below conflicts with the 09-15 block, the 09-15 block wins.

> 🔴 **DEPLOY FREEZE — STILL HOLDS, and the reason changed.** Trunk `069459b` now carries ALL
> FIVE pending migrations (0157 · 0158 · 0159 · 0160 · 0161) — B1/0157/0158 landed from the rescue
> branches 2026-09-15 with every gate re-run on the new Mac. Production is still `0156` (last
> measured 08-31; `supabase login` has not been done on this machine, so `migration list --linked`
> cannot be re-read here). Two things gate the ONE deploy: **(1) `supabase login` (Sean)**, and
> **(2) the codex verdicts for the five files — NONE EXISTS.** 0159 is REJECT/11 (fixed by 0160,
> the fix unreviewed); 0160/0161/0157/0158 have no verdict. Per Sean 2026-09-15 codex is for build
> work, so the review is a single diff-scoped `gpt-5.6-sol` high run when the deploy is actually
> possible — not a repo sweep (three parallel sweeps burned 673K tokens for zero verdicts today).

## 2026-09-21 — ⑪ + ⑫ THE RUN-END CEREMONY IS BUILT (branch `feat/run-end-ceremony`, 0188 + suite 219)

**The largest unbuilt piece of the 1:1 journey now has product callers.** Ruled and ASSIGNED
2026-08-13 (`docs/decisions/awaiting-sean.md` §5) to a session that ended; the server half has been
shipped and INERT since August — `end_run_tx` (0083 §3) had **zero callers**, `settle-run` flipped
`active → completed` at the stop with the dog still on the leash, and `runner_work_gate` (0092)
could only block on states the marketplace path never produced.

**The sequence as built (1:1 only — the club path is 0168's and is untouched):**
runner stops → edge `transition-booking { action: 'end_run' }` → `end_run_tx` freezes
km/duration/reason/trace and stamps `run_ended_at`, status STAYS `active` (「끝났지만 아직 안
돌려줬다」 — the state ⑫'s work gate reads) → the owner is asked 「반환 확인 요청」 and the runner is
work-gated from that instant → both parties stamp via `{ action: 'confirm_return' }` → **the SECOND
stamp seals AND settles inside the same locked transaction**, because the edge (service_role) brings
a price. That is 0083 §6's own designed shape (`p_quote`), used for the first time, and it is why a
client that dies after its tap cannot strand a settlement: the stamp and the settlement are ONE
statement on the server.

**Client:** new route `runner/return-seal.tsx` (lab R6a/b/c — 내 봉인 · 보호자 대기 · 양측 봉인, seals
drawn from server columns only, poll until the pair completes, celebration once per booking) ·
`runner/run.tsx`'s stop path calls `end_run` and routes to the seal instead of settling ·
`runner/home.tsx` gains the R1c work-gate strip (WHY + the exit; the accept door is replaced by a
SENTENCE while the gate is shut, never a coral that fails after the tap) · `owner/report.tsx` gains
the ⑫ 반환 확인 gate above the record.

🔴 **The defect this slice ARMED and had to fix, because arm ⓑ had never seen a real row:**
`sweep_run_end_recovery` escalated a stranded return `active → incident_review` unconditionally at
2h. On a row where a party has ALREADY said the dog is home that is **permanent unpayability** —
`_settle_sealed_run` is `active`-only and `enforce_booking_transition` gives `incident_review`
exactly one edge, `refund_pending` (`0066:56`) — and since 0096 made a late stamp possible, the
runner walks the dog, brings it home, both parties confirm, and the money can never move. **And the
escalation frees nobody**: 0092's gate reads the two stamp columns and ALSO catches
`incident_review` (pinned, `0188-B3`). 0188 narrows it to ZERO-stamp returns and alarms the rest
without moving state — arm ⓓ's own principle three arms down.

⚠ **Sean-only follow-up, and it is what actually closes the old-client hole:** set
`ops_flags.return_seal_since` AFTER this client build reaches devices. Until then a pre-build binary
can still settle a run it never ended — 0083's deliberate grandfathering arm, not a regression.
⚠ **NAMED RESIDUE, deliberately not closed:** a return NOBODY confirms still escalates at 2h and is
still a dead end if both parties stamp afterwards. Narrowing that means deciding what a clock may do
with money, which is Sean's (`awaiting-sean.md` §4).

**A COLD EXECUTING REVIEWER RETURNED `REJECT` WITH 12 FINDINGS, AND ALL 12 WERE FIXED BEFORE THE
COMMIT.** Two were serious and neither was visible from inside the slice:

🔴 **`active` stopped meaning 「running」 and five live surfaces were never told.** `owner/live.tsx`
had NO exit — its 1 s tick kept an elapsed clock climbing off `runs.started_at` forever, the island
printed `● LIVE · 달리는 중` over a dog being walked home, and its 5 s `updateOwnerActivity` kept
OVERWRITING the server's `homeward` Live Activity banner (0083 §8-ⓑ): two channels, contradictory,
client wins. The same widening hit owner home's hero, `owner/schedule`, and runner home's
`STAGE.active` — which contradicted THIS SLICE'S OWN work-gate strip on the same screen. Fixed by
carrying `run_ended_at` on every in-flight projection and adding a seventh hero state `returning`
(not folded into `handoff`, whose copy is the PICKUP). This is CLAUDE.md §④ — the defect is the
UNCHANGED line — one status level up, and nothing failed to compile.

🔴 **`confirm_return_tx` was granted to `authenticated`, and this slice ARMED it.** It is in
`public`, PostgREST exposes `public`, so a signed-in party could POST the RPC directly — and a
client may not bring a price, so a direct SECOND stamp sealed with no settlement and no in-app
repair (both stamps ⇒ every confirm CTA disappears by construction). 0188 §B revokes it; the
tempting alternative (raise on `v_both and p_quote is null`) was refused because it would delete
0083 §6's designed seal-now-settle-later capability that suite 133 exists to detect.
⚠ **My own suite header and the edge's §2 had BOTH argued that hole was 「unreachable through every
product surface this slice ships」** — a claim about our BUTTONS used to license a conclusion about
a PRIVILEGE. Both paragraphs are kept and CORRECTED rather than deleted.

**Gates, all re-run after the LAST edit:** harness **1307 → 1316 / 0**, delta exactly the 9 pins
added, each present by label · deno **336 → 354 / 0** · `npm test` exit 0, **1042 PASS + 38 ✅ / 0
FAIL** (1023 → +19) · tsc + all six check scripts exit 0. Battery in a lab COPY, control observed
clean first, every run `&&`-chained to its plant. ⚠ **The battery found two defects in ITSELF**: a
plant that landed in a definition `0169` had superseded (green for the wrong reason), and a pin
whose lock arm matched a string three other arms also carry — uninformative in both states, inside
a pin written to enforce rigour. Both recorded in the REGISTRY row rather than quietly fixed.
**NOT reviewed by codex** (this session was forbidden codex/CLI/deploy — the cold reviewer is an
Opus subagent, not codex) and **NOT deployed**.

## 2026-09-21 01:40 — session resumed (three-day gap); Sean: 「focus on building what's not there yet」

**Trunk unchanged at `ed65c3c` since 09-18 10:20; nothing deployed; no queue letter answered.** The
native Claude simulator tool now WORKS (`attach`/`launch`/`tap`/`screenshot` — the stale 「Xcode not
selected」 state cleared on the session restart), so device-visual checks are no longer blocked: an
incremental Xcode 27 Release build of `ed65c3c` is installed on the iPhone 16 Pro sim, and the
safe-area slice (`d3d56ea`) is **verified on device** on `/settings` (back button + title clear of the
Dynamic Island) and `/onboard/runner` (header clear, CTA dock above the home indicator, the
permission plate asks on a TAP, not on mount). The iOS 「Open in」 dialog on a cold deep link is
dismissed by a native tap at device points (269, 482); a second deep link while the app is foregrounded
shows no dialog. Seen while there: `/settings` still lists 「알림 설정 · 푸시 도입 후」 under 준비 중 —
push exists, so notification preferences are an UNBUILT surface (candidate build).
Old plan check (`docs/plans/finish-the-app-plan.md`, 08-10): A1 owner Live Activity, A2 runner LA
reskin, A3 private media, A4 riders are all BUILT since; the confirmed unbuilt items are the ops
manual payout journal (`payouts` has no writer — building now as 0186), notification preferences,
and whatever the spec gap finder returns. Sean's redirect: no more audits/harnesses; builders only.

**2026-09-21 01:47 — the build map (spec gap finder: 77 spec sentences judged, 68 built, 4 partial, 2 missing; plus
6 plan/queue items).** Building NOW, four builders in their own worktrees + one Codex task:
- **Run-end ceremony (⑪+⑫, R6a/b/c, R1c)** — `feat/run-end-ceremony`: `end_run_tx` and `confirm_return_tx`
  (0083) have ZERO product callers; `run.tsx:690` settles directly, so the work gate (0092) can never fire
  and the runner's return seal / owner's ⑫ confirm never existed. Ruled + assigned 2026-08-13 (queue §5),
  orphaned when that session ended. Server re-sequencing (settle follows the second stamp), an `end-run`
  edge action, `runner/return-seal.tsx`, ⑫ on the owner report, the R1c strip on runner home. Migration
  0188/219 if needed. Cold executing review before push; Codex review after landing.
- **Ops manual payout journal** — `be/0186`: `payouts` has no writer; `ops_record_manual_payout`,
  `ops_payouts_due`, a twice-daily stuck sweep with cron readback. Server only.
- **Notification preferences** — `be/0187` + `app/notification-settings.tsx`: the 준비 중 row goes live;
  per-category push prefs, safety always-on, enforcement on the send path.
- **Missing Korean copy on money/safety paths** — `fix/tokens`, ONE Codex astra-medium task from the
  token audit (107 client-reachable SQL functions, 350 (function, token) pairs; 46 tokens have no Korean
  anywhere): open-drop forwards the RPC's own `using detail`; arrears retry, card link, settle, incident
  settle, club return confirmation, delegation pay, `invokeTransition`'s English fold, the cancel-quote
  club remedy, the silent ledger read, and ④-1 (runner home's weekly km ignores `week_unmeasured` since
  0158 — a partial total shown as complete).
Gated on Sean, not built (queue item 22): the owner-home live strip for `runner_enroute`/`picked_up` (spec
vs `api.ts:927`'s rule), `/shop` in the 5-tab bar of a TestFlight build, decline history for owners
(privacy), `no_show` set by nothing (needs a rule), crash reporting (native dep), pre-accept distance.

**2026-09-21 01:56 — `6cf7453` Korean copy slice LANDED** (Codex gpt-6-astra medium, second attempt — the first stopped
to ask a question the prompt had left open; reviewed by hand; combined tree: deno 336/0 with the open-drop
assertions turned Korean · tsc · check-rpc · route-native-imports · npm 1023/0): open-drop forwards the
RPC's own `using detail` (token kept in `code`); arrears retry (collect-charges), card link
(register-billing-key, the Toss 402 sentence kept verbatim), settle-run, club incident settle
(`not_measured` / `quote_redacted`), club return confirmation (6 tokens), delegation pay (5 more tokens)
all map to Korean; `invokeTransition` folds any non-Hangul message to one honest line (nine screens at
once); the cancel-quote catch names the club remedy instead of a retry that cannot work; a failed
ledger read marks the runner's amounts 「추정」; runner home's weekly km says 「이상」 when
`week_unmeasured` > 0 (④-1: 0158 widened `my_week_stats` and this was the one reader left behind).
Deploy: `functions deploy open-drop` + the client build.

**2026-09-21 02:25 — `a5635a9` NOTIFICATION PREFERENCES LANDED** (0187 + suite 218 + `app/notification-settings.tsx`;
combined tree: harness **1314/0** = 1307 + 7 pins `0187-N1…N6, S1` · deno 336/0 · tsc · checks (64
routes now) · **npm 1049/0** = 1023 + 26): `notification_prefs` one row per profile, four categories
derived from the real writers (`booking` 118 sites · `chat` = 0090's title discriminator · `community`
52 · `reward` 3; `marketing` has ZERO writers so no column), `safety` + `system` always-on; enforcement in
0024's `notify_push` trigger — the safety decision is taken BEFORE the prefs table is read (0024's
`when others → return new` would otherwise be a second way to silence SOS), only an explicit `false`
suppresses, every NULL path sends; own-row RLS; `get_/set_notification_prefs` definers with ACL
restated. Client: the 준비 중 row is gone, 알림 설정 is a live row → a paper screen with switches (safety
row disabled + reason), loading sentence, fail strip + retry, optimistic toggle with rollback, VoiceOver
switch roles. Battery 12 plants; the builder's own S1 was found blind by N5 during (xii) and repaired.
Named residual: a tombstoned account keeps its four booleans (0115 ④ deletes `push_tokens`, so nothing
can be sent). Deploy: `db push` only (no edge change) + the client build. **Twenty-seven pending.**
**Device-verified 02:26** on the rebuilt sim app: signed out + RPC undeployed ⇒ the screen draws the fail
strip 「알림 설정을 불러오지 못했어요 · 다시 시도」 and NO switches (loading/failed are not default states),
header clear of the island. Codex review running.

**2026-09-21 02:30 — Codex review of 0187: REJECT / 2, both HIGH** (`docs/reviews/2026-09-21-migration-0187-codex-verdict.md`):
the client writes SOS / accident / run-stop notifications with `kind='booking'` (0114's INSERT policy
admits only `booking` from a party), so `booking=false` silences SOS — suite 218 pinned synthetic
`safety` kinds, not the real writers; and the send boundary never checks `profiles.deleted_at`, so a
tombstoned account that re-registers a token keeps receiving pushes. Correct-forward **0189 + suite 220**
assigned to the 0187 builder (title-family always-on classification before the prefs read; non-tombstoned
recipient at the send boundary; pins with the writers' real payloads). 🔴 **0187 must not deploy without
0189** — the queue says so.

**2026-09-21 02:35 — `a842fe8` OPS MANUAL PAYOUT JOURNAL LANDED** (0186 + suite 217; union-merged REGISTRY/manifest
with 0187, 0 markers; combined tree: harness **1321/0** = 1314 + 7 pins `0186-P1…P6, S1` · deno 336/0 ·
tsc · check-rpc 135/219 · check-definer-acl baseline unchanged): `payouts` finally has a writer —
`ops_record_manual_payout(runner, ledger_ids[], amount, memo)` (ops gate before any read, rows locked,
amount must EQUAL the locked rows' sum — no rounding, `already_paid` idempotent, `tax_withheld = 0` as a
statement of fact because no 사업자등록 withholds), `ops_payouts_due()` (per-runner unpaid settled
total / oldest age / count), `ledger_items.paid_payout_id`, and a twice-daily `ops-payouts-stuck` cron
(7 days, once per runner per 20 h) registered strictly with readback. The 「settled」 predicate is
「no run still in progress on the booking」, NOT `runs.settled_at` — 0072's incident settlement never
stamps it, so that anchor would refuse exactly the stranded runners this journal exists to pay.
Battery 14 plants; two blind arms found and repaired; the row lock is a NAMED GAP (a later slice owes a
`90_race_check.sh` arm). Deploy: `db push` only; no client (nothing in `app/` reads `payouts`).
**Twenty-eight pending.** Codex review running.

**2026-09-21 02:38 — Codex review of 0186: REJECT / 2, both MED** (`docs/reviews/2026-09-21-migration-0186-codex-verdict.md`):
the stuck sweep has no job lock (two overlapping ticks double-notify — the 0177/0180 shape not applied),
and 0115's bank-detail retention for tombstoned runners never ends because its predicate does not read
the new `paid_payout_id` and the writer never releases it. Correct-forward **0190 + suite 221** assigned
to the 0186 builder (try-lock + race arm; retention reads the unpaid marker; release on the final
payment; both orders pinned). The letter should carry 0190 with 0186.

**2026-09-21 02:49 — `e13c61a` THE RUN-END RETURN CEREMONY LANDED** (0188 + suite 219 + edge actions `end_run` /
`confirm_return` in transition-booking + `runner/return-seal.tsx` + ⑫ on the owner report + the R1c
work-gate strip on runner home; union-merged REGISTRY/manifest, 0 markers; combined tree: harness
**1330/0** = 1321 + 9 pins `0188-A1…D1` · deno **354/0** = 336 + 18 · tsc · checks (65 routes) ·
**npm 1068/0** = 1049 + 19). The 1:1 sequence is now: stop → `end_run_tx` freezes the numbers and
stamps `run_ended_at` (status stays `active` — the state the work gate reads) → 「반환 확인 요청」 to the
owner, runner gated → both stamp via `confirm_return_tx` → **the second stamp seals AND settles in one
locked transaction** using 0083 §6's `p_quote` (never used before), so a phone that dies after its tap
cannot strand a settlement. `settle_run_tx`'s existing `return_not_sealed` guard is now ARMED.
Two defects the slice armed and fixed: sweep arm ⓑ escalated a one-stamp strand to `incident_review`
(permanently unpayable — 0066 gives that state one edge) and now only escalates zero-stamp returns;
`confirm_return_tx` was granted to `authenticated` (a direct second stamp via PostgREST would seal with
no settlement) and is revoked. Cold executing review REJECT/12 → all fixed before push, notably five
live surfaces that read `active` as 「running」 (owner/live never exited, its 5 s tick overwrote the
server's `homeward` Live Activity banner; hero gains a seventh state `returning`). **Twenty-nine
pending.** Deploy: `db push` → `functions deploy transition-booking` → client build; then Sean sets
`ops_flags.return_seal_since` AFTER the build reaches devices (closes 0083's old-client arm). Open, for
Sean (queue item 23): a one-stamp strand is preserved but UNBOUNDED after one alarm at 2 h, and
`force_return_tx` — the named remedy — has no caller anywhere. Device-visual UNVERIFIED (rebuilding);
Codex review running.

**2026-09-21 02:55 — 🔴 a green that meant nothing, caught by the simulator build, fixed `e710ef1`:** the ceremony's
`runner/return-seal.tsx` imported its data interface `ReturnSeal` as a VALUE import beside its own
`export default function ReturnSeal`. tsc accepts a type/value name collision; Metro's Babel refuses it
(「Duplicate declaration」) — so tsc, four checks, npm 1068/0 and deno 354/0 were ALL green on a trunk
whose JS bundle could not build. New gate **`app/scripts/check-babel-routes.mjs`** (babel-preset-expo over
all 140 modules under `app/` + `src/`, ~10 s) — control-tested: the pre-fix file is refused with the exact
Metro error, the fixed tree passes. **Run it with the other checks before every commit.** The rebuilt
app installs; `/runner/return-seal` renders its honest not-found state on device (「확인할 인계가 없어요」 +
「일정으로」, header clear of the island). Codex: the ceremony review died mid-run once, then hit the
quota wall (「try again at 6:31 AM」) — a 06:41 one-shot re-runs it (SQL+edge halves) plus 0189/0190 if
landed. Its partial message flagged what I then measured: `confirm_return.ts` never calls settle-run's
`collectAfterSettle` after the sealing settle (the 5-min `sweep_settled_without_payments` covers it;
parity fix routed to the ceremony builder as `fix/confirm-return-collect`). Correct-forwards 0189
(SOS always-on + tombstone at the send boundary) and 0190 (sweep lock + bank-detail release) are being
built. Trunk `e710ef1`; twenty-nine pending; nothing deployed.

**2026-09-21 03:01 — `1474b71` collection parity LANDED** (edge-only; combined tree: deno **359/0** = 354 + 5 · tsc ·
check-rpc · check-babel-routes): `collectAfterSettle` + `afterCollectionThrew` MOVED (byte-identical) from
`settle-run/handler.ts` into `_shared/charge.ts`; both settle doors now run the same post-settle branch.
The gate is `settled && !unchanged` — 0083 §6's idempotence arm answers a completed booking
`{settled:true, unchanged:true}`, so gating on `settled` alone would have dispatched a pending charge on
EVERY re-entry of the seal screen; pinned. Doctrine kept: settlement never waits on collection, the
outcome never enters the response (the owner's 「결제 실패」 lives in `payphase.ts`). Deploy: rides with
`functions deploy transition-booking` + `settle-run`.

**2026-09-21 03:04 — `c680d5e` migration 0189 LANDED** (correct-forward for Codex's REJECT/2 on 0187; clean merge;
combined tree: harness **1335/0** = 1330 + 5 pins `0189-U1 U2 T1 T2 S1` · deno 359/0 · tsc · checks incl.
babel · **npm 1086/0** = 1068 + 18 drift-gate pins): the three urgent client writers (SOS · 사고 신고 접수 ·
러닝 중단 요청 — the whole set, enumerated past the reviewer's three sites; 응가/간식/km milestones stay
disableable) are always-on by exact title equality, decided above every disableable arm, kind unchanged
for deployed binaries; `notify_push` requires `profiles.deleted_at is null` on the token lookup taken
FIRST; a BEFORE trigger refuses a tombstoned owner's token INSERT/UPDATE by name. Three copies of each
title now exist (api.ts · notification-route.ts · the migration) — an 18-pin cjs drift gate reads all
three, comments stripped, both directions. Battery 13 plants; two false-coverage traps caught by the
builder itself ((v) vs (vb): only the plant that moves the lookup INSIDE the non-safety branch attacks the
behaviour). **0187's deploy block is lifted** — 0187 and 0189 ship together, db push only. **Thirty
pending.** Codex re-review at 06:41 with the others.

**2026-09-21 03:10 — `ba18098` migration 0190 LANDED** (correct-forward for Codex's REJECT/2 on 0186; union-merged
manifest 210–221 in order, 0 markers; combined tree: harness **1342/0** = 1335 + 7 pins `0190-L1 R1…R4 S1`
+ race `RP` · deno 359/0 · tsc · checks incl. babel): the stuck sweep takes
`pg_try_advisory_xact_lock` before reading a candidate (RP is the two-process arm); `delete_my_account_tx`
recreated from 0138 §F's catalog copy (NOT 0115's text — 0138 had rewritten it in place, and a paste would
have silently dropped the billing-key revocation enqueue; plant (ix) reddens 0138's own R4) with the
retention predicate reading `paid_payout_id is null`; a tombstoned runner's retained `bank_accounts` row
is released when the last unpaid row clears, serialised on the `profiles` row lock. Named gaps: the
profile-lock interleaving is source-pinned only; 150 P9 was green through the whole defect because both
its fixtures sat where old and new predicates agree (sentence corrected). **0186's block is lifted —
0186 and 0190 ship together, db push only. Thirty-one pending. Every slice of the night is on trunk.**

## ☀️ MORNING READ — 2026-09-21, everything below measured and read back from origin

**Trunk `ba18098` (start of night: `ed65c3c`). Nothing deployed; production still 0156.** Built and
landed tonight, each on the combined tree with tsc · the checks (incl. the new `check-babel-routes`) ·
npm · deno · the harness:

| slice | what | proof |
|---|---|---|
| `6cf7453` Korean copy (Codex astra) | 12 money/safety failure paths mapped; `invokeTransition` folds English; ④-1 weekly km 「이상」 | deno 336/0 · npm 1023/0 |
| `a5635a9` + `c680d5e` 0187/0189 | notification preferences screen + prefs table + push-trigger enforcement; SOS/accident/stop always-on; tombstoned accounts get no push | harness 1335/0 · npm 1086/0 |
| `a842fe8` + `ba18098` 0186/0190 | ops manual payout journal (`payouts` has a writer), stuck sweep with lock, bank-detail retention ends on final payment | harness 1342/0 |
| `e13c61a` + `e710ef1` + `1474b71` 0188 | the 1:1 run-end RETURN CEREMONY (end_run → both seals → the second seal settles), R6 seal screen, ⑫ on the report, R1c strip; Metro import fix + babel gate; collection parity | harness 1330/0 · deno 359/0 · npm 1068/0 |

Codex verdicts so far: 0176–0185 chain APPROVE/0 (09-18); 0187 REJECT/2 → 0189; 0186 REJECT/2 → 0190;
0188 review died twice (once mid-run, once on the quota wall) — **06:41 one-shot re-runs 0188, 0189, 0190**.
Device-verified on the sim (signed out): safe areas on settings + runner onboarding, the notification
settings screen's failure state, the seal screen's not-found state.

**Your letters (queue):** item 1 the deploy — thirty-one migrations (0157–0163, 0166–0174, 0176–0190) in
ONE sequence: `functions deploy revoke-billing-keys` → `db push` → `functions deploy` the rest
(transition-booking · settle-run · open-drop · confirm-payment · create-booking-hold · …) → the client
build → then set `ops_flags.return_seal_since` and subscribe an ops recipient for `payout_due`;
item 19 the premium labs by number; items 8–18, 20–23 (HIG rulings, board-wrapper-bundle fix, the
idempotency-key date, six gated build items, the one-stamp strand deadline).

## 2026-09-17 02:1x — Xcode 27 is in, the app builds locally again, HIG work is on trunk

> ⚠ Clock correction 04:26: the section labels below were first written as ESTIMATES that drifted up to
> four hours ahead of the wall clock (「08:3x」 was written at 04:25). Rewritten from each commit's
> `git log --date` timestamp; the Codex quota wall (06:44) has NOT lifted yet as of this line.

**Supersedes the 01:2x block below where they conflict.** Sean installed **Xcode 27.0 (27A266a, Swift
6.4)** and it is selected (`xcode-select -p` = `/Applications/Xcode.app/Contents/Developer`). Measured:
- **Local Release simulator build SUCCEEDED** under Xcode 27 (`npx expo prebuild` → `pod install` with
  `LANG=en_US.UTF-8` → `xcodebuild … -sdk iphonesimulator`, ~1 h; artifact
  `/tmp/dd27/Build/Products/Release-iphonesimulator/app.app`). Installed on the iPhone 16 Pro sim
  (iOS 18.3.1, UDID `E5591637-…`) and launched — login screen, screenshot in the session scratchpad.
  The EAS cloud recipe in `docs/setup-new-machine.md` §3 still works and stays the fallback.
- **Native Claude simulator tool still refuses** (「Xcode is installed but not selected」) even though
  the selection is correct — its MCP server cached the check at session start. A fresh Claude Code
  session should clear it; until then `xcrun simctl install/launch/io screenshot` is the door.
- iOS 27 simulator runtime download failed twice (exit 70); not needed — 18.3.1 runs the app.
- **Codex is quota-walled until 06:44 KST** (measured 02:00 via the plugin: 「You've hit your usage
  limit … try again at 6:44 AM」) despite 「credits renewed」 — Sean's four Codex-app sessions share
  the pool. ⚠ The plugin's `task` verb has no `--help`; `task --help` opens a real thread. A one-shot
  cron (06:52) retries ONE astra-medium slice. Until then HIG fixes are Claude agents.

**HIG conformance (Sean 2026-09-17: 「make sure the app ui is streamlined to ios」):**
- `docs/design/hig-conformance-checklist.md` on trunk (`b1b8ba0`) — 99 rows from 61 HIG pages
  (read from Apple's page JSON; the rendered site is empty JS), 8 tensions for Sean, 10 likely
  violations. ⚠ #6 (runners unprimed for location) is refuted — `onboard/runner.tsx` primes inline.
- Landed `9e702c2`: location primer button 「위치 사용 허용」→「계속」 (HIG names 허용 as the forbidden
  word on a pre-alert screen) and `push.ts` reads permission status before asking, never re-asks.
  Gates: tsc · checks · npm test exit 0, 989/0 (= trunk).
- Queue `docs/decisions/awaiting-sean.md` §2026-09-17 items **8–15** (`7eb7506`): Dynamic Type
  ruling, back-swipe, notification-ask placement, action sheets, `pageSheet` modals, `app.json`
  iPad/icon/splash, the primer copy change (reversible in one word), tensions kept as-is.
- In flight at time of writing, two Claude agents in their own worktrees: `hig/autofill` (AutoFill /
  keyboard semantics on all 51 product `TextInput`s) and `hig/safearea` (device insets replace the
  53 literal `paddingTop: 5x` status-bar clearances; `bottomnav` dock pads with `insets.bottom`).
  Each lands only on green gates with the read-back chain; if this section is not followed by a
  landing note, check `git branch -r | grep hig/` — an unlanded branch there is where they stopped.

**02:5x — both HIG slices LANDED, each re-gated on the combined tree (tsc · 4 checks · npm 989/0):**
- `095666d` AutoFill: 18 of 48 product `TextInput`s got `textContentType` / `autoComplete` /
  `autoCorrect` / `returnKeyType` (name ×3, phone ×3, address ×3, labels, search); 26 prose/numeric
  fields correctly untouched; `6f23499` adds the 이름 row on profile edit via a `Field` pass-through.
  Facts, not gaps: zero OTP/email/password fields exist (Kakao-only login), so zero `secureTextEntry`
  is correct. Open: `owner/dog.tsx:324` 생일 needs `numbers-and-punctuation` (hyphens).
- `d3d56ea` safe areas: 49 literal `paddingTop: 54–78` → `insets.top + (literal − 56)` across 49
  route files (relative spacing preserved; content moves out from under the Dynamic Island; correct
  on SE/iPad); `bottomnav` dock and 7 fixed CTA docks pad with `Math.max(insets.bottom, literal)`.
  Left alone on purpose: `owner/fitness.tsx` (DO-NOT-REFACTOR, `RIBBON_H` arithmetic),
  `owner/home.tsx` `PAD_TOP` (written product decision → queue item 16), `owner/request.tsx:1388`
  (modal body), dev labs. Post-edit crude grep = exactly those 4.
- ⚠ **Neither slice has a codex verdict** — the wall (06:44) refused both attempts (0 B stdout,
  `usage limit` on stderr, read from the tail, not re-run). They are on trunk on green gates; the
  06:52 cron's first job is a diff-scoped `review` of `b1b8ba0..d3d56ea` before any new build slice.
- Device-visual: **UNVERIFIED, and blocked.** The incremental rebuild succeeded and installs, but
  `xcrun simctl openurl daengrun:///settings` stops at iOS's own 「Open in 도그스하이?」 dialog, which
  needs a tap — the native Claude sim tool still refuses (`attach`/`tap`: 「Xcode … not selected」) and
  AppleScript UI scripting hung on the accessibility permission (Sean may find a TCC prompt). Two ways
  out, both Sean's: a fresh Claude Code session (the tool re-checks Xcode) or granting Accessibility to
  the Claude app. The login screen is untouched by both slices. Smoke list for Sean on hardware: first text line clear
  of the island on every screen · dock above the home indicator · QuickType offers name/phone/address
  on 온보딩·안전 연락처·주소 추가 · 생일 still accepts hyphens.

**03:1x — audit landed, two more Claude agents in flight (Codex still walled):**
- `571017f` `docs/design/loading-state-audit.md` — all 59 routes read: F1 settled (46 routes name their
  loading state; zero spinners is the house idiom, not a gap), **8 Tier-1 honesty defects** (a failed
  roster read shows 「불러오는 중」 forever; shop/card-link/settings/my swallow failures into the happy
  face; course/shot/cards render nothing while loading), **7 opacity-busy buttons**, 6 silent-catch
  clusters (Tier 3, recorded, not fixed).
- In flight: `hig/a11y` (VoiceOver names + roles on every icon-only control) and `hig/honesty` (Tier 1
  #1–8 and the text-labelled Tier 2 buttons). Both avoid `runner/run.tsx`, `owner/radar.tsx`,
  `owner/live.tsx` (reserved for the 06:52 Codex VoiceOver slice). If this note is not followed by a
  landing line, `git branch -r | grep hig/` shows where they stopped.

**02:46 — `f8ab905` a11y LANDED** (re-gated on the combined tree: tsc · 4 checks · npm 989/0): VoiceOver
names + roles on 32 icon-only controls across 18 files (sheet scrims 「닫기」, camera chips 「사진 보내기」,
bell 「알림」, 112/119 「…에 전화 걸기」, star rating as `radio` with `selected`, photo tiles as
`imagebutton`); 564 controls enumerated, parser diffed against the crude grep both ways (484/484).
Props-only, proven by stripping the a11y attributes from both diff sides (control arm reddened). Not
done on purpose: two image-dominant tiles (a container label would silence their children), selection
chips with a name but no role/state (A2 follow-up). Spoken output UNVERIFIED — VoiceOver smoke list:
owner home bell + moment strip · a club session sheet scrim · safety 112/119 · runner review stars ·
shot photo tile selected state.

**02:59 — `f38d809` honesty slice LANDED** (combined tree: tsc · 4 checks · npm 989/0 — ⚠ that suite
cannot import a route module, so its green means 「nothing regressed」, not 「this slice was checked」):
Tier 1 #1–8 of `loading-state-audit.md` closed — session roster failure now says so + retry (was
「불러오는 중」 forever); shop/card-link/settings/my surface failed reads instead of the happy face
(card-link keeps `locked` null on a failed read — money path, smoke it); course/shot/cards name their
loading state — and 5 opacity-busy buttons became label swaps (`shot` ×3, club 탈퇴, login). Left on
purpose: Tier 2 #13/#14 (icon-only send buttons need a design call), Tier 3, and a NEW note:
`shot/[bid].tsx:1103` uses a **disabled** alpha (DESIGN.md forbids that too) — follow-up. Device
smoke list (9 items, airplane-mode based) is in the agent's report; the money-path one is #3.

**03:11 — `.githooks/pre-commit` (react-doctor) now scans in linked worktrees.** Before: every
commit from a `.claude/worktrees/*` tree printed 「configuration differs between the index and
worktree」 for eight CLEAN config files, then 「found staged regressions」, then landed unchecked.
Measured cause, three parts: git exports `GIT_DIR` to hooks only when `.git` is a gitfile (a plain
clone's hook env has none); react-doctor resolves the project to `app/` and runs `git status` from
there; and `GIT_DIR` without `GIT_WORK_TREE` makes git treat the cwd (`app/`) as the worktree root
(`git-config(1)` core.worktree), so `app/*.json` read as deleted + untracked. Fix, in the commit carrying this note:
`unset GIT_DIR` in the hook (`GIT_INDEX_FILE` kept — it names the temporary index of a
`git commit -- <paths>`), and the failure message now separates 「scan did NOT run」 from 「found
regressions」 (a `Scanned N file` line is the marker; react-doctor exits 1 for both). Verified through
REAL commits in a scratch worktree, then removed: docs-only → silent, exit 0; a staged `.tsx` → genuine
scan (Score 76, 5 pre-existing `my.tsx` warnings), commit still lands. ⚠ The hook was and remains
ADVISORY (no `exit 1` on findings) — making it blocking is Sean's call, queue it if wanted. Also
noted, not changed: the repo root has no `node_modules`, so the hook's local-binary branch is dead and
it runs `pnpm dlx react-doctor@latest` (0.9.14 cached; `app/` pins 0.9.12). No codex verdict (wall).

**03:14 — Sean awake (「keep going… mocks… premium taste / impeccable… backend where necessary」):**
- `26c9bcd` `docs/reviews/2026-09-17-backend-honesty-audit.md` — 11 edge functions, 22 crons, RPC
  surface: **3 HIGH** (open-drop reports rewards it never checked were written; open-drop consumes the
  drop before it can pay it → needs an `open_drop_tx` definer; four money/ops crons have no readback),
  **10 MED**, 6 LOW. `c99babb` closed M4 (openDrop unwrapped the wrong level — the runner was never
  told what they won) and M5 (0083's `not_run_runner`/`run_ended` raises now map to Korean).
- Sean's react-doctor chip landed on trunk as `2fab448` (pre-commit now scans linked worktrees).
- **Five agents in flight**, each in its own worktree, each lands only on green gates with read-back:
  `labs/premium` (PRODUCT.md + premium-taste brief + four impeccable/taste labs: owner home, request
  flow, live run, run report — Sean picks by number) · `hig/tier3` (secondary sections say when a read
  failed) · `hig/a2` (roles + selected state on every chip/segmented control) · `be/edge` (M1 H1 M3 M2
  M8 M9 M6 L2 L1 + an open-drop deno suite) · `be/0175` (cron readback for the four unswept jobs + a
  job lock on `owner_la_sweep_stale`, suite 205, harness-gated). Codex still owes every slice a review
  once the wall lifts (06:44); H2 (`open_drop_tx`) and M7 (revocation refusal token) are Codex-sized
  migrations queued behind it.
- A macOS keychain prompt for 「Supabase CLI」 surfaced on Sean's screen ~03:10 — not from this session
  (no CLI running here); it wants the Mac login password; Deny is safe; alt route is a personal access
  token in his own shell.

**03:22 — `8ab703a` Tier 3 LANDED** (combined tree: tsc · 4 checks · npm 989/0): every secondary
section whose read failed now says so with a retry that re-issues exactly that read — club page
(board / series / stats), owner report (standings, review, slot, earning, gaps — the two celebration
pops stay silent on purpose: a retry would burn the once-per-entity token), owner home (a new
`QuietFail` one-liner on canvas, never a wash; the unread dot stays undrawn on purpose), runner
rewards (miles / status / claims, last-known rows kept under the strip), club receipt (strip outside
the shareable PNG), address pin (retry re-runs the whole resolve chain). Airplane-mode smoke list is
in the agent report (10 items). Loading-state audit Tiers 1–3 are now closed except #13/#14
(queue item 17).

**03:28 — `13d3658` A2 LANDED** (combined tree: tsc · 4 checks · npm 989/0): roles + selected/checked
state on 23 selection sets across 12 files (date strip, slot grid, dog picker, pace, add-ons, weekly
repeat, course carousel, neutered yes/no, schedule filter, weekday availability as `switch`, review
tags, gear checklist, community/leaderboard/club-session tabs, consent checkboxes). Props-only proven
two ways (char stream + AST) with control plants. Two pre-existing wrong roles flagged, not changed:
`runner-profile/[id].tsx:382` segmented tab carries `button` (should be `tab`); `runner/apply.tsx:636`
multi-select carries `selected` (should be `checked`) — small follow-up. VoiceOver output UNVERIFIED;
smoke list in the agent report (8 items).

**03:33 — cold review of A2 (APPROVE-WITH-FIXES/6) applied: `332e21b` two wrong roles, `bf4ff99` spot
chips get radio+state and the booked slot is now DRAWN selected (ink plate, 「선택됨」) so the eye and
VoiceOver agree — a small visible change on the booking sheet, reversible. Queue item 18 asks for one
VoiceOver vocabulary ruling (`checked` vs `selected`, `tab` inert on iOS Fabric — measured in RN 0.86).
Peer session `daengrun-b6` (Sean's react-doctor session) is now on backend-audit **H2**: migration
**0176 + suite 206** `open_drop_tx` definer in its own worktree; told not to touch `open-drop/index.ts`
(be/edge owns it), not to run codex or the Supabase CLI. Numbers 0175/205 (be/0175, unpushed) and
0176/206 (b6, unpushed) are both claimed — the three-sided check cannot see either yet.

**03:35 — `c7f207d` premium labs LANDED** (docs only): `docs/design/PRODUCT.md` (impeccable format, real
facts only), `docs/design/premium-taste-brief.md` (both skills distilled against DESIGN.md — 12
tensions, incl. a 🔴 finding that the GO law's waiting-blue ships as the accent violet), four labs
`docs/labs/premium-{owner-home,request-flow,live-run,run-report}-lab.html` (①② paper, ③ labelled
departure, English prose, Korean only inside the frames, verified complete from origin) and the
README with Q1–Q5 → queue item 19. Files sent to Sean to pick by number.
🔴 **Migration-number collision caught before any push** (b6's per-worktree scan + my re-check): Sean's
uncommitted Codex worktrees hold **0175/206** (`board-rejected-arm`) and **0165/205**
(`membership-three-tier`); the three-sided check cannot see uncommitted files. Reassigned: my cron
slice → **0177 / 208**, b6's open_drop_tx → **0176 / 207**, Sean's stay as they are. New fourth side
of the check: `ls .claude/worktrees/*/supabase/migrations | grep -E '^01'` (and tests) before
claiming.

**03:40 — `f6ed478` edge slice LANDED** (combined tree: deno **312/0** = 292 + exactly the 20 tests
added · tsc · check-rpc): malformed bodies are `400 bad_body` in all six functions (M1); open-drop
validates before the consuming CAS (M3) and reports only rewards it actually wrote — a partial write
returns `{applied, failed, error:<Korean>}` so the existing client shows 「오픈 실패」 instead of a
happy receipt (H1; H2 `open_drop_tx` is b6's 0176); `notify()` logs its error (M2); the three
payments bookkeeping writes and the account-deletion row bind their errors, a lost
`needs_manual_cancel` marker pages ops as a new `payment_marker_lost` class (M8); 10 s ceiling on
`invokeTransition` (M9); revoke-billing-keys `continue`s past a report failure, lease untouched (M6);
paymentKeys logged as last-6 (L2); `internalError(e, code)` at the 14 raw-Postgres sites (L1);
open-drop split into handler+index with its own suite (L5). Four shipped register-billing-key pins
were rewritten to assert `err.code === "billing_key_swap"` instead of raw SQL text — deliberate,
reverting `:472` reddens all four. ⚠ **Edge functions are NOT deployed** — `functions deploy` waits
for the same letter as `db push` (they assume 0157+ semantics). Codex still owes a verdict.

**03:48 — `ca6fbe9` migration 0177 LANDED** (renumbered from 0175 after the collision; combined tree:
harness **1236/0** = 1229 + exactly the 7 pins `0177-S1…S7` · deno 312/0 · tsc · check-rpc ·
check-definer-acl baseline unchanged): the four money/ops cron jobs `club-payout-release`,
`run-end-recovery`, `cancel-money-gaps`, `sweep-club-cancel-fees` are re-registered byte-identically
without the swallowing handler and read back at apply (schedule asserted too — a deliberate divergence
from 0172, reasoned in the file); `owner_la_sweep_stale` takes a job-level advisory lock with the
unlock on every exit path, ACL re-stated explicitly. Battery: A0 proved a single-site plant is a no-op
(0083's swallowed registration still succeeds locally), A1 aborts the apply at VERIFY, A2 reddens
S2+S5 alone, B/B3/C redden S6 alone (comment-strip control and NO-SOURCE arm measured). Named gaps in
the suite header: the harness cannot make `cron.schedule` fail, and a session-scoped lock is
re-entrant so M10's duplicate push is un-pinnable single-connection. ⚠ **Sixteen migrations are now
pending** (0157–0162, 0166–0174, 0177); production `cron.job` was never read — if the production
apply aborts at 0177's VERIFY, that abort is the first evidence either way. Codex owes this slice a
cold read (five named questions in the agent report). ⚠ Harness trap on this Mac: without
`LANG/LC_ALL=en_US.UTF-8` the postmaster dies at start (「became multithreaded」) and the run prints
`SHIM FAILED` — an environment fault wearing a failed control's costume; set the locale first.

**03:58 — `ee8845c` Codex branch `codex/runner-rules-checks` LANDED (0163 + suite 194).** The first
Codex-written slice to reach trunk. Rebased `4dc0608` onto `4f6a8a5`; REGISTRY.md auto-merged (row
0163 sits between 0162 and 0166, every trunk row 0166–0177 preserved), `harness.sh` was the one
conflict and was resolved by UNION with `suite 194_` inserted at its numeric position after
`suite 193_` (208 kept where it was; `uniq -d` on the manifest empty, 0 conflict markers in all three
shapes on all four files, verified again from origin after the push). **Harness 1236 → 1239/0, delta
EXACTLY the 3 pins the suite adds** (`0163-R1/R2/R3` each read back BY LABEL from the log) · deno
**312/0** · tsc · check-rpc · check-route-native · check-definer-acl (baseline 81 unchanged) ·
check-device-clock · npm test exit 0, **989 `^PASS` / 0 `^FAIL`** (+38 ✅). **What it does:** two
`not valid` CHECKs on `runner_booking_rules` bounding the only two columns any server code READS
(`is_slot_available`, 0003:42) to the shipped editor's own ranges — rest 0..120, daily 1..8. ⚠ **The
suite shipped with no mutation battery in its header, so I ran one before landing** (the slice's
central claim was reasoned, not measured): plant M1 removes both constraints, `&&`-chained to the
run with the plant re-read from disk and asserted, ⇒ **1237/2 = `0163-R1` + `0163-R2` alone**, and
the failure detail IS the hole (`accepted rest=-1 accepted rest=121`, `accepted daily=0 accepted
daily=9`) rather than a pin's opinion of it. R3 stays green, which is the control-pair point:
accept-everything reddens R1/R2 only and refuse-everything would redden R3 only, so no single
hard-wired answer satisfies the set. Restored byte-identical against a pristine copy, 0 `PLANT`
occurrences. **Review findings, all LOW, none blocking:** ① no SECURITY DEFINER, no function, no RPC
in the diff — the definer/`search_path`/ACL and party-before-state laws have no surface here; ② both
columns are `int not null` with defaults 30 and 4 (0001:110-112), both inside the new bounds, so
there is no nullable-predicate collapse and no `<>`/bare-`IF` to correct; ③ every writer enumerated
and each is safe — `registerRunner` inserts `runner_id` alone (defaults), `saveMyBookingRules`
upserts values the editor clamps to exactly 0..120 / 1..8 (`availability.tsx:176-177`), and **no
migration and no edge function writes these columns at all**; ④ no harness fixture outside 194
touches the table, so nothing else could break; ⑤ the one real residual — a 23514 from the upsert has
no Korean client mapping, unreachable from the shipped client because the stepper clamps, so it is a
note and not a defect. ⚠ NOT codex-reviewed (this was a cold Claude read), NOT DEPLOYED.

🔴 **04:07 — Codex branch `board-wrapper-bundle` NOT landed: 0164 removes the only route by which a
certified runner commits to a session, and rewrites the pin that exists to prevent exactly that.**
Every gate is GREEN — rebased `bf53c3b` onto `7d4db60` cleanly (harness.sh the one conflict, unioned
with `suite 195_` at its numeric position after 194; REGISTRY auto-merged; 0 markers in three shapes)
and measured: harness **1247/0 = 1239 + exactly the 8 pins suite 195 adds**, all 8 read back by
label · deno **312/0** · tsc · check-rpc · check-route-native · check-definer-acl (baseline 81
unchanged) · check-device-clock · npm test exit 0, **989/0**. **The greens are not the question.**
**The defect, every rung READ at source, none inferred:** ① `club_session_detail` (0052, last def)
returns a full row to a `none` caller by design (「문 앞 정직」), so the session screen **renders** for
a non-member runner · ② `_club_shell_access` (0049) grades a runner with no assignment, no RSVP and
no delegated dog as **`none`** — `'full'` requires `status = 'committed'`, and `session_runner_commit`
is a SELF-commit, so the runner about to commit has no row at all · ③ `_club_delegation_board_impl`
(last def `0168:724`) computes `'runnerCap', coalesce(_club_runner_cap(auth.uid()), 0)` **ungated by
`p_access`**, and `_club_runner_cap` (0037) returns 1–2 for any certified/veteran/master runner
independently of the session — so a `none` certified runner has `runnerCap > 0` today · ④ 0052's
wrapper passed `none` to the impl **on purpose**, its own comment naming this exact use:
「none도 session+me는 받는다 … me.runnerCap은 미확약 러너의 확약 CTA에 필요」 · ⑤ 0164 returns SQL NULL
for `none` → `fetchDelegationBoard` (`api.ts:4312`, `if (!data) return null`) → `board === null` ·
⑥ the CTA guard is `isOpenish && board && … && board.me.runnerCap > 0`
(`club/session/[sid].tsx:1677`) → **never renders** · ⑦ `commitAsHandler` → `session_runner_commit`
has **no other product call site** (only `dev/club-lab.tsx`, itself gated on `board`).
🔴 **The decisive evidence is the repo's own:** `95_audit_gates_suite.sql`'s **`G2b` was written for
precisely this regression the last time it happened** — its comment reads 「이분법 게이트는 미확약
인증 러너까지 not_party로 막아 세션 셸의 러너 확약 CTA(me.runnerCap이 그 사람 위한 필드)를 지웠다」,
a reviewer caught it, rev2 P1 fixed it, and G2b became the standing pin. **0164 reintroduces it and
closes the pin by rewriting it to assert the opposite** — the log now reads
`✅ G2b uncommitted certified runner receives NULL board`. A green pin whose sentence IS the defect,
which is why all four gate suites are green and none of them can see this. Its fixture also proves
rung ③ empirically: `(v_js->'me'->>'runnerCap')::int > 0` was a PASSING assertion for a `none`-graded
certified runner. And suite 195's own stranger is `t_user('bwb_stranger','owner')` — an owner, whose
`_club_runner_cap` is 0 — so B1 sits exactly in the zone where the old and new rules agree on
anything that matters (the fixture-cannot-distinguish-two-rules law).
**Why this is not what Sean ruled.** Ruling 5 (`docs/decisions/2026-08-31-sean-rulings.md:79`, read
verbatim) narrows 「incident counts, paid-dog counts, and staffing state」 for 「strangers」. The `me`
block is the caller's **own state about themselves**, not club operational data; 0164's suite header
extends the ruling by inference (「Ruling 5 also applies to a certified runner who has not
committed」) and that inference costs a shipped, reachable feature. **Whether an invited/uncommitted
runner is a 「stranger」 is Sean's product call, not mine** — hence not landed rather than edited.
**Fix shape, small either way:** return the `session`+`me` envelope for `none` (dogs/runners/incidents
still `[]`, which is the whole ruling) instead of SQL NULL, and restore G2b; **or** grade an
uncommitted certified runner above `none`. Either one keeps the rest of the slice, which is worth
keeping.
**What 0164 gets RIGHT and must survive the fix** — ⓐ a real defect closed: `session_set_backup`'s
party gate was `s.host_profile_id <> auth.uid()` on a **bare `IF`**, so a NULL-uid caller made the
predicate NULL, the gate stayed **silent**, and execution fell through to the write; `is distinct
from` closes it and 195's N1/N2 pin both halves (N2 has to `drop not null` to reach the host-NULL
arm, and restores it inside the same atomic DO) · ⓑ `set search_path = public` → `public, pg_temp`
in-body on both functions — a genuine repair, since 0055 §2's ALTER-applied config is discarded by
`create or replace` · ⓒ same-file explicit revoke+grant on both, which is the `check-definer-acl`
「never rely on grant preservation」 law. ⚠ **Corrected before it reached this file:** I first wrote
that ⓒ fixed a live PUBLIC-executable definer. **False, and the check is one line** — 98 **H9**
(schema-wide, PUBLIC and anon arms stated separately) is green on the slice-1 run that does **not**
contain 0164, so the built schema already had it revoked. ⓒ is same-file explicitness against the
absent-function apply path, not a breach fix. A grant is not a door.
**Suite 195 is otherwise good work** and should not be re-litigated when this is fixed: 8 pins, a
7-plant mutation battery in its header each naming which pins redden, comment-stripped `prosrc`
matching, `set local role authenticated` so the ACLs are actually exercised, and real control arms
(B3 host, N3 authorized). **Branch left intact at `origin/codex/board-wrapper-bundle` `bf53c3b`;** my
landing worktree and `land/board-wrapper-bundle` are removed. To redo the rebase: the only conflict
is `harness.sh`, resolved by keeping trunk's `suite 208_` line where it is and inserting
`suite 195_…` immediately after `suite 194_`.

**04:25 — `04d73a9` migration 0176 LANDED** (b6's slice, backend-audit H2; combined tree: harness
**1246/0** = 1239 + exactly the 7 pins `O1…O7` · deno 312/0 · tsc · check-rpc · check-definer-acl
baseline unchanged): `open_drop_tx(uuid, text)` SECURITY DEFINER, authenticated only (service_role
revoked in-file), gate order not_signed_in → drop_not_found → not_drop_owner (under `for update`) →
bad_pick_choice → already_opened → one CAS → reward arms → `drop_pays_nothing` when a mini paid
nothing; VERIFY asserts ACL by value and comment-stripped source order. Cold-reader review
APPROVE-WITH-FIXES/9, fixes applied before push; named gaps: the two-connection race is belt not pin,
`not_drop_owner`/`drop_not_found` is a uuid-existence oracle. Suite-update law honoured: `141 D19`'s
sweep now excludes exactly `open_drop_tx(uuid,text)` with a liveness arm. ⚠ **Not wired yet** —
`open-drop/handler.ts` still does the writes itself; the follow-up must call the RPC with the runner's
JWT and RE-WRAP `{applied}` (the RPC returns the bare object; `api.ts` unwraps one level — wiring it
bare silently reverts every alert to the M4 shape). **Eighteen pending** (0157–0163, 0166–0174,
0176, 0177) + edge functions; codex owes 0176 and 0177 a verdict.

**04:33 — `47b4113` open-drop WIRED to `open_drop_tx`** (b6's slice; combined tree: deno **311/0** = 312 − 10
old arm tests + 9 new, explained · tsc · check-rpc now 133 calls / 214 signatures): the handler is one
RPC through a caller-bound client (`_shared/ctx.ts` gains `callerBoundClient`; confirm-payment keeps
its own copy for now), a token map (`not_drop_owner` 403 · `already_opened` 409 · `bad_pick_choice`
400 · `drop_not_found` 404 · `drop_pays_nothing` 409 with a new Korean sentence), `internalError` for
the rest, and the response re-wrapped as `{ applied }` with a pin that fails if it is ever wired
bare. H1/H2/M3 are now closed end to end. ⚠ **Deploy ORDER matters and is in the queue:** `db push`
(0176 in production) BEFORE `functions deploy`, or every open fails 500; `SUPABASE_ANON_KEY` must be
in the function env (confirm-payment already depends on it).

**05:42 — `f67babf` migration 0178 LANDED** (b6's slice, backend-audit M7 — the server-side ④ instance;
combined tree: harness **1252/0** = 1246 + exactly the 6 pins `0178-R1…R6` · deno **314/0** = 311 + 3
· tsc · check-rpc · check-definer-acl baseline unchanged): `report_billing_key_revocation` returns
`(applied, refusal)` with the row locked FIRST and diagnosed from its pre-image (`absent` ·
`not_processing` outranks `lease_lost`); the revoke-billing-keys worker maps each token, fails CLOSED
on any other shape (incl. the old boolean), and the tick row carries seven counters. Race measured by
hand: draft 52–243/2000 false `lease_lost`, shipped body 0/2000, lock deleted 453/2000 (named gap, two
connections). Cold review APPROVE-WITH-FIXES/8, fixes applied. Suite-update law: 174 L3, 186 A1–A3,
196 F2/F3 rewritten to the tuple. 🔴 **DEPLOY ORDER FOR 0178 IS THE REVERSE OF 0176's**: `functions
deploy` FIRST, then `db push` — new handler + old function fails closed and loud; old handler + new
function silently counts a REFUSED report as revoked (an array is never `=== false`). Both orders
are in the queue's deploy item. **Nineteen pending** (0157–0163, 0166–0174, 0176–0178) + edge.
⚠ b6's first push put an EMPTY `be/0178` on origin (a zsh pathspec made the commit fail while the push
went out) — caught by its own read-back; the CLAUDE.md push law working as written.

**2026-09-18 02:53 — session resumed after a ~20 h gap** (last heartbeat 09-17 06:25; the machine or the session
slept). Trunk untouched since `0a090b4` (09-17 05:42); no Codex-session branch moved; b6's `be/0179`
(booking-hold idempotency) was never pushed — its worktree `.claude/worktrees/be-0179` and a postmaster
are still there, so that session may have died mid-slice: check `git -C .claude/worktrees/be-0179 status`
before assuming anything landed. The 06:52 Codex one-shot fired only now; `status` shows no current wall,
so a diff-scoped plugin REVIEW of the two HIG slices (AutoFill + safe-area, `b1b8ba0..d3d56ea`, run
from a detached worktree so the diff is exactly those two) is in progress — verdict lands in
`docs/reviews/2026-09-17-hig-slices-verdict.md` only if a `FINDINGS: <digit>` line exists.

**2026-09-18 02:59 — `3681e73` migration 0179 LANDED** (b6's slice, backend-audit §(a)#3 booking-hold idempotency;
combined tree: harness **1260/0** = 1252 + exactly the 8 pins `0179-K1…K8` · deno **320/0** = 314 + 6
· tsc · check-rpc 134/215 · check-definer-acl baseline unchanged · npm 989/0): `bookings.client_request_id`
+ partial unique index (owner, key); `create_booking_hold_tx(...)` SECURITY DEFINER service_role-only,
one transaction — party gate before any state read, advisory locks key→dog in fixed order, replay ⇒ the
same row with `unchanged:true` and its CURRENT status, reused key with a different payload ⇒
`request_mismatch`, clash guard atomic under the dog lock, any raise rolls everything back
(`compensate()` deleted). Edge: one `db.rpc`, token map (403 / `dog_slot_clash` 409 / `request_mismatch`
409 / `hold_close_failed` 500). App: `api.ts createHoldRequestKey()`; `request.tsx` mints one key per
submit attempt, keeps it across a retry of the same payload, replaces it when the payload changes. Races
measured by hand (two connections): both locks load-bearing; the unique index alone still prevents the
double booking when the key lock is deleted. Cold review APPROVE-WITH-FIXES/15, two recorded:
`generate_recurring_bookings` (0111) takes no dog lock (its own slice); suite 210 aborts namelessly if
an expected-success call raises. 🔴 Key is OPTIONAL server-side (NULL = pre-slice behaviour, K3 pins
it) so installed builds keep working — queue item 21 dates the 400. Deploy order for 0179 is the 0176
order (db push, then functions). **Twenty pending** (0157–0163, 0166–0174, 0176–0179) + edge.

**2026-09-18 03:02 — VoiceOver live-region slice LANDED — the first Codex-plugin BUILD of the night** (gpt-6-astra
medium, one task, `CHANGED: 3` digit detector hit, 0 usage-limit lines): `runner/run.tsx`,
`owner/radar.tsx`, `owner/live.tsx` get `accessibilityLiveRegion="polite"` on the status sentence and
one effect each that announces a state transition (never on hydration, never the same sentence twice),
every sentence pre-existing copy. Reviewed by hand: rules-of-hooks 0 errors on all three, declaration
order checked, no visual change. Gates: tsc · route-native-imports · npm 989/0 · combined tsc. Codex
also answered the HIG review (`docs/reviews/2026-09-17-hig-slices-verdict.md`, 0 actionable). The
`review` and `task` verbs both answer in prose — detect on their own completion lines / the `CHANGED`
digit, never on the prompt.

**2026-09-18 03:13 — Codex adversarial review of 0176 / 0178 / 0179 (+ wiring): APPROVE-WITH-FIXES / 1**
(`docs/reviews/2026-09-18-migrations-0176-0178-0179-codex-verdict.md`, `8ccd4d2`). The one finding is
real and EXECUTED (FakeDb): 0179's edge reaches the idempotent replay only AFTER the route / debt / card
gates, so a lost response followed by a gate change turns the retry into a 409 while the live booking
stays acceptable — the key protects the write, not the person. Routed to b6 (slice author) ahead of
0180: resolve the owner-scoped key right after the party check and return the existing booking before
any creation-only gate, plus the three lost-response tests. 🔴 **Say the deploy letter only after that
fix lands.** 0176 and 0178 drew no finding. Detector note in the verdict doc: the reviewer bulleted its
closing lines, so anchor the digit detector on the word, not on the line start.

**2026-09-18 03:35 — Codex's 0179 finding FIXED and LANDED** (b6, `d4f5560` fast-forwarded; edge-only, no SQL, no
number; combined tree: deno **326/0** = 320 + 6 · tsc · check-rpc): the edge resolves the owner-scoped
`client_request_id` right after the party checks and BEFORE every creation-only gate, compares the
nine slot/money fields exactly as the transaction does, and answers the existing booking with
`unchanged:true` without a write — reproduced first (the three gate sentences on a retry), then the
three lost-response tests + mismatch-before-gates + `payment_hold` prior falls through (the transaction
alone may close it, K7) + a stranger's dog with my key still 403. Gate order kept: ownership → replay →
route → debt → card → flag → transaction. **The deploy-wait is lifted** — the letter (queue item 1) can
be said on this trunk. 0180 (b6, in progress) will carry a `pg_advisory_xact_lock` held to commit (not a
session lock released early — that would reopen the race) and updates suite 161 P4's md5 pins under the
suite-update law.

**2026-09-18 04:30 — `a89b8ba` migration 0180 LANDED** (b6; fast-forward; combined tree: harness **1269/0** = 1260 +
exactly the 9 pins `0180-A1…B6` + race `RG` · deno 326/0 · tsc · check-rpc · check-definer-acl baseline
unchanged): `generate_recurring_bookings` takes 0179's dog lock as `pg_advisory_xact_lock` held to
commit (a session lock released early lands a second booking beside the sweep's — measured 2 rows vs
1; `90_race_check.sh RG` is the two-process pin, 211 A1 pins the absence of a session unlock),
`lock_timeout` 2 s on the sweep (measured: holder at 8 s ⇒ raise at 2 s); `billing_key_dispatch_ticks`
carries the 0178 three-way split durably and the reconciler reads all seven counters through one
guarded cast (a JSON `1.5` used to abort the whole call and leave every later tick `sent` for 6 h —
measured, fixed, pinned). Suite 161 P4's digests moved under the suite-update law. Cold review
APPROVE-WITH-FIXES/14, all fixed. **Twenty-one pending** (0157–0163, 0166–0174, 0176–0180) + edge;
0180 is db-push-only (the worker already writes the seven counters since 0178).

**2026-09-18 05:22 — `a3ecfb4` migration 0181 LANDED** (b6; fast-forward; combined tree: harness **1279/0** = 1269 +
exactly the 10 pins `0181-C1…C9` + race `RL` · deno 327/0 · tsc · check-rpc · check-definer-acl baseline
unchanged): `sweep_run_end_recovery` gains a try-xact job lock and arm ⓒ — a booking with exactly one
handoff stamp, a runner, a handoff-underway status (deny-list of the other fourteen; C6 walks the enum so
a new status reddens until placed), the stamp older than 5 min and NO 「인계 확인 요청」 row for the
counterparty since the stamp (10-min skew allowance) ⇒ the ask is inserted once, counted, named in a
notice; per-row exception arm; a deno drift pin ties the sweep's match text to the edge's. Cold review
APPROVE-WITH-FIXES/9 — the HIGH (the counterparty conjunct was load-bearing and unpinned) fixed and
pinned both ways (C9). Named gaps: a solo-test booking asks itself (as the edge does); no escalation
after the one re-send; club parties' push lands on the 1:1 meetup screens (client slice). **Twenty-two
pending** (0157–0163, 0166–0174, 0176–0181) + edge; 0181 is db-push-only. **Every backend-audit item
with a code fix is now closed** (H1 H2 H3 · M1–M10 · L1 L2 L5); L3/L4/L6 are recorded hygiene.

**2026-09-18 05:26 — Codex adversarial review of 0180 / 0181: REJECT / 5** (static; suites not executed by the
reviewer; `docs/reviews/2026-09-18-migrations-0180-0181-codex-verdict.md`). HIGH: a re-matched booking's
OLD ask (same owner recipient, inside the 10-min skew) suppresses the new runner's re-send forever; HIGH:
after the one re-send there is no recovery deadline (attack-INACTION; clubs are outside
`late_booking_sweep`); MED: arm ⓒ inserts without locking/re-checking the booking, so it can send after
the counterparty acted (RL cannot see this); MED: 0180's balance check can overflow int4 on individually
valid counters and roll back the whole reconciliation; MED: club recipients are routed to the 1:1
meetup screens (client half = b6's in-flight slice; sweep half = resolve `club_session_id`). Fix shape:
**correct-forward 0182 + suite 213** (never edit 0180/0181), routed to b6. 🔴 **Deploy letter WAITS
again** until 0182 lands and is re-reviewed.

**2026-09-18 05:34 — `1081a33` club handoff push ROUTE LANDED** (b6, client-only; fast-forward; combined tree: tsc ·
checks · **npm 1016/0** — new baseline: 989 + 27 pins in `app/test/notification-route.test.cjs`, registered
in the chain): the destination decision moved into a pure module `src/lib/notification-route.ts`; a
club booking's handoff-family push (인계 확인 요청 · 인계 완료) now lands on `/club/session/{sid}` for
both roles (the screen that owns both club confirmations), 1:1 bookings keep the meetup screens, unknown
club membership folds to the pre-slice route (loud, not a stall); `alerts.tsx`'s inbox shares the entry.
No arrival stage invented; the DO-NOT-REFACTOR meetup machines untouched. A drift pin reads
transition-booking's confirm_handoff arm (comments stripped) so a new edge title cannot part from the
family silently. Device-visual UNVERIFIED; smoke list in the commit message. Codex #5's sweep half:
b6 will PIN that 0181's re-send carries the edge's exact shape (booking ref + family title), which is
what the new resolver routes — a session-ref'd row would break it; accepted.

**2026-09-18 05:54 — 🔴 TRUNK DENO RED since `1081a33`: 326/1**, `chat_notify_contract_test.ts` (measured on trunk by
me after b6's heads-up): the contract test reads `app/src/lib/push.ts` for `const CHAT_TITLE`, and the
club-route slice moved the title tables into `src/lib/notification-route.ts` (push.ts imports it — nothing
functional is wrong). My landing chain ran tsc · checks · npm and NOT deno because the slice was
client-only — wrong: the deno drift pins READ app files, so **deno is a landing gate for any slice
touching `push.ts` / `notification-route.ts` / transition titles, not only for migrations** (the 0169 law,
one file wider). **Fixed `69cf477` at 2026-09-18 05:56 — trunk deno 327/0 again** (the contract test now reads the declaration
from `notification-route.ts` and requires the comparison in both the resolver and push.ts's fast path,
mutation-checked). 0182 follows on the green trunk.

**2026-09-18 06:47 — `8e7c392` migration 0182 LANDED** (b6; correct-forward for Codex's REJECT/5 on 0180/0181;
fast-forward; combined tree: harness **1288/0** = 1279 + exactly the 9 pins `0182-D1…D8` + race `RL2` ·
deno 327/0 · tsc · checks · **npm 1023/0** = 1016 + 7 client pins): #1 `bookings.handoff_cycle_at`
stamped by trigger on a runner change or stamp reset, the ask match keyed to the cycle; #3 arm ⓒ locks
each candidate (`for update skip locked`, batch 50, `lock_timeout` 2 s) and re-evaluates on the locked
row (RL2 + an EvalPlanQual measurement); #2 arm ⓓ: 30 min one-sided ⇒ both parties told (「인계 확인이
멈춰 있어요」), ops roster told (`handoff_unanswered`, redacted — a no-op until someone subscribes a
recipient: ops-roster owner's item), `handoff_escalated_at` once per cycle, club + marketplace, no flag,
no status move; #4 bigint balance sum + a per-tick boundary that marks an unreadable answer failed while
transient SQLSTATE classes stay `sent`; #5 pinned: the club re-send keeps the edge's shape, and the
escalation title is routed by the client resolver (cjs drift pin reads 0182). Cold review
APPROVE-WITH-FIXES/13, fixed or recorded. ⚠ **This slice touches the CLIENT** (`notification-route.ts`)
— it needs the app build alongside `db push`; no functions deploy. **Twenty-three pending**
(0157–0163, 0166–0174, 0176–0182). Codex re-review of 0182 running now; the letter waits for it.

**2026-09-18 06:51 — Codex re-review of 0182: REJECT / 3** (`docs/reviews/2026-09-18-migration-0182-codex-verdict.md`;
static for SQL, client tests executed). Closed: lock-then-look (#3) and club routing (#5). Open: HIGH —
a delayed old-cycle ask inserted after reassignment (the edge stamps and notifies in separate calls) and
pre-0182 NULL-cycle rows still suppress the current cycle's re-send; HIGH — arm ⓓ consumes the
escalation even when the ops roster is EMPTY (213 pins it as intended), so a later-subscribed operator
never hears of it; MED — the transient SQLSTATE list omits classes 53/58, so an out-of-memory in a tick
becomes a permanent `failed`. Fix shape: **correct-forward 0183 + suite 214** (explicit cycle id on
booking AND notification validated transactionally at ask creation, edge + sweep; legacy-NULL rule; ops
delivery tracked apart from party delivery with a durable pending state; deterministic-only failure
conversion). Routed to b6. 🔴 **Deploy letter stays parked** until 0183 lands and clears.

**2026-09-18 07:59 — `b615af4` migration 0183 LANDED** (b6; correct-forward for Codex's REJECT/3 on 0182; fast-forward;
combined tree: harness **1294/0** = 1288 + exactly the 6 pins `0183-E1…E6` · deno **330/0** = 327 + 3 ·
tsc · checks · npm 1023/0): `bookings.handoff_cycle_id` minted by the database on birth-with-stamp /
first stamp / runner change / stamp reset, carried on `notifications.handoff_cycle_id` by the edge
(read in the same request that stamped) and by the sweep, validated at insert by
`_notification_cycle_guard` (`stale_handoff_cycle`), matched by id alone in arm ⓒ; legacy rule: an id-less
ask never proves the current cycle (asked once more, a duplicate over a stall), a missed row gets an id
on first contact. Party delivery and ops delivery are two records; an empty roster leaves the ops
escalation PENDING and arm ⓔ delivers it once after provisioning. Reconciler marks `failed` only for
classes 22/23/P0, no longer aborts on an unnamed class. Cold review REJECT/13 → all fixed before push;
the one that mattered: the apply-time backfill had no status filter and the `updated_at` bump re-armed
`sweep_cancel_money_gaps` on old cancelled rows (measured: a 90-day-old cancelled row grew a ₩1,245
ledger row) — now scoped to `confirmed`/`runner_enroute`. **Twenty-four pending** (0157–0163,
0166–0174, 0176–0183). ⚠ Deploy order for 0183: `db push` FIRST, then `functions deploy
transition-booking` promptly (inverted, the new edge's ask insert dies on `undefined_column`, logged
non-fatally, and arm ⓒ catches up after). The ops half still needs a `handoff_unanswered` subscriber.
Codex re-review running; the letter waits for it.

**2026-09-18 08:03 — Codex re-review of 0183: REJECT / 2** (`docs/reviews/2026-09-18-migration-0183-codex-verdict.md`).
HIGH, **executed** through the real handler with mocked HTTP: the edge stamps in one transaction and
reads `handoff_cycle_id` in a second, so a reassignment between them makes the old runner's ask carry the
NEW cycle's id — the guard accepts it and the sweep's id match is then suppressed by that premature ask.
MED, static: an unnamed reconciliation error leaves the tick `sent` with only a NOTICE; once pg_net's
six-hour retention deletes the response, the `no_response` predicate turns true and an answered tick is
blamed on transport. Fix shape: **correct-forward 0184 + suite 215** — the stamping UPDATE (or one atomic
RPC) returns the cycle id and the edge carries exactly that id; the reconciler persists that a response
was observed and excludes observed ticks from `no_response` regardless of retention. Routed to b6.
🔴 **Deploy letter stays parked.**

**2026-09-18 08:52 — `ea7df14` migration 0184 LANDED** (b6; correct-forward for Codex's REJECT/2 on 0183; fast-forward;
combined tree: harness **1297/0** = 1294 + exactly the 3 pins `0184-F1…F3` · deno **333/0** = 330 − 1 + 4 ·
tsc · checks · npm 1023/0): confirm_handoff is ONE party-scoped PostgREST UPDATE that RETURNS the stamps,
parties and `handoff_cycle_id`, and the ask carries exactly that id (the post-stamp GET is gone; a zero-row
update ⇒ 409 in Korean, no ask — the mirror order where a re-match commits before the stamp used to land
the old runner's confirmation on the new pairing); the reconciler stamps `response_observed_at` +
`reconcile_error` and the `no_response` arm excludes observed ticks independently of pg_net retention,
with a `stuck_unreadable` health column. Both findings measured real; deno pins own the SQL-invisible
interleaving. **Twenty-five pending** (0157–0163, 0166–0174, 0176–0184); order for 0184: `db push`, then
`functions deploy transition-booking`; no client build. Codex re-review running; the letter waits for it.

**2026-09-18 08:57 — Codex re-review of 0184: REJECT / 2** (`docs/reviews/2026-09-18-migration-0184-codex-verdict.md`).
HIGH, **executed**: the stamp is atomic now, but the `picked_up` promotion is a SEPARATE id-only UPDATE
authorized by the stamp's returned confirmations — a reassignment committed in between promotes the NEW
pairing, notifies the OLD runner, and the custody trigger records the new runner as custodian with
neither confirmation. MED: a delayed answer on a row already `no_response` plus an unnamed fault keeps it
`no_response`, outside every health count after 24 h. Fix shape: **correct-forward 0185 + suite 216** —
stamp and promote inside ONE locked definer RPC, edge calls it and notifies only from a returned row;
the unreadable-answer arm conditionally moves `no_response` back to `sent`. Routed to b6. Convergence:
5 → 3 → 2 → 2 findings over four rounds, each round adjacent to the last; the remaining HIGH is
custody-without-confirmation, so the loop continues. 🔴 **Deploy letter stays parked.**

**2026-09-18 10:15 — `e0b3414` migration 0185 LANDED** (b6; correct-forward for Codex's REJECT/2 on 0184; fast-forward;
combined tree: harness **1307/0** = 1297 + 7 pins `0185-…` + race arms RV×2/RW · deno **336/0** = 333 + 3 ·
tsc · checks · npm 1023/0): `confirm_handoff_tx(p_booking, p_uid, p_side)` SECURITY DEFINER,
service_role only, `auth.uid()` overrides a spoofed argument — `for update` → party gate on the LOCKED
row (a re-match that committed first ⇒ `not_party`, nothing written) → status gate → stamp AND
promotion in ONE UPDATE decided on the locked row (both stamps, both this cycle's, a runner); a
counterparty stamp older than the cycle boundary never promotes and is re-asked; a re-tap keeps the
first stamp. The edge calls it once, writes nothing to bookings, notifies only from the returned row.
Two-connection RW arm measures the finding itself (lock deleted ⇒ the old runner's stamp AND
`picked_up` land on the re-matched pairing). The unreadable-answer arm moves an unresolved `no_response`
back to `sent` under a CAS; RV arms measure the concurrent-verdict guard. Suite-update law: 125 F5 ⓒ
exempts the new routine by name. Cold review APPROVE-WITH-FIXES/8, no code defect. Structural note
(measured): the property is carried by the LOCK, not the one-statement form — the shape pin is text-only
and says so. **Twenty-six pending** (0157–0163, 0166–0174, 0176–0185); order for 0185: `db push`, then
`functions deploy transition-booking`; no client build. Codex re-review running; the letter waits for it.

**2026-09-18 10:20 — Codex re-review of 0185: APPROVE / 0** (`docs/reviews/2026-09-18-migration-0185-codex-verdict.md`).
The handoff-recovery chain is CLOSED: 0181 → REJECT/5 → 0182 → REJECT/3 → 0183 → REJECT/2 → 0184 →
REJECT/2 → 0185 → APPROVE/0, every round adjacent to the last, the final HIGH (custody without
confirmation under a reassignment race) closed by one locked RPC and measured by the RW race arm.
**The deploy letter is UNPARKED.** Twenty-six migrations (0157–0163, 0166–0174, 0176–0185) + edge
functions + the client build, in the sequence in queue item 1. Nothing deployed. Every gate on trunk
is green at this line: harness 1307/0 · deno 336/0 · npm 1023/0 · tsc · the checks.

**Unchanged:** production tip 0156; TWENTY-SIX pending = trunk (was fifteen when this line was first written); deploy is Sean's letter (queue item 1).
Sean's four Codex worktrees: nothing pushed.

## 2026-09-17 01:2x — environment changed, trunk did not

**macOS is now 27.0** (Sean upgraded) but **Xcode is still 16.2** — the iOS 18.3.1 simulator no longer
finishes booting (stuck on the Apple logo across two attempts) and the native Claude simulator tool
refuses with 「Xcode is installed but not selected」. Both resolve with **Xcode 26 from the App Store,
then `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`** (sudo = Sean). That also
unlocks the LOCAL simulator build (Expo 57 / Swift 6.2) and sim tapping — item 3 in the queue is now
「install Xcode 26」, not 「upgrade macOS」.
**Supabase login is present** (`supabase migration list --linked` answers): **production tip 0156;
PENDING = exactly the fifteen on trunk (0157–0162, 0166–0174)** — measured 01:20, matches the record.
Production table reads (`db query`) are blocked for Claude by the harness classifier; migration listing
is not. Trunk `fd0f7d8`, unchanged since 09-15 13:02; Sean's four Codex worktrees unchanged, nothing
pushed; the deploy is still his letter (queue item 1, recommendation ⓐ).

## ☀️ MORNING READ — 2026-09-15 overnight, everything below measured and read back from origin

**Trunk `83ad0dc` (start of night: `1b9a41f`).** Landed while you slept, each re-gated on the
combined tree before push (harness delta = pins added every time; deno + tsc + checks + npm):

| slice | what | proof |
|---|---|---|
| B1 · 0157 · 0158 | the stranded rescue-branch migrations | 1135 → 1177/0 |
| P7 inline-script · 0162 chat idempotency (both halves) | codex astra wrote them | 983/0 · 1180/0 |
| 185 repairs (0154 #5/#6/#7) · **0166** (0155 REJECT/6, all six) · **0167** (0154 #3 CRITICAL, phone visibility gated on the flag) | codex findings closed | 1183 · 1188 · 1193/0 |
| **0168 two-phase stop** (from its contract) · **0169** settle belt · settle-run `run_stopping` arm | GPS finding 4 — the live money defect — closed, plus the SQL belt | 1201 · 1205/0 · deno 281 |
| **0170 billing intent row** | Toss memo §4 core (billing findings 3/4/6 local halves) | 1213/0 · deno 287/0 |
| client honesty wave 4 · `store.ts` −162 lines | 15 fixes, 12 non-club files | 983/0 |
| club-v2 labs ×4 (3 variants each) · GPS-4 contract · slim CLAUDE.md draft + incident ledger · suite audit · harness-diet proposal | your decision artifacts | — |

**The simulator runs.** EAS cloud build (`runtimeVersion` policy `fingerprint` was the cause of all
four prior failures — now `appVersion` on trunk; local Xcode is dead on macOS 14.6). iPhone 16 Pro
sim, iOS 18.3.1, `com.seankookim.dogshigh`, login screen up, Supabase host in the bundle. **It is
signed out — Kakao login is yours.** Recipe in `docs/setup-new-machine.md` §3.

**06:55 — CODEX VERDICT ON THE ELEVEN: REJECT, 10 findings** (`docs/reviews/2026-09-15-deploy-gate-verdict.md`,
genuine: ANSWERED, digit detector 1). Disposition: **HIGH #1** (collection lost after settlement if the
re-mint fails — `settle-run` `CHARGE LOST` path) and **HIGH #2** (register-billing-key's compensation can
DELETE a key the swap stored; 0170's `unresolved` sweep deliberately unbuilt pending Toss U1/U2) are
STANDING defects behind `payments`/`card_registration` flags Sean holds — not introduced by this set,
but they must be closed before either flag flips (queue). **HIGH #3** (a runner can push fabricated
trace inside the 90 s drain) is the pre-existing provenance class — ingest never checked provenance;
0168 widens the post-tap window by ≤480 m; the real fix is a provenance slice (options in queue).
**HIGH #4** (frozen run unsettleable when `trackMode` is `unavailable`/null — a build without the
location module strands a payout) — client bug, FIX WAVE. **MEDIUM #5** register handler reads the
flag before the profile/tombstone check (party-before-state) — FIX WAVE (edge). **MEDIUM #6**
`_club_phone_visible` carries 0049's bare `custody_phase <> 'resolved'` on a nullable column — FIX
WAVE as 0171 (correct-forward). **MEDIUM #7** `trace_future_fix` has no client copy — FIX WAVE.
**MEDIUM #8** photo retries orphan storage objects (new `Date.now()` path per retry) — FIX WAVE (path
keyed on the client key). **LOW #9** closed-window roster replaces instead of retaining — FIX WAVE.
**LOW #10** `run_stopping` vs contract's `run_stop_pending` — recorded in 0169's header, handler maps
it safely; left. All 0159's 11 findings: 7 measured closed, 4 in excluded `geo.ts` (unverified by this
run, verified by the 08-31 UI rounds).

**07:2x — FIX WAVE LANDED, RE-ATTACK WALLED.** Client wave `6a03ab6` (findings 4 · 7 · 8 · 9: frozen
run settles without local GPS state; `trace_future_fix` gets the contract's clock copy; photo retry
re-uploads the SAME object keyed on the client key with upsert — 0064's policies admit it; closed-window
roster retained, one pin ×3 zones, npm 986/0) · server wave `44e2e9c` (0171 `is distinct from` in
`_club_phone_visible` — ⚠ the finding's premise measured FALSE: `custody_phase` is NOT NULL since 0040:47
under an always-writing trigger, so 0171 is hardening and its P1 manufactures an unreachable state, said
in both headers; register-billing-key reordered auth → tombstone → flag with the divergence-zone deno
test, 288/0; harness 1217/0). **The re-attack review hit the quota wall (try again at 11:41 AM) after 1.3 MB of
reading — the fix wave is UNREVIEWED; REJECT/10 stays the verdict of record with 6 fixed (unreviewed)
+ 4 dispositioned.** Pending on production is now TWELVE (0171 joins).

**08:3x — HIGH #2 half closed (`bf47df7`):** register-billing-key never calls Toss DELETE on a failed or
unknown swap any more — definite SQL refusal → ORDER the revocation through the 0138/0157 outbox;
unknown outcome → nothing but the named intent row; thrown RPC → intent closed then the error
re-thrown unchanged. deno **291/0** (+3), M1/M2/M3 plants reddening the right pins. Still open on #2:
the production ops roster being empty (recheck before the flag), and the `unresolved` sweep (Toss
U1/U2). HIGH #1 (0172 reconciliation sweep) in flight. Sim tapping: `idb-companion` needs Xcode 26 →
macOS upgrade, or Accessibility permission for AppleScript (queue item 3).

**09:0x — HIGH #1 REFUTED, measured on the real settle path:** `sweep_settled_without_payments()`
(0080:569, extended 0116:60; cron `sweep-settled-charges` every 5 min) already re-mints for a settled
booking with no payments row — after `end_run_tx → confirm_return_tx ×2` with 0 payments rows, one
sweep minted `pending | 18900 | settle_charge` equal to `compute_owner_charge()`, and a second added
nothing. The verdict's 「no sweep or owner retry can find it」 was true of the HANDLER (it returns
`lost`) and false of the SYSTEM. ⚠ The briefed predicate (`status='completed'` + ledger row) was the
WRONG anchor per 0116:47-52 (settled bookings move to incident_review/refund_pending; 0080 §K writes
ledger rows for CANCELLED bookings) — the agent stopped on the STOP condition instead of building a
mis-anchored sweep. What 0172 IS: both recovery cron jobs (`sweep-settled-charges`,
`dispatch-due-charges`) were installed under the swallowing `exception when others` form and NOTHING
pinned their registration — 0172 re-registers byte-identically + reads both back in VERIFY; suite 202,
3 pins incl. a control that reports absent. No new constant. Residual, out of scope and named: a settled
booking the sweep can never price (NULL end_reason/actual_km or a raising mint) is skipped with a
`raise notice` and invisible to ops — `payments_reconciliation()` has no `settled_without_payment`
arm (`_shared/ops.ts:95`); latent today. 0172 joins pending → THIRTEEN.

**12:04 — RE-ATTACK VERDICT: REJECT/2 on the fix wave** (`docs/reviews/2026-09-15-fixwave-reattack-verdict.md`,
genuine). Findings 4·5·6·7·8 CLOSED (6 as hardening — codex agrees the premise was false); HIGH #2
half-fix CLOSED as scoped; **HIGH #1 refutation ACCEPTED** (0116:73/121 + suite 151). Two remain, both
mine: **R1 MEDIUM** — finding 9's `packRetainRoster` ignores `sessionId` and the map never resets
roster/peers/camera on a sid change, so session A's people can render under a closed session B on route
reuse (a regression the fix introduced); **R2 MEDIUM** — the residual the 0172 agent named: a settled
booking the sweep cannot price is skipped with `raise notice` and `payments_reconciliation()` (0118:1392,
seven arms) has no `settled_without_payment` arm — silent revenue loss once payments open. Both in a
second fix wave now (client + 0173/203).

**12:34 — WAVE 2 LANDED (`e78f678` R1 roster fix, npm 989/0 · `f180d10` 0173 reconciliation arm, harness
1225/0, deno 292/0) and RE-REVIEWED: R1 CLOSED; R2 WRONG** (`docs/reviews/2026-09-15-fixwave2-reattack-verdict.md`)
— arms seven and eight of `payments_reconciliation()` both emit `payment_id = NULL`, and the group-by
invariant pinned by 116 C11 / 120 J4 groups all NULLs together, exactly as 0118:1382-1385 warned; the 0173
agent had named it 「green because disjoint in this fixture chain」. Fix as 0174 (correct-forward): the
invariant's grouping key becomes arm-aware (`coalesce(payment_id, booking_id)` per arm), 116/120 pins
updated in the same slice per the suite-update law. Pending on production: FOURTEEN → will be FIFTEEN.

**13:1x — 0174 LANDED (`3dcae46`):** `payments_reconciliation()` gains a ninth column `row_key`
(`payment_id::text` for arms one–six, `'booking:'||booking_id` for seven and eight — a SUBJECT key,
deliberately not arm-prefixed because that would defeat C11's duplicate detection; measured by plant ii);
the function is DROPPED and recreated (a `returns table` cannot widen in place — measured on a scratch
cluster, exactly as 0173's header ⑥ predicted), ACL restated; C11/J4 moved to group by `row_key`, same
assertion, same counts (chg 25, goc 10). Harness **1229/0** (+4), deno 292/0. ⚠ Recorded honestly: the
old C11/J4 could not see this defect and cannot demonstrate the fix (no fixture reaches two NULL rows at
their point in the chain) — suite 204 K1 manufactures the collision first, and plant iii proves the
re-keyed pins still catch a real duplicate. Re-review of 0174 running. Pending: FIFTEEN.

**13:02 — 0174 re-review: APPROVE, 0 findings** (`docs/reviews/2026-09-15-fixwave3-reattack-verdict.md`).
**The review chain on the pending set is CLOSED:** deploy-gate REJECT/10 → 6 fixed + 4 dispositioned →
re-attack REJECT/2 → both fixed → wave-2 REJECT/1 → fixed (0174) → APPROVE/0. Every actionable finding
has a reviewed fix on trunk. Still open by disposition, none of them code: HIGH #3 trace provenance
(Sean's option in the queue; 0168 widens a pre-existing class by ≤480 m), HIGH #2's production
recheck that the ops roster is non-empty (before the card flag), HIGH #1 refuted. The deploy of the
FIFTEEN is Sean's call — recommendation ⓐ deploy.

**Production is still 0156. Pending on trunk: FIFTEEN** — 0157 0158 0159 0160 0161 0162 0166 0167
0168 0169 0170. The 06:41 codex review (diff-scoped, sol high) writes its verdict into
`docs/reviews/2026-09-15-deploy-gate-verdict.md` and item 1 of `docs/decisions/awaiting-sean.md`.
**I did not deploy** (your call, and the harness classifier refused an unattended deploy job).

**Your queue, one line each (details in `docs/decisions/awaiting-sean.md`):** ① deploy — with the
verdict in hand, say 「deploy」 or 「hold 0168」 (money path, provisional 90 s/1 min constants) ·
② harness diet — say 「A」 (slim CLAUDE.md, 10 KB, ready) and/or 「B」; D measured at 2.6% of pins,
C withdrawn (19 s) · ③ Xcode 26 needs macOS 15.6+ — an OS upgrade, not an install · ④ labs: pick
numbers in `docs/labs/README-club-v2.md` · ⑤ Toss support ticket (memo §3) unblocks 0170's sweep ·
⑥ isHost split · phones #1/#4 · OPEN-C/F · km wallet, as before.

**Your four Codex sessions** (runner-rules 0163 · board-wrapper 0164 · membership 0165 ·
board-rejected-arm) had dirty worktrees and NO pushed branches all night; the heartbeat lands any
`codex/<slice>` branch the moment it appears. ⚠ 0165 redefines `club_session_roster`, which calls
0167's gated helper — read the gate back from the DB after both apply.

**Two misses of mine, both caught and recorded in `docs/codex-claude-protocol.md`:** 0169 landed
with trunk deno RED for ~40 min (the CONTRACT pin caught the unmapped raise; fixed at `34bd905`;
deno is now a landing gate for every migration) · a docs commit announced 0170 landed while its
trunk push had been rejected (read-back refuted it one command later; re-landed at `d04f74e`;
the landing chain is now `&&`-strict through the read-back).

---

## State, measured 2026-09-15 (new Mac `/Users/seankim/dev/daengrun`)

| | |
|---|---|
| Trunk | `069459b` — B1 (`b4bba36`+`9d874a2`, from rescue c105151) · 0157 (`ff6222d`, merge of rescue fba55f4) · 0158 (`df23718`, merge of rescue a5aa94a) · protocol docs (`069459b`) |
| SQL harness | **1229 / 0** at 0174's landing (1217 at 0171's (1213 at 0170's (1205 at 0169's (1201 at 0168's (1193 at `aa72341` (1188 at `bc7d59d` (1180 at `bb21ccd`, 1177 at `df23718`) — deltas 1135 → 1154 (+19, suites 191/192) → 1163 (+9, suite 188) → 1177 (+14, suite 189): each delta equals the pins added, so each suite demonstrably RAN |
| App tests | exit 0, **983 `^PASS` / 0 `^FAIL`** (+38 ✅ lines from run-geo) at `5bcc4dc`+ (980 at `df23718`); trunk before B1 was 822 |
| tsc · check-rpc-contracts · check-route-native-imports · check-definer-acl · check-device-clock | all exit 0 at `df23718` |
| Deno edge tests | **291 / 0** at bf47df7 (288 at the fix wave (287 at 0170 (277 at 0157 (`deno test --allow-all --node-modules-dir=auto _test` from `supabase/functions`) |
| Production | **MEASURED 02:00 KST after `supabase login`: 0156 deployed · pending 0157 0158 0159 0160 0161** (+0162 since `bb21ccd`) |
| Rescue branches | ⚠ corrected minutes after first push (I wrote 「all eight are ancestors」 — false): `merge-base --is-ancestor` says **4 MERGED** (0157-adopted · 0157-billing-hardening · 0158-adopted · 0158-settled-distance) · `wip-b1-pack-publish` is NOT an ancestor but its two commits landed by cherry-pick (`b4bba36`/`9d874a2`, same diff) · **3 hold UNLANDED work**: `routes-basemap-45de013` (4 ahead), `wip-main-clone-chat-slice-2026-08-28` (1 ahead — the inline-script fix, being adopted by P7), `wip-registry-row-ab47081-2026-08-28` (1 ahead, unexamined) |
| Toolchain | node 20 · pg16 · supabase CLI · cocoapods (needs `LANG=en_US.UTF-8`) · deno · bun · gh · gstack · codex 0.154 (bundled in ChatGPT.app + npm) · Xcode 16.2 + iOS 18.3.1 runtime · `app/ios` regenerated, pods installed |
| Still Sean-only | ~~eas login~~ ✅ · ~~supabase login~~ ✅ · **Xcode 26 install** (sim build) · the deploy go/no-go (see freeze note) |

**Harness lines the 09-15 merges fixed:** the rescue branches carried `suite 190_…` under its OLD
`# 0156` comment; a naive union registered 190 twice (double-counted pins). Deduped before landing;
`awk '/^suite /{print $2}' harness.sh | sort | uniq -d` is empty on trunk.

**Landed later the same night (02:xx KST):** P7 inline-script safety (`5bcc4dc`, codex astra low,
npm test 983/0) · **0162 chat client_key idempotency, both halves** (`bb21ccd`; client by codex astra
medium, server by Claude after codex hit a second quota wall; harness **1180/0**, +3 = suite 193;
mutation plant: index removed → K1 alone reddens 1179/1). Production re-measured after Sean's
`supabase login`: **0156 deployed, pending exactly 0157–0161** (0162 now joins the pending set).
`app/.env` pulled from EAS preview (needed `npm i -g eas-cli@latest`).

**Sean's Codex-app sessions in flight at write time (his worktrees, do not touch):**
`codex/runner-rules-checks` (0163/194) · `codex/board-wrapper-bundle` (0164/195) ·
`codex/membership-three-tier` (0165) · `codex/board-rejected-arm` (no number yet). They land via
Claude re-gating each `codex/<slice>` branch; expect REGISTRY.md + harness.sh unions on every one.

**SIMULATOR IS RUNNING (03:17 KST) — via EAS CLOUD, not local Xcode.** macOS 14.6.1 cannot run
Xcode 26, so the local route is dead until Sean upgrades macOS. The cloud route works: **the cause of
all four prior 「Configure expo-updates」 failures was `runtimeVersion: {policy: 'fingerprint'}`** —
switched to `appVersion` on branch `claude/eas-sim-build` (build `aee5b601` FINISHED; the empty
`expo-widgets` extension was also removed in that build — build 3 is isolating whether the widget
removal is needed at all; only the proven minimum lands on trunk). Installed on iPhone 16 Pro sim
(iOS 18.3.1, UDID `E5591637-…`), bundle id `com.seankookim.dogshigh`, login screen renders, the
Hermes bundle carries the Supabase host (`/usr/bin/grep -a`, 1 hit — this shell's `grep` is ugrep
and prints nothing for `-c` on a binary). **Signed out — Kakao login is Sean's; no smoke row past
the login screen until he signs in.** Recipe in memory + setup guide.

**Club-v2 labs landed (`b56ae34`, four files × 3 variants, Sean picks by number):** chat tiers ·
20-min hold · HOST setup (§16.7h — `club-v2-setup-lab.html` is the OWNER flow, different surface) ·
pack map counter. Index `docs/labs/README-club-v2.md`. Three findings the labs report upward:
① tier ② (signed-up READS) has no server today — `club chat read` admits host/full only and
`_club_shell_access` grades `full` on APPROVAL not payment, so an approved-unpaid owner can already
POST and a merely-signed-up one cannot read (0165, Sean's membership session, is the fix — verify it
narrows the write arm, which is a shipped right); ② 「access ends with the hold」 is unbuilt
(`_club_shell_access` never reads `hold_status`); ③ the seat frees at `hold_expires_at` while
`hold_status` stays `active` until the cron — screens must key on the timestamp. The viewer
counter's VALUE is unreadable by any client role (0160:436, RLS-on zero policies) — drawn as `—`.

**Simulator build BLOCKED on Xcode 26 (LOCAL route only):** Expo SDK 57's `expo-modules-jsi` declares
`swift-tools-version: 6.2`; Xcode 16.2 fails at package resolution. Sean-only (App Store).
Everything else for the build is in place (`ios/` regenerated, pods installed, iOS 18.3.1 runtime,
`.env`). Harness-diet proposal awaiting Sean's letters:
`docs/decisions/2026-09-15-harness-diet-proposal.md`.

**Landed 03:xx KST (Claude agents, no codex quota):** GPS finding-4 CONTRACT
(`docs/contracts/run-end-two-phase-stop-contract.md`, b1ee373 — buildable by astra next; §8 has four
Sean questions) · 185 suite repairs for codex 0154 #5/#6/#7 (`58166cc`, 1183/0) · **0166 revocation
findings** (`bc7d59d`, closes codex 0155 REJECT/6 — all six were still open on trunk, 0157 touched
neither dispatcher nor reporter; suite 196, harness **1188/0**, 8 plants each reddening one pin;
flag-gated, arms only when card registration goes live). **0168 two-phase stop LANDED (money path, codex GPS finding 4, from the contract):** the host tap stamps
`run_stopping_at` and freezes nothing; trace is accepted 90 s more (PROVISIONAL, Sean §8.1) then refused
by name (`run_stopping`); `club_finalize_stopped_runs()` (definer, service_role, pg_cron every minute)
derives km with an EXPLICIT cutoff = the tap and stamps `run_ended_at` = the tap; a derivation that
fails leaves the run `stopping` with NO ledger row (never a client-priced fallback). `_club_derive_run_km`
2-arg DROPPED, 3-arg replaces it (sole caller moved to the sweep; suite 187 updated). settle-run edge:
409 `run_stopping` after the party gate. Client: `runStopping` key on the board (runEnded untouched),
console 「기록을 모으는 중이에요 · 곧 확정돼요」, runner 정산 중 with settle disabled, late-upload banner
red 「업로드가 늦었어요」 not the amber retry. Harness **1201/0** (+8, incl. INACTION and control-pair
pins; M4 「refuse everything」 leaves P2 green), deno **281/0**, npm 983/0. ⚠ NOT codex-reviewed —
the 06:41 review scope includes it. ⚠ NAMED GAP: no SQL belt inside `settle_run_tx` — a direct
service_role caller can still settle a `stopping` booking at the client's numbers. Smoke rows (sim,
needs Sean signed in): host tap → console copy · runner 정산 중 · km appears after ~2 min · backgrounded
runner sees the red banner · owner's pack map stays up through the drain.

**0169 settle belt LANDED** — closes 0168's NAMED GAP: `settle_run_tx` refuses a `stopping` booking
(`raise exception 'run_stopping'` after the existence gate, before any write; base extracted from
0083's last definition, three-line diff). Harness **1205/0** (+4). ⚠ Flagged: contract §5 named this
token `run_stop_pending`; `run_stopping` is also what `club_save_run_trace` raises for the late-upload
event with different copy — the two never meet today (different function/endpoint; settle-run's own
409 fires first, and its RPC error map has no arm for either), but a future client arm must key on
the SETTLE path, not the token.

**0170 billing intent row LANDED** (Toss memo §4's branch-independent core, codex billing findings 3/4/6
local halves): `billing_issue_intents` — one row per issuance attempt, server-minted `Idempotency-Key`
persisted BEFORE Toss is called, states issuing → issued_persisted | issued_unpersisted | provider_error
| unresolved, no edge back to issuing; RLS-on zero client policies + explicit revokes; two definers
(open/close). register-billing-key handler: open → Toss with the persisted key → close(outcome) → swap;
a thrown Toss call closes `unresolved` and re-throws (no client-visible status changed). Harness
**1213/0** (+8), deno **287/0** (+6). PROVISIONAL per memo §3: replay_deadline 15 d (U1),
provider_error terminal (U6). The sweep that RESOLVES `unresolved` rows is NOT built (needs U1/U2 —
Sean's Toss ticket). ⚠ Also this hour: 0169 landed with trunk deno RED for ~40 min — settle-run's
CONTRACT pin caught the unmapped `run_stopping` raise; mapped at `34bd905`, deno is now a landing
gate for every migration (protocol updated).

**Pending on production is now ELEVEN (0170 joins):
0157 0158 0159 0160 0161 0162 0166 0167 0168 0169 0170 0171 0172 0173 0174** (0167 = codex 0154 #3 CRITICAL closed: `_club_phone_visible`
and `incident_contact` consult `phone_collection_live()`; `aa72341`, harness 1193/0, +5; four shipped
pins in 67/124/130 re-fixtured with the switch armed — ⚠ 0165 (Sean's session) redefines
`club_session_roster`, which calls this helper: after both land, read the gate back from the DB).** 0154 #1–#4 remain Sean's; 0154 stays a REJECT until then.
**Client honesty pass, wave 4 (Claude agent, non-club screens)** — 4 commits, 12 files, 15 fixes:
dead buttons removed (shop cart/search/담기, `pickEarliest` no-op, the iOS-only alert that fired on
iOS), loading-is-not-0 (schedule/calendar/community counters), fabricated data unbound (fixture
roster fallback in schedule, `62 + runs×5` 러닝 경험, 「신규」 for a never-written 응답률, 「0kg」),
`ensureRunner()` no longer swallowed on the entry path. npm 983/0, tsc 0. ⚠ **UNVERIFIED on the
simulator** (Xcode 26 blocker): shop header now title-only with non-interactive cards · the three
counters in loading/error states · matching sheet's 러닝 경험 bar for a 0-run runner · 반려견 추가 on
iOS must show exactly one dialog. Deliberately NOT changed (agent's table, worth reading):
`store.ts` dead fixtures (zero importers now — a follow-up delete), `login.tsx` naming legal docs
that do not exist (Sean's), the ~120 sub-15pt sites (director's call).

---

## State, measured 2026-08-31

| | |
|---|---|
| Production | **0156 deployed · pending: 0159 only** (`supabase migration list --linked`; 0157/0158 are REGISTRY rows with no files — invisible to migration list by construction) |
| Trunk | `d9d1451` — moved ~20 commits on 2026-08-31 alone (see Today) |
| App tests | **exit 0, 804 `^PASS` / 0 `^FAIL`** at `d9d1451` — ⚠ `grep -c '^PASS'` UNDERCOUNTS this chain: `run-geo-tests.sh` prints ✅ lines, not PASS lines (backend measured 801 PASS + 38 ✅ = 839 real on its tree). **Exit code + per-suite summaries are the reliable pair**; the PASS count is a floor, not the total |
| tsc | clean, exit 0 at `d9d1451` |
| Money | **OFF.** All three flags null (`payments` · `card_registration` · `phone_collection`), 0 billing keys, 0 revocation rows (measured `db query --linked`) |
| SQL harness | **1135 / 0 — PROVENANCE: b12b4a7's commit body (2026-08-28), NOT re-run 2026-08-31** (backend's B1 will move it; its tree reports 1150/0 unlanded) |
| Repo | **PUBLIC since 2026-08-31** (Sean, for free CI). Secrets sweep clean: only designed-public EXPO_PUBLIC values ever committed. CI (gates + React Doctor) green again on free minutes |

## Today, 2026-08-31 — the master-session day

Sean booted two master sessions off `docs/prompts/master-backend.md` / `master-ui.md`
(announcer-authored, inventory-grounded), coordinated by the announcer. Live sessions:
**announcer** · **master-ui-prompts-docs-6c8c89** · **daengrun-redesign-v4-77ea99 (backend)**.
Every other session named in older sections (b6, ui6, ui5, spec-v2, route-depth) is DEAD; their
claims were audited 2026-08-31 — see the REGISTRY audit note.

**Landed on trunk today (UI session, all codex-gated):** U5 focus-scheme ③ remainder
(`118c844`) · U2 pack-map doors (`1cccaea`) · U3 pay surface + red-line cap (`65fdab9`) ·
U4c host 러닝 종료 (`16c758b`) · U4b 백업 호스트 doors (`4f8ecb5`) · chat-rescue landing
(`2699935`) · runner 예약 규칙 editor (`1e5598b`) · codex wave-1 fixes (`bf0d387`, REJECT/5
all answered) · codex wave-2 fixes (`b8ce1c8`, REJECT/13 all answered,
ledger `docs/reviews/2026-08-31-codex-ui-wave2.md`) · floor rulings (`2ea34ec`). Codex round 3
(re-attack + U4b + rules editor) was running at write time.

**Sean's rulings today — all in `docs/decisions/2026-08-31-sean-rulings.md`, verbatim:**
club floor 15 everywhere (+ correction: the legacy sweep had already landed 08-27) ·
wire `club_end_pack_runs` (done, U4c) · avatar initials are glyphs · drop 不變 · leave ClubTag ·
OPEN-A 20-min hold · OPEN-B three-tier membership (public sees roster+pictures · signed-up
READS chat · paid participates — refined twice, read the file not a summary) · YES to the
pack-map viewer counter (folded into backend 0160/0161).

**Backend session (in flight, unlanded):** B1 pack-publish hardening — contract at
`docs/contracts/pack-publish-hardening-contract.md`, claims 0160/0161 + suites 191/192; design:
publishing moves to RPC `club_pack_publish` (per-publish gating, server-authored payload,
publisher channel removed). Measured on production: **PrivateOnly is enforced** — trunk's pack
map cannot connect until this deploys. B2 = adopt 0157/0158 from the rescue branches (takeover
annotated in REGISTRY). Then: S2.5 three-tier re-key · board rejected-arm widening (must incl.
dog-NAME visibility — dogs RLS has no host arm) · §16.7 pickup/return columns — those three
unblock the UI session's entire U1 fan-out. Announcer holds: 0153/0156 codex reviews + the Toss
provider memo (`docs/research/2026-08-31-toss-provider-memo.md` when landed).

**Standing sequencing (revised with B2 completion):** backend lands B1 → 0157 → 0158
sequentially (each re-gated post-rebase) → codex verdicts for all three off ONE frozen trunk
export → **ONE deploy of 0159+0160+0161+0157+0158** with production probes → freeze lifts at the
backend's announcement. Fallback if codex quota-walls mid-set: deploy the reviewed B1 set alone
and KEEP the freeze until 0157/0158 clear — either way the freeze lifts only when
trunk == production. Then:
UI removes the dead `clubName` param from `club/session/[sid].tsx` (~:1444) → hardware builds
allowed. The pocketed-phone pack-publish fade is a NAMED LIMITATION (smoke doc), not a bug; the
background-task publish fix is a queued backend slice. OPEN-C and OPEN-F stay unruled on Sean's
console. Smoke list: `docs/design/device-smoke-ui-master-2026-08-31.md` (10 ⬜ rows need
fixtures no read-only session can produce).

---

## 08-27/08-28 record below — superseded where it conflicts with the sections above

## State, measured (2026-08-27 — HISTORICAL)

| | |
|---|---|
| Production | **0152 — `migration list` pending: NONE.** Fully caught up for the first time. |
| SQL harness | **1081 pass / 0 fail** |
| App tests | **707 PASS / 0 FAIL** (counted across the whole chain, never `tail`) |
| Money | **OFF.** `payments_live_since` null · `card_registration_live_since` null · 0 billing keys · 0 revocation rows |
| Security sweep | 0 anon-executable definers · 0 definers missing in-body `search_path` |
| Stranded work | **NONE.** 0 unpushed commits; 9 spent agent branches, **9 of 9 confirmed duplicated on trunk by `patch-id`**. ⚠ The first version of this row said 「8 by patch-id, the 9th's file on trunk is a superset」 and **reported 9 clean having measured 8** — a superset proves the file MOVED ON, which happens for reasons unrelated to that branch. Corrected by b6; the 9th was then settled properly (`patch-id` match at `91c581e`). **Same conclusion, and the evidence for it did not exist when it was written.** |

## What went live today (0130 → 0152, three sessions)

A 동반 (self-run) walk becomes a real record · the host's one-tap 러닝 종료 ends every runner's
walk on **server-derived** distances · 1 dog per person enforced by a table trigger, not a hidden
button · the club board's names open profiles, and non-runners have profiles at all · 집 반환
directions · KST everywhere (a ticket no longer prints the wrong weekday on an off-Seoul phone) ·
~950 text-size fixes to the 15pt floor · Instagram-shaped profiles + editor · guests-come-free
said out loud on the club board · unknown distances stopped rendering as `0km` · billing-key
hardening incl. the crash window where a destroyed key could be stored as a live card.

## 🔴 OPEN — needs Sean, in priority order

1. **The lawyer email.** `docs/legal/counsel-email.md` — copy-paste ready, two attachments, a
   three-line pre-send checklist, referral line deliberately blank. **This gates phone
   collection, publishing the privacy policy and terms, the KCC filing, and launch.** Oldest
   open item; nothing else on this list is close.
2. **Device build — and ⚠ RETRACTION of what this line said an hour ago (ui6, 2026-08-27).**
   I wrote here that 「THERE IS NO BUILD, NOTHING HAS EVER REACHED A PHONE」. **That was wrong,
   Sean caught it in one sentence — 「look at the ios sim」 — and the original line it replaced
   was closer to right than my correction.**
   **What I measured:** `eas build:list` empty (**true** — no CLOUD build exists) and no installed
   app for `com.seankookim.dogshigh` (**true, and irrelevant**). **What I reported:** that no build
   exists at all. 🔴 **The installed simulator app is `com.seankookim.daengrun` — the OLD bundle
   id.** The config was renamed to `dogshigh`; the installed shell predates that. I searched for
   the current identifier, got nothing, and promoted it to a claim about the world.
   **The measured truth:**
   · A **simulator build exists**, made **2026-08-13**, bundle id `com.seankookim.daengrun`.
   · It is a **DEBUG** build → it carries **no embedded bundle** and loads JS from **Metro**.
   · Metro is live on `:8081` from a worktree — so **the simulator runs TODAY's client**, and
     today's UI work is visible on it right now (verified by screenshot: `시간만 고르기 ›` renders
     ink — this afternoon's dim-text fix — while `예정된 러닝이 없어요` stays grey, the one
     deliberately left alone).
   🔴 **THE REAL GAP, which is narrower and more useful than what I claimed:** a Debug shell
   carries only NATIVE code. **Any native change since 2026-08-13 is NOT in what anyone is
   looking at** — JS flows through Metro, native does not. And there is still **no artifact
   installable on a PHYSICAL device** and no EAS cloud build.
   ⚠ **Whoever reads the simulator must also read WHICH Metro** — `lsof -nP -iTCP:8081` then the
   pid's `cwd`. A Debug build binds to whatever Metro answers, so it can silently serve a peer
   session's tree, and the screen then shows someone else's work.
   **What was done toward it (ui6, 2026-08-27):**
   · `EXPO_PUBLIC_SUPABASE_URL` + `_ANON_KEY` pushed to the EAS `preview` environment — there
     were **zero** env vars configured, so no build could ever have reached Supabase. Uploaded
     with `eas env:push --path .env`, which reads the file itself (no value handled by hand).
   · a **`simulator`** profile added to `eas.json` — it needs **no Apple signing**, which is the
     only iOS artifact obtainable without an interactive Apple credential setup.
   · `.easignore` added: the archive was **289 MB against a 4.6 MB app** (`docs/` 171 MB +
     `supabase/` 87 MB, neither compiled into a client). ⚠ It is a **superset of `.gitignore`**,
     verified rule-by-rule, because EAS uses it *instead of* `.gitignore` — dropping one line
     would ship `.env` to the build servers.
   · the app **bundles clean**: `expo export` produces a 7.3 MB Hermes bundle, exit 0.
   🔴 **STILL BLOCKED, three attempts, all identical:** every iOS build fails at the
   **`Configure expo-updates` build phase** with `UNKNOWN_ERROR`. ⚠ Ruled out: missing env
   (attempt 2 had it), archive size (attempt 3 was small), and local config — `expo config
   --type introspect` resolves fine, exit 0. **Prime suspect: the `ExpoWidgetsTarget` app
   extension**, which introspection shows carries `widgets: []` — an app extension with no
   widgets, configured alongside expo-updates. **The phase log is on the build page and the CLI
   cannot print it** (`api.expo.dev/.../logs` → 404 unauthenticated); someone with dashboard
   access should read it first — do not spend a fourth build guessing.
   ⚠ **And signed iOS builds are Sean-only regardless:** both `preview` and `testflight` fail at
   credential setup demanding interactive mode (Apple Developer sign-in). Android is not an
   escape — `android.package` is unset, so this app is iOS-only in practice.
   **When a build finally exists, `docs/design/device-smoke-ui6-2026-08-27.md`** is 33 honestly-⬜
   rows; its first section needs the phone's timezone **off Korea** before any row means anything.
   **The old text follows, still true of the code itself:** none of it is
   simulator- or device-verified. ~950 type-size changes and five screens of colour/copy work
   look fine in a diff and wrap badly on hardware. `docs/design/device-smoke-ui6-2026-08-27.md`
   is 33 honestly-⬜ rows; its first section needs the phone's timezone **off Korea** before any
   row means anything.
3. **Guest GPS → now a three-way question: `docs/decisions/guest-gps-options.md`** (landed
   2026-08-27). Every citation above verified at source, but **the framing here was wrong three
   ways and the third one is the decision.** (a) It is a **pack gap, not a guest gap** — there is
   no map of the group anywhere in the product; a 동반 owner *with* a dog is equally invisible
   (`club/companion/[sid].tsx:7,141` imports `startTracking` and publishes nothing), and the host
   sees nobody. So 「the same gps share service」 **has no referent yet**. (b) 「half a ruling
   unbuilt」 overstates it: `2026-08-25-console-rulings.md:1302-1306`, same document and same day
   as the ruling, records that **direction-of-sharing and who-may-see-whom were explicitly left
   open**. Nothing is owed; the question was never asked. (c) The constraint that decides it was
   omitted — `privacy-policy.md:91` promises 「해당 예약의 보호자에게만 … 다른 이용자나 제3자에게
   제공하지 않습니다」, and **every watch-the-pack option rewrites that sentence on a document
   currently in front of counsel** (item 1).
   ⚠ **New and not previously written down: session membership is self-serve.** `session_rsvp`
   has no club-membership and no host-approval gate (`0134:53-61`), `club_sessions` is
   `select using (true)` (`0030:133`). So 「a member of this session」 means 「anyone who found an
   open session and tapped join」 — which in code looks exactly like a membership check.
   Option ①（record, no map）needs one predicate and changes no privacy promise; ②/③ need counsel
   first. **All READ, no production query.**
4. **Card revocation → `docs/decisions/card-revocation-abandoned.md`** (landed 2026-08-27,
   **measured against production, not read**). Handoff confirmed on deployed `prosrc`: the
   8-attempt cap is real in both `claim_` and `report_`, and `enqueue_billing_key_revocation(…,
   'account_deleted')` precedes the local row delete at `0115:535`. OBSERVED live: **0 keys,
   0 revocation rows, 0 abandoned**, both money flags NULL, `revoke-billing-keys` ACTIVE v2 with
   its cron live and **11 ticks all `idle`** — so the `X-Cron-Key` handshake **has never actually
   run in production**, and the first real revocation is also its first live test.
   🔴 **The handoff's most valuable error: 「nothing reads it」 is *nearly* true, and the near-miss
   is worse than the claim.** There IS a reader — the view `billing_key_dispatch_health`, whose
   `due_now` (`0150:413-415`) counts `pending` + expired-lease `processing` and **structurally
   excludes `abandoned`** (verified: the deployed viewdef does not contain the string). So the one
   dashboard-shaped object in this family **reports the queue clean precisely because rows were
   given up on.** Also: 「someone who asked to be gone」 covers **2 of the 5 reasons**; `failed` is
   dead vocabulary written by nothing; and **there is no card-removal affordance in the client at
   all** — 「remove my card」 *is* 「delete my account」.
5. 🔴 **NEW (announcer, 2026-08-27, verified against production myself) — the host sees every
   member's phone number, and it arms the same instant phone collection does, with nothing in
   between.** Deployed `_club_phone_visible` (read from `pg_proc`, not from a migration file) is
   bidirectional host ↔ **everyone** for any session in `open`/`full`. A person-only guest is on
   that roster. **Not breached today and not close:** OBSERVED `profiles where phone is not null`
   = **0**, and `set_my_phone` has **0 client callers** (0133 landed the server deliberately
   without a collection point). ⚠ **But `ops_flags` has no phone column** — card registration has
   a switch and phone collection does not. So there is no way to turn phone collection on
   *without* turning host-sees-everyone on in the same commit. That makes it a decision that has
   to be made **before** the wiring, not after — and it lands in the same envelope as item 1,
   which is what unblocks phone collection in the first place. Related and still open from
   2026-08-26: whether a dogless guest counts as a 「member」 for this rule at all.
6. **`net` schema grant — needs Supabase, not us.** `anon` holds `USAGE` on `net` and `SELECT` on
   `net._http_response` and `net.http_request_queue` (whose headers carry `X-Cron-Key` and an
   `Authorization` bearer). **Structurally out of reach:** `net` is owned by `supabase_admin`,
   migrations run as `postgres` (not superuser, not a member), and REVOKE only removes grants
   issued by the current role — 0151 aborted itself proving this rather than claiming success.
   **Not reachable from outside:** PostgREST exposes only `public, graphql_public`; the anon key
   gets `406 PGRST106` on `net` and `200` on `public.clubs` (control run). **Defence in depth, no
   known reach.** A support request, not a blocker.

## ui6 lane — state at handoff (2026-08-27)

**Deployed and verified against production, not inferred:** 0131→0152, all 22. `migration list`
pending **NONE**. Anon-executable definers **0**, definers missing in-body `search_path` **0**,
`payments_live_since` and `card_registration_live_since` both **null** — no money moves. Edge:
`register-billing-key` v2, `revoke-billing-keys` v1 (first ever deploy, `verify_jwt=false` from
the committed `config.toml`).

🔴 **The money defect is closed ON THE LIVE ROW, not a fixture.** Production booking
`4f053152-…` — `actual_km` NULL, `incident_review` — now answers `basis=incident_unmeasured`,
`measured_km` NULL, `runner_gross` NULL. **An hour earlier that same row quoted 「실측 0km」 and
multiplied the runner's distance and addon fare by that zero.** Found by the announcer on the
screen; escalated here after measuring `0121:296`, where the ratio is *spent*.

**Dim-text wave 3 LANDED** (`69a926a`) — 48 sites read, **10 inked**, 707/0. Ratio ~21%, which
matches owner/home's 2-of-8 and is the third independent confirmation that this is a judgment
pass and not a sweep. ⚠ **`club/receipt` came back 0 of 10 and that is the finding**: its dim
styles are `club-ui`'s shared `bignumLabel`/`LoadGate` recipes byte-for-byte, and `theme.ts:80-86`
already records `L.dim` at **4.24:1 — under the body floor — as an open item reserved for Sean**.
Inking them per-site would be the first half of a product-wide repaint, made by an implementer.
**Left at the wall, deliberately.**

**사고 신고 (incident) client flow LANDED** (`de902e6`) — the biggest missing surface, closed.
New `app/app/incident/[bid].tsx`, `safety.tsx`'s 「준비 중」 card replaced by a real resolver, and
push routing for both roles. 707/0, route count 61→62, rpc calls 116→118 (**both deltas are
positive controls — the checkers demonstrably saw the new code rather than passing by not
looking**).

⚠ **It found that `0114` SUPERSEDES `0094` for the opener, and reading only 0094 would have
shipped a wrong client.** The reportable set (0114 §3 ⑥) is the accepted set **plus
`cancelled_owner` and `refund_pending`**, while `is_booking_party_active` — which gates chat AND
**`notifications` insert** — is the accepted set only. **So in exactly two states a party may
REPORT and may not be NOTIFIED.** Collapsing them ships a control that 42501s in the state 0114
widened the report set to protect.

⚠ **`incident_contact` was deliberately NOT built.** Its privacy prerequisite is met
(`privacy-policy.md:45-46`), but it returns `profiles.phone`, and `0133_phone_collection`
**landed the server and left the collection point unwired** on its own ship gate — measured **0
of 10** rows populated. It would return two blank rows. It stays unbuilt until the lawyer item
(OPEN #1) clears, which is the same gate.
⚠ **The runner sees 「보호자」, not a name** — no `profiles` SELECT policy admits 「the owner of my
booking」 (0002:55-58; 0145's arm is club-board-only). The only route to that name is the definer
that also hands over a phone number.

### What a next session should not re-learn

- ⚠ **`club_join` / `club_leave` are built and unreachable** — membership only happens as a side
  effect of committing to a session. Seven more granted-to-`authenticated` RPCs have no caller:
  `open_incident_tx` · `verify_incident_tx` · `incident_contact` · `session_set_backup` ·
  `club_assume_host` · `session_reconsider_dog` · `km_claim_welcome` · `runner_work_gate` ·
  `set_my_phone`. **That list is the honest map of missing UI**, derived from grants, not memory.
- ⚠ **Dim-text: the counts in circulation were wrong twice and both were mine.** 412 counted a
  colour token appearing anywhere — `placeholderTextColor` (which MUST be dim), dots, borders.
  Honest upper bound ~203 *text* styles. **Measured violation ratio on owner/home: 2 of 8.** The
  real count cannot be produced by grep, because the question is 「may the customer skip this?」.
  **An agent handed the 412 would have turned 29 placeholders ink and made every form look
  pre-filled.**
- ⚠ **`0151` was EDITED IN PLACE after landing on trunk**, against the correct-forward law. The
  exception was narrow and is stated in its header: its abort made every later migration
  unreachable, and `migration list` proved no environment held the old version. **If you meet a
  landed migration that cannot apply, that is the test to run — not the law to ignore.**

## Lanes

- **announcer** (this session) — coordination, Sean's queue, server/security. Nothing in flight.
- **b6** — club session/console/run screens, client honesty. Holds `club/session/[sid].tsx`,
  `club/console/[sid].tsx`, `club/run/[sid].tsx`, `club/receipt/[bid].tsx`,
  `src/components/run-share-card.tsx`, `app/shot/[bid].tsx`, and — added after this file's first
  version — `src/lib/rpc-skew.ts` + `test/rpc-skew.test.cjs`, `src/lib/tier.ts` +
  `test/tier.test.cjs`. ⚠ **Those four are small pure modules with MUTATION-VERIFIED pins:
  anyone editing them must re-run the batteries, not just the suite.** A green suite after a
  predicate edit means very little on its own — that is what the batteries are for.
  **Open for b6: only the guest counterpart on the session screen.** ⚠ **CORRECTED AGAIN — this
  file said 「waiting on the verified findings already sent」 and they had NOT been sent.** The
  announcer promised them twice, told Sean they were sent, and recorded that in this file.
  They were delivered 2026-08-27 after b6 pointed it out. **「Waiting on findings sent」 and
  「waiting on findings not sent」 are different states for whoever picks this up**, which is the
  whole reason it is worth a correction rather than a quiet fix.
  🔴 **And the fifth question — 「does a guest change what the HOST sees」 — was never answered
  by the agent**, which answered a different fifth of its own. Measured against the DEPLOYED
  0131 policy instead: **YES, the guest is visible to the host.** `session_people`'s policy is
  `(auth.uid() IS NOT NULL) AND ((profile_id = auth.uid()) OR _club_session_member(session_id,
  auth.uid()))`, and the deployed helper carries host and backup-host arms — so a host is a
  member and a member reads every `session_people` row in the session, dogless or not. ⚠ This
  only became answerable AFTER the deploy; pre-0131 the table was `auth.uid() IS NOT NULL` and
  the question was meaningless. Everything else b6 built is on trunk.
  ⚠ **CORRECTED — this file's first version said b6's two `PENDING_DEPLOY` entries 「can come
  out」 and the run-screen obligations were 「still open」. Both were already DONE** (`2b5d1c1`,
  `0714ac8`); b6 landed them while this was being written. Measured on origin: PENDING_DEPLOY
  executable mentions **0**, `runEnded` executable gates **3**, rpc-skew pin **10/0**.
  🔴 **The reason this was worth correcting rather than shrugging at:** a handoff saying a pin
  「should be failing until you do it」 sends the next session to run it, watch it PASS, and
  reasonably conclude **the pin is broken**. That is a false green manufactured by
  DOCUMENTATION — the same shape we spent two days removing from code, arriving through a file
  nobody thinks to distrust.
- **ui6** — design system, board, payments, deploy trigger. Holds `owner/request.tsx` and the
  press-grammar sweep.
- **Claim before you edit**, in REGISTRY's in-flight table, path-keyed. **Migration numbers are
  THREE-sided**: REGISTRY row · every remote branch · **local worktree branches** (`git branch -a`
  — `ls-remote` cannot see an unpushed agent worktree, and that is now the likeliest collision
  surface). Re-read at COMMIT time, not only at claim time.

## Two things that will bite the next session

- **Committing a hook does not install it.** `core.hooksPath` is the MAIN CLONE's
  `/Users/sean/dev/daengrun/.githooks`; a worktree's copy is a different file. After committing
  the pre-push fix, the repo had it and the machine did not. **Verify the live file.**
- **This shell wraps `grep` in a function that execs `ugrep`.** A hook runs under `sh` and gets
  `/usr/bin/grep`. Two sessions each spent an hour "verifying a hook's own pattern" through the
  wrapped grep — four checks that varied the input and held the tool fixed, which was the axis
  that mattered. **Use `/usr/bin/grep` explicitly when testing anything a hook runs.**
- ⚠ **The pre-push hook falsely refused two pushes** ("migration NNNN has no REGISTRY.md row")
  on pushes whose row WAS present. **Neither session found the cause and the state is gone.** It
  now prints its evidence on refusal — sha, byte length, rows it can see, the rows nearest the
  one it wants — so the next occurrence is self-describing. Two-sided tested with the evidence
  path exercised on a real refusal, and the ORIGINAL hook returns identical verdicts on both
  arms, so behaviour did not move.

## ui6 session 2026-08-28 — what landed, and two corrections to the brief

**① The card/billing chain now has a codex verdict: REJECT, 7 findings** (5 HIGH, 2 MEDIUM) —
`docs/reviews/2026-08-28-codex-billing-chain.md`, with the prompt archived beside it. First review
that chain has ever had. Nothing fires today (both money flags NULL, 0 keys), but **two HIGH
findings arm on `card_registration_live_since` ALONE** — charging does not have to be on — and both
put a real card in a wrong state.
🔴 **The one thing to act on: findings 3 and 4 both bottom out in a single unanswered PROVIDER
question — can Toss replay or look up a billing-key issuance by a persisted idempotency key, and
what does a repeated DELETE return?** The fix shape for both is unknown until that is answered, so
**it is now on the critical path to turning card registration on**, and it is a question for Toss's
documentation or support, not something to design around by guessing. Nobody owns it yet.
Closed 3 of codex's 5 open questions against production (all reads): the revocation cron **exists
and runs** (jobid 23, 110/110 succeeded, latest 00:48Z — which narrows finding 5 from breached to
latent); base-table ACLs are sealed but **asymmetrically**, a finding codex could not see from
source — `billing_key_revocations` revoked its client grants AND has RLS, `billing_keys` has **only**
RLS while carrying `anon`/`authenticated` SELECT **and INSERT**; and `net.http_request_queue` was
already settled on 2026-08-27.

**② `club_join` / `club_leave` BUILT and landed** (`297139a`). The sharpest of the eight, and the
gap was total: measured on production, exactly three deployed functions insert into `club_members`
— `club_claim_host`, `club_join` (unreachable), `session_runner_commit` — and **`session_rsvp` does
not**, because 0048's R4 abolished auto-join and left the invitation to 「UI/알림 몫」. So an owner
had **no path to membership by any route that existed**. Live data: 1 club, 14 sessions, 1 distinct
participant, `club_members` = 1 row (role=host). `club_overview` has been returning `isMember` the
whole time and the client read it in **exactly one place — the type declaration.**
🔴 **Server defect found while scouting, still open and unowned:** `club_overview.isHost` reads
`clubs.host_profile_id`; `club_demand_board.isHost` reads `club_members.role='host'`. Two deployed
definitions of one word, agreeing only because `club_claim_host` writes both. `club_leave` deletes
just the member row, so a host who leaves splits them. **The client ships with no leave affordance
for a host, so it cannot reach that state** — but the fix (refuse a host, or clear
`clubs.host_profile_id`) is a product call.

### ⚠ Two of the eight are NOT what the list says, and both were measured

The 「eight capabilities the server has and no screen offers」 list is derived from grants, which is
the right method, but a grant with no caller does not by itself mean a missing capability.

- 🔴 **`km_claim_welcome` is NOT a client-only slice — do not build the button.** The RPC is
  server-complete, but **the entire km subsystem has zero client callers**: `km_balance`,
  `km_purchase`, `km_reserve`, `km_settle` — all of them, 0. There is no km wallet anywhere in the
  app. km is wired into `_resolve_checkin` server-side, so granting the welcome 5km would hand
  someone an **invisible asset worth ~₩16,700 in runner pay** that they cannot see, spend, or
  understand. That is a worse defect than the gap. Building it honestly means building the wallet
  surface first, and deciding whether the km prepaid model is the intended one at all — money-shaped,
  with a 500-account cohort cap and ~₩8.4M exposure written into the function. **Sean's call, not an
  implementer's.**
- ⚠ **`runner_work_gate` is already delivered — the capability is not missing.** It has no client
  caller because it does not need one: `transition-booking/index.ts:77` calls it and returns
  **`waiting_on`-differentiated Korean copy** on a 409, so a gated runner is already told exactly
  why and what unblocks it. A direct client call would be pre-emptive polish (tell them before they
  tap, not after), which is real but is not a missing capability. ⚠ I nearly reported this one as
  「the gate is unenforced」 off a SQL-only search that found no caller — the enforcement is in
  TypeScript. **The measurement licensed 「no deployed SQL function references it」, not 「it is
  unenforced」**; caught before it was written down.

**`club_assume_host` and `session_set_backup` were deliberately NOT taken** — they belong on
`club/session/[sid].tsx` and `club/console/[sid].tsx`, which b6 holds exclusively. Flagged, not
built.

⚠ **Nothing in this session is simulator- or device-verified, and that was a choice.** Metro on
`:8081` serves `daengrun-redesign-v4-77ea99/app` — **a peer session's worktree** — so the simulator
cannot show this work, and repointing the shared simulator would have taken it away from that
session. The club membership card is unverified on a device. App tests are **707/0 UNCHANGED**,
which is honest rather than reassuring: `app/test/*.cjs` structurally cannot import a `.tsx` route
module, so the suite says nothing about this screen either way. Gates that DID move:
`check-rpc-contracts` 118 → **120**, exactly the two new calls — a positive control that the
checker saw the code rather than passing by not looking.

## ✅ CLOSED 2026-08-28 — the live board disclosure (was: needs one line). `0153` DEPLOYED

`0147` grants `authenticated` direct EXECUTE on the INNER board function, and that function
**trusts a caller-supplied access grade instead of deriving it**. Found cold by codex; then
**reproduced against production**, which is the pairing this file's laws prescribe.

Measured: `_club_delegation_board_impl(p_session uuid, p_access text)` is `prosecdef`,
`has_function_privilege('authenticated', …, 'EXECUTE')` = **TRUE**, the body references `p_access`
and — comment-stripped — **never references `_club_shell_access`**. The outer
`club_delegation_board` derives the grade correctly; nothing makes a caller use it. It lives in
`public`, which PostgREST **does** expose — so unlike the `net` grant (OPEN #6), the allowlist is
not standing in front of this one.

Executed as role `authenticated` with **no party relationship** to the session, on a session that
actually has content: `p_access='host'` returns **1 dog / 2,185 B**, `p_access='none'` returns
**0 dogs / 663 B**. Different digests. The forged grade hands over `ownerName`, `runnerName`,
`proposedRunnerName`, `custodianProfileId`, `runnerId`, `bookingStatus`, `chargeState`,
`refundState`, `payoutState`, `payoutHoldReason`, `openIncidentId`, `dogName`, `collar` — **names,
re-identifying profile IDs, money state and incident references for a stranger's session.**

**Fix is one line:** `revoke execute on function _club_delegation_board_impl(uuid, text) from
authenticated;`

✅ **DONE — `0153_board_impl_not_for_clients.sql`, deployed and verified TWO-SIDED on production.**
Live catalog after: `authenticated` EXECUTE on the impl **false** · `anon` false · `service_role`
**true** · outer `club_delegation_board` still **true**. 🔴 **The exploit, re-run verbatim, now
returns `42501: permission denied`** where an hour earlier it returned 1 dog / 2,185 B; the control
confirms the legitimate door still opens. Harness **1086/0** (+5 = exactly the pins added — the
positive control that suite 184 RAN rather than being skipped from the manifest). Mutation battery,
4 arms, each `&&`-chained to its plant so an unlanded plant yields no row: revoke removed →
**APPLY ABORTS**; revoke removed + VERIFY removed → **B1 red alone**; over-reach (service_role also
revoked) → **B3 red alone**; control → **1086/0 clean**. B1 is blind to over-reach and B3 to
under-revoke, so they are two genuine controls, not one printed twice.
⚠ **B2 (anon) does NOT redden under the plant, and that is honest rather than a gap** — `anon` was
already revoked by `0147:189`, so B2 pins a property 0147 holds, not one 0153 establishes.
⚠ **NO CODEX PASS. codex was quota-walled until 14:33. This slice is NOT reviewed and nobody may
say it is.** It is owed one.

⚠ **My first attempt at this proof measured NOTHING and read as reassuring** — run against the
first session id in the table, both grades returned identical digests, because that session has 0
dogs and 0 runners. An empty fixture discloses nothing regardless of grade. Same trap as
`billing_keys`. **Find a fixture with content before believing a negative.**
⚠ Rung honesty: the DB-level call is OBSERVED; the same call over PostgREST with a real user JWT is
NOT — that rung is a read, not a measurement.

## Also new 2026-08-28 — the run-end money chain is REJECT, 12 findings

`docs/reviews/2026-08-28-codex-runend-money.md`. Beyond the disclosure above:
- 🔴 **CRITICAL: a runner can mint arbitrarily inflated earnings** with a future-timestamped GPS
  trace. Ingest rejects neither future timestamps nor trace duration; the only bound is 100 km. It
  moves the ledger and runner earnings **today** — no flag involved.
- **`club_end_pack_runs` has ZERO client callers** (verified independently: no executable reference
  anywhere in `app/`). The whole 0144 freeze is not in the settlement path; runs settle from the
  runner's own button, so **the runner's client values price the ledger**. Whether to wire it or
  retire it is Sean's call, and two other findings fall out of that answer.
- **0152 is incomplete**: weekly, fitness and leaderboard aggregates still coalesce unknown distance
  to zero. ✅ Codex's open question answered on production — `completed` bookings with NULL
  `actual_km` = **0 of 8**, so this is schema-reachable but **not observable today**. ⚠ One
  transition away: 1 of 9 runs has NULL km AND NULL duration (the `incident` run sitting in
  `incident_review`).

## 2026-08-28 — a third capability that is NOT a client-only slice, and a live product dead end

`session_reconsider_dog` was scouted and **deliberately not built.** The contract was read from
deployed `pg_proc`: host-only (`not_host` party gate), requires `approval='rejected'`, session
`open`/`full` and not past, and returns a NEW pending `session_dogs` row (the rejected row is never
mutated).

🔴 **The blocker is that the only party allowed to call it cannot SEE the rows it operates on.**
`_club_delegation_board_impl` admits rejected rows only through an **owner-only** arm
(`d.owner_profile_id = auth.uid() and d.approval in ('rejected','withdrawn')`), and
`club_session_board` excludes them for everyone. **Measured with a discriminating control** on the
production session holding the one real rejected dog, at the maximum grade: `auth.uid()` = the dog's
owner → **1 dog**; `auth.uid()` = a different profile → **0 dogs**. ⚠ That session's host IS its
owner, so the naive read proves nothing — the non-owner arm is the measurement that decides it.

🔴 **AND THE PRODUCT HAS A LIVE DEAD END THAT THIS RPC EXISTS TO CLOSE.** Deployed
`session_delegate_dog` refuses re-application after a `host_rejected` attempt, and
`club/delegate/[sid].tsx:104` renders that as **「이 세션에서 거절된 신청이 있어요 — 호스트에게
문의해주세요」**, while `club/session/[sid].tsx:1116-1119` deliberately draws no re-apply door
because the remedy is the host's. **The host's remedy is unbuilt.** The app tells an owner to go ask
the host, and the host has no button — **a mis-tap on 거절 is permanent for that dog in that
session.**

**It belongs on `club/console/[sid].tsx`** (b6's, exclusive) — beside the existing `pending` /
`review` filters, as one sibling section. Flagged, not taken. Whoever owns the console needs: a
rejected-rows source (a host CAN read them by direct table select today — `authenticated` holds
SELECT and `_club_session_member`'s arm ⓐ is the host; the cleaner fix is widening the board's
rejected arm, which is a server slice), an error map for `not_rejected`/`session_closed`/`not_host`/
`not_found`, and copy that promises only 심사 대기 — **not** a seat, since `session_approve_dog` can
still fail `no_capacity`.

⚠ **Two more facts worth carrying.** (a) `club_flags.club_delegation_v2` is **`enabled: false`** on
production, so this RPC and the whole v2 surface raise `feature_disabled` for anyone outside
`club_test_accounts` — whether that is intentional-for-now or a stale flag is a product question
nobody has answered. (b) The RPC is **not idempotent**: it never clears the old row's `rejected`, so
a second call passes all five gates and inserts a second active `(session_id, dog_id)`, violating
`session_dogs_active_uni` with a raw `23505` no error map would translate. ⚠ Deductive from two
observed facts, **not executed** — no write was made to production.

**Running total: three of the eight 「server-complete, client-only」 capabilities are not that.**
`km_claim_welcome` (no km wallet exists at all), `runner_work_gate` (already delivered via the edge
function's 409), and now `session_reconsider_dog` (the caller cannot see its own rows). The list was
derived from grants, which is the right method — but **a grant with no caller is not by itself a
missing capability**, and that distinction has now cost three scouts to learn.

## ✅ 2026-08-28 — the CRITICAL GPS fraud vector is CLOSED on production (`0156`)

A runner supplied every coordinate **and every timestamp**; ingest checked only monotonicity and
≤8 m/s, and derivation had **no upper bound at all**. A plausible slow trace dated hours ahead froze
99 km into a 5 km booking and the payout path wrote it to `ledger_items`. **No flag gated it.**

**Proven on production after deploy, read-only, with two controls:** the attack (two real fixes plus
a DENSE fabricated tail an hour ahead) derives **0.10 km** — identical to the honest trace with no
tail (**0.10**), so the forged tail contributes nothing — and a densely-sampled stationary dog still
derives **0.00**, so the fix did not over-reach into refusing honest zeroes.

**The shape worth knowing:** `_club_derive_run_km` is `stable` and is called from exactly one place,
inside the freeze transaction — so `now()` there IS the host's tap. Bounding on it gave the
reviewer's `started_at <= t <= v_at` with **no signature change and no 225-line recreation**.
A 60 s tap grace is deliberate: a fix a second after the tap is jitter, and a strict bound would
silently UNDER-pay the runner, which is the same class of error pointed the other way.

⚠ **This does NOT close finding 4.** Points arriving after the tap are no longer counted, but the
stale-trace race still needs a two-phase stop. Do not read 0156 as closing it.
⚠ **The 300 s coverage threshold is PROVISIONAL and is Sean's call** — codex's own open question is
「what maximum gap and minimum coverage define a measured run, including a genuinely stationary
dog?」 and nobody has answered it. It is one named constant.
⚠ **NO CODEX PASS** — quota-walled until 14:33. 0153 and 0156 are both owed one and neither is
reviewed.

⚠ **Suite 176 was repaired in the same slice**, per the standing rule. Its over-band fixture
(999 × 111 m ≈ 110.89 km) only ever fit because its generated timestamps ran **≈3.7 hours into the
future** — at the 8 m/s ingest ceiling that distance cannot happen in 30 minutes. `dF` is re-dated
five hours back; it is BLOCKED and freezes no km or duration, so no other pin reads its timing.

⚠ **I also deployed 0154 and 0155, which are another session's**, because `db push` has no per-file
selection and 0156 was a live money bug. **Verified safe before deploying, not assumed:** 0154 ships
`phone_collection_live_since` **NULL** (it adds the switch, it does not flip it) and I confirmed
`phone_still_off = true` on production afterwards; 0155 arms only when card registration goes live
(0 keys, 0 revocation rows). ⚠ **0155's REGISTRY row still reads 「NOT DEPLOYED, NOT PUSHED」 and is
now stale twice over** — its owner should correct it.

## Unreviewed

~14 of the 21 deployed migrations carry **no codex verdict**, and 0131's seven review rounds
cover **0131 alone, not the stack**. Sean was told this before authorising and chose to proceed.
Worth a sweep when there is quota to spend.
