# SESSION HANDOFF — 2026-08-04d (0055/0056 + 수익·D-day·벨 실데이터 + W4 구현 WIP)

## ⓪ STATUS — 2026-08-04 세션 최종 (전 트랙 완결)
- W4 히어로 P0/P1 전부 수리 완료 → **fitness.tsx 반입·커밋 b0daea2** (재검 전항목 PASS + 기기 tsc). WIP 파일은 흡수·제거. 남은 것 = Sean 기기 스모크(모프·레일·로딩/빈/오류 3상태·fontScale).
- **안무 랩 완성** — docs/labs/choreography-lab.html (4모션 + 트리거 제안, 클릭 재생). Sean 채택 번호 + 트리거 승인 대기 → 채택분 RN 구현이 다음 프론트 슬라이스.
- 수익·D-day·벨 배치 = 567cdb7. 이 세션 커밋 스택: 0ed2709(0054, push됨) → 725bf78(0055/0056) → 567cdb7 → b0daea2 → [랩 커밋]. push 대기분 §7.

Companion docs: `docs/audit-2026-08-02.md` · precision-director skill (installed, READ AND FOLLOW) · **`docs/labs/fitness-hero-lab.html`** (W4 랩 — repo에 저장, /tmp 소멸 문제 해결).
Opener for next session: **"read docs/session-handoff.md fully, then continue"**.

## 1. Goal & current state (2026-08-04d 추가분)
- **수익·D-day·벨 배지 실데이터: DONE (이번 커밋)** — 스카웃 판정 전 항목 client-only (0057 불필요:
  누적=기존 my_ledger_total RPC · notifications는 read_at+부분 인덱스+RLS 기성). api.ts: kstMonthStartMs·
  fetchLedgerMonth(월 유계라 2000행 캡 무관, 주간 카드와 동일 net 식)·fetchUnreadCount·fetchMyBookings에
  scheduledAt. runner home: 이번 달·누적 행 + 오늘 확보→**오늘 확보·예정**(추정 혼입 정직화) + todayLabel
  KST 고정(기기 TZ 버그) + 벨 닷 신설(실카운트). owner home: **무조건 켜지던 벨 닷 = 조작 지표 제거**(unread>0만) +
  liveNext 정렬 버그 수리(안정정렬이 '가장 먼 미래'를 NEXT RUN으로 — 미래 우선·임박 순, 과거 6h 유예 뒤로) +
  D-day 칩(KST 캘린더 diff, 과거/결측이면 칩 없음 — 가짜 카운트다운 금지) + demoImminent 죽은 임포트 제거 +
  티켓 헤더 오버플로 가드. store.ts: Booking.scheduledAt?.
- **W4 히어로 구현: WIP 파킹** (⓪ 참조 — P0 수리 후 반입). **안무 랩: 미착수** (⓪-4).

## 1b. (이전 배치 기록)
daengrun (도그스하이) — RN/Expo + Supabase dog-running marketplace, 반포 pilot. 이 세션 (0054 배치에 이어 같은 날 2·3차):
- **0054 배치: 원격 반영 완료** [Sean 확인] — db push 0051~0054 + transition-booking deploy + git push (0ed2709). 스모크는 §7.
- **0055 definer 봉인 + 8+2 신인 슬롯: DONE** [verified-now: 하네스 224/224] — 전 public security-definer 함수(116개) `search_path = public, pg_temp` 일괄 ALTER (동적 sweep, 멱등, 소유자 가드) + runners_available_for 상위8 경험 + 잔여 최소경험 2 슬롯 (신인 콜드스타트 완화 — 한계는 파일 주석·§9 참조). 적대 리뷰어가 0054 P2 섀도잉 공격을 3개 게이트에서 재실행 → 전부 차단 확인.
- **0056 거절 원장: DONE** — booking_declines(RLS self-read only, 기록자는 엣지 fn service-role fail-open upsert) + marketplace_open_requests 뷰에 거절자 제외 술어 (17컬럼 byte-identical 유지). 지명 거절 → 오픈 풀 재등장 버그의 서버 근치 (세션 declinedIds는 낙관 레이어로 유지, **오픈 레그만** — 지명 레그까지 거르면 재지명이 썩는 P1이었음, 수리됨).
- **클라 정직성**: schedule.tsx stFor 배지(불발/확인 중) + no_show·incident_review 시트 = 액션 없는 정직 한 줄(취소는 전이상 불법 → 죽은 버튼 제거) + '응답 대기' 칩 모순 제거. runner home filterDeclined directed 예외.
- **W4 필름스트립 히어로 랩: 전달됨, Sean 선택 대기** — docs/labs/fitness-hero-lab.html, 4해석(①시네 스트립 ②콘택트 시트 ③파노라마 릴 ④티켓 하이브리드), 프레임 내 스크롤 = 모프 재생(owner-home 크로스페이드 패턴), 실필드 바인딩만(fetchRecentMoments·fetchFitness). **fitness.tsx는 아직 스웜프 그린(#0F1D13·cream·volt·tang) — 구현 = 라일락 리페인트 겸함.**
- 하네스 **224케이스** (97 V12/V12b 8+2 핀 재작성 + 98_hardening: H1 definer 전수봉인 상시핀·H2~H7 거절 원장). 뮤테이션으로 핀 실효성 검증(구현 되돌리면 정확히 해당 핀만 터짐). upgrade_check 'hard' 3필터 반영.
- 이 세션 커밋: 0ed2709(0054 배치, push됨) + [이번 커밋 — 0055/0056 배치].

## 2. Standing doctrines (Sean's invariants)
- 이전 문서 전부 유효 (mockup lab → 번호 선택 · precision-director boss-verify · 마이그레이션 5-agent + 하네스 · commit gate tsc+check-rpc · 라일락 토큰·coral-text law·폰트 법·≥12pt·큰 버튼·no dead buttons·no fabricated data · 홈=루트).
- **SQL 보안 법(확립)**: 새 definer 함수는 본문에 `set search_path = public, pg_temp` 필수 — ALTER는 create or replace에 리셋됨(실측). 98 H1이 상시 감시(빠뜨리면 하네스 즉사). add constraint는 가드 DDL. 당사자 게이트 뒤 상태 게이트(무료 draft 프로브 오라클 차단). 반환은 평면 화이트리스트.
- 표시 어휘가 서버 상태를 뭉갤 땐 rawStatus로 게이트/배지 (STATUS_MAP 폴백 신뢰 금지).

## 3. Working-relationship norms
- 이전 문서 유효. 추가: Sean이 스킬 2종 설치(**impeccable** = repo .claude/skills, 크래프트/배치 검수 루프 · **ghaida/intent** = 전역 설치라 브리지 밖, 소스는 github에서 참조 가능 — UX 전략/카피/엣지상태). 디자인 작업에 둘 다 적용할 것. 판단 위임 시("go ahead") 감독이 결정하고 근거 남김 — 제품 콜 3건(8+2·불발/확인중 카피·rotation 보류) 이 세션에서 그렇게 처리.

## 4. Decision log (이번 배치)
- **8+2** (limit-10 기아 → 상위8 + 잔여 최소경험 2, 결정적, 컬럼 추가 없음). 한계 정직 기록: 신인석은 전역 최소 2명 고정 — 로테이션 필요 시 rookies 타이브레이크 `md5(profile_id||p_booking)` 한 줄 (V12 오라클 동기 수정 필요).
- **sweep 소유자 가드** `pg_get_userbyid(proowner)=current_user` — 원격 대시보드 생성 함수로 push가 죽는 것 방지. 대가: 그런 함수는 미봉인으로 남고 로컬 핀은 못 본다 → §7 원격 감사 쿼리로 보완.
- **거절 원장 기록자 = 엣지 fn** (클라 RPC 없음 — 유일한 거절 문이 지명 거절뿐이라). fail-open(로그 실패해도 거절 성공 — 최악이 0056 이전 현상). set() 후 log 순서 = logged-but-not-reverted 불가능.
- **직접 재지명은 거절 무시** (제품 콜: 보호자가 콕 집으면 다시 물어봐도 된다) — H5 핀. declinedIds가 directed 레그를 거르면 이 경로가 죽는다 → r.directed 예외 (리뷰 P1).
- no_show(어느 마이그레이션도 안 씀 — enum만 존재)·incident_review(0045가 씀): 취소·변경 전이 불법(→refund_pending만) → 시트 액션 0 + 배지 불발/확인 중.
- 뷰는 create or replace로만 (컬럼 변경 불가 제약이 grant 보존을 강제 — DROP 금지).

## 5. Architecture & contracts (DO-NOT-REFACTOR 추가분)
- 이전 문서 유효. 추가: **98 H1 = definer 전수 pg_temp 상시 불변** (prokind='f' 한정 — definer 프로시저 생기면 sweep과 핀 동시 확장). 97 t_av_* 헬퍼는 98에서도 사용 가능(영속). 97은 runners.online 전역 mutate — 98이 그 뒤에 돈다는 가정 주의. V12b rank-9 드롭 단언은 이 무대의 등급 분포 전제(파일 주석 참조).
- booking_declines: 단조 증가(정리 경로 없음 — 행 40바이트, 방치 허용) · runner_profile_id 정책 컬럼 인덱스 없음(원장 직접 읽는 UI 생기면 추가).
- 거절 이중탭 = 403 (재독 시 runner_id null → isRunner false) — 상태는 이미 정상, 기존 동작 [R1 info].

## 6. File map (이번 배치 surface)
- `supabase/migrations/0055_definer_hardening.sql` · `0056_decline_log.sql` — NEW.
- `supabase/tests/97_availability_suite.sql`(V12/V12b 재작성) · `98_hardening_suite.sql`(NEW) · `harness.sh`(+98) · `upgrade_check.sh`(+98·hard 3필터).
- `supabase/functions/transition-booking/index.ts` — runner_decline에 거절 박제 블록. **재배포 필요, 0056 push 이후 또는 동시** (fail-open이라 순서 어겨도 안 죽지만 그동안 원장 미기록).
- `app/app/owner/schedule.tsx` — stFor·불발/확인중 시트 한 줄·칩 모순 제거. `app/app/runner/home.tsx` — filterDeclined directed 예외.
- `docs/labs/fitness-hero-lab.html` — W4 랩 (Sean 선택 대기).

## 7. Pending on Sean's side (ordered)
1. `supabase db push` — 0055·0056 (하네스 224/224 + UPGRADE OK).
2. `supabase functions deploy transition-booking` — 거절 박제 활성화 (0056 push 후).
3. push 후 SQL 에디터에서 원격 definer 봉인 감사 (sweep 소유자 가드의 사각 확인):
   `select p.oid::regprocedure from pg_proc p where p.pronamespace='public'::regnamespace and p.prosecdef and coalesce(array_to_string(p.proconfig,','),'') not like '%pg_temp%';`
   → 0행이어야 함. 행이 나오면 소유자 다른 함수 — 목록 들고 다음 세션.
4. `git push` (redesign-v4).
5. Device smoke (0054 배치 포함 누적): 매칭 로스터(가용만·빈/오류/재시도·신인 하단 노출), 러너 변경, 일정 시트 상태 매트릭스(+불발/확인중 배지), 수락 409 시각 지목, 지명 거절 → 오픈 풀 미재등장(재시작 후에도) → 직접 재지명 수신.
6. ~~W4 랩 번호 선택~~ → 선택됨: "① + ③ 이미지 디스플레이, 체력 나이 강조" — 구현 WIP는 ⓪.
7. 기기 스모크 추가분: 러너 홈 이번 달·누적 실값 + 오늘 확보·예정 라벨 · 오너 홈 벨 닷(안 읽은 알림 없으면 꺼짐!) ·
   NEXT RUN 티켓이 '가장 임박한' 건인지 + D-day 칩 · 알림 읽음 후 닷 소등.

## 8. Known bugs / gotchas
- 이전 문서 유효 (5pm 미스터리는 deploy 후 409가 자백 예정 · roster 폰트 클리핑 [기기] · .fuse_hidden 무시).
- no_show는 쓰는 코드가 없음(“불발” 배지는 미래 대비). refund_pending 탈출 전이 없음(진짜 종착역 — 제품상 맞는지 Sean 한 번 생각해볼 것).
- matching.tsx 로스터 신인석: matchFor 점수는 여전히 경험 위주 — 신인이 보이지만 하단(의도). AI 1순위엔 영향 없음.

## 9. Ideas discussed, not built
- 신인석 로테이션 (md5 타이브레이크 — §4) · booking_declines 정리 스윕/인덱스 (필요 시) · no_show/incident 전이 확장 여부 · 사진 비공개 버킷 §3b · 클럽 홈 안무 4종 기기 리뷰 · 러너 월간 수익/D-day/미확인 배지 RPC · request_runner에 '이 러너는 이 건을 거절했었어요' 안내(제품 콜 필요 — 현재는 무신호가 의도).
- W4 구현 (랩 선택 후): fitness.tsx 라일락 리페인트 + 선택 히어로 + 8주 바 dataviz 규격(선택 라벨만·검증 팔레트 #9787DC/#E45F41) + impeccable craft-floor·intent fortify 적용.

## 10. Next 1–3 steps
1. [read-only] §7 확인 (push·deploy·감사 쿼리 0행·랩 번호).
2. [local-edit, big] W4 선택안 구현 — fitness.tsx 전면 (리페인트+히어로+모프). frontend-design + impeccable(shape→craft-floor→batched inspect) + intent(journey/fortify) + precision-director. 기기 스크린샷 루프.
3. [design] 안무 4종 기기 리뷰 or 러너 수익 RPC (작음, 5-agent 불요할 수도 — 판단).

## 11. Verification commands
Read-only: `git log --oneline -6` · `git status --short` · device tsc `cd app && ./node_modules/.bin/tsc --noEmit` · `node scripts/check-rpc-contracts.mjs` · container `cd /tmp/daengrun/supabase/tests && runuser -u postgres -- bash harness.sh 2>&1 | tail -3` (expect 224/224).
Expensive/destructive (Sean only): db push, functions deploy, git push.
