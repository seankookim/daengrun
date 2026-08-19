-- ═══ 144 revoke-TRUNCATE suite — 0109 pins (the one verb RLS never covered) ═══
-- T1 = the attack, EXECUTED per role and per table. T2 = the schema-wide enumeration (metadata,
-- acceptable ONLY because T1 executes). T3 = tomorrow's table: a probe created after the
-- migration must not be born with TRUNCATE. T4 = the positive control that says the sweep did not
-- take the verb from the roles that legitimately hold it.
-- Purpose: production `pg_default_acl` hands `arwdDxtm` (ALL, `D` = TRUNCATE) to anon and
--   authenticated on every new public table, and RLS does not apply to TRUNCATE. 65/68 tables held
--   it (measured 2026-08-19). No path reaches it today; 0109 removes it before one does.
-- Style: sibling of 124/131 — `_pass('rtr',…)`/`_fail('rtr',…)`, one begin…exception per arm,
--   `set local role` + cleared `request.jwt.claim.sub` for every client path, ALWAYS `reset role`.
--   ⚠ ONLY sqlstate 42501 counts as a refusal. A missing table, an FK complaint (0A000) or a lock
--     failure must NOT read as "the revoke worked" — that is how a suite invents a security pass
--     it never earned. Each denial arm records the sqlstate it actually saw.
--   ⚠ Every attack goes through `execute` so the failure stays inside our handler.
--
-- ─── MUTATION map — each pin goes RED under a named revert of 0109 (house law) ───
--   T1 ← 0109 arm ①: delete `revoke truncate on all tables in schema public …`         → RED
--   T2 ← 0109 arm ①: as T1 (65 rows reappear in the enumeration)                       → RED
--   T3 ← 0109 arm ②: delete `alter default privileges for role postgres … revoke truncate`
--        (the probe is created AFTER 0109 and inherits whatever the default ACL says)     → RED
--   T4 ← no mutation in 0109 reddens it (positive control); a future
--        `revoke truncate … from service_role` would.
--   Harness precondition: 00_shim.sql grants `all` on new tables to anon/authenticated (as
--   production does). With the old DML-only shim line, T1-T3 are green even with 0109 deleted.
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-19, worktree `p0-truncate` (baseline before
--     0109 = 592/0 · green with 0109 + this suite = 596/0):
--       M1  arm ① deleted, verify block kept → the MIGRATION refuses: `❌ 0109 … TRUNCATE still
--           held by client roles on 130 table-role pairs: addresses:anon, …` (harness stops at
--           the migration stage — the fail-closed check works before any pin runs).
--       M1b arm ① AND the verify block deleted → 594/2, red = [T1, T2].
--           T1 detail: `anon→drops=SUCCEEDED · anon→bookings=0A000 · anon→routes=0A000` (same for
--           authenticated). Read that carefully: an anon TRUNCATE of `drops` WENT THROUGH, and the
--           FK-referenced tables failed on 0A000 (cannot truncate a table referenced by a FK), not
--           on privilege — the FK is not protection, `truncate … cascade` walks it, and anon held
--           TRUNCATE on the referencing tables too. T2 = `65 of 69`, production's number exactly.
--       M2  arm ② deleted → 594/2, red = [T3, T2]. T3: `probe: anon=SUCCEEDED authenticated=
--           SUCCEEDED`. ⚠ T2 ALSO reddens (`1 of 69`) and I had predicted a clean single: the one
--           table is `_t`, the harness's own results table, created by suite 10 AFTER migrations —
--           so it, like the probe, is born from the default ACL. Not noise: any table created after
--           0109 without arm ② regains the verb, and `_t` is simply the first one that exists.
--       M0  0109 absent entirely → 593/3, red = [T1, T2 (`66 of 69` = 65 + `_t`), T3].
--       Restore → 596/0.

do $$
declare
  v_msg  text;
  v_bad  text;
  v_st   text;
  v_n    int;
  v_tot  int;
  v_tbl  text;
  v_role text;
begin
  -- ---------- [T1] EXECUTED: anon and authenticated cannot truncate bookings / drops / routes ----------
  v_bad := '';
  foreach v_role in array array['anon', 'authenticated'] loop
    foreach v_tbl in array array['bookings', 'drops', 'routes'] loop
      v_st := null;
      begin
        execute 'set local role ' || v_role;
        perform set_config('request.jwt.claim.sub', '', true);
        execute 'truncate ' || v_tbl;
        v_st := 'SUCCEEDED';
      exception when others then v_st := sqlstate;
      end;
      reset role;
      if v_st <> '42501' then
        v_bad := v_bad || ' ' || v_role || '→' || v_tbl || '=' || v_st;
      end if;
    end loop;
  end loop;
  if v_bad = '' then
    call _pass('rtr', 'T1 anon·authenticated의 truncate bookings/drops/routes — 6/6 모두 42501 (실행으로 확인)');
  else
    v_msg := '42501이 아닌 결과:' || v_bad;
    call _fail('rtr', 'T1 executed truncate refused', v_msg);
  end if;

  -- ---------- [T2] enumeration: no public table grants TRUNCATE to either client role ----------
  -- Metadata pin, acceptable only next to T1. The `v_tot` arm keeps it from passing vacuously
  -- (a scan of an empty schema would also count 0).
  select count(*) filter (where has_table_privilege('anon',          c.oid, 'TRUNCATE')
                              or has_table_privilege('authenticated', c.oid, 'TRUNCATE')),
         count(*)
    into v_n, v_tot
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p');
  v_msg := 'truncate-granting tables=' || v_n || ' of ' || v_tot;
  if v_n = 0 and v_tot > 50 then
    call _pass('rtr', 'T2 public 테이블 ' || v_tot || '개 전부 anon·authenticated TRUNCATE 없음 (열거)');
  else
    call _fail('rtr', 'T2 enumeration', v_msg);
  end if;

  -- ---------- [T3] tomorrow's table: a probe created NOW is not born with TRUNCATE ----------
  -- Created as the migration/owner role (postgres, the session user), i.e. exactly how the next
  -- migration's `create table` will land. This is the pin that notices when arm ② is missing —
  -- T1/T2 stay green in that world because the 65 existing tables were swept.
  execute 'create table _t144_probe (id int)';
  v_bad := '';
  foreach v_role in array array['anon', 'authenticated'] loop
    v_st := null;
    begin
      execute 'set local role ' || v_role;
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'truncate _t144_probe';
      v_st := 'SUCCEEDED';
    exception when others then v_st := sqlstate;
    end;
    reset role;
    if v_st <> '42501' then v_bad := v_bad || ' ' || v_role || '=' || v_st; end if;
  end loop;
  -- discrimination arm: the default ACL still hands the probe to the client roles for DML,
  -- so a green here means TRUNCATE specifically was withheld, not that the probe is unreachable
  if not has_table_privilege('authenticated', '_t144_probe', 'select') then
    v_bad := v_bad || ' [probe not even selectable — default ACL absent, pin is vacuous]';
  end if;
  if v_bad = '' then
    call _pass('rtr', 'T3 0109 이후 만든 새 테이블 — anon·authenticated truncate 42501 (default privileges가 지운다)');
  else
    v_msg := 'probe:' || v_bad;
    call _fail('rtr', 'T3 default privileges', v_msg);
  end if;

  -- ---------- [T4] positive control: service_role and the owner still truncate the probe ----------
  v_bad := '';
  begin
    set local role service_role;
    execute 'truncate _t144_probe';
    reset role;
  exception when others then reset role; v_bad := v_bad || ' service_role=' || sqlstate;
  end;
  begin
    execute 'truncate _t144_probe';   -- as postgres, the owner
  exception when others then v_bad := v_bad || ' owner=' || sqlstate;
  end;
  if v_bad = '' then
    call _pass('rtr', 'T4 양성 대조 — service_role·소유자(postgres)의 truncate는 그대로 된다');
  else
    v_msg := 'truncate refused:' || v_bad;
    call _fail('rtr', 'T4 positive control', v_msg);
  end if;

  execute 'drop table _t144_probe';
exception when others then
  reset role;
  v_msg := sqlstate || ' ' || sqlerrm;
  call _fail('rtr', 'suite 144 aborted', v_msg);
end $$;
