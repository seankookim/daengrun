-- ═══ 0161 — billing_keys 의 클라이언트 권한을 회수한다 (billing_key_revocations 와 같은 봉인) ═══
--
-- `billing_keys` holds a bearer credential: whoever holds `billing_key` can charge the card
-- (0080:95-113 says so in its own header). The table was created with RLS ON and ZERO policies,
-- which is the seal this repo means by 「sealed」 — and it is genuinely load-bearing today: no
-- client can read a row through PostgREST, because no policy admits one.
--
-- ⚠ **BUT THE TABLE-LEVEL GRANT WAS NEVER REVOKED, AND THAT IS NOT THE SAME SENTENCE.** Supabase
--   ships `alter default privileges in schema public grant all on tables to anon, authenticated`,
--   so every table created in `public` is born with client DML privileges and RLS is the only
--   thing standing in front of it. `billing_key_revocations` — the table that holds the SAME
--   credentials on their way out — revokes them explicitly (0138:49) precisely because 「we
--   granted nothing」 and 「they hold nothing」 are different facts. This file makes the two tables
--   agree.
--
-- ⚠ **WHY NOW, AND WHAT IT IS AND IS NOT.** This is HYGIENE, not an incident, and the honest
--   sentence matters: RLS is on with zero policies, so there is no reachable read today. What the
--   revoke buys is that the protection stops depending on a POLICY COUNT staying at zero. One
--   permissive policy added by a future slice 「to let the owner see their own card」 and the grant
--   arms with no code change and nothing that fails. Removing it converts 「protected by there
--   being no policy」 into 「protected by not being granted」 — two independent walls instead of
--   one. (Same argument as 0151's `net` grant, and the same posture: a needless privilege on a
--   credential store is removed on sight, and the repo going public 2026-08-31 makes the shape of
--   that privilege readable by anyone.)
--
-- ⚠ **VERIFIED BEFORE CLAIMING, not assumed:** the only readers of `billing_keys` are edge
--   functions running as `service_role` (which bypasses RLS and keeps its own grants), plus the
--   `security definer` functions `my_billing_card()` (0080) and `billing_key_swap()` (0137/0138),
--   which run as their owner and are unaffected by a client-role revoke. No app-side direct
--   select exists. `service_role`'s SELECT is asserted as a CONTROL in suite 192 — an over-revoke
--   here would not leak anything, it would break card registration, and a one-sided pin cannot
--   tell those apart.
--
-- No table is created, no column added, no function touched. Two statements and a VERIFY.

revoke all on table billing_keys from anon, authenticated;

comment on table billing_keys is
  '0080 §A (0161): 빌링키 storage. SEALED — RLS on, zero policies, AND no client-role grant
(0161: 기본 권한으로 들어와 있던 anon/authenticated 의 테이블 권한을 회수했다 — billing_key_revocations
0138:49 와 같은 봉인). 키는 bearer 자격증명이다; 클라이언트가 보는 것은 my_billing_card()
(brand/last4/linked_at) 뿐이고 키 자체는 어떤 클라이언트 표면에도 나가지 않는다.';

-- ═══ VERIFY — house form. `has_table_privilege` can answer NULL and plpgsql skips an IF on NULL,
-- so every arm is `is distinct from`; a bare `if has_*` is silent in exactly the case this block
-- exists for. Both directions: the client roles hold nothing, and service_role still reads.
do $mig$
declare v_n int; v_bad text := '';
begin
  select count(*) into v_n from (
    select r.rolname, pr.priv
      from (values ('anon'),('authenticated')) r(rolname),
           (values ('select'),('insert'),('update'),('delete')) pr(priv)
     where has_table_privilege(r.rolname, 'public.billing_keys', pr.priv) is distinct from false
  ) t;
  if v_n <> 0 then v_bad := v_bad || ' billing_keys에 클라이언트 권한이 남아 있다=' || v_n; end if;

  -- the over-revoke control: this is the direction that breaks card registration silently
  if has_table_privilege('service_role', 'public.billing_keys', 'select') is distinct from true
    then v_bad := v_bad || ' service_role이 billing_keys를 못 읽는다(카드 등록·해지가 죽는다)'; end if;

  -- the seal this file does NOT change, asserted so a future slice cannot quietly trade one for
  -- the other: RLS stays on and the policy count stays zero
  if (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = 'billing_keys') is distinct from true
    then v_bad := v_bad || ' billing_keys에 RLS가 없다'; end if;
  select count(*) into v_n from pg_policies where schemaname='public' and tablename='billing_keys';
  if v_n <> 0 then v_bad := v_bad || ' billing_keys에 정책이 생겼다=' || v_n; end if;

  if v_bad <> '' then
    raise exception '0161 VERIFY 실패:%', v_bad;
  end if;
end $mig$;
