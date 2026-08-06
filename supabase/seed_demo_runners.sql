-- 데모 러너 3명 — 실백엔드 행 (로그인 불가 계정, 공급측 데모용).
-- SQL Editor에서 실행. 재실행 안전 (on conflict).
-- 주의: 이들은 앱이 없으므로 지명 요청에 응답하지 못함 — 전체 루프는 본인 지명 또는 오픈 매칭으로.

insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'minjun@daengrun.demo', '', now(), '{"provider":"email","providers":["email"]}', '{"name":"김민준"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'seoyeon@daengrun.demo', '', now(), '{"provider":"email","providers":["email"]}', '{"name":"이서연"}', now(), now()),
  ('00000000-0000-0000-0000-000000000000', '20000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'taeo@daengrun.demo', '', now(), '{"provider":"email","providers":["email"]}', '{"name":"박태오"}', now(), now())
on conflict (id) do nothing;

insert into profiles (id, role, name, district) values
  ('20000000-0000-0000-0000-000000000001', 'runner', '김민준', '성수동'),
  ('20000000-0000-0000-0000-000000000002', 'runner', '이서연', '성수동'),
  ('20000000-0000-0000-0000-000000000003', 'runner', '박태오', '뚝섬')
on conflict (id) do update set name = excluded.name, role = excluded.role, district = excluded.district;

insert into runners (profile_id, tier, funnel_step, avg_pace_sec_per_km, identity_verified, insurance_active, trainer_certified, total_runs, total_km, compliance_pct, respond_rate_pct, commission_rate, online)
values
  ('20000000-0000-0000-0000-000000000001', 'veteran',   'certified', 410, true, true, false, 214, 1182, 97, 98, 0.33, true),
  ('20000000-0000-0000-0000-000000000002', 'certified', 'certified', 430, true, true, true,   89,  512, 94, 95, 0.33, true),
  ('20000000-0000-0000-0000-000000000003', 'certified', 'certified', 400, true, true, false,  78,  455, 88, 90, 0.33, true)
on conflict (profile_id) do update set online = true, tier = excluded.tier;

insert into runner_availability_rules (runner_id, weekday, start_min, end_min)
select r.id, wd, 360, 1320
from (values
  ('20000000-0000-0000-0000-000000000001'::uuid),
  ('20000000-0000-0000-0000-000000000002'::uuid),
  ('20000000-0000-0000-0000-000000000003'::uuid)
) as r(id), generate_series(0, 6) as wd
on conflict do nothing;

insert into runner_booking_rules (runner_id) values
  ('20000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002'),
  ('20000000-0000-0000-0000-000000000003')
on conflict do nothing;
