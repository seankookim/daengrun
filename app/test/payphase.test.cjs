// derivePayPhase / summarizeCollection — tests run against the REAL compiled source (see
// run-payphase-tests.sh), not a retyped copy, so what these cases pin is what /owner/pay ships.
//
// WHY THIS FILE EXISTS (codex 2026-08-28, findings 11 and 12 —
// docs/reviews/2026-08-28-codex-runend-money.md). The screen derived its whole sentence from
// `bookings.status`, and two of those statuses do not carry the fact the sentence asserts:
//
//   · `refund_pending` is written by `club_incident_settle` whenever the quote's refund is > 0,
//     WITHOUT asking whether money was ever captured — the migration asks that question six lines
//     later, for the NOTIFICATION only. MEASURED on production 2026-08-28: two bookings sit in
//     `refund_pending` and both have ZERO payments rows, so both owners were being told 「환불이
//     진행 중이에요」 about a charge that never happened.
//   · `completed` means the LEDGER committed. Collection happens after it and cannot unwind it,
//     so a settled run whose card was declined is `completed` and read identically to a paid one.
//
// THE PROPERTIES, stated without reference to any mutation:
//   P1  A phase that asserts a REFUND IS RUNNING is reachable only when a payments row proves
//       money moved.
//   P2  A phase that asserts NOTHING WAS CHARGED is reachable only when that is proven — never
//       from an unread, absent or unrecognised payment state.
//   P3  A phase that asserts PAYMENT COMPLETED is reachable only when money moved.
//   P4  A payments status word outside the CHECK constraint's vocabulary is never resolved into
//       either direction: it produces "we could not tell you".
//   P5  For every booking status and every collection shape, the result is a phase this module
//       declares — the function is total.
//   P6  A booking status whose sentence does not depend on money is unaffected by any collection
//       input, including a missing one. (The 2026-08-06 phase machine must survive intact.)
//
// ⚠ P2 and P4 are the two that carry the money. Every other case in this file could pass while
// the screen still lies; those two cannot.
const {
  derivePayPhase, summarizeCollection, collectionMatters, COLLECTION_UNKNOWN,
} = require('./payphase.build.cjs');

let pass = 0, fail = 0;
const t = (name, fn) => { try { fn(); console.log('PASS ' + name); pass++; } catch (e) { console.log('FAIL ' + name + ' — ' + e.message); fail++; } };
const eq = (a, b, m) => { if (a !== b) throw new Error((m || '') + ' expected ' + JSON.stringify(b) + ' got ' + JSON.stringify(a)); };
const deq = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error((m || '') + ' expected ' + JSON.stringify(b) + ' got ' + JSON.stringify(a)); };

// bookings.status, all sixteen (0001_init.sql:9-14 — the union in payphase.ts mirrors it).
const ALL_STATUSES = [
  'draft', 'quoted', 'payment_hold', 'matching', 'runner_pending', 'confirmed',
  'runner_enroute', 'picked_up', 'active', 'completed', 'cancelled_owner',
  'cancelled_runner', 'expired', 'no_show', 'incident_review', 'refund_pending',
];
// Every phase the module declares. A result outside this set is a phase the screen has no
// Record entry for, which renders as `undefined` — i.e. a blank headline on a money screen.
const ALL_PHASES = [
  'loading', 'not_found', 'mock_pending', 'authorizing', 'authorized', 'disputed', 'failed',
  'cancelled', 'refund_pending', 'not_charged', 'paid', 'collect_pending', 'collect_failed',
  'charge_unknown',
];
// The three phases that make a CLAIM ABOUT MONEY. Each of them is a sentence an owner will act on.
const REFUND_CLAIM = 'refund_pending';   // "your money is coming back"
const NO_CHARGE_CLAIM = 'not_charged';   // "you were never charged"
const PAID_CLAIM = 'paid';               // "your card was charged and it worked"

// payments.status — the six words the production CHECK `payments_status_vocab` allows, split by
// `payments_settled_has_key`: the first three cannot exist without a payment_key (money moved),
// the last three can (nothing moved). Both lists read off production 2026-08-28.
const MOVED = ['confirmed', 'canceled', 'partial_canceled'];
const NOT_MOVED = ['pending', 'failed', 'waived'];
// Words the CHECK does not allow TODAY. `status` is TEXT, not an enum, so tomorrow it might.
const WIDENED = ['refunded', 'in_progress', 'aborted', 'CONFIRMED', 'confirmed ', ''];

const rows = (...statuses) => statuses.map((status) => ({ status }));

// ── P8-support: summarizeCollection's own answers ────────────────────────────────────────────
t('summarize(null) — a failed read is UNKNOWN, not "no rows"', () => {
  deq(summarizeCollection(null), COLLECTION_UNKNOWN);
  deq(summarizeCollection(undefined), COLLECTION_UNKNOWN);
});
t('summarize([]) — zero rows is a PROVEN absence of capture, and nothing minted', () => {
  deq(summarizeCollection([]), { captured: false, outstanding: 'none', minted: false });
});
for (const st of MOVED) {
  t('summarize([' + st + ']) — captured (payments_settled_has_key forbids it without a key)', () => {
    eq(summarizeCollection(rows(st)).captured, true);
  });
}
for (const st of NOT_MOVED) {
  t('summarize([' + st + ']) — not captured', () => {
    eq(summarizeCollection(rows(st)).captured, false);
  });
}
t('failed outranks pending — the row a human must act on is the one that names the state', () => {
  eq(summarizeCollection(rows('pending', 'failed')).outstanding, 'failed');
  eq(summarizeCollection(rows('failed', 'pending')).outstanding, 'failed');
});
t('waived alone is neither captured nor outstanding — 0원 by policy is settled, not owed', () => {
  deq(summarizeCollection(rows('waived')), { captured: false, outstanding: 'none', minted: true });
});
t('minted distinguishes "priced to zero" from "never minted" — the pilot lives in the second', () => {
  eq(summarizeCollection([]).minted, false);
  eq(summarizeCollection(rows('waived')).minted, true);
});

// ── P4 · the widened-vocabulary law, at the summarize layer ─────────────────────────────────
// ⚠ An unrecognised word must poison BOTH answers. Skipping it silently is exactly how "nothing
// was charged" gets invented about a row that may well be a capture.
for (const st of WIDENED) {
  t('summarize([' + JSON.stringify(st) + ']) — an unknown word is UNKNOWN, both answers', () => {
    const c = summarizeCollection(rows(st));
    eq(c.captured, null, 'captured');
    eq(c.outstanding, 'unknown', 'outstanding');
  });
  t('summarize([confirmed, ' + JSON.stringify(st) + ']) — one unknown word poisons a known set', () => {
    eq(summarizeCollection(rows('confirmed', st)).outstanding, 'unknown');
  });
}

// ── P5 · totality, over every status × every collection shape ────────────────────────────────
const COLLECTION_SHAPES = [
  null, undefined, COLLECTION_UNKNOWN,
  summarizeCollection([]),
  summarizeCollection(rows('confirmed')),
  summarizeCollection(rows('pending')),
  summarizeCollection(rows('failed')),
  summarizeCollection(rows('waived')),
  summarizeCollection(rows('canceled')),
  summarizeCollection(rows('partial_canceled')),
  summarizeCollection(rows('mystery')),
  summarizeCollection(rows('confirmed', 'failed')),
];
t('P5 — every status × every collection shape returns a DECLARED phase', () => {
  for (const status of ALL_STATUSES) {
    for (const collection of COLLECTION_SHAPES) {
      const p = derivePayPhase({ status, collection });
      if (!ALL_PHASES.includes(p)) {
        throw new Error(status + ' + ' + JSON.stringify(collection) + ' -> ' + JSON.stringify(p));
      }
    }
  }
});
t('P5b — a status the server invented is absence, never a money claim', () => {
  for (const collection of COLLECTION_SHAPES) {
    const p = derivePayPhase({ status: 'settled_offline', collection });
    eq(p, 'not_found', 'unknown status');
  }
});

// ── P1 · a refund is only claimed when there is something to refund ─────────────────────────
t('P1 — refund_pending + captured is the ONLY way to reach the refund sentence', () => {
  for (const status of ALL_STATUSES) {
    for (const collection of COLLECTION_SHAPES) {
      if (derivePayPhase({ status, collection }) !== REFUND_CLAIM) continue;
      eq(status, 'refund_pending', 'refund claimed for status ' + status);
      eq(collection && collection.captured, true, 'refund claimed without a capture');
    }
  }
});
for (const st of MOVED) {
  t('refund_pending + [' + st + '] -> 환불 진행 중 (money really moved)', () => {
    eq(derivePayPhase({ status: 'refund_pending', collection: summarizeCollection(rows(st)) }), REFUND_CLAIM);
  });
}
// The two rows that exist on production RIGHT NOW: refund_pending with no payments rows at all.
t('THE LIVE CASE — refund_pending with zero payments rows says 청구 없음, not 환불 중', () => {
  eq(derivePayPhase({ status: 'refund_pending', collection: summarizeCollection([]) }), NO_CHARGE_CLAIM);
});
for (const st of NOT_MOVED) {
  t('refund_pending + [' + st + '] -> 청구 없음 (nothing was ever captured)', () => {
    eq(derivePayPhase({ status: 'refund_pending', collection: summarizeCollection(rows(st)) }), NO_CHARGE_CLAIM);
  });
}

// ── P2 · "nothing was charged" is a CLAIM and needs proof ───────────────────────────────────
t('P2 — the no-charge sentence is never reached from an unproven absence', () => {
  for (const status of ALL_STATUSES) {
    for (const collection of COLLECTION_SHAPES) {
      if (derivePayPhase({ status, collection }) !== NO_CHARGE_CLAIM) continue;
      if (!collection) throw new Error(status + ': no-charge claimed with NO collection at all');
      eq(collection.captured, false, status + ': no-charge claimed while capture was ' + collection.captured);
      eq(collection.outstanding !== 'unknown', true, status + ': no-charge claimed on an unknown outstanding');
    }
  }
});

// ── P3 · "paid" is a CLAIM and needs proof ──────────────────────────────────────────────────
t('P3 — the paid sentence is never reached without a capture', () => {
  for (const status of ALL_STATUSES) {
    for (const collection of COLLECTION_SHAPES) {
      if (derivePayPhase({ status, collection }) !== PAID_CLAIM) continue;
      eq(status, 'completed', 'paid claimed for status ' + status);
      eq(collection && collection.captured, true, 'paid claimed without a capture');
    }
  }
});

// ── P4 · at the derive layer: unknown never resolves into a money claim ─────────────────────
for (const status of ['refund_pending', 'completed']) {
  t(status + ' + a widened payments word -> charge_unknown (no claim in either direction)', () => {
    for (const st of WIDENED) {
      eq(derivePayPhase({ status, collection: summarizeCollection(rows(st)) }), 'charge_unknown', st);
    }
  });
  t(status + ' + an UNREAD payments table -> charge_unknown', () => {
    eq(derivePayPhase({ status, collection: summarizeCollection(null) }), 'charge_unknown');
  });
  // ⚠ The forgotten-argument case. A caller that never asked about payments must not be handed a
  // money claim as a default — the absence of a question is not an answer.
  t(status + ' + NO collection argument at all -> charge_unknown', () => {
    eq(derivePayPhase({ status }), 'charge_unknown');
    eq(derivePayPhase({ status, collection: null }), 'charge_unknown');
  });
}

// ── finding 12 · settlement succeeded, collection did not ───────────────────────────────────
t('completed + a failed charge -> collect_failed (a settled run is not a paid one)', () => {
  eq(derivePayPhase({ status: 'completed', collection: summarizeCollection(rows('failed')) }), 'collect_failed');
});
t('completed + a pending charge -> collect_pending', () => {
  eq(derivePayPhase({ status: 'completed', collection: summarizeCollection(rows('pending')) }), 'collect_pending');
});
t('completed + captured AND a stale failed row -> paid (money moved; the retry already won)', () => {
  eq(derivePayPhase({ status: 'completed', collection: summarizeCollection(rows('failed', 'confirmed')) }), PAID_CLAIM);
});
t('completed + a waived-only row -> 청구 없음, NOT the pilot sentence', () => {
  // The pilot sentence on `authorized` reads 「파일럿 기간이라 실결제는 발생하지 않았어요」 — true
  // only while nothing is minted. A 0원 run after the flag flip is a real no-charge decision.
  eq(derivePayPhase({ status: 'completed', collection: summarizeCollection(rows('waived')) }), NO_CHARGE_CLAIM);
});
t('completed + NOTHING minted -> authorized (the card-less pilot, unchanged)', () => {
  eq(derivePayPhase({ status: 'completed', collection: summarizeCollection([]) }), 'authorized');
});

// ── P6 · the collection-insensitive statuses are untouched ──────────────────────────────────
// The 2026-08-06 machine, re-pinned verbatim. If a later slice widens `collectionMatters`, these
// go red and the widening has to be argued for rather than absorbed.
const UNCHANGED = {
  draft: 'not_found', quoted: 'not_found', payment_hold: 'mock_pending', matching: 'authorized',
  runner_pending: 'authorized', confirmed: 'authorized', runner_enroute: 'authorized',
  picked_up: 'authorized', active: 'authorized', cancelled_owner: 'cancelled',
  cancelled_runner: 'cancelled', expired: 'cancelled', no_show: 'disputed',
  incident_review: 'disputed',
};
for (const [status, phase] of Object.entries(UNCHANGED)) {
  t('P6 ' + status + ' -> ' + phase + ' under EVERY collection shape', () => {
    eq(collectionMatters(status), false, 'this status must not be collection-sensitive');
    for (const collection of COLLECTION_SHAPES) {
      eq(derivePayPhase({ status, collection }), phase, JSON.stringify(collection));
    }
  });
}
t('P6b — the PG attempt record still drives mock_pending, collection or not', () => {
  eq(derivePayPhase({ status: 'payment_hold', attempt: { state: 'declined' } }), 'failed');
  eq(derivePayPhase({ status: 'payment_hold', attempt: { state: 'in_flight' } }), 'authorizing');
  // and it never overrides a status past the hold
  eq(derivePayPhase({ status: 'active', attempt: { state: 'declined' } }), 'authorized');
});
t('collectionMatters names exactly the two statuses whose sentence needs money', () => {
  const sensitive = ALL_STATUSES.filter(collectionMatters);
  deq(sensitive.sort(), ['completed', 'refund_pending']);
});

console.log('\n' + pass + ' pass / ' + fail + ' fail');
process.exit(fail === 0 ? 0 : 1);
