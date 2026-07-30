-- ═══ 0044: R1 하드닝 — 돈 적대 검증이 잡은 2버그 + 테스트 계정 게이트 (R2는 0045로) ═══
--
-- ① [정직 수정] 실패 시도 기록은 in-DB에서 불가능했다 — raise exception이 트랜잭션 전체를
--    롤백하므로 0043의 실패 insert는 죽은 코드. 제거하고 각서로 남김: 실패 영속화는 에러를
--    받은 쪽(엣지 함수 래퍼, service role)이 기록해야 한다 [실PG 마일스톤]. 성공 기록은
--    업서트(미래의 외부 실패 기록과 키 공존 대비). 같은 키 재시도: 성공 후=같은 부킹 반환,
--    실패 후=행이 없으므로 새 시도로 진행 — 둘 다 안전.
-- ② [버그] pay의 approval 검증이 락 이전 스냅샷: 락 대기 중 이탈 좌초가 approval을 pending으로
--    되돌리면 stale 검사를 통과해 pending 강아지에 부킹이 생길 수 있다 — 락 후 재독으로 수정.
-- ③ 플래그 입도: 전역 club_delegation_v2 외에 **테스트 계정 허용목록** — Sean 계정 테스트를
--    위해 전역 프로덕션 플래그를 켤 필요가 없다.
-- ④ 명시 문서화: charge_state는 캐시 프로젝션 (정본 = 홀드 컬럼 + bookings + payment_attempts)
--    — 스펙 §2와 정합, 드리프트 검사 대상 유지.

-- ---------- ③ 테스트 계정 허용목록 ----------
create table if not exists club_test_accounts (
  profile_id uuid primary key references profiles(id) on delete cascade,
  note text,
  added_at timestamptz not null default now()
);
alter table club_test_accounts enable row level security;   -- 정책 없음 — 운영(service role)만

create or replace function _club_require_v2() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if club_flag('club_delegation_v2') then return; end if;
  if exists (select 1 from club_test_accounts where profile_id = auth.uid()) then return; end if;
  raise exception 'feature_disabled';
end $$;
revoke execute on function _club_require_v2() from public, anon, authenticated;

-- ---------- ①② 결제 RPC 재정의 (최신 정의 = 0043, grep 확인) ----------
create or replace function session_pay_delegation(p_session_dog uuid, p_idem_key text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  sd record; s record; v_km numeric; v_bid uuid; v_reserved int;
  v_start timestamptz; v_end timestamptz; v_clash boolean; v_prev uuid;
  v_hold text; v_hexp timestamptz; v_approval text; v_booking uuid;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if coalesce(trim(p_idem_key), '') = '' then raise exception 'idem_key_required'; end if;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  if sd.owner_profile_id <> auth.uid() then raise exception 'not_owner'; end if;

  -- 멱등 재전송: 같은 키의 '성공' 시도 → 같은 부킹 반환 (실패 키는 재시도 허용 — 업서트)
  select booking_id into v_prev from payment_attempts
  where session_dog_id = p_session_dog and kind = 'charge' and idempotency_key = p_idem_key and result = 'ok';
  if v_prev is not null then return v_prev; end if;

  select * into s from club_sessions where id = sd.session_id for update;
  if s.status not in ('open', 'full') or s.scheduled_at < now() then raise exception 'session_closed'; end if;

  -- [②] 락 '후' 재독 — approval·booking·hold 전부 (락 대기 중 이탈 좌초/변경 반영)
  select approval, booking_id, hold_status, hold_expires_at
    into v_approval, v_booking, v_hold, v_hexp
  from session_dogs where id = p_session_dog;
  if v_approval <> 'approved' or v_booking is not null then raise exception 'not_payable'; end if;

  -- 홀드 만료 시: 같은 락 안에서 정원 재확인 → 통과하면 바로 부킹 (중간 홀드 잔재 없음)
  if not (v_hold = 'active' and v_hexp > now()) then
    v_reserved := _club_delegated_reserved(sd.session_id);
    if v_reserved >= s.delegated_dog_capacity then raise exception 'no_capacity'; end if;
  end if;

  select km into v_km from routes where id = s.route_id;
  if v_km is null then raise exception 'route_required'; end if;
  v_start := s.scheduled_at;
  v_end := s.scheduled_at + make_interval(mins => (v_km * 8 + 25)::int);
  select exists (
    select 1 from bookings c
    where c.dog_id = sd.dog_id
      and c.status in ('matching','runner_pending','confirmed','runner_enroute','picked_up','active')
      and c.scheduled_at < v_end
      and c.scheduled_at + make_interval(mins => (c.km * 8 + 25)::int) > v_start
  ) into v_clash;
  if v_clash then raise exception 'dog_slot_clash'; end if;

  insert into bookings
    (owner_id, dog_id, runner_id, route_id, status, scheduled_at,
     km, addons, base_fare, distance_fare, addon_fare, total_price, min_fare, club_session_id)
  values
    (sd.owner_profile_id, sd.dog_id, null, s.route_id, 'matching', s.scheduled_at,
     v_km, '[]', 9900, club_fare(v_km) - 9900, 0, club_fare(v_km), 9900, sd.session_id)
  returning id into v_bid;

  update session_dogs set booking_id = v_bid, hold_status = 'consumed' where id = p_session_dog;
  insert into payment_attempts (session_dog_id, booking_id, kind, idempotency_key, result)
  values (p_session_dog, v_bid, 'charge', p_idem_key, 'ok')
  on conflict (session_dog_id, kind, idempotency_key) where idempotency_key is not null
  do update set result = 'ok', booking_id = excluded.booking_id, detail = null, created_at = now();

  insert into notifications (profile_id, kind, title, body, ref_id) values
    (sd.owner_profile_id, 'booking', '결제 완료 — 자리 확정',
     to_char(s.scheduled_at at time zone 'Asia/Seoul', 'FMMM"월" FMDD"일" HH24:MI')
     || ' 위탁이 확정됐어요 — 담당 러너는 집결지에서 배정돼요', v_bid),
    (s.host_profile_id, 'community', '위탁 결제 완료', '위탁 강아지의 결제가 완료됐어요', sd.session_id);
  return v_bid;
end $$;

comment on function session_pay_delegation is
  'R1 하드닝(0044): 락 후 재독(approval·booking·hold — 락 대기 중 좌초 반영) · 실패 = 전량 롤백
(상업적 부분 상태 0, in-DB 실패 기록은 불가능하므로 없음 — 외부 기록은 실PG 래퍼 몫) ·
같은 키: 성공 후 재전송=같은 부킹, 실패 후 재시도=새 시도.';
comment on table club_test_accounts is
  'R1 하드닝(0044): 위탁 v2 테스트 허용목록 — 전역 플래그 OFF에서도 등재 계정만 진입 가능';
