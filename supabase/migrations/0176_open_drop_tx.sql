-- ═══ 0176: open_drop_tx — a drop is paid in the SAME transaction that consumes it ═══════════════
--
-- BACKEND HONESTY AUDIT 2026-09-17 **H2** (and M3; L5 is the premise). The audit read
-- `open-drop/index.ts` at 26c9bcd: it stamps `opened_at` through a consuming CAS and only THEN
-- inserts miles / card / gear / boost, each a separate PostgREST statement, so a writer that fails
-- after the CAS leaves the drop stamped and unpaid, and 0106 §3 (correctly) refuses to un-stamp
-- it: the runner's reward is gone, no sweep looks for it, no ops event fires. While this file was
-- being built, f6ed478 (be/edge) moved that logic to `open-drop/handler.ts` and fixed M3 (the
-- choice check now sits ABOVE the CAS, `:56`) and H1 (a key reaches `applied` only when its write
-- landed, `:80-93`) — but the shape H2 names is still there: the consuming CAS at `:72-75` and the
-- writers at `:99-127` remain separate statements, and `:142` says it in the handler's own words:
-- 「opened_at is frozen (0106 §3) and nothing will retry this」. A drop can still be consumed and
-- not paid; the handler now REPORTS it instead of hiding it, which is the honest half of the fix.
--
-- THE FIX is the `settle_run_tx` shape: ONE plpgsql transaction. Party gate → choice validation →
-- state gate → CAS → every reward write, returning the flat `applied` object the edge builds today
-- (the `{applied}` envelope stays the edge's; `api.ts:3768` unwraps it since c99babb). Any failure
-- RAISES with a named token and everything — the CAS included — rolls back. There is no
-- half-applied state to sweep for, because plpgsql has no autonomous transactions: a raise
-- anywhere is a rollback of everything, and this file's VERIFY refuses a swallowing handler.
--
-- ORDER, and why each refusal sits where it does (0059 doctrine — party gate before state gate,
-- flat whitelisted returns):
--   1 not_signed_in    `auth.uid()` is NULL. Nothing below is reachable without a subject.
--   2 drop_not_found   no row (or a NULL id). A uuid's existence is not STATE; the edge answers
--                      404 for this today and the token keeps that vocabulary.
--   3 not_drop_owner   the row is not the caller's — judged BEFORE `opened_at` is read, under the
--                      row lock, so an outsider on an opened drop learns nothing (207 O1).
--   4 bad_pick_choice  BEFORE the CAS (the M3 fix). A pick needs one of boost|miles|gear AND it
--                      must be among the drop's own minted `contents.options`; a mini takes NONE
--                      (a choice on a mini is a client bug and is refused, not ignored). The
--                      options conjunct is stricter than the edge's static whitelist; the minter
--                      (0083 §6) always mints all three, so no shipped path changes.
--   5 already_opened   the state gate, under `for update`; the CAS predicate below is its belt.
--   6 the CAS          `opened_at = now(), pick_choice = …  where id = ? and opened_at is null` in
--                      ONE statement — exactly what 0106 §3 permits a client-JWT definer to do,
--                      once (D19b's tier: owner + `request.jwt.claim.role = authenticated`).
--   7 the rewards      the edge's arms, in the edge's order, with the edge's constants: a mini
--                      pays `contents.miles` (reason `drop`), upserts `cards_owned`
--                      (`drop-<run_count_at>`, tier 레어), inserts a `claimable` gear claim; a
--                      pick pays a 24h boost / 5,000 miles (reason `pick_drop`) / a `기어 교환권`
--                      claim (`handler.ts:99-127`; the old `index.ts:29-58` the audit cited).
--   8 drop_pays_nothing a row that would pay `{}` is refused and stays unopened (H2 by inaction).
--
-- ═══ WHAT THE COLD REVIEW MEASURED AND THIS FILE KEEPS AS-IS, each with its reason ═══
-- · The `for update` at step 2 is BELT: deleting it reddens nothing, and a live two-connection
--   race against that build still paid exactly once, because the CAS predicate re-evaluates under
--   the UPDATE's own row lock. It stays so a double tap WAITS and then reads `already_opened`
--   rather than racing the predicate; the race is a NAMED GAP in 207 (not pinned).
-- · The explicit `already_opened` gate (step 5) and the CAS belt (step 6) raise the same token,
--   so only one is observable through any fixture; both stay — the gate is the reading, the belt
--   is the write. 207's header records it.
-- · The card arm's `on conflict … do update set tier` is the edge's own upsert semantics
--   (`handler.ts:104`, PostgREST merge-duplicates) ported faithfully: on a second mini at the same
--   `run_count_at` it would DOWNGRADE an existing better tier and receipt a card already owned.
--   Reachable only by a hand-written row (`run_count_at` is the runner's monotonic run count), and
--   whether opening a drop re-grants a card is a product question — parity kept, not decided here.
-- · `not_drop_owner` vs `drop_not_found` lets an authenticated caller learn whether a uuid names a
--   drop. v4 uuids are unguessable, the edge splits 403/404 the same way, and collapsing them would
--   put the state answer ahead of the party answer — not a finding.
-- · A non-uuid `request.jwt.claim.sub` raises 22P02 from the DECLARE cast before any gate, as in
--   every other `:= auth.uid()` file; PostgREST fills that claim from a signature-verified JWT.
-- · The wiring follow-up MUST re-wrap: this returns the BARE `applied`; `handler.ts` returns
--   `{applied}` and `api.ts` unwraps one level — wire it bare and every alert silently reverts to
--   the M4 shape, with no gate able to see it.
--
-- ═══ WHAT THIS FILE DOES NOT DO ═══
-- - It does NOT edit `supabase/functions/open-drop/handler.ts` (be/edge landed it as f6ed478
--   during this slice; it still pays after its own CAS). The edge keeps working exactly as it
--   does; wiring it to `rpc('open_drop_tx')` — with the RUNNER'S JWT, never the service key (see
--   ACL) — is the follow-up. Until then H2 is closed in the schema and still open in the handler,
--   and this file says so rather than implying otherwise.
-- - It does not touch 0106's seal, `settle_run_tx` (the minter), or any table's shape or grants.
--   The tables stay as 0106 left them; this function is the only new door and it is judged by
--   0106's own trigger at the service tier.
--
-- ═══ ACL — `authenticated`, and deliberately NOT `service_role` ═══
-- The runner opens their OWN drop, so the subject is `auth.uid()` and the grant is to
-- `authenticated`. A `p_uid` parameter would be an impersonation oracle (0131 round 3's law).
-- `service_role` is REVOKED explicitly: this stack's default privileges hand every new public
-- function to service_role (`00_shim.sql:131-135` models production's `alter default privileges`),
-- so 「not granted」 is only true if it is revoked. Called with the service key `auth.uid()` is
-- NULL and the function would refuse `not_signed_in` anyway; a standing grant would be dead
-- weight that reads as a capability (0117:441 / 0144:524 are the precedent for this revoke).
-- The revoke from public/anon is in THIS file because this is the function's FIRST definition —
-- the one that sets its ACL (check-definer-acl law; 0116:636 on the PUBLIC-EXECUTE default).
--
-- ⚠ 141 D19 (0106 review F1) sweeps the catalog for a client-callable function that touches
--   drops/gear_claims and, until this file, expected ZERO. This function IS that shape — the door
--   0106 F1 designed the service tier for — so D19 gains a one-entry allowlist naming it, with a
--   two-sided arm (the entry must still exist and be authenticated-executable, so it cannot rot
--   into dead weight). What the function may DO is owned by suite 207, not by the allowlist.
--
-- ═══ MUTATION TABLE — measured, plants `&&`-chained against a COPY, control observed clean ═══
--   See suite 207's header and the REGISTRY row; the numbers live there, not here, so that a
--   later pin added to 207 does not silently stale this block (the write-up-outlives-the-thing law).

create or replace function open_drop_tx(p_drop_id uuid, p_pick_choice text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
declare
  v_uid     uuid := auth.uid();
  v_drop    drops%rowtype;
  v_applied jsonb := '{}'::jsonb;
  v_c       jsonb;
  v_miles   int;
  v_ends    timestamptz;
  v_n       int;
begin
  -- 1 the subject
  if v_uid is null then
    raise exception 'not_signed_in' using detail = '로그인이 필요해요';
  end if;
  if p_drop_id is null then
    raise exception 'drop_not_found' using detail = '드랍을 찾을 수 없어요';
  end if;

  -- 2 · 3 PARTY gate, under the row lock that serializes a double tap: the second caller waits
  --       here and then meets `already_opened` below. `for update` on a missing row locks nothing
  --       (0142:54), so absence is answered first.
  select * into v_drop from drops where id = p_drop_id for update;
  if not found then
    raise exception 'drop_not_found' using detail = '드랍을 찾을 수 없어요';
  end if;
  if v_drop.runner_id is distinct from v_uid then
    raise exception 'not_drop_owner' using detail = '내 드랍만 열 수 있어요';
  end if;

  -- 4 the choice, BEFORE anything is consumed (audit M3)
  if v_drop.kind = 'pick' then
    if p_pick_choice is null
       or p_pick_choice not in ('boost', 'miles', 'gear')
       or jsonb_typeof(v_drop.contents->'options') is distinct from 'array'
       or not (v_drop.contents->'options' ? p_pick_choice) then
      raise exception 'bad_pick_choice' using detail = '보상을 하나 골라 주세요';
    end if;
  elsif p_pick_choice is not null then
    raise exception 'bad_pick_choice' using detail = '보급 상자는 고를 게 없어요';
  end if;

  -- 5 STATE gate
  if v_drop.opened_at is not null then
    raise exception 'already_opened' using detail = '이미 열린 드랍이에요';
  end if;

  -- 6 the CAS: one statement, both columns, the predicate as a belt behind the lock
  update drops
     set opened_at   = now(),
         pick_choice = case when v_drop.kind = 'pick' then p_pick_choice else null end
   where id = p_drop_id and opened_at is null;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'already_opened' using detail = '이미 열린 드랍이에요';
  end if;

  -- 7 the rewards, in this same transaction. A raise in any of them undoes step 6.
  if v_drop.kind = 'mini' then
    v_c     := v_drop.contents;
    v_miles := coalesce(floor((v_c->>'miles')::numeric)::int, 0);
    if v_miles > 0 then
      insert into miles_ledger(profile_id, delta, reason, ref_id)
        values (v_uid, v_miles, 'drop', p_drop_id);
      v_applied := v_applied || jsonb_build_object('miles', v_miles);
    end if;
    if v_c ? 'card' then
      insert into cards_owned(profile_id, card_key, tier)
        values (v_uid, 'drop-' || v_drop.run_count_at, '레어')
        on conflict (profile_id, card_key) do update set tier = excluded.tier;
      v_applied := v_applied || jsonb_build_object('card', v_c->>'card');
    end if;
    if v_c ? 'gear' then
      insert into gear_claims(profile_id, side, item, milestone, status)
        values (v_uid, 'runner', v_c->>'gear', v_drop.run_count_at, 'claimable');
      v_applied := v_applied || jsonb_build_object('gear', v_c->>'gear');
    end if;
  else
    if p_pick_choice = 'boost' then
      v_ends := now() + interval '24 hours';
      insert into boosts(runner_id, ends_at) values (v_uid, v_ends);
      -- the edge returns `new Date().toISOString()`; render the same shape so no reader changes
      v_applied := jsonb_build_object('boost_until',
                     to_char(v_ends at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
    elsif p_pick_choice = 'miles' then
      insert into miles_ledger(profile_id, delta, reason, ref_id)
        values (v_uid, 5000, 'pick_drop', p_drop_id);
      v_applied := jsonb_build_object('miles', 5000);
    else
      insert into gear_claims(profile_id, side, item, milestone, status)
        values (v_uid, 'runner', '기어 교환권', v_drop.run_count_at, 'claimable');
      v_applied := jsonb_build_object('gear', '기어 교환권');
    end if;
  end if;

  -- 8 nothing to pay is a REFUSAL, not a receipt (cold review #3 — H2 arriving by INACTION).
  --   0106's CHECK admits a mini `{"miles":0}` and no minter produces one (0020/0025/0028/0083/0169
  --   all mint 500..1199), so this arm exists for a hand-written row: without it that row is
  --   consumed for `{}` and the client renders a success alert for nothing. Raising leaves the row
  --   unopened and visible for an ops repair.
  if v_applied = '{}'::jsonb then
    raise exception 'drop_pays_nothing' using detail = '이 드랍에는 보상이 없어요';
  end if;

  return v_applied;
end $$;

revoke execute on function open_drop_tx(uuid, text) from public, anon, service_role;
grant  execute on function open_drop_tx(uuid, text) to authenticated;

comment on function open_drop_tx is
  '0176 (audit H2/M3): the runner opens their own drop in ONE transaction — party gate, choice check, state gate, CAS, every reward — any raise rolls the CAS back. Returns the flat applied object the edge used to build. Tokens: not_signed_in · drop_not_found · not_drop_owner · bad_pick_choice · already_opened. authenticated only; service_role has no subject here.';

-- ═══ VERIFY — apply-time, and NOT a substitute for suite 207 ═══
-- VERIFY says 「the apply produced this shape」; 207 says 「the shape behaves」. Different artifacts.
-- Every arm is `is distinct from`, never a bare IF: a NULL answer must fail, not fall silent.
do $$
declare
  v_oid oid;
  v_src text;
  v_acl text;
  v_bad text := '';
begin
  select p.oid into v_oid
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'open_drop_tx'
     and pg_get_function_identity_arguments(p.oid) = 'p_drop_id uuid, p_pick_choice text';
  if v_oid is null then
    raise exception '0176 VERIFY FAILED: NO-FUNCTION(open_drop_tx(uuid, text))';
  end if;

  if (select prosecdef from pg_proc where oid = v_oid) is distinct from true
    then v_bad := v_bad || ' NOT-DEFINER'; end if;
  if (select coalesce(array_to_string(proconfig, ','), '') ~ 'search_path=public, pg_temp'
        from pg_proc where oid = v_oid) is distinct from true
    then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH'; end if;

  -- ACL by value. A NULL proacl is the PUBLIC-EXECUTE default (0116:636), so it is an arm of its own.
  if (select proacl is null from pg_proc where oid = v_oid) is distinct from false
    then v_bad := v_bad || ' PUBLIC-EXECUTE(acl-is-default)'; end if;
  select array_to_string(proacl, ',') into v_acl from pg_proc where oid = v_oid;
  if (coalesce(v_acl, '') ~ '(^|,)=[^/]*X') is distinct from false
    then v_bad := v_bad || ' PUBLIC-EXECUTE(acl-entry)'; end if;
  if has_function_privilege('anon', v_oid, 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' anon-EXECUTE'; end if;
  if has_function_privilege('authenticated', v_oid, 'EXECUTE') is distinct from true
    then v_bad := v_bad || ' authenticated-CANNOT-EXECUTE'; end if;
  if has_function_privilege('service_role', v_oid, 'EXECUTE') is distinct from false
    then v_bad := v_bad || ' service_role-EXECUTE(no-subject-there)'; end if;

  -- Source ORDER, comments STRIPPED first (the comment-matching law: prose must not satisfy this).
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where oid = v_oid;
  if v_src is null then
    v_bad := v_bad || ' NO-SOURCE';
  else
    if (position('not_drop_owner' in v_src) > 0
        and position('bad_pick_choice' in v_src) > 0
        and position('drop_pays_nothing' in v_src) > 0
        and position('update drops' in v_src) > 0) is distinct from true
      then v_bad := v_bad || ' TOKENS-MISSING'; end if;
    if (position('not_drop_owner' in v_src) < position('update drops' in v_src)) is distinct from true
      then v_bad := v_bad || ' PARTY-GATE-AFTER-CAS'; end if;
    if (position('bad_pick_choice' in v_src) < position('update drops' in v_src)) is distinct from true
      then v_bad := v_bad || ' CHOICE-CHECK-AFTER-CAS'; end if;
    if (v_src ~* 'exception\s+when\s+others') is distinct from false
      then v_bad := v_bad || ' SWALLOWING-HANDLER(atomicity-broken)'; end if;
  end if;

  if v_bad <> '' then
    raise exception '0176 VERIFY FAILED:%', v_bad;
  end if;
end $$;
