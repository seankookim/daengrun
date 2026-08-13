-- ═══ 124 profiles column-grant suite — 0088 pins (RLS is row-level; the columns need a wall) ═══
-- G1-G6 = the wall and its legitimate bypasses. G7-G8 = the ONE door (`incident_contact`, §E).
-- Purpose: `0002:56-58` makes every verified runner's profile ROW readable. Until 0088 there was
--   no column grant on `profiles`, so that row predicate published `phone` and `toss_customer_key`
--   to `authenticated` — and, because the policy has no `to` clause and no `auth.uid()` test, to
--   `anon` as well. These pins assert the WALL (G1/G2/G4), the DOOR that must stay open or the app
--   dies (G3), the two legitimate bypasses that must keep working (G5: service_role + definers),
--   and the one bypass that must stay narrow (G6: views run as their owner).
-- Style: sibling of 98/99/113 — `_pass('pcg',…)`/`_fail('pcg',…)`, one begin…exception per case,
--   `set local role` + `request.jwt.claim.sub` for every client path, and ALWAYS `reset role`.
--   ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
--   ⚠ Denials are asserted by CATCHING the error, so every attack query goes through `execute`
--     (a plain SQL statement in plpgsql is planned when the block is first executed, but the
--     privilege check happens at execution — `execute` keeps the failure inside our handler and
--     keeps the plan from being cached across role switches).
--
-- ⚠ WHY THIS SUITE AND NOT A NEW ARM OF 98/99 — and the gap that is worth recording:
--   **No pin in 98 or 99 could ever have caught this, and the reason is structural, not sloppy.**
--   · 99 S1 and 98 H1 are the two schema-wide tripwires, and both watch FUNCTIONS: S1 sweeps
--     `has_function_privilege('anon', …, 'execute')` over every definer, H1 sweeps `proconfig` for
--     `pg_temp`. Neither has ever looked at a TABLE privilege, let alone a column one.
--   · 99's table-level pins (S2-S5, S8) are all about WRITES — column-guard triggers on bookings /
--     runs / runners / runner_documents. The repo's instinct after 0057 was "clients must not
--     WRITE the wrong column"; nobody wrote the reading half.
--   · 113 K14 is the closest thing that existed, and it still could not have caught it, twice
--     over: it is scoped to `km_lots`/`km_ledger` (the tables 0075 created), and its matrix is
--     `has_table_privilege` — TABLE level. `has_column_privilege` appears NOWHERE in this repo
--     before this file (grep, 2026-08-13). 0075 §D wrote the law down in a comment and applied it
--     to every table born after it; `profiles` was born in 0001, before the law, and no sweep
--     ever went back for it. A law that is only ever applied going forward is not a sweep.
--   · The one shape that would have caught it is a schema-wide "which tables expose a column the
--     client never reads" sweep, and that cannot be automated — it needs the app-usage judgement
--     0088 §A makes by hand. So G1's fourth arm is the nearest safe automation: for `profiles`
--     specifically, the client-readable column set must EQUAL the whitelist. A future
--     `alter table profiles add column …` lands outside it and reddens here — which is the exact
--     failure mode that put `toss_customer_key` (0076) into the public payload in the first place.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert (house law) ───
--   G1 ← 0088 §D: `grant select on profiles to authenticated` (the pre-0088 world)         → RED
--   G2 ← 0088 §D: `grant select (id,name,handle,avatar_url,district) on profiles to anon`  → RED
--   G3 ← 0088 §D: drop `id` from the granted column list — the subtle one. `update profiles …
--        where id = auth.uid()` (api.ts:1451/2016) needs SELECT on a column it only FILTERS on  → RED
--   G4 ← 0088 §D: as G1 (a table-wide grant makes `select *` succeed again)                → RED
--   G5 ← 0088 §D: `revoke select on profiles from service_role` — billing's read of
--        `toss_customer_key` (create-payment-intent:38) and the club roster's phone rule    → RED
--   G6 ← 0015: add `p.phone` to `available_runners` — a definer view tunnels straight
--        through a column grant, and this is the repo's known bypass class                 → RED
--   G7 ← 0088 §E: remove EITHER gate from `incident_contact` — the party gate (it becomes an
--        enumeration oracle over phone numbers keyed by booking id) or the open-incident gate
--        (a party keeps the number forever, which is the thing 안심번호 exists to prevent) → RED
--   G8 ← 0088 §E: `grant execute on function incident_contact(uuid) to anon`               → RED
--
--   ✔ MUTATION-PROVEN by full-harness runs, 2026-08-13. Every line below is an OBSERVED run of
--     the FINAL text of this file, on the MERGED tree (`origin/redesign-v4` merged into
--     `claude/g1-ops-club-decisions`: 0085/121 + 0086/122 present), from an isolated /tmp copy
--     (a worktree path overruns the 103-byte unix socket limit).
--     **Baseline before 0088 = 471/0. Green with 0088 + this suite = 479/0.** Restore → 479/0.
--       ⓐ `grant select on profiles to authenticated` (the pre-0088 world) →
--          **475/4, red = [G1, G4, G5, G8]**. G1: `readable={avatar_url,created_at,district,handle,
--          id,name,phone,role,toss_customer_key,updated_at}` — the whole row, which is the bug
--          verbatim. G5 and G8 redden on their CONTRAST arms (`직접읽기 거부=false`), and that is
--          correct rather than a smear: a definer door means nothing if the caller could read the
--          column directly anyway, so both pins assert the direct path stays shut.
--          ⚠ MY PREDICTION WAS WRONG HERE and the correction is worth keeping: I expected G2. It
--          stays GREEN, because a table-wide grant to `authenticated` gives `anon` nothing. The
--          two roles have to be pinned separately — which is exactly why G2 exists as its own pin
--          rather than as an arm of G1.
--       ⓑ `grant select (…) on profiles to anon` added → **478/1, red = [G2]** (clean single;
--          `name raised=false · anon-readable cols=5`).
--       ⓒ `id` dropped from the granted list → **476/3, red = [G1, G3, G4]**, all with
--          `permission denied for table profiles`. Also not the clean single I predicted, and the
--          cascade is the finding: without `id` in the grant, EVERY query that filters `where
--          id = $1` dies, so the three pins that use that shape die with it. That is a fair
--          picture of the blast radius — `id` is not decoration in this list. Nothing OUTSIDE
--          this suite sees it: every other suite's profile access runs as postgres, the table
--          owner (113 K22's lesson, remeasured).
--       ⓓ `revoke select on profiles from service_role` → **477/2, red = [G5, axes X2]**.
--          ⚠ The SECOND red is a finding, not noise: `70_axes_suite`'s X2 (`완료 백필 —
--          ended/payable`) also goes red, so service_role's read of `profiles` is load-bearing
--          somewhere beyond billing. Whoever narrows service_role's grants later should start
--          from that pin, not from this file's §C paragraph.
--       ⓔ `p.phone` added to `available_runners` → **478/1, red = [G6]** (clean single), and the
--          message NAMES the leak: `화이트리스트 밖 뷰 컬럼=[available_runners.phone]`. 98's own
--          view pins stay green — they watch the other view's column list, not this one.
--       ⓕ `incident_contact`'s PARTY gate deleted → **478/1, red = [G7]** (clean single):
--          `무관자=2` — the stranger gets both numbers. This is the enumeration oracle 0088 §E
--          warns about, and only this suite sees it.
--       ⓖ `incident_contact`'s OPEN-INCIDENT gate deleted → **478/1, red = [G7]** (clean single):
--          `인시던트 전=2 · 해소 후=2` — a party keeps the counterparty's number before and after,
--          i.e. forever. That is precisely the harm 안심번호 exists to prevent, which is why the
--          resolve-then-recheck arm ⑤ is in G7 and not left as "obviously fine".
--       ⓗ `grant execute on function incident_contact(uuid) to anon` →
--          **477/2, red = [G8, sec S1]**. ⚠ The second red is the GOOD news and worth stating:
--          99 S1's schema-wide anon-execute sweep already covers this new function
--          (`anon 실행 가능 definer 함수 1개`). G8's anon arm is therefore belt-and-braces, and
--          the belt is the one that was already there.
--
--   🔎 Found by writing these pins, before any mutation: `select *` into a jsonb variable reddens
--     for the WRONG reason once the grant is re-widened (`invalid input syntax for type json`, a
--     casting artifact, not a privilege result). G4 now wraps it in `count(*)` over a subselect —
--     same privilege demand, honest failure message. A pin that goes red for a reason other than
--     the one it claims is a pin you cannot read at 2am.
--
--   ⚠ WHAT THESE PINS DELIBERATELY DO NOT ASSERT:
--   · That row visibility is correct. `profiles public runner read` still publishes every verified
--     runner's row to anyone; 0088 §C says why that is left alone (the storefront needs it). G1's
--     third arm PINS that the row stays visible — so anyone who "fixes" the leak by deleting the
--     policy learns here that they broke find-now instead of the leak.
--   · That `profiles` WRITES are whitelisted. They are not (0088 §0b) — a client can still UPDATE
--     their own `role`/`handle`/`toss_customer_key`. That is a separate slice with separate pins,
--     and a green run here must not be read as covering it.
--   · Anything about PostgREST itself. The harness sees SQL; that `?select=*` maps to `select *`
--     is an inference from the grant, verified by hand, not by this file.
--   · That decision ⑪ works. G7/G8 pin the DOOR (`incident_contact`), not the feature. Nothing
--     calls it, `profiles.phone` is null for every real user (PASS is not integrated) and nothing
--     writes `incidents` — see 0088 §E's two measured caveats. G7 supplies both fixtures by hand
--     precisely because production supplies neither; a green G7 says the gate is right, not that
--     ⑪ exists.
set client_min_messages = warning;

do $$
declare
  rr uuid; oo uuid; hh uuid; rt uuid;
  v_club uuid; v_s uuid;
  zz uuid; dg uuid; v_bk uuid; v_inc uuid;      -- G7: stranger · booking party fixture
  v_rows int; v_rows2 int; v_rows3 int; v_rows4 int;
  v_owner_ph text; v_runner_ph text;
  v_tck constant uuid := '0088cafe-0000-4000-8000-000000000088';
  v_phone constant text := '010-8800-0088';
  -- The whitelist, stated once. Every arm below derives from THIS array, so widening the grant
  -- without widening the deliberate list cannot pass.
  -- [0091, 2026-08-13] `role` added — a pin whose asserted property legitimately changed, updated
  -- in the slice that changed it (CLAUDE.md). NOT a relaxation for convenience: `role` MUST be
  -- readable by `authenticated` or the app cannot sign anyone in. PostgREST renders
  -- `.upsert({id, role, name})` as `insert … on conflict (id) do update set role = excluded.role,
  -- …`, and Postgres requires SELECT on every column read in that SET list — `excluded.role`
  -- included. With 0088's grant and no `role`, the role picker returns 403 for EVERY user on the
  -- first screen, first signup included (the privilege check is per-statement, so the ON CONFLICT
  -- arm is checked even when nothing conflicts). Measured against real PostgREST 12.2.3, and
  -- re-measured here by hand against the reconstructed post-0088/pre-0091 grant state.
  -- ⚠ So this array and a working signup are the same fact. If this arm ever reddens because
  -- someone dropped `grant select (role)`, the fix is to restore the grant — NOT to shorten this
  -- list. Doing the latter re-ships the 403 with a green harness, which is the worst of both.
  -- `role` is safe to expose: `user_role` is ('owner','runner'), there is no admin value, and no
  -- SQL anywhere grants privilege on `profiles.role` (swept 2026-08-13; the only role-based gate
  -- is `club_members.role`, a different column on a different table).
  v_public constant text[] := array['id','name','handle','avatar_url','district','role'];
  v_txt text; v_txt2 text; v_txt3 text; v_txt4 text; v_msg text;
  v_uuid uuid; v_n int;
  v_e1 boolean; v_e2 boolean; v_e3 boolean; v_e4 boolean;
  v_got text[]; v_js jsonb; v_ok boolean;
begin
  -- ---------- seed: a verified runner carrying both secrets, plus an unrelated logged-in owner --
  rr := t_user('pcg_rr', 'runner');            -- t_user makes tier='certified' → the 0002:56 policy
  oo := t_user('pcg_oo', 'owner');             -- the snooper: no relationship to rr whatsoever
  hh := t_user('pcg_host', 'runner');
  rt := t_route('컬럼 코스');
  update profiles
     set phone = v_phone, toss_customer_key = v_tck,
         handle = 'pcg_runner', avatar_url = 'https://cdn.test/pcg.jpg', district = '컬럼동'
   where id = rr;
  update profiles set phone = '010-8800-0089' where id = oo;   -- G1 arm 5: even MY OWN phone

  -- ---------- [G1] authenticated: the row is visible, the two secret columns are not ----------
  -- Five arms. Arms 1-2 are the attack; arm 3 is the discrimination test (rows still visible, so a
  -- green here means COLUMNS were blocked, not that the fixture stopped being reachable); arm 4 is
  -- the schema tripwire; arm 5 pins 0088 §B's chosen trade-off (option (a): no self-read either).
  begin
    v_e1 := false; v_e2 := false; v_e3 := false; v_txt := null;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', oo::text, true);
      begin execute 'select phone from profiles where id = $1' into v_txt using rr;
      exception when insufficient_privilege then v_e1 := true; end;
      begin execute 'select toss_customer_key from profiles where id = $1' into v_uuid using rr;
      exception when insufficient_privilege then v_e2 := true; end;
      -- arm 3: the ROW is still readable through the whitelist (the storefront must survive)
      execute 'select name from profiles where id = $1' into v_txt2 using rr;
      -- arm 5: my own row, my own phone — still denied. Grants cannot say "only on your row".
      begin execute 'select phone from profiles where id = $1' into v_txt3 using oo;
      exception when insufficient_privilege then v_e3 := true; end;
      reset role;
    exception when others then reset role; raise;
    end;
    -- arm 4: the client-readable column set is EXACTLY the whitelist (nothing more, nothing less)
    select coalesce(array_agg(a.attname::text order by a.attname), '{}')
      into v_got
      from pg_attribute a
     where a.attrelid = 'profiles'::regclass and a.attnum > 0 and not a.attisdropped
       and has_column_privilege('authenticated', a.attrelid, a.attnum, 'select');
    v_msg := 'phone raised=' || v_e1 || ' tck raised=' || v_e2 || ' self-phone raised=' || v_e3
          || ' name=' || coalesce(v_txt2, '<null>')
          || ' readable={' || array_to_string(v_got, ',') || '}';
    if v_e1 and v_e2 and v_e3 and v_txt2 = 'pcg_rr'
       and v_got @> v_public and v_public @> v_got
      then call _pass('pcg','G1 authenticated — 행은 보이고 phone·toss_customer_key는 안 보인다 '
                            '(본인 행도 동일) · 읽기 가능 컬럼 집합 = 화이트리스트 정확히 일치');
    else call _fail('pcg','G1 authenticated 컬럼 봉인', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pcg','G1', v_msg);
  end;

  -- ---------- [G2] anon: no read at all — the app bundle's public key opens nothing ----------
  -- Pre-0088 this was the WORSE half of the hole: `profiles public runner read` carries no `to`
  -- clause and no auth.uid() test, so it matched `anon` too. Measured before the fix, with no JWT:
  --   set local role anon; select name, phone, toss_customer_key from profiles … → rows returned.
  begin
    v_e1 := false; v_e2 := false; v_e3 := false;
    begin
      set local role anon;
      perform set_config('request.jwt.claim.sub', '', true);
      begin execute 'select phone from profiles where id = $1' into v_txt using rr;
      exception when insufficient_privilege then v_e1 := true; end;
      begin execute 'select toss_customer_key from profiles where id = $1' into v_uuid using rr;
      exception when insufficient_privilege then v_e2 := true; end;
      -- anon gets NOTHING, not even the public five (0088 §D: the app is auth-gated)
      begin execute 'select name from profiles where id = $1' into v_txt using rr;
      exception when insufficient_privilege then v_e3 := true; end;
      reset role;
    exception when others then reset role; raise;
    end;
    select count(*) into v_n
      from pg_attribute a
     where a.attrelid = 'profiles'::regclass and a.attnum > 0 and not a.attisdropped
       and has_column_privilege('anon', a.attrelid, a.attnum, 'select');
    v_msg := 'phone raised=' || v_e1 || ' tck raised=' || v_e2 || ' name raised=' || v_e3
          || ' anon-readable cols=' || v_n;
    if v_e1 and v_e2 and v_e3 and v_n = 0
      then call _pass('pcg','G2 anon — profiles에서 읽을 수 있는 컬럼 0개 '
                            '(0002:56 정책이 to절 없이 anon까지 매치하던 절반을 그랜트로 닫는다)');
    else call _fail('pcg','G2 anon 봉인', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pcg','G2', v_msg);
  end;

  -- ---------- [G3] the door: every real app query shape still works ----------
  -- Four arms, each a MEASURED call site — this is the pin that says "the app still runs".
  --   ① fetchMyProfile   (api.ts:1436) — self row, `name, handle, district, avatar_url`
  --   ② fetchMyDistrict  (api.ts:145)  — self row, `district`
  --   ③ fetchCertifiedRunners (api.ts:788) — the PostgREST EMBED, which is a join on profiles.id
  --   ④ updateMyProfile  (api.ts:1451) — ⚠ the arm that catches dropping `id` from the grant:
  --      an UPDATE needs SELECT privilege on a column it merely FILTERS on, and `profiles self
  --      write` (0002:59) reads `id` in its USING too.
  begin
    v_txt := null; v_txt2 := null; v_txt3 := null; v_txt4 := null; v_n := 0; v_ok := false;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', rr::text, true);
      execute 'select name || ''|'' || handle || ''|'' || district || ''|'' || avatar_url
                 from profiles where id = $1' into v_txt using rr;                        -- ①
      execute 'select district from profiles where id = $1' into v_txt2 using rr;         -- ②
      perform set_config('request.jwt.claim.sub', oo::text, true);
      execute 'select p.name || ''|'' || p.district || ''|'' || p.avatar_url
                 from runners r join profiles p on p.id = r.profile_id
                where r.profile_id = $1 and r.tier <> ''applicant'''
        into v_txt3 using rr;                                                             -- ③
      execute 'update profiles set district = ''바꾼동'' where id = $1' using oo;          -- ④
      execute 'select district from profiles where id = $1' into v_txt4 using oo;
      reset role;
    exception when others then reset role; raise;
    end;
    v_msg := '① ' || coalesce(v_txt, '<null>') || ' · ② ' || coalesce(v_txt2, '<null>')
          || ' · ③ ' || coalesce(v_txt3, '<null>') || ' · ④ ' || coalesce(v_txt4, '<null>');
    if v_txt = 'pcg_rr|pcg_runner|컬럼동|https://cdn.test/pcg.jpg'
       and v_txt2 = '컬럼동'
       and v_txt3 = 'pcg_rr|컬럼동|https://cdn.test/pcg.jpg'
       and v_txt4 = '바꾼동'
      then call _pass('pcg','G3 문은 열려 있다 — fetchMyProfile·fetchMyDistrict·러너 임베드 조인 '
                            '전부 통과하고, id로 필터하는 self UPDATE도 통과 (grant에 id가 없으면 쓰기가 죽는다)');
    else call _fail('pcg','G3 앱 질의 형상', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pcg','G3', v_msg);
  end;

  -- ---------- [G4] `select *` FAILS LOUDLY — it does not silently narrow ----------
  -- This is the shape of the actual attack (`GET /rest/v1/profiles?select=*`). A column grant makes
  -- Postgres refuse the whole statement rather than return the granted subset, and that difference
  -- is the pin: a silent narrowing would hide a re-widened grant from every other test here.
  begin
    v_e1 := false; v_e2 := false; v_txt := null; v_txt2 := null;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', oo::text, true);
      -- wrapped in count(*) on purpose: `select *` straight into a variable would fail on TYPE
      -- coercion once the grant is re-widened, and a pin must go red on the PRIVILEGE, not on a
      -- casting artifact. The subselect still demands SELECT on every column of the table.
      begin execute 'select count(*) from (select * from profiles where id = $1) q'
              into v_n using rr;
      exception when insufficient_privilege then v_e1 := true; end;
      begin execute 'select count(*) from (select p.* from profiles p where p.id = $1) q'
              into v_n using rr;
      exception when insufficient_privilege then v_e2 := true; end;
      -- positive control: the same row, named columns only → succeeds. So the refusal above is
      -- about `*`, not about the row having become unreachable.
      execute 'select name from profiles where id = $1' into v_txt using rr;
      reset role;
    exception when others then reset role; raise;
    end;
    v_msg := 'select * raised=' || v_e1 || ' · select p.* raised=' || v_e2
          || ' · 명시 컬럼=' || coalesce(v_txt, '<null>');
    if v_e1 and v_e2 and v_txt = 'pcg_rr'
      then call _pass('pcg','G4 select * 는 조용히 좁아지지 않고 거부된다 '
                            '(PostgREST ?select=* 의 실제 모양) · 명시 컬럼은 그대로 통과');
    else call _fail('pcg','G4 select * 거부', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pcg','G4', v_msg);
  end;

  -- ---------- [G5] the two legitimate bypasses: service_role, and definers ----------
  -- ① service_role reads everything. `create-payment-intent/handler.ts:38` and
  --    `_shared/charge.ts:192` read `toss_customer_key` through `admin()` (_shared/ctx.ts:23).
  --    If this arm goes red, billing is off in production.
  -- ② A SECURITY DEFINER runs as its OWNER, so removing the caller's column privilege does not
  --    touch it. Proven end-to-end on the ONE definer in this schema that reads a column 0088
  --    takes away: `club_session_roster` (0049) returns a phone number, gated by
  --    `_club_phone_visible` (phone rule B: host ↔ everyone) — to the SAME `authenticated` role
  --    that just got `permission denied` reading that column directly in G1.
  begin
    perform set_config('request.jwt.claim.sub', hh::text, false);
    v_club := club_request_district('컬럼동');
    perform club_claim_host(v_club);
    v_s := club_create_session(v_club, now() + interval '90 minutes', '컬럼 집결지', rt, 8, 'mixed');
    perform set_config('request.jwt.claim.sub', rr::text, false);
    perform session_runner_commit(v_s);

    v_txt := null; v_uuid := null; v_txt2 := null; v_e1 := false;
    begin
      set local role service_role;
      execute 'select phone from profiles where id = $1' into v_txt using rr;             -- ①
      execute 'select toss_customer_key from profiles where id = $1' into v_uuid using rr;
      reset role;
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', hh::text, true);
      begin execute 'select phone from profiles where id = $1' into v_txt3 using rr;      -- ② 직접 = 거부
      exception when insufficient_privilege then v_e1 := true; end;
      v_js := club_session_roster(v_s);                                                   -- ② definer = 허용
      reset role;
    exception when others then reset role; raise;
    end;
    select p->>'phone' into v_txt2
      from jsonb_array_elements(v_js->'people') p where (p->>'profileId')::uuid = rr;
    v_msg := 'service_role phone=' || coalesce(v_txt, '<null>')
          || ' tck=' || coalesce(v_uuid::text, '<null>')
          || ' · 직접읽기 거부=' || v_e1 || ' · roster phone=' || coalesce(v_txt2, '<null>');
    if v_txt = v_phone and v_uuid = v_tck and v_e1 and v_txt2 = v_phone
      then call _pass('pcg','G5 정당한 우회 둘 — service_role은 전 컬럼을 읽고(엣지 결제), definer는 '
                            '소유자 권한으로 돌아 같은 authenticated에게 규칙 B의 전화를 내준다 '
                            '(그 역할이 직접 읽기는 거부당한 바로 그 컬럼)');
    else call _fail('pcg','G5 service_role·definer 우회', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pcg','G5', v_msg);
  end;

  -- ---------- [G6] the view bypass stays narrow ----------
  -- Views run with their OWNER's rights unless `security_invoker`, so a view over `profiles` is a
  -- hole straight through a column grant — this repo's known bypass class (98's definer-view
  -- reasoning, 0015's own header). Two arms:
  --   ① the storefront view still WORKS for authenticated (find-now must not break), and
  --   ② schema-wide: NO client-readable view anywhere exposes a `profiles` column outside the
  --      whitelist. Column-level dependencies in pg_depend make this exact, not a text grep — add
  --      `p.phone` to `available_runners` and this arm names it.
  begin
    v_txt := null;
    -- `runners.online` defaults false and the view filters on it — seed visibility explicitly
    -- rather than assuming, then put it back so no later suite inherits an online runner.
    update runners set online = true where profile_id = rr;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', oo::text, true);
      execute 'select name || ''|'' || district from available_runners where profile_id = $1'
        into v_txt using rr;                                                              -- ①
      reset role;
    exception when others then reset role; raise;
    end;

    select coalesce(string_agg(distinct v.relname || '.' || a.attname, ', '), '')          -- ②
      into v_txt2
      from pg_depend d
      join pg_rewrite rw on rw.oid = d.objid and d.classid = 'pg_rewrite'::regclass
      join pg_class v on v.oid = rw.ev_class and v.relkind in ('v', 'm')
      join pg_class src on src.oid = d.refobjid
      join pg_attribute a on a.attrelid = src.oid and a.attnum = d.refobjsubid
     where src.relname = 'profiles' and src.relnamespace = 'public'::regnamespace
       and d.refobjsubid > 0
       and not (a.attname = any (v_public))
       and (has_table_privilege('authenticated', v.oid, 'select')
            or has_table_privilege('anon', v.oid, 'select'));
    update runners set online = false where profile_id = rr;
    v_msg := 'view read=' || coalesce(v_txt, '<null>') || ' · 화이트리스트 밖 뷰 컬럼=[' || v_txt2 || ']';
    if v_txt = 'pcg_rr|컬럼동' and v_txt2 = ''
      then call _pass('pcg','G6 뷰 우회는 좁은 채로 — available_runners는 그대로 동작하고, '
                            '클라가 읽을 수 있는 어떤 뷰도 화이트리스트 밖 profiles 컬럼을 내보내지 않는다');
    else call _fail('pcg','G6 뷰 우회', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pcg','G6', v_msg);
  end;

  -- ---------- [G7] incident_contact — the one door, and both of its gates ----------
  -- Fixture built BY HAND on purpose: nothing in production writes `incidents` and nothing writes
  -- `profiles.phone` (0088 §E's two measured caveats), so a pin that waited for real data would be
  -- green forever without ever executing the gates. Five arms, and the last two are the security
  -- property — "not a party" and "no open incident" must be INDISTINGUISHABLE (both zero rows, no
  -- error), or the function becomes an oracle over which bookings have live incidents.
  begin
    zz := t_user('pcg_zz', 'owner');                        -- the stranger: party to nothing
    dg := t_dog(oo, '인시던트견');
    v_bk := t_av_booking(oo, dg, rt, rr, now() + interval '3 days', 5.0, 'active');
    v_rows := -1; v_rows2 := -1; v_rows3 := -1; v_rows4 := -1;
    v_owner_ph := null; v_runner_ph := null;
    begin
      -- ① a party, NO incident open yet → zero rows (not an error)
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', oo::text, true);
      execute 'select count(*) from incident_contact($1)' into v_rows using v_bk;
      reset role;
    exception when others then reset role; raise;
    end;
    insert into incidents (booking_id, reporter_id, kind, severity, note)
      values (v_bk, oo, 'dog_injury', 'urgent', 'pcg fixture') returning id into v_inc;
    begin
      set local role authenticated;
      -- ② a party, incident OPEN → exactly two rows, both real numbers
      perform set_config('request.jwt.claim.sub', oo::text, true);
      execute 'select count(*) from incident_contact($1)' into v_rows2 using v_bk;
      execute 'select max(phone) filter (where role = ''owner''),
                      max(phone) filter (where role = ''runner'') from incident_contact($1)'
        into v_owner_ph, v_runner_ph using v_bk;
      -- ③ the OTHER party sees it too (the ruling is two-sided)
      perform set_config('request.jwt.claim.sub', rr::text, true);
      execute 'select count(*) from incident_contact($1)' into v_rows3 using v_bk;
      -- ④ a stranger, same open incident → zero rows, NOT an error (the anti-oracle arm)
      perform set_config('request.jwt.claim.sub', zz::text, true);
      execute 'select count(*) from incident_contact($1)' into v_rows4 using v_bk;
      reset role;
    exception when others then reset role; raise;
    end;
    -- ⑤ resolve it: the door shuts again. Without this arm the pin would allow a party to keep
    --    the number forever, which is the exact harm 안심번호 exists to prevent.
    update incidents set resolved_at = now() where id = v_inc;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', oo::text, true);
      execute 'select count(*) from incident_contact($1)' into v_n using v_bk;
      reset role;
    exception when others then reset role; raise;
    end;
    v_msg := '인시던트 전=' || v_rows || ' · 열림(보호자)=' || v_rows2 || ' · 열림(러너)=' || v_rows3
          || ' · 무관자=' || v_rows4 || ' · 해소 후=' || v_n
          || ' · owner=' || coalesce(v_owner_ph, '<null>')
          || ' · runner=' || coalesce(v_runner_ph, '<null>');
    if v_rows = 0 and v_rows2 = 2 and v_rows3 = 2 and v_rows4 = 0 and v_n = 0
       and v_owner_ph = '010-8800-0089' and v_runner_ph = v_phone
      then call _pass('pcg','G7 incident_contact — 열린 인시던트 동안에만, 당사자 양쪽에게만 두 행. '
                            '인시던트 전·해소 후·무관자는 모두 0행이고 에러가 아니다 '
                            '(당사자 아님과 인시던트 없음이 구분되면 그 자체가 오라클이다)');
    else call _fail('pcg','G7 incident_contact 게이트', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pcg','G7', v_msg);
  end;

  -- ---------- [G8] the door's permission matrix — and that it is the ONLY door ----------
  -- Three arms: anon cannot execute it (99 S1's class, checked for this one function by name);
  -- authenticated can (positive control — a revoked-from-everyone function is a dead door, not a
  -- safe one); and the direct `profiles.phone` read STILL fails for the very party the function
  -- just served. That third arm is what makes "the only door" a measured claim rather than a
  -- design intention.
  begin
    v_e1 := false;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', oo::text, true);
      begin execute 'select phone from profiles where id = $1' into v_txt using rr;
      exception when insufficient_privilege then v_e1 := true; end;
      reset role;
    exception when others then reset role; raise;
    end;
    v_msg := 'anon exec=' || has_function_privilege('anon', 'incident_contact(uuid)', 'execute')
          || ' · auth exec=' || has_function_privilege('authenticated', 'incident_contact(uuid)', 'execute')
          || ' · 당사자 직접 phone 읽기 거부=' || v_e1
          || ' · definer=' || (select prosecdef from pg_proc where oid = 'incident_contact(uuid)'::regprocedure);
    if     not has_function_privilege('anon', 'incident_contact(uuid)', 'execute')
       and     has_function_privilege('authenticated', 'incident_contact(uuid)', 'execute')
       and     (select prosecdef from pg_proc where oid = 'incident_contact(uuid)'::regprocedure)
       and v_e1
      then call _pass('pcg','G8 문은 하나뿐 — incident_contact는 anon 실행 불가·authenticated 전용 definer이고, '
                            '방금 그 함수로 번호를 받은 당사자조차 profiles.phone 직접 읽기는 여전히 거부된다');
    else call _fail('pcg','G8 문 권한 매트릭스', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pcg','G8', v_msg);
  end;

  -- ---------- cleanup: leave no open club session behind (80/98 precedent) ----------
  -- G7's booking is deliberately left `active` and NOT closed: `active -> expired` is not a legal
  -- transition (`enforce_booking_transition`), and it needs no closing anyway — the open-pool view
  -- keys on `status = 'matching'`, so a non-matching booking cannot pollute it (99's header states
  -- the same rule for its own fixtures).
  update club_sessions set status = 'cancelled' where id = v_s and status in ('open', 'full');
end $$;

-- ═══ G — THE ANON SURFACE IS A WHITELIST, NOT A DISCOVERY ═════════════════════════════════
-- 0088 fixed ONE table. The class is bigger: an RLS policy with no caller term is a row filter,
-- not a gate, and because RLS is row-level the column grant is the other half. A hardening pass
-- that pins definer bodies and search_path (98/99) never asks the question that catches this:
-- **what does an unauthenticated `select *` actually return?**
--
-- So this pin asks it for EVERY table, every run. The expected set below was established by
-- execution on 2026-08-13, not by reading DDL — reading DDL is what missed `profiles` for a year.
-- A new anon-readable table fails the harness until someone adds it here DELIBERATELY, which is
-- the point: convention becomes constraint, and instance eight is caught by a gate rather than by
-- someone thinking to ask.
--
-- ⚠ Adding a name here is a privacy decision, not a merge fix. Each entry is anon-readable
-- WITHOUT AN ACCOUNT — the app's public key is in the shipped client. Justify it or seal it.
do $$
declare
  t record; n bigint; v_bad text := ''; v_msg text;
  -- Deliberately public, verified 2026-08-13. Marketplace/community browse surfaces that a
  -- logged-out visitor is meant to see. Each carries a reason because "it was already like that"
  -- is not one.
  expected text[] := array[
    'routes',                     -- public course catalog; 0082 makes public read the point
    'runners',                    -- the browse directory the marketplace exists to show
    'clubs', 'club_series', 'club_sessions', 'club_members', 'club_critical_titles',
                                  -- public club listings + membership; a social graph by design
    'feed_posts',                 -- the community feed
    'runner_availability_rules',  -- 🔴 REVIEW: a runner's weekly free/busy schedule, pre-login.
                                  --    Grandfathered so this pin can land; see the note below.
    -- NOT listed, deliberately, and worth knowing why: bookings · dogs · session_dogs ·
    -- session_people · session_runner_assignments · participant_activities all LOOK
    -- anon-readable if you test with a stale JWT claim, and are correctly gated once you clear
    -- it (is_active_runner() / is_booking_party() read auth.uid() inside the function, so a
    -- text scan of the policy cannot see the caller term either). Whitelisting them would have
    -- blinded this pin to a future real exposure of the six tables holding dog memos, addresses
    -- and club rosters.
    '_t'                          -- the harness's own results table, not a product surface
  ];
begin
  for t in select tablename from pg_tables where schemaname = 'public' order by tablename loop
    begin
      -- ⚠ CLEARING THE CLAIM IS THE WHOLE TEST. `set role anon` changes the ROLE; it does not
      -- clear `request.jwt.claim.sub`, which earlier suites set — so auth.uid() keeps returning
      -- a real user and every policy gated on it (is_active_runner(), is_booking_party(), …)
      -- still passes. The first draft of this pin omitted this line and reported SIX tables as
      -- anon-readable that are correctly gated; whitelisting them would have blinded this pin to
      -- a future real exposure of exactly those tables. A test of "what can a stranger see" must
      -- first make itself a stranger.
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'set local role anon';
      execute format('select count(*) from public.%I', t.tablename) into n;
      execute 'reset role';
      if n > 0 and not (t.tablename = any(expected)) then
        v_bad := v_bad || ' ' || t.tablename || '(' || n || '행)';
      end if;
    exception when others then execute 'reset role';
    end;
  end loop;
  if v_bad = ''
    then call _pass('pcg','G1 anon 노출면 화이트리스트 — 로그인 없이 읽히는 테이블은 명시된 것뿐 (새 테이블은 의도적으로 추가해야 통과)');
  else v_msg := '화이트리스트에 없는 테이블이 anon에게 읽힘:' || v_bad;
       call _fail('pcg','G1 anon 노출면 화이트리스트', v_msg); end if;
end $$;

-- 🔴 FOLLOW-UP recorded rather than silently grandfathered: `runner_availability_rules` exposes
-- (runner_id, weekday, start_min, end_min) — i.e. each runner's weekly schedule — to anyone with
-- the public key, no account required. That is personal-schedule data about the supply side, and
-- unlike `runners` (a directory a marketplace must show) it is not obviously required pre-login.
-- Not changed here: 0088's scope is `profiles`, and silently sealing another team's table on the
-- way past is how a fix becomes an outage. Raised in docs/security-profiles-column-exposure.md.
