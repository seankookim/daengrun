-- ═══ 126 chat-notify suite — 0090 pins (⑬ chat reaches a phone) ═══
-- Purpose: push fires only on a `notifications` insert (0024:43), and until 0090 nothing wrote
--   one when a chat message was sent — so the channel both parties reach for when something
--   unexpected happens was the one that did not ring. These pins hold the four properties a
--   naive version of this trigger gets wrong: the recipient, the sender's silence, the
--   anti-storm rule, and the fact that no message text ever leaves for the lock screen.
-- Style: sibling of 105-125 — `_pass('cn',…)`/`_fail('cn',…)`, one begin…exception per case.
--   ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).
--
-- ─── WHAT THIS SUITE DOES NOT PROVE ───
--   · The push itself. `00_shim.sql` stubs `net.http_post`, so what is pinned is that the ROW
--     is written — the row→push step is 0024's, pinned by its own suite. A broken Expo token
--     or a revoked push permission is invisible here and always will be.
--   · The title string as a ROUTING key. `_test/chat_notify_contract_test.ts` reads 0090 at
--     test time and cross-checks push.ts's literal in both directions; SQL cannot see the
--     client, so a rename caught there is not caught here.
--
-- ─── MUTATION map — each pin goes RED under exactly one named revert ───
--   N1 ← 0090: send to the sender instead of the other party, or drop the sender guard  → RED
--   N2 ← 0090: drop the unread check (a back-and-forth then pushes per message)         → RED
--   N3 ← 0090: put `new.body` into the notification body (the lock-screen leak)         → RED
--   N4 ← 0090: notify on an unmatched booking (runner_id null → nobody to tell)         → RED
do $$
declare
  oo uuid; rr uuid; dg uuid; rt uuid;
  bk uuid; bk2 uuid; th uuid; th2 uuid;
  v_bad text := ''; v_msg text; v_n int; v_body text; v_title text;
begin
  oo := t_user('cn_oo', 'owner');
  rr := t_user('cn_rr', 'runner');
  dg := t_dog(oo, '채팅견'); rt := t_route('채팅 코스');
  bk := t_chg_bk(oo, dg, rt, rr, 'confirmed', now() + interval '2 hours', 3.0, 7900, 9000, 0);
  insert into chat_threads (booking_id) values (bk) returning id into th;

  -- ---------- [N1] the OTHER party is told, and only them ----------
  begin
    insert into chat_messages (thread_id, sender_id, body) values (th, oo, '몇 시에 도착하세요?');
    select count(*) into v_n from notifications
      where profile_id = rr and ref_id = bk and title = '새 메시지';
    if v_n <> 1 then v_bad := v_bad || ' 러너 수신 행수=' || v_n; end if;
    select count(*) into v_n from notifications
      where profile_id = oo and ref_id = bk and title = '새 메시지';
    if v_n <> 0 then v_bad := v_bad || ' 보낸 사람에게도 갔다 (행수=' || v_n || ')'; end if;
    if v_bad = '' then
      call _pass('cn','N1 수신자 — 보호자가 보내면 러너에게 1행, 보낸 사람에겐 0행');
    else v_msg := v_bad; call _fail('cn','N1 수신자', v_msg); end if;
  exception when others then call _fail('cn','N1 수신자', sqlerrm); end;

  -- ---------- [N2] one nudge per unread state ----------
  -- The anti-storm rule: while the first nudge is unread, further messages write nothing;
  -- reading it re-arms. A normal back-and-forth must not become twenty pushes.
  begin
    v_bad := '';
    insert into chat_messages (thread_id, sender_id, body) values (th, oo, '지금 출발했어요');
    insert into chat_messages (thread_id, sender_id, body) values (th, oo, '5분 뒤 도착이요');
    select count(*) into v_n from notifications
      where profile_id = rr and ref_id = bk and title = '새 메시지';
    if v_n <> 1 then v_bad := v_bad || ' 미읽음 상태에서 누적=' || v_n || ' (1이어야 한다)'; end if;
    -- read it → the next message notifies again
    update notifications set read_at = now()
      where profile_id = rr and ref_id = bk and title = '새 메시지';
    insert into chat_messages (thread_id, sender_id, body) values (th, oo, '도착했습니다');
    select count(*) into v_n from notifications
      where profile_id = rr and ref_id = bk and title = '새 메시지' and read_at is null;
    if v_n <> 1 then v_bad := v_bad || ' 읽은 뒤 재무장 실패 (새 미읽음=' || v_n || ')'; end if;
    if v_bad = '' then
      call _pass('cn','N2 폭주 방지 — 미읽음 하나로 합쳐지고, 읽으면 다시 알린다');
    else v_msg := v_bad; call _fail('cn','N2 폭주 방지', v_msg); end if;
  exception when others then call _fail('cn','N2 폭주 방지', sqlerrm); end;

  -- ---------- [N3] the message text never leaves ----------
  -- 0024 pushes body VERBATIM to a lock screen (the property behind today's ops-alert leak).
  -- The notification says who and which run; the words stay behind the app.
  begin
    v_bad := '';
    bk2 := t_chg_bk(oo, dg, rt, rr, 'confirmed', now() + interval '5 hours', 3.0, 7900, 9000, 0);
    insert into chat_threads (booking_id) values (bk2) returning id into th2;
    insert into chat_messages (thread_id, sender_id, body)
      values (th2, rr, '강아지가 다리를 절어요 — 병원 갈까요?');
    select n.body, n.title into v_body, v_title from notifications n
      where n.profile_id = oo and n.ref_id = bk2 and n.title = '새 메시지';
    if v_body is null then v_bad := v_bad || ' 알림이 없다';
    else
      if position('절어요' in v_body) > 0 or position('병원' in v_body) > 0 then
        v_bad := v_bad || ' 본문에 메시지 내용이 들어갔다 (잠금화면 유출)';
      end if;
      if position('님이 메시지를 보냈어요' in v_body) = 0 then
        v_bad := v_bad || ' 누가 보냈는지를 말하지 않는다';
      end if;
    end if;
    if v_bad = '' then
      call _pass('cn','N3 본문 — 누가·어느 러닝인지만, 메시지 내용은 절대 싣지 않는다 (0024는 잠금화면에 그대로 띄운다)');
    else v_msg := v_bad; call _fail('cn','N3 본문', v_msg); end if;
  exception when others then call _fail('cn','N3 본문', sqlerrm); end;

  -- ---------- [N4] no runner, nobody to tell ----------
  begin
    v_bad := '';
    declare b_nr uuid; th3 uuid; begin
      b_nr := t_chg_bk(oo, dg, rt, NULL, 'matching', now() + interval '9 hours', 3.0, 7900, 9000, 0);
      insert into chat_threads (booking_id) values (b_nr) returning id into th3;
      insert into chat_messages (thread_id, sender_id, body) values (th3, oo, '아무도 없는데 보냄');
      select count(*) into v_n from notifications where ref_id = b_nr and title = '새 메시지';
      if v_n <> 0 then v_bad := v_bad || ' 러너 없는 예약에 알림=' || v_n; end if;
    end;
    if v_bad = '' then
      call _pass('cn','N4 매칭 전 — 러너가 없으면 알릴 상대가 없다 (예외 아님, 무기록)');
    else v_msg := v_bad; call _fail('cn','N4 매칭 전', v_msg); end if;
  exception when others then call _fail('cn','N4 매칭 전', sqlerrm); end;

end $$;
