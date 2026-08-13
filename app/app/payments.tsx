import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { ChargeBanner, PaymentRow } from '../src/components/charge-states';
import { Row } from '../src/components/ui';
import {
  BillingCard, PaymentRecord, fetchMyBillingCard, fetchMyPayments, fetchUnsettledCharge, retryCollect,
} from '../src/lib/api';
import { paper } from '../src/theme';

// 설정 → 결제 관리 — the "on demand" half of the price-invisibility doctrine (§0-bis).
// The happy path shows the price ONCE (요청 화면) and never again; this screen is where the
// owner can always come back and see what was actually charged. It must therefore be complete
// and accurate, and it must never soften a failure.
//
// What this screen deliberately does NOT have:
//  · 카드 등록 CTA — the 빌링키 register flow is a separate slice. A button that opens nothing
//    is a dead button (CLAUDE.md 정직 법), so the empty state says 준비 중 and stops there.
//  · 전자상거래법 footer (상호·사업자등록번호·통신판매업신고·대표·주소·연락처) — those numbers
//    do not exist yet (사업자등록 pending). Fabricating them would be both a lie and a legal
//    claim. It lands with the real filing, not before.
//  · any client-side arithmetic. Every 원 on this screen is a payments row's own `amount`.

const CONTACT_MAIL = 'mailto:seankookim@uchicago.edu?subject=도그스하이 카드 재연결 문의';
const RECEIPT_LIMIT = 30;

const linkedLabel = (iso: string | null): string => {
  if (!iso) return '';
  try {
    return new Intl.DateTimeFormat('ko-KR', { timeZone: 'Asia/Seoul', year: 'numeric', month: 'long', day: 'numeric' })
      .format(new Date(iso));
  } catch {
    const d = new Date(iso);
    return `${d.getFullYear()}. ${d.getMonth() + 1}. ${d.getDate()}`;
  }
};

type LoadState = 'loading' | 'ready' | 'error';

export default function Payments() {
  const [card, setCard] = useState<BillingCard | null>(null);
  const [cardState, setCardState] = useState<LoadState>('loading');
  const [rows, setRows] = useState<PaymentRecord[]>([]);
  const [rowsState, setRowsState] = useState<LoadState>('loading');
  // null = 아직 모른다. 파생 읽기가 실패했다고 '잠기지 않았다'고 말하지 않는다 —
  // 진짜 잠금은 서버(create-booking-hold)가 쥐고 있고, 이 값은 그 이유를 미리 말해주는 역할일 뿐.
  const [locked, setLocked] = useState<boolean | null>(null);
  const [busy, setBusy] = useState(false);
  // 재시도 뒤에도 상태가 그대로일 때 사용자에게 남기는 한 줄 (침묵도 거짓 성공도 아니다)
  const [retryNote, setRetryNote] = useState<string | null>(null);

  const load = useCallback(() => {
    setCardState((s) => (s === 'ready' ? s : 'loading'));
    setRowsState((s) => (s === 'ready' ? s : 'loading'));
    const c = fetchMyBillingCard()
      .then((v) => { setCard(v); setCardState('ready'); })
      .catch((e) => { console.warn('[payments] card:', e?.message ?? e); setCardState('error'); });
    const p = fetchMyPayments(RECEIPT_LIMIT)
      .then((v) => { setRows(v); setRowsState('ready'); })
      .catch((e) => { console.warn('[payments] rows:', e?.message ?? e); setRowsState('error'); });
    const u = fetchUnsettledCharge()
      .then(setLocked)
      .catch((e) => { console.warn('[payments] unsettled:', e?.message ?? e); setLocked(null); });
    return Promise.all([c, p, u]);
  }, []);

  useFocusEffect(useCallback(() => { load(); }, [load]));

  const failedRows = rows.filter((r) => r.status === 'failed');
  const needsRelink = failedRows.some((r) => r.needsCardRelink);
  // 재청구는 서버가 만든 행에만 걸 수 있다 — 실패한 청구가 없으면 버튼도 없다 (죽은 버튼 금지).
  const retryTargets = Array.from(new Set(failedRows.map((r) => r.bookingId)));

  const onRetry = useCallback(async () => {
    if (busy || retryTargets.length === 0) return;
    setBusy(true);
    setRetryNote(null);
    let failure: string | null = null;
    for (const bid of retryTargets) {
      try {
        await retryCollect(bid);
      } catch (e) {
        failure = (e as Error).message; // 서버가 한 말 그대로
        break;
      }
    }
    const fresh = await fetchMyPayments(RECEIPT_LIMIT).catch(() => null);
    if (fresh) { setRows(fresh); setRowsState('ready'); }
    const stillFailed = (fresh ?? rows).some((r) => r.status === 'failed');
    await fetchUnsettledCharge().then(setLocked).catch(() => setLocked(null));
    setBusy(false);
    if (failure) {
      Alert.alert('다시 시도 실패', failure);
      return;
    }
    // 200 응답이 '수금 완료'는 아니다 — 결과는 다시 읽은 행이 말한다.
    setRetryNote(stillFailed ? '방금 다시 시도했지만 아직 처리되지 않았어요' : null);
  }, [busy, retryTargets, rows]);

  return (
    <ScrollView
      style={{ flex: 1, backgroundColor: paper.canvas }}
      contentContainerStyle={{ paddingTop: 56, paddingBottom: 40 }}
    >
      <Row style={{ justifyContent: 'space-between', paddingHorizontal: 16 }}>
        <Pressable onPress={() => router.back()} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
          <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
        </Pressable>
        <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>결제 관리</Text>
        <View style={{ width: 40 }} />
      </Row>

      {/* ── 예외 배너 — 숨길 수 없는 상태 (§0-bis: 예외는 크게, 영수증은 조용히) ── */}
      {needsRelink && (
        <ChargeBanner
          kind="relink"
          cta="문의하기"
          onPress={() => { Linking.openURL(CONTACT_MAIL).catch(() => Alert.alert('메일 앱을 열 수 없어요', CONTACT_MAIL)); }}
          style={{ marginTop: 18 }}
        />
      )}
      {locked === true && (
        <ChargeBanner
          kind="debt"
          detail={retryNote}
          // 카드가 죽은 상태(relink)에서는 재시도가 성공할 수 없다 — 그때는 위 배너의 문의가 유일한 길.
          cta={!needsRelink && retryTargets.length > 0 ? '다시 시도' : undefined}
          busyCta="다시 청구하는 중..."
          busy={busy}
          onPress={onRetry}
          style={{ marginTop: needsRelink ? 10 : 18 }}
        />
      )}
      {/* 잠기지는 않았지만 실패한 청구가 있는 경우 (예: 방금 실패, 아직 파생이 잡기 전) */}
      {locked !== true && failedRows.length > 0 && !needsRelink && (
        <ChargeBanner
          kind="declined"
          detail={retryNote}
          cta="다시 시도"
          busyCta="다시 청구하는 중..."
          busy={busy}
          onPress={onRetry}
          style={{ marginTop: 18 }}
        />
      )}

      {/* ── 결제 수단 ── */}
      <SectionHead title="결제 수단" />
      <View style={s.section}>
        {cardState === 'loading' && <Text style={s.note}>불러오는 중...</Text>}
        {cardState === 'error' && (
          <View style={s.failStrip}>
            <Text style={s.failTxt}>결제 수단을 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={s.retryTxt}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {cardState === 'ready' && card && (
          <>
            <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>
              {card.brand ?? '카드'} ···· {card.last4 ?? '····'}
            </Text>
            {card.linkedAt && <Text style={s.note}>{linkedLabel(card.linkedAt)} 연결됨</Text>}
          </>
        )}
        {cardState === 'ready' && !card && (
          <>
            <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>등록된 카드가 없어요</Text>
            {/* 카드 등록은 다음 슬라이스 — 없는 문을 그리는 대신 준비 중이라고 말한다 */}
            <Text style={s.note}>카드 등록 화면은 준비 중이에요 — 준비되면 여기서 연결할 수 있어요</Text>
          </>
        )}
      </View>

      {/* ── 결제 내역 ── */}
      <SectionHead title="결제 내역" />
      <View style={s.section}>
        {rowsState === 'loading' && <Text style={s.note}>불러오는 중...</Text>}
        {rowsState === 'error' && (
          <View style={s.failStrip}>
            <Text style={s.failTxt}>결제 내역을 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={s.retryTxt}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {rowsState === 'ready' && rows.length === 0 && (
          <>
            <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>아직 결제 내역이 없어요</Text>
            <Text style={s.note}>러닝이 끝난 뒤 청구가 생기면 여기에 쌓여요</Text>
          </>
        )}
      </View>
      {rowsState === 'ready' && rows.length > 0 && (
        <View style={{ paddingHorizontal: 16 }}>
          {rows.map((p) => <PaymentRow key={p.orderId} p={p} />)}
          {/* 목록은 최근 RECEIPT_LIMIT건까지 — 잘렸다는 사실을 말한다 (조용한 절단 금지) */}
          {rows.length >= RECEIPT_LIMIT && (
            <Text style={[s.note, { marginTop: 12 }]}>최근 {RECEIPT_LIMIT}건까지 보여드려요</Text>
          )}
        </View>
      )}
    </ScrollView>
  );
}

// §3b 섹션 헤더 — 풀블리드 코랄 1px + 20/800 잉크 타이틀 (라틴 키커·서브타이틀 없음)
function SectionHead({ title }: { title: string }) {
  return (
    <>
      <View style={s.rule} />
      <Text style={s.sectionTitle}>{title}</Text>
    </>
  );
}

const s = StyleSheet.create({
  backBtn: {
    width: 40, height: 40, backgroundColor: paper.canvas,
    alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: paper.line,
  },
  rule: { borderTopWidth: 1, borderColor: paper.line, marginTop: 22 },
  sectionTitle: { fontSize: 20, fontWeight: '800', color: paper.ink, paddingHorizontal: 16, marginTop: 14 },
  section: { paddingHorizontal: 16, marginTop: 8 },
  note: { fontSize: 14.5, lineHeight: 20, color: paper.dim, marginTop: 3 },
  failStrip: { backgroundColor: paper.criticalWash, padding: 13, marginTop: 4 },
  failTxt: { fontSize: 14, fontWeight: '700', color: paper.critical },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  retryTxt: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
});
