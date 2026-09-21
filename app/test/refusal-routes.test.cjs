// refusal-routes.ts — tests run against the REAL compiled source (see run-refusal-routes-tests.sh),
// not a retyped copy.
//
// WHAT THIS FILE IS FOR, since a token→path map can be pinned pointlessly: every entry here is a
// CLAIM ABOUT THE ROUTER — "this screen exists and accepts this id" — and the cost of getting one
// wrong is a button that opens 「찾을 수 없어요」 or, worse, the wrong record. The honesty law says a
// visible action must have a real route in every state, so the interesting arms are not the three
// that route; they are the NINE that must NOT, each for its own reason (0191 §0d and this module's
// header). A future session that "completes" the map by adding `open_incident` — the one that looks
// most obviously missing — reddens this file, and has to argue with the reason written beside it.
//
// The mutations that redden it: add a token to SESSION_TOKENS · drop one from it · relax the uuid
// guard to a truthiness check · return a path for an empty/absent detail · change the club session
// path shape · change the button label.
const { refusalRoute, REFUSAL_ROUTE_LABEL } = require('./refusal-routes.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

const SID = '5e551011-0000-4000-8000-00000000cafe';

// ── the three that route ───────────────────────────────────────────────────────────────────────
// All three carry a CLUB SESSION id (0191 §0d) and `app/app/club/session/[sid].tsx` reads `sid`.
for (const token of ['club_custody', 'club_custody_owner', 'club_assignment']) {
  t(`${token} deep-links to the club session screen`,
    refusalRoute(token, SID) === `/club/session/${SID}`, String(refusalRoute(token, SID)));
}

// ── the nine that must not ─────────────────────────────────────────────────────────────────────
// 🔴 THE CONTROL, and the half of this file that is actually load-bearing. Each of these is given
// a PERFECTLY VALID uuid — so the only thing that can produce a null is the map itself, not the
// id. A `refusalRoute` that returned `/club/session/<id>` for everything passes every arm above.
const NO_ROUTE = {
  // the screen takes no route param at all (measured: zero useLocalSearchParams in the file)
  active_booking: 'owner/schedule.tsx reads no param; the static button already lands there',
  active_run: 'owner/live.tsx and runner/run.tsx read no params; they resolve the caller own run',
  club_host_duty: 'club/[id].tsx never reads its own param — one club in the Banpo pilot',
  // no screen shows this entity at all
  unsettled_run: 'no screen shows a single run settlement',
  unsettled_payment: 'payments.tsx lists payments and cannot be opened on one',
  // 🔴 one token, two entities, no discriminator — a guess would be right half the time
  open_incident: 'incidents opens at /incident/[bid] (a BOOKING id); club_incidents at /club/case/[cid]',
  // these three carry no id at all, server-side (0191 §0a)
  km_balance: 'a SUM over km_lots — there is no single blocking row to name',
  unpaid_payout: 'knowingly inert: nothing writes payouts on the deletion path',
  active_recurring: 'a row exists but no route takes its id',
};
for (const [token, why] of Object.entries(NO_ROUTE)) {
  t(`${token} renders NO button even with a valid id — ${why}`,
    refusalRoute(token, SID) === null, String(refusalRoute(token, SID)));
}
t('the two lists together are the twelve server tokens, counted once',
  3 + Object.keys(NO_ROUTE).length === 12, String(3 + Object.keys(NO_ROUTE).length));

// ── a missing or malformed id can never become a URL ───────────────────────────────────────────
// `''` is what the server sends when a refusal is real and it could not name the row (plpgsql
// refuses a null RAISE option, and the id is read by a second statement a concurrent commit can
// outrun). `handle()` already drops an empty detail; this is the belt.
for (const bad of [undefined, null, '', ' ', 'not-a-uuid', SID + 'x', SID.slice(0, -1),
  `${SID}/../../owner/home`, '../../etc', '00000000-0000-0000-0000-00000000000g']) {
  t(`a detail of ${JSON.stringify(bad)} yields no route`,
    refusalRoute('club_custody_owner', bad) === null, String(refusalRoute('club_custody_owner', bad)));
}
t('an uppercase uuid is still a uuid (postgres renders lowercase, but nothing guarantees it)',
  refusalRoute('club_custody', SID.toUpperCase()) === `/club/session/${SID.toUpperCase()}`);

// ── an unknown token is never routed ───────────────────────────────────────────────────────────
// The default is null so a THIRTEENTH server token cannot produce a button before anyone has
// decided where it goes — the same fail-closed shape as the sheet's `unknown` phase.
for (const token of ['', 'club_custody_ownerx', 'CLUB_CUSTODY', 'some_future_token', 'club_custody ']) {
  t(`unknown token ${JSON.stringify(token)} is not routed`,
    refusalRoute(token, SID) === null, String(refusalRoute(token, SID)));
}

// ── the label ──────────────────────────────────────────────────────────────────────────────────
// One label for every routed token: each lands on the same kind of place, and a per-token verb
// would be three sentences that must each stay true as the destination screen changes.
t('the deep-link label is the agreed Korean string', REFUSAL_ROUTE_LABEL === '해당 화면으로 이동',
  REFUSAL_ROUTE_LABEL);
t('the label promises navigation and nothing about the outcome',
  !/삭제|탈퇴|완료|확인했/.test(REFUSAL_ROUTE_LABEL), REFUSAL_ROUTE_LABEL);

console.log(`\n${pass} pass / ${fail} fail`);
process.exit(fail === 0 ? 0 : 1);
