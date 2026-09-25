import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useState } from 'react';
import { Alert, Dimensions, Pressable, ScrollView, StyleSheet, Text, TextStyle, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { PaperBtn } from '../../src/components/paper-btn';
import { HeatTrace } from '../../src/components/runcard';
import { Icon, Row } from '../../src/components/ui';
import { alertFail } from '../../src/lib/alert-fail';
import { DropRow, fetchDrops, fetchLedger, fetchMeetupInfo, fetchMyReturnResolution, fetchReturnSeal, fetchRunPhotos, fetchRunTrace, type ReturnResolution as ReturnResolutionRow, uploadRunPhoto } from '../../src/lib/api';
import { inCustodyPhase, PING_FAIL_LINE } from '../../src/lib/custody-ping-policy';
import { useDisplayFont } from '../../src/lib/displayFont';
import { useNumFont } from '../../src/lib/fonts';
import { kstCal, kstClock } from '../../src/lib/kst';
import { MediaImage } from '../../src/lib/media';
import { withParticle } from '../../src/lib/particle';
import { receiptPhase } from '../../src/lib/receipt-phase';
import { RESOLUTION_KICKER_SHORT, returnResolutionStrip } from '../../src/lib/return-resolution';
import { GeoRoutePoint, traceToBox } from '../../src/lib/trace';
import { useCustodyPing } from '../../src/lib/use-custody-ping';
import { EndReason, runResult } from '../../src/store';
import { colors, layout, paper } from '../../src/theme';

// 러닝 완료 — the completion Peak (§7b Peak-End: exempt from minimization).
//
// [journey v4 · R7a 2026-08-19] The dark 50.5pt volt '오늘의 수익' receipt is RETIRED. It made the
// money the biggest object on the screen that exists to record a RUN, and it printed a client
// estimate at hero size whenever settle had failed. The lab's law: the amount is a plain row, never
// large; what goes large is **km**. So the hierarchy is now trace → display headline ("초코,
// 5.12km 완주") → the run's three numbers (Oswald) → one money row → the honesty sentence.
// The settled/unsettled split survives intact and is the whole point of the row's label: the spec
// word 적립 예정 is spoken only when the server confirmed the number; an unsettled run keeps the
// code's own '예상 수익 (정산 미완료)' verbatim and its explanation is drawn as a loud-fail strip
// (criticalWash + critical ink), because an unsettled run is a real failure with a real next step.
//
// The trace thumbnail is REAL: `runs.trace`, which run.tsx writes with saveRunTrace *before*
// settle (settle_run_tx closes the write window), read back here through fetchRunTrace under the
// "runs party read" policy. Three states — loading / failed / drawn — and nothing at all when
// there is no booking to read. Event counts (응가·물·스냅) the lab also asks for are NOT available
// on this screen: they live in run.tsx's local state and `runResult` (src/store.ts) does not carry
// them. Omitted rather than invented.
//
// Behavior frozen: fetchDrops/addPhoto/uploadRunPhoto, photo cap 6, the dogName re-read, all routes.
//
// [2026-08-24 · Sean] 사진 1장이 **요건**이 됐다 — 앞으로 가는 두 문이 실사진 0장에서 잠긴다.
// 판정 근거·세 상태·왜 '홈으로'는 잠그지 않는지는 아래 사진 넛지 블록(구 photoRequired)의 주석에 있다.
// 사진 자체의 경로(addPhoto/uploadRunPhoto/6장 상한)는 그대로다 — 새 저장소도 새 필드도 없다.
//
// ⚠ [2026-08-25 · Sean] 위 문단의 **잠금은 은퇴했다** (근거는 기록으로 남긴다 — 지우지 않는다).
// 그의 말 그대로 (docs/decisions/awaiting-sean.md §0-undetricies Q2·Q3):
//   "q2: let the runner review, dont trap them from anything, but make sure a huge nudge for photo."
//   "q3: accept a photo less one, but make sure there are screens before the run and during the
//    live run screen that remind the runner for photos."
// 앞으로 가는 두 문은 다시 **무조건** 열린다. 바뀐 것은 오직 **결과**다: 잠금 → 큰 넛지.
// 판정 기계(서버 진실 runs.photos · loading/ready/err 3상태)는 한 글자도 바뀌지 않았다 —
// 로딩은 여전히 0이 아니고, 못 읽은 상태는 여전히 0이라고 주장하지 않는다.
// 사진 경로(addPhoto/uploadRunPhoto/6장 상한)는 처음부터 지금까지 그대로다.

const W = Dimensions.get('window').width;
const TRACE_W = W - layout.gutter * 2;
const TRACE_H = 96;

// M:SS — same grammar as the report card's run numbers (owner/report.tsx fmtDur). The old
// '28분 40초' form was for a caption; inside an Oswald numeral row Korean units break the baseline.
const fmtDur = (sec: number) =>
  `${Math.floor(sec / 60)}:${String(Math.floor(sec % 60)).padStart(2, '0')}`;
// Average pace from the two measured values, using run.tsx's paceStr formula verbatim so the
// last number the runner saw live and the one printed here cannot disagree.
const paceStr = (sec: number, km: number) => {
  if (km < 0.05) return "-'--\"";
  const p = sec / km;
  return `${Math.floor(p / 60)}'${String(Math.round(p % 60)).padStart(2, '0')}"`;
};

// Real dog name — settle put it on runResult from the booking context; if that never loaded, the
// screen re-reads the settled booking once. If the name is genuinely unknown (or the server's own
// generic '반려견' placeholder), the copy names no dog — never a fake one.
// Pure, so it lives at module scope (react-doctor prefer-module-scope-pure-function).
const realName = (n: string | null | undefined) => (n && n !== '반려견' ? n : null);

// ═══ [0193 · codex A7] THE BOOKING-SCOPED RECEIPT ═══════════════════════════════════════════
// `runResult` is run.tsx's in-memory snapshot of the STOP: `settled:false` and a client-side
// payout ESTIMATE, written at the moment the freeze landed (run.tsx:789). Before 0188 that was
// true — the stop settled — and afterwards it is not: settlement happens later, inside the second
// return stamp's transaction. So a runner who completed the whole ceremony and tapped 「러닝 기록
// 보기」 from the seal screen arrived here and was told 「정산이 아직 서버에 반영되지 않았어요 …
// 러닝 화면에서 다시 정산하면」 about a run the server had already settled and paid — a real
// failure face on a successful run, pointing at a door that answers `return_not_sealed`.
// Re-entry was worse: the store still held the PREVIOUS run, so the screen showed another
// booking's numbers under this booking's heading.
//
// The fix is the one codex named: when the screen is opened with a booking id, every number on it
// comes from the server for THAT booking, and nothing is drawn until it does.
//   · measurements + settlement state ← `fetchReturnSeal` (`runs.actual_km` / `duration_sec` /
//     `end_reason`, and `rawStatus === 'completed'` — the same discriminator return-seal.tsx uses,
//     never `sealedAt`, because a sealed row that has not settled is precisely the stranded one)
//   · the money ← the LEDGER row for this booking (`my_ledger_rows`), which is the runner's actual
//     net. `null` when no row exists yet, and null renders as 「—」, never as 0.
// Without a `bid` the screen keeps the in-memory path byte for byte: that is the freeze-failed
// route (run.tsx:860), where the estimate IS the honest thing to show and says so.
type Receipt = {
  km: number | null;
  sec: number | null;
  payout: number | null;
  settled: boolean;
  completed: boolean;
  reason: EndReason;
  /** `bookings.status`, raw. Carried for the 귀가 heartbeat below: this screen is reachable from
   *  the seal screen's frame b (「기록 먼저 보기」) while the dog is STILL WITH THE RUNNER, so it
   *  is a custody screen too and owes the same ping. Never used for the settled claim — that stays
   *  `rawStatus === 'completed'`, computed once above. */
  rawStatus: string | null;
  /** [runner-journey-3] `runner_confirmed_return_at` — the runner's OWN return stamp. In the custody
   *  phase it decides whether the 반환 봉인 door is this runner's turn (coral) or a wait on the
   *  owner (secondary, the return-seal screen's frame b), and it anchors the sentence that replaces
   *  「인계해 주세요」 once the runner has already said they handed the dog back. null on the
   *  store path: no server read, no claim. */
  runnerConfirmedAt: string | null;
};

/** server `runs.end_reason` → this screen's three-word vocabulary. `completed` and `incident` map
 *  to null deliberately: the first is not an early end, and the second has no runner-facing
 *  sentence on this screen (owner/report.tsx owns that one). An unmapped value also returns null —
 *  a screen that does not know why a run ended says nothing rather than guessing. */
const RECEIPT_REASON: Record<string, EndReason> = {
  dog_condition: 'dog',
  owner_request: 'owner',
  owner_forced: 'owner',
  runner_personal: 'runner',
};

export default function RunDone() {
  const insets = useSafeAreaInsets();
  const df = useDisplayFont(); // display font — the run headline (1/screen budget)
  const nf = useNumFont();     // Oswald — the three run numbers + the payout
  // [0193] the booking this receipt is FOR. A param wins over the store: the store is whatever run
  // ended last in this process, which on a re-entry or a cold start is a different booking or none.
  const { bid } = useLocalSearchParams<{ bid?: string }>();
  const paramBid = typeof bid === 'string' && bid ? bid : null;
  const bookingId = paramBid ?? runResult.bookingId;

  // THREE STATES, NEVER TWO (the report screen's law): loading · loaded · failed. `off` is the
  // fourth and it is not a state of the fetch — it means 「no booking id, so there is nothing to
  // load and the in-memory estimate is the honest thing to show」.
  const [receipt, setReceipt] = useState<Receipt | null>(null);
  const [receiptState, setReceiptState] = useState<'off' | 'loading' | 'ready' | 'err'>(paramBid ? 'loading' : 'off');
  const loadReceipt = useCallback(() => {
    if (!paramBid) return;
    setReceiptState('loading');
    Promise.all([fetchReturnSeal(paramBid), fetchLedger().catch(() => null)])
      .then(([seal, ledger]) => {
        if (!seal) { setReceiptState('err'); return; }
        const row = ledger?.find((l) => l.bookingId === paramBid) ?? null;
        setReceipt({
          km: seal.actualKm,
          sec: seal.durationSec,
          // a ledger read that FAILED and a booking with no ledger row are both `null` here, and
          // both render 「—」. Neither is 0, and neither is the client's estimate.
          payout: row ? row.net : null,
          // `rawStatus`, never `sealedAt`: a sealed row that has not settled is the stranded state,
          // and calling it settled is the exact lie return-seal.tsx:223-229 refuses to tell.
          settled: seal.rawStatus === 'completed',
          completed: seal.endReason === 'completed',
          reason: seal.endReason ? (RECEIPT_REASON[seal.endReason] ?? null) : null,
          rawStatus: seal.rawStatus ?? null,
          runnerConfirmedAt: seal.runnerConfirmedAt ?? null,
        });
        setReceiptState('ready');
      })
      .catch((e) => { console.warn('[done] receipt:', (e as Error)?.message); setReceiptState('err'); });
  }, [paramBid]);
  useEffect(() => { loadReceipt(); }, [loadReceipt]);

  // [0199 · client half landed 0200] 운영팀 판정 — a row exists ONLY when `ops_resolve_return_tx`
  // (0193 §A) rescued this booking. It is read for ONE sentence on this screen, and it is the
  // sentence that stops the receipt telling a runner to hand back a dog that is already home.
  // ⚠ ONE state and no error flag, on purpose: `null` means 「ops never touched this run」 OR
  //   「not read yet」, and the two are not separated because a resolution is ADDITIVE information
  //   rather than a gate — the overwhelmingly common case is the first, and a failure strip on
  //   every healthy receipt is noise that trains people to ignore strips. A failed read logs and
  //   draws nothing; the receipt's own three states still own the 「I could not read this」 face.
  // ⚠ Keyed on `bookingId`, not `paramBid`: this sentence replaces the 인계 line, which is drawn
  //   from the store-only path too (a receipt reached straight off the stop).
  const [resolution, setResolution] = useState<ReturnResolutionRow | null>(null);
  useEffect(() => {
    if (!bookingId) return;
    fetchMyReturnResolution(bookingId)
      .then(setResolution)
      .catch((e) => console.warn('[done] resolution:', (e as Error)?.message));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // [0193] …and the NAME is part of the same defect. `runResult.dogName` belongs to whatever run
  // ended last in this process, so on a receipt opened for a DIFFERENT booking it is another dog's
  // name printed in this dog's headline. When the param names a booking the store does not, the
  // store's name is not evidence about it and the screen reads the booking instead.
  const storeName = paramBid && paramBid !== runResult.bookingId ? null : realName(runResult.dogName);
  const [dogName, setDogName] = useState<string | null>(storeName);
  useEffect(() => {
    if (!storeName && bookingId) {
      fetchMeetupInfo(bookingId)
        .then((i) => setDogName(realName(i.dogName)))
        .catch((e) => console.warn('[done] dogName:', (e as Error)?.message)); // unknown → generic wording stays
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // 실측 경로 — runs.trace. Three states, and none of them is a drawn placeholder: a failed read
  // says it failed, an in-flight read says so, and a run with no stored points draws no plate.
  const [trace, setTrace] = useState<GeoRoutePoint[] | null>(null);
  const [traceErr, setTraceErr] = useState(false);
  const [traceLoading, setTraceLoading] = useState(!!bookingId);
  useEffect(() => {
    // [0193] the RECEIPT's booking, not the store's — on a re-entry the store holds a different
    // run and this plate drew that run's route under this run's heading.
    if (!bookingId) return;
    fetchRunTrace(bookingId)
      .then(setTrace)
      .catch((e) => { setTraceErr(true); console.warn('[done] trace:', (e as Error)?.message); })
      .finally(() => setTraceLoading(false));
  }, []);
  const traceBox = trace ? traceToBox(trace) : [];

  // 실드랍 — settle-run이 굴린 결과를 DB에서 읽는다 (목업 215회 은퇴, fake-inventory)
  const [pendingDrop, setPendingDrop] = useState<DropRow | null>(null);
  useEffect(() => {
    fetchDrops().then((ds) => setPendingDrop(ds.find((d) => !d.openedAt) ?? null)).catch(() => {});
  }, []);
  // 오늘의 순간 — [honesty 2026-08-19 · runner review P2] `photos`는 업로드 응답으로만 채워졌고
  // 마운트에서 서버를 읽은 적이 없었다. 그런데 run.tsx:185가 **같은 booking**에 같은 uploadRunPhoto로
  // 올린다(서버 원자 append) — 러닝 중 4장을 찍고 온 러너는 이 화면에서 썸네일 0개를 보고,
  // '6장까지' 캡도 0부터 다시 셌다. 마운트에서 실제 배열을 읽고 3상태로 그린다:
  // 로딩은 로딩이라 말하고, 실패는 재시도를 주고, 개수에 의존하는 분기는 실사진만 센다.
  const [photos, setPhotos] = useState<string[]>([]);
  const [photoState, setPhotoState] = useState<'loading' | 'ready' | 'err'>(bookingId ? 'loading' : 'ready');
  const loadPhotos = useCallback(() => {
    if (!bookingId) return;
    setPhotoState('loading');
    fetchRunPhotos(bookingId)
      .then((p) => { setPhotos(p); setPhotoState('ready'); })
      .catch((e) => { console.warn('[done] photos:', (e as Error)?.message); setPhotoState('err'); });
  }, []);
  useEffect(() => { loadPhotos(); }, [loadPhotos]);
  const [uploading, setUploading] = useState(false);

  // 오늘의 순간 — 러닝 사진이 보호자 리포트(공유 페이지)에 실린다
  const addPhoto = async () => {
    if (!bookingId) return;
    let ImagePicker: any;
    try { ImagePicker = require('expo-image-picker'); } catch {
      Alert.alert('개발 빌드 업데이트 필요', '사진 기능은 새 빌드에 포함돼요'); return;
    }
    try {
      const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
      if (!perm.granted) { Alert.alert('사진 접근 권한이 필요해요'); return; }
      const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 0.7, base64: true });
      if (res.canceled || !res.assets?.[0]?.base64) return;
      setUploading(true);
      // 서버가 append 후 최신 배열 전체를 돌려준다 — 읽기가 실패했던 경우도 여기서 정합된다
      const next = await uploadRunPhoto(bookingId, res.assets[0].base64);
      setPhotos(next);
      setPhotoState('ready');
    } catch (e) {
      alertFail('업로드 실패', e);
    } finally {
      setUploading(false);
    }
  };

  // ── 사진 넛지 (Sean 2026-08-25 — 2026-08-24 요건의 후속) ──
  //
  // [SUPERSEDED 2026-08-24, 근거로 보존] 이 자리는 **게이트**였다. 그때의 말 그대로:
  //   "For the runner done screen (C), make sure there's a mandatory nudge for pictures (make that
  //    a requirement and nudge them during the runner live screen so they don't forget."
  //   → 앞으로 가는 두 문(리뷰·다음 요청)이 실사진 0장에서 disabledFill로 잠겼고, '홈으로'만 열려 있었다.
  //
  // [2026-08-25, 지금 유효] 그가 직접 뒤집었다 (§0-undetricies Q2·Q3, verbatim):
  //   "q2: let the runner review, dont trap them from anything, but make sure a huge nudge for photo."
  //   "q3: accept a photo less one, but make sure there are screens before the run and during the
  //    live run screen that remind the runner for photos."
  // 그래서 **결과만** 바뀐다: 잠금 → 넛지. 판정 기계는 그대로 남는다. 근거는 여전히 **실사진**이고
  // (서버가 돌려준 runs.photos 배열의 길이 하나 — 업로드 응답과 마운트 읽기가 같은 배열이다),
  // 세 상태도 그대로다:
  //   · ready & 0장  → 큰 넛지를 그린다. **부탁이지 잠금이 아니다** (두 문은 열려 있다).
  //   · loading      → 아직 0인지 모른다 → 아무 말도 하지 않는다 (로딩 ≠ 0. 이미 네 장 찍고 온
  //                    러너에게 '사진이 없어요'라고 말하는 순간 그건 거짓말이다).
  //   · err          → 0이라고 **주장할 수 없다** → 넛지 없음. 섹션 헤더의 '다시 시도'가 진짜 경로다.
  // 예약이 없으면 업로드 경로 자체가 없다 → 부탁할 것도 없다.
  //
  // 서버는 예나 지금이나 사진 없이 끝난 러닝을 정산한다 — Q3이 그걸 **의도**로 확정했다(서버 강제 없음).
  // 잊지 않게 만드는 일은 이제 세 화면이 나눠 진다: meetup(러닝 전) · run(라이브) · 이 화면(완료).
  const photoAskable = !!bookingId;
  const photoMissing = photoAskable && photoState === 'ready' && photos.length === 0;

  // [0193] ONE source for every number on this screen, chosen ONCE. With a `bid` it is the
  // server's answer for that booking; without one it is run.tsx's in-memory snapshot, which is
  // exactly the freeze-failed route where the estimate is the honest thing to show.
  const v: Receipt = receipt ?? {
    km: runResult.km, sec: runResult.sec, payout: runResult.payout,
    settled: runResult.settled, completed: runResult.completed, reason: runResult.reason,
    // No server read ⇒ no claim about the booking's state, so no heartbeat either. A null here
    // cannot pass `inCustodyPhase`, which is exactly right: the in-memory path is the
    // freeze-FAILED route (run.tsx:860), where there may be no custody at all.
    rawStatus: null,
    runnerConfirmedAt: null,
  };

  // ═══ [runner-journey-3] WHICH MOMENT THIS RECEIPT IS FOR ═══════════════════════════════════
  // One face used to serve four moments: 「인계해 주세요」 on a SETTLED run whose dog was long home,
  // 「러닝 화면에서 다시 정산하면」 during the return ceremony (where the run screen is not the door —
  // `settle_run_tx` answers `return_not_sealed` — and the seal screen is), and a coral 「다음 요청
  // 보기」 while the work gate (0092) holds the runner off new requests. receipt-phase.ts decides the
  // moment once; the sentence, the fail strip and the exits below all read that one answer.
  const phase = receiptPhase({ paramBid, settled: v.settled, rawStatus: v.rawStatus });
  // The runner's own return stamp as a KST clock (kst.ts — never the device clock). '' when absent
  // or unparseable, and an empty clock is never printed: the sentence falls back to one with no time.
  const stampedAt = (() => {
    const ms = v.runnerConfirmedAt ? Date.parse(v.runnerConfirmedAt) : NaN;
    return Number.isNaN(ms) ? '' : kstClock(kstCal(ms));
  })();
  const runnerStamped = !!v.runnerConfirmedAt;

  // ═══ [0083 §5] THE 귀가 HEARTBEAT, second site ═════════════════════════════════════════════
  // `return-seal.tsx` frame b draws 「기록 먼저 보기 ›」 into this screen (return-seal.tsx:377) —
  // the runner's own stamp is in, the owner's is not, and the dog is still with the runner. So
  // this is a custody screen and the owner's homeward LA is reading a column nobody writes while
  // it is open. One hook, shared with the seal screen, so the two cannot drift apart.
  //
  // ⚠ This screen reads its status ONCE and never polls. That is safe because the SERVER closes
  // the loop, not this gate: `custody_ping` answers a booking that has left custody with
  // `not_in_custody`, which `custody-ping-policy.ts` treats as permanent and stops on.
  const ping = useCustodyPing(paramBid, inCustodyPhase(v.rawStatus));
  const km = v.km;
  const sec = v.sec;
  // '완주' is a claim — spoken only when the server-recorded end was a completed run, exactly as
  // owner/report.tsx gates the same word on run.endReason.
  const dist = km == null ? null : km.toFixed(2);
  const headline = dist == null
    ? (dogName ?? '오늘의 러닝')
    : dogName
      ? `${dogName}, ${dist}km${v.completed ? ' 완주' : ''}`
      : `${dist}km${v.completed ? ' 완주' : ''}`;

  // THE RECEIPT IS NOT DRAWN FROM A GUESS. While the server read is in flight the screen says so;
  // if it failed it says that and offers the retry. Rendering `runResult` here instead would print
  // the stop's estimate under this booking's heading — codex A7's exact defect wearing a
  // loading-state costume.
  if (receiptState === 'loading' || receiptState === 'err') {
    const failed = receiptState === 'err';
    return (
      <View style={{ flex: 1, backgroundColor: paper.canvas, paddingTop: insets.top + 16, paddingHorizontal: layout.gutter }}>
        <Text style={[s.headline, df, { marginTop: 24 }]}>
          {failed ? '기록을 불러오지 못했어요' : '기록을 불러오는 중이에요'}
        </Text>
        <Text style={s.sub}>
          {failed
            ? '연결을 확인하고 다시 시도해주세요 — 러닝 기록과 정산은 서버에 그대로 있어요.'
            : '서버에서 이 러닝의 실측·정산 상태를 확인하고 있어요.'}
        </Text>
        {failed && <PaperBtn label="다시 시도" onPress={loadReceipt} style={{ marginTop: 20 }} />}
        {/* [runner-journey-8] the ready face's quiet 홈으로, on this face too. The receipt is opened
            from pushes, the seal screen and the calendar; a read that hangs or fails used to leave
            only 다시 시도 on screen, and this screen has no ‹ of its own. */}
        <PaperBtn label="홈으로" variant="quiet" style={{ marginTop: failed ? 8 : 20 }} onPress={() => router.dismissTo('/runner/home')} />
      </View>
    );
  }

  return (
    <ScrollView
      style={{ flex: 1, backgroundColor: paper.canvas }}
      contentContainerStyle={{ paddingHorizontal: layout.gutter, paddingTop: insets.top + 14, paddingBottom: 40 }}
    >
      {/* ══════ ① 실측 경로 — dark plate (HeatTrace is built for a dark face) ══════ */}
      {traceLoading && (
        <View style={s.tracePlate}>
          <Text style={s.traceNote}>경로 불러오는 중…</Text>
        </View>
      )}
      {!traceLoading && traceErr && (
        <View style={s.tracePlate}>
          <Text style={s.traceNote}>경로를 불러오지 못했어요 — 기록 자체는 저장돼 있어요</Text>
        </View>
      )}
      {!traceLoading && !traceErr && traceBox.length > 1 && (
        <View style={s.tracePlate}>
          <HeatTrace points={traceBox} width={TRACE_W} height={TRACE_H} tint={colors.volt} />
          <Text style={s.traceCap}>내 실측 경로</Text>
        </View>
      )}

      {/* ══════ ② 헤드라인 + ③ 숫자 셋 (14a 문법) ══════ */}
      <Text style={[s.headline, df]}>{headline}</Text>
      {/* R6 (반환 봉인) does not exist on the client — this sentence is the only place the app
          tells the runner to hand the dog back. It stays until that server slice ships.
          ══════ [0199/0200] …EXCEPT WHEN 운영팀 ALREADY CLOSED THE RETURN ══════
          🔴 NEVER BOTH. `ops_resolve_return_tx` (0193 §A) ends a stranded return by sealing and
          settling, so the dog is home and the handoff is over — and this line would still be
          asking the runner to perform it. The strip replaces it with what actually happened: the
          SERVER's fixed sentence (`note_public`, 0199 §0b — never the operator's memo, never the
          raw `rescuedFrom` word) and the KST instant of the decision. A missing date costs the
          DATE and never the sentence; no resolution, no strip, and the 인계 line is untouched. */}
      {(() => {
        const strip = returnResolutionStrip(resolution);
        if (!strip) {
          // [runner-journey-3] per phase. The 인계 sentence survives in exactly the two moments it
          // is true: custody before the runner's own stamp, and the estimate (freeze-failed) path.
          // Vocabulary is borrowed, not coined: 「정산이 확정됐어요」 is return-seal.tsx's sentence for
          // the same `completed` fact (「끝났어요」 would read as paid, and calendar.tsx C③ retired
          // 정산 완료 for exactly that — nothing pays a runner yet), and 「담당자가 확인하고 있어요」 is
          // return-seal's and runner/home's word for the same held booking.
          if (phase === 'settled') {
            return (
              <Row style={{ gap: 10, alignItems: 'baseline', flexWrap: 'wrap' }}>
                <Text style={s.sub}>정산이 확정됐어요</Text>
                <Pressable
                  onPress={() => router.push('/runner/earnings')}
                  hitSlop={8}
                  accessibilityRole="button"
                  accessibilityLabel="수익 화면 보기"
                >
                  <Text style={s.subLink}>수익 보기 ›</Text>
                </Pressable>
              </Row>
            );
          }
          if (phase === 'pending') {
            return <Text style={s.sub}>담당자가 확인하고 있어요</Text>;
          }
          if (phase === 'custody' && runnerStamped) {
            return (
              <Text style={s.sub}>
                {stampedAt ? `${stampedAt}에 반환 확인을 보냈어요 · 보호자 확인을 기다리고 있어요` : '반환 확인을 보냈어요 · 보호자 확인을 기다리고 있어요'}
              </Text>
            );
          }
          return (
            <Text style={s.sub}>
              {/* [copy-hierarchy-1] the particle follows the name (particle.ts) — 「콩을」, not 「콩를」 */}
              {`${withParticle(dogName ?? '반려견', '를/을')} 보호자에게 안전하게 인계해주세요`}
            </Text>
          );
        }
        return (
          <View style={s.resolutionStrip}>
            <Text style={s.resolutionKicker}>{RESOLUTION_KICKER_SHORT}</Text>
            <Text style={s.resolutionText}>{strip.text}</Text>
            {!!strip.when && <Text style={s.resolutionWhen}>{strip.when}</Text>}
          </View>
        );
      })()}
      {/* [0083 §5] The heartbeat's only runner-facing consequence — three consecutive misses, and
          it clears on the next success. It sits under the 인계 sentence because that sentence is
          the custody claim this strip qualifies. Quiet, not criticalWash: nothing the runner did
          has failed, and no door on this screen is affected. */}
      {ping.failing && (
        <View style={s.pingStrip}>
          <Text style={s.pingTitle}>{PING_FAIL_LINE}</Text>
          <Text style={s.pingBody}>보호자 화면에 위치가 오래된 것으로 보일 수 있어요 — 연결이 돌아오면 저절로 맞춰져요.</Text>
        </View>
      )}
      <Row style={{ gap: 22, marginTop: 14, alignItems: 'flex-start' }}>
        {/* [0193] null is a real answer and stays one — an early-ended run can carry no
            measurement at all, and `?? 0` here is what drew 「0km 완주」 on the report card. */}
        <DoneStat nf={nf} value={dist ?? '—'} unit="km" label="거리" />
        <DoneStat nf={nf} value={sec == null ? '—' : fmtDur(sec)} label="러닝 시간" />
        <DoneStat nf={nf} value={sec == null || km == null ? "-'--\"" : paceStr(sec, km)} label="평균 페이스 /km" />
      </Row>

      {/* ══════ ④ 돈 — 한 줄. 절대 히어로가 아니다 ══════
          [2026-08-11, kept] 정산 성공 여부가 이 낱말을 정한다. 서버가 확정한 금액만 '적립'이고,
          정산이 실패해 러너가 '나중에 (추정치 표시)'를 고른 경우는 클라이언트 추정치다 —
          그걸 확정된 돈이라 부르는 순간 앱이 못 지킬 돈을 약속한 것이 된다. */}
      <View style={s.rule} />
      <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
        <Text style={s.moneyLabel}>{v.settled ? '적립 예정' : '예상 수익 (정산 미완료)'}</Text>
        <Row style={{ alignItems: 'baseline' }}>
          {/* Oswald — [BUG A] lineHeight 24 = 1.26× */}
          <Text style={[s.moneyNum, nf]}>{v.payout == null ? '—' : v.payout.toLocaleString()}</Text>
          <Text style={s.moneyUnit}>원</Text>
        </Row>
      </Row>
      {/* [2026-08-11, kept] '수익은 매주 수요일 정산됩니다'는 존재하지 않는 지급 운영이었다.
          기록은 진짜다(ledger_items). 지급 일정은 진짜가 아니었다. 아는 것만 말한다.
          [copy-hierarchy-4, 2026-09-25] …and the 「payout schedule comes after payment integration」
          tail is gone too: since 0192 a ledger row can be PAID, and earnings prints 지급 완료 for it
          (payout-status.ts). This screen reads no payout field, so it says nothing about payment
          timing at all; the earnings screen is where that fact is drawn. */}
      <Text style={s.moneyNote}>
        {v.settled
          ? '정산 기록이 저장됐어요 — 수익 화면에서 누적을 볼 수 있어요'
          : '정산이 확정되면 수익 화면에 반영돼요'}
      </Text>

      {/* 정산 미완료 = 진짜 실패. 라우드-페일 스트립 문법(criticalWash + critical) — 이 화면의
          앰버 장식이 아니라 earnings.tsx가 이미 쓰는 실패의 얼굴이다. 재시도 문은 러닝
          화면에 있고(여기엔 없다), 문장이 그 경로를 가리킨다 — 죽은 버튼을 만들지 않는다. */}
      {/* [runner-journey-3] ONLY in 'estimate'. With a booking param the run was frozen server-side,
          and the run screen is not a settle door any more (0188): the custody phase's door is the
          seal screen below, and the pending phase has no door the runner can press at all. */}
      {phase === 'estimate' && !v.settled && (
        <View style={s.failStrip}>
          <Text style={s.failText}>
            정산이 아직 서버에 반영되지 않았어요 — 이 숫자는 앱이 계산한 추정치예요.{'\n'}
            예약은 진행 중으로 남아 있어요. 러닝 화면에서 다시 정산하면 실제 금액으로 확정돼요.
          </Text>
        </View>
      )}

      {/* 조기 종료 사유 — 사실이지 경고가 아니다. 문장은 그대로, 색만 읽는 잉크로. */}
      {!v.completed && (
        <Text style={s.reasonLine}>
          {v.reason === 'dog' && '컨디션 종료 — 실제 거리 정산 · 완주율 무영향\n상태 사진과 메모가 보호자에게 전달돼요'}
          {v.reason === 'owner' && '보호자 요청 종료 — 실제 거리 + 잔여 거리 50% 보장 포함'}
          {v.reason === 'runner' && '개인 사유 종료 — 실제 거리 정산 · 완주율에 반영돼요'}
          {!v.reason && '조기 종료 — 실제 뛴 거리만큼 정산돼요'}
        </Text>
      )}

      {/* ══════ ⑤ 오늘의 순간 — 사진이 보호자의 러닝 리포트에 실려요 (실예약만) ══════ */}
      {bookingId && (
        <>
          <View style={s.rule} />
          <Row style={{ justifyContent: 'space-between', alignItems: 'baseline' }}>
            <Text style={s.secTitle}>오늘의 순간</Text>
            {photoState === 'loading' ? (
              /* 개수를 모르는 동안에는 개수에 달린 문(추가/상한)을 그리지 않는다 */
              <Text style={s.secQuiet}>사진 불러오는 중…</Text>
            ) : photoState === 'err' ? (
              <Pressable onPress={loadPhotos} hitSlop={8} accessibilityRole="button" accessibilityLabel="사진 다시 불러오기">
                <Text style={s.secFail}>불러오지 못했어요 · 다시 시도</Text>
              </Pressable>
            ) : photos.length < 6 ? (
              <Pressable
                onPress={addPhoto}
                disabled={uploading}
                hitSlop={8}
                accessibilityRole="button"
                accessibilityLabel="사진 추가"
                accessibilityState={{ disabled: uploading, busy: uploading }}
              >
                <Text style={[s.secAction, uploading && { color: paper.dim }]}>
                  {uploading ? '올리는 중…' : '사진 추가 ›'}
                </Text>
              </Pressable>
            ) : (
              /* 상한에 닿으면 문을 남기지 않는다 — 눌러도 아무 일 없는 버튼 대신 사실 한 줄 */
              <Text style={s.secQuiet}>6장까지</Text>
            )}
          </Row>
          {/* 부탁은 개수를 **아는** 상태에서만 말한다 — 로딩·실패 중에 말하면 이미 찍은 러너에게도
              같은 문장이 뜬다. [2026-08-25] '필수예요'는 더 이상 참이 아니다(잠그지 않으므로):
              요건을 주장하지 않고, 무게만 남긴다 (700 잉크). */}
          <Text style={photoMissing ? s.secRequired : s.secQuiet}>
            {photoMissing ? '아직 한 장도 없어요 · 사진은 보호자 리포트에 실려요' : '보호자 리포트에 실려요'}
          </Text>
          {photos.length > 0 && (
            <Row style={{ gap: 6, marginTop: 10, flexWrap: 'wrap' }}>
              {photos.map((url) => (
                /* [0064] uploadRunPhoto가 media 경로를 돌려준다 — 서명 URL로 렌더 */
                <MediaImage key={url} source={url} style={{ width: 64, height: 64, borderRadius: 0, backgroundColor: '#EEEEEE' }} />
              ))}
            </Row>
          )}
        </>
      )}

      {/* ══════ ⑥ 실드랍 — 미오픈 드랍이 있을 때만, 오픈은 리워드 센터에서 ══════
          Ink+volt ceremony face stays (drop = milestone artifact; dark is the artifact). */}
      {pendingDrop && (
        <Pressable
          onPress={() => router.push('/runner/rewards')}
          style={({ pressed }) => [s.dropBanner, pressed && { transform: [{ scale: 0.96 }] }]}
          accessibilityRole="button"
          accessibilityLabel={`${pendingDrop.runCountAt}회 달성 드랍 — 리워드 센터에서 열기`}
        >
          <Icon name={pendingDrop.kind === 'pick' ? 'Gift' : 'Package'} glyph="●" size={24} color={colors.volt} />
          <Text style={{ fontSize: 16, fontWeight: '800', color: colors.volt, marginTop: 5 }}>
            {pendingDrop.runCountAt}회 달성 — {pendingDrop.kind === 'pick' ? '픽 드랍' : '보급 상자'} 도착!
          </Text>
          <Text style={{ fontSize: 15, color: '#BBBBBB', marginTop: 3 }}>리워드 센터에서 열기 ›</Text>
        </Pressable>
      )}

      {/* ══════ ⑦ 사진 넛지 — 문 **위**에 선다 (Sean 2026-08-25: "a huge nudge for photo") ══════
          큰 것은 면적·활자·자리이고, 코랄 **면**은 아니다: 이 화면의 프라이머리는 아래 '다음 요청
          보기' 하나뿐이라(프레임당 채도 1) 넛지는 세컨더리 문법을 쓴다 — wash 면 + 코랄 헤어라인 +
          actionInk 잉크. 블록 전체가 진짜 경로다(탭 = addPhoto, 위 섹션의 '사진 추가'와 같은 함수):
          말만 하고 러너를 위로 스크롤시키는 안내판은 죽은 버튼과 같은 얼굴이다.
          ready & 0장에서만 뜬다 — 로딩·실패·이미 찍은 러너에게는 존재하지 않는다. */}
      {photoMissing && (
        <Pressable
          onPress={addPhoto}
          disabled={uploading}
          accessibilityRole="button"
          accessibilityLabel="사진 추가 — 보호자 리포트에 실려요"
          accessibilityState={{ disabled: uploading, busy: uploading }}
          style={({ pressed }) => [s.nudge, pressed && !uploading && { backgroundColor: paper.canvas }]}
        >
          <Row style={{ gap: 9, alignItems: 'center' }}>
            <Icon name="Camera" glyph="◉" size={21} color={paper.actionInk} />
            <Text style={s.nudgeTitle}>사진 한 장만 남겨주세요</Text>
          </Row>
          <Text style={s.nudgeBody}>
            {dogName
              ? `보호자가 오늘 가장 기다리는 건 ${dogName}의 사진이에요 — 한 장이면 충분해요.`
              : '보호자가 오늘 가장 기다리는 건 사진이에요 — 한 장이면 충분해요.'}
          </Text>
          <Text style={s.nudgeAction}>{uploading ? '올리는 중…' : '사진 추가하기 ›'}</Text>
        </Pressable>
      )}

      {/* ══════ ⑧ 출구 — 코랄은 '다음 요청 보기' 하나 (프레임당 채도 1) ══════
          리뷰는 runResult.bookingId를 읽어 쓰므로, 예약이 없으면 그 화면은 제출할 수 없다 —
          문 자체를 그리지 않는다 (죽은 버튼 금지). 홈은 조용한 출구로 남는다.
          [2026-08-24 · SUPERSEDED] 두 문이 사진 요건(≥1장)을 졌고, 리뷰까지 잠근 이유는 리뷰 제출이
          dismissTo('/runner/home')로 이 러닝을 떠나기 때문이었다(열어 두면 한 탭짜리 우회로).
          [2026-08-25 · Sean, 지금 유효] "let the runner review, dont trap them from anything" —
          두 문 다 **무조건** 열린다. 우회로 걱정은 그가 값을 치르기로 한 쪽이고(Q3: 사진 없는 러닝도
          받는다), 리뷰는 재예약 지표에 가장 가까운 입력이라 마찰을 얹을 자리가 아니었다. */}
      {/* 🔴 THE BOOKING ID RIDES THE ROUTE, and the bare path was the defect — the same class
          0193 A4 closed for `/runner/done` and `/runner/return-seal`, left open on this one door.
          `runner/review.tsx` resolved its booking from `runResult.bookingId` alone, so (a) a
          runner who left this screen could never review that run again, there being no other
          door, and (b) a STALE store filed the review against the WRONG booking — the insert
          writes `booking_id: bookingId` verbatim, so yesterday's run collects today's stars.
          With a param the review screen names the run it is actually reviewing. */}
      {/* [runner-journey-3] The custody phase's real next step, and it comes FIRST. Coral only while
          it is this runner's turn (their own stamp is not in — return-seal frame a); once they have
          stamped it is a wait on the owner and the door drops to secondary (frame b's 「코랄 0」). */}
      {phase === 'custody' && paramBid && (
        <PaperBtn
          label={runnerStamped ? '반환 확인 상태 보기 ›' : '반환 봉인하러 가기 ›'}
          variant={runnerStamped ? 'secondary' : 'primary'}
          style={{ marginTop: photoMissing ? 14 : 22 }}
          onPress={() => router.push({ pathname: '/runner/return-seal', params: { bid: paramBid } })}
        />
      )}
      {bookingId && (
        <PaperBtn
          label={dogName ? `${dogName} 후기 남기기 ›` : '반려견 후기 남기기 ›'}
          variant="secondary"
          style={{ marginTop: phase === 'custody' ? 8 : photoMissing ? 14 : 22 }}
          onPress={() => router.push({ pathname: '/runner/review', params: { bid: bookingId } })}
        />
      )}
      {/* [runner-journey-3] 「다음 요청 보기」 is a promise that a request can be taken, and in custody
          and pending the work gate (0092) says it cannot. Those two phases keep only the quiet
          홈으로 below — no coral, and no door onto a refusal. */}
      {(phase === 'settled' || phase === 'estimate') && (
        <PaperBtn
          label="다음 요청 보기 ›"
          style={{ marginTop: bookingId ? 8 : photoMissing ? 14 : 22 }}
          onPress={() => router.replace('/runner/requests')}
        />
      )}
      <PaperBtn label="홈으로" variant="quiet" style={{ marginTop: 8 }} onPress={() => router.dismissTo('/runner/home')} />
    </ScrollView>
  );
}

// 숫자 셋 (14a) — Oswald via nf. [BUG A] lineHeight must be explicit or the ascenders clip.
// The unit rides inside the value line so '5.12' and 'km' share one baseline; the label under it
// holds the 14pt detail floor (it is not a letterspaced kicker, so it gets no exemption).
function DoneStat({ nf, value, unit, label }: { nf: TextStyle | null; value: string; unit?: string; label: string }) {
  return (
    <View>
      <Text style={[s.statValue, nf]}>
        {value}{unit ? <Text style={s.statUnit}>{unit}</Text> : null}
      </Text>
      <Text style={s.statLabel}>{label}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  // ---------- ① 트레이스 플레이트 ----------
  tracePlate: { backgroundColor: paper.ink, height: TRACE_H, marginBottom: 12, justifyContent: 'center' },
  traceNote: { fontSize: 15, lineHeight: 19, color: '#BBBBBB', paddingHorizontal: 12 },
  traceCap: { position: 'absolute', right: 10, bottom: 8, fontSize: 15, lineHeight: 18, color: '#999999' },
  // ---------- ② 헤드라인 ----------
  // Black Han Sans — [BUG A] lineHeight 34 = 1.24× (DESIGN §3); it wraps on a long dog name
  headline: { fontSize: 27.5, lineHeight: 34, fontWeight: '900', color: paper.ink },
  sub: { fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 6 },
  // [runner-journey-3] the settled sentence's 수익 door — the section-header action grammar (secAction)
  subLink: { fontSize: 15, lineHeight: 19, fontWeight: '800', color: paper.actionInk, marginTop: 6 },
  // ---------- ③ 숫자 셋 — owner/report.tsx와 같은 문법 ----------
  statValue: { fontSize: 27, lineHeight: 33, fontWeight: '900', color: paper.ink }, // [BUG A] 27 × 1.22
  statUnit: { fontSize: 15, lineHeight: 33, fontWeight: '800', color: paper.dim },
  statLabel: { fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 1 },
  // 섹션 분할 = 풀블리드 솔리드 코랄 1px — 이 선이 곧 브랜드 (§2 종이 법)
  rule: { marginHorizontal: -layout.gutter, height: 1, backgroundColor: paper.line, marginTop: 18, marginBottom: 14 },
  // ---------- ④ 돈 한 줄 ----------
  moneyLabel: { fontSize: 16, lineHeight: 21, fontWeight: '700', color: paper.text },
  moneyNum: { fontSize: 19, lineHeight: 24, fontWeight: '900', color: paper.ink, fontVariant: ['tabular-nums'] as const }, // [BUG A] 19 × 1.26
  moneyUnit: { fontSize: 15, lineHeight: 24, fontWeight: '800', color: paper.ink },
  moneyNote: { fontSize: 15, lineHeight: 19, color: paper.dim, marginTop: 6 },
  // [0199/0200] 운영팀 판정 — a FACT, not a failure, so the quiet secondary grammar (hairline box)
  // rather than criticalWash. It stands where the 인계 sentence was, directly under the headline.
  resolutionStrip: { borderWidth: 1, borderColor: paper.line, padding: 13, marginTop: 10 },
  resolutionKicker: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.dim, letterSpacing: 1 },
  resolutionText: { fontSize: 17, lineHeight: 23, fontWeight: '900', color: paper.ink, marginTop: 5 },
  resolutionWhen: { fontSize: 15, lineHeight: 20, color: paper.dim, marginTop: 3 },
  // [0083 §5] 귀가 하트비트 스트립 — 실패가 아니라 사실 한 줄이라 wash + 헤어라인 (세컨더리 문법)
  pingStrip: { backgroundColor: paper.wash, borderWidth: 1, borderColor: paper.line, padding: 13, marginTop: 12 },
  pingTitle: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.ink },
  pingBody: { fontSize: 15, lineHeight: 20, color: paper.dim, marginTop: 4 },
  // 라우드-페일 스트립 — earnings.tsx/community.tsx와 같은 문법 (criticalWash + critical ink)
  failStrip: { backgroundColor: paper.criticalWash, padding: 13, marginTop: 12 },
  failText: { fontSize: 15, lineHeight: 19.5, fontWeight: '700', color: paper.critical },
  reasonLine: { fontSize: 15, lineHeight: 20, color: paper.text, marginTop: 12 },
  // ---------- ⑤ 섹션 헤더 ----------
  // §3b 섹션 헤더는 앱 전체에서 하나의 문법: 20/800 잉크
  secTitle: { fontSize: 20, lineHeight: 25, fontWeight: '800', color: paper.ink },
  secAction: { fontSize: 15, lineHeight: 19, fontWeight: '800', color: paper.actionInk },
  secQuiet: { fontSize: 15, lineHeight: 19, color: paper.dim },
  // 사진 부탁 한 줄 — 실패가 아니라 **부탁**이라 critical이 아니고, 그냥 사실보다는 무겁게 (텍스트 잉크 700)
  secRequired: { fontSize: 15, lineHeight: 19, fontWeight: '700', color: paper.text },
  // ---------- ⑦ 사진 넛지 (2026-08-25) ----------
  // 세컨더리 문법 그대로(wash 면 + 코랄 1px + actionInk) — 새 헥스 0개, 코랄 **면** 0개.
  // '거대함'은 색이 아니라 면적과 활자로 만든다: 문 바로 위 22pt 여백 + 18pt 패딩 + 21/900 제목.
  // (gateHint는 은퇴 — 잠긴 문이 없어졌으므로 그 이유 줄도 없다.)
  nudge: {
    backgroundColor: paper.wash, borderWidth: 1, borderColor: paper.line,
    paddingVertical: 18, paddingHorizontal: 16, marginTop: 22,
  },
  nudgeTitle: { fontSize: 21, lineHeight: 27, fontWeight: '900', color: paper.ink },
  nudgeBody: { fontSize: 15, lineHeight: 20, color: paper.text, marginTop: 7 },
  nudgeAction: { fontSize: 15, lineHeight: 20, fontWeight: '800', color: paper.actionInk, marginTop: 11 },
  // 섹션 헤더 자리의 실패 + 재시도 — 라우드-페일 잉크, 밑줄 (스트립을 세우기엔 한 줄짜리 사실)
  secFail: { fontSize: 15, lineHeight: 19, fontWeight: '800', color: paper.critical, textDecorationLine: 'underline' },
  // ---------- ⑥ 드랍 ----------
  dropBanner: {
    marginTop: 18, padding: 18, alignItems: 'center',
    backgroundColor: paper.ink, borderWidth: 1.5, borderColor: colors.volt,
  },
});
