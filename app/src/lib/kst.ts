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
// ⚠ api.ts's `kstParts()` builds the same 「8월 26일 (화)」 vocabulary a second way (Intl, with a
// device-local fallback) and is wired into ~20 call sites; it is the older idiom and unifying it
// is its own slice. Anything NEW belongs here — this is the copy the .cjs suite can reach.
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
