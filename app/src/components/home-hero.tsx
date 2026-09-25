// 홈 히어로 — 두 개의 큰 선택 (Sean 2026-08-19, 홈 랩 ⑧ v2, 판정 "A")
//
// ═══ 이 컴포넌트가 대체하는 것 ═══
// GO 디스크와 그 접힘 안무. 디스크는 여섯 상태를 **색 하나**로 말하려 했고 그게 읽히지 않았다.
// 여기서는 같은 상태를 **버튼의 개수와 문장**으로 말한다. 색 어휘는 GO 법을 그대로 물려받는다
// (CLAUDE.md: 코랄 = 내 차례 · 블루 계열 = 대기 · 세이지 = 준비됨) — 디스크는 은퇴해도 사용자가
// 이미 배운 어휘는 남는다.
//
// ═══ 규칙 하나 ═══
// 히어로는 고정 UI가 아니라 **예약 상태의 함수**다. 입력은 home.tsx가 이미 계산하는 `goState`
// (여섯 상태, 상호 배타, 빈틈 없음)와 `liveNext`뿐이다. 새 상태 로직은 0줄.
//
//   none                → 두 옵션: 지금 찾기(코랄) + 예약하기(잉크)
//   searching/directed  → 알림 줄(대기) + 예약하기 하나. 지금 찾기 없음 — 이미 찾는 중이다.
//   confirmed           → 알림 줄(세이지, 러너 이름) + 예약하기 하나
//   handoff             → 알림 줄(세이지 = 인계 완료). 인계는 이미 끝났고 남은 건 기록 확인이다.
//   active              → 라이브 위젯이 존 전체를 대체 — 버튼 없음. 개가 밖에 있다.
//
// ═══ 위계 ═══
// 화면당 채도를 가진 요소는 **하나**. none에선 지금 찾기, handoff에선 알림 줄, active에선 위젯.
// 예약하기는 언제나 잉크 테두리 — 두 번째 코랄은 첫 번째 코랄을 지운다.
//
// ═══ 정직 ═══
// 로딩 중엔 두 옵션을 그리지 않는다 — 모르는 상태 위에 결정을 얹지 않는다. 실패는 실패로.
import { router } from 'expo-router';
import { Image, Pressable, StyleSheet, Text, View } from 'react-native';
import { useAnnounceOnChange } from '../lib/a11y-announce';
import { useDisplayFont } from '../lib/displayFont';
import { useNumFont } from '../lib/fonts';
import { haptic } from '../lib/haptics';
import { draft } from '../store';
import { layout, paper } from '../theme';
import { sinceLabel, type Lateness } from '../lib/lateness';
import { totalUnreadBadge, unreadBadge, unreadBadgeLabel, type ChatUnreadState } from '../lib/chat-read';
import { heroDestination, type HeroState } from '../lib/home-hero-route';
import { DrawButton } from './draw-button';

// [0188] `returning` is the SEVENTH state, and it exists because `active` stopped being one thing.
// Before the run-end ceremony the stop settled, so `active` meant 「running」 and the hero's live
// widget was always true. The ceremony leaves the booking `active` through the whole two-stamp
// return, so without a separate state the hero says 「N분째 달리는 중 — 지도 보기 ›」 about a dog
// that is home, and offers a live map instead of the one action the owner actually owes.
// ⚠ It is NOT folded into `handoff`: that state is the moment AFTER the pickup was sealed (see
// the `handoff` frame below), so reusing it would trade one false sentence for another. Coral,
// because by the GO law coral is the user's turn and confirming the return IS the owner's turn
// (DESIGN.md §GO).
//
// The union itself now lives in `../lib/home-hero-route`, which owns the destination rule written
// in this vocabulary — one definition, so the rule and the renderer cannot drift.
export type HomeGoState = HeroState;

export interface HomeHeroNext {
  id: string;
  runnerName?: string | null;
  timeLabel?: string;     // "19:30"
  dateLabel?: string;     // "오늘" · "내일" · "8월 20일"
  /** 이 예약의 아이 (bookings.dogs.name). 아래 `dogName` prop(첫 등록 아이)보다 항상 우선한다. */
  dogName?: string | null;
  /** 서버 원상태 (bookings.status enum 원문). 표시 어휘(6종)가 뭉갠 구분을 문장이 쓴다 —
   *  runner_enroute 와 confirmed 는 STATUS_MAP 에서 둘 다 'confirmed' 다 (api.ts:739). */
  rawStatus?: string | null;
  /** bookings.arrived_at — 러너가 문 앞에 선 시각. null = 아직 도착 보고 없음. */
  arrivedAt?: string | null;
}

/** 경과 라벨 — '이 시각으로부터 지금까지'를 사람 말로. 값이 없거나, 파싱이 안 되거나, 1분 미만이면
 *  **null** 이고 호출부는 그때 절을 통째로 뺀다. 「0분째」는 측정이 아니라 반올림이 만든 문장이고,
 *  미래 소인(음수 경과)은 시계가 어긋났다는 뜻이지 사실이 아니다.
 *
 *  ⚠ 시계를 함수 안에 둔 이유는 lateness() 와 같다 — 화면이 렌더 중에 Date.now() 를 부르면
 *  react-hooks/purity 가 잡고, 피하려고 상태로 올리면 컴파일러가 다른 데서 체한다
 *  (lateness.ts:126, 실측 2026-08-21). 테스트는 계속 명시적으로 주입한다.
 *
 *  ⚠ 초 단위 루프는 없다. §6 이 유휴 모션을 금지하고, 이 값은 1분에 한 번만 바뀐다 — 홈이 이미
 *  도는 세 경로(포커스 · 앱 복귀 · `bk-<id>` 실시간)가 재계산 시점이다. */
export function elapsedLabel(iso: string | null | undefined, now: number = Date.now()): string | null {
  if (!iso) return null;
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  const ms = now - t;
  if (ms < 60_000) return null;
  return sinceLabel(ms);
}

interface Props {
  state: HomeGoState;
  next: HomeHeroNext | null;
  /** 계정의 첫 등록 아이 — 예약이 없을 때만 부르는 이름. 예약이 있으면 next.dogName이 이긴다. */
  dogName: string | null;
  /** '지금 찾기'가 열 요청 화면의 km 다이얼 초기값 (draft.km). 하드코딩 금지 — 버튼이 약속한
   *  거리와 다음 화면이 여는 거리는 같은 값이어야 한다. */
  dialKm: number;
  loadState: 'loading' | 'ready' | 'error';
  onRetry: () => void;
  /** [A① 2026-08-24 Sean] 히어로 1행이 쓰는 **상대 라벨** — 오늘 / 내일 / D-2. home.tsx 가
   *  scheduled_at 에서 계산한다. 구 `ddayLabel` prop(서브라인 꼬리표)의 자리를 대신한다:
   *  1행은 도달 불가능한 ≤4자 분기 탓에 실서버 행에서 **언제나 「곧」**이었고(:238 의 shortDate),
   *  6일 뒤 예약도 「곧」이라고 말했다. 값이 없으면 null — 그때만 shortDate 로 떨어진다. */
  relLabel?: string | null;
  /** 이 예약의 예정 시각이 이미 지났는가 (KST 날짜 칸 기준, home.tsx가 계산).
   *  ddayLabel = null 은 "카운트다운을 그리지 않는다"는 뜻일 뿐 "아직 안 왔다"는 뜻이 아니다 —
   *  그 둘을 한 채널에 뭉쳤던 것이 8월 4일 예약에 "시간에 맞춰 알려드려요"를 인쇄한 원인이다. */
  nextIsPast?: boolean;
  /** [T6] 지각 판정. 있으면 지난-예약 문장이 '언제'만이 아니라 '누구를 기다리다'까지 말한다. */
  late?: Lateness | null;
  /** active 상태에서 라이브 위젯을 렌더할 슬롯. home.tsx가 이미 가진 위젯을 그대로 넘긴다. */
  liveWidget?: React.ReactNode;
  /** 지금 온라인인 러너 수 — **동네가 아니다** (fetchCertifiedRunners에 district 필터가 없다).
   *  라이브 점은 **이 값이 0보다 클 때만** 켜진다 — 0명인데 맥박을 그리면 그 점은 거짓말이고,
   *  한 번 거짓이 되면 인계 화면의 점까지 못 믿게 된다. `.limit(10)` 때문에 10 이상은
   *  '10명 이상'으로 말한다 (모르는 수를 아는 척하지 않는다). */
  /** null = not yet read (or the read failed) — render as silence, never as zero. */
  onlineRunners?: number | null;
  /** [0212] 채팅 미확인 — **상태 그대로** 받는다 (숫자가 아니라). 로딩·실패·「이 예약은 답에 없음」이
   *  전부 다른 사실이고 셋 다 배지를 그리지 않아야 하는데, 숫자 하나로 접으면 그 구분이 호출부에서
   *  사라지고 0이 배지가 될 길이 생긴다. 판정은 chat-read.ts 가 소유한다. */
  chatUnread?: ChatUnreadState;
}

const GO_SAGE = '#119B58';   // home.tsx와 같은 값 — 확정·준비됨
const WAIT_BLUE = '#6C5CE7'; // lilac.accent — 대기

// ── 히어로 문구 = 상태 그 자체 (Sean 2026-08-20, `home-full-lab.html`) ──────────────────
// 마크가 문구의 오른쪽 여백에 내려앉기 때문에 **1행은 마크 자리를 비워야 한다**. 랩에서
// 「s4kim2025 러너의 / 응답을 기다려요」가 마크와 겹치는 걸 보고 얻은 법이고, 여기서는 카피
// 규율이 아니라 **레이아웃**으로 강제한다: 1행 Text에만 오른쪽 패딩을 주고 2행은 전폭을 쓴다.
// 그래서 이름·장소처럼 길이를 모르는 값은 항상 2행이나 서브라인으로 간다.
const MARK_W = 104;

function Phrase({ top, bottom, df, topNum }: { top: string; bottom: string; df: any; topNum?: boolean }) {
  // [A① 2026-08-24] 1행이 D-라벨일 때만 Oswald. 한글 라벨(오늘 · 내일)은 그대로 디스플레이 서체다 —
  // Oswald 에는 한글 글리프가 없어 섞으면 한 줄 안에서 폴백이 갈린다.
  // ⚠ 그때 lineHeight 는 43×1.2 = 51.6 위여야 한다 (BUG A: 어센더 잘림은 활자가 클수록 크게 보인다).
  const nf = useNumFont();
  return (
    // [HIG A3/A6] One element, one header. These two Texts are a single sentence split across two
    // lines for the mark's sake (MARK_W above), so exposing them separately made a screen reader
    // read 「오늘」 and 「초코가 달려요」 as two unrelated items. `accessible` merges them and
    // `header` says what the hero IS, which is also what lets rotor navigation land on it.
    <View style={s.phw} accessible accessibilityRole="header" accessibilityLabel={`${top} ${bottom}`}>
      {/* ⚠ Hidden from accessibility on purpose. The mark is decoration here — merging a parent
          swallows its children's labels, so leaving it exposed appended 「도그스하이」 to the end of
          the headline on every single state. The brand is named by the screen, not by this hero. */}
      <View
        style={{ position: 'absolute', right: -2, top: -4, zIndex: 1 }}
        pointerEvents="none"
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
      >
        <Image
          source={require('../../assets/logo-alpha.png')}
          style={{ width: 66 * (1619 / 971), height: 66 }}
          resizeMode="contain"
        />
      </View>
      <Text
        style={[s.phr, topNum ? [nf, s.phrNum] : df, { paddingRight: MARK_W }]}
        numberOfLines={1}
      >{top}</Text>
      <Text style={[s.phr, df]} numberOfLines={1}>{bottom}</Text>
    </View>
  );
}

export function HomeHero({ state, next, dogName, dialKm, loadState, onRetry, relLabel, nextIsPast, late, liveWidget, onlineRunners = null, chatUnread = { status: 'loading' } }: Props) {
  // 이 예약의 아이가 먼저다. dogName prop은 fetchFitness의 `.order('created_at').limit(1)` —
  // 즉 **첫 등록 아이**다. 다견 가구에서 몽이 예약 위에 "초코를 인계하고 확인해주세요"라고 쓰던
  // 것이 그 차이였다 (review P1-6).
  const name = next?.dogName ?? dogName ?? '우리 아이';
  // 디스플레이 서체는 지연 로드 — 하드코딩하면 로드 전엔 시스템 폰트로 뜬다 (실측). 집 규칙대로 훅을 쓴다.
  const df = useDisplayFont();

  // 새 예약을 시작하는 두 문 — 지난 지명을 반드시 지운다. 은퇴한 goBook()이 하던 일이고
  // (old-home.tsx의 "스테일 지명이 슬롯을 한 러너로 묶던 버그"), 지금은 지명이 **성공했을 때만**
  // 지워지므로 실패하거나 중간에 그만둔 지명이 다음 예약에 그대로 따라붙었다 (review P1-3).
  const clearNomination = () => { draft.preferredRunnerId = null; draft.preferredRunnerName = null; };
  // 지금 찾기 = 요청 화면의 pickEarliest 경로. 새 화면 없음 — 홈이 그걸 묻어 두던 걸 그만둘 뿐.
  const findNow = () => { haptic('light'); clearNomination(); draft.autoEarliest = true; router.push('/owner/request'); };
  const schedule = () => { haptic('light'); clearNomination(); draft.autoEarliest = false; router.push('/owner/request'); };
  // ⚠ [codex 2026-08-21] nextIsPast 는 **KST 캘린더 하루** 차이다 (ddayN < 0). 그래서 09:00 예약이
  // 09:41에 늦어 있어도 하루가 넘어가기 전에는 false 였고, T6 문장이 통째로 꺼져 있었다.
  // 늦음의 근거는 시각이지 날짜 칸이 아니다 — 판정이 있으면 판정을 쓰고, 없을 때만 날짜로 떨어진다.
  const isLate = late?.late ?? nextIsPast;
  // [A④ 2026-08-24 Sean] 러너가 문 앞에 섰다는 **서버가 기록한** 사실. 표시 어휘가 runner_enroute 와
  // confirmed 를 한 낱말로 뭉개므로(api.ts STATUS_MAP) 판정은 rawStatus 로만 한다.
  // ⚠ [2026-09-25 owner-journey-1] 이 선언은 :325 에서 여기로 **올라왔다**. openNext 가 이 값을
  // 읽어야 하는데 거기서 선언하면 handoff·returning 분기가 그 전에 return 해서 TDZ 로 죽는다 —
  // 바로 아래 isLate 주석이 기록한 것과 같은 크래시다.
  const arrivedWaiting = next?.rawStatus === 'runner_enroute' && !!next.arrivedAt;
  // 천장(3h) 밖이면 false. 판정 자체가 없으면 true — 판단이 없는 것이 '문을 닫아라'는 판단은 아니다.
  const resumable = late?.resumable !== false;
  // 「늦었다」와 「진행할 문이 없다」는 같은 사실이 아니다. 히어로는 16일간 둘을 한 낱말로 썼고,
  // 그래서 문 앞에 러너가 서 있는 31분 지각 건에도 「일정에서 정리하기」를 그렸다. 문이 살아 있는
  // 경우를 빼고 나면 남는 게 진짜로 닫힌 건이다 — 목적지 규칙(home-hero-route.ts ②)과 같은 술어.
  const lateDoorClosed = !!isLate && !(arrivedWaiting && resumable);
  // ⚠ [워크플로 감사 2026-08-21] 이 선언은 openNext **위**에 있어야 한다. 아래에 두면 handoff
  // 분기(:186)가 그 전에 return 하므로, 그 분기의 코랄 버튼이 openNext 를 부르는 순간 isLate 가
  // TDZ 에 걸려 ReferenceError 로 죽는다 — 내가 isLate 를 도입하면서 만든 실제 크래시였다.
  //
  // ⚠ [codex 2026-08-21] 지각·천장 초과 건은 미트업으로 보내지 않는다. 두 가지가 동시에 틀렸다:
  //   ① 버튼이 「일정에서 정리하기」라고 말하는데 미트업으로 갔다 — 목적지가 라벨과 다르면 거짓말.
  //   ② 미트업은 runner_enroute 를 arrived 스테이지로 매핑하고 arrived_at 이 null 이어도 인계
  //      CTA 를 연다. 즉 이 버튼이 **16일 된 예약을 되살리는 경로**였다 — 천장 규칙이 막으려던 바로 그것.
  // [2026-09-25 owner-journey-1] That rule was RIGHT and too wide: it also shut the one door to
  // the handoff seal for a runner who had actually ARRIVED and a booking still inside the
  // ceiling. The arm order now lives in `home-hero-route.ts` — read its header for which arm
  // answers which case, and `app/test/home-hero-route.test.cjs` for the pins that hold the order.
  const openNext = () => {
    if (!next) return;
    draft.bookingId = next.id;
    router.push(heroDestination({ state, isLate: !!isLate, arrivedWaiting, resumable, bid: next.id }));
  };

  // 상태별 문구·칩·버튼. 1행은 항상 짧게(마크 자리) — 이름·시각처럼 길이를 모르는 값은
  // 2행이나 서브라인으로 내려보낸다.
  // ⚠ 지난 예약에 '확정됨'을 찍지 않는다. 시뮬레이터에서 초록 확정 칩 위에 「지난 예약이 하나
  // 있어요」가 같이 뜬 걸 보고 잡았다 — 칩과 문구가 서로를 반박하면 둘 다 못 믿게 된다.
  // 상태색 법의 초록은 '준비됨'이지 '지나갔음'이 아니므로, 지난 건은 중립 딤으로 내려간다.
  const chip =
    state === 'confirmed' ? (isLate
      // [T6] '지난 예약'만으로는 어제인지 16일 전인지 알 수 없다. 기간은 사실이고, 사실은 공짜다.
      ? { c: paper.dim, t: late?.late ? `지난 예약 · ${sinceLabel(late.sinceMs)}` : '지난 예약' }
      : { c: GO_SAGE, t: '확정됨' })
      : state === 'directed' ? { c: WAIT_BLUE, t: '응답 대기' }
        : state === 'searching' ? { c: WAIT_BLUE, t: '찾는 중' }
          // handoff·returning 은 아래에서 일찍 빠져나가지만 칩·문구는 여기서 같이 산다 —
          // 두 자리에 같은 문자열을 적어 두면 VoiceOver 가 읽는 문장과 화면의 문장이 조용히
          // 갈라진다 (announce 가 이 값들을 그대로 읽는다).
          //
          // ⚠ [2026-09-25 owner-journey-2] 이 두 상태는 **같은 칩을 쓰면 안 된다**. 표시 상태
          // 'handoff' 는 서버 원상태 picked_up 이고, picked_up 은 양측 인계 소인이 **둘 다** 찍힌
          // 뒤에만 찍힌다 (transition-booking `confirm_handoff_tx`, 소인과 승격이 한 UPDATE).
          // 즉 이 프레임은 인계 **직후**다 — 코랄 「내 차례」는 이미 끝난 일을 시키는 문장이었다.
          // 세이지는 GO 법의 '준비됨'이고, 그게 지금 참인 사실이다. returning 만 코랄로 남는다:
          // 거기서는 보호자의 확인이 아직 안 찍혔다.
          : state === 'handoff' ? { c: GO_SAGE, t: '인계 완료' }
            : state === 'returning' ? { c: paper.action, t: '내 차례' }
              : { c: paper.dim, t: '비어 있음' };
  // ⚠ 「지난 예약이 하나 있어요」는 Sean이 "무슨 뜻이냐"고 물은 문장이었다 — 맞는 지적이었고,
  // 사실은 "예약 시각이 지났는데 아직 확정으로 남아 있다"이다. 그래서 문구가 그걸 그대로 말하고
  // 정확한 날짜·시각은 서브라인이 든다.
  //
  // ⚠⚠ 그리고 **1행에는 길이를 모르는 값을 절대 넣지 않는다.** 방금 `dateLabel + ' 예약'`을
  // 1행에 넣었다가 「8월 4일 (화) 예약」이 마크 자리에 부딪혀 「8월 4일 (화)…」로 잘리는 걸
  // 시뮬레이터에서 봤다 — 내가 세운 드롭 법을 내가 어긴 것이다. dateLabel은 '오늘'(2자)일 수도
  // '8월 4일 (화)'(10자)일 수도 있으므로 1행에 올 수 없다. 짧을 때만 쓰고 아니면 '곧'으로
  // 접는다: 정확한 날짜는 어차피 바로 아래 17pt 서브라인이 말한다.
  //
  // ⚠⚠⚠ [A① 2026-08-24 Sean] 위 문단이 정확히 진단해 놓고도 고치지 못한 결함이 여기 있었다:
  // dateLabel 은 서버 행에서 **항상** kstParts 산출물(「8월 26일 (화)」, 10자)이라 ≤4 분기가
  // 실행되는 경우가 없다. 즉 확정 히어로의 1행은 언제나 「곧」이었고, 엿새 뒤 예약도 「곧」이라고
  // 말했다. 화면이 필요로 한 짧고 참인 값은 이미 한 층 위에 있었다 — kstDayDiff 로 계산되어
  // 서브라인 꼬리표로만 쓰이던 상대 라벨이다. 그 값을 1행으로 올린다 (relLabel).
  // shortDate 는 폴백으로만 남는다: relLabel 이 null 인 경우 = scheduled_at 자체가 없는 행.
  const shortDate = next?.dateLabel && next.dateLabel.length <= 4 ? next.dateLabel : '곧';
  const topLine = relLabel ?? shortDate;
  // D-n 만 숫자다 (오늘 · 내일 · 곧 은 한글). 서체 전환의 근거는 라벨의 **모양**이지 상태가 아니다.
  const topIsNum = state === 'confirmed' && !isLate && /^D-\d+$/.test(topLine);
  const phrase =
    state === 'confirmed'
      // ⚠ [codex 2026-08-21] 헤드라인만 nextIsPast 로 남아 있었다 — 칩·서브라인·버튼은 isLate 로
      // 옮겼는데 여기를 빠뜨렸다. 그 결과 10:00 예약을 10:31 에 보면 칩은 「지난 예약」, 서브라인은
      // 「러너가 도착하지 않았어요」, 헤드라인은 「오늘 초코가 달려요」였다. 한 화면이 자기를 반박했다.
      ? (isLate ? { top: '예약 시간이', bottom: '지났어요' } : { top: topLine, bottom: `${name}가 달려요` })
      : state === 'directed' ? { top: '응답을', bottom: '기다려요' }
        : state === 'searching' ? { top: '러너를', bottom: '찾고 있어요' }
          // [2026-09-25 owner-journey-2] 「지금 만나요 / {name} 인계할 시간」 은퇴. picked_up 은
          // 만남이 **끝난** 표시라서, 그 문장은 이미 넘긴 아이를 다시 넘기라고 말하고 있었다.
          : state === 'handoff' ? { top: '인계 끝났어요', bottom: `${name} 곧 출발해요` }
            : state === 'returning' ? { top: '러닝이 끝났어요', bottom: `${name} 인계 확인` }
              : { top: '오늘은 아직', bottom: '비어 있어요' };

  // ── HIG A3/A6 — the hero, out loud ───────────────────────────────────────────────────────────
  // This block moved ABOVE the early returns for one reason: the announcement must read the exact
  // strings the screen renders, and `handoff`/`returning` used to hard-code their chip and phrase
  // inside their own branches. Two copies of a sentence drift, and the copy that drifts silently
  // is the one nobody can see. Nothing about the rendered output changed — the branches below now
  // read `chip`/`phrase` instead of repeating them.
  //
  // The owner's home flips under them: `bk-<id>` realtime, the focus refetch, the app-resume
  // refetch. What a sighted owner takes from a glance is the chip plus the two headline lines, so
  // that is the sentence — not the subline, which is detail VoiceOver reads on focus.
  // ⚠ `active` announces NOTHING here. Its hero is `liveWidget`, which home.tsx owns and
  // announces, so a sentence built here would either duplicate it or describe a frame this
  // component does not draw.
  const heroSentence = loadState !== 'ready' || state === 'active'
    ? null
    : `${chip.t} · ${phrase.top} ${phrase.bottom}`;
  useAnnounceOnChange(heroSentence);

  // ── 로딩·실패: 결정을 얹지 않는다 ─────────────────────────────────────────
  if (loadState === 'loading') {
    return (
      <View style={s.wrap}>
        <Text style={[s.title, df]}>{name}, 오늘은?</Text>
        <Text style={s.quiet}>예약을 확인하는 중이에요</Text>
      </View>
    );
  }
  // 실패 줄. home.tsx의 loadBookings는 실패해도 **직전 실값을 유지**하므로, 예약을 이미 아는
  // 상태에서 새로고침 하나가 실패했다고 그 예약과 두 버튼을 통째로 지우면 안 된다 (review P1-2:
  // 인계 중 백그라운드 → LTE 핸드오버 실패 → 홈에 '인계 확인'이 사라졌다). 아는 게 없을 때만
  // 화면을 대신하고, 아는 게 있으면 그 위에 한 줄로 얹힌다 — clubcard.tsx의 compact 문법과 같다.
  const errRow = loadState === 'error' ? (
    <View style={s.alertRow}>
      <View style={[s.dot, { backgroundColor: paper.critical }]} />
      <Text style={[s.alertMain, { color: paper.critical, flex: 1 }]}>예약을 불러오지 못했어요</Text>
      <Pressable onPress={onRetry} hitSlop={8} accessibilityRole="button">
        <Text style={[s.alertAct, { color: paper.critical }]}>다시 시도</Text>
      </Pressable>
    </View>
  ) : null;
  if (loadState === 'error' && !next) {
    return <View style={s.wrap}>{errRow}</View>;
  }

  // ⚠ [codex #3b 2026-08-21] active 와 handoff 는 자기 위젯으로 **일찍 빠져나가서** 지각 판정을
  // 한 번도 보지 않았다. 하필 그 둘이 개가 러너에게 있는 상태다 — 즉 지각이 가장 중요한 두 경우에서
  // 홈이 아무 말도 안 하고 있었다. 헤드라인을 두 개 만들지 않고(설계는 랩 ⑧ v2 로 확정) 사실 한 줄만
  // 얹는다. 인계 후이므로 '불발'은 여기서도 금지어다 — 문장은 확인과 시간만 말한다.
  const lateStrip = late?.late ? (
    <View style={s.lateStrip}>
      <View style={[s.chipDot, { backgroundColor: paper.critical }]} />
      <Text style={s.lateStripTx}>
        {late.started
          ? `러닝이 예정보다 ${sinceLabel(late.sinceMs)} 길어지고 있어요`
          : `아직 러닝이 시작되지 않았어요 · ${sinceLabel(late.sinceMs)} 지남`}
      </Text>
    </View>
  ) : null;

  // ── active: 라이브 위젯이 존을 대체 ───────────────────────────────────────
  if (state === 'active') {
    return <View style={s.wrapTight}>{errRow}{lateStrip}{liveWidget}</View>;
  }

  const when = next ? [next.dateLabel, next.timeLabel].filter(Boolean).join(' ') : '';
  const runner = next?.runnerName ? `${next.runnerName} 러너` : '러너';

  // [A④ 2026-08-24 Sean, "how long runner has been…"] 화면이 이미 아는데 한 번도 말하지 않던 사실:
  // **러너가 문 앞에 얼마나 서 있었는가**. 근거는 bookings.arrived_at 하나뿐이고, 없으면 절이 통째로
  // 빠진다 — 「0분째」도, 추측한 도착 시각도 없다.
  // ⚠ 이건 사실 한 줄이지 인계 CTA 게이팅이 아니다. 코랄이 arrived_at 에서 켜지는가(A) 아니면 홈이
  // 도착에도 조용한가(B)는 여전히 Sean 의 재정 대기다 (docs/decisions/handoff-cta-gating.md) —
  // 칩·버튼·상태 판정은 이 슬라이스에서 한 줄도 건드리지 않았다. 랩 ④ 의 두 프레임이 **공통으로**
  // 더한 요소가 이 한 절이라서 A/B 어느 쪽으로 결정돼도 살아남는다.
  const doorWait = next?.rawStatus === 'runner_enroute' && next.arrivedAt
    ? elapsedLabel(next.arrivedAt)
    : null;
  // ⚠ `arrivedWaiting` 은 여기 있었다. openNext 가 읽어야 해서 :180 부근으로 올라갔다 — 한 벌만 산다.

  const openChat = () => {
    haptic('light');
    if (next) router.push(`/chat?bid=${next.id}`);
    else router.push('/chat');
  };
  // [0212] 채팅 버튼의 배지. `meta` 슬롯은 「버튼이 여는 것에 대한 실측 사실」 전용이고(draw-button
  // Props), 이 값이 정확히 그것이다 — 서버가 센 행 수다. 모르면(로딩·실패·이 예약이 답에 없음)
  // null 이 와서 슬롯이 통째로 빠진다: 이 자리는 문장이 아니라 수치라서, 빈 값을 0으로 채우면
  // 읽지 못한 것을 읽은 것처럼 말하게 된다.
  // ⚠ 이 버튼이 여는 화면을 따라간다 — 예약이 있으면 그 스레드, 없으면 bare /chat 이라 전체 합계.
  const chatBadge = next ? unreadBadge(chatUnread, next.id) : totalUnreadBadge(chatUnread);
  const chatBadgeA11y = next ? unreadBadgeLabel(chatUnread, next.id) : null;
  const chatLabel = (sub: string) => (chatBadge ? `채팅 — ${chatBadgeA11y ?? `읽지 않은 메시지 ${chatBadge}`}` : `채팅 — ${sub}`);

  // ── handoff: 인계 완료 — 러너가 아이를 데리고 출발 준비 중이다 ─────
  // 미리 예약은 여기서 **사라진다**. 아이가 막 넘어간 참에 다음 예약을 권하는 건
  // 선택지가 아니라 방해다.
  //
  // ⚠ [2026-09-25 owner-journey-2] 이 프레임은 코랄 「내 차례 · 인계하기 · 아이를 넘기고
  // 봉인해요」였다. 근거를 따라가면 **정확히 거꾸로**였다: 표시 상태 'handoff' 는 api.ts 의
  // STATUS_MAP 에서 picked_up 이고, picked_up 은 `confirm_handoff_tx` 가 양측 소인을 둘 다 본
  // 뒤에만 찍는다. 즉 화면에서 가장 급한 코랄 면이 **이미 끝난 일**을 시키고 있었고, 정작 인계
  // 순간(runner_enroute + arrived_at)에는 조용한 금색 「티켓 보기」가 떠 있었다. 급함은 사실을
  // 따라간다 — 세이지 칩 + 금색 티켓이 지금 참인 프레임이다. 코랄을 어디로 옮길지(도착 프레임에
  // 줄 것인가)는 Sean 의 재정이라 이 슬라이스는 **코랄을 더하지 않는다**.
  if (state === 'handoff') {
    return (
      <View style={s.wrapTight}>
        {errRow}
        {lateStrip}
        <View style={s.chipRow}>
          <View style={[s.chipDot, { backgroundColor: chip.c }]} />
          <Text accessibilityLiveRegion="polite" style={[s.chipTx, { color: chip.c }]}>{chip.t}</Text>
        </View>
        <Phrase top={phrase.top} bottom={phrase.bottom} df={df} />
        <Text style={s.sub}>{runner}가 곧 러닝을 시작해요 · 시작하면 실시간 보기가 열려요</Text>
        <View style={s.opts}>
          {/* 금색 = 세리머니(여권·도장·영수증). 봉인된 인계 기록이 정확히 그것이고, 미트업의
              SEALED 블록이 정직한 착지점이다. `dot` 과 `leash` 는 뺐다 — 맥박은 '지금 하라'는
              주장이고, 목줄은 넘기는 동작의 그림이다. 둘 다 끝난 일에 대해서는 거짓말이다.
              [fix/client-review-3 · Codex 2026-09-25 c4] openNext used to send a LATE sealed
              handoff to 내 일정, which has no record door — this label was false on exactly that
              case. `home-hero-route.ts` ①′ now routes `handoff` to the meetup above the lateness
              arm, so 「인계 기록을 확인해요」 is true in every lateness state; the late fact stays
              on screen in `lateStrip` above. */}
          <DrawButton title="티켓 보기" sub="인계 기록을 확인해요" ground="gold" art="ticket"
            onPress={openNext} accessibilityLabel="티켓 보기" />
          <DrawButton title="채팅" sub="러너에게 물어보세요" meta={chatBadge} ground="lilac" art="chat"
            small onPress={openChat} accessibilityLabel={chatLabel('러너에게 물어보세요')} />
        </View>
      </View>
    );
  }

  // ── [0188] returning: 내 차례 — the run is over and the dog is coming home ─────
  // The coral chip and one primary, but nothing has arrived: the run has ENDED, and what is owed
  // is a confirmation rather than a meeting. No live widget and no elapsed clock: both would be
  // claims about a run in progress.
  //
  // ⚠ [2026-09-25 owner-journey-1] The late strip is GONE from this frame and this frame only.
  // (Named in prose, not quoted as JSX — a comment carrying the removed token is a false green for
  // every later grep that hunts it, which is the standing comment-quoting law in CLAUDE.md.)
  // `lateness()` reads `started` off `rawStatus === 'active'`, and the run-end ceremony leaves the
  // booking `active` through the whole two-stamp return — so an overrun return printed
  // 「러닝이 예정보다 N분 길어지고 있어요」 directly above 「러닝이 끝났어요」, after the server had
  // already written `run_ended_at`. One frame contradicting itself, and the strip was the half
  // that was false. It stays in every other frame, where `active` still means running.
  if (state === 'returning') {
    return (
      <View style={s.wrapTight}>
        {errRow}
        <View style={s.chipRow}>
          <View style={[s.chipDot, { backgroundColor: chip.c }]} />
          <Text accessibilityLiveRegion="polite" style={[s.chipTx, { color: chip.c }]}>{chip.t}</Text>
        </View>
        <Phrase top={phrase.top} bottom={phrase.bottom} df={df} />
        <Text style={s.sub}>{runner}가 {name}를 돌려주고 있어요 · 받으셨으면 확인해주세요</Text>
        <View style={s.opts}>
          <DrawButton title="인계 확인하기" sub="둘 다 확인해야 마무리돼요" ground="coral" art="leash"
            dot onPress={openNext} accessibilityLabel="인계 확인하기" />
          <DrawButton title="채팅" sub="만나는 곳을 정해요" meta={chatBadge} ground="lilac" art="chat"
            small onPress={openChat} accessibilityLabel={chatLabel('만나는 곳을 정해요')} />
        </View>
      </View>
    );
  }

  const inFlight = state === 'searching' || state === 'directed' || state === 'confirmed';

  const subline =
    state === 'confirmed'
      ? (isLate ? (
        // [T6] 「시작하지 못했어요」는 참이지만 누가 오지 않았는지는 말하지 않았다. lateness()가
        // 그걸 안다 — arrived_at 이 찍혔으면 러너는 왔고 인계가 안 된 것이고, 아니면 러너가
        // 오지 않은 것이다. 둘은 보호자에게 완전히 다른 사실이다.
        // ⚠ 여기서 수수료를 말하지 않는다. 취소는 사다리가 있고(0066), 그 숫자는 조건이 적힌
        // 일정 시트가 말한다 — 히어로가 값을 주장하면 그게 거짓말이 된다 (:256 의 기존 규칙).
        late?.late && late.waitingOn === 'owner'
          // [A④] 「도착했지만 인계되지 않았어요」는 참이지만 **얼마나**를 말하지 않았다. 그 값도
          // 이미 있다 (lateness().waitMs 와 같은 근거인 arrived_at). 1분 미만이면 절이 빠진다.
          ? `${when} · 러너가 도착했지만 인계되지 않았어요${doorWait ? ` · ${doorWait}째 문 앞이에요` : ''}`
          : late?.late
            ? `${when} · 러너가 도착하지 않았어요`
            : `${when}에 시작하지 못했어요`)
        // [A④] 아직 늦지 않았어도 러너가 도착해 있으면 그게 이 순간의 사실이다 — 「확정」은
        // 그때 이미 지난 이야기다. arrived_at 이 없으면(= 오는 중) 문장은 그대로 확정 줄이다.
        : arrivedWaiting
          ? `${runner}가 도착했어요${doorWait ? ` · ${doorWait}째 문 앞이에요` : ''}`
          // [A①] D-라벨 꼬리표가 빠졌다 — 이제 1행이 그 값을 말한다. 한 화면에 두 번 쓰지 않는다.
          : `${when ? when + ' · ' : ''}${runner} 확정`)
      : state === 'directed' ? `${runner}에게 지명 요청을 보냈어요`
        : state === 'searching' ? '보통 몇 분 안에 응답이 와요'
          : `${name}와 달릴 시간을 잡아보세요`;
  // Basis for the live dot. Zero means no dot and a sentence that says so.
  // ⚠ `null` = we have not successfully read the count. A failed or pending read must NOT become
  // 「지금은 대기 중인 러너가 없어요」 — that is an affirmative claim about the world printed on
  // the funnel's primary CTA, and it was reachable on every cold start and every flaky network.
  // Unknown falls back to the neutral invitation, which is true regardless of who is online.
  // [Sean 2026-08-26] 서브라인 문장이 **수치 한 조각**이 된다: 「지금 러너 7명이 대기 중이에요」
  // → 제목 옆 「7명 대기」. 그의 지시는 두 큰 버튼의 서브텍스트를 지우고 지금 찾기 옆에 n명
  // 대기를 붙이라는 것이었고, 사실은 그대로 남기되 문장이 차지하던 줄을 제목에 돌려준다.
  // ⚠ null(못 읽음)은 여전히 아무 말도 하지 않는다 — 위 주석의 이유 그대로다. 0은 말한다:
  //   「0명 대기」는 참이고, 이 값이 사라지면 「대기 중인 러너가 없다」는 사실을 말하던 유일한
  //   자리가 화면에서 없어진다. 조용한 0은 여기서 오답이다.
  const waitMeta = onlineRunners == null
    ? null
    : onlineRunners >= 10 ? '10명+ 대기' : `${onlineRunners}명 대기`;

  return (
    <View style={s.wrap}>
      {errRow}
      {/* [HIG A3] Android's live region for the state chip — the iOS side is `heroSentence`
          above. polite, and on the CHIP rather than the headline: the chip is the one word that
          changes when the booking moves, and a live region on the two-line headline would re-read
          the dog's name every time. */}
      <View style={s.chipRow}>
        <View style={[s.chipDot, { backgroundColor: chip.c }]} />
        <Text accessibilityLiveRegion="polite" style={[s.chipTx, { color: chip.c }]}>{chip.t}</Text>
      </View>
      <Phrase top={phrase.top} bottom={phrase.bottom} df={df} topNum={topIsNum} />
      <Text style={s.sub}>{subline}</Text>

      <View style={s.opts}>
        {state === 'none' && (
          <DrawButton title="지금 찾기" meta={waitMeta} ground="coral" art="dog"
            dot={(onlineRunners ?? 0) > 0} sheen onPress={findNow}
            accessibilityLabel={waitMeta ? `지금 찾기, ${waitMeta}` : '지금 찾기'} />
        )}
        {(state === 'searching' || state === 'directed') && (
          <DrawButton title={state === 'searching' ? '레이더 보기' : '요청 보기'}
            sub={state === 'searching' ? '요청 상황을 볼 수 있어요' : '러너 응답을 기다려요'}
            ground="blue" art="radar" onPress={openNext} />
        )}
        {/* ⚠ 금색은 **세리머니 색**(여권·도장·영수증)이다. 지난 예약은 기념할 티켓이 아니라
            정리해야 할 행정 건이므로 금색을 주면 뜻이 뒤집힌다 — 중립 페이퍼로 간다.
            앞으로의 확정 건만 진짜 티켓이고, 그때만 금색을 쓴다. */}
        {/* ⚠ 지난 건은 amber(= paper.pending의 워시)다. 이유 둘:
              ① 시맨틱 — '주의가 필요한 미해결 상태'이지 중립 문서가 아니다.
              ② 충돌 회피 — paper로 두면 바로 아래 '미리 예약'과 **같은 색 두 개**가 된다
                 (Sean 2026-08-20 지적). 같은 바탕 두 개는 위계가 아니라 반복이다.
              ⚠ 서브라인이 「정리할 수 있어요」에서 바뀐 것도 정직 문제다: 확정 건 취소는
              수수료 구간(<24h 10%, 절반은 러너 몫)이 있어 '정리'가 공짜라는 함의를 줄 수 없다.
            서버가 만료를 처리하기 전까지 홈은 사실만 말하고 목적지는 일정 화면이다. */}
        {/* ⚠ [2026-09-25 owner-journey-1] 이 버튼은 `isLate` 가 아니라 `lateDoorClosed` 로
            갈린다. 둘이 갈라지는 칸이 정확히 하나 있고 그 칸이 이 결함의 전부였다: 러너가
            도착해 있고(arrived_at) 아직 천장(3h) 안인 지각 건. 거기서는 진행할 문이 **실제로
            남아 있으므로** 「일정에서 정리하기」가 거짓 라벨이 된다 — openNext 도 같은 조건으로
            미트업을 연다(home-hero-route.ts ②). 문이 닫힌 나머지 지각 건만 amber 로 남는다.
            ⚠ 코랄은 여기 오지 않는다. 도착 프레임의 채도는 Sean 의 재정 대기다. */}
        {state === 'confirmed' && (
          <DrawButton
            // [T6] 「예약 확인 / 아직 정리되지 않았어요」는 사실이지만 막다른 골목이었다 — 16일간
            // 그 자리에 있던 문장이다. 목적지를 말하는 라벨로 바꾼다. 여전히 공짜라고는 하지 않는다.
            title={lateDoorClosed ? '일정에서 정리하기' : '티켓 보기'}
            sub={lateDoorClosed ? '취소 조건을 확인하고 닫아요' : '시간과 장소를 확인해요'}
            ground={lateDoorClosed ? 'amber' : 'gold'} art="ticket" onPress={openNext} />
        )}
        {state === 'confirmed' && (
          <DrawButton title="채팅" sub="러너에게 물어보세요" meta={chatBadge}
            ground="lilac" art="chat" small onPress={openChat} accessibilityLabel={chatLabel('러너에게 물어보세요')} />
        )}
        {/* 서브 「날짜와 시간을 골라요」 은퇴 (Sean 2026-08-26) — 제목이 이미 그 말이다. */}
        <DrawButton title="미리 예약" ground="paper" art="calendar"
          small={inFlight} onPress={schedule} accessibilityLabel="미리 예약" />
      </View>
    </View>
  );
}


const s = StyleSheet.create({
  wrap: { paddingHorizontal: layout.gutter, paddingTop: 12, paddingBottom: 6 },
  wrapTight: { paddingHorizontal: layout.gutter, paddingTop: 12, paddingBottom: 6 },
  title: { fontSize: 24, fontWeight: '900', color: paper.ink, marginTop: 8, lineHeight: 30 },
  // [2026-08-25 Sean] 14 → 15 — 한글 작업 플로어 상향(DESIGN.md §2 개정). 아래 알림/지각/칩도 같다.
  quiet: { fontSize: 15, color: paper.dim, marginTop: 8, lineHeight: 21 },
  // 알림 줄 부품 — 점 · 굵은 줄 · 얇은 줄 · 우측 행동. 카드 아님, 룰 하나(아래).
  alertRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: '#EEEEEE', minHeight: 44 },
  alertHot: { backgroundColor: paper.wash, marginHorizontal: -layout.gutter, paddingHorizontal: layout.gutter, borderBottomWidth: 0 },
  dot: { width: 8, height: 8, borderRadius: 4 },
  // 지각 한 줄 — 헤드라인이 아니라 사실 띠. critical 워시는 F1.2 라우드-페일 토큰 그대로.
  lateStrip: {
    flexDirection: 'row', alignItems: 'center', gap: 7,
    backgroundColor: paper.criticalWash, borderWidth: 1, borderColor: '#F0CFC6',
    paddingVertical: 9, paddingHorizontal: 11, marginTop: 8,
  },
  // [타입 플로어 2026-08-24] 13 → 14. 한글은 레터스페이스 라틴 킥커 면제를 타지 못한다 (DESIGN.md §3,
  // 2026-08-10 감사 법) — 그리고 이건 크리티컬 문장이라 가장 작으면 안 되는 줄이다.
  // [2026-08-25 Sean] 같은 이유로 한 칸 더: 14 → 15 (작업 플로어).
  lateStripTx: { flex: 1, fontSize: 15, fontWeight: '700', color: paper.critical, lineHeight: 21 },
  alertMain: { fontSize: 15, fontWeight: '800', color: paper.ink, lineHeight: 21 },
  alertSub: { fontSize: 15, color: paper.dim, marginTop: 1, lineHeight: 21 },
  alertAct: { fontSize: 15, fontWeight: '800' },
  // ── v3 히어로 (Sean 2026-08-20) ──────────────────────────────────────────
  // 상태 칩 · 마크가 내려앉는 문구 · 서브라인 · 그림 버튼들.
  chipRow: { flexDirection: 'row', alignItems: 'center', gap: 7, marginTop: 2 },
  chipDot: { width: 9, height: 9, borderRadius: 5 },
  // [타입 플로어 2026-08-24] 13 → 14, 트래킹 1.4 → 0.6. 칩 문구는 전부 한글(확정됨 · 내 차례 ·
  // 찾는 중 · 응답 대기)이고 한글은 킥커 면제 밖이다. 랩의 모든 변형 프레임이 이 값으로 그려졌다.
  // [2026-08-25 Sean] 14 → 16: 플로어(15)만 넘긴 게 아니라 §3b 의 상태 칩 스펙(16/800)에 맞췄다.
  // 같은 어휘(확정됨 · LIVE …)를 쓰는 칩이 화면마다 다른 크기일 이유가 없다.
  chipTx: { fontSize: 16, lineHeight: 21, fontWeight: '800', letterSpacing: 0.6 },
  phw: { marginTop: 6, minHeight: 108 },
  // 38pt 디스플레이 — 이 화면의 Black Han Sans 사용 1회. 마스트헤드 워드마크는
  // home.tsx에서 본문 900으로 내려가 §3의 '화면당 1회' 예산을 지킨다.
  phr: { fontSize: 43, lineHeight: 50, color: paper.ink, fontWeight: '400' },
  // D-라벨 전용 — Oswald 는 어센더가 높아 43×1.16(=50)에서 잘린다 (BUG A). 1.21× 로 올린다.
  // 두 줄 합계 102 < phw.minHeight 108 이라 레이아웃은 그대로다.
  phrNum: { lineHeight: 52 },
  sub: { fontSize: 17, color: paper.dim, marginTop: 10, lineHeight: 24 },
  opts: { marginTop: 14, gap: 10 },
});
