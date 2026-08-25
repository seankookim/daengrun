import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { PaperBtn } from '../../src/components/paper-btn';
import { Row } from '../../src/components/ui';
import {
  AvailRule, checkSlot, fetchRescheduleInfo, fetchRunnerAvailability, NOT_FOUND,
  requestReschedule, RescheduleInfo, withdrawReschedule,
} from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { haptic } from '../../src/lib/haptics';
import { goBackOrHome } from '../../src/lib/nav';
import { paper } from '../../src/theme';
import { kstCal, kstInstant } from '../../src/lib/kst';
import { expectedDurationMs } from '../../src/lib/lateness';

// 일정 변경 = 제안 (reschedule-as-proposal, 0016)
// 확정 예약은 계약 — 여기서 고른 새 시간은 '요청'일 뿐, 러너가 수락해야 실제로 바뀐다.
// 슬롯은 이 예약의 러너 가용시간에 바인딩 (러너 프로필 그리드와 동일 검증: is_slot_available).
// 원래 시작 2시간 전까지 응답이 없으면 자동 만료 — 기존 시간이 확정.
//
// [2026-08-24 · Sean "I like the new schedule change screens" — enh-owner-booking-lab S①S②S③]
//   S① 페이퍼 리페인트. 이 화면은 이 흐름에서 마지막 V4 레거시 섬이었다: cream 캔버스,
//     #D8DAD2 보더, radius 20/16/13, 그리고 **은퇴한 팔레트의 볼트 그린이 돈 걸린 커밋 버튼**.
//     기계적으로 깨끗한 이관이었다 — 앰버 배너의 잉크 #9D580A는 이미 paper.paceSlowInk와 같은
//     값이고, 면 #FDE8D0은 paper.paceSlowWash에서 한 칸이다. 계약 카드는 **다크로 남는다**
//     ("dark is the artifact, light is the screen") — 코너만 날카로워지고 볼트 알파 보더를 버린다.
//   S② 요일 점. rules는 이미 통째로 메모리에 있는데(한 번의 fetch) 날짜 스트립이 그걸
//     하나도 말하지 않아, 보호자가 "이 러너는 수요일에 안 뛴다"를 알아내려면 7일을 눌러봐야 했다.
//     ⚠ 점은 **규칙이 있는 요일**만 뜻한다 — 충돌·2시간 하한·이 예약의 소요시간은 칸마다
//     is_slot_available이 따로 판정한다. 그래서 표식은 점이고 범례는 '운영 요일'이다.
//     rules가 null('확인 중')이나 'error'면 점을 **하나도** 찍지 않는다 — 없는 점이 '쉬는 날'로
//     읽히면 안 된다.
//   S③ 확인 중·확인 실패 요약 한 줄. 아홉 칸짜리 하루는 「확인 실패 · 재시도」를 아홉 번
//     따로 눌러야 했다. 칸별 진실은 그대로 두고, 위에 요약 + 전체 다시 확인(오늘 고른 날의
//     칸만 — recheckSlot 루프)을 놓는다. 모든 칸이 답을 받으면 줄은 사라진다: 가구가 아니라 상태다.
// 코랄 가로선은 헤더와 도크 둘뿐이다 (Sean: "too many horizontal red lines"). 칸·칩·행의
// 구분선은 뉴트럴 #EEEEEE — 코랄 풀블리드는 섹션의 문법이다 (request.tsx:1465).

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
const DAY = ['일', '월', '화', '수', '목', '금', '토'];
// 잉크 면 위의 보조 텍스트 — owner/home.tsx:596·fitness.tsx:515가 쓰는 같은 문법(흰색 알파).
// 새 헥스가 아니라 '흰 잉크의 약한 단계'다.
const ON_INK_SOFT = 'rgba(255,255,255,0.82)';
const fmtMin = (m: number) => {
  const h = Math.floor(m / 60);
  return `${h < 12 ? '오전' : '오후'} ${h % 12 === 0 ? 12 : h % 12}시${m % 60 ? ` ${m % 60}분` : ''}`;
};
// [E6] 슬롯 시각은 기기 로컬이 아니라 **KST 벽시계**로 짓는다 — 서버 가용 규칙과 홀드 검증이
// KST 고정이라, 로컬로 지으면 UTC 시뮬레이터·해외 기기에서 화면이 07:30을 보여주고 16:30 KST를
// 저장한다. 산술은 src/lib/kst.ts 한 곳에 있다 (세 입구가 복제하던 것을 모았다 — 그 복제가
// E6 를 처음 고칠 때 셋 중 둘만 고치게 만든 원인이다). 테스트: app/test/run-kst-tests.sh

const fmtIso = (iso: string) => {
  const c = kstCal(Date.parse(iso));
  return `${c.m + 1}.${c.d} (${DAY[c.wd]}) ${fmtMin(c.h * 60 + c.min)}`;
};

export default function Reschedule() {
  const df = useDisplayFont();
  const insets = useSafeAreaInsets();
  const { bid } = useLocalSearchParams<{ bid: string }>();
  const [info, setInfo] = useState<RescheduleInfo | null>(null);
  const [err, setErr] = useState<string | null>(null);
  // null = loading · 'error' = load failed — the same three-state idiom slotOk already uses (:46).
  // [honesty 2026-08-20] This was `AvailRule[]` seeded with `[]`, filled by
  // `.catch(() => setRules([]))`. A transient availability failure — and the whole loading
  // window — therefore rendered as 「이 날은 {runner} 러너의 가능 시간이 없어요」 on every day
  // in the strip (:256). An owner reading that concludes the runner cannot take the new time
  // and cancels a CONFIRMED booking instead of moving it, which is the 10% fee tier
  // (`cancelBooking`, src/lib/api.ts:1124). An empty grid must mean the server said empty.
  const [rules, setRules] = useState<AvailRule[] | null | 'error'>(null);
  const [dayIdx, setDayIdx] = useState(0);
  // null = 확인 중 · 'error' = check failed (availability UNKNOWN — never painted 가능)
  const [slotOk, setSlotOk] = useState<Record<string, boolean | null | 'error'>>({});
  const [picked, setPicked] = useState<{ label: string; start: Date } | null>(null);
  const [busy, setBusy] = useState(false);

  // Availability load, split out because it is the only thing the retry button re-runs.
  const loadRules = (runnerId: string) => {
    setRules(null);
    fetchRunnerAvailability(runnerId).then(setRules).catch(() => setRules('error'));
  };

  const load = () => {
    if (!bid) { setErr('예약 정보가 없어요'); return; }
    fetchRescheduleInfo(bid)
      .then((i) => {
        setInfo(i);
        // A confirmed booking always carries a runner. If one is somehow missing there is no
        // availability to read at all — say that instead of spinning on a fetch we never fire.
        if (i.runnerId) loadRules(i.runnerId); else setRules('error');
      })
      // Never render `e.message`: PostgREST's English reached this screen verbatim. Not-found and
      // failure are different states — only the second one can be retried.
      .catch((e) => setErr(e?.message === NOT_FOUND
        ? '이 예약을 찾을 수 없어요'
        : '예약 정보를 불러오지 못했어요'));
  };
  useEffect(load, [bid]);

  const days = useMemo(() => Array.from({ length: 7 }, (_, i) => {
    const cal = kstCal(Date.now() + i * 86400_000);
    return { cal, label: i === 0 ? '오늘' : i === 1 ? '내일' : undefined, d: cal.d, w: DAY[cal.wd] };
  }), []);

  // [S② 2026-08-24] 러너가 **규칙을 가진 요일** — 이미 로드된 배열에서 파생, 새 fetch 0.
  // rules가 배열이 아닐 때(확인 중·실패)는 빈 Set이고, 렌더는 그 경우 점 자체를 그리지 않는다.
  const ruleWeekdays = useMemo(
    () => new Set((Array.isArray(rules) ? rules : []).map((r) => r.weekday)),
    [rules],
  );
  const dotsReady = Array.isArray(rules) && rules.length > 0;

  // [지속시간 드리프트] 이 화면은 슬롯을 60분으로 검증했는데, 수락 시 서버(transition-booking)는
  // km×8+25분으로 본다 — owner/request.tsx의 slotAllowed가 쓰는 것과 같은 식이다. 10km 예약이면
  // 서버는 105분을 요구하므로, 60분만 맞는 칸이 UI에선 '가능'이었다가 러너가 수락할 때 거절됐다.
  // 화면이 서버가 거절할 칸을 내주는 건 이 파일이 이미 금지한 '거짓 준비'(honesty P1)와 같은 것.
  const durMin = expectedDurationMs(info?.km ?? 5) / 60_000; // 한 벌: src/lib/lateness.ts
  const daySlots = useMemo(() => {
    const day = days[dayIdx];
    const wd = day.cal.wd; // KST 요일 — rules.weekday가 KST 고정이다
    const out: { key: string; label: string; start: Date }[] = [];
    const minStart = Date.now() + 2 * 3600_000; // 최소 2시간 통보 (예약 규칙과 동일)
    // Loading ('null') and failure ('error') produce no slots, but they are NOT an empty
    // availability — the render below tells those three apart before it draws anything.
    (Array.isArray(rules) ? rules : []).filter((r) => r.weekday === wd).forEach((r) => {
      // 시작 칸은 60분 간격이되(그리드 눈금), 규칙 창 안에 **실소요**가 들어가야 칸이 산다.
      for (let m = r.startMin; m + durMin <= r.endMin; m += 60) {
        const start = kstInstant(day.cal, Math.floor(m / 60), m % 60);
        if (start.getTime() < minStart) continue;
        out.push({ key: start.toISOString(), label: fmtMin(m), start });
      }
    });
    return out;
  }, [rules, dayIdx, days, durMin]);

  // 슬롯별 서버 검증 — 러너 프로필 그리드와 동일 (규칙 + 예약 충돌 + 휴식 버퍼)
  // [honesty P1 2026-08-11] a failed check used to paint the slot 가능 — a booking
  // against fabricated availability is a real-world no-show. Failure now renders
  // as 확인 실패 (unknown), tappable only to retry the check.
  useEffect(() => {
    if (!info?.runnerId || daySlots.length === 0) return;
    let alive = true;
    setSlotOk((prev) => {
      const next = { ...prev };
      daySlots.forEach((sl) => { if (!(sl.key in next)) next[sl.key] = null; });
      return next;
    });
    daySlots.forEach((sl) => {
      const end = new Date(sl.start.getTime() + durMin * 60_000);
      checkSlot(info.runnerId!, sl.start.toISOString(), end.toISOString())
        .then((ok) => { if (alive) setSlotOk((m) => ({ ...m, [sl.key]: ok })); })
        .catch(() => { if (alive) setSlotOk((m) => ({ ...m, [sl.key]: 'error' })); });
    });
    return () => { alive = false; };
  }, [info, daySlots, durMin]);

  // single-slot recheck — the retry path for a failed availability check
  const recheckSlot = (sl: { key: string; start: Date }) => {
    if (!info?.runnerId) return;
    setSlotOk((m) => ({ ...m, [sl.key]: null }));
    const end = new Date(sl.start.getTime() + durMin * 60_000);
    checkSlot(info.runnerId, sl.start.toISOString(), end.toISOString())
      .then((ok) => setSlotOk((m) => ({ ...m, [sl.key]: ok })))
      .catch(() => setSlotOk((m) => ({ ...m, [sl.key]: 'error' })));
  };

  // [S③] 오늘 고른 날의 칸만 센다 — 요약은 눈앞의 그리드에 대한 말이어야 한다.
  const verify = useMemo(() => {
    let checking = 0; let failed = 0;
    daySlots.forEach((sl) => {
      const ok = slotOk[sl.key];
      if (ok === 'error') failed += 1;
      else if (ok === null || ok === undefined) checking += 1;
    });
    return { checking, failed };
  }, [daySlots, slotOk]);
  // 가드레일: 한 번에 N개의 RPC가 나간다 — 그래서 **오늘 화면의 실패한 칸만** 다시 던진다
  // (effect가 이미 하는 것과 같은 범위). 라벨은 잠그지 않고 상태 줄이 스스로 '확인 중'으로 바뀐다.
  const recheckAllFailed = () => daySlots.filter((sl) => slotOk[sl.key] === 'error').forEach(recheckSlot);

  const send = async () => {
    if (!info || !picked || busy) return;
    setBusy(true);
    haptic('medium');
    try {
      await requestReschedule(info.bookingId, picked.start.toISOString());
      Alert.alert(
        '변경 요청을 보냈어요',
        `${info.runnerName ?? '러너'}님이 수락하면 일정이 바뀌어요.\n수락 전까지는 기존 시간이 유지돼요.`,
        [{ text: '확인', onPress: () => router.back() }],
      );
    } catch (e) {
      Alert.alert('요청 실패', (e as Error).message); // 정직: 실패는 실패
    } finally {
      setBusy(false);
    }
  };

  const withdraw = async () => {
    if (!info || busy) return;
    setBusy(true);
    try {
      await withdrawReschedule(info.bookingId);
      setPicked(null);
      load();
    } catch (e) {
      Alert.alert('철회 실패', (e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const curSlotIso = info ? new Date(info.scheduledAtIso).toISOString() : null;

  // [honesty 2026-08-20] The pre-match arm read `info.status === 'pending' || 'matching'`.
  // `pending` is DISPLAY vocabulary: fetchRescheduleInfo hands back `bookings.status` raw
  // (src/lib/api.ts:1147) and only STATUS_MAP (api.ts:732-735) flattens payment_hold ·
  // matching · runner_pending into that one badge word. No row can hold it, so the comparison
  // was dead and `runner_pending` — nominated runner, no answer yet — fell to the else and got
  // 「진행 중이거나 종료된 예약은 변경할 수 없어요」, false in both halves. The outcome (no
  // reschedule until a runner is confirmed) was always right; only the sentence lied. Gate on
  // the raw status, and name which of the two waits the owner is actually in.
  const preMatch = info?.status === 'matching' || info?.status === 'runner_pending';
  const preMatchLine = info?.status === 'runner_pending'
    ? '지명한 러너의 수락을 기다리는 중이에요'
    : '아직 러너 매칭 전이에요';
  const dockOpen = info?.status === 'confirmed' && !!picked;

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      {/* ── 고정 헤더 + 코랄 풀블리드 룰 ① (이 화면의 코랄 가로선은 여기와 도크 둘뿐) ── */}
      <View style={s.head}>
        <Row style={{ gap: 12 }}>
          <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
          </Pressable>
          <Text style={[{ fontSize: 24, fontWeight: '900', color: paper.ink }, df]}>일정 변경</Text>
        </Row>
      </View>
      <View style={s.rule} />

      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: 15, paddingTop: 14, paddingBottom: dockOpen ? 220 : 40 }}
      >
        {err && (
          <View style={{ paddingTop: 8 }}>
            <Text style={s.noticeText}>{err}</Text>
            {/* 막다른 상태에도 문은 있다 — 이 화면에서 나가는 유일한 길 (goBackOrHome) */}
            <View style={{ marginTop: 12 }}>
              <PaperBtn label="돌아가기" variant="secondary" onPress={goBackOrHome} />
            </View>
          </View>
        )}

        {info && info.status !== 'confirmed' && (
          <View style={{ paddingTop: 8 }}>
            <Text style={s.noticeText}>
              {preMatch
                ? `${preMatchLine} — 러너가 확정되면\n그 러너의 가능 시간에서 변경할 수 있어요`
                : '진행 중이거나 종료된 예약은 변경할 수 없어요'}
            </Text>
            {/* Dead-end notice: this is the only exit from the state, so it takes goBackOrHome
                (src/lib/nav.ts). The Alert '확인' above keeps a bare back() — that one is the
                result of a successful request, where popping is the intended effect. */}
            <View style={{ marginTop: 12 }}>
              <PaperBtn label="돌아가기" variant="secondary" onPress={goBackOrHome} />
            </View>
          </View>
        )}

        {info && info.status === 'confirmed' && (
          <>
            {/* 현재 계약 — 무엇을 바꾸려는지부터 명확히. 다크는 아티팩트다(§DESIGN) — 코너만 날카롭게 */}
            <View style={s.current}>
              <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '800', color: ON_INK_SOFT, letterSpacing: 1 }}>현재 확정 일정</Text>
              <Text style={{ fontSize: 21, lineHeight: 28, fontWeight: '900', color: '#FFFFFF', marginTop: 6 }}>
                {info.dateLabel} {info.timeLabel}
              </Text>
              <Text style={{ fontSize: 15, lineHeight: 21, color: ON_INK_SOFT, marginTop: 4 }}>
                {info.dogName} · {info.km}km · {info.runnerName ?? '러너'} 러너
              </Text>
            </View>

            {/* 대기 중 제안 — 있으면 상태 + 철회. 앰버는 시맨틱(대기)이라 생존, 크롬만 토큰으로 */}
            {info.proposedIso && (
              <View style={s.pendingBanner}>
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 14, lineHeight: 19, fontWeight: '900', color: paper.paceSlowInk }}>
                    변경 요청 대기 중 → {fmtIso(info.proposedIso)}
                  </Text>
                  <Text style={{ fontSize: 14, lineHeight: 19, color: paper.paceSlowInk, marginTop: 2 }}>
                    러너 수락 전까지 기존 시간 유지 · 새로 고르면 요청이 교체돼요
                  </Text>
                </View>
                <Pressable onPress={withdraw} style={s.withdrawBtn} accessibilityRole="button" accessibilityLabel="변경 요청 철회">
                  <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.paceSlowInk }}>철회</Text>
                </Pressable>
              </View>
            )}

            {/* [S②] 날짜 스트립 + 운영 요일 범례 */}
            <Row style={{ justifyContent: 'space-between', alignItems: 'baseline', marginTop: 18 }}>
              <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.ink }}>언제로 옮길까요</Text>
              {dotsReady && (
                <Text style={{ fontSize: 14, lineHeight: 18, color: paper.dim }}>● {info.runnerName ?? '러너'} 러너 운영 요일</Text>
              )}
            </Row>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 10 }} contentContainerStyle={{ gap: 8 }}>
              {days.map((d, i) => {
                const on = dayIdx === i;
                return (
                  <Pressable
                    key={i}
                    onPress={() => { setDayIdx(i); setPicked(null); }}
                    style={[s.dayChip, on && s.dayChipOn]}
                    accessibilityRole="button"
                    accessibilityState={{ selected: on }}
                    accessibilityLabel={`${d.label ?? `${d.w}요일`} ${d.d}일${dotsReady ? (ruleWeekdays.has(d.cal.wd) ? ' · 러너 운영 요일' : '') : ''}`}
                  >
                    <Text style={{ fontSize: 14, lineHeight: 18, fontWeight: '700', color: on ? ON_INK_SOFT : paper.dim }}>{d.label ?? d.w}</Text>
                    <Text style={{ fontSize: 17, lineHeight: 22, fontWeight: '900', color: on ? '#FFFFFF' : paper.ink, marginTop: 2 }}>{d.d}</Text>
                    {/* 점은 '규칙이 있는 요일'만 말한다. rules가 아직/영영 없으면 아무 점도 찍지 않는다 */}
                    <View style={{ height: 5, marginTop: 4, justifyContent: 'center' }}>
                      {dotsReady && ruleWeekdays.has(d.cal.wd) && <View style={[s.dayDot, on && { backgroundColor: '#FFFFFF' }]} />}
                    </View>
                  </Pressable>
                );
              })}
            </ScrollView>
            {dotsReady && (
              <Text style={{ fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 10 }}>
                점이 없는 날은 이 러너가 뛰지 않는 요일이에요 — 칸이 열려도 실제 가능 여부는 칸마다 확인해요
              </Text>
            )}

            {/* 슬롯 그리드 — 이 러너의 실가용 시간만 */}
            {/* Three states come before the grid because they mean three different things to
                the owner: a failed load is not an empty calendar, nor is a load still in flight. */}
            {rules === 'error' ? (
              <View style={s.failStrip}>
                <Text style={{ flex: 1, fontSize: 14, lineHeight: 19, fontWeight: '700', color: paper.critical }}>가능 시간을 불러오지 못했어요</Text>
                <Pressable
                  onPress={() => (info.runnerId ? loadRules(info.runnerId) : load())}
                  style={{ minHeight: 44, justifyContent: 'center' }}
                  accessibilityRole="button"
                  accessibilityLabel="다시 시도"
                >
                  <Text style={s.failAction}>다시 시도</Text>
                </Pressable>
              </View>
            ) : rules === null ? (
              <Text style={[s.noticeText, { marginTop: 16, textAlign: 'left' }]}>가능 시간을 불러오는 중...</Text>
            ) : daySlots.length === 0 ? (
              <Text style={[s.noticeText, { marginTop: 16, textAlign: 'left' }]}>이 날은 {info.runnerName ?? '러너'} 러너의 가능 시간이 없어요</Text>
            ) : (
              <>
                {/* [S③] 요약 한 줄 — 실패가 있으면 라우드-페일 + 전체 다시 확인, 확인 중뿐이면 조용한 상태 줄.
                    모든 칸이 답을 받으면 이 줄은 통째로 사라진다 */}
                {verify.failed > 0 ? (
                  <View style={s.failStrip}>
                    <Text style={{ flex: 1, fontSize: 14, lineHeight: 19, fontWeight: '700', color: paper.critical }}>
                      {verify.checking > 0
                        ? `${verify.checking}칸은 확인 중, ${verify.failed}칸은 확인하지 못했어요`
                        : `${verify.failed}칸을 확인하지 못했어요`}
                    </Text>
                    <Pressable
                      onPress={recheckAllFailed}
                      style={{ minHeight: 44, justifyContent: 'center' }}
                      accessibilityRole="button"
                      accessibilityLabel="확인하지 못한 칸 전체 다시 확인"
                    >
                      <Text style={s.failAction}>전체 다시 확인</Text>
                    </Pressable>
                  </View>
                ) : verify.checking > 0 ? (
                  <Text style={{ fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 16 }}>
                    {verify.checking}칸을 확인하는 중이에요 — 러너가 실제로 갈 수 있는지 서버에 물어보고 있어요
                  </Text>
                ) : null}

                <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginTop: 14 }}>
                  {daySlots.map((sl) => {
                    const ok = slotOk[sl.key];
                    const isCur = curSlotIso === sl.key;
                    const isPicked = picked?.start.toISOString() === sl.key;
                    return (
                      <Pressable
                        key={sl.key}
                        disabled={ok === false || isCur}
                        onPress={() => {
                          if (ok === 'error') { recheckSlot(sl); return; } // unknown never books — retry the check
                          if (ok !== true) return; // still verifying — a slot is pickable only once confirmed
                          haptic('light'); setPicked(sl);
                        }}
                        accessibilityRole="button"
                        accessibilityState={{ selected: isPicked, disabled: ok === false || isCur }}
                        style={[s.slot, isPicked && s.slotPicked, ok === false && s.slotOff, ok === 'error' && s.slotErr, isCur && s.slotCur]}
                      >
                        <Text style={{
                          fontSize: 14, lineHeight: 18, fontWeight: '800',
                          color: isPicked ? '#FFFFFF' : ok === false ? paper.faint : paper.ink,
                        }}>
                          {sl.label}
                        </Text>
                        <Text style={{
                          fontSize: 14, lineHeight: 18, fontWeight: '700', marginTop: 2,
                          color: isPicked ? ON_INK_SOFT
                            : isCur ? paper.ink
                            : ok === false ? paper.faint
                            : ok === 'error' ? paper.critical
                            : ok === null || ok === undefined ? paper.dim
                            : paper.readyDeep,
                        }}>
                          {isCur ? '현재' : ok === null || ok === undefined ? '확인 중' : ok === 'error' ? '확인 실패 · 재시도' : ok === false ? '마감' : '가능'}
                        </Text>
                      </Pressable>
                    );
                  })}
                </View>
                <Text style={{ fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 12 }}>
                  확인되지 않은 칸은 고를 수 없어요
                </Text>
              </>
            )}
          </>
        )}
      </ScrollView>

      {/* 확정 도크 — 계약 원칙을 카피로 명시. 코랄 풀블리드 룰 ② */}
      {dockOpen && picked && (
        <View style={[s.dock, { paddingBottom: Math.max(insets.bottom, 12) + 12 }]}>
          <Text style={{ fontSize: 14, lineHeight: 19, fontWeight: '800', color: paper.ink }} numberOfLines={1}>
            {fmtIso(picked.start.toISOString())}로 변경 요청
          </Text>
          <View style={{ marginTop: 10 }}>
            <PaperBtn label="러너에게 변경 요청 ›" busyLabel="보내는 중..." busy={busy} onPress={send} />
          </View>
          <Text style={{ fontSize: 14, lineHeight: 19, color: paper.dim, textAlign: 'center', marginTop: 8 }}>
            러너가 수락해야 일정이 바뀌어요 · 원래 시간 2시간 전까지 응답 없으면 자동 만료
          </Text>
        </View>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  head: { paddingTop: 56, paddingHorizontal: 15, paddingBottom: 12, backgroundColor: paper.canvas },
  // 40×40 스퀘어 백 버튼 — request.tsx circleBtn 문법 (이름만 서클, 실체는 스퀘어)
  backBtn: {
    width: 40, height: 40, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: paper.line,
  },
  rule: { height: 1, backgroundColor: paper.line },
  // 계약 카드 — 다크 아티팩트. 볼트 알파 보더와 radius 20 은퇴
  current: { backgroundColor: paper.ink, padding: 16 },
  // 앰버 배너 — #FDE8D0/#9D580A 하드코딩이 paceSlowWash/paceSlowInk와 같은 역할이었다 (실측 4.78:1)
  pendingBanner: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: paper.paceSlowWash, padding: 12, marginTop: 10,
  },
  withdrawBtn: {
    borderWidth: 1, borderColor: paper.paceSlowInk, paddingVertical: 9, paddingHorizontal: 12,
    minHeight: 44, justifyContent: 'center',
  },
  dayChip: {
    width: 54, alignItems: 'center', backgroundColor: paper.canvas,
    paddingVertical: 9, borderWidth: 1, borderColor: '#EEEEEE',
  },
  dayChipOn: { backgroundColor: paper.ink, borderColor: paper.ink },
  dayDot: { width: 5, height: 5, backgroundColor: paper.line },
  slot: {
    width: '31%', backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE',
    alignItems: 'center', paddingVertical: 11,
  },
  slotPicked: { backgroundColor: paper.ink, borderColor: paper.ink },
  slotOff: { backgroundColor: paper.disabledFill, borderColor: paper.disabledFill },
  slotErr: { borderColor: paper.critical },
  // '현재'는 상태다 — 잉크 테두리(액션 아님). 누를 수 없는 칸이라 면을 칠하지 않는다
  slotCur: { borderColor: paper.ink, borderWidth: 1.5 },
  noticeText: { fontSize: 14.5, lineHeight: 21, color: paper.text },
  // 라우드-페일 스트립 (F1.2) — criticalWash 면 + critical 잉크, 풀블리드
  failStrip: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: paper.criticalWash, borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    marginHorizontal: -15, paddingHorizontal: 15, paddingVertical: 11, marginTop: 16,
  },
  failAction: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  // 도크는 화면 맨 아래까지 불투명하다 — 세이프에어리어는 도크 **안쪽** 패딩으로 존중 (request.tsx 문법)
  dock: {
    position: 'absolute', left: 0, right: 0, bottom: 0, backgroundColor: paper.canvas,
    borderTopWidth: 1, borderTopColor: paper.line, paddingHorizontal: 15, paddingTop: 12,
  },
});
