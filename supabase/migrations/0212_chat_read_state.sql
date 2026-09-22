-- ═══ 0212: chat gets a READ STATE — the unread count the settings screen already promises, and
-- ═══        the receipt a sender has never had
--
-- Deploy: `supabase db push` only, plus a client build. No edge function changes, no cron, no
-- backfill (an absent `chat_reads` row already MEANS 「never read」 and is read that way).
--
-- ═══ §0 WHAT IS MISSING, MEASURED ON TRUNK `0776c11` ═══════════════════════════════════════════
--
-- `chat_threads` is three columns — `id`, `booking_id`, `created_at` (0001:360-363) — and NOTHING
-- anywhere in this schema records who has read what in a thread. `grep -rn 'last_read' supabase/`
-- on trunk returns zero rows outside `notifications.read_at` (0001:357, a different surface: the
-- alerts inbox). Two facts follow, and both of them are visible in the product today.
--
-- ─── ① NO UNREAD COUNT IS COMPUTABLE, AND THE APP ALREADY SELLS ONE ───
--   `notification_prefs.chat` (0187 §A) is a switch labelled 채팅 that gates the chat PUSH. So the
--   product's own settings screen tells a person that chat is a category of thing that arrives —
--   while every chat entry point in the app (`owner` home hero's 채팅 button · `runner` home's job
--   채팅 row · the schedule sheet's 채팅 chip) is a button with **no information on it at all**.
--   A message that has been sitting unread for two hours looks exactly like a thread where nobody
--   has ever spoken. The person who turned the push OFF — which the settings screen invites — has
--   then no surface whatsoever that says a message arrived.
--   ⚠ And a count of this kind cannot be faked client-side. The client holds the newest 100
--     messages of the ONE thread it has open (`fetchMessages`, 2026-09-23); it has never seen the
--     other threads and it has no record of what was on screen last time. An 「unread」 derived
--     from anything the client knows would be a guess, which this repo forbids outright.
--
-- ─── ② NO READ RECEIPT, AND THE PRODUCT'S ANSWER IS TO SEND IT AGAIN ───
--   A runner who writes 「5분 늦어요」 at the door has no way to know whether the owner has seen it.
--   The only move available is to send it a second time, which is exactly what the chat screen's
--   own 「다시 시도」 grammar was built to prevent on the send path and cannot prevent here.
--
-- ═══ §0b WHAT THIS FILE DOES NOT DO ═══════════════════════════════════════════════════════════
--   · It does not touch `chat_messages`, `chat_threads`, their RLS, the realtime `chat-<thread>`
--     room (0108 §2), or `notify_chat_message` (0090). A read position is a new, separate fact.
--   · It adds NO per-message receipt. `chat_reads` holds one timestamp per (thread, person) and
--     the sender's screen derives 「읽음」 from it — so the wire carries a time, not a row per
--     message, and a thread with 300 messages costs one row either way.
--   · It does not tell either party WHEN the counterpart last OPENED the app, only when they last
--     read THIS thread. `chat_thread_read_state` returns exactly one timestamp and it is scoped to
--     the thread the caller is already a party of.
--
-- ═══ §A the table ═════════════════════════════════════════════════════════════════════════════
create table if not exists chat_reads (
  thread_id    uuid not null references chat_threads on delete cascade,
  profile_id   uuid not null references profiles     on delete cascade,
  -- The server's own clock, written only by §B. There is no client-supplied timestamp anywhere in
  -- this file: a read position a client could name is a read position a client could back-date.
  last_read_at timestamptz not null,
  primary key (thread_id, profile_id)
);

-- ⚠ TWO INDEPENDENT LAYERS, and the second one is not decoration. `00_shim.sql:128` mirrors
-- production's default privileges, under which a table born in a migration is `grant all` to
-- `anon` and `authenticated` — so a new table is NOT sealed by silence. The revoke takes the
-- write privileges away (there is no path from a client to an INSERT/UPDATE/DELETE on this table
-- at all), and RLS with a SELECT-only self policy decides rows for the one privilege that is
-- given back. Either layer alone would be enough today; both are here because a grant is a
-- deployment fact and a policy is a schema fact, and they fail in different ways.
alter table chat_reads enable row level security;
revoke all on chat_reads from public, anon, authenticated;
grant select on chat_reads to authenticated;

drop policy if exists "chat reads self" on chat_reads;
create policy "chat reads self" on chat_reads for select using (profile_id = auth.uid());

comment on table chat_reads is
  '0212: one row per (chat thread, person) holding when that person last read that thread. Written ONLY by chat_mark_read (definer, server clock, monotonic); no client INSERT/UPDATE/DELETE grant and no write policy. Read directly only by its owner (RLS "chat reads self"); the COUNTERPART''s value reaches a party through chat_thread_read_state, never through the table. An ABSENT row means 「never read」 and is read as -infinity, so no backfill exists or is needed.';

-- ═══ §B chat_mark_read — the only writer ══════════════════════════════════════════════════════
--
-- ⚠ THE PARTY GATE IS `is_booking_party` (0002:15), NOT `is_booking_party_active` (0114), and the
--   choice is deliberate. 0114 §4 kept every SELECT policy on the plain predicate on purpose:
--   after a cancel both parties keep READING the thread, they just cannot write into it. Marking a
--   thread read is a fact about reading, so gating it on the WRITE predicate would leave a person
--   who can still open a cancelled thread unable to record that they did — and §C would then be
--   the only thing clearing a badge they can see. (§C's set is narrower, so no such badge is drawn
--   today; the point is that the two predicates answer two different questions and this one is a
--   read.)
--
-- ⚠ MONOTONIC BY CONSTRUCTION, NOT BY CONVENTION. `greatest` in the `on conflict` arm means the
--   stored value can never move backwards, whatever order two concurrent calls commit in — and the
--   chat screen calls this on open, on focus AND on every arriving message, so out-of-order
--   arrival is the ordinary case rather than the exotic one. A read position that can go backwards
--   makes a message unread again after it was read, which is a false claim about the past.
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

  return query select v_at;
end $$;

comment on function chat_mark_read(uuid) is
  '0212 §B: record that the caller has read this thread up to NOW. Party gate (is_booking_party — the READ predicate, 0002:15) before any read or write; a stranger and a non-existent thread get the identical not_party. The write is monotonic by construction (greatest in the on-conflict arm), so a late call can never move a read position backwards. Returns the stored last_read_at, flat.';

revoke execute on function chat_mark_read(uuid) from public, anon;
grant  execute on function chat_mark_read(uuid) to authenticated;

-- ═══ §C my_chat_unread — the badge's only source ══════════════════════════════════════════════
--
-- ⚠ THE LIVE SET IS `is_booking_party_active` (0114:179) AND NOTHING RE-DERIVED. That is the
--   predicate the chat screen's own 42501 path implies: it is what `threads party insert` and
--   `messages party send` are gated on, so it is exactly the set of threads in which the reader
--   could REPLY. A badge on a thread you cannot answer is a call to action with no action — and
--   writing the status list out again here would be a second implementation of a rule that already
--   has an owner, free to drift the day 0114's successor lands.
--
-- ⚠ EVERY LIVE THREAD IS RETURNED, INCLUDING THE ZEROS. 「absent from the list」 and 「zero unread」
--   are different facts and the client needs both: a booking present with 0 is a measured zero it
--   may draw as silence, while a booking that is absent is one this read says nothing about. If
--   only the non-zero rows came back, a client could not tell a cleared thread from a thread the
--   read never covered, and 0 would have two meanings again — the defect 0207 exists to fix one
--   surface over.
--
-- ⚠ `unread_count` IS A COUNT OF ROWS. Not an estimate, not a cap, not a 「99+」 — the client may
--   choose to render a cap, but the number that crosses the wire is the number of messages.
create or replace function my_chat_unread()
returns table (thread_id uuid, booking_id uuid, unread_count int, last_message_at timestamptz)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  return query
    select q.o_thread, q.o_booking, q.o_unread, q.o_last
      from (
        select t.id          as o_thread,
               t.booking_id  as o_booking,
               -- The OTHER party's messages only. `is distinct from` rather than `<>` because a
               -- NULL on either side of `<>` yields NULL, which `count(*)` would then drop — the
               -- same collapse the NULL-collapse law names, one layer down in an aggregate.
               -- An absent read row is `-infinity`, so 「never read」 counts EVERYTHING the
               -- counterpart has said, which is the honest default: not zero.
               (select count(*)
                  from chat_messages m
                 where m.thread_id = t.id
                   and m.sender_id is distinct from v_uid
                   and m.created_at > coalesce(r.last_read_at, '-infinity'::timestamptz))::int
                                     as o_unread,
               -- The thread's newest message, from ANY sender — this orders the list and lets a
               -- caller say 「nothing has ever been said here」 (NULL) rather than guessing.
               (select max(m2.created_at) from chat_messages m2 where m2.thread_id = t.id)
                                     as o_last
          from chat_threads t
          left join chat_reads r on r.thread_id = t.id and r.profile_id = v_uid
         where is_booking_party_active(t.booking_id)
      ) q
     order by q.o_last desc nulls last, q.o_thread;
end $$;

comment on function my_chat_unread() is
  '0212 §C: the caller''s live chat threads with a REAL unread count. Live = is_booking_party_active (0114) — the same predicate that decides whether the caller could reply, never a re-derived status list. unread = messages whose sender is NOT the caller and whose created_at is after the caller''s own last_read_at (absent row = -infinity, so never-read counts everything). Threads with zero unread ARE returned, because 「absent」 and 「zero」 are different answers. No subject argument exists, so a caller can only ever ask about themselves.';

revoke execute on function my_chat_unread() from public, anon;
grant  execute on function my_chat_unread() to authenticated;

-- ═══ §D chat_thread_read_state — the counterpart's time, and only that ════════════════════════
--
-- What a sender needs in order to draw 「읽음」 under their own message is ONE number: when the
-- other person last read this thread. That is what this returns, and the shape is what keeps it
-- narrow — there is no way to ask about a third party, because the only argument is a thread the
-- caller must already be a party of, and the answer is derived from that thread's booking rather
-- than from anything the caller names.
--
-- ⚠ ALWAYS EXACTLY ONE ROW. NULL means 「the counterpart has never read this thread」 and the
--   client renders that as no receipt at all. Zero rows would reintroduce the two-meaning absence.
create or replace function chat_thread_read_state(p_thread uuid)
returns table (last_read_at timestamptz)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_b     record;
  v_other uuid;
  v_at    timestamptz;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- GATE BEFORE ANY READ of chat_reads. The booking row is what the gate is ABOUT, so reading it
  -- is the gate rather than a read the gate should have preceded; nothing about the read POSITION
  -- is touched until after the raise. Non-existent thread and stranger take the same branch.
  select b.id, b.owner_id, b.runner_id into v_b
    from chat_threads t join bookings b on b.id = t.booking_id
   where t.id = p_thread;
  if v_b.id is null or is_booking_party(v_b.id) is not true then
    raise exception 'not_party';
  end if;

  -- The counterpart, named from the booking rather than from anything the caller supplied.
  -- `runner_id` is NULL while a booking is still matching, so a thread with no runner yet has no
  -- counterpart and the answer is NULL — never the caller's own time wearing the other's name.
  v_other := case
               when v_uid = v_b.owner_id  then v_b.runner_id
               when v_uid = v_b.runner_id then v_b.owner_id
               else null
             end;
  if v_other is null then
    return query select null::timestamptz;
    return;
  end if;

  select c.last_read_at into v_at
    from chat_reads c
   where c.thread_id = p_thread and c.profile_id = v_other;
  return query select v_at;
end $$;

comment on function chat_thread_read_state(uuid) is
  '0212 §D: the COUNTERPART''s last_read_at for a thread the caller is a party of — the one number a sender needs to draw 「읽음」. Party gate (is_booking_party) before any read of chat_reads; stranger and non-existent thread get the identical not_party. Exactly one row always; NULL = the counterpart has never read this thread (and NULL when the booking has no runner yet, so a matching booking cannot report a reader who does not exist). The counterpart is derived from the booking, never named by the caller.';

revoke execute on function chat_thread_read_state(uuid) from public, anon;
grant  execute on function chat_thread_read_state(uuid) to authenticated;

-- ═══ §E VERIFY — fail the apply, not a later harness run ══════════════════════════════════════
do $verify$
declare v_bad text := ''; v_src text; v_n int;
begin
  -- ① the table's shape and its two layers
  if to_regclass('public.chat_reads') is null then
    v_bad := v_bad || ' NO-TABLE';
  else
    if (select relrowsecurity from pg_class where oid = 'public.chat_reads'::regclass) is not true
    then v_bad := v_bad || ' RLS-OFF'; end if;
    -- SELECT-only policy set: a write policy here would be a second door beside the revoke.
    select count(*) into v_n from pg_policies
     where schemaname = 'public' and tablename = 'chat_reads' and cmd <> 'SELECT';
    if v_n is distinct from 0 then v_bad := v_bad || ' A-WRITE-POLICY-EXISTS'; end if;
    select count(*) into v_n from pg_policies
     where schemaname = 'public' and tablename = 'chat_reads' and cmd = 'SELECT';
    if v_n is distinct from 1 then v_bad := v_bad || ' SELECT-POLICY-COUNT'; end if;
    -- and no client write privilege, in either client role
    if (has_table_privilege('authenticated', 'public.chat_reads', 'insert')
     or has_table_privilege('authenticated', 'public.chat_reads', 'update')
     or has_table_privilege('authenticated', 'public.chat_reads', 'delete')
     or has_table_privilege('anon',          'public.chat_reads', 'select'))
    then v_bad := v_bad || ' CLIENT-WRITE-OR-ANON-READ-GRANT'; end if;
    if has_table_privilege('authenticated', 'public.chat_reads', 'select') is not true
    then v_bad := v_bad || ' AUTHENTICATED-CANNOT-SELECT-ITS-OWN-ROW'; end if;
    if (select count(*) from information_schema.columns
         where table_schema = 'public' and table_name = 'chat_reads') is distinct from 3
    then v_bad := v_bad || ' COLUMN-COUNT'; end if;
  end if;

  -- ② the three definers: prosecdef, in-body search_path, ACL both ways
  if (select count(*) from pg_proc p
       where p.pronamespace = 'public'::regnamespace
         and p.proname in ('chat_mark_read', 'my_chat_unread', 'chat_thread_read_state')
         and p.prosecdef
         and 'search_path=public, pg_temp' = any (p.proconfig)) is distinct from 3
  then v_bad := v_bad || ' DEFINER-SHAPE'; end if;

  if exists (select 1 from pg_proc p
              where p.pronamespace = 'public'::regnamespace
                and p.proname in ('chat_mark_read', 'my_chat_unread', 'chat_thread_read_state')
                and (has_function_privilege('public', p.oid, 'execute')
                  or has_function_privilege('anon',   p.oid, 'execute')))
  then v_bad := v_bad || ' PUBLIC-OR-ANON-EXECUTE'; end if;

  if has_function_privilege('authenticated', 'chat_mark_read(uuid)',          'execute') is not true
   or has_function_privilege('authenticated', 'my_chat_unread()',             'execute') is not true
   or has_function_privilege('authenticated', 'chat_thread_read_state(uuid)', 'execute') is not true
  then v_bad := v_bad || ' AUTHENTICATED-CANNOT-CALL'; end if;

  -- ③ 🔴 NO SUBJECT ARGUMENT ON THE UNREAD READ. The gate there is an ABSENCE, not a clause: with
  --    no parameter by which to name someone else, there is nothing to get wrong. A `p_profile`
  --    added later reddens no behavioural arm where caller and subject are the same person
  --    (0203 E4's law), so it is asserted here, structurally.
  if (select pronargs from pg_proc
       where pronamespace = 'public'::regnamespace and proname = 'my_chat_unread')
     is distinct from 0
  then v_bad := v_bad || ' MY-CHAT-UNREAD-GAINED-AN-ARGUMENT'; end if;

  -- ④ the bodies, COMMENTS STRIPPED. Every paragraph above quotes the code it describes, and an
  --    un-stripped match would be satisfied by the prose rather than by the implementation — the
  --    comment-quoting law, which has cost this repo a pin three times.
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where pronamespace = 'public'::regnamespace and proname = 'chat_mark_read';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(chat_mark_read)';
  else
    if (position('is_booking_party(' in v_src) > 0
        and position('is_booking_party(' in v_src) < position('insert into chat_reads' in v_src))
       is not true
    then v_bad := v_bad || ' MARK-READ-GATE-GONE-OR-AFTER-THE-WRITE'; end if;
    if (v_src ~ 'greatest\s*\(\s*c\.last_read_at\s*,\s*excluded\.last_read_at\s*\)') is not true
    then v_bad := v_bad || ' MARK-READ-IS-NO-LONGER-MONOTONIC'; end if;
  end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where pronamespace = 'public'::regnamespace and proname = 'my_chat_unread';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(my_chat_unread)';
  else
    if (position('is_booking_party_active(' in v_src) > 0) is not true
    then v_bad := v_bad || ' UNREAD-NO-LONGER-USES-THE-REPLY-PREDICATE'; end if;
    if (v_src ~ 'sender_id\s+is\s+distinct\s+from') is not true
    then v_bad := v_bad || ' UNREAD-NO-LONGER-EXCLUDES-THE-CALLERS-OWN-MESSAGES'; end if;
  end if;

  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where pronamespace = 'public'::regnamespace and proname = 'chat_thread_read_state';
  if v_src is null then v_bad := v_bad || ' NO-SOURCE(chat_thread_read_state)';
  else
    if (position('is_booking_party(' in v_src) > 0
        and position('is_booking_party(' in v_src) < position('from chat_reads' in v_src))
       is not true
    then v_bad := v_bad || ' RECEIPT-GATE-GONE-OR-AFTER-THE-READ'; end if;
    if (position('profile_id = v_other' in v_src) > 0) is not true
    then v_bad := v_bad || ' THE-RECEIPT-NO-LONGER-READS-THE-COUNTERPARTS-ROW'; end if;
  end if;

  if v_bad <> '' then
    raise exception '❌ 0212 VERIFY:%', v_bad;
  end if;
end $verify$;
