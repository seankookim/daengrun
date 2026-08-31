# codex round 2 — UI wave (U3 + U4c + chat rescue + round-1 fix round)

**Genuine verdict** (gpt-5.6-sol, xhigh, frozen export, digit-detector `FINDINGS: 13` on stdout,
no quota wall): **REJECT, 13 findings.** Round 1 (U5+U2) was REJECT/5, answered in `bf0d387`.
This file is the round-2 disposition ledger — written BEFORE the fixes so a context compaction
cannot lose the mapping. Status column updated as fixes land.

| # | file:line (at review) | sev | finding (compressed) | disposition |
|---|---|---|---|---|
| F1 | owner/pay.tsx:250 | HIGH | doors discard the payment row's amount; screen prints planned `total_price` labeled 결제 금액 — a waived 0원 row opens a non-zero 「결제 금액」 | **FIX**: total label becomes phase-aware (결제 금액 only when `paid`; 청구 금액 for collect_*; 예상 요금 otherwise). Full Ⓒ1 per-payment receipt (actual amount rows) stays future work, noted in-file |
| F2 | payphase.ts:187 | HIGH | collection consulted only for completed/refund_pending — cancelled bookings with minted cancel-fee rows render quiet 「취소된 예약이에요」 | **FIX**: `collectionMatters` widened to cancelled_owner/cancelled_runner/expired; shared fold; `disputed` deliberately excluded (incident surface owns its money). payphase tests extended in-slice |
| F3 | club/run/[sid].tsx:125 | HIGH | in-flight board response race across sid change: A resolving after B overwrites B's board (publishing is guarded by boardFor, but A's dogs drive actions under B's sid) | **FIX**: drop stale responses — capture request sid, ignore resolution when it no longer matches |
| F4 | club/console/[sid].tsx:145 | HIGH | 0144 authorizes host OR backup, but the console bounces non-hosts and the shell hides its door — a backup can never invoke 러닝 종료 | **FIX**: console admits `iAmBackup` in a reduced backup mode (board read + 러닝 종료 + result only — every other console action is strict-host server-side and would be a dead button); shell console door widens to backup with a labeled variant |
| F5 | chat.tsx:67 | MED | bid change on a mounted route: old ctx/msgs union into the new thread | **FIX**: reset ctx/msgs/link/pollErr/state at the top of the thread-prep effect |
| F6 | club/console/[sid].tsx:286 | MED | 러닝 종료 preview names only active&unfrozen; the RPC loops every delegated booking — the confirm under-names what the tap reports | **FIX**: preview enumerates the RPC population (bookingId != null); confirm copy states that non-running delegations are reported too |
| F7 | club/console/[sid].tsx:94 | MED | endResult not sid-scoped and never invalidated — session A's report can render under B | **FIX**: store {sid, result}; render only on matching sid; timestamp label from result.at via kst |
| F8 | club/console/[sid].tsx:73 | MED | `error` reason copy promises a per-dog retry that doesn't exist | **FIX**: copy → 다시 시도해주세요 (pack-wide truth) |
| F9 | charge-states.tsx:87 | MED | PaymentRow a11y label replaces content but omits amount/status/refund/decline | **FIX**: label composed from title+amount+status(+환불) |
| F10 | chat.tsx:174 (+ :158 photo) | MED | send/refetch share one catch — committed send + failed refetch → 「전송 실패」 + restored input → duplicate on retry | **FIX**: split catches; refetch failure sets pollErr, never claims send failure |
| F11 | club/run/[sid].tsx:123 | LOW | retry after board failure renders 'denied' while actually loading (boardLoaded stays true) — pre-existing, surfaced by this slice | **FIX**: reset boardLoaded at load() start |
| F12 | club/console/[sid].tsx:373 | LOW | `not_signed_in` raise untranslated | **FIX**: map arm added |
| F13 | owner/pay.tsx:95 | LOW | whenLabel's catch falls back to device-timezone `toLocaleString` | **FIX**: converge on kst.ts (kstDateLabel + kstAmPm), Intl dropped entirely |

Verified-clean by the same review (kept for the record): pay's two-coral-rule count holds in every
state; map import stays lazy; map-less deep links render an honest terminal; merge dedup stable;
all SQL reason tokens rendered; the widened RPC-contracts regex alters no existing captures;
frozen lockfile carries transitive @types/node.

Round 3 (queued): these 13 fixes + U4b (set_backup/assume_host) + the 예약 규칙 editor — none of
which round 2's export contained.
