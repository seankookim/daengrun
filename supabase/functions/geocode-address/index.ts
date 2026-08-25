// Geocode a free-text address via the NCP Geocoding API (plan §D; F1-F3).
//
// FORWARD mode (unchanged, byte-compatible — three shipped callers pass exactly `{ query }`:
// owner/address-pin.tsx:60, owner/addresses.tsx:92, onboard/owner.tsx:80)
// input:  { query: string }  — any authenticated caller; used only to pre-center the pin picker.
// output: { available: false }                                        secret absent / NCP failure
//         { available: true, lat, lng, roadAddress }                  first match (numbers)
//         { available: true, lat: null, lng: null, roadAddress: null }  no match (one client branch)
//
// REVERSE mode (0122 — Sean's Q6 ruling: 「also include the 동」, 2026-08-25)
// input:  { address_id: uuid }  — the OWNER of that address only. The caller supplies NEITHER a
//         coordinate NOR a 동: this function reads the row's own pinned lat/lng and writes the
//         label back itself, so the client can never author what a stranger runner will read
//         (0122 §2 makes that structural at the table too).
// output: { available: false, dong: null }             secret absent / NCP failure / timeout
//         { available: true,  dong: null }             no pin yet, or NCP returned no 법정동
//         { available: true,  dong: "반포동" }          written to addresses.dong
// refusals: absent id and foreign id are THE SAME 404 `not_owner` — 0054:73's enumeration-oracle
//         doctrine (a distinguishable "no such address" turns this into an id prober).
//
// Missing secret is a deliberate no-op (0063 no-phantom-pipeline doctrine): the picker works
// without geocoding, so every failure here degrades to { available: false } — the client never
// parses error bodies (ES-10). No per-user throttle day one (AD-10): auth requirement + 100-char
// cap + per-invocation logging, with the NCP console quota alarm as the backstop.
// ⚠ AD-10 RE-RAISED BY REVERSE MODE, said out loud rather than silently doubled: the pin flow now
// makes TWO NCP calls where it made one (forward on open, reverse on save), against the same
// unthrottled quota and the same console alarm.
// Reverse shares AD-10's exposure, and the honest sentence is the ATTACKER's, not the happy
// path's: the endpoint accepts any authenticated { address_id }, and refreshAddressDong is an
// exported client function — an authenticated user can loop their OWN address id for one NCP
// reverse call and one DB write per request, unbounded. The HONEST-client volume is "pins per
// day"; the bound-by-construction claim that stood here was false and is retired (blind review
// MINOR-5: a security comment claiming a bound that is not there is how the next reader stops
// looking). Nothing NEW is reachable versus forward mode's identical exposure; the throttle
// remains unbuilt and remains AD-10's own slice.
// unbuilt and remains AD-10's, not this slice's.
import { admin, caller, handle, HttpError } from "../_shared/ctx.ts";
import { reverseDong } from "./reverse.ts";

const NCP_TIMEOUT_MS = 5000;

Deno.serve(handle(async (req) => {
  const db = admin();
  const uid = await caller(req, db); // anon → 401 via HttpError

  const b = await req.json().catch(() => ({}));

  // ── REVERSE mode. Branch on the presence of `address_id` so a forward body (which never
  //    carries the key) reaches byte-identical code below.
  if (typeof b?.address_id === "string") {
    return await reverseDong(db, uid, b.address_id);
  }

  const query = typeof b?.query === "string" ? b.query.trim() : "";
  if (!query || query.length > 100) throw new HttpError(400, "invalid query");

  // Privacy: one log line per invocation — caller prefix + query length + outcome.
  // Never the address text, never the secret.
  const log = (outcome: "hit" | "miss" | "unavailable") =>
    console.log(`geocode caller=${uid.slice(0, 8)} qlen=${query.length} outcome=${outcome}`);

  const secret = Deno.env.get("NAVER_GEOCODE_SECRET");
  if (!secret) {
    log("unavailable");
    return { available: false };
  }
  // The map client id is public (already shipped in app.json); env override for rotation.
  const clientId = Deno.env.get("NAVER_MAPS_CLIENT_ID") ?? "3vpkxtglpe";

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 5000);
  try {
    const res = await fetch(
      `https://maps.apigw.ntruss.com/map-geocode/v2/geocode?query=${encodeURIComponent(query)}`,
      {
        headers: {
          "x-ncp-apigw-api-key-id": clientId,
          "x-ncp-apigw-api-key": secret,
        },
        signal: ctrl.signal,
      },
    );
    if (!res.ok) {
      console.error(`geocode: NCP responded ${res.status}`);
      log("unavailable");
      return { available: false };
    }
    const json = await res.json();
    const item = Array.isArray(json?.addresses) ? json.addresses[0] : undefined;
    if (!item) {
      log("miss");
      return { available: true, lat: null, lng: null, roadAddress: null };
    }
    // NCP returns x = longitude, y = latitude, both as strings.
    const lat = Number(item.y);
    const lng = Number(item.x);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      console.error("geocode: NCP result carried non-numeric coordinates");
      log("unavailable");
      return { available: false };
    }
    log("hit");
    return { available: true, lat, lng, roadAddress: item.roadAddress ?? null };
  } catch (e) {
    // Fetch error, 5s timeout, or unparseable body (F2) — degrade, never surface to the client.
    console.error(`geocode: NCP fetch failed: ${e instanceof Error ? e.message : String(e)}`);
    log("unavailable");
    return { available: false };
  } finally {
    clearTimeout(timer);
  }
}));
