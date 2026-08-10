-- ═══ 0064 private media suite — the `media` bucket must DENY by execution, not by comment ═══
-- What this pins: dog/run/chat photos live in a PRIVATE bucket whose policies are verified by
-- actually running reads/writes under `set local role` (anon / authenticated + jwt sub), never
-- by reading the policy text. Split decision pinned too: avatars stays deliberately public (M12),
-- media is invisible to anon (M4), and the 0019 gear tie (verified_at ⇒ photo_url) survives (M13).
--
-- Real-Supabase grant parity: the shim only granted default privileges in schema public, but the
-- hosted platform grants authenticated/anon table access on storage.* and lets RLS gate rows —
-- deny tests must fail on POLICY, not on missing grants, or every RED is fake.
grant usage on schema storage to anon, authenticated;
grant select, insert, update, delete on storage.objects to anon, authenticated;
grant select on storage.buckets to anon, authenticated;

set client_min_messages = warning;

do $$
declare
  mo uuid; mr uuid; ms uuid; ch uuid; cm uuid;
  md uuid; rt uuid; bid uuid; tid uuid; cid uuid; sid uuid;
  dogp text; runp text; chatp text; clubp text;
  v_cnt int; v_pub boolean;
begin
  -- ---------- seed: owner+runner booking party, a stranger, and a club session shell ----------
  mo := t_user('med_owner', 'owner');
  mr := t_user('med_runner', 'runner');
  ms := t_user('med_stranger', 'owner');
  ch := t_user('med_host', 'runner');
  cm := t_user('med_member', 'owner');
  md := t_dog(mo, '미디어견');
  rt := t_route('미디어 코스');
  bid := t_active_booking(mo, mr, md, rt);
  insert into chat_threads (booking_id) values (bid) returning id into tid;
  insert into clubs (name, district, status, host_profile_id)
  values ('미디어클럽', '성수동', 'active', ch) returning id into cid;
  insert into club_sessions (club_id, host_profile_id, scheduled_at, meetup_point)
  values (cid, ch, now() + interval '2 hours', '미디어 집결지') returning id into sid;
  insert into session_people (session_id, profile_id, role, attendance)
  values (sid, cm, 'owner_attending', 'rsvp');

  dogp  := mo::text || '/dogs/' || md::text || '.jpg';
  runp  := mr::text || '/runs/' || bid::text || '/1.jpg';
  chatp := mr::text || '/chat/' || tid::text || '/1.jpg';
  clubp := ch::text || '/clubchat/' || sid::text || '/1.jpg';

  -- ── M1: bucket exists and is PRIVATE (public=false is the whole point of 0064) ──
  begin
    select public into v_pub from storage.buckets where id = 'media';
    if v_pub is false then call _pass('media', 'M1 media 버킷 존재+비공개 (public=false)');
    else call _fail('media', 'M1 media 버킷 존재+비공개', 'public=' || coalesce(v_pub::text, '버킷 없음'));
    end if;
  exception when others then call _fail('media', 'M1 media 버킷 존재+비공개', sqlerrm);
  end;

  -- ── M2: own-folder upload works (owner writes the dog photo into {own uid}/dogs/) ──
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', mo::text, true);
    insert into storage.objects (bucket_id, name, owner) values ('media', dogp, mo);
    reset role;
    select count(*) into v_cnt from storage.objects where bucket_id = 'media' and name = dogp;
    if v_cnt = 1 then call _pass('media', 'M2 본인 폴더 업로드 허용 ({uid}/dogs/…)');
    else call _fail('media', 'M2 본인 폴더 업로드 허용', 'rows=' || v_cnt);
    end if;
    update dogs set photo_url = dogp where id = md;  -- app stores the bare path from now on
  exception when others then reset role; call _fail('media', 'M2 본인 폴더 업로드 허용', sqlerrm);
  end;

  -- ── M3: writing into SOMEONE ELSE's folder is sealed (path prefix = party gate) ──
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', ms::text, true);
    insert into storage.objects (bucket_id, name, owner)
    values ('media', mo::text || '/dogs/hijack.jpg', ms);
    reset role;
    call _fail('media', 'M3 타인 폴더 쓰기 봉인', 'insert가 성공해버림');
  exception when others then
    reset role;
    if sqlerrm like '%row-level security%' then
      call _pass('media', 'M3 타인 폴더 쓰기 봉인 — RLS가 insert 거부');
    else call _fail('media', 'M3 타인 폴더 쓰기 봉인', sqlerrm);
    end if;
  end;

  -- ── M4: anonymous read is DEAD (this was the 0006 hole: world-readable dog photos) ──
  begin
    set local role anon;
    perform set_config('request.jwt.claim.sub', '', true);
    select count(*) into v_cnt from storage.objects where bucket_id = 'media' and name = dogp;
    reset role;
    if v_cnt = 0 then call _pass('media', 'M4 익명 읽기 봉인 — media 버킷은 비로그인에 행 0');
    else call _fail('media', 'M4 익명 읽기 봉인', 'rows=' || v_cnt);
    end if;
  exception when others then reset role; call _fail('media', 'M4 익명 읽기 봉인', sqlerrm);
  end;

  -- ── M5: dog photo = app-visible, not world-visible (any signed-in user may read) ──
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', ms::text, true);
    select count(*) into v_cnt from storage.objects where bucket_id = 'media' and name = dogp;
    reset role;
    if v_cnt = 1 then call _pass('media', 'M5 강아지 사진 = 로그인 사용자 읽기 (리더보드·오픈풀 제품 의미)');
    else call _fail('media', 'M5 강아지 사진 로그인 읽기', 'rows=' || v_cnt);
    end if;
  exception when others then reset role; call _fail('media', 'M5 강아지 사진 로그인 읽기', sqlerrm);
  end;

  -- ── M6: run photo — runner uploads, booking OWNER can read (delegated to runs RLS) ──
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', mr::text, true);
    insert into storage.objects (bucket_id, name, owner) values ('media', runp, mr);
    reset role;
    update runs set photos = array[runp] where booking_id = bid;
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', mo::text, true);
    select count(*) into v_cnt from storage.objects where bucket_id = 'media' and name = runp;
    reset role;
    if v_cnt = 1 then call _pass('media', 'M6 러닝 사진 — 예약 보호자 읽기 (runs RLS 위임)');
    else call _fail('media', 'M6 러닝 사진 보호자 읽기', 'rows=' || v_cnt);
    end if;
  exception when others then reset role; call _fail('media', 'M6 러닝 사진 보호자 읽기', sqlerrm);
  end;

  -- ── M7: run photo — a STRANGER gets zero rows (the route/인증샷 is party-only) ──
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', ms::text, true);
    select count(*) into v_cnt from storage.objects where bucket_id = 'media' and name = runp;
    reset role;
    if v_cnt = 0 then call _pass('media', 'M7 러닝 사진 — 무관자 읽기 봉인');
    else call _fail('media', 'M7 러닝 사진 무관자 봉인', 'rows=' || v_cnt);
    end if;
  exception when others then reset role; call _fail('media', 'M7 러닝 사진 무관자 봉인', sqlerrm);
  end;

  -- ── M8: feed share is the OWNER's explicit publish switch — after it, app-wide read ──
  begin
    insert into feed_posts (author_id, booking_id, body, photo_url)
    values (mo, bid, '자랑', runp);
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', ms::text, true);
    select count(*) into v_cnt from storage.objects where bucket_id = 'media' and name = runp;
    reset role;
    if v_cnt = 1 then call _pass('media', 'M8 피드 공유 후 앱 내 공개 (feed_posts 참조 = 옵트인 공개)');
    else call _fail('media', 'M8 피드 공유 후 공개', 'rows=' || v_cnt);
    end if;
  exception when others then reset role; call _fail('media', 'M8 피드 공유 후 공개', sqlerrm);
  end;

  -- ── M9: 1:1 chat photo — thread party reads, stranger sealed (chat_messages RLS 위임) ──
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', mr::text, true);
    insert into storage.objects (bucket_id, name, owner) values ('media', chatp, mr);
    insert into chat_messages (thread_id, sender_id, kind, media_path)
    values (tid, mr, 'photo', chatp);
    reset role;
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', mo::text, true);
    select count(*) into v_cnt from storage.objects where bucket_id = 'media' and name = chatp;
    reset role;
    if v_cnt <> 1 then call _fail('media', 'M9 채팅 사진 당사자/무관자', '상대 당사자 rows=' || v_cnt);
    else
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', ms::text, true);
      select count(*) into v_cnt from storage.objects where bucket_id = 'media' and name = chatp;
      reset role;
      if v_cnt = 0 then call _pass('media', 'M9 채팅 사진 — 스레드 당사자 읽기·무관자 봉인');
      else call _fail('media', 'M9 채팅 사진 당사자/무관자', '무관자 rows=' || v_cnt);
      end if;
    end if;
  exception when others then reset role; call _fail('media', 'M9 채팅 사진 당사자/무관자', sqlerrm);
  end;

  -- ── M10: club chat photo — session member reads, outsider sealed (메시지 가시성 위임) ──
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', ch::text, true);
    insert into storage.objects (bucket_id, name, owner) values ('media', clubp, ch);
    reset role;
    insert into club_chat_messages (session_id, sender_id, audience, kind, media_path)
    values (sid, ch, 'group', 'photo', clubp);
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', cm::text, true);
    select count(*) into v_cnt from storage.objects where bucket_id = 'media' and name = clubp;
    reset role;
    if v_cnt <> 1 then call _fail('media', 'M10 클럽 채팅 사진 멤버/외부인', '멤버 rows=' || v_cnt);
    else
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', ms::text, true);
      select count(*) into v_cnt from storage.objects where bucket_id = 'media' and name = clubp;
      reset role;
      if v_cnt = 0 then call _pass('media', 'M10 클럽 채팅 사진 — 세션 멤버 읽기·외부인 봉인');
      else call _fail('media', 'M10 클럽 채팅 사진 멤버/외부인', '외부인 rows=' || v_cnt);
      end if;
    end if;
  exception when others then reset role; call _fail('media', 'M10 클럽 채팅 사진 멤버/외부인', sqlerrm);
  end;

  -- ── M11: deleting the message seals its photo (audit-11 gap: bubble gone, URL alive) ──
  begin
    update club_chat_messages set deleted_at = now() where media_path = clubp;
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', cm::text, true);
    select count(*) into v_cnt from storage.objects where bucket_id = 'media' and name = clubp;
    reset role;
    if v_cnt = 0 then call _pass('media', 'M11 삭제 메시지의 사진 봉인 — 스토리지 잔존해도 읽기 불가');
    else call _fail('media', 'M11 삭제 메시지 사진 봉인', 'rows=' || v_cnt);
    end if;
  exception when others then reset role; call _fail('media', 'M11 삭제 메시지 사진 봉인', sqlerrm);
  end;

  -- ── M12: avatars stays DELIBERATELY public — the storefront half of the split decision ──
  begin
    insert into storage.objects (bucket_id, name, owner)
    values ('avatars', mo::text || '/avatar.jpg', mo);
    set local role anon;
    perform set_config('request.jwt.claim.sub', '', true);
    select count(*) into v_cnt from storage.objects
     where bucket_id = 'avatars' and name = mo::text || '/avatar.jpg';
    reset role;
    if v_cnt = 1 then call _pass('media', 'M12 avatars 버킷은 의도적 공개 유지 (프로필/스토어프런트)');
    else call _fail('media', 'M12 avatars 공개 유지', 'rows=' || v_cnt);
    end if;
  exception when others then reset role; call _fail('media', 'M12 avatars 공개 유지', sqlerrm);
  end;

  -- ── M13: 0019 gear tie intact — verified_at without photo_url still impossible ──
  begin
    insert into runner_gear (runner_id, kind, label, photo_url, verified_at)
    values (mr, 'leash', '리드줄', null, now());
    call _fail('media', 'M13 장비 인증 제약 (verified_at ⇒ photo_url)', '사진 없는 인증이 통과');
  exception when check_violation then
    call _pass('media', 'M13 장비 인증 제약 유지 — 사진 없는 verified_at 거부 (0019)');
  when others then
    call _fail('media', 'M13 장비 인증 제약', sqlerrm);
  end;

  -- ── M14: update/delete on someone else's object are no-ops (0 rows, no oracle) ──
  begin
    set local role authenticated;
    perform set_config('request.jwt.claim.sub', ms::text, true);
    update storage.objects set name = name || '.x' where bucket_id = 'media' and name = runp;
    delete from storage.objects where bucket_id = 'media' and name = runp;
    reset role;
    select count(*) into v_cnt from storage.objects where bucket_id = 'media' and name = runp;
    if v_cnt = 1 then call _pass('media', 'M14 타인 오브젝트 수정·삭제 봉인 (0행 무반응)');
    else call _fail('media', 'M14 타인 오브젝트 수정·삭제 봉인', '원본 rows=' || v_cnt);
    end if;
  exception when others then reset role; call _fail('media', 'M14 타인 오브젝트 수정·삭제 봉인', sqlerrm);
  end;
end $$;
