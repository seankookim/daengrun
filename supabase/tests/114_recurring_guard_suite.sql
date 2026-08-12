-- ═══ 114: create_recurring_series 이중 벨트 핀 (0077) ═══
-- Style: sibling of 105-113 — `_pass('rgd',…)` / `_fail('rgd',…)`, one begin…exception per case.
--   ⚠ `_fail` arguments are pre-computed into v_msg, never a subquery (the 110 header law).
--
-- Named reverts — 전부 실제 실행함 (2026-08-12, 각 리버트 후 전체 하네스):
--   R1 ← ⓑ(not_signed_in) 제거 → 382/1, R1 홀로 red (`raised=forbidden` — 벨트 ⓒ가 NULL을
--        잡되 틀린 오류로 잡는, 예측된 실패 형상 그대로). ✔ 실행됨.
--   R2 ← ⓒ 게이트를 `if false then` 동어반복으로 → 380/3: R2 red (타인이 시리즈 발행) +
--        R4 red (텍스트 소실, 정당한 캐스케이드). ✔ 실행됨.
--   R3 ← 멱등 return 제거 → 378/5: R3 red (id≠id2, 두 시리즈 발행) + 구 [recur] 스위트의
--        R2멱등/G2/G3/G7 red — 0026 시절 스위트가 멱등 계약을 실제로 소비하고 있다는 증명.
--        캐스케이드 정당. ✔ 실행됨.
--   R4 ← ⓒ를 `<>`로 되돌림 → 382/1, R4 홀로 red. **R4가 텍스트 핀인 이유(정직):** ⓑ가 살아
--        있는 한 ⓒ의 NULL 경로는 행동으로 도달 불가(벨트의 정의). 행동 핀은 ⓑ+ⓒ 동시 리버트를
--        요구하므로, 단일 리버트 red를 위해 pg_get_functiondef 텍스트를 본다 — H1(98)이
--        search_path에 쓰는 그 층위. ✔ 실행됨.
set client_min_messages = warning;

do $$
declare
  o1 uuid; o2 uuid; d1 uuid; rt uuid; bk uuid;
  v_id uuid; v_id2 uuid; v_series uuid;
  v_msg text; v_def text; v_ok boolean;
begin
  o1 := t_user('rgd_owner', 'owner');
  o2 := t_user('rgd_stranger', 'owner');
  d1 := t_dog(o1, '가드견');
  rt := t_route('가드 코스');
  insert into bookings (owner_id, dog_id, route_id, status, scheduled_at, km,
    base_fare, distance_fare, addon_fare, total_price, min_fare)
  values (o1, d1, rt, 'confirmed', now() + interval '1 day', 3.0, 9900, 9000, 0, 18900, 9900)
  returning id into bk;

  -- ── R1: uid 없음(service_role 형상) → 정확히 not_signed_in ──────────────────────────────
  begin
    perform set_config('request.jwt.claim.sub', '', false);
    v_id := create_recurring_series(bk);
    v_msg := '게이트 없이 통과 — series=' || coalesce(v_id::text, '<null>');
    call _fail('rgd', 'R1 uid=NULL 즉시 거부', v_msg);
  exception when others then
    if sqlerrm = 'not_signed_in'
      then call _pass('rgd', 'R1 uid=NULL 즉시 거부 — service_role 형상은 not_signed_in에서 끝난다');
      else v_msg := 'raised=' || sqlerrm; call _fail('rgd', 'R1 uid=NULL 즉시 거부', v_msg); end if;
  end;

  -- ── R2: 로그인한 타인 → forbidden ─────────────────────────────────────────────────────
  begin
    perform set_config('request.jwt.claim.sub', o2::text, false);
    v_id := create_recurring_series(bk);
    v_msg := '타인이 통과 — series=' || coalesce(v_id::text, '<null>');
    call _fail('rgd', 'R2 타인 거부', v_msg);
  exception when others then
    if sqlerrm = 'forbidden'
      then call _pass('rgd', 'R2 타인 거부 — is distinct from이 authenticated 비소유자에 발화');
      else v_msg := 'raised=' || sqlerrm; call _fail('rgd', 'R2 타인 거부', v_msg); end if;
  end;

  -- ── R3: 소유자 성공 + 멱등 + series_id 스탬프 (행동 보존 — 0026 계약 그대로) ──────────
  begin
    perform set_config('request.jwt.claim.sub', o1::text, false);
    v_id := create_recurring_series(bk);
    v_id2 := create_recurring_series(bk);
    select series_id into v_series from bookings where id = bk;
    if v_id is not null and v_id = v_id2 and v_series = v_id
      then call _pass('rgd', 'R3 소유자 성공·재탭 멱등·booking.series_id 스탬프 — 0026 행동 보존');
      else v_msg := 'id=' || coalesce(v_id::text,'<null>') || ' id2=' || coalesce(v_id2::text,'<null>')
                    || ' stamped=' || coalesce(v_series::text,'<null>');
           call _fail('rgd', 'R3 행동 보존', v_msg); end if;
  exception when others then
    v_msg := sqlerrm; call _fail('rgd', 'R3 행동 보존', v_msg);
  end;

  -- ── R4: 벨트 ⓒ 카탈로그 핀 (텍스트 층위 — 헤더의 정직 노트 참조) ──────────────────────
  begin
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'create_recurring_series';
    v_ok := v_def like '%is distinct from auth.uid()%' and v_def like '%not_signed_in%';
    if v_ok
      then call _pass('rgd', 'R4 벨트 카탈로그 — is distinct from + not_signed_in이 정본에 존재');
      else v_msg := left(coalesce(v_def, '<no def>'), 200); call _fail('rgd', 'R4 벨트 카탈로그', v_msg); end if;
  exception when others then
    v_msg := sqlerrm; call _fail('rgd', 'R4 벨트 카탈로그', v_msg);
  end;

  perform set_config('request.jwt.claim.sub', '', false);
end $$;
