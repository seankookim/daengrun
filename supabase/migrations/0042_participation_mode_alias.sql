-- ═══ 0042: participation_mode 물리 별칭 — 스펙 이름과 스키마 이름의 간극 봉합 ═══
-- 사건: 원격 검증 쿼리가 스펙(v3.3)의 논리명 participation_mode로 조회 → 물리 컬럼은 custody
-- (0040 설계 각서 7행: 개명은 정리 슬라이스로 유예) → 'column does not exist'로 정상 적용 DB가
-- 실패 판정됨. 두 이름 = 두 진실의 소형 재발 — 스펙에서 생성된 쿼리가 그대로 돌도록 봉합한다.
--
-- 해법: GENERATED 컬럼 (custody의 읽기 전용 물리 별칭). v1 RPC들의 custody 참조는 그대로 유효,
-- 쓰기는 여전히 custody로만 (GENERATED는 삽입/수정 불가 — 두 진실이 될 수 없음).
-- 진짜 개명(custody 폐기)은 v1 로직 교체가 끝나는 정리 슬라이스에서.

alter table session_dogs
  add column if not exists participation_mode text
  generated always as (custody) stored;

comment on column session_dogs.participation_mode is
  '스펙 v3.3 논리명의 물리 별칭 (= custody, GENERATED 읽기 전용) — 정리 슬라이스에서 custody를 대체 예정';
comment on column session_dogs.custody is
  '참여 모드 원본 컬럼 (owner_handled|runner_delegated) — participation_mode는 이 컬럼의 별칭';
