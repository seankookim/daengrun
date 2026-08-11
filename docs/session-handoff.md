# SESSION HANDOFF — 2026-08-11 · club backend hardened, prod on 0072, the PMF gauge exists

**Opener for the next session: "read docs/session-handoff.md fully, then continue."**

Companion docs, in reading order:
- **`CLAUDE.md`** — permanent law book (language, gates, migration doctrine, ops authority).
- **`DESIGN.md`** — design law book. Read before ANY UI work.
- **`TODOS.md`** — the live backlog. It was corrected this session; four entries had been listing
  finished work as open. Treat it as accurate as of 2026-08-11 and re-verify anything older.
- `docs/plans/payments-toss-plan.md` — the live payments scope (the bridge plan is a tombstone).
- `docs/launch-checklist.md` §3b — the PMF gate's executable definition, new this session.

**Build in the MAIN checkout `/Users/sean/dev/daengrun`, branch `redesign-v4`.**
Worktrees under `.claude/worktrees/` are stale snapshots — never build or gate there.

Fact tags: **[verified-now]** checked at handoff · **[reported]** an agent said so, not
independently confirmed · **[from-history]** remembered, recheck · **[uncertain]** assumption.

---

## ⓪ STATUS

| System | State | Provenance |
|---|---|---|
| git | `41ab7f7` on redesign-v4, **0 dirty tracked files**, 16 commits this session | **[verified-now]** |
| Database | prod through **0072**, local == remote | **[verified-now]** (`migration list`) |
| SQL harness | **336 / 0** (was 305 — 31 new pins across 106-110) | **[verified-now]** |
| tsc | 0 errors | **[verified-now]** |
| check-rpc | 78 calls / 113 signatures, all match | **[verified-now]** |
| geo runner | 38 / 0 | **[verified-now]** |
| **Real customers** | **ZERO.** All 23 prod bookings belong to `s4kim2025`, which is in `club_test_accounts`. 8 completed runs, all solo testing | **[verified-now]** (`scripts/pilot-metrics.mjs`, checked against `auth.users`) |
| Prod seal check | anon gets 401 (not 404) on all new/changed club RPCs; `payments` refuses anon INSERT with an RLS error, not a missing-grant error | **[verified-now]** |
| Device verification | runner home · owner report · owner schedule + sheet · my/passport · role switch walked on sim | **[verified-now]** |
| Club screens | code + gates only — **never seen on screen**: this account has no club, so that world is unreachable in the simulator | **[uncertain]** |

**No open threads.** The second Codex adversarial review completed and its seven findings are
fixed in `41ab7f7` — see §⑤. Nothing from this session is left half-done.

---

## ① Where the product actually is

Korean dog-running marketplace (RN/Expo + Supabase), Banpo pilot, PMF gate M1 rebooking ≥60%.

The club/delegation backend is now the most-hardened part of the codebase — four migrations of
security and money work with mutation-proven pins. The marketplace client got a pass of honesty
fixes. **Payments remain blocked on Sean's filings and nothing in the repo can unblock them.**

The single most important fact for planning: **no real person has ever used this app.** The
metric built this session reports `—` and says so out loud. Every remaining backlog item is
downstream of that.

## ② What shipped — 14 commits, `488031d` → `3fb76b9`, 39 files

**Server / money (all pushed to prod).**
- `0067_incident_subject_gate.sql` — **P1 SECURITY.** `club_incident_open` never validated
  `p_dog`/`p_booking`, and `club_release_payouts` matched a booking subject with no session join,
  so any club participant could freeze an arbitrary booking's payout cross-club. Three layers: who
  may open a case, what may be named as a subject, and a session-scoped release probe. Also folded
  in C3 (SOS unification — `club_sos` is now a thin wrapper, never dropped, still returns `uuid`).
- `0068_retire_t10_hard_stop.sql` — **C1.** A `*/5` cron auto-refunded every paid delegation at
  T-10 while the app promises assignment happens 집결지에서. Deleted, not relocated.
- `0069_host_force_resolve.sql` — **C4/H5.** A picked-up dog whose run never ends had no exit.
- `0070_incident_accountability.sql` — the adversarial cycle's findings on 0067-0069 (see §④).
- `0071_payments.sql` — the accounting artifact for money coming IN (finding R7). Nothing charges
  anyone; this is the entire unblocked payments list.
- `0072_incident_settlement.sql` — the commercial exit from `incident_review`. Three outcomes, no
  invented money constant.

**Client.**
- Action rollout finished: `ClubCta`'s primary face measured **2.83:1** white and now uses
  `paper.action` (4.84:1); `violet` retired as an action tone; `secondary`/`destructive` added.
  `owner/report.tsx` migrated to paper, six CTAs cut to three. `runner/home.tsx` bib inverted to ink.
- Honesty pass: mid-run stop now reaches the runner (chat carries no push, notifications do);
  both accept doors on `runner/requests` ask before committing; the completion screen stopped
  printing a client estimate as 오늘의 수익; the fictional "매주 수요일 정산" schedule deleted.
- Club: stopped rendering a fabricated club (with an OFFICIAL badge) for both "loading" and "no
  club exists"; gave the host the session-cancel door that had existed server-side since 0038 with
  zero call sites.

**Tooling.**
- `scripts/pilot-metrics.mjs` — the PMF gate is computable for the first time.
- The `_fail`-subquery defect fixed repo-wide (12 executable sites across five suites).

## ③ Standing doctrines — the ones that bit this session

1. **Honesty is a hard law.** Most of this session's value came from enforcing it: an estimate
   labelled as earnings, a payout schedule that doesn't exist, a club that doesn't exist, a
   "held" settlement over a terminal state, a delivery the app claimed but never made.
2. **Commit gate**: `tsc --noEmit` + `check-rpc-contracts.mjs` + `bash app/test/run-geo-tests.sh`,
   plus the SQL harness for anything touching migrations.
3. **Money changes get their own migration + adversarial cycle + mutation-proof pins** (0059).
   Each pin must go red under a single named revert, and **you must run the revert.**
4. **Definer functions**: `set search_path = public, pg_temp` in the BODY (replace resets
   proconfig; 98 H1 watches it). Party gate before state gate. Identical errors for absent vs
   not-yours.
5. **Never `git add -A`** — untracked investor decks and secrets live in the tree.
6. 🔴 **The latest definition of a function is not the lowest-numbered one.** Rebuilding
   `club_incident_resolve` from 0050's body silently reverted 0058 F1's NULL-safe gate. 99 S9 went
   red immediately. `grep -n "create or replace function <name>"` across ALL migrations first.

## ④ Three defect patterns this session kept producing — read before writing pins

These cost real time and all three recurred. They are the most transferable thing in this document.

1. **A pin that cannot go red reads as proof.** Happened four times: 106 S5 (a global release call
   had already released its victim), 107 R3 (every actor was a non-party host, so the
   `self_override` guard was never reached), 110 S1 (the fixture only exercised one side of a
   branch), and 108 A3's first revert. **A fixture that exercises one side of a branch cannot
   protect that branch.** Always run the revert; "I wrote a pin" is not evidence.
2. **`call _fail(…, (select …))` raises `cannot use subquery in CALL argument`.** It only fires on
   the FAILURE path, so it sits green forever — and when it fires, the exception unwinds the pin's
   `begin…end` and **rolls back the fixture that pin already wrote**. Under one mutation that
   silently un-settled a booking and made three unrelated pins fail for unrelated reasons. Fixed
   repo-wide; the law is in 110's header. **`_fail` arguments are pre-computed into a variable.**
3. **`auth.uid() in (host, backup)` folds to NULL when backup is null**, so `not(NULL)` never fires
   and a stranger passes. That is 0058 F1's exact fail-open, and I reproduced it in 0072 two
   migrations after documenting it. Use the `exists (select 1 … where auth.uid() in (…))` form.

## ⑤ The adversarial cycles — both of them, and what they changed

**Round 1, on the club security slice.** Two independent voices (Codex CLI + a Claude engineer
executing attacks against a live scratch DB) reviewed 12f5963. Neither could reopen the payout
freeze. They found **four sentences written in my own migration headers that were false as
shipped** — fixed in 0070. The one worth remembering:

> `session_host_force_resolve` was **unusable in exactly the shape the audit described.** Host-only
> plus self-override-banned meant that in a small club, where the host runs the dogs, nobody could
> call it — and the console drew the button anyway. C4's "fix" was a dead button.

0070 §F opened it to the backup host and narrowed self-override to the dog's *owner*: a host
reporting their own run stuck is self-incrimination, not self-dealing.

**Round 2, on the client honesty work.** Codex confirmed the RLS authorization, the absence of any
one-tap commit, that `settled=true` reliably implies a server response, the H3 state split, and
that all 12 `_fail` rewrites preserved their expressions exactly. It then found seven defects,
five of them mine — all fixed in `41ab7f7`. The two that matter most:

- **A committed settlement could read as unsettled forever.** `settle_run_tx` commits; if the
  HTTP response is lost the client throws, `settled` stays false, and retry gets "이미 정산" with
  no way to recover the amount. My failure copy asserted *"아무것도 반영되지 않았어요"*, which is
  false on exactly that path.
- **An inserted notification is not a delivered push.** The 0024 trigger swallows every push error
  (0024:19,39), so the app cannot know. `notifyRunStop` also discarded its lookup error. Nothing
  now claims the runner was alerted — only that the notification was sent and the chat holds the
  record.

**Correction to a commit message:** `12f5963` claims *"Every pin mutation-proven."* That was an
overclaim — 106's header omits S2 and S6, and 107 R3 could not go red at all. Both fixed.

## ⑥ Architecture, contracts, DO-NOT-REFACTOR

- **DO-NOT-REFACTOR**: owner-home + fitness collapsing heroes (pinned overlay + paddingTop
  reservation + transform/opacity native driver only — no height animation) · meetup stage
  machines, polling, confirmHandoff, once-law hydration ordering (new state at the END of the hook
  bundle) · the 2-layer matching compositor · availability's 3 deliberately distinct predicates.
- **Pixel budgets to re-derive, not eyeball**: GO stack 237 ≤ RING_BIG 240, disc interior 75 ≤ 140
  (`owner/home.tsx` top); `headerHFor`; runner-home column cages.
- **BUG A**: Oswald (`useNumFont`) needs explicit `lineHeight ≥ 1.2×` or ascenders clip.
  `Math.ceil`, never `round`.
- **`session_dogs` has a `club_v1_axes_sync` trigger** that recomputes derived columns
  (`custody_phase`, `refund_state`). Hand-setting them in a test or an RPC gets silently reverted —
  cost me two debug cycles. Derived values get one owner.
- **`club_fee_items.kind` is a CHECK, not an enum** — widening it needs no separate file. The §⑪
  enum trap is specifically `alter type … add value`.

## ⑦ Known-good — do NOT "fix" these

Zero TouchableOpacity app-wide · zero authored colored emoji · `compose.tsx` · the receipt seal
ceremony · `club/case`'s LoadGate idiom · the GPS honesty stack in `run.tsx` · shot's photo
truthfulness · the 0060/0065 pickup-address gating.

Deliberate, don't "simplify": dark artifacts (passport record face, seal band, club night world,
settlement ticket, floating request ticket incl. its **round** punch-hole notches) and Peak moments
(GO press, handoff seal, run completion, done screen) — exempt from decluttering by §7b.

## ⑧ Gotchas & failure modes

- **Tools that exit 0 on failure**: Expo/CocoaPods without a UTF-8 locale dies but exits 0, leaving
  a stale binary. Always `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8`; verify by bundle container path.
- **Harness**: `pkill -f "bin/postgres"` first, then `sleep 3` — an unclean shutdown gives
  "connection refused" on the next run.
- **"Open debugger to view warnings"** is RN LogBox in dev builds, not a product bug.
- **check-rpc only parses `create or replace function`** and **never removes a dropped signature** —
  `drop function foo(...)` leaves `foo` validated forever. It also parses **no return types**, so a
  changed return shape passes both gates and breaks at runtime.
- 🔴 **The SQL harness cannot detect enum-migration transaction failures.** Any migration adding an
  enum value gets its own file containing only the `add value`. `harness.sh` now applies each file
  with `--single-transaction` and self-pins that flag.
- **Colour emoji can arrive by font fallback, not authoring.** `↔` (U+2194) styled with Oswald fell
  back to Apple Color Emoji. `seed.sql:33-37` still ships `♒`/`☀` in `routes.features`, rendering
  as colour emoji on owner home **in prod data right now**. The emoji ban is about what RENDERS.

## ⑨ Working with Codex (it earned its keep this session)

`codex` is on PATH and authenticated (0.147.0). It is genuinely useful, not ceremony — it found
the `club_incident_assign` hole, the `payout_hold` orphaning, the missing session lock, and the
dead 107 R3 pin. Two things matter:

- Prefix every prompt with the skills/gstack filesystem boundary line, or it wastes minutes
  reading skill files.
- Tell it to **execute attacks, not read code**, and to be decisive. "Rank them, no hedging"
  produced a materially better answer than "review this".

Invocation shape that worked:
```bash
source ~/.claude/skills/gstack/bin/gstack-codex-probe
_gstack_codex_timeout_wrapper 900 codex exec "<prompt>" -C /Users/sean/dev/daengrun -s read-only
```

## 🔴 ⑩ Pending on Sean — nothing below can be done for you

**Payments — the only thing between the app and its first ₩.** Four locks, all yours:

| Lock | Detail | Blocks |
|---|---|---|
| 사업자등록 | 홈택스, same-day, **free** | everything below |
| 통신판매업 신고 | 시/군/구, ~₩40,000/yr | the PG contract |
| 토스페이먼츠 계약 | 1–2 week review, needs both above | the live switch |
| `TOSS_SECRET_KEY` | `supabase secrets set …` | `confirm-payment` |

~2–3 weeks from filing. ⚠ 예비창업패키지 2027 (~₩40M) closes the moment 사업자등록 lands — decided,
recorded so it isn't a surprise.

⚠ **Do NOT pre-delete `pay.tsx:334` (예약 확정하기) or `pay.tsx:299` ("실결제는 발생하지 않았어요").**
`:334` → `api.ts:230` `payment_ok` is the only path a booking has into `matching` today; `:299` is
currently TRUE. Both become wrong at the same instant `confirm-payment` goes live. Toss-plan step 3.

**Also yours:** NCP console (Mobile Dynamic Map + Geocoding API checkboxes) · `NAVER_GEOCODE_SECRET`
· counsel on the privacy-policy coordinates rider · the `identity_verified` cleanup (**9 of 9**
runner rows are fabricated, including `s4kim2025`; cleaning it empties the marketplace, which is
honest) · seed-runner decision · TestFlight · **recruiting one real owner and one real runner.**

## ⑪ Next 1–3

**The strategic call, from Codex standing in your seat, which I agree with:**

> "The absence of real runners and customers changes the answer completely: after these five, stop
> building. The next unit of progress is a real two-person run followed by a second booking — not
> reduced motion, emoji cleanup, rewards polish, another club abstraction, or more backend
> hardening. Existing rebooking UX is already sufficient to test; the company now needs people,
> observation, and a trustworthy number."

1. 🔴 **사업자등록.** Free, same-day, and the whole payments chain waits on it.
2. **One real run with one real owner and one real runner**, then `node scripts/pilot-metrics.mjs`.
   The gauge exists now; it needs people, not code.
3. **Then re-read TODOS** with real usage in hand — the priorities will have changed, and several
   P2s exist only because nobody has ever hit them.

**If you want code anyway**, in TODOS priority order: `rewards.tsx` swallowed catches (a failed
load renders as an absence of rewards — the raw enum beside it is cosmetic, the catches are not) ·
club M1 (`ui.allowedActions` is always `[]`, the structural source of the dead-button class) ·
club M2 (fee terms hardcoded in consent copy while the server reads `club_cfg` — a config change
silently makes the legal checkbox false) · reduced motion across ~8 loops · the `seed.sql` emoji.

**Explicitly deferred with reasons in TODOS:** non-club `incident_review` settlement (no ops role
exists) · guest-RSVP shell breadth · historical-runner case rights · the gear-dial momentum.

## ⑫ Environment & test data on prod

`s4kim2025` is the only account with bookings (23, of which 8 completed) and is registered in
`club_test_accounts` — so `pilot-metrics.mjs` correctly excludes all of it and reports `—`.
One address ("Home", pin at 세빛섬 37.512203/126.996087) attached to two 8/4 `runner_enroute`
bookings staged to verify map + cancel surfaces; the in-app cancel is the honest way to clear them.
`push_tokens` has **1 row**, so push is testable on one device only.

## ⑬ Verification commands

**Safe / read-only**
```bash
git -C /Users/sean/dev/daengrun log --oneline -5 && git status --porcelain
cd /Users/sean/dev/daengrun/app && ./node_modules/.bin/tsc --noEmit
cd /Users/sean/dev/daengrun/app && node scripts/check-rpc-contracts.mjs
bash /Users/sean/dev/daengrun/app/test/run-geo-tests.sh
cd /Users/sean/dev/daengrun && supabase migration list
node /Users/sean/dev/daengrun/scripts/pilot-metrics.mjs
node /Users/sean/dev/daengrun/scripts/diag.mjs
```
**Expensive but non-destructive** — PG16 harness (~2.5 min; kill orphans first)
```bash
pkill -f "bin/postgres"; sleep 3; cd /Users/sean/dev/daengrun/supabase/tests && \
  LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 bash harness.sh 2>&1 | tail -3
```
**App on the simulator** (from `app/`)
```bash
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 npx expo run:ios
```
**Destructive / changes the world — confirm with Sean first**
`supabase db push` · `supabase functions deploy <name>` · `node scripts/geocode-backfill.mjs --yes` ·
`node scripts/wipe-test-data.mjs` · `node scripts/migrate-private-media.mjs --yes --purge` ·
any in-app cancel of the 8/4 test bookings.
