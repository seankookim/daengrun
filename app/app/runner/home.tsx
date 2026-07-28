import { useDisplayFont } from '../../src/lib/displayFont';
import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { Card, Row, StatBlock, text } from '../../src/components/ui';
import {
  AvailRule, fetchMyAvailability, fetchMyName, fetchMyRunnerStatus, fetchRunnerInbox, fetchRunnerJobs,
  fetchRunnerWeekStats, MyRunnerStatus, OpenRequest, RunnerJob, RunnerWeekStats, saveMyAvailability, setRunnerOnline,
} from '../../src/lib/api';
import { runnerJob } from '../../src/store';
import { colors } from '../../src/theme';

// 러너 홈 — 정보 밀도 우선 (보호자 홈이 도파민이라면 여기는 관제탑).
// 진행 중 작업 + 단계, 지도 숏컷, 다음 예약, 드랍 트레일(실카운트), 최근 완료.

const FOREST = '#0F1D13';
const DAY_ORDER = [1, 2, 3, 4, 5, 6, 0]; // 월…일
const DAY_NAME = '일월화수목금토';
const hh = (m: number) => String(Math.floor(m / 60)).padStart(2, '0');

// 진행 단계 메타 — 서버 상태 → 러너가 지금 뭘 해야 하는지
const STAGE: Record<string, { label: string; action: string; color: string }> = {
  confirmed: { label: '픽업 대기', action: '픽업 이동 시작 ›', color: '#a97c12' },
  runner_enroute: { label: '픽업 이동 중', action: '인계 화면으로 ›', color: '#a97c12' },
  picked_up: { label: '인계 완료 · 시작 대기', action: '러닝 시작하기 ›', color: '#4a6d1f' },
  active: { label: '러닝 중 · LIVE', action: '러닝 화면으로 ›', color: '#d84a2f' },
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

export default function RunnerHome() {
  const df = useDisplayFont(); // 디스플레이 서체 — 화면 타이틀
  const [inbox, setInbox] = useState<OpenRequest[]>([]);
  const [name, setName] = useState<string | null>(null);
  const [stats, setStats] = useState<RunnerWeekStats>({ net: 0, runs: 0, km: 0 });
  const [jobs, setJobs] = useState<RunnerJob[]>([]);
  const [rs, setRs] = useState<MyRunnerStatus>({ totalRuns: 0, totalKm: 0, online: false, tier: 'certified' });
  const [avail, setAvail] = useState<AvailRule[] | null>(null);

  useFocusEffect(useCallback(() => {
    fetchMyAvailability().then(setAvail).catch((e) => console.warn('[rhome] avail:', e?.message ?? e));
    fetchRunnerInbox().then(setInbox).catch((e) => console.warn('[rhome] inbox:', e?.message ?? e));
    fetchMyName().then(setName).catch(() => {});
    fetchRunnerWeekStats().then(setStats).catch((e) => console.warn('[rhome] stats:', e?.message ?? e));
    fetchRunnerJobs().then(setJobs).catch((e) => console.warn('[rhome] jobs:', e?.message ?? e));
    fetchMyRunnerStatus().then(setRs).catch((e) => console.warn('[rhome] status:', e?.message ?? e));
  }, []));

  // 온라인 토글 — 실저장 (오프라인이면 추천·동네 러너 셸프에서 빠짐)
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

  return (
    <View style={{ flex: 1 }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16, paddingTop: 64, paddingBottom: 24 }}>
        <Row style={{ justifyContent: 'space-between' }}>
          <View>
            <Text style={text.dim}>러너 모드 · {rs.online ? '온라인' : '오프라인'}</Text>
            <Text style={[text.h1, { marginTop: 2 }, df]}>{name ?? '러너'} 러너</Text>
          </View>
          <Pressable
            onPress={toggleOnline}
            style={{
              width: 56, height: 32, borderRadius: 99, padding: 3,
              backgroundColor: rs.online ? colors.voltDeep : '#d8d4c4',
              alignItems: rs.online ? 'flex-end' : 'flex-start',
            }}
          >
            <View style={{ width: 26, height: 26, borderRadius: 13, backgroundColor: '#fff' }} />
          </Pressable>
        </Row>

        {/* ---------- 진행 중 작업 (관제탑의 심장) ---------- */}
        {current && (
          <Pressable onPress={() => openJob(current)} style={s.currentCard}>
            <Row style={{ justifyContent: 'space-between' }}>
              <View style={[s.stagePill, { backgroundColor: '#fff' }]}>
                <Text style={{ fontSize: 11.5, fontWeight: '900', color: STAGE[current.rawStatus]?.color ?? FOREST }}>
                  ● {STAGE[current.rawStatus]?.label ?? current.rawStatus}
                </Text>
              </View>
              <Text style={{ fontSize: 13, color: '#b8c4ae' }}>{current.when}</Text>
            </Row>
            <Text style={{ fontSize: 20.5, fontWeight: '900', color: '#fff', marginTop: 10 }}>
              {current.dogName} · {current.km}km 러닝
            </Text>
            <Text style={{ fontSize: 14, color: '#b8c4ae', marginTop: 3 }}>
              예상 수익 +{current.payout.toLocaleString()}원
            </Text>
            <Row style={{ gap: 8, marginTop: 12 }}>
              <View style={[s.currentBtn, { backgroundColor: colors.volt, flex: 1.4 }]}>
                <Text style={{ fontSize: 14.5, fontWeight: '900', color: FOREST }}>
                  {STAGE[current.rawStatus]?.action ?? '이어서 진행 ›'}
                </Text>
              </View>
              {(current.rawStatus === 'confirmed' || current.rawStatus === 'runner_enroute') && (
                <Pressable
                  onPress={(e) => { e.stopPropagation(); openNaverRoute(); }}
                  style={[s.currentBtn, { backgroundColor: '#1d3023', flex: 1 }]}
                >
                  <Text style={{ fontSize: 14, fontWeight: '800', color: '#fff' }}>➤ 픽업 길찾기</Text>
                </Pressable>
              )}
            </Row>
          </Pressable>
        )}

        {/* ---------- 주간 스탯 ---------- */}
        <Card dark style={{ marginTop: 12 }}>
          <Row style={{ justifyContent: 'space-around' }}>
            <StatBlock value={stats.net.toLocaleString()} label="이번 주 수익(원)" />
            <StatBlock value={String(stats.runs)} label="완료 러닝" />
            <StatBlock value={String(stats.km)} label="km" />
          </Row>
        </Card>

        {/* ---------- 러닝 가능 시간 — 홈에서 바로 열고 닫기 ---------- */}
        <View style={s.availCard}>
          <Row style={{ justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 15, fontWeight: '900', color: FOREST }}>러닝 가능 시간</Text>
            <Pressable onPress={() => router.push('/runner/availability')}>
              <Text style={{ fontSize: 13, fontWeight: '800', color: '#5a7a3c' }}>시간 조정 ›</Text>
            </Pressable>
          </Row>
          {!avail ? (
            <Text style={{ fontSize: 13, color: colors.dim, marginTop: 10 }}>불러오는 중...</Text>
          ) : (
            <>
              <Row style={{ gap: 6, marginTop: 12 }}>
                {DAY_ORDER.map((wd) => {
                  const rule = avail.find((r) => r.weekday === wd);
                  const on = !!rule;
                  return (
                    <Pressable key={wd} onPress={() => toggleDay(wd)} style={[s.availDay, on && s.availDayOn]}>
                      <Text style={{ fontSize: 17, fontWeight: '900', color: on ? FOREST : '#b3b3ab' }}>
                        {DAY_NAME[wd]}
                      </Text>
                      <Text style={{ fontSize: 10, fontWeight: '700', color: on ? '#4a6d1f' : '#c2c0b4', marginTop: 2 }}>
                        {rule ? `${hh(rule.startMin)}–${hh(rule.endMin)}` : '쉼'}
                      </Text>
                    </Pressable>
                  );
                })}
              </Row>
              <Text style={{ fontSize: 12, color: colors.dim, marginTop: 9 }}>
                요일을 탭하면 바로 열리고 닫혀요 (기본 06–22시) · 보호자 예약 화면에 즉시 반영
              </Text>
            </>
          )}
        </View>

        {/* ---------- 드랍 트레일 (실카운트) — 지그재그 체크포인트 (모던 목업) ---------- */}
        <Pressable onPress={() => router.push('/runner/rewards')} style={s.trailCard}>
          <View style={s.trailTab}>
            <Text style={{ fontSize: 12, fontWeight: '900', color: colors.volt }}>▣ 보급 드랍 트레일</Text>
          </View>
          <Text style={{ fontSize: 12.5, color: '#4a6d1f', textAlign: 'right' }}>누적 {rs.totalRuns}회 ›</Text>

          {/* 지그재그 다이아몬드 길 — i<cycle5 지남(볼트), i===cycle5 다음(화이트+볼트링), 끝 = 보급상자 */}
          <Row style={{ alignItems: 'center', marginTop: 16, height: 62 }}>
            {[0, 1, 2, 3, 4].map((i) => (
              <Row key={i} style={{ flex: 1, alignItems: 'center' }}>
                <View style={{
                  transform: [{ translateY: i % 2 === 0 ? 12 : -12 }, { rotate: '45deg' }],
                  width: 23, height: 23, borderRadius: 6,
                  backgroundColor: i < cycle5 ? '#a3d431' : '#ffffff',
                  borderWidth: 2,
                  borderColor: i < cycle5 ? '#7FA818' : i === cycle5 ? '#a3d431' : '#e4ecc9',
                  shadowColor: '#7FA818', shadowOpacity: i < cycle5 ? 0.35 : 0,
                  shadowRadius: 5, shadowOffset: { width: 0, height: 2 },
                }} />
                <View style={{
                  flex: 1, height: 3, borderRadius: 2, marginHorizontal: 1,
                  backgroundColor: i < cycle5 ? '#a3d431' : '#ffffffaa',
                  transform: [{ rotate: i % 2 === 0 ? '-14deg' : '14deg' }],
                }} />
              </Row>
            ))}
            <View style={{
              transform: [{ translateY: 12 }],
              width: 34, height: 34, borderRadius: 11, backgroundColor: '#fff',
              alignItems: 'center', justifyContent: 'center',
              borderWidth: 2, borderColor: cycle5 === 0 && rs.totalRuns > 0 ? '#7FA818' : '#e4ecc9',
              shadowColor: '#0F1D13', shadowOpacity: 0.12, shadowRadius: 6, shadowOffset: { width: 0, height: 3 },
            }}>
              <Text style={{ fontSize: 17 }}>▣</Text>
            </View>
          </Row>

          <Text style={{ fontSize: 15, color: FOREST, fontWeight: '900', marginTop: 12 }}>
            {rs.totalRuns === 0
              ? '첫 러닝을 완료하면 트레일이 시작돼요'
              : cycle5 === 0
                ? '보급 드랍 도착! 리워드 센터에서 열어보세요'
                : `${remaining5}번 더 달리면 보급 드랍!`}
          </Text>
          {/* 픽 드랍 (10회) 미니 진행바 — 깃발 */}
          <Row style={{ alignItems: 'center', gap: 8, marginTop: 9 }}>
            <Text style={{ fontSize: 11.5, color: '#4a6d1f' }}>픽 드랍</Text>
            <View style={s.flagTrack}>
              <View style={[s.flagFill, { width: `${(cycle10 / 10) * 100}%` }]} />
            </View>
            <Text style={{ fontSize: 12 }}>⚑</Text>
            <Text style={{ fontSize: 11.5, color: '#4a6d1f', fontWeight: '800' }}>{cycle10}/10</Text>
          </Row>
        </Pressable>

        {/* ---------- 티어 진행 — 수수료 사다리 (최강 동기, ui-audit P2) ---------- */}
        {(() => {
          // v1 승급 기준: 베테랑 30회(수수료 18%), 마스터 100회(15%) — 심사 도입 전 잠정
          const t = rs.tier === 'veteran'
            ? { next: '마스터', at: 100, fee: '15%' }
            : rs.tier === 'master'
              ? null
              : { next: '베테랑', at: 30, fee: '18%' };
          if (!t) {
            return (
              <View style={s.tierCard}>
                <Text style={{ fontSize: 14.5, fontWeight: '900', color: FOREST }}>🏅 마스터 러너 — 최저 수수료 15%</Text>
              </View>
            );
          }
          const left = Math.max(t.at - rs.totalRuns, 0);
          const pct = Math.min(rs.totalRuns / t.at, 1);
          return (
            <View style={s.tierCard}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 14.5, fontWeight: '900', color: FOREST }}>
                  {t.next}까지 러닝 <Text style={{ color: '#d84a2f' }}>{left}회</Text>
                </Text>
                <Text style={{ fontSize: 13, fontWeight: '800', color: '#5a7a3c' }}>수수료 20% → {t.fee}</Text>
              </Row>
              <View style={s.tierTrack}>
                <View style={[s.tierFill, { width: `${pct * 100}%` }]} />
              </View>
              <Text style={{ fontSize: 11.5, color: colors.dim, marginTop: 5 }}>
                같은 수익 기준 정산액이 늘어나요 · 승급 기준은 파일럿 중 조정될 수 있어요
              </Text>
            </View>
          );
        })()}

        {/* ---------- 새 요청 ---------- */}
        {inbox.length > 0 ? (
          <Pressable onPress={() => router.push('/runner/requests')} style={s.inboxBanner}>
            <View style={{ backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 3, paddingHorizontal: 8 }}>
              <Text style={{ fontSize: 10.5, fontWeight: '900', color: FOREST }}>● LIVE</Text>
            </View>
            <Text style={{ flex: 1, fontSize: 15, fontWeight: '800', color: '#fff' }} numberOfLines={1}>
              새 요청 {inbox.length}건 — {inbox[0].dogName} {inbox[0].km}km{inbox[0].directed ? ' (지명!)' : ''}
            </Text>
            <Text style={{ fontSize: 15, color: colors.volt, fontWeight: '900' }}>응답 ›</Text>
          </Pressable>
        ) : (
          <View style={s.emptyInbox}>
            <Text style={{ fontSize: 14, color: colors.dim, textAlign: 'center' }}>
              {rs.online ? '지금은 새 요청이 없어요 — 오는 대로 여기에 떠요' : '오프라인 상태 — 켜야 요청을 받아요'}
            </Text>
          </View>
        )}

        {/* ---------- 다음 예약 스냅샷 ---------- */}
        {upcoming.length > 0 && (
          <>
            <Row style={{ justifyContent: 'space-between', marginTop: 18, marginBottom: 8 }}>
              <Text style={s.sectionTitle}>다음 예약</Text>
              <Pressable onPress={() => router.push('/runner/calendar')}>
                <Text style={{ fontSize: 13, color: colors.dim, fontWeight: '700' }}>캘린더 ›</Text>
              </Pressable>
            </Row>
            {upcoming.map((j) => (
              <Pressable key={j.bookingId} onPress={() => openJob(j)} style={s.jobRow}>
                <View style={s.jobRail} />
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 14.5, fontWeight: '800', color: '#49524a' }}>{j.when}</Text>
                  <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST, marginTop: 2 }}>
                    {j.dogName} · {j.km}km
                  </Text>
                </View>
                <Text style={{ fontSize: 15, fontWeight: '900', color: '#5a7a3c' }}>+{j.payout.toLocaleString()}</Text>
              </Pressable>
            ))}
          </>
        )}

        {/* ---------- 최근 완료 ---------- */}
        {past.length > 0 && (
          <>
            <Row style={{ justifyContent: 'space-between', marginTop: 18, marginBottom: 8 }}>
              <Text style={s.sectionTitle}>최근 완료</Text>
              <Pressable onPress={() => router.push('/runner/earnings')}>
                <Text style={{ fontSize: 13, color: colors.dim, fontWeight: '700' }}>수익 상세 ›</Text>
              </Pressable>
            </Row>
            {past.map((j) => (
              <View key={j.bookingId} style={[s.jobRow, { opacity: 0.75 }]}>
                <View style={[s.jobRail, { backgroundColor: '#c9ccc0' }]} />
                <View style={{ flex: 1 }}>
                  <Text style={{ fontSize: 14.5, fontWeight: '800', color: '#49524a' }}>{j.when}</Text>
                  <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST, marginTop: 2 }}>
                    {j.dogName} · {j.km}km · 완료
                  </Text>
                </View>
                <Text style={{ fontSize: 15, fontWeight: '900', color: '#75806f' }}>+{j.payout.toLocaleString()}</Text>
              </View>
            ))}
          </>
        )}

        {/* ---------- quick links ---------- */}
        <Row style={{ justifyContent: 'flex-end', gap: 16, marginTop: 16 }}>
          <Pressable onPress={() => router.push('/leaderboard')}>
            <Text style={[text.dim, { fontWeight: '700' }]}>🏆 랭킹 ›</Text>
          </Pressable>
          <Pressable onPress={() => router.push('/community')}>
            <Text style={[text.dim, { fontWeight: '700' }]}>커뮤니티 ›</Text>
          </Pressable>
          <Pressable onPress={() => router.push('/safety')}>
            <Text style={[text.dim, { fontWeight: '700' }]}>안심 센터 ›</Text>
          </Pressable>
          <Pressable onPress={() => router.push('/cards')}>
            <Text style={[text.dim, { fontWeight: '700' }]}>마이 카드 ›</Text>
          </Pressable>
        </Row>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  currentCard: { backgroundColor: FOREST, borderRadius: 20, padding: 16, marginTop: 16, borderWidth: 2, borderColor: colors.volt },
  stagePill: { borderRadius: 99, paddingVertical: 4, paddingHorizontal: 9 },
  currentBtn: { borderRadius: 13, alignItems: 'center', paddingVertical: 12 },
  trailCard: {
    backgroundColor: '#DDF0A6', borderRadius: 18, padding: 16, paddingTop: 12, marginTop: 12,
    borderWidth: 1, borderColor: '#c3dd76', overflow: 'hidden',
  },
  trailTab: {
    position: 'absolute', top: 0, left: 0, backgroundColor: '#0F1D13',
    borderTopLeftRadius: 22, borderBottomRightRadius: 15, paddingVertical: 7, paddingHorizontal: 13,
  },
  availCard: { backgroundColor: '#fff', borderRadius: 18, padding: 15, marginTop: 12, borderWidth: 1, borderColor: '#DCD6C4' },
  availDay: {
    flex: 1, alignItems: 'center', paddingVertical: 12, borderRadius: 13,
    backgroundColor: '#f4f2ea', borderWidth: 1.5, borderColor: '#DCD6C4',
  },
  availDayOn: { backgroundColor: '#eaf7c8', borderColor: '#a9c47e' },
  tierCard: { backgroundColor: '#fff', borderRadius: 16, padding: 14, marginTop: 12, borderWidth: 1, borderColor: '#DCD6C4' },
  tierTrack: { height: 7, borderRadius: 99, backgroundColor: '#f0eee3', marginTop: 9, overflow: 'hidden' },
  tierFill: { height: 7, borderRadius: 99, backgroundColor: colors.volt },
  gem: {
    width: 16, height: 16, borderRadius: 4, backgroundColor: '#f0efe8',
    borderWidth: 1.5, borderColor: '#dcd9cc', transform: [{ rotate: '45deg' }],
  },
  trailLine: { flex: 1, height: 2.5, backgroundColor: '#DCD6C4', marginHorizontal: 3 },
  giftBox: {
    width: 30, height: 30, borderRadius: 9, backgroundColor: '#f0efe8',
    alignItems: 'center', justifyContent: 'center', borderWidth: 1.5, borderColor: '#dcd9cc',
  },
  flagTrack: { flex: 1, height: 6, borderRadius: 99, backgroundColor: '#ffffffbb', overflow: 'hidden' },
  flagFill: { height: 6, borderRadius: 99, backgroundColor: '#7FA818' },
  inboxBanner: {
    flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: 12,
    backgroundColor: FOREST, borderRadius: 16, padding: 14,
  },
  emptyInbox: { marginTop: 12, backgroundColor: '#f4f2ea', borderRadius: 14, padding: 14 },
  sectionTitle: { fontSize: 16, fontWeight: '900', color: FOREST },
  jobRow: {
    flexDirection: 'row', alignItems: 'center', gap: 11, backgroundColor: '#fff',
    borderRadius: 14, padding: 12, borderWidth: 1, borderColor: '#DCD6C4', marginBottom: 7,
  },
  jobRail: { width: 4, height: 32, borderRadius: 2, backgroundColor: '#5a7a3c' },
});
