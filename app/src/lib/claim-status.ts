// Gear-claim status word — pure, importless module (same shape as tier.ts / rpc-skew.ts).
// It lives here and not in api.ts because of the test: this repo's idiom
// (run-pace-tests.sh, run-tier-label-tests.sh) is "bundle the REAL source with esbuild rather
// than a retyped copy", so the mapping the cases pin is the mapping that ships. api.ts imports
// supabase and cannot be bundled that way, which is why these helpers get their own files.
//
// THE DOMAIN IS CLOSED. `claim_status` is a pg enum of exactly four values, declared once in
// 0001_init.sql:21 — ('locked', 'claimable', 'claimed', 'shipped') — and `gear_claims.status`
// (0001_init.sql:332) is `not null default 'locked'`. Four values, four words, all positive
// matches. Nothing is left to a fallthrough.
//
// ⚠ Why this helper exists: TWO screens printed this field with copied ternaries that DISAGREED
// on how much of the enum they covered. runner/rewards.tsx covered ONE value
// (`=== 'claimable' ? … : g.status`), so locked/claimed/shipped rendered as **raw English
// tokens in a Korean UI**. shop.tsx covered TWO (claimable, locked) and leaked the other two the
// same way. One enum, two partial maps, different coverage — unmanaged drift, and each screen
// would have to be found separately the day the enum became reachable.
//
// 🔴 Latent, not broken, and that is the whole reason to fix it now: production `gear_claims`
// has 0 rows and supabase/functions/open-drop/index.ts only ever inserts 'claimable', so today
// no screen can reach the broken arms. But 0106_drops_seal.sql:352 deliberately grants
// service_role write on `status`/`shipped_to`/`claimed_at` "for future ops fulfilment" — so the
// FIRST real shipment produces `shipped`, and a runner who was actually sent their gear reads
// the word `shipped` on a Korean screen.
//
// The unknown word is '확인 중': true no matter what the real state is, and it claims NO
// fulfilment. That direction matters more here than it did for tier.ts. An unknown value must
// never read as '수령 완료' or '발송 완료' — those are claims about a physical object having
// been handed over or dispatched, and the app must not assert a fulfilment step nobody recorded.
// The safe direction for a claim state is always "less than we know", never "more".
// ─────────────────────────────────────────────────────────────────────────────────────────────
// 🔴 [0195] THE ARM THIS FILE PREDICTED HAS FIRED. The line above says 「When fulfilment ships,
// this arm is the one line that changes」 — 0195_gear_claim_tx.sql is that shipment, and three of
// the four words move. The old words are NOT deleted, they are corrected, because a removed
// dissent teaches nothing:
//
//   · `claimable` was 「수령 가능 · 배송 연동 준비 중」. The second clause was the honest thing to
//     say while the chip was a label with no route. **It is now false**: there is a door, the
//     button beside this word opens it, and telling a runner 준비 중 next to a working button is
//     the mirror image of the original defect — copy that describes a state the product left.
//   · `claimed` was 「수령 완료」 and is now 「배송 준비 중」. The old word was written when
//     `claimed` could only be reached by an ops hand-edit and meant nothing more than 「redeemed」.
//     Under 0195 it has a precise meaning: the runner submitted an address, the row holds it, and
//     an operator has not yet posted the box (`ops_gear_claims_pending()` is exactly this
//     population). 수령 완료 reads to a runner as 「I have it」, which is the one thing that is
//     certainly not true yet — the box has not moved.
//   · `shipped` was 「발송 완료」 and is now 「배송 중」. Same fact, better tense for the person
//     waiting: 0195 §D stamps a carrier and a tracking number, so the box is in transit and the
//     runner can act on that. ⚠ The original reasoning is UNCHANGED and still binding: the enum's
//     last value is `shipped` and there is **no `delivered`**, so neither word may claim arrival.
//     배송 중 asserts transit, which is what was recorded; 배송 완료 would assert an arrival
//     nobody wrote down.
//   · `locked` is untouched, and so is the unknown-value direction below.
// ─────────────────────────────────────────────────────────────────────────────────────────────
export const claimStatusLabel = (s: string | null | undefined): string =>
  // The claim is redeemable and the button next to this word is real (rewards.tsx). No clause
  // about integration readiness — the integration is the operator, and that is not a caveat.
  s === 'claimable' ? '수령 가능'
    // shop.tsx's word, kept; rewards.tsx had none and printed the token `locked`.
    : s === 'locked' ? '잠김'
      // 0195: the address is on the row and an operator has not posted it yet. It claims a
      // PREPARATION, which is exactly what the server recorded, and stops short of possession.
      : s === 'claimed' ? '배송 준비 중'
        // 0195: a carrier and a tracking number exist. 배송 중 (in transit), NOT 배송 완료
        // (delivered) — the enum has no `delivered` value and nothing records an arrival.
        : s === 'shipped' ? '배송 중'
          // Unreachable while the enum has four values; reached by null/undefined/'' from a
          // partial fetch, or by a fifth value added server-side ahead of an app build.
          : '확인 중';

/** The carrier line, when ops has actually stamped one. Returns null otherwise — an absent
 *  shipment renders NOTHING rather than 「배송 정보 없음」, because a runner whose box has not left
 *  does not need a sentence about the absence of a tracking number they were never promised.
 *  ⚠ BOTH halves are required before anything is drawn. A carrier with no tracking number is not
 *  actionable and a tracking number with no carrier cannot be looked up, so a half-filled pair is
 *  treated as no pair rather than rendered as a partial truth. */
export const claimCarrierLine = (
  carrier: string | null | undefined,
  tracking: string | null | undefined,
): string | null => {
  const c = (carrier ?? '').trim();
  const t = (tracking ?? '').trim();
  if (c === '' || t === '') return null;
  return `${c} ${t}`;
};
