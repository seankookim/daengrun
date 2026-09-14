# Harness diet — proposal for Sean's ruling (2026-09-15)

Sean, verbatim: 「pull back on the unecessary harnesses that are in place; they take and space and
time」 and 「are those harnesses and edge tests necessary?」. This doc measures what each costs and
proposes cuts by option. **Nothing is cut until you pick; every cut names the property that
becomes unpinned.**

## What the infrastructure costs, measured on the new Mac today

| thing | size | wall-clock per run | what it proved today |
|---|---|---|---|
| SQL harness (`supabase/tests`, 106 suites registered, 109 files, 48,255 lines, 1,177 pins) | 87 MB on disk incl. `.pgtest` | **~2–4 min** (four runs today, log mtimes 01:12 → 01:14 → 01:24 → 01:32) | caught a double-registered suite in the 0157 merge (would have inflated the count); each landing's +19/+9/+14 delta proved the new suites actually ran |
| app test chain (`app/test`, 30 files, ~3k lines, 15 shell-chained suites, 980 PASS) | small | **~3–5 min** (dominated by `npx esbuild`/`tsx` startup × 15) | nothing today; green throughout |
| edge tests (`supabase/functions/_test`, 277 pins) | small | **2 s** | nothing today; green |
| six `check-*.mjs` gates + two baselines | small | seconds | nothing today; green |
| **`CLAUDE.md`** | **100,220 bytes** | loaded into EVERY Claude session, and every Codex session that reads it (the walled sol runs each spent ~5 min reading it) | — |
| `DESIGN.md` | 30,056 bytes | per UI session | — |
| `docs/` | 172 MB | cloned, `.easignore`d | — |

**Honest reading:** the runtime cost is small — the harness is minutes, not hours — and it did
real work today. The cost that is large is **context**: CLAUDE.md alone is ~25k tokens of process
law that every session and every codex read pays before doing anything, and the 48k-line suite
corpus is a maintenance surface every migration touching a shared object must keep green (the
rescue branches each carried fixture repairs to older suites for exactly that reason).

## Where the pins are (top tags from the 1,177/0 run)

`lb` 61 · `club` 32 · `acd` 29 · `pact` 28 · `cus` 25 · `chg` 25 · `rhd`/`rbd`/`km`/`dseal`/`bep` 23
each · `settle`/`pkmap` 21 · … — money (`chg`, `settle`, `km`, `ccf`, `crf`, `lb`) and security
(`acd`, `pact`, `srp`, `rbd`, `dseal`) dominate. The five largest files (152 late-booking 2,350 lines ·
153 club cancel fee 1,784 · 150 account deletion 1,386 · 119 run-end 1,372 · 116 charge 1,292) are
all money or deletion paths.

## Options

**A — Trim the context, keep the pins (recommended first step, zero risk to money/security).**
Move CLAUDE.md's incident narratives (the 「measured 2026-08-2x…」 paragraphs) into
`docs/laws/` as an appendix, leaving a ≤10 KB CLAUDE.md of operational law: language · operations ·
honesty laws · commit gate list · migration/security bullets · design extract · branch rule ·
codex invocation + the digit detector. Every law survives; the story of how it was learned moves
one hop away. Saves ~22k tokens per session. Also stop asking codex to read CLAUDE.md in full
(the P0 prompt already points at sections).

**B — Stop WRITING new harness by default.** Keep the existing 1,177 pins running (they're cheap)
but change the standing rule from 「every slice gets mutation-verified pins」 to 「pins only for a
money or security invariant the slice creates or changes; no batteries, no controls-of-controls,
no speculative suites」. This is the calibration the master prompts already call
「harness-light」; making it the written law stops the corpus growing 1,000 lines per slice.

**C — Merge the app test chain into one runner.** Fifteen `run-*.sh` scripts each boot
`npx esbuild`/`tsx`; one `node --test`-style runner would take the chain from minutes to seconds
and remove 15 shell files. Mechanical, astra-low work, no pin lost.

**D — Retire suites that pin vocabulary or UI copy rather than invariants.** Needs a per-suite
read to name candidates honestly — the walled codex run was going to do this and I will not
guess. If you want D, I run one astra-medium pass over `supabase/tests/` headers (they
self-describe what each pins) and bring back a keep/cut table with the unpinned property named
per row. Estimated saving: maybe 10–20 suites; money and security suites stay.

**E — Cut nothing; accept the cost.** Today's runs argue this is defensible: minutes per run,
and it caught a real merge defect.

## Recommendation

A + B + C now (no invariant lost; context and minutes both shrink), D only if you want the
per-suite read, never E's opposite (deleting money/security pins to save minutes).

**Your call:** which letters?
