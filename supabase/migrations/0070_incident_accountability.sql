-- ═══ 0070: adversarial-review follow-ups on 0067/0068/0069 (dual-voice review, 2026-08-11) ═══
--
-- The 0059 adversarial cycle ran two independent voices against 12f5963. They could not reopen
-- the payout-freeze the slice was written to close (both the booking gate and the session-scoped
-- release predicate held, and session_transfer_accept derives its subjects from the locked
-- session_dog so it is not a second door). They did find five things that were true, four of
-- which make a claim written in 0069's own header FALSE as shipped. Those are fixed here.
--
--   §A  0069 says "the host cannot force-resolve and walk away", resting on
--       club_finish_session's `incident_unassigned` guard. But `club_incident_assign`
--       (0045:369-382) accepts ANY profile uuid as `p_owner` — no party check, no acceptance —
--       and the close guard only tests `case_owner is null`. So the host could adopt the case
--       to a stranger and close the session with the dog still in runner custody and the money
--       still held. The sentence was true of the guard's intent and false of its code.
--   §B  `artifact_required` in 0069 §A rejected only SQL NULL and exactly `{}`. `'[]'::jsonb`,
--       `'null'::jsonb` and `'"x"'::jsonb` all passed, so "증빙 필수" was not enforced against a
--       caller hitting the RPC directly. Same hole in session_custody_override's witness branch
--       (pre-existing, 0045:150) — same law, fixed together.
--   §C  `payout_hold_incident` is a SINGLE mutable pointer, so two incidents on one dog orphan
--       the hold forever: I1 opens (pointer=I1), I2 opens (pointer=I2), resolve I2 (I1 still
--       open ⇒ hold kept), resolve I1 (the resolver scans `payout_hold_incident = I1`, but the
--       row now points at I2, so it is never cleared). 0069 made this reachable by design —
--       session_host_force_resolve opens a second incident on a dog that may already have one.
--       The same resolver also matched dog subjects with no session join, which is the last
--       cross-club freeze left in the family (same dog, not an arbitrary booking).
--   §D  The "serialization law" comment says every payout-blocking incident writes its hold
--       under the session lock. `club_release_payouts` never took that lock at all, so the
--       reverse interleaving (release locks the dog row first; the incident's plain SELECT then
--       reads `payout_state = 'released'` and writes no hold) released money with an incident
--       committing right behind it. The law was documented but not implemented on one side.
--   §E  0068 deleted the T-10 auto-refund and left the honest terminal in club_finish_session —
--       but a host who never closes leaves paid, unassigned delegations stranded, and NO sweep
--       reaches them (`expire_unmatched_bookings` explicitly excludes `club_session_id is not
--       null`, 0060:103). 0068's header recorded this as an accepted residual; the review
--       confirmed nothing collects it. Closing it properly is cheaper than carrying it.
--
-- No new constants: §E reuses the assign window's own close (T+6h, 0048:454). After that moment
-- assignment is server-impossible, so "this delegation did not happen" is a fact, not a guess —
-- which is exactly what the T-10 stop got wrong in the other direction.
--
-- `set search_path = public, pg_temp` is re-stated in every body (replace resets proconfig; 98 H1).
-- Pins: supabase/tests/108_incident_accountability_suite.sql, plus 107 R3 rewritten in the same
-- commit — the review proved R3 could NOT go red on a self_override revert, which is the same
-- "a pin that cannot go red reads as proof" defect 106 S5 had.

-- ---------- §A. 케이스 인수는 책임질 수 있는 사람만 ----------
-- 종전엔 임의 uuid를 case_owner로 꽂을 수 있었고, 종료 게이트는 not null만 봤다 —
-- 그래서 '호스트는 걸어나갈 수 없다'가 코드에서는 거짓이었다.
create or replace function club_incident_assign(p_incident uuid, p_owner uuid default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_session uuid; v_owner uuid;
begin
  perform _club_require_v2();
  select session_id into v_session from club_incidents where id = p_incident;
  if v_session is null then raise exception 'not_found'; end if;
  if not exists (select 1 from club_sessions where id = v_session and host_profile_id = auth.uid()) then
    raise exception 'not_host';
  end if;
  v_owner := coalesce(p_owner, auth.uid());
  -- 케이스 오너는 그 세션의 호스트 또는 백업 호스트뿐이다. 남에게 떠넘기고 세션을 닫는 경로를 봉한다.
  if not exists (select 1 from club_sessions where id = v_session
                 and v_owner in (host_profile_id, backup_host_profile_id)) then
    raise exception 'not_eligible_owner';
  end if;
  update club_incidents set case_owner = v_owner,
    state = case when state = 'open' then 'investigating' else state end
  where id = p_incident;
end $$;
grant execute on function club_incident_assign(uuid, uuid) to authenticated;

comment on function club_incident_assign is
  'R2(0045)+0070 §A: 케이스 인수 — 호스트만 호출하고, case_owner는 그 세션의 호스트/백업 호스트만
될 수 있다 (임의 uuid 떠넘기기 후 세션 종료 경로 폐쇄 — club_finish_session의 incident_unassigned가
실제로 책임자를 뜻하게 된다)';

-- ---------- §C. 지급 보류는 포인터가 아니라 '지금 살아있는 주체'에서 다시 계산한다 ----------
create or replace function club_incident_resolve(p_incident uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_session uuid; v_owner uuid; v_sd record; v_open uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  perform _club_require_v2();
  select session_id, case_owner into v_session, v_owner from club_incidents where id = p_incident;
  if v_session is null then raise exception 'not_found'; end if;
  -- [0058 F1 — 그대로 보존] NULL-안전 게이트. 이 함수의 최신 정본은 0050이 아니라 **0058**이었고,
  -- 0070이 0050 본문을 베껴오면서 하마터면 그 경화를 조용히 되돌릴 뻔했다 (99 S9가 즉시 빨개져
  -- 잡았다). `auth.uid() <> v_owner`는 case_owner가 NULL인 갓 개설 케이스에서 NULL로 접혀
  -- 비-호스트 당사자가 자기 payout_hold를 푸는 fail-open이었다. non-null 가드는 유지된다.
  if not (
       (v_owner is not null and auth.uid() = v_owner)
       or exists (select 1 from club_sessions where id = v_session
                    and auth.uid() in (host_profile_id, backup_host_profile_id))
     ) then
    raise exception 'not_case_owner';
  end if;
  perform 1 from club_sessions where id = v_session for update;      -- §D 직렬화 지점 공유
  if p_note is not null then
    insert into club_incident_evidence (incident_id, kind, payload, created_by)
    values (p_incident, 'text', jsonb_build_object('note', p_note, 'at', now()), auth.uid());
  end if;
  update club_incidents set state = 'resolved', resolved_at = now() where id = p_incident;

  -- [0070 §C] 종전엔 `payout_hold_incident = p_incident`인 행만 훑었다. 포인터는 하나뿐이라
  -- 두 번째 인시던트가 덮어쓰면 첫 번째를 해소해도 그 행에 영영 닿지 못했다 (보류 고아).
  -- 이제 이 세션에서 보류된 행 전부를 훑고, **지금 살아있는 같은 세션 주체**로 다시 계산한다.
  for v_sd in
    select id, dog_id, booking_id, session_id from session_dogs
    where payout_hold = 'held' and payout_hold_reason = 'incident'
      and (session_id = v_session or payout_hold_incident = p_incident)
  loop
    select i.id into v_open
    from club_incident_subjects sub join club_incidents i on i.id = sub.incident_id
    where i.state <> 'resolved'
      and i.session_id = v_sd.session_id                     -- 타 세션 케이스는 이 지급을 막지 않는다
      and ((sub.subject_type = 'dog' and sub.subject_id = v_sd.dog_id)
        or (sub.subject_type = 'booking' and sub.subject_id = v_sd.booking_id))
    limit 1;
    if v_open is null then
      update session_dogs set payout_hold = 'none', payout_hold_reason = null,
        payout_hold_incident = null where id = v_sd.id;
    else
      update session_dogs set payout_hold_incident = v_open where id = v_sd.id;   -- 살아있는 케이스로 재지정
    end if;
  end loop;
end $$;
grant execute on function club_incident_resolve(uuid, text) to authenticated;

comment on function club_incident_resolve is
  'R6(0050)+0070 §C: 케이스 해소 — 보류 해제는 단일 포인터가 아니라 **같은 세션의 미해소 주체 재계산**으로
결정한다 (다중 인시던트 보류 고아 폐쇄 · 타 세션 케이스는 이 지급을 막지 않는다) · 백업 호스트도 해소 가능(95 G13)';

-- ---------- §D. 릴리스도 세션 락을 잡는다 — 직렬화 법이 양쪽에서 참이 되도록 ----------
create or replace function club_release_payouts() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare r record; n int := 0; m int;
begin
  -- [직렬화 법 — 0070 §D에서 실제로 구현됨] 종전엔 '인시던트 개설이 세션 락 아래에서 보류를 쓴다'는
  -- 절반만 참이었다. 릴리스는 락을 아예 잡지 않아, 릴리스가 먼저 개 행을 잠그면 개설 쪽의 평범한
  -- SELECT가 이미 released를 읽고 보류를 못 쓴 채 커밋했다 — 돈이 나간 뒤 인시던트가 열린다.
  -- 이제 양쪽이 같은 세션 행에서 직렬화된다: 먼저 잡는 쪽이 이기고, 진 쪽은 커밋된 사실을 본다.
  -- 세션 id 순회 = 결정적 순서 (교착 회피). 멱등: payable → released 단방향.
  for r in
    select distinct sd.session_id from session_dogs sd
    where sd.payout_state = 'payable' and sd.payout_hold = 'none' and sd.custody_phase = 'resolved'
      and sd.session_id is not null
    order by 1
  loop
    perform 1 from club_sessions where id = r.session_id for update;
    update session_dogs sd set payout_state = 'released'
    where sd.session_id = r.session_id
      and sd.payout_state = 'payable' and sd.payout_hold = 'none' and sd.custody_phase = 'resolved'
      and not exists (
        select 1 from club_incident_subjects s join club_incidents i on i.id = s.incident_id
        where i.state <> 'resolved'
          and i.session_id = sd.session_id                   -- [0067 §D] 교차 세션/교차 클럽 차단
          and ((s.subject_type = 'dog' and s.subject_id = sd.dog_id)
            or (s.subject_type = 'booking' and s.subject_id = sd.booking_id)));
    get diagnostics m = row_count;
    n := n + m;
  end loop;
  return n;
end $$;
revoke execute on function club_release_payouts() from public, anon, authenticated;

comment on function club_release_payouts is
  '0045+0067+0070 §D: 지급 릴리스 배치 — 세션 행 락을 잡고 세션 단위로 돈다 (인시던트 개설과 같은
직렬화 지점: 종전엔 릴리스만 락 없이 돌아 "보류 없이 릴리스 후 인시던트 커밋" 인터리빙이 열려 있었다) ·
2차 방어선은 session_dog 자신의 세션으로 한정';

-- ---------- §B. 증빙은 '비어있지 않은 JSON 객체'여야 한다 ----------
create or replace function session_host_force_resolve(
  p_session_dog uuid, p_reason text, p_artifact jsonb
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare sd record; s record; v_runner uuid; v_bst text; v_inc uuid;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if coalesce(trim(p_reason), '') = '' then raise exception 'reason_required'; end if;
  -- [0070 §B] 종전 검사는 SQL NULL과 정확히 '{}'만 걸렀다 — '[]', 'null', '"x"'가 전부 통과했다.
  -- '증빙 필수'는 형태까지 요구해야 한다: 키가 하나 이상 있는 객체.
  if p_artifact is null or jsonb_typeof(p_artifact) <> 'object' or p_artifact = '{}'::jsonb then
    raise exception 'artifact_required';
  end if;
  select * into sd from session_dogs where id = p_session_dog;
  -- [0070 §F] 당사자 게이트 선행 — 없는 행과 남의 행은 같은 답이어야 한다. 0067 §C가 죽인 존재
  -- 오라클을 0069가 not_found로 되살렸다 (독립 리뷰가 실측: 무관자에게 real→not_host,
  -- random→not_found로 갈렸다). CLAUDE.md의 법이고, 같은 파일 안에서 어겨서는 안 된다.
  if sd.id is null then raise exception 'not_host'; end if;
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독 (0044 교훈)
  -- [0070 §F] 백업 호스트도 부른다. 종전엔 호스트만이었는데, 그러면 이 RPC는 **가장 흔한 클럽
  -- 모양에서 아무도 못 쓴다**: 소규모 클럽의 호스트가 곧 러너라 self_override로 막히고, 백업은
  -- not_host로 막혔다 — C4가 정확히 그 경우에 안 고쳐진 채였다 (독립 리뷰가 실행해서 증명).
  if auth.uid() is distinct from s.host_profile_id
     and auth.uid() is distinct from s.backup_host_profile_id then raise exception 'not_host'; end if;
  if sd.custody <> 'runner_delegated' or sd.booking_id is null then raise exception 'not_delegated'; end if;
  select status::text, runner_id into v_bst, v_runner from bookings where id = sd.booking_id for update;
  -- [0070 §F] 자기 오버라이드 금지는 **보호자일 때만**이다. session_custody_override에서 이 법은
  -- '자기 인계를 자기가 증언하지 못한다'는 뜻이었다. 여기서는 다르다: 호스트가 자기가 맡은 개의
  -- 러닝을 '끝나지 않았다'고 신고하는 것은 자기고발이지 자기이득이 아니다 — 자기 지급이 보류되고
  -- 자기 앞으로 케이스가 열린다. 반대로 호스트가 그 개의 **보호자**면 인계 후 취소를 우회하는
  -- 길이 되므로(전이 맵이 의도적으로 막은 것) 그대로 금지한다.
  if auth.uid() = sd.owner_profile_id then raise exception 'self_override'; end if;
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
  -- (0045:328-336) 세션 차단이 풀리고, club_finish_session은 케이스 인수 전까진 여전히 거부한다
  -- (그리고 0070 §A 이후로는 '인수'가 실제로 책임자를 뜻한다).
  update session_dogs set
    custody_phase = 'with_custodian',
    pending_transfer = null,
    return_override = jsonb_build_object(
      'side', 'host', 'kind', 'host_force_resolve', 'artifact', p_artifact,
      'reason', trim(p_reason), 'by', auth.uid(), 'at', now(), 'incident', v_inc)
  where id = p_session_dog;
  return v_inc;
end $$;
revoke execute on function session_host_force_resolve(uuid, text, jsonb) from public, anon;
grant execute on function session_host_force_resolve(uuid, text, jsonb) to authenticated;

-- 같은 법, 같은 구멍 — witness 오버라이드의 증빙 검사도 형태를 요구한다 (0045:150 이래 방치)
create or replace function session_custody_override(
  p_session_dog uuid, p_side text, p_kind text, p_artifact jsonb
) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare sd record; s record; v_runner uuid;
begin
  perform _club_require_v2();
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then raise exception 'not_host'; end if;             -- [0070 §F] 존재 오라클 폐쇄
  select * into s from club_sessions where id = sd.session_id for update;
  select * into sd from session_dogs where id = p_session_dog;          -- 락 후 재독 (0044 교훈)
  if s.host_profile_id <> auth.uid() then raise exception 'not_host'; end if;
  if p_side not in ('owner','runner') then raise exception 'bad_side'; end if;
  if p_kind not in ('witness','assisted') then raise exception 'bad_kind'; end if;
  if sd.custody_phase <> 'return_pending' then raise exception 'not_return_pending'; end if;
  select runner_id into v_runner from bookings where id = sd.booking_id;
  -- 자기 오버라이드 금지: 호스트가 그 에지의 당사자면 불가 (백업 호스트/ops 몫)
  if auth.uid() = sd.owner_profile_id or auth.uid() = v_runner then raise exception 'self_override'; end if;
  -- witness는 강증빙 필수 (PIN/QR/서명/사진). [0070 §B] 형태까지 — '[]'/'null'은 증빙이 아니다.
  if p_kind = 'witness' and (p_artifact is null or jsonb_typeof(p_artifact) <> 'object'
                             or p_artifact = '{}'::jsonb) then
    raise exception 'artifact_required';
  end if;

  -- [0070 §G] 종전엔 return_override를 통째로 덮어썼다. 콘솔이 양측 버튼을 그리므로 두 번 누르면
  -- 첫 번째 측의 증빙이 사라지고, _club_finalize_return이 남은 것을 **양측의** confirmation_kind로
  -- 도장 찍었다 — 실제로 107 R5가 그 손상을 만들고 있었다: owner는 assisted(증빙 불요)였는데
  -- 커스터디 기록은 양측 모두 '호스트 증인 수령'이라고 주장했다. 0069 §B가 눈에 보이던 좌초를
  -- 조용한 날조로 바꾼 셈이다. 이제 측별로 쌓는다 (최상위 kind/side는 하위 호환용 최신값).
  update session_dogs set return_override =
    coalesce(return_override, '{}'::jsonb)
    || jsonb_build_object(
         'side', p_side,
         'kind', case p_kind when 'witness' then 'host_witnessed_receipt' else 'authorized_person_pin' end,
         'artifact', p_artifact, 'by', auth.uid(), 'at', now(),
         'sides', coalesce(return_override->'sides', '{}'::jsonb) || jsonb_build_object(
           p_side, jsonb_build_object(
             'kind', case p_kind when 'witness' then 'host_witnessed_receipt' else 'authorized_person_pin' end,
             'artifact', p_artifact, 'by', auth.uid(), 'at', now())))
  where id = p_session_dog;
  if p_side = 'owner' then
    update session_dogs set owner_confirmed_return_at = coalesce(owner_confirmed_return_at, now()) where id = p_session_dog;
  else
    update session_dogs set runner_confirmed_return_at = coalesce(runner_confirmed_return_at, now()) where id = p_session_dog;
  end if;
  insert into notifications (profile_id, kind, title, body, ref_id)
  values (case when p_side = 'owner' then sd.owner_profile_id else v_runner end,
          'community', '반환 확인 대리 기록', '호스트가 현장 확인으로 반환 확인을 기록했어요 (' || p_kind || ')', sd.session_id);
  -- [0069 §B] 양측 스탬프가 차면 어느 쪽이 마지막이든 여기서 마감한다 (콘솔이 버튼 두 개를 그린다)
  perform _club_finalize_return(p_session_dog);
end $$;
grant execute on function session_custody_override(uuid, text, text, jsonb) to authenticated;

-- ---------- §E. 닫히지 않은 세션의 미배정 위탁도 결국 환불된다 ----------
-- 0068이 T-10 자동 환불을 지운 뒤 남은 잔여: 호스트가 종료를 누르지 않으면 결제된 미배정 위탁이
-- 영영 matching에 남았다. expire_unmatched_bookings는 club_session_id 있는 부킹을 명시적으로
-- 제외하므로(0060:103) 아무 스윕도 닿지 않는다. 새 상수는 만들지 않는다 —
-- **배정 창이 닫히는 시각(T+6h, 0048:454)**을 그대로 쓴다. 그 뒤로는 배정이 서버적으로 불가능하므로
-- '이 위탁은 진행되지 않았다'가 추측이 아니라 사실이다. 세션을 닫지도, 완료를 날조하지도 않는다.
create or replace function club_stale_delegation_sweep() returns int
language plpgsql security definer set search_path = public, pg_temp as $$
declare sess record; n int := 0; v_ids uuid[];
begin
  for sess in
    select id, host_profile_id from club_sessions
    where status in ('open', 'full')
      and scheduled_at < now() - interval '6 hours'
      and scheduled_at > now() - interval '30 days'
    order by id
    for update
  loop
    select coalesce(array_agg(b.id), '{}') into v_ids
    from session_dogs d join bookings b on b.id = d.booking_id
    where d.session_id = sess.id and d.custody = 'runner_delegated' and b.status = 'matching';
    continue when coalesce(array_length(v_ids, 1), 0) = 0;
    n := n + _club_refund_bookings(v_ids, 'club_not_picked_up',
      '위탁 미진행 — 전액 환불', '배정 창이 닫힐 때까지 러닝이 진행되지 않아 전액 환불돼요');
    insert into notifications (profile_id, kind, title, body, ref_id)
    select sess.host_profile_id, 'community', '미진행 위탁 자동 환불',
           coalesce(array_length(v_ids, 1), 0) || '건이 배정 창 마감으로 환불됐어요 — 세션 종료를 눌러주세요', sess.id
    where not exists (select 1 from notifications
                      where profile_id = sess.host_profile_id and ref_id = sess.id
                        and title = '미진행 위탁 자동 환불');
  end loop;
  return n;
end $$;
revoke execute on function club_stale_delegation_sweep() from public, anon, authenticated;

comment on function club_stale_delegation_sweep is
  '0070 §E: 배정 창(T+6h) 마감 뒤에도 matching인 결제 위탁을 club_not_picked_up으로 환불한다 —
0068이 T-10 자동 환불을 지운 뒤 남은 좌초를 회수. 세션을 닫지도 완료를 날조하지도 않는다';

do $$ begin
  create extension if not exists pg_cron;
  perform cron.schedule('club-stale-delegation-sweep', '17 * * * *', 'select club_stale_delegation_sweep()');
exception when others then
  raise notice 'pg_cron unavailable — schedule manually: %', sqlerrm;
end $$;

-- ---------- §G(cont). 반환 종단은 '약한 쪽'을 기록한다 — 증빙 세탁 금지 ----------
create or replace function _club_finalize_return(p_session_dog uuid) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare sd record; v_runner uuid; v_ok text; v_rk text; v_kind text;
begin
  select * into sd from session_dogs where id = p_session_dog;
  if sd.id is null then return false; end if;
  if sd.owner_confirmed_return_at is null or sd.runner_confirmed_return_at is null then return false; end if;
  if sd.custody_phase = 'resolved' then return false; end if;              -- 멱등
  select runner_id into v_runner from bookings where id = sd.booking_id;

  -- [0070 §G] 측별 기록에서 **약한 쪽**을 종단 confirmation_kind로 삼는다. 한 측이 당사자 본인
  -- 확인(app_user)이고 다른 측이 호스트 대리였다면, 그 반환은 대리로 확인된 반환이다 — 강한 쪽을
  -- 적으면 커스터디 체인이 실제보다 강한 증거를 주장한다. 구 형태(sides 없음) 행은 최상위 kind로
  -- 후퇴한다. 전체 기록은 meta에 그대로 실어 아무것도 잃지 않는다.
  v_ok := coalesce(sd.return_override->'sides'->'owner'->>'kind', sd.return_override->>'kind', 'app_user');
  v_rk := coalesce(sd.return_override->'sides'->'runner'->>'kind', sd.return_override->>'kind', 'app_user');
  v_kind := case
    when 'authorized_person_pin' in (v_ok, v_rk) then 'authorized_person_pin'
    when 'host_witnessed_receipt' in (v_ok, v_rk) then 'host_witnessed_receipt'
    else 'app_user' end;

  insert into dog_custody_events
    (session_dog_id, from_type, from_profile_id, to_type, to_profile_id, event_type,
     confirmation_kind, meta)
  values (sd.id, 'runner', v_runner, 'owner', sd.owner_profile_id, 'return', v_kind,
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
  '0069 §B + 0070 §G: 양측 반환 확정 종단 — confirmation_kind는 두 측 중 **약한 쪽**을 적는다
(강한 쪽을 적으면 커스터디 체인이 실제보다 강한 증거를 주장한다) · 전체 측별 기록은 meta.override에 보존';

-- ---------- §H. 주체 없는 케이스는 세션 종료를 인질로 잡을 수 없다 ----------
-- 게스트 RSVP만으로 shell='full'이 되고(0048 §게스트 RSVP 1급), 주체 없는 케이스는 §B 검증을
-- 통과할 게 없다 — 독립 리뷰가 실측으로 한 계정이 미해소 케이스 9건을 쌓아 club_finish_session을
-- 무한정 막는 것을 보였다. 돈 쪽은 §E가 호스트 행동과 무관하게 회수하므로 이미 인질이 아니고,
-- 여기서는 소음 쪽에 상한을 둔다: **한 사람이 한 세션에 미해소 무주체 케이스 2건까지.**
-- 진짜 응급은 1건이면 되고, 두 번째는 다른 사건을 위한 여지다. 그 이상은 열린 케이스에 증거를 붙인다.
create or replace function club_incident_open(
  p_session uuid, p_severity text, p_summary text,
  p_dog uuid default null, p_booking uuid default null, p_location jsonb default null
) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s record; v_inc uuid; v_sd record;
  v_owner uuid; v_dog_name text; v_role text;
begin
  perform _club_require_v2();
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if p_severity not in ('S1', 'S2', 'S3') then raise exception 'bad_severity'; end if;
  if coalesce(trim(p_summary), '') = '' then raise exception 'summary_required'; end if;

  -- [0067 §C] party gate BEFORE state gate — 없는 세션도 not_party (존재 오라클 없음)
  if not _club_incident_can_open(p_session, auth.uid()) then raise exception 'not_party'; end if;
  select * into s from club_sessions where id = p_session for update;
  if s.id is null then raise exception 'not_party'; end if;

  -- [0067 §B] subject gate — 검증 없이는 원격 지급 동결 프리미티브였다
  if p_dog is not null and not _club_incident_dog_party(p_session, p_dog, auth.uid()) then
    raise exception 'not_dog_party';
  end if;
  if p_booking is not null and not _club_incident_booking_party(p_session, p_booking, auth.uid()) then
    raise exception 'not_booking_party';
  end if;
  -- [0070 §H] 무주체 케이스 상한 (열린 것만 센다 — 해소하면 다시 열 수 있다)
  if p_dog is null and p_booking is null
     and (select count(*) from club_incidents i
          where i.session_id = p_session and i.opened_by = auth.uid() and i.state <> 'resolved'
            and not exists (select 1 from club_incident_subjects sub
                            where sub.incident_id = i.id and sub.subject_type in ('dog', 'booking'))) >= 2
  then raise exception 'open_case_limit'; end if;

  insert into club_incidents (session_id, severity, state, opened_by, summary)
  values (p_session, p_severity, 'open', auth.uid(), trim(p_summary))
  returning id into v_inc;
  insert into club_incident_subjects (incident_id, subject_type, subject_id)
  values (v_inc, 'session', p_session);
  if p_dog is not null then
    insert into club_incident_subjects (incident_id, subject_type, subject_id) values (v_inc, 'dog', p_dog);
    -- 강아지에 열린 인시던트 ⇒ 지급 보류 (릴리스 크론의 직렬화 지점 — 세션 락 하에서 씀).
    -- ended 행도 보류한다 (레이스 검사 RC가 잡은 결함).
    for v_sd in select id from session_dogs
      where session_id = p_session and dog_id = p_dog and custody = 'runner_delegated'
        and payout_state <> 'released'
    loop
      update session_dogs set payout_hold = 'held', payout_hold_reason = 'incident',
        payout_hold_incident = v_inc where id = v_sd.id;
    end loop;
  end if;
  if p_booking is not null then
    insert into club_incident_subjects (incident_id, subject_type, subject_id) values (v_inc, 'booking', p_booking);
  end if;
  if p_location is not null then
    insert into club_incident_evidence (incident_id, kind, payload, created_by)
    values (v_inc, 'location', p_location, auth.uid());
  end if;

  -- S1/S2 = 크리티컬 (제목 레지스트리 → ack 배너) · S3 = 커뮤니티 잉크
  insert into notifications (profile_id, kind, title, body, ref_id)
  select p.pid, (case when p_severity = 'S3' then 'community' else 'safety' end)::noti_kind,
         case when p_severity = 'S3' then '인시던트 접수' else '인시던트 발생' end,
         '[' || p_severity || '] ' || trim(p_summary) || ' — 케이스를 확인하세요', p_session
  from (select s.host_profile_id as pid
        union select s.backup_host_profile_id where s.backup_host_profile_id is not null) p
  where p.pid is not null and p.pid <> auth.uid();

  -- [0067 §E — C3] 커밋 러너 전원 팬아웃 (5분 dedup은 club_sos의 것 그대로)
  if p_severity in ('S1', 'S2') then
    insert into notifications (profile_id, kind, title, body, ref_id)
    select a.runner_profile_id, 'safety', '인시던트 발생',
           '[' || p_severity || '] ' || trim(p_summary) || ' — 주변을 확인하세요', p_session
    from session_runner_assignments a
    where a.session_id = p_session and a.status = 'committed'
      and a.runner_profile_id <> auth.uid()
      and a.runner_profile_id is distinct from s.host_profile_id
      and a.runner_profile_id is distinct from s.backup_host_profile_id
      and not exists (select 1 from notifications n where n.profile_id = a.runner_profile_id
                      and n.ref_id = p_session and n.title = '인시던트 발생'
                      and n.created_at > now() - interval '5 minutes');
  end if;

  -- [0067 §E — C3] 대상견 보호자에게 알린다 (제목은 상수 = ack 레지스트리 정확 일치)
  if p_dog is not null then
    select sd.owner_profile_id, d.name into v_owner, v_dog_name
    from session_dogs sd join dogs d on d.id = sd.dog_id
    where sd.session_id = p_session and sd.dog_id = p_dog;
  elsif p_booking is not null then
    select b.owner_id, d.name into v_owner, v_dog_name
    from bookings b join dogs d on d.id = b.dog_id where b.id = p_booking;
  end if;
  if v_owner is not null and v_owner <> auth.uid() then
    v_role := case
      when auth.uid() in (s.host_profile_id, s.backup_host_profile_id) then '호스트'
      when exists (select 1 from session_dogs sd join bookings b on b.id = sd.booking_id
                   where sd.session_id = p_session and b.runner_id = auth.uid()
                     and (p_dog is null or sd.dog_id = p_dog)) then '담당 러너'
      else '참가자' end;
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (v_owner,
      (case when p_severity = 'S3' then 'community' else 'safety' end)::noti_kind,
      case when p_severity = 'S3' then '담당견 케이스 접수' else '담당견 인시던트' end,
      coalesce(v_dog_name, '위탁견') || ' — [' || p_severity || '] ' || trim(p_summary)
        || ' · ' || v_role || '가 케이스를 열었어요 — 케이스를 열어 상황을 확인하세요',
      p_session);
  end if;
  return v_inc;
end $$;
grant execute on function club_incident_open(uuid, text, text, uuid, uuid, jsonb) to authenticated;
