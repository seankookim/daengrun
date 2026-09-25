-- ═══ 0225: a chat message's created_at is written by the SERVER whenever a client sends it
--
-- Deploy: `supabase db push` only. No client build (the client never sent `created_at` — §0c), no
-- edge function, no cron, no backfill. Existing rows are NOT touched (§0e).
--
-- ═══ §0 THE DEFECT (found by the chat-read-cursor builder, 2026-09-25; 0223 §0d ③) ═════════════
--
-- `chat_messages.created_at` (0001:373) is `not null default now()` and nothing else. The client's
-- send path is a direct INSERT under RLS (0114 §2 「messages party send」), the table-level INSERT
-- grant covers every column, there is no column revoke and no stamping trigger — so a party could
-- send `created_at` themselves and the row landed with the value they chose. Measured on trunk
-- `f131f28`'s schema by suite 256 (0225-R1/R2): an `authenticated` owner inserting `now() - 1 day`
-- and a runner inserting `now() + 1 day` both landed verbatim.
--
-- Everything downstream trusts that value, and the author chose it:
--   · ORDER — both chat reads sort `(created_at, id)`; a back-dated message files itself above
--     messages the reader has already scrolled past, a future-dated one pins itself to the bottom.
--   · THE 100-MESSAGE WINDOW and the composite `(created_at, id)` older-page cursor
--     (`chat-messages.ts`, fix/chat-read-cursor) page by it.
--   · READ STATE — `my_chat_unread` counts `created_at > last_read_at` (0212 §C), so a back-dated
--     message arrives ALREADY READ: the counterpart never sees an unread badge for it. Its
--     `last_message_at` orders the thread list, so a future-dated message pins the thread on top.
--     0223 §A clamps a recorded position at `now()`, which stopped the worst consequence (a
--     future-dated message silencing every later unread) but not the root.
--   · RETENTION — `purge_old_chat()` (0014:63) deletes `created_at < now() - 30 days`. A
--     future-dated message outlives the 30-day retention the product promises; a back-dated one is
--     purged the first night.
--
-- ═══ §0a THE RULE ═════════════════════════════════════════════════════════════════════════════
--
-- A writer that ROW-LEVEL SECURITY POLICES is a client, and the server replaces its `created_at`
-- with `now()` — unconditionally for that writer: a past value, a future value, an explicit NULL
-- and an omitted column all become `now()`. A writer RLS does NOT police — the table owner, a
-- superuser, a BYPASSRLS role such as `service_role` — is the server itself and keeps what it
-- wrote. The test is `row_security_active('public.chat_messages')`, evaluated as the role running
-- the INSERT, which is exactly the question 「did a policy have to admit this row?」.
--
-- `now()`, not `clock_timestamp()`: it is the column's own default, so a stamped row carries the
-- same transaction-start time a default-dated row always did, and 0223 §0d ①'s analysis
-- (「created_at defaults to transaction-start time」) stays true word for word.
--
-- ═══ §0b WHY NOT 「UNCONDITIONALLY FOR EVERY WRITER」 (the brief's literal wording) ═══════════════
--
-- Measured, not argued (battery M0, VERIFY demoted so the suites could run): the unconditional
-- form turns FIVE shipped pins red — 243 `0212-U1` and 254 `0223-C1` / `M1` / `X1` / `F1` —
-- plus this slice's own W1. Their fixtures insert as `postgres` with EXPLICIT timestamps — 254's own fixture
-- note ② explains why they must (one DO block is one transaction, so default-dated rows all share
-- one instant, the degenerate zone where a clock writer and a message writer agree), and 254
-- 0223-F1 plants a future-dated row precisely to prove 0223's clamp. The brief also requires those
-- suites to stay green unchanged. The property the defect needs is 「a CLIENT cannot choose the
-- time」, and the RLS test states it exactly; the server writing its own rows is not the defect.
-- Nothing on the server writes `chat_messages` today (no SECURITY DEFINER inserts it; no edge
-- function touches it — grep of `supabase/functions`, 2026-09-25), so no product path changes.
--
-- ═══ §0c THE CLIENT — NOTHING TO CHANGE ═══════════════════════════════════════════════════════
--
-- `sendChatMessage` (api.ts:4239) inserts `{thread_id, sender_id, body, client_key}` and
-- `sendChatPhoto` (api.ts:4269) `{thread_id, sender_id, kind, media_path, body, client_key}`;
-- neither sends `created_at`, and `chat.tsx`'s `send()` awaits the insert rather than drawing an
-- optimistic bubble with a local time. The shipped client already reads the server's value; this
-- file takes the choice away from every other client (a modified app, a raw PostgREST call).
-- 0162's idempotent retry is unaffected: the retry's own `created_at` never lands, because the
-- unique `(thread_id, client_key)` index refuses the row with 23505 either way.
--
-- ═══ §0d UPDATE — THERE IS NO CLIENT DOOR, SO THERE IS NO UPDATE TRIGGER ══════════════════════
--
-- `chat_messages` has exactly two policies: 「messages party read」 (SELECT, 0002:142) and
-- 「messages party send」 (INSERT, 0114 §2). RLS is enabled and not forced, so no RLS-policed role
-- can UPDATE a row at all — the table-level UPDATE grant reaches zero rows. A BEFORE UPDATE trigger
-- would guard a path no client can reach, and its pin could not be reddened by anything but a
-- planted policy. The ABSENCE is pinned instead (256 0225-U1: the two policies are present, none is
-- UPDATE or ALL, and a party who can read their own message updates zero rows of it). A future
-- slice that adds message editing owns this question the moment U1 goes red.
--
-- ═══ §0e EXISTING ROWS ARE NOT REWRITTEN ══════════════════════════════════════════════════════
--
-- A row a client already dated keeps its date: rewriting history would move messages both parties
-- have seen, and there is no server-side record of when such a row really arrived. Read-only
-- pre-flight for production (Sean, not run from here):
--     select count(*) filter (where created_at > now())                     as future_dated,
--            count(*) filter (where created_at < now() - interval '30 days') as due_for_purge
--       from chat_messages;
-- A nonzero `future_dated` names rows that will sort last and outlive retention until their own
-- date passes; what to do with them is a product decision, not this file's.
--
-- ═══ §0f NAMED LIMITATIONS (prose — a pin cannot reach these) ═════════════════════════════════
--   ① A future SECURITY DEFINER function that inserts `chat_messages` on a client's behalf runs as
--      its owner, so RLS does not police it and its value is kept. That function's author owns the
--      timestamp it passes; it must not forward one from its caller.
--   ② `session_replication_role = replica` skips an ENABLE ORIGIN ('O') trigger. Setting it is
--      superuser-only (PGC_SUSET), so no client can reach it; 256 0225-T1 pins `tgenabled = 'O'`.
--   ③ `now()` is transaction-start time: two sends that start in one microsecond still share a
--      stamp (0223 §0d ① — unchanged by this file, and not widened by it).

-- ═══ §A the stamp ══════════════════════════════════════════════════════════════════════════════
--
-- ⚠ SECURITY INVOKER IS LOAD-BEARING, not a default left in place. `row_security_active` answers
--   for the CURRENT role; inside a SECURITY DEFINER body that is the owner, for whom RLS is never
--   active, so a definer version of this function would stamp nothing, ever, while looking
--   present. 256 0225-S1 pins `prosecdef = false` and the battery flips it.
-- ⚠ `is not false`, never a bare `if`: a NULL answer stamps (fails closed), it does not admit.
create or replace function _chat_messages_stamp_created_at()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
begin
  -- An RLS-policed writer is a client: the time is the server's, whatever the row carried.
  if row_security_active('public.chat_messages'::regclass) is not false then
    new.created_at := now();
  end if;
  return new;
end $$;

comment on function _chat_messages_stamp_created_at() is
  '0225 §A: BEFORE INSERT trigger on chat_messages. When row-level security polices the inserting role (a client: anon/authenticated through PostgREST), created_at becomes now() whatever the row carried — past, future, NULL or omitted. A role RLS does not police (owner, superuser, BYPASSRLS such as service_role) is the server and keeps its value. SECURITY INVOKER on purpose: row_security_active reads the current role, and a definer body would read the owner and never stamp.';

-- A trigger fires on the table's authority, not on the inserting role's EXECUTE grant (measured in
-- 256: every stamp pin inserts as `authenticated` after this revoke), so this only closes direct
-- invocation — the same reasoning 0090 wrote for `notify_chat_message`.
revoke all on function _chat_messages_stamp_created_at() from public, anon, authenticated;

drop trigger if exists chat_messages_stamp_created_at on chat_messages;
create trigger chat_messages_stamp_created_at
  before insert on chat_messages
  for each row execute function _chat_messages_stamp_created_at();

-- ═══ §B VERIFY — fail the apply, not a later harness run ══════════════════════════════════════
do $verify$
declare
  v_bad text := '';
  v_src text;
  v_fn  oid;
begin
  select p.oid into v_fn from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = '_chat_messages_stamp_created_at';
  if v_fn is null then
    raise exception '❌ 0225 VERIFY: NO-FUNCTION(_chat_messages_stamp_created_at)';
  end if;

  -- ① the function: INVOKER (§A), in-body search_path, a trigger function.
  if (select p.prosecdef from pg_proc p where p.oid = v_fn) is not false
  then v_bad := v_bad || ' DEFINER(row_security_active would read the owner)'; end if;
  if (select 'search_path=public, pg_temp' = any (p.proconfig) from pg_proc p where p.oid = v_fn) is not true
  then v_bad := v_bad || ' NO-IN-BODY-SEARCH-PATH'; end if;
  if (select p.prorettype from pg_proc p where p.oid = v_fn) is distinct from 'trigger'::regtype
  then v_bad := v_bad || ' NOT-A-TRIGGER-FUNCTION'; end if;

  -- ② ACL: nobody calls it directly.
  if (has_function_privilege('public',        v_fn, 'execute')
   or has_function_privilege('anon',          v_fn, 'execute')
   or has_function_privilege('authenticated', v_fn, 'execute')) is not false
  then v_bad := v_bad || ' CLIENT-EXECUTE'; end if;

  -- ③ the trigger: one, BEFORE INSERT FOR EACH ROW only (tgtype 7 = ROW|BEFORE|INSERT), bound to
  --    §A, and ENABLED — `tgenabled` is the state; a definition read is only the shape.
  if (select count(*) from pg_trigger t
       where t.tgrelid = 'public.chat_messages'::regclass
         and t.tgname = 'chat_messages_stamp_created_at'
         and not t.tgisinternal
         and t.tgfoid = v_fn
         and t.tgtype = 7
         and t.tgenabled = 'O') is distinct from 1
  then v_bad := v_bad || ' TRIGGER-SHAPE-OR-STATE'; end if;

  -- ④ what the rule READS: RLS on the table (off ⇒ row_security_active is false for everyone and
  --    nothing is stamped), and no UPDATE/ALL policy (§0d — the absence the missing UPDATE trigger
  --    rests on), with the two policies that do exist present so this is not an empty world.
  if (select c.relrowsecurity from pg_class c where c.oid = 'public.chat_messages'::regclass) is not true
  then v_bad := v_bad || ' RLS-OFF'; end if;
  if (select count(*) from pg_policy p
       where p.polrelid = 'public.chat_messages'::regclass and p.polcmd in ('w', '*')) is distinct from 0
  then v_bad := v_bad || ' AN-UPDATE-OR-ALL-POLICY-EXISTS(§0d no longer holds)'; end if;
  if (select count(*) from pg_policy p
       where p.polrelid = 'public.chat_messages'::regclass
         and ((p.polname = 'messages party read' and p.polcmd = 'r')
           or (p.polname = 'messages party send' and p.polcmd = 'a'))) is distinct from 2
  then v_bad := v_bad || ' THE-TWO-KNOWN-POLICIES-ARE-NOT-BOTH-PRESENT'; end if;

  -- ⑤ the body, COMMENTS STRIPPED (the header above quotes the code it describes).
  select regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc p where p.oid = v_fn;
  if v_src is null then v_bad := v_bad || ' NO-SOURCE';
  else
    if (v_src ~ 'row_security_active\s*\(\s*''public\.chat_messages''::regclass\s*\)\s+is\s+not\s+false') is not true
    then v_bad := v_bad || ' THE-RLS-TEST-IS-GONE'; end if;
    if (v_src ~ 'new\.created_at\s*:=\s*now\(\)') is not true
    then v_bad := v_bad || ' THE-STAMP-IS-GONE'; end if;
  end if;

  if v_bad <> '' then
    raise exception '❌ 0225 VERIFY:%', v_bad;
  end if;
end $verify$;
