import { router } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Alert, Modal, Pressable, StyleSheet, Text, View } from 'react-native';
import { Monogram, Row } from '../../src/components/ui';
import { EndReason, payoutFor, runRequests, runResult } from '../../src/store';
import { colors } from '../../src/theme';

// Runner-side live run: route progress map (placeholder), camera status,
// pinned customer chat. Real version: expo-location + react-native-maps + camera stream.

const fmt = (sec: number) =>
  `${String(Math.floor(sec / 60)).padStart(2, '0')}:${String(Math.floor(sec % 60)).padStart(2, '0')}`;
const paceStr = (sec: number, km: number) => {
  if (km < 0.05) return "-'--\"";
  const p = sec / km;
  return `${Math.floor(p / 60)}'${String(Math.round(p % 60)).padStart(2, '0')}"`;
};

export default function ActiveRun() {
  const req = runRequests[0];
  const [running, setRunning] = useState(false);
  const [sec, setSec] = useState(0);
  const [endSheet, setEndSheet] = useState(false);
  const timer = useRef<ReturnType<typeof setInterval> | null>(null);

  const km = Math.min(sec / 409, req.km + 0.02); // ~6'49" pace, demo-accelerated
  const remaining = Math.max(req.km - km, 0);
  const progress = Math.min(km / req.km, 1);

  useEffect(() => {
    if (running) {
      timer.current = setInterval(() => setSec((s) => s + 8), 100); // accelerated demo time
    }
    return () => { if (timer.current) clearInterval(timer.current); };
  }, [running]);

  // per-reason payout (docs/product-notes: all pay actual km — never incentivize pushing a hurt dog)
  const payoutByReason = (reason: EndReason): number => {
    const actual = payoutFor(km);
    if (reason === 'owner') return actual + Math.round((payoutFor(req.km) - actual) * 0.5); // + 잔여 50% 보장
    return actual; // dog / runner: actual km
  };

  const endWith = (reason: EndReason) => {
    setEndSheet(false);
    Object.assign(runResult, { km, sec, payout: payoutByReason(reason), completed: false, reason });
    if (reason === 'dog') {
      Alert.alert('컨디션 종료', '보호자에게 알림 전송됨 · 상태 사진과 메모를 남겨주세요 (목업)\n근처 동물병원: 성수동물병원 650m');
    }
    router.replace('/runner/done');
  };

  const finish = (completed: boolean) => {
    Object.assign(runResult, { km, sec, payout: payoutFor(km), completed, reason: null });
    router.replace('/runner/done');
  };

  useEffect(() => {
    if (km >= req.km) {
      setRunning(false);
      Object.assign(runResult, { km, sec, payout: payoutFor(km), completed: true });
      router.replace('/runner/done');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [km >= req.km]);

  return (
    <View style={s.root}>
      {/* 코스 맵 placeholder */}
      <View style={s.mapArea}>
        <Row style={{ justifyContent: 'space-between', paddingHorizontal: 16 }}>
          <View style={s.statusBadge}>
            <Text style={{ fontSize: 12, fontWeight: '700', color: colors.volt }}>
              {running ? `● ${req.dogName}와 러닝 중` : `${req.dogName}와 러닝 준비`}
            </Text>
          </View>
          <View style={s.camStatus}>
            <View style={[s.recDot, !running && { backgroundColor: '#8a8877' }]} />
            <Text style={s.camText}>{running ? 'REC · 보호자 시청 중' : '카메라 대기'} · 배터리 82%</Text>
          </View>
        </Row>

        <View style={s.trackWrap}>
          <Row style={{ justifyContent: 'space-between', marginBottom: 8 }}>
            <Text style={{ fontSize: 12, color: colors.dim }}>{req.place} 코스 · {req.km}km</Text>
            <Text style={{ fontSize: 12, fontWeight: '800', color: colors.ink }}>
              남은 거리 {remaining.toFixed(1)}km
            </Text>
          </Row>
          <View style={s.track}>
            <View style={[s.trackFill, { width: `${progress * 100}%` }]} />
            <View style={[s.trackDot, { left: `${Math.max(progress * 100 - 2, 0)}%` }]} />
          </View>
        </View>
      </View>

      {/* 스탯 + 컨트롤 */}
      <View style={s.panel}>
        {/* 고정된 고객 채팅 */}
        <Pressable
          style={s.chatPin}
          onPress={() => router.push('/chat')}
        >
          <Monogram char={req.dogChar} bg={req.dogColor} size={36} />
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 13, fontWeight: '700', color: colors.cream }}>{req.dogName} 보호자님</Text>
            <Text style={{ fontSize: 11, color: '#8fa093' }} numberOfLines={1}>
              "자전거도로만 피해주시면 돼요!"
            </Text>
          </View>
          <Text style={{ fontSize: 12, color: colors.volt }}>채팅 ›</Text>
        </Pressable>

        <Row style={{ justifyContent: 'space-around', marginVertical: 22 }}>
          <MiniStat value={km.toFixed(2)} label="km" big />
          <MiniStat value={fmt(sec)} label="시간" />
          <MiniStat value={paceStr(sec, km)} label="페이스" />
        </Row>

        <Row style={{ justifyContent: 'center', marginBottom: 14 }}>
          <Text style={{ fontSize: 12, color: '#8fa093' }}>
            현재 예상 수익 <Text style={{ color: colors.volt, fontWeight: '800' }}>{payoutFor(km).toLocaleString()}원</Text> · 완주 시 {payoutFor(req.km + 0.02).toLocaleString()}원
          </Text>
        </Row>

        <View style={{ flexDirection: 'row', gap: 10, alignItems: 'center' }}>
          {running && (
            <Pressable style={s.moreBtn} onPress={() => setEndSheet(true)}>
              <Text style={{ fontSize: 14, color: '#8fa093', fontWeight: '900' }}>❙❙</Text>
            </Pressable>
          )}
          <Pressable
            style={[s.btn, { backgroundColor: '#1c2b21' }]}
            onPress={() => Alert.alert('전송 완료', '사진이 보호자에게 전송되었습니다 (목업)')}
          >
            <Text style={{ fontSize: 16, fontWeight: '800', color: colors.cream }}>사진 전송</Text>
          </Pressable>
          <Pressable
            style={[s.btn, { backgroundColor: colors.volt }]}
            onPress={() => (running ? setEndSheet(true) : setRunning(true))}
          >
            <Text style={{ fontSize: 16, fontWeight: '800', color: colors.ink }}>
              {running ? '러닝 종료' : '러닝 시작'}
            </Text>
          </Pressable>
        </View>
      </View>

      {/* ---------- end-run options sheet ---------- */}
      <Modal visible={endSheet} transparent animationType="slide" onRequestClose={() => setEndSheet(false)}>
        <Pressable style={s.sheetBackdrop} onPress={() => setEndSheet(false)} />
        <View style={s.sheet}>
          <View style={s.sheetHandle} />
          <Text style={{ fontSize: 17, fontWeight: '900', color: colors.cream }}>어떤 이유로 종료하나요?</Text>
          <Text style={{ fontSize: 11.5, color: '#8fa093', marginTop: 4 }}>
            지금까지 {km.toFixed(2)}km · 이유에 따라 정산이 달라져요
          </Text>

          <EndOption
            title="강아지 컨디션"
            desc="지친 기색·이상 징후 등. 사진과 메모를 남겨요"
            pay={`${payoutByReason('dog').toLocaleString()}원 · 완주율 무영향`}
            accent="#B9F23A"
            onPress={() => endWith('dog')}
          />
          <EndOption
            title="보호자 요청"
            desc="보호자가 조기 종료를 요청했어요"
            pay={`${payoutByReason('owner').toLocaleString()}원 · 잔여 거리 50% 보장 포함`}
            accent="#9fc3e8"
            onPress={() => endWith('owner')}
          />
          <EndOption
            title="러너 개인 사유"
            desc="부상·일정 등 러너 사정으로 종료해요"
            pay={`${payoutByReason('runner').toLocaleString()}원 · 완주율에 반영`}
            accent="#e2c56b"
            onPress={() => endWith('runner')}
          />

          <Pressable style={s.sheetCancel} onPress={() => setEndSheet(false)}>
            <Text style={{ fontSize: 13, fontWeight: '700', color: '#8fa093' }}>계속 달릴게요</Text>
          </Pressable>
        </View>
      </Modal>
    </View>
  );
}

function EndOption({ title, desc, pay, accent, onPress }: { title: string; desc: string; pay: string; accent: string; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={s.endOption}>
      <View style={[s.endRail, { backgroundColor: accent }]} />
      <View style={{ flex: 1 }}>
        <Text style={{ fontSize: 14.5, fontWeight: '900', color: colors.cream }}>{title}</Text>
        <Text style={{ fontSize: 11, color: '#8fa093', marginTop: 2 }}>{desc}</Text>
        <Text style={{ fontSize: 11.5, fontWeight: '800', color: accent, marginTop: 5 }}>{pay}</Text>
      </View>
      <Text style={{ fontSize: 15, color: '#8fa093' }}>›</Text>
    </Pressable>
  );
}

function MiniStat({ value, label, big }: { value: string; label: string; big?: boolean }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: big ? 44 : 28, fontWeight: '900', color: big ? colors.volt : colors.cream }}>
        {value}
      </Text>
      <Text style={{ fontSize: 11, color: '#8fa093', marginTop: 2 }}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#e7e9dc' },
  mapArea: { flex: 1, paddingTop: 56 },
  statusBadge: { backgroundColor: colors.ink, borderRadius: 99, paddingVertical: 8, paddingHorizontal: 14 },
  camStatus: { flexDirection: 'row', alignItems: 'center', gap: 6, backgroundColor: '#fff', borderRadius: 99, paddingVertical: 8, paddingHorizontal: 12 },
  recDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: '#ff3b30' },
  camText: { fontSize: 10, fontWeight: '700', color: colors.ink },
  trackWrap: { position: 'absolute', left: 20, right: 20, bottom: 24 },
  track: { height: 10, borderRadius: 99, backgroundColor: '#d5d8c6' },
  trackFill: { height: 10, borderRadius: 99, backgroundColor: colors.tang },
  trackDot: {
    position: 'absolute', top: -4, width: 18, height: 18, borderRadius: 9,
    backgroundColor: colors.tang, borderWidth: 3, borderColor: '#fff',
  },
  panel: { backgroundColor: colors.ink, borderTopLeftRadius: 24, borderTopRightRadius: 24, padding: 20, paddingBottom: 34 },
  chatPin: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: '#1c2b21', borderRadius: 16, padding: 12,
  },
  btn: { flex: 1, borderRadius: 16, padding: 16, alignItems: 'center' },
  moreBtn: { width: 44, height: 52, borderRadius: 16, backgroundColor: '#1c2b21', alignItems: 'center', justifyContent: 'center' },
  sheetBackdrop: { flex: 1, backgroundColor: '#00000066' },
  sheet: { backgroundColor: '#10160f', borderTopLeftRadius: 26, borderTopRightRadius: 26, padding: 22, paddingBottom: 40 },
  sheetHandle: { alignSelf: 'center', width: 44, height: 5, borderRadius: 3, backgroundColor: '#2c3a2c', marginBottom: 14 },
  endOption: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: '#1a231a', borderRadius: 16, padding: 14, marginTop: 10,
  },
  endRail: { width: 4, height: 44, borderRadius: 2 },
  sheetCancel: { alignItems: 'center', paddingVertical: 14, marginTop: 6 },
});
