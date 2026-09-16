# Backend honesty & reliability audit — 11 edge functions · 22 cron jobs · RPC surface (2026-09-17)

Server-side twin of `docs/design/loading-state-audit.md`. Produced by a read-only audit agent (Claude
Opus 5) and persisted by the orchestrating session; trunk `be258c6`. **OBSERVED** = a command was run;
everything else is **READ** from source. Known/pending 0157–0174 findings are cross-referenced, not
re-reported (see the tail).

## Observed
| command | result |
|---|---|
| `node app/scripts/check-rpc-contracts.mjs` | exit 0 — 132 call sites · 213 signatures · all match (arity + arg names only; says nothing about return MEANING) |
| `deno test -A supabase/functions/_test/` | **292 passed / 0 failed** across 18 suites |
| `ls supabase/functions/*/` | **11** deployed function dirs (+ `_shared` ×5 modules, `_test`) — the brief said 12 |
| `grep -c "cron.schedule("` on `*.sql` | 27 hits, 26 executable (1 comment `0117:1588`) → **22 distinct jobs**, 4 re-registrations |
| `grep 'not_run_runner\|run_ended'` in `app/` | **0 hits** — the two 0083 raise tokens are unmapped client-side |
| secrets grep over 65 non-test `console.*` lines + 13 `Deno.env.get` sites | no env-secret value logged |

## (a) Per edge function (all READ)

| fn | Auth / party | Input | Errors | Idempotency | External | Secrets |
|---|---|---|---|---|---|---|
| **collect-charges** | PASS — cron arm `requireCronKey` (`_shared/cron-auth.ts:47-54`); owner arm party gate `handler.ts:90-93` before the read `:95` | PASS — guarded parse `:79`, `400 missing fields :83` | deliberate: two catches (`:337,:361`) return `outcome:"error"` inside a 200 (batch policy `:12-13`); structural → 500 | PASS — dispatch CAS on `status` AND `raw->>attempts` (`_shared/charge.ts:214-228`); sequential loop `:167-171` | PASS — 10 s on `tossGetByOrderId`/`tossBillingCharge` (`toss.ts:198,:120`); throw = `unresolved`, never a decline | clean |
| **confirm-payment** | PASS — party `:93` → widget/kind `:101` → state `:106-116`, order written as law `:10-20` | **FAIL (M1)** — unguarded `req.json()` `:72` → `500 internal` (`ctx.ts:46-50`), its own `400 :76` unreachable | PASS — named refusals; `autoCancel` always throws with two honest sentences `:41-48` | PASS — idempotent short-circuit before Toss `:106-112`; key reuse refused `:119-124`; CAS on `status='pending'` `:170-187` | mixed — `tossConfirm/Cancel` no timeout, argued (`toss.ts:31-37`); `invokeTransition :344-359` no timeout, no argument (**M9**) | clean |
| **create-booking-hold** | PASS — ownership of dog/address before any write `:116-123` | strong on values (`:86,:102-106,:247,:284,:165`), **FAIL on shape** — unguarded parse `:72` | fail-closed on money gates `:179,:193,:212` ✓; raw Postgres text as 500 body at 8 sites (**L1**); CAS-failure arm has two honest sentences `:365-370` | **WEAK** — no idempotency key; double-submit stopped only by the same-dog overlap guard `:264-275`, which works because §C.1 lands `matching` synchronously `:254-262`; 4 sequential writes, no tx `:291-318` | none | clean |
| **create-payment-intent** | PASS — `:28` party before `:29` state | **FAIL (M1)** — `:18` | named 404/403/409; raw pg text `:23,:40,:51,:63,:76` | PASS — live pending reused `:47-56`, mismatched closed `:60-63`, server-minted unique `order_id :68` | none | `toss_customer_key` returned to its owner — documented |
| **delete-account** | PASS — uid from JWT only, reasoned `:87-89` | **PASS** — guarded `:93-98`, `400 confirm_required :99` (the only function fully right) | PASS — 12 state tokens → 409, `not_authenticated` → 401 `:104-118`; `202 auth_delete_pending :157-172` | PASS — `already:true` short-circuit `:163` | storage sweep count reported in the response `:129-143` | clean; **1 unchecked write** `:151-155` (audit row) |
| **geocode-address** | PASS — reverse gate is the `.eq(owner_id)` in the SELECT (`reverse.ts:25-36`) | PASS — guarded `index.ts:46`, 100-char cap `:55` | deliberate silent degrade to `{available:false}` (`index.ts:104`, `reverse.ts:95`), argued `:22-24` | n/a | PASS — 5 s AbortController both; **no throttle**, self-flagged AD-10 `:24-35` | best-in-class: prefix + query length + outcome only |
| **open-drop** | PASS-ish — `select *` incl. `contents` loaded before party `:13`/state `:14` | **FAIL** — unguarded `:8`; `pick_choice` validated `:48` AFTER the consuming CAS `:18-22` (**M3**) | **FAIL (H1)** — four writers `:34,:41,:51,:58` never bind `error`, then `applied.card/gear/boost_until` is set anyway | CAS correct but consuming; `0106 §3` freezes `opened_at` → no second attempt (**H2**) | none | clean; **no test suite** (L5) |
| **register-billing-key** | PASS — party → tombstone `:312-315` → rollout flag `:328-330` (09-15 MED #5 fix in place) | PASS — guarded `:295`; named refusals `:338,:342,:348,:527` | best in repo — durable intent row closed before every throw (`:366,:377,:391,:429,:461,:492`); three `swapped=false` causes each mapped `:496-508`; one bare `catch {}` `:123`, narrow and argued (L3) | strong; per-isolate attempt nonce `:43-44` self-flagged `:229-231` | PASS — 10 s (`toss.ts:189`); refusal shows Toss's own sentence `:381` | clean, deliberate: customer key logged, billing key refused `:200-208`; `:472` throws raw SQL text |
| **revoke-billing-keys** | PASS — `requireCronKey` first `:31`; `verify_jwt=false` declared in `config.toml:26-27` | n/a (no body) | Toss catch keeps row `pending` `:62-66` ✓; **`:72` report failure throws 500 mid-loop, abandoning claimed rows (M6)** | PASS — claim → call → report with lease + `claim_token` CAS `:70-74`; 404 ≠ success `:44-53` | 10 s (`toss.ts:151`) | clean (`err` sliced to 300) |
| **settle-run** | PASS — `:73`, every later refusal placed after it with the oracle argument `:86-88,:127-129` | unguarded `:68` (**M1**); then strictest validation in repo `:42-53,:159-169`, skipped on frozen path `:111-115` | PASS — every `settle_run_tx` raise mapped with the migration's Korean `:226-257`; `failed`/`lost`/`skipped_not_live` + greppable `CHARGE LOST :454-458` (HIGH #1, refuted 09-15) | PASS — double-settle refused in SQL; mint under `pg_advisory_xact_lock`, `order_id` UNIQUE `:400-405` | via `charge.ts` (10 s) | clean |
| **transition-booking** (+`cancel_owner`, `start_run`) | PASS with documented carve-out — `:49` party before switch; `runner_accept` re-gated `:62-63`; nomination chain named open `:31-34` | **FAIL (M1)** — `:42`; per-action validation good after | `:53` trigger refusal → 409 with raw trigger text; `:225-231` declines-log swallow argued; `cancel_owner.ts:283,:340,:370` non-fatal, two ping ops with remedy copy | strong — `enroute :252-268`, `arrived :281-297` CAS + re-read + `{unchanged:true}`; cancel double-tap refuses to invent ₩0 `cancel_owner.ts:83-101` | indirect; `cancel_owner.ts:194-196` orders push before billing | clean; **`notify()` fire-and-forget at 15 sites** `index.ts:55-56` (**M2**) |

## (b) Cron — 22 jobs (READ from migration source; production `cron.job` is a table read Claude cannot run)

| job | schedule | function | registration | readback | failure visible | self-concurrent |
|---|---|---|---|---|---|---|
| weekly-rewards | `10 15 * * 0` | `grant_weekly_rewards()` | `when others` `0014:73` | ✗ | ✗ | no lock |
| purge-chat | `0 19 * * *` | `purge_old_chat()` | `when others` `0014:73` | ✗ | ✗ | idempotent delete |
| expire-unmatched | `*/5` | `expire_unmatched_bookings()` | `when others` `0017:24` | ✗ | notification only | status CAS |
| expire-reschedules | `*/10` | `expire_reschedule_requests()` | `when others` `0021:34` | ✗ | notification only | no lock |
| recurring-gen | `7 * * * *` | `generate_recurring_bookings()` | `when others` `0026:157` | ✗ | `raise warning 0127:94` + owner notification | unique_violation arm |
| club-series-gen | `20 * * * *` | `club_generate_club_sessions()` | `when others` `0035:118` | ✗ | ✗ (`unique_violation` swallowed `0050:37`) | unique key |
| club-min-attendance | `40 * * * *` | `club_notify_min_attendance()` | `when others` `0037:472` | ✗ | notification only | no lock |
| club-hold-expiry | `*/5` | `club_expire_delegation_holds()` | `when others` `0043:406` | ✗ | notification only | no lock |
| **club-payout-release** | `0 18 * * *` | `club_release_payouts()` | `when others` `0045:444` | **✗** | **✗** | no lock |
| club-assignment-recovery | `*/5` | `club_assignment_recovery()` | `when others` `0047:437` | ✗ | notification only | no lock |
| purge-holds | `1-56/5` | `purge_expired_holds()` | `when others` `0060:151` | ✗ | ✗ | idempotent delete |
| owner-la-stale | `* * * * *` | `owner_la_sweep_stale()` | `when others` `0063:432` | ✗ | ✗ | **no lock; read-then-write dedupe on `last_state`** (M10) |
| club-stale-delegation-sweep | `17 * * * *` | `club_stale_delegation_sweep()` | `when others` `0070:37` | ✗ | notification only | no lock |
| sweep-payment-intents | `3-58/5` | `sweep_stale_payment_intents()` | `when others` `0076:109` | ✗ (named out of scope by 0172) | notification only | no lock |
| sweep-settled-charges | `2-57/5` | `sweep_settled_without_payments()` | strict `0172:100-107` | ✓ 0172 VERIFY | `raise notice` → reconciliation arm 8 (0173/0174) | mint advisory xact lock `0080:369` |
| dispatch-due-charges | `4-59/5` | `dispatch_due_charges()` | strict `0172:114-120` | ✓ 0172 VERIFY | `raise notice` only `0080:1241-1245` | real guard is `charge.ts:214` |
| **run-end-recovery** | `8-58/10` | `sweep_run_end_recovery()` | `when others` `0083:1513` | **✗** | `raise notice 0083:1531` + notifications | no lock |
| late-booking-sweep | `3-53/10` | `late_booking_sweep()` | `0117:1301`; re-reg `0126:141-147` narrow handler | ✓ self-verify `0117:1308-1322` | `raise warning` per row `0117:1269` | `pg_try_advisory_lock 0117:1206` ✓ |
| **cancel-money-gaps** | `6-56/10` | `sweep_cancel_money_gaps()` | `when others` `0117:1653` | **✗** | `raise warning` per row `0117:1630` | `pg_try_advisory_lock 0117:1559` ✓ |
| **sweep-club-cancel-fees** | `2-52/10` | `sweep_club_cancel_fee_intents()` | `when others` `0118:1340` | **✗** | ✗ | mint advisory lock `0118:584` |
| revoke-billing-keys | `8-58/10` | `dispatch_billing_key_revocations()` | `0138:289` → strict re-reg `0157:46-50` | ✓ 0157 VERIFY | ✓ `billing_key_dispatch_ticks` row per tick (0166) | `for update skip locked 0166:250` |
| finalize-stopped-runs | `* * * * *` | `club_finalize_stopped_runs()` | strict `0168:664-668` | ✓ 0168 VERIFY | `raise warning` per row `0168:630`; rich return discarded by the cron command | `lock_timeout 2000` + per-row `begin/exception 0168:532` |

Structural: **17/22 jobs registered inside `exception when others → raise notice`** (a failed `cron.schedule`
commits as a successful migration; 0172 condemned the form and swept two names). **22/22 cron commands
discard the function's return** (`select f()`). **2/22 hold a job-level advisory lock.**

## (c) Ranked defects

### HIGH — reachable today, no flag in front
- **H1 · `open-drop` returns a receipt for rewards it never checked were written.** `index.ts:34,:41,:51,:58` never bind `error`; `applied.*` is set regardless; the drop is already stamped `opened_at` by the CAS `:18`, frozen by `0106 §3`. Fix: bind/check each writer, add the key to `applied` only when the write landed (`cancel_owner.ts:197-202` idiom).
- **H2 · `open-drop` consumes the drop before it can pay it.** `miles_ledger` insert `:29` (or `:54`) fails → 500, but `opened_at` is already stamped and cannot be un-stamped; miles gone, no sweep, no ops event. Fix: one `open_drop_tx` definer (the `settle_run_tx` shape). *Migration — adversarial cycle.*
- **H3 · Four money/ops cron jobs have no readback**: `club-payout-release` (0045), `cancel-money-gaps` (0117), `sweep-club-cancel-fees` (0118), `run-end-recovery` (0083) — a failed registration on the production apply would be silent. Fix: one migration re-registering all four byte-identically without the handler + a VERIFY asserting `count(*)=1` per (jobname, command) — 0172's shape with four rows. *Repo-side claim about a missing guarantee; production `cron.job` was not read.*

### MED — wrong message or silent failure
- **M1 · 6/11 functions turn a malformed body into `500 internal`** — `transition-booking/index.ts:42`, `open-drop/index.ts:8`, `create-booking-hold/handler.ts:72`, `create-payment-intent/handler.ts:18`, `confirm-payment/handler.ts:72`, `settle-run/handler.ts:68`. Fix: `req.json().catch(() => { throw new HttpError(400,'bad_body') })` (`collect-charges:79` idiom).
- **M2 · `notify()` fire-and-forget at 15 sites** (`transition-booking/index.ts:55-56`, `start_run.ts:51`, `cancel_owner.ts:219`); worst is `:329` 「인계 확인 요청」 — a lost insert means nobody is asked to confirm the handoff (attack-INACTION shape). Fix: return + `console.error` the error (`charge.ts:494-498` shape); add a notifications-anchored arm to the handoff sweep.
- **M3 · `open-drop` validates `pick_choice` after the consuming write** → `rewards.tsx:83` prints `violates check constraint "drops_pick_opened_has_choice"` in a Korean alert. Fix: move the `:48` whitelist above `:18`.
- **M4 · client `openDrop` unwraps one level too few** — edge returns `{applied:{…}}` (`index.ts:67`); `api.ts:3758-3762` returns the envelope; `rewards.tsx:73-80` reads `applied.miles` → always undefined → alert always 「보상이 적용됐어요」. Fix: `return data.applied ?? {}`.
- **M5 · 0083 turned two no-ops into raises (`not_run_runner`, `run_ended`, `0083:485-517`) and no client maps them** (OBSERVED 0 hits); `api.ts:2457-2477` rethrows raw. Fix: map both tokens to the migration's own Korean copy.
- **M6 · `revoke-billing-keys` abandons a claimed batch on a report failure** (`handler.ts:72` throws mid-loop); re-claimed rows get a second DELETE whose Toss response is undocumented (`toss.ts:129-146`) → `abandoned` → ops paged for a key already gone. Card-flag gated. Fix: count, log, `continue` (like the Toss catch `:62`).
- **M7 · ④ instance server-side**: `report_billing_key_revocation` boolean widened (`0138:175` void → `0155:240` boolean → `0166:283-285` adds `and state='processing'`); `handler.ts:73` still reads one cause (`stale++`). Fix: return a refusal token (`lease_lost|not_processing|absent`), map each, absent fails closed (the 0143 `billing_key_swap` shape).
- **M8 · Three bookkeeping writes on the money path discard their error** — `confirm-payment/handler.ts:139-143`, `:244-250`, `:259-269` (`needs_manual_cancel` — the reconciliation `orphan_capture` arm's only anchor) + `delete-account/handler.ts:151-155`. Fix: bind + `console.error`; `:259` → `notifyOps` on failure.
- **M9 · `invokeTransition` has no timeout and no argument** (`confirm-payment/handler.ts:352-354`), inside the post-capture window. Fix: `signal: AbortSignal.timeout(10_000)` (failure is already non-fatal `:332-338`).
- **M10 · `owner-la-stale` every minute, no job lock, read-then-write dedupe** (`0063:431`, `0083`): overlapping ticks push the same stale-location line twice. Fix: `pg_try_advisory_lock(hashtextextended('owner_la_sweep_stale',0))` (`0117:1206` idiom).

### LOW — hygiene
- **L1** raw Postgres text reaches clients at ~20 sites (listed in (a)). Fix: one `internalError(e)` helper.
- **L2** `charge.ts:429` logs two Toss `paymentKey`s (refund handles) in the DOUBLE CAPTURE line; keep the pair in `raw.double_capture :422`, log last 6 chars.
- **L3** `register-billing-key/handler.ts:123` bare `catch {}` — argued; recorded, not a defect.
- **L4** `0126:142` `cron.unschedule` raises `P0001` when absent; unreachable forward (0117 VERIFY aborts first); latent.
- **L5** no `_test` suite for `open-drop` (H1/H2/M3 all in that 68-line file).
- **L6** `collect-charges:79` guard is owner-arm only (correct, undocumented).

**Cross-referenced, not re-reported:** deploy-gate HIGH #1 (`CHARGE LOST`) refuted 09-15; HIGH #2 half-closed `bf47df7`; HIGH #3 provenance; MED #5 party-before-flag **verified fixed** at `register-billing-key:312-330`; MED #6 → 0171; LOW #10 `run_stopping` mapped at `settle-run:228`; `collect-charges` absent from `config.toml` (written up at `config.toml:21-25`); no `deno.lock` on `jsr:@std/crypto@1` (REGISTRY).

## (d) Counts — what each counts
11 deployed functions · 5 shared modules · 292/0 deno · 132 call sites / 213 signatures (arity+names only) · 49 distinct RPC names · 28 executable catch sites (1 bare, 4 `.catch(()=>default)`) · **6/11 unguarded `req.json()`** · **25 DB writes whose error is never read** (open-drop 4, `notify()` 15, confirm-payment 3 + `notifyOwner` 2, delete-account 1) · 26/22 cron calls/jobs · **17/22 swallowing registration** · 5/22 with readback · 2/22 with a job lock · 0 env-secret values logged · 1 paymentKey pair logged.

## (e) Could not determine
1. Whether any cron job is actually registered on **production** (`cron.job` read is Sean's/blocked) — H3 is a missing-guarantee claim, not an observed gap.
2. Whether `collect-charges` is still deployed `--no-verify-jwt` (last measured 08-27).
3. Whether `register-billing-key:44`'s per-isolate nonce survives edge routing (`:229-231` open).
4. Toss's response to a second DELETE on an already-revoked billing key (M6 severity depends on it).
5. Whether `pg_advisory_unlock` at `0117:1275/1634` is reached on every exit path (shape looks right; not read statement-by-statement).
6. `club_release_payouts` failure visibility — 4 definitions (0045/0067/0070/0072); only 0072 read.
7. How often the 0083 raise tokens reach a person (runtime).
