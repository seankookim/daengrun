# SESSION HANDOFF — 2026-08-04b (가용성 게이팅 0054 · 5-에이전트 2라운드 · 마켓플레이스 정직성)

Companion docs: `docs/audit-2026-08-02.md` (감사 대장), precision-director skill (`.claude/skills/precision-director` — installed, READ AND FOLLOW).
Opener for next session: **"read docs/session-handoff.md fully, then continue"**.

## 1. Goal & current state
daengrun (도그스하이) — RN/Expo + Supabase dog-running marketplace, 반포 pilot. This session (precision-director full cycle):
- **0054 availability gating: DONE** [verified-now: harness 216/216 + UPGRADE OK, container] — `runners_available_for(p_booking)` security-definer RPC = 수락 게이트의 표시측 거울 (같은 공식 km*8+25 분수보존 · LIVE 4종 · ±6h 창 · 반열림 엄격 · 자기 부킹 제외). 소유자 게이트(not_owner, 부재=타인 구별불가) + **상태 게이트(payment_hold|matching|runner_pending → 아니면 not_open)** + `search_path = public, pg_temp` + **bookings_km_positive check (km>0) not valid**.
- **matching.tsx가 RPC 소비** (fresh+rebook) + 로딩/오류/빈 상태 3분리 + 재시도 버튼 + 정직한 빈 카피. schedule.tsx 액션 게이트 rawStatus 기반(변경요청=confirmed만 · 러너변경=matching|runner_pending만 · enroute=정직 한 줄+취소 숨김 · cancelled=액션 없음), open() 매칭중 Alert는 pending만.
- **transition-booking 엣지 fn**: accept-409가 충돌 일정 시각을 지목(KST UTC+9 산술, 종료 분올림, 자정 넘김 날짜 병기, .neq 자기제외, .order 결정적) + 이미 수락한 예약 재탭 = unchanged + **request_runner에도 동일 busy 게이트**(상태 판정 먼저, 보호자에겐 시각 비노출). **NOT DEPLOYED — Sean §7.**
- 5-에이전트 사이클 2라운드 실적: R1(negative-km 게이트 무력화 P1, pg_temp 섀도잉 P2, draft 프로브 집계 오라클 P2 — 전부 실행으로 실증) · R2(runner_enroute 죽은 버튼, 취소-매칭중 거짓말, auto-nominate 무방비 등). 전부 수리, 재검 클린.
- Branch `redesign-v4`. 이전 세션 커밋까지 push됨(ab7fca4). 이 세션 커밋은 아래 §7 참조.

## 2. Standing doctrines (Sean's invariants — outlive any task)
- Big UI decisions → HTML mockup lab first → Sean picks by number. Labs: 340px frames on #1C1837.
- precision-director protocol: fable directs, opus executes, **boss-verify every agent claim with own greps/runs**. Migrations: 하네스 게이트 + 5-agent adversarial (리뷰어는 RLS 경로 실행으로 반증) — 이번에도 매 라운드 P1/P2 검출.
- Commit gate: device `tsc --noEmit` + `node scripts/check-rpc-contracts.mjs`. Never claim device-visual success — Sean smoke-tests.
- Lilac tokens only; coral-text law; night #1C1837; fonts Black Han Sans(1/screen)+Oswald(lineHeight≥1.2×)+IBM Plex Sans KR; detail ≥12pt; buttons big when space allows; no dead/mislabeled buttons; no fabricated data — bind real fields or omit.
- **새 법(이번 세션): definer 함수는 `set search_path = public, pg_temp`** (미명시 시 pg_temp 우선탐색 → 섀도잉 우회. 기존 38개 definer 함수는 0055+ 일괄 ALTER 후보). **add constraint는 가드 DDL**(duplicate_object 무시 — 재적용 중도사망 방지). **당사자 게이트 뒤에 상태 게이트**(무료 draft 프로브가 집계 오라클이 되는 것 차단).
- 홈 = 루트; 0042 뷰 = 오픈풀 유일 읽기 경로; enforce_booking_transition·owner-home morph·matching 2층 컴포지터 DO-NOT-REFACTOR.

## 3. Working-relationship norms
- Sean 실기기 스크린샷 리포트 — his complaints are precise, trust them over agent claims. Honest ship/no-ship; "is X real?"엔 증거로 답. Approvals short, picks by number. 응답 영어, 코드주석·커밋 한국어. 커맨드는 주석 없는 명시 목록.
- 세션 중 "what's taking so long" 2회 → 진행 중엔 짧은 정직 상태 보고, 사이클은 유지하되 라운드 수 절제.

## 4. Decision log (what & why)
- 가용성 정의 3종 공존, 통합 금지 (0054 헤더에 박제): 0015 뷰(find-now '지금') · 0003 is_slot_available(슬롯 규칙 엔진 — reschedule/hold가 사용) · 0054 RPC(특정 부킹의 지명 화면 = 수락 게이트 거울). is_slot_available을 0054에 쓰면 표시가 서버보다 엄격 → 공급 증발.
- LIVE 4종만 점유 (runner_pending 미점유 — 수락 게이트와 동률). 클럽 위탁은 배정되면 같은 bookings LIVE로 자동 점유, 확약-미배정은 미점유 (수락 게이트와 동일, 의도).
- 분수 보존 `(km*8+25)||' minutes'` 형 — `::int` 형(0044/0053 dog-clash 계열)은 초 절삭으로 거울 깨짐. dog-clash 계열의 기존 절삭은 별개 게이트라 미수정 [from-history].
- 상태 게이트에 payment_hold 포함: 결제 확정 직전 매칭 화면 도달해도 안 죽게. 지명 CAS는 어차피 matching|runner_pending만.
- request_runner busy 게이트는 스토어프런트 필터(online/tier) 없음 — 오프라인 선호 러너 지명은 정당 (의도적 비대칭, 주석 박제).
- 보호자에게 타 러너 충돌 시각 비노출 (러너 본인에게만 자기 일정 시각 노출) — 0054 반환 원칙과 동일.
- limit 10 + total_runs desc 서버 고정 = 기존 '임의 10'을 결정적으로 바꾼 것. 신인 러너 기아 문제는 **Sean 제품 판단 대기** (§9).
- rawStatus를 Booking에 추가(옵셔널) — 표시 어휘 6종이 뭉갠 서버 상태를 액션 게이트가 씀. STATUS_MAP에 refund_pending→'cancelled' 추가.
- minjun 목업 runnerId 제거 (실 uuid 또는 ''), 주입 러너 paceSec 420 박제 → 실측(p.paceSec, RunnerPublicProfile에 필드 추가).

## 5. Architecture & contracts (tricky, DO-NOT-REFACTOR)
- 이전 세션 목록 전부 유효 (0047 트리거, 0042 뷰, owner-home morph, Oswald lineHeight, git lock mv 의식, stage 캐시 md5 대조, .claude 설치는 installer, 컨테이너 supabase.co 차단, device_bash 네트워크 없음).
- 하네스: 컨테이너 /tmp/daengrun/supabase, tar(md5)로 재구축, PG 시작은 같은 Bash 호출 안. **현재 216케이스** (97_availability_suite V1–V14 추가: 거울동률 property·분수보존·반열림·상태게이트·km제약·권한 4종·반환형상 9컬럼·정렬determinism). upgrade_check.sh도 'avail' 단언 (3곳 필터).
- 97 스위트는 runners.online을 전역 mutate (t_av_only_online) — **97 뒤에 새 스위트 붙이면 online 의존 금지** 또는 스냅샷/복원.
- V6는 사용자 계약 핀(리북에서 현 지명자 유지) — 상태 게이트 도입으로 '자기충돌'은 구조적으로 불가능해져 c.id<>p_booking은 방어선.
- check-rpc-contracts: rpc는 리터럴 이름+인라인 객체로만 호출해야 게이트 통과 (`supabase.rpc('runners_available_for', { p_booking: … })`).

## 6. File map (this session's surface)
- `supabase/migrations/0054_availability_gating.sql` — NEW (헤더에 왜/3정의/게이트 설계 전부 박제).
- `supabase/tests/97_availability_suite.sql` — NEW · `harness.sh` +1줄 · `upgrade_check.sh` 97 실행+avail 필터.
- `supabase/functions/transition-booking/index.ts` — accept 409 지목·재탭 unchanged·request_runner busy 게이트. **미배포.**
- `app/src/lib/api.ts` — fetchAvailableRunnersFor(+토큰 번역) · STATUS_MAP refund_pending · rawStatus · paceSec · minjun 제거.
- `app/app/owner/matching.tsx` — RPC 소비, 로딩/오류/빈 3상태, auto-nominate 실패 Alert, 주입 paceSec 실측.
- `app/app/owner/schedule.tsx` — rawStatus 게이트, enroute 한 줄, cancelled 한 줄, open() pending만.
- `app/src/store.ts` — Booking.rawStatus?: string.

## 7. Pending on Sean's side (ordered)
1. `supabase db push` — 0051/0052/0053(이전, 상태 미확인) + **0054**. 하네스 216/216 + 업그레이드 경로 green.
2. `supabase functions deploy transition-booking` — CAS + 409 지목 + request_runner busy 게이트, 전부 이것 전엔 INERT.
3. `git push` (redesign-v4).
4. Device smoke: 매칭 로스터(가용만 노출·빈/오류/재시도), 러너 변경(runner_pending에서), 일정 시트 상태 매트릭스(confirmed/pending/enroute/cancelled), 수락 409 메시지(시각 지목), 자동 지명 실패 Alert.

## 8. Known bugs / gotchas
- 5pm accept-409 미스터리: 이제 409가 충돌 일정을 지목하므로 배포 후 재현 시 원인 자동 판명 [deploy 대기].
- matching.tsx roster 최대폰트 클리핑 [uncertain — 기기]. `.fuse_hidden*` 파일 무시. my.tsx MRZ/✎ <11pt 예외 유지.
- no_show·incident_review는 여전히 표시 'pending' 폴백 (러너 변경은 rawStatus 게이트로 이제 안 뜸; 배지 어휘만 남음 — 별도 표시 낱말 필요, Sean 판단).
- 주입 경로(선호/현재 러너)는 바쁜 러너도 목록에 추가 가능 — 지명 시 서버 request_runner 409가 정직하게 막음 (의도된 잔여).
- draft.bookingId 모듈 전역 바인딩 (스택 중첩 시 이론상 stale) — 서버 게이트가 최종 방어, 코드 churn 회피 [accepted residual].

## 9. Ideas discussed, not built
- **NEXT 후보 1: definer 함수 38개 search_path 일괄 pg_temp 교정 (0055)** — ALTER FUNCTION ... SET search_path 일괄, 하네스 재활용. 위탁 보드·커스터디 게이트는 0054보다 민감한 페이로드.
- **NEXT 후보 2: server decline-log** (booking_declines 테이블 + 0042 뷰에서 거절자 제외) — runner home의 세션-로컬 declinedIds 대체. 리뷰 노트: 뷰 predicate에 `not exists (select 1 from booking_declines d where d.booking_id = b.id and d.runner_id = auth.uid())`, insert는 declineBooking 래퍼가 RPC로. 마이그레이션+하네스+5-agent 필요.
- limit 10 신인 러너 기아 — 슬롯 예약(8 경력 + 2 신인) or 페이지네이션, Sean 제품 판단.
- ±6h 프리필터 사각 (km>41.9 충돌 불가시 — 수락 게이트와 동일하게 눈멂, 양쪽 동시 수정해야 거울 유지) [inherited, both-sides].
- §3b 사진 비공개 버킷 (대공사) · W4 필름스트립 fitness hero · 안무 4종 기기 리뷰 · 러너 월간/누적 수익 + D-day/미확인 배지 RPC.

## 10. Next 1–3 steps
1. [read-only] §7 실행 여부 확인 (db push 0051-0054·deploy·git push) — 컨테이너에서 원격 확인 불가, Sean에게 물을 것.
2. [needs-harness] 0055 search_path 일괄 교정 or decline-log — 둘 다 5-agent 사이클. 하네스 재구축부터 (tar→md5→216 green 확인).
3. [design] no_show/incident_review 표시 어휘 + limit 10 정책 — Sean 판단 받고 소규모 클라 패스.

## 11. Verification commands
Read-only: `git -C /Users/sean/dev/daengrun log --oneline -8` · `git status --short` · device tsc `cd app && ./node_modules/.bin/tsc --noEmit` · `node scripts/check-rpc-contracts.mjs` · container harness `cd /tmp/daengrun/supabase/tests && runuser -u postgres -- bash harness.sh 2>&1 | tail -6` (expect 216/216).
Expensive/destructive (Sean only): functions deploy, db push, git push.
