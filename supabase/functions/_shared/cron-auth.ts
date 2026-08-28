// The shared gate on this project's two UNAUTHENTICATED cron endpoints.
//
// 🔴 [0157 · codex billing #7] Both `revoke-billing-keys` and `collect-charges` compared their
//    secret with an ordinary `!==`. JavaScript string equality short-circuits at the first
//    differing byte, so the comparison's DURATION carries information about the secret. Both
//    endpoints run with `verify_jwt = false` — the header IS the authentication — so an attacker
//    can call them at will, and `CRON_COLLECT_KEY` is SHARED between them, which means a
//    compromise reached from either one arms the other. That is what makes a timing oracle here
//    worth closing rather than filing as theory.
//
// ⚠ The comparison is over SHA-256 DIGESTS, not over the raw strings, and that is the substantive
//   half of the fix. Digesting first makes both operands a fixed 32 bytes, so the comparison leaks
//   neither the secret's LENGTH nor any prefix of it, and an attacker cannot steer digest bytes
//   without already knowing the secret. `timingSafeEqual` on top removes the last byte-position
//   signal. Either alone would be a real improvement; the pair is the standard construction and
//   costs one hash per request on a path that runs every ten minutes.
//
// ⚠ WHAT MUST STAY TRUE AND IS PINNED IN `_test/`:
//     · an UNSET or empty `CRON_COLLECT_KEY` answers **503** and authenticates nobody — without
//       that line `null === null` turns a half-configured deploy into an open, service-role,
//       credential-destroying endpoint;
//     · an absent or empty supplied header answers **401** whenever a non-empty secret exists;
//     · a wrong key answers 401 whether it is the SAME length as the real one or a different one.
import { timingSafeEqual } from "jsr:@std/crypto@1/timing-safe-equal";
import { HttpError } from "./ctx.ts";

const enc = new TextEncoder();

async function sha256(s: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(s)));
}

/** Constant-time secret comparison. `supplied` may be null/undefined — `Headers.get` returns
 *  `string | null` — and is treated as the empty string, which cannot match a non-empty secret. */
export async function cronSecretMatches(
  supplied: string | null | undefined,
  expected: string,
): Promise<boolean> {
  const [a, b] = await Promise.all([sha256(supplied ?? ""), sha256(expected)]);
  return timingSafeEqual(a, b);
}

/** The gate itself. Throws 503 when the secret is not configured, 401 when the header does not
 *  match it, and returns normally otherwise. `Deno.env.get` is read PER CALL, never captured at
 *  module load, so a deploy that sets the secret later — and the tests that unset it — see the
 *  real value rather than one frozen at import time. */
export async function requireCronKey(
  supplied: string | null | undefined,
  unconfiguredMessage: string,
): Promise<void> {
  const expected = Deno.env.get("CRON_COLLECT_KEY");
  if (!expected) throw new HttpError(503, unconfiguredMessage);
  if (!(await cronSecretMatches(supplied, expected))) throw new HttpError(401, "unauthorized");
}
