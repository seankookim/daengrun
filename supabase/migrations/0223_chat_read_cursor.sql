-- ═══ 0223: a chat read is recorded UP TO A MESSAGE the reader's screen rendered — never 「up to now」
--
-- Deploy: `supabase db push` plus a client build. No edge function, no cron, no backfill. The
-- client build ships BEFORE this file can be on production, so it carries a `PENDING_DEPLOY`
-- entry (`app/src/lib/rpc-skew.ts`) and falls back to 0212's `chat_mark_read` until the push —
-- see §0c for what that window costs.
--
-- ═══ §0 THE DEFECT (codex client review, 2026-09-25 · finding #1, high, READ) ═════════════════
--
-- `chat_mark_read(p_thread)` (0212 §B) records the server's `now()`. Its caller, `app/app/chat.tsx`,
-- fired it from the navigation-focus and app-foreground callbacks IMMEDIATELY — on the screen as it
-- was before the app was suspended, before any refetch had landed. After a suspension the server
-- holds peer messages the screen has never drawn, and `now()` is later than every one of them, so
-- all of them became 「읽음」 to the peer at once — and stayed so when the refetch then FAILED.
-- A read receipt is a claim that a person saw something; this one was made on behalf of a screen
-- that had not shown it.
--
-- Two halves, and this file is the server's half:
--   · CLIENT (`chat.tsx`, `chat-read.ts`): refresh first, acknowledge only after a SUCCESSFUL
--     fetch, only up to the newest PEER message that fetch returned and the screen rendered; a
--     failed refresh acknowledges nothing.
--   · SERVER (here): a writer that takes the MESSAGE the screen acknowledges and records THAT
--     message's `created_at`, rather than the clock. Without it, even a correctly ordered client
--     over-claims: `now()` is later than the fetch, so a message committed between the fetch and
--     the mark is acknowledged unseen. `now()` answers 「when did the call arrive」; the question a
--     receipt answers is 「what had the screen shown」, and only a message id can say that.
--
-- ═══ §0b WHAT THIS FILE DOES NOT DO ═══════════════════════════════════════════════════════════
--   · It changes NO existing object. `chat_reads` keeps its three columns, `my_chat_unread` and
--     `chat_thread_read_state` keep comparing `created_at` against `last_read_at` exactly as 0212
--     wrote them, and 0212's `chat_mark_read(uuid)` stays for builds older than this one (they
--     still call it, and removing it would break every installed app on the day of the push).
--   · The position stays a TIMESTAMP, and that is a decision rather than an omission: the three
--     readers above already compare against `last_read_at`, so recording the acknowledged
--     message's own `created_at` makes every one of them answer 「read up to message N」 with no
--     change to any of them. The cost is written down in §0d, not hidden.
--
-- ═══ §0c THE SKEW WINDOW (between the client build and this push) ══════════════════════════════
--   The new client calls `chat_mark_read_to`; PostgREST refuses it with PGRST202 until this file
--   is on production, and the client then calls 0212's `chat_mark_read` — but only AFTER a
--   successful refresh and only when no reconnect hole is open, so `now()` over-reaches by the
--   latency of one render and one RPC rather than by a whole suspension. That residual closes at
--   the push; the PENDING_DEPLOY line comes out the same day
--   (`select count(*) from pg_proc where proname = 'chat_mark_read_to'` → 1).
--
-- ═══ §0d NAMED LIMITATIONS (prose — the harness cannot produce any of these states) ═══════════
--   ① Two rows of ONE thread sharing one exact microsecond: acknowledging one covers the other.
--      `created_at` defaults to transaction-start time and every product insert is its own
--      transaction, so this needs two sends starting in the same microsecond — or a client that
--      writes `created_at` itself (③).
--   ② Commit-order inversion: a message whose transaction STARTED before N's and COMMITTED after
--      the reader's fetch sits below N in time and is covered by acknowledging N. The window is
--      one insert's commit latency. A timestamp cursor cannot close it; a commit-ordered sequence
--      could, and nothing in this product needs one yet.
--   ③ `chat_messages.created_at` is CLIENT-WRITABLE today (table-level grant, no column revoke,
--      no stamping trigger — 0001:373, 0114 §2's policy checks only the thread). A message dated
--      in the future would otherwise drag the reader's position forward past every message the
--      peer sends afterwards, silencing their unread count; §A clamps the recorded time at
--      `now()`, which for that one call is exactly 0212's semantics. The root — server-stamped
--      `created_at` — is a separate slice on the send path, named in this slice's report.

-- ═══ §A chat_mark_read_to — record a read UP TO one message ═══════════════════════════════════
--
-- ⚠ THE PARTY GATE IS FIRST AND IT IS 0212's GATE. `is_booking_party` (0002:15), the READ
--   predicate, for the reason 0212 §B gives: marking a thread read is a fact about reading, and a
--   party of a cancelled booking still reads the thread. The thread lookup yields only
--   `booking_id`; nothing about any MESSAGE is read until after the raise — so a stranger cannot
--   use this function to learn whether a message id exists, whether it belongs to a thread, or
--   who sent it, and a thread that does not exist takes the SAME branch as a stranger's.
--
-- ⚠ ONE TOKEN FOR 「THIS IS NOT A MESSAGE OF THIS THREAD」. A message id from another thread (one
--   the caller is a party of or not) and an id no row has both answer `not_in_thread`, so a party
--   cannot use the refusal to probe other threads' ids. `not_peer_message` is a separate token
--   because it is a separate question about a row the caller can already read (RLS
--   「messages party read」): a read position is a claim about the COUNTERPART's messages, and the
--   client only ever acknowledges those (`chat-read.ts` `newestPeerMessageId`).
--
-- ⚠ MONOTONIC BY CONSTRUCTION, the same `greatest` as 0212 §B. Acknowledging an older message
--   after a newer one — out-of-order arrival, a slow request overtaken by a fast one, two devices
--   — leaves the stored position where it was, and the RETURNED value is the stored one.
create or replace function chat_mark_read_to(p_thread uuid, p_up_to_message_id bigint)
returns table (last_read_at timestamptz)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid     uuid := auth.uid();
  v_booking uuid;
  v_at      timestamptz;
  v_sender  uuid;
  v_stored  timestamptz;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- GATE BEFORE ANY READ OF A MESSAGE OR A READ POSITION. `is not true`, never a bare `not`:
  -- a NULL predicate makes a plpgsql `if` fall through silently, which on a gate means ADMIT.
  select t.booking_id into v_booking from chat_threads t where t.id = p_thread;
  if v_booking is null or is_booking_party(v_booking) is not true then
    raise exception 'not_party';
  end if;

  -- The acknowledged message, scoped to THIS thread. A NULL id matches no row and takes the same
  -- branch as a foreign or missing one.
  select m.created_at, m.sender_id into v_at, v_sender
    from chat_messages m
   where m.id = p_up_to_message_id
     and m.thread_id = p_thread;
  if not found then
    raise exception 'not_in_thread';
  end if;
  if v_sender is not distinct from v_uid then
    raise exception 'not_peer_message';
  end if;

  -- §0d ③: never record a position later than the server's clock.
  v_at := least(v_at, now());

  insert into chat_reads as c (thread_id, profile_id, last_read_at)
       values (p_thread, v_uid, v_at)
  on conflict (thread_id, profile_id) do update
          set last_read_at = greatest(c.last_read_at, excluded.last_read_at)
    returning c.last_read_at into v_stored;

  return query select v_stored;
end $$;

comment on function chat_mark_read_to(uuid, bigint) is
  '0223 §A: record that the caller has read this thread UP TO one message — the newest counterpart message their screen rendered — by writing THAT message''s created_at (clamped at now()), never the clock. Party gate (is_booking_party, 0002:15) before any read of a message or a read position; a stranger and a non-existent thread get the identical not_party. A message id outside this thread, a missing id and NULL all get not_in_thread; the caller''s own message gets not_peer_message. Monotonic (greatest), so an older acknowledgement never moves the position back; returns the STORED last_read_at, flat. 0212''s chat_mark_read(uuid) stays for older builds.';

revoke all     on function chat_mark_read_to(uuid, bigint) from public, anon;
grant  execute on function chat_mark_read_to(uuid, bigint) to authenticated;

-- ═══ §B VERIFY — fail the apply, not a later harness run ══════════════════════════════════════
do $verify$
declare v_bad text := ''; v_src text;
begin
  -- ① shape: definer, in-body search_path, the argument list the client sends, the return column
  if (select count(*) from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname = 'chat_mark_read_to'
         and p.prosecdef
         and 'search_path=public, pg_temp' = any (p.proconfig)) is distinct from 1
  then v_bad := v_bad || ' DEFINER-SHAPE'; end if;

  if (select pg_get_function_identity_arguments(p.oid) from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.proname = 'chat_mark_read_to')
     is distinct from 'p_thread uuid, p_up_to_message_id bigint'
  then v_bad := v_bad || ' ARGUMENTS'; end if;

  -- ② ACL both ways: nobody but a signed-in caller, and a signed-in caller can.
  if (has_function_privilege('public', 'chat_mark_read_to(uuid,bigint)', 'execute')
   or has_function_privilege('anon',   'chat_mark_read_to(uuid,bigint)', 'execute'))
     is not false
  then v_bad := v_bad || ' PUBLIC-OR-ANON-EXECUTE'; end if;
  if has_function_privilege('authenticated', 'chat_mark_read_to(uuid,bigint)', 'execute') is not true
  then v_bad := v_bad || ' AUTHENTICATED-CANNOT-CALL'; end if;

  -- ③ the body, COMMENTS STRIPPED (every paragraph above quotes the code it describes).
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where pronamespace = 'public'::regnamespace and proname = 'chat_mark_read_to';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(chat_mark_read_to)';
  else
    if (position('is_booking_party(' in v_src) > 0
        and position('is_booking_party(' in v_src) < position('from chat_messages' in v_src)
        and position('is_booking_party(' in v_src) < position('insert into chat_reads' in v_src))
       is not true
    then v_bad := v_bad || ' GATE-GONE-OR-AFTER-A-READ'; end if;
    if (v_src ~ 'm\.thread_id\s*=\s*p_thread') is not true
    then v_bad := v_bad || ' MESSAGE-NOT-SCOPED-TO-THE-THREAD'; end if;
    if (v_src ~ 'greatest\s*\(\s*c\.last_read_at\s*,\s*excluded\.last_read_at\s*\)') is not true
    then v_bad := v_bad || ' NO-LONGER-MONOTONIC'; end if;
    if (v_src ~ 'least\s*\(\s*v_at\s*,\s*now\(\)\s*\)') is not true
    then v_bad := v_bad || ' FUTURE-CLAMP-GONE'; end if;
  end if;

  if v_bad <> '' then
    raise exception '❌ 0223 VERIFY:%', v_bad;
  end if;
end $verify$;
