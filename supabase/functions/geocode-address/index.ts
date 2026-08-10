// Geocode a free-text address via the NCP Geocoding API (plan §D; F1-F3).
// input:  { query: string }  — any authenticated caller; used only to pre-center the pin picker.
// output: { available: false }                                        secret absent / NCP failure
//         { available: true, lat, lng, roadAddress }                  first match (numbers)
//         { available: true, lat: null, lng: null, roadAddress: null }  no match (one client branch)
//
// Missing secret is a deliberate no-op (0063 no-phantom-pipeline doctrine): the picker works
// without geocoding, so every failure here degrades to { available: false } — the client never
// parses error bodies (ES-10). No per-user throttle day one (AD-10): auth requirement + 100-char
// cap + per-invocation logging, with the NCP console quota alarm as the backstop.
import { admin, caller, handle, HttpError } from "../_shared/ctx.ts";

Deno.serve(handle(async (req) => {
  const db = admin();
  const uid = await caller(req, db); // anon → 401 via HttpError

  const b = await req.json().catch(() => ({}));
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
