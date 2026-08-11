import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../src/components/ui';
import {
  AvailRule, checkSlot, fetchRescheduleInfo, fetchRunnerAvailability,
  requestReschedule, RescheduleInfo, withdrawReschedule,
} from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { haptic } from '../../src/lib/haptics';
import { colors, paper } from '../../src/theme';

// 일정 변경 = 제안 (reschedule-as-proposal, 0016)
// 확정 예약은 계약 — 여기서 고른 새 시간은 '요청'일 뿐, 러너가 수락해야 실제로 바뀐다.
// 슬롯은 이 예약의 러너 가용시간에 바인딩 (러너 프로필 그리드와 동일 검증: is_slot_available).
// 원래 시작 2시간 전까지 응답이 없으면 자동 만료 — 기존 시간이 확정.

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
const DAY = ['일', '월', '화', '수', '목', '금', '토'];
const fmtMin = (m: number) => {
  const h = Math.floor(m / 60);
  return `${h < 12 ? '오전' : '오후'} ${h % 12 === 0 ? 12 : h % 12}시${m % 60 ? ` ${m % 60}분` : ''}`;
};
const fmtIso = (iso: string) => {
  const d = new Date(iso);
  return `${d.getMonth() + 1}.${d.getDate()} (${DAY[d.getDay()]}) ${fmtMin(d.getHours() * 60 + d.getMinutes())}`;
};

export default function Reschedule() {
  const df = useDisplayFont();
  const { bid } = useLocalSearchParams<{ bid: string }>();
  const [info, setInfo] = useState<RescheduleInfo | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [rules, setRules] = useState<AvailRule[]>([]);
  const [dayIdx, setDayIdx] = useState(0);
  // null = 확인 중 · 'error' = check failed (availability UNKNOWN — never painted 가능)
  const [slotOk, setSlotOk] = useState<Record<string, boolean | null | 'error'>>({});
  const [picked, setPicked] = useState<{ label: string; start: Date } | null>(null);
  const [busy, setBusy] = useState(false);

  const load = () => {
    if (!bid) { setErr('예약 정보가 없어요'); return; }
    fetchRescheduleInfo(bid)
      .then((i) => {
        setInfo(i);
        if (i.runnerId) fetchRunnerAvailability(i.runnerId).then(setRules).catch(() => setRules([]));
      })
      .catch((e) => setErr(e?.message ?? '불러오기 실패'));
  };
  useEffect(load, [bid]);

  const days = useMemo(() => Array.from({ length: 7 }, (_, i) => {
    const d = new Date(Date.now() + i * 86400_000);
    return { date: d, label: i === 0 ? '오늘' : i === 1 ? '내일' : undefined, d: d.getDate(), w: DAY[d.getDay()] };
  }), []);

  const daySlots = useMemo(() => {
    const day = days[dayIdx];
    const wd = day.date.getDay();
    const out: { key: string; label: string; start: Date }[] = [];
    const minStart = Date.now() + 2 * 3600_000; // 최소 2시간 통보 (예약 규칙과 동일)
    rules.filter((r) => r.weekday === wd).forEach((r) => {
      for (let m = r.startMin; m + 60 <= r.endMin; m += 60) {
        const start = new Date(day.date.getFullYear(), day.date.getMonth(), day.date.getDate(), Math.floor(m / 60), m % 60);
        if (start.getTime() < minStart) continue;
        out.push({ key: start.toISOString(), label: fmtMin(m), start });
      }
    });
    return out;
  }, [rules, dayIdx, days]);

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
      const end = new Date(sl.start.getTime() + 60 * 60_000);
      checkSlot(info.runnerId!, sl.start.toISOString(), end.toISOString())
        .then((ok) => { if (alive) setSlotOk((m) => ({ ...m, [sl.key]: ok })); })
        .catch(() => { if (alive) setSlotOk((m) => ({ ...m, [sl.key]: 'error' })); });
    });
    return () => { alive = false; };
  }, [info, daySlots]);

  // single-slot recheck — the retry path for a failed availability check
  const recheckSlot = (sl: { key: string; start: Date }) => {
    if (!info?.runnerId) return;
    setSlotOk((m) => ({ ...m, [sl.key]: null }));
    const end = new Date(sl.start.getTime() + 60 * 60_000);
    checkSlot(info.runnerId, sl.start.toISOString(), end.toISOString())
      .then((ok) => setSlotOk((m) => ({ ...m, [sl.key]: ok })))
      .catch(() => setSlotOk((m) => ({ ...m, [sl.key]: 'error' })));
  };

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

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingTop: 56, paddingHorizontal: 16, paddingBottom: 140 }}>
        <Row style={{ gap: 12 }}>
          <Pressable onPress={() => router.back()} style={s.circleBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
          <Text style={[{ fontSize: 27.5, fontWeight: '900', color: paper.ink }, df]}>일정 변경</Text>
        </Row>

        {err && (
          <View style={s.notice}><Text style={s.noticeText}>{err}</Text></View>
        )}

        {info && info.status !== 'confirmed' && (
          <View style={s.notice}>
            <Text style={s.noticeText}>
              {info.status === 'pending' || info.status === 'matching'
                ? '아직 러너 매칭 전이에요 — 러너가 확정되면\n그 러너의 가능 시간에서 변경할 수 있어요'
                : '진행 중이거나 종료된 예약은 변경할 수 없어요'}
            </Text>
            <Pressable onPress={() => router.back()} style={s.noticeBtn}>
              <Text style={{ fontSize: 14.5, fontWeight: '800', color: paper.ink }}>돌아가기</Text>
            </Pressable>
          </View>
        )}

        {info && info.status === 'confirmed' && (
          <>
            {/* 현재 계약 — 무엇을 바꾸려는지부터 명확히 */}
            <View style={s.current}>
              <Text style={{ fontSize: 14.5, fontWeight: '800', color: '#b8c4ae', letterSpacing: 1 }}>현재 확정 일정</Text>
              <Text style={{ fontSize: 21, fontWeight: '900', color: '#fff', marginTop: 5 }}>
                {info.dateLabel} {info.timeLabel}
              </Text>
              <Text style={{ fontSize: 15.5, color: '#b8c4ae', marginTop: 4 }}>
                {info.dogName} · {info.km}km · {info.runnerName ?? '러너'} 러너
              </Text>
            </View>

            {/* 대기 중 제안 — 있으면 상태 + 철회 */}
            {info.proposedIso && (
              <View style={s.pendingBanner}>
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 14, fontWeight: '900', color: '#9D580A' }}>
                    변경 요청 대기 중 → {fmtIso(info.proposedIso)}
                  </Text>
                  <Text style={{ fontSize: 14, color: '#9D580A', marginTop: 2 }}>
                    러너 수락 전까지 기존 시간 유지 · 새로 고르면 요청이 교체돼요
                  </Text>
                </View>
                <Pressable onPress={withdraw} style={s.withdrawBtn}>
                  <Text style={{ fontSize: 14, fontWeight: '800', color: '#9D580A' }}>철회</Text>
                </Pressable>
              </View>
            )}

            {/* 날짜 스트립 */}
            <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: 18 }} contentContainerStyle={{ gap: 8 }}>
              {days.map((d, i) => (
                <Pressable key={i} onPress={() => { setDayIdx(i); setPicked(null); }} style={[s.dayChip, dayIdx === i && s.dayChipOn]}>
                  <Text style={{ fontSize: 14, fontWeight: '700', color: dayIdx === i ? '#b8c4ae' : colors.dim }}>{d.label ?? d.w}</Text>
                  <Text style={{ fontSize: 17, fontWeight: '900', color: dayIdx === i ? '#fff' : paper.ink, marginTop: 2 }}>{d.d}</Text>
                </Pressable>
              ))}
            </ScrollView>

            {/* 슬롯 그리드 — 이 러너의 실가용 시간만 */}
            {daySlots.length === 0 ? (
              <View style={s.notice}>
                <Text style={s.noticeText}>이 날은 {info.runnerName ?? '러너'} 러너의 가능 시간이 없어요</Text>
              </View>
            ) : (
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
                      style={[s.slot, isPicked && s.slotPicked, ok === false && s.slotOff, isCur && s.slotCur]}
                    >
                      <Text style={{
                        fontSize: 14, fontWeight: '800',
                        color: isPicked ? '#fff' : ok === false ? '#b7b4a5' : paper.ink,
                      }}>
                        {sl.label}
                      </Text>
                      <Text style={{ fontSize: 14, fontWeight: '700', marginTop: 2, color: isPicked ? '#b8c4ae' : isCur ? colors.voltDeep : ok === false ? '#b7b4a5' : ok === 'error' ? paper.critical : '#82887a' }}>
                        {isCur ? '현재' : ok === null ? '확인 중' : ok === 'error' ? '확인 실패 · 재시도' : ok === false ? '마감' : '가능'}
                      </Text>
                    </Pressable>
                  );
                })}
              </View>
            )}
          </>
        )}
      </ScrollView>

      {/* 확정 바 — 계약 원칙을 카피로 명시 */}
      {info?.status === 'confirmed' && picked && (
        <View style={s.confirmBar}>
          <Text style={{ fontSize: 14, fontWeight: '800', color: '#fff' }} numberOfLines={1}>
            {fmtIso(picked.start.toISOString())}로 변경 요청
          </Text>
          <Pressable onPress={send} disabled={busy} style={[s.confirmBtn, busy && { opacity: 0.5 }]}>
            <Text style={[{ fontSize: 15.5, fontWeight: '900', color: paper.ink }, df]}>
              {busy ? '보내는 중...' : '러너에게 변경 요청 ➤'}
            </Text>
          </Pressable>
          <Text style={{ fontSize: 14, color: '#b8c4ae', textAlign: 'center', marginTop: 8 }}>
            러너가 수락해야 일정이 바뀌어요 · 원래 시간 2시간 전까지 응답 없으면 자동 만료
          </Text>
        </View>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  circleBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  current: {
    backgroundColor: paper.ink, borderRadius: 20, padding: 18, marginTop: 16,
    borderWidth: 1.5, borderColor: 'rgba(198,245,66,0.4)',
  },
  pendingBanner: {
    flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: '#FDE8D0',
    borderRadius: 16, padding: 14, marginTop: 10,
  },
  withdrawBtn: { borderWidth: 1.5, borderColor: '#F59A43', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 13 },
  dayChip: { width: 54, alignItems: 'center', backgroundColor: '#fff', borderRadius: 14, paddingVertical: 10, borderWidth: 1, borderColor: '#DCD6C4' },
  dayChipOn: { backgroundColor: paper.ink, borderColor: paper.ink },
  slot: { width: '31%', backgroundColor: '#fff', borderRadius: 13, borderWidth: 1, borderColor: '#DCD6C4', alignItems: 'center', paddingVertical: 11 },
  slotPicked: { backgroundColor: paper.ink, borderColor: paper.ink },
  slotOff: { backgroundColor: '#f0eee5', borderColor: '#e5e2d4' },
  slotCur: { borderColor: colors.voltDeep, borderWidth: 1.6, backgroundColor: '#F3F8E2' },
  notice: {
    backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: '#DCD6C4',
    padding: 18, marginTop: 16, alignItems: 'center',
  },
  noticeText: { fontSize: 14.5, color: colors.dim, textAlign: 'center', lineHeight: 22 },
  noticeBtn: { marginTop: 12, backgroundColor: colors.volt, borderRadius: 12, paddingVertical: 10, paddingHorizontal: 18 },
  confirmBar: {
    position: 'absolute', left: 11, right: 11, bottom: 26, backgroundColor: paper.ink,
    borderRadius: 20, padding: 14, borderWidth: 1.5, borderColor: 'rgba(198,245,66,0.5)',
    shadowColor: '#0F1D13', shadowOpacity: 0.3, shadowRadius: 10, shadowOffset: { width: 0, height: 5 },
  },
  confirmBtn: { backgroundColor: colors.volt, borderRadius: 13, alignItems: 'center', paddingVertical: 13, marginTop: 10 },
});
