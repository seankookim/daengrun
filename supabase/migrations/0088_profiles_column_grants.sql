-- ═══ 0088: profiles column grants — RLS is ROW-level; the columns need their own wall ═══
--
-- ═══ §0 THE HOLE, AS MEASURED ═══
-- `0002:56-58` opens every VERIFIED RUNNER's profile row to readers:
--
--     create policy "profiles public runner read" on profiles for select using (
--       exists (select 1 from runners r where r.profile_id = profiles.id and r.tier <> 'applicant')
--     );
--
-- That is a ROW predicate. There is no column grant on `profiles` anywhere in this repo (grep:
-- zero `grant select (...)` before this file), and the shim/production default privileges hand
-- `anon, authenticated` `arwd` on every new public table. So the policy publishes the WHOLE ROW:
--
--     · `phone`             (0001:30 — "PASS 본인인증 후 확정", a real personal phone number)
--     · `toss_customer_key` (0076 §B — the PG customer key whose ENTIRE PURPOSE is to keep our
--                            identifiers out of Toss's logs. Leaking it outward inverts that.)
--
-- Reproduced on a clean harness cluster (2026-08-13), seeded runner + unrelated logged-in owner:
--     set local role authenticated;  -- request.jwt.claim.sub = an unrelated owner
--     select name, phone, toss_customer_key from profiles where id = <the runner>;
--       →  피해자러너 | 010-1234-5678 | 11111111-2222-3333-4444-555555555555
--
-- ⚠ AND IT IS WORSE THAN "any logged-in user". The policy carries no `to` clause and no
--   `auth.uid()` test, so it applies to PUBLIC — **`anon` passes it too**. Measured on the same
--   cluster with no JWT at all:
--     set local role anon;
--     select name, phone, toss_customer_key from profiles where phone is not null limit 3;  → 3 rows
--   The anon key ships inside the app bundle. `GET /rest/v1/profiles?select=*` needed no account.
--   Nothing in the app renders these fields — but PostgREST returns what the GRANT allows, not
--   what the client asks for, and `select=*` is one query-string edit away.
--
-- ═══ §A THE WALL ═══
-- Column-level SELECT. RLS decides WHICH ROWS; grants decide WHICH COLUMNS — 0075 §D already
-- states this law ("🔴 RLS는 행만 막는다. 컬럼과 DML은 grant가 막는다") and 113 K14 pins it for
-- the km tables. `profiles` is the table that law was written about and never applied to.
--
-- THE SET, and why each member is in it (every one is a MEASURED app read, not a guess):
--   · id         — `.eq('id', …)` / `.in('id', ids)` and every PostgREST embed
--                  (`profiles!feed_posts_author_id_fkey(...)`) joins on it. ⚠ ALSO LOAD-BEARING FOR
--                  WRITES: `update profiles … where id = auth.uid()` (api.ts:1451, 2016) reads `id`
--                  in its WHERE, and `profiles self write`'s USING reads it too — Postgres requires
--                  SELECT privilege on a column an UPDATE merely FILTERS on. Drop `id` from this
--                  list and profile editing dies, not just reading.
--   · name       — api.ts:788, 981, 1436, 1686, 1878, 2180, 2368, 2405, 2676, 3040, 3146, 3326…
--   · avatar_url — api.ts:788, 1436, 1878, 2676, 3326
--   · district   — api.ts:145 (fetchMyDistrict), 788, 1436, 1878
--   · handle     — api.ts:1436 (self) and 3326 (feed post AUTHOR — a cross-user read). 0074 §A
--                  defines it as the Instagram-style public account id; it is meant to be seen.
--
-- AND WHAT IS DELIBERATELY OUT:
--   · phone, toss_customer_key — the hole. Zero client reads (grep of app/src: none).
--   · role                     — zero client reads. `session.role` (app/src/store.ts:5) is local
--                                UI state, not this column. Least privilege: not granted.
--   · created_at, updated_at   — zero client reads.
--   ⚠ This is a WHITELIST, so a NEW column is private by default. That is the point: the next
--     `alter table profiles add column …` does not silently join the public payload the way
--     `toss_customer_key` did in 0076.
--
-- ═══ §B THE TRAP: column grants are per-ROLE, not per-POLICY — and the decision taken ═══
-- Revoking `phone` from `authenticated` also blocks a user reading THEIR OWN phone through
-- `profiles self read` (0002:55). A grant cannot say "this column, but only on your own row".
-- **Chosen: (a) revoke outright. No `my_profile()` definer is created here, and none exists.**
--   ① Nothing reads it. No client query in app/src selects `profiles.phone` — this breaks no
--      screen today, and inventing an unused definer is the speculative abstraction CLAUDE.md
--      forbids (it would also be new anon-reachable surface needing its own 98 H1 seal and pins).
--   ② The house already has the right shape for the ONE case where a phone must be disclosed:
--      `club_session_roster` (0049) is a SECURITY DEFINER that reads `p.phone` and gates each
--      person's number behind `_club_phone_visible`, logging the access. Disclosure of a phone
--      number in this product is a DECISION, and decisions live in definers, not in grants.
--   ③ So the honest statement of the gap, for whoever needs it next: **there is no self-read path
--      for `profiles.phone` or `profiles.toss_customer_key` from a client.** When a screen needs
--      the owner's own phone (e.g. a "confirm your PASS number" row), add
--      `my_profile()` — `language sql stable security definer set search_path = public, pg_temp`,
--      `select … from profiles where id = auth.uid()`, `revoke from public, anon` +
--      `grant execute to authenticated` — and pin it. Do NOT re-widen this grant to do it: a grant
--      cannot distinguish your row from a runner's, which is the entire bug above.
--   ④ ⚠ ONE such definer IS built here, in §E, and it is the reason this file is "revoke AND
--      provide" rather than just "revoke": `incident_contact`. It is the worked example of ③.
--
-- ═══ §C WHAT IS UNAFFECTED — verified in the catalog, not assumed ═══
--   · **service_role keeps everything.** The revoke names `public, anon, authenticated` only, and
--     service_role holds `arwdDxt` from 0001's default privileges. This is load-bearing:
--     `create-payment-intent/handler.ts:38` and `_shared/charge.ts:192` read `toss_customer_key`
--     through `admin()` (`_shared/ctx.ts:23` — the SERVICE_ROLE_KEY client). §D re-grants it
--     explicitly so a future blanket revoke cannot silently unplug billing. Pinned: 124 G5.
--   · **Definer functions run as their owner (postgres), so every existing RPC is untouched.**
--     Catalog sweep of `public`: 14 functions read `profiles`, and all 14 are `prosecdef` — the
--     only non-definer reader is `t_user`, a harness helper that runs as postgres. Exactly one
--     definer reads a column this file removes from clients: `club_session_roster` reads
--     `p.phone`. Pinned end-to-end by 124 G5, which shows the SAME authenticated caller getting
--     `permission denied` on a direct read and the phone number through the RPC.
--   · **The known view bypass is clean.** Views run with their OWNER's rights unless
--     `security_invoker`, so a view over `profiles` would tunnel straight through this grant.
--     One view depends on `profiles`: `available_runners` (0015), owner `postgres`, no
--     `security_invoker`, selecting `p.name, p.district, p.avatar_url` — a subset of §A's set, so
--     it leaks nothing. 124 G6 pins that it STAYS a subset, which is the pin that reddens the day
--     somebody adds `p.phone` to it. (`marketplace_open_requests` does not touch `profiles`.)
--   · **The 0002 policies are NOT touched.** Row visibility is unchanged on purpose: narrowing the
--     runner-read policy is a product decision (the storefront needs those rows) and would move
--     several suites. This file changes only what a visible row is allowed to SHOW.
--
-- ═══ §0b WHAT THIS FILE DOES NOT DO (0073/0075 lesson: unstated scope reads as a seal) ═══
-- - **It does not touch INSERT/UPDATE/DELETE grants on `profiles`, and that gap is real.** With
--   `profiles self write` (0002:59) and no column guard trigger on this table, a client can still
--   UPDATE their own `role`, `handle` and `toss_customer_key` directly. 0074's own comment already
--   names it ("클라 직접 UPDATE는 컬럼 화이트리스트가 없으므로 신뢰하지 않는다"). A write whitelist
--   is a DIFFERENT change with different pins and its own blast radius (the 0073 `addresses`
--   pattern, or a `_guard_profile_cols` trigger like 0057's) — it is not smuggled in here. This
--   file closes the READ hole only.
-- - It creates no policy, no table, no view, and re-creates nothing (REGISTRY.md silent-collision
--   rule: **NONE**). It creates exactly ONE new function, `incident_contact` (§E), which nothing
--   calls yet.
-- - **§E does not build ⑪.** No two-sided verification, no `incidents` writer, no screen. It builds
--   only the read door ⑪ will need. See §E's own scope note.
--
-- ═══ §0d DOCTRINE ═══
-- Mutation-proven pins in `124_profiles_column_grant_suite.sql` (G1-G8). Pins this file must not
-- break: 67 H4/H5 (`club_session_roster`'s phone rule B), 112 (handle/feed), 98 H2 (the definer
-- view path), 98 H1 (§E carries `set search_path = public, pg_temp` IN THE BODY), 99 S1 (§E is
-- revoked from anon), and every `set local role authenticated` block in 95-122.

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §D the grant itself
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- Order matters: revoke first, then re-grant the whitelist. `revoke select on profiles` clears
-- both the table-wide privilege and any column privileges under it, so this is idempotent — a
-- re-run cannot accumulate a stale column.
revoke select on profiles from public, anon, authenticated;

-- `authenticated` only. `anon` is granted NOTHING: the app is auth-gated (`auth-context.tsx` —
-- "index guards routing"), no client query reads `profiles` without a session, and the sibling
-- storefront view `available_runners` is likewise authenticated-only (0015:41). anon's ability to
-- read runner rows at all was an accident of a `to`-less policy, not a feature. 0075 §D is the
-- house precedent for this shape.
grant select (id, name, handle, avatar_url, district) on profiles to authenticated;

-- Explicit, not redundant: the edge functions' `toss_customer_key` read is the one path that MUST
-- keep whole-row access, and stating it here means a future `revoke ... from public` sweep that
-- catches service_role turns 124 G5 red instead of turning billing off in production.
grant select on profiles to service_role;

comment on column profiles.phone is
  '0001: PASS 본인인증 후 확정. [0088] 클라이언트는 이 컬럼을 SELECT할 수 없다 (컬럼 그랜트에서 제외) —
본인 행이라도 마찬가지다. 전화번호 공개는 판단이므로 definer를 통한다: 클럽은 club_session_roster(0049)가
_club_phone_visible로 상대를 가려 보여주고 접근을 로그하며, 마켓플레이스는 incident_contact(0088 §E)가
열린 인시던트 동안 당사자에게만 내준다. 본인 조회가 필요해지면 my_profile() definer를 새로 만들 것 —
이 그랜트를 다시 넓히지 말 것 (그랜트는 내 행과 러너의 행을 구분하지 못한다).';

comment on column profiles.toss_customer_key is
  '0076: Toss customerKey — profiles.id와 무관한 난수. 내부 식별자를 외부 PG에 넘기지 않기 위한 것이고,
id에서 유도하면 그 목적이 사라진다. 프로필당 하나로 고정(unique).
[0088] service_role 전용 컬럼: anon·authenticated는 SELECT 불가. 읽는 주체는 엣지 함수
(create-payment-intent, _shared/charge.ts)의 admin() 클라이언트뿐이다.';

-- ═══════════════════════════════════════════════════════════════════════════════════════
-- §E incident_contact — the ONE door a phone number may legitimately walk through
-- ═══════════════════════════════════════════════════════════════════════════════════════
-- ⚠ WHY THIS IS IN THE SAME FILE AS THE REVOKE. §D closes the only path by which a client can
-- reach `profiles.phone`. Decision ⑪ (two-sided incident verification) is going to need one:
-- during an incident BOTH parties must see each other's number on screen. Shipping the revoke
-- alone would make ⑪ unbuildable, and the next person would "fix" that by re-granting the column —
-- which puts every verified runner's number back in front of every logged-in user, i.e. exactly
-- the P0 this file exists to close. So the safe route opens in the same commit the unsafe one shuts.
--
-- ⚠ RELAYED, NOT VERIFIED — READ THIS BEFORE BUILDING ON IT. Sean's ruling in
-- `docs/decisions/incident-verification.md` is "incident verified by both runner and owner"; that
-- document, **on this branch AND on `origin/redesign-v4` (checked 2026-08-13), says nothing about
-- phone numbers.** The phone requirement reached this file as a relayed instruction, and
-- CLAUDE.md is explicit that a relayed decision is evidence, not authority. This function is
-- built anyway because it is strictly SAFER than the status quo in every direction — today every
-- authenticated user reads every verified runner's phone with no gate at all, and after this
-- file only a booking party during an OPEN incident can, through one audited function. But
-- **nothing calls it**, so no number moves until ⑪ is built, and whoever builds ⑪ must first put
-- Sean's own words about phone disclosure on origin.
--
-- ⚠ 안심번호 (masked relay) IS THE KOREAN NORM AND WE ARE NOT DOING IT — deliberately, for now.
-- Kakao T and the delivery apps interpose a masked relay number so neither party keeps the
-- other's real number after the job. We ship REAL numbers because relay needs a telco
-- integration we do not have. That is a pilot trade-off, not an oversight, and it has a hard
-- prerequisite: **`docs/legal/privacy-policy.md` must disclose that the counterparty sees your
-- real number during an incident BEFORE ⑪ ships.** Not edited here (this file has no business in
-- the legal docs) — recorded here so it is not rediscovered after launch.
--
-- ⚠ TWO FACTS THAT MAKE THIS FUNCTION RETURN NOTHING TODAY, both measured 2026-08-13, both of
-- which ⑪ must handle before it renders a screen:
--   ① `profiles.phone` IS NULL FOR EVERY REAL USER. PASS is not integrated: no migration, no edge
--      function and no client code ever writes this column (grep — the only writers are test
--      suites). `runner_applications.contact_phone` (0062) and `emergency_contacts.phone` are
--      DIFFERENT columns and are not copied here. ⑪ would render two empty rows.
--   ② NOTHING WRITES `incidents` EITHER. The table is 0001:383 and its RLS is 0002:151, but no
--      migration, edge function or client inserts a row — `sendSOS` (api.ts:2439) only writes a
--      `notifications` row. So the state gate below can never be satisfied yet. That is correct
--      behaviour for an unbuilt feature (zero rows, no error), not a bug in this function.
--
-- ⚠ SCOPE: this is the READ DOOR ONLY. It does not build ⑪ — no two-sided stamp, no `incidents`
-- writer, no state machine, no screen. `docs/decisions/incident-verification.md` owns that, and
-- its build notes say to model it on 0083's return-handoff machine WITHOUT re-creating 0083's
-- objects.
--
-- THE GATES, IN THIS ORDER (CLAUDE.md: party gate before state gate):
--   ① PARTY. The caller must be the booking's owner or its assigned runner. Without this the
--      function is an enumeration oracle over phone numbers keyed by booking id — strictly worse
--      than the leak §D closes, because it would survive every future grant audit.
--   ② STATE. An incident must be OPEN for that booking. `incidents.resolved_at is null` is the
--      real predicate, not an invented flag — `resolved_at` is 0001:391 and it is what 0002:151's
--      own policy family treats as the incident's lifetime. (`club_incidents.state` is the CLUB
--      side's separate model — 0045/0067/0072 — and is deliberately not consulted: this function
--      keys on a marketplace `bookings.id`.)
--
-- BOTH FAILURES RETURN ZERO ROWS, NOT AN ERROR, AND THAT IS THE SECURITY PROPERTY:
--   "you are not a party" and "there is no open incident" must be INDISTINGUISHABLE to the
--   caller. Raising `not_party` would turn the function back into an oracle — a stranger could
--   sweep booking ids and learn which ones have live incidents. Only `not_signed_in` raises,
--   because that is a fact about the caller's own session and leaks nothing about anyone else.
create or replace function incident_contact(p_booking uuid)
returns table (role text, name text, phone text)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare b record;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;

  -- ① party gate. `select … into` + `found` rather than `is_booking_party()` because the two
  -- party ids are needed for the result anyway, and one read beats two.
  select owner_id, runner_id into b from bookings where id = p_booking;
  if not found then return; end if;                        -- unknown booking: silence, not 404
  if auth.uid() is distinct from b.owner_id
     and auth.uid() is distinct from b.runner_id then
    return;                                                -- stranger: silence, not an error
  end if;

  -- ② state gate.
  if not exists (select 1 from incidents i
                  where i.booking_id = p_booking and i.resolved_at is null) then
    return;
  end if;

  -- Both parties, always both — the ruling is that each side sees the other, and a caller who
  -- also sees their own number learns nothing they did not type in themselves. An unassigned
  -- booking yields ONE row (the owner): the join drops a null runner rather than inventing a
  -- placeholder person.
  return query
    select v.who, p.name, p.phone
      from (values ('owner', b.owner_id), ('runner', b.runner_id)) as v(who, pid)
      join profiles p on p.id = v.pid
     order by v.who;
end $$;

revoke execute on function incident_contact(uuid) from public, anon;
grant  execute on function incident_contact(uuid) to authenticated;

comment on function incident_contact is
  '0088 §E: 열린 인시던트 동안 예약 당사자끼리 서로의 전화번호를 본다 (결정 ⑪).
게이트 순서 = 당사자 → 상태. 당사자가 아니거나 열린 인시던트가 없으면 **에러가 아니라 0행** —
두 경우가 구분되면 부킹 id를 훑어 인시던트 유무를 알아내는 오라클이 된다.
⚠ 아직 아무도 호출하지 않는다. profiles.phone은 현재 전원 NULL(PASS 미연동)이고 incidents에
행을 넣는 코드도 없다. 실번호를 쓰는 것은 안심번호(통신사 연동) 부재로 인한 파일럿 절충이며,
⑪ 출시 전에 개인정보처리방침에 "인시던트 중 상대방에게 내 번호가 보인다"가 고지돼야 한다.';
