-- ═══ 267 — 0236: a device token belongs to ONE account — the next registration takes it over
-- ═══        0236-T1 · E1 · G1 · S1, tag `ptk`
--
-- THE PROPOSITIONS THIS FILE OWNS, each stated without reference to any mutation.
--
--   · T1 **ONE TOKEN, ONE PROFILE — THE LATEST REGISTRANT HOLDS IT.** A registers T; B registers T
--        (the device changed hands and A's sign-out release never landed): only B holds T. A
--        registers T again: only A holds it. A third profile C holding a DIFFERENT token is
--        untouched throughout, and B's own row is removed only by the takeover, never replaced by
--        a second row. 🔴 Each takeover arm first observes that the row to be evicted IS present,
--        so its absence afterwards is a delta the call caused (an absence pin over an empty world
--        licenses nothing). The evicting call and a non-evicting call return the identical value
--        (void), so the response cannot say whether a row was evicted.
--   · E1 **EVICTION IS EXACT-TOKEN ONLY.** A caller who does not hold D's token cannot evict D's
--        row with a near-miss: a case-folded copy, a prefix, a LIKE pattern. D's row survives all
--        three. The arm that makes that mean something: the SAME caller passing D's exact token
--        DOES evict it — so the fixture can tell an exact rule from a loose one.
--   · G1 **THE REFUSALS ARE NAMED AND NONE OF THEM TOUCHES ANOTHER PROFILE'S ROW.** Anonymous →
--        `not_authenticated`; an auth user with no profile → `no_profile`; NULL and blank token →
--        `invalid_token`; a TOMBSTONED caller (made by the real `delete_my_account_tx`) →
--        `account_deleted` (0189 §C's trigger). In every case a live victim holding the very token
--        passed keeps its row — measured before and after each call.
--   · S1 **DEPLOYED SHAPE.** `prosecdef`, in-body `search_path`, `(p_token text)` returning void;
--        ACL both ways; the body with COMMENTS STRIPPED — the auth gate, the exact-equality
--        takeover scoped to OTHER profiles, and the order lock < own write < takeover — with a
--        NO-SOURCE arm and a two-sided control that the stripper ran; and the 0189 §C trigger the
--        tombstone refusal rides on, by `tgenabled` (state), not by its definition (shape).
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose — the harness cannot reach it) ───
--   · Concurrency. The advisory lock (0236 §0d ①) is what serialises two same-token
--     registrations; this harness is one session, so S1 pins only its presence and position.
--   · That a caller holds the token ON THEIR DEVICE. No server can check that; 0236 §0e states the
--     threat and the decision. E1 pins the only thing the server can enforce: exact equality.
--   · The client (`push.ts`): the RPC-or-fallback call and the registration generation counter are
--     pinned by `app/test/push-token-signout.test.cjs`, which no SQL pin can see.
--
-- ─── FIXTURE NOTES ───
--  ① `request.jwt.claim.sub` is set and cleared inside the caller helper and cleared at the end.
--  ② Victim rows are planted directly as `postgres` where a pin needs a starting state the product
--     reaches by a path this suite is not about (a stale row left by a failed release).
set client_min_messages = warning;

-- The product's writer, as a named caller. `p_uid` NULL = anonymous. Returns the call's own
-- result rendered as text (void renders as ''), or `raised:<message>`.
create or replace function t_ptk_register(p_uid uuid, p_token text) returns text
language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  select coalesce(register_push_token(p_token)::text, '∅') into v;
  perform set_config('request.jwt.claim.sub', '', true);
  return 'ok:' || v;
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  return 'raised:' || sqlerrm;
end $$;

create or replace function t_ptk_token(p_uid uuid) returns text
language sql as $$ select pt.token from push_tokens pt where pt.profile_id = p_uid $$;

create or replace function t_ptk_holders(p_token text) returns text
language sql as $$
  select coalesce(string_agg(pr.name, ',' order by pr.name), '')
    from push_tokens pt join profiles pr on pr.id = pt.profile_id
   where pt.token = p_token
$$;

do $$
declare
  a uuid; b uuid; c uuid; d uuid; e uuid; x uuid; tomb uuid; ghost uuid;
  v text; v2 text; v_bad text; v_msg text; v_n int; v_src text; v_raw text; v_res jsonb;
  k text;
  T  constant text := 'ExponentPushToken[ptk-device-1]';
  T2 constant text := 'ExponentPushToken[ptk-device-2]';
  TD constant text := 'ExponentPushToken[ptkAbC]';
begin
  perform set_config('request.jwt.claim.sub', '', true);                                       -- ①

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0236-T1] one token, one profile — the latest registrant holds it
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    a := t_user('ptk_t1_a', 'owner');
    b := t_user('ptk_t1_b', 'runner');
    c := t_user('ptk_t1_c', 'owner');
    insert into push_tokens (profile_id, token) values (c, T2);                                 -- ②

    v := t_ptk_register(a, T);
    if v not like 'ok:%' then v_bad := v_bad || ' A''s first registration was refused: ' || v; end if;
    if t_ptk_holders(T) is distinct from 'ptk_t1_a'
    then v_bad := v_bad || ' after A registers, holders(T) = [' || t_ptk_holders(T) || '], must be [ptk_t1_a]'; end if;

    -- the defect's precondition, observed: A's row is present before B registers.
    select count(*) into v_n from push_tokens where profile_id = a and token = T;
    if v_n is distinct from 1 then v_bad := v_bad || ' fixture: A does not hold T before the takeover'; end if;

    v2 := t_ptk_register(b, T);
    if v2 not like 'ok:%' then v_bad := v_bad || ' B''s registration was refused: ' || v2; end if;
    -- 🔴 the property
    if t_ptk_holders(T) is distinct from 'ptk_t1_b'
    then v_bad := v_bad || ' 🔴 after B registers T, holders(T) = [' || t_ptk_holders(T) || '], must be [ptk_t1_b] only'; end if;
    if t_ptk_token(a) is not null
    then v_bad := v_bad || ' 🔴 A still has a row (token ' || t_ptk_token(a) || ')'; end if;
    -- no oracle: the evicting call (v2) and the non-evicting first call (v) answer identically.
    if v is distinct from v2
    then v_bad := v_bad || ' the evicting call answered [' || v2 || '] and the non-evicting call [' || v || '] — the response is an oracle'; end if;

    -- and back: A re-registers T.
    v := t_ptk_register(a, T);
    if v not like 'ok:%' then v_bad := v_bad || ' A''s re-registration was refused: ' || v; end if;
    if t_ptk_holders(T) is distinct from 'ptk_t1_a'
    then v_bad := v_bad || ' 🔴 after A re-registers T, holders(T) = [' || t_ptk_holders(T) || '], must be [ptk_t1_a] only'; end if;

    -- a different token is untouched throughout; one row per profile.
    if t_ptk_token(c) is distinct from T2
    then v_bad := v_bad || ' C''s different token was touched (now ' || coalesce(t_ptk_token(c), '∅') || ')'; end if;
    select count(*) into v_n from push_tokens where profile_id in (a, b, c);
    if v_n is distinct from 2 then v_bad := v_bad || ' row count over A,B,C is ' || v_n || ', must be 2 (A:T, C:T2)'; end if;

    -- a profile moving to a NEW token keeps one row (the upsert, not a second insert).
    v := t_ptk_register(a, 'ExponentPushToken[ptk-device-1b]');
    select count(*) into v_n from push_tokens where profile_id = a;
    if v not like 'ok:%' or v_n is distinct from 1 or t_ptk_token(a) is distinct from 'ExponentPushToken[ptk-device-1b]'
    then v_bad := v_bad || ' A moving to a new token did not leave exactly one row carrying it (' || v || ', n=' || v_n || ')'; end if;

    if v_bad = '' then call _pass('ptk','0236-T1 one token, one profile — A registers T; B registers T and A''s row (observed present first) is GONE, holders(T)=[B]; A re-registers and holders(T)=[A]; C''s different token untouched; the evicting and non-evicting calls answer identically; a new token upserts one row');
    else v_msg := v_bad; call _fail('ptk','0236-T1 latest registrant holds the token', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('ptk','0236-T1 latest registrant holds the token', sqlerrm); end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0236-E1] eviction is exact-token only
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    d := t_user('ptk_e1_d', 'owner');
    e := t_user('ptk_e1_e', 'owner');
    insert into push_tokens (profile_id, token) values (d, TD);                                 -- ②

    foreach k in array array[lower(TD), upper(TD), 'ExponentPushToken[ptk', 'ExponentPushToken[ptk%', 'ExponentPushToken[ptkAbC_', TD || ' '] loop
      v := t_ptk_register(e, k);
      if v not like 'ok:%' then v_bad := v_bad || ' E''s near-miss [' || k || '] was refused (' || v || ') — the arm measures nothing'; end if;
      if t_ptk_token(d) is distinct from TD
      then v_bad := v_bad || ' 🔴 E registering the near-miss [' || k || '] evicted D''s row'; end if;
    end loop;

    -- the positive control: the exact token DOES evict — the fixture can tell exact from loose.
    v := t_ptk_register(e, TD);
    if v not like 'ok:%' then v_bad := v_bad || ' control: E''s exact registration was refused: ' || v; end if;
    if t_ptk_token(d) is not null
    then v_bad := v_bad || ' control: the exact token did not evict D — the near-miss arms above are vacuous'; end if;

    if v_bad = '' then call _pass('ptk','0236-E1 eviction is exact-token only — six near-misses of D''s token (lower, upper, prefix, LIKE %, LIKE _, trailing space) leave D''s row; the exact token evicts it (the control that the fixture can tell exact from loose)');
    else v_msg := v_bad; call _fail('ptk','0236-E1 exact-token eviction', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('ptk','0236-E1 exact-token eviction', sqlerrm); end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0236-G1] named refusals, and none of them touches another profile's row
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    x := t_user('ptk_g1_x', 'owner');
    insert into push_tokens (profile_id, token) values (x, T);                                  -- ② the victim
    select count(*) into v_n from push_tokens; -- world size, re-read after each refusal

    -- anonymous
    v := t_ptk_register(null, T);
    if v is distinct from 'raised:not_authenticated'
    then v_bad := v_bad || ' 🔴 anonymous answered [' || v || '], must be raised:not_authenticated'; end if;
    if t_ptk_token(x) is distinct from T then v_bad := v_bad || ' 🔴 anonymous evicted the victim'; end if;

    -- an auth user with no profiles row
    ghost := gen_random_uuid();
    insert into auth.users (id, email) values (ghost, 'ptk_g1_ghost@test.local');
    v := t_ptk_register(ghost, T);
    if v is distinct from 'raised:no_profile'
    then v_bad := v_bad || ' a profile-less user answered [' || v || '], must be raised:no_profile'; end if;
    if t_ptk_token(x) is distinct from T then v_bad := v_bad || ' 🔴 a profile-less user evicted the victim'; end if;

    -- NULL and blank tokens, with a blank-token victim planted so blank-eviction is observable
    e := t_user('ptk_g1_blank', 'owner');
    insert into push_tokens (profile_id, token) values (e, '');                                 -- ②
    c := t_user('ptk_g1_caller', 'owner');
    foreach k in array array['', '   '] loop
      v := t_ptk_register(c, k);
      if v is distinct from 'raised:invalid_token'
      then v_bad := v_bad || ' blank token [' || k || '] answered [' || v || '], must be raised:invalid_token'; end if;
    end loop;
    v := t_ptk_register(c, null);
    if v is distinct from 'raised:invalid_token'
    then v_bad := v_bad || ' NULL token answered [' || v || '], must be raised:invalid_token'; end if;
    if t_ptk_token(e) is distinct from '' then v_bad := v_bad || ' 🔴 a blank registration evicted the blank-token row'; end if;
    if t_ptk_token(c) is not null then v_bad := v_bad || ' a refused token wrote the caller''s row'; end if;

    -- a tombstone, made by the REAL delete_my_account_tx (the fixture starts where production does)
    tomb := t_user('ptk_g1_tomb', 'owner');
    v_res := delete_my_account_tx(tomb);
    if (v_res->>'tombstoned')::boolean is distinct from true
    then v_bad := v_bad || ' fixture: delete_my_account_tx did not tombstone (' || v_res::text || ')'; end if;
    v := t_ptk_register(tomb, T);
    if v is distinct from 'raised:account_deleted'
    then v_bad := v_bad || ' 🔴 a tombstone answered [' || v || '], must be raised:account_deleted'; end if;
    if t_ptk_token(x) is distinct from T then v_bad := v_bad || ' 🔴 a tombstone evicted the victim'; end if;
    if t_ptk_token(tomb) is not null then v_bad := v_bad || ' 🔴 a tombstone wrote a token row'; end if;

    -- the control that the refusals are about identity: a live caller with the same token succeeds
    b := t_user('ptk_g1_live', 'owner');
    v := t_ptk_register(b, T);
    if v not like 'ok:%' or t_ptk_holders(T) is distinct from 'ptk_g1_live'
    then v_bad := v_bad || ' control: a live caller''s registration of T did not take it over (' || v || ', holders=' || t_ptk_holders(T) || ')'; end if;

    if v_bad = '' then call _pass('ptk','0236-G1 named refusals leave every other row alone — anonymous → not_authenticated, profile-less → no_profile, NULL/blank → invalid_token (a blank-token row survives), a real tombstone → account_deleted; the victim holding T keeps it through all of them; a live caller then takes T over (the control)');
    else v_msg := v_bad; call _fail('ptk','0236-G1 named refusals', v_msg); end if;
  exception when others then perform set_config('request.jwt.claim.sub', '', true);
    call _fail('ptk','0236-G1 named refusals', sqlerrm); end;

  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  -- [0236-S1] deployed shape
  -- ═══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if (select count(*) from pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname = 'register_push_token'
           and p.prosecdef
           and 'search_path=public, pg_temp' = any (p.proconfig)
           and p.prorettype = 'void'::regtype) is distinct from 1
    then v_bad := v_bad || ' not exactly one definer register_push_token with in-body search_path returning void'; end if;
    if (select pg_get_function_identity_arguments(p.oid) from pg_proc p
         where p.pronamespace = 'public'::regnamespace and p.proname = 'register_push_token')
       is distinct from 'p_token text'
    then v_bad := v_bad || ' the argument list is not (p_token text) — the client sends p_token'; end if;

    if has_function_privilege('public', 'register_push_token(text)', 'execute') is not false
    then v_bad := v_bad || ' PUBLIC can execute'; end if;
    if has_function_privilege('anon', 'register_push_token(text)', 'execute') is not false
    then v_bad := v_bad || ' anon can execute'; end if;
    if has_function_privilege('authenticated', 'register_push_token(text)', 'execute') is not true
    then v_bad := v_bad || ' authenticated cannot execute'; end if;

    select p.prosrc, regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
      into v_raw, v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'register_push_token';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(register_push_token)';
    else
      -- 🔴 TWO-SIDED CONTROL THAT THE STRIPPER RAN. `serialise same-token` appears ONLY in this
      --    body's prose; if it survives stripping, every arm below is reading documentation.
      if (position('serialise same-token' in v_raw) > 0) is not true
      then v_bad := v_bad || ' the comment-control string is absent from the raw body — the stripper control is vacuous'; end if;
      if (position('serialise same-token' in v_src) > 0) is not false
      then v_bad := v_bad || ' comments were not stripped — the arms below would be measuring prose'; end if;
      if (v_src ~ 'v_uid\s+is\s+null\s+then\s+raise') is not true
      then v_bad := v_bad || ' the auth gate is gone'; end if;
      if (v_src ~ 'pt\.token\s*=\s*p_token\s+and\s+pt\.profile_id\s*<>\s*v_uid') is not true
      then v_bad := v_bad || ' the takeover is gone, not exact, or not scoped to OTHER profiles'; end if;
      if (position('pg_advisory_xact_lock(' in v_src) > 0
          and position('pg_advisory_xact_lock(' in v_src) < position('insert into push_tokens' in v_src)
          and position('insert into push_tokens' in v_src) < position('delete from push_tokens' in v_src))
         is not true
      then v_bad := v_bad || ' the order lock < own write < takeover does not hold'; end if;
    end if;

    if (select count(*) from pg_trigger
         where tgrelid = 'push_tokens'::regclass and tgname = 'push_tokens_live_owner'
           and not tgisinternal and tgenabled = 'O') is distinct from 1
    then v_bad := v_bad || ' 0189 §C push_tokens_live_owner is not present-and-enabled — the tombstone refusal has no floor'; end if;

    if v_bad = '' then call _pass('ptk','0236-S1 deployed shape — register_push_token is prosecdef + in-body search_path, (p_token text) → void; PUBLIC/anon cannot execute, authenticated can; stripped body carries the auth gate, the exact other-profile takeover, and lock < own write < takeover (stripper control two-sided); 0189 §C trigger enabled');
    else v_msg := v_bad; call _fail('ptk','0236-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('ptk','0236-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
