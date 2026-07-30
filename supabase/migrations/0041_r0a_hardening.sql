-- ═══ 0041: R0A 하드닝 — 동기화 메커니즘 교정 + 멱등 범위 (비평 6라운드 반영) ═══
-- 0040이 테스트 DB에 이미 적용됐을 수 있으므로 파일 수정 대신 후속 마이그레이션.
--
-- ① 원장 poke 격리 해제: '원장 insert가 정산 tx의 마지막 쓰기'라는 순서 우연에 의존하던
--    동기화를 폐기하고, 부킹 상태 변경 트리거를 **커밋 시점 평가(deferred constraint trigger)**로
--    전환 — 트랜잭션 안에서 몇 번을 어떤 순서로 쓰든, 커밋 순간의 최종 진실로 축을 재계산한다.
--    (0040의 즉시 poke + 원장 poke는 임시 호환 훅이었음을 인정하고 제거)
-- ② payment_attempts 멱등 키 범위: 전역 unique → (session_dog_id, kind, idempotency_key).
--    같은 클라이언트 재시도는 같은 결과, 무관한 두 강아지가 우연히 같은 키를 써도 안전.
--
-- 참고: 활성 시도 부분 유니크(한 세션·강아지당 활성 1행)는 R1에서 새 시도 플로우와 함께 —
-- v1의 unique(session_id,dog_id)와 ON CONFLICT 의존이 살아 있는 동안은 변경하지 않는다.

-- ---------- ① 커밋 시점 축 동기화 ----------
drop trigger if exists club_v2_axes_poke on bookings;
drop trigger if exists club_v2_ledger_poke on ledger_items;
drop function if exists _club_v2_ledger_poke_tg();

-- constraint trigger는 AFTER row-level만 허용 — 기존 poke 함수 재사용
create constraint trigger club_v2_axes_poke
  after update of status on bookings
  deferrable initially deferred
  for each row when (new.club_session_id is not null)
  execute function _club_v2_axes_poke_tg();

-- ---------- ② 멱등 키 범위 ----------
alter table payment_attempts alter column session_dog_id set not null;
alter table payment_attempts drop constraint if exists payment_attempts_idempotency_key_key;
create unique index if not exists payment_attempts_idem_uni
  on payment_attempts (session_dog_id, kind, idempotency_key)
  where idempotency_key is not null;

comment on trigger club_v2_axes_poke on bookings is
  'R0A 하드닝(0041): 커밋 시점 축 재동기화 — 쓰기 순서 무관, 최종 진실 기준';
