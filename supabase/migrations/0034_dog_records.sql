-- ═══ 0034: 강아지 기록 감지 — P3 기록 골드의 데이터 소스 (Sean 확정 컬러 리바이탈라이즈) ═══
-- 원칙: 골드는 사건에만 — 첫 완주는 팡파레 없음 (비교 대상이 있어야 '경신'), 기록은 실데이터만.
-- 구현: runs 트리거 (settle_run_tx 재작성 없이 정산 트랜잭션 안에서 함께 커밋).
--   기록 종류: ① 최고 페이스 경신 ② 누적 km 마일스톤 (10/25/50/100/250/500/1000)
--   ③ n번째 완주 (10/25/50/100). 알림 kind='reward' (기존 이넘 재사용 — 앱 소인 잉크는
--   제목의 '경신/달성/완주' + 🏆로 골드 처리, 탭 라우팅은 reward → 리포트).

create or replace function _detect_dog_records() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_dog uuid; v_owner uuid; v_name text;
  v_prev_best int; v_prev_km numeric; v_prev_cnt int;
  v_t int; v_n int;
begin
  select b.dog_id, b.owner_id into v_dog, v_owner from bookings b where b.id = new.booking_id;
  if v_dog is null or v_owner is null then return new; end if;
  select name into v_name from dogs where id = v_dog;

  -- 이전 완주 집계 (현재 런 제외 — '경신'은 과거와의 비교)
  select min(r.avg_pace_sec_per_km) filter (where r.actual_km >= 1),
         coalesce(sum(r.actual_km), 0), count(*)
  into v_prev_best, v_prev_km, v_prev_cnt
  from runs r join bookings b on b.id = r.booking_id
  where b.dog_id = v_dog and r.end_reason = 'completed' and r.booking_id <> new.booking_id;

  -- ① 최고 페이스 경신 (1km 미만 런은 페이스 기록 제외 — 짧은 전력질주 왜곡 방지)
  if new.avg_pace_sec_per_km is not null and new.actual_km >= 1
     and v_prev_best is not null and new.avg_pace_sec_per_km < v_prev_best then
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (v_owner, 'reward', '🏆 ' || v_name || ' 최고 페이스 경신!',
      (new.avg_pace_sec_per_km / 60)::text || '''' || lpad((new.avg_pace_sec_per_km % 60)::text, 2, '0')
        || '"/km — 이전 최고보다 ' || (v_prev_best - new.avg_pace_sec_per_km)::text || '초 단축',
      new.booking_id);
  end if;

  -- ② 누적 km 마일스톤 — 이번 런이 임계를 '통과'했을 때 1회 (여러 개 지나면 최고 임계만)
  select max(m) into v_t from unnest(array[10, 25, 50, 100, 250, 500, 1000]) m
  where v_prev_km < m and v_prev_km + new.actual_km >= m;
  if v_t is not null then
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (v_owner, 'reward', '🏆 ' || v_name || ' 누적 ' || v_t || 'km 달성',
      '동네를 ' || v_t || 'km나 달렸어요 — 기록 컬렉션에서 확인하세요', new.booking_id);
  end if;

  -- ③ n번째 완주 (10/25/50/100)
  v_n := v_prev_cnt + 1;
  if v_n in (10, 25, 50, 100) then
    insert into notifications (profile_id, kind, title, body, ref_id)
    values (v_owner, 'reward', '🏆 ' || v_name || ' ' || v_n || '번째 완주',
      '꾸준함이 기록이에요 — ' || v_n || '번의 러닝 하이', new.booking_id);
  end if;

  return new;
end $$;

-- 완주로 '전이'할 때만 발화 (insert와 update의 OLD 유무가 달라 트리거 2개로 분리)
drop trigger if exists trg_dog_records_ins on runs;
create trigger trg_dog_records_ins after insert on runs
  for each row when (new.end_reason = 'completed') execute function _detect_dog_records();
drop trigger if exists trg_dog_records_upd on runs;
create trigger trg_dog_records_upd after update on runs
  for each row when (old.end_reason is distinct from 'completed' and new.end_reason = 'completed')
  execute function _detect_dog_records();

comment on function _detect_dog_records is
  '강아지 기록 감지 (0034) — 페이스 경신·누적 km·n번째 완주 → reward 알림 (P3 기록 골드)';
