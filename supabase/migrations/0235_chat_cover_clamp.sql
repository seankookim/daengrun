-- ═══ 0235: 0228's covering test agrees with 0223's clamp — a forward-dated message no longer holds the nudge
--
-- Deploy: `supabase db push` only. No edge function, no cron, no client build, no backfill (§0e).
-- Correct-forward for R1 executing review of d0b6b6c..0ee30fa (docs/reviews/2026-09-26-r1-claude-
-- executing-review.md, cloud/doc-truth), server findings s1 (medium) and s2 (low). s3 (low) is a
-- comment in `transition-booking/resolve_return.ts`, same slice, no SQL.
--
-- ═══ §0 THE DEFECT (s1, MEASURED by the reviewer and REPRODUCED here first) ════════════════════
--
-- 0228 released the reader's 「새 메시지」 nudge only when no counterpart message is dated after the
-- read position: `not exists (… m.created_at > v_at)` (0228:128 §A, 0228:185 §B). The position is
-- CLAMPED — 0223 §0d ③ `v_at := least(v_at, now())` — but the message side of the comparison was
-- not. A counterpart row dated in the future therefore stays `> v_at` whatever the reader does:
--   · §A `chat_mark_read_to`: acknowledging that very row records now(), and the row is still after
--     now(), so the read that DREW it is held by it;
--   · §B `chat_mark_read`: the position is `greatest(stored, now())`, still before the row.
-- Until the row's own date passes, every chat read in that thread leaves the nudge unread, and
-- 0090's dedupe then suppresses every later message's push — the exact silence 0228 exists to end,
-- kept open through BOTH writers. Such rows exist wherever a client wrote `created_at` before 0225
-- stamped it (0225 §0e: existing rows are NOT rewritten; its `future_dated` pre-flight count is
-- Sean's to run on production — real-user count is about zero, so this is latent, not widespread).
-- Suite 266 0235-F1 / F2 were written first and measured RED on 0228's bodies (trunk 0ee30fa):
-- unread stayed 1 after acknowledging the forward-dated row, and no second nudge was written.
--
-- ═══ §0a THE RULE ═════════════════════════════════════════════════════════════════════════════
--
-- The covering test compares both sides on the same clock: a message dated past now() counts AS
-- now(), the clamp 0223 §0d ③ applies to the position. Written
--     and m.created_at > v_at
--     and now() > v_at
-- which is `least(m.created_at, now()) > v_at` split into its two conjuncts
-- (least(a, b) > x ⟺ a > x ∧ b > x; `created_at` is NOT NULL, 0001:373, so no NULL arm differs).
-- Consequences, each pinned in 266:
--   · §A, acknowledging the forward-dated row: v_at = now(), so `now() > v_at` is false and the
--     read covers it → release (F1).
--   · §A, acknowledging an OLDER message while the forward-dated row exists: v_at < now(), the row
--     still holds the nudge — it has not been drawn (F1's hold arm). The clamp is not a blanket
--     release.
--   · §B: v_at = greatest(stored, now()) ≥ now(), so the covering subquery is empty for every row
--     and the legacy writer always releases — 0212's own claim, 「read up to now」, carried to the
--     one row that depends on it (F2). 0228 §0b already called §B's test vacuous for every
--     server-stamped message; after 0235 it is vacuous for every message.
-- WHY THE SPLIT FORM AND NOT `least(…)` LITERALLY: suite 259 0228-S1 (a shipped pin, outside this
-- slice) asserts `m\.created_at\s*>\s*v_at` in the stripped body. The split form is the same
-- predicate and keeps that pin's sentence true (the covering test is still present); the new
-- conjunct is pinned by 266 0235-S1 and by this file's VERIFY.
--
-- ═══ §0b s2 — THE THREAD SCOPE IS NOW ASSERTED ════════════════════════════════════════════════
--
-- The covering subquery's `m.thread_id = p_thread` was checked by no VERIFY arm and no S1 arm; the
-- reviewer's mutation M3 (scope dropped from §A) applied cleanly and was caught only through other
-- fixtures' leftover messages. 0228 VERIFY ④ `0223-MESSAGE-NOT-SCOPED` matches the WHOLE body, and
-- §A's acknowledged-message lookup also says `m.thread_id = p_thread`, so it could not see it. This
-- file's VERIFY ③ and 266 0235-S1 match inside the RELEASE STATEMENT only (from `update
-- notifications` to `return query`), and 266 0235-T1 plants a newer counterpart message in the
-- reader's OTHER booking's thread on purpose.
--
-- ═══ §0c EVERY SITE THE FINDING'S SENTENCE COVERS (grep of every migration, 2026-09-26) ════════
--
-- The sentence: 「a comparison of a message's `created_at` against a CLAMPED read position must
-- clamp the message side too」. Grep `created_at\s*>` / `last_read_at` over supabase/migrations:
--   · 0228:128 §A, 0228:185 §B — the covering test. FIXED here (both writers).
--   · 0212:163 §C `my_chat_unread` — `m.created_at > coalesce(r.last_read_at, '-infinity')`.
--     NOT changed, deliberately. (1) The clamp there would not fix it: my_chat_unread runs in a
--     LATER transaction than the read, so `least(created_at, now())` is that later now(), which is
--     after the stored position (the earlier read's now()) — the forward-dated row would count as
--     unread at every query after every read. 0228's covering test works only because it runs in
--     the SAME transaction that stored the clamped position. A badge fix needs a different key (an
--     id cursor, or rewriting the forward-dated rows — 0225 §0e names that a product decision).
--     (2) 254 0223-F1 deliberately pins the current badge (「must be 2: the message an hour later +
--     the one dated tomorrow」). So the badge still counts a forward-dated message until its date;
--     that is 0225 §0e's standing limitation, not this file's.
--   · 0212 §D `chat_thread_read_state` — returns a position, compares nothing.
--   · 0090 `notify_chat_message` — no `created_at` comparison (dedupe is on the notification row).
--   · 0014:63 `purge_old_chat` — `created_at < now() - 30 days` is retention, not a read position.
--   · 0223:116 / 0228:106 `least(v_at, now())` — the clamp itself (unchanged, VERIFY ④ keeps it).
--   · Outside SQL (not this slice): the client's 「읽음」 receipt (`app/src/lib/chat-read.ts`
--     `readReceiptMessageId`) skips an own message dated after the counterpart's position, so a
--     pre-0225 forward-dated OWN message never shows 읽음 until its date. Client code, named only.
--
-- ═══ §0d NAMED LIMITATIONS (prose — the single-session harness cannot produce either state) ═══
--   ① 0228 §0d ① (commit-order race) and ② (same-microsecond siblings) — unchanged.
--   ② A NEW NEIGHBOUR OF ①, one statement wide. When v_at = now() — every §B call, and a §A call
--      acknowledging a row dated at or after this transaction's start — a counterpart message whose
--      transaction STARTED after this read's and COMMITTED before this UPDATE's snapshot has
--      `created_at` > now() and no longer holds the nudge (before 0235 it did). Its trigger saw the
--      unread nudge and wrote nothing, so that one message is unread with no push; the next message
--      re-arms normally. Same outcome class and remedy as ① (lock in `notify_chat_message`).
--
-- ═══ §0e NO BACKFILL ══════════════════════════════════════════════════════════════════════════
--
-- A nudge held by a forward-dated row is released by the reader's next covering read (or the
-- inbox). Nothing is stamped on anyone's behalf, and no message row is touched.

-- ═══ §A chat_mark_read_to — 0228 §A's body, copied BY SCRIPT; the covering test gains `now() > v_at`
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
  -- [0235] CLAMP-CONSISTENT COVER. `m.created_at > v_at and now() > v_at` is exactly
  -- `least(m.created_at, now()) > v_at` (created_at is NOT NULL, 0001:373): a counterpart message
  -- dated past the server clock counts AS now() — the clamp 0223 §0d ③ already applies to the
  -- position — so a read that acknowledged it covers it instead of being held by it forever.
  update notifications n
     set read_at = now()
   where n.profile_id = v_uid
     and n.ref_id     = v_booking
     and n.title      = '새 메시지'
     and n.read_at is null
     and not exists (select 1 from chat_messages m
                      where m.thread_id = p_thread
                        and m.sender_id is distinct from v_uid
                        and m.created_at > v_at
                        and now() > v_at);

  return query select v_stored;
end $$;

comment on function chat_mark_read_to(uuid, bigint) is
  '0223 §A: record that the caller has read this thread UP TO one message — the newest counterpart message their screen rendered — by writing THAT message''s created_at (clamped at now()), never the clock. Party gate (is_booking_party, 0002:15) before any read of a message or a read position; a stranger and a non-existent thread get the identical not_party. A message id outside this thread, a missing id and NULL all get not_in_thread; the caller''s own message gets not_peer_message. Monotonic (greatest), so an older acknowledgement never moves the position back; returns the STORED last_read_at, flat. 0212''s chat_mark_read(uuid) stays for older builds. [0228 §A] When no counterpart message is dated after the acknowledged one, the caller''s unread 「새 메시지」 rows for this booking are marked read (0090''s dedupe predicate), so the next message pushes again. [0235] The covering test compares both sides on one clock: m.created_at > v_at and now() > v_at (= least(m.created_at, now()) > v_at), so a counterpart message dated past the server clock counts as now() and a read that acknowledged it covers it.';

-- Restated in THIS file (a re-declaration never relies on grant preservation — CLAUDE.md, 0116:636).
revoke execute on function chat_mark_read_to(uuid, bigint) from public, anon;
grant  execute on function chat_mark_read_to(uuid, bigint) to authenticated;

-- ═══ §B chat_mark_read — 0228 §B's body, copied BY SCRIPT; the same conjunct added
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
  -- [0235] CLAMP-CONSISTENT COVER. `m.created_at > v_at and now() > v_at` is exactly
  -- `least(m.created_at, now()) > v_at` (created_at is NOT NULL, 0001:373): a counterpart message
  -- dated past the server clock counts AS now() — the clamp 0223 §0d ③ already applies to the
  -- position — so a read that acknowledged it covers it instead of being held by it forever.
  update notifications n
     set read_at = now()
   where n.profile_id = v_uid
     and n.ref_id     = v_booking
     and n.title      = '새 메시지'
     and n.read_at is null
     and not exists (select 1 from chat_messages m
                      where m.thread_id = p_thread
                        and m.sender_id is distinct from v_uid
                        and m.created_at > v_at
                        and now() > v_at);

  return query select v_at;
end $$;

comment on function chat_mark_read(uuid) is
  '0212 §B: record that the caller has read this thread up to NOW. Party gate (is_booking_party — the READ predicate, 0002:15) before any read or write; a stranger and a non-existent thread get the identical not_party. The write is monotonic by construction (greatest in the on-conflict arm), so a late call can never move a read position backwards. Returns the stored last_read_at, flat. [0228 §B] When no counterpart message is dated after the stored position, the caller''s unread 「새 메시지」 rows for this booking are marked read (0090''s dedupe predicate), so the next message pushes again. [0235] The covering test compares both sides on one clock: m.created_at > v_at and now() > v_at (= least(m.created_at, now()) > v_at), so a counterpart message dated past the server clock counts as now() and a read that acknowledged it covers it.';

revoke execute on function chat_mark_read(uuid) from public, anon;
grant  execute on function chat_mark_read(uuid) to authenticated;

-- ═══ §C VERIFY — fail the apply, not a later harness run ══════════════════════════════════════
do $verify$
declare
  v_bad text := ''; v_src text; v_rel text; v_fn text; v_pos_gate int; v_pos_upsert int; v_pos_upd int;
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
  --    covering-test arms read the RELEASE STATEMENT only — `update notifications` up to `return
  --    query` — because §A's acknowledged-message lookup also says `m.thread_id = p_thread` and a
  --    whole-body match is satisfied by it (s2: the reason 0228 VERIFY ④ could not see the scope).
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
    v_rel := case when v_pos_upd > 0
                  then split_part(substr(v_src, v_pos_upd), 'return query', 1) else '' end;
    if (v_rel ~ 'not\s+exists\s*\(\s*select\s+1\s+from\s+chat_messages\s+m'
        and v_rel ~ 'm\.sender_id\s+is\s+distinct\s+from\s+v_uid'
        and v_rel ~ 'm\.created_at\s*>\s*v_at') is not true
    then v_bad := v_bad || ' COVERING-TEST(' || v_fn || ')'; end if;
    if (v_rel ~ 'm\.thread_id\s*=\s*p_thread') is not true
    then v_bad := v_bad || ' COVERING-TEST-NOT-THREAD-SCOPED(' || v_fn || ')'; end if;
    if (v_rel ~ 'now\(\)\s*>\s*v_at') is not true
    then v_bad := v_bad || ' COVERING-TEST-NOT-CLAMPED(' || v_fn || ')'; end if;
    if (v_src ~ 'greatest\s*\(\s*c\.last_read_at\s*,\s*excluded\.last_read_at\s*\)') is not true
    then v_bad := v_bad || ' NO-LONGER-MONOTONIC(' || v_fn || ')'; end if;
  end loop;

  -- ④ 0223's own shape survived the copy (neither 0223's nor 0228's VERIFY re-runs on a
  --    re-declaration)
  select regexp_replace(prosrc, '--[^' || chr(10) || ']*', '', 'g') into v_src
    from pg_proc where pronamespace = 'public'::regnamespace and proname = 'chat_mark_read_to';
  if v_src is not null then
    if (position('is_booking_party(' in v_src) > 0
        and position('is_booking_party(' in v_src) < position('from chat_messages' in v_src)) is not true
    then v_bad := v_bad || ' 0223-GATE-AFTER-A-MESSAGE-READ'; end if;
    if (split_part(v_src, 'insert into chat_reads', 1) ~ 'm\.thread_id\s*=\s*p_thread') is not true
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
    raise exception '❌ 0235 VERIFY:%', v_bad;
  end if;
end $verify$;
