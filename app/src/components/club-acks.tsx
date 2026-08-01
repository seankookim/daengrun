import { useCallback, useEffect, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { ackClub, ClubAck, fetchMyAcks } from '../lib/api';
import { haptic } from '../lib/haptics';
import { lilac, lilacRadius, lilacShadow } from '../theme';

// ⑤ 크리티컬 ack 배너 스택 (정본: decisions-lab ⑤ — Sean 확정)
// 글래스 크롬 아래, 심각도 정렬, 탭 한 번 = 확인. 확인 전까지 어느 클럽 화면에서든 따라온다.
// 30분 미확인 → 호스트 에스컬레이션은 서버 크론 몫 — 클라이언트는 그리기만 한다.
// ⑥ 테이크오버는 기각됨 — 부활 금지 (모션 강등 로직은 우리가 쓰지 않는 죽은 코드).

const L = lilac;

// 코랄(크리티컬) 제목 — club_critical_titles 레지스트리 중 사고·이탈 계열. 나머지는 앰버.
const CRIT_TITLES = new Set(['외부 커스터디 이양', '세션 취소', '배정 불발 — 전액 환불', '이의 접수 — 전액 환불', '재검토 거절 — 전액 환불']);

export function AckStack() {
  const [acks, setAcks] = useState<ClubAck[]>([]);
  const busyIds = useRef(new Set<string>());

  const load = useCallback(() => { fetchMyAcks().then(setAcks).catch(() => {}); }, []);
  useEffect(() => {
    load();
    const t = setInterval(load, 45_000);
    return () => clearInterval(t);
  }, [load]);

  if (acks.length === 0) return null;

  const doAck = (a: ClubAck) => {
    if (busyIds.current.has(a.id)) return;
    busyIds.current.add(a.id);
    setAcks((prev) => prev.filter((x) => x.id !== a.id)); // 낙관 제거 — 실패 시 복원
    ackClub(a.id).then(() => haptic('light')).catch(() => { busyIds.current.delete(a.id); load(); });
  };

  const sorted = [...acks].sort((a, b) =>
    Number(CRIT_TITLES.has(b.title)) - Number(CRIT_TITLES.has(a.title))
    || b.createdAt.localeCompare(a.createdAt));

  return (
    <View>
      {sorted.map((a) => {
        const crit = CRIT_TITLES.has(a.title);
        return (
          <View key={a.id} style={[s.banner, crit && s.bannerCrit]}>
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text style={s.title}>{a.title}</Text>
              {!!a.body && <Text style={[s.body, crit && { color: '#a04a30' }]} numberOfLines={2}>{a.body}</Text>}
            </View>
            <Pressable onPress={() => doAck(a)} style={s.btn} hitSlop={6}>
              <Text style={[s.btnTxt, crit && { color: L.tang }]}>확인</Text>
            </Pressable>
          </View>
        );
      })}
    </View>
  );
}

const s = StyleSheet.create({
  banner: {
    flexDirection: 'row', alignItems: 'center', gap: 10,
    backgroundColor: L.amberSoft, borderWidth: 1, borderColor: L.amberEdge,
    borderRadius: lilacRadius.card, padding: 10, paddingHorizontal: 12, marginTop: 8,
    ...lilacShadow, shadowOpacity: 0.06,
  },
  bannerCrit: { backgroundColor: L.coralSoft, borderColor: '#F5C4B4' },
  title: { fontSize: 11.5, fontWeight: '800', color: L.head },
  body: { fontSize: 9.5, color: '#7a5a2a', marginTop: 2, lineHeight: 14 },
  btn: {
    backgroundColor: '#fff', borderRadius: 7, paddingVertical: 7, paddingHorizontal: 11,
    ...lilacShadow, shadowOpacity: 0.12, shadowRadius: 4,
  },
  btnTxt: { fontSize: 9.5, fontWeight: '700', letterSpacing: 1, color: L.amber },
});
