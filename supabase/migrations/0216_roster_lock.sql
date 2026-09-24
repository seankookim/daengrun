-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 0216 — the roster's ONE invariant gets ONE lock: every writer of `ops_recipients` serialises on it
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Suite: 247_roster_lock_suite.sql (tag `rlk`) — 0216-C1 · R1 · R3 · R2 · L1 · L2 · S1 · A1
--
-- DEPLOY: `supabase db push`. NO client change (the RPC's signature, returns and refusal tokens are
-- unchanged), NO edge function change (`delete-account/handler.ts` calls `delete_my_account_tx` on
-- the same contract), no cron, no secret, no enum. Two functions re-declared FROM THE CATALOG.
--
-- ─── §0 THE FINDING, AND ITS REPRODUCTION ───────────────────────────────────────────────────────
-- Codex #1 (docs/reviews/2026-09-25-server-0201-0215-codex-verdict.md, READ-based): 0208:291-304
-- guards 「the last active console operator cannot be deactivated」 by locking the TARGET row `for
-- update` and then COUNTING the others. With exactly two active `payout_due` operators X and Y,
-- X deactivating Y and Y deactivating X lock DIFFERENT rows; each count runs under READ COMMITTED
-- and sees the other's still-committed `active=true`; both pass `last_operator`; both commit; the
-- class is empty and `ops_me().is_ops` is false for every human (0208 §0d — the door that removes
-- its own handle), and every `payout_due` alert fires into nobody. 0208 ④'s comment argued the
-- row lock was 「enough … BECAUSE the count's members are rows the other transaction must itself
-- lock to change」 — true of the ROW, false of the COUNT: a `for update` on row Y does not block a
-- `select count(*)` that reads row Y.
--
-- REPRODUCED before it was fixed (the house rule for a READ finding): suite 247's R1, R3 and R2
-- were run against 0208's body — the full harness with THIS FILE ABSENT — and reddened on exactly
-- the arms the finding describes. Measured, lab A run 4 (247 present, 0216 absent): **1488 pass /
-- 6 fail** against a 1486 / 0 baseline:
--   R1  (a) session 2 NOT blocked (busy=0, wait=Client/ClientRead — it had already finished)
--       (b) result=completed(changed=true), not last_operator
--       (c) active console rows among the pair=0, X off — THE CLASS EMPTIED — journal delta=2
--   R3  the identical footprint with session 2 as Y: completed instead of not_ops, class empty
--   R2  (a) NOT blocked while the deletion of Y was open  (b) completed(changed=true)
--       (c) X off, active console operators=0, journal delta=1
--   L1 · L2 (no key held) · S1 (no key in either body) also red; C1 · A1 green — the
--   single-session guard and the ACL were never the defect.
-- And the fix, same suite, same harness, THIS FILE PRESENT (lab B run 3): **1494 / 0, exit 0.**
-- Full battery in the REGISTRY row (M1a · M1b · M1d · M2 · M3).
--
-- ─── §0b THE FIX SHAPE — one roster-wide advisory key, taken by EVERY writer, FIRST ─────────────
-- `perform pg_advisory_xact_lock(hashtextextended('ops_roster', 0));` — the house key shape (0078/
-- 0080's `mint:`/`comp:` keys, 0180's per-dog key, 0190's job key), TRANSACTION-scoped, so commit
-- or abort releases it and it can never be forgotten. ONE key for the whole roster, not per class:
-- the invariant that matters is per class (`payout_due`), but `delete_my_account_tx` removes a
-- person's rows in EVERY class in one statement, and a per-class key would make the deletion take
-- N keys in an order every other writer must then agree with — a lock-ordering contract for a table
-- with two writers and a handful of rows, buying nothing. Roster edits are human taps; deletions
-- are rare; the key is held for milliseconds.
--
-- ⚠ TAKEN BEFORE THE AUTHORIZATION READ, not merely before the count. The caller's own
--   `payout_due` row is part of the roster: a caller whose row another session is turning off must
--   see that write before deciding they may act. So `ops_roster_set` takes the key as its FIRST
--   statement — a caller turned off by a committed write gets `not_ops`, a caller who is the last
--   one gets `last_operator`, and no order of arrival produces an empty class.
-- ⚠ TAKEN AT THE TOP of `delete_my_account_tx`, not beside its roster delete (0115:590), and the
--   reason is LOCK ORDER rather than tidiness. The deletion holds row locks on the profile (and
--   much else) for its whole body; `ops_roster_set`'s upsert takes a KEY SHARE on that same profile
--   row through the 0084 FK. Advisory-then-rows in BOTH writers means neither can hold a row the
--   other needs while waiting for the key, so a deadlock is impossible by construction rather than
--   by luck — and `pg_advisory_xact_lock` WAITS, it does not fail, so a deletion is never refused
--   for a reason the customer cannot see.
-- ⚠ ANY `authenticated` caller can hold this key for the length of one refused statement (the gate
--   comes after the key). PostgREST holds no transaction across requests, so the hold is the
--   statement's own duration and a caller refused `not_ops` releases it in the same abort. Named
--   so nobody 「tidies」 it by moving the key after the gate. What that move would cost, measured
--   (247 R3; found on lab B run 1, where the PIN expected `last_operator` of the turned-off caller
--   and was wrong while the fix was right): with the key FIRST, the mutual shape — X turns Y off,
--   Y turns X off — refuses Y with `not_ops`. With the key after the gate the class still could
--   not empty, but Y, already turned off, would be refused `last_operator`: a sentence that speaks
--   to Y as if Y were still an operator. The gate is a roster read, and it is read under the
--   roster's key like every other roster read in this body.
--
-- ─── §0c EVERY WRITER OF `ops_recipients`, ENUMERATED (measured on trunk `792a16d`) ───────────
--   `grep -n 'ops_recipients\|ops_roster' supabase/migrations/*.sql | grep -iE 'update|insert|delete'`
--   · `ops_roster_set` (0208 §C) — the upsert + the journal. Re-declared in §A.
--   · `delete_my_account_tx` (0115:590, `delete from ops_recipients where profile_id = p_uid`),
--     catalog-patched by 0138 §F · 0190 §B · 0191 §A · 0202 §B② and never re-created from a file
--     since. Re-declared in §B from the catalog, with every one of those landings asserted present
--     BEFORE the copy is taken (0202's rule: a copy from a body that had lost one ships the loss).
--   · NOT writers: `ops_recipients_for` (0084 §E, a read); 0193:1324 / 0201:1041 (VERIFY blocks
--     reading `prosrc`); 0198:7 and 0208:19/37/101 (comments). No edge function touches the table
--     (`grep -rn ops_recipients supabase/functions --include='*.ts'` → 0 outside `_test`).
--   · OUTSIDE any function and therefore outside the key, named rather than hidden: Sean's psql
--     bootstrap insert (0208 §0, by construction) and the 0084 FK `on delete cascade`, reachable
--     only by a hard `delete from profiles`, which no shipped path performs (0115 tombstones).
--
-- ─── §0d WHAT 0208's TARGET-ROW LOCK STILL DOES, AND WHY IT STAYS ─────────────────────────────
-- The `for update` at 0208:291-294 is kept: it makes `v_was` — the journal's 「was it a change」 and
-- the guard's 「is this a real deactivation」 — a locked read rather than a stale one. The advisory
-- key serialises the INVARIANT; the row lock serialises the ROW. Both, and 247 S1 pins both.
--
-- ─── §0e WHY THE SUITE HAS TWO SESSIONS (233 wrote 「not built」) ──────────────────────────────
-- A lock's property is invisible to one connection. 247 creates `dblink` (contrib, measured
-- available on the harness's PG16 — `dblink.control`, `relocatable = true`) into its own schema and
-- runs the interleaving with two REAL backends over the harness's socket, observing the block in
-- `pg_stat_activity` rather than inferring it from a sleep. `90_race_check.sh` is the older two-psql
-- door and is a shared file owned by other slices; this suite owns its own second session.
--
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §A ops_roster_set — the catalog body, with the key taken FIRST
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Patched from the CATALOG, never from a file (0202 §0d's rule, and the reason is live today:
-- parallel correct-forwards 0217–0220 are in flight and a file copy taken now would erase
-- whichever of them lands on this function first). `git log -S ops_roster_set -- supabase/
-- migrations` on trunk shows 0208 as its only definer, so the landings asserted below are 0208's.
do $mig$
declare
  v_src  text;
  v_new  text;
  v_a    text;
  v_repl text;
  v_n    int;
  v_lock constant text := $l$pg_advisory_xact_lock(hashtextextended('ops_roster', 0))$l$;
begin
  select p.prosrc into v_src from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname = 'ops_roster_set';
  if v_src is null then
    raise exception '0216 §A: ops_roster_set not found — refusing to guess';
  end if;
  if position(v_lock in v_src) > 0 then
    raise exception '0216 §A: ops_roster_set already takes the roster key — this file was applied twice, or something else landed it; find out which before re-applying';
  end if;

  -- 0208's own landings this copy carries forward. Absent = something re-created the function from
  -- an older file, and the loss is already there — stop rather than carry it under our name.
  if position('ops_recipients_for(c_ops_class)' in v_src) = 0 then
    raise exception '0216 §A: 0208 §C''s gate is not in the live body — do not copy this, find out what removed it';
  end if;
  if position($e$raise exception 'last_operator'$e$ in v_src) = 0 then
    raise exception '0216 §A: 0208 §0d''s last_operator refusal is not in the live body';
  end if;
  if position('on conflict on constraint ops_recipients_pkey' in v_src) = 0 then
    raise exception '0216 §A: 0208 §C''s upsert-by-constraint is not in the live body';
  end if;
  if position('insert into ops_roster_changes' in v_src) = 0 then
    raise exception '0216 §A: 0208 §A''s journal write is not in the live body';
  end if;

  -- ── anchor 1: the top of the body. The key is the FIRST statement (§0b). ────────────────────
  v_a := $a$begin
  -- ① GATE FIRST, argument-blind (see the header).$a$;
  v_repl := $a$begin
  -- 🔴 [0216 §A] THE ROSTER-WIDE KEY, FIRST — before the authorization read, before the count.
  --    0208 ④ locked the TARGET row and then counted the others; two deactivations of the last two
  --    operators lock different rows and each count sees the other's committed active=true, so
  --    both passed (Codex #1, reproduced in 247 R1). A `for update` on a row does not block a
  --    `count(*)` that reads it; only a key every writer takes serialises a shared invariant.
  --    Transaction-scoped: released by commit or abort, never forgotten. `delete_my_account_tx`
  --    takes the same key at its top (0216 §B), so the deletion of one of the last two operators
  --    and the deactivation of the other cannot interleave either.
  perform pg_advisory_xact_lock(hashtextextended('ops_roster', 0));
  -- ① GATE FIRST, argument-blind (see the header).$a$;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  if v_n is distinct from 1 then
    raise exception '0216 §A: the top-of-body anchor occurs % time(s) in ops_roster_set, expected exactly 1 — patch by hand', v_n;
  end if;
  v_new := replace(v_src, v_a, v_repl);

  -- ── anchor 2: 0208 ④'s comment claimed the row lock was enough. Inside the deployed body that
  --    sentence is now false, and a body that argues against its own fix is the comment-quoting
  --    class one step removed. Replaced with what the row lock still does (§0d). ─────────────────
  v_a := $a$  -- ④ LOCK the roster row (if any) before the last-operator count is taken, so two terminals
  --    deactivating the two last operators cannot both observe 「there is another one」 and both
  --    succeed. `for update` on the target row plus a count over the others is enough here
  --    BECAUSE the only transition the guard forbids is a DEACTIVATION, and the count's members
  --    are rows the other transaction must itself lock to change.$a$;
  v_repl := $a$  -- ④ LOCK the roster row (if any) — this serialises the ROW: `v_was` below is a locked read,
  --    so 「was this a change」 (the journal) and 「is this a real deactivation」 (the guard) cannot
  --    be stale. It does NOT serialise the count (0208 believed it did — Codex #1): two
  --    deactivations of the last two operators lock different rows and each count still sees the
  --    other's committed active=true. The roster-wide key at the top of this body (0216 §A) is
  --    what serialises the INVARIANT; this lock stays for the row.$a$;
  v_n := (length(v_new) - length(replace(v_new, v_a, ''))) / length(v_a);
  if v_n is distinct from 1 then
    raise exception '0216 §A: 0208 ④''s comment anchor occurs % time(s) in ops_roster_set, expected exactly 1 — patch by hand', v_n;
  end if;
  v_new := replace(v_new, v_a, v_repl);

  if v_new = v_src then raise exception '0216 §A: patch did not apply'; end if;
  if position(v_lock in v_new) = 0 then raise exception '0216 §A: the patch did not land the key'; end if;
  if position(v_lock in v_new) > position('ops_recipients_for(c_ops_class)' in v_new) then
    raise exception '0216 §A: the key landed AFTER the authorization read';
  end if;

  -- the declaration is 0208:231-234's, verbatim
  execute format(
    'create or replace function ops_roster_set(p_profile uuid, p_event_class text, p_active boolean) returns table (profile_id uuid, event_class text, active boolean, changed boolean) language plpgsql security definer set search_path = public, pg_temp as %L',
    v_new);

  -- the comment: 0208's own, kept from the catalog, with this file's paragraph appended
  execute format('comment on function ops_roster_set(uuid, text, boolean) is %L',
    coalesce((select obj_description(p.oid, 'pg_proc') from pg_proc p
               join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
              where p.proname = 'ops_roster_set'), '')
    || chr(10) || '[0216 §A] Roster-wide advisory key pg_advisory_xact_lock(hashtextextended(''ops_roster'', 0)) '
    || 'taken FIRST — before the gate and before the last-operator count. 0208 ④''s target-row lock '
    || 'serialised the row, not the count: two deactivations of the last two console operators each '
    || 'counted the other''s committed row and both passed (Codex #1, 2026-09-25; reproduced in 247 R1). '
    || 'delete_my_account_tx takes the same key at its top (0216 §B). Signature, returns and tokens unchanged.');
end $mig$;

-- 0208:337-338's ACL restated — a `create or replace` on an absent-function path is a plain CREATE,
-- and a SECURITY DEFINER born PUBLIC-executable is the worst shape this repo makes.
revoke execute on function ops_roster_set(uuid, text, boolean) from public, anon;
grant  execute on function ops_roster_set(uuid, text, boolean) to authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- §B delete_my_account_tx — the catalog body, with the same key at its TOP
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- The second writer (§0c). Patched from the CATALOG exactly as 0202 §B② did, and for the same
-- reason: four files have patched this body in place and a copy from any FILE would ship the loss
-- of the other three. Every inherited landing is asserted — COUNTED where 0191 made counting the
-- rule — before the copy is taken.
do $mig$
declare
  v_src  text;
  v_new  text;
  v_a    text;
  v_repl text;
  v_n    int;
  v_lock constant text := $l$pg_advisory_xact_lock(hashtextextended('ops_roster', 0))$l$;
begin
  select p.prosrc into v_src from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname = 'delete_my_account_tx';
  if v_src is null then
    raise exception '0216 §B: delete_my_account_tx not found — refusing to guess';
  end if;
  if position(v_lock in v_src) > 0 then
    raise exception '0216 §B: delete_my_account_tx already takes the roster key — this file was applied twice, or something else landed it; find out which before re-applying';
  end if;

  -- inherited landings — 0202 §B②'s three, plus 0202's own
  if position($e$perform enqueue_billing_key_revocation(p_uid, 'account_deleted');$e$ in v_src) = 0 then
    raise exception '0216 §B: 0138 §F''s revocation enqueue is not in the live body — do not copy this, find out what removed it';
  end if;
  if position($e$where runner_id = p_uid and paid_payout_id is null$e$ in v_src) = 0 then
    raise exception '0216 §B: 0190 §B''s paid-marker retention predicate is not in the live body — do not copy this, find out what removed it';
  end if;
  v_a := $e$using detail = coalesce(v_block_id::text, '')$e$;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  if v_n is distinct from 9 then
    raise exception '0216 §B: 0191 §A''s detail arms occur % time(s) in the live body, expected exactly 9 — patch by hand', v_n;
  end if;
  if position($e$update gear_claims set delivery = '{"redacted": true}'::jsonb$e$ in v_src) = 0 then
    raise exception '0216 §B: 0202 §B②''s delivery redaction is not in the live body — do not copy this, find out what removed it';
  end if;
  -- the roster delete itself — the statement this key exists for
  v_a := $e$  with d as (delete from ops_recipients where profile_id = p_uid returning 1)$e$;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  if v_n is distinct from 1 then
    raise exception '0216 §B: 0115:590''s roster delete occurs % time(s) in the live body, expected exactly 1', v_n;
  end if;

  -- ── the anchor: the party gate, the FIRST executable statement of the body (0115:216-218). The
  --    key goes in front of it (§0b: advisory before any row read or lock, in both writers). ──────
  v_a := $a$  if p_uid is null then
    raise exception 'not_authenticated';
  end if;$a$;
  v_repl := $a$  -- 🔴 [0216 §B] THE ROSTER-WIDE KEY, AT THE TOP — before any row of this deletion is read or
  --    locked. This transaction deletes the profile's `ops_recipients` rows (0115 §F ④, below) and
  --    is therefore the SECOND writer of the roster: without the key, a deactivation of the other
  --    last console operator counts this profile's still-committed row, passes, and the class is
  --    empty once both commit (Codex #1, reproduced in 247 R2). Taken HERE rather than beside the
  --    delete for LOCK ORDER: `ops_roster_set` takes advisory-then-rows, so this body must too, or
  --    the profile row this transaction holds and the FK KEY SHARE that body needs could deadlock.
  --    `pg_advisory_xact_lock` waits rather than fails, so a deletion is never refused for it.
  perform pg_advisory_xact_lock(hashtextextended('ops_roster', 0));
  if p_uid is null then
    raise exception 'not_authenticated';
  end if;$a$;
  v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
  if v_n is distinct from 1 then
    raise exception '0216 §B: the party-gate anchor occurs % time(s) in delete_my_account_tx, expected exactly 1 — patch by hand', v_n;
  end if;
  v_new := replace(v_src, v_a, v_repl);
  if v_new = v_src then raise exception '0216 §B: patch did not apply'; end if;
  if position(v_lock in v_new) > position('from profiles where id = p_uid' in v_new) then
    raise exception '0216 §B: the key landed AFTER the first profile read — not at the top';
  end if;

  -- the declaration is 0202:392's, verbatim
  execute format(
    'create or replace function delete_my_account_tx(p_uid uuid) returns jsonb language plpgsql volatile security definer set search_path = public, pg_temp as %L',
    v_new);

  execute format('comment on function delete_my_account_tx(uuid) is %L',
    coalesce((select obj_description(p.oid, 'pg_proc') from pg_proc p
               join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
              where p.proname = 'delete_my_account_tx'), '')
    || chr(10) || '[0216 §B] Takes the roster-wide advisory key pg_advisory_xact_lock(hashtextextended(''ops_roster'', 0)) '
    || 'as its FIRST statement, before any row is read or locked, because this transaction deletes the '
    || 'profile''s ops_recipients rows and is the roster''s second writer (Codex #1, 2026-09-25; 247 R2). '
    || 'At the top for lock order (advisory-then-rows in both writers); the key waits, it never refuses.');
end $mig$;

-- 0115:645-648 / 0138 §F / 0190 §B / 0191 §A / 0202 §B②'s ACL restated (same reason as §A).
revoke execute on function delete_my_account_tx(uuid) from public, anon, authenticated;
grant  execute on function delete_my_account_tx(uuid) to service_role;

-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- VERIFY — the shape, at apply time
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ⚠ This block and 247 S1/A1 check overlapping things ON PURPOSE and neither is evidence for the
--   other: a property checked only at apply is protected exactly until someone recreates the
--   function (0131-G4), and a suite pin cannot abort a bad apply. Source arms read COMMENT-STRIPPED
--   `prosrc` — this file explains the key at length inside the very bodies it patches, and an
--   un-stripped match would be satisfied by that prose.
do $verify$
declare
  v_bad  text := '';
  v_src  text;
  v_oid  oid;
  v_lock constant text := $l$pg_advisory_xact_lock(hashtextextended('ops_roster', 0))$l$;
begin
  -- ops_roster_set
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'ops_roster_set';
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(ops_roster_set);';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is not true then v_bad := v_bad || ' ops_roster_set: not definer;'; end if;
    if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ops_roster_set: no in-body search_path;'; end if;
    if has_function_privilege('anon', v_oid, 'execute') is not false then v_bad := v_bad || ' ops_roster_set: open to anon;'; end if;
    if has_function_privilege('authenticated', v_oid, 'execute') is not true then v_bad := v_bad || ' ops_roster_set: closed to authenticated;'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(ops_roster_set);';
    else
      if position(v_lock in v_src) = 0 then v_bad := v_bad || ' ops_roster_set: no roster key;';
      else
        if (position(v_lock in v_src) < position('ops_recipients_for(c_ops_class)' in v_src)) is not true
          then v_bad := v_bad || ' ops_roster_set: key not before the gate;'; end if;
        if (position(v_lock in v_src) < position('count(*)' in v_src)) is not true
          then v_bad := v_bad || ' ops_roster_set: key not before the count;'; end if;
      end if;
      if position('for update' in v_src) = 0 then v_bad := v_bad || ' ops_roster_set: 0208 ④ row lock gone;'; end if;
      if position($e$raise exception 'last_operator'$e$ in v_src) = 0 then v_bad := v_bad || ' ops_roster_set: last_operator gone;'; end if;
    end if;
  end if;

  -- delete_my_account_tx
  select p.oid into v_oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'delete_my_account_tx';
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(delete_my_account_tx);';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is not true then v_bad := v_bad || ' delete_my_account_tx: not definer;'; end if;
    if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' delete_my_account_tx: no in-body search_path;'; end if;
    if has_function_privilege('anon', v_oid, 'execute') is not false then v_bad := v_bad || ' delete_my_account_tx: open to anon;'; end if;
    if has_function_privilege('authenticated', v_oid, 'execute') is not false then v_bad := v_bad || ' delete_my_account_tx: open to authenticated;'; end if;
    if has_function_privilege('service_role', v_oid, 'execute') is not true then v_bad := v_bad || ' delete_my_account_tx: closed to service_role;'; end if;
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src from pg_proc where oid = v_oid;
    if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(delete_my_account_tx);';
    else
      if position(v_lock in v_src) = 0 then v_bad := v_bad || ' delete_my_account_tx: no roster key;';
      else
        if (position(v_lock in v_src) < position('from profiles where id = p_uid' in v_src)) is not true
          then v_bad := v_bad || ' delete_my_account_tx: key not at the top;'; end if;
        if (position(v_lock in v_src) < position('delete from ops_recipients' in v_src)) is not true
          then v_bad := v_bad || ' delete_my_account_tx: key not before the roster delete;'; end if;
      end if;
      if position('delete from ops_recipients' in v_src) = 0 then v_bad := v_bad || ' delete_my_account_tx: roster delete gone;'; end if;
      if position($e$enqueue_billing_key_revocation(p_uid, 'account_deleted')$e$ in v_src) = 0 then v_bad := v_bad || ' delete_my_account_tx: 0138 landing gone;'; end if;
      if position('where runner_id = p_uid and paid_payout_id is null' in v_src) = 0 then v_bad := v_bad || ' delete_my_account_tx: 0190 landing gone;'; end if;
      if position('update gear_claims set delivery' in v_src) = 0 then v_bad := v_bad || ' delete_my_account_tx: 0202 landing gone;'; end if;
    end if;
  end if;

  if v_bad <> '' then raise exception '0216 VERIFY failed:%', v_bad; end if;
end $verify$;
