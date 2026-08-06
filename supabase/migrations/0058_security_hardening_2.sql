-- ═══ 0058: 서버 원격 취약점 P0 봉인 2차 (0057 완결성 갭 — 독립 검증 리뷰어 2인 실증) ═══
-- 왜: 0057이 문 여섯을 닫았지만, 두 독립 리뷰어가 각자 **엔드투엔드로 실행해** 잔여 갭 5종을 증명했다.
--   공통 뿌리는 0057이 §2에서 이미 명명한 것과 같다 — bare `X <> auth.uid()` 게이트는 우변(또는
--   비교 컬럼)이 NULL이면 `X <> NULL`=NULL → `if NULL then`이 **분기하지 않아** 조용히 통과한다.
--   0057 §2는 돈·커스터디 RPC 5종을 is-distinct로 고쳤지만 (a) club_incident_resolve (b)
--   session_transfer_accept/cancel 를 남겼고(§2가 스스로 '한계'로 명기한 belt-b 제외), 그 둘의
--   비교 대상(case_owner·pending_transfer.by)이 바로 **설계상 NULL이 되는 값**이라 갭이 남았다.
--
-- 인용 발견 (각각 리뷰어가 EXECUTE로 재현):
--   F1(P1 MONEY) club_incident_resolve — 갓 개설 인시던트는 case_owner=NULL. `auth.uid() <> v_owner`가
--     NULL이라 게이트 미발화 → 비-호스트 당사자(처리 러너)가 자기 케이스를 해소하고 자기 payout_hold
--     (held→none)를 풀었다. 자기 정산 홀드 자가 해제 = 돈.
--   F2(P2) session_transfer_accept/cancel — pending_transfer.by가 NULL(pre-0057 anon 개시 잔재)이면
--     외부 이양 분기 게이트가 fail-open → 인증된 외부인이 외부 커스터디 이양을 확정(→incident_review).
--   F3(P2→P1) bookings 클라 직접 쓰기 = **전면 차단**(서버-쓰기 전용). 0057 §4 블랙리스트를 deny-all로
--     승격 — status(수수료 회피)·reschedule·route_id·cancel_reason를 한 번에 닫고 미래 컬럼도 자동 포섭.
--   F4(P2→P1) 0057 §1 sweep의 `pg_get_userbyid(proowner)=current_user` 필터가 **비소유** definer 함수를
--     건너뛴다 → 원격에 대시보드/supabase 관리 함수가 있으면 anon 실행 표면이 남고 로컬 S1 핀은 못 본다.
--   F5 나머지 bare-`<>` 게이트 전수 감사 — 우변이 NULL 가능 ∧ 당사자 도달 ∧ 상태 영향인 것만 위험.
--     F1/F2 외엔 전부 NOT NULL 컬럼(host_profile_id·owner_profile_id·owner_id·sender_id) 비교라
--     인증 호출자(auth.uid() non-null)에게 `<>`가 정확히 발화 → assessed-safe (하단 §5 표).
--
-- 불변(0055 §계약): 0057까지는 정본. 파일 0001–0057은 한 글자도 수정하지 않는다 —
--   모든 변경은 이 파일의 create or replace / alter / do-block sweep.
--   새·재정의 definer 함수는 **본문 헤더에** `set search_path = public, pg_temp` (98 H1 법 — 0055 §2
--   ALTER가 create or replace에 리셋되므로 본문에 직접 박는다. 0057 전 함수가 이 규율을 따른다).
-- 재현 규율(0057 §2 계승): belt-b/인시던트 함수는 최신 정본(F1=0052:443·F2=0045:199/300)에서 바이트
--   그대로 옮기되 의도한 편집만 한다 — ⓐ search_path pg_temp ⓑ not_signed_in 선두 가드 ⓒ 당사자
--   게이트 NULL-안전화. 나머지 본문·revoke/grant 꼬리는 바이트 보존.
set client_min_messages = warning;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §1. F1 (P1 MONEY) — club_incident_resolve NULL-fail-open (case_owner=NULL 자가 해소·홀드 자가 해제)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 최신 정본 0052:443(rev2 — 백업 호스트 해소 허용). 편집 셋: ⓐ pg_temp ⓑ not_signed_in ⓒ 게이트 NULL-안전.
-- 게이트 재작성 (핵심): 기존 `if auth.uid() <> v_owner and not exists(host/backup) then raise`는
--   v_owner(case_owner)=NULL에서 `NULL and not exists(true)` = NULL → 미발화 → 비-호스트 통과.
--   **주의**: 단순히 `auth.uid() = v_owner or (v_owner is null and exists(...))` 로 바꿔도 첫 항
--   `auth.uid() = NULL`=NULL이라 `NULL or false`=NULL로 여전히 샌다. 그래서 첫 항을 `v_owner is not null
--   and auth.uid() = v_owner`로 **non-null 가드**해 3치 논리 누수를 원천 차단한다. exists(...)는 boolean로
--   접히므로 절대 NULL이 아니다 → 전체 판정이 TRUE/FALSE로만 확정된다.
-- 허용 집합(0052 rev2 의도 보존): 케이스 오너 본인 OR 세션 호스트/백업 호스트. director 제안(호스트는
--   case_owner=NULL일 때만)보다 **넓다** — 0052 rev2가 죽은 버튼 제거로 세운 '호스트/백업은 항상 해소
--   가능'을 되돌리지 않기 위해서다(G13 핀 계약). 호스트는 신뢰 역할이라 초과 허용이 아니며, 이 파일이
--   닫으려는 '비-호스트 당사자 자가 해소'는 그대로 차단된다. (호스트를 더 좁히려면 director 재량 — 그
--   경우도 non-null 가드는 유지해야 NULL 누수가 안 생긴다.)
create or replace function club_incident_resolve(p_incident uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_session uuid; v_owner uuid; v_sd record;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  perform _club_require_v2();
  select session_id, case_owner into v_session, v_owner from club_incidents where id = p_incident;
  if v_session is null then raise exception 'not_found'; end if;
  -- [0058 F1] NULL-안전 게이트: 케이스 오너 본인(non-null 가드) 또는 세션 호스트/백업 호스트만 해소.
  -- (case_owner=NULL 갓 개설 케이스에서 비-호스트 당사자가 auth.uid() <> NULL = NULL로 조용히 통과해
  --  자기 payout_hold를 풀던 fail-open 봉함. 0052 rev2의 백업 호스트 해소 허용은 그대로 유지.)
  if not (
       (v_owner is not null and auth.uid() = v_owner)
       or exists (select 1 from club_sessions where id = v_session
                    and auth.uid() in (host_profile_id, backup_host_profile_id))
     ) then
    raise exception 'not_case_owner';
  end if;
  if p_note is not null then
    insert into club_incident_evidence (incident_id, kind, payload, created_by)
    values (p_incident, 'text', jsonb_build_object('note', p_note, 'at', now()), auth.uid());
  end if;
  update club_incidents set state = 'resolved', resolved_at = now() where id = p_incident;
  -- 이 인시던트가 걸었던 지급 보류만 해제 — 같은 강아지의 다른 오픈 케이스가 있으면 유지
  for v_sd in select id, dog_id from session_dogs
    where payout_hold = 'held' and payout_hold_reason = 'incident' and payout_hold_incident = p_incident
  loop
    if not exists (
      select 1 from club_incident_subjects sub join club_incidents i2 on i2.id = sub.incident_id
      where sub.subject_type = 'dog' and sub.subject_id = v_sd.dog_id
        and i2.state <> 'resolved' and i2.id <> p_incident) then
      update session_dogs set payout_hold = 'none', payout_hold_reason = null,
        payout_hold_incident = null where id = v_sd.id;
    end if;
  end loop;
end $$;
revoke execute on function club_incident_resolve(uuid, text) from public, anon;
grant execute on function club_incident_resolve(uuid, text) to authenticated;

-- 형제 감사: club_incident_assign(0045:375)은 게이트가 `not exists(club_sessions … host_profile_id =
--   auth.uid())` — `not exists`는 NULL이 아닌 boolean이라 case_owner를 `<>`로 읽지 않는다. anon(auth.uid
--   =NULL)은 host_profile_id=NULL 매칭 0행 → not exists=true → not_host로 fail-CLOSED. §1(0057) anon
--   revoke도 겹친다. → 수정 불필요(정본 미변경). 0055 §2가 ALTER한 pg_temp도 create or replace 안 하므로 유지.

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §2. F2 (P2) — session_transfer_accept / session_transfer_cancel NULL-`by` fail-open
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 0057 §2가 belt-b에서 명시적으로 제외한 둘(드리프트 위험 vs 이득 0으로 판단했으나, 리뷰어가 pending_
--   transfer.by=NULL(pre-0057 anon 개시가 by=auth.uid()=NULL로 남긴 shape)에서 실 fail-open을 실행 재현).
-- 최신 정본 0045:199(accept, 99줄)·0045:300(cancel). 편집: ⓐ pg_temp ⓑ not_signed_in ⓒ 게이트 NULL-안전.
--   · accept 러너 분기: `auth.uid() <> (toProfile)` → is distinct from.
--   · accept 외부 분기: `(by) is null or auth.uid() is distinct from (by)` (by=NULL이면 명시적 거부).
--   · cancel: 두 항 모두 is distinct from — by=NULL이면 `auth is distinct from NULL`=TRUE라 initiator 자격
--     소멸 → 호스트만 취소 가능으로 fail-CLOSED (외부-분기 명시 거부와 등가 효과).
-- 본문 나머지는 0045에서 바이트 그대로 옮긴다.

-- ---------- session_transfer_accept (0045:199 정본) ----------
create or replace function session_transfer_accept(p_session_dog uuid, p_artifact jsonb default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  sd record; s record; v_old_runner uuid; v_t jsonb; v_load int; v_cap int; v_ev uuid;
  v_bst text; v_inc uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독
  if sd.custody_phase <> 'transfer_pending' or sd.pending_transfer is null then raise exception 'no_pending_transfer'; end if;
  v_t := sd.pending_transfer;
  select runner_id into v_old_runner from bookings where id = sd.booking_id;

  if v_t->>'toType' = 'runner' then
    if auth.uid() is distinct from (v_t->>'toProfile')::uuid then raise exception 'not_transfer_target'; end if;
    -- 수신 러너 검증: 티어 + 부하 (물리적으로 잡은 모든 개 ≤ 캡)
    v_cap := _club_runner_cap(auth.uid());
    if coalesce(v_cap, 0) = 0 then raise exception 'not_certified_runner'; end if;
    select count(*) into v_load from session_dogs x
    where x.custodian_type = 'runner' and x.custodian_profile_id = auth.uid()
      and x.custody_phase in ('with_custodian','return_pending','transfer_pending');
    if v_load >= v_cap then raise exception 'handler_overloaded'; end if;
    -- 원자 6단계: 배정 이벤트(교체·수락) → 부킹 러너 교체 → 커스터디 이벤트 → 세그먼트 → 프로젝션 → 알림
    insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
    values (sd.id, v_old_runner, 'replaced', 'emergency_transfer', auth.uid()),
           (sd.id, auth.uid(), 'accepted', 'emergency_transfer', auth.uid());
    update bookings set runner_id = auth.uid() where id = sd.booking_id;
    insert into dog_custody_events
      (session_dog_id, from_type, from_profile_id, to_type, to_profile_id, event_type, confirmation_kind, reason)
    values (sd.id, 'runner', v_old_runner, 'runner', auth.uid(), 'emergency_transfer', 'app_user', v_t->>'reason')
    returning id into v_ev;
    update dog_run_segments set left_at = now(), transfer_event_id = v_ev
    where session_dog_id = sd.id and left_at is null;
    insert into dog_run_segments (session_dog_id, run_id, runner_profile_id, joined_at, transfer_event_id)
    select sd.id, r.id, auth.uid(), now(), v_ev from runs r where r.booking_id = sd.booking_id;
    update session_dogs set
      custodian_profile_id = auth.uid(), custody_phase =
        case when exists (select 1 from bookings b where b.id = sd.booking_id and b.status = 'completed')
             then 'return_pending' else 'with_custodian' end,
      responsible_profile_id = auth.uid(),
      current_runner_profile_id = auth.uid(),
      runner_confirmed_return_at = null,                 -- 새 러너 기준으로 반환 확인 재시작
      pending_transfer = null
    where id = sd.id;
    insert into notifications (profile_id, kind, title, body, ref_id) values
      (sd.owner_profile_id, 'booking', '담당 러너 변경', '비상 이양으로 담당 러너가 변경됐어요 — 새 담당을 확인하세요', sd.booking_id),
      (s.host_profile_id, 'community', '비상 이양 완료', '러너간 커스터디 이양이 완료됐어요', sd.session_id);
  else
    -- clinic/authority/authorized_person: 개시 러너가 증빙과 함께 확정 (수신자는 앱 사용자가 아님)
    if (v_t->>'by') is null or auth.uid() is distinct from (v_t->>'by')::uuid then raise exception 'not_transfer_target'; end if;
    if p_artifact is null or p_artifact = '{}'::jsonb then raise exception 'artifact_required'; end if;
    select status::text into v_bst from bookings where id = sd.booking_id;

    -- [주행 전·중 비상 = 원자 인시던트 경로] 단순 거부 금지 — 부상견은 지금 병원에 가야 한다.
    -- ① 런 종료(end_reason=incident — 0001 이넘에 이미 존재) ② 부킹 incident_review
    -- (전이 맵 허용: picked_up|active → incident_review; 완료 통계·패치·리뷰 흐름 오염 없음)
    -- ③ 배정 폐쇄(revoked) ④ 인시던트 개설 + 대상(dog·session·booking) + 증빙 연결
    if v_bst in ('picked_up','active') then
      update runs set ended_at = now(), end_reason = 'incident',
        condition_note = coalesce(v_t->>'reason', '외부 커스터디 이양')
      where booking_id = sd.booking_id and ended_at is null;
      update bookings set status = 'incident_review' where id = sd.booking_id;
      insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
      values (sd.id, v_old_runner, 'revoked', 'external_custody', auth.uid());
      insert into club_incidents (session_id, severity, state, opened_by, summary)
      values (sd.session_id, 'S2', 'open', auth.uid(),
              coalesce(v_t->>'reason', '주행 중 외부 이양') || ' → ' || coalesce(v_t->>'toExternal', '외부 기관'))
      returning id into v_inc;
      insert into club_incident_subjects (incident_id, subject_type, subject_id) values
        (v_inc, 'dog', sd.dog_id), (v_inc, 'session', sd.session_id), (v_inc, 'booking', sd.booking_id);
      insert into club_incident_evidence (incident_id, kind, payload, created_by)
      values (v_inc, 'document', p_artifact, auth.uid());
    end if;

    insert into dog_custody_events
      (session_dog_id, from_type, from_profile_id, to_type, to_profile_id, to_external,
       event_type, confirmation_kind, reason, incident_id, meta)
    values (sd.id, 'runner', v_old_runner, v_t->>'toType', (v_t->>'toProfile')::uuid, v_t->>'toExternal',
      case when v_t->>'toType' = 'clinic' then 'vet_transfer' else 'authority_transfer' end,
      case when v_t->>'toType' = 'clinic' then 'clinic_receipt' else 'ops_attestation' end,
      v_t->>'reason', v_inc, jsonb_build_object('artifact', p_artifact))
    returning id into v_ev;
    update dog_run_segments set left_at = now(), transfer_event_id = v_ev
    where session_dog_id = sd.id and left_at is null;
    update session_dogs set
      custodian_type = v_t->>'toType', custodian_profile_id = (v_t->>'toProfile')::uuid,
      custodian_external = v_t->>'toExternal',
      custody_phase = 'with_custodian',                  -- 외부 커스터디언 보유 중 (종단 허용목록 통과형)
      termination_type = case when v_t->>'toType' = 'clinic' then 'vet_transfer' else termination_type end,
      payout_hold = 'held', payout_hold_reason = 'external_custody',
      pending_transfer = null
    where id = sd.id;
    insert into notifications (profile_id, kind, title, body, ref_id) values
      (sd.owner_profile_id, 'safety', '외부 커스터디 이양', coalesce(v_t->>'toExternal','외부 기관') || '(으)로 커스터디가 이양됐어요 — 즉시 확인하세요', sd.session_id),
      (s.host_profile_id, 'safety', '외부 커스터디 이양', '위탁견이 외부 커스터디로 이양됐어요 — 케이스 확인 필요', sd.session_id);
  end if;
end $$;
revoke execute on function session_transfer_accept(uuid, jsonb) from public, anon;
grant execute on function session_transfer_accept(uuid, jsonb) to authenticated;

-- ---------- session_transfer_cancel (0045:300 정본) ----------
create or replace function session_transfer_cancel(p_session_dog uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare sd record; s record; v_bst text;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독
  if sd.custody_phase <> 'transfer_pending' or sd.pending_transfer is null then
    raise exception 'no_pending_transfer';
  end if;
  -- [0058 F2] NULL-안전 게이트: by=NULL(pre-0057 anon 개시)이면 `auth is distinct from NULL`=TRUE라
  --   initiator 자격 소멸 → 호스트만 취소 가능. (기존 `auth <> by`가 NULL에서 미발화하며 비-호스트
  --   비-개시자가 transfer_pending을 되돌리던 fail-open 봉함.) host_profile_id는 NOT NULL.
  if auth.uid() is distinct from (sd.pending_transfer->>'by')::uuid and auth.uid() is distinct from s.host_profile_id then
    raise exception 'not_initiator';
  end if;
  select status::text into v_bst from bookings where id = sd.booking_id;
  if sd.pending_transfer->>'toType' = 'runner' and (sd.pending_transfer->>'toProfile') is not null then
    insert into notifications (profile_id, kind, title, body, ref_id)
    values ((sd.pending_transfer->>'toProfile')::uuid, 'booking', '이양 요청 취소',
            '커스터디 이양 요청이 취소됐어요', sd.session_id);
  end if;
  update session_dogs set
    custody_phase = case when v_bst = 'completed' then 'return_pending' else 'with_custodian' end,
    pending_transfer = null
  where id = p_session_dog;
end $$;
revoke execute on function session_transfer_cancel(uuid) from public, anon;
grant execute on function session_transfer_cancel(uuid) to authenticated;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §3. F3 (P2→P1) — bookings 클라 직접 쓰기 전면 차단 (blacklist → deny-all-client, 서버-쓰기 전용)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 왜 blacklist→deny-all: 0057 §4는 돈·신원·인계확인·일정 컬럼을 열거해 막았다(블랙리스트). 리뷰어가
--   그 목록 밖 컬럼으로 우회를 실증했다 — status(정산 전 상태 위조 = 수수료 회피, P1-5 우회)·
--   reschedule_new_time/reschedule_proposed_at(F2 R2 재우회)·route_id/address_id/cancel_reason(F-B3).
--   근본 사실: 클라는 bookings에 **아무것도 직접 쓰지 않는다** — api.ts·app/src 전수 grep 결과
--   `from('bookings')`는 전부 `.select(...)`이고 update/insert/upsert/delete가 0건이다(재확인 완료).
--   그러므로 감사 자신의 권고('클라 bookings 쓰기를 0으로 좁혀라')의 완전한 실현 = 컬럼 열거를 버리고
--   '클라 역할이면 어떤 컬럼 변경도 거부'다. 미래에 20번째 컬럼이 생겨도 자동 포섭된다(future-proof).
-- 판정: `new is distinct from old` — 행 전체 비교로 '한 컬럼이라도 바뀌면' 참. no-op UPDATE(아무것도
--   안 바뀜)는 통과(멱등). 예외명은 0057과 동일 `booking_protected_columns` 유지(이제 '보호 컬럼 = 전부').
-- 서버 경로 불변 (반드시 통과): 역할 판정은 0057 그대로 current_user다.
--   ① service_role 엣지 fn(settle-run·transition-booking) → current_user='service_role' → 가드 밖.
--   ② definer RPC(session_proposal_respond 등) 내부 → current_user='postgres' → 가드 밖.
--   ③ booking_transition 트리거(0001:218, enforce_booking_transition)는 **별개 트리거**이고 이 가드를
--      호출하지 않는다. 그 트리거·touch_updated_at·모든 definer/service-role write는 current_user가
--      authenticated/anon이 아니므로 `if current_user in (...)` 진입 자체가 안 된다 → 전원 통과.
--   (트리거 발화 순서: `_guard_booking_cols`(0x5F) < `booking_transition`(0x62) < `t_bookings_touch`(0x74)
--    바이트순 → 가드가 먼저 돌아 touch의 updated_at 세팅 전 상태를 본다. 클라 no-op은 여전히 통과.)
-- INVOKER 유지(0057 메커니즘): DEFINER면 트리거 안 current_user가 소유자(postgres)로 바뀌어 호출자
--   역할을 영원히 못 본다 — 파일 상단 0057 헤더 논거 그대로.
create or replace function _guard_booking_cols() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  -- [0058 F3] 직접 클라 쓰기(authenticated/anon)는 bookings의 **어떤 컬럼도** 직접 변경 불가 =
  --   서버-쓰기 전용. 서버 경로(service_role/postgres/definer)는 current_user가 여기 없어 통과.
  --   0057 §4의 컬럼 블랙리스트를 deny-all로 승격 — status·reschedule·route_id 등 목록 밖 우회를 일괄
  --   차단하고 미래 컬럼을 자동 포섭. 클라의 정당한 bookings 직접 쓰기 경로는 없다(api.ts 전수 grep=0).
  if current_user in ('authenticated', 'anon') then
    if new is distinct from old then
      raise exception 'booking_protected_columns'
        using detail = 'bookings는 서버 경로(엣지 함수/RPC)만 변경해요 — 클라이언트 직접 쓰기 전면 차단';
    end if;
  end if;
  return new;
end $$;
-- 트리거(0057 §4 생성)는 함수를 이름으로 참조하므로 재생성 불필요 — create or replace로 본문만 교체된다.

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §4. F4 (P2→P1) — 전 definer anon-execute 회수 sweep 재실행 (**비소유 함수 포함** — S1 false-green 봉함)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 왜: 0057 §1 sweep은 `pg_get_userbyid(proowner) = current_user`로 **소유 함수만** 돌았다(비소유 함수에
--   REVOKE가 권한 오류로 마이그레이션을 죽이는 걸 피하려는 0055 §2 계승). 그 결과 원격에 대시보드/
--   supabase가 관리하는(다른 role 소유) public definer 함수가 있으면 anon 실행 표면이 그대로 남는다.
--   로컬 하네스는 전부 postgres 소유라 S1 핀(anon 실행 가능 definer=0)이 **초록인데도** 원격은 뚫릴 수
--   있다(false-green). 여기서 소유 필터 없이 다시 돌려 표면을 실제로 닫는다.
-- 안전: postgres는 슈퍼유저라 REVOKE가 항상 성공한다. 그럼에도 각 함수 처리를 exception 핸들러로 감싸
--   insufficient_privilege면 건너뛴다(belt-and-braces — 혹여 비-슈퍼 실행 환경에서 마이그레이션이 안 죽게).
-- authenticated 보존: 0057 §1의 capture-and-restore 그대로 — 회수 전 유효 실행권(had_auth, 명시 grant든
--   PUBLIC 상속이든)을 포착하고, 있었으면 회수 후 명시 grant로 복원. 내부 `_`-헬퍼(had_auth=false)는 잠긴 채.
-- 멱등: 소유 함수는 0057이 이미 처리했다 — had_auth=true 재포착·revoke 무변화·grant 재부여로 무해.
do $$
declare r record; had_auth boolean;
begin
  for r in
    select p.oid as oid, p.oid::regprocedure as sig
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
    -- [0058 F4] 0057 §1과 달리 pg_get_userbyid(proowner)=current_user 필터 **없음** — 전 소유자 포섭.
  loop
    begin
      had_auth := has_function_privilege('authenticated', r.oid, 'execute');
      execute format('revoke execute on function %s from public, anon', r.sig);
      if had_auth then execute format('grant execute on function %s to authenticated', r.sig); end if;
    exception when insufficient_privilege then
      -- 비소유 함수라 REVOKE 권한이 없으면 건너뛴다(운영은 postgres 슈퍼유저라 도달 안 함).
      null;
    end;
  end loop;
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §5. F5 — 잔여 bare-`<>` / auth.uid() 게이트 전수 감사 결과 (fix = F1/F2, 나머지 assessed-safe)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 정본(최신 정의) 기준 definer 함수의 `X <> auth.uid()` / `auth.uid() <> X` 게이트를 전수해, 비교 대상 X가
-- **설계상 NULL 가능** ∧ **당사자 도달** ∧ **돈·상태 영향**인 것만 위험으로 분류. 결과:
--   위험(FIX): club_incident_resolve(X=case_owner, NULL 가능) → §1.  session_transfer_accept
--     (X=toProfile/by), session_transfer_cancel(X=by) → §2.  이 셋이 유일한 NULL-가능 우변 게이트.
--   assessed-safe (수정 불필요, 근거):
--     · host_profile_id <> auth.uid() (club_sessions.host_profile_id = NOT NULL, 0030:54) — 다수 클럽 RPC.
--       인증 호출자(auth.uid() non-null)에게 `<>`가 정확히 발화, anon은 §1 revoke로 본문 진입 불가.
--     · owner_profile_id <> auth.uid() (session_dogs.owner_profile_id = NOT NULL, 0030:83) — session_cancel_
--       delegation(0057)·session_confirm_return(0046, not_signed_in·is-distinct 러너측 이미 보유)·기타.
--     · owner_id <> auth.uid() (bookings.owner_id = NOT NULL, 0001:39) — 0026 리스케줄 요청 게이트.
--     · sender_id <> auth.uid() (0049:64 NOT NULL) — 세션 메시지 삭제 게이트.
--     · club_dog_custody_events(0045:734)·club_session_incidents(0045:749): 읽기 전용 choke, owner_profile_id
--       NOT NULL 비교 + is-distinct(v_runner) + not exists(host) 조합 → fail-CLOSED, 돈·상태 영향 없음.
--     · club_incident_evidence_add/_detail(0050/0052): `auth.uid() in (opened_by, case_owner)`는 `<>`가
--       아니라 `in`이고 0052 rev2가 coalesce로 NULL 우회를 이미 봉함(G11 핀) — 별개 계약, 재수정 불필요.
--     · 알림 제외 필터(`and X <> auth.uid()` in SELECT/notify)는 게이트가 아니다 — 최악이 자기알림 유무.
--   ※ 0057 §2가 이미 is-distinct화한 5종(proposal_respond·assignment_revoke·cancel_delegation·custody_
--     override·transfer_initiate)과 0047 proposal_respond의 `is null or …`는 정본에서 이미 NULL-안전.
