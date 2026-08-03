import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useRef, useState } from 'react';
import { Alert, Image, Pressable, ScrollView, Share, StyleSheet, Text, View } from 'react-native';
import { Row } from '../../../src/components/ui';
import { ClubCta, ClubMast, DawnCanvas, Flap } from '../../../src/components/club-ui';
import { fetchRunReport, RunReport, shareRunToFeed } from '../../../src/lib/api';
import { useDisplayFont } from '../../../src/lib/displayFont';
import { useNumFont } from '../../../src/lib/fonts';
import { haptic } from '../../../src/lib/haptics';
import { lilac, lilacRadius, lilacShadow } from '../../../src/theme';

// O11 — 완료 영수증 (정본: flow-lab O11 + 결정 로그 "영수증 = 사진 인화")
// 포일 예산: 골드 = SETTLED 전용 (여기가 골드가 사는 유일한 집).
// 사진법: 베스트 샷이 있으면 인화(골드 실이 사진에 반쯤 걸친다), 없으면 사진 없는 종이 —
// 스톡/플레이스홀더 이미지는 없다 (사진은 콘텐츠, 월페이퍼 금지). 공유 카드 = 성장 루프.

const L = lilac;

const durStr = (sec: number): string =>
  `${Math.floor(sec / 60)}:${String(Math.floor(sec % 60)).padStart(2, '0')}`;
const paceOf = (secPerKm: number): string =>
  `${Math.floor(secPerKm / 60)}'${String(Math.round(secPerKm % 60)).padStart(2, '0')}"`;

export default function ClubReceipt() {
  const df = useDisplayFont();
  const nf = useNumFont();
  const { bid, clubName } = useLocalSearchParams<{ bid: string; clubName?: string }>();
  const [report, setReport] = useState<RunReport | null>(null);
  const [busy, setBusy] = useState(false);
  const cardRef = useRef<View>(null);

  const load = useCallback(() => {
    if (bid) fetchRunReport(bid).then(setReport).catch(() => {});
  }, [bid]);
  useFocusEffect(useCallback(() => { load(); }, [load]));

  if (!report) {
    return (
      <DawnCanvas>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
          <Text style={{ fontSize: 13, color: L.dim }}>불러오는 중...</Text>
        </View>
      </DawnCanvas>
    );
  }
  if (!report.run) {
    return (
      <DawnCanvas>
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 24 }}>
          <Text style={{ fontSize: 13, color: L.dim }}>완료된 러닝만 영수증이 나와요</Text>
          <ClubCta label="돌아가기" tone="quiet" onPress={() => router.back()} style={{ alignSelf: 'stretch' }} />
        </View>
      </DawnCanvas>
    );
  }

  const run = report.run;
  const bestShot = run.photos[0] ?? null;
  const pace = run.paceSecPerKm != null ? paceOf(run.paceSecPerKm)
    : run.actualKm > 0.05 ? paceOf(run.durationSec / run.actualKm) : "-'--\"";

  // 카드 캡처 → 시스템 공유 시트 (인증샷 화면 선례 — view-shot 지연 로드, 미탑재 빌드는 정직 안내)
  const shareImage = async () => {
    try {
      const VS = require('react-native-view-shot');
      const uri = await VS.captureRef(cardRef, { format: 'png', quality: 1 });
      await Share.share({ url: uri }).catch(() => {});
    } catch {
      Alert.alert('개발 빌드 업데이트 필요', '카드 캡처(view-shot)는 새 빌드에 포함돼요');
    }
  };
  const shareFeed = () => {
    if (busy) return;
    setBusy(true);
    shareRunToFeed(bid!)
      .then(() => { haptic('success'); Alert.alert('피드에 올라갔어요', '동네 피드에서 오늘의 기록을 볼 수 있어요'); })
      .catch((e) => Alert.alert('공유 실패', (e as Error).message))
      .finally(() => setBusy(false));
  };

  return (
    <DawnCanvas>
      <ScrollView contentContainerStyle={{ padding: 12, paddingTop: 56, paddingBottom: 40 }}>
        <ClubMast title="완료" sub={`${report.when}${clubName ? ` · ${clubName}` : ''}`} onBack={() => router.back()} />

        {/* ---------- 영수증 카드 (캡처 대상) ---------- */}
        <View ref={cardRef} collapsable={false} style={s.card}>
          <View pointerEvents="none" style={s.innerFrame} />
          {/* 베스트 샷 인화 — 있으면 사진이 카드의 상단을 산다, 골드 실이 반쯤 걸친다 */}
          {bestShot && (
            <View style={s.photoWrap}>
              <Image source={{ uri: bestShot }} style={s.photo} resizeMode="cover" />
            </View>
          )}
          <View style={{ alignItems: 'center', marginTop: bestShot ? -26 : 16 }}>
            <View style={s.goldSeal}>
              <Text style={s.goldSealTxt}>SETTLED</Text>
            </View>
          </View>
          <View style={{ alignItems: 'center', paddingBottom: 18, paddingHorizontal: 14 }}>
            <Text style={[{ fontSize: 19, color: L.head, marginTop: 10 }, df]}>
              {report.dogName}, 오늘 <Text style={{ color: L.coral }}>{run.actualKm.toFixed(1)}km</Text>
            </Text>
            <Text style={{ fontSize: 11, color: L.dim, marginTop: 4 }}>
              {report.runnerName ? `${report.runnerName}와 · ` : ''}{pace} · {durStr(run.durationSec)}
            </Text>
            <View style={{ marginTop: 10 }}>
              <Flap state="SETTLED" />
            </View>
            {/* 수치 룰 행 */}
            <Row style={s.numRow}>
              <View style={s.numCell}>
                <Text style={[s.numV, nf]}>{run.actualKm.toFixed(1)}<Text style={{ fontSize: 11, color: L.coral }}>km</Text></Text>
                <Text style={s.numL}>실측 거리</Text>
              </View>
              <View style={s.numCell}>
                <Text style={[s.numV, nf]}>{pace}</Text>
                <Text style={s.numL}>페이스</Text>
              </View>
              <View style={[s.numCell, { borderRightWidth: 0 }]}>
                <Text style={[s.numV, nf]}>{durStr(run.durationSec)}</Text>
                <Text style={s.numL}>시간</Text>
              </View>
            </Row>
            {/* 크레딧 라인 — 항상 (사진법 6조) */}
            <Text style={s.credit}>{clubName || report.routeName || 'HIGH CLUB'} · DOGS HIGH</Text>
          </View>
        </View>

        {/* ---------- 공유 = 성장 루프 (카드 밖 — 캡처에 안 들어간다). [Sean 규칙] 여백 화면 = 큰 버튼 ---------- */}
        <ClubCta label="이미지로 공유 →" onPress={shareImage} style={{ marginTop: 14, paddingVertical: 18 }} />
        <ClubCta label="동네 피드에 자랑하기" tone="quiet" onPress={shareFeed} busy={busy} style={{ paddingVertical: 15 }} />
        <Pressable onPress={() => router.push({ pathname: '/owner/report', params: { bid: bid! } })}>
          <Text style={s.detailLink}>상세 리포트 (지도·이벤트) →</Text>
        </Pressable>
      </ScrollView>
    </DawnCanvas>
  );
}

const s = StyleSheet.create({
  card: {
    backgroundColor: L.card, borderRadius: lilacRadius.card, borderWidth: 1, borderColor: L.hair,
    marginTop: 12, overflow: 'hidden', ...lilacShadow,
  },
  innerFrame: {
    position: 'absolute', left: 5, right: 5, top: 5, bottom: 5, zIndex: 2,
    borderWidth: 1, borderColor: L.goldSheen, borderRadius: 4, opacity: 0.55,
  },
  photoWrap: { height: 190, backgroundColor: L.inset },
  photo: { width: '100%', height: '100%' },
  goldSeal: {
    width: 62, height: 62, borderRadius: 31, backgroundColor: L.goldSoft,
    borderWidth: 2, borderColor: L.gold, alignItems: 'center', justifyContent: 'center',
    transform: [{ rotate: '-8deg' }], zIndex: 3,
    shadowColor: L.gold, shadowOpacity: 0.35, shadowRadius: 8, shadowOffset: { width: 0, height: 3 }, elevation: 3,
  },
  goldSealTxt: { fontSize: 9, fontWeight: '800', letterSpacing: 1.5, color: '#8a6f2a' },
  numRow: {
    alignSelf: 'stretch', backgroundColor: L.inset, borderRadius: lilacRadius.inner,
    borderWidth: 1, borderColor: L.hair, marginTop: 14, overflow: 'hidden',
  },
  numCell: { flex: 1, paddingVertical: 9, alignItems: 'center', borderRightWidth: 1, borderRightColor: L.hair },
  numV: { fontSize: 18, fontWeight: '600', color: L.head, fontVariant: ['tabular-nums'] },
  numL: { fontSize: 7, fontWeight: '700', letterSpacing: 1.5, color: L.dim, marginTop: 3 },
  credit: { fontSize: 7.5, fontWeight: '700', letterSpacing: 2, color: L.dim, marginTop: 14 },
  detailLink: { textAlign: 'center', marginTop: 12, fontSize: 11, fontWeight: '800', color: L.accent },
});
