// ═══════════ 앱 전역 공용 문장 — one sentence, one place ═══════════
//
// What this file is FOR. Four screens draw the same map-failure placeholder — the owner's course
// map, the owner's address pin, the runner's base pin, and the shared PickupMap plate — and each
// one had retyped the sentence. Retyped copy does not drift loudly: it drifts one screen at a
// time, and nothing fails while three screens say one thing and the fourth says another. The
// sentence is the product surface, so it gets a single definition the same way a token does.
//
// ⚠ This file holds SENTENCES and nothing else — no state, no verdicts, no components. Copy that
// belongs to one domain keeps its own module (checkin-copy.ts, late-copy.ts, hold-replay-copy.ts);
// what lands here is copy that genuinely crosses domains, which so far is exactly one string.
// A constant that only ever has one caller belongs at that caller, not here.
//
// Form note (2026-09-23): the four sites used the `-을 수 없어요` construction, which had 5 uses
// app-wide against 193 for the `-지 못했어요` form below — and the two are not synonyms in tone.
// The first states an incapacity that sounds permanent; the second reports an attempt that
// failed, which is what actually happened and what the rest of the app says. The house form wins.
//
// ⚠ The retired wording is deliberately NOT quoted anywhere in this repo, comments included: a
// comment that quotes removed copy matches every grep that hunts for it, so documenting the fix
// and failing to make it would look identical to the next session (CLAUDE.md, comment-quoting
// law). `copy-forms.test.cjs` pins the absence; this paragraph explains it without restoring it.

/**
 * The map could not be drawn — the Naver SDK is absent from this build.
 *
 * ⚠ This is the SDK-absent placeholder, not a network failure and not an empty result. Every
 * site that renders it also hides its confirm control (dead-button law), because a map that is
 * not there cannot take a pin. Do not reuse this line for a fetch that failed — that state has
 * a retry door and this one does not.
 */
export const MAP_LOAD_FAIL_KO = '지도를 불러오지 못했어요';
