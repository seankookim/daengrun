import { router } from 'expo-router';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { BottomNav, homePath } from '../src/components/bottomnav';
import { RunCard } from '../src/components/runcard';
import { Row, text } from '../src/components/ui';
import { myCards, session } from '../src/store';
import { useTheme } from '../src/theme-context';

// 마이 카드 — collectible run + milestone cards. Shared by both roles.

export default function Cards() {
  const { mode, p } = useTheme();
  const unlocked = myCards.filter((c) => !c.locked);
  const locked = myCards.filter((c) => c.locked);

  return (
    <View style={{ flex: 1, backgroundColor: p.bg }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 16, paddingTop: 56, paddingBottom: 30 }}>
        <Row style={{ justifyContent: 'space-between', marginBottom: 4 }}>
          <Pressable onPress={() => router.replace(homePath())}><Text style={{ fontSize: 24, color: p.textStrong }}>‹</Text></Pressable>
          <Text style={[text.h2, { color: p.textStrong }]}>마이 카드</Text>
          <View style={{ width: 24 }} />
        </Row>
        <Text style={{ fontSize: 12, color: p.dim, textAlign: 'center', marginBottom: 16 }}>
          {session.role === 'runner' ? '러닝으로 쌓은 나의 기록' : '초코가 달려서 모은 카드'} · {unlocked.length}장 보유
        </Text>

        <View style={{ gap: 14, alignItems: 'center' }}>
          {unlocked.map((c) => <RunCard key={c.id} card={c} width={340} />)}
        </View>

        <Text style={[text.h2, { marginTop: 26, marginBottom: 4, color: p.textStrong }]}>다음 도전</Text>
        <Text style={{ fontSize: 12, color: p.dim, marginBottom: 12 }}>조건을 달성하면 카드가 열려요</Text>
        <View style={{ gap: 14, alignItems: 'center' }}>
          {locked.map((c) => <RunCard key={c.id} card={c} width={340} />)}
        </View>

        <View style={{ marginTop: 22, backgroundColor: p.card, borderRadius: 16, padding: 14, borderWidth: 1, borderColor: p.line }}>
          <Text style={{ fontSize: 12, color: p.dim, textAlign: 'center' }}>
            에픽 카드는 시리즈 코스 완주로만 얻을 수 있어요{'\n'}한강 시리즈: 뚝섬 → 잠원 → 반포 → 여의도
          </Text>
        </View>
      </ScrollView>
      <BottomNav dark={mode === 'dark'} />
    </View>
  );
}
