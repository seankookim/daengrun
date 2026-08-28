You are a cold reviewer. You have no author reasoning to lean on. Read the code, not the comments —
in this repo a comment quoting removed code has repeatedly defeated greps in both directions, and
`prosrc` carries our own prose inside it. Cite executable lines only.

# System

daengrun (도그스하이) — a Korean dog-running marketplace. React Native/Expo client, Supabase
(Postgres + edge functions). Pre-launch, Banpo pilot. All three migrations below are LIVE in
production (production is at 0152, nothing pending).

Money state: `ops_flags.payments_live_since` is NULL and `card_registration_live_since` is NULL, so
no card is charged today. **But ledger rows, runner earnings figures, settlement quotes and refund
states are all written and displayed regardless of those flags.** Do not treat "charging is off" as
"this path is inert" — say explicitly, per finding, whether it moves a NUMBER a human sees today or
only after a flag flip.

# The slice under review — the club pack run-end freeze and the money it prices

Read these as ONE chain, in order. This repo uses `create or replace` heavily, so a later file
silently replaces an earlier function body, and reading one file alone misdescribes who writes a
value and who spends it.

  supabase/migrations/0144_club_pack_run_end.sql
      creates the freeze: `club_end_pack_runs`, `_club_derive_run_km`. Writes
      `bookings.run_ended_at` and `runs.{ended_at, actual_km, duration_sec, end_reason}`.
  supabase/migrations/0147_board_run_frozen_flag.sql
      recreates `_club_delegation_board_impl` purely to project the freeze to the client
      as `runEnded`.
  supabase/migrations/0152_unmeasured_is_not_zero_km.sql
      rewrites `club_incident_settle_quote` and `club_incident_settle` around
      `runs.actual_km`, replacing an earlier `coalesce(actual_km, 0)`.

Also read, because they consume or produce the same fields:
  supabase/functions/settle-run/handler.ts        (takes km / end_reason / duration / condition_note)
  supabase/migrations/0121_*.sql                  (the settle quote this replaces; the ratio spend)

The client half — a server-only review misses the pairing, so review these too:
  app/src/lib/api.ts        (`runEnded` on the delegation board; the `club_incident_settle_quote`
                             and `club_incident_settle` wrappers)
  app/app/club/run/[sid].tsx       (the `runEnded` branch that suppresses the 조기 종료 reason picker)
  app/app/club/case/[cid].tsx      (fetches the settle outcomes together)
  app/app/owner/pay.tsx            (reads the `refund_pending` effect)

# House laws — violations are findings

1. **Unknown is not zero, and loading is not zero.** A NULL distance must never render or price as
   `0km`. This exact defect was found live in this repo one day ago: a booking with `actual_km`
   NULL quoted 「실측 0km」 and multiplied the runner's distance pay and addon fare by that zero.
   0152 exists to fix it. **Check that the fix is complete, not that it is present.**
2. **A finding's sentence is the property; the site someone cited is one place it is observable.**
   If NULL-km must not be priced as zero, enumerate EVERY site that reads `actual_km`,
   `duration_sec` or a derived distance — not only the ones 0152 touched.
3. Party gate before state gate. Flat whitelisted returns.
4. Failures are shown as failures; no silent catch producing a happy UI.
5. A SECURITY DEFINER function must set `search_path` in the BODY. A `create or replace` in a file
   that did not first define the function, without a same-file ACL, is a latent PUBLIC-EXECUTE hole.
6. Widening what a value can MEAN breaks correct callers with no edit to the caller.

# What to hunt, in priority order

A. **The freeze's completeness.** After the host's single 러닝 종료 tap, which fields are frozen and
   which are still writable? `settle-run` takes km/end_reason/duration/condition_note from the
   server row when frozen — enumerate every path by which a LATER write (a runner's early-stop
   reason, a dog-condition note, a retried settle, a late GPS flush) can still change a value that
   has already been priced, or be silently discarded after the user was told it was recorded.

B. **Partial freeze / inaction.** What if the host never taps? What if `club_end_pack_runs` writes
   some rows and fails midway — is it atomic across the pack? What is true of a runner whose pair
   was frozen while they were mid-run, and of one whose pair was NOT frozen because the host
   abandoned the session? Attack the state nobody transitions out of, not only the transitions.

C. **`_club_derive_run_km`'s arithmetic and its NULL behaviour.** What does it return when there is
   no GPS, one point, points with a time gap, or a device that never reported? Does any caller
   coalesce that NULL to 0 before pricing? Trace the value all the way into
   `club_incident_settle_quote` and into runner pay.

D. **0152's refusal is IN-BAND, not a raise** (the client fetches several settle outcomes together).
   An in-band refusal is a widened return meaning. Enumerate every consumer of the quote and say,
   per consumer, what it does when the refusal arrives — and specifically whether any consumer
   treats an absent or unrecognised reason as a valid priced quote. An absent reason must fail
   CLOSED.

E. **The client's `runEnded` gate.** `runEnded` is projected by 0147. If it is absent, stale, or
   `undefined` on an older server (deploy skew), what does `club/run/[sid].tsx` do — suppress the
   picker, or offer a picker whose input the server will discard? Both directions are defects and
   they fail in opposite ways; say which one this code does.

F. **Definer/ACL/search_path hygiene** across all three files, per law 5.

# What I do NOT want

- Style, naming or formatting opinions.
- Findings whose only evidence is a comment.
- Speculation you did not check in source. Put unsettled things under OPEN QUESTIONS.

# Output format

Per finding: one-line title · severity CRITICAL/HIGH/MEDIUM/LOW · `file:line` citations of
executable lines · the concrete failure scenario (state -> the wrong number or wrong screen) ·
whether it moves a number a human sees TODAY or only after a flag flip · the smallest fix.

Then OPEN QUESTIONS.

End your response with exactly these two lines, in this order and nothing after them:

FINDINGS: <n>
VERDICT: <verdict>

where <n> is the integer count of findings you reported, and <verdict> is whichever one of these
three is right: approve; approve-with-fixes; reject. Write it in capitals.
