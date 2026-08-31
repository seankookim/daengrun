-- ═══ 191: 팩 지도 발행 RPC (0160) — 0160-A1~A9 · B1 · S1 · W1~W3 · M1 · M2 ══════════════════
--
-- 🔴 THE PROPERTY THIS FILE OWNS, in one sentence: **`club_pack_publish` is the ONLY way a
--    position reaches a pack topic, it re-decides party and window on EVERY call, and the payload
--    it lands carries an identity no argument could have moved.** Suite 190 owns the READ side
--    and the socket door's absence; this file owns the door that replaced it.
--
-- Why the door moved at all (`docs/decisions/2026-08-28-codex-verdicts.md` §0159, REJECT/11):
--   · #2 — realtime authorization is CACHED PER SOCKET. 0159's write policy was evaluated once at
--     join and never again, so a participant who joined checked-in kept publishing after
--     세션 종료 / 러닝 종료 / a revoked check-in. No predicate can fix that; it is not consulted.
--   · #4 — the payload was CLIENT-AUTHORED. 0159 §2 said so itself and left the remedy to the
--     client. A checked-in attacker could publish another member's `profileId` and `name` with a
--     newer timestamp, and every honest client would render it, because that id IS in the roster.
-- 0160 answers both structurally: an RPC that re-gates per call and authors the payload from
-- `auth.uid()`. `0160-A2` is the pin for #4 and `0160-A4` for #2.
--
-- ⚠ **PIN LABELS ARE SLICE-PREFIXED** (`0160-…`, CLAUDE.md). A/B/S/W/M collide with several
--   suites' unprefixed labels; the prefix owns the namespace rather than sharing it.
--
-- ⚠ **EVERY PREDICATE ASSERTION IS `is not true` / `is distinct from`, NEVER a bare `if f(...)`.**
--   plpgsql skips an `IF` on a NULL predicate in BOTH directions, so a helper returning NULL
--   leaves every arm silent — and every arm here exists to notice something MISSING.
--
-- ⚠ **FIXTURES ARE THIS FILE'S OWN.** Suite 190 leaves its sessions AND its `realtime.messages`
--   probe rows in place, and 190's `0159-E2` counts rows on ITS topic. Nothing here touches a
--   topic it did not create, and every pin that counts rows DELETES its own topic first and
--   asserts 0 — so the number each pin reports is a delta IT caused rather than a state it found
--   (CLAUDE.md: if you deleted the behaviour, would this pin's number change?).
--
-- ⚠ `now()` is FROZEN inside this do-block — the whole file is one transaction. The throttle's
--   「wait, then it works again」 arm is exercised by REWINDING the mark row, never by waiting.
--
-- 🔴 **THREE LIMITATIONS, WRITTEN AS PROSE BECAUSE A PIN FOR ANY OF THEM WOULD BE
--    UNFALSIFIABLE.** A pin whose arms cannot be reddened is an unfalsifiable guard doing prose's
--    job, and its green is read by every later session as coverage.
--
--    ① **`not_delivered` is structurally unreachable here.** It exists because production's
--      `realtime.messages` is PARTITIONED by day and an insert into a cold project can fail with
--      `MissingPartition` (measured 2026-08-31: idle production had partitions ending 2026-08-29,
--      and holding one anon socket ~75 s took it to 2026-09-03). The harness shim's table is
--      UNPARTITIONED, so the INSERT always succeeds. `0160-S1` guards the exception handler's
--      EXISTENCE and its conversion to the typed refusal from source instead — a different kind
--      of evidence and the only one available. The deploy protocol's cold-start probe (publish
--      with no socket → expect `not_delivered`; open a socket, wait, publish → expect `ok`) is
--      where that refusal is actually observed.
--
--    ② **THE THROTTLE'S CONCURRENCY IS NOT EXERCISABLE IN THIS HARNESS, and that is precisely the
--      adversary it was rewritten for.** 0160 §A ⑤ is one atomic conditional upsert rather than
--      read-then-write, because N simultaneous requests all read the same committed mark and all
--      pass the check-then-write form. This file is ONE transaction on ONE connection: it can
--      drive the SERIAL case (`0160-A6` does — second call in the same transaction is `too_fast`)
--      and it structurally cannot drive two concurrent sessions. What the serial pin proves is
--      that the upsert's `where` clause refuses inside the window; what nothing here proves is
--      that the row lock serialises two racers. That is a property of `INSERT … ON CONFLICT DO
--      UPDATE` taking the conflicting row's lock for the duration of the statement, and it is
--      asserted from the shape of the statement (`0160-S1`), not measured.
--
--    ③ **Socket-level behaviour is invisible to SQL.** Join caching, the private-channel
--      handshake and `PrivateOnly` are properties of the realtime SERVER; a SQL harness has a
--      table where production has a socket. 0160's answer to those is a DESIGN (a cached join now
--      authorizes nothing, because there is nothing left to authorize), not a pin.
--
-- ═══ THE MUTATION BATTERY — see the bottom of this file for the measured table ═══════════════

do $suite$
declare
  v_host uuid; v_runner uuid; v_owner uuid; v_comp uuid; v_guest uuid;
  v_rsvp uuid; v_stranger uuid; v_zone uuid; v_thr uuid;
  v_club uuid; v_club2 uuid; v_ses uuid; v_ses2 uuid;
  v_dog uuid; v_bk uuid;
  v_topic text; v_topic2 text; v_sched timestamptz;
  v_j jsonb; v_p jsonb; v_keys text[]; v_src text;
  v_n int; v_n2 int; v_bad text; v_msg text; v_last timestamptz; v_txt text;
  v_age uuid; v_day date; v_a0 bigint; v_a1 bigint; v_b0 bigint; v_b1 bigint;
begin
  -- ═══════════ fixtures — the shipped path wherever one exists ═══════════
  v_host    := t_user('pb_host',    'runner');
  v_runner  := t_user('pb_runner',  'runner');
  v_owner   := t_user('pb_owner',   'owner');    -- delegates a dog
  v_comp    := t_user('pb_comp',    'owner');    -- 동반: walks their own dog
  v_guest   := t_user('pb_guest',   'owner');    -- dogless guest (Sean: a guest is a member)
  v_rsvp    := t_user('pb_rsvp',    'owner');    -- joins and never shows up
  v_stranger:= t_user('pb_stranger','owner');    -- not in this session at all
  v_zone    := t_user('pb_zone',    'owner');    -- the DIVERGENCE-ZONE fixture, see 0160-A3
  v_thr     := t_user('pb_thr',     'owner');    -- owns the throttle pin alone
  v_age     := t_user('pb_age',     'owner');    -- owns the p_age_ms clamp pin alone (0160-A9)

  insert into clubs (name, district, status, host_profile_id)
    values ('PB클럽', '반포동', 'active', v_host) returning id into v_club;
  insert into clubs (name, district, status, host_profile_id)
    values ('PB옆클럽', '반포동', 'active', v_host) returning id into v_club2;

  -- inside session_checkin's band (0030:251) so the shipped check-in RPC is usable
  v_sched := now() + interval '30 minutes';
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
    values (v_club, v_host, v_sched, 'PB 집결지') returning id into v_ses;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
    values (v_club2, v_host, v_sched, 'PB 집결지2') returning id into v_ses2;

  insert into session_people (session_id, profile_id, role) values
    (v_ses, v_host,   'host_runner'),
    (v_ses, v_runner, 'handling_runner'),
    (v_ses, v_owner,  'owner_attending'),
    (v_ses, v_comp,   'owner_attending'),
    (v_ses, v_guest,  'owner_attending'),
    (v_ses, v_rsvp,   'owner_attending'),
    (v_ses, v_thr,    'owner_attending'),
    (v_ses, v_age,    'owner_attending');
  insert into session_people (session_id, profile_id, role) values (v_ses2, v_host, 'host_runner');

  -- a delegated pairing WITH a booking, so 러닝 종료 (window ③) has something to stamp
  v_dog := t_dog(v_owner, 'PB-위탁견');
  insert into bookings (owner_id, dog_id, runner_id, club_session_id, status, scheduled_at,
                        km, base_fare, distance_fare, total_price)
    values (v_owner, v_dog, v_runner, v_ses, 'active', v_sched, 3, 7900, 9000, 16900)
    returning id into v_bk;
  insert into session_dogs (session_id, dog_id, owner_profile_id, responsible_profile_id,
                            custody, approval, booking_id)
    values (v_ses, v_dog, v_owner, v_runner, 'runner_delegated', 'approved', v_bk);

  -- 🔴 **THE DIVERGENCE-ZONE ROW, and it is inserted DIRECTLY on purpose.** `attendance =
  --    'checked_in'` with `checked_in_at` NULL is the one row shape on which 0159's two halves
  --    disagree: its window conjunct ② tests the STAMP while its write arm tested the ATTENDANCE
  --    word, and `session_no_show` (95:52) moves attendance by UPDATE while the stamp stands, so
  --    the mirror shape is reachable through the product. A fixture where both halves agree
  --    cannot tell the two candidate predicates apart (CLAUDE.md's fixture-agreement law), which
  --    is exactly why this row exists and why it cannot be produced by `session_checkin`.
  insert into session_people (session_id, profile_id, role, attendance, checked_in_at)
    values (v_ses, v_zone, 'owner_attending', 'checked_in', null);

  v_topic  := 'pack-' || v_ses::text;
  v_topic2 := 'pack-' || v_ses2::text;

  -- the shipped check-in path, as five participant kinds + the throttle user
  perform set_config('request.jwt.claim.sub', v_host::text,   true); perform session_checkin(v_ses);
  perform set_config('request.jwt.claim.sub', v_runner::text, true); perform session_checkin(v_ses);
  perform set_config('request.jwt.claim.sub', v_owner::text,  true); perform session_checkin(v_ses);
  perform set_config('request.jwt.claim.sub', v_comp::text,   true); perform session_checkin(v_ses);
  perform set_config('request.jwt.claim.sub', v_guest::text,  true); perform session_checkin(v_ses);
  perform set_config('request.jwt.claim.sub', v_thr::text,    true); perform session_checkin(v_ses);
  perform set_config('request.jwt.claim.sub', v_age::text,    true); perform session_checkin(v_ses);
  perform set_config('request.jwt.claim.sub', v_host::text,   true); perform session_checkin(v_ses2);
  perform set_config('request.jwt.claim.sub', '', true);
  -- v_rsvp deliberately never checks in; v_zone's row was never stamped

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-A1] THE HAPPY PATH, AND THE ROW IT LANDS. The RPC answers {ok:true, refusal:null},
  --           and — read in a SEPARATE STATEMENT, which is not a stylistic choice — the row is
  --           on the right topic, is a private broadcast with event 'pos', and its payload key
  --           set is EXACTLY the six keys the server authors.
  -- 🔴 The separate statement is measured, not preferred: on production 2026-08-31,
  --    `select realtime.send(...), (select count(*) from realtime.messages …)` returned **0** —
  --    the count reads the statement-start snapshot and structurally cannot see the insert its
  --    own statement is making. 0160 no longer NEEDS a later statement (it inserts the row itself
  --    and lets the exception be the detector), but this PIN still does: a count folded into the
  --    RPC's own statement would be green-blind here for exactly the same reason.
  -- ⚠ **THIS IS THE PIN THAT OWNS DELIVERY NOW.** 0160 §A inserts into `realtime.messages`
  --   directly instead of calling `realtime.send`, so 「did a row land」 is a behavioural question
  --   again rather than something only source could see. Deleting the INSERT statement reddens
  --   HERE, first.
  -- ⚠ The topic is CLEARED first and asserted 0, so the `= 1` below is a delta this pin caused
  --   rather than a state it found.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  delete from realtime.messages where topic in (v_topic, v_topic2);
  select count(*) into v_n from realtime.messages where topic = v_topic;
  if v_n <> 0 then v_bad := v_bad || ' 토픽을 비웠는데 행이 남아 있다(이 핀의 숫자가 자기 것이 아니다)=' || v_n; end if;

  perform set_config('request.jwt.claim.sub', v_guest::text, true);
  select club_pack_publish(v_ses, 37.5045, 126.9955) into v_j;
  perform set_config('request.jwt.claim.sub', '', true);

  if (v_j->>'ok')::boolean is not true
    then v_bad := v_bad || ' 체크인한 게스트의 발행이 ok 가 아니다 refusal=' || coalesce(v_j->>'refusal','(null)'); end if;
  if v_j->>'refusal' is not null
    then v_bad := v_bad || ' 성공인데 refusal 이 채워져 있다=' || coalesce(v_j->>'refusal','?'); end if;
  select array_agg(k order by k) into v_keys from jsonb_object_keys(v_j) k;
  if v_keys is distinct from array['ok','refusal']
    then v_bad := v_bad || ' 반환 키 집합이 {ok,refusal} 가 아니다=' || coalesce(array_to_string(v_keys,','),'(null)'); end if;

  -- ── the row, in a LATER statement ──
  select count(*) into v_n from realtime.messages where topic = v_topic;
  if v_n <> 1 then v_bad := v_bad || ' 발행 뒤 토픽의 행이 1개가 아니다=' || v_n; end if;
  select m.payload into v_p from realtime.messages m
   where m.topic = v_topic and m.event = 'pos' and m.payload->>'profileId' = v_guest::text;
  if v_p is null then v_bad := v_bad || ' 게스트의 행을 찾을 수 없다(event 나 profileId 가 다르다)';
  else
    select count(*) into v_n from realtime.messages m
     where m.topic = v_topic and m.event = 'pos' and m.extension = 'broadcast' and m.private is true;
    if v_n <> 1 then v_bad := v_bad || ' broadcast/private=true 인 pos 행이 1개가 아니다=' || v_n; end if;
    select array_agg(k order by k) into v_keys from jsonb_object_keys(v_p) k;
    if v_keys is distinct from array['at','id','lat','lng','name','profileId']
      then v_bad := v_bad || ' 페이로드 키 집합이 서버가 만든 여섯 개가 아니다=' || coalesce(array_to_string(v_keys,','),'(null)'); end if;
    if v_p->>'name' is distinct from 'pb_guest'
      then v_bad := v_bad || ' name 이 profiles 값이 아니다=' || coalesce(v_p->>'name','(null)'); end if;
    -- ⚠ compared with a tolerance, not for equality: the value round-trips float8 → jsonb numeric
    --   → text → float8, and pinning an exact decimal spelling would be a pin about formatting.
    if abs((v_p->>'lat')::double precision - 37.5045) > 1e-9 is not false
      then v_bad := v_bad || ' lat 이 인자와 다르다=' || coalesce(v_p->>'lat','(null)'); end if;
    if abs((v_p->>'lng')::double precision - 126.9955) > 1e-9 is not false
      then v_bad := v_bad || ' lng 이 인자와 다르다=' || coalesce(v_p->>'lng','(null)'); end if;
    -- `at` is ISO-8601 UTC with a Z, so a client can parse it without knowing the server's zone
    if v_p->>'at' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'
      then v_bad := v_bad || ' at 이 ISO-8601 UTC(Z) 형식이 아니다=' || coalesce(v_p->>'at','(null)'); end if;
    if (v_p->>'id')::uuid is null then v_bad := v_bad || ' 페이로드에 id 가 없다'; end if;
    -- ⚠ [0160 item 1] 행의 id 열과 페이로드의 id 가 같다. `realtime.send` 를 쓰던 때는 이것이
    --   **거짓**이었다(그 함수는 행 id 를 자기 gen_random_uuid() 로 채우고 호출자의
    --   payload->>'id' 만 남긴다 — 운영 측정 2026-08-31). 직접 INSERT 로 바뀌면서 둘이 같아졌고,
    --   INSERT 의 컬럼 목록에서 `id` 를 빼면 이 팔이 붉어진다.
    select count(*) into v_n from realtime.messages m
     where m.topic = v_topic and m.id::text = v_p->>'id';
    if v_n <> 1 then v_bad := v_bad || ' 행의 id 열이 페이로드의 id 와 다르다(직접 INSERT 가 id 를 안 넣는다)=' || v_n; end if;
  end if;
  if v_bad = '' then call _pass('pkpub','0160-A1 발행 성공 경로 — 체크인한 참가자가 club_pack_publish 로 {ok:true, refusal:null} 을 받고, **다음 문장에서** 읽으면 그 토픽에 broadcast·private=true·event=pos 행이 정확히 하나 있으며 페이로드 키는 서버가 만든 여섯 개(at·id·lat·lng·name·profileId), name 은 profiles 값, 좌표는 인자 그대로, at 은 ISO-8601 UTC(Z), 그리고 행의 id 열이 페이로드의 id 와 같다(0160 이 realtime.send 대신 행을 직접 넣기 때문 — send 를 쓰던 때는 이것이 거짓이었다)');
  else v_msg := v_bad; call _fail('pkpub','0160-A1 발행 성공 경로', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-A2] 🔴 IDENTITY IS STRUCTURAL — codex #4. Two different callers publish and each row
  --           carries ITS OWN uid. The pin's other half is the SIGNATURE, read from the catalog:
  --           `club_pack_publish(p_session, p_lat, p_lng, p_age_ms)` has **no identity argument
  --           at all**, so there is nothing a caller could pass to claim somebody else. That is
  --           not a guard someone must remember to write — it is the absence of a parameter, and
  --           this arm is what makes the absence executable rather than prose.
  -- ⚠ Names too: a forger's prize was `name`, not only `profileId`, and both come from `profiles`.
  -- ⚠ [0160 item 1b] `p_age_ms` joined the signature and the frozen string moved with it. The
  --   PROPERTY is unchanged — the argument list is fixed, so a later slice adding a `p_profile_id`
  --   「for the admin case」 has to argue with a pin — and the new argument is a scalar clamp on the
  --   timestamp, not an identity (`0160-A9` owns what it does).
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  select coalesce(array_to_string(p.proargnames, ','), '(null)') into v_txt
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_pack_publish';
  if v_txt is distinct from 'p_session,p_lat,p_lng,p_age_ms'
    then v_bad := v_bad || ' 시그니처가 (p_session,p_lat,p_lng,p_age_ms) 가 아니다 — 신원을 실어 나를 인자가 생겼는가=' || coalesce(v_txt,'(없음)'); end if;

  delete from realtime.messages where topic = v_topic;
  perform set_config('request.jwt.claim.sub', v_runner::text, true);
  select club_pack_publish(v_ses, 37.5100, 126.9900) into v_j;
  if (v_j->>'ok')::boolean is not true then v_bad := v_bad || ' 러너의 발행이 거절됐다=' || coalesce(v_j->>'refusal','(null)'); end if;
  perform set_config('request.jwt.claim.sub', v_comp::text, true);
  select club_pack_publish(v_ses, 37.5200, 126.9800) into v_j;
  if (v_j->>'ok')::boolean is not true then v_bad := v_bad || ' 동반 보호자의 발행이 거절됐다=' || coalesce(v_j->>'refusal','(null)'); end if;
  perform set_config('request.jwt.claim.sub', '', true);

  select count(*) into v_n from realtime.messages
   where topic = v_topic and payload->>'profileId' = v_runner::text and payload->>'name' = 'pb_runner';
  if v_n <> 1 then v_bad := v_bad || ' 러너의 행이 자기 uid·자기 이름을 달고 있지 않다=' || v_n; end if;
  select count(*) into v_n from realtime.messages
   where topic = v_topic and payload->>'profileId' = v_comp::text and payload->>'name' = 'pb_comp';
  if v_n <> 1 then v_bad := v_bad || ' 동반 보호자의 행이 자기 uid·자기 이름을 달고 있지 않다=' || v_n; end if;
  select count(distinct payload->>'profileId') into v_n from realtime.messages where topic = v_topic;
  if v_n <> 2 then v_bad := v_bad || ' 두 발행자의 profileId 가 서로 다르지 않다(상수로 고정됐는가)=' || v_n; end if;
  if v_bad = '' then call _pass('pkpub','0160-A2 신원은 구조적이다(codex #4) — 서로 다른 두 발행자의 행이 각자의 uid 와 각자의 profiles 이름을 달고 나가고, 시그니처는 (p_session,p_lat,p_lng,p_age_ms) 라 신원을 실어 나를 인자가 아예 없다. 0159 에서는 페이로드 전체가 클라이언트 주장이었고, 체크인한 공격자가 남의 profileId·이름으로 더 최신 시각을 찍을 수 있었다');
  else v_msg := v_bad; call _fail('pkpub','0160-A2 신원 구조', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-A3] 당사자 게이트 — 거절 어휘와 순서. Party gate BEFORE state gate: a stranger and a
  --           NONEXISTENT session get the identical answer, so this RPC is never an existence
  --           oracle over session ids.
  -- 🔴 The DIVERGENCE-ZONE arm is the load-bearing one and the only fixture that can see the
  --    membership CONJUNCTION. `attendance='checked_in'` with `checked_in_at` NULL satisfies the
  --    word and not the stamp; a rule testing only one half admits it. A fixture where both
  --    halves agree cannot distinguish the two candidate rules at all.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  perform set_config('request.jwt.claim.sub', '', true);
  select club_pack_publish(v_ses, 37.50, 127.00) into v_j;
  if v_j->>'refusal' is distinct from 'not_signed_in'
    then v_bad := v_bad || ' 로그인 없는 호출이 not_signed_in 이 아니다=' || coalesce(v_j->>'refusal','(null)'); end if;
  if (v_j->>'ok')::boolean is not false then v_bad := v_bad || ' 로그인 없는 호출이 ok=true'; end if;

  perform set_config('request.jwt.claim.sub', v_stranger::text, true);
  select club_pack_publish(v_ses, 37.50, 127.00) into v_j;
  if v_j->>'refusal' is distinct from 'not_checked_in'
    then v_bad := v_bad || ' 무관한 사용자가 not_checked_in 이 아니다=' || coalesce(v_j->>'refusal','(null)'); end if;
  -- and the SAME answer for a session that does not exist — party before state, no oracle
  select club_pack_publish(gen_random_uuid(), 37.50, 127.00) into v_j;
  if v_j->>'refusal' is distinct from 'not_checked_in'
    then v_bad := v_bad || ' 존재하지 않는 세션이 not_checked_in 과 다른 답을 준다(존재 오라클)=' || coalesce(v_j->>'refusal','(null)'); end if;

  perform set_config('request.jwt.claim.sub', v_rsvp::text, true);
  select club_pack_publish(v_ses, 37.50, 127.00) into v_j;
  if v_j->>'refusal' is distinct from 'not_checked_in'
    then v_bad := v_bad || ' 참가만 하고 체크인 안 한 사람이 not_checked_in 이 아니다=' || coalesce(v_j->>'refusal','(null)'); end if;

  perform set_config('request.jwt.claim.sub', v_zone::text, true);
  select club_pack_publish(v_ses, 37.50, 127.00) into v_j;
  if v_j->>'refusal' is distinct from 'not_checked_in'
    then v_bad := v_bad || ' 🔴 발산 구역(attendance=checked_in, 스탬프 NULL)이 발행에 성공한다 — 멤버십 술어가 두 반쪽 중 하나만 본다=' || coalesce(v_j->>'refusal','(null)'); end if;
  perform set_config('request.jwt.claim.sub', '', true);

  -- nothing above may have landed a row
  select count(*) into v_n from realtime.messages
   where topic = v_topic and payload->>'profileId' in (v_stranger::text, v_rsvp::text, v_zone::text);
  if v_n <> 0 then v_bad := v_bad || ' 거절된 호출이 행을 남겼다=' || v_n; end if;
  if v_bad = '' then call _pass('pkpub','0160-A3 당사자 게이트 — 로그인 없음=not_signed_in, 무관한 사용자·없는 세션·참가만 한 사람·**발산 구역(attendance=checked_in 인데 checked_in_at 이 NULL)** 전부 not_checked_in, 그리고 거절은 행을 하나도 남기지 않는다. 없는 세션이 무관한 사용자와 같은 답을 준다는 것이 당사자-먼저 순서의 관측 가능한 결과다');
  else v_msg := v_bad; call _fail('pkpub','0160-A3 당사자 게이트', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-A8] 🔴 THE ROSTER **IS** THE WRITE SET — ASSERTED AS ONE CONJUNCTION, NOT TWO HALVES.
  --           0159 §C claims 「the row set is exactly the set §B admits to WRITE」. That sentence
  --           is about a pair of predicates AGREEING, and two pins that separately assert
  --           「the roster omits X」 and 「publish refuses X」 do not establish it: each stays green
  --           while the other's predicate drifts, and the claim they jointly support is the one
  --           nobody is measuring. This pin drives BOTH doors against the SAME row in the same
  --           breath, which is the only shape whose failure message can say 「they diverged」.
  -- 🔴 The row is the divergence-zone fixture (`attendance='checked_in'`, `checked_in_at` NULL) —
  --    the one shape on which the two candidate predicates disagree. On any other fixture this
  --    pin is satisfied by two rules that are not the same rule (the fixture-agreement law).
  -- ⚠ THE POSITIVE HALF IS NOT DECORATION. Without it, 「absent from the roster AND refused
  --    publish」 is satisfied perfectly by a roster that returns nobody and a publisher that
  --    refuses everybody — the map dead rather than exact. So a genuinely checked-in member must
  --    be present in the roster AND publish successfully, in the same two lines.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  delete from realtime.messages where topic = v_topic;
  delete from club_pack_publish_marks;
  v_j := club_pack_map_roster(v_ses);
  if (v_j->>'windowOpen')::boolean is not true
    then v_bad := v_bad || ' 이 픽스처의 창이 닫혀 있다(로스터가 사람을 안 낸다 — 핀이 다른 상태를 잰다)'; end if;
  -- ⓐ the divergence row: absent from the roster …
  select count(*) into v_n from jsonb_array_elements(v_j->'people') e
   where e->>'profileId' = v_zone::text;
  if v_n <> 0 then v_bad := v_bad || ' 발산 구역 행이 로스터에 나온다=' || v_n; end if;
  -- … AND refused publish, same row, same breath
  perform set_config('request.jwt.claim.sub', v_zone::text, true);
  select club_pack_publish(v_ses, 37.50, 127.00) into v_j;
  if v_j->>'refusal' is distinct from 'not_checked_in'
    then v_bad := v_bad || ' 🔴 로스터에 없는 행이 발행에는 성공한다 — 로스터와 쓰기 집합이 갈렸다(0159 §C 의 문장이 거짓이 된다)=' || coalesce(v_j->>'refusal','(null)'); end if;
  -- ⓑ the control: a genuinely checked-in member is on the roster AND publishes
  perform set_config('request.jwt.claim.sub', v_guest::text, true);
  select club_pack_publish(v_ses, 37.5045, 126.9955) into v_j;
  if (v_j->>'ok')::boolean is not true
    then v_bad := v_bad || ' 통제 실패: 진짜 체크인한 참가자도 발행 못 한다(둘 다 거절하는 세계에서는 위 팔이 아무것도 안 잰다)=' || coalesce(v_j->>'refusal','(null)'); end if;
  perform set_config('request.jwt.claim.sub', '', true);
  v_j := club_pack_map_roster(v_ses);
  select count(*) into v_n from jsonb_array_elements(v_j->'people') e
   where e->>'profileId' = v_guest::text;
  if v_n <> 1 then v_bad := v_bad || ' 통제 실패: 발행에 성공한 참가자가 로스터에 없다=' || v_n; end if;
  select count(*) into v_n from realtime.messages where topic = v_topic;
  if v_n <> 1 then v_bad := v_bad || ' 성공 1회·거절 1회인데 남은 행이 1개가 아니다=' || v_n; end if;
  if v_bad = '' then call _pass('pkpub','0160-A8 로스터 = 쓰기 집합, 하나의 연언으로 — 발산 구역 행(attendance=checked_in, 스탬프 NULL)은 로스터에도 없고 발행도 거절된다(같은 행, 같은 호흡). 통제: 진짜 체크인한 참가자는 로스터에 있고 발행에도 성공한다 — 이 팔이 없으면 「아무도 못 내고 아무도 못 쓴다」가 이 핀을 완벽히 통과한다. 0159 §C 의 「행 집합이 정확히 쓰기 집합이다」는 두 술어가 **일치한다**는 문장이고, 따로 선 두 핀은 그 문장을 세우지 못한다');
  else v_msg := v_bad; call _fail('pkpub','0160-A8 로스터=쓰기 집합', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-A4] 🔴 THE WINDOW IS RE-DECIDED ON EVERY CALL — codex #2's answer, made observable.
  --           The same caller, the same arguments, publishes; the host taps 세션 종료; the very
  --           next call is refused. Under 0159 that second call went through a socket whose
  --           authorization had been decided at join time and was never asked again.
  --           Both of the window's affirmative end signals are driven: 세션 종료 (status) and
  --           러닝 종료 (`bookings.run_ended_at` on a club booking — one writer, 0144:456).
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  delete from realtime.messages where topic = v_topic;
  delete from club_pack_publish_marks;                 -- this pin owns the window, not the throttle

  perform set_config('request.jwt.claim.sub', v_host::text, true);
  select club_pack_publish(v_ses, 37.51, 126.99) into v_j;
  if (v_j->>'ok')::boolean is not true then v_bad := v_bad || ' 창이 열린 상태에서 호스트가 발행 못 한다=' || coalesce(v_j->>'refusal','(null)'); end if;

  update club_sessions set status = 'done' where id = v_ses;
  delete from club_pack_publish_marks;
  select club_pack_publish(v_ses, 37.51, 126.99) into v_j;
  if v_j->>'refusal' is distinct from 'window_closed'
    then v_bad := v_bad || ' 세션 종료 뒤 바로 다음 호출이 window_closed 가 아니다=' || coalesce(v_j->>'refusal','(null)'); end if;
  update club_sessions set status = 'open' where id = v_ses;

  update bookings set run_ended_at = now() where id = v_bk;
  delete from club_pack_publish_marks;
  select club_pack_publish(v_ses, 37.51, 126.99) into v_j;
  if v_j->>'refusal' is distinct from 'window_closed'
    then v_bad := v_bad || ' 러닝 종료 스탬프 뒤에도 발행이 통과한다=' || coalesce(v_j->>'refusal','(null)'); end if;
  update bookings set run_ended_at = null where id = v_bk;

  -- the reverse control: undoing both restores publishing, so this pin measures the window and
  -- not some other refusal that happens to fire
  delete from club_pack_publish_marks;
  select club_pack_publish(v_ses, 37.51, 126.99) into v_j;
  if (v_j->>'ok')::boolean is not true
    then v_bad := v_bad || ' 되돌렸는데 발행이 안 돌아온다(이 핀이 창이 아니라 다른 걸 재고 있다)=' || coalesce(v_j->>'refusal','(null)'); end if;
  perform set_config('request.jwt.claim.sub', '', true);

  select count(*) into v_n from realtime.messages where topic = v_topic;
  if v_n <> 2 then v_bad := v_bad || ' 성공 2회·거절 2회인데 남은 행이 2개가 아니다=' || v_n; end if;
  if v_bad = '' then call _pass('pkpub','0160-A4 창은 매 호출 다시 결정된다(codex #2) — 같은 발행자가 같은 인자로: 열림→ok, 세션 종료 직후 호출→window_closed, 러닝 종료 스탬프 뒤→window_closed, 둘 다 되돌리면 다시 ok. 남은 행은 성공한 두 번뿐. 0159 의 소켓은 조인 때 한 번 승인받고 다시 묻지 않았으므로 이 두 거절이 존재할 수 없었다');
  else v_msg := v_bad; call _fail('pkpub','0160-A4 창 재평가', v_msg); end if;

  -- ═══════════ [0160-A5] 좌표 가드 — 못 읽은 위치를 지도에 찍지 않는다 ═══════════
  -- (0,0) is refused by name: Null Island is not a coordinate this product produces, it is the
  -- commonest spelling of 「the device had no fix」, and drawing it puts a dot in the Gulf of
  -- Guinea. The positive control at the end is what stops a guard that refuses everything.
  v_bad := '';
  delete from realtime.messages where topic = v_topic;
  delete from club_pack_publish_marks;
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  select club_pack_publish(v_ses, 0, 0) into v_j;
  if v_j->>'refusal' is distinct from 'bad_position' then v_bad := v_bad || ' (0,0) 이 bad_position 이 아니다=' || coalesce(v_j->>'refusal','(null)'); end if;
  select club_pack_publish(v_ses, null, 126.99) into v_j;
  if v_j->>'refusal' is distinct from 'bad_position' then v_bad := v_bad || ' lat NULL 이 bad_position 이 아니다=' || coalesce(v_j->>'refusal','(null)'); end if;
  select club_pack_publish(v_ses, 37.5, null) into v_j;
  if v_j->>'refusal' is distinct from 'bad_position' then v_bad := v_bad || ' lng NULL 이 bad_position 이 아니다=' || coalesce(v_j->>'refusal','(null)'); end if;
  select club_pack_publish(v_ses, 91, 126.99) into v_j;
  if v_j->>'refusal' is distinct from 'bad_position' then v_bad := v_bad || ' lat 91 이 bad_position 이 아니다=' || coalesce(v_j->>'refusal','(null)'); end if;
  select club_pack_publish(v_ses, -91, 126.99) into v_j;
  if v_j->>'refusal' is distinct from 'bad_position' then v_bad := v_bad || ' lat -91 이 bad_position 이 아니다=' || coalesce(v_j->>'refusal','(null)'); end if;
  select club_pack_publish(v_ses, 37.5, 181) into v_j;
  if v_j->>'refusal' is distinct from 'bad_position' then v_bad := v_bad || ' lng 181 이 bad_position 이 아니다=' || coalesce(v_j->>'refusal','(null)'); end if;
  select club_pack_publish(v_ses, 37.5, -181) into v_j;
  if v_j->>'refusal' is distinct from 'bad_position' then v_bad := v_bad || ' lng -181 이 bad_position 이 아니다=' || coalesce(v_j->>'refusal','(null)'); end if;
  -- ⚠ THE CONTROL, and it is not optional: a guard that refuses every coordinate passes all seven
  --   arms above and ships a map that never draws a dot. A real Banpo coordinate must go through,
  --   and so must the two extremes that are legal (90 / 180 are on the boundary, not past it).
  select club_pack_publish(v_ses, 37.5045, 126.9955) into v_j;
  if (v_j->>'ok')::boolean is not true then v_bad := v_bad || ' 정상 좌표가 거절된다(좌표 가드가 전부를 막는다)=' || coalesce(v_j->>'refusal','(null)'); end if;
  delete from club_pack_publish_marks;
  select club_pack_publish(v_ses, 90, 180) into v_j;
  if (v_j->>'ok')::boolean is not true then v_bad := v_bad || ' 경계값 (90,180) 이 거절된다=' || coalesce(v_j->>'refusal','(null)'); end if;
  perform set_config('request.jwt.claim.sub', '', true);
  select count(*) into v_n from realtime.messages where topic = v_topic;
  if v_n <> 2 then v_bad := v_bad || ' 거절 7회·성공 2회인데 남은 행이 2개가 아니다=' || v_n; end if;
  if v_bad = '' then call _pass('pkpub','0160-A5 좌표 가드 — 정확히 (0,0)·lat NULL·lng NULL·|lat|>90·|lng|>180 은 bad_position 이고 행을 남기지 않는다. 통제: 실제 반포 좌표와 경계값 (90,180) 은 통과한다(전부 거절하는 가드는 위 일곱 팔을 완벽히 통과하면서 점을 하나도 안 찍는 지도를 만든다)');
  else v_msg := v_bad; call _fail('pkpub','0160-A5 좌표 가드', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-A6] 간격 제한 — 한 문장짜리 조건부 upsert 다. `now()` is frozen in this block, so the
  --           「wait and it works again」 half is exercised by REWINDING the mark, never by
  --           sleeping. A dedicated user owns this pin so no neighbouring publish can move it.
  -- 🔴 [0160 item 1a] The throttle is `insert … on conflict … do update … where m.last_at <=
  --    now() - interval '2 seconds'` followed by `if not found`, taking the row lock BEFORE the
  --    broadcast. The read-then-write shape this replaced was bypassable by exactly the adversary
  --    a throttle exists for — N simultaneous requests all read the same committed mark and all
  --    pass. **This harness is one transaction on one connection and structurally cannot drive
  --    that race** (see limitation ② in the header); what it CAN drive, and does below, is the
  --    serial case: the second call inside the window is refused and the `where` clause is the
  --    only thing that refuses it, so deleting that clause reddens this pin.
  -- ⚠ The 「a refusal does not stamp」 arm is the one that matters operationally: if a refused
  --   call wrote the mark, a client with a bad fix would throttle ITSELF out of the map. It holds
  --   for the four gates ABOVE the throttle (①~④). A `not_delivered` — which is BELOW it — does
  --   consume a slot, deliberately: the next client tick is 3 s away so nothing is lost, and the
  --   opposite trade (a failed publish leaving no mark) is unbounded retry.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  delete from realtime.messages where topic = v_topic;
  delete from club_pack_publish_marks;
  perform set_config('request.jwt.claim.sub', v_thr::text, true);

  select count(*) into v_n from club_pack_publish_marks where profile_id = v_thr;
  if v_n <> 0 then v_bad := v_bad || ' 시작부터 표시 행이 있다=' || v_n; end if;

  select club_pack_publish(v_ses, 37.505, 126.995) into v_j;
  if (v_j->>'ok')::boolean is not true then v_bad := v_bad || ' 첫 발행이 거절됐다=' || coalesce(v_j->>'refusal','(null)'); end if;
  select m.last_at into v_last from club_pack_publish_marks m where m.profile_id = v_thr;
  if v_last is distinct from now() then v_bad := v_bad || ' 성공 뒤 표시가 지금으로 안 찍혔다=' || coalesce(v_last::text,'(없음)'); end if;

  select club_pack_publish(v_ses, 37.506, 126.996) into v_j;
  if v_j->>'refusal' is distinct from 'too_fast'
    then v_bad := v_bad || ' 같은 트랜잭션의 두 번째 호출이 too_fast 가 아니다=' || coalesce(v_j->>'refusal','(null)'); end if;

  -- rewind 3 s (> the 2 s window) and the same caller is admitted again — a cycle, not a one-shot
  update club_pack_publish_marks set last_at = now() - interval '3 seconds' where profile_id = v_thr;
  -- ⚠ first, a REFUSED call in that state must not stamp the mark
  select club_pack_publish(v_ses, 0, 0) into v_j;
  if v_j->>'refusal' is distinct from 'bad_position' then v_bad := v_bad || ' 되감은 뒤 (0,0) 이 bad_position 이 아니다=' || coalesce(v_j->>'refusal','(null)'); end if;
  select m.last_at into v_last from club_pack_publish_marks m where m.profile_id = v_thr;
  if v_last is distinct from now() - interval '3 seconds'
    then v_bad := v_bad || ' 거절이 표시를 갱신했다(나쁜 위치 하나로 자기 자신을 지도에서 밀어낸다)=' || coalesce(v_last::text,'(없음)'); end if;

  select club_pack_publish(v_ses, 37.507, 126.997) into v_j;
  if (v_j->>'ok')::boolean is not true then v_bad := v_bad || ' 3초 되감은 뒤에도 통과 못 한다=' || coalesce(v_j->>'refusal','(null)'); end if;
  select m.last_at into v_last from club_pack_publish_marks m where m.profile_id = v_thr;
  if v_last is distinct from now() then v_bad := v_bad || ' 재통과 뒤 표시가 다시 안 찍혔다=' || coalesce(v_last::text,'(없음)'); end if;
  select count(*) into v_n from club_pack_publish_marks where profile_id = v_thr;
  if v_n <> 1 then v_bad := v_bad || ' 표시 행이 발행자당 1개가 아니다(upsert 가 아니다)=' || v_n; end if;
  perform set_config('request.jwt.claim.sub', '', true);

  select count(*) into v_n from realtime.messages where topic = v_topic;
  if v_n <> 2 then v_bad := v_bad || ' 성공 2회·거절 2회인데 남은 행이 2개가 아니다=' || v_n; end if;
  if v_bad = '' then call _pass('pkpub','0160-A6 간격 제한 2초 — 첫 발행 통과하며 표시를 찍고, 같은 트랜잭션의 두 번째는 too_fast 이며, 표시를 3초 되감으면 같은 발행자가 다시 통과한다(한 번 쓰고 마는 게 아니라 주기다). ⚠ 거절(bad_position)은 표시를 갱신하지 않는다 — 갱신했다면 위치를 한 번 못 읽은 클라이언트가 스스로를 지도에서 밀어낸다. 표시는 발행자당 정확히 한 행(upsert)');
  else v_msg := v_bad; call _fail('pkpub','0160-A6 간격 제한', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-A9] 🔴 `at` 은 「지금」이 아니라 「이 좌표를 읽은 때」다 — 과거로만 움직이는 clamp.
  --           (0160 item 1b.) The server stamps every payload now, which is the honest fix for
  --           codex #4's timestamp half — and it created a NEW dishonesty: a GPS fix that was
  --           110 s old was being rendered at full freshness, because the stamp said 「now」 and
  --           the client's own comment argued it did not. `p_age_ms` closes that.
  -- 🔴 **THE CLAMP IS ONE-SIDED ON PURPOSE, and that is the security property.** `least(greatest(
  --    p_age_ms, 0), 120000)` can only move `at` INTO THE PAST. A liar can make themselves look
  --    staler (their own marker fades — self-harm, and the map is honest about it); nobody can
  --    make themselves look NEWER than the instant the server ran, so the forged-future-stamp
  --    attack that server-side stamping killed stays dead. Both ends of the clamp are pinned
  --    below, because a clamp with one live end is a clamp someone will later 「simplify」.
  -- ⚠ `now()` is frozen for this whole transaction, which is what makes 「exactly 5 s ago」 a
  --   measurable claim rather than a tolerance. The comparison is against
  --   `date_trunc('milliseconds', …)` because the payload spells the instant to milliseconds.
  -- ⚠ A dedicated user owns this pin, and BOTH the topic and the mark are cleared before each
  --   call — five publishes inside one frozen-`now()` transaction are otherwise five `too_fast`
  --   refusals, and reading 「the row I just wrote」 out of five rows would mean matching on a
  --   float's jsonb spelling, which is a pin about formatting.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  perform set_config('request.jwt.claim.sub', v_age::text, true);

  -- ⓐ an honest 5 s-old fix is stamped 5 s old
  delete from realtime.messages where topic = v_topic; delete from club_pack_publish_marks;
  select club_pack_publish(v_ses, 37.5001, 126.9901, 5000) into v_j;
  if (v_j->>'ok')::boolean is not true then v_bad := v_bad || ' age=5000 발행이 거절됐다=' || coalesce(v_j->>'refusal','(null)'); end if;
  select m.payload into v_p from realtime.messages m where m.topic = v_topic;
  if v_p is null then v_bad := v_bad || ' age=5000 의 행을 못 찾았다';
  elsif (v_p->>'at')::timestamptz is distinct from date_trunc('milliseconds', now() - interval '5 seconds')
    then v_bad := v_bad || ' age=5000 인데 at 이 5초 전이 아니다=' || coalesce(v_p->>'at','(null)'); end if;

  -- ⓑ the UPPER clamp: 999999 ms is 16 minutes and must land at exactly 120 s, not 16 minutes
  delete from realtime.messages where topic = v_topic; delete from club_pack_publish_marks;
  select club_pack_publish(v_ses, 37.5002, 126.9902, 999999) into v_j;
  if (v_j->>'ok')::boolean is not true then v_bad := v_bad || ' age=999999 발행이 거절됐다=' || coalesce(v_j->>'refusal','(null)'); end if;
  select m.payload into v_p from realtime.messages m where m.topic = v_topic;
  if v_p is null then v_bad := v_bad || ' age=999999 의 행을 못 찾았다';
  elsif (v_p->>'at')::timestamptz is distinct from date_trunc('milliseconds', now() - interval '120 seconds')
    then v_bad := v_bad || ' 상한 clamp 가 없다 — age=999999 가 120초로 안 잘렸다=' || coalesce(v_p->>'at','(null)'); end if;

  -- ⓒ the LOWER clamp: a negative age is the future-stamp attack and must land at now()
  delete from realtime.messages where topic = v_topic; delete from club_pack_publish_marks;
  select club_pack_publish(v_ses, 37.5003, 126.9903, -50) into v_j;
  if (v_j->>'ok')::boolean is not true then v_bad := v_bad || ' age=-50 발행이 거절됐다=' || coalesce(v_j->>'refusal','(null)'); end if;
  select m.payload into v_p from realtime.messages m where m.topic = v_topic;
  if v_p is null then v_bad := v_bad || ' age=-50 의 행을 못 찾았다';
  elsif (v_p->>'at')::timestamptz is distinct from date_trunc('milliseconds', now())
    then v_bad := v_bad || ' 🔴 음수 age 가 at 을 미래로 밀었다(하한 clamp 가 없다)=' || coalesce(v_p->>'at','(null)'); end if;

  -- ⓓ NULL is absorbed to 0 (Postgres greatest/least ignore NULL args) — the shape a client
  --   sending an unmeasured age produces
  delete from realtime.messages where topic = v_topic; delete from club_pack_publish_marks;
  select club_pack_publish(v_ses, 37.5004, 126.9904, null) into v_j;
  if (v_j->>'ok')::boolean is not true then v_bad := v_bad || ' age=NULL 발행이 거절됐다=' || coalesce(v_j->>'refusal','(null)'); end if;
  select m.payload into v_p from realtime.messages m where m.topic = v_topic;
  if v_p is null then v_bad := v_bad || ' age=NULL 의 행을 못 찾았다';
  elsif (v_p->>'at')::timestamptz is distinct from date_trunc('milliseconds', now())
    then v_bad := v_bad || ' age=NULL 이 at 을 흔들었다=' || coalesce(v_p->>'at','(null)'); end if;

  -- ⓔ THE DEFAULT. Call sites that do not pass an age must behave as age 0, and this is also the
  --   arm that proves the argument HAS a default at all (a required fourth argument would break
  --   every three-argument caller, and this call would fail to resolve).
  delete from realtime.messages where topic = v_topic; delete from club_pack_publish_marks;
  select club_pack_publish(v_ses, 37.5005, 126.9905) into v_j;
  if (v_j->>'ok')::boolean is not true then v_bad := v_bad || ' 인자 생략(기본값) 발행이 거절됐다=' || coalesce(v_j->>'refusal','(null)'); end if;
  select m.payload into v_p from realtime.messages m where m.topic = v_topic;
  if v_p is null then v_bad := v_bad || ' 기본값 호출의 행을 못 찾았다';
  elsif (v_p->>'at')::timestamptz is distinct from date_trunc('milliseconds', now())
    then v_bad := v_bad || ' 기본값이 0 이 아니다=' || coalesce(v_p->>'at','(null)'); end if;
  perform set_config('request.jwt.claim.sub', '', true);

  select count(*) into v_n from realtime.messages where topic = v_topic;
  if v_n <> 1 then v_bad := v_bad || ' 마지막 발행 뒤 남은 행이 1개가 아니다=' || v_n; end if;
  if v_bad = '' then call _pass('pkpub','0160-A9 p_age_ms 는 과거로만 움직이는 clamp — 5000ms 는 정확히 5초 전, 999999ms 는 상한에 걸려 정확히 120초 전, **-50ms 는 지금**(미래로 못 민다 — 위조된 미래 시각 공격이 여기서 죽는다), NULL 은 0 으로 흡수되고, 인자를 생략하면 기본값 0. now() 가 트랜잭션 내내 얼어 있으므로 「정확히」가 허용오차가 아니라 측정이다');
  else v_msg := v_bad; call _fail('pkpub','0160-A9 age clamp', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-A7] 발행은 인자의 세션에 매인다 — 190 `0159-P3` 의 긍정 통제가 옮겨온 자리.
  --           A checked-in member of session A cannot publish into session B, and B's own
  --           checked-in host can — so the pin has a working positive arm, which the socket-side
  --           P3 lost when the write door was removed. The rows are counted PER TOPIC, so a
  --           publisher that ignored `p_session` and wrote one global topic reddens here.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  delete from realtime.messages where topic in (v_topic, v_topic2);
  delete from club_pack_publish_marks;
  perform set_config('request.jwt.claim.sub', v_guest::text, true);
  select club_pack_publish(v_ses2, 37.50, 127.00) into v_j;
  if v_j->>'refusal' is distinct from 'not_checked_in'
    then v_bad := v_bad || ' 이 세션의 게스트가 옆 세션에 발행한다=' || coalesce(v_j->>'refusal','(null)'); end if;
  perform set_config('request.jwt.claim.sub', v_host::text, true);
  select club_pack_publish(v_ses2, 37.55, 126.95) into v_j;
  if (v_j->>'ok')::boolean is not true
    then v_bad := v_bad || ' 옆 세션에 체크인한 호스트가 발행 못 한다(긍정 통제)=' || coalesce(v_j->>'refusal','(null)'); end if;
  perform set_config('request.jwt.claim.sub', '', true);
  select count(*) into v_n  from realtime.messages where topic = v_topic2;
  select count(*) into v_n2 from realtime.messages where topic = v_topic;
  if v_n <> 1 then v_bad := v_bad || ' 옆 세션 토픽의 행이 1개가 아니다=' || v_n; end if;
  if v_n2 <> 0 then v_bad := v_bad || ' 옆 세션에 발행했는데 이 세션 토픽에 행이 생겼다(토픽이 인자에서 안 나온다)=' || v_n2; end if;
  if v_bad = '' then call _pass('pkpub','0160-A7 발행은 인자의 세션에 매인다 — 이 세션의 게스트가 옆 세션에 발행하면 not_checked_in, 옆 세션에 체크인한 호스트는 통과(긍정 통제), 그리고 행은 pack-<그 세션> 토픽에만 생긴다');
  else v_msg := v_bad; call _fail('pkpub','0160-A7 토픽 결합', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-B1] 🔴 THE BOUNDARY, AND THE PAIR THAT MAKES IT MEAN SOMETHING. As the `authenticated`
  --           ROLE, carrying the JWT of a genuinely checked-in participant:
  --             ⓐ a direct INSERT into `realtime.messages` on a pack topic is REFUSED — 0160
  --               dropped `pack channel write` and NO policy admits it. Deny-by-no-policy is the
  --               one shape a cached socket join cannot re-open (codex #2).
  --             ⓑ the SAME caller, in the same role, publishes successfully through the RPC.
  --           ⓑ is not decoration: without it, ⓐ is equally satisfied by a database where
  --           nothing works at all, and the map would be dead rather than hardened.
  -- ⚠ ⓐ is also the arm that catches 「someone re-adds a permissive INSERT policy」, which is a
  --   thing a later slice can do without touching a single line of 0160.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  delete from realtime.messages where topic = v_topic;
  delete from club_pack_publish_marks;
  perform set_config('realtime.topic', v_topic, true);
  perform set_config('request.jwt.claim.sub', v_guest::text, true);
  set local role authenticated;
  begin
    insert into realtime.messages (topic, extension, payload, event, private)
      values (v_topic, 'broadcast', '{"profileId":"forged","lat":37.5,"lng":127.0}'::jsonb, 'pos', true);
    v_bad := v_bad || ' 체크인한 참가자의 소켓 INSERT 가 통과했다(팩 토픽에 INSERT 정책이 다시 생겼다)';
  exception when insufficient_privilege or check_violation then null;
  end;
  reset role;

  perform set_config('request.jwt.claim.sub', v_guest::text, true);
  set local role authenticated;
  begin
    select club_pack_publish(v_ses, 37.5045, 126.9955) into v_j;
  exception when others then
    v_j := null; v_txt := sqlstate || ' ' || sqlerrm;
  end;
  reset role;
  if v_j is null then v_bad := v_bad || ' authenticated 롤에서 club_pack_publish 호출이 예외로 죽었다 [' || coalesce(v_txt,'?') || ']';
  elsif (v_j->>'ok')::boolean is not true then v_bad := v_bad || ' authenticated 롤의 발행이 거절됐다=' || coalesce(v_j->>'refusal','(null)'); end if;
  perform set_config('request.jwt.claim.sub', '', true);

  select count(*) into v_n from realtime.messages where topic = v_topic;
  if v_n <> 1 then v_bad := v_bad || ' 경계에서 남은 행이 1개(RPC 것)가 아니다=' || v_n; end if;
  select count(*) into v_n from realtime.messages where topic = v_topic and payload->>'profileId' = 'forged';
  if v_n <> 0 then v_bad := v_bad || ' 위조 profileId 행이 살아남았다=' || v_n; end if;
  if v_bad = '' then call _pass('pkpub','0160-B1 경계 실측(authenticated) — 진짜 체크인한 참가자조차 realtime.messages 에 직접 INSERT 하지 못하고(0160 이 pack channel write 를 지웠으므로 받아줄 정책이 없다), **같은 사용자가 같은 롤에서 club_pack_publish 로는 발행에 성공한다**. 문이 닫혔다는 팔과 기능이 살아 있다는 팔이 둘 다 있어야 이 핀이 무언가를 재는 것이다');
  else v_msg := v_bad; call _fail('pkpub','0160-B1 경계 authenticated', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-S1] SOURCE — the shape of the two things this harness cannot execute. 0160 §A inserts
  --           the broadcast row ITSELF (`realtime.send` swallows every error — production prosrc,
  --           measured 2026-08-31) and converts an INSERT failure into the TYPED refusal
  --           `not_delivered`. The shim's `realtime.messages` is unpartitioned, so **the INSERT
  --           never fails here and the handler never runs** — its existence is asserted from
  --           source because behaviour cannot reach it (header limitation ①). Same for the
  --           throttle's atomic shape: this file cannot run two concurrent sessions, so the
  --           `on conflict … where` form is asserted from source (header limitation ②).
  -- ⚠ Comments are STRIPPED first. `prosrc` is our code AND our prose, and 0160's own body
  --   comments name `realtime.send`, `not_delivered` and the whole throttle argument at length —
  --   an un-stripped match would be satisfied by the EXPLANATION, so the better the documentation
  --   the more certainly the check passes. That is the comment-matching law, and it has cost this
  --   repo three separate pins.
  -- ⚠ NO-SOURCE arm: a regex that matches nothing on an absent function is a vacuous green, the
  --   most expensive kind. Absence fails loudly here.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  select regexp_replace(p.prosrc, '--[^\n]*', '', 'g') into v_src
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_pack_publish';
  if v_src is null then
    v_bad := v_bad || ' NO-SOURCE(club_pack_publish) — 함수가 없다(아래 팔들이 공허하게 초록이 될 뻔했다)';
  else
    -- ⓐ the broadcast is this function's own INSERT, not a call into the swallowing wrapper
    if position('insert into realtime.messages' in v_src) = 0
      then v_bad := v_bad || ' 🔴 본문이 realtime.messages 에 직접 INSERT 하지 않는다(브로드캐스트가 안 나가거나, 모든 오류를 삼키는 realtime.send 로 되돌아갔다)'; end if;
    -- ⓑ … and a failed INSERT becomes a TYPED refusal with a logged cause. All three tokens, and
    --    the refusal must come AFTER the insert — a `not_delivered` that is not in the handler is
    --    not the conversion this arm is about.
    if position('when others' in v_src) = 0
      then v_bad := v_bad || ' INSERT 을 감싸는 예외 핸들러가 없다(실패가 500 으로 새어 나가 네트워크 장애와 구별되지 않는다)'; end if;
    if position('raise warning' in v_src) = 0
      then v_bad := v_bad || ' 핸들러가 원인을 로그에 남기지 않는다(조용한 catch 와 구별되는 절반이 없다)'; end if;
    if position('not_delivered' in v_src) = 0
      then v_bad := v_bad || ' 실패했을 때의 거절 어휘(not_delivered)가 없다'; end if;
    if position('insert into realtime.messages' in v_src) >= position('not_delivered' in v_src)
      then v_bad := v_bad || ' not_delivered 가 INSERT 보다 앞에 있다(핸들러의 변환이 아니다)'; end if;
    -- ⓒ the throttle is ONE conditional upsert, not read-then-write. The `where` on the conflict
    --    action is the whole property: without it every concurrent request updates and passes.
    if position('on conflict (profile_id) do update' in v_src) = 0
      then v_bad := v_bad || ' 간격 제한이 조건부 upsert 한 문장이 아니다(읽고-판단하고-쓰는 모양은 동시 요청 N 개가 전부 통과한다)'; end if;
    if position('not found' in v_src) = 0
      then v_bad := v_bad || ' upsert 가 아무 행도 안 건드린 경우(NOT FOUND)를 보지 않는다 — too_fast 가 결정되는 자리가 없다'; end if;
    -- ⓓ identity, still
    if position('auth.uid()' in v_src) = 0
      then v_bad := v_bad || ' 본문이 auth.uid() 를 읽지 않는다(신원이 어디서 오는가)'; end if;
  end if;
  if v_bad = '' then call _pass('pkpub','0160-S1 소스(주석 제거) — club_pack_publish 본문은 realtime.messages 에 **직접 INSERT** 하고(모든 오류를 삼키는 realtime.send 를 거치지 않는다), 실패를 when others → raise warning + not_delivered 라는 타입 있는 거절로 바꾸며(거절 어휘가 INSERT 뒤에 온다 = 핸들러 안이다), 간격 제한은 on conflict … do update + NOT FOUND 한 문장이고, 신원은 auth.uid() 에서 온다. 이 네 가지 중 두 가지(핸들러·동시성)는 이 하네스가 **실행할 수 없어서** 소스로 재는 것이다 — 파일 머리의 한계 ①②. NO-SOURCE 팔로 부재는 시끄럽게 실패한다');
  else v_msg := v_bad; call _fail('pkpub','0160-S1 소스', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-W1] ACL 과 형상 — 0160 §F 가 apply 때 재는 것을 상시 핀으로도. A property checked at
  --           apply and never pinned is protected exactly until someone recreates the function.
  -- ⚠ Every arm is `is distinct from`: `has_function_privilege` can answer NULL and plpgsql
  --   skips an IF on NULL, so a bare `if has_*` is silent in exactly the case this pin is for.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'club_pack_publish'
     and p.prosecdef and coalesce(array_to_string(p.proconfig,','),'') like '%pg_temp%';
  if v_n <> 1 then v_bad := v_bad || ' club_pack_publish 가 definer + 본문 search_path 가 아니다=' || v_n; end if;
  if has_function_privilege('authenticated','club_pack_publish(uuid,double precision,double precision,integer)','execute') is distinct from true
    then v_bad := v_bad || ' authenticated 가 club_pack_publish 를 못 부른다(발행이 죽는다)'; end if;
  if has_function_privilege('service_role','club_pack_publish(uuid,double precision,double precision,integer)','execute') is distinct from true
    then v_bad := v_bad || ' service_role 이 club_pack_publish 를 못 부른다'; end if;
  if has_function_privilege('anon','club_pack_publish(uuid,double precision,double precision,integer)','execute') is distinct from false
    then v_bad := v_bad || ' anon 이 club_pack_publish 를 부를 수 있다'; end if;
  if has_function_privilege('public','club_pack_publish(uuid,double precision,double precision,integer)','execute') is distinct from false
    then v_bad := v_bad || ' PUBLIC 이 club_pack_publish 를 부를 수 있다(부분 적용 시 definer 가 PUBLIC 으로 태어나는 클래스)'; end if;
  -- the ROLE boundary, not only the catalog: anon must be refused before the body is reached
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;
  begin
    perform club_pack_publish(v_ses, 37.5, 127.0);
    v_bad := v_bad || ' anon 롤이 club_pack_publish 본문에 도달했다';
  exception when insufficient_privilege then null;
    when others then v_bad := v_bad || ' anon 롤의 거절이 42501 이 아니다 [' || sqlstate || ']';
  end;
  reset role;
  if v_bad = '' then call _pass('pkpub','0160-W1 ACL — club_pack_publish 는 definer + 본문 search_path 이고, authenticated·service_role 에 열려 있으며 anon·PUBLIC 에는 닫혀 있다(카탈로그 양방향 + anon 롤 경계에서 42501). 전부 is distinct from — bare IF 는 NULL 술어에서 침묵한다');
  else v_msg := v_bad; call _fail('pkpub','0160-W1 ACL', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-W2] 표시 테이블의 봉인 — RLS on, 정책 0개, 클라이언트 권한 0.
  -- ⚠ **THE FIXTURE STARTS WHERE PRODUCTION STARTS, and that is what makes this pin worth
  --    anything.** Supabase's default privileges grant `anon`/`authenticated` full DML on every
  --    new table in `public`, and the shim mirrors that (`00_shim.sql:82-95`). So this table is
  --    born with client privileges and 0160's `revoke` genuinely removes something. An absence
  --    pin over a table that never had the grant is green for the wrong reason and licenses
  --    nothing — the 0151 lesson, one table over.
  -- ⚠ Two-sided: the boundary arm asserts an `authenticated` caller can neither READ nor WRITE
  --    it, which is the sentence that matters (a mark row leaks nothing dramatic, but a client
  --    that can UPDATE it can switch its own throttle off).
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  if (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = 'club_pack_publish_marks') is distinct from true
    then v_bad := v_bad || ' club_pack_publish_marks 에 RLS 가 없다'; end if;
  select count(*) into v_n from pg_policies where schemaname='public' and tablename='club_pack_publish_marks';
  if v_n <> 0 then v_bad := v_bad || ' 표시 테이블에 정책이 있다(정책 0개가 봉인이다)=' || v_n; end if;
  select count(*) into v_n from (
    select r.rolname, pr.priv
      from (values ('anon'),('authenticated')) r(rolname),
           (values ('select'),('insert'),('update'),('delete')) pr(priv)
     where has_table_privilege(r.rolname, 'public.club_pack_publish_marks', pr.priv) is distinct from false
  ) t;
  if v_n <> 0 then v_bad := v_bad || ' 표시 테이블에 클라이언트 권한이 남아 있다=' || v_n; end if;
  -- the control that proves the revoke removed something real rather than describing an empty
  -- world: the very same default privileges are still on an ordinary table in this schema
  if has_table_privilege('authenticated', 'public.session_people', 'select') is distinct from true
    then v_bad := v_bad || ' 통제 실패: 이 스키마의 평범한 테이블에도 기본 권한이 없다(픽스처가 운영의 출발점이 아니다)'; end if;
  perform set_config('request.jwt.claim.sub', v_thr::text, true);
  set local role authenticated;
  begin
    perform 1 from club_pack_publish_marks;
    v_bad := v_bad || ' authenticated 가 표시 테이블을 읽었다';
  exception when insufficient_privilege then null;
    when others then v_bad := v_bad || ' 표시 테이블 읽기 거절이 42501 이 아니다 [' || sqlstate || ']';
  end;
  begin
    update club_pack_publish_marks set last_at = now() - interval '1 hour';
    v_bad := v_bad || ' authenticated 가 표시 테이블을 갱신했다(스스로 간격 제한을 끌 수 있다)';
  exception when insufficient_privilege then null;
    when others then v_bad := v_bad || ' 표시 테이블 갱신 거절이 42501 이 아니다 [' || sqlstate || ']';
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  if v_bad = '' then call _pass('pkpub','0160-W2 표시 테이블 봉인 — RLS on + 정책 0개 + anon/authenticated 권한 0(카탈로그), 그리고 경계에서 authenticated 의 SELECT·UPDATE 둘 다 42501. 통제: 같은 스키마의 평범한 테이블은 여전히 기본 권한을 갖고 있으므로 이 부재는 회수의 결과이지 빈 세계의 결과가 아니다');
  else v_msg := v_bad; call _fail('pkpub','0160-W2 표시 테이블 봉인', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-M1] 로스터의 clubName 과 serverNow — codex #10 의 서버 절반과 시계 보정의 서버 절반.
  --           The masthead used to render a club name taken from a URL PARAMETER, unbound to the
  --           session, so a deep link could title somebody else's walk with any string. This is
  --           the server's own answer.
  -- ⚠ VALUE, not key presence, and measured against a SECOND club: a constant would satisfy a
  --   key-set check and a single-club fixture equally well. (190 `0159-M3` owns the frozen KEY
  --   SET; this pin owns the values, and neither is evidence for the other.)
  -- ⚠ Present whether or not the window is open — the masthead has to say something before the
  --   walk starts, which is exactly when `people` is (deliberately) empty.
  -- 🔴 **`serverNow` IS WHAT STOPS A SKEWED VIEWER SEEING AN EMPTY MAP** (0160 item 1c). Every
  --    `at` is now the SERVER's clock (0160 §A authors it), so a phone 15 s slow reads every
  --    marker as being in the future, the freshness rule refuses all of them, and the screen goes
  --    blank with nothing saying why — silent feature loss, not a cosmetic bug. The screen
  --    computes `offset = serverNow - Date.now()` per fetch, so both sides of the comparison are
  --    on the server's clock. Pinned as a VALUE equal to the transaction's frozen `now()` and in
  --    the SAME ISO-8601 UTC spelling as the payload's `at`, because a differently-spelled
  --    timestamp is a client-side parse bug wearing a correct value's costume.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  perform set_config('request.jwt.claim.sub', '', true);
  set local role anon;
  begin
    v_j := club_pack_map_roster(v_ses);
  exception when others then
    v_j := null; v_bad := v_bad || ' 익명이 로스터를 부르지 못했다 [' || sqlstate || ' ' || sqlerrm || ']';
  end;
  reset role;
  if v_j is not null then
    if v_j->>'clubName' is distinct from 'PB클럽'
      then v_bad := v_bad || ' 창이 열린 세션의 clubName 이 클럽 이름이 아니다=' || coalesce(v_j->>'clubName','(null)'); end if;
    if (v_j->>'windowOpen')::boolean is not true then v_bad := v_bad || ' 이 픽스처의 창이 닫혀 있다(핀이 다른 상태를 잰다)'; end if;
    -- serverNow: the ISO-8601 UTC(Z) spelling AND the value. `now()` is frozen for this
    -- transaction, so this is an equality, not a window.
    if v_j->>'serverNow' is null then v_bad := v_bad || ' 로스터에 serverNow 가 없다(시계가 어긋난 뷰어는 지도 전체가 조용히 빈다)';
    else
      if v_j->>'serverNow' !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'
        then v_bad := v_bad || ' serverNow 가 페이로드의 at 과 같은 ISO-8601 UTC(Z) 철자가 아니다=' || (v_j->>'serverNow'); end if;
      if (v_j->>'serverNow')::timestamptz is distinct from date_trunc('milliseconds', now())
        then v_bad := v_bad || ' serverNow 가 서버의 지금이 아니다=' || (v_j->>'serverNow'); end if;
    end if;
  end if;
  -- a DIFFERENT club's session must answer a DIFFERENT name — a constant passes without this
  v_j := club_pack_map_roster(v_ses2);
  if v_j->>'clubName' is distinct from 'PB옆클럽'
    then v_bad := v_bad || ' 옆 클럽 세션의 clubName 이 자기 클럽 이름이 아니다(상수인가)=' || coalesce(v_j->>'clubName','(null)'); end if;
  -- and it survives the window closing, unlike `people`
  update club_sessions set status = 'done' where id = v_ses;
  v_j := club_pack_map_roster(v_ses);
  if v_j->>'clubName' is distinct from 'PB클럽'
    then v_bad := v_bad || ' 창이 닫히면 clubName 이 사라진다(머리글이 시작 전에 말할 게 없어진다)=' || coalesce(v_j->>'clubName','(null)'); end if;
  if (v_j->>'windowOpen')::boolean is not false then v_bad := v_bad || ' 종료된 세션의 windowOpen 이 false 가 아니다'; end if;
  select count(*) into v_n from jsonb_array_elements(v_j->'people');
  if v_n <> 0 then v_bad := v_bad || ' 창이 닫혔는데 사람 이름이 공개된다=' || v_n; end if;
  if v_j->>'serverNow' is distinct from to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
    then v_bad := v_bad || ' 창이 닫히면 serverNow 가 사라진다(시계 보정이 종료 화면에서 죽는다)=' || coalesce(v_j->>'serverNow','(null)'); end if;
  update club_sessions set status = 'open' where id = v_ses;      -- restore
  if v_bad = '' then call _pass('pkpub','0160-M1 로스터의 clubName(codex #10) 과 serverNow(item 1c) — 익명이 부를 수 있고, clubName 값은 그 세션의 clubs.name 이며(옆 클럽 세션은 다른 이름을 답한다 — 상수가 아니다), serverNow 는 서버의 지금이자 페이로드의 at 과 같은 ISO-8601 UTC(Z) 철자이고, 둘 다 창이 닫혀도 남는다. people 은 창이 닫히면 여전히 비어 있으므로 세 결정이 뒤섞이지 않았다');
  else v_msg := v_bad; call _fail('pkpub','0160-M1 로스터 clubName·serverNow', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-M2] 🔴 뷰어 카운터 — Sean 2026-08-31 (announcer console) 「Yes, add counter」.
  --           The pilot question the map exists to answer is 「does anyone open this」, and a
  --           counter that silently counts nothing answers it 「no」 forever. So the numbers here
  --           are DELTAS this pin causes, never a state it finds: other pins in this file (and
  --           190's, in another transaction) also call the roster, and a pin reading an absolute
  --           count would be measuring the neighbourhood.
  -- ⚠ The anon/authed split is the ONLY distinction the counter draws, and both arms are needed:
  --   a counter that lands everything in one bucket passes a 「moved by 2」 check perfectly while
  --   answering none of the question that made Sean say yes (does a shared link bring in people
  --   without accounts).
  -- ⚠ **KST, stated rather than pinned.** The key's `day` is `(now() at time zone 'Asia/Seoul')`.
  --   An arm comparing it to the UTC date is only discriminating between 15:00 and 24:00 UTC and
  --   is vacuous the rest of the day — a pin that is silent for two thirds of every run reads as
  --   coverage and is not, so this is prose (and `check-device-clock`'s law, one layer down).
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  perform set_config('request.jwt.claim.sub', '', true);
  v_day := (now() at time zone 'Asia/Seoul')::date;
  select coalesce((select r.n from pack_map_roster_reads r
                    where r.session_id = v_ses and r.viewer = 'anon'   and r.day = v_day), 0) into v_a0;
  select coalesce((select r.n from pack_map_roster_reads r
                    where r.session_id = v_ses and r.viewer = 'authed' and r.day = v_day), 0) into v_b0;

  -- two ANONYMOUS reads
  set local role anon;
  begin
    perform club_pack_map_roster(v_ses);
    perform club_pack_map_roster(v_ses);
  exception when others then
    v_bad := v_bad || ' 익명 로스터 호출이 죽었다 [' || sqlstate || ' ' || sqlerrm || '] — 카운터가 definer 밖에서 쓰이고 있는가';
  end;
  reset role;
  select coalesce((select r.n from pack_map_roster_reads r
                    where r.session_id = v_ses and r.viewer = 'anon'   and r.day = v_day), 0) into v_a1;
  select coalesce((select r.n from pack_map_roster_reads r
                    where r.session_id = v_ses and r.viewer = 'authed' and r.day = v_day), 0) into v_b1;
  if v_a1 - v_a0 <> 2 then v_bad := v_bad || ' 익명 조회 2회가 anon 행을 2 만큼 올리지 않았다=' || (v_a1 - v_a0); end if;
  if v_b1 - v_b0 <> 0 then v_bad := v_bad || ' 익명 조회가 authed 행을 움직였다(두 버킷이 한 버킷이다)=' || (v_b1 - v_b0); end if;

  -- one SIGNED-IN read
  perform set_config('request.jwt.claim.sub', v_guest::text, true);
  perform club_pack_map_roster(v_ses);
  perform set_config('request.jwt.claim.sub', '', true);
  select coalesce((select r.n from pack_map_roster_reads r
                    where r.session_id = v_ses and r.viewer = 'anon'   and r.day = v_day), 0) into v_a0;
  select coalesce((select r.n from pack_map_roster_reads r
                    where r.session_id = v_ses and r.viewer = 'authed' and r.day = v_day), 0) into v_b0;
  if v_b0 - v_b1 <> 1 then v_bad := v_bad || ' 로그인한 조회가 authed 행을 1 올리지 않았다=' || (v_b0 - v_b1); end if;
  if v_a0 - v_a1 <> 0 then v_bad := v_bad || ' 로그인한 조회가 anon 행을 움직였다(auth.uid() 를 안 본다)=' || (v_a0 - v_a1); end if;

  -- the counter is keyed on the SESSION too — a neighbouring session must not absorb these
  select coalesce((select r.n from pack_map_roster_reads r
                    where r.session_id = v_ses2 and r.viewer = 'anon' and r.day = v_day), 0) into v_a1;
  perform club_pack_map_roster(v_ses2);
  select coalesce((select r.n from pack_map_roster_reads r
                    where r.session_id = v_ses2 and r.viewer = 'anon' and r.day = v_day), 0) into v_b1;
  if v_b1 - v_a1 <> 1 then v_bad := v_bad || ' 옆 세션 조회가 그 세션의 행을 1 올리지 않았다=' || (v_b1 - v_a1); end if;
  select coalesce((select r.n from pack_map_roster_reads r
                    where r.session_id = v_ses and r.viewer = 'anon' and r.day = v_day), 0) into v_a1;
  if v_a1 <> v_a0 then v_bad := v_bad || ' 옆 세션 조회가 이 세션의 행을 움직였다(세션 키가 안 걸린다)=' || (v_a1 - v_a0); end if;

  -- a nonexistent session must NOT create a row: counting above the existence check would let
  -- anyone (anon included) grow this table without bound from random uuids
  select count(*) into v_n from pack_map_roster_reads;
  begin
    perform club_pack_map_roster(gen_random_uuid());
    v_bad := v_bad || ' 없는 세션이 not_found 를 안 낸다';
  exception when others then
    if sqlerrm <> 'not_found' then v_bad := v_bad || ' 없는 세션의 오류가 not_found 가 아니다=' || sqlerrm; end if;
  end;
  select count(*) into v_n2 from pack_map_roster_reads;
  if v_n2 <> v_n then v_bad := v_bad || ' 없는 세션 조회가 카운터 행을 만들었다(임의 uuid 로 무한히 부풀릴 수 있다)=' || (v_n2 - v_n); end if;

  -- the viewer vocabulary is CLOSED by a check constraint, not by convention
  begin
    insert into pack_map_roster_reads (session_id, viewer, day, n) values (v_ses, 'other', v_day, 1);
    v_bad := v_bad || ' viewer 에 anon/authed 아닌 값이 들어간다(check 제약이 없다)';
    delete from pack_map_roster_reads where session_id = v_ses and viewer = 'other';
  exception when check_violation then null;
  end;
  if v_bad = '' then call _pass('pkpub','0160-M2 뷰어 카운터(Sean 2026-08-31 「Yes, add counter」) — 익명 조회 2회가 (세션, anon, KST 날짜) 행을 정확히 2 올리고 authed 행은 건드리지 않으며, 로그인한 조회는 반대로 authed 행만 1 올린다(auth.uid() 를 본다). 옆 세션 조회는 자기 세션 행으로 간다. 없는 세션은 not_found 를 내고 **행을 만들지 않는다**(존재 확인 위에서 셌다면 임의 uuid 로 무한히 부풀릴 수 있다). viewer 어휘는 check 제약으로 닫혀 있다. 전부 이 핀이 만든 델타다 — 이 파일과 190 의 다른 핀들도 로스터를 부르므로 절대값은 이웃을 재는 숫자다');
  else v_msg := v_bad; call _fail('pkpub','0160-M2 뷰어 카운터', v_msg); end if;

  -- ═══════════════════════════════════════════════════════════════════════════════════════
  -- [0160-W3] 카운터 테이블의 봉인 — 표시 테이블(W2)과 같은 두 겹, 같은 이유.
  -- ⚠ **THE FIXTURE STARTS WHERE PRODUCTION STARTS.** Supabase's default privileges grant
  --    `anon`/`authenticated` full DML on every new table in `public`, and the shim mirrors that
  --    (`00_shim.sql:82-95`), so 0160's `revoke` genuinely removes something here. An absence pin
  --    over a table that never had the grant is green for the wrong reason (the 0151 lesson).
  -- ⚠ It matters more than it looks for THIS table: a client that can UPDATE it can write its own
  --    numbers into the one artifact the pilot decision will be read off.
  -- ═══════════════════════════════════════════════════════════════════════════════════════
  v_bad := '';
  if (select c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
       where n.nspname = 'public' and c.relname = 'pack_map_roster_reads') is distinct from true
    then v_bad := v_bad || ' pack_map_roster_reads 에 RLS 가 없다'; end if;
  select count(*) into v_n from pg_policies where schemaname='public' and tablename='pack_map_roster_reads';
  if v_n <> 0 then v_bad := v_bad || ' 카운터 테이블에 정책이 있다(정책 0개가 봉인이다)=' || v_n; end if;
  select count(*) into v_n from (
    select r.rolname, pr.priv
      from (values ('anon'),('authenticated')) r(rolname),
           (values ('select'),('insert'),('update'),('delete')) pr(priv)
     where has_table_privilege(r.rolname, 'public.pack_map_roster_reads', pr.priv) is distinct from false
  ) t;
  if v_n <> 0 then v_bad := v_bad || ' 카운터 테이블에 클라이언트 권한이 남아 있다=' || v_n; end if;
  if has_table_privilege('authenticated', 'public.session_people', 'select') is distinct from true
    then v_bad := v_bad || ' 통제 실패: 이 스키마의 평범한 테이블에도 기본 권한이 없다(픽스처가 운영의 출발점이 아니다)'; end if;
  perform set_config('request.jwt.claim.sub', v_guest::text, true);
  set local role authenticated;
  begin
    perform 1 from pack_map_roster_reads;
    v_bad := v_bad || ' authenticated 가 카운터 테이블을 읽었다';
  exception when insufficient_privilege then null;
    when others then v_bad := v_bad || ' 카운터 읽기 거절이 42501 이 아니다 [' || sqlstate || ']';
  end;
  begin
    update pack_map_roster_reads set n = 999999;
    v_bad := v_bad || ' authenticated 가 카운터 테이블을 갱신했다(자기 숫자를 써넣을 수 있다)';
  exception when insufficient_privilege then null;
    when others then v_bad := v_bad || ' 카운터 갱신 거절이 42501 이 아니다 [' || sqlstate || ']';
  end;
  reset role;
  perform set_config('request.jwt.claim.sub', '', true);
  -- and the definer still writes it — the seal must not have sealed the counter out of its own
  -- table, which is exactly what an over-revoke looks like and what a one-sided pin cannot see
  select count(*) into v_n from pack_map_roster_reads where session_id = v_ses;
  if v_n < 1 then v_bad := v_bad || ' 통제 실패: 봉인 뒤 definer 도 카운터를 못 쓴다(행이 하나도 없다)=' || v_n; end if;
  if v_bad = '' then call _pass('pkpub','0160-W3 카운터 테이블 봉인 — RLS on + 정책 0개 + anon/authenticated 권한 0(카탈로그), 경계에서 authenticated 의 SELECT·UPDATE 둘 다 42501. 통제 둘: 같은 스키마의 평범한 테이블은 여전히 기본 권한을 갖고 있으므로 이 부재는 회수의 결과이지 빈 세계의 결과가 아니고, definer 는 여전히 쓸 수 있다(과잉 회수는 N1 류 팔을 완벽히 통과하면서 카운터를 조용히 죽인다)');
  else v_msg := v_bad; call _fail('pkpub','0160-W3 카운터 테이블 봉인', v_msg); end if;

  perform set_config('request.jwt.claim.sub', '', true);
end $suite$;

-- ═══ THE MUTATION BATTERY, RE-MEASURED IN FULL 2026-08-31 (post-/autoplan-addendum) ══════════
--
-- 🔴 **THE FIRST BATTERY (round 1, pre-addendum) IS GONE FROM THIS FILE ON PURPOSE, AND THAT IS
--    THE POINT OF THIS PARAGRAPH.** Its table was measured against a 0160 that called
--    `realtime.send` and verify-read its own row, on a baseline of 1150. The addendum replaced
--    that delivery path, so one of its rows (「the verify-read deleted」) described a mutation of
--    code that no longer exists, and EVERY row's numbers were against a baseline four pins short.
--    A record that is stale in the safe direction is the most durable kind of wrong, because
--    nothing ever contradicts it — so rather than annotate round 1, all fourteen rows were RE-RUN
--    against the current tree. One battery, one vintage, no mixing.
--
-- Baseline **1150 → 1154 (+4 = exactly the pins the addendum adds: `0160-A8` · `0160-A9` ·
-- `0160-M2` · `0160-W3`)** — the positive control that this suite RAN rather than being silently
-- skipped from `harness.sh`'s manifest. A green whose pin COUNT did not move is not a green.
-- (The +15 that took 1135 → 1150 is round 1's own count: 12 pins here + 3 in suite 192.)
-- ⚠ Every plant ran against an rsync'd COPY of `supabase/` OUTSIDE the worktree (another agent
--   shares this tree), restored from a pristine copy before each row, and was `&&`-CHAINED to its
--   harness run — so a plant that failed its own assertion yields **NO ROW** rather than a
--   plausible green one. That is not theoretical here: `M13`'s first attempt is an INSERTION whose
--   replacement text CONTAINS its own anchor, so the generic 「the old text must not survive」
--   read-back fired and the chain produced no row at all. The repair was to assert the LANDED
--   marker instead of the removed one — which is the same distinction as reading the artifact
--   rather than the tool's report, one level down inside the planter.
-- ⚠ CONTROL was observed clean BEFORE any row was read (1154/0) and again AFTER (1154/0).
--
-- | # | mutation | result |
-- |---|---|---|
-- | CONTROL | none | **1154/0** — observed first, so the deltas mean something |
-- | M1  | 🔴 §A ⑦ the `insert into realtime.messages` DELETED (`perform 1;`) | 1144/**10** = `0160-S1` · `A1` · `A2` · `A8` · `A4` · `A5` · `A6` · `A9` · `A7` · `B1` — see the note below, the blast radius is the redesign's signature |
-- | M2  | §A ⑤ the throttle's `where m.last_at <= now() - interval '2 seconds'` deleted | 1153/1 = **`0160-A6` alone** — the second call in the same transaction stops being `too_fast` |
-- | M3  | §A ⑥ the `least(greatest(p_age_ms,0),120000)` clamp removed | 1153/1 = **`0160-A9` alone**, and its detail names three arms: the upper clamp, **the negative age reaching the FUTURE**, and NULL |
-- | M4v | §D `serverNow` dropped, 0160's VERIFY arm LEFT IN | **APPLY ABORTS** — `ERROR: 0160 VERIFY 실패: club_pack_map_roster 본문에 serverNow가 없다=0`. Recorded separately, because an aborted apply measures the VERIFY block and NOT this suite |
-- | M4  | same, with that VERIFY arm removed so SUITE pins have to catch it alone | 1152/2 = 190 `0159-M3` (key set) + `0160-M1` (value + spelling) |
-- | M5  | 🔴 §A ② `checked_in_at is not null` HALF removed | 1152/2 = `0160-A3` + **`0160-A8`**, and both details name ONE arm each: 「발산 구역이 발행에 성공한다」 / 「로스터에 없는 행이 발행에는 성공한다」. Every other A3 arm stayed green, because on every other fixture the two candidate predicates AGREE |
-- | M6  | §D the `pack_map_roster_reads` upsert deleted | 1152/2 = **`0160-M2`** + `0160-W3` (its 「the definer can still write」 control) |
-- | M7  | §A ③ window check removed | 1153/1 = **`0160-A4` alone** |
-- | M8  | `profileId` hardwired to a constant uuid | 1152/2 = `0160-A1` + `0160-A2` |
-- | M9  | §A ⑦ the `exception when others` handler deleted (bare `begin`/`end`) | 1153/1 = **`0160-S1` alone** — behaviourally invisible, because the shim's unpartitioned table never makes the INSERT fail |
-- | M10 | §A ② membership gate removed entirely | 1151/3 = `0160-A3` + `0160-A8` + `0160-A7` |
-- | M11 | §A ④ coord guard removed | 1152/2 = `0160-A5` + `0160-A6` (A6 drives a `bad_position` call to prove a refusal does not stamp) |
-- | M12 | a LATER migration adds `create policy … for insert to authenticated with check (true)` | 1146/**8** = `0160-B1` · 190 `0159-E1`·`0159-W1` · 143 `E1`·`E2`·`E3`·`W1` · 142 `L7` |
-- | M13 | 0159's pack WRITE arm restored inside `channel_allowed` | 1151/3 = 190 `0159-P1`·`P3`·`S5` |
-- | M14 | 0161's `revoke` deleted (+ its VERIFY arm) | 1152/2 = 192 `0161-N1` + 116 `C15` |
-- | CONTROL | none, re-run last | **1154/0** |
--
-- 🔴 **M1's TEN IS THE ADDENDUM'S SIGNATURE, AND IT IS AN IMPROVEMENT WORTH NAMING.** Under the
--    pre-addendum design the same question — 「does the broadcast actually leave」 — was answerable
--    ONLY by a source pin, because `realtime.send` swallows every error and the shim can never
--    make it fail: round 1's equivalent row reddened `0160-S1` **alone**, a single source-shaped
--    detector standing in for a behavioural fact. Now that the RPC inserts the row itself, ten
--    pins across every behavioural surface notice. **A defect that was visible to one source
--    regex is now visible to the product's own observations** — that is what moving from a
--    swallowing wrapper to a raising statement buys, stated as a measurement rather than a claim.
-- 🔴 **M2 vs M9 IS THE PAIR THAT SHOWS THE TWO HALVES ARE INDEPENDENT.** Both live inside §A and
--    neither substitutes for the other: deleting the throttle's `where` (M2) is invisible to every
--    source pin and reddens exactly one behavioural pin; deleting the exception handler (M9) is
--    invisible to every behavioural pin and reddens exactly one source pin. The suite needs both
--    kinds of evidence because the harness can execute one property and not the other.
-- ⚠ **M12's BLAST RADIUS IS THE FINDING**: a single `with check (true)` INSERT policy on
--    `realtime.messages` opens the write door for `chat-`, `bk-`, `club-chat-` and `run2-` as
--    well — 8 pins across four suites, not one. `realtime.messages` is ONE table for every
--    channel family in the product, so any permissive policy anyone adds there is systemic.
-- ⚠ **M12 vs M13 attack the two halves of the SAME door and the halves are independent**:
--    restoring the PREDICATE arm (M13) reddens three `channel_allowed` pins and leaves every
--    BOUNDARY pin green, because with no INSERT policy there is nothing for the predicate to be
--    consulted by; re-adding a POLICY (M12) reddens every boundary pin and leaves the predicate
--    pins green.
-- ⚠ **M14 reddens `116 C15` as well as 192, and that is correct rather than collateral.** C15 is
--    the BOUNDARY pin for this seal (what a real `authenticated`/`anon` session actually gets);
--    `0161-N1` is the CATALOG pin. Two kinds of evidence for one property, and neither is
--    evidence for the other — which is why C15's arms were split in the same slice rather than
--    relaxed (see the note at `116_charge_suite.sql:786`).
--
-- 🔴 **M4v/M4 IS THE THREE-PROPOSITION DISCIPLINE, AND IT WAS OWED.** 「the hole is real」, 「a pin
--    notices」 and 「the fix closes it」 are three claims and one mutation proves only the middle.
--    M4v establishes that 0160's own VERIFY is LIVE (the apply refuses to land a roster without
--    `serverNow`); M4 then removes exactly that arm so SUITE pins must catch it alone — because a
--    property checked at apply and never pinned is protected exactly until someone recreates the
--    function. M14 is the same shape for 0161's revoke.
-- ⚠ **WHAT THIS BATTERY DOES NOT PROVE, said out loud.** `not_delivered` has no BEHAVIOURAL
--    mutation, because the shim's unpartitioned `realtime.messages` cannot make the INSERT fail —
--    M9 attacks its source shape instead, and the deploy protocol's cold-start probe is where the
--    refusal is actually observed. The throttle's CONCURRENCY has no mutation either, for the
--    same kind of reason: this file is one transaction on one connection (header limitation ②).
--    And no mutation here can reach socket-level behaviour (join caching, the private handshake),
--    which is a property of the realtime server and not of this schema.
