-- ═══ 0228: reading the chat re-arms its push — a covering chat read marks the 「새 메시지」 nudge read
--
-- Deploy: `supabase db push` only. No edge function, no cron, no backfill (§0c). No client build is
-- needed for THIS file — the shipped client already calls `chat_mark_read_to` (0223) after every
-- successful refresh. The same slice's client half (`push.ts` marking a TAPPED push's row read) is
-- independent of this file and ships in a build.
--
-- ═══ §0 THE DEFECT (gap sweep 2, 2026-09-25 · ops-notifications-1, high, READ) ═════════════════
--
-- `notify_chat_message` (0090:42-95, never re-declared) writes ONE 「새 메시지」 row per unread state:
-- while the recipient holds an unread `새 메시지` row for the booking (0090:74-82), the next message
-- inserts nothing — and therefore pushes nothing, because 0024's push fires only on a
-- `notifications` INSERT. 0090 §② says 「reading it re-arms the nudge」, and the only writers of that
-- row's `read_at` were the inbox (`alerts.tsx` → `markNotificationsRead`, and 모두 읽음). Reading the
-- CHAT wrote `chat_reads` and nothing else — 0212 §B `chat_mark_read` and 0223 §A
-- `chat_mark_read_to` both. So a person who opens the chat from anywhere but the inbox (a run
-- screen's chat button, a home card, an OS push tap) reads every message and leaves the nudge
-- unread, and every later message in that booking is SILENT on their phone until they happen to
-- open the inbox. 0090 kept the escalating case it was built for (「they are NOT reading」); the
-- ordinary case (「they read it and the conversation went on」) lost its phone.
--
-- ═══ §0a THE RULE ═════════════════════════════════════════════════════════════════════════════
--
-- A chat read that COVERS every counterpart message of the thread marks the reader's unread
-- 「새 메시지」 rows for that booking read, in the same transaction as the read position.
--   · COVERS = no counterpart message of the thread is dated after the position this call
--     recorded from — for `chat_mark_read_to` the acknowledged message's `created_at` (clamped,
--     0223 §0d ③), for `chat_mark_read` the stored position. A read UP TO an older message while a
--     newer counterpart message exists leaves the nudge unread: the newer message has not been
--     drawn, and the nudge is the only phone signal it has (it wrote no row of its own, because
--     the unread nudge suppressed it).
--   · COUNTERPART = `sender_id is distinct from` the reader — the exclusion `my_chat_unread` uses
--     (0212 §C). The reader's own later message does not hold the nudge.
--   · THE ROW PREDICATE IS 0090's DEDUPE PREDICATE, conjunct for conjunct (profile_id, ref_id,
--     title '새 메시지', read_at is null): the row this releases is the row the trigger's `exists`
--     waits on — no other title, no other booking, no other person, and nothing narrower.
--   · It runs AFTER the party gate and after every raise (placed after the upsert), so a refused
--     call writes nothing — a raise also rolls the statement back, so the ordering is belt and the
--     rollback is the rule. It also DEPENDS on the gate's own lookups (`v_booking`, and for §A the
--     acknowledged message's `v_at`), so it cannot drift above the gate without breaking.
--
-- ═══ §0b 0212's `chat_mark_read(uuid)` gets the same statement ═══════════════════════════════
--
-- A database carrying 0228 carries 0223 (numeric apply order), so the CURRENT client never reaches
-- 0212's writer against it — `api.ts markChatRead` falls back to it only on PGRST202 for
-- `chat_mark_read_to`. The client that still calls it is a build OLDER than 0223's client, which
-- marks read on focus and on every arriving message; Sean's own phone may carry one. Same clause,
-- same predicate, so neither writer can leave the other's reader silent. For 0212 the position is
-- `greatest(stored, now())`, so the covering test is vacuous for every client-written message (0225
-- stamps them at insert) and the nudge is released on every call — which is 0212's own claim
-- (「read up to now」) carried to the one row that depends on it.
--
-- ═══ §0c NO BACKFILL ═══════════════════════════════════════════════════════════════════════════
--
-- Nudges left unread by pre-0228 chat reads stay unread until the reader's next covering read of
-- that thread (or the inbox), which releases them. A backfill would have to stamp `read_at` on rows
-- nobody opened, at a time nobody read them — a claim about the past the person never made.
--
-- ═══ §0d NAMED LIMITATIONS (prose — the single-session harness cannot produce either state) ═══
--   ① COMMIT-ORDER RACE, one transaction wide. A counterpart message whose transaction is still
--      open when this UPDATE's snapshot is taken is invisible to the `not exists`; if its trigger
--      ran before this UPDATE committed, it saw the old unread nudge and wrote nothing, and this
--      UPDATE then releases that nudge. That one message is unread with no nudge and no push; the
--      next message re-arms normally. Closing it needs the TRIGGER to lock the nudge row it tests
--      (0090's `exists` → `for update`), which is `notify_chat_message` — outside this slice (the
--      push path is held by be/0204-push-outbox).
--   ② Same-microsecond siblings (0223 §0d ①): a counterpart message sharing the acknowledged
--      message's exact `created_at` is not 「after」 it and does not hold the nudge.

-- ═══ §A chat_mark_read_to — 0223 §A's body, copied BY SCRIPT; one statement added after the upsert
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

  -- [0228 §A] RE-ARM THE CHAT NUDGE. When this read covers every counterpart message of the
  -- thread, release the reader's unread 「새 메시지」 rows for this booking — exactly the rows
  -- 0090's dedupe `exists` waits on (same four conjuncts), so the next message pushes again.
  -- A counterpart message dated after the position keeps the nudge: it is that message's
  -- only phone signal. Runs after the gate and after every raise, so a refusal writes nothing.
  update notifications n
     set read_at = now()
   where n.profile_id = v_uid
     and n.ref_id     = v_booking
     and n.title      = '새 메시지'
     and n.read_at is null
     and not exists (select 1 from chat_messages m
                      where m.thread_id = p_thread
                        and m.sender_id is distinct from v_uid
                        and m.created_at > v_at);

  return query select v_stored;
end $$;

comment on function chat_mark_read_to(uuid, bigint) is
  '0223 §A: record that the caller has read this thread UP TO one message — the newest counterpart message their screen rendered — by writing THAT message''s created_at (clamped at now()), never the clock. Party gate (is_booking_party, 0002:15) before any read of a message or a read position; a stranger and a non-existent thread get the identical not_party. A message id outside this thread, a missing id and NULL all get not_in_thread; the caller''s own message gets not_peer_message. Monotonic (greatest), so an older acknowledgement never moves the position back; returns the STORED last_read_at, flat. 0212''s chat_mark_read(uuid) stays for older builds. [0228 §A] When no counterpart message is dated after the acknowledged one, the caller''s unread 「새 메시지」 rows for this booking are marked read (0090''s dedupe predicate), so the next message pushes again.';

-- 0223:130-131 wrote `revoke all`; a function's only privilege is EXECUTE, so `revoke execute` sets
-- the identical ACL — spelled this way because `check-definer-acl.mjs` reads a re-declaring file's
-- revoke by that word (and §C VERIFY ② measures the resulting ACL both ways).
revoke execute on function chat_mark_read_to(uuid, bigint) from public, anon;
grant  execute on function chat_mark_read_to(uuid, bigint) to authenticated;

-- ═══ §B chat_mark_read — 0212 §B's body, copied BY SCRIPT; the same statement added after the upsert
create or replace function chat_mark_read(p_thread uuid)
returns table (last_read_at timestamptz)
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid     uuid := auth.uid();
  v_booking uuid;
  v_at      timestamptz;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- GATE BEFORE ANY READ OR WRITE. The thread lookup yields only `booking_id` — no message, no
  -- counterpart, no read position — and a thread that does not exist takes the SAME branch as a
  -- thread the caller is not a party of, so the refusal is not an existence oracle for thread ids.
  -- ⚠ `is not true`, never a bare `not`: a NULL predicate makes a plpgsql `if` fall through
  --   silently, which on a gate means ADMIT (CLAUDE.md, the NULL-collapse law).
  select t.booking_id into v_booking from chat_threads t where t.id = p_thread;
  if v_booking is null or is_booking_party(v_booking) is not true then
    raise exception 'not_party';
  end if;

  insert into chat_reads as c (thread_id, profile_id, last_read_at)
       values (p_thread, v_uid, now())
  on conflict (thread_id, profile_id) do update
          set last_read_at = greatest(c.last_read_at, excluded.last_read_at)
    returning c.last_read_at into v_at;

  -- [0228 §B] RE-ARM THE CHAT NUDGE. When this read covers every counterpart message of the
  -- thread, release the reader's unread 「새 메시지」 rows for this booking — exactly the rows
  -- 0090's dedupe `exists` waits on (same four conjuncts), so the next message pushes again.
  -- A counterpart message dated after the position keeps the nudge: it is that message's
  -- only phone signal. Runs after the gate and after every raise, so a refusal writes nothing.
  update notifications n
     set read_at = now()
   where n.profile_id = v_uid
     and n.ref_id     = v_booking
     and n.title      = '새 메시지'
     and n.read_at is null
     and not exists (select 1 from chat_messages m
                      where m.thread_id = p_thread
                        and m.sender_id is distinct from v_uid
                        and m.created_at > v_at);

  return query select v_at;
end $$;

comment on function chat_mark_read(uuid) is
  '0212 §B: record that the caller has read this thread up to NOW. Party gate (is_booking_party — the READ predicate, 0002:15) before any read or write; a stranger and a non-existent thread get the identical not_party. The write is monotonic by construction (greatest in the on-conflict arm), so a late call can never move a read position backwards. Returns the stored last_read_at, flat. [0228 §B] When no counterpart message is dated after the stored position, the caller''s unread 「새 메시지」 rows for this booking are marked read (0090''s dedupe predicate), so the next message pushes again.';

revoke execute on function chat_mark_read(uuid) from public, anon;
grant  execute on function chat_mark_read(uuid) to authenticated;

-- ═══ §C VERIFY — fail the apply, not a later harness run ══════════════════════════════════════
do $verify$
declare
  v_bad text := ''; v_src text; v_fn text; v_pos_gate int; v_pos_upsert int; v_pos_upd int;
begin
  -- ① shape: both definers, in-body search_path, the argument lists the clients send
  if (select count(*) from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname in ('chat_mark_read_to', 'chat_mark_read')
         and p.prosecdef
         and 'search_path=public, pg_temp' = any (p.proconfig)) is distinct from 2
  then v_bad := v_bad || ' DEFINER-SHAPE'; end if;
  if (select pg_get_function_identity_arguments(p.oid) from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.proname = 'chat_mark_read_to')
     is distinct from 'p_thread uuid, p_up_to_message_id bigint'
  then v_bad := v_bad || ' ARGUMENTS(chat_mark_read_to)'; end if;
  if (select pg_get_function_identity_arguments(p.oid) from pg_proc p
       where p.pronamespace = 'public'::regnamespace and p.proname = 'chat_mark_read')
     is distinct from 'p_thread uuid'
  then v_bad := v_bad || ' ARGUMENTS(chat_mark_read)'; end if;

  -- ② ACL both ways, both functions
  if (has_function_privilege('public', 'chat_mark_read_to(uuid,bigint)', 'execute')
   or has_function_privilege('anon',   'chat_mark_read_to(uuid,bigint)', 'execute')
   or has_function_privilege('public', 'chat_mark_read(uuid)', 'execute')
   or has_function_privilege('anon',   'chat_mark_read(uuid)', 'execute'))
     is not false
  then v_bad := v_bad || ' PUBLIC-OR-ANON-EXECUTE'; end if;
  if (has_function_privilege('authenticated', 'chat_mark_read_to(uuid,bigint)', 'execute')
      and has_function_privilege('authenticated', 'chat_mark_read(uuid)', 'execute')) is not true
  then v_bad := v_bad || ' AUTHENTICATED-CANNOT-CALL'; end if;

  -- ③ the bodies, COMMENTS STRIPPED (every paragraph above quotes the code it describes). The
  --    release follows the party gate; it is keyed on 0090's four conjuncts and the covering test.
  foreach v_fn in array array['chat_mark_read_to', 'chat_mark_read'] loop
    select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
      from pg_proc where pronamespace = 'public'::regnamespace and proname = v_fn;
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(' || v_fn || ')'; continue; end if;
    v_pos_gate   := position('is_booking_party(' in v_src);
    v_pos_upsert := position('insert into chat_reads' in v_src);
    v_pos_upd    := position('update notifications' in v_src);
    if (v_pos_gate > 0 and v_pos_upsert > v_pos_gate and v_pos_upd > v_pos_gate) is not true
    then v_bad := v_bad || ' ORDER(' || v_fn || ':gate<upsert, gate<release)'; end if;
    if (v_src ~ 'n\.profile_id\s*=\s*v_uid' and v_src ~ 'n\.ref_id\s*=\s*v_booking'
        and v_src ~ 'n\.title\s*=\s*''새 메시지''' and v_src ~ 'n\.read_at\s+is\s+null') is not true
    then v_bad := v_bad || ' RELEASE-PREDICATE(' || v_fn || ')'; end if;
    if (v_src ~ 'not\s+exists\s*\(\s*select\s+1\s+from\s+chat_messages\s+m'
        and v_src ~ 'm\.sender_id\s+is\s+distinct\s+from\s+v_uid'
        and v_src ~ 'm\.created_at\s*>\s*v_at') is not true
    then v_bad := v_bad || ' COVERING-TEST(' || v_fn || ')'; end if;
    if (v_src ~ 'greatest\s*\(\s*c\.last_read_at\s*,\s*excluded\.last_read_at\s*\)') is not true
    then v_bad := v_bad || ' NO-LONGER-MONOTONIC(' || v_fn || ')'; end if;
  end loop;

  -- ④ 0223's own shape survived the copy (its VERIFY does not re-run on a re-declaration)
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where pronamespace = 'public'::regnamespace and proname = 'chat_mark_read_to';
  if v_src is not null then
    if (position('is_booking_party(' in v_src) > 0
        and position('is_booking_party(' in v_src) < position('from chat_messages' in v_src)) is not true
    then v_bad := v_bad || ' 0223-GATE-AFTER-A-MESSAGE-READ'; end if;
    if (v_src ~ 'm\.thread_id\s*=\s*p_thread') is not true
    then v_bad := v_bad || ' 0223-MESSAGE-NOT-SCOPED'; end if;
    if (v_src ~ 'least\s*\(\s*v_at\s*,\s*now\(\)\s*\)') is not true
    then v_bad := v_bad || ' 0223-FUTURE-CLAMP-GONE'; end if;
  end if;

  -- ⑤ the other side of the contract: 0090's dedupe still keys on the literal this releases.
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where pronamespace = 'public'::regnamespace and proname = 'notify_chat_message';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(notify_chat_message)';
  elsif (v_src ~ 'n\.title\s*=\s*''새 메시지''' and v_src ~ 'n\.read_at\s+is\s+null') is not true
  then v_bad := v_bad || ' 0090-DEDUPE-NO-LONGER-KEYED-ON-THE-RELEASED-ROW'; end if;

  if v_bad <> '' then
    raise exception '❌ 0228 VERIFY:%', v_bad;
  end if;
end $verify$;
