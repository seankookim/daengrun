import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Alert, Animated, Easing, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { PaperBtn } from '../../src/components/paper-btn';
import { Avatar } from '../../src/components/ui';
import {
  cancelBooking, fetchAvailableRunnersFor, fetchBookingBrief, fetchBookingCard,
  LiveRunner, requestRunner, subscribeBooking,
} from '../../src/lib/api';
import { haptic } from '../../src/lib/haptics';
import { draft } from '../../src/store';
import { layout, lilac, paper } from '../../src/theme';

// 러너 찾는 중 — journey-v3 §C frame 4 (Sean 2026-08-19, RULING 7).
//
// ═══ 시계는 갔다 ═══
// "애니메이션 ≠ 카운터". 이 화면에는 숫자가 하나도 없다 — 경과 M:SS 도, 10분 앰버 넛지도 없다.
// 넛지가 말하려던 것("직접 지명하면 응답 확률이 올라가요")은 화면 아래 **상시** 지명 목록이 되었다.
// 조건부로 뜨는 조언보다 언제나 거기 있는 버튼이 정직하다.
//
// ═══ 화면은 rawStatus의 함수다 ═══
// 지명에 성공해도 이 화면에 남는다. 그러면 헤더가 '러너 찾는 중'인 채로 진실은
// '지명 응답 대기'인 순간이 생기는데, 그건 표시 어휘가 서버 상태를 뭉개는 것이다 (정직법).
// 그래서 헤더 · 알림 줄 · 목록 행이 전부 rawStatus에서 나온다:
//   matching        → "러너 찾는 중"           · "가까운 러너에게 요청을 보냈어요"
//   runner_pending  → "{러너} 러너 응답 대기"  · "지명 요청을 보냈어요" · 그 행은 '지명됨'
//   confirmed+      → 확정 문장 후 1.8초 뒤 일정으로 (오늘과 동일)
// 다른 러너는 계속 지명 가능하다 — 서버가 matching·runner_pending 둘 다에서 재지명을 허용한다
// (transition-booking 엣지 함수의 request_runner 분기: 확정 전 두 상태만 통과시킨다).
// 서버가 거절하면(409) 그 문장을 그대로 보여준다.
// ⚠ 줄 번호로 인용하지 않는다 — 종전 주석의 `:163`은 이미 어긋나 있었다. 심볼은 안 움직인다.
//
// ═══ 정직 ═══
// 알림 줄의 필드는 이 예약의 실제 행에서 온다. 없는 필드는 자리표시자 없이 안 그린다.
// 목록은 이 예약에 실제로 갈 수 있는 러너만 (수락 게이트의 표시측 거울) — 지명했는데
// 수락이 불가능한 러너를 목록에 올리지 않는다. 실패는 실패로, 빈 목록은 빈 목록으로.

// 코랄 물결 — 잔잔한 리플이 퍼져나간다 (소나가 아니라 산책로 물웅덩이 느낌).
// [2026-08-19] 모션은 그대로 (3200ms · out(cubic) · 1→2.5 · .4→.14→0 · 네이티브 드라이버).
// 색만 은퇴한 colors.tang → paper.action. Sean: "지금 코드의 링을 그대로 쓴다".
// Statuses that end the search but are neither a match nor `cancelled*`/`expired` (which have
// their own arms in the poll below). Each states what happened and what continues — never a
// delay this screen is not actually polling for. Landing screen for all of them is 내 일정,
// whose badges pick the story up where the alert leaves off.
const TERMINAL_ON_RADAR: Record<string, { title: string; body: string }> = {
  refund_pending: { title: '환불이 진행 중이에요', body: '이 예약은 환불 절차로 넘어갔어요 — 처리되면 알림으로 알려드릴게요' },
  no_show: { title: '불발로 처리됐어요', body: '이 예약은 진행되지 않았어요 — 자세한 내용은 알림으로 알려드릴게요' },
  incident_review: { title: '확인이 진행 중이에요', body: '이 예약은 확인 절차로 넘어갔어요 — 처리되면 알림으로 알려드릴게요' },
  completed: { title: '이미 끝난 러닝이에요', body: '기록은 내 일정에서 볼 수 있어요' },
};

function Ripple({ delay }: { delay: number }) {
  const v = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const loop = Animated.loop(
      Animated.timing(v, { toValue: 1, duration: 3200, delay, easing: Easing.out(Easing.cubic), useNativeDriver: true }),
    );
    loop.start();
    return () => loop.stop();
  }, [v, delay]);
  return (
    <Animated.View
      pointerEvents="none"
      style={{
        position: 'absolute', width: 130, height: 130, borderRadius: 65,
        borderWidth: 2, borderColor: paper.action,
        opacity: v.interpolate({ inputRange: [0, 0.6, 1], outputRange: [0.4, 0.14, 0] }),
        transform: [{ scale: v.interpolate({ inputRange: [0, 1], outputRange: [1, 2.5] }) }],
      }}
    />
  );
}

type Card = Awaited<ReturnType<typeof fetchBookingCard>>;

export default function Radar() {
  // The booking comes from the draft (home hero / request, which sets it right after the hold), or from a `bid` param so a push
  // notification or deep link can land here directly. The param wins when present.
  const { bid: bidParam } = useLocalSearchParams<{ bid?: string }>();
  const bookingId = (typeof bidParam === 'string' && bidParam) || draft.bookingId;
  const insets = useSafeAreaInsets();

  const [card, setCard] = useState<Card | null>(null);
  const [cardErr, setCardErr] = useState(false);
  const [avail, setAvail] = useState<LiveRunner[] | null>(null);
  // 문장을 그대로 쥔다 (불리언 아님). fetchAvailableRunnersFor는 서버 토큰을 **행동 지시**로
  // 옮겨 준다 — not_owner → '세션이 만료된 것 같아요 — 다시 로그인해주세요'. 그걸 버리고
  // '확인 실패 — 30초 내 재시도'로 뭉개면 세션 만료가 일시 오류처럼 보이고, 절대 성공할 수 없는
  // 자동 재시도를 약속하게 된다.
  const [availErr, setAvailErr] = useState<string | null>(null);
  const [rawStatus, setRawStatus] = useState<string | null>(null);
  // 상태 폴링의 실패도 상태다 — 예전엔 catch {} 하나뿐이라 계속 실패하는 폴링이 헤더를
  // 영원히 '러너 찾는 중'으로 붙잡아 두면서 아무 말도 하지 않았다. 폴링은 계속 돈다.
  const [pollErr, setPollErr] = useState(false);
  const [runnerName, setRunnerName] = useState<string | null>(null);
  const [nominatedId, setNominatedId] = useState<string | null>(null);
  const [nominating, setNominating] = useState<string | null>(null);
  const [matchedName, setMatchedName] = useState<string | null>(null);
  const [cancelling, setCancelling] = useState(false);
  const matchedRef = useRef(false);
  // 마지막 낙관적 지명 시각 — 그보다 **먼저 출발한** 폴링 응답이 뒤늦게 도착해 배지를 되돌리는
  // 것을 막는다 (in-flight 응답은 그 지명을 아직 못 본 상태다).
  const nominatedAt = useRef(0);

  // 부킹 없이 진입하면 홈으로 (딥링크/백스택 잔재 방어)
  useEffect(() => {
    if (!bookingId) router.replace('/owner/home');
  }, [bookingId]);

  // 알림 줄의 실필드 — 한 번만 읽는다 (날짜·시각·km·강아지는 대기 중에 바뀌지 않는다).
  // runnerId는 재진입 시 '지명됨' 행을 서버 진실로 복원하기 위한 것 — 이름 매칭 금지.
  const loadCard = useCallback(() => {
    if (!bookingId) return;
    fetchBookingCard(bookingId)
      .then((c) => {
        setCard(c); setCardErr(false);
        if (c.runnerId) setNominatedId((prev) => prev ?? c.runnerId);
      })
      .catch(() => setCardErr(true));
  }, [bookingId]);
  useEffect(loadCard, [loadCard]);

  // 지명 가능한 러너 = 이 예약에 실제로 갈 수 있는 사람들 (0055 RPC — 수락 게이트의 거울).
  // [honesty 2026-08-11] 실패 시 '확인 중…'으로 영원히 굳던 것 — 실패는 실패로 말한다
  // (30초 자동 재시도는 유지, 직전 실값은 유지).
  const loadAvail = useCallback(() => {
    if (!bookingId) return;
    fetchAvailableRunnersFor(bookingId)
      .then((a) => { setAvail(a); setAvailErr(null); })
      .catch((e) => setAvailErr((e as Error)?.message ?? '러너 목록을 불러오지 못했어요'));
  }, [bookingId]);
  useEffect(() => {
    if (!bookingId) return;
    loadAvail();
    const t = setInterval(loadAvail, 30_000);
    return () => clearInterval(t);
  }, [bookingId, loadAvail]);

  // 수락 감지 — realtime 구독 + 10초 폴링 (벨트+서스펜더)
  useEffect(() => {
    if (!bookingId) return;
    let nav: ReturnType<typeof setTimeout> | null = null; // 1.8초 지연 이동 — 언마운트 시 취소
    const check = async () => {
      if (matchedRef.current) return;
      const startedAt = Date.now(); // 이 요청보다 **나중에** 일어난 낙관적 지명은 덮지 않는다
      try {
        const b = await fetchBookingBrief(bookingId);
        setPollErr(false);
        setRawStatus(b.status);
        setRunnerName(b.runnerName);
        // 지명 배지는 **서버의 runner_id**를 따라간다. 낙관적 로컬 값만 쓰던 때는 러너가 거절해
        // 서버가 runner_id를 NULL로 되돌려도 그 행이 '지명됨'인 채 굳어, 하필 그 러너만 다시
        // 지명할 수 없었다 (review P1-9).
        if (nominatedAt.current < startedAt) setNominatedId(b.runnerId);
        if (['confirmed', 'runner_enroute', 'picked_up', 'active'].includes(b.status)) {
          matchedRef.current = true;
          haptic('success');
          setMatchedName(b.runnerName ?? '러너');
          nav = setTimeout(() => router.replace('/owner/schedule'), 1800);
        } else if (b.status.startsWith('cancelled')) {
          matchedRef.current = true;
          router.replace('/owner/home');
        } else if (b.status === 'expired') {
          // 종점. 0017의 만료 크론이 scheduled_at을 지난 미매칭 예약을 matching|runner_pending →
          // expired로 넘긴다 — 바로 이 화면이 앉아 있는 상태다. 분기가 없던 동안 헤더는 링을
          // 돌리며 '러너 찾는 중'이라 말했고, 화면의 유일한 CTA(요청 취소)는 전이 맵에 없는
          // 경로라 'invalid booking transition: expired -> cancelled_owner'를 날것으로 뱉었다.
          matchedRef.current = true;
          Alert.alert('시간이 지났어요', '예약 시간까지 러너를 찾지 못해 요청이 만료됐어요 — 새로 예약해주세요');
          router.replace('/owner/schedule');
        } else if (TERMINAL_ON_RADAR[b.status]) {
          // Same shape as the `expired` arm above, for the three statuses that were never given
          // one. Without these the screen sits on a spinning ring saying 러너 찾는 중 forever —
          // `refund_pending` in particular does NOT match `startsWith('cancelled')` even though it
          // is a legal successor of `cancelled_owner` — and its only CTA (요청 취소) points at a
          // transition the server will refuse, which is exactly the dead-button-on-a-lie the
          // expired arm was added to kill. Every arm lands on schedule, whose badge vocabulary
          // (불발 · 확인 중) continues the sentence the alert starts.
          matchedRef.current = true;
          const t = TERMINAL_ON_RADAR[b.status];
          Alert.alert(t.title, t.body);
          router.replace('/owner/schedule');
        }
      } catch {
        // 일시 네트워크 오류 — 다음 틱에 재시도. 조용히 삼키지는 않는다: 계속 실패하면
        // 헤더가 '러너 찾는 중'이라고 우기게 되므로 그 사실을 한 줄로 말한다.
        setPollErr(true);
      }
    };
    check();
    const unsub = subscribeBooking(bookingId, check);
    const poll = setInterval(check, 10_000);
    return () => { unsub(); clearInterval(poll); if (nav) clearTimeout(nav); };
  }, [bookingId]);

  const nominate = async (r: LiveRunner) => {
    if (!bookingId || nominating) return;
    setNominating(r.profileId);
    try {
      await requestRunner(bookingId, r.profileId);
      haptic('light');
      // 화면에 남는다 — 상태는 realtime/폴링이 runner_pending으로 끌어올린다.
      nominatedAt.current = Date.now();
      setNominatedId(r.profileId);
    } catch (e) {
      // 서버 문장 그대로 (409 "러너 변경은 확정 전에만 가능해요" 등) — 일반화 금지
      Alert.alert('지명 실패', (e as Error).message);
    } finally {
      setNominating(null);
    }
  };

  const cancel = () => {
    if (!bookingId) return;
    Alert.alert('요청 취소', '러너 찾기를 취소할까요?', [
      { text: '계속 찾기', style: 'cancel' },
      {
        text: '취소하기', style: 'destructive',
        onPress: async () => {
          setCancelling(true);
          try {
            const r = await cancelBooking(bookingId);
            draft.bookingId = null;
            // [post-pay 2026-08-13] 러너를 찾는 동안에는 결제된 금액이 없다 — 환불이 아니라
            // 청구 여부만 말한다 (0066 래더에서 미매칭 취소는 수수료 0).
            Alert.alert('취소 완료', r.cancel_fee > 0
              ? `취소 수수료 ${r.cancel_fee.toLocaleString()}원이 청구돼요`
              : '청구되는 금액은 없어요');
            router.replace('/owner/home');
          } catch (e) {
            Alert.alert('취소 실패', (e as Error).message);
          } finally {
            setCancelling(false);
          }
        },
      },
    ]);
  };

  const directed = rawStatus === 'runner_pending';
  const dogName = card?.dogName ?? null;

  const title = matchedName ? `${matchedName} 러너 확정`
    : directed && runnerName ? `${runnerName} 러너 응답 대기`
      : '러너 찾는 중';

  // 알림 줄 굵은 줄 — 실제로 가진 필드만. 없으면 그 조각은 없다 (자리표시자 금지).
  const alertMain = [
    [card?.dateLabel, card?.timeLabel].filter(Boolean).join(' '),
    card?.km != null ? `${card.km}km` : '',
    dogName ?? '',
  ].filter(Boolean).join(' · ');

  // 얇은 줄 — 상태를 모르는 동안엔 아무 말도 하지 않는다 (모르는 상태 위에 문장을 얹지 않는다).
  const alertSub = matchedName ? '일정 화면으로 이동할게요'
    : directed ? '지명 요청을 보냈어요'
      : rawStatus === 'matching' ? '가까운 러너에게 요청을 보냈어요'
        : null;

  const dockPadBottom = insets.bottom + 12;
  const dockH = 12 + 54 + dockPadBottom;
  // contentContainerStyle을 인라인 객체로 두면 매 렌더마다 새 참조 — ScrollView가 통째로 다시 잰다
  // (request.tsx의 `pageStyle` useMemo와 같은 관용구. 줄 번호로 쓰지 않는다 — 종전의 `:581`은
  //  이미 다른 코드를 가리키고 있었다).
  const scrollPad = useMemo(
    () => ({ paddingHorizontal: layout.gutter, paddingBottom: dockH + 20 }),
    [dockH],
  );

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      {/* ── 고정 헤더 ── */}
      <View style={[s.topBar, { paddingTop: insets.top + 8 }]}>
        <View style={s.topRow}>
          <Pressable onPress={() => router.replace('/owner/home')} hitSlop={10} style={s.back}
            accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 22, lineHeight: 26, color: paper.ink }}>‹</Text>
          </Pressable>
          <Text style={s.topTitle} numberOfLines={1}>{title}</Text>
          <View style={{ width: 32 }} />
        </View>
      </View>

      <ScrollView contentContainerStyle={scrollPad}>
        {/* ── 알림 줄 ── */}
        {cardErr ? (
          <View style={s.alertRow}>
            <View style={[s.dot, { backgroundColor: paper.critical }]} />
            <View style={{ flex: 1 }}>
              <Text style={[s.alertMain, { color: paper.critical }]}>예약 정보를 불러오지 못했어요</Text>
            </View>
            <Pressable onPress={loadCard} hitSlop={8} accessibilityRole="button">
              <Text style={[s.alertAct, { color: paper.critical }]}>다시 시도</Text>
            </Pressable>
          </View>
        ) : (alertMain !== '' || alertSub) ? (
          <View style={s.alertRow}>
            <View style={[s.dot, { backgroundColor: matchedName ? paper.ready : lilac.accent }]} />
            <View style={{ flex: 1 }}>
              {alertMain !== '' && <Text style={s.alertMain}>{alertMain}</Text>}
              {alertSub && <Text style={s.alertSub}>{alertSub}</Text>}
            </View>
          </View>
        ) : null}

        {/* 상태 폴링이 실패 중 — 헤더의 '러너 찾는 중'은 마지막으로 확인된 사실이지 지금 사실이
            아니다. 조용한 한 줄로 그것만 말한다 (폴링은 10초마다 계속 돈다 — 실제로 계속 돈다는
            사실만 약속한다). */}
        {pollErr && !matchedName && (
          <Text style={[s.state, { color: paper.critical, paddingVertical: 6 }]}>
            예약 상태를 확인하지 못했어요 — 계속 확인하고 있어요
          </Text>
        )}

        {/* ── 레이더 — 링 모션은 원본 그대로, 중앙은 강아지 이니셜 ── */}
        <View style={s.radar}>
          {!matchedName && (
            <>
              <Ripple delay={0} />
              <Ripple delay={1050} />
              <Ripple delay={2100} />
            </>
          )}
          <View style={s.core}>
            {/* 글리프 예외 — 모노그램 한 글자. 이름이 없으면 아무것도 안 쓴다. */}
            {dogName ? <Text style={s.coreChar}>{dogName[0]}</Text> : null}
          </View>
        </View>

        {!matchedName && (
          <Text style={s.quiet}>러너가 응답하면 알림으로 와요 · 앱을 닫아도 돼요</Text>
        )}

        {/* ── 지명 목록 — 상시 CTA (10분 앰버 넛지를 대체한다) ── */}
        {!matchedName && (
          <View style={{ marginTop: 20 }}>
            <Text style={s.kick}>바로 지명할 수도 있어요</Text>

            {/* 실패는 **서버가 준 문장 그대로**. '30초 내 재시도'라는 약속은 없앴다: 세션 만료
                (not_owner)에서는 자동 재시도가 절대 성공할 수 없어 지어낸 위로가 된다.
                대신 진짜 동작하는 버튼 하나를 준다. 30초 인터벌은 조용히 계속 돈다. */}
            {availErr && (
              <View style={s.availFail}>
                <Text style={s.availFailTxt}>{availErr}</Text>
                <Pressable onPress={loadAvail} hitSlop={8} accessibilityRole="button" accessibilityLabel="러너 목록 다시 불러오기">
                  <Text style={s.availFailRetry}>다시 시도</Text>
                </Pressable>
              </View>
            )}
            {avail == null && !availErr && <Text style={s.state}>확인 중…</Text>}
            {avail != null && avail.length === 0 && !availErr && (
              <Text style={s.state}>지금 지명할 수 있는 러너가 없어요 — 응답을 기다려요</Text>
            )}

            {(avail ?? []).map((r) => {
              const isNominated = r.profileId === nominatedId;
              const busy = nominating === r.profileId;
              return (
                // 행 자체는 Pressable이 아니다. 예전에는 `accessible` Pressable 안에 지명
                // Pressable이 중첩돼 있어서 iOS가 행 전체를 **한 개의** a11y 요소로 합쳤고,
                // VoiceOver로는 이 화면의 새 주요 동작(지명)에 도달할 수 없었다. 이제 프로필로
                // 가는 본문과 지명 버튼이 나란한 두 요소다.
                <View key={r.profileId} style={s.row}>
                  <Pressable
                    onPress={() => router.push(`/runner-profile/${r.profileId}`)}
                    style={({ pressed }) => [s.rowBody, pressed && { backgroundColor: paper.wash }]}
                    accessibilityRole="button"
                    accessibilityLabel={`${r.name} 러너 프로필`}
                  >
                    <Avatar url={r.avatarUrl} char={r.name[0]} bg={paper.ink} size={38} />
                    <View style={{ flex: 1, marginLeft: 11 }}>
                      <Text style={s.rowName}>{r.name}</Text>
                      <Text style={s.rowSub}>{[r.tier, r.district].filter(Boolean).join(' · ')}</Text>
                    </View>
                  </Pressable>
                  {isNominated ? (
                    <Text style={[s.rowAct, { color: paper.dim }]}>지명됨</Text>
                  ) : (
                    <Pressable
                      onPress={() => nominate(r)} hitSlop={10} disabled={busy}
                      style={s.rowActBtn}
                      accessibilityRole="button" accessibilityLabel={`${r.name} 러너 지명`}
                      accessibilityState={{ disabled: busy, busy }}
                    >
                      <Text style={[s.rowAct, { color: busy ? paper.dim : paper.action }]}>
                        {busy ? '지명 중...' : '지명 ›'}
                      </Text>
                    </Pressable>
                  )}
                </View>
              );
            })}
          </View>
        )}
      </ScrollView>

      {/* ── 고정 CTA 도크 — 고스트 취소 ── */}
      {!matchedName && (
        <View style={[s.ctaDock, { paddingBottom: dockPadBottom }]}>
          <PaperBtn label="요청 취소" busyLabel="취소 중..." busy={cancelling} variant="quiet" onPress={cancel} />
        </View>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  // ── 고정 헤더 — 랩 §C의 `.top`. paddingTop은 JSX가 세이프에어리어로 주입한다 ──
  topBar: { backgroundColor: paper.canvas, paddingHorizontal: layout.gutter, paddingBottom: 10 },
  topRow: { flexDirection: 'row', alignItems: 'center', gap: 8, minHeight: 32 },
  back: { width: 32, height: 32, alignItems: 'flex-start', justifyContent: 'center' },
  topTitle: { flex: 1, fontSize: 16.5, fontWeight: '800', color: paper.ink, textAlign: 'center' },
  // ── 알림 줄 — home-hero의 문법 그대로 (점 · 굵은 줄 · 얇은 줄 · 우측 행동) ──
  alertRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 12, minHeight: 44 },
  dot: { width: 8, height: 8, borderRadius: 4 },
  alertMain: { fontSize: 14, fontWeight: '800', color: paper.ink, lineHeight: 19 },
  alertSub: { fontSize: 14, color: paper.dim, marginTop: 1, lineHeight: 19 },
  alertAct: { fontSize: 14, fontWeight: '800' },
  // ── 레이더 — 링이 스케일 2.5까지 자란다 (130 → 325). 컨테이너는 잘라내지 않는다 ──
  radar: { alignItems: 'center', justifyContent: 'center', marginTop: 10, height: 200 },
  core: {
    width: 64, height: 64, borderRadius: 32, backgroundColor: paper.action,
    alignItems: 'center', justifyContent: 'center',
  },
  coreChar: { fontSize: 20, fontWeight: '800', color: '#FFFFFF', lineHeight: 26 },
  quiet: { fontSize: 14, color: paper.dim, textAlign: 'center', marginTop: 12, lineHeight: 20 },
  // 키커 — 랩은 라틴 캡스지만 한글엔 레터스페이스 캡스가 없다. 14pt 플로어를 지킨다.
  kick: { fontSize: 14, fontWeight: '800', color: paper.dim, marginBottom: 4 },
  state: { fontSize: 14, color: paper.dim, paddingVertical: 12, lineHeight: 20 },
  row: {
    flexDirection: 'row', alignItems: 'center', paddingVertical: 10,
    borderBottomWidth: 1, borderBottomColor: '#EEEEEE', minHeight: 58,
  },
  // 본문(프로필로 가는 문)과 지명 버튼은 형제다 — 중첩하면 iOS가 하나로 합친다 (a11y 수정).
  rowBody: { flex: 1, flexDirection: 'row', alignItems: 'center', paddingVertical: 4, minHeight: 44 },
  rowName: { fontSize: 14, fontWeight: '800', color: paper.ink, lineHeight: 19 },
  rowSub: { fontSize: 14, color: paper.dim, marginTop: 1, lineHeight: 19 },
  rowAct: { fontSize: 14, fontWeight: '800' },
  rowActBtn: { minHeight: 44, justifyContent: 'center', paddingLeft: 12 },
  // 지명 목록 로드 실패 — 홈의 fitFail과 같은 라우드 페일 문법 (14/700 critical · 텍스트 재시도)
  availFail: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 9,
    borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    paddingVertical: 11, marginTop: 4,
  },
  availFailTxt: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.critical, flex: 1 },
  availFailRetry: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  // ── 고정 CTA 도크 — bottom: 0까지 불투명한 캔버스 면 + 코랄 헤어라인 1px ──
  ctaDock: {
    position: 'absolute', left: 0, right: 0, bottom: 0,
    backgroundColor: paper.canvas, borderTopWidth: 1, borderTopColor: paper.line,
    paddingTop: 12, paddingHorizontal: layout.gutter,
  },
});
