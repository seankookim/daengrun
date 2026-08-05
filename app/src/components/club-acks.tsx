import { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { ackClub, ClubAck, fetchMyAcks } from '../lib/api';
import { haptic } from '../lib/haptics';
import { lilac, lilacRadius, lilacShadow } from '../theme';

// ⑤ 크리티컬 ack 배너 스택 (정본: decisions-lab ⑤ — Sean 확정)
// 글래스 크롬 아래, 심각도 정렬, 탭 한 번 = 확인. 확인 전까지 어느 클럽 화면에서든 따라온다.
// 30분 미확인 → 호스트 에스컬레이션은 서버 크론 몫 — 클라이언트는 그리기만 한다.
// [감사 P2] 다중 인스턴스(홈·셸·콘솔)가 각자 45초 폴 + 상태 로컬이라, 한 화면에서 확인해도 뒤 화면 배너가
// 45초 남던 것 — 모듈 레벨 단일 스토어 + 폴러 하나로 통합. 확인이 전 화면에 즉시 전파된다.

const L = lilac;

const CRIT_TITLES = new Set(['외부 커스터디 이양', '세션 취소', '세션 취소 — 전액 환불', '배정 불발 — 전액 환불', '이의 접수 — 전액 환불', '재검토 거절 — 전액 환불', '위탁 취소 — 전액 환불', '위탁 미진행 — 전액 환불']);

// ---------- 모듈 레벨 단일 스토어 ----------
let acksStore: ClubAck[] = [];
const busyIds = new Set<string>();
const listeners = new Set<(a: ClubAck[]) => void>();
let poller: ReturnType<typeof setInterval> | null = null;
let refCount = 0;

const emit = () => { for (const fn of listeners) fn(acksStore); };
const loadAcks = () => {
  fetchMyAcks()
    .then((list) => { acksStore = list.filter((a) => !busyIds.has(a.id)); emit(); })
    .catch(() => {});
};
const ackOne = (id: string) => {
  if (busyIds.has(id)) return;
  busyIds.add(id);
  acksStore = acksStore.filter((x) => x.id !== id); // 낙관 제거 — 전 인스턴스 즉시 반영
  emit();
  ackClub(id)
    .then(() => { haptic('light'); busyIds.delete(id); loadAcks(); })
    .catch(() => { busyIds.delete(id); loadAcks(); });
};
const subscribe = (fn: (a: ClubAck[]) => void) => {
  listeners.add(fn);
  refCount += 1;
  if (poller == null) { loadAcks(); poller = setInterval(loadAcks, 45_000); }
  return () => {
    listeners.delete(fn);
    refCount -= 1;
    if (refCount <= 0 && poller != null) { clearInterval(poller); poller = null; refCount = 0; }
  };
};

export function AckStack() {
  const [acks, setAcks] = useState<ClubAck[]>(acksStore);
  useEffect(() => subscribe(setAcks), []);

  if (acks.length === 0) return null;

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
            <Pressable onPress={() => ackOne(a.id)} style={s.btn} hitSlop={6}>
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
  title: { fontSize: 14, fontWeight: '800', color: L.head },
  body: { fontSize: 9.5, color: '#7a5a2a', marginTop: 2, lineHeight: 14 },
  btn: {
    backgroundColor: '#fff', borderRadius: 7, paddingVertical: 7, paddingHorizontal: 11,
    ...lilacShadow, shadowOpacity: 0.12, shadowRadius: 4,
  },
  btnTxt: { fontSize: 9.5, fontWeight: '700', letterSpacing: 1, color: L.amber },
});
