-- ═══ 0054: 매칭 화면 가용성 게이팅 — 수락 게이트의 표시측 거울 ═══
-- 왜:
--  1) 보호자의 지명 매칭 화면은 바쁜 러너를 그대로 보여준다. fetchCertifiedRunners(api.ts:461)는
--     runners 테이블 생읽기 + tier<>'applicant' + online 필터가 전부 — 가용성 필터가 0이다.
--     보호자가 이미 다른 러닝에 묶인 러너를 지명하면 수락 측 409("그 시간에 이미 확정된 일정이
--     있어요" — transition-booking runner_accept)가 유일한 방어였다. 즉 '이 사람은 안 된다'는 사실을
--     화면이 아니라 거절이 알려줬다. 기다림·재지명·불신이 전부 보호자 몫이었다.
--  2) 이 RPC는 그 수락 게이트를 **표시측에서 그대로 거울**로 만든다 (transition-booking/index.ts:41-54):
--     구간 = [scheduled_at, scheduled_at + (km*8+25)분) · LIVE 상태 정확히 4종
--     (confirmed·runner_enroute·picked_up·active) · 후보 프리필터 scheduled_at ∈ [aStart-6h, aEnd+6h] ·
--     반열림 엄격 겹침 (cs < aEnd and ce > aStart). 넷 다 그대로 옮겼다.
--  3) is_slot_available(0003)을 **일부러 쓰지 않는다**: 그 함수는 runner_pending까지 점유로 세고
--     rest_after_min 휴식 버퍼를 양쪽에 덧대며 주간 가용 규칙·일일 상한·슬롯 홀드까지 본다 →
--     수락 게이트보다 엄격하다. 표시가 서버보다 엄격하면 **서버가 수락할 러너를 화면이 숨긴다**
--     (공급이 조용히 증발, 보호자는 이유를 모른다). 표시가 서버보다 느슨하면 죽은 지명이 남는다.
--     화면과 서버는 정확히 같은 문장을 말해야 한다 — 그래서 '거울'이고, 그래서 0003이 아니다.
--     (같은 이유로 runner_accept도 0003을 안 쓴다 — index.ts:38-40 주석 참조.)
--  4) club_session_id로 거르지 않는다: 배정된 클럽 위탁 부킹은 같은 LIVE 상태를 타므로 자동으로
--     점유되고, 확약만 하고 아직 배정 안 된 클럽 러너는 bookings 행이 없어 막히지 않는다 —
--     둘 다 수락 게이트의 동작과 같다. 별도 처리가 곧 이탈이다.
--  5) 대상 부킹 자신은 충돌 스캔에서 뺀다(c.id <> p_booking): 재지명(rebook) 모드에서 현재 지명
--     러너가 '자기 부킹과 겹친다'는 이유로 목록에서 사라지는 자기충돌을 막는다.
--  6) 당사자 게이트를 머리에 둔다 — 임의 booking uuid로 남의 일정 창(시각·거리)을 캐는 프로빙
--     오라클 차단. 부킹 부재와 남의 부킹은 구별 불가(둘 다 not_owner). 0053 §3a 선례 + 0052 rev2 P0의
--     coalesce(..., false) 법칙(NULL이 술어를 접어 not(...)을 무력화하는 우회 봉함).
--     부킹 status는 러너 선택 단계(payment_hold·matching·runner_pending)로 게이팅한다 — 무료 draft
--     프로브로 남 일정을 복원하는 집계 오라클 차단(아래 본문 주석). 가용 판정 자체가 '이 시각에 이
--     러너가 바쁘다'는 1비트를 주는 것은 이 기능의 본질이라 남는다 — 프로브 비용을 올리는 게 방어다.
--  7) 반환은 평면 컬럼만 — 가용 '판정'만 주고 스케줄 상세(누가 언제 어디에 묶였는지)는 한 줄도
--     주지 않는다. 컬럼 집합은 0015 available_runners 뷰의 공개 스토어프런트 화이트리스트와 동일.
--
-- ── 가용성 정의가 셋이다 · 통합하지 말 것 ────────────────────────────────────────────────
--   · 0015 available_runners (뷰)  — find-now 히어로 카운트/레이더. 시간 인자가 **없다**('지금'
--     기준, 2시간 내 confirmed 제외). 화면: 즉시 요청.
--   · 0003 is_slot_available (함수) — 슬롯 예약 규칙 엔진. 주간 규칙·휴식 버퍼·일일 상한·홀드.
--     화면: 예약 캘린더에서 슬롯을 고를 때.
--   · 0054 runners_available_for (이 함수) — **특정 부킹**의 지명 화면. 수락 게이트의 거울.
--   셋은 서로 다른 화면의 서로 다른 계약이다. 하나로 합치면 반드시 어느 한 화면이 거짓말한다
--   (합집합 → 죽은 버튼, 교집합 → 공급 증발). 중복이 아니라 분화다.
--
-- 불변: 0053까지는 정본. 기존 파일 수정 없음 — 모든 변경은 이 파일에서 create or replace.

-- ---------- km 양수 제약 — 게이트 무력화 봉인 (적대 리뷰 P1) ----------
-- bookings.km은 CHECK 0개 + 당사자 update 정책(0002:97, with check 없음)으로 음수 기입이 가능했다.
-- km이 음수면 v_end < v_start가 되어 겹침 술어가 항구 거짓 — 이 RPC와 수락 게이트가 동시에 무력화
-- (겹치는 러너가 전원 가용으로 표시되고 수락도 통과 → 이중 계약). 리뷰어가 role authenticated로 실증.
-- not valid: 기존 행 검증은 생략(원격 잔여 데이터로 push가 죽는 사고 방지) — 신규 쓰기부터 봉인.
-- 가드 DDL: 재적용 시 duplicate_object로 파일 중도 사망(ON_ERROR_STOP) → 함수 교체 누락 사고 방지.
do $$ begin
  alter table bookings add constraint bookings_km_positive check (km > 0) not valid;
exception when duplicate_object then null; end $$;

-- ---------- 보호자의 지명 매칭 화면용 가용 러너 목록 ----------
create or replace function runners_available_for(p_booking uuid)
returns table (
  profile_id uuid,
  name text,
  district text,
  avatar_url text,
  tier runner_tier,
  bio text,
  avg_pace_sec_per_km int,
  total_runs int,
  respond_rate_pct int
)
-- search_path에 pg_temp를 명시적으로 '마지막'에 둔다 — 미명시 시 PG는 pg_temp를 먼저 탐색하므로
-- 임시 테이블 bookings 섀도잉으로 definer 게이트가 우회된다 (적대 리뷰 P2 실증. 0055+에서 전 definer 함수 일괄 교정 예정).
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_start timestamptz;
  v_end timestamptz;
begin
  -- 당사자 게이트 (프로빙 오라클 차단 — 부킹 부재와 타인 부킹이 구별 불가)
  if not coalesce((select b.owner_id = auth.uid() from bookings b where b.id = p_booking), false) then
    raise exception 'not_owner';
  end if;

  -- 상태 게이트 (적대 리뷰 2기 N2) — draft는 인증 계정이 '무료·무제한'으로 만들 수 있어(0002:95),
  -- 임의 시각의 draft 프로브를 반복 호출하면 특정 러너의 남 일정 창을 초 단위로 복원하는 집계
  -- 오라클이 된다. 러너 선택 단계(결제 후)의 부킹만 허용 — 프로브 1회당 실결제 홀드가 필요해진다.
  -- (payment_hold 포함: 결제 확정 직전에 매칭 화면이 열려도 죽지 않게. 지명 CAS는 어차피
  --  matching|runner_pending만 받는다 — 표시가 여기서 더 엄격할 이유가 없다.)
  if not coalesce((select b.status in ('payment_hold', 'matching', 'runner_pending')
                   from bookings b where b.id = p_booking), false) then
    raise exception 'not_open';
  end if;

  -- 대상 구간 [v_start, v_end) — 실소요 공식 km*8+25분.
  -- 분수 보존형(0003:55 스타일): 수락 게이트의 TS는 절삭하지 않는다(km 5.3 → 67.4분).
  -- make_interval(mins => ...::int) 형(0044/0053)은 초 단위를 버려 경계 케이스에서 거울이 깨진다.
  select b.scheduled_at, b.scheduled_at + ((b.km * 8 + 25) || ' minutes')::interval
    into v_start, v_end
  from bookings b where b.id = p_booking;

  -- 게이트와 창 조회가 두 문장이라 이론상 사이에 행이 사라질 수 있다(현재는 stable 스냅샷이 가리지만
  -- 휘발성이 바뀌면 fail-open: NULL 창 → not exists 항진 → 전원 노출). 닫힌 쪽으로 실패시킨다.
  if v_start is null then raise exception 'not_owner'; end if;

  return query
  select r.profile_id, p.name, p.district, p.avatar_url, r.tier, r.bio,
         r.avg_pace_sec_per_km, r.total_runs, r.respond_rate_pct
  from runners r
  join profiles p on p.id = r.profile_id
  where r.tier <> 'applicant'                      -- fetchCertifiedRunners와 동일한 스토어프런트 필터
    and r.online = true
    and not exists (
      select 1 from bookings c
      where c.runner_id = r.profile_id
        and c.id <> p_booking                      -- 재지명: 현재 지명 러너의 자기충돌 방지
        and c.status in ('confirmed', 'runner_enroute', 'picked_up', 'active')   -- LIVE 정확히 4종
        -- 후보 프리필터 — 수락 게이트가 이 창 밖은 아예 읽지 않는다. 창을 좁히면 서버보다 엄격해지고
        -- 넓히면 느슨해지므로 그대로 옮긴다 (상한은 아래 반열림 조건에 포섭되지만 거울의 문자 그대로).
        and c.scheduled_at >= v_start - interval '6 hours'
        and c.scheduled_at <= v_end + interval '6 hours'
        -- 반열림 엄격 겹침: cs < aEnd and ce > aStart (경계 맞닿음은 충돌 아님 — 연속 세션 허용)
        and c.scheduled_at < v_end
        and c.scheduled_at + ((c.km * 8 + 25) || ' minutes')::interval > v_start
    )
  order by r.total_runs desc, r.profile_id             -- 결정적 정렬 (동점도 흔들리지 않음)
  limit 10;                                            -- 현재 클라 .limit(10)과 동일
end $$;

revoke execute on function runners_available_for(uuid) from public, anon;
grant execute on function runners_available_for(uuid) to authenticated;

comment on function runners_available_for is
  '지명 매칭 화면의 가용 러너 (0054) — 수락 게이트(transition-booking runner_accept)의 표시측 거울:
같은 공식(km*8+25분)·같은 LIVE 4종·같은 ±6h 프리필터·같은 반열림 겹침 · 대상 부킹 자신은 제외(재지명)
· 보호자만 호출 가능(아니면 not_owner — 타인 일정 프로빙 차단) · 평면 공개 필드만 반환(스케줄 상세 0).
is_slot_available(0003)은 의도적으로 쓰지 않는다 — 그쪽이 더 엄격해 서버가 수락할 러너를 숨긴다.';
