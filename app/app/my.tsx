import { router } from 'expo-router';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../src/auth-context';
import { BottomNav } from '../src/components/bottomnav';
import { Monogram, Row } from '../src/components/ui';
import { dog, session } from '../src/store';
import { colors } from '../src/theme';

// 마이 — stub for P1 (profile setup, 예약 관리, settings come later).
// For now: profile header + menu incl. 안심 센터 entry.

const FOREST = '#132117';

export default function My() {
  const isRunner = session.role === 'runner';
  const { session: auth, signOut } = useAuth();

  const MENU = [
    { glyph: '✚', label: '안심 센터', desc: 'SOS · 실시간 위치 · 보험', path: '/safety' as const },
    isRunner
      ? { glyph: '✓', label: '러너 인증 센터', desc: '지원 절차 · 등급 사다리 · 교육', path: '/runner/apply' as const }
      : { glyph: '⌂', label: '주소 관리', desc: '픽업 장소 · 공동현관 정보', path: '/owner/addresses' as const },
    { glyph: '▦', label: '예약 관리', desc: '다가오는 일정과 지난 예약', path: isRunner ? null : ('/owner/schedule' as const) },
    { glyph: '⌗', label: isRunner ? '내 러닝 기록' : `${dog.name}의 기록`, desc: '마이 카드 · 러닝 히스토리', path: '/cards' as const },
    { glyph: '◔', label: '알림', desc: '알림 확인 및 설정', path: '/alerts' as const },
    { glyph: '⚙', label: '설정', desc: '계정 · 결제 수단 · 보안', path: null },
  ];

  return (
    <View style={{ flex: 1, backgroundColor: colors.cream }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 64, paddingBottom: 24 }}>
        <Text style={s.h1}>마이</Text>

        {/* profile header */}
        <View style={s.profile}>
          <Monogram char={isRunner ? '민' : dog.name[0]} bg={isRunner ? '#FF6347' : colors.volt} size={56} />
          <View style={{ flex: 1, marginLeft: 14 }}>
            <Text style={{ fontSize: 17, fontWeight: '900', color: FOREST }}>
              {isRunner ? '김민준 러너' : `${dog.name} 보호자님`}
            </Text>
            <Text style={{ fontSize: 12, color: colors.dim, marginTop: 3 }}>
              {isRunner ? '신원인증 · 펫보험 가입' : `${dog.name} · ${dog.breed} · 성수동`}
            </Text>
          </View>
          <Pressable style={s.editBtn} onPress={() => Alert.alert('프로필', '프로필 설정 (P1 예정)')}>
            <Text style={{ fontSize: 11, fontWeight: '700', color: '#3d453d' }}>프로필 설정</Text>
          </Pressable>
        </View>

        {/* menu */}
        <View style={{ gap: 10, marginTop: 16 }}>
          {MENU.map((m) => (
            <Pressable
              key={m.label}
              style={s.menuRow}
              onPress={() => (m.path ? router.push(m.path) : Alert.alert(m.label, '준비 중이에요'))}
            >
              <View style={s.menuIcon}><Text style={{ fontSize: 15, color: '#5a7a3c' }}>{m.glyph}</Text></View>
              <View style={{ flex: 1 }}>
                <Text style={{ fontSize: 14.5, fontWeight: '800', color: FOREST }}>{m.label}</Text>
                <Text style={{ fontSize: 11.5, color: colors.dim, marginTop: 2 }}>{m.desc}</Text>
              </View>
              <Text style={{ fontSize: 16, color: colors.dim }}>›</Text>
            </Pressable>
          ))}
        </View>

        <Pressable style={s.roleSwitch} onPress={() => router.dismissTo('/')}>
          <Text style={{ fontSize: 12.5, fontWeight: '700', color: '#5d655d' }}>역할 전환 (보호자 ↔ 러너)</Text>
        </Pressable>
        <Pressable
          style={s.roleSwitch}
          onPress={async () => { await signOut(); router.dismissTo('/login'); }}
        >
          <Text style={{ fontSize: 12.5, fontWeight: '700', color: '#d84a2f' }}>
            로그아웃{auth?.user.email ? ` (${auth.user.email})` : ''}
          </Text>
        </Pressable>
      </ScrollView>
      <BottomNav />
    </View>
  );
}

const s = StyleSheet.create({
  h1: { fontSize: 30, fontWeight: '900', color: FOREST },
  profile: {
    flexDirection: 'row', alignItems: 'center', backgroundColor: '#fff',
    borderRadius: 20, padding: 16, borderWidth: 1, borderColor: '#eceadf', marginTop: 16,
  },
  editBtn: { backgroundColor: '#f4f2ea', borderRadius: 99, paddingVertical: 7, paddingHorizontal: 11 },
  menuRow: {
    flexDirection: 'row', alignItems: 'center', gap: 12,
    backgroundColor: '#fff', borderRadius: 18, padding: 15, borderWidth: 1, borderColor: '#eceadf',
  },
  menuIcon: { width: 40, height: 40, borderRadius: 12, backgroundColor: '#eef4e0', alignItems: 'center', justifyContent: 'center' },
  roleSwitch: { alignItems: 'center', marginTop: 20, padding: 12 },
});
