import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { BottomNav } from '../../src/components/bottomnav';
import { PaperBtn } from '../../src/components/paper-btn';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { TabSwipe } from '../../src/components/tabswipe';
import { Row } from '../../src/components/ui';
import {
  fetchLedger, fetchLedgerMonthTotals, fetchLedgerTotal, fetchLedgerUnpaidTotal, fetchMyBankAccount,
  fetchMyPayouts, fetchMyPayoutMethodLabels, LiveLedgerItem, MyBankAccount, MyPayout,
} from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import {
  monthLabel, MONTHS_EMPTY_KO, MONTHS_WINDOW, type MonthTotal, netAmount, paidLine, runLine,
  sortMonthsNewestFirst,
} from '../../src/lib/earnings-month';
import {
  ledgerPaymentLabel, ledgerPaymentState, payoutPeriodLabel, payoutStatusWithMethod,
  sortPayoutsNewestFirst,
} from '../../src/lib/payout-status';
// RAW server text for the log. These three strips render Korean of their own and never a
// message, so the log is the ONLY place the server's own words survive.
import { rpcRaw } from '../../src/lib/rpc-error';
import { layout, paper } from '../../src/theme';

// 수익 — 실원장(ledger_items)만 표시. 정산·계좌는 백엔드 후속.
//
// [paper repaint 2026-08-11] forest/cream/volt chrome scrapped → paper. Kept as artifact:
// the settlement ticket (dark ink face — the other side of the owner's payment ticket),
// now sharp with Oswald money numerals + explicit lineHeight (BUG A). Fixed in passing:
// the ticket/stub notches were still painted stale beige #F8F6F0 against the white canvas
// — they punch paper.canvas now. Korean captions lose their latin letterspacing (§3).
// [honesty audit 2026-08-11 · P1 #3] 빠른 정산 신청 / 계좌 등록 buttons retired — both were dead
// doors firing "준비 중" alerts (demoting them to quiet outlines didn't change the lie). There is
// no real store for a waitlist/notify intent (no such table, and we don't invent schema), so an
// honest waitlist conversion is impossible today — removed until the feature exists. The missing
// account is stated as a non-pressable info sentence (the sanctioned settings.tsx 준비-중 pattern).
// Behavior frozen: fetchLedger/fetchLedgerTotal, pendingSum fallback. (The tax calc that used to
// be listed here is gone — see the 2026-08-24 margin-secrecy note below.)
//
// [journey v4 · R7b/R7c 2026-08-19] The dark settlement ticket (43.5pt volt sum, 절취선, notches)
// and the per-run ticket stubs (vertical perforation + two notches each) are RETIRED for plain
// rows. Every sentence on this screen already existed and none of them changed — what changed is
// that the SUM stopped being a hero. The lab's law for the runner journey: the amount is a plain
// row, never large, and this screen's amount is the one number a runner is most tempted to read as
// money in hand. It is not: it is a ledger total with no payout run behind it, which is exactly
// what 지급 일정 미정 says one line below. A 43.5pt volt numeral argued the opposite.
// Also retired: the ● LIVE chip (a saturated, non-actionable badge — the row says 원장 합계) and
// the per-run green net (one saturated number per ledger row × N rows). The Bd breakdown keeps its
// colour coding, which is information: coral = the fee coming off, green = money added on.
// 수수료율(33%) is a real column (runners.commission_rate) — the lab's choice not to print the RATE
// is a design decision, not a correction; the per-run 수수료 AMOUNT is a real ledger column and stays.
//
// [MARGIN SECRECY 2026-08-24 · Sean, verbatim] "For runner money, don't show them the 수수료.
// I don't think we should be showing them the calcuations ever; only show the final profit per
// run; keep the margin a secret."
// The whole per-row breakdown is gone — 기본 · 거리 · 옵션 · 잔여 보장 · 팁 · 수수료 — and that
// OVERRULES the two lines directly above: the per-run fee amount no longer stays. Removing only
// the 수수료 token would have kept no secret at all: any component printed beside the net hands
// back the fee by subtraction (fee = Σcomponents − net) and with it the rate (fee ÷ gross). So a
// row now carries exactly one figure. The word 실수령 stays — it names what the number IS (what
// lands, after everything) without printing a step of how it got there.
// ⚠ NOT stripped: 원천징수 3.3%. That is a statutory income-tax withholding, not our margin — it
// reveals nothing about commission_rate, and a runner never told about it is short at payout. It
// is now stated as a fact in words rather than as an arithmetic result glued to the balance,
// which honours "no calculations" without dropping a disclosure we owe.
// The blue judgment was RULED on 2026-08-25 — Sean, Q7, verbatim: "sure include that statement
// but make it small and show once only." Kept, shrunk to one dim 14pt caption line, stated in
// exactly one place on the screen. See the caption's own comment for what small and once mean.
// After this edit the screen reads exactly TWO money values: LiveLedgerItem.net and
// my_ledger_total. base · distancePay · addonPay · tip · guarantee · fee are no longer read here.

// [2026-08-11] nextWednesday() 삭제 — 오늘 아침 '다음 정산일 <수요일>'을 지웠을 때(존재하지 않는
// 지급 운영의 날짜였다) 계산 함수만 남아 호출부 0으로 떠 있었다. 죽은 코드이자, 되살리기 쉬운
// 형태로 남은 거짓 약속이다.

export default function Earnings() {
  const insets = useSafeAreaInsets();
  const df = useDisplayFont(); // display font — screen title (1/screen budget)
  const nf = useNumFont();     // Oswald — settlement sum, per-run nets
  const [ledger, setLedger] = useState<LiveLedgerItem[]>([]);

  const [total, setTotal] = useState<number | null>(null);
  // [honesty 2026-08-11] warn-only catch + no loading state rendered "0원" + "아직
  // 정산 내역이 없어요" in flight and on failure. Three states now.
  const [loaded, setLoaded] = useState(false);
  const [loadErr, setLoadErr] = useState(false);
  // [honesty 2026-08-19 · runner review P2] 실패하면 **값을 버린다** (requests.tsx:99-106과 같은 법).
  // 종전엔 loaded/total/ledger를 catch에서 건드리지 않아, 한 번 성공한 뒤의 실패한 당겨-새로고침이
  // '정산 내역을 불러오지 못했어요' 스트립 **바로 아래**에 이전 합계와 이전 행들을 그대로 인쇄했고,
  // 그 낡은 합계가 원천징수 추정치까지 몰았다. sumKnown 게이트는 0원 위장을 막는 장치이지,
  // 옛 숫자를 지금 숫자로 파는 것을 막는 장치가 아니다.
  // [0192] 미지급 합계 — my_ledger_unpaid_total. 평생 누계(total)와 **다른 문장**이고, 0186이
  // payouts에 쓰는 쪽을 만들기 전까지는 둘이 항상 같았다. 이제 갈라진다.
  const [unpaid, setUnpaid] = useState<number | null>(null);

  // [0192] 지급 내역은 **자기 로드 그룹**이다. 원장과 한 Promise.all에 묶으면 payouts 한 번의
  // 실패가 멀쩡히 읽힌 원장까지 지운다 — 그건 실패를 실패로 보이게 하는 게 아니라 성공을
  // 실패로 지우는 것이다. 행별 「지급 완료」 배지는 원장 읽기(paid_payout_id)에서 나오므로 이
  // 그룹이 죽어도 정확하게 유지된다.
  const [payouts, setPayouts] = useState<MyPayout[]>([]);
  const [poLoaded, setPoLoaded] = useState(false);
  const [poErr, setPoErr] = useState(false);
  // [0200] 지급 수단 라벨 — payout id → 「계좌 이체」. `payouts.method` is sealed away from the
  // runner by 0186:192-195 (and that seal stays), so the LABEL comes from its own definer.
  // ⚠ NO error flag and no loading state, deliberately: this is ADDITIVE information on a row
  //   that is already complete and correct without it. An empty map is 「we have nothing to add」
  //   and a failed read is the same — the element is omitted, exactly as it is for a method this
  //   server has no label for. A failure strip here would report a missing *adjective* on a money
  //   row whose noun and number are right, which is noise the 지급 내역 strip above already owns
  //   for the failure that actually matters.
  const [methodLabels, setMethodLabels] = useState<Map<string, string>>(new Map());

  // [0209] 월별 수익 — **자기 로드 그룹**이고, 0192가 지급 내역을 떼어 낸 것과 같은 이유다: 한
  // 읽기의 실패가 다른 읽기의 성공을 지우면 그건 실패를 실패로 보이게 하는 게 아니라 성공을
  // 실패로 지우는 것이다. 여기엔 실패 스트립이 **있다** — 0200의 수단 라벨과 달리 이건 행 위에
  // 얹는 형용사가 아니라 그 자체로 한 섹션이고, 없으면 섹션이 통째로 빈다. 빈 섹션과 못 읽은
  // 섹션은 러너에게 전혀 다른 사실이다.
  const [months, setMonths] = useState<MonthTotal[]>([]);
  const [moLoaded, setMoLoaded] = useState(false);
  const [moErr, setMoErr] = useState(false);
  const loadMonths = () => {
    setMoErr(false);
    return fetchLedgerMonthTotals(MONTHS_WINDOW)
      .then((rows) => { setMonths(sortMonthsNewestFirst(rows)); setMoLoaded(true); })
      .catch((e) => {
        // 같은 법(requests.tsx:99-106): 실패하면 **값을 버린다**. 실패 스트립 아래에 지난번 달
        // 목록을 그대로 두면, 방금 끝난 이번 달이 없는 것처럼 읽힌다.
        console.warn('[earnings] months:', rpcRaw(e));
        setMoLoaded(false);
        setMonths([]);
        setMoErr(true);
      });
  };

  const loadLedger = () => {
    setLoadErr(false);
    return Promise.all([
      fetchLedger().then(setLedger),
      fetchLedgerTotal().then(setTotal),
      fetchLedgerUnpaidTotal().then(setUnpaid),
    ]).then(() => setLoaded(true))
      .catch((e) => {
        console.warn('[earnings] ledger:', rpcRaw(e));
        setLoaded(false);
        setTotal(null);
        setUnpaid(null);
        setLedger([]);
        setLoadErr(true);
      });
  };
  const loadPayouts = () => {
    setPoErr(false);
    return fetchMyPayouts()
      .then((rows) => {
        setPayouts(sortPayoutsNewestFirst(rows));
        setPoLoaded(true);
        // [0200] the labels, AFTER the rows and never instead of them. Chained rather than run in
        // a `Promise.all` beside `fetchMyPayouts` for the reason this whole group exists: one
        // read's failure must not erase the other's success, and here the dependency runs one way
        // — there is nothing to label until the ids are in hand. 세터는 성공에서만 돈다.
        setMethodLabels(new Map());
        fetchMyPayoutMethodLabels(rows.map((r) => r.id))
          .then(setMethodLabels)
          .catch((e2) => console.warn('[earnings] payout methods:', rpcRaw(e2)));
      })
      .catch((e) => {
        // 같은 법(requests.tsx:99-106): 실패하면 **값을 버린다**. 실패 스트립 아래에 지난번
        // 지급 목록을 그대로 두면, 방금 들어온 지급이 없는 것처럼 읽힌다.
        console.warn('[earnings] payouts:', rpcRaw(e));
        setPoLoaded(false);
        setPayouts([]);
        setMethodLabels(new Map());
        setPoErr(true);
      });
  };
  const load = () => Promise.all([loadLedger(), loadPayouts(), loadMonths()]);
  useFocusEffect(useCallback(() => { load(); }, []));
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  // [0192] 합계 줄의 주어가 바뀐다 — 그리고 **이것이 이 슬라이스의 클라이언트 쪽 결함이다.**
  // 종전 라벨은 「정산 예정 · 원장 합계」였고, my_ledger_total은 평생 누계다. 0186 이전에는
  // payouts에 쓰는 쪽이 없어 지급된 행이 존재할 수 없었으므로 그 라벨은 참이었다. 첫 수기 지급이
  // 들어오는 순간, 그 줄은 **이미 통장에 들어간 돈을 아직 올 돈이라고** 말한다. 코드는 한 글자도
  // 바뀌지 않았고 게이트도 하나 안 빨개진다(§④ 부류: 결함은 바뀌지 않은 줄이다).
  // 이제 미지급 합계가 주 숫자이고, 평생 누계는 그 아래 한 줄로 사실로서 남는다 — 지우면 러너가
  // 자기가 이 앱에서 얼마를 벌었는지 볼 곳이 없어진다.
  // [honesty 2026-08-11, 그대로] sumKnown 전에는 '—' — 로딩/실패를 0원으로 위장하지 않는다.
  // ⚠ 30행 캡 합산 폴백은 **미지급 합계에 쓰지 않는다**: 캡 안의 미지급 행 합은 31번째부터
  //   실제보다 작고, 「덜 받을 돈」을 발명하는 쪽이 「모른다」보다 나쁘다.
  const unpaidKnown = unpaid != null;
  const lifetimeKnown = loaded || total != null;
  const lifetimeSum = total ?? ledger.reduce((sum, l) => sum + l.net, 0);

  // [0194] 정산 계좌 — 이 화면은 0001 부터 있던 `bank_accounts` 에 행을 만들 방법이 없다는 사실을
  // 「계좌 등록은 오픈뱅킹 연동과 함께 제공돼요」라는 문장으로 정직하게 적어 두고 있었다. 이제
  // 등록하는 화면(`runner/bank-account`)이 있으므로 그 문장은 거짓이 됐고, 자리에는 실상태가 온다.
  // ⚠ 원장 로드와 **일부러 분리**돼 있다: 계좌를 못 읽는 것과 정산 내역을 못 읽는 것은 다른 실패이고,
  //   하나가 다른 하나의 스트립을 띄우면 러너는 고칠 수 없는 것을 고치려 든다.
  const [bankAcct, setBankAcct] = useState<MyBankAccount | null>(null);
  const [bankPhase, setBankPhase] = useState<'loading' | 'error' | 'ready'>('loading');
  const loadBank = useCallback(() => {
    setBankPhase('loading');
    fetchMyBankAccount()
      .then((row) => { setBankAcct(row); setBankPhase('ready'); })
      .catch((e) => {
        console.warn('[earnings] bank:', rpcRaw(e));
        setBankAcct(null);
        setBankPhase('error');
      });
  }, []);
  useFocusEffect(useCallback(() => { loadBank(); }, [loadBank]));


  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <TabSwipe>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: insets.top + 4, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        {/* [§3c 화면 타이틀 2026-08-11] 30/900 · lineHeight 37 (1.23× — BUG A) */}
        <Text style={[{ fontSize: 30, lineHeight: 37, fontWeight: '900', color: paper.ink }, df]}>수익</Text>

        {/* 합계 — 한 줄. sumKnown 게이트는 그대로: 로딩·실패를 0원으로 위장하지 않는다 ('—'). */}
        <View style={[s.rule, { marginTop: 14 }]} />
        <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
          <Text style={s.sumLabel}>아직 받지 않은 금액</Text>
          {unpaidKnown ? (
            <Row style={{ alignItems: 'baseline' }}>
              {/* Oswald sum — lineHeight 24 = 1.26× (BUG A) */}
              <Text style={[s.sumNum, nf]}>{unpaid.toLocaleString()}</Text>
              <Text style={s.sumUnit}>원</Text>
            </Row>
          ) : (
            <Text style={s.sumUnknown}>—</Text>
          )}
        </Row>
        {/* 평생 누계는 사라지지 않는다 — 주어만 양보한다. 두 숫자가 같으면 아직 한 번도 지급이
            없었다는 뜻이고, 그건 오늘 모든 러너의 상태다. */}
        <Row style={{ justifyContent: 'space-between', alignItems: 'baseline', marginTop: 4 }}>
          <Text style={s.subLabel}>지금까지 번 금액 (누적)</Text>
          {lifetimeKnown ? (
            <Row style={{ alignItems: 'baseline' }}>
              <Text style={[s.subNum, nf]}>{lifetimeSum.toLocaleString()}</Text>
              <Text style={s.subUnit}>원</Text>
            </Row>
          ) : (
            <Text style={s.subUnknown}>—</Text>
          )}
        </Row>
        {/* [2026-08-11] '다음 정산일 <수요일>'은 존재하지 않는 지급 운영의 날짜를 못박았다.
            실결제도 러너 지급 코드도 아직 없다 — 날짜는 지운다.
            [margin secrecy 2026-08-24] 그 자리에 있던 '약 −1,524원 예정'(= pendingSum × 0.033)도
            지운다. 세율은 제도라 숨길 것이 없지만, 잔액 옆에 놓인 **계산 결과**는 이 화면이 더는
            그리지 않는 것이다. 사실은 낱말로 남긴다 — 지워버리면 러너가 지급일에 덜 받는다.

            [Q7 · Sean 2026-08-25, verbatim] "sure include that statement but make it small and
            show once only."
            SMALL: type size was already the floor — 14pt is the detail floor and is law, so nothing
            here may go below it; it stays paper.dim, no weight, no colour. Footprint was the only
            lever left, so the sentence was tightened from 「지급할 때 사업소득 3.3%가 원천징수돼요」
            to a fragment parallel with 지급 일정 미정. It now rides the same caption on ONE line
            instead of wrapping into a two-line block (estimated, NOT simulator-verified: the old
            string runs ~375pt of glyphs against a 363pt content width — 393pt device minus the
            2×15 gutter — so it wrapped there and on every narrower phone). Nothing was
            dropped: timing (지급 시), income class (사업소득), rate (3.3%), action (원천징수).
            ONCE = once per screen. This caption is the single place the withholding is ever
            stated: once for the whole ledger, never per row, and the tail note below stays
            deliberately silent about it. It is not gated, so it is always present when the 합계
            block renders — which is what a disclosure has to be. If he meant once-EVER (shown to
            a runner one time, then never again), that is an AsyncStorage seen-flag around this
            one Text — not built, deliberately: a tax fact a runner cannot find again is a fact
            they do not have at payout. */}
        <Text style={s.sumNote}>
          지급 일정 미정 · 지급 시 사업소득 3.3% 원천징수
        </Text>

        {/* bank account — [0194] a real door now. Four states, all different: loading is not
            「없어요」, a failure is a failure with a retry, a registered account shows the SERVER's
            mask (the full number never reaches this app), and no account is an invitation. */}
        <View style={s.rule} />
        <Text style={s.secTitle}>정산 계좌</Text>
        {bankPhase === 'loading' && (
          <Text style={{ fontSize: 15, color: paper.dim, marginTop: 3, lineHeight: 19 }}>
            계좌 정보를 불러오는 중…
          </Text>
        )}
        {bankPhase === 'error' && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>정산 계좌를 불러오지 못했어요</Text>
            <Pressable onPress={loadBank} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {bankPhase === 'ready' && bankAcct !== null && (
          <Row style={{ justifyContent: 'space-between', alignItems: 'center', marginTop: 5 }}>
            <View style={{ flex: 1, paddingRight: 12 }}>
              <Text style={{ fontSize: 16, fontWeight: '700', color: paper.ink, lineHeight: 22 }}>
                {bankAcct.accountMasked === null
                  ? (bankAcct.bankLabel ?? bankAcct.bank)
                  : `${bankAcct.bankLabel ?? bankAcct.bank} ${bankAcct.accountMasked}`}
              </Text>
              {/* 복호화가 안 되는 행은 실패다 — dim 으로 적으면 그냥 정보처럼 읽힌다. */}
              <Text style={{
                fontSize: 15, marginTop: 2, lineHeight: 20,
                color: bankAcct.accountMasked === null ? paper.critical : paper.dim,
                fontWeight: bankAcct.accountMasked === null ? '700' : '400',
              }}>
                {bankAcct.accountMasked === null ? '계좌를 읽지 못했어요 — 다시 등록해주세요' : bankAcct.holder}
              </Text>
            </View>
            <Pressable
              onPress={() => router.push('/runner/bank-account')}
              style={s.bankChange}
              accessibilityRole="button"
              accessibilityLabel="정산 계좌 변경"
            >
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.actionInk }}>변경</Text>
            </Pressable>
          </Row>
        )}
        {/* 🔴 [ui-consistency-2] 잉크 면 프라이머리 은퇴 → PaperBtn. paper-btn.tsx:1-9가 기록한
            2026-08-11 Sean의 재정은 「검정 버튼이 싫다 … 액션 버튼은 동기를 일으켜야 한다」이고,
            이 버튼은 이 화면에서 러너가 할 수 있는 가장 중요한 한 가지다 — 돈 받을 곳을 등록하는
            문. 손으로 만 잉크 면 + 4px 립은 그 매트릭스를 화면 하나가 다시 구현한 것이었고,
            DESIGN.md:203의 「primary = ink face」 줄은 그 재정보다 **먼저** 쓰인 낡은 표다.
            치수·립·눌림 산식은 이제 매트릭스가 갖고, 여기 남는 것은 자리(marginTop)뿐이다. */}
        {bankPhase === 'ready' && bankAcct === null && (
          <PaperBtn label="정산 계좌 등록하기" onPress={() => router.push('/runner/bank-account')} style={s.bankRegister} />
        )}

        {/* ---------- [0209] 월별 수익 — my_ledger_month_totals, 최근 6개 KST 달 ---------- */}
        {/* 러닝별 내역 **바로 위**다. 아래 목록은 서버에서 30행으로 잘려 오므로(0121 §A의 limit
            30) 많이 뛴 러너일수록 그 목록만으로는 지난달을 볼 수 없고, 이 섹션이 그 공백을
            메운다 — 클라가 30행을 달로 묶으면 바로 그 러너에게 조용히 틀린 숫자가 나온다.
            ⚠ 달 경계도 달 이름도 서버가 고른 KST 사실이다. month_start는 문자열로 들고 다니고
              earnings-month.ts가 **글자에서** 이름을 만든다 — new Date로 되돌리면 서울이 아닌
              폰에서 9월이 8월로 찍힌다(app/test/earnings-month.test.cjs가 세 존에서 핀).
            ⚠ 서버가 안 준 달은 **없는 달**이고, 0원 행을 만들어 채우지 않는다. 그 러너가 아직
              없던 달에 대해 「0원을 벌었다」고 쓰게 된다 (0209 §0e의 클라 쪽 절반).
            ⚠ 이 섹션에 수수료·요율·총액은 없다. 한 달 net은 아래 행들이 이미 보여 준 숫자의
              합이라 뺄셈할 상대가 없지만, 구성요소가 한 칸이라도 붙는 순간 마진이 돌아온다
              (2026-08-24 Sean). 「지급 완료」 줄은 그 net을 0186의 표식으로 가른 같은 축이다. */}
        <View style={s.rule} />
        <Text style={[s.secTitle, { marginBottom: 10 }]}>월별 수익</Text>
        {!moLoaded && !moErr && (
          // 로딩 스켈레톤 — 0이 아니고 빈 상태도 아니다. 두 줄인 이유는 이 섹션이 목록이라는
          // 것이 로딩 중에도 읽혀야 하기 때문이고, 숫자는 한 글자도 그리지 않는다.
          <View>
            {[0, 1].map((i) => (
              <Row key={i} style={[s.row, { justifyContent: 'space-between', alignItems: 'center' }]}>
                <View style={[s.skel, { width: 92 }]} />
                <View style={[s.skel, { width: 68 }]} />
              </Row>
            ))}
          </View>
        )}
        {moErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>월별 수익을 불러오지 못했어요</Text>
            <Pressable onPress={loadMonths} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {moLoaded && !moErr && months.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', lineHeight: 22 }}>
              {MONTHS_EMPTY_KO}
            </Text>
          </View>
        )}
        {moLoaded && !moErr && months.map((m) => {
          // 이름이 없는 달은 그리지 않는다 — 읽을 수 없는 month_start는 우리가 갖지 못한 달이고,
          // 그 자리에 원문을 찍으면 한국어 화면에 '2026-09-01'이 뜬다 (END_REASON_LABEL의 법).
          const label = monthLabel(m.monthStart);
          if (label == null) return null;
          const runs = runLine(m);
          const paid = paidLine(m);
          return (
            <Row key={m.monthStart} style={s.row}>
              <View style={{ flex: 1, paddingRight: 12 }}>
                <Text style={{ fontSize: 16.5, lineHeight: 22, fontWeight: '800', color: paper.ink }}>{label}</Text>
                {/* 러닝 횟수는 0이면 **말하지 않는다**: 취소 보상만 있는 달은 진짜로 0회이고
                    진짜 돈이 있어서, 「러닝 0회」가 금액 쪽 버그처럼 읽힌다 (0209 §0c). */}
                {runs != null && (
                  <Text style={{ fontSize: 15, lineHeight: 20, color: paper.dim, marginTop: 2 }}>{runs}</Text>
                )}
              </View>
              <View style={{ alignItems: 'flex-end' }}>
                <Row style={{ alignItems: 'baseline' }}>
                  {/* Oswald — lineHeight 24 = 1.26× (BUG A) */}
                  <Text style={[s.netNum, nf]}>{netAmount(m)}</Text>
                  <Text style={s.netUnit}>원</Text>
                </Row>
                {/* 지급된 금액이 있을 때만. 0원은 상태가 아니라 평범한 기다림이고,
                    「지급 완료 0원」은 실패한 이체처럼 읽힌다. */}
                {paid != null && (
                  <Text style={[s.payLine, { color: paper.readyDeep }]}>{paid}</Text>
                )}
              </View>
            </Row>
          );
        })}

        {/* ledger — §3b section header: full-bleed coral rule + 20/800 ink */}
        <View style={s.rule} />
        <Text style={[s.secTitle, { marginBottom: 10 }]}>러닝별 내역</Text>
        {!loaded && !loadErr && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center' }}>불러오는 중…</Text>
          </View>
        )}
        {/* loud-fail strip — criticalWash bg + critical ink + retry (never a fake empty) */}
        {loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>정산 내역을 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {loaded && !loadErr && ledger.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', lineHeight: 22 }}>
              아직 정산 내역이 없어요{'\n'}러닝을 완료하면 여기에 기록돼요
            </Text>
          </View>
        )}
        {/* 러닝 하나 = 한 줄. 왼쪽은 어떤 러닝이었는지, 오른쪽은 실수령 하나.
            '실수령' 낱말은 지킨다 — 랩의 '적립'과 달리 이 숫자가 **무엇인지** 말한다. 산수는 말하지
            않는다 (2026-08-24 마진 비밀 규칙: 최종 금액 하나만). */}
        {/* [0209] 행이 **문**이 됐다 — 그 러닝의 기록으로. `my_ledger_rows`는 0192부터
            booking_id를 돌려주고 매퍼도 들고 있었는데(api.ts LiveLedgerItem.bookingId) 이
            화면에서는 아무 데도 쓰이지 않았다: 러너가 「이 8,300원이 무슨 러닝이었지」를 물을
            곳이 없었고, 이 화면의 유일한 탭 가능한 것은 계좌 두 버튼이었다.
            ⚠ 목적지는 `/runner/done?bid=`이고, **bid가 있을 때만** 이 화면이 콜드 진입에
              안전하다: 0193이 그 화면을 고쳐서, bid가 오면 모든 숫자를 그 예약에 대해 서버에서
              다시 읽고(fetchReturnSeal + 원장) 세 상태로 그린다 — 로딩은 0이 아니고 실패는
              재시도가 붙은 실패다. bid 없이 들어가면 그 화면은 런타임 메모리(runResult)를
              읽으므로, 며칠 전 러닝을 여기서 열면 **직전에 끝난 다른 러닝의 숫자**가 이 예약의
              제목 아래 찍힌다 — codex A7이 이름 붙인 바로 그 결함이다. 그래서 파라미터는 선택이
              아니다.
            🔴 취소 보상 행은 **버튼이 아니다.** runs 행이 없으므로(0080/0085가 러닝 없이 쓰는
              행이다) fetchReturnSeal이 null을 내고 목적지는 「기록을 불러오지 못했어요」만
              그린다 — 있지도 않은 기록을 못 읽었다고 말하는 실패 화면이고, 그건 죽은 버튼보다
              나쁘다. cancelComp가 그 판별자이고 서버가 정한다(0121 §A: runs 행의 존재).
              그런 행은 종전 그대로 평범한 텍스트로 남는다 — 눌리지 않고, 눌리는 척도 안 한다. */}
        {ledger.map((l) => {
          const openable = !l.cancelComp && !!l.bookingId;
          const Body = (
            <>
            <View style={{ flex: 1, paddingRight: 12 }}>
              <Row style={{ gap: 6, alignItems: 'baseline', flexWrap: 'wrap' }}>
                {/* ⚠ A ledger row does not imply a run happened.
                    `record_enroute_cancel_comp` (0080) and `record_late_cancel_share` (0085) write
                    `ledger_items` for a CANCELLATION — no `runs` row exists — and this line used to
                    read the km straight off the booking, so an en-route cancel rendered
                    「초코 · 5km · 실수령 12,450원」: the runner's own ledger claiming they ran 5km.
                    `fetchLedger` resolves km from `runs` and hands back null when there is none.
                    [0132] The reason word MOVED to the line below, so this line is now one thing
                    only — what was run and how far — and the line under it is when and why. The
                    cancellation case therefore renders the dog alone here, not 「초코 · 취소 보상」:
                    that phrase is a reason, and reasons now live in one place. */}
                <Text style={{ fontSize: 16.5, lineHeight: 22, fontWeight: '800', color: paper.ink }}>
                  {l.km != null ? `${l.dogName} · ${l.km}km` : l.dogName}
                </Text>
              </Row>
              {/* [0132] Sean 2026-08-26: 「a one phrase description per ledger row … b/c price
                  fluctuates per run and runner may be like why is it different」. The price really
                  does move with the reason (0101 §A: actual-km arms · the owner-caused 50%
                  guarantee · runner_personal's distance-only delegation), so this sits directly
                  under the dog and directly beside the net — the two things being compared.
                  ⚠ It says the KIND of run and never the arithmetic. Margin secrecy (2026-08-24)
                    is a rule about components, not about honesty, and this adds no component.
                  ⚠ `reason` null → the date renders ALONE. No 「사유 없음」, no em-dash placeholder:
                    an unknown reason is a thing we do not know, and the honest rendering of that
                    is silence (same law as `cancelComp`'s "unknown is not cancelled").
                  15pt, not the 14 this line used to be — Korean detail floor (DESIGN.md §3). */}
              <Text style={{ fontSize: 15, lineHeight: 20, color: paper.dim, marginTop: 2 }}>
                {l.reason ? `${l.when} · ${l.reason}` : l.when}
              </Text>
            </View>
            <View style={{ alignItems: 'flex-end' }}>
              <Row style={{ alignItems: 'baseline' }}>
                {/* Oswald net — lineHeight 24 = 1.26× (BUG A) */}
                <Text style={[s.netNum, nf]}>{l.net.toLocaleString()}</Text>
                <Text style={s.netUnit}>원</Text>
              </Row>
              <Text style={{ fontSize: 15, lineHeight: 19, color: paper.dim }}>실수령</Text>
              {/* [0192] 이 행이 실제로 지급됐는지 — 서버의 paid_payout_id·paid_at·settled에서만
                  나온다. 세 상태이고 셋째(아직 정산 전)는 **아무 말도 하지 않는다**: 그 행은
                  금액이 아직 움직일 수 있고, 서버가 지급을 이름으로 거절하는(not_settled) 행이라
                  「지급 대기」라고 쓰면 우리가 옮기지 않을 돈을 약속하게 된다.
                  ⚠ 지급 예정일은 없다 — 서버에 일정이 없고, 없는 날짜를 그리는 것이 이 화면이
                    2026-08-11에 nextWednesday()를 지운 이유다. */}
              {(() => {
                const pay = ledgerPaymentLabel(l);
                if (pay == null) return null;
                const paid = ledgerPaymentState(l) === 'paid';
                return (
                  <Text style={[s.payLine, { color: paid ? paper.readyDeep : paper.dim }]}>
                    {pay}
                  </Text>
                );
              })()}
            </View>
            </>
          );
          if (!openable) return <Row key={l.id} style={s.row}>{Body}</Row>;
          return (
            <Pressable
              key={l.id}
              onPress={() => router.push({ pathname: '/runner/done', params: { bid: l.bookingId } })}
              accessibilityRole="button"
              accessibilityLabel={`${l.dogName} 러닝 기록 보기`}
              style={({ pressed }) => [s.row, { flexDirection: 'row' }, pressed && { backgroundColor: paper.wash }]}
            >
              {Body}
            </Pressable>
          );
        })}

        {/* ---------- [0192] 지급 내역 — payouts 자기 행 (RLS + 0186의 열 제한 그랜트) ---------- */}
        {/* 0186이 payouts에 쓰는 쪽(ops_record_manual_payout)을 만들기 전까지 이 표는 영원히 비어
            있었고, 그래서 이 화면에 없었다. 이제 실제로 채워진다.
            ⚠ 한 행에 숫자는 **하나**다. payouts.gross와 tax_withheld는 그랜트돼 있지만 읽지
              않는다 — gross−net이 곧 플랫폼 수수료이고, 그 뺄셈을 막으려고 2026-08-24에 행별
              내역 여섯 토큰을 지웠다. 그때 서른 줄에서 없앤 것을 여기서 한 줄로 돌려줄 수는 없다.
            ⚠ memo는 없다. 0186:192-195가 memo·method·recorded_by를 authenticated에게서 회수했고
              (그건 운영자끼리 보는 절반이다), 이 화면은 그 봉인을 존중한다 — 없는 필드를 그리는
              대신 요소를 뺀다.
            ⚠ [0200] **수단**은 예외가 아니라 그 봉인을 지키는 방법이다. method 열을 그랜트에
              더하면 memo의 이웃이 한 낱말 차이가 되므로, 열을 넓히는 대신 definer
              (`my_payout_method_labels`)가 고정 라벨 「계좌 이체」만 만들어 준다 — 넓힐 열 목록이
              없으니 메모 쪽으로 자랄 수 없다. 라벨이 없으면 요소를 뺀다(여기 법 그대로). */}
        <View style={s.rule} />
        <Text style={[s.secTitle, { marginBottom: 10 }]}>지급 내역</Text>
        {!poLoaded && !poErr && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center' }}>불러오는 중…</Text>
          </View>
        )}
        {poErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>지급 내역을 불러오지 못했어요</Text>
            <Pressable onPress={loadPayouts} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {poLoaded && !poErr && payouts.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', lineHeight: 22 }}>
              아직 지급된 내역이 없어요
            </Text>
          </View>
        )}
        {poLoaded && payouts.map((p) => {
          // [0200] 날짜 옆에 **수단**이 붙는다 — 라벨이 있을 때만. 없으면(아직 못 읽었든, 서버가
          // 이름을 모르는 수단이든) 줄은 종전과 바이트 그대로이고, 추측한 낱말도 매달린 구분점도
          // 생기지 않는다. 합성은 payout-status.ts가 하고 app/test/payout-status.test.cjs가 핀.
          const when = payoutStatusWithMethod(p, methodLabels.get(p.id));
          const period = payoutPeriodLabel(p);
          return (
            <Row key={p.id} style={s.row}>
              <View style={{ flex: 1, paddingRight: 12 }}>
                {/* 상태 낱말은 payouts.status를 매핑한 것이고, 모르는 값은 **아무 말도 하지
                    않는다**(END_REASON_LABEL과 같은 법 — 원문 토큰을 한국어 UI에 찍지 않는다).
                    ⚠ [0200] 수단 라벨도 서버가 고른 고정 문장이다 — raw method 토큰은 클라이언트에
                    오지 않고, 운영 메모(0186의 봉인)는 서버를 떠나지 않는다. */}
                {when != null && (
                  <Text style={{ fontSize: 16.5, lineHeight: 22, fontWeight: '800', color: paper.ink }}>{when}</Text>
                )}
                {period != null && (
                  <Text style={{ fontSize: 15, lineHeight: 20, color: paper.dim, marginTop: 2 }}>{period}</Text>
                )}
              </View>
              <Row style={{ alignItems: 'baseline' }}>
                {/* Oswald — lineHeight 24 = 1.26× (BUG A) */}
                <Text style={[s.netNum, nf]}>{p.netWon.toLocaleString()}</Text>
                <Text style={s.netUnit}>원</Text>
              </Row>
            </Row>
          );
        })}

        <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', marginTop: 12, lineHeight: 19 }}>
          {/* 같은 이유: 주기·지급을 약속하지 않는다. 일정은 아직 우리가 못 지킨다.
              원천징수 문장은 합계 줄이 이제 낱말로 지고 있으므로 여기서는 겹쳐 말하지 않는다.
              (Q7 "show once only" — 이 침묵이 그 법을 지키는 자리다. 여기 한 줄 더하면 두 번이 된다.)
              [0192] 「기록된 금액이에요 — 지급 일정은 결제 연동 후 안내드려요」였다. 앞 절은 이제
              위의 「지급 완료」 행들과 **모순된다**(기록만 된 게 아니라 실제로 옮겨진 돈이 있다).
              뒤 절은 여전히 참이라 그대로 두고, 앞 절을 지급이 남는 곳을 가리키는 문장으로 바꾼다.
              일정을 약속하지 않는다는 원래의 법은 그대로다.
              🔴 [less-is-more-19 2026-09-25] 앞 절 「지급 일정은 아직 정해지지 않았어요」도 나간다:
              합계 줄의 sumNote(:280)가 이미 「지급 일정 미정」이라고 말한다. 한 화면이 같은 미정을
              두 번 말하면 두 번째는 정보가 아니라 걱정을 한 번 더 시키는 일이다. 새 사실을 들고
              있는 절 — 지급이 **어디에** 남는지 — 만 남긴다. 일정을 약속하지 않는 법은 그대로다. */}
          지급되면 위 지급 내역에 남아요
        </Text>
      </ScrollView>
      {/* 시스템 바 스트립 — 정산 티켓과 주간 표가 시계 뒤로 지나가던 것 */}
      <StatusBarCover />
      </TabSwipe>
      <BottomNav />
    </View>
  );
}

// [margin secrecy 2026-08-24] Bd() — the per-run breakdown token — is DELETED, not left unused.
// It rendered one ledger column per token (기본 · 거리 · 옵션 · 잔여 보장 · 팁 · 수수료) with the
// coral/green colour coding described in the header. Keeping the helper around would leave the
// rule one JSX line from being undone by a future pass that reads it as dead code to revive.

const s = StyleSheet.create({
  // 섹션 분할 = 풀블리드 솔리드 코랄 1px — 이 선이 곧 브랜드 (§2 종이 법).
  // 반복되는 원장 행 사이는 중립 헤어라인이다: 코랄을 행마다 그으면 구조가 아니라 소음이 된다.
  rule: {
    marginHorizontal: -layout.gutter, height: 1, backgroundColor: paper.line,
    marginTop: 20, marginBottom: 12,
  },
  // ---------- 합계 한 줄 ----------
  sumLabel: { fontSize: 16, lineHeight: 21, fontWeight: '700', color: paper.text },
  sumNum: { fontSize: 19, lineHeight: 24, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] as const },
  sumUnit: { fontSize: 15, lineHeight: 24, fontWeight: '800', color: paper.ink },
  sumUnknown: { fontSize: 19, lineHeight: 24, fontWeight: '900', color: paper.ink },
  sumNote: { fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 6 },
  // [0192] 평생 누계 — 미지급 합계에 주어를 넘겼으므로 한 단계 조용하다. 15pt 디테일 플로어
  // (DESIGN.md §3: 한국어는 kicker 면제를 타지 않는다), Oswald에는 명시 lineHeight (BUG A).
  subLabel: { fontSize: 15, lineHeight: 20, fontWeight: '700', color: paper.dim },
  subNum: { fontSize: 16, lineHeight: 21, fontWeight: '800', color: paper.dim, fontVariant: ['tabular-nums'] as const },
  subUnit: { fontSize: 15, lineHeight: 21, fontWeight: '700', color: paper.dim },
  subUnknown: { fontSize: 16, lineHeight: 21, fontWeight: '800', color: paper.dim },
  // ---------- 원장 행 ----------
  row: { alignItems: 'flex-start', paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: '#EEEEEE' },
  netNum: { fontSize: 19, lineHeight: 24, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] as const },
  netUnit: { fontSize: 15, lineHeight: 24, fontWeight: '800', color: paper.ink },
  // [0192] 행별 지급 상태 한 줄. 색은 두 가지뿐이다 — readyDeep(#0E7F49, 5.06:1)은 「끝났다」,
  // dim은 「아직」. pending 앰버를 쓰지 않는 이유: 이 화면의 대기는 러너가 할 수 있는 일이 없는
  // 대기라서, 주의를 끄는 색은 행동을 요구하는 것처럼 읽힌다.
  payLine: { fontSize: 15, lineHeight: 20, fontWeight: '700', marginTop: 2, textAlign: 'right' },
  emptyBox: { backgroundColor: paper.canvas, paddingVertical: 26, alignItems: 'center' },
  // [0209] 월별 수익의 로딩 스켈레톤 — 숫자를 그리지 않으려고 존재한다. 높이는 그 자리에 올
  // 16.5/22 한 줄과 같아서, 도착했을 때 목록이 튀지 않는다. 중립 헤어라인 색(#EEEEEE)과 같은
  // 계열의 면이라 이 화면에 새 색을 들이지 않는다.
  skel: { height: 14, borderRadius: 2, backgroundColor: '#EEEEEE' },
  // loud-fail strip — community.tsx failStrip grammar (criticalWash + critical, retry ≥40pt)
  failStrip: { backgroundColor: paper.criticalWash, padding: 13 },
  // [액션 시스템 2026-08-11] 잉크 테두리 박스 은퇴. 이 버튼은 criticalWash 라우드-페일 스트립
  // 안에 있는데, 잉크 테두리가 크리티컬 잉크와 싸웠다. 실패 스트립은 박스 버튼이 필요 없다 —
  // runner/run.tsx failAction의 밑줄 텍스트 문법으로 통일 (박스 9개 삭제, 결정 1개).
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },
  // [0194] 정산 계좌 두 문, DESIGN.md:203-206 의 버튼 표 그대로. 「변경」은 이미 목적지가 있는
  // 사람의 조용한 문 = Secondary(canvas 면 + 1px line 보더 + actionInk 라벨 — 첫 초안은 보더를
  // 빠뜨려 wash 만 떠 있었다), 「등록하기」는 아직 받을 곳이 없는 사람의 Primary(ink 면 + 4px 립,
  // radius 0) — 러너가 이 화면에서 할 수 있는 가장 중요한 한 가지다.
  bankChange: { paddingHorizontal: 14, minHeight: 44, justifyContent: 'center', borderRadius: 0, backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line },
  // [ui-consistency-2] 면·립·눌림 산식은 PaperBtn(매트릭스)이 갖는다 — 여기는 자리뿐이다.
  bankRegister: { marginTop: 9 },
  // §3b 섹션 헤더는 앱 전체에서 하나의 문법: 20/800 잉크 (s.rule이 그 위의 코랄 선을 긋는다).
  // 정산 계좌도 이제 같은 헤더다 — 종전 15.5/800 카드 제목은 이 화면만의 크기였다.
  secTitle: { fontSize: 20, lineHeight: 25, fontWeight: '800', color: paper.ink },
});
