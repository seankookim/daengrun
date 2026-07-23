# Mock vs Real 상태 대장

> 앱에서 진짜로 동작하는 것 / 목업(가짜)인 것의 목록. 백엔드(Supabase) 붙일 때마다 업데이트.
> 마지막 업데이트: 2026-07-22 (v0.14)

## ✅ 진짜로 동작 (클라이언트 로직)

- 화면 이동 전체 (owner/runner 전 플로우)
- 요청 화면 가격 계산 (거리·옵션 실시간 합산)
- 시간 슬롯 선택 → 선택값 반영
- 코스 선택 → 선택 상태
- 러너 수익 비례 정산 계산 (실제 km 기준)
- 러닝 시뮬레이션 (타이머 기반 거리·페이스·진행률)
- 내 일정 필터링
- 다크/라이트 모드 전환 (홈·기록 화면 — 전 화면 확대 예정)
- 채팅 입력·전송 (로컬 상태만, 상대 응답 없음)
- 인계 확인 단계 진행 (양측 화면 존재 · 상대방 확인은 타이머로 가짜 처리)
- 러너 종료 사유별 정산 계산 (컨디션/보호자 요청+잔여50%/개인 사유)
- 보호자 종료 시트 (사유 선택 필수 · 최소 요금 고지 · 확인 경고)

## ⛔ 목업 (백엔드 필요)

| 항목 | 현재 상태 | 실제 구현 시 필요한 것 |
|---|---|---|
| 계정/로그인 | 없음 (역할 선택만) | Kakao OAuth + Supabase Auth |
| 푸시 알림 전체 | Alert 팝업으로 흉내 | Expo Notifications + 서버 트리거 |
| 수락 알림 (러너→보호자) | Alert "전송되었어요" | 예약 상태 머신 + 푸시 |
| 알림 센터 데이터 | 하드코딩 8건, 탭 필터 장식 | notifications 테이블 + 읽음 처리 |
| 채팅 상대방 | 응답 없음 (시드 대화만) | Supabase Realtime |
| 지도 전체 | View로 그린 가짜 지도 | react-native-maps + 실 GPS |
| GPS 트래킹 | 타이머 시뮬레이션 | expo-location (러너 기기) |
| 바디캠 | 스타일된 박스 | 하드웨어 + 스트리밍 인프라 |
| 결제 | 화면만 | 카카오페이/토스페이먼츠 + 슬롯 홀드 |
| 슬롯 홀드 | 2.2초 모달 데모 | 서버 원자적 홀드 (calendar.md) |
| 러너 가용성/슬롯 공급 수 | 하드코딩 | 가용성 엔진 (calendar.md) |
| 매칭 점수/AI 추천 | 하드코딩 98% | 실제 매칭 알고리즘 |
| 예약 데이터 | store.ts 4건 하드코딩 | bookings 테이블 |
| 취소/환불 | Alert | 결제 취소 API + 정책 엔진 |
| 반복 예약 | "준비 중" 칩 | 시리즈 데이터 모델 |
| 커뮤니티 피드 | 하드코딩 4포스트, 좋아요 정적 | posts 테이블 + 미디어 업로드 |
| 샵 구매 | Alert | 커머스 백엔드 (또는 외부몰 연동) |
| 마이 카드 획득 | 6장 하드코딩 | 러닝 완료 트리거 + 조건 엔진 |
| 체력 나이/주간 목표 | 하드코딩 1.8살/15km | 수의 검증 공식 + 실데이터 |
| 날씨/미세먼지 | 하드코딩 24° | 기상청/에어코리아 API |
| 사진 전송/갤러리 | Alert | 스토리지 + 권한 |
| 안심 통화 | Alert | 번호 마스킹 (Twilio류) |
| 러너 인증(7단계 대응) | 배지만 존재 | 신원확인 절차 + KYC |
| 프로필 사진 전체 | 모노그램 원 | 이미지 업로드 |
| 테마 유지 | 앱 재시작 시 초기화 | AsyncStorage |
| 보호자 종료 → 러너 강제 알림 | Alert 안내문만 | 푸시(critical alert급) + 러너 화면 강제 배너 |
| 위젯 '곧 시작' 상태 전환 | demoImminent 플래그 하드코딩 | 예약 시각 기준 실시간 계산 (30분 전) |
| 러너 이동/도착 감지 | 타이머 시뮬레이션 | 러너 GPS + 지오펜스 |
| 사진/휴식 요청 (보호자→러너) | Alert | 푸시 + 러너 화면 표시 |
| 보급/픽 드랍 판정·확률 | 하드코딩 (215회=드랍) | drops 테이블 + 서버 확률 롤 + 회계 |
| 기어 수령/배송 | Alert | gear_claims + 배송 연동 |
| 매칭 부스트 적용 | UI만 | 매칭 랭킹 가중치 |

## ✅ 실화(實化) 완료

- **안심 코스 카탈로그** — request 화면이 Supabase `routes`에서 로드 (실패 시 목업 폴백, "실시간 코스 정보" 표시). 첫 라이브 데이터.
- **인증** — 이메일 OTP 로그인 실동작, 세션 유지, profiles upsert. (카카오: Expo Go 리다이렉트 이슈 — dev build에서 해결 예정)
- **예약 생성 파이프라인** — 결제하기 → ensureDog → create-booking-hold (서버 가격·원자 홀드) → payment_ok → matching 상태. 홀드 모달에 "서버 홀드 확보" 표시. 실패 시 오프라인 데모 모드 폴백.
- **내 일정 실예약 표시** — DB 예약이 LIVE 배지로 목업 위에 병합. 매칭 전 예약은 관리 시트 게이트.
- **지명 매칭 (v0.18)** — 매칭 화면에 실러너 목록(● LIVE), 지명 요청 → runner_pending → 러너 인박스 ★ 지명 요청 표시. 목업 러너 카드는 데모 표기.
- **인계 동기화 정직화** — 보호자 화면의 '러너 도착'이 서버 상태(runner_enroute) 기반. 러너 미트업 진입 시 enroute 보고. 가짜 타이머는 데모 경로에만.
- **알림 읽기** — 알림 센터가 notifications 테이블 표시(● LIVE 섹션) + 모두 읽음 실동작. 배달(푸시/실시간)은 다음 세션.
- **러너 홈 실요청 배너** — 인박스 요약 스트립 (데모 목록은 표기).
- ⚠ 필요: `npx supabase functions deploy transition-booking` (request_runner 액션 추가됨)
- **러너 루프 전체 (v0.17)** — 역할 선택 시 runners 행+가용시간 생성(테스트용 즉시 인증), 요청 인박스가 실 matching 예약 표시, 수락→confirmed, 양측 인계 confirm_handoff+상태 폴링→picked_up, 러닝 시작→active+runs 행, 종료→settle-run(사유별 실지급·원장·드랍 롤). **한 예약이 상태 머신 전 구간을 실주행.** 필요: `supabase db push` (0004 — 러너 인박스 가시성 정책).

## 백엔드 진행 상황

- ✅ 스키마 v1 (`supabase/migrations/0001_init.sql`) — 28 테이블, 상태 머신 트리거, pglast 구문 검증 완료
- ✅ RLS v1 (`0002_rls.sql`) — 역할별 접근, platform_only 리뷰, 돈 테이블 서버 전용
- ✅ 시드 (`seed.sql`) + 셋업 가이드 (`docs/backend.md`)
- ✅ Sean: 프로젝트 생성 + db push + routes 시드 완료 (2026-07-22)
- ✅ Phase 2 코드: 가용성 엔진 (`0003` — is_slot_available/count_available_runners/purge_expired_holds), Edge Functions 4종 (create-booking-hold, transition-booking, settle-run, open-drop)
- ⏳ Sean: `npx supabase db push` (0003) + `npx supabase functions deploy` + Kakao provider
- ✅ Phase 3a: 로그인 (이메일 OTP 실동작 + 카카오 스텁), 세션 유지 (AsyncStorage), 라우트 가드, 역할 선택 시 profiles upsert, 로그아웃
- ⏳ Sean: `cd app && npx expo install @react-native-async-storage/async-storage` 후 재시작 (버전은 package.json에 지정됨 — `npm install`로도 충분)
- ⏳ Phase 3b: 카카오 OAuth (provider 설정 후), bookings 화면 → 상태 머신 연결, Realtime (chat/status), 매칭 자동배정, 실좌표 트레이스

## 2026-07-23 세션: 인계 side 버그 + E2E 하네스

- ✅ **confirm_handoff side 버그 수정** — 한 계정이 양측(솔로 테스트)이면 `isOwner` 우선 검사 때문에 양쪽 확인이 모두 owner 타임스탬프에 기록 → 영원히 picked_up 불가. 이제 클라이언트가 `meta.side`('owner'|'runner') 선언, 서버가 자격 검증 + 확인 후 재조회(동시 확인 레이스 방지). **⏳ Sean: `npx supabase functions deploy transition-booking` 필수** (request_runner 배포도 아직이면 함께 해결됨)
- ✅ 보호자 미트업 재진입 시 이미 확인했으면 'waiting' 복원 (버튼 재노출 방지)
- ✅ **E2E 하네스** `scripts/e2e.mjs` — 전체 루프(hold→결제→RLS 노출→수락→enroute→양측 인계→start→settle→원장 검증)를 자동 실행. `--solo`(한 계정 양측 = Sean 수동 테스트 재현), `--keep`(데이터 유지). **⏳ Sean: 루트 `.env`에 `SUPABASE_SERVICE_ROLE_KEY=` 추가 후 `node scripts/e2e.mjs`** (Dashboard → Settings → API). 샌드박스에서 supabase.co 직접 접근이 차단되어 잔심부름은 이 스크립트 한 줄로 대체
- ✅ 보안: `app/.env`를 git 추적에서 제거(+.gitignore) — 서비스 키 커밋 사고 예방
- ✅ 보호자 탭 개편: '기록' 탭 → **'내 일정'** 탭 (예약 관리가 접근 빈도상 탭 자격; 기록은 홈 히어로·스탯에서 진입 유지)

## 2026-07-23 세션 2: 데모 전락 사고 근절

원인 하나가 버그 셋을 만들었다: 트랜잭션 화면들이 인메모리 booking id(draft/runnerJob)에 의존 →
리로드 등으로 유실되면 **조용히 데모 모드로 전락** → 가짜 자동도착·가짜 상대확인·정산 누락(위젯 ● LIVE 좀비).

- ✅ 보호자/러너 미트업: 데모 타이머 전면 삭제. id 없으면 서버에서 진행 중 예약 복원(fetchCurrentOwnerBookingId/RunnerJobId), 없으면 안내 후 닫힘 — 이 화면들은 이제 실예약 전용
- ✅ run.tsx: **자동 완주가 서버 정산을 건너뛰던 버그 수정** (settle 없이 done 직행 → 예약 영원히 active). 이제 자동/수동 모두 settle-run 경유 + 중복 정산 가드 + id 복원
- ✅ 내 일정: 진행 중(● LIVE) 카드에 라이트 코랄 '실시간 보기' 버튼 (Sean 요청)
- ✅ 홈 위젯 실시간 보기 버튼이 draft.bookingId 설정
- ✅ e2e `--directed`: 지명(request_runner) 경로 서버 테스트 추가
- 남은 목업(다음): 미트업 픽업 좌표/강아지 카드 표기(runRequests[0] 목업), owner/live 지도 데모, run.tsx 거리 가속 타이머(실 GPS 전까지)

## 2026-07-23 세션 3: 인계 타임스탬프 위생 + 상태별 시트

- ✅ **runner_accept/decline이 인계 타임스탬프 초기화** — 이전 시도의 잔재 stamp가 남으면 한쪽 확인만으로 즉시 picked_up ("러너는 대기 중인데 보호자 화면은 이미 LIVE" 사고). **⏳ Sean: `npx supabase functions deploy transition-booking` 재배포 필요**
- ✅ 양쪽 미트업 화면이 **양측 확인 상태를 각각 서버 진실로 표시** ('내 인계 확인' / '상대 인계 확인' 별도 스텝) — 누가 누굴 기다리는지 추측 불가능하게. 러너 화면도 전 단계 폴링으로 전환
- ✅ 내 일정 시트 상태별 액션: 진행 중 → 실시간 보기만(변경·취소 불가 안내 + SOS 안내), 완료 → 기록 보기만, 시작 전 → 기존 변경·취소
- ✅ e2e: 수락 시 타임스탬프 초기화 검증 추가

## 2026-07-23 세션 4: picked_up ≠ active (라이브 조기 점화 수정)

- ✅ BookingStatus에 `handoff` 추가 — picked_up(인계 완료·시작 대기)이 active(러닝 중)로 뭉개져 보호자 라이브 UI가 조기 점화되던 문제. 위젯: '인계 완료 · 러닝 시작 대기 중' 버튼(미트업으로), 코랄 실시간 보기는 **start_run 이후에만**. 일정 카드/시트도 동일 구분
- ✅ 보호자 미트업: picked_up이면 '러너가 곧 러닝을 시작해요'에서 대기, **active가 되어야만** 라이브로 자동 전환 (1.2s 연출 타이머 제거 — 서버 상태만 따름)
- ✅ `scripts/wipe-test-data.mjs --yes` — 예약·러닝·정산·알림·채팅 전체 초기화(계정·강아지·러너 유지). 테스트 전 백지화가 한 줄로
- 참고: 이전 수정 검증이 안 됐던 이유 = 기존 예약이 수정 배포 이전의 stamps를 이미 들고 있었음. wipe 후 새 예약으로 재검증 필요

## 2026-07-23 세션 5: 추천 매칭 복원 + 러닝 리포트

- ✅ **러너 추천 UI 실데이터로 복원** — 데모 정리 때 추천 경험(배너·1순위 다크카드·매치 바)이 데모 전용으로 묶여 실예약에선 밋밋한 리스트만 남았었음. 이제 실러너를 응답률(35%)·경험(30%)·페이스 적합(35%) 가중합으로 점수화해 1순위 추천 카드 + 대안 리스트 렌더. 실매칭 엔진(견종 경험·후기·거리) 전까지의 v1
- ✅ **러닝 리포트 화면** `/owner/report?bid=` — 실거리 vs 계획, 시간, 페이스, 종료 사유(컨디션 종료는 코랄 + 러너 메모 + 안내), 결제. 러닝 전 예약이면 상태 안내로 대체
- ✅ **알림 탭 가능** — kind/ref_id 로드, 보호자→리포트, 러너→요청/캘린더 ('자세히 보기 ›' 표시)
- ✅ e2e cleanup이 양쪽 E2E 계정 러너를 online=false 처리 (추천 목록 오염 방지). 이미 떠 있는 E2E 계정 제거는 SQL 1줄: `UPDATE runners SET online = false WHERE profile_id IN (SELECT id FROM auth.users WHERE email LIKE '%daengrun.test');`

## 다음 실화(實化) 순서 (제안)

1. Supabase: auth + bookings + 상태 머신 → 수락 알림이 진짜가 되는 지점
2. react-native-maps + expo-location → 지도·트래킹 실화
3. Expo Notifications → 알림 센터 실화
4. Realtime 채팅
5. 결제 (파일럿은 계좌이체/수기로도 가능)
