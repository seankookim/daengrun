-- ═══ 143 realtime party channels — 0108 pins (C1-C3 · B1-B2 · K1-K2 · X1-X2 · E1-E3 · W1-W2) ═══
-- What this suite pins: that the three postgres_changes rooms the app opens — `chat-<thread>`,
-- `bk-<booking>`, `club-chat-<session>` — admit exactly the people the room's own table admits,
-- admit nobody to PUBLISH on them, and that the admission is WIRED (a real SELECT/INSERT on
-- `realtime.messages` as `authenticated`/`anon`, with `realtime.topic()` set the way realtime
-- sets it), not merely stated by the predicate. Without 0108, flipping `private_only` kills all
-- three rooms for everyone; with a wrong 0108, a stranger holding a UUID sits in them.
-- ⚠ Positive controls matter as much as denials here (140's law): a policy that admits nobody is
--   green on every negative arm while three features are dead. C1/B1/K1/E* each carry one.
-- ⚠ Every predicate assertion is written `is not true` / `is not false`, never `if [not] f()`
--   (adversarial review F3, 2026-08-19): plpgsql `if` skips on NULL in BOTH directions, so a
--   predicate that returns NULL instead of false — drop the final coalesce and it does — turned
--   0 of 14 pins red. Three-valued logic is the mutation that ordinary `if` cannot see.
-- ⚠ `_fail` args are pre-computed into v_msg, never a subquery (the 110 header law).
do $$
declare
  v_owner uuid; v_runner uuid; v_loser uuid; v_stranger uuid;
  v_dog uuid; v_dog2 uuid; v_bk uuid; v_bk2 uuid; v_bk_c uuid; v_bk_open uuid;
  v_th uuid; v_th2 uuid; v_th_c uuid;
  v_host uuid; v_member uuid; v_applicant uuid; v_host2 uuid; v_club uuid; v_ses uuid; v_ses2 uuid;
  v_cdog uuid; v_msgid bigint;
  v_t_chat text; v_t_bk text; v_t_club text; v_topic text;
  v_msg text; v_bad text; v_n int; v_ok boolean;
begin
  -- ---------- fixtures ----------
  v_owner := t_user('rc_owner', 'owner');   v_runner := t_user('rc_runner', 'runner');
  v_loser := t_user('rc_loser', 'runner');  v_stranger := t_user('rc_stranger', 'owner');
  v_dog := t_dog(v_owner, 'RC-dog');        v_dog2 := t_dog(v_stranger, 'RC-dog2');
  -- the party booking, in a NON-live status on purpose: chat and bk have no status gate
  insert into bookings (owner_id, dog_id, runner_id, status, scheduled_at, km, base_fare, distance_fare, total_price)
    values (v_owner, v_dog, v_runner, 'confirmed', now(), 3, 7900, 9000, 16900) returning id into v_bk;
  -- someone else's booking (topic-substitution target)
  insert into bookings (owner_id, dog_id, runner_id, status, scheduled_at, km, base_fare, distance_fare, total_price)
    values (v_stranger, v_dog2, v_loser, 'confirmed', now(), 3, 7900, 9000, 16900) returning id into v_bk2;
  -- a cancelled booking of the same party (chat persistence)
  insert into bookings (owner_id, dog_id, runner_id, status, scheduled_at, km, base_fare, distance_fare, total_price)
    values (v_owner, v_dog, v_runner, 'cancelled_owner', now(), 3, 7900, 9000, 16900) returning id into v_bk_c;
  -- an open request: runner_id still null (the radar screen watches this one)
  insert into bookings (owner_id, dog_id, runner_id, status, scheduled_at, km, base_fare, distance_fare, total_price)
    values (v_owner, v_dog, null, 'matching', now(), 3, 7900, 9000, 16900) returning id into v_bk_open;
  insert into chat_threads (booking_id) values (v_bk)   returning id into v_th;
  insert into chat_threads (booking_id) values (v_bk2)  returning id into v_th2;
  insert into chat_threads (booking_id) values (v_bk_c) returning id into v_th_c;

  -- club: host / full member / limited applicant / stranger, plus a second session
  v_host := t_user('rc_host', 'runner'); v_member := t_user('rc_member', 'owner');
  v_applicant := t_user('rc_applicant', 'owner'); v_host2 := t_user('rc_host2', 'runner');
  insert into clubs (name, district, status, host_profile_id) values ('RC클럽', '반포동', 'active', v_host) returning id into v_club;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
    values (v_club, v_host, now() + interval '2 hours', 'RC 집결지') returning id into v_ses;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
    values (v_club, v_host2, now() + interval '3 hours', 'RC 집결지2') returning id into v_ses2;
  insert into session_people (session_id, profile_id, role, attendance) values (v_ses, v_member, 'owner_attending', 'rsvp');
  v_cdog := t_dog(v_applicant, 'RC-cdog');
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id, custody, approval)
    values (v_ses, v_cdog, v_applicant, v_host, 'runner_delegated', 'pending');

  v_t_chat := 'chat-' || v_th::text;
  v_t_bk   := 'bk-'   || v_bk::text;
  v_t_club := 'club-chat-' || v_ses::text;

  -- ═════════ chat-<thread> ═════════
  -- ---------- [C1] both parties read; NOBODY writes (positive control + the publish deny) ----------
  v_bad := '';
  if channel_allowed(v_t_chat, v_owner,  'read') is not true then v_bad := v_bad || ' 오너가 채팅방에 못 들어간다'; end if;
  if channel_allowed(v_t_chat, v_runner, 'read') is not true then v_bad := v_bad || ' 러너가 채팅방에 못 들어간다'; end if;
  if     channel_allowed(v_t_chat, v_owner,  'write') then v_bad := v_bad || ' 오너가 채팅 채널에 발행한다'; end if;
  if     channel_allowed(v_t_chat, v_runner, 'write') then v_bad := v_bad || ' 러너가 채팅 채널에 발행한다'; end if;
  if v_bad = '' then call _pass('rtpc','C1 chat — 양 당사자 읽기, 발행은 아무도 못 한다 (postgres_changes 방)');
  else v_msg := v_bad; call _fail('rtpc','C1 chat 당사자', v_msg); end if;

  -- ---------- [C2] stranger · loser · anon · substituted thread · booking-id-as-thread · malformed ----------
  v_bad := '';
  if channel_allowed(v_t_chat, v_stranger, 'read') is not false then v_bad := v_bad || ' 무관한 사용자가 채팅방에 들어간다'; end if;
  if channel_allowed(v_t_chat, v_loser,    'read') is not false then v_bad := v_bad || ' 낙선 러너가 채팅방에 들어간다'; end if;
  if channel_allowed(v_t_chat, null,       'read') is not false then v_bad := v_bad || ' null uid(익명)가 통과'; end if;
  if channel_allowed('chat-' || v_th2::text, v_owner, 'read') is not false then v_bad := v_bad || ' 남의 스레드 토픽이 열린다'; end if;
  if channel_allowed('chat-' || v_bk::text,  v_owner, 'read') is not false then v_bad := v_bad || ' 예약 id를 스레드 id 자리에 넣어도 열린다'; end if;
  if channel_allowed('chat-not-a-uuid', v_owner, 'read') is not false then v_bad := v_bad || ' 형식 오류 토픽 통과'; end if;
  if channel_allowed('chat-' || v_th::text || '-x', v_owner, 'read') is not false then v_bad := v_bad || ' 꼬리 붙은 토픽 통과'; end if;
  if v_bad = '' then call _pass('rtpc','C2 chat — 무관·낙선·익명·치환·잘못된 id·형식 오류 전부 거부');
  else v_msg := v_bad; call _fail('rtpc','C2 chat fail closed', v_msg); end if;

  -- ---------- [C3] mirrors chat_threads: persists after cancel; former runner out on reassignment ----------
  -- chat_threads "threads party" is is_booking_party() with NO status gate — a cancelled booking's
  -- thread is still readable by its parties on the table, so the room must admit them too.
  v_bad := '';
  if channel_allowed('chat-' || v_th_c::text, v_owner,  'read') is not true then v_bad := v_bad || ' 취소된 예약의 채팅방에 오너가 못 들어간다(테이블은 허용)'; end if;
  if channel_allowed('chat-' || v_th_c::text, v_runner, 'read') is not true then v_bad := v_bad || ' 취소된 예약의 채팅방에 러너가 못 들어간다'; end if;
  update bookings set runner_id = v_loser where id = v_bk;
  if channel_allowed(v_t_chat, v_runner, 'read') is not false then v_bad := v_bad || ' 재배정 후 이전 러너가 채팅방에 남는다'; end if;
  if channel_allowed(v_t_chat, v_loser, 'read') is not true then v_bad := v_bad || ' 새 러너가 채팅방에 못 들어간다'; end if;
  update bookings set runner_id = v_runner where id = v_bk;   -- restore
  if v_bad = '' then call _pass('rtpc','C3 chat — 취소 후에도 당사자에게 열려 있고(테이블 정책 그대로), 재배정 즉시 이전 러너는 나간다');
  else v_msg := v_bad; call _fail('rtpc','C3 chat 상태·재배정', v_msg); end if;

  -- ═════════ bk-<booking> ═════════
  -- ---------- [B1] both parties read in a non-live status; owner alone while matching; nobody writes ----------
  v_bad := '';
  if channel_allowed(v_t_bk, v_owner,  'read') is not true then v_bad := v_bad || ' 오너가 예약 채널에 못 들어간다'; end if;
  if channel_allowed(v_t_bk, v_runner, 'read') is not true then v_bad := v_bad || ' 러너가 예약 채널에 못 들어간다'; end if;
  if channel_allowed('bk-' || v_bk_open::text, v_owner, 'read') is not true then v_bad := v_bad || ' 매칭 중(runner_id null) 오너가 레이더 채널에 못 들어간다'; end if;
  if     channel_allowed('bk-' || v_bk_open::text, v_loser, 'read') then v_bad := v_bad || ' 매칭 중 입찰 러너가 예약 채널에 들어간다'; end if;
  if     channel_allowed(v_t_bk, v_owner,  'write') then v_bad := v_bad || ' 오너가 예약 채널에 발행한다'; end if;
  if     channel_allowed(v_t_bk, v_runner, 'write') then v_bad := v_bad || ' 러너가 예약 채널에 발행한다'; end if;
  if v_bad = '' then call _pass('rtpc','B1 bk — 양 당사자 읽기(상태 무관), 매칭 중엔 오너만, 발행은 아무도 못 한다');
  else v_msg := v_bad; call _fail('rtpc','B1 bk 당사자', v_msg); end if;

  -- ---------- [B2] stranger · loser · anon · substituted booking · malformed · former runner ----------
  v_bad := '';
  if channel_allowed(v_t_bk, v_stranger, 'read') is not false then v_bad := v_bad || ' 무관한 사용자가 예약 채널에 들어간다'; end if;
  if channel_allowed(v_t_bk, v_loser,    'read') is not false then v_bad := v_bad || ' 낙선 러너가 예약 채널에 들어간다'; end if;
  if channel_allowed(v_t_bk, null,       'read') is not false then v_bad := v_bad || ' null uid(익명)가 통과'; end if;
  if channel_allowed('bk-' || v_bk2::text, v_owner, 'read') is not false then v_bad := v_bad || ' 남의 예약 토픽이 열린다'; end if;
  if channel_allowed('bk-' || v_th::text,  v_owner, 'read') is not false then v_bad := v_bad || ' 스레드 id를 예약 id 자리에 넣어도 열린다'; end if;
  if channel_allowed('bk-not-a-uuid', v_owner, 'read') is not false then v_bad := v_bad || ' 형식 오류 토픽 통과'; end if;
  update bookings set runner_id = v_loser where id = v_bk;
  if channel_allowed(v_t_bk, v_runner, 'read') is not false then v_bad := v_bad || ' 재배정 후 이전 러너가 예약 채널에 남는다'; end if;
  if channel_allowed(v_t_bk, v_loser, 'read') is not true then v_bad := v_bad || ' 새 러너가 예약 채널에 못 들어간다'; end if;
  update bookings set runner_id = v_runner where id = v_bk;   -- restore
  if v_bad = '' then call _pass('rtpc','B2 bk — 무관·낙선·익명·치환·형식 오류 거부, 재배정 즉시 이전 러너는 나간다');
  else v_msg := v_bad; call _fail('rtpc','B2 bk fail closed', v_msg); end if;

  -- ═════════ club-chat-<session> ═════════
  -- ---------- [K1] host · full member · limited applicant read; stranger/other-session/anon do not; nobody writes ----------
  v_bad := '';
  if channel_allowed(v_t_club, v_host,      'read') is not true then v_bad := v_bad || ' 호스트가 클럽 채팅방에 못 들어간다'; end if;
  if channel_allowed(v_t_club, v_member,    'read') is not true then v_bad := v_bad || ' 참석자(full)가 못 들어간다'; end if;
  if channel_allowed(v_t_club, v_applicant, 'read') is not true then v_bad := v_bad || ' 신청자(limited)가 자기 호스트 채널 방에 못 들어간다'; end if;
  if     channel_allowed(v_t_club, v_stranger,  'read') then v_bad := v_bad || ' 무관한 사용자가 클럽 채팅방에 들어간다'; end if;
  if     channel_allowed(v_t_club, v_host2,     'read') then v_bad := v_bad || ' 다른 세션의 호스트가 이 세션 방에 들어간다'; end if;
  if     channel_allowed(v_t_club, null,        'read') then v_bad := v_bad || ' null uid(익명)가 통과'; end if;
  if     channel_allowed('club-chat-' || v_ses2::text, v_member, 'read') then v_bad := v_bad || ' 남의 세션 토픽이 열린다'; end if;
  if     channel_allowed('club-chat-' || v_bk::text,   v_owner,  'read') then v_bad := v_bad || ' 예약 id를 세션 id 자리에 넣어도 열린다'; end if;
  if     channel_allowed('club-chat-not-a-uuid', v_host, 'read') then v_bad := v_bad || ' 형식 오류 토픽 통과'; end if;
  if     channel_allowed(v_t_club, v_host,   'write') then v_bad := v_bad || ' 호스트가 클럽 채팅 채널에 발행한다'; end if;
  if     channel_allowed(v_t_club, v_member, 'write') then v_bad := v_bad || ' 참석자가 클럽 채팅 채널에 발행한다'; end if;
  if v_bad = '' then call _pass('rtpc','K1 club-chat — host/full/limited 입장, 무관·타세션·익명·치환·형식 오류 거부, 발행은 아무도 못 한다');
  else v_msg := v_bad; call _fail('rtpc','K1 club-chat 입장', v_msg); end if;

  -- ---------- [K2] the room mirrors the table: limited reads ITS OWN host-channel row and not the group ----------
  -- The room predicate is `_club_shell_access <> 'none'`; this pins that 'limited' is inside the
  -- table's read set (own host-channel thread) so admitting it is not wider than the table — and
  -- that the group rows stay hidden from limited by the table's own RLS, which is what filters
  -- the postgres_changes events after admission.
  insert into club_chat_messages (session_id, sender_id, audience, recipient_profile_id, kind, body)
    values (v_ses, v_host, 'host_channel', v_applicant, 'text', 'RC-dm') returning id into v_msgid;
  insert into club_chat_messages (session_id, sender_id, audience, kind, body)
    values (v_ses, v_host, 'group', 'text', 'RC-group');
  perform set_config('request.jwt.claim.sub', v_applicant::text, true);
  set local role authenticated;
  select count(*) into v_n from club_chat_messages where session_id = v_ses and id = v_msgid;
  v_bad := '';
  if v_n <> 1 then v_bad := v_bad || ' limited가 자기 호스트 채널 행을 테이블에서 못 읽는다=' || v_n; end if;
  select count(*) into v_n from club_chat_messages where session_id = v_ses and audience = 'group';
  if v_n <> 0 then v_bad := v_bad || ' limited가 그룹 행을 읽는다=' || v_n; end if;
  reset role;
  perform set_config('request.jwt.claim.sub', v_stranger::text, true);
  set local role authenticated;
  select count(*) into v_n from club_chat_messages where session_id = v_ses;
  reset role;
  if v_n <> 0 then v_bad := v_bad || ' 무관한 사용자가 테이블 행을 읽는다=' || v_n; end if;
  if v_bad = '' then call _pass('rtpc','K2 club-chat — 방 입장 집합은 테이블 읽기 집합의 세션 투영이다 (limited는 자기 행만, 무관은 0행)');
  else v_msg := v_bad; call _fail('rtpc','K2 club-chat 테이블 대조', v_msg); end if;

  -- ═════════ cross-family ═════════
  -- ---------- [X1] unknown family · legacy run- · unknown op · null topic ----------
  v_bad := '';
  if channel_allowed('run-' || v_bk::text,  v_owner, 'read') is not false then v_bad := v_bad || ' 레거시 공개 run- 네임스페이스가 인가된다'; end if;
  if channel_allowed('foo-' || v_bk::text,  v_owner, 'read') is not false then v_bad := v_bad || ' 알 수 없는 패밀리가 통과'; end if;
  if channel_allowed('bk-' || v_bk::text || '/x', v_owner, 'read') is not false then v_bad := v_bad || ' 꼬리 붙은 토픽이 통과'; end if;
  if channel_allowed(v_bk::text, v_owner, 'read') is not false then v_bad := v_bad || ' 접두어 없는 uuid가 통과'; end if;
  if channel_allowed(v_t_bk,  v_owner, 'delete') is not false then v_bad := v_bad || ' 알 수 없는 op가 통과'; end if;
  if channel_allowed(v_t_bk,  v_owner, null) is not false then v_bad := v_bad || ' null op가 통과'; end if;
  if channel_allowed(null,    v_owner, 'read') is not false then v_bad := v_bad || ' null 토픽이 통과'; end if;
  if channel_allowed('',      v_owner, 'read') is not false then v_bad := v_bad || ' 빈 토픽이 통과'; end if;
  if v_bad = '' then call _pass('rtpc','X1 알 수 없는 패밀리·레거시 run-·꼬리·접두어 없음·알 수 없는 op·null 전부 거부 (fail closed)');
  else v_msg := v_bad; call _fail('rtpc','X1 fail closed', v_msg); end if;

  -- ---------- [X2] run2-* is delegated verbatim to 0103/0104 ----------
  declare v_live uuid; v_tl text;
  begin
    insert into bookings (owner_id, dog_id, runner_id, status, scheduled_at, km, base_fare, distance_fare, total_price)
      values (v_owner, v_dog, v_runner, 'active', now(), 3, 7900, 9000, 16900) returning id into v_live;
    v_tl := 'run2-' || v_live::text;
    v_bad := '';
    if channel_allowed(v_tl, v_owner,  'read')  is distinct from run_channel_allowed(v_tl, v_owner,  'read')  then v_bad := v_bad || ' owner/read 불일치'; end if;
    if channel_allowed(v_tl, v_owner,  'write') is distinct from run_channel_allowed(v_tl, v_owner,  'write') then v_bad := v_bad || ' owner/write 불일치'; end if;
    if channel_allowed(v_tl, v_runner, 'write') is distinct from run_channel_allowed(v_tl, v_runner, 'write') then v_bad := v_bad || ' runner/write 불일치'; end if;
    if channel_allowed(v_tl, v_loser,  'read')  is distinct from run_channel_allowed(v_tl, v_loser,  'read')  then v_bad := v_bad || ' loser/read 불일치'; end if;
    if channel_allowed(v_tl, v_runner, 'write') is not true then v_bad := v_bad || ' 위임 경로에서 배정 러너 발행이 죽었다'; end if;
    -- 'bk-' on the same live booking is a different room with a different rule: owner may not publish there either
    if channel_allowed('bk-' || v_live::text, v_runner, 'write') is not false then v_bad := v_bad || ' bk-가 run2-의 발행 규칙을 물려받았다'; end if;
    if v_bad = '' then call _pass('rtpc','X2 run2-* 는 run_channel_allowed에 그대로 위임된다 (4조합 일치, 배정 러너 발행 생존)');
    else v_msg := v_bad; call _fail('rtpc','X2 run2 위임', v_msg); end if;
  end;

  -- ═════════ THE BOUNDARY — real SELECT/INSERT on realtime.messages ═════════
  -- Everything above pins the RULE. These pin that the rule is WIRED: RLS on realtime.messages
  -- decides. Realtime's join check is exactly this: a `broadcast` probe row for the topic is
  -- inserted, then read back as the caller; a returned row admits the join. So the SELECT count
  -- as `authenticated` with the topic set IS the join decision. Rows are seeded as superuser
  -- (bypasses RLS) so the SELECT leg is measured alone.
  insert into realtime.messages (topic, extension, payload, private) values
    (v_t_chat, 'broadcast', '{}'::jsonb, true),
    (v_t_bk,   'broadcast', '{}'::jsonb, true),
    (v_t_club, 'broadcast', '{}'::jsonb, true),
    (v_t_club, 'presence',  '{}'::jsonb, true);

  -- ---------- [E1] chat room at the boundary ----------
  v_bad := '';
  perform set_config('realtime.topic', v_t_chat, true);
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = v_t_chat and extension = 'broadcast';
  reset role;
  if v_n <> 1 then v_bad := v_bad || ' 오너의 SELECT가 경계에서 0행 (채팅 라이브가 죽는다)=' || v_n; end if;
  perform set_config('request.jwt.claim.sub', v_stranger::text, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = v_t_chat;
  reset role;
  if v_n <> 0 then v_bad := v_bad || ' 무관한 사용자의 SELECT가 경계에서 통과=' || v_n; end if;
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;
  select count(*) into v_n from realtime.messages where topic = v_t_chat;
  reset role;
  if v_n <> 0 then v_bad := v_bad || ' 익명 SELECT가 경계에서 통과=' || v_n; end if;
  -- the party may NOT publish: INSERT is refused at the boundary even for the owner
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  set local role authenticated;
  begin
    insert into realtime.messages (topic, extension, payload, private)
      values (v_t_chat, 'broadcast', '{"typing":true}'::jsonb, true);
    v_bad := v_bad || ' 당사자의 채팅 채널 INSERT(발행)가 경계에서 통과했다';
  exception when insufficient_privilege or check_violation then null;
  end;
  reset role;
  if v_bad = '' then call _pass('rtpc','E1 경계 실측 chat — 당사자 SELECT 1행, 무관·익명 0행, 당사자 INSERT 거부');
  else v_msg := v_bad; call _fail('rtpc','E1 경계 chat', v_msg); end if;

  -- ---------- [E2] bk room at the boundary ----------
  v_bad := '';
  perform set_config('realtime.topic', v_t_bk, true);
  perform set_config('request.jwt.claim.sub', v_runner::text, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = v_t_bk;
  reset role;
  if v_n <> 1 then v_bad := v_bad || ' 러너의 SELECT가 경계에서 0행 (예약 상태 라이브가 죽는다)=' || v_n; end if;
  perform set_config('request.jwt.claim.sub', v_loser::text, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = v_t_bk;
  reset role;
  if v_n <> 0 then v_bad := v_bad || ' 낙선 러너의 SELECT가 경계에서 통과=' || v_n; end if;
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;
  select count(*) into v_n from realtime.messages where topic = v_t_bk;
  reset role;
  if v_n <> 0 then v_bad := v_bad || ' 익명 SELECT가 경계에서 통과=' || v_n; end if;
  perform set_config('request.jwt.claim.sub', v_runner::text, true);
  set local role authenticated;
  begin
    insert into realtime.messages (topic, extension, payload, private)
      values (v_t_bk, 'broadcast', '{"status":"completed"}'::jsonb, true);
    v_bad := v_bad || ' 러너의 예약 채널 INSERT(위조 이벤트)가 경계에서 통과했다';
  exception when insufficient_privilege or check_violation then null;
  end;
  reset role;
  if v_bad = '' then call _pass('rtpc','E2 경계 실측 bk — 러너 SELECT 1행, 낙선·익명 0행, 러너 INSERT 거부');
  else v_msg := v_bad; call _fail('rtpc','E2 경계 bk', v_msg); end if;

  -- ---------- [E3] club-chat room at the boundary (+ presence probe stays closed) ----------
  v_bad := '';
  perform set_config('realtime.topic', v_t_club, true);
  perform set_config('request.jwt.claim.sub', v_applicant::text, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = v_t_club and extension = 'broadcast';
  reset role;
  if v_n <> 1 then v_bad := v_bad || ' limited 신청자의 SELECT가 경계에서 0행=' || v_n; end if;
  perform set_config('request.jwt.claim.sub', v_host::text, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = v_t_club and extension = 'presence';
  reset role;
  if v_n <> 0 then v_bad := v_bad || ' presence 프로브가 열려 있다(아무도 presence를 쓰지 않는 방)=' || v_n; end if;
  perform set_config('request.jwt.claim.sub', v_stranger::text, true);
  set local role authenticated;
  select count(*) into v_n from realtime.messages where topic = v_t_club;
  reset role;
  if v_n <> 0 then v_bad := v_bad || ' 무관한 사용자의 SELECT가 경계에서 통과=' || v_n; end if;
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;
  select count(*) into v_n from realtime.messages where topic = v_t_club;
  reset role;
  if v_n <> 0 then v_bad := v_bad || ' 익명 SELECT가 경계에서 통과=' || v_n; end if;
  perform set_config('request.jwt.claim.sub', v_host::text, true);
  set local role authenticated;
  begin
    insert into realtime.messages (topic, extension, payload, private)
      values (v_t_club, 'broadcast', '{"x":1}'::jsonb, true);
    v_bad := v_bad || ' 호스트의 클럽 채팅 채널 INSERT(발행)가 경계에서 통과했다';
  exception when insufficient_privilege or check_violation then null;
  end;
  reset role;
  if v_bad = '' then call _pass('rtpc','E3 경계 실측 club-chat — limited SELECT 1행, presence 프로브 0행, 무관·익명 0행, 호스트 INSERT 거부');
  else v_msg := v_bad; call _fail('rtpc','E3 경계 club-chat', v_msg); end if;

  -- ═════════ wiring ═════════
  -- ---------- [W1] policy present and shaped; 0103's pair untouched; predicates sealed ----------
  v_bad := '';
  select count(*) into v_n from pg_policies
    where schemaname='realtime' and tablename='messages' and policyname='party channel read' and cmd='SELECT'
      and roles = '{authenticated}'::name[];
  if v_n <> 1 then v_bad := v_bad || ' party channel read 정책(SELECT, authenticated)이 없다=' || v_n; end if;
  select count(*) into v_n from pg_policies
    where schemaname='realtime' and tablename='messages' and policyname in ('run channel read','run channel write');
  if v_n <> 2 then v_bad := v_bad || ' 0103의 정책 2개가 온전하지 않다=' || v_n; end if;
  -- [0156, 2026-08-28] 3 → 5. `pack channel read` + `pack channel write` landed for Sean's public
  -- pack map. This pin's PROPERTY is 「아무도 몰래 정책을 하나 더 달지 못한다」, and that property is
  -- unchanged — only the number it counts moved, because a slice deliberately added two and said so.
  -- The two new policies are owned by 187 `0156-W1`/`0156-W2`, which assert their cmd, their role
  -- lists and their topic guards; this arm only owns the TOTAL, so a sixth policy still reddens here.
  select count(*) into v_n from pg_policies where schemaname='realtime' and tablename='messages';
  if v_n <> 5 then v_bad := v_bad || ' realtime.messages 정책 수가 5가 아니다=' || v_n; end if;
  if not (select p.prosecdef from pg_proc p where p.proname='channel_allowed')
    then v_bad := v_bad || ' channel_allowed가 definer가 아니다'; end if;
  if (select coalesce(array_to_string(p.proconfig,','),'') from pg_proc p where p.proname='channel_allowed') not like '%pg_temp%'
    then v_bad := v_bad || ' channel_allowed 본문에 search_path가 없다'; end if;
  if not (select p.prosecdef from pg_proc p where p.proname='my_channel_allowed')
    then v_bad := v_bad || ' my_channel_allowed가 definer가 아니다'; end if;
  if (select coalesce(array_to_string(p.proconfig,','),'') from pg_proc p where p.proname='my_channel_allowed') not like '%pg_temp%'
    then v_bad := v_bad || ' my_channel_allowed 본문에 search_path가 없다'; end if;
  if has_function_privilege('anon','channel_allowed(text,uuid,text)','execute')
    then v_bad := v_bad || ' anon이 channel_allowed를 실행할 수 있다'; end if;
  if has_function_privilege('authenticated','channel_allowed(text,uuid,text)','execute')
    then v_bad := v_bad || ' authenticated가 임의 uid로 channel_allowed를 실행할 수 있다(당사자 프로브)'; end if;
  -- [0156, 2026-08-28] INVERTED, by ruling, and this is the sharper of the two edits.
  -- 0108 asserted 「anon이 my_channel_allowed를 실행할 수 없다」. That was correct while every family
  -- needed an identity: an anon caller has `auth.uid()` NULL, so the grant bought nothing and its
  -- absence cost nothing. 0156 adds `pack-<session>`, whose READ is PUBLIC by Sean's ruling
  -- (2026-08-28 「total public」), so the anon path must reach the predicate — the grant is now
  -- LOAD-BEARING and its absence is the feature being dead. Asserting the grant's PRESENCE here
  -- keeps this arm two-sided rather than deleting it: revoking anon reddens 143 W1 and 187 0156-E2.
  -- ⚠ What anon can learn through it is still exactly one boolean per session id (「is this map
  --   live」); every other family denies on the NULL uid, which 187 `0156-W3` pins arm by arm.
  if not has_function_privilege('anon','my_channel_allowed(text,text)','execute')
    then v_bad := v_bad || ' anon이 my_channel_allowed를 실행 못 한다(0156 공개 팩 지도가 죽는다)'; end if;
  if not has_function_privilege('authenticated','my_channel_allowed(text,text)','execute')
    then v_bad := v_bad || ' authenticated가 my_channel_allowed를 실행 못 한다(정책이 죽는다)'; end if;
  -- F1: 0103's own predicate was a party/liveness oracle for any logged-in user; 0108 closes it.
  if has_function_privilege('authenticated','run_channel_allowed(text,uuid,text)','execute')
    then v_bad := v_bad || ' authenticated가 임의 uid로 run_channel_allowed를 실행할 수 있다(0103 오라클 미봉인)'; end if;
  if has_function_privilege('anon','run_channel_allowed(text,uuid,text)','execute')
    then v_bad := v_bad || ' anon이 run_channel_allowed를 실행할 수 있다'; end if;
  -- the two 0103-named policies must now be wired through the wrapper, not the raw predicate
  select count(*) into v_n from pg_policies
    where schemaname='realtime' and tablename='messages' and policyname in ('run channel read','run channel write')
      and (coalesce(qual,'') || coalesce(with_check,'')) like '%my_channel_allowed%';
  if v_n <> 2 then v_bad := v_bad || ' 0103 정책이 래퍼(my_channel_allowed)를 거치지 않는다=' || v_n; end if;
  if v_bad = '' then call _pass('rtpc','W1 배선 — party channel read(SELECT/authenticated) 1개 + 0103의 2개 재정의(래퍼 경유) + 0156의 pack 2개(총 5), 술어 definer·search_path·임의 uid 봉인, my_channel_allowed는 anon에게 열려 있다(0156 공개 읽기), run_channel_allowed 오라클 폐쇄');
  else v_msg := v_bad; call _fail('rtpc','W1 배선', v_msg); end if;

  -- ---------- [W2] the probe is closed AT THE ROLE, and the uid-fixed form answers for the caller ----------
  v_bad := '';
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  set local role authenticated;
  begin
    perform channel_allowed(v_t_bk, v_stranger, 'read');
    v_bad := v_bad || ' authenticated가 남의 uid로 channel_allowed를 호출했다';
  exception when insufficient_privilege then null;
  end;
  begin
    perform run_channel_allowed('run2-' || v_bk::text, v_stranger, 'read');
    v_bad := v_bad || ' authenticated가 남의 uid로 run_channel_allowed를 호출했다(0103 오라클)';
  exception when insufficient_privilege then null;
  end;
  begin
    select my_channel_allowed(v_t_bk, 'read') into v_ok;
    if not coalesce(v_ok, false) then v_bad := v_bad || ' 오너의 my_channel_allowed(bk)가 false'; end if;
    select my_channel_allowed('bk-' || v_bk2::text, 'read') into v_ok;
    if coalesce(v_ok, false) then v_bad := v_bad || ' 오너의 my_channel_allowed(남의 bk)가 true'; end if;
  exception when others then
    v_bad := v_bad || ' my_channel_allowed 호출 실패 [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  reset role;
  if v_bad = '' then call _pass('rtpc','W2 임의 uid 프로브(channel_allowed·run_channel_allowed 둘 다)는 역할 단계에서 42501, auth.uid() 고정형은 호출자에 대해서만 답한다');
  else v_msg := v_bad; call _fail('rtpc','W2 프로브 봉인', v_msg); end if;
end $$;
