# Codex adversarial review — CLIENT half of everything since da47510 — WALLED at the emit step (UNREVIEWED), observations captured

Run: 2026-09-25 02:3x KST · plugin `adversarial-review --wait --base da47510` from a detached export worktree at `b46adb9`
with `supabase/` reverted to the base (client-only diff: 135 files). Streams split (`scratchpad/codex-review/mig16-cli.{out,err}`).
Detection: `FINDINGS: [0-9]+` → **0** · verdict VALUE → **0** · `usage limit` → **1** (「try again at 7:26 AM」, 2026-09-25) · exit 1.
**No verdict exists for the client half.** The run read for ~6 minutes, ran tsc + the three source gates (green), could not
run `npm test` (the sandbox has no esbuild and no network), wrote four interim observations, and died at the emit step.
The observations below are Codex's own sentences (plugin job log `state/cli-b46adb9-*/jobs/review-muft5su6-o7z3xv.log`),
each confirmed against the source by the announcer at 02:41 before routing — they are NOT a verdict and the re-run is owed
after 07:26.

## Captured observations → routing (announcer, 02:41 KST)

| # | Codex sentence (verbatim) | source check | goes to |
|---|---|---|---|
| c1 | 「incoming messages can be marked read while chat remains mounted behind another screen, because that path checks app activity but not navigation focus」 | `app/app/chat.tsx:251-254` — the poll path passes `appActive` only; focus is read only in the `useFocusEffect` path (:267) | **fix/client-review-1** (chat.tsx + chat-read.ts + test) |
| c2 | 「a slow read for booking A can overwrite booking B's card after the user switches bookings」 | `app/app/owner/schedule.tsx:358-367` (`fetchBookingPaymentState(bid).then(setPayState)`, no guard; :341-347 same shape) | **be/0220-payment-state-terminal** (already owns schedule.tsx's card; scope added by message) |
| c3 | 「The chat pager also merges only the newest 100 messages after reconnecting, with no way to fill a gap between that page and history already held on screen」 | `app/src/lib/chat-messages.ts` + chat.tsx poll merge — to be measured by the builder | **fix/client-review-1** |
| c4 | 「a dead control in the ops roster: after one successful addition, `saving` remains true and blocks the next addition」 | `app/app/ops/roster.tsx:126-146` — `setSaving(false)` at :144 sits in one branch, not `finally` | **fix/client-review-1** |
| c5 | 「The accessibility gate also passed a fix-plus-regression swap in the same file」 | known, documented blind spot of the per-file ledger (CLAUDE.md §check-a11y-roles: 「fix one and add one bare in the SAME file and the count nets to zero」) | prose; no build |
| — | 「the edge-error drift test failed when I injected a new unmapped HttpError token」 | the drift pin WORKS (a pass, recorded so the negative counts) | — |

## Re-run
Owed after 07:26 KST 2026-09-25: same export (`scratchpad/codex-review/cli-b46adb9`, refreshed to the trunk head of that
moment with `supabase/` at the base), same prompt (`mig16-cli.prompt`), streams split, digit detector. Not a cron —
one-shots do not fire while the session is idle (09-25 lesson); the announcer runs it in the first turn after 07:26.

## Codex streams (verbatim tail of stdout)

```
# Codex Adversarial Review

Codex did not return valid structured JSON.

- Parse error: Unexpected token 'T', "The probes"... is not valid JSON

Raw final message:

```text
The probes reproduced the payment response race and a dead control in the ops roster: after one successful addition, `saving` remains true and blocks the next addition. The accessibility gate also passed a fix-plus-regression swap in the same file. Its comment handling and unreadable-file failure behaved correctly, and the edge-error drift test failed when I injected a new unmapped `HttpError` token.
```
exit=1
```
