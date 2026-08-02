# 도그스하이 — 종합 TODO (2026-08-02 스모크 세션 + 0051 기준)

새 세션 오프너: **"read docs/session-handoff.md fully, then continue"** — 이 파일은 실행 목록, 맥락·결정 이유는 핸드오프에.
상태 태그: [ready]=바로 착수 가능 · [needs-user]=Sean 행동 필요 · [needs-verify]=실기기 확인 후 진행 · [design]=논의 먼저

## ⓪ 위탁(클럽) RN 트랙 — 현재 주 무대 (정본: 핸드오프 v5.1 + club-run-logic v3.3)
- [x] 빌드 1 (ad89de1): 라일락 토큰 · club-ui 킷 · api 위탁 블록 복원 · O1 티켓 · O2 승낙서
- [x] 빌드 2 (5a54b2b): 세션 셸(개요·참가자·채팅) · O3/O4 상태 카드 · O5 결제 시트
- [x] 빌드 3 (40d3deb): O8/O10 양측 확인 · 호스트 콘솔 · ownerObjection 시그니처 수리
- [x] 빌드 4 (541bdd9): R2 제안 수락 · R3 오늘 담당 · 러너 확약
- [x] 빌드 5 (801b451): 챗 고정 드로어 ④ + ack 배너 스택 ⑤ (club-acks.tsx — 셸·콘솔·클럽 홈 장착)
- [x] 빌드 6 (5aadd49): 케이스 상세 club/case/[cid] + 신고·SOS 문 (R6 래퍼 일체)
- [x] 빌드 7 (dbee04e·da41f91): 러닝 시작 = 러너 액션으로 수리 · O9 라이브 문(owner/live 재사용) · SETTLED→리포트 문
- [x] **08-02 실기기 스모크 (Sean, 솔로)**: 신청→승인→결제→자기제안 확정→인계→러닝→종료(settle)→결과 화면 완주. 발견→수리: 동적 정원 카피(f43b022) · 배정 창 카피(38369a2) · O2 매핑(ec2746d) · 러닝 종료 문 신설(5487aa8) · **done=결과 화면만(06238d4, Sean 결정)** · RPC 계약 검사기(2723234, 커밋 게이트 편입) · 홈 모프 단순화(d2c77e8)
- [x] 마이그레이션 0051 (def1c66): nextSession에 format·코스·요금 — 하네스 181/181 + UPGRADE OK (컨테이너 재구축). O1 문 정직화 포함
- [ ] [needs-user] **`supabase db push` (0051) → 클럽 홈 새로고침으로 문 확인** · git push (ahead 2) · 스모크 잔여: 반환 ×2 → 세션 종료 → 결과 화면 검수 · 결과 화면 뒷문 3개(채팅·신고·호스트 요약) 유지 여부 판정
- [x] 빌드 8 (572e9f1): 클럽 러너 런 화면 club/run/[sid] — GPS 실측·60초 트레이스 배치·멀티 라이브 브로드캐스트(geo.createPosPublisher)·마리별 완주/조기 정산·SOS+위치. 셸 러닝 시작→런 화면 직행
- [x] 빌드 9 (aba1f17): O11 영수증 club/receipt/[bid] — 골드 실·실측 수치·베스트 샷 인화(있을 때만)·이미지 공유(view-shot)·피드 자랑·SETTLED 문 교체
- [ ] [needs-verify] 빌드 8·9 실기기: GPS 권한→실측 거리·트레이스 저장·보호자 라이브 수신·마리별 종료·영수증 캡처 공유
- [ ] [ready] 챗 사진 전송 (kind photo — sendChatPhoto 선례) · 케이스 타임라인에 커스터디 이벤트 병합 · 클럽 런 사진 업로드(영수증 인화 원천)
- [ ] [ready] 클럽 홈 이음새 재도색 · 플랩 플립/봉인/링 안무 4종 · expo-blur 도입 여부 [needs-user]

## A. 검증 (최우선 — 실기기 확인) [needs-user]
- [ ] 푸시: 양 홈에서 권한 수락 → 앱 완전 종료 → 요청 발송 → 잠금화면 수신. 실패 시 push_tokens 행 + pg_net 응답 점검 (`select * from net._http_response order by id desc limit 5`)
- [ ] **푸시 딥링크 (NEW 9b0a32b)**: 잠금화면 알림 탭 → 보호자는 리포트 / 러너는 요청 탭 착지. 콜드스타트(완전 종료 상태)도 확인
- [ ] 인증샷: 4스킨 스와이프 · A/B 사진 온오프 · 캡처→공유 시트 · 투명 PNG를 인스타 스토리 스티커로 · **스킨별 사진 독립(NEW)**: B에서 사진 바꿔도 A 크롭 유지
- [ ] 홈 모프 연속선 착지 위치(LINE_Y_HERO=154) · 요일 스탬프 겹침 · 리포트 매트 칩
- [ ] 정산 풀루프 (settle_run_tx 경유 첫 실정산) · 패치 팝 · 포디움 빕 · 드랍 볼트 파동
- [ ] **일정 확정 카드 절취선 (NEW)**: 레일 경계 노치+도트가 카드 경계에서 반원으로 잘리는지
- [ ] **Sean: `npx supabase db push` (0025~0029) + `npx supabase functions deploy settle-run`** — settle-run 재배포는 이제 필수 (서버 입력 검증 추가). ⚠ 0027 push 전 잔액/정산 RPC 404 · **0028 push 전 모든 정산 실패** (이넘 캐스트 — 트랜잭션 롤백이라 부분 반영 없음)
- [ ] 셀프 테스트 하네스 도입됨 (supabase/tests/harness.sh — 46 SQL 케이스 + app/test 23 geo 케이스, 2026-07-29 전건 통과). **새 마이그레이션은 db push 전 하네스 통과 필수**
- [ ] **정산 재검증 (0028 push 후)**: 완주 정산 + 조기 종료(컨디션/보호자 요청) 정산 + 5회차 드랍 롤 (drops.kind 동종 버그 수리됨) · 실패 시 '다시 시도' 버튼으로 회복되는지 · 좌초됐던 테스트 예약은 wipe로 정리
- [ ] **반복 예약 (NEW 6882d93)**: 요청 화면 토글 → 결제 → 일정 탭 ⟳ 필 확인 → 관리 시트 '매주 반복 해지' → 크론 생성은 다음 발생 72h 전 (수동 트리거: 대시보드 SQL `select generate_recurring_bookings();`)
- [ ] **네이버 지도 (NEW)**: 설치+prebuild 후 — 러너 run 화면 실지도+본인 라인 · 보호자 live 실시간 라인/마커 · 지도 안 뜨면 NCP 콘솔에서 **Mobile Dynamic Map 활성 + iOS 번들 com.seankookim.daengrun 등록** 확인 (401 = 키/번들 문제)
- [ ] **트레이스 스무딩 (NEW ce8fc00)**: 라인이 곡선+화이트 케이싱으로 보이는지 (3화면) · 도심에서 지그재그/순간이동 사라졌는지 · km 값이 이전 대비 살짝 줄 수 있음(지터 제거 — 정상)
- [ ] **Sean 설치 커맨드 (지도)**: `cd app && npx expo install expo-build-properties && npm i @mj-studio/react-native-naver-map && npm uninstall react-native-maps && npx expo prebuild -p ios --clean && npx expo run:ios` → package.json 변경 커밋

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
- [ ] 코스 v2: 실좌표 + **네이버 지도** (2026-07-29 SDK 채택·라이브 2화면 적용 완료 — getNaverMap()) · 코스별 실좌표 데이터 작성이 선행 (routes.trace는 0..1 스키마틱) · 지오 거리 정렬 · trace/desc DB 이전
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
