-- ═══ 192: billing_keys 의 클라이언트 권한 회수 (0161) — 0161-N1 · N2 · N3 ═══════════════════════
--
-- 🔴 THE PROPERTY: **`billing_keys` is sealed by TWO independent walls, not one.** It has been
--    RLS-on-with-zero-policies since 0080:110, which is genuinely enough today; 0161 removes the
--    table-level grant `anon`/`authenticated` inherited from Supabase's default privileges, so the
--    seal stops depending on the policy count staying at zero. One permissive policy added by a
--    future slice 「so the owner can see their own card」 and the grant arms with no code change
--    and nothing that fails.
--
-- ⚠ **THE FIXTURE STARTS WHERE PRODUCTION STARTS, AND THAT IS WHAT MAKES N1 WORTH ANYTHING.**
--    `00_shim.sql:82-95` mirrors production's `alter default privileges … grant all on tables to
--    anon, authenticated`, and `billing_keys` is created (0080) after the shim — so it is BORN
--    with SELECT/INSERT/UPDATE/DELETE for both client roles and 0161's revoke genuinely removes
--    something. Measured on this harness before the migration was written: anon and authenticated
--    each held all four. An absence pin over a table that never had the grant is green for the
--    wrong reason and licenses nothing — that is 0151's recorded near-miss, one table over, and
--    `0161-N3` is the arm that keeps this file honest about it.
--
-- ⚠ **N2 IS NOT DECORATION.** Over-revoking is the failure direction that does not leak anything
--    — it breaks card registration and revocation instead, silently, because those run as
--    `service_role` through edge functions. A one-sided pin cannot tell 「sealed」 from 「broken」.
--
-- ⚠ Every arm is `is distinct from`, never a bare `if has_*`: `has_table_privilege` can answer
--   NULL and plpgsql does not take an `IF` on a NULL predicate in either direction, so a bare IF
--   is silent in exactly the case an ACL pin exists for.

do $suite$
declare
  v_n int; v_bad text; v_msg text; v_txt text;
begin
  -- ═══════════ [0161-N1] 클라이언트 롤은 이 테이블에 아무 권한도 없다 ═══════════
  -- Eight arms (2 roles × 4 privileges), each named in the failure string, because 「something
  -- regressed」 and 「this role, this privilege」 are different messages to wake up to.
  v_bad := '';
  select count(*), coalesce(string_agg(t.rolname || ':' || t.priv, ', ' order by t.rolname, t.priv), '')
    into v_n, v_txt
  from (
    select r.rolname, pr.priv
      from (values ('anon'),('authenticated')) r(rolname),
           (values ('select'),('insert'),('update'),('delete')) pr(priv)
     where has_table_privilege(r.rolname, 'public.billing_keys', pr.priv) is distinct from false
  ) t;
  if v_n <> 0 then v_bad := v_bad || ' billing_keys 에 클라이언트 권한이 남아 있다 (' || v_txt || ')'; end if;
  -- the neighbour this file makes it agree with: billing_key_revocations (0138:49) holds the same
  -- credentials on their way out and was revoked from day one
  select count(*) into v_n from (
    select r.rolname, pr.priv
      from (values ('anon'),('authenticated')) r(rolname),
           (values ('select'),('insert'),('update'),('delete')) pr(priv)
     where has_table_privilege(r.rolname, 'public.billing_key_revocations', pr.priv) is distinct from false
  ) t;
  if v_n <> 0 then v_bad := v_bad || ' billing_key_revocations 의 봉인(0138:49)이 풀렸다=' || v_n; end if;
  if v_bad = '' then call _pass('bkgr','0161-N1 billing_keys 에 anon·authenticated 의 테이블 권한이 하나도 없다(SELECT·INSERT·UPDATE·DELETE 8팔 전부) — billing_key_revocations 와 같은 봉인. 빌링키는 bearer 자격증명이고, 정책이 0개라는 사실 하나에만 기대지 않는다');
  else v_msg := v_bad; call _fail('bkgr','0161-N1 클라이언트 권한 부재', v_msg); end if;

  -- ═══════════ [0161-N2] 과잉 회수 통제 — service_role 은 여전히 읽는다 ═══════════
  -- 🔴 This is the arm that fails on the direction N1 cannot see. Card registration
  --    (`billing_key_swap`, 0137/0138) and revocation (`claim_billing_key_revocations`, 0141) run
  --    as `service_role` through edge functions; revoking THEM would pass N1 perfectly and take
  --    the payment path down with no leak and no failing pin. Both arms, and the definer that
  --    the client actually reaches, are asserted.
  v_bad := '';
  if has_table_privilege('service_role', 'public.billing_keys', 'select') is distinct from true
    then v_bad := v_bad || ' service_role 이 billing_keys 를 못 읽는다(카드 등록·해지가 죽는다)'; end if;
  if has_table_privilege('service_role', 'public.billing_keys', 'insert') is distinct from true
    then v_bad := v_bad || ' service_role 이 billing_keys 에 못 쓴다(카드 등록이 죽는다)'; end if;
  if has_table_privilege('service_role', 'public.billing_keys', 'update') is distinct from true
    then v_bad := v_bad || ' service_role 이 billing_keys 를 못 갱신한다(카드 교체가 죽는다)'; end if;
  -- the client's own legitimate window onto this table is a definer, and 0161 did not touch it
  if has_function_privilege('authenticated', 'my_billing_card()', 'execute') is distinct from true
    then v_bad := v_bad || ' authenticated 가 my_billing_card 를 못 부른다(설정 화면의 카드 칸이 죽는다)'; end if;
  if has_function_privilege('anon', 'my_billing_card()', 'execute') is distinct from false
    then v_bad := v_bad || ' anon 이 my_billing_card 를 부를 수 있다'; end if;
  if v_bad = '' then call _pass('bkgr','0161-N2 과잉 회수 통제 — service_role 은 billing_keys 를 SELECT·INSERT·UPDATE 할 수 있고(엣지 함수의 카드 등록·교체·해지가 이 경로다), 클라이언트가 실제로 쓰는 창구인 my_billing_card() 는 authenticated 에 열려 있고 anon 에는 닫혀 있다. 이 팔이 없으면 「전부 회수」가 N1 을 완벽히 통과하면서 결제 경로를 조용히 끊는다');
  else v_msg := v_bad; call _fail('bkgr','0161-N2 과잉 회수 통제', v_msg); end if;

  -- ═══════════ [0161-N3] 봉인의 다른 반쪽 + 픽스처가 운영의 출발점이라는 통제 ═══════════
  -- ⚠ The control matters more than it looks. If this harness did NOT hand out default
  --   privileges, N1 would be green with 0161 deleted — the pin would be measuring an empty
  --   world. So an ORDINARY table in the same schema is asserted to still carry the client grant:
  --   the absence on `billing_keys` is then attributable to the revoke rather than to the fixture.
  v_bad := '';
  if (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = 'billing_keys') is distinct from true
    then v_bad := v_bad || ' billing_keys 에 RLS 가 없다'; end if;
  select count(*) into v_n from pg_policies where schemaname='public' and tablename='billing_keys';
  if v_n <> 0 then v_bad := v_bad || ' billing_keys 에 정책이 생겼다(정책 0개가 두 벽 중 하나다)=' || v_n; end if;
  if has_table_privilege('authenticated', 'public.session_people', 'select') is distinct from true
    then v_bad := v_bad || ' 통제 실패: 같은 스키마의 평범한 테이블에도 기본 권한이 없다 — 이 하네스는 운영의 출발점이 아니므로 N1 은 회수를 재는 게 아니라 빈 세계를 재고 있다'; end if;
  if has_table_privilege('authenticated', 'public.dogs', 'update') is distinct from true
    then v_bad := v_bad || ' 통제 실패: 평범한 테이블의 UPDATE 기본 권한도 없다(같은 이유)'; end if;
  if v_bad = '' then call _pass('bkgr','0161-N3 봉인의 다른 반쪽 — RLS 는 켜져 있고 정책은 0개 그대로(0161 은 벽을 하나 더한 것이지 바꾼 게 아니다). ⚠ 통제: 같은 스키마의 평범한 테이블(session_people·dogs)은 여전히 anon/authenticated 기본 권한을 갖고 있으므로, billing_keys 의 권한 부재는 회수의 결과이지 하네스가 기본 권한을 안 준 결과가 아니다 — 결함을 담지 않은 픽스처는 수정을 시험할 수 없다');
  else v_msg := v_bad; call _fail('bkgr','0161-N3 봉인·픽스처 통제', v_msg); end if;
end $suite$;
