# Codex adversarial verdicts — 0225–0227 (4fc8514..d0b6b6c) and the client wave (597f4c1..d0b6b6c, eleven slices)

Runs: 2026-09-25 21:44–21:51 KST · plugin `adversarial-review --wait` from detached exports at `d0b6b6c` (server-only, base 4fc8514;
client-only, base 597f4c1). Streams split (`scratchpad/codex-review/mig20-{srv,cli}.*`). Detection both runs: `FINDINGS: [0-9]+` → 1 ·
verdict VALUE → 1 · `usage limit` → 0 · exit 0. This client run supersedes the 19:35 WALLED client run.

## Server — REJECT · FINDINGS: 2 (0225 drew no finding; Codex confirmed 0227's minting body equals 0226's apart from isolation)

| # | sev | finding | routing |
|---|---|---|---|
| s1 | high | 0227:323-345 — a series that fails every tick is recorded and warned, the tick succeeds, and nothing ever escalates: the owner silently loses recurring bookings while cron reports success | **be/sweep-honesty-route-gate** (already re-declaring `generate_recurring_bookings` as 0231 — one owner per function): a deduplicated ops escalation for repeated/aged failures, isolated from minting, recovery resets the episode; owner-facing copy stays Sean's letter |
| s2 | med | 0226:732-744 — `_unsettled_charge_through` asks whether a payment existed before the notice and is debt NOW, not whether it was debt THEN; an existing pending payment that crosses the one-hour threshold after the old debt cleared suppresses the genuinely new pause for up to 24 h | same builder: track debt-episode transitions explicitly; regression for the existing-payment transition |

## Client — REJECT · FINDINGS: 3

| # | sev | finding | routing |
|---|---|---|---|
| c1 | high | `chat.tsx:193-198` — MEASURED: hold message 1 + a realtime-only 102, fetch 102–201 → `snapshotGap` is null because 102 is held, the ack advances past 2–101 which were never loaded | **fix/client-review-4**: track contiguous FETCHED coverage apart from realtime arrivals; advance the cursor only over verified coverage; the reconnect sequence as a regression |
| c2 | med | `api.ts:4223-4226` — MEASURED: after a delayed skew error from `chat_mark_read_to`, the wrapper calls 0212's `chat_mark_read` (writes now()) — messages arriving after the fetch are acknowledged unseen, and leaving the screen does not cancel it | **fix/client-review-4**: on a missing cursor RPC, acknowledge NOTHING (unread stays unread until the server can take a cursor) — this reverses the chat builder's deliberate fallback; Codex's reading is the honest one |
| c3 | med | `run.tsx:326-328` — a failed `fetchReturnSeal` resolves the ended-check to false and is cached; an ended-but-active booking can then be started again (start_run_tx accepts active rows idempotently), re-recording and re-sending 「러닝 시작」 | **fix/client-review-4**: unknown ≠ not-ended; block start/resume with 다시 시도; route ended bookings to return-seal first |

## Codex output (verbatim)

### Server
```
# Codex Adversarial Review

Target: branch diff against 4fc8514
Verdict: needs-attention

Do not ship yet: persistent generation failures remain unattended, and the debt-episode predicate can suppress a new pause. Static review only; the read-only sandbox prevents running the harness. The normalized 0227 minting body matches 0226 apart from isolation and failure recording.
FINDINGS: 2
VERDICT: REJECT

Findings:
- [high] Persistent generation failures never trigger intervention (supabase/migrations/0227_recurring_row_isolation.sql:323-345)
  READ: The handler converts every series failure into a warning and a journal upsert, then returns successfully. No automated reader or escalation for recurring_generation_failures ships. A persistently failing series therefore loses recurring bookings indefinitely while cron reports success; the owner receives neither bookings nor a failure notice. Suite 258 verifies recording and retries, but not intervention after repeated failures.
  Recommendation: Add a monitored, deduplicated escalation for repeated or aged failures, isolated from minting. Test that persistent failure alerts an operator, healthy series continue, and recovery resets the escalation episode.
- [medium] Payment creation time does not identify a debt episode (supabase/migrations/0226_strand_sweep_fixes.sql:732-744)
  READ: _unsettled_charge_through tests whether a payment existed before the notice and is debt NOW, not whether it was debt when that notice was sent. For example, A is failed and B is recently dispatched pending when the notice lands. A is paid, clearing all qualifying debt; B later crosses the one-hour pending threshold before the next generator tick. B's earlier created_at makes this helper return true, suppressing the genuinely new pause for up to 24 hours. Suite 257 C2 only covers a newly inserted payment after recovery, so it misses this existing-payment transition.
  Recommendation: Track debt episode transitions explicitly instead of inferring them from payment creation timestamps. Add a regression where an existing non-debt pending payment becomes debt after the previous debt clears, without an intervening generated booking.

Next steps:
- Fix escalation and episode tracking, then run the SQL harness and edge tests in a writable sandbox.
exit=0
```

### Client
```
# Codex Adversarial Review

Target: branch diff against 597f4c1
Verdict: needs-attention

Do not ship yet: unseen chat messages can still be acknowledged, and a failed run-end check permits recording an already-ended run. MEASURED: TypeScript, a11y and RPC checks passed. npm test was blocked by unavailable esbuild and restricted npm access.

Findings:
- [high] Realtime overlap can conceal an unread gap (app/app/chat.tsx:193-198)
  MEASURED using the actual compiled helpers: hold fetched message 1 and realtime-only message 102, then fetch messages 102–201. snapshotGap returns null because 102 already exists in held history; newestPeerMessageId selects 201. Messages 2–101 were never loaded, but the new acknowledgement advances past all of them. A reconnect followed by a burst can therefore hide messages and falsely mark them read.
  Recommendation: Track contiguous fetched coverage separately from realtime arrivals. Require overlap with that verified coverage before advancing the read cursor; add this reconnect sequence as a regression test.
- [medium] Legacy fallback still acknowledges messages beyond the rendered cursor (app/src/lib/api.ts:4223-4226)
  MEASURED with the actual wrapper and a deferred mocked RPC: after chat_mark_read_to returns a delayed skew error, the wrapper invokes chat_mark_read using the original fallback boolean. That legacy RPC writes now(), ignoring upToMessageId. Messages arriving after the fetch are acknowledged unseen; leaving or backgrounding the screen while the first request is pending does not cancel the fallback. The delay is not bounded to one render.
  Recommendation: On missing cursor RPC, skip acknowledgement rather than calling the now()-based writer. Preserve unread state until a cursor-capable server is available.
- [medium] Failed end-state reads permanently authorize resuming an ended run (app/app/runner/run.tsx:326-328)
  READ: fetchReturnSeal failure resolves endedCheck to false, and every subsequent start reuses that cached result. For an ended booking still active while awaiting return seals, a transient read failure lets startRunServer succeed: start_run_tx accepts active rows idempotently without checking run_ended_at. The client then sets running=true and records again instead of opening the return ceremony; the edge also sends another 러닝 시작 notification.
  Recommendation: Represent failed end-state reads as unknown, block start/resume, and render 다시 시도 that refetches the state. Route ended bookings to return-seal before enabling tracking.

Next steps:
- Fix the three failure paths and add regression tests covering reconnect gaps, delayed skew responses, and failed end-state reads.
- Rerun npm test where esbuild is available.
- FINDINGS: 3
VERDICT: REJECT
exit=0
```
