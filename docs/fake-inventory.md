# 목업/페이크 전수 인벤토리 (2026-07-23 현재)

전 화면·전 버튼 스캔 결과. 분류: 🔴 정직성 버그(실화면에 영향) / 🟡 목업 요소(라벨됨/무해) / ⚪ 의도적 목업 존(파일럿 후).

## 🔴 이번 스캔에서 발견된 버그 (즉시 수정)
1. **runner/run.tsx — 목표 거리가 목업 상수** — `req = runRequests[0]` (mock 5km)를 진행바·자동완주 임계·수익 미리보기에 사용. 실예약이 3km면 5km에서 자동완주 → 진행/완주 판정 틀림. 강아지 이름·채팅핀 인용문("자전거도로만…")도 목업. → fetchMeetupInfo로 실데이터화.
2. **owner/schedule.tsx — 취소가 서버 미호출** — '취소하고 환불받기'가 목업 알럿만 띄우고 예약은 살아있음. 서버 cancel_owner(수수료 계산 포함)는 존재하는데 UI가 안 부름. → 실호출 연결.

## 🟡 목업 요소 (실코어 화면 안의 부분 목업 — 대부분 라벨됨)
| 위치 | 내용 | 해소 시점 |
|---|---|---|
| 양쪽 meetup + runner/run + runner home 길찾기 | 픽업 좌표·주소 하드코딩(서울숲/뚝섬로 273) | 주소 실화 세션 |
| owner/meetup, runner/meetup, live(데모분기), run | 지도 배경 = 장식용 도트/도로 그림 | 리빌드 후 MapView 확대 적용 |
| owner/live (실모드) | '사진 요청'·'휴식 요청' 버튼 = 목업 알럿 | 러너측 수신 UI와 함께 |
| owner/home 체력나이 칩 | ▼delta가 mock dog.age 기준 | 강아지 생일 기반으로 교체(소) |
| runner/done 드랍 카드 | 노출 조건이 mock rewardStatus (%5) — 실드랍은 settle 응답 알럿이 담당 | 리워드 센터 실화와 함께 |
| runner/review 표시명 | req 목업 이름 (저장은 실동작) | fetchMeetupInfo 재사용(소) |
| request '반복 예약' 칩 | 준비 중 라벨 | 반복 예약 기능 |
| request '요금 상세 접기 ⌃' | 장식(접히지 않음) | 소소 — 제거 or 구현 |
| availability '예약 규칙' | 준비 중 라벨 (서버 함수는 rest buffer 등 일부 사용 중) | 규칙 편집 실화 |
| chat '안심 통화' / profile '채팅 문의' | 준비 중 라벨 | 통화 마스킹 서비스 |
| alerts markAll 실패 폴백 문구 '(데모)' | 오해 소지 문구 | 소소 |
| schedule 시트 '예상 러닝 ~65분' 등 | 고정 추정치 | 실통계 축적 후 |
| 결제 전체 | 시뮬레이션 (서버 가격·원장은 실) | PG (docs/payments.md) |

## ⚪ 의도적 목업 존 (파일럿 후 실화 — 진입은 가능하되 전부 목업)
- **shop.tsx** — 상품·장바구니 전부 목업
- **cards.tsx** — 콜렉터블 카드 컬렉션 목업 (myCards)
- **runner/rewards.tsx** — 리워드 센터 목업 (실데이터: drops·miles_ledger 존재, 미연결)
- **runner/apply.tsx** — 러너 지원/인증 퍼널 목업 (KYC 세션)
- **safety.tsx** — SOS·긴급연락처·체크리스트 목업 (알럿 스텁)
- **owner/addresses.tsx** — 주소 목록·추가 목업
- **owner/pay.tsx** — 러닝 후 결제/팁 화면 (데모 라이브 경로에서만 도달)
- **runner/detail.tsx** — 명시적 '데모' 카드
- **owner/live 데모 분기** — 예약 없이 진입 시의 연출 (실분기는 실동작)

## 실화 완료 (목업 없음)
login(OTP) · index · owner/home 코어 · request 코어 · matching · schedule 코어 · meetup 코어 ·
live 실분기 · report · review · fitness · dog · runner-profile · availability 코어 · runner home ·
requests · calendar · earnings · run 코어(GPS) · done 코어 · chat · alerts · community · leaderboard · my
