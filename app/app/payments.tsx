import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { homePath } from '../src/components/bottomnav';
import { ChargeBanner, PaymentRow } from '../src/components/charge-states';
import { PaperBtn } from '../src/components/paper-btn';
import { Row } from '../src/components/ui';
import {
  BillingCard, PaymentRecord, fetchMyBillingCard, fetchMyPayments, fetchUnsettledCharge, retryCollect,
} from '../src/lib/api';
import { goBackOrHome } from '../src/lib/nav';
import { TOSS_CLIENT_KEY } from '../src/lib/toss';
import { paper } from '../src/theme';

// 설정 → 결제 관리 — the "on demand" half of the price-invisibility doctrine (§0-bis).
// The happy path shows the price ONCE (요청 화면) and never again; this screen is where the
// owner can always come back and see what was actually charged. It must therefore be complete
// and accurate, and it must never soften a failure.
//
// RETURN INTENT (Sean 재정 ⑤, 2026-08-13). Screens that hit a money refusal send the owner here
// instead of dead-ending, and they carry where to go back to:
//   router.push({ pathname: '/payments', params: { returnTo: '<href>', returnLabel: '<button copy>' } })
// `returnTo` is a complete href (query string included) so this screen stays ignorant of the
// caller's world — it only knows "there is somewhere to go back to". The door is drawn ONLY when
// a card actually exists: offering "돌아가서 마저 하기" to a card-less owner would just walk them
// into the same refusal again. The caller (club session) re-opens what they were doing.
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

// `returnTo` is a ROUTE PARAM, and a route param is whatever the URL says — a push payload, a
// shared link, a typed `daengrun://payments?returnTo=…`. Handing it straight to router.replace()
// made the destination of a button on OUR screen the choice of whoever wrote the link. Today's
// two callers (owner/report.tsx:547, club/session/[sid].tsx:623) pass valid hrefs, so nothing is
// live; this closes the shape before a third caller or a deep link finds it.
//
// The check is on the PATH ONLY — the query string is the caller's payload (`bid`, `resumeSd`,
// `clubName`) and the destination screen validates its own params. A path that is not on this
// list is not "an odd return", it is a return we cannot vouch for, so the button goes home and
// SAYS SO (the label follows the destination — a button reading '러닝 리포트로' that lands on the
// home screen is a dead-button lie in slower motion).
function allowedReturn(href: string): string | null {
  const path = href.split('?')[0];
  if (path === '/owner/report') return href;                    // owner/report.tsx:547
  const parts = path.split('/');                                // '/club/session/<sid>' → ['', 'club', 'session', '<sid>']
  if (parts.length === 4 && parts[1] === 'club' && parts[2] === 'session' && parts[3].length > 0) return href;
  return null;                                                  // club/session/[sid].tsx:623
}

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
  const { returnTo, returnLabel } = useLocalSearchParams<{ returnTo?: string; returnLabel?: string }>();
  // null = a return was carried in but it is not an address we can vouch for; the door goes home.
  const backHref = returnTo ? allowedReturn(returnTo) : null;
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
        <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
          <Text style={{ fontSize: 20.5, color: paper.ink }}>‹</Text>
        </Pressable>
        <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>결제 관리</Text>
        <View style={{ width: 40 }} />
      </Row>

      {/* ── 예외 배너 — 숨길 수 없는 상태 (§0-bis: 예외는 크게, 영수증은 조용히) ── */}
      {/* [2026-08-26] 이 배너의 CTA는 mailto: 였다 — 카드 등록 화면이 없던 시절의 유일한 출구.
          이제 문이 있으므로 문으로 보낸다 (codex REJECT #5: 새 화면을 만들고도 실제 앱 경로가
          아무도 거기 닿지 않았다). 키가 없으면 옛 문의 경로가 그대로 남는다 — 열리지 않는
          화면으로 보내는 것이 메일보다 나쁘다. */}
      {needsRelink && (
        <ChargeBanner
          kind="relink"
          cta={TOSS_CLIENT_KEY != null ? '카드 다시 연결하기' : '문의하기'}
          onPress={() => {
            if (TOSS_CLIENT_KEY != null) { router.push('/owner/card-link'); return; }
            Linking.openURL(CONTACT_MAIL).catch(() => Alert.alert('메일 앱을 열 수 없어요', CONTACT_MAIL));
          }}
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
            {/* 돌아갈 곳을 들고 온 방문 = 하려던 일이 있는 방문. 카드가 있는 지금은 그 일이 통한다.
                replace = 결제 관리가 스택에 남지 않는다 (돌아간 화면에서 뒤로 = 원래 있던 곳). */}
            {/* [2026-08-26] 카드 교체 — Sean의 배치 판정이 명시한 절반이다: 「after that first run,
                there should be no card whatever, and the card should be changeable and manageable
                in settings」. 첫 구현은 그 절반을 빠뜨렸고, 카드가 있는 보호자에게는 아무 동작도
                없었다 (codex REJECT #5). 같은 화면(owner/card-link)이 교체를 처리한다 —
                register-billing-key의 upsert가 프로필당 한 행을 유지하므로 연결과 교체는 같은 쓰기다. */}
            {TOSS_CLIENT_KEY != null && (
              <PaperBtn label="카드 바꾸기" variant="secondary" style={{ marginTop: 12 }}
                onPress={() => router.push('/owner/card-link')} />
            )}
            {returnTo && (
              <PaperBtn
                label={backHref ? (returnLabel || '하던 일로 돌아가기 ›') : '홈으로 ›'}
                variant="secondary"
                onPress={() => router.replace(backHref ?? homePath())}
                style={{ marginTop: 12 }}
              />
            )}
          </>
        )}
        {cardState === 'ready' && !card && (
          <>
            <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>등록된 카드가 없어요</Text>
            {/* [2026-08-26] 그 TODO의 화면이 생겼다 — owner/card-link (랩 ① 픽). 문은 키가 있을
                때만 그린다: TOSS_CLIENT_KEY가 없으면 연결 시트가 열리지 않으므로 (billing-auth-
                sheet의 early return) CTA는 죽은 버튼이 된다. 키 부재 = 아직 결제사가 아니라는
                사실이고, 그 동안은 그 사실을 말하는 문장이 남는다 — 「준비 중」이 아니라 언제
                열리는지를 말한다. */}
            {TOSS_CLIENT_KEY != null ? (
              <PaperBtn label="카드 연결하기" variant="secondary" style={{ marginTop: 12 }}
                onPress={() => router.push('/owner/card-link')} />
            ) : (
              <Text style={s.note}>카드 연결은 결제 오픈과 함께 열려요</Text>
            )}
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
