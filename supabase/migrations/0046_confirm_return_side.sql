-- ═══ 0046: 반환 확인 명시 side — 솔로 테스트 문법 정합 (0045는 원격 적용됨 → 신규 번호 규칙) ═══
-- confirm_handoff가 이미 확립한 문법: "한 계정이 양측인 솔로 테스트에서 서버가 역할을 추측할
-- 수 없음" — side 명시. 반환 확인도 동일해야 한다: 보호자==러너인 솔로 루프에서 기존 추론은
-- 항상 owner로 해석돼 runner 측이 영원히 닿지 않았다 (SQL 수기 스탬프는 정직 원칙 위반 소지).
-- 명시 side는 검증을 통과해야 한다: 그 side의 실제 당사자가 아니면 not_your_side.

drop function if exists session_confirm_return(uuid);

create or replace function session_confirm_return(p_session_dog uuid, p_side text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  sd record; v_runner uuid; v_side text; v_both boolean;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if p_side is not null and p_side not in ('owner', 'runner') then raise exception 'bad_side'; end if;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  perform 1 from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독
  if sd.custody_phase <> 'return_pending' then raise exception 'not_return_pending'; end if;
  select runner_id into v_runner from bookings where id = sd.booking_id;

  -- side 해석: 명시가 우선 (명시 시 그 측의 당사자인지 검증) · 미명시 = 기존 추론
  if p_side = 'owner' then
    if auth.uid() <> sd.owner_profile_id then raise exception 'not_your_side'; end if;
    v_side := 'owner';
  elsif p_side = 'runner' then
    if auth.uid() is distinct from v_runner then raise exception 'not_your_side'; end if;
    v_side := 'runner';
  elsif auth.uid() = sd.owner_profile_id then v_side := 'owner';
  elsif auth.uid() = v_runner then v_side := 'runner';
  else raise exception 'not_party'; end if;

  if v_side = 'owner' then
    update session_dogs set owner_confirmed_return_at = coalesce(owner_confirmed_return_at, now())
    where id = p_session_dog;
  else
    update session_dogs set runner_confirmed_return_at = coalesce(runner_confirmed_return_at, now())
    where id = p_session_dog;
  end if;

  select owner_confirmed_return_at is not null and runner_confirmed_return_at is not null
    into v_both from session_dogs where id = p_session_dog;

  if v_both then
    insert into dog_custody_events
      (session_dog_id, from_type, from_profile_id, to_type, to_profile_id, event_type,
       confirmation_kind, meta)
    values (sd.id, 'runner', v_runner, 'owner', sd.owner_profile_id, 'return',
      case when sd.return_override is not null then (sd.return_override->>'kind') else 'app_user' end,
      case when sd.return_override is not null then jsonb_build_object('override', sd.return_override) end);
    update session_dogs set
      custodian_type = 'owner', custodian_profile_id = owner_profile_id, custodian_external = null,
      custody_phase = 'resolved',
      responsible_profile_id = owner_profile_id,
      checked_out_at = coalesce(checked_out_at, now()),
      payout_state = case when payout_state = 'earned' then 'payable' else payout_state end
    where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id) values
      (sd.owner_profile_id, 'booking', '반환 완료', '위탁이 안전하게 끝났어요 — 리포트를 확인하세요', sd.booking_id),
      (v_runner, 'booking', '반환 완료', '반환이 확인됐어요 — 정산이 지급 대기로 넘어갑니다', sd.booking_id);
  else
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (case when v_side = 'owner' then v_runner else sd.owner_profile_id end,
            'booking', '반환 확인 요청', '상대방이 반환을 확인했어요 — 확인해주세요', sd.booking_id);
  end if;
  return jsonb_build_object('both', v_both);
end $$;

grant execute on function session_confirm_return(uuid, text) to authenticated;

comment on function session_confirm_return is
  'R2+0046: 양측 반환 확인 — side 명시 지원 (confirm_handoff 문법 정합, 솔로 테스트). 명시 side는 당사자 검증(not_your_side)';
