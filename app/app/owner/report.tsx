import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useState } from 'react';
import { Dimensions, Image, Pressable, ScrollView, Share, StyleSheet, Text, View } from 'react-native';
import { Monogram, Row } from '../../src/components/ui';
import { fetchRunReport, fetchRunStandings, RunReport, RunStandings } from '../../src/lib/api';
import { draft } from '../../src/store';
import { colors } from '../../src/theme';

// 러닝 리포트 — 러닝 하나의 '프로필 페이지'. 풀블리드 · 공유 가능 · 사진 · 개인 기록 배지.
// 진입: 알림 · 내 일정 완료 카드 · 체력 리포트 최근 러닝. 공유가 곧 마케팅 (자랑 = 전파).

const FOREST = '#132117';
const FOREST_INNER = '#1d3023';
const W = Dimensions.get('window').width;
const TILE = (W - 4) / 3;

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
const targetPaceSec = (label: string) => (label.includes('8') ? 480 : label.includes('6') ? 360 : 420);

// 개인 기록 배지 — 내 역사와의 경쟁 (동네 리더보드는 서버 집계 후)
function badges(st: RunStandings | null): string[] {
  if (!st) return [];
  const out: string[] = [`${st.nth}번째 러닝`];
  if (st.total > 1) {
    if (st.kmRank === 1) out.push('🏆 역대 최장 거리');
    else if (st.kmRank <= 3) out.push(`거리 TOP ${st.kmRank}`);
    if (st.paceRank === 1) out.push('⚡ 역대 최고 페이스');
    else if (st.paceRank != null && st.paceRank <= 3) out.push(`페이스 TOP ${st.paceRank}`);
  }
  return out;
}

export default function Report() {
  const { bid } = useLocalSearchParams<{ bid: string }>();
  const [report, setReport] = useState<RunReport | null>(null);
  const [standings, setStandings] = useState<RunStandings | null>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    if (!bid) { setErr('예약 정보가 없어요'); return; }
    fetchRunReport(bid).then(setReport).catch((e) => setErr(e?.message ?? '불러오기 실패'));
    fetchRunStandings(bid).then(setStandings).catch(() => {});
  }, [bid]);

  const run = report?.run ?? null;
  const reason = run?.endReason ? REASON[run.endReason] : null;
  const kmPct = run && report ? Math.min(100, Math.round((run.actualKm / report.plannedKm) * 100)) : 0;
  const pacePct = run?.paceSecPerKm && report
    ? Math.min(100, Math.round((targetPaceSec(report.paceLabel) / run.paceSecPerKm) * 100))
    : null;
  const bList = badges(standings);

  const share = async () => {
    if (!report || !run) return;
    const bLine = bList.filter((b) => b.includes('역대') || b.includes('TOP')).join(' · ');
    try {
      await Share.share({
        message:
          `🐕 ${report.dogName}의 ${run.actualKm}km 러닝 완주!\n` +
          `⏱ ${fmtDur(run.durationSec)} · 페이스 ${fmtPace(run.paceSecPerKm)}/km\n` +
          `📍 ${report.routeName}${report.runnerName ? ` · ${report.runnerName} 러너와 함께` : ''}` +
          (bLine ? `\n${bLine}` : '') +
          `\n\n반려견 피트니스, 댕런 🏃`,
      });
    } catch { /* 사용자 취소 */ }
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 40 }}>
        <Row style={{ justifyContent: 'space-between', paddingHorizontal: 20, paddingTop: 56 }}>
          <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
          <Text style={{ fontSize: 20, fontWeight: '900', color: FOREST }}>러닝 리포트</Text>
          {run ? (
            <Pressable onPress={share} style={s.backBtn}><Text style={{ fontSize: 15 }}>↗</Text></Pressable>
          ) : <View style={{ width: 40 }} />}
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
            {/* ---------- hero: 풀블리드 ---------- */}
            <View style={s.hero}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 12, color: '#b8c4ae' }}>{report.when} · {report.routeName}</Text>
                {reason && (
                  <View style={[s.heroReason, { backgroundColor: reason.bg }]}>
                    <Text style={{ fontSize: 9.5, fontWeight: '900', color: reason.color }}>{reason.label}</Text>
                  </View>
                )}
              </Row>
              <Text style={{ fontSize: 24, fontWeight: '900', color: '#fff', marginTop: 6 }}>
                {report.dogName}의 러닝
              </Text>
              <Text style={{ fontSize: 44, fontWeight: '900', color: colors.tang, marginTop: 8 }}>
                {run.actualKm}<Text style={{ fontSize: 18, color: '#b8c4ae' }}> km</Text>
              </Text>
              {/* 개인 기록 배지 */}
              {bList.length > 0 && (
                <Row style={{ gap: 6, marginTop: 10, flexWrap: 'wrap' }}>
                  {bList.map((b) => (
                    <View key={b} style={s.badgePill}>
                      <Text style={{ fontSize: 10, fontWeight: '900', color: FOREST }}>{b}</Text>
                    </View>
                  ))}
                </Row>
              )}
              <Row style={{ marginTop: 14, backgroundColor: FOREST_INNER, borderRadius: 14, paddingVertical: 12, justifyContent: 'space-around' }}>
                <HeroStat value={fmtDur(run.durationSec)} label="러닝 시간" />
                <View style={s.heroDiv} />
                <HeroStat value={fmtPace(run.paceSecPerKm)} label="평균 페이스 /km" />
                <View style={s.heroDiv} />
                <HeroStat value={`${report.plannedKm}km`} label="계획 거리" />
              </Row>
            </View>

            {/* ---------- 러닝 순간 스탬프 (응가 도장 등) ---------- */}
            {run.events.length > 0 && (
              <View style={[s.section, { flexDirection: 'row', gap: 8, flexWrap: 'wrap' }]}>
                {(
                  [['poop', '💩 응가'], ['snack', '🍖 간식'], ['water', '💧 물'], ['photo', '📷 사진']] as const
                ).map(([kind, label]) => {
                  const n = run.events.filter((e) => e.kind === kind).length;
                  if (n === 0) return null;
                  return (
                    <View key={kind} style={s.stampChip}>
                      <Text style={{ fontSize: 12.5, fontWeight: '900', color: '#3d5a2b' }}>{label} ×{n}</Text>
                    </View>
                  );
                })}
                <Text style={{ fontSize: 10, color: colors.dim, width: '100%', marginTop: 4 }}>
                  러너가 러닝 중 실시간으로 기록한 순간들이에요
                </Text>
              </View>
            )}

            {/* ---------- 사진: 엣지-투-엣지 ---------- */}
            {run.photos.length > 0 ? (
              <View style={{ backgroundColor: '#fff', flexDirection: 'row', flexWrap: 'wrap', gap: 2 }}>
                {run.photos.map((url) => (
                  <Image key={url} source={{ uri: url }} style={{ width: TILE, height: TILE, backgroundColor: '#e2e0d4' }} />
                ))}
              </View>
            ) : (
              <View style={[s.section, { flexDirection: 'row', gap: 2, paddingHorizontal: 0, paddingVertical: 0 }]}>
                {[0, 1, 2].map((i) => (
                  <View key={i} style={s.photoSlot}><Text style={{ fontSize: 16, color: '#c9ccc0' }}>▣</Text></View>
                ))}
              </View>
            )}
            {run.photos.length === 0 && (
              <Text style={{ fontSize: 10, color: colors.dim, textAlign: 'center', backgroundColor: '#fff', paddingBottom: 10 }}>
                러너가 남긴 사진과 바디캠 하이라이트가 여기에 담겨요
              </Text>
            )}

            {/* ---------- 목표 달성 ---------- */}
            <View style={s.section}>
              <Text style={s.sectionTitle}>목표 달성</Text>
              <GoalBar label="거리" pct={kmPct} detail={`${run.actualKm} / ${report.plannedKm}km`} />
              {pacePct != null && (
                <GoalBar label="페이스" pct={pacePct} detail={`목표 ${fmtPace(targetPaceSec(report.paceLabel))} · 실제 ${fmtPace(run.paceSecPerKm)}`} />
              )}
            </View>

            {/* ---------- 러너 & 코스 ---------- */}
            <View style={s.section}>
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

            {/* ---------- 러너 노트 ---------- */}
            {(run.conditionNote || reason?.note) && (
              <View style={s.section}>
                <Text style={s.sectionTitle}>러너 노트</Text>
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

            {/* ---------- 결제 ---------- */}
            <View style={s.section}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 13, fontWeight: '800', color: FOREST }}>결제 금액</Text>
                <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST }}>{report.price.toLocaleString()}원</Text>
              </Row>
              <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 5 }}>
                조기 종료 시 정산 조정은 고객센터를 통해 처리돼요
              </Text>
            </View>

            {/* ---------- CTA ---------- */}
            <View style={{ paddingHorizontal: 20 }}>
              <Pressable onPress={share} style={s.cta}>
                <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>↗ 자랑하기</Text>
                <Text style={{ fontSize: 10.5, color: '#5d6b4a', marginTop: 2 }}>카카오톡·인스타그램으로 오늘의 러닝을 공유해요</Text>
              </Pressable>
              {/* 재예약 = 두 번째 예약이 첫 예약보다 중요하다 — 설정 전부 프리필, 시간만 고르면 끝 */}
              <Pressable
                onPress={() => {
                  draft.km = report.plannedKm;
                  draft.pace = report.paceLabel;
                  if (report.routeId) draft.routeId = report.routeId;
                  draft.preferredRunnerId = report.runnerProfileId;
                  draft.preferredRunnerName = report.runnerName;
                  draft.scheduledAtIso = null;
                  draft.timeLabel = '시간을 선택해주세요';
                  router.push('/owner/request');
                }}
                style={[s.cta, { backgroundColor: '#fff', borderWidth: 1.5, borderColor: '#a9c47e' }]}
              >
                <Text style={{ fontSize: 14, fontWeight: '900', color: '#3d5a2b' }}>⟳ 이대로 다시 예약</Text>
                <Text style={{ fontSize: 10.5, color: colors.dim, marginTop: 2 }}>
                  같은 코스·거리{report.runnerName ? ` · ${report.runnerName} 러너 지명` : ''} — 시간만 고르면 돼요
                </Text>
              </Pressable>
              <Pressable onPress={() => router.replace('/owner/home')} style={s.ghostCta}>
                <Text style={{ fontSize: 13, fontWeight: '800', color: '#3d453d' }}>홈으로</Text>
              </Pressable>
            </View>
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
  hero: { backgroundColor: FOREST, padding: 20, marginTop: 14 },
  heroReason: { borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9 },
  heroDiv: { width: 1, backgroundColor: '#2c4034' },
  badgePill: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10 },
  section: { backgroundColor: '#fff', paddingHorizontal: 20, paddingVertical: 16, borderBottomWidth: 1, borderBottomColor: '#eceadf' },
  sectionTitle: { fontSize: 13.5, fontWeight: '900', color: FOREST, marginBottom: 6 },
  barTrack: { height: 8, borderRadius: 99, backgroundColor: '#f0eee3', marginTop: 6, overflow: 'hidden' },
  barFill: { height: 8, borderRadius: 99, backgroundColor: colors.volt },
  certPill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9, alignSelf: 'center' },
  stampChip: { backgroundColor: '#eef4e0', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 13 },
  photoSlot: { width: TILE, height: TILE * 0.6, backgroundColor: '#f4f2ea', alignItems: 'center', justifyContent: 'center' },
  emptyBox: { margin: 20, backgroundColor: '#f4f2ea', borderRadius: 18, padding: 26, alignItems: 'center' },
  emptyText: { fontSize: 13, color: colors.dim, textAlign: 'center', lineHeight: 19 },
  ctaGhost: { marginTop: 14, backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 10, paddingHorizontal: 18 },
  cta: { backgroundColor: colors.volt, borderRadius: 18, alignItems: 'center', paddingVertical: 15, marginTop: 16 },
  ghostCta: { backgroundColor: '#fff', borderRadius: 16, alignItems: 'center', paddingVertical: 13, marginTop: 8, borderWidth: 1, borderColor: '#eceadf' },
});
