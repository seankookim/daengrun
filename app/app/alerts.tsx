import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../src/components/bottomnav';
import { Row } from '../src/components/ui';
import { fetchNotifications, LiveNoti, markAllNotificationsRead } from '../src/lib/api';
import { dog, session } from '../src/store';
import { colors } from '../src/theme';

// 알림 — notification center per mock: filter tabs, unread section, history.

const FOREST = '#132117';

export default function Alerts() {
  const [liveNotis, setLiveNotis] = useState<LiveNoti[]>([]);

  const load = () => fetchNotifications().then(setLiveNotis).catch(() => {});
  useFocusEffect(useCallback(() => { load(); }, []));
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  // 알림 탭 도착지 — 역할별: 보호자는 리포트(러닝 전이면 상태 안내), 러너는 요청/캘린더
  const openNoti = (n: LiveNoti) => {
    if (!n.refId || n.kind !== 'booking') return;
    if (session.role === 'runner') {
      router.push(n.title.includes('요청') ? '/runner/requests' : '/runner/calendar');
    } else {
      router.push({ pathname: '/owner/report', params: { bid: n.refId } });
    }
  };

  const markAll = async () => {
    try {
      await markAllNotificationsRead();
      load();
      Alert.alert('모두 읽음', '모든 알림을 읽음 처리했어요');
    } catch {
      Alert.alert('모두 읽음', '모든 알림을 읽음 처리했어요 (데모)');
    }
  };

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ padding: 22, paddingTop: 64, paddingBottom: 24 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        {/* header */}
        <Row style={{ justifyContent: 'space-between', alignItems: 'flex-start' }}>
          <Pressable onPress={() => router.back()} style={[s.hBtn, { marginRight: 12 }]}>
            <Text style={{ fontSize: 18, color: FOREST }}>‹</Text>
          </Pressable>
          <View style={{ flex: 1 }}>
            <Row style={{ gap: 5 }}>
              <Text style={s.h1}>알림</Text>
              <View style={{ width: 7, height: 7, borderRadius: 4, backgroundColor: colors.voltDeep, marginTop: 8 }} />
            </Row>
            <Text style={s.sub}>{dog.name}와 관련된 소식을 한눈에 확인하세요!</Text>
          </View>
          <Pressable onPress={markAll}>
            <HeaderBtn glyph="✓" label="모두 읽음" />
          </Pressable>
        </Row>

        {/* 필터 탭 은퇴 (ui-audit P1) — 알림 종류가 늘면 실필터로 복귀 */}

        {/* ---------- 실시간 알림 (서버) ---------- */}
        {liveNotis.length > 0 && (
          <View style={{ marginTop: 22 }}>
            <Row style={{ gap: 8, marginBottom: 10 }}>
              <Text style={s.section}>내 알림</Text>
              <View style={{ backgroundColor: '#5a7a3c', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' }}>
                <Text style={{ fontSize: 8.5, fontWeight: '900', color: '#fff' }}>● LIVE</Text>
              </View>
            </Row>
            <View style={{ gap: 10 }}>
              {liveNotis.map((n) => (
                <Pressable key={n.id} onPress={() => openNoti(n)} style={[s.noti, n.unread && s.notiHi]}>
                  <View style={[s.notiIcon, { backgroundColor: '#e7efd8' }]}>
                    {n.unread && <View style={s.unreadDot} />}
                    <Text style={{ fontSize: 13, fontWeight: '900', color: '#3d5a2b' }}>런</Text>
                  </View>
                  <View style={{ flex: 1 }}>
                    <Row style={{ justifyContent: 'space-between' }}>
                      <Text style={{ fontSize: 14.5, fontWeight: '900', color: FOREST }}>{n.title}</Text>
                      <Text style={{ fontSize: 10.5, color: colors.dim }}>{n.when}</Text>
                    </Row>
                    {n.body && <Text style={{ fontSize: 12.5, color: '#5d655d', marginTop: 3 }}>{n.body}</Text>}
                    {n.refId && n.kind === 'booking' && (
                      <Text style={{ fontSize: 11, fontWeight: '800', color: '#5a7a3c', marginTop: 5 }}>자세히 보기 ›</Text>
                    )}
                  </View>
                </Pressable>
              ))}
            </View>
          </View>
        )}

        {liveNotis.length === 0 && (
          <View style={{ marginTop: 24, backgroundColor: '#fff', borderRadius: 16, padding: 24, alignItems: 'center', borderWidth: 1, borderColor: '#eceadf' }}>
            <Text style={{ fontSize: 13, color: colors.dim, textAlign: 'center', lineHeight: 20 }}>
              아직 알림이 없어요{'\n'}예약·러닝 소식이 여기에 도착해요
            </Text>
          </View>
        )}

      </ScrollView>
      <BottomNav />
    </View>
  );
}

function HeaderBtn({ glyph, label }: { glyph: string; label: string }) {
  return (
    <View style={{ alignItems: 'center', gap: 3 }}>
      <View style={s.hBtn}><Text style={{ fontSize: 14, color: '#5d655d' }}>{glyph}</Text></View>
      <Text style={{ fontSize: 10, color: '#5d655d' }}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  h1: { fontSize: 30, fontWeight: '900', color: FOREST },
  sub: { fontSize: 13, color: '#5d655d', marginTop: 6 },
  hBtn: { width: 42, height: 42, borderRadius: 21, backgroundColor: '#fff', borderWidth: 1, borderColor: colors.line, alignItems: 'center', justifyContent: 'center' },
  tabsWrap: { flexDirection: 'row', backgroundColor: '#fff', borderRadius: 99, padding: 4, marginTop: 18, borderWidth: 1, borderColor: '#eceadf' },
  tab: { flex: 1, alignItems: 'center', paddingVertical: 9, borderRadius: 99, flexDirection: 'row', justifyContent: 'center' },
  tabSel: { backgroundColor: FOREST },
  tabText: { fontSize: 13, fontWeight: '700', color: '#5d655d' },
  tabDivider: { position: 'absolute', right: 0, top: 10, bottom: 10, width: 1, backgroundColor: '#eceadf' },
  section: { fontSize: 15, fontWeight: '900', color: FOREST },
  countBadge: { width: 20, height: 20, borderRadius: 10, backgroundColor: colors.volt, alignItems: 'center', justifyContent: 'center' },
  noti: { flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: '#fff', borderRadius: 18, padding: 14, borderWidth: 1, borderColor: '#eceadf' },
  notiHi: { backgroundColor: '#f7faee', borderColor: '#dde8c4' },
  notiIcon: { width: 46, height: 46, borderRadius: 23, alignItems: 'center', justifyContent: 'center' },
  unreadDot: { position: 'absolute', top: 2, right: 2, width: 8, height: 8, borderRadius: 4, backgroundColor: colors.voltDeep, zIndex: 2 },
  newBadge: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 2, paddingHorizontal: 7, alignSelf: 'center' },
  pointBadge: { backgroundColor: '#e3f0c4', borderRadius: 99, paddingVertical: 5, paddingHorizontal: 9 },
  thumb: { width: 52, height: 52, borderRadius: 12, overflow: 'hidden' },
});
