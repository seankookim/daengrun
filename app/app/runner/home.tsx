import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Animated, Easing, Linking, Pressable, ScrollView, StyleSheet, Text, TextStyle, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { CourseStrip } from '../../src/components/CourseStrip';
import { RunnerClubCard } from '../../src/components/clubcard';
import { Row } from '../../src/components/ui';
import {
  AvailRule, CoursePatch, fetchCoursePatches, fetchMyAvailability, fetchMyName, fetchMyRunnerStatus, fetchRunnerInbox, fetchRunnerJobs,
  fetchRunnerWeekStats, MyRunnerStatus, OpenRequest, RunnerJob, RunnerWeekStats, saveMyAvailability, setRunnerOnline,
} from '../../src/lib/api';
import { PatchBadge } from '../../src/components/patch';
import { registerPushToken } from '../../src/lib/push';
import { runnerJob } from '../../src/store';
import { colors, lilac, lilacRadius } from '../../src/theme';

// 러너 홈 — 테일러드 라일락 리페인트 (빕 퍼스트 × 정산 장부 × 클럽 엔진).
// 컬러 월드 결정: DAWN DUAL — 코랄이 정체성·CTA(빕 토글·수락 문·라이브), 바이올렛이 구조·클럽.
// 로직은 동결: 모든 훅·데이터 페치·핸들러·라우터 타깃·조건 가드 보존, JSX/StyleSheet만 재도색.
// 2026-08-03 FIX 라운드 (Sean 디바이스): 타입 스케일 ~1.75× · 모든 컨테이너 리플로 · 빕 대형숫자/₩·금액 오버랩 제거.

const DAY_ORDER = [1, 2, 3, 4, 5, 6, 0]; // 월…일
const DAY_NAME = '일월화수목금토';
const hh = (m: number) => String(Math.floor(m / 60)).padStart(2, '0');

// 코랄-텍스트 법: 흰 텍스트는 오직 어두운 터미널 스톱(≥ #C6472C, 백지 4.84:1) 위에.
// 밝은 --coral(#F0765A)은 fill/edge/dot·글로우 섀도로만 생존, 절대 그 위에 흰 소자 텍스트 금지.
const CORAL_INK = '#C6472C';
const CORAL_INK_DEEP = '#B23E25';

const TIER_LABEL: Record<string, string> = { certified: '인증 러너', veteran: '베테랑', master: '마스터' };

// 진행 단계 메타 — 서버 상태 → 러너가 지금 뭘 해야 하는지 (라벨·액션 동결, 색만 라일락으로 재매핑)
const STAGE: Record<string, { label: string; action: string; color: string }> = {
  confirmed: { label: '픽업 대기', action: '픽업 이동 시작 ›', color: lilac.amber },
  runner_enroute: { label: '픽업 이동 중', action: '인계 화면으로 ›', color: lilac.amber },
  picked_up: { label: '인계 완료 · 시작 대기', action: '러닝 시작하기 ›', color: lilac.voltDeep }, // 확인/성공 볼트만 기능적
  active: { label: '러닝 중 · LIVE', action: '러닝 화면으로 ›', color: CORAL_INK },
};

// 픽업 지도 숏컷 — 실좌표는 주소 실화 후 (meetup과 동일한 목업 좌표)
const PICKUP = { lat: 37.5443, lng: 127.0398, name: '서울숲 2번 출입구' };
async function openNaverRoute() {
  const app = `nmap://route/walk?dlat=${PICKUP.lat}&dlng=${PICKUP.lng}&dname=${encodeURIComponent(PICKUP.name)}&appname=com.daengrun.app`;
  const web = `https://map.naver.com/p/directions/-/${PICKUP.lng},${PICKUP.lat},${encodeURIComponent(PICKUP.name)}/-/walk`;
  try {
    const canApp = await Linking.canOpenURL(app);
    await Linking.openURL(canApp ? app : web);
  } catch { Linking.openURL(web).catch(() => {}); }
}

// 파동 링 — 긴급/도착 신호. 링 두 개가 900ms 간격으로 퍼져나간다 (네이티브 드라이버)
function PulseRings({ color = colors.tang, size = 30 }: { color?: string; size?: number }) {
  const a1 = useRef(new Animated.Value(0)).current;
  const a2 = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    const mk = (v: Animated.Value, delay: number) => Animated.loop(Animated.sequence([
      Animated.delay(delay),
      Animated.timing(v, { toValue: 1, duration: 1800, easing: Easing.out(Easing.quad), useNativeDriver: true }),
    ]));
    const l1 = mk(a1, 0);
    const l2 = mk(a2, 900);
    l1.start(); l2.start();
    return () => { l1.stop(); l2.stop(); };
  }, [a1, a2]);
  const ring = (v: Animated.Value) => (
    <Animated.View
      pointerEvents="none"
      style={{
        position: 'absolute', width: size, height: size, borderRadius: size / 2,
        borderWidth: 1.5, borderColor: color,
        opacity: v.interpolate({ inputRange: [0, 0.15, 1], outputRange: [0, 0.85, 0] }),
        transform: [{ scale: v.interpolate({ inputRange: [0, 1], outputRange: [0.45, 1.6] }) }],
      }}
    />
  );
  return <>{ring(a1)}{ring(a2)}</>;
}

// 홀로 상단 엣지 — 3px 포일 트림 (빕·장부·티켓·스텁). 포일 예산: 모노그램 + 카드 엣지만.
const HOLO = ['#CFC4FF', '#FFD9CB', '#F3E9C6', '#EAF6C8', '#CFE0FF'];
function HoloEdge({ radius = false }: { radius?: boolean }) {
  return (
    <View style={[styles.holo, radius && { borderTopLeftRadius: lilacRadius.card, borderTopRightRadius: lilacRadius.card }]}>
      {HOLO.map((c, i) => <View key={i} style={{ flex: 1, backgroundColor: c }} />)}
    </View>
  );
}

// 바코드 푸터 — 러너 빕/티켓 스톱마크
const BAR_W = [2, 1, 3, 1, 1, 2, 1, 3, 2, 1, 1, 2, 3, 1, 2, 1, 1, 3, 1, 2, 2, 1, 3, 1, 2, 1, 1, 2, 3, 1, 2, 1];
function Barcode({ width = 150 }: { width?: number }) {
  return (
    <View style={{ height: 18, width, flexDirection: 'row', alignItems: 'stretch', overflow: 'hidden', opacity: 0.82 }}>
      {BAR_W.map((w, i) => (
        <View key={i} style={{ width: w, marginRight: i % 3 === 0 ? 2.5 : 1.5, backgroundColor: i % 2 ? 'transparent' : lilac.head }} />
      ))}
    </View>
  );
}

// 섹션 룰 — 에디토리얼 순차 넘버 (01→06)
function SectionRule({ no, title, link, onPress }: { no: string; title: string; link?: string; onPress?: () => void }) {
  return (
    <Row style={{ alignItems: 'center', gap: 8, marginTop: 10 }}>
      <Text style={styles.srNo}>{no}</Text>
      <Text style={styles.srTitle}>{title}</Text>
      <View style={styles.rule} />
      {link ? <Pressable onPress={onPress}><Text style={styles.srLink}>{link}</Text></Pressable> : null}
    </Row>
  );
}

// 캡션 헤더 — 넘버 없는 섹션 (진행중·클럽)
function CapHead({ title, link, onPress }: { title: string; link?: string; onPress?: () => void }) {
  return (
    <Row style={{ alignItems: 'center', gap: 8, marginTop: 6 }}>
      <Text style={styles.srTitle}>{title}</Text>
      <View style={styles.rule} />
      {link ? <Pressable onPress={onPress}><Text style={styles.srLink}>{link}</Text></Pressable> : null}
    </Row>
  );
}

// 장부 점선 리더 행 — 좌 라벨 · 점선 리더 · 우 값
function LedgerRow({ label, sub, value, unit, nf, total }: {
  label: string; sub: string; value: string; unit: string; nf: TextStyle | null; total?: boolean;
}) {
  return (
    <Row style={[styles.lr, total && { borderBottomWidth: 0 }]}>
      <View style={{ width: 132 }}>
        <Text style={styles.lrLabel}>{label}</Text>
        <Text style={styles.lrSub}>{sub}</Text>
      </View>
      <View style={styles.lead} />
      <Text style={styles.lrVal}>
        <Text style={[styles.lrValNum, nf, total && { fontSize: 25 }]}>{value}</Text>{unit}
      </Text>
    </Row>
  );
}

export default function RunnerHome() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면당 1회 (빕 네임)
  const nf = useNumFont();     // 숫자 서체 — Oswald tabular
  const [inbox, setInbox] = useState<OpenRequest[]>([]);
  const [name, setName] = useState<string | null>(null);
  const [stats, setStats] = useState<RunnerWeekStats>({ net: 0, runs: 0, km: 0 });
  const [jobs, setJobs] = useState<RunnerJob[]>([]);
  const [patchMap, setPatchMap] = useState<Record<string, CoursePatch>>({}); // 완료 카드 미니 패치
  const [rs, setRs] = useState<MyRunnerStatus>({ totalRuns: 0, totalKm: 0, online: false, tier: 'certified' });
  const [avail, setAvail] = useState<AvailRule[] | null>(null);

  useFocusEffect(useCallback(() => {
    fetchMyAvailability().then(setAvail).catch((e) => console.warn('[rhome] avail:', e?.message ?? e));
    fetchRunnerInbox().then(setInbox).catch((e) => console.warn('[rhome] inbox:', e?.message ?? e));
    fetchMyName().then(setName).catch(() => {});
    fetchRunnerWeekStats().then(setStats).catch((e) => console.warn('[rhome] stats:', e?.message ?? e));
    fetchRunnerJobs().then(setJobs).catch((e) => console.warn('[rhome] jobs:', e?.message ?? e));
    fetchCoursePatches()
      .then(({ earned }) => setPatchMap(Object.fromEntries(earned.map((pt) => [pt.routeId, pt]))))
      .catch(() => {});
    registerPushToken(); // APNs (0024) — 러너는 푸시가 곧 수입 (요청 도착 알림)
    fetchMyRunnerStatus().then(setRs).catch((e) => console.warn('[rhome] status:', e?.message ?? e));
  }, []));

  // 온라인 토글 — 실저장 (오프라인이면 추천·동네 러너 셸프에서 빠짐). 빕 위 스위치가 이 상태를 쓴다.
  const toggleOnline = () => {
    const next = !rs.online;
    setRs((v) => ({ ...v, online: next }));
    setRunnerOnline(next).catch((e) => {
      setRs((v) => ({ ...v, online: !next }));
      console.warn('[rhome] online:', e?.message ?? e);
    });
  };

  // 요일 탭 = 즉시 열기/닫기 (저장 버튼 없음 — 충동적 슬롯 오픈은 홈에서 바로)
  const toggleDay = (wd: number) => {
    if (!avail) return;
    const has = avail.some((r) => r.weekday === wd);
    const prev = avail;
    const next = has
      ? avail.filter((r) => r.weekday !== wd)
      : [...avail, { weekday: wd, startMin: 360, endMin: 1320 }];
    setAvail(next);
    saveMyAvailability(next).catch((e) => {
      setAvail(prev);
      console.warn('[rhome] avail save:', e?.message ?? e);
    });
  };

  const current = jobs.find((j) => ['runner_enroute', 'picked_up', 'active'].includes(j.rawStatus))
    ?? jobs.find((j) => j.rawStatus === 'confirmed');
  const upcoming = jobs.filter((j) => j.status === 'confirmed' && j.bookingId !== current?.bookingId).slice(0, 3);
  const past = jobs.filter((j) => j.status === 'completed').slice(0, 3);

  const openJob = (j: RunnerJob) => {
    runnerJob.bookingId = j.bookingId;
    router.push(j.rawStatus === 'active' ? '/runner/run' : '/runner/meetup');
  };

  // 드랍 트레일 — 실카운트 (runners.total_runs, settle-run이 증가시키는 값)
  const cycle5 = rs.totalRuns % 5;
  const remaining5 = 5 - cycle5;
  const cycle10 = rs.totalRuns % 10;

  const tierLabel = TIER_LABEL[rs.tier] ?? '러너';
  const avg = stats.runs > 0 ? Math.round(stats.net / stats.runs) : 0;

  // when 문자열 파싱 — 마지막 토큰 = 시간, 앞 = 요일/날짜 (소스 다음예약 파싱과 동일)
  const parseWhen = (w: string) => {
    const i = w.lastIndexOf(' ');
    return i < 0 ? { wd: '', wt: w } : { wd: w.slice(0, i), wt: w.slice(i + 1) };
  };

  // 오늘의 루트 — 진행 중 + 다음 예약을 정차역 타임라인으로 (모든 job 데이터·openJob 보존)
  const routeStops: { job: RunnerJob; kind: 'on' | 'next' }[] = [
    ...(current ? [{ job: current, kind: 'on' as const }] : []),
    ...upcoming.map((j) => ({ job: j, kind: 'next' as const })),
  ];

  return (
    <View style={{ flex: 1, backgroundColor: lilac.bg }}>
      {/* ————— 프로스트 상단 크롬 — 알림 벨 보존 (/alerts) ————— */}
      <View style={styles.top}>
        <Row style={{ alignItems: 'center', gap: 9 }}>
          <View style={styles.brandmark}><Text style={styles.brandmarkGlyph}>다</Text></View>
          <Text style={styles.crumb}>RUNNER</Text>
        </Row>
        <Pressable onPress={() => router.push('/alerts')} style={styles.bell} accessibilityLabel="알림">
          <Text style={{ fontSize: 20, color: lilac.head }}>🔔</Text>
        </Pressable>
      </View>

      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 14, paddingTop: 14, paddingBottom: 32 }}>

        {/* ————— 마스트헤드 · ① HERO 레이스 빕 (온라인 토글이 빕 위에) ————— */}
        <Row style={styles.kicker}>
          <Text style={styles.kickerTxt}>DAENGRUN RUNNER</Text>
          <View style={styles.rule} />
          <Text style={styles.kickerTxt}>{tierLabel}</Text>
        </Row>

        <View style={styles.bib}>
          <HoloEdge />
          <View style={styles.bibInner} pointerEvents="none" />
          <View style={[styles.pin, { top: 12, left: 12 }]} />
          <View style={[styles.pin, { top: 12, right: 12 }]} />
          <View style={[styles.pin, { bottom: 68, left: 12 }]} />
          <View style={[styles.pin, { bottom: 68, right: 12 }]} />

          <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start', paddingHorizontal: 22, paddingTop: 20, gap: 12 }}>
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text style={styles.bibOrg}>DAENGRUN · {tierLabel}</Text>
              <Text style={[styles.bibName, df]} numberOfLines={1}>
                {name ?? '러너'}<Text style={styles.bibNameEm}> 러너</Text>
              </Text>
            </View>
            {/* 온라인 토글 — 러너의 유일한 스위치, 빕 위에 산다. 같은 rs.online/toggleOnline 상태 */}
            <Pressable onPress={toggleOnline} style={{ alignItems: 'flex-end', gap: 6 }} accessibilityRole="switch" accessibilityState={{ checked: rs.online }}>
              <View style={[styles.swTrack, rs.online ? styles.swTrackOn : styles.swTrackOff]}>
                <View style={styles.swKnob} />
              </View>
              <Text style={[styles.swLabel, { color: rs.online ? CORAL_INK : lilac.dim }]}>
                {rs.online ? '온라인' : '오프라인'}
              </Text>
            </Pressable>
          </Row>

          {/* 빕 바디 — 대형숫자 열은 고정폭(bibNoCol)으로 경계, gap 18 + 좌측보더로 사이드 스탯과 완전 분리 (오버랩 FIX #1) */}
          <Row style={{ alignItems: 'flex-end', gap: 18, paddingHorizontal: 22, paddingTop: 14 }}>
            <View style={styles.bibNoCol}>
              <Text style={[styles.bibNo, nf]} numberOfLines={1}>{String(stats.runs).padStart(2, '0')}</Text>
              <Text style={styles.bibNoCap}>이번 주 완료 러닝</Text>
            </View>
            <View style={styles.bibSide}>
              <Row style={styles.bsRow}>
                <Text style={styles.bsK}>TOTAL</Text>
                <Text style={styles.bsV}><Text style={[styles.bsVNum, nf]}>{rs.totalRuns}</Text>회</Text>
              </Row>
              <Row style={[styles.bsRow, styles.bsRowTop]}>
                <Text style={styles.bsK}>TIER</Text>
                <Text style={styles.bsV}>{tierLabel}</Text>
              </Row>
              <Row style={[styles.bsRow, styles.bsRowTop]}>
                <Text style={styles.bsK}>DISTANCE</Text>
                <Text style={styles.bsV}><Text style={[styles.bsVNum, nf]}>{rs.totalKm}</Text>km</Text>
              </Row>
            </View>
          </Row>

          <Row style={styles.bibFoot}>
            <Barcode />
            <Text style={styles.bibFootTxt}>DAENGRUN · RUNNER</Text>
          </Row>
        </View>

        {/* ————— ② EARNINGS: 정산 장부 — 빕 바로 아래, 실 정산 필드 바인딩 · 점선 리더 ————— */}
        <View style={[styles.card, { marginTop: 16, padding: 6 }]}>
          <View style={styles.ledgerIn}>
            <HoloEdge />
            <Row style={{ justifyContent: 'space-between', alignItems: 'center', marginTop: 8 }}>
              <Row style={{ alignItems: 'center', gap: 8 }}>
                <View style={styles.lGlyph}><Text style={{ color: '#fff', fontSize: 13, fontWeight: '700' }}>₩</Text></View>
                <Text style={styles.lBrand}>EARNINGS LEDGER</Text>
              </Row>
              <View style={styles.monoTagV}><Text style={styles.monoTagVTxt}>THIS WEEK</Text></View>
            </Row>

            {/* 정산 히어로 — ₩와 금액은 baseline 정렬 + gap 10으로 절대 겹치지 않음 (오버랩 FIX #2) */}
            <Row style={{ alignItems: 'baseline', gap: 10, marginTop: 14 }}>
              <Text style={[styles.won, nf]}>₩</Text>
              <Text style={[styles.lBig, nf]} numberOfLines={1}>{stats.net.toLocaleString()}</Text>
            </Row>
            <Text style={styles.lCap}>이번 주 실수령 예정 금액 · 수수료 차감 후 기준</Text>

            <View style={{ marginTop: 14, borderTopWidth: 1, borderTopColor: lilac.hair }}>
              <LedgerRow label="완료 러닝" sub="THIS WEEK" value={String(stats.runs)} unit="회" nf={nf} />
              <LedgerRow label="총 거리" sub="DISTANCE" value={String(stats.km)} unit="km" nf={nf} />
              <LedgerRow label="회당 평균" sub="AVG / RUN" value={avg.toLocaleString()} unit="원" nf={nf} total />
            </View>

            <Row style={styles.lFoot}>
              <Text style={styles.lFootTxt}>매주 정산 · 수익 상세에서 입금 내역 확인</Text>
              <Pressable onPress={() => router.push('/runner/earnings')}>
                <Text style={styles.lFootLink}>수익 상세 ›</Text>
              </Pressable>
            </Row>
          </View>
        </View>

        {/* ————— ③ CLUB ENGINE — 히어로 인접 승격 (빕·장부 다음, 운영 피드보다 위). 클럽+호스트 로직은 컴포넌트가 보유 ————— */}
        <CapHead title="하이클럽" />
        <View style={{ marginTop: 10 }}>
          <RunnerClubCard />
        </View>

        {/* ————— 진행 중 작업 (관제탑의 심장) — 코랄 좌측 엣지 ————— */}
        {current && (
          <>
            <CapHead title="진행 중" />
            <Pressable onPress={() => openJob(current)} style={styles.now}>
              <View style={styles.nowEdge} />
              <Row style={{ justifyContent: 'space-between', alignItems: 'center' }}>
                <Row style={{ alignItems: 'center', gap: 8 }}>
                  <View style={{ width: 20, height: 20, alignItems: 'center', justifyContent: 'center' }}>
                    <PulseRings color={lilac.coral} size={20} />
                    <View style={{ width: 10, height: 10, borderRadius: 5, backgroundColor: lilac.coral }} />
                  </View>
                  <Text style={{ fontSize: 19, fontWeight: '800', color: STAGE[current.rawStatus]?.color ?? CORAL_INK }}>
                    {STAGE[current.rawStatus]?.label ?? current.rawStatus}
                  </Text>
                </Row>
                <Text style={styles.nowWhen}>{current.when}</Text>
              </Row>
              <Text style={styles.nowTitle}>{current.dogName} · {current.km}km 러닝</Text>
              <Text style={styles.nowSub}>
                예상 수익 <Text style={{ fontWeight: '700', color: lilac.text }}>+{current.payout.toLocaleString()}원</Text>
              </Text>
              <Row style={{ gap: 8, marginTop: 14 }}>
                <View style={[styles.btnCoral, { flex: 1.5 }]}>
                  <Text style={styles.btnCoralTxt}>{STAGE[current.rawStatus]?.action ?? '이어서 진행 ›'}</Text>
                </View>
                {(current.rawStatus === 'confirmed' || current.rawStatus === 'runner_enroute') && (
                  <Pressable onPress={(e) => { e.stopPropagation(); openNaverRoute(); }} style={[styles.btnQuiet, { flex: 1 }]}>
                    <Text style={styles.btnQuietTxt}>➤ 픽업 길찾기</Text>
                  </Pressable>
                )}
              </Row>
            </Pressable>
          </>
        )}

        {/* ————— ①(01) QUEUE: 오늘 맨 앞 = 보딩패스 티켓 · 나머지 = 스텁 행. 수락/거절 = 소스 요청함 핸들러 ————— */}
        <SectionRule no="01" title="요청 대기열" link={`요청함 · ${inbox.length}건 ›`} onPress={() => router.push('/runner/requests')} />

        {inbox.length > 0 ? (
          <>
            {/* 오늘 맨 앞 예약 = 보딩패스 티켓 전문 (inbox[0]) */}
            <View style={styles.ticket}>
              <View style={styles.tMain}>
                <HoloEdge />
                <Row style={{ justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 15, paddingTop: 14, gap: 8 }}>
                  <Row style={{ alignItems: 'center', gap: 8 }}>
                    <View style={styles.tGlyph}><Text style={{ color: '#fff', fontSize: 13 }}>✈</Text></View>
                    <Text style={styles.tBrand}>TODAY · FRONT REQUEST</Text>
                  </Row>
                  {inbox[0].directed && (
                    <View style={styles.monoTagStar}><Text style={styles.monoTagStarTxt}>★ 나를 지명</Text></View>
                  )}
                </Row>
                <View style={{ paddingHorizontal: 15, paddingTop: 12, paddingBottom: 14 }}>
                  <Row style={{ alignItems: 'baseline', gap: 8 }}>
                    <Text style={[styles.tBig, nf]}>{inbox[0].when}</Text>
                  </Row>
                  <Row style={{ alignItems: 'center', gap: 8, marginTop: 10 }}>
                    <View style={{ width: 11, height: 13, borderRadius: 5, backgroundColor: lilac.coral }} />
                    <Text style={styles.tWhere}>{inbox[0].dogName}</Text>
                    <Text style={styles.tWhereSub}>· 지명 요청 픽업</Text>
                  </Row>
                  <Row style={{ marginTop: 12, borderTopWidth: 1, borderTopColor: lilac.hair2, paddingTop: 12 }}>
                    <View style={{ flex: 1 }}>
                      <Text style={styles.factK}>COURSE</Text>
                      <Text style={styles.factV}><Text style={[styles.factVNum, nf]}>{inbox[0].km}</Text><Text style={styles.factVUnit}> km</Text></Text>
                    </View>
                    <View style={styles.factDiv}>
                      <Text style={styles.factK}>정산</Text>
                      <Text style={styles.factV}><Text style={[styles.factVNum, nf]}>{inbox[0].payout.toLocaleString()}</Text><Text style={styles.factVUnit}> 원</Text></Text>
                    </View>
                  </Row>
                </View>
              </View>

              {/* 퍼포레이션 + 사이드 노치 */}
              <View style={styles.perfWrap}>
                <View style={styles.perf} />
                <View style={[styles.perfNotch, { left: -9 }]} />
                <View style={[styles.perfNotch, { right: -9 }]} />
              </View>

              <View style={styles.tStub}>
                <Row style={{ gap: 8 }}>
                  <Pressable onPress={() => router.push('/runner/requests')} style={[styles.door, styles.doorCoral]}>
                    <Text style={[styles.doorName, { color: '#fff' }]}>수락</Text>
                    <Text style={[styles.doorSub, { color: '#fff' }]}>
                      <Text style={[styles.doorSubNum, nf]}>{inbox[0].payout.toLocaleString()}</Text>원 · 요청함에서 응답
                    </Text>
                  </Pressable>
                  <Pressable onPress={() => router.push('/runner/requests')} style={[styles.door, styles.doorQuiet]}>
                    <Text style={[styles.doorName, { color: lilac.head }]}>거절</Text>
                    <Text style={[styles.doorSub, { color: lilac.dim }]}>다른 러너에게 넘겨요</Text>
                  </Pressable>
                </Row>
                <Row style={{ justifyContent: 'space-between', alignItems: 'center', marginTop: 12 }}>
                  <Barcode width={150} />
                  <Text style={styles.bibFootTxt}>REQ · FRONT</Text>
                </Row>
              </View>
            </View>

            {/* 나머지 요청 = 스텁 행 (퍼포 스텁 · 장부 행) */}
            <View style={{ gap: 11, marginTop: 11 }}>
              {inbox.slice(1).map((rq, i) => (
                <View key={i} style={styles.stub}>
                  <HoloEdge radius />
                  <View style={{ flex: 1, minWidth: 0, paddingHorizontal: 14, paddingTop: 15, paddingBottom: 13 }}>
                    <Row style={{ alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
                      <Text style={styles.stubNm}>{rq.dogName}</Text>
                      <Text style={[styles.stubKm, nf]}>{rq.km}<Text style={styles.stubKmUnit}>KM</Text></Text>
                      {rq.directed && <View style={styles.monoTagStar}><Text style={styles.monoTagStarTxt}>★ 나를 지명</Text></View>}
                    </Row>
                    <Row style={{ alignItems: 'center', gap: 6, marginTop: 7 }}>
                      <Text style={styles.stubWhen}>{rq.when}</Text>
                    </Row>
                  </View>
                  <View style={styles.stubAct}>
                    <View style={[styles.stubNotch, { top: -7 }]} />
                    <View style={[styles.stubNotch, { bottom: -7 }]} />
                    <View style={{ alignItems: 'center' }}>
                      <Text style={[styles.stubFare, nf]}>{rq.payout.toLocaleString()}</Text>
                      <Text style={styles.stubFareCap}>KRW 실수령</Text>
                    </View>
                    <Pressable onPress={() => router.push('/runner/requests')} style={styles.accept}>
                      <Text style={styles.acceptTxt}>수락</Text>
                    </Pressable>
                  </View>
                </View>
              ))}

              <Pressable onPress={() => router.push('/runner/requests')} style={styles.stubMore}>
                <Text style={styles.stubMoreTxt}>비어 있으면 조용한 날 — 요청이 오는 대로 맨 앞에 붙어요</Text>
                <Text style={styles.stubMoreLink}>모두 보기 ›</Text>
              </Pressable>
            </View>
          </>
        ) : (
          <View style={styles.emptyInbox}>
            <Text style={{ fontSize: 18, color: lilac.dim, textAlign: 'center', lineHeight: 25 }}>
              {rs.online ? '지금은 새 요청이 없어요 — 오는 대로 여기에 떠요' : '오프라인 상태 — 켜야 요청을 받아요'}
            </Text>
          </View>
        )}

        {/* ————— ②(02) 오늘의 루트 — 정차역 타임라인 (진행 중 + 다음 예약) ————— */}
        {routeStops.length > 0 && (
          <>
            <SectionRule no="02" title="오늘의 루트" link="캘린더 ›" onPress={() => router.push('/runner/calendar')} />
            <View style={styles.card}>
              <View style={{ marginTop: 2 }}>
                {routeStops.map((st, i) => {
                  const { wd, wt } = parseWhen(st.job.when);
                  const on = st.kind === 'on';
                  return (
                    <Pressable
                      key={st.job.bookingId}
                      onPress={() => openJob(st.job)}
                      style={[styles.stop, i > 0 && { borderTopWidth: 1, borderTopColor: lilac.hair2 }]}
                    >
                      <View style={[styles.stopPt, on && styles.stopPtOn]}>
                        {on && <View style={{ width: 8, height: 8, borderRadius: 4, backgroundColor: lilac.coral }} />}
                      </View>
                      <View style={{ width: 62 }}>
                        <Text style={[styles.stopTm, nf]}>{wt}</Text>
                        <Text style={styles.stopTmSub}>{on ? '지금' : wd || '예정'}</Text>
                      </View>
                      <View style={{ flex: 1, minWidth: 0 }}>
                        <Text style={styles.stopInfoB}>{st.job.dogName} · {st.job.km}km</Text>
                        <Text style={styles.stopInfoS}>{on ? '픽업 대기' : '지명 요청 · 예정'}</Text>
                      </View>
                      <Text style={[styles.stopPay, nf]}>+{st.job.payout.toLocaleString()}</Text>
                    </Pressable>
                  );
                })}
              </View>
            </View>
          </>
        )}

        {/* ————— ③(03) 리워드 — 티어 사다리 + 보급 드랍 트레일 (실카운트) ————— */}
        <SectionRule no="03" title="리워드" link="리워드 센터 ›" onPress={() => router.push('/runner/rewards')} />
        <Pressable onPress={() => router.push('/runner/rewards')} style={styles.card}>
          {(() => {
            // v1 승급 기준: 베테랑 30회(수수료 18%), 마스터 100회(15%) — 심사 도입 전 잠정
            const t = rs.tier === 'veteran'
              ? { next: '마스터', at: 100, fee: '15%' }
              : rs.tier === 'master'
                ? null
                : { next: '베테랑', at: 30, fee: '18%' };
            if (!t) {
              return <Text style={{ fontSize: 21, fontWeight: '800', color: lilac.head }}>🏅 마스터 러너 — 최저 수수료 15%</Text>;
            }
            const left = Math.max(t.at - rs.totalRuns, 0);
            const pct = Math.min(rs.totalRuns / t.at, 1);
            return (
              <>
                <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
                  <Text style={{ fontSize: 21, fontWeight: '700', color: lilac.head }}>
                    {t.next}까지 러닝 <Text style={[{ fontSize: 24, color: CORAL_INK }, nf]}>{left}</Text>회
                  </Text>
                  <Text style={[styles.fee, nf]}>수수료 <Text style={{ color: lilac.dim, textDecorationLine: 'line-through' }}>20%</Text> → <Text style={{ color: lilac.voltDeep }}>{t.fee}</Text></Text>
                </Row>
                <Row style={{ alignItems: 'center', marginTop: 13, gap: 0 }}>
                  {[0, 1, 2, 3, 4].map((i) => {
                    const segFill = Math.max(0, Math.min(1, pct * 5 - i));
                    return (
                      <View key={i} style={[styles.rung, i === 0 && styles.rungL, i === 4 && styles.rungR]}>
                        {segFill > 0 && <View style={[styles.rungFill, { width: `${segFill * 100}%` }, i === 0 && styles.rungL, i === 4 && segFill >= 1 && styles.rungR]} />}
                      </View>
                    );
                  })}
                </Row>
                <Text style={{ fontSize: 16, lineHeight: 24, color: lilac.dim, marginTop: 10 }}>
                  같은 수익 기준 정산액이 늘어나요 · 승급 기준은 파일럿 중 조정될 수 있어요
                </Text>
              </>
            );
          })()}

          <View style={{ height: 1, backgroundColor: lilac.hair2, marginTop: 13, marginBottom: 12 }} />

          {/* 보급 드랍 트레일 — 지그재그 체크포인트 (i<cycle5 지남=accent, i===cycle5 다음=accent 링, 끝=보급 상자) */}
          <Row style={{ justifyContent: 'space-between', alignItems: 'center' }}>
            <Text style={{ fontSize: 20, fontWeight: '700', color: lilac.head }}>
              <Text style={{ color: lilac.gold }}>▣ </Text>보급 드랍 트레일
            </Text>
            <Text style={styles.trailCnt}>누적 {rs.totalRuns}회 ›</Text>
          </Row>
          <Row style={{ alignItems: 'center', height: 72, marginTop: 8 }}>
            {[0, 1, 2, 3, 4].map((i) => (
              <Row key={i} style={{ flex: 1, alignItems: 'center' }}>
                <View style={{
                  transform: [{ translateY: i % 2 === 0 ? 16 : -16 }, { rotate: '45deg' }],
                  width: 22, height: 22, borderRadius: 5,
                  backgroundColor: i < cycle5 ? lilac.accent : lilac.card,
                  borderWidth: 2,
                  borderColor: i < cycle5 ? lilac.accentDeep : i === cycle5 ? lilac.accent : lilac.hair,
                  shadowColor: lilac.accent, shadowOpacity: i < cycle5 ? 0.3 : 0,
                  shadowRadius: 5, shadowOffset: { width: 0, height: 2 },
                }} />
                <View style={{
                  flex: 1, height: 2, borderRadius: 2, marginHorizontal: 2,
                  backgroundColor: i < cycle5 ? '#C9BEF7' : lilac.hair,
                  transform: [{ rotate: i % 2 === 0 ? '-13deg' : '13deg' }],
                }} />
              </Row>
            ))}
            <View style={{ transform: [{ translateY: 16 }], width: 36, height: 36, alignItems: 'center', justifyContent: 'center' }}>
              {cycle5 === 0 && rs.totalRuns > 0 && <PulseRings color={lilac.accent} size={36} />}
              <View style={{
                width: 36, height: 36, borderRadius: 9, backgroundColor: lilac.amberSoft,
                alignItems: 'center', justifyContent: 'center',
                borderWidth: 2, borderColor: cycle5 === 0 && rs.totalRuns > 0 ? lilac.accent : lilac.amberEdge,
              }}>
                <Text style={{ fontSize: 18, color: lilac.amber }}>▣</Text>
              </View>
            </View>
          </Row>
          <Text style={{ fontSize: 19, fontWeight: '700', color: lilac.head, marginTop: 4 }}>
            {rs.totalRuns === 0
              ? '첫 러닝을 완료하면 트레일이 시작돼요'
              : cycle5 === 0
                ? '보급 드랍 도착! 리워드 센터에서 열어보세요'
                : `${remaining5}번 더 달리면 보급 드랍!`}
          </Text>
          <Row style={{ alignItems: 'center', gap: 8, marginTop: 12, paddingTop: 12, borderTopWidth: 1, borderTopColor: lilac.hair2 }}>
            <Text style={styles.flagLb}>픽 드랍</Text>
            <View style={styles.flagTrack}>
              <View style={[styles.flagFill, { width: `${(cycle10 / 10) * 100}%` }]} />
            </View>
            <Text style={[styles.flagCnt, nf]}>{cycle10}/10</Text>
          </Row>
        </Pressable>

        {/* ————— ④(04) 러닝 가능 시간 — 요일 탭 (온라인 토글은 빕 위) ————— */}
        <SectionRule no="04" title="러닝 가능 시간" link="시간 조정 ›" onPress={() => router.push('/runner/availability')} />
        <View style={styles.card}>
          {!avail ? (
            <Text style={{ fontSize: 20, color: lilac.dim }}>불러오는 중...</Text>
          ) : (
            <>
              <Row style={{ gap: 5 }}>
                {DAY_ORDER.map((wd) => {
                  const rule = avail.find((r) => r.weekday === wd);
                  const on = !!rule;
                  return (
                    <Pressable key={wd} onPress={() => toggleDay(wd)} style={[styles.day, on && styles.dayOn]}>
                      <Text style={[styles.dayD, { color: on ? lilac.head : lilac.dim }]}>{DAY_NAME[wd]}</Text>
                      <Text style={[styles.dayH, { color: on ? lilac.accent : lilac.dim }]}>
                        {rule ? `${hh(rule.startMin)}–${hh(rule.endMin)}` : '쉼'}
                      </Text>
                    </Pressable>
                  );
                })}
              </Row>
              <Text style={{ fontSize: 16, lineHeight: 24, color: lilac.dim, marginTop: 12 }}>
                요일을 탭하면 바로 열리고 닫혀요 (기본 06–22시) · 보호자 예약 화면에 즉시 반영
              </Text>
            </>
          )}
        </View>

        {/* ————— ⑤(05) 최근 완료 — 패치 + 인증샷 ————— */}
        {past.length > 0 && (
          <>
            <SectionRule no="05" title="최근 완료" link="수익 상세 ›" onPress={() => router.push('/runner/earnings')} />
            <View style={[styles.card, { padding: 0, overflow: 'hidden' }]}>
              {past.map((j, i) => (
                <Row key={j.bookingId} style={[styles.drow, i > 0 && { borderTopWidth: 1, borderTopColor: lilac.hair2 }]}>
                  <View style={{ alignSelf: 'center' }}>
                    {j.routeId && patchMap[j.routeId] ? (
                      <Pressable onPress={() => router.push('/cards')}>
                        <PatchBadge km={patchMap[j.routeId].km} grade={patchMap[j.routeId].grade} size={44} />
                      </Pressable>
                    ) : (
                      <View style={styles.patchFallback}><Text style={[styles.patchFallbackTxt, nf]}>{j.km}K</Text></View>
                    )}
                  </View>
                  <View style={{ flex: 1, minWidth: 0 }}>
                    <Text style={styles.drowB}>{j.dogName} · {j.km}km · 완료</Text>
                    <Text style={styles.drowS}>{j.when} · <Text style={{ color: lilac.voltDeep, fontWeight: '700' }}>✓ 정산 완료</Text></Text>
                  </View>
                  <View style={{ alignItems: 'flex-end', gap: 6 }}>
                    <Text style={[styles.drowPay, nf]}>+{j.payout.toLocaleString()}</Text>
                    <Pressable onPress={() => router.push(`/shot/${j.bookingId}`)} style={styles.shot}>
                      <Text style={styles.shotTxt}>📸 인증샷</Text>
                    </Pressable>
                  </View>
                </Row>
              ))}
            </View>
          </>
        )}

        {/* ————— ⑥(06) 동네 코스 ————— */}
        <View style={{ marginTop: 8 }}>
          <CourseStrip title="동네 코스" />
        </View>

        {/* ————— 퀵 링크 ————— */}
        <Row style={{ flexWrap: 'wrap', gap: 8, marginTop: 18 }}>
          <Pressable onPress={() => router.push('/leaderboard')} style={styles.qlink}>
            <Text style={styles.qlinkB}>🏆 랭킹</Text><Text style={styles.qlinkChev}>›</Text>
          </Pressable>
          <Pressable onPress={() => router.push('/community')} style={styles.qlink}>
            <Text style={styles.qlinkB}>커뮤니티</Text><Text style={styles.qlinkChev}>›</Text>
          </Pressable>
          <Pressable onPress={() => router.push('/safety')} style={styles.qlink}>
            <Text style={styles.qlinkB}>안심 센터</Text><Text style={styles.qlinkChev}>›</Text>
          </Pressable>
          <Pressable onPress={() => router.push('/cards')} style={styles.qlink}>
            <Text style={styles.qlinkB}>마이 카드</Text><Text style={styles.qlinkChev}>›</Text>
          </Pressable>
        </Row>

        {/* ————— 푸터 ————— */}
        <Row style={styles.foot}>
          <Text style={styles.footTxt}>누적 <Text style={{ color: lilac.text }}>{rs.totalRuns}</Text>회</Text>
          <View style={styles.footDot} />
          <Text style={styles.footTxt}>{tierLabel}</Text>
          <View style={styles.footDot} />
          <Text style={styles.footTxt}>{rs.online ? '온라인' : '오프라인'}</Text>
        </Row>
      </ScrollView>

      <BottomNav />
    </View>
  );
}

const styles = StyleSheet.create({
  // 상단 크롬
  top: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingTop: 48, paddingBottom: 13, paddingHorizontal: 14,
    backgroundColor: lilac.glass, borderBottomWidth: 1, borderBottomColor: lilac.glassEdge,
  },
  brandmark: {
    width: 30, height: 30, borderRadius: 8, backgroundColor: HOLO[0], alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: 'rgba(34,30,61,0.16)',
  },
  brandmarkGlyph: { fontSize: 16, color: lilac.head, lineHeight: 20 },
  crumb: { fontSize: 14, letterSpacing: 3, color: lilac.dim, fontWeight: '600' },
  bell: {
    width: 40, height: 40, borderRadius: 9, borderWidth: 1, borderColor: lilac.hair,
    backgroundColor: lilac.card, alignItems: 'center', justifyContent: 'center',
  },

  // 공통 카드 + 룰
  card: {
    backgroundColor: lilac.card, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: lilac.hair,
    padding: 16, marginTop: 14,
    shadowColor: '#1C1837', shadowOpacity: 0.08, shadowRadius: 14, shadowOffset: { width: 0, height: 6 }, elevation: 2,
  },
  rule: { flex: 1, height: 1, backgroundColor: lilac.hair },
  holo: { flexDirection: 'row', height: 3, position: 'absolute', top: 0, left: 0, right: 0, zIndex: 3 },

  // 마스트헤드
  kicker: { alignItems: 'center', gap: 8, marginBottom: 14, marginTop: 2 },
  kickerTxt: { fontSize: 14, letterSpacing: 3, color: lilac.dim, fontWeight: '600' },

  srNo: { fontSize: 15, letterSpacing: 2, color: lilac.accent, fontWeight: '700' },
  srTitle: { fontSize: 21, fontWeight: '700', color: lilac.head },
  srLink: { fontSize: 16, color: lilac.dim, fontWeight: '500' },

  // ① 빕
  bib: {
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.card,
    overflow: 'hidden', paddingBottom: 0,
    shadowColor: '#1C1837', shadowOpacity: 0.09, shadowRadius: 14, shadowOffset: { width: 0, height: 6 }, elevation: 3,
  },
  bibInner: { position: 'absolute', top: 4, left: 4, right: 4, bottom: 4, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.inner },
  pin: {
    position: 'absolute', width: 8, height: 8, borderRadius: 4, backgroundColor: lilac.inset,
    borderWidth: 1, borderColor: lilac.hair, zIndex: 2,
  },
  bibOrg: { fontSize: 13, letterSpacing: 2.4, color: lilac.dim, fontWeight: '600', marginBottom: 7 },
  bibName: { fontSize: 34, color: lilac.head, lineHeight: 38 },
  bibNameEm: { fontSize: 19, color: lilac.dim, fontWeight: '600' },
  swTrack: { width: 54, height: 31, borderRadius: 99, padding: 4, flexDirection: 'row' },
  swTrackOn: {
    backgroundColor: lilac.coral, justifyContent: 'flex-end',
    shadowColor: lilac.coral, shadowOpacity: 0.32, shadowRadius: 9, shadowOffset: { width: 0, height: 3 },
  },
  swTrackOff: { backgroundColor: lilac.inset, justifyContent: 'flex-start', borderWidth: 1, borderColor: lilac.hair },
  swKnob: { width: 23, height: 23, borderRadius: 12, backgroundColor: '#fff', shadowColor: '#1C1837', shadowOpacity: 0.3, shadowRadius: 2, shadowOffset: { width: 0, height: 1 } },
  swLabel: { fontSize: 13, letterSpacing: 2, fontWeight: '700' },
  // 대형숫자 열 — 고정폭 130으로 경계 (2자리 "07" ~80px가 안에 완전히 들어감 · 사이드 스탯과 절대 충돌 안함)
  bibNoCol: { width: 130, flexShrink: 0 },
  bibNo: { fontSize: 80, color: lilac.head, lineHeight: 80, letterSpacing: -2, includeFontPadding: false },
  bibNoCap: { marginTop: 8, fontSize: 15, fontWeight: '600', color: lilac.text, lineHeight: 19 },
  bibSide: { flex: 1, minWidth: 0, borderLeftWidth: 1, borderLeftColor: lilac.hair2, paddingLeft: 16, paddingBottom: 3 },
  bsRow: { justifyContent: 'space-between', alignItems: 'baseline', gap: 8, paddingVertical: 8 },
  bsRowTop: { borderTopWidth: 1, borderTopColor: lilac.hair2 },
  bsK: { fontSize: 13, letterSpacing: 2, color: lilac.dim, fontWeight: '600' },
  bsV: { fontSize: 18, fontWeight: '600', color: lilac.head },
  bsVNum: { fontSize: 21, color: lilac.head },
  bibFoot: {
    marginTop: 16, borderTopWidth: 1.5, borderTopColor: '#DCD7F0', borderStyle: 'dashed',
    justifyContent: 'space-between', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 13, backgroundColor: lilac.card,
  },
  bibFootTxt: { fontSize: 14, letterSpacing: 2, color: lilac.dim, fontWeight: '500' },

  // ② 장부
  ledgerIn: { borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.inner, paddingHorizontal: 16, paddingTop: 14, paddingBottom: 14, overflow: 'hidden' },
  lGlyph: { width: 24, height: 24, borderRadius: 6, backgroundColor: lilac.accent, alignItems: 'center', justifyContent: 'center' },
  lBrand: { fontSize: 14, letterSpacing: 2.4, color: lilac.head, fontWeight: '700' },
  monoTagV: { borderWidth: 1, borderColor: '#DCD6F8', backgroundColor: '#F4F1FE', borderRadius: lilacRadius.tag, paddingHorizontal: 9, paddingVertical: 5 },
  monoTagVTxt: { fontSize: 13, letterSpacing: 1.6, color: lilac.accent, fontWeight: '600' },
  monoTagStar: { borderWidth: 1, borderColor: lilac.amberEdge, backgroundColor: lilac.amberSoft, borderRadius: lilacRadius.tag, paddingHorizontal: 9, paddingVertical: 5 },
  monoTagStarTxt: { fontSize: 13, letterSpacing: 1.4, color: lilac.amber, fontWeight: '700' },
  // ₩와 금액은 baseline 정렬 · won은 flexShrink 0로 자기 폭 확보, 금액은 numberOfLines 1 (오버랩 FIX #2)
  won: { fontSize: 28, color: CORAL_INK, lineHeight: 32, flexShrink: 0 },
  lBig: { fontSize: 50, color: lilac.head, lineHeight: 54, letterSpacing: 0.2, includeFontPadding: false, flexShrink: 1 },
  lCap: { marginTop: 9, fontSize: 16, color: lilac.dim, lineHeight: 24 },
  lr: { alignItems: 'baseline', gap: 10, paddingTop: 11, paddingBottom: 10, borderBottomWidth: 1, borderBottomColor: lilac.hair2 },
  lrLabel: { fontSize: 18, fontWeight: '600', color: lilac.head },
  lrSub: { fontSize: 12, letterSpacing: 1.6, color: lilac.dim, fontWeight: '500', marginTop: 2 },
  lead: { flex: 1, borderBottomWidth: 1, borderStyle: 'dotted', borderBottomColor: '#D5CFEC', transform: [{ translateY: -4 }] },
  lrVal: { fontSize: 16, fontWeight: '500', color: lilac.text },
  lrValNum: { fontSize: 23, color: lilac.head },
  lFoot: { justifyContent: 'space-between', alignItems: 'center', gap: 10, marginTop: 12, paddingTop: 12, borderTopWidth: 1, borderTopColor: lilac.hair2 },
  lFootTxt: { fontSize: 16, color: lilac.dim, flex: 1 },
  lFootLink: { fontSize: 17, fontWeight: '700', color: lilac.accent },

  // 진행 중
  now: {
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.card,
    overflow: 'hidden', paddingVertical: 15, paddingRight: 15, paddingLeft: 17, marginTop: 10,
    shadowColor: '#1C1837', shadowOpacity: 0.08, shadowRadius: 14, shadowOffset: { width: 0, height: 6 }, elevation: 2,
  },
  nowEdge: { position: 'absolute', left: 0, top: 0, bottom: 0, width: 4, backgroundColor: lilac.coral },
  nowWhen: { fontSize: 16, letterSpacing: 2, color: lilac.dim, fontWeight: '500' },
  nowTitle: { marginTop: 10, fontSize: 24, fontWeight: '700', color: lilac.head },
  nowSub: { marginTop: 5, fontSize: 17, color: lilac.dim },
  btnCoral: {
    borderRadius: lilacRadius.btn, alignItems: 'center', justifyContent: 'center', paddingVertical: 17, backgroundColor: CORAL_INK,
    borderWidth: 1, borderColor: CORAL_INK_DEEP,
    shadowColor: lilac.coral, shadowOpacity: 0.34, shadowRadius: 16, shadowOffset: { width: 0, height: 6 },
  },
  btnCoralTxt: { fontSize: 20, fontWeight: '700', color: '#fff' },
  btnQuiet: { borderRadius: lilacRadius.btn, alignItems: 'center', justifyContent: 'center', paddingVertical: 17, backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair },
  btnQuietTxt: { fontSize: 20, fontWeight: '700', color: lilac.head },

  // ① 티켓
  ticket: { marginTop: 11, shadowColor: '#1C1837', shadowOpacity: 0.1, shadowRadius: 12, shadowOffset: { width: 0, height: 6 }, elevation: 3 },
  tMain: { backgroundColor: lilac.card, borderTopLeftRadius: lilacRadius.card, borderTopRightRadius: lilacRadius.card, borderWidth: 1, borderBottomWidth: 0, borderColor: lilac.hair2, overflow: 'hidden' },
  tGlyph: { width: 24, height: 24, borderRadius: 6, backgroundColor: lilac.accent, alignItems: 'center', justifyContent: 'center' },
  tBrand: { fontSize: 15, letterSpacing: 2.4, color: lilac.head, fontWeight: '700' },
  tBig: { fontSize: 34, color: lilac.head, lineHeight: 38, includeFontPadding: false },
  tWhere: { fontSize: 22, fontWeight: '600', color: lilac.head },
  tWhereSub: { fontSize: 17, color: lilac.dim },
  factK: { fontSize: 14, letterSpacing: 2, color: lilac.dim, fontWeight: '600', marginBottom: 5 },
  factV: { fontSize: 20, fontWeight: '600', color: lilac.head },
  factVNum: { fontSize: 23, color: lilac.head },
  factVUnit: { fontSize: 16, fontWeight: '500', color: lilac.text },
  factDiv: { flex: 1, borderLeftWidth: 1, borderLeftColor: lilac.hair2, paddingLeft: 14 },
  perfWrap: { backgroundColor: lilac.card, borderLeftWidth: 1, borderRightWidth: 1, borderColor: lilac.hair2, position: 'relative' },
  perf: { borderTopWidth: 1.5, borderTopColor: '#DCD7F0', borderStyle: 'dashed' },
  perfNotch: { position: 'absolute', top: -9, width: 18, height: 18, borderRadius: 9, backgroundColor: lilac.bg, borderWidth: 1, borderColor: lilac.hair2 },
  tStub: { backgroundColor: lilac.card, borderBottomLeftRadius: lilacRadius.card, borderBottomRightRadius: lilacRadius.card, borderWidth: 1, borderTopWidth: 0, borderColor: lilac.hair2, paddingHorizontal: 15, paddingTop: 14, paddingBottom: 15 },
  door: { flex: 1, borderRadius: lilacRadius.btn, paddingVertical: 16, paddingHorizontal: 13, overflow: 'hidden' },
  doorCoral: { backgroundColor: CORAL_INK, borderWidth: 1, borderColor: CORAL_INK_DEEP, shadowColor: lilac.coral, shadowOpacity: 0.34, shadowRadius: 16, shadowOffset: { width: 0, height: 6 } },
  doorQuiet: { backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair },
  doorName: { fontSize: 24, fontWeight: '800' },
  doorSub: { marginTop: 6, fontSize: 15 },
  doorSubNum: { fontSize: 20 },

  // 스텁 행
  stub: { flexDirection: 'row', backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.card, overflow: 'hidden', shadowColor: '#1C1837', shadowOpacity: 0.08, shadowRadius: 14, shadowOffset: { width: 0, height: 6 }, elevation: 2 },
  stubNm: { fontSize: 22, fontWeight: '700', color: lilac.head },
  stubKm: { fontSize: 22, fontWeight: '600', color: lilac.head },
  stubKmUnit: { fontSize: 15, color: CORAL_INK, fontWeight: '600' },
  stubWhen: { fontSize: 18, color: lilac.dim, fontWeight: '500' },
  stubAct: { width: 134, borderLeftWidth: 1.4, borderStyle: 'dashed', borderLeftColor: '#DCD7F0', paddingVertical: 14, paddingHorizontal: 10, alignItems: 'center', justifyContent: 'center', gap: 9 },
  stubNotch: { position: 'absolute', left: -6.7, width: 13, height: 13, borderRadius: 7, backgroundColor: lilac.bg, borderWidth: 1, borderColor: lilac.hair2, zIndex: 3 },
  stubFare: { fontSize: 24, color: lilac.head, includeFontPadding: false },
  stubFareCap: { fontSize: 12, letterSpacing: 1.6, color: lilac.dim, fontWeight: '500', marginTop: 5 },
  accept: { width: '100%', borderRadius: lilacRadius.btn, paddingVertical: 13, alignItems: 'center', backgroundColor: CORAL_INK, borderWidth: 1, borderColor: CORAL_INK_DEEP },
  acceptTxt: { fontSize: 19, fontWeight: '700', color: '#fff' },
  stubMore: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: 10, borderWidth: 1, borderStyle: 'dashed', borderColor: lilac.hair, borderRadius: lilacRadius.card, paddingVertical: 15, paddingHorizontal: 14, backgroundColor: lilac.glass },
  stubMoreTxt: { fontSize: 16, color: lilac.text, flex: 1 },
  stubMoreLink: { fontSize: 16, fontWeight: '700', color: lilac.accent },
  emptyInbox: { marginTop: 11, backgroundColor: lilac.inset, borderRadius: lilacRadius.card, padding: 20, borderWidth: 1, borderColor: lilac.hair },

  // ② 루트
  stop: { flexDirection: 'row', alignItems: 'flex-start', gap: 13, paddingVertical: 11 },
  stopPt: { width: 18, height: 18, borderRadius: 9, marginTop: 3, backgroundColor: lilac.card, borderWidth: 1.5, borderColor: '#DCD6F8', alignItems: 'center', justifyContent: 'center' },
  stopPtOn: { borderColor: lilac.coral },
  stopTm: { fontSize: 22, fontWeight: '600', color: lilac.head },
  stopTmSub: { fontSize: 14, color: lilac.dim, fontWeight: '500', marginTop: 3 },
  stopInfoB: { fontSize: 20, fontWeight: '600', color: lilac.head },
  stopInfoS: { fontSize: 16, color: lilac.dim, marginTop: 3 },
  stopPay: { fontSize: 21, fontWeight: '600', color: lilac.head, marginTop: 2 },

  // ③ 리워드
  fee: { fontSize: 17, letterSpacing: 0.6, color: lilac.head, fontWeight: '600' },
  rung: { flex: 1, height: 8, backgroundColor: lilac.inset, borderWidth: 1, borderColor: lilac.hair, overflow: 'hidden' },
  rungL: { borderTopLeftRadius: 99, borderBottomLeftRadius: 99 },
  rungR: { borderTopRightRadius: 99, borderBottomRightRadius: 99 },
  rungFill: { height: '100%', backgroundColor: lilac.accent },
  trailCnt: { fontSize: 15, letterSpacing: 0.8, color: lilac.accent, fontWeight: '500' },
  flagLb: { fontSize: 14, letterSpacing: 2, color: lilac.dim, fontWeight: '600' },
  flagTrack: { flex: 1, height: 7, borderRadius: 99, backgroundColor: lilac.inset, overflow: 'hidden', borderWidth: 1, borderColor: lilac.hair },
  flagFill: { height: '100%', borderRadius: 99, backgroundColor: lilac.accent },
  flagCnt: { fontSize: 17, fontWeight: '600', color: lilac.head },

  // ④ 가능 시간
  day: { flex: 1, borderRadius: lilacRadius.inner, paddingVertical: 12, alignItems: 'center', backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair },
  dayOn: { backgroundColor: '#F4F1FE', borderColor: '#DCD6F8' },
  dayD: { fontSize: 21, fontWeight: '700', lineHeight: 23 },
  dayH: { fontSize: 13, letterSpacing: 0.4, fontWeight: '500', marginTop: 6 },

  // ⑤ 최근 완료
  drow: { alignItems: 'center', gap: 13, paddingHorizontal: 14, paddingVertical: 13 },
  patchFallback: { width: 44, height: 44, borderRadius: 22, backgroundColor: '#1C1837', alignItems: 'center', justifyContent: 'center' },
  patchFallbackTxt: { fontSize: 18, color: '#CFC4FF', fontWeight: '600' },
  drowB: { fontSize: 19, fontWeight: '600', color: lilac.head },
  drowS: { fontSize: 15, color: lilac.dim, marginTop: 3 },
  drowPay: { fontSize: 20, fontWeight: '600', color: lilac.text },
  shot: { borderWidth: 1, borderColor: lilac.hair, backgroundColor: lilac.card, borderRadius: lilacRadius.tag, paddingVertical: 6, paddingHorizontal: 9 },
  shotTxt: { fontSize: 14, fontWeight: '600', color: lilac.head },

  // 퀵 링크 + 푸터
  qlink: { flexBasis: '48%', flexGrow: 1, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: 8, backgroundColor: lilac.glass, borderWidth: 1, borderStyle: 'dashed', borderColor: lilac.hair, borderRadius: lilacRadius.card, paddingVertical: 15, paddingHorizontal: 14 },
  qlinkB: { fontSize: 18, fontWeight: '600', color: lilac.head },
  qlinkChev: { fontSize: 17, color: lilac.dim },
  foot: { alignItems: 'center', gap: 8, paddingTop: 14, marginTop: 16, borderTopWidth: 1, borderTopColor: lilac.hair },
  footTxt: { fontSize: 15, letterSpacing: 0.2, color: lilac.dim },
  footDot: { width: 3, height: 3, borderRadius: 1.5, backgroundColor: lilac.hair },
});
