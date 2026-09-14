-- 0172_settle_charge_reconcile.sql — CLAIM COMMIT 2026-09-15 (Claude): header only; body lands on this branch.
-- codex deploy-gate HIGH #1: a settled booking whose charge intent failed to mint (settle-run CHARGE LOST path) is never charged; a flag-gated reconciliation sweep re-mints idempotently.
select 1;
