// Extracted from index.ts so the party gate is TESTABLE (blind review MINOR-9): index.ts calls
// Deno.serve at import time, which no test can import. Same split as create-booking-hold's
// handler.ts — the deploy bundler follows relative imports, so nothing changes at runtime.
import { admin, HttpError } from "../_shared/ctx.ts";

const NCP_TIMEOUT_MS = 5000;
const DONG_MAX = 20; // must agree with `addresses_dong_len` (0122 §1) — over-length is a miss, not a 400

// ── 0122 REVERSE: address_id → 법정동, written server-side ────────────────────────────────────
// Order is load-bearing and matches the SQL doctrine: PARTY GATE FIRST, before the row's
// coordinates are read for any purpose and before a single byte leaves for NCP. An id the caller
// does not own must cost exactly the same as an id that does not exist.
export async function reverseDong(
  db: ReturnType<typeof admin>,
  uid: string,
  addressId: string,
): Promise<{ available: boolean; dong: string | null }> {
  // Privacy: caller prefix + outcome only. Never the address, never the coordinates, and never
  // the 동 itself — it is 개인정보 at 동 granularity (0122 header) and a log line is a copy.
  const log = (outcome: "wrote" | "no_pin" | "miss" | "unavailable" | "too_long") =>
    console.log(`reverse caller=${uid.slice(0, 8)} outcome=${outcome}`);

  // service_role read — RLS is bypassed here, so the ownership term IS the gate. `.eq(owner_id)`
  // rather than a post-hoc comparison: a row that is not mine must not be fetched at all.
  const { data: row, error } = await db
    .from("addresses")
    .select("id, lat, lng")
    .eq("id", addressId)
    .eq("owner_id", uid)
    .maybeSingle();
  if (error) {
    console.error(`reverse: address read failed: ${error.message}`);
    throw new HttpError(500, "internal");
  }
  // Absent OR foreign — one sentence, one status (0054:73).
  if (!row) throw new HttpError(404, "not_owner");

  // No pin yet: nothing to reverse. Honest empty answer, no write, no NCP call.
  if (row.lat == null || row.lng == null) {
    log("no_pin");
    return { available: true, dong: null };
  }

  const secret = Deno.env.get("NAVER_GEOCODE_SECRET");
  if (!secret) {
    log("unavailable");
    return { available: false, dong: null };
  }
  const clientId = Deno.env.get("NAVER_MAPS_CLIENT_ID") ?? "3vpkxtglpe";

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), NCP_TIMEOUT_MS);
  try {
    // NCP reverse-geocoding takes `coords=<lng>,<lat>` — x then y, the opposite of how every
    // other line in this repo writes a pair. `orders=legalcode` asks for the 법정동 layer, which
    // is what 「동」 means in Sean's ruling (행정동 would be `admcode` and can differ).
    const res = await fetch(
      `https://maps.apigw.ntruss.com/map-reversegeocode/v2/gc` +
        `?coords=${encodeURIComponent(`${row.lng},${row.lat}`)}&orders=legalcode&output=json`,
      { headers: { "x-ncp-apigw-api-key-id": clientId, "x-ncp-apigw-api-key": secret }, signal: ctrl.signal },
    );
    if (!res.ok) {
      console.error(`reverse: NCP responded ${res.status}`);
      log("unavailable");
      return { available: false, dong: null };
    }
    const json = await res.json();
    const results = Array.isArray(json?.results) ? json.results : [];
    const name = results
      .map((r: Record<string, unknown>) =>
        ((r?.region as Record<string, { name?: unknown }> | undefined)?.area3?.name)
      )
      .find((n: unknown) => typeof n === "string" && n.trim().length > 0) as string | undefined;
    const dong = name?.trim() ?? "";
    if (!dong) {
      // Sea, a new development with no assigned 법정동, an NCP shape change — all the same
      // honest answer. Nothing is written; the column stays NULL and the card omits the token.
      log("miss");
      return { available: true, dong: null };
    }
    if (dong.length > DONG_MAX) {
      // The CHECK would refuse this write. Refusing it here keeps the failure a measured miss
      // instead of a 500 the client would have to parse (ES-10).
      log("too_long");
      return { available: true, dong: null };
    }

    const { error: wErr } = await db.from("addresses").update({ dong }).eq("id", addressId).eq("owner_id", uid);
    if (wErr) {
      console.error(`reverse: dong write failed: ${wErr.message}`);
      return { available: false, dong: null };
    }
    log("wrote");
    return { available: true, dong };
  } catch (e) {
    console.error(`reverse: NCP fetch failed: ${e instanceof Error ? e.message : String(e)}`);
    log("unavailable");
    return { available: false, dong: null };
  } finally {
    clearTimeout(timer);
  }
}
