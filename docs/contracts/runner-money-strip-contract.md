# Runner-money strip — contract

**Ruling (Sean, 2026-08-24, verbatim):** "For runner money, don't show them the 수수료. I don't
think we should be showing them the calcuations ever; only show the final profit per run; keep
the margin a secret. You can show the expected profit at first per run next to how far away the
starting point is and how long the run is and how long it will take total."

**Status of this document:** contract, pre-implementation. The display half was already shipped
by ui6 (earnings.tsx breakdown removed, 「수수료 제외」 wording retired, rate never printed).
This slice is the DATA half: today the wire and the bundle still carry everything needed to
reconstruct the margin. Display-side hiding is not secrecy.

## 0. The invariant (what "secret" means, precisely)

> **No runner-facing response, table read, or client-bundle constant may contain the commission
> rate, the fee amount, any gross-side amount, or any component set from which fee or rate is
> recoverable by arithmetic.** Runner-facing money is NET-denominated only.

"Recoverable by arithmetic" is the load-bearing clause — ui6's earnings note derived it first:
components beside a net hand back the fee by subtraction (fee = Σcomponents − net), and fee
beside a gross hands back the rate (fee ÷ gross). So the strip removes **whole component sets**,
not just the fee field. Owner-side money is untouched: owners see owner pricing (base_fare 7,900
world), which is different money from the runner settlement basis (9,900 + 3,000/km world), and
the rate is not recoverable across the two without the internal gross formula — which this
slice also removes from the bundle.

## 1. The four measured leak channels (scout 2026-08-25, all verified at line)

| # | Channel | Today | Recoverable |
|---|---|---|---|
| C1 | `runners.commission_rate` via PostgREST | `api.ts:939` (`myCommissionRate` session cache, feeds every request-card estimate) · `api.ts:1867` (`MyRunnerCert.commissionRate` — fetched, **zero render consumers**, dead field) | the rate itself |
| C2 | `ledger_items` component columns via PostgREST | 4 sites: `api.ts:~1350` (netByBooking), `fetchRunnerWeekStats` (~2588), `fetchLedgerMonth` (~2621), `fetchLedger` (~2661) — each selects `base, distance_pay, addon_pay, tip, remaining_guarantee, platform_fee` and subtracts client-side | fee directly; rate via fee÷(Σ−…) |
| C3 | `settle-run` edge response | `SettleResult { net, gross, fee, guarantee, … }` (`api.ts:1289`) | rate = fee ÷ gross, exact |
| C4 | Client bundle constants + math | `theme.ts:229` `pricing.commission: 0.33` · `pricing.runnerCompBase/perKm` gross math in `estimatedPayout` (`api.ts:861`) and `store.ts:28` `runnerPayout`/`payoutFor` (live run ticker) | rate literal + full gross formula |

## 2. Server objects (one migration, number two-sided from remote tip at write time)

All functions: SECURITY DEFINER · `set search_path = public, pg_temp` **in the body** (98 H1) ·
party gate (`auth.uid()`) before any state logic · flat whitelisted returns · revoke PUBLIC/anon,
grant authenticated only where the caller is the runner themselves.

- **§A `my_ledger_rows()`** → `table(id, booking_id, net int, created_at, km, dog_name)`.
  Replaces `fetchLedger`'s direct read. `net = base + distance_pay + addon_pay + tip +
  coalesce(remaining_guarantee,0) − platform_fee`, computed server-side; components never leave.
- **§B `my_net_summary()`** → one flat row `(week_net, week_runs, week_km, month_net,
  total_net)`. Replaces `fetchRunnerWeekStats` + `fetchLedgerMonth` (and collapses two of the
  react-doctor "sequential independent awaits" into one round trip). Week/month boundaries: KST,
  same arithmetic the two client functions use today — captured as literals in the suite, not
  re-derived.
- **§C `my_net_by_booking(p_bookings uuid[])`** → `table(booking_id, net)`. Replaces the
  netByBooking read at api.ts:~1350.
- **§D expected net on the two request surfaces.**
  `marketplace_open_requests` (0042 choke-point view) gains `expected_net int`:
  `round((RUNNER_COMP_BASE + round(km*PER_KM) + coalesce(addon_fare,0)) * (1 −
  rate(auth.uid())))` where `rate()` is a small STABLE definer helper reading the caller's
  `runners.commission_rate` with the 0059 fallback 0.33 — the helper's EXECUTE is granted to
  authenticated but it returns nothing; it exists so the VIEW can price per-caller without the
  rate appearing in any output column. View changes via `create or replace` ONLY (grant
  preservation law). A new sibling view **`my_directed_requests`** flattens the directed leg
  (today a raw `bookings` read with `REQ_SELECT` + dog embeds) with the same `expected_net`,
  filtered `runner_id = auth.uid() and status = 'runner_pending'` — this also retires the
  client-side PGRST201 two-FK trap for that leg.
- **§E net-denominated live estimate.** The accepted-jobs surface additionally carries
  `net_base int` and `net_per_km int` (each = the gross constant pre-multiplied by
  `(1 − rate)`, rounded). run.tsx's live ticker becomes `net_base + km * net_per_km` — the
  client keeps doing live math but only ever holds net-side numbers. Accepted drift vs the
  settle-time number: rounding only (≤ ₩2 per component); every surface already labels this
  「예상」, and settle remains the only real number.
- **§F `my_ledger_total` (0027) converts invoker → DEFINER** in-slice, same body semantics,
  `auth.uid()` gate, in-body search_path. Reason: it is invoker-rights and sums the component
  columns, so §G's revoke would break it for exactly its legitimate caller. `create or replace`
  (grant preservation). Its existing consumers (delete-account flow, earnings) see no shape
  change.
- **§G the seal — LAST section of the migration, after every reader above it exists.**
  Column-level `revoke select (commission_rate) on runners from authenticated, anon` ·
  `revoke select (base, distance_pay, addon_pay, tip, remaining_guarantee, platform_fee) on
  ledger_items from authenticated, anon` (id/booking_id/created_at stay readable — harmless and
  keeps existence probes like delete-account's alive). VERIFY block in the migration asserts the
  post-state with `has_column_privilege` negatives and REFUSES to apply otherwise (0111 M7
  pattern: a re-grant becomes a failed deploy, not a red harness).

## 3. Edge function (deno half)

`settle-run` response shrinks to `{ net, total_runs, drop }` — `gross`, `fee`, `guarantee`
leave the wire. (`guarantee` is a component; net beside components is subtraction — §0.)
Server-side reads of `commission_rate` as service_role (handler.ts:107) are untouched: the
server may know the margin; the runner's client may not. Deno pins assert the response body has
NO `fee`/`gross`/`guarantee` keys (absence pins, the 0088-reverse direction).

## 4. Client swap (atomic with §G — the 0088 law)

- `myCommissionRate`, `_commissionRate` cache, `estimatedPayout` — **deleted**. Mappers read
  `expected_net` from the views. `MyRunnerCert` drops `commissionRate` (dead field, C1).
- The four C2 sites → §A/§B/§C RPCs. `SettleResult` → `{ net, total_runs, drop }`.
- `theme.ts pricing.commission` and `store.ts runnerPayout`'s `(1 − commission)` math —
  **deleted**; `payoutFor` reads `net_base`/`net_per_km` (§E). `runnerCompBase`/`perKm` leave
  the bundle if no owner-side consumer remains (owner pricing uses its own constants; verify at
  impl).
- store.ts's dead mock exports (`ledger`, `ledgerNet`, `payoutInfo` — zero consumers, hardcoded
  fee rows) are deleted in-slice: they encode the margin in the bundle and violate the
  no-fake-data law besides.

**Deploy order (0088 class, stated as law):** the migration and the client swap land on trunk in
ONE branch. Deploy = `db push` + new binary together; a binary older than §G that still names
`commission_rate`/`platform_fee` in a select gets a whole-request 403 the moment §G applies —
with 0 phone builds today the exposure is nil, but the law is recorded for the day it isn't.
**§G must never deploy before the swapped client ships** — same class as 0119's deploy-order
law, same checklist.

## 5. Club shape (for spec v2 — contract only, no build here)

Club runner money surfaces (crew-runner cards, session pay lines) are **net-only by
construction from birth**: whatever RPC serves them returns `expected_net` / `net` computed
server-side by the same §D/§E mechanism (the `rate()` helper is reusable), and NEVER a
component set, gross, fee, or percentage. Spec v2 §money should cite this section rather than
invent a parallel shape. The 0118 fee ladder (owner-side cancel fees) is owner money and out of
scope of the secrecy invariant.

## 6. What this slice does NOT do (unstated scope reads as a seal — 0073/0075)

- No change to any settlement AMOUNT, ledger row, or money movement — read-shapes and ACLs only.
- No change to owner-facing money anywhere.
- Does not remove `commission_rate` from the schema or from server-side readers
  (settle-run/0101/0072 read on as service_role/definers).
- Does not touch 0117/0118/0119 surfaces, the mirror branch, or club money paths.
- Does not claim the bundle is reverse-engineering-proof — the invariant is that the margin is
  not present, not that the binary is obfuscated.

## 7. Suite + mutation plan (numbers resolved at write time, two-sided)

New suite pins, each mutation-verified: party gates both ways on §A/§B/§C (mine vs another
runner's rows) · flat-shape pins asserting NO fee/gross/component key in any return · net
arithmetic pinned against postgres-computed ledger truth · `expected_net` formula pinned for a
known rate AND for the no-row fallback (0.33) · §F is definer with in-body search_path (98 H1
watches schema-wide; the definer conversion gets its own pin) · §G ACL pins via
`has_column_privilege` negatives · the two views remain non-insertable (D-22 sibling) · the
VERIFY block refuses a re-grant (0111 M7 pattern, executed as a mutation). Mutations: drop a
party gate → its pin alone; re-grant a sealed column → ACL pin + VERIFY refusal; drift a §D
constant → formula pin; revert §F to invoker → definer pin; add `fee` back to the settle
response → deno absence pin. Every pin states its proposition in words in a comment (the v5
unstated-scope lesson), and pin/mutation pairs name the same observable.

## 8. Review path

Money-path change → the standing adversarial cycle: this contract → blind review (fresh codex
voice + independent Opus reviewer, neither shown authoring reasoning) where reviewers EXECUTE
attacks (recover the rate from any post-strip surface) → implement → measure (harness + deno +
three app gates) → mutation battery → land. The strip is DONE when a reviewer with a
post-slice client and a runner JWT cannot name the rate.
