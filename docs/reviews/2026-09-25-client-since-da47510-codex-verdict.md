# Codex adversarial verdict — CLIENT half, everything since da47510 (incl. fix/client-review-1 and 0220's client part)

Run: 2026-09-25 16:36–16:40 KST · plugin `adversarial-review --wait --base da47510` from a detached export at `b12c68f` with `supabase/`
reverted to the base (client-only: 140 files). Streams split (`scratchpad/codex-review/mig17-cli.{out,err}`).
Detection: `FINDINGS: [0-9]+` → 1 · verdict VALUE → 1 · `usage limit` → 0 · exit 0. tsc + three source gates MEASURED green by the
reviewer; `npm test` could not run in its sandbox (no esbuild, no network) — the chain's health stands on the landing logs, not on this run.
This replaces the 02:3x WALLED run (`…-codex-WALLED.md`); its four captured observations were built as fix/client-review-1 and re-reviewed here.

**VERDICT: REJECT · FINDINGS: 4** (1 high · 3 medium)

## Routing (announcer, 16:41 KST)

| # | sev | finding | goes to |
|---|---|---|---|
| 1 | high | `app/app/chat.tsx:395-406` — the foreground AND focus callbacks call `recordRead` immediately on the previously-ready screen, before the poll refetches; after a suspension the server may hold messages the screen has not shown, and `chat_mark_read` records server `now()`, so unseen messages become 「읽음」 even if the fetch then fails | **fix/chat-read-cursor** (+ **0223** if the RPC needs a cursor column): refresh successfully first, then acknowledge; acknowledge only up to the newest peer message id actually displayed |
| 2 | med | `app/src/lib/api.ts:4063-4068` — timestamp-only pagination: 101 messages sharing a timestamp → the newest 100 load and the older query returns zero (strict predicate, no id tie-breaker); `olderCursor` picks the smallest ID while the query orders by timestamp | **fix/chat-read-cursor**: deterministic `(created_at, id)` ordering + composite cursor through fetch, olderCursor and the gap fill; boundary-tie and inverted-id pins |
| 3 | med | `app/app/ops/returns/index.tsx:60-62` — an EMPTY successful response assigns `deadline = null` and `strandDeadlineNote` then says strand alerts are switched OFF; `ops_stranded_returns` returns the setting only on matching rows, so an enabled threshold with no stranded bookings prints a fabricated configuration claim | **fix/client-review-2**: represent 「unobserved」 apart from a server null; omit the claim on empty results (or read the flag independently) |
| 4 | med | `app/scripts/check-a11y-roles.mjs:154-162` — MEASURED: removing a role in owner/schedule.tsx exits 1; adding a role to another bare Pressable in the same file makes the same regression exit 0 (the per-file ledger's named blind spot) | **fix/client-review-2**: per-element fingerprints (file + nearest named ancestor + ordinal), shrink-only, with the balanced-mutation regression test |

## Codex output (verbatim)

```
# Codex Adversarial Review

Target: branch diff against da47510
Verdict: needs-attention

Do not ship yet: chat can acknowledge unseen messages and omit messages at page boundaries. Reviewed actual HEAD against da47510, including later client fixes. MEASURED: tsc and all three static gates exited 0. npm test exited 1 before assertions (esbuild registry ENOTFOUND; whole-output counts: 0 PASS, 0 FAIL). The edge-error drift test passed 45 assertions and correctly failed after an in-memory new HttpError mutation.

Findings:
- [high] Foregrounding chat marks messages read before fetching them (app/app/chat.tsx:395-406)
  READ: The foreground callback calls recordRead immediately using the previously ready screen. After suspension, messages can exist on the server but remain absent locally until polling succeeds. chat_mark_read records server now(), so these unseen messages become read—even if the subsequent fetch fails. The navigation-focus callback has the same ordering.
  Recommendation: Refresh successfully before acknowledging on focus, and extend the RPC to acknowledge only a server-validated message cursor actually received and displayed. Do not advance the read position through missing pages.
- [medium] Timestamp-only pagination permanently excludes boundary siblings (app/src/lib/api.ts:4063-4068)
  MEASURED: With 101 messages sharing a timestamp, the newest 100 load and the older query returns zero, leaving one message unreachable. The strict timestamp predicate has no ID tie-breaker. Separately, olderCursor chooses the smallest ID rather than the oldest timestamp, although the query orders by timestamp; concurrent transactions need not preserve that ordering.
  Recommendation: Use deterministic ordering and a matching composite (created_at, id) cursor throughout fetching, olderCursor, and gap filling. Add boundary-tie and inverted-ID/timestamp tests.
- [medium] Empty returns queue falsely claims strand alerts are disabled (app/app/ops/returns/index.tsx:60-62)
  READ: An empty successful response assigns deadline=null. The ready-state renderer passes that to strandDeadlineNote, which explicitly says strand alerts are switched off. ops_stranded_returns returns the setting only on matching rows, so an enabled threshold with no stranded bookings produces the same empty response. Operators receive a fabricated configuration claim.
  Recommendation: Represent an unobserved threshold separately from a server-returned null. Omit the configuration claim for empty results, or fetch configuration independently.
- [medium] Accessibility gate allows a fix to conceal a regression (app/scripts/check-a11y-roles.mjs:154-162)
  MEASURED: In-memory mutation removing the booking action's role in owner/schedule.tsx made the gate exit 1. Adding a role to another bare Pressable in that file made the same regression exit 0. Per-file counts preserve the total while allowing accessible controls to regress. Comment-quoted Pressables were correctly ignored, and injected unreadable-file errors failed loudly.
  Recommendation: Track individual grandfathered elements using stable AST fingerprints or explicit reviewed exemptions. Reject newly unroled elements independently of fixes elsewhere, and retain this balanced-mutation regression test.

Next steps:
- Fix the four findings and rerun the full suite with esbuild available; this run did not establish test-suite health.
- FINDINGS: 4
VERDICT: REJECT
exit=0
```
