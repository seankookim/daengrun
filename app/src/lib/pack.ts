// 팩 지도 (club-session pack map) — the pure half.
//
// WHY THIS FILE IS SEPARATE FROM THE SCREEN. `app/test/*.cjs` can bundle a `.ts` module with
// esbuild and cannot import a `.tsx` route module at all (CLAUDE.md, the check-device-clock
// entry). So every decision this feature makes that CAN be tested lives here — payload
// validation, staleness, the camera fit — and `club/map/[sid].tsx` is left with rendering.
// A rule that lives in the screen is a rule with no pin.
//
// CONTRACT (0160 — `docs/contracts/pack-publish-hardening-contract.md`):
//   topic    `pack-<sessionId>`, realtime BROADCAST, event `pos`, joined PRIVATE
//   payload  { id, profileId, name, lat, lng, at } — authored ENTIRELY by `club_pack_publish`
//   subscribe always · publishing is an RPC, so no client can author an identity at all
//
// ⚠ WHAT CHANGED IN 0160 AND WHY THE PARSER STAYED. Before 0160 a client wrote the payload onto a
// socket, so `parsePackPos` was the whole defence: codex #4 (payload identity forgeable) is closed
// STRUCTURALLY now — the `pack channel write` policy is dropped and the only writer is a definer
// RPC that takes `profileId` from `auth.uid()`. The parser is kept anyway, as a belt: it is what
// stops a malformed or out-of-range row from being drawn as a confident marker, and a validator
// deleted because 「the server is trustworthy now」 is a validator nobody re-adds when a new writer
// appears. It is no longer the identity gate — `mergePeer`'s roster set is (codex #5).
//
// RULING PROVENANCE. Sean, 2026-08-28, verbatim: 「everyone should see everyone else on the map
// during a club run session with a little runner icon. total public; everything that's not their
// password is public to anyone.」 and, on sequencing, 「Build it now anyway」. Recorded in
// `docs/decisions/2026-08-28-sean-rulings.md` (both rounds). Not re-opened here.
//
// ⚠ THIS MODULE NOW OWNS ONE CALENDAR FACT AND THEREFORE HAS A ZONE (addendum 3a). Everything else
// in here is an epoch DELTA — 「how long ago」 — but `packStartLine` prints a session's scheduled
// START, which is a KST wall-clock fact. It goes through `kst.ts` (fixed +9, no Intl) and NEVER
// through a device-local getter, and `run-pack-tests.sh` gained a New_York arm the same day,
// because a Seoul-only run is structurally incapable of seeing that class (CLAUDE.md §Commit gate).

import { kstCal, kstClock, kstDateLabel } from './kst';

/** Broadcast topic for one club session. One definition, because three call sites drift.
 *  (`geo.ts`'s own comment on `run2-` records what a scattered topic string costs: the next
 *  bump leaves one behind, and the symptom is a silently empty map.) */
export const PACK_TOPIC = (sessionId: string): string => `pack-${sessionId}`;

/** The broadcast event name inside that topic. */
export const PACK_EVENT = 'pos';

/** One participant's position as it travels on the wire. Authored server-side by
 *  `club_pack_publish` (0160 §A) — no client builds one of these any more. */
export interface PackPos {
  profileId: string;
  name: string;
  lat: number;
  lng: number;
  /** ISO 8601 UTC, stamped by the RPC's own `now()`. */
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

/**
 * How long an entry may sit in the peer table after its last position before it is EVICTED —
 * removed from the Map, not merely hidden.
 *
 * 🔴 IT IS A DIFFERENT JOB FROM `PACK_STALE_MS` AND THAT IS WHY IT IS A SECOND NUMBER. Past STALE
 * a peer stops being DRAWN (`visiblePeers`); nothing about that shrinks the table, so before 0160
 * the Map grew for the life of the screen — codex #5, an unbounded retention whose only visible
 * symptom is memory. Eviction is the half that frees it.
 *
 * ⚠ It MUST be looser than STALE, or a peer would be evicted while still drawable and would flicker
 * back in on their next broadcast. Deliberately generous (10 min): re-adding an evicted peer costs
 * one message, and the table is already bounded by the roster (see `mergePeer`), so the only thing
 * this number buys is releasing a runner who has genuinely left.
 */
export const PACK_PEER_EVICT_MS = 600_000;

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
 * ⚠ 0160 narrowed the ATTACK but not the RULE. `at` is now the server's `now()`, so a future stamp
 * can no longer be chosen by a sender; what remains is a RECEIVER whose own clock runs slow, and
 * this refusal is still the only thing between that and a permanently pinned marker.
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

/**
 * The viewer's clock, corrected onto the SERVER's — `serverNow` (from `club_pack_map_roster`)
 * minus the device epoch at the moment that answer arrived. Every freshness decision on this map
 * is then made against `Date.now() + offset`.
 *
 * 🔴 WITHOUT IT A SLOW PHONE SEES AN EMPTY MAP AND IS TOLD NOTHING (addendum 1c). Since 0160 every
 * `at` is stamped by ONE clock — the database's — so a viewer whose phone is 20 s behind reads
 * every payload as 20 s in the FUTURE, `parsePackPos` refuses all of them past
 * `PACK_FUTURE_SKEW_MS`, and the screen renders 「아직 아무도 달리고 있지 않아요」 over a pack that
 * is running. Nothing errors. That is the silent-feature-loss shape this repo has now met three
 * times, and widening the skew constant would MASK it rather than fix it: the skew tolerance is
 * there for two honest clocks disagreeing by seconds, not for a device that is simply wrong.
 *
 * Returns 0 — 「no correction」 — for an absent or unparseable stamp, which is exactly the answer a
 * pre-0160 database produces (the key is simply missing) and is the same behaviour as before.
 *
 * ⚠ It is biased by roughly the response leg of the round trip: `serverNow` was stamped before the
 * answer travelled, so the correction is a fraction of a second short and peers read a fraction of
 * a second FRESHER than they are. Against a 15 s tolerance and a 60 s freshness window that is
 * noise, and correcting for it would need a round-trip measurement this screen does not take.
 */
export function packClockOffsetMs(serverNowIso: string | null, deviceNowMs: number): number {
  if (typeof serverNowIso !== 'string' || serverNowIso === '') return 0;
  const ms = Date.parse(serverNowIso);
  if (!Number.isFinite(ms)) return 0;
  return ms - deviceNowMs;
}

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
// Payload validation. Everything arriving on this channel is still treated as untrusted, for the
// reason in the header: 0160 made the WRITE side structural, and a parser deleted on that basis is
// a parser nobody re-adds when a new writer appears. A parser that returns null is the cheapest
// defence the client can mount, and it is the reason `parsePackPos` is a pure function with pins
// rather than a few `if`s inside a render.
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
 *
 * 🔴 `allowed` IS THE MAP'S ONLY BOUND (codex #5). It is the set of profile ids the SERVER roster
 * named for this session; a payload for anyone else is dropped rather than stored, so the table
 * can never hold more entries than the roster has people no matter how many messages arrive. That
 * is a different property from 「the marker is drawn」 — `visiblePeers` hides an old peer and does
 * not shrink anything, which is exactly how the unbounded growth survived review.
 *
 * ⚠ `null` MEANS ALLOW ALL AND EXISTS FOR THE PINS. A screen must pass a real set — an empty one
 * while the roster is still loading, which drops a message or two and is repaired by the next
 * broadcast 3 s later. Passing `null` from a screen would restore the unbounded table.
 *
 * ═══ WHY 「EMPTY SET BEFORE THE FIRST ROSTER」 AND 「ALLOW-ALL BEFORE THE FIRST ROSTER」 CONVERGE ══
 * (addendum 2b, written down because the two read as opposite policies and are not.)
 * They differ in exactly one place — what is RETAINED — and in no place at all in what is DRAWN,
 * because `packMarkers` drops any peer with no roster row a SECOND time on the way to the screen.
 * That is the property the 「a peer with no roster row is not drawn」 pin holds, and it is why the
 * screen may pick the empty set: before the roster lands, allow-all would let a flood into the
 * table (the unbounded map, codex #5) and still draw nobody, while the empty set draws the same
 * nobody and keeps the table bounded in that window too. The cost of the empty set is a message or
 * two dropped in the first seconds; the publisher re-sends 3 s later.
 *
 * ⚠ NAMED ACCEPTED PROPERTY, not a bug: a person who checks in AFTER the screen's last roster
 * fetch is invisible for up to ~33 s (a 30 s roster tick plus a 3 s publish tick). Their broadcasts
 * are refused here because the roster we hold does not name them yet, and the next roster admits
 * them. Shortening it means polling the roster harder, which is a real cost for a bounded and
 * self-healing delay — so the delay is stated rather than engineered away.
 */
export function mergePeer(
  peers: ReadonlyMap<string, PackPeer>,
  next: PackPeer,
  allowed: ReadonlySet<string> | null,
): Map<string, PackPeer> {
  if (allowed !== null && !allowed.has(next.profileId)) return peers as Map<string, PackPeer>;
  const cur = peers.get(next.profileId);
  if (cur && cur.atMs >= next.atMs) return peers as Map<string, PackPeer>;
  const out = new Map(peers);
  out.set(next.profileId, next);
  return out;
}

/**
 * Drop every peer whose newest position is older than `PACK_PEER_EVICT_MS`.
 *
 * Referentially stable like `mergePeer`: the SAME map comes back when nothing was evicted, so a
 * caller can put this on a timer without re-rendering on every tick. A peer evicted while still
 * running reappears on their next broadcast — eviction costs a message, never truth.
 */
export function prunePeers(
  peers: ReadonlyMap<string, PackPeer>,
  nowMs: number,
): Map<string, PackPeer> {
  let doomed: string[] | null = null;
  for (const p of peers.values()) {
    if (nowMs - p.atMs > PACK_PEER_EVICT_MS) (doomed ??= []).push(p.profileId);
  }
  if (doomed === null) return peers as Map<string, PackPeer>;
  const out = new Map(peers);
  for (const id of doomed) out.delete(id);
  return out;
}

// ---------------------------------------------------------------------------------------------
// Roster precedence. `club_pack_map_roster` (0159 §D) is the authoritative list of who is on this
// map; the broadcast contributes POSITION and FRESHNESS and nothing else. Splitting it this way is
// what makes 「which name is on that dot」 answerable from one place even if the payload's own
// `name` ever drifts from `profiles.name` — the payload is server-authored since 0160, so today
// they agree, and a rule that only holds while two sources agree is not a rule.
// ---------------------------------------------------------------------------------------------

/** The fields the map needs from one roster person. Declared HERE, structurally, rather than
 *  imported from `api.ts`: this module is bundled by esbuild for the pins and must not pull in
 *  supabase-js. `api.ts`'s `PackRosterPerson` satisfies it. */
export interface PackRosterEntry {
  profileId: string;
  /** `profiles.name`, which is genuinely nullable — a missing name is a reason not to invent one. */
  name: string | null;
  /** `session_people.role` says this person runs somebody else's dog. It rides the caption and
   *  nothing else (addendum 3c): the data already crosses the wire, and a role-distinct marker
   *  ASSET is deferred work (3f), so the honest half is shipped and the rest is not faked. */
  isRunner: boolean;
}

/** One drawable marker: identity and caption from the ROSTER, position and instant from the
 *  broadcast. */
export interface PackMarker {
  profileId: string;
  name: string;
  lat: number;
  lng: number;
  atMs: number;
  isRunner: boolean;
}

/** Index a roster once per fetch: `ids` is what `mergePeer` gates on, `byId` is what the caption
 *  reads. One pass, one definition — two derivations of the same list is how a screen ends up
 *  drawing someone it decided not to admit. */
export function packRosterIndex(people: ReadonlyArray<PackRosterEntry>): {
  ids: Set<string>;
  byId: Map<string, PackRosterEntry>;
} {
  const ids = new Set<string>();
  const byId = new Map<string, PackRosterEntry>();
  for (const p of people) {
    if (typeof p?.profileId !== 'string' || p.profileId === '') continue;
    ids.add(p.profileId);
    byId.set(p.profileId, p);
  }
  return { ids, byId };
}

/** Join drawable peers to the roster. A peer with no roster row is DROPPED rather than captioned
 *  from the payload: `mergePeer` should already have refused it, and drawing it here would be the
 *  screen quietly re-admitting what the gate refused. A roster row with a null name captions as
 *  참가자 — what we actually know. */
export function packMarkers(
  peers: ReadonlyArray<PackPeer>,
  byId: ReadonlyMap<string, PackRosterEntry>,
): PackMarker[] {
  const out: PackMarker[] = [];
  for (const p of peers) {
    const person = byId.get(p.profileId);
    if (!person) continue;
    const nm = typeof person.name === 'string' ? person.name.trim() : '';
    out.push({
      profileId: p.profileId, name: nm === '' ? '참가자' : nm,
      lat: p.lat, lng: p.lng, atMs: p.atMs, isRunner: person.isRunner === true,
    });
  }
  return out;
}

/**
 * The whole caption under one marker: name, then 러너 when the roster says so, then the age when
 * the marker is already being drawn faintly.
 *
 * It is a function rather than a template in the screen for the reason the rest of this file
 * exists: the screen cannot be reached by a pin, and 「a stale marker states its age」 is a rule.
 * The age is appended ONLY in the stale band — a 「방금」 on every fresh marker is noise, and this
 * string's whole job is to stop a faint dot reading as a current position.
 */
export function packCaption(m: PackMarker, nowMs: number): string {
  let out = m.name;
  if (m.isRunner) out += ' · 러너';
  if (peerAge(m.atMs, nowMs) === 'stale') out += ' · ' + agoLabel(m.atMs, nowMs);
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

// ---------------------------------------------------------------------------------------------
// What the screen SAYS. These are pure so the copy has pins — the map screen is a `.tsx` route
// module and no `.cjs` suite can reach it, so a sentence built inside the render is a sentence
// nothing checks. Each helper answers one question and every branch is a fact we hold.
// ---------------------------------------------------------------------------------------------

/**
 * The upper edge of the server's pack window, in ms after `scheduled_at`.
 *
 * ⚠ IT IS A SECOND COPY OF A SERVER NUMBER (`_club_pack_window`, 0159:144 — `now() <=
 * s.scheduled_at + interval '6 hours'`), and it is written here on purpose with its blast radius
 * bounded: it NEVER decides whether the window is open — `roster.windowOpen` is the only answer to
 * that — it only chooses which of two SENTENCES to print once the server has already said closed.
 * If the migration's band ever moves, the worst this constant can do is print 「끝났어요」 slightly
 * early or 「시작 예정」 slightly late; it cannot show or hide a position.
 */
export const PACK_WINDOW_TAIL_MS = 6 * 3_600_000;

/** Where this session sits relative to its pack window, as the CLIENT can honestly answer it. */
export type PackWindowPhase =
  /** the server says the window is open */
  | 'open'
  /** terminal: the session is done/cancelled, or the window's inaction band has run out */
  | 'closed'
  /** the window has not opened yet and can still open — a start time may be stated */
  | 'before'
  /** closed, and we hold nothing that says which of the two it is */
  | 'unknown';

/**
 * 🔴 THIS IS THE FIX FOR THE STATE EVERY SESSION ENDS IN (addendum 3a). `windowOpen` / `status` /
 * `scheduledAt` were fetched and never read, so a finished session rendered 「러닝이 시작되면 여기에
 * 나타나요」 — a promise about a run that already happened, on the terminal screen of every session
 * this product will ever run.
 *
 * The order of the arms is the argument:
 *   1. `windowOpen` is the SERVER's answer and outranks every local guess.
 *   2. `done` / `cancelled` is a fact that has already happened — terminal, unambiguous.
 *   3. Past the band's tail, nothing can re-open the window, so it is terminal too.
 *   4. Otherwise the window may still open (the commonest cause of a closed window inside the band
 *      is that nobody has checked in YET, `_club_pack_window` ②) and a start time is honest.
 *
 * ⚠ ARM 4 IS THE ONE THAT CAN BE WRONG, and it is stated rather than hidden: a host who ends the
 * runs without finishing the session leaves `status='open'` inside the band with the window shut,
 * and this reads it as 「not started yet」. The client holds nothing that separates that from 「nobody
 * has checked in」 — `run_ended_at` is not on the roster — so the addendum chose the reading that is
 * right in the ordinary case. It is a wrong SENTENCE in a transient state, never a wrong map.
 */
export function packWindowPhase(
  status: string | null,
  windowOpen: boolean,
  scheduledAtIso: string | null,
  nowMs: number,
): PackWindowPhase {
  if (windowOpen) return 'open';
  if (status === 'done' || status === 'cancelled') return 'closed';
  const at = typeof scheduledAtIso === 'string' ? Date.parse(scheduledAtIso) : NaN;
  if (!Number.isFinite(at)) return 'unknown';
  return nowMs > at + PACK_WINDOW_TAIL_MS ? 'closed' : 'before';
}

/** 「8월 31일 (월) 19:00 시작 예정」 — the scheduled start as a KST wall clock.
 *
 *  ⚠ THROUGH `kst.ts`, NEVER THROUGH THE DEVICE CLOCK. `new Date(iso).getHours()` prints whatever
 *  zone the phone is in, and `check-device-clock` refuses it; the fixed +9 arithmetic has no Intl
 *  dependency and no fallback branch, so there is no second copy of this sentence to drift. */
export function packStartLine(scheduledAtIso: string | null): string | null {
  if (typeof scheduledAtIso !== 'string' || scheduledAtIso === '') return null;
  const ms = Date.parse(scheduledAtIso);
  if (!Number.isFinite(ms)) return null;
  const c = kstCal(ms);
  return `${kstDateLabel(c)} ${kstClock(c)} 시작 예정`;
}

export interface PackEmptyCopy {
  title: string;
  /** null when there is nothing further we actually know. An empty second line beats an invented one. */
  body: string | null;
}

/**
 * What an empty map says, given the window phase. Four different facts that all look like 「나갈 게
 * 없다」 on screen, so each says its own cause.
 *
 * ⚠ NOT ONE OF THESE PROMISES A FUTURE. 「러닝이 시작되면 여기에 나타나요」 was the old single line
 * for all four, and it is a promise the screen cannot keep in three of them.
 */
export function packEmptyCopy(phase: PackWindowPhase, scheduledAtIso: string | null): PackEmptyCopy {
  switch (phase) {
    case 'open':
      // The window IS open and nothing has arrived. That is a measurement, not a wait.
      return { title: '지금 신호가 없어요', body: '위치가 도착하면 바로 나타나요' };
    case 'before':
      return { title: '아직 러닝이 시작되지 않았어요', body: packStartLine(scheduledAtIso) };
    case 'closed':
      return { title: '이 세션의 러닝이 끝났어요', body: null };
    default:
      // Closed, and we cannot say which kind of closed. State only the part we hold.
      return { title: '지금은 팩 지도가 열려 있지 않아요', body: null };
  }
}

/**
 * The one line that says whether the LOCAL user's position is on this map.
 *
 * ⚠ `cause` IS WHY THIS FUNCTION EXISTS (addendum 3, design F8). `usePackShare` returns a frozen
 * `boolean | null` — three live call sites — so `false` alone cannot tell 「my GPS has not produced
 * a fix yet」 from 「the window closed」, and the trunk screen answered by naming NO cause at all.
 * The additive detail accessor supplies the cause and this maps it; anything we did not measure
 * still falls to the cause-neutral line rather than guessing.
 *
 * `viewerOnly` is the signed-out / not-a-participant reading, and it comes FIRST because it is a
 * statement about who you are, not about a publish attempt: an anon viewer never publishes, so
 * 「확인 중」 there would be a measurement that is never going to happen (addendum 3b).
 */
export function packShareLine(
  sharing: boolean | null,
  cause: string | null,
  viewerOnly: boolean,
): string {
  if (viewerOnly) return '보기만 하는 중';
  if (sharing === null) return '내 위치 확인 중...';
  if (sharing) return '내 위치 공유 중';
  if (cause === 'no_fix') return '내 위치 잡히는 중';
  if (cause === 'window_closed') return '위치 공유 시간이 끝났어요';
  // Everything else — not deployed, not delivered, a throw, a refusal we do not recognise — is a
  // refusal we can stand behind without naming. Naming a cause we did not measure is the defect
  // this branch used to have in the other direction.
  return '아직 지도에 안 올라갔어요';
}
