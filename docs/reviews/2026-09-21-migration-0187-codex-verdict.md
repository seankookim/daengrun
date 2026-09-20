# Codex adversarial review — 0187 notification prefs (+ suite 218, client screen), diff `b1270c7..a5635a9`

Run 2026-09-21 02:30 KST through the Codex plugin (`adversarial-review --wait --base b1270c7`) from a DETACHED worktree at `a5635a9`. Streams split; completion lines present; **0** `usage limit` hits; `FINDINGS: [0-9]+` = 1, verdict-value = 1. The 26 client tests and the mocked loading/401 rollback checks were executed by the reviewer; SQL reviewed statically (executed at landing: harness 1314/0).

## Verdict (reviewer's message, verbatim)

> # Codex Adversarial Review
> 
> Target: branch diff against b1270c7
> Verdict: needs-attention
> 
> Do not ship: booking preferences suppress real SOS alerts, and tombstoned accounts can still receive pushes. All 26 client tests and mocked loading/401 rollback checks passed; SQL tests were not run in the read-only sandbox.
> 
> Findings:
> - [high] Booking opt-out silences SOS and accident alerts (supabase/migrations/0187_notification_prefs.sql:134-140)
>   The mapper classifies every non-chat booking notification as disableable. However, sendSOS writes kind='booking', title='SOS' (app/src/lib/api.ts:3548–3551); accident reports and run-stop requests also use booking (3741–3744, 3811–3814). With booking=false, notify_push suppresses these emergency pushes. Suite 218 tests synthetic safety/system kinds, missing the actual client writers. Simply changing the writers to safety would also fail the current booking-only INSERT policy (0114_party_membership_active.sql:273–281).
>   Recommendation: Classify existing SOS, accident, and stop-request payloads as always-on before reading preferences, preserving compatibility with deployed clients. Add behavioral tests using those writers' actual payloads with all preferences false.
> - [high] Token cleanup does not prevent pushes to tombstoned accounts (supabase/migrations/0187_notification_prefs.sql:185-187)
>   The replacement trigger sends whenever a token exists, without checking profiles.deleted_at. Deletion removes tokens once, but auth deletion can fail after tombstoning while leaving the account signed in (supabase/functions/delete-account/handler.ts:168–182). On restart, registerPushToken can recreate the token (app/src/lib/push.ts:194–201): its RLS policy checks only ownership, and the profile survives. Deletion retries skip cleanup for existing tombstones (0115_account_deletion.sql:227–234), so subsequent notifications can keep pushing to the deleted account.
>   Recommendation: Require a non-tombstoned recipient at the send boundary. Add a test that tombstones an account, restores its token, and verifies zero pushes—including safety/system—with a live-profile control.
> 
> Next steps:
> - Fix both send-path guards and run suite 218 with the real emergency payloads and restored-token tombstone cases.
> - FINDINGS: 2
> VERDICT: REJECT

## Disposition
- **REJECT/2, both HIGH and both real-shaped.** (1) The client writes SOS (`api.ts:3548`), accident reports and run-stop requests with `kind='booking'` (0114's INSERT policy only admits `booking` from a party), so the mapper's 「every non-chat booking notification is disableable」 silences the one push that must never be silenced; suite 218 tested synthetic `safety`/`system` kinds, not the real writers' payloads. (2) The send boundary checks only that a token exists; a tombstoned account whose auth deletion failed can re-register a token on restart and keep receiving pushes.
- Fix shape: correct-forward **0189 + suite 220** (0188/219 are claimed by the run-end ceremony builder): classify the existing SOS / accident / stop-request payloads as always-on by their title family BEFORE the prefs read (compatibility with deployed clients — do not change the writers' kind), and require `profiles.deleted_at is null` at the send boundary; pins with the writers' REAL payloads under all-false prefs, and a tombstone-with-restored-token case with a live-profile control. Routed to the 0187 builder.
- 🔴 The deploy letter must include 0189 (0187 alone ships the SOS silencing); the queue says so.
