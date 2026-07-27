# 세션 핸드오프 — 2026-07-27

새 세션 시작 시: 이 파일 + docs/mock-status.md + docs/fake-inventory.md 를 먼저 읽을 것.

## 운영 원칙 (불변)
- **정직 원칙**: 목업/데모 폴백/가짜 숫자 금지. 실패는 실패로 Alert. 챌린지 탭·가짜 지도 점 등 실시스템 없는 표면 금지.
- **빌드 규칙**: 패키지 설치 → 캐시 클리어 재시작. app.json/플러그인 변경 → `npx expo prebuild -p ios --clean` + `run:ios`. JS만 → r.
- tsc 통과 후 커밋. 커밋은 한국어 상세 메시지. Sean이 push/deploy (샌드박스에 토큰 없음).
- 네이티브 모듈은 전부 lazy-require. SERVICE_ROLE_KEY는 루트 .env만.

## 디자인 언어 (현재)
- 배경 #F8F7F3 (화이트 베이스), 거터 12px 전역, 헤어라인 #DEDACB, dim #6E6C5E.
- 라디우스: 카드 24 이하 (32→24 스윕 완료), 그림자 아키텍처럴 (blur/offset 절반).
- 화면당 다크 앵커 1개 (#132117 + volt). 파스텔 팔레트 ['#d9f294','#bfd8aa','#ffc9b2','#f2d992'].
- 러너 선택 = 2층 컴포지터 캐러셀 (오버레이가 액티브 카드, matching.tsx — 구조 건드리지 말 것).

## 최근 완성 (이번 세션)
- find-now: 홈 히어로(상태연동 레이더 백드롭) → 프리필 시트 → 오픈 브로드캐스트 → radar.tsx (코랄 리플, 실가용 러너, realtime+폴링 수락 감지).
- available_runners 뷰(0015): 러닝 중 러너 제외. transition-booking 원자 선점 수락.
- liveNext 우선순위 정렬 (active>handoff>confirmed>pending) — 스테일 매칭이 확정 위젯 가리던 버그 수정.
- 요청 화면 티켓 리디자인, 마이 다크 스탯 카드, 커뮤니티 피드|러너 후기 탭, 샵 정직 폴리시.
- wipe-test-data.mjs: 신규 테이블 포함, 시드 러너 스탯 보존.

## Sean 쪽 미완 (확인할 것)
- `npx supabase db push` (0015) + `functions deploy transition-booking` 실행 여부.
- `npx expo prebuild -p ios --clean` + `run:ios` 1회 (카메라 권한 + Live Activity 위젯).
- 클린 슬레이트: `node scripts/wipe-test-data.mjs --yes`.

## 다음 우선순위 (Sean 합의됨)
1. **홈 생기 패스**: 숫자/네온 → 실사진. 강아지 프로필 사진을 히어로에, '최근 순간' 러닝 사진 스트립 (feed/report 사진 재사용). 스톡/가짜 이미지 금지.
2. **러너 장비 v1** (Sean의 RPG 아이디어): runner_gear 테이블(kind/label/photo/verified_at), 캐러셀·프로필 장비 배지, 인계 체크리스트(미트업 플로우), 사진 인증(인증샷 패턴). 가드레일: 매칭 점수는 응답/경험/페이스 유지 — 장비는 배지 + 소폭 캡된 부스트만 (pay-to-win 금지). 구매 연동은 샵 실화 후.
3. **샵 셸 확장**: 10개 목업 스크린 참고 (PDP/카트/필터/브랜드관…) — 실 SKU 생기기 전까지 최소 셸만. 첫 고객은 러너 (장비 경제와 연결).

## 외부 블로커
- Apple Developer $99 → 푸시(find-now 응답속도), TestFlight, 보호자 LA.
- 사업자등록 → Toss PG (docs/payments.md).
