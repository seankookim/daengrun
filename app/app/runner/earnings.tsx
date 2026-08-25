import { useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { BottomNav } from '../../src/components/bottomnav';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { TabSwipe } from '../../src/components/tabswipe';
import { Row } from '../../src/components/ui';
import { fetchLedger, fetchLedgerTotal, LiveLedgerItem } from '../../src/lib/api';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
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
  const load = () => {
    setLoadErr(false);
    return Promise.all([
      fetchLedger().then(setLedger),
      fetchLedgerTotal().then(setTotal),
    ]).then(() => setLoaded(true))
      .catch((e) => {
        console.warn('[earnings] ledger:', e?.message ?? e);
        setLoaded(false);
        setTotal(null);
        setLedger([]);
        setLoadErr(true);
      });
  };
  useFocusEffect(useCallback(() => { load(); }, []));
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  // 정산 예정 = 원장 전체 누적 (30행 캡 합계가 31번째 러닝부터 오히려 줄어들던 버그 — 로드 전엔 표시 리스트 합으로 폴백)
  // [honesty 2026-08-11] sumKnown 전에는 '—' — 로딩/실패를 0원으로 위장하지 않는다.
  const sumKnown = loaded || total != null;
  const pendingSum = total ?? ledger.reduce((sum, l) => sum + l.net, 0);

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <TabSwipe>
      <ScrollView
        style={{ flex: 1 }}
        contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: 60, paddingBottom: 30 }}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
      >
        {/* [§3c 화면 타이틀 2026-08-11] 30/900 · lineHeight 37 (1.23× — BUG A) */}
        <Text style={[{ fontSize: 30, lineHeight: 37, fontWeight: '900', color: paper.ink }, df]}>수익</Text>

        {/* 합계 — 한 줄. sumKnown 게이트는 그대로: 로딩·실패를 0원으로 위장하지 않는다 ('—'). */}
        <View style={[s.rule, { marginTop: 14 }]} />
        <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
          <Text style={s.sumLabel}>정산 예정 · 원장 합계</Text>
          {sumKnown ? (
            <Row style={{ alignItems: 'baseline' }}>
              {/* Oswald sum — lineHeight 24 = 1.26× (BUG A) */}
              <Text style={[s.sumNum, nf]}>{pendingSum.toLocaleString()}</Text>
              <Text style={s.sumUnit}>원</Text>
            </Row>
          ) : (
            <Text style={s.sumUnknown}>—</Text>
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

        {/* bank account — honest info row, not a door: registration ships with open banking */}
        <View style={s.rule} />
        <Text style={s.secTitle}>정산 계좌</Text>
        <Text style={{ fontSize: 14, color: paper.dim, marginTop: 3, lineHeight: 19 }}>
          아직 등록된 계좌가 없어요 — 계좌 등록은 오픈뱅킹 연동과 함께 제공돼요
        </Text>

        {/* ledger — §3b section header: full-bleed coral rule + 20/800 ink */}
        <View style={s.rule} />
        <Text style={[s.secTitle, { marginBottom: 10 }]}>러닝별 내역</Text>
        {!loaded && !loadErr && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center' }}>불러오는 중...</Text>
          </View>
        )}
        {/* loud-fail strip — criticalWash bg + critical ink + retry (never a fake empty) */}
        {loadErr && (
          <View style={s.failStrip}>
            <Text style={{ fontSize: 14, fontWeight: '700', color: paper.critical }}>정산 내역을 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
              <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {loaded && !loadErr && ledger.length === 0 && (
          <View style={s.emptyBox}>
            <Text style={{ fontSize: 14.5, color: paper.dim, textAlign: 'center', lineHeight: 22 }}>
              아직 정산 내역이 없어요{'\n'}러닝을 완료하면 여기에 기록돼요
            </Text>
          </View>
        )}
        {/* 러닝 하나 = 한 줄. 왼쪽은 어떤 러닝이었는지, 오른쪽은 실수령 하나.
            '실수령' 낱말은 지킨다 — 랩의 '적립'과 달리 이 숫자가 **무엇인지** 말한다. 산수는 말하지
            않는다 (2026-08-24 마진 비밀 규칙: 최종 금액 하나만). */}
        {ledger.map((l) => (
          <Row key={l.id} style={s.row}>
            <View style={{ flex: 1, paddingRight: 12 }}>
              <Row style={{ gap: 6, alignItems: 'baseline', flexWrap: 'wrap' }}>
                {/* ⚠ Three cases, because a ledger row does not imply a run happened.
                    `record_enroute_cancel_comp` (0080) and `record_late_cancel_share` (0085) write
                    `ledger_items` for a CANCELLATION — no `runs` row exists — and this line used to
                    read the km straight off the booking, so an en-route cancel rendered
                    「초코 · 5km · 실수령 12,450원」: the runner's own ledger claiming they ran 5km.
                    `fetchLedger` now resolves km from `runs` and hands back null when there is none;
                    `cancelComp` distinguishes "cancellation compensation" from "the lookup failed",
                    and an unknown must not be labelled a cancellation. */}
                <Text style={{ fontSize: 16.5, lineHeight: 22, fontWeight: '800', color: paper.ink }}>
                  {l.km != null ? `${l.dogName} · ${l.km}km` : l.cancelComp ? `${l.dogName} · 취소 보상` : l.dogName}
                </Text>
                <Text style={{ fontSize: 14, lineHeight: 19, color: paper.dim }}>{l.when}</Text>
              </Row>
            </View>
            <View style={{ alignItems: 'flex-end' }}>
              <Row style={{ alignItems: 'baseline' }}>
                {/* Oswald net — lineHeight 24 = 1.26× (BUG A) */}
                <Text style={[s.netNum, nf]}>{l.net.toLocaleString()}</Text>
                <Text style={s.netUnit}>원</Text>
              </Row>
              <Text style={{ fontSize: 14, lineHeight: 19, color: paper.dim }}>실수령</Text>
            </View>
          </Row>
        ))}

        <Text style={{ fontSize: 14, color: paper.dim, textAlign: 'center', marginTop: 12, lineHeight: 19 }}>
          {/* 같은 이유: 주기·지급을 약속하지 않는다. 일정은 아직 우리가 못 지킨다.
              원천징수 문장은 합계 줄이 이제 낱말로 지고 있으므로 여기서는 겹쳐 말하지 않는다.
              (Q7 "show once only" — 이 침묵이 그 법을 지키는 자리다. 여기 한 줄 더하면 두 번이 된다.) */}
          기록된 금액이에요 — 지급 일정은 결제 연동 후 안내드려요
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
  sumNote: { fontSize: 14, lineHeight: 19, color: paper.dim, marginTop: 6 },
  // ---------- 원장 행 ----------
  row: { alignItems: 'flex-start', paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: '#EEEEEE' },
  netNum: { fontSize: 19, lineHeight: 24, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] as const },
  netUnit: { fontSize: 15, lineHeight: 24, fontWeight: '800', color: paper.ink },
  emptyBox: { backgroundColor: paper.canvas, paddingVertical: 26, alignItems: 'center' },
  // loud-fail strip — community.tsx failStrip grammar (criticalWash + critical, retry ≥40pt)
  failStrip: { backgroundColor: paper.criticalWash, padding: 13 },
  // [액션 시스템 2026-08-11] 잉크 테두리 박스 은퇴. 이 버튼은 criticalWash 라우드-페일 스트립
  // 안에 있는데, 잉크 테두리가 크리티컬 잉크와 싸웠다. 실패 스트립은 박스 버튼이 필요 없다 —
  // runner/run.tsx failAction의 밑줄 텍스트 문법으로 통일 (박스 9개 삭제, 결정 1개).
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },
  // §3b 섹션 헤더는 앱 전체에서 하나의 문법: 20/800 잉크 (s.rule이 그 위의 코랄 선을 긋는다).
  // 정산 계좌도 이제 같은 헤더다 — 종전 15.5/800 카드 제목은 이 화면만의 크기였다.
  secTitle: { fontSize: 20, lineHeight: 25, fontWeight: '800', color: paper.ink },
});
