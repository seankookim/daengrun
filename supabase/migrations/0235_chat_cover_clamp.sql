-- ═══ 0235: 0228's covering test agrees with 0223's clamp — a forward-dated message no longer holds the nudge
-- ═══        (and a message that commits DURING the read still does — §0d ②, fixer round 1)
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
-- The covering test compares both sides on the same clock: a message dated past the server's clock
-- counts AS now(), the clamp 0223 §0d ③ applies to the position — but ONLY a message dated past
-- the clock, never a real one that committed while this read ran. Written
--     and m.created_at > v_at
--     and (now() > v_at or m.created_at <= clock_timestamp())
-- A counterpart row therefore holds the nudge iff it is dated after the position AND either
--   (i)  the position is before this transaction's start (`now() > v_at`) — then
--        `least(m.created_at, now()) > v_at` is exactly the old test, split into its conjuncts
--        (least(a, b) > x ⟺ a > x ∧ b > x; `created_at` is NOT NULL, 0001:373, so no NULL arm
--        differs), or
--   (ii) the row is dated no later than this statement's wall clock (`clock_timestamp()`, volatile,
--        read as the subquery runs). Every message a client can write since 0225 is stamped with
--        its own transaction's now(), which precedes its commit, which precedes this statement's
--        snapshot, which precedes clock_timestamp() — so EVERY committed, server-stamped message
--        visible here satisfies (ii) and keeps 0228's hold unchanged. Only a row dated past the
--        wall clock (a pre-0225 client's date, or a non-RLS writer's; 0225 §A keeps those) fails
--        (ii), and it is then clamped by (i).
-- Consequences, each pinned in 266:
--   · §A, acknowledging the forward-dated row: v_at = now(), (i) is false and the row is past the
--     wall clock, so the read covers it → release (F1).
--   · §A, acknowledging an OLDER message while the forward-dated row exists: v_at < now(), (i)
--     holds, the row still holds the nudge — it has not been drawn (F1's hold arm). The clamp is
--     not a blanket release.
--   · §A and §B, a counterpart message dated after this transaction's start but before this
--     statement (one that committed while the read ran — §0d ②): (ii) holds → the nudge is held,
--     as 0228 held it (C1 §A, C2 §B). This is the arm the first draft of this file lacked.
--   · §B: v_at = greatest(stored, now()) ≥ now(), so (i) is false for every row and only rows in
--     (v_at, clock_timestamp()] hold — i.e. exactly the messages that committed during the read.
--     A forward-dated row no longer blocks the legacy writer (F2); 0228 §0b already called §B's
--     test vacuous for every message committed before the read began, which stays true.
--     (So in §B the `now() > v_at` disjunct is inert — false for every row. It is kept so both
--     bodies carry the same group; 266's header names it as a gap with no behavioural door.)
--   · The thread scope matters in §B again for that same reason: T2 plants a concurrent-dated
--     counterpart row in the reader's OTHER booking's thread.
-- WHY THE SPLIT FORM AND NOT `least(…)` LITERALLY: suite 259 0228-S1 (a shipped pin, outside this
-- slice) asserts `m\.created_at\s*>\s*v_at` in the stripped body. The split form keeps that pin's
-- sentence true (the covering test is still present); the new disjunction is pinned by 266 0235-S1
-- and by this file's VERIFY, both of which read INSIDE the covering subquery's own parentheses.
--
-- ═══ §0b s2 — THE THREAD SCOPE IS NOW ASSERTED ════════════════════════════════════════════════
--
-- The covering subquery's `m.thread_id = p_thread` was checked by no VERIFY arm and no S1 arm; the
-- reviewer's mutation M3 (scope dropped from §A) applied cleanly and was caught only through other
-- fixtures' leftover messages. 0228 VERIFY ④ `0223-MESSAGE-NOT-SCOPED` matches the WHOLE body, and
-- §A's acknowledged-message lookup also says `m.thread_id = p_thread`, so it could not see it. This
-- file's VERIFY ③ and 266 0235-S1 match inside the COVERING SUBQUERY only (the text between the
-- `(` after `not exists` in the release statement and its matching `)`, found by counting depth —
-- so a conjunct moved OUTSIDE the subquery no longer satisfies them; fixer round 1, R2 finding 4),
-- and 266 0235-T1 (§A) and 0235-T2 (§B) plant a counterpart message in the reader's OTHER
-- booking's thread on purpose.
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
--   · Outside SQL (not this slice), a SECOND client site (R2 finding 2, read at chat-read.ts
--     :187-202 and :268-271): `newestPeerMessageId` picks the acknowledged message by
--     `(created_at, id)`, so a forward-dated peer row stays the 「newest」 after a real message
--     arrives, and `shouldMarkRead` gates reason 'message' on that id CHANGING — so the chat screen
--     never re-marks on an incoming message in such a thread. 'open' and 'focus' do re-mark, and
--     with 0235 they release (they acknowledge the forward row, v_at = now()); a message that
--     lands while the screen is up writes a nudge nobody releases until the next open/focus, and
--     later messages are deduped silent meanwhile. Before 0235 there was no release at all in such
--     a thread, so this is strictly better, not fixed. Client follow-up: order the acknowledgement
--     by min(created_at, now), or let 'message' re-mark when a newer-by-id peer message was
--     fetched under an unchanged target.
--
-- ═══ §0d NAMED LIMITATIONS AND THE RACE THIS FILE'S FIRST DRAFT OPENED ═════════════════════════
--   ① 0228 §0d ① (commit-order race) and ② (same-microsecond siblings) — unchanged; prose, the
--      single-session harness cannot interleave two commits.
--   ② THE FIRST DRAFT OF THIS FILE (`and now() > v_at` alone) DROPPED A CONCURRENT MESSAGE — MEASURED,
--      then FIXED by arm (ii) of §0a. When v_at = now() — EVERY §B call, and a §A call acknowledging
--      a row dated at or after this transaction's start — a counterpart message whose transaction
--      STARTED after this read's and COMMITTED before this UPDATE's snapshot has created_at > now(),
--      so `now() > v_at` was false for it and the nudge was released; its own trigger had seen the
--      unread nudge and written nothing, so that message was left unread with no push and no nudge.
--      Not limited to forward-dated threads: every legacy call. Measured with two real sessions on
--      the harness cluster (R: begin, fix now(), sleep 3 s; M: insert an ordinary message at 1 s and
--      commit; R: call, commit), first draft: §B 1 row / 0 unread, §A (acknowledging a 30-days-
--      ahead row) 1 row / 0 unread, M dated after R's stored position both times — 0228's bodies
--      held it (1 / 1, the R2 reviewer's measurement). With arm (ii): measured 1 row / 1 unread in
--      both modes (the nudge held, as under 0228). The harness reproduces the STATE single-session
--      — a counterpart row dated clock_timestamp() inside the pin's transaction is exactly 「dated
--      after the read's transaction start, before its statement」 — and 266 0235-C1 / C2 pin it.
--   ③ Residual of arm (ii), one read wide: a row forward-dated by LESS than the read's own latency
--      (clock_timestamp() − now(), milliseconds) counts as concurrent and holds; the next read after
--      its date has passed clamps the position to it and covers it. Conservative, self-healing.
--
-- ═══ §0e NO BACKFILL ══════════════════════════════════════════════════════════════════════════
--
-- A nudge held by a forward-dated row is released by the reader's next covering read (or the
-- inbox). Nothing is stamped on anyone's behalf, and no message row is touched.

-- ═══ §A chat_mark_read_to — 0228 §A's body, copied BY SCRIPT; the covering test's last conjunct
-- ═══    `and m.created_at > v_at` gains `and (now() > v_at or m.created_at <= clock_timestamp())`
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
  -- [0235] CLAMP-CONSISTENT COVER. A counterpart message dated past the server's wall clock
  -- counts AS now() — the clamp 0223 §0d ③ already applies to the position — so a read that
  -- acknowledged it covers it instead of being held by it forever (arm `now() > v_at`). A message
  -- dated no later than this statement's clock is a real one (0225 stamps its transaction's now(),
  -- before its commit, before this snapshot) and holds exactly as under 0228, including one that
  -- committed while this read ran (arm `<= clock_timestamp()`; §0a (ii), §0d ②).
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
                        and (now() > v_at or m.created_at <= clock_timestamp()));

  return query select v_stored;
end $$;

comment on function chat_mark_read_to(uuid, bigint) is
  '0223 §A: record that the caller has read this thread UP TO one message — the newest counterpart message their screen rendered — by writing THAT message''s created_at (clamped at now()), never the clock. Party gate (is_booking_party, 0002:15) before any read of a message or a read position; a stranger and a non-existent thread get the identical not_party. A message id outside this thread, a missing id and NULL all get not_in_thread; the caller''s own message gets not_peer_message. Monotonic (greatest), so an older acknowledgement never moves the position back; returns the STORED last_read_at, flat. 0212''s chat_mark_read(uuid) stays for older builds. [0228 §A] When no counterpart message is dated after the acknowledged one, the caller''s unread 「새 메시지」 rows for this booking are marked read (0090''s dedupe predicate), so the next message pushes again. [0235] The covering test compares both sides on one clock: m.created_at > v_at and (now() > v_at or m.created_at <= clock_timestamp()), so a counterpart message dated past the server''s wall clock counts as now() and a read that acknowledged it covers it, while a real message that committed during the read still holds the nudge.';

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
  -- [0235] CLAMP-CONSISTENT COVER. A counterpart message dated past the server's wall clock
  -- counts AS now() — the clamp 0223 §0d ③ already applies to the position — so a read that
  -- acknowledged it covers it instead of being held by it forever (arm `now() > v_at`). A message
  -- dated no later than this statement's clock is a real one (0225 stamps its transaction's now(),
  -- before its commit, before this snapshot) and holds exactly as under 0228, including one that
  -- committed while this read ran (arm `<= clock_timestamp()`; §0a (ii), §0d ②).
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
                        and (now() > v_at or m.created_at <= clock_timestamp()));

  return query select v_at;
end $$;

comment on function chat_mark_read(uuid) is
  '0212 §B: record that the caller has read this thread up to NOW. Party gate (is_booking_party — the READ predicate, 0002:15) before any read or write; a stranger and a non-existent thread get the identical not_party. The write is monotonic by construction (greatest in the on-conflict arm), so a late call can never move a read position backwards. Returns the stored last_read_at, flat. [0228 §B] When no counterpart message is dated after the stored position, the caller''s unread 「새 메시지」 rows for this booking are marked read (0090''s dedupe predicate), so the next message pushes again. [0235] The covering test compares both sides on one clock: m.created_at > v_at and (now() > v_at or m.created_at <= clock_timestamp()), so a counterpart message dated past the server''s wall clock counts as now() and a read that acknowledged it covers it, while a real message that committed during the read still holds the nudge.';

revoke execute on function chat_mark_read(uuid) from public, anon;
grant  execute on function chat_mark_read(uuid) to authenticated;

-- ═══ §C VERIFY — fail the apply, not a later harness run ══════════════════════════════════════
do $verify$
declare
  v_bad text := ''; v_src text; v_rel text; v_sub text; v_fn text; v_pos_gate int; v_pos_upsert int; v_pos_upd int;
  v_m text; v_open int; v_i int; v_depth int; v_ch text;
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
  --    covering-test arms read the COVERING SUBQUERY only — the parenthesised text after `not
  --    exists` inside the release statement — because §A's acknowledged-message lookup also says
  --    `m.thread_id = p_thread` and a whole-body match is satisfied by it (s2: the reason 0228
  --    VERIFY ④ could not see the scope), and because a clamp conjunct outside the subquery inverts
  --    the fix while a statement-wide match still finds it (R2 finding 4).
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
    -- The COVERING SUBQUERY itself: from the `(` after `not exists` to its MATCHING `)`, by depth.
    -- Every covering arm reads this text only, so a conjunct moved outside the subquery (where it
    -- inverts the fix — R2 finding 4, mutation outerclampA) no longer satisfies it. Unbalanced or
    -- absent → empty → every arm below fails loudly.
    v_sub := '';
    v_m := substring(v_rel from 'not\s+exists\s*\(');
    if v_m is not null then
      v_open := position(v_m in v_rel) + length(v_m) - 1;          -- the subquery's own `(`
      v_depth := 0;
      for v_i in v_open .. length(v_rel) loop
        v_ch := substr(v_rel, v_i, 1);
        if v_ch = '(' then v_depth := v_depth + 1;
        elsif v_ch = ')' then
          v_depth := v_depth - 1;
          if v_depth = 0 then v_sub := substr(v_rel, v_open + 1, v_i - v_open - 1); exit; end if;
        end if;
      end loop;
    end if;
    if (v_sub ~ '^\s*select\s+1\s+from\s+chat_messages\s+m\s'
        and v_sub ~ 'm\.sender_id\s+is\s+distinct\s+from\s+v_uid'
        and v_sub ~ 'm\.created_at\s*>\s*v_at') is not true
    then v_bad := v_bad || ' COVERING-TEST(' || v_fn || ')'; end if;
    if (v_sub ~ 'm\.thread_id\s*=\s*p_thread') is not true
    then v_bad := v_bad || ' COVERING-TEST-NOT-THREAD-SCOPED(' || v_fn || ')'; end if;
    if (v_sub ~ '\(\s*now\(\)\s*>\s*v_at\s+or\s+m\.created_at\s*<=\s*clock_timestamp\(\)\s*\)') is not true
    then v_bad := v_bad || ' COVERING-TEST-NOT-CLAMPED(' || v_fn || ':(now() > v_at or m.created_at <= clock_timestamp()) inside the subquery)'; end if;
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
