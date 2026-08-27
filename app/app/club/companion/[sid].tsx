import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { fetchClubSession, type ClubSessionDetail } from '../../../src/lib/api';
import { useNumFont } from '../../../src/lib/fonts';
import { getTraceSnapshot, resetTrace, startTracking, type TrackHandle, type TrackMode } from '../../../src/lib/geo';
import { paper } from '../../../src/theme';

// 동반 러닝 화면 — an owner walking their OWN dog on a club walk.
//
// WHY THIS FILE EXISTS. Sean, 2026-08-26, verbatim: 「why those owner run dogs dont have gps? they
// should … also yes the self runs are still part of the pack. so yes.」 Until now a 동반 참가자 had
// NOTHING: `club/run/[sid].tsx:127-129` filters to `d.runnerId === myRunnerId && bookingStatus ===
// 'active'`, and a 동반 row has no booking and no runner (0134:193-196 — 「no booking, no money」),
// so that screen renders an empty list for them. After check-in the session screen showed a static
// 「체크인 완료 — 좋은 러닝 되세요」 card with no CTA and no next screen. The tracking engine was
// always generic (`geo.ts` has no runner concept); the DOOR did not exist.
//
// ⚠ A NEW ROUTE ON PURPOSE. `club/session/[sid].tsx` and `club/console/[sid].tsx` are held by
// another session tonight. Building here means zero collision; the one-line entry point in the
// session screen is handed to whoever owns that file rather than taken.
//
// 🔴 WHAT THIS SCREEN DOES NOT DO, AND SAYS SO. The walk is **not saved**. `participant_activities`
// is the right home for it (run_id nullable, `source` admits 'self_reported'), but NOTHING writes
// it for a 동반 dog — every `insert into runs` requires a booking_id, and a 동반 row has none. The
// writer is a migration, and the migration queue is jammed behind 0131's review hold. So this
// screen shows a live measurement and makes **no claim of a record**. Under the honesty laws that
// is the whole difference between a useful screen and a lie: 「no fake numbers」 forbids showing a
// saved-looking total that nothing saved.
//
// PAPER WORLD (DESIGN.md §4): canvas #FFFFFF · solid coral hairline #E8552F · ink #111111 ·
// square corners · detail floor 15pt · Oswald numerals carry an explicit lineHeight >= 1.2x.

const fmtClock = (sec: number): string => {
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  const two = (n: number) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${two(m)}:${two(s)}` : `${two(m)}:${two(s)}`;
};

export default function CompanionRun() {
  const { sid } = useLocalSearchParams<{ sid: string }>();
  const num = useNumFont();

  // 🔴 [review-agent finding, verified] The first draft fetched the ROSTER here — and the roster
  // RPC writes a phone-view audit row for every member whose number it returns (0053), on a screen
  // that renders no numbers. A false audit trail: rows claiming this user saw phones they never
  // saw. fetchClubSession carries myAttendance + my own dogName via people.isMe, returns no
  // phones, and is DEPLOYED (no PGRST202 window while 0136+ waits behind 0131).
  const [detail, setDetail] = useState<ClubSessionDetail | null>(null);
  const [rosterErr, setRosterErr] = useState(false);
  const [loaded, setLoaded] = useState(false);          // null-resolve is NOT loading (club/run:108 trap)
  const [mode, setMode] = useState<TrackMode | null>(null);
  const [km, setKm] = useState<number | null>(null);     // null = not measured yet. NEVER 0 as a placeholder.
  const [startedAt, setStartedAt] = useState<number | null>(null);
  const [elapsed, setElapsed] = useState(0);
  // [review-agent] finish() left startedAt set, so the interval kept ticking and the 시간 stat
  // counted WALL time after 러닝 종료 — a stopped run whose clock runs is the frozen-countdown
  // defect mirrored. finalElapsed freezes the display; clearing startedAt kills the interval.
  const [finalElapsed, setFinalElapsed] = useState<number | null>(null);
  const handle = useRef<TrackHandle | null>(null);
  const beginBusy = useRef(false);   // [review-agent] handle.current is set AFTER an await — two
                                     // fast taps both passed that guard. A ref set synchronously
                                     // BEFORE the await is the only race-free gate here.
  const [running, setRunning] = useState(false);

  useEffect(() => {
    let alive = true;
    fetchClubSession(String(sid))
      .then((r) => { if (alive) { setDetail(r); setLoaded(true); } })
      .catch(() => { if (alive) { setRosterErr(true); setLoaded(true); } });
    return () => { alive = false; };
  }, [sid]);

  // The tick is unconditional. A conditional interval is how a countdown freezes at mount —
  // measured on the console's hold chip the same week.
  useEffect(() => {
    if (startedAt == null) return;
    const id = setInterval(() => setElapsed(Math.floor((Date.now() - startedAt) / 1000)), 1000);
    return () => clearInterval(id);
  }, [startedAt]);

  useEffect(() => () => { handle.current?.stop().catch(() => {}); }, []);

  const me = detail?.people.find((p) => p.isMe) ?? null;
  const myDogName: string | null = me?.dogName ?? null;

  // 🔴 CHECK-IN GATED HERE TOO, not only on the CTA that opens this screen. Codex raised it
  // against the session screen's door and it is the destination's problem: a deep link
  // (/club/companion/<sid>) reaches this route without passing any CTA, so a gate that lives only
  // on the button is a gate on the polite path. Tracking a walk you have not checked into would
  // record a run for someone who is not at the meetup — the same class as a fixture the lifecycle
  // cannot produce, except here the product would produce it.
  // ⚠ `undefined` is NOT 「not checked in」 — it is 「we have not been told」. Only a loaded roster
  // can answer, so the gate reads false until `loaded`, and the copy below distinguishes them.
  const checkedIn = detail?.myAttendance === 'checked_in';

  const begin = async () => {
    if (handle.current || beginBusy.current) return;
    beginBusy.current = true;
    resetTrace();
    setFinalElapsed(null);
    setStartedAt(Date.now());
    const h = await startTracking((snap) => setKm(snap.km), { dogName: myDogName ?? undefined });
    handle.current = h;
    setMode(h.mode);
    setRunning(true);
    if (h.mode === 'denied' || h.mode === 'unavailable') {
      // Do not pretend a run started. Stop the clock and let the plate below say why.
      await h.stop().catch(() => {});
      handle.current = null;
      setRunning(false);
      setStartedAt(null);
    }
    beginBusy.current = false;
  };

  const finish = async () => {
    await handle.current?.stop().catch(() => {});
    handle.current = null;
    setRunning(false);
    if (startedAt != null) setFinalElapsed(Math.floor((Date.now() - startedAt) / 1000));
    setStartedAt(null);            // kills the interval — the clock of a stopped run must stop
    const snap = getTraceSnapshot();
    setKm(snap.km);
    setMode(null);
  };

  // ⚠ `running` was derived from `handle.current` — a REF read during render. Refs do not trigger
  // a re-render, so the CTA's label and action could disagree with reality: it happened to work
  // only because begin()/finish() also touch state, which forced the render. That is a coincidence
  // of neighbouring code, not a guarantee, and 12 lint warnings said so. It is the same shape as
  // the console's frozen countdown — a control bound to something that cannot notify it.
  // State drives the render; the ref stays for what refs are for (holding the handle to stop).

  return (
    <ScrollView style={s.root} contentContainerStyle={s.body}>
      <Pressable onPress={() => router.back()} hitSlop={10} accessibilityRole="button"
        accessibilityLabel="세션으로 돌아가기" style={s.back}>
        <Text style={s.backTxt}>‹</Text>
      </Pressable>

      <Text style={s.kicker}>동반 러닝</Text>
      <Text style={s.head}>
        {!loaded ? '불러오는 중…'
          : rosterErr ? '세션을 불러오지 못했어요'
          : !myDogName ? '동반 신청한 아이가 없어요'
          // ⚠ 「뛰는 중」 is a claim about NOW. It was rendered whenever the dog existed — before
          // check-in, before start, after finish — i.e. the screen asserted a run that had not
          // begun. Same family as a countdown frozen at mount: a live-sounding string bound to
          // nothing live. Each state now says what is actually true.
          : running ? `${myDogName}와 함께 뛰는 중`
          : !checkedIn ? `${myDogName} · 체크인 전`
          : `${myDogName}와 함께 뛸 준비가 됐어요`}
      </Text>

      {/* loading ≠ error ≠ genuinely empty — three named branches, never one blank */}
      {loaded && rosterErr && (
        <View style={s.strip}>
          <Text style={s.stripTxt}>세션 정보를 불러오지 못했어요 — 연결을 확인하고 다시 들어와 주세요</Text>
        </View>
      )}
      {loaded && !rosterErr && !myDogName && (
        <Text style={s.lede}>이 세션에 동반으로 등록한 아이가 없어요. 세션 화면 참가자 탭에서 「내 아이도 데려가기」로 등록할 수 있어요.</Text>
      )}

      {myDogName && loaded && !checkedIn && (
        <>
          <View style={s.rule} />
          <Text style={s.lede}>
            체크인하면 러닝을 시작할 수 있어요. 세션 화면에서 입장권으로 체크인해 주세요.
          </Text>
          <Pressable onPress={() => router.back()} style={s.cta}
            accessibilityRole="button" accessibilityLabel="세션 화면으로 돌아가기">
            <Text style={s.ctaTxt}>세션 화면으로</Text>
          </Pressable>
        </>
      )}

      {myDogName && checkedIn && (
        <>
          <View style={s.rule} />
          <View style={s.stats}>
            <View style={s.stat}>
              <Text style={s.statLabel}>거리</Text>
              <Text style={[s.statNum, num]}>{km == null ? '—' : km.toFixed(2)}<Text style={s.statUnit}> km</Text></Text>
            </View>
            <View style={s.stat}>
              <Text style={s.statLabel}>시간</Text>
              <Text style={[s.statNum, num]}>{startedAt != null ? fmtClock(elapsed) : finalElapsed != null ? fmtClock(finalElapsed) : '—'}</Text>
            </View>
          </View>
          <View style={s.rule} />

          {mode === 'foreground' && (
            <View style={s.strip}>
              <Text style={s.stripTxt}>화면이 꺼지면 기록이 멈춰요 — 러닝 중에는 앱을 켠 채로 두세요</Text>
            </View>
          )}
          {mode === 'denied' && (
            <View style={s.strip}>
              <Text style={s.stripTxt}>위치 권한이 꺼져 있어요 — 거리를 잴 수 없어요</Text>
              <Pressable onPress={() => { Linking.openSettings().catch(() => {}); }}
                accessibilityRole="button" accessibilityLabel="설정에서 위치 권한 켜기">
                <Text style={s.stripAction}>설정에서 켜기 ›</Text>
              </Pressable>
            </View>
          )}
          {mode === 'unavailable' && (
            <View style={s.strip}>
              <Text style={s.stripTxt}>이 빌드에는 위치 기능이 없어요 — 새 빌드에서 기록할 수 있어요</Text>
            </View>
          )}

          <Pressable onPress={running ? finish : begin} style={s.cta}
            accessibilityRole="button" accessibilityLabel={running ? '러닝 종료' : '러닝 시작'}>
            <Text style={s.ctaTxt}>{running ? '러닝 종료' : '러닝 시작'}</Text>
          </Pressable>

          {/* 🔴 The honest line. Nothing writes a 동반 walk yet, so this screen must not let a
              number look saved. Delete this ONLY in the same change that lands the
              participant_activities writer — not before, and not because it reads awkwardly. */}
          <Text style={s.note}>
            지금은 러닝 중 거리만 보여드려요. 기록으로 저장하는 기능은 아직 준비 중이에요.
          </Text>
        </>
      )}
    </ScrollView>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: paper.canvas },
  body: { padding: 20, paddingBottom: 60 },
  back: { width: 40, height: 40, borderWidth: 1, borderColor: paper.line, alignItems: 'center', justifyContent: 'center' },
  backTxt: { fontSize: 20.5, color: paper.ink, lineHeight: 25 },
  kicker: { fontSize: 12, fontWeight: '800', letterSpacing: 1.9, color: paper.faint, marginTop: 22 },
  head: { fontSize: 26, lineHeight: 34, fontWeight: '900', color: paper.ink, marginTop: 10 },
  lede: { fontSize: 16, lineHeight: 24, color: paper.text, marginTop: 14 },
  rule: { height: 1, backgroundColor: paper.line, marginTop: 22 },
  stats: { flexDirection: 'row', gap: 34, paddingVertical: 20 },
  stat: { flex: 1 },
  statLabel: { fontSize: 15, color: paper.dim, fontWeight: '700' },
  // Oswald clips without an explicit lineHeight >= 1.2x — DESIGN.md "BUG A"
  statNum: { fontSize: 34, lineHeight: 42, fontWeight: '900', color: paper.ink, marginTop: 6 },
  statUnit: { fontSize: 16, lineHeight: 22, fontWeight: '700', color: paper.dim },
  strip: { backgroundColor: paper.criticalWash, borderLeftWidth: 3, borderLeftColor: paper.critical, padding: 13, marginTop: 18 },
  stripTxt: { fontSize: 15, lineHeight: 21, fontWeight: '700', color: paper.critical },
  stripAction: { fontSize: 15, fontWeight: '800', color: paper.critical, marginTop: 8 },
  cta: { backgroundColor: paper.action, paddingVertical: 16, marginTop: 22 },
  ctaTxt: { textAlign: 'center', color: '#FFFFFF', fontSize: 16.5, fontWeight: '800' },
  note: { fontSize: 15, lineHeight: 22, color: paper.dim, marginTop: 18 },
});
