import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useAuth } from '../src/auth-context';
import { DeleteAccountSheet } from '../src/components/delete-account-sheet';
import { Row } from '../src/components/ui';
import { fetchMyProfile, MyProfile } from '../src/lib/api';
import { session } from '../src/store';
import { colors, paper } from '../src/theme';

// 설정 — 실화면. 가짜 하위메뉴 없음: 실계정 정보 + 실동작만, 나머지는 정직 라벨.

// [2026-08-12 · Sean "remove forest"] 이 파일의 로컬 상수 FOREST = '#0F1D13' 은퇴. 은퇴된 스왈프/포레스트 팔레트의
// 마지막 잔재였고, 12개 파일에 각자 로컬 상수로 복사돼 있었다 (한 값에 주인 12명).
// paper.ink(#111111)로 접는다 — 색차는 사실상 안 보이고(둘 다 근처 검정), 그게 정확히 아무도
// 못 본 이유다. 다크 면에도 같은 토큰을 쓴다 — 캘린더 보드·정산 티켓·빕 스트랩이 이미 그런다.
const APP_VERSION = '0.9 (파일럿)';

export default function Settings() {
  const { session: auth, signOut } = useAuth();
  const [profile, setProfile] = useState<MyProfile | null>(null);
  const [deleteOpen, setDeleteOpen] = useState(false);

  useEffect(() => {
    fetchMyProfile().then(setProfile).catch(() => {});
  }, []);

  return (
    <ScrollView style={{ flex: 1, backgroundColor: colors.cream }} contentContainerStyle={{ paddingHorizontal: 11, paddingTop: 56, paddingBottom: 40 }}>
      <Row style={{ justifyContent: 'space-between' }}>
        <Pressable onPress={() => router.back()} style={s.backBtn}><Text style={{ fontSize: 20.5 }}>‹</Text></Pressable>
        <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>설정</Text>
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
          <Text style={{ fontSize: 16, color: colors.dim }}>›</Text>
        </Pressable>
        <View style={s.div} />
        {/* [charge slice 2026-08-13] 준비 중 카드의 '결제 수단 — PG 연동 후' InfoRow가 여기로 승격.
            실화면이 생겼다: 등록된 카드·청구 내역·실패한 청구의 재시도가 전부 서버 진실이다. */}
        <Pressable onPress={() => router.push('/payments')} style={s.actionRow}>
          <Text style={s.actionText}>결제 관리</Text>
          <Text style={{ fontSize: 16, color: colors.dim }}>›</Text>
        </Pressable>
        <View style={s.div} />
        <Pressable
          onPress={() => Linking.openURL('mailto:seankookim@uchicago.edu?subject=도그스하이 문의')}
          style={s.actionRow}
        >
          <Text style={s.actionText}>문의하기</Text>
          <Text style={{ fontSize: 16, color: colors.dim }}>›</Text>
        </Pressable>
        <View style={s.div} />
        <Pressable
          onPress={async () => { await signOut(); router.dismissTo('/login'); }}
          style={s.actionRow}
        >
          <Text style={[s.actionText, { color: '#d84a2f' }]}>로그아웃</Text>
        </Pressable>
        <View style={s.div} />
        {/* [O-6 2026-08-20] 계정 삭제는 '준비 중 · 문의로 처리' InfoRow에서 여기로 승격.
            App Store 5.1.1(v)는 인앱 개시를 요구한다 — 문의 메일은 개시가 아니고,
            비활성 카드 안의 회색 라벨은 '찾을 수 있는' 위치도 아니다 (계약 §C.2 1).
            로그아웃과 같은 코랄 잉크: 둘 다 세션을 끝내는 행이고, 무게 차이는 시트가 진다. */}
        <Pressable onPress={() => setDeleteOpen(true)} style={s.actionRow} accessibilityRole="button">
          <Text style={[s.actionText, { color: '#d84a2f' }]}>계정 삭제</Text>
          <Text style={{ fontSize: 16, color: colors.dim }}>›</Text>
        </Pressable>
      </View>

      {/* DEV 전용 — 프로덕션 빌드에선 렌더되지 않음 (__DEV__ 게이트, 화면 자체도 이중 게이트) */}
      {__DEV__ && (
        <View style={[s.card, { marginTop: 10, borderColor: '#7B6CDF' }]}>
          <Pressable onPress={() => router.push('/dev/club-lab')} style={s.actionRow}>
            <Text style={[s.actionText, { color: '#4A3DA8' }]}>R2 커스터디 랩 (DEV)</Text>
            <Text style={{ fontSize: 16, color: colors.dim }}>›</Text>
          </Pressable>
        </View>
      )}

      {/* 준비 중 — 정직 라벨. 계정 삭제는 실동작이 되어 위 카드로 떠났다 (O-6). */}
      <Text style={s.section}>준비 중</Text>
      <View style={[s.card, { opacity: 0.55 }]}>
        <InfoRow label="알림 설정" value="푸시 도입 후" />
      </View>

      <Text style={{ fontSize: 14, color: colors.dim, textAlign: 'center', marginTop: 18 }}>
        도그스하이 {APP_VERSION} · 반려견 피트니스
      </Text>

      {/* 열려 있을 때만 마운트 — 시트의 상태(거절 문구·꾹 누름 확인)가 다음 열기로 새지 않는다 */}
      {deleteOpen && <DeleteAccountSheet onClose={() => setDeleteOpen(false)} />}
    </ScrollView>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <Row style={{ justifyContent: 'space-between', paddingVertical: 12 }}>
      <Text style={{ fontSize: 15.5, color: '#3d453d' }}>{label}</Text>
      <Text style={{ fontSize: 15.5, fontWeight: '700', color: paper.ink }} numberOfLines={1}>{value}</Text>
    </Row>
  );
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#DCD6C4' },
  section: { fontSize: 17, fontWeight: '900', color: paper.ink, marginTop: 20, marginBottom: 8 },
  card: { backgroundColor: '#fff', borderRadius: 16, paddingHorizontal: 15, borderWidth: 1, borderColor: '#DCD6C4' },
  div: { height: 1, backgroundColor: '#f0eee3' },
  actionRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 14 },
  actionText: { fontSize: 16, fontWeight: '700', color: paper.ink },
});
