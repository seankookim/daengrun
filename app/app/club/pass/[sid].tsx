import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, ScrollView, Text, View, StyleSheet } from 'react-native';
import { Row } from '../../../src/components/ui';
import { checkinClubSession, ClubSessionDetail, fetchClubSession } from '../../../src/lib/api';
import { useDisplayFont } from '../../../src/lib/displayFont';
import { haptic } from '../../../src/lib/haptics';
import { colors } from '../../../src/theme';

// 🎟 입장권 (D1×D2 하이브리드, Sean 확정) — 집결지에서 호스트에게 '보여주는' 화면.
// 나이트 스텁 티켓: ADMIT 언어(책임 불변식의 입장권 버전) + 빕 넘버(D1 명부) + 바코드.
// 체크인 버튼이 티켓 위에 산다 — 보여주면서 그 자리에서 찍는 게 자연스러운 동선.
// 체크인 창(시작 −2h~+6h)은 서버(session_checkin)가 강제 — 화면은 안내만.

const WD = ['일', '월', '화', '수', '목', '금', '토'];

export default function ClubPass() {
  const df = useDisplayFont();
  const { sid, clubName } = useLocalSearchParams<{ sid: string; clubName?: string }>();
  const [sess, setSess] = useState<ClubSessionDetail | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    if (sid) fetchClubSession(sid).then(setSess).catch(() => {});
  }, [sid]);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  if (!sess) {
    return (
      <View style={[s.stage, { alignItems: 'center', justifyContent: 'center' }]}>
        <Text style={{ fontSize: 14.5, color: colors.nightDim }}>불러오는 중...</Text>
      </View>
    );
  }

  const myIdx = sess.people.findIndex((p) => p.isMe);
  const me = myIdx >= 0 ? sess.people[myIdx] : null;
  const bib = myIdx >= 0 ? String(myIdx + 1).padStart(3, '0') : '—';
  const teamOf = me?.dogName ? 'TEAM OF 2 (YOU + DOG)' : 'TEAM OF 1';
  const d = new Date(sess.scheduledAt);
  const checked = sess.myAttendance === 'checked_in';
  const startMs = d.getTime();
  const inWindow = Date.now() >= startMs - 2 * 3600_000 && Date.now() <= startMs + 6 * 3600_000;

  const doCheckin = async () => {
    setBusy(true);
    try {
      await checkinClubSession(sess.id);
      haptic('success');
      load();
    } catch (e) {
      Alert.alert('체크인', (e as Error).message.includes('checkin_window') ? '체크인은 시작 2시간 전부터 가능해요' : (e as Error).message);
    } finally { setBusy(false); }
  };

  return (
    <View style={s.stage}>
      <ScrollView contentContainerStyle={{ padding: 18, paddingTop: 58, paddingBottom: 40, flexGrow: 1, justifyContent: 'center' }}>
        <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 20, color: '#fff' }}>‹</Text></Pressable>

        <View style={s.ticket}>
          <View style={s.neonEdge} />

          {/* 상단 — ADMIT + 빕 */}
          <View style={s.top}>
            <View style={{ flex: 1 }}>
              <Text style={s.kicker}>ADMIT — {teamOf}</Text>
              <Text style={[{ fontSize: 25, fontWeight: '900', color: '#fff', marginTop: 5 }, df]} numberOfLines={1}>
                {clubName || '하이클럽'}
              </Text>
              <Text style={{ fontSize: 12.5, color: colors.nightDim, marginTop: 3 }}>
                호스트 {sess.hostName ?? '—'} 러너 · HIGH-VERIFIED
              </Text>
            </View>
            <View style={s.bibBox}>
              <Text style={{ fontSize: 8.5, letterSpacing: 2, fontWeight: '700', color: colors.nightDim }}>BIB</Text>
              <Text style={{ fontSize: 21, fontWeight: '900', color: colors.neon, fontVariant: ['tabular-nums'] }}>{bib}</Text>
            </View>
          </View>

          {/* 절취선 + 다이아 노치 */}
          <View style={s.perf}>
            <View style={[s.notch, { left: -7 }]} />
            <View style={s.dash} />
            <View style={[s.notch, { right: -7 }]} />
          </View>

          {/* 메타 그리드 (D2) */}
          <Row style={s.grid}>
            <View style={[s.cell, { borderRightWidth: 1 }]}>
              <Text style={s.cellK}>DATE</Text>
              <Text style={s.cellV}>{WD[d.getDay()]} {String(d.getHours()).padStart(2, '0')}:{String(d.getMinutes()).padStart(2, '0')}</Text>
            </View>
            <View style={s.cell}>
              <Text style={s.cellK}>MEET</Text>
              <Text style={s.cellV} numberOfLines={1}>{sess.meetupPoint}</Text>
            </View>
          </Row>

          {/* 홀더 — 내 팀 */}
          <View style={{ paddingHorizontal: 16, paddingTop: 13 }}>
            <Text style={s.cellK}>TEAM</Text>
            <Text style={[{ fontSize: 27, fontWeight: '900', color: '#fff', marginTop: 3 }, df]} numberOfLines={1}>
              {me ? `${me.name}${me.dogName ? ` + ${me.dogName}` : ''}` : '참가자 아님'}
            </Text>
          </View>

          {/* 상태 — RSVP / CHECKED 도장 */}
          <View style={{ paddingHorizontal: 16, paddingTop: 12, paddingBottom: 4, minHeight: 74, justifyContent: 'center' }}>
            {checked ? (
              <View style={s.checkedStamp}>
                <Text style={{ fontSize: 17, fontWeight: '900', letterSpacing: 3, color: colors.volt }}>CHECKED</Text>
                <Text style={{ fontSize: 8.5, fontWeight: '700', letterSpacing: 2, color: 'rgba(198,245,66,.75)', marginTop: 2 }}>ARRIVED · GOOD RUN 🐾</Text>
              </View>
            ) : me ? (
              inWindow ? (
                <Pressable onPress={doCheckin} disabled={busy} style={[s.checkinBtn, busy && { opacity: 0.5 }]}>
                  <Text style={{ fontSize: 15.5, fontWeight: '900', color: '#fff', letterSpacing: 1 }}>✓ 집결지 도착 체크인</Text>
                </Pressable>
              ) : (
                <Text style={{ fontSize: 12.5, color: colors.nightDim, textAlign: 'center' }}>
                  RSVP ✓ — 체크인은 시작 2시간 전부터 열려요
                </Text>
              )
            ) : (
              <Text style={{ fontSize: 12.5, color: colors.nightDim, textAlign: 'center' }}>이 세션의 참가자가 아니에요</Text>
            )}
          </View>

          {/* 바코드 */}
          <Row style={s.bars}>
            {Array.from({ length: 32 }).map((_, i) => (
              <View key={i} style={{ width: i % 3 === 0 ? 3.5 : 2, height: i % 4 === 0 ? '58%' : '100%', backgroundColor: colors.nightDim }} />
            ))}
          </Row>
          <Text style={s.serial}>DOGS HIGH · {sess.id.slice(0, 8).toUpperCase()}</Text>
        </View>

        <Text style={{ fontSize: 12, color: colors.nightDim, textAlign: 'center', marginTop: 14 }}>
          집결지에서 호스트에게 이 화면을 보여주세요
        </Text>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  stage: { flex: 1, backgroundColor: colors.nightBg },
  backBtn: { position: 'absolute', top: 56, left: 16, width: 40, height: 40, borderRadius: 6, backgroundColor: colors.nightCard, borderWidth: 1, borderColor: colors.nightEdge, alignItems: 'center', justifyContent: 'center', zIndex: 2 },
  ticket: { backgroundColor: colors.nightCard, borderRadius: 6, borderWidth: 1, borderColor: colors.nightEdge, overflow: 'hidden', paddingBottom: 14 },
  neonEdge: { position: 'absolute', left: 0, top: 0, bottom: 0, width: 3, backgroundColor: colors.neon, zIndex: 2 },
  top: { flexDirection: 'row', gap: 12, padding: 16, paddingLeft: 19, alignItems: 'flex-start' },
  kicker: { fontSize: 9.5, fontWeight: '700', letterSpacing: 3, color: colors.neon },
  bibBox: { borderWidth: 1, borderColor: colors.nightEdge, borderRadius: 4, paddingVertical: 6, paddingHorizontal: 12, alignItems: 'center', backgroundColor: '#1B1536' },
  perf: { flexDirection: 'row', alignItems: 'center', height: 14, marginVertical: 2 },
  dash: { flex: 1, borderTopWidth: 1, borderStyle: 'dashed', borderColor: '#3A3168', marginHorizontal: 10 },
  notch: { position: 'absolute', width: 14, height: 14, backgroundColor: colors.nightBg, transform: [{ rotate: '45deg' }] },
  grid: { marginHorizontal: 16, borderWidth: 1, borderColor: colors.nightEdge, marginTop: 8 },
  cell: { flex: 1, paddingVertical: 9, paddingHorizontal: 11, borderColor: colors.nightEdge },
  cellK: { fontSize: 8.5, letterSpacing: 2, fontWeight: '700', color: colors.nightDim },
  cellV: { fontSize: 15, fontWeight: '800', color: '#fff', marginTop: 3 },
  checkinBtn: { backgroundColor: colors.club, borderRadius: 6, borderWidth: 1.2, borderColor: colors.neon, alignItems: 'center', paddingVertical: 14, shadowColor: colors.neon, shadowOpacity: 0.45, shadowRadius: 12, shadowOffset: { width: 0, height: 0 } },
  checkedStamp: { alignSelf: 'center', borderWidth: 2.5, borderColor: colors.volt, borderRadius: 6, paddingVertical: 8, paddingHorizontal: 18, transform: [{ rotate: '-7deg' }], alignItems: 'center', backgroundColor: 'rgba(198,245,66,.06)' },
  bars: { gap: 2, alignItems: 'flex-end', height: 26, marginTop: 10, marginHorizontal: 16, opacity: 0.75 },
  serial: { fontSize: 8.5, letterSpacing: 2.5, fontWeight: '700', color: colors.nightDim, marginTop: 6, marginLeft: 16 },
});
