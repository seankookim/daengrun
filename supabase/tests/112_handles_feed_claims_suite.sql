-- ═══ 112 handles + feed-claim suite — 0074 pins ═══
-- Purpose: two things that are easy to quietly reverse later.
--   ① @handle validation (format, reserved, case-insensitive uniqueness, idempotence).
--   ② 🔴 **F1 pins a Sean DECISION, not a bug fix.** "let's not restrict what the users will be
--      uploading" (2026-08-12) means a photo/text post with NO booking must stay legal. A future
--      session tightening the feed back to "완료된 러닝만" would be undoing a product call, so the
--      pin exists to make that reversal loud instead of silent.
--   The gate is on the CLAIM, not the upload: F2/F3 prove a post cannot assert km/badges it did
--   not earn, while F1/F5 prove ordinary posting stays wide open.
-- Style: sibling of 105-111. `_fail` args pre-computed into v_msg, never a subquery (110 header law).
--
-- ─── MUTATION map — each pin RED under exactly one revert ───
--   H1 ← 0074: delete the `update profiles set handle` statement                       → RED
--   H2 ← 0074: drop the `v !~ '^[a-z0-9_.]+$'` charset check                           → RED
--   H3 ← 0074: drop the `lower(handle) = v` taken check (or the unique index)          → RED
--   H4 ← 0074: make `_handle_reserved` return false always                             → RED
--   H5 ← 0074: drop the length check                                                   → RED
--   F1 ← 0074: make enforce_feed_claim require booking_id for EVERY post
--        (i.e. delete the `if not _feed_claims_run(...) then return new` early exit)   → RED
--   F2 ← 0074: drop the `booking_id is null → claim_needs_booking` raise               → RED
--   F3 ← 0074: drop the ownership arm of the exists(...) check                         → RED
--   F4 ← 0074: drop the `join runs` (a booking with no run would count as a run)       → RED

do $$
declare
  oo uuid; oz uuid; rr uuid; dg uuid; rt uuid;
  bk_done uuid; bk_nolauf uuid; bk_other uuid;
  v_h text; v_msg text; v_err text; v_n int; v_id uuid;
begin
  -- ---------- seed ----------
  oo := t_user('hdl_oo', 'owner');
  oz := t_user('hdl_oz', 'owner');
  rr := t_user('hdl_rr', 'runner');
  dg := t_dog(oo, '핸들견'); rt := t_route('핸들 코스');
  -- oo's completed run
  bk_done := t_av_booking(oo, dg, rt, rr, now() - interval '2 hours', 5.0, 'completed');
  insert into runs (booking_id, started_at, ended_at, actual_km, duration_sec, end_reason)
    values (bk_done, now() - interval '2 hours', now() - interval '1 hour', 5.0, 1800, 'completed');
  -- oo's booking with NO run row
  bk_nolauf := t_av_booking(oo, dg, rt, rr, now() + interval '3 hours', 5.0, 'confirmed');
  -- oz's completed run (a stranger's)
  bk_other := t_av_booking(oz, t_dog(oz, '남의견'), rt, rr, now() - interval '3 hours', 4.0, 'completed');
  insert into runs (booking_id, started_at, ended_at, actual_km, duration_sec, end_reason)
    values (bk_other, now() - interval '3 hours', now() - interval '2 hours', 4.0, 1500, 'completed');

  perform set_config('request.jwt.claim.sub', oo::text, false);

  -- ---------- [H1] 유효한 핸들이 저장된다 + 대문자는 소문자로 받아준다 ----------
  begin
    v_h := set_my_handle('  ChoCo.Runner  ');
    select handle into v_msg from profiles where id = oo;
    if v_h = 'choco.runner' and v_msg = 'choco.runner'
      then call _pass('hdl','H1 핸들 저장 + 소문자 정규화 — 대문자로 내도 거절하지 않고 받아준다');
      else v_msg := 'ret=' || coalesce(v_h,'<null>') || ' stored=' || coalesce(v_msg,'<null>');
           call _fail('hdl','H1 핸들 저장', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('hdl','H1', v_msg);
  end;

  -- ---------- [H1b] 같은 값 재설정은 멱등 성공 (중복이라고 부르지 않는다) ----------
  begin
    v_h := set_my_handle('choco.runner');
    if v_h = 'choco.runner' then call _pass('hdl','H1b 동일 값 재설정 = 멱등 성공');
    else v_msg := 'ret=' || coalesce(v_h,'<null>'); call _fail('hdl','H1b 멱등', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('hdl','H1b', v_msg);
  end;

  -- ---------- [H2] 문자셋 — 한글·공백·@ 거절 ----------
  begin
    v_err := '';
    begin perform set_my_handle('초코러너'); v_err := v_err || 'ko:none '; exception when others then v_err := v_err || 'ko:' || sqlerrm || ' '; end;
    begin perform set_my_handle('choco runner'); v_err := v_err || 'sp:none '; exception when others then v_err := v_err || 'sp:' || sqlerrm || ' '; end;
    begin perform set_my_handle('@choco'); v_err := v_err || 'at:none '; exception when others then v_err := v_err || 'at:' || sqlerrm; end;
    if v_err like '%ko:%charset%' and v_err like '%sp:%charset%' and v_err like '%at:%charset%'
      then call _pass('hdl','H2 문자셋 — 한글·공백·@ 전부 거절 (a-z0-9_. 만)');
      else call _fail('hdl','H2 문자셋', v_err); end if;
  exception when others then v_msg := sqlerrm; call _fail('hdl','H2', v_msg);
  end;

  -- ---------- [H5] 길이 3~20 ----------
  begin
    v_err := '';
    begin perform set_my_handle('ab'); v_err := v_err || 'short:none '; exception when others then v_err := v_err || 'short:' || sqlerrm || ' '; end;
    begin perform set_my_handle(repeat('a', 21)); v_err := v_err || 'long:none'; exception when others then v_err := v_err || 'long:' || sqlerrm; end;
    if v_err like '%short:%length%' and v_err like '%long:%length%'
      then call _pass('hdl','H5 길이 3~20자');
      else call _fail('hdl','H5 길이', v_err); end if;
  exception when others then v_msg := sqlerrm; call _fail('hdl','H5', v_msg);
  end;

  -- ---------- [H4] 예약어 차단 (브랜드·시스템 사칭) ----------
  begin
    v_err := '';
    begin perform set_my_handle('dogshigh'); v_err := v_err || 'brand:none '; exception when others then v_err := v_err || 'brand:' || sqlerrm || ' '; end;
    begin perform set_my_handle('admin'); v_err := v_err || 'admin:none'; exception when others then v_err := v_err || 'admin:' || sqlerrm; end;
    if v_err like '%brand:%reserved%' and v_err like '%admin:%reserved%'
      then call _pass('hdl','H4 예약어 차단 — dogshigh·admin 사칭 불가');
      else call _fail('hdl','H4 예약어', v_err); end if;
  exception when others then v_msg := sqlerrm; call _fail('hdl','H4', v_msg);
  end;

  -- ---------- [H3] 대소문자 무시 유니크 — 남이 선점한 아이디 ----------
  begin
    perform set_config('request.jwt.claim.sub', oz::text, false);
    v_err := '';
    begin perform set_my_handle('CHOCO.RUNNER'); v_err := 'none'; exception when others then v_err := sqlerrm; end;
    select handle into v_msg from profiles where id = oz;
    if v_err like '%taken%' and v_msg is null
      then call _pass('hdl','H3 대소문자 무시 유니크 — CHOCO.RUNNER는 choco.runner를 못 가져간다');
      else v_msg := 'err=' || v_err || ' oz_handle=' || coalesce(v_msg,'<null>');
           call _fail('hdl','H3 유니크', v_msg); end if;
    perform set_config('request.jwt.claim.sub', oo::text, false);
  exception when others then v_msg := sqlerrm; call _fail('hdl','H3', v_msg);
  end;

  -- ═══════════ 피드 주장 게이트 ═══════════

  -- ---------- [F1] 🔴 자유 포스트 — 예약 없이 사진·글만. Sean의 결정을 핀으로 박는다 ----------
  begin
    insert into feed_posts (author_id, booking_id, body, photo_url, meta)
      values (oo, null, '오늘 초코랑 산책했어요', null, '{}'::jsonb)
      returning id into v_id;
    if v_id is not null
      then call _pass('hdl','F1 자유 포스트 — 예약 없이 글만 올라간다 (Sean 2026-08-12 결정)');
      else call _fail('hdl','F1 자유 포스트','행이 안 생겼다'); end if;
  exception when others then v_msg := sqlerrm;
    call _fail('hdl','F1 자유 포스트가 막혔다 — 업로드 제한 금지 결정 위반', v_msg);
  end;

  -- ---------- [F5] 자유 포스트에 강아지 이름 같은 비-러닝 meta는 허용 ----------
  begin
    insert into feed_posts (author_id, booking_id, body, meta)
      values (oo, null, '초코 소개합니다', '{"dogName":"초코"}'::jsonb)
      returning id into v_id;
    if v_id is not null
      then call _pass('hdl','F5 러닝을 주장하지 않는 meta(dogName)는 자유 — 게이트는 주장에만 건다');
      else call _fail('hdl','F5','행이 안 생겼다'); end if;
  exception when others then v_msg := sqlerrm; call _fail('hdl','F5 비-러닝 meta 차단됨', v_msg);
  end;

  -- ---------- [F2] 러닝을 주장하는데 예약이 없다 → 거절 ----------
  begin
    v_err := '';
    begin
      insert into feed_posts (author_id, booking_id, body, meta)
        values (oo, null, '오늘 42km 뛰었어요', '{"km":42.2,"badges":["★ 역대 최장 거리"]}'::jsonb);
      v_err := 'none';
    exception when others then v_err := sqlerrm;
    end;
    select count(*) into v_n from feed_posts where author_id = oo and meta ? 'km';
    if v_err like '%claim_needs_booking%' and v_n = 0
      then call _pass('hdl','F2 예약 없는 러닝 주장 거절 — 달리지 않은 42km PB를 못 올린다');
      else v_msg := 'err=' || v_err || ' rows=' || v_n; call _fail('hdl','F2 가짜 기록', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('hdl','F2', v_msg);
  end;

  -- ---------- [F3] 남의 러닝을 내 기록으로 주장 → 거절 ----------
  begin
    v_err := '';
    begin
      insert into feed_posts (author_id, booking_id, body, meta)
        values (oo, bk_other, '내 기록', '{"km":4.0}'::jsonb);
      v_err := 'none';
    exception when others then v_err := sqlerrm;
    end;
    if v_err like '%claim_not_yours%'
      then call _pass('hdl','F3 남의 예약을 내 기록으로 주장 거절');
      else v_msg := 'err=' || v_err; call _fail('hdl','F3 타인 기록 도용', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('hdl','F3', v_msg);
  end;

  -- ---------- [F4] 내 예약이지만 달린 적 없음(runs 행 없음) → 거절 ----------
  begin
    v_err := '';
    begin
      insert into feed_posts (author_id, booking_id, body, meta)
        values (oo, bk_nolauf, '달렸다 치고', '{"km":5.0}'::jsonb);
      v_err := 'none';
    exception when others then v_err := sqlerrm;
    end;
    if v_err like '%claim_not_yours%'
      then call _pass('hdl','F4 runs 행 없는 예약의 기록 주장 거절 — 없는 러닝은 기록이 아니다');
      else v_msg := 'err=' || v_err; call _fail('hdl','F4 미실시 러닝', v_msg); end if;
  exception when others then v_msg := sqlerrm; call _fail('hdl','F4', v_msg);
  end;

  -- ---------- [F6] 진짜 완료 러닝은 통과 (shareRunToFeed의 실제 모양) ----------
  begin
    insert into feed_posts (author_id, booking_id, body, meta)
      values (oo, bk_done, '오늘 5km', '{"km":5.0,"durationSec":1800,"trace":[{"x":0,"y":0},{"x":1,"y":1}]}'::jsonb)
      returning id into v_id;
    if v_id is not null
      then call _pass('hdl','F6 내 완료 러닝의 기록은 통과 — shareRunToFeed 경로가 살아 있다');
      else call _fail('hdl','F6','행이 안 생겼다'); end if;
  exception when others then v_msg := sqlerrm; call _fail('hdl','F6 정상 공유가 막혔다', v_msg);
  end;

  -- ---------- [F7] 클럽 리캡 모양 — badges만 있고 예약 없음 → 통과해야 한다 ----------
  -- 회귀 핀. 첫 초안이 `badges`를 주장 키에 넣었다가 서버 리캡 5곳(0031/0037/0038/0045/0048)을
  -- 전부 막아 하네스가 15건 red가 됐다. 주장 키를 다시 넓히면 여기서 잡힌다.
  begin
    insert into feed_posts (author_id, booking_id, body, meta)
      values (oo, null, '반포동 하이클럽 리캡',
              '{"club":"반포동 하이클럽","teams":4,"dogs":6,"badges":["🏁 하이클럽"]}'::jsonb)
      returning id into v_id;
    if v_id is not null
      then call _pass('hdl','F7 클럽 리캡(badges만·예약 없음) 통과 — 주장 키는 측정치(km/durationSec/trace)뿐');
      else call _fail('hdl','F7','행이 안 생겼다'); end if;
  exception when others then v_msg := sqlerrm;
    call _fail('hdl','F7 리캡이 막혔다 — 주장 키가 다시 넓어졌다', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
