// ═══════════ KST 벽시계 산술 (Asia/Seoul 고정) ═══════════
// 예약을 쓰는 화면 셋(owner/request · owner/reschedule · runner-profile/[id])이 공유한다.
//
// 왜 하나로 모았나 (2026-08-21 Sean, /plan-eng-review D4): 이 산술은 세 파일에 글자 그대로
// 복제돼 있었고, 그래서 .cjs 스위트가 닿을 수 없었다. E6 를 고칠 때 세 입구 중 둘만 고친 것도
// 같은 이유다 — 복제된 규칙은 한 곳만 고쳐도 티가 나지 않는다.
//
// ⚠ CLAUDE.md 의 "가용 정의는 의도적으로 3개의 서로 다른 술어 — 통합 금지" 와 충돌하지 않는다.
// 그 법은 **뜻이 다른 세 술어**를 지키라는 것이고, 이건 뜻이 하나인 산술 한 벌이다. (Sean 확인)
//
// 한국은 DST 가 없다. 고정 +9 산술로 충분하며, api.ts 의 kstWeekStartMs 와 같은 전제다.

export const KST_MS = 9 * 3_600_000;

export type KstCal = {
  y: number; m: number; d: number;
  /** 0=일 … 6=토 (KST 기준) */
  wd: number;
  h: number; min: number;
};

/** 어떤 시각의 KST 캘린더 조각. +9 로 민 뒤엔 UTC 파트가 곧 KST 파트다. */
export const kstCal = (ms: number): KstCal => {
  const k = new Date(ms + KST_MS);
  return {
    y: k.getUTCFullYear(), m: k.getUTCMonth(), d: k.getUTCDate(),
    wd: k.getUTCDay(), h: k.getUTCHours(), min: k.getUTCMinutes(),
  };
};

/** KST 벽시계(캘린더 날 + 시:분) → 실제 시각. 저장되는 instant 는 여기서만 만들어진다. */
export const kstInstant = (c: KstCal, h: number, min: number): Date =>
  new Date(Date.UTC(c.y, c.m, c.d, h, min) - KST_MS);

/** 날짜 칸 동일성 키 — toDateString() 은 기기 로컬이라 KST 날짜 칸과 어긋난다. */
export const kstKey = (c: KstCal): string => `${c.y}-${c.m}-${c.d}`;

// ── KST labels ────────────────────────────────────────────────────────────────
// Rendering helpers, so a screen never reads a server instant through the DEVICE clock.
// `new Date(iso).getDay()/getHours()` are local-timezone: on a phone that is not Asia/Seoul they
// print the wrong weekday and the wrong time. These take a KstCal so a caller pays for the
// arithmetic once and both lines are guaranteed to agree.
//
// api.ts's `kstParts()` used to build the same 「8월 26일 (화)」 vocabulary a second way — Intl with
// `timeZone:'Asia/Seoul'` and a device-local `catch` — behind 28 call sites. Since 2026-08-27 it is
// a two-line wrapper over kstDateLabel + kstAmPm, so there is exactly ONE arithmetic left. Anything
// NEW belongs here: this is the copy the .cjs suite can reach, and it has no Intl dependency, so a
// build whose Hermes ignores `timeZone` cannot change a single character it prints.
const WD_KO = ['일', '월', '화', '수', '목', '금', '토'];

/** 「8월 26일」 — month/day with no weekday. Three screens print a bare date (설정·베이스 핀의
 *  can_change_at, 리포트의 후기 등록일) and a weekday there is noise, not information. */
export const kstMonthDay = (c: KstCal): string => `${c.m + 1}월 ${c.d}일`;

/** 「8월 26일 (화)」 — the product's standing KST date vocabulary. Built ON kstMonthDay rather
 *  than beside it: these two drifting apart is the same duplication kst.ts exists to end. */
export const kstDateLabel = (c: KstCal): string => `${kstMonthDay(c)} (${WD_KO[c.wd]})`;

/** 「19:00」 — 24h KST wall clock. Unambiguous at a glance, which a ticket needs more than 오전/오후. */
export const kstClock = (c: KstCal): string =>
  `${String(c.h).padStart(2, '0')}:${String(c.min).padStart(2, '0')}`;

/** 「오전 7:05」 · 「오후 12:30」 — 12h KST clock, the vocabulary chat bubbles and receipts use.
 *  ⚠ Byte-identical to api.ts kstParts()'s timeLabel on purpose: hour UNPADDED, minute PADDED,
 *  and 0시/12시 both print 12 (오전 12:05 · 오후 12:30). A padded hour here would make the same
 *  instant read differently on two screens. */
export const kstAmPm = (c: KstCal): string =>
  `${c.h < 12 ? '오전' : '오후'} ${c.h % 12 === 0 ? 12 : c.h % 12}:${String(c.min).padStart(2, '0')}`;

/** 「2026년 8월 26일」 — 연도까지 붙는 KST 날짜. 결제 관리의 「… 연결됨」 한 줄이 쓴다.
 *  kstDateLabel 과 같은 이유로 kstMonthDay **위에** 짓는다: 「n월 n일」의 두 번째 사본은 언젠가
 *  어긋나는 사본이다. `Intl.DateTimeFormat('ko-KR', {year, month:'long', day})` 의 출력과 바이트
 *  동일하다 (2026-08-27, 네 개 존에서 ICU 대조 284,070건 · 불일치 0). */
export const kstYearMonthDay = (c: KstCal): string => `${c.y}년 ${kstMonthDay(c)}`;

/** KST 캘린더 날 일련번호 — 「며칠 차이냐」만 묻는 곳(D-day)을 위한 정수. 두 값의 차가 곧 KST
 *  달력상 날짜 차다 (한국은 DST 가 없어 하루는 언제나 정확히 86400000ms).
 *  ⚠ 캘린더를 문자열로 만들었다가 Date.parse 로 되돌리던 왕복(club/[id].tsx 의 옛 kstYmd)을
 *  대신한다. 그 왕복은 Intl 을 필요로 했고, Intl 을 쓰면 폴백이 필요하고, 폴백은 기기 시계다. */
export const kstDayIndex = (ms: number): number => Math.floor((ms + KST_MS) / 86_400_000);
