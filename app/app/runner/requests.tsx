import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { TabSwipe } from '../../src/components/tabswipe';
import { DemandStrip } from '../../src/components/clubcard';
import { Avatar, Row } from '../../src/components/ui';
import { acceptBooking, acceptReschedule, AvailRule, declineReschedule, fetchMyAvailability, fetchMyRunnerBase, fetchMyRunnerStatus, fetchRescheduleRequests, fetchRunnerInbox, fetchRunnerJobs, MyRunnerStatus, OpenRequest, RescheduleRequest, RunnerJob } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { haptic } from '../../src/lib/haptics';
import { expectedDurationMs, sinceLabel } from '../../src/lib/lateness';
import { runnerJob } from '../../src/store';
import { layout, lilac, paper } from '../../src/theme';

// 요청 인박스 — deadlines, match score, conflict warnings (docs/calendar.md).
//
// [paper repaint 2026-08-11] forest/cream/volt chrome scrapped → paper. Cards go neutral
// #EEE sharp; the STATUS moves onto §3b chips (지명=amber tint, LIVE=green tint) on the
// datum's own row — the colored 2px card borders retired with the chrome. Accept doors
// use the home ticket's coral-door grammar (CORAL_INK fill, white 17/800) — the assigned
// state color for the accept action; busy = label swap, opacity tricks retired. Miller:
// each card keeps time → dog → payout → tags → memo → course → door, one chunk per row.
// Behavior frozen: accept/acceptReschedule/declineReschedule, focus reload, all routes.
//
// [journey v4 · R2a/R2b/R2c 2026-08-19] The lab's object grammar lands: a request is a thing
// the runner accepts, so it gets a 1.5px ink box (owner/request.tsx's RULING-5 nudge grammar),
// and everything that used to be a grey fill inside it (when-bar, memo plate, course box) goes
// back to type + a hairline. Three substantive changes beyond the dress:
//   1. ONE coral per frame. Every card's accept door used to be #C6472C — five requests meant
//      five climaxes and none. The single topmost ACTIONABLE door owns the coral now
//      (변경 요청 → 지명 → nothing); every other door is the ink-outline ghost. 근처(오픈) accepts
//      are never coral: "지명 먼저" is said in colour as well as in order (lab §B).
//   2. Money is one line, in place, in the dog's own row — the 18.5pt green payout column is
//      retired with the rest of the v4 money heroes (home hero, done receipt, earnings ticket).
//      The rate stops being printed: "수수료 제외" as words. 33% is a real column
//      (runners.commission_rate) — this is the lab's design choice, not a correction.
//      ⚠ SUPERSEDED 2026-08-24 — see the margin-secrecy block below. The words go too.
//   3. The empty state gains two REAL summary rows (온라인 from fetchMyRunnerStatus, 러닝 가능
//      시간 from fetchMyAvailability). A row that has not loaded renders nothing; a row that
//      failed says so quietly with a retry — never a default dressed up as an answer.
// NOT built from the lab: the "자세히 →" door (no open-request detail screen exists — a door to
// nowhere) and the "근처 요청 · 온라인일 때만" kicker — measured false: the open pool's gate is
// is_active_runner() (tier <> 'applicant', 0004:4-10), which never reads runners.online.
//   ⚠ CORRECTED 2026-08-25 — this list used to also carry the lab's "홈 베이스에서 1.2km" line as
//   unbuildable, on the grounds that `OpenRequest` has no pickup field. HALF of that is now
//   built and half is still true, and the halves are different questions (see the Q6 block
//   below): the 동 ships (0122); the DISTANCE does not, and its blocker was never the mapper.
//
// [MARGIN SECRECY + THE FOUR NUMBERS · Sean 2026-08-24, verbatim] "For runner money, don't show
// them the 수수료. I don't think we should be showing them the calcuations ever; only show the
// final profit per run; keep the margin a secret. You can show the expected profit at first per
// run next to how far away the starting point is and how long the run is and how long it will
// take total."
//   · 「수수료 제외」 is GONE from the money line. It printed no number, but it named the
//     mechanism and invited the arithmetic; the rule is that a runner's decision is made on ONE
//     figure. `req.payout` is the only money this screen reads, and it is already net.
//   · 「예상」 STAYS, and that is not a contradiction of the secrecy rule. Secrecy is about the
//     margin; 예상 is about the number not being final. api.ts:815 computes this client-side
//     from the runner settlement basis and the BOOKING's planned km, and the server finalises it
//     on actual distance (0101 §A). Dropping 예상 would sell an estimate as a settled amount —
//     the exact lie home.tsx:287 and the confirm dialog below already refuse to tell.
//   · 「총 N분」 is new: his "how long it will take total". It is `expectedDurationMs(km)` from
//     lateness.ts — km×8+25min, THE one shared duration formula (owner/request's slotAllowed and
//     the server's own accept validation use it). A second formula here would reproduce the
//     "the slot it offered me gets rejected" drift in a third place.
//   · "how far away the starting point is" — ⚠ THIS BULLET IS SUPERSEDED IN HALF, 2026-08-25.
//     It used to read: not built, `OpenRequest` carries no coordinate and no address, and that is
//     a gate not an omission (`booking_pickup_address`, 0060 widened 0065, hands out lat/lng ONLY
//     to a booking's ASSIGNED runner, in-flight or inside 24 h of a confirmed start — a pre-accept
//     card is on the far side of that gate by design), so building it needs a server decision
//     about pre-accept location disclosure, not a mapper field. **The server decision was taken.**
//     See the Q6 block immediately below. The sealed address window is still sealed and still
//     untouched — the 동 arrives through its own two-column definer, not through that gate.
//
// [Q6 RULED · Sean 2026-08-25, verbatim] "q6: if the runner is searching for a run, then a how far
// away they are from the starting point is a metric they need to see and doesnt show the actual
// address anyways; also include the 동." [end of his words]
// (docs/decisions/awaiting-sean.md §0-untricies, answering the 2026-08-24 pick sheet's Q6,
//  whose options were 「동 라벨로 / 빼자 / 좌표 열어」.)
//   · BUILT, this slice — **the 동 half only.** `OpenRequest.pickupDong` comes from
//     `open_request_pickup_dong()` (migration 0122 §3), a SECURITY DEFINER window returning two
//     flat columns (booking_id, pickup_dong) and nothing else — no lat/lng, no address text, no
//     address id. Its row set INHERITS `marketplace_open_requests` (so the five open-pool gates
//     cannot drift) plus the caller's own directed rows. A 법정동 label of a fixed address is
//     개인정보 at 동 granularity, not 위치정보, which is why it is disclosable at all.
//     The token renders ONLY when non-null — absence, never a placeholder (0122's own rule:
//     an invented 동 on a stranger's card is worse than no 동).
//   · ✅ **THE DISTANCE HALF IS NOW BUILT TOO — Sean ruled B, 2026-08-25.** This bullet used to
//     read "NOT BUILT, awaiting Sean's A/B/C", and the reason it could not be built was real:
//     distance needed the RUNNER's own coordinate, and taking one while no run is in progress
//     contradicts what `docs/legal/privacy-policy.md` publishes (「러닝 중이 아닐 때는 위치를
//     수집하지 않습니다」). **Ruling B does not read a device.** Sean, verbatim: 「go with B for
//     distance, and the runner should be able to switch this address in settings.」 The runner
//     TYPES a place once in settings (/runner/base-pin), the server snaps it to a ~1.1km grid
//     and stores it, and `open_request_distance()` (migration 0123 §8) returns a BAND — never
//     metres, never a coordinate. `OpenRequest.distanceBand` carries it; the token renders only
//     when non-null, absence never a placeholder, same law as the 동.
//     ⚠ WHAT KEEPS THIS SAFE IS THE COOLDOWN, NOT THE GRID — and that correction is measured,
//     not stylistic. A band is an annulus and annuli intersect; the blind review of 2026-08-25
//     drove 323 probes through these two RPCs and localized a stranger's pickup to 8.8 m, ~125×
//     finer than the ~1.1 km grid the first version of this comment leaned on, with 4 base moves
//     already beating the 동. What bounds it is how RARELY one account can produce a new annulus
//     CENTRE: `set_runner_base` refuses a change inside `_base_change_cooldown()` (0123 §4b —
//     **7 days, Sean's ruling 2026-08-25, T1**, his words: 「no need to over worry about such
//     abuse」). So: the RPC takes NO parameters (a parameter is an unlimited supply of centres),
//     the client cannot write the column (0123 §3, which now covers the cooldown stamp too), and
//     the grid stays as a belt on a single observation. Do not "improve away" any of the three,
//     and do not restate the old lattice claim — it is refuted in 0123's header with numbers.
//     ⚠ STILL OPEN and not this screen's to answer: retention (counsel Q3 — there is no sweep),
//     and the privacy-policy §1 line, which is Sean's wording (`docs/decisions/awaiting-sean.md`
//     §0-untricies). Option A (live device position) remains unbuilt and unruled — and
//     `runner/base-pin.tsx` no longer reads the device at all, which is the code catching up to
//     the sentence at :97-99 rather than the sentence being edited to fit the code.
//   · "but also show them what's next" — the flow after 수락 is stated where the decision is made
//     (the confirm dialog) and once at the foot of the screen. Both name the real stages the
//     booking actually walks: confirmed → runner_enroute → 인계(picked_up) → active → completed,
//     and completion is what writes `ledger_items`, i.e. what the 수익 screen then shows.
//
// [runner-home lab B②/B③ · 2026-08-25] Both were blocked on ONE mapper field and nothing else;
// `OpenRequest.scheduledAt` (raw ISO) landed on 2026-08-24 and unblocked them together.
//   · B② THE DEADLINE. The footer already promised auto-expiry and no card said when. The rule is
//     not a policy number: `expire_unmatched_bookings` (0080 ⓐ, inherited from 0017/0037/0060)
//     expires a `matching`/`runner_pending` booking when `scheduled_at < now()`, so the run's own
//     start time IS the deadline. Each card prints the time left, and each leg sorts by it.
//     ⚠ The sort stays INSIDE each leg — 지명 먼저 is a ladder, and a deadline must not climb it.
//     ⚠ Behavioural consequence, named rather than hidden: the coral rule reads `directed[0]`, so
//       the coral now follows the SOONEST directed request instead of the server's return order.
//       That is lab open question 3 and Sean has not answered it; it is recorded in the handoff.
//   · B③ 겹침, THE ACCEPT GATE MIRRORED BEFORE THE TAP. `runner_accept` refuses a request that
//     overlaps a live booking of mine (transition-booking/index.ts:94-127). Today the runner learns
//     that only from a failed accept — the single most expensive mistake this screen allows.
//     The mirror is exact on purpose: same window [scheduled_at, scheduled_at + km×8+25min), same
//     four LIVE statuses, same `cs < aEnd && ce > aStart` test, same `!==` self-exclusion.
//     ⚠ THE DOOR STAYS LIVE. The server is the authority and a client-side guess must never close a
//       door the server might still honour — hence 「수락이 거절될 수 있어요」, conditional on purpose.
//     ⚠ HONESTY GATE (absolute, lab §B③): the warning renders ONLY when BOTH loads succeeded. A
//       failed `fetchRunnerJobs` renders NO overlap information at all — never 「겹침 없음」, which
//       would be a fabricated all-clear on the one screen where an all-clear costs a real promise.
//     ⚠ NOT BUILT — the lab also moved the coral to the topmost directed door WITHOUT a conflict
//       (open question 4, drawn as "confirm"). Left alone deliberately: that would make the screen's
//       one climax move according to whether a SECOND load succeeded, i.e. the coral would report a
//       fact the screen may not know. The ladder (변경 요청 > 지명 > nothing) is byte-identical.

const CORAL_INK = '#C6472C';      // accept-door fill (white label holds ≥4.5:1)
const CORAL_INK_DEEP = '#B23E25';
const AMBER_BG = '#FDE8D0';       // pending/directed tint world (paper.pending family)
const AMBER_INK = '#9D580A';
const GREY_CHIP = '#F5F5F5';      // neutral chip fill (성향 태그 · 매칭 대기)

// "7월 31일 (목) 15:30" → ["7월 31일 (목)", "15:30"] — 시간을 1급 정보로 분리
const splitWhen = (w: string): [string, string] => {
  const i = w.lastIndexOf(' ');
  return i < 0 ? [w, ''] : [w.slice(0, i), w.slice(i + 1)];
};

const hhmm = (min: number) => `${String(Math.floor(min / 60)).padStart(2, '0')}:${String(min % 60).padStart(2, '0')}`;

// 「how long it will take total」 (Sean 2026-08-24) — 한 요청이 실제로 잡아먹는 시간.
// ⚠ 식은 **하나뿐이다**: lateness.ts의 expectedDurationMs (km×8+25분). owner/request의 slotAllowed와
// 서버의 수락 검증이 쓰는 바로 그 식이고, 여기서 두 번째 식을 세우면 '가능하다던 칸이 거절되는'
// 드리프트가 이 화면에도 생긴다. 25분은 러닝이 아니라 픽업·인계 몫이라 카드가 아니라 확인창에서
// 그렇게 밝힌다.
// km을 못 믿으면 **아무 말도 하지 않는다** (null → 토큰 생략): 모르는 시간을 25분으로 반올림해
// 인쇄하는 것이 이 파일이 계속 막아 온 그 거짓말이다.
const totalTimeLabel = (km: number): string | null => {
  if (!Number.isFinite(km) || km <= 0) return null;
  const min = Math.round(expectedDurationMs(km) / 60_000);
  const h = Math.floor(min / 60);
  const rem = min % 60;
  if (h === 0) return `${min}분`;
  return rem ? `${h}시간 ${rem}분` : `${h}시간`;
};

// ── [lab B② 2026-08-25] 마감까지 남은 시간 ────────────────────────────────────────────────
// 마감은 **정책 숫자가 아니다**: expire_unmatched_bookings(0080 ⓐ)가 `status in ('matching',
// 'runner_pending') and scheduled_at < now()`인 예약을 지운다 — 이 러닝의 시작 시각 그 자체가 기한이다.
// ⚠ 반드시 **원본 ISO**(OpenRequest.scheduledAt)에서만 판다. 조판된 `when`을 되파싱하는 순간 이 화면에
//   시계가 두 개 생기고, 그게 RunnerJob.scheduledAt이 애초에 존재하는 이유다.
// 어휘는 lateness.ts의 sinceLabel 하나를 그대로 쓴다 — runner/home의 relWhen과 **같은 말**을 하고
// (「5시간 30분」), 여기서 두 번째 포맷터를 세우지 않는다.
const AHEAD_CAP_MS = 24 * 3_600_000;  // home.tsx AHEAD_CAP_MIN과 같은 값·같은 이유
const deadlineLabel = (iso: string): string | null => {
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;   // 시각을 모르면 남은 시간을 말하지 않는다
  const left = t - Date.now();
  // 시작 시각이 이미 지난 요청은 **아무 말도 하지 않는다**. 그건 카운트다운이 아니라 만료 대상이고
  // (0080이 지운다 — 다만 크론은 즉시가 아니라서 목록에 남아 있을 수 있다), 「N분 늦음」류의 지각
  // 어휘는 러너를 탓하는 말이다: 아무도 늦지 않았다.
  if (left <= 0) return null;
  // 하루 넘게 남은 카운트다운은 아무의 행동도 바꾸지 않는다 — 카드의 날짜가 이미 그 일을 한다.
  if (left > AHEAD_CAP_MS) return null;
  if (left < 60_000) return '1분 이내';   // 「0분 뒤」는 고장난 문장이지 사실이 아니다
  return `${sinceLabel(left)} 뒤`;
};

// 마감 오름차순 — **레그 안에서만** 쓴다 (지명 먼저라는 사다리는 정렬보다 위다).
// 시각을 못 읽는 행은 순서를 지어내지 않고 뒤로 보낸다.
const byDeadline = (a: OpenRequest, b: OpenRequest): number => {
  const ta = Date.parse(a.scheduledAt);
  const tb = Date.parse(b.scheduledAt);
  if (Number.isNaN(ta)) return Number.isNaN(tb) ? 0 : 1;
  if (Number.isNaN(tb)) return -1;
  return ta - tb;
};

// ── [lab B③ 2026-08-25] 겹침 — 서버 수락 게이트의 표시측 거울 ────────────────────────────────
// 정본은 transition-booking/index.ts:94-127 (runner_accept). 여기 있는 네 가지가 거기와 같아야 한다:
//   ① 창 = [scheduled_at, scheduled_at + km×8+25분)  ② LIVE = 아래 네 상태 정확히
//   ③ 겹침 판정 = cs < aEnd && ce > aStart          ④ 자기 자신 제외
// ⚠ 식이 서버에서 바뀌면 이 줄이 곧 거짓말이 된다 — 그래서 소요 식은 여기서 만들지 않고
//   lateness.ts의 expectedDurationMs 하나만 부른다 (owner/request의 slotAllowed와 같은 그 식).
// ⚠ 서버는 `km*8+25`를 반올림 없이 쓰고 expectedDurationMs는 분 단위로 반올림한다 — 분수 km에서
//   최대 30초 어긋난다. 경계에 정확히 걸친 예약 하나가 서버에선 겹치고 화면엔 안 뜰 수 있다는 뜻이고,
//   그래서 문을 닫지 않는다(경고만 한다). 식을 두 벌로 갈라 맞추는 것이 더 비싼 실수다.
const OVERLAP_LIVE = new Set(['confirmed', 'runner_enroute', 'picked_up', 'active']);

// 표시용 KST 시계 (UTC+9 고정 — 한국은 DST가 없다). api.ts의 kstParts와 같은 문법이지만 그 함수는
// export되지 않고 이 슬라이스는 api.ts를 건드리지 않는다. **시작 라벨은 이미 조판된 job.when을 쓰고**
// 이 함수는 파생된 종료 시각 하나에만 쓴다 (라벨을 되파싱하는 게 아니라 원본에서 계산한다).
const KST_MS = 9 * 3_600_000;
const kstClock = (ms: number): string => {
  const d = new Date(ms + KST_MS);
  const h = d.getUTCHours();
  return `${h < 12 ? '오전' : '오후'} ${h % 12 === 0 ? 12 : h % 12}:${String(d.getUTCMinutes()).padStart(2, '0')}`;
};

type Conflict = { dogName: string; km: number; when: string; endLabel: string };

/** 이 요청이 내 확정 일정과 겹치는가. 겹치는 첫 예약(시각순)만 지목한다 — 서버도 그렇게 한다
 *  (무순서면 재시도마다 다른 예약을 지목해 러너가 뭘 정리할지 모른다).
 *  null = **모른다 또는 안 겹친다**를 구분하지 않는다: 호출부가 '둘 다 로드 성공'을 이미 갈랐고,
 *  이 함수는 겹침을 찾았을 때만 말한다. 「겹침 없음」은 어디서도 그리지 않는다. */
const findConflict = (req: OpenRequest, jobs: RunnerJob[]): Conflict | null => {
  const aStart = Date.parse(req.scheduledAt);
  if (Number.isNaN(aStart) || !Number.isFinite(req.km) || req.km <= 0) return null; // 창을 못 그리면 판정하지 않는다
  const aEnd = aStart + expectedDurationMs(req.km);
  const hit = jobs
    .filter((j) => OVERLAP_LIVE.has(j.rawStatus) && j.bookingId !== req.bookingId)
    .flatMap((j): { j: RunnerJob; cs: number; ce: number }[] => {
      const cs = j.scheduledAt ? Date.parse(j.scheduledAt) : NaN;
      if (Number.isNaN(cs) || !Number.isFinite(j.km) || j.km <= 0) return [];
      const ce = cs + expectedDurationMs(j.km);
      return cs < aEnd && ce > aStart ? [{ j, cs, ce }] : [];
    })
    .sort((x, y) => x.cs - y.cs)[0];
  if (!hit) return null;
  // 종료는 분 단위로 **올림**한다 — 서버가 자기 409 메시지에서 그렇게 한다. 절삭하면 화면이 말한
  // 구간과 러너가 실제로 받는 거절 메시지의 구간이 1분 어긋난다.
  return {
    dogName: hit.j.dogName,
    km: hit.j.km,
    when: hit.j.when,
    endLabel: kstClock(Math.ceil(hit.ce / 60_000) * 60_000),
  };
};

// 수락 뒤에 오는 순서 — 예약이 실제로 밟는 서버 상태를 사람 말로 옮긴 것이다
// (confirmed → runner_enroute → picked_up(양측 인계 확인) → active → completed).
// 완료가 곧 settle_run_tx이고, 그것이 ledger_items를 써서 수익 화면의 한 줄이 된다.
const NEXT_STEPS = '픽업 이동 → 인계 확인 → 러닝 → 완료 후 수익에 기록';

// 가용시간 한 줄 요약 — 규칙 행이 정본이다. 요일마다 시간이 다르면 시간을 지어내지 않고 그렇다고 말한다.
// [honesty 2026-08-19 · runner review P2] 빈 규칙 집합은 "설정한 적 없음"이 아니다:
// availability.tsx:85-89가 저장 전에 enabled만 남기므로, 모든 요일을 '쉬는 날'로 돌린 러너는
// **의도적으로** 빈 집합을 저장한다. 그 러너에게 '아직 설정 안 했어요'라고 말한 뒤 시간 조정 →을
// 열어주면 자기 설정이 그대로 있고, 둘 중 무엇을 믿어야 할지 알 수 없게 된다. 이 함수가 구분할 수
// 있는 사실은 '지금 켜진 요일이 없다' 하나뿐이므로 그것만 말한다 (로딩·실패는 호출부가 가른다).
const availSummary = (rules: AvailRule[]): string => {
  if (rules.length === 0) return '설정된 요일이 없어요';
  const same = rules.every((r) => r.startMin === rules[0].startMin && r.endMin === rules[0].endMin);
  return same
    ? `주 ${rules.length}일 · ${hhmm(rules[0].startMin)}–${hhmm(rules[0].endMin)}`
    : `주 ${rules.length}일 · 요일마다 다름`;
};

export default function Requests() {
  const df = useDisplayFont(); // display font — screen title (1/screen budget)
  const nf = useNumFont();     // Oswald — request times, payouts
  const [live, setLive] = useState<OpenRequest[]>([]);
  const [accepting, setAccepting] = useState<string | null>(null);
  // 일정 변경 요청 (0016) — 확정 예약의 새 시간 제안, 수락해야만 시간이 바뀐다
  const [resched, setResched] = useState<RescheduleRequest[]>([]);
  const [reschedBusy, setReschedBusy] = useState<string | null>(null);
  // 어느 **문**이 지금 동작 중인가 — bookingId만으로는 한 카드의 두 문(거절/수락)을 가를 수 없고,
  // 그러면 '동작 중이 아닌 문'을 정확히 비활성으로 그릴 수 없다 (아래 doorRow 참조).
  const [reschedAct, setReschedAct] = useState<'accept' | 'decline' | null>(null);
  // [적대 리뷰] busy는 확인 콜백 안에서야 켜진다 — 그 전 구간에 연타가 확인창을 쌓을 수 있었다.
  // 서버 CAS가 이중 커밋은 막지만, 중복 내비게이션과 '성공 뒤 실패' UI는 막지 못한다.
  const [asking, setAsking] = useState(false);
  const [reschedAsking, setReschedAsking] = useState(false);
  // [honesty 2026-08-11] warn-only catch + no loading state rendered "새 요청 0건 /
  // 지금은 열린 요청이 없어요" while loading AND on failure. Three states now.
  const [loaded, setLoaded] = useState(false);
  const [loadErr, setLoadErr] = useState(false);
  // [R2c] 빈 상태의 두 요약 행 — 인박스와 독립적으로 살고 죽는다. null = 아직 안 들어옴(그리지 않음).
  // [runner-home lab B① 2026-08-24] 종전엔 `st.online` 하나만 남기고 나머지를 버렸다. 같은 응답의
  // `tier`가 '조용한 날'과 '구조적으로 도달 불가'를 가르는 값이다 — 오픈 풀은 is_active_runner()
  // (tier <> 'applicant', 0004:4-10)에서 끝나고, 지명은 보호자가 목록에서 골라야 오는데 미인증
  // 러너는 그 목록에 없다. 응답 전체를 들고 있는다 (새 페치 0개).
  const [rs, setRs] = useState<MyRunnerStatus | null>(null);
  const [rsErr, setRsErr] = useState(false);
  const [avail, setAvail] = useState<AvailRule[] | null>(null);
  const [availErr, setAvailErr] = useState(false);
  // [lab B③] 내 확정 일정 — 수락 게이트를 탭 **전에** 비추기 위한 유일한 입력.
  // null은 '아직 안 들어옴'과 '실패'를 하나로 묶는다. **의도된 설계다**: 두 경우에 화면이 해야 할
  // 일이 정확히 같기 때문이다 — 겹침에 대해 아무 말도 하지 않는다. 실패를 따로 상태로 들고 있으면
  // 그 값을 읽는 곳이 없는 죽은 상태가 되거나(계산만 남은 상태 금지), 「확인 못 했어요」 같은 줄로
  // 새어나가 결국 없는 정보를 화면에 만든다. 여기서 실패는 **부재**로 렌더된다 (lab §B③ 절대 규칙).
  const [myJobs, setMyJobs] = useState<RunnerJob[] | null>(null);
  // [0123] 기준 위치가 **없어서** 거리가 안 보이는가? 카드의 null에서 추론하지 않고 서버에 묻는다.
  // null = 모름 (아직 안 읽었거나 읽기 실패) → 아무 줄도 그리지 않는다. `false` = 러너가 아니거나
  // 이미 지정함 → 역시 안 그린다. `true`일 때만 문이 뜬다.
  // 왜 추론하면 안 되는가: 밴드가 전부 null인 상태는 세 가지 원인을 갖고(미설정 · 주소 핀 없음 ·
  // 다리 사망), 그중 하나에만 문이 있다. 「거리가 안 보이네 → 설정하라고 하자」는 다리가 죽었을 때
  // 러너를 이미 설정한 화면으로 보내는 거짓 안내가 된다.
  const [baseUnset, setBaseUnset] = useState<boolean | null>(null);

  // 요약 두 줄도 매 로드마다 다시 읽는다 — '시간 조정 ›'으로 나갔다 돌아온 러너에게 옛 요약을 보여주지
  // 않으려면 포커스 리로드가 이 둘도 함께 끌어와야 한다 (빈 상태에서만 그려지지만, 빈 상태야말로 그
  // 출구가 있는 곳이다). 인박스와 **독립적으로** 실패한다 — 한쪽의 네트워크 오류가 다른 쪽을 지우지 않게.
  // ⚠ 별도 함수로 빼지 않는다: `load`가 컴포넌트 스코프의 다른 함수를 부르는 순간
  // exhaustive-deps가 `load`를 unstable로 보고 useFocusEffect에 새 에러를 만든다 (린트 베이스라인 6개 유지).
  const load = () => {
    setLoadErr(false);
    setRsErr(false);
    setAvailErr(false);
    // 실패하면 **값을 버린다**: 옛 값 옆에 실패 줄을 같이 그리면 둘 다 못 믿는 화면이 되고,
    // 옛 값만 조용히 남기면 그건 오래된 사실을 지금 사실로 파는 것이다. 하나의 행 = 하나의 상태.
    fetchMyRunnerStatus()
      .then(setRs)
      .catch((e) => { console.warn('[requests] status:', e?.message ?? e); setRs(null); setRsErr(true); });
    fetchMyAvailability()
      .then(setAvail)
      .catch((e) => { console.warn('[requests] availability:', e?.message ?? e); setAvail(null); setAvailErr(true); });
    // [lab B③] 인박스와 **독립적으로** 산다. 확정 일정 로드가 실패해도 요청 목록은 그대로 서고,
    // 반대로 이 실패가 요청을 지우지도 않는다 — 겹침 경고만 조용히 사라진다.
    fetchRunnerJobs()
      .then(setMyJobs)
      .catch((e) => { console.warn('[requests] jobs:', e?.message ?? e); setMyJobs(null); });
    // [0123] 인박스와 독립적으로 산다 — 실패하면 안내 문이 사라질 뿐, 요청 목록은 그대로.
    fetchMyRunnerBase()
      .then((b) => setBaseUnset(b != null && b.lat == null))
      .catch((e) => { console.warn('[requests] runner base:', e?.message ?? e); setBaseUnset(null); });
    return Promise.all([
      fetchRunnerInbox().then(setLive),
      fetchRescheduleRequests().then(setResched),
    ]).then(() => setLoaded(true))
      .catch((e) => { console.warn('[requests] inbox:', e?.message ?? e); setLoadErr(true); });
  };
  // 화면에 돌아올 때마다 갱신 — 수락/완료된 요청 카드가 남지 않게
  useFocusEffect(useCallback(() => { load(); }, []));
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  // [lab B③] 겹침을 말해도 되는가 — **두 로드가 모두 성공했을 때만**. 요청 목록이 옛 성공분이고
  // 지금 로드가 실패한 상태(loadErr)에서도 침묵한다: 그 요청이 아직 살아 있는지조차 지금은 모른다.
  // 실패한 확정 일정 로드는 「겹침 없음」이 아니라 **아무 줄도 아니다** (조작된 안심 금지).
  // 카드와 확인창이 **같은 게이트**를 쓴다 (아래 accept·renderRequest 둘 다 이 함수만 부른다).
  const overlapKnown = loaded && !loadErr && myJobs !== null;
  const conflictOf = (req: OpenRequest): Conflict | null =>
    (overlapKnown && myJobs !== null ? findConflict(req, myJobs) : null);

  // [2026-08-11] 여기는 한 번의 탭이 곧 커밋이었다. 수락은 **현실 세계의 약속**이다 — 그 시간에
  // 남의 개를 데리러 가겠다는 것이고, 동시에 다른 일에 쓸 수 있는 자리를 없앤다. 잘못 눌린 수락은
  // 보호자를 길에 세우거나 노쇼가 된다. 러너 홈의 티켓(home.tsx:182)은 이미 개·시각·실수령을
  // 보여주고 확인을 받는데, 정작 요청이 잔뜩 쌓이는 이 화면만 즉시 커밋이었다. 같은 계약으로 맞춘다.
  const accept = (req: OpenRequest) => {
    if (accepting || asking) return;
    setAsking(true);
    const dur = totalTimeLabel(req.km);
    // [lab B③] 겹침은 **결정하는 자리에서도** 말한다. 카드의 경고를 스쳐 지나간 러너에게 마지막 기회이고,
    // 문을 막지 않겠다는 결정(서버가 판단자다)의 대가는 사실을 한 번 더 말하는 것이다.
    // 모를 때는 여기서도 아무 줄도 붙지 않는다 — 확인창은 카드와 같은 게이트를 쓴다.
    const clash = conflictOf(req);
    Alert.alert('요청 수락',
      // '실수령'은 확정 금액을 뜻한다 — 이 값은 api.ts의 **추정치**다 (서버가 실거리로 확정).
      // [2026-08-24] 결정하는 자리라서 네 가지가 다 여기 있다: 거리 · 총 소요 · 예상 금액 · 그다음.
      // 소요 시간 줄은 km을 못 믿으면 통째로 빠진다 (없는 시간을 인쇄하지 않는다).
      `${req.dogName} · ${req.when}\n`
      + (dur ? `${req.km}km · 총 ${dur} (픽업·인계 포함)\n` : `${req.km}km\n`)
      + (clash ? `⚠ ${clash.dogName} · ${clash.km}km (${clash.when} ~ ${clash.endLabel}) 러닝과 겹쳐요 — 수락이 거절될 수 있어요\n` : '')
      + `예상 ${req.payout.toLocaleString()}원 (실거리로 확정) — 수락할까요?\n`
      + '수락하면 이 시간에 갈 사람은 나예요.\n'
      + `다음 순서: ${NEXT_STEPS}`,
      [
        { text: '아직', style: 'cancel', onPress: () => setAsking(false) },
        { text: '수락', style: 'default', onPress: () => { setAsking(false); void commitAccept(req); } },
      ]);
  };
  const commitAccept = async (req: OpenRequest) => {
    setAccepting(req.bookingId);
    try {
      await acceptBooking(req.bookingId);
      haptic('success');
      runnerJob.bookingId = req.bookingId;
      Alert.alert('수락 완료', '보호자에게 수락 알림이 전송되었어요');
      router.push('/runner/meetup');
    } catch (e) {
      Alert.alert('수락 실패', (e as Error).message);
      load();
    } finally {
      setAccepting(null);
    }
  };

  // 지명 먼저 — fetchRunnerInbox가 이미 directed를 앞에 붙여 오지만, 코랄 예산을 계산하려면
  // 두 레그를 이름으로 갈라놔야 한다 (섞인 배열의 '첫 항목'은 예산의 근거가 못 된다).
  // [lab B② 2026-08-25] 각 레그 **안에서** 마감 오름차순 = 먼저 사라질 것이 위로. filter가 새 배열을
  // 주므로 여기 sort는 live를 건드리지 않는다 (서버가 준 순서는 그대로 남는다).
  const directed = live.filter((r) => r.directed).sort(byDeadline);
  const nearby = live.filter((r) => !r.directed).sort(byDeadline);
  // 화면당 코랄 하나 (DESIGN §5) — **지금 눌러야 할 문 하나**가 가진다.
  // 변경 요청 > 지명 요청 > 없음. 변경 요청이 이기는 이유: 그건 새 일이 아니라 **이미 확정된 약속의
  // 시간**이 흔들리는 중이라 답을 미룰수록 비싸다 (lab R2b). 근처(오픈) 요청의 수락은 절대 코랄이
  // 아니다 — 지명이 없을 때도 그렇다. 코랄 0인 화면은 합법이다 (lab R2c).
  const coralResched = resched.length > 0 ? resched[0].bookingId : null;
  const coralDirected = coralResched === null && directed.length > 0 ? directed[0].bookingId : null;

  // [lab B①] 인증 전 — home.tsx:438이 계산하는 것과 **같은** 술어다 (한 규칙, 두 구현이 아니라
  // 한 규칙을 같은 모양으로 옮긴 것). rs가 없으면(로딩·실패) 절대 참이 되지 않는다: 모르는 tier에
  // 대고 '지원하세요'라고 말하는 것은 인증된 러너를 쫓아내는 거짓말이다.
  const preCert = rs !== null && !rsErr && (rs.tier === null || rs.tier === 'applicant');

  const renderRequest = (req: OpenRequest) => {
    const [wd, wt] = splitWhen(req.when);
    const coral = req.bookingId === coralDirected;
    // 다른 문이 동작 중이라 이 문은 눌러도 아무 일이 없다 — 그렇게 **보이게** 그린다
    // (theme.ts:206 매트릭스: disabled = disabledFill + faint, 불투명도 트릭 금지).
    const inert = accepting !== null && accepting !== req.bookingId;
    // [0114 residual · docs/contracts/party-membership-status-filter-contract.md §C.6]
    // `directed`는 곧 서버 상태 'runner_pending'이다 (api.ts fetchRunnerInbox의 지명 레그는
    // .eq('status','runner_pending')로만 읽는다). 수락 **전**의 지명 카드에는 보호자가 작성한
    // 자유 텍스트를 렌더하지 않는다: dogs.memo, dogs.preferences.tags[], bookings.pace_label은
    // 전부 무검증 통과 값이고, 0114가 채팅·리뷰·알림을 닫은 뒤에도 지명 하나로 낯선 러너에게
    // 닿는 잔여 경로다. 이름·견종·체중·백신은 남는다 — 러너가 수락 여부를 판단하는 정보이고,
    // 케어 지시(메모)는 수락한 러너의 잡 화면에서 볼 것이다. 오픈 풀(matching) 카드는 그대로.
    const preAccept = !!req.directed;
    const totalTime = totalTimeLabel(req.km);
    const deadline = deadlineLabel(req.scheduledAt);
    const clash = conflictOf(req);
    return (
      <View key={req.bookingId} style={s.reqCard}>
        <View style={s.cardBody}>
          <Row style={{ justifyContent: 'space-between', alignItems: 'center' }}>
            {/* §3b status chip — the request's nature, 16/800 tinted, no border.
                오픈 요청은 라일락(매칭 대기 = 기다림의 색). 예전 초록 '● LIVE 요청'은 은퇴 —
                초록은 이 팔레트에서 '준비됨'이고, 아직 아무도 배정되지 않은 요청은 준비된 게 아니다. */}
            <View style={[s.chip, { backgroundColor: req.directed ? AMBER_BG : GREY_CHIP }]}>
              <Text style={{ fontSize: 16, lineHeight: 20, fontWeight: '800', color: req.directed ? AMBER_INK : lilac.accent }}>
                {req.directed ? '★ 지명 요청' : '● 요청 · 매칭 대기'}
              </Text>
            </View>
            {req.repeatPrior != null && req.repeatPrior > 0 && (
              <View style={[s.metaChip, { backgroundColor: AMBER_BG }]}>
                <Text style={{ fontSize: 15, fontWeight: '800', color: AMBER_INK }}>⟳ {req.repeatPrior + 1}번째 함께</Text>
              </View>
            )}
          </Row>
          {/* 언제 뛰는가 — 요청의 1급 정보 (회색 각주 은퇴, 정보 위계 수정 2026-07-28).
              [v4] 회색 바 은퇴 — 잉크 상자 안에서 회색 면은 소음이다. 활자가 위계를 진다. */}
          <Row style={s.whenRow}>
            <Text style={{ fontSize: 15, fontWeight: '800', color: paper.text }}>{wd}</Text>
            {/* [lab B② 2026-08-25] 마감은 **자기가 파생된 시각 옆에** 붙는다 — 한 사실이 한 자리에.
                (칩 행으로 올리지 않은 이유: 그 행의 오른쪽은 이미 「⟳ N번째 함께」의 자리이고, 390pt에서
                 둘을 나란히 두면 RN의 flexShrink 기본 0 때문에 리플로가 아니라 잘림이 된다.)
                ⚠ 색은 조용하다. 앰버 임박 칩은 **일부러 짓지 않았다**: 서버에는 임박 문턱이 아예 없고
                  (오직 scheduled_at < now()), 그 컷을 정하는 것은 열린 질문 2 — 아직 답이 없다.
                  없는 문턱을 색으로 주장하면 그건 측정이 아니라 지어낸 긴급함이다. */}
            <Row style={{ alignItems: 'baseline', gap: 7 }}>
              {/* Oswald request time — lineHeight 27 = 1.29× (BUG A) */}
              <Text style={[{ fontSize: 21, lineHeight: 27, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] as const }, nf]}>{wt}</Text>
              {deadline && (
                <Text style={{ fontSize: 15, lineHeight: 19, fontWeight: '800', color: paper.dim }}>{deadline}</Text>
              )}
            </Row>
          </Row>
          <Row style={{ gap: 12, marginTop: 10 }}>
            <Avatar url={req.photoUrl} char={req.dogName[0]} bg={paper.ink} size={48} />
            <View style={{ flex: 1 }}>
              <Text style={{ fontSize: 18, fontWeight: '800', color: paper.ink }}>
                {req.dogName} · {req.breed} {req.weightKg}kg
              </Text>
              {/* 결정에 필요한 수는 한 줄에 — 개의 줄 안에서, 사실로. Oswald 숫자 lineHeight 19 = 1.27× (BUG A).
                  [2026-08-24] 「수수료 제외」 삭제. 숫자를 인쇄하진 않았지만 구조를 이름으로 불렀고,
                  이 화면의 규칙은 러너가 **하나의 수**로 결정한다는 것이다 (마진은 우리 몫의 비밀).
                  '예상'은 장식이 아니라 계약이라 남는다: 이 값은 견적이고 서버가 실거리로 확정한다.
                  「총 N분」 = expectedDurationMs(km) — 앱 전체가 공유하는 단 하나의 소요 식.
                  [0122 · Sean Q6 2026-08-25] 「반포동 출발」 — 수락 전 러너가 보는 유일한 위치
                  정보이고, 동 단위라 주소가 아니다. 값이 없으면 **토큰째로 빠진다**: 「동 미정」
                  같은 자리표시자는 없는 사실을 있는 것처럼 만든다. km 바로 뒤인 이유는 이게
                  거리·시간과 같은 결정 데이텀이기 때문이고, 돈은 줄 끝을 지킨다.
                  [0123 · Sean Q6 ruling B 2026-08-25] 「기준 위치에서 ~1km」 — Q6의 나머지 절반이
                  여기 붙는다. 라벨이 「기준 위치에서」인 이유는 두 가지이고 둘 다 정직 문제다:
                  ① 바로 앞의 {km}km는 **러닝 거리**라 아무 수식 없이 밴드를 붙이면 한 줄에 뜻이
                     다른 km가 둘이 된다; ② 「내 위치에서」라고 쓰면 지금 기기 위치를 읽은 것처럼
                     들리는데 우리는 러닝 중이 아닐 때 위치를 수집하지 않는다 — 이건 러너가 설정
                     화면에서 **직접 저장한** 기준점이고, 그나마 ~1km 격자로 반올림돼 있다.
                  값이 없으면 토큰째로 빠진다 (자리표시자 없음). 세 원인 — 기준 위치 미설정 ·
                  주소에 핀 없음 · 이 다리가 죽음 — 이 카드 위에서 같은 모습인 건 의도다. 셋을
                  구분하는 곳은 아래 안내 문 하나뿐이고, 거기서도 추론하지 않고 서버에 묻는다. */}
              <Text style={{ fontSize: 15, color: paper.dim, marginTop: 3, lineHeight: 19 }}>
                <Text style={{ fontWeight: '800', color: paper.ink }}>{req.km}km</Text>
                {req.distanceBand ? ` · 기준 위치에서 ${req.distanceBand}` : ''}
                {req.pickupDong ? ` · ${req.pickupDong} 출발` : ''}
                {preAccept ? '' : ` · ${req.paceLabel}`}
                {totalTime ? ` · 총 ${totalTime}` : ''} · 예상{' '}
                <Text style={[{ fontSize: 15, fontWeight: '800', color: paper.ink, lineHeight: 19, fontVariant: ['tabular-nums'] as const }, nf]}>
                  {req.payout.toLocaleString()}
                </Text>
                원
              </Text>
            </View>
          </Row>
          {(req.vaccines.length > 0 || (!preAccept && req.prefTags.length > 0)) && (
            <Row style={{ gap: 5, marginTop: 9, flexWrap: 'wrap' }}>
              {req.vaccines.length > 0 && (
                <View style={[s.metaChip, { backgroundColor: '#E3EFF9' }]}>
                  <Text style={{ fontSize: 15, fontWeight: '700', color: '#2D6DA8' }}>백신 {req.vaccines.length}종</Text>
                </View>
              )}
              {!preAccept && req.prefTags.map((t) => (
                <View key={t} style={[s.metaChip, { backgroundColor: GREY_CHIP }]}>
                  <Text style={{ fontSize: 15, fontWeight: '700', color: paper.text }}>{t}</Text>
                </View>
              ))}
            </Row>
          )}
          {req.memo && !preAccept && (
            <View style={s.memo}>
              <Text style={{ fontSize: 15, color: paper.text, lineHeight: 20 }} numberOfLines={2}>메모: {req.memo}</Text>
            </View>
          )}
          {/* 코스 미리보기 — 수락 전에 코스를 알고 결정한다 (트레이스·지형·점검일).
              라벨은 잉크: 이 화면의 코랄은 문 하나가 가진다. 코스 이름은 원문 그대로 (§6 정본). */}
          {req.routeId && req.routeName && (
            <Pressable
              onPress={() => router.push(`/course/${req.routeId}`)}
              style={({ pressed }) => [s.courseRow, pressed && { backgroundColor: paper.wash }]}
            >
              <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink, flex: 1 }} numberOfLines={1}>{req.routeName}</Text>
              <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink, marginLeft: 10 }}>코스 미리보기 ›</Text>
            </Pressable>
          )}
          {/* [lab B③ 2026-08-25] 겹침 — 문 바로 위, 탭 직전에 읽히는 자리.
              세 줄이 각각 다른 일을 한다: 무슨 일인지 · 무엇과 겹치는지(이름·거리·구간) · 그래서 뭐가
              될 수 있는지. 세 번째 줄이 **조건문**인 것이 핵심이다 — 판단자는 서버이고, 이 화면은
              같은 산술을 먼저 보여줄 뿐이다. 그래서 문은 그대로 살아 있다.
              앰버(대기·주의)이지 크리티컬이 아니다: 실패가 아니라 아직 일어나지 않은 충돌이다. */}
          {clash && (
            <View style={s.clashStrip}>
              <Text style={s.clashTitle}>확정된 러닝과 겹쳐요</Text>
              <Text style={s.clashBody}>{clash.dogName} · {clash.km}km · {clash.when} ~ {clash.endLabel}</Text>
              <Text style={s.clashBody}>수락이 거절될 수 있어요</Text>
            </View>
          )}
        </View>
        <View style={s.doorRow}>
          <Pressable
            style={({ pressed }) => [
              coral ? s.doorPrimary : s.doorGhost,
              inert && s.doorOff,
              !inert && pressed && (coral ? { backgroundColor: CORAL_INK_DEEP } : { backgroundColor: paper.wash }),
              // [Sean 2026-08-26 press behaviour] §3b splits the grammar on whether the door has
              // a FILL: the coral door is a physical key (4px lip at rest, translateY(3) + 1px
              // pressed, no scale), the ghost door keeps its scale — paper has no depth. An inert
              // door stays flat in both, because a dead key has no travel.
              !inert && coral && (pressed
                ? { transform: [{ translateY: 3 }], borderBottomWidth: 1, borderBottomColor: CORAL_INK_DEEP }
                : { borderBottomWidth: 4, borderBottomColor: CORAL_INK_DEEP }),
              !inert && !coral && pressed && { transform: [{ scale: 0.97 }] },
            ]}
            disabled={accepting !== null}
            accessibilityState={{ disabled: accepting !== null }}
            onPress={() => accept(req)}
          >
            <Text style={{ fontSize: 17, fontWeight: '800', color: inert ? paper.faint : coral ? '#FFFFFF' : paper.ink }}>
              {accepting === req.bookingId ? '수락 중...' : '수락하기 ›'}
            </Text>
          </Pressable>
        </View>
      </View>
    );
  };

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <TabSwipe>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: 60, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            {/* [§3c 화면 타이틀 2026-08-11] 30/900 · lineHeight 37 (1.23× — BUG A) */}
            <Text style={[{ fontSize: 30, lineHeight: 37, fontWeight: '900', color: paper.ink }, df]}>요청</Text>
            <Text style={{ fontSize: 15, color: paper.dim, marginTop: 3 }}>
              {/* count only after a real load — never "0건" in flight or on failure */}
              {!loaded
                ? loadErr ? '요청을 불러오지 못했어요' : '요청 확인 중...'
                : `새 요청 ${live.length}건${resched.length > 0 ? ` · 변경 요청 ${resched.length}건` : ''}`}
            </Text>
          </View>
          <Pressable style={({ pressed }) => [s.refreshChip, pressed && { backgroundColor: paper.wash }]} onPress={load}>
            <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink }}>↻ 새로고침</Text>
          </Pressable>
        </Row>

        {/* ---------- 하이클럽 호스트 수요 스트립 (R1-C, 0032) — 호스트 = 또 하나의 동네 일감.
            대기 팀이 있을 때만 나타난다 (유령 클럽 금지) ---------- */}
        <View style={{ marginTop: 12 }}>
          <DemandStrip />
        </View>

        {/* [0123 · Sean Q6 ruling B] 진짜 문 하나 — 「기준 위치를 설정하면 거리도 보여요 ›」.
            네 조건이 전부 참일 때만 뜬다:
              · loaded && !loadErr — 목록이 실제로 지금 사실이다
              · baseUnset === true — 서버가 「러너인데 기준 위치 없음」이라고 **말했다** (카드의
                null에서 추론한 게 아니다: 다리가 죽어도 카드는 똑같이 비어 보인다)
              · live.length > 0   — 볼 요청이 있다. 빈 화면에서 이 줄은 안내가 아니라 잡음이다
            이 줄이 없던 자리에 「거리 정보 없음」 같은 회색 라벨을 두지 않는 이유는 그게 문이
            아니기 때문이다 — 보이는 모든 행위에는 진짜 경로가 있어야 한다. */}
        {loaded && !loadErr && baseUnset === true && live.length > 0 && (
          <Pressable
            onPress={() => router.push('/runner/base-pin')}
            style={s.baseDoor}
            accessibilityRole="button"
            accessibilityLabel="활동 기준 위치 설정하기"
          >
            <Text style={s.baseDoorTxt}>
              기준 위치를 설정하면 거리도 보여요 › <Text style={s.baseDoorHint}>약 1km 단위로만 저장돼요</Text>
            </Text>
          </Pressable>
        )}

        {/* ---------- 일정 변경 요청 (0016) — 기존→새 시간, 수락/거절 ---------- */}
        {resched.map((rq) => {
          const coral = rq.bookingId === coralResched;
          // 동작 중인 문은 정확히 하나다 (그 카드 × 그 액션). 나머지는 전부 눌러도 아무 일이
          // 없으므로 disabled 필로 내려간다 — 다섯 장이 떠 있을 때 한 장을 누르면 나머지 여덟
          // 개의 문이 온전한 무게로 남아 "눌리는 문"을 사칭하던 상태를 없앤다.
          const busyHere = reschedBusy === rq.bookingId;
          const declineOff = reschedBusy !== null && !(busyHere && reschedAct === 'decline');
          const acceptOff = reschedBusy !== null && !(busyHere && reschedAct === 'accept');
          return (
            <View key={`rs-${rq.bookingId}`} style={s.reqCard}>
              <View style={s.cardBody}>
                {/* §3b status chip — amber pending, beside its subject */}
                <View style={[s.chip, { backgroundColor: AMBER_BG, alignSelf: 'flex-start' }]}>
                  <Text style={{ fontSize: 16, lineHeight: 20, fontWeight: '800', color: AMBER_INK }}>일정 변경 요청</Text>
                </View>
                <Text style={{ fontSize: 17, fontWeight: '800', color: paper.ink, marginTop: 10 }}>
                  {rq.dogName} · {rq.km}km
                </Text>
                <Row style={{ gap: 8, marginTop: 8, alignItems: 'center' }}>
                  <View style={s.timeBox}>
                    <Text style={{ fontSize: 15, fontWeight: '700', color: paper.dim }}>기존</Text>
                    <Text style={{ fontSize: 15, fontWeight: '700', color: paper.dim, textDecorationLine: 'line-through', marginTop: 1 }}>
                      {rq.curDate}
                    </Text>
                    <Text style={{ fontSize: 17, fontWeight: '800', color: paper.dim, textDecorationLine: 'line-through' }}>
                      {rq.curTime}
                    </Text>
                  </View>
                  <Text style={{ fontSize: 17, fontWeight: '900', color: AMBER_INK }}>→</Text>
                  <View style={[s.timeBox, { backgroundColor: AMBER_BG }]}>
                    <Text style={{ fontSize: 15, fontWeight: '700', color: AMBER_INK }}>제안</Text>
                    <Text style={{ fontSize: 15, fontWeight: '800', color: AMBER_INK, marginTop: 1 }}>{rq.newDate}</Text>
                    <Text style={{ fontSize: 17, fontWeight: '900', color: AMBER_INK }}>{rq.newTime}</Text>
                  </View>
                </Row>
              </View>
              <View style={s.doorRow}>
                {/* busy = label swap on the acting door; both disabled while one is in flight.
                    거절(기존 유지)은 고스트지만 약한 문이 아니다 — 내 캘린더를 지키는 쪽이
                    눈에 안 띄면 그건 넛지가 아니라 함정이다. 둘 다 같은 크기·같은 테두리. */}
                <Pressable
                  style={({ pressed }) => [
                    s.doorGhost,
                    declineOff && s.doorOff,
                    !declineOff && pressed && { backgroundColor: paper.wash, transform: [{ scale: 0.97 }] },
                  ]}
                  disabled={reschedBusy !== null}
                  accessibilityState={{ disabled: reschedBusy !== null }}
                  onPress={async () => {
                    setReschedBusy(rq.bookingId);
                    setReschedAct('decline');
                    try { await declineReschedule(rq.bookingId); haptic('light'); load(); }
                    catch (e) { Alert.alert('처리 실패', (e as Error).message); }
                    finally { setReschedBusy(null); setReschedAct(null); }
                  }}
                >
                  <Text style={{ fontSize: 17, fontWeight: '800', color: declineOff ? paper.faint : paper.ink }}>
                    {busyHere && reschedAct === 'decline' ? '처리 중...' : '거절 (기존 유지)'}
                  </Text>
                </Pressable>
                <Pressable
                  style={({ pressed }) => [
                    coral ? s.doorPrimary : s.doorGhost,
                    acceptOff && s.doorOff,
                    !acceptOff && pressed && (coral ? { backgroundColor: CORAL_INK_DEEP } : { backgroundColor: paper.wash }),
                    // Same split as the accept door above (§3b): filled coral = key, ghost = scale.
                    !acceptOff && coral && (pressed
                      ? { transform: [{ translateY: 3 }], borderBottomWidth: 1, borderBottomColor: CORAL_INK_DEEP }
                      : { borderBottomWidth: 4, borderBottomColor: CORAL_INK_DEEP }),
                    !acceptOff && !coral && pressed && { transform: [{ scale: 0.97 }] },
                  ]}
                  disabled={reschedBusy !== null}
                  accessibilityState={{ disabled: reschedBusy !== null }}
                  /* 같은 법: 이건 **이미 확정된 약속의 시간을 바꾸는** 커밋이다. 한 번의 탭으로
                     내 캘린더가 조용히 옮겨가면 안 된다 — 옛 시간과 새 시간을 다시 보여주고 묻는다. */
                  onPress={() => {
                    if (reschedBusy || reschedAsking) return;   // 확인창이 겹쳐 쌓이는 것도 막는다
                    setReschedAsking(true);
                    Alert.alert('새 시간 수락',
                      `${rq.dogName} · ${rq.km}km\n${rq.curDate} ${rq.curTime} → ${rq.newDate} ${rq.newTime}\n이 시간으로 바꿀까요?`,
                      [
                        { text: '아직', style: 'cancel', onPress: () => setReschedAsking(false) },
                        { text: '수락', style: 'default', onPress: async () => {
                          setReschedAsking(false);
                          setReschedBusy(rq.bookingId);
                          setReschedAct('accept');
                          try {
                            await acceptReschedule(rq.bookingId);
                            haptic('success');
                            Alert.alert('변경 수락', '일정이 새 시간으로 변경됐어요 — 캘린더에 반영됩니다');
                            load();
                          } catch (e) { Alert.alert('수락 실패', (e as Error).message); load(); }
                          finally { setReschedBusy(null); setReschedAct(null); }
                        } },
                      ]);
                  }}
                >
                  <Text style={{ fontSize: 17, fontWeight: '800', color: acceptOff ? paper.faint : coral ? '#FFFFFF' : paper.ink }}>
                    {busyHere && reschedAct === 'accept' ? '처리 중...' : '새 시간 수락 ›'}
                  </Text>
                </Pressable>
              </View>
            </View>
          );
        })}

        {/* ---------- 실시간 요청 (Supabase) — 지명 먼저, 근처는 그 아래 ---------- */}
        {directed.map(renderRequest)}
        {nearby.map(renderRequest)}

        {!loaded && !loadErr && (
          <View style={s.stateBlock}>
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center' }}>불러오는 중...</Text>
          </View>
        )}
        {/* loud-fail strip — criticalWash bg + critical ink + retry (never a fake empty) */}
        {loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>요청 인박스를 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {/* ---------- 미인증 러너의 빈 인박스 — 조용한 날이 아니라 **닫힌 문**이다 (lab B①).
            홈은 2026-08-08 정직 수리에서 이미 이 거짓말을 고쳤는데(「인증 전에는 요청이 오지 않아요」
            + /runner/apply 실문), 요청 화면만 수리 이전 문장을 계속 출하하고 있었다.
            게이트는 tier 하나이고, **로드에 성공했을 때만** 갈린다 — 모르는 tier로 이 상태를
            그리면 인증된 러너에게 지원하라고 말하게 된다. 온라인 행은 이 상태에서 **일부러 뺀다**:
            미인증 러너에게 토글은 아무것도 바꾸지 못하고, 두 번째 헛다리가 된다. ---------- */}
        {loaded && !loadErr && live.length === 0 && resched.length === 0 && preCert && (
          <>
            <View style={s.stateBlock}>
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink, textAlign: 'center' }}>인증 전에는 요청이 오지 않아요</Text>
              <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', marginTop: 4, lineHeight: 20 }}>
                인증된 러너에게만 요청이 열려요{'\n'}지원은 몇 분이면 끝나요
              </Text>
            </View>
            {/* 실문 — /runner/apply는 존재하고 홈이 이미 같은 곳으로 보낸다. 고스트 문법(잉크 윤곽):
                이 화면의 코랄 예산은 수락 문의 것이고, 빈 인박스에는 수락할 것이 없다. */}
            <Pressable
              onPress={() => router.push('/runner/apply')}
              style={({ pressed }) => [s.applyDoor, pressed && { backgroundColor: paper.wash, transform: [{ scale: 0.97 }] }]}
              accessibilityRole="button"
              accessibilityLabel="인증 센터로 이동해 러너 지원하기"
            >
              <Text style={{ fontSize: 17, fontWeight: '800', color: paper.ink }}>인증 센터에서 지원하기 ›</Text>
            </Pressable>
            {/* 러닝 가능 시간은 남는다 — 인증 전에 설정해두는 것이 실제로 쓸모 있고, 편집기는 지금 열린다. */}
            <View style={s.sumGroup}>
              {avail !== null && (
                <Pressable
                  onPress={() => router.push('/runner/availability')}
                  style={({ pressed }) => [s.sumRow, pressed && { backgroundColor: paper.wash }]}
                >
                  <Text style={s.sumLabel}>러닝 가능 시간</Text>
                  <Text style={s.sumValue}>{availSummary(avail)}</Text>
                  <Text style={s.sumAction}>시간 조정 ›</Text>
                </Pressable>
              )}
              {availErr && (
                <Row style={s.sumRow}>
                  <Text style={s.sumLabel}>러닝 가능 시간</Text>
                  <Text style={s.sumState}>불러오지 못했어요</Text>
                  <Pressable onPress={load} style={s.sumRetry} accessibilityRole="button">
                    <Text style={s.sumAction}>다시 시도</Text>
                  </Pressable>
                </Row>
              )}
            </View>
            {avail !== null && (
              <Text style={{ fontSize: 15, lineHeight: 20, color: paper.dim, marginTop: 12 }}>
                지금 설정해두면 인증되는 즉시 보호자 예약 화면에 반영돼요
              </Text>
            )}
          </>
        )}

        {loaded && !loadErr && live.length === 0 && resched.length === 0 && !preCert && (
          <>
            <View style={s.stateBlock}>
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink, textAlign: 'center' }}>지금은 열린 요청이 없어요</Text>
              <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', marginTop: 4 }}>새 요청이 오면 여기에 표시돼요</Text>
            </View>
            {/* ---------- 조용한 날의 두 줄 — 왜 조용한지 러너가 스스로 볼 수 있게.
                둘 다 실필드다: runners.online · runner_availability_rules.
                아직 안 들어온 행은 **그리지 않는다** (기본값을 답으로 위장하지 않는다). ---------- */}
            <View style={s.sumGroup}>
              {rs !== null && (
                <Row style={s.sumRow}>
                  <Text style={s.sumLabel}>온라인</Text>
                  <Text style={s.sumValue}>{rs.online ? '켜짐' : '꺼짐'}</Text>
                </Row>
              )}
              {rsErr && (
                <Row style={s.sumRow}>
                  <Text style={s.sumLabel}>온라인</Text>
                  <Text style={s.sumState}>상태를 불러오지 못했어요</Text>
                  <Pressable onPress={load} style={s.sumRetry} accessibilityRole="button">
                    <Text style={s.sumAction}>다시 시도</Text>
                  </Pressable>
                </Row>
              )}
              {avail !== null && (
                <Pressable
                  onPress={() => router.push('/runner/availability')}
                  style={({ pressed }) => [s.sumRow, pressed && { backgroundColor: paper.wash }]}
                >
                  <Text style={s.sumLabel}>러닝 가능 시간</Text>
                  <Text style={s.sumValue}>{availSummary(avail)}</Text>
                  <Text style={s.sumAction}>시간 조정 ›</Text>
                </Pressable>
              )}
              {availErr && (
                <Row style={s.sumRow}>
                  <Text style={s.sumLabel}>러닝 가능 시간</Text>
                  <Text style={s.sumState}>불러오지 못했어요</Text>
                  <Pressable onPress={load} style={s.sumRetry} accessibilityRole="button">
                    <Text style={s.sumAction}>다시 시도</Text>
                  </Pressable>
                </Row>
              )}
            </View>
          </>
        )}

        {/* 화면의 콜로폰 — 수락이 무엇을 만드는지, 그리고 **그다음에 무엇이 오는지**.
            (Sean 2026-08-24: "but also show them what's next.") 상자를 두르지 않는다:
            이 파일의 법대로, 활자가 위계를 진다. */}
        <View style={s.note}>
          <Text style={{ fontSize: 15, lineHeight: 20, color: paper.dim, textAlign: 'center' }}>
            수락하면 캘린더에 확정 일정으로 추가돼요{'\n'}
            그다음은 {NEXT_STEPS}{'\n'}
            {/* [lab B② 2026-08-25] 「응답 기한」은 이 앱에 존재하지 않는 개념이었다 — 별도의 기한
                컬럼도, 정책 숫자도 없다. 0080 ⓐ가 실제로 하는 일을 그대로 말한다: 시작 시각까지
                아무도 수락하지 않으면 만료. 이제 카드 하나하나가 그 기한을 숫자로 인쇄한다. */}
            시작 시각까지 아무도 수락하지 않으면 요청은 자동 만료돼요
          </Text>
        </View>
      </ScrollView>
      </TabSwipe>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  refreshChip: { backgroundColor: paper.canvas, paddingVertical: 9, paddingHorizontal: 13, borderWidth: 1, borderColor: paper.line, alignSelf: 'flex-start' },
  // [v4] 요청 = 러너가 수락하는 **오브젝트**라 잉크 1.5px 상자를 받는다
  // (owner/request.tsx:1341 코스 넛지와 같은 문법). 안쪽 회색 면들은 전부 은퇴 — 상자 안의
  // 상자는 위계를 만들지 못하고 소음만 만든다.
  reqCard: { backgroundColor: paper.canvas, borderWidth: 1.5, borderColor: paper.ink, marginTop: 14 },
  cardBody: { padding: 14, paddingBottom: 12 },
  chip: { borderRadius: 0, paddingVertical: 4, paddingHorizontal: 9 },
  metaChip: { borderRadius: 0, paddingVertical: 3, paddingHorizontal: 8 },
  // 메모 — 회색 면 대신 왼쪽 규칙선 (보호자의 목소리를 인용문처럼)
  memo: { borderLeftWidth: 2, borderLeftColor: '#EEEEEE', paddingLeft: 9, marginTop: 9 },
  whenRow: { justifyContent: 'space-between', alignItems: 'baseline', marginTop: 10 },
  // [lab B③] 겹침 스트립 — 랩의 warnstrip 그대로, 새 헥스 0개: 면 lilac.amberSoft(#FBEED9),
  // 테두리 lilac.amberEdge(#F2DFC2), 잉크는 이 파일이 이미 쓰는 AMBER_INK(#9D580A, 그 면 위 4.78:1).
  clashStrip: {
    backgroundColor: lilac.amberSoft, borderWidth: 1, borderColor: lilac.amberEdge,
    paddingVertical: 9, paddingHorizontal: 10, marginTop: 9,
  },
  clashTitle: { fontSize: 15, lineHeight: 19, fontWeight: '800', color: AMBER_INK },
  clashBody: { fontSize: 15, lineHeight: 19, color: AMBER_INK, marginTop: 2 },
  courseRow: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    borderTopWidth: 1, borderTopColor: '#EEEEEE',
    marginTop: 12, paddingTop: 12, minHeight: 44,
  },
  timeBox: { flex: 1, backgroundColor: '#F7F7F7', paddingVertical: 7, paddingHorizontal: 10 },
  doorRow: { flexDirection: 'row', gap: 8, paddingHorizontal: 12, paddingBottom: 12 },
  // 코랄 문 — 화면당 하나. CORAL_INK fill, 흰 라벨 17/800 (4.84:1), 샤프.
  doorPrimary: {
    flex: 1, backgroundColor: CORAL_INK, borderWidth: 1.5, borderColor: CORAL_INK,
    alignItems: 'center', justifyContent: 'center', paddingVertical: 14, minHeight: 48,
  },
  // 고스트 문 — 캔버스 + 잉크 1.5px 윤곽 + 잉크 라벨. 코랄 예산 밖의 모든 문이 이것이다.
  // (theme.ts:205의 세컨더리 매트릭스는 wash+코랄 라인이지만, 그 문법을 여러 문에 쓰면
  //  화면에 코랄이 대여섯 개가 된다 — v4 랩의 doorB(잉크 윤곽)를 따른다.)
  doorGhost: {
    flex: 1, backgroundColor: paper.canvas, borderWidth: 1.5, borderColor: paper.ink,
    alignItems: 'center', justifyContent: 'center', paddingVertical: 14, minHeight: 48,
  },
  // 비활성 문 — theme.ts:206 매트릭스의 disabled 항 (disabledFill + faint 라벨, 알파 금지).
  // 코랄 문에도 그대로 얹힌다: 동작 중이 아닌 문은 그 프레임의 코랄 예산도 쓰지 않는다.
  doorOff: { backgroundColor: paper.disabledFill, borderColor: '#EEEEEE' },
  // 로딩·빈 상태 — 상자 없이 활자만 (빈 인박스에 테두리를 그리면 없는 내용에 무게가 생긴다)
  stateBlock: { marginTop: 40, paddingHorizontal: 10, alignItems: 'center' },
  // [lab B①] 인증 문 — doorGhost와 같은 문법(캔버스 + 잉크 1.5px), 카드 밖이라 자기 여백을 갖는다.
  applyDoor: {
    backgroundColor: paper.canvas, borderWidth: 1.5, borderColor: paper.ink,
    alignItems: 'center', justifyContent: 'center', paddingVertical: 14, minHeight: 48, marginTop: 16,
  },
  // ── R2c 요약 행 — owner/request.tsx의 prefRow 문법 (딤 라벨 왼쪽 · 굵은 값 오른쪽 · 잉크 액션) ──
  sumGroup: { marginTop: 40, borderTopWidth: 1, borderTopColor: '#EEEEEE' },
  sumRow: {
    flexDirection: 'row', alignItems: 'center',
    paddingVertical: 14, borderBottomWidth: 1, borderBottomColor: '#EEEEEE',
    minHeight: 52,   // 44pt 터치 타깃 이상
  },
  sumLabel: { fontSize: 15, color: paper.dim, width: 110 },
  sumValue: { fontSize: 15, fontWeight: '800', color: paper.ink, flex: 1, textAlign: 'right' },
  // 값이 아니라 **상태**를 말하는 자리 — 굵은 잉크로 그리면 답으로 읽힌다
  sumState: { fontSize: 15, color: paper.dim, flex: 1, textAlign: 'right' },
  sumAction: { fontSize: 15, fontWeight: '800', color: paper.ink, marginLeft: 10 },
  sumRetry: { minHeight: 44, justifyContent: 'center' },
  // loud-fail strip — community.tsx failStrip grammar (criticalWash + critical, retry ≥40pt)
  failStrip: { marginTop: 24, backgroundColor: paper.criticalWash, padding: 13 },
  // [액션 시스템 2026-08-11] 잉크 테두리 박스 은퇴. 이 버튼은 criticalWash 라우드-페일 스트립
  // 안에 있는데, 잉크 테두리가 크리티컬 잉크와 싸웠다. 실패 스트립은 박스 버튼이 필요 없다 —
  // runner/run.tsx failAction의 밑줄 텍스트 문법으로 통일 (박스 9개 삭제, 결정 1개).
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },
  note: { marginTop: 18, padding: 10 },
  // [0123] 기준 위치 안내 문 — address-pin의 메모 스트립과 같은 문법(≥44pt, 뉴트럴 상단선).
  // 코랄 잉크(actionInk 5.99:1)로 그리는 이유: 이건 상태 라벨이 아니라 **누를 수 있는 문**이다.
  baseDoor: {
    marginTop: 12, borderTopWidth: 1, borderTopColor: '#EEEEEE',
    minHeight: 48, justifyContent: 'center', paddingHorizontal: 2,
  },
  baseDoorTxt: { fontSize: 15, lineHeight: 19, fontWeight: '800', color: paper.actionInk },
  baseDoorHint: { fontSize: 15, lineHeight: 19, fontWeight: '600', color: paper.dim },
});
