// rating.ts — tests run against the REAL compiled source (see run-rating-tests.sh), not a
// retyped copy. rating.ts imports nothing; no stubbing needed.
//
// WHAT THIS FILE IS FOR. The defect it was written against was not an arithmetic slip — the old
// code computed a correct mean of the wrong SET: `fetchRunnerProfile` averaged the `.limit(5)`
// window it had fetched for the review list, and `fetchRunnerReviewCount` counted all of them, so
// a runner with 40 reviews showed the mean of 5 beside 「40」. No pin here can see that (the set is
// chosen by a database read), so these cases pin the half that CAN be pinned without a database —
// the arithmetic and, more importantly, the three honesty boundaries around it:
//   ① an empty set has NO mean — `null`, never 0, because 0 is below the worst score a human can
//      give and therefore reads as 「rated, and terribly」;
//   ② a `rating = null` review is a real review that cannot be averaged, so the rated count and
//      the review count are two different numbers;
//   ③ a preview line is absent, not empty, when there is no prose.
//
// The mutations that redden it: make `meanRating` return 0 for an empty set · drop the
// `isRating` range check so an out-of-band value joins the mean · average over `values.length`
// instead of the rated length · make `starText`/`firstLine` return '' instead of null · change
// the rounding to truncation · make `reviewCountText` count the rated subset.
const {
  RATING_MIN, RATING_MAX, isRating, ratedOnly, meanRating, starText, reviewCountText, firstLine,
} = require('./rating.build.cjs');

let pass = 0, fail = 0;
const t = (name, cond, detail = '') => {
  if (cond) { pass++; console.log('PASS ' + name); }
  else { fail++; console.log('FAIL ' + name + (detail ? ' - ' + detail : '')); }
};

// ── the scale is the table's, not ours ────────────────────────────────────────────────────────
// `reviews.rating` is `int check (rating between 1 and 5)` (0001_init.sql:255).
t('the scale is exactly the column constraint 1..5', RATING_MIN === 1 && RATING_MAX === 5,
  `${RATING_MIN}..${RATING_MAX}`);

t('every integer on the scale is a rating', [1, 2, 3, 4, 5].every(isRating));
t('0 is NOT a rating — it is below the worst score a human can give', isRating(0) === false);
t('6 is not a rating', isRating(6) === false);
t('null is not a rating', isRating(null) === false);
t('undefined is not a rating', isRating(undefined) === false);
t('a numeric STRING is not a rating (a read that returned text must not be averaged silently)',
  isRating('5') === false);
t('NaN is not a rating', isRating(NaN) === false);
t('Infinity is not a rating', isRating(Infinity) === false);

// ── ① the empty set has no mean, and the answer is never 0 ─────────────────────────────────────
t('no values → null, NOT 0', meanRating([]) === null, String(meanRating([])));
t('only nulls → null, NOT 0', meanRating([null, null]) === null, String(meanRating([null, null])));
t('only out-of-band values → null, NOT 0', meanRating([0, 9]) === null, String(meanRating([0, 9])));
t('null is returned, not the falsy 0 that would print ★ 0',
  meanRating([]) !== 0 && Object.is(meanRating([]), null));

// ── the mean itself ───────────────────────────────────────────────────────────────────────────
t('one rating is its own mean', meanRating([4]) === 4, String(meanRating([4])));
t('all fives → 5', meanRating([5, 5, 5, 5, 5]) === 5, String(meanRating([5, 5, 5, 5, 5])));
t('5 and 4 → 4.5', meanRating([5, 4]) === 4.5, String(meanRating([5, 4])));
t('1 and 5 → 3', meanRating([1, 5]) === 3, String(meanRating([1, 5])));
t('5,5,4 → 4.7 (rounded to one decimal)', meanRating([5, 5, 4]) === 4.7, String(meanRating([5, 5, 4])));
t('5,4,4 → 4.3', meanRating([5, 4, 4]) === 4.3, String(meanRating([5, 4, 4])));

// 🔴 THE DEFECT'S OWN SHAPE, in the only form a pure test can carry it: the mean of a WINDOW is
// not the mean of the set. 35 fives followed by 5 ones — the last five (the `.limit(5)` window
// ordered newest-first) average 1, the whole set averages 4.5. A caller that hands this function
// five values gets a truthful mean OF FIVE; the honesty lives at the call site, which must hand
// over every rated review. The two numbers are pinned side by side so the distance is on record.
const WINDOW = [1, 1, 1, 1, 1];
const WHOLE = Array(35).fill(5).concat(WINDOW);
t('the five-newest window averages 1', meanRating(WINDOW) === 1, String(meanRating(WINDOW)));
t('the same runner over all 40 averages 4.5 — the window is off by 3.5 stars',
  meanRating(WHOLE) === 4.5, String(meanRating(WHOLE)));

// ── ② a rating-less review is a review, and is not a zero ──────────────────────────────────────
t('nulls are skipped, not counted as 0', meanRating([5, null, 5]) === 5, String(meanRating([5, null, 5])));
t('the denominator is the RATED count, not the value count',
  meanRating([4, null, null, null]) === 4, String(meanRating([4, null, null, null])));
t('ratedOnly drops everything unusable', JSON.stringify(ratedOnly([5, null, 0, '3', 4, undefined, 6])) === JSON.stringify([5, 4]),
  JSON.stringify(ratedOnly([5, null, 0, '3', 4, undefined, 6])));
t('a set of five reviews where two carry no score averages the three that do',
  meanRating([5, null, 4, null, 3]) === 4, String(meanRating([5, null, 4, null, 3])));

// ── rounding is one decimal, deterministic, and stated ────────────────────────────────────────
t('one decimal, never more', String(meanRating([5, 5, 5, 4])) === '4.8', String(meanRating([5, 5, 5, 4])));
t('a repeating mean is rounded, not truncated (4.666… → 4.7)',
  meanRating([5, 5, 4]) === 4.7, String(meanRating([5, 5, 4])));
t('3.333… → 3.3', meanRating([4, 3, 3]) === 3.3, String(meanRating([4, 3, 3])));
t('an exact whole mean carries no decimal noise', Number.isInteger(meanRating([4, 4, 4])),
  String(meanRating([4, 4, 4])));

// ── starText: no average → no string at all ───────────────────────────────────────────────────
t('an average becomes ★ n', starText(4.3) === '★ 4.3', String(starText(4.3)));
t('a whole average prints without a trailing .0', starText(5) === '★ 5', String(starText(5)));
t('no average → null, not an empty string (an empty Text still occupies a row)',
  Object.is(starText(null), null), String(starText(null)));

// ── the count label counts REVIEWS ─────────────────────────────────────────────────────────────
t('the label names the review count', reviewCountText(40) === '40개의 후기', reviewCountText(40));
t('zero has a label too — the caller decides whether to use it', reviewCountText(0) === '0개의 후기', reviewCountText(0));
t('a negative or broken count never prints as a negative', reviewCountText(-3) === '0개의 후기', reviewCountText(-3));
t('a fractional count is floored, never rendered as 2.5', reviewCountText(2.5) === '2개의 후기', reviewCountText(2.5));

// ── ③ a preview line is ABSENT, not empty ──────────────────────────────────────────────────────
t('the first line of a note', firstLine('초코가 정말 잘 뛰었어요\n다음에도 부탁드려요') === '초코가 정말 잘 뛰었어요',
  String(firstLine('초코가 정말 잘 뛰었어요\n다음에도 부탁드려요')));
t('a single-line note is itself', firstLine('좋았어요') === '좋았어요', String(firstLine('좋았어요')));
t('leading blank lines are skipped', firstLine('\n\n  첫 줄  \n둘째') === '첫 줄', String(firstLine('\n\n  첫 줄  \n둘째')));
t('a null note has no line', Object.is(firstLine(null), null));
t('an undefined note has no line', Object.is(firstLine(undefined), null));
t('a whitespace-only note has no line, not an empty quote', Object.is(firstLine('   \n  '), null));
t('a non-string note has no line', Object.is(firstLine(42), null));
t('no ellipsis is appended — truncation belongs to the renderer, which knows the width',
  firstLine('한 줄짜리 후기') === '한 줄짜리 후기');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
