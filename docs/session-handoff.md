# SESSION HANDOFF — 2026-08-12 (FINAL, post-midnight) · redesign-v4 @ 4afa3f5

**Opener for the next session: "read docs/session-handoff.md fully, then continue."**

Companion docs, in reading order:
1. `docs/plans/payments-toss-plan.md` — **THE money plan.** Read §0-bis (post-pay +
   price-invisibility + final screen inventory + pricing) then §0-ter (settle-charge
   machine + 15 absorbed adversarial findings). §2/§3 below them = the FALLBACK widget
   flow (built, merged, demoted).
2. `TODOS.md` — top entries are tonight's.
3. `docs/labs/` — 4 labs; picks still open (see §9).
4. The abandoned token design (reasoning archive only):
   `~/.gstack/projects/seankookim-daengrun/sean-claude-token-payments-model-891c11-design-20260812-134138.md`
5. `docs/session-handoff-archive-20260812-am.md` — the morning session.

## 1. Status table

| System | State | Provenance |
|---|---|---|
| `redesign-v4` @ `4afa3f5` | BOTH agent branches merged (835e119 backend, 6c85a85 SDK); pricing decoupled (eda0560); 0077 guard (d89af7c); eng pass committed (4afa3f5). Untracked strays (`.agents/`, `docs/b2b-revenue.md`…) = other sessions', untouched | [verified-now] |
| SQL harness | **388 pass / 0 fail** on the MERGED tree (`cd supabase/tests && PATH=/opt/homebrew/opt/postgresql@16/bin:$PATH LC_ALL=C bash harness.sh`) | [verified-now] |
| Deno tests | **35/35** (`deno test -A supabase/functions/_test/`; deno 2.9.5 in session scratchpad — reinstall if gone) | [verified-now] |
| Client tsc | **clean** after `npm install` picked up the merged lockfile (SDK package present) | [verified-now] |
| Prod DB | on 0074; 0075 pushed-unwired; **0076/0077 NOT pushed** (push = Sean-only, harness-gated) | [from-history — verify `supabase migration list`] |
| Real payments | zero ever charged; pay.tsx pilot copy still TRUE | [verified-now] |
| Filings | 사업자등록 NOT filed — the critical path | [from-history] |
| SDK runtime | install/prebuild/pod/tsc clean; **no device build, no real TEST-key payment ever executed** | [reported — agent evidence, unrun on device] |

## 2. THE MODEL (final form — memorize this paragraph)

Per-run, post-pay, invisible. Card linked once (Toss 빌링키; 자동결제 심사 in the same
application). Price appears exactly once — the unchanged request screen. Booking:
card-linked owners flow create→…→matching in one server request (payment_hold transient;
CAS failure = compensating delete). Run happens; 귀가 is custody (meter cut at run-stop).
`settle_run_tx` commits FIRST (runner always paid); the billing charge follows on the
booking's FROZEN numbers with basis `min(actual, planned)` — owner-caused ends charge
planned; runner_personal waives the base; dog_condition/incident = Sean's open G1 call
(provisional: charge nothing pending review). Decline → in-place retry ladder
(0/+1h/+24h, same order_id) → derived debt state (anchored on runs/ledger existence) →
account lock (create-booking-hold + recurring cron both gate). Money UI: on-demand
(설정 결제 관리 + booking-detail 결제 내역 — MUST ship with the money-free flow) or
on-exception only. **Tokens/levels/bundles/적립: ABANDONED.** Pricing:
`ownerBaseFare 7,900 / runnerCompBase 9,900` decoupled (2km = 13,900; margin 23.4→29.5%;
never "unify" the constants — comments in ctx.ts/theme.ts say why).

## 3. What shipped tonight (all on redesign-v4, all gate-verified)

`d89af7c` 0077 double-belt + 114 suite (mutation 4/4) · `2ba322a` labs + banners + first
handoff · `aba0d38`/`b2186e5` TODOS + abandonment · `eda0560` pricing split (8 call sites
by side, tsc-forced completeness) · `835e119` merge: intent machine + confirm-payment +
Deno infra (now the FALLBACK/card-link rail) · `6c85a85` merge: RN SDK scaffold behind
`TOSS_ENABLED=false` + 39-scheme plugin · `4afa3f5` §0-ter eng pass + 15 findings absorbed.

## 4–5. Doctrines & norms (unchanged from the earlier handoff; the additions)

All prior doctrines stand (honesty law, money-path adversarial cycles, 클라 불신, 0077
caller doctrine, style freeze). NEW tonight: **owner basis ceiling** (never charge above
quote), **frozen-numbers charging** (never live constants), **billing intents never
auto-fail while stale**, **settlement never waits on collection**. Sean's norms: picks by
number; kills with one taste sentence; reverses fast on evidence (D1 B→C in an hour;
dual-threshold same day); brings adversarial critiques of your own work — welcome them.

## 6. Decisions with WHY (tonight's layer; full chain in `gstack-decision-search`)

Token model PARKED→**ABANDONED** ("abandon the token and whatever") — invisibility
achieves its psychology without it · only NEW screens = card-register; receipts =
extension; everything else existing surfaces; km dial STAYS; level system dead ·
post-pay basis rules (see §2) · pricing decoupled — the cut lands on platform margin,
never the runner pitch · Ⓛ③ 산책의 반대말 picked with 우리 {dogName} personalization ·
time is never a stopper (routes loop home), one-directional encourager only · REFUSALS:
no silent runner-pay cut; no auto-failing dispatched billing intents; no charging above
the quoted price.

## 7. Architecture ordering constraints (the expensive-to-relearn list)

설정 결제 관리 ships WITH the money-free flow (else concealment) · 0060 e_match +
0072 refund copy FIXED at cutover (they promise refunds of never-taken money — the NEW
go-live gate, replacing the vacuous refund gate) · cancel-fee machine + en-route runner
comp ledger path before real charges · pay.tsx:334 deletion only after sandbox matrix ·
recurring cron debt-gate lands WITH the lock (else the exposure bound is false) ·
bookings-anchored settled-without-payments sweep is THE invariant of the charge slice.

## 8. Verification commands

Read-only: the three gates in §1 · `gstack-decision-search --recent 10` ·
`git log --oneline -8`. Destructive/Sean-only: `supabase db push` (0076+0077 would go
live) · `expo prebuild` · any push.

## 9. Pending on Sean

**Ops:** ① 사업자등록 → 통신판매업 → Toss (일반 + 자동결제 심사 one application);
② dashboard: TEST keys + variantKey 카드/간편결제-only (가상계좌 OFF); ③ review + push
redesign-v4 when ready (harness-gated).
**Decisions:** ① lab picks — Ⓡ①②③ + Ⓖ rule · Ⓛ③ spec-plate graft + ₩/원 (D-1/D-2 pay
picks DIED with the request-screen freeze); ② G1 abort-charge basis for
dog_condition/incident (provisional charge-nothing recorded); ③ D-3 silent-charge users
(accept vs monthly summary — counsel); ④ OPS_PROFILE_ID env vs admin role;
⑤ DESIGN.md §3b reconcile + legal-footer 12pt ruling.

## 10. Next prompts (exact openers)

- **Build the charge slice** (the main line, buildable NOW with TEST keys):
  "read docs/session-handoff.md fully, then build payments-toss-plan §0-ter as its own
  slice: 0078 migration (sweep fn, debt derivation, failed-index, dispatched_at
  convention), settle-run charge branch, recurring-cron gates, cancel-fee machine,
  0060/0072 copy fixes, 설정 결제 관리 + booking-detail 결제 내역 screens, Deno tests for
  every §0-ter rule, adversarial round 2, harness green."
- **Device-verify the SDK**: "read docs/session-handoff.md; run the A3 device build:
  expo run:ios with TEST keys, execute the §4-2 sandbox matrix through pay-lab, report
  the verdict." (needs Toss TEST keys first)
- **After Sean's lab picks**: "read docs/session-handoff.md; implement the picked lab
  variants: card-register screens (Ⓐ approved), record-card restyle, 귀가 state on
  live.tsx, run-end confirm + return handoff."
- **Cleanup (low priority)**: "drop the unwired km ledger (0075) with its own migration
  + suite retirement, per the abandonment decision."

## 11. Known-good — do not "fix"

Everything in the earlier handoff's list, plus: the merged intent machine's cancel-failed
distinct copy · the decoupled constants (never unify) · the transient payment_hold reuse
(zero map delta by design) · e_hold's silence for WIDGET-flow holds (W7) — card-linked
strays are prevented by compensating delete, not by breaking W7.
