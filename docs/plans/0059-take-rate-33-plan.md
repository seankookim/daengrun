<!-- /autoplan restore point: /Users/sean/.gstack/projects/seankookim-daengrun/redesign-v4-autoplan-restore-20260806-130208.md -->
# 0059 — Take-rate 33% (Sean decision 2026-08-05)

Status: PLANNED · Sprint phase: Plan · Prereq: 0057 K-1 (commission_rate server-only) SHIPPED ✅

## Decision being implemented

Platform take-rate moves 20% → **33%**, flat for all runners (Sean, 2026-08-05, recorded in
handoff §2g). Deliberately its OWN migration, separate from the 0057/0058 security slices, so
settlement-arithmetic changes cannot mask a security regression. Unblocked by 0057 §6 (K-1):
`commission_rate` is now server-only — before K-1, any rate value was advisory because runners
could self-write it.

## Change surface (scouted 2026-08-06, all references verified)

### Server
1. **NEW `supabase/migrations/0059_take_rate_33.sql`**
   - `alter table runners alter column commission_rate set default 0.33;`
   - `update runners set commission_rate = 0.33;` — ALL existing rows (flat rate; the 0001:75
     comment's tier ladder 0.18/0.15 was never actually linked to tier — cert-funnel spec Q7).
   - Refresh the column comment to name the flat 33% policy + Sean decision date.
   - Interplay check: 0057 §6 `runner_protected_columns` trigger blocks
     `current_user in ('authenticated','anon')` only — migrations run as postgres → passes.
2. **`supabase/functions/settle-run/index.ts:23`** — fallback `?? 0.2` → `?? 0.33`
   (fires only when the runner row is missing; must not silently undercharge).
   ⚠ Adds `settle-run` to Sean's deploy queue (was only transition-booking).

### Client (same commit — Sean's explicit directive)
3. **`app/src/theme.ts:152`** — `pricing.commission: 0.2` → `0.33` (feeds store.ts:19 payout preview).
4. **`app/src/lib/api.ts:407`** — `?? 0.2` → `?? 0.33` (cached commission for previews).
5. **`app/src/lib/api.ts:1162`** — `?? 0.2` → `?? 0.33` (fetchMyRunnerCert display).

### Seeds (consistency; not applied by harness)
6. **`supabase/seed.sql:23-26`** — two runners at 0.20 → 0.33.
7. **`supabase/seed_demo_runners.sql:18-22`** — 0.18/0.20/0.20 → 0.33 flat.

### Tests
8. **`supabase/tests/10_settle_suite.sql:42`** — helper `p_fee` 4980 → **8217**
   (gross 24,900 = 9,900 base + 5km×3,000; 24,900 × 0.33 = 8,217; net 24,900 − 8,217 = 16,683 —
   matches handoff's "net 19,920 → 16,683"). No suite asserts amounts (verified: row
   counts/statuses/miles only), so this is the only test literal that shifts.
9. **NEW pin `S9 테이크레이트 33%`** in 10_settle_suite: (a) catalog default of
   `runners.commission_rate` is 0.33, (b) a fresh insert without explicit rate gets 0.33,
   (c) zero rows ≠ 0.33 after migration. Mutation-verified: reverting 0059 turns it red.

## Explicitly out of scope
- Removing the runner-row read from settle-run (audit recommendation) — kept: per-runner rate
  preserves tier flexibility; safe now that the column is server-only.
- Rewards ③ (point spend) — unblocked BY this, not part of it.
- Tier-linked rates — no real ladder exists (3 unbacked ladders coexist; cert-funnel spec Q7).

## Gates
- Harness full run: 234 existing + 1 new pin = **235/0** expected.
- Device gate: `app tsc --noEmit` + `check-rpc-contracts.mjs`.
- Adversarial review executes: pin revert-mutation, 0.2-residue sweep, trigger interplay,
  arithmetic re-derivation.

## Phase 1 — CEO review (/autoplan, 2026-08-06, [subagent-only] — codex CLI not installed)

**Premise challenge (0A)**: P-1 "33% flat now" = Sean's recorded directive (handoff §2g) — not
re-litigated, implementation premises only. P-2 "own migration, isolated from security" — valid,
purpose is regression visibility. P-3 "zero-notice instant flip is acceptable" — TRUE only while
real-runner count = 0 (pre-PG-launch); the PATTERN must not be copy-pasted later (KR 약관규제법
notice requirements) → deploy-note sentence added. P-4 "all references verified" — was FALSE:
CEO voice found api.ts:405 third fallback + stale comments api.ts:339/400 → folded into surface.

**Leverage map (0B)**: settle_run_tx untouched (fee passed in) · runner_protected_columns (0057)
already guards the column · getCommissionRate() already exists for per-runner previews.
**Alternatives (0C-bis)**: (a) flat update all rows [CHOSEN — matches directive, 1 migration] ·
(b) owner-side price bump instead of runner net cut [NOT ANALYZED by directive — recorded as
dismissed-by-decision; pricing architecture pass stays available pre-launch] · (c) booking-time
rate snapshot column [DEFERRED → fast-follow gate before PG go-live; adding schema to 0059
works against its isolation intent — surfaced at final gate as User Challenge].
**Temporal (0E)**: HOUR 1 all surfaces consistent at 33% · 6-MONTH regret risk = recruiting
first runner cohort on printed 20%-era numbers (F2) → docs swept in same commit.

**CEO findings adopted**: F3 api.ts:405 + comments (mechanical, added) · F2 docs sweep
runner-recruitment.md + one-pager.md derivable numbers (P2 blast radius; growth-model.xlsx
B13 is binary → Sean manual, flagged) · F4 runner-side math recorded: 5km net 19,920→16,683,
~1.62× min wage at ~60min run (was 1.9×) — retention assumption unchanged, Sean owns the call ·
F5 dismissal recorded · F6 deploy-note sentence · F7 theme.ts-vs-DB dual truth recorded as debt
(previews should derive from getCommissionRate(); theme constant becomes fallback) · F1 snapshot
column → User Challenge at gate. Not adopted into 0059: F1 implementation (schema change).

**NOT in scope**: bookings.commission_rate_at_booking (fast-follow, pre-PG gate) · owner-side
pricing architecture · tier-linked rates · rewards ③ · notice/effective-date machinery ·
growth-model.xlsx re-derivation (Sean).
**What already exists**: settle-run per-runner read · K-1 server-only guard · S4/S8 pins ·
myCommissionRate() cache.
**Error & rescue**: migration is idempotent-safe (default+update re-runnable); revert = restore
default 0.20 + update back (but pin S9 goes red — intended).
**Failure modes registry**: FM-1 old app binary previews 20% vs DB 33% (pre-launch: no users;
post-launch: F7 debt closes it) · FM-2 missing runner row → fallback now 0.33 (matches policy;
fail-loud alternative considered, kept fallback for minimal deployed-fn diff) ·
FM-3 [CORRECTED by Eng review] fresh harness creates all runner rows post-0059 → only the
UPGRADE path (v1 rows at 0.20) exercises the flatten UPDATE → pin must live in
98_hardening_suite (H8, tag 'hard') which runs post-migrations in BOTH harness.sh and
upgrade_check.sh and sits in the upgrade gate filter. A pin in 10_settle would run pre-005x
on the upgrade path (red there, unverified UPDATE in fresh runs) — original plan §Tests item 9
placement was WRONG.

**CEO consensus table** ([subagent-only] — single independent voice + primary reviewer):
premises valid ✓(as scoped) · right problem ✓(unblocks ③/⑤; PG integration remains the real
revenue gate) · scope calibration: code right-sized, artifact scope EXPANDED (docs) ·
alternatives: recorded ✓ · market risk: flagged (33% top-of-market for KR labor marketplace —
Sean's call, recorded) · 6-month trajectory ✓ with F1+F6 named as pre-launch workstream.

## Phase 3 — Eng review (/autoplan, 2026-08-06, [subagent-only])

**Architecture** (no new components — parameter flow):
```
runners.commission_rate (DB, default 0.33, server-only per 0057 §6)
  ├─→ settle-run edge fn :22 (row read; ?? 0.33 fallback) ──→ settle_run_tx(p_fee) [UNCHANGED]
  ├─→ api.ts myCommissionRate() :401 (cache; ?? 0.33 ×2) ──→ runner quote previews
  └─→ api.ts fetchMyRunnerCert :1146 (?? 0.33) ──→ apply.tsx display
theme.ts pricing.commission 0.33 ──→ store.ts:19 estPayout preview   [dual-truth debt, F7]
```

**Eng findings adopted**: E-F1 pin → **H8 in 98_hardening_suite** (tag 'hard'; 3 asserts:
catalog default cast-compared ::numeric = 0.33 · behavioral fresh-insert · zero rows distinct
from 0.33; mutation-verified on the UPGRADE path where pre-0059 rows exist) · E-F2
scripts/seed-runners.mjs:63 tier-conditional 0.15/0.18/0.2 → 0.33 flat · E-F3 hardcoded
"수수료 20% 제외" copy in app/app/runner/requests.tsx:181 + detail.tsx:53 → "수수료 33% 제외"
(static matches flat rate; deriving from myCommissionRate() folded into F7 debt) · E-F4
api.ts:405 fallback + comment sweep :339/:400/:738 + store.ts:360 mock payout 19900 (verify
consumers; recompute or retire) · E-F6 docs/product-notes.md:39 added to doc sweep · E-F7
upgrade_check.sh glob 004[0-9]|005[0-9] → extend to 006x so 0060 doesn't silently fall out.
**E-F5** (S9 name collision with 0058's S9 pin) — moot via H8 rename.

**Eng confirmations**: trigger interplay safe (guard blocks authenticated/anon only; harness +
db push run as postgres) · numeric(4,3) exact · no CHECK constraints · 4980→8217 breaks zero
downstream asserts (full suite read: counts/statuses/miles only; 20_recurring A2's 22720 uses
its own ledger literals; 60_custody's 6 t_settle callers assert custody/status) ·
check-rpc-contracts unaffected (settle_run_tx signature unchanged) · 99 S4 attack pin
value-independent · 0057/0058 hardening not weakened · 234+1 = 235/0 expected.

**Test diagram** (new/changed codepaths → coverage):
| Codepath | Test |
|---|---|
| 0059 default on fresh insert | H8(b) behavioral insert |
| 0059 flatten of pre-existing rows | H8(c) on upgrade path (v1 rows at 0.20) — mutation-verified |
| catalog default itself | H8(a) information_schema cast-compare |
| settle fee arithmetic at 33% | 10_settle helper 8217 (input truthfulness; no server recompute exists) |
| edge fn fallback | not harness-testable (Deno) — covered by code review + S4 value-independence |
| client previews | tsc gate + device smoke (Sean) |

## Phase 4 — cross-phase themes
**Theme: "all references verified" was false twice** (CEO F3: api.ts:405; Eng F2/F3/F4: seeds
script, UI copy, mock). Two independent voices each found residues the scout missed — the
0.2-residue sweep in adversarial review is now a MUST-pass gate, not a formality.
**Theme: rate-change pattern needs pre-launch machinery** (CEO F1 snapshot + F6 notice law) —
one named workstream before PG go-live.

## Decision Audit Trail
| # | Phase | Decision | Class | Principle | Rationale |
|---|---|---|---|---|---|
| 1 | CEO | Premises accepted as Sean's directive | gate | — | recorded decision, not re-litigated |
| 2 | CEO | Docs sweep into same commit (md only) | auto | P2 | blast radius = everything encoding take-rate |
| 3 | CEO | growth-model.xlsx → Sean manual | auto | P3 | binary artifact, his model |
| 4 | CEO | api.ts:405 + comments into surface | auto | P1 | mechanical correctness |
| 5 | CEO | runner-math paragraph recorded | auto | P1 | honesty doctrine |
| 6 | CEO | owner-side pricing dismissal recorded | auto | P6 | decision stays Sean's |
| 7 | CEO | theme.ts dual-truth → debt list | auto | P3/P5 | pre-launch preview-only |
| 8 | CEO | snapshot column NOT in 0059 | USER CHALLENGE | — | surfaced at gate |
| 9 | Eng | pin → H8 in 98_hardening_suite | auto | P1 | only placement with real mutation coverage |
| 10 | Eng | seed-runners.mjs 0.33 flat | auto | P1 | live residue |
| 11 | Eng | UI copy static "33%" | TASTE | P5 | derived-label alternative → F7 debt |
| 12 | Eng | upgrade_check glob → 006x | auto | P2 | 2-char fix, prevents silent 0060 gap |
| 13 | Eng | settle-run keeps fallback (no fail-loud) | auto | P3 | minimal deployed-fn diff |

## Adversarial review result (2026-08-06, attacks EXECUTED on isolated PG16 cluster)

Verdict: SHIP-WITH-FIXES → all fixes applied. Reviewer independently: re-derived every changed
number (all exact; one-pager formula chain cross-checked against financial-slides LTV 105,277),
applied full 0001→0059 chain to clean cluster, ran fresh suite + upgrade path, re-executed the
H8 mutation (UPDATE removed → red, drift_rows=11). Attacks that LANDED, all fixed:
**R-F1 (HIGH)** runner/home.tsx:625-655 live tier-ladder fee promise "수수료 ~~20%~~→18%/15%"
contradicted flat-33% settlement → ladder kept (승급 count is real), fee promises removed,
"수수료 일괄 33%" + 승급 혜택 준비 중 · **R-F2** 4 docs/instagram files carried 19,920/24,720/
39,840 with their own "fix before publishing" gates → 16,683/20,703/33,366 (their publication
gate "take rate 확정" is now genuinely satisfied) · **R-F3** one-pager:23 (~₩19,900 four lines
above the 33% line) + faq.md:212 → 16,700/1.6배 · **R-F4** financial-slides.md: 🔴 20%-기준
재산출-필요 banner + :110's obsolete "20%→25%" recommendation restated as decided-33% ·
**R-F5** upgrade_check.sh had the same broken BIN line harness.sh just fixed → same 2-line fix ·
**R-F6** api.ts:361/:388 stale comments · **R-F8** store.ts runnerStats dead mock (0 consumers)
retired. **R-F7 ACCEPTED as known cosmetic debt**: at 0.33, preview `round(g×0.67)` vs server
`g − round(g×0.33)` diverge by ₩1 when gross ≡ 50 (mod 100) (130 values in [9.9k,200k]; 0 at
0.20) — labels say 예상/추정, completed rows read the real ledger; folds into the F7
derive-preview debt.

## Deploy note for Sean (updates handoff queue)
`supabase db push` now carries 0055·0056·0057·0058·**0059** + `supabase functions deploy
transition-booking` **and `settle-run`**. Order caution: deploy settle-run AFTER (or with) the
db push — new fallback 0.33 with old DB rows at 0.20 is fine (row read wins), but old fn +
new rows is also fine; no ordering hazard either way since the row read dominates.
