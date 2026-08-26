-- ═══ 168 approval notification — 0135 pins (N1 · N2 · G1) ═══
-- What this pins: that the notification `session_approve_dog` sends to the OWNER describes what
-- the function actually does. The old title said 「위탁 승인 — 결제 대기」 while the function's own
-- comment two lines above says 「요금 없음, '결제' 없음 … 이 단계에서 움직이는 돈은 없다」.
--
-- ⚠ EVERY FIXTURE IS DRIVEN THROUGH THE REAL LIFECYCLE, never INSERTed: club_request_district →
--   club_claim_host → club_create_session → session_runner_commit → session_checkin →
--   session_delegate_dog → session_approve_dog. A notification asserted over a hand-planted row
--   would prove the string, not the emission — and the emission is the thing that reaches a person.
-- ⚠ N1 asserts the ROW THE RPC WROTE, not `prosrc`. A source grep cannot tell a title that ships
--   from a title in a branch nothing reaches.
-- ⚠ G1 is schema-wide ON PURPOSE. A per-function pin only catches the function you already
--   suspected — and this defect was found by someone looking at something else entirely.
-- ⚠ `_fail` args pre-computed into v_msg, never a subquery (the 110 header law).
set client_min_messages = warning;

do $$
declare
  h uuid; r uuid; o uuid; d uuid; o2 uuid; d2 uuid; rt uuid;
  v_club uuid; v_ses uuid; v_sd uuid;
  v_title text; v_body text; v_n int; v_bad text; v_msg text;
begin
  -- ---------- fixtures: a real approval, driven end to end ----------
  h := t_user('apn_host', 'runner');
  r := t_user('apn_runner', 'runner');
  o := t_user('apn_owner', 'owner'); d := t_dog(o, '알림견');
  -- N2 needs its OWN dog: the product refuses a second registration of the same dog
  -- (`already_registered`), which is the lifecycle refusing an unreachable fixture — the
  -- first draft tried to reuse `d` and died there. Kept as a second owner+dog rather than
  -- worked around, because the refusal is correct.
  o2 := t_user('apn_owner2', 'owner'); d2 := t_dog(o2, '알림견2');
  rt := t_route('알림 코스');

  perform set_config('request.jwt.claim.sub', h::text, false);
  v_club := club_request_district('알림동');
  perform club_claim_host(v_club);
  v_ses := club_create_session(v_club, now() + interval '90 minutes', '알림 집결지', rt, 8, 'mixed');
  perform session_runner_commit(v_ses);
  perform set_config('request.jwt.claim.sub', r::text, false);
  perform session_runner_commit(v_ses); perform session_checkin(v_ses);
  perform set_config('request.jwt.claim.sub', o::text, false);
  v_sd := session_delegate_dog(v_ses, d, t_consent());
  perform set_config('request.jwt.claim.sub', h::text, false);
  perform session_approve_dog(v_sd, true);

  -- ---------- [N1] the notification the OWNER actually received ----------
  select title, body into v_title, v_body
    from notifications
   where profile_id = o and ref_id = v_ses and kind = 'booking'
   order by id desc limit 1;

  v_bad := '';
  if v_title is null then v_bad := v_bad || ' 알림이 발송되지 않았다';
  else
    -- the defect: a money word in a step the function itself documents as money-free
    if v_title like '%결제%' then v_bad := v_bad || ' 제목이 결제를 주장한다: ' || v_title; end if;
    if v_title like '%청구%' or v_title like '%환불%' then v_bad := v_bad || ' 제목에 돈 낱말: ' || v_title; end if;
    -- positive half: the deadline the owner has 20 minutes to act on must survive in the TITLE,
    -- because the title is the sentence most owners will ever see about this step
    if v_title not like '%20분%' then v_bad := v_bad || ' 제목이 20분 시한을 잃었다: ' || v_title; end if;
    if v_title not like '%자리%' then v_bad := v_bad || ' 제목이 자리를 말하지 않는다: ' || v_title; end if;
  end if;
  if v_bad = '' then call _pass('apn','N1 승인 알림 — 돈을 주장하지 않고 자리·시한을 말한다 (실제 발송된 행)');
  else v_msg := v_bad; call _fail('apn','N1 승인 알림', v_msg); end if;

  -- ---------- [N2] the recreation did not lose the rejection arm ----------
  -- 0135 recreated the whole function to change one string. The other notification it emits is the
  -- REJECTION, on a branch N1 never reaches — exactly the arm a careless recreation drops silently.
  perform set_config('request.jwt.claim.sub', o2::text, false);
  v_sd := session_delegate_dog(v_ses, d2, t_consent());
  perform set_config('request.jwt.claim.sub', h::text, false);
  perform session_approve_dog(v_sd, false);
  select count(*) into v_n from notifications
   where profile_id = o2 and ref_id = v_ses and title = '위탁 신청 거절';
  if v_n = 1 then call _pass('apn','N2 거절 알림 — 재생성에서 살아남았다 (N1이 닿지 않는 가지)');
  else v_msg := '거절 알림 ' || v_n || '건 (기대 1)'; call _fail('apn','N2 거절 알림', v_msg); end if;
end $$;

-- ═══ standing guard — schema-wide ═══
do $$
declare v_n int; v_list text; v_msg text;
begin
  -- ---------- [G1] no function that documents itself as money-free emits a money-word title ----------
  -- The exact shape of 0135's defect, generalised: a function whose own body states that no money
  -- moves, while inserting a notification whose title claims one does. Allowlist is EMPTY and any
  -- future entry must carry its reason inline — widening it to get green is how this guard dies.
  select count(*), coalesce(string_agg(p.proname, ', ' order by p.proname), '')
    into v_n, v_list
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and (p.prosrc like '%움직이는 돈은 없다%' or p.prosrc like '%요금 없음%')
    and p.prosrc ~ 'insert into notifications[^;]*''[^'']*결제[^'']*''';
  if v_n = 0 then call _pass('apn','G1 스키마 전체 — 「돈 안 움직인다」고 적어 둔 함수가 결제를 주장하는 알림을 보내지 않는다');
  else v_msg := v_n || '개 함수가 자기 주석과 모순되는 알림을 보낸다: ' || v_list;
       call _fail('apn','G1 자기모순 알림 스윕', v_msg); end if;
end $$;
