// 팩 지도 (club-session pack map) — the pure half.
//
// WHY THIS FILE IS SEPARATE FROM THE SCREEN. `app/test/*.cjs` can bundle a `.ts` module with
// esbuild and cannot import a `.tsx` route module at all (CLAUDE.md, the check-device-clock
// entry). So every decision this feature makes that CAN be tested lives here — payload
// validation, staleness, the camera fit — and `club/map/[sid].tsx` is left with rendering.
// A rule that lives in the screen is a rule with no pin.
//
// CONTRACT (fixed by the coordinator; the server half is built against the same one):
//   topic    `pack-<sessionId>`, realtime BROADCAST, event `pos`
//   payload  { profileId, name, lat, lng, at }   with `at` an ISO string
//   subscribe always · publish only while the local user is a session participant with a live run
//
// RULING PROVENANCE. Sean, 2026-08-28, verbatim: 「everyone should see everyone else on the map
// during a club run session with a little runner icon. total public; everything that's not their
// password is public to anyone.」 and, on sequencing, 「Build it now anyway」. Recorded in
// `docs/decisions/2026-08-28-sean-rulings.md` (both rounds). Not re-opened here.

/** Broadcast topic for one club session. One definition, because three call sites drift.
 *  (`geo.ts`'s own comment on `run2-` records what a scattered topic string costs: the next
 *  bump leaves one behind, and the symptom is a silently empty map.) */
export const PACK_TOPIC = (sessionId: string): string => `pack-${sessionId}`;

/** The broadcast event name inside that topic. */
export const PACK_EVENT = 'pos';

/** One participant's position as it travels on the wire. */
export interface PackPos {
  profileId: string;
  name: string;
  lat: number;
  lng: number;
  /** ISO 8601, produced by the publisher's own device. */
  at: string;
}

/** A peer as the screen holds it: the wire payload plus the parsed instant. */
export interface PackPeer extends PackPos {
  /** epoch ms parsed from `at` — an EPOCH delta, never a KST fact (see the note below). */
  atMs: number;
}

// ---------------------------------------------------------------------------------------------
// Time. Everything here is an epoch DELTA — "how long ago" — never a calendar fact, so it does
// not go through `kst.ts` and does not trip `check-device-clock`. `Date.parse` and `Date.now`
// are the epoch-safe family the gate deliberately does not match (CLAUDE.md §Commit gate).
// ---------------------------------------------------------------------------------------------

/** A fix this new is drawn at full strength. Chosen against `startTracking`'s own cadence
 *  (timeInterval 2000 / distanceInterval 5) plus the 3 s publish throttle, with headroom for
 *  one dropped message. */
export const PACK_FRESH_MS = 60_000;

/** Past this, a peer is dropped from the map entirely. A ten-minute-old point drawn as a live
 *  marker is the map claiming knowledge it does not have — the honesty law, not a preference.
 *  Between FRESH and STALE the marker is still drawn, dimmed, and captioned with its age. */
export const PACK_STALE_MS = 300_000;

/** The local user stops publishing once their own newest fix is older than this. A runner who
 *  stands still legitimately produces no fix for a while (distanceInterval 5 m), so this is
 *  deliberately looser than PACK_FRESH_MS — but it is finite, because re-broadcasting a fix
 *  from ten minutes ago says "I am here" about a place we left. */
export const PACK_PUBLISH_MAX_FIX_AGE_MS = 120_000;

/**
 * How far ahead of us a payload's own timestamp may sit before we refuse it outright.
 *
 * 🔴 THIS IS NOT COSMETIC, and the no-op it replaced is why it is written down. `mergePeer` is
 * newest-wins and `visiblePeers` sorts on the same field, so ONE payload stamped an hour into the
 * future pins that marker at the top of the map permanently: every honest later message from the
 * same person is "older" and is discarded. Nothing in the product would look broken. A future
 * timestamp is already a live class in this repo — the run-end money review found a runner could
 * mint inflated earnings with a future-stamped trace — and on a channel whose writes carry no
 * server gate it is the cheapest possible attack.
 *
 * The tolerance exists because two honest phones disagree by seconds — NTP-synced devices sit
 * inside a second or two, so 15 s is already generous. Past it we cannot draw the point honestly,
 * so we do not draw it at all.
 *
 * ⚠ IT MUST BE STRICTLY TIGHTER THAN `PACK_FRESH_MS`, and the first value written here was not:
 * at 60 s it EQUALLED the fresh window, so a payload stamped 60 s ahead stayed at full strength
 * for 120 s of wall time — twice the freshness the window promises, chosen by the sender. The pin
 * that says so was written before the number was checked and went red on it.
 */
export const PACK_FUTURE_SKEW_MS = 15_000;

/** Publish throttle. The same 3 s the 1:1 live share uses (`geo.ts` PUB_MIN_MS) — the map gains
 *  nothing from sub-3-second updates and the runner's battery and the Realtime quota lose. */
export const PACK_PUB_MIN_MS = 3_000;

export type PeerAge = 'fresh' | 'stale' | 'gone';

export function peerAge(atMs: number, nowMs: number): PeerAge {
  const d = nowMs - atMs;
  // A slightly-future stamp (clock skew inside PACK_FUTURE_SKEW_MS) lands here as `fresh`, which
  // is what a negative delta produces anyway. Anything FURTHER ahead never reaches this function:
  // `parsePackPos` refuses it, for the reason written there.
  if (d <= PACK_FRESH_MS) return 'fresh';
  if (d <= PACK_STALE_MS) return 'stale';
  return 'gone';
}

/** "N분 전" / "방금" for a stale marker's caption. Minutes only — a seconds counter on a map
 *  marker is noise, and this string only ever renders for a peer we have already said is not
 *  current. */
export function agoLabel(atMs: number, nowMs: number): string {
  const sec = Math.floor((nowMs - atMs) / 1000);
  if (sec < 60) return '방금';
  return `${Math.floor(sec / 60)}분 전`;
}

// ---------------------------------------------------------------------------------------------
// Payload validation. Everything arriving on this channel is untrusted: the contract says reads
// are public and no auth gate stands on subscribe, so nothing stops a malformed — or invented —
// payload. A parser that returns null is the whole defence the client can mount, and it is the
// reason `parsePackPos` is a pure function with pins rather than a few `if`s inside a render.
// ---------------------------------------------------------------------------------------------

const isFiniteNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);

/**
 * Validate one broadcast payload. Returns null for anything that cannot be drawn honestly.
 *
 * ⚠ (0, 0) IS REJECTED ON PURPOSE. Null Island is 2,000 km off West Africa; nobody in this
 * product is ever there, and a zeroed struct is exactly what an uninitialised position looks
 * like. "Unknown position renders as absent, never as (0,0)" — so the parser refuses it here
 * rather than letting the map draw a confident marker in the Atlantic.
 */
export function parsePackPos(raw: unknown, nowMs: number = Date.now()): PackPeer | null {
  if (!raw || typeof raw !== 'object') return null;
  const o = raw as Record<string, unknown>;

  const profileId = typeof o.profileId === 'string' ? o.profileId.trim() : '';
  if (!profileId) return null;

  if (!isFiniteNum(o.lat) || !isFiniteNum(o.lng)) return null;
  const lat = o.lat;
  const lng = o.lng;
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
  if (lat === 0 && lng === 0) return null; // see the note above

  if (typeof o.at !== 'string') return null;
  const atMs = Date.parse(o.at);
  if (!Number.isFinite(atMs)) return null;
  if (atMs - nowMs > PACK_FUTURE_SKEW_MS) return null; // see PACK_FUTURE_SKEW_MS

  // A missing name is not a reason to hide someone from the map — it is a reason not to invent
  // one. The caption falls back to 참가자, which is what we actually know.
  const rawName = typeof o.name === 'string' ? o.name.trim() : '';
  const name = rawName === '' ? '참가자' : rawName;

  return { profileId, name, lat, lng, at: o.at, atMs };
}

/**
 * Fold one parsed payload into the peer table, newest-wins per profile.
 *
 * Returns a NEW map when it changed and the SAME map when it did not, so a caller can use the
 * identity to decide whether to re-render. An out-of-order delivery (Realtime does not promise
 * ordering) must not move a marker backwards in time.
 */
export function mergePeer(
  peers: ReadonlyMap<string, PackPeer>,
  next: PackPeer,
): Map<string, PackPeer> {
  const cur = peers.get(next.profileId);
  if (cur && cur.atMs >= next.atMs) return peers as Map<string, PackPeer>;
  const out = new Map(peers);
  out.set(next.profileId, next);
  return out;
}

/** Everyone still drawable, newest first, with anyone past PACK_STALE_MS dropped. */
export function visiblePeers(
  peers: ReadonlyMap<string, PackPeer>,
  nowMs: number,
): PackPeer[] {
  const out: PackPeer[] = [];
  for (const p of peers.values()) {
    if (peerAge(p.atMs, nowMs) !== 'gone') out.push(p);
  }
  out.sort((a, b) => b.atMs - a.atMs);
  return out;
}

// ---------------------------------------------------------------------------------------------
// Camera. Same shape as the one owner/live.tsx computes inline; it lives here so it has pins.
// ---------------------------------------------------------------------------------------------

export interface PackCamera { latitude: number; longitude: number; zoom: number }

/** Widest zoom we will ever choose, and the tightest. A single point gets `ZOOM_POINT` — close
 *  enough to read the street, not so close that the next fix jumps off screen. */
export const ZOOM_MIN = 11;
export const ZOOM_MAX = 17;
export const ZOOM_POINT = 15.5;

/**
 * A camera that contains every point given.
 *
 * ⚠ The zoom is APPROXIMATE and deliberately conservative. `owner/live.tsx` records that Naver's
 * SDK draws about one step tighter than the standard Mercator formula predicts (MAP_ZOOM_TRIM,
 * from a simulator measurement), so this errs wide: a pack half off-screen is a broken map, a
 * pack drawn slightly too small is a legible one. Returns null for no points — the caller must
 * then say "nobody is on the map yet" rather than centring on a guess.
 */
export function packCamera(pts: ReadonlyArray<{ lat: number; lng: number }>): PackCamera | null {
  if (pts.length === 0) return null;
  let minLat = pts[0].lat, maxLat = pts[0].lat, minLng = pts[0].lng, maxLng = pts[0].lng;
  for (const p of pts) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lng < minLng) minLng = p.lng;
    if (p.lng > maxLng) maxLng = p.lng;
  }
  const latitude = (minLat + maxLat) / 2;
  const longitude = (minLng + maxLng) / 2;

  // The zoom formula below is in DEGREES OF LONGITUDE (a Mercator viewport shows 360° of them at
  // zoom 0), so the north-south extent has to be converted into that unit before the two can be
  // compared. On a Mercator map at latitude φ, one degree of LATITUDE occupies 1/cos(φ) as much
  // screen as one degree of longitude — ~1.26× at Banpo (37.5°N).
  // ⚠ Without this conversion a north-south pack is framed TOO TIGHT and the outermost runners
  // fall off the top and bottom. (The first draft of this line scaled the longitude term by
  // cos(φ) instead, which picks the same winner and then applies the factor to the answer — the
  // frame was uniformly ~0.33 steps wide and the two axes were never actually compared. It was
  // found by a mutation that deleted the correction and reddened nothing.)
  const dLat = (maxLat - minLat) / Math.cos((latitude * Math.PI) / 180);
  const dLng = maxLng - minLng;
  const span = Math.max(dLat, dLng);
  if (span <= 0) return { latitude, longitude, zoom: ZOOM_POINT };

  // 360° of longitude at zoom 0; one step per halving. `* 1.6` is the padding that keeps the
  // outermost runner off the bezel — the same intent as owner/live's MAP_FIT_PAD, larger here
  // because this map has no bottom island reserving space for it.
  const zoom = Math.log2(360 / (span * 1.6));
  return { latitude, longitude, zoom: Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, zoom)) };
}
