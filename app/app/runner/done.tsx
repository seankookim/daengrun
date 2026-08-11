import { router } from 'expo-router';
import { useEffect, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { Icon, Row } from '../../src/components/ui';
import { DropRow, fetchDrops, fetchMeetupInfo, uploadRunPhoto } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { MediaImage } from '../../src/lib/media';
import { runResult } from '../../src/store';
import { colors, layout, paper } from '../../src/theme';

// 러닝 완료 — the completion Peak (§7b Peak-End: exempt from minimization).
// [paper repaint 2026-08-11] cream/rounded legacy scrapped → paper chrome. The payout
// receipt stays a DARK artifact (paper.ink face, volt money numeral — dark is the
// artifact, light is the screen), now sharp-cornered with an Oswald numeral (BUG A
// lineHeight). The drop banner keeps its ink+volt ceremony face (glow shadow retired —
// nothing floats). Buttons → PaperBtn matrix: 리뷰 = the one primary, 홈으로 secondary.
// Behavior frozen: fetchDrops/addPhoto/uploadRunPhoto, photo cap 6, all routes.

const fmt = (sec: number) =>
  `${Math.floor(sec / 60)}분 ${String(Math.floor(sec % 60)).padStart(2, '0')}초`;

export default function RunDone() {
  const df = useDisplayFont(); // display font — celebration headline (1/screen budget)
  const nf = useNumFont();     // Oswald — payout numeral
  // Real dog name — settle put it on runResult from the booking context; if that never
  // loaded, re-read the settled booking once. If the name is genuinely unknown (or the
  // server's own generic '반려견' placeholder), the copy names no dog — never a fake one.
  const realName = (n: string | null | undefined) => (n && n !== '반려견' ? n : null);
  const [dogName, setDogName] = useState<string | null>(realName(runResult.dogName));
  useEffect(() => {
    if (!realName(runResult.dogName) && runResult.bookingId) {
      fetchMeetupInfo(runResult.bookingId)
        .then((i) => setDogName(realName(i.dogName)))
        .catch((e) => console.warn('[done] dogName:', (e as Error)?.message)); // unknown → generic wording stays
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
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
    <ScrollView
      style={{ flex: 1, backgroundColor: paper.canvas }}
      contentContainerStyle={{ justifyContent: 'center', paddingHorizontal: layout.gutter, paddingTop: 70, paddingBottom: 40, flexGrow: 1 }}
    >
      <Text style={[{ fontSize: 32, fontWeight: '900', color: paper.ink, textAlign: 'center' }, df]}>
        {runResult.completed ? '러닝 완료!' : '러닝 종료'}
      </Text>
      <Text style={{ fontSize: 14, lineHeight: 19, color: paper.dim, textAlign: 'center', marginTop: 8 }}>
        {dogName ? `${dogName}를 보호자에게 안전하게 인계해 주세요` : '반려견을 보호자에게 안전하게 인계해 주세요'}
      </Text>

      {/* 정산 영수증 — dark artifact face (sharp, ink), volt money numeral */}
      <View style={s.receipt}>
        {/* [2026-08-11] 정산 성공 여부가 이 낱말을 정한다. 서버가 확정한 금액만 '수익'이고,
            정산이 실패해 러너가 '나중에 (추정치 표시)'를 고른 경우는 클라이언트 추정치다 —
            그걸 수익이라 부르는 순간 앱이 못 지킬 돈을 약속한 것이 된다. */}
        <Text style={{ fontSize: 14, lineHeight: 18, color: '#BBBBBB' }}>
          {runResult.settled ? '오늘의 수익' : '예상 수익 (정산 미완료)'}
        </Text>
        {/* Oswald payout — lineHeight 63 = 1.25× (BUG A) */}
        <Text style={[{ fontSize: 50.5, lineHeight: 63, fontWeight: '900', color: colors.volt, marginTop: 8, fontVariant: ['tabular-nums'] as const }, nf]}>
          +{runResult.payout.toLocaleString()}원
        </Text>
        <Text style={{ fontSize: 14, lineHeight: 18, color: '#BBBBBB', marginTop: 8 }}>
          {runResult.km.toFixed(2)}km · {fmt(runResult.sec)}{dogName ? ` · ${dogName}` : ''}
        </Text>
        {!runResult.settled && (
          <Text style={{ fontSize: 14, lineHeight: 19, color: '#e0a06a', marginTop: 10, textAlign: 'center' }}>
            정산이 아직 서버에 반영되지 않았어요 — 이 숫자는 앱이 계산한 추정치예요.{'\n'}
            예약은 진행 중으로 남아 있어요. 러닝 화면에서 다시 정산하면 실제 금액으로 확정돼요.
          </Text>
        )}
        {!runResult.completed && (
          <Text style={{ fontSize: 14, lineHeight: 19, color: '#c9a15e', marginTop: 10, textAlign: 'center' }}>
            {runResult.reason === 'dog' && '컨디션 종료 — 실제 거리 정산 · 완주율 무영향\n상태 사진과 메모가 보호자에게 전달돼요'}
            {runResult.reason === 'owner' && '보호자 요청 종료 — 실제 거리 + 잔여 거리 50% 보장 포함'}
            {runResult.reason === 'runner' && '개인 사유 종료 — 실제 거리 정산 · 완주율에 반영돼요'}
            {!runResult.reason && '조기 종료 — 실제 뛴 거리만큼 정산됩니다'}
          </Text>
        )}
      </View>

      {/* 오늘의 순간 — 사진이 보호자의 러닝 리포트에 실려요 (실예약만) */}
      {runResult.bookingId && (
        <View style={s.photoCard}>
          <Row style={{ justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 15.5, fontWeight: '800', color: paper.ink }}>오늘의 순간</Text>
            <Text style={{ fontSize: 14, color: paper.dim }}>보호자 리포트에 실려요</Text>
          </Row>
          <Row style={{ gap: 8, marginTop: 10, flexWrap: 'wrap' }}>
            {photos.map((url) => (
              /* [0064] uploadRunPhoto가 media 경로를 돌려준다 — 서명 URL로 렌더 */
              <MediaImage key={url} source={url} style={{ width: 64, height: 64, borderRadius: 0, backgroundColor: '#EEEEEE' }} />
            ))}
            {photos.length < 6 && (
              <Pressable
                onPress={addPhoto}
                disabled={uploading}
                style={s.addTile}
                accessibilityRole="button"
                accessibilityLabel="사진 추가"
              >
                <Text style={{ fontSize: 20.5, color: paper.ink }}>{uploading ? '…' : '＋'}</Text>
              </Pressable>
            )}
          </Row>
          <Text style={{ fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 8 }}>
            {dogName ?? '반려견'}의 신나는 순간을 남겨주세요 — 보호자 만족도와 재지명율이 올라가요
          </Text>
        </View>
      )}

      {/* 실드랍 — 미오픈 드랍이 있을 때만, 오픈은 리워드 센터에서. Ink+volt ceremony face
          stays (drop = milestone artifact); glow shadow retired, corners sharp */}
      {pendingDrop && (
        <Pressable
          onPress={() => router.push('/runner/rewards')}
          style={({ pressed }) => [s.dropBanner, pressed && { transform: [{ scale: 0.96 }] }]}
        >
          <Icon name={pendingDrop.kind === 'pick' ? 'Gift' : 'Package'} glyph="●" size={24} color={colors.volt} />
          <Text style={{ fontSize: 16, fontWeight: '800', color: colors.volt, marginTop: 5 }}>
            {pendingDrop.runCountAt}회 달성 — {pendingDrop.kind === 'pick' ? '픽 드랍' : '보급 상자'} 도착!
          </Text>
          <Text style={{ fontSize: 14, color: '#BBBBBB', marginTop: 3 }}>리워드 센터에서 열기 ›</Text>
        </Pressable>
      )}

      {/* [2026-08-11] '수익은 매주 수요일 정산됩니다'를 지웠다. 수요일 지급 운영은 존재하지
          않는다 — 실결제가 아직 없고(pay.tsx가 그렇게 말한다), 러너 지급을 실행하는 코드도 없다.
          기록은 진짜다(ledger_items). 지급 일정은 진짜가 아니었다. 아는 것만 말한다. */}
      <Text style={{ fontSize: 14, color: paper.dim, textAlign: 'center', marginTop: 14 }}>
        {runResult.settled
          ? '정산 기록이 저장됐어요 — 수익 화면에서 누적을 볼 수 있어요'
          : '정산이 확정되면 수익 화면에 반영돼요'}
      </Text>
      <PaperBtn label={dogName ? `${dogName} 리뷰 남기기` : '반려견 리뷰 남기기'} style={{ marginTop: 20 }} onPress={() => router.push('/runner/review')} />
      <PaperBtn label="홈으로" variant="secondary" style={{ marginTop: 8 }} onPress={() => router.dismissTo('/runner/home')} />
    </ScrollView>
  );
}

const s = StyleSheet.create({
  receipt: { marginTop: 24, alignItems: 'center', padding: 26, backgroundColor: paper.ink, borderRadius: 0 },
  photoCard: { marginTop: 14, backgroundColor: paper.canvas, padding: 15, borderWidth: 1, borderColor: '#EEEEEE' },
  addTile: {
    width: 64, height: 64, backgroundColor: paper.canvas, alignItems: 'center', justifyContent: 'center',
    borderWidth: 1, borderColor: '#CCCCCC', borderStyle: 'dashed',
  },
  dropBanner: {
    marginTop: 14, padding: 18, alignItems: 'center',
    backgroundColor: paper.ink, borderWidth: 1.5, borderColor: colors.volt,
  },
});
