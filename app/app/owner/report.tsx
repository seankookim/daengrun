import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Alert, Animated, Dimensions, Image, Pressable, ScrollView, Share, StyleSheet, Text, View } from 'react-native';
import { PatchBadge } from '../../src/components/patch';
import { HeatTrace } from '../../src/components/runcard';
import { Monogram, Row, Skeleton } from '../../src/components/ui';
import { CoursePatch, fetchPatchPop, fetchRunReport, fetchRunStandings, RunReport, RunStandings, shareRunToFeed } from '../../src/lib/api';
import { haptic } from '../../src/lib/haptics';
import { useDisplayFont } from '../../src/lib/displayFont';
import { getNaverMap, smoothTrace } from '../../src/lib/geo';
import { draft, TracePoint } from '../../src/store';
import { colors } from '../../src/theme';

// 러닝 리포트 — 러닝 하나의 '프로필 페이지'. 풀블리드 · 공유 가능 · 사진 · 개인 기록 배지.
// 진입: 알림 · 내 일정 완료 카드 · 체력 리포트 최근 러닝. 공유가 곧 마케팅 (자랑 = 전파).

const FOREST = '#0F1D13';
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

// 실트레이스 → HeatTrace 정규화 (지도 모듈 없는 빌드 폴백)
function normalizeTrace(trace: { lat: number; lng: number }[]): TracePoint[] {
  const lats = trace.map((p) => p.lat);
  const lngs = trace.map((p) => p.lng);
  const [minLa, maxLa] = [Math.min(...lats), Math.max(...lats)];
  const [minLo, maxLo] = [Math.min(...lngs), Math.max(...lngs)];
  const dLa = Math.max(maxLa - minLa, 1e-6);
  const dLo = Math.max(maxLo - minLo, 1e-6);
  return trace.map((p, i) => ({
    x: (p.lng - minLo) / dLo,
    y: 1 - (p.lat - minLa) / dLa,
    v: i / Math.max(trace.length - 1, 1),
  }));
}

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
  const df = useDisplayFont(); // 피니셔 증서 서체 — 타이틀·완주 도장 (숫자 금지)
  const { bid, shot } = useLocalSearchParams<{ bid: string; shot?: string }>();
  const [report, setReport] = useState<RunReport | null>(null);
  const [standings, setStandings] = useState<RunStandings | null>(null);
  const [err, setErr] = useState<string | null>(null);
  // 패치 획득/승급 팝 — 이 러닝이 임계를 넘긴 순간에만 1회 (수집의 획득 모먼트)
  const [patchPop, setPatchPop] = useState<CoursePatch | null>(null);
  useEffect(() => {
    if (!bid) { setErr('예약 정보가 없어요'); return; }
    fetchRunReport(bid).then(setReport).catch((e) => setErr(e?.message ?? '불러오기 실패'));
    fetchRunStandings(bid).then(setStandings).catch(() => {});
  }, [bid]);
  useEffect(() => {
    if (!bid || !report?.routeId || report.run?.endReason !== 'completed') return;
    fetchPatchPop(bid, report.routeId).then((p) => { if (p) { setPatchPop(p); haptic('success'); } }).catch(() => {});
  }, [bid, report]);

  // 인증샷은 전용 스튜디오(/shot/[bid])로 — 리포트 상단 인라인 카드 은퇴 (2026-07-28)
  const shotAuto = useRef(false);
  useEffect(() => {
    if (shot === '1' && bid && !shotAuto.current) {
      shotAuto.current = true;
      router.push(`/shot/${bid}`);
    }
  }, [shot, bid]);

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
          `\n\n반려견 피트니스, 도그스하이 🏃`,
      });
    } catch { /* 사용자 취소 */ }
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 40 }}>
        <Row style={{ justifyContent: 'space-between', paddingHorizontal: 12, paddingTop: 56 }}>
          <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
          <Text style={[{ fontSize: 23, fontWeight: '900', color: FOREST }, df]}>러닝 리포트</Text>
          {run ? (
            <Pressable onPress={share} style={s.backBtn}><Text style={{ fontSize: 17 }}>↗</Text></Pressable>
          ) : <View style={{ width: 40 }} />}
        </Row>

        {err && <View style={s.emptyBox}><Text style={s.emptyText}>{err}</Text></View>}
        {!err && !report && (
          <View style={{ paddingHorizontal: 12, marginTop: 14, gap: 12 }}>
            <Skeleton width="100%" height={210} radius={0} />
            <Skeleton width="100%" height={90} />
            <Skeleton width="70%" height={20} />
          </View>
        )}

        {report && !run && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>
              {STATUS_LABEL[report.status] ?? '진행 상황 확인 중'}
            </Text>
            <Text style={[s.emptyText, { marginTop: 6 }]}>러닝이 끝나면 여기서 기록을 볼 수 있어요</Text>
            <Pressable onPress={() => router.replace('/owner/schedule')} style={s.ctaGhost}>
              <Text style={{ fontSize: 14.5, fontWeight: '800', color: FOREST }}>내 일정에서 보기 ›</Text>
            </Pressable>
          </View>
        )}

        {report && run && (
          <>
            {/* ---------- hero: 풀블리드 + 사진 구조화 (사진이 디자인이다) ---------- */}
            <View style={[s.hero, { overflow: 'hidden' }]}>
              {run.photos[0] && (
                <Image
                  source={{ uri: run.photos[0] }}
                  style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, opacity: 0.28 }}
                  resizeMode="cover"
                />
              )}
              <Row style={{ justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 14, color: '#b8c4ae' }}>{report.when} · {report.routeName}</Text>
                {reason && run.endReason !== 'completed' && (
                  <View style={[s.heroReason, { backgroundColor: reason.bg }]}>
                    <Text style={{ fontSize: 11, fontWeight: '900', color: reason.color }}>{reason.label}</Text>
                  </View>
                )}
              </Row>
              <Text style={[{ fontSize: 27.5, fontWeight: '900', color: '#fff', marginTop: 6 }, df]}>
                {report.dogName}의 러닝
              </Text>
              {/* 완주 도장 — 피니셔 증서 (점검 도장과 같은 스탬프 언어) */}
              {run.endReason === 'completed' && (
                <View style={s.finStamp}>
                  <Text style={[{ fontSize: 15, fontWeight: '900', color: colors.volt, letterSpacing: 1 }, df]}>완주</Text>
                  <Text style={{ fontSize: 8.5, fontWeight: '900', color: colors.volt, letterSpacing: 2.5, marginTop: 1 }}>FINISHER</Text>
                </View>
              )}
              <Text style={{ fontSize: 50.5, fontWeight: '900', color: colors.tang, marginTop: 8 }}>
                {run.actualKm}<Text style={{ fontSize: 20.5, color: '#b8c4ae' }}> km</Text>
              </Text>
              {/* 개인 기록 배지 */}
              {bList.length > 0 && (
                <Row style={{ gap: 6, marginTop: 10, flexWrap: 'wrap' }}>
                  {bList.map((b) => (
                    <View key={b} style={s.badgePill}>
                      <Text style={{ fontSize: 11.5, fontWeight: '900', color: FOREST }}>{b}</Text>
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

            {/* ---------- 러닝 경로 (실트레이스) ---------- */}
            {run.trace.length > 1 && (() => {
              const maps = getNaverMap(); // 네이버 지도 (2026-07-29)
              if (maps) {
                const lats = run.trace.map((p) => p.lat);
                const lngs = run.trace.map((p) => p.lng);
                const latDelta = Math.max((Math.max(...lats) - Math.min(...lats)) * 1.4, 0.004);
                const camera = {
                  latitude: (Math.min(...lats) + Math.max(...lats)) / 2,
                  longitude: (Math.min(...lngs) + Math.max(...lngs)) / 2,
                  // 바운즈 → 네이버 줌 근사: zoom = log2(360/latΔ), 10~17 클램프
                  zoom: Math.min(17, Math.max(10, Math.log2(360 / latDelta))),
                };
                return (
                  <View style={{ height: 190, backgroundColor: '#fff' }}>
                    <maps.NaverMapView
                      style={{ flex: 1 }}
                      camera={camera}
                      isShowLocationButton={false}
                      isShowCompass={false}
                      isShowScaleBar={false}
                      isShowZoomControls={false}
                      isScrollGesturesEnabled={false}
                      isZoomGesturesEnabled={false}
                      isTiltGesturesEnabled={false}
                      isRotateGesturesEnabled={false}
                    >
                      <maps.NaverMapPathOverlay
                        coords={smoothTrace(run.trace.map((p) => ({ latitude: p.lat, longitude: p.lng })))}
                        color={colors.voltDeep}
                        width={5}
                        outlineWidth={2}
                        outlineColor="#ffffff"
                      />
                    </maps.NaverMapView>
                  </View>
                );
              }
              return (
                <View style={{ backgroundColor: '#0e150f', alignItems: 'center', paddingVertical: 12 }}>
                  <HeatTrace points={normalizeTrace(run.trace)} width={W - 60} height={140} />
                  <Text style={{ fontSize: 12.5, color: '#8fa093', marginTop: 6 }}>실제 GPS 경로 · 지도 배경은 새 빌드에서</Text>
                </View>
              );
            })()}

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
                      <Text style={{ fontSize: 14.5, fontWeight: '900', color: '#3d5a2b' }}>{label} ×{n}</Text>
                    </View>
                  );
                })}
                <Text style={{ fontSize: 13, color: colors.dim, width: '100%', marginTop: 4 }}>
                  러너가 러닝 중 실시간으로 기록한 순간들이에요
                </Text>
              </View>
            )}

            {/* ---------- 사진: 엣지-투-엣지 ---------- */}
            {run.photos.length > 0 ? (
              <View style={{ backgroundColor: '#fff', flexDirection: 'row', flexWrap: 'wrap', gap: 2 }}>
                {run.photos.map((url) => (
                  <Image key={url} source={{ uri: url }} style={{ width: TILE, height: TILE, backgroundColor: '#DCD6C4' }} />
                ))}
              </View>
            ) : (
              <View style={[s.section, { flexDirection: 'row', gap: 2, paddingHorizontal: 0, paddingVertical: 0 }]}>
                {[0, 1, 2].map((i) => (
                  <View key={i} style={s.photoSlot}><Text style={{ fontSize: 18.5, color: '#c9ccc0' }}>▣</Text></View>
                ))}
              </View>
            )}
            {run.photos.length === 0 && (
              <Text style={{ fontSize: 13, color: colors.dim, textAlign: 'center', backgroundColor: '#fff', paddingBottom: 10 }}>
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
                  <Text style={{ fontSize: 16.5, fontWeight: '900', color: FOREST }}>
                    {report.runnerName ?? '러너'} 러너
                  </Text>
                  <Text style={{ fontSize: 15, color: colors.dim, marginTop: 2 }}>
                    {report.routeName}{report.routeArea ? ` · ${report.routeArea}` : ''}
                  </Text>
                </View>
                <View style={s.certPill}><Text style={{ fontSize: 11, fontWeight: '800', color: '#4a6d1f' }}>신원인증</Text></View>
              </Row>
            </View>

            {/* ---------- 러너 노트 ---------- */}
            {(run.conditionNote || reason?.note) && (
              <View style={s.section}>
                <Text style={s.sectionTitle}>러너 노트</Text>
                {run.conditionNote && (
                  <Text style={{ fontSize: 14.5, color: '#49524a', lineHeight: 20.5 }}>{run.conditionNote}</Text>
                )}
                {reason?.note && (
                  <Text style={{ fontSize: 13, color: reason.color, marginTop: run.conditionNote ? 8 : 0, lineHeight: 19.5 }}>
                    {reason.note}
                  </Text>
                )}
              </View>
            )}

            {/* ---------- 결제 ---------- */}
            <View style={s.section}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 15, fontWeight: '800', color: FOREST }}>결제 금액</Text>
                <Text style={{ fontSize: 18.5, fontWeight: '900', color: FOREST }}>{report.price.toLocaleString()}원</Text>
              </Row>
              <Text style={{ fontSize: 14, color: colors.dim, marginTop: 5 }}>
                조기 종료 시 정산 조정은 고객센터를 통해 처리돼요
              </Text>
            </View>

            {/* ---------- CTA ---------- */}
            <View style={{ paddingHorizontal: 12 }}>
              <Pressable onPress={() => bid && router.push(`/shot/${bid}`)} style={s.cta}>
                <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>📸 인증샷 만들기</Text>
                <Text style={{ fontSize: 14, color: '#5d6b4a', marginTop: 2 }}>인스타그램용 브랜디드 카드로 자랑해요</Text>
              </Pressable>
              <Pressable
                onPress={() => {
                  if (!bid) return;
                  shareRunToFeed(bid)
                    .then(() => {
                      Alert.alert('피드에 올렸어요', '동네 이웃들이 응원할 거예요 🐕');
                      router.push('/community');
                    })
                    .catch((e) => Alert.alert('공유 실패', (e as Error).message));
                }}
                style={s.ghostCta}
              >
                <Text style={{ fontSize: 15, fontWeight: '800', color: '#3d5a2b' }}>🐕 동네 피드에 자랑하기</Text>
              </Pressable>
              <Pressable onPress={share} style={s.ghostCta}>
                <Text style={{ fontSize: 15, fontWeight: '800', color: '#3d453d' }}>↗ 텍스트로 공유</Text>
              </Pressable>
              {report.status === 'completed' && report.runnerProfileId && (
                <Pressable
                  onPress={() => router.push({ pathname: '/owner/review', params: { bid: bid!, rid: report.runnerProfileId!, rname: report.runnerName ?? '러너' } })}
                  style={s.ghostCta}
                >
                  <Text style={{ fontSize: 15, fontWeight: '800', color: '#a97c12' }}>★ {report.runnerName ?? ''} 러너 후기 남기기</Text>
                </Pressable>
              )}
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
                <Text style={{ fontSize: 16, fontWeight: '900', color: '#3d5a2b' }}>⟳ 이대로 다시 예약</Text>
                <Text style={{ fontSize: 14, color: colors.dim, marginTop: 2 }}>
                  같은 코스·거리{report.runnerName ? ` · ${report.runnerName} 러너 지명` : ''} — 시간만 고르면 돼요
                </Text>
              </Pressable>
              <Pressable onPress={() => router.replace('/owner/home')} style={s.ghostCta}>
                <Text style={{ fontSize: 15, fontWeight: '800', color: '#3d453d' }}>홈으로</Text>
              </Pressable>
            </View>
          </>
        )}
      </ScrollView>

      {/* ---------- 패치 팝 오버레이 — 획득/승급의 순간 (탭 = 닫기) ---------- */}
      {patchPop && (
        <PatchPopOverlay
          patch={patchPop}
          df={df}
          onClose={() => setPatchPop(null)}
          onWall={() => { setPatchPop(null); router.push('/cards'); }}
        />
      )}
    </View>
  );
}

const POP_TITLE: Record<string, string> = { basic: '패치 획득!', silver: '실버 승급!', gold: '골드 승급!', master: '코스 마스터!' };

function PatchPopOverlay({ patch, df, onClose, onWall }: {
  patch: CoursePatch; df: any; onClose: () => void; onWall: () => void;
}) {
  // 스프링 팝 — 수집물이 '떨어져 박히는' 모션 (1회, 화면당 펄스 예산 내)
  const a = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    Animated.spring(a, { toValue: 1, friction: 5, tension: 90, useNativeDriver: true }).start();
  }, [a]);
  return (
    <Pressable onPress={onClose} style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(10,16,10,.72)', alignItems: 'center', justifyContent: 'center', padding: 30 }}>
      <Animated.View style={{
        alignItems: 'center',
        opacity: a,
        transform: [
          { scale: a.interpolate({ inputRange: [0, 1], outputRange: [0.4, 1] }) },
          { rotate: a.interpolate({ inputRange: [0, 1], outputRange: ['-18deg', '-4deg'] }) },
        ],
      }}>
        <PatchBadge km={patch.km} name={patch.name} grade={patch.grade} size={132} />
      </Animated.View>
      <Animated.View style={{ alignItems: 'center', opacity: a, marginTop: 20 }}>
        <Text style={[{ fontSize: 26, fontWeight: '900', color: colors.volt }, df]}>{POP_TITLE[patch.grade]}</Text>
        <Text style={{ fontSize: 14.5, fontWeight: '800', color: '#dfe7d8', marginTop: 6 }}>
          {patch.name} · {patch.count === 1 ? '첫 완주' : `×${patch.count} 완주`}
        </Text>
        <Pressable onPress={onWall} style={{ backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 10, paddingHorizontal: 20, marginTop: 16 }}>
          <Text style={{ fontSize: 14, fontWeight: '900', color: FOREST }}>패치 월 보기 ›</Text>
        </Pressable>
        <Text style={{ fontSize: 13, color: '#8fa093', marginTop: 12 }}>탭하면 닫혀요</Text>
      </Animated.View>
    </Pressable>
  );
}

function HeroStat({ value, label }: { value: string; label: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: 18.5, fontWeight: '900', color: '#fff' }}>{value}</Text>
      <Text style={{ fontSize: 13, color: '#b8c4ae', marginTop: 3 }}>{label}</Text>
    </View>
  );
}

function GoalBar({ label, pct, detail }: { label: string; pct: number; detail: string }) {
  // 채워지는 모션 — 진행이 '벌어들인 것'처럼 (motion = meaning)
  const w = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    Animated.timing(w, { toValue: pct, duration: 700, useNativeDriver: false }).start();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pct]);
  return (
    <View style={{ marginTop: 10 }}>
      <Row style={{ justifyContent: 'space-between' }}>
        <Text style={{ fontSize: 14, fontWeight: '700', color: '#3d453d' }}>{label}</Text>
        <Text style={{ fontSize: 15, fontWeight: '900', color: pct >= 100 ? '#5a7a3c' : FOREST }}>{pct}%</Text>
      </Row>
      <View style={s.barTrack}>
        <Animated.View
          style={[
            s.barFill,
            { width: w.interpolate({ inputRange: [0, 100], outputRange: ['0%', '100%'] }) },
            pct >= 100 && { backgroundColor: '#7FA818' },
          ]}
        />
      </View>
      <Text style={{ fontSize: 14, color: colors.dim, marginTop: 4 }}>{detail}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  hero: { backgroundColor: FOREST, padding: 20, marginTop: 14 },
  heroReason: { borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9 },
  finStamp: {
    position: 'absolute', top: 52, right: 18, alignItems: 'center',
    borderWidth: 2.5, borderColor: colors.volt, borderRadius: 10,
    paddingVertical: 6, paddingHorizontal: 12, transform: [{ rotate: '-9deg' }], opacity: 0.92,
  },
  heroDiv: { width: 1, backgroundColor: '#2c4034' },
  badgePill: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10 },
  section: { backgroundColor: '#fff', paddingHorizontal: 12, paddingVertical: 16, borderBottomWidth: 1, borderBottomColor: '#DCD6C4' },
  sectionTitle: { fontSize: 15.5, fontWeight: '900', color: FOREST, marginBottom: 6 },
  barTrack: { height: 8, borderRadius: 99, backgroundColor: '#f0eee3', marginTop: 6, overflow: 'hidden' },
  barFill: { height: 8, borderRadius: 99, backgroundColor: colors.volt },
  certPill: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9, alignSelf: 'center' },
  stampChip: { backgroundColor: '#eef4e0', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 13 },
  photoSlot: { width: TILE, height: TILE * 0.6, backgroundColor: '#f4f2ea', alignItems: 'center', justifyContent: 'center' },
  emptyBox: { margin: 20, backgroundColor: '#f4f2ea', borderRadius: 18, padding: 26, alignItems: 'center' },
  emptyText: { fontSize: 15, color: colors.dim, textAlign: 'center', lineHeight: 22 },
  ctaGhost: { marginTop: 14, backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 10, paddingHorizontal: 18 },
  cta: { backgroundColor: colors.volt, borderRadius: 18, alignItems: 'center', paddingVertical: 15, marginTop: 16 },
  ghostCta: { backgroundColor: '#fff', borderRadius: 16, alignItems: 'center', paddingVertical: 13, marginTop: 8, borderWidth: 1, borderColor: '#DCD6C4' },
});
