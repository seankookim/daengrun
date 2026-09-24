-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- 247 — 0216: the roster invariant is serialised by ONE lock, and a SECOND SESSION proves it
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
-- Tag `rlk`. Pins 0216-C1 · R1 · R3 · R2 · L1 · L2 · S1 · A1 (in run order).
--
-- Codex finding #1 (2026-09-25 server review, READ-based): 0208:291-304 guarded 「the last console
-- operator cannot be turned off」 with a plain COUNT after locking only the TARGET row. Two
-- deactivations of the last two operators lock DIFFERENT rows, each count sees the other's still
-- committed `active=true` row, both pass, both commit, the class is empty. REPRODUCED here before it
-- was fixed: R1, R3 and R2 below run against 0208's body (the harness with 0216 absent) and redden
-- on exactly the arms the finding describes — the measurement is in the REGISTRY row and 0216 §0.
--
-- ─── WHAT EACH PIN ESTABLISHES, WITHOUT REFERENCE TO ANY MUTATION ───
--  · **0216-C1** — single-session CONTROL: with exactly one active console operator, turning them
--        off raises `last_operator` and the row is unchanged. That is 0208 §0d's guard, which 0216
--        does not touch; it is here so a red R1/R2 can never be misread as 「the guard is gone」.
--  · **0216-R1** — TWO SESSIONS, both `ops_roster_set`. World = exactly two active console operators
--        X and Y. Session 1 (as X) deactivates Y and HOLDS its transaction open. Session 2 (as X, on
--        a second terminal — 0208 ④'s own 「two terminals」) deactivates X, a DIFFERENT target row,
--        and (a) BLOCKS — its backend reads `wait_event_type='Lock', wait_event='advisory'` in
--        `pg_stat_activity` while 1 is open; (b) after 1 commits it completes with `last_operator`;
--        (c) end state: exactly one active console row among the pair (Y off, X on) and the
--        journal grew by exactly ONE row (a refusal writes nothing). On 0208's body session 2 does
--        not block, both commit, the class is EMPTY, the journal grew by two.
--  · **0216-R3** — the MUTUAL shape, and why the key sits BEFORE the authorization read: session 1
--        (as X) deactivates Y and holds; session 2 (as Y) deactivates X. It blocks the same way, and
--        once 1 commits it is refused `not_ops` — Y's own row was turned off by a committed write,
--        and the gate, read under the same key, says so — never `last_operator` (a sentence that
--        would speak to Y as if Y were still an operator) and never success. End state as R1.
--        On 0208's body both succeed and the class is empty. ⚠ Measured lab B run 1: R1 was first
--        written in this shape expecting `last_operator` and reddened with `not_ops` — the pin was
--        wrong and the fix was right; this pin is that correction, kept as its own property.
--  · **0216-R2** — TWO SESSIONS, the OTHER writer. Session 1 runs `delete_my_account_tx(Y)` and
--        holds it open; session 2 (as X) deactivates X — the same three arms: blocked on the same
--        advisory key, `last_operator` once Y's row is gone, X still on and Y's row gone. On a body
--        where deletion does not take the lock, 2's count sees Y's committed active row, X goes
--        off, then Y's row is deleted: empty.
--  · **0216-L1 / L2** — `pg_locks` for THIS backend, one transaction each: the roster key is not
--        held BEFORE the call and IS held AFTER (classid/objid = the 64-bit key split, objsubid 1).
--        L1 through `ops_roster_set` on a call that changes nothing (`changed=false`, no journal
--        row) — the lock is taken FIRST, not only when a row would move; L2 through
--        `delete_my_account_tx` on a bare profile that is not on the roster at all — the lock is
--        taken at the TOP of the deletion, not beside the roster delete.
--  · **0216-S1** — the deployed source, COMMENT-STRIPPED, each function with a NO-SOURCE arm and a
--        raw>stripped control: in `ops_roster_set` the lock call precedes the authorization read
--        (`ops_recipients_for(c_ops_class)`) AND the count (`count(*)`), and 0208's target-row
--        `for update` and `on conflict on constraint` are still there (the lock ADDS to them); in
--        `delete_my_account_tx` it precedes the first `profiles` read (lock order: advisory before
--        any row lock, in both writers) and the `delete from ops_recipients`; and the four inherited
--        landings 0216 §B re-copied (0138 · 0190 · 0191 × 9, counted · 0202) are all still in the
--        catalog copy.
--  · **0216-A1** — shape and ACL of both re-declared functions (definer, in-body `search_path`,
--        `ops_roster_set` closed to anon / open to authenticated, `delete_my_account_tx` closed to
--        anon + authenticated / open to service_role). ⚠ This block is LAST and therefore also
--        carries the world's RESTORE with a control on it (see fixture note ①).
--
-- ─── HOW A SECOND SESSION EXISTS HERE (233 wrote 「not built」; this is it) ───
-- `dblink` — contrib, shipped with the PG16 the harness runs on (measured: `dblink.control` in
-- share/postgresql@16/extension, `relocatable = true`) — is created into a suite-owned schema
-- `_rlk`, so nothing lands in `public` for a later definer sweep to meet. Each named connection is
-- a REAL second backend over the harness's own unix socket (`unix_socket_directories` + `port`
-- read from the server, never assumed). The suite's own `do` block never touches the rows the two
-- backends fight over inside the same transaction: every fixture write is COMMITTED in its own
-- statement first, because 「the world is exactly two」 has to be committed to be visible to them.
-- Blocking is OBSERVED (`pg_stat_activity.wait_event`), not inferred from a sleep; every backend
-- carries a `statement_timeout`, so a wrong lock can only redden, never hang the harness; and both
-- backends are disconnected on every path, so an aborted transaction rolls back rather than
-- holding a lock into the next suite.
-- ⚠ If `dblink` is ever absent, `create extension` FAILS and `harness.sh` stops loudly
--   (ON_ERROR_STOP). A missing second session is not a green.
--
-- ─── NAMED GAPS (facts about the system, written as prose because no pin can reach them) ───
--  · psql writes (Sean's bootstrap insert, 0208 §0) and a hard `delete from profiles` (the 0084
--    FK cascade) change the roster outside any function and therefore outside the lock. No shipped
--    path does either — `delete_my_account_tx` tombstones — and a pin cannot forbid what a
--    superuser types.
--  · **M3 (the ACL restatement deleted from 0216) does NOT redden A1 here.** In this harness the
--    function already exists when 0216 re-declares it, so `create or replace` preserves the ACL
--    and A1 stays green. That class belongs to `check-definer-acl.mjs` (source); 0216's battery
--    runs it against the mutated copy. Neither is evidence for the other.
--  · The lock is `pg_advisory_xact_lock` — TRANSACTION scope — and `pg_locks` does not say which
--    scope an advisory lock has. L1/L2 prove it is HELD; S1 proves it is the xact form BY NAME.
--
-- ─── FIXTURE NOTES ───
--  ① `ops_recipients` is SHARED: eleven suites seat `payout_due` operators. Every other active
--     console row is SAVED and neutralised (committed) before the races and RESTORED at the end,
--     with a control on both ends (239 ②'s idiom) — reading a `last_operator` on a world that
--     merely happened to be empty is the fixture-agreement failure this house has met three times.
--  ② X and Y are this suite's own `rlk_*` profiles. Y and Z are BARE runners (a profile and a
--     `runners` row, nothing else) so `delete_my_account_tx`'s twelve gates pass and R2/L2 measure
--     the lock rather than a refusal (233 ④).
--  ③ Every journal assertion is a DELTA the pin caused. Every count of console rows is scoped to
--     the pair where the pair is what is being asserted.
--  ④ Cross-statement state (X, Y, Z, the saved set) travels in a TEMP table this psql session owns;
--     the dblink backends never need it — every uuid they need is passed inline.
--  ⑤ 🔴 EVERY RACE PIN'S PREMISE IS SET BY A FIXTURE STATEMENT OF ITS OWN, COMMITTED IMMEDIATELY
--     BEFORE IT (a superuser UPDATE on the table, exactly how the seat itself is made) — never by
--     the previous pin's end state and never through the door under test. Measured lab A run 3 /
--     M1b run 2: on a body where R1 empties the class, everything after it — C1, R3, R2, L1 and
--     the suite's own re-seat — got `not_ops`, so five pins reddened for PREMISE reasons and what
--     each of them measures was invisible. A pin that inherits another pin's outcome is testing
--     that outcome (`175 V2`); with ⑤ each pin reddens on ITS arms or not at all, and a mutation's
--     footprint is the set of properties it breaks rather than the set of pins after the first.
--
-- ─── MUTATION MAP — measured against these exact files ───
-- In the REGISTRY row (0216). Lab: a copy of `supabase/` OUTSIDE the worktree with `.pgtest`
-- excluded, every plant assert-verified and `&&`-chained to its harness run.
set client_min_messages = warning;

create schema if not exists _rlk;
create extension if not exists dblink with schema _rlk;

create temp table _rlk_fx (k text primary key, v text);

-- the harness's own socket: read from the server so a hashed fallback dir (harness.sh:45-49) is
-- still the right one.
create or replace function _rlk.connstr() returns text language sql stable as $$
  select format('host=%s port=%s dbname=%s user=%s',
                current_setting('unix_socket_directories'), current_setting('port'),
                current_database(), current_user)
$$;

-- the 64-bit key exactly as 0216 takes it, and the `pg_locks` count for THIS backend (211 ②'s
-- encoding: classid = k >> 32, objid = k & 0xFFFFFFFF, objsubid = 1)
create or replace function _rlk.held() returns int language sql stable as $$
  select count(*)::int from pg_locks l
   where l.locktype = 'advisory' and l.granted and l.pid = pg_backend_pid()
     and l.objsubid = 1
     and l.classid = ((hashtextextended('ops_roster', 0) >> 32) & 4294967295)::oid
     and l.objid   = ( hashtextextended('ops_roster', 0)        & 4294967295)::oid
$$;

create or replace procedure _rlk.drop_conns() language plpgsql as $$
begin
  if 'rlk1' = any(coalesce(_rlk.dblink_get_connections(), '{}'::text[]))
    then perform _rlk.dblink_disconnect('rlk1'); end if;
  if 'rlk2' = any(coalesce(_rlk.dblink_get_connections(), '{}'::text[]))
    then perform _rlk.dblink_disconnect('rlk2'); end if;
end $$;

-- ═════════════════════════════════════════════════════════════════
-- FIXTURE — committed in its own statement (④), before any second backend looks
-- ═════════════════════════════════════════════════════════════════
do $rlk$
declare
  ox uuid; oy uuid; oz uuid;
  v_saved uuid[];
  v_tag text := substr(gen_random_uuid()::text, 1, 8);
begin
  ox := t_user('rlk_x_' || v_tag, 'owner');
  oy := t_user('rlk_y_' || v_tag, 'runner');
  oz := t_user('rlk_z_' || v_tag, 'runner');
  insert into ops_recipients (profile_id, event_class, active)
  values (ox, 'payout_due', true), (oy, 'payout_due', true);
  -- ① save + neutralise every OTHER active console operator
  select coalesce(array_agg(r.profile_id), '{}'::uuid[]) into v_saved
    from ops_recipients r
   where r.event_class = 'payout_due' and r.active and r.profile_id not in (ox, oy);
  update ops_recipients set active = false
   where event_class = 'payout_due' and profile_id = any(v_saved);
  insert into _rlk_fx values ('ox', ox::text), ('oy', oy::text), ('oz', oz::text),
                             ('saved', v_saved::text);
end $rlk$;

-- ═════════════════════════════════════════════════════════════════
-- [0216-R1] TWO SESSIONS, TWO DEACTIVATIONS OF THE LAST TWO OPERATORS — the reproduction, fixed
-- ═════════════════════════════════════════════════════════════════
do $rlk$
declare
  ox uuid := (select v::uuid from _rlk_fx where k = 'ox');
  oy uuid := (select v::uuid from _rlk_fx where k = 'oy');
  v_conn text := _rlk.connstr();
  v_bad text := '';
  v_n int; v_j0 int; v_i int;
  v_pid2 int; v_busy int;
  v_wet text; v_we text;
  v_changed boolean;
  v_msg text;
begin
  -- CONTROL ①: the world really is exactly two (committed by the fixture statement)
  select count(*)::int into v_n from ops_recipients r where r.event_class = 'payout_due' and r.active;
  if v_n is distinct from 2
    then v_bad := v_bad || ' control: active console operators=' || v_n || ' (expected 2 — the premise)'; end if;
  select count(*)::int into v_j0 from ops_roster_changes;

  call _rlk.drop_conns();
  begin
    perform _rlk.dblink_connect('rlk1', v_conn);
    perform _rlk.dblink_connect('rlk2', v_conn);
    perform _rlk.dblink_exec('rlk1', $q$set statement_timeout = '10s'$q$);
    perform _rlk.dblink_exec('rlk2', $q$set statement_timeout = '10s'$q$);
    select t.pid into v_pid2 from _rlk.dblink('rlk2', 'select pg_backend_pid()') as t(pid int);

    -- session 1: as X, deactivate Y — and HOLD
    perform _rlk.dblink_exec('rlk1', 'begin');
    perform _rlk.dblink_exec('rlk1', format('set local request.jwt.claim.sub = %L', ox::text));
    select t.changed into v_changed
      from _rlk.dblink('rlk1', format($q$select changed from ops_roster_set(%L::uuid, 'payout_due', false)$q$, oy::text)) as t(changed boolean);
    if v_changed is not true
      then v_bad := v_bad || ' session 1: deactivating Y did not report changed=true'; end if;

    -- session 2: X AGAIN, on a second terminal (0208 ④'s own words: 「two terminals」), deactivating
    -- X — a DIFFERENT target row from session 1's. ASYNC. It must block.
    -- (The mutual shape — session 2 as Y — is R3: it blocks the same way and is refused `not_ops`,
    --  because the gate is read under the key too. Measured lab B run 1, where THIS pin expected
    --  `last_operator` of Y and was wrong; the fix was right.)
    perform _rlk.dblink_exec('rlk2', 'begin');
    perform _rlk.dblink_exec('rlk2', format('set local request.jwt.claim.sub = %L', ox::text));
    if _rlk.dblink_send_query('rlk2', format($q$select changed from ops_roster_set(%L::uuid, 'payout_due', false)$q$, ox::text)) <> 1
      then v_bad := v_bad || ' send_query to session 2 failed'; end if;

    -- (a) BLOCKED — poll up to 3 s for the backend to be waiting on an ADVISORY lock, or to finish
    v_i := 0; v_we := null; v_wet := null; v_busy := null;
    loop
      perform pg_sleep(0.1); v_i := v_i + 1;
      v_busy := _rlk.dblink_is_busy('rlk2');
      select a.wait_event_type, a.wait_event into v_wet, v_we from pg_stat_activity a where a.pid = v_pid2;
      exit when v_busy = 0 or (v_wet = 'Lock' and v_we = 'advisory') or v_i >= 30;
    end loop;
    if v_busy is distinct from 1 then
      v_bad := v_bad || ' 🔴 (a) session 2 was NOT blocked while session 1 held its deactivation open (busy='
               || coalesce(v_busy::text, 'null') || ' wait=' || coalesce(v_wet, '∅') || '/' || coalesce(v_we, '∅') || ')';
    elsif (v_wet = 'Lock' and v_we = 'advisory') is not true then
      v_bad := v_bad || ' (a) session 2 is busy but not waiting on an advisory lock (wait='
               || coalesce(v_wet, '∅') || '/' || coalesce(v_we, '∅') || ')';
    end if;

    -- release: session 1 commits its deactivation of Y
    perform _rlk.dblink_exec('rlk1', 'commit');

    -- (b) session 2 now completes — and must REFUSE by name
    v_msg := null;
    begin
      select t.changed into v_changed from _rlk.dblink_get_result('rlk2') as t(changed boolean);
      v_msg := 'completed(changed=' || coalesce(v_changed::text, 'null') || ')';
      -- dblink's async protocol: get_result is called AGAIN until it returns no rows, which clears
      -- the connection's async state — without this the commit below is refused with 「another
      -- command is already in progress」 (measured, lab A run 2).
      perform * from _rlk.dblink_get_result('rlk2') as t(changed boolean);
      -- a completed write is COMMITTED, as the real caller's would be: arm (c) must see what the
      -- product would have seen, never a rollback the scaffolding performed. (On the fixed body
      -- the call raises, the transaction is already aborted, and nothing commits.)
      perform _rlk.dblink_exec('rlk2', 'commit');
    exception when others then v_msg := sqlerrm;
    end;
    if (v_msg like '%last_operator%') is not true
      then v_bad := v_bad || ' 🔴 (b) session 2 result=' || coalesce(v_msg, '(null)') || ' (expected last_operator)'; end if;
  exception when others then
    v_bad := v_bad || ' 🔴 race scaffolding raised: ' || sqlerrm;
  end;
  -- always tear both backends down (an aborted transaction in rlk2 rolls back on disconnect)
  call _rlk.drop_conns();

  -- (c) end state, read after both backends are gone
  select count(*)::int into v_n from ops_recipients r
   where r.event_class = 'payout_due' and r.active and r.profile_id in (ox, oy);
  if v_n is distinct from 1
    then v_bad := v_bad || ' 🔴 (c) active console rows among the pair=' || v_n || ' (expected 1)'; end if;
  if (select r.active from ops_recipients r where r.profile_id = oy and r.event_class = 'payout_due') is not false
    then v_bad := v_bad || ' (c) Y is not off (session 1 committed it)'; end if;
  if (select r.active from ops_recipients r where r.profile_id = ox and r.event_class = 'payout_due') is not true
    then v_bad := v_bad || ' 🔴 (c) X is not on — the refused deactivation LANDED'; end if;
  select count(*)::int into v_n from ops_roster_changes;
  if (v_n - v_j0) is distinct from 1
    then v_bad := v_bad || ' (c) journal delta=' || (v_n - v_j0) || ' (expected 1: a refusal writes nothing)'; end if;

  if v_bad = '' then
    call _pass('rlk', '0216-R1 two sessions, two deactivations of the LAST TWO console operators: the second BLOCKS on the roster advisory lock while the first holds its deactivation open (observed in pg_stat_activity), completes with last_operator once the first commits, leaves X on and Y off, and the journal grew by exactly one row');
  else
    call _fail('rlk', '0216-R1 two sessions, two deactivations of the last two operators', v_bad);
  end if;
end $rlk$;

-- FIXTURE (⑤): C1's premise, set and COMMITTED in its own statement — exactly one console
-- operator, X. On a body where R1 emptied the class, this is what stops R1's red from cascading
-- into C1 as a premise failure: C1 reddens on ITS arms or not at all.
update ops_recipients r set active = (f.k = 'ox')
  from _rlk_fx f
 where f.k in ('ox', 'oy') and r.profile_id = f.v::uuid and r.event_class = 'payout_due';

-- ═════════════════════════════════════════════════════════════════
-- [0216-C1] SINGLE-SESSION CONTROL — the guard 0216 did not touch still refuses
-- ═════════════════════════════════════════════════════════════════
do $rlk$
declare
  ox uuid := (select v::uuid from _rlk_fx where k = 'ox');
  oy uuid := (select v::uuid from _rlk_fx where k = 'oy');
  v_bad text := '';
  v_msg text; v_n int;
begin
  -- CONTROL ①: exactly one active console operator, X (set by the fixture statement above, committed)
  select count(*)::int into v_n from ops_recipients r where r.event_class = 'payout_due' and r.active;
  if v_n is distinct from 1
    then v_bad := v_bad || ' control: active console operators=' || v_n || ' (expected 1 — the premise)'; end if;

  perform set_config('request.jwt.claim.sub', ox::text, false);
  begin
    perform * from ops_roster_set(ox, 'payout_due', false);
    v_msg := 'no refusal';
  exception when others then v_msg := sqlerrm;
  end;
  perform set_config('request.jwt.claim.sub', '', false);
  if v_msg is distinct from 'last_operator'
    then v_bad := v_bad || ' 🔴 the last operator turning themselves off got=' || coalesce(v_msg, '(null)'); end if;
  if (select r.active from ops_recipients r where r.profile_id = ox and r.event_class = 'payout_due') is not true
    then v_bad := v_bad || ' 🔴 refused, but the row changed'; end if;

  if v_bad = '' then
    call _pass('rlk', '0216-C1 single-session control: with exactly one active console operator, turning them off raises last_operator and the row is unchanged (0208 §0d, untouched by 0216)');
  else
    call _fail('rlk', '0216-C1 single-session control', v_bad);
  end if;
end $rlk$;

-- FIXTURE (⑤): R3's premise, committed — both X and Y on.
update ops_recipients r set active = true
  from _rlk_fx f
 where f.k in ('ox', 'oy') and r.profile_id = f.v::uuid and r.event_class = 'payout_due';

-- ═════════════════════════════════════════════════════════════════
-- [0216-R3] THE MUTUAL SHAPE — X turns Y off, Y turns X off: the gate is read under the key too
-- ═════════════════════════════════════════════════════════════════
do $rlk$
declare
  ox uuid := (select v::uuid from _rlk_fx where k = 'ox');
  oy uuid := (select v::uuid from _rlk_fx where k = 'oy');
  v_conn text := _rlk.connstr();
  v_bad text := '';
  v_n int; v_j0 int; v_i int;
  v_pid2 int; v_busy int;
  v_wet text; v_we text;
  v_changed boolean;
  v_msg text;
begin
  -- CONTROL ①: exactly two (set by the fixture statement above, committed)
  select count(*)::int into v_n from ops_recipients r where r.event_class = 'payout_due' and r.active;
  if v_n is distinct from 2
    then v_bad := v_bad || ' control: active console operators=' || v_n || ' (expected 2 — the premise)'; end if;
  select count(*)::int into v_j0 from ops_roster_changes;

  call _rlk.drop_conns();
  begin
    perform _rlk.dblink_connect('rlk1', v_conn);
    perform _rlk.dblink_connect('rlk2', v_conn);
    perform _rlk.dblink_exec('rlk1', $q$set statement_timeout = '10s'$q$);
    perform _rlk.dblink_exec('rlk2', $q$set statement_timeout = '10s'$q$);
    select t.pid into v_pid2 from _rlk.dblink('rlk2', 'select pg_backend_pid()') as t(pid int);

    -- session 1: as X, deactivate Y — and HOLD
    perform _rlk.dblink_exec('rlk1', 'begin');
    perform _rlk.dblink_exec('rlk1', format('set local request.jwt.claim.sub = %L', ox::text));
    select t.changed into v_changed
      from _rlk.dblink('rlk1', format($q$select changed from ops_roster_set(%L::uuid, 'payout_due', false)$q$, oy::text)) as t(changed boolean);
    if v_changed is not true
      then v_bad := v_bad || ' session 1: deactivating Y did not report changed=true'; end if;

    -- session 2: as Y — the operator session 1 is turning off — deactivate X. ASYNC. It must block.
    perform _rlk.dblink_exec('rlk2', 'begin');
    perform _rlk.dblink_exec('rlk2', format('set local request.jwt.claim.sub = %L', oy::text));
    if _rlk.dblink_send_query('rlk2', format($q$select changed from ops_roster_set(%L::uuid, 'payout_due', false)$q$, ox::text)) <> 1
      then v_bad := v_bad || ' send_query to session 2 failed'; end if;

    v_i := 0; v_we := null; v_wet := null; v_busy := null;
    loop
      perform pg_sleep(0.1); v_i := v_i + 1;
      v_busy := _rlk.dblink_is_busy('rlk2');
      select a.wait_event_type, a.wait_event into v_wet, v_we from pg_stat_activity a where a.pid = v_pid2;
      exit when v_busy = 0 or (v_wet = 'Lock' and v_we = 'advisory') or v_i >= 30;
    end loop;
    if v_busy is distinct from 1 then
      v_bad := v_bad || ' 🔴 (a) session 2 was NOT blocked while session 1 held its deactivation open (busy='
               || coalesce(v_busy::text, 'null') || ' wait=' || coalesce(v_wet, '∅') || '/' || coalesce(v_we, '∅') || ')';
    elsif (v_wet = 'Lock' and v_we = 'advisory') is not true then
      v_bad := v_bad || ' (a) session 2 is busy but not waiting on an advisory lock (wait='
               || coalesce(v_wet, '∅') || '/' || coalesce(v_we, '∅') || ')';
    end if;

    perform _rlk.dblink_exec('rlk1', 'commit');

    -- (b) Y's own row was turned off by a committed write; the gate, read under the key, says so.
    --     `not_ops` — not `last_operator` (which would speak to Y as if Y were still an operator),
    --     and never success.
    v_msg := null;
    begin
      select t.changed into v_changed from _rlk.dblink_get_result('rlk2') as t(changed boolean);
      v_msg := 'completed(changed=' || coalesce(v_changed::text, 'null') || ')';
      perform * from _rlk.dblink_get_result('rlk2') as t(changed boolean);
      perform _rlk.dblink_exec('rlk2', 'commit');
    exception when others then v_msg := sqlerrm;
    end;
    if (v_msg like '%not_ops%') is not true
      then v_bad := v_bad || ' 🔴 (b) session 2 result=' || coalesce(v_msg, '(null)') || ' (expected not_ops: Y was turned off by a committed write before its gate was read)'; end if;
  exception when others then
    v_bad := v_bad || ' 🔴 race scaffolding raised: ' || sqlerrm;
  end;
  call _rlk.drop_conns();

  -- (c) end state
  select count(*)::int into v_n from ops_recipients r
   where r.event_class = 'payout_due' and r.active and r.profile_id in (ox, oy);
  if v_n is distinct from 1
    then v_bad := v_bad || ' 🔴 (c) active console rows among the pair=' || v_n || ' (expected 1)'; end if;
  if (select r.active from ops_recipients r where r.profile_id = ox and r.event_class = 'payout_due') is not true
    then v_bad := v_bad || ' 🔴 (c) X is not on — the refused deactivation LANDED'; end if;
  select count(*)::int into v_n from ops_roster_changes;
  if (v_n - v_j0) is distinct from 1
    then v_bad := v_bad || ' (c) journal delta=' || (v_n - v_j0) || ' (expected 1: a refusal writes nothing)'; end if;

  if v_bad = '' then
    call _pass('rlk', '0216-R3 the MUTUAL shape: X turns Y off and holds; Y turning X off BLOCKS on the roster key, and once X commits is refused not_ops — the authorization read happens under the same key, so an operator already turned off is told so rather than last_operator or success; X on, Y off, journal +1');
  else
    call _fail('rlk', '0216-R3 mutual deactivation, gate read under the key', v_bad);
  end if;
end $rlk$;

-- FIXTURE (⑤): R2's premise, committed — both X and Y on (Y must still exist: on the fixed body
-- nothing before this deletes Y; on a broken one R3 may have turned Y off, never deleted).
update ops_recipients r set active = true
  from _rlk_fx f
 where f.k in ('ox', 'oy') and r.profile_id = f.v::uuid and r.event_class = 'payout_due';

-- ═════════════════════════════════════════════════════════════════
-- [0216-R2] TWO SESSIONS, THE OTHER WRITER — deletion holds the roster while a deactivation arrives
-- ═════════════════════════════════════════════════════════════════
do $rlk$
declare
  ox uuid := (select v::uuid from _rlk_fx where k = 'ox');
  oy uuid := (select v::uuid from _rlk_fx where k = 'oy');
  v_conn text := _rlk.connstr();
  v_bad text := '';
  v_n int; v_j0 int; v_i int;
  v_pid2 int; v_busy int;
  v_wet text; v_we text;
  v_changed boolean;
  v_msg text; v_res text;
begin
  select count(*)::int into v_n from ops_recipients r where r.event_class = 'payout_due' and r.active;
  if v_n is distinct from 2
    then v_bad := v_bad || ' control: active console operators=' || v_n || ' (expected 2 — the premise)'; end if;
  select count(*)::int into v_j0 from ops_roster_changes;

  call _rlk.drop_conns();
  begin
    perform _rlk.dblink_connect('rlk1', v_conn);
    perform _rlk.dblink_connect('rlk2', v_conn);
    perform _rlk.dblink_exec('rlk1', $q$set statement_timeout = '10s'$q$);
    perform _rlk.dblink_exec('rlk2', $q$set statement_timeout = '10s'$q$);
    select t.pid into v_pid2 from _rlk.dblink('rlk2', 'select pg_backend_pid()') as t(pid int);

    -- session 1: the deletion of Y (service path: no caller uid), HELD open
    perform _rlk.dblink_exec('rlk1', 'begin');
    perform _rlk.dblink_exec('rlk1', $q$set local request.jwt.claim.sub = ''$q$);
    select t.r into v_res
      from _rlk.dblink('rlk1', format($q$select delete_my_account_tx(%L::uuid)::text$q$, oy::text)) as t(r text);
    if (v_res::jsonb->>'ok') is distinct from 'true' or (v_res::jsonb->>'tombstoned') is distinct from 'true'
      then v_bad := v_bad || ' session 1: deleting Y did not report ok+tombstoned: ' || coalesce(v_res, '(null)'); end if;

    -- session 2: as X, deactivate X — ASYNC. It must block.
    perform _rlk.dblink_exec('rlk2', 'begin');
    perform _rlk.dblink_exec('rlk2', format('set local request.jwt.claim.sub = %L', ox::text));
    if _rlk.dblink_send_query('rlk2', format($q$select changed from ops_roster_set(%L::uuid, 'payout_due', false)$q$, ox::text)) <> 1
      then v_bad := v_bad || ' send_query to session 2 failed'; end if;

    v_i := 0; v_we := null; v_wet := null; v_busy := null;
    loop
      perform pg_sleep(0.1); v_i := v_i + 1;
      v_busy := _rlk.dblink_is_busy('rlk2');
      select a.wait_event_type, a.wait_event into v_wet, v_we from pg_stat_activity a where a.pid = v_pid2;
      exit when v_busy = 0 or (v_wet = 'Lock' and v_we = 'advisory') or v_i >= 30;
    end loop;
    if v_busy is distinct from 1 then
      v_bad := v_bad || ' 🔴 (a) session 2 was NOT blocked while the deletion of Y was open (busy='
               || coalesce(v_busy::text, 'null') || ' wait=' || coalesce(v_wet, '∅') || '/' || coalesce(v_we, '∅') || ')';
    elsif (v_wet = 'Lock' and v_we = 'advisory') is not true then
      v_bad := v_bad || ' (a) session 2 is busy but not waiting on an advisory lock (wait='
               || coalesce(v_wet, '∅') || '/' || coalesce(v_we, '∅') || ')';
    end if;

    perform _rlk.dblink_exec('rlk1', 'commit');

    v_msg := null;
    begin
      select t.changed into v_changed from _rlk.dblink_get_result('rlk2') as t(changed boolean);
      v_msg := 'completed(changed=' || coalesce(v_changed::text, 'null') || ')';
      -- dblink's async protocol: get_result is called AGAIN until it returns no rows, which clears
      -- the connection's async state — without this the commit below is refused with 「another
      -- command is already in progress」 (measured, lab A run 2).
      perform * from _rlk.dblink_get_result('rlk2') as t(changed boolean);
      -- a completed write is COMMITTED, as the real caller's would be: arm (c) must see what the
      -- product would have seen, never a rollback the scaffolding performed. (On the fixed body
      -- the call raises, the transaction is already aborted, and nothing commits.)
      perform _rlk.dblink_exec('rlk2', 'commit');
    exception when others then v_msg := sqlerrm;
    end;
    if (v_msg like '%last_operator%') is not true
      then v_bad := v_bad || ' 🔴 (b) session 2 result=' || coalesce(v_msg, '(null)') || ' (expected last_operator: Y''s row is gone, X is the last)'; end if;
  exception when others then
    v_bad := v_bad || ' 🔴 race scaffolding raised: ' || sqlerrm;
  end;
  call _rlk.drop_conns();

  -- (c) end state
  if (select count(*) from ops_recipients r where r.profile_id = oy) <> 0
    then v_bad := v_bad || ' (c) Y''s roster rows survived the deletion'; end if;
  if (select p.deleted_at is not null from profiles p where p.id = oy) is not true
    then v_bad := v_bad || ' (c) Y is not tombstoned'; end if;
  if (select r.active from ops_recipients r where r.profile_id = ox and r.event_class = 'payout_due') is not true
    then v_bad := v_bad || ' 🔴 (c) X is not on — the refused deactivation LANDED and the class is empty'; end if;
  select count(*)::int into v_n from ops_recipients r where r.event_class = 'payout_due' and r.active;
  if v_n is distinct from 1
    then v_bad := v_bad || ' 🔴 (c) active console operators=' || v_n || ' (expected 1)'; end if;
  select count(*)::int into v_n from ops_roster_changes;
  if (v_n - v_j0) is distinct from 0
    then v_bad := v_bad || ' (c) journal delta=' || (v_n - v_j0) || ' (expected 0: deletion does not journal, a refusal writes nothing)'; end if;

  if v_bad = '' then
    call _pass('rlk', '0216-R2 two sessions, the OTHER writer: while delete_my_account_tx(Y) is held open, a deactivation of X BLOCKS on the same roster advisory lock, completes with last_operator once the deletion commits (Y''s row gone, X the last), X stays on, the class keeps one operator');
  else
    call _fail('rlk', '0216-R2 two sessions, deletion vs deactivation', v_bad);
  end if;
end $rlk$;

-- FIXTURE (⑤): L1's premise, committed — X on (L1 calls the door as X; Y's row is gone on the
-- fixed body, so only X is named).
update ops_recipients r set active = true
  from _rlk_fx f
 where f.k = 'ox' and r.profile_id = f.v::uuid and r.event_class = 'payout_due';

-- ═════════════════════════════════════════════════════════════════
-- [0216-L1] THE LOCK IS HELD BY THIS BACKEND AFTER ops_roster_set — even when nothing changes
-- ═════════════════════════════════════════════════════════════════
do $rlk$
declare
  ox uuid := (select v::uuid from _rlk_fx where k = 'ox');
  v_bad text := '';
  v_n int; v_j0 int; v_changed boolean;
begin
  if _rlk.held() <> 0 then v_bad := v_bad || ' lock held BEFORE the call (' || _rlk.held() || ')'; end if;
  select count(*)::int into v_j0 from ops_roster_changes;
  perform set_config('request.jwt.claim.sub', ox::text, false);
  begin
    -- X is already on: a no-op write. The lock must be taken FIRST, not only when a row would move.
    select t.changed into v_changed from ops_roster_set(ox, 'payout_due', true) as t;
  exception when others then v_bad := v_bad || ' the call raised: ' || sqlerrm;
  end;
  perform set_config('request.jwt.claim.sub', '', false);
  if v_changed is not false then v_bad := v_bad || ' expected changed=false (X was already on), got ' || coalesce(v_changed::text, 'null'); end if;
  select count(*)::int into v_n from ops_roster_changes;
  if (v_n - v_j0) <> 0 then v_bad := v_bad || ' a no-op write journaled (delta=' || (v_n - v_j0) || ')'; end if;
  if _rlk.held() <> 1
    then v_bad := v_bad || ' 🔴 the roster advisory lock is not held by this backend after ops_roster_set (held=' || _rlk.held() || ')'; end if;

  if v_bad = '' then
    call _pass('rlk', '0216-L1 pg_locks: the roster advisory key (hashtextextended(''ops_roster'',0), classid/objid split) is not held before ops_roster_set and IS held by this backend after it — on a call that changed nothing and journaled nothing, so the lock is taken first, not only when a row would move');
  else
    call _fail('rlk', '0216-L1 pg_locks after ops_roster_set', v_bad);
  end if;
end $rlk$;

-- ═════════════════════════════════════════════════════════════════
-- [0216-L2] THE LOCK IS HELD BY THIS BACKEND AFTER delete_my_account_tx — on a profile NOT on the roster
-- ═════════════════════════════════════════════════════════════════
do $rlk$
declare
  oz uuid := (select v::uuid from _rlk_fx where k = 'oz');
  v_bad text := '';
  v_res jsonb;
begin
  if _rlk.held() <> 0 then v_bad := v_bad || ' lock held BEFORE the call (' || _rlk.held() || ')'; end if;
  if (select count(*) from ops_recipients r where r.profile_id = oz) <> 0
    then v_bad := v_bad || ' fixture: Z is on the roster (the arm needs a profile with no roster row)'; end if;
  perform set_config('request.jwt.claim.sub', '', false);
  begin
    v_res := delete_my_account_tx(oz);
  exception when others then v_bad := v_bad || ' the deletion raised: ' || sqlerrm;
  end;
  if (v_res->>'ok') is distinct from 'true' or (v_res->>'tombstoned') is distinct from 'true'
    then v_bad := v_bad || ' deletion did not report ok+tombstoned: ' || coalesce(v_res::text, '(null)'); end if;
  if _rlk.held() <> 1
    then v_bad := v_bad || ' 🔴 the roster advisory lock is not held by this backend after delete_my_account_tx (held=' || _rlk.held() || ')'; end if;

  if v_bad = '' then
    call _pass('rlk', '0216-L2 pg_locks: the same roster advisory key is not held before delete_my_account_tx and IS held after it, on a bare profile with NO roster row — the deletion takes the lock at its top, not beside the roster delete');
  else
    call _fail('rlk', '0216-L2 pg_locks after delete_my_account_tx', v_bad);
  end if;
end $rlk$;

-- ═════════════════════════════════════════════════════════════════
-- [0216-S1] THE DEPLOYED SOURCE, COMMENT-STRIPPED — the lock precedes what it protects, in both writers
-- ═════════════════════════════════════════════════════════════════
do $rlk$
declare
  v_bad  text := '';
  v_raw  text; v_src text;
  v_lock constant text := $l$pg_advisory_xact_lock(hashtextextended('ops_roster', 0))$l$;
  v_a    text; v_n int;
begin
  -- ── ops_roster_set ──
  select p.prosrc, regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_raw, v_src
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname = 'ops_roster_set';
  if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(ops_roster_set)';
  else
    -- crude control: stripping removed SOMETHING, so a stripped match is not a prose match
    if length(v_raw) <= length(v_src) then v_bad := v_bad || ' control: stripping removed nothing from ops_roster_set'; end if;
    if position(v_lock in v_src) = 0 then v_bad := v_bad || ' 🔴 ops_roster_set does not take the roster lock';
    else
      if position('ops_recipients_for(c_ops_class)' in v_src) = 0
        then v_bad := v_bad || ' the authorization read is gone from ops_roster_set';
      elsif position(v_lock in v_src) > position('ops_recipients_for(c_ops_class)' in v_src)
        then v_bad := v_bad || ' 🔴 the lock is taken AFTER the authorization read'; end if;
      if position('count(*)' in v_src) = 0
        then v_bad := v_bad || ' the last-operator count is gone from ops_roster_set';
      elsif position(v_lock in v_src) > position('count(*)' in v_src)
        then v_bad := v_bad || ' 🔴 the lock is taken AFTER the count — it protects nothing'; end if;
    end if;
    -- 0208's own pieces the lock ADDS to (never replaces)
    if position('for update' in v_src) = 0 then v_bad := v_bad || ' 0208 ④ target-row for update is gone'; end if;
    if position('on conflict on constraint ops_recipients_pkey' in v_src) = 0
      then v_bad := v_bad || ' 0208 ⑥ upsert-by-constraint is gone'; end if;
    if position($e$raise exception 'last_operator'$e$ in v_src) = 0 then v_bad := v_bad || ' last_operator refusal is gone'; end if;
  end if;

  -- ── delete_my_account_tx ──
  select p.prosrc, regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_raw, v_src
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace and ns.nspname = 'public'
   where p.proname = 'delete_my_account_tx';
  if v_src is null or btrim(v_src) = '' then v_bad := v_bad || ' NO-SOURCE(delete_my_account_tx)';
  else
    if length(v_raw) <= length(v_src) then v_bad := v_bad || ' control: stripping removed nothing from delete_my_account_tx'; end if;
    if position(v_lock in v_src) = 0 then v_bad := v_bad || ' 🔴 delete_my_account_tx does not take the roster lock';
    else
      if position('delete from ops_recipients' in v_src) = 0
        then v_bad := v_bad || ' the roster delete (0115:590) is gone';
      elsif position(v_lock in v_src) > position('delete from ops_recipients' in v_src)
        then v_bad := v_bad || ' 🔴 the lock is taken AFTER the roster delete'; end if;
      -- lock ORDER: advisory before ANY row read/lock of the deletion, so neither writer can hold a
      -- row the other needs while waiting for the key
      if position('from profiles where id = p_uid' in v_src) = 0
        then v_bad := v_bad || ' the first profile read is gone';
      elsif position(v_lock in v_src) > position('from profiles where id = p_uid' in v_src)
        then v_bad := v_bad || ' 🔴 the lock is not at the top of the deletion — a row read precedes it'; end if;
    end if;
    -- the inherited landings 0216 §B re-copied. Counted where 0191 made counting the rule.
    if position($e$enqueue_billing_key_revocation(p_uid, 'account_deleted')$e$ in v_src) = 0
      then v_bad := v_bad || ' 0138 §F revocation enqueue lost in the copy'; end if;
    if position('where runner_id = p_uid and paid_payout_id is null' in v_src) = 0
      then v_bad := v_bad || ' 0190 §B retention predicate lost in the copy'; end if;
    v_a := $e$using detail = coalesce(v_block_id::text, '')$e$;
    v_n := (length(v_src) - length(replace(v_src, v_a, ''))) / length(v_a);
    if v_n is distinct from 9 then v_bad := v_bad || ' 0191 §A detail arms=' || v_n || ' (expected 9)'; end if;
    if position('update gear_claims set delivery' in v_src) = 0
      then v_bad := v_bad || ' 0202 §B② delivery redaction lost in the copy'; end if;
  end if;

  if v_bad = '' then
    call _pass('rlk', '0216-S1 comment-stripped source (NO-SOURCE arms, raw>stripped control): ops_roster_set takes pg_advisory_xact_lock(hashtextextended(''ops_roster'',0)) BEFORE the authorization read and BEFORE the count, with 0208''s for-update/upsert/refusal intact; delete_my_account_tx takes the same key before its first profile read and before the roster delete, and the 0138/0190/0191×9/0202 landings are all still in the copy');
  else
    call _fail('rlk', '0216-S1 source order', v_bad);
  end if;
end $rlk$;

-- ═════════════════════════════════════════════════════════════════
-- [0216-A1] SHAPE + ACL of both re-declared functions — and the world RESTORED (last block, note ①)
-- ═════════════════════════════════════════════════════════════════
do $rlk$
declare
  ox uuid := (select v::uuid from _rlk_fx where k = 'ox');
  v_saved uuid[] := (select v::uuid[] from _rlk_fx where k = 'saved');
  v_bad text := '';
  v_oid oid; v_n int;
begin
  -- ops_roster_set: definer, in-body search_path, anon closed, authenticated open
  select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'ops_roster_set';
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(ops_roster_set)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is not true then v_bad := v_bad || ' ops_roster_set is not definer'; end if;
    if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' ops_roster_set has no in-body search_path'; end if;
    if has_function_privilege('anon', v_oid, 'execute') is not false then v_bad := v_bad || ' ops_roster_set open to anon'; end if;
    if has_function_privilege('authenticated', v_oid, 'execute') is not true then v_bad := v_bad || ' ops_roster_set closed to authenticated'; end if;
  end if;
  -- delete_my_account_tx: definer, in-body search_path, anon + authenticated closed, service_role open
  select p.oid into v_oid from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'delete_my_account_tx';
  if v_oid is null then v_bad := v_bad || ' NO-FUNCTION(delete_my_account_tx)';
  else
    if (select prosecdef from pg_proc where oid = v_oid) is not true then v_bad := v_bad || ' delete_my_account_tx is not definer'; end if;
    if (select 'search_path=public, pg_temp' = any(coalesce(proconfig, '{}')) from pg_proc where oid = v_oid) is not true
      then v_bad := v_bad || ' delete_my_account_tx has no in-body search_path'; end if;
    if has_function_privilege('anon', v_oid, 'execute') is not false then v_bad := v_bad || ' delete_my_account_tx open to anon'; end if;
    if has_function_privilege('authenticated', v_oid, 'execute') is not false then v_bad := v_bad || ' delete_my_account_tx open to authenticated'; end if;
    if has_function_privilege('service_role', v_oid, 'execute') is not true then v_bad := v_bad || ' delete_my_account_tx closed to service_role'; end if;
  end if;

  -- ── RESTORE (note ①): every console operator this suite neutralised comes back, with a control
  update ops_recipients set active = true
   where event_class = 'payout_due' and profile_id = any(v_saved);
  select count(*)::int into v_n from ops_recipients r
   where r.event_class = 'payout_due' and r.active and r.profile_id = any(v_saved);
  if v_n is distinct from coalesce(array_length(v_saved, 1), 0)
    then v_bad := v_bad || ' 🔴 restore: ' || v_n || ' of ' || coalesce(array_length(v_saved, 1), 0) || ' saved console operators came back'; end if;
  -- and this suite's own operator leaves the shared class as it found it (Y's row is gone, Z is tombstoned)
  update ops_recipients set active = false where profile_id = ox and event_class = 'payout_due';

  if v_bad = '' then
    call _pass('rlk', '0216-A1 shape + ACL: both re-declared functions are definer with in-body search_path; ops_roster_set is anon-closed/authenticated-open, delete_my_account_tx is anon+authenticated-closed/service_role-open; and every console operator this suite neutralised was restored (control: count = saved)');
  else
    call _fail('rlk', '0216-A1 shape + ACL + restore', v_bad);
  end if;
end $rlk$;

drop table if exists _rlk_fx;
