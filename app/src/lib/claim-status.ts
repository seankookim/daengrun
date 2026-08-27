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
export const claimStatusLabel = (s: string | null | undefined): string =>
  // Verbatim from BOTH screens — they already agreed on this one and it is right: the claim is
  // redeemable, and there is genuinely no shipping integration yet (the honesty law: say the
  // state we are actually in). When fulfilment ships, this arm is the one line that changes.
  s === 'claimable' ? '수령 가능 · 배송 연동 준비 중'
    // shop.tsx's word, kept; rewards.tsx had none and printed the token `locked`.
    : s === 'locked' ? '잠김'
      // New — neither screen had a word. 'claimed' means the runner redeemed it; it says nothing
      // about dispatch, so the word stops at 수령 and does not reach 배송.
      : s === 'claimed' ? '수령 완료'
        // New. '발송 완료' (dispatched), NOT '배송 완료' (delivered) — the enum's last value is
        // `shipped`, and there is no `delivered`, so 배송 완료 would assert an arrival the server
        // never recorded.
        : s === 'shipped' ? '발송 완료'
          // Unreachable while the enum has four values; reached by null/undefined/'' from a
          // partial fetch, or by a fifth value added server-side ahead of an app build.
          : '확인 중';
