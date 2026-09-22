import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { Row } from '../../src/components/ui';
import {
  fetchNotifications, fetchOpsGearClaimsPending, fetchOpsPayoutsDue, fetchOpsStalledHandoffs,
  fetchOpsStrandedReturns, LiveNoti, OpsGearClaim, OpsPayoutDue, OpsStalledHandoff,
  OpsStrandedReturn, opsMe,
} from '../../src/lib/api';
import { kstCal, kstMonthDay } from '../../src/lib/kst';
import { goBackOrHome } from '../../src/lib/nav';
import { destinationForSystemRef, OPS_SYSTEM_TITLES } from '../../src/lib/notification-route';
import { strandAgeLabel } from '../../src/lib/ops-console';
import { wonLabel } from '../../src/lib/ops-payout';
// RAW server text for the log. Both strips render `e.message`, which is now the mapped Korean
// (api.ts `opsError` → `foldRpcError`), so the log is the only place the server's own words live.
import { rpcRaw } from '../../src/lib/rpc-error';
import { colors, paper } from '../../src/theme';

// 운영 콘솔 홈 — 네 대기열 + 운영 알림. 0186 §B + 0195 §C + [0206] §A/§B.
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

  // `null` = not read yet. NOT an empty list — the difference decides whether a section is drawn.
  const [kinds, setKinds] = useState<string[] | null>(null);

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

  // 🔴 [0206] THE OPERATOR'S OWN INBOX, filtered to the ops kind. `fetchNotifications` reads
  //    `notifications` under RLS `noti self` (0002:138 — `profile_id = auth.uid()`), so this is the
  //    caller's OWN rows and no new read surface: the ops escalations were always addressed to
  //    them and always readable; they simply had nowhere to land. Filtered to `kind === 'system'`
  //    AND to a title with a console destination, so every row drawn here is one this console can
  //    actually open — the remaining `system` rows (if a future writer adds a title) still show in
  //    the ordinary /alerts inbox as text.
  const loadAlerts = useCallback(() => {
    setAlertPhase('loading');
    setAlertErr(null);
    fetchNotifications()
      .then((rows) => {
        setAlerts(rows.filter((n) => n.kind === 'system' && OPS_SYSTEM_TITLES.includes(n.title)));
        setAlertPhase('ready');
      })
      .catch((e) => {
        console.warn('[ops] alerts:', rpcRaw(e));
        setAlertErr((e as Error)?.message || '운영 알림을 불러오지 못했어요');
        setAlertPhase('error');
      });
  }, []);

  // `kinds` decides which desks exist for this operator. A failure here leaves it `null`, which
  // draws neither new section and claims nothing — the `_layout` has already established that the
  // caller is an operator, so this is about WHICH desks, never about access.
  const loadKinds = useCallback(() => {
    opsMe()
      .then((me) => setKinds(me.kinds))
      .catch((e) => { console.warn('[ops] ops_me:', rpcRaw(e)); setKinds(null); });
  }, []);

  // Re-read on every return: paying a runner, posting a box or resolving a strand on a detail
  // screen changes exactly these lists, and a stale count here is an operator acting twice.
  useFocusEffect(useCallback(() => {
    loadKinds(); loadDue(); loadGear(); loadAlerts();
  }, [loadKinds, loadDue, loadGear, loadAlerts]));

  // The two 0206 desks are fetched only when the caller actually holds the class — an unconditional
  // fetch would write a `not_ops` line into the log on every console open for a payout-only
  // operator, and would make the section's error state indistinguishable from a real fault.
  const hasStrandDesk = kinds !== null && kinds.includes('return_strand');
  const hasStallDesk = kinds !== null && kinds.includes('handoff_unanswered');
  useFocusEffect(useCallback(() => {
    if (hasStrandDesk) loadStrand();
    if (hasStallDesk) loadStall();
  }, [hasStrandDesk, hasStallDesk, loadStrand, loadStall]));

  return (
    <>
      <ScrollView
        style={{ flex: 1, backgroundColor: colors.cream }}
        contentContainerStyle={{ paddingHorizontal: 11, paddingTop: insets.top, paddingBottom: insets.bottom + 40 }}
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

        {/* ── 운영 알림 [0206] ───────────────────────────────────────────────────────────
            The operator's OWN `system` rows — the bells 0183 · 0186 · 0193 · 0206 §C ring. Read
            through `fetchNotifications` under RLS `noti self`, so no new read surface: these rows
            were always addressed to this person and always readable, they simply had nowhere to
            land. Every row drawn here has a console destination (the filter guarantees it), so
            there is no dead tap in this list by construction. */}
        <SectionHeader
          title="운영 알림"
          count={alertPhase === 'ready' ? alerts.length : null}
          hint="담당자에게 온 알림 · 누르면 해당 화면으로 가요"
        />

        {alertPhase === 'loading' && <Text style={s.loading}>운영 알림을 불러오는 중이에요…</Text>}

        {alertPhase === 'error' && <FailStrip message={alertErr} onRetry={loadAlerts} />}

        {alertPhase === 'ready' && alerts.length === 0 && (
          <View style={s.emptyCard}>
            <Text style={s.emptyText}>최근 운영 알림이 없어요</Text>
            {/* ⚠ Honest about what this list IS: `fetchNotifications` reads the most recent 20
                rows of every kind, so an operator with a busy inbox can have older ops rows that
                do not appear here. Said rather than implied. */}
            <Text style={s.emptySub}>최근 알림 20건 중 담당자 알림만 보여줘요</Text>
          </View>
        )}

        {alertPhase === 'ready' && alerts.map((n) => (
          <Pressable
            key={n.id}
            onPress={() => {
              const dest = destinationForSystemRef({ refId: n.refId, title: n.title });
              if (dest === null) return;   // unreachable: the filter admits only routable titles
              router.push(dest as Parameters<typeof router.push>[0]);
            }}
            accessibilityRole="button"
            accessibilityLabel={`${n.title} · ${n.when}`}
            style={({ pressed }) => [s.row, pressed && s.rowPressed, n.unread && s.rowUnread]}
          >
            <View style={{ flex: 1, paddingRight: 10 }}>
              <Text style={s.rowTitle}>{n.title}</Text>
              <Text style={s.rowHint}>{n.when}</Text>
            </View>
            <Text style={s.chev}>›</Text>
          </Pressable>
        ))}
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
