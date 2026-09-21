import { router, useFocusEffect } from 'expo-router';
import { useCallback, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { StatusBarCover } from '../../src/components/status-bar-cover';
import { Row } from '../../src/components/ui';
import {
  fetchOpsGearClaimsPending, fetchOpsPayoutsDue, OpsGearClaim, OpsPayoutDue,
} from '../../src/lib/api';
import { kstCal, kstMonthDay } from '../../src/lib/kst';
import { goBackOrHome } from '../../src/lib/nav';
import { wonLabel } from '../../src/lib/ops-payout';
import { colors, paper } from '../../src/theme';

// 운영 콘솔 홈 — 두 대기열. 0186 §B + 0195 §C.
//
// ⚠ THE TWO SECTIONS LOAD INDEPENDENTLY AND FAIL INDEPENDENTLY, and that is not a nicety: an
//   operator whose gear list is broken must still be able to pay people. A single combined
//   `Promise.all` + one error state would take the whole console down for either failure, which is
//   exactly the shape that makes a tool get abandoned.
// ⚠ Each section is FOUR states and none of them is a blank: 'loading' says so in words (loading
//   is not 0 and it is not an empty list), 'error' is a loud strip with 다시 시도, 'empty' says
//   the queue is genuinely empty, and 'rows' draws them.
// ⚠ Every date goes through `kst.ts` (fixed +9, no Intl — Korea has no DST). `check-device-clock`
//   refuses a device-clock read for a KST fact and this screen has none.

type Phase = 'loading' | 'error' | 'ready';

export default function OpsHome() {
  const insets = useSafeAreaInsets();

  const [duePhase, setDuePhase] = useState<Phase>('loading');
  const [due, setDue] = useState<OpsPayoutDue[]>([]);
  const [dueErr, setDueErr] = useState<string | null>(null);

  const [gearPhase, setGearPhase] = useState<Phase>('loading');
  const [gear, setGear] = useState<OpsGearClaim[]>([]);
  const [gearErr, setGearErr] = useState<string | null>(null);

  const loadDue = useCallback(() => {
    setDuePhase('loading');
    setDueErr(null);
    fetchOpsPayoutsDue()
      .then((rows) => { setDue(rows); setDuePhase('ready'); })
      .catch((e) => { setDueErr((e as Error)?.message || '지급 대기를 불러오지 못했어요'); setDuePhase('error'); });
  }, []);

  const loadGear = useCallback(() => {
    setGearPhase('loading');
    setGearErr(null);
    fetchOpsGearClaimsPending()
      .then((rows) => { setGear(rows); setGearPhase('ready'); })
      .catch((e) => { setGearErr((e as Error)?.message || '배송 대기를 불러오지 못했어요'); setGearPhase('error'); });
  }, []);

  // Re-read on every return: paying a runner or posting a box on a detail screen changes exactly
  // these two lists, and a stale count here is an operator paying someone twice.
  useFocusEffect(useCallback(() => { loadDue(); loadGear(); }, [loadDue, loadGear]));

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
