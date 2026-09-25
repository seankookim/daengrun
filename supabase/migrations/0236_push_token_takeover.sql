-- ═══ 0236: a device token belongs to ONE account — the next registration on a device takes it over
--
-- Deploy: `supabase db push` plus a client build. No edge function, no cron, no backfill. The
-- client build ships BEFORE this file can be on production, so it carries a `PENDING_DEPLOY`
-- entry (`app/src/lib/rpc-skew.ts`) and falls back to the pre-0236 direct upsert until the push —
-- see §0c for what that window costs.
--
-- ═══ §0 THE DEFECT (R1 executing review 2026-09-26, finding c2, medium, MEASURED there) ════════
--
-- `push_tokens` (0024:10-17) is keyed by `profile_id`, has NO uniqueness on `token`, and its only
-- policy is 「push self all」 (own row, read and write). Sign-out deletes this device's row for the
-- outgoing account (`releasePushToken`, fix/notification-truth), but that delete is BEST-EFFORT:
-- offline, a 4 s timeout, a failed request, or a build older than that fix all skip it. The
-- reviewer ran the real `push.ts` against a stubbed backend with the release's delete failing and
-- measured the end state `{A: TOKEN-DEV, B: TOKEN-DEV}` — two accounts on one device, so every
-- push addressed to A (chat, requests, money) keeps arriving on the phone B is now using. B's
-- client cannot repair it: RLS admits a delete only of B's OWN row.
--
-- ═══ §0a THE FIX ═════════════════════════════════════════════════════════════════════════════
--
-- `register_push_token(p_token)`, a SECURITY DEFINER writer, in ONE transaction: upserts the
-- CALLER's row (auth.uid(); one row per profile, as before) AND deletes every OTHER profile's row
-- holding the same token. The next registration on a device is the correction, whatever happened
-- at the previous sign-out.
--
-- ⚠ Order inside the body is deliberate: the caller's own row is written FIRST, so every refusal
--   the write can raise — the 0189 §C trigger's `account_deleted` for a tombstoned caller — fires
--   before any other profile's row is touched. The whole call is one transaction either way, so a
--   raise after the delete would also undo it; the order makes that true by reading rather than by
--   reasoning about rollback.
-- ⚠ Same-token registrations are serialised by a transaction-scoped advisory lock keyed on the
--   token. Without it two concurrent registrations of one token by two profiles could each delete
--   「everyone else」 before the other's INSERT committed, and both rows would survive. (READ, not
--   measured — see §0d ①.)
--
-- ═══ §0b WHO READS AND WRITES `push_tokens` — nothing depends on a token being shared ═══════════
--   Read at write time, every reference in `supabase/migrations/**`, `supabase/functions/**`,
--   `app/src/**`, `app/app/**`:
--   · `notify_push()` (latest body 0210:212-216) — `where pt.profile_id = new.profile_id`. Keyed by
--     the RECIPIENT's profile; never asks which other profiles share the token.
--   · `delete_my_account_tx` (0115:520) — `delete … where profile_id = p_uid`.
--   · `_push_token_live_owner()` (0189 §C, BEFORE INSERT OR UPDATE) — reads NEW only; it fires on
--     this function's upsert, which is how a tombstone stays refused (§0a).
--   · client `push.ts` — registration upserts its own row (`onConflict: 'profile_id'`); sign-out
--     deletes its own row scoped by (profile_id, token).
--   · `supabase/functions/**` — no function reads the table (only `_test/delete_account_test.ts`,
--     which mocks a deletion count).
--   No reader or writer treats two profiles holding one token as meaningful, and the product has no
--   state in which it is: an Expo token names ONE app install, and one install has one signed-in
--   account at a time. Every such pair is a stale row.
--
-- ═══ §0c THE SKEW WINDOW (between the client build and this push) ══════════════════════════════
--   The new client calls `register_push_token`; PostgREST refuses it with PGRST202 until this file
--   is on production, and the client then performs the pre-0236 direct upsert — exactly today's
--   behaviour, including today's residual (a failed sign-out release leaves the old account's row).
--   That residual closes at the push; the PENDING_DEPLOY line comes out the same day
--   (`select count(*) from pg_proc where proname = 'register_push_token'` → 1).
--   Builds older than this one keep upserting directly after the push, and for them the residual
--   stays until they update — this function repairs only what a NEW build registers.
--
-- ═══ §0e THE THREAT, AND THE DECISION ════════════════════════════════════════════════════════════
--   The new capability is EVICTION: a caller who passes a token another profile holds removes that
--   profile's row. The server cannot tell 「this token is on my device」 from 「I learned this token」.
--   What an attacker needs is the victim's Expo push token, and:
--   · nothing in this product discloses one — `push_tokens` is self-only under RLS, `notify_push`
--     is a definer that returns nothing, and this function returns `void` whether or not a row was
--     evicted (no oracle: the same response, the same row count visible to the caller — none);
--   · an Expo token is a device SECRET already: whoever holds it can send pushes to that device
--     through Expo's public push API directly, with no account of ours at all. Eviction adds
--     nothing to the power of a token holder that the token did not already confer except the
--     ability to SILENCE the victim's pushes — until the victim's app next registers (every home
--     mount of a fresh process), which takes the token straight back;
--   · the pre-0236 table already let any signed-in caller write ANY token into their own row, i.e.
--     already let a token holder route their own account's pushes onto the victim's device.
--   Eviction is by EXACT token equality only — no pattern, no case folding, no prefix — so a caller
--   who does not hold a token cannot evict its row by guessing a shape (suite 267 `0236-E1`).
--   DECISION: accepted. Token possession is treated as device possession, which is the model the
--   push provider itself uses. If Expo push access tokens ("enhanced security") are ever enabled,
--   that changes the provider half of this argument, not ours.
--
-- ═══ §0d NAMED LIMITATIONS (prose — the harness cannot produce these states) ══════════════════
--   ① Concurrency. The advisory lock is what makes two same-token registrations order-independent;
--      the harness here is one session, so no pin observes the interleaving it closes. Suite 267's
--      S1 pins the lock's PRESENCE and position in the source (the only door this harness has).
--   ② The client half — the generation counter that keeps an in-flight registration from reviving
--      a signed-out account's row (R1 c3) — lives in `app/src/lib/push.ts` and is pinned by
--      `app/test/push-token-signout.test.cjs`. No SQL pin can see it.
--   ③ No UNIQUE index on `token`: production may already hold duplicates (that is the defect), and
--      a unique index would make every OLD build's direct upsert fail with 23505 on a device
--      another account still holds — i.e. convert 「the old account also gets pushes」 into 「the
--      current account gets none」. The takeover lives in the writer instead.

-- ═══ §A register_push_token — the caller's row, and nobody else's copy of the token ═══════════
create or replace function register_push_token(p_token text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- A blank or NULL token names no device; it would otherwise evict every other blank row.
  if p_token is null or btrim(p_token) = '' then raise exception 'invalid_token'; end if;

  -- Named, rather than the FK violation's constraint text: an auth user with no profiles row.
  if not exists (select 1 from profiles p where p.id = v_uid) then
    raise exception 'no_profile';
  end if;

  -- §0d ①: serialise same-token registrations.
  perform pg_advisory_xact_lock(hashtextextended(p_token, 0));

  -- The caller's own row FIRST — the 0189 §C trigger refuses a tombstone here, before any other
  -- profile's row is touched.
  insert into push_tokens as pt (profile_id, token, updated_at)
       values (v_uid, p_token, now())
  on conflict (profile_id) do update
          set token = excluded.token, updated_at = excluded.updated_at;

  -- The takeover: EXACT token equality, other profiles only.
  delete from push_tokens pt
   where pt.token = p_token
     and pt.profile_id <> v_uid;
end $$;

comment on function register_push_token(text) is
  '0236 §A: register this device''s Expo token for the caller (auth.uid()) and remove every OTHER profile''s row holding the same token, in one transaction — so the next registration on a device corrects a sign-out whose release failed (R1 c2). Refusals: not_authenticated · invalid_token · no_profile · account_deleted (0189 §C trigger). Returns void either way: never says whether a row was evicted. Eviction is exact-token only; the threat and the decision are in 0236 §0e.';

revoke all     on function register_push_token(text) from public, anon;
grant  execute on function register_push_token(text) to authenticated;

-- ═══ §B VERIFY — fail the apply, not a later harness run ══════════════════════════════════════
-- Suite 267 `0236-S1` carries the same properties as a STANDING pin: a property checked only at
-- apply is protected exactly until someone recreates the function.
do $verify$
declare v_bad text := ''; v_src text;
begin
  -- ① shape: definer, in-body search_path, the argument list the client sends, returns void
  if (select count(*) from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname = 'register_push_token'
         and p.prosecdef
         and 'search_path=public, pg_temp' = any (p.proconfig)
         and p.prorettype = 'void'::regtype) is distinct from 1
  then v_bad := v_bad || ' DEFINER-SHAPE'; end if;

  if (select pg_get_function_identity_arguments(p.oid) from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.proname = 'register_push_token')
     is distinct from 'p_token text'
  then v_bad := v_bad || ' ARGUMENTS'; end if;

  -- ② ACL both ways
  if (has_function_privilege('public', 'register_push_token(text)', 'execute')
   or has_function_privilege('anon',   'register_push_token(text)', 'execute'))
     is not false
  then v_bad := v_bad || ' PUBLIC-OR-ANON-EXECUTE'; end if;
  if has_function_privilege('authenticated', 'register_push_token(text)', 'execute') is not true
  then v_bad := v_bad || ' AUTHENTICATED-CANNOT-CALL'; end if;

  -- ③ the body, COMMENTS STRIPPED
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where pronamespace = 'public'::regnamespace and proname = 'register_push_token';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(register_push_token)';
  else
    if (v_src ~ 'v_uid\s+is\s+null\s+then\s+raise') is not true
    then v_bad := v_bad || ' AUTH-GATE-GONE'; end if;
    if (v_src ~ 'pt\.token\s*=\s*p_token\s+and\s+pt\.profile_id\s*<>\s*v_uid') is not true
    then v_bad := v_bad || ' TAKEOVER-GONE-OR-NOT-EXACT'; end if;
    if (position('pg_advisory_xact_lock(' in v_src) > 0
        and position('pg_advisory_xact_lock(' in v_src) < position('insert into push_tokens' in v_src)
        and position('insert into push_tokens' in v_src) < position('delete from push_tokens' in v_src))
       is not true
    then v_bad := v_bad || ' ORDER(lock<own-write<takeover)'; end if;
  end if;

  -- ④ the precondition the tombstone refusal rides on: 0189 §C's trigger, STATE not shape
  if (select count(*) from pg_trigger
       where tgrelid = 'push_tokens'::regclass and tgname = 'push_tokens_live_owner'
         and not tgisinternal and tgenabled = 'O') is distinct from 1
  then v_bad := v_bad || ' NO-LIVE-OWNER-TRIGGER'; end if;

  if v_bad <> '' then
    raise exception '❌ 0236 VERIFY:%', v_bad;
  end if;
end $verify$;
