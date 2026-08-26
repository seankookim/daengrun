-- ═══ 125 profiles WRITE column-grant suite — 0091 pins (the other half of 0088's wall) ═══
-- W1-W3 = the wall (what a client must never write). W4-W5 = the door (what the app actually
-- writes, including the ONE statement nobody had ever executed). W6-W7 = DELETE and anon.
-- W8 = the legitimate bypass (service_role). W9 = the schema tripwire.
--
-- Purpose: `profiles self write` (0002:59) is a ROW predicate with no column guard, and the
--   Supabase default privileges hand `authenticated` table-wide INSERT/UPDATE/DELETE. So before
--   0091 a client could `PATCH /profiles?id=eq.<self>` with `{"toss_customer_key": …}` and
--   desynchronise itself from Toss AFTER `settle_run_tx` had already paid the runner (0091 §B),
--   or with `{"handle":"admin"}` and walk around every rule in `set_my_handle` (0091 §D).
--
-- Style: sibling of 124 — `_pass('pwg',…)`/`_fail('pwg',…)`, one begin…exception per case,
--   `set local role` + `request.jwt.claim.sub` for every client path, ALWAYS `reset role`.
--   ⚠ `_fail` arguments pre-computed into v_msg, never a subquery (the 110 header law).
--   ⚠ Denials asserted by CATCHING, so every attack goes through `execute` (privilege is checked
--     at execution; `execute` keeps the failure in our handler and the plan out of the cache).
--
-- ⚠⚠ W5 IS THE REASON THIS SUITE EXISTS IN THIS SHAPE. 0091 §E records a P0 that 0088 introduces
--   and that 124 structurally cannot see: PostgREST turns `.upsert({id,role,name})` into
--   `INSERT … ON CONFLICT("id") DO UPDATE SET "id"=EXCLUDED."id", "name"=…, "role"=…`, which needs
--   UPDATE on `id` and — the killer — **SELECT on `role`**, which 0088 revoked. Measured against a
--   real PostgREST v12.2.3: post-0088, both first signup and role switch return HTTP 403.
--   124 G3's arm ④ tests `update profiles set district = …`; nothing ever executed the upsert
--   shape. W5 executes that statement text verbatim, in SQL, so the harness owns it from now on.
--
-- ⚠ ONE SHIPPED PIN LEGITIMATELY MOVES, and it is not this suite's to move:
--   `124:132`'s `v_public constant text[] := array['id','name','handle','avatar_url','district']`
--   must gain `'role'`. 0091 §H grants `select (role)` because §E② requires it. 124 G1's fourth
--   arm asserts set EQUALITY against `v_public`, so it goes RED until that array is updated —
--   correctly: it is the tripwire noticing that the read surface changed, which is its job.
--   125 W9 owns the WRITE sets; the READ set stays 124 G1's property, one owner per pin.
--
-- ─── MUTATION map — OBSERVED, not predicted (full-harness runs, 2026-08-13, this worktree) ───
--   With 0091 + this suite = **515 pins, 514/1** — the one red is `[pcg] G1`, predicted in the note
--   above and explained by ⓑ below. Restore after every mutation → 514/1.
--   The **506/0** baseline is not quoted from a doc, it is what run ⓑ shows: with `select (role)`
--   removed the only red among 515 is W5, so all 506 pre-existing pins are green there, and
--   515 − 9 (W1-W9) = 506. Every number below is an observed full-harness run in this worktree.
--
--   ⓐ delete `revoke insert, update, delete … from public, anon, authenticated`
--        → **508/7, red = [pcg G1, W1, W2, W3, W6, W7, W9]**. The whole wall is that one line.
--        ⚠ W7 in this list is the finding: the revoke is the ONLY thing sealing `anon`, because
--          nothing re-grants to anon and the Supabase default privileges had already given it
--          table-wide `arwd`. anon's write access was never a decision, it was a default.
--   ⓑ delete `grant select (role)` → **514/1, red = [W5] and `[pcg] G1` GOES GREEN.**
--        ⚠ THE DECISIVE RUN. It proves the two facts are ONE decision, not a coincidence: the
--          single line that makes 124 G1 red is the same single line that makes the role picker
--          work at all. Green-124 and working-signup are mutually exclusive until 124:132's
--          `v_public` gains `'role'`. Anyone tempted to "fix the red" by deleting this grant is
--          re-shipping the 403 — that is why the mutation is recorded here rather than described.
--   ⓒ drop `id` from the UPDATE list → **511/4, red = [pcg G1, W5, W6, W9]**.
--        W6 is not noise: without `update (id)` the id-rewrite dies at the GRANT instead of at the
--        POLICY, and W6 asserts the message says `row-level security`. A pin that accepts "denied,
--        somehow" would let 0091 §F's claim rot silently.
--   ⓓ add `handle` to the UPDATE list → **512/3, red = [pcg G1, W3, W9]** — W3's conjunction
--        catches it even though arm ② (the RPC) is unaffected, which is why it is one pin.
--   ⓔ drop `district`,`avatar_url` from the UPDATE list (over-tightening) →
--        **510/5, red = [pcg G1, pcg G3, W2, W4, W9]**. ⚠ `124 G3` in this list is the good news:
--        0088's own door-is-open pin already guards `district`, so the two suites overlap exactly
--        where the app would break. W2 reddens because its trigger arm writes `district`.
--   ⓕ keep `delete` for authenticated (revoke only insert+update) →
--        **511/4, red = [pcg G1, W6, W7, W9]** — W7 again, for ⓐ's reason applied to DELETE alone.
--   ⓖ add `grant update (name) on profiles to anon` → **513/2, red = [pcg G1, W7]** (clean single).
--   ⓗ `revoke insert, update, delete on profiles from service_role` →
--        **513/2, red = [pcg G1, W8]** (clean single). ⚠ Unlike 124's ⓓ (which also reddened
--        `70_axes` X2 on the READ side), nothing outside this suite depends on service_role's
--        WRITE access to `profiles` — so the write direction really is billing-only.
--
--   🔎 W9 reddens under five of the eight mutations and that is the design, not a smear: it is the
--     derived tripwire, so every deliberate change to the write surface must pass through it. The
--     per-behaviour pins say WHAT broke; W9 says the surface moved at all.
set client_min_messages = warning;

do $$
declare
  w uuid; fresh uuid; bare uuid; killme uuid;
  v_e1 boolean; v_e2 boolean; v_e3 boolean; v_e4 boolean;
  v_txt text; v_txt2 text; v_txt3 text; v_msg text; v_err text;
  v_uuid uuid; v_n int; v_ts timestamptz;
  v_tck constant uuid := '0091cafe-0000-4000-8000-000000000091';
  -- [0133] 하이픈 제거 — profiles_phone_shape CHECK 는 정규화된 숫자만 받는다
  -- (^01[0-9]{8,9}$). 이 픽스처는 **권한**에 대한 핀이지 형식에 대한 핀이 아니므로 값이 바뀌어도
  -- 이 파일이 주장하는 명제는 그대로다. 계약서 §2 가 이 비용을 미리 적어 두었다.
  v_phone constant text := '01089000091';
  -- The write whitelists, stated once. Every arm below derives from THESE, so widening a grant
  -- without widening the deliberate list cannot pass. (0091 §H is the only place they are set.)
  v_upd constant text[] := array['avatar_url','district','id','name','role'];
  v_ins constant text[] := array['id','name','role'];
  v_got text[]; v_got2 text[];
begin
  -- ---------- seed ----------
  w := t_user('pwg_w', 'owner');              -- the user under test, writing their OWN row
  update profiles set phone = v_phone, toss_customer_key = v_tck, handle = 'pwg_w_handle'
   where id = w;
  -- an auth.users row with NO profile: the fresh-signup fixture (t_user always makes a profile)
  fresh := gen_random_uuid();
  insert into auth.users (id, email) values (fresh, 'pwg_fresh@test.local');
  -- another bare auth id, used only as the id-rewrite TARGET. Bare on purpose: if it had a
  -- profile row the UPDATE would die on the primary key instead, and W6 arm ② would be green
  -- for a reason that has nothing to do with the policy it claims to pin.
  bare := gen_random_uuid();
  insert into auth.users (id, email) values (bare, 'pwg_bare@test.local');

  -- ---------- [W1] the money column: toss_customer_key is unwritable, even on your own row ----
  -- 0091 §B: this is not an orphan-row nit. `billing_keys` keys on `profile_id`, so rewriting the
  -- customerKey does not orphan OUR storage — it desynchronises us from TOSS, where the billingKey
  -- was issued against the old key and `_shared/charge.ts:232` sends both. Mismatch → decline
  -- ladder → debt, AFTER `settle_run_tx` committed and the runner was paid. A self-service
  -- uncharge, repeatable.
  -- Three arms. ① the attack raises (permission denied — NOT a silent zero rows, which is what a
  -- row-level fix would have produced). ② the value is actually unchanged. ③ the CONTRAST: the
  -- same caller updating `name` on the same row in the same breath succeeds — so arm ① is about
  -- the COLUMN, not about the row having become unreachable.
  begin
    v_e1 := false; v_txt := null;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', w::text, true);
      begin execute 'update profiles set toss_customer_key = $1 where id = $2'
              using '00000000-dead-4000-8000-000000000000'::uuid, w;
      exception when insufficient_privilege then v_e1 := true; end;
      execute 'update profiles set name = ''pwg_w2'' where id = $1' using w;   -- ③ contrast
      reset role;
    exception when others then reset role; raise;
    end;
    select toss_customer_key, name into v_uuid, v_txt from profiles where id = w;
    v_msg := 'raised=' || v_e1 || ' · tck=' || coalesce(v_uuid::text, '<null>')
          || ' · 같은 행 name 쓰기=' || coalesce(v_txt, '<null>');
    if v_e1 and v_uuid = v_tck and v_txt = 'pwg_w2'
      then call _pass('pwg','W1 toss_customer_key — 본인 행이어도 쓰기 거부(에러이지 0행이 아니다). '
                            '같은 호출자가 같은 행의 name은 그대로 쓴다 = 막힌 것은 컬럼이지 행이 아니다 '
                            '(정산 커밋 후 자가 청구불능 = 우리 돈이 걸린 반복 가능한 공격)');
    else call _fail('pwg','W1 toss_customer_key 쓰기 봉인', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pwg','W1', v_msg);
  end;

  -- ---------- [W2] phone is unwritable, and `updated_at` needs no grant to be written ---------
  -- Arm ③ is the one that looks like it does not belong and does: `t_profiles_touch` (0002:9) sets
  -- `updated_at` on every UPDATE, yet `updated_at` is NOT in the grant. That is correct and worth
  -- pinning — privilege is checked against the STATEMENT's SET list, not against what a BEFORE
  -- trigger assigns to NEW. If someone "fixes" the omission by granting `updated_at`, this arm
  -- still passes, but 0091 §H's comment and W9 both say why it is not needed.
  -- `now()` is fixed for the whole transaction, so the past-stamp trick is how the trigger's
  -- effect is made observable at all.
  begin
    v_e1 := false;
    update profiles set updated_at = timestamptz '2020-01-01 00:00+09' where id = w;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', w::text, true);
      -- [0133] 같은 이유로 하이픈 제거. 이 UPDATE 는 insufficient_privilege 로 **거부되는 것**이
      -- 핀이므로 값 자체는 도달하지 않지만, 권한이 아니라 CHECK 때문에 실패하기 시작하면 핀이
      -- 다른 이유로 초록이 된다 — 그건 같은 초록이 아니다.
      begin execute 'update profiles set phone = ''01000000000'' where id = $1' using w;
      exception when insufficient_privilege then v_e1 := true; end;
      execute 'update profiles set district = ''반포동'' where id = $1' using w;   -- fires the trigger
      reset role;
    exception when others then reset role; raise;
    end;
    select phone, updated_at into v_txt, v_ts from profiles where id = w;
    v_msg := 'raised=' || v_e1 || ' · phone=' || coalesce(v_txt, '<null>')
          || ' · updated_at moved=' || (v_ts > timestamptz '2020-06-01 00:00+09');
    if v_e1 and v_txt = v_phone and v_ts > timestamptz '2020-06-01 00:00+09'
      then call _pass('pwg','W2 phone 쓰기 거부(PASS 본인인증 컬럼) · updated_at은 그랜트 없이도 '
                            'BEFORE 트리거가 갱신한다 — 권한 검사는 문장의 SET 목록을 보지 '
                            '트리거가 NEW에 넣는 값을 보지 않는다');
    else call _fail('pwg','W2 phone 봉인 · updated_at 트리거', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pwg','W2', v_msg);
  end;

  -- ---------- [W3] handle: the seal AND the door, or it is half a test ----------
  -- Both arms are one claim. "Clients cannot write `handle`" is only true-and-safe if
  -- `set_my_handle` still works — otherwise the pin is green while handle-setting is dead.
  --   ① direct UPDATE → permission denied.
  --   ② `set_my_handle` (0074:63, `security definer`, prosecdef=true) → still sets it, as the
  --      SAME authenticated caller that was just refused. A definer runs as its owner.
  --   ③ the tightening this buys: `admin` is on `_handle_reserved`'s list, so the RPC refuses it.
  --      Before 0091 a direct UPDATE walked around the reserved list, the charset rule and the
  --      length rule entirely — 0074's column comment asked for a whitelist and never got one.
  --   ④ prosecdef itself, read from the catalog: if someone converts `set_my_handle` to INVOKER,
  --      arm ② dies with it, and this arm names the cause instead of leaving a mystery.
  begin
    v_e1 := false; v_e2 := false; v_txt := null; v_txt2 := null;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', w::text, true);
      begin execute 'update profiles set handle = ''admin'' where id = $1' using w;      -- ①
      exception when insufficient_privilege then v_e1 := true; end;
      execute 'select set_my_handle(''pwg_new_id'')' into v_txt;                          -- ②
      begin execute 'select set_my_handle(''admin'')' into v_txt2;                        -- ③
      exception when others then v_e2 := (sqlerrm = 'handle_reserved'); end;
      reset role;
    exception when others then reset role; raise;
    end;
    select handle into v_txt3 from profiles where id = w;
    v_msg := '직접 UPDATE 거부=' || v_e1 || ' · set_my_handle 반환=' || coalesce(v_txt, '<null>')
          || ' · 저장된 handle=' || coalesce(v_txt3, '<null>')
          || ' · 예약어 거절=' || v_e2
          || ' · definer=' || (select prosecdef from pg_proc
                                where oid = 'set_my_handle(text)'::regprocedure);
    if v_e1 and v_txt = 'pwg_new_id' and v_txt3 = 'pwg_new_id' and v_e2
       and (select prosecdef from pg_proc where oid = 'set_my_handle(text)'::regprocedure)
      then call _pass('pwg','W3 handle — 직접 UPDATE는 거부되고 set_my_handle(definer)은 그대로 동작한다. '
                            '그래서 예약어·글자수·charset 규칙을 우회할 길이 사라졌다 '
                            '(0074 주석이 요구했지만 강제할 수 없던 화이트리스트)');
    else call _fail('pwg','W3 handle 봉인 + RPC 생존', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pwg','W3', v_msg);
  end;

  -- ---------- [W4] the app is UNBROKEN — the arm that catches an over-tight grant -------------
  -- Attack pins cannot see a grant that is too narrow; only this shape can. Each arm is a measured
  -- call site, executed as the real caller:
  --   ① updateMyProfile   (api.ts:1459) — `update({name, district}).eq('id', uid)`
  --   ② avatar upload     (api.ts:2029) — `update({avatar_url}).eq('id', uid)`
  --   ③ the read-back the screen does right after (fetchMyProfile, api.ts:1436) — proving 0088's
  --      SELECT grant and 0091's UPDATE grant agree with each other on the same columns.
  begin
    v_txt := null;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', w::text, true);
      execute 'update profiles set name = $1, district = $2 where id = $3'
        using '김보호자', '반포1동', w;                                                    -- ①
      execute 'update profiles set avatar_url = $1 where id = $2'
        using 'https://cdn.test/pwg.jpg', w;                                              -- ②
      execute 'select name || ''|'' || district || ''|'' || avatar_url || ''|'' || handle
                 from profiles where id = $1' into v_txt using w;                         -- ③
      reset role;
    exception when others then reset role; raise;
    end;
    v_msg := 'read-back=' || coalesce(v_txt, '<null>');
    if v_txt = '김보호자|반포1동|https://cdn.test/pwg.jpg|pwg_new_id'
      then call _pass('pwg','W4 앱은 멀쩡하다 — updateMyProfile(name·district)·아바타 업로드가 '
                            '그대로 통과하고 직후 읽기도 통과 (그랜트가 너무 좁아진 경우는 '
                            '공격 핀으로는 절대 보이지 않는다)');
    else call _fail('pwg','W4 앱 쓰기 형상', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pwg','W4', v_msg);
  end;

  -- ---------- [W5] ⚠ THE UPSERT — the statement nobody had ever executed ----------------------
  -- The role picker (`app/app/index.tsx:27`) is `supabase.from('profiles').upsert({id, role, name})`
  -- and `/` is reachable AFTER signup, so tapping 러너/보호자 again re-runs it on an EXISTING row.
  -- The SQL below is PostgREST v12.2.3's actual output, captured from `log_statement=all` on
  -- 2026-08-13 (0091 §E①) — including `"id" = EXCLUDED."id"`, which is why `update (id)` is in the
  -- grant, and `"role" = EXCLUDED."role"`, which is why `select (role)` had to be added back.
  -- Two arms, and BOTH must pass:
  --   ① CONFLICT path — an existing row, role owner → runner. This is the one 124 could not see.
  --   ② FRESH path — a signed-up user with no profile row yet (first-ever role pick). ⚠ It is NOT
  --      redundant with ①: the privilege check is made once for the STATEMENT, so the ON CONFLICT
  --      arm is checked even when nothing conflicts. Post-0088/pre-0091 BOTH arms were 403, which
  --      is the measured claim that "every user, first screen" rests on.
  begin
    v_txt := null; v_txt2 := null; v_n := 0;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', w::text, true);
      execute 'insert into profiles ("id","name","role") values ($1, $2, $3::user_role)
                 on conflict ("id") do update
                 set "id" = excluded."id", "name" = excluded."name", "role" = excluded."role"'
        using w, '김러너', 'runner';                                                        -- ①
      perform set_config('request.jwt.claim.sub', fresh::text, true);
      execute 'insert into profiles ("id","name","role") values ($1, $2, $3::user_role)
                 on conflict ("id") do update
                 set "id" = excluded."id", "name" = excluded."name", "role" = excluded."role"'
        using fresh, '신규가입', 'owner';                                                   -- ②
      reset role;
    exception when others then reset role; raise;
    end;
    select role::text || '|' || name into v_txt  from profiles where id = w;
    select role::text || '|' || name into v_txt2 from profiles where id = fresh;
    v_msg := '충돌경로=' || coalesce(v_txt, '<null>') || ' · 신규경로=' || coalesce(v_txt2, '<null>');
    if v_txt = 'runner|김러너' and v_txt2 = 'owner|신규가입'
      then call _pass('pwg','W5 역할 선택 upsert — PostgREST가 실제로 보내는 문장 그대로 '
                            '(ON CONFLICT DO UPDATE SET "id"=EXCLUDED."id",…) 충돌 경로·신규 경로 둘 다 통과. '
                            'update(id) 또는 select(role) 중 하나만 빠져도 프로덕션 첫 화면이 403이다');
    else call _fail('pwg','W5 역할 선택 upsert', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pwg','W5', v_msg);
  end;

  -- ---------- [W6] DELETE is nobody's, and the id-rewrite is refused BY THE POLICY -------------
  --   ① DELETE own row → permission denied. Before 0091 the table-wide grant was there and the
  --      absence of a DELETE policy made it a silent ZERO ROWS — so the mutation flips this pin
  --      from "error" to "0 rows", not from error to success. Account deletion arrives through
  --      `id … references auth.users on delete cascade` (0001:27) and needs no privilege here.
  --   ② `update profiles set id = <another auth user>` → refused, and the pin checks the message
  --      says ROW-LEVEL SECURITY. That is 0091 §F's whole argument: `profiles self write` is
  --      USING-only, and Postgres uses the USING expression AS the WITH CHECK when none is given,
  --      so the proposed row is tested too. `update (id)` is therefore safe to grant.
  --      ⚠ If anyone adds an explicit `with check` to that policy WITHOUT `auth.uid() = id`, this
  --      arm is what turns red. The target is a bare auth id with no profile row, so a primary-key
  --      violation cannot stand in for the policy and make this green by accident.
  begin
    v_e1 := false; v_e2 := false; v_n := -1; v_err := '';
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', w::text, true);
      begin execute 'delete from profiles where id = $1' using w;                          -- ①
      exception when insufficient_privilege then v_e1 := true; end;
      begin execute 'update profiles set id = $1 where id = $2' using bare, w;             -- ②
      exception when others then v_e2 := true; v_err := sqlerrm; end;
      reset role;
    exception when others then reset role; raise;
    end;
    select count(*) into v_n from profiles where id = w;
    v_msg := 'delete raised=' || v_e1 || ' · 행 남음=' || v_n
          || ' · id 재작성 거부=' || v_e2 || ' [' || left(v_err, 60) || ']';
    if v_e1 and v_n = 1 and v_e2 and v_err like '%row-level security%'
      then call _pass('pwg','W6 DELETE 권한은 아무에게도 없고(계정 삭제는 auth.users 캐스케이드), '
                            'id 재작성은 정책이 거부한다 — UPDATE 정책에 with check가 없으면 '
                            'USING이 with check 역할을 하므로 update(id)를 줘도 안전하다');
    else call _fail('pwg','W6 DELETE 봉인 · id 재작성 거부', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pwg','W6', v_msg);
  end;

  -- ---------- [W7] anon writes nothing ----------------------------------------------------
  -- ⚠ CLEARING THE CLAIM IS PART OF THE TEST (124's G-arm lesson, which cost six false positives):
  -- `set local role anon` changes the ROLE but leaves `request.jwt.claim.sub` set by the arms
  -- above, so `auth.uid()` keeps returning a real user and every policy gated inside a function
  -- still passes. A test of "what can a stranger write" must first make itself a stranger.
  -- Here the grant denial fires before RLS is even consulted, so this arm would pass either way —
  -- which is exactly why the line goes in with a comment rather than being left out as unneeded:
  -- the day someone re-grants a column to anon, the claim is what decides whether this pin lies.
  begin
    v_e1 := false; v_e2 := false; v_e3 := false; v_e4 := false;
    begin
      perform set_config('request.jwt.claim.sub', '', true);
      execute 'set local role anon';
      begin execute 'insert into profiles (id, role, name) values ($1, ''owner'', ''anon'')'
              using bare;
      exception when insufficient_privilege then v_e1 := true; end;
      begin execute 'update profiles set name = ''anon'' where id = $1' using w;
      exception when insufficient_privilege then v_e2 := true; end;
      begin execute 'delete from profiles where id = $1' using w;
      exception when insufficient_privilege then v_e3 := true; end;
      execute 'reset role';
    exception when others then execute 'reset role'; raise;
    end;
    select count(*) into v_n
      from pg_attribute a
     where a.attrelid = 'profiles'::regclass and a.attnum > 0 and not a.attisdropped
       and (has_column_privilege('anon', a.attrelid, a.attnum, 'insert')
         or has_column_privilege('anon', a.attrelid, a.attnum, 'update'));
    v_e4 := not has_table_privilege('anon', 'profiles', 'delete');
    v_msg := 'insert raised=' || v_e1 || ' · update raised=' || v_e2 || ' · delete raised=' || v_e3
          || ' · anon 쓰기 가능 컬럼=' || v_n || ' · anon delete 없음=' || v_e4;
    if v_e1 and v_e2 and v_e3 and v_n = 0 and v_e4
      then call _pass('pwg','W7 anon — profiles에 쓸 수 있는 컬럼 0개, DELETE도 없다 '
                            '(앱 번들에 들어 있는 공개 키로는 아무 것도 쓰지 못한다)');
    else call _fail('pwg','W7 anon 쓰기 봉인', v_msg); end if;
  exception when others then execute 'reset role'; v_msg := sqlerrm; call _fail('pwg','W7', v_msg);
  end;

  -- ---------- [W8] service_role still writes everything — breaking this breaks money ----------
  -- Edge functions write `profiles` through `admin()` (`_shared/ctx.ts:23`, the SERVICE_ROLE_KEY
  -- client): `create-payment-intent/handler.ts` mints and stores `toss_customer_key`. 0091 §H
  -- re-grants service_role explicitly so a future blanket revoke reddens HERE instead of turning
  -- billing off in production. Arm ④ is DELETE on a throwaway profile, the one privilege no client
  -- has at all — 124's ⓓ mutation showed service_role's `profiles` access reaches past billing
  -- (`70_axes` X2 also went red), so it is pinned in full rather than column by column.
  begin
    v_uuid := null; v_txt := null; v_n := -1;
    killme := t_user('pwg_killme', 'owner');
    begin
      set local role service_role;
      execute 'update profiles set toss_customer_key = $1, phone = $2, handle = $3 where id = $4'
        using '0091beef-0000-4000-8000-000000000091'::uuid, '01099999999', 'pwg_svc', w;
      execute 'select toss_customer_key::text || ''|'' || phone || ''|'' || handle
                 from profiles where id = $1' into v_txt using w;
      execute 'delete from profiles where id = $1' using killme;                            -- ④
      reset role;
    exception when others then reset role; raise;
    end;
    select count(*) into v_n from profiles where id = killme;
    v_msg := 'service_role 쓰기=' || coalesce(v_txt, '<null>') || ' · 삭제 후 남은 행=' || v_n;
    if v_txt = '0091beef-0000-4000-8000-000000000091|01099999999|pwg_svc' and v_n = 0
      then call _pass('pwg','W8 service_role은 전 컬럼 쓰기 + DELETE 유지 — 엣지 함수가 '
                            'toss_customer_key를 심고 PASS 번호를 확정하는 경로 (이게 빨개지면 결제가 멈춘다)');
    else call _fail('pwg','W8 service_role 쓰기 보존', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pwg','W8', v_msg);
  end;

  -- ---------- [W9] THE DURABLE ARM: the write surface is a whitelist, derived not listed -------
  -- 124 G1's fourth arm is the model, and this is its write twin. Derived from the CATALOG, not
  -- from a hand-kept list of forbidden columns, so a future `alter table profiles add column …`
  -- is client-UNWRITABLE by default and reddens here the moment it is not — which is the exact
  -- failure mode that put `toss_customer_key` (0076) inside the client's reach in the first place.
  -- `has_column_privilege` rather than `information_schema.column_privileges`: they were measured
  -- to agree, including on a table-wide `grant update on profiles`, which both expand to all ten
  -- columns — and `has_column_privilege` is the shape 113 K14 and 124 G1 already use.
  -- Three arms: UPDATE set, INSERT set, and DELETE absent. Set EQUALITY both ways, so a grant that
  -- is too narrow fails here too, not only a grant that is too wide.
  begin
    select coalesce(array_agg(a.attname::text order by a.attname), '{}') into v_got
      from pg_attribute a
     where a.attrelid = 'profiles'::regclass and a.attnum > 0 and not a.attisdropped
       and has_column_privilege('authenticated', a.attrelid, a.attnum, 'update');
    select coalesce(array_agg(a.attname::text order by a.attname), '{}') into v_got2
      from pg_attribute a
     where a.attrelid = 'profiles'::regclass and a.attnum > 0 and not a.attisdropped
       and has_column_privilege('authenticated', a.attrelid, a.attnum, 'insert');
    v_e1 := not has_table_privilege('authenticated', 'profiles', 'delete');
    v_msg := 'UPDATE={' || array_to_string(v_got, ',') || '} · INSERT={'
          || array_to_string(v_got2, ',') || '} · DELETE 없음=' || v_e1;
    if v_got @> v_upd and v_upd @> v_got and v_got2 @> v_ins and v_ins @> v_got2 and v_e1
      then call _pass('pwg','W9 쓰기 가능 컬럼 집합 = 화이트리스트 정확히 일치 (UPDATE 5 · INSERT 3 · DELETE 0). '
                            '카탈로그에서 유도하므로 앞으로 추가되는 profiles 컬럼은 기본적으로 '
                            '클라 쓰기 불가이고, 아니게 되는 순간 여기가 빨개진다');
    else call _fail('pwg','W9 쓰기 컬럼 화이트리스트', v_msg); end if;
  exception when others then reset role; v_msg := sqlerrm; call _fail('pwg','W9', v_msg);
  end;
end $$;
