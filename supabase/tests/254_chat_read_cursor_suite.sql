-- ═══ 254 — 0223: a chat read is recorded UP TO A MESSAGE, never 「up to now」
-- ═══        0223-C1 · M1 · G1 · X1 · F1 · S1, tag `crc`
--
-- THE PROPOSITIONS THIS FILE OWNS, each stated without reference to any mutation (the mid-battery
-- law — a pin written while staring at a mutation asserts what that mutation broke).
--
--   · C1 **THE POSITION IS THE ACKNOWLEDGED MESSAGE'S TIME, NOT THE CLOCK.** 🔴 The fixture sits
--        where the old rule and the new one DISAGREE: the runner has sent three messages, the owner
--        acknowledges the MIDDLE one, and the third — dated after it but before `now()` — is the
--        message a screen had not yet drawn. The new writer leaves it unread (count 1) and the
--        runner's receipt reads the middle message's time; 0212's `chat_mark_read`, run on a twin
--        thread with the identical timeline, calls it read (count 0, position = now()). Both
--        answers are measured in this pin, so 「the fixture can tell the two rules apart」 is an
--        observation, not an assumption.
--   · M1 **A READ POSITION NEVER MOVES BACKWARDS, AND IT DOES MOVE FORWARD.** Acknowledging the
--        newest message advances it; acknowledging an OLDER one afterwards leaves it where it was
--        and REPORTS the stored value rather than the one it tried to write; a position planted in
--        the future by the legacy writer survives. One row per (thread, person) throughout.
--   · G1 **THE PARTY GATE IS FIRST, AND IT IS NOT AN ORACLE — for threads OR for messages.** A
--        stranger gets `not_party` for (real thread, real message), (real thread, missing
--        message) and (missing thread, real message) — the identical word three times, so the
--        refusal cannot say whether a message id exists or where it lives. Anonymous gets
--        `not_authenticated`. The party's call succeeds (the control that the refusals are about
--        identity). 🔴 The gate precedes the WRITE, measured: every refused call leaves the
--        thread's `chat_reads` row count at 0; the party's one call takes it to 1.
--   · X1 **THE CURSOR MUST NAME A COUNTERPART'S MESSAGE IN THIS THREAD — one token per question.**
--        A party of two threads passes (a) a message of their OTHER thread, (b) a message of a
--        thread they are a stranger to, (c) an id no row has, (d) NULL: all four answer the
--        identical `not_in_thread`. Their OWN message answers `not_peer_message`. None of the five
--        writes a row; a real peer message then does.
--   · F1 **A FUTURE-DATED MESSAGE CANNOT DRAG THE POSITION PAST THE SERVER'S CLOCK.**
--        `chat_messages.created_at` is client-writable today (0223 §0d ③). Acknowledging a message
--        dated tomorrow records `now()`, not tomorrow — and the arm that makes it mean something:
--        a peer message sent AFTER the acknowledgement but before tomorrow is still counted
--        unread, which is exactly what an unclamped position would have silenced.
--   · S1 **DEPLOYED SHAPE.** `prosecdef`, the in-body `search_path`, the argument list the client
--        sends, the return column; ACL both ways; the body with COMMENTS STRIPPED — gate before
--        the first read of `chat_messages` AND before the write, the thread scope on the message
--        lookup, `greatest`, the `least(…, now())` clamp — with a NO-SOURCE arm so an absent
--        function fails LOUDLY and a two-sided control that the stripper actually ran.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose — the harness cannot reach it) ───
--   · Concurrency. `greatest` is what makes two racing acknowledgements order-independent; this
--     harness is one session. M1's 「an older acknowledgement after a newer one」 is the same
--     inequality seen from the outside.
--   · 0223 §0d ① and ② (same-microsecond siblings, commit-order inversion). A single-session
--     harness cannot produce a commit that lands after a read which began before it, and a pin
--     for a state it cannot produce would be green by construction.
--   · The client. `app/test/chat-read.test.cjs` and `chat-window.test.cjs` pin the rule for WHICH
--     message a screen acknowledges and WHEN; no SQL pin can see a `.tsx` route module.
--
-- ─── FIXTURE NOTES ───
--  ① `request.jwt.claim.sub` is set and cleared inside every helper and cleared again at the end.
--  ② Every message carries an EXPLICIT `created_at` around `now()`: the whole DO block is one
--     transaction, so `now()` is one instant and default-dated rows would all share it — the
--     degenerate zone where a clock writer and a message writer give the same answer.
--  ③ A position the product's writers would not produce (the future) is planted directly as
--     `postgres`: a fixture, not a product path.
set client_min_messages = warning;

create or replace function t_crc_thread(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                        out bk uuid, out th uuid)
language plpgsql as $$
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'confirmed', now(), 5.0, 9900, 15000, 0, 24900, 9900)
  returning id into bk;
  insert into chat_threads (booking_id) values (bk) returning id into th;
end $$;

create or replace function t_crc_msg(p_thread uuid, p_sender uuid, p_body text, p_at timestamptz)
returns bigint language sql as $$
  insert into chat_messages (thread_id, sender_id, body, created_at)
  values (p_thread, p_sender, p_body, p_at)
  returning id
$$;

-- The product's new writer, as a named caller. `p_uid` NULL = anonymous.
create or replace function t_crc_mark_to(p_uid uuid, p_thread uuid, p_msg bigint) returns jsonb
language plpgsql as $$
declare v timestamptz; v_rows int;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  select count(*)::int, max(m.last_read_at) into v_rows, v from chat_mark_read_to(p_thread, p_msg) m;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('rows', v_rows, 'at', v);
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('raised', sqlerrm);
end $$;

-- 0212's writer — the rule this file replaces for current builds, run as the divergence control.
create or replace function t_crc_mark_legacy(p_uid uuid, p_thread uuid) returns jsonb
language plpgsql as $$
declare v timestamptz;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  select m.last_read_at into v from chat_mark_read(p_thread) m;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('at', v);
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('raised', sqlerrm);
end $$;

create or replace function t_crc_unread(p_uid uuid, p_booking uuid) returns int
language plpgsql as $$
declare v int;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  select u.unread_count into v from my_chat_unread() u where u.booking_id = p_booking;
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;

create or replace function t_crc_receipt(p_uid uuid, p_thread uuid) returns timestamptz
language plpgsql as $$
declare v timestamptz;
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, true);
  select s.last_read_at into v from chat_thread_read_state(p_thread) s;
  perform set_config('request.jwt.claim.sub', '', true);
  return v;
end $$;

create or replace function t_crc_stored(p_thread uuid, p_uid uuid) returns timestamptz
language sql as $$
  select c.last_read_at from chat_reads c where c.thread_id = p_thread and c.profile_id = p_uid
$$;

create or replace function t_crc_rows(p_thread uuid) returns int
language sql as $$ select count(*)::int from chat_reads c where c.thread_id = p_thread $$;

do $$
declare
  o uuid; r uuid; d uuid; rt uuid; stranger uuid; o2 uuid; r2 uuid; d2 uuid;
  bk uuid; th uuid; bk2 uuid; th2 uuid; bk3 uuid; th3 uuid;
  m1 bigint; m2 bigint; m3 bigint; m_own bigint; m_other bigint; m_foreign bigint; m_future bigint;
  v jsonb; v2 jsonb; v3 jsonb; v4 jsonb; v_bad text; v_msg text; v_n int;
  v_src text; v_raw text;
  t0 timestamptz; t_planted timestamptz;
begin
  perform set_config('request.jwt.claim.sub', '', true);                                       -- ①
  t0 := now();

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0223-C1] the position is the ACKNOWLEDGED message's time, not the clock
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('crc_c1_o', 'owner');
    r  := t_user('crc_c1_r', 'runner');
    d  := t_dog(o, 'crc-c1');
    rt := t_route('crc route c1');
    select w.bk, w.th into bk,  th  from t_crc_thread(o, r, d, rt) w;
    select w.bk, w.th into bk2, th2 from t_crc_thread(o, r, d, rt) w;                       -- the twin

    -- ② the same timeline in both threads. m3 is the message 「the screen had not drawn yet」:
    --    after the acknowledged one, before now().
    m1 := t_crc_msg(th,  r, 'r-1', t0 - interval '300 seconds');
    m2 := t_crc_msg(th,  r, 'r-2', t0 - interval '120 seconds');
    m3 := t_crc_msg(th,  r, 'r-3', t0 - interval '30 seconds');
    perform t_crc_msg(th2, r, 'r-1', t0 - interval '300 seconds');
    perform t_crc_msg(th2, r, 'r-2', t0 - interval '120 seconds');
    perform t_crc_msg(th2, r, 'r-3', t0 - interval '30 seconds');

    if t_crc_unread(o, bk) is distinct from 3 then v_bad := v_bad || ' fixture: unread before any read is not 3'; end if;

    v := t_crc_mark_to(o, th, m2);
    if v ? 'raised' then v_bad := v_bad || ' the cursor mark was refused: ' || (v->>'raised'); end if;
    if (v->>'rows')::int is distinct from 1 then v_bad := v_bad || ' the return is not exactly one row'; end if;
    -- 🔴 the property: the stored position IS m2's time — not now(), not m3's.
    if t_crc_stored(th, o) is distinct from t0 - interval '120 seconds'
    then v_bad := v_bad || ' 🔴 the stored position is not the acknowledged message''s time (stored=' || coalesce(t_crc_stored(th, o)::text,'∅') || ')'; end if;
    if (v->>'at')::timestamptz is distinct from t_crc_stored(th, o)
    then v_bad := v_bad || ' the returned value differs from the stored one'; end if;
    if t_crc_unread(o, bk) is distinct from 1
    then v_bad := v_bad || ' 🔴 r-3, which the screen had not drawn, became read (unread=' || coalesce(t_crc_unread(o, bk)::text,'∅') || ', must be 1)'; end if;
    if t_crc_receipt(r, th) is distinct from t0 - interval '120 seconds'
    then v_bad := v_bad || ' the runner''s receipt does not read r-2''s time'; end if;

    -- the divergence control: 0212's writer on the twin, same timeline, disagrees on both numbers.
    v2 := t_crc_mark_legacy(o, th2);
    if v2 ? 'raised' then v_bad := v_bad || ' control (legacy writer) was refused: ' || (v2->>'raised'); end if;
    if t_crc_stored(th2, o) is distinct from t0
    then v_bad := v_bad || ' control: the legacy writer did not write now() — the two rules do not diverge on this fixture'; end if;
    if t_crc_unread(o, bk2) is distinct from 0
    then v_bad := v_bad || ' control: r-3 did not become read under the legacy writer — the fixture does not reproduce the defect'; end if;

    if v_bad = '' then call _pass('crc','0223-C1 the read position is the ACKNOWLEDGED message''s time, not the clock — acknowledging the middle of three runner messages (r-2) stores and returns r-2''s created_at, r-3 (after it, before now(): the message a screen had not drawn yet) stays unread (1), and the runner''s receipt reads r-2''s time. 🔴 On a twin thread with the identical timeline, 0212''s chat_mark_read writes now() and makes r-3 read (unread 0) — that the fixture sits where the two rules diverge is measured inside this pin, not assumed');
    else v_msg := v_bad; call _fail('crc','0223-C1 position is the message''s time', v_msg); end if;
  exception when others then call _fail('crc','0223-C1 position is the message''s time', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0223-M1] monotonic — forward yes, backward never, and the call reports the stored truth
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('crc_m1_o', 'owner');
    r  := t_user('crc_m1_r', 'runner');
    d  := t_dog(o, 'crc-m1');
    rt := t_route('crc route m1');
    select w.bk, w.th into bk, th from t_crc_thread(o, r, d, rt) w;
    m1 := t_crc_msg(th, r, 'r-1', t0 - interval '300 seconds');
    m2 := t_crc_msg(th, r, 'r-2', t0 - interval '200 seconds');
    m3 := t_crc_msg(th, r, 'r-3', t0 - interval '100 seconds');

    -- forward, from no row: 0 → 1, and the position is the newest message's time.
    if t_crc_rows(th) is distinct from 0 then v_bad := v_bad || ' the fixture already holds a read row'; end if;
    v := t_crc_mark_to(o, th, m3);
    if v ? 'raised' then v_bad := v_bad || ' acknowledging the newest message was refused: ' || (v->>'raised'); end if;
    if t_crc_rows(th) is distinct from 1 then v_bad := v_bad || ' the first acknowledgement did not create a row'; end if;
    if t_crc_stored(th, o) is distinct from t0 - interval '100 seconds'
    then v_bad := v_bad || ' the newest acknowledgement''s position is not r-3''s time'; end if;

    -- 🔴 backward: an OLDER message acknowledged afterwards (a slow request overtaken by a fast one).
    v := t_crc_mark_to(o, th, m1);
    if v ? 'raised' then v_bad := v_bad || ' acknowledging an older message was refused (it must be a silent no-op): ' || (v->>'raised'); end if;
    if t_crc_stored(th, o) is distinct from t0 - interval '100 seconds'
    then v_bad := v_bad || ' 🔴 the read position moved backwards (stored=' || coalesce(t_crc_stored(th, o)::text,'∅') || ')'; end if;
    if (v->>'at')::timestamptz is distinct from t0 - interval '100 seconds'
    then v_bad := v_bad || ' the call reported the value it tried to write, not the stored one'; end if;
    if t_crc_unread(o, bk) is distinct from 0
    then v_bad := v_bad || ' after an older acknowledgement, already-read messages became unread again'; end if;

    -- a position planted in the future (③ — the legacy writer's clock can be ahead of any message)
    -- survives a cursor call.
    t_planted := t0 + interval '1 hour';
    update chat_reads set last_read_at = t_planted where thread_id = th and profile_id = o;   -- ③
    v := t_crc_mark_to(o, th, m2);
    if t_crc_stored(th, o) is distinct from t_planted
    then v_bad := v_bad || ' a future position was pushed down by a cursor call'; end if;
    if (v->>'at')::timestamptz is distinct from t_planted
    then v_bad := v_bad || ' the call after a future position does not report the stored value'; end if;
    if t_crc_rows(th) is distinct from 1 then v_bad := v_bad || ' two rows exist for one (thread, person)'; end if;

    if v_bad = '' then call _pass('crc','0223-M1 the read position only moves forward — the first acknowledgement from no row creates it (0→1 delta) at the newest message''s time (r-3); an OLDER message (r-1) acknowledged afterwards leaves it where it was and reports the stored r-3 time (a slow request overtaken by a fast one: already-read messages never become unread again); a future position planted by the legacy writer is not pushed down by a cursor call; one row throughout');
    else v_msg := v_bad; call _fail('crc','0223-M1 monotonic', v_msg); end if;
  exception when others then call _fail('crc','0223-M1 monotonic', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0223-G1] the party gate is first, and it is not an oracle for threads OR messages
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('crc_g1_o', 'owner');
    r  := t_user('crc_g1_r', 'runner');
    d  := t_dog(o, 'crc-g1');
    rt := t_route('crc route g1');
    stranger := t_user('crc_g1_x', 'owner');
    select w.bk, w.th into bk, th from t_crc_thread(o, r, d, rt) w;
    m1 := t_crc_msg(th, r, 'r-1', t0 - interval '60 seconds');

    if t_crc_rows(th) is distinct from 0 then v_bad := v_bad || ' the fixture already holds a read row'; end if;

    v  := t_crc_mark_to(stranger, th, m1);                          -- real thread, real message
    v2 := t_crc_mark_to(stranger, th, -1);                          -- real thread, no such message
    v3 := t_crc_mark_to(stranger, gen_random_uuid(), m1);           -- no such thread, real message
    if coalesce(v->>'raised','') not like '%not_party%'
    then v_bad := v_bad || ' the stranger does not get not_party (' || coalesce(v::text,'∅') || ')'; end if;
    if (v->>'raised') is distinct from (v2->>'raised') or (v->>'raised') is distinct from (v3->>'raised')
    then v_bad := v_bad || ' 🔴 the refusal is an oracle — its word depends on whether the message/thread exists ('
                        || coalesce(v->>'raised','∅') || ' / ' || coalesce(v2->>'raised','∅') || ' / ' || coalesce(v3->>'raised','∅') || ')'; end if;

    v4 := t_crc_mark_to(null, th, m1);
    if coalesce(v4->>'raised','') not like '%not_authenticated%'
    then v_bad := v_bad || ' the anonymous call is not not_authenticated (' || coalesce(v4::text,'∅') || ')'; end if;

    -- 🔴 GATE BEFORE THE WRITE, measured.
    if t_crc_rows(th) is distinct from 0
    then v_bad := v_bad || ' 🔴 a refused call left a read row (' || t_crc_rows(th)::text || ')'; end if;

    -- the control that the refusals are about identity: the party succeeds.
    v := t_crc_mark_to(o, th, m1);
    if v ? 'raised' then v_bad := v_bad || ' the party (owner) was refused: ' || (v->>'raised'); end if;
    if t_crc_rows(th) is distinct from 1 then v_bad := v_bad || ' the party''s call did not create a row'; end if;

    if v_bad = '' then call _pass('crc','0223-G1 the party gate is first and is an oracle for neither threads nor messages — a stranger gets the IDENTICAL word (not_party) for (real thread, real message), (real thread, missing message) and (missing thread, real message), so the refusal says nothing about whether a message id exists or where it lives; anonymous gets not_authenticated. 🔴 After the four refused calls chat_reads holds 0 rows for the thread and the party''s one call makes it 1 — gate BEFORE the write, measured');
    else v_msg := v_bad; call _fail('crc','0223-G1 party gate first', v_msg); end if;
  exception when others then call _fail('crc','0223-G1 party gate first', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0223-X1] the cursor must name a COUNTERPART's message in THIS thread — one token per question
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('crc_x1_o', 'owner');
    r  := t_user('crc_x1_r', 'runner');
    d  := t_dog(o, 'crc-x1');
    rt := t_route('crc route x1');
    select w.bk, w.th into bk,  th  from t_crc_thread(o, r, d, rt) w;
    select w.bk, w.th into bk2, th2 from t_crc_thread(o, r, d, rt) w;     -- the owner's OTHER thread
    o2 := t_user('crc_x1_o2', 'owner');
    r2 := t_user('crc_x1_r2', 'runner');
    d2 := t_dog(o2, 'crc-x1b');
    select w.bk, w.th into bk3, th3 from t_crc_thread(o2, r2, d2, rt) w;  -- a thread the owner is a stranger to

    m1        := t_crc_msg(th,  r,  'r-1',   t0 - interval '60 seconds');
    m_own     := t_crc_msg(th,  o,  'o-1',   t0 - interval '30 seconds');
    m_other   := t_crc_msg(th2, r,  'r-2nd', t0 - interval '20 seconds');
    m_foreign := t_crc_msg(th3, r2, 'x-1',   t0 - interval '10 seconds');

    v  := t_crc_mark_to(o, th, m_other);      -- (a) a message of the caller's OTHER thread
    v2 := t_crc_mark_to(o, th, m_foreign);    -- (b) a message of a thread the caller is a stranger to
    v3 := t_crc_mark_to(o, th, -1);           -- (c) no such message
    v4 := t_crc_mark_to(o, th, null);         -- (d) NULL
    if coalesce(v->>'raised','') not like '%not_in_thread%'
    then v_bad := v_bad || ' a message of another thread is not not_in_thread (' || coalesce(v::text,'∅') || ')'; end if;
    if (v->>'raised') is distinct from (v2->>'raised')
       or (v->>'raised') is distinct from (v3->>'raised')
       or (v->>'raised') is distinct from (v4->>'raised')
    then v_bad := v_bad || ' 🔴 the four out-of-thread cases do not get one word — other threads'' ids can be probed ('
                        || coalesce(v->>'raised','∅') || ' / ' || coalesce(v2->>'raised','∅') || ' / '
                        || coalesce(v3->>'raised','∅') || ' / ' || coalesce(v4->>'raised','∅') || ')'; end if;

    v := t_crc_mark_to(o, th, m_own);         -- (e) the caller's own message
    if coalesce(v->>'raised','') not like '%not_peer_message%'
    then v_bad := v_bad || ' acknowledging one''s own message is not not_peer_message (' || coalesce(v::text,'∅') || ')'; end if;

    if t_crc_rows(th) is distinct from 0 or t_crc_rows(th2) is distinct from 0 or t_crc_rows(th3) is distinct from 0
    then v_bad := v_bad || ' 🔴 a refused call left a read row'; end if;

    -- the control: a real counterpart message of this thread is accepted, and lands on its own time.
    v := t_crc_mark_to(o, th, m1);
    if v ? 'raised' then v_bad := v_bad || ' a counterpart message of this thread was refused: ' || (v->>'raised'); end if;
    if t_crc_stored(th, o) is distinct from t0 - interval '60 seconds'
    then v_bad := v_bad || ' the counterpart acknowledgement''s position is not that message''s time'; end if;
    if t_crc_rows(th2) is distinct from 0 then v_bad := v_bad || ' an acknowledgement in one thread wrote a row in another'; end if;

    if v_bad = '' then call _pass('crc','0223-X1 the cursor must name a COUNTERPART message of THIS thread, one word per question — a party of two threads sending (a) a message of their other thread, (b) a message of a thread they are a stranger to, (c) a missing id, (d) NULL gets the IDENTICAL not_in_thread four times (no probing other threads'' ids); their own message gets not_peer_message. None of the five writes a row; a real counterpart message of this thread is accepted and lands on its own time, and nothing is written to the other thread');
    else v_msg := v_bad; call _fail('crc','0223-X1 cursor names a peer message of this thread', v_msg); end if;
  exception when others then call _fail('crc','0223-X1 cursor names a peer message of this thread', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0223-F1] a future-dated message cannot drag the position past the server's clock
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('crc_f1_o', 'owner');
    r  := t_user('crc_f1_r', 'runner');
    d  := t_dog(o, 'crc-f1');
    rt := t_route('crc route f1');
    select w.bk, w.th into bk, th from t_crc_thread(o, r, d, rt) w;
    -- ③ of 0223 §0d: a client wrote this row's created_at itself.
    m_future := t_crc_msg(th, r, 'from-tomorrow', t0 + interval '1 day');

    v := t_crc_mark_to(o, th, m_future);
    if v ? 'raised' then v_bad := v_bad || ' acknowledging a future-dated message was refused: ' || (v->>'raised'); end if;
    if t_crc_stored(th, o) is distinct from t0
    then v_bad := v_bad || ' 🔴 the stored position is not the server clock now() (stored=' || coalesce(t_crc_stored(th, o)::text,'∅') || ')'; end if;
    if (t_crc_stored(th, o) <= t0) is not true
    then v_bad := v_bad || ' 🔴 the position is later than the server clock'; end if;

    -- the arm that makes it mean something: the peer speaks AFTER the acknowledgement (before
    -- tomorrow). An unclamped position (tomorrow) would have silenced it.
    perform t_crc_msg(th, r, 'an-hour-later', t0 + interval '1 hour');
    v_n := t_crc_unread(o, bk);
    if v_n is distinct from 2
    then v_bad := v_bad || ' a counterpart message sent after the acknowledgement is not counted unread (unread=' || coalesce(v_n::text,'∅') || ', must be 2: the message an hour later + the one dated tomorrow)'; end if;

    if v_bad = '' then call _pass('crc','0223-F1 a future-dated message cannot drag the position past the server clock — chat_messages.created_at is client-writable today (0223 §0d ③); acknowledging a message dated tomorrow stores now(), not tomorrow. The arm that gives it meaning: a counterpart message sent AFTER the acknowledgement (before tomorrow) is counted unread (2) — an unclamped position (tomorrow) would have silently made it read');
    else v_msg := v_bad; call _fail('crc','0223-F1 future clamp', v_msg); end if;
  exception when others then call _fail('crc','0223-F1 future clamp', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0223-S1] deployed shape
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';

    if (select count(*) from pg_proc p
         where p.pronamespace = 'public'::regnamespace and p.proname = 'chat_mark_read_to'
           and p.prosecdef and 'search_path=public, pg_temp' = any (p.proconfig)) is distinct from 1
    then v_bad := v_bad || ' prosecdef / in-body search_path shape broken (or the function is absent)'; end if;

    if (select pg_get_function_identity_arguments(p.oid) from pg_proc p
         where p.pronamespace = 'public'::regnamespace and p.proname = 'chat_mark_read_to')
       is distinct from 'p_thread uuid, p_up_to_message_id bigint'
    then v_bad := v_bad || ' the argument list differs from what the client sends'; end if;

    if (select pg_get_function_result(p.oid) from pg_proc p
         where p.pronamespace = 'public'::regnamespace and p.proname = 'chat_mark_read_to')
       is distinct from 'TABLE(last_read_at timestamp with time zone)'
    then v_bad := v_bad || ' the return shape is not the single last_read_at column'; end if;

    -- ACL both ways — the negative alone is satisfied by a function nobody can call.
    if (has_function_privilege('public', 'chat_mark_read_to(uuid,bigint)', 'execute')
     or has_function_privilege('anon',   'chat_mark_read_to(uuid,bigint)', 'execute')) is not false
    then v_bad := v_bad || ' PUBLIC/anon can execute'; end if;
    if has_function_privilege('authenticated', 'chat_mark_read_to(uuid,bigint)', 'execute') is not true
    then v_bad := v_bad || ' authenticated cannot call'; end if;

    select p.prosrc, regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
      into v_raw, v_src
      from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'chat_mark_read_to';
    if v_src is null then v_bad := v_bad || ' NO-SOURCE(chat_mark_read_to)';
    else
      -- 🔴 TWO-SIDED CONTROL THAT THE STRIPPER RAN. `NULL predicate` appears ONLY in this body's
      --    prose; if it survives stripping, every arm below is reading documentation.
      if (position('NULL predicate' in v_raw) > 0) is not true
      then v_bad := v_bad || ' the comment-control string is absent from the raw body — the stripper control is vacuous'; end if;
      if (position('NULL predicate' in v_src) > 0) is not false
      then v_bad := v_bad || ' comments were not stripped — the arms below would be measuring prose, not code'; end if;
      if (position('is_booking_party(' in v_src) > 0
          and position('is_booking_party(' in v_src) < position('from chat_messages' in v_src)
          and position('is_booking_party(' in v_src) < position('insert into chat_reads' in v_src))
         is not true
      then v_bad := v_bad || ' the party gate is gone or sits after the message read / the write'; end if;
      if (v_src ~ 'm\.thread_id\s*=\s*p_thread') is not true
      then v_bad := v_bad || ' the message lookup is not scoped to this thread'; end if;
      if (v_src ~ 'greatest\s*\(\s*c\.last_read_at\s*,\s*excluded\.last_read_at\s*\)') is not true
      then v_bad := v_bad || ' the monotonic guard (greatest) is gone'; end if;
      if (v_src ~ 'least\s*\(\s*v_at\s*,\s*now\(\)\s*\)') is not true
      then v_bad := v_bad || ' the future clamp is gone'; end if;
    end if;

    if v_bad = '' then call _pass('crc','0223-S1 deployed shape — chat_mark_read_to is prosecdef + in-body search_path, arguments (p_thread uuid, p_up_to_message_id bigint) exactly as the client sends them, returns the single last_read_at column; PUBLIC/anon cannot execute, authenticated can (both ways); in the comment-stripped body the party gate precedes BOTH the first chat_messages read and the chat_reads write, the message lookup is scoped to this thread, and greatest (monotonic) and least(…, now()) (future clamp) are present. NO-SOURCE arm + a two-sided control that the stripper ran');
    else v_msg := v_bad; call _fail('crc','0223-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('crc','0223-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);
end $$;
