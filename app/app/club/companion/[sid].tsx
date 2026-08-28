import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useRef, useState } from 'react';
import { Linking, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { PaperBtn } from '../../../src/components/paper-btn';
import { fetchClubSession, recordCompanionRun, type ClubSessionDetail } from '../../../src/lib/api';
import { useNumFont } from '../../../src/lib/fonts';
import { getTraceSnapshot, resetTrace, startTracking, type TrackHandle, type TrackMode } from '../../../src/lib/geo';
import { usePackShare } from '../../../src/lib/use-pack-share';
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
// 🔴 THE WALK IS NOW SAVED — 0143 (2026-08-27). This block used to say the opposite, and the note
// at the bottom of the screen said so to the user, both under an instruction to delete them ONLY
// in the change that lands the writer. That change is this one. `session_record_companion_run`
// upserts the single `participant_activities` row for (session, me): `self_reported` when a
// distance was measured, `checkin_only` when it was not — Sean's own ruling, 2026-08-26: a flat
// battery 「lands as checkin_only rather than never having happened」.
//
// ⚠ SAVING CAN FAIL, AND FAILURE IS RENDERED AS FAILURE. No silent catch → happy UI. On a failed
//   save the measured distance and time stay on screen exactly as they were, the copy says the
//   record did not save, and 다시 시도 re-sends the SAME measurement (never a re-measure).
// ⚠ AND IT WILL FAIL FOR A WHILE: 0143 is not deployed yet, so the RPC answers PGRST202 until the
//   stack ships. `PENDING_DEPLOY` in src/lib/rpc-skew.ts carries the entry that turns that one
//   window into an honest Korean sentence instead of a raw PostgREST string; the entry is DELETED
//   at deploy, together with its pin in test/rpc-skew.test.cjs.
//
// PAPER WORLD (DESIGN.md §4): canvas #FFFFFF · solid coral hairline #E8552F · ink #111111 ·
// square corners · detail floor 15pt · Oswald numerals carry an explicit lineHeight >= 1.2x.

// 저장 실패 사유를 사용자가 읽을 수 있는 한 문장으로. 서버가 던지는 토큰은 영어이고, 화면에 영어
// 토큰을 그대로 내보내는 것은 「실패를 실패로 보여준다」가 아니라 그냥 진단 유출이다.
// clubRpc는 배포 스큐·feature_disabled를 이미 한국어로 번역해서 던지므로 그 문장은 그대로 쓴다.
const saveErrorText = (e: unknown): string => {
  const m = e instanceof Error ? e.message : '';
  if (m.includes('not_checked_in')) return '체크인 기록이 없어 저장할 수 없어요 — 세션 화면에서 체크인해 주세요';
  if (m.includes('no_companion_dog')) return '이 세션에 동반으로 등록한 아이가 없어요';
  if (m.includes('not_joined')) return '이 세션의 참가자가 아니에요';
  if (m.includes('invalid_measure')) return '측정값이 저장할 수 있는 범위를 벗어났어요';
  if (/[가-힣]/.test(m)) return m;
  return '기록을 저장하지 못했어요 — 잠시 후 다시 시도해 주세요';
};

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

  // 저장 상태 — 'idle'은 「아직 종료하지 않았다」이지 「저장됐다」가 아니다. 네 갈래를 이름으로
  // 구분하는 이유는 로딩·성공·실패를 한 칸에 뭉개면 실패가 조용히 사라지기 때문이다.
  const [saveState, setSaveState] = useState<'idle' | 'saving' | 'saved' | 'failed'>('idle');
  const [saveErr, setSaveErr] = useState<string | null>(null);
  // 다시 시도는 「다시 측정」이 아니다 — 보낸 값 그대로를 다시 보낸다.
  // ⚠ ref가 아니라 STATE다. 이 값은 렌더에서 읽힌다(저장 문구가 거리 유무로 갈린다). 이 파일이
  //   이미 한 번 밟은 덫이 바로 그것 — 렌더에서 읽은 ref는 리렌더를 일으키지 못해 화면과 실제가
  //   어긋난다(아래 running 주석). 렌더가 읽는 값은 state가 가진다.
  const [lastMeasure, setLastMeasure] =
    useState<{ km: number | null; durationSec: number | null } | null>(null);

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

  // 팩 지도 송신 — 한 줄. Sean, 2026-08-28: 「everyone should see everyone else on the map during a
  // club run session with a little runner icon.」 **「everyone」 includes the 동반 owner**, and this
  // screen was the one kind of participant with no publisher at all: it imports `startTracking`
  // and broadcast nothing, so a pack of self-runners rendered a nearly empty map that looked like
  // it was working. The hook reads the buffer this screen's own `startTracking` fills — it starts
  // no tracking of its own (`geo.ts`'s `liveSub` is a singleton and taking it would freeze the km
  // above), and it publishes only while a fix is actually arriving.
  const packSharing = usePackShare(sid ? String(sid) : null, detail);

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
    // 새 러닝은 아직 저장된 기록이 없다 — 이전 러닝의 「저장됐어요」를 물려받으면 그건 거짓말이다.
    setSaveState('idle');
    setSaveErr(null);
    setLastMeasure(null);
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

  // 한 번 만든 측정값을 그대로 다시 보낸다. finish()와 다시 시도가 공유한다.
  const save = async (measuredKm: number | null, durationSec: number | null) => {
    setLastMeasure({ km: measuredKm, durationSec });
    setSaveState('saving');
    setSaveErr(null);
    try {
      await recordCompanionRun(String(sid), measuredKm, durationSec);
      setSaveState('saved');
    } catch (e) {
      // 실패를 삼키지 않는다 — 화면의 거리·시간은 그대로 두고 저장이 안 됐다고 말한다.
      setSaveErr(saveErrorText(e));
      setSaveState('failed');
    }
  };

  const finish = async () => {
    await handle.current?.stop().catch(() => {});
    handle.current = null;
    setRunning(false);
    const secs = startedAt != null ? Math.floor((Date.now() - startedAt) / 1000) : null;
    if (secs != null) setFinalElapsed(secs);
    setStartedAt(null);            // kills the interval — the clock of a stopped run must stop
    const snap = getTraceSnapshot();
    // ⚠ 「재지 못했다」와 「0km를 걸었다」는 다른 문장이다. 고정점이 0개면 거리는 측정된 적이 없으므로
    //    화면에도 숫자를 넣지 않고(—), 서버에도 null을 보낸다 — 0143은 그걸 checkin_only로 남긴다
    //    (Sean: 방전된 산책도 「일어나지 않은 것」이 아니다). 0.00을 보내면 그게 가짜 숫자다.
    const measuredKm = snap.trace.length === 0 ? null : snap.km;
    setKm(measuredKm);
    setMode(null);
    await save(measuredKm, secs);
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
          <PaperBtn label="세션 화면으로" onPress={() => router.back()} style={s.cta} />
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

          {/* 내 위치가 지금 팩 지도에 공개되고 있다는 사실은, 그게 참일 때만 말한다.
              (아직 확인 전이면 아무 말도 하지 않는다 — null은 「공유 안 함」이 아니다.) */}
          {packSharing === true && <Text style={s.note}>팩 지도에 내 위치가 공유되고 있어요</Text>}

          <PaperBtn label={running ? '러닝 종료' : '러닝 시작'} onPress={running ? finish : begin} style={s.cta} />

          {/* 저장 결과. 네 상태가 각자 다른 문장을 갖는다 — 저장 중은 저장됨이 아니고, 실패는
              아무 말도 안 하는 것이 아니다. */}
          {saveState === 'saving' && <Text style={s.note}>기록을 저장하고 있어요…</Text>}
          {saveState === 'saved' && (
            <Text style={s.note}>
              {lastMeasure?.km == null
                // 거리를 못 잰 산책도 기록이다 — 다만 「거리 기록」인 척하지 않는다.
                ? '거리를 재지 못해 참가 기록으로 저장했어요.'
                : '기록이 저장됐어요.'}
            </Text>
          )}
          {saveState === 'failed' && (
            <View style={s.strip}>
              <Text style={s.stripTxt}>{saveErr ?? '기록을 저장하지 못했어요'}</Text>
              <Text style={s.stripSub}>화면의 거리·시간은 그대로예요 — 다시 시도할 수 있어요.</Text>
              <Pressable
                onPress={() => {
                  const m = lastMeasure;
                  if (m) save(m.km, m.durationSec).catch(() => {});
                }}
                accessibilityRole="button" accessibilityLabel="기록 저장 다시 시도">
                <Text style={s.stripAction}>다시 시도 ›</Text>
              </Pressable>
            </View>
          )}
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
  kicker: { fontSize: 15, fontWeight: '800', letterSpacing: 1.9, color: paper.faint, marginTop: 22 },
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
  // second line inside a strip — stripTxt carries no top margin, so two stacked copies collide
  stripSub: { fontSize: 15, lineHeight: 21, fontWeight: '700', color: paper.critical, marginTop: 6 },
  stripAction: { fontSize: 15, fontWeight: '800', color: paper.critical, marginTop: 8 },
  // Layout only — PaperBtn owns the action fill, the padding, the 17/800 label and the
  // §3b press key (4px lip at rest, translateY(3) + 1px pressed).
  cta: { marginTop: 22 },
  note: { fontSize: 15, lineHeight: 22, color: paper.dim, marginTop: 18 },
});
