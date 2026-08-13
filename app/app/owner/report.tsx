import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Animated, Dimensions, Easing, Image, Pressable, ScrollView, Share, StyleSheet, Text, TextStyle, View } from 'react-native';
import { PatchBadge } from '../../src/components/patch';
import { HeatTrace } from '../../src/components/runcard';
import { traceToBox } from '../../src/lib/trace';
import { PaperBtn } from '../../src/components/paper-btn';
import { Monogram, Row, Skeleton } from '../../src/components/ui';
import { MediaImage } from '../../src/lib/media';
import { CoursePatch, fetchPatchPop, fetchRunEarning, fetchRunReport, fetchRunStandings, fetchStampPop, RunEarning, RunReport, RunStandings, StampInfo } from '../../src/lib/api';
import { haptic } from '../../src/lib/haptics';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { getNaverMap, smoothTrace } from '../../src/lib/geo';
import { draft, TracePoint } from '../../src/store';
import { colors, lilac, paper } from '../../src/theme';

// 러닝 리포트 — 러닝 하나의 '프로필 페이지'. 풀블리드 · 공유 가능 · 사진 · 개인 기록 배지.
// 진입: 알림 · 내 일정 완료 카드 · 체력 리포트 최근 러닝. 공유가 곧 마케팅 (자랑 = 전파).

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
// paper.inkPressed 동반 은퇴 — 다크 카드 위의 더 밝은 안쪽 패널은 paper.inkPressed(#333)가 같은 역할을 한다 (신규 색 0개).
// 읽는 바이올렛 (colors.clubInk와 같은 값 — '텍스트용 2단' 문법). 적립 스트립 키커 전용.
// lilac.bg(#F4F2FB) 위 실측 대비: accent #6C5CE7 = 4.38:1 (AA 미달) · #4A3DA8 = 7.50:1 (통과).
const READ_VIOLET = '#4A3DA8';
const W = Dimensions.get('window').width;
const TILE = (W - 4) / 3;

const REASON: Record<string, { label: string; color: string; bg: string; note?: string }> = {
  completed: { label: '완주 완료', color: '#3d5a2b', bg: '#e3f0c4' },
  dog_condition: {
    label: '반려견 컨디션으로 조기 종료', color: '#d84a2f', bg: '#fde8e3',
    // Trimmed: "러너 판단으로 안전하게 종료했어요" moved into the 왜 멈췄는지 block, which says it
    // better and says it first. What survives here is the half that block does NOT carry — the
    // owner's next action and the recourse path. One fact, one printing.
    note: '아이 상태를 확인해주시고, 이상이 있으면 안심 센터로 연락주세요.',
  },
  owner_request: { label: '보호자 요청으로 종료', color: '#a97c12', bg: '#fbf0d4' },
  runner_personal: { label: '러너 사정으로 종료', color: '#75806f', bg: '#e9ebe2' },
};

const STATUS_LABEL: Record<string, string> = {
  matching: '러너 매칭 중', runner_pending: '러너 응답 대기', confirmed: '러너 확정 — 러닝 전',
  runner_enroute: '러너 이동 중', picked_up: '인계 완료 — 시작 대기', active: '러닝 진행 중',
};

// 실트레이스 → 박스 좌표: src/lib/trace.ts의 traceToBox로 이전 (0082 K1).
// 여기 있던 normalizeTrace는 축별 min-max라 종횡비를 늘렸다 — 동서로 긴 경로가
// 세로로 부푼 실루엣이 되던 버그. 이제 코스·러닝이 같은 투영을 쓴다.

const fmtDur = (sec: number) => `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;
const fmtPace = (sec: number | null) => (sec ? `${Math.floor(sec / 60)}'${String(sec % 60).padStart(2, '0')}"` : '—');
const targetPaceSec = (label: string) => (label.includes('8') ? 480 : label.includes('6') ? 360 : 420);

// 개인 기록 배지 — 내 역사와의 경쟁 (동네 리더보드는 서버 집계 후)
function badges(st: RunStandings | null): string[] {
  if (!st) return [];
  const out: string[] = [`${st.nth}번째 러닝`];
  if (st.total > 1) {
    if (st.kmRank === 1) out.push('★ 역대 최장 거리');
    else if (st.kmRank <= 3) out.push(`거리 TOP ${st.kmRank}`);
    if (st.paceRank === 1) out.push('★ 역대 최고 페이스');
    else if (st.paceRank != null && st.paceRank <= 3) out.push(`페이스 TOP ${st.paceRank}`);
  }
  return out;
}

export default function Report() {
  const df = useDisplayFont(); // 피니셔 증서 서체 — 타이틀·완주 도장 (숫자 금지)
  const nf = useNumFont();     // Oswald 숫자 — 적립 합계 (lineHeight 명시 필수, BUG A)
  const { bid, shot } = useLocalSearchParams<{ bid: string; shot?: string }>();
  const [report, setReport] = useState<RunReport | null>(null);
  const [standings, setStandings] = useState<RunStandings | null>(null);
  const [err, setErr] = useState<string | null>(null);
  // Ⓒ② 오늘의 수확 — 패치 승급 + 이 러닝이 방금 넘긴 도장을 오버레이 '하나'로 (닫기도 하나).
  // null = 그릴 게 없다 (fetch 진행 중 포함) — 둘 다 결과가 온 뒤 내용이 있을 때만 세워진다.
  const [haul, setHaul] = useState<{ patch: CoursePatch | null; stamps: StampInfo[] } | null>(null);
  // 리워드 ① — 이 러닝의 하이 포인트 적립. loaded 플래그가 따로 있는 이유: null 은 '적립 없음'
  // (조기 종료·정산 전)이라는 사실이고, 미도착은 '아직 모름'이다. 둘 다 0을 그리지 않는다.
  const [earning, setEarning] = useState<RunEarning | null>(null);
  const [earningLoaded, setEarningLoaded] = useState(false);
  useEffect(() => {
    if (!bid) { setErr('예약 정보가 없어요'); return; }
    fetchRunReport(bid).then(setReport).catch((e) => setErr(e?.message ?? '불러오기 실패'));
    fetchRunStandings(bid).then(setStandings).catch(() => {});
    // 실패 시 loaded 를 세우지 않는다 — 섹션은 조용히 없는 채로 남는다 (거짓 0 금지)
    setEarning(null);
    setEarningLoaded(false);
    fetchRunEarning(bid).then((e) => { setEarning(e); setEarningLoaded(true); }).catch(() => {});
  }, [bid]);
  // 두 팝을 '같은' effect에서 함께 부른다. 게이트는 각자의 모듈 Set이고 각자 내놓을 게 있을 때만
  // 소비하므로, 재방문 때 둘 다 조용해진다 — 한쪽만 소비된 어정쩡한 상태가 생기지 않는다.
  // 코스가 없는 러닝(routeId null)도 완주 도장은 찍힌다 → 패치 팝만 건너뛴다.
  // 실패는 조용한 부재로: 축하가 못 뜨는 편이 화면이 거짓을 말하는 것보다 낫다 (벽에는 남는다).
  useEffect(() => {
    if (!bid || !report || report.run?.endReason !== 'completed') return;
    const routeId = report.routeId;
    Promise.all([
      routeId ? fetchPatchPop(bid, routeId).catch(() => null) : Promise.resolve(null),
      fetchStampPop(bid).catch(() => [] as StampInfo[]),
    ]).then(([patch, stamps]) => {
      if (!patch && stamps.length === 0) return; // 둘 다 비면 오버레이 자체가 마운트되지 않는다
      setHaul({ patch, stamps });
      haptic('success');
    }).catch(() => {});
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
          `${report.dogName}의 ${run.actualKm}km 러닝 완주!\n` +
          `${fmtDur(run.durationSec)} · 페이스 ${fmtPace(run.paceSecPerKm)}/km\n` +
          `${report.routeName}${report.runnerName ? ` · ${report.runnerName} 러너와 함께` : ''}` +
          (bLine ? `\n${bLine}` : '') +
          `\n\n반려견 피트니스, 도그스하이`,
      });
    } catch { /* 사용자 취소 */ }
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: 40 }}>
        <Row style={{ justifyContent: 'space-between', paddingHorizontal: 12, paddingTop: 56 }}>
          <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
          <Text style={[{ fontSize: 23, fontWeight: '900', color: paper.ink }, df]}>러닝 리포트</Text>
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
            <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>
              {STATUS_LABEL[report.status] ?? '진행 상황 확인 중'}
            </Text>
            <Text style={[s.emptyText, { marginTop: 6 }]}>러닝이 끝나면 여기서 기록을 볼 수 있어요</Text>
            <PaperBtn label="내 일정에서 보기 ›" variant="secondary" style={{ alignSelf: 'stretch', marginTop: 14 }}
              onPress={() => router.replace('/owner/schedule')} />
          </View>
        )}

        {report && run && (
          <>
            {/* ---------- hero: 풀블리드 + 사진 구조화 (사진이 디자인이다) ---------- */}
            <View style={[s.hero, { overflow: 'hidden' }]}>
              {run.photos[0] && (
                /* [0064] 러닝 사진은 프라이빗 media 경로 — 서명 URL로 렌더 */
                <MediaImage
                  source={run.photos[0]}
                  style={{ position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, opacity: 0.28 }}
                  resizeMode="cover"
                />
              )}
              {/* [시뮬 실측 2026-08-11] 두 자식 모두 폭 예산이 없어, 종료 사유 칩이 코스명 위로
                  올라타 '서울숲 숲길 3km'가 잘렸다. 메타 줄은 남는 폭만 갖고 한 줄로 접고(넘치면
                  ellipsize), 칩은 자기 크기를 지킨다 — 칩이 말하는 건 사유이고, 사유는 잘리면 안 된다. */}
              <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start', gap: 8 }}>
                <Text style={{ fontSize: 14, color: '#b8c4ae', flex: 1, minWidth: 0 }} numberOfLines={1}>
                  {report.when} · {report.routeName}
                </Text>
                {reason && run.endReason !== 'completed' && (
                  <View style={[s.heroReason, { backgroundColor: reason.bg, flexShrink: 0 }]}>
                    <Text style={{ fontSize: 14, fontWeight: '900', color: reason.color }}>{reason.label}</Text>
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
                      <Text style={{ fontSize: 14, fontWeight: '900', color: paper.ink }}>{b}</Text>
                    </View>
                  ))}
                </Row>
              )}
              <Row style={{ marginTop: 14, backgroundColor: paper.inkPressed, borderRadius: 14, paddingVertical: 12, justifyContent: 'space-around' }}>
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
                  <HeatTrace points={traceToBox(run.trace)} width={W - 60} height={140} />
                  <Text style={{ fontSize: 14, color: '#8fa093', marginTop: 6 }}>실제 GPS 경로 · 지도 배경은 새 빌드에서</Text>
                </View>
              );
            })()}

            {/* ---------- 하이 포인트 적립 (리워드 ①) — 이 러닝이 벌어들인 것 ----------
                영수증이지 팡파레가 아니다: 애니메이션 없음 (축하는 패치 팝 하나뿐).
                원장 행이 0이면 fetchRunEarning 이 null 을 주고 섹션 자체가 사라진다 —
                조기 종료 러닝은 서버가 한 줄도 안 쓰므로 '적립 0원'이 아니라 '없는 이야기'다.
                endReason 게이트는 서버 게이트(v_is_full)의 클라 거울. */}
            {earningLoaded && earning && run.endReason === 'completed' && (
              <View style={s.earnSection}>
                <Text style={s.earnKicker}>하이 포인트 적립</Text>
                <Row style={{ alignItems: 'baseline', marginTop: 4 }}>
                  <Text style={[s.earnTotal, nf]}>{earning.total > 0 ? '+' : ''}{earning.total.toLocaleString()}</Text>
                  <Text style={s.earnUnit}> 포인트</Text>
                </Row>
                <View style={{ marginTop: 10 }}>
                  {earning.lines.map((l, i) => (
                    <Row key={`${l.reason}-${i}`} style={{ justifyContent: 'space-between', marginTop: i === 0 ? 0 : 5 }}>
                      <Text style={s.earnLabel}>{l.label}</Text>
                      <Text style={s.earnDelta}>{l.delta > 0 ? '+' : ''}{l.delta.toLocaleString()}</Text>
                    </Row>
                  ))}
                </View>
              </View>
            )}

            {/* ---------- 러닝 순간 스탬프 (응가 도장 등) ---------- */}
            {run.events.length > 0 && (
              <View style={[s.section, { flexDirection: 'row', gap: 8, flexWrap: 'wrap' }]}>
                {(
                  [['poop', '응가'], ['snack', '간식'], ['water', '물'], ['photo', '사진']] as const
                ).map(([kind, label]) => {
                  const n = run.events.filter((e) => e.kind === kind).length;
                  if (n === 0) return null;
                  return (
                    <View key={kind} style={s.stampChip}>
                      <Text style={{ fontSize: 14.5, fontWeight: '900', color: paper.actionInk }}>{label} ×{n}</Text>
                    </View>
                  );
                })}
                <Text style={{ fontSize: 14, color: colors.dim, width: '100%', marginTop: 4 }}>
                  러너가 러닝 중 실시간으로 기록한 순간들이에요
                </Text>
              </View>
            )}

            {/* ---------- 사진: 엣지-투-엣지 ---------- */}
            {run.photos.length > 0 ? (
              <View style={{ backgroundColor: '#fff', flexDirection: 'row', flexWrap: 'wrap', gap: 2 }}>
                {run.photos.map((url) => (
                  <MediaImage key={url} source={url} style={{ width: TILE, height: TILE, backgroundColor: '#DCD6C4' }} />
                ))}
              </View>
            ) : (
              /* [정직 배치 2.5 · 감사 #31] 유령 타일 3개 은퇴 — 채워질 자리인 척하는 빈 액자였다.
                 바디캠 하이라이트도 파이프라인이 없으므로 약속에서 뺀다. 끝난 러닝의 사실은 과거형 한 줄. */
              <View style={{ backgroundColor: '#fff', paddingHorizontal: 20, paddingTop: 4, paddingBottom: 14 }}>
                <Text style={{ fontSize: 15, fontWeight: '700', color: paper.ink, textAlign: 'center' }}>
                  이번 러닝은 사진이 없어요
                </Text>
                <Text style={{ fontSize: 14, color: colors.dim, textAlign: 'center', marginTop: 3 }}>
                  러너가 러닝 중 남긴 사진이 있으면 여기에 표시돼요
                </Text>
              </View>
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
                  <Text style={{ fontSize: 16.5, fontWeight: '900', color: paper.ink }}>
                    {report.runnerName ?? '러너'} 러너
                  </Text>
                  <Text style={{ fontSize: 15, color: colors.dim, marginTop: 2 }}>
                    {report.routeName}{report.routeArea ? ` · ${report.routeArea}` : ''}
                  </Text>
                </View>
                {/* [honesty audit 2026-08-11 · P1 #3] 신원인증 badge retired — it was stamped on
                    every runner unconditionally with no data source (meetup.tsx already retired
                    the same badge for the same reason, P1-6). The runners.identity_verified
                    column exists, but its current values originate from the bootstrap/seed
                    fabrication (see api.ts fetchMyRunnerCert note and the 0061 insert-seal
                    rationale), so binding it would still render a review that never happened.
                    Re-add bound to the real field once the 0062 application funnel is the only
                    writer and existing fabricated rows are cleaned. */}
              </Row>
            </View>

            {/* ---------- 왜 멈췄는지 (컨디션 종료 전용) ----------
                G1 (docs/decisions/g1-abort-charge-basis.md) makes a welfare stop a REAL BILL, and
                both adversarial rounds flagged the same consequence: an owner who feels charged for
                a stopped run leans on the next runner to keep going. The agreed mitigation is copy,
                and this is it. Two jobs, and the second one is newer than the first:

                ① Say plainly that stopping was right. Note the claim is about the DECISION, not
                   about the dog — we do not know the dog was unwell, and asserting a diagnosis we
                   cannot see would be the same fabrication this section exists to retire.
                ② Carry enough for the owner to JUDGE the stop. Under G1 the owner pays, so the
                   owner is now the auditor of an abort — the fraud posture inverted the day the
                   waive ended. That means the runner's own words (real since 611f014; before it,
                   every owner read one hardcoded sentence) plus where it happened.  */}
            {run.endReason === 'dog_condition' && (
              <View style={s.section}>
                <Text style={s.sectionTitle}>왜 멈췄는지</Text>
                <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink, lineHeight: 21 }}>
                  아이가 힘들어 보이면 멈추는 게 맞아요.
                </Text>
                <Text style={{ fontSize: 14.5, color: paper.dim, marginTop: 5, lineHeight: 20.5 }}>
                  러너는 그렇게 하도록 안내받아요. 끝까지 달리는 것보다 아이 상태가 먼저예요.
                </Text>

                {run.conditionNote ? (
                  <View style={{ marginTop: 13, borderLeftWidth: 2, borderLeftColor: paper.line, paddingLeft: 11 }}>
                    <Text style={{ fontSize: 14, fontWeight: '800', color: paper.dim, marginBottom: 4 }}>
                      러너가 본 것
                    </Text>
                    <Text style={{ fontSize: 15, color: '#49524a', lineHeight: 21.5 }}>{run.conditionNote}</Text>
                  </View>
                ) : (
                  /* Loading ≠ empty ≠ absent (§7): the note is required at the stop, so a missing
                     one is a real gap in the record — say so rather than rendering nothing. */
                  <Text style={{ fontSize: 14, color: paper.dim, marginTop: 13, lineHeight: 20 }}>
                    러너 메모가 기록되지 않았어요 — 안심 센터로 문의해주세요.
                  </Text>
                )}

                <Text style={{ fontSize: 14, color: paper.dim, marginTop: 13, lineHeight: 20 }}>
                  {run.actualKm}km 지점 · {fmtDur(run.durationSec)} 지나 종료했어요
                </Text>
                {reason?.note && (
                  <Text style={{ fontSize: 14, color: reason.color, marginTop: 9, lineHeight: 19.5 }}>
                    {reason.note}
                  </Text>
                )}
              </View>
            )}

            {/* ---------- 러너 노트 (그 외 사유) ---------- */}
            {run.endReason !== 'dog_condition' && (run.conditionNote || reason?.note) && (
              <View style={s.section}>
                <Text style={s.sectionTitle}>러너 노트</Text>
                {run.conditionNote && (
                  <Text style={{ fontSize: 14.5, color: '#49524a', lineHeight: 20.5 }}>{run.conditionNote}</Text>
                )}
                {reason?.note && (
                  <Text style={{ fontSize: 14, color: reason.color, marginTop: run.conditionNote ? 8 : 0, lineHeight: 19.5 }}>
                    {reason.note}
                  </Text>
                )}
              </View>
            )}

            {/* ---------- 결제 ---------- */}
            {/* [2026-08-13] This block used to print `bookings.total_price` under the label
                결제 금액 — the FROZEN PLANNED total minted at booking time, not what was
                charged. compute_owner_charge (0084 §A) bills `least(actual, km)` for every
                reason except owner-caused ends, and `runner_personal` drops the base and
                addons entirely, so any early-ended run showed a number the owner was never
                billed, on the one screen they open to check what a run cost. Beneath it sat
                "조기 종료 시 정산 조정은 고객센터를 통해 처리돼요" — naming a support process
                that does not exist anywhere in this app (settle-time adjustment is automatic).
                Two assertions, neither backed; found by the ⑩ class sweep
                (docs/decisions/cancel-fee-runner-share.md).
                The fix is not a corrected number here. §0-bis is explicit that the post-run
                moment is the RECORD CARD — the dog, never the charge — and that money lives in
                exactly two modes, on demand and on exception. So the charge leaves this screen
                and the receipt stays one tap away, which is what the doctrine actually asks
                for. /payments is the on-demand half and reads the real `payments` rows. */}
            <View style={s.section}>
              <PaperBtn
                label="결제 내역 보기"
                variant="secondary"
                onPress={() =>
                  router.push({
                    pathname: '/payments',
                    params: { returnTo: `/owner/report?bid=${bid ?? ''}`, returnLabel: '러닝 리포트로' },
                  })}
              />
              <Text style={{ fontSize: 14, color: paper.dim, marginTop: 8, lineHeight: 19, textAlign: 'center' }}>
                실제 청구된 금액과 영수증은 결제 내역에 있어요
              </Text>
            </View>

            {/* ---------- CTA ---------- */}
            {/* [액션 롤아웃 2026-08-11] 여섯 개가 세로로 쌓여 있었고 셋은 중복이었다:
                · '동네 피드에 자랑하기' — compose.tsx가 완주 러닝 피커로 이 일을 이미 한다
                · '↗ 텍스트로 공유' — 인증샷 스튜디오가 끝나면서 여는 OS 공유 시트가 상위 호환이다
                  (그건 실제 이미지를 나른다; 이건 글자만 나른다). 헤더의 ↗ 버튼도 남아 있다.
                · '홈으로' — 뒤로가기 버튼과 탭바가 이미 하는 일
                남은 셋은 서로 다른 일을 한다. 강조는 하나다 (§7b Von Restorff):
                **이대로 다시 예약**이 프라이머리다 — 두 번째 예약이 이 제품의 PMF 지표다. */}
            <View style={{ paddingHorizontal: 12, gap: 8, marginTop: 16 }}>
              <PaperBtn
                label="⟳ 이대로 다시 예약"
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
              />
              <Text style={{ fontSize: 14, lineHeight: 19, color: paper.dim, textAlign: 'center', marginBottom: 4 }}>
                같은 코스·거리{report.runnerName ? ` · ${report.runnerName} 러너 지명` : ''} — 시간만 고르면 돼요
              </Text>
              <PaperBtn label="인증샷 만들기" variant="secondary"
                onPress={() => bid && router.push(`/shot/${bid}`)} />
              {report.status === 'completed' && report.runnerProfileId && (
                <PaperBtn label={`★ ${report.runnerName ?? ''} 러너 후기 남기기`} variant="secondary"
                  onPress={() => router.push({ pathname: '/owner/review', params: { bid: bid!, rid: report.runnerProfileId!, rname: report.runnerName ?? '러너' } })} />
              )}
            </View>
          </>
        )}
      </ScrollView>

      {/* ---------- 오늘의 수확 — 패치 승급 + 새 도장 병합 세리머니 (탭 = 닫기) ---------- */}
      {haul && (
        <HaulOverlay
          patch={haul.patch}
          stamps={haul.stamps}
          nf={nf}
          onClose={() => setHaul(null)}
          onCollection={() => { setHaul(null); router.push('/cards'); }}
        />
      )}
    </View>
  );
}

// 승급 어휘 — 문장 안에 들어가므로 느낌표 없이 ('실버 승급 · 서울숲 순환 코스 ×5')
const POP_TITLE: Record<string, string> = { basic: '패치 획득', silver: '실버 승급', gold: '골드 승급', master: '코스 마스터' };

// ═══════ Ⓒ② 오늘의 수확 — 오버레이 하나 · 세계 하나 · 닫기 하나 ═══════
// 배경은 나이트 라일락을 0.94로 덮는다. 예전 rgba(10,16,10,.72)는 새 적립 스트립과 응가 칩이
// 그대로 읽혀 '축하 위에 영수증'이 겹쳐 보였다 (랩이 실측해 잡은 결함) — 포레스트 잔재도 함께 라일락으로.
// 세 가지 정직한 모양으로 degrade한다: 패치만 · 도장만 · 둘 다. 아무것도 없으면 마운트조차 안 된다.
const STAMP_INK = '#B9AEF5';    // 나이트 위 도장 잉크 — 벽의 #4A3DA8은 어두운 배경에서 사라진다
const STAMP_FIRST = '#FF9C82';  // 첫-family 외곽링·도트 (코랄은 링이지 절대 글자가 아니다)
const HAUL_DIM = '#A9A3C8';     // 보조 텍스트 (#1C1837 위 7.09:1 — 실측)
// 한 줄에 놓을 도장 수. 셀 100 + gap 12 → 3칸 324px가 들어가려면 가용폭(W−52) ≥ 324, 즉 W ≥ 376.
// 375dp(가용 323)에서 1px 넘쳐 2+1로 감기던 것을 폭으로 가른다 — 도장 크기는 절대 줄이지 않는다.
const HAUL_CAP = W >= 377 ? 3 : 2;

// 도장 한 개 — 벽과 같은 문법(숫자+한글, 링 수가 사다리, 첫-family만 코랄 링+도트)의 나이트 버전
function StampDisc({ info, nf }: { info: StampInfo; nf: TextStyle | null }) {
  const D = 92;
  const edge = info.coral ? STAMP_FIRST : STAMP_INK;
  return (
    <View style={[s.disc, { width: D, height: D, borderRadius: D / 2, borderColor: edge }]}>
      {info.rings >= 2 && (
        <View style={[s.discRing, { left: 5, right: 5, top: 5, bottom: 5, borderRadius: (D - 10) / 2, borderColor: edge, opacity: 0.85 }]} />
      )}
      {info.rings >= 3 && (
        <View style={[s.discRing, { left: -6, right: -6, top: -6, bottom: -6, borderRadius: (D + 12) / 2, borderColor: STAMP_INK, opacity: 0.55 }]} />
      )}
      {info.coral && <View style={[s.discDot, { left: (D - 5) / 2 - 4 }]} />}
      {/* [BUG A] Oswald 숫자는 lineHeight 명시 없이 어센더가 잘린다 — 27 × 1.2 = 33 */}
      <Text style={[{ fontSize: 27, lineHeight: 33, fontWeight: '600', color: STAMP_INK }, nf]}>{info.num}</Text>
      <Text style={{ fontSize: 15, lineHeight: 19, fontWeight: '800', color: STAMP_INK, marginTop: 1 }}>{info.word}</Text>
    </View>
  );
}

function HaulOverlay({ patch, stamps, nf, onClose, onCollection }: {
  patch: CoursePatch | null; stamps: StampInfo[]; nf: TextStyle | null; onClose: () => void; onCollection: () => void;
}) {
  // 한 줄 상한(폭에 따라 3 또는 2). 넘치면 '외 N개'로 적고 도장을 줄이지 않는다.
  const shown = stamps.slice(0, HAUL_CAP);
  const more = stamps.length - shown.length;
  const kick = useRef(new Animated.Value(0)).current;
  const pa = useRef(new Animated.Value(0)).current;
  // 훅 수는 고정 — 상한이 3칸이라 값 3개를 항상 만든다 (조건부 훅 금지)
  const s0 = useRef(new Animated.Value(0)).current;
  const s1 = useRef(new Animated.Value(0)).current;
  const s2 = useRef(new Animated.Value(0)).current;
  const copy = useRef(new Animated.Value(0)).current;
  const slams = [s0, s1, s2];
  useEffect(() => {
    const steps: Animated.CompositeAnimation[] = [];
    // ① 패치가 먼저 스프링으로 박힌다 (오늘 쓰던 값 그대로 — friction 5 · tension 90)
    if (patch) steps.push(Animated.spring(pa, { toValue: 1, friction: 5, tension: 90, useNativeDriver: true }));
    // ② 도장이 차례로 내려찍힌다 — 영수증 실 스탬프의 커브 그대로, 80ms 간격
    if (shown.length > 0) {
      steps.push(Animated.stagger(80, shown.map((_, i) => Animated.timing(slams[i], {
        toValue: 1, duration: 340, easing: Easing.bezier(0.5, 0, 0.7, 0.35), useNativeDriver: true,
      }))));
    }
    // ③ 카피와 CTA가 마지막에 올라온다
    steps.push(Animated.timing(copy, { toValue: 1, duration: 320, useNativeDriver: true }));
    Animated.parallel([
      Animated.timing(kick, { toValue: 1, duration: 300, useNativeDriver: true }),
      Animated.sequence(steps),
    ]).start();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <Pressable onPress={onClose} style={s.haulBack}>
      <Animated.Text style={[s.haulKicker, { opacity: kick }]}>DOGS HIGH · 오늘의 수확</Animated.Text>

      {patch && (
        <>
          {/* 패치는 자기 색(자수 오브젝트)을 그대로 지킨 채 여권의 나이트 배경 위에 앉는다 */}
          <Animated.View style={{
            alignItems: 'center',
            opacity: pa,
            transform: [
              { scale: pa.interpolate({ inputRange: [0, 1], outputRange: [0.4, 1] }) },
              { rotate: pa.interpolate({ inputRange: [0, 1], outputRange: ['-18deg', '-4deg'] }) },
            ],
          }}>
            <PatchBadge km={patch.km} name={patch.name} grade={patch.grade} size={132} />
          </Animated.View>
          <Animated.Text style={[s.haulPatchLine, { opacity: pa }]}>
            {POP_TITLE[patch.grade]} · {patch.name} {patch.count === 1 ? '첫 완주' : `×${patch.count}`}
          </Animated.Text>
        </>
      )}

      {patch && shown.length > 0 && <View style={s.haulPerf} />}

      {shown.length > 0 && (
        <View style={s.haulRow}>
          {shown.map((st, i) => (
            <Animated.View
              key={st.key}
              style={{
                // 셀 100 + gap 12 → 3칸 324 / 2칸 212. 오버레이 가용폭 = W − 좌우 패딩 52
                alignItems: 'center', width: 100,
                opacity: slams[i],
                transform: [
                  { scale: slams[i].interpolate({ inputRange: [0, 1], outputRange: [2.2, 1] }) },
                  // 착지 각도는 그 도장의 고정 기울기(api.ts angle) — 벽과 세리머니가 같은 손도장이어야 한다
                  { rotate: slams[i].interpolate({ inputRange: [0, 1], outputRange: ['-12deg', `${st.angle}deg`] }) },
                ],
              }}
            >
              <StampDisc info={st} nf={nf} />
              <Text style={s.haulCap}>{st.label}</Text>
            </Animated.View>
          ))}
        </View>
      )}

      <Animated.View style={{
        alignItems: 'center',
        opacity: copy,
        transform: [{ translateY: copy.interpolate({ inputRange: [0, 1], outputRange: [8, 0] }) }],
      }}>
        {more > 0 && <Text style={s.haulMore}>외 {more}개</Text>}
        {shown.length > 0 ? (
          <>
            <Text style={s.haulSub}>여권에 새 도장 {stamps.length}개가 찍혔어요</Text>
            {/* '지워지지 않아요'는 거짓이 될 수 있다 — 자랑 글 삭제·코스 비활성은 실제 감소 벡터다 (api.ts 계약 주석) */}
            <Text style={s.haulNote}>기록이 남아 있는 한 도장은 그대로예요</Text>
          </>
        ) : (
          <Text style={s.haulSub}>패치가 컬렉션에 들어갔어요</Text>
        )}
        <Pressable onPress={onCollection} style={s.haulCta}>
          <Text style={s.haulCtaText}>컬렉션 보기 ›</Text>
        </Pressable>
        <Text style={s.haulHint}>탭하면 닫혀요</Text>
      </Animated.View>
    </Pressable>
  );
}

function HeroStat({ value, label }: { value: string; label: string }) {
  return (
    <View style={{ alignItems: 'center' }}>
      <Text style={{ fontSize: 18.5, fontWeight: '900', color: '#fff' }}>{value}</Text>
      <Text style={{ fontSize: 14, color: '#b8c4ae', marginTop: 3 }}>{label}</Text>
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
        <Text style={{ fontSize: 15, fontWeight: '900', color: pct >= 100 ? paper.readyDeep : paper.ink }}>{pct}%</Text>
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
  // §2 종이 크롬: 40×40 **정사각**, 캔버스 면, 1px 코랄 트림 (runner/meetup circleBtn 문법 —
  // 이름만 circle이고 모양은 사각이다). 종전 borderRadius 20 + 베이지 트림은 V4 잔재였다.
  backBtn: { width: 40, height: 40, borderRadius: 0, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: paper.line },
  hero: { backgroundColor: paper.ink, padding: 20, marginTop: 14 },
  heroReason: { borderRadius: 0, paddingVertical: 4, paddingHorizontal: 9 }, // §3b 상태 칩 = radius 0
  finStamp: {
    position: 'absolute', top: 52, right: 18, alignItems: 'center',
    borderWidth: 2.5, borderColor: colors.volt, borderRadius: 10,
    paddingVertical: 6, paddingHorizontal: 12, transform: [{ rotate: '-9deg' }], opacity: 0.92,
  },
  heroDiv: { width: 1, backgroundColor: '#2c4034' },
  badgePill: { backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 4, paddingHorizontal: 10 },
  // 섹션 분할은 풀블리드 솔리드 코랄 1px — 이 선이 곧 브랜드 (§2 종이 법)
  section: { backgroundColor: paper.canvas, paddingHorizontal: 12, paddingVertical: 16, borderBottomWidth: 1, borderBottomColor: paper.line },
  // §3b 섹션 헤더는 앱 전체에서 하나의 문법: 20/800 잉크. 화면마다 크기를 달리 쓰지 않는다.
  sectionTitle: { fontSize: 20, fontWeight: '800', color: paper.ink, marginBottom: 6 },
  barTrack: { height: 8, borderRadius: 99, backgroundColor: '#EEEEEE', marginTop: 6, overflow: 'hidden' }, // 은퇴 팔레트 크림(#f0eee3) → 뉴트럴
  barFill: { height: 8, borderRadius: 99, backgroundColor: colors.volt },
  // 은퇴 팔레트(연두 워시)의 마지막 잔재 + 알약 코너. 코랄 워시 위 샤프 칩으로.
  stampChip: { backgroundColor: paper.wash, borderRadius: 0, paddingVertical: 7, paddingHorizontal: 13 },
  // ---------- 리워드 ① 적립 스트립 — 조용한 라일락 영수증 (섹션 리듬은 s.section과 동일) ----------
  earnSection: {
    backgroundColor: lilac.bg, paddingHorizontal: 12, paddingVertical: 16,
    borderBottomWidth: 1, borderBottomColor: lilac.hair,
  },
  // 한글 키커 — 라틴 대문자 예외가 아니므로 플로어 14를 그대로 지킨다.
  // 색은 accent(#6C5CE7)가 아니라 READ_VIOLET: lilac.bg 위에서 accent는 4.38:1로 AA를 못 넘는다
  earnKicker: { fontSize: 14, lineHeight: 18, fontWeight: '800', letterSpacing: 1.2, color: READ_VIOLET },
  // [BUG A] Oswald 숫자는 lineHeight 명시 없이는 어센더가 잘린다 — 34 × 1.2 = 41
  earnTotal: { fontSize: 34, lineHeight: 41, fontWeight: '900', color: lilac.head },
  // 단위는 lilac.dim(#7C76A0)이 아니라 text — dim은 lilac.bg 위에서 3.82:1로 AA 미달
  earnUnit: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: lilac.text },
  earnLabel: { fontSize: 14, lineHeight: 19, color: lilac.text },
  earnDelta: { fontSize: 14, lineHeight: 19, fontWeight: '800', color: lilac.head },
  // ---------- Ⓒ② 오늘의 수확 오버레이 — 나이트 라일락 한 겹 (transform/opacity만 애니) ----------
  haulBack: {
    position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
    // 나이트 라일락 #1C1837 · 0.94 — 랩이 잡은 결함(0.72는 적립 스트립·응가 칩이 그대로 읽힌다)의 수정치
    backgroundColor: 'rgba(28,24,55,0.94)',
    alignItems: 'center', justifyContent: 'center', paddingHorizontal: 26, paddingVertical: 30,
  },
  // 라틴+한글 혼합 키커 — 라틴 대문자 예외가 아니므로 14pt 플로어를 그대로 지킨다
  haulKicker: { fontSize: 14, lineHeight: 18, fontWeight: '700', letterSpacing: 2.4, color: STAMP_INK, marginBottom: 14 },
  haulPatchLine: { fontSize: 14, lineHeight: 19, fontWeight: '800', color: '#fff', marginTop: 12, textAlign: 'center' },
  haulPerf: { alignSelf: 'stretch', marginHorizontal: 8, marginTop: 15, marginBottom: 14, borderTopWidth: 1, borderStyle: 'dashed', borderTopColor: 'rgba(255,255,255,0.3)' },
  // 줄바꿈은 HAUL_CAP이 이미 막았다 (376dp 미만은 2칸) — wrap은 폰트 확대 등 예외 상황의 안전망
  haulRow: { flexDirection: 'row', flexWrap: 'wrap', justifyContent: 'center', gap: 12 },
  disc: {
    borderWidth: 2.5, backgroundColor: 'rgba(185,174,245,0.10)',
    alignItems: 'center', justifyContent: 'center',
  },
  discRing: { position: 'absolute', borderWidth: 1.5 },
  discDot: { position: 'absolute', top: -4, width: 8, height: 8, borderRadius: 4, backgroundColor: STAMP_FIRST },
  haulCap: { fontSize: 14, lineHeight: 18, fontWeight: '800', color: '#fff', marginTop: 8, textAlign: 'center' },
  haulMore: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: HAUL_DIM, marginTop: 10 },
  haulSub: { fontSize: 14, lineHeight: 19, fontWeight: '800', color: HAUL_DIM, marginTop: 14, textAlign: 'center' },
  haulNote: { fontSize: 14, lineHeight: 19, color: HAUL_DIM, marginTop: 3, textAlign: 'center' },
  haulCta: { backgroundColor: '#fff', borderRadius: 99, paddingVertical: 11, paddingHorizontal: 22, marginTop: 16 },
  haulCtaText: { fontSize: 15, lineHeight: 20, fontWeight: '900', color: lilac.head },
  haulHint: { fontSize: 14, lineHeight: 18, color: HAUL_DIM, marginTop: 12 },
  emptyBox: { margin: 20, backgroundColor: paper.wash, borderRadius: 0, padding: 26, alignItems: 'center', borderWidth: 1, borderColor: paper.line },
  emptyText: { fontSize: 15, color: paper.dim, textAlign: 'center', lineHeight: 22 },
});
