import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { Monogram, Row } from '../../src/components/ui';
import { fetchRunReport, RunReport } from '../../src/lib/api';
import { colors } from '../../src/theme';

// 러닝 리포트 — 개별 러닝의 실기록 페이지. 알림·내 일정 '러닝 기록 보기'의 도착지.
// 목표 달성률(거리·페이스), 러너·코스, 메디컬/러너 노트, 하이라이트 사진(실좌표 세션 후 실물).
// 콜렉터블 카드(/cards)와 별개 — 이건 기록의 진실, 카드는 도파민.

const FOREST = '#132117';
const FOREST_INNER = '#1d3023';

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

const fmtDur = (sec: number) => `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;
const fmtPace = (sec: number | null) => (sec ? `${Math.floor(sec / 60)}'${String(sec % 60).padStart(2, '0')}"` : '—');
// 페이스 목표: 라벨에서 분/km 추출 ("빠른 6'" → 360s)
const targetPaceSec = (label: string) => (label.includes('8') ? 480 : label.includes('6') ? 360 : 420);

export default function Report() {
  const { bid } = useLocalSearchParams<{ bid: string }>();
  const [report, setReport] = useState<RunReport | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (!bid) { setErr('예약 정보가 없어요'); return; }
    fetchRunReport(bid).then(setReport).catch((e) => setErr(e?.message ?? '불러오기 실패'));
  }, [bid]);

  const run = report?.run ?? null;
  const reason = run?.endReason ? REASON[run.endReason] : null;
  // 목표 달성률
  const kmPct = run && report ? Math.min(100, Math.round((run.actualKm / report.plannedKm) * 100)) : 0;
  const pacePct = run?.paceSecPerKm && report
    ? Math.min(100, Math.round((targetPaceSec(report.paceLabel) / run.paceSecPerKm) * 100))
    : null;

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 40 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
          <Text style={{ fontSize: 20, fontWeight: '900', color: FOREST }}>러닝 리포트</Text>
          <View style={{ width: 40 }} />
        </Row>

        {err && <View style={s.emptyBox}><Text style={s.emptyText}>{err}</Text></View>}
        {!err && !report && <View style={s.emptyBox}><Text style={s.emptyText}>불러오는 중...</Text></View>}

        {report && !run && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>
              {STATUS_LABEL[report.status] ?? '진행 상황 확인 중'}
            </Text>
            <Text style={[s.emptyText, { marginTop: 6 }]}>러닝이 끝나면 여기서 기록을 볼 수 있어요</Text>
            <Pressable onPress={() => router.replace('/owner/schedule')} style={s.ctaGhost}>
              <Text style={{ fontSize: 12.5, fontWeight: '800', color: FOREST }}>내 일정에서 보기 ›</Text>
            </Pressable>
          </View>
        )}

        {report && run && (
          <>
            {/* ---------- hero: 핵심 지표 ---------- */}
            <View style={s.hero}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 12, color: '#b8c4ae' }}>{report.when}</Text>
                {reason && (
                  <View style={[s.heroReason, { backgroundColor: reason.bg }]}>
                    <Text style={{ fontSize: 9.5, fontWeight: '900', color: reason.color }}>{reason.label}</Text>
                  </View>
                )}
              </Row>
              <Text style={{ fontSize: 24, fontWeight: '900', color: '#fff', marginTop: 6 }}>
                {report.dogName}의 러닝
              </Text>
              <Text style={{ fontSize: 40, fontWeight: '900', color: colors.tang, marginTop: 10 }}>
                {run.actualKm}<Text style={{ fontSize: 18, color: '#b8c4ae' }}> km</Text>
              </Text>
              <Row style={{ marginTop: 14, backgroundColor: FOREST_INNER, borderRadius: 14, paddingVertical: 12, justifyContent: 'space-around' }}>
                <HeroStat value={fmtDur(run.durationSec)} label="러닝 시간" />
                <View style={s.heroDiv} />
                <HeroStat value={`${fmtPace(run.paceSecPerKm)}`} label="평균 페이스 /km" />
                <View style={s.heroDiv} />
                <HeroStat value={`${report.plannedKm}km`} label="계획 거리" />
              </Row>
            </View>

            {/* ---------- 목표 달성 ---------- */}
            <View style={s.card}>
              <Text style={s.cardTitle}>목표 달성</Text>
              <GoalBar label="거리" pct={kmPct} detail={`${run.actualKm} / ${report.plannedKm}km`} />
              {pacePct != null && (
                <GoalBar label="페이스" pct={pacePct} detail={`목표 ${fmtPace(targetPaceSec(report.paceLabel))} · 실제 ${fmtPace(run.paceSecPerKm)}`} />
              )}
            </View>

            {/* ---------- 러너 & 코스 ---------- */}
            <View style={s.card}>
              <Row style={{ gap: 12 }}>
                <Monogram char={(report.runnerName ?? '러')[0]} bg="#5a7a3c" size={44} />
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 14.5, fontWeight: '900', color: FOREST }}>
                    {report.runnerName ?? '러너'} 러너
                  </Text>
                  <Text style={{ fontSize: 11.5, color: colors.dim, marginTop: 2 }}>
                    {report.routeName}{report.routeArea ? ` · ${report.routeArea}` : ''}
                  </Text>
                </View>
                <View style={s.certPill}><Text style={{ fontSize: 9.5, fontWeight: '800', color: '#4a6d1f' }}>신원인증</Text></View>
              </Row>
            </View>

            {/* ---------- 메디컬 / 러너 노트 ---------- */}
            {(run.conditionNote || reason?.note) && (
              <View style={[s.card, reason && { borderColor: reason.color + '44' }]}>
                <Text style={s.cardTitle}>러너 노트</Text>
                {run.conditionNote && (
                  <Text style={{ fontSize: 12.5, color: '#5d655d', lineHeight: 18 }}>{run.conditionNote}</Text>
                )}
                {reason?.note && (
                  <Text style={{ fontSize: 11.5, color: reason.color, marginTop: run.conditionNote ? 8 : 0, lineHeight: 17 }}>
                    {reason.note}
                  </Text>
                )}
              </View>
            )}

            {/* ---------- 하이라이트 ---------- */}
            <View style={s.card}>
              <Text style={s.cardTitle}>하이라이트</Text>
              {run.photos.length === 0 ? (
                <Row style={{ gap: 8 }}>
                  {[0, 1, 2].map((i) => (
                    <View key={i} style={s.photoSlot}><Text style={{ fontSize: 16, color: '#c9ccc0' }}>▣</Text></View>
                  ))}
                </Row>
              ) : (
                <Text style={{ fontSize: 12, color: colors.dim }}>{run.photos.length}장의 사진</Text>
              )}
              <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 8 }}>
                러닝 사진과 GPS 트랙은 곧 리포트에 추가돼요
              </Text>
            </View>

            {/* ---------- 결제 ---------- */}
            <View style={s.card}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 13, fontWeight: '800', color: FOREST }}>결제 금액</Text>
                <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST }}>{report.price.toLocaleString()}원</Text>
              </Row>
              <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 5 }}>
                조기 종료 시 정산 조정은 고객센터를 통해 처리돼요
              </Text>
            </View>

            <Pressable onPress={() => router.replace('/owner/home')} style={s.cta}>
              <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST }}>홈으로</Text>
            </Pressable>
          </>
        )}
      </ScrollView>
    </View>
  );
}

function HeroStat({ value, label }: { value: string; label: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: 16, fontWeight: '900', color: '#fff' }}>{value}</Text>
      <Text style={{ fontSize: 10, color: '#b8c4ae', marginTop: 3 }}>{label}</Text>
    </View>
  );
}

function GoalBar({ label, pct, detail }: { label: string; pct: number; detail: string }) {
  return (
    <View style={{ marginTop: 10 }}>
      <Row style={{ justifyContent: 'space-between' }}>
        <Text style={{ fontSize: 12, fontWeight: '700', color: '#3d453d' }}>{label}</Text>
        <Text style={{ fontSize: 13, fontWeight: '900', color: pct >= 100 ? '#5a7a3c' : FOREST }}>{pct}%</Text>
      </Row>
      <View style={s.barTrack}>
        <View style={[s.barFill, { width: `${pct}%` }, pct >= 100 && { backgroundColor: '#82b016' }]} />
      </View>
      <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 4 }}>{detail}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  hero: { backgroundColor: FOREST, borderRadius: 22, padding: 18, marginTop: 18 },
  heroReason: { borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9 },
  heroDiv: { width: 1, backgroundColor: '#2c4034' },
  card: { backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#eceadf', marginTop: 12 },
  cardTitle: { fontSize: 13.5, fontWeight: '900', color: FOREST, marginBottom: 6 },
  barTrack: { height: 8, borderRadius: 99, backgroundColor: '#f0eee3', marginTop: 6, overflow: 'hidden' },
  barFill: { height: 8, borderRadius: 99, backgroundColor: colors.volt },
  certPill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9, alignSelf: 'center' },
  photoSlot: { flex: 1, height: 74, borderRadius: 12, backgroundColor: '#f4f2ea', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf', borderStyle: 'dashed' },
  emptyBox: { marginTop: 24, backgroundColor: '#f4f2ea', borderRadius: 18, padding: 26, alignItems: 'center' },
  emptyText: { fontSize: 13, color: colors.dim, textAlign: 'center', lineHeight: 19 },
  ctaGhost: { marginTop: 14, backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 10, paddingHorizontal: 18 },
  cta: { marginTop: 16, backgroundColor: colors.volt, borderRadius: 16, alignItems: 'center', paddingVertical: 14 },
});
