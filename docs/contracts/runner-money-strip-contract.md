# Runner-money strip — contract v2

**Ruling (Sean, 2026-08-24, verbatim):** "For runner money, don't show them the 수수료. I don't
think we should be showing them the calcuations ever; only show the final profit per run; keep
the margin a secret. You can show the expected profit at first per run next to how far away the
starting point is and how long the run is and how long it will take total."

**v2, 2026-08-25:** v1 (`f6ed2cf`) went through two blind adversarial reviews (independent Opus
+ fresh codex voice, neither shown authoring reasoning). Both returned **FIX-FIRST**: v1's
diagnosis held, but its mechanism handed the rate back in three of its own §2 objects, its seal
statement was a measured no-op in this schema, and one *shipped* RPC already answers the rate in
a single call. Every finding below is folded with its evidence re-verified at source by the
author. Reviewer tags: [O#] = Opus finding, [X#] = codex finding.

## 0. The invariant, stated honestly

> **No runner-facing surface — response, table read, view row, RPC return, stored payload, push
> body, bundle constant, or rendered pixel — names or carries the platform commission rate, the
> commission fee amount, or the runner-settlement gross (as a total or as a component set).**
> Runner-facing settlement money is NET-denominated only.

**Named residual CLASS (not closable at the read layer):** owner-side pricing is public and
km-linear (`club_fare(km) = 9900 + round(km×3000)`, owner fare columns on the runner's own
bookings, marketing copy), and runner pay is a fixed share of that line — so ANY honest net
value beside ANY public gross point yields the rate by one or two divisions [O-F3/F4/F5,
X-№4/№5]. This slice removes every surface that *names* the margin and every *gratuitous* gross
disclosure it can reach, and it narrows the residual (club_fare's direct oracle is revoked,
§2G′), but the class closes only by decoupling runner net from the public linear price — a
PRICING decision, queued for Sean, explicitly not assumed here.

**Second named residual [O-F4, X-№5]:** `bookings party read` (0002:92) gives the assigned
runner table-wide SELECT on their own bookings — `base_fare`, `distance_fare`, `addon_fare`,
`min_fare`, priced `addons` jsonb — and `bookings` is in the realtime publication (0008:14).
Closing this is a table-wide revoke + whitelist on the busiest table in the product, touching
the OWNER client's reads too. That is its own slice with its own deploy-order story; doing it
as a §G side-effect would be exactly the unreviewed blast radius this repo's laws exist to
prevent. **Queued as the follow-up slice; until it lands, the §0 invariant holds for named
margin/fee/gross fields and for every surface this slice touches, not for the booking row.**

**Carve-outs (deliberate, not omissions) [X-№14]:**
- The statutory **3.3% withholding** stays visible (earnings.tsx:129 keeps it deliberately —
  tax law, not margin).
- **Cancellation-compensation disclosures to the runner** stay: money the runner RECEIVES,
  with its stated basis (`transition-booking/cancel_owner.ts:123-130`'s 「취소 수수료의 절반인
  X원」). A runner must know why they were paid; the cancel-fee split is Sean-ruled product
  copy (0066/0117 territory), not the commission margin.
- **`payouts`** (0001:285: gross/tax/net, runner self-read at 0002:126) has NO writer today
  (0115:282 confirms). Dormant §0-shaped surface, named here so its first writer inherits the
  question instead of the default [O-F7]. Out of scope until then.

## 1. Leak channels (all verified at line; v1's four + three the reviews added)

| # | Channel | Evidence | What leaks |
|---|---|---|---|
| C1 | `runners.commission_rate` PostgREST reads | api.ts:939 (estimate cache) · api.ts:1867 (`MyRunnerCert.commissionRate`, zero render consumers) | the rate |
| C2 | `ledger_items` component columns | api.ts:1351, 2588, 2661 (+ dead 2622) select all six components and subtract client-side | fee; rate by ÷ |
| C3 | `settle-run` response | `SettleResult { net, gross, fee, guarantee … }` api.ts:1288 | rate = fee÷gross exact |
| C4 | Bundle constants + math | theme.ts:229 `commission: 0.33` · gross formula in `estimatedPayout` (api.ts:861) and `payoutFor` (store.ts:28) · dead mock `ledger`/`payoutInfo` exports with hardcoded fees (store.ts:247-259) | rate literal + formula |
| C5 | **`club_incident_settle_quote`** [O-F1, X-№2] | 0116:414 returns `(refund, runner_gross, runner_fee, runner_net, …)`; party gate 0116:437 admits `b.runner_id = auth.uid()`; `grant … to authenticated` 0116:481; **no state gate**; client exposes all three at api.ts:3820-3829 | exact rate, one RPC, TODAY |
| C6 | **Incident evidence persistence** [X-№3] | 0080:1034-1045 writes `runnerGross`/`runnerNet` into `club_incident_evidence` payload and returns both (0080:1079); 0052:375-398 evidence read policy admits the runner as party | fee = gross−net, incl. HISTORICAL rows after any strip |
| C7 | **`club_fare()` direct oracle** [X-№4, O-F5] | 0043:14 formula; 0081:284 `grant execute … to authenticated`; zero client-side callers (verified — fares reach clients via `club_delegation_board`) | PER_KM and full gross base by RPC |

## 2. Server objects (one migration; number + suite two-sided from remote tip at write time)

Discipline for every function here [X-№13]: SECURITY DEFINER · `set search_path = public,
pg_temp` **in the body** (98 H1 — and note 0027's current bodies carry bare `public`, no
`pg_temp` [O-F11]) · **explicit `auth.uid() is null` rejection before anything else** · party
gates written `coalesce(…, false)` / `is distinct from` (the 0116:425 NOT(NULL) fail-open is
the measured trap) · party gate before state gate · flat whitelisted returns · `revoke … from
public, anon` + `grant execute … to authenticated` explicitly (never default PUBLIC EXECUTE) ·
the suite proves the party selector is `auth.uid()`, never `current_user` (0111:27 — postgres
inside a definer).

- **§A `my_ledger_rows()`** → `table(id, booking_id, net int, cancel_comp boolean, km numeric
  NULL, dog_name text, created_at)`. Replaces `fetchLedger` (api.ts:2661). `net` = the six-term
  sum, server-side. **`cancel_comp` is server-computed (no `runs` row ⇔ true) and `km` is NULL
  on those rows** — the earnings screen's cancellation label (earnings.tsx:173) survives, and
  the 「5km printed for a run that never happened」 honesty fix is preserved, not reverted
  [O-F15, X-№9]. Reproduces `order by created_at desc limit 30`.
- **§B `my_week_stats()`** → one row `(week_net bigint, week_runs int NULL, week_km numeric
  NULL)`. Replaces `fetchRunnerWeekStats` (api.ts:2588) ONLY — **`fetchLedgerMonth` has zero
  callers (home.tsx:45's own comment) and is DELETED, not ported** [X-№15]. Semantics pinned
  exactly as the client computes them today [O-F16, X-№11]: `week_net` includes
  compensation-only rows; `week_runs` counts only rows WITH a `runs` row; `week_km` = sum of
  `runs.actual_km`, 1-decimal rounded; runs/km go NULL together on lookup failure (net does
  not). Week boundary: **KST Monday 00:00**, SQL per the 0022:15 precedent —
  `date_trunc('week', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul'` — with pins
  on rows straddling the boundary [X-№12]. `total_net` is NOT here: `my_ledger_total` (§F)
  stays the single canonical source.
- **§C `my_booking_nets(p_bookings uuid[])`** → `table(booking_id, net int)` — settled actuals
  from the ledger. Replaces the netByBooking read (api.ts:1351).
- **§D two NEW runner request views** — `runner_open_requests` and `my_directed_requests`
  [O-F3, X-№6]. NEW objects, because `create or replace` can only append columns and the old
  view carries `base_fare/distance_fare/addon_fare`, which beside `expected_net` yield the rate
  from one response body (r = 1 − Δnet/Δdistance_fare). Both views: **no owner-fare columns**,
  flat dog/route/schedule columns as the mappers need, plus `expected_net int` computed via an
  **inline scalar subquery** on `runners.commission_rate` with the 0.33 no-row fallback —
  NEVER a callable helper function [O-F2, X-№1: view bodies do not shield function EXECUTE
  (`is_active_runner`'s ungranted-but-works state at 0004:4/0056:68 proves the mechanics), so
  any helper the view could call, a client could call]. Table access inside the definer-owned
  view is checked as the view OWNER, so the subquery survives §G. `expected_net` =
  `round((9900 + round(km*3000) + coalesce(addon_fare,0)) * (1 − rate))`. ACLs on BOTH views,
  explicitly [O-F17, X-№8]: `revoke select from public, anon` (0107:98 — default privileges
  hand anon SELECT on new views) · `revoke insert, update, delete from public, anon,
  authenticated` (0112's measured definer-view DML trap) · `grant select to authenticated`.
  The OLD `marketplace_open_requests` view keeps existing for any non-runner consumer but
  loses its purpose; its grants are left untouched this slice (owner surfaces may read it;
  auditing that is the bookings-slice's job — §0 residual 2).
- **§E `my_run_net_coeffs(p_bookings uuid[])`** → `table(booking_id, expected_net int,
  net_base int, net_per_km int)`, party-gated to the caller being `runner_id` on each row
  (rows the caller isn't party to are OMITTED, not errored). Named object — v1 said "the
  accepted-jobs surface" and named nothing [O-F13, X-№10]. Serves: the two jobs mappers
  (api.ts:1369, 1410), and run.tsx's live ticker on BOTH entry paths — fresh start AND
  reload/deep-link (store.ts:8 persists only `bookingId`; `fetchMeetupInfo` has no
  coefficients — the reload path calls this RPC too). **Failure behavior (honesty law): if the
  coeffs fetch fails mid-run, the ticker renders the placeholder '—' with a retry, never 0 and
  never a fabricated rate** [X-№10]. Drift disclosure [O-F14]: the ticker's
  `net_base + km*net_per_km` omits addons (up to ≈₩10k net on max-addon bookings) and the
  guarantee arm — it is the SAME omission the shipped ticker makes today (store.ts:27 takes no
  addon), every surface labels it 「예상」, and settle remains the only real number. No ≤₩2
  claim: the ROUNDING term is <₩1, the estimate-vs-settle gap is unbounded by design and
  already shipped.
- **§F `my_ledger_total` (0027) → DEFINER**, same summing semantics, `auth.uid()` null-reject +
  gate, **`set search_path = public, pg_temp` written into the body** (0027 currently has bare
  `public`; create-or-replace resets ALTER-applied config — the exact 98 H1 trap) [O-F11].
  Consumer correction from v1: earnings.tsx's 누적 total is the caller; delete-account-sheet
  calls `fetchLedger()`, not this [X-№15]. `create or replace` (grant preservation).
- **§G the seal — the 0088/0107 two-step, NOT bare column revokes** [O-F8, X-№7: a column
  revoke is a measured no-op while table-wide SELECT stands (0107:75's own text, 0098 M4), and
  neither `runners` nor `ledger_items` has ever been table-revoked]. So:
  1. `revoke select on runners from public, anon, authenticated;` then
     `grant select (profile_id, tier, bio, specialties, photos, avg_pace_sec_per_km,
     total_runs, total_km, respond_rate_pct, trainer_certified, online) on runners to
     authenticated;` — the eleven-column storefront whitelist enumerated from the measured
     client read set (api.ts:809, 1037, 1840, 2079, 2099, 2265) [O-F9]. `commission_rate` is
     exactly the column that does not return. anon gets nothing (measured: no anon runner
     read).
  2. `revoke select on ledger_items from public, anon, authenticated;` — NO re-grant: after
     §A/§B/§C/§F every legitimate client read is an RPC. (v1's "keeps existence probes alive"
     rationale was false — delete-account's probe is `fetchLedger()` → §A, and the server-side
     reads are service_role/definer [O-F12].)
  3. VERIFY block: `has_column_privilege` **negatives** (commission_rate, all six ledger
     components) AND **positives** (each whitelisted column) — refuse to apply otherwise
     (0111 M7: a re-grant becomes a failed deploy).
  4. The six `runners(profiles(name))`-style embeds (api.ts:1231, 2037, 2910, 2925, 4213,
     4307) are MEASURED against the whitelist in the suite, not assumed [O-F10].
- **§G′ oracle revoke [X-№4]:** `revoke execute on function club_fare(numeric) from
  authenticated;` (keep service_role/definer callers — `club_delegation_board` runs as owner
  and is unaffected; verified zero client-side `rpc('club_fare')` callers). Closes the
  one-call PER_KM oracle; the linear-price residual class remains as named in §0.
- **§H incident money [O-F1, X-№2, X-№3]:**
  1. `club_incident_settle_quote`: keep the signature; **when the caller's ONLY qualifying
     party role is the booking's runner, `runner_gross` and `runner_fee` return NULL**
     (runner_net stays). Host/backup-host/case-owner/opener keep the full readout — they are
     the settling side. Pinned both ways.
  2. `club_incident_settle` (0080): stop writing `runnerGross` into the evidence payload
     going forward, and **UPDATE existing `club_incident_evidence` rows to strip the
     `runnerGross` key** (`runnerNet` stays; pre-launch row count is small and the settling
     side's canonical record is the fee ledger, not the evidence jsonb). Its RETURN drops
     `runnerGross` too (the caller is the settling side, but the value is derivable from the
     fee ledger they already read — returning it buys nothing and keeps a gross on a wire).
  3. Client: api.ts:3820-3829 stops surfacing gross/fee.

## 3. Edge function (deno half)

`settle-run` response shrinks to `{ net, total_runs, drop }` — `gross`, `fee`, `guarantee`
leave. Server-side reads of `commission_rate` (handler.ts:107, service_role) untouched. Deno
absence pins on the response keys.

## 4. Client swap (atomic with §G — the 0088 law)

- Delete: `myCommissionRate` + `_commissionRate`, `estimatedPayout`, `fetchLedgerMonth` (dead),
  store.ts mock `ledger`/`ledgerNet`/`payoutInfo` exports (dead + fee-bearing),
  `theme.ts pricing.commission`, `MyRunnerCert.commissionRate`, `payoutFor`'s
  `(1 − commission)` math. **`pricing.perKm` STAYS — four owner-side consumers
  (owner/request.tsx:326, 1247, 1390; store.ts:319); `runnerCompBase` goes to zero consumers
  and leaves** [O-F20].
- Swap: the two request mappers → §D views · api.ts:1351 → §C · fetchRunnerWeekStats → §B ·
  fetchLedger → §A (keeping `cancelComp`) · jobs mappers + run.tsx ticker (both entry paths) →
  §E with the '—' failure state · `SettleResult` → `{net, total_runs, drop}` · incident quote
  consumer → nulls tolerated.
- Deploy order (0088 class): migration + client land on trunk in ONE branch; deploy = `db push`
  + binary together; §G never deploys before the swapped client ships. 0 phone builds today;
  law recorded for when that changes.

## 5. Club shape (for spec v2 — unchanged from v1 except the helper is gone)

Club runner money surfaces are net-only by construction from birth: server-computed
`expected_net`/`net` via the §D inline-subquery mechanism (NOT a callable helper — [O-F2]
applies to club too), never a component set, gross, fee, or percentage. The 0118 fee ladder is
owner money, out of secrecy scope. Spec v2 cites this section.

## 6. Not in this slice (each named deliberately — 0073/0075)

- The `bookings`/`runs` gross-input surface (§0 residual 2) — its own follow-up slice.
- The pricing decoupling that would close the residual class — Sean's product decision.
- `payouts` (dormant, no writer), 3.3% withholding, cancellation-comp disclosures — carve-outs.
- No settlement amount, ledger row, or money movement changes. No owner-facing money changes.
- Server-side margin knowledge (settle-run, 0101, 0072-as-definer) — untouched by design.
- No claim of binary obfuscation.

## 7. Suite + mutation plan

All pins state their proposition in words; pin and mutation name the same observable (v5
lesson). Party gates both ways incl. **null-UID rejection** and an `auth.uid()`-vs-
`current_user` proof arm [X-№13] · flat-shape + absence pins (no fee/gross/component keys) ·
net arithmetic vs postgres-computed truth · `cancel_comp`/null-km pin [O-F15] · §B semantics
pins: comp-row inclusion in net, exclusion from runs-count, actual-km sum, the KST Monday
boundary rows [X-№11/12] · `expected_net` formula for a known rate AND the 0.33 no-row
fallback · §D view ACL pins (anon no-SELECT, no DML — independent of `is_insertable_into`)
[X-№8] · §G positive AND negative `has_column_privilege` pins + the six embed-survival probes
[O-F10] · §G′ club_fare EXECUTE negative · §H both-arms pins (runner sees NULL gross/fee;
host sees values; evidence payload has no `runnerGross` key — historical rows included) ·
98 H1 covers §F's search_path schema-wide · **a schema-wide sweep pin** [O-F19]: every
function with authenticated EXECUTE whose OUT columns match `fee|gross|commission|rate` is
enumerated against a comment-justified allowlist (post-§H that allowlist is
`club_incident_settle_quote` alone, justified by its host arm). Mutations: drop a party gate →
its pin alone · re-grant `commission_rate` / a ledger component → VERIFY refusal (executed as
a mutation) + ACL pin · drift a §D constant → formula pin · revert §F to invoker → definer
pin · restore `runnerGross` to quote's runner arm / evidence → §H pins · re-grant club_fare →
§G′ pin · add `fee` back to settle response → deno absence pin.

## 8. Review path

This v2 goes back to one fresh blind voice (findings-fold verification, cheaper than round 1)
before implementation. Then: implement → measure (harness + deno + three app gates) → mutation
battery → land. DONE test: a reviewer with a post-slice client and a runner JWT cannot name
the rate through any channel other than the two §0 named residuals — reaching it ONLY via
public-linear-price arithmetic or the bookings-row gross inputs confirms a residual, not a
defeat. §E's `net_per_km` is the sharpest edge of residual 1 and is accepted as such
explicitly [O-F14].
