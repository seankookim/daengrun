-- ═══ 0112: a definer view has NO RLS behind it — so it must have no client DML in front ═══
--
-- ═══ §0 THE HOLE, MEASURED AS anon AGAINST PRODUCTION AND ROLLED BACK ═══
-- My own defect in 0110. `routes_public` is a SINGLE-TABLE view, therefore `is_insertable_into =
-- YES`, and the postgres default ACL hands `anon`/`authenticated` INSERT/UPDATE/DELETE on every
-- new relation. 0110 granted SELECT and never revoked the rest. Executed as `anon`, in a
-- transaction that was rolled back:
--
--     update routes_public set name = name where id = (select id from routes limit 1)
--       -> 1 ROW UPDATED
--     delete from routes_public where id = …
--       -> past privilege AND past RLS; stopped only by bookings_route_id_fkey (23503)
--
-- **A route with no bookings would have been DELETED by an anonymous caller.** Any anonymous
-- caller could also rename every course in the catalog.
--
-- ═══ §0b WHY RLS DID NOT SAVE IT — the part worth carrying ═══
-- `routes` has RLS enabled and a policy. It did not matter. **A view without
-- `security_invoker` executes against its base tables as the VIEW'S OWNER** (here `postgres`),
-- and RLS does not apply to the table owner. So the write went through the view, ran as postgres,
-- and RLS never executed. The protection everyone reasons about for `routes` is invisible from
-- this path.
--
-- That is the general rule, and it is view-specific rather than schema-wide:
--   · **a TABLE** with client DML is fine — RLS stands behind the privilege and decides per row.
--   · **a definer VIEW** with client DML has **nothing** behind the privilege.
-- So the fix is not "revoke DML broadly". **Measured before choosing: 60 of 62 base tables in
-- `public` grant client DML to `anon`, and they work precisely because RLS is behind it.** A
-- schema-wide default-privilege change would break the application while fixing nothing that this
-- file fixes. `alter default privileges … revoke insert, update, delete on tables` is therefore
-- deliberately NOT done here — it aims at the wrong object class.
--
-- ═══ §0c SCOPE — all three views, not just the one that was live ═══
-- `marketplace_open_requests` (0015) and `available_runners` (0015) carry the SAME grants. They are
-- not exploitable today only because each contains a join, which makes it non-updatable — an
-- accident of their shape, not a decision anyone made. One simplifying refactor away from live.
-- Revoking there costs nothing (no client writes through either) and removes a loaded gun.
--
-- ⚠ **The views stay DEFINER on purpose.** `security_invoker = true` would look like a fix and is
-- the wrong one for `routes_public`: after the trace revoke lands, anon will NOT hold SELECT on
-- `routes.trace`, and an invoker view would then fail for exactly the readers it exists to serve.
-- The projection must read as its owner. **That is precisely why its DML surface must be zero** —
-- definer power and client write privilege must never meet on the same object.
--
-- ═══ §0d WHAT MAKES THIS NOT RECUR ═══
-- Suite 147 carries a whole-schema watchdog in the 98-H1 shape: **no client role may hold
-- INSERT/UPDATE/DELETE on ANY view in `public`.** It enumerates rather than naming these three, so
-- the next definer view someone adds cannot be born writable — the harness reddens on creation,
-- not after an audit notices. This file fixes three objects; the pin fixes the class.

revoke insert, update, delete on routes_public             from public, anon, authenticated;
revoke insert, update, delete on marketplace_open_requests  from public, anon, authenticated;
revoke insert, update, delete on available_runners          from public, anon, authenticated;

comment on view routes_public is
  'The public read path for route geometry (0110). SELECT ONLY — 0112 revoked client INSERT/UPDATE/DELETE after anon was measured updating and deleting catalog rows straight through it. This view is DEFINER on purpose (it must out-read the caller once routes.trace is revoked), which is exactly why its DML surface must stay empty: a write through a definer view runs as the view owner and RLS on routes never executes. Never `select *` here, and never grant DML.';
