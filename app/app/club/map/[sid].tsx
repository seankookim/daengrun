import { useLocalSearchParams } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import {
  fetchClubSession, fetchPackRoster, type ClubSessionDetail, type PackRoster,
} from '../../../src/lib/api';
import { useDisplayFont } from '../../../src/lib/displayFont';
import { useNumFont } from '../../../src/lib/fonts';
import { getNaverMap, subscribePack, type LiveLinkState } from '../../../src/lib/geo';
import { goBackOrHome } from '../../../src/lib/nav';
import {
  mergePeer, packCamera, packCaption, packClockOffsetMs, packEmptyCopy, packMarkers,
  packRosterIndex, packShareLine, packWindowPhase, parsePackPos, peerAge, prunePeers,
  visiblePeers, type PackCamera, type PackPeer,
} from '../../../src/lib/pack';
import {
  packIdentity, useMyProfileId, usePackShare, usePackShareDetail,
} from '../../../src/lib/use-pack-share';
import { paper } from '../../../src/theme';

// 팩 지도 — one club session, everybody on it, a little runner icon each.
//
// ═══ THE RULING ════════════════════════════════════════════════════════════════════════════════
// Sean, 2026-08-28, verbatim: 「everyone should see everyone else on the map during a club run
// session with a little runner icon. total public; everything that's not their password is public
// to anyone.」 Asked whether to wait for counsel, he answered 「Build it now anyway」 and 「forget
// about all legal concerns」. Both rounds are in `docs/decisions/2026-08-28-sean-rulings.md`.
// **The privacy question was put to him and overruled; no session re-opens it.** Phones stay
// host-only — that ruling was NOT widened (`password-scope`, same document).
//
// ═══ THE LAYOUT IS A PICKED MOCK, NOT AN INVENTION ═════════════════════════════════════════════
// `docs/labs/club-v2-livemap-lab.html` frame ① (Sean, round 7: 「i like all lab screens」) is a
// full-bleed map under a white mastchip (‹ · display name · live dot) with a bottom paper strip:
// a numeral hero row over an ink 1.5px rule and a crew line.
//
// ⚠ WHAT IS DELIBERATELY *NOT* COPIED FROM IT, and why each omission is the honest move:
//   · The mock is the HOST's view. Its three exits (페어 목록 · 케이스 등록 · 비상 도구) and its
//     thumb CTA (러닝 종료) are host supervision powers that live on the console and run screens.
//     Rendering them here would be dead buttons — an action with no effect in this state.
//   · The mock's numeral row has THREE cells (경과 · 러닝 중 · 케이스). **Only 러닝 중 can be
//     bound to a real field from this screen.** `club_session_detail` carries the SCHEDULED time,
//     not an actual pack start, so 경과 computed here would be a fabricated number that inflates
//     whenever a session starts late; and the case count is the console's data. Two invented
//     numerals to match a mock is exactly the trade this repo refuses — so one cell renders and
//     the gap is reported rather than papered over.
//
// ═══ WHAT IS DRAWN, AND WHAT IS REFUSED ════════════════════════════════════════════════════════
// POSITION comes from the CHANNEL; IDENTITY comes from the ROSTER (`club_pack_map_roster`). The
// roster says who MIGHT run and what they are called; only a broadcast says where somebody IS. So:
//   · a member who has not started is absent rather than pinned at a guess;
//   · a broadcast for a profileId the roster does not name is DROPPED, not drawn — which is also
//     what bounds the peer table by the roster's size (codex #5);
//   · the caption is the roster's name, never the payload's;
//   · `(0,0)` and far-future stamps are refused by the parser, a fix past PACK_STALE_MS stops being
//     drawn, and one past PACK_PEER_EVICT_MS is removed from the table entirely.
// Every kind of participant is drawn the same way — a 동반 owner walking their own dog and a
// delegated runner are one population here, which is what 「everyone should see everyone else」
// means. All three tracking screens publish (companion · this one · run, U2 `1cccaea`).
//
// ═══ WHAT THE ROSTER DECIDES, BEYOND WHO MAY APPEAR ════════════════════════════════════════════
// `club_pack_map_roster` carries five things this screen now BINDS, three of which trunk fetched
// and never read (addendum 3a/3b/3c — all three were honesty defects in states the plan created):
//   · `clubName`    the masthead, so a deep link cannot write a title over live positions;
//   · `windowOpen` · `status` · `scheduledAt`  the empty map's own sentence — a finished session
//     says 「끝났어요」 and never 「러닝이 시작되면 여기에 나타나요」, which is a promise about a run
//     that already happened and is the state EVERY session ends in;
//   · `people.length`  the denominator beside 「지도에 M명」, so a phone in a pocket is a stated
//     fact rather than a silent vanish;
//   · `meetupPoint` · `serverNow`  the anon-safe meetup line, and the clock every freshness
//     decision on this screen is judged against.
//
// ═══ THE ANON VIEWER IS A FIRST-CLASS VIEWER ═══════════════════════════════════════════════════
// `club_session_detail` is authenticated-only; the roster RPC is granted to `anon`. So the ERROR
// and MISSING states key on the ROSTER alone and the detail fetch is an enhancement — it names the
// local user's own eligibility to publish and nothing else. A signed-out viewer sees the map, the
// crew line 「보기만 하는 중」, the meetup point from the roster, and no retry button aimed at a
// fetch that can never succeed for them.
//
// ⚠ NAMED ACCEPTED PROPERTY: somebody who checks in AFTER the last roster fetch is invisible for
// up to ~33 s (a 30 s roster tick plus a 3 s publish tick). Their broadcasts are refused by the
// roster gate until the next fetch admits them. The full argument, and why an empty allowed-set and
// allow-all converge on what is DRAWN, is in `mergePeer`'s doc.
//
// PAPER WORLD (DESIGN.md §2/§4): white canvas · square corners · detail floor 15pt · Black Han
// Sans once per screen (the mastchip title) · Oswald numerals with an explicit lineHeight ≥1.2×.

const MAP_ASSETS = {
  // Generated by `scripts/gen-pack-runner-icon.mjs` (reviewable as geometry, not opaque bytes).
  // A `require`d PNG is the ONE Naver marker path this repo has shipped and seen on a device
  // (`route-anchor.png`, owner/live.tsx). The custom-React-view marker type is documented as a
  // performance hazard and needs `collapsable={false}` on iOS's new architecture — an untested
  // path, and this screen is not device-verified.
  other: require('../../../assets/pack-runner.png'),
  me: require('../../../assets/pack-runner-me.png'),
};

// Marker box. Not tappable, deliberately: **Naver markers have no hit-slop** (measured in this
// repo), so a tappable marker gets either an oversized invisible target that swallows map pans or
// a target nobody can hit. The name is already on the caption and there is nothing a tap would do.
const MARKER_PT = 32;

// The freshness clock. Markers only change when a broadcast ARRIVES, so without a tick a peer who
// went silent would keep looking current forever — the frozen-countdown defect, on a map.
const AGE_TICK_MS = 5_000;

// How often the roster is re-read while the screen is open. People check in DURING a session, so a
// roster taken once on mount would silently refuse every later arrival's broadcasts — the gate that
// bounds the peer table would also freeze the pack at whoever happened to be there on mount.
const ROSTER_TICK_MS = 30_000;

type Load = 'loading' | 'ready' | 'missing' | 'error';

export default function ClubPackMap() {
  // ⚠ `sid` ONLY. The masthead used to render a `clubName` URL param, which a deep link could set
  // to any string at all — a spoofable name over somebody's live positions (codex #10). The club
  // name now comes from `club_pack_map_roster`, which reads it from the session's own club row.
  const { sid } = useLocalSearchParams<{ sid: string }>();
  const sessionId = String(sid ?? '');
  const disp = useDisplayFont();
  const nf = useNumFont();

  const maps = getNaverMap();

  const [detail, setDetail] = useState<ClubSessionDetail | null>(null);
  const [roster, setRoster] = useState<PackRoster | null>(null);
  const [rosterLoad, setRosterLoad] = useState<Load>('loading');
  const [load, setLoad] = useState<Load>('loading');
  const [link, setLink] = useState<LiveLinkState>('connecting');
  const [peers, setPeers] = useState<Map<string, PackPeer>>(() => new Map());
  // 🔴 `now` IS THE SERVER'S CLOCK, NOT THE DEVICE'S. Every `at` on this map is stamped by the
  // database (0160), so a phone that is 20 s slow reads every payload as future-skewed,
  // `parsePackPos` refuses the lot, and the screen says 「아직 아무도 달리고 있지 않아요」 over a
  // running pack with nothing to report — silent feature loss (addendum 1c). The correction is
  // `serverNow` from each roster fetch; before the first one it is 0, which is the old behaviour.
  const [now, setNow] = useState(() => Date.now());
  const [offsetMs, setOffsetMs] = useState(0);

  // Publishing is the hook's job, not this screen's — see the block comment in use-pack-share.ts
  // for why it cannot live here alone (and why N mounted hooks now drive ONE loop).
  const sharing = usePackShare(sessionId || null, packIdentity(detail));
  // …and WHY it answered that, which the frozen boolean cannot carry. Additive accessor, same
  // singleton, no obligation on the other two call sites (addendum 3).
  const shareCause = usePackShareDetail(sessionId || null);
  // The local user's own id, so their marker can be told from a stranger's. Shared with the hook
  // so one screen makes one `getUser` call, and so 「who am I」 has a single definition.
  const myId = useMyProfileId();

  // `fetchClubSession` and NOT `fetchSessionRoster`: the roster RPC writes a phone-view audit row
  // for every member whose number it returns (0053), on a screen that renders no numbers. A false
  // audit trail is worse than a missing convenience — the finding that shaped club/companion.
  //
  // ⚠ TWO GUARDS, BECAUSE THERE ARE TWO WAYS AN ANSWER CAN ARRIVE TOO LATE, and neither implies
  // the other. `aliveBox` is the SCREEN's: a fetch that resolves after the screen is gone writes
  // nothing, and that includes one a 다시 시도 tap started. `loadGen` is the LOAD's: a retry tapped
  // while the first fetch is still in flight would otherwise let the OLDER answer land last.
  // ⚠ The box is a plain object rather than a boolean ref for a mechanical reason —
  // `react-hooks/exhaustive-deps` refuses `ref.current` inside a cleanup and asks for exactly this
  // shape: capture the value in the effect BODY and let the cleanup close over the local.
  const aliveRef = useRef<{ v: boolean }>({ v: true });
  useEffect(() => {
    const box = { v: true };
    aliveRef.current = box;
    return () => { box.v = false; };
  }, []);

  const loadGen = useRef(0);
  const loadSession = useCallback(() => {
    if (!sessionId) { setLoad('missing'); return; }
    const gen = ++loadGen.current;
    const box = aliveRef.current;
    const may = () => box.v && loadGen.current === gen;
    setLoad('loading');
    fetchClubSession(sessionId)
      .then((d) => { if (!may()) return; setDetail(d); setLoad(d ? 'ready' : 'missing'); })
      .catch(() => { if (!may()) return; setDetail(null); setLoad('error'); });
  }, [sessionId]);
  useEffect(loadSession, [loadSession]);

  // ---- the roster: who may appear on this map, and what they are called --------------------
  // Re-read on a timer because people check in DURING a session. A roster taken once on mount
  // would refuse every later arrival's broadcasts, and the map would freeze at whoever happened to
  // be checked in when the screen opened — a gap the map itself could never show.
  const rosterGen = useRef(0);
  const loadRoster = useCallback((fresh: boolean) => {
    if (!sessionId) { setRosterLoad('missing'); return; }
    const gen = ++rosterGen.current;
    const box = aliveRef.current;
    const may = () => box.v && rosterGen.current === gen;
    // ⚠ Only a FRESH start says 「loading」. If a 30 s poll did it too, `measured` would drop and the
    // numeral would blink to 「—」 twice a minute over a map that never stopped working.
    if (fresh) setRosterLoad('loading');
    fetchPackRoster(sessionId)
      .then((r) => {
        if (!may()) return;
        // A null roster is 「no such session」. A refresh that comes back null after a good one is
        // still that — the session cannot un-exist — so the roster is replaced either way.
        setRoster(r);
        setRosterLoad(r ? 'ready' : 'missing');
        // ⚠ THE OFFSET IS TAKEN HERE AND NOWHERE ELSE, because `serverNow` is only meaningful
        // against the device clock AT THE MOMENT THE ANSWER ARRIVED. Computing it later — in a
        // render, in a memo — would measure the drift since the fetch instead of the drift between
        // the two clocks. Every roster fetch re-takes it, so a phone whose clock is corrected
        // mid-session follows within 30 s.
        setOffsetMs(packClockOffsetMs(r?.serverNow ?? null, Date.now()));
      })
      .catch(() => {
        if (!may()) return;
        // ⚠ KEEP the last good roster on a failed REFRESH. Blanking it on one flaky poll would drop
        // every marker off the map for 30 s and read as 「everyone stopped running」.
        setRosterLoad((cur) => (cur === 'ready' ? 'ready' : 'error'));
      });
  }, [sessionId]);
  useEffect(() => {
    loadRoster(true);
    const t = setInterval(() => loadRoster(false), ROSTER_TICK_MS);
    return () => clearInterval(t);
  }, [loadRoster]);

  const { ids: rosterIds, byId: rosterById } = useMemo(
    () => packRosterIndex(roster?.people ?? []),
    [roster],
  );

  // The allowed set travels through a ref so a 30 s roster refresh does not tear the CHANNEL down
  // and stand a new one up — the subscription must not churn on data that only decides filtering.
  // ⚠ Assigned in an EFFECT, never during render (`react-hooks/refs`).
  const allowedRef = useRef<ReadonlySet<string>>(new Set<string>());
  useEffect(() => { allowedRef.current = rosterIds; }, [rosterIds]);
  // Same reason for the clock correction: it decides how a payload is JUDGED, never whether the
  // channel exists, so it must not be a dependency of the subscription or of the 5 s tick.
  const offsetRef = useRef(0);
  useEffect(() => { offsetRef.current = offsetMs; }, [offsetMs]);

  // Subscribe ALWAYS: reads are public by Sean's ruling, so this runs whether or not the local user
  // is running, checked in, or a member at all. The channel is PRIVATE at the transport (production
  // refuses a public join) and ref-counted per topic inside `subscribePack`.
  useEffect(() => {
    if (!sessionId) return;
    return subscribePack(sessionId, (raw) => {
      // ⚠ The CORRECTED clock, not `Date.now()`. `parsePackPos` refuses a stamp more than
      // PACK_FUTURE_SKEW_MS ahead of the clock it is given, and on a slow phone every honest
      // server stamp looks exactly like that — the refusal is silent and the map simply stays
      // empty (addendum 1c).
      const p = parsePackPos(raw, Date.now() + offsetRef.current);
      if (!p) return;   // malformed, out of range, Null Island, or far-future
      // ⚠ The roster set is what BOUNDS this table. Before the first roster lands the set is empty
      // and a message or two is dropped; the publisher re-sends 3 s later, so the cost is a moment.
      // ⚠ THE EMPTY SET AND ALLOW-ALL CONVERGE ON WHAT IS DRAWN and differ only on what is
      // RETAINED — `packMarkers` drops an unlisted peer a second time on the way to the screen, so
      // neither policy can put a stranger on the map. The empty set is chosen because it ALSO
      // bounds the table in the pre-roster window, which allow-all does not (codex #5). The full
      // argument is in `mergePeer`'s doc, beside the ~33 s late-check-in property named there.
      setPeers((cur) => mergePeer(cur, p, allowedRef.current)); // SAME map when nothing moved
    }, setLink);
  }, [sessionId]);

  useEffect(() => {
    const t = setInterval(() => {
      const n = Date.now() + offsetRef.current;
      setNow(n);
      // Ageing a peer out of the VIEW does not shrink the table; this is the half that does.
      // Referentially stable, so a tick with nothing to evict does not re-render.
      setPeers((cur) => prunePeers(cur, n));
    }, AGE_TICK_MS);
    return () => clearInterval(t);
  }, []);

  const shown = useMemo(() => visiblePeers(peers, now), [peers, now]);
  // Identity from the roster, position from the channel. A peer with no roster row is dropped here
  // as well as at the merge — the screen must not re-admit what the gate refused.
  const markers = useMemo(() => packMarkers(shown, rosterById), [shown, rosterById]);

  // The camera is taken on the FIRST frame that has one and then HELD, so an incoming position
  // does not yank the view out from under a finger mid-pan.
  // ⚠ State, not a ref. A ref written and read in the same render works only by luck of ordering,
  // and `react-hooks/refs` flags every read — the value genuinely IS needed for rendering, which
  // is the definition of state.
  const [camera, setCamera] = useState<PackCamera | null>(null);
  useEffect(() => {
    if (camera !== null) return;
    const c = packCamera(markers);
    if (c) setCamera(c);
  }, [markers, camera]);

  // 🔴 THE RETRY BELONGS TO THE ROSTER, because the roster is the only fetch on this screen that
  // CAN succeed for every viewer (addendum 3b). `club_session_detail` is authenticated-only, so for
  // a signed-out viewer a retry aimed at it is a button that can never work — a dead button wearing
  // a live one's costume. It is refreshed alongside because a signed-in viewer's share line depends
  // on it; for anon that second call fails invisibly and changes nothing the button promised.
  const retry = useCallback(() => { loadRoster(true); loadSession(); }, [loadRoster, loadSession]);

  const mapReady = !!maps && !!camera && markers.length > 0;
  // ⚠ 「loading is not 0」. Before the channel has joined AND the roster has answered we have not
  // measured anything, and a 0 here would assert an empty pack we have not observed.
  // ⚠ `load` (the DETAIL fetch) is deliberately NOT a conjunct any more. Detail contributes nothing
  // to what is on the map — it names the local user's own eligibility and nothing else — so letting
  // it gate the numeral held an honest measurement behind an enhancement, and held it FOREVER for
  // an anon viewer, for whom that fetch never succeeds (addendum 3b).
  const measured = link !== 'connecting' && rosterLoad !== 'loading';

  // ── what the screen may say about the LOCAL user ───────────────────────────────────────────
  // `viewerOnly` is a statement about who you are rather than about a publish attempt: with no
  // detail we cannot be an eligible publisher at all, so 「확인 중」 would be a measurement that is
  // never going to arrive. It waits for the fetch to SETTLE, so a slow network does not flash it.
  const viewerOnly = load !== 'loading' && detail?.myAttendance !== 'checked_in';
  const shareLine = packShareLine(sharing, shareCause, viewerOnly);

  // ── what the screen may say about the SESSION ──────────────────────────────────────────────
  // `windowOpen` / `status` / `scheduledAt` were fetched and never read on trunk, so the terminal
  // state of every session read 「러닝이 시작되면 여기에 나타나요」 — a promise about a run that had
  // already finished (addendum 3a). The phase is judged on the CORRECTED clock like everything else.
  const phase = useMemo(
    () => packWindowPhase(roster?.status ?? null, roster?.windowOpen === true, roster?.scheduledAt ?? null, now),
    [roster, now],
  );
  const emptyCopy = useMemo(() => packEmptyCopy(phase, roster?.scheduledAt ?? null), [phase, roster]);

  // The roster's own count is the DENOMINATOR (addendum 3c): 「지도에 3명」 alone cannot tell a
  // three-person pack from a six-person pack with three dark phones. Stated, never inferred.
  const checkedIn = roster?.people.length ?? 0;
  // A dropped socket while markers are on screen is a fact the 10 px dot alone whispers. The markers
  // stay drawn — they are the last thing we actually observed — and the line says they may be stale.
  const linkStale = markers.length > 0 && link !== 'live';
  // The meetup point comes from the ROSTER first: it is the anon-safe source and it is fetched on
  // this screen anyway, so an anon viewer gets the same line a member does.
  const meetup = roster?.meetupPoint ?? detail?.meetupPoint ?? null;

  const recenter = useCallback(() => {
    const c = packCamera(markers);
    if (c) setCamera(c);
  }, [markers]);

  return (
    <View style={s.root}>
      <StatusBar style="dark" />

      {mapReady && maps && camera ? (
        <maps.NaverMapView
          style={StyleSheet.absoluteFill}
          camera={camera}
          isShowLocationButton={false}
          isShowCompass={false}
          isShowScaleBar={false}
          isShowZoomControls={false}
        >
          {markers.map((p) => {
            const stale = peerAge(p.atMs, now) === 'stale';
            const isMe = myId != null && p.profileId === myId;
            return (
              <maps.NaverMapMarkerOverlay
                key={p.profileId}
                latitude={p.lat}
                longitude={p.lng}
                anchor={{ x: 0.5, y: 0.5 }}
                width={MARKER_PT}
                height={MARKER_PT}
                image={isMe ? MAP_ASSETS.me : MAP_ASSETS.other}
                // A stale marker is drawn faintly and says how old it is. Drawing it at full
                // strength would be the map asserting a position it does not have.
                alpha={stale ? 0.45 : 1}
                caption={{
                  // Name · 러너 · age — built in `pack.ts` so the rule has a pin. The 러너 affix is
                  // the roster's `isRunner`, which already crosses the wire; a role-distinct marker
                  // ASSET is deferred work (addendum 3f) and is not faked with this one.
                  text: packCaption(p, now),
                  textSize: 15,
                  color: paper.ink,
                  haloColor: '#FFFFFF',
                }}
                zIndex={isMe ? 3 : 2}
              />
            );
          })}
        </maps.NaverMapView>
      ) : (
        /* An empty map draws nine different facts identically. Each one says its own cause, or
           every one of them reads to the customer as 「nobody is running」.
           ⚠ THE ERROR AND MISSING BRANCHES KEY ON THE ROSTER ALONE (addendum 3b). They used to
           key on `load` too — the `club_session_detail` fetch, which is authenticated-only — so a
           signed-out viewer opening a perfectly healthy map was shown 「세션을 확인하지 못했어요」
           and a retry button that could never succeed. Detail is an ENHANCEMENT here: it names the
           local user's eligibility to publish and contributes nothing else to this screen. */
        <View style={s.emptyWrap}>
          {rosterLoad === 'error' ? (
            <>
              <Text style={s.emptyTitle}>세션을 확인하지 못했어요</Text>
              <Pressable
                onPress={retry}
                hitSlop={12}
                accessibilityRole="button"
                accessibilityLabel="다시 시도"
                style={({ pressed }) => [s.retryBtn, pressed && s.retryBtnPressed]}
              >
                <Text style={s.retryTxt}>다시 시도</Text>
              </Pressable>
            </>
          ) : rosterLoad === 'missing' ? (
            <Text style={s.emptyTitle}>이 세션을 찾을 수 없어요</Text>
          ) : !maps ? (
            <>
              <Text style={s.emptyTitle}>이 빌드에는 지도가 없어요</Text>
              <Text style={s.emptyBody}>새 빌드에서 팩 지도를 볼 수 있어요</Text>
            </>
          ) : link === 'denied' ? (
            /* ⚠ NOT 「권한이 없어요」. That sentence blames the reader for a state they cannot own —
               and the state it actually describes, in the window this landing lives in, is a client
               talking to a database where 0160 is not applied yet. A refusal we did not diagnose is
               said as a refusal, not as a verdict on the person (addendum 3, design F6). */
            <>
              <Text style={s.emptyTitle}>아직 이 세션의 실시간 위치를 볼 수 없어요</Text>
              <Text style={s.emptyBody}>잠시 후 다시 시도해주세요</Text>
            </>
          ) : link === 'error' ? (
            /* ⚠ NO 「네트워크를 확인해주세요」. We never measured the network — the first join failure
               on a quiet project is the partition janitor waking up, which `subscribePack` now
               absorbs with one grace rejoin (addendum 3e). By the time this renders we know only
               that the join has failed twice, so that is all it says. */
            <>
              <Text style={s.emptyTitle}>실시간 위치에 연결하지 못했어요</Text>
              <Text style={s.emptyBody}>다시 연결하고 있어요 — 러닝과 기록은 그대로 진행돼요</Text>
            </>
          ) : !measured ? (
            <Text style={s.emptyTitle}>연결하는 중...</Text>
          ) : (
            /* The window's own three answers, from `roster.windowOpen`/`status`/`scheduledAt`.
               Built in `pack.ts` so the copy matrix has pins — a sentence assembled in a render is
               a sentence no suite can reach. */
            <>
              <Text style={s.emptyTitle}>{emptyCopy.title}</Text>
              {!!emptyCopy.body && <Text style={s.emptyBody}>{emptyCopy.body}</Text>}
            </>
          )}
        </View>
      )}


      {/* ---------- 마스트칩 (lab ①) — ‹ · 이름 · 라이브 도트를 한 판에 ---------- */}
      <View style={s.mastchip}>
        <Pressable
          onPress={goBackOrHome}
          style={s.back}
          accessibilityRole="button"
          accessibilityLabel="뒤로"
        >
          <Text style={s.backGlyph}>‹</Text>
        </Pressable>
        {/* The club name is the SERVER's (`club_pack_map_roster.clubName`), never a URL param —
            a deep link must not be able to write the title over somebody's live positions. */}
        <Text style={[s.disp, disp]} numberOfLines={1}>{roster?.clubName ?? '팩 지도'}</Text>
        {/* The dot is a claim that the channel is joined — it is bound to the link state, never
            drawn decoratively. Honest motion law: no idle pulse, no fake liveness. */}
        {link === 'live' && <View style={s.livedot} />}
      </View>

      {/* ---------- 스트립 (lab ①) — 실측 가능한 숫자 하나 + 크루 줄 ---------- */}
      <View style={s.strip}>
        <View style={s.nums}>
          <View style={s.numCell}>
            <Text style={[s.numV, nf]}>{measured ? String(markers.length) : '—'}</Text>
            <Text style={s.numL}>지도에 표시 중</Text>
          </View>
          {/* ---------- 전체 보기 — re-fit the camera to everyone currently drawn ----------
              The camera is taken once and HELD so an incoming position cannot yank the view out
              from under a finger. The cost is that a user who pans away has no way back, and the
              numeral beside this button can then describe people who are off-screen — a count over
              an empty viewport (addendum 3d). This is the way back, and there is deliberately NO
              auto re-fit: that would fight the pan the hold exists to protect.
              It lives INSIDE the strip rather than floating over the map so its position is the
              layout's, not a hand-picked offset — nothing on this screen is device-verified. */}
          {mapReady && (
            <Pressable
              onPress={recenter}
              accessibilityRole="button"
              accessibilityLabel="전체 보기"
              style={({ pressed }) => [s.recenter, pressed && s.recenterPressed]}
            >
              <Text style={s.recenterTxt}>전체 보기</Text>
            </Pressable>
          )}
        </View>
        <View style={s.crew}>
          <Text style={s.crewT}>{shareLine}</Text>
          {!!meetup && (
            <Text style={s.crewOthers} numberOfLines={1}>{meetup}</Text>
          )}
        </View>
        {/* 🔴 THE DENOMINATOR. 「지도에 3명」 on its own cannot tell a three-person pack from a
            six-person pack with three phones in pockets, so a runner going dark is a silent
            vanish. Both numbers are server facts: N is the roster (checked in), M is what is
            drawn. Only rendered once both have been measured — 「loading is not 0」. */}
        {measured && (
          <Text style={s.meta}>{`체크인 ${checkedIn}명 · 지도에 ${markers.length}명`}</Text>
        )}
        {/* A dropped socket while markers are still drawn. The markers stay — they are the last
            thing we observed — but they are no longer being updated, and the 10 px live dot going
            out is not a sentence anybody reads (addendum 3c). critical ink: this is a failure
            being shown as a failure, not decoration. */}
        {linkStale && (
          <Text style={s.metaWarn}>실시간 연결 끊김 — 자동으로 다시 연결 중</Text>
        )}
      </View>
    </View>
  );
}

// Values are lab ①'s, converted one-for-one: mastchip 16/44 · pad 10/14 · gap 11 · back 34 with a
// 1px #C2BFB7 border and a 24pt glyph · disp 24/30 Black Han Sans · livedot 10 round coral ·
// strip 16/16 · numeral hero 38/48 Oswald · label 15/21 700 dim · crew rule 1.5px ink.
const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: paper.canvas },

  mastchip: {
    position: 'absolute', top: 44, left: 16, zIndex: 2,
    flexDirection: 'row', alignItems: 'center', gap: 11,
    backgroundColor: paper.canvas, paddingVertical: 10, paddingHorizontal: 14, maxWidth: '86%',
  },
  back: {
    width: 34, height: 34,
    borderWidth: 1, borderColor: '#C2BFB7', backgroundColor: paper.canvas,
    alignItems: 'center', justifyContent: 'center',
  },
  backGlyph: { fontSize: 24, lineHeight: 28, color: paper.ink },
  // Black Han Sans, once per screen (DESIGN.md §3 budget). This is that one use.
  disp: { fontSize: 24, lineHeight: 30, color: paper.ink, letterSpacing: -0.24, flexShrink: 1 },
  livedot: { width: 10, height: 10, borderRadius: 5, backgroundColor: '#F0765A' },

  // 빈 지도면 — 다섯 갈래가 각자 자기 원인을 말한다 (전부 '빈 지도'로 보이기 때문이다).
  emptyWrap: { flex: 1, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 24 },
  emptyTitle: { fontSize: 16, fontWeight: '900', color: paper.ink, textAlign: 'center' },
  // §7a-bis: 행동에 필요한 문장은 딤이 아니라 잉크. 이 화면의 본문은 이 한 줄이 전부다.
  emptyBody: { fontSize: 15, color: paper.text, marginTop: 6, textAlign: 'center', lineHeight: 19.5 },
  // 세컨더리 버튼 매트릭스(F2.1): 캔버스 면 + 코랄 1px + actionInk 라벨, pressed는 wash.
  // 면이 없는 버튼이라 §3b는 scale(0.96)을 주지만 여기선 44pt 타깃이 우선이라 패딩으로 크기를
  // 확보하고 눌림은 색으로 말한다 (오퍼시티 금지 — 매트릭스 법).
  retryBtn: {
    marginTop: 14, paddingVertical: 12, paddingHorizontal: 22,
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line,
  },
  retryBtnPressed: { backgroundColor: paper.wash },
  retryTxt: { fontSize: 16, fontWeight: '800', color: paper.actionInk },

  strip: {
    position: 'absolute', left: 16, right: 16, bottom: 40, zIndex: 2,
    backgroundColor: paper.canvas, paddingTop: 4,
  },
  nums: { flexDirection: 'row', alignItems: 'stretch' },
  numCell: { flex: 1, paddingTop: 16, paddingBottom: 14, paddingHorizontal: 8, alignItems: 'center' },
  // Oswald clips without an explicit lineHeight >= 1.2x — DESIGN.md "BUG A". 38/48 = 1.26x.
  numV: { fontSize: 38, lineHeight: 48, color: paper.ink },
  numL: { fontSize: 15, lineHeight: 21, fontWeight: '700', color: paper.dim, marginTop: 4 },
  crew: {
    flexDirection: 'row', alignItems: 'center', gap: 11,
    borderTopWidth: 1.5, borderTopColor: paper.ink,
    // paddingBottom was 15 in the lab conversion, when the crew line was the last thing in the
    // strip. Two measured lines now sit under it, so the gap is theirs to own.
    marginHorizontal: 14, paddingTop: 14, paddingBottom: 10,
  },
  // 딤이 아니라 잉크: 이 줄은 「내 위치가 지금 공개되고 있는가」를 말하는 유일한 자리이고,
  // 그건 건너뛰어도 되는 정보가 아니다 (§7a-bis — 딤은 건너뛰어도 되는 것에만).
  crewT: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.ink },
  crewOthers: { fontSize: 15, lineHeight: 21, fontWeight: '700', color: paper.dim, marginLeft: 'auto', flexShrink: 1 },
  // 체크인 N명 · 지도에 M명 — text, not dim: 「누가 안 보이는가」는 건너뛰어도 되는 정보가 아니다
  // (§7a-bis — 딤은 건너뛰어도 되는 것에만). 15pt 디테일 플로어.
  meta: {
    fontSize: 15, lineHeight: 21, fontWeight: '700', color: paper.text,
    marginHorizontal: 14, paddingBottom: 12,
  },
  // 라우드-페일 잉크 (F1.2): 실패는 실패로 보인다. line 과 절대 공유하지 않는 역할 색.
  metaWarn: {
    fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.critical,
    marginHorizontal: 14, paddingBottom: 12,
  },

  // 전체 보기 — 세컨더리 매트릭스(F2.1)와 같은 판: 캔버스 면 + 1px 코랄 라인 + actionInk 라벨.
  // 44pt 타깃은 minHeight 로 확보하고, 눌림은 오퍼시티가 아니라 wash 로 말한다 (매트릭스 법).
  recenter: {
    alignSelf: 'center', marginRight: 8,
    minHeight: 44, justifyContent: 'center', paddingHorizontal: 16,
    backgroundColor: paper.canvas, borderWidth: 1, borderColor: paper.line,
  },
  recenterPressed: { backgroundColor: paper.wash },
  recenterTxt: { fontSize: 15, lineHeight: 21, fontWeight: '800', color: paper.actionInk },
});
