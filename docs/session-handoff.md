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

## 샵 목업 10종 — 텍스트 전사 (원본 이미지는 새 세션에 재업로드 권장)
공통: 화이트 베이스, 헤어라인 카드, volt 액센트, 다크 포레스트 앵커, 제품사진은 카키/그린 톤.
1. **주문/배송 추적**: 주문번호+주문일 그레이 헤더카드 → '배송 중' 4단계 스텝퍼(주문접수→상품준비→배송중→배송완료, 지난 단계 volt 원형아이콘+라임 연결선, 현재 단계 다크 링) → 배송업체(CJ대한통운)/송장번호 + '배송조회' 아웃라인 버튼 → 상품 라인아이템(썸네일+이름+가격+수량) → 배송지 블록(이름/주소/동호수/전화).
2. **찜한 상품/최근 본 상품**: 섹션 2개, 각 3열 그리드, 우상단 '전체보기 ›'. 카드 = 제품사진(♥ 빨강 우상단)+이름+₩가격.
3. **샵 메인**: 검색바 → 다크 포레스트 히어로 배너('초코를 위한 건강한 라이프 스타일' + 강아지 사진 + volt '지금 쇼핑하기 →' 필) → 카테고리 아이콘 행(사료/간식·산책용품·의류/액세서리·건강/영양·장난감·전체보기) → 추천 상품 3열.
4. **브랜드관**: 세로 브랜드 카드 3개(초코펫 다크그린+강아지 사진 / PUPPY PLUS 라이트+로프토이 / NATURE DOG 산 풍경), 각 태그라인 + '보러가기 ›'.
5. **검색 결과**: 검색어 칩('하네스'), "'하네스' 검색 결과 18개", 2열 그리드: 사진+NEW 배지, 이름, ₩가격, ★평점(리뷰수), 우하단 volt 장바구니 미니버튼.
6. **필터 시트**: 초기화/적용(volt) 헤더, 카테고리 칩(선택=다크), 가격대 듀얼 슬라이더(₩0–50,000+, volt 트랙), 브랜드 체크리스트(전체/초코펫/파피플러스/네이처독).
7. **카테고리 허브**: 2열 대형 타일(사료/간식, 산책용품, 의류/액세서리, 건강/영양, 장난감, 위생/케어 — 각 제품사진), 하단 와이드 '브랜드관' 타일.
8. **상품 상세(PDP)**: 이미지 캐러셀(1/4 도트) → 이름+BEST 배지, ★4.9(128)·구매 342 → ₩가격 크게 → 한줄 설명 → 특징 4칸 아이콘 그리드(고단백 28%/오메가3/저알러지/국내생산) → 배송 안내 행 → 하단 고정: ♥ + '장바구니 담기'(다크) + '바로 구매'(volt).
9. **장바구니**: 'N개의 상품'+전체 선택, 아이템 카드(volt 체크서클+썸네일+이름/옵션+₩+수량 스테퍼 −/1/+) → 배송비 ₩0(무료배송 적용) → 총 주문금액 크게 → volt '주문하기 (N)' 와이드 버튼.
10. **카테고리 목록(PLP)**: '사료/간식' 타이틀, '필터 ▾'/'추천순 ▾' 칩 행, 2열 그리드(사진/이름/₩/★리뷰/volt 카트버튼).

---
# 확장 컨텍스트 — 의사결정 로그·철학·아이디어 전체 (2026-07-27 심층 핸드오프)

## 제품 정체성 & 전략
- 댕런 = 반려견 **피트니스** 마켓플레이스. '산책 대행'(비포펫)이 아니라 '운동 결과'를 판다. 체력 나이·주간 km·페이스가 핵심 지표인 이유.
- 인센티브 경제는 **댕마일 단일 원장**(miles_ledger): 완주 +50 양측, 응가 보너스 +30, 드랍, 주간 TOP3 200/100/50 (pg_cron 월 00:10 KST).
- 매칭 철학: 하이브리드 — AI 추천(응답35/경험30/페이스35) + 지명 + 오픈 브로드캐스트. 추천은 핵심 기능, 절대 제거 금지 (한 번 실수로 사라졌다가 Sean이 잡아냄).

## Sean의 작업 스타일 (관계 규범)
- "항상 사용자 효과 최소화(less effort)" — 모든 UX 결정의 제1원칙. 원탭·프리필·자동화 선호, 단 결제 전 가격 노출은 필수(다크패턴 거부).
- 비주얼 피드백 루프: 스크린샷 → 정확한 불만 목록 → 수치 조정. "고백 가능(go-backable)" 변형 선호 — 토글로 비교하고 되돌림 (라임 스케줄 카드처럼 통째 스크랩도 함).
- 셀프서브 진단 요구: e2e.mjs / diag.mjs / wipe-test-data.mjs — "내가 수동으로 모든 시나리오 돌게 하지 마".
- 푸시백 환영: "feel free to push back" 반복. 근거 있는 반대(가짜 지도 점, 챌린지 탭, 풀 라디우스 카드)는 수용됨.

## 주요 의사결정 로그 (왜 그렇게 했나)
- **find-now 2탭**(시트 확인) > 1탭: 결제 동의 없는 과금은 다크패턴. CTA에 행동 명시("주변 러너 검색 시작 ➤"), '직접 설정 ›'로 커스텀 탈출구.
- **오픈 브로드캐스트 + 레이더** > 캐러셀 우선: 스피드가 본질. 캐러셀은 '직접 고를래요' 한 탭 뒤. 원자 선점(runner_id IS NULL 조건부 UPDATE)으로 동시 수락 해결.
- **가짜 지도 점 거부**: 러너 GPS는 러닝 중에만 존재. 레이더는 리플+실가용 리스트. 블립 각도/반경은 연출값 — 거리 라벨 절대 금지.
- **캐러셀 스태킹**: zIndex/정렬/형제 페인트 순서 전부 실패 → **2층 컴포지터**(비활성=ScrollView, 액티브=absoluteFill 오버레이, translateY=base-scrollY 동기, 동일 물리 커브 공유). 터치는 스크롤 레이어의 투명 액티브 카드가 받음(오버레이 pointerEvents none) — 드래그 스크롤 보존 위한 의도적 스펙 이탈.
- **포커스 연동 색 전환 제거**: 카드가 포커스 따라 다크로 바뀌는 건 "too abrupt" — 색은 랭크 고정(1순위만 다크), 포커스는 물리(스케일/틸트/그림자)로만 표현.
- **홈 라임 스케줄 카드 스크랩**: 모던 목업 적용했다가 원복. 원인 진단: 위젯이 사라진 게 아니라 스테일 matching 부킹이 confirmed를 가림 → liveNext 상태 우선순위 정렬로 해결. 교훈: "사라졌다"는 불만은 먼저 데이터 상태 의심.
- **테마 스턱 다크**: theme-context 기본값 'dark'가 홈만 어둡게 만든 근본 원인 → 'light' 통일. 나이트 러너 다크 테마는 전 화면 완성 후 복귀 예정.
- **덱 클램프 지오메트리**: STEP=260 고정 스크롤 트래블, 이웃은 translateY로 액티브 곁 클램프(위 140px 피크/아래 30px 턱). 반투명 이웃 뒤 비침 방지 위해 2칸 위 카드 완전 은닉. 엣지 힌지 rotateX는 origin 에뮬레이션(translate→rotate→역translate, ±cardH/2 보간).
- **요청 화면**: 거리 3/5/7 프리셋 채택(임의 km은 find-now 스테퍼에 잔존, 리북 4km는 하이라이트 안 됨 — 알려진 트레이드오프). 요금상세 카드→한줄 (티켓이 총액 소유).
- **샵 정직 게이팅**: 하드코딩 '12.4km·4,900P' 같은 가짜 숫자 발견 즉시 은퇴. 목업 알럿도 '준비 중'으로 정직하게.

## 러너 장비 경제 (Sean 아이디어 — 다음 빅 피처, 상세)
- 컨셉: 러너 = 게임 캐릭터, 장비 = 신뢰 시그널 (마법사의 지팡이). 인증 리드줄/의류/물병/프리미엄 간식/바디캠.
- **전략적 통찰: 샵의 첫 고객은 러너다** — 장비가 지명율을 올리면 러너가 산다. 공급측 커머스로 콜드스타트 해결.
- 두 가지 '장착' 경로: (a) 앱 구매 → 자동 인증 (샵 실화 후), (b) 사진 인증 (인증샷 패턴, 지금 구현 가능).
- 가드레일: 매칭 점수(응답/경험/페이스)는 불변. 장비 = 배지 레이어 + 캡된 소폭 부스트. pay-to-win은 신뢰 파괴.
- 미트업 인계 체크리스트로 장비 전달 확인 (리드줄 교체·물·간식 양측 확인).
- 프로모 포인트: 구매→사용 등록→포인트 지급 아이디어 있음 (댕마일과 통합 검토).

## 홈 생기 패스 (다음 작업 상세)
- 문제: "too numbers and text… weird semi neon non humane" — 링 히어로가 차갑고 데이터 터미널 같음.
- 해법 방향(합의): 실사진만 사용 — 강아지 프로필 사진을 히어로 요소로, '최근 순간' 스트립(run_photos/feed 재사용). 스톡 이미지 금지.
- 레이더 백드롭은 상태 정직 모션: idle=브리딩 아크+실러너 블립, 검색 중=스윕 회전. 이 원칙 유지.

## 알려진 버그/특이점
- 시드 러너 6명은 앱이 없어 수락 불가 — 지명/수락 테스트는 s4kim2025(러너 겸) 또는 e2e 계정.
- 계정: s4kim2025@chadwickschool.org(주 테스트, 러너+보호자 겸), seankookim@uchicago.edu, e2e-owner/runner@daengrun.test.
- expo run:ios는 스테일 ios/ 재사용 — config plugin 변경 반영 안 됨 (prebuild --clean 필수). Metro 캐시는 패키지 설치 후 반드시 클리어.
- Live Activity 'widget' 함수는 문자열화됨 — 모듈 스코프 상수 참조 불가, 전부 함수 안에.
- PostgREST 임베드 FK명 모호성 조심 (feed_posts↔profiles 이중 경로 사례) — 신규 조인은 2-step 쿼리 선호.
- 레이더 10분 무응답 배너만 있음 — 자동 만료/환불 크론 미구현(백로그).
- 커뮤니티 후기 탭: 공개 리뷰 storefront 읽기는 0011 정책 — 실데이터 확인 필요(아직 실기기 검증 전).
- 마이 스탯 카드: fetchFitness의 totalKm/totalRuns 필드 존재 가정 (weekKm 폴백) — 실기기에서 값 확인할 것.

---
# 2026-07-28 리브랜드 — 댕런 → 도그스하이 (상세: docs/rebrand.md)
- 이름: **도그스하이 (DOGS HIGH)** — 러너스하이 5음절 미러. '하이' 시스템: 하이 포인트(구 댕마일, UI 라벨만)·하이 찍다. KIPRIS/핸들 스윕 미실시 — 커밋 전 필수.
- 토큰 리프레시 적용됨: forest #0F1D13 · volt #C6F542 · tang #FF5C3D · cream #F8F6F0 · clay #EDE8DA(NEW) · 헤어라인 #DCD6C4 단일 수렴 · 파스텔 4종 재보정. 위 '디자인 언어' 섹션의 구 hex는 이 표로 대체.
- 디스플레이 서체 Black Han Sans (displayFont.ts 지연 로드, 화면당 1회 규칙). **Sean: `cd app && npx expo install expo-font @expo-google-fonts/black-han-sans`**
- 앱 아이콘 = 옵션 A 풀블리드 스택 (assets/icon.png 교체 — prebuild 반영). app.json 표시명 변경, scheme/slug/bundleId는 KIPRIS 후.
- 마스코트: 크림 진돗개+volt 반다나 방향 (미구현) — "개를 칠하지 말고 입혀라". 실사진 구역 불가침.
- 보류: 인계 확인→하이파이브(안전 명료성), 최근 순간→오늘의 하이(정직성), 댕댕 스냅 애드온명, prototype/index.html.

---
# 세션 핸드오프 — 2026-07-28 (리브랜드 + 홈 개편 + 리스케줄 + 로직 감사)

새 세션 시작 시: 이 섹션 + docs/rebrand.md + docs/mock-status.md(하단 2026-07-28 항목) + project memory(project-status.md의 감사 백로그)를 먼저 읽을 것. 위 2026-07-27 섹션의 디자인 언어 수치는 이 섹션이 대체한다.

## 태그 규약
[V] = 이 세션에서 코드/DB로 검증됨 · [H] = 대화 기억 기반(재확인 권장) · [?] = 가정(신뢰 전 검증 필수)

## 1. 목표 & 현재 상태
- **리브랜드 댕런→도그스하이(DOGS HIGH)**: 완료 [V]. 근거: 러너스하이(5음절) 1:1 운율 미러 — 러닝 크루 타깃에 설명 없는 인용. '하이' 시스템: 하이 포인트(구 댕마일, UI 라벨만·DB 불변), 하이 찍다(동사). KIPRIS/앱스토어/@dogs.high/dogshigh.run 스윕 **미실시** — 대외 공개 전 필수 [V].
- **홈 개편**: 완료, Sean 스크린샷 루프 수차례 통과 [V]. 링 실사진 히어로 + 원라인 로테이팅 그리팅 + 랭킹 티커 + 미니 빕 칩 + 최근 순간 스트립.
- **리스케줄(0016)**: 전 구간 실동작 배포 확인(컬럼 존재 SQL로 검증) [V].
- **로직 감사**: 3면 병렬 감사 24건 발견 → 8건 크리티컬 수리 완료(배치 1: c5aabb2, 배치 2: a4b3344) [V], 잔여 16건 백로그(§9).
- **미신뢰 상태**: 배치 2의 서버 3함수는 코드만 커밋 — **Sean 배포 전** (§7). 배포 전 정산/취소/중복가드는 구버전으로 동작 중 [V].

## 2. 불변 원칙 (기존 유지 + 신규)
- 정직 원칙 전체 유지 (목업/가짜 숫자/데모 폴백 금지, 실패는 크게 실패).
- [신규] **확정 예약은 계약** — 시간 변경은 러너 수락제(제안 기반). 조용한 scheduled_at UPDATE 금지 [V].
- [신규] **인센티브는 완주만** — 마일/total_runs/드랍은 end_reason='completed'만. total_km은 실주행이라 항상 [V].
- [신규] **데모 거리는 정산 불가** — GPS 없으면 실예약 정산 차단 [V].
- [신규] **없는 데이터는 그리지 않는다** — 티커 ▲▼는 지난주 델타 RPC 생기기 전 금지 [V].
- 빌드/커밋 규칙 기존 그대로 (tsc 후 커밋·한국어 상세 메시지·Sean이 push/deploy). ⚠ tsc와 commit을 한 명령에 체이닝하지 말 것 — tsc 실패해도 커밋되는 사고 1회(da3eea7→ede545b로 수습) [V].

## 3. 디자인 언어 (2026-07-28 확정판 — 27일 수치 대체)
- 토큰 [V]: forest #0F1D13 · volt #C6F542 · tang #FF5C3D · cream #F8F6F0 · clay #EDE8DA(신규 웜 뉴트럴) · 헤어라인 #DCD6C4(3종 수렴) · dim #5B594A · voltDeep #7FA818 · 파스텔 DDF0A6/C3D9AE/FFCDB6/F2DA96. 거터 11(홈·설정 적용, 나머지 점진).
- 상태 컬러 [V]: 확정 그린 #5a7a3c / 대기 앰버×탠저린 #F59A43(틴트 #FDE8D0·fg #9D580A) / 완료 소프트 블루 #6E9BC5(틴트 #E3EEF8·fg #4A6E93). 일정 필터 칩 = 레일과 동일 스키마(칩이 범례).
- 서체 [V]: Black Han Sans = 화면 타이틀·히어로 카피·주요 CTA만. 숫자는 900 tabular(BHS 금지 — tabular 없음). displayFont.ts 지연 로드, 미설치 폴백. Sean이 expo install 실행함(리빌드 후 발현).
- 탭 헤더 표준 [V]: 좌측 BHS 30 + 서브 14.5 #49524a + 인셋 16. 탭 루트에 뒤로가기 금지.
- 타입 스케일 1.15배 전면 적용(41파일, 실험 커밋 0cc7ba4 — 통째 리버트 가능) [V]. Sean "i like the new font sizes" [H].
- 아이콘 = 옵션 A 풀블리드 저스티파이드 스택(도그스 55/하이 86, 플렉스 센터링) [V]. assets/icon.png 교체됨, 마스터 docs/brand/dogshigh-icon-a-1024.png. 보드 5종 docs/brand/board-*.html.

## 4. 의사결정 로그 (왜)
- **이름 도그스하이 > 독스하이**: 러너스하이와 5음절 1:1 — 운율이 곧 인용. 독스하이는 반 박자 어긋남 + 毒 그림자. 하이테일은 영어 원어민 워드플레이라 탈락 [V].
- **아이콘 풀블리드 + 저스티파이드**: 두 줄 같은 폭 → 하이(2글자)가 커져 위계 자동 생성. Sean 픽 = C(빼꼼)였다가 최종 A 채택 [H].
- **마스코트**: volt 털 = 고블린(포유류 자연 색역 이탈) → **"개를 칠하지 말고 입혀라"** — 크림 진돗개 + volt 반다나(장비 경제와 동형). 구현은 안 함. 구역: 빈 상태·온보딩·스탬프·에러·마케팅만, 실사진 구역 불가침 [V-보드].
- **캐러셀 아래 덱**: 반투명 월렛 z역전(내 안) 실패 → Sean 안 채택: 불투명 '밑으로 턱'(아래 카드들이 액티브 뒤로 올라와 바닥 엣지 56px 계단만 노출). 포커스 스케일 1.04→1.0(풀와이드 클리핑) [V].
- **그리팅**: 2줄 → 1줄 '{문구}, 우리 {이름}'(문구 10종 5s rotateX 플립, adjustsFontSizeToFit) + 좌측 pfp(profiles.avatar_url) + 아래 랭킹 티커. 회색 서브 → forest+voltDeep [V].
- **리스케줄 = 제안**: 취소·재예약 프리필(구 '같은 러너로 일정 변경') 은퇴. 러너 수락 시에만 적용, 수락 시점 슬롯 재검증 + 제안값 일치 조건부 UPDATE(레이스 방지), 레이지 만료(원 시간 2h 전) [V].
- **km↔코스**: **코스가 km을 따른다**로 결정(가격·정산의 진실은 km) — request 화면 구현은 백로그 [H].
- **보류 리네임**: 인계 확인→하이파이브(안전 명료성 우선), 최근 순간→오늘의 하이(과거 사진에 '오늘' 라벨은 부정직) [V].

## 5. 아키텍처 & 계약 (신규분)
- 0016 [V]: bookings.reschedule_new_time/proposed_at. transition-booking 액션 4종(request/accept/decline/withdraw_reschedule).
- 0017 [V-코드]: expire_unmatched_bookings() — matching/runner_pending && scheduled_at<now → expired + 알림, pg_cron 5분. **배포 미확인** — db push가 "up to date"를 거짓 반환한 전례 2회, `npx supabase migration list`로 확인 후 필요시 `db push --include-all`.
- settle-run [V-코드]: 원자 클레임(.eq status active → completed)이 중복 정산 락. 전 쓰기 에러 throw. 트랜잭션 RPC화는 백로그.
- create-booking-hold [V-코드]: 같은 강아지 겹침 가드(라이브 상태만: matching~active — draft/payment_hold 잔재는 차단 사유 아님·오탐 방지 의도, DO-NOT-"FIX").
- 실소요 공식 = **km×8분 + 25분 버퍼** (hold·accept_reschedule·리스케줄 화면 공통). 프로필 탐색 그리드만 60분(km 미정 — 의도, hold가 최종 검증).
- fetchCurrent*Id = FLIGHT_RANK(active>picked_up>enroute>confirmed) 정렬 — scheduled_at 최신순 금지 (엉뚱한 예약에 정산 붙던 버그) [V].
- matching.tsx 2층 컴포지터 불변 — 물리 상수(physicsFor)만 조정 가능. 헤더는 zIndex 50 + 불투명(뒤로가기 복원) [V].
- draft(store.ts) = 가변 싱글턴 — 제네릭 진입(슬라이드/직접 설정/findNowPay)에서 preferredRunner 소거 필수. 새 진입점 추가 시 동일 규칙 [V].

## 6. 파일 맵 (이 세션 신규/핵심)
- app/src/lib/displayFont.ts — BHS 지연 로더(useDisplayFont → TextStyle|null)
- app/app/owner/reschedule.tsx — 제안 화면(러너 바인딩 슬롯 그리드)
- supabase/migrations/0015~0017 — available_runners 뷰 / 리스케줄 컬럼 / 만료 크론
- docs/rebrand.md — 리브랜드 정본 · docs/brand/ — 아이콘 마스터 + 보드 5종
- scripts/wipe-test-data.mjs — 클린 슬레이트(`node scripts/wipe-test-data.mjs --yes`)

## 7. Sean 쪽 미완 (순서대로)
1. `npx supabase functions deploy transition-booking settle-run create-booking-hold` — 감사 배치 2 서버분. **미배포 시 구버전 정산(조용한 미지급 가능) 동작 중**
2. `npx supabase migration list` → 0017 원격 미적용이면 `npx supabase db push --include-all`
3. `npx expo prebuild -p ios --clean && npx expo run:ios` — 아이콘·앱명·BHS·카메라·LA 일괄 발현
4. `git push` (전부 로컬 커밋됨, 927a7d8~) · _to_delete/ 삭제
5. KIPRIS + 앱스토어 + 핸들 스윕 (도그스하이/DOGS HIGH) — 대외 공개 게이트

## 8. 환경 특이점 (다음 세션 필독)
- git: 커밋마다 lock/tmp 파일 unlink 불가 → **mkdir -p _to_delete/git-locks 후 mv** 의식 필수. Sean이 _to_delete를 지우면 mkdir부터 (전례 1회) [V].
- device_stage_files는 같은 경로 재스테이징 시 **스테일 캐시** 반환 가능 — 세션 중 수정된 파일은 device_bash python으로 직접 편집하거나 base64로 끌어올 것 [V].
- **파일 유실 사고 2회**: 최근 순간 스트립이 home.tsx와 api.ts 양쪽에서 사라진 채 발견(원인 미상 — Sean 편집 or 스테일 기반 커밋). 수리 전 반드시 대상 파일 최신본 확인 [V].
- supabase db push "Remote database is up to date" 거짓 반환 전례 — migration list로 검증 [V].
- python 편집 시 replace 뒤 후행 콤마 → 튜플 → 파일 truncate 사고 1회. write 전 assert + len 체크 습관 [V].

## 9. 감사 잔여 백로그 (16건 — 상세는 project memory와 동일)
MED: ① 지명 예약 서버 가용성 미검증(hold에 runner_id 미전달 + request_runner/runner_accept 재검증 없음 → 동시각 이중 계약) ② runner_pending이 클라 'pending'으로 뭉개져 지명 대기가 레이더 'N명 가능' 허위 표시 ③ 미트업 양측 종말 상태(completed/decline) 미처리로 화면 좌초 ④ runs.events/photos 클라 RMW 레이스(연타 시 응가 보너스 증발) — 서버 jsonb append RPC로 ⑤ 수익 표시 3종(주간 스탯 guarantee 누락·견적 일괄 20%가 티어 15/18% 무시·'정산 예정' 30행 캡) ⑥ '이번 주' 창 불일치(롤링 7일 vs 리더보드 월요일 리셋 — KST 캘린더 주로 통일)
LOW: ⑦ request 60분 슬롯 체크·DATES 자정 고정·체력나이 시드 1.8 표시+미래생일·open-drop 에러 미체크+동시 오픈 이중 적립
설계: ⑧ 코스가 km을 따른다(request 필터) · 코스↔픽업지 고지 · 티커 델타 RPC · 정산 트랜잭션 RPC · 리스케줄 만료 알림 크론

## 10. 미구현 아이디어 (유실 주의)
- 러너 장비 v1 (27일 섹션 상세 그대로 유효 — 다음 빅 피처 후보)
- 마스코트: 크림 진돗개+volt 반다나 확정 → 포즈 시트(앉기/달리기/하이파이브/미안/응가 경례) + 캐릭터명(KIPRIS 동반)
- iOS 대체 아이콘 A/D/F 세트 · 스탯 칩 에스컬레이션(7일 스트릭 시 필 심화) · pending 레일 브리딩 펄스(제안만 됨)
- 샵 셸 확장(27일 목업 10종 전사 유효) · 나이트 러너 테마

## 11. 다음 1–3 스텝 (권장)
1. [needs-user 먼저] §7의 1·2 배포 확인 → 솔로 루프 재검증: wipe → 예약 → 수락 → 리스케줄 제안/수락 → 러닝(GPS) → 정산 → 중복 예약 시도(409 확인) → 매칭 전 취소(전액 환불 확인)
2. [local-edit] 감사 백로그 ①+② (지명 가용성 검증 + pending/지명 분리 — 한 배치로 자연스러움)
3. [local-edit] ⑥ 주간 창 통일 or 러너 장비 v1 착수 (Sean 선택)

## 12. 검증 명령
- 읽기 전용: `npx supabase migration list` · 대시보드 SQL: `select column_name from information_schema.columns where table_name='bookings' and column_name like 'reschedule%';` · `node scripts/e2e.mjs --solo --keep` [H-스크립트 존재]
- 파괴적: `node scripts/wipe-test-data.mjs --yes` (테스트 초기화) · prebuild --clean (풀 리빌드 유발)

---

# 세션 핸드오프 — 2026-07-28 (저녁) 글로업·코스·장비·인증샷·패치

읽을 동반 문서: docs/mock-status.md (실/목업 원장 — 오늘분 4섹션 추가됨) · docs/rebrand.md · project memory `project-status.md` (백로그 정본) · 목업 3장: work/rebrand/shot-lab.html / share-flow-lab.html / shot-final-lab.html (Sean 컨테이너가 아니라 Claude 세션 산출물 — 대화에 전달됨, 재작업 시 재요청)

## 1. 목표 & 현재 상태

이 세션(오후~저녁)은 기능 대량 신설 세션. 전부 [verified-now] (tsc 통과 + 커밋):
- **요청 UX 2건** (be96676) — 코스가 km을 따른다 + 지리 고지 — 완료
- **러너 장비 v1** (f6d91e2, 마이그레이션 0019) — 완료, DB push 대기
- **코스 카드 v1** (3682538) — /course/[id] + CourseStrip 4진입점 — 완료, 마이그레이션 불필요
- **글로업 배치** (d8756ce/ac0f383/f9d8912) — 러너 시간 위계·요청 대형 카드+코랄 파동·리포트 FINISHER 도장·수익 티켓·CourseStrip 패치 덱 — 완료
- **홈 히어로 모프** (4447a84 → d4bdb8c) — 링 언랩→진행선(54도트 연속 스트로크), 요일 스탬프, 리포트 진입 매트 칩, 체력 나이 정직 게이트 — 완료
- **인증샷 스튜디오 + 코스 패치 v1** (fe8fcfc → 42c2aab → 67aff6d) — 완료, 실기기 부분 검증(사진 편집 OK[Sean 확인], 캡처/투명 PNG는 새 빌드 후 검증 필요)

## 2. 표준 독트린 (이 세션 추가분 — 불변 규칙)

- **디자인 모티프 독트린**: 5모티프(레이스 빕=숫자 · 티켓=거래 · 여권 도장=검증/완주 · 패치/스티커=수집 · 히트 트레이스=움직임). 화면당 히어로 모티프 1개, 같은 데이터 타입 = 같은 모티프. 채팅·설정·안심센터·폼은 의도적 플레인. 화면당 애니메이션 펄스 1~2개 상한.
- **사진이 곧 인증** (장비): verified_at ⇒ photo_url — DB 체크 제약으로 강제.
- **측정처럼 보이는 비측정 금지** (체력 나이): 활동 데이터 없이 계산값=등록 나이면 측정이 아니다 → 게이트 + 레시피 카피.
- **인증샷 = 마케팅 자산**: 완성 즉시 공유 시트 자동 — '공유' 버튼 재탭 금지. 브랜드 디바이스 3종(아이콘 칩·브랜드 테이프·워드마크 락업)은 모든 스킨 필수.

## 3. 협업 규범 [from-history]

- Sean은 스크린샷+구체 불만으로 피드백. 오해 정정은 즉시·정확 ("pixel by pixel exactly the same" = 슬롯2 미렌더 진단). 잘못 짚으면 되물어보지 말고 코드로 원인 찾기.
- "make your own decisions after substantial thinking" 위임 유지 — 단 배치·등급 임계 같은 제품 결정은 옵션+추천으로 물어봄 (예: 패치 골드 5회 → Sean이 상향 지시).
- 푸시백 환영 ("feel free to push back") — 라디에이터 중복·홈 밀도 등 실제로 반려하고 대안 제시가 잘 통했다.

## 4. 결정 로그 (WHY 포함)

- **장비 = 슬롯제(kind당 1)** — 부스트 파밍 구조적 차단 + RPG 로드아웃 가독성. 부스트 min(2,인증수) 상한: 장비는 신뢰 신호이지 승부축 아님.
- **코스 v1 = 스키마틱, 지도 SDK 없음** — 네이티브 리빌드 회피 + routes.trace 기존 스킴 활용. 실좌표는 v2 [Sean 승인].
- **코스 사진 = 내 것만** — 타인 runs.photos 공개는 RLS 위반+동의 문제. 공개 갤러리는 v2 동의 UI와 함께 [Sean 승인].
- **모프 = 도트 언랩** [Sean 안] — 축소 대신 재배열: 데이터 객체(점)는 하나, 원/미니바/센터 숫자 3중 표기 은퇴. 빈 자리 = 요일 스탬프 (radar/티어/사진 반려 — 각각 중복·부재·중복 사유).
- **패치 사다리 ×1/×5/×10/×25** — 골드 5회는 너무 쌈[Sean]; 5/10을 드랍 리듬에 동기('드랍 여는 날=승급하는 날'), 학습 비용 0. 포인트 보너스는 v2 서버(완주 인센티브 독트린과 무충돌).
- **인증샷 스킨 A·B·G·I** [Sean 선택, 9안 중]. **A·B 사진 온/오프 이중 모드** — '투명 대형' 별도 스킨은 A와 쌍둥이(특히 무트레이스 러닝에서 픽셀 동일)로 오독 → B의 사진 없는 상태로 흡수. 교훈: 폴백 상태까지 포함해 스킨 간 차별성을 검증할 것.
- **체력 나이 게이트(28일 2완주)** — 0완주 계산값 = 등록 나이 그대로 → 측정 사칭. Sean이 정확히 지적.

## 5. 아키텍처 & 계약 (신규분)

- **runner_gear (0019)**: unique(runner_id,kind), check(verified_at ⇒ photo_url), 공개 read/본인 write. DO-NOT-REFACTOR: 체크 제약이 정직성의 집.
- **코스 패치 = 순수 파생** (fetchCoursePatches): completed bookings × route_id, or(owner,runner). 테이블 없음 — 마이그레이션 0이 의도. 등급 patchGrade(n): 25/10/5 임계.
- **/shot/[bid] 스튜디오**: photoOn{A,Bp} 상태로 투명/사진 동적 전환 — isTransparent()가 체커보드·라운딩·캡처·액션 전부 구동. PhotoLayer = PanResponder 핀치/팬/더블탭, 새 photoUri → transform 리셋. 캡처 = view-shot(activeKey ref), 시트 확정/갤러리 선택 → 450ms 후 자동 Share. sheetFor ref가 어느 스킨의 사진 요청인지 기억.
- **모프 스트로크**: MORPH_DOTS 54 × 11px (간격≤지름 = 연속선). 각 도트가 원좌표↔선좌표를 scrollY t로 개별 보간(JS 드라이버 — 스크롤 이벤트가 원래 JS). LINE_Y_HERO=154. dotBoxY는 onLayout 실측. DO-NOT-REFACTOR: 네이티브 드라이버로 옮기려면 스크롤 이벤트부터 옮겨야 함.
- **fitnessGate**: null | {reason:'birth'} | {reason:'runs', left}. fetchFitness가 산출 — 홈·체력 리포트가 소비.
- **REQ_SELECT에 route_id, routes(name) 추가** — OpenRequest.routeId/routeName. fetchOpenRequests(별도 인라인 매퍼)도 동일 추가 — 두 곳 다 고쳐야 하는 이중 지점 주의.
- **PulseRings**(runner/home) — 코랄 긴급 파동, 현재 tang 고정(색 파라미터화는 #1 작업에서).

## 6. 파일 맵 (이 세션 신규/핵심 수정)

신규: app/shot/[bid].tsx(스튜디오) · app/course/[id].tsx(코스) · src/components/CourseStrip.tsx · src/components/patch.tsx(PatchBadge) · supabase/migrations/0019_runner_gear.sql
대수정: src/lib/api.ts(장비·코스사진·패치·fitnessGate·runDays·REQ_SELECT) · app/owner/home.tsx(모프·스탬프·칩·CourseStrip) · app/runner/home.tsx(요청 대형 카드·PulseRings·패치·CourseStrip) · app/owner/report.tsx(FINISHER 도장·인라인 인증샷 은퇴) · app/runner/earnings.tsx(티켓) · app/owner/schedule.tsx(완료 패치+인증샷) · app/cards.tsx(패치 월) · app/runner/requests.tsx(whenBar·코스 링크) · app/owner/request.tsx(미리보기 칩·routeId 파라미터) · app/owner/matching.tsx(장비 칩·부스트) · app/runner/meetup.tsx(장비 체크리스트) · app/runner-profile/[id].tsx(장비 로드아웃)

## 7. Sean 쪽 미완 (순서대로)

1. `npx expo install react-native-view-shot expo-media-library` → `npx expo prebuild -p ios --clean` → `npx expo run:ios` [uncertain — 실행 여부 미확인]
2. `npx supabase db push` (0018+0019 — 0018 미배포 시 러닝 이벤트 기록 실패!) + `npx supabase functions deploy open-drop` [uncertain — 동일]
3. `git push` (~25 커밋 선행)
4. 실기기 검증: 투명 PNG 알파(인스타 스토리 스티커) · 포토 스킨에서 캐러셀 스와이프 감 · 모프 연속선 착지 위치 · 요일 스탬프 겹침

## 8. 환경 특이점 (기존 + 오늘 추가)

- git lock 의식 유지 (mkdir -p _to_delete/git-locks 후 mv; index.lock 잔존 시 다음 커밋 실패 — 커밋 직후 정리 확인).
- device_stage_files 스테일 캐시 전례 — 서버 파일 수정은 device_bash python 직접 편집.
- tsc와 commit 체이닝 금지 (tsc 먼저, 통과 확인 후 커밋).
- 목업 HTML은 Google Fonts CDN 사용(컨테이너에선 폰트 폴백, Sean 브라우저에선 정상).

## 9. 미구현 아이디어 (유실 주의 — v2 대기)

- 패치: 리포트 획득 팝(→ #1에서 구현 예정) · 러너 프로필 공개 '달린 코스' 스트립(SECURITY DEFINER 뷰 필요) · 골드/마스터 포인트 보너스(settle-run).
- 코스: 실좌표+지도 · 사진 공개 동의 갤러리 · fit 실화 · trace/desc DB 이전.
- 장비 v2: 관리자 검수 · 샵 연동(gear_claims).
- 스튜디오: 스킨별 사진 독립 transform(현재 A/B 공유) · 무GPS 러닝에서 A/B 폴백 차별화 강화.
- KIPRIS 스윕 · 마스코트 포즈 시트 · 샵 셸 · APNs · 반복 예약 UI.

## 10. 다음 1–3 스텝

1. [local-edit, 진행 중] #1 폴리시: 리포트 패치 팝 1회 + 드랍 보급상자 볼트 펄스 + 리더보드 톱3 포디움 빕.
2. [needs-deploy, Sean 예고] #2 서버 라운드: 정산 트랜잭션 RPC화 · 리스케줄 만료 알림 크론 · 티커 델타 RPC.
3. [read-only] KIPRIS 스윕.

## 11. 검증 명령 (읽기 전용)

- `cd app && npx tsc --noEmit` — 타입 무결성
- `npx supabase migration list` — 0018/0019 배포 여부 확인
- 앱: 러너 프로필 장비 슬롯 → 매칭 카드 칩 → 미트업 체크리스트 / 일정 완료 카드 → 스튜디오 4스킨 / 마이 카드 패치 월 / 홈 스크롤 모프
