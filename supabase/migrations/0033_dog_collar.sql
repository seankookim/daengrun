-- ═══ 0033: 강아지 칼라 컬러 (P1 퍼스널라이즈 — Sean 확정 컬러 리바이탈라이즈 1순위) ═══
-- 보호자가 강아지마다 '칼라(목줄) 컬러'를 고른다 — 아바타 링·일정 카드 도트·(후속) 피드 트레이스가
-- 그 강아지의 색으로. 저장은 팔레트 키 (hex는 앱 theme.collarColors가 단일 소스 — 색 보정을
-- 마이그레이션 없이 할 수 있게 키-값 분리). null = 기본 (볼트 브랜드 톤).

alter table dogs add column if not exists collar text
  check (collar is null or collar in ('tangerine', 'sky', 'rose', 'violet', 'gold', 'teal', 'moss', 'berry'));

comment on column dogs.collar is
  '칼라 컬러 키 (0033) — 앱 theme.collarColors 매핑. null = 기본. 쓰기는 기존 dogs RLS(소유자)로 충분';
