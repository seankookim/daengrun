import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Image, Pressable, ScrollView, Text, View } from 'react-native';
import { Btn, Card, Row, text } from '../../src/components/ui';
import { DropRow, fetchDrops, uploadRunPhoto } from '../../src/lib/api';
import { MediaImage } from '../../src/lib/media';
import { runRequests, runResult } from '../../src/store';
import { colors } from '../../src/theme';

const fmt = (sec: number) =>
  `${Math.floor(sec / 60)}분 ${String(Math.floor(sec % 60)).padStart(2, '0')}초`;

export default function RunDone() {
  const req = runRequests[0];
  // 실드랍 — settle-run이 굴린 결과를 DB에서 읽는다 (목업 215회 은퇴, fake-inventory)
  const [pendingDrop, setPendingDrop] = useState<DropRow | null>(null);
  useEffect(() => {
    fetchDrops().then((ds) => setPendingDrop(ds.find((d) => !d.openedAt) ?? null)).catch(() => {});
  }, []);
  const [photos, setPhotos] = useState<string[]>([]);
  const [uploading, setUploading] = useState(false);

  // 오늘의 순간 — 러닝 사진이 보호자 리포트(공유 페이지)에 실린다
  const addPhoto = async () => {
    if (!runResult.bookingId) return;
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch {
      Alert.alert('개발 빌드 업데이트 필요', '사진 기능은 새 빌드에 포함돼요'); return;
    }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) { Alert.alert('사진 접근 권한이 필요해요'); return; }
      const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.7, base64: true });
      if (res.canceled || !res.assets?.[0]?.base64) return;
      setUploading(true);
      const next = await uploadRunPhoto(runResult.bookingId, res.assets[0].base64);
      setPhotos(next);
    } catch (e) {
      Alert.alert('업로드 실패', (e as Error).message);
    } finally {
      setUploading(false);
    }
  };

  return (
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ justifyContent: 'center', padding: 16, paddingTop: 70, paddingBottom: 40, flexGrow: 1 }}>
      <Text style={[text.h1, { textAlign: 'center' }]}>
        {runResult.completed ? '러닝 완료!' : '러닝 종료'}
      </Text>
      <Text style={[text.dim, { textAlign: 'center', marginTop: 8 }]}>
        {req.dogName}를 보호자에게 안전하게 인계해 주세요
      </Text>

      <Card dark style={{ marginTop: 24, alignItems: 'center', padding: 26 }}>
        <Text style={{ fontSize: 14, color: '#8fa093', letterSpacing: 2 }}>오늘의 수익</Text>
        <Text style={{ fontSize: 50.5, fontWeight: '900', color: colors.volt, marginTop: 8 }}>
          +{runResult.payout.toLocaleString()}원
        </Text>
        <Text style={{ fontSize: 14, color: '#8fa093', marginTop: 8 }}>
          {runResult.km.toFixed(2)}km · {fmt(runResult.sec)} · {req.dogName}
        </Text>
        {!runResult.completed && (
          <Text style={{ fontSize: 14, color: '#c9a15e', marginTop: 10, textAlign: 'center' }}>
            {runResult.reason === 'dog' && '컨디션 종료 — 실제 거리 정산 · 완주율 무영향\n상태 사진과 메모가 보호자에게 전달돼요'}
            {runResult.reason === 'owner' && '보호자 요청 종료 — 실제 거리 + 잔여 거리 50% 보장 포함'}
            {runResult.reason === 'runner' && '개인 사유 종료 — 실제 거리 정산 · 완주율에 반영돼요'}
            {!runResult.reason && '조기 종료 — 실제 뛴 거리만큼 정산됩니다'}
          </Text>
        )}
      </Card>

      {/* 오늘의 순간 — 사진이 보호자의 러닝 리포트에 실려요 (실예약만) */}
      {runResult.bookingId && (
        <View style={{
          marginTop: 14, backgroundColor: '#fff', borderRadius: 18, padding: 15,
          borderWidth: 1, borderColor: '#DCD6C4',
        }}>
          <Row style={{ justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 15.5, fontWeight: '900', color: '#0F1D13' }}>오늘의 순간</Text>
            <Text style={{ fontSize: 14, color: colors.dim }}>보호자 리포트에 실려요</Text>
          </Row>
          <Row style={{ gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
            {photos.map((url) => (
              /* [0064] uploadRunPhoto가 media 경로를 돌려준다 — 서명 URL로 렌더 */
              <MediaImage key={url} source={url} style={{ width: 64, height: 64, borderRadius: 10, backgroundColor: '#DCD6C4' }} />
            ))}
            {photos.length < 6 && (
              <Pressable
                onPress={addPhoto}
                disabled={uploading}
                style={{
                  width: 64, height: 64, borderRadius: 10, backgroundColor: '#f4f2ea',
                  alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: '#dde8c4', borderStyle: 'dashed',
                }}
              >
                <Text style={{ fontSize: 20.5, color: '#5a7a3c' }}>{uploading ? '…' : '＋'}</Text>
              </Pressable>
            )}
          </Row>
          <Text style={{ fontSize: 14, color: colors.dim, marginTop: 8 }}>
            {req.dogName}의 신나는 순간을 남겨주세요 — 보호자 만족도와 재지명율이 올라가요
          </Text>
        </View>
      )}

      {/* 실드랍 — 미오픈 드랍이 있을 때만, 오픈은 리워드 센터에서 */}
      {pendingDrop && (
        <Pressable
          onPress={() => router.push('/runner/rewards')}
          style={{
            marginTop: 14, borderRadius: 18, padding: 18, alignItems: 'center',
            backgroundColor: colors.ink, borderWidth: 1.5, borderColor: colors.volt,
            shadowColor: colors.volt, shadowOpacity: 0.35, shadowRadius: 7, shadowOffset: { width: 0, height: 3 },
          }}
        >
          <Text style={{ fontSize: 25.5 }}>{pendingDrop.kind === 'pick' ? '🎁' : '▣'}</Text>
          <Text style={{ fontSize: 16, fontWeight: '900', color: colors.volt, marginTop: 5 }}>
            {pendingDrop.runCountAt}회 달성 — {pendingDrop.kind === 'pick' ? '픽 드랍' : '보급 상자'} 도착!
          </Text>
          <Text style={{ fontSize: 14, color: '#8fa093', marginTop: 3 }}>리워드 센터에서 열기 ›</Text>
        </Pressable>
      )}

      <Text style={[text.dim, { textAlign: 'center', marginTop: 14 }]}>수익은 매주 수요일 정산됩니다</Text>
      <Btn label={`${req.dogName} 리뷰 남기기`} variant="volt" style={{ marginTop: 20 }} onPress={() => router.push('/runner/review')} />
      <Btn label="홈으로" style={{ marginTop: 8 }} onPress={() => router.dismissTo('/runner/home')} />
    </ScrollView>
  );
}
