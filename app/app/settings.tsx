import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../src/auth-context';
import { Row } from '../src/components/ui';
import { fetchMyProfile, MyProfile } from '../src/lib/api';
import { session } from '../src/store';
import { colors } from '../src/theme';

// 설정 — 실화면. 가짜 하위메뉴 없음: 실계정 정보 + 실동작만, 나머지는 정직 라벨.

const FOREST = '#132117';
const APP_VERSION = '0.9 (파일럿)';

export default function Settings() {
  const { session: auth, signOut } = useAuth();
  const [profile, setProfile] = useState<MyProfile | null>(null);

  useEffect(() => {
    fetchMyProfile().then(setProfile).catch(() => {});
  }, []);

  return (
    <ScrollView style={{ flex: 1, backgroundColor: colors.cream }} contentContainerStyle={{ padding: 22, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between' }}>
        <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 18 }}>‹</Text></Pressable>
        <Text style={{ fontSize: 20, fontWeight: '900', color: FOREST }}>설정</Text>
        <View style={{ width: 40 }} />
      </Row>

      {/* 계정 (실정보) */}
      <Text style={s.section}>계정</Text>
      <View style={s.card}>
        <InfoRow label="이메일" value={auth?.user.email ?? '—'} />
        <View style={s.div} />
        <InfoRow label="이름" value={profile?.name ?? '—'} />
        <View style={s.div} />
        <InfoRow label="현재 모드" value={session.role === 'runner' ? '러너' : '보호자'} />
      </View>

      {/* 실동작 */}
      <View style={[s.card, { marginTop: 10 }]}>
        <Pressable onPress={() => router.dismissTo('/')} style={s.actionRow}>
          <Text style={s.actionText}>역할 전환 (보호자 ↔ 러너)</Text>
          <Text style={{ fontSize: 14, color: colors.dim }}>›</Text>
        </Pressable>
        <View style={s.div} />
        <Pressable
          onPress={() => Linking.openURL('mailto:seankookim@uchicago.edu?subject=댕런 문의')}
          style={s.actionRow}
        >
          <Text style={s.actionText}>문의하기</Text>
          <Text style={{ fontSize: 14, color: colors.dim }}>›</Text>
        </Pressable>
        <View style={s.div} />
        <Pressable
          onPress={async () => { await signOut(); router.dismissTo('/login'); }}
          style={s.actionRow}
        >
          <Text style={[s.actionText, { color: '#d84a2f' }]}>로그아웃</Text>
        </Pressable>
      </View>

      {/* 준비 중 — 정직 라벨 */}
      <Text style={s.section}>준비 중</Text>
      <View style={[s.card, { opacity: 0.55 }]}>
        <InfoRow label="결제 수단" value="PG 연동 후" />
        <View style={s.div} />
        <InfoRow label="알림 설정" value="푸시 도입 후" />
        <View style={s.div} />
        <InfoRow label="계정 삭제" value="문의로 처리" />
      </View>

      <Text style={{ fontSize: 10.5, color: colors.dim, textAlign: 'center', marginTop: 18 }}>
        댕런 {APP_VERSION} · 반려견 피트니스
      </Text>
    </ScrollView>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <Row style={{ justifyContent: 'space-between', paddingVertical: 12 }}>
      <Text style={{ fontSize: 13.5, color: '#3d453d' }}>{label}</Text>
      <Text style={{ fontSize: 13.5, fontWeight: '700', color: FOREST }} numberOfLines={1}>{value}</Text>
    </Row>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#eceadf' },
  section: { fontSize: 15, fontWeight: '900', color: FOREST, marginTop: 20, marginBottom: 8 },
  card: { backgroundColor: '#fff', borderRadius: 16, paddingHorizontal: 15, borderWidth: 1, borderColor: '#eceadf' },
  div: { height: 1, backgroundColor: '#f0eee3' },
  actionRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 14 },
  actionText: { fontSize: 14, fontWeight: '700', color: FOREST },
});
