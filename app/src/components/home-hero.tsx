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
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { haptic } from '../lib/haptics';
import { draft } from '../store';
import { paper } from '../theme';

export type HomeGoState = 'none' | 'searching' | 'directed' | 'confirmed' | 'handoff' | 'active';

export interface HomeHeroNext {
  id: string;
  runnerName?: string | null;
  timeLabel?: string;     // "19:30"
  dateLabel?: string;     // "오늘" · "내일" · "8월 20일"
  km?: number;
}

interface Props {
  state: HomeGoState;
  next: HomeHeroNext | null;
  dogName: string | null;
  loadState: 'loading' | 'ready' | 'error';
  onRetry: () => void;
  ddayLabel?: string | null;
  /** active 상태에서 라이브 위젯을 렌더할 슬롯. home.tsx가 이미 가진 위젯을 그대로 넘긴다. */
  liveWidget?: React.ReactNode;
}

const GO_SAGE = '#119B58';   // home.tsx와 같은 값 — 확정·준비됨
const WAIT_BLUE = '#6C5CE7'; // lilac.accent — 대기

export function HomeHero({ state, next, dogName, loadState, onRetry, ddayLabel, liveWidget }: Props) {
  const name = dogName ?? '우리 아이';

  // 지금 찾기 = 요청 화면의 pickEarliest 경로. 새 화면 없음 — 홈이 그걸 묻어 두던 걸 그만둘 뿐.
  const findNow = () => { haptic('light'); draft.autoEarliest = true; router.push('/owner/request'); };
  const schedule = () => { haptic('light'); draft.autoEarliest = false; router.push('/owner/request'); };
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
        <Text style={s.title}>{name}, 오늘은?</Text>
        <Text style={s.quiet}>예약을 확인하는 중이에요</Text>
      </View>
    );
  }
  if (loadState === 'error') {
    return (
      <View style={s.wrap}>
        <View style={s.alertRow}>
          <View style={[s.dot, { backgroundColor: paper.critical }]} />
          <Text style={[s.alertMain, { color: paper.critical }]}>예약을 불러오지 못했어요</Text>
          <Pressable onPress={onRetry} hitSlop={8} accessibilityRole="button">
            <Text style={[s.alertAct, { color: paper.critical }]}>다시 시도</Text>
          </Pressable>
        </View>
      </View>
    );
  }

  // ── active: 라이브 위젯이 존을 대체 ───────────────────────────────────────
  if (state === 'active') {
    return <View style={s.wrapTight}>{liveWidget}</View>;
  }

  const when = next ? [next.dateLabel, next.timeLabel].filter(Boolean).join(' ') : '';
  const runner = next?.runnerName ? `${next.runnerName} 러너` : '러너';

  // ── handoff: 내 차례 — 알림 줄 하나, 버튼 없음 ───────────────────────────
  if (state === 'handoff') {
    return (
      <View style={s.wrapTight}>
        <Pressable onPress={openNext} style={[s.alertRow, s.alertHot]} accessibilityRole="button" accessibilityLabel="인계 확인">
          <View style={[s.dot, { backgroundColor: paper.action }]} />
          <View style={{ flex: 1 }}>
            <Text style={s.alertMain}>{runner} 도착</Text>
            <Text style={s.alertSub}>{name}를 인계하고 확인해주세요</Text>
          </View>
          <Text style={[s.alertAct, { color: paper.action, fontSize: 14.5 }]}>인계 확인 ›</Text>
        </Pressable>
      </View>
    );
  }

  const inFlight = state === 'searching' || state === 'directed' || state === 'confirmed';
  return (
    <View style={s.wrap}>
      {inFlight && next && (
        <Pressable onPress={openNext} style={s.alertRow} accessibilityRole="button">
          <View style={[s.dot, { backgroundColor: state === 'confirmed' ? GO_SAGE : WAIT_BLUE }]} />
          <View style={{ flex: 1 }}>
            <Text style={s.alertMain}>
              {when && `${when} · `}
              {state === 'confirmed' ? `${runner} 확정` : state === 'directed' ? `${runner} 응답 대기` : '러너 찾는 중'}
            </Text>
            <Text style={s.alertSub}>
              {state === 'confirmed'
                ? (ddayLabel ? `${ddayLabel}` : '시간에 맞춰 알려드려요')
                : state === 'directed' ? '지명 요청을 보냈어요' : '보통 몇 분 안에 응답이 와요'}
            </Text>
          </View>
          <Text style={[s.alertAct, { color: state === 'confirmed' ? GO_SAGE : WAIT_BLUE }]}>
            {state === 'confirmed' ? '티켓 ›' : '보기 ›'}
          </Text>
        </Pressable>
      )}

      <Text style={s.title}>{inFlight ? '다른 날도 잡아둘까요?' : `${name}, 오늘은?`}</Text>

      <View style={{ marginTop: 14, gap: 9 }}>
        {/* 지금 찾기 — none 에서만. 진행 중이면 자기 자신과 경쟁시키는 것이다. */}
        {!inFlight && (
          <Pressable onPress={findNow} style={({ pressed }) => [s.opt, s.optA, pressed && { opacity: 0.92 }]}
            accessibilityRole="button" accessibilityLabel="지금 찾기">
            <View>
              <Text style={[s.optT, { color: '#fff' }]}>지금 찾기</Text>
              <Text style={[s.optD, { color: '#FFD9CE' }]}>가장 빠른 시간 · 5km · {name}</Text>
            </View>
            <Text style={[s.optArr, { color: '#FFD9CE' }]}>›</Text>
          </Pressable>
        )}
        <Pressable onPress={schedule} style={({ pressed }) => [s.opt, s.optB, pressed && { backgroundColor: paper.wash }]}
          accessibilityRole="button" accessibilityLabel="예약하기">
          <View>
            <Text style={[s.optT, { color: paper.ink }]}>예약하기</Text>
            <Text style={[s.optD, { color: paper.dim }]}>날짜와 시간을 골라 잡아둬요</Text>
          </View>
          <Text style={[s.optArr, { color: paper.ink }]}>›</Text>
        </Pressable>
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { paddingHorizontal: 18, paddingTop: 12, paddingBottom: 6 },
  wrapTight: { paddingHorizontal: 18, paddingTop: 12, paddingBottom: 6 },
  title: { fontFamily: 'BlackHanSans', fontSize: 24, color: paper.ink, marginTop: 8, lineHeight: 30 },
  quiet: { fontSize: 14, color: paper.dim, marginTop: 8, lineHeight: 20 },
  // 알림 줄 부품 — 점 · 굵은 줄 · 얇은 줄 · 우측 행동. 카드 아님, 룰 하나(아래).
  alertRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: '#EEEEEE', minHeight: 44 },
  alertHot: { backgroundColor: paper.wash, marginHorizontal: -18, paddingHorizontal: 18, borderBottomWidth: 0 },
  dot: { width: 8, height: 8, borderRadius: 4 },
  alertMain: { fontSize: 14, fontWeight: '800', color: paper.ink, lineHeight: 19 },
  alertSub: { fontSize: 14, color: paper.dim, marginTop: 1, lineHeight: 19 },
  alertAct: { fontSize: 14, fontWeight: '800' },
  // 두 옵션 — Fitts: 큰 면, 엄지가 닿는 곳. Von Restorff: 둘 중 하나만 채도.
  opt: { paddingVertical: 19, paddingHorizontal: 16, minHeight: 104, flexDirection: 'row', alignItems: 'flex-end', justifyContent: 'space-between' },
  optA: { backgroundColor: paper.action },
  optB: { backgroundColor: paper.canvas, borderWidth: 1.5, borderColor: paper.ink },
  optT: { fontFamily: 'BlackHanSans', fontSize: 24, lineHeight: 28 },
  optD: { fontSize: 14, marginTop: 5, lineHeight: 19 },
  optArr: { fontSize: 22, lineHeight: 26 },
});
