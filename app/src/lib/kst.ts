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
