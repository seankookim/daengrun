import { router } from 'expo-router';
import { useState } from 'react';
import { Alert, Image, Pressable, ScrollView, Text, View } from 'react-native';
import { Btn, Card, Row, text } from '../../src/components/ui';
import { uploadRunPhoto } from '../../src/lib/api';
import { currentDrop, rewardStatus, runRequests, runResult } from '../../src/store';
import { colors } from '../../src/theme';

const fmt = (sec: number) =>
  `${Math.floor(sec / 60)}분 ${String(Math.floor(sec % 60)).padStart(2, '0')}초`;

export default function RunDone() {
  const req = runRequests[0];
  const dropDue = rewardStatus.totalRuns % 5 === 0; // 이번 러닝으로 보급 드랍
  const [opened, setOpened] = useState(false);
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
    <ScrollView style={{ flex: 1 }} contentContainerStyle={{ justifyContent: 'center', padding: 22, paddingTop: 70, paddingBottom: 40, flexGrow: 1 }}>
      <Text style={[text.h1, { textAlign: 'center' }]}>
        {runResult.completed ? '러닝 완료!' : '러닝 종료'}
      </Text>
      <Text style={[text.dim, { textAlign: 'center', marginTop: 8 }]}>
        {req.dogName}를 보호자에게 안전하게 인계해 주세요
      </Text>

      <Card dark style={{ marginTop: 24, alignItems: 'center', padding: 26 }}>
        <Text style={{ fontSize: 12, color: '#8fa093', letterSpacing: 2 }}>오늘의 수익</Text>
        <Text style={{ fontSize: 44, fontWeight: '900', color: colors.volt, marginTop: 8 }}>
          +{runResult.payout.toLocaleString()}원
        </Text>
        <Text style={{ fontSize: 12, color: '#8fa093', marginTop: 8 }}>
          {runResult.km.toFixed(2)}km · {fmt(runResult.sec)} · {req.dogName}
        </Text>
        {!runResult.completed && (
          <Text style={{ fontSize: 11, color: '#c9a15e', marginTop: 10, textAlign: 'center' }}>
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
          borderWidth: 1, borderColor: '#eceadf',
        }}>
          <Row style={{ justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 13.5, fontWeight: '900', color: '#132117' }}>오늘의 순간</Text>
            <Text style={{ fontSize: 10.5, color: colors.dim }}>보호자 리포트에 실려요</Text>
          </Row>
          <Row style={{ gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
            {photos.map((url) => (
              <Image key={url} source={{ uri: url }} style={{ width: 64, height: 64, borderRadius: 10, backgroundColor: '#e2e0d4' }} />
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
                <Text style={{ fontSize: 18, color: '#5a7a3c' }}>{uploading ? '…' : '＋'}</Text>
              </Pressable>
            )}
          </Row>
          <Text style={{ fontSize: 10, color: colors.dim, marginTop: 8 }}>
            {req.dogName}의 신나는 순간을 남겨주세요 — 보호자 만족도와 재지명율이 올라가요
          </Text>
        </View>
      )}

      {/* 보급 드랍 — every 5th run */}
      {dropDue && (
        <Pressable
          onPress={() => (opened ? router.push('/runner/rewards') : setOpened(true))}
          style={{
            marginTop: 14, borderRadius: 18, padding: 18, alignItems: 'center',
            backgroundColor: opened ? '#eef4e0' : colors.ink,
            borderWidth: 1.5, borderColor: opened ? '#a9c47e' : colors.volt,
            shadowColor: colors.volt, shadowOpacity: 0.35, shadowRadius: 12, shadowOffset: { width: 0, height: 3 },
          }}
        >
          {opened ? (
            <>
              <Text style={{ fontSize: 13, fontWeight: '900', color: '#3d5a2b' }}>보급 상자 오픈!</Text>
              <Text style={{ fontSize: 17, fontWeight: '900', color: '#132117', marginTop: 6 }}>
                +{currentDrop.miles} 댕마일 · 카드 「{currentDrop.card}」
              </Text>
              <Text style={{ fontSize: 10.5, color: '#75806f', marginTop: 5 }}>리워드 센터에서 확인 ›</Text>
            </>
          ) : (
            <>
              <Text style={{ fontSize: 22 }}>▣</Text>
              <Text style={{ fontSize: 14, fontWeight: '900', color: colors.volt, marginTop: 5 }}>
                {rewardStatus.totalRuns}회 달성 — 보급 상자 도착!
              </Text>
              <Text style={{ fontSize: 10.5, color: '#8fa093', marginTop: 3 }}>탭해서 열기</Text>
            </>
          )}
        </Pressable>
      )}

      <Text style={[text.dim, { textAlign: 'center', marginTop: 14 }]}>수익은 매주 수요일 정산됩니다</Text>
      <Btn label={`${req.dogName} 리뷰 남기기`} variant="volt" style={{ marginTop: 20 }} onPress={() => router.push('/runner/review')} />
      <Btn label="홈으로" style={{ marginTop: 8 }} onPress={() => router.dismissTo('/runner/home')} />
    </ScrollView>
  );
}
