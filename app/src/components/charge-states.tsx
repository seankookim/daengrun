// 청구 상태의 단 하나의 어휘 — post-pay charge slice (payments-toss-plan §0-bis/§0-ter).
//
// Why a shared component and not per-screen copy: the same three facts (this charge failed /
// the card must be re-linked / new bookings are locked) surface on FOUR surfaces — 설정 → 결제
// 관리, 예약 상세의 결제 내역, 러닝 요청, and the dev lab. Written four times they would drift,
// and money copy that drifts is money copy that lies somewhere.
//
// Laws this file carries:
//  · 가격 비가시성(§0-bis) — money UI exists on demand (영수증) and on exception (아래 배너).
//    Exceptions are LOUD. Receipts are quiet. Neither invents a number: `amount` is the server's.
//  · Honesty — an unknown status renders as itself, never as a friendly guess; a failure names
//    the decline when the server gave us one.
//  · Paper world (DESIGN.md §2 — 거래 화면) : sharp corners, coral hairline rows, criticalWash
//    fail strips, detail text ≥14pt, Oswald numerals with explicit lineHeight (BUG A).
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { PaymentRecord } from '../lib/api';
import { useNumFont } from '../lib/fonts';
import { paper } from '../theme';

// payments.status → 보호자가 읽는 말. 'waived'(청구 없음)는 0원짜리 의도된 무청구다 —
// 실패가 아니므로 조용한 톤, failed만 크리티컬 잉크를 쓴다.
const STATUS_LABEL: Record<string, string> = {
  pending: '청구 진행 중',
  confirmed: '결제 완료',
  canceled: '청구 취소됨',
  partial_canceled: '부분 취소됨',
  failed: '결제 실패',
  waived: '청구 없음',
};

// ⚠ 검토 중인 무청구는 확정된 무청구와 **다른 말**이어야 한다. 0084 §B는 `incident` 종료에
// 0원 waived 행을 쓰면서 raw.review 표식을 남기고, 그 사건의 돈 판단은 0072의 케이스 정산이
// 소유한다 — 즉 아직 끝나지 않았다. 둘을 같은 '청구 없음'으로 그리면 화면이 열린 사건을
// 종결된 것처럼 말한다(정직법). 상태 어휘가 서버 상태를 뭉갤 때는 rawStatus로 게이트한다는
// CLAUDE.md의 규칙과 같은 문제, 같은 답.
export const paymentStatusLabel = (status: string, underReview = false): string =>
  underReview && status === 'waived' ? '확인 중 — 지금은 청구된 금액이 없어요' : (STATUS_LABEL[status] ?? status);

// 날짜 — Asia/Seoul 고정 (기기 타임존 금지, api.ts kstParts와 같은 이유)
function dayLabel(iso: string | null): string {
  if (!iso) return '';
  try {
    return new Intl.DateTimeFormat('ko-KR', { timeZone: 'Asia/Seoul', month: 'long', day: 'numeric' })
      .format(new Date(iso));
  } catch {
    const d = new Date(iso);
    return `${d.getMonth() + 1}월 ${d.getDate()}일`;
  }
}

/** 영수증 한 줄. 숫자는 전부 payments 행에서 온다 — 이 컴포넌트는 계산하지 않는다. */
export function PaymentRow({ p, showDog = true }: { p: PaymentRecord; showDog?: boolean }) {
  const nf = useNumFont();
  const failed = p.status === 'failed';
  const when = dayLabel(p.scheduledAt ?? p.createdAt);
  const title = [showDog ? p.dogName : null, when].filter(Boolean).join(' · ') || '러닝';
  return (
    <View style={s.row}>
      <View style={{ flex: 1, paddingRight: 12 }}>
        <Text style={s.rowTitle} numberOfLines={1}>{title}</Text>
        <Text style={s.rowSub}>청구 {dayLabel(p.createdAt)}</Text>
        {/* 거절은 이름으로 말한다 — 서버가 준 사유가 있을 때만 (없으면 지어내지 않는다) */}
        {failed && p.lastError != null && (
          <Text style={s.rowErr} numberOfLines={2}>{p.lastError}</Text>
        )}
        {p.refundedAmount > 0 && (
          <Text style={s.rowSub}>환불 {p.refundedAmount.toLocaleString('ko-KR')}원</Text>
        )}
      </View>
      <View style={{ alignItems: 'flex-end' }}>
        <Text style={[s.amt, nf]}>
          {p.amount.toLocaleString('ko-KR')}<Text style={s.amtUnit}> 원</Text>
        </Text>
        <Text style={[s.status, failed && { color: paper.critical }]}>{paymentStatusLabel(p.status, p.underReview)}</Text>
      </View>
    </View>
  );
}

// 예외 상태 3종 — 숨길 수 없는 것들 (§0-bis: 예외는 크게).
//  debt     = 미해결 청구로 새 예약이 잠긴 상태 (my_unsettled_charge)
//  relink   = 빌링키가 죽었다 (raw.needs_card_relink) — 일반 거절과 다른 사실
//  declined = 이번 청구가 카드사에서 거절됐다
export type ChargeBannerKind = 'debt' | 'relink' | 'declined';

const BANNER: Record<ChargeBannerKind, { title: string; body: string }> = {
  debt: {
    title: '결제 문제로 새 예약이 잠겼어요',
    body: '지난 러닝의 청구가 아직 처리되지 않았어요 — 정산이 끝나면 다시 예약할 수 있어요.',
  },
  relink: {
    title: '카드를 다시 연결해야 해요',
    body: '등록된 카드로 청구할 수 없었어요 (만료·해지·정지). 카드 재연결 화면은 아직 준비 중이라, 문의로 알려주시면 직접 도와드려요.',
  },
  declined: {
    title: '이번 청구가 거절됐어요',
    body: '카드사에서 결제가 거절됐어요 — 다시 시도하거나, 카드 상태를 확인해주세요.',
  },
};

/**
 * 라우드 페일 스트립 문법 (criticalWash 면 + 크리티컬 잉크 + 밑줄 액션, ≥44pt 타깃).
 * `cta`가 없으면 액션 없이 사실만 말한다 — 효과 없는 버튼을 그리지 않는다 (죽은 버튼 금지).
 */
export function ChargeBanner({ kind, detail, cta, busyCta, busy = false, onPress, style }: {
  kind: ChargeBannerKind;
  detail?: string | null;   // 서버가 준 한 줄 (거절 사유 등) — 없으면 렌더 안 함
  cta?: string;
  busyCta?: string;
  busy?: boolean;
  onPress?: () => void;
  style?: object;
}) {
  const c = BANNER[kind];
  return (
    <View style={[s.banner, style]}>
      <Text style={s.bannerTitle}>{c.title}</Text>
      <Text style={s.bannerBody}>{c.body}</Text>
      {detail != null && detail !== '' && <Text style={s.bannerDetail} numberOfLines={2}>{detail}</Text>}
      {cta && onPress && (
        <Pressable onPress={busy ? undefined : onPress} style={s.bannerBtn} accessibilityRole="button" accessibilityState={{ busy }}>
          {/* busy = 라벨 스왑 (버튼 매트릭스 법) — disabled 페인트도 불투명도 트릭도 없다 */}
          <Text style={s.bannerBtnTxt}>{busy ? (busyCta ?? '처리 중...') : cta}</Text>
        </Pressable>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  row: {
    flexDirection: 'row', alignItems: 'flex-start',
    paddingVertical: 13, borderTopWidth: 1, borderColor: paper.line,
  },
  rowTitle: { fontSize: 15, fontWeight: '800', color: paper.ink },
  rowSub: { fontSize: 14, lineHeight: 18, color: paper.dim, marginTop: 2 },
  rowErr: { fontSize: 14, lineHeight: 18, fontWeight: '700', color: paper.critical, marginTop: 3 },
  // Oswald + explicit lineHeight ≥1.2× (BUG A)
  amt: { fontSize: 19, lineHeight: 24, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] },
  amtUnit: { fontSize: 14, fontWeight: '700', color: paper.dim },
  status: { fontSize: 14, fontWeight: '800', color: paper.dim, marginTop: 2 },
  banner: {
    backgroundColor: paper.criticalWash,
    borderTopWidth: 1, borderBottomWidth: 1, borderColor: paper.critical,
    paddingHorizontal: 15, paddingVertical: 13,
  },
  bannerTitle: { fontSize: 16, lineHeight: 21, fontWeight: '800', color: paper.critical },
  bannerBody: { fontSize: 14.5, lineHeight: 20, fontWeight: '700', color: paper.text, marginTop: 4 },
  bannerDetail: { fontSize: 14, lineHeight: 18, color: paper.critical, marginTop: 4 },
  bannerBtn: { alignSelf: 'flex-start', minHeight: 44, justifyContent: 'center' },
  bannerBtnTxt: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
});
