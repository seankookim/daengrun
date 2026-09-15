-- 0174_reconciliation_group_key.sql — CLAIM COMMIT 2026-09-15 (Claude): header only; body lands on this branch.
-- Wave-2 re-attack R2: arms seven and eight of payments_reconciliation() share a NULL payment_id group key (0118:1382-1385 warned) — make the invariant key arm-aware.
select 1;
