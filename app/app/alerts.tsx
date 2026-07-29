import { router, useFocusEffect } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../src/components/bottomnav';
import { Row } from '../src/components/ui';
import { fetchNotifications, LiveNoti, markAllNotificationsRead } from '../src/lib/api';
import { useDisplayFont } from '../src/lib/displayFont';
import { routeForNotification } from '../src/lib/push';
import { colors } from '../src/theme';

// 알림 — A1(소인 우편함) × A2(러닝 레일) 머지 (Sean 확정, 2026-07-29, docs/hi-club-plan.md §1-A).
// A2에서: 다크 헤더 + 라이브 티커(최신 미읽음 실데이터) + 상태 컬러 수직 레일 (일정 탭과 같은 스키마).
// A1에서: 날짜 그룹 = 회전 원형 소인 스탬프, 아이템 = 아이콘 칩 + NEW 볼트 씰 포맷.
// 히어로 모티프 = 레일(트레이스) 1개 — 소인·씰은 보조 (화면당 1히어로 규칙).

const FOREST = '#0F1D13';

// 소인 잉크 시스템 (P4, Sean 확정) — kind + 제목 휴리스틱으로 종류별 잉크색.
// 인박스가 스캔 한 번에 분류되게: 예약=그린 · 클럽=바이올렛 · 변경/대기=앰버 · 기록=골드 · 취소=레드
const inkFor = (kind: string | null | undefined, title: string): { bg: string; fg: string } => {
  if (/돌파|기록|달성|경신/.test(title)) return { bg: colors.goldTint, fg: colors.goldDeep }; // 기록 골드 (P3)
  if (kind === 'community') return { bg: colors.clubTint, fg: colors.clubInk };               // 클럽 바이올렛
  if (/만료|취소|SOS/.test(title)) return { bg: '#FCE7E1', fg: '#d84a2f' };
  if (/대기|요청|재탐색|이동|변경|제안/.test(title)) return { bg: '#FCEFD9', fg: '#9D580A' }; // 앰버
  if (/수락|확정|매칭/.test(title)) return { bg: '#E3EEF8', fg: '#4A6E93' };                  // 확정 블루
  return { bg: '#e7efd8', fg: '#3d5a2b' }; // 완료·시작·적립 등 — 그린
};
const glyphFor = (title: string): string => {
  if (/완료|시작|돌파/.test(title)) return '🏃';
  if (/반복/.test(title)) return '⟳';
  if (/변경|수락/.test(title)) return '✓';
  if (/만료|취소/.test(title)) return '✕';
  if (/SOS/.test(title)) return '🚨';
  return '런';
};
// 소인 스탬프용 컴팩트 날짜 ("7월 29일 (화)" → "7.29")
const stampOf = (dateLabel: string): string => {
  const m = dateLabel.match(/(\d+)월\s*(\d+)일/);
  return m ? `${m[1]}.${m[2]}` : dateLabel;
};

export default function Alerts() {
  const df = useDisplayFont();
  const [liveNotis, setLiveNotis] = useState<LiveNoti[]>([]);

  const load = () => fetchNotifications().then(setLiveNotis).catch(() => {});
  useFocusEffect(useCallback(() => { load(); }, []));
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  // 알림 탭 도착지 — push.ts routeForNotification과 단일 소스 (푸시 탭 딥링크와 동일 규칙)
  const openNoti = (n: LiveNoti) => routeForNotification(n.kind, n.refId, n.title);

  const markAll = async () => {
    try {
      await markAllNotificationsRead();
      load();
    } catch {
      Alert.alert('읽음 처리 실패', '잠시 후 다시 시도해주세요');
    }
  };

  const unreadCount = liveNotis.filter((n) => n.unread).length;
  const latestUnread = liveNotis.find((n) => n.unread) ?? null;
  // 날짜 그룹 (fetchNotifications가 최신순 정렬 — 그룹 순서 보존)
  const groups = useMemo(() => {
    const out: { date: string; items: LiveNoti[] }[] = [];
    for (const n of liveNotis) {
      const last = out[out.length - 1];
      if (last && last.date === n.dateLabel) last.items.push(n);
      else out.push({ date: n.dateLabel, items: [n] });
    }
    return out;
  }, [liveNotis]);

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ padding: 16, paddingTop: 60, paddingBottom: 28 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        <Row style={{ justifyContent: 'space-between', marginBottom: 12 }}>
          <Pressable onPress={() => router.back()} style={s.hBtn}>
            <Text style={{ fontSize: 20.5, color: FOREST }}>‹</Text>
          </Pressable>
          {unreadCount > 0 && (
            <Pressable onPress={markAll} style={s.markAll}>
              <Text style={{ fontSize: 13, fontWeight: '800', color: '#49524a' }}>✓ 모두 읽음</Text>
            </Pressable>
          )}
        </Row>

        {/* ---------- 다크 헤더 + 라이브 티커 (A2) ---------- */}
        <View style={s.head}>
          <Row style={{ justifyContent: 'space-between', alignItems: 'flex-end' }}>
            <Text style={[{ fontSize: 27, fontWeight: '900', color: '#fff' }, df]}>알림</Text>
            {unreadCount > 0 && (
              <Text style={{ fontSize: 14.5, fontWeight: '800', color: colors.volt }}>안 읽음 {unreadCount}</Text>
            )}
          </Row>
          {/* 티커 — 최신 미읽음 1건 실데이터. 없으면 그리지 않는다 */}
          {latestUnread && (
            <Pressable onPress={() => openNoti(latestUnread)} style={s.ticker}>
              <View style={s.tickDot} />
              <Text numberOfLines={1} style={{ flex: 1, fontSize: 14, fontWeight: '700', color: colors.volt }}>
                {latestUnread.timeLabel} · {latestUnread.title}
              </Text>
              <Text style={{ fontSize: 14, color: '#8fa093' }}>›</Text>
            </Pressable>
          )}
        </View>

        {/* ---------- 레일 타임라인 + 소인 그룹 ---------- */}
        {groups.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: colors.dim, textAlign: 'center', lineHeight: 23 }}>
              아직 알림이 없어요{'\n'}예약·러닝 소식이 여기에 도착해요
            </Text>
          </View>
        )}

        {groups.length > 0 && (
          <View style={s.railWrap}>
            <View style={s.railLine} />
            {groups.map((g, gi) => (
              <View key={g.date}>
                {/* 소인 스탬프 (A1) — 살짝 교차 회전 */}
                <Row style={{ alignItems: 'center', gap: 10, marginTop: gi === 0 ? 18 : 24, marginBottom: 10 }}>
                  <View style={[s.stamp, { transform: [{ rotate: gi % 2 === 0 ? '-7deg' : '6deg' }] }]}>
                    <Text style={[{ fontSize: 15, fontWeight: '900', color: FOREST }, df]}>{stampOf(g.date)}</Text>
                    <Text style={{ fontSize: 8, letterSpacing: 1.5, color: '#75806f', fontWeight: '700' }}>DOGS HIGH</Text>
                  </View>
                  <View style={s.stampDash} />
                </Row>
                {g.items.map((n) => {
                  const ink = inkFor(n.kind, n.title);
                  return (
                  <Pressable key={n.id} onPress={() => openNoti(n)} style={s.evtRow}>
                    {/* 레일 도트 — 소인 잉크와 동색 링 */}
                    <View style={[s.railDot, { borderColor: ink.fg }, n.unread && { backgroundColor: colors.volt, borderColor: FOREST }]} />
                    <View style={[s.card, n.unread && s.cardHi]}>
                      {n.unread && <View style={s.seal}><Text style={{ fontSize: 9.5, fontWeight: '900', color: FOREST }}>NEW</Text></View>}
                      <Row style={{ gap: 11 }}>
                        <View style={[s.icon, { backgroundColor: ink.bg }]}><Text style={{ fontSize: 15, fontWeight: '900', color: ink.fg }}>{glyphFor(n.title)}</Text></View>
                        <View style={{ flex: 1 }}>
                          <Row style={{ justifyContent: 'space-between' }}>
                            <Text style={{ fontSize: 16, fontWeight: '900', color: FOREST, flex: 1, paddingRight: 40 }}>{n.title}</Text>
                          </Row>
                          {n.body && <Text style={{ fontSize: 14.5, color: '#49524a', marginTop: 3, lineHeight: 20 }}>{n.body}</Text>}
                          <Text style={{ fontSize: 12.5, color: '#9a978a', marginTop: 5 }}>{n.timeLabel}</Text>
                        </View>
                      </Row>
                    </View>
                  </Pressable>
                  );
                })}
              </View>
            ))}
          </View>
        )}
      </ScrollView>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  hBtn: { width: 42, height: 42, borderRadius: 21, backgroundColor: '#fff', borderWidth: 1, borderColor: colors.line, alignItems: 'center', justifyContent: 'center' },
  markAll: { backgroundColor: '#fff', borderWidth: 1, borderColor: colors.line, borderRadius: 99, paddingVertical: 10, paddingHorizontal: 14, alignSelf: 'center' },
  head: { backgroundColor: FOREST, borderRadius: 20, padding: 16 },
  ticker: { flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: '#1b2d20', borderRadius: 12, paddingVertical: 9, paddingHorizontal: 12, marginTop: 11 },
  tickDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: colors.tang },
  emptyBox: { marginTop: 20, backgroundColor: '#fff', borderRadius: 16, padding: 18, borderWidth: 1, borderColor: '#DCD6C4' },
  railWrap: { position: 'relative', paddingLeft: 22 },
  railLine: { position: 'absolute', left: 5, top: 26, bottom: 8, width: 3.5, borderRadius: 3, backgroundColor: '#cede96' },
  stamp: { width: 58, height: 58, borderRadius: 29, borderWidth: 2.5, borderColor: FOREST, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', marginLeft: -4 },
  stampDash: { flex: 1, borderTopWidth: 2, borderColor: '#DCD6C4', borderStyle: 'dashed' },
  evtRow: { position: 'relative', marginBottom: 9 },
  railDot: { position: 'absolute', left: -22.5, top: 18, width: 14, height: 14, borderRadius: 8, backgroundColor: '#fff', borderWidth: 3.5 },
  card: { backgroundColor: '#fff', borderRadius: 15, padding: 13, borderWidth: 1, borderColor: '#DCD6C4' },
  cardHi: { backgroundColor: '#fbfdf2', borderColor: '#cede96' },
  seal: { position: 'absolute', top: -8, right: 13, backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 3, paddingHorizontal: 9, transform: [{ rotate: '3deg' }], zIndex: 2, shadowColor: FOREST, shadowOpacity: 0.18, shadowRadius: 4, shadowOffset: { width: 0, height: 2 } },
  icon: { width: 42, height: 42, borderRadius: 12, backgroundColor: '#e7efd8', alignItems: 'center', justifyContent: 'center' },
});
