# Codex adversarial review — 0176 wiring · 0178 · 0179 (+ edge and client), diff `b8844d9..3681e73`

Run 2026-09-18 03:12 KST through the Codex plugin (`codex-companion.mjs adversarial-review --wait --base b8844d9
"<house laws + attack list>"`) from a DETACHED worktree at `3681e73`, so the diff is exactly the
three landings and their wiring. Streams split; stderr carries the reviewer's completion lines; **0**
`usage limit` hits. Detector note: the reviewer wrote the closing lines as a bullet (`- FINDINGS: 1`),
so `^FINDINGS: [0-9]+` read 0 while the verdict-value match read 1 — anchor the digit detector on the
word, not the line start (`FINDINGS: [0-9]+` anywhere) next time.

## Verdict (reviewer's message, verbatim)

> Verdict: needs-attention
> Fix booking replay before shipping. All 33 targeted edge tests passed; the SQL harness was not rerun.
>
> - [medium] Resolve existing request keys before creation-only state gates
>   (supabase/functions/create-booking-hold/handler.ts:311-315)
>   Replay is reached only through this RPC, after the route, debt, and card gates. If creation commits
>   but its response is lost, suspending the route, activating the debt lock, or enabling charging before
>   retry makes the identical request return 409 instead of its existing booking. Reproduced each case
>   against the handler with FakeDb: one booking remained matching, and the retry never reached SQL. The
>   client then clears bookingId and displays booking failure (app/app/owner/request.tsx:589–596), while
>   the live booking can still be accepted.
>   Recommendation: After authentication and ownership checks, resolve and validate an existing
>   owner-scoped request key before applying creation-only gates. Return its booking without another
>   write. Add lost-response retry tests that change route status, debt eligibility, and charging state
>   between calls.
>
> FINDINGS: 1
> VERDICT: APPROVE-WITH-FIXES

## Disposition
- The finding is real and EXECUTED (FakeDb reproduction), and it is the attack-INACTION shape applied to
  a lost response: the idempotency key protects the write but not the person, because the gates that
  sit in front of the replay can change between the two attempts. 0176 and 0178 drew no finding.
- Routed to the slice's author (peer session b6) as a fix ahead of 0180: resolve the owner-scoped key
  right after the party check, return the existing booking (`unchanged:true`) before any creation-only
  gate, with the three lost-response tests the reviewer names, plus a 210 pin if the SQL side moves.
- Nothing deployed; the deploy letter (queue item 1) is unaffected in order, but this fix should land
  before the letter is said.
