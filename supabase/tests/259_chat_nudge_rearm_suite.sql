-- ═══ 259 — 0228: a covering chat read re-arms the 「새 메시지」 push
-- ═══        0228-R1 · O1 · O2 · P1 · L1 · S1, tag `cnr`
--
-- THE PROPOSITIONS THIS FILE OWNS, each stated without reference to any mutation (the mid-battery
-- law — a pin written while staring at a mutation asserts what that mutation broke).
--
--   · R1 **A READ THAT COVERS EVERY COUNTERPART MESSAGE RE-ARMS THE PUSH.** Two runner messages
--        leave the owner ONE unread nudge (0090's dedupe — observed, not assumed); the owner's
--        `chat_mark_read_to` up to the newest runner message takes the unread count 1 → 0, and the
--        runner's NEXT message writes a second nudge row (rows 1 → 2, unread 0 → 1). 🔴 The
--        attribution control is a twin thread where the owner does NOT read: its third message
--        writes nothing (rows stay 1) — so the second row in the main thread is caused by the
--        read, not by the fixture.
--   · O1 **A READ UP TO AN OLDER MESSAGE, WHILE A NEWER COUNTERPART MESSAGE EXISTS, KEEPS THE
--        NUDGE.** The read position still advances (the read is recorded); the nudge stays unread
--        (it is the newer message's only phone signal), a further runner message still writes no
--        second row, and a covering read on the SAME thread then releases it (the control that the
--        withholding is about coverage, not about this thread).
--   · O2 **THE READER'S OWN LATER MESSAGE DOES NOT HOLD THE NUDGE.** Covering is about the
--        COUNTERPART's messages (`sender_id is distinct from` the reader, `my_chat_unread`'s own
--        exclusion). The owner's reply, dated after the runner message they acknowledge, does not
--        keep their nudge unread.
--   · P1 **THE RELEASE IS EXACTLY 0090's DEDUPE PREDICATE — no other person, booking or title.**
--        One covering read by the owner on booking A: the owner's A-nudge is released; the owner's
--        B-nudge (same parties, other booking), the RUNNER's A-nudge (same booking, other person)
--        and the owner's A-row under another title all stay unread — each present and unread
--        BEFORE the read, so every absence is measured against a presence.
--   · L1 **0212's LEGACY WRITER RE-ARMS TOO.** `chat_mark_read(p_thread)` releases the nudge and
--        the next message writes a second row — the path a build older than 0223's client takes.
--   · S1 **DEPLOYED SHAPE.** Both writers: `prosecdef`, in-body `search_path`, argument lists, ACL
--        both ways; in the COMMENT-STRIPPED body the release sits below the party gate, carries 0090's
--        four conjuncts and the covering test; a NO-SOURCE arm per function and a two-sided control
--        that the stripper ran.
--
-- ─── WHAT THIS SUITE DOES NOT PROVE (prose — the harness cannot reach it) ───
--   · That a REFUSED call releases nothing. Every refusal is a raise, and a raise rolls back the
--     statement — so an arm asserting it would stay green even with the release moved ahead of the
--     gate (the tell: no mutation reddens it). The ORDER is asserted structurally in S1 instead.
--   · 0228 §0d ① — the commit-order race between a sender's trigger and this UPDATE. A single
--     session cannot interleave two commits; a pin for it would be green by construction.
--   · The push itself (`00_shim.sql` stubs `net.http_post`) and the client's OS-push tap path
--     (`push.ts` → `markNotificationsReadByTap`), which no SQL pin can see.
--
-- ─── FIXTURE NOTES ───
--  ① `request.jwt.claim.sub` is set and cleared inside every helper and cleared again at the end.
--  ② Messages are inserted as `postgres` with EXPLICIT `created_at` values before `now()`: the DO
--     block is one transaction, so default-dated rows would all share one instant (254's note ②),
--     and 0225's stamp leaves a non-RLS writer's value alone. The nudge rows are written by the
--     REAL `chat_messages_notify` trigger — no pin inserts a `새 메시지` row by hand.
set client_min_messages = warning;

create or replace function t_cnr_thread(p_owner uuid, p_runner uuid, p_dog uuid, p_route uuid,
                                        out bk uuid, out th uuid)
language plpgsql as $$
begin
  insert into bookings (owner_id, dog_id, runner_id, route_id, status, scheduled_at, km,
                        base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (p_owner, p_dog, p_runner, p_route, 'confirmed', now(), 5.0, 9900, 15000, 0, 24900, 9900)
  returning id into bk;
  insert into chat_threads (booking_id) values (bk) returning id into th;
end $$;

create or replace function t_cnr_msg(p_thread uuid, p_sender uuid, p_body text, p_at timestamptz)
returns bigint language sql as $$
  insert into chat_messages (thread_id, sender_id, body, created_at)
  values (p_thread, p_sender, p_body, p_at)
  returning id
$$;

create or replace function t_cnr_mark_to(p_uid uuid, p_thread uuid, p_msg bigint) returns jsonb
language plpgsql as $$
declare v timestamptz;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
  select m.last_read_at into v from chat_mark_read_to(p_thread, p_msg) m;
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('at', v);
exception when others then
  perform set_config('request.jwt.claim.sub', '', true);
  return jsonb_build_object('raised', sqlerrm);
end $$;

create or replace function t_cnr_mark_legacy(p_uid uuid, p_thread uuid) returns jsonb
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

-- 「새 메시지」 rows addressed to p_uid for booking p_bk — all of them, or only the unread ones.
create or replace function t_cnr_nudges(p_uid uuid, p_bk uuid, p_unread_only boolean) returns int
language sql as $$
  select count(*)::int from notifications n
   where n.profile_id = p_uid and n.ref_id = p_bk and n.title = '새 메시지'
     and (not p_unread_only or n.read_at is null)
$$;

create or replace function t_cnr_stored(p_thread uuid, p_uid uuid) returns timestamptz
language sql as $$
  select c.last_read_at from chat_reads c where c.thread_id = p_thread and c.profile_id = p_uid
$$;

do $$
declare
  o uuid; r uuid; d uuid; rt uuid;
  bk uuid; th uuid; bk2 uuid; th2 uuid;
  m1 bigint; m2 bigint; m3 bigint; m_own bigint;
  v jsonb; v_bad text; v_msg text; v_n int;
  v_src text; v_raw text; v_fn text;
  t0 timestamptz;
begin
  perform set_config('request.jwt.claim.sub', '', true);                                       -- ①
  t0 := now();

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0228-R1] a covering read re-arms the push — the reproduction, attributed by a twin
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('cnr_r1_o', 'owner');
    r  := t_user('cnr_r1_r', 'runner');
    d  := t_dog(o, 'cnr-r1');
    rt := t_route('cnr route r1');
    select w.bk, w.th into bk,  th  from t_cnr_thread(o, r, d, rt) w;
    select w.bk, w.th into bk2, th2 from t_cnr_thread(o, r, d, rt) w;                       -- the twin

    m1 := t_cnr_msg(th, r, 'r-1', t0 - interval '300 seconds');
    if t_cnr_nudges(o, bk, false) is distinct from 1 or t_cnr_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' fixture: the first runner message did not leave exactly one unread nudge (the trigger is not writing)'; end if;
    m2 := t_cnr_msg(th, r, 'r-2', t0 - interval '200 seconds');
    if t_cnr_nudges(o, bk, false) is distinct from 1
    then v_bad := v_bad || ' fixture: a second message while the nudge is unread wrote a row (0090''s dedupe is not in force — nothing here would be measured)'; end if;

    -- 🔴 the property: the covering read releases the nudge …
    v := t_cnr_mark_to(o, th, m2);
    if v ? 'raised' then v_bad := v_bad || ' the covering read was refused: ' || (v->>'raised'); end if;
    if t_cnr_nudges(o, bk, true) is distinct from 0
    then v_bad := v_bad || ' 🔴 the covering read left the nudge unread (unread=' || coalesce(t_cnr_nudges(o, bk, true)::text,'∅') || ', must be 0)'; end if;
    if (select n.read_at from notifications n
         where n.profile_id = o and n.ref_id = bk and n.title = '새 메시지') is distinct from t0
    then v_bad := v_bad || ' the released nudge''s read_at is not the read''s now()'; end if;
    -- … and the next message pushes again.
    m3 := t_cnr_msg(th, r, 'r-3', t0 - interval '100 seconds');
    if t_cnr_nudges(o, bk, false) is distinct from 2 or t_cnr_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' 🔴 the message after the read wrote no new nudge (rows=' || coalesce(t_cnr_nudges(o, bk, false)::text,'∅') || ', must be 2 with 1 unread)'; end if;

    -- the attribution control: the same three messages with NO read — the third is silent.
    perform t_cnr_msg(th2, r, 'r-1', t0 - interval '300 seconds');
    perform t_cnr_msg(th2, r, 'r-2', t0 - interval '200 seconds');
    perform t_cnr_msg(th2, r, 'r-3', t0 - interval '100 seconds');
    if t_cnr_nudges(o, bk2, false) is distinct from 1 or t_cnr_nudges(o, bk2, true) is distinct from 1
    then v_bad := v_bad || ' control: without a read the twin did not stay at ONE unread nudge — the second row above is not attributable to the read'; end if;

    if v_bad = '' then call _pass('cnr','0228-R1 a read that covers every counterpart message re-arms the push — two runner messages leave ONE unread nudge (0090''s dedupe, observed), chat_mark_read_to up to the newest takes unread 1→0 with read_at = the read''s now(), and the NEXT runner message writes a second row (rows 1→2, unread 0→1). 🔴 A twin thread with the same three messages and no read stays at one row — the second row is caused by the read');
    else v_msg := v_bad; call _fail('cnr','0228-R1 covering read re-arms the push', v_msg); end if;
  exception when others then call _fail('cnr','0228-R1 covering read re-arms the push', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0228-O1] a read up to an OLDER message, with a newer counterpart message, keeps the nudge
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('cnr_o1_o', 'owner');
    r  := t_user('cnr_o1_r', 'runner');
    d  := t_dog(o, 'cnr-o1');
    rt := t_route('cnr route o1');
    select w.bk, w.th into bk, th from t_cnr_thread(o, r, d, rt) w;
    m1 := t_cnr_msg(th, r, 'r-1', t0 - interval '300 seconds');
    m2 := t_cnr_msg(th, r, 'r-2', t0 - interval '200 seconds');
    if t_cnr_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' fixture: no unread nudge before the read'; end if;

    v := t_cnr_mark_to(o, th, m1);                                   -- r-2 is newer and undrawn
    if v ? 'raised' then v_bad := v_bad || ' the older acknowledgement was refused: ' || (v->>'raised'); end if;
    if t_cnr_stored(th, o) is distinct from t0 - interval '300 seconds'
    then v_bad := v_bad || ' the read itself was not recorded at r-1''s time (the withholding must not cost the read)'; end if;
    if t_cnr_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' 🔴 a read up to r-1 released the nudge while r-2 (newer, undrawn) exists'; end if;
    m3 := t_cnr_msg(th, r, 'r-3', t0 - interval '100 seconds');
    if t_cnr_nudges(o, bk, false) is distinct from 1
    then v_bad := v_bad || ' a further message wrote a second row while the nudge was (correctly) held'; end if;

    -- the control on the SAME thread: a covering read releases it.
    v := t_cnr_mark_to(o, th, m3);
    if v ? 'raised' then v_bad := v_bad || ' control: the covering read was refused: ' || (v->>'raised'); end if;
    if t_cnr_nudges(o, bk, true) is distinct from 0
    then v_bad := v_bad || ' control: a covering read on the same thread did not release the nudge — the withholding above is not about coverage'; end if;

    if v_bad = '' then call _pass('cnr','0228-O1 a read up to an OLDER message while a newer counterpart message exists keeps the nudge — acknowledging r-1 with r-2 present records the position at r-1 but leaves the nudge unread (r-2''s only phone signal) and a further message still writes no second row; acknowledging the newest (r-3) on the same thread then releases it (the withholding is about coverage)');
    else v_msg := v_bad; call _fail('cnr','0228-O1 older acknowledgement keeps the nudge', v_msg); end if;
  exception when others then call _fail('cnr','0228-O1 older acknowledgement keeps the nudge', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0228-O2] the reader's own later message does not hold the nudge
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('cnr_o2_o', 'owner');
    r  := t_user('cnr_o2_r', 'runner');
    d  := t_dog(o, 'cnr-o2');
    rt := t_route('cnr route o2');
    select w.bk, w.th into bk, th from t_cnr_thread(o, r, d, rt) w;
    m1    := t_cnr_msg(th, r, 'r-1',   t0 - interval '300 seconds');
    m_own := t_cnr_msg(th, o, 'reply', t0 - interval '200 seconds');     -- AFTER r-1, the owner's own
    if t_cnr_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' fixture: the owner has no unread nudge'; end if;

    v := t_cnr_mark_to(o, th, m1);
    if v ? 'raised' then v_bad := v_bad || ' the read was refused: ' || (v->>'raised'); end if;
    if t_cnr_nudges(o, bk, true) is distinct from 0
    then v_bad := v_bad || ' 🔴 the owner''s OWN later message kept their nudge unread'; end if;

    if v_bad = '' then call _pass('cnr','0228-O2 the reader''s own later message does not hold the nudge — the owner''s reply, dated after the runner message they acknowledge, does not keep their nudge unread (covering is about COUNTERPART messages, my_chat_unread''s own exclusion)');
    else v_msg := v_bad; call _fail('cnr','0228-O2 own message does not hold the nudge', v_msg); end if;
  exception when others then call _fail('cnr','0228-O2 own message does not hold the nudge', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0228-P1] the release is 0090's dedupe predicate — no other person, booking or title
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('cnr_p1_o', 'owner');
    r  := t_user('cnr_p1_r', 'runner');
    d  := t_dog(o, 'cnr-p1');
    rt := t_route('cnr route p1');
    select w.bk, w.th into bk,  th  from t_cnr_thread(o, r, d, rt) w;                       -- booking A
    select w.bk, w.th into bk2, th2 from t_cnr_thread(o, r, d, rt) w;                       -- booking B
    perform t_cnr_msg(th, o, 'o-1', t0 - interval '400 seconds');          -- → the RUNNER's A-nudge
    m1 := t_cnr_msg(th, r, 'r-1', t0 - interval '300 seconds');            -- → the owner's A-nudge
    perform t_cnr_msg(th2, r, 'r-b', t0 - interval '300 seconds');         -- → the owner's B-nudge
    insert into notifications (profile_id, kind, title, body, ref_id)      -- another title, same A
    values (o, 'booking', '러너 도착', '러너가 픽업 장소에 도착했어요 — 인계를 준비해주세요', bk);

    -- every row the read must NOT touch is present and unread first (an absence needs a presence)
    if t_cnr_nudges(o, bk, true) is distinct from 1 then v_bad := v_bad || ' fixture: owner A-nudge'; end if;
    if t_cnr_nudges(o, bk2, true) is distinct from 1 then v_bad := v_bad || ' fixture: owner B-nudge'; end if;
    if t_cnr_nudges(r, bk, true) is distinct from 1 then v_bad := v_bad || ' fixture: runner A-nudge'; end if;
    if (select count(*) from notifications n where n.profile_id = o and n.ref_id = bk
          and n.title = '러너 도착' and n.read_at is null) is distinct from 1
    then v_bad := v_bad || ' fixture: owner A other-title row'; end if;

    v := t_cnr_mark_to(o, th, m1);
    if v ? 'raised' then v_bad := v_bad || ' the read was refused: ' || (v->>'raised'); end if;
    if t_cnr_nudges(o, bk, true) is distinct from 0
    then v_bad := v_bad || ' control: the owner''s own A-nudge was not released'; end if;
    if t_cnr_nudges(o, bk2, true) is distinct from 1
    then v_bad := v_bad || ' 🔴 the owner''s nudge for ANOTHER booking was released'; end if;
    if t_cnr_nudges(r, bk, true) is distinct from 1
    then v_bad := v_bad || ' 🔴 the RUNNER''s nudge for this booking was released by the owner''s read'; end if;
    if (select count(*) from notifications n where n.profile_id = o and n.ref_id = bk
          and n.title = '러너 도착' and n.read_at is null) is distinct from 1
    then v_bad := v_bad || ' 🔴 a row under another title was released'; end if;

    if v_bad = '' then call _pass('cnr','0228-P1 the release is exactly 0090''s dedupe predicate — one covering read by the owner on booking A releases the owner''s A-nudge and nothing else: the owner''s B-nudge (other booking), the RUNNER''s A-nudge (other person) and the owner''s A-row titled 러너 도착 (other title) all stay unread, each observed present and unread before the read');
    else v_msg := v_bad; call _fail('cnr','0228-P1 release scope', v_msg); end if;
  exception when others then call _fail('cnr','0228-P1 release scope', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0228-L1] 0212's legacy writer re-arms too
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    o  := t_user('cnr_l1_o', 'owner');
    r  := t_user('cnr_l1_r', 'runner');
    d  := t_dog(o, 'cnr-l1');
    rt := t_route('cnr route l1');
    select w.bk, w.th into bk, th from t_cnr_thread(o, r, d, rt) w;
    perform t_cnr_msg(th, r, 'r-1', t0 - interval '300 seconds');
    perform t_cnr_msg(th, r, 'r-2', t0 - interval '200 seconds');
    if t_cnr_nudges(o, bk, false) is distinct from 1 or t_cnr_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' fixture: not exactly one unread nudge before the read'; end if;

    v := t_cnr_mark_legacy(o, th);
    if v ? 'raised' then v_bad := v_bad || ' the legacy read was refused: ' || (v->>'raised'); end if;
    if t_cnr_nudges(o, bk, true) is distinct from 0
    then v_bad := v_bad || ' 🔴 0212''s chat_mark_read left the nudge unread'; end if;
    perform t_cnr_msg(th, r, 'r-3', t0 - interval '100 seconds');
    if t_cnr_nudges(o, bk, false) is distinct from 2 or t_cnr_nudges(o, bk, true) is distinct from 1
    then v_bad := v_bad || ' 🔴 the message after the legacy read wrote no new nudge'; end if;

    if v_bad = '' then call _pass('cnr','0228-L1 0212''s legacy chat_mark_read re-arms too — it releases the unread nudge (1→0) and the next runner message writes a second row (rows 1→2) — the path a build older than 0223''s client takes');
    else v_msg := v_bad; call _fail('cnr','0228-L1 legacy writer re-arms', v_msg); end if;
  exception when others then call _fail('cnr','0228-L1 legacy writer re-arms', sqlerrm); end;

  -- ══════════════════════════════════════════════════════════════════════════════════════════
  -- [0228-S1] deployed shape, both writers
  -- ══════════════════════════════════════════════════════════════════════════════════════════
  begin
    v_bad := '';
    if (select count(*) from pg_proc p
         where p.pronamespace = 'public'::regnamespace
           and p.proname in ('chat_mark_read_to', 'chat_mark_read')
           and p.prosecdef and 'search_path=public, pg_temp' = any (p.proconfig)) is distinct from 2
    then v_bad := v_bad || ' prosecdef / in-body search_path shape broken (or a function is absent)'; end if;
    if (select pg_get_function_identity_arguments(p.oid) from pg_proc p
         where p.pronamespace = 'public'::regnamespace and p.proname = 'chat_mark_read_to')
       is distinct from 'p_thread uuid, p_up_to_message_id bigint'
    then v_bad := v_bad || ' chat_mark_read_to arguments changed'; end if;
    if (select pg_get_function_identity_arguments(p.oid) from pg_proc p
         where p.pronamespace = 'public'::regnamespace and p.proname = 'chat_mark_read')
       is distinct from 'p_thread uuid'
    then v_bad := v_bad || ' chat_mark_read arguments changed'; end if;

    -- ACL both ways — the negative alone is satisfied by a function nobody can call.
    if (has_function_privilege('public', 'chat_mark_read_to(uuid,bigint)', 'execute')
     or has_function_privilege('anon',   'chat_mark_read_to(uuid,bigint)', 'execute')
     or has_function_privilege('public', 'chat_mark_read(uuid)', 'execute')
     or has_function_privilege('anon',   'chat_mark_read(uuid)', 'execute')) is not false
    then v_bad := v_bad || ' PUBLIC/anon can execute a writer'; end if;
    if (has_function_privilege('authenticated', 'chat_mark_read_to(uuid,bigint)', 'execute')
        and has_function_privilege('authenticated', 'chat_mark_read(uuid)', 'execute')) is not true
    then v_bad := v_bad || ' authenticated cannot call a writer'; end if;

    foreach v_fn in array array['chat_mark_read_to', 'chat_mark_read'] loop
      select p.prosrc, regexp_replace(p.prosrc, '--[^' || chr(10) || ']*', '', 'g')
        into v_raw, v_src
        from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = v_fn;
      if v_src is null then v_bad := v_bad || ' NO-SOURCE(' || v_fn || ')'; continue; end if;
      -- 🔴 TWO-SIDED CONTROL THAT THE STRIPPER RAN. `RE-ARM THE CHAT NUDGE` appears ONLY in the
      --    0228 comment inside each body; if it survives stripping, the arms below read prose.
      if (position('RE-ARM THE CHAT NUDGE' in v_raw) > 0) is not true
      then v_bad := v_bad || ' ' || v_fn || ': the comment-control string is absent from the raw body — the stripper control is vacuous'; end if;
      if (position('RE-ARM THE CHAT NUDGE' in v_src) > 0) is not false
      then v_bad := v_bad || ' ' || v_fn || ': comments were not stripped'; end if;
      if (position('is_booking_party(' in v_src) > 0
          and position('update notifications' in v_src) > position('is_booking_party(' in v_src))
         is not true
      then v_bad := v_bad || ' ' || v_fn || ': the release is gone or sits above the party gate'; end if;
      if (v_src ~ 'n\.profile_id\s*=\s*v_uid' and v_src ~ 'n\.ref_id\s*=\s*v_booking'
          and v_src ~ 'n\.title\s*=\s*''새 메시지''' and v_src ~ 'n\.read_at\s+is\s+null') is not true
      then v_bad := v_bad || ' ' || v_fn || ': the release no longer carries 0090''s four conjuncts'; end if;
      if (v_src ~ 'not\s+exists\s*\(\s*select\s+1\s+from\s+chat_messages\s+m'
          and v_src ~ 'm\.sender_id\s+is\s+distinct\s+from\s+v_uid'
          and v_src ~ 'm\.created_at\s*>\s*v_at') is not true
      then v_bad := v_bad || ' ' || v_fn || ': the covering test is gone or changed'; end if;
    end loop;

    if v_bad = '' then call _pass('cnr','0228-S1 deployed shape — chat_mark_read_to and chat_mark_read are prosecdef + in-body search_path with the argument lists the clients send; PUBLIC/anon cannot execute either, authenticated can (both ways); in each COMMENT-STRIPPED body the notifications release sits below the party gate, carries 0090''s four conjuncts (profile_id, ref_id, 새 메시지, read_at is null) and the covering test (not exists a counterpart message after v_at). NO-SOURCE arm per function + a two-sided stripper control');
    else v_msg := v_bad; call _fail('cnr','0228-S1 deployed shape', v_msg); end if;
  exception when others then call _fail('cnr','0228-S1 deployed shape', sqlerrm); end;

  perform set_config('request.jwt.claim.sub', '', true);                                       -- ①
end $$;
