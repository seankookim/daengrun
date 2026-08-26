-- ═══ 축(0040 R0A) 스위트 — 백필·동기화·드리프트·프로젝션 ═══
-- 50/60 스위트가 만든 v1 세계를 그대로 검증 대상으로 사용 (별도 시드 최소화).
-- ⚠ [2026-08-21] 이 스위트의 아홉 개 `limit 1`은 모두 **무순**이었다. 백필 단언 핀(X2·X3·X4·
-- X6·X9)에서 그것은 "임의의 한 행"을 보는 것이었고, 술어에 맞는 행들의 프로파일이 갈리면
-- 통과·실패가 플래너 마음이었다 — 0117 뮤테이션 배터리 중 실제로 유령 red가 나왔다. 이제
-- 그 핀들은 **모든** 대상 행을 본다. 두 가지가 함께 필요하다:
--   ① 비공허성: 대상이 0행이면 "이탈 0행"은 공허한 초록이다. 먼저 대상 수를 단언한다.
--   ② NULL 안전: `not (A and B)`는 한 필드가 NULL이면 NULL이고, WHERE는 NULL을 세지 않아
--      **이탈 행이 조용히 빠진다**(이 저장소가 0058 F1·110 S2·0116 §D에서 세 번 겪은 fail-open).
--      그래서 `not coalesce(<프로파일>, false)`로 센다.
-- 행을 **고르기만** 하는 핀(X5·X8·X10)은 어떤 행이든 무방하므로 순서만 고정했다(재현성).
set client_min_messages = warning;

do $$
declare
  v_cnt int; v_bad int; v_txt2 text; v_sd record; v_js jsonb;
begin
  -- [X1] 드리프트 제로 — 모든 기존 행의 저장 축 = 재계산 축
  begin
    select count(*) into v_cnt from club_drift_check();
    if v_cnt = 0 then call _pass('axes','X1 드리프트 제로 (전 행 저장=재계산)');
    else
      declare v_detail text;
      begin
        select string_agg(field || ':' || coalesce(stored,'∅') || '≠' || coalesce(expected,'∅'), ', ')
        into v_detail from (select * from club_drift_check() limit 3) t;
        call _fail('axes','X1 드리프트','rows=' || v_cnt || ' — ' || coalesce(v_detail,''));
      end;
    end if;
  exception when others then call _fail('axes','X1 드리프트', sqlerrm);
  end;

  -- [X2] 완료+반환 해소(resolved) 위탁견의 축 프로파일 — **전 행**
  -- ⚠ [2026-08-21, 무순 limit 1을 걷어내자마자 드러난 사실] payout_state는 두 값 모두가 참이다:
  --   'released' — v1 축 동기화(0040:233)가 completed+원장행 있음에 대해 직접 쓰는 값
  --   'payable'  — v2 커스터디 반환 경로(0045:109·0046:58·0069:70·0070:374·0072:189)가
  --                earned→payable로 올린 뒤, **지급이 일어나야** released가 되는데 이 저장소에는
  --                payouts에 writer가 하나도 없다. 즉 payable은 부패가 아니라 **미구축 지급
  --                루프의 상시 표식**이다 (X1 드리프트 제로가 이 행들의 내부 정합성을 이미 보증).
  -- 7행 중 2행이 payable이었고, 옛 무순 `limit 1`은 그 두 행을 뽑으면 red, 나머지 다섯을 뽑으면
  -- green이었다 — 유령 red의 정체가 바로 이것이다. 지급 루프가 생기는 날 이 핀은 세 번째 값이
  -- 나타나거나 payable이 남아 있으면 red가 된다.
  -- [R2] 정산≠반환이므로 resolved 행만 이 프로파일 — 미반환 완료 행은 X11에서 별도 단언
  begin
    select count(*), count(*) filter (where not coalesce(
             sd.service_state = 'ended' and sd.completion_outcome = 'completed'
             and sd.charge_state = 'paid' and sd.payout_state in ('released','payable')
             and sd.assignment_state = 'accepted' and sd.custodian_type = 'owner', false))
      into v_cnt, v_bad
      from session_dogs sd join bookings b on b.id = sd.booking_id
     where sd.custody = 'runner_delegated' and b.status = 'completed'
       and sd.custody_phase = 'resolved';
    if v_cnt = 0 then call _fail('axes','X2 완료 백필','대상 0행 — 픽스처 소실 (공허한 초록 차단)');
    elsif v_bad = 0
      then call _pass('axes','X2 완료·해소 위탁 전 행 (ended/completed·paid·released|payable·accepted·owner)');
    else
      -- red가 defect를 **호명**한다: 어느 축이 어떤 값으로 이탈했는지 (숫자만 있는 red는 다음
      -- 사람에게 조사를 통째로 넘긴다)
      select string_agg(d, ', ') into v_txt2 from (
        select distinct case
                 when not coalesce(sd.service_state = 'ended', false) then 'service_state=' || coalesce(sd.service_state,'∅')
                 when not coalesce(sd.completion_outcome = 'completed', false) then 'completion_outcome=' || coalesce(sd.completion_outcome,'∅')
                 when not coalesce(sd.charge_state = 'paid', false) then 'charge_state=' || coalesce(sd.charge_state,'∅')
                 when not coalesce(sd.payout_state in ('released','payable'), false) then 'payout_state=' || coalesce(sd.payout_state,'∅')
                 when not coalesce(sd.assignment_state = 'accepted', false) then 'assignment_state=' || coalesce(sd.assignment_state,'∅')
                 else 'custodian_type=' || coalesce(sd.custodian_type,'∅') end as d
          from session_dogs sd join bookings b on b.id = sd.booking_id
         where sd.custody = 'runner_delegated' and b.status = 'completed'
           and sd.custody_phase = 'resolved'
           and not coalesce(sd.service_state = 'ended' and sd.completion_outcome = 'completed'
                 and sd.charge_state = 'paid' and sd.payout_state in ('released','payable')
                 and sd.assignment_state = 'accepted' and sd.custodian_type = 'owner', false)) t;
      call _fail('axes','X2 완료 백필', v_bad || '/' || v_cnt || '행 이탈 — ' || coalesce(v_txt2,'?'));
    end if;
  exception when others then call _fail('axes','X2 완료 백필', sqlerrm);
  end;

  -- [X3] 거절 위탁견 → ended/no_service/cancelled/host_rejected (ended 불변 표현)
  begin
    select count(*), count(*) filter (where not coalesce(
             sd.service_state = 'ended' and sd.completion_outcome = 'no_service'
             and sd.termination_type = 'cancelled' and sd.service_reason = 'host_rejected'
             and sd.cancelled_by = 'host' and sd.charge_state = 'none', false))
      into v_cnt, v_bad
      from session_dogs sd
     where sd.custody = 'runner_delegated' and sd.approval = 'rejected';
    if v_cnt = 0 then call _fail('axes','X3 거절 백필','대상 0행 — 픽스처 소실 (공허한 초록 차단)');
    elsif v_bad = 0 then call _pass('axes','X3 거절 백필 전 행 (ended/no_service/host_rejected·무결제)');
    else call _fail('axes','X3 거절 백필', v_bad || '/' || v_cnt || '행이 프로파일 이탈'); end if;
  exception when others then call _fail('axes','X3 거절 백필', sqlerrm);
  end;

  -- [X4] 환불 경로 → refund_state=pending + 서비스 종료 (돈 진실과 서비스 진실 분리)
  begin
    select count(*), count(*) filter (where not coalesce(
             sd.charge_state = 'paid' and sd.refund_state = 'pending'
             and sd.service_state = 'ended' and sd.completion_outcome = 'no_service', false))
      into v_cnt, v_bad
      from session_dogs sd join bookings b on b.id = sd.booking_id
     where sd.custody = 'runner_delegated' and b.status = 'refund_pending';
    if v_cnt = 0 then call _fail('axes','X4 환불 백필','대상 0행 — 픽스처 소실 (공허한 초록 차단)');
    elsif v_bad = 0
      then call _pass('axes','X4 환불 백필 전 행 — charge=paid 유지 + refund=pending (진실 분리)');
    else call _fail('axes','X4 환불 백필', v_bad || '/' || v_cnt || '행이 프로파일 이탈'); end if;
  exception when others then call _fail('axes','X4 환불 백필', sqlerrm);
  end;

  -- [X5] [R2] 커스터디 이벤트 1차화: v1 동기화 트리거 제거·v2 전이 트리거 존재·
  --      responsible 변경은 더 이상 이벤트를 만들지 않는다 (이벤트는 전이 RPC/트리거만 생성)
  begin
    if exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
               where c.relname = 'session_dogs' and t.tgname = 'club_v1_custody_event')
       or exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                  where c.relname = 'bookings' and t.tgname = 'club_custody_transition')
      then call _fail('axes','X5 v1 잔존','v1 커스터디 트리거가 남아 있음');
    elsif not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                      where c.relname = 'bookings' and t.tgname = 'club_custody_transition_v2')
      then call _fail('axes','X5 v2 부재','club_custody_transition_v2 없음');
    else
      select sd.* into v_sd from session_dogs sd
      where sd.custody = 'runner_delegated' and sd.responsible_profile_id = sd.owner_profile_id
        and sd.booking_id is not null order by sd.id limit 1;   -- 고르기만 하는 핀: 순서 고정
      select count(*) into v_cnt from dog_custody_events where session_dog_id = v_sd.id;
      update session_dogs set responsible_profile_id =
        (select runner_id from bookings where id = v_sd.booking_id) where id = v_sd.id
        and exists (select 1 from bookings where id = v_sd.booking_id and runner_id is not null);
      update session_dogs set responsible_profile_id = v_sd.owner_profile_id where id = v_sd.id;
      if (select count(*) from dog_custody_events where session_dog_id = v_sd.id) = v_cnt
        then call _pass('axes','X5 이벤트 1차화 — v1 트리거 제거·v2 전이 존재·responsible 무이벤트');
      else call _fail('axes','X5 이벤트','responsible 변경이 이벤트 생성'); end if;
    end if;
  exception when others then call _fail('axes','X5 이벤트', sqlerrm);
  end;

  -- [X6] 구조화 프로젝션 + 플래그 기본 OFF
  begin
    -- [R2] '완료' 표기는 resolved 한정. 전 행을 투영해 검사한다 — 한 행만 보면 프로젝션이
    -- 어느 행에서 깨졌는지는 뽑기 운이었다.
    select count(*), count(*) filter (where not coalesce(
             club_dog_ui_state(sd.id)->>'primaryStage' = '완료'
             and jsonb_typeof(club_dog_ui_state(sd.id)->'secondaryBadges') = 'array'
             and jsonb_typeof(club_dog_ui_state(sd.id)->'requiredActors') = 'array'
             and club_dog_ui_state(sd.id) ? 'severity', false))
      into v_cnt, v_bad
      from session_dogs sd
     where sd.custody = 'runner_delegated' and sd.service_state = 'ended'
       and sd.completion_outcome = 'completed' and sd.custody_phase = 'resolved';
    if v_cnt = 0 then call _fail('axes','X6 프로젝션','대상 0행 — 픽스처 소실 (공허한 초록 차단)');
    elsif v_bad = 0 and exists (select 1 from club_flags where name = 'club_delegation_v2')
      then call _pass('axes','X6 구조화 프로젝션 전 행 (stage/badges/actors/severity) + 플래그 존재');
    else call _fail('axes','X6 프로젝션', v_bad || '/' || v_cnt || '행 이탈 또는 플래그 부재'); end if;
  exception when others then call _fail('axes','X6 프로젝션', sqlerrm);
  end;

  -- [X7] 최종 드리프트 재확인 (X5의 변경·원복 후에도 제로)
  begin
    select count(*) into v_cnt from club_drift_check();
    if v_cnt = 0 then call _pass('axes','X7 드리프트 제로 유지 (변경·원복 후)');
    else call _fail('axes','X7 드리프트','rows=' || v_cnt); end if;
  end;
end $$;

-- ═══ R0A 하드닝(0041) 검증 — 독립 오라클·부패 감지·권한 봉인·리터럴 매핑 ═══
do $$
declare
  v_cnt int; v_bad int; v_sd record; v_txt text; v_err boolean := false;
begin
  -- [X8] 부패 감지 — 동기화 트리거를 끄고 축을 오염시키면 드리프트가 잡는다 (자기검증 우회 증명)
  begin
    -- [2026-08-26] ⚠ 이 선택은 예전에 `order by sd.id limit 1`에 「순서 고정」 주석이 달려 있었다.
    -- `id`는 gen_random_uuid()라 그 주석은 **거짓**이었다 — 고정이 아니라 임의였다. 그리고 이 핀은
    -- 두 필드를 오염시켜 drift ≥2를 기대하는데, 고른 행에서 두 쓰기 중 하나가 no-op이면 detected=1로
    -- 떨어진다. drift는 「저장값 vs 재계산값」이고 `charge_state='hold'`의 재계산 조건은
    -- `hold_status='active' AND hold_expires_at > now()` (0043:75) — **시간 의존**이다. 그래서
    -- 실패가 간헐적이었고(CI에서 ~1/17), 같은 커밋이 재실행에서 통과했다.
    -- 고침: 두 쓰기가 **반드시** 값을 바꾸는 행만 고른다. 그러면 detected=2가 구조적으로 보장된다.
    -- ⚠ 조건에 맞는 행이 없으면 조용히 아무 행이나 잡지 말고 **크게 실패**한다 — 픽스처가 바뀌었다는
    -- 사실 자체가 이 핀이 무엇을 재고 있는지에 대한 정보다.
    select sd.* into v_sd from session_dogs sd
      where sd.custody = 'runner_delegated'
        and sd.charge_state is distinct from 'hold'
        and sd.assignment_state is distinct from 'replacement_needed'
      order by sd.id limit 1;
    -- ⚠ `return`이 아니라 raise다. plpgsql의 bare `return`은 이 DO 블록 **전체**를 끝내므로
    -- 뒤따르는 X9·X10이 조용히 건너뛰어진다 — 정직한 실패 하나를 실패 하나 + 침묵 둘로 바꾸는 짓이다.
    -- 아래 `exception when others` 핸들러가 트리거를 되살리고 _fail을 부른 뒤 X9로 계속 간다.
    if v_sd.id is null then
      raise exception '오염 가능한 runner_delegated 행이 없다 — 픽스처가 바뀌었다';
    end if;
    alter table session_dogs disable trigger club_v1_axes_sync;
    update session_dogs set charge_state = 'hold', assignment_state = 'replacement_needed' where id = v_sd.id;
    alter table session_dogs enable trigger club_v1_axes_sync;
    select count(*) into v_cnt from club_drift_check() where session_dog_id = v_sd.id;
    -- 복구 (트리거 재계산)
    update session_dogs set id = id where id = v_sd.id;
    if v_cnt >= 2 and (select count(*) from club_drift_check()) = 0
      then call _pass('axes','X8 부패 감지 — 오염 ' || v_cnt || '필드 검출 + 재동기화 복구');
    else call _fail('axes','X8 부패','detected=' || v_cnt); end if;
  exception when others then
    alter table session_dogs enable trigger club_v1_axes_sync;
    call _fail('axes','X8 부패', sqlerrm);
  end;

  -- [X9] 동반견 리터럴 — 커스터디만 받고 돈·배정 축은 중립값
  begin
    select count(*), count(*) filter (where not coalesce(
             sd.service_state is null and sd.charge_state = 'none'
             and sd.refund_state = 'none' and sd.payout_state = 'none'
             and sd.assignment_state = 'unassigned'
             and sd.custodian_type = 'owner' and sd.custodian_profile_id = sd.owner_profile_id
             and sd.custody_phase = 'with_custodian', false))
      into v_cnt, v_bad
      from session_dogs sd where sd.custody = 'owner_handled';
    if v_cnt = 0 then call _fail('axes','X9 동반견','대상 0행 — 픽스처 소실 (공허한 초록 차단)');
    elsif v_bad = 0 then call _pass('axes','X9 동반견 리터럴 전 행 (커스터디 ○ · 돈/배정 중립)');
    else call _fail('axes','X9 동반견', v_bad || '/' || v_cnt || '행이 프로파일 이탈'); end if;
  exception when others then call _fail('axes','X9 동반견', sqlerrm);
  end;

  -- [X10] RLS 봉인 (실서비스 권한 모사 하) — grant는 있으나 정책 0 = 행 비가시 + 쓰기 거부
  begin
    insert into club_incidents (session_id, severity, summary)
    select id, 'S3', '봉인 테스트' from club_sessions order by id limit 1;
    begin
      set local role authenticated;
      perform set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
      execute 'select count(*) from club_incidents' into v_cnt;
      begin
        insert into club_incidents (session_id, severity, summary)
        select id, 'S3', '침입 시도' from club_sessions order by id limit 1;
        v_err := false;
      exception when others then v_err := true;
      end;
      reset role;
    exception when others then reset role; raise;
    end;
    delete from club_incidents where summary = '봉인 테스트';
    if v_cnt = 0 and v_err
      then call _pass('axes','X10 RLS 봉인 — grant 하 행 비가시(0) + 정책 무 쓰기 거부');
    else call _fail('axes','X10 봉인','visible=' || v_cnt || ' write_blocked=' || v_err); end if;
  exception when others then call _fail('axes','X10 봉인', sqlerrm);
  end;

  -- [X11] 리터럴 매핑 오라클 — compute 함수를 거치지 않는 상태별 기대값 직접 단언
  begin
    -- pending → requested/none/unassigned
    select count(*) into v_cnt from session_dogs
    where custody = 'runner_delegated' and approval = 'pending'
      and not (service_state = 'requested' and charge_state = 'none' and assignment_state = 'unassigned');
    if v_cnt > 0 then call _fail('axes','X11 리터럴','pending 불일치 ' || v_cnt); else
      -- 부킹 matching(승인·결제·수락 전) → confirmed/paid+consumed/비수락 배정 상태
      -- [R3] matching은 unassigned 외에도 proposed/declined/replacement_needed 가능 — accepted만 모순
      select count(*) into v_cnt from session_dogs sd join bookings b on b.id = sd.booking_id
      where sd.custody = 'runner_delegated' and b.status = 'matching'
        and not (sd.service_state = 'confirmed' and sd.charge_state = 'paid'
                 and sd.hold_status = 'consumed' and sd.assignment_state <> 'accepted'
                 and sd.custodian_type = 'owner');
      if v_cnt > 0 then call _fail('axes','X11 리터럴','matching 불일치 ' || v_cnt); else
        -- 환불 계열 → refund=pending·service=ended (전건)
        select count(*) into v_cnt from session_dogs sd join bookings b on b.id = sd.booking_id
        where sd.custody = 'runner_delegated' and b.status in ('refund_pending','cancelled_runner','expired')
          and not (sd.refund_state = 'pending' and sd.service_state = 'ended' and sd.charge_state = 'paid');
        if v_cnt > 0 then call _fail('axes','X11 리터럴','환불 불일치 ' || v_cnt); else
          -- [R2] completed 이분법: 해소행(체크아웃 또는 양측 반환 확인) = owner/resolved/payable+
          --      미반환행 = runner/return_pending/earned — 외부 커스터디언(클리닉 등)은 별도 프로파일
          select count(*) into v_cnt from session_dogs sd join bookings b on b.id = sd.booking_id
          where sd.custody = 'runner_delegated' and b.status = 'completed'
            and sd.custodian_type not in ('clinic','authority','authorized_person')
            and case when sd.checked_out_at is not null
                       or (sd.owner_confirmed_return_at is not null
                           and sd.runner_confirmed_return_at is not null)
                then not (sd.service_state = 'ended' and sd.custodian_type = 'owner'
                          and sd.custody_phase = 'resolved'
                          and sd.payout_state in ('payable','released'))
                else not (sd.custodian_type = 'runner' and sd.custody_phase = 'return_pending'
                          and sd.payout_state = 'earned') end;
          if v_cnt > 0 then call _fail('axes','X11 리터럴','completed 불일치 ' || v_cnt);
          else call _pass('axes','X11 리터럴 매핑 오라클 — pending·matching·환불·완료(R2 이분) 일치'); end if;
        end if;
      end if;
    end if;
  exception when others then call _fail('axes','X11 리터럴', sqlerrm);
  end;

  -- [X12] 커밋 시점 동기화 — 이 DO 블록(단일 tx) 안에서 상태를 굴려도 커밋 후 드리프트 0는
  -- X13(다음 블록)이 확인. 여기서는 deferred 트리거가 등록돼 있음을 단언.
  begin
    if exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
               where c.relname = 'bookings' and t.tgname = 'club_v2_axes_poke'
                 and t.tgdeferrable and t.tginitdeferred)
       and not exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid
                       where c.relname = 'ledger_items' and t.tgname = 'club_v2_ledger_poke')
      then call _pass('axes','X12 커밋 시점 동기화 — deferred 트리거 등록·원장 훅 제거');
    else call _fail('axes','X12 deferred','트리거 상태 불일치'); end if;
  end;
end $$;

-- [X13] 별도 트랜잭션에서 최종 드리프트 — deferred 동기화가 커밋을 통과한 뒤의 전역 정합
do $$
declare v_cnt int;
begin
  select count(*) into v_cnt from club_drift_check();
  if v_cnt = 0 then call _pass('axes','X13 커밋 후 전역 드리프트 제로 (deferred 동기화 검증)');
  else call _fail('axes','X13 드리프트','rows=' || v_cnt); end if;
end $$;

