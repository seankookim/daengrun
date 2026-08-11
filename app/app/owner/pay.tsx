import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { PaperBtn } from '../../src/components/paper-btn';
import { BookingCharge, confirmPayment, createRecurringSeries, fetchBookingCharge, requestRunner } from '../../src/lib/api';
import { useNumFont } from '../../src/lib/fonts';
import { derivePayPhase, PayPhase } from '../../src/lib/payphase';
import { draft } from '../../src/store';
import { paper, pricing } from '../../src/theme';

// 결제 표면 `/owner/pay?bid=` — 예약 하나의 결제 상태를 서버 진실로만 말하는 화면.
// [정직 배치 2026-08-06 · 웨이브 2 item 1] 100% 목업이던 영수증(지어낸 러닝 기록·가짜 결제수단 끝자리·
// 목업 draft 재계산 총액·'결제하고 리뷰 남기기')을 통째로 은퇴시키고, PG 상태 머신 위에 다시 세웠다.
// 페이즈 파생은 src/lib/payphase.ts 하나 — PG 실연동(phase ④)은 드라이버만 추가하면 된다(3차 리빌드 없음).
//
// 오늘의 진실: PG는 목업이다. 그래서 '결제됐다'고 말하지 않는다 — 확정 시 실결제가 없다고 화면이 먼저 말한다.
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
  mock_pending: '예약 확정 전이에요',
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
  // recurring/after는 draft가 아니라 파라미터로 온다 — 이번 내비게이션의 의도이지 예약 초안의 속성이 아니다
  // (draft에 남기면 다음 예약까지 따라붙어 오발사한다). after=radar는 파인드나우 전용 (지명 없음).
  const { bid, recurring, after, exp } = useLocalSearchParams<{ bid?: string; recurring?: string; after?: string; exp?: string }>();
  // [리뷰 #5] 실홀드 만료 — 이 화면에 오래 머물면 슬롯 홀드(5분)가 조용히 풀린다. 시각을 정직하게 말한다.
  const holdUntil = exp ? new Date(exp) : null;
  const holdLabel = holdUntil && !isNaN(holdUntil.getTime())
    ? `${String(holdUntil.getHours()).padStart(2, '0')}:${String(holdUntil.getMinutes()).padStart(2, '0')}`
    : null;
  const [screen, setScreen] = useState<PayScreen>('loading');
  const [charge, setCharge] = useState<BookingCharge | null>(null);
  const [busy, setBusy] = useState(false);
  const [failReason, setFailReason] = useState<string | null>(null);

  // 청구 로드 — 반환값은 '방금 파생된 페이즈'다 (재시도가 그 값으로 판단한다, H2)
  const load = useCallback(async (): Promise<PayScreen> => {
    if (!bid) { setScreen('not_found'); return 'not_found'; }
    try {
      const c = await fetchBookingCharge(bid);
      if (!c) { setCharge(null); setScreen('not_found'); return 'not_found'; } // 0행·남의 예약 (H3/M5)
      setCharge(c);
      const phase = derivePayPhase({ status: c.status }); // attempt는 오늘 없다 — PG 슬라이스가 채운다
      setScreen(phase);
      return phase;
    } catch (e) {
      setFailReason(msgOf(e));
      setScreen('error'); // 로딩도 0도 아니다 — 못 불러왔다고 말한다
      return 'error';
    }
  }, [bid]);

  useEffect(() => { load(); }, [load]);

  // ── 확정 이후 블록 (웨이브 2 리뷰 C3/C4) ──────────────────────────────────────────────
  // request.tsx의 결제 직후 로직이 통째로 여기로 옮겨왔다. 그 자리에 남으면:
  //   C4 — createRecurringSeries가 확정 전에 돌아 미결제 주간 예약이 생성됐고,
  //   C3 — 지명 requestRunner가 payment_hold 상태에서 409로 조용히 증발했다.
  // 이제 confirmPayment가 성공한 뒤에만, 이 순서로 돈다.
  const postConfirm = useCallback(async (bookingId: string) => {
    draft.bookingId = bookingId;
    // 매주 반복 (0026) — 시리즈 생성 실패가 이번 예약을 막지 않는다 (예약은 이미 성립)
    if (recurring === '1') {
      try {
        await createRecurringSeries(bookingId);
      } catch (e) {
        Alert.alert('반복 설정 실패', `이번 예약은 확정됐지만 매주 반복 설정에 실패했어요 — 다음 예약 때 다시 켜주세요\n(${msgOf(e)})`);
      }
    }
    // 지명 예약: 확정 직후 여기서 바로 지명 전송 — 러너 선택 화면을 아예 거치지 않는다
    let nominated: string | null = null;
    if (draft.preferredRunnerId) {
      const who = draft.preferredRunnerName ?? '선택한';
      try {
        await requestRunner(bookingId, draft.preferredRunnerId);
        nominated = who;
        draft.preferredRunnerId = null;
        draft.preferredRunnerName = null;
      } catch (e) {
        // 조용한 warn 삼킴 금지 (C3) — 지명이 실패했다는 사실을 사용자가 알아야 다음 선택을 한다.
        // preferred는 남긴다: 매칭 화면이 같은 지명을 자동으로 한 번 더 시도한다 (matching.tsx:191)
        Alert.alert('지명 요청 실패', `${who} 러너에게 우선 요청을 보내지 못했어요 — 매칭 화면에서 다시 골라주세요\n(${msgOf(e)})`);
      }
    }
    if (nominated) {
      // 지명 완료 — 러너 선택 화면 건너뛰고 내 일정에서 대기
      Alert.alert('지명 요청 전송', `${nominated} 러너에게 우선 요청을 보냈어요.\n수락하면 알림으로 알려드릴게요.`);
      router.replace('/owner/schedule');
      return;
    }
    router.push(after === 'radar' ? '/owner/radar' : '/owner/matching');
  }, [recurring, after]);

  // confirmPayment 1회 — busy 관리는 호출자가 한다 (재시도가 재fetch와 한 덩어리로 묶기 때문)
  const runConfirm = useCallback(async (bookingId: string) => {
    try {
      await confirmPayment(bookingId);
      setFailReason(null);
      setScreen('authorized');
      await postConfirm(bookingId);
    } catch (e) {
      setFailReason(msgOf(e)); // 실패 사유는 서버가 한 말 그대로 (침묵도, 각색도 없다)
      setScreen('failed');
    }
  }, [postConfirm]);

  // [M2 수용 명기] 이 화면을 떠나면(뒤로/앱 종료) 예약은 payment_hold로 남는다 — fetchMyBookings가
  // 결제 미완 유령을 걸러(api.ts '유령은 일정이 아니다' 법) 어디에도 안 보이고, 슬롯 홀드는 5분 뒤
  // 풀린다. 잔존 행 만료는 웨이브 3 서버 슬라이스(expire 확장) 몫 — 수용된 결과다.
  // [리뷰 #8] busy state는 같은 커밋 안의 더블탭을 못 막는다 — ref가 동기 가드
  const inFlight = useRef(false);

  const onConfirm = useCallback(async () => {
    if (!bid || busy || inFlight.current) return;
    inFlight.current = true;
    setBusy(true);
    await runConfirm(bid);
    setBusy(false);
    inFlight.current = false;
  }, [bid, busy, runConfirm]);

  // 재시도 (H2) — 재fetch → 재파생 → 여전히 payment_hold일 때만 confirm.
  // 서버가 이미 앞서 갔으면(다른 기기·크론) 새 진실을 그대로 채택한다 (409 레이스 방지).
  // [리뷰 #2] 첫 confirm이 서버에선 성공했는데 응답만 유실된 경우(fresh=authorized):
  // post-confirm 블록(리커링·지명·라우팅)을 여기서 반드시 이어간다 — 아니면 지명이 조용히 증발한다.
  const onRetry = useCallback(async () => {
    if (!bid || busy || inFlight.current) return;
    inFlight.current = true;
    setBusy(true);
    const fresh = await load();
    if (fresh === 'mock_pending') await runConfirm(bid);
    else if (fresh === 'authorized') await postConfirm(bid);
    setBusy(false);
    inFlight.current = false;
  }, [bid, busy, load, runConfirm, postConfirm]);

  // 통신 실패 전용 재시도 — 다시 읽기만 한다 (사용자가 요청하지 않은 결제를 시키지 않는다)
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
      onConfirm={onConfirm}
      onRetry={onRetry}
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
  onConfirm: () => void;
  onRetry: () => void;
  onReload: () => void;
  onBack: () => void;
}

// 순수 표현 컴포넌트 — 상태는 위에서만 만든다. dev 페이즈 랩(app/dev/pay-lab.tsx)이 이걸 그대로 쓴다
// (L2: 프로덕션 화면에 __DEV__ 분기를 만들지 않기 위해 뷰를 밖으로 뽑았다).
export function PayView({ screen, charge, busy, failReason, holdLabel, onConfirm, onRetry, onReload, onBack }: PayViewProps) {
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
            <Text style={s.plateTxt}>
              결제 수단 연동 준비 중 — 파일럿 기간에는 확정 시 실결제가 발생하지 않아요
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

      {/* ── CTA — 페이즈당 잉크-필 하나 (승인 중에는 아예 없다) ── */}
      <View style={s.footer}>
        {screen === 'mock_pending' && (
          <PaperBtn label="예약 확정하기" busyLabel="확정 중..." busy={busy} onPress={onConfirm} />
        )}
        {screen === 'failed' && (
          <>
            {/* 취소 CTA 없음 (C1) — 0047 전이표상 payment_hold → cancelled_owner는 불허다.
                죽은 버튼을 두느니 정직한 출구는 재시도와 홈뿐이다. */}
            <PaperBtn label="다시 시도" busyLabel="확인 중..." busy={busy} onPress={onRetry} />
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
        {(screen === 'cancelled' || screen === 'refund_pending' || screen === 'not_found') && (
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
