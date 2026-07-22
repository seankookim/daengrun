# 백엔드 (Supabase) 셋업 가이드

스키마는 `supabase/migrations/`에 버전 관리됨. 모든 테이블은 목업 화면에서 도출 (feature-audit.md 참조).

## 1. 프로젝트 생성 (Sean이 직접, ~5분)

1. https://supabase.com → New project (org: 개인, region: **Northeast Asia (Seoul)**, 무료 플랜)
2. 프로젝트 생성 후 Settings → API에서 두 값 복사:
   - Project URL → `EXPO_PUBLIC_SUPABASE_URL`
   - anon public key → `EXPO_PUBLIC_SUPABASE_ANON_KEY`
3. `app/.env`에 붙여넣기 (`.env.example` 참고)

## 2. 스키마 적용 — 두 가지 방법

**A. CLI (권장 — 마이그레이션 히스토리 유지)**
```bash
cd ~/dev/daengrun
npx supabase login              # 브라우저 인증
npx supabase link --project-ref <프로젝트 ref>   # dashboard URL의 xyz 부분
npx supabase db push            # migrations/ 순서대로 적용
```

**B. 대시보드 (빠른 확인용)**
SQL Editor에 `0001_init.sql` → `0002_rls.sql` 순서로 붙여넣고 실행.

## 3. Kakao 로그인 켜기

1. https://developers.kakao.com → 앱 생성 → REST API 키 확보
2. 카카오 로그인 활성화, Redirect URI에:
   `https://<프로젝트ref>.supabase.co/auth/v1/callback`
3. Supabase → Authentication → Providers → Kakao: REST API 키(Client ID) + Client Secret 입력
4. 앱 딥링크: `daengrun://` scheme은 app.json에 이미 있음 (`scheme: "daengrun"`)

## 4. 로컬 개발 (선택)

```bash
npx supabase init   # 이미 supabase/ 있으므로 config만 생성됨
npx supabase start  # Docker 필요 — 로컬 DB + Studio
npx supabase db reset  # migrations + seed.sql 적용 (초코 세계)
```

## 5. 타입 생성 (스키마 적용 후)

```bash
npx supabase gen types typescript --linked > app/src/lib/db-types.ts
```

## 설계 결정 요약

- **상태 전이는 DB가 강제** — `enforce_booking_transition` 트리거가 calendar.md 상태 머신 외 전이를 거부. 클라이언트 버그가 데이터를 오염 못 시킴.
- **공동현관 비번**: `gate_code_enc` 암호문만 저장. 러너는 직접 select 불가(RLS) — 세션 중 security definer 함수로만 복호 (Phase 2), 열람은 `gate_code_access_log`에 기록.
- **리뷰 가시성**: `platform_only` 행은 작성자 외 아무도 못 읽음 (미고지 문제 신고).
- **돈은 서버만 쓴다**: ledger/payouts/miles에 클라이언트 insert 정책 없음 — Edge Function(service role) 전용.
- **완주율**: `dog_condition` 종료는 completion_rate에 미반영 (제품 원칙이 스키마 주석으로).

## Phase 2 (다음 백엔드 세션)

- Edge Functions: `create_booking_hold` (원자적 슬롯 홀드), `transition_booking`, `settle_run` (사유별 정산 계산), `roll_drop` (5/10회 판정 + 확률)
- 가용성 조회 뷰 (rules − exceptions − bookings − holds − travel buffer)
- Realtime: chat_messages, bookings.status 구독
- 앱 연결: 로그인 화면 + store.ts를 쿼리로 교체 (화면 하나씩)
