-- ═══ 256 — 0225: a chat message's created_at is written by the SERVER whenever a client sends it
-- ═══        0225-R1 · R2 · D1 · C1 · P1 · W1 · U1 · T1 · S1, tag `cms`
--
-- THE PROPOSITIONS THIS FILE OWNS, each stated without reference to any mutation (the mid-battery
-- law — a pin written while staring at a mutation asserts what that mutation broke).
--
--   · R1 **A CLIENT CANNOT BACK-DATE ITS OWN MESSAGE.** An `authenticated` owner of a live booking
--        inserts `created_at = now() - 1 day`; the row lands at `now()` — in what the client's own
--        RETURNING sees, in what the client can SELECT back, and in the stored row read as
--        `postgres`. `now()` is one instant for the whole DO block, so equality with it is the
--        zero-width window: not earlier, not later.
--   · R2 **A CLIENT CANNOT FORWARD-DATE ITS OWN MESSAGE** — the other party (the runner), the other
--        direction (`now() + 1 day`), the same three reads.
--        🔴 R1 and R2 are the REPRODUCTION: on trunk `f131f28`'s schema (0225 absent) both land
--        verbatim and both pins are RED — measured, see the REGISTRY row.
--   · D1 **A CLIENT THAT SENDS NO TIME STILL GETS THE SERVER'S.** Omitted ⇒ `now()` (the column
--        default also gives this, so this arm is the CONTROL that the stamp did not disturb the
--        shipped client's path — api.ts never sends the column). Explicit NULL ⇒ `now()` as well
--        (without the stamp it is a 23502 not-null violation), which is the arm that separates
--        「the stamp ran」 from 「the default ran」.
--   · C1 **WHAT READS THE TIME READS THE SERVER'S.** The owner has read up to ten minutes ago; the
--        runner then sends a message dated YESTERDAY. It counts as UNREAD (1) in `my_chat_unread`
--        — a back-dated message would otherwise arrive already read — and it sorts LAST in the
--        thread's `(created_at, id)` order, after a message from five minutes ago. A second thread
--        where the runner sends a message dated NEXT YEAR reports `last_message_at = now()`, not
--        next year, so it cannot pin itself atop the thread list.
--   · P1 **THE 30-DAY PURGE DECIDES BY THE STAMPED VALUE.** `purge_old_chat()` (0014:63) deletes a
--        server-planted row dated 31 days ago (the control that the purge runs and reads
--        `created_at`), and keeps a row a client sent dated 40 days ago — its stored time is
--        `now()`. Run inside a rolled-back subtransaction so no other suite's rows are touched.
--   · W1 **THE SERVER KEEPS ITS OWN TIME.** `postgres` (the owner — every fixture in 243/254) and
--        `service_role` (BYPASSRLS — the edge functions' role) insert explicit past timestamps and
--        keep them. This is the other half of 0225 §0a's rule, pinned so that 「stamp every writer」
--        cannot slip in without this file and 243/254 saying so (0225 §0b).
--   · U1 **NO CLIENT CAN UPDATE A MESSAGE, SO NONE CAN RE-DATE ONE.** 0225 adds no UPDATE trigger
--        because there is no client UPDATE door (0225 §0d); this pin owns that absence. The two
--        policies that exist are PRESENT (SELECT 「messages party read」, INSERT 「messages party
--        send」) and neither they nor any other is UPDATE or ALL. Behaviourally: the sender can
--        SELECT their own message (1 row — the thing is present), and the same `update … set
--        created_at` as `authenticated` touches 0 rows and changes nothing, while the identical
--        statement as `postgres` touches 1 (the control that the statement is capable).
--   · T1 **THE TRIGGER IS ON.** `pg_trigger.tgenabled = 'O'` — the STATE, not the definition
--        (`pg_get_triggerdef` renders a disabled trigger identically) — plus exactly one such
--        trigger, BEFORE INSERT FOR EACH ROW (tgtype 7) and nothing else, bound to 0225 §A.
--   · S1 **DEPLOYED SHAPE AND WHAT THE RULE READS.** `prosecdef = false` (a definer body would make
--        `row_security_active` read the owner and never stamp), in-body `search_path`, trigger
--        return type, no client EXECUTE, RLS enabled on `chat_messages`, and in the
--        COMMENT-STRIPPED body the RLS test and the `now()` assignment — with a NO-SOURCE arm and a
--        two-sided control that the stripper ran.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose — the harness cannot reach it) ───
--   · PostgREST itself. The harness reaches the client role by `set local role authenticated`
--     plus `request.jwt.claim.sub`, which is what PostgREST does per request; a real HTTP insert is
--     not run here.
--   · Realtime. The `chat-<thread>` INSERT payload is the stored row, so it carries the stamped
--     value by construction of logical replication; no harness pin observes a realtime event.
--   · A future definer that inserts on a client's behalf (0225 §0f ①) — no such function exists,
--     so any pin about it would be green by construction.
--
-- ─── FIXTURE NOTES ───
--  ① `request.jwt.claim.sub` is set and cleared inside every helper and cleared again at the end;
--     every role switch is asserted (`current_user` is returned and checked) so a pin cannot pass
--     because `set role` did not take.
--  ② Server-side fixture rows (the planted read position, the purge control, the five-minutes-ago
--     message) are written as `postgres`: fixtures, not product paths — and W1 pins that this
--     technique is still honoured.
set client_min_messages = warning;

create or replace function t_cms_thread(p_tag text, out o uuid, out r uuid, out bk uuid, out th uuid)
language plpgsql as $$
declare d uuid; rt uuid;
begin
  o  := t_user('cms_' || p_tag || '_o', 'owner');
  r  := t_user('cms_' || p_tag || '_r', 'runner');
  d  := t_dog(o, 'cms-' || p_tag);
  rt := t_route('cms route ' || p_tag);
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (o, d, r, rt, 'confirmed', now(), 5.0, 9900, 15000, 0, 24900, 9900)
  returning id into bk;
  insert into chat_threads (booking_id) values (bk) returning id into th;
end $$;

-- An INSERT as a named role. p_mode: 'at' sends p_at (NULL included) · 'omit' leaves the column out.
-- Returns what the WRITER saw through RETURNING, and the role the insert actually ran as.
create or replace function t_cms_send(p_role text, p_uid uuid, p_thread uuid, p_body text,
                                      p_mode text, p_at timestamptz) returns jsonb
language plpgsql as $$
declare v_id bigint; v_at timestamptz; v_role text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  if p_role <> 'postgres' then execute format('set local role %I', p_role); end if;
  v_role := current_user;
  if p_mode = 'omit' then
    insert into chat_messages (thread_id, sender_id, body)
    values (p_thread, p_uid, p_body) returning id, created_at into v_id, v_at;
  else
    insert into chat_messages (thread_id, sender_id, body, created_at)
    values (p_thread, p_uid, p_body, p_at) returning id, created_at into v_id, v_at;
  end if;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('id', v_id, 'at', v_at, 'role', v_role);
exception when others then
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('raised', sqlerrm, 'state', sqlstate, 'role', v_role);
end $$;

-- What the party can SELECT back of one message, as the client.
create or replace function t_cms_read_as(p_uid uuid, p_msg bigint) returns jsonb
language plpgsql as $$
declare v_n int; v_at timestamptz; v_role text;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  set local role authenticated;
  v_role := current_user;
  select count(*)::int, max(m.created_at) into v_n, v_at from chat_messages m where m.id = p_msg;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('n', v_n, 'at', v_at, 'role', v_role);
end $$;

create or replace function t_cms_stored(p_msg bigint) returns timestamptz
language sql as $$ select m.created_at from chat_messages m where m.id = p_msg $$;

create or replace function t_cms_unread(p_uid uuid, p_booking uuid) returns jsonb
language plpgsql as $$
declare v_n int; v_last timestamptz;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  select u.unread_count, u.last_message_at into v_n, v_last from my_chat_unread() u where u.booking_id = p_booking;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('unread', v_n, 'last', v_last);
end $$;

do $$
declare
  o uuid; r uuid; bk uuid; th uuid; o2 uuid; r2 uuid; bk2 uuid; th2 uuid;
  v jsonb; v2 jsonb; v3 jsonb; v_bad text; v_msg text; v_n int; v_ids bigint[];
  m_old bigint; m_client bigint; m_recent bigint; m_back bigint; m_own bigint;
  v_old_gone boolean; v_client_kept boolean; v_client_at timestamptz; v_purge_raised text;
  v_src text; v_raw text; v_fn oid;
  t0 timestamptz;
begin
  perform set_config('request.jwt.claim.sub', '', true);                                       -- ①
  t0 := now();

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0225-R1] a client cannot back-date its own message
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select w.o, w.r, w.bk, w.th into o, r, bk, th from t_cms_thread('r1') w;
    v := t_cms_send('authenticated', o, th, 'yesterday, says the client', 'at', t0 - interval '1 day');
    if v ? 'raised' then v_bad := v_bad || ' the party''s send was refused: ' || (v->>'raised');
    else
      if v->>'role' is distinct from 'authenticated' then v_bad := v_bad || ' set role did not take (ran as ' || coalesce(v->>'role','∅') || ')'; end if;
      if (v->>'at')::timestamptz is distinct from t0
      then v_bad := v_bad || ' 🔴 RETURNING shows the client''s value, not the server clock (' || coalesce(v->>'at','∅') || ')'; end if;
      if t_cms_stored((v->>'id')::bigint) is distinct from t0
      then v_bad := v_bad || ' 🔴 the stored created_at is not now() (stored=' || coalesce(t_cms_stored((v->>'id')::bigint)::text,'∅') || ', client sent ' || (t0 - interval '1 day')::text || ')'; end if;
      v2 := t_cms_read_as(o, (v->>'id')::bigint);
      if (v2->>'n')::int is distinct from 1 or (v2->>'at')::timestamptz is distinct from t0
      then v_bad := v_bad || ' the sender reading it back does not see exactly one row at now() (' || v2::text || ')'; end if;
    end if;

    if v_bad = '' then call _pass('cms','0225-R1 a client cannot back-date its own message — an authenticated owner inserting created_at = now() - 1 day gets a row at now() (the zero-width window: equal to the transaction''s now(), neither earlier nor later) in its own RETURNING, in its own SELECT back, and in the stored row. 🔴 Measured RED on trunk f131f28''s schema: the value landed verbatim');
    else v_msg := v_bad; call _fail('cms','0225-R1 a client cannot back-date', v_msg); end if;
  exception when others then call _fail('cms','0225-R1 a client cannot back-date', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0225-R2] a client cannot forward-date its own message — the other party, the other direction
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select w.o, w.r, w.bk, w.th into o, r, bk, th from t_cms_thread('r2') w;
    v := t_cms_send('authenticated', r, th, 'tomorrow, says the client', 'at', t0 + interval '1 day');
    if v ? 'raised' then v_bad := v_bad || ' the runner''s send was refused: ' || (v->>'raised');
    else
      if v->>'role' is distinct from 'authenticated' then v_bad := v_bad || ' set role did not take (ran as ' || coalesce(v->>'role','∅') || ')'; end if;
      if (v->>'at')::timestamptz is distinct from t0
      then v_bad := v_bad || ' 🔴 RETURNING shows the client''s value, not the server clock (' || coalesce(v->>'at','∅') || ')'; end if;
      if t_cms_stored((v->>'id')::bigint) is distinct from t0
      then v_bad := v_bad || ' 🔴 the stored created_at is not now() (stored=' || coalesce(t_cms_stored((v->>'id')::bigint)::text,'∅') || ', client sent ' || (t0 + interval '1 day')::text || ')'; end if;
      v2 := t_cms_read_as(o, (v->>'id')::bigint);
      if (v2->>'n')::int is distinct from 1 or (v2->>'at')::timestamptz is distinct from t0
      then v_bad := v_bad || ' the counterpart reading it does not see exactly one row at now() (' || v2::text || ')'; end if;
    end if;

    if v_bad = '' then call _pass('cms','0225-R2 a client cannot forward-date its own message — the runner inserting created_at = now() + 1 day gets a row at now() in its RETURNING, in the stored row, and in what the owner reads. 🔴 Measured RED on trunk f131f28''s schema: the value landed verbatim');
    else v_msg := v_bad; call _fail('cms','0225-R2 a client cannot forward-date', v_msg); end if;
  exception when others then call _fail('cms','0225-R2 a client cannot forward-date', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0225-D1] a client that sends no time still gets the server's
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select w.o, w.r, w.bk, w.th into o, r, bk, th from t_cms_thread('d1') w;
    -- control: the shipped client's shape (api.ts:4239 never sends the column)
    v := t_cms_send('authenticated', o, th, 'no time sent', 'omit', null);
    if v ? 'raised' then v_bad := v_bad || ' an insert without created_at was refused: ' || (v->>'raised');
    elsif v->>'role' is distinct from 'authenticated' then v_bad := v_bad || ' set role did not take';
    elsif t_cms_stored((v->>'id')::bigint) is distinct from t0
    then v_bad := v_bad || ' the omitted column did not become now() (' || coalesce(t_cms_stored((v->>'id')::bigint)::text,'∅') || ')'; end if;
    -- the discriminating arm: explicit NULL is replaced BEFORE the not-null check
    v2 := t_cms_send('authenticated', r, th, 'null time sent', 'at', null);
    if v2 ? 'raised' then v_bad := v_bad || ' 🔴 an explicit NULL created_at was refused (' || coalesce(v2->>'state','') || ' ' || (v2->>'raised') || ') — the server did not stamp it';
    elsif v2->>'role' is distinct from 'authenticated' then v_bad := v_bad || ' set role did not take (NULL arm)';
    elsif t_cms_stored((v2->>'id')::bigint) is distinct from t0
    then v_bad := v_bad || ' the explicit NULL did not become now()'; end if;

    if v_bad = '' then call _pass('cms','0225-D1 a client that sends no time still gets the server''s — the shipped client''s shape (column omitted) lands at now() (the control that the stamp does not disturb the default path), and an explicit NULL lands at now() too instead of raising 23502 (the arm that separates 「the stamp ran」 from 「the default ran」)');
    else v_msg := v_bad; call _fail('cms','0225-D1 omitted / NULL time', v_msg); end if;
  exception when others then call _fail('cms','0225-D1 omitted / NULL time', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0225-C1] what reads the time reads the server's — unread count, thread order, list order
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select w.o, w.r, w.bk, w.th into o, r, bk, th from t_cms_thread('c1') w;
    -- ② fixtures as postgres: the owner has read up to ten minutes ago; a message from five
    --    minutes ago is already on the thread.
    insert into chat_reads (thread_id, profile_id, last_read_at) values (th, o, t0 - interval '10 minutes');
    v := t_cms_send('postgres', r, th, 'five minutes ago', 'at', t0 - interval '5 minutes');
    m_recent := (v->>'id')::bigint;
    v := t_cms_unread(o, bk);
    if (v->>'unread')::int is distinct from 1 then v_bad := v_bad || ' fixture: unread before the back-dated send is not 1 (' || v::text || ')'; end if;

    -- the runner, as a client, dates a message YESTERDAY — before the owner's read position.
    v := t_cms_send('authenticated', r, th, 'yesterday, says the runner', 'at', t0 - interval '1 day');
    if v ? 'raised' then v_bad := v_bad || ' the runner''s send was refused: ' || (v->>'raised');
    else
      m_back := (v->>'id')::bigint;
      v2 := t_cms_unread(o, bk);
      if (v2->>'unread')::int is distinct from 2
      then v_bad := v_bad || ' 🔴 the back-dated message is not counted unread (unread=' || coalesce(v2->>'unread','∅') || ', must be 2) — it arrived already read'; end if;
      if (v2->>'last')::timestamptz is distinct from t0
      then v_bad := v_bad || ' last_message_at is not the stamped now()'; end if;
      select array_agg(m.id order by m.created_at, m.id) into v_ids from chat_messages m where m.thread_id = th;
      if v_ids is distinct from array[m_recent, m_back]
      then v_bad := v_bad || ' 🔴 the (created_at, id) order does not put the new message LAST (' || coalesce(v_ids::text,'∅') || ')'; end if;
    end if;

    -- a second thread: a message dated NEXT YEAR cannot pin the thread atop the list.
    select w.o, w.r, w.bk, w.th into o2, r2, bk2, th2 from t_cms_thread('c1b') w;
    v3 := t_cms_send('authenticated', r2, th2, 'next year, says the runner', 'at', t0 + interval '1 year');
    if v3 ? 'raised' then v_bad := v_bad || ' the next-year send was refused: ' || (v3->>'raised');
    elsif (t_cms_unread(o2, bk2)->>'last')::timestamptz is distinct from t0
    then v_bad := v_bad || ' 🔴 last_message_at of the next-year thread is not now() (' || coalesce(t_cms_unread(o2, bk2)->>'last','∅') || ')'; end if;

    if v_bad = '' then call _pass('cms','0225-C1 what reads the time reads the server''s — the owner has read up to ten minutes ago; the runner sends a message dated YESTERDAY as a client: my_chat_unread counts it (2, with the five-minutes-ago message), where a back-dated row would have arrived already read; it sorts LAST in the thread''s (created_at, id) order; and a message dated NEXT YEAR on another thread reports last_message_at = now(), so it cannot pin its thread atop the list');
    else v_msg := v_bad; call _fail('cms','0225-C1 readers see the stamped time', v_msg); end if;
  exception when others then call _fail('cms','0225-C1 readers see the stamped time', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0225-P1] the 30-day purge decides by the stamped value
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select w.o, w.r, w.bk, w.th into o, r, bk, th from t_cms_thread('p1') w;
    v := t_cms_send('postgres', r, th, 'planted 31 days ago', 'at', t0 - interval '31 days');
    m_old := (v->>'id')::bigint;
    v2 := t_cms_send('authenticated', o, th, '40 days ago, says the client', 'at', t0 - interval '40 days');
    if v2 ? 'raised' then v_bad := v_bad || ' the client send was refused: ' || (v2->>'raised'); end if;
    m_client := (v2->>'id')::bigint;
    if t_cms_stored(m_old) is distinct from t0 - interval '31 days' then v_bad := v_bad || ' fixture: the planted row is not 31 days old'; end if;

    -- run the product's purge, observe, then roll the subtransaction back so no other suite's
    -- rows are deleted by this pin. plpgsql variables survive the rollback.
    v_old_gone := null; v_client_kept := null; v_client_at := null; v_purge_raised := null;
    begin
      perform purge_old_chat();
      v_old_gone    := not exists (select 1 from chat_messages m where m.id = m_old);
      v_client_kept := exists (select 1 from chat_messages m where m.id = m_client);
      v_client_at   := t_cms_stored(m_client);
      raise exception using errcode = 'ZZ225', message = 'roll back the purge';
    exception
      when sqlstate 'ZZ225' then null;
      when others then v_purge_raised := sqlerrm;
    end;
    if v_purge_raised is not null then v_bad := v_bad || ' purge_old_chat raised: ' || v_purge_raised; end if;
    if v_old_gone is not true then v_bad := v_bad || ' control: the purge did not delete the row planted 31 days ago'; end if;
    if v_client_kept is not true
    then v_bad := v_bad || ' 🔴 the purge deleted the client''s message — it read the client''s 40-days-ago value, not the stamp'; end if;
    if v_client_at is distinct from t0 then v_bad := v_bad || ' the surviving row is not dated now()'; end if;
    if not exists (select 1 from chat_messages m where m.id = m_old)
    then v_bad := v_bad || ' the purge was not rolled back (the planted row is gone after the pin)'; end if;

    if v_bad = '' then call _pass('cms','0225-P1 the 30-day purge decides by the stamped value — purge_old_chat() (0014:63) deletes a server-planted row dated 31 days ago (the control that it runs and reads created_at) and keeps a message a client sent dated 40 days ago, whose stored time is now(); run in a rolled-back subtransaction, the planted row is back afterwards');
    else v_msg := v_bad; call _fail('cms','0225-P1 purge reads the stamp', v_msg); end if;
  exception when others then call _fail('cms','0225-P1 purge reads the stamp', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0225-W1] the server keeps its own time (owner / superuser, and BYPASSRLS service_role)
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select w.o, w.r, w.bk, w.th into o, r, bk, th from t_cms_thread('w1') w;
    v := t_cms_send('postgres', r, th, 'server, two days ago', 'at', t0 - interval '2 days');
    if v ? 'raised' then v_bad := v_bad || ' the postgres insert raised: ' || (v->>'raised');
    elsif t_cms_stored((v->>'id')::bigint) is distinct from t0 - interval '2 days'
    then v_bad := v_bad || ' postgres (owner) lost its explicit time'; end if;
    v2 := t_cms_send('service_role', r, th, 'service, three days ago', 'at', t0 - interval '3 days');
    if v2 ? 'raised' then v_bad := v_bad || ' the service_role insert raised: ' || (v2->>'raised');
    elsif v2->>'role' is distinct from 'service_role' then v_bad := v_bad || ' set role service_role did not take';
    elsif t_cms_stored((v2->>'id')::bigint) is distinct from t0 - interval '3 days'
    then v_bad := v_bad || ' service_role lost its explicit time'; end if;

    if v_bad = '' then call _pass('cms','0225-W1 the server keeps its own time — postgres (the owner, the role every 243/254 fixture writes as) and service_role (BYPASSRLS, the edge functions'' role) insert explicit past timestamps and keep them: 0225 §0a stamps exactly the writers RLS polices');
    else v_msg := v_bad; call _fail('cms','0225-W1 server writers keep their time', v_msg); end if;
  exception when others then call _fail('cms','0225-W1 server writers keep their time', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0225-U1] no client can UPDATE a message, so none can re-date one
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    -- the catalog: the two policies that exist are PRESENT, and none is UPDATE or ALL.
    if (select count(*) from pg_policy p
         where p.polrelid = 'public.chat_messages'::regclass
           and ((p.polname = 'messages party read' and p.polcmd = 'r')
             or (p.polname = 'messages party send' and p.polcmd = 'a'))) is distinct from 2
    then v_bad := v_bad || ' the SELECT and INSERT policies are not both present (the absence below would be read in an empty world)'; end if;
    select count(*)::int into v_n from pg_policy p
     where p.polrelid = 'public.chat_messages'::regclass and p.polcmd in ('w', '*');
    if v_n is distinct from 0 then v_bad := v_bad || ' 🔴 an UPDATE or ALL policy exists on chat_messages (' || v_n || ') — 0225 §0d no longer holds'; end if;

    -- behaviour: the sender's own message, present and readable, cannot be re-dated.
    select w.o, w.r, w.bk, w.th into o, r, bk, th from t_cms_thread('u1') w;
    v := t_cms_send('authenticated', o, th, 'mine', 'omit', null);
    m_own := (v->>'id')::bigint;
    if (t_cms_read_as(o, m_own)->>'n')::int is distinct from 1 then v_bad := v_bad || ' fixture: the sender cannot read their own message'; end if;
    v_n := null;
    begin
      perform set_config('request.jwt.claim.sub', o::text, true);
      set local role authenticated;
      if current_user <> 'authenticated' then
        raise exception 'set role did not take: current_user=%', current_user using errcode = 'ZZ001';
      end if;
      update chat_messages set created_at = t0 - interval '1 day', body = 'edited' where id = m_own;
      get diagnostics v_n = row_count;
      reset role;
      perform set_config('request.jwt.claim.sub', '', true);
    exception when others then
      v_bad := v_bad || ' the client update raised instead of reaching zero rows: ' || sqlerrm;
      perform set_config('request.jwt.claim.sub', '', true);
    end;
    if v_n is distinct from 0 then v_bad := v_bad || ' 🔴 the client''s UPDATE touched ' || coalesce(v_n::text,'∅') || ' rows (must be 0)'; end if;
    if t_cms_stored(m_own) is distinct from t0
       or (select m.body from chat_messages m where m.id = m_own) is distinct from 'mine'
    then v_bad := v_bad || ' 🔴 the message changed under the client''s UPDATE'; end if;
    -- control: the identical statement as postgres reaches the row
    update chat_messages set created_at = t0 - interval '1 day', body = 'edited' where id = m_own;
    get diagnostics v_n = row_count;
    if v_n is distinct from 1 then v_bad := v_bad || ' control: the same UPDATE as postgres did not reach the row (' || coalesce(v_n::text,'∅') || ')'; end if;

    if v_bad = '' then call _pass('cms','0225-U1 no client can UPDATE a message, so none can re-date one — chat_messages has exactly its SELECT and INSERT policies (both present) and no UPDATE or ALL policy; the sender, who reads their own message (1 row), updates created_at and body as authenticated and reaches 0 rows with nothing changed, while the identical statement as postgres reaches 1 (the statement is capable). 0225 adds no UPDATE trigger because this door does not exist (0225 §0d)');
    else v_msg := v_bad; call _fail('cms','0225-U1 no client UPDATE door', v_msg); end if;
  exception when others then call _fail('cms','0225-U1 no client UPDATE door', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0225-T1] the trigger is ON — state, not definition
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select p.oid into v_fn from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname = '_chat_messages_stamp_created_at';
    if v_fn is null then v_bad := v_bad || ' NO-FUNCTION(_chat_messages_stamp_created_at)'; end if;
    select count(*)::int into v_n from pg_trigger t
     where t.tgrelid = 'public.chat_messages'::regclass and not t.tgisinternal
       and t.tgfoid is not distinct from v_fn;
    if v_n is distinct from 1 then v_bad := v_bad || ' the stamp function is bound by ' || v_n || ' triggers (must be exactly 1)'; end if;
    if (select t.tgenabled from pg_trigger t
         where t.tgrelid = 'public.chat_messages'::regclass
           and t.tgname = 'chat_messages_stamp_created_at' and not t.tgisinternal) is distinct from 'O'
    then v_bad := v_bad || ' 🔴 tgenabled is not ''O'' (' || coalesce((select t.tgenabled::text from pg_trigger t where t.tgrelid = 'public.chat_messages'::regclass and t.tgname = 'chat_messages_stamp_created_at'), 'absent') || ')'; end if;
    if (select t.tgtype from pg_trigger t
         where t.tgrelid = 'public.chat_messages'::regclass
           and t.tgname = 'chat_messages_stamp_created_at' and not t.tgisinternal) is distinct from 7::int2
    then v_bad := v_bad || ' the trigger is not BEFORE INSERT FOR EACH ROW only (tgtype 7)'; end if;
    if (select t.tgfoid from pg_trigger t
         where t.tgrelid = 'public.chat_messages'::regclass
           and t.tgname = 'chat_messages_stamp_created_at' and not t.tgisinternal) is distinct from v_fn
    then v_bad := v_bad || ' the trigger is not bound to _chat_messages_stamp_created_at'; end if;

    if v_bad = '' then call _pass('cms','0225-T1 the trigger is ON — pg_trigger.tgenabled = ''O'' for chat_messages_stamp_created_at (the state; pg_get_triggerdef renders a disabled trigger identically), BEFORE INSERT FOR EACH ROW only (tgtype 7), bound to _chat_messages_stamp_created_at, and it is the one trigger that function drives');
    else v_msg := v_bad; call _fail('cms','0225-T1 trigger enabled', v_msg); end if;
  exception when others then call _fail('cms','0225-T1 trigger enabled', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0225-S1] deployed shape, and what the rule READS
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    select p.oid into v_fn from pg_proc p
     where p.pronamespace = 'public'::regnamespace and p.proname = '_chat_messages_stamp_created_at';
    if v_fn is null then v_bad := v_bad || ' NO-FUNCTION(_chat_messages_stamp_created_at)';
    else
      if (select p.prosecdef from pg_proc p where p.oid = v_fn) is not false
      then v_bad := v_bad || ' 🔴 SECURITY DEFINER — row_security_active would read the owner and never stamp'; end if;
      if (select 'search_path=public, pg_temp' = any (p.proconfig) from pg_proc p where p.oid = v_fn) is not true
      then v_bad := v_bad || ' no in-body search_path'; end if;
      if (select p.prorettype from pg_proc p where p.oid = v_fn) is distinct from 'trigger'::regtype
      then v_bad := v_bad || ' not a trigger function'; end if;
      if (has_function_privilege('public',        v_fn, 'execute')
       or has_function_privilege('anon',          v_fn, 'execute')
       or has_function_privilege('authenticated', v_fn, 'execute')) is not false
      then v_bad := v_bad || ' a client role can execute the stamp function directly'; end if;

      select p.prosrc, regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
        into v_raw, v_src from pg_proc p where p.oid = v_fn;
      if v_src is null then v_bad := v_bad || ' NO-SOURCE(_chat_messages_stamp_created_at)';
      else
        -- 🔴 TWO-SIDED CONTROL THAT THE STRIPPER RAN. `An RLS-policed writer` appears ONLY in the
        --    body's comment; if it survives stripping, the arms below are reading prose.
        if (position('An RLS-policed writer' in v_raw) > 0) is not true
        then v_bad := v_bad || ' the comment-control string is absent from the raw body — the stripper control is vacuous'; end if;
        if (position('An RLS-policed writer' in v_src) > 0) is not false
        then v_bad := v_bad || ' comments were not stripped — the arms below would be measuring prose'; end if;
        if (v_src ~ 'row_security_active\s*\(\s*''public\.chat_messages''::regclass\s*\)\s+is\s+not\s+false') is not true
        then v_bad := v_bad || ' the RLS test (row_security_active … is not false) is gone'; end if;
        if (v_src ~ 'new\.created_at\s*:=\s*now\(\)') is not true
        then v_bad := v_bad || ' the now() assignment is gone'; end if;
      end if;
    end if;
    if (select c.relrowsecurity from pg_class c where c.oid = 'public.chat_messages'::regclass) is not true
    then v_bad := v_bad || ' 🔴 RLS is off on chat_messages — row_security_active is false for every writer and nothing is stamped'; end if;

    if v_bad = '' then call _pass('cms','0225-S1 deployed shape — _chat_messages_stamp_created_at is SECURITY INVOKER (a definer body would make row_security_active read the owner and never stamp), in-body search_path, returns trigger, and no client role can execute it; RLS is enabled on chat_messages (what the rule reads); the comment-stripped body holds row_security_active(''public.chat_messages''::regclass) is not false and new.created_at := now(). NO-SOURCE arm + a two-sided control that the stripper ran');
    else v_msg := v_bad; call _fail('cms','0225-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('cms','0225-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
