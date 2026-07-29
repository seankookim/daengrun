# 하이클럽 마스터 플랜 v2 (2026-07-29 — 외부 비평 반영 개정)

정본. v1 대비: ChatGPT 비평을 검토해 8건 수용·4건 반려, Sean 재결정 2건 반영
(페이즈 순서 소셜 우선 전환 · 베타 핸들링 상한 min(2, 티어)).

## 1. 확정 UI 머지 (P0 — 클럽과 독립, 진행 중)
- 1-A 알림 = A1×A2 머지 ✅ 완료 (fb3e677)
- 1-B 러너 캘린더 = C1×C2 머지 ✅ 완료 (fb3e677)
- 1-C 커뮤니티 = 인스타 풀와이드 피드 + 더블탭 🐾 + 스트라바식 데이터 오버레이 — **다음 작업**.
  단, 비평 수용: 피드의 기본 공급원은 수동 포스트가 아니라 **완료 활동 자동 유입** (세션 리캡이
  베이스라인 콘텐츠, Phase B에서 합류). 수동 포스트는 보충.

## 2. 하이클럽 — 개정 설계

### 2-0. 불변 원칙 (신설 독트린)
- **한 세션에 소셜(보호자 책임)과 위탁(러너 커스터디)을 섞지 않는다** — 사고 시 책임이 모호해지는 구조 금지.
- **유령 객체 금지 확장**: 세션뿐 아니라 클럽도 — 활성 조건(호스트 확약 + 관심 임계) 전에는
  클럽 페이지 대신 '관심 등록 N명' 수요 수집 화면.
- **수요 수집 > 자동 생성**: 시스템은 수요를 모아 러너에게 제안만 한다. 세션 개설은 항상 사람.
- **활동 기록에 측정 출처 명시**: verified(GPS 위탁런) / self-reported / check-in-only —
  리캡 카드에 구분 표기 (측정 사칭 금지의 스키마화).
- 위탁 그룹런 인계는 **고정 미팅 포인트 단일 창구** — 개별 가정 픽업 금지 (경제·지연 전파 문제).
  프리미엄 픽업 애드온은 후순위.

### 2-1. 행동 규칙 (v1에서 답해두는 것 — 비평 수용)
- 왜 가입하나: 정기 시리즈 RSVP 권한 + 멤버 우선 슬롯 + 클럽 패치/스트릭. '팔로우 버튼'이 아님.
- 왜 돌아오나: 리텐션 단위는 클럽이 아니라 **정기 시리즈** (토요 아침 3km 같은). 리캡 안에
  다음 세션 RSVP가 박혀 있어 '함께 완주 → 다음 주 약속'이 한 탭.
- 호스트 자격: v1은 인증 러너만. 호스트 신뢰 카드 = 세션 N회 · 출석률 · 재방문 멤버 수 ·
  무사고 — 팔로워 수가 아니라 검증된 로컬 신뢰가 클라우트.
- 호스트 잠적: 시리즈 자동 일시정지 + 멤버 알림 + 운영(=Sean) 개입. 소유권 이전은 P-D.
- 강아지 승인: 소셜런은 자유 참가(보호자 책임 + 동의문), 위탁런은 호스트 사전 승인 필수.
- 공개 범위: 클럽 페이지·리캡 요약은 공개, 참가자 상세·세션 채팅(후순위)은 멤버 한정.
  사진은 동의 기반 (기존 사진 동의 갤러리 백로그와 통합).

### 2-2. 스키마 (개정 — 참가 역할 명시 모델)
```
clubs               id, name, district, kind('official'), photo_url, description, status('collecting'|'active'),
                    host_profile_id, created_at          -- v1은 official 단일, 유저 생성은 P-D(자격 해금)
club_interest       club_id?, district, profile_id, desired_window jsonb, created_at   -- 수요 수집
club_members        club_id, profile_id, role('host'|'member'), joined_at
club_series         id, club_id, title, recurrence_rule jsonb, default_route_id, pace_band,
                    participation_mode('social'|'delegated'), capacity, host_profile_id   -- 리텐션 단위
club_sessions       id, club_id, series_id?, host_profile_id, scheduled_at, route_id,
                    meetup_point, mode('social'|'delegated'), capacity, min_attendance,
                    status('open'|'full'|'done'|'cancelled')
session_participants id, session_id, profile_id, dog_id?, role('host_runner'|'owner_attending'|
                    'runner_attending'|'delegated_dog'), responsible_profile_id, booking_id?,
                    approval('auto'|'pending'|'approved'|'rejected'), attendance('rsvp'|'checked_in'|'no_show'),
                    waiver_version, checked_in_at
participant_activities id, session_id, participant_id, km?, pace?, duration?, source('gps_verified'|
                    'self_reported'|'checkin_only'), run_id?, photos, created_at   -- M3 리캡 카드의 원천
```
- 위탁 강아지 = 기존 booking (session_id 링크) — 돈·보험·정산 단위 유지 (비평도 이 구조엔 동의).
- **세션 오케스트레이션 레이어는 신규 로직임을 인정** (v1 주장 정정): 호스트 취소 → N부킹
  원자 취소/환불, 최소 인원 미달 처리, 공유 GPS 트레이스 → N runs 팬아웃, 부분 이탈.
  Phase C의 본체이자 하네스 시나리오 추가 대상.

### 2-3. 수요 보드 (킬러 메커닉 승격)
- 보호자: "토 09:00 · 3km · 소셜/위탁" 희망 창 등록 (club_interest).
- 러너 홈: "이번 토 오전, 반경 내 4마리가 그룹런을 기다려요 → 세션 열기" — 실수요 CTA.
- 홈 모듈은 상태 인지형: 신규(탐색) / 멤버(D-2 커밋) / 러너(수요 공급) / 무유동성(관심 수집만,
  큰 빈 모듈 금지).

### 2-4. 가격 (Sean 결정 유지 + 프레이밍 수정)
- 위탁 베타 = 일반가 (1마리 세션 = 사실상 일반런으로 자연 강등 — 경제 붕괴 없음).
- 고객 가치 프레임 = 사회화·페이스 그룹·구조화된 운동. **'러너는 N배 번다'를 보호자 표면에
  노출 금지** (비평 수용). 그룹 SKU(할인+호스트 개런티)는 실 PG 마일스톤과 함께.

### 2-5. 안전 (개정)
- 위탁 베타 상한 = **min(2, 티어)** [Sean 재결정] — 티어 2/3/4 스키마는 유지, 베타 검증 후 해제.
- 사전 승인 + 고정 미팅 포인트 + 세션 분리(소셜/위탁) + 동의문 버전 기록(waiver_version).

### 2-6. 페이즈 (개정 — 소셜 우선 [Sean 재결정])
- **P0** UI 머지 (알림✅·캘린더✅·커뮤니티 피드 — 진행 중)
- **P-A 클럽 스파인 + 소셜런**: 성수동 공식 클럽(관심 임계 후 활성) · 클럽 페이지(M2 사진 배경)
  · club_series · session_participants(풀 역할 모델 — 마이그레이션 재작업 방지 위해 처음부터)
  · 소셜 세션 RSVP+체크인+동의문 · 수요 보드. 웨이트리스트·세션 채팅·날씨는 의도적 제외.
- **P-B 정체성/리텐션**: 자동 세션 리캡(M3 — participant_activities 원천, 인증샷 스튜디오
  파이프라인 재사용, 스토리/카톡 포맷) · 출석 스트릭 · 클럽 패치 · 리캡 내 다음 RSVP ·
  호스트 신뢰 카드 · 피드 자동 유입 합류.
- **P-C 위탁 그룹런 베타**: 사전 승인 · 고정 미팅 인계 · min(2,티어) · 세션 오케스트레이션
  (최소 인원·취소 팬아웃·트레이스 팬아웃 — 하네스 시나리오 필수) · 일반가.
- **P-D 확장**: 자격 해금형 유저 클럽 생성(참석 N회+호스팅 검증 — 시간 게이트가 아니라 획득형)
  · 코호스트 · 그룹 SKU · 동네 #2 · 클럽 대항전.

### 2-7. 비평 처리 로그 (감사용)
수용: 고정 미팅 포인트 / 세션 오케스트레이션 신규 인정 / 소셜·위탁 세션 분리 / 수요 보드 /
클럽 활성 임계 / 시리즈 = 리텐션 단위 / 참가 역할 모델·활동 출처 / 페이즈 역전 / 베타 캡 2 /
'N배 수익' 노출 금지 / 획득형 클럽 생성 / 상태 인지형 홈 모듈.
반려(사유): 그룹 SKU 즉시 설계(결제 모의 단계 — 스프레드시트 픽션, 1마리 세션은 일반런으로
자연 강등되어 경제 문제 없음) / 다변수 용량 모델(파일럿 YAGNI — 캡2가 실질 대체) / 비평의
Phase1 풀스코프(RSVP+웨이트리스트+채팅+날씨 = 이벤트 플랫폼 — 코어만 채택) / 전국 유동성
경고(원래 단일 동네 파일럿).
