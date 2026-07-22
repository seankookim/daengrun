import { router } from 'expo-router';
import { Alert, Pressable, ScrollView, Text, View } from 'react-native';
import { BottomNav, homePath } from '../src/components/bottomnav';
import { RunCard } from '../src/components/runcard';
import { Row, text } from '../src/components/ui';
import { myCards, ownerGearLadder, session } from '../src/store';
import { colors } from '../src/theme';
import { useTheme } from '../src/theme-context';

// 마이 카드 — collectible run + milestone cards. Shared by both roles.

export default function Cards() {
  const { mode, p } = useTheme();
  const unlocked = myCards.filter((c) => !c.locked);
  const locked = myCards.filter((c) => c.locked);

  return (
    <View style={{ flex: 1, backgroundColor: p.bg }}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 30 }}>
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

        {/* 콜라보 기어 사다리 — 반려견 누적 km 마일스톤 (owner) */}
        {session.role === 'owner' && (
          <>
            <Text style={[text.h2, { marginTop: 26, marginBottom: 4, color: p.textStrong }]}>마일스톤 리워드</Text>
            <Text style={{ fontSize: 12, color: p.dim, marginBottom: 12 }}>
              초코의 누적 86.2km — 달릴수록 콜라보 굿즈가 열려요
            </Text>
            <View style={{ backgroundColor: p.card, borderRadius: 18, paddingHorizontal: 15, paddingVertical: 4, borderWidth: 1, borderColor: p.line }}>
              {ownerGearLadder.map((g, i) => (
                <View key={g.at}>
                  {i > 0 && <View style={{ height: 1, backgroundColor: p.line, opacity: 0.6 }} />}
                  <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 12 }}>
                    <View style={{
                      width: 20, height: 20, borderRadius: 10, alignItems: 'center', justifyContent: 'center',
                      backgroundColor: g.got ? '#6aa53c' : g.claimable ? colors.volt : p.chip,
                    }}>
                      {g.got && <Text style={{ fontSize: 9, fontWeight: '900', color: '#fff' }}>✓</Text>}
                      {g.claimable && <Text style={{ fontSize: 9, fontWeight: '900', color: '#132117' }}>!</Text>}
                    </View>
                    <View style={{ flex: 1 }}>
                      <Text style={{ fontSize: 13.5, fontWeight: '800', color: g.got || g.claimable ? p.textStrong : p.dim }}>{g.item}</Text>
                      <Text style={{ fontSize: 10.5, color: p.dim, marginTop: 1 }}>누적 {g.at}km</Text>
                    </View>
                    {g.claimable ? (
                      <Pressable
                        onPress={() => Alert.alert('수령 신청', '배송지로 콜라보 굿즈를 보내드려요 (목업)')}
                        style={{ backgroundColor: colors.volt, borderRadius: 99, paddingVertical: 7, paddingHorizontal: 12 }}
                      >
                        <Text style={{ fontSize: 11, fontWeight: '900', color: '#132117' }}>수령하기</Text>
                      </Pressable>
                    ) : g.got ? (
                      <Text style={{ fontSize: 10.5, fontWeight: '700', color: '#5a7a3c' }}>수령 완료</Text>
                    ) : (
                      <Text style={{ fontSize: 10.5, color: p.dim }}>{(g.at - 86.2).toFixed(0)}km 남음</Text>
                    )}
                  </View>
                </View>
              ))}
            </View>
          </>
        )}
      </ScrollView>
      <BottomNav dark={mode === 'dark'} />
    </View>
  );
}
