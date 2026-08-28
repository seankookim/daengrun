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
const {
  PACK_TOPIC, PACK_EVENT, PACK_FRESH_MS, PACK_STALE_MS, PACK_PUBLISH_MAX_FIX_AGE_MS,
  PACK_PUB_MIN_MS, PACK_FUTURE_SKEW_MS, ZOOM_MIN, ZOOM_MAX, ZOOM_POINT,
  parsePackPos, peerAge, agoLabel, mergePeer, visiblePeers, packCamera,
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
// PROPERTY: each participant has exactly one marker, showing their newest known position.
// Realtime does not promise ordering, so an old message arriving late must not move a marker
// backwards in time.

t('a new profile is added; the same profile is replaced, not duplicated', () => {
  const a = P(good());
  const b = P({ ...good(), at: iso(T0 + 5000), lat: 37.51 });
  const m1 = mergePeer(new Map(), a);
  eq(m1.size, 1, 'first insert');
  const m2 = mergePeer(m1, b);
  eq(m2.size, 1, 'same profile duplicated');
  eq(m2.get('p-1').lat, 37.51, 'newer position not adopted');
});

t('🔴 an OUT-OF-ORDER (older) delivery does not move the marker backwards', () => {
  const newer = P({ ...good(), at: iso(T0 + 5000), lat: 37.51 });
  const older = P({ ...good(), at: iso(T0), lat: 37.40 });
  const m = mergePeer(mergePeer(new Map(), newer), older);
  eq(m.get('p-1').lat, 37.51, 'an older message overwrote a newer one');
});

t('an unchanged merge returns the SAME map object, so a caller can skip a re-render', () => {
  const newer = P({ ...good(), at: iso(T0 + 5000) });
  const older = P({ ...good(), at: iso(T0) });
  const m1 = mergePeer(new Map(), newer);
  ok(mergePeer(m1, older) === m1, 'a no-op merge allocated a new map');
  // …and a real change must NOT reuse it, or React would never see the update.
  const other = P({ ...good(), profileId: 'p-2' });
  ok(mergePeer(m1, other) !== m1, 'a real change reused the old map');
});

t('two different profiles both stay on the map', () => {
  const a = P(good());
  const b = P({ ...good(), profileId: 'p-2', name: '지연' });
  eq(mergePeer(mergePeer(new Map(), a), b).size, 2, 'a second person was swallowed');
});

// ═══ visiblePeers ══════════════════════════════════════════════════════════════════════════════

t('peers past STALE are dropped; fresh and stale ones survive, newest first', () => {
  const mk = (id, ageMs) => P({ ...good(), profileId: id, at: iso(T0 - ageMs) }, T0);
  let m = new Map();
  for (const [id, age] of [['fresh', 1000], ['stale', PACK_FRESH_MS + 5000], ['gone', PACK_STALE_MS + 5000]]) {
    m = mergePeer(m, mk(id, age));
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

t('the clock defaults to the real one — the injected clock is a test seam, not the rule', () => {
  const now = Date.now();
  ok(parsePackPos({ ...good(), at: new Date(now).toISOString() }) !== null,
    'a payload stamped NOW was refused by the default clock');
  ok(parsePackPos({ ...good(), at: new Date(now + 3_600_000).toISOString() }) === null,
    'an hour-ahead payload was accepted by the default clock');
});

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail ? 1 : 0);
