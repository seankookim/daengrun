# 도그스하이 — 종합 TODO (2026-07-29 B 배치 + 반복 예약 완료 기준)

새 세션 오프너: **"read docs/session-handoff.md fully, then continue"** — 이 파일은 실행 목록, 맥락·결정 이유는 핸드오프에.
상태 태그: [ready]=바로 착수 가능 · [needs-user]=Sean 행동 필요 · [needs-verify]=실기기 확인 후 진행 · [design]=논의 먼저

## A. 검증 (최우선 — 실기기 확인) [needs-user]
- [ ] 푸시: 양 홈에서 권한 수락 → 앱 완전 종료 → 요청 발송 → 잠금화면 수신. 실패 시 push_tokens 행 + pg_net 응답 점검 (`select * from net._http_response order by id desc limit 5`)
- [ ] **푸시 딥링크 (NEW 9b0a32b)**: 잠금화면 알림 탭 → 보호자는 리포트 / 러너는 요청 탭 착지. 콜드스타트(완전 종료 상태)도 확인
- [ ] 인증샷: 4스킨 스와이프 · A/B 사진 온오프 · 캡처→공유 시트 · 투명 PNG를 인스타 스토리 스티커로 · **스킨별 사진 독립(NEW)**: B에서 사진 바꿔도 A 크롭 유지
- [ ] 홈 모프 연속선 착지 위치(LINE_Y_HERO=154) · 요일 스탬프 겹침 · 리포트 매트 칩
- [ ] 정산 풀루프 (settle_run_tx 경유 첫 실정산) · 패치 팝 · 포디움 빕 · 드랍 볼트 파동
- [ ] **일정 확정 카드 절취선 (NEW)**: 레일 경계 노치+도트가 카드 경계에서 반원으로 잘리는지
- [ ] **Sean: `npx supabase db push` (0025 패치 보너스 + 0026 반복 예약 + 0027 집계 RPC)** — 함수 재배포는 불필요 (RPC/크론만). ⚠ 0027 push 전까지 앱의 포인트 잔액·정산 예정이 RPC 404로 에러 — push 먼저, 앱 확인 나중
- [ ] **반복 예약 (NEW 6882d93)**: 요청 화면 토글 → 결제 → 일정 탭 ⟳ 필 확인 → 관리 시트 '매주 반복 해지' → 크론 생성은 다음 발생 72h 전 (수동 트리거: 대시보드 SQL `select generate_recurring_bookings();`)

## B. 소형 빌드 — 2026-07-29 세션 전부 완료 (9b0a32b)
- [x] 푸시 딥링크: routeForNotification 단일 소스(push.ts), 탭 리스너 + 콜드스타트, 알림 인박스와 규칙 공유
- [x] 골드/마스터 포인트 보너스: 0025 — settle_run_tx 안 코스 누적 =10/=25 판정, patch_gold +200 / patch_master +500 (완주 게이트 안)
- [x] 일정 확정 카드 절취선: 상태 레일 = 티켓 스텁, 크림 펀치 노치 + 도트 퍼포레이션
- [x] 스튜디오 스킨별 사진 transform 독립화: photos{A,Bp,G} — resetKey 스킨별
- [x] 러너 홈 '최근 완료' → ledger_items 실 net (2-step 쿼리, 과거 무원장 건은 견적 폴백)

## C. 중형 빌드 [ready, 새 세션 권장]
- [x] **반복 예약 UI** (2026-07-29, 6882d93 + 0026): 토글(가격·해지 명시) → 시리즈 스냅샷 → 매시 크론(72h 창, 같은 러너 우선 + 가용성 재검증, 겹침 가드) → ⟳ 필 실화 + 시트 해지. v2: 실 PG 청구 단계 · 가격 개정 반영 · 다요일
- [x] **샵 셸 v1** (2026-07-29): 실잔액 히어로(0027) + 최근 적립 + 기어 교환권(gear_claims 실데이터) + 도착한 드랍 스트립 + 활성 부스트 표시. '멤버 10% 할인' 가짜 약속 은퇴, 상품 그리드는 '오픈 준비 중 · 예정가' 명시. v2: 포인트 실사용처(shop_spend) · 실 SKU · 교환권 배송
- [x] fetchMiles/fetchLedgerTotal 2000행 상한 → 서버 집계 RPC (2026-07-29, 0027 — invoker + RLS self read)
- [ ] 코스 v2: 실좌표 + 지도 SDK(react-native-maps 이미 조건부 로드 구조 있음 — getMaps()) · 지오 거리 정렬 · routes.trace/desc DB 이전
- [ ] 사진 공개 동의 UI → 코스 공개 갤러리 (러닝 후 '이 사진을 코스 갤러리에 공개할까요?')
- [ ] 장비 v2: 관리자 검수 인증 · 샵 연동
- [ ] fit(코스 적합도) 실화 — 매칭 엔진 v2 (견종·체중·에너지 레벨 × 코스 특성)

## D. 대형 [design]
- [ ] 결제 실연동 (현재 payment_ok 모의) — PG 선정부터
- [ ] 러너 온보딩/심사 플로우 (신원·경력 검증 — tier 'applicant' 승급 경로)
- [ ] 실시간 러닝 추적 고도화 (owner/live) · 바디캠
- [ ] 나이트 러너 다크 테마 (반쪽 다크 은퇴된 상태 — 전 화면 일괄)

## E. 비즈니스 [needs-user]
- [ ] **KIPRIS 수동 확인** (2026-07-28 웹 스윕: '도그스하이'/'독스하이'/'dogshigh' 사용 브랜드 미발견. 단 **하이독(HIGHDOG)** — 반려동물 영양 기업 highdog.co.kr — 어순 반전 유사 상표 존재, 전문 검토 권장):
  kipris.or.kr → 상표 검색 → '도그스하이', 'DOGS HIGH', '독스하이', '하이독' × 분류 9(앱)·35(플랫폼 중개)·41(훈련/스포츠)·45(반려동물 돌봄) — 출원 전 변리사 1회 상담 권장
- [ ] 핸들: 인스타 @dogshigh · 도메인 dogshigh.com/.kr 가용 확인 및 선점
- [ ] 마스코트 포즈 시트 (방향 확정: 크림 진도 + 볼트 반다나 — '개를 칠하지 말고 입혀라'. 그린 도그 반려됨)
- [ ] App Store 준비: 번들 com.seankookim.daengrun · EAS projectId 0436bc27 · 푸시 키 등록 완료 · TestFlight 빌드는 `eas build --profile preview -p ios`

## F. 기술 부채 / 환경
- [x] app.json·eas.json 커밋 확인 — git ls-files로 검증 (03ba266에 포함)
- [ ] git lock 의식 유지 · device_stage_files 스테일 캐시 회피(핸드오프 §8)
- [ ] 의도적 잔여 1건 유지: 프로필 탐색 그리드 60분 (러너 홈 net은 B에서 해소됨)
