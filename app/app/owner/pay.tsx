import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { BookingCharge, fetchBookingCharge } from '../../src/lib/api';
import { useNumFont } from '../../src/lib/fonts';
import { derivePayPhase, PayPhase } from '../../src/lib/payphase';
import { paper, pricing } from '../../src/theme';

// 청구 표면 `/owner/pay?bid=` — 예약 하나의 청구 상태를 서버 진실로만 말하는 **읽기 전용** 화면.
// [정직 배치 2026-08-06 · 웨이브 2 item 1] 100% 목업이던 영수증(지어낸 러닝 기록·가짜 결제수단 끝자리·
// 목업 draft 재계산 총액·'결제하고 리뷰 남기기')을 통째로 은퇴시키고, PG 상태 머신 위에 다시 세웠다.
// 페이즈 파생은 src/lib/payphase.ts 하나 — PG 실연동(phase ④)은 드라이버만 추가하면 된다(3차 리빌드 없음).
//
// ⚠ [O-5 §E.5.1 · 2026-08-19] **이 화면은 파일럿에서 도달할 수 없다.** 결제가 러닝 뒤로 갔고
//   (create-booking-hold v10이 한 요청 안에서 matching까지 닫는다), `payment_ok`는 삭제됐으며
//   (transition-booking v34 → 400 unknown action), request.tsx는 더 이상 여기로 push하지 않는다.
//   그래서 이 화면에서 다음 세 가지가 사라졌다:
//     · '예약 확정하기' 버튼과 confirmPayment 호출 — 서버에 그런 문이 없다.
//     · postConfirm 블록(리커링·지명·라우팅) — request.tsx의 홀드 직후로 되돌아갔다.
//     · 토스 위젯 경로(intent → TossSheet → confirmToss) — 진입점이 확정 버튼뿐이었다.
//       api.ts의 createPaymentIntent/confirmToss와 toss-sheet.tsx는 그대로 살아 있다(머니 세션의
//       카드 등록 슬라이스 몫). 여기에 죽은 배선을 남겨두는 것보다 그쪽에서 다시 세우는 게 정직하다.
//   파일을 지우지 않는 이유: app/dev/pay-lab.tsx가 PayScreen/PayView를 import한다. 라우트가
//   닿는 모듈은 앱 시작 시 전부 평가되므로 (CLAUDE.md, check-route-native-imports) dev 화면
//   하나가 프로덕션 실행을 죽일 수 있다 — 정리는 그 랩과 함께 한 번에 한다.
//
// 숫자는 전부 bookings 행에서 온다 (클라이언트 재계산 금지). 하드코드 헥스 0 — 토큰과 PaperBtn만 쓴다.

// 화면 상태 = 서버 진실의 파생(PayPhase 9종) + 통신 실패 한 칸.
// 'error'가 PayPhase에 없는 이유: 그건 예약의 상태가 아니라 우리 쪽 실패다 (웨이브 2 리뷰 M1).
export type PayScreen = PayPhase | 'error';

// 페이즈 칩 — 장식 클래스 캡스(모노 계열 서체 미보유 → 자간 확장으로 대체). failed/error만 크리티컬 잉크.
const CHIP: Record<PayScreen, string> = {
  loading: 'LOADING',
  not_found: 'NOT FOUND',
  mock_pending: 'MOCK · 준비 중',
  authorizing: 'AUTHORIZING',
  authorized: 'AUTHORIZED',
  disputed: 'REVIEW · 확인 중',
  failed: 'FAILED',
  cancelled: 'CANCELLED',
  refund_pending: 'REFUND · 환불 중',
  error: 'ERROR',
};

const HEAD: Record<PayScreen, string> = {
  loading: '결제 정보를 불러오는 중',
  not_found: '결제 정보를 찾을 수 없어요',
  mock_pending: '아직 접수되지 않은 예약이에요',
  authorizing: '승인 요청 중',
  authorized: '예약이 확정됐어요',
  disputed: '러닝에 확인이 필요한 일이 있어요',
  failed: '결제가 완료되지 않았어요',
  cancelled: '취소된 예약이에요',
  refund_pending: '환불이 진행 중이에요',
  error: '결제 정보를 불러오지 못했어요',
};

// 애드온 라벨은 서버 행에 없다 (C2: 실데이터는 {key,price}) — 클라 사전에서 되찾고,
// 모르는 키(서버가 먼저 추가한 옵션)는 키를 그대로 보여준다. 없는 이름을 지어내지 않는다.
const ADDON_LABELS = pricing.addons as Record<string, { label: string } | undefined>;
const addonLabel = (k: string) => ADDON_LABELS[k]?.label ?? k;

const msgOf = (e: unknown) => (e instanceof Error ? e.message : String(e));
const goHome = () => router.replace('/owner/home');

// 예약 시각 — Asia/Seoul 고정 (기기 로컬 타임존 금지: api.ts kstParts와 같은 이유)
const whenLabel = (iso: string): string => {
  try {
    return new Intl.DateTimeFormat('ko-KR', {
      timeZone: 'Asia/Seoul', month: 'long', day: 'numeric', weekday: 'short',
      hour: 'numeric', minute: '2-digit',
    }).format(new Date(iso));
  } catch {
    return new Date(iso).toLocaleString('ko-KR');
  }
};

export default function Pay() {
  // [O-5 §E.5.1] recurring/after 파라미터는 사라졌다 — 그것을 소비하던 postConfirm 블록이
  // request.tsx의 홀드 직후로 돌아갔기 때문이다. 남은 파라미터는 어떤 예약을 읽을지(bid)와
  // 슬롯 홀드 만료 시각(exp)뿐이고, 둘 다 이 화면이 **보여주기만** 하는 값이다.
  const { bid, exp } = useLocalSearchParams<{ bid?: string; exp?: string }>();
  // [리뷰 #5] 실홀드 만료 — 슬롯 홀드(5분)는 조용히 풀린다. 시각을 정직하게 말한다.
  const holdUntil = exp ? new Date(exp) : null;
  const holdLabel = holdUntil && !isNaN(holdUntil.getTime())
    ? `${String(holdUntil.getHours()).padStart(2, '0')}:${String(holdUntil.getMinutes()).padStart(2, '0')}`
    : null;
  const [screen, setScreen] = useState<PayScreen>('loading');
  const [charge, setCharge] = useState<BookingCharge | null>(null);
  const [busy, setBusy] = useState(false);
  const [failReason, setFailReason] = useState<string | null>(null);

  // 청구 로드 — 이 화면이 하는 일의 전부다 (서버를 앞으로 미는 호출은 하나도 남아 있지 않다).
  const load = useCallback(async () => {
    if (!bid) { setScreen('not_found'); return; }
    try {
      const c = await fetchBookingCharge(bid);
      if (!c) { setCharge(null); setScreen('not_found'); return; } // 0행·남의 예약 (H3/M5)
      setCharge(c);
      // attempt 인자는 넘기지 않는다 — 클라이언트가 만드는 PG 시도 레코드가 더 이상 없다.
      // (payphase.ts의 authorizing/failed는 위젯 슬라이스가 돌아올 때 그 인자와 함께 살아난다.)
      setScreen(derivePayPhase({ status: c.status }));
    } catch (e) {
      setFailReason(msgOf(e));
      setScreen('error'); // 로딩도 0도 아니다 — 못 불러왔다고 말한다
    }
  }, [bid]);

  useEffect(() => { load(); }, [load]);

  // ── 확정 이후 블록은 여기 없다 (O-5 §E.5.1) ────────────────────────────────────────────
  // 예전에 이 자리에 postConfirm(draft.bookingId · createRecurringSeries · requestRunner ·
  // 라우팅)이 있었다. 웨이브 2 리뷰가 C3/C4 때문에 request.tsx에서 이리로 옮겼던 블록인데,
  // 그 두 이유가 서버 슬라이스로 사라졌다: 홀드가 반환될 때 예약은 이미 matching이라 미결제
  // 시리즈를 만들 창도, 지명이 409로 증발할 payment_hold도 없다. 블록은 request.tsx의 홀드
  // 직후로 되돌아갔다 — 이 화면이 아니라 **예약을 만든 화면**이 그 결과를 책임진다.
  // 여기에 남기면 이 화면이 도달 불가가 되는 순간 세 효과가 통째로 죽는다(리뷰 F1).

  // 통신 실패 전용 재시도 — 다시 읽기만 한다. 이 화면에서 서버를 앞으로 미는 버튼은 없다.
  const onReload = useCallback(async () => {
    if (busy) return;
    setBusy(true);
    await load();
    setBusy(false);
  }, [busy, load]);

  return (
    <PayView
      screen={screen}
      charge={charge}
      busy={busy}
      failReason={failReason}
      holdLabel={holdLabel}
      onReload={onReload}
      onBack={() => router.back()}
    />
  );
}

export interface PayViewProps {
  screen: PayScreen;
  charge: BookingCharge | null;
  busy: boolean;
  failReason: string | null;
  holdLabel?: string | null; // [리뷰 #5] 실홀드 만료 HH:MM — mock_pending에서만 표시
  // [O-5 §E.5.1] onConfirm/onRetry는 삭제됐다 — 이 화면에서 서버를 앞으로 미는 동작이 없다.
  // 남은 액션은 '다시 불러오기'(읽기)와 '뒤로'뿐이다.
  onReload: () => void;
  onBack: () => void;
}

// 순수 표현 컴포넌트 — 상태는 위에서만 만든다. dev 페이즈 랩(app/dev/pay-lab.tsx)이 이걸 그대로 쓴다
// (L2: 프로덕션 화면에 __DEV__ 분기를 만들지 않기 위해 뷰를 밖으로 뽑았다).
export function PayView({ screen, charge, busy, failReason, holdLabel, onReload, onBack }: PayViewProps) {
  const nf = useNumFont(); // 숫자 = Oswald — 이 화면의 단 하나의 타입 점프(총액)
  const dots = useEllipsis(screen === 'authorizing'); // 스피너 연출 금지 — 말줄임표만 움직인다
  const loud = screen === 'failed' || screen === 'error';
  // 로딩('—' 자리)과 청구가 손에 있는 상태에서만 테이블을 그린다. 재로드 실패(error)로 직전 청구가
  // 남아 있으면 그 숫자는 계속 보여준다 — 지웠다가 다시 그리는 쪽이 더 거짓말이다 (라우드 스트립이 함께 뜬다).
  const showTable = screen === 'loading' || charge !== null;

  return (
    <View style={s.root}>
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingTop: 60, paddingBottom: 28 }}>
        {/* kicker + 페이즈 칩 — 승인 중에는 뒤로가기 어포던스 자체가 없다 (취소 불가 화면) */}
        <View style={s.headRow}>
          <View style={{ flex: 1 }}>
            {screen !== 'authorizing' && (
              <Pressable onPress={onBack} hitSlop={10} accessibilityRole="button" accessibilityLabel="뒤로">
                <Text style={s.back}>‹</Text>
              </Pressable>
            )}
            <Text style={s.kicker}>PAYMENT</Text>
          </View>
          <Text style={[s.chip, loud && s.chipLoud]}>{CHIP[screen]}</Text>
        </View>

        <Text style={s.headline}>
          {HEAD[screen]}{screen === 'authorizing' ? dots : ''}
        </Text>
        {charge && (
          <Text style={s.meta}>
            {charge.dogName} · {charge.routeName ?? '코스 미지정'} · {whenLabel(charge.scheduledAt)}
          </Text>
        )}

        {/* ── 청구 테이블 — 전부 bookings 행의 숫자. 로딩 중엔 '—' (0원을 실측처럼 보이지 않게) ── */}
        {showTable && (
          <View style={s.table}>
            <ChargeRow label="기본요금" value={charge?.baseFare ?? null} nf={nf} />
            <ChargeRow label={`거리요금${charge ? ` · ${charge.km}km` : ''}`} value={charge?.distanceFare ?? null} nf={nf} />
            {charge && (charge.addonFare > 0 || charge.addons.length > 0) && (
              <ChargeRow
                label="프리미엄 옵션"
                sub={charge.addons.map((a) => addonLabel(a.key)).join(' · ') || undefined}
                value={charge.addonFare}
                nf={nf}
              />
            )}
            {/* 총액 행 — 이 화면의 유일한 타입 점프. 위는 1px 이중 룰(3dp 간격, 채움 없음) */}
            <View style={s.rule} />
            <View style={{ height: 3 }} />
            <View style={s.rule} />
            <View style={s.totalRow}>
              <Text style={s.totalLabel}>결제 금액</Text>
              <View style={s.amtWrap}>
                <Text style={[s.totalAmt, nf]}>{charge ? charge.totalPrice.toLocaleString('ko-KR') : '—'}</Text>
                <Text style={s.totalUnit}>원</Text>
              </View>
            </View>
          </View>
        )}

        {/* ── 상태 존 — 페이즈마다 말이 다르다 ── */}
        {screen === 'mock_pending' && (
          <View style={s.plate}>
            {/* [O-5 §E.5.1] 예전엔 여기 '확정하면 실결제가 없어요'가 있었고 아래에 확정 버튼이
                있었다. 그 버튼(과 그것이 부르던 payment_ok)이 삭제됐으므로, 이 자리에서 할 수
                있는 일이 없다는 사실을 그대로 말한다 — 없는 문을 가리키지 않는다. */}
            <Text style={s.plateTxt}>
              이 예약은 아직 접수되지 않았어요 — 이 화면에서 진행할 수 있는 일은 없어요.{'\n'}
              접수되지 않은 예약은 잠시 뒤 자동으로 정리되고, 청구되는 금액은 없어요.
            </Text>
            {holdLabel && (
              <Text style={[s.plateTxt, { marginTop: 6 }]}>
                이 슬롯은 {holdLabel}까지 홀드돼요 — 그 뒤엔 다른 보호자에게 다시 열려요
              </Text>
            )}
          </View>
        )}
        {screen === 'authorizing' && (
          <Text style={s.body}>승인 요청을 보냈어요{dots}{'\n'}완료될 때까지 앱을 닫지 말아주세요</Text>
        )}
        {screen === 'authorized' && (
          <Text style={s.body}>
            {/* PG 실연동 시 이 카피 삭제 — 파일럿 한정 사실 (리뷰 닛) */}
            이 예약은 결제 홀드를 지났어요 — 파일럿 기간이라 실결제는 발생하지 않았어요
          </Text>
        )}
        {screen === 'disputed' && (
          <Text style={s.body}>
            도그스하이가 이 러닝을 확인하고 있어요 — 결제·환불은 확인이 끝난 뒤에 정리해서 알려드려요
          </Text>
        )}
        {screen === 'cancelled' && (
          <Text style={s.body}>이 예약은 취소된 상태예요 — 이 화면에서 진행할 결제가 없어요</Text>
        )}
        {screen === 'refund_pending' && (
          /* TODO(widget slice, R3 P3-7): "환불이 진행 중" is only true when money was captured
             (a confirmed payments row exists). club_incident_settle sets refund_pending
             regardless of capture; 0080 §J-ⓑ already made the NOTIFICATION conditional —
             this screen must gain the same predicate (fetchBookingPayments) before the
             widget slice makes uncaptured refund_pending reachable with real money. */
          <Text style={s.body}>환불이 진행 중이에요 — 완료되면 알려드려요</Text>
        )}
        {screen === 'not_found' && (
          <Text style={s.body}>
            이 예약의 결제 정보를 볼 수 없어요 — 예약이 사라졌거나, 내 예약이 아니에요
          </Text>
        )}
        {loud && (
          // 라우드 페일(F1.2) — 풀블리드 크리티컬 헤어라인 + 서버가 한 말 그대로
          <View style={s.failStrip}>
            <Text style={s.failTxt}>
              {screen === 'failed' ? '예약 확정 전이가 실패했어요' : '서버에서 결제 정보를 받지 못했어요'}
              {failReason ? `\n${failReason}` : ''}
            </Text>
          </View>
        )}
      </ScrollView>

      {/* ── CTA — 페이즈당 잉크-필 하나 (승인 중에는 아예 없다) ──
          [O-5 §E.5.1] 확정 버튼은 삭제됐다. 이 화면의 모든 액션은 읽기(다시 불러오기)이거나
          다른 화면으로 나가는 문이다 — 예약을 앞으로 미는 버튼은 하나도 없다. */}
      <View style={s.footer}>
        {screen === 'failed' && (
          <>
            {/* 취소 CTA 없음 (C1) — 0047 전이표상 payment_hold → cancelled_owner는 불허다.
                재시도도 '다시 확정'이 아니라 '다시 읽기'다: 확정하는 문이 서버에 없다. */}
            <PaperBtn label="다시 불러오기" busyLabel="불러오는 중..." busy={busy} onPress={onReload} />
            <PaperBtn label="홈으로" variant="secondary" style={{ marginTop: 10 }} onPress={goHome} />
          </>
        )}
        {screen === 'error' && (
          <>
            <PaperBtn label="다시 불러오기" busyLabel="불러오는 중..." busy={busy} onPress={onReload} />
            <PaperBtn label="홈으로" variant="secondary" style={{ marginTop: 10 }} onPress={goHome} />
          </>
        )}
        {screen === 'authorized' && (
          <PaperBtn label="내 일정에서 확인하기" onPress={() => router.push('/owner/schedule')} />
        )}
        {screen === 'disputed' && (
          <>
            {/* [리뷰 닛] 분쟁 중의 실행 가능한 출구는 안심 센터다 — 잉크 필이 그쪽에 간다 */}
            <PaperBtn label="안심 센터 열기" onPress={() => router.push('/safety')} />
            <PaperBtn label="홈으로" variant="secondary" style={{ marginTop: 10 }} onPress={goHome} />
          </>
        )}
        {/* mock_pending도 여기 들어온다: 접수되지 않은 예약에서 할 수 있는 유일한 정직한 일은
            나가는 것이다 ('내 일정'은 거짓말이 된다 — payment_hold는 그 목록에 없다). */}
        {(screen === 'mock_pending' || screen === 'cancelled' || screen === 'refund_pending' || screen === 'not_found') && (
          <PaperBtn label="홈으로" onPress={goHome} />
        )}
      </View>
    </View>
  );
}

function ChargeRow({ label, sub, value, nf }: {
  label: string; sub?: string; value: number | null; nf: ReturnType<typeof useNumFont>;
}) {
  return (
    <View style={s.row}>
      <View style={{ flex: 1 }}>
        <Text style={s.rowLabel}>{label}</Text>
        {sub && <Text style={s.rowSub}>{sub}</Text>}
      </View>
      <View style={s.amtWrap}>
        <Text style={[s.rowAmt, nf]}>{value == null ? '—' : value.toLocaleString('ko-KR')}</Text>
        <Text style={s.rowUnit}>원</Text>
      </View>
    </View>
  );
}

// 말줄임표만 움직인다 — 스피너 연출 없음 (F2.1 'busy ≠ disabled' 쇼케이스)
function useEllipsis(on: boolean): string {
  const [n, setN] = useState(0);
  useEffect(() => {
    if (!on) { setN(0); return; }
    const t = setInterval(() => setN((v) => (v + 1) % 4), 450);
    return () => clearInterval(t);
  }, [on]);
  return '.'.repeat(n);
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: paper.canvas },
  // 풀블리드 순백 — 사이드 마진 없음. 섹션 구분은 코랄 헤어라인이 한다.
  headRow: { flexDirection: 'row', alignItems: 'flex-start', paddingHorizontal: 18 },
  back: { fontSize: 26, lineHeight: 30, color: paper.ink, marginBottom: 6 },
  // 모노 캡스 키커 — 장식 클래스(14pt 플로어 면제), 자간으로 모노 질감을 대신한다
  kicker: { fontSize: 11.5, fontWeight: '800', letterSpacing: 2.6, color: paper.faint },
  // [D13 FLOOR14 2026-08-12] 11.5 → 14. CHIP은 순수 라틴이 아니다 — 'MOCK · 준비 중',
  // 'REVIEW · 확인 중', 'REFUND · 환불 중'이 한글을 싣는다. 한글은 라틴 레터스페이스 캡스
  // 키커 예외를 타지 못한다(§3). 하필 **결제 화면의 상태 표시**다. 트래킹도 1.6 → 0.8로
  // 낮춘다 — 레터스페이싱은 라틴 캡스의 문법이고 한글에 걸면 자간이 벌어져 더 안 읽힌다.
  chip: { fontSize: 14, lineHeight: 18, fontWeight: '800', letterSpacing: 0.8, color: paper.dim, marginTop: 2 },
  // [리뷰 #9] critical 잉크는 ≥14pt/700 플로어를 받는다 — 라우드일 땐 장식 클래스에서 승격
  chipLoud: { color: paper.critical, fontSize: 14, letterSpacing: 0.8 },
  headline: { fontSize: 25.5, lineHeight: 32, fontWeight: '900', color: paper.ink, paddingHorizontal: 18, marginTop: 10 },
  meta: { fontSize: 14.5, lineHeight: 19, color: paper.dim, paddingHorizontal: 18, marginTop: 6 },
  body: { fontSize: 15, lineHeight: 21, color: paper.text, paddingHorizontal: 18, marginTop: 16 },
  // 청구 테이블 — 행 구분은 풀블리드 헤어라인, 카드도 그림자도 없다
  table: { marginTop: 22 },
  row: {
    flexDirection: 'row', alignItems: 'center', paddingHorizontal: 18, paddingVertical: 13,
    borderTopWidth: 1, borderColor: paper.line,
  },
  rowLabel: { fontSize: 14.5, fontWeight: '600', color: paper.text },
  rowSub: { fontSize: 14, lineHeight: 18, color: paper.dim, marginTop: 2 },
  amtWrap: { flexDirection: 'row', alignItems: 'baseline' },
  rowAmt: { fontSize: 17, lineHeight: 21, fontWeight: '600', color: paper.text, fontVariant: ['tabular-nums'] },
  rowUnit: { fontSize: 14, fontWeight: '600', color: paper.dim, marginLeft: 2 },
  rule: { borderTopWidth: 1, borderColor: paper.line }, // 이중 룰의 한 줄
  totalRow: { flexDirection: 'row', alignItems: 'baseline', paddingHorizontal: 18, paddingVertical: 15 },
  totalLabel: { flex: 1, fontSize: 14.5, fontWeight: '800', color: paper.ink },
  // 큰 Oswald 숫자 — lineHeight ≥ 1.2× (상단 클리핑 방지, BUG A)
  totalAmt: { fontSize: 38, lineHeight: 46, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] },
  totalUnit: { fontSize: 15, fontWeight: '700', color: paper.dim, marginLeft: 3 },
  // 결제 수단 자리 — 가짜 계좌·카드 숫자 대신 정직한 고지 플레이트
  plate: { backgroundColor: paper.wash, marginTop: 18, paddingHorizontal: 18, paddingVertical: 14 },
  plateTxt: { fontSize: 14.5, lineHeight: 20, fontWeight: '700', color: paper.text },
  failStrip: {
    marginTop: 18, backgroundColor: paper.criticalWash,
    borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    paddingHorizontal: 18, paddingVertical: 12,
  },
  failTxt: { fontSize: 14, lineHeight: 19, fontWeight: '700', color: paper.critical },
  footer: { paddingHorizontal: 18, paddingTop: 14, paddingBottom: 34, borderTopWidth: 1, borderColor: paper.line },
});
