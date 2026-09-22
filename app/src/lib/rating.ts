// rating.ts — the arithmetic behind every star number this app prints, and nothing else.
//
// WHY IT IS ITS OWN MODULE. Until 2026-09-23 a runner's profile printed `★ 4.8` next to
// 「40 후기」 and the two numbers came from two different reads: the count was a real
// `count: 'exact'` over every public review (`fetchRunnerReviewCount`, api.ts), while the average
// was computed inside `fetchRunnerProfile` over the `.limit(5)` window it fetched for the review
// LIST. A runner with forty reviews was shown the mean of five, under a label naming forty. That
// is the honesty law's own example of a fabricated number: the digits were real, the sentence they
// sat in was not. The fix is `fetchRunnerRatingSummary`, which reads every rated public review; the
// arithmetic moved here so it can be pinned without a database.
//
// EVERYTHING HERE IS PURE — no imports, no clock, no network. `app/test/rating.test.cjs` bundles
// this exact file (run-rating-tests.sh) rather than a retyped copy.

/** `reviews.rating` is `int check (rating between 1 and 5)` (0001_init.sql:255) and NULLABLE — a
 *  review may carry tags and a note and no score at all. Both facts matter below. */
export const RATING_MIN = 1;
export const RATING_MAX = 5;

/**
 * Is this value a score we are allowed to average?
 *
 * The range check is not defensive theatre: it is the boundary between「what the table promises」
 * and「what arrived」. A row outside 1–5 cannot exist under the check constraint, so one showing up
 * means the read returned something else (a widened column, a bad join, a hand-written row inserted
 * with the constraint dropped). Averaging it would move a public number by an amount nobody can
 * explain, so it is excluded and counted as unrated rather than silently folded in.
 */
export function isRating(v: unknown): v is number {
  return typeof v === 'number' && Number.isFinite(v) && v >= RATING_MIN && v <= RATING_MAX;
}

/** Every value in `values` that is a usable score. Exported because callers need the COUNT of
 *  rated reviews separately from the count of reviews — see `meanRating`'s note. */
export function ratedOnly(values: readonly unknown[]): number[] {
  return values.filter(isRating);
}

/**
 * The mean of every valid rating in `values`, rounded to one decimal — or `null`.
 *
 * 🔴 `null` IS THE POINT, AND IT IS NEVER 0. An empty set has no mean. Returning 0 would print
 * 「★ 0」 next to a new runner's name, which is not a neutral placeholder — 0 is below the worst
 * score a human can give, so it reads as「rated, and terribly」. Every caller must branch on null
 * and draw NOTHING rather than a number (honesty law: loading is not 0, and unknown is not 0).
 *
 * ⚠ The mean is over the RATED subset, not over every review. A review with `rating = null` is a
 * real review — it belongs in「N개의 후기」— but it has no score to average. So `count` and the
 * mean's denominator are two different numbers, and a caller printing both owes the reader the
 * honest pair: the count of reviews, and an average of the ones that carry a score. That is why
 * `RunnerRatingSummary` (api.ts) carries `count` AND `ratedCount`.
 *
 * Rounding is round-half-away-from-zero at one decimal, via `Math.round(m * 10) / 10`. Binary
 * floating point makes a few exact halves land down (4.65 * 10 is 46.499…), which is deterministic,
 * off by at most 0.1 in the conservative direction, and pinned below so a future rewrite has to
 * decide it deliberately rather than discover it.
 */
export function meanRating(values: readonly unknown[]): number | null {
  const rated = ratedOnly(values);
  if (rated.length === 0) return null;
  const sum = rated.reduce((a, b) => a + b, 0);
  return Math.round((sum / rated.length) * 10) / 10;
}

/**
 * `★ 4.3` — or `null` when there is no average, so a caller cannot accidentally render the string
 * 「★ null」 or fall back to a zero. Deliberately returns `null` and not `''`: an empty string is
 * falsy and renderable, and `<Text>{''}</Text>` draws an invisible row that still occupies layout.
 */
export function starText(avg: number | null): string | null {
  return avg == null ? null : `★ ${avg}`;
}

/** 「12개의 후기」. Takes the review count, NOT the rated count — the label says how many people
 *  wrote, which is the number a reader is counting. Zero is a legitimate answer here and gets a
 *  string, because a runner with no reviews is told so in words by the caller's empty state. */
export function reviewCountText(count: number): string {
  const n = Number.isFinite(count) && count > 0 ? Math.floor(count) : 0;
  return `${n}개의 후기`;
}

/**
 * The first line of a review note, for a one-line preview.
 *
 * Returns `null` for absent/blank so the caller draws no preview row at all rather than an empty
 * one — a review may be tags-and-stars with no prose, and an empty quote box asserts「they wrote
 * something」. Truncation is left to the renderer (`numberOfLines`), which knows the width; this
 * only picks the line and trims it, and never appends an ellipsis of its own (a note whose first
 * line happens to fit would otherwise be shown as if it had been cut).
 */
export function firstLine(note: string | null | undefined): string | null {
  if (typeof note !== 'string') return null;
  const line = note.split('\n').map((l) => l.trim()).find((l) => l.length > 0);
  return line && line.length > 0 ? line : null;
}
