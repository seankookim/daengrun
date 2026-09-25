import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Alert, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Row, ScreenHead } from '../../src/components/ui';
import { claimGear, DropRow, fetchDrops, fetchGearClaims, fetchMiles, fetchMyRunnerStatus, GearClaim, MilesInfo, MyRunnerStatus, openDrop } from '../../src/lib/api';
import { claimCarrierLine, claimStatusLabel } from '../../src/lib/claim-status';
import { EMPTY_GEAR_CLAIM_FORM, GEAR_CLAIM_PROBLEM_TEXT, gearClaimProblem, GearClaimForm } from '../../src/lib/gear-claim-form';
import { useNumFont } from '../../src/lib/fonts';
import { haptic } from '../../src/lib/haptics';
// RAW server text for the log; `e.message` on a claim failure is the mapped Korean
// (api.ts `gearClaimError` -> `foldRpcError`) that `claimErr` renders.
import { foldRpcError, rpcRaw } from '../../src/lib/rpc-error';
import { colors, layout, paper, secTitle } from '../../src/theme';

// 리워드 센터 — 실화: 하이 포인트 잔액·드랍 오픈(open-drop)·기어 교환권. 목업 사다리 은퇴.
// 5회 보급 드랍(랜덤·바닥 보장) · 10회 픽 드랍(3택1 — 선택 데이터 = 러너 동기 시그널)
//
// [paper repaint 2026-08-11] forest/cream chrome scrapped → paper. Kept as artifacts:
// the points balance face and the unopened-drop cards stay DARK (paper.ink + volt edge —
// a drop is a ceremony object) with volt open/pick buttons (personal reward semantics).
// §3b: sections = coral rule + 20/800 (count folds into the title line), history cards
// lose the 0.75 opacity (explicit dim ink instead), Korean captions lose latin tracking.
// Ladder/cycle logic untouched. Behavior frozen: load fan-out, openDrop(pick), routes.
//
// [enh lab B① + B③ · Sean 2026-08-24, verbatim: "I like b1 but also show them what's next."]
//   B① 포인트 내역 — `fetchMiles()` already returns `recent[]` (10 real `miles_ledger` rows) on
//     every focus and this screen threw them away, while shop.tsx drew 2 of them and
//     leaderboard.tsx 3. The rewards centre, whose subject IS points, now draws its own ledger.
//     The earning-rules blurb is not deleted: it becomes the fallback when there is no history,
//     so a runner on day one still learns how points are earned. Sign comes from `delta`, never
//     from a '+' literal — `shop_spend` rows are negative (the leaderboard.tsx:76 point).
//   B③ what's next — the empty state did arithmetic and got the NOUN wrong: `5 - totalRuns % 5`
//     counts to the next multiple of five, but `settle_run_tx` (0083 §6:812-816) mints a 픽 drop
//     when the new total is a multiple of TEN and a mini only otherwise. At 17 완주 the screen
//     said 보급 and the server would mint 픽. Same arithmetic, one more test. Both the count and
//     the noun still render ONLY when `rs !== null` — a failed status fetch prints neither.
//     `runners.total_runs` increments on 완주 only (0083:796, `v_is_full`), which is the same gate
//     that mints the drop, so the two cannot drift.
// Neither variant adds a fetch, a column, a route, or a colour. No money is displayed on this
// screen at all — points are not currency and the 2026-08-24 margin rule does not reach here.

export default function Rewards() {
  const insets = useSafeAreaInsets();
  const nf = useNumFont();     // Oswald — points balance
  const [miles, setMiles] = useState<MilesInfo | null>(null);
  const [drops, setDrops] = useState<DropRow[]>([]);
  const [claims, setClaims] = useState<GearClaim[]>([]);
  const [rs, setRs] = useState<MyRunnerStatus | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [refreshing, setRefreshing] = useState(false);

  // [honesty 2026-08-11] drops 실패가 "대기 중인 드랍이 없어요 + N번 더 완주"라는
  // 지어낸 빈 상태로 굳던 것 — 3상태 분리.
  const [dropsLoaded, setDropsLoaded] = useState(false);
  const [dropsErr, setDropsErr] = useState(false);
  // [honesty 2026-09-17 · loading-state-audit #19] The line above used to end 「miles/claims/rs는
  // 이미 null→'—'/생략 처리라 soft 유지」. '—' and 생략 are honest about the VALUE and say nothing
  // about the READ: a person looking at '—' cannot tell a slow network from a dead call, and an
  // absent 교환권 section says 「you own none」 in exactly the voice a failure borrowed. Each of the
  // three now owns a flag and gets the treatment `drops` has had since 2026-08-11.
  // ⚠ Setters only run on success, so a failed refresh keeps every last-known row on screen —
  // the strip says the READ failed, never that the value is 0.
  const [milesErr, setMilesErr] = useState(false);
  const [claimsErr, setClaimsErr] = useState(false);
  const [rsErr, setRsErr] = useState(false);
  // [0195] 굿즈 수령 — which claim's form is open, what is in it, whether it is in flight, and the
  // server's own refusal. `claimErr` holds the MAPPED Korean message (api.ts `gearClaimError`)
  // and is rendered, never swallowed.
  const [claimOpen, setClaimOpen] = useState<string | null>(null);
  const [form, setForm] = useState<GearClaimForm>(EMPTY_GEAR_CLAIM_FORM);
  const [claimBusy, setClaimBusy] = useState<string | null>(null);
  const [claimErr, setClaimErr] = useState<string | null>(null);
  const load = () => {
    setDropsErr(false); setMilesErr(false); setClaimsErr(false); setRsErr(false);
    return Promise.all([
      fetchMiles().then(setMiles)
        .catch((e) => { console.warn('[rewards] miles:', e?.message ?? e); setMilesErr(true); }),
      fetchDrops()
        .then((d) => { setDrops(d); setDropsLoaded(true); })
        .catch((e) => { console.warn('[rewards] drops:', e?.message ?? e); setDropsErr(true); }),
      fetchGearClaims().then(setClaims)
        .catch((e) => { console.warn('[rewards] claims:', rpcRaw(e)); setClaimsErr(true); }),
      fetchMyRunnerStatus().then(setRs)
        .catch((e) => { console.warn('[rewards] status:', e?.message ?? e); setRsErr(true); }),
    ]);
  };
  useFocusEffect(useCallback(() => { load(); }, []));
  const onRefresh = () => { setRefreshing(true); load().finally(() => setRefreshing(false)); };

  const open = async (d: DropRow, pick?: string) => {
    setBusy(d.id);
    try {
      const applied = await openDrop(d.id, pick);
      haptic('success');
      const parts: string[] = [];
      if (applied.miles) parts.push(`+${(applied.miles as number).toLocaleString()} 하이 포인트`);
      if (applied.card) parts.push(`카드 「${applied.card}」`);
      if (applied.gear) parts.push(`기어: ${applied.gear}`);
      if (applied.boost_until) parts.push('부스트 24시간 활성');
      Alert.alert('드랍 오픈!', parts.join('\n') || '보상이 적용됐어요');
      load();
    } catch (e) {
      // ⚠ SCOPE NOTE — this one is NOT one of tonight's RPC wrappers; it is the `open-drop` EDGE
      // function, and it was already capable of putting a non-Korean word in this alert. Its
      // mapped refusals are Korean (`RPC_TOKEN_MAP`: 「이미 열린 드랍이에요」 …) and pass through
      // `foldRpcError` untouched, but its UNMAPPED path throws `HttpError(500, 'internal')`
      // (`_shared/ctx.ts:112`), so the alert body read the literal English word `internal`.
      // ⚠ [2026-09-23] THE FOLD MOVED INTO `openDrop` and this note is corrected rather than
      // deleted, because the reasoning it records is still the trade that was made. It said
      // 「folding here keeps the FnError (with its code/detail) intact for any future caller」 —
      // true, and the cost was that `bad_body` / `missing drop_id` / `unauthorized` (the
      // ENVELOPE, which no `RPC_TOKEN_MAP` covers) reached a Korean alert in English on any
      // path that did NOT go through this screen. There is no other path today, so the wrapper
      // now folds and this call is a PASSTHROUGH: a Hangul message comes back unchanged, same
      // object, and `empty` is byte-identical on both sides (src/lib/edge-errors.ts).
      // What is genuinely given up: `isFnError(e)` is false here now, and nothing reads it.
      console.warn('[rewards] open:', rpcRaw(e));
      Alert.alert('오픈 실패', foldRpcError(e, { empty: '드랍을 열지 못했어요' }).message);
    } finally {
      setBusy(null);
    }
  };

  // ── [0195] 굿즈 수령 ────────────────────────────────────────────────────────────────────────
  // One form at a time, keyed by claim id: two open forms would share `form` state and a runner
  // could submit hoodie A's address against cap B without anything looking wrong.
  const openClaimForm = (id: string) => {
    setClaimOpen(id);
    setForm(EMPTY_GEAR_CLAIM_FORM);
    setClaimErr(null);
  };
  const closeClaimForm = () => { setClaimOpen(null); setClaimErr(null); };

  const submitClaim = async (id: string) => {
    // The client check is a COURTESY and says so in gear-claim-form.ts — it points at the topmost
    // unfillable field instead of making a person wait for a round trip to learn a postal code is
    // five digits. The SERVER is still the authority and its refusal is rendered below verbatim.
    const problem = gearClaimProblem(form);
    if (problem !== null) { setClaimErr(GEAR_CLAIM_PROBLEM_TEXT[problem]); return; }
    setClaimBusy(id);
    setClaimErr(null);
    try {
      const res = await claimGear(id, form);
      // 🔴 The row re-renders from the SERVER's answer, never from an optimistic flip. `res.status`
      // is read back out of the written row (0195 §B ⑧), so what the chip says after this is what
      // the table holds — and `alreadyClaimed` is a SUCCESS, not a failure: a dropped response on
      // a first tap looks exactly like a second tap, and telling that person their claim failed
      // would be a lie about a claim that landed.
      setClaims((prev) => prev.map((c) => (
        c.id === res.claimId
          ? { ...c, status: res.status, carrier: res.carrier, tracking: res.tracking }
          : c
      )));
      haptic('success');
      setClaimOpen(null);
      Alert.alert(
        res.alreadyClaimed ? '이미 신청된 교환권이에요' : '수령 신청 완료',
        res.alreadyClaimed
          ? '먼저 접수된 배송지로 보내드릴게요.'
          : '배송 준비가 시작되면 상태가 바뀌어요.',
      );
      // Re-read rather than trust the patch above to be the whole truth: another surface may have
      // moved this row, and the list is cheap.
      load();
    } catch (e) {
      setClaimErr((e as Error).message);
    } finally {
      setClaimBusy(null);
    }
  };

  const unopened = drops.filter((d) => !d.openedAt);
  const opened = drops.filter((d) => d.openedAt);
  const cycle5 = (rs?.totalRuns ?? 0) % 5;
  // [B③] 다음 드랍까지 남은 완주 수와 **그 드랍의 이름**. 서버(0083 §6:812-816)는 픽을 먼저 본다:
  // 새 누적이 10의 배수면 픽, 아니면(5의 배수면) 보급. 같은 순서로 판정한다 — 이름을 지어내지 않고
  // 서버가 실제로 만들 상자를 말한다. rs가 null이면 이 두 값은 화면에 나가지 않는다 (아래 게이트).
  const nextInRuns = 5 - cycle5;
  const nextIsPick = ((rs?.totalRuns ?? 0) + nextInRuns) % 10 === 0;
  // [B①] 포인트 내역 — fetchMiles가 이미 실어온 miles_ledger 10행. 비었으면(또는 못 불러왔으면)
  // 적립 규칙 한 줄이 그 자리를 지킨다: 0행짜리 내역을 그리는 것보다 규칙을 말하는 편이 정직하다.
  const recent = miles?.recent ?? [];

  return (
    <ScrollView
      style={{ flex: 1, backgroundColor: paper.canvas }}
      contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: insets.top, paddingBottom: 40 }}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} />}
    >
      {/* Chrome header (DESIGN.md §3b). The title no longer borrows the display face: a pushed
          sub-screen's header is the shared 23/900 chrome title on every screen. */}
      <ScreenHead title="리워드 센터" />

      {/* 하이 포인트 — dark balance face (artifact), volt numeral = personal reward */}
      <View style={s.milesCard}>
        <Text style={{ fontSize: 15, lineHeight: 18, color: '#BBBBBB' }}>내 하이 포인트</Text>
        {/* Oswald balance — lineHeight 49 = 1.26× (BUG A) */}
        <Text style={[{ fontSize: 39, lineHeight: 49, fontWeight: '900', color: colors.volt, marginTop: 4, fontVariant: ['tabular-nums'] as const }, nf]}>
          {miles?.balance?.toLocaleString() ?? '—'}<Text style={{ fontSize: 15, color: '#BBBBBB' }}> 포인트</Text>
        </Text>
        {/* [B①] 잔액 아래는 그 잔액이 어떻게 만들어졌는지 — miles_ledger 실행들.
            부호는 delta가 진다: shop_spend는 음수이고, '+'를 붙여 그리면 쓴 돈이 번 돈이 된다.
            [honesty #19] 네 얼굴이지 하나가 아니다. 적립 규칙 줄은 **정착된** 얼굴이다 —
            「응답이 왔고 최근 내역이 없다」는 뜻이라, 실패와 대기는 그 줄을 그리면 안 된다.
            위 잔액의 '—'도 같은 이유로 남는다: 잔액을 모를 때 0을 그리면 거짓말이다.
            어두운 면 위 잉크는 이 카드의 어휘(tang · volt)를 쓴다 — paper.critical이 아니다.
            ⚠ 실패 스트립은 내역을 **대체하지 않고 그 위에 선다**. 직전에 받아둔 내역은 여전히
            참이고(세터는 성공에서만 돈다), 재조회가 실패했다고 화면에서 지워 버리면 실패가
            데이터를 먹는다. 아래 「최근 10건까지 보여요」 캡션이 내역과 같은 게이트를 쓰는 이유도
            이것이다 — 스트립이 내역을 가리면 그 캡션만 홀로 남는다. */}
        {milesErr && (
          <View style={s.milesLedger}>
            <Text style={{ fontSize: 15, lineHeight: 19, fontWeight: '800', color: colors.tang }}>하이 포인트를 불러오지 못했어요</Text>
            <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button" accessibilityLabel="하이 포인트 다시 불러오기">
              <Text style={{ fontSize: 16, fontWeight: '800', color: colors.volt, textDecorationLine: 'underline' }}>다시 시도</Text>
            </Pressable>
          </View>
        )}
        {milesErr && recent.length === 0 ? null : miles == null ? (
          <Text style={{ fontSize: 15, lineHeight: 19, color: '#BBBBBB', marginTop: 6 }}>불러오는 중…</Text>
        ) : recent.length > 0 ? (
          <View style={s.milesLedger}>
            {recent.map((m, i) => (
              <Row key={`${m.when}-${m.reason}-${i}`} style={s.mileRow}>
                <Text style={{ fontSize: 15, lineHeight: 20, color: '#BBBBBB', flex: 1 }} numberOfLines={1}>
                  {m.reason} · {m.when}
                </Text>
                {/* Oswald delta — lineHeight 20 = 1.33× (BUG A).
                    ⚠ 마이너스는 coralText(#d84a2f)가 아니라 tang(#FF5C3D)이다. coralText는 **흰
                    면 위의** 읽는 코랄이고, 이 카드는 잉크 면이다 — 역할이 뒤집힌다. 실측: #d84a2f
                    on #111111 = 4.48:1 (15pt 볼드는 큰 활자가 아니라 4.5 미달), tang = 6.24:1.
                    같은 이유로 플러스는 volt다 (14.99:1) — 이 화면의 개인 보상 색. 신규 색 0개. */}
                <Text style={[{ fontSize: 15, lineHeight: 20, fontWeight: '800', marginLeft: 10, color: m.delta < 0 ? colors.tang : colors.volt, fontVariant: ['tabular-nums'] as const }, nf]}>
                  {m.delta < 0 ? '−' : '+'}{Math.abs(m.delta).toLocaleString()}
                </Text>
              </Row>
            ))}
          </View>
        ) : (
          <Text style={{ fontSize: 15, lineHeight: 19, color: '#BBBBBB', marginTop: 6 }}>
            완주 +50 · 응가 도장 +30 · 드랍 보상 · 주간 TOP3 보너스
          </Text>
        )}
      </View>
      {recent.length > 0 && (
        <Text style={{ fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 8 }}>최근 10건까지 보여요</Text>
      )}

      {/* 미오픈 드랍 — §3b section header */}
      <Row style={s.secWrap}>
        <Text style={secTitle}>도착한 드랍{unopened.length > 0 ? ` · ${unopened.length}` : ''}</Text>
      </Row>
      {!dropsLoaded && !dropsErr && (
        <View style={s.emptyBox}>
          <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center' }}>불러오는 중…</Text>
        </View>
      )}
      {/* loud-fail strip — criticalWash bg + critical ink + retry (never a fake empty) */}
      {dropsErr && (
        <View style={s.failStrip}>
          <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>드랍을 불러오지 못했어요</Text>
          <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button">
            <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
          </Pressable>
        </View>
      )}
      {dropsLoaded && !dropsErr && unopened.length === 0 && (
        <View style={s.emptyBox}>
          <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', lineHeight: 22 }}>
            대기 중인 드랍이 없어요
            {/* run count claim only when the runner status actually arrived — no fabricated "5번 더".
                [B③] 상자의 이름도 같은 게이트 안에 있다: 10의 배수면 픽, 아니면 보급 (0083 §6). */}
            {rs != null ? `\n${nextInRuns}번 더 완주하면 ` : ''}
            {rs != null && (
              <Text style={{ fontWeight: '800', color: paper.ink }}>{nextIsPick ? '픽 드랍' : '보급 드랍'}</Text>
            )}
            {rs != null ? '이 도착해요' : ''}
          </Text>
          {/* 픽 드랍일 때만 한 줄 더 — 고를 수 있다는 사실이 픽의 전부다.
              세 선택지는 drops.contents.options 그대로 (0083 §6:814 minted ["boost","miles","gear"]). */}
          {rs != null && nextIsPick && (
            <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', lineHeight: 20, marginTop: 6 }}>
              픽 드랍은 부스트 · 5,000 포인트 · 기어 중 하나를 직접 골라요
            </Text>
          )}
          {/* [honesty #19] rs 실패 — 위 게이트(rs != null)는 숫자를 지어내지 않는 데까지만 정직했고,
              「다음 드랍 안내가 원래 없는 화면」과 구분되지 않았다. 못 읽었다고 말하고 문을 연다. */}
          {rsErr && (
            <>
              <Text style={{ fontSize: 15, color: paper.critical, textAlign: 'center', lineHeight: 20, marginTop: 6 }}>
                다음 드랍까지 남은 완주 수를 불러오지 못했어요
              </Text>
              <Pressable onPress={load} style={[s.retryBtn, { alignSelf: 'center' }]} accessibilityRole="button" accessibilityLabel="완주 기록 다시 불러오기">
                <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
              </Pressable>
            </>
          )}
        </View>
      )}
      {unopened.map((d) => (
        <View key={d.id} style={s.dropCard}>
          <Row style={{ justifyContent: 'space-between' }}>
            <Text style={{ fontSize: 17, fontWeight: '800', color: colors.volt }}>
              {d.kind === 'pick' ? '픽 드랍' : '보급 드랍'} · {d.runCountAt}회 달성
            </Text>
            <Text style={{ fontSize: 15, color: '#BBBBBB' }}>{d.when}</Text>
          </Row>
          {d.kind === 'pick' ? (
            <>
              {/* busy = hint-line label swap (the tapped choice is the card's action) */}
              <Text style={{ fontSize: 15, lineHeight: 19, color: '#BBBBBB', marginTop: 8 }}>
                {busy === d.id ? '적용 중…' : '셋 중 하나를 선택하세요 — 되돌릴 수 없어요'}
              </Text>
              <Row style={{ gap: 8, marginTop: 10 }}>
                {([['boost', '부스트'], ['miles', '5,000포인트'], ['gear', '기어']] as const).map(([k, label]) => (
                  <Pressable
                    key={k}
                    disabled={busy !== null}
                    onPress={() => open(d, k)}
                    style={({ pressed }) => [s.pickBtn, pressed && { backgroundColor: colors.voltDeep, transform: [{ scale: 0.96 }] }]}
                  >
                    <Text style={{ fontSize: 15, fontWeight: '800', color: '#111111' }}>{label}</Text>
                  </Pressable>
                ))}
              </Row>
            </>
          ) : (
            <Pressable
              disabled={busy !== null}
              onPress={() => open(d)}
              style={({ pressed }) => [s.openBtn, pressed && { backgroundColor: colors.voltDeep, transform: [{ scale: 0.96 }] }]}
            >
              <Text style={{ fontSize: 16, fontWeight: '800', color: '#111111' }}>{busy === d.id ? '여는 중…' : '상자 열기'}</Text>
            </Pressable>
          )}
        </View>
      ))}

      {/* 기어 교환권
          [honesty #19] 섹션이 통째로 사라지면 「가진 교환권이 없다」로 읽힌다 — 실패면 제목까지
          세워야 그 자리가 원래 무엇이었는지 알 수 있다. 제목은 두 경우가 **하나로** 쓴다:
          갱신이 실패했는데 직전 목록이 남아 있으면 제목이 두 번 서기 때문이다. 스트립은 목록을
          대체하지 않고 그 위에 선다 — 직전에 받아둔 교환권은 여전히 참이다. */}
      {(claimsErr || claims.length > 0) && (
        <>
          <Row style={s.secWrap}>
            <Text style={secTitle}>기어 교환권</Text>
          </Row>
          {claimsErr && (
            <View style={s.failStrip}>
              <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>교환권을 불러오지 못했어요</Text>
              <Pressable onPress={load} style={s.retryBtn} accessibilityRole="button" accessibilityLabel="기어 교환권 다시 불러오기">
                <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>다시 시도</Text>
              </Pressable>
            </View>
          )}
          {claims.length > 0 && (
          <View style={s.card}>
            {claims.map((g, i) => (
              <View key={g.id}>
                {i > 0 && <View style={s.div} />}
                <Row style={{ paddingVertical: 10, justifyContent: 'space-between' }}>
                  <View>
                    <Text style={{ fontSize: 15.5, fontWeight: '800', color: paper.ink }}>{g.item}</Text>
                    <Text style={{ fontSize: 15, color: paper.dim, marginTop: 2 }}>{g.milestone}회 달성 보상</Text>
                  </View>
                  {/* [0195] The chip was a `View` — a word with no route and no effect, which is
                      exactly what the no-dead-buttons law forbids once a door exists. On a
                      `claimable` row it is now the button that opens the form; on every other
                      row it stays the label it always was, because there is nothing to press. */}
                  {g.status === 'claimable' ? (
                    <Pressable
                      onPress={() => openClaimForm(g.id)}
                      style={s.claimBtn}
                      accessibilityRole="button"
                      accessibilityLabel={`${g.item} 수령 신청`}
                    >
                      <Text style={{ fontSize: 16, fontWeight: '900', color: '#2F5417' }}>수령 신청</Text>
                    </Pressable>
                  ) : (
                    <View style={[s.claimChip, { backgroundColor: '#F5F5F5' }]}>
                      <Text style={{ fontSize: 15, fontWeight: '800', color: paper.dim }}>
                        {/* claim_status is a closed pg enum of four (0001_init.sql:21) and this
                            line covered ONE of them — locked/claimed/shipped printed the raw
                            English token on a Korean screen. Single source now:
                            src/lib/claim-status.ts, shared with shop.tsx. */}
                        {claimStatusLabel(g.status)}
                      </Text>
                    </View>
                  )}
                </Row>
                {/* The carrier line renders ONLY when ops stamped both halves — an absent
                    shipment draws nothing rather than a sentence about its absence. */}
                {claimCarrierLine(g.carrier, g.tracking) !== null && (
                  <Text style={{ fontSize: 15, color: paper.dim, marginTop: -4, marginBottom: 8 }}>
                    {claimCarrierLine(g.carrier, g.tracking)}
                  </Text>
                )}

                {/* ── the form, inline under its own row ───────────────────────────────── */}
                {claimOpen === g.id && (
                  <View style={s.claimForm}>
                    <Text style={{ fontSize: 15, fontWeight: '800', color: paper.ink, marginBottom: 2 }}>
                      배송지를 알려주세요
                    </Text>
                    <Text style={{ fontSize: 15, color: paper.dim, marginBottom: 4 }}>
                      신청 후에는 주소를 바꿀 수 없어요 — 한 번만 확인해 주세요
                    </Text>
                    <TextInput
                      value={form.recipient}
                      onChangeText={(t) => setForm({ ...form, recipient: t })}
                      placeholder="받는 분 이름" placeholderTextColor="#b0ada0" style={s.input}
                      maxLength={20} textContentType="name" autoComplete="name" autoCorrect={false}
                      editable={claimBusy !== g.id}
                    />
                    <TextInput
                      value={form.phone}
                      onChangeText={(t) => setForm({ ...form, phone: t })}
                      placeholder="연락처" placeholderTextColor="#b0ada0" style={s.input}
                      keyboardType="phone-pad" maxLength={15}
                      textContentType="telephoneNumber" autoComplete="tel"
                      editable={claimBusy !== g.id}
                    />
                    <TextInput
                      value={form.address1}
                      onChangeText={(t) => setForm({ ...form, address1: t })}
                      placeholder="주소" placeholderTextColor="#b0ada0" style={s.input}
                      maxLength={80} textContentType="fullStreetAddress" autoComplete="street-address"
                      editable={claimBusy !== g.id}
                    />
                    <TextInput
                      value={form.address2}
                      onChangeText={(t) => setForm({ ...form, address2: t })}
                      placeholder="상세 주소 (선택)" placeholderTextColor="#b0ada0" style={s.input}
                      maxLength={60} textContentType="streetAddressLine2" autoComplete="postal-address-extended"
                      editable={claimBusy !== g.id}
                    />
                    <TextInput
                      value={form.postal}
                      onChangeText={(t) => setForm({ ...form, postal: t })}
                      placeholder="우편번호 (5자리)" placeholderTextColor="#b0ada0" style={s.input}
                      keyboardType="number-pad" maxLength={5}
                      textContentType="postalCode" autoComplete="postal-code"
                      editable={claimBusy !== g.id}
                    />

                    {/* The server's own refusal word, mapped to Korean. It is shown INSTEAD of
                        being swallowed, and the retry is a real second attempt — the honesty
                        law's 「failures are shown as failures」. */}
                    {claimErr !== null && (
                      <View style={s.failStrip}>
                        <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical }}>{claimErr}</Text>
                        <Pressable
                          onPress={() => submitClaim(g.id)}
                          style={s.retryBtn}
                          accessibilityRole="button"
                          accessibilityLabel="수령 신청 다시 시도"
                        >
                          <Text style={{ fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' }}>
                            다시 시도
                          </Text>
                        </Pressable>
                      </View>
                    )}

                    <Row style={{ gap: 8, marginTop: 4 }}>
                      {/* busy = LABEL SWAP, never a spinner replacing the label (button matrix) */}
                      <Pressable
                        onPress={() => submitClaim(g.id)}
                        disabled={claimBusy === g.id}
                        style={[s.claimSubmit, claimBusy === g.id && { opacity: 0.6 }]}
                        accessibilityRole="button"
                        accessibilityState={{ disabled: claimBusy === g.id, busy: claimBusy === g.id }}
                        accessibilityLabel="신청하기"
                      >
                        <Text style={{ fontSize: 17, fontWeight: '900', color: paper.ink }}>
                          {claimBusy === g.id ? '신청 중…' : '신청하기'}
                        </Text>
                      </Pressable>
                      <Pressable
                        onPress={closeClaimForm}
                        disabled={claimBusy === g.id}
                        style={s.claimCancel}
                        accessibilityRole="button"
                        accessibilityLabel="수령 신청 취소"
                      >
                        <Text style={{ fontSize: 16, fontWeight: '700', color: paper.dim }}>취소</Text>
                      </Pressable>
                    </Row>
                  </View>
                )}
              </View>
            ))}
          </View>
          )}
        </>
      )}

      {/* 오픈 히스토리 — muted with explicit dim ink (opacity paint retired) */}
      {opened.length > 0 && (
        <>
          <Row style={s.secWrap}>
            <Text style={secTitle}>지난 드랍</Text>
          </Row>
          {opened.map((d) => (
            <View key={d.id} style={[s.card, { marginBottom: 8 }]}>
              <Row style={{ justifyContent: 'space-between' }}>
                <Text style={{ fontSize: 15, fontWeight: '700', color: paper.dim }}>
                  {/* 포인트가 실제로 들어 있을 때만 괄호를 연다 — '+0포인트'는 없는 적립을 그리는 것 */}
                  {d.kind === 'pick'
                    ? `픽 드랍 — ${d.pickChoice === 'miles' ? '5,000포인트' : d.pickChoice === 'boost' ? '부스트' : '기어'} 선택`
                    : typeof d.contents.miles === 'number' && d.contents.miles > 0
                      ? `보급 드랍 (+${d.contents.miles.toLocaleString()}포인트)`
                      : '보급 드랍'}
                </Text>
                <Text style={{ fontSize: 15, color: paper.dim }}>{d.when}</Text>
              </Row>
            </View>
          ))}
        </>
      )}

      <Pressable onPress={() => router.push('/leaderboard')} style={s.rankLink}>
        <Text style={{ fontSize: 15, fontWeight: '800', color: colors.coralText }}>주간 랭킹에서 보너스 노려보기 ›</Text>
      </Pressable>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  milesCard: { backgroundColor: paper.ink, padding: 18, marginTop: 16 },
  // [B①] 잔액과 그 내역을 가르는 선 — 다크 면 위의 헤어라인. paper.text(#333333)를 면 색으로 쓴다:
  // 이 카드에서 유일하게 '잉크보다 한 단 밝은' 값이고, 새 헥스를 만들지 않는다.
  milesLedger: { marginTop: 10, borderTopWidth: 1, borderTopColor: paper.text, paddingTop: 6 },
  mileRow: { justifyContent: 'space-between', alignItems: 'baseline', paddingVertical: 5 },
  // §3b section header — full-bleed coral rule via negative gutter margins, then theme.secTitle
  secWrap: {
    marginHorizontal: -layout.gutter, paddingHorizontal: layout.gutter,
    borderTopWidth: 1, borderTopColor: paper.line, paddingTop: 10, marginTop: 20, marginBottom: 8,
  },
  emptyBox: { backgroundColor: paper.canvas, borderWidth: 1, borderColor: '#EEEEEE', padding: 20 },
  // loud-fail strip — community.tsx failStrip grammar (criticalWash + critical, retry ≥40pt)
  failStrip: { backgroundColor: paper.criticalWash, padding: 13 },
  // [액션 시스템 2026-08-11] 잉크 테두리 박스 은퇴. 이 버튼은 criticalWash 라우드-페일 스트립
  // 안에 있는데, 잉크 테두리가 크리티컬 잉크와 싸웠다. 실패 스트립은 박스 버튼이 필요 없다 —
  // runner/run.tsx failAction의 밑줄 텍스트 문법으로 통일 (박스 9개 삭제, 결정 1개).
  retryBtn: { alignSelf: 'flex-start', marginTop: 10, minHeight: 44, justifyContent: 'center' },
  // unopened drop — dark ceremony card, volt edge (artifact vocabulary survives)
  dropCard: { backgroundColor: paper.ink, padding: 16, marginBottom: 10, borderWidth: 1.5, borderColor: colors.volt },
  openBtn: { backgroundColor: colors.volt, alignItems: 'center', paddingVertical: 15, marginTop: 12 },
  pickBtn: { flex: 1, backgroundColor: colors.volt, alignItems: 'center', paddingVertical: 15 },
  card: { backgroundColor: paper.canvas, padding: 14, borderWidth: 1, borderColor: '#EEEEEE' },
  div: { height: 1, backgroundColor: '#EEEEEE' },
  claimChip: { backgroundColor: '#E8F3D2', borderRadius: 0, paddingVertical: 5, paddingHorizontal: 10, alignSelf: 'center' },
  // [0195] The claimable row's chip is now a BUTTON, so it carries a real hit area (≥44pt) and
  // the sage plate it always had. Roomy screen, so the label sits at 16 rather than the 15 floor.
  claimBtn: {
    backgroundColor: '#E8F3D2', paddingVertical: 11, paddingHorizontal: 16,
    minHeight: 44, justifyContent: 'center', alignSelf: 'center',
  },
  claimForm: { paddingBottom: 12, gap: 8 },
  input: {
    borderWidth: 1, borderColor: '#E3E1DA', backgroundColor: paper.canvas,
    paddingHorizontal: 12, paddingVertical: 11, fontSize: 16, color: paper.ink, minHeight: 44,
  },
  claimSubmit: {
    flex: 1.5, backgroundColor: '#E8F3D2', minHeight: 48,
    alignItems: 'center', justifyContent: 'center',
  },
  claimCancel: { flex: 1, minHeight: 48, alignItems: 'center', justifyContent: 'center' },
  rankLink: { alignItems: 'center', marginTop: 18, padding: 10 },
});
