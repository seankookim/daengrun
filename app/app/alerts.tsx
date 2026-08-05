import { router, useFocusEffect } from 'expo-router';
import { useCallback, useMemo, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../src/components/bottomnav';
import { Row } from '../src/components/ui';
import { fetchNotifications, LiveNoti, markAllNotificationsRead } from '../src/lib/api';
import { useDisplayFont } from '../src/lib/displayFont';
import { useNumFont } from '../src/lib/fonts';
import { routeForNotification } from '../src/lib/push';
import { colors, lilac, lilacRadius, lilacShadow } from '../src/theme';

// 알림 — "여권 × 안내판(Arrivals board)" 정본 (Sean 확정, 2026-08-01 delegation-premium-refresh2).
// 문법: 시각 컬럼(Oswald) · 정사각 모노 타입 태그 · 헤어라인 행 · 안 읽음 = 좌측 코랄 틱(도트/엣지, 텍스트 금지).
// 히어로 = 나이트-라일락 보드 헤더 1개 + 라이브 티커(최신 미읽음 실데이터). 날짜/요일은 전부 실 timestamp에서 온다.
// FIX3 (2026-08-03): 디테일 텍스트 1.4–1.75x 상향(12–15pt 밴드, 플로어 11.5) · Oswald 숫자 lineHeight ≥1.2x 클리핑 방지.

// 소인 잉크 시스템 — kind + 제목 휴리스틱으로 종류별 잉크색 (라일락 리페인트: 스왐프 그린 은퇴, 확정 블루 유지).
// 인박스가 스캔 한 번에 분류되게: 완료/시작=볼트(기능 성공) · 클럽=바이올렛 · 변경/대기=앰버 · 확정=블루 · 기록=골드 · 취소=탱
const inkFor = (kind: string | null | undefined, title: string): { bg: string; fg: string } => {
  if (/돌파|기록|달성|경신/.test(title)) return { bg: lilac.goldSoft, fg: lilac.gold };      // 기록 골드 (P3, 희소)
  if (kind === 'community') return { bg: colors.clubTint, fg: lilac.accent };                // 클럽 바이올렛
  if (/만료|취소|SOS/.test(title)) return { bg: '#FDEDE8', fg: lilac.tang };                  // 크리티컬 탱
  if (/대기|요청|재탐색|이동|변경|제안/.test(title)) return { bg: lilac.amberSoft, fg: lilac.amber }; // 앰버
  if (/수락|확정|매칭/.test(title)) return { bg: '#E3EEF8', fg: '#4A6E93' };                  // 확정 블루 (정본 유지)
  return { bg: lilac.voltFill, fg: lilac.voltDeep }; // 완료·시작·적립 등 — 기능 볼트(성공 확인 전용)
};
const glyphFor = (title: string): string => {
  if (/완료|시작|돌파/.test(title)) return '🏃';
  if (/반복/.test(title)) return '⟳';
  if (/변경|수락/.test(title)) return '✓';
  if (/만료|취소/.test(title)) return '✕';
  if (/SOS/.test(title)) return '🚨';
  return '런';
};
// 정사각 모노 타입 태그 라벨 — inkFor와 동일 버킷에서 파생 (제목 실데이터 기반, 조작 아님)
const tagFor = (kind: string | null | undefined, title: string): string => {
  if (/돌파|기록|달성|경신/.test(title)) return '기록';
  if (kind === 'community') return '클럽';
  if (/만료|취소|SOS/.test(title)) return '취소';
  if (/반복/.test(title)) return '반복';
  if (/대기|요청|재탐색|이동|변경|제안/.test(title)) return '변경';
  if (/수락|확정|매칭/.test(title)) return '확정';
  return '완료';
};
// 소인 스탬프용 컴팩트 날짜 ("8월 3일 (일)" → "8.3") — 실 dateLabel에서만 파생, 하드코딩 없음
const stampOf = (dateLabel: string): string => {
  const m = dateLabel.match(/(\d+)월\s*(\d+)일/);
  return m ? `${m[1]}.${m[2]}` : dateLabel;
};

export default function Alerts() {
  const df = useDisplayFont();
  const nf = useNumFont(); // Oswald — 시각·소인·카운트 (안내판 문법)
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
    <View style={{ flex: 1, backgroundColor: lilac.bg }}>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingTop: 56, paddingBottom: 28 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        {/* ---------- 글래스 마스트 ---------- */}
        <Row style={s.mast}>
          <Pressable onPress={() => router.back()} style={s.iconBtn}>
            <Text style={{ fontSize: 15, color: lilac.head, marginTop: -1 }}>‹</Text>
          </Pressable>
          <Text style={[s.crumb, nf]}>MY / ALERTS</Text>
          {unreadCount > 0 ? (
            <Pressable onPress={markAll} style={s.markAll}>
              <Text style={[s.markAllTxt, nf]}>✓ 모두 읽음</Text>
            </Pressable>
          ) : (
            <View style={{ width: 26 }} />
          )}
        </Row>

        {/* ---------- 나이트-라일락 보드 헤더 + 라이브 티커 ---------- */}
        <View style={s.board}>
          <View style={s.boardEdge} />
          <View style={{ padding: 14 }}>
            <Text style={[s.boardKick, nf]}>ARRIVALS · 도착한 소식</Text>
            <Row style={{ justifyContent: 'space-between', alignItems: 'flex-end' }}>
              <Text style={[{ fontSize: 30, color: '#fff', lineHeight: 36 }, df]}>알림</Text>
              {unreadCount > 0 && (
                <Row style={{ alignItems: 'baseline', gap: 6 }}>
                  <Text style={{ fontSize: 14, color: 'rgba(255,255,255,0.72)', fontWeight: '600' }}>안 읽음</Text>
                  <Text style={[{ fontSize: 17, lineHeight: 21, color: '#fff' }, nf]}>{unreadCount}</Text>
                </Row>
              )}
            </Row>
            {/* 티커 — 최신 미읽음 1건 실데이터. 없으면 그리지 않는다 */}
            {latestUnread && (
              <Pressable onPress={() => openNoti(latestUnread)} style={s.ticker}>
                <View style={s.liveDot} />
                <Text style={[s.tickTime, nf]}>{latestUnread.timeLabel}</Text>
                <Text numberOfLines={1} style={s.tickTxt}>{latestUnread.title}</Text>
                <Text style={{ fontSize: 14, color: 'rgba(255,255,255,0.55)' }}>›</Text>
              </Pressable>
            )}
          </View>
        </View>

        <View style={{ paddingHorizontal: 12, paddingTop: 12 }}>
          {/* 보드 컬럼 헤더 (안내판 문법) */}
          {groups.length > 0 && (
            <Row style={s.colhead}>
              <Text style={[s.colTxt, nf, { width: 66 }]}>TIME</Text>
              <Text style={[s.colTxt, nf, { width: 54 }]}>TYPE</Text>
              <Text style={[s.colTxt, nf, { flex: 1 }]}>내용</Text>
            </Row>
          )}

          {/* 빈 상태 */}
          {groups.length === 0 && (
            <View style={s.empty}>
              <View style={s.emptyTag}><Text style={[s.emptyTagTxt, nf]}>EMPTY STATE</Text></View>
              <Text style={{ fontSize: 14.5, color: lilac.dim, textAlign: 'center', lineHeight: 23 }}>
                아직 알림이 없어요{'\n'}예약 · 러닝 소식이 여기에 도착해요
              </Text>
            </View>
          )}

          {/* ---------- 레일 타임라인 + 소인 그룹 ---------- */}
          {groups.map((g, gi) => (
            <View key={g.date}>
              {/* 소인 스탬프 — 살짝 교차 회전, 날짜는 실 dateLabel 파생 */}
              <Row style={{ alignItems: 'center', gap: 9, marginTop: gi === 0 ? 14 : 18, marginBottom: 8 }}>
                <View style={[s.postmark, { transform: [{ rotate: gi % 2 === 0 ? '-7deg' : '6deg' }] }]}>
                  <Text style={[s.postmarkD, nf]}>{stampOf(g.date)}</Text>
                  <Text style={[s.postmarkK, nf]}>DOGS HIGH</Text>
                </View>
                <View style={s.groupDash} />
                <Text style={[s.groupLabel, nf]}>{g.date} · {g.items.length}</Text>
              </Row>

              <View style={s.rail}>
                <View style={s.railLine} />
                {g.items.map((n) => {
                  const ink = inkFor(n.kind, n.title);
                  return (
                    <Pressable key={n.id} onPress={() => openNoti(n)} style={[s.evt, n.unread && s.evtNew]}>
                      {/* 레일 도트 — 미읽음=코랄 채움/엣지, 읽음=잉크 링 */}
                      <View
                        style={[
                          s.dot,
                          { borderColor: ink.fg },
                          n.unread && { backgroundColor: lilac.coral, borderColor: lilac.coralDeep },
                        ]}
                      />
                      {/* 좌측 코랄 틱 — 미읽음 엣지 (텍스트 아님) */}
                      <View style={[s.evtTick, n.unread && { backgroundColor: lilac.coral }]} />
                      <View style={s.evtCell}>
                        <Row style={{ alignItems: 'center', gap: 7, marginBottom: 7 }}>
                          <Text style={[s.evtTime, nf, !n.unread && { color: lilac.text }]}>{n.timeLabel}</Text>
                          <View style={[s.typeTag, { backgroundColor: ink.bg }]}>
                            <Text style={[s.typeTagTxt, nf]}>{tagFor(n.kind, n.title)}</Text>
                          </View>
                          {n.unread && (
                            <View style={s.seal}><Text style={[s.sealTxt, nf]}>NEW</Text></View>
                          )}
                        </Row>
                        <Row style={{ gap: 9, alignItems: 'flex-start' }}>
                          <View style={[s.glyph, { backgroundColor: ink.bg }]}>
                            <Text style={{ fontSize: 14, fontWeight: '900', color: ink.fg }}>{glyphFor(n.title)}</Text>
                          </View>
                          <View style={{ flex: 1 }}>
                            <Text style={s.evtTitle}>{n.title}</Text>
                            {n.body && <Text style={s.evtBody}>{n.body}</Text>}
                          </View>
                        </Row>
                      </View>
                    </Pressable>
                  );
                })}
              </View>
            </View>
          ))}
        </View>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  mast: {
    justifyContent: 'space-between', alignItems: 'center', gap: 8,
    paddingHorizontal: 12, paddingBottom: 10, marginBottom: 2,
    backgroundColor: lilac.glass, borderBottomWidth: 1, borderBottomColor: lilac.hair2,
  },
  iconBtn: {
    width: 26, height: 26, borderRadius: lilacRadius.inner, backgroundColor: lilac.card,
    borderWidth: 1, borderColor: lilac.hair, alignItems: 'center', justifyContent: 'center',
  },
  crumb: { fontSize: 12, letterSpacing: 2, color: lilac.dim },
  markAll: {
    backgroundColor: lilac.card, borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.tag,
    paddingVertical: 7, paddingHorizontal: 10,
  },
  markAllTxt: { fontSize: 14, lineHeight: 18, letterSpacing: 1, color: lilac.head },

  board: {
    marginHorizontal: 12, borderRadius: lilacRadius.card, overflow: 'hidden',
    backgroundColor: '#1C1837', ...lilacShadow, shadowOpacity: 0.34,
  },
  boardEdge: { position: 'absolute', top: 0, left: 0, right: 0, height: 2, backgroundColor: lilac.coral, opacity: 0.85, zIndex: 2 },
  boardKick: { fontSize: 12, letterSpacing: 2, color: 'rgba(255,255,255,0.5)', marginBottom: 8 },
  ticker: {
    flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 11, paddingVertical: 10, paddingHorizontal: 10,
    borderRadius: lilacRadius.inner, backgroundColor: 'rgba(255,255,255,0.07)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.14)',
  },
  liveDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: lilac.coral },
  tickTime: { fontSize: 14, lineHeight: 18, color: '#fff', letterSpacing: 0.5 },
  tickTxt: { flex: 1, fontSize: 14, fontWeight: '600', color: '#fff' },

  colhead: {
    alignItems: 'center', gap: 8, paddingVertical: 8,
    borderTopWidth: 1, borderTopColor: lilac.hair, borderBottomWidth: 1, borderBottomColor: lilac.hair,
  },
  colTxt: { fontSize: 12, letterSpacing: 1.8, color: lilac.dim },

  empty: {
    marginTop: 14, borderWidth: 1, borderColor: lilac.hair, borderStyle: 'dashed',
    borderRadius: lilacRadius.card, backgroundColor: lilac.glass, paddingVertical: 20, paddingHorizontal: 14, alignItems: 'center',
  },
  emptyTag: { borderWidth: 1, borderColor: lilac.hair, borderRadius: lilacRadius.tag, paddingHorizontal: 8, paddingVertical: 4, marginBottom: 10 },
  emptyTagTxt: { fontSize: 12, letterSpacing: 1.2, color: lilac.dim },

  postmark: {
    width: 62, height: 62, borderRadius: 31, borderWidth: 1.5, borderColor: lilac.head, backgroundColor: lilac.card,
    alignItems: 'center', justifyContent: 'center', ...lilacShadow, shadowOpacity: 0.1, shadowRadius: 12,
  },
  postmarkD: { fontSize: 14, lineHeight: 17, color: lilac.head },
  // 소인 도장 안의 브랜드 각인 — 62px 원 안에 한 줄로 앉아야 하는 시리얼 보이스(장식)라 플로어 면제
  postmarkK: { fontSize: 12, letterSpacing: 0.2, color: lilac.dim, marginTop: 1 },
  groupDash: { flex: 1, borderTopWidth: 1.5, borderTopColor: lilac.hair, borderStyle: 'dashed' },
  groupLabel: { fontSize: 14, lineHeight: 18, letterSpacing: 1.2, color: lilac.dim },

  rail: { position: 'relative', paddingLeft: 16 },
  railLine: { position: 'absolute', left: 4, top: 20, bottom: 14, width: 1, backgroundColor: lilac.hair },

  evt: {
    position: 'relative', flexDirection: 'row', backgroundColor: lilac.card,
    borderWidth: 1, borderColor: lilac.hair2, borderRadius: lilacRadius.inner, marginBottom: 7, overflow: 'hidden',
    ...lilacShadow, shadowOpacity: 0.05, shadowRadius: 12,
  },
  evtNew: { borderColor: lilac.hair, shadowOpacity: 0.09 },
  dot: {
    position: 'absolute', left: -15.5, top: 17, width: 9, height: 9, borderRadius: 5,
    backgroundColor: lilac.card, borderWidth: 2, zIndex: 3,
  },
  evtTick: { width: 3, alignSelf: 'stretch', backgroundColor: 'transparent' },
  evtCell: { flex: 1, paddingVertical: 12, paddingLeft: 9, paddingRight: 11 },
  evtTime: { fontSize: 14, lineHeight: 18, color: lilac.head, letterSpacing: 0.5 },
  typeTag: {
    borderWidth: 1, borderColor: 'rgba(34,30,61,0.1)', borderRadius: lilacRadius.tag,
    paddingHorizontal: 7, paddingTop: 4, paddingBottom: 3,
  },
  typeTagTxt: { fontSize: 12, letterSpacing: 1, color: lilac.head },
  seal: {
    marginLeft: 'auto', backgroundColor: lilac.coralSoft, borderWidth: 1, borderColor: lilac.coral,
    borderRadius: lilacRadius.tag, paddingHorizontal: 7, paddingTop: 4, paddingBottom: 3,
  },
  sealTxt: { fontSize: 12, letterSpacing: 1, color: lilac.head },
  glyph: {
    width: 28, height: 28, borderRadius: lilacRadius.tag, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: 'rgba(34,30,61,0.05)',
  },
  evtTitle: { fontSize: 14, fontWeight: '700', color: lilac.head, lineHeight: 19 },
  evtBody: { fontSize: 14, color: lilac.text, marginTop: 4, lineHeight: 18 },
});
