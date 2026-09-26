# Cloud run ledger — 2026-09-26 (Opus 5.5 cloud session, trunk `0ee30fa`)

Sean chose "Wave 1 here" and then "continue all tasks in cloud". Every slice below was built in its own worktree. Each then went to an **executing** adversarial reviewer, which ran attacks against the code, and then a fixer. Each branch was pushed and read back from origin. **None of these slices has had a Codex review.** Codex, the iOS simulator, deno, `supabase login` and deploys are all unavailable in the cloud container. Nothing here has landed on `redesign-v4`, and nothing has been deployed.

Harness recipe in the cloud: root cannot run `initdb`, so run it as the postgres user.
```
runuser -u postgres -- env LANG=C.UTF-8 LC_ALL=C.UTF-8 HOME=/tmp bash harness.sh
```
Baselines at `0ee30fa` (measured here):
- harness: 1586 pass / 0 fail
- npm: exit 0, 5156 PASS / 0 FAIL + 39 ✅
- lint: **11 errors**, over the CI budget of 6, so trunk's `client-gates` is red. That is fixed by #6.

Migration and suite numbers: 0229–0231 and 260–262 were skipped, because REGISTRY.md:308 says those are held on the Mac. The cloud took migrations **0232–0239** and suites **263–270**.

## Merge order (each step: merge, run the full chain, read back from origin)

1. **#6 lint** (`cloud/lint-exhaustive-deps`). It is fully green. Merge it first: it turns `client-gates` green for every other PR, because it sets budget 0 and fixes the parser that read "1 error" as 0.
2. **Trunk-based, independent.** Merge trunk into each branch before landing it:
   - #5 docs
   - #3 F4 reduced motion
   - #4 rpc-contracts comment-strip
   - #2 P8 first-run
   - #7 client-review-4
   - #13 owner return frame
   - #12 0236 push takeover
   - #11 0235 chat clamp
   - #19 F5 silent catches
   - #20 F6 15pt floor
3. **#8 0232.** After it lands, retarget #10 to `redesign-v4`.
4. **#10 0233/0234.** After it lands, retarget #14 and #15.
5. **#14 0237** and **#15 0238**.
6. **#17 0239**, the root cause for #10 and #15. It flips pins those PRs added.
7. **#9 P10.** Its base is #6 + #7; retarget it once they land.
8. **#18 chat-read follow-up.** Its base is #7; retarget it once #7 lands.
9. **#16 recurring course line.** Land it **only after #8 is deployed**. Its copy describes the 0232 generator.

Expected textual conflicts: `REGISTRY.md`, `harness.sh`, the `"test"` chain in `app/package.json`, `rpc-skew.ts` PENDING_DEPLOY, and the a11y baseline. Resolve them by union. Before each commit, the marker grep must print 0.

## Deploy additions (deploy letter (b) lists 0203–0228)

Migrations: 0232 · 0233 · 0234 · 0235 · 0236 · 0237 · 0238 · 0239. Push them in number order after their PRs land.

PENDING_DEPLOY entries to delete once they are live:
- `ops_prerun_cases` and `ops_open_incidents` (#10)
- `register_push_token` (#12)

Afterwards, seat at least one operator at `incident_opened` (#10), and one at the recurring-escalation class (#14).

The client build ships **after** the push. #7's chat read needs `chat_mark_read_to` to be live.

## Letters (Sean's rulings, each written up in its PR)

| PR | question |
|---|---|
| #10 F2 | A runner whose run hit the 3-hour ceiling with only one handoff stamp stays locked out, and no door exists. Options: an L2/L3 door, or a predicate that requires both stamps. |
| #10 F5 | Should an operator be able to switch off SOS incident pushes? |
| #8 | Retired-course notice copy (「점검 중 … 이번 주」 is untrue for a retired course) and its 24 h re-tell cadence. |
| #12 | A failed sign-out release plus no later sign-in means A's pushes keep reaching the device. There are two closures, and both cost something. |
| #11 | `my_chat_unread` counts a forward-dated message as unread until its date (0225 §0e). Also: a production count of forward-dated rows. |
| #16 | Confirm the retired-course wording, both unpaused and paused. |
| #17 | `noti party insert` still allows booking-kind look-alikes from parties. Closing it needs a writer-provenance column (0238 §0e). |
| #20 | Image share on Android silently does nothing. Options: a file share, or an explicit failure. |
| #9 | Pick an own-bubble colour variant ⓪/①/② in `docs/labs/chat-own-bubble-lab.html`. |

## Still open (not built)

- **Codex R1** over `d0b6b6c..0ee30fa`, plus every cloud PR: no Codex verdict exists. `docs/reviews/2026-09-26-r1-claude-executing-review.md` is an executing-reviewer stand-in only.
- **F7 nav-back** (onboard, card-link). It waits for #2, which owns both onboards.
- **`fetchRunStandings` error check** (#19 finding 1). Building as `cloud/run-standings-error`.
- **Device smoke tests.** Every PR carries its own list. Nothing was seen on a simulator.
