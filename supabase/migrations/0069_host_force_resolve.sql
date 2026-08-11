-- ═══ 0069: C4 + H5 — a stuck dog gets a host terminal, and a two-sided override finalizes ═══
--
-- Two defects from the club audit (2026-08-11), both of which strand a session and its payouts
-- forever, and both of which live in the return/custody family:
--
-- C4 — a picked-up dog whose run never ends locks the session and the payouts.
--   `_club_dogs_unresolved` (0045:328-336) counts a delegated dog whose custodian is still the
--   runner while its booking is picked_up/active/completed, so `club_finish_session` raises
--   `dogs_not_returned` forever. The runner confirms handoff, then never presses 시작/종료 (the
--   phone dies). There is no row for the host to act on and no button: the console's only
--   override renders solely for `return_pending` (console:201, 483-508), and the blocker banner
--   even says '반환 미완' — for a dog that was never returned because the run never started.
--   PANEL VERDICT: the schema already answers this, NO transition-map change is needed.
--   `picked_up → incident_review` and `active → incident_review` are already legal (0066:53-54)
--   and `_club_dogs_unresolved` counts only picked_up/active/completed — so moving the stuck
--   dog's booking to `incident_review` clears the session blocker for free, while
--   `club_release_payouts` still cannot leak (it needs no open incident, 0045:427).
--
-- H5 — custody transfer has no production terminal for the host. `session_transfer_initiate` is
--   runner-only (0045:177), so a dog stalled in `transfer_pending` MID-RUN has no host exit.
--   The same RPC closes it: mid-run means the booking is picked_up/active, which is exactly the
--   window §A covers. (A stalled transfer on a COMPLETED booking is deliberately NOT in scope
--   here — `session_transfer_cancel` (0045:299) already returns it to `return_pending` for the
--   normal return flow, and forcing a terminal there would fabricate a return.)
--
-- §B is the third one, found while reading C4: the CURRENT console override reproduces the bug
--   it works around. `session_custody_override` (0045:145-150) stamps ONE side and leaves
--   finalization "to the remaining party's session_confirm_return" — but the console renders
--   BOTH buttons when both sides are unconfirmed (console:485-505). Press both: both timestamps
--   are set, `custody_phase` stays `return_pending`, no `dog_custody_events` row is written,
--   `payout_state` never reaches `payable`. The dog then leaves `returnStuck` but stays in
--   `unreturned` — the blocker banner reads '반환 미완' with NO button at all, and
--   `club_finish_session` raises `dogs_not_returned` forever. 60 E19 covers only the
--   single-sided path, so this is green today. Fix: extract the both-sides terminal into
--   `_club_finalize_return` and call it from BOTH writers.
--
-- Honesty note on §A: the dog is NOT recorded as returned and NOT recorded as transferred —
-- neither is known. It stays in the runner's custody with the case open; the case is what
-- carries the truth. `club_finish_session` still refuses to close on an unadopted incident
-- (0048:398), so a host cannot force-resolve and walk away.
--
-- `set search_path = public, pg_temp` is re-stated in every body: replace resets proconfig and
-- pin 98 H1 fails the harness on any public definer function without it.
-- Pins: 107_recovery_force_resolve_suite.sql (mutation map in its header).

-- ---------- §B. 양측 반환 확정 종단 — 두 쓰기 경로가 공유한다 ----------
-- 0046 session_confirm_return의 both 분기를 바이트 그대로 옮긴 것 + 멱등 가드.
-- 반환값: 이번 호출이 실제로 마감했으면 true (이미 resolved면 false — 이중 이벤트 금지).
create or replace function _club_finalize_return(p_session_dog uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare sd record; v_runner uuid;
begin
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then return false; end if;
  if sd.owner_confirmed_return_at is null or sd.runner_confirmed_return_at is null then return false; end if;
  if sd.custody_phase = 'resolved' then return false; end if;              -- 멱등
  select runner_id into v_runner from bookings where id = sd.booking_id;

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
  return true;
end $$;
revoke execute on function _club_finalize_return(uuid) from public, anon, authenticated;

comment on function _club_finalize_return is
  '0069 §B: 양측 반환 확정 종단 (커스터디 이벤트·resolved·payable·양측 알림) — session_confirm_return과
session_custody_override가 공유한다. 콘솔이 양측 버튼을 모두 그리므로 어느 쪽이 마지막이든 마감돼야 한다';

-- ---------- 반환 확인 v3 — 종단을 공유 함수에 위임 (그 외 0046 그대로) ----------
create or replace function session_confirm_return(p_session_dog uuid, p_side text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
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
    perform _club_finalize_return(p_session_dog);                       -- [0069 §B] 공유 종단
  else
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (case when v_side = 'owner' then v_runner else sd.owner_profile_id end,
            'booking', '반환 확인 요청', '상대방이 반환을 확인했어요 — 확인해주세요', sd.booking_id);
  end if;
  return jsonb_build_object('both', v_both);
end $$;
grant execute on function session_confirm_return(uuid, text) to authenticated;

comment on function session_confirm_return is
  'R2+0046+0069: 양측 반환 확인 — side 명시 지원 (confirm_handoff 문법 정합, 솔로 테스트).
명시 side는 당사자 검증(not_your_side) · 양측 완성 시 종단은 _club_finalize_return 공유';

-- ---------- 커스터디 오버라이드 v2 — 양측이 차면 여기서도 마감한다 (0045 본문 + §B 호출) ----------
create or replace function session_custody_override(
  p_session_dog uuid, p_side text, p_kind text, p_artifact jsonb
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare sd record; s record; v_runner uuid;
begin
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독 (0044 교훈)
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  if p_side not in ('owner','runner') then raise exception 'bad_side'; end if;
  if p_kind not in ('witness','assisted') then raise exception 'bad_kind'; end if;
  if sd.custody_phase <> 'return_pending' then raise exception 'not_return_pending'; end if;
  select runner_id into v_runner from bookings where id = sd.booking_id;
  -- 자기 오버라이드 금지: 호스트가 그 에지의 당사자면 불가 (백업 호스트/ops 몫)
  if auth.uid() = sd.owner_profile_id or auth.uid() = v_runner then raise exception 'self_override'; end if;
  -- witness는 강증빙 필수 (PIN/QR/서명/사진 — 비어있으면 거부)
  if p_kind = 'witness' and (p_artifact is null or p_artifact = '{}'::jsonb) then
    raise exception 'artifact_required';
  end if;

  update session_dogs set return_override = jsonb_build_object(
    'side', p_side, 'kind', case p_kind when 'witness' then 'host_witnessed_receipt' else 'authorized_person_pin' end,
    'artifact', p_artifact, 'by', auth.uid(), 'at', now())
  where id = p_session_dog;
  -- 해당 측 스탬프를 대신 기록 (assisted = 당사자 본인 확인을 호스트 기기로 수집)
  if p_side = 'owner' then
    update session_dogs set owner_confirmed_return_at = coalesce(owner_confirmed_return_at, now()) where id = p_session_dog;
  else
    update session_dogs set runner_confirmed_return_at = coalesce(runner_confirmed_return_at, now()) where id = p_session_dog;
  end if;
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (case when p_side = 'owner' then sd.owner_profile_id else v_runner end,
          'community', '반환 확인 대리 기록', '호스트가 현장 확인으로 반환 확인을 기록했어요 (' || p_kind || ')', sd.session_id);
  -- [0069 §B] 종전 주석은 "양측 완성 시 마무리는 남은 당사자의 session_confirm_return이 수행"이라고
  -- 가정했다. 콘솔은 양측 미확인일 때 버튼 두 개를 모두 그린다 — 둘 다 누르면 남은 당사자가 없어
  -- 영원히 return_pending에 멈췄다. 어느 쪽이 마지막 스탬프든 여기서 마감한다.
  perform _club_finalize_return(p_session_dog);
end $$;
grant execute on function session_custody_override(uuid, text, text, jsonb) to authenticated;

comment on function session_custody_override is
  'R2(0045)+0069: 호스트 대리 반환 스탬프 (witness=강증빙 필수 · assisted) · 자기 오버라이드 금지 ·
양측 스탬프가 차면 _club_finalize_return으로 즉시 마감 (양측 오버라이드 좌초 폐쇄)';

-- ---------- §A. 호스트 강제 종결 — 끝나지 않는 러닝의 유일한 출구 (C4 + H5) ----------
create or replace function session_host_force_resolve(
  p_session_dog uuid, p_reason text, p_artifact jsonb
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare sd record; s record; v_runner uuid; v_bst text; v_inc uuid;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'reason_required'; end if;
  if p_artifact is null or p_artifact = '{}'::jsonb then raise exception 'artifact_required'; end if;
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독 (0044 교훈)
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  if sd.custody <> 'runner_delegated' or sd.booking_id is null then raise exception 'not_delegated'; end if;
  select status::text, runner_id into v_bst, v_runner from bookings where id = sd.booking_id for update;
  -- 자기 오버라이드 금지 — session_custody_override와 같은 법 (백업 호스트/ops 몫)
  if auth.uid() = sd.owner_profile_id or auth.uid() = v_runner then raise exception 'self_override'; end if;
  -- 적용 범위는 '러닝이 끝나지 않은 개'뿐이다. 반환 국면(completed)은 반환 흐름의 몫이고
  -- (session_confirm_return · session_custody_override · session_transfer_cancel),
  -- 여기서 종결하면 일어나지 않은 반환을 날조하게 된다.
  if v_bst not in ('picked_up', 'active') then raise exception 'not_stuck'; end if;

  -- 0058 session_transfer_accept 외부 분기의 종단을 그대로 쓴다 — 전이 맵은 건드리지 않는다
  -- (picked_up|active → incident_review는 이미 합법, 0066:53-54).
  update runs set ended_at = now(), end_reason = 'incident', condition_note = trim(p_reason)
  where booking_id = sd.booking_id and ended_at is null;
  update bookings set status = 'incident_review' where id = sd.booking_id;
  insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
  values (sd.id, v_runner, 'revoked', 'host_force_resolve', auth.uid());
  update dog_run_segments set left_at = now() where session_dog_id = sd.id and left_at is null;

  -- 케이스는 검증된 경로(0067)로 연다: 대상견 지급 보류 + 호스트/백업 + 커밋 러너 팬아웃 +
  -- 대상견 보호자 알림이 전부 그 안에 있다. 호스트는 이미 당사자·주체 검증을 통과한다.
  v_inc := club_incident_open(sd.session_id, 'S2',
    '호스트 강제 종결 — ' || trim(p_reason), sd.dog_id, sd.booking_id, null);
  insert into club_incident_evidence (incident_id, kind, payload, created_by)
  values (v_inc, 'document', p_artifact, auth.uid());

  -- 개가 어디 있는지는 모른다 — 반환도 이양도 기록하지 않는다. 커스터디언은 여전히 러너이고,
  -- 진실은 케이스가 나른다. custody_phase='with_custodian'는 종단 허용목록을 통과하므로
  -- (0045:328-336) 세션 차단이 풀리고, club_finish_session은 케이스 인수 전까진 여전히 거부한다.
  update session_dogs set
    custody_phase = 'with_custodian',
    pending_transfer = null,
    return_override = jsonb_build_object(
      'side', 'host', 'kind', 'host_force_resolve', 'artifact', p_artifact,
      'reason', trim(p_reason), 'by', auth.uid(), 'at', now(), 'incident', v_inc)
  where id = p_session_dog;
  return v_inc;
end $$;
-- 0057 §1 sweep은 그 시점의 함수들만 훑는다 — 새 definer 함수는 본인 파일에서 public/anon을
-- 직접 회수해야 한다 (Supabase default privileges가 PUBLIC EXECUTE를 준다). 99 S1이 감시한다.
revoke execute on function session_host_force_resolve(uuid, text, jsonb) from public, anon;
grant execute on function session_host_force_resolve(uuid, text, jsonb) to authenticated;

comment on function session_host_force_resolve is
  '0069 §A (C4+H5): 호스트 강제 종결 — 러닝이 끝나지 않은 위탁견(picked_up/active)의 유일한 출구.
호스트 전용·자기 오버라이드 금지·증빙 필수 · 런 종료(incident)·부킹 incident_review·배정 폐쇄 ·
S2 케이스 개설(지급 보류·팬아웃·보호자 알림) · 반환을 날조하지 않는다 (커스터디언은 러너 유지)';
