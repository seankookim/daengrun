-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0172 — the settle-charge RECOVERY CHAIN is read back from `cron.job`, not assumed
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 202_settle_charge_reconcile_suite.sql (tag `scr`).
--
-- ═══ 🔴 THIS FILE IS NOT WHAT IT WAS CLAIMED FOR, AND THE REASON IS A MEASUREMENT ═══════════
--
-- The claim commit said: 「codex deploy-gate HIGH #1 — settle-run's post-settlement
-- `mint_settle_charge_intent` can fail twice and log `CHARGE LOST`; **no sweep or owner retry
-- finds it**. Build a flag-gated reconciliation sweep that re-mints idempotently.」
--
-- **THE SWEEP ALREADY EXISTS, AND IT WAS MEASURED RECOVERING EXACTLY THAT STATE.**
--   `sweep_settled_without_payments()` — `0080:569` §G, extended at `0116:60` §A — is bookings-
--   anchored precisely because the payments-anchored reconciliation arms structurally cannot see a
--   crash that left NO payments row. Its own header (`0080:562-566`) names this class in the
--   finding's own words: *「if the process died between `settle_run_tx` committing and the mint,
--   there is no payments row to be stale … this sweep is the only thing standing between "the
--   runner was paid" and "nobody ever recorded that the owner owes"」*. It is registered on
--   `cron.job` as `sweep-settled-charges` `2-57/5 * * * *` (`0080:643`) — every five minutes.
--
--   MEASURED 2026-09-15 in this worktree's harness, on the REAL settle path (no hand-written
--   fixture row): `end_run_tx` → `confirm_return_tx(runner)` → `confirm_return_tx(owner, quote)`.
--   That is the CHARGE LOST state by construction, because **no SQL path mints** — the mint is
--   only ever called by `settle-run/handler.ts` and by this sweep. State after settlement:
--   `runs.settled_at` stamped · 1 `ledger_items` row · `bookings.status = 'completed'` ·
--   **0 `payments` rows**. Then one `select sweep_settled_without_payments()`:
--       status `pending` · amount **18900** · `raw.kind` `settle_charge` ·
--       `raw.basis_km` **3.00** (the FROZEN distance) · `raw.rule` `actual_capped`
--   — amount asserted equal to `compute_owner_charge()`'s own answer, never a literal. A second
--   sweep in the same block added nothing (1 row before, 1 row after).
--
--   So the finding's sentence 「no sweep … can find that booking again」 is **FALSE**. Same shape
--   as the `net` grant this file's house rules record: a true fact about one artifact (the
--   handler really does give up and return `lost`) stated as a fact about the SYSTEM, which has a
--   second machine the handler does not know about.
--
-- ⚠ AND BUILDING THE CLAIMED SWEEP WOULD HAVE BEEN WORSE THAN THE GAP IT WAS AIMED AT. The brief's
--   own 「settled」 predicate was 「`bookings.status = 'completed'` with a ledger row」. `0116:47-52`
--   documents BOTH halves of that as the two wrong substitutes, with reasons:
--     · `bookings.status` — §0-ter #11 / `116 C8`: a settled booking legitimately moves on to
--       `incident_review` / `refund_pending`, so anchoring there HIDES the very crash class the
--       sweep exists to catch. (Reproduced incidentally by this slice's own measurement: the two
--       neighbouring bookings in the fixture database sit at exactly those two statuses.)
--     · `ledger_items` presence — `0080 §K` writes a ledger row for a **CANCELLED** booking, which
--       is not a run at all. A sweep anchored there mints an owner charge for a run that never
--       happened. That is the brief's own STOP condition (「a sweep that mints a wrong amount is
--       worse than the gap」) arriving through the predicate rather than through an argument.
--   The correct anchor is `runs.settled_at`, which is what the deployed sweep already uses and
--   what `119 R11` exists to keep true.
--
-- ═══ WHAT IS ACTUALLY OWED, AND IT IS THE HALF THE FINDING GOT RIGHT ════════════════════════
--
-- 「The sweep exists」 and 「the sweep RUNS」 are two propositions, and only the first one has ever
-- been checked. Both of the jobs that make up the charge-recovery chain were registered under the
-- **swallowing** form this repo has already condemned once:
--
--     do $$ begin  perform cron.schedule(...);
--     exception when others then raise notice 'pg_cron unavailable — …';  end $$;
--                                            ↑ `0080:643` and `0080:1259`
--
-- `0157 §A` (`0157:23-66`) is the file that named this class and fixed it — for ONE job,
-- `revoke-billing-keys`: *「`cron.schedule` returning (or, worse, being swallowed) is a claim; a
-- row in `cron.job` is the fact」*. The two 0080 jobs were left behind, and **nothing anywhere —
-- no VERIFY, no pin, no suite — asserts that either one is registered.** Swept: the only readback
-- in the repo is 0157's own, plus 0168's for `finalize-stopped-runs`.
--
-- That is the residual of HIGH #1 stated accurately: *the recovery machine exists and has never
-- been verified to be scheduled.* If `cron.schedule` failed on the production apply of 0080 —
-- pg_cron absent at that moment, the role lacking rights in `cron`, a malformed schedule — the
-- migration printed a NOTICE and COMMITTED, and the day `payments_live_since` flips, every
-- settle-crash becomes exactly the permanent charge loss the finding describes. Nothing today
-- would tell anyone.
--
-- ⚠ THIS SLICE IS A READBACK, NOT A POLICY CHANGE. Both re-registrations below are **byte-identical
--   to the shipped ones** — same jobname, same schedule string, same command. `cron.schedule`
--   UPSERTS on (jobname, username) in pg_cron >= 1.4, so this overwrites rather than duplicating.
--   No cadence is chosen here and therefore nothing in this file is PROVISIONAL: a new constant
--   would be a product decision, and there is no new constant.
-- ⚠ NO `exception` HANDLER, DELIBERATELY — 0157 §A's reason verbatim: an environment with no
--   scheduler must not be allowed to believe it has one. The harness ships a pg_cron registry stub
--   (`tests/00_shim.sql:79-118`), so the strict form is EXERCISED here, not merely asserted.
-- ⚠ ONE ABORT DIRECTION IS KNOWN AND ACCEPTED, and 0157 §A carries the same exposure: if
--   production's existing job is owned by a DIFFERENT `username` than the role applying this file,
--   the upsert key differs, a second row appears, and VERIFY aborts on `found 2`. That is the
--   correct failure direction — loud, before anything moves — and the message names the count.
--
-- ⚠ OUT OF SCOPE, NAMED RATHER THAN SILENTLY OMITTED:
--   · `sweep-payment-intents` (`0076:108`) carries the same swallowing form. It CLOSES stale
--     intents; it is not on the settle-charge recovery chain, and widening this file to every
--     swallowed cron in the repo is a different slice with a different blast radius.
--   · A settled booking the sweep can never price — `end_reason` NULL, `actual_km` NULL, or a mint
--     that raises — is skipped with a `raise notice` and is invisible to ops: `payments_
--     reconciliation()` deliberately has no `settled_without_payment` arm, on the stated grounds
--     that the sweep mints the row (`_shared/ops.ts:95`). Post-`settle_run_tx` both columns are
--     non-null, so this is latent rather than live; it is a REAL residual and it belongs to a
--     reconciliation-arm slice, not to a cron readback.
-- ═══════════════════════════════════════════════════════════════════════════════════════════


-- ═══ §A — `sweep-settled-charges`: the mint half of the recovery chain ═════════════════════
-- Re-registration of `0080:643`, unswallowed. Identical jobname / schedule / command.
do $$
begin
  perform cron.schedule('sweep-settled-charges', '2-57/5 * * * *',
                        'select sweep_settled_without_payments()');
end $$;


-- ═══ §B — `dispatch-due-charges`: the collect half ═════════════════════════════════════════
-- Re-registration of `0080:1259`, unswallowed. Identical jobname / schedule / command.
-- ⚠ Both halves or neither. A minted `pending` row that nothing ever dispatches is the same
--   revenue outcome as a row that was never minted — the owner is not charged — and it arrives
--   through the same swallowed registration. Splitting them would leave this file asserting that
--   the chain is scheduled while checking one link of it.
do $$
begin
  perform cron.schedule('dispatch-due-charges', '4-59/5 * * * *',
                        'select dispatch_due_charges()');
end $$;


-- ═══ VERIFY — the ARTIFACT, read back from `cron.job` ══════════════════════════════════════
-- `is distinct from`, never a bare `IF` on a possibly-NULL predicate: an aggregate cannot be NULL
-- here, but the pins this repo has lost to that collapse were every one of them pins whose job was
-- to notice that something is MISSING, which is exactly this block's job.
-- The command is asserted, not only the name: a re-registration that succeeds while installing
-- something else satisfies a name-only readback. The SCHEDULE string is deliberately NOT asserted
-- (0157 §A's precedent) — a later slice may legitimately re-stagger a cadence, and a VERIFY that
-- aborts the apply over a minute offset is a gate that gets `--no-verify`'d.
do $$
declare
  v_sweep int;
  v_disp  int;
begin
  select count(*)::int into v_sweep
    from cron.job
   where jobname = 'sweep-settled-charges'
     and active
     and command = 'select sweep_settled_without_payments()';

  select count(*)::int into v_disp
    from cron.job
   where jobname = 'dispatch-due-charges'
     and active
     and command = 'select dispatch_due_charges()';

  if v_sweep is distinct from 1 or v_disp is distinct from 1 then
    raise exception '0172 VERIFY FAILED: the settle-charge recovery chain is not scheduled — expected exactly 1 active job each, found sweep-settled-charges=% dispatch-due-charges=%',
      coalesce(v_sweep::text, 'NULL'), coalesce(v_disp::text, 'NULL');
  end if;
end $$;


-- ⚠ ONE COMMENT IS RE-STATED — not a drive-by edit, and it CORRECTS a line rather than only
--   appending to it. `0116:134`'s comment says the existence predicate 「is the mint's definition,
--   not any row」, which contradicts `0116:96-106`'s own inline comment in the same file: review
--   round 2 made that predicate DELIBERATELY WIDER than the mint's, because aligning them enabled
--   a ₩15,000+₩20,000 double-charge on refund-vocabulary rows, and `151 B1 ⓒ′` pins the wider
--   form. The function is correct; its comment lagged its body. The cutover-scope sentence is
--   carried over verbatim in substance, because it is the sentence that stops a retroactive bill.
comment on function sweep_settled_without_payments is
  '0080 §G + [0116 §A] + [0172]: invariant #1 (§0-ter #1) — a booking whose run is SETTLED
(`runs.settled_at`, 0083 §0f) and has no payments row gets one, minted from the runs row''s own
end_reason/actual_km (a run missing either is SKIPPED with a notice — a money sweep does not
guess). ⚠ `settled_at`, never `ended_at` alone: after 0083 `ended_at` means the run STOPPED, and
minting on it bills an owner whose dog is still on the leash. Never `bookings.status` (§0-ter #11
/ 116 C8 — a settled booking legitimately moves to incident_review/refund_pending, so anchoring
there HIDES this crash class) and never `ledger_items` presence (0080 §K writes one for a
CANCELLED booking). "Has a row" is DELIBERATELY WIDER than the mint''s own existence check — any
kind-bearing row at all, plus confirmed/waived — because aligning the two enabled a double-charge
on refund-vocabulary rows (151 B1 ⓒ′ pins it; [0172] corrects 0116''s comment, which said the
opposite of 0116''s own body). Scoped to runs that ended at or after ops_flags.payments_live_since
(0 while null) — the flip must never bill a pilot-era run retroactively. [0172] THIS IS THE ANSWER
TO codex deploy-gate HIGH #1: settle-run''s `CHARGE LOST` path leaves exactly the state this sweep
is anchored on, measured end-to-end through end_run_tx → confirm_return_tx ×2 → this sweep. Its
cron row `sweep-settled-charges` is read back at apply by 0172''s VERIFY and pinned standing by
202 0172-S1. Pinned by 116 C9/C22/C24, 119 R10/R11, 151 B1';
