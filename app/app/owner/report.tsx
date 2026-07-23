import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../src/components/ui';
import { fetchRunReport, RunReport } from '../../src/lib/api';
import { colors } from '../../src/theme';

// 러닝 리포트 — 알림 '리포트 준비됨' 탭 도착지. 완료 전 예약이면 상태 안내로 대체.
// GPS 트랙·사진은 실좌표 세션 후 추가.

const FOREST = '#132117';

const REASON: Record<string, { label: string; color: string; bg: string; note?: string }> = {
  completed: { label: '완주 완료', color: '#3d5a2b', bg: '#e3f0c4' },
  dog_condition: {
    label: '반려견 컨디션으로 조기 종료', color: '#d84a2f', bg: '#fde8e3',
    note: '러너 판단으로 안전하게 종료했어요. 아이 상태를 확인해주시고, 이상이 있으면 안심 센터로 연락주세요.',
  },
  owner_request: { label: '보호자 요청으로 종료', color: '#a97c12', bg: '#fbf0d4' },
  runner_personal: { label: '러너 사정으로 종료', color: '#75806f', bg: '#e9ebe2' },
};

const STATUS_LABEL: Record<string, string> = {
  matching: '러너 매칭 중', runner_pending: '러너 응답 대기', confirmed: '러너 확정 — 러닝 전',
  runner_enroute: '러너 이동 중', picked_up: '인계 완료 — 시작 대기', active: '러닝 진행 중',
};

const fmtDur = (sec: number) => `${Math.floor(sec / 60)}분 ${sec % 60}초`;
const fmtPace = (sec: number | null) => (sec ? `${Math.floor(sec / 60)}'${String(sec % 60).padStart(2, '0')}" /km` : '—');

export default function Report() {
  const { bid } = useLocalSearchParams<{ bid: string }>();
  const [report, setReport] = useState<RunReport | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (!bid) { setErr('예약 정보가 없어요'); return; }
    fetchRunReport(bid).then(setReport).catch((e) => setErr(e?.message ?? '불러오기 실패'));
  }, [bid]);

  const reason = report?.run?.endReason ? REASON[report.run.endReason] : null;

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 40 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
          <Text style={{ fontSize: 20, fontWeight: '900', color: FOREST }}>러닝 리포트</Text>
          <View style={{ width: 40 }} />
        </Row>

        {err && (
          <View style={s.emptyBox}><Text style={s.emptyText}>{err}</Text></View>
        )}
        {!err && !report && (
          <View style={s.emptyBox}><Text style={s.emptyText}>불러오는 중...</Text></View>
        )}

        {report && !report.run && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>
              {STATUS_LABEL[report.status] ?? '진행 상황 확인 중'}
            </Text>
            <Text style={[s.emptyText, { marginTop: 6 }]}>
              러닝이 끝나면 여기서 리포트를 볼 수 있어요
            </Text>
            <Pressable onPress={() => router.replace('/owner/schedule')} style={s.ctaGhost}>
              <Text style={{ fontSize: 12.5, fontWeight: '800', color: FOREST }}>내 일정에서 보기 ›</Text>
            </Pressable>
          </View>
        )}

        {report && report.run && (
          <>
            {/* summary hero */}
            <View style={s.hero}>
              <Text style={{ fontSize: 12, color: '#b8c4ae' }}>{report.when} · {report.routeName}</Text>
              <Text style={{ fontSize: 24, fontWeight: '900', color: '#fff', marginTop: 6 }}>
                {report.dogName}의 러닝
              </Text>
              <Row style={{ marginTop: 16, justifyContent: 'space-around' }}>
                <HeroStat value={`${report.run.actualKm}`} unit="km" label={`계획 ${report.plannedKm}km`} />
                <View style={s.heroDiv} />
                <HeroStat value={fmtDur(report.run.durationSec).split(' ')[0]} unit={fmtDur(report.run.durationSec).split(' ')[1] ?? ''} label="러닝 시간" />
                <View style={s.heroDiv} />
                <HeroStat value={fmtPace(report.run.paceSecPerKm).split(' ')[0]} unit="" label="평균 페이스" />
              </Row>
            </View>

            {/* end reason */}
            {reason && (
              <View style={[s.card, { borderColor: reason.color + '44' }]}>
                <View style={[s.reasonPill, { backgroundColor: reason.bg }]}>
                  <Text style={{ fontSize: 11.5, fontWeight: '900', color: reason.color }}>{reason.label}</Text>
                </View>
                {report.run.conditionNote && (
                  <Text style={{ fontSize: 12.5, color: '#5d655d', marginTop: 10, lineHeight: 18 }}>
                    러너 메모: {report.run.conditionNote}
                  </Text>
                )}
                {reason.note && (
                  <Text style={{ fontSize: 11.5, color: reason.color, marginTop: 8, lineHeight: 17 }}>{reason.note}</Text>
                )}
              </View>
            )}

            {/* payment */}
            <View style={s.card}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 13, fontWeight: '800', color: FOREST }}>결제 금액</Text>
                <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST }}>{report.price.toLocaleString()}원</Text>
              </Row>
              <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 5 }}>
                {report.paceLabel} · 조기 종료 시 정산 조정은 고객센터를 통해 처리돼요
              </Text>
            </View>

            <Text style={{ fontSize: 10.5, color: colors.dim, textAlign: 'center', marginTop: 14, lineHeight: 15 }}>
              GPS 트랙과 러닝 사진은 곧 리포트에 추가돼요
            </Text>

            <Pressable onPress={() => router.replace('/owner/home')} style={s.cta}>
              <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST }}>홈으로</Text>
            </Pressable>
          </>
        )}
      </ScrollView>
    </View>
  );
}

function HeroStat({ value, unit, label }: { value: string; unit: string; label: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: 22, fontWeight: '900', color: colors.volt }}>
        {value}<Text style={{ fontSize: 12 }}> {unit}</Text>
      </Text>
      <Text style={{ fontSize: 10.5, color: '#b8c4ae', marginTop: 3 }}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  hero: { backgroundColor: FOREST, borderRadius: 22, padding: 18, marginTop: 18 },
  heroDiv: { width: 1, backgroundColor: '#2c4034' },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#eceadf', marginTop: 12 },
  reasonPill: { borderRadius: 99, paddingVertical: 6, paddingHorizontal: 12, alignSelf: 'flex-start' },
  emptyBox: { marginTop: 24, backgroundColor: '#f4f2ea', borderRadius: 18, padding: 26, alignItems: 'center' },
  emptyText: { fontSize: 13, color: colors.dim, textAlign: 'center', lineHeight: 19 },
  ctaGhost: { marginTop: 14, backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 10, paddingHorizontal: 18 },
  cta: { marginTop: 16, backgroundColor: colors.volt, borderRadius: 16, alignItems: 'center', paddingVertical: 14 },
});
