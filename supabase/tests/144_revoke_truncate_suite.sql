-- ═══ 144 revoke-TRUNCATE suite — 0109 pins (the verbs RLS never covered) ═══
-- T1 = the attack, EXECUTED per role and per table. T2 = the schema-wide enumeration over every
-- relkind TRUNCATE can name — tables, partitioned tables, views, matviews, foreign tables (review
-- F3) — and, since round 2, over all THREE revoked verbs plus a service_role arm that catches an
-- over-revoke; a metadata pin, acceptable ONLY because T1 executes. T3 = tomorrow's table: a probe
-- created after the migration must not be born with the verbs. T4 = the positive control that says
-- the sweep did not take TRUNCATE from the role that legitimately holds it.
-- Purpose: production `pg_default_acl` hands `arwdDxtm` (ALL — `D` TRUNCATE, `t` TRIGGER,
--   `x` REFERENCES) to anon and authenticated on every new public table, and RLS applies to none
--   of them. 63/68 tables and both public views held all three (re-measured on production
--   2026-08-19, after 0106 deployed and sealed `drops`+`gear_claims`; the pre-0106 number was
--   65/68). No path reaches them today; 0109 removes them before one appears.
-- Style: sibling of 124/131 — `_pass('rtr',…)`/`_fail('rtr',…)`, one begin…exception per arm,
--   `set local role` + cleared `request.jwt.claim.sub` for every client path, ALWAYS `reset role`.
--   ⚠ ONLY sqlstate 42501 counts as a refusal. A missing table, an FK complaint (0A000) or a lock
--     failure must NOT read as "the revoke worked" — that is how a suite invents a security pass
--     it never earned. Each denial arm records the sqlstate it actually saw.
--   ⚠ Every attack goes through `execute` so the failure stays inside our handler.
--   ⚠ Round 2 (Codex C6): every client arm asserts `current_user = <role>` AFTER the `set local
--     role` and before the attack, raising the custom sqlstate `ZZ001`. Without it a SET ROLE that
--     silently failed would run the truncate as `postgres`… or, worse, a SET ROLE that ERRORED
--     would land in the same handler and be recorded as a non-42501 result for the wrong reason.
--     `ZZ001` is distinguishable from both 42501 (real refusal) and 0A000 (FK complaint) in the
--     failure text, so a broken world never reads as a security pass.
--
-- ─── MUTATION map — each pin goes RED under a named revert of 0109 (house law) ───
--   T1 ← 0109 arm ①: delete `revoke truncate, trigger, references on all tables …`      → RED
--   T2 ← 0109 arm ①: as T1 (65 relations reappear in the enumeration)                   → RED
--   T3 ← 0109 arm ②: delete `alter default privileges for role postgres … revoke …`
--        (the probe is created AFTER 0109 and inherits whatever the default ACL says)     → RED
--   T4 ← 0109 arm ①, the OTHER direction: ADD `service_role` to the revoke list          → RED
--        (with T2's service_role arm. Round 1's T4 was one-directional — nothing in the file
--         could redden it, so it pinned nothing. An over-revoke is the exact failure this
--         slice's own change is most likely to cause, so it now has a pin.)
--   Harness precondition: 00_shim.sql grants `all` on new tables to anon/authenticated (as
--   production does). With the old DML-only shim line, T1-T3 are green even with 0109 deleted.
--   ✔ MUTATION-PROVEN by full-harness runs, worktree `p0-truncate`.
--     ROUND 2, 2026-08-19, post-merge tree (origin/redesign-v4 merged at 979c159 — 0106/0107/0108
--     applied, `HELD`/`deploy-migrations.sh` present). green = 641/0.
--       M-over `service_role` appended to arm ①'s revoke list → 639/2, red = [T2, T4].
--           T2: `client-verb-holding relations=0 of 71 · service_role truncate-holding
--                relations=1 (expected >= 60)`.
--           T4: `positive control broken: service_role→club_critical_titles=42501`.
--           This is the pin round 1 did not have: the sweep taking a verb from a role that needs
--           it is invisible to T1/T2/T3, all of which only ask whether CLIENT roles were stripped.
--       M1  arm ① deleted, verify block kept → the MIGRATION refuses: `❌ 0109 … TRUNCATE/TRIGGER/
--           REFERENCES still held by client roles on 390 relation-role-verb triples: addresses:
--           anon:REFERENCES, …` (harness stops at the migration stage — the fail-closed check
--           works before any pin runs). The list names `available_runners` and
--           `marketplace_open_requests` — the two VIEWS the old ('r','p') filter could not see.
--       M1b arm ① AND the verify block deleted → 639/2, red = [T1, T2].
--           T2 = `client-verb-holding relations=65 of 71` — 63 base tables + 2 views, production's
--           number exactly (production re-measured the same day: anon 63/68 tables, 2/2 views).
--           T1 detail: `anon→bookings=0A000 · anon→chat_messages=SUCCEEDED · anon→routes=0A000`
--           (same for authenticated).
--           Read that carefully: 0A000 is "cannot truncate a table referenced by a foreign key",
--           NOT a privilege refusal — the FK is not protection, `truncate … cascade` walks it, and
--           anon held TRUNCATE on the referencing tables too. Which is why T1 counts only 42501,
--           and why round 2 added `chat_messages`: it is a LEAF (no inbound FK, verified against
--           pg_constraint), so in a broken world it reports `SUCCEEDED` outright — a plain, unarguable
--           "an anon truncate emptied a table", with no FK error to hide behind.
--           ⚠ `drops` reads 42501 on its own since 0106 sealed it; on the pre-0106 tree it read
--           `anon→drops=SUCCEEDED`. The pin is unchanged; the world moved.
--       M2  arm ② deleted, verify block B kept → the MIGRATION refuses: `❌ 0109: postgres-creator
--           default privileges still grant 6 client verb(s) on future tables: public:anon:
--           REFERENCES, public:anon:TRIGGER, public:anon:TRUNCATE, public:authenticated:…`.
--           Round 1 had no fail-closed check on the arm ② half at all; this is it.
--       M2b arm ② AND verify block B deleted → 639/2, red = [T2, T3]. T3: `probe: anon=SUCCEEDED
--           authenticated=SUCCEEDED`. ⚠ T2 reddens WITH it (`1 of 71`): the one relation is `_t`,
--           the harness's own results table, created by suite 10 AFTER migrations — so it, like
--           the probe, is born from the default ACL. Not noise: any table created after 0109
--           without arm ② regains the verbs, and `_t` is simply the first one that exists.
--     Restore → 641/0.

do $$
declare
  v_msg   text;
  v_bad   text;
  v_st    text;
  v_n     int;
  v_tot   int;
  v_svc   int;
  v_tbl   text;
  v_role  text;
  v_roles text[];
begin
  -- ---------- [T1] EXECUTED: anon and authenticated cannot truncate ----------
  -- bookings / drops / routes are FK-referenced; `chat_messages` is a LEAF (no inbound FK,
  -- checked against pg_constraint) added in round 2 so a broken world says SUCCEEDED rather than
  -- hiding behind 0A000.
  v_bad := '';
  foreach v_role in array array['anon', 'authenticated'] loop
    foreach v_tbl in array array['bookings', 'chat_messages', 'drops', 'routes'] loop
      v_st := null;
      begin
        execute 'set local role ' || v_role;
        -- the SET ROLE must have actually taken, or a refusal below means nothing (Codex C6)
        if current_user <> v_role then
          raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
        end if;
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
    call _pass('rtr', 'T1 anon·authenticated의 truncate bookings/chat_messages/drops/routes — 8/8 모두 42501 (실행으로 확인)');
  else
    v_msg := '42501이 아닌 결과 (ZZ001 = set role 자체가 실패):' || v_bad;
    call _fail('rtr', 'T1 executed truncate refused', v_msg);
  end if;

  -- ---------- [T2] enumeration: no public relation grants the three verbs to a client role ----------
  -- Metadata pin, acceptable only next to T1. The `v_tot` arm keeps it from passing vacuously
  -- (a scan of an empty schema would also count 0). The `v_svc` arm keeps it from passing
  -- because the migration over-revoked (round 2).
  v_roles := array['anon', 'authenticated'];
  -- `authenticator` is PostgREST's login role: present on production (measured holding 0 table
  -- privileges in public), absent from the harness cluster. Assert where it exists — and never
  -- call has_table_privilege on a role that does not, because that raises rather than returns false.
  if exists (select 1 from pg_roles where rolname = 'authenticator') then
    v_roles := v_roles || 'authenticator'::text;
  end if;

  select count(*) filter (
           where exists (select 1
                           from unnest(v_roles) r,
                                unnest(array['TRUNCATE', 'TRIGGER', 'REFERENCES']) p
                          where has_table_privilege(r, c.oid, p))),
         count(*)
    into v_n, v_tot
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f');
  -- relkind includes views/matviews/foreign tables ON PURPOSE (review F3). Views are handed these
  -- verbs by the same production default ACL (`available_runners`, `marketplace_open_requests`),
  -- and arm ① does sweep them — `revoke … on all tables` means all relations. Scoped to ('r','p')
  -- this pin would have passed while asserting nothing about a surface the fix covers, and would
  -- have stayed silent if a later change re-granted it there.
  -- All three verbs ON PURPOSE (round 2): they ride one default-ACL row and one revoke statement,
  -- so a pin on TRUNCATE alone would go green while TRIGGER — the escalation verb, a client-attached
  -- function running inside an owner/service_role transaction — sat untouched.

  -- over-revoke arm: service_role must still hold TRUNCATE on essentially everything. A pre-0109
  -- snapshot is impossible from here — harness.sh applies EVERY migration (each with
  -- --single-transaction) and only then runs the suites, so by the time this file executes the
  -- pre-migration world is gone and no temp table could have been written in it. So the assertion
  -- is a floor, not an equality: measured 69 of 71 in this harness world (the 2 missing are
  -- 0106's `drops`/`gear_claims`, whose own migration revoked service_role TRUNCATE on purpose),
  -- and 66 of 68 base tables on production. `>= 60` is far above what any legitimate future
  -- service_role revoke would leave and far below what the over-revoke mutation produces (0).
  select count(*)
    into v_svc
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm', 'f')
     and has_table_privilege('service_role', c.oid, 'TRUNCATE');

  v_msg := 'client-verb-holding relations=' || v_n || ' of ' || v_tot
        || ' · service_role truncate-holding relations=' || v_svc || ' (expected >= 60)';
  if v_n = 0 and v_tot > 50 and v_svc >= 60 then
    call _pass('rtr', 'T2 public 릴레이션 ' || v_tot || '개(테이블+뷰) 전부 클라이언트 역할의 TRUNCATE·TRIGGER·REFERENCES 없음, service_role은 ' || v_svc || '개 유지 (열거)');
  else
    call _fail('rtr', 'T2 enumeration', v_msg);
  end if;

  -- ---------- [T3] tomorrow's table: a probe created NOW is not born with the verbs ----------
  -- Created as the migration/owner role (postgres, the session user), i.e. exactly how the next
  -- migration's `create table` will land. This is the pin that notices when arm ② is missing —
  -- T1/T2 stay green in that world because the relations that already existed were swept.
  execute 'drop table if exists _t144_probe';   -- a probe left behind by an aborted earlier run
  execute 'create table _t144_probe (id int)';
  v_bad := '';
  foreach v_role in array array['anon', 'authenticated'] loop
    v_st := null;
    begin
      execute 'set local role ' || v_role;
      if current_user <> v_role then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'truncate _t144_probe';
      v_st := 'SUCCEEDED';
    exception when others then v_st := sqlstate;
    end;
    reset role;
    if v_st <> '42501' then v_bad := v_bad || ' ' || v_role || '=' || v_st; end if;
  end loop;
  -- discrimination arm: the default ACL must still be handing this probe SOMETHING, or a green
  -- above would only mean "no default ACL exists here at all" and the pin would be vacuous.
  -- Asked of service_role's TRUNCATE specifically (review F6) rather than of authenticated's
  -- SELECT: that is the same verb the pin is about, from the same default-ACL row, so it fails if
  -- arm ② ever over-reaches instead of merely being absent.
  if not has_table_privilege('service_role', '_t144_probe', 'TRUNCATE') then
    v_bad := v_bad || ' [probe TRUNCATE not held by service_role either — default ACL absent or over-revoked, pin is vacuous]';
  end if;
  if v_bad = '' then
    call _pass('rtr', 'T3 0109 이후 만든 새 테이블 — anon·authenticated truncate 42501 (default privileges가 지운다)');
  else
    v_msg := 'probe:' || v_bad;
    call _fail('rtr', 'T3 default privileges', v_msg);
  end if;

  -- ---------- [T4] positive control, two-directional (round 2) ----------
  -- Round 1 truncated the freshly-created probe as service_role. That proved almost nothing: the
  -- probe is a table 0109's arm ① never touched (it did not exist yet). This version exercises a
  -- PRE-EXISTING, production-shaped table that arm ① DID sweep — `club_critical_titles`, sealed
  -- from clients by 0095 (`revoke all … from anon, authenticated`) while service_role keeps
  -- TRUNCATE from the default ACL. It is also a leaf (no inbound FK, checked), so `cascade`
  -- reaches nothing else.
  -- The truncate is REAL and then unwound: this block has an exception handler, so plpgsql opens a
  -- subtransaction for it, and the `raise … P0001` at the end rolls the truncate back. The pin
  -- passes ONLY on P0001 — which can only be reached by getting PAST the truncate. 42501 means the
  -- sweep took the verb from service_role; any other sqlstate is reported verbatim.
  v_bad := '';
  v_st  := null;
  begin
    set local role service_role;
    execute 'truncate club_critical_titles cascade';
    raise exception 'T144 positive control reached the end — unwinding' using errcode = 'P0001';
  exception when others then
    v_st := sqlstate;
  end;
  reset role;
  if v_st <> 'P0001' then
    v_bad := v_bad || ' service_role→club_critical_titles=' || coalesce(v_st, 'NULL');
  end if;
  -- and the owner still truncates its own table
  begin
    execute 'truncate _t144_probe';   -- as postgres, the owner
  exception when others then v_bad := v_bad || ' owner→_t144_probe=' || sqlstate;
  end;
  if v_bad = '' then
    call _pass('rtr', 'T4 양성 대조 — service_role은 기존 테이블(club_critical_titles) truncate 가능(서브트랜잭션으로 되돌림), 소유자(postgres)도 그대로');
  else
    v_msg := 'positive control broken:' || v_bad;
    call _fail('rtr', 'T4 positive control', v_msg);
  end if;

  execute 'drop table if exists _t144_probe';
exception when others then
  reset role;
  -- the probe must not survive an abort into the next suite's world (review F7)
  begin
    execute 'drop table if exists _t144_probe';
  exception when others then null;
  end;
  v_msg := sqlstate || ' ' || sqlerrm;
  call _fail('rtr', 'suite 144 aborted', v_msg);
end $$;
