-- ═══ 0057: 서버 원격 취약점 P0 봉인 (audit-2026-08-05-server) ═══
-- 왜: 실행된 감사(공격을 '추론'이 아니라 '실행'했다)가 원격 악용 가능한 P0 3종을 증명했다. 하나는
--     앱 번들에 실린 공개 anon 키만 든 **미인증** 호출자가 개를 주행 중에 낯선 사람에게 이양했다.
--     구멍은 방(로직)이 아니라 **문**에 있다 — 클럽/커스터디/정산 기계는 정문으로 들어온 모든 공격을
--     막아냈다. 이 파일은 문 여섯을 닫는다: (1) 전 definer RPC anon 실행 차단 (2) 돈·커스터디 RPC 심화
--     방어 (3) 배치/디버그 함수 봉인 (4) bookings 컬럼 가드 (5) runs 컬럼 가드 (6) runners/문서 거버넌스.
--
-- 인용 발견: P0-1(bookings 컬럼 절도)·P0-2(클럽 위탁 탈취)·P0-3(anon 전 definer 표면)·
--            P1-4(크론/디버그 anon)·P1-5(confirmed 거절)·P1-6(runs 위조)·K-1(runners 거버넌스)·
--            K-2(runner_documents 자가검증)·K-3(ensureRunner 자동인증 — 엣지 fn에서 처리).
--
-- 불변(0055 §계약): 0056까지는 정본. 파일 0001–0056은 한 글자도 수정하지 않는다 —
--   모든 변경은 이 파일의 create or replace / drop policy if exists+create / alter / do-block sweep.
--   새 definer 함수·트리거 함수는 **본문 헤더에** `set search_path = public, pg_temp` (98 H1 법 — ALTER
--   사후보정은 create or replace에 리셋됨. 0055 §2 실측).
--
-- ─── 역할 판정의 핵심 결정 (컬럼 가드 트리거는 왜 SECURITY INVOKER인가) ───────────────────────
-- 컬럼 가드(§4·§5·§6·§7)는 '직접 클라 쓰기'만 막고 '서버 경로 쓰기'는 통과시켜야 한다. 서버 경로는 셋:
--   ① service_role 엣지 fn(settle-run·transition-booking — admin() 클라이언트) → current_user='service_role'
--   ② definer RPC(session_proposal_respond 등 — 소유자 postgres) → 그 안에서 current_user='postgres'
--   ③ 하네스/운영 콘솔의 postgres 세션 → current_user='postgres'
-- 직접 클라 쓰기(막아야 할 것)만 current_user in ('authenticated','anon') 이다 (PostgREST가 JWT로 SET ROLE).
--
-- auth.uid() 판정은 **틀렸다**(감사가 제안한 폴백이지만 이 코드베이스에선 깨진다):
--   · 클럽 definer RPC(session_proposal_respond/assignment_revoke/cancel_delegation …)는 호출자의 JWT
--     문맥에서 돌면서 bookings.runner_id(가드 컬럼!)를 쓴다 — 그 안에서 auth.uid()는 여전히 호출자의
--     non-null uuid다(SECURITY DEFINER는 역할만 바꾸지 GUC는 안 바꾼다). auth.uid() 판정이면 이 정당한
--     쓰기가 전부 막혀 클럽 플로우가 죽는다.
--   · 기존 핀도 깨진다: 98_hardening H5/H7은 postgres 세션에서 request.jwt.claim.sub가 non-null인 채로
--     `update bookings set runner_id=…`를 한다(지명 CAS 등가 재현). auth.uid() 판정이면 이 핀이 빨간불.
-- request.jwt.claim.role 판정도 불안정하다 — 하네스 공격은 `set role authenticated`만 하고 claim.role은
--   안 세팅한다(shim의 auth.role() 기본값 'anon'). 반면 current_user는 SET ROLE로 확정된다.
--
-- 그래서 가드 트리거는 SECURITY **INVOKER** 여야 한다: DEFINER면 트리거 안에서 current_user가 그 트리거의
-- 소유자(postgres)로 바뀌어 호출자 역할을 영원히 못 본다 — 판정 자체가 불가능해진다. INVOKER면
-- current_user가 실제 실행 문맥(definer RPC 안=postgres, 직접 클라=authenticated)을 그대로 비춘다.
-- pg_temp 섀도잉 위험은 이 트리거들엔 없다(정본 테이블 참조는 §5의 bookings.status 한 건뿐이고 그건
-- 호출자=해당 부킹의 러너라 RLS로 정당하게 읽힌다). 그럼에도 헤더에 pg_temp를 박아 위생·일관성을 지킨다.
-- (98 H1은 prosecdef만 검사하므로 INVOKER 트리거는 핀 대상 밖 — 규정 위반 아님.)
set client_min_messages = warning;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §1. P0-3(a) — 전 public definer 함수에서 public·anon 실행 권한 일괄 회수 [load-bearing]
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 왜: PG는 함수 생성 시 EXECUTE를 PUBLIC에 기본 부여한다. 내부 헬퍼(_club_*, settle_run_tx …)는
--   명시적으로 revoke됐지만, 사용자용 RPC는 `grant … to authenticated`만 붙이고 PUBLIC 기본값을 안
--   지웠다 — 그 결과 89개 definer 함수가 anon(앱 번들에 실린 공개 키)으로 실행 가능했다. Supabase는
--   이들을 POST /rest/v1/rpc/<fn> 로 anon 키 소지자 누구에게나 연다. **이 sweep이 진짜 방벽이다** —
--   anon은 어떤 본문도 돌기 전에 permission denied를 받는다(§2의 not_signed_in 가드보다 앞선다).
-- 왜 blanket이 안전한가 (capture-and-restore):
--   · PG 함정: PUBLIC grant에서 anon만 빼는 건 불가능하다 — `revoke … from public`은 PUBLIC으로만
--     받던 authenticated 권한까지 함께 없앤다. 그래서 회수 '전'에 authenticated의 **유효** 실행권을
--     포착(had_auth = has_function_privilege('authenticated', oid, 'execute') — 명시 grant든 PUBLIC
--     상속이든)하고, 있었으면 회수 후 명시 grant로 복원한다. 이게 뷰/RLS가 호출하는 definer 술어를
--     안 깨는 이유다: is_active_runner(0042 marketplace_open_requests의 WHERE가 부른다)는 authenticated
--     명시 grant가 없고 PUBLIC으로만 도달했다 — 순수 revoke면 뷰가 permission denied로 죽는다(하네스 K1/K2/H2).
--   · 새 표면은 열리지 않는다: had_auth가 회수 전 상태를 그대로 포착하므로, 내부 `_`-헬퍼(이미
--     authenticated에서도 revoke됨 — 0028/0030/0044)는 had_auth=false → 재부여 없이 잠긴 채 남는다.
--   · service_role은 EXECUTE를 **PUBLIC이 아니라** Supabase 함수 default privileges로 받는다 —
--     public 회수와 무관하게 유지된다(운영). 하네스에선 RPC를 postgres 슈퍼유저 세션에서 실행하므로
--     public 회수가 이들에 영향을 주지 않는다. settle_run_tx는 이미 public·anon·authenticated에서
--     revoke돼 있고(0028:169) 이 sweep은 그 위에 멱등이다 — 리뷰어의 'settle_run_tx가 service_role로
--     여전히 돈다' 확인은 이 파일 전후로 불변이다.
--   · 이 앱에서 anon이 정당하게 필요한 커스텀 RPC는 없다(감사 확인).
-- 필터는 0055 §2의 sweep 루프와 동일: pronamespace='public'·prosecdef·prokind='f' · extension 소유
--   제외(deptype='e' — 확장 함수를 건드리면 업그레이드가 깨진다) · 비소유 함수 제외(pg_get_userbyid=
--   current_user — 원격에 대시보드 함수 등이 있으면 REVOKE가 권한 오류로 마이그레이션을 죽인다).
do $$
declare r record; had_auth boolean;
begin
  for r in
    select p.oid as oid, p.oid::regprocedure as sig
    from pg_proc p
    where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.prokind = 'f'
      and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
      and pg_get_userbyid(p.proowner) = current_user
  loop
    -- 회수 전 authenticated의 유효 실행권 포착 (명시 grant OR PUBLIC 상속 — 둘 다 true로 잡힌다)
    had_auth := has_function_privilege('authenticated', r.oid, 'execute');
    execute format('revoke execute on function %s from public, anon', r.sig);
    -- PUBLIC을 지우면 PUBLIC으로만 받던 authenticated 권한도 사라진다 — 포착값이 참이면 명시 grant로
    -- 복원한다(뷰/RLS definer 술어 보존). 내부 `_`-헬퍼는 had_auth=false라 잠긴 채 남는다.
    if had_auth then execute format('grant execute on function %s to authenticated', r.sig); end if;
  end loop;
end $$;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §2. P0-3(b) — 돈·커스터디 RPC 심화 방어 (not_signed_in 선두 가드 + NULL-안전 당사자 게이트)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 왜: §1이 anon 벡터를 이미 닫았지만, 두 겹으로 간다. (i) 각 함수 첫 문장에 not_signed_in — 어떤
--   경로로든 auth.uid()가 NULL이면 즉시 거부. (ii) 당사자 게이트를 `X <> auth.uid()` → `X is distinct
--   from auth.uid()` 로 재작성 — anon의 NULL에서 `X <> NULL`=NULL이라 `if NULL then`이 **분기하지
--   않아** 게이트가 조용히 통과하던 fail-open(0052 rev2가 술어에 세운 coalesce-false 법의 명령형 판)을 닫는다.
-- 재현 규율: 각 함수를 최신 정의(grep 확인)에서 그대로 옮기되 정확히 세 곳만 바꾼다 —
--   ⓐ 헤더 search_path를 `public` → `public, pg_temp`(98 H1 법 — 0055 §2 ALTER가 create or replace에
--      리셋되므로 본문에 직접 박는다) ⓑ begin 직후 not_signed_in ⓒ 당사자 게이트 is distinct from.
--   본문의 나머지·기존 revoke/grant 꼬리는 바이트 그대로 보존한다.
-- 한계(정직): session_transfer_accept(0045:199-297, 99줄·이중 분기·인시던트/세그먼트 생성)는 재현 시
--   드리프트 위험이 커, 이 파일에서는 §1(anon 차단)에 맡기고 belt-(b)에서 제외한다 — belt-(b)가 그
--   함수에 더하는 값은 '로그인한 잘못된 호출자'에 대한 not_signed_in(§1의 anon 차단과 중복)과
--   is-distinct(기존 `<>`가 non-null 호출자엔 이미 정확히 발화)뿐이라 한계 대비 이득이 사실상 0이다.

-- ---------- session_proposal_respond (0047:150 정본) ----------
create or replace function session_proposal_respond(p_session_dog uuid, p_accept boolean, p_reason text default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare sd record; s record; v_bstatus text;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독
  if sd.proposed_runner_profile_id is null or auth.uid() is distinct from sd.proposed_runner_profile_id then
    raise exception 'no_proposal_for_you';
  end if;
  if sd.proposal_expires_at <= now() then raise exception 'proposal_expired'; end if;
  select status::text into v_bstatus from bookings where id = sd.booking_id for update;
  if v_bstatus <> 'matching' then raise exception 'not_pending'; end if;

  if p_accept then
    -- 수락 시점 부하 재검증 (제안 후 다른 수락으로 캡이 찼을 수 있다 — 락 후 현재값)
    if _club_runner_load(sd.session_id, auth.uid())
       - 1  -- 본인의 이 활성 제안은 부하에 이미 계상돼 있다 — 수락은 제안→수락 치환
       >= coalesce((select delegated_capacity from session_runner_assignments
                    where session_id = sd.session_id and runner_profile_id = auth.uid()
                      and status = 'committed'), 0) then
      raise exception 'runner_cap_full';
    end if;
    insert into assignment_events (session_dog_id, runner_profile_id, event, created_by)
    values (sd.id, auth.uid(), 'accepted', auth.uid());
    update bookings set runner_id = auth.uid(), status = 'confirmed',
      owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null
    where id = sd.booking_id;
    update session_dogs set proposed_runner_profile_id = null, proposal_expires_at = null
    where id = p_session_dog;
    -- 이제야 보호자에게 확정 러너 카드가 공개된다 (Model A)
    insert into notifications (profile_id, kind, title, body, ref_id) values
      (sd.owner_profile_id, 'booking', '담당 러너 배정',
       (select name from profiles where id = auth.uid()) || ' 러너가 아이의 담당으로 확정됐어요 — 집결지에서 인계를 확인하세요', sd.booking_id),
      (s.host_profile_id, 'community', '배정 수락',
       (select name from dogs where id = sd.dog_id) || ' 배정이 수락됐어요', sd.session_id);
  else
    -- 거절: 보이지 않는 이탈 — 호스트에게만, 보호자 알림 없음
    insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
    values (sd.id, auth.uid(), 'declined', p_reason, auth.uid());
    update session_dogs set proposed_runner_profile_id = null, proposal_expires_at = null
    where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (s.host_profile_id, 'community', '배정 거절',
      (select name from dogs where id = sd.dog_id) || ' 제안이 거절됐어요 — 다른 러너에게 제안하세요', sd.session_id);
  end if;
end $$;
revoke execute on function session_proposal_respond(uuid, boolean, text) from public, anon;
grant execute on function session_proposal_respond(uuid, boolean, text) to authenticated;

-- ---------- session_assignment_revoke (0047:221 정본) ----------
create or replace function session_assignment_revoke(p_session_dog uuid, p_reason text default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare sd record; s record; v_bstatus text; v_runner uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;
  if s.host_profile_id is distinct from auth.uid() then raise exception 'not_host'; end if;
  select status::text, runner_id into v_bstatus, v_runner from bookings where id = sd.booking_id for update;
  if v_bstatus <> 'confirmed' or v_runner is null then raise exception 'not_assigned'; end if;
  perform 1 from bookings where id = sd.booking_id
    and (owner_confirmed_handoff_at is not null or runner_confirmed_handoff_at is not null);
  if found then raise exception 'already_handed_off'; end if;
  -- 상습 철회는 이벤트 조회로 추적한다 (스트라이크 정책 수치 = Sean) — 기록이 정책보다 먼저
  insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
  values (sd.id, v_runner, 'revoked', coalesce(p_reason, 'host_revoke'), auth.uid());
  update bookings set runner_id = null, status = 'matching',
    owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null
  where id = sd.booking_id;
  -- 즉시 재동기화 (deferred 포크는 커밋 시점 — 같은 tx의 후속 판단이 낡은 캐시를 보면 안 된다)
  update session_dogs set id = id where id = p_session_dog;
  insert into notifications (profile_id, kind, title, body, ref_id) values
    (v_runner, 'booking', '배정 철회', '위탁 배정이 철회됐어요', sd.session_id),
    (sd.owner_profile_id, 'booking', '담당 재배정 중', '담당 러너를 다시 배정하고 있어요 — 자리는 유지돼요', sd.booking_id);
end $$;
revoke execute on function session_assignment_revoke(uuid, text) from public, anon;
grant execute on function session_assignment_revoke(uuid, text) to authenticated;

-- ---------- session_cancel_delegation (0050:307 정본 — 0048 대체) ----------
create or replace function session_cancel_delegation(p_session_dog uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  sd record; s record; v_bst text; v_runner uuid; v_total int; v_pct numeric; v_rule text;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독
  if sd.owner_profile_id is distinct from auth.uid() then raise exception 'not_owner'; end if;
  if sd.service_state = 'ended' then raise exception 'already_ended'; end if;
  -- [R6 §8·§11] 강아지에 열린 인시던트 ⇒ 무동의 취소 차단 — 분쟁은 케이스로 푼다
  if exists (select 1 from club_incident_subjects sub join club_incidents i on i.id = sub.incident_id
             where sub.subject_type = 'dog' and sub.subject_id = sd.dog_id and i.state <> 'resolved') then
    raise exception 'incident_open';
  end if;

  if sd.booking_id is null then
    -- 결제 전 = 자유 취소: 행 종결 (홀드 해제 포함) — 수수료 없음, 재신청 자유(withdrawn)
    update session_dogs set approval = 'withdrawn',
      hold_status = case when hold_status = 'active' then 'released' else hold_status end
    where id = p_session_dog;
    update session_dogs set id = id where id = p_session_dog;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (s.host_profile_id, 'community', '위탁 신청 취소', '보호자가 위탁 신청을 취소했어요', sd.session_id);
    return;
  end if;

  select status::text, runner_id, total_price into v_bst, v_runner, v_total
  from bookings where id = sd.booking_id for update;
  if v_bst not in ('matching', 'confirmed') then raise exception 'already_handed_off'; end if;

  -- 사다리 (config): 수락 후 > 시한 내 > 무료 — 근거는 basis에 기록
  if v_bst = 'confirmed' and v_runner is not null then
    v_pct := coalesce(club_cfg('cancel_post_accept_pct'), 20); v_rule := 'post_acceptance';
  elsif s.scheduled_at - now() < make_interval(hours => coalesce(club_cfg('cancel_free_hours'), 24)::int) then
    v_pct := coalesce(club_cfg('cancel_late_pct'), 10); v_rule := 'late_cancel';
  else
    v_pct := 0; v_rule := 'free_window';
  end if;

  if v_bst = 'confirmed' then
    insert into assignment_events (session_dog_id, runner_profile_id, event, reason, created_by)
    values (sd.id, v_runner, 'revoked', 'owner_cancel', auth.uid());
    update bookings set runner_id = null, status = 'matching',
      owner_confirmed_handoff_at = null, runner_confirmed_handoff_at = null
    where id = sd.booking_id;
  end if;
  update bookings set status = 'refund_pending', cancel_reason = 'club_owner_cancel'
  where id = sd.booking_id;
  update session_dogs set id = id where id = p_session_dog;

  perform _club_record_cancel_fee(sd.session_id, sd.id, sd.booking_id, 'cancel_fee',
    v_total, v_pct, v_runner, v_rule);

  insert into notifications (profile_id, kind, title, body, ref_id) values
    (sd.owner_profile_id, 'booking', '위탁 취소 접수',
     case when v_pct > 0 then '환불이 진행돼요 — 취소 수수료 ' || v_pct || '%가 기록됐어요 (모의 시대: 청구 없음)'
          else '전액 환불이 진행돼요' end, sd.booking_id),
    (s.host_profile_id, 'community', '위탁 취소', '보호자가 결제된 위탁을 취소했어요', sd.session_id);
  if v_runner is not null then
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (v_runner, 'booking', '배정 취소', '보호자 취소로 배정이 해제됐어요 — 보상 기록이 남았어요', sd.session_id);
  end if;
end $$;
revoke execute on function session_cancel_delegation(uuid) from public, anon;
grant execute on function session_cancel_delegation(uuid) to authenticated;

-- ---------- session_custody_override (0045:123 정본) ----------
create or replace function session_custody_override(
  p_session_dog uuid, p_side text, p_kind text, p_artifact jsonb
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare sd record; s record; v_runner uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독 (0044 교훈)
  if s.host_profile_id is distinct from auth.uid() then raise exception 'not_host'; end if;
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
  -- 양측 완성 시 마무리는 남은 당사자의 session_confirm_return이 수행 (이벤트에 오버라이드 meta 부착)
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (case when p_side = 'owner' then sd.owner_profile_id else v_runner end,
          'community', '반환 확인 대리 기록', '호스트가 현장 확인으로 반환 확인을 기록했어요 (' || p_kind || ')', sd.session_id);
end $$;
revoke execute on function session_custody_override(uuid, text, text, jsonb) from public, anon;
grant execute on function session_custody_override(uuid, text, text, jsonb) to authenticated;

-- ---------- session_transfer_initiate (0045:163 정본) ----------
create or replace function session_transfer_initiate(
  p_session_dog uuid, p_to_type text, p_to_profile uuid default null,
  p_to_external text default null, p_reason text default null
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare sd record; v_runner uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_found'; end if;
  perform 1 from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독 (0044 교훈)
  select runner_id into v_runner from bookings where id = sd.booking_id;
  if auth.uid() is distinct from v_runner then raise exception 'not_custodian'; end if;
  if sd.custodian_type <> 'runner' then raise exception 'not_in_runner_custody'; end if;
  if p_to_type = 'runner' then
    if p_to_profile is null then raise exception 'target_required'; end if;
    if sd.custody_phase not in ('with_custodian','return_pending') then raise exception 'bad_phase'; end if;
  elsif p_to_type in ('clinic','authority','authorized_person') then
    -- 외부 이양은 러너 보유 어느 국면에서도 개시 가능 — **부상은 주행 중에 일어난다.**
    -- 주행 전·중 확정은 accept가 원자 인시던트 경로(런 종료·incident_review·배정 폐쇄·인시던트 개설)로 처리.
    if sd.custody_phase not in ('with_custodian','return_pending') then raise exception 'bad_phase'; end if;
    if coalesce(trim(p_to_external), '') = '' and p_to_profile is null then raise exception 'target_required'; end if;
  else
    raise exception 'bad_target_type';
  end if;
  update session_dogs set custody_phase = 'transfer_pending',
    pending_transfer = jsonb_build_object('toType', p_to_type, 'toProfile', p_to_profile,
      'toExternal', p_to_external, 'reason', p_reason, 'by', auth.uid(), 'at', now())
  where id = p_session_dog;
  if p_to_type = 'runner' then
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (p_to_profile, 'booking', '비상 이양 요청', '강아지 커스터디 이양 요청이 왔어요 — 수락 여부를 결정하세요', sd.session_id);
  end if;
end $$;
revoke execute on function session_transfer_initiate(uuid, text, uuid, text, text) from public, anon;
grant execute on function session_transfer_initiate(uuid, text, uuid, text, text) to authenticated;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §3. P1-4 — 배치/디버그 함수 봉인 (크론·service-role 전용 · 당사자 개념 자체가 없다)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 왜: §1과 같은 뿌리지만 이들은 배치 함수라 게이트가 애초에 없다 — anon이 그대로 돌렸다(감사 a11).
--   grant_weekly_rewards는 멱등이 아니라 anon이 하이 포인트를 무제한 발행할 수 있었고,
--   club_debug_release_payouts는 payout_state를 전부 released로 뒤집는다. 세 역할 모두에서 회수한다
--   (public·anon·authenticated) — 이들은 오직 크론/service-role에서만 돈다.
-- club_debug_release_payouts는 **드롭하지 않고** 회수만 한다 — 후속 마이그레이션이 존재를 참조할 수
--   있으므로(감독 지시). 회수만으로 프로덕션 도달 불가가 충족된다.
revoke execute on function grant_weekly_rewards()        from public, anon, authenticated;
revoke execute on function expire_unmatched_bookings()   from public, anon, authenticated;
revoke execute on function expire_reschedule_requests()  from public, anon, authenticated;
revoke execute on function purge_expired_holds()         from public, anon, authenticated;
revoke execute on function purge_old_chat()              from public, anon, authenticated;
revoke execute on function club_debug_release_payouts()  from public, anon, authenticated;

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §4. P0-1 — bookings 컬럼 가드 (WITH CHECK + BEFORE UPDATE 트리거)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 왜: `bookings party update`는 **행**만 인가하고 **컬럼**은 인가하지 않았다 — 양측 당사자가 살아있는
--   부킹의 모든 컬럼을 다시 썼고, settle-run이 그 컬럼(addons·km·min_fare)에서 지급을 유도했다
--   (감사 실행: 19,920₩ → 2,400,000₩, 120배). owner_id 재기입으로 소유권 탈취까지 가능했다.
--   적대 리뷰 잔여 2건도 같은 뿌리라 여기 접는다: R1 — 러너가 인계 확인 타임스탬프
--   (owner/runner_confirmed_handoff_at)를 직접 위조하면 confirm_handoff가 양측 확인으로 오판해
--   picked_up로 넘어가며 보호자 진짜 확인 없이 "펫보험 적용"을 발화한다(책임 사고). R2 — scheduled_at
--   직접 재기입은 0016 리스케줄 계약을 우회한다. 둘 다 정당한 클라 직접 쓰기 경로가 없고 서버 경로
--   (service_role/definer)로만 쓰인다 → 가드를 통과하는 건 서버뿐, 직접 클라 위조만 막힌다.
-- 정책: WITH CHECK로 '쓰기 후에도 호출자가 여전히 당사자'를 못박는다(신원 고정의 절반).
-- 트리거: 나머지 절반 — WITH CHECK는 RLS라 OLD를 못 본다. '불변'은 트리거에서 OLD vs NEW로 판정한다.
--   직접 클라 쓰기(current_user in authenticated/anon)일 때 돈·신원 컬럼 집합이 하나라도 바뀌면 거부.
--   service_role 엣지 fn(current_user='service_role')과 definer RPC(current_user='postgres')는 통과 —
--   클라가 정당히 바꾸는 필드는 전부 엣지 fn/definer RPC를 지나므로 직접 쓰기는 아무것도 필요 없다.
--   (역할 판정이 왜 current_user·왜 INVOKER인지는 파일 상단 헤더 참조.)
drop policy if exists "bookings party update" on bookings;
create policy "bookings party update" on bookings for update
  using (owner_id = auth.uid() or runner_id = auth.uid())
  with check (owner_id = auth.uid() or runner_id = auth.uid());

create or replace function _guard_booking_cols() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  -- 직접 클라 쓰기만 검문 (서버 경로 = service_role/postgres/definer는 통과)
  if current_user in ('authenticated', 'anon') then
    if new.owner_id       is distinct from old.owner_id
    or new.dog_id         is distinct from old.dog_id
    or new.runner_id      is distinct from old.runner_id
    or new.series_id      is distinct from old.series_id
    or new.km             is distinct from old.km
    or new.base_fare      is distinct from old.base_fare
    or new.distance_fare  is distinct from old.distance_fare
    or new.addon_fare     is distinct from old.addon_fare
    or new.addons         is distinct from old.addons
    or new.total_price    is distinct from old.total_price
    or new.min_fare       is distinct from old.min_fare
    or new.cancel_fee     is distinct from old.cancel_fee
    or new.club_session_id is distinct from old.club_session_id
    -- R1(책임 — 가장 중요): 인계 확인 타임스탬프. 직접 위조하면 confirm_handoff의 재조회가 양측
    --   확인으로 오판해 picked_up로 넘어가며 "펫보험 적용"을 보호자 진짜 확인 없이 발화한다.
    --   confirm_handoff/러너 리셋은 service_role/definer로 쓰므로 통과 — 직접 클라 위조만 막힌다.
    or new.owner_confirmed_handoff_at  is distinct from old.owner_confirmed_handoff_at
    or new.runner_confirmed_handoff_at is distinct from old.runner_confirmed_handoff_at
    -- R2: scheduled_at 직접 재기입은 0016 request/accept_reschedule 계약을 우회한다.
    --   일정 변경 쓰기는 엣지 fn(service_role)만 — 정당한 클라 직접 쓰기 경로 없음(grep 확인).
    or new.scheduled_at   is distinct from old.scheduled_at
    then
      raise exception 'booking_protected_columns'
        using detail = '소유·식별·요금·인계확인·일정 컬럼은 클라이언트가 직접 변경할 수 없어요 — 서버 경로(엣지 함수/RPC)로만';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists _guard_booking_cols on bookings;
create trigger _guard_booking_cols before update on bookings
  for each row execute function _guard_booking_cols();

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §5. P1-6 — runs 컬럼 가드 (WITH CHECK + 정산 후 동결 + 라이브 append 표면 한정)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 왜: `runs runner update`는 WITH CHECK도 정산 후 동결도 없어 러너가 정산 뒤에 run 기록을 다시 썼다
--   (감사 실행: 정산 후 actual_km 5 → 900, 리더보드가 전원에게 그 900을 보여줬다). 돈은 이미
--   고정됐지만 파생 표면(리더보드·코스 이력·주간 하이 포인트·패치 카운트)이 전부 runs를 라이브로 읽는다.
-- 정책: using을 거울로 WITH CHECK 추가.
-- 트리거: 직접 클라 쓰기일 때 ① 부킹이 completed/incident_review면 전면 동결 ② 클라 쓰기 가능 표면을
--   events/photos/trace(라이브 append) 3종으로 한정. append_run_event/append_run_photo definer RPC
--   (0018 — SECURITY DEFINER, 소유자 postgres)가 이미 그 표면을 소유하므로 직접 UPDATE 정책은 사실상
--   잉여지만, 라이브 트레이스 저장(api.ts saveTrace)이 이 경로를 쓰므로 최소한으로 남긴다.
--   definer append RPC는 current_user='postgres'라 이 트리거를 통과한다 — 잉여가 서로 안 부딪친다.
drop policy if exists "runs runner update" on runs;
create policy "runs runner update" on runs for update
  using (exists (select 1 from bookings b where b.id = booking_id and b.runner_id = auth.uid()))
  with check (exists (select 1 from bookings b where b.id = booking_id and b.runner_id = auth.uid()));

create or replace function _guard_run_cols() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
declare v_status text;
begin
  if current_user in ('authenticated', 'anon') then
    -- ① 정산 후 동결 — 부킹이 종단이면 클라 쓰기 전면 거부 (호출자=해당 부킹 러너라 RLS로 정당히 읽힘)
    select b.status::text into v_status from bookings b where b.id = new.booking_id;
    if v_status in ('completed', 'incident_review') then
      raise exception 'run_frozen_after_settlement'
        using detail = '정산·인시던트 종료된 러닝 기록은 변경할 수 없어요';
    end if;
    -- ② 클라 쓰기 가능 표면 = 라이브 append 3종(events/photos/trace)뿐 — 그 외 변경 거부
    if new.actual_km          is distinct from old.actual_km
    or new.duration_sec       is distinct from old.duration_sec
    or new.avg_pace_sec_per_km is distinct from old.avg_pace_sec_per_km
    or new.end_reason         is distinct from old.end_reason
    or new.condition_note     is distinct from old.condition_note
    or new.started_at         is distinct from old.started_at
    or new.ended_at           is distinct from old.ended_at
    or new.booking_id         is distinct from old.booking_id
    then
      raise exception 'run_protected_columns'
        using detail = '거리·시간·페이스·종료사유는 서버(정산)만 기록해요 — 클라는 events/photos/trace만';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists _guard_run_cols on runs;
create trigger _guard_run_cols before update on runs
  for each row execute function _guard_run_cols();

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §6. K-1 — runners 거버넌스 (스토어프런트 컬럼만 클라 쓰기 · tier/commission_rate 서버 전용)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 왜: `runners self write`는 WITH CHECK·컬럼 제한이 없어 러너가 commission_rate=0(정산 지급 절도)·
--   tier/total_runs/*_verified를 자기 설정할 수 있었다(P0-1과 합성). commission_rate는 이제 **서버
--   전용** — 테이크레이트 인상의 선결 조건이다. 단 이 파일은 값을 바꾸지 않는다: 기본 0.20 유지(값 변경은
--   별도 마이그레이션 — commission_rate가 서버 전용이 되기 전엔 그 rate가 자문에 불과하다는 감사 순서).
-- 클라 쓰기 허용(스토어프런트): bio·specialties·avg_pace_sec_per_km·service_radius_km·max_dog_weight_kg·
--   online·photos(0007). 거부(서버 전용): tier·funnel_step·identity_verified·insurance_active·
--   trainer_certified·education_modules_done·total_runs·total_km·completion_rate·compliance_pct·
--   respond_rate_pct·commission_rate. (블랙리스트 방식 — photos 등 정당한 스토어프런트 컬럼을 실수로
--   막지 않도록. 이 목록이 곧 돈·신뢰·검증 표면 전부다.)
--   settle_run_tx(definer)의 total_runs/total_km/completion_rate 증분과 grant_weekly_rewards(definer)의
--   tier 승급은 current_user='postgres'라 통과한다.
drop policy if exists "runners self write" on runners;
create policy "runners self write" on runners for update
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

create or replace function _guard_runner_cols() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  if current_user in ('authenticated', 'anon') then
    if new.tier                  is distinct from old.tier
    or new.funnel_step           is distinct from old.funnel_step
    or new.identity_verified     is distinct from old.identity_verified
    or new.insurance_active      is distinct from old.insurance_active
    or new.trainer_certified     is distinct from old.trainer_certified
    or new.education_modules_done is distinct from old.education_modules_done
    or new.total_runs            is distinct from old.total_runs
    or new.total_km              is distinct from old.total_km
    or new.completion_rate       is distinct from old.completion_rate
    or new.compliance_pct        is distinct from old.compliance_pct
    or new.respond_rate_pct      is distinct from old.respond_rate_pct
    or new.commission_rate       is distinct from old.commission_rate
    then
      raise exception 'runner_protected_columns'
        using detail = '등급·수수료율·실적·검증 상태는 서버만 정해요 — 클라는 스토어프런트 필드만';
    end if;
  end if;
  return new;
end $$;

drop trigger if exists _guard_runner_cols on runners;
create trigger _guard_runner_cols before update on runners
  for each row execute function _guard_runner_cols();

-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- §7. K-2 — runner_documents (verified_at 서버 전용 — 신청자 자가 검증 차단)
-- ══════════════════════════════════════════════════════════════════════════════════════════════
-- 왜: `runner docs self`는 for all이라 신청자가 자기 문서에 verified_at을 박아 스스로 인증 통과처럼
--   보이게 할 수 있었다. verified_at은 운영/서버만 쓴다. INSERT(업로드 시 즉시 검증 위장)와
--   UPDATE(사후 검증 위장) 둘 다 막는다. (테이블에 'verified' 불리언은 없다 — verified_at 하나만 가드.)
create or replace function _guard_runner_doc_verify() returns trigger
language plpgsql security invoker set search_path = public, pg_temp as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      if new.verified_at is not null then
        raise exception 'runner_doc_verify_server_only' using detail = '검증 시각은 서버만 기록해요';
      end if;
    elsif tg_op = 'UPDATE' then
      if new.verified_at is distinct from old.verified_at then
        raise exception 'runner_doc_verify_server_only' using detail = '검증 시각은 서버만 기록해요';
      end if;
    end if;
  end if;
  return new;
end $$;

drop trigger if exists _guard_runner_doc_verify on runner_documents;
create trigger _guard_runner_doc_verify before insert or update on runner_documents
  for each row execute function _guard_runner_doc_verify();
