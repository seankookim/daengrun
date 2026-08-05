import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { BottomNav, homePath } from '../src/components/bottomnav';
import { PatchBadge, worldOf } from '../src/components/patch';
import { Row, text } from '../src/components/ui';
import { CoursePatch, fetchCoursePatches } from '../src/lib/api';
import { session } from '../src/store';
import { useTheme } from '../src/theme-context';

// 마이 카드 — 코스 패치 월(파생 실데이터). Shared by both roles.
// [정직 수리 2026-08-05] 목업 카드 6장(myCards — 조작 기록 5.02km·가짜 스트릭·없는 한강 시리즈) 퇴역.
// 이 화면은 이제 실파생 패치 월 하나만 말한다. 스탬프 택소노미는 리워드 ② 랩에서 결정 후 합류.

const GRADE_LABEL: Record<string, string> = { basic: '획득', silver: '실버', gold: '골드', master: '마스터' };
const nextGrade = (n: number) => (n < 5 ? `실버까지 ${5 - n}회` : n < 10 ? `골드까지 ${10 - n}회` : n < 25 ? `마스터까지 ${25 - n}회` : '코스 마스터 👑');

export default function Cards() {
  const { mode, p } = useTheme();
  // 코스 패치 월 (2026-07-28) — ×1 획득 → ×5 실버 → ×10 골드 → ×25 마스터
  const [patches, setPatches] = useState<{ earned: CoursePatch[]; locked: { routeId: string; name: string; km: number }[] } | null>(null);
  useEffect(() => {
    fetchCoursePatches().then(setPatches).catch((e) => console.warn('[cards] patches:', e?.message ?? e));
  }, []);

  return (
    <View style={{ flex: 1, backgroundColor: p.bg }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 30 }}>
        <Row style={{ justifyContent: 'space-between', marginBottom: 4 }}>
          <Pressable onPress={() => router.replace(homePath())}><Text style={{ fontSize: 27.5, color: p.textStrong }}>‹</Text></Pressable>
          <Text style={[text.h2, { color: p.textStrong }]}>마이 카드</Text>
          <View style={{ width: 24 }} />
        </Row>
        <Text style={{ fontSize: 14, color: p.dim, textAlign: 'center', marginBottom: 16 }}>
          {session.role === 'runner' ? '러닝으로 쌓은 나의 기록' : '초코가 달려서 모은 패치'}
        </Text>

        {/* ---------- 코스 패치 월 — 첫 완주마다 획득, 5/10/25 승급 (드랍 리듬 동기) ---------- */}
        {patches && (patches.earned.length > 0 || patches.locked.length > 0) && (
          <View style={{ backgroundColor: p.card, borderRadius: 6, padding: 16, borderWidth: 1, borderColor: p.line, marginBottom: 20 }}>
            <Row style={{ justifyContent: 'space-between', marginBottom: 2 }}>
              <Text style={{ fontSize: 17, fontWeight: '900', color: p.textStrong }}>코스 패치</Text>
              <Text style={{ fontSize: 14, fontWeight: '800', color: '#7FA818' }}>
                {patches.earned.length}/{patches.earned.length + patches.locked.length}
              </Text>
            </Row>
            <Text style={{ fontSize: 14, color: p.dim, marginBottom: 14 }}>
              거리마다 색 세계 — TRAIL·FOREST·RIVER·NIGHT·HALF · ×5 실버 · ×10 골드 · ×25 마스터
            </Text>
            <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 14, justifyContent: 'flex-start' }}>
              {patches.earned.map((pt) => (
                <Pressable key={pt.routeId} onPress={() => router.push(`/course/${pt.routeId}`)} style={{ alignItems: 'center', width: 92 }}>
                  <PatchBadge km={pt.km} name={pt.name} grade={pt.grade} size={84} />
                  <Text numberOfLines={1} style={{ fontSize: 14, fontWeight: '800', color: p.textStrong, marginTop: 7 }}>{pt.name}</Text>
                  <Text style={{ fontSize: 9.5, color: p.dim, marginTop: 1 }}>
                    {GRADE_LABEL[pt.grade]} · ×{pt.count} · {nextGrade(pt.count)}
                  </Text>
                </Pressable>
              ))}
              {patches.locked.map((pt) => (
                <Pressable key={pt.routeId} onPress={() => router.push(`/course/${pt.routeId}`)} style={{ alignItems: 'center', width: 92 }}>
                  {/* 잠긴 패치도 월드색 힌트 — '저 색을 갖고 싶다' (P2) */}
                  <View style={{
                    width: 84, height: 84, borderRadius: 42, borderWidth: 2, borderStyle: 'dashed',
                    borderColor: worldOf(pt.km).dim, alignItems: 'center', justifyContent: 'center',
                  }}>
                    <Text style={{ fontSize: 19, fontWeight: '900', color: worldOf(pt.km).tone, opacity: 0.75 }}>{pt.km}K</Text>
                    <Text style={{ fontSize: 7.5, fontWeight: '800', letterSpacing: 1.2, color: worldOf(pt.km).dim, marginTop: 1 }}>{worldOf(pt.km).label}</Text>
                  </View>
                  <Text numberOfLines={1} style={{ fontSize: 14, fontWeight: '800', color: p.dim, marginTop: 7 }}>{pt.name}</Text>
                  <Text style={{ fontSize: 9.5, color: p.dim, marginTop: 1 }}>완주하면 획득 ›</Text>
                </Pressable>
              ))}
            </View>
          </View>
        )}

      </ScrollView>
      <BottomNav dark={mode === 'dark'} />
    </View>
  );
}
