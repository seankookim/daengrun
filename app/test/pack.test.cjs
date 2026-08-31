// pack.ts — the pure half of the club-session pack map. Tests run against the REAL compiled
// source (see run-pack-tests.sh), never a retyped copy.
//
// WHY THESE PINS EXIST AND WHAT THEY DO NOT COVER, said first because it is the honest part:
// `app/test/*.cjs` structurally cannot import a `.tsx` route module, so NOTHING here says whether
// `club/map/[sid].tsx` calls any of it. These pins establish the RULES; that the screen obeys them
// is unpinned and stays unpinned until the suite can reach a route module. Same division as
// `check-definer-acl` beside 98 H1 — and the same warning: neither is evidence for the other.
//
// Every property below is stated as a sentence a reader can check WITHOUT looking at a mutation,
// because a pin shaped to a mutation passes the re-run by construction.
//
// ⚠ THE 「NO TZ MATRIX」 NOTE IN `run-pack-tests.sh` DIED ON 2026-08-31 AND THE RUNNER CHANGED WITH
// IT. `packStartLine` prints a session's scheduled START, which is a KST CALENDAR fact — the first
// thing in this module that is not an epoch delta. A Seoul-only run is structurally incapable of
// seeing that class (CLAUDE.md: re-planting the device-clock bug reddened 25 pins under
// America/New_York and ZERO under Asia/Seoul), so the runner now executes this file under three
// zones and the label assertions are literal strings that must be identical in all three.
const {
  PACK_TOPIC, PACK_EVENT, PACK_FRESH_MS, PACK_STALE_MS, PACK_PUBLISH_MAX_FIX_AGE_MS,
  PACK_PUB_MIN_MS, PACK_FUTURE_SKEW_MS, PACK_PEER_EVICT_MS, PACK_WINDOW_TAIL_MS,
  ZOOM_MIN, ZOOM_MAX, ZOOM_POINT,
  parsePackPos, peerAge, agoLabel, mergePeer, prunePeers, visiblePeers, packCamera,
  packRosterIndex, packMarkers, packCaption, packClockOffsetMs, packWindowPhase, packStartLine,
  packEmptyCopy, packShareLine,
} = require('./pack.build.cjs');

let pass = 0, fail = 0;
const t = (n, f) => { try { f(); console.log('PASS ' + n); pass++; } catch (e) { console.log('FAIL ' + n + ' — ' + e.message); fail++; } };
const ok = (c, m) => { if (!c) throw new Error(m || 'assertion failed'); };
const eq = (a, b, m) => ok(a === b, (m || '') + ' — got ' + JSON.stringify(a) + ', want ' + JSON.stringify(b));

const T0 = Date.parse('2026-08-28T10:00:00.000Z');
const iso = (ms) => new Date(ms).toISOString();
// A well-formed payload, used as the base every negative case mutates ONE field of. Building the
// bad cases from a known-good one is what stops a pin passing because the whole fixture was junk.
const good = () => ({ profileId: 'p-1', name: '민수', lat: 37.5096, lng: 126.9954, at: iso(T0) });

// Every case fixes the clock EXPLICITLY. `parsePackPos` refuses a far-future stamp, which makes
// "now" load-bearing — and a pin whose verdict depends on when it is RUN is a flaky pin. That is
// exactly why the clock is a parameter rather than a `Date.now()` read inside the function.
const P = (raw, nowMs = T0) => parsePackPos(raw, nowMs);

// ═══ the contract's own surface ════════════════════════════════════════════════════════════════
// The topic string and the event name are the two things the SERVER half must match byte for
// byte. They are pinned as literals because a rename here is a silently empty map, not an error.

t('the topic is `pack-<sessionId>` and the event is `pos` (the fixed contract)', () => {
  eq(PACK_TOPIC('abc-123'), 'pack-abc-123', 'topic');
  eq(PACK_EVENT, 'pos', 'event');
});

t('the topic namespace cannot be confused with the 1:1 run namespace', () => {
  // `run2-` is the private, policy-bound 1:1 channel (0104). A pack topic must never be parseable
  // as one, or a loose server-side regex could admit it to the wrong policy family.
  ok(!PACK_TOPIC('x').startsWith('run'), 'pack topic collides with the run namespace');
});

// ═══ parsePackPos — everything on this channel is untrusted ═════════════════════════════════════
// PROPERTY: a payload is drawn only when every field needed to draw it honestly is present and in
// range. Reads are public and the subscribe carries no auth gate, so this parser is the only
// defence the client has against a malformed or invented message.

t('a well-formed payload parses, and `atMs` is the parsed instant', () => {
  const p = P(good());
  ok(p, 'good payload rejected');
  eq(p.profileId, 'p-1', 'profileId');
  eq(p.name, '민수', 'name');
  eq(p.lat, 37.5096, 'lat');
  eq(p.lng, 126.9954, 'lng');
  eq(p.atMs, T0, 'atMs');
});

t('🔴 (0,0) is REFUSED — an unknown position renders as absent, never as Null Island', () => {
  ok(P({ ...good(), lat: 0, lng: 0 }) === null, '(0,0) was accepted');
  // …but a real zero on ONE axis is a real place and must survive. This arm is what stops the
  // rule being "reject anything with a zero in it", which would blank the prime meridian.
  ok(P({ ...good(), lat: 0 }) !== null, 'lat 0 (equator) was rejected');
  ok(P({ ...good(), lng: 0 }) !== null, 'lng 0 (prime meridian) was rejected');
});

t('out-of-range coordinates are refused', () => {
  for (const bad of [{ lat: 90.1 }, { lat: -90.1 }, { lng: 180.1 }, { lng: -180.1 }])
    ok(P({ ...good(), ...bad }) === null, JSON.stringify(bad) + ' was accepted');
  // the boundaries themselves are legal coordinates
  ok(P({ ...good(), lat: 90, lng: 180 }) !== null, 'the pole was rejected');
});

t('non-numeric, NaN and Infinity coordinates are refused', () => {
  for (const bad of [{ lat: '37.5' }, { lng: null }, { lat: NaN }, { lng: Infinity }, { lat: undefined }])
    ok(P({ ...good(), ...bad }) === null, JSON.stringify(String(Object.values(bad)[0])) + ' was accepted');
});

t('a payload with no usable profileId is refused — an anonymous dot cannot be de-duplicated', () => {
  for (const bad of [{ profileId: '' }, { profileId: '   ' }, { profileId: 42 }, { profileId: null }])
    ok(P({ ...good(), ...bad }) === null, JSON.stringify(bad) + ' was accepted');
});

t('an unparseable or missing `at` is refused — a marker with no instant can never go stale', () => {
  for (const bad of [{ at: '' }, { at: 'yesterday' }, { at: 1234567890 }, { at: null }, { at: undefined }])
    ok(P({ ...good(), ...bad }) === null, JSON.stringify(bad) + ' was accepted');
});

t('a missing name falls back to 참가자 rather than hiding the person or inventing a name', () => {
  eq(P({ ...good(), name: undefined }).name, '참가자', 'undefined name');
  eq(P({ ...good(), name: '  ' }).name, '참가자', 'blank name');
  eq(P({ ...good(), name: 7 }).name, '참가자', 'non-string name');
});

t('non-objects are refused without throwing', () => {
  for (const bad of [null, undefined, 'pos', 42, true, []])
    ok(P(bad) === null, JSON.stringify(bad) + ' was accepted');
});

// ═══ peerAge / agoLabel ════════════════════════════════════════════════════════════════════════
// PROPERTY: a marker is drawn at full strength only while we have reason to believe it is current;
// after that it is drawn faintly with its age; after that it is not drawn at all.

t('the three ages are exactly the two thresholds, boundaries included in the younger band', () => {
  eq(peerAge(T0, T0), 'fresh', 'now');
  eq(peerAge(T0, T0 + PACK_FRESH_MS), 'fresh', 'exactly FRESH');
  eq(peerAge(T0, T0 + PACK_FRESH_MS + 1), 'stale', 'one ms past FRESH');
  eq(peerAge(T0, T0 + PACK_STALE_MS), 'stale', 'exactly STALE');
  eq(peerAge(T0, T0 + PACK_STALE_MS + 1), 'gone', 'one ms past STALE');
});

t('🔴 a FAR-FUTURE payload is REFUSED — newest-wins would otherwise pin it forever', () => {
  // The hazard is not the label. `mergePeer` is newest-wins and `visiblePeers` sorts on the same
  // field, so one payload stamped an hour ahead makes every honest later message from that person
  // "older" and discarded — the marker freezes at a place of the sender's choosing, and nothing
  // looks broken. On a channel whose writes carry no server gate that is the cheapest attack
  // available, so the parser refuses the payload rather than the merge coping with it.
  ok(P({ ...good(), at: iso(T0 + 3_600_000) }, T0) === null, 'an hour-ahead stamp was accepted');
  ok(P({ ...good(), at: iso(T0 + PACK_FUTURE_SKEW_MS + 1) }, T0) === null, 'just past the skew was accepted');
});

t('…but ordinary clock skew between two honest phones is tolerated, and reads as fresh', () => {
  const p = P({ ...good(), at: iso(T0 + PACK_FUTURE_SKEW_MS) }, T0);
  ok(p, 'a payload inside the skew tolerance was refused');
  eq(peerAge(p.atMs, T0), 'fresh', 'a slightly-future stamp');
});

t('the future tolerance is far tighter than the window a marker is drawn in', () => {
  // A tolerance as loose as the drawable window would let a sender park a marker for its whole
  // lifetime, which is the thing the refusal exists to prevent.
  ok(PACK_FUTURE_SKEW_MS < PACK_FRESH_MS, 'the skew tolerance is not tighter than FRESH');
});

t('the thresholds are ordered, and publishing stops inside the drawable window', () => {
  ok(PACK_FRESH_MS < PACK_STALE_MS, 'FRESH must be tighter than STALE');
  // If a device kept publishing past the point at which everyone else drops it, it would appear
  // and vanish repeatedly. Publishing must stop strictly before the drawable window closes.
  ok(PACK_PUBLISH_MAX_FIX_AGE_MS < PACK_STALE_MS, 'publishing outlives the map');
  // …and must outlive the fresh window, or a runner standing still (distanceInterval 5 m) would
  // stop broadcasting while still legitimately on the run.
  ok(PACK_PUBLISH_MAX_FIX_AGE_MS > PACK_FRESH_MS, 'publishing stops before a still runner moves');
  ok(PACK_PUB_MIN_MS >= 3000, 'the publish throttle is looser than the 1:1 share');
});

t('agoLabel says 방금 under a minute and whole minutes above it', () => {
  eq(agoLabel(T0, T0), '방금', '0s');
  eq(agoLabel(T0, T0 + 59_000), '방금', '59s');
  eq(agoLabel(T0, T0 + 60_000), '1분 전', '60s');
  eq(agoLabel(T0, T0 + 119_000), '1분 전', '119s');
  eq(agoLabel(T0, T0 + 600_000), '10분 전', '10m');
});

// ═══ mergePeer ═════════════════════════════════════════════════════════════════════════════════
// PROPERTY: each participant has exactly one marker, showing their newest known position — and no
// participant the SERVER ROSTER did not name has a marker at all.
//
// ⚠ WHY EVERY CALL BELOW NOW PASSES A THIRD ARGUMENT (0160). `mergePeer` gained `allowed`, the set
// of profile ids the roster admits. The pins that existed before it are about the newest-wins rule
// and say nothing about admission, so they pass `null` (allow all) — which is what keeps each pin
// measuring ONE property. The admission pins are the new block below, and they are the only ones
// that pass a real set.

t('a new profile is added; the same profile is replaced, not duplicated', () => {
  const a = P(good());
  const b = P({ ...good(), at: iso(T0 + 5000), lat: 37.51 });
  const m1 = mergePeer(new Map(), a, null);
  eq(m1.size, 1, 'first insert');
  const m2 = mergePeer(m1, b, null);
  eq(m2.size, 1, 'same profile duplicated');
  eq(m2.get('p-1').lat, 37.51, 'newer position not adopted');
});

t('🔴 an OUT-OF-ORDER (older) delivery does not move the marker backwards', () => {
  const newer = P({ ...good(), at: iso(T0 + 5000), lat: 37.51 });
  const older = P({ ...good(), at: iso(T0), lat: 37.40 });
  const m = mergePeer(mergePeer(new Map(), newer, null), older, null);
  eq(m.get('p-1').lat, 37.51, 'an older message overwrote a newer one');
});

t('an unchanged merge returns the SAME map object, so a caller can skip a re-render', () => {
  const newer = P({ ...good(), at: iso(T0 + 5000) });
  const older = P({ ...good(), at: iso(T0) });
  const m1 = mergePeer(new Map(), newer, null);
  ok(mergePeer(m1, older, null) === m1, 'a no-op merge allocated a new map');
  // …and a real change must NOT reuse it, or React would never see the update.
  const other = P({ ...good(), profileId: 'p-2' });
  ok(mergePeer(m1, other, null) !== m1, 'a real change reused the old map');
});

t('two different profiles both stay on the map', () => {
  const a = P(good());
  const b = P({ ...good(), profileId: 'p-2', name: '지연' });
  eq(mergePeer(mergePeer(new Map(), a, null), b, null).size, 2, 'a second person was swallowed');
});

// ═══ mergePeer — the roster gate (0160, codex 0159 #5) ═════════════════════════════════════════
// PROPERTY: the peer table can never hold more entries than the roster has people, no matter how
// many distinct profileIds arrive on the channel. Before 0160 it grew for the life of the screen,
// and the pins missed it because they only ever asserted what was DRAWN — `visiblePeers` hides an
// old peer and shrinks nothing.

t('🔴 a payload for a profileId the ROSTER does not name is DROPPED, not stored', () => {
  const allowed = new Set(['p-1']);
  const mine = P(good());
  const stranger = P({ ...good(), profileId: 'p-999', name: '침입자' });
  const m = mergePeer(new Map(), stranger, allowed);
  eq(m.size, 0, 'a stranger entered the peer table');
  // …and the refusal is referentially stable, so it does not even cost a re-render.
  const m0 = new Map();
  ok(mergePeer(m0, stranger, allowed) === m0, 'a dropped payload allocated a new map');
  // The control: the SAME code path admits someone the roster does name. Without this arm the pin
  // above would also pass on a `mergePeer` that admits nobody at all.
  eq(mergePeer(new Map(), mine, allowed).size, 1, 'a roster member was refused');
});

t('🔴 the table is BOUNDED BY THE ROSTER — 500 distinct strangers add nothing', () => {
  // The DoS shape from the finding, stated as an experiment: flood the merge with unique ids and
  // measure the table. This is a delta the behaviour causes, not a state the fixture arrives in —
  // deleting the gate makes this 501.
  const allowed = new Set(['p-1']);
  let m = mergePeer(new Map(), P(good()), allowed);
  for (let i = 0; i < 500; i++) {
    m = mergePeer(m, P({ ...good(), profileId: 'flood-' + i, at: iso(T0 + i) }), allowed);
  }
  eq(m.size, 1, 'the peer table grew past the roster');
});

t('an EMPTY roster admits nobody — which is what the screen holds before the first fetch lands', () => {
  eq(mergePeer(new Map(), P(good()), new Set()).size, 0, 'an empty roster admitted a payload');
});

t('`null` means allow-all, and it is the pins-only escape hatch', () => {
  // Stated so nobody "simplifies" the screen to pass null: this arm is what would silently restore
  // the unbounded table, so it is pinned as a DIFFERENT answer from the empty set above.
  eq(mergePeer(new Map(), P(good()), null).size, 1, 'null did not allow');
});

// ═══ prunePeers ════════════════════════════════════════════════════════════════════════════════
// PROPERTY: an entry whose newest position is older than PACK_PEER_EVICT_MS leaves the TABLE, not
// merely the view. `visiblePeers` answers "what is drawn"; this answers "what is retained", and
// conflating them is exactly how the unbounded map survived a green suite.

t('🔴 a peer past PACK_PEER_EVICT_MS is REMOVED from the table, and a younger one is not', () => {
  const mk = (id, ageMs) => P({ ...good(), profileId: id, at: iso(T0 - ageMs) }, T0);
  let m = new Map();
  for (const [id, age] of [['young', 1000], ['past-stale', PACK_STALE_MS + 5000], ['ancient', PACK_PEER_EVICT_MS + 1]]) {
    m = mergePeer(m, mk(id, age), null);
  }
  eq(m.size, 3, 'the fixture did not build three peers');
  const out = prunePeers(m, T0);
  eq(out.size, 2, 'wrong number retained');
  ok(!out.has('ancient'), 'the ancient peer survived eviction');
  // ⚠ The 「past-stale」 arm is the one that separates this function from `visiblePeers`: it is NOT
  // drawn and it IS retained. A prune keyed on STALE would evict it and it would flicker back in.
  ok(out.has('past-stale'), 'a merely-stale peer was evicted');
  eq(visiblePeers(m, T0).length, 1, 'the stale peer was drawn — the two rules were conflated');
});

t('the eviction boundary is inclusive on the younger side, like the age bands', () => {
  const at = (ageMs) => mergePeer(new Map(), P({ ...good(), at: iso(T0 - ageMs) }, T0), null);
  eq(prunePeers(at(PACK_PEER_EVICT_MS), T0).size, 1, 'exactly EVICT was evicted');
  eq(prunePeers(at(PACK_PEER_EVICT_MS + 1), T0).size, 0, 'one ms past EVICT survived');
});

t('a prune with nothing to evict returns the SAME map, so a 5 s tick does not re-render', () => {
  const m = mergePeer(new Map(), P(good()), null);
  ok(prunePeers(m, T0) === m, 'a no-op prune allocated a new map');
  ok(prunePeers(m, T0 + PACK_PEER_EVICT_MS + 1) !== m, 'a real eviction reused the old map');
  eq(prunePeers(new Map(), T0).size, 0, 'an empty table pruned to something');
});

t('eviction is LOOSER than the drawable window, or a drawn peer would flicker out', () => {
  ok(PACK_PEER_EVICT_MS > PACK_STALE_MS, 'a peer would be evicted while still drawable');
});

// ═══ visiblePeers ══════════════════════════════════════════════════════════════════════════════

t('peers past STALE are dropped; fresh and stale ones survive, newest first', () => {
  const mk = (id, ageMs) => P({ ...good(), profileId: id, at: iso(T0 - ageMs) }, T0);
  let m = new Map();
  for (const [id, age] of [['fresh', 1000], ['stale', PACK_FRESH_MS + 5000], ['gone', PACK_STALE_MS + 5000]]) {
    m = mergePeer(m, mk(id, age), null);
  }
  const v = visiblePeers(m, T0);
  eq(v.length, 2, 'wrong number drawn');
  eq(v[0].profileId, 'fresh', 'not newest-first');
  eq(v[1].profileId, 'stale', 'stale one missing or misordered');
});

t('an empty table draws nobody — the screen must say so rather than centring on a guess', () => {
  eq(visiblePeers(new Map(), T0).length, 0, 'phantom peers');
  ok(packCamera([]) === null, 'a camera was invented for an empty pack');
});

// ═══ packRosterIndex / packMarkers — roster precedence (0160) ══════════════════════════════════
// PROPERTY: a marker's IDENTITY (who, and what caption) comes from the server roster; its POSITION
// and INSTANT come from the broadcast. Nothing on the map is captioned from a payload.

const RP = [
  { profileId: 'p-1', name: '민수', role: 'host_runner', isHost: true, isRunner: true },
  { profileId: 'p-2', name: null, role: 'attendee', isHost: false, isRunner: false },
];

t('packRosterIndex gives ONE derivation of the admitted set and the caption lookup', () => {
  const { ids, byId } = packRosterIndex(RP);
  eq(ids.size, 2, 'ids');
  ok(ids.has('p-1') && ids.has('p-2'), 'a listed person is missing from the set');
  eq(byId.get('p-1').name, '민수', 'byId lost the name');
  // The set and the lookup must never disagree — two derivations of one list is how a screen ends
  // up drawing someone it decided not to admit.
  for (const id of ids) ok(byId.has(id), 'ids and byId disagree on ' + id);
});

t('packRosterIndex ignores a row with no usable profileId rather than indexing an empty key', () => {
  const { ids, byId } = packRosterIndex([...RP, { profileId: '', name: 'x' }, { name: 'y' }]);
  eq(ids.size, 2, 'a junk row was admitted');
  ok(!byId.has(''), 'the empty key was indexed');
  eq(packRosterIndex([]).ids.size, 0, 'an empty roster produced ids');
});

t('🔴 the caption is the ROSTER name, even when the payload carries a different one', () => {
  // The payload is server-authored since 0160, so today the two agree. A rule that only holds while
  // two sources agree is not a rule — this pin is what makes the roster authoritative rather than
  // coincidentally equal.
  const { byId } = packRosterIndex(RP);
  const peer = P({ ...good(), profileId: 'p-1', name: '사칭' });
  const out = packMarkers([peer], byId);
  eq(out.length, 1, 'a roster member was dropped');
  eq(out[0].name, '민수', 'the payload name was rendered');
  // …and the POSITION is the payload's, not the roster's (the roster has none).
  eq(out[0].lat, 37.5096, 'lat came from somewhere other than the payload');
  eq(out[0].atMs, T0, 'atMs came from somewhere other than the payload');
});

t('🔴 `isRunner` comes from the ROSTER too — a payload cannot make itself a 러너', () => {
  const { byId } = packRosterIndex(RP);
  // The payload carries no such field and could not be believed if it did; identity and role are
  // one question with one source, which is the whole point of the roster precedence rule.
  const out = packMarkers([
    P({ ...good(), profileId: 'p-1', isRunner: false }),
    P({ ...good(), profileId: 'p-2', isRunner: true }),
  ], byId);
  eq(out.length, 2, 'a roster member was dropped');
  eq(out[0].isRunner, true, 'the host_runner lost their role');
  eq(out[1].isRunner, false, 'an attendee was promoted to 러너 by their own payload');
});

t('a roster row with a null name captions 참가자 — a missing name is not a reason to hide someone', () => {
  const { byId } = packRosterIndex(RP);
  const out = packMarkers([P({ ...good(), profileId: 'p-2', name: '무시됨' })], byId);
  eq(out.length, 1, 'a nameless member was hidden');
  eq(out[0].name, '참가자', 'name');
});

t('🔴 a peer with no roster row is not drawn — the screen cannot re-admit what the gate refused', () => {
  const { byId } = packRosterIndex(RP);
  eq(packMarkers([P({ ...good(), profileId: 'p-999' })], byId).length, 0, 'a stranger was drawn');
  // Control: the same call draws a listed peer, so the zero above is the rule and not a dead join.
  eq(packMarkers([P({ ...good(), profileId: 'p-1' })], byId).length, 1, 'a listed peer was dropped');
});

t('packMarkers preserves the order it is given (visiblePeers already sorted newest-first)', () => {
  const { byId } = packRosterIndex(RP);
  const peers = [P({ ...good(), profileId: 'p-2', at: iso(T0) }), P({ ...good(), profileId: 'p-1', at: iso(T0 - 1000) })];
  const out = packMarkers(peers, byId);
  eq(out.map((m) => m.profileId).join(','), 'p-2,p-1', 'order');
});

// ═══ packCamera ════════════════════════════════════════════════════════════════════════════════
// PROPERTY: the frame contains every point given, at a zoom inside the declared band.

t('one point centres on it at the single-point zoom', () => {
  const c = packCamera([{ lat: 37.5, lng: 127.0 }]);
  eq(c.latitude, 37.5, 'lat');
  eq(c.longitude, 127.0, 'lng');
  eq(c.zoom, ZOOM_POINT, 'zoom');
});

t('several coincident points behave like one point (no divide-by-zero, no NaN)', () => {
  const c = packCamera([{ lat: 37.5, lng: 127 }, { lat: 37.5, lng: 127 }]);
  eq(c.zoom, ZOOM_POINT, 'zoom');
  ok(Number.isFinite(c.latitude) && Number.isFinite(c.longitude), 'NaN centre');
});

t('the centre is the midpoint of the bounding box, not of the first point', () => {
  const c = packCamera([{ lat: 37.4, lng: 126.9 }, { lat: 37.6, lng: 127.1 }, { lat: 37.5, lng: 127.0 }]);
  ok(Math.abs(c.latitude - 37.5) < 1e-9, 'lat centre ' + c.latitude);
  ok(Math.abs(c.longitude - 127.0) < 1e-9, 'lng centre ' + c.longitude);
});

t('🔴 zoom NARROWS as the pack spreads, and never leaves the declared band', () => {
  const tight = packCamera([{ lat: 37.500, lng: 127.000 }, { lat: 37.501, lng: 127.001 }]);
  const wide = packCamera([{ lat: 37.40, lng: 126.90 }, { lat: 37.60, lng: 127.10 }]);
  const huge = packCamera([{ lat: -33, lng: 151 }, { lat: 60, lng: -5 }]);
  ok(tight.zoom > wide.zoom, 'a wider pack was not zoomed out');
  for (const c of [tight, wide, huge]) {
    ok(c.zoom >= ZOOM_MIN && c.zoom <= ZOOM_MAX, 'zoom out of band: ' + c.zoom);
  }
  eq(huge.zoom, ZOOM_MIN, 'a continental spread did not clamp to ZOOM_MIN');
});

t('🔴 the same DEGREE span north-south is framed WIDER than east-west (the Mercator conversion)', () => {
  // One degree of latitude occupies ~1.26x the screen of one degree of longitude at Seoul, so the
  // same numeric span needs a wider frame north-south. Deleting the conversion makes the two
  // EQUAL — so the assertion has to be STRICT, and the fixture has to sit away from the ZOOM_MIN
  // clamp, or corrected and uncorrected agree and the pin measures nothing. (Both of those were
  // wrong in the first draft: a `>=` pin on a 0.10-degree fixture stayed green when the
  // conversion was deleted.)
  const ns = packCamera([{ lat: 37.495, lng: 127.0 }, { lat: 37.505, lng: 127.0 }]);
  const ew = packCamera([{ lat: 37.500, lng: 126.995 }, { lat: 37.500, lng: 127.005 }]);
  ok(ns.zoom > ZOOM_MIN && ew.zoom < ZOOM_MAX, 'the fixture is against a clamp: '
    + ns.zoom + ' / ' + ew.zoom);
  // ⚠ ASSERT THE MAGNITUDE, NOT THE SIGN. A bare `ew.zoom > ns.zoom` passes on the MUTATED code
  // by 2e-12: `37.505 - 37.495` and `127.005 - 126.995` are not the same double, so deleting the
  // conversion leaves floating-point dust behind and the strict comparison reads it as the
  // property holding. Measured — the mutation reddened nothing until this line was written.
  // The correct separation is exactly log2(1/cos(37.5°)) = 0.3340 zoom steps, and only the
  // conversion produces it.
  const expected = Math.log2(1 / Math.cos((37.5 * Math.PI) / 180));
  ok(Math.abs((ew.zoom - ns.zoom) - expected) < 1e-6,
    'the axis separation is ' + (ew.zoom - ns.zoom) + ', expected ' + expected);
});

// ═══ packClockOffsetMs — the viewer's clock, corrected onto the server's (addendum 1c) ═════════
// PROPERTY: freshness is judged against the clock that STAMPED the payloads, so a device whose own
// clock is wrong still sees the pack. The hazard is not a wrong label — it is an EMPTY MAP with
// nothing to report, because `parsePackPos` refuses a future-skewed stamp silently.

t('the offset is server-minus-device, in both directions, and zero when there is nothing to correct', () => {
  eq(packClockOffsetMs(iso(T0 + 20_000), T0), 20_000, 'a device running SLOW');
  eq(packClockOffsetMs(iso(T0 - 20_000), T0), -20_000, 'a device running FAST');
  eq(packClockOffsetMs(iso(T0), T0), 0, 'two agreeing clocks');
});

t('an absent or unparseable serverNow corrects nothing rather than guessing', () => {
  // A pre-0160 database simply omits the key. Correcting by a guess would be worse than not
  // correcting: the pre-0160 behaviour is the device clock, and that is what 0 restores.
  for (const bad of [null, undefined, '', 'yesterday', 42, {}])
    eq(packClockOffsetMs(bad, T0), 0, JSON.stringify(String(bad)) + ' produced a correction');
});

t('🔴 the correction is what stops a SLOW phone rendering an empty map over a running pack', () => {
  // The whole class in one experiment. A payload stamped by the server at T0 arrives at a device
  // whose clock reads 20 s EARLIER; on the raw device clock it is 20 s in the future, which is past
  // PACK_FUTURE_SKEW_MS, so the parser refuses it and nothing is drawn and nothing is reported.
  const deviceNow = T0 - 20_000;
  const payload = { ...good(), at: iso(T0) };
  ok(parsePackPos(payload, deviceNow) === null, 'the raw device clock accepted it — no bug to fix');
  const offset = packClockOffsetMs(iso(T0), deviceNow);
  ok(parsePackPos(payload, deviceNow + offset) !== null, 'the corrected clock still refused it');
  // …and the correction does not blind the refusal it exists beside: a genuinely future-stamped
  // payload is still refused ON the corrected clock. Without this arm the pin above would also pass
  // on a `packClockOffsetMs` that returned a number large enough to accept anything.
  ok(parsePackPos({ ...good(), at: iso(T0 + 3_600_000) }, deviceNow + offset) === null,
    'an hour-ahead stamp survived the corrected clock');
});

// ═══ packWindowPhase / packEmptyCopy — the state EVERY session ends in (addendum 3a) ═══════════
// PROPERTY: an empty map states which KIND of empty it is, and never promises a run that has
// already happened. Trunk fetched windowOpen/status/scheduledAt and read none of them, so the
// terminal screen of every session said 「러닝이 시작되면 여기에 나타나요」.

t('the server\'s own answer outranks every local guess: windowOpen true is `open`', () => {
  eq(packWindowPhase('open', true, iso(T0), T0), 'open', 'open session');
  // Even a status this client would call terminal: `windowOpen` is computed by `_club_pack_window`
  // and it is the only thing that decides whether positions can arrive.
  eq(packWindowPhase('done', true, iso(T0), T0), 'open', 'windowOpen was overruled locally');
});

t('🔴 a done or cancelled session is CLOSED — the terminal state, said as terminal', () => {
  eq(packWindowPhase('done', false, iso(T0), T0), 'closed', 'done');
  eq(packWindowPhase('cancelled', false, iso(T0), T0), 'closed', 'cancelled');
  // Control: the same call with a live status and the same clock does NOT say closed, so the two
  // arms above are the status doing the work rather than the function answering closed for everyone.
  eq(packWindowPhase('open', false, iso(T0), T0), 'before', 'a live session read as terminal');
});

t('before the window and inside the band a start time may be promised; past the tail it may not', () => {
  const at = iso(T0);
  eq(packWindowPhase('open', false, at, T0 - 3 * 3_600_000), 'before', 'three hours early');
  eq(packWindowPhase('open', false, at, T0 + 3_600_000), 'before', 'an hour in, nobody checked in yet');
  eq(packWindowPhase('open', false, at, T0 + PACK_WINDOW_TAIL_MS), 'before', 'exactly the tail');
  eq(packWindowPhase('open', false, at, T0 + PACK_WINDOW_TAIL_MS + 1), 'closed', 'one ms past the tail');
});

t('with no scheduled time the phase is `unknown` — closed, and we cannot say which kind', () => {
  for (const bad of [null, undefined, '', 'soon'])
    eq(packWindowPhase('open', false, bad, T0), 'unknown', JSON.stringify(String(bad)));
});

t('the client tail matches the server band it mirrors (_club_pack_window, 0159:144)', () => {
  eq(PACK_WINDOW_TAIL_MS, 6 * 3_600_000, 'the tail drifted from the migration');
});

t('🔴 NOT ONE empty-map sentence promises a run that may already be over', () => {
  // The defect stated as a property rather than as a string comparison: the old single line
  // 「러닝이 시작되면 여기에 나타나요」 was rendered for all four phases, and it is a promise in three
  // of them. A future phase added without copy would fall to the default and still pass this.
  for (const phase of ['open', 'before', 'closed', 'unknown', 'something-new']) {
    const c = packEmptyCopy(phase, iso(T0));
    ok(typeof c.title === 'string' && c.title !== '', phase + ' has no title');
    const all = c.title + ' ' + (c.body || '');
    if (phase !== 'before') ok(!/시작/.test(all), phase + ' promises a start: ' + all);
  }
});

t('each phase says its OWN cause — four different titles, not one line four times', () => {
  const titles = ['open', 'before', 'closed', 'unknown'].map((p) => packEmptyCopy(p, iso(T0)).title);
  eq(new Set(titles).size, 4, 'two phases share a sentence: ' + titles.join(' / '));
  eq(packEmptyCopy('closed', iso(T0)).title, '이 세션의 러닝이 끝났어요', 'the terminal title');
  eq(packEmptyCopy('open', iso(T0)).title, '지금 신호가 없어요', 'window open, nothing arriving');
});

t('the `before` body is the scheduled start, and absent when there is no start to state', () => {
  eq(packEmptyCopy('before', iso(T0)).body, '8월 28일 (금) 19:00 시작 예정', 'body');
  ok(packEmptyCopy('before', null).body === null, 'a start line was invented with no scheduledAt');
  ok(packEmptyCopy('closed', iso(T0)).body === null, 'the terminal state grew a second line');
});

// ═══ packStartLine — the module's ONE calendar fact, and the reason for the zone matrix ════════
// PROPERTY: the scheduled start renders as a KST wall clock on every phone in the world. These are
// literal strings; the runner executes this file under UTC, America/New_York and Asia/Seoul, and a
// device-local read would make the New_York run disagree with the other two.

t('🔴 a KST evening start renders identically in every zone the runner uses', () => {
  eq(packStartLine('2026-08-31T10:00:00.000Z'), '8월 31일 (월) 19:00 시작 예정', '19:00 KST');
});

t('🔴 an instant whose KST DATE differs from its UTC date still prints the KST one', () => {
  // 2026-08-28T22:30Z is 08-29 07:30 in KST, 08-28 18:30 in New_York and 08-28 22:30 in UTC — the
  // three zones disagree on the DAY and on the WEEKDAY, which is exactly the class that shipped
  // unnoticed once already. Only the KST answer is correct here.
  eq(packStartLine('2026-08-28T22:30:00.000Z'), '8월 29일 (토) 07:30 시작 예정', 'day boundary');
});

t('a missing or unparseable scheduled time yields no line rather than an invented one', () => {
  for (const bad of [null, undefined, '', 'tomorrow', 42, {}])
    ok(packStartLine(bad) === null, JSON.stringify(String(bad)) + ' produced a start line');
});

// ═══ packShareLine — one sentence about the local user, four situations (addendum 3) ═══════════
// PROPERTY: the line says what we measured and never names a cause we did not. `usePackShare`'s
// boolean is frozen, so the CAUSE arrives separately; an unrecognised cause must land in the
// honest neutral branch rather than being guessed at.

t('the three measured answers, before any cause is consulted', () => {
  eq(packShareLine(null, null, false), '내 위치 확인 중...', 'not measured');
  eq(packShareLine(true, null, false), '내 위치 공유 중', 'on the map');
  eq(packShareLine(false, null, false), '아직 지도에 안 올라갔어요', 'refused, cause unknown');
});

t('🔴 the two causes the screen is allowed to NAME, and only those two', () => {
  eq(packShareLine(false, 'no_fix', false), '내 위치 잡히는 중', 'no fix yet');
  eq(packShareLine(false, 'window_closed', false), '위치 공유 시간이 끝났어요', 'window closed');
  // Every other refusal keeps the cause-neutral line. This is the arm that stops the branch
  // re-acquiring the right to name GPS for a server refusal — the defect it was written to fix.
  for (const c of ['not_signed_in', 'not_checked_in', 'bad_position', 'not_delivered',
    'not_deployed', 'too_fast', 'threw', 'unknown', 'a_refusal_from_the_future', null])
    eq(packShareLine(false, c, false), '아직 지도에 안 올라갔어요', 'cause ' + c);
});

t('🔴 a viewer-only reader is told they are watching, whatever the publish loop says', () => {
  // It is a statement about WHO YOU ARE, not about a publish attempt, so it outranks the others:
  // an anon viewer never publishes, and 「확인 중」 there is a measurement that will never arrive.
  for (const [shared, cause] of [[null, null], [false, 'no_fix'], [false, 'window_closed'], [true, null]])
    eq(packShareLine(shared, cause, true), '보기만 하는 중', JSON.stringify([shared, cause]));
  // Control: the same inputs with viewerOnly false do NOT all collapse to one line, so the pin
  // above is the flag doing the work and not the function answering 보기만 for everybody.
  ok(packShareLine(null, null, false) !== '보기만 하는 중', 'viewerOnly=false also said 보기만');
});

// ═══ packCaption — name · 러너 · age (addendum 3c) ══════════════════════════════════════════════
// PROPERTY: the caption states the role the roster gave and the age only when the marker is
// already being drawn faintly. 러너 is a caption affix and nothing else — role-distinct marker
// assets are deferred (3f) and are deliberately not faked here.

const MK = (over) => ({ profileId: 'p-1', name: '민수', lat: 37.5, lng: 127, atMs: T0, isRunner: false, ...over });

t('a fresh non-runner is just their name — no age, no affix', () => {
  eq(packCaption(MK(), T0), '민수', 'fresh');
  eq(packCaption(MK(), T0 + PACK_FRESH_MS), '민수', 'exactly fresh');
});

t('🔴 the 러너 affix comes from the ROSTER flag, and the age only in the stale band', () => {
  eq(packCaption(MK({ isRunner: true }), T0), '민수 · 러너', 'runner, fresh');
  // 90 s past the stamp: one whole minute of age, and past PACK_FRESH_MS so the marker is faint.
  eq(packCaption(MK({ isRunner: true }), T0 + 90_000), '민수 · 러너 · 1분 전', 'runner, stale');
  eq(packCaption(MK(), T0 + 90_000), '민수 · 1분 전', 'non-runner, stale');
});

t('the clock defaults to the real one — the injected clock is a test seam, not the rule', () => {
  const now = Date.now();
  ok(parsePackPos({ ...good(), at: new Date(now).toISOString() }) !== null,
    'a payload stamped NOW was refused by the default clock');
  ok(parsePackPos({ ...good(), at: new Date(now + 3_600_000).toISOString() }) === null,
    'an hour-ahead payload was accepted by the default clock');
});

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
