import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { Row } from '../../src/components/ui';
import {
  fetchNotifications, fetchOpsGearClaimsPending, fetchOpsPayoutsDue, fetchOpsSealedUnsettled,
  fetchOpsStalledHandoffs, fetchOpsStrandedCustody, fetchOpsStrandedReturns, LiveNoti,
  markNotificationsRead, OpsGearClaim, OpsPayoutDue, OpsSealedUnsettled, OpsStalledHandoff,
  OpsStrandedCustody, OpsStrandedReturn,
} from '../../src/lib/api';
import { kstCal, kstMonthDay } from '../../src/lib/kst';
import { goBackOrHome } from '../../src/lib/nav';
import { destinationForSystemRef } from '../../src/lib/notification-route';
import { strandAgeLabel } from '../../src/lib/ops-console';
import {
  CUSTODY_DESK_CLASS, CUSTODY_EMPTY_KO, CUSTODY_EMPTY_SUB_KO, CUSTODY_FAILED_KO, CUSTODY_LOADING_KO,
  CUSTODY_TITLE_KO, deskAccess, SEALED_DESK_CLASS, SEALED_EMPTY_KO, SEALED_EMPTY_SUB_KO,
  SEALED_FAILED_KO, SEALED_LOADING_KO, SEALED_TITLE_KO,
} from '../../src/lib/ops-custody';
import { useOps } from '../../src/lib/ops-context';
import { wonLabel } from '../../src/lib/ops-payout';
// RAW server text for the log. Both strips render `e.message`, which is now the mapped Korean
// (api.ts `opsError` → `foldRpcError`), so the log is the only place the server's own words live.
import { rpcRaw } from '../../src/lib/rpc-error';
import { colors, paper } from '../../src/theme';

// 운영 콘솔 홈 — 네 대기열 + 운영 알림. 0186 §B + 0195 §C + [0206] §A/§B.
// [0224 §F] + two READ-ONLY desks — 러닝 좌초 (`return_strand`) and 정산 미완료 (`payout_due`) — each
// drawn and fetched only for the roster its read gates on (`deskAccess`, src/lib/ops-custody.ts).
//
// ⚠ EVERY SECTION LOADS INDEPENDENTLY AND FAILS INDEPENDENTLY, and that is not a nicety: an
//   operator whose gear list is broken must still be able to pay people. A single combined
//   `Promise.all` + one error state would take the whole console down for any one failure, which
//   is exactly the shape that makes a tool get abandoned.
// ⚠ Each section is FOUR states and none of them is a blank: 'loading' says so in words (loading
//   is not 0 and it is not an empty list), 'error' is a loud strip with 다시 시도, 'empty' says
//   the queue is genuinely empty, and 'rows' draws them.
// ⚠ Every date goes through `kst.ts` (fixed +9, no Intl — Korea has no DST). `check-device-clock`
//   refuses a device-clock read for a KST fact and this screen has none.
//
// 🔴 **[0206] THE TWO NEW DESKS ARE GATED ON `ops_me().kinds`, NOT ON `isOps`, AND THAT IS THE
//    NO-DEAD-BUTTONS LAW RATHER THAN A PREFERENCE.** 0206 §0b gates `ops_stranded_returns()` on
//    the `return_strand` roster and `ops_stalled_handoffs()` on `handoff_unanswered` — the rosters
//    their bell and their action actually use — while this route group's `_layout` admits on
//    `payout_due` (0198 §0d). So an operator can legitimately be inside the console and refused by
//    one of these two doors. Drawing the section anyway would be a button that opens onto
//    `not_ops`; hiding it when the class IS held would hide a live desk. `kinds` is the caller's
//    own active class list from the same sealed table the gates read, and 237 `0206-R1`/`0206-H1`
//    pin that `kinds` and each door agree in BOTH directions — so this decision cannot quietly
//    become a lie.
//    ⚠ While `kinds` has not been read yet, neither section is drawn and neither is claimed to be
//    empty. An unread answer is not a 'no'.

type Phase = 'loading' | 'error' | 'ready';

export default function OpsHome() {
  const insets = useSafeAreaInsets();

  // [0213] `null` = not read yet. NOT an empty list — the difference decides whether a section is
  // drawn, and an unread answer is not a 'no'. It is the LAYOUT'S value now: the gate already
  // asked `ops_me()` to decide whether to render this stack at all, and asking again here was two
  // round trips on open plus one per return from a desk (`ops-context.tsx` carries the why).
  const { kinds, refresh } = useOps();

  const [duePhase, setDuePhase] = useState<Phase>('loading');
  const [due, setDue] = useState<OpsPayoutDue[]>([]);
  const [dueErr, setDueErr] = useState<string | null>(null);

  const [gearPhase, setGearPhase] = useState<Phase>('loading');
  const [gear, setGear] = useState<OpsGearClaim[]>([]);
  const [gearErr, setGearErr] = useState<string | null>(null);

  const [strandPhase, setStrandPhase] = useState<Phase>('loading');
  const [strand, setStrand] = useState<OpsStrandedReturn[]>([]);
  const [strandErr, setStrandErr] = useState<string | null>(null);

  const [stallPhase, setStallPhase] = useState<Phase>('loading');
  const [stall, setStall] = useState<OpsStalledHandoff[]>([]);
  const [stallErr, setStallErr] = useState<string | null>(null);

  // [0224 §F] the two read-only desks behind the custody-strand and sealed-unsettled bells.
  const [custodyPhase, setCustodyPhase] = useState<Phase>('loading');
  const [custody, setCustody] = useState<OpsStrandedCustody[]>([]);
  const [custodyErr, setCustodyErr] = useState<string | null>(null);

  const [sealedPhase, setSealedPhase] = useState<Phase>('loading');
  const [sealed, setSealed] = useState<OpsSealedUnsettled[]>([]);
  const [sealedErr, setSealedErr] = useState<string | null>(null);

  const [alertPhase, setAlertPhase] = useState<Phase>('loading');
  const [alerts, setAlerts] = useState<LiveNoti[]>([]);
  const [alertErr, setAlertErr] = useState<string | null>(null);

  const loadDue = useCallback(() => {
    setDuePhase('loading');
    setDueErr(null);
    fetchOpsPayoutsDue()
      .then((rows) => { setDue(rows); setDuePhase('ready'); })
      .catch((e) => {
        console.warn('[ops] payouts_due:', rpcRaw(e));
        setDueErr((e as Error)?.message || '지급 대기를 불러오지 못했어요');
        setDuePhase('error');
      });
  }, []);

  const loadGear = useCallback(() => {
    setGearPhase('loading');
    setGearErr(null);
    fetchOpsGearClaimsPending()
      .then((rows) => { setGear(rows); setGearPhase('ready'); })
      .catch((e) => {
        console.warn('[ops] gear_claims_pending:', rpcRaw(e));
        setGearErr((e as Error)?.message || '배송 대기를 불러오지 못했어요');
        setGearPhase('error');
      });
  }, []);

  const loadStrand = useCallback(() => {
    setStrandPhase('loading');
    setStrandErr(null);
    fetchOpsStrandedReturns()
      .then((rows) => { setStrand(rows); setStrandPhase('ready'); })
      .catch((e) => {
        console.warn('[ops] stranded_returns:', rpcRaw(e));
        setStrandErr((e as Error)?.message || '좌초된 반환을 불러오지 못했어요');
        setStrandPhase('error');
      });
  }, []);

  const loadStall = useCallback(() => {
    setStallPhase('loading');
    setStallErr(null);
    fetchOpsStalledHandoffs()
      .then((rows) => { setStall(rows); setStallPhase('ready'); })
      .catch((e) => {
        console.warn('[ops] stalled_handoffs:', rpcRaw(e));
        setStallErr((e as Error)?.message || '멈춘 인계를 불러오지 못했어요');
        setStallPhase('error');
      });
  }, []);

  const loadCustody = useCallback(() => {
    setCustodyPhase('loading');
    setCustodyErr(null);
    fetchOpsStrandedCustody()
      .then((rows) => { setCustody(rows); setCustodyPhase('ready'); })
      .catch((e) => {
        console.warn('[ops] stranded_custody:', rpcRaw(e));
        setCustodyErr((e as Error)?.message || CUSTODY_FAILED_KO);
        setCustodyPhase('error');
      });
  }, []);

  const loadSealed = useCallback(() => {
    setSealedPhase('loading');
    setSealedErr(null);
    fetchOpsSealedUnsettled()
      .then((rows) => { setSealed(rows); setSealedPhase('ready'); })
      .catch((e) => {
        console.warn('[ops] sealed_unsettled:', rpcRaw(e));
        setSealedErr((e as Error)?.message || SEALED_FAILED_KO);
        setSealedPhase('error');
      });
  }, []);

  // 🔴 [0206] THE OPERATOR'S OWN INBOX, filtered to the ops kind. `fetchNotifications` reads
  //    `notifications` under RLS `noti self` (0002:138 — `profile_id = auth.uid()`), so this is the
  //    caller's OWN rows and no new read surface: the ops escalations were always addressed to
  //    them and always readable; they simply had nowhere to land.
  // 🔴 [gap sweep 2026-09-25 · ops-notifications-5/8] TWO FILTERS CHANGED, and both were hiding
  //    work. (a) The kind filter is now SERVER-side (`{ kind: 'system' }`): the old read took the
  //    newest 20 rows of EVERY kind and filtered here, so an operator who is also an owner or a
  //    runner could have an ops bell pushed out of the window by their own chat traffic.
  //    (b) The title filter is GONE. It admitted only the four titles with a console screen, so
  //    seven of the eleven ledgered ops titles (0214 `_noti_ops_titles()` — 카드 해지 실패, the
  //    lost payment marker, the failed compensation records …) never appeared on the desk at all.
  //    Every `system` row is now drawn; the ones with no console door are drawn as plain cards
  //    carrying their BODY, which is the operator's instruction. No dead tap either way.
  const loadAlerts = useCallback(() => {
    setAlertPhase('loading');
    setAlertErr(null);
    fetchNotifications({ kind: 'system' })
      .then((rows) => {
        setAlerts(rows);
        setAlertPhase('ready');
      })
      .catch((e) => {
        console.warn('[ops] alerts:', rpcRaw(e));
        setAlertErr((e as Error)?.message || '운영 알림을 불러오지 못했어요');
        setAlertPhase('error');
      });
  }, []);

  // [ops-notifications-7] Opening a bell marks THAT row read. The 2pt unread border clears only
  // after the write resolves; a failed write is logged and the row stays drawn as unread (the next
  // focus reload is the truth). The navigation does not wait for the bookkeeping.
  const openAlert = useCallback((n: LiveNoti) => {
    const dest = destinationForSystemRef({ refId: n.refId, title: n.title });
    if (dest === null) return;   // unreachable: only rows with a destination are drawn as buttons
    if (n.unread) {
      markNotificationsRead([n.id])
        .then(() => setAlerts((prev) => prev.map((r) => (r.id === n.id ? { ...r, unread: false } : r))))
        .catch((e) => console.warn('[ops] alert mark read:', (e as Error)?.message ?? e));
    }
    router.push(dest as Parameters<typeof router.push>[0]);
  }, []);

  // Re-read on every return: paying a runner, posting a box or resolving a strand on a detail
  // screen changes exactly these lists, and a stale count here is an operator acting twice.
  // 🔴 [0213] `loadKinds()` IS GONE FROM THIS EFFECT and its `opsMe()` call with it. It re-asked
  //    the same RPC the `_layout` had already answered — two round trips on every console open and
  //    another on every return from a desk — for a value that is ROSTER MEMBERSHIP, which nothing
  //    inside this console can change. `kinds` now comes from `useOps()`, and the one way to
  //    re-ask it is the pull-to-refresh below.
  useFocusEffect(useCallback(() => {
    loadDue(); loadGear(); loadAlerts();
  }, [loadDue, loadGear, loadAlerts]));

  // The two 0206 desks are fetched only when the caller actually holds the class — an unconditional
  // fetch would write a `not_ops` line into the log on every console open for a payout-only
  // operator, and would make the section's error state indistinguishable from a real fault.
  const hasStrandDesk = kinds !== null && kinds.includes('return_strand');
  const hasStallDesk = kinds !== null && kinds.includes('handoff_unanswered');
  // [0224 §F] the same rule for the two new desks, each on the roster ITS read gates on: the custody
  // list on `return_strand`, the sealed list on `payout_due` (0224 §F — 「the people who were TOLD are
  // the people who may look」). `deskAccess` is the pinned form (src/lib/ops-custody.ts).
  const hasCustodyDesk = deskAccess(kinds, CUSTODY_DESK_CLASS) === 'held';
  const hasSealedDesk = deskAccess(kinds, SEALED_DESK_CLASS) === 'held';
  useFocusEffect(useCallback(() => {
    if (hasStrandDesk) loadStrand();
    if (hasStallDesk) loadStall();
    if (hasCustodyDesk) loadCustody();
    if (hasSealedDesk) loadSealed();
  }, [hasStrandDesk, hasStallDesk, hasCustodyDesk, hasSealedDesk, loadStrand, loadStall, loadCustody, loadSealed]));

  // [0213] THE ONE REFRESH PATH, and the only thing in this stack that re-asks `ops_me()`. Every
  // section plus the roster answer — an operator who pulls expects the whole screen re-asked, not
  // a subset. `refreshing` is the control's own state and is NOT a section phase: each section
  // keeps its own four states and goes back to saying 「불러오는 중이에요…」 in words.
  const [refreshing, setRefreshing] = useState(false);
  const onRefresh = useCallback(() => {
    setRefreshing(true);
    loadDue(); loadGear(); loadAlerts();
    if (hasStrandDesk) loadStrand();
    if (hasStallDesk) loadStall();
    if (hasCustodyDesk) loadCustody();
    if (hasSealedDesk) loadSealed();
    // Only the roster re-ask is awaited, because it is the one whose progress this screen has no
    // section phase for. A refresh that FAILS keeps the last known answer (see `_layout`): the
    // spinner stops and nothing claims the operator lost a desk.
    refresh().finally(() => setRefreshing(false));
  }, [loadDue, loadGear, loadAlerts, loadStrand, loadStall, loadCustody, loadSealed,
    hasStrandDesk, hasStallDesk, hasCustodyDesk, hasSealedDesk, refresh]);

  return (
    <>
      <ScrollView
        style={{ flex: 1, backgroundColor: colors.cream }}
        contentContainerStyle={{ paddingHorizontal: 11, paddingTop: insets.top, paddingBottom: insets.bottom + 40 }}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={paper.dim} />
        }
      >
        <Row style={{ justifyContent: 'space-between' }}>
          <Pressable onPress={goBackOrHome} style={s.backBtn} accessibilityRole="button" accessibilityLabel="뒤로">
            <Text style={{ fontSize: 20.5 }}>‹</Text>
          </Pressable>
          <Text style={{ fontSize: 23, fontWeight: '900', color: paper.ink }}>운영 콘솔</Text>
          <View style={{ width: 40 }} />
        </Row>

        {/* ── 지급 대기 ─────────────────────────────────────────────────────────────────── */}
        {/* ⚠ The count is only printed once the list is READ. 「지급 대기 0」 while loading would be
            a number we do not have, which is the honesty law this repo states first. */}
        <SectionHeader
          title="지급 대기"
          count={duePhase === 'ready' ? due.length : null}
          hint="러너별 미지급 정산 합계 · 누르면 어떤 행을 덮는지 고를 수 있어요"
        />

        {duePhase === 'loading' && <Text style={s.loading}>지급 대기를 불러오는 중이에요…</Text>}

        {duePhase === 'error' && (
          <FailStrip message={dueErr} onRetry={loadDue} />
        )}

        {duePhase === 'ready' && due.length === 0 && (
          <View style={s.emptyCard}>
            <Text style={s.emptyText}>지금 지급할 것이 없어요</Text>
            <Text style={s.emptySub}>정산이 끝난 미지급 행이 있는 러너만 여기에 나와요</Text>
          </View>
        )}

        {duePhase === 'ready' && due.map((d) => (
          <Pressable
            key={d.runnerProfileId}
            onPress={() => router.push(`/ops/payout/${d.runnerProfileId}`)}
            accessibilityRole="button"
            accessibilityLabel={`러너 ${shortId(d.runnerProfileId)} · ${wonLabel(d.unpaidNetWon)} 미지급`}
            style={({ pressed }) => [s.row, pressed && s.rowPressed]}
          >
            <View style={{ flex: 1, paddingRight: 10 }}>
              {/* ⚠ An ID, not a name. 0186 §B carries no name, no phone and no bank row on
                  purpose — the amount and the person's details must not meet in one window. */}
              <Text style={s.rowTitle}>러너 {shortId(d.runnerProfileId)}</Text>
              <Text style={s.rowHint}>
                {d.unpaidItems}건{d.oldestUnpaidAt ? ` · 가장 오래된 행 ${kstMonthDay(kstCal(Date.parse(d.oldestUnpaidAt)))}` : ''}
              </Text>
            </View>
            <Text style={s.rowAmount}>{wonLabel(d.unpaidNetWon)}</Text>
            <Text style={s.chev}>›</Text>
          </Pressable>
        ))}

        {/* ── 배송 대기 ─────────────────────────────────────────────────────────────────── */}
        <SectionHeader
          title="배송 대기"
          count={gearPhase === 'ready' ? gear.length : null}
          hint="수령 신청은 됐고 아직 안 보낸 굿즈 · 누르면 주소와 송장 입력이 나와요"
        />

        {gearPhase === 'loading' && <Text style={s.loading}>배송 대기를 불러오는 중이에요…</Text>}

        {gearPhase === 'error' && (
          <FailStrip message={gearErr} onRetry={loadGear} />
        )}

        {gearPhase === 'ready' && gear.length === 0 && (
          <View style={s.emptyCard}>
            <Text style={s.emptyText}>보낼 굿즈가 없어요</Text>
            <Text style={s.emptySub}>수령 신청이 들어오면 여기에 나와요</Text>
          </View>
        )}

        {gearPhase === 'ready' && gear.map((g) => (
          <Pressable
            key={g.claimId}
            onPress={() => router.push(`/ops/gear/${g.claimId}`)}
            accessibilityRole="button"
            accessibilityLabel={`${g.item} · 받는사람 ${g.recipient ?? '미상'}`}
            style={({ pressed }) => [s.row, pressed && s.rowPressed]}
          >
            <View style={{ flex: 1, paddingRight: 10 }}>
              <Text style={s.rowTitle}>{g.item}</Text>
              <Text style={s.rowHint}>
                {g.recipient ?? '받는사람 미상'}
                {g.claimedAt ? ` · ${kstMonthDay(kstCal(Date.parse(g.claimedAt)))} 신청` : ''}
              </Text>
            </View>
            <Text style={s.chev}>›</Text>
          </Pressable>
        ))}

        {/* ── 반환 좌초 [0206 §A] ────────────────────────────────────────────────────────
            Drawn only for an operator on the `return_strand` roster — the roster
            `ops_stranded_returns()` and `ops_resolve_return_tx` both gate on. See the header. */}
        {hasStrandDesk && (
          <>
            <SectionHeader
              title="반환 좌초"
              count={strandPhase === 'ready' ? strand.length : null}
              hint="러닝은 끝났는데 반환 확인이 안 끝난 예약 · 누르면 사실과 처리 버튼이 나와요"
            />

            {strandPhase === 'loading' && <Text style={s.loading}>좌초된 반환을 불러오는 중이에요…</Text>}

            {strandPhase === 'error' && <FailStrip message={strandErr} onRetry={loadStrand} />}

            {strandPhase === 'ready' && strand.length === 0 && (
              <View style={s.emptyCard}>
                <Text style={s.emptyText}>좌초된 반환이 없어요</Text>
                <Text style={s.emptySub}>마감을 넘긴 반환이 생기면 여기에 나와요</Text>
              </View>
            )}

            {strandPhase === 'ready' && strand.map((r) => (
              <Pressable
                key={r.bookingId}
                onPress={() => router.push(`/ops/returns/${r.bookingId}`)}
                accessibilityRole="button"
                accessibilityLabel={`${r.dogName ?? '이름 없는 강아지'} 반환 좌초`}
                style={({ pressed }) => [s.row, pressed && s.rowPressed]}
              >
                <View style={{ flex: 1, paddingRight: 10 }}>
                  <Text style={s.rowTitle}>{r.dogName ?? '이름 없는 강아지'}</Text>
                  <Text style={s.rowHint}>
                    {r.ownerName ?? '보호자'} · {r.runnerName ?? '러너'}
                    {strandAgeLabel(r.minutesStranded) !== null ? ` · ${strandAgeLabel(r.minutesStranded)}` : ''}
                  </Text>
                </View>
                <Text style={s.chev}>›</Text>
              </Pressable>
            ))}
          </>
        )}

        {/* ── 인계 멈춤 [0206 §B] ────────────────────────────────────────────────────────
            A READ-ONLY desk (0183 arm ⓓ's ruling — what a stuck handoff should become is Sean's
            call). The row here is a count and a door to the list; there is no action anywhere. */}
        {hasStallDesk && (
          <>
            <SectionHeader
              title="인계 멈춤"
              count={stallPhase === 'ready' ? stall.length : null}
              hint="한쪽만 확인한 채 멈춘 인계 · 보기 전용이에요"
            />

            {stallPhase === 'loading' && <Text style={s.loading}>멈춘 인계를 불러오는 중이에요…</Text>}

            {stallPhase === 'error' && <FailStrip message={stallErr} onRetry={loadStall} />}

            {stallPhase === 'ready' && stall.length === 0 && (
              <View style={s.emptyCard}>
                <Text style={s.emptyText}>멈춘 인계가 없어요</Text>
                <Text style={s.emptySub}>한쪽만 확인한 인계가 30분을 넘기면 여기에 나와요</Text>
              </View>
            )}

            {stallPhase === 'ready' && stall.length > 0 && (
              <Pressable
                onPress={() => router.push('/ops/handoffs')}
                accessibilityRole="button"
                accessibilityLabel={`멈춘 인계 ${stall.length}건 보기`}
                style={({ pressed }) => [s.row, pressed && s.rowPressed]}
              >
                <View style={{ flex: 1, paddingRight: 10 }}>
                  <Text style={s.rowTitle}>멈춘 인계 {stall.length}건</Text>
                  <Text style={s.rowHint}>누르면 어떤 예약인지, 어느 쪽을 기다리는지 보여요</Text>
                </View>
                <Text style={s.chev}>›</Text>
              </Pressable>
            )}
          </>
        )}

        {/* ── 러닝 좌초 [0224 §F] ────────────────────────────────────────────────────────
            A READ-ONLY desk: whether an operator may start or end a run the runner never did is
            Sean's letter (0224 §0c). Drawn only for the `return_strand` roster. The row here is a
            count and a door to the list; there is no action anywhere. */}
        {hasCustodyDesk && (
          <>
            <SectionHeader
              title={CUSTODY_TITLE_KO}
              count={custodyPhase === 'ready' ? custody.length : null}
              hint="인계 후 시작되지 않았거나 종료되지 않은 러닝 · 보기 전용이에요"
            />

            {custodyPhase === 'loading' && <Text style={s.loading}>{CUSTODY_LOADING_KO}</Text>}

            {custodyPhase === 'error' && <FailStrip message={custodyErr} onRetry={loadCustody} />}

            {custodyPhase === 'ready' && custody.length === 0 && (
              <View style={s.emptyCard}>
                <Text style={s.emptyText}>{CUSTODY_EMPTY_KO}</Text>
                <Text style={s.emptySub}>{CUSTODY_EMPTY_SUB_KO}</Text>
              </View>
            )}

            {custodyPhase === 'ready' && custody.length > 0 && (
              <Pressable
                onPress={() => router.push('/ops/custody')}
                accessibilityRole="button"
                accessibilityLabel={`멈춘 러닝 ${custody.length}건 보기`}
                style={({ pressed }) => [s.row, pressed && s.rowPressed]}
              >
                <View style={{ flex: 1, paddingRight: 10 }}>
                  <Text style={s.rowTitle}>멈춘 러닝 {custody.length}건</Text>
                  <Text style={s.rowHint}>누르면 어떤 예약인지, 시작과 종료 중 무엇이 멈췄는지 보여요</Text>
                </View>
                <Text style={s.chev}>›</Text>
              </Pressable>
            )}
          </>
        )}

        {/* ── 정산 미완료 [0224 §F] ──────────────────────────────────────────────────────
            A READ-ONLY desk: settling a sealed row needs the pricing re-drive (0083 §0f), which is
            not built. Drawn only for the `payout_due` roster. */}
        {hasSealedDesk && (
          <>
            <SectionHeader
              title={SEALED_TITLE_KO}
              count={sealedPhase === 'ready' ? sealed.length : null}
              hint="양측 반환 확인 후 정산이 멈춘 예약 · 보기 전용이에요"
            />

            {sealedPhase === 'loading' && <Text style={s.loading}>{SEALED_LOADING_KO}</Text>}

            {sealedPhase === 'error' && <FailStrip message={sealedErr} onRetry={loadSealed} />}

            {sealedPhase === 'ready' && sealed.length === 0 && (
              <View style={s.emptyCard}>
                <Text style={s.emptyText}>{SEALED_EMPTY_KO}</Text>
                <Text style={s.emptySub}>{SEALED_EMPTY_SUB_KO}</Text>
              </View>
            )}

            {sealedPhase === 'ready' && sealed.length > 0 && (
              <Pressable
                onPress={() => router.push('/ops/sealed')}
                accessibilityRole="button"
                accessibilityLabel={`정산 미완료 ${sealed.length}건 보기`}
                style={({ pressed }) => [s.row, pressed && s.rowPressed]}
              >
                <View style={{ flex: 1, paddingRight: 10 }}>
                  <Text style={s.rowTitle}>정산 미완료 {sealed.length}건</Text>
                  <Text style={s.rowHint}>누르면 어떤 예약인지, 봉인 후 얼마나 지났는지 보여요</Text>
                </View>
                <Text style={s.chev}>›</Text>
              </Pressable>
            )}
          </>
        )}

        {/* ── 운영 알림 [0206] ───────────────────────────────────────────────────────────
            The operator's OWN `system` rows — the bells 0183 · 0186 · 0193 · 0206 §C ring, plus
            the ledgered titles with no console screen (0214 `_noti_ops_titles()`). Read through
            `fetchNotifications({ kind: 'system' })` under RLS `noti self`, so no new read surface.
            A row is a BUTTON only when `destinationForSystemRef` names a screen; otherwise it is a
            plain card that carries its body — the instruction is the whole content, and a chevron
            on a card that goes nowhere would be a dead button. */}
        <SectionHeader
          title="운영 알림"
          count={alertPhase === 'ready' ? alerts.length : null}
          hint="담당자에게 온 알림 · 누를 수 있는 알림은 해당 화면으로 가요"
        />

        {alertPhase === 'loading' && <Text style={s.loading}>운영 알림을 불러오는 중이에요…</Text>}

        {alertPhase === 'error' && <FailStrip message={alertErr} onRetry={loadAlerts} />}

        {alertPhase === 'ready' && alerts.length === 0 && (
          <View style={s.emptyCard}>
            <Text style={s.emptyText}>최근 운영 알림이 없어요</Text>
            {/* ⚠ Honest about what this list IS: the newest 20 `system` rows addressed to this
                person, so an older bell past that window does not appear here. Said rather than
                implied. */}
            <Text style={s.emptySub}>최근 담당자 알림 20건 안에 없어요</Text>
          </View>
        )}

        {alertPhase === 'ready' && alerts.map((n) => (
          destinationForSystemRef({ refId: n.refId, title: n.title }) !== null ? (
            <Pressable
              key={n.id}
              onPress={() => openAlert(n)}
              accessibilityRole="button"
              accessibilityLabel={`${n.unread ? '안 읽음 · ' : ''}${n.title} · ${n.when}`}
              style={({ pressed }) => [s.row, pressed && s.rowPressed, n.unread && s.rowUnread]}
            >
              <View style={{ flex: 1, paddingRight: 10 }}>
                <Text style={s.rowTitle}>{n.title}</Text>
                <Text style={s.rowHint}>{n.when}</Text>
              </View>
              <Text style={s.chev}>›</Text>
            </Pressable>
          ) : (
            <View key={n.id} style={[s.row, n.unread && s.rowUnread]}>
              <View style={{ flex: 1 }}>
                <Text style={s.rowTitle}>{n.title}</Text>
                {n.body ? <Text style={s.rowBody}>{n.body}</Text> : null}
                <Text style={s.rowHint}>{n.when}</Text>
              </View>
            </View>
          )
        ))}

        {/* ── 운영자 명단 ───────────────────────────────────────────────────────────────── */}
        {/* 0208. A LINK and not a section: the roster is not a queue, so it has no count to
            print and nothing about it can be stale in a way that costs money. It sits last
            because it is the thing an operator touches once a quarter, not once a shift. */}
        <Pressable
          onPress={() => router.push('/ops/roster')}
          accessibilityRole="button"
          accessibilityLabel="운영자 명단"
          style={({ pressed }) => [s.row, { marginTop: 22 }, pressed && s.rowPressed]}
        >
          <View style={{ flex: 1, paddingRight: 10 }}>
            <Text style={s.rowTitle}>운영자 명단</Text>
            <Text style={s.rowHint}>누가 어떤 운영 알림을 받는지 · 콘솔에 들어올 수 있는 사람</Text>
          </View>
          <Text style={s.chev}>›</Text>
        </Pressable>
      </ScrollView>
      <StatusBarCover color={colors.cream} />
    </>
  );
}

/** ⚠ `count === null` means NOT READ YET and prints nothing at all. A 0 in that position would be
 *  a claim about the world made before the world was consulted. */
function SectionHeader({ title, count, hint }: { title: string; count: number | null; hint: string }) {
  return (
    <View style={{ marginTop: 22 }}>
      <Row style={{ justifyContent: 'flex-start', alignItems: 'baseline' }}>
        <Text style={s.secTitle}>{title}</Text>
        {count !== null && <Text style={s.secCount}>{count}</Text>}
      </Row>
      <Text style={s.secHint}>{hint}</Text>
    </View>
  );
}

function FailStrip({ message, onRetry }: { message: string | null; onRetry: () => void }) {
  return (
    <View style={s.failStrip}>
      <Text style={s.failText}>{message ?? '불러오지 못했어요'}</Text>
      <Pressable onPress={onRetry} accessibilityRole="button" style={s.retryBtn}>
        <Text style={s.retryLabel}>다시 시도</Text>
      </Pressable>
    </View>
  );
}

/** The first eight characters of a uuid, uppercased — enough to tell two rows apart and to read
 *  aloud, and deliberately not a name (0186 §B). */
function shortId(id: string): string {
  return id.slice(0, 8).toUpperCase();
}

const s = StyleSheet.create({
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', borderWidth: 1, borderColor: colors.line },
  secTitle: { fontSize: 20, fontWeight: '900', color: paper.ink },
  secCount: { fontSize: 20, fontWeight: '900', color: paper.action, marginLeft: 8 },
  secHint: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 3, marginBottom: 10 },
  loading: { fontSize: 15.5, lineHeight: 22, color: paper.dim, paddingVertical: 14 },
  row: {
    flexDirection: 'row', alignItems: 'center',
    backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: colors.line,
    paddingHorizontal: 15, paddingVertical: 14, marginBottom: 8, minHeight: 64,
  },
  rowPressed: { transform: [{ scale: 0.985 }] },
  rowUnread: { borderColor: paper.ink, borderWidth: 2 },
  rowTitle: { fontSize: 17, fontWeight: '800', color: paper.ink },
  rowHint: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 3 },
  // The body of a bell with no console door is the operator's instruction, so it is INK, not dim —
  // it is the one thing on that card that must not be skipped.
  rowBody: { fontSize: 15, lineHeight: 21, color: paper.ink, marginTop: 4 },
  rowAmount: { fontSize: 18, fontWeight: '900', color: paper.ink },
  chev: { fontSize: 16, color: paper.dim, marginLeft: 8 },
  emptyCard: { backgroundColor: '#fff', borderRadius: 16, borderWidth: 1, borderColor: colors.line, paddingHorizontal: 15, paddingVertical: 18 },
  emptyText: { fontSize: 16, fontWeight: '800', color: paper.ink },
  emptySub: { fontSize: 15, lineHeight: 21, color: paper.dim, marginTop: 4 },
  failStrip: { backgroundColor: paper.criticalWash, borderRadius: 16, padding: 13 },
  failText: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.critical },
  retryBtn: { alignSelf: 'flex-start', marginTop: 8, minHeight: 44, justifyContent: 'center' },
  retryLabel: { fontSize: 16, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
});
