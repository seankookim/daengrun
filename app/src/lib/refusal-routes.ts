// A deletion refusal's token + row id → a real screen, or nothing. (0191, server half in
// `supabase/migrations/0191_refusal_detail_ids.sql`; queue item `awaiting-sean.md` §0-unvicies.)
//
// ═══ WHY THIS IS A SEPARATE, DEPENDENCY-FREE MODULE ══════════════════════════════════════════
// Two reasons, and the second is the one that matters. (a) `app/test/*.cjs` can bundle a `.ts`
// and cannot bundle a `.tsx` route module, so a map that lived in the sheet could not be pinned
// at all. (b) The answer here is a CLAIM ABOUT THE ROUTER — "this path exists and accepts this
// id" — and a claim that is checkable in one place stays true; the same claim spread across a
// copy table drifts screen by screen.
//
// ═══ 🔴 THE HONESTY LAW IS THE DESIGN, NOT A CAVEAT ══════════════════════════════════════════
// Nine of the twelve refusal tokens now arrive with an id. **Three of those nine get a route.**
// A button is rendered only where `refusalRoute()` returns a path, so a token whose id has
// nowhere to go renders no button at all — which is what "no dead buttons" means when the entity
// genuinely has no screen. Naming the destination in prose (which the copy already does) is the
// honest maximum in the other cases.
//
//   ROUTED, because `app/app/club/session/[sid].tsx` takes a club session id and the return
//   confirm lives on it:
//     club_custody         you are holding someone's dog      → /club/session/<sid>
//     club_custody_owner   your dog is out with a runner      → /club/session/<sid>   ★ the
//                          queue item's own example: 0115:388-392 wrote "the refusal is a BARE
//                          TOKEN — it does not carry the club session id", and named `ctx.ts` as
//                          the reason. This line is that sentence retired.
//     club_assignment      a committed assignment             → /club/session/<sid>
//
//   NOT ROUTED, each for its own measured reason — none of these is an unfinished half:
//     active_booking   `owner/schedule.tsx` reads NO route param (measured: zero
//                      `useLocalSearchParams` in the file). The existing static button already
//                      lands exactly where a deep link would, so an id-carrying route would be
//                      the same screen with a longer URL.
//     active_run       same — `owner/live.tsx` and `runner/run.tsx` take no params; both resolve
//                      the caller's own live run.
//     unsettled_run    no screen shows a single run's settlement.
//     unsettled_payment `payments.tsx` takes `returnTo`/`returnLabel` only; it lists payments and
//                      cannot be opened on one.
//     open_incident    🔴 ONE TOKEN, TWO ENTITIES. `incidents` opens at `/incident/[bid]` — keyed
//                      on the BOOKING id, not the incident id — and `club_incidents` opens at
//                      `/club/case/[cid]`, keyed on the incident id. The detail is a bare uuid
//                      with no discriminator, so a client that guessed would be right half the
//                      time: a button that goes to the wrong screen, or to a 「찾을 수 없어요」.
//                      Closing this needs a typed detail or two tokens — a copy decision, not a
//                      patch. Until then: no button. The id is still worth sending; it is the
//                      one durable handle a support thread has on 「which incident」.
//     club_host_duty   `app/app/club/[id].tsx` is a dynamic route that never reads its own param
//                      (measured): the Banpo pilot has one club and the screen loads it
//                      unconditionally. The id is correct and buys nothing the static
//                      `/community` button does not already give.
//     km_balance · unpaid_payout · active_recurring  carry no id at all (0191 §0a).
//
// When a route gains an id — a booking detail screen, an incident router that takes either kind —
// the change is ONE line here plus its case in `refusal-routes.test.cjs`.

/** The canonical uuid shape. A detail that is not one is not an id we will put in a URL: the
 *  server sends `''` when it refused and could not name the row (plpgsql will not take a null
 *  RAISE option), and `handle()` already drops an empty one — this is the belt, so a future
 *  server that sends a sentence instead of an id cannot produce a link to nowhere. */
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Tokens whose id IS a club session id, and whose screen takes one. The value is the only
 *  thing that differs from an unrouted token, so adding a route is adding a key. */
const SESSION_TOKENS: ReadonlyArray<string> = ['club_custody', 'club_custody_owner', 'club_assignment'];

/** The label of the deep-link control. One string, because every routed token lands on the same
 *  kind of place and a per-token verb would be four sentences that must each stay true. */
export const REFUSAL_ROUTE_LABEL = '해당 화면으로 이동';

/**
 * The screen this refusal is about, or `null` when there is none.
 *
 * ⚠ `null` is the DEFAULT and the safe direction: an unknown token, a missing id, a malformed id
 * and a token whose entity has no screen all return `null`, so a server that grows a thirteenth
 * token cannot produce a button before anyone has decided where it goes.
 */
export function refusalRoute(token: string, detail?: string | null): string | null {
  if (!detail || !UUID.test(detail)) return null;
  if (SESSION_TOKENS.includes(token)) return `/club/session/${detail}`;
  return null;
}
