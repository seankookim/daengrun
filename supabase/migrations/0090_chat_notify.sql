-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- 0090 — ⑬ 채팅이 상대의 폰에 도달하게 한다
-- ═══════════════════════════════════════════════════════════════════════════════════════════
-- docs/decisions/chat-notifications.md
--
-- WHAT WAS BROKEN. Push fires on exactly one thing — `notifications_push after insert on
-- notifications` (0024:43) — and NOTHING wrote a notifications row when a chat message was
-- sent (`sendChatMessage`, api.ts:2325, inserts the message and returns). So runner↔owner chat
-- was realtime in-app only: visible on an open screen, silent in a pocket.
--
-- The precise shape, because it is not "nothing notified": STRUCTURED events did. The owner's
-- stop request writes a notifications row (`notifyRunStop`), which is why that sheet can
-- honestly promise an alert. It was FREE-FORM CHAT that had no path to a phone — the channel
-- both parties reach for when something unexpected happens was the one that did not ring.
--
-- WHY IT IS URGENT rather than tidy (Sean's ⑫ rulings, 2026-08-13): every one of them is
-- *tell someone something* — the runner must be told pay waits for return, the owner must be
-- told where the relief point is — and his design gate is **"we dont want the runner stranded
-- in the middle of town."** Today that runner can message the owner and the owner's phone stays
-- silent while the 2h escalation clock runs. The unanswered message is the first failure in
-- that story; the stranded state is the second.
-- ═══════════════════════════════════════════════════════════════════════════════════════════

-- ── The title is a ROUTING KEY, not just copy ─────────────────────────────────────────────
-- `routeForNotification` (app/src/lib/push.ts) sends a tapped `booking` notification to the
-- role's default screen, EXCEPT for titles it recognises — the `RUN_STOP_TITLE` precedent,
-- whose own comment says "한쪽을 바꾸면 둘 다 바꾼다". So this string is a cross-language
-- contract, and today's lesson about those is that duplicated literals drift silently.
-- It is therefore pinned from BOTH sides: `_test/chat_notify_contract_test.ts` reads THIS FILE
-- at test time and asserts push.ts carries the same literal, in both directions. Do not hoist
-- it into a TS constant to "tidy" the test — that makes the test pass against the copy.
-- ── Design decisions, both deliberate and both Sean's to overrule ─────────────────────────
-- ① THE PUSH CARRIES NO MESSAGE TEXT. 0024 pushes `title`/`body` VERBATIM to a lock screen —
--    the same property behind the ops-alert leak that was fixed by redaction today. A chat
--    body on a lock screen is the other party's words visible to anyone holding the phone, and
--    for an incident that is exactly when the phone is most likely to be handed around. The
--    notification says WHO and WHICH RUN; the message itself is one tap away, behind the app.
-- ② ONE NUDGE PER UNREAD STATE. If the recipient already has an unread chat notification for
--    this booking, a second message writes nothing. No time window, no cron, no dedupe table:
--    reading it re-arms the nudge. A normal back-and-forth therefore produces one push, not
--    twenty — and the escalating case (they are NOT reading) keeps exactly the one signal.
create or replace function notify_chat_message() returns trigger
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_booking uuid;
  v_owner   uuid;
  v_runner  uuid;
  v_to      uuid;
  v_name    text;
begin
  select t.booking_id, b.owner_id, b.runner_id
    into v_booking, v_owner, v_runner
  from chat_threads t join bookings b on b.id = t.booking_id
  where t.id = new.thread_id;

  -- No thread row, or an unmatched booking with no runner yet: nobody to tell.
  if v_booking is null or v_owner is null or v_runner is null then
    return new;
  end if;

  -- The other party. A sender who is neither (impossible under RLS, cheap to be sure of)
  -- notifies nobody rather than guessing a recipient.
  if new.sender_id = v_owner then
    v_to := v_runner;
  elsif new.sender_id = v_runner then
    v_to := v_owner;
  else
    return new;
  end if;

  -- ② one nudge per unread state
  if exists (
    select 1 from notifications n
    where n.profile_id = v_to
      and n.ref_id = v_booking
      and n.title = '새 메시지'
      and n.read_at is null
  ) then
    return new;
  end if;

  select p.name into v_name from profiles p where p.id = new.sender_id;

  -- ① who and which run — never what they said
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (
    v_to, 'booking', '새 메시지',
    coalesce(v_name, '상대방') || '님이 메시지를 보냈어요',
    v_booking
  );

  return new;
end $$;

-- ⚠ A trigger function is still a `security definer` function in the catalog, so it is caught by
-- 99's S1 sweep ("anon 실행 가능 definer 함수 0개", the 0057 §1 rule) unless execute is revoked.
-- I did not revoke it in the first draft and S1 went red on the first harness run — the sweep
-- doing exactly its job on new code. Revoking costs nothing: the trigger fires on the table's
-- own authority, not on the caller's execute grant, so this only closes direct invocation.
revoke execute on function notify_chat_message() from public, anon, authenticated;

drop trigger if exists chat_messages_notify on chat_messages;
create trigger chat_messages_notify after insert on chat_messages
  for each row execute function notify_chat_message();

comment on function notify_chat_message is
  '0090 ⑬: 채팅 메시지 → 상대방 notifications 행 (0024 트리거가 그 행을 푸시로 만든다).
본문에 메시지 내용을 담지 않는다 — 0024는 body를 잠금화면에 그대로 띄우고, 사건 상황일수록
폰은 남에게 보인다. 미읽음 알림이 이미 있으면 쓰지 않는다: 읽으면 다시 무장된다(폭주 방지).
제목 ''새 메시지''는 push.ts의 라우팅 키다 — 계약 테스트가 양방향으로 고정한다';
