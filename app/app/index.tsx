import { router } from 'expo-router';
import { useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { Btn } from '../src/components/ui';
import { colors } from '../src/theme';

type Role = 'owner' | 'runner' | null;

export default function RoleSelect() {
  const [role, setRole] = useState<Role>(null);

  const start = () => {
    if (role === 'owner') router.push('/home');
    // runner flow: 다음 마일스톤
  };

  return (
    <View style={s.root}>
      <View style={s.hero}>
        <Text style={s.big}>
          우리 개는{'\n'}
          <Text style={{ color: colors.cream }}>오늘도</Text>
          {'\n'}달린다
        </Text>
        <Text style={s.sub}>바쁜 당신 대신, 검증된 러너가{'\n'}반려견과 함께 달립니다.</Text>
      </View>

      <View style={{ gap: 12 }}>
        <Pressable
          style={[s.roleCard, { backgroundColor: colors.volt }, role === 'owner' && s.sel]}
          onPress={() => setRole('owner')}
        >
          <Text style={[s.roleTitle, { color: colors.ink }]}>보호자예요</Text>
          <Text style={[s.roleDesc, { color: colors.ink }]}>믿을 수 있는 러너에게 맡겨요</Text>
        </Pressable>
        <Pressable
          style={[s.roleCard, { backgroundColor: '#2c3020' }, role === 'runner' && s.sel]}
          onPress={() => setRole('runner')}
        >
          <Text style={[s.roleTitle, { color: colors.volt }]}>러너예요</Text>
          <Text style={[s.roleDesc, { color: colors.cream }]}>달리면서 수익도 얻어요 (준비 중)</Text>
        </Pressable>
      </View>

      <Btn
        label={role ? '시작하기' : '역할을 선택하세요'}
        variant="volt"
        disabled={!role || role === 'runner'}
        onPress={start}
        style={{ marginTop: 20, marginBottom: 24 }}
      />
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.ink, padding: 26, justifyContent: 'flex-end' },
  hero: { marginBottom: 36 },
  big: { fontSize: 56, lineHeight: 60, fontWeight: '900', color: colors.volt },
  sub: { marginTop: 16, fontSize: 15, lineHeight: 24, color: '#b9b6a4' },
  roleCard: { borderRadius: 24, padding: 22, borderWidth: 2, borderColor: 'transparent' },
  sel: { borderColor: colors.tang },
  roleTitle: { fontSize: 24, fontWeight: '800' },
  roleDesc: { fontSize: 13, marginTop: 4, opacity: 0.75 },
});
