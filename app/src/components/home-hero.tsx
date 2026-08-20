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
//   handoff             → 알림 줄(코랄 = 내 차례) — 버튼 없음. 지금 할 일은 인계 확인 하나뿐이다.
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
import { useDisplayFont } from '../lib/displayFont';
import { haptic } from '../lib/haptics';
import { draft } from '../store';
import { paper } from '../theme';
import { DrawButton } from './draw-button';

export type HomeGoState = 'none' | 'searching' | 'directed' | 'confirmed' | 'handoff' | 'active';

export interface HomeHeroNext {
  id: string;
  runnerName?: string | null;
  timeLabel?: string;     // "19:30"
  dateLabel?: string;     // "오늘" · "내일" · "8월 20일"
  /** 이 예약의 아이 (bookings.dogs.name). 아래 `dogName` prop(첫 등록 아이)보다 항상 우선한다. */
  dogName?: string | null;
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
  ddayLabel?: string | null;
  /** 이 예약의 예정 시각이 이미 지났는가 (KST 날짜 칸 기준, home.tsx가 계산).
   *  ddayLabel = null 은 "카운트다운을 그리지 않는다"는 뜻일 뿐 "아직 안 왔다"는 뜻이 아니다 —
   *  그 둘을 한 채널에 뭉쳤던 것이 8월 4일 예약에 "시간에 맞춰 알려드려요"를 인쇄한 원인이다. */
  nextIsPast?: boolean;
  /** active 상태에서 라이브 위젯을 렌더할 슬롯. home.tsx가 이미 가진 위젯을 그대로 넘긴다. */
  liveWidget?: React.ReactNode;
  /** 지금 온라인인 동네 러너 수 (fetchCertifiedRunners는 이미 `.eq('online', true)`로 거른다).
   *  라이브 점은 **이 값이 0보다 클 때만** 켜진다 — 0명인데 맥박을 그리면 그 점은 거짓말이고,
   *  한 번 거짓이 되면 인계 화면의 점까지 못 믿게 된다. `.limit(10)` 때문에 10 이상은
   *  '10명 이상'으로 말한다 (모르는 수를 아는 척하지 않는다). */
  onlineRunners?: number;
}

const GO_SAGE = '#119B58';   // home.tsx와 같은 값 — 확정·준비됨
const WAIT_BLUE = '#6C5CE7'; // lilac.accent — 대기

// ── 히어로 문구 = 상태 그 자체 (Sean 2026-08-20, `home-full-lab.html`) ──────────────────
// 마크가 문구의 오른쪽 여백에 내려앉기 때문에 **1행은 마크 자리를 비워야 한다**. 랩에서
// 「s4kim2025 러너의 / 응답을 기다려요」가 마크와 겹치는 걸 보고 얻은 법이고, 여기서는 카피
// 규율이 아니라 **레이아웃**으로 강제한다: 1행 Text에만 오른쪽 패딩을 주고 2행은 전폭을 쓴다.
// 그래서 이름·장소처럼 길이를 모르는 값은 항상 2행이나 서브라인으로 간다.
const MARK_W = 104;

function Phrase({ top, bottom, df }: { top: string; bottom: string; df: any }) {
  return (
    <View style={s.phw}>
      <View style={{ position: 'absolute', right: -2, top: -4, zIndex: 1 }} pointerEvents="none">
        <Image
          source={require('../../assets/logo-alpha.png')}
          style={{ width: 66 * (1619 / 971), height: 66 }}
          resizeMode="contain"
          accessibilityRole="image"
          accessibilityLabel="도그스하이"
        />
      </View>
      <Text style={[s.phr, df, { paddingRight: MARK_W }]} numberOfLines={1}>{top}</Text>
      <Text style={[s.phr, df]} numberOfLines={1}>{bottom}</Text>
    </View>
  );
}

export function HomeHero({ state, next, dogName, dialKm, loadState, onRetry, ddayLabel, nextIsPast, liveWidget, onlineRunners = 0 }: Props) {
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
  const openNext = () => {
    if (!next) return;
    draft.bookingId = next.id;
    if (state === 'active') router.push('/owner/live');
    else if (state === 'handoff' || state === 'confirmed') router.push('/owner/meetup');
    else router.push('/owner/radar');
  };

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

  // ── active: 라이브 위젯이 존을 대체 ───────────────────────────────────────
  if (state === 'active') {
    return <View style={s.wrapTight}>{errRow}{liveWidget}</View>;
  }

  const when = next ? [next.dateLabel, next.timeLabel].filter(Boolean).join(' ') : '';
  const runner = next?.runnerName ? `${next.runnerName} 러너` : '러너';

  const openChat = () => {
    haptic('light');
    if (next) router.push(`/chat?bid=${next.id}`);
    else router.push('/chat');
  };

  // ── handoff: 내 차례 — 화면에서 유일하게 급한 순간이라 코랄 면을 쓴다 ─────
  // 미리 예약은 여기서 **사라진다**. 러너가 문 앞에 서 있는데 다음 예약을 권하는 건
  // 선택지가 아니라 방해다.
  if (state === 'handoff') {
    return (
      <View style={s.wrapTight}>
        {errRow}
        <View style={s.chipRow}>
          <View style={[s.chipDot, { backgroundColor: paper.action }]} />
          <Text style={[s.chipTx, { color: paper.action }]}>내 차례</Text>
        </View>
        <Phrase top="지금 만나요" bottom={`${name} 인계할 시간`} df={df} />
        <Text style={s.sub}>{runner}가 도착했어요 · 만나서 인계해주세요</Text>
        <View style={s.opts}>
          <DrawButton title="인계하기" sub="아이를 넘기고 봉인해요" ground="coral" art="leash"
            dot onPress={openNext} accessibilityLabel="인계하기" />
          <DrawButton title="채팅" sub="늦으면 알려주세요" ground="lilac" art="chat"
            small onPress={openChat} />
        </View>
      </View>
    );
  }

  const inFlight = state === 'searching' || state === 'directed' || state === 'confirmed';

  // 상태별 문구·칩·버튼. 1행은 항상 짧게(마크 자리) — 이름·시각처럼 길이를 모르는 값은
  // 2행이나 서브라인으로 내려보낸다.
  // ⚠ 지난 예약에 '확정됨'을 찍지 않는다. 시뮬레이터에서 초록 확정 칩 위에 「지난 예약이 하나
  // 있어요」가 같이 뜬 걸 보고 잡았다 — 칩과 문구가 서로를 반박하면 둘 다 못 믿게 된다.
  // 상태색 법의 초록은 '준비됨'이지 '지나갔음'이 아니므로, 지난 건은 중립 딤으로 내려간다.
  const chip =
    state === 'confirmed' ? (nextIsPast ? { c: paper.dim, t: '지난 예약' } : { c: GO_SAGE, t: '확정됨' })
      : state === 'directed' ? { c: WAIT_BLUE, t: '응답 대기' }
        : state === 'searching' ? { c: WAIT_BLUE, t: '찾는 중' }
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
  const shortDate = next?.dateLabel && next.dateLabel.length <= 4 ? next.dateLabel : '곧';
  const phrase =
    state === 'confirmed'
      ? (nextIsPast ? { top: '예약 시간이', bottom: '지났어요' } : { top: shortDate, bottom: `${name}가 달려요` })
      : state === 'directed' ? { top: '응답을', bottom: '기다려요' }
        : state === 'searching' ? { top: '러너를', bottom: '찾고 있어요' }
          : { top: '오늘은 아직', bottom: '비어 있어요' };
  const subline =
    state === 'confirmed'
      ? (nextIsPast ? `${when} · 일정에서 확인하거나 취소해주세요`
        : `${when ? when + ' · ' : ''}${runner} 확정${ddayLabel ? ' · ' + ddayLabel : ''}`)
      : state === 'directed' ? `${runner}에게 지명 요청을 보냈어요`
        : state === 'searching' ? '보통 몇 분 안에 응답이 와요'
          : `${name}와 달릴 시간을 잡아보세요`;
  // 라이브 점의 근거. 0명이면 점도 없고 문장도 그렇게 말한다.
  const runnersLine = onlineRunners > 0
    ? `지금 러너 ${onlineRunners >= 10 ? '10명 이상이' : onlineRunners + '명이'} 대기 중이에요`
    : '지금은 대기 중인 러너가 없어요';

  return (
    <View style={s.wrap}>
      {errRow}
      <View style={s.chipRow}>
        <View style={[s.chipDot, { backgroundColor: chip.c }]} />
        <Text style={[s.chipTx, { color: chip.c }]}>{chip.t}</Text>
      </View>
      <Phrase top={phrase.top} bottom={phrase.bottom} df={df} />
      <Text style={s.sub}>{subline}</Text>

      <View style={s.opts}>
        {state === 'none' && (
          <DrawButton title="지금 찾기" sub={runnersLine} ground="coral" art="dog"
            dot={onlineRunners > 0} sheen onPress={findNow} accessibilityLabel="지금 찾기" />
        )}
        {(state === 'searching' || state === 'directed') && (
          <DrawButton title={state === 'searching' ? '레이더 보기' : '요청 보기'}
            sub={state === 'searching' ? '요청 상황을 볼 수 있어요' : '러너 응답을 기다려요'}
            ground="blue" art="radar" onPress={openNext} />
        )}
        {state === 'confirmed' && (
          <DrawButton title={nextIsPast ? '보기' : '티켓 보기'} sub="시간과 장소를 확인해요"
            ground="gold" art="ticket" onPress={openNext} />
        )}
        {state === 'confirmed' && (
          <DrawButton title="채팅" sub="러너에게 물어보세요"
            ground="lilac" art="chat" small onPress={openChat} />
        )}
        <DrawButton title="미리 예약" sub="날짜와 시간을 골라요" ground="paper" art="calendar"
          small={inFlight} onPress={schedule} accessibilityLabel="미리 예약" />
      </View>
    </View>
  );
}


const s = StyleSheet.create({
  wrap: { paddingHorizontal: 18, paddingTop: 12, paddingBottom: 6 },
  wrapTight: { paddingHorizontal: 18, paddingTop: 12, paddingBottom: 6 },
  title: { fontSize: 24, fontWeight: '900', color: paper.ink, marginTop: 8, lineHeight: 30 },
  quiet: { fontSize: 14, color: paper.dim, marginTop: 8, lineHeight: 20 },
  // 알림 줄 부품 — 점 · 굵은 줄 · 얇은 줄 · 우측 행동. 카드 아님, 룰 하나(아래).
  alertRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: '#EEEEEE', minHeight: 44 },
  alertHot: { backgroundColor: paper.wash, marginHorizontal: -18, paddingHorizontal: 18, borderBottomWidth: 0 },
  dot: { width: 8, height: 8, borderRadius: 4 },
  alertMain: { fontSize: 14, fontWeight: '800', color: paper.ink, lineHeight: 19 },
  alertSub: { fontSize: 14, color: paper.dim, marginTop: 1, lineHeight: 19 },
  alertAct: { fontSize: 14, fontWeight: '800' },
  // ── v3 히어로 (Sean 2026-08-20) ──────────────────────────────────────────
  // 상태 칩 · 마크가 내려앉는 문구 · 서브라인 · 그림 버튼들.
  chipRow: { flexDirection: 'row', alignItems: 'center', gap: 7, marginTop: 2 },
  chipDot: { width: 9, height: 9, borderRadius: 5 },
  chipTx: { fontSize: 13, fontWeight: '800', letterSpacing: 1.4 },
  phw: { marginTop: 6, minHeight: 108 },
  // 38pt 디스플레이 — 이 화면의 Black Han Sans 사용 1회. 마스트헤드 워드마크는
  // home.tsx에서 본문 900으로 내려가 §3의 '화면당 1회' 예산을 지킨다.
  phr: { fontSize: 43, lineHeight: 50, color: paper.ink, fontWeight: '400' },
  sub: { fontSize: 17, color: paper.dim, marginTop: 10, lineHeight: 24 },
  opts: { marginTop: 14, gap: 10 },
});
