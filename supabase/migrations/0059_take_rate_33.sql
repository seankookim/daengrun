-- ═══ 0059 — 테이크레이트 33% (Sean 결정 2026-08-05, 핸드오프 §2g) ═══
-- 왜 별도 마이그레이션: 0057:474가 예약해 둔 바로 그 변경 — commission_rate가 서버 전용(K-1)이
--   된 뒤에야 요율이 자문이 아니라 사실이 된다. 보안 슬라이스와 분리해, 정산 산술 변경이
--   보안 회귀를 가리지 못하게 한다.
-- 정책: 일괄 33%. 티어 연동 요율은 실재하는 사다리가 없다(cert-funnel spec Q7 — 3개 사다리 공존,
--   어느 것도 commission_rate와 실제로 연결돼 있지 않다).
-- ⚠ 소급 주의: bookings에 예약 시점 요율 스냅샷이 없어 요율 변경은 진행 중 예약에 소급된다.
--   실주자 0명인 지금만 무해한 패턴. PG 런칭 전 스냅샷 컬럼(commission_rate_at_booking) +
--   고지 장치(약관규제법 — 기존 러너 불리 변경은 사전 개별 고지) 필수. 이 파일을 복붙해
--   다음 요율 변경을 하면 안 된다.
-- 상호작용 검증: 0057 §6 _guard_runner_cols는 current_user in ('authenticated','anon')만 차단 —
--   마이그레이션(postgres)·db push(postgres)는 통과. numeric(4,3)에 0.330 정확 저장.

alter table runners alter column commission_rate set default 0.33;

update runners set commission_rate = 0.33;  -- 기존 행 일괄 평탄화 (업그레이드 경로에서 98 H8(c)가 핀)

comment on column runners.commission_rate is
  '플랫폼 수수료율 — 일괄 0.33 (2026-08-05 Sean 결정, 0059). 클라 쓰기 금지(0057 §6 서버 전용). 티어 연동 없음.';
