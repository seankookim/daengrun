// ⑪ 반환 봉인 — the runner's side of the return handoff. Lab `journey-v4-runner.html` §F, R6a/b/c.
//
// ═══ WHY THIS SCREEN DID NOT EXIST UNTIL NOW ═══
// The lab's own note: "클라이언트엔 러너 반환 화면이 아직 없습니다 — done.tsx는 '초코를 보호자에게
// 안전하게 인계해 주세요'라고만 말하고 버튼이 없습니다. 이 화면이 그 빈자리이고, 0092의
// work-gate(R1c)가 풀리는 지점입니다." The server has had `confirm_return_tx` since 0083 and zero
// product callers; a button drawn before the run-end re-sequencing would have drawn a seal that
// never happened (RULINGS-2026-08-19 §runner journey v4).
//
// ═══ THE THREE FRAMES ARE ONE SCREEN, DRAWN FROM SERVER TRUTH ═══
//   R6a 내 봉인      — neither stamp · coral CTA 「돌려줬어요 — 봉인」
//   R6b 보호자 대기  — my stamp in, theirs not · lilac (waiting) · CORAL ZERO · exits are ink
//   R6c 양측 봉인    — both stamps · sage · CTA is sage (the colour of completion)
// The frame is never local state: it is `runnerConfirmedAt`/`ownerConfirmedAt`/`sealedAt` off the
// booking. SEALS FILL ON SERVER TRUTH ONLY (DESIGN.md) — an optimistic stamp here would be a
// drawn claim about the other party, which is the one thing this ceremony exists to make real.
//
// ⚠ `sealedAt` is read, not derived from "both stamps present". From `incident_review` 0096 lets
// both stamps exist while NOTHING is sealed, and a screen that computed `both ⇒ sealed` would
// tell the runner their money is moving when it is not.
//
// ⚠ The GO colour law, applied (DESIGN.md §owner home, same grammar): coral = YOUR turn · lilac =
// waiting on someone else · sage = done. So R6b has no coral anywhere — not a dimmed CTA, not a
// disabled one. A button you cannot press is not drawn.
//
// ⚠ NO 돌려줄 것 CHECKLIST. The lab draws one and marks it `[체크 목록 — 코드 없음, 플레이스홀더]`.
// There is no column for it, so it is omitted rather than mocked (honesty law: bind real fields
// or omit the element).
//
// ⚠ NO 운영자 force BUTTON. 0089 removed the party force; ops-only. Drawing one would be a dead
// button. The 안심 센터 line the lab shows routes to the real incident screen.
import { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Pressable, ScrollView, Text, View } from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import {
  confirmRunReturn, ensureThread, fetchReturnSeal, returnSealFresh, ReturnSeal,
} from '../../src/lib/api';
import { PaperBtn } from '../../src/components/paper-btn';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { haptic } from '../../src/lib/haptics';
import { runnerJob } from '../../src/store';
import { paper } from '../../src/theme';

/** How often we ask whether the owner has stamped. The counterparty's tap is the only thing this
 *  screen waits for, and it arrives as a push too — the poll is what makes the seal land while the
 *  runner is LOOKING at it, which is the whole moment. Stopped the instant the pair completes. */
const POLL_MS = 5000;

function hhmm(iso: string | null): string {
  if (!iso) return '';
  // KST is a fixed +9 with no DST (src/lib/kst.ts's law) — arithmetic, never the device clock and
  // never Intl, which `check-device-clock.mjs` refuses in a route module.
  const d = new Date(new Date(iso).getTime() + 9 * 3600_000);
  return `${String(d.getUTCHours()).padStart(2, '0')}:${String(d.getUTCMinutes()).padStart(2, '0')}`;
}

function kmLabel(km: number | null): string | null {
  return km == null ? null : `${km.toFixed(2)}km`;
}

function durLabel(sec: number | null): string | null {
  if (sec == null) return null;
  const m = Math.floor(sec / 60);
  return `${String(m).padStart(2, '0')}:${String(sec % 60).padStart(2, '0')}`;
}

const END_REASON_LABEL: Record<string, string> = {
  completed: '완주',
  dog_condition: '컨디션 종료',
  owner_request: '보호자 요청 종료',
  runner_personal: '러너 사정 종료',
};

/** One seal. `on` is a SERVER fact and the only input that decides whether the seal is filled —
 *  there is deliberately no animation prop: the once-per-entity gate lives in the screen
 *  (`returnSealFresh` + `popRef`), and a per-seal `fresh` would let two circles disagree about
 *  whether the same moment was new. */
function Seal({ label, sub, on, tone }: { label: string; sub: string; on: boolean; tone: 'coral' | 'sage' }) {
  const fill = on ? (tone === 'sage' ? paper.ready : paper.action) : 'transparent';
  return (
    <View
      style={{
        width: 104, height: 104, borderRadius: 52, alignItems: 'center', justifyContent: 'center',
        borderWidth: 2, borderColor: on ? fill : '#D8D3E6', backgroundColor: on ? fill : paper.canvas,
      }}
    >
      <Text style={{ fontSize: 15, fontWeight: '900', color: on ? '#FFFFFF' : paper.faint, letterSpacing: 0.5 }}>
        {label}
      </Text>
      <Text style={{ fontSize: 15, fontWeight: '700', color: on ? '#FFFFFF' : paper.faint, marginTop: 2 }}>
        {sub}
      </Text>
    </View>
  );
}

export default function ReturnSeal() {
  const insets = useSafeAreaInsets();
  const df = useDisplayFont();
  const nf = useNumFont();
  const { bid } = useLocalSearchParams<{ bid?: string }>();
  // The booking id can arrive three ways and all three are real: a param (the R1c strip and the
  // push both pass one), the in-flight store (the stop routes here directly), and neither — which
  // is an honest empty state, not a crash.
  const bookingId = (typeof bid === 'string' && bid) || runnerJob.bookingId || null;

  const [seal, setSeal] = useState<ReturnSeal | null>(null);
  // THREE STATES, NEVER TWO: loading · loaded-and-absent · failed. Merging the last two tells a
  // runner on flaky LTE that a run they just finished does not exist (the report screen's law).
  const [state, setState] = useState<'loading' | 'ready' | 'notfound' | 'err'>(bookingId ? 'loading' : 'notfound');
  const [busy, setBusy] = useState(false);
  const [actionErr, setActionErr] = useState<string | null>(null);
  // The pop plays once per booking per app session (`returnSealFresh`, the `sealStampFresh`
  // idiom). Re-entering after the seal hydrates the filled state with no animation.
  // ⚠ [cold review #10] `popped` is RENDERED (the 「방금 확인됐어요」 line below), not merely set.
  // Its first version stored the flag and drew nothing, so the whole once-per-entity apparatus
  // gated a haptic and read as coverage for a celebration that did not exist.
  const popRef = useRef<boolean | null>(null);
  const [popped, setPopped] = useState(false);

  const load = useCallback(() => {
    if (!bookingId) return;
    fetchReturnSeal(bookingId)
      .then((s) => {
        if (!s) { setState('notfound'); return; }
        setSeal(s);
        setState('ready');
      })
      .catch((e) => {
        console.warn('[return-seal] load:', (e as Error)?.message);
        setState('err');
      });
  }, [bookingId]);

  useEffect(() => { load(); }, [load]);

  const bothIn = !!seal?.runnerConfirmedAt && !!seal?.ownerConfirmedAt;

  // Poll only while there is something to wait for. A timer that keeps running after the pair
  // completes is a battery cost with no question behind it.
  useEffect(() => {
    if (state !== 'ready' || bothIn || !bookingId) return;
    const t = setInterval(load, POLL_MS);
    return () => clearInterval(t);
  }, [state, bothIn, bookingId, load]);

  // The celebration, exactly once per entity.
  useEffect(() => {
    if (!bothIn || !bookingId) return;
    if (popRef.current === null) popRef.current = returnSealFresh(bookingId);
    if (popRef.current && !popped) { setPopped(true); haptic('success'); }
  }, [bothIn, bookingId, popped]);

  const stamp = async () => {
    if (!bookingId || busy) return;
    setBusy(true);
    setActionErr(null);
    try {
      const res = await confirmRunReturn(bookingId);
      haptic(res.sealed || res.bothConfirmed ? 'success' : 'light');
      // Never draw the seal from the response's optimism — re-read the row. The response says what
      // the server DID; the row is what the server HAS, and these three circles are supposed to
      // mean the second thing.
      load();
    } catch (e) {
      // A failure is shown as a failure. The stamp is idempotent server-side, so a retry is safe
      // and the sentence says so rather than guessing what happened.
      setActionErr((e as Error).message || '인계 확인에 실패했어요 — 다시 시도해주세요');
    } finally {
      setBusy(false);
    }
  };

  const pad = { paddingHorizontal: 18 };

  if (state === 'loading') {
    return (
      <View style={{ flex: 1, backgroundColor: paper.canvas, paddingTop: insets.top + 16, alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator color={paper.action} />
        <Text style={{ marginTop: 10, fontSize: 15, color: paper.dim }}>인계 상태를 불러오는 중이에요</Text>
      </View>
    );
  }

  if (state === 'err' || state === 'notfound') {
    const failed = state === 'err';
    return (
      <View style={{ flex: 1, backgroundColor: paper.canvas, paddingTop: insets.top + 16, ...pad }}>
        <Text style={[df, { fontSize: 22, color: paper.ink, marginTop: 24 }]}>
          {failed ? '인계 상태를 불러오지 못했어요' : '확인할 인계가 없어요'}
        </Text>
        <Text style={{ fontSize: 15, color: paper.dim, marginTop: 6, lineHeight: 22 }}>
          {failed
            ? '연결을 확인하고 다시 시도해주세요 — 기록은 서버에 그대로 있어요.'
            : '이 예약은 이미 마무리됐거나 내 예약이 아니에요.'}
        </Text>
        {failed
          ? <PaperBtn label="다시 시도" onPress={() => { setState('loading'); load(); }} style={{ marginTop: 20 }} />
          : <PaperBtn label="일정으로" variant="secondary" onPress={() => router.replace('/runner/calendar')} style={{ marginTop: 20 }} />}
      </View>
    );
  }

  const s = seal!;
  // ⚠ The run has not been stopped. Reaching here from a stale push is legitimate; the ceremony
  // simply is not open yet, and saying so is better than a disabled CTA with no reason.
  if (!s.runEndedAt) {
    return (
      <View style={{ flex: 1, backgroundColor: paper.canvas, paddingTop: insets.top + 16, ...pad }}>
        <Text style={[df, { fontSize: 22, color: paper.ink, marginTop: 24 }]}>아직 러닝이 끝나지 않았어요</Text>
        <Text style={{ fontSize: 15, color: paper.dim, marginTop: 6, lineHeight: 22 }}>
          러닝을 종료하면 여기서 인계를 확인할 수 있어요.
        </Text>
        <PaperBtn label="러닝 화면으로" onPress={() => router.replace('/runner/run')} style={{ marginTop: 20 }} />
      </View>
    );
  }

  const mine = !!s.runnerConfirmedAt;
  const theirs = !!s.ownerConfirmedAt;
  // 🔴 [cold review #5] `sealed` IS NOT `settled`. `sealedAt` is `settlement_ready_at` — 「money MAY
  // move」 — and a settlement moves the row to `completed` in the same transaction. So any
  // externally visible `sealedAt` on a row still `active` means SEALED AND NOT SETTLED, which is
  // precisely the stranded state. Printing 「정산이 확정됐어요」 there renders a failure as the happy
  // path. The settled claim is drawn from `rawStatus === 'completed'` and from nothing else.
  const sealed = !!s.sealedAt;
  const settled = s.rawStatus === 'completed';
  // 🔴 [cold review #4] THE STATUS ALLOW-LIST, and `rawStatus` was fetched and never read until
  // now. `confirm_return_tx` accepts `active` and `incident_review` and raises `not_active` for
  // everything else (0096 §2) — and a stranded return really does reach `refund_pending`
  // (arm ⓑ-① escalates to `incident_review`, 0072:179 moves it on, legal via 0066:56's `else`).
  // The escalation push 「귀가 확인이 필요해요」 routes the runner HERE, so without this the product
  // aimed a runner at a full-coral button whose every tap 409s. Gate on the raw status, never on
  // display vocabulary (house law).
  const canStamp = s.rawStatus === 'active' || s.rawStatus === 'incident_review';
  // R6a = neither/mine-missing · R6b = mine in, theirs out · R6c = both
  const frame: 'a' | 'b' | 'c' = bothIn ? 'c' : mine ? 'b' : 'a';
  const dog = s.dogName ?? '반려견';
  const alertTone = frame === 'c' ? paper.ready : frame === 'b' ? '#6C5CE7' : paper.ready;
  const alertText = frame === 'c'
    ? `${dog}가 집에 돌아갔어요`
    : frame === 'b'
      ? '보호자 확인 대기 중'
      : `러닝 종료 · ${dog}를 돌려주세요`;
  const alertSub = frame === 'c'
    ? `양측 확인 ${hhmm(s.ownerConfirmedAt && s.runnerConfirmedAt && s.ownerConfirmedAt > s.runnerConfirmedAt ? s.ownerConfirmedAt : s.runnerConfirmedAt)}${settled ? ' · 정산 기록됨' : ''} · 새 요청을 받을 수 있어요`
    : frame === 'b'
      ? `보호자 앱에 확인 요청을 보냈어요 · ${hhmm(s.runnerConfirmedAt)}`
      : [kmLabel(s.actualKm), durLabel(s.durationSec), s.endReason ? END_REASON_LABEL[s.endReason] ?? null : null]
        .filter(Boolean).join(' · ');

  return (
    <View style={{ flex: 1, backgroundColor: paper.canvas }}>
      <View style={[pad, { paddingTop: insets.top + 10, paddingBottom: 8, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' }]}>
        <Pressable onPress={() => router.back()} hitSlop={10}>
          <Text style={{ fontSize: 22, color: paper.ink }}>‹</Text>
        </Pressable>
        <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>인계 · 반환</Text>
        <Pressable
          hitSlop={10}
          onPress={async () => {
            if (!bookingId) return;
            try { await ensureThread(bookingId); } catch (e) { console.warn('[return-seal] thread:', (e as Error)?.message); }
            router.push({ pathname: '/chat', params: { bid: bookingId } });
          }}
        >
          <Text style={{ fontSize: 15, fontWeight: '800', color: paper.actionInk }}>보호자 채팅 ›</Text>
        </Pressable>
      </View>

      <ScrollView contentContainerStyle={[pad, { paddingBottom: insets.bottom + 120 }]}>
        {/* the state line — the lab's alert row, coloured by the GO law */}
        <View style={{ flexDirection: 'row', alignItems: 'flex-start', gap: 10, backgroundColor: paper.canvasSoft, padding: 12, borderRadius: 8 }}>
          <View style={{ width: 10, height: 10, borderRadius: 5, backgroundColor: alertTone, marginTop: 5 }} />
          <View style={{ flex: 1 }}>
            <Text style={{ fontSize: 16, fontWeight: '800', color: paper.ink }}>{alertText}</Text>
            {!!alertSub && <Text style={{ fontSize: 15, color: paper.dim, marginTop: 3, lineHeight: 21 }}>{alertSub}</Text>}
          </View>
        </View>

        {/* the two seals — the only thing on this screen that is a claim, and both are server facts */}
        <Text style={{ fontSize: 15, fontWeight: '800', color: paper.dim, letterSpacing: 1, marginTop: 22 }}>
          반환 확인 · {(mine ? 1 : 0) + (theirs ? 1 : 0)}/2
        </Text>
        <View style={{ flexDirection: 'row', gap: 14, justifyContent: 'center', marginTop: 12 }}>
          <Seal label="RUNNER" sub={mine ? '확인 완료' : '나'} on={mine} tone={frame === 'c' ? 'sage' : 'coral'} />
          <Seal label="OWNER" sub={theirs ? '확인 완료' : '확인 대기'} on={theirs} tone="sage" />
        </View>
        {popped && frame === 'c' && (
          <Text style={{ fontSize: 15, fontWeight: '800', color: paper.readyDeep, textAlign: 'center', marginTop: 10 }}>
            방금 양쪽 확인이 맞춰졌어요
          </Text>
        )}
        <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', marginTop: 10, lineHeight: 21 }}>
          {frame === 'c'
            ? (settled ? '정산이 확정됐어요 — 새 요청을 받을 수 있어요' : '양측 확인이 끝났어요 — 정산은 담당자 확인 뒤에 진행돼요')
            : frame === 'b'
              ? '보호자가 찍으면 정산이 확정되고 다음 요청을 받을 수 있어요'
              : '둘 다 찍히면 정산이 확정돼요\n그 전엔 새 요청을 받을 수 없어요'}
        </Text>

        {/* 이번 러닝 — frozen facts only. Every row omits itself when the server has no value;
            none of them is a `?? 0`, because an early-ended run can carry no measurement at all. */}
        <Text style={{ fontSize: 15, fontWeight: '800', color: paper.dim, letterSpacing: 1, marginTop: 26 }}>이번 러닝</Text>
        {[
          ['기록', [kmLabel(s.actualKm), durLabel(s.durationSec)].filter(Boolean).join(' · ') || null],
          ['종료 사유', s.endReason ? END_REASON_LABEL[s.endReason] ?? s.endReason : null],
          ['러닝 종료', hhmm(s.runEndedAt) || null],
        ].filter(([, v]) => !!v).map(([k, v]) => (
          <View key={String(k)} style={{ flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 9, borderBottomWidth: 1, borderBottomColor: '#EEEEEE' }}>
            <Text style={{ fontSize: 15, color: paper.dim }}>{k}</Text>
            <Text style={[nf, { fontSize: 15, lineHeight: 19, fontWeight: '800', color: paper.ink }]}>{v}</Text>
          </View>
        ))}
        {/* NO 적립 예정 ROW. The lab's R6b shows one, and this screen has no honest number to put
            in it: the payout is computed by the server AT SETTLE from the frozen measurement, and
            the client's `estNet` coefficients belong to the live ticker, not to a post-run claim.
            The earnings screen is where the real ledger row lands. */}
        <Text style={{ fontSize: 15, color: paper.dim, marginTop: 14, lineHeight: 21 }}>
          정산 금액은 서버가 실측 기록으로 확정해요 — 수익 화면에서 확인할 수 있어요.
        </Text>

        {frame === 'b' && (
          <Text style={{ fontSize: 15, color: paper.dim, marginTop: 18, lineHeight: 21 }}>
            보호자가 오지 않거나 연락이 안 되면{' '}
            <Text
              style={{ color: paper.ink, fontWeight: '800' }}
              onPress={() => bookingId && router.push(`/incident/${bookingId}`)}
            >
              안심 센터 ›
            </Text>{' '}
            — 운영자가 함께 확인해요
          </Text>
        )}

        {!!actionErr && (
          <View style={{ marginTop: 16, backgroundColor: paper.criticalWash, padding: 12, borderRadius: 6 }}>
            <Text style={{ fontSize: 15, fontWeight: '700', color: paper.critical, lineHeight: 21 }}>{actionErr}</Text>
            <Text style={{ fontSize: 15, color: paper.critical, marginTop: 4, lineHeight: 21 }}>
              다시 시도해도 안전해요 — 같은 확인은 한 번만 기록돼요.
            </Text>
          </View>
        )}
      </ScrollView>

      {/* THE CTA. R6a coral (my turn) · R6b NOTHING (waiting — the lab's 「코랄 0」) · R6c sage. */}
      <View style={[pad, { paddingBottom: insets.bottom + 14, paddingTop: 10, backgroundColor: paper.canvas }]}>
        {frame === 'a' && canStamp && (
          <PaperBtn
            label={`${dog}를 돌려줬어요 — 봉인`}
            busyLabel="확인하는 중..."
            busy={busy}
            disabled={busy}
            onPress={stamp}
          />
        )}
        {frame === 'a' && !canStamp && (
          // No button at all, and a sentence instead — a disabled coral is still a drawn promise.
          <Text style={{ fontSize: 15, color: paper.dim, textAlign: 'center', lineHeight: 21 }}>
            이 예약은 담당자가 확인하고 있어요 — 지금은 인계를 확인할 수 없어요
          </Text>
        )}
        {frame === 'b' && (
          <PaperBtn label="기록 먼저 보기 ›" variant="secondary" onPress={() => router.push('/runner/done')} />
        )}
        {frame === 'c' && (
          <PaperBtn
            label="러닝 기록 보기 ›"
            style={{ backgroundColor: paper.ready }}
            onPress={() => router.replace('/runner/done')}
          />
        )}
      </View>
    </View>
  );
}
