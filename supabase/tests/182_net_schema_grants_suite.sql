-- ═══ 182: no client role reaches schema `net` (0151) — N1~N3 ═══
--
-- 🔴 THIS IS A STANDING PIN AND 0151 HAS AN APPLY-TIME CHECK, AND NEITHER IS EVIDENCE FOR THE
--    OTHER. The grant this file watches is created by `pg_net` itself, so a
--    `create extension … update` can restore it AFTER 0151 has applied — a state an apply-time
--    check structurally cannot see, because it ran before the change existed. Same division as
--    `check-definer-acl` (source) beside 98 H1 (runtime), and the same warning applies.
--
-- ⚠ WHAT THIS PROTECTS, IN BOTH HALVES, so nobody reads the pin as wider than its sentence.
--   `net.http_request_queue` has `headers` and `body` columns, and real secrets transit them:
--   `X-Cron-Key` and the push `Authorization`. But a holder of the anon key **cannot reach the
--   schema over HTTP** — measured against production 2026-08-27 with the app's own public key:
--   `406 PGRST106, "Only the following schemas are exposed: public, graphql_public"`.
--   **So this pin guards a needless grant behind a config line, not a live exposure.** It exists
--   because that config is a SETTING and not an invariant: add `net` to the exposed list for any
--   unrelated reason and the grant arms with no code change and nothing else failing.
--
-- ⚠ AND THE TABLE BEING EMPTY PROVES NOTHING. `pg_net` drains the queue, so rows exist only while
--   a request is in flight. **It measures clean every time a human looks by hand** — two sessions
--   checked it today and both saw an empty or benign table. A content check is not available to
--   this pin; only the GRANT is stable enough to assert.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).

do $$
declare v_bad text := ''; v_msg text; v_n int; v_present boolean;
begin
  select exists (select 1 from pg_namespace where nspname = 'net') into v_present;

  -- N1: the schema grant. ⚠ If `net` is absent this pin must SAY SO rather than pass — an absent
  -- schema and a revoked grant are different facts, and only one of them is this file's subject.
  -- The harness has no pg_net, so this arm is the honest one there.
  if not v_present then
    call _pass('nsg','N1 net 스키마 자체가 없다 (하네스) — 권한 명제는 프로덕션에서만 성립');
  else
    if has_schema_privilege('anon', 'net', 'usage')          then v_bad := v_bad || ' anon-USAGE'; end if;
    if has_schema_privilege('authenticated', 'net', 'usage') then v_bad := v_bad || ' authenticated-USAGE'; end if;
    v_msg := 'anon_usage=' || has_schema_privilege('anon','net','usage')::text
          || ' auth_usage=' || has_schema_privilege('authenticated','net','usage')::text;
    if v_bad <> '' then call _fail('nsg','N1 클라이언트 롤은 net 스키마에 USAGE 가 없다', v_bad || ' | ' || v_msg);
                   else call _pass('nsg','N1 클라이언트 롤은 net 스키마에 USAGE 가 없다'); end if;
    v_bad := '';
  end if;

  -- N2: the TABLE grants, asserted separately from N1 and both required. Revoking schema USAGE
  -- makes the tables unreachable, so a surviving table grant cannot be exercised — but it is
  -- still granted, and re-granting USAGE later (which an extension update does) restores reach
  -- without touching the table grant. **A pin that checked only the schema would call that
  -- state clean**, which is the same 「my green is narrower than the property」 shape as everything
  -- else in this repo's ledger.
  if not v_present then
    call _pass('nsg','N2 net 테이블 권한 (스키마 부재 — 프로덕션 명제)');
  else
    select count(*) into v_n
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'net' and c.relkind in ('r','p','v','m')
       and (has_table_privilege('anon', c.oid, 'select')
         or has_table_privilege('authenticated', c.oid, 'select'));
    v_msg := 'readable_relations=' || v_n;
    if v_n <> 0 then call _fail('nsg','N2 클라이언트 롤이 읽을 수 있는 net 릴레이션은 0개다', v_msg);
                else call _pass('nsg','N2 클라이언트 롤이 읽을 수 있는 net 릴레이션은 0개다'); end if;
  end if;

  -- N3: the SOURCE half — every pg_net caller in this repo is a definer, so revoking the client
  -- grant cannot break one. Asserted as source because the harness has no `net` to call, and a
  -- behavioural pin that cannot run would be a green standing for an untested property.
  -- ⚠ Matches an executable-shaped phrase, not a bare identifier: `net.http_post(` appears in
  --   prose throughout these files, and a pin that matches its own documentation measures the
  --   documentation (0148 W6 learned this the hard way, on its first run).
  v_bad := '';
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and regexp_replace(p.prosrc, '--[^\n]*', '', 'g') ~ 'net\.http_(post|get|delete)\s*\('
     and not p.prosecdef;
  v_msg := 'non-definer pg_net callers=' || v_n;
  if v_n <> 0 then call _fail('nsg','N3 pg_net 호출자는 전부 definer 다', v_msg);
              else call _pass('nsg','N3 pg_net 호출자는 전부 definer 다'); end if;
end $$;
