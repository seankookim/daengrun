-- Local dev seed — mirrors the mock world (초코, 김민준 등).
-- 로컬 전용: supabase db reset 시 적용. 프로덕션에 흘리지 말 것.

-- auth users (local only; passwords unusable)
insert into auth.users (id, email, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000001', 'owner@daengrun.dev', '{"name":"초코 보호자"}'),
  ('00000000-0000-0000-0000-000000000002', 'minjun@daengrun.dev', '{"name":"김민준"}'),
  ('00000000-0000-0000-0000-000000000003', 'seoyeon@daengrun.dev', '{"name":"이서연"}')
on conflict do nothing;

insert into profiles (id, role, name, district) values
  ('00000000-0000-0000-0000-000000000001', 'owner', '초코 보호자', '성수동'),
  ('00000000-0000-0000-0000-000000000002', 'runner', '김민준', '성수동'),
  ('00000000-0000-0000-0000-000000000003', 'runner', '이서연', '성수동');

insert into dogs (id, owner_id, name, breed, weight_kg, neutered, memo, weekly_goal_km, fitness_age, cumulative_km, streak_days)
values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001',
  '초코', '웰시코기', 11, true,
  '겁이 없어서 큰 개한테도 달려듭니다. 자전거를 보면 짖어요. 물은 30분마다. 오른쪽 뒷다리 슬개골 주의.',
  15, 1.8, 86.2, 12);

insert into runners (profile_id, tier, funnel_step, avg_pace_sec_per_km, identity_verified, insurance_active, trainer_certified, total_runs, total_km, compliance_pct, respond_rate_pct, commission_rate)
values
  ('00000000-0000-0000-0000-000000000002', 'certified', 'certified', 410, true, true, false, 214, 1182, 97, 98, 0.20),
  ('00000000-0000-0000-0000-000000000003', 'certified', 'certified', 430, true, true, true, 89, 512, 94, 95, 0.20);

insert into addresses (owner_id, label, addr, detail, lat, lng, is_default) values
  ('00000000-0000-0000-0000-000000000001', '서울숲 2번 출입구', '성동구 뚝섬로 273', '출입구 옆 벤치에서 만나요', 37.5443, 127.0398, true);

insert into routes (name, area, km, terrain, tags, features, checked_at) values
  ('서울숲 순환 코스', '성수동', 5, '흙길 70%', '{중형견 최적,그늘 많음,식수대 2곳}',
   '[{"g":"❋","label":"공원"},{"g":"⏚","label":"흙길"},{"g":"♒","label":"식수대 2곳"},{"g":"☂","label":"그늘"}]', '2026-07-18'),
  ('뚝섬 리버뷰 코스', '뚝섬한강공원', 5, '포장 60%', '{리버뷰,평지,야간 조명}',
   '[{"g":"♒","label":"리버뷰"},{"g":"—","label":"평지"},{"g":"☀","label":"야간 조명"}]', '2026-07-20'),
  ('서울숲 숲길 3km', '성수동', 3, '흙길 90%', '{소형견·시니어,완만,조용함}',
   '[{"g":"❋","label":"숲길"},{"g":"⏚","label":"흙길 90%"}]', '2026-07-15'),
  ('뚝섬–잠원 7km', '한강', 7, '포장 80%', '{고에너지견,장거리,한강 시리즈}',
   '[{"g":"♒","label":"리버뷰"},{"g":"✦","label":"에픽 코스"}]', '2026-07-19');

-- ═══ [로컬 전용] 호스티드 패리티 권한 — 신형 CLI 로컬 스택은 API 롤에 CRUD를 기본 부여하지
-- 않는다 (호스티드/원격은 구 기본값 유지). 보안 모델은 RLS가 담당 (X10 독트린) — grant 부재에
-- 기대는 봉인은 없으므로 안전. seed.sql은 supabase db reset(로컬)에서만 실행된다.
grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to anon, authenticated, service_role;
grant usage, select on all sequences in schema public to anon, authenticated, service_role;
alter default privileges in schema public grant select, insert, update, delete on tables to anon, authenticated, service_role;
alter default privileges in schema public grant usage, select on sequences to anon, authenticated, service_role;
-- 함수 실행권: 호스티드는 기본 권한이 service_role에 직접 execute를 부여해 마이그레이션의
-- revoke(public/anon/authenticated) 후에도 service_role 경로가 산다 — 로컬 패리티.
grant execute on all functions in schema public to service_role;
alter default privileges in schema public grant execute on functions to service_role;
