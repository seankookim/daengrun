# 세션 핸드오프 — 2026-07-29 (v3, 대규모 UI 업히벌 + 하이클럽 P-B 완결 세션)

> **먼저 읽을 동반 문서**: `docs/hi-club-plan.md` (하이클럽 v2.1 확정 스펙), `docs/todo.md` (전체 작업 목록),
> `docs/design/final-system-lab.html` (V4 디자인 시스템 — 6규칙 합의본), `docs/design/app-upheaval-lab.html` (V1/V2/V3 원안),
> `docs/design/club-customer-flow.html` (보호자 클럽 여정 레플리카). 이전 핸드오프 내용은 이 파일이 대체한다.

---

## 1. 목표 & 현재 상태

도그스하이(DOGS HIGH, repo daengrun) — 러너가 고객의 강아지를 뛰어주는 반려견 피트니스 마켓플레이스.
RN/Expo + Supabase. Sean 솔로 테스트 중 (호스트 계정 1개).

**워크스트림 상태**:
- **V4 전면 리디자인** [verified-now]: `redesign-v4` 브랜치에 5커밋 (90b909d→a57860d). Sean: "원래보다 훨씬 좋다".
  main 머지 전 — Sean 실기기 검수 대기. **진행 중**.
- **하이클럽 P-A + P-B** [verified-now]: 완결. 0030~0036 마이그레이션, 하네스 83/83.
  수요 보드·정기 시리즈·리캡 피드·입장권까지 구현.
- **컬러 리바이탈라이즈 P1~P5** [verified-now]: 전부 구현 (칼라 컬러·소인 잉크·기록 골드·배지 월드·샵 테라코타).
- **P-C (위탁 delegation)** [from-history]: 미착수. 스키마는 0030에 선행 존재 (session_runner_assignments).
- **실기기 클럽 풀루프 검증** [uncertain]: 두 번째(보호자) 계정으로 RSVP→체크인→리캡 미검증. 레플리카 HTML로 대체 중.

## 2. 불변 독트린 (Sean의 규칙 — 태스크보다 오래 산다)

- **정직 원칙**: 가짜 데이터·가짜 활동 연출 금지. 실데이터 있을 때만 렌더. 유령 클럽 금지 (collecting은 '대기'로만).
  첫 완주 팡파레 금지 (경신은 비교 대상 필요). 존재하지 않는 혜택 약속 금지.
- **하네스 게이트**: 마이그레이션은 db push 전 반드시 `supabase/tests/harness.sh` 통과 (현재 83 pass). 데이터 주도 기대값 (하드코딩 카운트 금지 — S10 교훈).
- **커밋**: 한국어 상세 메시지, tsc 클린 후 커밋, 커밋 후 git lock mv 리추얼 (§8). Sean이 push/deploy.
- **언어**: 대화는 영어, 코드 주석·커밋은 한국어.
- **명령어**: Sean이 실행할 명령은 항상 명시적으로 제공.
- **네이버 클라우드 시크릿**: 클라이언트 시크릿(3yobs...)은 절대 앱/레포에 금지 — 루트 .env 서버 전용. client id(3vpkxtglpe)는 app.json OK.
- **디자인 신규 표면**: 큰 UI 결정은 HTML 랩 먼저 → Sean 선택 → 구현.

## 3. 협업 규범 (새 팀원 브리핑)

- Sean은 음성 구술로 피드백 주기도 함 (두서없어 보여도 전부 의도 있음 — 요구 분해 필수). 가끔 GPT로 정리한 구조화 브리프.
- 미학 결정은 반드시 시각물로: "let's see it html first". 옵션 3~5개 + 추천 1개 형식 선호. 번호로 선택.
- 반복 패턴: 구현 → 실기기 확인 → 구체 미세조정 ("버튼 훨씬 크게", "1.2x", "더 왼쪽·위로"). 미세조정은 즉시 반영.
- 싫어하는 것: 파스텔·베이지·라운드 카드 수프·시스템 폰트·"AI스러운" 균질함·빕 넘버(은퇴됨)·작고 제네릭한 모듈.
- 좋아하는 것: 샤프 코너, 다크 콘트라스트(V2), 도장·티켓 모티프, 클럽 바이올렛, 워너웃 텍스처, 형광펜 하이라이트, 3D 하드섀도(절제), Oswald 숫자.
- 자율권: "go ahead in whichever order you like" 수준의 위임 자주. 단 방향 전환은 본인이 결정.

## 4. 결정 로그 (WHY 포함)

- **V4 디자인 6규칙** [verified-now]: ①본체=V1 화이트×잉크 룰·밴드 ②펀치=V3 (3D 하드섀도는 화면당 프라이머리 1개, 코랄=도파민, 형광펜=히어로 1곳) ③밤=V2 (라이브·클럽·샷스튜디오·입장권 — 낮/밤 스위치가 브랜드 리듬) ④소프트 예외=생명체와 도장만 원형 ⑤폰트 3단 (BHS 디스플레이/Oswald 숫자/IBM Plex Sans KR 본문/Mono 라벨) ⑥컬러맵 유지. — V1·V3 "너무 크리스프", V2는 "무조건 어딘가에" 절충 결과.
- **브랜치 전략**: redesign-v4 브랜치 — Sean이 "쉽게 돌아올 수 있게" 요청. `git checkout main` = 원복.
- **토큰 혁명 방식**: cream 값을 #FFFFFF로 바꿔 (이름 유지) 전앱 일괄 디베이지 — 화면별 수작업 대신. 위험 대비 리터럴 스윕 병행.
- **컬러맵**: 볼트=개인/브랜드, 코랄=긴급·도파민, 앰버=대기, 블루=완주, 바이올렛=클럽(C1 선택 — 틸은 볼트와 혼동, 베리는 코랄과 경쟁), 골드=기록(희소 운용), 테라=샵, 칼라 8색=강아지 퍼스널.
- **러너 발견**: 전용 탭 기각 (예약 인접 행동을 분절) → 홈 피처드+로스터 → runner-profile 강화 예정.
- **레이더=코랄**: 볼트 그리드에서 전환 — "퍼플의 보색 에너지" (Sean 지시).
- **하이클럽 핵심 불변식**: 혼합 이벤트 + 모든 강아지에 명시적 책임자 1명 (세션 분리 아님 — ChatGPT 비평 수용).
  P-C는 "스키마 확장이지 재설계 아님". 유령 클럽 금지. RSVP=멤버십. 리캡은 체크인 1팀+만.
- **기록 감지 = runs 트리거** (0034): settle_run_tx 재작성 대신 — 정산 트랜잭션 안에서 커밋되면서 함수 중복 없음.
- **club_session_detail 정렬** (0036): created_at 타이는 호스트 우선 — 하네스 DO 블록은 단일 트랜잭션이라 now() 동일 → 정렬 불안정 발견이 계기.
- **완료 카드 도장 = T3 원형 소인 84px 인플로우** — 앱솔루트는 겹침 사고, 인라인은 원천 차단. 패치 3K 네온 서클은 완료 카드에서 은퇴 (Sean: "don't add that").
- **빕 넘버 은퇴**: 명부는 아바타+이름, 입장권 BIB 박스 → TEAMS n/cap ("they look awful").

## 5. 아키텍처 & 계약

- **마이그레이션 0030~0036** [verified-now]: 0030 클럽 코어 / 0031 검색·리캡·스탯 / 0032 club_demand_board() / 0033 dogs.collar / 0034 기록 트리거(_detect_dog_records, kind='reward') / 0035 클럽 정기 시리즈(크론 club-series-gen 매시 20분, 72h 창·2h 통보·±1h dedup) / 0036 session_detail isMe.
- **하네스**: `supabase/tests/harness.sh` — PG16 로컬, 전 마이그레이션 제로 적용 + 10/20/30/40 스위트 = 83케이스.
  컨테이너에서 root 불가 → `runuser -u postgres -- bash harness.sh`. 미러: /tmp/daengrun/supabase (컨테이너).
- **클럽 쓰기 = RPC 전용** (테이블 직접 쓰기 정책 없음). 참가자 이름은 SECURITY DEFINER 경유.
- **settle-run 신뢰 경계**: km 클램프 0..planned×2+2, 완주 판정 = planned의 50%+.
- **폰트 로딩 문법** (DO-NOT-REFACTOR): displayFont.ts/fonts.ts — 지연 로드 + 실패 시 조용한 시스템 폴백 (구빌드에서 크래시 금지). 훅이 null 반환하면 스타일 배열에서 무시됨.
- **HeatTrace tint prop**: 있으면 히트 그라디언트 대신 단색 (칼라 컬러·코스 월드용).
- **worldOf(km)** (patch.tsx): 거리→색 세계 단일 소스 — 패치와 코스 카드가 공유.
- **V4 나이트 토큰**: nightBg #0D0A1E · nightCard #14102B(클럽)/#121712(러너) · nightEdge #2A2350 · nightDim #8F86C2 · neon #9F8FFF.
- **noti_kind 이넘**: booking/community/shop/safety/reward/system — 'record' 없음, 기록은 reward 재사용 (이넘 수술 회피).
- **알림 소인 잉크**: alerts.tsx inkFor(kind,title) — 제목 휴리스틱 (경신/달성/돌파=골드 등).

## 6. 파일 맵 (이 세션 접촉분, 역할 1줄)

앱:
- `app/src/theme.ts` — V4 토큰 전부 (페이퍼·나이트·클럽·골드·테라·칼라 8색·radius 6/6/4·폰트 상수)
- `app/src/lib/fonts.ts` — useNumFont/useBodyFont (Oswald·Plex KR 지연 로드)
- `app/src/components/clubcard.tsx` — 클럽 홈 모듈 전체 (검색·나이트 배너·수요 티켓/스트립/리그·워너웃 직인)
- `app/src/components/patch.tsx` — 배지 월드 (worldOf + 등급 재질)
- `app/src/components/CourseStrip.tsx` — 코스 월드 카드 (월드 톤 트레이스)
- `app/src/components/ui.tsx` — StatBlock Oswald 승급
- `app/app/owner/home.tsx` — 룰드 스탯 셀·코랄 레이더·스타디움 로스터 (1200줄, 모핑 히어로 주의)
- `app/app/owner/schedule.tsx` — 밴드+T3 소인+공유 행 (Sean이 현상 유지 지시 — 큰 변경 금지)
- `app/app/community.tsx` — 스트라바 스탯 바·바이올렛 리캡 스텁·칼라 도트
- `app/app/my.tsx` — 도메인 잉크 메뉴
- `app/app/shop.tsx` — 테라코타 부티크 (현상 유지 지시)
- `app/app/alerts.tsx` — 소인 잉크 시스템
- `app/app/club/[id].tsx`, `club/session/[sid].tsx`, `club/pass/[sid].tsx` — 바이올렛 나이트 월드 + 입장권
- `app/app/owner/dog.tsx` — 칼라 컬러 피커
- `app/app/runner/requests.tsx` — 수요 스트립(R1-C)
- `app/src/lib/api.ts` — 클럽/수요/시리즈/칼라 API (주의: 디바이스에서 직접 python 편집한 파일)
- `app/src/lib/push.ts` — reward/community 딥링크 라우팅

디자인 랩 (docs/design/): final-system-lab, app-upheaval-lab, club-premium-lab, club-customer-flow, color-vitalize-lab, club-color-lab, demand-board-lab, schedule-stamp-lab, club-stamp-lab, club-emphasis-lab, glowup-lab, hi-club-lab.

## 7. Sean 쪽 대기 사항

- **[needs-user] npx supabase db push** — 0032/0033/0034/0035/0036 적용 여부 [uncertain] (0030·0031은 적용됨 [from-history]). 클럽 수요보드·시리즈·기록·입장권은 push 전엔 무데이터.
- **[needs-user] git push** — main + redesign-v4 둘 다.
- **[needs-user] 리디자인 검수** — redesign-v4 실기기 (npm install 완료 확인됨 [verified-now]). 만족 시 main 머지: `git checkout main && git merge redesign-v4`.
- **[needs-user] 두 번째 계정** 클럽 풀루프 검증 (RSVP→입장권→체크인→종료→리캡 피드).
- KIPRIS 상표 수동 확인 (todo §E) [from-history].

## 8. 환경 함정 (반드시 숙지)

- **디바이스 git lock**: 커밋마다 `.git/index.lock`·`tmp_obj_*`가 unlink 불가로 남음 → 커밋 후 `mv`로 `_to_delete/git-locks/`에 치우는 리추얼 필수 (rm 불가, mv만 가능). 커밋 전에도 lock 존재 확인.
- **스테이징 캐시 부패** ⚠⚠: device_stage_files가 **간헐적으로 구버전을 반환** (md5 불일치 — api.ts·theme.ts·shop.tsx에서 실제 발생). **모든 편집 전 디바이스 md5와 대조**. 불일치 시 디바이스에서 python heredoc으로 직접 편집. 이 함정이 과거 스윕 롤백 사고(df66d94)의 원인.
- **/tmp 컨테이너 미러**: /tmp/daengrun — 부분적·구버전 가능. 신뢰 금지, md5 검증 후 사용.
- **하네스는 컨테이너에서**: root 불가 → runuser -u postgres. .pgtest 잔존 postmaster 죽으면 rm -rf .pgtest 후 재실행.
- **tsc는 디바이스에서**: `cd app && npx tsc --noEmit` (체이닝 금지).
- **RN 제약**: Row 컴포넌트 style은 배열 불가 (스프레드로) · StyleSheet.absoluteFillObject 타입 에러 이력 (명시 position 사용) · 그라디언트 라이브러리 없음 (solid+glow로 대체) · rn-svg strokeDashoffset 애니메이션은 JS 드라이버.
- **하네스 DO 블록 = 단일 트랜잭션**: now() 동결 → created_at 타이브레이크 필요했던 이유.

## 9. 논의됐지만 미구현 아이디어

- **V4 잔여**: 홈 마스트헤드+잉크 룰 히어로, 형광펜 하이라이트("오늘도 <하이> 찍자"), 3D 코랄 CTA (슬라이더는 샤프만 됨), 본문 폰트(Plex KR) 전화면 롤아웃, request/report/live/shot 스튜디오 V4 패스, 클럽 페이지 D1 마스트헤드. Sean: "later later i want to ask you again to show me this style in other screens".
- **runner-profile 강화** — 피처드 러너의 목적지, "athlete page"로 (러너 PR 흐름의 2단계).
- **P-B 폴리시 잔여**: 클럽 패치 시각화(사다리 재사용), 스토리/카카오 공유 포맷(인증샷 파이프라인).
- **P-C 위탁**: 기존 예약+session_id 확장 방식. 하네스 시나리오 의무. 시작 전 hi-club-plan.md 재독.
- **P3 골드 UI면**: 리포트 PB 히어로·피드 마일스톤 카드 (감지는 0034로 완료, 표면 미구현).
- **수요 보드 임계 10팀**: 프로덕트 상수 — 도달 시 "호스트 모집 시작"의 실제 동작(알림? 러너 브로드캐스트?) 미정의.
- **커뮤니티 컴포저**: "+ 자랑하기" 진입점 논의만 (현재 공유는 일정 탭 경유).

## 10. 다음 1–3 스텝

1. **[needs-user→read-only]** Sean 실기기 검수 결과 수취 → 미세조정 (예상 쟁점: 코랄 레이더 vs 바이올렛 클럽 공존, 피처드 러너 1명일 때, Oswald×한글 조화).
2. **[local-edit]** V4 잔여 화면 패스 (§9 첫 항목) — Sean이 "show me this style in other screens" 요청 시 랩 먼저.
3. **[needs-deploy]** 검수 통과 시 main 머지 + db push 전체 + 클럽 풀루프 2계정 검증 안내.

## 11. 검증 명령

읽기 전용 (안전):
```bash
# 디바이스 (device_bash, cd /sessions/<sess>/mnt/daengrun)
git branch --show-current && git log --oneline -8
cd app && npx tsc --noEmit
md5sum app/src/lib/api.ts app/src/theme.ts   # 편집 전 스테이징 검증용
# 컨테이너 (Bash)
cd /tmp/daengrun/supabase/tests && chown -R postgres:postgres .. && runuser -u postgres -- bash harness.sh 2>&1 | tail -3
```
파괴적/비용 (Sean 승인 후):
```bash
npx supabase db push      # 0032~0036
git checkout main && git merge redesign-v4   # 검수 후에만
rm -rf .pgtest            # 하네스 리셋 (컨테이너)
```
